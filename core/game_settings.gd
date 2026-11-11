class_name GameSettings
extends RefCounted

# Player settings shared by every save slot: whether each kind of sound plays
# and how loud, fullscreen on desktop, the language (scripts/language.gd),
# and reduced flashing (lightning, world/weather/rain.gd).
# Kept in their own file, so erasing a save slot leaves them alone. The volumes drive the buses in
# default_bus_layout.tres. Every AudioStreamPlayer should name one of them;
# a player left on Master ignores these settings.
#
# Static, not an autoload. Call ensure_loaded() from any scene that can be
# the first one played (splash, and world for F6 or a debug start).

const PATH := "user://settings.cfg"

const MUSIC := &"Music"
const SFX := &"SFX"
const VOICE := &"Voice"
const BUSES: Array[StringName] = [MUSIC, SFX, VOICE]

const DEFAULT_VOLUME := {MUSIC: 0.7, SFX: 1.0, VOICE: 1.0}

# Every player of spoken words (dialogue, verses, captions, the tour, the
# quest) joins this group, so a tap on the quest plaque can tell whether
# someone is already speaking.
const VOICE_PLAYERS := &"voice_players"

static func is_voice_playing(tree: SceneTree) -> bool:
	for player in tree.get_nodes_in_group(VOICE_PLAYERS):
		if player.playing:
			return true
	return false

# 0 to 1 per bus, applied on a curve so the slider sounds even.
static var _volume := DEFAULT_VOLUME.duplicate()
static var _enabled := {MUSIC: true, SFX: true, VOICE: true}
static var _fullscreen := false
# "" until the player picks one in Settings, so the game follows the device.
static var _language := ""
# For players bothered by flashing light: lightning only glows softly.
static var _reduce_flashing := false
static var _loaded := false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		for bus in BUSES:
			_volume[bus] = clampf(file.get_value("volume", bus, _volume[bus]), 0.0, 1.0)
			_enabled[bus] = file.get_value("enabled", bus, true)
		_fullscreen = file.get_value("display", "fullscreen", false)
		_language = file.get_value("display", "language", "")
		_reduce_flashing = file.get_value("display", "reduce_flashing", false)
	Language.apply(language())
	for bus in BUSES:
		_apply_bus(bus)
	if can_fullscreen() and _fullscreen:
		_apply_fullscreen()

static func save() -> void:
	var file := ConfigFile.new()
	for bus in BUSES:
		file.set_value("volume", bus, _volume[bus])
		file.set_value("enabled", bus, _enabled[bus])
	file.set_value("display", "fullscreen", _fullscreen)
	file.set_value("display", "reduce_flashing", _reduce_flashing)
	if not _language.is_empty():
		file.set_value("display", "language", _language)
	var err := file.save(PATH)
	if err != OK:
		push_error("Could not save settings to %s (error %d)" % [PATH, err])

static func volume(bus: StringName) -> float:
	return _volume[bus]

static func set_volume(bus: StringName, value: float) -> void:
	_volume[bus] = clampf(value, 0.0, 1.0)
	_apply_bus(bus)

static func is_enabled(bus: StringName) -> bool:
	return _enabled[bus]

static func set_enabled(bus: StringName, on: bool) -> void:
	_enabled[bus] = on
	_apply_bus(bus)

# Phones and tablets are always fullscreen, so the menu hides the option there.
static func can_fullscreen() -> bool:
	return not OS.has_feature("mobile")

static func is_fullscreen() -> bool:
	return _fullscreen

static func set_fullscreen(on: bool) -> void:
	_fullscreen = on
	_apply_fullscreen()

static func is_reducing_flashing() -> bool:
	return _reduce_flashing

# Saved with the rest at save(). Read at each flash, so it applies at once.
static func set_reduce_flashing(on: bool) -> void:
	_reduce_flashing = on

# The language picked in Settings, or the device's until one is picked.
static func language() -> String:
	if _language.is_empty():
		return Language.device_language()
	return Language.supported_or_default(_language)

# Saved with the rest at save(), like the volumes.
static func set_language(language: String) -> void:
	_language = Language.supported_or_default(language)
	Language.apply(_language)

# For a moment meant to be heard (the ending's music): the bus at least
# floor loud until restore_bus(), without changing the setting. A bus
# switched off, or slid all the way down, stays silent.
static func raise_bus_to(bus: StringName, floor: float) -> void:
	if _enabled[bus] and _volume[bus] > 0.0:
		_apply_bus(bus, maxf(_volume[bus], floor))

static func restore_bus(bus: StringName) -> void:
	_apply_bus(bus)

static func _apply_bus(bus: StringName, value: float = -1.0) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("No audio bus '%s'. Is default_bus_layout.tres missing?" % bus)
		return
	if value < 0.0:
		value = _volume[bus]
	AudioServer.set_bus_mute(index, not _enabled[bus] or value <= 0.0)
	# Squared, because a straight line in linear volume is all loud until the end.
	AudioServer.set_bus_volume_db(index, linear_to_db(value * value))

static func _apply_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen \
			else DisplayServer.WINDOW_MODE_WINDOWED)
