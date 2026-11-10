@tool
class_name FlyingBird
extends Node2D
## A bird that flies a large, slightly wobbly loop around this node's position
## and calls out now and then. Place the node at the center of the loop; the
## loop is drawn in the editor so it's easy to tweak.
##
## type picks the bird. Every bird in flying_animals.png that shares the same
## layout is here: a 3x4 block of 32-pixel cells (three wing positions, one row
## per direction), with the same bird perched in the block just below it. The
## bats and butterflies on the sheet are laid out differently and are not.
## Names are best guesses from the pictures; rename freely, but the order is
## saved in scenes, so add new ones at the end.

enum Type {
	BLUE_JAY, HAWK, ROBIN, WHITE_DOVE, FINCH, EAGLE, CARDINAL, SPARROW, WREN,
	BLUEBIRD, BLACKBIRD, GULL, DOVE, RED_KITE, ORIOLE,
}

const SHEET := preload("res://world/wildlife/flying_animals.png")
const FRAME := 32
# Top-left cell (column, row) of each type's flying block. Its perched block
# is PERCHED_OFFSET below.
const SHEET_ORIGIN := {
	Type.BLUE_JAY: Vector2i(0, 0),
	Type.HAWK: Vector2i(3, 0),
	Type.ROBIN: Vector2i(6, 0),
	Type.WHITE_DOVE: Vector2i(9, 0),
	Type.FINCH: Vector2i(12, 0),
	Type.EAGLE: Vector2i(15, 0),
	Type.CARDINAL: Vector2i(18, 0),
	Type.SPARROW: Vector2i(21, 0),
	Type.WREN: Vector2i(24, 0),
	Type.BLUEBIRD: Vector2i(27, 0),
	Type.BLACKBIRD: Vector2i(0, 8),
	Type.GULL: Vector2i(3, 8),
	Type.DOVE: Vector2i(6, 8),
	Type.RED_KITE: Vector2i(9, 8),
	Type.ORIOLE: Vector2i(12, 8),
}
const PERCHED_OFFSET := Vector2i(0, 4)
# Big birds cry, small ones chirp. call_sound overrides it for one bird.
const BIG_CALL := preload("res://audio/animals/osprey.ogg")
const SONG := preload("res://audio/animals/long_chirp.ogg")
const CHIRP := preload("res://audio/animals/chirp.ogg")
const CALLS := {
	Type.HAWK: BIG_CALL, Type.EAGLE: BIG_CALL, Type.RED_KITE: BIG_CALL, Type.GULL: BIG_CALL,
	Type.BLUEBIRD: SONG, Type.BLUE_JAY: SONG, Type.ROBIN: SONG, Type.ORIOLE: SONG, Type.CARDINAL: SONG,
}
# Sheet rows, top to bottom.
const DIRECTIONS := ["left", "up", "down", "right"]

@export var type: Type = Type.HAWK:
	set(v):
		type = v
		if is_node_ready():
			_build_frames()
## Its call. Empty uses the one for its type.
@export var call_sound: AudioStream
@export var radius := Vector2(1500, 900):
	set(v):
		radius = v
		queue_redraw()
## How far the path drifts off a perfect ellipse.
@export var wobble := 120.0:
	set(v):
		wobble = v
		queue_redraw()
## Pixels per second.
@export var speed := 70.0
@export var clockwise := true
## Where on the loop the bird starts, in degrees.
@export_range(0, 360) var start_angle := 0.0:
	set(v):
		start_angle = v
		_seed = deg_to_rad(v) * 1.7
		queue_redraw()
@export var call_interval_min := 6.0
@export var call_interval_max := 18.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _voice: AudioStreamPlayer2D = $Sprite/Voice

var _t := 0.0
# Varies the wobble per bird; derived from start_angle so the editor preview matches.
var _seed := 0.0
var _call_timer := 0.0


func _ready() -> void:
	_build_frames()
	_t = deg_to_rad(start_angle)
	_sprite.position = _path(_t)
	_call_timer = randf_range(call_interval_min, call_interval_max)
	if not Engine.is_editor_hint():
		_sprite.play("left")
		_sprite.frame = randi() % 4


func _build_frames() -> void:
	var origin: Vector2i = SHEET_ORIGIN[type]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for row in DIRECTIONS.size():
		var anim: String = DIRECTIONS[row]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, 8.0)
		# Ping-pong the three wing positions for a smooth flap.
		for col in [0, 1, 2, 1]:
			var tex := AtlasTexture.new()
			tex.atlas = SHEET
			tex.region = Rect2(Vector2((origin + Vector2i(col, row)) * FRAME), Vector2(FRAME, FRAME))
			frames.add_frame(anim, tex)
	_sprite.sprite_frames = frames
	_sprite.animation = "left"
	_voice.stream = call_sound if call_sound else CALLS.get(type, CHIRP)


func _path(t: float) -> Vector2:
	var p := Vector2(cos(t) * radius.x, sin(t) * radius.y)
	p += Vector2(sin(3.0 * t + _seed), cos(2.0 * t + _seed)) * wobble
	return p


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Step along the loop at a constant pixel speed regardless of curvature.
	# Screen y points down, so increasing t runs clockwise.
	var dir := 1.0 if clockwise else -1.0
	var tangent := (_path(_t + 0.001) - _path(_t)) / 0.001
	_t = wrapf(_t + dir * speed * delta / maxf(tangent.length(), 1.0), 0.0, TAU)

	var prev := _sprite.position
	_sprite.position = _path(_t)
	_face(_sprite.position - prev)

	_call_timer -= delta
	if _call_timer <= 0.0:
		_call_timer = randf_range(call_interval_min, call_interval_max)
		_voice.pitch_scale = randf_range(0.92, 1.08)
		_voice.play()


func _face(velocity: Vector2) -> void:
	if velocity.is_zero_approx():
		return
	# A little hysteresis so the bird doesn't flicker between facings on diagonals.
	var horizontal := _sprite.animation in [&"left", &"right"]
	var ratio := absf(velocity.x) / maxf(absf(velocity.y), 0.0001)
	if horizontal and ratio < 0.7:
		horizontal = false
	elif not horizontal and ratio > 1.4:
		horizontal = true
	var anim: String
	if horizontal:
		anim = "right" if velocity.x > 0.0 else "left"
	else:
		anim = "down" if velocity.y > 0.0 else "up"
	if anim != _sprite.animation:
		var frame := _sprite.frame
		_sprite.play(anim)
		_sprite.frame = frame


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var points := PackedVector2Array()
	for i in 97:
		points.append(_path(TAU * i / 96.0))
	draw_polyline(points, Color(1, 1, 1, 0.35), 2.0)
	draw_circle(_path(deg_to_rad(start_angle)), 6.0, Color(1, 0.8, 0.2, 0.8))
