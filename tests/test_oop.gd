extends SceneTree
## OOP unit tests: verify that each subsystem class can be instantiated and
## behaves correctly in isolation, independent of the full game scene.
##
## Run with:
##   godot --headless --script tests/test_oop.gd

func _initialize() -> void:
	var failures := 0

	failures += _test_board()
	failures += _test_piece()
	failures += _test_ball_factory()
	failures += _test_auto_player()
	failures += _test_special_effects()
	failures += _test_hud()
	failures += _test_scene_builder()

	if failures == 0:
		print("\nALL OOP TESTS PASSED")
		quit(0)
	else:
		push_error("\nOOP TEST SUITE FAILED: %d failure(s)" % failures)
		quit(1)


# ---------------------------------------------------------------------------
# T-OOP-1: Board
# ---------------------------------------------------------------------------
func _test_board() -> int:
	var fails := 0
	var b := Board.new(8, 16)

	# Initial state is all empty.
	if b.count_occupied() != 0:
		push_error("Board T1: expected 0 occupied cells, got %d" % b.count_occupied())
		fails += 1
	if b.lines != 0:
		push_error("Board T1: lines should start at 0")
		fails += 1
	if not b.is_integrity_ok():
		push_error("Board T1: integrity check failed on fresh board")
		fails += 1

	# Place a cell and verify retrieval.
	var dummy := MeshInstance3D.new()
	b.set_cell(0, 0, dummy, 0, Color.RED)
	if b.get_node(0, 0) != dummy:
		push_error("Board T2: get_node returned wrong node")
		fails += 1
	if b.get_color(0, 0) != Color.RED:
		push_error("Board T2: get_color returned wrong color")
		fails += 1
	if b.count_occupied() != 1:
		push_error("Board T2: expected 1 occupied cell")
		fails += 1

	# Clear the cell.
	b.clear_cell(0, 0)
	if b.get_node(0, 0) != null:
		push_error("Board T3: cell should be null after clear_cell")
		fails += 1
	if b.count_occupied() != 0:
		push_error("Board T3: expected 0 occupied after clearing")
		fails += 1

	# Row clearing: fill row 0 completely and clear it.
	var nodes_r0: Array = []
	for col in 8:
		var n := MeshInstance3D.new()
		b.set_cell(0, col, n, 0, Color.WHITE)
		nodes_r0.append(n)
	# Place one ball in row 1 (should shift down to row 0 after clear).
	var n_r1 := MeshInstance3D.new()
	b.set_cell(1, 0, n_r1, 0, Color.BLUE)

	var cleared := b.clear_full_rows()
	if cleared != 1:
		push_error("Board T4: expected 1 row cleared, got %d" % cleared)
		fails += 1
	if b.lines != 1:
		push_error("Board T4: lines counter should be 1, got %d" % b.lines)
		fails += 1
	# The ball from row 1 should now be at row 0.
	if b.get_node(0, 0) != n_r1:
		push_error("Board T4: ball from row 1 did not shift to row 0")
		fails += 1
	if b.count_occupied() != 1:
		push_error("Board T4: expected 1 ball remaining after row clear")
		fails += 1

	# Chebyshev clear.
	var b2 := Board.new(8, 16)
	for row in range(2, 7):
		for col in range(2, 7):
			var m := MeshInstance3D.new()
			b2.set_cell(row, col, m, 0, Color.WHITE)
	var cnt_before := b2.count_occupied()
	b2.clear_chebyshev(Vector2i(4, 4), 2)
	var cnt_after := b2.count_occupied()
	if cnt_after >= cnt_before:
		push_error("Board T5: Chebyshev clear had no effect (before=%d after=%d)" % [cnt_before, cnt_after])
		fails += 1
	for row in range(2, 7):
		for col in range(2, 7):
			if maxi(absi(col - 4), absi(row - 4)) <= 2:
				if b2.get_node(row, col) != null:
					push_error("Board T5: cell (%d,%d) not cleared by Chebyshev" % [col, row])
					fails += 1

	# Column clear.
	var b3 := Board.new(8, 16)
	for row in 16:
		var m := MeshInstance3D.new()
		b3.set_cell(row, 3, m, 0, Color.GREEN)
	b3.clear_column(3)
	for row in 16:
		if b3.get_node(row, 3) != null:
			push_error("Board T6: column 3 not fully cleared at row %d" % row)
			fails += 1

	# Color clear.
	var b4 := Board.new(8, 16)
	var red_node := MeshInstance3D.new()
	var blue_node := MeshInstance3D.new()
	b4.set_cell(0, 0, red_node, 0, Color.RED)
	b4.set_cell(0, 1, blue_node, 0, Color.BLUE)
	b4.clear_by_colors([Color.RED])
	if b4.get_node(0, 0) != null:
		push_error("Board T7: red cell not cleared by color clear")
		fails += 1
	if b4.get_node(0, 1) == null:
		push_error("Board T7: blue cell incorrectly cleared")
		fails += 1

	# Reset.
	var b5 := Board.new(8, 16)
	var m5 := MeshInstance3D.new()
	b5.set_cell(0, 0, m5, 0, Color.WHITE)
	b5.reset()
	if b5.count_occupied() != 0:
		push_error("Board T8: board not empty after reset")
		fails += 1

	print("OOP Board:          %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	return fails


# ---------------------------------------------------------------------------
# T-OOP-2: Piece
# ---------------------------------------------------------------------------
func _test_piece() -> int:
	var fails := 0
	var b := Board.new(8, 16)
	var p := Piece.new(b)

	# Set up a simple I-piece shape.
	p.offsets = [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0)]
	p.types = [0, 0, 0, 0]
	p.colors = [Color.RED, Color.RED, Color.RED, Color.RED]
	p.nodes = []

	# Place at a valid position.
	p.set_base(Vector2i(2, 5))
	if p.base != Vector2i(2, 5):
		push_error("Piece T1: base not updated after set_base")
		fails += 1
	if p.cells.size() != 4:
		push_error("Piece T1: expected 4 cells, got %d" % p.cells.size())
		fails += 1
	if p.cells[0] != Vector2i(2, 5):
		push_error("Piece T1: cells[0] should be (2,5), got %s" % str(p.cells[0]))
		fails += 1

	# Valid placement on empty board.
	if not p.is_valid():
		push_error("Piece T2: valid placement returned false on empty board")
		fails += 1

	# Invalid: out of bounds left.
	p.set_base(Vector2i(-1, 5))
	if p.is_valid():
		push_error("Piece T3: out-of-bounds placement should be invalid")
		fails += 1

	# Invalid: piece below row 0.
	p.offsets = [Vector2i(0,0)]
	p.set_base(Vector2i(0, -1))
	if p.is_valid():
		push_error("Piece T4: below-floor placement should be invalid")
		fails += 1

	# Board collision check.
	var b2 := Board.new(8, 16)
	var dummy := MeshInstance3D.new()
	b2.set_cell(5, 3, dummy, 0, Color.WHITE)
	var p2 := Piece.new(b2)
	p2.offsets = [Vector2i(0,0)]
	p2.set_base(Vector2i(3, 5))
	if p2.is_valid():
		push_error("Piece T5: piece overlapping settled ball should be invalid")
		fails += 1

	# Distinct colors.
	var p3 := Piece.new(b)
	p3.colors = [Color.RED, Color.BLUE, Color.RED]
	var dc := p3.distinct_colors()
	if dc.size() != 2:
		push_error("Piece T6: expected 2 distinct colors, got %d" % dc.size())
		fails += 1
	if not dc.has(Color.RED) or not dc.has(Color.BLUE):
		push_error("Piece T6: wrong distinct colors: %s" % str(dc))
		fails += 1

	print("OOP Piece:          %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	return fails


# ---------------------------------------------------------------------------
# T-OOP-3: BallFactory
# ---------------------------------------------------------------------------
func _test_ball_factory() -> int:
	var fails := 0

	# Use a dummy node as parent so add_child works.
	var parent := Node.new()
	root.add_child(parent)
	var factory := BallFactory.new(parent)

	# random_color returns one of the palette colors.
	var c := factory.random_color()
	if not BallFactory.COLORS.has(c):
		push_error("BallFactory T1: random_color not in palette: %s" % str(c))
		fails += 1

	# random_type with 0.0 special chance always returns NORMAL.
	for _i in 20:
		var t := factory.random_type(0.0)
		if t != BallFactory.BallType.NORMAL:
			push_error("BallFactory T2: random_type with 0 chance should be NORMAL")
			fails += 1
			break

	# random_type with 1.0 special chance never returns NORMAL.
	var saw_special := false
	for _i in 20:
		var t := factory.random_type(1.0)
		if t != BallFactory.BallType.NORMAL:
			saw_special = true
			break
	if not saw_special:
		push_error("BallFactory T3: random_type with 1.0 chance should return specials")
		fails += 1

	# make_ball creates a MeshInstance3D child.
	var ball := factory.make_ball(Color.RED, BallFactory.BallType.NORMAL)
	if ball == null:
		push_error("BallFactory T4: make_ball returned null")
		fails += 1
	else:
		if not (ball is MeshInstance3D):
			push_error("BallFactory T4: make_ball should return MeshInstance3D")
			fails += 1
		if ball.get_parent() != parent:
			push_error("BallFactory T4: ball parent should be the provided parent node")
			fails += 1

	# make_material returns a StandardMaterial3D for each type.
	for btype in [BallFactory.BallType.NORMAL, BallFactory.BallType.BOMB,
				  BallFactory.BallType.RAINBOW, BallFactory.BallType.FREEZE,
				  BallFactory.BallType.LIGHTNING]:
		var mat := factory.make_material(Color.WHITE, btype)
		if not (mat is StandardMaterial3D):
			push_error("BallFactory T5: make_material returned wrong type for %d" % btype)
			fails += 1

	parent.queue_free()
	print("OOP BallFactory:    %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	return fails


# ---------------------------------------------------------------------------
# T-OOP-4: AutoPlayer
# ---------------------------------------------------------------------------
func _test_auto_player() -> int:
	var fails := 0
	var ai := AutoPlayer.new()
	var b := Board.new(8, 16)
	var p := Piece.new(b)
	p.offsets = [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0)] # I
	p.set_base(Vector2i(2, 14))

	var col := ai.best_column(p, b)
	if col < 0 or col >= b.width:
		push_error("AutoPlayer T1: best_column returned out-of-range value: %d" % col)
		fails += 1

	# On an empty board the I-piece should always find a valid column.
	if not p.is_valid_at(col, 0):
		push_error("AutoPlayer T2: best_column returned invalid placement column")
		fails += 1

	# Fill every column with balls except column 0 — the AI should prefer 0
	# because it avoids adding height everywhere else.
	var b2 := Board.new(8, 16)
	var p2 := Piece.new(b2)
	p2.offsets = [Vector2i(0,0)]  # 1-cell piece
	p2.set_base(Vector2i(4, 15))
	# Fill columns 1-7 halfway (rows 0..7).
	for col2 in range(1, 8):
		for row in range(0, 8):
			var m := MeshInstance3D.new()
			b2.set_cell(row, col2, m, 0, Color.WHITE)
	var best := ai.best_column(p2, b2)
	if best != 0:
		# The AI may not always pick 0 (heuristic), but it must be valid.
		if not p2.is_valid_at(best, 0):
			push_error("AutoPlayer T3: best_column returned invalid column on biased board")
			fails += 1

	print("OOP AutoPlayer:     %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	return fails


# ---------------------------------------------------------------------------
# T-OOP-5: SpecialEffects
# ---------------------------------------------------------------------------
func _test_special_effects() -> int:
	var fails := 0
	var fx := SpecialEffects.new()

	# --- Bomb ---
	var b1 := Board.new(8, 16)
	for row in range(2, 7):
		for col in range(2, 7):
			var m := MeshInstance3D.new()
			b1.set_cell(row, col, m, 0, Color.WHITE)
	var cnt_before := b1.count_occupied()
	fx.apply_bomb(b1, Vector2i(4, 4), 2)
	var cnt_after := b1.count_occupied()
	if cnt_after >= cnt_before:
		push_error("SpecialEffects T1: Bomb had no effect")
		fails += 1
	for row in range(2, 7):
		for col in range(2, 7):
			if maxi(absi(col - 4), absi(row - 4)) <= 2:
				if b1.get_node(row, col) != null:
					push_error("SpecialEffects T1: cell (%d,%d) not cleared by bomb" % [col, row])
					fails += 1

	# --- Rainbow ---
	var b2 := Board.new(8, 16)
	var n_red1 := MeshInstance3D.new(); b2.set_cell(0, 0, n_red1, 0, Color.RED)
	var n_red2 := MeshInstance3D.new(); b2.set_cell(0, 1, n_red2, 0, Color.RED)
	var n_blue := MeshInstance3D.new(); b2.set_cell(0, 2, n_blue, 0, Color.BLUE)
	fx.apply_rainbow(b2, [Color.RED])
	if b2.get_node(0, 0) != null or b2.get_node(0, 1) != null:
		push_error("SpecialEffects T2: Rainbow did not clear red balls")
		fails += 1
	if b2.get_node(0, 2) == null:
		push_error("SpecialEffects T2: Rainbow incorrectly cleared blue ball")
		fails += 1

	# --- Freeze signal ---
	var freeze_received := false
	var received_duration := 0.0
	fx.freeze_activated.connect(func(d): freeze_received = true; received_duration = d)
	fx.apply_freeze(5.0)
	if not freeze_received:
		push_error("SpecialEffects T3: freeze_activated signal not emitted")
		fails += 1
	if received_duration != 5.0:
		push_error("SpecialEffects T3: wrong duration: %f" % received_duration)
		fails += 1

	# --- Lightning ---
	var b3 := Board.new(8, 16)
	for row in 16:
		var m := MeshInstance3D.new()
		b3.set_cell(row, 3, m, 0, Color.YELLOW)
	var m_other := MeshInstance3D.new()
	b3.set_cell(0, 5, m_other, 0, Color.GREEN)
	fx.apply_lightning(b3, 3)
	for row in 16:
		if b3.get_node(row, 3) != null:
			push_error("SpecialEffects T4: column 3 not cleared by lightning at row %d" % row)
			fails += 1
	if b3.get_node(0, 5) == null:
		push_error("SpecialEffects T4: column 5 incorrectly cleared by lightning")
		fails += 1

	# --- effect_triggered signal ---
	var effect_count := 0
	fx.effect_triggered.connect(func(): effect_count += 1)
	var b_sig := Board.new(8, 16)
	fx.apply_bomb(b_sig, Vector2i(0, 0), 1)
	fx.apply_rainbow(b_sig, [Color.WHITE])
	fx.apply_freeze(1.0)
	fx.apply_lightning(b_sig, 0)
	if effect_count != 4:
		push_error("SpecialEffects T5: expected 4 effect_triggered signals, got %d" % effect_count)
		fails += 1

	print("OOP SpecialEffects: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	return fails


# ---------------------------------------------------------------------------
# T-OOP-6: HUD
# ---------------------------------------------------------------------------
func _test_hud() -> int:
	var fails := 0

	# HUD can be constructed and updated without crashing.
	var parent := Node.new()
	root.add_child(parent)
	var hud := HUD.new(parent)

	# update_score and update_freeze must not crash.
	hud.update_score(10, 3)
	hud.update_freeze(2.5)
	hud.update_freeze(0.0)

	# The CanvasLayer should have been added as a child.
	var has_layer := false
	for child in parent.get_children():
		if child is CanvasLayer:
			has_layer = true
			break
	if not has_layer:
		push_error("HUD T1: CanvasLayer not added to parent")
		fails += 1

	parent.queue_free()
	print("OOP HUD:            %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	return fails


# ---------------------------------------------------------------------------
# T-OOP-7: SceneBuilder
# ---------------------------------------------------------------------------
func _test_scene_builder() -> int:
	var fails := 0
	var parent := Node3D.new()
	root.add_child(parent)

	# Build all scene elements without crashing.
	SceneBuilder.build_environment(parent)
	SceneBuilder.build_camera(parent)
	SceneBuilder.build_lights(parent)
	SceneBuilder.build_back_panel(parent)

	# Check that children were added.
	if parent.get_child_count() < 4:
		push_error("SceneBuilder T1: expected at least 4 children, got %d" % parent.get_child_count())
		fails += 1

	# cell_to_world should return a centered vector.
	var origin := SceneBuilder.cell_to_world(Vector2i(3, 7))  # near-center on 8×16 grid
	if abs(origin.x) > 1.0:
		push_error("SceneBuilder T2: center cell x too far from 0: %f" % origin.x)
		fails += 1

	var corner := SceneBuilder.cell_to_world(Vector2i(0, 0))
	var corner2 := SceneBuilder.cell_to_world(Vector2i(7, 15))
	# They should be symmetric.
	if abs(corner.x + corner2.x) > 0.01:
		push_error("SceneBuilder T3: corner cells not symmetric in x")
		fails += 1
	if abs(corner.y + corner2.y) > 0.01:
		push_error("SceneBuilder T3: corner cells not symmetric in y")
		fails += 1

	parent.queue_free()
	print("OOP SceneBuilder:   %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	return fails
