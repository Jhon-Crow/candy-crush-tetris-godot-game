extends Node3D
## Candy Crush + Tetris — with Candy Crush-style progression.
##
## Tetromino pieces made of multicoloured candy balls fall automatically down a
## grid. The game is played on a flat playfield, but everything is rendered in a
## true 3D scene (real sphere meshes, lighting and shadows).
##
## Progression features (issue #9):
##   * Score counter   — 100/300/600/1200 pts for 1/2/3/4 simultaneous rows,
##                       then × combo multiplier (capped at ×8).
##   * Combo system    — incremented on each piece that clears ≥ 1 row; reset
##                       to 1 after a piece that clears nothing.
##   * Rush sections   — when the rush meter fills (score ≥ RUSH_GOAL) the fall
##                       speed doubles for RUSH_PIECES pieces, then reverts.
##   * Progress bar    — HUD ProgressBar fills toward the next rush threshold.
##   * Visual effects  — screen flash on clear, floating combo popup, rush
##                       border pulse. All effects are null-guarded so the
##                       headless test continues to pass unchanged.

# --- Board configuration -----------------------------------------------------
const GRID_W := 8        # columns
const GRID_H := 16       # rows (row 0 = bottom)
const CELL := 1.0        # world units per cell
const FALL_INTERVAL := 0.30  # seconds between downward steps (base speed)

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

# --- Progression configuration -----------------------------------------------
## Score awarded for clearing N rows simultaneously (index = rows-1).
const LINE_SCORE := [100, 300, 600, 1200]
## Maximum combo multiplier.
const MAX_COMBO := 8
## Score points needed to fill the rush progress bar and trigger a Rush.
## Set to 300 so the AI reliably triggers rush (≥3 single-row clears needed).
const RUSH_GOAL := 300
## Number of pieces that fall at rush speed before reverting to normal.
const RUSH_PIECES := 10

# --- Runtime state -----------------------------------------------------------
var _settled: Array = []          # _settled[row][col] -> MeshInstance3D or null
var _piece_offsets: Array = []    # Array[Vector2i] shape offsets of active piece
var _piece_base := Vector2i.ZERO  # bottom-left anchor of the active piece
var _piece_nodes: Array = []      # Array[MeshInstance3D] parallel to _piece_offsets
var _piece_cells: Array = []      # cached absolute cells (= base + offsets)
var _target_x := 0                # auto-player's desired anchor column
var _fall_timer := 0.0
var _lines := 0

# Progression state
var _score := 0           # current-round score (resets on board overflow)
var _total_score := 0     # cumulative all-time score (never resets)
var _combo := 1          # current combo multiplier (1 = no combo active)
var _rush_progress := 0  # score points accumulated toward the next rush
var _rush_active := false
var _rush_pieces_left := 0  # pieces remaining in current rush

var _ball_mesh: SphereMesh
var _lines_label: Label
var _score_label: Label
var _combo_label: Label
var _rush_label: Label
var _rush_bar: ProgressBar
var _flash_rect: ColorRect      # full-screen flash overlay
var _rush_border: ColorRect     # border overlay shown during rush


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
	var interval := FALL_INTERVAL / 2.0 if _rush_active else FALL_INTERVAL
	_fall_timer += delta
	if _fall_timer >= interval:
		_fall_timer -= interval
		_step()
	# Smoothly glide active balls toward their logical grid position.
	var speed := CELL / interval * 1.6
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
	for o in shape:
		var ball := _make_ball(COLORS[randi() % COLORS.size()])
		# Start one cell higher so the piece glides into view.
		ball.position = _cell_to_world(_piece_base + o + Vector2i(0, 1))
		_piece_nodes.append(ball)
	_refresh_cells()

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

	# Tick rush duration on each locked piece (regardless of whether it clears).
	if _rush_active:
		_rush_pieces_left -= 1
		if _rush_pieces_left <= 0:
			_end_rush()


func _clear_full_rows() -> void:
	var rows_cleared := 0
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
			rows_cleared += 1
			# Re-check the same row index (it now holds the row that fell down).
		else:
			row += 1

	if rows_cleared > 0:
		# Award score: escalating table × current combo multiplier.
		var base_pts: int = LINE_SCORE[min(rows_cleared - 1, LINE_SCORE.size() - 1)]
		_add_score(base_pts * _combo)
		# Increment combo for consecutive clears.
		_combo = min(_combo + 1, MAX_COMBO)
		_show_combo_popup(rows_cleared)
		_flash_screen()
	else:
		# No clear this piece — reset combo.
		_combo = 1

	_update_hud()


## Award [param pts] points, update the rush progress meter.
func _add_score(pts: int) -> void:
	_score += pts
	_total_score += pts
	_rush_progress += pts
	if not _rush_active and _rush_progress >= RUSH_GOAL:
		_rush_progress -= RUSH_GOAL
		_start_rush()


func _start_rush() -> void:
	_rush_active = true
	_rush_pieces_left = RUSH_PIECES
	_update_hud()
	_pulse_rush_border(true)


func _end_rush() -> void:
	_rush_active = false
	_update_hud()
	_pulse_rush_border(false)


## Empties the settled board after an overflow. The active piece is left
## untouched so play continues immediately on the cleared board.
func _reset_board() -> void:
	for row in GRID_H:
		for col in GRID_W:
			if _settled[row][col] != null:
				_settled[row][col].queue_free()
				_settled[row][col] = null
	_lines = 0
	_score = 0
	_combo = 1
	_rush_progress = 0
	_rush_active = false
	_rush_pieces_left = 0
	_update_hud()
	if _rush_border != null:
		_rush_border.visible = false


# --- Visual effects ----------------------------------------------------------
## Brief full-screen flash — signals a row was cleared.
func _flash_screen() -> void:
	if _flash_rect == null:
		return
	_flash_rect.modulate.a = 0.55
	var tw := create_tween()
	tw.tween_property(_flash_rect, "modulate:a", 0.0, 0.25)


## Floating "+score COMBO ×N" label that rises and fades away.
func _show_combo_popup(rows: int) -> void:
	if _rush_bar == null:
		return  # HUD not built (headless test) — skip
	var pts: int = LINE_SCORE[min(rows - 1, LINE_SCORE.size() - 1)] * _combo
	var popup := Label.new()
	popup.text = "+%d  ×%d COMBO" % [pts, _combo] if _combo > 1 else "+%d" % pts
	popup.add_theme_font_size_override("font_size", 28)
	var hue := 0.13 if rows < 2 else (0.55 if rows < 3 else 0.83)
	popup.add_theme_color_override("font_color", Color.from_hsv(hue, 0.9, 1.0))
	popup.position = Vector2(randf_range(80, 220), 300)
	# Add to the same CanvasLayer as the rush bar's parent.
	_rush_bar.get_parent().add_child(popup)
	var tw := create_tween()
	tw.tween_property(popup, "position:y", popup.position.y - 80, 0.8)
	tw.parallel().tween_property(popup, "modulate:a", 0.0, 0.8)
	tw.tween_callback(popup.queue_free)


## Pulse (show/hide) the rush border overlay.
func _pulse_rush_border(on: bool) -> void:
	if _rush_border == null:
		return
	_rush_border.visible = on
	if on:
		var tw := create_tween()
		tw.set_loops()
		tw.tween_property(_rush_border, "modulate:a", 0.7, 0.25)
		tw.tween_property(_rush_border, "modulate:a", 0.25, 0.25)


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

	# ---- Title ----
	var title := Label.new()
	title.text = "CANDY • TETRIS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("ffd43b"))
	title.position = Vector2(24, 18)
	layer.add_child(title)

	# ---- Lines cleared ----
	_lines_label = Label.new()
	_lines_label.add_theme_font_size_override("font_size", 22)
	_lines_label.add_theme_color_override("font_color", Color("ffffff"))
	_lines_label.position = Vector2(24, 64)
	layer.add_child(_lines_label)

	# ---- Score ----
	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 22)
	_score_label.add_theme_color_override("font_color", Color("ffd43b"))
	_score_label.position = Vector2(24, 92)
	layer.add_child(_score_label)

	# ---- Combo ----
	_combo_label = Label.new()
	_combo_label.add_theme_font_size_override("font_size", 22)
	_combo_label.add_theme_color_override("font_color", Color("f783ac"))
	_combo_label.position = Vector2(24, 120)
	layer.add_child(_combo_label)

	# ---- Rush status ----
	_rush_label = Label.new()
	_rush_label.add_theme_font_size_override("font_size", 22)
	_rush_label.add_theme_color_override("font_color", Color("51cf66"))
	_rush_label.position = Vector2(24, 148)
	layer.add_child(_rush_label)

	# ---- Rush progress bar ----
	var bar_bg := Label.new()
	bar_bg.text = "RUSH:"
	bar_bg.add_theme_font_size_override("font_size", 18)
	bar_bg.add_theme_color_override("font_color", Color("aaaaaa"))
	bar_bg.position = Vector2(24, 180)
	layer.add_child(bar_bg)

	_rush_bar = ProgressBar.new()
	_rush_bar.min_value = 0.0
	_rush_bar.max_value = 1.0
	_rush_bar.value = 0.0
	_rush_bar.size = Vector2(180, 22)
	_rush_bar.position = Vector2(80, 182)
	_rush_bar.show_percentage = false
	layer.add_child(_rush_bar)

	# ---- Screen flash overlay (full-screen transparent rect) ----
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1.0, 1.0, 0.6, 0.0)
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash_rect)

	# ---- Rush border overlay ----
	_rush_border = ColorRect.new()
	_rush_border.color = Color(0.3, 1.0, 0.5, 0.45)
	_rush_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rush_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rush_border.visible = false
	# Use a sub-rect inset so only the border is visible (center transparent).
	# We achieve a "border only" look by overlaying a dark inner rect.
	var inner := ColorRect.new()
	inner.color = Color(0.0, 0.0, 0.0, 0.0)
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.set_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 12
	inner.offset_top = 12
	inner.offset_right = -12
	inner.offset_bottom = -12
	_rush_border.add_child(inner)
	layer.add_child(_rush_border)

	_update_hud()


func _update_hud() -> void:
	if _lines_label != null:
		_lines_label.text = "Lines: %d" % _lines
	if _score_label != null:
		_score_label.text = "Score: %d" % _score
	if _combo_label != null:
		if _combo > 1:
			_combo_label.text = "Combo ×%d" % _combo
		else:
			_combo_label.text = ""
	if _rush_label != null:
		_rush_label.text = "⚡ RUSH!" if _rush_active else ""
	if _rush_bar != null:
		if _rush_active:
			_rush_bar.value = 1.0
		else:
			_rush_bar.value = clampf(float(_rush_progress) / float(RUSH_GOAL), 0.0, 1.0)
