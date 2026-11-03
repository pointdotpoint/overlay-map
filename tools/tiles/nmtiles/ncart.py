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


# ------------------------------------------------------------------------------------------------------ track graph

RES = 1.0             # m per pixel of the track raster
PRUNE_M = 15.0        # dead-end skeleton spurs shorter than this are artefacts of wide track areas
SMOOTH_PX = 7         # moving-average window along an edge (px), removes the raster staircase
SIMPLIFY_M = 0.25     # Douglas-Peucker tolerance after smoothing
SPUR_MIN_M = 6.0      # a station farther than this from the track gets a spur from the nearest track point

_NB = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1))


@dataclass
class Edge:
    a: int
    b: int
    pts: np.ndarray       # (k, 2) world xy from node a to node b, endpoints equal to the nodes


@dataclass
class TrackGraph:
    nodes: np.ndarray     # (n, 2) world xy
    edges: list[Edge]


def metro_tris(glb: Path) -> np.ndarray:
    """World-xy triangles of the 3D map's track mesh."""
    from nmtiles.heightmap import MESHES, _mesh_tris
    flip, offset = MESHES["3dmap_metro"]
    return _mesh_tris(Path(glb), flip, offset)[:, :, :2].astype(np.float64)


def _raster(tris: np.ndarray, res: float) -> tuple[np.ndarray, float, float]:
    from PIL import Image, ImageDraw
    lo = tris.reshape(-1, 2).min(0) - 4 * res
    hi = tris.reshape(-1, 2).max(0) + 4 * res
    w, h = (np.ceil((hi - lo) / res)).astype(int) + 1
    img = Image.new("1", (int(w), int(h)))
    d = ImageDraw.Draw(img)
    for t in tris:
        d.polygon([((x - lo[0]) / res, (hi[1] - y) / res) for x, y in t], fill=1)
    return np.asarray(img).astype(np.uint8), float(lo[0]), float(hi[1])


def _thin(img: np.ndarray) -> np.ndarray:
    """Zhang-Suen thinning to a 1-px, 8-connected skeleton."""
    img = img.copy()
    while True:
        changed = False
        for step in (0, 1):
            P = np.pad(img, 1)
            p2, p3, p4, p5 = P[:-2, 1:-1], P[:-2, 2:], P[1:-1, 2:], P[2:, 2:]
            p6, p7, p8, p9 = P[2:, 1:-1], P[2:, :-2], P[1:-1, :-2], P[:-2, :-2]
            b = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
            seq = (p2, p3, p4, p5, p6, p7, p8, p9, p2)
            a = sum(((seq[i] == 0) & (seq[i + 1] == 1)).astype(np.uint8) for i in range(8))
            c = ((p2 * p4 * p6 == 0) & (p4 * p6 * p8 == 0)) if step == 0 else ((p2 * p4 * p8 == 0) & (p2 * p6 * p8 == 0))
            m = (img == 1) & (b >= 2) & (b <= 6) & (a == 1) & c
            if m.any():
                img[m] = 0
                changed = True
        if not changed:
            return img


def _smooth(p: np.ndarray, win: int) -> np.ndarray:
    if len(p) <= 2 or win <= 1:
        return p
    k = min(win, len(p) - (1 - len(p) % 2))
    if k < 3:
        return p
    pad = k // 2
    q = np.concatenate([np.repeat(p[:1], pad, 0), p, np.repeat(p[-1:], pad, 0)])
    ker = np.ones(k) / k
    out = np.stack([np.convolve(q[:, 0], ker, "valid"), np.convolve(q[:, 1], ker, "valid")], 1)
    out[0], out[-1] = p[0], p[-1]
    return out


def _simplify(p: np.ndarray, tol: float) -> np.ndarray:
    if len(p) <= 2:
        return p
    keep = np.zeros(len(p), bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(p) - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        a, b = p[i], p[j]
        ab = b - a
        L = np.hypot(*ab)
        seg = p[i + 1:j] - a
        d = np.abs(ab[0] * seg[:, 1] - ab[1] * seg[:, 0]) / L if L > 1e-9 else np.hypot(seg[:, 0], seg[:, 1])
        k = int(np.argmax(d))
        if d[k] > tol:
            keep[i + 1 + k] = True
            stack += [(i, i + 1 + k), (i + 1 + k, j)]
    return p[keep]


def _trace(skel: np.ndarray, x0: float, ytop: float, res: float) -> TrackGraph:
    from scipy.ndimage import convolve, label
    sk = skel.astype(bool)
    deg = convolve(sk.astype(np.uint8), np.array([[1, 1, 1], [1, 0, 1], [1, 1, 1]], np.uint8), mode="constant") * sk
    node_px = sk & (deg != 2)
    lab, n = label(node_px, structure=np.ones((3, 3)))
    H, W = sk.shape
    world = lambda r, c: (x0 + (c + 0.5) * res, ytop - (r + 0.5) * res)
    nodes = [None] * n
    rr, cc = np.nonzero(lab)
    for k in range(1, n + 1):
        m = lab[rr, cc] == k
        nodes[k - 1] = np.mean([world(r, c) for r, c in zip(rr[m], cc[m])], axis=0)
    visited = np.zeros_like(sk)
    edges: list[Edge] = []

    def walk(start_node: int, r: int, c: int, pr: int, pc: int) -> None:
        path = [world(pr, pc), world(r, c)]
        while True:
            if lab[r, c]:
                end = lab[r, c] - 1
                if end != start_node or len(path) > 4:
                    edges.append(Edge(start_node, end, np.array(path)))
                return
            visited[r, c] = True
            nxt = None
            for dr, dc in _NB:
                y, x = r + dr, c + dc
                if 0 <= y < H and 0 <= x < W and sk[y, x] and (y, x) != (pr, pc) and not visited[y, x]:
                    if lab[y, x] and lab[y, x] - 1 == start_node and len(path) <= 4:
                        continue
                    nxt = (y, x)
                    if lab[y, x]:
                        break
            if nxt is None:
                return
            pr, pc, (r, c) = r, c, nxt
            path.append(world(r, c))

    for r, c in zip(rr, cc):
        k = lab[r, c] - 1
        for dr, dc in _NB:
            y, x = r + dr, c + dc
            if 0 <= y < H and 0 <= x < W and sk[y, x] and not lab[y, x] and not visited[y, x]:
                walk(k, y, x, r, c)
    # Rings with no junction at all: start a node anywhere on them.
    left = sk & ~visited & (lab == 0)
    while left.any():
        r, c = map(int, np.argwhere(left)[0])
        nodes.append(np.array(world(r, c)))
        k = len(nodes) - 1
        lab[r, c] = k + 1
        for dr, dc in _NB:
            y, x = r + dr, c + dc
            if 0 <= y < H and 0 <= x < W and sk[y, x] and not lab[y, x] and not visited[y, x]:
                walk(k, y, x, r, c)
                break
        left = sk & ~visited & (lab == 0)
    return TrackGraph(np.array(nodes, float).reshape(-1, 2), edges)


def _finish(g: TrackGraph, prune_m: float) -> TrackGraph:
    """Prune short dead-end spurs, snap edge ends to their nodes, smooth and simplify, drop unused nodes."""
    edges = list(g.edges)
    while True:
        deg = np.bincount(np.array([[e.a, e.b] for e in edges]).ravel(), minlength=len(g.nodes)) if edges else np.zeros(len(g.nodes), int)
        drop = [i for i, e in enumerate(edges)
                if e.a != e.b and (deg[e.a] == 1) != (deg[e.b] == 1)
                and np.linalg.norm(np.diff(e.pts, axis=0), axis=1).sum() < prune_m]
        if not drop:
            break
        edges = [e for i, e in enumerate(edges) if i not in set(drop)]
    out = []
    for e in edges:
        p = e.pts.copy()
        p[0], p[-1] = g.nodes[e.a], g.nodes[e.b]
        out.append(Edge(e.a, e.b, _simplify(_smooth(p, SMOOTH_PX), SIMPLIFY_M)))
    used = sorted({e.a for e in out} | {e.b for e in out})
    remap = {o: i for i, o in enumerate(used)}
    return TrackGraph(g.nodes[used], [Edge(remap[e.a], remap[e.b], e.pts) for e in out])


def track_graph(tris: np.ndarray, res: float = RES, prune_m: float = PRUNE_M) -> TrackGraph:
    from scipy.ndimage import binary_closing
    img, x0, ytop = _raster(np.asarray(tris, np.float64), res)
    img = binary_closing(img, structure=np.ones((3, 3)), iterations=max(1, int(round(2.0 / res)))).astype(np.uint8)
    return _finish(_trace(_thin(img), x0, ytop, res), prune_m)


# ----------------------------------------------------------------------------------------------------------- routes

def _nearest_on_edges(g: TrackGraph, p: np.ndarray) -> tuple[int, int, np.ndarray, float]:
    """(edge, segment index, point, distance) of the track point closest to p."""
    best = (-1, -1, None, np.inf)
    for ei, e in enumerate(g.edges):
        a, b = e.pts[:-1], e.pts[1:]
        ab = b - a
        L2 = np.maximum((ab ** 2).sum(1), 1e-12)
        t = np.clip(((p - a) * ab).sum(1) / L2, 0, 1)
        q = a + ab * t[:, None]
        d = np.hypot(*(q - p).T)
        k = int(np.argmin(d))
        if d[k] < best[3]:
            best = (ei, k, q[k], float(d[k]))
    return best


def with_stations(g: TrackGraph, stations: dict[str, Station]) -> tuple[TrackGraph, dict[str, int]]:
    """The graph with every placed station as a node: on the track (the edge split there) when within SPUR_MIN_M of
    it, else joined by a straight spur from the nearest track point."""
    nodes = [n for n in g.nodes]
    edges = [Edge(e.a, e.b, e.pts.copy()) for e in g.edges]
    node_of: dict[str, int] = {}
    for key in sorted(stations):
        s = stations[key]
        if s.xy is None:
            continue
        p = np.array(s.xy, float)
        ei, k, q, d = _nearest_on_edges(TrackGraph(np.array(nodes), edges), p)
        e = edges[ei]
        here = len(nodes)
        nodes.append(q)
        first = np.vstack([e.pts[:k + 1], q])
        second = np.vstack([q, e.pts[k + 1:]])
        edges[ei] = Edge(e.a, here, first)
        edges.append(Edge(here, e.b, second))
        if d > SPUR_MIN_M:
            nodes.append(p)
            edges.append(Edge(here, len(nodes) - 1, np.vstack([q, p])))
            here = len(nodes) - 1
        node_of[key] = here
    return TrackGraph(np.array(nodes), edges), node_of


def _dijkstra(g: TrackGraph, src: int, dst: int) -> list[tuple[int, bool]]:
    import heapq
    adj: dict[int, list[tuple[int, int, bool, float]]] = {}
    for i, e in enumerate(g.edges):
        L = float(np.linalg.norm(np.diff(e.pts, axis=0), axis=1).sum())
        adj.setdefault(e.a, []).append((e.b, i, True, L))
        adj.setdefault(e.b, []).append((e.a, i, False, L))
    dist, prev = {src: 0.0}, {}
    q = [(0.0, src)]
    while q:
        d, u = heapq.heappop(q)
        if u == dst:
            break
        if d > dist.get(u, np.inf):
            continue
        for v, ei, fwd, L in adj.get(u, []):
            nd = d + L
            if nd < dist.get(v, np.inf):
                dist[v], prev[v] = nd, (u, ei, fwd)
                heapq.heappush(q, (nd, v))
    if dst not in dist:
        raise ValueError(f"no track between nodes {src} and {dst}")
    out, v = [], dst
    while v != src:
        u, ei, fwd = prev[v]
        out.append((ei, fwd))
        v = u
    return out[::-1]


def route_edges(g: TrackGraph, node_of: dict[str, int], line: Line) -> list[tuple[int, bool]]:
    """The (edge, forward) sequence the line runs over, station to station (and back to the first when looped)."""
    stops = [node_of[s] for s in line.stations if s in node_of]
    if line.looped:
        stops.append(stops[0])
    out: list[tuple[int, bool]] = []
    for u, v in zip(stops, stops[1:]):
        if u != v:
            out += _dijkstra(g, u, v)
    return out


def edges_polyline(g: TrackGraph, seq: list[tuple[int, bool]]) -> np.ndarray:
    parts = []
    for ei, fwd in seq:
        p = g.edges[ei].pts if fwd else g.edges[ei].pts[::-1]
        parts.append(p if not parts else p[1:])
    return np.vstack(parts) if parts else np.zeros((0, 2))


def line_polyline(g: TrackGraph, line: Line, stations: dict[str, Station]) -> np.ndarray:
    gs, node_of = with_stations(g, {k: v for k, v in stations.items() if k in line.stations})
    return edges_polyline(gs, route_edges(gs, node_of, line))
