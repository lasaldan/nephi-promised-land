@tool
extends EditorPlugin

# Shows the tile under the mouse in the 2D editor, in the same units a
# chapter's characters list and walkTo() use: world pixels / 32. Cutscene sits
# at the world origin, so these match "start" values directly.

const TILE := 32.0

var _last_mouse := Vector2.INF

func _enter_tree() -> void:
	# Draw over the 2D viewport even when the selected node is not ours.
	set_force_draw_over_forwarding_enabled()

func _process(_delta: float) -> void:
	var viewport := EditorInterface.get_editor_viewport_2d()
	if viewport == null or not _viewport_shown(viewport):
		return
	var mouse := viewport.get_mouse_position()
	if mouse != _last_mouse:
		_last_mouse = mouse
		update_overlays()

func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	var viewport := EditorInterface.get_editor_viewport_2d()
	if viewport == null:
		return
	var mouse := overlay.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, overlay.size).has_point(mouse):
		return
	var to_screen := viewport.global_canvas_transform
	var world := to_screen.affine_inverse() * mouse
	var tile := world / TILE

	# Outline the tile under the mouse. Its top-left corner is the whole-number
	# coordinate, which is where a character's origin lands for that value.
	var cell := Rect2(tile.floor() * TILE, Vector2(TILE, TILE))
	var screen_cell := Rect2(to_screen * cell.position, cell.size * to_screen.get_scale())
	overlay.draw_rect(screen_cell, Color(1, 1, 0, 0.6), false, 1.0)

	var font := overlay.get_theme_default_font()
	var font_size := 14
	var text := "%.1f, %.1f" % [tile.x, tile.y]
	var text_pos := mouse + Vector2(14, -8)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	overlay.draw_rect(Rect2(text_pos + Vector2(-3, -text_size.y + 2), text_size + Vector2(6, 4)), Color(0, 0, 0, 0.7))
	overlay.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _viewport_shown(viewport: Viewport) -> bool:
	var container := viewport.get_parent() as Control
	return container != null and container.is_visible_in_tree()
