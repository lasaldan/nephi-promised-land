class_name Cast

# Where everyone's scene lives, by name: people under characters/cast/<name>/,
# animals under characters/animals/<name>/. The name is the folder, which is
# also the speaker in story/main.dialogue, the folder of their voice clips
# (voice/<name>/), and their entry in tools/voice/cast.json.
#   Cast.scene("sam")        res://characters/cast/sam/sam.tscn
#   Cast.scene("sheep")      res://characters/animals/sheep/sheep.tscn

const FOLDERS: Array[String] = ["res://characters/cast", "res://characters/animals"]

# The scene for a name, or null with an error when there is none. A trailing
# number is a second of a kind ("sheep2" is a sheep).
static func scene(character_name: String) -> PackedScene:
	var path := scene_path(character_name)
	if path.is_empty():
		push_error("No character scene named '%s' under %s" % [character_name, FOLDERS])
		return null
	return load(path)

static func scene_path(character_name: String) -> String:
	for name in [character_name, character_name.rstrip("0123456789")]:
		for folder in FOLDERS:
			var path := "%s/%s/%s.tscn" % [folder, name, name]
			if ResourceLoader.exists(path):
				return path
	return ""

# Names shown over a speaker's lines, for names that would not read well
# capitalized ("Ishmael Daughter 1"). Everyone else is shown capitalized
# ("lehi" is "Lehi"). Translated under the context "dialogue".
const DISPLAY_NAMES := {
	"sister_1": "Nephi's Sister",
	"sister_2": "Nephi's Sister",
	"ishmael_wife": "Ishmael's Wife",
	"ishmael_daughter_1": "Ishmael's Eldest Daughter",
	"ishmael_daughter_2": "Ishmael's Daughter",
	"ishmael_daughter_3": "Ishmael's Daughter",
	"ishmael_daughter_4": "Ishmael's Daughter",
	"ishmael_daughter_5": "Ishmael's Daughter",
	"ishmael_son_1": "Ishmael's Son",
	"ishmael_son_2": "Ishmael's Son",
}

static func display_name(character_name: String) -> String:
	return DISPLAY_NAMES.get(character_name, character_name.capitalize())

# A spawned character's name: the folder its scene is in. "sheep" for every sheep.
static func name_of(node: Node) -> String:
	return node.scene_file_path.get_file().get_basename()
