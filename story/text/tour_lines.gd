class_name TourLines

# What Nephi says in the tour of the controls (ui/ui_tour.gd), looked up by
# key. Each is shown in the bubble and read aloud from
# res://voice/nephi/<key>.mp3 (made by tools/voice/generate.py), so a child
# who can't read yet can still follow it. A line that differs by device has a
# _touch and a _desktop key; world.gd showUiTour() picks one.
# Keep each entry on one line so tools/voice/build_manifest.py can read it.
const TEXT := {
	"tour_walk_touch": "Drag here to help me walk around. ",
	"tour_walk_desktop": "Use the WASD keys to help me walk around.",
	"tour_use_touch": "When I'm close to something, tap here to pick it up, or to talk to someone.",
	"tour_use_desktop": "When I'm close to something, press Space, or click here, to pick it up or talk to someone.",
	"tour_quest_touch": "This tells us what to do next. Tap it to hear it.",
	"tour_quest_desktop": "This tells us what to do next. Click it to hear it.",
	"tour_pray_touch": "Not sure where to go? Tap here, and I'll pray to know the way.",
	"tour_pray_desktop": "Not sure where to go? Click here, and I'll pray to know the way.",
	"tour_backpack": "Things we pick up go here, in my backpack. Now, let's go!",
}

# Who reads them: voice/<SPEAKER>/<key>.mp3.
const SPEAKER := "nephi"

# A key's words in the current language, translated under the key as context.
static func text(key: String) -> String:
	return Language.t(TEXT.get(key, key), key)
