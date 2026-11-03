"""NCART metro lines for the map: line definitions, station places, track routes, shared-track slots and the `metro`
tile set (design: docs/superpowers/specs/2026-11-03-nightmap-ncart-lines-design.md).

Sources: the line list of the game's in-train route diagram (ue_metro_route_diagram.inkwidget, LinesList: number,
colour, ordered ENcartStations, looped), the NCART map markers dumped in game (data/ncart_stations.json) and the 3D
map's track mesh (3dmap_metro).
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

DATA = Path(__file__).resolve().parent.parent / "data" / "ncart_stations.json"
LINES = Path(__file__).resolve().parent.parent / "data" / "ncart_lines.json"   # LinesList, trimmed from the widget


@dataclass(frozen=True)
class Line:
    number: int
    letter: str                       # "A".."E" = "ABCDE"[number - 1]
    rgb: tuple[int, int, int]
    stations: tuple[str, ...]         # ENcartStations names, in service order
    looped: bool


@dataclass(frozen=True)
class Station:
    key: str                          # ENcartStations name
    name: str
    xy: tuple[float, float] | None    # world xy; None until placed
    marked: bool                      # has an NCART marker on the map


def _find(o, key: str):
    if isinstance(o, dict):
        if key in o:
            return o[key]
        for v in o.values():
            r = _find(v, key)
            if r is not None:
                return r
    elif isinstance(o, list):
        for v in o:
            r = _find(v, key)
            if r is not None:
                return r
    return None


def load_lines(widget_json: Path) -> list[Line]:
    """The lines of the route-diagram widget (WolvenKit JSON, or a trimmed copy holding LinesList), by number."""
    raw = _find(json.loads(Path(widget_json).read_text()), "LinesList")
    if not raw:
        raise ValueError(f"no LinesList in {widget_json}")
    out = []
    for l in raw:
        n = int(l["lineNumber"])
        c = l["lineColor"]
        out.append(Line(n, "ABCDE"[n - 1], (int(c["Red"]), int(c["Green"]), int(c["Blue"])),
                        tuple(s["station"] for s in l["stationsList"]), bool(l["lineIsLooped"])))
    return sorted(out, key=lambda l: l.number)


def load_stations(path: Path = DATA) -> dict[str, Station]:
    d = json.loads(Path(path).read_text())
    out = {k: Station(k, v["name"], (float(v["pos"][0]), float(v["pos"][1])), True) for k, v in d["marked"].items()}
    for k in d["unmarked"]:
        v = d.get("placed", {}).get(k)
        out[k] = Station(k, v["name"] if v else k, (float(v["pos"][0]), float(v["pos"][1])) if v else None, False)
    return out
