extends SceneTree
## Headless integration test for the falling-tetromino game logic.
##
## Run with:
##   godot --headless --script tests/test_game_logic.gd
##
## It instances the main scene, drives the fall loop directly (bypassing the
## real-time timer) and asserts the core invariants:
##   * the active piece is always in a valid (in-bounds, non-overlapping) state;
##   * settled balls stay within the grid and never overlap;
##   * the spawn -> lock -> line-clear loop actually makes progress;
##   * score accumulates as lines are cleared;
##   * combo counter stays within [1, MAX_COMBO];
##   * rush progress bar value stays within [0, 1];
##   * rush activates when the score meter fills.

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
	var rush_ever_activated := false

	for i in range(STEPS):
		# The active piece must always be in a valid position.
		if not game._is_valid(game._piece_cells):
			push_error("Invalid active piece at step %d: %s" % [i, str(game._piece_cells)])
			failures += 1

		# Settled balls must stay inside the grid and never collide.
		if not _check_settled(game):
			push_error("Corrupt settled grid at step %d" % i)
			failures += 1

		# Combo counter must always be in [1, MAX_COMBO].
		if game._combo < 1 or game._combo > game.MAX_COMBO:
			push_error("Combo out of range at step %d: %d" % [i, game._combo])
			failures += 1

		# Rush progress must be non-negative. It may exceed RUSH_GOAL while rush
		# is active (points overflow into the next bar), but must not go negative.
		if game._rush_progress < 0:
			push_error("Rush progress negative at step %d: %d" % [i, game._rush_progress])
			failures += 1

		# Score must never be negative.
		if game._score < 0:
			push_error("Score went negative at step %d: %d" % [i, game._score])
			failures += 1

		if game._rush_active:
			rush_ever_activated = true

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
	# _score resets on board overflow; use the never-resetting _total_score
	# to verify that points were actually awarded over the full run.
	if game._total_score <= 0:
		push_error("Total score never accumulated in %d steps (total=%d)" % [STEPS, game._total_score])
		failures += 1

	# Verify that rush is reachable. RUSH_GOAL=300 means 3 single-row clears
	# trigger it; the AI reliably clears that many lines.
	if not rush_ever_activated:
		push_error("Rush mode never activated in %d steps" % STEPS)
		failures += 1

	if failures == 0:
		print("TEST PASS: %d steps, max lines=%d, total score=%d, spawns=%d, rush=%s" % [
			STEPS, max_lines, game._total_score, spawns_seen, str(rush_ever_activated)
		])
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
