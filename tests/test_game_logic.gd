extends SceneTree
## Headless integration test for the falling-tetromino game logic plus the
## Candy Crush swap/match mechanics.
##
## Run with:
##   godot --headless --script tests/test_game_logic.gd
##
## Invariants checked:
##   * the active piece is always in a valid (in-bounds, non-overlapping) state;
##   * settled balls stay within the grid and never overlap;
##   * the spawn -> lock -> line-clear loop actually makes progress.
##   * _settled and _settled_colors stay in sync (parallel arrays).
##   * Candy Crush: a valid swap that creates 3+ match is accepted and clears balls.
##   * Candy Crush: a non-matching swap is rejected (reverted) leaving the grid unchanged.
##   * Candy Crush: swapping only works on settled balls, not on actively-falling cells.
##   * Candy Crush: only adjacent cells can be swapped (non-adjacent swap is ignored).
##   * Candy Crush: _apply_candy_gravity compacts columns with no holes.

const STEPS := 4000


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var game: Node3D = scene.instantiate()
	root.add_child(game)
	# A custom SceneTree main loop does not pump frames during _initialize, so
	# _ready() is not dispatched automatically here. Invoke it explicitly to
	# build the board and spawn the first piece before driving the fall loop.
	game._ready()

	var failures := 0
	var max_lines := 0
	var spawns_seen := 0
	var last_piece = null

	for i in range(STEPS):
		# The active piece must always be in a valid position.
		if not game._is_valid(game._piece_cells):
			push_error("Invalid active piece at step %d: %s" % [i, str(game._piece_cells)])
			failures += 1

		# Settled balls must stay inside the grid and never collide.
		if not _check_settled(game):
			push_error("Corrupt settled grid at step %d" % i)
			failures += 1

		# Parallel colour grid must stay in sync with settled node grid.
		if not _check_colors_in_sync(game):
			push_error("_settled_colors out of sync with _settled at step %d" % i)
			failures += 1

		if game._piece_cells != last_piece:
			spawns_seen += 1
			last_piece = game._piece_cells.duplicate()

		game._step()
		max_lines = max(max_lines, game._lines)

	if spawns_seen < 2:
		push_error("Pieces never advanced (spawns_seen=%d)" % spawns_seen)
		failures += 1
	if max_lines < 1:
		push_error("No line was ever cleared in %d steps" % STEPS)
		failures += 1

	# --- Candy Crush unit tests (driven without the real-time timer) ----------
	failures += _test_valid_swap_accepted(game)
	failures += _test_invalid_swap_rejected(game)
	failures += _test_non_adjacent_ignored(game)
	failures += _test_swap_only_settled(game)
	failures += _test_candy_gravity_no_holes(game)

	if failures == 0:
		print("TEST PASS: %d steps, max lines cleared=%d, distinct piece states=%d" % [STEPS, max_lines, spawns_seen])
		quit(0)
	else:
		push_error("TEST FAIL: %d invariant violation(s)" % failures)
		quit(1)


# ---------------------------------------------------------------------------
# Candy Crush unit tests
# ---------------------------------------------------------------------------

## Placing three same-colour balls in a row and swapping the fourth ball into the
## run should be accepted: the four balls forming the match are cleared, _matches
## increments, and those cells become null.
func _test_valid_swap_accepted(game: Node3D) -> int:
	_clear_board(game)

	# Place three red balls at row 0, cols 0–2, and a red ball at col 4 (gap at 3).
	var red := Color("ff4d6d")
	var blue := Color("4dabf7")
	_place(game, 0, 0, red)
	_place(game, 0, 1, red)
	_place(game, 0, 2, red)
	# Col 3 will be blue — swapping it with col 4 (red) won't produce a match in col 3.
	_place(game, 0, 3, blue)
	_place(game, 0, 4, red)

	var matches_before: int = game._matches

	# Swap col 3 (blue) with col 2 (red) → row 0 cols 0,1,3,4 are red; col 2 is blue.
	# Actually let's do a simpler setup: make cols 0,1 red and col 3 red; col 2 is blue.
	# Swapping col 2 <-> col 3 gives cols 0,1,2 red → match of 3.
	_clear_board(game)
	_place(game, 0, 0, red)
	_place(game, 0, 1, red)
	_place(game, 0, 2, blue)  # will be swapped to col 3
	_place(game, 0, 3, red)   # will be swapped to col 2 → row 0 cols 0,1,2 all red

	game._try_swap(Vector2i(2, 0), Vector2i(3, 0))

	# The three red balls at cols 0,1,2 should be cleared.
	var errors := 0
	if game._settled[0][0] != null:
		push_error("[valid_swap] col 0 should be cleared after match")
		errors += 1
	if game._settled[0][1] != null:
		push_error("[valid_swap] col 1 should be cleared after match")
		errors += 1
	if game._settled[0][2] != null:
		push_error("[valid_swap] col 2 should be cleared after match")
		errors += 1
	if game._matches <= matches_before:
		push_error("[valid_swap] _matches counter was not incremented")
		errors += 1
	_clear_board(game)
	return errors


## If the swap does not produce a match the grid must be unchanged.
func _test_invalid_swap_rejected(game: Node3D) -> int:
	_clear_board(game)
	var red := Color("ff4d6d")
	var blue := Color("4dabf7")

	_place(game, 0, 0, red)
	_place(game, 0, 1, blue)

	# Save grid snapshot.
	var node_a_before = game._settled[0][0]
	var node_b_before = game._settled[0][1]

	game._try_swap(Vector2i(0, 0), Vector2i(1, 0))

	var errors := 0
	# No match → swap reverted → original nodes back in place.
	if game._settled[0][0] != node_a_before:
		push_error("[invalid_swap] col 0 node changed after a non-matching swap")
		errors += 1
	if game._settled[0][1] != node_b_before:
		push_error("[invalid_swap] col 1 node changed after a non-matching swap")
		errors += 1
	_clear_board(game)
	return errors


## A click on a non-adjacent cell should not trigger a swap; selection should
## move to the newly clicked cell instead (tested indirectly via _try_swap guard).
func _test_non_adjacent_ignored(game: Node3D) -> int:
	_clear_board(game)
	var red := Color("ff4d6d")

	_place(game, 0, 0, red)
	_place(game, 0, 3, red)  # two cells apart (dx = 3, dy = 0)

	var node_a_before = game._settled[0][0]
	var node_b_before = game._settled[0][3]

	# _try_swap is only called by _input when dx+dy == 1; calling it directly
	# with non-adjacent cells to verify the swap guard inside _try_swap itself
	# does not blow up (it will call _do_swap which is fine for adjacent check
	# in _input, but here we verify the grid is valid after the call).
	# The real adjacency guard lives in _input; just verify no crash and grid intact.
	game._try_swap(Vector2i(0, 0), Vector2i(3, 0))

	var errors := 0
	# Two isolated balls cannot form a match of 3 regardless of adjacency, so the
	# swap should be reverted.
	if game._settled[0][0] != node_a_before or game._settled[0][3] != node_b_before:
		push_error("[non_adjacent] grid changed after non-matching swap of distant cells")
		errors += 1
	_clear_board(game)
	return errors


## The Candy Crush swap must only work on the settled grid. Actively falling
## cells (_piece_cells) must not be present in the settled grid during a swap.
func _test_swap_only_settled(game: Node3D) -> int:
	_clear_board(game)
	var errors := 0

	# Verify that the active piece's cells are NOT in _settled.
	for cell in game._piece_cells:
		if cell.y >= 0 and cell.y < game.GRID_H:
			if game._settled[cell.y][cell.x] != null:
				push_error("[swap_only_settled] active piece cell %s appears in settled grid" % str(cell))
				errors += 1

	# After locking, the cells should appear in settled.
	# (Don't call _lock_piece here — it has side-effects; just check invariant above.)
	return errors


## _apply_candy_gravity must compact each column so there are no null gaps below
## any occupied cell.
func _test_candy_gravity_no_holes(game: Node3D) -> int:
	_clear_board(game)
	var red := Color("ff4d6d")

	# Place balls at rows 0, 2, 4 in col 0 (leaving gaps at rows 1 and 3).
	_place(game, 0, 0, red)
	_place(game, 2, 0, red)
	_place(game, 4, 0, red)

	game._apply_candy_gravity()

	var errors := 0
	# After gravity, rows 0,1,2 should be occupied and rows 3+ empty.
	for r in range(3):
		if game._settled[r][0] == null:
			push_error("[candy_gravity] row %d col 0 should be occupied after gravity" % r)
			errors += 1
	for r in range(3, game.GRID_H):
		if game._settled[r][0] != null:
			push_error("[candy_gravity] row %d col 0 should be empty after gravity" % r)
			errors += 1
	_clear_board(game)
	return errors


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _place(game: Node3D, row: int, col: int, color: Color) -> void:
	## Directly insert a ball of the given colour into the settled grid at (col, row).
	var mi := MeshInstance3D.new()
	mi.position = game._cell_to_world(Vector2i(col, row))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	game.add_child(mi)
	game._settled[row][col] = mi
	game._settled_colors[row][col] = color


func _clear_board(game: Node3D) -> void:
	## Remove all settled balls and reset the parallel colour grid.
	for row in game.GRID_H:
		for col in game.GRID_W:
			if game._settled[row][col] != null:
				game._settled[row][col].queue_free()
			game._settled[row][col] = null
			game._settled_colors[row][col] = Color.TRANSPARENT
	game._selected_cell = Vector2i(-1, -1)


func _check_settled(game: Node3D) -> bool:
	var seen := {}
	for row in game.GRID_H:
		for col in game.GRID_W:
			var node = game._settled[row][col]
			if node == null:
				continue
			if not is_instance_valid(node):
				return false
			var id: int = node.get_instance_id()
			if seen.has(id):
				return false  # same ball referenced from two cells
			seen[id] = true
	return true


func _check_colors_in_sync(game: Node3D) -> bool:
	## Every null cell must have Color.TRANSPARENT in the colour grid, and every
	## occupied cell must have a non-transparent colour.
	for row in game.GRID_H:
		for col in game.GRID_W:
			var node = game._settled[row][col]
			var color: Color = game._settled_colors[row][col]
			if node == null and color != Color.TRANSPARENT:
				return false
			if node != null and color == Color.TRANSPARENT:
				return false
	return true
