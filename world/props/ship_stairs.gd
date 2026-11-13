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
# The decks are kept apart by z_index, not y-sort: nested y-sorted nodes all
# sort together by Y, so a hold tile low on screen would draw over the upper
# deck. Lower sits at z -1, Upper at 0, and player.gd set_deck gives him the z
# of his deck so he still y-sorts with its tiles. Anyone else standing below
# decks needs z -1 too. _show_deck sets his z: going up it rises at once, so
# the upper deck fading in is never drawn over him, but going down it drops
# only once the upper deck has faded out. Dropped any sooner, the half-faded
# stairs and rails would draw over him and he would look see-through.
# Off the ship (or with it hidden) he is at z 0, as on the upper deck.
#
# The Upper node fades out while he is below and back in when he comes up.
# The Lower node is hidden while he is above (nothing shows down through the
# deck), shown as soon as he starts down, and hidden once the upper deck has
# faded back in.
# Below, everything in outside (the sea) fades to black too, so all that
# shows is the hold he is in, and the weather (world/weather/rain.gd, fog.gd)
# shelters over the same fade: no rain or fog drawn, the rain heard quieter. While the ship
# is hidden (another chapter) nothing is sheltered or darkened, whatever deck
# he was last on.
# Put this under the Ship, so it rocks with it.

enum Deck { UPPER, LOWER }

## Where on the stairs the decks change over, in this node's coordinates (the
## Ship's, when it sits at the Ship's origin). West of it is below decks.
@export var threshold_x := 208.0
## The upper deck's art, which fades while he is below.
@export var upper: CanvasItem
## The lower deck's art, hidden while he is above.
@export var lower: CanvasItem
## What goes black while he is below: the sea around the ship.
@export var outside: Array[CanvasItem] = []
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
	# Hiding the ship's chapter hides this too, and must not leave the world
	# sheltered.
	visibility_changed.connect(func() -> void: _show_deck(_player.deck, false))
	_show_deck(_player.deck, false)

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if _fade:
		_fade.kill()
	for weather in _weather():
		weather.shelter = 0.0
	_set_player_z(false)

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
	var below := deck == Deck.LOWER and is_visible_in_tree()
	if _fade:
		_fade.kill()
	var shown := not below
	var dark := Color.BLACK if below else Color.WHITE
	if lower and below:
		lower.visible = true
	if not below:
		_set_player_z(false)
	if not animate:
		_set_player_z(below)
		if lower:
			lower.visible = below
		if upper:
			upper.modulate.a = 1.0 if shown else 0.0
			upper.visible = shown
		for item in outside:
			if is_instance_valid(item):
				item.modulate = dark
		for weather in _weather():
			weather.shelter = 1.0 if below else 0.0
		return
	_fade = create_tween().set_parallel()
	if upper:
		upper.visible = true
		_fade.tween_property(upper, "modulate:a", 1.0 if shown else 0.0, fade_seconds)
	for item in outside:
		if is_instance_valid(item):
			_fade.tween_property(item, "modulate", dark, fade_seconds)
	for weather in _weather():
		_fade.tween_property(weather, "shelter", 1.0 if below else 0.0, fade_seconds)
	if below:
		_fade.chain().tween_callback(_set_player_z.bind(true))
	if upper and not shown:
		_fade.chain().tween_callback(upper.hide)
	if lower and shown:
		_fade.chain().tween_callback(lower.hide)

# The hold draws at z -1 under the upper deck (world.tscn), and he y-sorts
# only with what shares his z, so below decks he goes down with it.
func _set_player_z(below: bool) -> void:
	if is_instance_valid(_player):
		_player.z_index = -1 if below else 0

# The world's rain and fog, which shelter while he is below.
func _weather() -> Array[Node]:
	var found: Array[Node] = []
	for group in [Rain.GROUP, Fog.GROUP]:
		found.append_array(get_tree().get_nodes_in_group(group))
	return found

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
