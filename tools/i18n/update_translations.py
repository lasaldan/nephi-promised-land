#!/usr/bin/env python3
"""Gathers every string the player sees and brings translations/<lang>.po up
to date with it, keeping the translations already there.

    python3 tools/i18n/update_translations.py            # translations/es.po
    python3 tools/i18n/update_translations.py --check    # report, write nothing

Run it after changing any English the player sees: story/main.dialogue, the
text tables (quests, scriptures, captions, tour lines, achievements,
artifacts, credits), or a scene label. Then fill in the empty
msgstr lines, and fix the ones marked "#, fuzzy" (their English changed; the
old translation is kept under them as a starting point). Godot skips fuzzy
and empty entries, so those show in English until they are done.

Where each string comes from, and the msgctxt it is translated under:

  main.dialogue lines        the line's [ID:...]      (Dialogue Manager looks
                                                       them up that way)
  speaker names              "dialogue"               (characters/cast.gd)
  Quests/Scriptures/Captions/TourLines .TEXT   the key (Language.t(text, key))
  Quests.COUNTED             the key, with a plural form
  achievements               "achievement"
  artifacts                  "artifact"
  credits sections           "credits"
  tr("...") / tr("...", "ctx") and Language.t("...", "ctx") in any .gd
  scene text and tooltips    no context               (Controls translate
                                                       themselves)
  UI_STRINGS below           no context               (labels set from code,
                                                       which translate themselves)

Entries no longer found are dropped, and listed so a translation can be
rescued by hand if a key was only renamed.
"""

import argparse
import json
import re
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent.parent
TRANSLATIONS_DIR = PROJECT_DIR / "translations"

PLURAL_FORMS = {"es": "nplurals=2; plural=(n != 1);"}

# English assigned in code to a Label or Button, which translates its own text
# (auto-translate), so there's no tr() to find. Keep in step with the code.
UI_STRINGS = [
    ("Paused", "ui/pause_menu.gd"),
    ("Settings", "ui/pause_menu.gd"),
    ("Resume", "ui/pause_menu.gd"),
    ("Done", "ui/pause_menu.gd"),
    ("New Game", "ui/save_slot.gd"),
    ("Achievement", "ui/achievement_toast.gd"),
    ("Keep playing to discover this one.", "ui/achievement_list.gd"),
    ("Skip", "ui/ui_tour.gd"),
]

# Scene text that is never words to translate.
SCENE_TEXT_SKIP = re.compile(r"^[\d\s:/.%-]*$|^Danimate$|^Character$|^Dialogue\.\.\.$|^Response example$"
                             r"|^Erase save 1\?$|^And I beheld the Sea and saw that it was good\.$")

# The same names as Cast.DISPLAY_NAMES (characters/cast.gd); anyone else is shown capitalized.
BALLOON_FILE = PROJECT_DIR / "characters" / "cast.gd"

DIALOGUE_FILE = PROJECT_DIR / "story" / "main.dialogue"
LINE_RE = re.compile(r"^\s*(?:%\s*)?(?:([a-z_0-9]+):\s*)?(.*?)\s*\[ID:([A-Za-z0-9_]+)\]\s*$")
GD_STRING = r'"(?:[^"\\]|\\.)*"'
TABLE_ENTRY_RE = re.compile(r'^\s*"([^"]+)"\s*:\s*(' + GD_STRING + r')\s*,?\s*$')
COUNTED_RE = re.compile(r'^\s*"([^"]+)"\s*:\s*\[(' + GD_STRING + r')\s*,\s*(' + GD_STRING + r')\]\s*,?\s*$')
TR_RE = re.compile(r'\b(?:tr|Language\.t)\((' + GD_STRING + r')(?:\s*,\s*(' + GD_STRING + r'))?\s*\)')
SCENE_TEXT_RE = re.compile(r'^(?:text|tooltip_text) = (' + GD_STRING + r')\s*$')


def gd_string(literal):
    """A GDScript "..." literal's value. Its escapes read the same as JSON's."""
    return json.loads(literal)


class Entry:
    def __init__(self, ctx, msgid, ref, plural=None, comment=None):
        self.ctx, self.msgid, self.plural = ctx, msgid, plural
        self.refs = [ref]
        self.comments = [comment] if comment else []
        self.msgstr = [""] * (2 if plural else 1)
        self.fuzzy = False
        self.previous = None

    @property
    def key(self):
        return (self.ctx, self.msgid)


class Catalog:
    def __init__(self):
        self.entries = {}

    def add(self, ctx, msgid, ref, plural=None, comment=None):
        if not msgid:
            return
        key = (ctx, msgid)
        if key in self.entries:
            if ref not in self.entries[key].refs:
                self.entries[key].refs.append(ref)
            return
        self.entries[key] = Entry(ctx, msgid, ref, plural, comment)


def rel(path):
    return str(Path(path).relative_to(PROJECT_DIR))


def gather_dialogue(cat):
    title = ""
    speakers = []
    for number, raw in enumerate(DIALOGUE_FILE.read_text(encoding="utf-8").splitlines(), 1):
        if raw.startswith("~ "):
            title = raw[2:].strip()
            continue
        if raw.lstrip().startswith("#"):
            continue
        m = LINE_RE.match(raw)
        if not m:
            continue
        speaker, text, line_id = m.groups()
        comment = f"{speaker or '(no speaker)'} in ~ {title}"
        cat.add(line_id, text.strip(), f"story/main.dialogue:{number}", comment=comment)
        if speaker and speaker not in speakers:
            speakers.append(speaker)
    return speakers


def gather_speaker_names(cat, speakers):
    src = BALLOON_FILE.read_text(encoding="utf-8")
    block = re.search(r"const DISPLAY_NAMES := \{(.*?)\n\}", src, re.S).group(1)
    names = {k: gd_string(v) for k, v in re.findall(r'"([^"]+)":\s*(' + GD_STRING + ')', block)}
    artifacts = set(re.findall(r'^\t"([a-z_]+)": \{', (PROJECT_DIR / "story/artifacts.gd").read_text(), re.M))
    for speaker in speakers:
        if speaker in artifacts:
            continue  # shown by Artifacts.display_name
        # Godot's String.capitalize(): "lehi" -> "Lehi", "sister_1" -> "Sister 1".
        name = names.get(speaker) or " ".join(w.capitalize() for w in speaker.split("_"))
        cat.add("dialogue", name, "characters/cast.gd", comment=f"the name over {speaker}'s lines")


def gather_table(cat, path, comment=None):
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if m := TABLE_ENTRY_RE.match(raw):
            cat.add(m.group(1), gd_string(m.group(2)), f"{rel(path)}:{number}", comment=comment)


def gather_counted(cat, path):
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if m := COUNTED_RE.match(raw):
            cat.add(m.group(1), gd_string(m.group(2)), f"{rel(path)}:{number}",
                    plural=gd_string(m.group(3)), comment="%d is how many are left")


def gather_achievements(cat):
    path = PROJECT_DIR / "story" / "achievements.gd"
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        m = re.match(r'^\s*"([a-z_]+)": \{"name": (' + GD_STRING + r'), "description": (' + GD_STRING + ')', raw)
        if m:
            ref = f"{rel(path)}:{number}"
            cat.add("achievement", gd_string(m.group(2)), ref, comment=f"name of {m.group(1)}")
            cat.add("achievement", gd_string(m.group(3)), ref, comment=f"description of {m.group(1)}")


def gather_artifacts(cat):
    path = PROJECT_DIR / "story" / "artifacts.gd"
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if m := re.match(r'^\s*"name": (' + GD_STRING + ')', raw):
            cat.add("artifact", gd_string(m.group(1)), f"{rel(path)}:{number}")


def gd_literals(text):
    """Every string literal in a stretch of GDScript, triple-quoted ones too."""
    out = []
    for m in re.finditer(r'"""(.*?)"""|(' + GD_STRING + ')', text, re.S):
        out.append(m.group(1) if m.group(1) is not None else gd_string(m.group(2)))
    return out


def gather_credits(cat):
    path = PROJECT_DIR / "menus" / "credits.gd"
    src = path.read_text(encoding="utf-8")
    for name in ("LPC_SHORT", "LPC_FULL_TITLE", "CLOSING", "TO_BE_CONTINUED"):
        m = re.search(r"^const %s := (\"\"\".*?\"\"\"|%s)" % (name, GD_STRING), src, re.M | re.S)
        if m:
            value = gd_literals(m.group(1))[0]
            # The closing card is a Label, which translates itself without a context.
            cat.add(None if name == "CLOSING" else "credits", value, rel(path))
    block = re.search(r"^const CREDITS := \[(.*?)^\]", src, re.M | re.S).group(1)
    # Strings inside {"cast": ...} rows are names, not words.
    block = re.sub(r"\{[^{}]*\}", "", block)
    for value in gd_literals(block):
        cat.add("credits", value, rel(path))


def gather_code(cat):
    for path in sorted(PROJECT_DIR.rglob("*.gd")):
        if any(part in ("addons", ".godot", "tools") for part in path.relative_to(PROJECT_DIR).parts):
            continue
        for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if raw.lstrip().startswith("#"):
                continue
            for m in TR_RE.finditer(raw):
                ctx = gd_string(m.group(2)) if m.group(2) else None
                cat.add(ctx, gd_string(m.group(1)), f"{rel(path)}:{number}")


def gather_scenes(cat):
    for path in sorted(PROJECT_DIR.rglob("*.tscn")):
        if any(part in ("addons", ".godot", "android") for part in path.relative_to(PROJECT_DIR).parts):
            continue
        for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if m := SCENE_TEXT_RE.match(raw):
                value = gd_string(m.group(1))
                if not SCENE_TEXT_SKIP.match(value):
                    cat.add(None, value, f"{rel(path)}:{number}")


def gather():
    cat = Catalog()
    speakers = gather_dialogue(cat)
    gather_speaker_names(cat, speakers)
    gather_table(cat, PROJECT_DIR / "story" / "text" / "quests.gd", "quest plaque")
    gather_counted(cat, PROJECT_DIR / "story" / "text" / "quests.gd")
    gather_table(cat, PROJECT_DIR / "story" / "text" / "scriptures.gd",
                 "verse: use the official translation of the Book of Mormon; [right][i]...[/i][/right] is the reference")
    gather_table(cat, PROJECT_DIR / "story" / "text" / "captions.gd", "caption on black")
    gather_table(cat, PROJECT_DIR / "story" / "text" / "tour_lines.gd", "Nephi in the controls tour")
    gather_achievements(cat)
    gather_artifacts(cat)
    gather_credits(cat)
    gather_code(cat)
    gather_scenes(cat)
    for text, ref in UI_STRINGS:
        cat.add(None, text, ref)
    # Language.join_list() puts lists together with these.
    for text in ("%s and %s", "%s, and %s", ", "):
        cat.add("list", text, "scripts/language.gd", comment="joining a list: \"hammer, saw, and nails\"")
    return cat


# --- PO reading and writing -------------------------------------------------

def po_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


def po_unquote(s):
    s = s.strip()
    assert s.startswith('"') and s.endswith('"'), s
    return json.loads(s)


def read_po(path):
    """Returns {(ctx, msgid): {"msgstr": [...], "fuzzy": bool, "plural": str|None}}."""
    entries = {}
    if not path.exists():
        return entries
    cur, field, flags = {}, None, []

    def finish():
        if "msgid" in cur and cur["msgid"] != "":
            strs = [cur.get(f"msgstr[{i}]", "") for i in range(2)] if "msgid_plural" in cur else [cur.get("msgstr", "")]
            entries[(cur.get("msgctxt"), cur["msgid"])] = {
                "msgstr": strs, "fuzzy": "fuzzy" in flags, "plural": cur.get("msgid_plural")}

    for raw in path.read_text(encoding="utf-8").splitlines() + [""]:
        line = raw.strip()
        if not line:
            finish()
            cur, field, flags = {}, None, []
        elif line.startswith("#,"):
            flags += [f.strip() for f in line[2:].split(",")]
        elif line.startswith("#"):
            continue
        elif line.startswith('"'):
            cur[field] += po_unquote(line)
        else:
            field, _, rest = line.partition(" ")
            cur[field] = po_unquote(rest)
    return entries


def write_po(path, lang, entries):
    out = ['msgid ""', 'msgstr ""',
           po_quote("Content-Type: text/plain; charset=UTF-8\n"),
           po_quote(f"Language: {lang}\n"),
           po_quote(f"Plural-Forms: {PLURAL_FORMS.get(lang, 'nplurals=2; plural=(n != 1);')}\n"),
           ""]
    for e in entries:
        for c in e.comments:
            out.append(f"#. {c}")
        out.append("#: " + " ".join(e.refs[:4]))
        if e.fuzzy:
            out.append("#, fuzzy")
        if e.previous is not None:
            out.append("#| msgid " + po_quote(e.previous))
        if e.ctx is not None:
            out.append("msgctxt " + po_quote(e.ctx))
        out.append("msgid " + po_quote(e.msgid))
        if e.plural:
            out.append("msgid_plural " + po_quote(e.plural))
            for i, s in enumerate(e.msgstr):
                out.append(f"msgstr[{i}] " + po_quote(s))
        else:
            out.append("msgstr " + po_quote(e.msgstr[0]))
        out.append("")
    path.write_text("\n".join(out), encoding="utf-8")


def merge(cat, old):
    """Carries translations over. A context whose English changed keeps its old
    translation, marked fuzzy. Returns the keys of old entries dropped."""
    by_ctx = {}
    for (ctx, msgid), v in old.items():
        if ctx is not None:
            by_ctx.setdefault(ctx, []).append((msgid, v))
    used = set()
    for e in cat.entries.values():
        if e.key in old:
            v = old[e.key]
            used.add(e.key)
        elif e.ctx is not None and len(by_ctx.get(e.ctx, [])) == 1 and e.ctx not in (
                "dialogue", "achievement", "artifact", "recipe", "material", "credits", "fruitFound", "list", "forge"):
            # Only for one-per-key contexts (a line ID, a quest key).
            msgid, v = by_ctx[e.ctx][0]
            used.add((e.ctx, msgid))
            e.previous = msgid
            v = dict(v, fuzzy=True)
        else:
            continue
        strs = (v["msgstr"] + [""])[:len(e.msgstr)] if e.plural else v["msgstr"][:1]
        e.msgstr = strs + [""] * (len(e.msgstr) - len(strs))
        e.fuzzy = v["fuzzy"] or (e.previous is not None and any(strs))
    return [k for k in old if k not in used]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lang", default="es")
    parser.add_argument("--check", action="store_true", help="report only; write nothing")
    args = parser.parse_args()

    path = TRANSLATIONS_DIR / f"{args.lang}.po"
    cat = gather()
    old = read_po(path)
    dropped = merge(cat, old)
    entries = list(cat.entries.values())

    done = sum(1 for e in entries if all(e.msgstr) and not e.fuzzy)
    fuzzy = sum(1 for e in entries if e.fuzzy)
    print(f"{len(entries)} strings: {done} translated, {fuzzy} fuzzy, {len(entries) - done - fuzzy} untranslated")
    for ctx, msgid in dropped:
        print(f"  dropped (no longer used): [{ctx}] {msgid[:70]!r}")
    if args.check:
        return 0 if done == len(entries) else 1
    TRANSLATIONS_DIR.mkdir(exist_ok=True)
    write_po(path, args.lang, entries)
    print(f"Wrote {rel(path)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
