import numpy as np

from nmtiles import heightmap as hm


def _grid():
    return hm.Grid(x0=-64.0, y0=-64.0, cell=32.0, n=4)


def _boost(monkeypatch):
    monkeypatch.setattr(hm, "SAMPLES", 2)


def test_a_flat_triangle_fills_the_cells_it_covers():
    tops = hm.empty(_grid())
    tri = np.array([[[-64.0, -64.0, 10.0], [64.0, -64.0, 10.0], [-64.0, 64.0, 10.0]]])
    hm.add_triangles(tops, _grid(), tri)
    assert tops[0, 0] == 10.0        # inside
    assert np.isnan(tops[3, 3])      # past the hypotenuse


def test_a_sloped_triangle_keeps_each_cells_highest_sample(monkeypatch):
    _boost(monkeypatch)
    tops = hm.empty(_grid())
    tri = np.array([[[-64.0, -64.0, 0.0], [64.0, -64.0, 64.0], [-64.0, 64.0, 0.0]]])
    hm.add_triangles(tops, _grid(), tri)
    assert 16.0 <= tops[0, 2] <= 48.0
    assert tops[0, 1] < tops[0, 2]


def test_the_highest_surface_wins():
    tops = hm.empty(_grid())
    hm.add_triangles(tops, _grid(), np.array([[[-64.0, -64.0, 80.0], [64.0, -64.0, 80.0], [-64.0, 64.0, 80.0]]]))
    hm.add_triangles(tops, _grid(), np.array([[[-64.0, -64.0, 5.0], [64.0, -64.0, 5.0], [-64.0, 64.0, 5.0]]]))
    assert tops[0, 0] == 80.0


def test_a_box_raises_only_the_cells_under_it():
    tops = hm.empty(_grid())
    tops[:] = 0.0
    hm.add_boxes(tops, _grid(), cx=np.array([-48.0]), cy=np.array([-48.0]), dx=np.array([10.0]), dy=np.array([10.0]),
                 yaw=np.array([0.0]), top=np.array([120.0]))
    assert tops[0, 0] == 120.0
    assert tops[1, 1] == 0.0


def test_a_rotated_box_covers_its_real_corners(monkeypatch):
    _boost(monkeypatch)
    tops = hm.empty(_grid())
    tops[:] = 0.0
    hm.add_boxes(tops, _grid(), cx=np.array([0.0]), cy=np.array([0.0]), dx=np.array([100.0]), dy=np.array([4.0]),
                 yaw=np.array([np.pi / 4.0]), top=np.array([50.0]))
    assert tops[3, 3] == 50.0        # along the diagonal
    assert tops[0, 3] == 0.0         # off the diagonal


def test_a_value_survives_the_encoding_and_never_rounds_down():
    for z in (-128.0, -0.5, 0.0, 11.2, 642.9, 1500.0):
        assert hm.decode(hm.encode(z)) >= z
        assert hm.decode(hm.encode(z)) - z < 1.0 or z >= 1500.0


def test_the_encoding_is_two_characters_from_the_alphabet():
    s = hm.encode(11.2)
    assert len(s) == 2 and all(c in hm.ALPHABET for c in s)


def test_a_cell_keeps_its_lowest_and_highest_sample():
    fine = np.array([[1.0, 2.0, 7.0, 7.0], [3.0, 300.0, 7.0, 7.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]])
    lo, hi = hm.reduce(fine, 2)
    assert (lo[0, 0], hi[0, 0]) == (1.0, 300.0)
    assert (lo[0, 1], hi[0, 1]) == (7.0, 7.0)


def test_chunks_are_row_major_and_open_sea_is_left_out():
    lo = np.full((4, 4), -6.0)
    hi = np.full((4, 4), -6.0)
    lo[2, 1], hi[2, 1] = 10.0, 40.0  # row (y) 2, column (x) 1
    chunks = hm.pack(lo, hi, chunk=2)
    assert list(chunks) == [(0, 1)]  # chunk column 0, chunk row 1
    s = chunks[(0, 1)]
    assert len(s) == 4 * 2 * 2
    assert s[4:8] == hm.encode(10.0) + hm.encode(40.0)
    assert s[0:4] == hm.encode(-6.0) * 2


def test_the_generated_script_lists_every_chunk():
    g = hm.Grid(x0=-64.0, y0=-64.0, cell=32.0, n=4)
    src = hm.to_reds(g, hm.pack(np.full((4, 4), 1.0), np.full((4, 4), 1.0), chunk=2), chunk=2)
    assert "public abstract class NMHeightData" in src
    assert "case 0:" in src and "case 3:" in src
    assert "X0() -> Float { return -64.0; }" in src
    assert "ChunkCells() -> Int32 { return 2; }" in src
