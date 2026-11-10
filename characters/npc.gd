extends CharacterBody2D

class_name Npc

# Anyone the story can direct: people (characters/person.tscn and the cast
# scenes that inherit it) and animals (characters/animals/). Three layers,
# from the top:
#   - Orders from a chapter: go_to(), hold(), pose(), release(). An order
#     owns them until release().
#   - A habit (characters/habits/): what they do when the story is not
#     directing them. Ticked every physics frame unless held.
#   - The walk: one target at a time, followed along a navigation path
#     (world/navigation/world_navigation.gd) and steered around anyone else
#     walking (avoidance). With no navigation in the world, they walk
#     straight at the target.

# Sent when a go_to() order finishes. reached is false when they got stuck,
# or when another order, release(), or set_habit() cut the walk short.
signal arrived(reached: bool)

const TILE := 32.0
# Pixels per second at walk_speed 1.0.
const SPEED := 10.0
const FACINGS: Array[String] = ["up", "right", "down", "left"]

# Optional: the bunny animates its own sprite and has no tree.
@onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree")
@onready var sprite: Node2D = get_node_or_null("Sprite2D")
# The direction they are walking, scaled by speed. The animation tree reads
# it (and velocity) to pick the walk state. A chapter can still set it
# directly for a timed walk (StoryChapter.walk()).
@export var input_vector := Vector2.ZERO
@export var immovable := false
# A pose, not a step: "up", "down", "left" or "right" holds them faced that
# way. "" lets the walk direction decide.
@export var facing := ""
# Plays the work cycle (rows 4-7 of the sheet) instead of the stand pose while
# they stand faced one way. Walking, hold(), set_habit() and dialogue clear it.
#   sam.hold("up")
#   sam.working = true
var working := false

# Temperament: how this character carries out any habit. The habit itself
# (Idle, Meander, Patrol, ...) is chosen per chapter.
@export_group("Habits")
## Walk pace. 1.0 is SPEED pixels per second.
@export var walk_speed := 1.0
## Seconds a habit stands still between moves. Each pause is a random time in this range.
@export var pause_min := 1.5
@export var pause_max := 4.0
## Chance a pause includes turning to look around.
@export_range(0.0, 1.0, 0.05) var look_around_chance := 0.4
## Stand still while a dialogue balloon is open, and pick the habit back up after.
@export var pauses_for_dialogue := true

@export_group("Navigation")
## Steer around other walkers and the player instead of bumping into them.
@export var avoidance := true
## Half their width, for avoidance. Their collision diamond is about 16 wide.
@export var body_radius := 8.0

@export_group("Talking")
## How far Nephi can stand from them and still talk, in pixels. More for
## animals behind a fence.
@export var talk_reach := 32.0

var habit: Habit
var _held := false
var _dialogue_paused := false
var _agent: NavigationAgent2D

# --- Poses: frames of the sheet held with the animation tree off. ---

# Each pose names the sheet rows it uses (by facing) and the frames it steps
# through to get there. The last frame is held.
#   sit*   the sit rows of a full (54-row) Universal LPC sheet. CharGen sheets
#          stop at row 20 and cannot sit.
#   kneel  the start of the hurt row, which only faces south.
#   pray   the start of the cast rows: hands folding.
const SIT_ROWS := {"up": 30, "left": 31, "down": 32, "right": 33}
const POSES := {
	"sit": {"rows": SIT_ROWS, "frames": [2]},
	"sit_lean": {"rows": SIT_ROWS, "frames": [1]},
	"sit_ground": {"rows": SIT_ROWS, "frames": [0]},
	"kneel": {"rows": {"down": 20}, "frames": [0, 1, 2], "seconds": 0.45},
	"pray": {"rows": {"up": 0, "left": 1, "down": 2, "right": 3}, "frames": [0, 1, 2], "seconds": 0.3},
}
var _pose := ""
var _pose_frame := 0
# Bumped by every pose change, so frames still stepping stop when another
# order cuts in.
var _pose_token := 0


func _ready() -> void:
	_fit_sheet()
	# A balloon's picture of the speaker: not someone in the world.
	if get_meta("portrait", false):
		return
	add_to_group("npcs")
	add_to_group(Interaction.GROUP)
	_agent = NavigationAgent2D.new()
	_agent.name = "NavigationAgent"
	_agent.path_desired_distance = 4.0
	_agent.target_desired_distance = 2.0
	_agent.radius = body_radius
	_agent.neighbor_distance = 96.0
	_agent.avoidance_enabled = avoidance
	_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(_agent)


# A sheet's row count from its height, so a cast scene only has to name the
# texture. Universal LPC sheets are 64-pixel frames, 13 across.
func _fit_sheet() -> void:
	var sheet := sprite as Sprite2D
	if sheet == null or sheet.texture == null or sheet.hframes != 13:
		return
	sheet.vframes = maxi(1, sheet.texture.get_height() / 64)


func _physics_process(delta: float) -> void:
	if _agent == null:
		return
	_update_pass_through()
	if immovable:
		if is_walking():
			_stop_walk(false)
		return
	if habit != null and not _held and not _dialogue_paused:
		habit.tick(delta)
	_update_walk(delta)

	if is_posed():
		input_vector = Vector2.ZERO
		velocity = Vector2.ZERO
		_show_pose_frame()
		return

	if FACINGS.has(facing):
		# Pose only. input_vector is the walk state's "still moving" signal,
		# so writing the facing direction there plays the walk cycle in place.
		var face_vector := vector_for_facing(facing)
		input_vector = Vector2.ZERO
		velocity = Vector2.ZERO
		update_blend_positions(Vector2(face_vector.x, -face_vector.y))
		_snap_to("WorkState" if working and _has_work_state() else "StandState")
		return
	if input_vector == Vector2.ZERO:
		# move_and_slide() with no velocity still pushes the body out of
		# anything overlapping it, so the player walking into them would
		# shove them along.
		velocity = Vector2.ZERO
		return

	update_blend_positions(Vector2(input_vector.x, -input_vector.y))
	var wanted := input_vector * SPEED
	if is_walking() and _agent.avoidance_enabled and not is_passing_through():
		# Moved in _on_velocity_computed once avoidance has had its say.
		_agent.velocity = wanted
	else:
		velocity = wanted
		move_and_slide()


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if not is_walking() or is_posed() or FACINGS.has(facing):
		return
	velocity = safe_velocity
	move_and_slide()


func update_blend_positions(direction_vector: Vector2) -> void:
	if animation_tree == null:
		return
	animation_tree.set("parameters/StateMachine/MoveState/WalkState/blend_position", direction_vector)
	animation_tree.set("parameters/StateMachine/MoveState/StandState/blend_position", direction_vector)
	if _has_work_state():
		animation_tree.set("parameters/StateMachine/MoveState/WorkState/blend_position", direction_vector)

# Calling start() again while already there would restart the clip every
# physics frame.
func _snap_to(state: String) -> void:
	if animation_tree == null:
		return
	var playback := animation_tree.get("parameters/StateMachine/MoveState/playback") as AnimationNodeStateMachinePlayback
	if playback and playback.get_current_node() != state:
		playback.start(state)

# People have a WorkState. The animal scenes do not.
func _has_work_state() -> bool:
	if animation_tree == null or not animation_tree.tree_root is AnimationNodeBlendTree:
		return false
	var root := (animation_tree.tree_root as AnimationNodeBlendTree).get_node("StateMachine") as AnimationNodeStateMachine
	var move := root.get_node("MoveState") as AnimationNodeStateMachine if root and root.has_node("MoveState") else null
	return move != null and move.has_node("WorkState")


# --- Talking (Interaction): their talk_<name> title in story/main.dialogue. ---

func interact_kind() -> String:
	return "talk"

func interact_point() -> Vector2:
	return global_position

func interact_reach() -> float:
	return talk_reach

func can_interact() -> bool:
	if not is_visible_in_tree() or is_vanished():
		return false
	# On a scripted walk, so they would walk off mid-sentence.
	if _held and is_walking():
		return false
	return SmallTalk.has_title(SmallTalk.title_for(self)) and SmallTalk.free_to_talk(get_tree())

func interact(_player: Node) -> void:
	await SmallTalk.find(get_tree()).talk_to(self)


# --- Scripted orders. These pause the habit until release(). ---

# Walk to a tile (the same coordinates as a characters list "start"), then
# hold there. Returns right away; await arrived, or use the chapter's
# walkTo(), to wait for it. Returns this NPC so then_face() can be chained.
# With pass_through, someone standing in the way for a moment cannot stop
# them: they walk through. On by default so the player can never stall the
# story by standing in a doorway.
#   lehi.go_to(Vector2(-10, 7))
#   lehi.go_to(Vector2(-10, 7), 2).then_face("up")
func go_to(tile: Vector2, speed := 1.0, stuck_seconds := 1.5, pass_through_people := true) -> Npc:
	hold()
	_start_walk(tile * TILE, speed, stuck_seconds, true, pass_through_people)
	return self

# After the current go_to() ends, turn to face something: "up"/"down"/
# "left"/"right", a tile (Vector2), or a node. Applies even if they got stuck
# short of the spot. With no walk in progress it turns them now.
#   sam.go_to(Vector2(-8, 6)).then_face(lehi)
func then_face(target: Variant) -> Npc:
	if is_walking() and _walk.order:
		_walk.face = target
	else:
		hold()
		_face(target)
	return self

func _face(target: Variant) -> void:
	if target is String:
		facing = target
	elif target is Vector2:
		facing = facing_for(target * TILE - position)
	elif target is Node2D and is_instance_valid(target):
		face_toward(target)

# Stop whatever they are doing and stand. With a direction, face it.
#   sam.hold("left")
func hold(direction := "") -> void:
	end_pass_through_when_clear()
	working = false
	clear_pose()
	if is_walking():
		_stop_walk(false)
	_held = true
	input_vector = Vector2.ZERO
	if direction != "":
		facing = direction

# Hand them back to their habit, which picks up from where they now stand.
func release() -> void:
	if not _held:
		return
	if is_walking():
		_stop_walk(false)
	_held = false
	input_vector = Vector2.ZERO
	clear_pose()
	if habit != null:
		habit.resume()

func is_held() -> bool:
	return _held

# Replace the habit and start it now. Also ends any hold, since a new habit
# means "go do this". null leaves them standing with no habit.
#   lehi.set_habit(Meander.new(2))
func set_habit(new_habit: Habit) -> void:
	if new_habit != null and new_habit.npc != null and new_habit.npc != self and is_instance_valid(new_habit.npc):
		push_error("%s: that habit already belongs to %s. Give each character its own." % [name, new_habit.npc.name])
		return
	if is_walking():
		_stop_walk(false)
	_held = false
	working = false
	clear_pose()
	input_vector = Vector2.ZERO
	var old := habit
	habit = null
	if old != null:
		old.stop()
	habit = new_habit
	if habit != null:
		habit.npc = self
		habit.start()

# Called by the chapter around each dialogue balloon, through the npcs group.
func pause_for_dialogue(paused: bool) -> void:
	if not pauses_for_dialogue or paused == _dialogue_paused:
		return
	_dialogue_paused = paused
	if paused:
		working = false
		# Orders keep going. Only a habit's own walk stops.
		if is_walking() and not _walk.order:
			_stop_walk(false)
	elif habit != null and not _held:
		habit.resume()


# --- Poses ---

# Take a pose from POSES and stay in it, held, until the story moves them on:
# hold(), go_to(), set_habit() and release() all end it. Steps through the
# pose's frames and returns once they are in it. Returns false, and leaves
# them standing, when their sheet has no rows for it. Facing is kept where
# the pose has a row for it; kneel only faces south.
#   await laman.pose("kneel")
#   wife.pose("sit", "down")
#   await lehi.pose("pray")
# With keep_habit, the pose does not hold them (for habits such as Station).
func pose(pose_name: String, direction := "", keep_habit := false) -> bool:
	if not can_pose(pose_name):
		push_warning("%s has no %s rows in their sheet." % [name, pose_name])
		return false
	if not keep_habit:
		hold()
	var rows: Dictionary = POSES[pose_name].rows
	if direction != "":
		facing = direction
	if not rows.has(facing):
		facing = "down" if rows.has("down") else rows.keys()[0]
	working = false
	if animation_tree:
		animation_tree.active = false
	_pose = pose_name
	_pose_token += 1
	var token := _pose_token
	var frames: Array = POSES[pose_name].frames
	var step: float = POSES[pose_name].get("seconds", 0.0) / frames.size()
	for i in frames.size():
		_pose_frame = frames[i]
		_show_pose_frame()
		if i < frames.size() - 1 and step > 0.0:
			await get_tree().create_timer(step, false).timeout
			if token != _pose_token:
				return true
	return true

# Out of the pose. With slowly, back through its frames first (getting up
# off their knees, unfolding hands). Still held, facing as before.
#   await laman.end_pose(true)
func end_pose(slowly := false) -> void:
	if not is_posed():
		return
	if slowly:
		_pose_token += 1
		var token := _pose_token
		var frames: Array = POSES[_pose].frames
		var step: float = POSES[_pose].get("seconds", 0.0) / frames.size()
		for i in range(frames.find(_pose_frame) - 1, -1, -1):
			await get_tree().create_timer(step, false).timeout
			if token != _pose_token:
				return
			_pose_frame = frames[i]
			_show_pose_frame()
		await get_tree().create_timer(step, false).timeout
		if token != _pose_token:
			return
	clear_pose()

# Back on their feet at once. Does nothing if they are not posed.
func clear_pose() -> void:
	if not is_posed():
		return
	_pose_token += 1
	_pose = ""
	if animation_tree:
		animation_tree.active = true

func is_posed(pose_name := "") -> bool:
	return _pose != "" if pose_name == "" else _pose == pose_name

func is_sitting() -> bool:
	return _pose.begins_with("sit")

func can_pose(pose_name: String) -> bool:
	var sheet := sprite as Sprite2D
	if not POSES.has(pose_name) or animation_tree == null or sheet == null:
		return false
	return sheet.vframes > (POSES[pose_name].rows.values() as Array).max()

# Every frame while posed, so turning them (facing = ...) turns them in place.
func _show_pose_frame() -> void:
	var rows: Dictionary = POSES[_pose].rows
	var row: int = rows.get(facing, rows.values()[0])
	var sheet := sprite as Sprite2D
	if sheet and sheet.frame_coords != Vector2i(_pose_frame, row):
		sheet.frame_coords = Vector2i(_pose_frame, row)

# The familiar names, for chapter scripts.
func sit(direction := "", pose_name := "sit") -> bool:
	return await pose(pose_name, direction)

func kneel() -> void:
	await pose("kneel")

func rise() -> void:
	await end_pose(true)

func fold_hands() -> void:
	await pose("pray", facing if FACINGS.has(facing) else "down")

func unfold_hands() -> void:
	clear_pose()


# --- Small effects ---

# Twitch in place by a pixel or two for seconds. Only the sprite moves, so
# they keep their tile.
#   await laman.shake(1.0)
func shake(seconds := 1.0) -> void:
	var rest: Vector2 = sprite.offset
	var left := seconds
	while left > 0.0:
		sprite.offset = rest + Vector2(randi_range(-2, 2), randi_range(-1, 1))
		await get_tree().create_timer(0.05, false).timeout
		left -= 0.05
	sprite.offset = rest

# Gone from the world for now, as into a tent: hidden, no habit, and no
# collision. reappear() brings them back.
func vanish() -> void:
	if is_vanished():
		return
	set_habit(null)
	_end_pass_through()
	_saved_layers = Vector2i(collision_layer, collision_mask)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

# Back where they now stand, held. Give them a habit or an order after.
#   wife.position = door * 32
#   wife.reappear()
func reappear() -> void:
	if not is_vanished():
		return
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	collision_layer = _saved_layers.x
	collision_mask = _saved_layers.y
	_saved_layers = Vector2i(-1, -1)
	hold()

func is_vanished() -> bool:
	return _saved_layers.x != -1

var _saved_layers := Vector2i(-1, -1)


# --- Passing through. A walk caught on someone for PASS_THROUGH_SECONDS
# carries on through them, so nobody can stall the story by standing in the
# way. Their collision is off until their body overlaps nothing again, so
# they never end up standing inside anyone. ---

const PASS_THROUGH_SECONDS := 0.5
var _through_layers := Vector2i(-1, -1)
var _end_through_pending := false

func pass_through() -> void:
	_end_through_pending = false
	if is_passing_through() or is_vanished():
		return
	_through_layers = Vector2i(collision_layer, collision_mask)
	collision_layer = 0
	collision_mask = 0

func is_passing_through() -> bool:
	return _through_layers.x != -1

func end_pass_through_when_clear() -> void:
	if is_passing_through():
		_end_through_pending = true

func _update_pass_through() -> void:
	if not _end_through_pending:
		return
	if not is_passing_through():
		_end_through_pending = false
	elif _bodies_at(position, _through_layers.y, 1).is_empty():
		_end_pass_through()

func _end_pass_through() -> void:
	_end_through_pending = false
	if not is_passing_through():
		return
	collision_layer = _through_layers.x
	collision_mask = _through_layers.y
	_through_layers = Vector2i(-1, -1)


# --- Used by habits. ---

func current_tile() -> Vector2:
	return position / TILE

func is_walking() -> bool:
	return _walk.target != Vector2.INF

# How the last habit walk ended. Habits read it after is_walking() goes false.
var last_walk_reached := false

# A habit's walk. It never sends arrived; the habit checks is_walking() and
# last_walk_reached instead. speed below 0 is their own walk_speed.
#   npc.habit_walk_to(spot, 3.0, true)
func habit_walk_to(tile_position: Vector2, stuck_seconds := 1.5, pass_through_people := false, speed := -1.0) -> void:
	_start_walk(tile_position * TILE, walk_speed if speed < 0.0 else speed, stuck_seconds, false, pass_through_people)

func stop_walking() -> void:
	if is_walking():
		_stop_walk(true)

# True when they could walk to the tile. With navigation, the tile has to be
# on the walkable area and joined to where they stand; without, the straight
# line has to be clear.
func can_reach(tile_position: Vector2) -> bool:
	var target := tile_position * TILE
	if not _has_navigation():
		return not test_move(global_transform, target - position)
	var map := get_world_2d().navigation_map
	var global_target := global_position + (target - position)
	var snapped := NavigationServer2D.map_get_closest_point(map, global_target)
	if snapped.distance_to(global_target) > 4.0:
		return false
	var path := NavigationServer2D.map_get_path(map, global_position, snapped, true)
	return not path.is_empty() and path[path.size() - 1].distance_to(snapped) < 4.0

# True when their body, standing at the tile, would overlap something solid.
func overlaps_at(tile_position: Vector2) -> bool:
	return not _bodies_at(tile_position * TILE, collision_mask, 1).is_empty()

# What their body, standing at a position (in the parent's space), would
# overlap on mask: up to max_results of the colliders.
func _bodies_at(at: Vector2, mask: int, max_results: int) -> Array[Object]:
	var hits: Array[Object] = []
	var body := global_transform
	body.origin += at - position
	var query := PhysicsShapeQueryParameters2D.new()
	query.collision_mask = mask
	query.exclude = [get_rid()]
	var space := get_world_2d().direct_space_state
	for child in get_children():
		var shape: Shape2D = null
		if child is CollisionShape2D and not child.disabled:
			shape = child.shape
		elif child is CollisionPolygon2D and not child.disabled:
			var hull := ConvexPolygonShape2D.new()
			hull.set_point_cloud(child.polygon)
			shape = hull
		if shape == null:
			continue
		query.shape = shape
		query.transform = body * child.transform
		for hit in space.intersect_shape(query, max_results):
			hits.append(hit["collider"])
		if hits.size() >= max_results:
			break
	return hits

func random_pause() -> float:
	return randf_range(minf(pause_min, pause_max), maxf(pause_min, pause_max))

# Something small to do while standing. Habits call it once during most
# pauses. Animals override this to graze.
func fidget() -> void:
	if randf() < look_around_chance:
		turn_quarter()

func turn_quarter() -> void:
	var current := FACINGS.find(facing)
	if current == -1:
		current = 2
	var step := 1 if randf() < 0.5 else -1
	facing = FACINGS[posmod(current + step, FACINGS.size())]

# Face a node along the stronger axis. Does not hold them.
func face_toward(target: Node2D) -> void:
	facing = facing_for(target.global_position - global_position)

static func facing_for(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "right" if direction.x > 0.0 else "left"
	return "down" if direction.y > 0.0 else "up"

static func vector_for_facing(direction: String) -> Vector2:
	match direction:
		"down": return Vector2.DOWN
		"up": return Vector2.UP
		"left": return Vector2.LEFT
		"right": return Vector2.RIGHT
	return Vector2.ZERO


# --- The walk itself ---

# target is in the parent's space, as position is. order: a go_to(), which
# sends arrived. face: what then_face() asked for.
var _walk := {"target": Vector2.INF}

func _has_navigation() -> bool:
	if not is_inside_tree():
		return false
	var map := get_world_2d().navigation_map
	return NavigationServer2D.map_get_iteration_id(map) > 0 and not NavigationServer2D.map_get_regions(map).is_empty()

func _start_walk(target: Vector2, speed: float, stuck_seconds: float, order: bool, through: bool) -> void:
	clear_pose()
	facing = ""
	working = false
	_walk = {"target": target, "speed": speed, "stuck_limit": stuck_seconds, "order": order,
			"through": through, "face": null, "best": INF, "since_progress": 0.0, "caught": 0.0,
			"last_distance": INF, "navigating": _has_navigation()}
	if _walk.navigating:
		_agent.max_speed = speed * SPEED
		_agent.target_position = global_position + (target - position)

func _update_walk(delta: float) -> void:
	if not is_walking():
		return
	var to_target: Vector2 = _walk.target - position
	var distance := to_target.length()
	var step: float = _walk.speed * SPEED * delta
	# Avoidance moves them a frame late, so allow a little more than one
	# frame's step, or they hop back and forth over the spot.
	if distance <= maxf(2.0, step * 1.5):
		position = _walk.target
		_stop_walk(true)
		return
	# Progress is measured along the path: walking around a wall takes them
	# further from the spot for a while, and that is not being stuck.
	var left := _distance_left(distance)
	_check_caught(left, step, delta)
	if left < _walk.best - 0.5:
		_walk.best = left
		_walk.since_progress = 0.0
	else:
		_walk.since_progress += delta
		if _walk.since_progress >= _walk.stuck_limit:
			_stop_walk(false)
			return
	var heading := to_target / distance
	# Along the path, until it runs out. The last stretch, or a target off
	# the walkable area, is a straight line.
	if _walk.navigating and not _agent.is_navigation_finished():
		var next := _agent.get_next_path_position() - global_position
		if next.length() > 0.5:
			heading = next.normalized()
	input_vector = heading * _walk.speed

# How far is left to walk: along the navigation path while there is one,
# otherwise straight to the spot.
func _distance_left(straight: float) -> float:
	if not _walk.navigating or _agent.is_navigation_finished():
		return straight
	var path := _agent.get_current_navigation_path()
	var index := _agent.get_current_navigation_path_index()
	if index >= path.size():
		return straight
	var left := global_position.distance_to(path[index])
	for i in range(index, path.size() - 1):
		left += path[i].distance_to(path[i + 1])
	# The path ends at the nearest walkable point; the rest is straight.
	return left + path[path.size() - 1].distance_to(global_position + (_walk.target - position))

# Pressed against someone and closing on the spot slower than this share of
# their pace counts as caught. Sliding around them still gains a little.
const CAUGHT_SLOW_FRACTION := 0.6

func _check_caught(distance: float, step: float, delta: float) -> void:
	if not _walk.through or is_passing_through():
		_walk.last_distance = distance
		return
	var gained: float = _walk.last_distance - distance
	_walk.last_distance = distance
	if _caught_on_someone() and gained < step * CAUGHT_SLOW_FRACTION:
		_walk.caught += delta
		if _walk.caught >= PASS_THROUGH_SECONDS:
			pass_through()
			_walk.caught = 0.0
			_walk.since_progress = 0.0
	else:
		# Decay rather than reset, so contact flickering for a frame does
		# not start the count over.
		_walk.caught = maxf(0.0, _walk.caught - delta)

func _caught_on_someone() -> bool:
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() is CharacterBody2D:
			return true
	return false

func _stop_walk(reached: bool) -> void:
	var was_order: bool = _walk.order
	var face_target: Variant = _walk.face
	# Keep looking the way they were walking, so fidgets have a facing to turn from.
	if input_vector != Vector2.ZERO:
		facing = facing_for(input_vector)
	_walk = {"target": Vector2.INF}
	input_vector = Vector2.ZERO
	velocity = Vector2.ZERO
	if _agent.avoidance_enabled:
		_agent.velocity = Vector2.ZERO
	end_pass_through_when_clear()
	# A walk ends a fraction of a pixel off the spot. Standing there, the
	# sprite rounds differently from the ground as the camera glides, and
	# twitches a pixel.
	position = position.round()
	if was_order and face_target != null:
		_face(face_target)
	# State is cleared first: a chapter awaiting arrived may issue the next
	# order from inside this emit.
	if was_order:
		arrived.emit(reached)
	else:
		last_walk_reached = reached
