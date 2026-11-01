import numpy as np
from PIL import Image

from nmtiles.holo_preview import compose, pick_level, write_holo_previews

LEVELS = [{"mpp": m, "origin_x": 0.0, "origin_top": 512.0 * m, "nx": 1, "ny": 1} for m in (0.5, 1.0, 2.0, 4.0, 8.0, 16.0)]


def mask(path, a):
    Image.new("RGBA", (512, 512), (255, 255, 255, a)).save(path)
    return path


def tiles(tmp_path, glow=True):
    t = {s: {(li, 0, 0): mask(tmp_path / f"{s}{li}.png", 255) for li in range(6)} for s in ("road_minor", "road_major", "bfill", "outline")}
    t["glow"] = {(li, 0, 0): mask(tmp_path / f"g{li}.png", 255) for li in range(2, 6)} if glow else {}
    return t


def test_pick_level_is_downscale_only():
    assert [pick_level(LEVELS, m) for m in (0.5, 0.7, 1.0, 3.9, 4.0, 100.0)] == [0, 0, 1, 2, 3, 5]


def test_compose_size_and_glow_changes_the_picture(tmp_path):
    size = (400, 300)
    with_glow = compose(tiles(tmp_path), LEVELS, 0.5, (128.0, 128.0), size)
    without = compose(tiles(tmp_path, glow=False), LEVELS, 0.5, (128.0, 128.0), size)
    assert with_glow.size == size and with_glow.mode == "RGB"
    assert np.asarray(with_glow).astype(int).sum() != np.asarray(without).astype(int).sum()


def test_write_names(tmp_path):
    paths = write_holo_previews(LEVELS, tiles(tmp_path), tmp_path, (128.0, 128.0))
    assert [p.name for p in paths] == ["preview_holo_close.png", "preview_holo_far.png"]
    assert all(Image.open(p).size == (1882, 1480) for p in paths)
