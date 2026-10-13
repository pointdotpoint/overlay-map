import numpy as np
from PIL import Image

from nmtiles.preview import composite_sets, write_previews
from nmtiles.style import PREVIEW_BG

LEVEL = {"mpp": 1.0, "origin_x": 0.0, "origin_top": 1024.0, "nx": 2, "ny": 2}


def mask(path, a):
    Image.new("RGBA", (512, 512), (255, 255, 255, a)).save(path)
    return path


def test_composite_tints_masks_over_dark_background_in_layer_order(tmp_path):
    road, stroke = mask(tmp_path / "r.png", 255), mask(tmp_path / "s.png", 255)
    img = composite_sets({"road": {(0, 0): road}, "stroke": {(0, 0): stroke}}, LEVEL, (256.0, 768.0), (512, 512))
    assert img.size == (512, 512)
    r, g, b = img.getpixel((10, 10))
    assert abs(r - (0.1 * (0.45 * PREVIEW_BG[0] + 0.55 * 0x1e) + 0.9 * 0x9f)) < 2          # stroke over road over bg
    only_road = composite_sets({"road": {(0, 0): road}}, LEVEL, (256.0, 768.0), (512, 512)).getpixel((10, 10))
    assert only_road != (r, g, b)


def test_missing_tiles_stay_background(tmp_path):
    img = composite_sets({"road": {(1, 0): mask(tmp_path / "r.png", 255)}}, LEVEL, (256.0, 768.0), (512, 512))
    assert img.getpixel((10, 10)) == PREVIEW_BG


def test_write_previews_names_and_size(tmp_path):
    p = mask(tmp_path / "r.png", 255)
    paths = write_previews([dict(LEVEL, mpp=0.5), dict(LEVEL, mpp=2.0), dict(LEVEL, mpp=8.0)],
                           {"road": {(0, 0, 0): p, (1, 0, 0): p}}, tmp_path, (0.0, 0.0))
    assert [x.name for x in paths] == ["preview_minimap_close.png", "preview_minimap_mid.png", "preview_minimap_far.png"]
    assert all(Image.open(x).size == (1882, 1480) for x in paths)
