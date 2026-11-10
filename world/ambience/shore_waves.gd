class_name ShoreWaves
extends Node2D

# Wave sounds timed to the animated shore tiles on beach_layer. Every loop of
# the tile animation one clip plays, started early enough that its crash
# lands on crash_at. A long clip still rings out while the next one starts, so
# there are two players and each wave takes the other one.
#
# The sound sits on the shore cell nearest the camera, so it fades in as you
# walk down to the water and follows you along the beach.

@export var beach_layer: TileMapLayer
@export var clips: Array[AudioStream] = []
# For each clip, the seconds into it where the wave crashes (its loudest point).
# The defaults are for shore_wave_long.ogg and shore_wave_short.ogg.
@export var crash_times := PackedFloat32Array([1.65, 0.675])
# Seconds into the tile animation loop for the crash to land. Frame 0 is the
# water all the way in; at 4 fps frame 1 (the foam at the far edge) starts at 0.25.
@export var crash_at := 0.25
# Each wave plays this much faster or slower, at random, so repeats differ.
@export_range(0.0, 0.2) var pitch_wander := 0.04
@export var volume_db := 0.0
@export var max_distance := 200.0
@export var bus := &"SFX"
# 0 to 1, on top of volume_db, for a scene that wants the sea quieter or
# fades it out. Tween it like any property.
var level := 1.0:
	set(value):
		level = value
		for player in _players:
			player.volume_db = _level_db()

# Seconds between nearest-cell searches as the camera moves.
const FOLLOW_INTERVAL := 0.2
# A wave whose start was missed by more than this (a long hitch) is skipped.
const LATE_LIMIT := 0.3

var _players: Array[AudioStreamPlayer2D] = []
var _turn := 0
var _period := 0.0
var _cells: PackedVector2Array = []
var _follow_wait := 0.0
# RenderClock time of the next crash that has no sound started for it yet,
# and the clip and pitch picked for it.
var _next_crash := 0.0
var _next_clip := 0
var _next_pitch := 1.0

func _ready() -> void:
	for i in 2:
		var player := AudioStreamPlayer2D.new()
		player.bus = bus
		player.volume_db = _level_db()
		player.max_distance = max_distance
		add_child(player)
		_players.append(player)
	_read_layer()
	if crash_times.size() != clips.size():
		push_error("ShoreWaves needs one crash time per clip (%d clips, %d times)" % [clips.size(), crash_times.size()])
		set_process(false)
		return
	if _period <= 0.0 or clips.is_empty():
		set_process(false)
		return
	_pick_next()
	var now := RenderClock.time
	_next_crash = ceil((now - crash_at + _lead()) / _period) * _period + crash_at
	_follow()

func _process(delta: float) -> void:
	_follow_wait -= delta
	if _follow_wait <= 0.0:
		_follow()
	var now := RenderClock.time
	while now >= _next_crash - _lead():
		var late := now - (_next_crash - _lead())
		if late < LATE_LIMIT and beach_layer.is_visible_in_tree():
			var player := _players[_turn]
			_turn = 1 - _turn
			player.stream = clips[_next_clip]
			player.pitch_scale = _next_pitch
			player.play(late * _next_pitch)
		_next_crash += _period
		_pick_next()

func _level_db() -> float:
	# linear_to_db(0) is -inf.
	return volume_db + maxf(linear_to_db(level), -80.0)

# Seconds of real time from the start of the next clip to its crash.
func _lead() -> float:
	return crash_times[_next_clip] / _next_pitch

func _pick_next() -> void:
	_next_clip = randi() % clips.size()
	_next_pitch = 1.0 + randf_range(-pitch_wander, pitch_wander)

# Finds the loop length of the animated tiles and where they are. Only tiles
# in the default animation mode play in step; random-start ones are left out.
func _read_layer() -> void:
	if beach_layer == null or beach_layer.tile_set == null:
		return
	for cell in beach_layer.get_used_cells():
		var source := beach_layer.tile_set.get_source(beach_layer.get_cell_source_id(cell)) as TileSetAtlasSource
		if source == null:
			continue
		var coords := beach_layer.get_cell_atlas_coords(cell)
		if source.get_tile_animation_frames_count(coords) < 2:
			continue
		if source.get_tile_animation_mode(coords) != TileSetAtlasSource.TILE_ANIMATION_MODE_DEFAULT:
			continue
		if _period <= 0.0:
			_period = source.get_tile_animation_total_duration(coords) / source.get_tile_animation_speed(coords)
		_cells.append(beach_layer.to_global(beach_layer.map_to_local(cell)))

func _follow() -> void:
	_follow_wait = FOLLOW_INTERVAL
	var camera := get_viewport().get_camera_2d()
	if camera == null or _cells.is_empty():
		return
	var at := camera.get_screen_center_position()
	var best := _cells[0]
	var best_distance := INF
	for cell in _cells:
		var distance := at.distance_squared_to(cell)
		if distance < best_distance:
			best_distance = distance
			best = cell
	global_position = best
