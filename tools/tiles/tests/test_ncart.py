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
    # Every marked station is on one of its lines, or joined to it by a connector.
    g = ncart.track_graph(ncart.metro_tris(METRO_GLB))
    st = ncart.load_stations(STATIONS)
    lines = ncart.load_lines(FIXTURE)
    gs, node_of = ncart.with_stations(g, st)
    polys = {l.number: ncart.edges_polyline(gs, ncart.route_edges(gs, node_of, l)) for l in lines}
    ends = [c[-1] for c, _ in ncart.connectors(polys, lines, st)]
    for key, s in st.items():
        if not s.marked:
            continue
        p = np.array(s.xy)
        on = min(np.linalg.norm(polys[l.number] - p, axis=1).min() for l in lines if key in l.stations)
        joined = any(np.linalg.norm(e - p) < 0.5 for e in ends)
        print(key, round(float(on), 1), "connector" if joined else "")
        assert on <= ncart.SPUR_MIN_M + 0.01 or joined, key


# ----------------------------------------------------------------------------------------------- shared-track slots

def mk(n, *stations, looped=False):
    return ncart.Line(n, "ABCDE"[n - 1], (255, 255, 255), tuple(stations), looped)


def offset_lines(g, lines, st, spacing=5.0, ease=30.0):
    gs, node_of = ncart.with_stations(g, st)
    routes = {l.number: ncart.route_edges(gs, node_of, l) for l in lines}
    sl = ncart.slots(routes)
    return {n: ncart.offset_polyline(gs, r, sl, spacing, ease, n) for n, r in routes.items()}


def dist_to(poly, pts):
    """Distance from each of pts to the polyline poly."""
    a, b = poly[:-1], poly[1:]
    ab = b - a
    L2 = np.maximum((ab ** 2).sum(1), 1e-12)
    out = []
    for p in pts:
        t = np.clip(((p - a) * ab).sum(1) / L2, 0, 1)
        out.append(np.hypot(*(a + ab * t[:, None] - p).T).min())
    return np.array(out)


def test_two_lines_on_one_edge_are_parallel_at_spacing():
    g = ncart.track_graph(tracks(((0, 0), (400, 0))))
    st = places(S=(10, 0), T=(390, 0))
    o = offset_lines(g, [mk(1, "S", "T"), mk(2, "S", "T")], st)
    mid = o[1][(o[1][:, 0] > 100) & (o[1][:, 0] < 300)]
    assert np.allclose(dist_to(o[2], mid), 5.0, rtol=0.01)


def test_slot_frame_ignores_travel_direction():
    # Line 2 runs the other way: it must still sit on the other side of line 1, not on top of it.
    g = ncart.track_graph(tracks(((0, 0), (400, 0))))
    st = places(S=(10, 0), T=(390, 0))
    o = offset_lines(g, [mk(1, "S", "T"), mk(2, "T", "S")], st)
    mid = o[1][(o[1][:, 0] > 100) & (o[1][:, 0] < 300)]
    assert np.allclose(dist_to(o[2], mid), 5.0, rtol=0.01)


def flipped_chain():
    # Nodes 0 -- 1 -- 2 along y = 0; edge 1 is stored backwards (2 -> 1), as the skeleton trace often does at a node.
    nodes = np.array([[0.0, 0.0], [200.0, 0.0], [400.0, 0.0]])
    e0 = ncart.Edge(0, 1, np.array([[0.0, 0.0], [100.0, 0.0], [200.0, 0.0]]))
    e1 = ncart.Edge(2, 1, np.array([[400.0, 0.0], [300.0, 0.0], [200.0, 0.0]]))
    return ncart.TrackGraph(nodes, [e0, e1])


def test_lines_keep_their_sides_through_a_reversed_edge():
    g = flipped_chain()
    routes = {1: [(0, True), (1, False)], 2: [(0, True), (1, False)]}
    sl = ncart.slots(routes)
    o = {n: ncart.offset_polyline(g, r, sl, 5.0, 30.0, n) for n, r in routes.items()}
    side = np.sign(o[1][:, 1] - np.interp(o[1][:, 0], o[2][:, 0], o[2][:, 1]))
    assert np.all(side[5:-5] == side[len(side) // 2])            # never cross


def test_opposite_running_lines_are_aligned_before_ordering():
    # Line 2 is listed the other way round; on both edges it must still sit on the same side of line 1.
    g = flipped_chain()
    routes = {1: [(0, True), (1, False)], 2: [(1, True), (0, False)]}
    sl = ncart.slots(routes)
    o = {n: ncart.offset_polyline(g, r, sl, 5.0, 30.0, n) for n, r in routes.items()}
    o2 = o[2][::-1]
    side = np.sign(o[1][:, 1] - np.interp(o[1][:, 0], o2[:, 0], o2[:, 1]))
    assert np.all(side[5:-5] == side[len(side) // 2])


def test_a_spike_at_a_node_is_smoothed_out():
    # The skeleton node of a wide junction often sits off the track centre: the joined route kinks up to it and back.
    nodes = np.array([[0.0, 0.0], [200.0, 6.0], [400.0, 0.0]])
    e0 = ncart.Edge(0, 1, np.array([[0.0, 0.0], [196.0, 0.0], [200.0, 6.0]]))
    e1 = ncart.Edge(1, 2, np.array([[200.0, 6.0], [204.0, 0.0], [400.0, 0.0]]))
    g = ncart.TrackGraph(nodes, [e0, e1])
    routes = {1: [(0, True), (1, True)]}
    p = ncart.offset_polyline(g, routes[1], ncart.slots(routes), 5.0, 30.0, 1)
    assert np.abs(p[:, 1]).max() < 1.5
    assert np.linalg.norm(p[0] - (0, 0)) < 0.5 and np.linalg.norm(p[-1] - (400, 0)) < 0.5   # ends stay at stations


def test_three_share_then_one_leaves():
    # Lines 1, 2, 3 share x 0..200; line 2 (the middle one) turns north at x = 200, 1 and 3 run on to x = 400.
    g = ncart.track_graph(tracks(((0, 0), (400, 0)), ((200, -4), (200, 200))))
    st = places(S=(10, 0), T=(390, 0), N=(200, 190))
    o = offset_lines(g, [mk(1, "S", "T"), mk(2, "S", "N"), mk(3, "S", "T")], st, spacing=5.0, ease=30.0)
    share = o[1][(o[1][:, 0] > 50) & (o[1][:, 0] < 150)]
    assert np.allclose(dist_to(o[3], share), 10.0, rtol=0.02)          # outer slots: 2 x spacing apart
    after = o[1][(o[1][:, 0] > 260) & (o[1][:, 0] < 360)]
    assert np.allclose(dist_to(o[3], after), 5.0, rtol=0.02)           # eased to +-spacing/2
    for n in (1, 3):
        step = np.hypot(*np.diff(o[n], axis=0).T)
        side = np.diff(o[n][:, 1])
        assert np.all(np.abs(side) <= np.maximum(step, 1e-9) * 0.5)    # no sideways jump: a smooth ease
    assert np.all(np.sign(o[1][(o[1][:, 0] > 20) & (o[1][:, 0] < 380), 1]) == np.sign(o[1][len(o[1]) // 2, 1]))  # never crosses


# ----------------------------------------------------------------------------------------- stubs, spurs, connectors

def test_through_line_skips_a_short_stub_and_gets_a_connector():
    # Track x 0..400; a 60 m stub north at x = 200 with the station at its end. Line 1 passes through the station:
    # it must not run up the stub and back; the station is joined by one connector instead.
    g = ncart.track_graph(tracks(((0, 0), (400, 0)), ((200, -4), (200, 60))))
    st = places(S=(10, 0), M=(200, 58), T=(390, 0))
    gs, node_of = ncart.with_stations(g, st)
    r = ncart.route_edges(gs, node_of, mk(1, "S", "M", "T"))
    p = ncart.edges_polyline(gs, r)
    assert p[:, 1].max() < 2                                     # stayed on the main track
    cons = ncart.connectors({1: p}, [mk(1, "S", "M", "T")], st)
    assert len(cons) == 1 and cons[0][1] == 1
    c = cons[0][0]
    assert np.linalg.norm(c[-1] - (200, 58)) < 0.5 and np.linalg.norm(c[0] - (200, 0)) < 2


def test_terminal_station_on_a_stub_is_reached():
    g = ncart.track_graph(tracks(((0, 0), (400, 0)), ((200, -4), (200, 60))))
    st = places(S=(10, 0), M=(200, 58))
    p = ncart.line_polyline(g, mk(1, "S", "M"), st)
    assert np.linalg.norm(p[-1] - (200, 58)) < ncart.SPUR_MIN_M and p[:, 1].max() > 50


def test_long_reversal_is_kept():
    # A 400 m branch to a through station and back is real service, not a detour, even when the branch is many
    # short edges (side stubs every 50 m split it, like the real mesh's skeleton).
    side = [((396, y), (440, y)) for y in range(50, 400, 50)]
    g = ncart.track_graph(tracks(((0, 0), (800, 0)), ((400, -4), (400, 400)), *side))
    st = places(S=(10, 0), W=(400, 390), T=(790, 0))
    p = ncart.line_polyline(g, mk(1, "S", "W", "T"), st)
    assert p[:, 1].max() > 380


# ----------------------------------------------------------------------------------------------------- metro tiles

from nmtiles.render import LevelGrid  # noqa: E402

GRID = LevelGrid(1.0, 0.0, 1024.0, 2, 2, 512)   # tile (ix, iy): x in [512 ix, +512), y in (1024 - 512 (iy+1), 1024 - 512 iy]


def rgba(img):
    return np.asarray(img).astype(int)


def test_metro_tile_is_coloured_and_transparent_elsewhere():
    paths = [(np.array([[50.0, 900.0], [450.0, 900.0]]), (229, 25, 25), "line")]
    a = rgba(ncart.render_metro_tile(paths, GRID, 0, 0))
    col = a[1024 - 900 - 4:1024 - 900 + 5, 250]
    pure = [p for p in col if p[3] == 255 and abs(p[0] - 229) <= 3 and abs(p[1] - 25) <= 3 and abs(p[2] - 25) <= 3]
    assert pure                                                  # the core keeps the line colour
    centre = col[np.argmax(col[:, 1])]
    assert centre[3] == 255 and centre[1] > 25 + 30 and centre[0] >= 229    # a paler centre: the neon-tube highlight
    assert a[1024 - 900 - 40, 250, 3] == 0 and a[1024 - 900, 480, 3] == 0
    assert ncart.render_metro_tile(paths, GRID, 1, 1) is None


def test_metro_glow_is_soft():
    paths = [(np.array([[50.0, 900.0], [450.0, 900.0]]), (18, 228, 255), "line")]
    a = rgba(ncart.render_metro_tile(paths, GRID, 0, 0))[:, 250, 3]
    row = 1024 - 900
    edge = row + int(ncart.LINE_PX / 2) + 1
    fall = a[edge:edge + 14]
    assert 0 < fall[0] < 255 and np.all(np.diff(fall) <= 0) and fall[-1] < 8
    rgb = rgba(ncart.render_metro_tile(paths, GRID, 0, 0))[edge + 3, 250, :3]
    assert abs(rgb[2] - 255) <= 12 and rgb[0] < 60          # the glow keeps the line colour: no dark fringe


def test_side_by_side_lines_keep_a_dark_gap():
    # Glow sits under the casing, so the gap between two lines on shared track stays dark instead of mixing colours.
    y = 900.0
    paths = [(np.array([[50.0, y], [450.0, y]]), (229, 25, 25), "line"),
             (np.array([[50.0, y - ncart.SPACING_PX], [450.0, y - ncart.SPACING_PX]]), (18, 228, 255), "line")]
    a = rgba(ncart.render_metro_tile(paths, GRID, 0, 0))
    gap = a[int(1024 - y + ncart.SPACING_PX / 2), 250]
    assert gap[3] > 200 and gap[:3].max() < 50


def test_connector_takes_its_line_colour():
    g = ncart.track_graph(tracks(((0, 0), (400, 0))))
    st = places(S=(10, 0), M=(200, 40), T=(390, 0))
    cyan = ncart.Line(3, "C", (18, 228, 255), ("S", "M", "T"), False)
    net = ncart.Network.build(g, [cyan], st)
    cons = [rgb for pts, rgb, kind in ncart.level_paths(net, 1.0) if kind == "connector"]
    assert cons == [(18, 228, 255)]


def test_metro_tiles_stitch():
    paths = [(np.array([[400.0, 700.0], [640.0, 760.0]]), (250, 131, 0), "line"),
             (np.array([[480.0, 650.0], [560.0, 650.0]]), (255, 255, 255), "connector")]
    left, right = rgba(ncart.render_metro_tile(paths, GRID, 0, 0)), rgba(ncart.render_metro_tile(paths, GRID, 1, 0))
    big = LevelGrid(1.0, 0.0, 1024.0, 1, 1, 1024)
    whole = rgba(ncart.render_metro_tile(paths, big, 0, 0))[:512]
    assert np.abs(np.hstack([left, right]) - whole).max() <= 2


def test_level_paths_space_lines_by_pixels():
    g = ncart.track_graph(tracks(((0, 0), (400, 0))))
    st = places(S=(10, 0), T=(390, 0))
    net = ncart.Network.build(g, [mk(1, "S", "T"), mk(2, "S", "T")], st)
    for mpp in (1.0, 4.0):
        p = {rgb: pts for pts, rgb, kind in ncart.level_paths(net, mpp) if kind == "line"}
        assert len(p) == 1 or len(p) == 2
        lines = [pts for pts, rgb, kind in ncart.level_paths(net, mpp) if kind == "line"]
        mid = lines[0][(lines[0][:, 0] > 100) & (lines[0][:, 0] < 300)]
        assert np.allclose(dist_to(lines[1], mid), ncart.SPACING_PX * mpp, rtol=0.02)


def test_engine_encoding_undoes_the_games_gamma():
    # The game reads the metro texture as linear colour and gamma-encodes it for the screen. Baking linear light
    # makes the on-screen colour the intended sRGB colour: (250, 131, 0) would otherwise show as about (253, 190, 0).
    from PIL import Image
    src = np.zeros((2, 3, 4), np.uint8)
    src[0, 0] = (250, 131, 0, 255)
    src[0, 1] = (8, 6, 16, 235)
    src[0, 2] = (27, 233, 32, 128)
    enc = np.asarray(ncart.to_engine_linear(Image.fromarray(src, "RGBA"))).astype(float)
    assert np.array_equal(enc[..., 3], src[..., 3])                     # coverage is untouched
    c = enc[..., :3] / 255.0
    shown = np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055) * 255.0
    assert np.abs(shown[0] - src[0, :, :3]).max() <= 6                  # the game's encode lands on the intended colour
    assert enc[0, 0, 1] < 70                                             # 131 is stored as linear light (~58)
