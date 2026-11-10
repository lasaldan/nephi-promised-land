extends Control

# Three save slots. Pressing a card sets StoryState.slot and opens the world,
# which loads that slot on start (world.gd resume_from_save) or begins fresh
# when the slot is empty. The star on a card lists every achievement, earned
# or still to find. Erasing a slot is in Settings (PauseMenu).

const FADE_IN_TIME := 0.8

# Entrance, under the fade up: the logo's letters drop in one by one, the
# cards are dealt one after another, then the buttons rise. Leaving for the
# game is a hard cut.
# One image per letter of the logo (spaces too), from tools/make_menu_title.py.
const LOGO_LETTERS := 17
const LETTER_DROP := 40.0
const LETTER_STAGGER := 0.07
const LETTER_TIME := 0.6
const SUBTITLE_TIME := 0.5
const CARD_START := 0.35
const CARD_STAGGER := 0.12
const CARD_TIME := 0.45
const CARD_TILT := 8.0
const BUTTON_START := 0.75
const BUTTON_STAGGER := 0.08
const BUTTON_RISE := 48.0
const BUTTON_TIME := 0.45

# The slot the achievement list is showing, 0 while it is closed.
var _slot_listed := 0
# Sound and screen settings, the same panel the in-game pause menu shows.
var _settings: PauseMenu

func _ready() -> void:
	for card in _slot_cards():
		card.play_requested.connect(_on_slot_play_requested)
		card.achievements_requested.connect(_open_achievements)
	%AchievementList.closed.connect(_close_achievements)
	_settings = PauseMenu.create(false)
	add_child(_settings)
	_settings.closed.connect(%SettingsButton.grab_focus)
	_settings.save_cleared.connect(func(slot: int) -> void: _slot_cards()[slot - 1].refresh())
	%SettingsButton.pressed.connect(_settings.open)
	%CreditsButton.pressed.connect(_open_credits)
	# iOS apps may not quit themselves (quit() does nothing there), so drop
	# the button and centre Settings and Credits where the three sat.
	if OS.has_feature("ios"):
		$ExitButton.queue_free()
		%SettingsButton.offset_left = -102.0
		%SettingsButton.offset_right = -6.0
		%CreditsButton.offset_left = 6.0
		%CreditsButton.offset_right = 102.0
	_focus_first_card()
	# Already playing when arriving from the splash; back from the game or
	# the credits, it fades up again.
	MenuMusic.start(get_tree())
	# Arrives from the splash on black, so fade up from it.
	%Fader.visible = true
	%Fader.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(%Fader, "modulate:a", 0.0, FADE_IN_TIME)
	tween.tween_callback(%Fader.hide)
	_play_entrance()

func _play_entrance() -> void:
	var tween := create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Each letter is a copy of the logo holding only that letter, laid over
	# it; once they have all landed the whole logo shows in their place, so
	# the cuts between letters never show at rest.
	var letters := _add_logo_letters()
	%Logo.self_modulate.a = 0.0
	for i in letters.size():
		var letter := letters[i]
		var delay := LETTER_STAGGER * i
		letter.position.y -= LETTER_DROP
		letter.modulate.a = 0.0
		tween.tween_property(letter, "position:y", LETTER_DROP, LETTER_TIME).as_relative() \
				.set_delay(delay)
		tween.tween_property(letter, "modulate:a", 1.0, LETTER_TIME * 0.5).set_delay(delay) \
				.set_trans(Tween.TRANS_SINE)
	var logo_time := LETTER_STAGGER * (letters.size() - 1) + LETTER_TIME
	tween.tween_callback(_show_whole_logo.bind(letters)).set_delay(logo_time)
	# As the last letters land the subtitle fades up and its rules draw
	# outward from it. Like the cards, the rules' scale is set by from().
	var subtitle_delay := logo_time * 0.8
	%SubtitleText.modulate.a = 0.0
	tween.tween_property(%SubtitleText, "modulate:a", 1.0, SUBTITLE_TIME).set_delay(subtitle_delay) \
			.set_trans(Tween.TRANS_SINE)
	%RuleLeft.pivot_offset_ratio = Vector2(1.0, 0.5)
	%RuleRight.pivot_offset_ratio = Vector2(0.0, 0.5)
	for rule: Control in [%RuleLeft, %RuleRight]:
		rule.modulate.a = 0.0
		tween.tween_property(rule, "scale:x", 1.0, SUBTITLE_TIME).from(0.0).set_delay(subtitle_delay) \
				.set_trans(Tween.TRANS_SINE)
		tween.tween_property(rule, "modulate:a", 1.0, SUBTITLE_TIME * 0.5).set_delay(subtitle_delay) \
				.set_trans(Tween.TRANS_SINE)
	# Each card pops up from small and tilted, the outer two tilting outward.
	# The Slots box resets scale and rotation when it lays the cards out, which
	# comes after _ready, so from() sets them only as each card's turn starts.
	var cards := _slot_cards()
	for i in cards.size():
		var card: Control = cards[i]
		var delay := CARD_START + CARD_STAGGER * i
		var tilt := CARD_TILT * (i - (cards.size() - 1) / 2.0)
		card.pivot_offset_ratio = Vector2(0.5, 0.5)
		card.modulate.a = 0.0
		tween.tween_property(card, "scale", Vector2.ONE, CARD_TIME).from(Vector2.ONE * 0.6) \
				.set_delay(delay)
		tween.tween_property(card, "rotation_degrees", 0.0, CARD_TIME).from(tilt).set_delay(delay)
		tween.tween_property(card, "modulate:a", 1.0, CARD_TIME * 0.5).set_delay(delay).set_trans(Tween.TRANS_SINE)
	var buttons: Array[Control] = [%SettingsButton, %CreditsButton]
	if not $ExitButton.is_queued_for_deletion():
		buttons.append($ExitButton)
	for i in buttons.size():
		var button := buttons[i]
		var delay := BUTTON_START + BUTTON_STAGGER * i
		button.position.y += BUTTON_RISE
		button.modulate.a = 0.0
		tween.tween_property(button, "position:y", -BUTTON_RISE, BUTTON_TIME).as_relative() \
				.set_delay(delay)
		tween.tween_property(button, "modulate:a", 1.0, BUTTON_TIME * 0.5).set_delay(delay).set_trans(Tween.TRANS_SINE)

func _add_logo_letters() -> Array[TextureRect]:
	var letters: Array[TextureRect] = []
	for i in LOGO_LETTERS:
		var letter := TextureRect.new()
		letter.texture = load("res://ui/menu_title_letters/%d.png" % i)
		letter.expand_mode = %Logo.expand_mode
		letter.stretch_mode = %Logo.stretch_mode
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		%Logo.add_child(letter)
		letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		letters.append(letter)
	return letters

func _show_whole_logo(letters: Array[TextureRect]) -> void:
	%Logo.self_modulate.a = 1.0
	for letter in letters:
		letter.queue_free()

func _slot_cards() -> Array[Node]:
	return $Slots.get_children()

# The first slot with a save, or slot 1 when they are all empty.
func _focus_first_card() -> void:
	var cards := _slot_cards()
	for card in cards:
		if card.has_save():
			card.grab_focus()
			return
	cards[0].grab_focus()

func _on_slot_play_requested(slot: int) -> void:
	StoryState.slot = slot
	# Always, so nothing carries over from a game left through the pause
	# menu. The world loads this slot's save on top, when it has one.
	StoryState.reset()
	StoryState.slot_chosen = true
	# The cut to the game is hard, but the music fades under the world's own.
	MenuMusic.stop(1.0)
	get_tree().change_scene_to_file("res://world/world.tscn")

func _open_achievements(slot: int) -> void:
	_slot_listed = slot
	%AchievementList.open(tr("Save %d") % slot, StoryState.slot_achievements(slot))

func _close_achievements() -> void:
	var slot := _slot_listed
	_slot_listed = 0
	_slot_cards()[slot - 1].grab_focus()

# Every credit, the character sprites' authors too, which the end of the
# game leaves out. Fades to black first; the credits open on black.
func _open_credits() -> void:
	Credits.full = true
	# The credits bring their own music; this fades with the picture.
	MenuMusic.stop(FADE_IN_TIME)
	%Fader.visible = true
	var tween := create_tween()
	tween.tween_property(%Fader, "modulate:a", 1.0, FADE_IN_TIME)
	tween.tween_callback(get_tree().change_scene_to_file.bind("res://menus/credits.tscn"))

func _on_exit_button_pressed() -> void:
	get_tree().quit()
