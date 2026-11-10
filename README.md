# The Promised Land

The engine from *Bountiful: Nephi Builds a Ship*, cleaned up as a starting
point: no story, no map, ready for both. Godot 4.7.

The commit tagged `template-v1` is that clean starting point. The prequel
starts from the same commit:

    git clone <this repo> ../../prequel/project && cd ../../prequel/project
    git checkout -b main template-v1

## Layout

| Folder | What is in it |
| --- | --- |
| `core/` | Autoloads (SignalBus, StoryState, RenderClock, ScreenShape, Screenshot) and static helpers: `GameSettings`, `Language`, `Interaction` |
| `world/` | `world.tscn` and `world.gd`: the map, the HUD, the chapter director |
| `world/lighting/` | `DayNight` (time of day), `FlickerLight`, a campfire light |
| `world/ambience/` | `AmbientZone` (looping sound inside a rectangle), `ShoreWaves`, `FireSound` |
| `world/navigation/` | `WorldNavigation`: where people can walk, built from the map's collision |
| `world/wildlife/` | `FlyingBird` (15 bird types), `Butterfly` |
| `world/props/` | `Collectable` (anything that goes in the backpack), `Artifact` (look closely) |
| `world/items/` | Inventory items and their icons |
| `characters/` | `Npc`, `person.tscn` (every person's shared scene), `Cast` (find anyone by name) |
| `characters/cast/` | One folder per person: sprite sheet, CharGen sources, a three-line scene |
| `characters/animals/` | `FarmAnimal` (chicken, goat, sheep), `Bunny`, `farm_animals.png` |
| `characters/habits/` | What NPCs do on their own: `Idle`, `Meander`, `Patrol`, `Follow`, `Station` |
| `player/` | Movement, use, praying (`Prayer`), footsteps, the backpack |
| `story/` | The chapter engine (`StoryChapter`, `Story`, `Chapters`, triggers, prop groups), `SmallTalk`, achievements, artifacts, the dialogue balloon |
| `story/text/` | Quest, caption, scripture and controls-tour text tables (voiced and translated by the tools) |
| `story/main.dialogue` | Every line, by title |
| `ui/` | HUD pieces, pause/settings menu, achievement list and toast, scripture scroll, activity scroll |
| `menus/` | Splash, main menu (three save slots), credits |
| `audio/` | Music, ambience, animal calls, footsteps, sound effects |
| `voice/` | Voice clips by speaker (`voice/<speaker>/<ID>.mp3`, Spanish under `voice/es/`) |
| `translations/` | `es.po` |
| `tools/` | `voice/` (manifest, generate), `i18n/` (update es.po), logo and credits builders |

The parent folder (not in git) holds the art sources, `tools/` (sprite
scripts, the CharGen converter, the overview renderer, headless tests), the
Godot binary, builds and the keystore.

## Starting the story

1. Make a chapter: in the FileSystem dock, New Script in `story/chapters/`
   using the *Story Chapter* template. Its checklist is at the top.
2. Add it to `Story.CHAPTER_SCRIPTS` (`story/story.gd`).
3. Give it a Set: a Node2D under `Chapters` in `world/world.tscn` with
   `story/chapter_content.gd` and its `chapter_id`.

With no chapters the world opens straight into free play, which is handy
while building the map.

## The world

Put the map under `GroundLayer` and delete `PlaceholderGround`. Then:

- **Walking**: nothing to paint. `WorldNavigation` makes the walkable area
  from tile collision and every StaticBody2D in play, and rebuilds when a
  chapter starts or a Collectable is taken. Debug > Visible Navigation shows
  it. Give it `bounds` if the map's used cells are not the right area.
- **Footsteps**: add a custom data layer named `surface` (String) to a
  TileSet and paint `grass`, `sand`, `stone` or `wood`.
- **Time of day**: `world.day_night`, or from a chapter `nightfall()`,
  `daybreak()`, `setTimeOfDay(DayNight.DUSK)`, `startDayCycle(minutes)`.
  Saved with each chapter.
- **Ambient sound**: drop an `AmbientZone` under `Ambience` (it draws its
  rectangle in the editor); `when` makes it day or night only. Positional
  sounds (a waterfall) are plain AudioStreamPlayer2D.

## NPCs

    var lehi := getCharacter("lehi") as Npc
    await walkTo(lehi, Vector2(12, 8))          # along the path, around walls and walkers
    lehi.go_to(Vector2(3, 4)).then_face("up")   # without waiting
    await lehi.pose("kneel")                    # sit, sit_lean, sit_ground, kneel, pray
    await lehi.end_pose(true)
    lehi.set_habit(Meander.new(3))
    sariah.set_habit(Station.new(Vector2(-7, 9), "up", "work"))
    sam.set_habit(Patrol.new([{"tile": Vector2(1, 4), "facing": "up", "works": Vector2i(2, 3)}, Vector2(-1, 4)]))
    sister.set_habit(Follow.new(getPlayer(), 1.5))

Walkers steer around each other and the player. A go_to() caught on someone
for half a second walks through them, so nobody can stall the story.
CharGen sheets (21 rows) cannot sit; `Station` falls back to standing.

A new person: make their sheet, put it in `characters/cast/<name>/`, and
copy any cast scene there, changing the texture. `<name>` is also their
dialogue speaker, their voice folder and their `tools/voice/cast.json` entry.

## Talking, looking, picking up

The use button goes to the nearest thing in reach (`Interaction`): a
Collectable (always first), a person with a `talk_<name>` title in
`main.dialogue`, or an Artifact with an `artifact_<id>` title. The button's
icon follows. Anything can join by being in the `interactables` group and
answering the five methods described in `core/interaction.gd`.

## Achievements

`story/achievements.gd` lists them with a rule each: a chapter, an
activity, a count (`StoryState.count("prayers")`), a set of ids recorded
(`StoryState.record("talked_to", ...)`), or reaching out to something in a
group. The five there are not tied to a story; keep or drop them.

## Voices and translations

    python3 tools/voice/build_manifest.py          # after changing lines
    python3 tools/voice/generate.py                # make missing clips (LuvVoice)
    python3 tools/i18n/update_translations.py      # bring translations/es.po up to date

Add `--locale es` to the voice tools for Spanish clips.

## Exporting

Presets for Android (`net.danimate.promisedland`, signed with the upload
key), iOS and Linux write to `../builds/`. The Android build template is
installed (`android/`, not in git; reinstall from Project > Install Android
Build Template after a Godot upgrade). Icons in `ui/app_icon/` and `icon.png`
are still Bountiful's; `../tools/make_app_icons.py` rebuilds them from new
art.
