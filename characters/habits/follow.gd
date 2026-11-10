extends Habit

class_name Follow

# Stay within distance tiles of someone, facing them while standing. With
# navigation in the world they find their way around walls to catch up.
#   sister_2.set_habit(Follow.new(sariah))
#   sister_1.set_habit(Follow.new(getPlayer(), 2))

# How far past distance the target must get before they start walking again,
# so a small step by the target does not set them off every time.
const SLACK := 0.75
# How often the walk is re-aimed at a target that keeps moving.
const REAIM_SECONDS := 0.5
# Short checks while standing, so they notice the target leaving quickly.
const WATCH_MIN := 0.3
const WATCH_MAX := 0.8

var target: Node2D
var distance: float

var _walking := false
var _aimed_at := Vector2.INF
var _reaim_in := 0.0


func _init(follow_target: Node2D, distance_tiles: float = 1.5) -> void:
	target = follow_target
	distance = distance_tiles
	# They keep their eyes on the target instead of looking around.
	fidgets = false

func start() -> void:
	_walking = false
	rest(randf_range(0.2, 0.6))

func resume() -> void:
	start()

func tick(delta: float) -> void:
	if not is_instance_valid(target):
		return
	# The player is not under Cutscene, so measure in the follower's own space.
	var target_tile := (npc.get_parent() as Node2D).to_local(target.global_position) / Npc.TILE
	var away := npc.current_tile().distance_to(target_tile)
	if _walking:
		if not npc.is_walking():
			_walking = false
			# Stuck, or arrived where the target used to be. Pause either way.
			rest(randf_range(WATCH_MIN, WATCH_MAX))
			return
		if away <= distance:
			npc.stop_walking()
			_walking = false
			npc.face_toward(target)
			rest(randf_range(WATCH_MIN, WATCH_MAX))
			return
		_reaim_in -= delta
		# Re-aim only when the target has moved, so a blocked walk still times out.
		if _reaim_in <= 0.0 and target_tile.distance_to(_aimed_at) > 0.5:
			_walk_toward(target_tile)
		return
	if resting(delta):
		return
	if away > distance + SLACK:
		_walk_toward(target_tile)
	else:
		npc.face_toward(target)
		rest(randf_range(WATCH_MIN, WATCH_MAX))

func _walk_toward(target_tile: Vector2) -> void:
	_walking = true
	_aimed_at = target_tile
	_reaim_in = REAIM_SECONDS
	npc.habit_walk_to(target_tile)
