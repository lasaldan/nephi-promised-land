extends Resource

class_name InventoryItem

@export var name: String = ""
@export var quantity: int = 0
@export var icon: Texture
# How many share one backpack slot. 1 is one item per slot. More than 1 (seeds)
# piles icon up in the slot, one per item, and each slot holds its own copy
# of this item with quantity counting what is in it.
@export var stack_size: int = 1
# For a stacking item: colours its icon is tinted, one picked at random for
# each pickup, so the pile is not all one colour. Empty draws the icon as is,
# so the icon should be light (seed.png is grey) for the tints to show.
@export var tints: Array[Color] = []
# The tint of each item in this slot's stack, in the order they came. Kept on
# the slot's own copy, filled by the player's add_to_inventory.
var stack_tints: Array[Color] = []
