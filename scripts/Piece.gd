class_name Piece
## Represents an active falling tetromino piece.
##
## A piece is a set of cell offsets from an anchor (base) position, together
## with parallel arrays of ball types and colors.  The Piece class manages its
## own position state but delegates placement-validity checks to a Board
## instance and node-creation to a BallFactory instance.

# --- State -------------------------------------------------------------------
## The Board this piece operates on.
var board: Board

## Cell offsets relative to [member base] (Array[Vector2i]).
var offsets: Array = []

## Anchor position in board coordinates (bottom-left of the bounding box).
var base := Vector2i.ZERO

## Cached absolute cell positions (= base + offsets).  Refreshed by [method _refresh_cells].
var cells: Array = []

## Parallel arrays for per-ball data.
var types: Array = []   # Array[int]  (BallType values)
var colors: Array = []  # Array[Color]
var nodes: Array = []   # Array[MeshInstance3D]

# --- Init --------------------------------------------------------------------
func _init(b: Board) -> void:
	board = b


# --- Position helpers --------------------------------------------------------
## Move the anchor to [param new_base] and refresh the cells cache.
func set_base(new_base: Vector2i) -> void:
	base = new_base
	_refresh_cells()


## Recompute [member cells] from [member base] and [member offsets].
func _refresh_cells() -> void:
	cells = []
	for o in offsets:
		cells.append(base + o)


# --- Validity ----------------------------------------------------------------
## Returns true when every cell in [param candidate_cells] is within bounds and
## not occupied on the board.
func is_valid_cells(candidate_cells: Array) -> bool:
	for cell in candidate_cells:
		if cell.x < 0 or cell.x >= board.width or cell.y < 0:
			return false
		if cell.y < board.height and board.is_occupied(cell.y, cell.x):
			return false
	return true


## Returns true when placing the piece at base=(base_x, base_y) is valid.
func is_valid_at(base_x: int, base_y: int) -> bool:
	var candidate: Array = []
	for o in offsets:
		candidate.append(Vector2i(base_x, base_y) + o)
	return is_valid_cells(candidate)


## Returns true when the current position is valid.
func is_valid() -> bool:
	return is_valid_cells(cells)


# --- Distinct colors ---------------------------------------------------------
## Returns the set of distinct colors carried by this piece.
func distinct_colors() -> Array:
	var result: Array = []
	for c in colors:
		if not result.has(c):
			result.append(c)
	return result
