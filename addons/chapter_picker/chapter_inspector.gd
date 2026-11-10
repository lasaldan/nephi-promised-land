@tool
extends EditorInspectorPlugin

const PROPERTY := "debug_start_chapter"

func _can_handle(_object: Object) -> bool:
	return true

func _parse_property(_object: Object, type: Variant.Type, name: String, _hint_type: PropertyHint,
		_hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if name != PROPERTY or type != TYPE_STRING:
		return false
	add_property_editor(name, preload("chapter_property.gd").new())
	return true
