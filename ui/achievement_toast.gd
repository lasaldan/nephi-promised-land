extends CanvasLayer

class_name AchievementToast

# A star and the achievement's name slide down from the top middle of the
# screen to just below the pause tab when StoryState.achievement_unlocked
# fires, stay a moment, and slide back up. Several at once wait their turn. world.gd adds one on its own
# layer, above the cutscene overlay, so a toast at the end of a chapter shows
# over the fade to black.

const STAR: Texture2D = preload("res://ui/star.svg")
# Plays as each toast slides in.
const SOUND: AudioStream = preload("res://audio/sfx/achievement.mp3")
const SLIDE_SECONDS := 0.35
const SHOW_SECONDS := 2.5
# Top of the panel while it is shown: just below the pause tab, whose bottom
# edge is at 20 (pause_menu.tscn).
const MARGIN := 24.0

var _panel: PanelContainer
var _name_label: Label
var _queue: Array[String] = []
var _showing := false
var _sound: AudioStreamPlayer

func _init() -> void:
	layer = 100

func _ready() -> void:
	_build()
	StoryState.achievement_unlocked.connect(_on_unlocked)

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.06, 0.9)
	style.border_color = Color("#f2c14e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	var star := TextureRect.new()
	star.texture = STAR
	star.custom_minimum_size = Vector2(16, 16)
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(star)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var heading := Label.new()
	heading.text = "Achievement"
	heading.add_theme_font_size_override("font_size", 8)
	heading.add_theme_color_override("font_color", Color("#f2c14e"))
	text.add_child(heading)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 12)
	text.add_child(_name_label)

	_panel.visible = false
	add_child(_panel)

	_sound = AudioStreamPlayer.new()
	_sound.name = "Sound"
	_sound.stream = SOUND
	_sound.bus = GameSettings.SFX
	add_child(_sound)

func _on_unlocked(id: String) -> void:
	_queue.append(id)
	if not _showing:
		_show_next()

func _show_next() -> void:
	_showing = true
	while not _queue.is_empty():
		_name_label.text = Achievements.display_name(_queue.pop_front())
		# Let the label measure its new text before the panel is sized to it.
		await get_tree().process_frame
		_panel.reset_size()
		var width := get_viewport().get_visible_rect().size.x
		var hidden_y := -_panel.size.y - 2.0
		_panel.position = Vector2(roundf((width - _panel.size.x) / 2.0), hidden_y)
		_panel.visible = true
		_sound.play()
		var tween := create_tween()
		tween.tween_property(_panel, "position:y", MARGIN, SLIDE_SECONDS) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(SHOW_SECONDS)
		tween.tween_property(_panel, "position:y", hidden_y, SLIDE_SECONDS) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tween.finished
		_panel.visible = false
	_showing = false
