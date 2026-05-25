extends Node3D
## Candy Crush + Tetris — primitive auto-falling implementation with special balls.
##
## Tetromino pieces made of multicoloured candy balls fall automatically down a
## grid. The game is played on a flat playfield, but everything is rendered in a
## true 3D scene (real sphere meshes, lighting and shadows).
##
## Special Candy Crush-style balls spawn randomly and trigger effects when a
## piece locks into the settled grid:
##   BOMB      — clears all cells within a Chebyshev radius of 2
##   RAINBOW   — clears every settled ball whose colour matches any ball in the
##               locked piece
##   FREEZE    — slows the fall speed for several seconds
##   LIGHTNING — clears the entire column the ball lands in
##
## When [member auto_play] is enabled (the default) a lightweight heuristic
## steers each piece toward the column that keeps the stack flat and clears
## rows. With it disabled, pieces simply drop down the centre.

# --- Board configuration -----------------------------------------------------
const GRID_W := 8        # columns
const GRID_H := 16       # rows (row 0 = bottom)
const CELL := 1.0        # world units per cell
const FALL_INTERVAL := 0.30  # seconds between downward steps (normal speed)
const FALL_INTERVAL_FROZEN := 1.20  # slowed fall interval during freeze effect

## When true, pieces are automatically steered toward a good landing column.
@export var auto_play := true

## Probability (0–1) that any individual ball in a piece is a special ball.
@export var special_ball_chance := 0.15

## Duration in seconds of the freeze (slow-fall) effect.
@export var freeze_duration := 4.0

## Bomb effect radius in cells (Chebyshev / max-norm distance).
@export var bomb_radius := 2

# --- Ball type enum ----------------------------------------------------------
enum BallType { NORMAL, BOMB, RAINBOW, FREEZE, LIGHTNING }

# Candy palette (bright, saturated sweets).
const COLORS := [
	Color("ff4d6d"), # strawberry
	Color("ff922b"), # orange
	Color("ffd43b"), # lemon
	Color("51cf66"), # apple
	Color("4dabf7"), # blueberry
	Color("9775fa"), # grape
	Color("f783ac"), # bubblegum
]

# Tetromino shapes as cell offsets (x right, y up), each normalised so the
# minimum x and y are 0. Spawned upright (no rotation in this primitive build).
const SHAPES := [
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], # I
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], # O
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)], # T
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)], # S
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)], # Z
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)], # J
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)], # L
]

# Four-feature placement heuristic used by the auto-player. The weights are the
# genetic-algorithm-tuned values from Code My Road's "Tetris AI – The (Near)
# Perfect Player" (aggregate height, complete lines, holes, bumpiness).
# https://codemyroad.wordpress.com/2013/04/14/tetris-ai-the-near-perfect-player/
const W_HEIGHT := -0.51
const W_LINES := 0.76
const W_HOLES := -0.36
const W_BUMPY := -0.18

# --- Runtime state -----------------------------------------------------------
var _settled: Array = []          # _settled[row][col] -> MeshInstance3D or null
var _settled_types: Array = []    # _settled_types[row][col] -> BallType (mirrors _settled)
var _settled_colors: Array = []   # _settled_colors[row][col] -> Color (mirrors _settled)

var _piece_offsets: Array = []    # Array[Vector2i] shape offsets of active piece
var _piece_base := Vector2i.ZERO  # bottom-left anchor of the active piece
var _piece_nodes: Array = []      # Array[MeshInstance3D] parallel to _piece_offsets
var _piece_cells: Array = []      # cached absolute cells (= base + offsets)
var _piece_types: Array = []      # Array[BallType] parallel to _piece_offsets
var _piece_colors: Array = []     # Array[Color] parallel to _piece_offsets
var _target_x := 0                # auto-player's desired anchor column

var _fall_timer := 0.0
var _freeze_timer := 0.0          # > 0 when a freeze effect is active
var _anim_time := 0.0             # runs continuously for material animations

var _lines := 0
var _specials_triggered := 0      # HUD counter for special effects fired

var _ball_mesh: SphereMesh
var _lines_label: Label
var _freeze_label: Label          # shows "FROZEN!" while freeze is active


func _ready() -> void:
	randomize()
	_build_environment()
	_build_camera()
	_build_lights()
	_build_back_panel()
	_build_hud()
	_init_grid()
	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = 0.46
	_ball_mesh.height = 0.92
	_ball_mesh.radial_segments = 24
	_ball_mesh.rings = 12
	_spawn_piece()


func _process(delta: float) -> void:
	_anim_time += delta

	# Animate special-ball materials in the active piece.
	_animate_piece_materials()

	# Update freeze timer.
	if _freeze_timer > 0.0:
		_freeze_timer -= delta
		if _freeze_timer <= 0.0:
			_freeze_timer = 0.0
			_update_hud()

	var interval := FALL_INTERVAL_FROZEN if _freeze_timer > 0.0 else FALL_INTERVAL

	_fall_timer += delta
	if _fall_timer >= interval:
		_fall_timer -= interval
		_step()

	# Smoothly glide active balls toward their logical grid position.
	var speed := CELL / FALL_INTERVAL * 1.6
	for i in _piece_nodes.size():
		var node: MeshInstance3D = _piece_nodes[i]
		node.position = node.position.move_toward(_cell_to_world(_piece_cells[i]), speed * delta)


# --- Game loop ---------------------------------------------------------------
func _step() -> void:
	var dx := 0
	if auto_play and _piece_base.x != _target_x:
		dx = signi(_target_x - _piece_base.x)

	var down := _piece_base + Vector2i(0, -1)
	if dx != 0 and _placement_valid(down + Vector2i(dx, 0)):
		# Glide diagonally toward the target column while descending.
		_set_base(down + Vector2i(dx, 0))
	elif _placement_valid(down):
		_set_base(down)
	elif dx != 0 and _placement_valid(_piece_base + Vector2i(dx, 0)):
		# Can't descend yet, but can still shuffle toward the target.
		_set_base(_piece_base + Vector2i(dx, 0))
	else:
		_lock_piece()
		_clear_full_rows()
		_spawn_piece()


func _spawn_piece() -> void:
	var shape: Array = SHAPES[randi() % SHAPES.size()]
	var max_x := 0
	var max_y := 0
	for o in shape:
		max_x = max(max_x, o.x)
		max_y = max(max_y, o.y)

	_piece_offsets = shape
	# Centre the shape horizontally and drop it from the top row.
	_piece_base = Vector2i(int((GRID_W - (max_x + 1)) / 2.0), GRID_H - 1 - max_y)
	_target_x = _best_target_column() if auto_play else _piece_base.x

	_piece_nodes = []
	_piece_types = []
	_piece_colors = []
	for o in shape:
		var btype: BallType = _random_ball_type()
		var color: Color = COLORS[randi() % COLORS.size()]
		var ball := _make_ball(color, btype)
		# Start one cell higher so the piece glides into view.
		ball.position = _cell_to_world(_piece_base + o + Vector2i(0, 1))
		_piece_nodes.append(ball)
		_piece_types.append(btype)
		_piece_colors.append(color)
	_refresh_cells()

	# If the spawn space is occupied, the board has overflowed. Clear the
	# settled balls and keep this fresh piece so the demo restarts seamlessly.
	if not _is_valid(_piece_cells):
		_reset_board()


func _lock_piece() -> void:
	# Collect colors of all special balls in this piece for the rainbow effect.
	var piece_colors_set: Array = []
	for c in _piece_colors:
		if not piece_colors_set.has(c):
			piece_colors_set.append(c)

	for i in _piece_cells.size():
		var cell: Vector2i = _piece_cells[i]
		var node: MeshInstance3D = _piece_nodes[i]
		var btype: BallType = _piece_types[i]
		var bcolor: Color = _piece_colors[i]
		node.position = _cell_to_world(cell)
		if cell.y >= 0 and cell.y < GRID_H:
			_settled[cell.y][cell.x] = node
			_settled_types[cell.y][cell.x] = btype
			_settled_colors[cell.y][cell.x] = bcolor

	# Fire special effects for any special balls that landed.
	for i in _piece_cells.size():
		var cell: Vector2i = _piece_cells[i]
		var btype: BallType = _piece_types[i]
		if btype == BallType.BOMB:
			_effect_bomb(cell)
		elif btype == BallType.RAINBOW:
			_effect_rainbow(piece_colors_set)
		elif btype == BallType.FREEZE:
			_effect_freeze()
		elif btype == BallType.LIGHTNING:
			_effect_lightning(cell.x)

	_piece_nodes = []
	_piece_cells = []
	_piece_types = []
	_piece_colors = []


# --- Special ball effects ----------------------------------------------------

## BOMB: clears every settled cell within [member bomb_radius] (Chebyshev dist).
func _effect_bomb(center: Vector2i) -> void:
	_specials_triggered += 1
	for row in GRID_H:
		for col in GRID_W:
			if _settled[row][col] != null:
				var dist := maxi(absi(col - center.x), absi(row - center.y))
				if dist <= bomb_radius:
					_settled[row][col].queue_free()
					_settled[row][col] = null
					_settled_types[row][col] = BallType.NORMAL
					_settled_colors[row][col] = Color.BLACK
	_apply_gravity_to_settled()
	_update_hud()


## RAINBOW: clears every settled ball whose colour matches any colour in the
## locked piece (piece_colors is the set of distinct colours in the piece).
func _effect_rainbow(piece_colors: Array) -> void:
	_specials_triggered += 1
	for row in GRID_H:
		for col in GRID_W:
			if _settled[row][col] != null:
				if piece_colors.has(_settled_colors[row][col]):
					_settled[row][col].queue_free()
					_settled[row][col] = null
					_settled_types[row][col] = BallType.NORMAL
					_settled_colors[row][col] = Color.BLACK
	_apply_gravity_to_settled()
	_update_hud()


## FREEZE: activates the slow-fall effect for [member freeze_duration] seconds.
func _effect_freeze() -> void:
	_specials_triggered += 1
	_freeze_timer = freeze_duration
	_update_hud()


## LIGHTNING: clears every settled ball in the given column.
func _effect_lightning(col: int) -> void:
	_specials_triggered += 1
	for row in GRID_H:
		if _settled[row][col] != null:
			_settled[row][col].queue_free()
			_settled[row][col] = null
			_settled_types[row][col] = BallType.NORMAL
			_settled_colors[row][col] = Color.BLACK
	_apply_gravity_to_settled()
	_update_hud()


## Applies gravity to all settled balls: any ball that has empty space below it
## falls down until it lands on the bottom or on another settled ball.
## This is called after special effects (bomb, rainbow, lightning) clear cells,
## so that settled balls do not float in mid-air.
func _apply_gravity_to_settled() -> void:
	# Process columns independently — each ball in a column falls as far down as
	# it can without overlapping another settled ball.
	for col in GRID_W:
		# Scan from bottom (row 0) upward, compacting balls toward row 0.
		var write_row := 0  # next free row in this column
		for row in GRID_H:
			if _settled[row][col] != null:
				if row != write_row:
					# Move the ball from row → write_row.
					_settled[write_row][col] = _settled[row][col]
					_settled_types[write_row][col] = _settled_types[row][col]
					_settled_colors[write_row][col] = _settled_colors[row][col]
					_settled[row][col] = null
					_settled_types[row][col] = BallType.NORMAL
					_settled_colors[row][col] = Color.BLACK
					# Snap the mesh to its new world position.
					var node: MeshInstance3D = _settled[write_row][col]
					if node != null:
						node.position = _cell_to_world(Vector2i(col, write_row))
				write_row += 1


func _clear_full_rows() -> void:
	var row := 0
	while row < GRID_H:
		var full := true
		for col in GRID_W:
			if _settled[row][col] == null:
				full = false
				break
		if full:
			for col in GRID_W:
				_settled[row][col].queue_free()
				_settled[row][col] = null
				_settled_types[row][col] = BallType.NORMAL
				_settled_colors[row][col] = Color.BLACK
			# Shift every row above down by one.
			for r in range(row, GRID_H - 1):
				for col in GRID_W:
					var node: MeshInstance3D = _settled[r + 1][col]
					_settled[r][col] = node
					_settled_types[r][col] = _settled_types[r + 1][col]
					_settled_colors[r][col] = _settled_colors[r + 1][col]
					if node != null:
						node.position = _cell_to_world(Vector2i(col, r))
			for col in GRID_W:
				_settled[GRID_H - 1][col] = null
				_settled_types[GRID_H - 1][col] = BallType.NORMAL
				_settled_colors[GRID_H - 1][col] = Color.BLACK
			_lines += 1
			_update_hud()
			# Re-check the same row index (it now holds the row that fell down).
		else:
			row += 1


## Empties the settled board after an overflow. The active piece is left
## untouched so play continues immediately on the cleared board.
func _reset_board() -> void:
	for row in GRID_H:
		for col in GRID_W:
			if _settled[row][col] != null:
				_settled[row][col].queue_free()
				_settled[row][col] = null
			_settled_types[row][col] = BallType.NORMAL
			_settled_colors[row][col] = Color.BLACK
	_lines = 0
	_update_hud()


# --- Auto-player -------------------------------------------------------------
## Returns the anchor column that yields the best board score for the current
## shape, dropped straight down (no rotation in this primitive build).
func _best_target_column() -> int:
	var max_x := 0
	for o in _piece_offsets:
		max_x = max(max_x, o.x)

	var best_x := _piece_base.x
	var best_score := -INF
	for base_x in range(0, GRID_W - max_x):
		var base_y := _drop_row(base_x)
		if base_y == GRID_H:  # column blocked all the way up
			continue
		var score := _score_placement(Vector2i(base_x, base_y))
		if score > best_score:
			best_score = score
			best_x = base_x
	return best_x


## Lowest valid anchor row for the active shape dropped at [param base_x].
## Returns GRID_H when no valid placement exists.
func _drop_row(base_x: int) -> int:
	var by := GRID_H
	while by > 0 and _placement_valid_at(base_x, by - 1):
		by -= 1
	return by if _placement_valid_at(base_x, by) else GRID_H


func _score_placement(base: Vector2i) -> float:
	# Build an occupancy snapshot with the candidate piece added.
	var occ: Array = []
	for row in GRID_H:
		var line: Array = []
		for col in GRID_W:
			line.append(_settled[row][col] != null)
		occ.append(line)
	for o in _piece_offsets:
		var c: Vector2i = base + o
		if c.y >= 0 and c.y < GRID_H:
			occ[c.y][c.x] = true

	var heights: Array = []
	var holes := 0
	for col in GRID_W:
		var top := -1
		for row in range(GRID_H - 1, -1, -1):
			if occ[row][col]:
				top = row
				break
		heights.append(top + 1)
		if top >= 0:
			for row in range(top):
				if not occ[row][col]:
					holes += 1

	var aggregate := 0
	for h in heights:
		aggregate += h
	var bumpiness := 0
	for col in range(GRID_W - 1):
		bumpiness += abs(heights[col] - heights[col + 1])
	var lines := 0
	for row in GRID_H:
		var full := true
		for col in GRID_W:
			if not occ[row][col]:
				full = false
				break
		if full:
			lines += 1

	return W_HEIGHT * aggregate + W_LINES * lines + W_HOLES * holes + W_BUMPY * bumpiness


# --- Helpers -----------------------------------------------------------------
func _init_grid() -> void:
	_settled = []
	_settled_types = []
	_settled_colors = []
	for row in GRID_H:
		var line: Array = []
		var type_line: Array = []
		var color_line: Array = []
		for col in GRID_W:
			line.append(null)
			type_line.append(BallType.NORMAL)
			color_line.append(Color.BLACK)
		_settled.append(line)
		_settled_types.append(type_line)
		_settled_colors.append(color_line)


func _set_base(base: Vector2i) -> void:
	_piece_base = base
	_refresh_cells()


func _refresh_cells() -> void:
	_piece_cells = []
	for o in _piece_offsets:
		_piece_cells.append(_piece_base + o)


func _placement_valid(base: Vector2i) -> bool:
	return _placement_valid_at(base.x, base.y)


func _placement_valid_at(base_x: int, base_y: int) -> bool:
	for o in _piece_offsets:
		var cell: Vector2i = Vector2i(base_x, base_y) + o
		if cell.x < 0 or cell.x >= GRID_W or cell.y < 0:
			return false
		if cell.y < GRID_H and _settled[cell.y][cell.x] != null:
			return false
	return true


func _is_valid(cells: Array) -> bool:
	for cell in cells:
		if cell.x < 0 or cell.x >= GRID_W or cell.y < 0:
			return false
		if cell.y < GRID_H and _settled[cell.y][cell.x] != null:
			return false
	return true


func _cell_to_world(cell: Vector2i) -> Vector3:
	# Centre the board on the world origin.
	var x := (cell.x - (GRID_W - 1) / 2.0) * CELL
	var y := (cell.y - (GRID_H - 1) / 2.0) * CELL
	return Vector3(x, y, 0.0)


## Returns a randomly chosen BallType, respecting [member special_ball_chance].
func _random_ball_type() -> BallType:
	if randf() >= special_ball_chance:
		return BallType.NORMAL
	# Equal probability among the four special types.
	var r := randi() % 4
	match r:
		0: return BallType.BOMB
		1: return BallType.RAINBOW
		2: return BallType.FREEZE
		_: return BallType.LIGHTNING


func _make_ball(color: Color, btype: BallType = BallType.NORMAL) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _ball_mesh
	mi.material_override = _make_material(color, btype)
	add_child(mi)
	return mi


func _make_material(color: Color, btype: BallType) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.22
	mat.rim_enabled = true
	mat.rim = 0.5
	mat.emission_enabled = true

	match btype:
		BallType.NORMAL:
			mat.albedo_color = color
			mat.metallic = 0.0
			mat.roughness = 0.22
			mat.emission = color
			mat.emission_energy_multiplier = 0.22

		BallType.BOMB:
			# Dark sphere with a hot red-orange glow — looks dangerous.
			mat.albedo_color = Color(0.12, 0.08, 0.08)
			mat.metallic = 0.4
			mat.roughness = 0.55
			mat.emission = Color("ff4500")
			mat.emission_energy_multiplier = 2.0

		BallType.RAINBOW:
			# Bright white with intense multi-colour emission (starts white,
			# animated to cycle colours in _process).
			mat.albedo_color = Color(1.0, 1.0, 1.0)
			mat.metallic = 0.0
			mat.roughness = 0.15
			mat.emission = Color(1.0, 1.0, 1.0)
			mat.emission_energy_multiplier = 1.5

		BallType.FREEZE:
			# Icy blue tint, frosted surface.
			mat.albedo_color = Color(0.55, 0.85, 1.0)
			mat.metallic = 0.1
			mat.roughness = 0.85
			mat.emission = Color("00cfff")
			mat.emission_energy_multiplier = 1.0

		BallType.LIGHTNING:
			# Bright yellow with extreme emission — electric.
			mat.albedo_color = Color(1.0, 1.0, 0.1)
			mat.metallic = 0.0
			mat.roughness = 0.10
			mat.emission = Color(1.0, 1.0, 0.0)
			mat.emission_energy_multiplier = 3.0

	return mat


## Animate the materials of special balls in the active piece each frame.
func _animate_piece_materials() -> void:
	for i in _piece_nodes.size():
		var btype: BallType = _piece_types[i]
		if btype == BallType.NORMAL:
			continue
		var node: MeshInstance3D = _piece_nodes[i]
		var mat: StandardMaterial3D = node.material_override as StandardMaterial3D
		if mat == null:
			continue

		match btype:
			BallType.BOMB:
				# Pulse emission between dim and bright.
				var pulse := (sin(_anim_time * 6.0) + 1.0) * 0.5  # 0..1
				mat.emission_energy_multiplier = lerp(1.0, 4.0, pulse)

			BallType.RAINBOW:
				# Cycle hue continuously.
				var hue := fmod(_anim_time * 0.4, 1.0)
				var rainbow := Color.from_hsv(hue, 1.0, 1.0)
				mat.emission = rainbow
				mat.albedo_color = rainbow.lightened(0.3)
				mat.emission_energy_multiplier = 1.5

			BallType.LIGHTNING:
				# Fast flicker.
				var flicker := (sin(_anim_time * 20.0) + 1.0) * 0.5
				mat.emission_energy_multiplier = lerp(2.0, 5.0, flicker)


# --- Scene construction ------------------------------------------------------
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.06, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.42, 0.6)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = GRID_H + 2.0
	cam.position = Vector3(0, 0, 30)
	cam.near = 0.1
	cam.far = 100.0
	add_child(cam)
	cam.make_current()


func _build_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 130, 0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)


func _build_back_panel() -> void:
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(GRID_W + 0.6, GRID_H + 0.6, 0.4)
	panel.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.10, 0.18)
	mat.roughness = 0.9
	panel.material_override = mat
	panel.position = Vector3(0, 0, -0.7)
	add_child(panel)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var title := Label.new()
	title.text = "CANDY • TETRIS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("ffd43b"))
	title.position = Vector2(24, 18)
	layer.add_child(title)

	_lines_label = Label.new()
	_lines_label.add_theme_font_size_override("font_size", 26)
	_lines_label.add_theme_color_override("font_color", Color("ffffff"))
	_lines_label.position = Vector2(24, 64)
	layer.add_child(_lines_label)

	_freeze_label = Label.new()
	_freeze_label.add_theme_font_size_override("font_size", 26)
	_freeze_label.add_theme_color_override("font_color", Color("00cfff"))
	_freeze_label.position = Vector2(24, 100)
	_freeze_label.visible = false
	layer.add_child(_freeze_label)

	# Legend for special balls.
	var legend := Label.new()
	legend.text = "💣 Bomb  🌈 Rainbow  ❄️ Freeze  ⚡ Lightning"
	legend.add_theme_font_size_override("font_size", 18)
	legend.add_theme_color_override("font_color", Color("cccccc"))
	legend.position = Vector2(24, 140)
	layer.add_child(legend)

	_update_hud()


func _update_hud() -> void:
	if _lines_label != null:
		_lines_label.text = "Lines: %d  |  Specials: %d" % [_lines, _specials_triggered]
	if _freeze_label != null:
		if _freeze_timer > 0.0:
			_freeze_label.text = "❄️ FROZEN! (%.1fs)" % _freeze_timer
			_freeze_label.visible = true
		else:
			_freeze_label.visible = false
