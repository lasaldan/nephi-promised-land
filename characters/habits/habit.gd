extends RefCounted

class_name Habit

# What a character does when the story is not directing them. npc.gd ticks
# the current habit every physics frame, except while a scripted order holds
# them (go_to, hold, walk) or a dialogue balloon is open. How they do it
# (pace, pause length, how often they look around) comes from the character's
# Habits exports, so the same Meander looks different on Lehi and on Sam.
#
# Habits keep state, so give each character its own instance:
#   lehi.set_habit(Meander.new(2))
#   {"name": "sheep", "start": Vector2(-20, -51), "habit": Meander.new(1.5)},

# Set by Npc.set_habit. One habit belongs to one character.
var npc: Npc
# False for habits that should keep their facing while they rest.
var fidgets := true

var _rest_left := 0.0
var _fidget_in := INF


# Once, when the habit is assigned.
func start() -> void:
	rest()

# After a hold, release, or dialogue pause. Any walk was stopped, so a habit
# that was mid-walk should choose again. Most habits just pause first.
func resume() -> void:
	rest()

func tick(_delta: float) -> void:
	pass

# Once, when another habit (or none) replaces this one. Undo anything the
# habit holds on to, such as a place in line.
func stop() -> void:
	pass


# Stand still for a while, fidgeting once somewhere in the middle of it.
# With no length, uses the character's pause range.
func rest(seconds: float = -1.0) -> void:
	if seconds < 0.0:
		seconds = npc.random_pause()
	_rest_left = seconds
	_fidget_in = randf_range(0.2, 0.8) * seconds

# True while a rest() is still running. Call it at the top of tick().
func resting(delta: float) -> bool:
	if _rest_left <= 0.0:
		return false
	_rest_left -= delta
	_fidget_in -= delta
	if _fidget_in <= 0.0:
		_fidget_in = INF
		if fidgets:
			npc.fidget()
	return _rest_left > 0.0
