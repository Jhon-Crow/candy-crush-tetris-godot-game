extends SceneTree
## Renders the game to a virtual framebuffer and saves PNG screenshots.
##
## Run under a display (e.g. xvfb) with the OpenGL backend:
##   xvfb-run -s "-screen 0 720x1280x24" \
##     godot --rendering-driver opengl3 --script experiments/screenshot.gd
##
## Used to capture evidence screenshots for the pull request / issue.

var _game: Node3D
var _frame := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	_game = scene.instantiate()
	root.add_child(_game)
	_game._ready()
	# Drop a number of pieces so the board shows an interesting stack.
	for i in range(140):
		_game._step()
	_snap_active_balls()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 6:
		_capture("res://shot_a.png")
	elif _frame == 12:
		for i in range(45):
			_game._step()
		_snap_active_balls()
	elif _frame == 18:
		_capture("res://shot_b.png")
		quit(0)
	return false


# Place the falling piece's balls exactly on their grid cells for a crisp shot
# (skips the smooth glide that would otherwise leave them mid-air).
func _snap_active_balls() -> void:
	for i in _game._piece_nodes.size():
		_game._piece_nodes[i].position = _game._cell_to_world(_game._piece_cells[i])


func _capture(path: String) -> void:
	var img: Image = root.get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
