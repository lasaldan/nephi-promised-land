#!/usr/bin/env python3
"""Rebuilds tools/voice/manifest.csv from story/main.dialogue, story/scriptures.gd,
story/captions.gd, story/quests.gd, ui/tour_lines.gd and cast.json.

One row per clip: each spoken line with an [ID:...], once per speaker, and once
per value for lines using a {{variable}}; then each verse in Scriptures.TEXT,
each caption in Captions.TEXT and each quest in Quests.TEXT, read by the
narrator and named by its key; then each line of the controls tour in
TourLines.TEXT, read by Nephi and named by its key. tts_override and notes
typed into the manifest are kept. Run it after editing the dialogue, the
verses, the captions, the quests, the tour or the cast:

    python3 tools/voice/build_manifest.py
    python3 tools/voice/build_manifest.py --locale es   # manifest_es.csv, from translations/es.po

In another language the words are the translations (voice_common), and lines
not translated yet are listed and left out until they are.
"""

import argparse
from collections import Counter

import voice_common
from voice_common import (CAPTIONS_FILE, MANIFEST_FILE, add_locale_argument, variable_text, NARRATOR, QUESTS_FILE, TOUR_LINES_FILE, TOUR_SPEAKER,
                          VARIABLE_RE, apply_pronunciations,
                          load_cast, read_dialogue_lines, read_manifest, read_scriptures,
                          refresh_status, scripture_spoken_text, spoken_text,
                          write_manifest)

# The title column for verse rows, which have no dialogue title.
SCRIPTURE_TITLE = "scripture"
# And for caption rows.
CAPTION_TITLE = "caption"
# And for quest rows.
QUEST_TITLE = "quest"
# And for the controls tour's rows.
TOUR_TITLE = "ui_tour"


def make_row(clip, character, title, spoken, old, cast):
    """A manifest row, keeping what was typed into the old one by hand."""
    previous = old.get((character, clip), {})
    row = {
        "clip": clip,
        "character": character,
        "title": title,
        "text": spoken,
        "tts_text": apply_pronunciations(spoken, cast.get("pronunciations", {})),
        "tts_override": previous.get("tts_override", ""),
        "generated_hash": previous.get("generated_hash", ""),
        "notes": previous.get("notes", ""),
    }
    refresh_status(row, cast)
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_locale_argument(parser)
    parser.parse_args()
    cast = load_cast()
    variables = cast.get("variables", {})
    old = {(r["character"], r["clip"]): r for r in read_manifest()}

    lines, missing = read_dialogue_lines()
    rows, seen, problems = [], set(), []
    for title, character, text, line_id in lines:
        if character not in cast["characters"]:
            problems.append(f"{character} ({line_id}) has no entry in cast.json")

        # Expand {{variable}} lines into one clip per value.
        names = VARIABLE_RE.findall(text)
        variants = [("", text)]
        for name in names:
            values = variables.get(name)
            if not values:
                problems.append(f"{line_id} uses {{{{{name}}}}}, which has no values in cast.json variables")
                continue
            variants = [(f"{suffix}__{value}",
                         VARIABLE_RE.sub(lambda m: variable_text(name, value) if m.group(1) == name else m.group(0), t))
                        for suffix, t in variants for value in values]

        for suffix, variant_text in variants:
            clip = line_id + suffix
            # The same words get the same ID, so a repeated line shares a clip.
            if (character, clip) in seen:
                continue
            seen.add((character, clip))
            rows.append(make_row(clip, character, title, spoken_text(variant_text), old, cast))

    if NARRATOR not in cast["characters"]:
        problems.append(f"{NARRATOR} (the scripture verses) has no entry in cast.json")
    verses, unread_verses = read_scriptures()
    for key, text in verses:
        seen.add((NARRATOR, key))
        rows.append(make_row(key, NARRATOR, SCRIPTURE_TITLE, scripture_spoken_text(text), old, cast))
    captions, unread_captions = read_scriptures(CAPTIONS_FILE)
    for key, text in captions:
        if (NARRATOR, key) in seen:
            problems.append(f"caption {key} has the same key as a verse; rename one")
            continue
        seen.add((NARRATOR, key))
        rows.append(make_row(key, NARRATOR, CAPTION_TITLE, spoken_text(text), old, cast))
    quests, unread_quests = read_scriptures(QUESTS_FILE)
    for key, text in quests:
        if (NARRATOR, key) in seen:
            problems.append(f"quest {key} has the same key as a verse or caption; rename one")
            continue
        seen.add((NARRATOR, key))
        rows.append(make_row(key, NARRATOR, QUEST_TITLE, spoken_text(text), old, cast))

    tour_lines, unread_tour = read_scriptures(TOUR_LINES_FILE)
    for key, text in tour_lines:
        if (TOUR_SPEAKER, key) in seen:
            problems.append(f"tour line {key} has the same key as one of {TOUR_SPEAKER}'s lines; rename it")
            continue
        seen.add((TOUR_SPEAKER, key))
        rows.append(make_row(key, TOUR_SPEAKER, TOUR_TITLE, spoken_text(text), old, cast))

    write_manifest(rows)

    dropped = set(old) - seen
    counts = Counter(r["status"] for r in rows)
    print(f"Wrote {len(rows)} clips to {MANIFEST_FILE}")
    print("  " + ", ".join(f"{n} {s}" for s, n in sorted(counts.items())))
    if dropped:
        print(f"  {len(dropped)} clips no longer in the dialogue (their mp3s can be deleted):")
        for character, clip in sorted(dropped):
            print(f"    voice/{character}/{clip}.mp3")
    for line in missing:
        print(f"  warning: main.dialogue:{line} is spoken but has no [ID:...]; regenerate line IDs")
    for line in unread_verses:
        print(f"  warning: scriptures.gd:{line} couldn't be read; keep each verse on one line")
    for line in unread_captions:
        print(f"  warning: captions.gd:{line} couldn't be read; keep each caption on one line")
    for line in unread_quests:
        print(f"  warning: quests.gd:{line} couldn't be read; keep each quest on one line")
    for line in unread_tour:
        print(f"  warning: tour_lines.gd:{line} couldn't be read; keep each line on one line")
    for p in problems:
        print(f"  warning: {p}")
    if voice_common.untranslated:
        print(f"  {len(voice_common.untranslated)} lines have no {voice_common.LOCALE} translation yet, so no clip:")
        for line in voice_common.untranslated:
            print(f"    {line}")


if __name__ == "__main__":
    main()
