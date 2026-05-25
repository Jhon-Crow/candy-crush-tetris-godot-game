extends Node3D
## Candy Crush + Tetris — primitive auto-falling implementation.
##
## Tetromino pieces made of multicoloured candy crystal shards fall automatically
## down a grid. The game is played on a flat playfield, but everything is rendered
## in a true 3D scene (real faceted crystal meshes, lighting, transparency and
## refraction) so the visuals can be elaborated on later.
##
## There is no human input yet. When [member auto_play] is enabled (the default)
## a lightweight heuristic steers each piece toward the column that keeps the
## stack flat and clears rows — this is the "automatic control of the falling
## figures" requested in the issue. With it disabled, pieces simply drop down
## the centre. Either way, full rows are cleared and the board resets when it
## overflows.

# --- Board configuration -----------------------------------------------------
const GRID_W := 8        # columns
const GRID_H := 16       # rows (row 0 = bottom)
const CELL := 1.0        # world units per cell

## Seconds between downward logical steps. Larger value → slower, more time for
## the smooth glide to animate between positions.
const FALL_INTERVAL := 0.55

## Exponential-smoothing speed for the visual glide (λ in 1 − e^(−λΔt)).
## Higher = catches up faster; lower = more lag / trailing feel.
const GLIDE_LAMBDA := 12.0

## When true, pieces are automatically steered toward a good landing column.
@export var auto_play := true

# Crystal colour palette — semi-saturated jewel tones that read well through
# transparency (avoid pure-white or near-white that look washed out when alpha
# is applied).
const COLORS := [
	Color(0.95, 0.22, 0.35, 1.0), # ruby
	Color(0.95, 0.52, 0.10, 1.0), # amber
	Color(0.92, 0.80, 0.12, 1.0), # citrine
	Color(0.18, 0.78, 0.35, 1.0), # emerald
	Color(0.18, 0.60, 0.95, 1.0), # sapphire
	Color(0.52, 0.30, 0.92, 1.0), # amethyst
	Color(0.90, 0.38, 0.72, 1.0), # rose quartz
]

# Tetromino shapes as cell offsets (x right, y up), each normalised so the
# minimum x and y are 0. Spawned upright (no rotation in this primitive build).
const SHAPES := [
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], # I
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], # O
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)], # T
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)], # S
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)], # Z
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)], # J
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)], # L
]

# Four-feature placement heuristic used by the auto-player. The weights are the
# genetic-algorithm-tuned values from Code My Road's "Tetris AI – The (Near)
# Perfect Player" (aggregate height, complete lines, holes, bumpiness).
# https://codemyroad.wordpress.com/2013/04/14/tetris-ai-the-near-perfect-player/
const W_HEIGHT := -0.51
const W_LINES := 0.76
const W_HOLES := -0.36
const W_BUMPY := -0.18

# --- Runtime state -----------------------------------------------------------
var _settled: Array = []          # _settled[row][col] -> MeshInstance3D or null
var _piece_offsets: Array = []    # Array[Vector2i] shape offsets of active piece
var _piece_base := Vector2i.ZERO  # bottom-left anchor of the active piece
var _piece_nodes: Array = []      # Array[MeshInstance3D] parallel to _piece_offsets
var _piece_cells: Array = []      # cached absolute cells (= base + offsets)
var _target_x := 0                # auto-player's desired anchor column
var _fall_timer := 0.0
var _lines := 0
var _crystal_mesh: CylinderMesh   # shared low-poly hex-prism mesh for all crystals
var _lines_label: Label


func _ready() -> void:
	randomize()
	_build_environment()
	_build_camera()
	_build_lights()
	_build_back_panel()
	_build_hud()
	_init_grid()
	# Build a shared low-polygon CylinderMesh (hexagonal prism) that gives every
	# piece a clearly faceted crystal / gem silhouette.
	_crystal_mesh = CylinderMesh.new()
	_crystal_mesh.top_radius = 0.40
	_crystal_mesh.bottom_radius = 0.40
	_crystal_mesh.height = 0.80
	# 6 radial segments → hexagonal prism; each flat face reads as a crystal
	# facet. rings = 1 keeps height subdivision minimal.
	_crystal_mesh.radial_segments = 6
	_crystal_mesh.rings = 1
	_spawn_piece()


func _process(delta: float) -> void:
	_fall_timer += delta
	if _fall_timer >= FALL_INTERVAL:
		_fall_timer -= FALL_INTERVAL
		_step()

	# Smoothly glide active crystals toward their logical grid position using
	# exponential smoothing: pos += (target - pos) * (1 − e^(−λΔt)).
	# This gives a natural ease-out that is frame-rate independent and never
	# snaps, unlike move_toward which can produce a visible jerk on the last step.
	var alpha := 1.0 - exp(-GLIDE_LAMBDA * delta)
	for i in _piece_nodes.size():
		var node: MeshInstance3D = _piece_nodes[i]
		node.position = node.position.lerp(_cell_to_world(_piece_cells[i]), alpha)


# --- Game loop ---------------------------------------------------------------
func _step() -> void:
	var dx := 0
	if auto_play and _piece_base.x != _target_x:
		dx = signi(_target_x - _piece_base.x)

	var down := _piece_base + Vector2i(0, -1)
	if dx != 0 and _placement_valid(down + Vector2i(dx, 0)):
		# Glide diagonally toward the target column while descending.
		_set_base(down + Vector2i(dx, 0))
	elif _placement_valid(down):
		_set_base(down)
	elif dx != 0 and _placement_valid(_piece_base + Vector2i(dx, 0)):
		# Can't descend yet, but can still shuffle toward the target.
		_set_base(_piece_base + Vector2i(dx, 0))
	else:
		_lock_piece()
		_clear_full_rows()
		_spawn_piece()


func _spawn_piece() -> void:
	var shape: Array = SHAPES[randi() % SHAPES.size()]
	var max_x := 0
	var max_y := 0
	for o in shape:
		max_x = max(max_x, o.x)
		max_y = max(max_y, o.y)

	_piece_offsets = shape
	# Centre the shape horizontally and drop it from the top row.
	_piece_base = Vector2i(int((GRID_W - (max_x + 1)) / 2.0), GRID_H - 1 - max_y)
	_target_x = _best_target_column() if auto_play else _piece_base.x

	_piece_nodes = []
	# All cells in one piece share a colour so they read as a single crystal.
	var piece_color := COLORS[randi() % COLORS.size()]
	for o in shape:
		var crystal := _make_crystal(piece_color)
		# Start one cell higher so the piece glides into view.
		crystal.position = _cell_to_world(_piece_base + o + Vector2i(0, 1))
		_piece_nodes.append(crystal)
	_refresh_cells()

	# If the spawn space is occupied, the board has overflowed. Clear the
	# settled crystals and keep this fresh piece (which now fits on the empty
	# board) so the demo restarts seamlessly.
	if not _is_valid(_piece_cells):
		_reset_board()


func _lock_piece() -> void:
	for i in _piece_cells.size():
		var cell: Vector2i = _piece_cells[i]
		var node: MeshInstance3D = _piece_nodes[i]
		node.position = _cell_to_world(cell)
		if cell.y >= 0 and cell.y < GRID_H:
			_settled[cell.y][cell.x] = node
	_piece_nodes = []
	_piece_cells = []


func _clear_full_rows() -> void:
	var row := 0
	while row < GRID_H:
		var full := true
		for col in GRID_W:
			if _settled[row][col] == null:
				full = false
				break
		if full:
			for col in GRID_W:
				_settled[row][col].queue_free()
				_settled[row][col] = null
			# Shift every row above down by one.
			for r in range(row, GRID_H - 1):
				for col in GRID_W:
					var node: MeshInstance3D = _settled[r + 1][col]
					_settled[r][col] = node
					if node != null:
						node.position = _cell_to_world(Vector2i(col, r))
			for col in GRID_W:
				_settled[GRID_H - 1][col] = null
			_lines += 1
			_update_hud()
			# Re-check the same row index (it now holds the row that fell down).
		else:
			row += 1


## Empties the settled board after an overflow. The active piece is left
## untouched so play continues immediately on the cleared board.
func _reset_board() -> void:
	for row in GRID_H:
		for col in GRID_W:
			if _settled[row][col] != null:
				_settled[row][col].queue_free()
				_settled[row][col] = null
	_lines = 0
	_update_hud()


# --- Auto-player -------------------------------------------------------------
## Returns the anchor column that yields the best board score for the current
## shape, dropped straight down (no rotation in this primitive build).
func _best_target_column() -> int:
	var max_x := 0
	for o in _piece_offsets:
		max_x = max(max_x, o.x)

	var best_x := _piece_base.x
	var best_score := -INF
	for base_x in range(0, GRID_W - max_x):
		var base_y := _drop_row(base_x)
		if base_y == GRID_H:  # column blocked all the way up
			continue
		var score := _score_placement(Vector2i(base_x, base_y))
		if score > best_score:
			best_score = score
			best_x = base_x
	return best_x


## Lowest valid anchor row for the active shape dropped at [param base_x].
## Returns GRID_H when no valid placement exists.
func _drop_row(base_x: int) -> int:
	var by := GRID_H
	while by > 0 and _placement_valid_at(base_x, by - 1):
		by -= 1
	return by if _placement_valid_at(base_x, by) else GRID_H


func _score_placement(base: Vector2i) -> float:
	# Build an occupancy snapshot with the candidate piece added.
	var occ: Array = []
	for row in GRID_H:
		var line: Array = []
		for col in GRID_W:
			line.append(_settled[row][col] != null)
		occ.append(line)
	for o in _piece_offsets:
		var c: Vector2i = base + o
		if c.y >= 0 and c.y < GRID_H:
			occ[c.y][c.x] = true

	var heights: Array = []
	var holes := 0
	for col in GRID_W:
		var top := -1
		for row in range(GRID_H - 1, -1, -1):
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
	for col in range(GRID_W - 1):
		bumpiness += abs(heights[col] - heights[col + 1])
	var lines := 0
	for row in GRID_H:
		var full := true
		for col in GRID_W:
			if not occ[row][col]:
				full = false
				break
		if full:
			lines += 1

	return W_HEIGHT * aggregate + W_LINES * lines + W_HOLES * holes + W_BUMPY * bumpiness


# --- Helpers -----------------------------------------------------------------
func _init_grid() -> void:
	_settled = []
	for row in GRID_H:
		var line: Array = []
		for col in GRID_W:
			line.append(null)
		_settled.append(line)


func _set_base(base: Vector2i) -> void:
	_piece_base = base
	_refresh_cells()


func _refresh_cells() -> void:
	_piece_cells = []
	for o in _piece_offsets:
		_piece_cells.append(_piece_base + o)


func _placement_valid(base: Vector2i) -> bool:
	return _placement_valid_at(base.x, base.y)


func _placement_valid_at(base_x: int, base_y: int) -> bool:
	for o in _piece_offsets:
		var cell: Vector2i = Vector2i(base_x, base_y) + o
		if cell.x < 0 or cell.x >= GRID_W or cell.y < 0:
			return false
		if cell.y < GRID_H and _settled[cell.y][cell.x] != null:
			return false
	return true


func _is_valid(cells: Array) -> bool:
	for cell in cells:
		if cell.x < 0 or cell.x >= GRID_W or cell.y < 0:
			return false
		if cell.y < GRID_H and _settled[cell.y][cell.x] != null:
			return false
	return true


func _cell_to_world(cell: Vector2i) -> Vector3:
	# Centre the board on the world origin.
	var x := (cell.x - (GRID_W - 1) / 2.0) * CELL
	var y := (cell.y - (GRID_H - 1) / 2.0) * CELL
	return Vector3(x, y, 0.0)


## Creates a faceted crystal MeshInstance3D with the given jewel colour.
##
## Visual design goals (issue #13):
##   • Subtle highlights — low rim tinted toward albedo; very low emission.
##   • Faceted silhouette — shared hexagonal-prism mesh (_crystal_mesh) reads as
##     a cut gemstone without any custom mesh data.
##   • Glass-like surface — high metallic_specular + low roughness produces sharp
##     Fresnel-like highlights on each facet edge.
##
## NOTE: This project uses the GL Compatibility renderer (see project.godot),
## required for single-threaded Web export. Advanced material features such as
## transparency, refraction, and clearcoat are either unsupported (refraction,
## clearcoat — Forward+ only) or cause the headless logic test to run very slowly
## (TRANSPARENCY_ALPHA triggers expensive per-frame transparent-object sorting
## even in headless mode). The crystal look is therefore achieved with opaque
## materials: faceted geometry + high specular + low roughness + subtle rim +
## low emission. This produces convincing gemstone / crystal facet highlights
## without any transparency.
func _make_crystal(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _crystal_mesh

	var mat := StandardMaterial3D.new()

	# --- Base colour (opaque) ------------------------------------------------
	mat.albedo_color = color

	# --- Surface properties --------------------------------------------------
	# Low roughness + high metallic_specular → very sharp specular highlight on
	# each flat crystal facet, like light catching the face of a gemstone.
	mat.metallic = 0.10
	mat.roughness = 0.08
	mat.metallic_specular = 1.0

	# --- Rim (very subtle, tinted) -------------------------------------------
	# A faint rim glow tinted toward the albedo colour reads as a facet edge
	# catching light — like a cut gemstone. Much lower than the old rim = 0.5
	# to avoid the harsh white halo of the previous design.
	mat.rim_enabled = true
	mat.rim = 0.14
	mat.rim_tint = 0.70

	# --- Inner glow (very low emission) --------------------------------------
	# A tiny emission gives each crystal a sense of trapped internal light
	# without dominating the specular highlight.
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.07

	mi.material_override = mat
	add_child(mi)
	return mi


# --- Scene construction ------------------------------------------------------
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.04, 0.12)
	# Slightly reduced ambient energy so the transparent crystals don't look
	# washed-out (too much ambient fills the alpha "holes" with flat colour).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.38, 0.58)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = GRID_H + 2.0
	cam.position = Vector3(0, 0, 30)
	cam.near = 0.1
	cam.far = 100.0
	add_child(cam)
	cam.make_current()


func _build_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 1.1
	key.shadow_enabled = true
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 130, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.85, 1.0)
	add_child(fill)


func _build_back_panel() -> void:
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(GRID_W + 0.6, GRID_H + 0.6, 0.4)
	panel.mesh = box
	var mat := StandardMaterial3D.new()
	# Slightly lighter panel so the crystal refraction has something visible to
	# warp (pure-black background makes refraction invisible).
	mat.albedo_color = Color(0.16, 0.13, 0.24)
	mat.roughness = 0.85
	panel.material_override = mat
	panel.position = Vector3(0, 0, -0.7)
	add_child(panel)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var title := Label.new()
	title.text = "CANDY • TETRIS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("ffd43b"))
	title.position = Vector2(24, 18)
	layer.add_child(title)

	_lines_label = Label.new()
	_lines_label.add_theme_font_size_override("font_size", 26)
	_lines_label.add_theme_color_override("font_color", Color("ffffff"))
	_lines_label.position = Vector2(24, 64)
	layer.add_child(_lines_label)
	_update_hud()


func _update_hud() -> void:
	if _lines_label != null:
		_lines_label.text = "Lines cleared: %d" % _lines
