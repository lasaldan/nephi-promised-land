extends Habit

class_name Tend

# Stay where they stand, faced one way, and every so often work a moment
# (the work cycle, hands reaching out) before standing easy again, as Sam at
# the helm making a small turn now and then. Station "work" works without
# stopping; this rests between.
#   sam.set_habit(Tend.new("left"))
#   sam.set_habit(Tend.new("left", Vector2i(1, 2), Vector2(3, 7)))

# One play of the work row (the work clips are 0.8 seconds).
const WORK_CYCLE := 0.8

var direction: String
# How many plays of the work row in one go, and the seconds stood between.
var works: Vector2i
var pause: Vector2

var _work_left := 0.0


func _init(facing_direction := "down", works_range := Vector2i(1, 2), pause_range := Vector2(3.0, 7.0)) -> void:
	direction = facing_direction
	works = works_range
	pause = pause_range
	fidgets = false

func start() -> void:
	_stand()

# After a hold or a talk, back to facing their work.
func resume() -> void:
	_stand()

func stop() -> void:
	npc.working = false

func tick(delta: float) -> void:
	if _work_left > 0.0:
		_work_left -= delta
		if _work_left <= 0.0:
			_stand()
		return
	if resting(delta):
		return
	npc.facing = direction
	npc.working = true
	_work_left = randi_range(works.x, works.y) * WORK_CYCLE

func _stand() -> void:
	_work_left = 0.0
	npc.working = false
	npc.facing = direction
	rest(randf_range(pause.x, pause.y))
