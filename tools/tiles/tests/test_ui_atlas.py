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
    assert s == 72
    a = chip.getchannel("A")
    assert a.getpixel((s // 2, 5)) > 0          # vertex near the top centre
    assert a.getpixel((5, 6)) == 0              # top-left corner empty


def test_plate_ring_white_disc_dark():
    img, parts = build_ui_atlas()
    plate = img.crop(parts["plate"])
    assert plate.size == (224, 224) and SIZES["plate"] == 224
    r, g, b, a = plate.getpixel((112, 112))
    assert max(r, g, b) <= 10 and a > 200
    r, g, b, a = plate.getpixel((112 + 56, 112))
    assert min(r, g, b) >= 240 and a >= 240
    assert plate.getpixel((112 + 80, 112))[3] < plate.getpixel((112 + 40, 112))[3]   # falls off outward
    assert plate.getpixel((0, 0))[3] == 0


def test_chip_dark_fill_white_edge():
    img, parts = build_ui_atlas()
    chip = img.crop(parts["chip"])
    r, g, b, a = chip.getpixel((36, 36))
    assert max(r, g, b) <= 10 and 215 <= a <= 235
    assert min(chip.getpixel((36, 3))[:3]) >= 240 and chip.getpixel((36, 3))[3] >= 240


def test_icon_dot_is_solid_disc_and_brackets_exist():
    img, parts = build_ui_atlas()
    assert SIZES["icon_dot"] == 24
    dot = img.crop(parts["icon_dot"])
    assert dot.getpixel((12, 12)) == (255, 255, 255, 255) and dot.getpixel((0, 0))[3] == 0
    tl = img.crop(parts["bracket_tl"]).getchannel("A")
    assert tl.getpixel((60, 11)) > 200 and tl.getpixel((11, 60)) > 200 and tl.getpixel((70, 70)) == 0
    assert 0 < tl.getpixel((60, 4)) < 255      # soft glow around the stroke


def test_atlas_is_deterministic():
    a, _ = build_ui_atlas()
    b, _ = build_ui_atlas()
    assert a.tobytes() == b.tobytes()


def test_glow_halo_is_pure_white():
    img, parts = build_ui_atlas()
    ring = img.crop(parts["ring"])
    soft = [px for px in ring.getdata() if 0 < px[3] < 255]
    assert soft
    assert all(min(px[:3]) >= 250 for px in soft)


def test_chip_vertex0_has_no_dark_speck():
    img, parts = build_ui_atlas()
    chip = img.crop(parts["chip"])
    for xy in [(66, 54), (67, 53)]:   # lower-right vertex, just outside the stroke
        r, g, b, a = chip.getpixel(xy)
        assert not (a > 200 and r < 200), (xy, (r, g, b, a))
