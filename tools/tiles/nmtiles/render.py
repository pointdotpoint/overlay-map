"""Level grids and top-down rasterization of map meshes (the latter is only used by calibration)."""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw

from nmtiles.glb import Mesh
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
    tris = np.floor(px[mesh.triangles])                       # (M,3,2)
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
