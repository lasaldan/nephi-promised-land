@tool
class_name Fog
extends Node2D

# Drifting banks of fog over the world. The world has one of these (world.fog).
# It is two layers of lumpy cloud made from a small seamless noise texture,
# each a Parallax2D that repeats it around the camera, so the fog covers
# wherever the camera goes without being as big as the map:
#   - Far rides with the ground (scroll 1.0): walk past a patch and it stays
#     where it was, like fog sitting in the valley.
#   - Near is thinner and slides past a little faster than the ground
#     (scroll 1.25), as if it hung between the ground and the camera.
# Both drift on the wind, and their edges churn so banks thicken, thin and
# break apart as they go (world/weather/fog.gdshader).
#
# It sits on the world's canvas, so the DayNight tints it: grey-blue at night,
# pink at dawn. Campfires light the fog near them.
#
# Chapters use the StoryChapter helpers (fogRollsIn(), fogLifts(), setFog());
# like the hour, the fog outlasts the chapter and is saved with each one.
#   await fog.fade_to(0.7, 6.0)
#   fog.wind = Vector2(40, 0)    # at sea: the ship sails west through it

const GROUP := "fog"
const SHADER := preload("res://world/weather/fog.gdshader")

## 0 is clear air, 1 is thick fog. Nothing is drawn at 0.
@export_range(0.0, 1.0, 0.01) var density := 0.0:
	set(value):
		density = clampf(value, 0.0, 1.0)
		_apply()
## The fog's color in daylight. DayNight tints it from there.
@export var color := Color(0.92, 0.94, 0.97):
	set(value):
		color = value
		_apply()
## World pixels per second the fog drifts. The near layer goes a little faster.
@export var wind := Vector2(-8.0, 3.0):
	set(value):
		wind = value
		_apply()
## Higher leaves smaller, separate banks with clear air between them. Lower
## joins them into one blanket.
@export_range(0.0, 1.0, 0.01) var patchiness := 0.42:
	set(value):
		patchiness = value
		_apply()
## How far under cover he is, 0 to 1 (below a ship's deck; world/props/
## ship_stairs.gd fades it with the upper deck). The fog fades out as it
## rises and is not drawn at 1, though it keeps its density for when he
## comes out.
var shelter := 0.0:
	set(value):
		shelter = clampf(value, 0.0, 1.0)
		_apply()

@export_group("Depth")
## How the far layer moves with the camera. 1 stays with the ground.
@export var far_scroll := 1.0:
	set(value):
		far_scroll = value
		_apply()
## How the near layer moves with the camera. Above 1 passes faster than the
## ground, as if nearer the camera.
@export var near_scroll := 1.25:
	set(value):
		near_scroll = value
		_apply()

# Both layers share one noise texture. The near one reads it turned on its
# side and shifted (transpose, offset), and at another size, so the two never
# line up. stretch: world px per texture px. share: of density. wind: of wind.
const LAYERS := [
	{"name": "Far", "stretch": 4.0, "transpose": false, "offset": Vector2.ZERO, "share": 1.0, "wind": 1.0, "phase": 0.0},
	{"name": "Near", "stretch": 3.0, "transpose": true, "offset": Vector2(0.37, 0.61), "share": 0.55, "wind": 1.6, "phase": 2.5},
]

# The noise texture, in texture px. Small and stretched is cheap and keeps it soft.
const NOISE_SIZE := 128
# Banks across the texture at the coarsest octave; each finer octave doubles it.
const NOISE_PERIOD := 3
const NOISE_OCTAVES := 4
const NOISE_SEED := 11

# Made once and kept, so reloading the world (or the editor) doesn't redo it.
static var _noise_texture: ImageTexture

var _layers: Array[Parallax2D] = []
var _materials: Array[ShaderMaterial] = []
var _tween: Tween

func _ready() -> void:
	add_to_group(GROUP)
	for spec in LAYERS:
		_add_layer(spec)
	_apply()

# Thicken or thin to target over seconds. 0 seconds switches at once.
func fade_to(target: float, seconds := 5.0) -> void:
	if _tween:
		_tween.kill()
	if seconds <= 0.0:
		density = target
		return
	_tween = create_tween()
	_tween.tween_property(self, "density", clampf(target, 0.0, 1.0), seconds) \
			.set_trans(Tween.TRANS_SINE)
	await _tween.finished

func _add_layer(spec: Dictionary) -> void:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("phase", spec.phase)
	material.set_shader_parameter("swap_axes", spec.transpose)
	material.set_shader_parameter("offset", spec.offset)
	_materials.append(material)

	var sprite := Sprite2D.new()
	sprite.texture = _noise()
	sprite.material = material
	sprite.centered = false
	sprite.scale = Vector2.ONE * spec.stretch
	# Soft, not pixelated like the tiles, and wrapping for the shader's churn.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# Parallax2D only covers the screen when what it repeats is bigger than
	# the screen. One stretched texture can be narrower (the near one is 384
	# px against a 512 px viewport), which left a hard edge on the right where
	# that layer ran out. So the sprite draws a square of copies of the
	# texture (the region wraps, and the noise tiles), wider than the screen.
	var tile: float = NOISE_SIZE * spec.stretch
	var copies := _copies_to_cover(tile)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, NOISE_SIZE * copies, NOISE_SIZE * copies)

	var layer := Parallax2D.new()
	layer.name = spec.name
	layer.repeat_size = Vector2.ONE * tile * copies
	# Spare copies around the screen, for a camera that zooms out.
	layer.repeat_times = 2
	layer.add_child(sprite)
	_layers.append(layer)
	# Internal, so the editor preview is never saved into the scene.
	add_child(layer, false, Node.INTERNAL_MODE_FRONT)

# How many textures across a square must be to stay wider than the viewport,
# with one to spare for drift and camera motion.
func _copies_to_cover(tile: float) -> int:
	var view := Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	return maxi(2, ceili(maxf(view.x, view.y) / tile) + 1)

func _apply() -> void:
	for i in _layers.size():
		var spec: Dictionary = LAYERS[i]
		var layer := _layers[i]
		# Clear air costs nothing to draw.
		layer.visible = density > 0.0 and shelter < 1.0
		layer.modulate.a = 1.0 - shelter
		layer.autoscroll = wind * float(spec.wind)
		layer.scroll_scale = Vector2.ONE * (far_scroll if i == 0 else near_scroll)
		var material := _materials[i]
		material.set_shader_parameter("fog_color", color)
		material.set_shader_parameter("density", density * float(spec.share))
		material.set_shader_parameter("threshold", patchiness)

# Fractal gradient noise that tiles exactly. NoiseTexture2D's seamless option
# only blends a strip of each edge into the other, which leaves a flat,
# low-contrast band there that the shader's threshold turns into a hard line.
# Here each octave's grid of random gradients wraps around instead (the cell
# past the last is the first), so the right edge runs straight on into the
# left and the bottom into the top, with full contrast everywhere.
static func _noise() -> ImageTexture:
	if _noise_texture:
		return _noise_texture
	var rng := RandomNumberGenerator.new()
	rng.seed = NOISE_SEED
	var size := NOISE_SIZE
	var values := PackedFloat32Array()
	values.resize(size * size)
	var period := NOISE_PERIOD
	var amplitude := 1.0
	for _octave in NOISE_OCTAVES:
		var gradients := PackedVector2Array()
		gradients.resize(period * period)
		for i in gradients.size():
			gradients[i] = Vector2.from_angle(rng.randf() * TAU)
		for y in size:
			var fy := float(y) * period / size
			var y0 := int(fy)
			var ty := fy - y0
			var sy := ty * ty * ty * (ty * (ty * 6.0 - 15.0) + 10.0)
			var row0 := y0 * period
			var row1 := ((y0 + 1) % period) * period
			for x in size:
				var fx := float(x) * period / size
				var x0 := int(fx)
				var tx := fx - x0
				var sx := tx * tx * tx * (tx * (tx * 6.0 - 15.0) + 10.0)
				var x1 := (x0 + 1) % period
				var g00 := gradients[row0 + x0]
				var g10 := gradients[row0 + x1]
				var g01 := gradients[row1 + x0]
				var g11 := gradients[row1 + x1]
				var top := lerpf(g00.x * tx + g00.y * ty, g10.x * (tx - 1.0) + g10.y * ty, sx)
				var bottom := lerpf(g01.x * tx + g01.y * (ty - 1.0), g11.x * (tx - 1.0) + g11.y * (ty - 1.0), sx)
				values[y * size + x] += lerpf(top, bottom, sy) * amplitude
		period *= 2
		amplitude *= 0.5
	# Stretched to the full 0 to 1, like NoiseTexture2D's normalize.
	var low := INF
	var high := -INF
	for v in values:
		low = minf(low, v)
		high = maxf(high, v)
	var bytes := PackedByteArray()
	bytes.resize(values.size())
	for i in values.size():
		bytes[i] = int(remap(values[i], low, high, 0.0, 255.0))
	var image := Image.create_from_data(size, size, false, Image.FORMAT_L8, bytes)
	_noise_texture = ImageTexture.create_from_image(image)
	return _noise_texture
