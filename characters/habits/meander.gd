extends Habit

class_name Meander

# Wander within radius tiles of home: walk to a nearby spot, pause, repeat.
# home defaults to where they stand when the habit is given. Only spots they
# can reach are chosen (Npc.can_reach): on the walkable area with
# navigation, or along a clear straight line without it.
# After a scripted order and release(), they drift back toward home.
#   sam.set_habit(Meander.new(2))
#   sam.set_habit(Meander.new(3, Vector2(-12, 6)))

const PICK_TRIES := 6

var radius: float
var home: Vector2

var _home: Vector2
var _walking := false


func _init(radius_tiles: float = 2.0, home_tile: Vector2 = Vector2.INF) -> void:
	radius = radius_tiles
	home = home_tile

func start() -> void:
	_home = npc.current_tile() if home == Vector2.INF else home
	_walking = false
	rest(randf_range(0.5, maxf(0.5, npc.pause_min)))

func resume() -> void:
	_walking = false
	rest()

func tick(delta: float) -> void:
	if _walking:
		if npc.is_walking():
			return
		_walking = false
		rest()
		return
	if resting(delta):
		return
	var spot := _pick_spot()
	if spot == Vector2.INF:
		rest()
		return
	_walking = true
	npc.habit_walk_to(spot)

func _pick_spot() -> Vector2:
	var here := npc.current_tile()
	for i in PICK_TRIES:
		# sqrt spreads picks evenly over the circle instead of bunching at home.
		var spot := _home + Vector2.from_angle(randf() * TAU) * radius * sqrt(randf())
		if spot.distance_to(here) < 0.5:
			continue
		if npc.can_reach(spot):
			return spot
	return Vector2.INF
