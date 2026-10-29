import numpy as np

from nmtiles.holo_atlas import ATLAS_H, ATLAS_W, SIZES, TILEABLE, build_holo_atlas


def part(img, parts, name):
    return np.asarray(img.crop(parts[name]))


def test_parts_sizes_bounds_and_no_overlap():
    img, parts = build_holo_atlas()
    assert img.size == (ATLAS_W, ATLAS_H) == (1024, 512) and img.mode == "RGBA"
    assert set(parts) == set(SIZES)
    assert {"holo_scan", "holo_grid", "holo_noise", "holo_bar", "holo_halo"} <= set(parts)
    assert SIZES["holo_scan"] == (64, 64) and SIZES["holo_grid"] == (256, 256) and SIZES["holo_noise"] == (256, 256)
    assert SIZES["holo_bar"] == (512, 160) and SIZES["holo_halo"] == (128, 128)
    rects = []
    for name, (l, t, r, b) in parts.items():
        assert (r - l, b - t) == SIZES[name], name
        assert 0 <= l < r <= ATLAS_W and 0 <= t < b <= ATLAS_H, name
        rects.append((l - 2, t - 2, r + 2, b + 2))     # 4 px apart: bilinear sampling cannot bleed a neighbour in
    for i, a in enumerate(rects):
        for b in rects[i + 1:]:
            assert a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1], (a, b)


def test_rgb_is_pure_white_and_every_part_has_visible_pixels():
    img, parts = build_holo_atlas()
    for name in parts:
        p = part(img, parts, name)
        assert (p[..., :3] == 255).all(), name
        assert p[..., 3].max() > 0, name


def test_deterministic():
    a, pa = build_holo_atlas()
    b, pb = build_holo_atlas()
    assert a.tobytes() == b.tobytes() and pa == pb


def test_scan_is_one_pixel_line_every_four_and_tiles_seamlessly():
    img, parts = build_holo_atlas()
    a = part(img, parts, "holo_scan")[..., 3]
    assert (a[0::4] == 255).all() and (a[1::4] == 0).all() and (a[2::4] == 0).all() and (a[3::4] == 0).all()
    # the row after the last row is row 0 again: a line exactly every 4 rows across the wrap
    rows = np.nonzero(a[:, 0])[0]
    assert (np.diff(np.concatenate([rows, [rows[0] + 64]])) == 4).all()
    assert (a == a[:, :1]).all()                       # constant along x: columns tile trivially


def test_grid_lines_every_64_and_seamless():
    img, parts = build_holo_atlas()
    a = part(img, parts, "holo_grid")[..., 3]
    assert (a[0, :] == 255).all() and (a[:, 0] == 255).all()                   # first row/column is a line ...
    assert a[63, 1:64].max() == 0 and a[1:63, 1:63].max() == 0                # ... and the cell is empty
    for y in (0, 64, 128, 192):
        assert (a[y, :] == 255).all()
    for x in (0, 64, 128, 192):
        assert (a[:, x] == 255).all()
    assert (a == 255).sum() == 4 * 256 + 4 * 256 - 16                          # nothing but the 4+4 lines
    # period 64 in both axes: shifting by one period reproduces the image, so the wrap continues the pattern
    assert np.array_equal(a, np.roll(a, 64, 0)) and np.array_equal(a, np.roll(a, 64, 1))


def test_noise_is_seamless_and_not_flat():
    img, parts = build_holo_atlas()
    a = part(img, parts, "holo_noise")[..., 3].astype(float)
    assert a.std() > 25 and a.min() < 20 and a.max() > 235
    inside_x = np.abs(a[:, 1:] - a[:, :-1]).mean()
    inside_y = np.abs(a[1:, :] - a[:-1, :]).mean()
    seam_x = np.abs(a[:, 0] - a[:, -1]).mean()
    seam_y = np.abs(a[0, :] - a[-1, :]).mean()
    assert abs(seam_x - inside_x) < 0.15 * inside_x and abs(seam_y - inside_y) < 0.15 * inside_y


def test_tileable_periods_are_declared_and_hold():
    img, parts = build_holo_atlas()
    for name, period in TILEABLE.items():
        a = part(img, parts, name)[..., 3]
        assert a.shape[0] % period == 0 and a.shape[1] % period == 0, name
    assert TILEABLE == {"holo_scan": 4, "holo_grid": 64, "holo_noise": 256}


def test_bar_is_transparent_bright_transparent_vertical_gradient():
    img, parts = build_holo_atlas()
    a = part(img, parts, "holo_bar")[..., 3].astype(int)
    assert (a == a[:, :1]).all()                              # vertical gradient only
    col = a[:, 0]
    peak = int(col.argmax())
    assert col[peak] == 255 and 40 < peak < 120
    assert col[0] < 10 and col[-1] < 10
    assert (np.diff(col[:peak + 1]) >= 0).all() and (np.diff(col[peak:]) <= 0).all()


def test_halo_is_radial_and_fades_to_zero_at_the_rim():
    img, parts = build_holo_atlas()
    a = part(img, parts, "holo_halo")[..., 3].astype(int)
    assert a[63, 63] > 240 and a[0, 0] == 0 and a[0, 63] == 0 and a[63, 0] == 0
    assert a[63, 63] > a[63, 90] > a[63, 120]
    assert abs(int(a[63, 30]) - int(a[30, 63])) <= 2         # symmetric


def test_edge_strips_are_bright_on_the_frame_side_and_fade_inward():
    img, parts = build_holo_atlas()
    t = part(img, parts, "holo_edge_t")[..., 3][:, 0].astype(int)
    b = part(img, parts, "holo_edge_b")[..., 3][:, 0].astype(int)
    l = part(img, parts, "holo_edge_l")[..., 3][0, :].astype(int)
    r = part(img, parts, "holo_edge_r")[..., 3][0, :].astype(int)
    assert t[0] == 255 and t[-1] < 10 and (np.diff(t) <= 0).all()
    assert np.array_equal(b, t[::-1]) and np.array_equal(l, t) and np.array_equal(r, t[::-1])


def test_line_is_opaque_in_the_middle_and_fades_to_zero_on_both_sides():
    img, parts = build_holo_atlas()
    assert SIZES["holo_line"] == (16, 16)
    a = part(img, parts, "holo_line")[..., 3].astype(int)
    assert (a == a[:, :1]).all()                              # uniform along the length (x): pieces stretch along it
    col = a[:, 0]
    assert col[0] == 0 and col[-1] == 0                       # transparent outer rows: the quad's edge is invisible
    assert (col[5:11] == 255).all()                           # opaque core
    assert np.array_equal(col, col[::-1])                     # symmetric
    assert (np.diff(col[:8]) >= 0).all() and 0 < col[1] < 255 # a ramp, not a step
