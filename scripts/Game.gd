extends Node3D
## Candy Crush + Tetris — primitive auto-falling implementation with
## Candy Crush swap mechanics for settled balls.
##
## Tetromino pieces made of multicoloured candy balls fall automatically down a
## grid. The game is played on a flat playfield, but everything is rendered in a
## true 3D scene (real sphere meshes, lighting and shadows) so the visuals can be
## elaborated on later.
##
## When [member auto_play] is enabled (the default) a lightweight heuristic steers
## each piece toward the column that keeps the stack flat and clears rows.
##
## **Candy Crush mechanic:** once a piece has landed (settled), the player can
## click/tap on any two adjacent settled balls to swap them. A swap is only
## accepted if it creates a match of 3 or more same-coloured balls in a row or
## column (just like the original Candy Crush). Matched balls are removed and
## balls above fall down to fill the gaps. The mechanic never applies to balls
## that are still falling as part of the active piece.

# --- Board configuration -----------------------------------------------------
const GRID_W := 8        # columns
const GRID_H := 16       # rows (row 0 = bottom)
const CELL := 1.0        # world units per cell
const FALL_INTERVAL := 0.30  # seconds between downward steps

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

# --- Runtime state -----------------------------------------------------------
var _settled: Array = []          # _settled[row][col] -> MeshInstance3D or null
var _settled_colors: Array = []   # _settled_colors[row][col] -> Color (parallel)
var _piece_offsets: Array = []    # Array[Vector2i] shape offsets of active piece
var _piece_base := Vector2i.ZERO  # bottom-left anchor of the active piece
var _piece_nodes: Array = []      # Array[MeshInstance3D] parallel to _piece_offsets
var _piece_cells: Array = []      # cached absolute cells (= base + offsets)
var _target_x := 0                # auto-player's desired anchor column
var _fall_timer := 0.0
var _lines := 0
var _matches := 0                 # Candy Crush matches made
var _ball_mesh: SphereMesh
var _lines_label: Label
var _matches_label: Label         # HUD label for match count

# --- Candy Crush selection state ---------------------------------------------
## The grid cell of the currently selected settled ball, or Vector2i(-1,-1) if
## none is selected. Selection is only possible while no active piece is falling.
var _selected_cell := Vector2i(-1, -1)

# Visual highlight: a slightly enlarged semi-transparent overlay sphere shown on
# the selected cell.
var _selection_highlight: MeshInstance3D


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
	_build_selection_highlight()
	_spawn_piece()


func _process(delta: float) -> void:
	_fall_timer += delta
	if _fall_timer >= FALL_INTERVAL:
		_fall_timer -= FALL_INTERVAL
		_step()
	# Smoothly glide active balls toward their logical grid position.
	var speed := CELL / FALL_INTERVAL * 1.6
	for i in _piece_nodes.size():
		var node: MeshInstance3D = _piece_nodes[i]
		node.position = node.position.move_toward(_cell_to_world(_piece_cells[i]), speed * delta)


# --- Input handling ----------------------------------------------------------
func _input(event: InputEvent) -> void:
	# Candy Crush swaps only happen via left mouse click or single touch tap.
	var is_click := false
	var screen_pos := Vector2.ZERO

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			is_click = true
			screen_pos = mb.position
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			is_click = true
			screen_pos = st.position

	if not is_click:
		return

	# Determine which settled grid cell (if any) was hit.
	var hit_cell := _screen_to_settled_cell(screen_pos)
	if hit_cell == Vector2i(-1, -1):
		# Clicked on empty space — deselect.
		_deselect()
		return

	if _selected_cell == Vector2i(-1, -1):
		# Nothing selected yet — select this cell.
		_select(hit_cell)
	elif hit_cell == _selected_cell:
		# Clicked the same cell again — deselect.
		_deselect()
	else:
		# A second cell was clicked — try to swap if they are adjacent.
		var dx := abs(hit_cell.x - _selected_cell.x)
		var dy := abs(hit_cell.y - _selected_cell.y)
		if dx + dy == 1:  # exactly one step horizontal or vertical
			_try_swap(_selected_cell, hit_cell)
		else:
			# Not adjacent — move selection to the new cell instead.
			_select(hit_cell)


## Convert a screen position to the settled grid cell under it.
## Returns Vector2i(-1, -1) when no settled ball is at that screen position.
func _screen_to_settled_cell(screen_pos: Vector2) -> Vector2i:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return Vector2i(-1, -1)

	# Project the screen click into a world ray and intersect with the z=0 plane
	# (the plane all balls live on).
	var ray_origin: Vector3 = cam.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = cam.project_ray_normal(screen_pos)

	# z = 0 plane: t = -ray_origin.z / ray_dir.z
	if abs(ray_dir.z) < 1e-6:
		return Vector2i(-1, -1)
	var t: float = -ray_origin.z / ray_dir.z
	var world_pos: Vector3 = ray_origin + ray_dir * t

	# Convert world position back to grid coordinates.
	var col := int(round(world_pos.x / CELL + (GRID_W - 1) / 2.0))
	var row := int(round(world_pos.y / CELL + (GRID_H - 1) / 2.0))

	if col < 0 or col >= GRID_W or row < 0 or row >= GRID_H:
		return Vector2i(-1, -1)
	if _settled[row][col] == null:
		return Vector2i(-1, -1)

	return Vector2i(col, row)


func _select(cell: Vector2i) -> void:
	_selected_cell = cell
	_update_highlight()


func _deselect() -> void:
	_selected_cell = Vector2i(-1, -1)
	_update_highlight()


## Try to swap the settled balls at [param cell_a] and [param cell_b].
## The swap is accepted only if it creates at least one match of 3+ same-colour
## balls (Candy Crush rules). Otherwise the swap is reverted immediately.
func _try_swap(cell_a: Vector2i, cell_b: Vector2i) -> void:
	_deselect()

	# Both cells must still be occupied (a piece lock could have changed things).
	if _settled[cell_a.y][cell_a.x] == null or _settled[cell_b.y][cell_b.x] == null:
		return

	# Perform the swap in the data grid.
	_do_swap(cell_a, cell_b)

	# Check if the swap produces any match.
	var matched := _find_matches()
	if matched.is_empty():
		# No match — revert.
		_do_swap(cell_a, cell_b)
		return

	# Clear matched balls and let gravity pull remaining settled balls down.
	_clear_matches(matched)
	_apply_candy_gravity()
	_matches += 1
	_update_hud()


## Swap the two settled entries (node + colour) in the grid and update 3D positions.
func _do_swap(cell_a: Vector2i, cell_b: Vector2i) -> void:
	var node_a: MeshInstance3D = _settled[cell_a.y][cell_a.x]
	var node_b: MeshInstance3D = _settled[cell_b.y][cell_b.x]
	var color_a: Color = _settled_colors[cell_a.y][cell_a.x]
	var color_b: Color = _settled_colors[cell_b.y][cell_b.x]

	_settled[cell_a.y][cell_a.x] = node_b
	_settled[cell_b.y][cell_b.x] = node_a
	_settled_colors[cell_a.y][cell_a.x] = color_b
	_settled_colors[cell_b.y][cell_b.x] = color_a

	# Move the 3D meshes to their new positions instantly.
	if node_b != null:
		node_b.position = _cell_to_world(cell_a)
	if node_a != null:
		node_a.position = _cell_to_world(cell_b)


## Return the set of cells that form matches of 3+ same-colour balls.
## Each match is collected horizontally and vertically, per standard Candy Crush.
func _find_matches() -> Array:
	var matched := {}  # cell (encoded as int) -> true

	# Horizontal runs.
	for row in GRID_H:
		var col := 0
		while col < GRID_W:
			if _settled[row][col] == null:
				col += 1
				continue
			var color: Color = _settled_colors[row][col]
			var run_end := col + 1
			while run_end < GRID_W and _settled[row][run_end] != null and _settled_colors[row][run_end] == color:
				run_end += 1
			if run_end - col >= 3:
				for c in range(col, run_end):
					matched[row * GRID_W + c] = true
			col = run_end

	# Vertical runs.
	for col in GRID_W:
		var row := 0
		while row < GRID_H:
			if _settled[row][col] == null:
				row += 1
				continue
			var color: Color = _settled_colors[row][col]
			var run_end := row + 1
			while run_end < GRID_H and _settled[run_end][col] != null and _settled_colors[run_end][col] == color:
				run_end += 1
			if run_end - row >= 3:
				for r in range(row, run_end):
					matched[r * GRID_W + col] = true
			row = run_end

	# Decode the set back to Vector2i cells.
	var result: Array = []
	for encoded in matched.keys():
		result.append(Vector2i(encoded % GRID_W, encoded / GRID_W))
	return result


## Remove all matched cells from the settled grid.
func _clear_matches(cells: Array) -> void:
	for cell in cells:
		var node: MeshInstance3D = _settled[cell.y][cell.x]
		if node != null:
			node.queue_free()
		_settled[cell.y][cell.x] = null
		_settled_colors[cell.y][cell.x] = Color.TRANSPARENT


## After matches are cleared, slide settled balls downward to fill gaps
## (column by column, compacting from bottom to top).
func _apply_candy_gravity() -> void:
	for col in GRID_W:
		var write_row := 0
		for read_row in GRID_H:
			if _settled[read_row][col] != null:
				if read_row != write_row:
					_settled[write_row][col] = _settled[read_row][col]
					_settled_colors[write_row][col] = _settled_colors[read_row][col]
					_settled[read_row][col] = null
					_settled_colors[read_row][col] = Color.TRANSPARENT
					# Snap the 3D mesh to its new grid position immediately.
					_settled[write_row][col].position = _cell_to_world(Vector2i(col, write_row))
				write_row += 1
		# Clear any leftover cells above write_row (there should be none, but
		# defensive cleanup just in case).
		for r in range(write_row, GRID_H):
			_settled[r][col] = null
			_settled_colors[r][col] = Color.TRANSPARENT


# --- Selection highlight ------------------------------------------------------
func _build_selection_highlight() -> void:
	_selection_highlight = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.50
	mesh.height = 1.0
	mesh.radial_segments = 24
	mesh.rings = 12
	_selection_highlight.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 0.8
	_selection_highlight.material_override = mat
	_selection_highlight.visible = false
	add_child(_selection_highlight)


func _update_highlight() -> void:
	if _selection_highlight == null:
		return
	if _selected_cell == Vector2i(-1, -1):
		_selection_highlight.visible = false
	else:
		_selection_highlight.position = _cell_to_world(_selected_cell) + Vector3(0, 0, 0.15)
		_selection_highlight.visible = true


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
			# Record the ball's colour in the parallel colour grid so the
			# Candy Crush match logic can compare without reading material data.
			var mat := node.material_override as StandardMaterial3D
			_settled_colors[cell.y][cell.x] = mat.albedo_color if mat != null else Color.WHITE
	_piece_nodes = []
	_piece_cells = []


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
				_settled_colors[row][col] = Color.TRANSPARENT
			# Shift every row above down by one.
			for r in range(row, GRID_H - 1):
				for col in GRID_W:
					var node: MeshInstance3D = _settled[r + 1][col]
					_settled[r][col] = node
					_settled_colors[r][col] = _settled_colors[r + 1][col]
					if node != null:
						node.position = _cell_to_world(Vector2i(col, r))
			for col in GRID_W:
				_settled[GRID_H - 1][col] = null
				_settled_colors[GRID_H - 1][col] = Color.TRANSPARENT
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
			_settled_colors[row][col] = Color.TRANSPARENT
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
	_settled_colors = []
	for row in GRID_H:
		var line: Array = []
		var color_line: Array = []
		for col in GRID_W:
			line.append(null)
			color_line.append(Color.TRANSPARENT)
		_settled.append(line)
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

	_matches_label = Label.new()
	_matches_label.add_theme_font_size_override("font_size", 22)
	_matches_label.add_theme_color_override("font_color", Color("f783ac"))
	_matches_label.position = Vector2(24, 100)
	layer.add_child(_matches_label)

	_update_hud()


func _update_hud() -> void:
	if _lines_label != null:
		_lines_label.text = "Lines cleared: %d" % _lines
	if _matches_label != null:
		_matches_label.text = "Candy matches: %d" % _matches
