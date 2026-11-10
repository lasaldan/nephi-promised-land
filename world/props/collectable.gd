extends Node2D

class_name Collectable

# Something Nephi can put in his backpack: a log, a stone, a honeycomb, fruit
# on a tree. Place Collectable.tscn and set its item and picture, or make a
# scene that uses this script. Near one, the use button shows the hand, and a
# press reaches for it (Player.use()).
#
#   TAKE  picked up and gone: hidden, its Body's collision off.
#   PICK  picked from and still standing, like a fruit tree: its Sprite shows
#         picked_frame instead, and it cannot be picked again.
#
# Optional children: Sprite (Sprite2D or AnimatedSprite2D), Body (a
# StaticBody2D, for things Nephi cannot walk through), and any
# AudioStreamPlayer2D (the bees at a hive), which fades out when it is taken.
#
# Saving: every collectable joins GROUP, and when a chapter completes each one
# picked so far is flagged in StoryState (remember_collected()), so it goes to
# disk with that save. One picked during a quest that was never finished comes
# back on a load. Node names must be unique under Chapters for that, which
# Godot's own naming (Log, Log2, ...) already gives.

# Once it is in the backpack.
signal collected

enum Mode { TAKE, PICK }

const GROUP := "pickups"

@export var item: InventoryItem
@export var mode := Mode.TAKE
## The frame the Sprite shows once picked (PICK only).
@export var picked_frame := 0
## Off: not offered to the use button until a chapter turns it on.
@export var collectable := true
## From interact_offset to Nephi's feet, in pixels.
@export var reach := 28.0
## Where reach is measured from, relative to this node: its foot on the ground.
@export var interact_offset := Vector2(0, 8)
## Seconds for any sound on it (bees) to fade once it is taken.
@export var sound_fade_seconds := 1.5

var _collected := false

func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(Interaction.GROUP)
	StoryState.changed.connect(_read_state)
	_read_state()

# --- Interaction ---

func interact_kind() -> String:
	return "pickup"

func interact_point() -> Vector2:
	return global_position + interact_offset

func interact_reach() -> float:
	return reach

func can_interact() -> bool:
	return collectable and not _collected and item != null and is_visible_in_tree()

func interact(player: Node) -> void:
	if player.add_to_inventory(item):
		take()

# --- Taking it ---

# Gone (TAKE) or picked (PICK), and collected sent. A chapter can call this
# to clear a path without a pickup.
func take() -> void:
	_take_away()
	collected.emit()

func is_collected() -> bool:
	return _collected

static func flag(pickup: Node) -> String:
	return "collected_" + pickup.name

# Flag every pickup collected so far. Called just before the game saves.
static func remember_collected(tree: SceneTree) -> void:
	for pickup in tree.get_nodes_in_group(GROUP):
		if pickup.is_collected():
			StoryState.set_flag(flag(pickup), true)

# Collected before the last save, so it stays gone in a loaded game. A
# missing flag leaves it alone, so one picked during the current quest is not
# put back.
func _read_state() -> void:
	if not _collected and StoryState.get_flag(flag(self), false):
		_take_away()

func _take_away() -> void:
	_collected = true
	if mode == Mode.PICK:
		var sprite := get_node_or_null("Sprite")
		if sprite:
			sprite.set("frame", picked_frame)
		return
	visible = false
	var body := get_node_or_null("Body") as CollisionObject2D
	if body:
		# Deferred, since this can run inside a physics callback.
		body.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
		for shape in body.get_children():
			if shape is CollisionShape2D or shape is CollisionPolygon2D:
				shape.set_deferred("disabled", true)
		WorldNavigation.rebuild_soon(self)
	for sound in find_children("*", "AudioStreamPlayer2D", false, false):
		var player := sound as AudioStreamPlayer2D
		if player.playing:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -80.0, sound_fade_seconds)
			tween.tween_callback(player.stop)
