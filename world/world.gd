extends Node2D

class_name World

# The game while it is being played: the map, Nephi, everyone in the story,
# the HUD, and the director that plays the chapters in order. Chapters reach
# it as `world` and mostly go through their own helpers (story/chapter.gd),
# but these are the world's own controls:
#
#   day_night        the time of day (world/lighting/day_night.gd)
#   fog              drifting fog over the world (world/weather/fog.gd)
#   rain             rain over the world (world/weather/rain.gd)
#   music            background music (audio/music_playlist.gd)
#   fade             the screen fade (ui/screen_fade.gd)
#   setQuest()       the quest plaque, top left
#   set_hud_visible()
#   ambience(name)   an AmbientZone under Ambience, to turn on or off
#   navigation       where people can walk (world/navigation/world_navigation.gd)
#
# The map goes under GroundLayer: TileMapLayers, and anything else that
# should y-sort with Nephi. PlaceholderGround is only there so an empty map
# is not black; delete it once there is real ground.

# Pick a chapter from the dropdown (the Chapter Picker addon lists
# Story.CHAPTER_SCRIPTS) and press Play. Earlier chapters count as finished,
# so this one runs its real setup() without the walk to reach it. Set it back
# to (none) before a full playthrough.
# Release exports ignore it. Known ids are printed if the name does not match.
# A debug start never reads or writes the save file.
@export var debug_start_chapter: String = ""
# StoryState flags for a debug start, standing in for what earlier chapters
# would have set. {"met_zoram": true}
@export var debug_flags: Dictionary = {}
# Off starts from the beginning every time, for playtesting a full run. The
# save file is left alone until the first chapter completes, then overwritten.
# Only for a world played on its own (F6): a slot picked on the main menu
# always loads, so this can't wipe a real save.
@export var resume_from_save: bool = true

# Every physics frame while the world is in the tree. Chapters wait on this
# (StoryChapter.nextFrame()), not the SceneTree's physics_frame, which keeps
# firing after Main Menu frees the world, so a chapter's wait loop would wake
# up and reach for a world that is gone. This one stops with the world.
signal physics_tick

# SignalBus and DialogueManager are autoloads, so they outlive the world too.
# A chapter left waiting on one of them when the player quits to the menu
# would wake in the next game and reach for this freed world, which can crash
# on Android. Chapters wait on these copies instead, which stop with the world.
signal item_added(item: InventoryItem)
signal dialogue_ended

@onready var day_night: DayNight = $DayNight
@onready var fog: Fog = $Fog
@onready var rain: Rain = $Rain
@onready var music: MusicPlaylist = $Ambience/Music
@onready var navigation: WorldNavigation = $Navigation
@onready var player: CharacterBody2D = $Player
var fade: ScreenFade

# The flag the hour is saved under with each chapter.
const TIME_OF_DAY_FLAG := "time_of_day"
# And how thick the fog is.
const FOG_FLAG := "fog_density"
# And how hard it is raining.
const RAIN_FLAG := "rain_intensity"
# And how often lightning strikes in it.
const LIGHTNING_FLAG := "lightning_every"

func _ready() -> void:
	GameSettings.ensure_loaded()
	_route_audio()
	# Freeing the world disconnects these, so the copies go quiet with it.
	SignalBus.player_item_added.connect(item_added.emit)
	DialogueManager.dialogue_ended.connect(func(_resource: DialogueResource) -> void: dialogue_ended.emit())
	# The scene-tree eye writes `visible`, and Play keeps that. Layers hidden
	# so the map is easy to see would otherwise stay hidden for the session.
	_restore_play_visibility()
	# Black frame until the first chapter fades in.
	fade = ScreenFade.new()
	fade.name = "ScreenFade"
	add_child(fade)
	fade.set_black(true)
	_ready_hud()
	# Its own layer, not under UI, which cutscenes hide.
	add_child(AchievementToast.new())
	# Its own layer too, so it can be opened during a cutscene.
	var pause_menu := PauseMenu.create(true)
	pause_menu.tour_requested.connect(showUiTour)
	add_child(pause_menu)
	var small_talk := SmallTalk.new()
	small_talk.name = "SmallTalk"
	add_child(small_talk)
	if not _apply_debug_start() and (StoryState.slot_chosen or resume_from_save):
		StoryState.load_game()
	day_night.hour = StoryState.get_flag(TIME_OF_DAY_FLAG, day_night.hour)
	fog.density = StoryState.get_flag(FOG_FLAG, fog.density)
	rain.intensity = StoryState.get_flag(RAIN_FLAG, rain.intensity)
	rain.lightning_every = StoryState.get_flag(LIGHTNING_FLAG, rain.lightning_every)
	continueStoryline()

func _physics_process(_delta: float) -> void:
	physics_tick.emit()

func _process(delta: float) -> void:
	_update_hud(delta)
	_tick_played_time(delta)

# Puts each player on the bus whose volume the settings menu sets. Done here
# rather than in the scene so it can't be lost to an unrelated scene edit.
func _route_audio() -> void:
	music.bus = GameSettings.MUSIC
	$Ambience/Narration.bus = GameSettings.VOICE
	$Ambience/Narration.add_to_group(GameSettings.VOICE_PLAYERS)

# Editor hides that must not survive into play. The HUD toggle only flips the
# UI layer, so a child hidden on its own stays gone after the cutscene.
func _restore_play_visibility() -> void:
	for path in ["Cutscene", "UI/Virtual Joystick", "UI/Inventory", "UI/UseButtonHolder"]:
		var node := get_node_or_null(NodePath(path)) as CanvasItem
		if node == null:
			push_warning("Play visibility: missing %s" % path)
			continue
		node.visible = true

# --- World controls ---

func set_hud_visible(shown: bool) -> void:
	$UI.visible = shown

func is_hud_visible() -> bool:
	return $UI.visible

# An AmbientZone under Ambience by node name, or null.
#   world.ambience("MountainWind").enabled = false
func ambience(zone_name: String) -> AmbientZone:
	return get_node_or_null("Ambience/" + zone_name) as AmbientZone

# --- The story ---

# Set while the chapter it names is running, so the quest signal handler
# knows which id ends it.
var _expected_quest_id := ""
var _pending_quest_id := ""
var _debug_started := false

func continueStoryline() -> void:
	var story := Story.new()
	while true:
		var chapter := story.next_chapter(StoryState.completed_chapter_ids)
		if chapter == null:
			print("Storyline complete")
			_clock_running = false
			await _play_after_story()
			return
		print("Starting chapter %d/%d: %s (%s)" % [story.chapter_index(chapter.id) + 1,
				Story.CHAPTER_SCRIPTS.size(), chapter.id, chapter.title])
		# Listen before setup(). setup() arms this chapter's triggers, and a
		# player already standing in one can complete it on the next physics frame.
		_begin_quest_watch(chapter)
		_quiet_zones(chapter.quiet_zones)
		await chapter.setup(self)
		await _play_until_end(chapter)
		_end_quest_watch()
		# A held chapter is the world from here on. end() would hide its Set
		# and free the family, so the camp would vanish as soon as it appeared.
		if chapter.ends_on == StoryChapter.END_ON_HOLD:
			return
		StoryState.complete_chapter(chapter.id)
		Collectable.remember_collected(get_tree())
		StoryState.set_flag(TIME_OF_DAY_FLAG, day_night.hour)
		StoryState.set_flag(FOG_FLAG, fog.density)
		StoryState.set_flag(RAIN_FLAG, rain.intensity)
		StoryState.set_flag(LIGHTNING_FLAG, rain.lightning_every)
		if not _debug_started:
			StoryState.save_game()
		print("Checkpoint: %s complete%s" % [chapter.id, " (debug start, not saved)" if _debug_started else ", saved"])
		await chapter.end()

# Where a finished save opens (Story.AFTER_STORY_SCRIPT), free to explore.
# Not completed or saved. With none, the world just stays as it is.
func _play_after_story() -> void:
	# A typed local: calling new() on the const itself fails to compile while it is null.
	var after_script: Script = Story.AFTER_STORY_SCRIPT
	if after_script == null:
		fade.fade_in()
		set_hud_visible(true)
		return
	var after := after_script.new() as StoryChapter
	print("Starting %s (%s)" % [after.id, after.title])
	_quiet_zones(after.quiet_zones)
	await after.setup(self)
	await after.play()

func _quiet_zones(names: Array[String]) -> void:
	for zone in get_tree().get_nodes_in_group("ambient_zones"):
		zone.enabled = not names.has(String(zone.name))

func _begin_quest_watch(chapter: StoryChapter) -> void:
	_expected_quest_id = ""
	_pending_quest_id = ""
	if chapter.ends_on == StoryChapter.END_ON_CUTSCENE or chapter.ends_on == StoryChapter.END_ON_HOLD:
		return
	_expected_quest_id = chapter.ends_on
	if not SignalBus.quest_completed.is_connected(_on_quest_completed):
		SignalBus.quest_completed.connect(_on_quest_completed)

# Cutscene chapters end when play() returns. Held chapters do too, and then
# stay active. Quest chapters return from play() after the opening scene,
# then wait here for their own quest id. A chapter that hands off to the next
# Set should fade to black before emitting that id, so the swap happens off
# screen.
func _play_until_end(chapter: StoryChapter) -> void:
	await chapter.play()
	if chapter.ends_on == StoryChapter.END_ON_CUTSCENE or chapter.ends_on == StoryChapter.END_ON_HOLD:
		return
	while _pending_quest_id != chapter.ends_on:
		await SignalBus.quest_completed

func _end_quest_watch() -> void:
	if SignalBus.quest_completed.is_connected(_on_quest_completed):
		SignalBus.quest_completed.disconnect(_on_quest_completed)
	_expected_quest_id = ""
	_pending_quest_id = ""

func _on_quest_completed(quest_id: String) -> void:
	if quest_id == _expected_quest_id:
		_pending_quest_id = quest_id

# True when a debug start is in effect, so the save is neither loaded nor written.
func _apply_debug_start() -> bool:
	var target := debug_start_chapter.strip_edges()
	if target.is_empty() or not OS.is_debug_build():
		return false
	var ids: Array[String] = []
	if not Story.new().prepare_debug_start(target, ids):
		return false
	StoryState.reset()
	StoryState.debug_run = true
	StoryState.completed_chapter_ids.assign(ids)
	for key in debug_flags:
		StoryState.set_flag(str(key), debug_flags[key])
	_debug_started = true
	print("Debug: earlier chapters marked done. Starting at " + target)
	return true

# --- The quest plaque ---

# text is a key in Quests.TEXT (story/text/quests.gd) or the words themselves.
# voice_key names the clip a tap on the plaque reads, for words that are not
# a key themselves. A countdown passes its key in Quests.COUNTED and how many
# are left, and is read as that key:
#   setQuest("quest_more_seeds", "", 3)    Collect 3 more seeds
# An empty text hides the plaque.
func setQuest(text: String, voice_key: String = "", count: int = -1) -> void:
	_quest_source = text
	_quest_count = count
	_show_quest_text()
	%Quest.visible = not text.is_empty()
	if voice_key.is_empty() and (Quests.TEXT.has(text) or Quests.COUNTED.has(text)):
		voice_key = text
	if voice_key != _quest_voice_key:
		_quest_voice.stop()
	_quest_voice_key = voice_key

# What setQuest() was given, so the words can be shown again in a new language.
var _quest_source := ""
var _quest_count := -1

func _show_quest_text() -> void:
	if _quest_count >= 0 and Quests.COUNTED.has(_quest_source):
		%QuestText.text = Quests.counted(_quest_source, _quest_count)
	else:
		%QuestText.text = Quests.lookup(_quest_source)

# Read from the narrator's clip for the key (Language.voice_path) only when
# the plaque is tapped.
const QUEST_VOICE_SPEAKER := "narrator"
var _quest_voice_key := ""
var _quest_voice := AudioStreamPlayer.new()

# A tap while anyone else is speaking is ignored, not saved for later.
func _on_quest_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	%QuestPanel.accept_event()
	if _quest_voice_key.is_empty() or not Language.has_voice(QUEST_VOICE_SPEAKER, _quest_voice_key):
		return
	if not GameSettings.is_enabled(GameSettings.VOICE) or GameSettings.is_voice_playing(get_tree()):
		return
	_quest_voice.stream = Language.voice(QUEST_VOICE_SPEAKER, _quest_voice_key)
	_quest_voice.play()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_played_time()
	# The language was changed in the pause menu: the quest in the new one.
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_show_quest_text()

# --- The rest of the HUD ---

func _ready_hud() -> void:
	# The story opens on a cutscene, which shows the HUD when it is done. The
	# quest plaque stays hidden until setQuest() is given an errand. The scene
	# leaves both visible so they can be edited; play must not.
	%Quest.visible = false
	$UI.visible = false
	_quest_voice.bus = GameSettings.VOICE
	_quest_voice.add_to_group(GameSettings.VOICE_PLAYERS)
	add_child(_quest_voice)
	%QuestPanel.gui_input.connect(_on_quest_input)
	# A RichTextLabel stops the mouse by default; let taps on the words reach the plaque.
	%QuestText.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%UseButton.pressed.connect(func() -> void: player.use())
	%PrayButton.pressed.connect(func() -> void: player.prayer.pray())
	_enlarge_use_button_for_touch()

func _update_hud(delta: float) -> void:
	var prayer: Prayer = player.prayer
	# Up while a prayer has somewhere to point and Nephi is free to pray, and
	# while he prays, so it does not blink away.
	%PrayButton.visible = prayer.praying or prayer.can_pray()
	_highlight_use_button()
	_show_use_icon()
	_show_joystick(delta)

# The joystick hides once Nephi has been unable to walk for this long (a
# cutscene, a talk, a menu, a prayer), so the player watches instead of
# pushing a stick that does nothing. The wait keeps it from blinking during
# short locks.
const HIDE_JOYSTICK_AFTER_SECONDS := 1.0
var _locked_seconds := 0.0

func _show_joystick(delta: float) -> void:
	_locked_seconds = 0.0 if player.can_act() else _locked_seconds + delta
	$"UI/Virtual Joystick".visible = _locked_seconds < HIDE_JOYSTICK_AFTER_SECONDS

# Lit while the use button is held down by touch or mouse, or player_use (E or
# space) is held, so the button shows the press whichever way it came.
const USE_HIGHLIGHT := Color(1.5, 1.4, 0.9)

func _highlight_use_button() -> void:
	var held: bool = %UseButton.is_pressed() or Input.is_action_pressed("player_use")
	%UseButton.modulate = USE_HIGHLIGHT if held else Color.WHITE

# A thumb needs a bigger target than a mouse. Grown from its bottom-right
# corner so it keeps its gap from the screen edges.
const TOUCH_USE_BUTTON_SCALE := 1.6

func _enlarge_use_button_for_touch() -> void:
	if not DisplayServer.is_touchscreen_available():
		return
	var holder: Control = $UI/UseButtonHolder
	holder.pivot_offset = holder.size
	holder.scale = Vector2.ONE * TOUCH_USE_BUTTON_SCALE

# The use button's picture for what a press would do (Interaction.nearest()).
const USE_ICONS := {
	"pickup": preload("res://ui/hand.png"),
	"talk": preload("res://ui/speech.png"),
	"look": preload("res://ui/magnify.png"),
}

func _show_use_icon() -> void:
	var target := Interaction.nearest(get_tree(), player.global_position)
	var kind: String = target.interact_kind() if target else "pickup"
	%UseButton.icon = USE_ICONS.get(kind, USE_ICONS["pickup"])

# The tour of the controls (ui/ui_tour.gd), in Nephi's words
# (story/text/tour_lines.gd). A chapter plays it once with showUiTour(), and
# the pause menu's Controls button replays it. Each lit control is shown for
# the tour even where play has it hidden; it is all put back after.
const UI_TOUR_DONE_FLAG := "ui_tour_done"
var _ui_tour: UiTour

func showUiTour() -> void:
	if _ui_tour:
		return
	# Not is_touchscreen_available(): the project emulates touch from the mouse,
	# so that is true on desktop too.
	var device := "touch" if OS.has_feature("mobile") else "desktop"
	var steps := [
		{"target": $"UI/Virtual Joystick/Base", "line": "tour_walk_" + device},
		{"target": %UseButton, "line": "tour_use_" + device},
		{"target": %QuestPanel, "line": "tour_quest_" + device},
		{"target": %PrayButton, "line": "tour_pray_" + device},
		{"target": $UI/Inventory/Backpack, "line": "tour_backpack"},
	]
	var ui_shown: bool = $UI.visible
	var quest_shown: bool = %Quest.visible
	$UI.visible = true
	%Quest.visible = true
	%PrayButton.visible = true
	$"UI/Virtual Joystick".visible = true
	_ui_tour = UiTour.new(steps)
	add_child(_ui_tour)
	await _ui_tour.finished
	_ui_tour = null
	$UI.visible = ui_shown
	%Quest.visible = quest_shown
	StoryState.set_flag(UI_TOUR_DONE_FLAG, true)

# --- Played time ---

# The clock behind StoryState.played_seconds. Stops once the story is over, so
# a finished save shows how long the game took. Written every
# PLAYED_TIME_SAVE_SECONDS and when the world closes, so quitting partway
# through a chapter keeps the time spent in it.
const PLAYED_TIME_SAVE_SECONDS := 30.0
var _clock_running := true
var _since_time_saved := 0.0

# Only while unpaused: the pause menu pauses the tree, and this node with it.
func _tick_played_time(delta: float) -> void:
	if not _clock_running:
		return
	StoryState.played_seconds += delta
	_since_time_saved += delta
	if _since_time_saved >= PLAYED_TIME_SAVE_SECONDS:
		_save_played_time()

func _save_played_time() -> void:
	_since_time_saved = 0.0
	StoryState.save_played_time()

# Quitting to the menu frees the world. Closing the window or a phone sending
# the app to the background may never get that far.
func _exit_tree() -> void:
	_save_played_time()
