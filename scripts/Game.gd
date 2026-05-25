extends Node3D
## Candy Crush + Tetris — main game controller.
##
## This script is intentionally thin: it owns one instance of each subsystem
## ([Board], [Piece], [BallFactory], [AutoPlayer], [SpecialEffects], [HUD])
## and coordinates their interactions.  All heavy logic lives in the subsystem
## classes so features can be developed and reviewed in isolation, reducing
## merge conflicts.
##
## Tetromino pieces made of multicoloured candy balls fall automatically down a
## grid.  The game is played on a flat playfield, but everything is rendered in a
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
## **Candy Crush mechanic:** once a piece has landed (settled), the player can
## click/tap on any two adjacent settled balls to swap them. A swap is only
## accepted if it creates a match of 3 or more same-coloured balls in a row or
## column (just like the original Candy Crush). Matched balls are removed and
## balls above fall down to fill the gaps. The mechanic never applies to balls
## that are still falling as part of the active piece.
##
## When [member auto_play] is enabled (the default) a lightweight heuristic
## steers each piece toward the column that keeps the stack flat and clears
## rows. With it disabled, pieces simply drop down the centre.
##
## The animated retrowave background is rendered via [Background] on a
## CanvasLayer at layer -1 (behind all 3D content).  The 3D environment uses a
## transparent background so the canvas shines through.  To swap themes as the
## player progresses, call [method _background.set_theme] with one of the
## [constant Background.THEME_*] dictionaries.

# --- Ball type enum (exposed here for backward compatibility with tests) -----
enum BallType { NORMAL, BOMB, RAINBOW, FREEZE, LIGHTNING }

# --- Board configuration -----------------------------------------------------
const GRID_W := 8
const GRID_H := 16
const CELL   := 1.0

const FALL_INTERVAL        := 0.30   # seconds between downward steps (normal speed)
const FALL_INTERVAL_FROZEN := 1.20   # slowed fall interval during freeze effect

# Tetromino shapes as cell offsets (x right, y up).
const SHAPES := [
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], # I
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], # O
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)], # T
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)], # S
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)], # Z
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)], # J
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)], # L
]

# --- Exports -----------------------------------------------------------------
## When true, pieces are automatically steered toward a good landing column.
@export var auto_play := true

## Probability (0–1) that any individual ball in a piece is a special ball.
@export var special_ball_chance := 0.15

## Duration in seconds of the freeze (slow-fall) effect.
@export var freeze_duration := 4.0

## Bomb effect radius in cells (Chebyshev / max-norm distance).
@export var bomb_radius := 2

# --- Subsystems --------------------------------------------------------------
var _board: Board
var _piece: Piece
var _factory: BallFactory
var _auto_player: AutoPlayer
var _effects: SpecialEffects
var _hud: HUD

# --- Runtime state -----------------------------------------------------------
var _target_x := 0
var _fall_timer := 0.0
var _freeze_timer := 0.0
var _anim_time := 0.0
var _specials_triggered := 0
var _matches := 0  # Candy Crush matches made

# --- Candy Crush selection state ---------------------------------------------
## The grid cell of the currently selected settled ball, or Vector2i(-1,-1) if
## none is selected. Selection is only possible while no active piece is falling.
var _selected_cell := Vector2i(-1, -1)

# Visual highlight: a slightly enlarged semi-transparent overlay sphere shown on
# the selected cell.
var _selection_highlight: MeshInstance3D

# Keep these public for backward-compatible test access
var _settled: Array:
	get: return _board._cells

var _settled_types: Array:
	get: return _board._types

var _settled_colors: Array:
	get: return _board._colors

var _piece_offsets: Array:
	get: return _piece.offsets

var _piece_base: Vector2i:
	get: return _piece.base

var _piece_nodes: Array:
	get: return _piece.nodes

var _piece_cells: Array:
	get: return _piece.cells

var _piece_types: Array:
	get: return _piece.types

var _piece_colors: Array:
	get: return _piece.colors

var _lines: int:
	get: return _board.lines


# --- Lifecycle ---------------------------------------------------------------
func _ready() -> void:
	randomize()
	_board = Board.new(GRID_W, GRID_H)
	_factory = BallFactory.new(self)
	_piece = Piece.new(_board)
	_auto_player = AutoPlayer.new()
	_effects = SpecialEffects.new()
	_hud = HUD.new(self)

	# Connect effect signals
	_effects.effect_triggered.connect(_on_effect_triggered)
	_effects.freeze_activated.connect(_on_freeze_activated)

	# Build the retrowave background first (must be behind all 3D content).
	SceneBuilder.build_background(self)
	SceneBuilder.build_environment(self)
	SceneBuilder.build_camera(self)
	SceneBuilder.build_lights(self)
	SceneBuilder.build_back_panel(self)
	_build_selection_highlight()

	_hud.update_score(_board.lines, _specials_triggered, _matches)
	_spawn_piece()


func _process(delta: float) -> void:
	_anim_time += delta
	_factory.animate_piece_materials(_piece, _anim_time)

	if _freeze_timer > 0.0:
		_freeze_timer -= delta
		if _freeze_timer <= 0.0:
			_freeze_timer = 0.0
		_hud.update_freeze(_freeze_timer)

	var interval := FALL_INTERVAL_FROZEN if _freeze_timer > 0.0 else FALL_INTERVAL
	_fall_timer += delta
	if _fall_timer >= interval:
		_fall_timer -= interval
		_step()

	# Smoothly glide active balls toward their logical grid position.
	var speed := CELL / FALL_INTERVAL * 1.6
	for i in _piece.nodes.size():
		var node: MeshInstance3D = _piece.nodes[i]
		node.position = node.position.move_toward(SceneBuilder.cell_to_world(_piece.cells[i]), speed * delta)


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
		var dx: int = absi(hit_cell.x - _selected_cell.x)
		var dy: int = absi(hit_cell.y - _selected_cell.y)
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
	_hud.update_score(_board.lines, _specials_triggered, _matches)


## Swap the two settled entries (node + type + colour) in the grid and update 3D positions.
func _do_swap(cell_a: Vector2i, cell_b: Vector2i) -> void:
	var node_a: MeshInstance3D = _settled[cell_a.y][cell_a.x]
	var node_b: MeshInstance3D = _settled[cell_b.y][cell_b.x]
	var type_a: int = _settled_types[cell_a.y][cell_a.x]
	var type_b: int = _settled_types[cell_b.y][cell_b.x]
	var color_a: Color = _settled_colors[cell_a.y][cell_a.x]
	var color_b: Color = _settled_colors[cell_b.y][cell_b.x]

	_settled[cell_a.y][cell_a.x] = node_b
	_settled[cell_b.y][cell_b.x] = node_a
	_settled_types[cell_a.y][cell_a.x] = type_b
	_settled_types[cell_b.y][cell_b.x] = type_a
	_settled_colors[cell_a.y][cell_a.x] = color_b
	_settled_colors[cell_b.y][cell_b.x] = color_a

	# Move the 3D meshes to their new positions instantly.
	if node_b != null:
		node_b.position = SceneBuilder.cell_to_world(cell_a)
	if node_a != null:
		node_a.position = SceneBuilder.cell_to_world(cell_b)


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
		_board.clear_cell(cell.y, cell.x)


## After matches are cleared, slide settled balls downward to fill gaps
## (column by column, compacting from bottom to top).
func _apply_candy_gravity() -> void:
	for col in GRID_W:
		var write_row := 0
		for read_row in GRID_H:
			if _settled[read_row][col] != null:
				if read_row != write_row:
					_settled[write_row][col] = _settled[read_row][col]
					_settled_types[write_row][col] = _settled_types[read_row][col]
					_settled_colors[write_row][col] = _settled_colors[read_row][col]
					_settled[read_row][col] = null
					_settled_types[read_row][col] = Board.NORMAL_TYPE
					_settled_colors[read_row][col] = Color.BLACK
					# Snap the 3D mesh to its new grid position immediately.
					_settled[write_row][col].position = SceneBuilder.cell_to_world(Vector2i(col, write_row))
				write_row += 1
		# Clear any leftover cells above write_row.
		for r in range(write_row, GRID_H):
			_settled[r][col] = null
			_settled_types[r][col] = Board.NORMAL_TYPE
			_settled_colors[r][col] = Color.BLACK


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
		_selection_highlight.position = SceneBuilder.cell_to_world(_selected_cell) + Vector3(0, 0, 0.15)
		_selection_highlight.visible = true


# --- Game loop ---------------------------------------------------------------
func _step() -> void:
	var dx := 0
	if auto_play and _piece.base.x != _target_x:
		dx = signi(_target_x - _piece.base.x)

	var down := _piece.base + Vector2i(0, -1)
	if dx != 0 and _piece.is_valid_at((down + Vector2i(dx, 0)).x, (down + Vector2i(dx, 0)).y):
		_piece.set_base(down + Vector2i(dx, 0))
	elif _piece.is_valid_at(down.x, down.y):
		_piece.set_base(down)
	elif dx != 0 and _piece.is_valid_at((_piece.base + Vector2i(dx, 0)).x, (_piece.base + Vector2i(dx, 0)).y):
		_piece.set_base(_piece.base + Vector2i(dx, 0))
	else:
		_lock_piece()
		_board.clear_full_rows()
		_reposition_settled_nodes()
		_hud.update_score(_board.lines, _specials_triggered, _matches)
		_spawn_piece()


func _spawn_piece() -> void:
	var shape: Array = SHAPES[randi() % SHAPES.size()]
	var max_x := 0
	var max_y := 0
	for o in shape:
		max_x = max(max_x, o.x)
		max_y = max(max_y, o.y)

	_piece.offsets = shape
	_piece.set_base(Vector2i(int((GRID_W - (max_x + 1)) / 2.0), GRID_H - 1 - max_y))
	_target_x = _auto_player.best_column(_piece, _board) if auto_play else _piece.base.x

	_piece.nodes = []
	_piece.types = []
	_piece.colors = []
	for o in shape:
		var btype: int = _factory.random_type(special_ball_chance)
		var color: Color = _factory.random_color()
		var ball := _factory.make_ball(color, btype)
		ball.position = SceneBuilder.cell_to_world(_piece.base + o + Vector2i(0, 1))
		_piece.nodes.append(ball)
		_piece.types.append(btype)
		_piece.colors.append(color)

	# If the spawn space is occupied, the board has overflowed — reset and keep piece.
	if not _piece.is_valid():
		_reset_board()


func _lock_piece() -> void:
	var piece_colors_set := _piece.distinct_colors()

	for i in _piece.cells.size():
		var cell: Vector2i = _piece.cells[i]
		var node: MeshInstance3D = _piece.nodes[i]
		var btype: int = _piece.types[i]
		var bcolor: Color = _piece.colors[i]
		node.position = SceneBuilder.cell_to_world(cell)
		if cell.y >= 0 and cell.y < GRID_H:
			_board.set_cell(cell.y, cell.x, node, btype, bcolor)

	# Fire special effects for balls that landed.
	for i in _piece.cells.size():
		var cell: Vector2i = _piece.cells[i]
		var btype: int = _piece.types[i]
		if btype == BallFactory.BallType.BOMB:
			_effects.apply_bomb(_board, cell, bomb_radius)
		elif btype == BallFactory.BallType.RAINBOW:
			_effects.apply_rainbow(_board, piece_colors_set)
		elif btype == BallFactory.BallType.FREEZE:
			_effects.apply_freeze(freeze_duration)
		elif btype == BallFactory.BallType.LIGHTNING:
			_effects.apply_lightning(_board, cell.x)

	_piece.nodes = []
	_piece.cells = []
	_piece.types = []
	_piece.colors = []


## Repositions all settled ball nodes to match their current grid row/col after
## row clearing has shifted them down in the data arrays.
func _reposition_settled_nodes() -> void:
	for row in GRID_H:
		for col in GRID_W:
			var node: MeshInstance3D = _board.get_node(row, col)
			if node != null:
				node.position = SceneBuilder.cell_to_world(Vector2i(col, row))


## Empties the settled board after an overflow. The active piece is left untouched.
func _reset_board() -> void:
	_board.clear_all_nodes()
	_board.lines = 0
	_hud.update_score(_board.lines, _specials_triggered, _matches)


# --- Signal handlers ---------------------------------------------------------
func _on_effect_triggered() -> void:
	_specials_triggered += 1
	_hud.update_score(_board.lines, _specials_triggered, _matches)


func _on_freeze_activated(duration: float) -> void:
	_freeze_timer = duration
	_hud.update_freeze(_freeze_timer)


# --- Backward-compatible helpers (used by tests) ----------------------------
## Converts a grid cell coordinate to a world-space Vector3.
func _cell_to_world(cell: Vector2i) -> Vector3:
	return SceneBuilder.cell_to_world(cell)


## Returns true when no cell in [param cells] is out of bounds or occupied.
func _is_valid(cells: Array) -> bool:
	return _piece.is_valid_cells(cells)


## Public wrappers so tests can call effects directly (backward compatibility).
## The effect_triggered signal handler (_on_effect_triggered) increments
## _specials_triggered; no double-counting here.
func _effect_bomb(center: Vector2i) -> void:
	_effects.apply_bomb(_board, center, bomb_radius)


func _effect_rainbow(piece_colors: Array) -> void:
	_effects.apply_rainbow(_board, piece_colors)


func _effect_freeze() -> void:
	# The freeze signal connects to _on_freeze_activated which sets _freeze_timer.
	# Call apply_freeze so the signal chain fires correctly.
	_effects.apply_freeze(freeze_duration)


func _effect_lightning(col: int) -> void:
	_effects.apply_lightning(_board, col)


## Gravity for settled balls (used by tests and Candy Crush swap mechanic).
## Identical to _apply_candy_gravity; exposed as _apply_gravity_to_settled for
## backward compatibility with upstream test T6.
func _apply_gravity_to_settled() -> void:
	_apply_candy_gravity()
