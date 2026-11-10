extends Node

# Autoload. Everything a save file needs to rebuild the story: which chapters
# are finished, and flags that chapters set along the way. Props render from
# these flags, not the other way around, so a loaded game and a debug start
# look the same as a played-through one.
#
# The game saves when a chapter completes. Loading resumes at the start of the
# next chapter, because a play() that is partway through its awaits cannot be
# written to disk. Flags changed during an unfinished chapter are not saved.
#
# Progress toward achievements is kept apart from the flags and saved as soon
# as it changes, so it is never lost to quitting partway through a chapter:
#   achievements   ids earned (story/achievements.gd)
#   counts         named counters: count("prayers")
#   records        named sets of ids: record("talked_to", "lehi")
#
# There are SLOT_COUNT save files, one per slot. The main menu sets `slot`
# before opening the world, and every save call below works on that slot.

# Any change: set_flag, load_game, reset. Props that render from a flag listen here.
signal changed
# A new achievement this session, for the toast. Not sent on load.
signal achievement_unlocked(id: String)

const SLOT_COUNT := 3
# Bump when the saved layout changes in a way old saves cannot be read as.
const SAVE_VERSION := 1

# 1-based, so it matches the number the menu shows.
var slot := 1
# Set by the main menu when a slot card is pressed. The world then always
# loads that slot, whatever its resume_from_save says.
var slot_chosen := false

var completed_chapter_ids: Array[String] = []
# Values must be plain data (String, numbers, bool, Vector2, Array, Dictionary).
var flags: Dictionary = {}
var achievements: Array[String] = []
var counts: Dictionary = {}
var records: Dictionary = {}
# Seconds spent in the world on this slot, counting chapters replayed after
# quitting partway. The world adds to it while unpaused and writes it with
# save_played_time().
var played_seconds := 0.0
# A debug start never touches the save file, so achievements earned during
# one are not written either. world.gd sets it after reset().
var debug_run := false
# True once this session has loaded or saved the slot, so the file on disk is
# this game's. A world started fresh over an old save (resume_from_save off)
# must not write its clock into that save before its first chapter save.
var _save_is_ours := false

# --- Flags ---

func set_flag(key: String, value: Variant) -> void:
	flags[key] = value
	changed.emit()

func get_flag(key: String, default: Variant = null) -> Variant:
	return flags.get(key, default)

func has_flag(key: String) -> bool:
	return flags.has(key)

func complete_chapter(chapter_id: String) -> void:
	if not completed_chapter_ids.has(chapter_id):
		completed_chapter_ids.append(chapter_id)
	# The chapter save right after this writes them, so no early write.
	for id in Achievements.with_rule("chapter", chapter_id):
		unlock_achievement(id, false)

# --- Achievements and their progress ---

func has_achievement(id: String) -> bool:
	return achievements.has(id)

# Earns id in this slot. Earning one already earned does nothing. persist
# writes it to the save file now, for one earned partway through a chapter.
func unlock_achievement(id: String, persist := true) -> void:
	if not Achievements.LIST.has(id):
		push_error("No achievement '%s'" % id)
		return
	if achievements.has(id):
		return
	achievements.append(id)
	print("Achievement: %s" % id)
	achievement_unlocked.emit(id)
	if persist:
		_save_progress()

# Adds to a named counter and returns the new value.
#   StoryState.count("prayers")
func count(counter: String, amount := 1) -> int:
	counts[counter] = get_count(counter) + amount
	_save_progress()
	Achievements.check_count(counter, counts[counter])
	return counts[counter]

func get_count(counter: String) -> int:
	return counts.get(counter, 0)

# Adds an id to a named set, once. Returns false when it was already there.
#   StoryState.record("talked_to", "lehi")
func record(record_name: String, id: String) -> bool:
	var seen: Array = records.get(record_name, [])
	if seen.has(id):
		return false
	seen.append(id)
	records[record_name] = seen
	_save_progress()
	Achievements.check_record(record_name, seen)
	return true

func get_record(record_name: String) -> Array:
	return records.get(record_name, [])

func _ready() -> void:
	SignalBus.activity_finished.connect(func(activity_id: String) -> void:
		for id in Achievements.with_rule("activity", activity_id):
			unlock_achievement(id))

# --- Files ---

func save_path(for_slot: int = slot) -> String:
	return "user://save_%d.cfg" % for_slot

# The last save that read back whole, kept beside the slot's save. Godot does
# not flush a written file to storage, so if the phone loses power just after
# a save, the save can come back empty. The slot then reads from this instead,
# and loses at most that last save.
func backup_path(for_slot: int = slot) -> String:
	return "user://save_%d.bak" % for_slot

func has_save(for_slot: int = slot) -> bool:
	return FileAccess.file_exists(save_path(for_slot)) \
			or FileAccess.file_exists(backup_path(for_slot))

# The file at path, or null when it is missing, unreadable, or has no version
# (an empty or zeroed file from a cut-off write loads, but with nothing in it).
func _read_save_file(path: String) -> ConfigFile:
	var file := ConfigFile.new()
	if not FileAccess.file_exists(path) or file.load(path) != OK:
		return null
	if not file.has_section_key("save", "version"):
		return null
	return file

# The slot's save, or its backup when the save is broken. Null with neither.
func _read_save(for_slot: int = slot) -> ConfigFile:
	var file := _read_save_file(save_path(for_slot))
	if file:
		return file
	file = _read_save_file(backup_path(for_slot))
	if file:
		push_warning("Save for slot %d was unreadable; using its backup" % for_slot)
	return file

# Backs up the slot's save, if it reads back whole, then writes file over it.
func _write_save(file: ConfigFile) -> Error:
	if _read_save_file(save_path()):
		var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path()),
				ProjectSettings.globalize_path(backup_path()))
		if err != OK:
			push_error("Could not back up %s (error %d)" % [save_path(), err])
	return file.save(save_path())

# What the menu shows on a slot's card, read without loading it.
# {exists, percent (0-100), achievements, achievement_total, played_seconds}
func slot_summary(for_slot: int) -> Dictionary:
	var summary := {"exists": false, "percent": 0, "achievements": 0,
			"achievement_total": Achievements.LIST.size(), "played_seconds": 0.0}
	if not has_save(for_slot):
		return summary
	summary.exists = true
	var file := _read_save(for_slot)
	if not file:
		return summary
	# Finished chapters out of all chapters. Chapters vary in length, so this
	# is an estimate, and it reads 100 only once the last one is done.
	var done: Array = file.get_value("save", "completed_chapter_ids", [])
	var total := Story.CHAPTER_SCRIPTS.size()
	summary.percent = clampi(floori(100.0 * done.size() / total), 0, 100) if total > 0 else 0
	summary.achievements = slot_achievements(for_slot).size()
	summary.played_seconds = file.get_value("save", "played_seconds", 0.0)
	return summary

# Achievement ids earned in a slot, read without loading it. Empty with no save.
func slot_achievements(for_slot: int) -> Array[String]:
	var ids: Array[String] = []
	var file := _read_save(for_slot)
	if file:
		ids.assign((file.get_value("save", "achievements", []) as Array).filter(
				func(id): return Achievements.LIST.has(id)))
	return ids

func save_game() -> void:
	var file := ConfigFile.new()
	file.set_value("save", "version", SAVE_VERSION)
	file.set_value("save", "completed_chapter_ids", completed_chapter_ids)
	file.set_value("save", "flags", flags)
	for key in _progress():
		file.set_value("save", key, _progress()[key])
	file.set_value("save", "played_seconds", played_seconds)
	var err := _write_save(file)
	if err != OK:
		push_error("Could not save the game to %s (error %d)" % [save_path(), err])
		return
	_save_is_ours = true
	print("Saved slot %d after %s" % [slot, completed_chapter_ids])

func _progress() -> Dictionary:
	return {"achievements": achievements, "counts": counts, "records": records}

# Writes only the achievements and their progress into the slot's save. With
# no save yet (partway through the first chapter) they wait for the first
# chapter save, which writes everything.
func _save_progress() -> void:
	_update_save(_progress())

# Writes only played_seconds into the slot's save, so time spent partway
# through a chapter is kept when the player quits.
func save_played_time() -> void:
	if _save_is_ours:
		_update_save({"played_seconds": played_seconds})

# Sets these keys in the slot's existing save and leaves the rest as it was.
func _update_save(values: Dictionary) -> void:
	if debug_run or not has_save():
		return
	var file := _read_save()
	if not file:
		push_error("Could not read the save at " + save_path())
		return
	for key in values:
		file.set_value("save", key, values[key])
	var err := _write_save(file)
	if err != OK:
		push_error("Could not update %s in %s (error %d)" % [values.keys(), save_path(), err])

# Returns false, and leaves the current state alone, when there is no usable save.
func load_game() -> bool:
	if not has_save():
		return false
	var file := _read_save()
	if not file:
		push_error("Could not read the save at " + save_path())
		return false
	if file.get_value("save", "version", 0) != SAVE_VERSION:
		push_warning("Ignoring a save from an older version of the game")
		return false
	completed_chapter_ids.assign(file.get_value("save", "completed_chapter_ids", []))
	flags = file.get_value("save", "flags", {})
	achievements.assign((file.get_value("save", "achievements", []) as Array).filter(
			func(id): return Achievements.LIST.has(id)))
	counts = file.get_value("save", "counts", {})
	records = file.get_value("save", "records", {})
	played_seconds = file.get_value("save", "played_seconds", 0.0)
	_save_is_ours = true
	print("Loaded slot %d: %s" % [slot, completed_chapter_ids])
	changed.emit()
	return true

func delete_save(for_slot: int = slot) -> void:
	for path in [save_path(for_slot), backup_path(for_slot)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# A new game: nothing finished, no flags. Does not touch the file on disk.
func reset() -> void:
	completed_chapter_ids.clear()
	flags.clear()
	achievements.clear()
	counts.clear()
	records.clear()
	played_seconds = 0.0
	debug_run = false
	_save_is_ours = false
	changed.emit()
