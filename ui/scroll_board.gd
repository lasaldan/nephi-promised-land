extends Control

class_name ScrollBoard

# What sits on the ActivityScroll: one hands-on activity. A board covers the right half of the screen
# and draws itself, so it stays crisp at 512x288.

# An activity is done. The scroll sets its flag and closes.
signal finished
# One stage of an activity is done, such as one log of the sawing; step
# counts from 0. The scroll stays open.
signal step_done(step: int)
# The player asked to close the scroll (the X at CLOSE_RECT).
signal close_requested

# Board size, and where it sits on the 512x288 screen.
const RECT := Rect2(256, 0, 256, 288)
# The paper's border is wider on the right, so the middle of the board's
# writing area sits a little left of RECT's middle.
const CENTER := 125.0

const INK := Color(0.29, 0.18, 0.08)
const OUTLINE := Color(0.29, 0.18, 0.08, 0.45)
const PAPER := Color(0.96, 0.89, 0.72)
const FONT := preload("res://ui/fonts/OverlockBold.ttf")

# The X in the top right corner that closes the scroll, on a board that has
# one.
const CLOSE_RECT := Rect2(222, 6, 14, 14)

# How many steps (step_done) were done before this open, for an activity the
# player can leave and come back to. Set before reset(); step_done counts on
# from here.
var start_step := 0

# Called each time the scroll opens on this board.
func reset() -> void:
	pass

# Whether a press at at hits the close X, with a little slack for fingers.
static func is_close_press(at: Vector2) -> bool:
	return CLOSE_RECT.grow(4).has_point(at)

func draw_close() -> void:
	var r := CLOSE_RECT.grow(-3)
	draw_line(r.position, r.end, INK, 2)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), INK, 2)

# A mouse and a finger both work. Events emulated from the other kind are
# skipped, so a tap is never handled twice, whichever emulation settings the
# project has.
static func is_emulated(event: InputEvent) -> bool:
	return event.device == InputEvent.DEVICE_ID_EMULATION

# A left click or first finger, going down or coming up.
static func is_press(event: InputEvent) -> bool:
	return (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.index == 0)

# The mouse or first finger moving.
static func is_drag(event: InputEvent) -> bool:
	return event is InputEventMouseMotion \
		or (event is InputEventScreenDrag and event.index == 0)

static func point_of(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return (event as InputEventMouse).position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	return (event as InputEventScreenDrag).position
