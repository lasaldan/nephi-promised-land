#!/usr/bin/env python3
"""Builds the game logo (TEXT): Lilita One in a timber gradient, ringed in
cream and then dark brown, with the dark ring dropped below as a shadow.

Writes ui/menu_title.png, the whole word, and ui/menu_title_letters/<i>.png,
one per letter, for the main menu; and ui/title.png, the intro cutscene's
title, the word centred in TITLE_BOX on a TITLE_SIZE canvas where the old
title's word sat, with the tagline in white below it. tools/make_feature_graphic.py draws it too, through
render_word().

Each letter file is the whole word's size, clear except for that letter's
columns, so the menu can stack them in one rect and drop each letter in on
its own (main_menu.gd), then swap to the whole word once they land so the
cuts between letters never show at rest.

Drawn at RES times the game's pixels; the menu shows it at 1/RES.

Run from anywhere after changing anything here:
    python3 tools/make_menu_title.py
"""

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FONT = os.path.join(ROOT, "tools", "fonts", "LilitaOne-Regular.ttf")
OUT = os.path.join(ROOT, "ui", "menu_title.png")
LETTERS_DIR = os.path.join(ROOT, "ui", "menu_title_letters")
TITLE_OUT = os.path.join(ROOT, "ui", "title.png")
TITLE_SIZE = (640, 320)
# Left, top, right, bottom.
TITLE_BOX = (60, 32, 580, 152)
TAGLINE_FONT = os.path.join(ROOT, "ui", "fonts", "OverlockBold.ttf")
TAGLINE = ["An Interactive Story from", "The Book of Mormon"]
TAGLINE_SIZE = 36
TAGLINE_TOP = 162
TAGLINE_LEADING = 40

TEXT = "The Promised Land"
RES = 3
FONT_SIZE = 35 * RES
# Extra space between letters, in drawn pixels at the menu's size.
TRACKING = 3
# Ring widths and the shadow's drop, in drawn pixels at the menu's size.
CREAM_RING = 4
DARK_RING = 4
SHADOW_DROP = 7

CREAM = (255, 243, 214)
DARK = (59, 34, 15)
# Top to bottom over the letters' height: (position, colour).
GRADIENT = [
    (0.00, (246, 217, 164)),
    (0.45, (226, 166, 94)),
    (0.55, (184, 110, 51)),
    (1.00, (138, 77, 34)),
]


def dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    """Grows mask by a round brush of radius, keeping its soft edges."""
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx * dx + dy * dy > radius * radius:
                continue
            shifted = np.zeros_like(mask)
            shifted[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = \
                mask[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
            np.maximum(out, shifted, out=out)
    return out


def drop(mask: np.ndarray, distance: int) -> np.ndarray:
    """mask with copies of itself smeared straight down by up to distance."""
    out = mask.copy()
    for dy in range(1, distance + 1):
        np.maximum(out[dy:], mask[:-dy], out=out[dy:])
    return out


def gradient_column(height: int, top: int, bottom: int) -> np.ndarray:
    ys = np.clip((np.arange(height) - top) / max(bottom - top, 1), 0.0, 1.0)
    stops = np.array([s for s, _ in GRADIENT])
    colours = np.array([c for _, c in GRADIENT], dtype=float)
    return np.stack([np.interp(ys, stops, colours[:, ch]) for ch in range(3)], axis=1)


def render_word(scale: float = 1.0) -> tuple[Image.Image, list[int]]:
    """The word at scale times the menu's size, cropped, and the columns
    cutting it between letters (its left edge first, its right edge last)."""
    font = ImageFont.truetype(FONT, round(FONT_SIZE * scale))
    tracking = TRACKING * scale
    cream_ring = round(CREAM_RING * scale)
    dark_ring = round(DARK_RING * scale)
    shadow_drop = round(SHADOW_DROP * scale)
    pad = cream_ring + dark_ring + shadow_drop + 4
    # Each letter's pen position, so the cuts between letters can be placed.
    xs = []
    x = 0.0
    for ch in TEXT:
        xs.append(x)
        x += font.getlength(ch) + tracking
    width = int(x) + pad * 2
    ascent, descent = font.getmetrics()
    height = ascent + descent + pad * 2

    text_img = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(text_img)
    inks = []
    for ch, cx in zip(TEXT, xs):
        draw.text((pad + cx, pad), ch, font=font, fill=255)
        left, top, right, bottom = font.getbbox(ch)
        inks.append((pad + cx + left, pad + cx + right, pad + top, pad + bottom))

    fill = np.asarray(text_img, dtype=np.uint8)
    cream = dilate(fill, cream_ring)
    dark = drop(dilate(cream, dark_ring), shadow_drop)

    ink_top = int(min(i[2] for i in inks))
    ink_bottom = int(max(i[3] for i in inks))
    rgb = np.empty((height, width, 3), dtype=float)
    rgb[:] = np.array(DARK, dtype=float)
    a_cream = cream / 255.0
    a_fill = fill / 255.0
    rgb = rgb * (1 - a_cream[..., None]) + np.array(CREAM) * a_cream[..., None]
    grad = gradient_column(height, ink_top, ink_bottom)[:, None, :]
    rgb = rgb * (1 - a_fill[..., None]) + grad * a_fill[..., None]
    rgba = np.dstack([rgb, dark.astype(float)]).round().astype(np.uint8)

    word = Image.fromarray(rgba, "RGBA")
    box = word.getbbox()
    word = word.crop(box)
    # Cut halfway between one letter's ink and the next's.
    cuts = [0]
    for (_, right, _, _), (left, _, _, _) in zip(inks, inks[1:]):
        cuts.append(round((right + left) / 2) - box[0])
    cuts.append(word.width)
    return word, cuts


def main() -> None:
    word, cuts = render_word()
    word.save(OUT)
    print(f"wrote {OUT} {word.size}, shown at {word.width / RES:.1f}x{word.height / RES:.1f}")

    os.makedirs(LETTERS_DIR, exist_ok=True)
    pixels = np.asarray(word)
    for i in range(len(TEXT)):
        letter = np.zeros_like(pixels)
        letter[:, cuts[i]:cuts[i + 1]] = pixels[:, cuts[i]:cuts[i + 1]]
        path = os.path.join(LETTERS_DIR, f"{i}.png")
        Image.fromarray(letter, "RGBA").save(path)
    print(f"wrote {len(TEXT)} letters to {LETTERS_DIR}")

    # Drawn at the size that fills the box, rather than resized into it.
    box_w = TITLE_BOX[2] - TITLE_BOX[0]
    box_h = TITLE_BOX[3] - TITLE_BOX[1]
    title, _ = render_word(min(box_w / word.width, box_h / word.height))
    canvas = Image.new("RGBA", TITLE_SIZE, (0, 0, 0, 0))
    canvas.paste(title, (TITLE_BOX[0] + (box_w - title.width) // 2,
            TITLE_BOX[1] + (box_h - title.height) // 2))
    tag_font = ImageFont.truetype(TAGLINE_FONT, TAGLINE_SIZE)
    draw = ImageDraw.Draw(canvas)
    for i, line in enumerate(TAGLINE):
        x = (TITLE_SIZE[0] - tag_font.getlength(line)) / 2
        draw.text((x, TAGLINE_TOP + TAGLINE_LEADING * i), line, font=tag_font,
                fill=(255, 255, 255, 255))
    canvas.save(TITLE_OUT)
    print(f"wrote {TITLE_OUT} {canvas.size}, word {title.size}")


if __name__ == "__main__":
    main()
