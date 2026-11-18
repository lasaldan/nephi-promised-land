extends StoryChapter

# The opening, after Bountiful's: older Nephi tells how the family left
# Jerusalem while they walk out of its gate, then how they came to Bountiful
# and built the ship while it sails away from Bountiful's shore with all of
# them on deck, as Bountiful's ending showed it. Then the title, with
# 1 Nephi 18:8 on the scroll, and black into ship_at_sea.
#
# Jerusalem is this chapter's own Set (Chapters/Jerusalem, the gate from
# Bountiful's map). The sailing shot borrows the ShipAtSea Set's ship, moved
# for the shot onto the Coast Set (Chapters/Coast, Bountiful's shore).

const DIALOGUE := preload("res://story/main.dialogue")
const JERUSALEM_LINES := "intro_jerusalem"
const BOUNTIFUL_LINES := "intro_bountiful"
const SHIP_SET := "ship_at_sea"
const TITLE_VERSE := "1_nephi_18_8"

# The narration panel, as in Bountiful: older Nephi's lines are read by the
# narrator from voice/narrator/<ID>.mp3 (tools/voice/generate.py) and shown
# in a dark rounded panel floating over the right of the screen.
const SUBTITLE_FONT := preload("res://ui/fonts/OverlockRegular.ttf")
# Wide enough that the longest line wraps to 11 lines at size 16.
const SUBTITLE_WIDTH := 176.0
# Gap between the panel and the screen edges, and between it and the words.
const SUBTITLE_INSET := 8.0
const SUBTITLE_PADDING := 10.0
const SUBTITLE_FONT_SIZE := 16
# Smallest size a long line (or a long translation) may shrink to so it stays
# inside the padding instead of running to the panel's bottom edge.
const SUBTITLE_MIN_FONT_SIZE := 11
# Seconds per word to show a line whose clip has not been made yet.
const FALLBACK_WORD_SECONDS := 0.4
var subtitles: CanvasLayer
var subtitleLabel: Label

# The title shot: the logo in the space left of the verse scroll, styled like
# the main menu's. TITLE_SUBTITLE goes between two rules under the logo, as
# "Nephi Builds a Ship" did in Bountiful; empty leaves that row out.
const TITLE_LOGO := preload("res://ui/menu_title.png")
const TITLE_FONT := preload("res://ui/fonts/OverlockBold.ttf")
const TITLE_LOGO_WIDTH := 260.0
const TITLE_SUBTITLE := ""
const TITLE_SUBTITLE_SIZE := 16
const TITLE_TAGLINE := "An Interactive Story from\nThe Book of Mormon"
const TITLE_TAGLINE_SIZE := 14
const TITLE_CREAM := Color(1, 0.97, 0.9)
const TITLE_BROWN := Color(0.23, 0.13, 0.06)
const TITLE_Z_INDEX := 10
const TITLE_BACKDROP_SIZE := Vector2(4096, 4096)
# Above Jerusalem's gate, where nothing is drawn. The backdrop covers it anyway.
const TITLE_CAMERA := Vector2(-59.5, -69)
var titleCard: Node2D

# Leaving Jerusalem: the guards at the gate, and the family walking out of it
# and down the road, as in Bountiful.
const JERUSALEM_CAMERA := Vector2(-59.5, -56)
var jerusalem = [
	{"name": "guard_left", "start": Vector2(-62.7, -57.5), "move": Vector2(0,0)},
	{"name": "guard_right", "start": Vector2(-58.2, -57.5), "move": Vector2(0,0)},
	{"name": "lehi", "start": Vector2(-60.75, -58), "move": Vector2(0,1)},
	{"name": "sister_1", "start": Vector2(-59.95, -63.1), "move": Vector2(0,1)},
	{"name": "sariah", "start": Vector2(-60, -58.5), "move": Vector2(0,1), "delay": 0.15},
	{"name": "laman", "start": Vector2(-61, -59), "move": Vector2(0,1), "delay": 0.25},
	{"name": "chicken", "start": Vector2(-60.35, -61.25), "move": Vector2(0,1)},
	{"name": "sister_2", "start": Vector2(-60.5, -63.6), "move": Vector2(0,1)},
	{"name": "lemuel", "start": Vector2(-60, -59.5), "move": Vector2(0,1), "delay": 0.15},
	{"name": "sheep", "start": Vector2(-60.75, -60), "move": Vector2(0,1)},
	{"name": "chicken", "start": Vector2(-60.25, -62.25), "move": Vector2(0,1)},
	{"name": "sheep", "start": Vector2(-60.65, -61), "move": Vector2(0,1), "delay": 0.25},
	{"name": "goat", "start": Vector2(-60, -60.5), "move": Vector2(0,1)},
	{"name": "goat", "start": Vector2(-61, -64), "move": Vector2(0,1)},
	{"name": "chicken", "start": Vector2(-61, -62), "move": Vector2(0,1)},
	{"name": "sam", "start": Vector2(-60.85, -61), "move": Vector2(0,1)},
	{"name": "nephi", "start": Vector2(-61, -63), "move": Vector2(0,1)},
]

# Sailing away: everyone on the upper deck, in the ship's tiles (the Ship
# node sits at the origin). Nephi is the player, the rest are spawned and
# ride the swell with the deck (ShipSway.carry). The hatch is at x 5-8 and
# the grate at x 10-11 on rows 3-4; the stern steps start at x 14.
const SHIP_NEPHI := Vector2(3.5, 3.6)
var ship = [
	{"name": "lehi", "start": Vector2(2.3, 3.0), "facing": "left"},
	{"name": "sariah", "start": Vector2(2.4, 4.3), "facing": "left"},
	{"name": "jacob", "start": Vector2(3.4, 4.8), "facing": "left"},
	{"name": "joseph", "start": Vector2(4.2, 5.0), "facing": "up"},
	{"name": "sam", "start": Vector2(4.4, 2.6), "facing": "left"},
	{"name": "sister_1", "start": Vector2(5.6, 5.1), "facing": "up"},
	{"name": "sister_2", "start": Vector2(6.6, 5.1), "facing": "left"},
	{"name": "zoram", "start": Vector2(8.8, 2.6), "facing": "left"},
	{"name": "ishmael_wife", "start": Vector2(8.6, 5.0), "facing": "left"},
	{"name": "ishmael_daughter_1", "start": Vector2(9.6, 5.1), "facing": "left"},
	{"name": "ishmael_daughter_2", "start": Vector2(10.6, 5.1), "facing": "up"},
	{"name": "laman", "start": Vector2(12.4, 2.7), "facing": "down"},
	{"name": "lemuel", "start": Vector2(13.1, 3.4), "facing": "left"},
	{"name": "ishmael_daughter_3", "start": Vector2(12.6, 4.6), "facing": "up"},
	{"name": "ishmael_son_2", "start": Vector2(13.4, 5.0), "facing": "left"},
	{"name": "ishmael_daughter_4", "start": Vector2(11.8, 5.2), "facing": "right"},
	{"name": "ishmael_daughter_5", "start": Vector2(9.8, 2.6), "facing": "down"},
	# At the helm on the raised stern, where 1 Nephi 18:12 finds him later.
	{"name": "ishmael_son_1", "start": Vector2(16.0, 2.8), "facing": "left"},
]

# The ship leaves the shore of Bountiful as Bountiful's ending showed it. The
# shore is the Coast Set (world/coast/coast.tscn, Chapters/Coast, copied from
# Bountiful's map), shown beside the ship for this shot only. Its tiles are
# numbered as Bountiful's were, so these are Bountiful's own numbers.
const COAST_SET := "intro_coast"
# Where the ship rides off the beach, in the Coast's tiles: where it was built.
const COAST_SHIP := Vector2(12, 12)
# Bountiful's framing, in the Coast's tiles: the box around the whole ship
# with 1.5 tiles spare, zoomed out until it fits the screen. The camera then
# shifts so the ship is centered in the space left of the panel.
const COAST_VIEW := Rect2(2.5, -0.5, 29, 23)
# As in Bountiful: a moment at rest, then off to the west and a little
# south, slowly at first as the wind takes the sails.
const SAIL_DELAY := 2.5
const SAIL_OFFSET := Vector2(-24, 4)
const SAIL_SECONDS := 14.0
# Longer than any reading could run on past SAIL_SECONDS; the fade cuts it off.
const SAIL_CRUISE_SECONDS := 60.0
# The waves on the shore, faded in and out with the screen.
const WAVES_LEVEL := 0.5
# Where ShipAtSea keeps the ship, for putting it back.
var shipHome := Vector2.ZERO

func _init() -> void:
	id = "intro"
	title = "Intro"
	starts_after = ""
	ends_on = END_ON_CUTSCENE

func preview_spawns() -> Array[Dictionary]:
	return previewCharacters(jerusalem)

func setup(w):
	super(w)
	disablePlayerControls()
	await delay(1)
	await spawnCharacters(jerusalem)

func play():
	startCutsceneAt(JERUSALEM_CAMERA, false, true)
	await delay(1.0)

	_showSubtitles()
	await _narrateTitle(JERUSALEM_LINES)

	# Off the road and onto the ship at Bountiful's shore, behind black. The
	# panel stays up.
	await screenFade().fade_out()
	_clearJerusalem()
	await _boardShip()
	var waves := _shoreWaves()
	waves.level = 0.0
	world.create_tween().tween_property(waves, "level", WAVES_LEVEL, 1.0)
	screenFade().fade_in()
	await delay(1.0)

	var sail: Tween = world.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	sail.tween_interval(SAIL_DELAY)
	var under_way: Vector2 = world.ship.anchor + SAIL_OFFSET * 32
	sail.tween_property(world.ship, "anchor", under_way, SAIL_SECONDS)
	# Then on at the speed the easing ended with (a sine ease-in finishes at
	# PI/2 times its average speed) until the screen is black, however long
	# the reading runs, so on a wide screen it never stops in view.
	var cruise := SAIL_OFFSET * 32 * (PI / 2.0) / SAIL_SECONDS * SAIL_CRUISE_SECONDS
	sail.tween_property(world.ship, "anchor", under_way + cruise, SAIL_CRUISE_SECONDS).set_trans(Tween.TRANS_LINEAR)
	await _narrateTitle(BOUNTIFUL_LINES)

	_hideSubtitles()
	world.create_tween().tween_property(waves, "level", 0.0, 1.0)
	await screenFade().fade_out()
	sail.kill()
	_leaveShip()

	await delay(0.5)

	# The Promised Land title on the left, with the verse on a scroll at the right.
	var camera := world.get_node("Cutscene/Camera") as Camera2D
	camera.position = TITLE_CAMERA * 32
	_showTitleCard()
	screenFade().fade_in(5.0)

	await delay(1)

	# Held at least 8 seconds, longer if the reading runs on.
	await showScroll(TITLE_VERSE, ScriptureScroll.Placement.RIGHT, 8.0)

	await delay(.2)

	# Stay black into ship_at_sea. endCutscene() would fade back in on
	# Nephi's camera, showing the deck before that chapter fades in.
	await fadeOutCutsceneAndHold()
	titleCard.queue_free()

# Reads every line under a title in main.dialogue, one after another.
func _narrateTitle(dialogue_title: String) -> void:
	var line: DialogueLine = await DialogueManager.get_next_dialogue_line(DIALOGUE, dialogue_title)
	while line:
		await _narrate(line)
		await delay(0.5)
		# Stop at => END without asking, which would emit dialogue_ended to
		# listeners waiting on a real balloon.
		if line.next_id in [DMConstants.ID_END, DMConstants.ID_END_CONVERSATION, DMConstants.ID_NULL]:
			break
		line = await DialogueManager.get_next_dialogue_line(DIALOGUE, line.next_id)

# The family and their animals leave with the Jerusalem Set.
func _clearJerusalem() -> void:
	for character in spawnedCharacters:
		if is_instance_valid(character):
			character.get_parent().remove_child(character)
			character.queue_free()
	spawnedCharacters.clear()

# Shows the ship in place of Jerusalem, puts everyone on its upper deck, and
# moves it, with them, to the Coast, framed as Bountiful framed it. The
# open sea under ShipAtSea is hidden: this is the shore's own water.
func _boardShip() -> void:
	_chapters().activate_chapter(id, SHIP_SET)
	_coast().activate()
	_sea().visible = false
	var player := getPlayer()
	player.set_deck(ShipStairs.Deck.UPPER)
	player.position = SHIP_NEPHI * 32
	player.facing = "left"
	await spawnCharacters(ship)
	for character in spawnedCharacters:
		world.ship.carry.append(character)
	# The deck carries everyone aboard on the next physics frame.
	shipHome = world.ship.anchor
	world.ship.anchor = _coast().position + COAST_SHIP * 32
	await world.get_tree().physics_frame
	await world.get_tree().physics_frame

	var camera := world.get_node("Cutscene/Camera") as Camera2D
	var view := Rect2(_coast().position + COAST_VIEW.position * 32, COAST_VIEW.size * 32)
	var screen: Vector2 = world.get_viewport_rect().size
	var zoom := minf(screen.x / view.size.x, screen.y / view.size.y)
	camera.zoom = Vector2(zoom, zoom)
	# Half the panel's width to the right, in world pixels, so the ship sits
	# in the middle of what the panel leaves open.
	var panel := SUBTITLE_WIDTH + SUBTITLE_INSET
	camera.position = view.get_center() + Vector2(panel / 2.0 / zoom, 0)

# The ship back where ShipAtSea keeps it and the Coast gone, for the title
# and ship_at_sea after it. Nephi is put back on deck, as ship_at_sea
# expects to find him.
func _leaveShip() -> void:
	for character in spawnedCharacters:
		world.ship.carry.erase(character)
	world.ship.anchor = shipHome
	_chapters().deactivate_chapter(SHIP_SET)
	_coast().deactivate()
	_sea().visible = true
	getPlayer().position = SHIP_NEPHI * 32
	(world.get_node("Cutscene/Camera") as Camera2D).zoom = Vector2.ONE

func _coast() -> ChapterContent:
	return world.get_node("Chapters/Coast") as ChapterContent

func _sea() -> CanvasItem:
	return world.get_node("Chapters/ShipAtSea/ParallaxSea") as CanvasItem

func _shoreWaves() -> ShoreWaves:
	return _coast().get_node("ShoreWaves") as ShoreWaves

# Shows a line as a subtitle and reads it aloud, returning when the reading
# ends, or after a pause that fits its length when its clip has not been made.
func _narrate(line: DialogueLine) -> void:
	await _setSubtitle(line.text)
	if not Language.has_voice("narrator", line.translation_key):
		await delay(line.text.split(" ", false).size() * FALLBACK_WORD_SECONDS)
		return
	var narration := world.get_node("Ambience/Narration") as AudioStreamPlayer
	narration.stream = Language.voice("narrator", line.translation_key)
	narration.play()
	await narration.finished

# The see-through black panel floating down the right of the screen, with
# rounded corners and the words at its top.
func _showSubtitles() -> void:
	subtitles = CanvasLayer.new()
	# Over the screen fade (1) and the HUD, under dialogue balloons (100).
	subtitles.layer = 90
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.75)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -SUBTITLE_INSET - SUBTITLE_WIDTH
	panel.offset_right = -SUBTITLE_INSET
	panel.offset_top = SUBTITLE_INSET
	panel.offset_bottom = -SUBTITLE_INSET
	subtitleLabel = Label.new()
	subtitleLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	subtitleLabel.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	subtitleLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitleLabel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, SUBTITLE_PADDING)
	subtitleLabel.add_theme_font_override("font", SUBTITLE_FONT)
	subtitleLabel.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
	subtitleLabel.add_theme_color_override("font_color", Color.WHITE)
	subtitleLabel.modulate.a = 0.0
	panel.add_child(subtitleLabel)
	panel.modulate.a = 0.0
	subtitles.add_child(panel)
	world.add_child(subtitles)
	world.create_tween().tween_property(panel, "modulate:a", 1.0, 1.0)

# Fades the old words out and the new ones in, returning once they show.
func _setSubtitle(text: String) -> void:
	if subtitleLabel.modulate.a > 0.0:
		await world.create_tween().tween_property(subtitleLabel, "modulate:a", 0.0, 0.3).finished
	subtitleLabel.text = text
	_fitSubtitle()
	await world.create_tween().tween_property(subtitleLabel, "modulate:a", 1.0, 0.3).finished

# Shrinks the words until they end at least SUBTITLE_PADDING above the
# panel's bottom, matching the gap at the top.
func _fitSubtitle() -> void:
	var room: float = subtitleLabel.get_parent().size.y - SUBTITLE_PADDING * 2.0
	var size := SUBTITLE_FONT_SIZE
	while true:
		subtitleLabel.add_theme_font_size_override("font_size", size)
		var lines := subtitleLabel.get_line_count()
		var height := lines * subtitleLabel.get_line_height() \
			+ (lines - 1) * subtitleLabel.get_theme_constant("line_spacing")
		if height <= room or size <= SUBTITLE_MIN_FONT_SIZE:
			break
		size -= 1

# Fades out with the screen fade (1 second) and is gone once it is black.
func _hideSubtitles() -> void:
	var layer := subtitles
	var tween: Tween = world.create_tween()
	tween.tween_property(layer.get_child(0), "modulate:a", 0.0, 1.0)
	tween.tween_callback(layer.queue_free)
	subtitles = null
	subtitleLabel = null

# The logo with the subtitle and tagline under it, centered in the screen
# left of the right-hand scroll. It sits in the world under the cutscene
# camera, so the screen fade covers it.
func _showTitleCard() -> void:
	var camera := world.get_node("Cutscene/Camera") as Camera2D
	var screen: Vector2 = world.get_viewport().get_visible_rect().size
	var scroll := ScriptureScroll.paper_rect(ScriptureScroll.Placement.RIGHT, screen)
	var space := Rect2(Vector2.ZERO, Vector2(scroll.position.x, screen.y))
	titleCard = Node2D.new()
	titleCard.position = camera.position - screen / 2.0 + space.get_center()
	# Over the map, which would otherwise sort with it; the screen fade, a
	# CanvasLayer, still covers it.
	titleCard.z_index = TITLE_Z_INDEX
	world.get_node("Cutscene").add_child(titleCard)

	# Black behind the card, well past the widest and tallest screens, so
	# nothing around the title shot ever shows, whatever shape the window is.
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.size = TITLE_BACKDROP_SIZE
	backdrop.position = camera.position - titleCard.position - backdrop.size / 2.0
	titleCard.add_child(backdrop)

	var logo := Sprite2D.new()
	logo.texture = TITLE_LOGO
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var logo_scale := TITLE_LOGO_WIDTH / TITLE_LOGO.get_width()
	logo.scale = Vector2(logo_scale, logo_scale)
	var logo_height := TITLE_LOGO.get_height() * logo_scale
	titleCard.add_child(logo)

	var subtitle := HBoxContainer.new()
	subtitle.alignment = BoxContainer.ALIGNMENT_CENTER
	subtitle.add_theme_constant_override("separation", 8)
	if not TITLE_SUBTITLE.is_empty():
		var rule_style := StyleBoxFlat.new()
		rule_style.bg_color = Color(1, 0.945, 0.81)
		rule_style.set_border_width_all(1)
		rule_style.border_color = TITLE_BROWN
		var font := FontVariation.new()
		font.base_font = TITLE_FONT
		font.spacing_glyph = 2
		var text := Label.new()
		text.text = TITLE_SUBTITLE
		text.uppercase = true
		text.add_theme_font_override("font", font)
		text.add_theme_font_size_override("font_size", TITLE_SUBTITLE_SIZE)
		text.add_theme_color_override("font_color", TITLE_CREAM)
		text.add_theme_color_override("font_outline_color", TITLE_BROWN)
		text.add_theme_color_override("font_shadow_color", TITLE_BROWN)
		text.add_theme_constant_override("outline_size", 5)
		text.add_theme_constant_override("shadow_offset_x", 0)
		text.add_theme_constant_override("shadow_offset_y", 1)
		text.add_theme_constant_override("shadow_outline_size", 5)
		for i in 3:
			if i == 1:
				subtitle.add_child(text)
				continue
			var rule := Panel.new()
			rule.custom_minimum_size = Vector2(36, 5)
			rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rule.add_theme_stylebox_override("panel", rule_style)
			subtitle.add_child(rule)
	titleCard.add_child(subtitle)

	var tagline := Label.new()
	tagline.text = TITLE_TAGLINE
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_override("font", TITLE_FONT)
	tagline.add_theme_font_size_override("font_size", TITLE_TAGLINE_SIZE)
	tagline.add_theme_color_override("font_color", Color.WHITE)
	titleCard.add_child(tagline)

	# Logo, subtitle and tagline together, centered up and down in the space.
	var subtitle_height := subtitle.get_combined_minimum_size().y
	var tagline_height := tagline.get_combined_minimum_size().y
	var gap := 4.0 if subtitle_height > 0.0 else 0.0
	var tagline_gap := 10.0
	var top := -(logo_height + gap + subtitle_height + tagline_gap + tagline_height) / 2.0
	logo.position.y = top + logo_height / 2.0
	subtitle.position = Vector2(-space.size.x / 2.0, top + logo_height + gap)
	subtitle.size = Vector2(space.size.x, subtitle_height)
	tagline.position = Vector2(-space.size.x / 2.0, subtitle.position.y + subtitle_height + tagline_gap)
	tagline.size = Vector2(space.size.x, tagline_height)
