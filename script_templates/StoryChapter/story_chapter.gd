# meta-name: Story Chapter (own Set)
# meta-description: A chapter with its own ChapterContent under Chapters. Fill in _init(), setup() and play().
# meta-default: true
extends StoryChapter

# CHECKLIST
#   1. Save it under story/chapters/ and add it to Story.CHAPTER_SCRIPTS in
#      play order.
#   2. In world/world.tscn, add a Node2D under Chapters with
#      story/chapter_content.gd, name it, and set chapter_id to this id. Props go under its Set, goal areas under
#      Triggers (StoryTrigger; starts_armed off for a later beat).
#   3. setup() must build the whole starting world from nothing. A load, or a
#      debug start, runs it on a fresh world with nobody spawned.
#   4. Props that outlast this chapter go under Chapters/Props in a PropGroup
#      (appears_in / starts_hidden / gone_after), not in this Set.
#
# What happens in this chapter.

# Only when ends_on is a quest id. Emit it (fade out first) to end the chapter.
const QUEST_DONE := "CHANGE_ME_done"

func _init() -> void:
	# Stable id. Saves and starts_after use it, so do not rename it later.
	id = "CHANGE_ME"
	title = "CHANGE ME"
	starts_after = "PREVIOUS_CHAPTER_ID"
	# END_ON_CUTSCENE: the chapter ends, and the game saves, when play() returns.
	# QUEST_DONE: play() can return early; the chapter ends when that id is
	#   sent on SignalBus.quest_completed (a StoryTrigger quest_id, or
	#   waitForPlayerNear(..., QUEST_DONE)).
	# END_ON_HOLD: never completes. Only for the last beat written so far.
	ends_on = END_ON_CUTSCENE
	# Set when sharing another chapter's ChapterContent instead of having one.
	# set_id = "village"

# Tiles, as in spawnCharacters. A list, so the editor preview can show them.
var characters = [
	{"name": "lehi", "start": Vector2(0, 0), "facing": "down"},
	# {"name": "sam", "start": Vector2(1, 0), "habit": Meander.new(1)},
	# {"name": "chicken", "id": "tent_hen", "start": Vector2(2, 0)},
]

# Type this id into Chapters' editor_preview_chapter to see these in the editor.
func preview_spawns() -> Array[Dictionary]:
	return previewCharacters(characters)

# Runs on a black screen when the previous chapter faded out. Build the world here:
# place Nephi, spawn people, set the time of day, enable the right SceneN.
func setup(w):
	super(w) # shows this chapter's Set, arms starts_armed triggers, applies PropGroups
	disablePlayerControls()
	var player = getPlayer()
	player.position = Vector2(0, 0) * 32
	player.facing = "down"
	(world.get_node("Player/Camera") as Camera2D).reset_smoothing()
	# transient (default true): end() frees them. Pass false for people a later
	# chapter keeps; then that later chapter must handle them already existing.
	await spawnCharacters(characters)

func play():
	# Fade in from the black the previous chapter left.
	await startCutsceneAt(getPlayer().position / 32.0, false, true)
	if screenFade().is_fading():
		await screenFade().settled
	world.setQuest("")
	await endCutscene(false, false)
	var lehi = getCharacter("lehi")

	disablePlayerControls()
	await show_dialogue("someDialogueTitle")
	enablePlayerControls()

	world.setQuest("Do the thing")
	var goal := get_trigger("SomeGoal")
	arm_trigger("SomeGoal") # only if it was saved with starts_armed off
	await goal.fired

	# Hand off on black so the next chapter's setup() is unseen.
	await fade_out_and_hold()

# end() runs after completion: frees transient spawns, hides this Set, unlocks
# controls. Override only to keep something.
