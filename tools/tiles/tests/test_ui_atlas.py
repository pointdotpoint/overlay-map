from nmtiles.ui_atlas import SIZES, build_ui_atlas


def test_atlas_has_all_parts_inside_bounds_without_overlap():
    img, parts = build_ui_atlas()
    assert img.size == (1024, 1024) and img.mode == "RGBA"
    assert set(parts) == set(SIZES)
    rects = list(parts.values())
    for name, (l, t, r, b) in parts.items():
        assert 0 <= l < r <= 1024 and 0 <= t < b <= 1024, name
        assert (r - l, b - t) == (SIZES[name], SIZES[name]), name
    for i, a in enumerate(rects):
        for b in rects[i + 1:]:
            assert a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1], (a, b)


def test_every_part_has_visible_pixels():
    img, parts = build_ui_atlas()
    for name, box in parts.items():
        assert img.crop(box).getchannel("A").getextrema()[1] > 0, name


def test_chip_is_pointy_top_hexagon():
    img, parts = build_ui_atlas()
    chip = img.crop(parts["chip"])
    s = chip.size[0]
    a = chip.getchannel("A")
    assert a.getpixel((s // 2, 9)) > 0          # vertex near the top centre
    assert a.getpixel((10, 12)) == 0            # top-left corner empty


def test_atlas_is_deterministic():
    a, _ = build_ui_atlas()
    b, _ = build_ui_atlas()
    assert a.tobytes() == b.tobytes()
