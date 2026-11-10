class_name Captions

# Words for showCaption, looked up by key so chapters can say
# showCaption("many_days_later") and the narrator can read them aloud from
# res://voice/narrator/<key>.mp3 (made by tools/voice/generate.py).
# Keep each entry on one line so tools/voice/build_manifest.py can read it.
const TEXT := {
	# "many_days_later": "Many days later...",
}

# A key returns its text in the current language: the translation whose
# context is the key (translations/es.po), or the English here. Anything else
# is shown as written.
static func lookup(key_or_text: String) -> String:
	if not TEXT.has(key_or_text):
		return key_or_text
	return Language.t(TEXT[key_or_text], key_or_text)
