class_name ShipSway
extends Node2D

# Rocks the ship as if it rides over waves in a storm. Put it on the Ship node.
# As a wave passes under, the whole ship rises and falls (heave) and its bow
# tips up and then down (roll, a rotation about the middle of the ship). Roll
# follows the wave's slope, so the ship is steepest halfway up a wave and level
# at the crest and in the trough, like a real hull riding a swell.
#
# The project stretches in canvas_items mode: the window draws the world at its
# own resolution and only scales the art up. So a rotated ship is drawn with
# real screen pixels. Each art pixel becomes a slightly tilted square, still
# crisp (nearest filtering), not blurred. Set style to HEAVE_ONLY to compare
# with plain bobbing.
#
# sea slides it between two swells, Calm and Storm, each with its own roll,
# heave and period. Like the rain it is saved with each chapter.
#
# Whoever stands on the deck (the player, and anything in carry) is moved with
# it, so they don't float while the ship drops away under them. They stay
# upright, as if keeping their feet.
#
# Not a @tool: the sway would move the ship in the editor and get saved into
# the scene. Tweak it while the game runs, in the Remote scene tree.

enum Style { ROLL_AND_HEAVE, HEAVE_ONLY }

@export var style := Style.ROLL_AND_HEAVE
## 0 is the calm swell, 1 the storm, and anything between blends the two.
## Chapters ease it with set_sea() (StoryChapter.setSea()).
@export_range(0.0, 1.0, 0.01) var sea := 0.0:
	set(value):
		sea = clampf(value, 0.0, 1.0)
## Scales the whole motion on top of sea. 0 holds the ship still.
@export_range(0.0, 3.0, 0.01, "or_greater") var amount := 1.0
## Rise and fall in whole art pixels, the way the rest of the art moves. Off
## is smooth, in screen pixels.
@export var snap_heave := false
## Where the ship pivots, in its own coordinates. Zero picks the middle of
## its tiles.
@export var pivot := Vector2.ZERO
## Others carried with the deck when standing on it. The player always is.
@export var carry: Array[Node2D] = []

# Each end of the sea slider. roll is the steepest the bow tips, in degrees;
# heave how far the ship rises and falls, in art pixels; period the seconds for
# one wave to pass under it.
@export_group("Calm")
@export_range(0.0, 15.0, 0.1) var calm_roll := 2.5
@export_range(0.0, 32.0, 0.5) var calm_heave := 7.5
@export_range(1.0, 20.0, 0.1) var calm_period := 3.0
@export_group("Storm")
@export_range(0.0, 15.0, 0.1) var storm_roll := 3.0
@export_range(0.0, 32.0, 0.5) var storm_heave := 15.0
@export_range(1.0, 20.0, 0.1) var storm_period := 7.0

const GROUP := "ship_sway"

var _base: Transform2D
var _pivot: Vector2
# The ship's tiles, in its own coordinates. Who stands inside is carried.
var _bounds: Rect2
var _last: Transform2D
# How far through the wave the ship is, in radians. It advances by the
# current period each frame rather than being worked out from the clock, so
# changing the period slows or quickens the waves without a jump.
var _phase := 0.0
var _phase2 := 1.1
var _tween: Tween

func _ready() -> void:
	add_to_group(GROUP)
	_base = transform
	_bounds = _tile_bounds()
	_pivot = pivot if pivot != Vector2.ZERO else _bounds.get_center()
	_last = global_transform

# Ease the sea from calm (0) to storm (1) over seconds. 0 seconds switches at
# once.
func set_sea(target: float, seconds := 5.0) -> void:
	if _tween:
		_tween.kill()
	if seconds <= 0.0:
		sea = target
		return
	_tween = create_tween()
	_tween.tween_property(self, "sea", clampf(target, 0.0, 1.0), seconds) \
			.set_trans(Tween.TRANS_SINE)
	await _tween.finished

func roll() -> float:
	return lerpf(calm_roll, storm_roll, sea)

func heave() -> float:
	return lerpf(calm_heave, storm_heave, sea)

func period() -> float:
	return lerpf(calm_period, storm_period, sea)

# In physics frames, so the player's own movement and the deck's agree.
func _physics_process(delta: float) -> void:
	# A second, smaller and quicker wave out of step with the first, so the
	# motion never quite repeats. Each keeps its own phase, so neither jumps
	# when it wraps. height is the sea under the ship, slope its tilt there.
	var step := delta * TAU / period()
	_phase = fmod(_phase + step, TAU)
	_phase2 = fmod(_phase2 + step * 1.73, TAU)
	var height := 0.8 * sin(_phase) + 0.2 * sin(_phase2)
	var slope := 0.8 * cos(_phase) + 0.2 * 1.73 * cos(_phase2)
	slope /= 0.8 + 0.2 * 1.73

	var rise := -heave() * amount * height
	if snap_heave:
		rise = roundf(rise)
	var angle := 0.0
	if style == Style.ROLL_AND_HEAVE:
		angle = deg_to_rad(roll()) * amount * slope

	var tilt := Transform2D(0.0, _pivot) * Transform2D(angle, Vector2.ZERO) \
			* Transform2D(0.0, -_pivot)
	var next := _base * tilt
	next.origin.y += rise
	transform = next
	_carry()

# Moves everyone on deck by however the deck moved since last frame.
func _carry() -> void:
	var moved := global_transform * _last.affine_inverse()
	var riders: Array[Node2D] = carry.duplicate()
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node2D and node not in riders:
			riders.append(node)
	for rider in riders:
		if is_instance_valid(rider) and _bounds.has_point(_last.affine_inverse() * rider.global_position):
			rider.global_position = moved * rider.global_position
	_last = global_transform

func _notification(what: int) -> void:
	# The chapter is over: leave the ship level and where it was.
	if what == NOTIFICATION_DISABLED and is_node_ready():
		transform = _base
		_last = global_transform

func _tile_bounds() -> Rect2:
	var bounds := Rect2()
	var found := false
	var to_ship := global_transform.affine_inverse()
	for layer: TileMapLayer in find_children("*", "TileMapLayer", true, false):
		var used := layer.get_used_rect()
		if used.size == Vector2i.ZERO or layer.tile_set == null:
			continue
		var tile := Vector2(layer.tile_set.tile_size)
		var to_layer := to_ship * layer.global_transform
		for corner in [used.position, used.end, Vector2i(used.position.x, used.end.y), Vector2i(used.end.x, used.position.y)]:
			var p: Vector2 = to_layer * (Vector2(corner) * tile)
			if not found:
				bounds = Rect2(p, Vector2.ZERO)
				found = true
			else:
				bounds = bounds.expand(p)
	return bounds
