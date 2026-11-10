class_name Footsteps
extends AudioStreamPlayer

# Nephi's steps as he walks, with a sound for what he is walking on. Each
# surface has two steps that play in turn.
#
# The surface comes from the tiles: give a TileSet a custom data layer named
# "surface" (a String) and paint it with a key of SURFACES ("grass", "sand",
# "stone", "wood"). The topmost shown TileMapLayer under GroundLayer with a
# surface under his feet decides, so a wooden bridge over water, or a path over
# grass, sounds right. Tiles with no surface (water) are silent. They keep the walk cycle's pace (two steps a
# loop) but are not tied to its frames. player.gd adds this as a child.

# The walk animations are 0.586667 s a loop, one step per foot.
const STEP_SECONDS := 0.586667 / 2.0
# The first step comes this soon after he sets off, so a tap of a direction
# still makes a sound.
const FIRST_STEP_SECONDS := 0.08
# Slower than this (pushing into a wall) is standing still. Measured from how
# far he actually went since the last physics frame, not his velocity, which
# keeps its last value while a pose (facing) holds him still.
const MOVING_SPEED := 10.0
# No steps while this is showing, even if he is walked during it.
const SCRIPTURE_SCROLL := "../../ScriptureScroll"
# Each step plays this much faster or slower, at random, so repeats differ.
const PITCH_WANDER := 0.06
# Below the rest of the SFX bus. Every 6 dB lower is about half as loud.
const VOLUME_DB := -20.0

# The two steps for each surface, and how much quieter than VOLUME_DB they
# play. The dirt, stone and wood recordings are louder than the grass ones,
# so they are turned down to match it.
const SURFACES := {
	&"grass": {
		"steps": [preload("res://audio/footsteps/grass_1.wav"), preload("res://audio/footsteps/grass_2.wav")],
		"volume_db": 0.0,
	},
	&"sand": {
		"steps": [preload("res://audio/footsteps/dirt_1.wav"), preload("res://audio/footsteps/dirt_2.wav")],
		"volume_db": -10.0,
	},
	&"stone": {
		"steps": [preload("res://audio/footsteps/stone_1.wav"), preload("res://audio/footsteps/stone_2.wav")],
		"volume_db": -10.0,
	},
	&"wood": {
		"steps": [preload("res://audio/footsteps/wood_1.wav"), preload("res://audio/footsteps/wood_2.wav")],
		"volume_db": -0,
	},
}

const SURFACE_DATA := "surface"
const GROUND := "../../GroundLayer"

var _wait := 0.0
var _second_foot := false
var _last_position := Vector2.INF

func _ready() -> void:
	bus = &"SFX"

func _physics_process(delta: float) -> void:
	var body := get_parent() as CharacterBody2D
	var moved := body.global_position.distance_to(_last_position)
	_last_position = body.global_position
	if moved < MOVING_SPEED * delta or _scroll_showing():
		_wait = FIRST_STEP_SECONDS
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait += STEP_SECONDS
	var surface := _surface_at(body.global_position)
	if surface != &"":
		var sounds: Dictionary = SURFACES[surface]
		stream = sounds.steps[1 if _second_foot else 0]
		volume_db = VOLUME_DB + sounds.volume_db
		pitch_scale = 1.0 + randf_range(-PITCH_WANDER, PITCH_WANDER)
		play()
	_second_foot = not _second_foot

func _scroll_showing() -> bool:
	var scroll := get_node_or_null(SCRIPTURE_SCROLL) as ScriptureScroll
	return scroll != null and scroll.is_showing()

# The surface under at, or empty when nothing there has one.
func _surface_at(at: Vector2) -> StringName:
	var ground := get_node_or_null(GROUND)
	if ground == null:
		return &""
	var layers := ground.find_children("*", "TileMapLayer", true, false)
	# Later layers draw on top.
	layers.reverse()
	for node in layers:
		var layer := node as TileMapLayer
		if layer.tile_set == null or not layer.is_visible_in_tree() \
				or layer.tile_set.get_custom_data_layer_by_name(SURFACE_DATA) < 0:
			continue
		var data := layer.get_cell_tile_data(layer.local_to_map(layer.to_local(at)))
		if data == null:
			continue
		var surface := StringName(str(data.get_custom_data(SURFACE_DATA)))
		if SURFACES.has(surface):
			return surface
	return &""
