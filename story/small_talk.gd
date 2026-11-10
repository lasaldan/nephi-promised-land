extends Node

class_name SmallTalk

# Nephi talking to someone, looking closely at an artifact, or saying
# something to himself. The use button finds who or what is in reach
# (Interaction); this node runs the balloon. The world adds it as "SmallTalk".
#
# Each person's lines are the talk_<name> title in story/main.dialogue, where
# <name> is their folder under characters/ (talk_lehi, talk_sheep). Anyone
# without a title is never offered. An artifact's lines are its artifact_<id>
# title (story/artifacts.gd).

const DIALOGUE := preload("res://story/main.dialogue")
const TITLE_PREFIX := "talk_"
const GROUP := &"small_talk"
# The press that closes a balloon is also a use press (space is both), so a
# new talk waits this long after any balloon closes.
const REOPEN_DELAY_MSEC := 300

signal finished

var talking := false
var _balloons_open := 0
var _closed_at_msec := -REOPEN_DELAY_MSEC

func _ready() -> void:
	add_to_group(GROUP)
	# Story balloons count too, so a talk never opens over one.
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)

static func find(tree: SceneTree) -> SmallTalk:
	return tree.get_first_node_in_group(GROUP) as SmallTalk

static func has_title(title: String) -> bool:
	return DIALOGUE.titles.has(title)

static func title_for(npc: Npc) -> String:
	return TITLE_PREFIX + Cast.name_of(npc)

# True when nothing would be cut into by a talk (see free_to_remark()).
static func free_to_talk(tree: SceneTree) -> bool:
	var small_talk := find(tree)
	return small_talk != null and small_talk.free_to_remark()

# Their lines, with Nephi and them turned to each other and everyone's habits
# paused. Someone the chapter is holding in a pose goes back to it afterwards.
func talk_to(npc: Npc) -> void:
	var player = _player()
	var was_held := npc.is_held()
	var was_facing := npc.facing
	var was_working := npc.working
	# Someone sitting stays as they sit, rather than turning in their seat.
	if not npc.is_posed():
		npc.face_toward(player)
	StoryState.record("talked_to", Cast.name_of(npc))
	await _converse(title_for(npc), npc)
	if is_instance_valid(npc) and was_held and npc.is_held():
		npc.facing = was_facing
		npc.working = was_working

# Nephi turns to the artifact and tells about it.
func inspect(artifact: Artifact) -> void:
	StoryState.record("inspected", artifact.artifact_id)
	await _converse(Artifacts.title_for(artifact.artifact_id), artifact)

# Nephi says something to himself, with no one to turn to, such as on
# finding a place (world/zones/place.gd). Check free_to_remark() first.
func remark(title: String) -> void:
	await _converse(title, null)

func _converse(title: String, turn_to: Node2D) -> void:
	var player = _player()
	talking = true
	player.talking = true
	player.play_idle()
	if turn_to:
		player.facing = Npc.facing_for(turn_to.global_position - player.global_position)
	get_tree().call_group("npcs", "pause_for_dialogue", true)
	DialogueManager.show_dialogue_balloon(DIALOGUE, title, [_stages(), self])
	await get_parent().dialogue_ended
	get_tree().call_group("npcs", "pause_for_dialogue", false)
	player.talking = false
	talking = false
	finished.emit()

# StoryChapter.show_dialogue waits here, so a story balloon never opens over
# a talk.
func wait_until_done() -> void:
	while talking:
		await finished

# Every talker with a talk_ title, people and animals.
static func everyone() -> Array[String]:
	var names: Array[String] = []
	for title in DIALOGUE.titles:
		if title.begins_with(TITLE_PREFIX):
			names.append(title.trim_prefix(TITLE_PREFIX))
	return names

# For a one-off condition in a talk_ title.
#   if after("arrival")
func after(chapter_id: String) -> bool:
	return StoryState.completed_chapter_ids.has(chapter_id)

# Where the story is, by name, for the talk_ titles to branch on. Each is
# true once its chapter is finished. Add one here when the lines need a new
# point in the story:
#   "planted_seeds": after("first_planting"),
# and in main.dialogue:
#   if planted_seeds
#       lehi: The seeds are in the ground. Now we wait.
func _stages() -> Dictionary:
	return {}

# Nothing on screen and Nephi free to walk, so a talk or remark would not cut
# into a story balloon, a cutscene or a prayer.
func free_to_remark() -> bool:
	if talking or _balloons_open > 0:
		return false
	if Time.get_ticks_msec() - _closed_at_msec < REOPEN_DELAY_MSEC:
		return false
	var world := get_parent()
	if not (world.get_node("UI") as CanvasLayer).visible:
		return false
	var player = _player()
	return player.controls_enabled and not player.menu_open and not player.prayer.praying

func _player() -> Node2D:
	return get_parent().get_node("Player")

func _on_dialogue_started(_resource: DialogueResource) -> void:
	_balloons_open += 1

func _on_dialogue_ended(_resource: DialogueResource) -> void:
	_balloons_open = maxi(0, _balloons_open - 1)
	_closed_at_msec = Time.get_ticks_msec()
