#!/usr/bin/env python3
"""Builds menus/credits_lpc.gd, the LPC sprite credits for the full credits
(Credits on the main menu), from the *_credits.txt files the Universal LPC
Spritesheet Character Generator writes next to each character sheet.

Each part (a body, a shirt, a hairstyle) is listed once, with every author,
license and link any character's sheet gives for it.

Run from anywhere after adding or changing a character:
    python3 tools/build_lpc_credits.py
"""

import glob
import os
import re

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = [
    os.path.join(PROJECT, "characters", "cast", "*", "*_credits.txt"),
    # Jacob's and Joseph's, kept beside the generator's .char files.
    os.path.join(os.path.dirname(PROJECT), "*_credits.txt"),
]
OUTPUT = os.path.join(PROJECT, "menus", "credits_lpc.gd")

FIELDS = {"Author(s)": "authors", "License(s)": "licenses", "Url(s)": "urls"}


def parse(path, parts):
    part = None
    field = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            header = re.match(r"^\* (.+)$", line)
            if header:
                part = parts.setdefault(header.group(1).strip(), {"authors": [], "licenses": [], "urls": []})
                field = None
                continue
            if part is None:
                continue
            labelled = re.match(r"^\s+(Author\(s\)|License\(s\)|Url\(s\))\s*:\s*(.*)$", line)
            if labelled:
                field = FIELDS[labelled.group(1)]
                value = labelled.group(2).strip()
            elif field and re.match(r"^\s{10,}\S", line):
                # A further value, lined up under the first.
                value = line.strip()
            else:
                field = None
                continue
            if value and value not in part[field]:
                part[field].append(value)


def bbcode(text):
    return text.replace("[", "[lb]")


def main():
    parts = {}
    files = sorted(p for pattern in SOURCES for p in glob.glob(pattern))
    for path in files:
        parse(path, parts)
    sections = []
    for name in sorted(parts, key=str.lower):
        part = parts[name]
        lines = ["[b]%s[/b]" % bbcode(name), bbcode(", ".join(part["authors"]))]
        if part["licenses"]:
            lines.append(bbcode(" / ".join(part["licenses"])))
        lines.extend(bbcode(url) for url in part["urls"])
        sections.append("\n".join(lines))
    text = "\n\n".join(sections)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write("# Made by tools/build_lpc_credits.py from the characters' *_credits.txt.\n")
        f.write("# Run that again rather than editing this.\n\n")
        f.write("const TEXT := %s\n" % gdscript_string(text))
    print("%d parts from %d files -> %s" % (len(parts), len(files), os.path.relpath(OUTPUT, PROJECT)))


def gdscript_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


if __name__ == "__main__":
    main()
