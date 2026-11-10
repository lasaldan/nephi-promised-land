#!/usr/bin/env python3
"""Builds ui/menu_background.jpg, the main menu's backdrop: the game's
illustration softened with a light blur, so the logo and cards stand out and
the generated image's mushy detail reads as distance rather than noise.

Baked here rather than blurred by a shader each frame, which older phones
would pay for. The menu covers the screen with it (about half size at
512x288), so BLUR source pixels is roughly half that in game pixels.

Run from anywhere after changing the source or BLUR:
    python3 tools/make_menu_background.py
"""

import os

from PIL import Image, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SOURCE = os.path.join(ROOT, "Gemini_Generated_Image_xyt3f9xyt3f9xyt3.jpeg")
OUT = os.path.join(ROOT, "ui", "menu_background.jpg")

# Gaussian radius in source pixels.
BLUR = 3


def main() -> None:
    src = Image.open(SOURCE).convert("RGB")
    out = src.filter(ImageFilter.GaussianBlur(BLUR))
    out.save(OUT, quality=90)
    print(f"wrote {OUT} {out.size}")


if __name__ == "__main__":
    main()
