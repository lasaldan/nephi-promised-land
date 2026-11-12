@tool
class_name ShipStairs
extends Area2D

# The stairs between the ship's two decks. Nephi is on whichever deck the
# side of threshold_x he stands on says, while he is on the stairs: east of
# it is the upper deck, west of it the lower. That is read from where he is,
# not from which way he crossed, so stopping on the line, turning back, or a
# cutscene walking him down cannot leave the wrong deck showing.
#
# Each deck collides on its own physics layer (named in Project Settings,
# Layer Names > 2D Physics). The ship TileSet's physics layer 0 is the upper
# deck and physics layer 1 the lower. The player only collides with the deck
# he is on (player.gd set_deck), so NPCs on the other deck keep theirs.
#
# The upper rails close the stairwell on the north, south and west, open to
# the east. Lower-deck walls should close it on the north, south and east,
# open to the west, so he can only come onto the stairs from the end that
# belongs to the deck he is on.
#
# The Upper node fades out while he is below and back in when he comes up.
# Put this under the Ship, so it rocks with it.

enum Deck { UPPER, LOWER }

## Where on the stairs the decks change over, in this node's coordinates (the
## Ship's, when it sits at the Ship's origin). West of it is below decks.
@export var threshold_x := 208.0
## The upper deck's art, which fades while he is below.
@export var upper: CanvasItem
## How long the upper deck takes to fade out or in.
@export var fade_seconds := 0.25
## Draws the trigger box and the threshold over the ship, in the editor and
## while playing, and tints the box with the deck he is on. Debug builds only.
@export var debug_draw := false:
	set(value):
		debug_draw = value
		queue_redraw()

var _player: Node2D
var _fade: Tween

func _ready() -> void:
	# Above the decks, so the debug drawing is not hidden under them.
	z_index = 100
	if Engine.is_editor_hint():
		return
	_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		push_warning("ShipStairs: no player")
		return
	_player.deck_changed.connect(_show_deck)
	_show_deck(_player.deck, false)

func _physics_process(_delta: float) -> void:
	if debug_draw:
		queue_redraw()
	if Engine.is_editor_hint():
		return
	if _player == null or not overlaps_body(_player):
		return
	var below := to_local(_player.global_position).x < threshold_x
	_player.set_deck(Deck.LOWER if below else Deck.UPPER)

func _show_deck(deck: Deck, animate: bool = true) -> void:
	if upper == null:
		return
	if _fade:
		_fade.kill()
	var shown := deck == Deck.UPPER
	if not animate:
		upper.modulate.a = 1.0 if shown else 0.0
		upper.visible = shown
		return
	upper.visible = true
	_fade = create_tween()
	_fade.tween_property(upper, "modulate:a", 1.0 if shown else 0.0, fade_seconds)
	if not shown:
		_fade.tween_callback(upper.hide)

func _draw() -> void:
	if not debug_draw or not OS.is_debug_build():
		return
	var on_stairs := not Engine.is_editor_hint() and _player != null and overlaps_body(_player)
	var tint := Color(1, 0.8, 0, 0.25)
	if on_stairs:
		tint = Color(0.2, 0.6, 1, 0.35) if _player.deck == Deck.LOWER else Color(0.2, 1, 0.3, 0.35)
	for child in get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.shape == null:
			continue
		var rect := shape_node.shape.get_rect()
		draw_set_transform_matrix(shape_node.transform)
		draw_rect(rect, tint)
		draw_rect(rect, Color(tint, 1.0), false, 1.0)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var top := shape_node.position.y + rect.position.y * shape_node.scale.y
		var bottom := top + rect.size.y * shape_node.scale.y
		draw_line(Vector2(threshold_x, top - 8), Vector2(threshold_x, bottom + 8), Color.RED, 1.0)
	if on_stairs:
		draw_circle(to_local(_player.global_position), 2.0, Color.RED)
