extends Resource

class_name Story

# Play order. starts_after on each chapter is what actually unlocks it;
# this list is only the order the director considers them in.
# Add a new chapter script here. Filename numbers are not consulted.
const CHAPTER_SCRIPTS: Array[Script] = [
	# preload("res://story/chapters/arrival.gd"),
]

# Where a finished save opens, free to explore: a chapter that is not part
# of the story, so not in CHAPTER_SCRIPTS. It is never completed or saved.
# null leaves the world as the last chapter left it.
const AFTER_STORY_SCRIPT: Script = null

# First chapter that is not finished and whose start chapter (if any) is finished.
# Returns a fresh instance so runtime state is not stored on a shared resource.
func next_chapter(completed_ids: Array[String]) -> StoryChapter:
	for chapter in _each_chapter():
		if completed_ids.has(chapter.id):
			continue
		if chapter.starts_after.is_empty() or completed_ids.has(chapter.starts_after):
			return chapter
	return null

func chapter_by_id(chapter_id: String) -> StoryChapter:
	for chapter in _each_chapter():
		if chapter.id == chapter_id:
			return chapter
	return null

# Place in play order, or -1 for an unknown id.
func chapter_index(chapter_id: String) -> int:
	var chapters := _each_chapter()
	for i in chapters.size():
		if chapters[i].id == chapter_id:
			return i
	return -1

# Ids that should count as finished so next_chapter() selects chapter_id.
# Clears the array and returns false when the id is not in CHAPTER_SCRIPTS.
func prepare_debug_start(chapter_id: String, ids_before: Array[String]) -> bool:
	ids_before.clear()
	var known := PackedStringArray()
	for chapter in _each_chapter():
		known.append(chapter.id)
		if chapter.id == chapter_id:
			return true
		ids_before.append(chapter.id)
	ids_before.clear()
	push_error("No chapter id '%s'. Known ids: %s" % [chapter_id, ", ".join(known)])
	return false

func _each_chapter() -> Array[StoryChapter]:
	var found: Array[StoryChapter] = []
	for chapter_script in CHAPTER_SCRIPTS:
		# Script.new() is typed as Resource. Cast so a failed script becomes null
		# instead of a type error on the StoryChapter variable.
		var chapter := chapter_script.new() as StoryChapter
		if chapter == null:
			push_error("Chapter script failed to instantiate: %s" % chapter_script.resource_path)
			continue
		found.append(chapter)
	return found
