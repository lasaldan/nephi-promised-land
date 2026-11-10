class_name Artifacts

# The things Nephi can look at closely. Each one is an Artifact placed in the
# world (world/props/artifact.gd). Near one, the use button shows the
# magnifying glass, and a press opens its balloon: the artifact's picture and
# name, and Nephi telling about it in his own voice.
#
# The id is used everywhere for the same thing, so keep it in step:
#   - the speaker in story/main.dialogue        liahona: This is the Liahona...
#   - the title of its lines there              ~ artifact_liahona
#   - the folder of its voice clips             voice/liahona/
#   - its cast.json entry (voice_of: "nephi")   tools/voice/cast.json
#   - what the save remembers                   StoryState.record("inspected", id)
# For an achievement for finding a set of them, use an "all_of": "inspected"
# rule in story/achievements.gd. Item pictures can be made with the SDF
# scripts in the parent folder's tools/ (item_sprites.py, memento_sprites.py).
#   "liahona": {
#       "name": "The Liahona",
#       "portrait": "res://world/items/liahona_64.png",
#   },
const LIST := {
}

const TITLE_PREFIX := "artifact_"

static func title_for(id: String) -> String:
	return TITLE_PREFIX + id

static func has(id: String) -> bool:
	return LIST.has(id)

# In the current language, translated under the context "artifact".
static func display_name(id: String) -> String:
	return Language.t(LIST.get(id, {}).get("name", id.capitalize()), "artifact")

# The picture shown beside its lines in the balloon.
static func portrait(id: String) -> Texture2D:
	var path: String = LIST.get(id, {}).get("portrait", "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path)
