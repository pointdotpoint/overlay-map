"""Welcome screen picture `overlaymap\\ui\\welcome.inkatlas`: the themes banner (docs/banners), one part "welcome".

Shown once, below the text of the first-run tutorial popup (r6/scripts/OverlayMap/Core/Welcome.reds).
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

from nmtiles.ncart import to_engine_linear

BANNER = Path(__file__).resolve().parents[3] / "docs" / "banners" / "1_themes_1920x1080.png"
W, H = 1024, 576   # 16:9, multiples of 4 for BC7


def build_welcome_atlas() -> tuple[Image.Image, dict[str, tuple[int, int, int, int]]]:
    img = Image.open(BANNER).convert("RGBA").resize((W, H), Image.LANCZOS)
    # The texture is read as linear colour: store linear light, or the banner comes out pastel (as NCART did).
    return to_engine_linear(img), {"welcome": (0, 0, W, H)}
