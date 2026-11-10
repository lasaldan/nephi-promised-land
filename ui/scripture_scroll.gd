extends CanvasLayer

class_name ScriptureScroll

# Where the paper sits on the screen (see paper_rect()). The sides run top to
# bottom, BOTTOM spans the width, FULL covers it all, whatever its shape.
enum Placement { LEFT, RIGHT, BOTTOM, FULL }

# Width of a side scroll and height of the bottom one, in 32px tiles.
const SIDE_TILES := 6
const BOTTOM_TILES := 4

# Nine-slice of the scroll in scripture_scroll_tile_set.tres. The rolled ends
# are the top and bottom rows; the middle row and column repeat to fill.
const ATLAS_LEFT := 11
const ATLAS_MIDDLE := 12
const ATLAS_RIGHT := 13
const ATLAS_TOP := 1
const ATLAS_CENTER := 2
const ATLAS_BOTTOM := 3
const TILE := 32

# Pixels between the tile rect and the text, so words stay off the rolled ends.
@export var text_margin_left: int = 12
# Wider than the left, so right-aligned references clear the scroll's edge.
@export var text_margin_right: int = 22
@export var text_margin_top: int = 28
@export var text_margin_bottom: int = 26

@export var max_font_size: int = 16
@export var min_font_size: int = 8

@export var paper_fade_seconds: float = 0.5
@export var text_fade_seconds: float = 0.4

# An optional picture under the text, such as a vision. It takes this share of
# the space inside the margins, from the bottom up, and the text gets the rest.
@export var image_share: float = 0.55
# Below 1 so the parchment still shows through.
@export var image_alpha: float = 0.7
@export var image_fade_seconds: float = 2.0
@export var image_fade_out_seconds: float = 1.0

@onready var paper: TileMapLayer = $Paper
@onready var label: RichTextLabel = $Paper/Text
# Holds the picture, a texture or a scene of its own, sized to the image area.
@onready var image: Control = $Paper/Image

# Bumped by every show, update and hide. A timed hide from an earlier
# show_scroll checks it, so it cannot close a scroll that replaced it.
var _generation := 0
var _tween: Tween
# The image fades on its own tween so a text fade cannot stop it. Bumped by
# show, update and hide, so a stale reveal cannot fade in a replaced picture.
var _image_generation := 0
var _image_tween: Tween
# Kept so update_scroll can lay the paper out again for a new picture.
var _placement: Placement = Placement.RIGHT

# The picture has finished fading in. A scene picture can start moving then.
signal image_revealed

signal _fade_done

# As the paper opens, not when update_scroll swaps the words.
const OPEN_SOUND: AudioStream = preload("res://audio/sfx/scroll_open.wav")
# About half as loud as the recording. Every 6 dB lower is about half.
const OPEN_VOLUME_DB := -6.0
var _open_sound: AudioStreamPlayer

# A verse given by its key in Scriptures.TEXT is read aloud from
# VOICE_SPEAKER's clip for the key in the current language (Language.voice_path,
# made by tools/voice/generate.py) as its words show. Literal text, or a key with no clip yet, stays silent. Changing or
# closing the scroll waits for the reading to finish, so no verse is cut off.
const VOICE_SPEAKER := "narrator"
var _voice: AudioStreamPlayer
# Set from play until finished, so a pause (when the player stops reporting
# playing) is not taken for the end of the verse.
var _reading := false

func _ready() -> void:
	# Editor-only mockups of the other placements; toggle them in the scene tree.
	$Previews.queue_free()
	get_viewport().size_changed.connect(_on_screen_resized)
	visible = false
	paper.modulate.a = 0.0
	label.modulate.a = 0.0
	image.modulate.a = 0.0
	_open_sound = AudioStreamPlayer.new()
	_open_sound.stream = OPEN_SOUND
	_open_sound.volume_db = OPEN_VOLUME_DB
	_open_sound.bus = GameSettings.SFX
	add_child(_open_sound)
	_voice = AudioStreamPlayer.new()
	_voice.bus = GameSettings.VOICE
	_voice.add_to_group(GameSettings.VOICE_PLAYERS)
	_voice.finished.connect(func(): _reading = false)
	add_child(_voice)

# Leaving the world mid-verse (Main Menu from the pause menu) never lets the
# voice finish, so end the reading here. The bumped generations make a waiting
# show, update, hide or picture reveal stop instead of fading a scroll that is gone.
func _exit_tree() -> void:
	_reading = false
	_generation += 1
	_image_generation += 1

func is_showing() -> bool:
	return visible

# Returns once the verse being read has finished, or at once if none is.
func wait_for_voice() -> void:
	while _reading:
		await get_tree().process_frame

func _play_voice(key: String) -> void:
	_voice.stop()
	_reading = false
	if Scriptures.TEXT.has(key) and Language.has_voice(VOICE_SPEAKER, key):
		_voice.stream = Language.voice(VOICE_SPEAKER, key)
		_voice.play()
		_reading = true

# Fade the paper in, then the text. text may be a key in Scriptures.TEXT or the
# words themselves (BBCode allowed). duration counts from when the text is fully
# shown, and is stretched to the end of the verse's narration if that runs longer.
# With a duration, awaiting this returns after the scroll has faded out.
# With duration <= 0 it returns once the text is shown and stays until hide_scroll().
# With a picture, the text keeps to the top and the picture fades in below it
# image_delay seconds after the text is shown. On hide it fades out first.
# picture is a Texture2D, or a Control (such as an instanced scene) that fills
# the image area. The scroll takes ownership and frees it when it closes.
func show_scroll(text: String, placement: Placement = Placement.RIGHT, duration: float = 0.0, picture: Variant = null, image_delay: float = 1.0) -> void:
	_generation += 1
	var generation := _generation
	_image_generation += 1
	var image_generation := _image_generation

	if visible and paper.modulate.a > 0.0:
		# Already open somewhere. Close it first so the paper does not jump.
		await wait_for_voice()
		if generation != _generation:
			return
		await _fade(label, 0.0, text_fade_seconds)
		await _fade(paper, 0.0, paper_fade_seconds)
		if generation != _generation:
			return

	_stop_image_fade()
	_set_picture(picture)
	image.modulate.a = 0.0
	_placement = placement
	_layout(placement)
	_set_text(Scriptures.lookup(text))
	label.modulate.a = 0.0
	paper.modulate.a = 0.0
	visible = true

	_open_sound.play()
	await _fade(paper, 1.0, paper_fade_seconds)
	if generation != _generation:
		return
	_play_voice(text)
	await _fade(label, 1.0, text_fade_seconds)
	if picture != null:
		_reveal_image(image_delay, image_generation)

	if duration <= 0.0:
		return
	await get_tree().create_timer(duration, false).timeout
	if generation != _generation:
		return
	await hide_scroll()

# Swap the words on a scroll that is already open. The paper stays put.
# Any picture fades out first, then the words. A new picture, if given, fades
# in below the new words image_delay seconds after they show, as in show_scroll.
func update_scroll(text: String, picture: Variant = null, image_delay: float = 1.0) -> void:
	if not visible:
		push_warning("update_scroll called with no scroll showing")
		return
	_generation += 1
	var generation := _generation
	await wait_for_voice()
	if generation != _generation:
		return
	_image_generation += 1
	var image_generation := _image_generation
	_stop_image_fade()
	if image.visible:
		await _fade(image, 0.0, image_fade_out_seconds)
		if generation != _generation:
			return
	await _fade(label, 0.0, text_fade_seconds)
	if generation != _generation:
		return
	if image.visible or picture != null:
		_set_picture(picture)
		image.modulate.a = 0.0
		_layout(_placement)
	_set_text(Scriptures.lookup(text))
	_play_voice(text)
	await _fade(label, 1.0, text_fade_seconds)
	if picture != null and generation == _generation:
		_reveal_image(image_delay, image_generation)

# Once the verse has been read, fade the picture out, then the text, then the paper.
func hide_scroll() -> void:
	if not visible:
		return
	_generation += 1
	var generation := _generation
	await wait_for_voice()
	if generation != _generation:
		return
	# From wherever its fade-in reached.
	_image_generation += 1
	_stop_image_fade()
	if image.visible:
		await _fade(image, 0.0, image_fade_out_seconds)
		if generation != _generation:
			return
	await _fade(label, 0.0, text_fade_seconds)
	if generation != _generation:
		return
	await _fade(paper, 0.0, paper_fade_seconds)
	if generation != _generation:
		return
	visible = false
	_set_picture(null)

# One tween at a time. A new fade stops the old one where it stands, so a
# hide called mid fade-in starts from the current alpha. A killed tween never
# emits finished, so _fade_done also fires on a stop; otherwise whoever was
# awaiting the old fade (a chapter's play()) would never resume.
func _fade(item: CanvasItem, alpha: float, seconds: float) -> void:
	_stop_fade()
	if is_equal_approx(item.modulate.a, alpha):
		return
	_tween = create_tween()
	_tween.tween_property(item, "modulate:a", alpha, seconds)
	_tween.finished.connect(_stop_fade)
	await _fade_done

func _stop_fade() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
	_fade_done.emit()

func _reveal_image(delay: float, image_generation: int) -> void:
	await get_tree().create_timer(delay, false).timeout
	if image_generation != _image_generation:
		return
	_image_tween = create_tween()
	_image_tween.tween_property(image, "modulate:a", image_alpha, image_fade_seconds)
	await _image_tween.finished
	if image_generation == _image_generation:
		image_revealed.emit()

func _stop_image_fade() -> void:
	if _image_tween and _image_tween.is_valid():
		_image_tween.kill()
	_image_tween = null

func _set_picture(picture: Variant) -> void:
	for child in image.get_children():
		image.remove_child(child)
		child.queue_free()
	if picture is Texture2D:
		var rect := TextureRect.new()
		rect.texture = picture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture = rect
	if picture is Control:
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.add_child(picture)
	elif picture != null:
		push_warning("Scroll picture must be a Texture2D or a Control, got %s" % picture)

# The paper for placement on a screen of this size, in screen pixels. It is
# whole tiles, so a screen that is not leaves a sliver of under half a tile:
# the left and right scrolls keep to their edge, the rest center in it.
static func paper_rect(placement: Placement, screen: Vector2) -> Rect2:
	var cols := floori(screen.x / TILE)
	var rows := floori(screen.y / TILE)
	var tiles: Rect2i
	match placement:
		Placement.LEFT:
			tiles = Rect2i(0, 0, SIDE_TILES, rows)
		Placement.RIGHT:
			tiles = Rect2i(cols - SIDE_TILES, 0, SIDE_TILES, rows)
		Placement.BOTTOM:
			tiles = Rect2i(1, rows - BOTTOM_TILES, cols - 2, BOTTOM_TILES)
		_:
			tiles = Rect2i(0, 0, cols, rows)
	var spare := screen - Vector2(cols, rows) * TILE
	var shift := Vector2(spare.x / 2, spare.y / 2)
	if placement == Placement.LEFT:
		shift.x = 0
	elif placement == Placement.RIGHT:
		shift.x = spare.x
	return Rect2(Vector2(tiles.position * TILE) + shift, Vector2(tiles.size * TILE))

# The window changed shape with the scroll open, so lay it out again.
func _on_screen_resized() -> void:
	if visible:
		_layout(_placement)
		_set_text(label.text)

func _layout(placement: Placement) -> void:
	var screen_rect := paper_rect(placement, get_viewport().get_visible_rect().size)
	paper.position = screen_rect.position.round()
	paint_paper(paper, Rect2i(Vector2i.ZERO, Vector2i(screen_rect.size) / TILE))

	# Text and picture are under the paper, so in its own pixels.
	var px := Rect2(Vector2.ZERO, screen_rect.size)
	var inner := Rect2(px.position + Vector2(text_margin_left, text_margin_top),
		px.size - Vector2(text_margin_left + text_margin_right, text_margin_top + text_margin_bottom))
	label.position = inner.position
	label.size = inner.size
	image.visible = image.get_child_count() > 0
	if image.visible:
		var image_height := inner.size.y * image_share
		label.size.y -= image_height
		# Centred on the paper, so the wider right margin goes on both sides.
		var side := maxf(text_margin_left, text_margin_right)
		image.position = Vector2(px.position.x + side, inner.end.y - image_height)
		image.size = Vector2(px.size.x - side * 2, image_height)

# Fill rect (in tiles) of a layer using scripture_scroll_tile_set.tres with
# paper. Without rolled ends every row is the plain middle of the scroll, so
# the paper runs off the top and bottom of the screen (the crafting scroll).
static func paint_paper(layer: TileMapLayer, rect: Rect2i, rolled_ends: bool = true) -> void:
	layer.clear()
	var last := rect.end - Vector2i.ONE
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var ax := ATLAS_LEFT if x == rect.position.x else (ATLAS_RIGHT if x == last.x else ATLAS_MIDDLE)
			var ay := ATLAS_CENTER
			if rolled_ends:
				ay = ATLAS_TOP if y == rect.position.y else (ATLAS_BOTTOM if y == last.y else ATLAS_CENTER)
			layer.set_cell(Vector2i(x, y), 0, Vector2i(ax, ay))

# Largest font size whose wrapped text fits the label's box.
func _set_text(text: String) -> void:
	label.text = text
	var font_size := min_font_size
	for candidate in range(max_font_size, min_font_size - 1, -1):
		_apply_font_size(candidate)
		if label.get_content_height() <= label.size.y:
			font_size = candidate
			break
	_apply_font_size(font_size)

func _apply_font_size(font_size: int) -> void:
	for kind in ["normal", "bold", "italics", "bold_italics", "mono"]:
		label.add_theme_font_size_override(kind + "_font_size", font_size)
