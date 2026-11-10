class_name Quests

# Quest words, looked up by key, so world.setQuest("quest_return_to_lehi")
# shows them and a tap on the quest plaque has the narrator read them from
# res://voice/narrator/<key>.mp3 (made by tools/voice/generate.py). Quests are
# never read aloud on their own; a child who can't read yet taps to hear one.
# A quest that counts down is in COUNTED too, and is read aloud as its key
# here, which leaves the number out:
#   world.setQuest("quest_more_ore", "", left)
# Keep each entry on one line so tools/voice/build_manifest.py can read it.
const TEXT := {
	# "quest_find_lehi": "Find Father by the river",
}

# Quests that count down, by the key a tap reads (which leaves the number
# out). Each has the words for one left and for more, with %d for the count,
# so a language with other plural rules can say each its own way:
#   world.setQuest("quest_more_ore", "", left)
const COUNTED := {
	# "quest_more_seeds": ["Collect %d more seed", "Collect %d more seeds"],
}

# A key returns its words in the current language: the translation whose
# context is the key (translations/es.po), or the English here. Anything else
# is shown as written.
static func lookup(key_or_text: String) -> String:
	if not TEXT.has(key_or_text):
		return key_or_text
	return Language.t(TEXT[key_or_text], key_or_text)

# A COUNTED quest with count filled in: "Collect 3 more ore".
static func counted(key: String, count: int) -> String:
	var forms: Array = COUNTED.get(key, [])
	if forms.is_empty():
		push_warning("No counted quest '%s' in Quests.COUNTED" % key)
		return lookup(key)
	return Language.t_n(forms[0], forms[1], count, key) % count
