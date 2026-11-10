extends Node2D

class_name ChapterContent

# Must match StoryChapter.id, or the set_id of chapters that share this Set.
# The node name is for the editor tree.
@export var chapter_id: String = ""

func _ready() -> void:
	# Hidden until this chapter is the one running. Props stay visible in the
	# editor so they can be placed on the map; play mode turns the others off.
	deactivate()

# Show this chapter's Set and arm triggers marked starts_armed.
# A prop or area for a later beat stays off until show_prop() or arm().
func activate() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	_set_shown(_props(), true)
	for trigger in _triggers():
		trigger.set_armed(trigger.starts_armed)

func deactivate() -> void:
	for trigger in _triggers():
		trigger.set_armed(false)
	_set_shown(_props(), false)
	# Stops scripts on this chapter. Tile collision is cleared in _set_shown;
	# process_mode alone leaves TileMapLayer bodies in the physics world.
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

func get_trigger(trigger_name: String) -> StoryTrigger:
	for trigger in _triggers():
		if trigger.name == trigger_name:
			return trigger
	push_error("Chapter '%s' has no StoryTrigger named '%s'" % [chapter_id, trigger_name])
	return null

func arm(trigger_name: String) -> void:
	for trigger in _triggers():
		if trigger.name == trigger_name:
			trigger.set_armed(true)
			return
	push_error("Chapter '%s' has no StoryTrigger named '%s'" % [chapter_id, trigger_name])

# Reveal one prop that was saved hidden under Set. The Set itself must already
# be showing, which it is while this chapter is active.
func show_prop(prop_name: String) -> void:
	var set := _props()
	if set == null:
		push_error("Chapter '%s' has no Set node" % chapter_id)
		return
	var prop := find_named(set, prop_name)
	if prop == null:
		push_error("Chapter '%s' Set has no prop named '%s'" % [chapter_id, prop_name])
		return
	if prop is CanvasItem:
		prop.visible = true
	prop.process_mode = Node.PROCESS_MODE_INHERIT
	# Showing a prop that was collision-disabled while hidden.
	set_interaction(prop, true)

# Any node under Set by name, at any depth, such as "Crate1".
func get_prop(prop_name: String) -> Node:
	var set := _props()
	var prop := find_named(set, prop_name) if set else null
	if prop == null:
		push_error("Chapter '%s' Set has no prop named '%s'" % [chapter_id, prop_name])
	return prop

func has_prop(prop_name: String) -> bool:
	var set := _props()
	return set != null and find_named(set, prop_name) != null

# Not named _set. That name belongs to Object's property setter, and a
# different signature stops this script from compiling.
func _props() -> Node2D:
	return get_node_or_null("Set") as Node2D

func _set_shown(set: Node2D, shown: bool) -> void:
	if set == null:
		return
	set.visible = shown
	set.process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED
	# visible = false does not take TileMapLayer bodies out of the physics
	# world. Sync collision to match what is actually shown.
	set_interaction(set, shown)

# Scene1, Scene2, ... under Set. Called from StoryChapter.enableScene / disableScene.
func set_scene_enabled(scene_number: int, enabled: bool) -> void:
	var set := _props()
	if set == null:
		push_error("Chapter '%s' has no Set node" % chapter_id)
		return
	var scene := find_named(set, "Scene%d" % scene_number)
	if scene == null:
		push_error("Chapter '%s' Set has no node named Scene%d" % [chapter_id, scene_number])
		return
	if scene is CanvasItem:
		scene.visible = enabled
	# Disabled stops scripts on the scene. It does not remove tile collision;
	# set_interaction does that. A hidden chapter Set stays non-colliding
	# even if this scene was just marked visible, until the chapter is shown.
	scene.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	var set_shown := set.is_visible_in_tree()
	set_interaction(scene, enabled and set_shown)

# `active` is whether this node should interact. A hidden CanvasItem under an
# active parent is turned off too, so a scene saved with the eye closed does
# not keep its tile collision when the chapter starts.
static func set_interaction(node: Node, active: bool) -> void:
	_apply_node_collision(node, active)
	for child in node.get_children():
		var child_active := active
		if active and child is CanvasItem and not (child as CanvasItem).visible:
			child_active = false
		if _is_scene_node(child):
			child.process_mode = Node.PROCESS_MODE_INHERIT if child_active else Node.PROCESS_MODE_DISABLED
		set_interaction(child, child_active)

static func _is_scene_node(node: Node) -> bool:
	var node_name := String(node.name)
	if not node_name.begins_with("Scene"):
		return false
	return node_name.substr(5).is_valid_int()

# Remember the authored collision the first time we turn a node off, and put
# it back the next time that node is shown. A second hide must not save the
# already-disabled values over the originals.
static func _apply_node_collision(node: Node, active: bool) -> void:
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		_set_bool_prop(layer, &"_scene_saved_collision_enabled", &"collision_enabled", active)
		_set_bool_prop(layer, &"_scene_saved_navigation_enabled", &"navigation_enabled", active)
	elif node is CollisionObject2D:
		var body := node as CollisionObject2D
		if active:
			if body.has_meta(&"_scene_saved_collision_layer"):
				body.collision_layer = body.get_meta(&"_scene_saved_collision_layer")
				body.collision_mask = body.get_meta(&"_scene_saved_collision_mask")
				body.remove_meta(&"_scene_saved_collision_layer")
				body.remove_meta(&"_scene_saved_collision_mask")
		else:
			if not body.has_meta(&"_scene_saved_collision_layer"):
				body.set_meta(&"_scene_saved_collision_layer", body.collision_layer)
				body.set_meta(&"_scene_saved_collision_mask", body.collision_mask)
			body.collision_layer = 0
			body.collision_mask = 0

static func _set_bool_prop(node: Object, meta_key: StringName, prop: StringName, active: bool) -> void:
	if active:
		if node.has_meta(meta_key):
			node.set(prop, node.get_meta(meta_key))
			node.remove_meta(meta_key)
		return
	if not node.has_meta(meta_key):
		node.set_meta(meta_key, node.get(prop))
	node.set(prop, false)

# Goal areas live under Triggers, so a tent added to Set is not treated as one.
func _triggers() -> Array[StoryTrigger]:
	var found: Array[StoryTrigger] = []
	var root := get_node_or_null("Triggers")
	if root == null:
		return found
	_collect_triggers(root, found)
	return found

func _collect_triggers(node: Node, found: Array[StoryTrigger]) -> void:
	for child in node.get_children():
		if child is StoryTrigger:
			found.append(child)
		_collect_triggers(child, found)

static func find_named(node: Node, node_name: String) -> Node:
	for child in node.get_children():
		if String(child.name) == node_name:
			return child
		var nested := find_named(child, node_name)
		if nested:
			return nested
	return null
