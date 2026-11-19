extends ScrollBoard

class_name PanBoard

# Panning for gold in the stream (ACTIVITIES.md). A pan lies on the paper,
# seen from above, with water in it and a mound of sand and gravel. A ring of
# glowing dots runs around it to show the swirl.
#
# Swirling a finger around the pan, either way round, turns the water, and the
# sand turns with it. Every bit of swirl washes some sand out: grains drift to
# the rim and spill over it, the outside of the mound first, so the mound
# shrinks toward the middle. Whatever gold lies under it shows as it thins.
# After TURNS swirls the sand is gone, the gold glints, and the board emits
# finished.
#
# Grains only move while the swirl goes on, so stopping just stops. Nothing is
# lost. The angle is read around the pan's middle wherever the finger is, so
# a big loose circle works as well as a neat one.
#
# config: "flakes", how much gold this spot holds (0 to 8, default 3). A
# chapter tries several spots along the stream, each with its own count, and
# gives the gold itself afterward. "seed" changes how the sand lies.

# Whole swirls to wash the pan clean, either way round, added up.
const TURNS := 6.0
const GRAINS := 170
# How much of the whole swirl one grain takes to wash from its place over the
# rim.
const WASH_SPAN := 0.12
# One drag event counts at most this much swirl, so a jump across the middle
# is not a free half-turn.
const MAX_STEP := 0.6
# A finger closer than this to the middle does not swirl: there the angle
# jumps about with the slightest move.
const DEAD_ZONE := 12.0
const DONE_SECONDS := 1.8
const MAX_FLAKES := 8

const PAN_CENTER := Vector2(CENTER, 146)
const PAN_RADIUS := 86.0
# Inside the rim, where the water is.
const WATER_RADIUS := 76.0
const MOUND_RADIUS := 46.0
const GUIDE_RADIUS := 97.0
const GUIDE_DOTS := 12

const IRON_OUTLINE := Color("2a2622")
const IRON := Color("5b5550")
const IRON_LIGHT := Color("7a726a")
const IRON_BOTTOM := Color("75604a")
const WATER := Color(0.3, 0.62, 0.78, 0.3)
const WATER_SHINE := Color(1, 1, 1, 0.5)
const WET_SAND := Color(0.55, 0.44, 0.3, 0.9)
const SAND := [Color("c9a873"), Color("b08d5a"), Color("8f7048"), Color("d8c08e"), Color("6e6258"), Color("9a8f84")]
const GOLD := [Color("f7d64a"), Color("e3b42c"), Color("fff2a0")]
const GLOW := Color(1.0, 0.92, 0.55)
const GUIDE := Color("d9a940")

const GOLD_SOUND := preload("res://audio/sfx/collect_item.ogg")

var progress := 0.0
var flakes := 3

# Each grain: radius and angle in the mound, size, color, how fast it turns
# with the water, and how far through the swirl it starts to wash.
var _grains: Array[Dictionary] = []
var _gold: Array[Dictionary] = []
var _swirl := 0.0
var _spin_speed := 0.0
var _push := 0.0
var _dragging := false
var _last_angle := 0.0
# The way the last swirl went, for the guide dots: 1 clockwise, -1 not.
var _turning := 1.0
var _time := 0.0
var _done_time := -1.0
var _sound: AudioStreamPlayer

func _ready() -> void:
	_sound = AudioStreamPlayer.new()
	_sound.stream = GOLD_SOUND
	_sound.bus = GameSettings.SFX
	add_child(_sound)

func reset() -> void:
	flakes = clampi(int(config.get("flakes", 3)), 0, MAX_FLAKES)
	progress = 0.0
	_swirl = 0.0
	_spin_speed = 0.0
	_push = 0.0
	_dragging = false
	_done_time = -1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.get("seed", 7))
	_grains.clear()
	for i in GRAINS:
		var rr := sqrt(rng.randf()) * MOUND_RADIUS
		var outer := rr / MOUND_RADIUS
		_grains.append({
			"r": rr,
			"a": rng.randf() * TAU,
			"size": 3.0 if rng.randf() < 0.7 else 4.0,
			"color": SAND[rng.randi() % SAND.size()],
			"turn": 0.35 + 0.3 * outer,
			# Outside first: the mound shrinks toward the middle.
			"wash": ((1.0 - outer) * 0.85 + rng.randf() * 0.15) * (1.0 - WASH_SPAN),
		})
	_gold.clear()
	for i in flakes:
		_gold.append({
			"r": sqrt(rng.randf()) * MOUND_RADIUS * 0.4,
			"a": rng.randf() * TAU,
			"size": Vector2(4, 3) if rng.randf() < 0.5 else Vector2(3, 3),
			"color": GOLD[rng.randi() % 2],
			"phase": rng.randf() * TAU,
		})
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	# The water follows the finger and keeps turning a little once let go.
	if _push != 0.0 and delta > 0.0:
		_spin_speed = lerpf(_spin_speed, _push / delta, 0.5)
	else:
		_spin_speed *= exp(-2.0 * delta)
	_swirl += _spin_speed * delta
	_push = 0.0
	if _done_time >= 0.0:
		_done_time += delta
		if _done_time >= DONE_SECONDS and _done_time - delta < DONE_SECONDS:
			finished.emit()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if is_emulated(event) or _done_time >= 0.0:
		return
	if is_press(event):
		var at := point_of(event)
		_dragging = event.is_pressed()
		if _dragging:
			_last_angle = (at - PAN_CENTER).angle()
		accept_event()
	elif is_drag(event) and _dragging:
		var at := point_of(event)
		if at.distance_to(PAN_CENTER) <= DEAD_ZONE:
			return
		var angle := (at - PAN_CENTER).angle()
		var step := clampf(wrapf(angle - _last_angle, -PI, PI), -MAX_STEP, MAX_STEP)
		_last_angle = angle
		_push += step
		if absf(step) > 0.01:
			_turning = signf(step)
		progress = minf(progress + absf(step) / (TURNS * TAU), 1.0)
		if progress >= 1.0:
			_done_time = 0.0
			_dragging = false
			if flakes > 0:
				_sound.play()
		accept_event()

# --- Drawing ---

func _draw() -> void:
	var c := PAN_CENTER
	if _done_time < 0.0:
		_draw_guide()
	# The pan.
	draw_circle(c, PAN_RADIUS + 2, IRON_OUTLINE)
	draw_circle(c, PAN_RADIUS, IRON)
	draw_arc(c, PAN_RADIUS - 2, PI * 1.05, PI * 1.6, 32, IRON_LIGHT, 2.0)
	draw_circle(c, WATER_RADIUS + 2, IRON_OUTLINE)
	draw_circle(c, WATER_RADIUS, IRON_BOTTOM)
	# Wet sand under the grains, shrinking with them.
	# The gold lies under it, showing through as it thins.
	_draw_gold()
	var mound := MOUND_RADIUS * (1.0 - progress * 0.97) + 4.0
	var wet := WET_SAND
	wet.a *= clampf(1.15 - progress * 1.25, 0.0, 1.0)
	draw_circle(c, mound, wet)
	_draw_grains()
	# Water over it all, with shine turning on it.
	draw_circle(c, WATER_RADIUS, WATER)
	for ring in [0.55, 0.82]:
		var a: float = _swirl * 0.8 + ring * 3.0
		draw_arc(c, WATER_RADIUS * ring, a, a + 0.7, 12, WATER_SHINE, 1.5)
		draw_arc(c, WATER_RADIUS * ring, a + PI, a + PI + 0.45, 8, WATER_SHINE, 1.0)
	if _done_time >= 0.0:
		_draw_glints()

func _draw_grains() -> void:
	var c := PAN_CENTER
	for grain in _grains:
		var w := clampf((progress - grain.wash) / WASH_SPAN, 0.0, 1.0)
		if w >= 1.0:
			continue
		var r: float = lerpf(grain.r, PAN_RADIUS + 6.0, ease(w, 2.0))
		var a: float = grain.a + _swirl * grain.turn + w * 1.5
		var color: Color = grain.color
		if w > 0.6:
			color.a = (1.0 - w) / 0.4
		var size: float = grain.size
		var at := (c + Vector2.from_angle(a) * r - Vector2(size, size) / 2).round()
		draw_rect(Rect2(at, Vector2(size, size)), color)

func _draw_gold() -> void:
	var c := PAN_CENTER
	for flake in _gold:
		var a: float = flake.a + _swirl * 0.3
		var at: Vector2 = (c + Vector2.from_angle(a) * flake.r).round()
		draw_rect(Rect2(at - Vector2(1, 1), flake.size + Vector2(2, 2)), Color("7a5a14"))
		draw_rect(Rect2(at, flake.size), flake.color)
		draw_rect(Rect2(at, Vector2(1, 1)), GOLD[2])

# Each flake twinkles once the pan is clean.
func _draw_glints() -> void:
	var c := PAN_CENTER
	var fade := clampf(_done_time / 0.3, 0.0, 1.0)
	for flake in _gold:
		var a: float = flake.a + _swirl * 0.3
		var at: Vector2 = (c + Vector2.from_angle(a) * flake.r).round() + flake.size / 2
		var twinkle := maxf(sin(_time * 6.0 + flake.phase), 0.0)
		var color := GLOW
		color.a = fade * twinkle
		var arm := 2.0 + 3.0 * twinkle
		draw_line(at - Vector2(arm, 0), at + Vector2(arm, 0), color, 1.0)
		draw_line(at - Vector2(0, arm), at + Vector2(0, arm), color, 1.0)

# Dots running around the pan the way to swirl. Dimmer while swirling.
func _draw_guide() -> void:
	var c := PAN_CENTER
	var color := GUIDE
	var base := 0.35 if _dragging else 0.9
	for i in GUIDE_DOTS:
		var a := TAU * i / GUIDE_DOTS + _turning * _time * 1.2
		var t := fposmod(float(i) / GUIDE_DOTS * 3.0 + _turning * _time * 0.5, 1.0)
		color.a = base * (0.4 + 0.6 * t)
		var at := c + Vector2.from_angle(a) * GUIDE_RADIUS
		draw_circle(at, 2.0 + t, color)
