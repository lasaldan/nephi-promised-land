extends Node2D

class_name Prayer

# Nephi prays for guidance: he folds his hands (the first frames of the cast
# rows), and after a moment three glowing dots run out from his feet toward
# the quest's goal. No pathfinding: they head straight there, through trees and
# all. The pray button on the quest plaque calls pray(), as often as the
# player likes. Standing still to pray is the cost; knowing the way is the gain.
#
# The goal comes from whatever the chapter is waiting on. The wait helpers in
# StoryChapter (waitForPlayerNear, waitForPlayerAt, waitForItemAdded,
# arm_trigger) register it while they wait, and a chapter can name one itself
# with setGuidance(). With none registered, an armed one-shot StoryTrigger is
# the goal, and failing that the nearest pickup the backpack will take.

# The cast rows of the LPC sheet, by direction.
const CAST_ROWS := {"up": 0, "left": 1, "down": 2, "right": 3}
# Frames 0 to 2 of a cast row: eyes closed, hands together.
const FOLD_FRAMES := 3
const FOLD_SECONDS := 0.3
# Hands folded, before the first dot shows.
const PRAY_SECONDS := 1.0
# The dots: each starts DOT_START pixels out from his feet (half a tile, clear
# of his body) and runs DOT_DISTANCE pixels further in DOT_SECONDS,
# the next DOT_GAP seconds behind it. Each fades in over its first
# DOT_FADE_IN of the run and out over its last DOT_FADE_OUT.
const DOT_COUNT := 3
const DOT_SECONDS := 0.9
const DOT_GAP := 0.3
const DOT_START := 16.0
const DOT_DISTANCE := 56.0
const DOT_FADE_IN := 0.1
const DOT_FADE_OUT := 0.25
const DOT_RADIUS := 1.5
const DOT_GLOW_RADIUS := 3.5
const DOT_COLOR := Color(1, 1, 1)

var praying := false

# Registered goals, newest last. Each is [token, Callable returning a Vector2
# global position, or null when it has nothing to point at].
var _goals: Array = []
var _next_token := 1
var _direction := Vector2.ZERO
# Seconds since the first dot set out, or negative with no dots showing.
var _dots_time := -1.0

@onready var player: CharacterBody2D = get_parent()

func _ready() -> void:
	# Under Nephi, as if drawn on the ground at his feet.
	show_behind_parent = true
	# Unshaded, so DayNight does not darken them: night is when they help most.
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded

# --- Goals ---

# Point prayers at target until unguide(token). target is a Node2D, a global
# position (Vector2, pixels), a Rect2 (pixels, its center), an Array of
# Node2D (the nearest one still shown), or a Callable returning a position or
# null. The newest goal that still has a position wins.
func guide(target: Variant) -> int:
	var token := _next_token
	_next_token += 1
	_goals.append([token, _resolver(target)])
	return token

func unguide(token: int) -> void:
	for i in _goals.size():
		if _goals[i][0] == token:
			_goals.remove_at(i)
			return

func clear_guidance() -> void:
	_goals.clear()

func _resolver(target: Variant) -> Callable:
	if target is Callable:
		return target
	if target is Vector2:
		return func() -> Variant: return target
	if target is Rect2:
		return func() -> Variant: return (target as Rect2).get_center()
	if target is Array:
		return func() -> Variant: return _nearest(target)
	if target is Node2D:
		return func() -> Variant: return _nearest([target])
	push_warning("Prayer cannot point at %s" % [target])
	return func() -> Variant: return null

# Where a prayer points right now, or null with nowhere to go.
func goal_position() -> Variant:
	for i in range(_goals.size() - 1, -1, -1):
		var spot: Variant = (_goals[i][1] as Callable).call()
		if spot != null:
			return spot
	var trigger: Variant = _nearest(get_tree().get_nodes_in_group(StoryTrigger.GROUP).filter(
			func(t: StoryTrigger) -> bool: return t.one_shot and t.is_waiting()))
	if trigger != null:
		return trigger
	return nearest_pickup()

# The nearest pickup still lying out that the backpack would take now, such
# as the last apple tree with fruit. item_name narrows it to one kind.
func nearest_pickup(item_name: String = "") -> Variant:
	return _nearest(get_tree().get_nodes_in_group(Collectable.GROUP).filter(
			func(pickup: Collectable) -> bool:
				var item: InventoryItem = pickup.item
				return pickup.can_interact() \
						and (item_name.is_empty() or item.name == item_name) \
						and player.can_pick_up(item)))

func _nearest(nodes: Array) -> Variant:
	var best: Variant = null
	var best_distance := INF
	for node in nodes:
		if not is_instance_valid(node) or not (node as CanvasItem).is_visible_in_tree():
			continue
		var spot := center_of(node)
		var distance := spot.distance_to(player.global_position)
		if distance < best_distance:
			best = spot
			best_distance = distance
	return best

# A trigger's middle is its shape's, not its origin.
func center_of(node: Node2D) -> Vector2:
	for child in node.get_children():
		if child is CollisionShape2D:
			return (child as CollisionShape2D).global_position
	return node.global_position

# --- Praying ---

func can_pray() -> bool:
	return not praying and player.controls_enabled and not player.menu_open \
			and goal_position() != null

func pray() -> void:
	if not can_pray():
		return
	praying = true
	StoryState.count("prayers")
	# Facing the camera, the folded hands read as prayer. From the side or
	# behind, the pose is less clear. unfold_hands() turns him back.
	var row := _begin_fold("down")
	for frame in FOLD_FRAMES:
		_show_fold_frame(frame, row)
		if not await _wait(FOLD_SECONDS / FOLD_FRAMES):
			break
	if praying:
		await _wait(PRAY_SECONDS)
	if praying:
		_aim()
		var t := 0.0
		var run := DOT_SECONDS + DOT_GAP * (DOT_COUNT - 1)
		while praying and t < run:
			_aim()
			_dots_time = t
			queue_redraw()
			await get_tree().process_frame
			t += get_process_delta_time()
	_dots_time = -1.0
	queue_redraw()
	unfold_hands()
	praying = false

# The same folded hands, held for a story beat, such as the visions on the
# mountain. No dots. Stays until unfold_hands(). Chapters use
# StoryChapter.startPraying() and stopPraying(). Always facing the camera, as
# in pray(), and he stays that way after: facing and the stand pose are set
# here, not left to his next physics frame, which may not have run yet.
func fold_hands() -> void:
	player.velocity = Vector2.ZERO
	player.facing = "down"
	player.update_blend_positions(Vector2(0, -1))
	var row := _begin_fold("down")
	for frame in FOLD_FRAMES:
		_show_fold_frame(frame, row)
		await get_tree().create_timer(FOLD_SECONDS / FOLD_FRAMES, false).timeout

# Back to the stand pose, facing as before (the tree still holds that way).
func unfold_hands() -> void:
	player.animation_tree.active = true

# Stops him and returns the cast row for direction. The tree would put the
# stand frame back every frame, so it is off until unfold_hands().
func _begin_fold(direction: String) -> int:
	player.play_idle()
	var row: int = CAST_ROWS[direction]
	player.animation_tree.active = false
	return row

func _show_fold_frame(frame: int, row: int) -> void:
	(player.get_node("Sprite2D") as Sprite2D).frame_coords = Vector2i(frame, row)

# Wait, but stop early if a cutscene takes the controls (a chapter beat that
# fired while he prayed). Returns false when the prayer was cut short.
func _wait(seconds: float) -> bool:
	var t := 0.0
	while t < seconds:
		if not player.controls_enabled:
			praying = false
			return false
		await get_tree().process_frame
		t += get_process_delta_time()
	return true

func _aim() -> void:
	if not player.controls_enabled:
		praying = false
		return
	var spot: Variant = goal_position()
	if spot != null and (spot as Vector2).distance_to(global_position) > 1.0:
		_direction = global_position.direction_to(spot)

# The way he faces, from the stand pose's blend position (y is up there).
func _draw() -> void:
	if _dots_time < 0.0 or _direction == Vector2.ZERO:
		return
	for i in DOT_COUNT:
		var run := (_dots_time - i * DOT_GAP) / DOT_SECONDS
		if run <= 0.0 or run >= 1.0:
			continue
		var alpha := 1.0
		if run < DOT_FADE_IN:
			alpha = run / DOT_FADE_IN
		elif run > 1.0 - DOT_FADE_OUT:
			alpha = (1.0 - run) / DOT_FADE_OUT
		# Quick off the start, easing as it nears the end.
		var spot := _direction * (DOT_START + DOT_DISTANCE * ease(run, 0.6))
		var color := DOT_COLOR
		color.a = alpha * 0.3
		draw_circle(spot, DOT_GLOW_RADIUS, color, true, -1.0, true)
		color.a = alpha
		draw_circle(spot, DOT_RADIUS, color, true, -1.0, true)
