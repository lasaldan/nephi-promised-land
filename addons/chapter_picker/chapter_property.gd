@tool
extends EditorProperty

# Chapter scripts are not @tool, so the editor never runs their _init() and
# chapter.id is empty here. The id and title are read from the source instead,
# which works as long as _init() assigns them string literals.

const STORY_SCRIPT := "res://story/story.gd"

var _options := OptionButton.new()
var _ids := PackedStringArray()
var _updating := false

func _init() -> void:
	_options.clip_text = true
	_options.item_selected.connect(_on_item_selected)
	add_child(_options)
	add_focusable(_options)

func _update_property() -> void:
	_updating = true
	var current := str(get_edited_object().get(get_edited_property())).strip_edges()
	_options.clear()
	_ids.clear()
	_add_item("(none: normal start)", "")
	for chapter in _read_chapters():
		_add_item("%s  (%s)" % [chapter.id, chapter.title] if chapter.title else chapter.id, chapter.id)
	var index := _ids.find(current)
	if index == -1:
		# A value typed before this plugin, or a chapter since removed.
		_add_item("%s  (not in CHAPTER_SCRIPTS)" % current, current)
		index = _ids.size() - 1
	_options.select(index)
	_updating = false

func _add_item(label: String, id: String) -> void:
	_options.add_item(label)
	_ids.append(id)

func _on_item_selected(index: int) -> void:
	if _updating:
		return
	emit_changed(get_edited_property(), _ids[index])

# [{id, title}] in play order.
func _read_chapters() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var story := load(STORY_SCRIPT) as Script
	if story == null:
		push_warning("Chapter picker: could not load %s" % STORY_SCRIPT)
		return found
	var id_regex := RegEx.create_from_string("(?m)^\\s*id\\s*=\\s*\"([^\"]*)\"")
	var title_regex := RegEx.create_from_string("(?m)^\\s*title\\s*=\\s*\"([^\"]*)\"")
	var constants := story.get_script_constant_map()
	var scripts: Array = constants.get("CHAPTER_SCRIPTS", []).duplicate()
	# A finished save's camp, after the story.
	if constants.get("AFTER_STORY_SCRIPT") is Script:
		scripts.append(constants["AFTER_STORY_SCRIPT"])
	for chapter_script: Script in scripts:
		var source := chapter_script.source_code
		var id_match := id_regex.search(source)
		if id_match == null:
			push_warning("Chapter picker: no id = \"...\" in %s" % chapter_script.resource_path)
			continue
		var title_match := title_regex.search(source)
		found.append({
			"id": id_match.get_string(1),
			"title": title_match.get_string(1) if title_match else "",
		})
	return found
