extends Habit

class_name Idle

# Stand in place, now and then looking around. Animals graze too, since
# pasture_animal.gd's fidget() can eat.
#   lehi.set_habit(Idle.new())

func start() -> void:
	# Sooner than a full pause, so a scene does not sit frozen through its fade-in.
	rest(randf_range(0.8, maxf(0.8, npc.pause_min)))

func tick(delta: float) -> void:
	if not resting(delta):
		rest()
