extends ScrollBoard

class_name SteerBoard

# Steering the ship by the Liahona (ACTIVITIES.md). The Liahona's dial sits at
# the top of the paper, seen from above, with a glowing wedge at its top: that
# is straight ahead, over the bow. Its spindle points the way to go, so it
# swings as the ship turns. Below it is the ship's wheel.
#
# The wheel sets how fast the ship turns, not where it points, like a real
# helm: one spoke, the king spoke, is marked in brass, and while it stands at
# the top the ship holds its heading. Turn the wheel off center and the ship
# comes around (ShipSway.heading), the further the quicker, easing into and
# out of the turn; the spindle swings to match. To hold the new course, the
# wheel has to go back to center. Let go near center and it settles there.
# While the spindle is in the wedge, a ring around the dial fills; out of it,
# the ring slowly drains. Once it is full the dial pulses and the board
# emits finished. The ship keeps its heading and the wheel rights itself.
#
# The wheel follows the finger around its hub from wherever the drag starts,
# so grabbing a handle and turning works, and so does a swipe across the top.
# A curved arrow over the wheel shows which way to turn it: toward the course
# while off it, and back to center as the ship comes onto it.
#
# config: "target", the heading the spindle points to, in ship degrees
# (default 0, the course). The board starts from wherever the ship is turned,
# so a chapter turns it off course first (StoryChapter.setShipHeading()).

# Seconds in the wedge to finish.
const ALIGN_SECONDS := 4.0
# Seconds out of the wedge for a full ring to drain empty.
const DRAIN_SECONDS := 10.0
# How close to the target counts as on course, in ship degrees either way.
const WEDGE_DEGREES := 0.75
# Degrees of wheel for one degree per second of turn. 90 makes a quarter turn
# of the wheel turn the ship a degree each second.
const WHEEL_PER_RATE := 90.0
# How far the wheel turns either way from center, in degrees, so the
# quickest turn is WHEEL_LIMIT / WHEEL_PER_RATE degrees a second.
const WHEEL_LIMIT := 180.0
# This close to center, in wheel degrees, the ship holds its heading, and
# letting go this close lets the wheel settle back to center.
const CENTER_DEGREES := 6.0
const CENTER_SNAP_DEGREES := 15.0
# Degrees a second the wheel turns by itself to settle at center.
const SETTLE_DEGREES_PER_SECOND := 180.0
# How quickly the turn follows the wheel, in degrees per second each second,
# so the ship eases into a turn and carries on a little after the wheel is
# centered.
const HELM_RESPONSE := 1.5
# Seconds ahead the arrow looks: if the ship would reach the course by then,
# it asks for the wheel back to center.
const ARROW_LEAD_SECONDS := 1.2
# Degrees the spindle swings for one degree of ship off course, so a small
# turn of the ship reads plainly on the dial. It never swings past
# SPINDLE_LIMIT.
const DIAL_SCALE := 12.0
const SPINDLE_LIMIT := 150.0
# A press closer than this to the hub does not turn the wheel: there the
# angle jumps about with the slightest move.
const HUB_DEAD_ZONE := 8.0
# Seconds of the pulse after the last second in the wedge.
const DONE_SECONDS := 1.0

const DIAL_CENTER := Vector2(CENTER, 80)
const DIAL_RADIUS := 48.0
const WHEEL_CENTER := Vector2(CENTER, 218)
const WHEEL_RADIUS := 44.0
const HANDLE_REACH := 56.0
const SPOKES := 8
const ARROW_RADIUS := 64.0

# Brass and wood from tools/liahona_sprites.py, so the dial matches the
# Liahona's sprite.
const BRASS_DARK := Color("4a2a14")
const BRASS_SHADE := Color("96601f")
const BRASS := Color("bd862c")
const BRASS_LIGHT := Color("d9a940")
const BRASS_SHINE := Color("fbeaa8")
const FACE := Color("2e1c0e")
const SPINDLE := Color("d8d3c0")
const SPINDLE_TIP := Color("fffbe8")
const WOOD_DARK := Color("45220f")
const WOOD := Color("7f4422")
const WOOD_LIGHT := Color("9c5a2e")
const WOOD_SHINE := Color("b8743e")
const GLOW := Color(1.0, 0.92, 0.55)

const DONE_SOUND := preload("res://audio/sfx/craft_success.wav")

var target := 0.0
var progress := 0.0

var _ship: ShipSway
# Without a ship (a test), the board steers this instead.
var _heading := 0.0
# The wheel's turn from center, in radians, and the ship's turn now, in
# degrees a second.
var _wheel := 0.0
var _rate := 0.0
var _dragging := false
var _last_angle := 0.0
var _time := 0.0
# Seconds since finishing, or negative before.
var _done_time := -1.0
var _sound: AudioStreamPlayer

func _ready() -> void:
	_sound = AudioStreamPlayer.new()
	_sound.stream = DONE_SOUND
	_sound.bus = GameSettings.SFX
	add_child(_sound)

func reset() -> void:
	target = float(config.get("target", 0.0))
	progress = 0.0
	_done_time = -1.0
	_dragging = false
	_ship = get_tree().get_first_node_in_group(ShipSway.GROUP) as ShipSway
	if _ship:
		_ship.stop_turning()
		_heading = _ship.heading
	_wheel = 0.0
	_rate = 0.0
	queue_redraw()

func heading() -> float:
	return _ship.heading if _ship else _heading

func is_aligned() -> bool:
	return absf(heading() - target) <= WEDGE_DEGREES

# How fast the wheel asks the ship to turn, in degrees a second.
func _commanded_rate() -> float:
	var turned := rad_to_deg(_wheel)
	if absf(turned) <= CENTER_DEGREES:
		return 0.0
	return (turned - signf(turned) * CENTER_DEGREES) / WHEEL_PER_RATE

func _process(delta: float) -> void:
	_time += delta
	# Settling: after finishing, or let go near center.
	if _done_time >= 0.0 or (not _dragging and absf(rad_to_deg(_wheel)) <= CENTER_SNAP_DEGREES):
		_wheel = move_toward(_wheel, 0.0, deg_to_rad(SETTLE_DEGREES_PER_SECOND) * delta)
	var wanted := 0.0 if _done_time >= 0.0 else _commanded_rate()
	_rate = move_toward(_rate, wanted, HELM_RESPONSE * delta)
	var now := clampf(heading() + _rate * delta, -ShipSway.MAX_HEADING, ShipSway.MAX_HEADING)
	if absf(now) >= ShipSway.MAX_HEADING:
		_rate = 0.0
	if _ship:
		_ship.heading = now
	else:
		_heading = now
	if _done_time >= 0.0:
		_done_time += delta
		if _done_time >= DONE_SECONDS and _done_time - delta < DONE_SECONDS:
			finished.emit()
	elif is_aligned():
		progress = minf(progress + delta / ALIGN_SECONDS, 1.0)
		if progress >= 1.0:
			_done_time = 0.0
			_dragging = false
			_sound.play()
	else:
		progress = maxf(progress - delta / DRAIN_SECONDS, 0.0)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if is_emulated(event) or _done_time >= 0.0:
		return
	if is_press(event):
		var at := point_of(event)
		_dragging = event.is_pressed() and at.distance_to(WHEEL_CENTER) > HUB_DEAD_ZONE
		if _dragging:
			_last_angle = (at - WHEEL_CENTER).angle()
		accept_event()
	elif is_drag(event) and _dragging:
		var at := point_of(event)
		if at.distance_to(WHEEL_CENTER) <= HUB_DEAD_ZONE:
			return
		var angle := (at - WHEEL_CENTER).angle()
		var limit := deg_to_rad(WHEEL_LIMIT)
		_wheel = clampf(_wheel + wrapf(angle - _last_angle, -PI, PI), -limit, limit)
		_last_angle = angle
		accept_event()

# --- Drawing ---

# A direction clockwise from straight up, as the dial reads.
static func _dial_dir(degrees: float) -> Vector2:
	var a := deg_to_rad(degrees)
	return Vector2(sin(a), -cos(a))

func _draw() -> void:
	_draw_dial()
	_draw_wheel()
	if _done_time < 0.0:
		_draw_turn_arrow()

func _draw_dial() -> void:
	var c := DIAL_CENTER
	var r := DIAL_RADIUS
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	# The bow, above the dial: the way the ship points.
	var bow_tip := c + Vector2(0, -r - 16)
	draw_colored_polygon(PackedVector2Array([bow_tip, bow_tip + Vector2(-6, 9), bow_tip + Vector2(6, 9)]), INK)

	# Progress ring, outside the rim.
	draw_arc(c, r + 6, 0, TAU, 64, OUTLINE, 1.0)
	if progress > 0.0:
		var glow := GLOW
		draw_arc(c, r + 6, -PI / 2, -PI / 2 + TAU * progress, 64, glow, 3.0)

	# The brass rim and the dark face.
	draw_circle(c, r + 2, BRASS_DARK)
	draw_circle(c, r, BRASS)
	draw_arc(c, r - 1, PI * 1.1, PI * 1.6, 24, BRASS_LIGHT, 2.0)
	draw_circle(c, r - 5, BRASS_SHADE)
	draw_circle(c, r - 8, FACE)
	for i in 24:
		var dir := _dial_dir(i * 15.0)
		var inner := r - 12.0 if i % 6 == 0 else r - 10.0
		draw_line(c + dir * inner, c + dir * (r - 8), BRASS_LIGHT if i % 6 == 0 else BRASS_SHADE, 1.0)

	# The wedge at the top: straight ahead.
	var half := WEDGE_DEGREES * DIAL_SCALE
	var wedge := PackedVector2Array([c])
	for i in 9:
		wedge.append(c + _dial_dir(lerpf(-half, half, i / 8.0)) * (r - 9))
	var aligned := is_aligned()
	var wedge_color := GLOW
	wedge_color.a = 0.65 + 0.3 * pulse if aligned else 0.2 + 0.15 * pulse
	if _done_time >= 0.0:
		wedge_color.a = 0.95
	draw_colored_polygon(wedge, wedge_color)

	# The spindle, pointing the way to go. It trembles a little, alive.
	var swing := clampf((target - heading()) * DIAL_SCALE, -SPINDLE_LIMIT, SPINDLE_LIMIT)
	swing += sin(_time * 1.7) * 1.2 + sin(_time * 4.3) * 0.5
	var dir := _dial_dir(swing)
	var side := Vector2(-dir.y, dir.x)
	var tip := c + dir * (r - 13)
	var tail := c - dir * 10
	draw_colored_polygon(PackedVector2Array([tip, c + side * 2.5, tail, c - side * 2.5]), SPINDLE)
	draw_line(c, tip, SPINDLE_TIP, 1.0)
	draw_circle(c, 4, BRASS_LIGHT)
	draw_circle(c, 2, BRASS_DARK)

	# Done: a ring of light swells out from the dial and fades.
	if _done_time >= 0.0:
		var t := clampf(_done_time / DONE_SECONDS, 0.0, 1.0)
		var ring := GLOW
		ring.a = 1.0 - t
		draw_arc(c, r + 6 + 18 * t, 0, TAU, 64, ring, 3.0 * (1.0 - t) + 1.0)

func _draw_wheel() -> void:
	var c := WHEEL_CENTER
	var r := WHEEL_RADIUS
	var glow_handles := _done_time < 0.0 and not is_aligned()
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	# Spoke 0 is the king spoke, straight up when the wheel is centered.
	var up := _wheel - PI / 2
	for i in SPOKES:
		var dir := Vector2.from_angle(up + TAU * i / SPOKES)
		if glow_handles:
			var glow := GLOW
			glow.a = 0.25 + 0.3 * pulse
			draw_circle(c + dir * (HANDLE_REACH - 2), 6.5, glow)
		# Spoke inside the rim, and the turned handle beyond it.
		draw_line(c + dir * 8, c + dir * (r - 3), WOOD_DARK, 5.0)
		draw_line(c + dir * 8, c + dir * (r - 3), WOOD_LIGHT, 3.0)
		draw_line(c + dir * (r + 3), c + dir * (HANDLE_REACH - 3), WOOD_DARK, 6.0)
		draw_line(c + dir * (r + 3), c + dir * (HANDLE_REACH - 3), WOOD_SHINE, 4.0)
		if i == 0:
			# The king spoke: a brass band round the handle, and a brass knob.
			draw_line(c + dir * (r + 5), c + dir * (r + 8), BRASS_DARK, 7.0)
			draw_line(c + dir * (r + 5.5), c + dir * (r + 7.5), BRASS_LIGHT, 6.0)
			draw_circle(c + dir * (HANDLE_REACH - 2), 4.5, BRASS_DARK)
			draw_circle(c + dir * (HANDLE_REACH - 2), 3.5, BRASS_LIGHT)
			draw_circle(c + dir * (HANDLE_REACH - 2) + Vector2(-1, -1), 1.2, BRASS_SHINE)
		else:
			draw_circle(c + dir * (HANDLE_REACH - 2), 3.5, WOOD_DARK)
			draw_circle(c + dir * (HANDLE_REACH - 2), 2.5, WOOD_SHINE)
	# The rim, over the spokes.
	draw_arc(c, r, 0, TAU, 64, WOOD_DARK, 8.0)
	draw_arc(c, r, 0, TAU, 64, WOOD, 6.0)
	draw_arc(c, r + 1.5, up, up + TAU, 64, WOOD_LIGHT, 1.0)
	# Brass bands on the rim where the spokes meet it, so it shows turning.
	for i in SPOKES:
		var a := up + TAU * i / SPOKES
		draw_arc(c, r, a - 0.05, a + 0.05, 4, BRASS, 6.0)
	# The hub.
	draw_circle(c, 10, BRASS_DARK)
	draw_circle(c, 9, BRASS)
	draw_circle(c, 5, BRASS_SHADE)
	draw_circle(c + Vector2(-3, -3), 2, BRASS_SHINE)

# Over the top of the wheel, curving the way to turn it: toward the course
# while the ship is not coming onto it, back to center once it will be there
# soon (or is), and not at all when the wheel is already right.
func _draw_turn_arrow() -> void:
	var off := target - heading()
	var ahead := target - (heading() + _rate * ARROW_LEAD_SECONDS)
	var turned := rad_to_deg(_wheel)
	var clockwise: bool
	if is_aligned() or signf(ahead) != signf(off):
		if absf(turned) <= CENTER_DEGREES:
			return
		clockwise = turned < 0.0
	else:
		if signf(turned) == signf(off) and absf(turned) > CENTER_DEGREES:
			return
		clockwise = off > 0.0
	var c := WHEEL_CENTER
	var color := INK
	color.a = (0.35 if _dragging else 0.55) + 0.3 * sin(_time * 4.0)
	var from := -PI / 2 - 0.45
	var to := -PI / 2 + 0.45
	draw_arc(c, ARROW_RADIUS, from, to, 24, color, 2.5)
	var end := to if clockwise else from
	var tip := c + Vector2.from_angle(end) * ARROW_RADIUS
	# Along the arc, the way it runs.
	var along := Vector2.from_angle(end + (PI / 2 if clockwise else -PI / 2))
	var out := Vector2.from_angle(end)
	var head := tip + along * 6
	draw_colored_polygon(PackedVector2Array([head, tip - along * 1 + out * 5, tip - along * 1 - out * 5]), color)
