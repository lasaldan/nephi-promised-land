@tool
class_name DayNight
extends CanvasModulate

# The time of day, as the color of the world. The world has exactly one of
# these (only one CanvasModulate may exist per canvas). CanvasLayers (the UI,
# the scripture scroll, dialogue balloons) are not on this canvas, so they
# stay fully lit.
#
# hour runs 0 to 24. The color comes from the keys below: night, a pink dawn,
# the white of day, an orange dusk, and back to night. night_amount (0 day, 1
# night) follows it, and everything that cares listens to that:
#   - FlickerLights with night_only fade up (campfires, lamps)
#   - the crickets fade in
#   - AmbientZones set to day or night only (world/ambience/ambient_zone.gd)
#   - night_amount_changed, for anything else
#
# Time stands still unless a cycle is running. Chapters use the StoryChapter
# helpers (nightfall(), daybreak(), setTimeOfDay(), startDayCycle()); the
# world keeps the hour across chapters and saves it with each chapter.
#   await day_night.go_to_hour(DayNight.DUSK, 4.0)
#   day_night.start_cycle(10.0)   # a whole day every ten real minutes

signal night_amount_changed(amount: float)

const GROUP := "day_night"
const CRICKETS_SOUND := preload("res://audio/ambience/crickets_loop.ogg")

# Hours worth naming.
const MIDNIGHT := 0.0
const DAWN := 6.0
const MORNING := 8.0
const NOON := 12.0
const DUSK := 19.0
const NIGHT := 21.5

@export_range(0.0, 24.0, 0.25) var hour := NOON:
	set(value):
		hour = wrapf(value, 0.0, 24.0)
		_apply()

@export_group("Colors")
@export var night_color := Color(0.28, 0.31, 0.50)
@export var dawn_color := Color(0.85, 0.72, 0.78)
@export var day_color := Color.WHITE
@export var dusk_color := Color(0.95, 0.70, 0.52)
@export_group("Sound")
## How loud the crickets are at full night.
@export var crickets_volume_db := -6.0

# Hour, color, night_amount. Between keys both are blended.
var _keys: Array = []

# 0 is full day, 1 is full night.
var night_amount := 0.0

var _tween: Tween
var _crickets: AudioStreamPlayer
# Real minutes for a whole day while a cycle runs. 0 is no cycle.
var _cycle_minutes := 0.0

func _ready() -> void:
	add_to_group(GROUP)
	if not Engine.is_editor_hint():
		_crickets = AudioStreamPlayer.new()
		_crickets.name = "Crickets"
		_crickets.stream = CRICKETS_SOUND
		_crickets.bus = GameSettings.SFX
		add_child(_crickets)
	_apply()

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _cycle_minutes <= 0.0:
		return
	hour += 24.0 * delta / (_cycle_minutes * 60.0)

# The day moves on by itself, a whole day every minutes_per_day real minutes.
func start_cycle(minutes_per_day: float) -> void:
	_cycle_minutes = maxf(minutes_per_day, 0.0)

func stop_cycle() -> void:
	_cycle_minutes = 0.0

func is_cycling() -> bool:
	return _cycle_minutes > 0.0

# Move time forward to target over seconds (never backward: 22 to 8 goes
# through the night). 0 seconds switches at once, for behind a black screen.
func go_to_hour(target: float, seconds := 3.0) -> void:
	if _tween:
		_tween.kill()
	var start := hour
	var ahead := fposmod(target - start, 24.0)
	if seconds <= 0.0 or ahead == 0.0:
		hour = target
		return
	_tween = create_tween()
	_tween.tween_method(func(t: float) -> void: hour = start + ahead * t, 0.0, 1.0, seconds) \
			.set_trans(Tween.TRANS_SINE)
	await _tween.finished

func is_night() -> bool:
	return night_amount >= 0.5

# Kept for scripts that think in night and day.
func fade_to_night(seconds := 3.0) -> void:
	await go_to_hour(NIGHT, seconds)

func fade_to_day(seconds := 3.0) -> void:
	await go_to_hour(MORNING, seconds)

func set_night(on: bool) -> void:
	await go_to_hour(NIGHT if on else MORNING, 0.0)

# The crickets down to silent, leaving the night as it is, for a night that
# ends on the black. The next change to the hour brings them back to match it.
func fade_out_crickets(seconds: float) -> void:
	if _crickets == null or not _crickets.playing:
		return
	var tween := create_tween()
	tween.tween_method(func(level: float) -> void: _crickets.volume_db = maxf(linear_to_db(level), -80.0),
			db_to_linear(_crickets.volume_db), 0.0, seconds)
	await tween.finished
	_crickets.stop()

func _apply() -> void:
	_keys = [
		[0.0, night_color, 1.0],
		[5.0, night_color, 1.0],
		[6.5, dawn_color, 0.4],
		[8.0, day_color, 0.0],
		[17.5, day_color, 0.0],
		[19.0, dusk_color, 0.3],
		[21.0, night_color, 1.0],
		[24.0, night_color, 1.0],
	]
	for i in range(1, _keys.size()):
		if hour <= _keys[i][0]:
			var a: Array = _keys[i - 1]
			var b: Array = _keys[i]
			var t: float = inverse_lerp(a[0], b[0], hour)
			color = (a[1] as Color).lerp(b[1], t)
			_set_night_amount(lerpf(a[2], b[2], t))
			return

func _set_night_amount(amount: float) -> void:
	if is_equal_approx(amount, night_amount) and is_node_ready():
		return
	night_amount = amount
	if not is_inside_tree() or Engine.is_editor_hint():
		return
	get_tree().call_group(FlickerLight.GROUP, "set_night_amount", amount)
	night_amount_changed.emit(amount)
	# Louder as the night deepens, silent and stopped by day.
	if _crickets:
		if amount <= 0.0:
			_crickets.stop()
		else:
			_crickets.volume_db = crickets_volume_db + linear_to_db(amount)
			if not _crickets.playing:
				_crickets.play()
