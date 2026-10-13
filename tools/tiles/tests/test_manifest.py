import re

from nmtiles.manifest import emit_manifest, emit_stub

SETS = ["road", "bfill", "glow", "outline"]


def lv(mpp, nx, ny, **tiles):
    return {"mpp": mpp, "origin_x": -6144.0, "origin_top": 8192.0, "nx": nx, "ny": ny, "tiles": tiles}


def test_emit_manifest_contains_levels_sets_and_tiles():
    levels = [lv(0.5, 40, 40, road=[(3, 2), (0, 0)]), lv(4.0, 6, 7, bfill=[(1, 1)])]
    src = emit_manifest(levels, (-6012.0, -4608.0, 4589.0, 7381.0), "2.31", SETS)
    assert src.startswith("// GENERATED") and "module NightMap" in src
    assert "public static func Available() -> Bool {\n        return true;" in src
    assert "case 0: return 0.5;" in src and "case 1: return 4.0;" in src
    assert "public static func LevelCount() -> Int32 {\n        return 2;" in src
    assert "public static func SetCount() -> Int32 {\n        return 4;" in src
    for i, n in enumerate(SETS):
        assert f'case {i}: return "{n}";' in src
    assert "LevelTiles" not in src
    assert "[0, 83]" in src                                  # road at L0, sorted: (0,0) -> 0, (3,2) -> 2*40+3
    assert "[7]" in src                                      # base at L1: (1,1) -> 1*6+1
    assert "return -6012.0;" in src and "return 7381.0;" in src


def test_missing_set_level_returns_typed_empty_array():
    src = emit_manifest([lv(2.0, 1, 1)], (0.0, 0.0, 1.0, 1.0), "2.31", SETS)
    assert "public static func SetTiles(s: Int32, l: Int32) -> array<Int32> {" in src
    assert "let empty: array<Int32>;" in src and "return empty;" in src


def test_stub_reports_unavailable():
    src = emit_stub()
    assert "return false;" in src and "LevelCount() -> Int32 {\n        return 0;" in src


def _big(n):
    nx = 20
    tiles = [(i % nx, i // nx) for i in range(n)]
    src = emit_manifest([lv(1.0, nx, n // nx + 1, road=tiles)], (0.0, 0.0, 1.0, 1.0), "t", SETS)
    return src


def _funcs(src):
    return {m.group(1): m.group(2) for m in re.finditer(r"func (\w+)\([^)]*\) -> array<Int32> \{\n(.*?)\n    \}", src, re.S)}


def test_300_tiles_emit_three_chunks_of_at_most_128_literals():
    src = _big(300)
    chunks = {k: v for k, v in _funcs(src).items() if re.fullmatch(r"Tiles_0_0_\d+", k)}
    assert len(chunks) == 3
    sizes = [len(re.search(r"\[([^\]]*)\]", v).group(1).split(",")) for _, v in sorted(chunks.items())]
    assert sizes == [128, 128, 44]
    lits = re.findall(r"\[([^\]]*)\]", src)
    assert max(len(l.split(",")) for l in lits) <= 128
    assert all("private static" in src.split(f"func {k}(")[0].rsplit("\n", 1)[-1] for k in chunks)   # chunks are private


def test_chunks_concatenate_in_order_and_public_switch_dispatches():
    src = _big(300)
    fs = _funcs(src)
    concat = fs["Tiles_0_0"]
    calls = re.findall(r"NMTileManifest\.(Tiles_0_0_\d+)\(\)", concat)
    assert calls == ["Tiles_0_0_0", "Tiles_0_0_1", "Tiles_0_0_2"]
    got = []
    for c in calls:
        got += [int(x) for x in re.search(r"\[([^\]]*)\]", fs[c]).group(1).split(",")]
    assert got == list(range(300))
    assert "private static func Tiles_0_0()" in src
    assert re.search(r"case 0: return NMTileManifest\.Tiles_0_0\(\);", src)         # key = s * 100 + l


def test_every_set_level_pair_round_trips_through_the_switch():
    levels = [lv(0.5, 40, 40, road=[(i % 40, i // 40) for i in range(300)], outline=[(5, 5)]),
              lv(1.0, 20, 20, bfill=[(1, 2), (0, 0)], glow=[(19, 19)]), lv(2.0, 10, 10)]
    src = emit_manifest(levels, (0.0, 0.0, 1.0, 1.0), "t", SETS)
    fs = _funcs(src)
    got = {}
    for m in re.finditer(r"case (\d+): return NMTileManifest\.(Tiles_\d+_\d+)\(\);", src):
        vals = []
        for c in re.findall(r"NMTileManifest\.(Tiles_\d+_\d+_\d+)\(\)", fs[m.group(2)]):
            vals += [int(x) for x in re.search(r"\[([^\]]*)\]", fs[c]).group(1).split(",")]
        got[int(m.group(1))] = vals
    want = {}
    for li, l in enumerate(levels):
        for s, n in enumerate(SETS):
            if l["tiles"].get(n):
                want[s * 100 + li] = sorted(iy * l["nx"] + ix for ix, iy in l["tiles"][n])
    assert got == want
