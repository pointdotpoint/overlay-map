from nmtiles.build import main


def test_levels_default_and_skip_export_accepted():
    import argparse  # noqa: F401
    import inspect
    import nmtiles.build as b
    src = inspect.getsource(b.main)
    assert '"0.5,1,2,4,8,16"' in src and "--jobs" in src and "--skip-export" in src
    assert "export_meshes" not in src and "load_boxes" not in src


def test_world_bounds_cover_pins_with_a_margin():
    import numpy as np
    from nmtiles.build import world_bounds
    geom = np.array([[0.0, 0.0], [100.0, 50.0]])
    pins = np.array([[-700.0, 20.0]])           # a shard off the coast, past every road and building
    assert world_bounds([geom, pins], margin=250.0) == (-950.0, -250.0, 350.0, 300.0)


def test_collect_spots_parsed_from_generated_data(tmp_path):
    from nmtiles.build import collect_spots
    p = tmp_path / "CollectData.reds"
    p.write_text('case 0: return "S,-1300.20,-1905.02,64.16,Items.a;T,12.5,-3.0,1.0,Items.b";\n'
                 'case 1: return "I,-7027.48,-4507.35,2.0,Items.c";\n')
    assert collect_spots(p).tolist() == [[-1300.20, -1905.02], [12.5, -3.0], [-7027.48, -4507.35]]


def test_shipped_collectibles_inside_shipped_bounds():
    """Every collectible pin must sit inside the world the shipped tiles cover, or the map rejects it."""
    import re
    from pathlib import Path
    from nmtiles.build import collect_spots
    root = Path(__file__).resolve().parents[3]
    gen = root / "r6/scripts/OverlayMap/Generated"
    src = (gen / "TileManifest.reds").read_text()
    def val(name):
        return float(re.search(rf"func {name}\(\)[^{{]*{{\s*return (-?[\d.]+);", src).group(1))
    spots = collect_spots(gen / "CollectData.reds")
    out = [(x, y) for x, y in spots.tolist()
           if not (val("WorldMinX") <= x <= val("WorldMaxX") and val("WorldMinY") <= y <= val("WorldMaxY"))]
    assert len(spots) > 1000 and out == []
