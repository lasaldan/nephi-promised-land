extends Resource

class_name Inventory

# One entry per backpack slot. Null means that slot is empty.
# The length of this array is the pack size. The corner HUD has a matching
# Slot0 .. SlotN-1 node for each entry and only draws the ones that are filled.
@export var items: Array[InventoryItem]
