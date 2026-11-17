class_name Animal
extends Npc

# An animal that potters about on its own: wanders to a free spot nearby,
# stands a while, turns, grazes, stares at Nephi when he comes close, and
# calls out now and then. Built on Npc, so it uses the same habits, walking,
# navigation and story orders as everyone else; a chapter can still
# go_to(), hold() or set_habit() it.
#
# The sheet is the usual 4 x 8 animal layout, one cell per frame:
#   rows 0-3  walk, facing up, left, down, right
#   rows 4-7  eat (head lowering over the four frames), same facings
# Standing is the first walk frame. The Sprite2D's hframes/vframes and
# offset are set in each scene; the offset puts the animal's feet on the
# node's position, so it y-sorts like everyone else.
#
# Sounds: drop any number of clips into `sounds`. One is picked at random
# (never the same twice running) every call_interval, and sometimes as a
# fidget. Only heard while Nephi is within hearing_tiles.

const ROWS := {"up": 0, "left": 1, "down": 2, "right": 3}
const EAT_ROWS := 4
const WALK_FRAMES: Array[int] = [0, 1, 2, 3]
# Hoppers only move while in the air: speed per walk frame (sit, push off,
# leap, land), averaging 1.
const HOP_GAIT: Array[float] = [0.0, 1.4, 2.2, 0.4]

@export_group("Animation")
## Walk cycle frames per second. Match it to walk_speed so the feet don't slide.
@export var walk_fps := 6.0
## Eat frames per second.
@export var eat_fps := 5.0
## Moves in bursts, only while the walk frames are in the air (rabbits).
@export var hops := false

@export_group("Wander")
## Wander about on its own. Off: stands in place, still turning, eating and calling.
@export var wanders := true
## How far from where it was placed it wanders, in tiles.
@export var wander_radius := 4.0
## Chance a pause turns it 90 degrees.
@export_range(0.0, 1.0, 0.05) var turn_chance := 0.3
## Chance a pause is spent eating.
@export_range(0.0, 1.0, 0.05) var eat_chance := 0.35
## Chance a pause is spent calling out (needs sounds).
@export_range(0.0, 1.0, 0.05) var call_chance := 0.15
## Chance it stops to stare when Nephi is within stare_tiles. Checked first.
@export_range(0.0, 1.0, 0.05) var stare_chance := 0.6
@export var stare_tiles := 4.0
@export var stare_seconds_min := 2.0
@export var stare_seconds_max := 5.0

@export_group("Sounds")
## Clips to pick from at random.
@export var sounds: Array[AudioStream] = []
## Seconds between calls. Each wait is a random time in this range.
@export var call_interval_min := 8.0
@export var call_interval_max := 20.0
## How far away Nephi can hear it, in tiles. It fades out toward the edge.
@export var hearing_tiles := 5.0
@export_range(0.0, 1.0, 0.05) var volume := 0.6
## Random pitch change per call, so repeats don't sound identical.
@export_range(0.0, 0.3, 0.01) var pitch_variance := 0.06

var _voice: AudioStreamPlayer2D
var _call_timer := 0.0
var _last_sound := -1

# The clip on the sprite: frame columns, its row, speed, and whether it loops.
var _clip: Array[int] = []
var _clip_row := 0
var _clip_fps := 1.0
var _clip_loop := false
var _clip_time := 0.0
var _eating := false
var _stare_left := 0.0
# The way it last faced, for standing between a walk and the next facing.
var _last_facing := "down"
# Decided on the first physics frame, after any spawner has set facing and habit.
var _started := false


func _init() -> void:
	pause_min = 2.0
	pause_max = 6.0
	look_around_chance = 0.0
	# Animals keep pottering about while people talk.
	pauses_for_dialogue = false


func _ready() -> void:
	if hops:
		# Its speed jumps about with the gait, which avoidance would clamp.
		avoidance = false
	super()
	_voice = AudioStreamPlayer2D.new()
	_voice.name = "Voice"
	_voice.bus = GameSettings.SFX
	_voice.volume_db = linear_to_db(volume)
	_voice.max_distance = hearing_tiles * TILE
	_voice.attenuation = 1.0
	add_child(_voice)
	# Spread out, so a flock doesn't all call at once.
	_call_timer = randf_range(0.0, call_interval_max)


# Animal sheets have no sit, kneel or pray rows.
func can_pose(_pose_name: String) -> bool:
	return false


func _physics_process(delta: float) -> void:
	if _agent == null:
		return
	if not _started:
		_started = true
		# Spawned mid-walk (no facing, already moving): let that walk play out.
		var walking_in := facing == "" and input_vector != Vector2.ZERO
		if habit == null and not walking_in:
			if facing == "":
				facing = FACINGS.pick_random()
			set_habit(Meander.new(wander_radius) if wanders else Idle.new())
	_update_stare(delta)
	if hops and is_walking():
		if not _walk.has("base_speed"):
			_walk.base_speed = _walk.speed
		var frame := _clip_frame_index() if _clip_row < EAT_ROWS else 0
		_walk.speed = _walk.base_speed * HOP_GAIT[frame]
	super(delta)


func _process(delta: float) -> void:
	_tick_calls(delta)
	_animate(delta)


# --- What to do with a pause ---

func fidget() -> void:
	if not FACINGS.has(facing):
		facing = _last_facing
	var player := _player()
	if player and _distance_to(player) < stare_tiles * TILE and randf() < stare_chance:
		stare()
		return
	var roll := randf()
	if roll < turn_chance:
		turn_quarter()
	elif roll < turn_chance + eat_chance:
		eat()
	elif roll < turn_chance + eat_chance + call_chance:
		call_out()


# Lower its head and nibble a few times. Moving cuts it short.
func eat(chews := -1) -> void:
	if chews < 0:
		chews = randi_range(2, 5)
	var frames: Array[int] = [0, 1, 2, 3]
	for i in chews:
		frames.append_array([2, 3])
	frames.append_array([3, 2, 1, 0])
	_eating = true
	_play(frames, EAT_ROWS + ROWS[_current_facing()], eat_fps, false)
	if habit:
		habit.extend_rest(frames.size() / eat_fps + 0.3)


# Turn to watch Nephi for a few seconds, following him if he moves.
func stare(seconds := -1.0) -> void:
	if seconds < 0.0:
		seconds = randf_range(stare_seconds_min, stare_seconds_max)
	_stare_left = seconds
	_eating = false
	var player := _player()
	if player:
		face_toward(player)
	if habit:
		habit.extend_rest(seconds)


# Play one of its sounds now, if Nephi is close enough to hear it.
func call_out() -> void:
	if sounds.is_empty() or _voice.playing or is_vanished() or not is_visible_in_tree():
		return
	var player := _player()
	if player == null or _distance_to(player) > hearing_tiles * TILE:
		return
	# Quiet while Nephi talks to anyone, so a call never covers a voice line.
	var small_talk := player.get_node_or_null("../SmallTalk") as SmallTalk
	if small_talk and small_talk.talking:
		return
	var pick := randi() % sounds.size()
	if sounds.size() > 1 and pick == _last_sound:
		pick = (pick + 1 + randi() % (sounds.size() - 1)) % sounds.size()
	_last_sound = pick
	_voice.stream = sounds[pick]
	_voice.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	_voice.play()


func _tick_calls(delta: float) -> void:
	if sounds.is_empty():
		return
	_call_timer -= delta
	if _call_timer <= 0.0:
		_call_timer = randf_range(minf(call_interval_min, call_interval_max), maxf(call_interval_min, call_interval_max))
		call_out()


func _update_stare(delta: float) -> void:
	if _stare_left <= 0.0:
		return
	_stare_left -= delta
	var player := _player()
	if is_walking() or _held or player == null or _distance_to(player) > stare_tiles * TILE * 1.5:
		_stare_left = 0.0
		return
	face_toward(player)


# --- The sprite ---

func _animate(delta: float) -> void:
	var sheet := sprite as Sprite2D
	if sheet == null:
		return
	# A hopper sits still between hops (input_vector is zero then) but is
	# still on its walk.
	var moving := input_vector != Vector2.ZERO or (hops and is_walking())
	if moving:
		_eating = false
		if input_vector != Vector2.ZERO:
			_last_facing = facing_for(input_vector)
		_play(WALK_FRAMES, ROWS[_last_facing], walk_fps, true)
	elif _eating:
		# Turned mid-meal (by the story, or to stare): keep eating that way.
		_clip_row = EAT_ROWS + ROWS[_current_facing()]
	else:
		_play([0], ROWS[_current_facing()], 1.0, false)

	_clip_time += delta
	if not _clip_loop and _clip_time * _clip_fps >= _clip.size():
		if _eating:
			_eating = false
			_play([0], ROWS[_current_facing()], 1.0, false)
	sheet.frame_coords = Vector2i(_clip[_clip_frame_index()], _clip_row)


# Start a clip, unless that same clip is already running.
func _play(frames: Array[int], row: int, fps: float, loop: bool) -> void:
	if frames == _clip and row == _clip_row and loop == _clip_loop:
		return
	# Walking on in a new direction keeps its step, so turning doesn't stutter.
	if not (loop and _clip_loop):
		_clip_time = 0.0
	_clip = frames
	_clip_row = row
	_clip_fps = fps
	_clip_loop = loop


func _clip_frame_index() -> int:
	if _clip.is_empty():
		return 0
	var i := int(_clip_time * _clip_fps)
	return i % _clip.size() if _clip_loop else mini(i, _clip.size() - 1)


func _current_facing() -> String:
	if FACINGS.has(facing):
		_last_facing = facing
	return _last_facing


func _player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

func _distance_to(node: Node2D) -> float:
	return node.global_position.distance_to(global_position)
