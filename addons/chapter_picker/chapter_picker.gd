@tool
extends EditorPlugin

# Replaces the debug_start_chapter text box on World with a dropdown. The list
# comes from Story.CHAPTER_SCRIPTS, so adding a chapter there adds it here.

var _inspector: EditorInspectorPlugin

func _enter_tree() -> void:
	_inspector = preload("chapter_inspector.gd").new()
	add_inspector_plugin(_inspector)

func _exit_tree() -> void:
	remove_inspector_plugin(_inspector)
	_inspector = null
