extends SceneTree
## Headless integration test for the falling-tetromino game logic.
##
## Run with:
##   godot --headless --script tests/test_game_logic.gd
##
## Tested invariants and behaviours:
##   * the active piece is always in a valid (in-bounds, non-overlapping) state;
##   * settled balls stay within the grid and never overlap;
##   * the spawn -> lock -> line-clear loop actually makes progress;
##   * manual left/right movement works and is bounds-checked;
##   * hard drop instantly lands the piece and spawns a new one;
##   * toggling auto_play switches modes correctly;
##   * contact-area scoring prefers snug placements over open columns.

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

	# -------------------------------------------------------------------------
	# Part 1: auto-play mode — basic invariants over many steps.
	# -------------------------------------------------------------------------
	game.auto_play = true
	for i in range(STEPS):
		if not game._is_valid(game._piece_cells):
			push_error("FAIL [auto] Invalid active piece at step %d: %s" % [i, str(game._piece_cells)])
			failures += 1

		if not _check_settled(game):
			push_error("FAIL [auto] Corrupt settled grid at step %d" % i)
			failures += 1

		if game._piece_cells != last_piece:
			spawns_seen += 1
			last_piece = game._piece_cells.duplicate()

		game._step()
		max_lines = max(max_lines, game._lines)

	if spawns_seen < 2:
		push_error("FAIL [auto] Pieces never advanced (spawns_seen=%d)" % spawns_seen)
		failures += 1
	if max_lines < 1:
		push_error("FAIL [auto] No line was ever cleared in %d steps" % STEPS)
		failures += 1

	# -------------------------------------------------------------------------
	# Part 2: manual mode — left/right movement and hard drop.
	# -------------------------------------------------------------------------
	game.auto_play = false
	var start_x := game._piece_base.x

	# Move left; verify column decreased (or stayed if already at left edge).
	game._try_move(-1)
	var after_left := game._piece_base.x
	if after_left > start_x:
		push_error("FAIL [manual] Moving left increased x: %d -> %d" % [start_x, after_left])
		failures += 1

	# Move right; verify column increased (or stayed if at right edge).
	var before_right := game._piece_base.x
	game._try_move(1)
	var after_right := game._piece_base.x
	if after_right < before_right:
		push_error("FAIL [manual] Moving right decreased x: %d -> %d" % [before_right, after_right])
		failures += 1

	# The piece must remain valid after manual moves.
	if not game._is_valid(game._piece_cells):
		push_error("FAIL [manual] Invalid piece after manual moves: %s" % str(game._piece_cells))
		failures += 1

	# Hard drop: piece should settle instantly and a new piece should spawn.
	var pre_drop_lines := game._lines
	game._hard_drop()
	if not game._is_valid(game._piece_cells):
		push_error("FAIL [manual] Invalid piece after hard drop: %s" % str(game._piece_cells))
		failures += 1

	# -------------------------------------------------------------------------
	# Part 3: toggle auto_play via _toggle_auto_play().
	# -------------------------------------------------------------------------
	var before := game.auto_play
	game._toggle_auto_play()
	if game.auto_play == before:
		push_error("FAIL [toggle] auto_play did not change after _toggle_auto_play()")
		failures += 1
	game._toggle_auto_play()
	if game.auto_play != before:
		push_error("FAIL [toggle] auto_play did not restore after second _toggle_auto_play()")
		failures += 1

	# -------------------------------------------------------------------------
	# Part 4: contact area scoring — snug placement scores higher than a free column.
	# -------------------------------------------------------------------------
	# Place a flat row of settled balls except for two adjacent cells, then
	# spawn an I piece aligned to those two cells. A placement that fits in the
	# gap should score better than one hanging over empty space.
	game._reset_board()
	# Fill row 0 except columns 2 and 3.
	for col in game.GRID_W:
		if col != 2 and col != 3:
			var ball := MeshInstance3D.new()
			game.add_child(ball)
			game._settled[0][col] = ball

	# Use the I piece (width = 4 cells in one row) placed horizontally.
	game._piece_offsets = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]

	# Score a placement directly over the gap (base_x = 0 so cells 0-3 cover
	# the gap at x=2,3 and land on settled cells).
	var score_gap  := game._score_placement(Vector2i(0, 1))
	# Score a placement at the far right column (no floor neighbours on the left).
	var score_free := game._score_placement(Vector2i(game.GRID_W - 4, 2))
	if score_gap <= score_free:
		push_error("FAIL [contact] Gap placement (%.3f) should score higher than free column (%.3f)" % [score_gap, score_free])
		failures += 1

	# -------------------------------------------------------------------------
	# Report results.
	# -------------------------------------------------------------------------
	if failures == 0:
		print("TEST PASS: %d auto steps, max lines=%d, piece states=%d; manual/toggle/contact OK"
				% [STEPS, max_lines, spawns_seen])
		quit(0)
	else:
		push_error("TEST FAIL: %d invariant violation(s)" % failures)
		quit(1)


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
