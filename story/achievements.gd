class_name Achievements

# Every achievement, in the order the menu lists them. Each is earned per save
# slot (StoryState.unlock_achievement) and saved with that slot. Ids are what
# a save file stores, so do not rename one; a platform backend (Game Center,
# Play Games) would use the same ids.
#
# Each entry has a name, a description, and at most one rule for when it is
# earned on its own. With no rule, code earns it by id:
#   StoryState.unlock_achievement("first_harvest")
#
# Rules:
#   "chapter": id                   that chapter completes
#   "activity": id                  that activity board is finished (ActivityScroll)
#   "count": name, "at": n          StoryState.count(name) reaches n
#                                   ("prayers" is counted by every prayer)
#   "all_of": record, "ids": [...]  every id is in StoryState.record(record, ...)
#                                   ("talked_to" and "inspected" are recorded
#                                   by SmallTalk). "ids": TALKERS means everyone
#                                   with a talk_ title in main.dialogue.
#   "place": id                     Nephi stands in the Place zone with that id
#                                   (world/zones/place.gd)
#   "reach_out": group, "reach": px a use press with a node of that group within
#                                   reach of Nephi's feet
#
# The ones here are not tied to any story, so they carry over from game to
# game. Delete any the new game does not want.
const LIST := {
	"pray_oft": {"name": "Pray Oft", "description": "Pray ten times.", "count": "prayers", "at": 10},
	"dolittle": {"name": "Dolittle", "description": "Talk with a sheep, a chicken, and a goat.",
			"all_of": "talked_to", "ids": ["sheep", "chicken", "goat"]},
	"small_talk": {"name": "Small Talk", "description": "Talk with everyone.", "all_of": "talked_to", "ids": TALKERS},
	"lepidopterist": {"name": "Lepidopterist", "description": "Reach out to a butterfly.",
			"reach_out": "butterflies", "reach": 24.0},
	"snuggle_bunny": {"name": "Snuggle Bunny", "description": "Reach out to a wild bunny.",
			"reach_out": "bunnies", "reach": 28.0},
}

const TALKERS := "talkers"

# In the current language. Names and descriptions are translated under the
# context "achievement" (translations/es.po).
static func display_name(id: String) -> String:
	return Language.t(LIST.get(id, {}).get("name", id), "achievement")

static func description(id: String) -> String:
	return Language.t(LIST.get(id, {}).get("description", ""), "achievement")

# Ids whose rule is key = value, such as every "chapter" rule for one chapter.
static func with_rule(key: String, value: Variant) -> Array[String]:
	var ids: Array[String] = []
	for id in LIST:
		if LIST[id].get(key) == value:
			ids.append(id)
	return ids

# Earn whatever a count or a record now satisfies. StoryState calls these as
# the numbers change.
static func check_count(counter: String, value: int) -> void:
	for id in with_rule("count", counter):
		if value >= LIST[id].get("at", 1):
			StoryState.unlock_achievement(id)

static func check_record(record: String, ids_seen: Array) -> void:
	for id in with_rule("all_of", record):
		var needed: Variant = LIST[id].get("ids", [])
		if needed is String and needed == TALKERS:
			needed = SmallTalk.everyone()
		if not (needed as Array).is_empty() and (needed as Array).all(func(x): return ids_seen.has(x)):
			StoryState.unlock_achievement(id)

# A use press at Nephi's feet (Player.use()).
static func check_reach_out(tree: SceneTree, at: Vector2) -> void:
	for id in LIST:
		var group: String = LIST[id].get("reach_out", "")
		if group.is_empty() or StoryState.has_achievement(id):
			continue
		for node in tree.get_nodes_in_group(group):
			if (node as Node2D).global_position.distance_to(at) <= LIST[id].get("reach", 24.0):
				StoryState.unlock_achievement(id)
				break
