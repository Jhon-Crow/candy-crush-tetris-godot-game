class_name HUD
## Heads-up display: score labels, freeze indicator, and ball-type legend.
##
## All UI nodes are created procedurally and parented to a [CanvasLayer] that
## the caller (Game.gd) adds to the scene.

var _lines_label: Label
var _freeze_label: Label
var _layer: CanvasLayer


# --- Init --------------------------------------------------------------------
## Creates the CanvasLayer and all child labels; adds the layer to [param parent].
func _init(parent: Node) -> void:
	_layer = CanvasLayer.new()
	parent.add_child(_layer)

	var title := Label.new()
	title.text = "CANDY • TETRIS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("ffd43b"))
	title.position = Vector2(24, 18)
	_layer.add_child(title)

	_lines_label = Label.new()
	_lines_label.add_theme_font_size_override("font_size", 26)
	_lines_label.add_theme_color_override("font_color", Color("ffffff"))
	_lines_label.position = Vector2(24, 64)
	_layer.add_child(_lines_label)

	_freeze_label = Label.new()
	_freeze_label.add_theme_font_size_override("font_size", 26)
	_freeze_label.add_theme_color_override("font_color", Color("00cfff"))
	_freeze_label.position = Vector2(24, 100)
	_freeze_label.visible = false
	_layer.add_child(_freeze_label)

	var legend := Label.new()
	legend.text = "💣 Bomb  🌈 Rainbow  ❄️ Freeze  ⚡ Lightning"
	legend.add_theme_font_size_override("font_size", 18)
	legend.add_theme_color_override("font_color", Color("cccccc"))
	legend.position = Vector2(24, 140)
	_layer.add_child(legend)


# --- Updates -----------------------------------------------------------------
## Refresh the score line.
func update_score(lines: int, specials: int) -> void:
	if _lines_label != null:
		_lines_label.text = "Lines: %d  |  Specials: %d" % [lines, specials]


## Refresh the freeze indicator.
## Pass freeze_timer > 0 to show it; pass 0 (or negative) to hide it.
func update_freeze(freeze_timer: float) -> void:
	if _freeze_label == null:
		return
	if freeze_timer > 0.0:
		_freeze_label.text = "❄️ FROZEN! (%.1fs)" % freeze_timer
		_freeze_label.visible = true
	else:
		_freeze_label.visible = false
