extends Node

# The time that animated tiles (and shader TIME) are drawn at. The renderer
# adds each drawn frame's step to its own clock from the first frame of the
# game, and tile animations play off that, not off when their scene loaded.
# Sounds that have to land on a tile animation frame (shore_waves.gd) read
# it here. It has to be an autoload so it counts from the same first frame.
#
# Like the renderer it only counts frames that are drawn (not while the
# window is minimized), and it keeps going while the game is paused.

var time := 0.0

var _step := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)

func _process(delta: float) -> void:
	_step = delta

func _on_frame_pre_draw() -> void:
	time += _step
	_step = 0.0
