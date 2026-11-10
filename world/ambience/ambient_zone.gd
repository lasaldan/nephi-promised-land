@tool
class_name AmbientZone
extends Node2D

# A looping sound heard everywhere inside a rectangle, fading in as Nephi
# walks in and out as he leaves: wind on a mountaintop, the hum of a market,
# frogs by a pond at night. Place it, set size (drawn in the editor), and
# pick a looping stream. For a sound that should come from one spot and fade
# with distance (a waterfall, a fire), use an AudioStreamPlayer2D instead.
#
# when limits it to the day or the night, following DayNight.night_amount, so
# frogs and owls come out with the dark and birdsong fades with it.
# Chapters can quiet one by name (StoryChapter.quiet_zones), or code can set
# enabled.

enum When { ALWAYS, DAY, NIGHT }

@export var stream: AudioStream
@export var size := Vector2(640, 320):
	set(value):
		size = value
		queue_redraw()
@export var when := When.ALWAYS
@export var volume_db := -12.0
## Seconds to fade all the way in or out.
@export var fade_seconds := 1.5
@export var enabled := true

# 0 is silent, 1 is volume_db.
var _level := 0.0
var _player: AudioStreamPlayer

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("ambient_zones")
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.bus = GameSettings.SFX
	_player.volume_db = -80.0
	add_child(_player)

func area() -> Rect2:
	return Rect2(global_position - size / 2.0, size)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var target := 0.0
	if enabled and player and area().has_point(player.global_position):
		target = _time_of_day_share()
	_level = move_toward(_level, target, delta / fade_seconds)
	if _level > 0.0 and not _player.playing:
		_player.play()
	elif _level == 0.0 and _player.playing:
		_player.stop()
	if _player.playing:
		_player.volume_db = volume_db + linear_to_db(_level)

func _time_of_day_share() -> float:
	if when == When.ALWAYS:
		return 1.0
	var sky := get_tree().get_first_node_in_group(DayNight.GROUP) as DayNight
	var night := sky.night_amount if sky else 0.0
	return night if when == When.NIGHT else 1.0 - night

func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(Rect2(-size / 2.0, size), Color(0.4, 0.8, 1.0, 0.15))
		draw_rect(Rect2(-size / 2.0, size), Color(0.4, 0.8, 1.0, 0.6), false, 2.0)
