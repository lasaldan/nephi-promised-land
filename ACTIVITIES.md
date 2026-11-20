# Activities

Small hands-on tasks that break up the questing. There are three kinds:

- **Scroll boards**: open on the activity scroll (paper on the right half,
  camera slid so Nephi stands in the middle of the left half). Each is a
  `ScrollBoard` in `ui/activities/`, listed in `ActivityScroll.BOARDS`, and
  started from a chapter with `doActivity("id")`.
- **World quests**: played in the world with the joystick, Use and the
  backpack. These need no board, just a chapter, props and sometimes a new
  world mechanic.
- **Tweaks to existing systems**, such as the prayer button.

Bountiful (`../../nephi_builds_a_ship/nephi-builds-a-ship/ACTIVITIES.md`) has
the full write-ups of its rope, saw and nail boards. They are good patterns,
and some of them come back here reskinned.

**Status:** Liahona steering (`steer`), the held prayer, and gold panning
(`pan`) are built. Everything else is a decision, not code yet.

---

## Rules every scroll board follows

These are for players as young as four or five.

- **One gesture.** Each board uses one kind of input: tap, drag, hold, or
  circle (swirl). It never uses two.
- **The next target glows.** Nobody has to read or guess what to do next.
- **No failing.** A wrong tap wiggles, and nothing resets or is lost.
- **Progress shows right away.** Every correct action visibly changes
  something.
- **Short.** About 10–20 actions, under a minute.
- **The work stays in the world.** Finishing shows a prop, moves the ship,
  or adds an item to the backpack.
- **Mouse and touch both work** (`ScrollBoard.is_press`, `is_drag`,
  `is_emulated`).
- **Small targets are a problem.** The board is only half of a phone screen.
  Avoid anything that needs fine tracing or tiny shapes.

A board that needs settings from the chapter (how much gold a spot holds,
say) gets them as `config`: `doActivity("pan", "", 0, focus, {"flakes": 3})`.
They are in `board.config` before `reset()`.

---

## Decisions by story part

### On the ship

| Beat | Decision | Kind |
|---|---|---|
| Steer by the Liahona | **Built** (`steer`). See below. Played before the storm and again after it. | board |
| Lamps at dusk | Nephi takes a lit candle or stick from the lamps below deck. Its light follows him, and Use near an upper-deck lamp lights it. | world quest |
| Tend Mother | Words of comfort: Nephi sits on the bed or the floor beside her and brings her things. No board. | world quest |
| Prayer that calms the storm | **Built.** The existing pray button, held. See below. | tweak |
| Tidy the deck after the storm | Find the fruit scattered about the ship, some hidden behind things so it is tricky to see, and put each into its correct bin. | world quest |
| Furl / raise the sail on arrival | Maybe. Hand over hand on the rope, and the sail rises a frame with each pull. Skip it if the hands are too much art; a prototype would show whether it is worth it. | board (maybe) |

### First camp

| Beat | Decision | Kind |
|---|---|---|
| Find the spot from the vision | Not here. It is used for the land of Nephi (below). | — |
| Pitch tents | At the night camps while fleeing (2 Nephi 5), with the hammer. Reuses Bountiful's nail board, with stakes and a mallet. | board |
| Campfire | Skipped. | — |
| Till, plant, water, harvest | World quests, not boards. Take a hoe and press Use to prepare a plot, choose which seeds to plant, plant them, water them, and later harvest them all. | world quests |
| Store the food | Sorting the harvest into the right jars and baskets. | board |
| Flowers at the graves | Gather flowers in the world, then place them around the grave. Quiet, with no glow pressure and no score. For both Sariah and Lehi. | world quest + gentle board |

### Animals and ore

| Beat | Decision | Kind |
|---|---|---|
| Find the animals | One quest per animal, each with habits. The **cow** plods. The **donkey** stops a lot. The **goat** jumps up onto anything short (stumps, rocks, logs), then hops off and catches up. Once caught, each follows Nephi home. | world quests |
| Gold | **Built** (`pan`). Panning in the stream, done several times along it to find the best spot. See below. | board |
| Silver and copper | Hidden caves in the tileset, blocked by debris. Clear the debris, go in, and pick the walls for copper and silver. | world quest |
| Smelting | Heat the metal (bellows) and pour it into molds. Needed for the plates and the sword. | board |

### Plates and record

| Beat | Decision | Kind |
|---|---|---|
| Make the plates | Hammer the ingot flat (tap glowing spots, like the nail board), then punch the ring holes. | board |
| Engrave | Tracing letters or glyphs. Probably too fiddly on half a phone screen; revisit later. | undecided |
| Memory card game | Skipped here. Maybe later as a game the children play around camp, which Nephi can join. | later |

### Fleeing to Nephi

| Beat | Decision | Kind |
|---|---|---|
| Pack the donkey | Load the saddlebags left and right and keep them balanced. If it tips, the donkey leans and brays. Nothing is lost. | board |
| Find the spot | The hot/cold "find the place from the vision" search, when they look for their new home in Nephi. The vision picture sharpens as Nephi nears the right place. | world quest |
| Carve the "Nephi" sign | Tracing the name. It needs a plan for other languages. | board |
| Sort the animals | Walk into the mixed herd, choose an animal to grab, and lead it to its pen. The quest is done when every animal is in a pen with its own kind. | world quest |

### Town and temple

| Beat | Decision | Kind |
|---|---|---|
| Town planner | Like blueprints for the city: some buildings are fixed in place and others can go on any free lot. | board |
| Assign jobs | Drag a tool to a person: a hammer to the smith, a bow to the hunter, a sack of grain to the animal tender, a hoe to the farmer. Each one gets to work in the world. | board |
| Temple timber | Lots of lumber, but pick only the best. | board or world |
| Cut stone | Tap along the chalk line. | board |
| Fit stones | Drag blocks into the wall's outline, where they snap into place. | board |
| Polish | Rub the brass and gold until it shines. | board |
| Weave the veil | Left and right taps on the loom, like the rope braid, and a pattern grows. | board |
| Copy the sword of Laban | Heat, hammer and quench at the forge. | board(s) |

Crafting at the forge stays, with new recipes for new items.

---

## Steering by the Liahona (`steer`) — built

**Gesture:** drag (turn the wheel).

**On the scroll:** the Liahona's dial at the top, seen from above. A glowing
wedge sits at the top of the dial: that is straight ahead, over the bow. The
spindle points the way the Lord would have them go, so it swings as the ship
turns. Below the dial is the ship's wheel.

**Difficulty:** each save slot picks Normal or Hard in the pause menu
(`StoryState.difficulty`, written to the save at once). The board reads it
each time it opens. Normal is for the youngest players.

**Play:**
1. Grab the wheel anywhere and turn it. It follows the finger around its hub,
   so a swipe across the top of the wheel turns it too. One spoke, the king
   spoke, is marked in brass.
2. *Normal:* the wheel points the ship. Turning it turns the ship in the
   world (`ShipSway.heading`, from -10 to +10 degrees), easing a little behind
   the wheel like a real helm. The king spoke at the top means on course.
   The wedge is wide (±1.5 degrees).
3. *Hard:* the wheel sets how fast the ship turns, not where it points.
   While the king spoke stands at the top the ship holds its heading. Turned
   off center, the ship comes around, the further the quicker, easing into
   and out of the turn. To hold the new course, put the wheel back to center;
   let go near center and it settles there by itself. The wedge is half as
   wide (±0.75 degrees).
4. Either way the spindle swings with the ship. While it is in the wedge, the
   wedge glows brighter and a ring around the dial fills. Out of the wedge,
   the ring just stops filling. It never empties.
5. A curved arrow over the wheel shows which way to turn it: toward the
   course while off it, and on hard, back to center as the ship comes onto
   it. It hides while the wheel is already right.

**Done:** after `ALIGN_SECONDS` (4) with the spindle in the wedge, the dial
pulses and the board emits finished. The ship keeps the heading it was
given, and the wheel rights itself.

**Twice in the story:**
- *Before the storm:* the chapter turns the ship off course first, such as
  `await setShipHeading(3.0, 3.0)`, so there is something to correct, then
  `doActivity("steer", "up")`. Kept small: the whole ship tilts with the
  heading, which makes walking the deck awkward.
- *During the storm:* the Liahona stops working and the ship drifts to an odd
  angle (`setShipHeading(-9.0, 6.0)`). An NPC notices that they are no
  longer going the right way.
- *After the storm:* `resetActivity("steer")`, then `doActivity("steer")`
  again. The board starts from wherever the storm left the ship.

The heading is saved with each chapter, like the sea (`World.HEADING_FLAG`).

**Knobs:** `ALIGN_SECONDS`; `NORMAL_WEDGE_DEGREES` and `HARD_WEDGE_DEGREES`,
how close counts as on course (in ship degrees); `NORMAL_DIAL_SCALE` and
`HARD_DIAL_SCALE`, how far the spindle swings per ship degree. Normal:
`WHEEL_TURN_PER_DEGREE`, how far the wheel turns for one degree of ship;
`HELM_DEGREES_PER_SECOND`, how quickly the ship follows. Hard:
`WHEEL_PER_RATE`, wheel degrees for one degree a second of turn;
`WHEEL_LIMIT`, how far the wheel turns either way; `CENTER_DEGREES`, the
slack at center; `HELM_RESPONSE`, how quickly the turn follows the wheel.
`config` can set `"target"`, the heading the spindle points to (default 0).

---

## Held prayer — built

**Gesture:** hold the pray button.

The usual pray button, for one beat: Nephi praying at the Liahona so the
storm calms (1 Nephi 18:21). The chapter arms it with
`waitForHeldPrayer(seconds, on_progress)`. While it is armed, the pray button
shows even with nothing to point at.

- Pressing and holding folds Nephi's hands, and a soft light grows around
  him. `progress` climbs from 0 to 1 over `seconds` of holding.
- Letting go lets it sink back slowly (`HELD_FALL_RATE`, a third as fast).
  So a tap barely changes anything, and holding for a few seconds calms the
  storm.
- At 1, the prayer is answered: it stays at 1 and `waitForHeldPrayer`
  returns.

The chapter decides what progress does. Rain and sea stay separate, so the
chapter moves each itself:

    await waitForHeldPrayer(4.0, func(p: float) -> void:
        world.rain.intensity = lerpf(1.0, 0.15, p)
        world.ship.sea = 1.0 - p)
    rainStops(4.0)
    seaCalms(4.0)

---

## Gold panning (`pan`) — built

**Gesture:** circle (swirl).

**On the scroll:** a pan seen from above, with water in it and a mound of
sand and gravel. A ring of dots runs around the pan to show the swirl.

**Play:**
1. Swirling a finger around the pan, in either direction, sets the water
   turning. The sand turns with it.
2. Swirling washes sand out: grains drift to the rim and spill over, the
   outside of the mound first, so the mound shrinks toward the middle.
3. Whatever gold the spot holds lies under the sand and shows as the mound
   thins.

**Done:** after `TURNS` (6) swirls the sand is gone. Any gold glints, and
the board emits finished.

**Several spots:** the chapter says how much gold each spot holds with
`config` (`{"flakes": 0}` to `{"flakes": 8}`). A poor spot is still fine
(a speck or two, or just sand), and Nephi tries further along the stream.
Use `resetActivity("pan")` before each new spot. The chapter gives the gold
item afterward.

**Knobs:** `TURNS`; `GRAINS`; `config.flakes`.
