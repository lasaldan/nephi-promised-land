extends CanvasLayer

class_name PauseMenu

# The pause tab poking down from the top centre of the screen, and the menu it opens: on/off and
# loudness for music, sounds and the narrator, full screen on desktop, the
# language (English or Spanish, GameSettings.language()), the
# slot's achievements (the star), a replay of the controls tour, and the way back to the main menu. Escape,
# P or a gamepad's Start opens and closes it too. The tree is paused while it is open. Chapter.delay() and
# other story waits use pausable timers, so a cutscene waits as well.
#
# world.gd adds one as is. The main menu sets in_game off before adding it
# and calls open() from its Settings button: no pause button, no pausing,
# no Main menu button, no achievements, and Resume reads Done. In their
# place it shows a Clear button per save slot, each asking before it erases.

signal closed
# The Controls button: the menu closes and world.gd replays the tour of the HUD.
signal tour_requested
# A slot's save was erased from the main menu's Settings, so its card redraws.
signal save_cleared(slot: int)

const SCENE_PATH := "res://ui/pause_menu.tscn"
const MAIN_MENU := "res://menus/main_menu.tscn"

var in_game := true
# The slot the erase prompt is asking about, 0 while it is closed.
var _slot_to_clear := 0

static func create(for_game: bool) -> PauseMenu:
	# load(), not preload(): this script is the scene's own, and would load itself.
	var menu: PauseMenu = load(SCENE_PATH).instantiate()
	menu.in_game = for_game
	return menu

func _ready() -> void:
	GameSettings.ensure_loaded()
	%PauseButton.visible = in_game
	%MainMenuButton.visible = in_game
	%AchievementsButton.visible = in_game
	%ControlsButton.visible = in_game
	%Title.text = "Paused" if in_game else "Settings"
	%ResumeButton.text = "Resume" if in_game else "Done"
	_bind_sound(%MusicToggle, %MusicSlider, GameSettings.MUSIC)
	_bind_sound(%SfxToggle, %SfxSlider, GameSettings.SFX)
	_bind_sound(%VoiceToggle, %VoiceSlider, GameSettings.VOICE)
	# A chime when the sounds slider is let go, so a parent hears the new level.
	%SfxSlider.drag_ended.connect(func(_changed: bool) -> void: %SoundPreview.play())
	%SfxToggle.toggled.connect(func(on: bool) -> void:
		if on:
			%SoundPreview.play())
	%FullscreenLabel.visible = GameSettings.can_fullscreen()
	%FullscreenToggle.visible = GameSettings.can_fullscreen()
	%FullscreenToggle.button_pressed = GameSettings.is_fullscreen()
	%FullscreenToggle.toggled.connect(func(on: bool) -> void: GameSettings.set_fullscreen(on))
	%PauseButton.pressed.connect(open)
	%ResumeButton.pressed.connect(close)
	%MainMenuButton.pressed.connect(_ask_leave)
	%AchievementsButton.pressed.connect(_show_achievements)
	%ControlsButton.pressed.connect(_show_controls)
	%AchievementList.closed.connect(%AchievementsButton.grab_focus)
	%StayButton.pressed.connect(_close_leave)
	%LeaveButton.pressed.connect(_leave)
	%ClearSaves.visible = not in_game
	if not in_game:
		for slot in range(1, StoryState.SLOT_COUNT + 1):
			var button := Button.new()
			button.text = tr("Clear %d") % slot
			button.custom_minimum_size.x = 64
			button.add_theme_color_override("font_color", Color(1, 0.78, 0.74, 1))
			button.pressed.connect(_ask_clear.bind(slot))
			%ClearSaves.add_child(button)
	%KeepButton.pressed.connect(_close_clear)
	%EraseButton.pressed.connect(_erase)
	_fill_language_picker()

# Each language under its own name. Picking one switches the game over at
# once; it is saved with the rest when the menu closes.
func _fill_language_picker() -> void:
	var picker: OptionButton = %LanguagePicker
	picker.clear()
	for language in Language.SUPPORTED:
		picker.add_item(Language.NAMES[language])
		picker.set_item_metadata(picker.item_count - 1, language)
		if language == GameSettings.language():
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void:
		GameSettings.set_language(picker.get_item_metadata(index)))

# The labels set from the scene translate themselves; these are built from
# pieces, so they are built again in the new language.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		for button: Button in %ClearSaves.get_children():
			button.text = tr("Clear %d") % (button.get_index() + 1)
		if _slot_to_clear > 0:
			%ClearTitle.text = tr("Erase save %d?") % _slot_to_clear

func _bind_sound(toggle: CheckButton, slider: HSlider, bus: StringName) -> void:
	toggle.button_pressed = GameSettings.is_enabled(bus)
	slider.value = GameSettings.volume(bus)
	slider.editable = toggle.button_pressed
	toggle.toggled.connect(func(on: bool) -> void:
		GameSettings.set_enabled(bus, on)
		slider.editable = on)
	slider.value_changed.connect(func(value: float) -> void: GameSettings.set_volume(bus, value))

func is_open() -> bool:
	return %Menu.visible

func open() -> void:
	if is_open():
		return
	if in_game:
		get_tree().paused = true
	%PauseButton.hide()
	%AchievementsButton.text = "%d/%d" % [StoryState.achievements.size(), Achievements.LIST.size()]
	_refresh_clear_buttons()
	%Menu.show()
	%ResumeButton.grab_focus()

func close() -> void:
	if not is_open():
		return
	GameSettings.save()
	_close_leave()
	_close_clear()
	%AchievementList.close()
	%Menu.hide()
	%PauseButton.visible = in_game
	if in_game:
		get_tree().paused = false
	closed.emit()

# Earned in this game so far, including any since the last save.
func _show_achievements() -> void:
	%AchievementList.open(tr("Save %d") % StoryState.slot, StoryState.achievements)

func _show_controls() -> void:
	close()
	tour_requested.emit()

func _ask_leave() -> void:
	%SettingsPanel.hide()
	%LeavePanel.show()
	%StayButton.grab_focus()

func _close_leave() -> void:
	if not %LeavePanel.visible:
		return
	%LeavePanel.hide()
	%SettingsPanel.show()
	%MainMenuButton.grab_focus()

func _leave() -> void:
	GameSettings.save()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)

# Empty slots have nothing to clear, so their buttons are greyed out.
func _refresh_clear_buttons() -> void:
	for button: Button in %ClearSaves.get_children():
		button.disabled = not StoryState.has_save(button.get_index() + 1)

func _ask_clear(slot: int) -> void:
	_slot_to_clear = slot
	%ClearTitle.text = tr("Erase save %d?") % slot
	%SettingsPanel.hide()
	%ClearPanel.show()
	%KeepButton.grab_focus()

func _close_clear() -> void:
	if not %ClearPanel.visible:
		return
	var button: Button = %ClearSaves.get_child(_slot_to_clear - 1)
	_slot_to_clear = 0
	%ClearPanel.hide()
	%SettingsPanel.show()
	if button.disabled:
		%ResumeButton.grab_focus()
	else:
		button.grab_focus()

func _erase() -> void:
	var slot := _slot_to_clear
	StoryState.delete_save(slot)
	_refresh_clear_buttons()
	_close_clear()
	save_cleared.emit(slot)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_pause_key(event):
		return
	if not is_open():
		# On the main menu the Settings button opens it, not a key.
		if not in_game:
			return
		open()
	elif %LeavePanel.visible:
		_close_leave()
	elif %ClearPanel.visible:
		_close_clear()
	else:
		close()
	get_viewport().set_input_as_handled()

func _is_pause_key(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if event is InputEventKey:
		return event.physical_keycode in [KEY_ESCAPE, KEY_P]
	if event is InputEventJoypadButton:
		return event.button_index == JOY_BUTTON_START
	return false
