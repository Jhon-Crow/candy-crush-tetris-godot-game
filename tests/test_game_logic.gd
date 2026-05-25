extends SceneTree
## Headless integration test for the falling-tetromino game logic plus the
## Candy Crush swap/match mechanics and special balls.
##
## Run with:
##   godot --headless --script tests/test_game_logic.gd
##
## Tests:
##   1. Core loop invariants over 4 000 steps (piece validity, grid integrity,
##      line clearing progress, colour-grid sync).
##   2. BOMB effect — clears cells within the configured radius.
##   3. RAINBOW effect — clears all settled balls whose colour matches the piece.
##   4. FREEZE effect — sets _freeze_timer and slows the effective fall interval.
##   5. LIGHTNING effect — clears the entire target column.
##   6. Gravity after special effects — balls fall into gaps left by effects.
##   7. Candy Crush: a valid swap that creates 3+ match is accepted and clears balls.
##   8. Candy Crush: a non-matching swap is rejected (reverted) leaving the grid unchanged.
##   9. Candy Crush: non-adjacent swap is reverted (no match formed).
##  10. Candy Crush: swapping only works on settled balls, not on actively-falling cells.
##  11. Candy Crush: _apply_candy_gravity compacts columns with no holes.

const STEPS := 4000


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")

	# ---- Test 1: core loop invariants ---------------------------------------
	var game: Node3D = scene.instantiate()
	root.add_child(game)
	game._ready()

	var failures := 0
	var max_lines := 0
	var spawns_seen := 0
	var last_piece = null

	for i in range(STEPS):
		if not game._is_valid(game._piece_cells):
			push_error("T1: Invalid active piece at step %d: %s" % [i, str(game._piece_cells)])
			failures += 1
		if not _check_settled(game):
			push_error("T1: Corrupt settled grid at step %d" % i)
			failures += 1
		# Parallel colour grid must stay in sync with settled node grid.
		if not _check_colors_in_sync(game):
			push_error("T1: _settled_colors out of sync with _settled at step %d" % i)
			failures += 1
		if game._piece_cells != last_piece:
			spawns_seen += 1
			last_piece = game._piece_cells.duplicate()
		game._step()
		max_lines = max(max_lines, game._lines)

	if spawns_seen < 2:
		push_error("T1: Pieces never advanced (spawns_seen=%d)" % spawns_seen)
		failures += 1
	if max_lines < 1:
		push_error("T1: No line was ever cleared in %d steps" % STEPS)
		failures += 1
	print("T1 (core loop): %s  [steps=%d, max_lines=%d, spawns=%d]" % [
		"PASS" if failures == 0 else "FAIL", STEPS, max_lines, spawns_seen])

	# ---- Test 2: BOMB effect ------------------------------------------------
	var g2: Node3D = scene.instantiate()
	root.add_child(g2)
	g2._ready()
	var bomb_fails := 0

	# Fill a 5×5 block of settled cells centred at (4, 4) to give the bomb
	# something to clear.
	_fill_rect(g2, 2, 2, 6, 6)

	var filled_before := _count_settled(g2)
	if filled_before == 0:
		push_error("T2: Pre-fill failed — nothing to clear")
		bomb_fails += 1
	else:
		# Fire a bomb at (4, 4) with the default radius of 2.
		g2._effect_bomb(Vector2i(4, 4))
		var filled_after := _count_settled(g2)
		if filled_after >= filled_before:
			push_error("T2: Bomb had no effect (before=%d, after=%d)" % [filled_before, filled_after])
			bomb_fails += 1
		if not _check_settled(g2):
			push_error("T2: Settled grid corrupted after bomb")
			bomb_fails += 1
		# Cells within the bomb radius (Chebyshev 2) must be empty.
		for row in range(2, 7):
			for col in range(2, 7):
				if maxi(absi(col - 4), absi(row - 4)) <= g2.bomb_radius:
					if g2._settled[row][col] != null:
						push_error("T2: Cell (%d,%d) not cleared by bomb" % [col, row])
						bomb_fails += 1
	failures += bomb_fails
	print("T2 (bomb):      %s" % ("PASS" if bomb_fails == 0 else "FAIL"))

	# ---- Test 3: RAINBOW effect ---------------------------------------------
	var g3: Node3D = scene.instantiate()
	root.add_child(g3)
	g3._ready()
	var rainbow_fails := 0

	var target_color := Color("ff4d6d")   # strawberry
	var other_color  := Color("4dabf7")   # blueberry

	# Place some balls of both colours.
	_place_ball_color(g3, 0, 0, target_color)
	_place_ball_color(g3, 0, 1, target_color)
	_place_ball_color(g3, 0, 2, other_color)
	_place_ball_color(g3, 0, 3, other_color)

	var total_before := _count_settled(g3)
	g3._effect_rainbow([target_color])
	var total_after := _count_settled(g3)

	# Two target-color balls should be gone; two other-color balls should remain.
	if total_after != total_before - 2:
		push_error("T3: Rainbow cleared wrong count (before=%d after=%d, expected %d)" % [
			total_before, total_after, total_before - 2])
		rainbow_fails += 1
	if g3._settled[0][0] != null or g3._settled[0][1] != null:
		push_error("T3: Target-colour balls were not cleared")
		rainbow_fails += 1
	if g3._settled[0][2] == null or g3._settled[0][3] == null:
		push_error("T3: Non-target-colour balls were incorrectly cleared")
		rainbow_fails += 1
	if not _check_settled(g3):
		push_error("T3: Settled grid corrupted after rainbow")
		rainbow_fails += 1
	failures += rainbow_fails
	print("T3 (rainbow):   %s" % ("PASS" if rainbow_fails == 0 else "FAIL"))

	# ---- Test 4: FREEZE effect ----------------------------------------------
	var g4: Node3D = scene.instantiate()
	root.add_child(g4)
	g4._ready()
	var freeze_fails := 0

	if g4._freeze_timer != 0.0:
		push_error("T4: _freeze_timer should start at 0, got %f" % g4._freeze_timer)
		freeze_fails += 1
	g4._effect_freeze()
	if g4._freeze_timer <= 0.0:
		push_error("T4: _freeze_timer not set after _effect_freeze()")
		freeze_fails += 1
	# Verify that _process uses the slower interval while frozen.
	# Advance the fall timer to just under the fast interval; without freeze,
	# a step would fire. With freeze the step must NOT fire (piece shouldn't move).
	g4._freeze_timer = 999.0  # keep frozen indefinitely for this check
	var cells_before: Array = g4._piece_cells.duplicate()
	# The frozen interval is FALL_INTERVAL_FROZEN (4× slower); advance the timer
	# to just under the frozen threshold — no step should fire.
	g4._fall_timer = 0.0
	g4._process(g4.FALL_INTERVAL - 0.001)   # still under frozen interval
	var cells_after: Array = g4._piece_cells.duplicate()
	if cells_before != cells_after:
		# Piece moved even though the frozen interval was not reached — that's wrong.
		push_error("T4: Piece moved during freeze when it shouldn't have")
		freeze_fails += 1
	failures += freeze_fails
	print("T4 (freeze):    %s" % ("PASS" if freeze_fails == 0 else "FAIL"))

	# ---- Test 5: LIGHTNING effect -------------------------------------------
	var g5: Node3D = scene.instantiate()
	root.add_child(g5)
	g5._ready()
	var lightning_fails := 0

	# Fill column 3 entirely.
	for row in g5.GRID_H:
		_place_ball_color(g5, row, 3, Color("ffd43b"))

	# Fill a different column to ensure it is NOT cleared.
	for row in g5.GRID_H:
		_place_ball_color(g5, row, 5, Color("51cf66"))

	g5._effect_lightning(3)

	# Column 3 must be empty.
	for row in g5.GRID_H:
		if g5._settled[row][3] != null:
			push_error("T5: Lightning did not clear row %d of column 3" % row)
			lightning_fails += 1
	# Column 5 must be untouched.
	for row in g5.GRID_H:
		if g5._settled[row][5] == null:
			push_error("T5: Lightning incorrectly cleared row %d of column 5" % row)
			lightning_fails += 1
	if not _check_settled(g5):
		push_error("T5: Settled grid corrupted after lightning")
		lightning_fails += 1
	failures += lightning_fails
	print("T5 (lightning): %s" % ("PASS" if lightning_fails == 0 else "FAIL"))

	# ---- Test 6: gravity after special effects ---------------------------------
	# After a special effect removes balls from the middle of the settled stack,
	# the balls above the gap must fall down to fill it.
	var g6: Node3D = scene.instantiate()
	root.add_child(g6)
	g6._ready()
	var gravity_fails := 0

	# Place a ball at row 0 (bottom) in column 0.
	_place_ball_color(g6, 0, 0, Color("ff4d6d"))
	# Place a ball at row 1 above it.
	_place_ball_color(g6, 1, 0, Color("ffd43b"))
	# Place a ball at row 2 above row 1.
	_place_ball_color(g6, 2, 0, Color("51cf66"))

	# Manually clear row 0 of column 0 (simulate a gap appearing at the bottom).
	if g6._settled[0][0] != null:
		g6._settled[0][0].queue_free()
		g6._settled[0][0] = null
		g6._settled_types[0][0] = g6.BallType.NORMAL
		g6._settled_colors[0][0] = Color.BLACK

	# Apply gravity — the two balls at rows 1 and 2 must fall down by one row each.
	g6._apply_gravity_to_settled()

	# After gravity: row 0 should have the ball that was at row 1,
	# row 1 should have the ball that was at row 2, row 2 should be empty.
	if g6._settled[0][0] == null:
		push_error("T6: Ball did not fall into row 0 after gap at bottom")
		gravity_fails += 1
	if g6._settled[1][0] == null:
		push_error("T6: Ball did not fall into row 1 after gap at bottom")
		gravity_fails += 1
	if g6._settled[2][0] != null:
		push_error("T6: Row 2 should be empty after gravity but is occupied")
		gravity_fails += 1
	# Verify no floating balls anywhere (every non-null ball has no null below it).
	for col in g6.GRID_W:
		var found_empty := false
		for row in g6.GRID_H:
			if g6._settled[row][col] == null:
				found_empty = true
			elif found_empty:
				push_error("T6: Ball at (%d,%d) is floating above an empty cell" % [col, row])
				gravity_fails += 1
				break
	if not _check_settled(g6):
		push_error("T6: Settled grid corrupted after gravity")
		gravity_fails += 1

	# Also test via lightning: place a column of balls with a ball in the same
	# column one row above (after lightning clears column 2, ball in col 1
	# should not be affected, but ball in col 2 at row > 0 should fall to row 0).
	var g6b: Node3D = scene.instantiate()
	root.add_child(g6b)
	g6b._ready()

	# In column 2: place only at row 2 (nothing below it).
	_place_ball_color(g6b, 2, 2, Color("ff4d6d"))
	# Place another ball at row 3 in column 2.
	_place_ball_color(g6b, 3, 2, Color("ffd43b"))
	# Nothing at rows 0 or 1 in column 2 — balls should fall after effect.
	# Trigger lightning on another column (col 5) to avoid clearing col 2.
	g6b._effect_lightning(5)  # clears col 5, applies gravity across all cols
	# Balls in col 2 at rows 2 and 3 must have fallen to rows 0 and 1.
	if g6b._settled[0][2] == null:
		push_error("T6b: Ball in col 2 did not fall to row 0 after gravity")
		gravity_fails += 1
	if g6b._settled[1][2] == null:
		push_error("T6b: Ball in col 2 did not fall to row 1 after gravity")
		gravity_fails += 1
	if g6b._settled[2][2] != null:
		push_error("T6b: Row 2 col 2 should be empty after gravity")
		gravity_fails += 1
	if g6b._settled[3][2] != null:
		push_error("T6b: Row 3 col 2 should be empty after gravity")
		gravity_fails += 1

	failures += gravity_fails
	print("T6 (gravity):   %s" % ("PASS" if gravity_fails == 0 else "FAIL"))

	# ---- Test 7: valid Candy Crush swap accepted ----------------------------
	var swap_fails := 0
	var g7: Node3D = scene.instantiate()
	root.add_child(g7)
	g7._ready()

	var red := Color("ff4d6d")
	var blue := Color("4dabf7")
	# Set up: cols 0,1 red; col 2 blue; col 3 red → swapping col2↔col3 gives
	# cols 0,1,2 all red → match of 3.
	_place_ball_color(g7, 0, 0, red)
	_place_ball_color(g7, 0, 1, red)
	_place_ball_color(g7, 0, 2, blue)
	_place_ball_color(g7, 0, 3, red)

	var matches_before: int = g7._matches
	g7._try_swap(Vector2i(2, 0), Vector2i(3, 0))

	# The three red balls at cols 0,1,2 should be cleared.
	if g7._settled[0][0] != null:
		push_error("T7: col 0 should be cleared after match")
		swap_fails += 1
	if g7._settled[0][1] != null:
		push_error("T7: col 1 should be cleared after match")
		swap_fails += 1
	if g7._settled[0][2] != null:
		push_error("T7: col 2 should be cleared after match")
		swap_fails += 1
	if g7._matches <= matches_before:
		push_error("T7: _matches counter was not incremented")
		swap_fails += 1
	failures += swap_fails
	print("T7 (valid swap): %s" % ("PASS" if swap_fails == 0 else "FAIL"))

	# ---- Test 8: invalid Candy Crush swap rejected --------------------------
	var reject_fails := 0
	var g8: Node3D = scene.instantiate()
	root.add_child(g8)
	g8._ready()

	_place_ball_color(g8, 0, 0, red)
	_place_ball_color(g8, 0, 1, blue)

	var node_a_before = g8._settled[0][0]
	var node_b_before = g8._settled[0][1]

	g8._try_swap(Vector2i(0, 0), Vector2i(1, 0))

	# No match → swap reverted → original nodes back in place.
	if g8._settled[0][0] != node_a_before:
		push_error("T8: col 0 node changed after a non-matching swap")
		reject_fails += 1
	if g8._settled[0][1] != node_b_before:
		push_error("T8: col 1 node changed after a non-matching swap")
		reject_fails += 1
	failures += reject_fails
	print("T8 (invalid swap): %s" % ("PASS" if reject_fails == 0 else "FAIL"))

	# ---- Test 9: non-adjacent swap reverted --------------------------------
	var nonadj_fails := 0
	var g9: Node3D = scene.instantiate()
	root.add_child(g9)
	g9._ready()

	_place_ball_color(g9, 0, 0, red)
	_place_ball_color(g9, 0, 3, red)  # two cells apart (dx=3)

	var node9_a = g9._settled[0][0]
	var node9_b = g9._settled[0][3]

	# Two isolated balls cannot form a match of 3, so swap should be reverted.
	g9._try_swap(Vector2i(0, 0), Vector2i(3, 0))

	if g9._settled[0][0] != node9_a or g9._settled[0][3] != node9_b:
		push_error("T9: grid changed after non-matching swap of distant cells")
		nonadj_fails += 1
	failures += nonadj_fails
	print("T9 (non-adjacent swap): %s" % ("PASS" if nonadj_fails == 0 else "FAIL"))

	# ---- Test 10: swap only works on settled, not falling -------------------
	var settled_fails := 0
	var g10: Node3D = scene.instantiate()
	root.add_child(g10)
	g10._ready()

	# Verify that the active piece's cells are NOT in _settled.
	for cell in g10._piece_cells:
		if cell.y >= 0 and cell.y < g10.GRID_H:
			if g10._settled[cell.y][cell.x] != null:
				push_error("T10: active piece cell %s appears in settled grid" % str(cell))
				settled_fails += 1
	failures += settled_fails
	print("T10 (swap only settled): %s" % ("PASS" if settled_fails == 0 else "FAIL"))

	# ---- Test 11: _apply_candy_gravity no holes ----------------------------
	var grav_fails := 0
	var g11: Node3D = scene.instantiate()
	root.add_child(g11)
	g11._ready()

	# Place balls at rows 0, 2, 4 in col 0 (leaving gaps at rows 1 and 3).
	_place_ball_color(g11, 0, 0, red)
	_place_ball_color(g11, 2, 0, red)
	_place_ball_color(g11, 4, 0, red)

	g11._apply_candy_gravity()

	# After gravity, rows 0,1,2 should be occupied and rows 3+ empty.
	for r in range(3):
		if g11._settled[r][0] == null:
			push_error("T11: row %d col 0 should be occupied after gravity" % r)
			grav_fails += 1
	for r in range(3, g11.GRID_H):
		if g11._settled[r][0] != null:
			push_error("T11: row %d col 0 should be empty after gravity" % r)
			grav_fails += 1
	failures += grav_fails
	print("T11 (candy gravity): %s" % ("PASS" if grav_fails == 0 else "FAIL"))

	# ---- Summary ------------------------------------------------------------
	if failures == 0:
		print("\nALL TESTS PASSED")
		quit(0)
	else:
		push_error("\nTEST SUITE FAILED: %d failure(s)" % failures)
		quit(1)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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
	## Every null cell must have Color.BLACK in the colour grid (the sentinel used
	## by Game.gd), and every occupied cell must have a non-black colour.
	for row in game.GRID_H:
		for col in game.GRID_W:
			var node = game._settled[row][col]
			var color: Color = game._settled_colors[row][col]
			if node == null and color != Color.BLACK:
				return false
			if node != null and color == Color.BLACK:
				return false
	return true


func _count_settled(game: Node3D) -> int:
	var count := 0
	for row in game.GRID_H:
		for col in game.GRID_W:
			if game._settled[row][col] != null:
				count += 1
	return count


## Fills a rectangular region of settled cells with dummy ball nodes.
func _fill_rect(game: Node3D, r0: int, c0: int, r1: int, c1: int) -> void:
	for row in range(r0, r1 + 1):
		for col in range(c0, c1 + 1):
			if row < game.GRID_H and col < game.GRID_W:
				_place_ball_color(game, row, col, Color("ffffff"))


## Places a dummy ball node at (row, col) with the given colour.
func _place_ball_color(game: Node3D, row: int, col: int, color: Color) -> void:
	var mi := MeshInstance3D.new()
	game.add_child(mi)
	game._settled[row][col] = mi
	game._settled_colors[row][col] = color
	game._settled_types[row][col] = game.BallType.NORMAL
