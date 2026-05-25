class_name AutoPlayer
## Heuristic auto-player: selects the best target column for a falling piece.
##
## Uses the four-feature genetic-algorithm-tuned weights from:
## https://codemyroad.wordpress.com/2013/04/14/tetris-ai-the-near-perfect-player/
##
## The auto-player is stateless: it evaluates candidate placements against a
## snapshot of the current [Board] and returns the best anchor X coordinate.

const W_HEIGHT := -0.51
const W_LINES  :=  0.76
const W_HOLES  := -0.36
const W_BUMPY  := -0.18


## Returns the anchor column that yields the best heuristic score for the given
## [param piece] dropped straight down onto [param board].
func best_column(piece: Piece, board: Board) -> int:
	var max_x := 0
	for o in piece.offsets:
		max_x = max(max_x, o.x)

	var best_x := piece.base.x
	var best_score := -INF
	for base_x in range(0, board.width - max_x):
		var base_y := _drop_row(piece, board, base_x)
		if base_y == board.height:  # column blocked all the way up
			continue
		var score := _score_placement(piece, board, Vector2i(base_x, base_y))
		if score > best_score:
			best_score = score
			best_x = base_x
	return best_x


# --- Private helpers ---------------------------------------------------------
## Lowest valid anchor row for the piece dropped at [param base_x].
## Returns board.height when no valid placement exists.
func _drop_row(piece: Piece, board: Board, base_x: int) -> int:
	var by := board.height
	while by > 0 and piece.is_valid_at(base_x, by - 1):
		by -= 1
	return by if piece.is_valid_at(base_x, by) else board.height


## Computes the four-feature heuristic score for placing [param piece] at [param base].
func _score_placement(piece: Piece, board: Board, base: Vector2i) -> float:
	# Build occupancy snapshot with the candidate piece inserted.
	var occ: Array = []
	for row in board.height:
		var line: Array = []
		for col in board.width:
			line.append(board.is_occupied(row, col))
		occ.append(line)
	for o in piece.offsets:
		var c: Vector2i = base + o
		if c.y >= 0 and c.y < board.height:
			occ[c.y][c.x] = true

	# Compute column heights and holes.
	var heights: Array = []
	var holes := 0
	for col in board.width:
		var top := -1
		for row in range(board.height - 1, -1, -1):
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
	for col in range(board.width - 1):
		bumpiness += abs(heights[col] - heights[col + 1])
	var lines := 0
	for row in board.height:
		var full := true
		for col in board.width:
			if not occ[row][col]:
				full = false
				break
		if full:
			lines += 1

	return W_HEIGHT * aggregate + W_LINES * lines + W_HOLES * holes + W_BUMPY * bumpiness
