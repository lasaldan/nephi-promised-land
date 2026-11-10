extends Resource

class_name StoryChapter

# END_ON_CUTSCENE: play() finishing is the end of the chapter.
# END_ON_HOLD: play() returns and the chapter stays active (its Set and actors remain).
# Any other ends_on value is a quest id. Fade out before emitting that id when the
# next chapter should replace this one, so its setup() runs on a black screen.
const END_ON_CUTSCENE := "cutscene"
const END_ON_HOLD := "hold"

# Stable id used by starts_after and by future saves. Not the filename.
var id: String = ""
var title: String = ""
# Chapter id that must already be complete. Empty means this chapter may start immediately.
var starts_after: String = ""
# END_ON_CUTSCENE, or the quest id that completes this chapter.
var ends_on: String = END_ON_CUTSCENE
# The ChapterContent under Chapters this chapter shows, when it is not the
# one named by id. Several chapters can share one Set this way, such as the
# coast camp segments, each a save point in the same camp.
var set_id: String = ""
# The chapter whose place in Story.CHAPTER_SCRIPTS decides which PropGroups
# show (appears_in, gone_after), when it is not this one: a chapter outside
# that list stands at that point in the story. Empty means id.
var story_point_id: String = ""
# Ambient sounds (world/ambience/ambient_zone.gd) to keep quiet while this
# chapter runs, by node name, such as a wind the opening scene should not have.
var quiet_zones: Array[String] = []

var world
var spawnedCharacters = []

func setup(w:Node2D):
	print("Setting up Chapter")
	world = w
	# A goal left by the chapter before must not steer this one's prayers.
	clearGuidance()
	# Shows this chapter's Set, arms its starts_armed areas, and hides every other
	# chapter. Content lives in chapters.tscn. An id with no node hides them all.
	var chapters := _chapters()
	if chapters:
		chapters.activate_chapter(id if story_point_id.is_empty() else story_point_id, content_id())
	# Gone for good once a chapter used them up (useUpProps()).
	for prop_name in getFlag(USED_UP_FLAG, []):
		_hide_prop(prop_name)
	
func play():
	print("Playing chapter")

# The ChapterContent this chapter's props, triggers and scenes live in.
func content_id() -> String:
	return id if set_id.is_empty() else set_id

# World-pixel positions of actors setup() will spawn. The Chapters node shows
# these in the editor when its preview id matches this chapter. Return nothing
# once those actors live in the Set instead of being spawned here, or the
# preview will show people the chapter no longer creates.
func preview_spawns() -> Array[Dictionary]:
	return []

# transient actors are removed in end(). Pass false to leave someone who should
# stay and walk (the family, once they live at the coast). Tents and other
# scenery belong in that chapter's Set under Chapters. id, when given, is the
# name getCharacter() finds them by instead of a numbered scene name.
func spawnCharacter(name:String = "sheep", position:Vector2 = Vector2(0,0), input_vector:Vector2 = Vector2(0,0), transient:bool = true, id:String = ""):
	var character = Cast.scene(name).instantiate()
	character.position = position * 32
	character.input_vector = input_vector
	character.set_meta("transient", transient)
	var cutscene: Node = world.get_node("Cutscene")
	if id.is_empty():
		character.name = _unique_character_name(cutscene, name.to_pascal_case())
	else:
		if cutscene.has_node(id.to_pascal_case()):
			push_error("Character id '%s' is already taken under Cutscene" % id)
		character.name = id.to_pascal_case()
	cutscene.add_child(character)
	print("added "+name)
	spawnedCharacters.append(character)
	return character

# The first chicken is Chicken, the next Chicken2, then Chicken3, so
# getCharacter("chicken2") finds the second one. Counts everyone under
# Cutscene, including persistent actors left by an earlier chapter.
func _unique_character_name(parent: Node, base: String) -> String:
	if not parent.has_node(base):
		return base
	var n := 2
	while parent.has_node(base + str(n)):
		n += 1
	return base + str(n)

# Spawn a chapter's characters list. Each entry needs "name" and "start" (tiles).
# Optional: "move" (starting input_vector), "facing", "delay" (seconds to
# wait before this one appears), "habit" (what they do when the story is
# not directing them, one Habit instance per entry), and "id" (the name
# getCharacter() finds them by, for telling repeats like chickens apart).
# offset in tiles is added to every start, so a layout can be reused
# somewhere else. Await it when any entry has a delay.
#   {"name": "sam", "start": Vector2(-36.5, -46.5), "habit": Meander.new(2)},
#   {"name": "chicken", "id": "tent_hen", "start": Vector2(-25, -48)},
func spawnCharacters(list: Array, offset: Vector2 = Vector2.ZERO, transient: bool = true) -> void:
	for character in list:
		if character.has("delay"):
			await delay(character["delay"])
		var spawned = spawnCharacter(character["name"], character["start"] + offset, character.get("move", Vector2.ZERO), transient, character.get("id", ""))
		if character.has("facing"):
			spawned.facing = character["facing"]
		if character.has("habit"):
			spawned.set_habit(character["habit"])

# Editor marks for a characters list, for use in preview_spawns().
func previewCharacters(list: Array, offset: Vector2 = Vector2.ZERO) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	for character in list:
		marks.append({
			"label": character["name"],
			"position": (character["start"] + offset) * 32,
		})
	return marks

# Walk someone in a direction for a while, then stop. Clears facing first,
# because a set facing holds the pose and zeroes input_vector every frame.
# Pauses an NPC's habit until who.release(). Straight ahead, no pathfinding.
#   await walk(lehi, Vector2.DOWN, 3.2)
func walk(who: Node2D, direction: Vector2, seconds: float) -> void:
	_hold(who)
	who.facing = ""
	who.input_vector = direction
	await delay(seconds)
	who.input_vector = Vector2.ZERO

# Walk an NPC to a tile, the same tile coordinates a characters list uses for
# "start", and wait until they get there. They follow the navigation path
# around walls and steer around other walkers (Npc). They give up when no
# progress has been made for stuck_seconds. speed scales input_vector, so 1.0 matches
# walk(who, DOWN, ...). They hold at the end, habit paused, until who.release().
# Returns true when they arrived, false when they gave up.
# To send them without waiting, call who.go_to(tile) instead.
#   await walkTo(lehi, Vector2(12, 8))
#   if not await walkTo(sam, Vector2(3, 4), 2.0): sam.position = Vector2(3, 4) * 32
func walkTo(who: Npc, tile: Vector2, speed: float = 1.0, stuck_seconds: float = 1.5) -> bool:
	who.go_to(tile, speed, stuck_seconds)
	return await who.arrived

# Walk Nephi to a tile in a cutscene, as walkTo does an NPC, and wait until
# he gets there. Lock controls first. He follows the navigation path around
# walls when the world has one. If he catches on someone for stuck_seconds, he
# walks through them for the rest of the way, so he always arrives. With face,
# he turns that way at the end.
#   disablePlayerControls()
#   await walkPlayerTo(Vector2(4.5, 5.5), "up")
func walkPlayerTo(tile: Vector2, face: String = "", stuck_seconds: float = 1.0) -> void:
	var player = getPlayer()
	var target := tile * 32.0
	var waypoints := WorldNavigation.path(player, target)
	var mask: int = player.collision_mask
	var best := INF
	var since_progress := 0.0
	player.facing = ""
	while not waypoints.is_empty():
		var waypoint: Vector2 = waypoints[0]
		var to_target: Vector2 = waypoint - player.global_position
		var distance := to_target.length()
		var delta: float = world.get_physics_process_delta_time()
		if distance <= maxf(1.0, player.SPEED * delta):
			waypoints.remove_at(0)
			best = INF
			continue
		if distance < best - 0.5:
			best = distance
			since_progress = 0.0
		else:
			since_progress += delta
			if since_progress >= stuck_seconds:
				player.collision_mask = 0
		player.scripted_input = to_target / distance
		await nextFrame()
	player.scripted_input = Vector2.ZERO
	player.collision_mask = mask
	player.global_position = target
	if face != "":
		player.facing = face
	player.play_idle()

# Wait until none of these NPCs is still on a go_to() walk.
#   laman.go_to(Vector2(-11, 7)).then_face("up")
#   lemuel.go_to(Vector2(-11.5, 6)).then_face(laman)
#   await waitForArrivals([laman, lemuel])
func waitForArrivals(people: Array) -> void:
	while people.any(func(who): return is_instance_valid(who) and who.is_walking() and who.is_held()):
		await nextFrame()

# Turn who toward target along the stronger axis. An NPC is held facing
# that way, habit paused, until who.release(). The player is not held:
# movement input clears facing, and so does enablePlayerControls.
func faceToward(who: Node2D, target: Node2D) -> void:
	var facing := Npc.facing_for(target.global_position - who.global_position)
	if who is Npc:
		(who as Npc).hold(facing)
	else:
		who.set("facing", facing)

# Stop an NPC's habit so the script can move or pose them. Anything else
# (the player) is left alone.
func _hold(who: Node2D) -> void:
	if who is Npc:
		(who as Npc).hold()

func faceEachOther(a: Node2D, b: Node2D) -> void:
	faceToward(a, b)
	faceToward(b, a)

func switchToGameMode():
	world.get_node("UI").visible = false

# Turn on one trigger that was saved with starts_armed = false.
# Use this when a beat begins after the chapter is already active.
func arm_trigger(trigger_name: String) -> void:
	var chapters := _chapters()
	if chapters:
		chapters.arm(content_id(), trigger_name)
		# Prayers point at it for as long as it waits to be walked into.
		var trigger := get_trigger(trigger_name)
		if trigger:
			var middle := _prayer().center_of(trigger)
			setGuidance(func() -> Variant: return middle if trigger.is_waiting() else null)

# Reveal one prop that was saved hidden: under this chapter's Set, or under
# Chapters/Props (which also reveals the PropGroup around it, for a group
# with starts_hidden).
func show_prop(prop_name: String) -> void:
	var chapters := _chapters()
	if chapters:
		chapters.show_prop(content_id(), prop_name)

# Hide one prop for the rest of this chapter only. The next chapter's setup
# shows it again if its PropGroup is in that chapter. useUpProps() hides it
# for good.
func hide_prop(prop_name: String) -> void:
	_hide_prop(prop_name)

# A node by name, at any depth, under this chapter's Set or else under
# Chapters/Props, where props that outlast one chapter live.
#   var crate: FruitCrate = getProp("Crate1")
func getProp(prop_name: String) -> Node:
	var chapters := _chapters()
	if chapters == null:
		return null
	return chapters.get_prop(content_id(), prop_name)

# Story facts that later chapters, props and the save file need, such as a
# choice the player made. Values must be plain data. Saved when this chapter
# completes, together with the chapter itself.
#   setFlag("met_zoram", true)
#   if getFlag("met_zoram", false): ...

# Props (by name, as getProp() finds them) used up in the story, such as the
# ore on the table once it went into tools. Hidden, with their collision off,
# now and at the start of every later chapter.
const USED_UP_FLAG := "used_up_props"

#   useUpProps(["OreOnTable"])
func useUpProps(prop_names: Array) -> void:
	var used: Array = getFlag(USED_UP_FLAG, []).duplicate()
	for prop_name in prop_names:
		if not used.has(prop_name):
			used.append(prop_name)
		_hide_prop(prop_name)
	setFlag(USED_UP_FLAG, used)

# Bring back props useUpProps() took away, such as the ore on the table once
# Nephi brings more. Shown now and at the start of every later chapter.
#   restoreProps(["OreOnTable"])
func restoreProps(prop_names: Array) -> void:
	var used: Array = getFlag(USED_UP_FLAG, []).duplicate()
	for prop_name in prop_names:
		used.erase(prop_name)
		show_prop(prop_name)
	setFlag(USED_UP_FLAG, used)

func isUsedUp(prop_name: String) -> bool:
	return getFlag(USED_UP_FLAG, []).has(prop_name)

func _hide_prop(prop_name: String) -> void:
	var prop := getProp(prop_name)
	if prop is CanvasItem:
		(prop as CanvasItem).visible = false
	if prop:
		ChapterContent.set_interaction(prop, false)

# An activity (ui/activity_scroll.gd) done earlier can be done again: doActivity()
# opens it instead of returning at once.
func resetActivity(activity_id: String) -> void:
	setFlag(ActivityScroll.flag(activity_id), false)

func setFlag(key: String, value: Variant) -> void:
	StoryState.set_flag(key, value)

func getFlag(key: String, default: Variant = null) -> Variant:
	return StoryState.get_flag(key, default)

func getPlayer() -> Node2D:
	return world.get_node("Player")

# A spawned character by the name used in a characters list ("lehi",
# "sister_1") or by node name ("Lehi", "Sister1"). Repeats are numbered in
# spawn order: "chicken" is the first chicken, "chicken2" the second.
# A character spawned with an "id" is found by that id instead.
func getCharacter(character_name: String) -> Node2D:
	var character := world.get_node_or_null("Cutscene/" + character_name.to_pascal_case()) as Node2D
	if character == null:
		push_error("No spawned character named '%s'" % character_name)
	return character

func get_trigger(trigger_name: String) -> StoryTrigger:
	var chapters := _chapters()
	if chapters == null:
		return null
	return chapters.get_trigger(content_id(), trigger_name)

# Show one balloon and wait until the player advances past the last line.
# A leftover dialogue_ended connection would stack the next time a chapter talks.
# Nephi is posed idle for the whole balloon. A walk cycle would otherwise keep
# playing in place, because facing holds him still without leaving WalkState.
# NPC habits pause for the balloon too, so nobody wanders off mid-conversation
# (animals keep grazing). Scripted go_to walks keep going.
# extra_game_states are passed to Dialogue Manager, so a dictionary such as
# {"fruit": "bananas"} fills {{fruit}} in the dialogue line.
# One Nephi started himself by talking to someone runs to its end first.
# With fade_out seconds, the balloon fades out after the last line and the
# await returns once it is gone.
func show_dialogue(title: String, extra_game_states: Array = [], fade_out: float = 0.0) -> void:
	var small_talk := world.get_node_or_null("SmallTalk") as SmallTalk
	if small_talk:
		await small_talk.wait_until_done()
	var player = world.get_node("Player")
	player.play_idle()
	world.get_tree().call_group("npcs", "pause_for_dialogue", true)
	var resource = load("res://story/main.dialogue")
	var balloon = DialogueManager.show_dialogue_balloon(resource, title, extra_game_states)
	balloon.fade_out_seconds = fade_out
	await world.dialogue_ended
	if fade_out > 0.0 and is_instance_valid(balloon):
		await balloon.tree_exited
	world.get_tree().call_group("npcs", "pause_for_dialogue", false)

# Scene1, Scene2, ... are Node2D children of this chapter's Set. Hiding a scene
# in the editor does not turn off its tile collision. These do both: the scene
# is hidden, and every tilemap and body under it stops interacting.
func enableScene(scene_number: int) -> void:
	_set_scene_enabled(scene_number, true)

func disableScene(scene_number: int) -> void:
	_set_scene_enabled(scene_number, false)

func _set_scene_enabled(scene_number: int, enabled: bool) -> void:
	var chapters := _chapters()
	if chapters:
		chapters.set_scene_enabled(content_id(), scene_number, enabled)

# Fade to black and stay there, with the HUD hidden. The next chapter switches
# cameras while this is still covered.
func fade_out_and_hold() -> void:
	await screenFade().fade_out()
	world.get_node("UI").visible = false

# The same fade. Kept for scenes shot through the cutscene camera, from when
# each camera had its own overlay.
func fadeOutCutsceneAndHold() -> void:
	await fade_out_and_hold()

# The screen-space fade world.gd adds. See ui/screen_fade.gd.
func screenFade() -> ScreenFade:
	return world.get_node("ScreenFade") as ScreenFade

func _chapters() -> Chapters:
	var chapters := world.get_node_or_null("Chapters") as Chapters
	if chapters == null:
		push_error("World is missing a Chapters node (res://story/chapters.tscn)")
	return chapters

# Stop movement and the use action. Call enablePlayerControls before the player
# should walk again. end() also unlocks, so a chapter that returns early cannot
# leave Nephi stuck. Cutscenes that should allow walking simply skip this.
func disablePlayerControls() -> void:
	_setPlayerControls(false)

func enablePlayerControls() -> void:
	_setPlayerControls(true)

# Hide the joystick, buttons, backpack and quest (the UI layer) for a long
# locked beat, such as a scripture or a prayer, so the player does not try to
# walk off. The pause button is on its own layer and stays. Controls are left
# alone, so lock them too. Call showHud() before handing control back;
# endCutscene() and beginSegment() after a fade also bring it back.
func hideHud() -> void:
	world.get_node("UI").visible = false

func showHud() -> void:
	world.get_node("UI").visible = true

# Where a prayer for guidance points (player/prayer.gd). The wait helpers
# (waitForPlayerNear, waitForPlayerAt, waitForItemAdded, arm_trigger) set this
# while they wait, so most quests need nothing more. For a goal they do not
# cover, name it here and clear it with the returned token once it is reached.
# target is a Node2D, a tile (Vector2), an Array of Node2D (the nearest one
# still shown), a Rect2 in pixels (its center), or a Callable returning a
# pixel position or null. The newest goal that has a position wins.
#   var goal := setGuidance([getCharacter("sister_1"), getCharacter("sister_2")])
#   ...
#   clearGuidance(goal)
func setGuidance(target: Variant) -> int:
	if target is Vector2:
		target = target * 32.0
	return _prayer().guide(target)

# Clear one goal from setGuidance(), or with no token every goal.
func clearGuidance(token: int = -1) -> void:
	var prayer := _prayer()
	if prayer == null:
		return
	if token < 0:
		prayer.clear_guidance()
	else:
		prayer.unguide(token)

# Nephi folds his hands to pray and holds it, for a story beat such as a
# vision on the mountain. Controls are left alone, so lock them first. Await
# it to wait until his hands are together. stopPraying() lets go.
#   disablePlayerControls()
#   await startPraying()
#   ...
#   stopPraying()
func startPraying() -> void:
	await _prayer().fold_hands()

func stopPraying() -> void:
	_prayer().unfold_hands()

func _prayer() -> Prayer:
	var player = world.get_node_or_null("Player")
	return player.prayer if player else null

func _setPlayerControls(enabled: bool) -> void:
	var player = world.get_node("Player")
	player.controls_enabled = enabled
	if enabled:
		# A cutscene pose should not outlive the cutscene.
		player.facing = ""
	else:
		# Locking controls used to zero velocity but leave WalkState running.
		player.play_idle()

# Papyrus scroll over the game (ui/scripture_scroll.tscn). text is a key in
# Scriptures.TEXT (story/scriptures.gd) or the words themselves, and shrinks to
# fit. With a duration, await returns after the scroll has faded away again.
# Without one, await returns once the text is showing; call hideScroll later.
# Controls are left alone, so lock them first if the player should stop.
# A verse given by key is read aloud from the narrator's clip for it
# (Language.voice_path: res://voice/narrator/<key>.mp3 in English) when
# that clip exists. The scroll waits for the reading to end before it changes
# words or closes, so a duration or delay shorter than the clip just runs long.
# A picture (a Texture2D, or a Control that draws itself) puts the text at the
# top and fades the picture in below it image_delay seconds after the text
# shows. hideScroll fades it out before the scroll. waitForScrollImage() returns once it is in.
#   await showScroll("1_nephi_17_8", ScriptureScroll.Placement.RIGHT, 6)
#   await showScroll("1_nephi_18_23", ScriptureScroll.Placement.FULL, 0, preload("res://story/pictures/landing.png"))
func showScroll(text: String, placement: ScriptureScroll.Placement = ScriptureScroll.Placement.RIGHT, duration: float = 0.0, picture: Variant = null, image_delay: float = 1.0) -> void:
	await _scroll().show_scroll(text, placement, duration, picture, image_delay)

func waitForScrollImage() -> void:
	await _scroll().image_revealed

# Returns once the verse on the scroll has been read aloud, or at once if it
# has no clip, so a scene can follow the narration instead of a fixed delay.
#   await showScroll("1_nephi_17_9")
#   await waitForScrollVoice()
func waitForScrollVoice() -> void:
	await _scroll().wait_for_voice()

# Fade the current words (and any picture) out and these in, keeping the paper
# where it is. A new picture fades in below them as in showScroll.
#   await updateScroll("1_nephi_17_9")
#   await updateScroll("1_nephi_17_10", preload("res://story/pictures/vision.png"))
func updateScroll(text: String, picture: Variant = null, image_delay: float = 1.0) -> void:
	await _scroll().update_scroll(text, picture, image_delay)

func hideScroll() -> void:
	await _scroll().hide_scroll()

# How long the player camera slides in frameBesideScroll and recenterCamera.
const FRAME_SLIDE_SECONDS := 0.6

# Slide the player camera so the middle of who (Nephi and whoever is in the
# shot) sits in the middle of the screen a scroll at placement leaves open.
# Await returns once it has slid; recenterCamera() slides it back.
#   frameBesideScroll([getPlayer(), laman, lemuel], ScriptureScroll.Placement.RIGHT)
#   await showScroll("1_nephi_17_45")
func frameBesideScroll(who: Array, placement: ScriptureScroll.Placement = ScriptureScroll.Placement.RIGHT) -> void:
	var middle := Vector2.ZERO
	for node in who:
		middle += (node as Node2D).global_position
	middle /= who.size()
	var screen: Vector2 = world.get_viewport_rect().size
	var paper := ScriptureScroll.paper_rect(placement, screen)
	# The open part is beside a side scroll, above the bottom one.
	var open := Rect2(Vector2.ZERO, screen)
	match placement:
		ScriptureScroll.Placement.RIGHT:
			open.size.x = paper.position.x
		ScriptureScroll.Placement.LEFT:
			open = Rect2(paper.end.x, 0, screen.x - paper.end.x, screen.y)
		ScriptureScroll.Placement.BOTTOM:
			open.size.y = paper.position.y
	var view_middle := middle - (open.get_center() - screen / 2)
	await _slide_camera(view_middle - getPlayer().global_position)

func recenterCamera() -> void:
	await _slide_camera(Vector2.ZERO)

func _slide_camera(offset: Vector2) -> void:
	var camera := world.get_node("Player/Camera") as Camera2D
	var tween: Tween = world.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "offset", offset, FRAME_SLIDE_SECONDS)
	await tween.finished

# A picture alone on the scroll, filling the paper, with no words. Await
# returns once the paper is showing; the picture fades in after it. Hide it
# with hideScroll().
#   await showPicture(preload("res://story/pictures/promised_land.jpeg"))
#   await waitForScrollImage()
func showPicture(picture: Variant, placement: ScriptureScroll.Placement = ScriptureScroll.Placement.FULL) -> void:
	var scroll := _scroll()
	var share := scroll.image_share
	# The paper is laid out before the first fade, so the picture keeps the
	# whole page once the share is put back.
	scroll.image_share = 1.0
	await scroll.show_scroll("", placement, 0.0, picture, 0.0)
	scroll.image_share = share

# Words alone in the middle of the screen, over everything but dialogue,
# such as "Many days later..." on the black screen between two segments.
# text is a key in Captions.TEXT (story/captions.gd) or the words themselves.
# Fades in, stays for seconds, and fades out before the await returns. A key
# is read aloud from res://voice/narrator/<key>.mp3 when that clip exists, and
# the words stay until the reading ends if it runs longer than seconds.
# voiced false shows them silently, clip or not.
#   await showCaption("many_days_later")
func showCaption(text: String, seconds: float = 2.5, voiced: bool = true) -> void:
	var layer := CanvasLayer.new()
	# Over the scripture scroll (50), under dialogue balloons (100).
	layer.layer = 90
	var label := Label.new()
	label.text = Captions.lookup(text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Long lines wrap inside these side margins.
	label.anchor_left = CAPTION_SIDE_MARGIN
	label.anchor_right = 1.0 - CAPTION_SIDE_MARGIN
	label.add_theme_font_override("font", CAPTION_FONT)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.96, 0.91, 0.8))
	label.modulate.a = 0.0
	layer.add_child(label)
	world.add_child(layer)
	var voice := _caption_voice(text) if voiced else null
	if voice:
		layer.add_child(voice)
	var tween: Tween = world.create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 1.0)
	await tween.finished
	if voice:
		voice.play()
	await world.get_tree().create_timer(seconds, false).timeout
	if voice and voice.playing:
		await voice.finished
	tween = world.create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	await tween.finished
	layer.queue_free()

func _caption_voice(key: String) -> AudioStreamPlayer:
	if not Captions.TEXT.has(key) or not Language.has_voice("narrator", key):
		return null
	var voice := AudioStreamPlayer.new()
	voice.bus = GameSettings.VOICE
	voice.add_to_group(GameSettings.VOICE_PLAYERS)
	voice.stream = Language.voice("narrator", key)
	return voice

const CAPTION_FONT := preload("res://ui/fonts/OverlockItalic.ttf")
const CAPTION_SIDE_MARGIN := 0.12

func _scroll() -> ScriptureScroll:
	return world.get_node("ScriptureScroll") as ScriptureScroll

# Time of day (world/lighting/day_night.gd). The UI, scroll and balloons stay
# lit because they are CanvasLayers. FlickerLights, such as a
# world/lighting/campfire_light.tscn placed in this chapter's Set, fade up as
# it darkens, and the crickets come out. Time outlasts the chapter. Pass 0
# seconds to switch at once behind a black screen.
#   await nightfall()
#   await setTimeOfDay(DayNight.DUSK, 4.0)
#   startDayCycle(10.0)      # a whole day every ten minutes, until stopDayCycle()
func nightfall(seconds: float = 3.0) -> void:
	await world.day_night.go_to_hour(DayNight.NIGHT, seconds)

func daybreak(seconds: float = 3.0) -> void:
	await world.day_night.go_to_hour(DayNight.MORNING, seconds)

func setTimeOfDay(hour: float, seconds: float = 3.0) -> void:
	await world.day_night.go_to_hour(hour, seconds)

func startDayCycle(minutes_per_day: float) -> void:
	world.day_night.start_cycle(minutes_per_day)

func stopDayCycle() -> void:
	world.day_night.stop_cycle()

# Which items the player may pick up, by InventoryItem name. Once one is
# in the pack, only that same item can be added until emptyBackpack().
# Call with no names to allow nothing. Clears any setPickupLimit().
#   setPickupList("Apple", "Banana")
func setPickupList(...item_names: Array) -> void:
	var player = world.get_node("Player")
	player.pickup_list.assign(item_names)
	player.pickup_limit = 0

# The most the pack takes until the next setPickupList(), for a quest that
# wants fewer than a full pack. Without it, the pack fills.
#   setPickupList("Log")
#   setPickupLimit(3)
func setPickupLimit(count: int) -> void:
	world.get_node("Player").pickup_limit = count

func emptyBackpack() -> void:
	world.get_node("Player").empty_inventory()

# Wait until the player puts an item in the backpack, and return it. With a
# name, keep waiting until that item is picked up and ignore the others.
#   var item = await waitForItemAdded()
#   await waitForItemAdded("Banana")
func waitForItemAdded(item_name: String = "") -> InventoryItem:
	var guidance := setGuidance(func() -> Variant: return _prayer().nearest_pickup(item_name))
	while true:
		var item: InventoryItem = await world.item_added
		if item_name == "" or item.name == item_name:
			clearGuidance(guidance)
			return item
	return null

# Wait until Nephi is within `tiles` tiles (32px each) of target, measured
# center to center. Checked every physics frame, so it follows a walking NPC
# and needs no Area2D in the chapter's Set. With a quest_id, that id is also
# sent on SignalBus.quest_completed, the same as a StoryTrigger would.
#   await waitForPlayerNear(lehi)
#   await waitForPlayerNear(lehi, 1.5, "return_fruit")
func waitForPlayerNear(target: Node2D, tiles: float = 1.0, quest_id: String = "") -> void:
	var player := world.get_node("Player") as Node2D
	var reach := tiles * 32.0
	var guidance := setGuidance(target)
	while is_instance_valid(target) and player.global_position.distance_to(target.global_position) > reach:
		await nextFrame()
	clearGuidance(guidance)
	if not quest_id.is_empty():
		SignalBus.quest_completed.emit(quest_id)

# Wait until Nephi is within `tiles` tiles of a spot, given in tiles, such as
# just in front of a prop that is drawn as tiles and has no node to follow.
#   await waitForPlayerAt(Vector2(4.5, 5.5))
func waitForPlayerAt(tile: Vector2, tiles: float = 1.0) -> void:
	var player := world.get_node("Player") as Node2D
	var spot := tile * 32.0
	var reach := tiles * 32.0
	var guidance := setGuidance(tile)
	while player.global_position.distance_to(spot) > reach:
		await nextFrame()
	clearGuidance(guidance)

# Open a hands-on activity on the scroll (ui/activity_scroll.gd) and wait until it is
# done (or left) and the camera has slid back. Returns at once if it was already done,
# so a segment loaded afterward moves on. facing turns Nephi first ("" leaves
# him as he is). Talk before and after it, not during.
#   await show_dialogue("plant_seeds")
#   await doActivity("plant")
#   await show_dialogue("seeds_planted")
# A board with a close X can also be left partway; then this
# returns with isActivityDone() still false. start_step opens it again at
# the step it reached. focus, a world position in pixels, is kept in view
# beside Nephi while the scroll is open (ActivityScroll.open_activity()),
# such as where the activity's work shows up in the world.
func doActivity(activity_id: String, facing: String = "", start_step: int = 0, focus: Vector2 = Vector2.INF) -> void:
	if isActivityDone(activity_id):
		return
	var scroll := world.get_node_or_null("ActivityScroll") as ActivityScroll
	if scroll == null or not scroll.open_activity(activity_id, facing, start_step, focus):
		return
	await scroll.closed
	await delay(scroll.slide_seconds)

func isActivityDone(activity_id: String) -> bool:
	return ActivityScroll.is_done(activity_id)

func matchCutsceneCameraToPlayerCamera():
	world.get_node("Cutscene/Camera").position.x = world.get_node("Player").position.x
	world.get_node("Cutscene/Camera").position.y = world.get_node("Player").position.y
	world.get_node("Cutscene/Camera").enabled = true
	screenFade().fade_in()
	world.get_node("Cutscene/Camera").make_current()
	
# cameraPosition is in tiles. Both cutscene functions take (fadeOut, fadeIn),
# the order the fades happen in.
func startCutsceneAt(cameraPosition, fadeOut=true, fadeIn=true):
	if(fadeOut):
		await screenFade().fade_out()
	world.get_node("UI").visible = false
	world.get_node("Cutscene/Camera").position.x = cameraPosition.x * 32
	world.get_node("Cutscene/Camera").position.y = cameraPosition.y * 32
	world.get_node("Cutscene/Camera").enabled = true
	world.get_node("Cutscene/Camera").make_current()
	if(fadeIn):
		screenFade().fade_in()
	
func endCutscene(fadeOut=true, fadeIn=true):
	if(fadeOut):
		await screenFade().fade_out()

	world.get_node("UI").visible = true
	world.get_node("Cutscene/Camera").enabled = false
	world.get_node("Player").facing = ""
	world.get_node("Player/Camera").make_current()
	
	if(fadeIn):
		screenFade().fade_in()

# A Timer under the world, not a SceneTree timer, so it is freed with the
# world and a chapter waiting on it never wakes after Main Menu.
func delay(seconds):
	var timer := Timer.new()
	timer.one_shot = true
	# Timer.start() refuses 0, which a SceneTree timer allowed.
	timer.wait_time = maxf(seconds, 0.001)
	timer.autostart = true
	timer.timeout.connect(timer.queue_free)
	world.add_child(timer)
	return timer.timeout

# One physics frame. Ends with the world, unlike the SceneTree's physics_frame.
#   while not done:
#       await nextFrame()
func nextFrame() -> Signal:
	return world.physics_tick
	
func end():
	print("Closing Chapter " + id)
	# Only this chapter's transient actors. Persistent spawns stay parented to
	# Cutscene for later chapters. Do not wipe every Cutscene child.
	for character in spawnedCharacters:
		if not is_instance_valid(character):
			continue
		if character.get_meta("transient", true):
			print("freeing " + str(character))
			# Leave the tree now, not at end of frame, so the next chapter's
			# spawns can reuse names like Chicken2.
			character.get_parent().remove_child(character)
			character.queue_free()
	spawnedCharacters.clear()

	# Hide this chapter's props and disarm its areas. The nodes stay in the
	# scene so the next run of the game still has the layouts you placed.
	var chapters := _chapters()
	if chapters:
		chapters.deactivate_chapter(content_id())

	# Safety net. play() should already re-enable before a quest the player walks.
	enablePlayerControls()
	clearGuidance()

	print("waiting for free")
	await nextFrame()
	print("free!")
