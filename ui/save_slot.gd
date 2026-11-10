extends Button

# One save slot card on the main menu. The whole card starts or continues the
# game, and the star button asks the menu to list the slot's achievements.
# Clearing a slot lives in the Settings panel, away from little fingers.

signal play_requested(slot: int)
signal achievements_requested(slot: int)

# 1-based, matching StoryState.slot and the number drawn on the card.
@export_range(1, 3) var slot := 1

func _ready() -> void:
	pressed.connect(func(): play_requested.emit(slot))
	%AchievementsButton.pressed.connect(func(): achievements_requested.emit(slot))
	refresh()

# "45% complete" is built from pieces, so it is built again in a new language.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()

func has_save() -> bool:
	return StoryState.has_save(slot)

func refresh() -> void:
	var info := StoryState.slot_summary(slot)
	%Number.text = str(slot)
	%Stats.visible = info.exists
	_set_blank_look(not info.exists)
	if info.exists:
		%Status.text = tr("%d%% complete") % info.percent
		%Progress.value = info.percent
		%AchievementsButton.text = "%d/%d" % [info.achievements, info.achievement_total]
		%PlayedTime.text = _format_played_time(info.played_seconds)
	else:
		%Status.text = "New Game"

# Background opacity of an empty card in each state, low enough that the menu
# art shows through; a dotted outline (_draw) stands in for the solid border.
const BLANK_ALPHA := {"normal": 0.12, "hover": 0.3, "pressed": 0.42, "hover_pressed": 0.42}
const DOT_COLOR := Color(0.95, 0.76, 0.31, 0.9)
const DOT_INSET := 2.0

var _blank := false

# Empty slots swap the theme's solid card for a see-through one so a first-time
# player can see the background art; slots with a save keep the solid card.
func _set_blank_look(blank: bool) -> void:
	_blank = blank
	for state in BLANK_ALPHA:
		remove_theme_stylebox_override(state)
		if blank:
			var box := get_theme_stylebox(state).duplicate() as StyleBoxFlat
			box.bg_color.a = BLANK_ALPHA[state]
			box.border_color = Color.TRANSPARENT
			add_theme_stylebox_override(state, box)
	# Keeps "New Game" readable against the art behind it.
	if blank:
		%Status.add_theme_color_override("font_outline_color", Color(0.2, 0.11, 0.05, 1))
		%Status.add_theme_constant_override("outline_size", 4)
	else:
		%Status.remove_theme_color_override("font_outline_color")
		%Status.remove_theme_constant_override("outline_size")
	queue_redraw()

func _draw() -> void:
	if not _blank:
		return
	var r := Rect2(Vector2.ONE * DOT_INSET, size - Vector2.ONE * DOT_INSET * 2)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], DOT_COLOR, 2.0, 4.0)

# For playtesting: time played on this slot (StoryState.played_seconds), as
# 1:05:09 or, under an hour, 5:09.
@warning_ignore("integer_division")
static func _format_played_time(seconds: float) -> String:
	var total := int(seconds)
	var hours := total / 3600
	var minutes := (total / 60) % 60
	var secs := total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	return "%d:%02d" % [minutes, secs]
