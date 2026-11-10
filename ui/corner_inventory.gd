extends Control

# Shared with the player. Kept as a const so a cleared scene export can be restored.
const PACK: Inventory = preload("res://player/inventory/player_inventory.tres")

@export var inventory: Inventory = PACK
var is_open = false

# Right edge of the icon row, just left of the backpack. Captured in _ready so
# the scene layout stays the source of truth.
var _strip_right := 0.0
# The bar's right end, on the backpack's left edge, so the bar seems to start
# from the backpack's background. Closed, the bar is shut down to nothing here.
var _bar_right := 0.0
# Bar showing to the left of the last icon when open.
const BAR_PAD := 4.0
var _pack_tween: Tween
# Played as each item reaches the pack, and as each one leaves it.
const PACK_SOUND: AudioStream = preload("res://audio/sfx/add_to_inventory.ogg")
var _pack_sound: AudioStreamPlayer

func _ready():
	# world.tscn saved this export as null while the script failed to parse.
	if inventory == null:
		inventory = PACK
	# Collapsed in the scene: position.x is the backpack edge, size.x is 0.
	_strip_right = $Items.position.x
	var backpack: Control = $Backpack
	_bar_right = backpack.position.x
	# The right end is fixed here and only the left end ever moves, in whole
	# pixels (_set_bar_left). Controls are drawn snapped to the pixel but their
	# width is not, so a fractional left end jiggles the right end off the
	# backpack while the bar slides.
	var items: Control = $Items
	items.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	items.offset_right = _bar_right
	items.offset_left = _bar_right
	_square_backpack_edges()
	_pin_slots_to_backpack()
	SignalBus.player_inventory_change.connect(update_inventory)
	SignalBus.player_item_added.connect(_on_item_added)
	SignalBus.player_items_removed.connect(_on_items_removed)
	_pack_sound = AudioStreamPlayer.new()
	_pack_sound.stream = PACK_SOUND
	_pack_sound.bus = GameSettings.SFX
	# A pack emptied of five things sends them out close together.
	_pack_sound.max_polyphony = 6
	add_child(_pack_sound)
	update_inventory()

func update_inventory():
	for slot_index in range(inventory.items.size()):
		var inventory_item = inventory.items[slot_index]
		# Slot nodes are Slot0 .. SlotN-1, matching inventory.items.
		var slot = get_node_or_null("Items/Wrapper/Slots/Slot" + str(slot_index))
		if slot == null:
			push_warning("Backpack has no Slot%s for inventory entry %s" % [slot_index, slot_index])
			continue

		if inventory_item:
			var stacks: bool = inventory_item.stack_size > 1
			# First time this slot fills, fly the icon into the backpack.
			# A stacking item flies in on every pickup instead (_on_item_added).
			if slot.item == null and not stacks:
				$ItemAdd.texture = inventory_item.icon
				$AddAnimation.play("add_to_pack")
			slot.item = inventory_item
			if stacks:
				slot.get_node("DisplayTexture").texture = null
				slot.show_stack(inventory_item.icon, inventory_item.stack_tints)
			else:
				slot.get_node("DisplayTexture").texture = inventory_item.icon
				slot.show_stack(null, [])
			slot.visible = true
		else:
			slot.item = null
			slot.get_node("DisplayTexture").texture = null
			slot.show_stack(null, [])
			# Empty panels stay out of the row so the open animation never reveals them.
			slot.visible = false

	# Width follows whatever is actually in the pack. A closed strip stays closed.
	_pin_slots_to_backpack()
	if is_open:
		_animate_strip(_filled_width())

func _on_inventory_toggle() -> void:
	if is_open:
		_animate_strip(0.0)
		is_open = false
	else:
		_show_strip()

# A pickup always shows the pack, even if the player closed it, so the count
# stays in view. player_inventory_change fires first, so the new slot is
# already filled and the width includes it.
func _on_item_added(item: InventoryItem) -> void:
	if item.stack_size > 1:
		_fly_into_pack(item.icon, _latest_tint(item.name))
	_show_strip()
	# When the icon gets to the pack. Both fly-ins take one add_to_pack.
	get_tree().create_timer(_fly_duration(), false).timeout.connect(_pack_sound.play)

# Out of the pack, one slot at a time, LEAVE_GAP seconds apart, with one sound
# each. A stack sends out one icon for each thing in it, in its own tint, in a
# rush STACK_GAP seconds apart, so a full pack of seeds pours out in about a second.
const LEAVE_GAP := 0.15
const STACK_GAP := 0.015

func _on_items_removed(items: Array[InventoryItem]) -> void:
	var delay := 0.0
	for item in items:
		if item.stack_size > 1:
			for i in item.quantity:
				var tint: Color = item.stack_tints[i] if i < item.stack_tints.size() else Color.WHITE
				_fly_out_of_pack(item.icon, tint, STACK_FLY_SCALE, delay + i * STACK_GAP, i == 0)
		else:
			_fly_out_of_pack(item.icon, Color.WHITE, 0, delay)
		delay += LEAVE_GAP

# add_to_pack backwards: from the pack down to where a pickup flies in from,
# fading out over the second half. An icon_scale of 0 fits the icon to ItemAdd's
# box, as add_to_pack shows it; a stacking item's tiny icon is drawn at icon_scale.
# With sound false it leaves quietly, as the rest of a stack does after its first.
func _fly_out_of_pack(icon: Texture2D, tint: Color, icon_scale: int, delay: float, sound: bool = true) -> void:
	var flyer := TextureRect.new()
	flyer.texture = icon
	flyer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flyer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flyer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var box: Vector2 = $ItemAdd.size
	var drawn := box if icon_scale <= 0 else icon.get_size() * icon_scale
	flyer.size = drawn
	var centre := (box - drawn) / 2.0
	flyer.position = FLY_TO + centre
	# Hidden until its turn, so a queue of them does not sit on the backpack.
	flyer.modulate = Color(tint, 0.0)
	add_child(flyer)
	var duration := _fly_duration()
	var nudge := Vector2(randf_range(-10, 10), randf_range(-4, 4)) if icon_scale > 0 else Vector2.ZERO
	var tween := flyer.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func():
		flyer.modulate.a = 1.0
		if sound:
			_pack_sound.play())
	tween.tween_property(flyer, "position", FLY_FROM + centre + nudge, duration)
	tween.parallel().tween_property(flyer, "modulate:a", 0.0, duration / 2.0).set_delay(duration / 2.0)
	tween.tween_callback(flyer.queue_free)

# add_to_pack is 1 second long, played at AddAnimation's speed.
func _fly_duration() -> float:
	var player: AnimationPlayer = $AddAnimation
	return 1.0 / player.speed_scale

# add_to_pack, as a tween on a copy of ItemAdd, so a run through a patch of
# plants sends up several seeds at once. Each starts a little to one side, and
# the icon is drawn at STACK_FLY_SCALE since a stacking item's icon is tiny.
const STACK_FLY_SCALE := 3
const FLY_FROM := Vector2(145, 40)
const FLY_TO := Vector2(185, 4)

func _fly_into_pack(icon: Texture2D, tint: Color) -> void:
	var flyer := TextureRect.new()
	flyer.texture = icon
	flyer.modulate = tint
	flyer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flyer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flyer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var box: Vector2 = $ItemAdd.size
	var drawn := icon.get_size() * STACK_FLY_SCALE
	flyer.size = drawn
	# Centred where ItemAdd's icon would be, nudged so a burst spreads out.
	var nudge := Vector2(randf_range(-10, 10), randf_range(-4, 4))
	var centre := (box - drawn) / 2.0
	flyer.position = FLY_FROM + centre + nudge
	add_child(flyer)
	var duration := _fly_duration()
	var tween := flyer.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flyer, "position", FLY_TO + centre, duration)
	tween.tween_property(flyer, "modulate:a", 0.0, duration / 2.0).set_delay(duration / 2.0)
	tween.chain().tween_callback(flyer.queue_free)

func _show_strip() -> void:
	_animate_strip(_filled_width())
	is_open = true

# How wide the open strip should be: only slots that hold an item, plus the gaps between them.
func _filled_width() -> float:
	var slots: HBoxContainer = $Items/Wrapper/Slots
	return slots.get_combined_minimum_size().x

# Keep the row glued to the backpack end of the bar, ending where the backpack
# starts. The bar then opens leftward over this row, so the first item stays
# next to the button and later items appear to its left. Hidden (empty) slots
# add no width.
func _pin_slots_to_backpack() -> void:
	var slots: Control = $Items/Wrapper/Slots
	var width := _filled_width()
	slots.anchor_left = 1.0
	slots.anchor_right = 1.0
	slots.offset_right = _strip_right - _bar_right
	slots.offset_left = slots.offset_right - width

# open_pack in the scene always expands to a full bar. The width has to follow
# the filled slots, so this tween uses that animation's length and playback speed
# but drives the clip itself.
func _animate_strip(width: float) -> void:
	_pin_slots_to_backpack()
	var items: Control = $Items
	if _pack_tween:
		_pack_tween.kill()
	_pack_tween = create_tween()
	_pack_tween.set_parallel(true)
	_pack_tween.set_trans(Tween.TRANS_CUBIC)
	_pack_tween.set_ease(Tween.EASE_IN_OUT)
	var duration := _open_duration()
	# An empty pack shows no bar at all, not just the tail and padding.
	var bar := 0.0
	if width > 0.0:
		bar = width + BAR_PAD + (_bar_right - _strip_right)
	# Right end stays on the backpack edge. Only the left end moves.
	_pack_tween.tween_method(_set_bar_left, items.offset_left, _bar_right - bar, duration)

func _set_bar_left(left: float) -> void:
	$Items.offset_left = roundf(left)

# The bar and the backpack meet on a half pixel at the game's 2.5x scale.
# Anti-aliased, each fades out across that pixel and a light line shows
# between them. Without it, the shared edge fills the pixel exactly once. The
# bar's style is set in the scene; the button's comes from the HUD theme, so
# it gets its own copies here.
const BACKPACK_ICON_MARGIN := 1.0

func _square_backpack_edges() -> void:
	var button: Button = $Backpack/Button
	for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var style := button.get_theme_stylebox(state)
		if style is StyleBoxFlat:
			var crisp: StyleBoxFlat = style.duplicate()
			crisp.anti_aliasing = false
			# Thinner than the theme's 4 so the backpack fills more of its square.
			crisp.set_content_margin_all(BACKPACK_ICON_MARGIN)
			button.add_theme_stylebox_override(state, crisp)

func _open_duration() -> float:
	# open_pack is 1 second long in CornerInventory.tscn. Reading it through
	# get_animation() is untyped on a $ lookup, which GDScript refuses to infer.
	var player: AnimationPlayer = $OpenAnimation
	var speed: float = player.speed_scale
	if speed <= 0.0:
		return 1.0
	return 1.0 / speed

# The tint of the newest item_name in the pack. Slots fill in order, so it is
# the last one in the last slot holding it.
func _latest_tint(item_name: String) -> Color:
	for slot_index in range(inventory.items.size() - 1, -1, -1):
		var held: InventoryItem = inventory.items[slot_index]
		if held and held.name == item_name and not held.stack_tints.is_empty():
			return held.stack_tints.back()
	return Color.WHITE
