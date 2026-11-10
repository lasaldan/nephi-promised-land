extends CanvasLayer

class_name ActivityScroll

# The paper scroll over the right half of the screen, holding one hands-on
# activity at a time (a ScrollBoard). While it is open Nephi cannot move, the
# HUD is hidden, and the player camera slides right so he stands in the
# middle of the left half.
#
# A chapter calls doActivity("id"), which calls open_activity(). The board is
# made fresh from BOARDS, and when it is done the scroll sets flag(id), sends
# SignalBus.activity_finished, and closes itself. A board's step_done along
# the way goes out as SignalBus.activity_step. A board may also have a close X
# (ScrollBoard.CLOSE_RECT): that closes the scroll without finishing, and the
# chapter can open it again later at the step it reached (start_step).
#
# Bountiful's boards (rope braiding, sawing, nailing; ui/activities/ there)
# are good patterns for new ones: one gesture, the next target glows, no
# failing, short, mouse and touch both work.

const GROUP := "activity_scroll"

# Activity id -> board script. Each is a ScrollBoard that emits finished.
const BOARDS := {
	# "plant": preload("res://ui/activities/plant_board.gd"),
}

signal opened
signal closed

# The paper is this many tiles wide, against the right edge of the screen and
# top to bottom whatever its height. The board is centered on it up and down.
const PAPER_TILES := 8

# How far the camera moves right: half the paper puts Nephi in the middle of
# the screen it leaves open.
@export var camera_shift: float = 128.0
# With a focus (open_activity()), the camera moves on toward it, but no
# further than leaves Nephi this many pixels inside the open half.
const FOCUS_MARGIN := Vector2(40, 40)
@export var slide_seconds: float = 0.6
@export var fade_seconds: float = 0.35

@onready var paper: TileMapLayer = $Paper

var _open := false
var _board: ScrollBoard
var _tween: Tween
var _ui_was_visible := true
# The same as a scripture scroll opening (ScriptureScroll.OPEN_SOUND).
var _open_sound: AudioStreamPlayer
static func flag(activity_id: String) -> String:
	return "activity_" + activity_id

static func is_done(activity_id: String) -> bool:
	return StoryState.get_flag(flag(activity_id), false)

func _ready() -> void:
	add_to_group(GROUP)
	_layout()
	get_viewport().size_changed.connect(_layout)
	visible = false
	paper.modulate.a = 0.0
	_open_sound = AudioStreamPlayer.new()
	_open_sound.stream = ScriptureScroll.OPEN_SOUND
	_open_sound.volume_db = ScriptureScroll.OPEN_VOLUME_DB
	_open_sound.bus = GameSettings.SFX
	add_child(_open_sound)

func is_open() -> bool:
	return _open

# The board showing, or null while closed.
func board() -> ScrollBoard:
	return _board if _open else null

# Returns false, and opens nothing, for an unknown id or while the scroll is
# already open. facing turns Nephi ("up", "left", ...); "" leaves him as he is.
# start_step is how many of its steps were done on an earlier open.
# focus, a world position, is what the open half of the screen should show
# along with Nephi, such as where the activity's work appears in the world.
# Without one, Nephi stands in the middle of it.
func open_activity(activity_id: String, facing: String = "", start_step: int = 0, focus: Vector2 = Vector2.INF) -> bool:
	if _open:
		push_warning("The scroll is already open; cannot start activity '%s'" % activity_id)
		return false
	if not BOARDS.has(activity_id):
		push_error("No activity '%s' in ActivityScroll.BOARDS" % activity_id)
		return false
	var board: ScrollBoard = BOARDS[activity_id].new()
	board.start_step = start_step
	add_child(board)
	_place_board(board)
	board.close_requested.connect(close)
	board.finished.connect(_on_finished.bind(activity_id), CONNECT_ONE_SHOT)
	board.step_done.connect(func(step: int): SignalBus.activity_step.emit(activity_id, step))
	_show(board, facing, focus)
	return true

func close() -> void:
	if not _open:
		return
	_open = false
	var player = _player()
	player.menu_open = false
	# A held pose should not outlive the menu.
	player.facing = ""
	var ui := _ui()
	if ui:
		ui.visible = _ui_was_visible
	_animate(0.0, Vector2.ZERO)
	closed.emit()

# Paper against the right edge, painted down past the bottom of the screen.
func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var width := PAPER_TILES * ScriptureScroll.TILE
	paper.position = Vector2(roundf(screen.x - width), 0)
	var rows := ceili(screen.y / ScriptureScroll.TILE)
	ScriptureScroll.paint_paper(paper, Rect2i(0, 0, PAPER_TILES, rows), false)
	for child in get_children():
		if child is ScrollBoard:
			_place_board(child)

# Boards are drawn for ScrollBoard.RECT, the right half of a 512x288 screen.
# Keep that against the right edge, centered up and down.
func _place_board(board: ScrollBoard) -> void:
	var screen := get_viewport().get_visible_rect().size
	var design := Vector2(512, 288)
	board.position = (ScrollBoard.RECT.position + Vector2(screen.x - design.x, (screen.y - design.y) / 2)).round()
	board.size = ScrollBoard.RECT.size

func _show(board: ScrollBoard, facing: String, focus: Vector2 = Vector2.INF) -> void:
	if _open:
		return
	_open = true
	# A board still fading out from the last close goes now.
	if _board and _board != board:
		_put_away(_board)
	_board = board
	var player = _player()
	player.menu_open = true
	if not facing.is_empty():
		player.facing = facing
	player.play_idle()
	var ui := _ui()
	if ui:
		_ui_was_visible = ui.visible
		ui.visible = false
	board.reset()
	board.modulate.a = 0.0
	board.visible = true
	visible = true
	_open_sound.play()
	_animate(1.0, _camera_offset(focus))
	opened.emit()

# Where the camera sits while the scroll is open: Nephi in the middle of the
# open left half, or moved toward focus as far as keeps him in it.
func _camera_offset(focus: Vector2) -> Vector2:
	var offset := Vector2(camera_shift, 0)
	if not focus.is_finite():
		return offset
	var screen := get_viewport().get_visible_rect().size
	var room := Vector2(screen.x / 4.0, screen.y / 2.0) - FOCUS_MARGIN
	var toward: Vector2 = focus - _player().global_position
	return offset + toward.clamp(-room, room)

# Paper and board fade together while the camera slides.
func _animate(alpha: float, shift: Vector2) -> void:
	if _tween:
		_tween.kill()
	var board := _board
	board.mouse_filter = Control.MOUSE_FILTER_STOP if alpha > 0.0 else Control.MOUSE_FILTER_IGNORE
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(paper, "modulate:a", alpha, fade_seconds)
	_tween.tween_property(board, "modulate:a", alpha, fade_seconds)
	_tween.tween_property(_player().get_node("Camera"), "offset", shift, slide_seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if alpha == 0.0:
		_tween.chain().tween_callback(func():
			visible = false
			_put_away(board))

# A board is made fresh for each open, so it goes.
func _put_away(board: ScrollBoard) -> void:
	if board == _board:
		_board = null
	if is_instance_valid(board):
		board.queue_free()

func _on_finished(activity_id: String) -> void:
	StoryState.set_flag(flag(activity_id), true)
	print("Finished activity " + activity_id)
	SignalBus.activity_finished.emit(activity_id)
	close()

# Untyped, so menu_open and the other player.gd fields can be reached.
func _player():
	return get_tree().get_first_node_in_group("player")

func _ui() -> CanvasLayer:
	return get_parent().get_node_or_null("UI") as CanvasLayer
