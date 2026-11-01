"""Procedural white UI atlas (tinted in game). Sizes are 4K HUD units and must match NMTheme."""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 4  # supersampling factor
SIZES = {
    "plate": 152, "chip": 72, "chip_sel": 92,
    "ring": 216, "player": 112,
    "bracket_tl": 110, "bracket_tr": 110, "bracket_bl": 110, "bracket_br": 110,
    "icon_quest": 48, "icon_gig": 48, "icon_vendor": 48, "icon_ft": 48, "icon_undisc": 48, "icon_dot": 24,
    # collectibles (NMTheme.VanillaIconSize) and the scratch drawn over a collected one
    "icon_c_shard": 64, "icon_c_tarot": 64, "icon_c_weapon": 64, "icon_c_cyber": 64, "icon_c_cloth": 64,
    "icon_c_skill": 64, "icon_strike": 64,
}
# hex radius / stroke width per hex part (4K units)
_HEX = {"chip": (34, 4), "chip_sel": (41, 5)}
_FILL = (41, 41, 41, 235)     # white * 0.16 value, 92% alpha -> tinted dark fill
_WHITE = (255, 255, 255, 255)
_DARK = (4, 6, 10)             # near-black plate/chip fill (tint multiplies, so it stays near black)
_CHIP_FILL = _DARK + (225,)


def _hex_points(cx: float, cy: float, r: float) -> list[tuple[float, float]]:
    return [(cx + r * math.cos(math.radians(60 * i + 30)), cy + r * math.sin(math.radians(60 * i + 30)))
            for i in range(6)]  # pointy-top: vertices at 90 and 270 degrees


def _canvas(size: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def _down(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def _hex(size: int, r: int, stroke: int, fill=_FILL) -> Image.Image:
    img, d = _canvas(size)
    c = size * SS / 2
    d.polygon(_hex_points(c, c, r * SS), fill=fill)
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


def _over(dst: np.ndarray, rgb: float, alpha: np.ndarray) -> None:
    """Composites a flat grey layer with per-pixel alpha (0..1) over dst (float RGBA, alpha 0..1), in place."""
    out_a = alpha + dst[..., 3] * (1.0 - alpha)
    safe = np.where(out_a > 0, out_a, 1.0)
    for ch in range(3):
        dst[..., ch] = (rgb * alpha + dst[..., ch] * dst[..., 3] * (1.0 - alpha)) / safe
    dst[..., 3] = out_a


def _plate(size: int) -> Image.Image:
    """Spec 5.1, tinted in game with the icon colour: a near-black disc to half the radius that cuts out the city, a
    dark falloff to the rim, a faint white glow around the ring (the icon's own glow once tinted), and a 4-unit white
    ring at ~70 %."""
    n = size * SS
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.hypot(x + 0.5 - n / 2, y + 0.5 - n / 2) / SS            # distance from the centre, in units
    ring_r = size / 4.0
    t = np.clip((d - ring_r) / (size / 2.0 - ring_r), 0.0, 1.0)
    out = np.zeros((n, n, 4), np.float32)
    out[..., :3] = np.array(_DARK, np.float32)
    out[..., 3] = np.where(d <= ring_r, 245.0, 235.0 * (1.0 - t) ** 2) / 255.0
    glow = 80.0 / 255.0 * np.exp(-((d - ring_r) / 5.0) ** 2)       # soft, ~5 units each side of the ring
    _over(out, 255.0, glow)
    _over(out, 255.0, (np.abs(d - ring_r) <= 2.0).astype(np.float32) * (178.0 / 255.0))
    out[..., 3] *= 255.0
    img = Image.fromarray(np.rint(np.clip(out, 0, 255)).astype(np.uint8), "RGBA")
    return _down(img, size)


def _player(size: int) -> Image.Image:
    img, d = _canvas(size)
    c = size * SS / 2
    d.ellipse((c - 52 * SS, c - 52 * SS, c + 52 * SS, c + 52 * SS), fill=(255, 255, 255, 46))
    k = SS
    d.polygon([(c, c - 40 * k), (c + 26 * k, c + 29 * k), (c, c + 12 * k), (c - 26 * k, c + 29 * k)], fill=_WHITE)
    return _down(img, size)


def _bracket(size: int, corner: str) -> Image.Image:
    img, d = _canvas(size)
    s, t, pad = size * SS, 3 * SS, 10 * SS
    d.rectangle((pad, pad, s - pad, pad + t), fill=_WHITE)       # horizontal arm (top-left form)
    d.rectangle((pad, pad, pad + t, s - pad), fill=_WHITE)       # vertical arm
    img = _glow(_down(img, size), 3)   # ~6 px soft spread
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
    elif kind == "c_shard":   # a data shard with its contacts
        d.polygon([P(7, 3), P(14, 3), P(17, 6), P(17, 21), P(7, 21)], outline=_WHITE, width=w)
        for x in (10, 12.5, 15):
            d.line([P(x - 0.5, 16), P(x - 0.5, 19)], fill=_WHITE, width=int(1.4 * k))
    elif kind == "c_tarot":   # a card with a star
        d.rectangle((5.5 * k, 2 * k, 18.5 * k, 22 * k), outline=_WHITE, width=w)
        star = [P(12 + r * math.sin(math.radians(36 * i)), 12 - r * math.cos(math.radians(36 * i)))
                for i, r in zip(range(10), [4.8, 2.0] * 5)]
        d.polygon(star, fill=_WHITE)
    elif kind == "c_weapon":   # a pistol
        d.polygon([P(3, 6), P(21, 6), P(21, 11), P(13, 11), P(11, 19), P(6, 19), P(7.5, 11), P(3, 11)],
                  outline=_WHITE, width=w)
        d.line([P(13, 11), P(14, 14), P(10.5, 14)], fill=_WHITE, width=int(1.6 * k))
    elif kind == "c_cyber":   # a chip with pins
        d.rectangle((7 * k, 7 * k, 17 * k, 17 * k), outline=_WHITE, width=w)
        for c in (10, 14):
            d.line([P(c, 3), P(c, 7)], fill=_WHITE, width=w)
            d.line([P(c, 17), P(c, 21)], fill=_WHITE, width=w)
            d.line([P(3, c), P(7, c)], fill=_WHITE, width=w)
            d.line([P(17, c), P(21, c)], fill=_WHITE, width=w)
        d.ellipse((10.5 * k, 10.5 * k, 13.5 * k, 13.5 * k), fill=_WHITE)
    elif kind == "c_cloth":   # a jacket
        d.polygon([P(8.5, 3), P(3, 6.5), P(1.5, 12), P(5.5, 13), P(6, 21), P(18, 21), P(18.5, 13), P(22.5, 12),
                   P(21, 6.5), P(15.5, 3), P(12, 7)], outline=_WHITE, width=w)
        d.line([P(12, 7), P(12, 21)], fill=_WHITE, width=int(1.6 * k))
    elif kind == "c_skill":   # an arrow up in a ring
        d.ellipse((3 * k, 3 * k, 21 * k, 21 * k), outline=_WHITE, width=w)
        d.line([P(12, 17), P(12, 8)], fill=_WHITE, width=w)
        d.line([P(8, 11.5), P(12, 7.5), P(16, 11.5)], fill=_WHITE, width=w, joint="curve")
    elif kind == "strike":   # black edge then white core: the tint colours the core, the edge keeps it readable
        for half, fill in ((2.3, (0, 0, 0, 255)), (1.2, _WHITE)):
            o = half / math.sqrt(2)
            d.polygon([P(3 - o, 21 - o), P(21 - o, 3 - o), P(21 + o, 3 + o), P(3 + o, 21 + o)], fill=fill)
    else:  # dot: a solid disc
        d.ellipse((0, 0, 24 * k - 1, 24 * k - 1), fill=_WHITE)
    return _down(img, size)


def _render(name: str) -> Image.Image:
    size = SIZES[name]
    if name == "plate":
        return _plate(size)
    if name == "chip":
        return _hex(size, *_HEX[name], fill=_CHIP_FILL)
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
