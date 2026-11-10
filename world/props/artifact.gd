extends Node2D

class_name Artifact

# Something Nephi can look at closely (story/artifacts.gd). Place it like any
# prop; its origin is the spot on the ground it stands on. Near one, the use
# button shows the magnifying glass, and a press opens its balloon
# (SmallTalk.inspect): its picture and name, and Nephi telling about it.
# The sprite is a child, so a scene can swap in another picture of the same
# thing without touching anything else. Make the root a StaticBody2D for
# things Nephi should not walk through.

# Its key in Artifacts.LIST.
@export var artifact_id := ""
## From its spot to Nephi, in pixels. A body keeps him about a tile off.
@export var reach := 44.0

func _ready() -> void:
	add_to_group(Interaction.GROUP)
	if not Artifacts.has(artifact_id):
		push_error("Artifact %s: no artifact id '%s' in Artifacts.LIST" % [name, artifact_id])

func interact_kind() -> String:
	return "look"

func interact_point() -> Vector2:
	return global_position

func interact_reach() -> float:
	return reach

func can_interact() -> bool:
	return is_visible_in_tree() and SmallTalk.has_title(Artifacts.title_for(artifact_id)) \
			and SmallTalk.free_to_talk(get_tree())

func interact(_player: Node) -> void:
	await SmallTalk.find(get_tree()).inspect(self)
