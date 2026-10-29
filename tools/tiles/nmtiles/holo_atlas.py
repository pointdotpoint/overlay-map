"""Procedural hologram overlay atlas `nightmap\\ui\\holo.inkatlas` (white RGB, alpha = shape; tinted in game).

Separate from ui_atlas.py (whose size/space tests are fixed). Everything is deterministic: same bytes every build.

Tileable parts are periodic in both axes, so the first row/column continues the last one:
  holo_scan   64x64    1 px line every 4 px
  holo_grid   256x256  1 px lines every 64 px
  holo_noise  256x256  fine random noise (wrap-around smoothed, so it tiles)
Others:
  holo_bar    512x160  scan band: alpha rises from 0 to a bright core and back to 0 (vertical gradient)
  holo_edge_t/_b 16x64, holo_edge_l/_r 64x16  soft glowing frame line, bright on the outer pixel row, fading inward;
                       stretched along their length (they are uniform that way)
  holo_halo   128x128  radial soft glow for marker halos
  holo_line   16x16    antialiased line: opaque core, alpha ramps to 0 on the top and bottom rows; uniform along x
                       (GPS route pieces stretch it along their length, so their rotated edges are smooth)
"""
from __future__ import annotations

import numpy as np
from PIL import Image

ATLAS_W, ATLAS_H = 1024, 512
SIZES = {   # name -> (w, h)
    "holo_scan": (64, 64), "holo_grid": (256, 256), "holo_noise": (256, 256), "holo_bar": (512, 160),
    "holo_halo": (128, 128), "holo_line": (16, 16),
    "holo_edge_t": (16, 64), "holo_edge_b": (16, 64), "holo_edge_l": (64, 16), "holo_edge_r": (64, 16),
}
TILEABLE = {"holo_scan": 4, "holo_grid": 64, "holo_noise": 256}     # name -> period in px (both axes)
# Fixed layout (4 px gaps so bilinear sampling never bleeds a neighbour in).
LAYOUT = {
    "holo_grid": (0, 0), "holo_noise": (260, 0), "holo_halo": (520, 0), "holo_scan": (652, 0),
    "holo_edge_t": (720, 0), "holo_edge_b": (740, 0), "holo_edge_l": (760, 0), "holo_edge_r": (760, 20),
    "holo_bar": (0, 260), "holo_line": (840, 0),
}
NOISE_SEED = 20261015


def _white(alpha: np.ndarray) -> Image.Image:
    a = np.clip(np.rint(alpha), 0, 255).astype(np.uint8)
    out = np.empty(a.shape + (4,), np.uint8)
    out[..., :3] = 255
    out[..., 3] = a
    return Image.fromarray(out, "RGBA")


def _scan() -> Image.Image:
    a = np.zeros((64, 64), np.float32)
    a[::4, :] = 255
    return _white(a)


def _grid() -> Image.Image:
    a = np.zeros((256, 256), np.float32)
    a[::64, :] = 255
    a[:, ::64] = 255
    return _white(a)


def _noise() -> Image.Image:
    rng = np.random.default_rng(NOISE_SEED)
    n = rng.random((256, 256), dtype=np.float32)
    # 3-tap wrap-around blur (np.roll): keeps the texture seamless while softening single-pixel salt-and-pepper.
    n = 0.5 * n + 0.25 * (np.roll(n, 1, 0) + np.roll(n, -1, 0))
    n = 0.5 * n + 0.25 * (np.roll(n, 1, 1) + np.roll(n, -1, 1))
    n = (n - n.min()) / max(float(n.max() - n.min()), 1e-6)
    return _white(n * 255.0)


def _bar() -> Image.Image:
    h, w = 160, 512
    t = (np.arange(h, dtype=np.float32) + 0.5) / h                # 0..1 top to bottom
    # soft rise to a bright core near 62 % (the leading edge, as the bar sweeps down), quick falloff below it
    core = 0.62
    up = np.where(t < core, (t / core) ** 2.2, 0.0)
    down = np.where(t >= core, (1.0 - (t - core) / (1.0 - core)) ** 1.6, 0.0)
    prof = (up + down) * 255.0
    prof[int(core * h)] = 255.0
    return _white(np.tile(prof[:, None], (1, w)))


def _halo() -> Image.Image:
    n = 128
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    r = np.hypot(x - (n - 1) / 2, y - (n - 1) / 2) / (n / 2)
    a = np.clip(1.0 - r, 0.0, 1.0)
    a = (a * a * (3.0 - 2.0 * a)) ** 1.4 * 255.0                  # smoothstep-ish: bright centre, zero at the rim
    return _white(a)


def _edge(w: int, h: int, side: str) -> Image.Image:
    """Bright on the outermost pixel row/column (that touches the frame), fading to 0 over 64 px inward."""
    depth = 64
    d = np.arange(depth, dtype=np.float32) / (depth - 1)
    prof = 230.0 * (1.0 - d) ** 3 + 25.0 * np.exp(-d * 18.0)     # glow tail plus a crisp edge line
    prof[0] = 255.0
    if side in ("t", "b"):
        col = prof if side == "t" else prof[::-1]
        return _white(np.tile(col[:, None], (1, w)))
    row = prof if side == "l" else prof[::-1]
    return _white(np.tile(row[None, :], (h, 1)))


def _line() -> Image.Image:
    n = 16
    d = np.minimum(np.arange(n) + 0.5, n - (np.arange(n) + 0.5))    # distance of each row centre from the edge
    u = np.clip((d - 0.5) / 4.0, 0.0, 1.0)
    prof = u * u * (3.0 - 2.0 * u) * 255.0                           # smoothstep: 0 on the outer rows, 255 from row 4
    return _white(np.tile(prof[:, None], (1, n)))


def _render(name: str) -> Image.Image:
    if name == "holo_scan":
        return _scan()
    if name == "holo_grid":
        return _grid()
    if name == "holo_noise":
        return _noise()
    if name == "holo_bar":
        return _bar()
    if name == "holo_halo":
        return _halo()
    if name == "holo_line":
        return _line()
    return _edge(*SIZES[name], name[-1])


def build_holo_atlas() -> tuple[Image.Image, dict[str, tuple[int, int, int, int]]]:
    atlas = Image.new("RGBA", (ATLAS_W, ATLAS_H), (0, 0, 0, 0))
    parts: dict[str, tuple[int, int, int, int]] = {}
    for name in SIZES:
        w, h = SIZES[name]
        x, y = LAYOUT[name]
        if x + w > ATLAS_W or y + h > ATLAS_H:
            raise RuntimeError(f"holo atlas overflow: {name}")
        atlas.paste(_render(name), (x, y))
        parts[name] = (x, y, x + w, y + h)
    return atlas, parts
