@tool
class_name FruitBox
extends StaticBody2D

# A crate of fruit or vegetables from world/tilesets/fruits-veggies-box.png:
# pick which in the Kind dropdown and the picture follows, in the editor too.
# Its origin is the middle of the crate's bottom edge, where it stands on the
# floor and y-sorts, and its collision covers the crate's footprint there.
# For one Nephi can take from, use FruitPickup set to CRATE instead.

@export var kind: Fruit.Kind = Fruit.Kind.RED_APPLE:
	set(value):
		kind = value
		_show()

@onready var _sprite: Sprite2D = $Sprite

func _ready() -> void:
	_show()

func _show() -> void:
	if not is_node_ready():
		return
	_sprite.region_rect = Fruit.region(kind, Fruit.Amount.CRATE)
