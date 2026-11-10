extends Npc

class_name Bunny

# A wild bunny. It uses the same habits as the people and farm animals
# (Meander by default), but
# it only moves while a hop is in the air: between hops it sits still. While
# resting, its fidget turns it or plays the sniff and ear twitch.
# The node's position is where its feet touch the ground, so it y-sorts
# behind tree trunks like everyone else.

const SHEET := preload("res://characters/animals/farm_animals.png")
# Its cells in the farm animals sheet (64 px), packed there by
# tools/merge_bunny_into_farm_animals.py in the promised_land folder. One row
# per facing; per row, 4 hop frames (sit, push off, leap, land), then 4 idle
# frames (sit, then lowering the head with the ears going back). Each frame's
# ground spot (the middle of its shadow) is at GROUND in its cell. The leap
# frame's shadow is smaller and sits below the feet, so the bunny reads as off
# the ground.
const CELL := 64
const ORIGIN := Vector2i(4, 8)
const ROWS := {"down": 0, "up": 1, "right": 2, "left": 3}
const GROUND := Vector2(32, 56)
const IDLE_SEQUENCE := [4, 5, 6, 7, 6, 7, 6, 5, 4]
# The bunny is off the ground from the push-off frame until the end of the
# landing frame, as a fraction of the whole hop animation.
const AIR_START := 0.25
const AIR_END := 1.0

@export_group("Bunny")
## Meander radius in tiles, around where it was placed.
@export var wander_radius: float = 8.0
## Pixels covered by one hop.
@export var hop_distance: float = 14.0
## Frames per second of the hop animation; lower makes slower, floatier hops.
@export var hop_fps: float = 10.0
## Seconds sat still between hops on a walk. Each is a random time in this range.
@export var hop_gap_min: float = 0.05
@export var hop_gap_max: float = 0.3
@export var idle_fps: float = 6.0
## Chance a fidget turns the bunny 90 degrees. Checked before the twitch.
@export_range(0.0, 1.0, 0.05) var turn_chance: float = 0.3
## Chance a fidget plays the sniff and ear twitch.
@export_range(0.0, 1.0, 0.05) var twitch_chance: float = 0.6

@onready var _sprite: AnimatedSprite2D = $Sprite

var _hopping := false
var _hop_dir := Vector2.ZERO
var _hop_eased := 0.0
var _hop_gap := 0.0
var _twitching := false


func _init() -> void:
	pause_min = 1.0
	pause_max = 5.0
	pauses_for_dialogue = false
	# Hops are its own movement; it does not steer around walkers.
	avoidance = false


func _ready() -> void:
	super()
	# Player.use() looks for this group for snuggle_bunny.
	add_to_group("bunnies")
	_build_frames()
	if not FACINGS.has(facing):
		facing = FACINGS.pick_random()
	_show_rest()
	_sprite.animation_finished.connect(_on_animation_finished)
	set_habit(Meander.new(wander_radius))


func _build_frames() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for direction: String in ROWS:
		var textures: Array[AtlasTexture] = []
		for column in 8:
			var tex := AtlasTexture.new()
			tex.atlas = SHEET
			tex.region = Rect2(Vector2(ORIGIN + Vector2i(column, ROWS[direction])) * CELL, Vector2(CELL, CELL))
			textures.append(tex)

		var hop := "hop_" + direction
		frames.add_animation(hop)
		frames.set_animation_loop(hop, false)
		frames.set_animation_speed(hop, hop_fps)
		for i in 4:
			frames.add_frame(hop, textures[i])

		var idle := "idle_" + direction
		frames.add_animation(idle)
		frames.set_animation_loop(idle, false)
		frames.set_animation_speed(idle, idle_fps)
		for i: int in IDLE_SEQUENCE:
			frames.add_frame(idle, textures[i])
	_sprite.sprite_frames = frames
	_sprite.centered = false
	_sprite.offset = -GROUND


# Replaces npc.gd's, which drives an AnimationTree and walks at a steady pace.
# The habit and walk bookkeeping are the same; only the movement differs.
func _physics_process(delta: float) -> void:
	velocity = Vector2.ZERO
	if immovable:
		if is_walking():
			_stop_walk(false)
		return
	if habit != null and not _held and not _dialogue_paused:
		habit.tick(delta)
	_update_walk(delta)

	if _hopping:
		_move_hop(delta)
	elif input_vector != Vector2.ZERO:
		_hop_gap -= delta
		if _hop_gap <= 0.0:
			_start_hop()
	elif not _twitching:
		_show_rest()


func _start_hop() -> void:
	_twitching = false
	_hopping = true
	_hop_dir = input_vector.normalized()
	_hop_eased = 0.0
	_sprite.play("hop_" + facing_for(_hop_dir))


# Movement follows where the hop animation is, so the bunny only travels
# while airborne: it eases out of the push-off, is fastest on the stretched
# frame, and settles as it lands.
func _move_hop(delta: float) -> void:
	var count := _sprite.sprite_frames.get_frame_count(_sprite.animation)
	var t := (_sprite.frame + _sprite.frame_progress) / float(count)
	var u := clampf(inverse_lerp(AIR_START, AIR_END, t), 0.0, 1.0)
	var eased := (1.0 - cos(u * PI)) / 2.0
	var step := (eased - _hop_eased) * hop_distance
	_hop_eased = eased

	# Steer with the walk, and don't sail past its end, or the walk would
	# turn around and hop back over the spot.
	if input_vector != Vector2.ZERO:
		_hop_dir = input_vector.normalized()
		if is_walking():
			step = minf(step, position.distance_to(_walk.target))
	if step <= 0.0:
		return
	velocity = _hop_dir * step / delta
	move_and_slide()


func _on_animation_finished() -> void:
	if _hopping:
		_hopping = false
		_hop_gap = randf_range(minf(hop_gap_min, hop_gap_max), maxf(hop_gap_min, hop_gap_max))
		_show_rest()
	elif _twitching:
		_twitching = false
		_show_rest()


func fidget() -> void:
	if _hopping:
		return
	if not FACINGS.has(facing):
		facing = "down"
	var roll := randf()
	if roll < turn_chance:
		turn_quarter()
		_show_rest()
	elif roll < turn_chance + twitch_chance:
		_twitching = true
		_sprite.play("idle_" + facing)


# Sitting pose: the first hop frame, held still. Mid-walk facing is cleared,
# so it faces the way it last hopped.
func _show_rest() -> void:
	var direction := facing
	if not FACINGS.has(direction):
		direction = facing_for(_hop_dir) if _hop_dir != Vector2.ZERO else "down"
	var anim := "hop_" + direction
	if _sprite.animation == anim and _sprite.frame == 0 and not _sprite.is_playing():
		return
	_sprite.animation = anim
	_sprite.frame = 0
	_sprite.stop()
