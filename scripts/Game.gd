extends Node3D
## Candy Crush + Tetris — manual and automatic control.
##
## Tetromino pieces made of multicoloured candy balls fall automatically down a
## grid. The game is played on a flat playfield, but everything is rendered in a
## true 3D scene (real sphere meshes, lighting and shadows).
##
## Controls (keyboard):
##   ← / A            — move piece left  (manual mode)
##   → / D            — move piece right (manual mode)
##   ↓ / S            — soft drop (speed up falling)
##   ↑ / W            — hard drop (instantly land piece)
##   Space / Enter    — toggle automatic / manual mode
##
## Controls (on-screen, also usable on mobile):
##   ◀ button         — move piece left
##   ▶ button         — move piece right
##   ▼ button         — soft drop
##   "Авто" button    — toggle auto/manual mode

# --- Board configuration -----------------------------------------------------
const GRID_W := 8        # columns
const GRID_H := 16       # rows (row 0 = bottom)
const CELL := 1.0        # world units per cell
const FALL_INTERVAL := 0.30  # seconds between downward steps (normal)
const SOFT_DROP_INTERVAL := 0.06  # seconds between steps during soft drop

## When true, pieces are automatically steered toward a good landing column.
@export var auto_play := true

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
# Extra weight for contact area (pieces should slot neatly into gaps).
const W_CONTACT := 0.20

# --- Runtime state -----------------------------------------------------------
var _settled: Array = []          # _settled[row][col] -> MeshInstance3D or null
var _piece_offsets: Array = []    # Array[Vector2i] shape offsets of active piece
var _piece_base := Vector2i.ZERO  # bottom-left anchor of the active piece
var _piece_nodes: Array = []      # Array[MeshInstance3D] parallel to _piece_offsets
var _piece_cells: Array = []      # cached absolute cells (= base + offsets)
var _target_x := 0                # auto-player's desired anchor column
var _fall_timer := 0.0
var _lines := 0
var _ball_mesh: SphereMesh
var _lines_label: Label
var _auto_button: CheckButton     # bottom-centre toggle button
var _soft_drop := false           # true while the down-key / ▼ button is held
# Mobile on-screen button pressed flags (set/cleared by button signals).
var _btn_left_held := false
var _btn_right_held := false
# One-shot manual horizontal move queued by button press this tick.
var _manual_dx := 0
# Prevent Space/Enter from toggling auto_play multiple times in one held press.
var _toggle_pressed := false
# Ghost piece nodes (preview of where the piece will land).
var _ghost_nodes: Array = []


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
	# --- Read held-key soft-drop state ---------------------------------------
	_soft_drop = Input.is_action_pressed("ui_down")

	var interval := SOFT_DROP_INTERVAL if _soft_drop else FALL_INTERVAL
	_fall_timer += delta
	if _fall_timer >= interval:
		_fall_timer -= interval
		_step()

	# Smoothly glide active balls toward their logical grid position.
	var speed := CELL / FALL_INTERVAL * 1.6
	for i in _piece_nodes.size():
		var node: MeshInstance3D = _piece_nodes[i]
		node.position = node.position.move_toward(_cell_to_world(_piece_cells[i]), speed * delta)

	# Keep ghost piece in sync.
	_update_ghost()


func _unhandled_input(event: InputEvent) -> void:
	# --- Space / Enter: toggle auto-play mode --------------------------------
	if event.is_action_pressed("ui_accept"):
		_toggle_auto_play()

	# --- Hard drop (↑ / W) ---------------------------------------------------
	if event.is_action_pressed("ui_up") and not auto_play:
		_hard_drop()

	# --- One-shot left/right move on key-down (manual mode) ------------------
	if not auto_play:
		if event.is_action_pressed("ui_left"):
			_try_move(-1)
		if event.is_action_pressed("ui_right"):
			_try_move(1)


# --- Game loop ---------------------------------------------------------------
func _step() -> void:
	# In manual mode apply any pending one-shot dx from mobile buttons.
	if not auto_play and _manual_dx != 0:
		_try_move(_manual_dx)
		_manual_dx = 0

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


## Immediately drop the active piece to its lowest valid position and lock it.
func _hard_drop() -> void:
	while _placement_valid(_piece_base + Vector2i(0, -1)):
		_set_base(_piece_base + Vector2i(0, -1))
	_lock_piece()
	_clear_full_rows()
	_spawn_piece()


## Attempt to shift the active piece by [param dx] columns (-1 = left, 1 = right).
func _try_move(dx: int) -> void:
	var candidate := _piece_base + Vector2i(dx, 0)
	if _placement_valid(candidate):
		_set_base(candidate)


## Toggle between manual and automatic play, updating the UI button.
func _toggle_auto_play() -> void:
	auto_play = not auto_play
	if auto_play:
		_target_x = _best_target_column()
	if _auto_button != null:
		_auto_button.button_pressed = auto_play
	_update_ghost()


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
	for o in shape:
		var ball := _make_ball(COLORS[randi() % COLORS.size()])
		# Start one cell higher so the piece glides into view.
		ball.position = _cell_to_world(_piece_base + o + Vector2i(0, 1))
		_piece_nodes.append(ball)
	_refresh_cells()

	# Spawn ghost nodes for the new piece.
	_spawn_ghost()

	# If the spawn space is occupied, the board has overflowed. Clear the
	# settled balls and keep this fresh piece (which now fits on the empty
	# board) so the demo restarts seamlessly.
	if not _is_valid(_piece_cells):
		_reset_board()


func _lock_piece() -> void:
	for i in _piece_cells.size():
		var cell: Vector2i = _piece_cells[i]
		var node: MeshInstance3D = _piece_nodes[i]
		node.position = _cell_to_world(cell)
		if cell.y >= 0 and cell.y < GRID_H:
			_settled[cell.y][cell.x] = node
	_piece_nodes = []
	_piece_cells = []
	_clear_ghost()


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
			# Shift every row above down by one.
			for r in range(row, GRID_H - 1):
				for col in GRID_W:
					var node: MeshInstance3D = _settled[r + 1][col]
					_settled[r][col] = node
					if node != null:
						node.position = _cell_to_world(Vector2i(col, r))
			for col in GRID_W:
				_settled[GRID_H - 1][col] = null
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
	_lines = 0
	_update_hud()


# --- Ghost piece -------------------------------------------------------------

## Spawn semi-transparent ghost nodes that preview the landing position.
func _spawn_ghost() -> void:
	_clear_ghost()
	for _o in _piece_offsets:
		var mi := MeshInstance3D.new()
		mi.mesh = _ball_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 1, 1, 0.18)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		add_child(mi)
		_ghost_nodes.append(mi)


func _clear_ghost() -> void:
	for gn in _ghost_nodes:
		if is_instance_valid(gn):
			gn.queue_free()
	_ghost_nodes = []


## Reposition ghost nodes to show where the active piece will land.
func _update_ghost() -> void:
	if _ghost_nodes.size() != _piece_offsets.size():
		return
	# Find the ghost base: drop until the placement is no longer valid.
	var ghost_base := _piece_base
	while _placement_valid(ghost_base + Vector2i(0, -1)):
		ghost_base += Vector2i(0, -1)
	# Only show the ghost if it is below the current piece position.
	var show_ghost := (ghost_base.y < _piece_base.y)
	for i in _ghost_nodes.size():
		var gn: MeshInstance3D = _ghost_nodes[i]
		if show_ghost:
			gn.visible = true
			gn.position = _cell_to_world(ghost_base + _piece_offsets[i])
		else:
			gn.visible = false


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

	var contact := _contact_area(base, occ)

	return (W_HEIGHT * aggregate + W_LINES * lines + W_HOLES * holes
			+ W_BUMPY * bumpiness + W_CONTACT * contact)


## Count cells of the placed piece that touch the floor or an occupied cell.
## A higher contact area means the piece nestles snugly into existing gaps.
func _contact_area(base: Vector2i, occ: Array) -> int:
	var contacts := 0
	for o in _piece_offsets:
		var c: Vector2i = base + o
		# Floor contact.
		if c.y == 0:
			contacts += 1
		elif c.y > 0 and c.y - 1 < GRID_H and occ[c.y - 1][c.x]:
			contacts += 1
		# Left neighbour.
		if c.x > 0 and occ[c.y][c.x - 1]:
			contacts += 1
		# Right neighbour.
		if c.x < GRID_W - 1 and occ[c.y][c.x + 1]:
			contacts += 1
	return contacts


# --- Helpers -----------------------------------------------------------------
func _init_grid() -> void:
	_settled = []
	for row in GRID_H:
		var line: Array = []
		for col in GRID_W:
			line.append(null)
		_settled.append(line)


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


func _make_ball(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _ball_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.0
	mat.roughness = 0.22
	mat.rim_enabled = true
	mat.rim = 0.5
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.22
	mi.material_override = mat
	add_child(mi)
	return mi


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

	# --- Title ---------------------------------------------------------------
	var title := Label.new()
	title.text = "CANDY • TETRIS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("ffd43b"))
	title.position = Vector2(24, 18)
	layer.add_child(title)

	# --- Lines cleared counter -----------------------------------------------
	_lines_label = Label.new()
	_lines_label.add_theme_font_size_override("font_size", 26)
	_lines_label.add_theme_color_override("font_color", Color("ffffff"))
	_lines_label.position = Vector2(24, 64)
	layer.add_child(_lines_label)
	_update_hud()

	# --- Controls hint -------------------------------------------------------
	var hint := Label.new()
	hint.text = "← → A D: move  ↓ S: faster  ↑ W: drop  Space: auto"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	hint.position = Vector2(24, 100)
	layer.add_child(hint)

	# --- "Авто" toggle button (bottom-centre) --------------------------------
	_auto_button = CheckButton.new()
	_auto_button.text = "Авто"
	_auto_button.button_pressed = auto_play
	_auto_button.add_theme_font_size_override("font_size", 28)
	_auto_button.add_theme_color_override("font_color", Color("ffd43b"))
	# Anchor to bottom-centre of the viewport.
	_auto_button.anchor_left   = 0.5
	_auto_button.anchor_right  = 0.5
	_auto_button.anchor_top    = 1.0
	_auto_button.anchor_bottom = 1.0
	_auto_button.offset_left   = -80.0
	_auto_button.offset_right  =  80.0
	_auto_button.offset_top    = -64.0
	_auto_button.offset_bottom = -12.0
	_auto_button.toggled.connect(func(pressed: bool) -> void:
		if auto_play != pressed:
			auto_play = pressed
			if auto_play:
				_target_x = _best_target_column()
	)
	layer.add_child(_auto_button)

	# --- Mobile / touch arrow buttons ----------------------------------------
	_build_mobile_buttons(layer)


## Build on-screen arrow buttons for mobile / touch play. The left and right
## arrows sit beside the game field; a down arrow sits at the bottom-left.
func _build_mobile_buttons(layer: CanvasLayer) -> void:
	# Common style for all mobile buttons.
	var btn_size := Vector2(80, 80)

	# ◀ Left — left side of screen, vertically centred.
	var btn_left := Button.new()
	btn_left.text = "◀"
	btn_left.add_theme_font_size_override("font_size", 40)
	btn_left.custom_minimum_size = btn_size
	btn_left.anchor_left   = 0.0
	btn_left.anchor_right  = 0.0
	btn_left.anchor_top    = 0.5
	btn_left.anchor_bottom = 0.5
	btn_left.offset_left   =  8.0
	btn_left.offset_right  = 88.0
	btn_left.offset_top    = -40.0
	btn_left.offset_bottom =  40.0
	btn_left.pressed.connect(func() -> void:
		if not auto_play:
			_manual_dx = -1
	)
	layer.add_child(btn_left)

	# ▶ Right — right side of screen, vertically centred.
	var btn_right := Button.new()
	btn_right.text = "▶"
	btn_right.add_theme_font_size_override("font_size", 40)
	btn_right.custom_minimum_size = btn_size
	btn_right.anchor_left   = 1.0
	btn_right.anchor_right  = 1.0
	btn_right.anchor_top    = 0.5
	btn_right.anchor_bottom = 0.5
	btn_right.offset_left   = -88.0
	btn_right.offset_right  =  -8.0
	btn_right.offset_top    = -40.0
	btn_right.offset_bottom =  40.0
	btn_right.pressed.connect(func() -> void:
		if not auto_play:
			_manual_dx = 1
	)
	layer.add_child(btn_right)

	# ▼ Soft-drop — bottom-left area (above the auto button area).
	var btn_down := Button.new()
	btn_down.text = "▼"
	btn_down.add_theme_font_size_override("font_size", 36)
	btn_down.custom_minimum_size = btn_size
	btn_down.anchor_left   = 0.0
	btn_down.anchor_right  = 0.0
	btn_down.anchor_top    = 1.0
	btn_down.anchor_bottom = 1.0
	btn_down.offset_left   =  8.0
	btn_down.offset_right  = 88.0
	btn_down.offset_top    = -88.0
	btn_down.offset_bottom =  -8.0
	# Holding this button activates soft drop via _soft_drop flag.
	btn_down.button_down.connect(func() -> void: _soft_drop = true)
	btn_down.button_up.connect(func() -> void: _soft_drop = false)
	layer.add_child(btn_down)

	# ▲ Hard-drop — bottom-right area.
	var btn_up := Button.new()
	btn_up.text = "▲"
	btn_up.add_theme_font_size_override("font_size", 36)
	btn_up.custom_minimum_size = btn_size
	btn_up.anchor_left   = 1.0
	btn_up.anchor_right  = 1.0
	btn_up.anchor_top    = 1.0
	btn_up.anchor_bottom = 1.0
	btn_up.offset_left   = -88.0
	btn_up.offset_right  =  -8.0
	btn_up.offset_top    = -88.0
	btn_up.offset_bottom =  -8.0
	btn_up.pressed.connect(func() -> void:
		if not auto_play:
			_hard_drop()
	)
	layer.add_child(btn_up)


func _update_hud() -> void:
	if _lines_label != null:
		_lines_label.text = "Lines cleared: %d" % _lines
