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


BACKTRACK_M = 200.0   # an out-and-back shorter than this (into a stub or a spur) is dropped from a through line
CONNECT_M = SPUR_MIN_M  # a marker farther than this from its lines gets a connector


def _edge_len(g: TrackGraph, ei: int) -> float:
    return float(np.hypot(*np.diff(g.edges[ei].pts, axis=0).T).sum())


def _drop_short_backtracks(g: TrackGraph, seq: list[tuple[int, bool]]) -> list[tuple[int, bool]]:
    """Remove out-and-back runs whose one-way length is under BACKTRACK_M. Each run is measured whole: from a
    turnaround (an edge followed by itself reversed) outward while the sequence mirrors."""
    seq = list(seq)
    i = 0
    while i < len(seq) - 1:
        if seq[i][0] == seq[i + 1][0] and seq[i][1] != seq[i + 1][1]:
            m = 1
            while i - m >= 0 and i + 1 + m < len(seq) and seq[i - m][0] == seq[i + 1 + m][0] and seq[i - m][1] != seq[i + 1 + m][1]:
                m += 1
            if sum(_edge_len(g, e) for e, _ in seq[i - m + 1:i + 1]) < BACKTRACK_M:
                del seq[i - m + 1:i + 1 + m]
                i = max(0, i - m)
                continue
            i += m
        i += 1
    return seq


def route_edges(g: TrackGraph, node_of: dict[str, int], line: Line) -> list[tuple[int, bool]]:
    """The (edge, forward) sequence the line runs over, station to station (and back to the first when looped).
    Short out-and-back detours to a through station (a stub or a spur) are dropped: connectors() joins such a
    station's marker to the line instead."""
    stops = [node_of[s] for s in line.stations if s in node_of]
    if line.looped:
        stops.append(stops[0])
    out: list[tuple[int, bool]] = []
    for u, v in zip(stops, stops[1:]):
        if u != v:
            out += _dijkstra(g, u, v)
    return _drop_short_backtracks(g, out)


def connectors(polys: dict[int, np.ndarray], lines: list[Line],
               stations: dict[str, Station]) -> list[tuple[np.ndarray, int]]:
    """A straight connector (2 points, line -> marker) for every marked station farther than CONNECT_M from all the
    lines that serve it, from the nearest point of those lines, with the number of that line (its colour)."""
    out = []
    for key, s in sorted(stations.items()):
        if not s.marked or s.xy is None:
            continue
        p = np.array(s.xy, float)
        best, at, by = np.inf, None, None
        for l in lines:
            if key not in l.stations or l.number not in polys or len(polys[l.number]) < 2:
                continue
            q = polys[l.number]
            a, b = q[:-1], q[1:]
            ab = b - a
            t = np.clip(((p - a) * ab).sum(1) / np.maximum((ab ** 2).sum(1), 1e-12), 0, 1)
            c = a + ab * t[:, None]
            d = np.hypot(*(c - p).T)
            k = int(np.argmin(d))
            if d[k] < best:
                best, at, by = float(d[k]), c[k], l
        if at is not None and best > CONNECT_M:
            out.append((np.vstack([at, p]), by.number))
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


# ------------------------------------------------------------------------------------------------ shared-track slots

STEP_M = 1.0          # resampling step of an offset polyline


def _travel_signs(routes: dict[int, list[tuple[int, bool]]]) -> dict[int, int]:
    """+1 or -1 per line: whether to read its route as listed or reversed, so that lines sharing track run the same
    way. Lines are taken in number order; each one is reversed when it runs against the lines already placed on more
    of its shared edges than with them."""
    sign: dict[int, int] = {}
    placed: dict[int, list[bool]] = {}          # edge -> effective forward flags of placed lines
    for n in sorted(routes):
        agree = against = 0
        for ei, fwd in routes[n]:
            for f in placed.get(ei, ()):
                if f == fwd:
                    agree += 1
                else:
                    against += 1
        sign[n] = -1 if against > agree else 1
        for ei, fwd in routes[n]:
            placed.setdefault(ei, []).append(fwd if sign[n] > 0 else not fwd)
    return sign


PART_M = 15.0      # how far along a parting edge its direction is measured
WALK_MAX = 400     # edges walked along a shared run before giving up


def _oriented(g: TrackGraph, ei: int, fwd: bool) -> np.ndarray:
    return g.edges[ei].pts if fwd else g.edges[ei].pts[::-1]


def _walk(route: list[tuple[int, bool]], j: int, along: bool):
    """Oriented edges of a route after step j, travelling the way edge route[j] runs a -> b (along) or b -> a."""
    ahead = route[j][1] == along
    k = j + (1 if ahead else -1)
    while 0 <= k < len(route):
        ei, f = route[k]
        yield ei, (f if ahead else not f)
        k += 1 if ahead else -1


def _away(q: np.ndarray, d: float) -> np.ndarray:
    seg = np.hypot(*np.diff(q, axis=0).T)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    t = min(d, s[-1])
    v = np.array([np.interp(t, s, q[:, 0]), np.interp(t, s, q[:, 1])]) - q[0]
    return v / max(float(np.hypot(*v)), 1e-9)


def _parting_side(g: TrackGraph, routes, ei: int, n: int, jn: int, m: int, jm: int, first_along: bool = True) -> int:
    """+1 when line n should ride left of line m on edge ei (left of a -> b), -1 when right, 0 when the shape says
    nothing. Both lines are walked edge by edge while they share track, first one way (past b when first_along, else
    past a) and then the other; at the node where they part, the one whose next edge leaves more to the left of the
    shared direction is left. The walk is not limited in length, and every edge of a run must look the same way
    first (the caller passes the bundle's travel direction): when the two ends of a run disagree, a crossing is
    unavoidable, and looking the same way puts it once, at a junction, instead of flipping edge by edge."""
    for along in (first_along, not first_along):
        last = (ei, along)
        wn, wm = _walk(routes[n], jn, along), _walk(routes[m], jm, along)
        for _ in range(WALK_MAX):
            en, em = next(wn, None), next(wm, None)
            if en is None or em is None:
                break
            if en == em:
                last = en
                continue
            q = _oriented(g, *last)
            t = q[-1] - q[max(0, len(q) - 4)]
            t = t / max(float(np.hypot(*t)), 1e-9)
            dn, dm = _away(_oriented(g, *en), PART_M), _away(_oriented(g, *em), PART_M)
            an = float(np.arctan2(t[0] * dn[1] - t[1] * dn[0], t @ dn))
            am = float(np.arctan2(t[0] * dm[1] - t[1] * dm[0], t @ dm))
            if abs(an - am) > 1e-3:
                side = 1 if an > am else -1        # more counter-clockwise = further left of the walk direction
                return side if along else -side    # walking b -> a, the walk's left is the edge's right
            break
    return 0


def slots(routes: dict[int, list[tuple[int, bool]]], g: TrackGraph | None = None) -> dict[int, dict[int, float]]:
    """Per edge, per line number: its slot across the track, measured to the left of the edge's canonical direction
    (node a -> b), centred: i - (n - 1) / 2. With the graph, lines are ordered geometrically, the way transit maps do:
    a line that parts from another to the left (ahead, or behind) rides on its left, so lines part and join without
    crossing (_parting_side). Lines that never part are ordered by number in the travel direction of the lowest line
    there (after _travel_signs has aligned the lines): a travel frame rather than each edge's stored direction keeps
    every line on its side where a chain of edges flips direction at a node, so lines sharing track never braid."""
    from functools import cmp_to_key
    sign = _travel_signs(routes)
    on: dict[int, dict[int, bool]] = {}                  # edge -> line -> runs along a -> b (after alignment)
    first: dict[int, dict[int, int]] = {}                # edge -> line -> route step of its first visit
    for n, r in routes.items():
        for j, (ei, fwd) in enumerate(r):
            on.setdefault(ei, {})[n] = fwd if sign[n] > 0 else not fwd
            first.setdefault(ei, {}).setdefault(n, j)
    out: dict[int, dict[int, float]] = {}
    for ei, ls in on.items():
        ns = sorted(ls)
        frame = 1 if ls[ns[0]] else -1

        def cmp(n: int, m: int) -> int:     # positive: n sorts later, i.e. further left
            side = _parting_side(g, routes, ei, n, first[ei][n], m, first[ei][m], frame > 0) if g is not None else 0
            if side:
                return side
            return (frame * n > frame * m) - (frame * n < frame * m)
        order = sorted(ns, key=cmp_to_key(cmp))
        out[ei] = {n: i - (len(ns) - 1) / 2 for i, n in enumerate(order)}
    return out


def _resample(p: np.ndarray, step: float) -> np.ndarray:
    seg = np.hypot(*np.diff(p, axis=0).T)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    if s[-1] <= 0:
        return p[:1]
    n = max(1, int(np.ceil(s[-1] / step)))
    t = np.linspace(0, s[-1], n + 1)
    return np.stack([np.interp(t, s, p[:, 0]), np.interp(t, s, p[:, 1])], 1)


def _left_normals(p: np.ndarray) -> np.ndarray:
    d = np.gradient(p, axis=0) if len(p) > 1 else np.array([[1.0, 0.0]])
    d /= np.maximum(np.hypot(*d.T), 1e-12)[:, None]
    return np.stack([-d[:, 1], d[:, 0]], 1)


ROUTE_SMOOTH_M = 16.0     # half-width of the box filter run twice over a joined route (removes kinks at nodes)


def _smooth_route(p: np.ndarray, k: int) -> np.ndarray:
    """Two passes of a centred box filter of width 2k + 1 over an evenly resampled polyline. The ends are padded by
    point reflection, so they stay exactly in place and a straight run stays straight."""
    if k < 1 or len(p) < 3:
        return p
    k = min(k, len(p) - 1)
    for _ in range(2):
        pad = np.vstack([2 * p[0] - p[k:0:-1], p, 2 * p[-1] - p[-2:-k - 2:-1]])
        c = np.cumsum(np.vstack([np.zeros((1, 2)), pad]), axis=0)
        p = (c[2 * k + 1:] - c[: len(p)]) / (2 * k + 1)
    return p


SIZE_EASE = 3     # where a bundle grows or shrinks, the one-sided ease is this many ease lengths long (no notch)


def _eased_offsets(runs: list[tuple[int, float, int]], k: int) -> np.ndarray:
    """Per-sample sideways offset from runs of (samples, offset, lines on that edge), with a smoothstep of k samples
    at every change. The ease is one-sided where the bundle size changes: a line leaving a bundle keeps its bundle
    offset through the junction and eases on the smaller side, after the tracks have parted; a line joining eases in
    before the junction. A centred ease would pull every line of a splitting bundle onto the junction point (a pinch).
    Equal sizes (a reordering) ease centred."""
    merged: list[tuple[int, float, int]] = []
    for m, v, n in runs:                  # consecutive edges with the same offset and bundle are one stretch
        if merged and merged[-1][1] == v and merged[-1][2] == n:
            merged[-1] = (merged[-1][0] + m, v, n)
        else:
            merged.append((m, v, n))
    runs = merged
    o = np.concatenate([np.full(m, v) for m, v, _ in runs]) if runs else np.zeros(0)
    if k < 1:
        return o
    start = 0
    for i in range(1, len(runs)):
        (m1, v1, n1), (m2, v2, n2) = runs[i - 1], runs[i]
        start += m1
        if v1 == v2:
            continue
        if n2 < n1:
            w0, w1 = start, start + min(SIZE_EASE * k, m2)
        elif n2 > n1:
            w0, w1 = start - min(SIZE_EASE * k, m1), start
        else:
            w0, w1 = start - min(k // 2, m1), start + min(k // 2, m2)
        w0, w1 = max(w0, 0), min(w1, len(o))
        if w1 - w0 < 2:
            continue
        a = o[w0 - 1] if w0 > 0 else v1
        t = np.linspace(0.0, 1.0, w1 - w0)
        o[w0:w1] = a + (v2 - a) * (t * t * (3 - 2 * t))
        o[w1:start + m2] = v2
    return o


def offset_polyline(g: TrackGraph, route: list[tuple[int, bool]], sl: dict[int, dict[int, float]],
                    spacing_m: float, ease_m: float, number: int) -> np.ndarray:
    """The line's polyline shifted sideways by its slot x spacing_m on every edge. The shift is a scalar in the
    line's own left frame (an edge run backwards flips the sign, so every line on an edge uses the edge's frame) and
    eases over ease_m of arc length where it changes (_eased_offsets), so the line eases in and out where it joins or
    leaves others. The joined centre line is smoothed first (ROUTE_SMOOTH_M): each edge was smoothed alone with its
    ends pinned to the skeleton nodes, which sit off the track centre at wide junctions and would otherwise spike."""
    pts, runs = [], []
    for ei, fwd in route:
        p = _resample(g.edges[ei].pts if fwd else g.edges[ei].pts[::-1], STEP_M)
        if pts:
            p = p[1:]
        pts.append(p)
        runs.append((len(p), sl[ei][number] * spacing_m * (1.0 if fwd else -1.0), len(sl[ei])))
    if not pts:
        return np.zeros((0, 2))
    p = _smooth_route(np.vstack(pts), int(round(ROUTE_SMOOTH_M / STEP_M)))
    o = _eased_offsets(runs, max(1, int(round(ease_m / STEP_M))))
    return p + _left_normals(p) * o[:, None]


# ------------------------------------------------------------------------------------------------- the metro set

LINE_PX = 6.5                  # core line width at every level
SPACING_PX = 9.5               # centre-to-centre distance of side-by-side lines: a 3 px dark gap survives the in-game
                               # downscale (tiles show at 0.5-1x), so shared track reads as separate lines
CASING_PX = 1.75               # dark casing beyond each side of a line; between neighbours it fills the gap
CASING_RGB = (8, 6, 16)
CASING_ALPHA = 0.92
HILITE_PX = 1.25               # pale centre of the core: the neon-tube look of the NCART diagram
HILITE_MIX = 0.25              # share of white in the centre colour
EASE_PX = 24.0                 # ease length where lines join or split, in pixels (at least EASE_MIN_M)
EASE_MIN_M = 25.0
GLOW_PX = 18.0                 # width of the glow stroke before the blur; drawn under the casing, so it only shows
GLOW_SIGMA = 5.0               # outside a bundle and never tints a neighbour
GLOW_ALPHA = 0.4
CONNECTOR_PX = 2.5
RSS = 4                        # supersampling of the strokes
MARGIN_PX = int(GLOW_PX / 2 + 4 * GLOW_SIGMA) + 4


@dataclass
class Network:
    g: TrackGraph                          # with the stations as nodes
    lines: list[Line]
    routes: dict[int, list[tuple[int, bool]]]
    slots: dict[int, dict[int, float]]
    connectors: list[tuple[np.ndarray, int]]      # (2-point polyline, line number)

    @staticmethod
    def build(g: TrackGraph, lines: list[Line], stations: dict[str, Station]) -> "Network":
        gs, node_of = with_stations(g, stations)
        routes = {l.number: trim_spur_visits(gs, route_edges(gs, node_of, l)) for l in lines}
        centre = {n: edges_polyline(gs, r) for n, r in routes.items()}
        return Network(gs, lines, routes, slots(routes, gs), connectors(centre, lines, stations))

    @staticmethod
    def from_game(glb: Path, lines_json: Path = LINES, stations_json: Path = DATA) -> "Network":
        return Network.build(track_graph(metro_tris(glb)), load_lines(lines_json), load_stations(stations_json))


SPUR_TRIM_M = 40.0   # a visit into a dead-end edge shorter than this is left to a station connector


def trim_spur_visits(g: TrackGraph, route: list[tuple[int, bool]]) -> list[tuple[int, bool]]:
    """The route without out-and-back visits into short dead-end edges (a station a few metres off the track): drawn,
    such a visit curls the line into a hook. connectors() joins the station marker instead."""
    deg: dict[int, int] = {}
    for e in g.edges:
        deg[e.a] = deg.get(e.a, 0) + 1
        deg[e.b] = deg.get(e.b, 0) + 1
    r = list(route)
    i = 0
    while i + 1 < len(r):
        (ei, f), (ej, h) = r[i], r[i + 1]
        e = g.edges[ei]
        tip = e.b if f else e.a
        if ei == ej and f != h and deg.get(tip, 0) == 1 and _edge_len(g, ei) < SPUR_TRIM_M:
            del r[i:i + 2]
            i = max(i - 1, 0)
            continue
        i += 1
    return r


def split_at_reversals(route: list[tuple[int, bool]]) -> list[list[tuple[int, bool]]]:
    """A route cut where it turns back onto the edge it came along (an out-and-back to a terminus station). Drawn as
    one polyline, the U-turn would be smoothed into a hook; drawn as two, the halves overlap and simply end there."""
    parts, cur = [], []
    for step in route:
        if cur and step[0] == cur[-1][0] and step[1] != cur[-1][1]:
            parts.append(cur)
            cur = []
        cur.append(step)
    if cur:
        parts.append(cur)
    return parts


def level_paths(net: Network, mpp: float) -> list[tuple[np.ndarray, tuple[int, int, int], str]]:
    """What a level draws, bottom to top: connectors, then the lines offset by SPACING_PX at this level's mpp, each
    line as one polyline per stretch between reversals (split_at_reversals)."""
    spacing, ease = SPACING_PX * mpp, max(EASE_MIN_M, EASE_PX * mpp)
    rgb = {l.number: l.rgb for l in net.lines}
    out = [(c, rgb[n], "connector") for c, n in net.connectors]
    for l in net.lines:
        for part in split_at_reversals(net.routes[l.number]):
            out.append((offset_polyline(net.g, part, net.slots, spacing, ease, l.number), l.rgb, "line"))
    return out


def _premul(a: np.ndarray) -> np.ndarray:
    out = a.astype(np.float32)
    out[..., :3] *= out[..., 3:4] / 255.0
    return out


def _unpremul(p: np.ndarray) -> np.ndarray:
    a = p[..., 3:4]
    rgb = np.where(a > 0, p[..., :3] * 255.0 / np.maximum(a, 1e-6), 0)
    return np.clip(np.concatenate([rgb, a], -1) + 0.5, 0, 255).astype(np.uint8)


def _box_down(p: np.ndarray, k: int) -> np.ndarray:
    h, w = p.shape[0] // k, p.shape[1] // k
    return p[:h * k, :w * k].reshape(h, k, w, k, 4).mean(axis=(1, 3))


def to_engine_linear(img):
    """The metro tiles carry real colours (every other set is a white mask tinted at runtime). The game samples the
    texture as linear colour and gamma-encodes it for the screen, which lifts the colours to pastel and the dark
    casing to grey. Storing linear light (sRGB decode of each colour channel; coverage alpha unchanged) makes the
    on-screen colour the intended one."""
    from PIL import Image
    a = np.asarray(img.convert("RGBA")).astype(np.float64)
    c = a[..., :3] / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    out = np.concatenate([lin * 255.0, a[..., 3:4]], -1)
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGBA")


def render_metro_tile(paths: list[tuple[np.ndarray, tuple[int, int, int], str]], grid, ix: int, iy: int):
    """RGBA tile (colour in RGB, coverage in alpha) of the lines and connectors, or None when empty."""
    from PIL import Image, ImageDraw
    from scipy.ndimage import gaussian_filter
    mpp, tw, m = grid.mpp, grid.tile_world, MARGIN_PX
    x0 = grid.origin_x + ix * tw - m * mpp
    y1 = grid.origin_top - iy * tw + m * mpp
    span = tw + 2 * m * mpp
    hits = [p for p in paths if len(p[0]) > 1 and p[0][:, 0].max() >= x0 and p[0][:, 0].min() <= x0 + span
            and p[0][:, 1].max() >= y1 - span and p[0][:, 1].min() <= y1]
    if not hits:
        return None
    n = grid.tile + 2 * m
    W = n * RSS
    s = RSS / mpp
    layers = {k: Image.new("RGBA", (W, W)) for k in ("glow", "case", "core", "hi")}
    draws = {k: ImageDraw.Draw(v) for k, v in layers.items()}

    def stroke(d, xy, wpx, col):
        w = max(1, int(round(wpx * RSS)))
        d.line(xy, fill=col + (255,), width=w, joint="curve")
        r = w / 2                       # round caps
        for cx, cy in (xy[0], xy[-1]):
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (255,))

    for pts, rgb, kind in hits:
        xy = [((x - x0) * s, (y1 - y) * s) for x, y in pts]
        line = kind == "line"
        width = LINE_PX if line else CONNECTOR_PX
        hi = tuple(int(round(c + (255 - c) * HILITE_MIX)) for c in rgb)
        stroke(draws["glow"], xy, GLOW_PX if line else GLOW_PX / 2, rgb)
        stroke(draws["case"], xy, width + 2 * CASING_PX, CASING_RGB)
        stroke(draws["core"], xy, width, rgb)
        if line:
            stroke(draws["hi"], xy, HILITE_PX, hi)
    down = {k: _box_down(_premul(np.asarray(v)), RSS) for k, v in layers.items()}
    g = np.stack([gaussian_filter(down["glow"][..., c], GLOW_SIGMA, mode="constant") for c in range(4)], -1) * GLOW_ALPHA
    over = lambda top, under: top + under * (1.0 - top[..., 3:4] / 255.0)   # premultiplied "over"
    # Bottom to top: glow, casing, core, highlight. The casing covers the glow inside a bundle, so neighbouring
    # lines never tint each other and the gap between them stays dark.
    out = over(down["hi"], over(down["core"], over(down["case"] * CASING_ALPHA, g)))
    out = out[m:m + grid.tile, m:m + grid.tile]
    if out[..., 3].max() < 1.0:
        return None
    return Image.fromarray(_unpremul(out), "RGBA")
