extends Habit

class_name Station

# Go to a spot and stay there, faced one way, doing one thing all day:
#   "stand"       just standing, as a guard at a gate
#   "work"        the work cycle, as tending a fire or chopping wood
#   "sit", "sit_lean", "sit_ground", "kneel", "pray"   a pose (Npc.POSES)
# A pose their sheet cannot do (CharGen sheets cannot sit) falls back to
# standing. Stuck short of the spot, they stay where they got to. They do not
# look around, so they stay on their task.
#   sariah.set_habit(Station.new(Vector2(-7, 9), "up", "work"))
#   wife.set_habit(Station.new(Vector2(-3, -5.5), "down", "sit"))

var spot: Vector2
var direction: String
var action: String

var _walking := false


func _init(spot_tile: Vector2, facing_direction := "down", what := "stand") -> void:
	spot = spot_tile
	direction = facing_direction
	action = what
	fidgets = false

func start() -> void:
	_go()

# After a dialogue pause they are still in place, and _go() settles them again.
func resume() -> void:
	_go()

func tick(_delta: float) -> void:
	if not _walking or npc.is_walking():
		return
	_walking = false
	_settle()

func _go() -> void:
	if npc.current_tile().distance_to(spot) * Npc.TILE <= 2.0:
		_walking = false
		_settle()
		return
	_walking = true
	# A long stuck timeout: getting there matters more than giving up quickly.
	npc.habit_walk_to(spot, 3.0, true)

func _settle() -> void:
	npc.facing = direction
	match action:
		"stand":
			pass
		"work":
			npc.working = true
		_:
			if not npc.is_posed(action) and npc.can_pose(action):
				npc.pose(action, direction, true)
