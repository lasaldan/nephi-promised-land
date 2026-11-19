@tool
class_name GrateLight
extends Node2D

# Daylight falling through a deck grate onto the hold floor: a square of
# light for each of the grate's holes (world/props/grate_light.png, made from
# the grate's own tiles by tools/grate_light/gen.py), lit with the sky's
# light, DayNight.outdoor_color. So it is bright by day, a faint blue by
# night, grey in a storm, and flashes with the lightning at full strength
# while the rest of the hold only glows (DayNight.indoor_flash).
#
# A few dust motes drift in it (world/props/grate_motes.gdshader). Each is
# as bright as the light where it floats: they glint as they cross a beam
# and vanish in the bars' shadow between, and they dim and flash with it.
#
# Under rain or fog the sky is a flat grey, so the light dims (gloom_energy)
# and goes cool (gloom_tint), whichever of the two is thicker: the bare floor
# is warm wood, and plain white on it looks like sunshine. A lightning flash
# still comes through at full strength. The weather scatters the light too:
# the crisp squares fade into a soft square of light (Diffuse, made by
# tools/grate_light/gen.py), so no sun or moon casts a sharp grid through
# cloud. Fog, thick and close, dims it further still (fog_energy).
#
# Around the squares, a soft round glow in the same light (Glow, the
# world's light_falloff) is the daylight bouncing off the floor, lighting
# the hold around the grate a little.
#
# Put it under the ship's Lower node, below the grate (its origin is the
# middle of the squares), so it rocks with the ship and is hidden with the
# hold. The hold's floor is drawn further south than the upper deck, so on
# the ship it sits a tile and a quarter south of the grate's center.
# The light shines on the below_decks light layer only.

## How bright the squares are under a full day's sky.
@export_range(0.0, 3.0, 0.05) var energy := 1.0:
	set(value):
		energy = value
		_apply()

## How bright the glow around the squares is under a full day's sky.
@export_range(0.0, 2.0, 0.05) var glow_energy := 0.35:
	set(value):
		glow_energy = value
		_apply()
## How far the glow reaches, in tiles from the middle (64px of falloff per
## unit, as FlickerLight's texture_scale).
@export_range(0.5, 8.0, 0.25) var glow_radius := 3.0:
	set(value):
		glow_radius = value
		_apply()

## How bright the light is, of its clear-sky self, under a storm or thick fog.
@export_range(0.0, 1.0, 0.05) var gloom_energy := 0.35:
	set(value):
		gloom_energy = value
		_apply()
## The grey the light turns under a storm or thick fog. Cool, to offset the
## warm floor.
@export var gloom_tint := Color(0.5, 0.66, 1.0):
	set(value):
		gloom_tint = value
		_apply()
## How bright the light is, of what the gloom leaves, in the thickest fog.
@export_range(0.0, 1.0, 0.05) var fog_energy := 0.5:
	set(value):
		fog_energy = value
		_apply()
## How much of the light stays together in the soft square once it scatters.
@export_range(0.0, 1.0, 0.05) var diffuse_energy := 0.7:
	set(value):
		diffuse_energy = value
		_apply()

@onready var _light: PointLight2D = $Light
@onready var _glow: PointLight2D = $Glow
@onready var _diffuse: PointLight2D = $Diffuse
@onready var _motes: ShaderMaterial = $Motes.material

var _sky: DayNight
var _rain: Rain
var _fog: Fog
# 0 clear, 1 a storm or thick fog. Read from them each frame: neither says
# when it changes.
var _gloom := 0.0
var _fog_density := 0.0

func _ready() -> void:
	# The DayNight may come later in the scene: it is ready by then.
	_settle.call_deferred()
	_apply()

func _settle() -> void:
	_sky = get_tree().get_first_node_in_group(DayNight.GROUP) as DayNight
	_rain = get_tree().get_first_node_in_group(Rain.GROUP) as Rain
	_fog = get_tree().get_first_node_in_group(Fog.GROUP) as Fog
	if _sky and not _sky.outdoor_changed.is_connected(_on_outdoor_changed):
		_sky.outdoor_changed.connect(_on_outdoor_changed)
	_apply()

func _on_outdoor_changed(_color: Color) -> void:
	_apply()

func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var gloom := 0.0
	if is_instance_valid(_rain):
		gloom = _rain.intensity
	var fog := 0.0
	if is_instance_valid(_fog):
		fog = _fog.density
		gloom = maxf(gloom, fog)
	# Steady rain or a light fog is most of the way grey already.
	gloom = clampf(gloom * 1.5, 0.0, 1.0)
	if not is_equal_approx(gloom, _gloom) or not is_equal_approx(fog, _fog_density):
		_gloom = gloom
		_fog_density = fog
		_apply()

func _apply() -> void:
	if not is_node_ready():
		return
	var outdoor := _sky.outdoor_color if is_instance_valid(_sky) else Color.WHITE
	var flash := _sky.flash if is_instance_valid(_sky) else 0.0
	# The gloom greys the sky's light, but never a flash.
	var gloom := _gloom * (1.0 - flash)
	var grey := outdoor.get_luminance()
	outdoor = outdoor.lerp(Color(grey, grey, grey) * gloom_tint * gloom_energy, gloom)
	outdoor *= lerpf(1.0, fog_energy, _fog_density * (1.0 - flash))
	# Past white (a flash) goes into energy: a light's color is clamped.
	var peak := maxf(maxf(outdoor.r, outdoor.g), maxf(outdoor.b, 1.0))
	_light.color = Color(outdoor.r / peak, outdoor.g / peak, outdoor.b / peak)
	# Scattered by the weather, flash and all: crisp squares to the soft one.
	_light.energy = energy * peak * (1.0 - _gloom)
	_diffuse.color = _light.color
	_diffuse.energy = energy * peak * _gloom * diffuse_energy
	_glow.color = _light.color
	_glow.energy = glow_energy * peak
	_glow.texture_scale = glow_radius
	_motes.set_shader_parameter("light_color", _light.color)
	_motes.set_shader_parameter("energy", energy * peak)
