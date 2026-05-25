## Animated background system for Candy Crush Tetris.
##
## Renders a retrowave/synthwave animated backdrop (neon perspective grid +
## retro sun) behind the gameplay layer.  The background is designed to be
## swappable: call [method set_theme] with a different [BackgroundTheme] dict
## to instantly switch to a new look — handy for future per-level themes.
##
## Usage (called from Game.gd):
##   var bg = Background.new()
##   add_child(bg)
##   # optionally change colour theme later:
##   bg.set_theme(Background.THEME_PLASMA)

class_name Background
extends Node

# ---------------------------------------------------------------------------
# Built-in themes (colour palettes + speed settings)
# ---------------------------------------------------------------------------

## The default retrowave / synthwave look: neon magenta grid, orange sunset.
const THEME_RETROWAVE := {
	"sky_top":        Color(0.05, 0.01, 0.12),
	"sky_horizon":    Color(0.55, 0.05, 0.35),
	"sun_outer":      Color(1.00, 0.40, 0.10),
	"sun_inner":      Color(1.00, 0.85, 0.20),
	"grid_color":     Color(0.90, 0.05, 0.80),
	"grid_glow":      Color(0.30, 0.00, 0.60),
	"ground_dark":    Color(0.03, 0.00, 0.10),
	"grid_speed":     0.5,
	"scanline_count": 8.0,
}

## Cyan/teal "plasma" variant for a mid-game feel.
const THEME_PLASMA := {
	"sky_top":        Color(0.00, 0.02, 0.14),
	"sky_horizon":    Color(0.00, 0.45, 0.55),
	"sun_outer":      Color(0.00, 0.85, 1.00),
	"sun_inner":      Color(0.80, 1.00, 1.00),
	"grid_color":     Color(0.00, 0.95, 0.95),
	"grid_glow":      Color(0.00, 0.30, 0.50),
	"ground_dark":    Color(0.00, 0.02, 0.10),
	"grid_speed":     0.8,
	"scanline_count": 6.0,
}

## Hot pink / electric-lime "neon" variant for later levels.
const THEME_NEON := {
	"sky_top":        Color(0.08, 0.00, 0.08),
	"sky_horizon":    Color(0.80, 0.00, 0.45),
	"sun_outer":      Color(1.00, 0.80, 0.00),
	"sun_inner":      Color(1.00, 1.00, 0.50),
	"grid_color":     Color(0.20, 1.00, 0.10),
	"grid_glow":      Color(0.05, 0.40, 0.00),
	"ground_dark":    Color(0.02, 0.04, 0.00),
	"grid_speed":     1.1,
	"scanline_count": 10.0,
}

# ---------------------------------------------------------------------------
# Internal nodes
# ---------------------------------------------------------------------------
var _canvas_layer: CanvasLayer
var _rect: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	# Create a CanvasLayer behind all gameplay (layer 0) and UI (layer 1+).
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = -1
	add_child(_canvas_layer)

	# Full-screen quad that receives the shader.
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(_rect)

	# Load and attach the retrowave shader.
	# (safe in both editor/player and headless CI — the shader is parsed but
	#  not executed when there is no display, so this never crashes headless runs.)
	var shader := load("res://shaders/retrowave_background.gdshader") as Shader
	if shader == null:
		push_warning("Background: retrowave shader not found; background will be invisible.")
		return
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect.material = _material

	# Apply the default theme.
	set_theme(THEME_RETROWAVE)


## Instantly switches the background to the given theme dictionary.
## [param theme] must contain the same keys as the THEME_* constants.
## Unknown keys are silently ignored; missing keys keep their previous value.
func set_theme(theme: Dictionary) -> void:
	if _material == null:
		return
	for key in theme:
		_material.set_shader_parameter(key, theme[key])
