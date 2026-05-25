class_name SceneBuilder
## Constructs the 3-D scene elements: environment, camera, lights, and back panel.
##
## All methods are static so no instance is needed; call them with the parent
## node to which children should be attached.

const GRID_W := 8
const GRID_H := 16
const CELL   := 1.0


## Creates and attaches a [WorldEnvironment] with a dark purple background and
## ambient lighting suited to the candy aesthetic.
static func build_environment(parent: Node) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.06, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.42, 0.6)
	env.ambient_light_energy = 0.6
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


## Creates and attaches the dark back panel behind the play field.
static func build_back_panel(parent: Node) -> void:
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(GRID_W + 0.6, GRID_H + 0.6, 0.4)
	panel.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.10, 0.18)
	mat.roughness = 0.9
	panel.material_override = mat
	panel.position = Vector3(0, 0, -0.7)
	parent.add_child(panel)


## Converts a grid cell coordinate to a world-space [Vector3].
## Centres the board on the world origin.
static func cell_to_world(cell: Vector2i) -> Vector3:
	var x := (cell.x - (GRID_W - 1) / 2.0) * CELL
	var y := (cell.y - (GRID_H - 1) / 2.0) * CELL
	return Vector3(x, y, 0.0)
