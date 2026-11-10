class_name Credits
extends Control

# The end of the game. On black,
# the closing card fades in and holds, then the credits roll up the screen,
# with some of the cast walking along between the sections, until the
# promised land from Nephi's vision (PROMISED_LAND) comes to rest in the
# middle, with TO_BE_CONTINUED below it. After END_HOLD it all fades out
# with MUSIC, and then the main menu fades up from black. A click, touch or
# key skips the card, and then the rest. MUSIC plays from the card on.
#
# To credit an asset, add it to a section of CREDITS below. Each is BBCode,
# so [b]...[/b], [i]...[/i] and [font_size=N]...[/font_size] work.
#
# Credits on the main menu opens this with full set: no closing card, and
# the character sprite credits in full (credits_lpc.gd) instead of
# LPC_SHORT, then back to the main menu.

# Set before changing to this scene for the full credits. Read once, in
# _ready, and cleared, so the end of the game always gets the short ones.
static var full := false

const NEXT_SCENE := "res://menus/main_menu.tscn"

# The character sprites, in the roll at the end of the game. Credits on the
# main menu lists every author instead (LPC_FULL).
const LPC_SHORT := """[font_size=22]Character Sprites[/font_size]
Universal LPC Spritesheet Character Generator
by many Liberated Pixel Cup artists.
Every one is named under Credits
on the main menu."""
const LPC_FULL_TITLE := """[font_size=22]Character Sprites[/font_size]
Universal LPC Spritesheet Character Generator
liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator"""
# Regenerate with tools/build_lpc_credits.py.
const LPC_FULL := preload("res://menus/credits_lpc.gd")
const LPC_FULL_FONT_SIZE := 12
# One of the background tracks from the game (BG_music in world.tscn).
const MUSIC: AudioStream = preload("res://audio/music/delicate_hymn.mp3")
const MUSIC_IN_SECONDS := 1.5
# Once the picture has rested, the roll and the music fade out together.
const MUSIC_OUT_SECONDS := 3.0
# The same, after a skip.
const MUSIC_OUT_SKIPPED_SECONDS := 1.0

const CLOSING := "This game tells only a small part of the account of Lehi and his family.\n\nThe full story, in Nephi's own words, is found in the Book of Mormon: Another Testament of Jesus Christ."

# The roll, top to bottom: sections of text, the character sprite credits
# ({"lpc": true}, see LPC_SHORT), and now and then a row of the cast, walking in place the way "walk" says (right, left, up or down), or
# for "pray", standing facing forward with hands folded.
# Each name is a character (Cast.scene()).
const CREDITS := [
	"[font_size=30]The Promised Land[/font_size]\n\nAn interactive story by Danimate\nDaniel Fuller",
	"""[font_size=22]Story[/font_size]
Scripture from 1 Nephi in
The Book of Mormon:
Another Testament of Jesus Christ

Dialogue by Daniel Fuller""",
	{"cast": ["lehi", "sariah", "sister_1", "sister_2", "jacob", "joseph"], "walk": "right"},
	"""[font_size=22]Art[/font_size]
Daniel Fuller
Icon art made with PixelLab
Illustrations made with Gemini""",
	"""[font_size=22]Environment Art[/font_size]
[i][lb]LPC] Food[/i], [i][lb]LPC] Goat[/i],
[i][lb]LPC] Birds[/i]
by bluecarrot16
CC-BY-SA 4.0 / CC-BY-SA 3.0 / GPL 3.0
opengameart.org/users/bluecarrot16
""",
	{"lpc": true},
	{"cast": ["zoram", "sam", "lemuel", "laman"], "walk": "left"},
	"""[font_size=22]Music[/font_size]
Composed with Suno""",
	"""[font_size=22]Sounds[/font_size]
Daniel Fuller
and freesound.org (CC0)""",
	"""[font_size=22]Narration[/font_size]
Written by Daniel Fuller
Generated with LuvVoice""",
	{"cast": ["ishmael_wife", "ishmael_son_1", "ishmael_son_2", "ishmael_daughter_1",
			"ishmael_daughter_2", "ishmael_daughter_3", "ishmael_daughter_4", "ishmael_daughter_5"], "walk": "right"},
	"""[font_size=22]Fonts[/font_size]
Overlock by Dario Manuel Muhafara
Lilita One by Juan Montoreano
SIL Open Font License""",
	"""[font_size=22]Software[/font_size]
Made with the Godot Engine
godotengine.org/license

Dialogue Manager by Nathan Hoad
MIT License

Code written by Daniel Fuller 
with input from Claude by Anthropic""",
	{"cast": ["chicken", "sheep", "goat"], "walk": "left"},
	"This game is an independent, fan-made work. It is not created, sponsored, endorsed, or approved by The Church of Jesus Christ of Latter-day Saints or any of its affiliates. The views and gameplay interpretations expressed are those of the developer alone. Scripture text is taken from the 1920 edition of the Book of Mormon, which is in the public domain.",
	"Thank you for playing.",
	{"cast": ["nephi"], "walk": "pray"},
]

# The last of the roll, which stops with the picture in the middle of the
# screen and TO_BE_CONTINUED just below it.
const PROMISED_LAND: Texture2D = preload("res://story/pictures/promised_land.jpeg")
# Share of the screen's height.
const PROMISED_LAND_HEIGHT := 0.45
const TO_BE_CONTINUED := "To be continued..."
const TO_BE_CONTINUED_GAP := 10
# Space above the picture, enough that the last of the roll is off the top
# of the screen by the time the picture stops.
const ENDING_GAP := SECTION_GAP * 3
# Seconds the picture rests in the middle before it all fades out.
const END_HOLD := 6.0

const FADE_TIME := 1.5
const CLOSING_HOLD := 8.0
# How fast the credits roll, in pixels a second. The full credits are long,
# so they go faster.
const ROLL_SPEED := 45.0
const ROLL_SPEED_FULL := 70.0
# Space between one part of the roll and the next.
const SECTION_GAP := 48
# A row of the cast: its height, with their feet near the bottom, and the
# space each one takes, wider for sheep and goats.
const CAST_ROW_HEIGHT := 56
const CAST_SPACING := 30.0
const CAST_SPACING_BIG := 46.0
const BIG_ANIMALS := ["sheep", "goat"]
# Input is ignored this long after the scene opens, so a press still held
# from the game does not skip the card.
const INPUT_GRACE := 1.0
const SIDE_MARGIN := 0.12
const TEXT_COLOR := Color(0.96, 0.91, 0.8)

var _card: Label
var _roll: VBoxContainer
var _tween: Tween
var _rolling := false
var _leaving := false
var _opened_at := 0.0
var _music := AudioStreamPlayer.new()
var _music_in: Tween
var _full := false

func _ready() -> void:
	_full = full
	full = false
	_opened_at = Time.get_ticks_msec() / 1000.0
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)

	_card = Label.new()
	_card.text = CLOSING
	_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_theme_font_size_override("font_size", 22)
	_card.add_theme_color_override("font_color", TEXT_COLOR)
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.anchor_left = SIDE_MARGIN
	_card.anchor_right = 1.0 - SIDE_MARGIN
	_card.modulate.a = 0.0
	add_child(_card)

	_roll = VBoxContainer.new()
	_roll.add_theme_constant_override("separation", SECTION_GAP)
	_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll.visible = false
	add_child(_roll)

	GameSettings.ensure_loaded()
	_music.stream = MUSIC
	_music.bus = GameSettings.MUSIC
	_music.volume_db = -80.0
	add_child(_music)
	_music.play()
	if _full:
		# The full roll can outlast the track.
		_music.finished.connect(_music.play)
	_music_in = create_tween()
	_music_in.tween_method(_set_music_level, 0.0, 1.0, MUSIC_IN_SECONDS)

	if _full:
		_tween = create_tween()
		_tween.tween_interval(0.5)
		_tween.tween_callback(_start_roll)
		return
	_tween = create_tween()
	_tween.tween_interval(0.5)
	_tween.tween_property(_card, "modulate:a", 1.0, FADE_TIME)
	_tween.tween_interval(CLOSING_HOLD)
	_tween.tween_property(_card, "modulate:a", 0.0, FADE_TIME)
	_tween.tween_callback(_start_roll)

func _start_roll() -> void:
	_rolling = true
	_card.visible = false
	var width := size.x * (1.0 - 2.0 * SIDE_MARGIN)
	for part in CREDITS:
		if part is Dictionary and part.has("lpc"):
			if _full:
				_roll.add_child(_text(LPC_FULL_TITLE))
				var list := _text(LPC_FULL.TEXT)
				list.add_theme_font_size_override("normal_font_size", LPC_FULL_FONT_SIZE)
				list.add_theme_font_size_override("bold_font_size", LPC_FULL_FONT_SIZE)
				_roll.add_child(list)
			else:
				_roll.add_child(_text(LPC_SHORT))
		elif part is Dictionary:
			_roll.add_child(_cast_row(part["cast"], part["walk"], width))
		else:
			_roll.add_child(_text(part))
	# ENDING_GAP in all, counting the gaps either side of the spacer.
	var spacer := Control.new()
	spacer.custom_minimum_size.y = ENDING_GAP - 2 * SECTION_GAP
	_roll.add_child(spacer)
	# The picture and the words under it, closer together than two sections.
	var ending := VBoxContainer.new()
	ending.add_theme_constant_override("separation", TO_BE_CONTINUED_GAP)
	var picture := TextureRect.new()
	picture.texture = PROMISED_LAND
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# A painting, not pixel art, so smoothed as it is shrunk.
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var picture_height := size.y * PROMISED_LAND_HEIGHT
	picture.custom_minimum_size = Vector2(picture_height * PROMISED_LAND.get_width() / PROMISED_LAND.get_height(), picture_height)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ending.add_child(picture)
	ending.add_child(_text(TO_BE_CONTINUED))
	_roll.add_child(ending)

	_roll.position = Vector2(size.x * SIDE_MARGIN, size.y)
	_roll.size = Vector2(width, 0)
	_roll.custom_minimum_size.x = width
	_roll.visible = true
	# fit_content sizes the labels, and the boxes lay them out, over the next
	# frames.
	for i in 3:
		await get_tree().process_frame
	if _leaving:
		return
	# Stops with the middle of the picture in the middle of the screen.
	var stop := size.y / 2.0 - (ending.position.y + picture.position.y + picture.size.y / 2.0)
	_tween = create_tween()
	_tween.tween_property(_roll, "position:y", stop, (size.y - stop) / (ROLL_SPEED_FULL if _full else ROLL_SPEED))
	_tween.tween_interval(END_HOLD)
	_tween.tween_callback(_go_to_menu.bind(MUSIC_OUT_SECONDS))

func _text(bbcode: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Each section is translated whole, under the context "credits"
	# (translations/es.po); names and links are kept as they are.
	label.text = "[center]%s[/center]" % tr(bbcode, "credits")
	label.add_theme_font_size_override("normal_font_size", 18)
	label.add_theme_color_override("default_color", TEXT_COLOR)
	return label

# Each of cast walking in place, side by side, centered in width. Only the
# sprite and its walk animations come from each scene; the rest of the Npc
# (its body, its AnimationTree) is left out.
func _cast_row(cast: Array, walk: String, width: float) -> Control:
	var row := Control.new()
	row.custom_minimum_size.y = CAST_ROW_HEIGHT
	var spans: Array[float] = []
	var total := 0.0
	for who in cast:
		var span := CAST_SPACING_BIG if who in BIG_ANIMALS else CAST_SPACING
		spans.append(span)
		total += span
	var x := (width - total) / 2.0
	for i in cast.size():
		var who: String = cast[i]
		var npc := Cast.scene(who).instantiate()
		var sprite := npc.get_node("Sprite2D") as Sprite2D
		var animation := npc.get_node("AnimationPlayer") as AnimationPlayer
		for part: Node in [sprite, animation]:
			npc.remove_child(part)
			part.owner = null
		npc.free()
		# Feet near the bottom of the row, on whole pixels.
		var figure := Node2D.new()
		figure.position = Vector2(x + spans[i] / 2.0, CAST_ROW_HEIGHT - 4).round()
		figure.add_child(sprite)
		# Its tracks (Sprite2D:frame) are from its parent, now figure.
		figure.add_child(animation)
		row.add_child(figure)
		if walk == "pray":
			# The last of the fold, as Npc.fold_hands() ends on.
			sprite.frame_coords = Vector2i(Prayer.FOLD_FRAMES - 1, Prayer.CAST_ROWS["down"])
		else:
			animation.play("walk_" + walk)
			# So they do not all step in time.
			animation.seek(randf() * animation.current_animation_length, true)
		x += spans[i]
	return row

func _input(event: InputEvent) -> void:
	var pressed := (event is InputEventMouseButton or event is InputEventKey \
			or event is InputEventScreenTouch) and event.is_pressed()
	if not pressed or _leaving:
		return
	if Time.get_ticks_msec() / 1000.0 - _opened_at < INPUT_GRACE:
		return
	get_viewport().set_input_as_handled()
	if _rolling:
		_go_to_menu(MUSIC_OUT_SKIPPED_SECONDS)
	else:
		_tween.kill()
		_tween = create_tween()
		_tween.tween_property(_card, "modulate:a", 0.0, FADE_TIME * 0.5 * _card.modulate.a)
		_tween.tween_callback(_start_roll)

# The roll and MUSIC fade out together over seconds, then the main menu.
func _go_to_menu(seconds: float) -> void:
	_leaving = true
	# Skipped through fast enough, it may still be fading in.
	_music_in.kill()
	_tween.kill()
	_tween = create_tween().set_parallel()
	_tween.tween_method(_set_music_level, db_to_linear(_music.volume_db), 0.0, seconds)
	_tween.tween_property(_roll, "modulate:a", 0.0, seconds)
	_tween.chain().tween_callback(get_tree().change_scene_to_file.bind(NEXT_SCENE))

func _set_music_level(level: float) -> void:
	# linear_to_db(0) is -inf.
	_music.volume_db = maxf(linear_to_db(level), -80.0)
