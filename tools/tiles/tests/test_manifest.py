from nmtiles.manifest import emit_manifest, emit_stub


def test_emit_manifest_contains_levels_and_tiles():
    levels = [
        {"mpp": 2.0, "origin_x": -6144.0, "origin_top": 8192.0, "nx": 11, "ny": 14, "tiles": [(0, 0), (3, 2)]},
        {"mpp": 4.0, "origin_x": -6144.0, "origin_top": 8192.0, "nx": 6, "ny": 7, "tiles": []},
    ]
    src = emit_manifest(levels, (-6012.0, -4608.0, 4589.0, 7381.0), "2.31")
    assert src.startswith("// GENERATED")
    assert "module NightMap" in src
    assert "public static func Available() -> Bool {\n        return true;" in src
    assert "case 0: return 2.0;" in src and "case 1: return 4.0;" in src
    assert "case 0: return [0, 25];" in src          # (3,2) -> 2*11+3
    assert "public static func LevelCount() -> Int32 {\n        return 2;" in src
    assert "return -6012.0;" in src and "return 7381.0;" in src


def test_empty_tile_list_uses_typed_empty_array():
    levels = [{"mpp": 2.0, "origin_x": 0.0, "origin_top": 0.0, "nx": 1, "ny": 1, "tiles": []}]
    src = emit_manifest(levels, (0.0, 0.0, 1.0, 1.0), "2.31")
    assert "let empty: array<Int32>;" in src


def test_stub_reports_unavailable():
    src = emit_stub()
    assert "return false;" in src and "LevelCount() -> Int32 {\n        return 0;" in src
