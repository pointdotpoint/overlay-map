import numpy as np
import pytest

from nmtiles.buildings import Boxes
from nmtiles.glb import Mesh
from nmtiles.vector_budget import BudgetError, fit_level, worst_view
from nmtiles.vector_cells import Cell, VGrid, build_level, grid_for, order
from nmtiles.vector_config import VLevel
from nmtiles.buildings import box_corners
from nmtiles.vector_extract import Shape, Sources, block_features
from nmtiles.world import Transform

TF = Transform(1.0, -1.0, 0.0, 0.0)
LV = VLevel("T", 0.5, 1.0, 0.25, 50.0, 0.5, 0.0, 2.0, 0.0, 20.0)


def quad(x0, y0, x1, y1):
    pos = np.array([[x0, 0, -y0], [x1, 0, -y0], [x1, 0, -y1], [x0, 0, -y1]], float)
    return Mesh("q", pos, np.array([[0, 1, 2], [0, 2, 3]]))


def boxes(*rows):
    a = np.array(rows, float)
    return Boxes(a[:, 0], a[:, 1], a[:, 2], a[:, 3], a[:, 4], a[:, 5])


def sq(x, y, s=2.0, style="block0", prio=4.0):
    pts = np.array([[x, y], [x + s, y], [x + s, y + s], [x, y + s], [x, y]], float)
    return Shape(style, pts, prio)


def test_grid_for_aligns_to_cell():
    g = grid_for(LV, (-130.0, -70.0, 230.0, 40.0))
    assert (g.ox, g.otop, g.nx, g.ny) == (-150.0, 50.0, 8, 3)
    assert g.rect(0, 0) == (-150.0, 0.0, -100.0, 50.0)


def test_order_by_style_then_priority():
    s = [sq(0, 0, style="road", prio=1), sq(0, 0, style="land", prio=1), sq(0, 0, style="road", prio=9)]
    assert [(x.style, x.prio) for x in order(s)] == [("land", 1), ("road", 9), ("road", 1)]


def test_cell_bounds_and_style_counts():
    c = Cell(0, 0, [sq(1, 2), sq(10, 20, style="road")])
    assert c.bounds() == (1.0, 2.0, 12.0, 22.0)
    counts, points = c.style_counts()
    assert counts == [0, 0, 1, 0, 0, 1, 0] and points == [0, 0, 5, 0, 0, 5, 0]


def test_build_level_small_road_mesh():
    road = Mesh("r", np.array([[-10, 0, -20], [110, 0, -20], [110, 0, -30], [-10, 0, -30]], float),
                np.array([[0, 1, 2], [0, 2, 3]]))
    src = Sources([road], [], [quad(0, 0, 100, 50)], [], boxes([25, 40, 6, 6, 50, 0]), TF)
    g, cells = build_level(LV, src, (0.0, 0.0, 100.0, 50.0), log=lambda *_: None)
    assert (g.nx, g.ny) == (2, 1) and set(cells) == {(0, 0), (1, 0)}
    styles0 = [s.style for s in cells[(0, 0)].shapes]
    assert "land" not in styles0 and "road" in styles0 and "block1" in styles0
    assert styles0 == sorted(styles0, key=["land", "water", "block0", "block1", "block2", "road", "metro"].index)


def _grid_cells(n_blocks_per_cell):
    g = VGrid(0.0, 100.0, 2, 2, 50.0)
    cells = {}
    for ix in range(2):
        for iy in range(2):
            x0, y1 = ix * 50.0, 100.0 - iy * 50.0
            cells[(ix, iy)] = Cell(ix, iy, [sq(x0 + 1 + k % 20 * 2, y1 - 3 - k // 20 * 2, 1.0, prio=float(k + 1))
                                            for k in range(n_blocks_per_cell)])
    return g, cells


def test_worst_view_counts_every_cell_a_view_can_touch():
    g, cells = _grid_cells(10)
    pts, shp, _ = worst_view(LV, g, cells)
    assert shp == 40 and pts == 200      # the 941 x 740 m worst view covers the whole 100 m world


def test_fit_level_passes_untouched_when_under_budget():
    g, cells = _grid_cells(10)
    lv, out, rep = fit_level(LV, g, cells, rebuild_roads=lambda l: {}, log=lambda *_: None,
                             point_budget=1000, shape_budget=100)
    assert lv == LV and rep["steps"] == [] and rep["shapes"] == 40


def test_fit_level_drops_smallest_blocks_first():
    g, cells = _grid_cells(10)       # block areas are 1 m^2 with prio 1..10
    lv, out, rep = fit_level(LV, g, cells, rebuild_roads=lambda l: {}, log=lambda *_: None,
                             point_budget=1000, shape_budget=10)
    assert rep["steps"][0].startswith("area") and rep["shapes"] <= 10
    assert all(s.prio >= lv.min_area for c in out.values() for s in c.shapes)


def test_fit_level_raises_when_nothing_helps():
    g = VGrid(0.0, 100.0, 1, 1, 50.0)
    road = Shape("road", np.column_stack((np.linspace(0, 40, 50), np.linspace(0, 40, 50) ** 1.5 / 10)), 40.0)
    cells = {(0, 0): Cell(0, 0, [road])}
    with pytest.raises(BudgetError):
        fit_level(LV, g, cells, rebuild_roads=lambda l: {(0, 0): [road]}, log=lambda *_: None,
                  point_budget=3, shape_budget=100, strict=True)


def test_fit_level_non_strict_warns_and_flags():
    g = VGrid(0.0, 100.0, 1, 1, 50.0)
    road = Shape("road", np.column_stack((np.linspace(0, 40, 50), np.linspace(0, 40, 50) ** 1.5 / 10)), 40.0)
    cells = {(0, 0): Cell(0, 0, [road])}
    logs = []
    lv, out, rep = fit_level(LV, g, cells, rebuild_roads=lambda l: {(0, 0): [road]}, log=logs.append,
                             point_budget=3, shape_budget=100)
    assert rep["over_budget"] is True and out and any("WARNING" in m for m in logs)
    _, _, ok = fit_level(LV, g, cells, rebuild_roads=lambda l: {}, log=lambda *_: None,
                         point_budget=10000, shape_budget=100)
    assert ok["over_budget"] is False


def _road_mesh():
    road = Mesh("r", np.array([[-10, 0, -20], [210, 0, -20], [210, 0, -30], [-10, 0, -30]], float),
                np.array([[0, 1, 2], [0, 2, 3]]))
    return road


def test_build_level_workers_identical():
    src = Sources([_road_mesh()], [], [quad(0, 0, 200, 100)], [quad(120, 10, 160, 40)],
                  boxes([25, 40, 6, 6, 50, 0], [75, 60, 6, 6, 20, 0], [160, 70, 8, 8, 90, 0]), TF)
    ext = (0.0, 0.0, 200.0, 100.0)
    g1, c1 = build_level(LV, src, ext, log=lambda *_: None, workers=1)
    g2, c2 = build_level(LV, src, ext, log=lambda *_: None, workers=2)
    assert g1 == g2 and list(c1) == list(c2) and c1
    for k in c1:
        assert [s.style for s in c1[k].shapes] == [s.style for s in c2[k].shapes]
        assert all(np.array_equal(a.pts, b.pts) for a, b in zip(c1[k].shapes, c2[k].shapes))


def test_blocks_land_in_own_cell_once():
    src = Sources([], [], [], [], boxes([60, 25, 6, 6, 50, 0], [10, 25, 6, 6, 20, 0]), TF)
    g, cells = build_level(LV, src, (0.0, 0.0, 100.0, 50.0), log=lambda *_: None, workers=1)
    assert (g.nx, g.ny) == (2, 1)
    blocks = {k: [s.style for s in c.shapes if s.style.startswith("block")] for k, c in cells.items()}
    assert blocks == {(0, 0): ["block0"], (1, 0): ["block1"]}


def test_tiles_match_per_cell_reference_and_workers():
    rows = [[10, 240, 6, 6, 20, 0], [60, 20, 8, 8, 50, 0], [180, 130, 6, 6, 90, 0],
            [290, 40, 7, 7, 10, 0], [270, 200, 6, 6, 60, 0], [155, 100, 12, 6, 30, 0]]
    rows.append([200, 100, 30, 6, 40, 0])     # x 185..215 spans the column 3|4 border at x=200
    src = Sources([_road_mesh()], [], [quad(0, 0, 300, 250)], [], boxes(*rows), TF)
    ext = (0.0, 0.0, 300.0, 250.0)
    lv = VLevel("T", 0.5, 1.0, 0.25, 50.0, 0.5, 0.0, 2.0, 0.0, 20.0)
    g, c1 = build_level(lv, src, ext, log=lambda *_: None, workers=1)
    _, c2 = build_level(lv, src, ext, log=lambda *_: None, workers=2)
    assert (g.nx, g.ny) == (6, 5) and list(c1) == list(c2)
    for k in c1:
        assert [s.style for s in c1[k].shapes] == [s.style for s in c2[k].shapes]
        assert all(np.array_equal(a.pts, b.pts) for a, b in zip(c1[k].shapes, c2[k].shapes))
    corners = box_corners(src.boxes) + np.array([TF.dx, TF.dy])
    centres, heights = corners.mean(axis=1), np.asarray(src.boxes.dz, float)

    def cents(shapes):
        return sorted((s.style, *np.round(s.pts[:-1].mean(axis=0), 3)) for s in shapes if s.style.startswith("block"))
    total = 0
    for iy in range(g.ny):
        for ix in range(g.nx):
            ref = block_features(corners, centres, heights, g.rect(ix, iy), lv)
            got = c1[(ix, iy)].shapes if (ix, iy) in c1 else []
            assert cents(got) == cents(ref), (ix, iy)
            total += len(ref)
    assert total >= 6
    wide = [s for c in c1.values() for s in c.shapes if s.style.startswith("block")
            and s.pts[:, 0].min() < 200 < s.pts[:, 0].max()]
    assert len(wide) == 1


def _fit_setup():
    g = VGrid(0.0, 100.0, 2, 1, 50.0)
    road = Shape("road", np.array([[0, 10], [40, 10], [40, 20], [0, 20], [0, 10]], float), 400.0)
    blk = sq(5, 5, 13.0, prio=169.0)
    cells = {(0, 0): Cell(0, 0, order([blk, road, road]))}
    return g, cells, road


def test_fit_level_road_step_and_new_cell():
    g, cells, road = _fit_setup()
    new = Shape("road", np.array([[60, 10], [90, 10], [90, 20], [60, 20], [60, 10]], float), 300.0)
    seen = []

    def rebuild(l):
        seen.append(l.road_min_width)
        return {(1, 0): [new]}
    lv, out, rep = fit_level(LV, g, cells, rebuild_roads=rebuild, log=lambda *_: None,
                             point_budget=1000, shape_budget=1)    # area and tol steps cannot help: roads are last
    assert rep["steps"][-1] == "road 4" and rep["steps"][-2] == "tol 2" and seen == [4.0] and lv.road_min_width == 4.0
    assert set(out) == {(1, 0)}      # the small block went in the area steps, the old roads with the rebuild
    assert out[(1, 0)].shapes[0].style == "road"
    assert set(rep) == {"level", "steps", "points", "shapes", "at", "over_budget"}


def test_replace_roads_keeps_style_order():
    from nmtiles.vector_budget import _replace_roads
    g, cells, road = _fit_setup()
    out = _replace_roads(cells, {(0, 0): [road, road]})
    st = [s.style for s in out[(0, 0)].shapes]
    assert st == ["block0", "road", "road"]


def test_fit_level_tol_steps_keep_rings_closed():
    g = VGrid(0.0, 100.0, 1, 1, 50.0)
    t = np.linspace(0, 2 * np.pi, 400)
    ring = np.column_stack((25 + 20 * np.cos(t), 25 + 20 * np.sin(t)))
    ring[-1] = ring[0]
    sliver = Shape("block0", np.array([[0, 0], [0.01, 0], [0, 0.0]]), 1e6)     # degenerate: dropped by the tol step
    cells = {(0, 0): Cell(0, 0, [Shape("block1", ring, 1250.0), sliver])}
    lv, out, rep = fit_level(LV, g, cells, rebuild_roads=lambda l: {(0, 0): []}, log=lambda *_: None,
                             point_budget=150, shape_budget=100)
    assert any(s.startswith("tol") for s in rep["steps"]) and set(rep) == {"level", "steps", "points", "shapes", "at", "over_budget"}
    shapes = out[(0, 0)].shapes
    assert all(np.array_equal(s.pts[0], s.pts[-1]) and len(s.pts) >= 4 for s in shapes)
    assert [s.style for s in shapes] == ["block1"]


def _split_world():
    """Points-heavy corner A (3 roads x 100 pts) and shapes-heavy corner B (30 blocks x 5 pts), far apart."""
    g = VGrid(0.0, 100.0, 4, 2, 50.0)
    lv = VLevel("S", 0.005, 0.01, 0.25, 50.0, 0.5, 0.0, 2.0, 0.0, 20.0)     # worst view is only ~19 x 15 m
    roads = [Shape("road", np.column_stack((np.linspace(1, 10, 100), np.full(100, 85.0 + k * 0.5))), 9.0) for k in range(3)]
    blocks = [sq(160 + k % 10, 10 + k // 10 * 2, 1.0, prio=float(k + 1)) for k in range(30)]
    cells = {(0, 0): Cell(0, 0, roads), (3, 1): Cell(3, 1, blocks)}
    return g, lv, cells


def test_worst_view_custom_budgets_pick_the_matching_location():
    g, lv, cells = _split_world()
    p_at = worst_view(lv, g, cells, point_budget=300, shape_budget=10**9)
    s_at = worst_view(lv, g, cells, point_budget=10**9, shape_budget=30)
    assert p_at[:2] == (300, 3) and p_at[2][0] < 50
    assert s_at[:2] == (150, 30) and s_at[2][0] > 100


def test_fit_level_uses_its_own_budgets_for_the_report():
    g, lv, cells = _split_world()
    ref = worst_view(lv, g, cells, point_budget=300, shape_budget=1000)
    _, _, rep = fit_level(lv, g, cells, rebuild_roads=lambda l: {}, log=lambda *_: None,
                          point_budget=300, shape_budget=1000)
    assert rep["steps"] == [] and (rep["points"], rep["shapes"]) == (300, 3) and rep["at"] == ref[2]


def test_resimplify_drops_slivers_keeps_lines_and_closed_rings():
    from nmtiles.vector_budget import _resimplify
    sliver = Shape("block0", np.array([[0, 0], [10, 0], [10, 0.05], [0, 0.05], [0, 0]], float), 0.5)
    metro = Shape("metro", np.array([[0.0, 0.0], [10.0, 0.0]]), 10.0)
    square = Shape("block1", np.array([[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]], float), 100.0)
    road = Shape("road", np.array([[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]], float), 100.0)
    road_sliver = Shape("road", np.array([[0, 0], [10, 0], [10, 0.05], [0, 0.05], [0, 0]], float), 0.5)
    out = _resimplify({(0, 0): Cell(0, 0, [sliver, metro, square, road, road_sliver])}, 0.5)[(0, 0)].shapes
    # shapely keeps thin but valid fill rings (the area step removes small blocks); only degenerate rings go
    assert [s.style for s in out] == ["block0", "metro", "block1", "road", "road"]
    assert all(np.array_equal(s.pts[0], s.pts[-1]) and len(s.pts) >= 4 for s in out if s.style != "metro")
    flat = Shape("block0", np.array([[0, 0], [10, 0], [0, 0]], float), 0.0)
    assert _resimplify({(0, 0): Cell(0, 0, [flat])}, 0.5) == {}


def test_resimplify_slit_ring_stays_valid():
    from shapely.geometry import Polygon
    from nmtiles.vector_budget import _resimplify
    from nmtiles.vector_geom import split_holes
    ring_poly = Polygon([(0, 0), (100, 0), (100, 100), (0, 100)], [[(30, 30), (70, 30), (70, 70), (30, 70)]])
    (piece,) = split_holes(ring_poly)                 # one keyhole ring carrying a 0.05 m slit
    s = Shape("road", np.asarray(piece.exterior.coords, float), piece.area)
    for tol in (0.5, 2.0, 20.0, 60.0):
        out = _resimplify({(0, 0): Cell(0, 0, [s])}, tol)
        for c in out.values():
            for r in c.shapes:
                p = Polygon(r.pts)
                assert p.is_valid and p.area > 0 and np.array_equal(r.pts[0], r.pts[-1])


def test_build_level_ignores_boxes_below_min_height():
    b = boxes([20, 25, 10, 10, 3, 0], [80, 25, 10, 10, 10, 0])       # 3 m (ground) and 10 m tall
    src = Sources([], [], [], [], b, TF)
    _, cells = build_level(LV, src, (0.0, 0.0, 100.0, 50.0), log=lambda *_: None, workers=1)
    blocks = [s for c in cells.values() for s in c.shapes if s.style.startswith("block")]
    assert len(blocks) == 1 and blocks[0].pts[:, 0].min() > 50
