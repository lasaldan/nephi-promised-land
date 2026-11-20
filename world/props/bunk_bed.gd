@tool
class_name BunkBed
extends StaticBody2D

# A two-berth bunk below decks, drawn from the ship tiles (ship.png): the
# frame with both berths, the posts in front, and a raised blanket for each
# berth that shows only while someone lies under it.
#
# The bunk keeps track of who is in it. Point top or bottom at an Npc in the
# inspector and, when the game starts, they are laid in that berth asleep
# (head on the pillow, to the west), lifted onto it and sorted between the
# frame and the blanket. Chapters can move people in and out:
#   bunk.tuck_in(sariah, BunkBed.BOTTOM)      asleep
#   bunk.tuck_in(sariah, BunkBed.BOTTOM, true) awake, lying there
#   bunk.sit_on_edge(lehi)                   sitting on the bottom berth
#   bunk.let_out(sariah)                     up, standing at the exit
# Anyone in it who gets up some other way (wake(), clear_pose(), a sit or
# kneel pose) is let out too: put at the exit, the spot beside the bunk given
# by exit_offset, so nobody is left standing inside the frame. The exit is
# drawn in the editor as a small ring.
#
# Its origin is the front of the bunk at floor level, where the posts stand:
# everything in it sorts by its height from there, like the tiles it
# replaces. Put it under Ship/Lower, which y-sorts, so people walking in front
# of it draw over it and the sleepers in it draw between its parts.

enum { TOP, BOTTOM }

const SHEET := preload("res://world/tilesets/ship.png")
const FRAME_REGION := Rect2(608, 64, 64, 64)
const POSTS_REGION := Rect2(608, 0, 64, 64)
const BLANKET_REGION := Rect2(416, 0, 64, 32)

# Where each berth's sleeper stands (their position, which they sort by) and
# how far the figure is lifted onto the berth (Npc.lying_lift).
const BERTH_SPOT := {TOP: Vector2(-4, -27), BOTTOM: Vector2(-4, -5)}
const BERTH_LIFT := {TOP: 18.0, BOTTOM: 8.0}
# Sitting on the bottom berth's edge, facing out.
const EDGE_SPOT := Vector2(0, 2)
# What it stands on: the frame's width, from its origin back to the wall.
const FOOTPRINT := Rect2(-32, -24, 64, 24)

## Who lies in the top berth.
@export var top: Npc:
	set(value):
		top = value
		_refresh()
## Who lies in the bottom berth.
@export var bottom: Npc:
	set(value):
		bottom = value
		_refresh()
## Where people stand on getting out, from the bunk's origin. Beside the
## bottom pillow, on the walkway side.
@export var exit_offset := Vector2(-20, 14):
	set(value):
		exit_offset = value
		queue_redraw()
## Which way they face on getting out.
@export_enum("down", "up", "left", "right") var exit_facing := "down"
## How much further north than its footprint it keeps people off, in pixels.
## For a bunk against the near (south) wall, whose footprint is hidden behind
## the wall and only its top berth shows over it: this keeps anyone from
## walking onto that.
@export var extra_depth := 0.0:
	set(value):
		extra_depth = value
		_refresh()

# Whoever sits on the bottom berth's edge.
var _sitter: Npc
# Set while the bunk itself poses someone, so its own pose changes are not
# taken for getting up.
var _placing := false

@onready var _top_blanket := $TopBlanket as Sprite2D
@onready var _bottom_blanket := $BottomBlanket as Sprite2D
@onready var _collision := $Collision as CollisionPolygon2D

func _ready() -> void:
	_refresh()
	if Engine.is_editor_hint():
		return
	for berth in [TOP, BOTTOM]:
		var npc := occupant(berth)
		if npc == null:
			continue
		if not npc.is_node_ready():
			await npc.ready
		tuck_in(npc, berth, npc.start_pose == "lie")

# Who is in a berth (TOP, BOTTOM), or null.
func occupant(berth: int) -> Npc:
	return top if berth == TOP else bottom

# The berth someone lies in, or -1.
func berth_of(npc: Npc) -> int:
	if npc == null:
		return -1
	if top == npc:
		return TOP
	if bottom == npc:
		return BOTTOM
	return -1

func has(npc: Npc) -> bool:
	return berth_of(npc) != -1 or (npc != null and npc == _sitter)

# The exit beside the bunk, in world pixels.
func exit_position() -> Vector2:
	return to_global(exit_offset)

# Lays npc in a berth, asleep or (awake) lying there with eyes open. Anyone
# already in that berth is let out first.
func tuck_in(npc: Npc, berth := BOTTOM, awake := false) -> void:
	var current := occupant(berth)
	if current != null and current != npc:
		let_out(current)
	_forget(npc)
	_set_occupant(berth, npc)
	_watch(npc)
	npc.lying_lift = BERTH_LIFT[berth]
	npc.global_position = to_global(BERTH_SPOT[berth])
	_placing = true
	npc.pose("lie" if awake else "sleep", "left")
	_placing = false
	_refresh()

# Sits npc on the bottom berth's edge, facing out. False if their sheet has
# no sitting rows, or someone lies in the bottom berth.
func sit_on_edge(npc: Npc) -> bool:
	if bottom != null and bottom != npc:
		return false
	if not npc.can_pose("sit"):
		return false
	_forget(npc)
	_sitter = npc
	_watch(npc)
	npc.global_position = to_global(EDGE_SPOT)
	_placing = true
	npc.sit("down")
	_placing = false
	_refresh()
	return true

# Out of the bunk: on their feet at the exit, facing exit_facing.
func let_out(npc: Npc) -> void:
	if not has(npc):
		return
	_forget(npc)
	if npc.is_posed():
		_placing = true
		npc.clear_pose()
		_placing = false
	npc.global_position = exit_position()
	npc.facing = exit_facing
	_refresh()

func _set_occupant(berth: int, npc: Npc) -> void:
	if berth == TOP:
		top = npc
	else:
		bottom = npc

func _forget(npc: Npc) -> void:
	if top == npc:
		top = null
	if bottom == npc:
		bottom = null
	if _sitter == npc:
		_sitter = null
	if npc and npc.pose_changed.is_connected(_on_pose_changed):
		npc.pose_changed.disconnect(_on_pose_changed)

func _watch(npc: Npc) -> void:
	if not npc.pose_changed.is_connected(_on_pose_changed):
		npc.pose_changed.connect(_on_pose_changed.bind(npc))

# Someone in the bunk changed pose by other means: still lying (sleep to lie
# and back) keeps them in; anything else gets them out.
func _on_pose_changed(_pose_name: String, npc: Npc) -> void:
	if _placing:
		return
	var staying := npc.is_lying() if berth_of(npc) != -1 else npc.is_sitting()
	if staying:
		_refresh()
		return
	_forget(npc)
	npc.global_position = exit_position()
	npc.facing = exit_facing
	_refresh()

func _refresh() -> void:
	if not is_node_ready():
		return
	_top_blanket.visible = _under_blanket(top)
	_bottom_blanket.visible = _under_blanket(bottom)
	var r := FOOTPRINT.grow_side(SIDE_TOP, extra_depth)
	_collision.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	queue_redraw()

# In the editor, whoever is assigned; in the game, only while lying there.
func _under_blanket(npc: Npc) -> bool:
	if npc == null:
		return false
	return Engine.is_editor_hint() or npc.is_lying()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_arc(exit_offset, 5.0, 0.0, TAU, 16, Color(0.3, 1.0, 0.5, 0.9), 1.0)
	draw_line(exit_offset + Vector2(-3, 0), exit_offset + Vector2(3, 0), Color(0.3, 1.0, 0.5, 0.9), 1.0)
