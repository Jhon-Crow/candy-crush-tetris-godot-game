class_name Board
## Manages the settled-ball grid: a rectangular 2-D array of cells.
##
## Each cell stores a [MeshInstance3D] node (or null), a [BallType], and a
## [Color].  Row 0 is the bottom; row [member height]-1 is the top.

# --- Constants ----------------------------------------------------------------
const NORMAL_TYPE := 0  # BallType.NORMAL equivalent for default initialization

# --- Grid data ----------------------------------------------------------------
var width: int
var height: int

## _cells[row][col] -> MeshInstance3D or null
var _cells: Array = []
## _types[row][col] -> int (BallType)
var _types: Array = []
## _colors[row][col] -> Color
var _colors: Array = []

## Number of lines cleared so far.
var lines: int = 0

## Signal emitted after one or more rows are cleared. Carries the new line count.
signal lines_updated(new_lines: int)

## Signal emitted whenever the grid is modified (bomb, rainbow, etc.)
signal grid_changed


# --- Lifecycle ----------------------------------------------------------------
func _init(w: int, h: int) -> void:
	width = w
	height = h
	_allocate()


## (Re-)initialize all cells to empty.
func reset() -> void:
	for row in height:
		for col in width:
			_cells[row][col] = null
			_types[row][col] = NORMAL_TYPE
			_colors[row][col] = Color.BLACK
	lines = 0
	grid_changed.emit()


# --- Cell access --------------------------------------------------------------
func get_node(row: int, col: int) -> MeshInstance3D:
	return _cells[row][col]


func get_type(row: int, col: int) -> int:
	return _types[row][col]


func get_color(row: int, col: int) -> Color:
	return _colors[row][col]


func set_cell(row: int, col: int, node: MeshInstance3D, btype: int, bcolor: Color) -> void:
	_cells[row][col] = node
	_types[row][col] = btype
	_colors[row][col] = bcolor


func clear_cell(row: int, col: int) -> void:
	if _cells[row][col] != null:
		_cells[row][col].queue_free()
		_cells[row][col] = null
	_types[row][col] = NORMAL_TYPE
	_colors[row][col] = Color.BLACK


func is_occupied(row: int, col: int) -> bool:
	if row < 0 or row >= height or col < 0 or col >= width:
		return false
	return _cells[row][col] != null


# --- Row clearing -------------------------------------------------------------
## Clears all full rows and shifts upper rows down. Returns the number of rows
## cleared in this call.
func clear_full_rows() -> int:
	var cleared := 0
	var row := 0
	while row < height:
		if _is_row_full(row):
			_clear_row(row)
			_shift_rows_down(row)
			cleared += 1
			lines += 1
			lines_updated.emit(lines)
			# Don't advance row: re-check the same index (now holds the row above).
		else:
			row += 1
	if cleared > 0:
		grid_changed.emit()
	return cleared


# --- Column / region clearers (used by special effects) ----------------------
## Clears every occupied cell within Chebyshev [param radius] of [param center].
func clear_chebyshev(center: Vector2i, radius: int) -> void:
	for row in height:
		for col in width:
			if _cells[row][col] != null:
				var dist := maxi(absi(col - center.x), absi(row - center.y))
				if dist <= radius:
					clear_cell(row, col)
	grid_changed.emit()


## Clears every occupied cell whose stored color is in [param colors].
func clear_by_colors(colors: Array) -> void:
	for row in height:
		for col in width:
			if _cells[row][col] != null:
				if colors.has(_colors[row][col]):
					clear_cell(row, col)
	grid_changed.emit()


## Clears every occupied cell in [param col_index].
func clear_column(col_index: int) -> void:
	for row in height:
		clear_cell(row, col_index)
	grid_changed.emit()


## Clears every occupied cell (hard reset without touching line counter).
func clear_all_nodes() -> void:
	for row in height:
		for col in width:
			clear_cell(row, col)
	grid_changed.emit()


# --- Validity ----------------------------------------------------------------
## Returns false when any cell reference is stale (freed) or the same node
## appears twice (data corruption).
func is_integrity_ok() -> bool:
	var seen := {}
	for row in height:
		for col in width:
			var node = _cells[row][col]
			if node == null:
				continue
			if not is_instance_valid(node):
				return false
			var id: int = node.get_instance_id()
			if seen.has(id):
				return false
			seen[id] = true
	return true


## Returns the number of currently occupied cells.
func count_occupied() -> int:
	var count := 0
	for row in height:
		for col in width:
			if _cells[row][col] != null:
				count += 1
	return count


# --- Private helpers ----------------------------------------------------------
func _allocate() -> void:
	_cells = []
	_types = []
	_colors = []
	for row in height:
		var cell_row: Array = []
		var type_row: Array = []
		var color_row: Array = []
		for _col in width:
			cell_row.append(null)
			type_row.append(NORMAL_TYPE)
			color_row.append(Color.BLACK)
		_cells.append(cell_row)
		_types.append(type_row)
		_colors.append(color_row)


func _is_row_full(row: int) -> bool:
	for col in width:
		if _cells[row][col] == null:
			return false
	return true


func _clear_row(row: int) -> void:
	for col in width:
		clear_cell(row, col)


func _shift_rows_down(from_row: int) -> void:
	for r in range(from_row, height - 1):
		for col in width:
			var node: MeshInstance3D = _cells[r + 1][col]
			_cells[r][col] = node
			_types[r][col] = _types[r + 1][col]
			_colors[r][col] = _colors[r + 1][col]
			# NOTE: The caller (Game.gd) is responsible for updating node
			# world positions after row clearing via reposition_settled_nodes().
	# Clear the vacated top row.
	for col in width:
		_cells[height - 1][col] = null
		_types[height - 1][col] = NORMAL_TYPE
		_colors[height - 1][col] = Color.BLACK
