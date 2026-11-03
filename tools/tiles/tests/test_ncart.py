from pathlib import Path

import numpy as np
import pytest

from nmtiles import ncart

HERE = Path(__file__).resolve().parent
FIXTURE = HERE.parent / "data" / "ncart_lines.json"
STATIONS = HERE.parent / "data" / "ncart_stations.json"


def test_load_lines_reads_number_colour_order_loop():
    lines = ncart.load_lines(FIXTURE)
    assert [l.number for l in lines] == [1, 2, 3, 4, 5]
    a = lines[0]
    assert a.letter == "A" and a.rgb == (229, 25, 25) and not a.looped
    assert a.stations[0] == "ARASAKA_WATERFRONT" and len(a.stations) == 9
    d = lines[3]
    assert d.letter == "D" and d.looped and d.rgb == (27, 233, 32)
    assert lines[4].rgb == (250, 131, 0)


def test_every_line_station_has_a_place():
    st = ncart.load_stations(STATIONS)
    for line in ncart.load_lines(FIXTURE):
        for s in line.stations:
            assert s in st, (line.letter, s)
    assert sum(1 for s in st.values() if s.marked) == 15


# ----------------------------------------------------------------------------------------------- track graph, routes

def ribbon(p0, p1, w=8.0):
    """Two triangles: a w-metre-wide straight track from p0 to p1."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    d = (p1 - p0) / np.linalg.norm(p1 - p0)
    n = np.array([-d[1], d[0]]) * w / 2
    a, b, c, e = p0 + n, p1 + n, p1 - n, p0 - n
    return np.array([[a, b, c], [a, c, e]], np.float32)


def tracks(*segs):
    return np.concatenate([ribbon(*s) for s in segs])


def line(*stations, looped=False):
    return ncart.Line(1, "A", (229, 25, 25), tuple(stations), looped)


def places(**xy):
    return {k: ncart.Station(k, k, v, True) for k, v in xy.items()}


def polyline_length(p):
    return float(np.linalg.norm(np.diff(p, axis=0), axis=1).sum())


def test_graph_of_a_cross_has_one_junction_four_edges():
    g = ncart.track_graph(tracks(((0, 100), (200, 100)), ((100, 0), (100, 200))))
    deg = np.bincount(np.array([[e.a, e.b] for e in g.edges]).ravel(), minlength=len(g.nodes))
    assert len(g.edges) == 4 and (deg == 4).sum() == 1 and (deg == 1).sum() == 4
    j = g.nodes[np.argmax(deg)]
    assert np.linalg.norm(j - (100, 100)) < 3


def test_route_follows_track_between_stations():
    g = ncart.track_graph(tracks(((0, 0), (300, 0)), ((300, -4), (300, 200))))
    pts = ncart.line_polyline(g, line("S", "T"), places(S=(10, 0), T=(300, 190)))
    want = 290 + 190
    assert abs(polyline_length(pts) - want) / want < 0.02
    assert np.linalg.norm(pts[0] - (10, 0)) < 2 and np.linalg.norm(pts[-1] - (300, 190)) < 2


def test_route_reaches_off_mesh_station():
    # The station is 40 m past the end of the track (like Pacifica - Stadium past the mesh): the line runs on.
    g = ncart.track_graph(tracks(((0, 0), (300, 0))))
    pts = ncart.line_polyline(g, line("S", "T"), places(S=(20, 0), T=(340, 0)))
    assert np.linalg.norm(pts[-1] - (340, 0)) < 1
    assert polyline_length(pts) == pytest.approx(320, rel=0.02)


def test_loop_closes():
    sq = ((0, 0), (200, 0)), ((200, -4), (200, 204)), ((204, 200), (-4, 200)), ((0, 204), (0, -4))
    g = ncart.track_graph(tracks(*sq))
    pts = ncart.line_polyline(g, line("S", "T", "U", looped=True), places(S=(100, 0), T=(200, 100), U=(100, 200)))
    assert np.linalg.norm(pts[0] - pts[-1]) < 2
    assert polyline_length(pts) == pytest.approx(800, rel=0.03)


METRO_GLB = HERE.parent / "build" / "meshes" / "base" / "entities" / "cameras" / "3dmap" / "3dmap_metro.glb"


@pytest.mark.skipif(not METRO_GLB.exists(), reason="needs the exported 3D-map metro mesh (a tile build)")
def test_real_mesh_routes_every_line_through_every_marker():
    g = ncart.track_graph(ncart.metro_tris(METRO_GLB))
    st = ncart.load_stations(STATIONS)
    for ln in ncart.load_lines(FIXTURE):
        pts = ncart.line_polyline(g, ln, st)
        for s in ln.stations:
            if st[s].xy is None:
                continue
            d = np.linalg.norm(pts - np.array(st[s].xy), axis=1).min()
            print(ln.letter, s, round(float(d), 1))
            assert d <= ncart.SPUR_MIN_M + 0.01, (ln.letter, s, d)
