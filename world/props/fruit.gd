class_name Fruit
extends RefCounted

# The fruits and vegetables on world/tilesets/fruits-veggies-box.png (32px
# tiles), shared by FruitBox and FruitPickup so both offer the same dropdown.
# Each kind is listed by its single-fruit tile. Below it on the sheet are a
# few of them (+1), a heap (+2), and its crate, two tiles tall (+3 and +4).
#
# Scenes save a kind as its number, so add new kinds at the end of Kind (and
# to TILES); moving one would turn every placed one into something else.

const SHEET: Texture2D = preload("res://world/tilesets/fruits-veggies-box.png")
const TILE := 32

enum Kind {
	HONEY,
	SEEDS,
	RED_GRAPES,
	BLACK_GRAPES,
	PURPLE_GRAPES,
	GREEN_GRAPES,
	CARROTS,
	PINEAPPLE,
	PEAS,
	GREEN_BEANS,
	CABBAGE,
	SMALL_SQUASH,
	LARGE_SQUASH,
	PUMPKIN,
	GOURD,
	WATERMELON,
	TOMATO,
	SMALL_PEPPERS,
	POTATO,
	RED_APPLE,
	GREEN_APPLE,
	YELLOW_APPLE,
	HONEYCRISP_APPLE,
	PEAR,
	YELLOW_PEAR,
	CHERRY,
	PEACH,
	ORANGE,
	GRAPEFRUIT,
	LEMON,
	LIME,
	BANANA,
	PLANTAIN,
	COCONUT,
	CORN,
}

# How much of it there is: the rows under the single fruit.
enum Amount { ONE, FEW, MANY, CRATE }

# Column and row of each kind's single-fruit tile.
const TILES := {
	Kind.HONEY: Vector2i(10, 25),
	Kind.SEEDS: Vector2i(11, 25),
	Kind.RED_GRAPES: Vector2i(8, 20),
	Kind.BLACK_GRAPES: Vector2i(9, 20),
	Kind.PURPLE_GRAPES: Vector2i(10, 20),
	Kind.GREEN_GRAPES: Vector2i(11, 20),
	Kind.CARROTS: Vector2i(24, 20),
	Kind.PINEAPPLE: Vector2i(12, 15),
	Kind.PEAS: Vector2i(0, 10),
	Kind.GREEN_BEANS: Vector2i(1, 10),
	Kind.CABBAGE: Vector2i(1, 5),
	Kind.SMALL_SQUASH: Vector2i(31, 5),
	Kind.LARGE_SQUASH: Vector2i(31, 0),
	Kind.PUMPKIN: Vector2i(28, 0),
	Kind.GOURD: Vector2i(29, 0),
	Kind.WATERMELON: Vector2i(22, 0),
	Kind.TOMATO: Vector2i(5, 0),
	Kind.SMALL_PEPPERS: Vector2i(4, 0),
	Kind.POTATO: Vector2i(0, 0),
	Kind.RED_APPLE: Vector2i(0, 30),
	Kind.GREEN_APPLE: Vector2i(1, 30),
	Kind.YELLOW_APPLE: Vector2i(3, 30),
	Kind.HONEYCRISP_APPLE: Vector2i(4, 30),
	Kind.PEAR: Vector2i(5, 30),
	Kind.YELLOW_PEAR: Vector2i(6, 30),
	Kind.CHERRY: Vector2i(8, 30),
	Kind.PEACH: Vector2i(9, 30),
	Kind.ORANGE: Vector2i(14, 30),
	Kind.GRAPEFRUIT: Vector2i(15, 30),
	Kind.LEMON: Vector2i(17, 30),
	Kind.LIME: Vector2i(18, 30),
	Kind.BANANA: Vector2i(0, 35),
	Kind.PLANTAIN: Vector2i(1, 35),
	Kind.COCONUT: Vector2i(4, 35),
	Kind.CORN: Vector2i(28, 10),
}

# The part of SHEET showing that much of it, in pixels. A crate is two tiles
# tall; the rest are one.
static func region(kind: Kind, amount: Amount) -> Rect2:
	var tile: Vector2i = TILES[kind]
	if amount == Amount.CRATE:
		return Rect2(tile.x * TILE, (tile.y + 3) * TILE, TILE, TILE * 2)
	return Rect2(tile.x * TILE, (tile.y + amount) * TILE, TILE, TILE)

# "Red Apple" for RED_APPLE.
static func display_name(kind: Kind) -> String:
	return (Kind.keys()[kind] as String).capitalize()

# A backpack picture of it: the few-of-them tile.
static func icon(kind: Kind) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = SHEET
	atlas.region = region(kind, Amount.FEW)
	return atlas
