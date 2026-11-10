class_name FireSound
extends AudioStreamPlayer2D

# The crackle of a fire, looping (parameters/looping) while the fire is shown.
# Hiding it, or anything above it such as its PropGroup or light, silences it.
# ignite() plays the whoosh of the fire catching first. fade_out() quiets
# it while the fire still shows.

const IGNITE := preload("res://audio/ambience/fire_start.ogg")

var _flare := AudioStreamPlayer2D.new()
var _fade: Tween
# volume_db as set in the scene, which the crackle comes back at.
var _full_db := 0.0

func _ready() -> void:
	_full_db = volume_db
	_flare.stream = IGNITE
	_flare.bus = bus
	_flare.max_distance = max_distance
	_flare.finished.connect(_sync)
	add_child(_flare)
	visibility_changed.connect(_sync)
	_sync()

# The fire is lit now: the whoosh, then the crackle.
func ignite() -> void:
	stop()
	_flare.play()

# The crackle down to silent over seconds, then stopped, for a night that
# ends on the black. It comes back at full volume the
# next time the fire is shown or lit.
func fade_out(seconds: float) -> void:
	if not playing:
		return
	_fade = create_tween()
	_fade.tween_method(func(level: float) -> void: volume_db = _full_db + maxf(linear_to_db(level), -80.0),
			1.0, 0.0, seconds)
	await _fade.finished
	stop()

func _sync() -> void:
	var shown := is_visible_in_tree()
	if not shown:
		_flare.stop()
	if shown and not _flare.playing:
		if not playing:
			if _fade != null and _fade.is_valid():
				_fade.kill()
			volume_db = _full_db
			play()
	else:
		stop()
