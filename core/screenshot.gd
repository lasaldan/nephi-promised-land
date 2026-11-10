extends Node

# Store screenshots, only in debug builds so it is not in the released game.
#
# F11 picks the next store size in SIZES and makes the window the biggest it
# can be on this screen at that shape. The game lays itself out to the shape
# (ScreenShape), so it looks as it would on that device.
# F12 saves what the window shows as a PNG on the Desktop, scaled to the
# store size picked with F11. The window is usually smaller than the store
# size (an iPad screenshot is taller than a laptop screen), so the picture
# is scaled up a little. Before F11 is pressed it is saved at window size.
# After F11 the size's name shows on screen for a moment, so you know which
# one is picked. It is hidden before F12 saves, so it never shows in a PNG.

const PICK_KEY := KEY_F11
const SAVE_KEY := KEY_F12

# Landscape, the way the game is played. Sizes App Store Connect asks for.
const SIZES := [
	{"name": "iphone_6.9", "size": Vector2i(2868, 1320)},
	# App Store Connect turned down 2868x1320 for iPhone; this is the nearest
	# size it took (2556x1179, 2622x1206 and their portrait turns).
	{"name": "iphone_6.3", "size": Vector2i(2622, 1206)},
	# iPhone Duo. It also takes 2034x1398, a little wider; this is the larger.
	{"name": "iphone_duo", "size": Vector2i(2853, 2007)},
	{"name": "ipad_13", "size": Vector2i(2752, 2064)},
]

# Room left on the screen for the title bar and the Dock.
const SCREEN_MARGIN := 120

# How long the picked size's name stays on screen, in seconds.
const NAME_SHOW_TIME := 1.0
const NAME_FADE_TIME := 0.3

var _picked := -1
var _name_label: Label
var _name_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build():
		set_process_input(false)
		return
	# Drawn above everything else in the game.
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_name_label = Label.new()
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("font_size", 64)
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 16)
	_name_label.visible = false
	layer.add_child(_name_label)

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == PICK_KEY:
		get_viewport().set_input_as_handled()
		_pick_next()
	elif key.keycode == SAVE_KEY:
		get_viewport().set_input_as_handled()
		_save()

func _pick_next() -> void:
	_picked = (_picked + 1) % SIZES.size()
	var target: Vector2i = SIZES[_picked].size
	var window := get_window()
	var room := DisplayServer.screen_get_usable_rect(window.current_screen)
	room.size -= Vector2i(SCREEN_MARGIN, SCREEN_MARGIN)
	var scale := minf(1.0, minf(float(room.size.x) / target.x, float(room.size.y) / target.y))
	var fitted := Vector2i(roundi(target.x * scale), roundi(target.y * scale))
	# On macOS a resize from code leaves the picture drawn at the window's
	# last shape, squeezed with bars at the sides, until the window is resized
	# again. So it is resized twice, a pixel apart.
	window.size = fitted + Vector2i(0, 1)
	window.position = room.position + (room.size - window.size) / 2
	for i in 2:
		await get_tree().process_frame
	window.size = fitted
	for i in 2:
		await get_tree().process_frame
	ScreenShape.fit()
	print("Screenshot size: %s %s, window %s" % [SIZES[_picked].name, target, window.size])
	_show_name("%s\n%d × %d" % [SIZES[_picked].name, target.x, target.y])
	# The editor's Game tab draws the game squeezed into its own panel, so the
	# window looks the wrong shape there. The saved PNG is still right.
	if Engine.is_embedded_in_editor():
		push_warning("Running inside the editor's Game tab, so it will look squeezed. "
			+ "Turn off Embed Game in the Game tab's menu, or run from a terminal, to see the real shape.")

func _show_name(text: String) -> void:
	if _name_tween:
		_name_tween.kill()
	_name_label.text = text
	_name_label.modulate.a = 1.0
	_name_label.visible = true
	_name_tween = create_tween()
	_name_tween.tween_interval(NAME_SHOW_TIME)
	_name_tween.tween_property(_name_label, "modulate:a", 0.0, NAME_FADE_TIME)
	_name_tween.tween_callback(_name_label.hide)

func _save() -> void:
	# If the size's name is still on screen, hide it and let a clean frame
	# draw first.
	if _name_label.visible:
		_name_tween.kill()
		_name_label.hide()
		for i in 2:
			await get_tree().process_frame
	# The last frame drawn, which is what the window shows.
	var image := get_viewport().get_texture().get_image()
	var label := "window"
	if _picked >= 0:
		var target: Vector2i = SIZES[_picked].size
		label = SIZES[_picked].name
		if image.get_size() != target:
			image.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).path_join(
		"promised_land_%s_%dx%d_%s.png" % [label, image.get_width(), image.get_height(), stamp])
	var err := image.save_png(path)
	if err == OK:
		print("Screenshot saved: ", path)
	else:
		push_error("Screenshot failed (%s): %s" % [error_string(err), path])
