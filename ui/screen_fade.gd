class_name ScreenFade
extends CanvasLayer

# Fades the whole screen to and from black. It is drawn in screen space, so it
# covers the view whatever the window shape, camera or zoom, and switching
# cameras while it is black shows nothing. Over the world, under the HUD (2)
# and everything above it, so dialogue, scrolls and captions still show on
# black. world.gd adds it as "ScreenFade".
#   await fade.fade_out()    # to black, returns when black
#   fade.fade_in()           # from black, without waiting

const LAYER := 1

# Emitted when a fade finishes or is cut short by another.
signal settled

var _rect := ColorRect.new()
var _tween: Tween

func _init() -> void:
	layer = LAYER
	_rect.color = Color.BLACK
	_rect.color.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)

# Black or clear at once, stopping any fade.
func set_black(black: bool) -> void:
	_stop()
	_rect.color.a = 1.0 if black else 0.0

func is_fading() -> bool:
	return _tween != null and _tween.is_running()

# From where it is now to black, so fading an already black screen stays black.
func fade_out(seconds: float = 1.0) -> void:
	await _fade_to(1.0, seconds)

# Starts black on this frame, so a camera switched to in the same frame never
# shows unfaded.
func fade_in(seconds: float = 1.0) -> void:
	_stop()
	_rect.color.a = 1.0
	await _fade_to(0.0, seconds)

func _fade_to(alpha: float, seconds: float) -> void:
	_stop()
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", alpha, seconds)
	_tween.finished.connect(settled.emit)
	await settled

# Anyone awaiting the old fade wakes now rather than never.
func _stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
		settled.emit()
