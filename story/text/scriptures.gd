class_name Scriptures

# Text for ScriptureScroll, looked up by key so chapters can say
# showScroll("1_nephi_17_8") instead of pasting the verse inline.
# Values are BBCode, so [i]...[/i] and [center]...[/center] work.
const TEXT := {
	"1_nephi_18_8": "And it came to pass after we had all gone down into the ship, ... we did put forth into the sea and were driven forth before the wind towards the promised land.\n\n[right][i]1 Nephi 18:8[/i][/right]",
	# "1_nephi_18_23": "And it came to pass that after we had sailed for the space of many days we did arrive at the promised land. (1 Nephi 18:23)",
}

# A key returns its text in the current language: the translation whose
# context is the key (translations/es.po), or the English here. Anything else
# is shown as written.
static func lookup(key_or_text: String) -> String:
	if not TEXT.has(key_or_text):
		return key_or_text
	return Language.t(TEXT[key_or_text], key_or_text)
