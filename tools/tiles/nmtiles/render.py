"""Top-down orthographic rasterization of styled map meshes into north-up tiles."""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from nmtiles.buildings import Boxes, box_corners
from nmtiles.glb import Mesh
from nmtiles.style import STYLE
from nmtiles.world import Transform


@dataclass(frozen=True)
class LevelGrid:
    mpp: float
    origin_x: float     # world x of the left edge of tile column 0
    origin_top: float   # world y of the top edge of tile row 0 (rows grow south)
    nx: int
    ny: int
    tile: int = 512

    @property
    def tile_world(self) -> float:
        return self.tile * self.mpp

    @property
    def width(self) -> int:
        return self.nx * self.tile

    @property
    def height(self) -> int:
        return self.ny * self.tile


def level_grid(bounds: tuple[float, float, float, float], mpp: float, tile: int = 512) -> LevelGrid:
    minx, miny, maxx, maxy = bounds
    tw = tile * mpp
    ox = math.floor(minx / tw) * tw
    otop = math.ceil(maxy / tw) * tw
    nx = max(1, math.ceil((maxx - ox) / tw))
    ny = max(1, math.ceil((otop - miny) / tw))
    return LevelGrid(mpp, ox, otop, nx, ny, tile)


def _to_px(xy: np.ndarray, origin_x: float, origin_top: float, mpp: float) -> np.ndarray:
    return np.column_stack(((xy[:, 0] - origin_x) / mpp, (origin_top - xy[:, 1]) / mpp))


def _draw_mesh(draw: ImageDraw.ImageDraw, mesh: Mesh, tf: Transform, origin_x: float, origin_top: float,
               mpp: float, width: int, height: int, fill, height_alpha: int = 0) -> None:
    px = _to_px(tf.apply(mesh.positions), origin_x, origin_top, mpp)
    tris = px[mesh.triangles]                       # (M,3,2)
    lo = tris.min(axis=1)
    hi = tris.max(axis=1)
    keep = (hi[:, 0] >= 0) & (lo[:, 0] < width) & (hi[:, 1] >= 0) & (lo[:, 1] < height)
    heights = mesh.positions[:, 1][mesh.triangles].mean(axis=1) if height_alpha else None
    for i in np.nonzero(keep)[0]:
        color = fill
        if height_alpha:
            h = float(np.clip(heights[i] / 150.0, 0.0, 1.0))
            color = (fill[0], fill[1], fill[2], int(fill[3] + height_alpha * h))
        draw.polygon([tuple(p) for p in tris[i]], fill=color)


def rasterize_mask(meshes: list[Mesh], tf: Transform, origin_x: float, origin_top: float, mpp: float,
                   width: int, height: int) -> np.ndarray:
    img = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(img)
    for m in meshes:
        _draw_mesh(draw, m, tf, origin_x, origin_top, mpp, width, height, 255)
    return np.asarray(img) > 0


OUTLINE_MAX_MPP = 4.0   # coarser levels drop the per-box outline: it would be noise


def _draw_boxes(draw: ImageDraw.ImageDraw, boxes: Boxes, grid: LevelGrid, spec: dict) -> None:
    """World-space rotated rectangles; each box's fill alpha grows with its height (metres)."""
    corners = box_corners(boxes)
    px = np.empty_like(corners)
    px[..., 0] = (corners[..., 0] - grid.origin_x) / grid.mpp
    px[..., 1] = (grid.origin_top - corners[..., 1]) / grid.mpp
    lo, hi = px.min(axis=1), px.max(axis=1)
    keep = (hi[:, 0] >= 0) & (lo[:, 0] < grid.width) & (hi[:, 1] >= 0) & (lo[:, 1] < grid.height)
    fr, fg, fb, fa = spec["fill"]
    alpha = (fa + spec.get("height_alpha", 0) * np.clip(boxes.dz / 150.0, 0.0, 1.0)).astype(int)
    outline = tuple(spec["outline"]) if grid.mpp <= OUTLINE_MAX_MPP and "outline" in spec else None
    for i in np.nonzero(keep)[0]:
        draw.polygon([tuple(p) for p in px[i]], fill=(fr, fg, fb, int(alpha[i])), outline=outline)


def render_level(styled: dict[str, list[Mesh]], tf: Transform, grid: LevelGrid,
                 boxes: Boxes | None = None) -> Image.Image:
    w, h = grid.width, grid.height
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    names = set(styled) | ({"building"} if boxes is not None and len(boxes) else set())
    for style in sorted(names, key=lambda s: STYLE[s]["order"]):
        spec = STYLE[style]
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        for m in styled.get(style, []):
            _draw_mesh(draw, m, tf, grid.origin_x, grid.origin_top, grid.mpp, w, h, spec["fill"],
                       spec.get("height_alpha", 0))
        if style == "building" and boxes is not None:
            _draw_boxes(draw, boxes, grid, spec)
        if "glow" in spec:
            radius = max(1.0, 6.0 / grid.mpp)
            glow = Image.new("RGBA", (w, h), spec["glow"])
            glow.putalpha(layer.getchannel("A").filter(ImageFilter.GaussianBlur(radius))
                          .point(lambda a: min(255, a * spec["glow"][3] // 255 * 2)))
            layer = Image.alpha_composite(glow, layer)
        out = Image.alpha_composite(out, layer)
    return out


def slice_tiles(img: Image.Image, grid: LevelGrid) -> dict[tuple[int, int], Image.Image]:
    tiles: dict[tuple[int, int], Image.Image] = {}
    t = grid.tile
    for iy in range(grid.ny):
        for ix in range(grid.nx):
            tile = img.crop((ix * t, iy * t, (ix + 1) * t, (iy + 1) * t))
            if tile.getchannel("A").getextrema()[1] > 0:
                tiles[(ix, iy)] = tile
    return tiles
