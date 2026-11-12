@tool
class_name Rain
extends Node2D

# Rain over the world. The world has one of these (world.rain). Like the fog,
# each part is a Parallax2D that repeats around the camera, so the rain covers
# wherever the camera goes without being as big as the map:
#   - Splashes: little rings opening on the ground, which stay where they
#     landed as the camera moves (world/weather/rain_splash.gdshader). Give
#     it splash_surfaces (the ground, a ship's deck) and they only land on
#     those layers' tiles, drawn just after each layer's own tiles, so
#     everyone walking on it, and every wall or prop drawn over it, covers
#     them. With no surfaces they land anywhere, over everything.
#   - Far streaks: small, faint and slower, riding with the ground.
#   - Near streaks: longer, brighter and faster, sliding past a little faster
#     than the ground as if nearer the camera.
#   - Close streaks: long and fast, just past the camera. Only in a storm.
# The streaks stay in front of everyone: rain falls between them and the camera.
# The streaks are pixel lines drawn once into a small texture, slanted with
# the wind, and the layer's autoscroll makes them fall. intensity shows more
# or fewer of them (world/weather/rain.gdshader), so nothing is redrawn as the
# rain builds, only when the wind changes.
#
# It sits on the world's canvas, so the DayNight tints it, and campfires light
# the drops near them. Heavy rain also dims the light itself (darken, through
# DayNight.overcast). The sound is two loops layered: light rain on its own,
# soft at first and full by steady rain, then heavy rain joining it from
# there, until both play full in a storm. Past steady rain a howling wind
# rises too, so only a real storm has it.
#
# Lightning: with lightning_every set, a storm strikes now and then at random,
# some close and blinding, some far and faint. Each lights the whole world
# (DayNight.flash) with a flicker, and thunder, if set, follows after a
# delay: soon and loud for a close strike, late and soft for a far one.
# strike() makes one happen on cue, rain or not.
#
# Chapters use the StoryChapter helpers (rainStarts(), rainStops(),
# setRain()); like the fog, the rain outlasts the chapter and is saved with
# each one.
#   await rain.fade_to(0.8, 5.0)
#   rain.wind = -60.0    # blowing hard to the west
#   rain.lightning_every = 8.0
#   await rain.strike()  # right on cue

const GROUP := "rain"
const STREAK_SHADER := preload("res://world/weather/rain.gdshader")
const SPLASH_SHADER := preload("res://world/weather/rain_splash.gdshader")

## 0 is dry, 0.5 steady rain, 1 a storm. Nothing is drawn at 0.
@export_range(0.0, 1.0, 0.01) var intensity := 0.0:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		_apply()
## World pixels per second the wind pushes the rain sideways. Negative blows
## west. The streaks lean to match.
@export_range(-200.0, 200.0, 1.0) var wind := 20.0:
	set(value):
		wind = value
		_draw_streaks()
		_apply()
## World pixels per second the near drops fall. The far ones fall slower.
@export_range(50.0, 1000.0, 10.0) var fall_speed := 380.0:
	set(value):
		fall_speed = value
		_draw_streaks()
		_apply()
## The drops' color in daylight, alpha included. DayNight tints it from there.
@export var color := Color(0.78, 0.84, 0.95, 0.55):
	set(value):
		color = value
		_apply()
## How much a storm dims the light. Drizzle barely does. 0 never dims.
@export_range(0.0, 1.0, 0.01) var darken := 0.7:
	set(value):
		darken = value
		_apply()
@export_group("Splashes")
## How many rings open on the ground in a downpour. 0 turns them off.
@export_range(0.0, 1.0, 0.01) var splashes := 0.35:
	set(value):
		splashes = value
		_apply()
@export var splash_color := Color(0.82, 0.88, 0.97, 0.6):
	set(value):
		splash_color = value
		_apply()
## Where splashes may land: only on tiles of these layers (the ground, a ship's
## deck, the sea, flat roofs). The rings draw just after each layer's tiles,
## so whatever draws over the layer covers them. Use flat layers with y-sort
## off. Empty lets them land anywhere, drawn over everything.
@export var splash_surfaces: Array[TileMapLayer] = []:
	set(value):
		splash_surfaces = value
		_mask_dirty = true
		_apply()
@export_group("Lightning")
## Seconds between strikes, on average, while it rains. 0 is no lightning.
@export_range(0.0, 120.0, 0.5) var lightning_every := 0.0:
	set(value):
		lightning_every = maxf(value, 0.0)
		_until_strike = _strike_gap()
## A thunderclap, played after each strike. Close strikes are louder.
@export var thunder: AudioStream
## How loud the closest thunder is.
@export var thunder_volume_db := 0.0
@export_group("Sound")
## The patter of light rain, from the first drops. Played as a loop.
@export var light_sound: AudioStream = preload("res://audio/ambience/rain_light_loop.ogg")
## The roar of heavy rain, layered over the light from steady rain up.
@export var heavy_sound: AudioStream = preload("res://audio/ambience/rain_heavy_loop.ogg")
## A storm's wind, rising from steady rain to full in a storm. Played as a loop.
@export var wind_sound: AudioStream = preload("res://audio/ambience/storm_wind_loop.ogg")
## How loud each layer is at its fullest.
@export var sound_volume_db := -4.0:
	set(value):
		sound_volume_db = value
		_apply()
## How much quieter the rain and thunder are while fully sheltered.
@export var sheltered_volume_db := -6.0:
	set(value):
		sheltered_volume_db = value
		_apply()

## How far under cover he is, 0 to 1 (below a ship's deck; world/props/
## ship_stairs.gd fades it with the upper deck). The streaks and splashes fade
## out as it rises and the sound drops toward sheltered_volume_db; at 1 none
## is drawn, and no lightning flashes. The rain itself carries on, so coming
## out finds it as it was. Overcast still dims the light.
var shelter := 0.0:
	set(value):
		shelter = clampf(value, 0.0, 1.0)
		# A flash already going would light the hold.
		if shelter > 0.0 and _flash_tween:
			_flash_tween.kill()
			if is_instance_valid(_day_night):
				_day_night.flash = 0.0
		_apply()

# The layers of streaks, far first. size: texture px (drawn at 1:1, as pixel
# art). count: streaks in the texture, all shown at intensity 1. length: px,
# shortest and longest. speed: of fall_speed. share: of color's alpha.
# scroll: with the camera. from: the intensity the layer starts at.
const LAYERS := [
	{"name": "Far", "seed": 3, "size": 256, "count": 340, "length": Vector2i(3, 6), "speed": 0.6, "share": 0.5, "scroll": 1.0, "from": 0.0},
	{"name": "Near", "seed": 7, "size": 256, "count": 170, "length": Vector2i(8, 13), "speed": 1.0, "share": 1.0, "scroll": 1.2, "from": 0.0},
	{"name": "Close", "seed": 13, "size": 256, "count": 36, "length": Vector2i(18, 28), "speed": 1.6, "share": 0.75, "scroll": 1.5, "from": 0.6},
]
# Where each sound layer starts and is full, in intensity. Light is full by
# steady rain; heavy comes in from just below that and is full in a storm.
const LIGHT_SOUND_FULL := 0.55
const HEAVY_SOUND_FROM := 0.4
# The wind is a gale, wrong for any lesser rain: silent until steady rain.
const WIND_SOUND_FROM := 0.5
# Streaks shown grow faster than intensity near the top, so 0.5 is steady
# rain and only the last stretch up to 1 turns into a storm.
const STORM_CURVE := 1.6
# World px per splash cell. See rain_splash.gdshader.
const SPLASH_CELL := 16
# World px per pixel of a surface's mask, and the most pixels it may have
# across (a bigger layer gets a coarser mask). Tile edges fall on whole mask
# pixels while tiles are a multiple of this.
const MASK_SCALE := 4
const MASK_MAX := 2048

# Used while there are no splash_surfaces: splashes anywhere, over everything.
var _splash_layer: Parallax2D
var _splash_material: ShaderMaterial
# 1 px of white, which every splash sprite stretches (see rain_splash.gdshader).
var _white: ImageTexture
# Used instead while there are splash_surfaces: a sprite on each surface
# layer, masked to its tiles. Layer instance id: {sprite, material, area}.
var _surface_splashes := {}
var _mask_dirty := true
var _layers: Array[Parallax2D] = []
var _sprites: Array[Sprite2D] = []
var _materials: Array[ShaderMaterial] = []
var _light_player: AudioStreamPlayer
var _heavy_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _day_night: DayNight
var _tween: Tween
var _flash_tween: Tween
var _until_strike := 0.0

func _ready() -> void:
	add_to_group(GROUP)
	_add_splashes()
	for spec in LAYERS:
		_add_layer(spec)
	_draw_streaks()
	if not Engine.is_editor_hint():
		_light_player = _loop_player("LightRain", light_sound)
		_heavy_player = _loop_player("HeavyRain", heavy_sound)
		_wind_player = _loop_player("StormWind", wind_sound)
	# DayNight comes before this in the world, so it is ready by now.
	_day_night = get_tree().get_first_node_in_group(DayNight.GROUP) as DayNight
	_apply()

func _exit_tree() -> void:
	# Don't leave the world dimmed by rain that is gone.
	if is_instance_valid(_day_night):
		_day_night.overcast = 0.0
		_day_night.flash = 0.0
	# Nor splashes on the surfaces, which are other nodes' children.
	_clear_surface_splashes()
	_mask_dirty = true

func _loop_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	# The loops are cut to repeat seamlessly; make sure they do repeat,
	# whatever their import settings say.
	if stream and "loop" in stream:
		stream.loop = true
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.bus = GameSettings.SFX
	add_child(player, false, Node.INTERNAL_MODE_FRONT)
	return player

# Get heavier or lighter to target over seconds. 0 seconds switches at once.
func fade_to(target: float, seconds := 5.0) -> void:
	if _tween:
		_tween.kill()
	if seconds <= 0.0:
		intensity = target
		return
	_tween = create_tween()
	_tween.tween_property(self, "intensity", clampf(target, 0.0, 1.0), seconds) \
			.set_trans(Tween.TRANS_SINE)
	await _tween.finished

# Lightning: the world flickers bright, then thunder follows. strength is how
# close it is, 0 to 1: brighter, and the thunder sooner and louder. Waits
# for the flash (under a second), not the thunder, so a cutscene can carry
# on as it rolls. With Reduce flashing on in Settings, it only glows softly.
func strike(strength := 1.0) -> void:
	strength = clampf(strength, 0.0, 1.0)
	if thunder and not Engine.is_editor_hint():
		_thunder_after(lerpf(2.5, 0.25, strength), strength)
	# Below decks there is no sky to light up, only the thunder.
	if _day_night == null or shelter > 0.0:
		return
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	if GameSettings.is_reducing_flashing():
		# Reduce flashing (Settings): one soft glow up and down, never a
		# flicker, and never more than a quarter as bright.
		_flash_tween.tween_property(_day_night, "flash", 0.25 * strength, 0.35) \
				.set_trans(Tween.TRANS_SINE)
		_flash_tween.tween_property(_day_night, "flash", 0.0, 0.9) \
				.set_trans(Tween.TRANS_SINE)
		await _flash_tween.finished
		return
	var flash := func(to: float, seconds: float) -> void:
		_flash_tween.tween_property(_day_night, "flash", to * strength, seconds)
	# A first flash, a flicker, a second, then fading off.
	flash.call(1.0, 0.04)
	flash.call(0.2, 0.07)
	if randf() < 0.7:
		flash.call(0.8, 0.05)
		flash.call(0.3, 0.08)
	_flash_tween.tween_property(_day_night, "flash", 0.0, 0.6) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	await _flash_tween.finished

func _thunder_after(seconds: float, strength: float) -> void:
	await get_tree().create_timer(seconds).timeout
	# One player each, so thunder can roll over thunder.
	var player := AudioStreamPlayer.new()
	player.stream = thunder
	player.bus = GameSettings.SFX
	player.volume_db = thunder_volume_db + linear_to_db(lerpf(0.35, 1.0, strength)) \
			+ sheltered_volume_db * shelter
	player.finished.connect(player.queue_free)
	add_child(player, false, Node.INTERNAL_MODE_FRONT)
	player.play()

# Seconds until the next strike: around lightning_every, never on a beat.
func _strike_gap() -> float:
	return lightning_every * randf_range(0.4, 1.6)

func _add_splashes() -> void:
	_splash_material = ShaderMaterial.new()
	_splash_material.shader = SPLASH_SHADER
	# The tile must be wider than the screen, or the layer leaves a strip
	# uncovered (as the fog once did), and a whole number of cells, so the
	# rings repeat with it.
	var cells := ceili(_view_size() / SPLASH_CELL) + 2
	var tile := cells * SPLASH_CELL
	_splash_material.set_shader_parameter("cell", float(SPLASH_CELL))
	_splash_material.set_shader_parameter("cells", float(cells))

	var image := Image.create(1, 1, false, Image.FORMAT_L8)
	image.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(image)
	var sprite := _splash_sprite(_splash_material)
	sprite.region_rect = Rect2(0, 0, tile, tile)

	_splash_layer = Parallax2D.new()
	_splash_layer.name = "Splashes"
	_splash_layer.repeat_size = Vector2.ONE * tile
	_splash_layer.repeat_times = 2
	_splash_layer.add_child(sprite)
	# Internal, so the editor preview is never saved into the scene.
	add_child(_splash_layer, false, Node.INTERNAL_MODE_FRONT)

# The white pixel stretched by the region, so the shader's UV is world px.
func _splash_sprite(material: ShaderMaterial) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _white
	sprite.material = material
	sprite.centered = false
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	return sprite

func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and lightning_every > 0.0 and intensity > 0.0:
		_until_strike -= delta
		if _until_strike <= 0.0:
			_until_strike = _strike_gap()
			# Mostly far off, now and then right overhead.
			strike(lerpf(0.3, 1.0, randf() ** 2.0))
	# Rebuilt when the list changes or a layer is painted (its changed
	# signal). Checked only while splashes show, so dry weather costs nothing.
	if _mask_dirty and _splashing() and not splash_surfaces.is_empty():
		_build_masks()
		_apply()

func _splashing() -> bool:
	return intensity > 0.0 and splashes > 0.0

func _mark_mask_dirty() -> void:
	_mask_dirty = true

func _clear_surface_splashes() -> void:
	for entry in _surface_splashes.values():
		if is_instance_valid(entry.sprite):
			entry.sprite.queue_free()
	_surface_splashes.clear()

# Gives each surface layer a splash sprite of its own, as its child, covering
# its tiles, with a mask of which of its pixels are tiles (white) or not.
# Being the layer's child it moves, shows and hides with the layer, and draws
# right after its tiles. Even the sea, scrolling in its Parallax2D, keeps its
# rings with no rebuilding.
func _build_masks() -> void:
	_mask_dirty = false
	var wanted := {}
	for layer in splash_surfaces:
		if is_instance_valid(layer):
			wanted[layer.get_instance_id()] = layer
	for id in _surface_splashes.keys():
		if not wanted.has(id):
			var old: Dictionary = _surface_splashes[id]
			if is_instance_valid(old.sprite):
				old.sprite.queue_free()
			_surface_splashes.erase(id)
	for id in wanted:
		var layer: TileMapLayer = wanted[id]
		if not layer.changed.is_connected(_mark_mask_dirty):
			layer.changed.connect(_mark_mask_dirty)
		if not _surface_splashes.has(id):
			var material := ShaderMaterial.new()
			material.shader = SPLASH_SHADER
			material.set_shader_parameter("cell", float(SPLASH_CELL))
			material.set_shader_parameter("cells", 1024.0)
			material.set_shader_parameter("use_mask", true)
			var sprite := _splash_sprite(material)
			sprite.name = "RainSplashes"
			# Last among the layer's children, so after its tiles.
			layer.add_child(sprite, false, Node.INTERNAL_MODE_BACK)
			_surface_splashes[id] = {"sprite": sprite, "material": material, "area": false}
		_build_mask(layer, _surface_splashes[id])

func _build_mask(layer: TileMapLayer, entry: Dictionary) -> void:
	var rects := _tile_rects(layer)
	entry.area = not rects.is_empty()
	if not entry.area:
		return
	var bounds: Rect2 = rects[0]
	for rect in rects:
		bounds = bounds.merge(rect)
	var scale := float(MASK_SCALE)
	while maxf(bounds.size.x, bounds.size.y) / scale > MASK_MAX:
		scale *= 2.0
	var origin := (bounds.position / scale).floor() * scale
	var size := Vector2i(((bounds.end - origin) / scale).ceil())
	var image := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	for rect in rects:
		var start := ((rect.position - origin) / scale).floor()
		var end := ((rect.end - origin) / scale).ceil()
		image.fill_rect(Rect2i(Vector2i(start), Vector2i(end - start)), Color.WHITE)
	var cover := Vector2(size) * scale
	var sprite: Sprite2D = entry.sprite
	sprite.position = origin
	sprite.region_rect = Rect2(Vector2.ZERO, cover)
	var material: ShaderMaterial = entry.material
	material.set_shader_parameter("surface_mask", ImageTexture.create_from_image(image))
	material.set_shader_parameter("mask_size", cover)

# Each used tile of the layer, as a rect in the layer's own px.
static func _tile_rects(layer: TileMapLayer) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if layer.tile_set == null:
		return rects
	var size := Vector2(layer.tile_set.tile_size)
	for cell in layer.get_used_cells():
		rects.append(Rect2(layer.map_to_local(cell) - size / 2.0, size))
	return rects

func _add_layer(spec: Dictionary) -> void:
	var material := ShaderMaterial.new()
	material.shader = STREAK_SHADER
	_materials.append(material)

	var sprite := Sprite2D.new()
	sprite.material = material
	sprite.centered = false
	# Crisp pixels like the tiles, and wrapping so the region can hold copies.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# As with the fog: one texture is narrower than the screen, so the sprite
	# draws a square of copies of it, wider than the screen.
	var size: int = spec.size
	var copies := maxi(2, ceili(_view_size() / size) + 1)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, size * copies, size * copies)
	_sprites.append(sprite)

	var layer := Parallax2D.new()
	layer.name = spec.name
	layer.repeat_size = Vector2.ONE * size * copies
	# Spare copies around the screen, for a camera that zooms out.
	layer.repeat_times = 2
	layer.scroll_scale = Vector2.ONE * float(spec.scroll)
	layer.add_child(sprite)
	_layers.append(layer)
	add_child(layer, false, Node.INTERNAL_MODE_FRONT)

# The longer side of the viewport, in px.
func _view_size() -> float:
	return maxf(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))

# Redraws each layer's streaks, leaning along the way the drops now fall.
func _draw_streaks() -> void:
	var slant := Vector2(wind, fall_speed).normalized()
	for i in _sprites.size():
		var spec: Dictionary = LAYERS[i]
		_sprites[i].texture = _streaks(spec, slant)

func _apply() -> void:
	for i in _layers.size():
		var spec: Dictionary = LAYERS[i]
		var layer := _layers[i]
		layer.autoscroll = Vector2(wind, fall_speed) * float(spec.speed)
		var material := _materials[i]
		var tint := color
		tint.a *= float(spec.share)
		material.set_shader_parameter("rain_color", tint)
		var from: float = spec.from
		var amount := pow(clampf((intensity - from) / (1.0 - from), 0.0, 1.0), STORM_CURVE)
		material.set_shader_parameter("amount", amount)
		# Dry air, or a layer the rain isn't heavy enough for yet, costs
		# nothing to draw. Nor does rain falling on the deck overhead.
		layer.visible = amount > 0.0 and shelter < 1.0
		layer.modulate.a = 1.0 - shelter
	var splash_amount := intensity * splashes
	if _splash_layer:
		_splash_layer.visible = _splashing() and splash_surfaces.is_empty() and shelter < 1.0
		_splash_layer.modulate.a = 1.0 - shelter
		_splash_material.set_shader_parameter("splash_color", splash_color)
		_splash_material.set_shader_parameter("amount", splash_amount)
	for entry in _surface_splashes.values():
		if not is_instance_valid(entry.sprite):
			continue
		entry.sprite.visible = _splashing() and entry.area and shelter < 1.0
		entry.sprite.modulate.a = 1.0 - shelter
		entry.material.set_shader_parameter("splash_color", splash_color)
		entry.material.set_shader_parameter("amount", splash_amount)
	# Squared, so drizzle hardly dims and a downpour does.
	if _day_night:
		_day_night.overcast = darken * intensity * intensity
	# Light: soft at the first drops, full by steady rain. Heavy: silent
	# until then, easing in to full in a storm.
	_set_layer(_light_player, clampf(intensity / LIGHT_SOUND_FULL, 0.0, 1.0))
	_set_layer(_heavy_player, smoothstep(HEAVY_SOUND_FROM, 1.0, intensity))
	_set_layer(_wind_player, smoothstep(WIND_SOUND_FROM, 1.0, intensity))

# gain is 0 to 1, as amplitude; 0 stops the player.
func _set_layer(player: AudioStreamPlayer, gain: float) -> void:
	if player == null or player.stream == null:
		return
	if gain <= 0.0:
		player.stop()
		return
	player.volume_db = sound_volume_db + linear_to_db(gain) \
			+ sheltered_volume_db * shelter
	if not player.playing:
		player.play()

# A square texture of pixel streaks that tiles exactly (each one wraps off an
# edge onto the opposite one). Red: brightness, a faint tail up to a bright
# head. Green: the streak's rank, 0 to 1, which the shader compares with the
# intensity. Ranks go evenly up the list and the streaks are placed at
# random, so any intensity shows an even scatter.
static func _streaks(spec: Dictionary, slant: Vector2) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = spec.seed
	var size: int = spec.size
	var count: int = spec.count
	var shortest: int = spec.length.x
	var longest: int = spec.length.y
	var bytes := PackedByteArray()
	bytes.resize(size * size * 2)
	for n in count:
		var rank := int((n + 0.5) / count * 255.0)
		var tail := Vector2(rng.randf() * size, rng.randf() * size)
		var length := rng.randi_range(shortest, longest)
		for step in length:
			var at := tail + slant * step
			var x := posmod(int(at.x), size)
			var y := posmod(int(at.y), size)
			var i := (y * size + x) * 2
			var bright := int(lerpf(0.3, 1.0, float(step) / maxf(length - 1, 1)) * 255.0)
			# Where two cross, the brighter one wins the pixel.
			if bright > bytes[i]:
				bytes[i] = bright
				bytes[i + 1] = rank
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RG8, bytes)
	return ImageTexture.create_from_image(image)
