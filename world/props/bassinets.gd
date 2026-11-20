@tool
class_name Bassinets
extends StaticBody2D

# Two lashed cribs of rough lumber below decks, a baby asleep in each,
# bundled in fur (left in a tawny hide, right in a sheepskin). Art from
# tools/bassinet/gen.py.
#
# The babies breathe slowly while they sleep. Now and then one fusses: it
# wriggles, a fist works free and it wails, playing one of cries if any are
# set. Chapters can start and stop it:
#   bassinets.fuss(Bassinets.LEFT)         fusses for fuss_seconds
#   bassinets.fuss(Bassinets.RIGHT, 6.0)   ...or for 6 seconds
#   bassinets.hush(Bassinets.RIGHT)        back to sleep now
# With fuss_every set, they also fuss on their own, one at a time.
#
# Its origin is the front of the cribs at floor level, like the bunk it
# stands in for: put it under Ship/Lower, which y-sorts.

enum { LEFT, RIGHT }

signal fussing_started(which: int)
signal fussing_stopped(which: int)

const SLEEP_FRAMES := [0, 1]
const FUSS_FRAMES := [2, 3]
# Seconds per breath (in, then out), and per wriggle while fussing.
const BREATH_SECONDS := 1.6
const WRIGGLE_SECONDS := 0.2

## Whether the left crib has its baby.
@export var left_baby := true:
	set(value):
		left_baby = value
		_refresh()
## Whether the right crib has its baby.
@export var right_baby := true:
	set(value):
		right_baby = value
		_refresh()
## Crying sounds; one is picked at random each time a baby starts to fuss.
@export var cries: Array[AudioStream] = []
## How long a fuss lasts when fuss() is not given a time.
@export var fuss_seconds := 4.0
## Seconds between fusses on their own, picked at random in this range.
## (0, 0) means they only fuss when told to.
@export var fuss_every := Vector2.ZERO

# Seconds of fussing left for each baby (0 while asleep).
var _fussing := [0.0, 0.0]
var _clock := 0.0
var _next_fuss := 0.0

@onready var _babies: Array[Sprite2D] = [$BabyLeft as Sprite2D, $BabyRight as Sprite2D]
@onready var _cry := $Cry as AudioStreamPlayer2D

func _ready() -> void:
	_refresh()
	if Engine.is_editor_hint():
		set_process(false)
		return
	_cry.bus = GameSettings.SFX
	_schedule()

func has_baby(which: int) -> bool:
	return left_baby if which == LEFT else right_baby

func is_fussing(which: int) -> bool:
	return _fussing[which] > 0.0

# The baby in that crib wakes and fusses for seconds (fuss_seconds if not
# given), then drops back off.
func fuss(which: int, seconds := -1.0) -> void:
	if not has_baby(which):
		return
	var was := is_fussing(which)
	_fussing[which] = seconds if seconds > 0.0 else fuss_seconds
	if not cries.is_empty():
		_cry.global_position = _babies[which].global_position + Vector2(_babies[which].offset.x + 14, -20)
		_cry.stream = cries.pick_random()
		_cry.play()
	if not was:
		fussing_started.emit(which)

# Back to sleep at once.
func hush(which: int) -> void:
	if not is_fussing(which):
		return
	_fussing[which] = 0.0
	_cry.stop()
	_babies[which].frame = SLEEP_FRAMES[0]
	fussing_stopped.emit(which)

func _process(delta: float) -> void:
	_clock += delta
	for which in [LEFT, RIGHT]:
		var baby := _babies[which]
		if is_fussing(which):
			_fussing[which] -= delta
			if _fussing[which] <= 0.0:
				_fussing[which] = 0.0
				_cry.stop()
				fussing_stopped.emit(which)
			else:
				baby.frame = FUSS_FRAMES[int(_clock / WRIGGLE_SECONDS) % 2]
				continue
		# the two breathe out of step
		var t := _clock / BREATH_SECONDS + (0.5 if which == RIGHT else 0.0)
		baby.frame = SLEEP_FRAMES[int(t) % 2]
	if fuss_every.y > 0.0 and not is_fussing(LEFT) and not is_fussing(RIGHT):
		_next_fuss -= delta
		if _next_fuss <= 0.0:
			var awake := [LEFT, RIGHT].filter(has_baby)
			if not awake.is_empty():
				fuss(awake.pick_random())
			_schedule()

func _schedule() -> void:
	_next_fuss = randf_range(fuss_every.x, maxf(fuss_every.x, fuss_every.y))

func _refresh() -> void:
	if not is_node_ready():
		return
	_babies[LEFT].visible = left_baby
	_babies[RIGHT].visible = right_baby
