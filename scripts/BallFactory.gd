class_name BallFactory
## Creates and configures 3-D ball [MeshInstance3D] nodes.
##
## The factory owns a shared [SphereMesh] so all balls in the game share the
## same geometry resource, saving memory.  Materials are per-instance so each
## ball can carry its own color and emission.

# Ball type constants (mirrored here so the factory is self-contained)
enum BallType { NORMAL, BOMB, RAINBOW, FREEZE, LIGHTNING }

# Candy palette
const COLORS := [
	Color("ff4d6d"), # strawberry
	Color("ff922b"), # orange
	Color("ffd43b"), # lemon
	Color("51cf66"), # apple
	Color("4dabf7"), # blueberry
	Color("9775fa"), # grape
	Color("f783ac"), # bubblegum
]

# Shared sphere mesh
var _sphere: SphereMesh

## The scene node that will be the parent of all created balls.
var _parent: Node

# --- Init --------------------------------------------------------------------
func _init(parent: Node) -> void:
	_parent = parent
	_sphere = SphereMesh.new()
	_sphere.radius = 0.46
	_sphere.height = 0.92
	_sphere.radial_segments = 24
	_sphere.rings = 12


# --- Public API --------------------------------------------------------------
## Creates a ball node with the given color and type, adds it as a child of the
## parent, and returns it.
func make_ball(color: Color, btype: int = BallType.NORMAL) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere
	mi.material_override = make_material(color, btype)
	_parent.add_child(mi)
	return mi


## Returns a random color from the candy palette.
func random_color() -> Color:
	return COLORS[randi() % COLORS.size()]


## Returns a random BallType, with [param special_chance] probability that it
## is one of the four special types.
func random_type(special_chance: float) -> int:
	if randf() >= special_chance:
		return BallType.NORMAL
	match randi() % 4:
		0: return BallType.BOMB
		1: return BallType.RAINBOW
		2: return BallType.FREEZE
		_: return BallType.LIGHTNING


## Builds and returns a new [StandardMaterial3D] for the given color and type.
func make_material(color: Color, btype: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.22
	mat.rim_enabled = true
	mat.rim = 0.5
	mat.emission_enabled = true

	match btype:
		BallType.NORMAL:
			mat.albedo_color = color
			mat.metallic = 0.0
			mat.roughness = 0.22
			mat.emission = color
			mat.emission_energy_multiplier = 0.22

		BallType.BOMB:
			mat.albedo_color = Color(0.12, 0.08, 0.08)
			mat.metallic = 0.4
			mat.roughness = 0.55
			mat.emission = Color("ff4500")
			mat.emission_energy_multiplier = 2.0

		BallType.RAINBOW:
			mat.albedo_color = Color(1.0, 1.0, 1.0)
			mat.metallic = 0.0
			mat.roughness = 0.15
			mat.emission = Color(1.0, 1.0, 1.0)
			mat.emission_energy_multiplier = 1.5

		BallType.FREEZE:
			mat.albedo_color = Color(0.55, 0.85, 1.0)
			mat.metallic = 0.1
			mat.roughness = 0.85
			mat.emission = Color("00cfff")
			mat.emission_energy_multiplier = 1.0

		BallType.LIGHTNING:
			mat.albedo_color = Color(1.0, 1.0, 0.1)
			mat.metallic = 0.0
			mat.roughness = 0.10
			mat.emission = Color(1.0, 1.0, 0.0)
			mat.emission_energy_multiplier = 3.0

	return mat


## Animate special-ball materials in [param piece].
## [param anim_time] should be a continuously increasing float (seconds).
func animate_piece_materials(piece: Piece, anim_time: float) -> void:
	for i in piece.nodes.size():
		var btype: int = piece.types[i]
		if btype == BallType.NORMAL:
			continue
		var node: MeshInstance3D = piece.nodes[i]
		var mat: StandardMaterial3D = node.material_override as StandardMaterial3D
		if mat == null:
			continue

		match btype:
			BallType.BOMB:
				var pulse := (sin(anim_time * 6.0) + 1.0) * 0.5
				mat.emission_energy_multiplier = lerp(1.0, 4.0, pulse)

			BallType.RAINBOW:
				var hue := fmod(anim_time * 0.4, 1.0)
				var rainbow := Color.from_hsv(hue, 1.0, 1.0)
				mat.emission = rainbow
				mat.albedo_color = rainbow.lightened(0.3)
				mat.emission_energy_multiplier = 1.5

			BallType.LIGHTNING:
				var flicker := (sin(anim_time * 20.0) + 1.0) * 0.5
				mat.emission_energy_multiplier = lerp(2.0, 5.0, flicker)
