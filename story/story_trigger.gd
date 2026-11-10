extends Area2D

class_name StoryTrigger

# Every trigger joins this, so a prayer for guidance can find the armed ones.
const GROUP := "story_triggers"

# Fired when the player enters, including a player already overlapping on arm.
# quest_id, when set, is also sent on SignalBus.quest_completed.
signal fired(trigger: StoryTrigger)

# Matches a StoryChapter.ends_on quest id, or a side-quest id.
# Leave empty when a chapter script listens to fired() instead.
@export var quest_id: String = ""

# Chapter activation arms only these. A later beat stays false until
# StoryChapter.arm_trigger() names it.
@export var starts_armed: bool = true

# A goal that already counted should not complete again if the player walks back in.
@export var one_shot: bool = true

var _consumed := false
# Source of truth for armed state. monitoring is set deferred because arming can
# happen inside a body_entered flush, so it lags a frame behind this flag.
var _armed := false
# instance id -> true, so body_entered and the overlap scan cannot both emit.
var _reported_bodies: Dictionary = {}
# Physics frames to wait after arming before reading overlaps. The area's
# overlap list is filled on a physics step, not on the frame monitoring flips on.
var _overlap_wait_frames := 0

func _ready() -> void:
	add_to_group(GROUP)
	# Scene instances stay inert until the owning chapter arms them.
	# _physics_process exists only for the post-arm overlap check.
	monitoring = false
	monitorable = false
	set_physics_process(false)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

# Armed and not yet used up: the player still has to walk into it.
func is_waiting() -> bool:
	return _armed and not _consumed

func set_armed(armed: bool) -> void:
	if _consumed:
		_armed = false
		set_deferred("monitoring", false)
		set_physics_process(false)
		return
	_armed = armed
	set_deferred("monitoring", armed)
	if not armed:
		_overlap_wait_frames = 0
		set_physics_process(false)
		return
	# A player already inside should count again if this trigger is re-armed.
	_reported_bodies.clear()
	# Skip the physics frame that enables monitoring; read overlaps on the next one.
	_overlap_wait_frames = 1
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if _overlap_wait_frames > 0:
		_overlap_wait_frames -= 1
		return
	set_physics_process(false)
	if not _armed:
		return
	for body in get_overlapping_bodies():
		_on_body_entered(body)

func _on_body_entered(body: Node) -> void:
	if _consumed or not _armed:
		return
	# NPCs share the player's collision layer, so the layer mask is not enough.
	if not body.is_in_group("player"):
		return
	var body_id := body.get_instance_id()
	if _reported_bodies.has(body_id):
		return
	_reported_bodies[body_id] = true
	if one_shot:
		_consumed = true
		_armed = false
		set_deferred("monitoring", false)
		set_physics_process(false)
	fired.emit(self)
	if not quest_id.is_empty():
		SignalBus.quest_completed.emit(quest_id)

func _on_body_exited(body: Node) -> void:
	# Lets a trigger that is not one-shot fire again the next time they enter.
	_reported_bodies.erase(body.get_instance_id())
