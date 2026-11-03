"""Offline hologram preview (build/preview_holo_{close,far}.png): the in-game layer stack composited with plain
"over" blends (the engine has no additive blend), using the shipped baked tiles and holo atlas.

Order, bottom to top: dim city scene stand-in, panel background (see-through), grid, glow (a level 2 steps coarser
than the camera's, bilinearly upscaled), road, bfill, outline, scanlines, noise, marker halos + markers, scan bar,
edge glow + brackets. Defaults are NMTheme's cyan values. Static frame: the scan bar is drawn mid-sweep.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

from nmtiles.holo_atlas import build_holo_atlas
from nmtiles.preview import CENTRE, VIEW

TILE = 512
GLOW_OFFSET = 2
PREVIEWS = (("close", 0.5), ("far", 4.0))
ACCENT = (0x4f, 0xe3, 0xff)
SETS = (            # set, rgb, opacity (NMTheme.TileTint / TileOpacity, cyan)
    ("bfill", (0x9f, 0xf3, 0xff), 0.12),
    ("outline", (0x9f, 0xf3, 0xff), 0.90),
    ("road", (0x5c, 0xb1, 0xec), 0.90),
)
PANEL_BG = (0x08, 0x12, 0x1a)
PANEL_OPACITY = 0.45
# pin colours (vanilla state colours) at fixed offsets from the centre, in screen px: (dx, dy, rgb)
PINS = ((-420, -160, (255, 255, 78)), (260, -210, (0, 255, 213)), (120, 190, (255, 113, 103)),
        (-250, 250, (89, 180, 255)), (480, 120, (204, 129, 255)))


def pick_level(levels: list[dict], mpp: float) -> int:
    best = 0
    for i, lv in enumerate(levels):
        if lv["mpp"] <= mpp * 1.001:
            best = i
    return best


def _window_alpha(tiles: dict[tuple[int, int, int], Path], li: int, level: dict, centre: tuple[float, float],
                  box: tuple[float, float, float, float]) -> np.ndarray:
    """Alpha (float 0..1) of the level-pixel box (left, top, right, bottom), integer-aligned outward."""
    l0, t0 = int(np.floor(box[0])), int(np.floor(box[1]))
    r0, b0 = int(np.ceil(box[2])), int(np.ceil(box[3]))
    out = np.zeros((b0 - t0, r0 - l0), np.float32)
    for (lv, ix, iy), path in tiles.items():
        if lv != li:
            continue
        x0, y0 = ix * TILE, iy * TILE
        cx0, cy0, cx1, cy1 = max(x0, l0), max(y0, t0), min(x0 + TILE, r0), min(y0 + TILE, b0)
        if cx0 >= cx1 or cy0 >= cy1:
            continue
        im = Image.open(path).convert("RGBA")
        if im.size != (TILE, TILE):     # half-resolution glow tiles are stretched to the tile's 512 units in game
            im = im.resize((TILE, TILE), Image.BILINEAR)
        a = np.asarray(im)[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0, 3]
        out[cy0 - t0:cy1 - t0, cx0 - l0:cx1 - l0] = a.astype(np.float32) / 255.0
    return out


def _layer(tiles: dict, levels: list[dict], li: int, centre: tuple[float, float], mpp: float,
           size: tuple[int, int]) -> np.ndarray:
    """Alpha of level li drawn scaled by levels[li].mpp / mpp so it covers `size` screen px around `centre`."""
    w, h = size
    lvl = levels[li]
    k = lvl["mpp"] / mpp                                    # screen px per level px
    cx = (centre[0] - lvl["origin_x"]) / lvl["mpp"]
    cy = (lvl["origin_top"] - centre[1]) / lvl["mpp"]
    box = (cx - w / 2 / k, cy - h / 2 / k, cx + w / 2 / k, cy + h / 2 / k)
    a = _window_alpha(tiles, li, lvl, centre, box)
    l0, t0 = int(np.floor(box[0])), int(np.floor(box[1]))
    img = Image.fromarray(a, "F")
    return np.asarray(img.resize((w, h), Image.BILINEAR, box=(box[0] - l0, box[1] - t0, box[2] - l0, box[3] - t0)),
                      np.float32)


def _over(canvas: np.ndarray, rgb, alpha: np.ndarray) -> None:
    a = alpha[..., None]
    canvas[:] = canvas * (1.0 - a) + np.array(rgb, np.float32) * a


def _tiled(part: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    w, h = size
    ph, pw = part.shape
    return np.tile(part, (h // ph + 1, w // pw + 1))[:h, :w]


def _scene(size: tuple[int, int]) -> np.ndarray:
    """A dark, blurred, neon-ish stand-in for the game world behind the see-through panel."""
    w, h = size
    rng = np.random.default_rng(11)
    img = Image.new("RGB", size, (14, 12, 22))
    px = np.asarray(img).astype(np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    for cx, cy, r, col in ((0.18, 0.3, 0.28, (150, 40, 120)), (0.75, 0.2, 0.3, (30, 80, 140)), (0.5, 0.75, 0.35, (120, 30, 40)),
                           (0.9, 0.8, 0.25, (160, 120, 40))):
        d = np.hypot(xx / w - cx, yy / h - cy) / r
        px += np.clip(1.0 - d, 0, 1)[..., None] ** 2 * np.array(col, np.float32) * 0.55
    px += rng.random((h, w, 1), dtype=np.float32) * 6
    return np.asarray(Image.fromarray(np.clip(px, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(18)), np.float32).copy()


def compose(tiles: dict[str, dict[tuple[int, int, int], Path]], levels: list[dict], mpp: float,
            centre: tuple[float, float] = CENTRE, size: tuple[int, int] = VIEW) -> Image.Image:
    w, h = size
    atlas, parts = build_holo_atlas()
    A = np.asarray(atlas)[..., 3].astype(np.float32) / 255.0

    def part(name: str) -> np.ndarray:
        l, t, r, b = parts[name]
        return A[t:b, l:r]

    canvas = _scene(size)
    _over(canvas, PANEL_BG, np.full((h, w), PANEL_OPACITY, np.float32))
    _over(canvas, ACCENT, _tiled(part("holo_grid"), size) * 0.07)
    base = pick_level(levels, mpp)
    gl = min(base + GLOW_OFFSET, len(levels) - 1)
    if tiles.get("glow"):
        _over(canvas, ACCENT, _layer(tiles["glow"], levels, gl, centre, mpp, size) * 0.45)
    for name, rgb, op in SETS:
        _over(canvas, rgb, _layer(tiles[name], levels, base, centre, mpp, size) * op)
    _over(canvas, (0, 0, 0), _tiled(part("holo_scan"), size) * 0.20)
    _over(canvas, ACCENT, _tiled(part("holo_noise"), size) * 0.12)
    halo = part("holo_halo")
    hs = 90
    halo_s = np.asarray(Image.fromarray(halo, "F").resize((hs * 2, hs * 2), Image.BILINEAR), np.float32)
    for dx, dy, rgb in PINS:
        x0, y0 = int(w / 2 + dx - hs), int(h / 2 + dy - hs)
        a = np.zeros((h, w), np.float32)
        sx0, sy0 = max(-x0, 0), max(-y0, 0)
        ex, ey = min(x0 + hs * 2, w), min(y0 + hs * 2, h)
        if ex > max(x0, 0) and ey > max(y0, 0):
            a[max(y0, 0):ey, max(x0, 0):ex] = halo_s[sy0:sy0 + ey - max(y0, 0), sx0:sx0 + ex - max(x0, 0)] * 0.35
        _over(canvas, rgb, a)
        d = np.hypot(*np.mgrid[0:h, 0:w].astype(np.float32) - np.array([h / 2 + dy, w / 2 + dx], np.float32)[:, None, None])
        _over(canvas, rgb, np.clip(12.0 - d, 0, 1) * 0.85)
    bh = int(h * 0.14)
    bar = np.asarray(Image.fromarray(part("holo_bar"), "F").resize((w, bh), Image.BILINEAR), np.float32)
    y0 = int(h * 0.42)
    a = np.zeros((h, w), np.float32)
    a[y0:y0 + bh] = bar * 0.25
    _over(canvas, ACCENT, a)
    thick = max(2, int(40 * w / 3840 * 2))
    for side in "tblr":
        e = part(f"holo_edge_{side}")
        if side in "tb":
            img = np.asarray(Image.fromarray(e, "F").resize((w, thick), Image.BILINEAR), np.float32)
            a = np.zeros((h, w), np.float32)
            if side == "t":
                a[:thick] = img
            else:
                a[h - thick:] = img
        else:
            img = np.asarray(Image.fromarray(e, "F").resize((thick, h), Image.BILINEAR), np.float32)
            a = np.zeros((h, w), np.float32)
            if side == "l":
                a[:, :thick] = img
            else:
                a[:, w - thick:] = img
        _over(canvas, ACCENT, a * 0.6)
    arm = int(110 * w / 3840 * 2)
    br = np.zeros((h, w), np.float32)
    t = max(3, arm // 12)
    for (x0, y0, dx, dy) in ((0, 0, 1, 1), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)):
        xs = slice(x0, x0 + dx * arm, dx) if dx > 0 else slice(x0 - arm, x0)
        ys = slice(y0, y0 + dy * t, dy) if dy > 0 else slice(y0 - t, y0)
        br[ys, xs] = 1.0
        xs2 = slice(x0, x0 + dx * t, dx) if dx > 0 else slice(x0 - t, x0)
        ys2 = slice(y0, y0 + dy * arm, dy) if dy > 0 else slice(y0 - arm, y0)
        br[ys2, xs2] = 1.0
    _over(canvas, (0x7a, 0xf0, 0xff), br)
    return Image.fromarray(np.clip(canvas + 0.5, 0, 255).astype(np.uint8), "RGB")


def write_holo_previews(levels: list[dict], set_pngs: dict[str, dict[tuple[int, int, int], Path]], out_dir: Path,
                        centre: tuple[float, float] = CENTRE) -> list[Path]:
    paths = []
    for name, mpp in PREVIEWS:
        paths.append(out_dir / f"preview_holo_{name}.png")
        compose(set_pngs, levels, mpp, centre).save(paths[-1])
    return paths
