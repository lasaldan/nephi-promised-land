#!/usr/bin/env python3
"""Builds the Google Play feature graphic (1024x500, no transparency): the
game illustration with the logo over the sky on the left, the menu's
"NEPHI BUILDS A SHIP" subtitle between rules under it, and the tagline below.

The logo comes from make_menu_title.render_word(). Writes feature_graphic.png
in the folder above the repo, next to the other store art.

Run from anywhere:
    python3 tools/make_feature_graphic.py
"""

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from make_menu_title import CREAM, DARK, render_word

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ART = os.path.join(ROOT, "..", "website", "images", "bountiful.jpg")
BOLD = os.path.join(ROOT, "ui", "fonts", "OverlockBold.ttf")
OUT = os.path.join(ROOT, "..", "feature_graphic.png")

SIZE = (1024, 500)
# How far down the illustration the graphic starts, in its pixels at 1024 wide.
ART_TOP = 42
# The logo block's centre line and top.
CENTRE_X = 262
LOGO_TOP = 34
LOGO_WIDTH = 400

SUBTITLE = "NEPHI BUILDS A SHIP"
SUBTITLE_SIZE = 24
SUBTITLE_TRACKING = 5
RULE = (56, 4)
TAGLINE = ["An Interactive Story from", "The Book of Mormon"]
TAGLINE_SIZE = 30
TAGLINE_LEADING = 36


def tracked_width(font: ImageFont.FreeTypeFont, text: str, tracking: float) -> float:
    return sum(font.getlength(ch) for ch in text) + tracking * (len(text) - 1)


def draw_tracked(draw: ImageDraw.ImageDraw, xy: tuple[float, float], text: str,
        font: ImageFont.FreeTypeFont, tracking: float, **kwargs) -> None:
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, **kwargs)
        x += font.getlength(ch) + tracking


def main() -> None:
    art = Image.open(ART).convert("RGB")
    art = art.resize((SIZE[0], round(art.height * SIZE[0] / art.width)), Image.LANCZOS)
    out = art.crop((0, ART_TOP, SIZE[0], ART_TOP + SIZE[1])).convert("RGBA")

    probe, _ = render_word()
    word, _ = render_word(LOGO_WIDTH / probe.width)
    out.alpha_composite(word, (round(CENTRE_X - word.width / 2), LOGO_TOP))

    # Subtitle: cream capitals ringed in dark brown, a rule either side.
    sub_font = ImageFont.truetype(BOLD, SUBTITLE_SIZE)
    sub_w = tracked_width(sub_font, SUBTITLE, SUBTITLE_TRACKING)
    sub_y = LOGO_TOP + word.height + 2
    gap = 14
    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    sub_x = CENTRE_X - sub_w / 2
    draw_tracked(draw, (sub_x, sub_y + 2), SUBTITLE, sub_font, SUBTITLE_TRACKING,
            fill=DARK, stroke_width=2, stroke_fill=DARK)
    draw_tracked(draw, (sub_x, sub_y), SUBTITLE, sub_font, SUBTITLE_TRACKING,
            fill=(255, 248, 230), stroke_width=2, stroke_fill=DARK)
    _, top, _, bottom = sub_font.getbbox("N")
    rule_y = sub_y + (top + bottom) / 2 - RULE[1] / 2
    for left in (sub_x - gap - RULE[0], sub_x + sub_w + gap):
        draw.rectangle((left - 1.5, rule_y - 1.5, left + RULE[0] + 1.5, rule_y + RULE[1] + 1.5),
                fill=DARK)
        draw.rectangle((left, rule_y, left + RULE[0], rule_y + RULE[1]), fill=CREAM)
    out.alpha_composite(layer)

    # Tagline: white over a soft dark shadow, as before.
    tag_font = ImageFont.truetype(BOLD, TAGLINE_SIZE)
    tag_top = sub_y + bottom + 18
    shadow = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    text = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    text_draw = ImageDraw.Draw(text)
    for i, line in enumerate(TAGLINE):
        x = CENTRE_X - tag_font.getlength(line) / 2
        y = tag_top + TAGLINE_LEADING * i
        shadow_draw.text((x, y + 2), line, font=tag_font, fill=DARK + (230,),
                stroke_width=3, stroke_fill=DARK + (230,))
        text_draw.text((x, y), line, font=tag_font, fill=(255, 255, 255))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(3)))
    out.alpha_composite(text)

    out.convert("RGB").save(OUT)
    print(f"wrote {OUT} {out.size}")


if __name__ == "__main__":
    main()
