@tool
class_name Butterfly
extends Node2D
## A butterfly that flits erratically around where it was placed. The node's
## position is the spot on the ground beneath it (used for y-sorting), and the
## sprite floats about head height above that, so it passes behind trees but
## over grass and shrubs. The roaming area is drawn in the editor.

enum Species { WHITE, BLUE }

const SHEET := preload("res://world/wildlife/flying_animals.png")
const FRAME := 32
# Top-left cell (column, row) of each species' 4-frame row in the sheet.
const SHEET_ORIGIN := {
	Species.WHITE: Vector2i(22, 8),
	Species.BLUE: Vector2i(22, 9),
}

@export var species: Species = Species.BLUE:
	set(v):
		species = v
		if is_node_ready():
			_build_frames()
## How far from its starting spot the butterfly wanders before turning back.
@export var roam_radius := 220.0:
	set(v):
		roam_radius = v
		queue_redraw()
## Height of the sprite above its ground spot, in pixels.
@export var height := 40.0
@export var speed_min := 25.0
@export var speed_max := 60.0

@onready var _sprite: AnimatedSprite2D = $Sprite

var _home := Vector2.ZERO
var _heading := 0.0
var _turn_rate := 0.0
var _speed := 40.0
var _flit_timer := 0.0
var _t := 0.0


func _ready() -> void:
	_build_frames()
	_sprite.position.y = -height
	if Engine.is_editor_hint():
		return
	add_to_group("butterflies")
	_home = position
	_heading = randf() * TAU
	_t = randf() * 100.0
	_sprite.frame = randi() % 4
	_sprite.play("default")
	_new_flit()


func _build_frames() -> void:
	var origin: Vector2i = SHEET_ORIGIN[species]
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", 11.0)
	for col in 4:
		var tex := AtlasTexture.new()
		tex.atlas = SHEET
		tex.region = Rect2(Vector2((origin + Vector2i(col, 0)) * FRAME), Vector2(FRAME, FRAME))
		frames.add_frame("default", tex)
	_sprite.sprite_frames = frames


# Each flit is a short burst with its own speed and curve, which gives the
# jittery, unpredictable path butterflies have.
func _new_flit() -> void:
	_flit_timer = randf_range(0.25, 1.0)
	_speed = randf_range(speed_min, speed_max)
	_turn_rate = randf_range(-4.0, 4.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_t += delta
	_flit_timer -= delta
	if _flit_timer <= 0.0:
		_new_flit()

	# Drift back toward home harder the further out it strays.
	var to_home := _home - position
	var stray := to_home.length() / roam_radius
	if stray > 0.6:
		var diff := angle_difference(_heading, to_home.angle())
		_turn_rate += signf(diff) * stray * 6.0 * delta

	_heading = wrapf(_heading + _turn_rate * delta, -PI, PI)
	position += Vector2.from_angle(_heading) * _speed * delta

	# Bob up and down while flying, with a faster flutter on top.
	_sprite.position.y = -height + sin(_t * 2.3) * 6.0 + sin(_t * 9.0) * 1.5

	# The sprites face up, so rotate them to point along the heading.
	_sprite.rotation = lerp_angle(_sprite.rotation, _heading + PI / 2.0, minf(delta * 8.0, 1.0))


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_arc(Vector2.ZERO, roam_radius, 0.0, TAU, 64, Color(1, 1, 1, 0.35), 2.0)
	draw_circle(Vector2.ZERO, 4.0, Color(0.4, 0.7, 1, 0.8))
