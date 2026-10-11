from PIL import Image

from nmtiles.preview import BACKDROP, composite


def test_composite_places_tiles_over_dark_backdrop(tmp_path):
    p = tmp_path / "t.png"
    Image.new("RGBA", (512, 512), (255, 0, 0, 255)).save(p)
    img = composite({(1, 0): p}, 0, 0, 2, 1)
    assert img.size == (1024, 512)
    assert img.getpixel((10, 10)) == BACKDROP and img.getpixel((600, 10)) == (255, 0, 0, 255)
