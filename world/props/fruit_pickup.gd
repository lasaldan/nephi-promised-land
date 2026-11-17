@tool
class_name FruitPickup
extends Collectable

# Fruit or vegetables Nephi can put in his backpack, drawn from
# world/tilesets/fruits-veggies-box.png. Pick which in the Kind dropdown and
# how much in Amount (one, a few, a heap, or a crate); the picture follows,
# in the editor too. Its origin is the middle of the picture's bottom edge,
# where it sits on the floor and y-sorts.
#
# Only a crate is solid: the Body's collision is on for CRATE and off for the
# rest, which Nephi can walk over.
#
# Item: leave it empty and it goes in the backpack named after its kind
# ("Red Apple", for a chapter's pickup_list) with a picture from the sheet.
# Set one (world/items/AppleInventoryItem.tres) to use that instead.

@export var kind: Fruit.Kind = Fruit.Kind.RED_APPLE:
	set(value):
		kind = value
		_show()

@export var amount: Fruit.Amount = Fruit.Amount.FEW:
	set(value):
		amount = value
		_show()

@onready var _sprite: Sprite2D = $Sprite
@onready var _collision: CollisionPolygon2D = $Body/Collision

func _ready() -> void:
	_show()
	if Engine.is_editor_hint():
		return
	if item == null:
		item = InventoryItem.new()
		item.name = Fruit.display_name(kind)
		item.quantity = 1
		item.icon = Fruit.icon(kind)
	super._ready()

func _show() -> void:
	if not is_node_ready():
		return
	var crate := amount == Fruit.Amount.CRATE
	_sprite.region_rect = Fruit.region(kind, amount)
	_sprite.offset = Vector2(-Fruit.TILE * 0.5, -(Fruit.TILE * 2 if crate else Fruit.TILE))
	if not is_collected():
		_collision.disabled = not crate
