class_name Scriptures

# Text for ScriptureScroll, looked up by key so chapters can say
# showScroll("1_nephi_17_8") instead of pasting the verse inline.
# Values are BBCode, so [i]...[/i] and [center]...[/center] work.
const TEXT := {
	# "1_nephi_18_23": "And it came to pass that after we had sailed for the space of many days we did arrive at the promised land. (1 Nephi 18:23)",
}

# A key returns its text in the current language: the translation whose
# context is the key (translations/es.po), or the English here. Anything else
# is shown as written.
static func lookup(key_or_text: String) -> String:
	if not TEXT.has(key_or_text):
		return key_or_text
	return Language.t(TEXT[key_or_text], key_or_text)
