extends Control

class_name AchievementList

# Every achievement in Achievements.LIST order, earned ones lit and the rest
# faded. A description stays hidden (HIDDEN_DESCRIPTION) until it is earned,
# so the list does not give the story away; the names still show how many
# are left to find. The main menu opens it from a save card's star, and the
# pause menu from its own star. Done or Escape closes it.

signal closed

const STAR: Texture2D = preload("res://ui/star.svg")
# An achievement not earned yet: a faded star and dimmer words.
const MISSING_STAR := Color(0.25, 0.22, 0.2, 0.7)
const EARNED_NAME := Color(1, 0.86, 0.45, 1)
const MISSING_NAME := Color(0.7, 0.65, 0.55, 1)
const DESCRIPTION := Color(0.8, 0.75, 0.65, 1)
const HIDDEN_DESCRIPTION := "Keep playing to discover this one."
const MISSING_DESCRIPTION := Color(0.6, 0.55, 0.48, 1)

func _ready() -> void:
	%DoneButton.pressed.connect(close)

# heading goes before the count, as in "Save 1: 5/13".
func open(heading: String, earned: Array[String]) -> void:
	%ListTitle.text = tr("%s: %d/%d") % [heading, earned.size(), Achievements.LIST.size()]
	for row in %Rows.get_children():
		row.free()
	for id in Achievements.LIST:
		%Rows.add_child(_row(Achievements.LIST[id], earned.has(id)))
	%Scroll.scroll_vertical = 0
	show()
	%DoneButton.grab_focus()

func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()

func _row(info: Dictionary, earned: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var star := TextureRect.new()
	star.texture = STAR
	star.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	star.custom_minimum_size = Vector2(16, 16)
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not earned:
		star.modulate = MISSING_STAR
	row.add_child(star)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	row.add_child(words)
	var title := Label.new()
	title.text = Language.t(info.name, "achievement")
	title.add_theme_color_override("font_color", EARNED_NAME if earned else MISSING_NAME)
	words.add_child(title)
	var about := Label.new()
	about.text = Language.t(info.description, "achievement") if earned else HIDDEN_DESCRIPTION
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.add_theme_font_size_override("font_size", 10)
	about.add_theme_color_override("font_color", DESCRIPTION if earned else MISSING_DESCRIPTION)
	words.add_child(about)
	return row

# Escape (or a gamepad's back) closes the list before anything under it,
# such as the pause menu, sees the key.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
