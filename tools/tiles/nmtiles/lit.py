"""Lit buildings: the vanilla world map's building boxes drawn as a 3D city seen from straight above.

Review 2026-11-05: flat footprint outlines (merged, smoothed or split into height layers) read as rough cut-outs, and
the player wanted buildings "smooth and realistic" like the vanilla map. The vanilla map gets that look from lighting,
so every tile now renders the boxes as a height map and shades it:
  roofs     brighter the taller the building
  shadows   each box casts a soft shadow from a fixed light in the north-west, on the ground and on lower roofs
  base      soft darkening where a lower roof or the ground meets something taller (ambient occlusion)
  edges     a thin line wherever the height jumps (the outline set), so stepped towers and blocks stay crisp
Everything is supersampled, so nothing looks pixelated. The tiles hold brightness only (grey RGB, alpha = coverage
or shadow): the runtime still tints them with NMTheme, so every colour theme keeps working. Ground shadows are black
with partial alpha: they darken the panel under the buildings, and the road set, drawn on top, stays as bright.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from nmtiles import buildings

# light
SHADOW_DIR = np.array([1.0, -1.0]) / math.sqrt(2.0)   # shadows fall south-east: the light is in the north-west
SHADOW_K = 0.7                                       # shadow length per metre of height (sun ~55 degrees up)
SHADOW_STEP_M = 6.0                                  # a shadow is swept in steps of about this length
SHADOW_MAX_STEPS = 16
SHADOW_EPS_M = 1.0                                   # a roof is shadowed only by something this much taller
MIN_CASTER_M = 2.0                                   # lower boxes cast no shadow
SOFT_M = 1.5                                         # shadow edge softness (Gaussian sigma)
# shading
ROOF_BASE = 0.3                                      # brightness of a ground-level roof; 1.0 at ROOF_REF_M and up
ROOF_REF_M = 120.0
ROOF_GAMMA = 0.6
ROOF_SHADOW = 0.5                                    # a shadowed roof loses this much brightness
GROUND_SHADOW = 0.5                                  # alpha of a shadow on the ground (black)
AO_SIGMA_M = 6.0
AO_SCALE_M = 15.0                                    # height difference that gives full occlusion
AO_ROOF, AO_GROUND = 0.3, 0.35
# edges
EDGE_JUMP_M = 8.0                                    # a height step at least this tall gets an edge line
MAX_TOP_M = 400.0
# boxes left out: floating cables, beams and bridges (thin, long, off the ground) cut across buildings as spokes
THIN_M, LONG_M, ASPECT, FLOAT_M = 4.0, 12.0, 4.0, 3.0
GROUND_CELL = 40.0          # local ground = lowest box bottom in the 3x3 cells of this size around a box


@dataclass
class LitBoxes:
    quads: np.ndarray       # (N, 4, 2) float64 world corners, counter-clockwise
    top: np.ndarray         # (N,) top height above the local ground, metres
    sweep: np.ndarray       # (N, 2, 2) bbox of the box and its shadow: what a tile must query

    def __len__(self) -> int:
        return len(self.top)


def _local_ground(cx: np.ndarray, cy: np.ndarray, bottom: np.ndarray) -> np.ndarray:
    gx = np.floor(cx / GROUND_CELL).astype(np.int64)
    gy = np.floor(cy / GROUND_CELL).astype(np.int64)
    x0, y0 = gx.min() - 1, gy.min() - 1
    grid = np.full((gx.max() - x0 + 2, gy.max() - y0 + 2), np.inf)
    np.minimum.at(grid, (gx - x0, gy - y0), bottom)
    pad = np.pad(grid, 1, constant_values=np.inf)
    near = np.min([pad[1 + i:pad.shape[0] - 1 + i, 1 + j:pad.shape[1] - 1 + j]
                   for i in (-1, 0, 1) for j in (-1, 0, 1)], axis=0)
    return near[gx - x0, gy - y0]


def lit_boxes(boxes: dict[str, buildings.Boxes] | buildings.Boxes) -> LitBoxes:
    """Every box with its height above the local ground; floating cables and beams left out."""
    b = boxes if isinstance(boxes, buildings.Boxes) else buildings.Boxes.concat(
        [v for _, v in sorted(boxes.items()) if len(v)])
    if not len(b):
        return LitBoxes(np.zeros((0, 4, 2)), np.zeros(0), np.zeros((0, 2, 2)))
    if b.z is None:
        raise ValueError("lit_boxes needs box heights (Boxes.z)")
    bottom = b.z - b.dz / 2
    ground = _local_ground(b.cx, b.cy, bottom)
    thin, long_ = np.minimum(b.dx, b.dy), np.maximum(b.dx, b.dy)
    floating = (thin < THIN_M) & (long_ > LONG_M) & (long_ > ASPECT * thin) & (bottom - ground > FLOAT_M)
    keep = ~floating
    quads = buildings.box_corners(b)[keep]
    top = np.clip(b.z[keep] + b.dz[keep] / 2 - ground[keep], 0.3, MAX_TOP_M)
    shift = SHADOW_DIR[None, :] * (top * SHADOW_K)[:, None]
    lo = np.minimum(quads.min(1), quads.min(1) + shift)
    hi = np.maximum(quads.max(1), quads.max(1) + shift)
    return LitBoxes(quads, top, np.stack([lo, hi], 1))


def roof_brightness(h: np.ndarray) -> np.ndarray:
    return ROOF_BASE + (1.0 - ROOF_BASE) * np.clip(h / ROOF_REF_M, 0.0, 1.0) ** ROOF_GAMMA


def _shadow_polys(quads: np.ndarray, top: np.ndarray, mpp: float) -> tuple[np.ndarray, np.ndarray]:
    """(P, 4, 2) world polygons and (P,) heights whose painter's union (highest wins) is the height of the shadow
    rays over each point: a box's footprint swept along SHADOW_DIR in steps, each step at the ray's height there."""
    m = top >= MIN_CASTER_M
    q, t = quads[m], top[m]
    if not len(t):
        return np.zeros((0, 4, 2)), np.zeros(0)
    length = t * SHADOW_K
    step = max(SHADOW_STEP_M, 2.0 * mpp)
    n = np.clip(np.ceil(length / step), 1, SHADOW_MAX_STEPS).astype(np.int64)
    idx = np.repeat(np.arange(len(t)), n)
    j = np.arange(len(idx)) - np.repeat(np.cumsum(n) - n, n)
    nn = n[idx].astype(np.float64)
    a = SHADOW_DIR[None, :] * (length[idx] * j / nn)[:, None]
    b = SHADOW_DIR[None, :] * (length[idx] * (j + 1) / nn)[:, None]
    v = t[idx] * (1.0 - j / nn)                          # ray height where the step starts (slightly generous)
    qa, qb = q[idx] + a[:, None, :], q[idx] + b[:, None, :]
    polys = [qb]
    for k in range(4):                                   # each edge swept from a to b
        k1 = (k + 1) % 4
        polys.append(np.stack([qa[:, k], qa[:, k1], qb[:, k1], qb[:, k]], 1))
    vals = [v] * 5
    first = j == 0
    polys.append(qa[first])                              # the footprint itself, at full height
    vals.append(v[first])
    return np.concatenate(polys), np.concatenate(vals)


def _paint(size: int, polys_px: np.ndarray, vals: np.ndarray) -> np.ndarray:
    """Float image: each polygon filled with its value, lowest first, so the highest wins."""
    img = Image.new("F", (size, size), 0.0)
    if len(vals):
        draw = ImageDraw.Draw(img)
        order = np.argsort(vals, kind="stable")
        flat = polys_px[order].reshape(len(order), 8).tolist()
        for p, val in zip(flat, vals[order].tolist()):
            draw.polygon(p, fill=val)
    return np.asarray(img, np.float32)


def _block_mean(a: np.ndarray, ss: int) -> np.ndarray:
    h, w = a.shape
    return a.reshape(h // ss, ss, w // ss, ss).mean(axis=(1, 3))


def _block_max(a: np.ndarray, ss: int) -> np.ndarray:
    h, w = a.shape
    return a.reshape(h // ss, ss, w // ss, ss).max(axis=(1, 3))


def margin_px(mpp: float) -> int:
    """Output px of margin a tile needs so its blurs see the neighbouring tile (3 sigma of the widest blur)."""
    return int(math.ceil(3.0 * max(AO_SIGMA_M, SOFT_M) / mpp)) + 3


def shade(quads: np.ndarray, top: np.ndarray, x0: float, y1: float, size: int, ss: int, mpp: float
          ) -> tuple[np.ndarray, np.ndarray] | None:
    """(bfill RGBA uint8, outline alpha uint8) at output resolution (size // ss), margin included, for the boxes
    given (already selected for this window). The window's top-left world corner is (x0, y1); y grows north."""
    if not len(top):
        return None
    s = ss / mpp

    def to_px(p: np.ndarray) -> np.ndarray:
        out = np.empty_like(p)
        out[..., 0] = np.floor((p[..., 0] - x0) * s)
        out[..., 1] = np.floor((y1 - p[..., 1]) * s)
        return out

    h = _paint(size, to_px(quads), top.astype(np.float64))
    sp, sv = _shadow_polys(quads, top, mpp)
    ray = _paint(size, to_px(sp), sv)
    cov = (h > 0).astype(np.float32)
    shadow = (ray > h + SHADOW_EPS_M).astype(np.float32)
    jump = ndimage.maximum_filter(h, 3) - ndimage.minimum_filter(h, 3)
    edge = ((jump > EDGE_JUMP_M) | (ndimage.maximum_filter(cov, 3) != ndimage.minimum_filter(cov, 3))).astype(np.float32)
    edge = ndimage.maximum_filter(edge, ss)              # about one output px wide

    c1 = _block_mean(cov, ss)
    lit1 = _block_mean(cov * roof_brightness(h), ss)
    hmax = _block_max(h, ss)
    sh1 = _block_mean(shadow, ss)
    soft = SOFT_M / mpp
    if soft > 0.3:
        sh1 = ndimage.gaussian_filter(sh1, soft)
    ao1 = np.clip((ndimage.gaussian_filter(hmax, AO_SIGMA_M / mpp) - hmax) / AO_SCALE_M, 0.0, 1.0)
    roof = lit1 * (1.0 - ROOF_SHADOW * sh1) * (1.0 - AO_ROOF * ao1)
    ground = np.clip(np.maximum(GROUND_SHADOW * sh1, AO_GROUND * ao1), 0.0, 1.0)
    alpha = c1 + (1.0 - c1) * ground
    rgb = np.where(alpha > 1e-6, roof / np.maximum(alpha, 1e-6), 0.0)
    fill = np.empty(c1.shape + (4,), np.uint8)
    fill[..., :3] = np.rint(np.clip(rgb, 0, 1) * 255)[..., None]
    fill[..., 3] = np.rint(np.clip(alpha, 0, 1) * 255)
    fill[fill[..., 3] == 0, :3] = 0
    return fill, np.rint(_block_mean(edge, ss) * 255).astype(np.uint8)
