"""Shared pieces of the voice-over tools: paths, reading the dialogue and cast,
and reading and writing the manifest.

Every tool takes --locale (default en). In English the words come straight
from main.dialogue and the .gd tables, the cast is cast.json, the manifest
manifest.csv and the clips voice/<character>/<clip>.mp3. In another language
the words are the translations in translations/<locale>.po (keyed by the same
line IDs and keys), the cast is cast_<locale>.json, the manifest
manifest_<locale>.csv and the clips voice/<locale>/<character>/<clip>.mp3,
where scripts/language.gd looks for them. A line with no translation yet is
left out and listed."""

import csv
import hashlib
import json
import re
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent.parent
DIALOGUE_FILE = PROJECT_DIR / "story" / "main.dialogue"
# Verses shown on the scripture scroll. Each key in Scriptures.TEXT is a clip,
# read by NARRATOR and saved as res://voice/narrator/<key>.mp3, which
# ui/scripture_scroll.gd looks for.
SCRIPTURES_FILE = PROJECT_DIR / "story" / "text" / "scriptures.gd"
# Words shown on the black screen between segments (Captions.TEXT), read by
# NARRATOR the same way and saved as res://voice/narrator/<key>.mp3, which
# showCaption in story/chapter.gd looks for.
CAPTIONS_FILE = PROJECT_DIR / "story" / "text" / "captions.gd"
# Quest plaque words (Quests.TEXT), read by NARRATOR when the plaque is tapped
# and saved as res://voice/narrator/<key>.mp3, which world.gd looks for.
QUESTS_FILE = PROJECT_DIR / "story" / "text" / "quests.gd"
NARRATOR = "narrator"
# What Nephi says in the tour of the controls (TourLines.TEXT), read by
# TOUR_SPEAKER and saved as res://voice/nephi/<key>.mp3, which ui/ui_tour.gd
# looks for.
TOUR_LINES_FILE = PROJECT_DIR / "story" / "text" / "tour_lines.gd"
TOUR_SPEAKER = "nephi"
TRANSLATIONS_DIR = PROJECT_DIR / "translations"


def _locale_from_argv():
    """--locale xx (or --locale=xx) on the command line. Read here, before the
    tools import the paths below, so every tool agrees on them."""
    for i, arg in enumerate(sys.argv):
        if arg == "--locale" and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
        if arg.startswith("--locale="):
            return arg.split("=", 1)[1]
    return "en"


LOCALE = _locale_from_argv()
ENGLISH = LOCALE == "en"
_SUFFIX = "" if ENGLISH else f"_{LOCALE}"
CAST_FILE = TOOLS_DIR / f"cast{_SUFFIX}.json"
MANIFEST_FILE = TOOLS_DIR / f"manifest{_SUFFIX}.csv"
# Clips land at res://voice/<character>/<clip>.mp3 in English and
# res://voice/<locale>/<character>/<clip>.mp3 otherwise (Language.voice_path).
VOICE_DIR = PROJECT_DIR / "voice" if ENGLISH else PROJECT_DIR / "voice" / LOCALE


def add_locale_argument(parser):
    parser.add_argument("--locale", default="en",
                        help="language of the clips: en (default) or one with translations/<locale>.po")


# --- Translations -------------------------------------------------------------

_translations = None
# What a translated read left out, for the tools to list.
untranslated = []


def _po_unquote(s):
    return json.loads(s.strip())


def load_translations():
    """{(msgctxt, msgid): msgstr} from translations/<LOCALE>.po, without fuzzy
    or empty entries (Godot skips those too). Plural entries are left out; no
    spoken line has one."""
    global _translations
    if _translations is not None:
        return _translations
    _translations = {}
    path = TRANSLATIONS_DIR / f"{LOCALE}.po"
    if not path.exists():
        raise SystemExit(f"No {path.relative_to(PROJECT_DIR)}; run tools/i18n/update_translations.py --lang {LOCALE}")
    cur, field, fuzzy = {}, None, False

    def finish():
        if cur.get("msgid") and cur.get("msgstr") and not fuzzy:
            _translations[(cur.get("msgctxt"), cur["msgid"])] = cur["msgstr"]

    for raw in path.read_text(encoding="utf-8").splitlines() + [""]:
        line = raw.strip()
        if not line:
            finish()
            cur, field, fuzzy = {}, None, False
        elif line.startswith("#,"):
            fuzzy = fuzzy or "fuzzy" in line
        elif line.startswith("#"):
            continue
        elif line.startswith('"'):
            if field:
                cur[field] += _po_unquote(line)
        else:
            name, _, rest = line.partition(" ")
            # msgid_plural and msgstr[n] belong to plural entries, which are skipped.
            field = name if name in ("msgctxt", "msgid", "msgstr") else None
            if field:
                cur[field] = _po_unquote(rest)
            else:
                cur["msgstr"] = ""
    return _translations


def translated(context, english, where):
    """The words in LOCALE for english under context, or None (noted in
    untranslated) when there is no translation yet. English passes through."""
    if ENGLISH:
        return english
    words = load_translations().get((context, english))
    if words is None:
        untranslated.append(f"{where} [{context}] {english[:60]}")
    return words


def variable_text(name, value):
    """The words a {{name}} = value puts into a line. Spanish gives fruitFound
    whole phrases ("Estas manzanas"), translated under that title's context."""
    if ENGLISH:
        return value
    return load_translations().get(("fruitFound" if name == "fruit" else name, value), value)

# Columns in order. tts_override and notes are typed by hand and kept across
# rebuilds; generated_hash is written by generate.py; the rest are rebuilt.
COLUMNS = ["clip", "character", "title", "text", "tts_text", "tts_override",
           "status", "hash", "generated_hash", "notes"]

# A spoken line: optional % (random pick), speaker, text, static ID.
LINE_RE = re.compile(r"^\s*(?:%\s*)?([a-z_0-9]+):\s*(.*?)\s*\[ID:([A-Za-z0-9_]+)\]\s*$")
TITLE_RE = re.compile(r"^~\s*(\S+)")
# One entry of Scriptures.TEXT: "key": "GDScript string",
SCRIPTURE_RE = re.compile(r'^\s*"([^"]+)"\s*:\s*("(?:[^"\\]|\\.)*")\s*,?\s*$')
VARIABLE_RE = re.compile(r"\{\{\s*(\w+)\s*\}\}")


# Voice settings a "voice_of" entry in cast.json takes from the speaker it names.
VOICE_KEYS = ("voice_name", "voice_id", "voice_type", "rate", "pitch", "volume", "skip")


def load_cast():
    """cast.json, with each "voice_of" speaker given the voice of the one it
    names (the artifacts speak in Nephi's voice), so a change to that voice
    carries over and marks their clips stale too."""
    with open(CAST_FILE, encoding="utf-8") as f:
        cast = json.load(f)
    characters = cast["characters"]
    for name, entry in characters.items():
        source = entry.get("voice_of")
        if not source:
            continue
        if source not in characters:
            raise SystemExit(f"cast.json: {name} has voice_of {source!r}, which is not in characters")
        for key in VOICE_KEYS:
            if key in characters[source]:
                entry[key] = characters[source][key]
    return cast


def spoken_text(text):
    """The words of a line with Dialogue Manager markup taken out. [i](...)[/i]
    is a stage direction, so it goes entirely."""
    text = re.sub(r"\[i\]\s*\(.*?\)\s*\[/i\]", "", text)
    text = re.sub(r"\[/?[a-z#][^\]]*\]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def scripture_spoken_text(text):
    """The words of a verse. The reference under it ([right]1 Nephi 17:8[/right])
    is for reading, not saying, so it goes."""
    text = re.sub(r"\[right\].*?\[/right\]", "", text, flags=re.S)
    return spoken_text(text)


def apply_pronunciations(text, pronunciations):
    for word, said in pronunciations.items():
        if word.startswith("_"):
            continue
        text = re.sub(r"\b%s\b" % re.escape(word), said, text)
    return text


def read_dialogue_lines():
    """Returns (title, character, text, id) for each spoken line with a static
    ID, text in LOCALE (lines not yet translated are left out), and the line
    numbers of spoken lines missing an ID."""
    lines, missing = [], []
    title = ""
    with open(DIALOGUE_FILE, encoding="utf-8") as f:
        for number, raw in enumerate(f, 1):
            if m := TITLE_RE.match(raw):
                title = m.group(1)
                continue
            if m := LINE_RE.match(raw):
                text = translated(m.group(3), m.group(2), f"main.dialogue:{number}")
                if text is not None:
                    lines.append((title, m.group(1), text, m.group(3)))
            elif re.match(r"^\s*(?:%\s*)?[a-z_0-9]+:\s+\S", raw):
                missing.append(number)
    return lines, missing


def read_scriptures(path=SCRIPTURES_FILE):
    """Returns (key, text) for each entry in the TEXT dictionary of path
    (Scriptures.TEXT unless given Captions'), text unescaped, and the line
    numbers of entries it couldn't read (one not on one line)."""
    verses, unread = [], []
    with open(path, encoding="utf-8") as f:
        for number, raw in enumerate(f, 1):
            if m := SCRIPTURE_RE.match(raw):
                # GDScript's \n and \" escapes read the same as JSON's.
                text = translated(m.group(1), json.loads(m.group(2)), f"{path.name}:{number}")
                if text is not None:
                    verses.append((m.group(1), text))
            # A list ("key": [...]) is Quests.COUNTED, shown, not read aloud.
            elif re.match(r'^\s*"[^"]+"\s*:(?!\s*\[)', raw):
                unread.append(number)
    return verses, unread


def voice_settings(character_cast):
    return {k: character_cast.get(k) for k in ("voice_id", "voice_type", "rate", "pitch", "volume")}


def clip_hash(tts_text, character_cast):
    """Changes whenever the words sent or the voice settings change, so a clip
    made from older ones shows up as stale."""
    blob = json.dumps([tts_text, voice_settings(character_cast)], sort_keys=True)
    return hashlib.sha1(blob.encode("utf-8")).hexdigest()[:12]


def clip_path(character, clip):
    return VOICE_DIR / character / f"{clip}.mp3"


def text_to_send(row):
    return row["tts_override"].strip() or row["tts_text"]


def read_manifest():
    if not MANIFEST_FILE.exists():
        return []
    with open(MANIFEST_FILE, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write_manifest(rows):
    with open(MANIFEST_FILE, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def refresh_status(row, cast):
    """Works out status and hash from the row's text, its speaker's cast entry
    and whether the clip is on disk."""
    character_cast = cast["characters"].get(row["character"], {})
    row["hash"] = clip_hash(text_to_send(row), character_cast)
    if character_cast.get("skip"):
        row["status"] = "skip"
    elif not character_cast.get("voice_id"):
        row["status"] = "no voice"
    elif not clip_path(row["character"], row["clip"]).exists():
        row["status"] = "missing"
    elif row.get("generated_hash") != row["hash"]:
        row["status"] = "stale"
    else:
        row["status"] = "done"
