extends StoryChapter

# Out on the sea, the morning after the title. Nephi starts on the upper deck,
# free to walk the ship. Its Set is Chapters/ShipAtSea: the ship, the sea, and
# whoever is already placed below decks.
#
# Held for now: the opening scene in STORY_SCRIPT.txt (checking on everyone
# below, taking them food, steering by the Liahona, lighting the lamps at
# dusk, Lehi's family prayer) goes here.

const NEPHI_START := Vector2(3.5, 3.6)

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

func play():
	# Fade in from the black the intro's title left.
	await endCutscene(false, true)
	enablePlayerControls()
