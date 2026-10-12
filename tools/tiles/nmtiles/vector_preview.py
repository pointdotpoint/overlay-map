"""SVG previews of the packed vector geometry (spec 2026-10-12 §4.6), drawn as in-game at the level's design unit."""
from __future__ import annotations

from pathlib import Path

from nmtiles.vector_extract import Rect

BG = "#08121a"
# style -> (fill, fill opacity, stroke, stroke opacity, stroke width in screen units)
STYLE_SVG = {
    "land": ("#28c8ff", 0.05, "none", 0.0, 0.0),
    "water": ("#28c8ff", 0.13, "none", 0.0, 0.0),
    "block0": ("#7af0ff", 0.06, "#7af0ff", 0.45, 1.0),
    "block1": ("#7af0ff", 0.09, "#7af0ff", 0.45, 1.0),
    "block2": ("#7af0ff", 0.12, "#7af0ff", 0.45, 1.0),
    "road": ("none", 0.0, "#7af0ff", 0.85, 1.5),
    "metro": ("none", 0.0, "#ff4fd8", 0.80, 2.0),
}


def _hits(b: Rect, r: Rect) -> bool:
    return b[2] >= r[0] and b[0] <= r[2] and b[3] >= r[1] and b[1] <= r[3]


def write_svg(path: Path, cells: dict, rect: Rect, unit: float) -> Path:
    x0, y0, x1, y1 = rect
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0:g} {-y1:g} {x1 - x0:g} {y1 - y0:g}" '
           f'width="{min(4000, int((x1 - x0) / unit))}">',
           f'<rect x="{x0:g}" y="{-y1:g}" width="{x1 - x0:g}" height="{y1 - y0:g}" fill="{BG}"/>']
    for c in cells.values():
        if not _hits(c.bounds(), rect):
            continue
        for s in c.shapes:
            fill, fo, stroke, so, w = STYLE_SVG[s.style]
            d = "M" + " L".join(f"{x:.2f} {-y:.2f}" for x, y in s.pts)
            out.append(f'<path d="{d}" fill="{fill}" fill-opacity="{fo}" stroke="{stroke}" stroke-opacity="{so}" '
                       f'stroke-width="{w * unit:g}" stroke-linejoin="round" stroke-linecap="round"/>')
    out.append("</svg>\n")
    path.write_text("\n".join(out))
    return path
