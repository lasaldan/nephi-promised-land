extends Habit

class_name Patrol

# Walk a list of spots in order, then loop back to the first. With
# back_and_forth, walk the list forward then backward instead. Starts at
# whichever spot is nearest. A spot they cannot reach is skipped after the
# usual stuck timeout.
#
# A spot is a tile, or a dictionary for a stop where they work a while:
#   {"tile": Vector2, "facing": "up" or ["up", "right"], "works": Vector2i(2, 4)}
# They turn one of the facings (picked for each play, so they reach about)
# and play the work cycle a number of times in the works range. A plain tile
# is a pause in the character's usual range instead.
#   laman.set_habit(Patrol.new([Vector2(-10, 7), Vector2(-4, 7), Vector2(-4, 2)]))
#   daughter.set_habit(Patrol.new([
#       {"tile": Vector2(-7.5, 3.5), "facing": ["right"], "works": Vector2i(2, 3)},
#       Vector2(-10.5, 3.5),
#       {"tile": Vector2(-10.5, -11.5), "facing": ["up", "right"], "works": Vector2i(4, 6)},
#   ]))

# One play of the work row (the work clips are 0.8 seconds), and the
# standing between plays.
const WORK_CYCLE := 0.8
const BETWEEN_WORK := Vector2(0.8, 2.2)

var points: Array[Dictionary] = []
var back_and_forth: bool

var _index := 0
var _step := 1
var _walking := false
var _works_left := 0
var _work_left := 0.0


func _init(spots: Array, walk_back_and_forth := false) -> void:
	for spot in spots:
		points.append(spot if spot is Dictionary else {"tile": spot})
	back_and_forth = walk_back_and_forth

func start() -> void:
	if points.is_empty():
		push_error("Patrol needs at least one spot")
		return
	var here := npc.current_tile()
	_index = 0
	for i in points.size():
		if (points[i].tile as Vector2).distance_to(here) < (points[_index].tile as Vector2).distance_to(here):
			_index = i
	_step = 1
	_walk_to_current()

func resume() -> void:
	# Head back to the spot they were going for.
	if not points.is_empty():
		_walk_to_current()

func stop() -> void:
	npc.working = false

func tick(delta: float) -> void:
	if points.is_empty():
		return
	if _walking:
		if npc.is_walking():
			return
		_walking = false
		_arrive()
		return
	if _work_left > 0.0:
		_work_left -= delta
		if _work_left <= 0.0:
			npc.working = false
			rest(randf_range(BETWEEN_WORK.x, BETWEEN_WORK.y))
		return
	if resting(delta):
		return
	if _works_left > 0:
		_work_once()
		return
	_advance()
	_walk_to_current()

func _arrive() -> void:
	var works: Vector2i = points[_index].get("works", Vector2i.ZERO)
	_works_left = randi_range(works.x, works.y) if works != Vector2i.ZERO else 0
	if _works_left > 0:
		_work_once()
	else:
		rest()

func _work_once() -> void:
	_works_left -= 1
	var facings: Variant = points[_index].get("facing", ["down"])
	npc.facing = facings if facings is String else (facings as Array).pick_random()
	npc.working = true
	_work_left = WORK_CYCLE

func _advance() -> void:
	if points.size() == 1:
		return
	if back_and_forth:
		if _index + _step < 0 or _index + _step >= points.size():
			_step = -_step
		_index += _step
	else:
		_index = (_index + 1) % points.size()

func _walk_to_current() -> void:
	_walking = true
	_work_left = 0.0
	_works_left = 0
	npc.working = false
	npc.habit_walk_to(points[_index].tile)
