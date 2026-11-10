extends Panel

class_name InventorySlot
@export var item: InventoryItem

# Where each item of a stack sits in the slot, in the order they arrive,
# measured from the bottom centre of the pile to an icon's top left. Rows of
# five, five, four, three, two and one make a mound of twenty, each row up
# two pixels and over two, so the icons nestle like the seed pile art.
const PILE: Array[Vector2] = [
	Vector2(-3, -4), Vector2(1, -4), Vector2(-7, -4), Vector2(5, -4), Vector2(-11, -4),
	Vector2(-1, -6), Vector2(-5, -6), Vector2(3, -6), Vector2(-9, -6), Vector2(7, -6),
	Vector2(-1, -8), Vector2(-5, -8), Vector2(3, -8), Vector2(-9, -8),
	Vector2(-3, -10), Vector2(1, -10), Vector2(-7, -10),
	Vector2(-1, -12), Vector2(-5, -12),
	Vector2(-3, -14),
]
# The pile's bottom centre inside the 32 x 32 slot.
const PILE_BASE := Vector2(16, 24)

var _stack_icon: Texture2D
var _stack_tints: Array[Color] = []

func _ready() -> void:
	if item:
		add_child(item.scene.instantiate())

# Pile one copy of icon in the slot for each tint, tinted by it. No tints
# clears it.
func show_stack(icon: Texture2D, tints: Array) -> void:
	_stack_icon = icon
	_stack_tints.assign(tints.slice(0, PILE.size()))
	queue_redraw()

func _draw() -> void:
	if _stack_icon == null:
		return
	var order := range(_stack_tints.size())
	# Upper icons first, so the ones in front overlap them.
	order.sort_custom(func(a: int, b: int) -> bool: return PILE[a].y < PILE[b].y)
	for i in order:
		draw_texture(_stack_icon, PILE_BASE + PILE[i], _stack_tints[i])

#func add(new_item: InventoryItem):
	#item = new_item
	#var sprite_scene = item.scene.instantiate()
	#add_child(sprite_scene)
	#
#func remove():
	#item = null
	#for child in get_children():
		#child.queue_free()
