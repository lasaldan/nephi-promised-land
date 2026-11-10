class_name FlickerLight
extends PointLight2D

# A PointLight2D that wavers like a flame. With night_only it is dark during
# the day and fades up with the DayNight. With no texture it uses a soft round
# falloff, 64px across, so texture_scale is the radius in tiles.

const GROUP := "night_lights"
const FALLOFF := preload("res://world/lighting/light_falloff.tres")

@export var base_energy := 1.0
# How far energy wanders, as a fraction of base_energy.
@export_range(0.0, 1.0) var flicker_amount := 0.15
# Roughly how many flickers per second.
@export var flicker_speed := 6.0
# How far the radius wanders, as a fraction of texture_scale.
@export_range(0.0, 0.5) var scale_wobble := 0.03
@export var night_only := true

var night_amount := 0.0

var _noise := FastNoiseLite.new()
var _base_scale := 1.0
var _time := 0.0

func _ready() -> void:
	add_to_group(GROUP)
	if texture == null:
		texture = FALLOFF
	_base_scale = texture_scale
	_noise.seed = randi()
	_noise.frequency = 1.0
	# A light that appears after dusk (a torch carried in) starts at the
	# current darkness instead of fading up from day.
	var sky := get_tree().get_first_node_in_group(DayNight.GROUP) as DayNight
	if sky:
		night_amount = sky.night_amount
	_time = randf() * 100.0
	_process(0.0)

func set_night_amount(value: float) -> void:
	night_amount = value

func _process(delta: float) -> void:
	_time += delta * flicker_speed
	var strength := night_amount if night_only else 1.0
	var flicker := _noise.get_noise_1d(_time)
	energy = base_energy * strength * (1.0 + flicker * flicker_amount)
	texture_scale = _base_scale * (1.0 + _noise.get_noise_1d(_time + 50.0) * scale_wobble)
