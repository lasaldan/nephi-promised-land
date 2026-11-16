class_name OilLamp
extends Node2D

# A clay oil lamp on a wall bracket (world/props/oil_lamp.png, made by
# tools/oil_lamp/gen.py). The flame changes shape now and then and its light
# (a FlickerLight, lit day and night) wavers on its own. The node sits on the
# floor 48px below the bracket's foot, with the sprite and light raised above
# it: that is where it y-sorts, in front of the bunks (whose fronts reach the
# floor) and behind anyone walking past. Put it under the deck's art so it is
# shown, hidden and rocked with it. Its lights shine only on the
# below_decks light layer, which ShipStairs gives the hold and the player.

## Shortest and longest time a flame shape holds, in seconds.
@export var frame_seconds := Vector2(0.10, 0.28)

@onready var _sprite: Sprite2D = $Sprite

var _wait := 0.0

func _ready() -> void:
	_sprite.frame = randi() % _sprite.hframes

func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = randf_range(frame_seconds.x, frame_seconds.y)
	# Never the same shape twice running, so every change shows.
	_sprite.frame = (_sprite.frame + 1 + randi() % (_sprite.hframes - 1)) % _sprite.hframes
