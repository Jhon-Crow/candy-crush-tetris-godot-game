class_name SceneBuilder
## Constructs the 3-D scene elements: environment, camera, lights, back panel,
## and the animated retrowave background.
##
## All methods are static so no instance is needed; call them with the parent
## node to which children should be attached.

const GRID_W := 8
const GRID_H := 16
const CELL   := 1.0


## Creates and attaches the animated retrowave [Background] node at canvas
## layer −1 (behind all 3D content). Must be called before [method build_environment]
## so layers stack correctly.
static func build_background(parent: Node) -> void:
	var bg := Background.new()
	parent.add_child(bg)


## Creates and attaches a [WorldEnvironment] that uses a transparent (canvas)
## background so the retrowave CanvasLayer at layer −1 is visible behind the 3D
## scene.  Warm purple ambient lighting complements the retrowave palette.
static func build_environment(parent: Node) -> void:
	var env := Environment.new()
	# BG_CANVAS lets the retrowave CanvasLayer at layer -1 show through.
	env.background_mode = Environment.BG_CANVAS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Warm purple ambient to complement the retrowave palette.
	env.ambient_light_color = Color(0.45, 0.30, 0.65)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)


## Creates and attaches an orthographic [Camera3D] looking down the −Z axis.
static func build_camera(parent: Node) -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = GRID_H + 2.0
	cam.position = Vector3(0, 0, 30)
	cam.near = 0.1
	cam.far = 100.0
	parent.add_child(cam)
	cam.make_current()


## Creates and attaches a key and a fill [DirectionalLight3D].
static func build_lights(parent: Node) -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	parent.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 130, 0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.7, 0.8, 1.0)
	parent.add_child(fill)


## Creates and attaches the semi-transparent dark back panel behind the play
## field.  This keeps the candy balls readable against the bright retrowave
## background while still letting the animated grid and sun glow through around
## the edges.
static func build_back_panel(parent: Node) -> void:
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(GRID_W + 0.6, GRID_H + 0.6, 0.4)
	panel.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.04, 0.12, 0.72)  # dark violet, 72 % opaque
	mat.roughness = 0.95
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	panel.material_override = mat
	panel.position = Vector3(0, 0, -0.7)
	parent.add_child(panel)


## Converts a grid cell coordinate to a world-space [Vector3].
## Centres the board on the world origin.
static func cell_to_world(cell: Vector2i) -> Vector3:
	var x := (cell.x - (GRID_W - 1) / 2.0) * CELL
	var y := (cell.y - (GRID_H - 1) / 2.0) * CELL
	return Vector3(x, y, 0.0)
