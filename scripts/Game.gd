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
## When [member auto_play] is enabled (the default) a lightweight heuristic
## steers each piece toward the column that keeps the stack flat and clears
## rows. With it disabled, pieces simply drop down the centre.

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

	SceneBuilder.build_environment(self)
	SceneBuilder.build_camera(self)
	SceneBuilder.build_lights(self)
	SceneBuilder.build_back_panel(self)

	_hud.update_score(_board.lines, _specials_triggered)
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
		_hud.update_score(_board.lines, _specials_triggered)
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
	_hud.update_score(_board.lines, _specials_triggered)


# --- Signal handlers ---------------------------------------------------------
func _on_effect_triggered() -> void:
	_specials_triggered += 1
	_hud.update_score(_board.lines, _specials_triggered)


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
