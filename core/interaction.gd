class_name Interaction

# What the use button reaches: anything in the "interactables" group that
# answers these, duck typed so a pickup, a person and an artifact need no
# common base class:
#   interact_kind() -> String     "pickup", "talk" or "look", which picks the
#                                 button's icon (world.gd) and whether Nephi
#                                 plays the work cycle first (player.gd use())
#   interact_point() -> Vector2   global position measured from
#   interact_reach() -> float     pixels
#   can_interact() -> bool        shown, not used up, has something to say
#   interact(player) -> void      may be awaited
# Collectable, Artifact and Npc are the ones so far.
#
# A pickup in reach always wins over talking or looking, so a person standing
# by a fruit tree never blocks picking it. Otherwise the nearest wins.

const GROUP := &"interactables"
const KINDS_FIRST: Array[String] = ["pickup"]

static func nearest(tree: SceneTree, at: Vector2) -> Node:
	var best: Node = null
	var best_rank := INF
	for node in tree.get_nodes_in_group(GROUP):
		if not node.is_inside_tree() or not node.can_interact():
			continue
		var distance: float = (node.interact_point() as Vector2).distance_to(at)
		if distance > node.interact_reach():
			continue
		# Kinds that come first rank below every distance anything else can have.
		var rank := distance - (1e6 if KINDS_FIRST.has(node.interact_kind()) else 0.0)
		if rank < best_rank:
			best = node
			best_rank = rank
	return best
