extends StoryChapter

# Out on the sea, the morning after the title. Nephi starts on the upper deck,
# free to walk the ship. Its Set is Chapters/ShipAtSea: the ship, the sea, and
# whoever is already placed below decks.
#
# Nephi remembers Bountiful and goes to check on Sam at the helm. Sam says
# the ship and the Liahona are working well, and Nephi heads below to check
# on the others and the animals. At the pen, Sariah, resting in her bunk,
# asks for a banana; Nephi fetches one from the crate upstairs and brings it
# down. While he talks with her the ship drifts off course, and back at the
# helm Sam hands him the wheel to steer by the Liahona. Held for now after
# that: the rest of the opening scene in STORY_SCRIPT.txt (lighting the lamps
# at dusk, Lehi's family prayer) goes on from there.

const NEPHI_START := Vector2(3.5, 3.6)

# Who is up on deck at the start (Ship/Upper in world.tscn, placed and facing
# there): Sam at the helm, Zoram and Ishmael's son at the north rail, Laman
# and Lemuel at the south rail, Nephi's sister in the bow looking west, the
# way the ship is going. They hold that for DECK_HOLD_SECONDS, then wander a
# little, each this many tiles from where they stood. The radii keep them clear
# of the stairwell's open east end, which only Nephi can use. Sam stays at
# the helm, steering: he faces west, the way the ship is going, and now and
# then reaches out to make a small turn (Tend).
const DECK_HOLD_SECONDS := 10.0
const DECK_WANDER := {
	"Zoram": 1.5,
	"IshmaelSon1": 1.5,
	"Laman": 1.5,
	"Lemuel": 1.5,
	"Sister1": 1.0,
}

# How close Nephi walks up to Sam for their talk to start, in tiles.
const SAM_REACH := 1.5

# The animal pen in the hold (Ship/Lower), in tiles: about the middle of the
# chickens, goats and sheep, and how near Nephi must come on the lower deck.
# The decks share the same tiles, so standing above it does not count.
const PEN_CENTER := Vector2(16.2, 6.1)
const PEN_REACH := 2.5

# Sariah in her bunk below (Ship/Lower/SleepingSariah), awake for this
# chapter, and how near Nephi must come to hand her the banana.
const SARIAH_REACH := 1.75

# The banana crate upstairs (Ship/Upper/BananaBox, a FruitPickup in PICK
# mode, so the crate stays). It is offered only during that quest.
const BANANA := "Banana"

# The ship drifts off course while Nephi is below, this many degrees over
# this many seconds, for the steering board to put right.
const DRIFT_DEGREES := 3.0
const DRIFT_SECONDS := 8.0

# Once Sariah has her banana, wisps of fog start drifting past: every few
# seconds the fog eases to a new thin density, never above FOG_WISPS_MAX.
const FOG_WISPS_MAX := 0.2
const FOG_WISPS_SECONDS := Vector2(3.0, 6.0)

# At the helm, on Ship/Upper in pixels: where Sam stands to steer (and Nephi
# while he takes the wheel), where Sam steps aside to meanwhile, and where
# Nephi steps back to after.
const HELM_SPOT := Vector2(520, 96)
const SAM_ASIDE := Vector2(548, 124)
const NEPHI_AFTER_STEERING := Vector2(530, 134)

# Seconds the ship takes to ease back to exactly on course (heading 0) after
# Nephi steers.
const SQUARE_UP_SECONDS := 2.0

func _init() -> void:
	id = "ship_at_sea"
	title = "Ship at Sea"
	starts_after = "intro"
	ends_on = END_ON_HOLD

func setup(w):
	super(w)
	disablePlayerControls()
	var player = getPlayer()
	player.set_deck(ShipStairs.Deck.UPPER)
	player.position = NEPHI_START * 32
	player.facing = "down"
	(world.get_node("Player/Camera") as Camera2D).reset_smoothing()
	(_upper().get_node("Sam") as Npc).set_habit(Tend.new("left"))
	_sariah().pose("lie", "left")

func play():
	# Fade in from the black the intro's title left.
	await endCutscene(false, true)
	disablePlayerControls()
	await show_dialogue("ship_at_sea_opening")
	world.setQuest("quest_check_on_sam")
	enablePlayerControls()
	_wander_after_hold()

	var sam := _upper().get_node("Sam") as Npc
	await _waitForPlayerOnDeck(ShipStairs.Deck.UPPER, sam.get_global_position, SAM_REACH)
	disablePlayerControls()
	faceEachOther(getPlayer(), sam)
	await show_dialogue("sam_at_helm")
	# Back to the helm, looking the way the ship is going.
	sam.release()
	world.setQuest("quest_check_animals")
	enablePlayerControls()

	var lower := _lower()
	await _waitForPlayerOnDeck(ShipStairs.Deck.LOWER, func() -> Vector2: return lower.to_global(PEN_CENTER * 32.0), PEN_REACH)
	disablePlayerControls()
	await show_dialogue("animals_settled")

	# Up to the crate for a banana.
	var crate := _upper().get_node("BananaBox") as Collectable
	crate.collectable = true
	setPickupList(BANANA)
	setPickupLimit(1)
	world.setQuest("quest_banana_for_mother")
	enablePlayerControls()
	await waitForItemAdded(BANANA)
	crate.collectable = false
	setPickupList()

	# And back down to her.
	world.setQuest("quest_banana_to_mother")
	var sariah := _sariah()
	await _waitForPlayerOnDeck(ShipStairs.Deck.LOWER, sariah.get_global_position, SARIAH_REACH)
	disablePlayerControls()
	# Only Nephi turns: she stays lying in her bunk.
	faceToward(getPlayer(), sariah)
	emptyBackpack()
	# Not awaited: the ship drifts while they talk and he goes back up.
	setShipHeading(DRIFT_DEGREES, DRIFT_SECONDS)
	await show_dialogue("sariah_banana")
	world.fog.drift(FOG_WISPS_MAX, FOG_WISPS_SECONDS)

	world.setQuest("quest_check_course")
	enablePlayerControls()
	await _waitForPlayerOnDeck(ShipStairs.Deck.UPPER, sam.get_global_position, SAM_REACH)
	disablePlayerControls()
	faceEachOther(getPlayer(), sam)
	await show_dialogue("sam_off_course")
	world.setQuest("")

	# Sam steps aside and Nephi takes the wheel.
	sam.go_to(SAM_ASIDE / 32.0).then_face("left")
	await walkPlayerTo(_upper().to_global(HELM_SPOT) / 32.0, "left")
	await doActivity("steer", "left")
	# The wheel leaves the ship a hair off; square it up exactly, which keeps
	# the pixel art crisp. Not awaited: it eases round as he steps back.
	setShipHeading(0.0, SQUARE_UP_SECONDS)

	# Nephi steps back and is free again while Sam returns to the helm.
	await walkPlayerTo(_upper().to_global(NEPHI_AFTER_STEERING) / 32.0, "up")
	enablePlayerControls()
	await walkTo(sam, HELM_SPOT / 32.0)
	sam.release()
	# Next: dusk, the lamps, and Lehi's family prayer.

# Like waitForPlayerNear, but only on the given deck: the hold is under the
# upper deck's tiles, so standing above or below the spot does not count.
# where gives the spot in world pixels, read each frame since the ship sways
# and sails. Prayer for guidance points to it meanwhile.
func _waitForPlayerOnDeck(deck: ShipStairs.Deck, where: Callable, tiles: float) -> void:
	var player := getPlayer()
	var reach := tiles * 32.0
	var guidance := setGuidance(where)
	while player.deck != deck or player.global_position.distance_to(where.call()) > reach:
		await nextFrame()
	clearGuidance(guidance)

func _lower() -> Node2D:
	return world.get_node("Chapters/ShipAtSea/Ship/Lower")

func _sariah() -> Npc:
	return _lower().get_node("SleepingSariah") as Npc

func _upper() -> Node:
	return world.get_node("Chapters/ShipAtSea/Ship/Upper")

# A held chapter is let go once play() returns, so nothing here can await
# past that: the timer calls straight into each person instead. Pausing
# (the menu) pauses it too.
func _wander_after_hold() -> void:
	var upper := _upper()
	var timer: SceneTreeTimer = world.get_tree().create_timer(DECK_HOLD_SECONDS, false)
	for person in DECK_WANDER:
		var npc := upper.get_node_or_null(person) as Npc
		if npc:
			timer.timeout.connect(npc.set.bind("facing", ""))
			timer.timeout.connect(npc.set_habit.bind(Meander.new(DECK_WANDER[person])))
