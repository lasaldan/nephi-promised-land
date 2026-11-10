class_name WorldNavigation
extends NavigationRegion2D

# Where people can walk, worked out from the map so nobody has to paint it.
# The walkable area is everything inside bounds (or the used cells of the
# ground layers, when bounds is empty) minus anything solid:
#   - tile collision on the TileMapLayers under GroundLayer
#   - StaticBody2D shapes anywhere under the world that are shown and
#     processing: props in the shown chapter's Set, Collectables not yet
#     taken, and so on
# shrunk by agent_radius so a body never brushes a wall. Characters, being
# CharacterBody2D, are not walls: avoidance (Npc) steers them around each other.
#
# It is rebuilt when a chapter starts (its Set changes what stands where) and
# shortly after a Collectable with a body is taken. Anything else that adds,
# removes, shows or hides something solid should call rebuild_soon(self).
# Building runs on a thread and takes a moment; walks started in between use
# the old area.
#
# To see it while playing: Debug menu > Visible Navigation.

const GROUP := "world_navigation"

## The walkable area, in world pixels. Empty: the used cells of the ground
## layers, or DEFAULT_BOUNDS when they have none yet.
@export var bounds := Rect2()
## Half a body's width. Paths keep this far from walls.
@export var agent_radius := 8.0
## The node whose TileMapLayers are the map.
@export var ground: Node2D
## Seconds to wait after a rebuild_soon(), so several changes at once rebuild once.
@export var settle_seconds := 0.25

const DEFAULT_BOUNDS := Rect2(-2048, -2048, 4096, 4096)

signal rebuilt

var _pending := false
var _building := false

static func rebuild_soon(from: Node) -> void:
	if from.is_inside_tree():
		from.get_tree().call_group(GROUP, "_request")

# Points to walk along from body to target (world pixels), ending at target.
# Just [target] with no navigation, so a caller can always walk the list.
static func path(body: Node2D, target: Vector2) -> PackedVector2Array:
	var map := body.get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(map) == 0 or NavigationServer2D.map_get_regions(map).is_empty():
		return PackedVector2Array([target])
	var points := NavigationServer2D.map_get_path(map, body.global_position, target, true)
	if points.is_empty():
		return PackedVector2Array([target])
	points.remove_at(0)
	points.append(target)
	return points

func _ready() -> void:
	add_to_group(GROUP)
	rebuild()

func _request() -> void:
	if _pending:
		return
	_pending = true
	await get_tree().create_timer(settle_seconds, false).timeout
	_pending = false
	rebuild()

func rebuild() -> void:
	if _building:
		_request()
		return
	_building = true
	var polygon := NavigationPolygon.new()
	polygon.agent_radius = agent_radius
	polygon.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	polygon.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	var area := _area()
	polygon.add_outline(PackedVector2Array([area.position, Vector2(area.end.x, area.position.y),
			area.end, Vector2(area.position.x, area.end.y)]))
	var source := NavigationMeshSourceGeometryData2D.new()
	if ground:
		NavigationServer2D.parse_source_geometry_data(polygon, source, ground)
	_add_props(source)
	NavigationServer2D.bake_from_source_geometry_data_async(polygon, source, func() -> void:
		navigation_polygon = polygon
		_building = false
		rebuilt.emit())

func _area() -> Rect2:
	if bounds.has_area():
		return bounds
	var used := Rect2()
	if ground:
		for node in ground.find_children("*", "TileMapLayer", true, false):
			var layer := node as TileMapLayer
			var cells := layer.get_used_rect()
			if cells.has_area() and layer.tile_set:
				var size := Vector2(layer.tile_set.tile_size)
				var rect := layer.get_global_transform() * Rect2(Vector2(cells.position) * size, Vector2(cells.size) * size)
				used = rect if not used.has_area() else used.merge(rect)
	return used if used.has_area() else DEFAULT_BOUNDS

# Every StaticBody2D under the world that is in play now, as obstructions.
# Hidden or disabled ones (a Set not showing, a log already taken) are left out.
func _add_props(source: NavigationMeshSourceGeometryData2D) -> void:
	var world := get_parent()
	for node in world.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		if body.is_ancestor_of(self) or (ground and ground.is_ancestor_of(body)):
			continue
		if not body.is_visible_in_tree() or not body.can_process():
			continue
		for child in body.get_children():
			var outline := _outline(child)
			if not outline.is_empty():
				source.add_obstruction_outline(outline)

func _outline(shape_node: Node) -> PackedVector2Array:
	if shape_node is CollisionPolygon2D and not shape_node.disabled:
		return (shape_node as CollisionPolygon2D).get_global_transform() * (shape_node as CollisionPolygon2D).polygon
	if shape_node is CollisionShape2D and not shape_node.disabled and shape_node.shape:
		var xform := (shape_node as CollisionShape2D).get_global_transform()
		var shape: Shape2D = shape_node.shape
		if shape is RectangleShape2D:
			var half: Vector2 = shape.size / 2.0
			return xform * PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
		if shape is CircleShape2D or shape is CapsuleShape2D:
			var radius: float = shape.radius
			var points := PackedVector2Array()
			for i in 12:
				points.append(Vector2.from_angle(TAU * i / 12.0) * radius)
			return xform * points
		if shape is ConvexPolygonShape2D:
			return xform * (shape as ConvexPolygonShape2D).points
	return PackedVector2Array()
