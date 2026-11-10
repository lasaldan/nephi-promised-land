@tool
extends Node2D

class_name Chapters

# Shows preview_spawns() as temporary actors while editing. Empty shows none.
# They are not saved. This does not hide other Sets; use the eye icon on those
# chapter nodes when their props sit on the same ground. Ignored in game.
@export var editor_preview_chapter: String = "":
	set(value):
		editor_preview_chapter = value
		if Engine.is_editor_hint():
			_refresh_preview()

# One ChapterContent child per chapter, chapter_id set to StoryChapter.id.
# Each child has two nodes:
#   Triggers — StoryTrigger areas for that chapter's goals
#   Set — the props visible during that chapter (tents, fields, a boat)
# Add the next chapter by duplicating one of these nodes. A later camp stage
# should instance the previous Set under its own Set and add the new pieces,
# so the old goal areas are not copied along with the tents.
# y_sort_enabled stays on this node, each chapter, and each Set so props sort
# with the player. An instanced prop that still draws out of order usually
# needs Z As Relative turned off on that instance.

func _ready() -> void:
	# deactivate_all() writes visible and process_mode. In the editor that would
	# hide every Set and can be saved into the scene by accident.
	if Engine.is_editor_hint():
		_refresh_preview()
		return
	deactivate_all()

func _refresh_preview() -> void:
	_clear_preview_actors()
	if not is_inside_tree():
		return
	var target := editor_preview_chapter.strip_edges()
	if target.is_empty():
		return
	var chapter := Story.new().chapter_by_id(target)
	if chapter == null:
		push_warning("No chapter id '%s' to preview" % target)
		return
	for mark in chapter.preview_spawns():
		_add_preview_actor(mark)

# Internal children are omitted from the saved scene, so a preview cannot
# accidentally become part of the camp.
func _add_preview_actor(mark: Dictionary) -> void:
	var label := str(mark.get("label", ""))
	# A second of a kind, such as sheep2, uses the first one's scene.
	var path := Cast.scene_path(label)
	if path.is_empty():
		push_warning("No character scene to preview for '%s'" % label)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var actor := packed.instantiate()
	actor.position = mark.get("position", Vector2.ZERO)
	actor.set_meta("_chapter_preview", true)
	# A character scene includes its own Camera2D. Leave it off so the 2D
	# editor keeps the view you are already looking at.
	var camera := actor.get_node_or_null("Camera2D") as Camera2D
	if camera:
		camera.enabled = false
	add_child(actor, false, Node.INTERNAL_MODE_BACK)

func _clear_preview_actors() -> void:
	var stale: Array[Node] = []
	for child in get_children(true):
		if child.get_meta("_chapter_preview", false):
			stale.append(child)
	for child in stale:
		remove_child(child)
		child.free()

# Called from StoryChapter.setup. Every other chapter is hidden and disarmed,
# and each PropGroup under Props is shown or hidden for this point in the story.
# content_id names the ChapterContent to show when the chapter borrows another
# chapter's Set. PropGroups still go by chapter_id, the place in the story.
func activate_chapter(chapter_id: String, content_id: String = "") -> void:
	if content_id.is_empty():
		content_id = chapter_id
	for chapter in _chapters():
		if chapter.chapter_id == content_id:
			chapter.activate()
		else:
			chapter.deactivate()
	_apply_prop_lifespans(chapter_id)
	# What stands where has changed, so where people can walk has too.
	WorldNavigation.rebuild_soon(self)

# Props holds whatever outlasts a single chapter. Its
# nodes keep their state from chapter to chapter; PropGroups under it decide
# which chapters they appear in.
func _props_root() -> Node2D:
	return get_node_or_null("Props") as Node2D

func _apply_prop_lifespans(chapter_id: String) -> void:
	var root := _props_root()
	if root == null:
		return
	var story := Story.new()
	var index := story.chapter_index(chapter_id)
	for group in _prop_groups(root):
		group.apply_lifespan(index, story)

func _prop_groups(node: Node) -> Array[PropGroup]:
	var found: Array[PropGroup] = []
	for child in node.get_children():
		if child is PropGroup:
			found.append(child)
		found.append_array(_prop_groups(child))
	return found

func deactivate_chapter(chapter_id: String) -> void:
	for chapter in _chapters():
		if chapter.chapter_id == chapter_id:
			chapter.deactivate()
			return

func deactivate_all() -> void:
	for chapter in _chapters():
		chapter.deactivate()

func arm(chapter_id: String, trigger_name: String) -> void:
	var chapter := _find(chapter_id)
	if chapter == null:
		push_error("No chapter content for '%s'" % chapter_id)
		return
	chapter.arm(trigger_name)

func get_trigger(chapter_id: String, trigger_name: String) -> StoryTrigger:
	var chapter := _find(chapter_id)
	if chapter == null:
		push_error("No chapter content for '%s'" % chapter_id)
		return null
	return chapter.get_trigger(trigger_name)

# Looks in the chapter's Set first, then under Props. Revealing something
# under Props also reveals the PropGroup it sits in.
func show_prop(chapter_id: String, prop_name: String) -> void:
	var chapter := _find(chapter_id)
	if chapter == null:
		push_error("No chapter content for '%s'" % chapter_id)
		return
	if chapter.has_prop(prop_name):
		chapter.show_prop(prop_name)
		return
	var prop := _find_in_props(prop_name)
	if prop == null:
		push_error("No prop named '%s' in chapter '%s' Set or in Props" % [prop_name, chapter_id])
		return
	_reveal_in_props(prop)

# The chapter's Set wins when both have a node with this name.
func get_prop(chapter_id: String, prop_name: String) -> Node:
	var chapter := _find(chapter_id)
	if chapter and chapter.has_prop(prop_name):
		return chapter.get_prop(prop_name)
	var prop := _find_in_props(prop_name)
	if prop == null:
		push_error("No prop named '%s' in chapter '%s' Set or in Props" % [prop_name, chapter_id])
	return prop

func _find_in_props(prop_name: String) -> Node:
	var root := _props_root()
	return ChapterContent.find_named(root, prop_name) if root else null

# Groups from the outside in, so an inner group is not left hidden by an outer one.
func _reveal_in_props(prop: Node) -> void:
	var root := _props_root()
	var chain: Array[Node] = []
	var node := prop
	while node and node != root:
		chain.push_front(node)
		node = node.get_parent()
	for link in chain:
		if link is PropGroup:
			(link as PropGroup).set_shown(true)
		elif link == prop and link is CanvasItem:
			(link as CanvasItem).visible = true
			link.process_mode = Node.PROCESS_MODE_INHERIT
			ChapterContent.set_interaction(link, true)

# scene_number 1 is the Set child named Scene1. Called from StoryChapter.
func set_scene_enabled(chapter_id: String, scene_number: int, enabled: bool) -> void:
	var chapter := _find(chapter_id)
	if chapter == null:
		push_error("No chapter content for '%s'" % chapter_id)
		return
	chapter.set_scene_enabled(scene_number, enabled)

func _find(chapter_id: String) -> ChapterContent:
	for chapter in _chapters():
		if chapter.chapter_id == chapter_id:
			return chapter
	return null

func _chapters() -> Array[ChapterContent]:
	var found: Array[ChapterContent] = []
	for child in get_children():
		if child is ChapterContent:
			found.append(child)
	return found
