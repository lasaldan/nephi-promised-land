class_name MusicPlaylist
extends AudioStreamPlayer

# Background music that moves through a list of tracks instead of looping
# one. Add tracks to `tracks` in the inspector. Each pass plays every track
# once; with `shuffle` on the order is reshuffled each pass, never starting
# with the track that just ended.

@export var tracks: Array[AudioStream] = []
@export var shuffle := true
# Seconds of quiet between tracks.
@export var gap := 2.0

var _queue: Array[AudioStream] = []

func _ready() -> void:
	finished.connect(_on_finished)
	if not tracks.is_empty():
		_play_next()

func _on_finished() -> void:
	if gap > 0.0:
		await get_tree().create_timer(gap).timeout
	_play_next()

func _play_next() -> void:
	if tracks.is_empty():
		return
	if _queue.is_empty():
		_queue = tracks.duplicate()
		if shuffle:
			_queue.shuffle()
			# Don't repeat the track that just ended at a pass boundary.
			if _queue.size() > 1 and _queue[0] == stream:
				_queue.push_back(_queue.pop_front())
	stream = _queue.pop_front()
	play()

# Plays track once and ends the playlist, for a scene scored to one piece
# (an ending, say).
func play_once(track: AudioStream) -> void:
	tracks = []
	_queue.clear()
	stream = track
	play()
