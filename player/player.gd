extends CharacterBody2D

const SPEED = 80.0

var input_vector: = Vector2.ZERO
# Cutscenes set this through StoryChapter.disablePlayerControls / enablePlayerControls.
# Keyboard and the virtual joystick both feed the move_* actions, so this blocks both.
# Scripted facing still works while this is false, so a cutscene can turn Nephi.
var controls_enabled: bool = true
# A menu over the game, such as the crafting scroll, holds Nephi still on top
# of controls_enabled, so a chapter enabling controls mid-menu cannot free him.
var menu_open: bool = false
# Talking to someone (story/small_talk.gd) holds him still the same way.
var talking: bool = false
# Where a cutscene is walking him while controls are off
# (StoryChapter.walkPlayerTo). Zero when nothing is.
var scripted_input := Vector2.ZERO
@export var facing: String
@export var inventory = preload("res://player/inventory/player_inventory.tres")
@onready var animation_tree: AnimationTree = $AnimationTree
# Praying for guidance (player/prayer.gd). It holds Nephi still while he
# prays without touching controls_enabled, which cutscenes own.
var prayer: Prayer
# Seconds left of the work cycle (rows 4-7 of the sheet) from play_work.
var _work_left := 0.0
const WORK_CYCLE_SECONDS := 0.8
# How far into the work cycle a use takes the item, so it reaches the pack
# once his hands have got to it.
const USE_TAKES_AT := 0.5
# The pickup a use is reaching for until USE_TAKES_AT. Walking off drops it.
var _pending_use: Node = null
# Counts items going into the pack, so a use can tell it took something.
var _items_added := 0
const COLLECT_SOUND: AudioStream = preload("res://audio/sfx/collect_item.ogg")
# The recording is sharp next to the other sounds. Every 6 dB lower is about
# half as loud.
const COLLECT_VOLUME_DB := -20.0
var _collect_sound: AudioStreamPlayer
var _obstacle: NavigationObstacle2D

func _ready() -> void:
	# StoryTrigger ignores every body that is not in this group. NPCs use the
	# same collision layer, so the layer mask alone cannot tell Nephi apart.
	add_to_group("player")
	# The pack is one preloaded resource shared by every world, so it would
	# keep what was carried when the player quit to the menu. A game always
	# starts at a checkpoint, and nothing is in the pack at a checkpoint.
	empty_inventory(false)
	prayer = Prayer.new()
	prayer.name = "Prayer"
	add_child(prayer)
	var footsteps := Footsteps.new()
	footsteps.name = "Footsteps"
	add_child(footsteps)
	_collect_sound = AudioStreamPlayer.new()
	_collect_sound.name = "CollectSound"
	_collect_sound.stream = COLLECT_SOUND
	_collect_sound.volume_db = COLLECT_VOLUME_DB
	_collect_sound.bus = GameSettings.SFX
	add_child(_collect_sound)
	# NPCs walking by steer around him (Npc avoidance).
	_obstacle = NavigationObstacle2D.new()
	_obstacle.name = "AvoidanceObstacle"
	_obstacle.radius = 8.0
	_obstacle.avoidance_enabled = true
	add_child(_obstacle)

## True while the player can walk and use things. The world hides the
## joystick when this has been false for a while.
func can_act() -> bool:
	return controls_enabled and not menu_open and not talking and not (prayer and prayer.praying)

func _physics_process(delta: float) -> void:
	var free := can_act()
	if free and Input.is_action_just_pressed("player_use"):
		use()
	_work_left = maxf(0.0, _work_left - delta)
	_obstacle.velocity = velocity

	if free:
		input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		# Walking breaks a scripted pose, so faceToward never locks Nephi in place.
		if input_vector != Vector2.ZERO:
			facing = ""
			# Walking off cuts a use's work cycle short, and leaves the item.
			_work_left = 0.0
			_pending_use = null
	else:
		# Drop any held direction so the character stops on the same frame controls lock.
		# A cutscene walking him (StoryChapter.walkPlayerTo) steers instead.
		input_vector = scripted_input
	
	# Facing is a pose, not a step. The walk state only leaves when input_vector
	# is zero, and this branch returns before move_and_slide. Stuffing the
	# direction into input_vector used to keep the walk cycle playing in place
	# (dialogue sets facing, then holds Nephi still).
	if facing == "left" || facing == "right" || facing == "up" || facing == "down":
		var face_vector := _vector_for_facing(facing)
		input_vector = Vector2.ZERO
		velocity = Vector2.ZERO
		update_blend_positions(Vector2(face_vector.x, -face_vector.y))
		# Once per entry into the stand (or work) state. Already there does not restart it.
		_snap_to_pose()
		return
		
	if input_vector != Vector2.ZERO:
		velocity = input_vector * SPEED
		var direction_vector: = Vector2(input_vector.x, -input_vector.y)
		update_blend_positions(direction_vector)
	else:
		velocity = input_vector * SPEED
		_snap_to_pose()
		
	move_and_slide()
	
func update_blend_positions(direction_vector: Vector2) -> void:
	animation_tree.set("parameters/StateMachine/MoveState/WalkState/blend_position", direction_vector)
	animation_tree.set("parameters/StateMachine/MoveState/StandState/blend_position", direction_vector)
	animation_tree.set("parameters/StateMachine/MoveState/WorkState/blend_position", direction_vector)

# Use: the nearest thing in reach (Interaction). A pickup takes one work
# cycle, and the item goes into the pack partway through it; presses during
# the reach are ignored, so one press takes one thing. Talking to someone or
# looking at an artifact starts at once. The use key and the touch button
# both come here.
func use() -> void:
	Achievements.check_reach_out(get_tree(), global_position)
	if _pending_use != null:
		return
	var target := Interaction.nearest(get_tree(), global_position)
	if target == null:
		return
	if target.interact_kind() != "pickup":
		target.interact(self)
		return
	_pending_use = target
	play_work()
	await get_tree().create_timer(WORK_CYCLE_SECONDS * USE_TAKES_AT, false, true).timeout
	if _pending_use != target:
		return
	_pending_use = null
	if is_instance_valid(target) and target.can_interact():
		var added_before := _items_added
		target.interact(self)
		# A full pack or the wrong item leaves it where it is, with no sound.
		if _items_added != added_before:
			_collect_sound.play()

# One work cycle facing the way he stands. A walk cuts it short.
func play_work(seconds: float = WORK_CYCLE_SECONDS) -> void:
	_work_left = seconds

# The work cycle's rows by facing, and the frame where his arm reaches
# furthest out.
const STRETCH_ROWS := {"up": 4, "left": 5, "down": 6, "right": 7}
const STRETCH_FRAME := 5

# The work cycle up to its furthest reach, then held there with his hand
# stretched forth (1 Nephi 17:54). Controls should be off. The tree would put
# the stand frame back every frame, so it is off until lower_hand().
#   await getPlayer().stretch_forth_hand()
func stretch_forth_hand() -> void:
	_work_left = 0.0
	animation_tree.active = false
	var sprite := $Sprite2D as Sprite2D
	var row: int = STRETCH_ROWS.get(facing, STRETCH_ROWS["down"])
	for frame in STRETCH_FRAME + 1:
		sprite.frame_coords = Vector2i(frame, row)
		await get_tree().create_timer(WORK_CYCLE_SECONDS / 8.0, false).timeout

# Back to the stand pose, facing as before.
func lower_hand() -> void:
	animation_tree.active = true

# Stop the walk cycle and hold the stand pose. Dialogue calls this as the
# balloon opens. The last blend position is kept, so Nephi stays faced the
# way he was already looking unless `facing` says otherwise. A use's work
# cycle stops, though the item it reached for still goes into the pack.
func play_idle() -> void:
	input_vector = Vector2.ZERO
	velocity = Vector2.ZERO
	_work_left = 0.0
	if facing == "left" || facing == "right" || facing == "up" || facing == "down":
		var face_vector := _vector_for_facing(facing)
		update_blend_positions(Vector2(face_vector.x, -face_vector.y))
	_snap_to_pose()

func _vector_for_facing(direction: String) -> Vector2:
	match direction:
		"left":
			return Vector2(-1, 0)
		"right":
			return Vector2(1, 0)
		"up":
			return Vector2(0, -1)
		"down":
			return Vector2(0, 1)
		_:
			return Vector2.ZERO

# WalkState does not leave on its own while input_vector was non-zero, so
# zeroing the vector is not enough for the frame dialogue begins.
# Standing still: the work cycle during play_work, otherwise the stand pose.
func _snap_to_pose() -> void:
	_snap_to("WorkState" if _work_left > 0.0 else "StandState")

# Calling start() again while already there would restart the clip every
# physics frame.
func _snap_to(state: String) -> void:
	if animation_tree == null:
		return
	var playback := animation_tree.get("parameters/StateMachine/MoveState/playback") as AnimationNodeStateMachinePlayback
	if playback == null:
		return
	if playback.get_current_node() != state:
		playback.start(state)

# Item names the player may collect. Empty means nothing can be picked up.
# Once the pack holds something, only more of that same item fits.
# Chapters set this through StoryChapter.setPickupList.
var pickup_list: Array[String] = []
# The most the pack takes for a quest that wants fewer than it holds, such as
# three logs. 0 means as many as fit. Chapters set this through
# StoryChapter.setPickupLimit.
var pickup_limit := 0

func can_pick_up(item: InventoryItem) -> bool:
	if not item.name in pickup_list:
		return false
	var held_count := 0
	for held in inventory.items:
		if held:
			if held.name != item.name:
				return false
			held_count += 1
	return pickup_limit <= 0 or held_count < pickup_limit

# With show_leaving, the backpack shows what was in it going out
# (SignalBus.player_items_removed).
func empty_inventory(show_leaving: bool = true) -> void:
	var removed: Array[InventoryItem] = []
	for slotIndex in range(inventory.items.size()):
		if inventory.items[slotIndex]:
			removed.append(inventory.items[slotIndex])
		inventory.items[slotIndex] = null
	SignalBus.player_inventory_change.emit()
	if show_leaving and not removed.is_empty():
		SignalBus.player_items_removed.emit(removed)

func add_to_inventory(item: InventoryItem):
	if not can_pick_up(item):
		print("Cannot pick up " + item.name + " right now")
		return false
	var added = false
	# The slot's own copy of a stacking item, once it is in.
	var stack: InventoryItem = null
	# A stacking item tops up the slot it is filling before taking a new one.
	if item.stack_size > 1:
		for held in inventory.items:
			if held and held.name == item.name and held.quantity < item.stack_size:
				held.quantity += 1
				stack = held
				added = true
				break
	# First empty entry wins. The array length is the pack size.
	if not added:
		for slotIndex in range(inventory.items.size()):
			if inventory.items[slotIndex] == null:
				var entry := item
				if item.stack_size > 1:
					# Its own copy, so each slot keeps its own count.
					entry = item.duplicate() as InventoryItem
					entry.quantity = 1
					stack = entry
				inventory.items[slotIndex] = entry
				print("Added " + item.name + " to slot " + str(slotIndex))
				added = true
				break

	if stack:
		stack.stack_tints.append(item.tints.pick_random() if not item.tints.is_empty() else Color.WHITE)

	if added:
		_items_added += 1
		print("sending inventory change event")
		SignalBus.player_inventory_change.emit()
		SignalBus.player_item_added.emit(item)
		
	return added
	
