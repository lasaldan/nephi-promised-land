class_name Language
extends RefCounted

# The languages the game can be played in, and where each one's words and
# voice clips live. The words are Godot translations: translations/es.po,
# registered under Project Settings > Localization > Translations, holds the
# Spanish for everything on screen (see LOCALIZATION.md). English needs no
# file: it is the text written in the scripts, scenes and main.dialogue.
#
# GameSettings remembers the player's choice and calls apply() at start-up.
# Until they pick one in Settings, the game follows the device's language.

const ENGLISH := "en"
const SPANISH := "es"
const SUPPORTED: Array[String] = [ENGLISH, SPANISH]
const DEFAULT := ENGLISH
# Each one written in its own language, so a player who can't read the one
# showing can still find theirs in the Settings picker.
const NAMES := {ENGLISH: "English", SPANISH: "Español"}

# The device's language, if the game has it, otherwise English. On Android 13+
# this is the per-app language when one is set.
static func device_language() -> String:
	return supported_or_default(OS.get_locale_language())

static func supported_or_default(language: String) -> String:
	language = language.substr(0, 2).to_lower()
	return language if language in SUPPORTED else DEFAULT

# The language the game is showing now.
static func current() -> String:
	return supported_or_default(TranslationServer.get_locale())

static func is_english() -> bool:
	return current() == ENGLISH

# Switches every translated word over. Controls with auto-translate redraw on
# their own; scripts that build sentences from pieces listen for
# NOTIFICATION_TRANSLATION_CHANGED and build them again.
static func apply(language: String) -> void:
	language = supported_or_default(language)
	if TranslationServer.get_locale() != language:
		TranslationServer.set_locale(language)

# The words for text in the current language: the translation of text under
# context, or text itself where there is none (always, in English). Static
# code can't call tr(), so the lookups in story/quests.gd and the like use this.
static func t(text: String, context: String = "") -> String:
	if text.is_empty():
		return text
	return String(TranslationServer.translate(text, context))

# One of two forms by count: t_n("Find %d more log", "Find %d more logs", 2)
# % 2. The translation's Plural-Forms header decides which form a count takes.
static func t_n(singular: String, plural: String, count: int, context: String = "") -> String:
	return String(TranslationServer.translate_plural(singular, plural, count, context))

# "hammer", "hammer and saw", "hammer, saw, and nails", in the current
# language ("martillo, sierra y clavos").
static func join_list(items: Array) -> String:
	if items.is_empty():
		return ""
	if items.size() == 1:
		return str(items[0])
	if items.size() == 2:
		return t("%s and %s", "list") % [items[0], items[1]]
	var head := PackedStringArray()
	for item in items.slice(0, -1):
		head.append(str(item))
	return t("%s, and %s", "list") % [t(", ", "list").join(head), items[-1]]

# Where a voice clip lives: res://voice/<character>/<clip>.mp3 in English,
# res://voice/<language>/<character>/<clip>.mp3 in any other (made by
# tools/voice/generate.py --locale <language>).
static func voice_path(character: String, clip: String, language: String = "") -> String:
	if language.is_empty():
		language = current()
	if language == ENGLISH:
		return "res://voice/%s/%s.mp3" % [character, clip]
	return "res://voice/%s/%s/%s.mp3" % [language, character, clip]

# The clip in the current language, or null when it has not been made. A
# Spanish line with no Spanish clip stays silent rather than playing the
# English one under Spanish words.
static func voice(character: String, clip: String) -> AudioStream:
	var path := voice_path(character, clip)
	if not ResourceLoader.exists(path):
		return null
	return load(path)

static func has_voice(character: String, clip: String) -> bool:
	return ResourceLoader.exists(voice_path(character, clip))
