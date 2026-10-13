from nmtiles.build import main


def test_levels_default_and_skip_export_accepted():
    import argparse  # noqa: F401
    import inspect
    import nmtiles.build as b
    src = inspect.getsource(b.main)
    assert '"0.5,1,2,4,8,16"' in src and "--jobs" in src and "--skip-export" in src
    assert "export_meshes" not in src and "load_boxes" not in src
