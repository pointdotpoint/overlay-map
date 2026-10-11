"""Procedural white UI atlas (tinted in game). Sizes are 4K HUD units and must match NMTheme."""
from __future__ import annotations

import math

from PIL import Image, ImageDraw, ImageFilter

SS = 4  # supersampling factor
SIZES = {
    "chip": 112, "chip_sel": 136, "cluster": 176, "cluster_sel": 200, "mini": 80,
    "ring": 216, "player": 112,
    "bracket_tl": 110, "bracket_tr": 110, "bracket_bl": 110, "bracket_br": 110,
    "icon_quest": 48, "icon_gig": 48, "icon_vendor": 48, "icon_ft": 48, "icon_undisc": 48, "icon_dot": 48,
}
# hex radius / stroke width per hex part (4K units)
_HEX = {"chip": (48, 5), "chip_sel": (60, 7), "cluster": (79, 6), "cluster_sel": (91, 7), "mini": (34, 4)}
_FILL = (41, 41, 41, 235)     # white * 0.16 value, 92% alpha -> tinted dark fill
_WHITE = (255, 255, 255, 255)


def _hex_points(cx: float, cy: float, r: float) -> list[tuple[float, float]]:
    return [(cx + r * math.cos(math.radians(60 * i + 30)), cy + r * math.sin(math.radians(60 * i + 30)))
            for i in range(6)]  # pointy-top: vertices at 90 and 270 degrees


def _canvas(size: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def _down(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def _hex(size: int, r: int, stroke: int) -> Image.Image:
    img, d = _canvas(size)
    c = size * SS / 2
    d.polygon(_hex_points(c, c, r * SS), fill=_FILL)
    pts = _hex_points(c, c, (r - stroke / 2) * SS)
    d.line(pts + [pts[0], pts[1]], fill=_WHITE, width=stroke * SS, joint="curve")
    return _down(img, size)


def _glow(img: Image.Image, radius: float) -> Image.Image:
    # blur alpha only; halo RGB stays pure white (blurring RGBA would darken it toward the transparent black)
    alpha = img.getchannel("A").filter(ImageFilter.GaussianBlur(radius))
    halo = Image.new("RGBA", img.size, (255, 255, 255, 0))
    halo.putalpha(alpha)
    return Image.alpha_composite(halo, img)


def _ring(size: int) -> Image.Image:
    img, d = _canvas(size)
    c, r, w = size * SS / 2, 96 * SS, 5 * SS
    d.ellipse((c - r, c - r, c + r, c + r), outline=_WHITE, width=w)
    return _glow(_down(img, size), 3)


def _player(size: int) -> Image.Image:
    img, d = _canvas(size)
    c = size * SS / 2
    d.ellipse((c - 52 * SS, c - 52 * SS, c + 52 * SS, c + 52 * SS), fill=(255, 255, 255, 46))
    k = SS
    d.polygon([(c, c - 40 * k), (c + 26 * k, c + 29 * k), (c, c + 12 * k), (c - 26 * k, c + 29 * k)], fill=_WHITE)
    return _down(img, size)


def _bracket(size: int, corner: str) -> Image.Image:
    img, d = _canvas(size)
    s, t, pad = size * SS, 9 * SS, 8 * SS
    d.rectangle((pad, pad, s - pad, pad + t), fill=_WHITE)       # horizontal arm (top-left form)
    d.rectangle((pad, pad, pad + t, s - pad), fill=_WHITE)       # vertical arm
    img = _glow(_down(img, size), 3)
    if corner == "tr":
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    elif corner == "bl":
        img = img.transpose(Image.FLIP_TOP_BOTTOM)
    elif corner == "br":
        img = img.transpose(Image.ROTATE_180)
    return img


def _icon(size: int, kind: str) -> Image.Image:
    img, d = _canvas(size)
    k = SS * size / 24.0   # glyphs authored on a 24-unit box centred at (12,12)
    w = int(2.4 * k)

    def P(x, y):
        return (x * k, y * k)

    if kind == "quest":
        d.polygon([P(12, 3), P(21, 12), P(12, 21), P(3, 12)], outline=_WHITE, width=w)
        d.line([P(12, 8), P(12, 13)], fill=_WHITE, width=w)
        d.ellipse((11 * k, 15.5 * k, 13 * k, 17.5 * k), fill=_WHITE)
    elif kind == "gig":
        d.rectangle((4 * k, 8 * k, 20 * k, 19 * k), outline=_WHITE, width=w)
        d.line([P(8, 8), P(8, 5), P(16, 5), P(16, 8)], fill=_WHITE, width=w)
    elif kind == "vendor":
        d.polygon([P(4, 9), P(20, 9), P(18, 20), P(6, 20)], outline=_WHITE, width=w)
        d.arc((8 * k, 3 * k, 16 * k, 13 * k), 180, 360, fill=_WHITE, width=w)
    elif kind == "ft":
        d.line([P(4, 9), P(18, 9)], fill=_WHITE, width=w)
        d.line([P(15, 6), P(18, 9), P(15, 12)], fill=_WHITE, width=w)
        d.line([P(20, 15), P(6, 15)], fill=_WHITE, width=w)
        d.line([P(9, 12), P(6, 15), P(9, 18)], fill=_WHITE, width=w)
    elif kind == "undisc":
        d.arc((7 * k, 3 * k, 17 * k, 13 * k), 180, 60, fill=_WHITE, width=w)
        d.line([P(12, 12), P(12, 15)], fill=_WHITE, width=w)
        d.ellipse((11 * k, 18 * k, 13 * k, 20 * k), fill=_WHITE)
    else:  # dot
        d.ellipse((7 * k, 7 * k, 17 * k, 17 * k), fill=_WHITE)
    return _down(img, size)


def _render(name: str) -> Image.Image:
    size = SIZES[name]
    if name in _HEX:
        return _hex(size, *_HEX[name])
    if name == "ring":
        return _ring(size)
    if name == "player":
        return _player(size)
    if name.startswith("bracket_"):
        return _bracket(size, name.split("_")[1])
    return _icon(size, name.split("_", 1)[1])


def build_ui_atlas() -> tuple[Image.Image, dict[str, tuple[int, int, int, int]]]:
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    parts: dict[str, tuple[int, int, int, int]] = {}
    x = y = row_h = 0
    gap = 4
    for name in sorted(SIZES, key=lambda n: (-SIZES[n], n)):   # shelf packing, largest first
        s = SIZES[name]
        if x + s > 1024:
            x, y, row_h = 0, y + row_h + gap, 0
        if y + s > 1024:
            raise RuntimeError("UI atlas overflow")
        atlas.paste(_render(name), (x, y))
        parts[name] = (x, y, x + s, y + s)
        x += s + gap
        row_h = max(row_h, s)
    return atlas, parts
