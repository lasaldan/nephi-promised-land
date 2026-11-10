extends Npc

class_name FarmAnimal

# Farm animals (chicken, goat, sheep, and whatever joins them in
# farm_animals.png) use the same habits as people. Their fidget() turns or
# grazes instead of only looking around, so an Idle animal stays planted and
# a Meander animal grazes between walks. With no habit from the chapter they
# get Idle, unless they were spawned walking (the road in chapter 0).
# Each animal scene owns eat_up, eat_left, eat_down, and eat_right. The tree
# keeps stand and walk, and is switched off while an eat clip plays.

@export_group("Grazing")
## Chance a fidget turns the animal 90 degrees. Checked before the graze.
@export_range(0.0, 1.0, 0.05) var turn_chance: float = 0.5
## Chance a fidget plays one graze. Ignored when the turn roll already hit.
@export_range(0.0, 1.0, 0.05) var eat_chance: float = 0.35

# Each animal calls now and then, heard only when Nephi is within reach of it.
# Keyed by Cast.name_of(). The same sound, at full volume, is its
# voice line when he talks to it (voice/<name>/<ID>.mp3).
const CALLS := {
	"chicken": {"sound": preload("res://audio/animals/chicken.ogg"), "tiles": 2.0},
	"goat": {"sound": preload("res://audio/animals/goat.ogg"), "tiles": 3.0},
	"sheep": {"sound": preload("res://audio/animals/sheep.ogg"), "tiles": 3.0},
}
# Loudest a call gets, right next to the animal. It fades to silence at the
# edge of its reach.
const CALL_VOLUME := 0.5

@export_group("Calls")
## Seconds between one call and the next. Each wait is a random time in this range.
@export var call_interval_min: float = 7.0
@export var call_interval_max: float = 14.0

@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _call: AudioStreamPlayer2D
var _call_reach := 0.0
var _call_timer := 0.0
var _eating: bool = false
# Decided on the first physics frame, after the chapter has set facing, input and habit.
var _role_checked: bool = false


func _init() -> void:
	# Slower to fidget than people, and they keep grazing through dialogue.
	pause_min = 2.5
	pause_max = 5.0
	pauses_for_dialogue = false


func _ready() -> void:
	super()
	# _ready runs from add_child, before the spawner assigns facing. The tree
	# stays active (Godot's default) and the first physics frame points it.
	animation_player.animation_finished.connect(_on_animation_finished)
	var sound: Dictionary = CALLS.get(Cast.name_of(self), {})
	if not sound.is_empty():
		_call_reach = sound.tiles * TILE
		_call = AudioStreamPlayer2D.new()
		_call.stream = sound.sound
		_call.bus = GameSettings.SFX
		_call.volume_db = linear_to_db(CALL_VOLUME)
		_call.max_distance = _call_reach
		_call.attenuation = 1.0
		add_child(_call)
		# Spread out, so a flock doesn't start calling all at once.
		_call_timer = randf_range(0.0, call_interval_max)


func _process(delta: float) -> void:
	if _call == null:
		return
	_call_timer -= delta
	if _call_timer > 0.0:
		return
	_call_timer = randf_range(call_interval_min, call_interval_max)
	if _call.playing or is_vanished() or not is_visible_in_tree():
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or player.global_position.distance_to(global_position) > _call_reach:
		return
	# Quiet while Nephi talks to anyone, so a call never covers a voice line.
	var small_talk := player.get_node_or_null("../SmallTalk") as SmallTalk
	if small_talk and small_talk.talking:
		return
	_call.pitch_scale = randf_range(0.95, 1.05)
	_call.play()


func _physics_process(delta: float) -> void:
	if not _role_checked:
		_role_checked = true
		# A move order with no facing means this animal should keep walking.
		# Everyone else stands, and idles unless the chapter gave a habit.
		var walking_in := facing == "" and input_vector != Vector2.ZERO
		if habit == null and not walking_in:
			set_habit(Idle.new())

	# The eat clip owns the sprite until it finishes. npc.gd would otherwise
	# push the stand pose back through the tree. A walk cuts the meal short.
	if _eating:
		if not is_walking() and input_vector == Vector2.ZERO:
			velocity = Vector2.ZERO
			return
		_stop_eat()

	super._physics_process(delta)


func fidget() -> void:
	if not FACINGS.has(facing):
		facing = "down"
	var roll := randf()
	if roll < turn_chance:
		turn_quarter()
	elif roll < turn_chance + eat_chance:
		_start_eat()


func _start_eat() -> void:
	var direction := facing if FACINGS.has(facing) else "down"
	var anim_name := "eat_%s" % direction
	if not animation_player.has_animation(anim_name):
		return
	_eating = true
	animation_tree.active = false
	animation_player.play(anim_name)


func _stop_eat() -> void:
	_eating = false
	animation_player.stop()
	animation_tree.active = true


func _on_animation_finished(anim_name: StringName) -> void:
	if not String(anim_name).begins_with("eat_"):
		return
	_eating = false
	animation_tree.active = true
