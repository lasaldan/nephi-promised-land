extends CanvasLayer

class_name UiTour

# A short tour of the HUD: the screen dims except for one control, and a
# bubble beside it says what it does while Nephi reads it aloud (TourLines).
# A tap, click, E, Space or a gamepad's A
# moves to the next bubble; Skip or Escape ends it early. The tree is paused
# while it shows, so nothing moves behind it. world.gd builds the steps from
# its HUD nodes (showUiTour()) and makes sure each one is on screen.
#
#   var tour := UiTour.new([{"target": button, "line": "tour_quest_touch"}])
#   add_child(tour)
#   await tour.finished

signal finished

const MENU_THEME: Theme = preload("res://ui/menu_theme.tres")
const DIM := Color(0, 0, 0, 0.62)
const GOLD := Color(0.95, 0.76, 0.31, 1)
const PANEL_BG := Color(0.29, 0.18, 0.1, 0.97)
# Room around the lit control, so its outline does not sit on its edge.
const HOLE_PADDING := 4.0
# Between the lit control and the bubble. The arrow fills it.
const GAP := 14.0
const ARROW_HALF_WIDTH := 6.0
const SCREEN_MARGIN := 8.0
const BUBBLE_TEXT_WIDTH := 170.0
const FADE_SECONDS := 0.2
# A tap this soon after a bubble shows is ignored. The player may still be
# tapping through the dialogue that came before, and would skip it unread.
const READ_SECONDS := 0.6
# When "Tap to continue" fades in under the text, for a line with no clip or
# with the narrator's voice turned off. A spoken line shows it as Nephi finishes.
const HINT_SECONDS := 1.0

# [{"target": Control, "line": TourLines.TEXT key}, ...]
var _steps: Array
var _index := -1
var _shown_at := 0.0
var _was_paused := false
var _hole := Rect2()
# The bubble's side the arrow leaves from: true for its bottom edge.
var _bubble_above := true
var _pulse := 0.0
var _done := false
# Seconds after the bubble shows that the hint comes in.
var _hint_after := HINT_SECONDS

var _overlay: Control
var _bubble: PanelContainer
var _text: Label
var _count: Label
var _hint: Label
var _skip: Button
var _fade: Tween
var _voice: AudioStreamPlayer

func _init(steps: Array) -> void:
	_steps = steps
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_build()
	_was_paused = get_tree().paused
	get_tree().paused = true
	_next()

func _build() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.theme = MENU_THEME
	_overlay.draw.connect(_draw_overlay)
	_overlay.gui_input.connect(_on_overlay_input)
	add_child(_overlay)

	_bubble = PanelContainer.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 4
	_bubble.add_theme_stylebox_override("panel", style)
	_overlay.add_child(_bubble)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(column)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = BUBBLE_TEXT_WIDTH
	_text.add_theme_font_size_override("font_size", 13)
	column.add_child(_text)

	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(footer)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 9)
	_count.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78, 0.6))
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_count)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 9)
	_hint.add_theme_color_override("font_color", GOLD)
	footer.add_child(_hint)

	# Bottom middle: the joystick and the use button hold the bottom corners,
	# the quest, backpack and pause tab the top.
	_skip = Button.new()
	_skip.text = "Skip"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.add_theme_font_size_override("font_size", 10)
	_skip.pressed.connect(_finish)
	# Added first, so its size comes from the menu theme.
	_overlay.add_child(_skip)
	_skip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 8)
	_skip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skip.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Its bus is the one the pause menu calls Narrator.
	_voice = AudioStreamPlayer.new()
	_voice.bus = GameSettings.VOICE
	_voice.add_to_group(GameSettings.VOICE_PLAYERS)
	add_child(_voice)

func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta, 1.2)
	_overlay.queue_redraw()
	if _hint.modulate.a < 1.0 and _since_shown() >= _hint_after:
		_hint.modulate.a = minf(1.0, _hint.modulate.a + delta / FADE_SECONDS)

func _since_shown() -> float:
	return Time.get_ticks_msec() / 1000.0 - _shown_at

func _next() -> void:
	_index += 1
	if _index >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_index]
	var last := _index == _steps.size() - 1
	_text.text = TourLines.text(step["line"])
	_count.text = "%d/%d" % [_index + 1, _steps.size()]
	# Not is_touchscreen_available(), which mouse-to-touch emulation makes true on desktop.
	if OS.has_feature("mobile"):
		_hint.text = tr("Tap to start") if last else tr("Tap to continue")
	else:
		_hint.text = tr("Click to start") if last else tr("Click to continue")
	_hint.modulate.a = 0.0
	_skip.visible = not last
	_hole = _screen_rect(step["target"]).grow(HOLE_PADDING)
	_shown_at = Time.get_ticks_msec() / 1000.0
	_hint_after = HINT_SECONDS
	_bubble.modulate.a = 0.0
	_say(step["line"])
	# The label wraps to its new text over a frame. Place the bubble once its
	# size has settled, still hidden, then fade it in.
	_bubble.reset_size()
	await get_tree().process_frame
	if _done:
		return
	_place_bubble()
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_bubble, "modulate:a", 1.0, FADE_SECONDS)

# Reads the line, cutting off the last one if the player tapped on before it
# ended. The hint waits for him to finish. A line with no clip stays silent.
func _say(line: String) -> void:
	_voice.stop()
	if not GameSettings.is_enabled(GameSettings.VOICE) or not Language.has_voice(TourLines.SPEAKER, line):
		return
	_voice.stream = Language.voice(TourLines.SPEAKER, line)
	_voice.play()
	_hint_after = maxf(HINT_SECONDS, _voice.stream.get_length())

# The control's rectangle on screen, through its layer and any scale (the
# joystick is scaled down, the use button grown for touch).
func _screen_rect(target: Control) -> Rect2:
	var xform := target.get_global_transform_with_canvas()
	return Rect2(xform.origin, target.size * xform.get_scale()).abs()

# Beside the lit control, toward the middle of the screen: above one in the
# bottom half, below one in the top. Lined up with its outer edge, and kept
# on screen.
func _place_bubble() -> void:
	var screen := _overlay.get_rect().size
	var size := _bubble.get_combined_minimum_size()
	_bubble.size = size
	var center := _hole.get_center()
	_bubble_above = center.y > screen.y / 2.0
	var y := _hole.position.y - GAP - size.y if _bubble_above else _hole.end.y + GAP
	var x := _hole.position.x if center.x < screen.x / 2.0 else _hole.end.x - size.x
	x = clampf(x, SCREEN_MARGIN, screen.x - SCREEN_MARGIN - size.x)
	y = clampf(y, SCREEN_MARGIN, screen.y - SCREEN_MARGIN - size.y)
	_bubble.position = Vector2(x, y)

func _draw_overlay() -> void:
	var screen := _overlay.get_rect()
	# Four bands around the hole.
	_overlay.draw_rect(Rect2(0, 0, screen.size.x, _hole.position.y), DIM)
	_overlay.draw_rect(Rect2(0, _hole.end.y, screen.size.x, screen.size.y - _hole.end.y), DIM)
	_overlay.draw_rect(Rect2(0, _hole.position.y, _hole.position.x, _hole.size.y), DIM)
	_overlay.draw_rect(Rect2(_hole.end.x, _hole.position.y, screen.size.x - _hole.end.x, _hole.size.y), DIM)
	# A gold outline that breathes, so the eye finds the lit control.
	var glow := 0.55 + 0.45 * sin(_pulse / 1.2 * TAU)
	_overlay.draw_rect(_hole, Color(GOLD, glow), false, 1.5)
	if _bubble.modulate.a > 0.0:
		_draw_arrow(_bubble.modulate.a)

# From the bubble's edge to the hole, at the hole's middle where the bubble
# reaches that far.
func _draw_arrow(alpha: float) -> void:
	var box := Rect2(_bubble.position, _bubble.size)
	var x := clampf(_hole.get_center().x, box.position.x + 10.0, box.end.x - 10.0)
	var base_y := box.end.y - 1.0 if _bubble_above else box.position.y + 1.0
	var tip_y := _hole.position.y - 2.0 if _bubble_above else _hole.end.y + 2.0
	var points := PackedVector2Array([
		Vector2(x - ARROW_HALF_WIDTH, base_y),
		Vector2(x + ARROW_HALF_WIDTH, base_y),
		Vector2(x, tip_y),
	])
	_overlay.draw_colored_polygon(points, Color(PANEL_BG, alpha))
	_overlay.draw_polyline(PackedVector2Array([points[0], points[2], points[1]]), Color(GOLD, alpha), 1.0)

# Mouse only: touch arrives as an emulated mouse press too, and a desktop
# click as an emulated touch (project settings), so handling both would step twice.
func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_overlay.accept_event()
		_advance()

# Every key and button is the tour's while it shows, so P or Start cannot open
# the pause menu over it.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton):
		return
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("ui_cancel") or (event is InputEventKey and event.physical_keycode == KEY_ESCAPE):
		_finish()
	elif event.is_action("player_use") or event.is_action("ui_accept"):
		_advance()

func _advance() -> void:
	if _since_shown() < READ_SECONDS:
		return
	_next()

func _finish() -> void:
	if _done:
		return
	_done = true
	_voice.stop()
	get_tree().paused = _was_paused
	finished.emit()
	queue_free()
