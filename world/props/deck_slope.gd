@tool
class_name DeckSlope
extends Node2D

# A stretch of deck that climbs as you walk across it, such as the steps up
# to the raised stern of the ship. While Nephi is inside area on deck,
# walking east also carries him north (up the steps) and walking west carries
# him south (back down). Walking north or south along the steps is left alone.
#
# Worked out in this node's own coordinates, so it tilts with the ship. Put
# it under the Ship. player.gd asks it (DeckSlope.adjust) before he moves.

const GROUP := "deck_slopes"

## The steps, in this node's coordinates.
@export var area := Rect2(448, 0, 32, 288):
	set(value):
		area = value
		queue_redraw()
## How far north he goes for each step east. 1 climbs at 45 degrees.
@export var rise := 1.0
## Only while he is on this deck.
@export var deck := ShipStairs.Deck.UPPER
## Keeps his walking speed the same on the slope as on the flat. Off, the
## climb is added on top, so he moves faster along it.
@export var keep_speed := true
## Draws area over the ship.
@export var debug_draw := false:
	set(value):
		debug_draw = value
		queue_redraw()

func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)

# velocity bent along any slope the body stands on.
static func adjust(body: Node2D, velocity: Vector2) -> Vector2:
	if velocity.x == 0.0:
		return velocity
	for node in body.get_tree().get_nodes_in_group(GROUP):
		var slope := node as DeckSlope
		if slope and slope.is_visible_in_tree() and slope.holds(body):
			return slope.bend(velocity)
	return velocity

func holds(body: Node2D) -> bool:
	if "deck" in body and body.deck != deck:
		return false
	return area.has_point(to_local(body.global_position))

func bend(velocity: Vector2) -> Vector2:
	var local := global_transform.basis_xform_inv(velocity)
	var speed := local.length()
	local.y -= local.x * rise
	if keep_speed and local != Vector2.ZERO:
		local = local.normalized() * speed
	return global_transform.basis_xform(local)

func _draw() -> void:
	if debug_draw and OS.is_debug_build():
		draw_rect(area, Color(1, 0.5, 0, 0.25))
		draw_rect(area, Color(1, 0.5, 0, 1), false, 1.0)
