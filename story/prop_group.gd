extends Node2D

class_name PropGroup

# A group of props under Chapters/Props that lasts across several chapters.
# Unlike a chapter's Set, these nodes are never swapped out, so whatever state
# the story gives them (a filled crate) carries on to later chapters.
# Chapters shows or hides the group each time a chapter starts, by the order
# in Story.CHAPTER_SCRIPTS. Props directly under Props, outside any group, are
# always shown.

# First chapter the group is in. Empty means from the start of the game.
@export var appears_in: String = ""
# Hidden during appears_in until that chapter calls showProp() on the group or
# on anything inside it. Shown from the start of every later chapter.
@export var starts_hidden: bool = false
# Last chapter the group is in. It is hidden, with collision off, from the next
# chapter on. Empty means it stays for the rest of the game.
@export var gone_after: String = ""

# Set by apply_lifespan once the running chapter is past gone_after.
var expired := false

# chapter_index is the running chapter's place in Story.CHAPTER_SCRIPTS.
func apply_lifespan(chapter_index: int, story: Story) -> void:
	var first := _index_of(appears_in, story, -1)
	var last := _index_of(gone_after, story, 1 << 30)
	expired = chapter_index > last
	var shown := chapter_index > first and chapter_index <= last
	if chapter_index == first:
		shown = not starts_hidden and chapter_index <= last
	set_shown(shown)

func set_shown(shown: bool) -> void:
	visible = shown
	process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED
	ChapterContent.set_interaction(self, shown)

func _index_of(chapter_id: String, story: Story, missing: int) -> int:
	if chapter_id.is_empty():
		return missing
	var index := story.chapter_index(chapter_id)
	if index < 0:
		push_warning("PropGroup %s: no chapter id '%s'" % [name, chapter_id])
		return missing
	return index
