# NightMap Core + Tile Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A custom hologram-style 2D world map for Cyberpunk 2077. It opens as a live overlay on `\`, draws offline-rendered city tiles, and renders any number of items through a pooled, culled and clustered layer API. It also includes crosshair selection, a docked info card and a player marker.

**Architecture:**
- **Offline (Python):** a pipeline exports the game's 3D-map meshes with WolvenKit CLI and rasterizes them top-down into 512 px tiles at 4 zoom levels. It encodes them to BC7 with texconv (under Wine) and writes xbm/inkatlas resources from JSON templates. Finally it packs `NightMap.archive` and emits a redscript tile manifest.
- **In game (redscript + Codeware):** a `ScriptableSystem` owns a HUD-layer panel and a zero-delay `DelayCallback` frame loop.
  - Content arrives only through `NightMapLayer` objects.
  - Each layer keeps a 3-level spatial grid pyramid (250/1000/4000 m) with live counts, centroids and category tallies.
  - The renderer fills fixed widget pools from it.

**Tech Stack:**
- redscript 0.5.x (offline compile check via the game's `scc.exe` under Wine), Codeware 1.20.5, Mod Settings (optional), RedIMGRetriever (optional).
- Python 3.14 with numpy, Pillow, scipy and pytest (all installed).
- WolvenKit CLI 8.18+ (`~/.local/bin/WolvenKit.CLI`), texconv (`~/.local/bin/texconv.exe` via Wine).

**Spec:** `docs/superpowers/specs/2026-10-11-nightmap-core-design.md` (approved), mockups in `docs/superpowers/specs/mockups/`.

## Spec deviations (found while planning — confirm at plan review)

| # | Spec says | Plan does | Why |
|---|---|---|---|
| D1 | Calibration fails if fast-travel-point RMS error > 2 m | Fit axis signs + offset (±50 m) of the mesh→world transform by matching fast-travel points to a road distance field; **fail if the median point-to-road distance > 15 m** | Fast-travel points are not part of the map meshes, so no point-to-point RMS exists. They sit beside roads, so road distance is the measurable signal. |
| D2 | Tiles packed into one atlas per level, ≤ 25 MB, premultiplied alpha | **One 512² BC7 texture + inkatlas per tile, single mip, straight alpha**; target ≤ 60 MB | Generating one fixed-size xbm per tile reuses the proven template path. Zoom always picks the level that magnifies (never minifies), so mips aren't needed. Ink blends straight alpha. |
| D3 | A 250 m cell is drawn as one cluster when under 96 px | Clusters are **screen-space blocks ≥ 192 px in 4K units (= 96 px at 1080p)** built from a 3-level grid pyramid. Individual chips are drawn when a 250 m cell is ≥ 192 px. | A single 250 m grid would need about 9,000 cell visits per frame when zoomed out; the pyramid caps it at about 1,400. |
| D4 | Budget: 600 chips, 200 clusters | **300 chips, 80 clusters** (2 and 8 widgets each) | Benchmark: about 7–10 µs per live widget. The spec's budget × widgets-per-element would exceed the +3 ms target. |
| D5 | Missing Codeware/RedIMG → runtime error, no hotkey | Codeware is a **compile-time** dependency (redscript names NightMap in its error). RedIMG and Mod Settings are optional via `@if(ModuleExists(...))`. | Scripts that reference Codeware types cannot compile without it, so a runtime check can't run. |
| D6 | "Flat-top hexagon" | **Pointy-top hexagon** | That's what the approved mockups show (vertex at top/bottom). |

## Global Constraints

- **Game:** Cyberpunk 2077 2.31 at `~/cyberpunk_symlink` (Proton). Scripts install to `r6/scripts/NightMap/`, the archive to `archive/pc/mod/NightMap.archive`.
- **Code style:** all redscript files start with `module NightMap`. Public API classes are `NightMap`, `NightMapLayer`, `NightMapItem`, `NightMapDetails`, `NightMapLayerListener`; internals are prefixed `NM`.
- **Units:** layout sizes are authored in 3840×2160 HUD units and multiplied by `panel.scale = windowWidth / 3840`.
- **Coordinates:**
  - World = meters, X east, Y north.
  - Map-area pixels have Y pointing down.
  - North-up: `py = (cy - wy) / mpp + viewH/2`.
- **Frame loop:** `GameInstance.GetDelaySystem(game).DelayCallback(cb, 0.0, false)`. Never `DelayCallbackNextFrame` (silently dropped when re-armed from a callback).
- **Timing:** `NMClock.NowMs()` (RedIMG when present). Never `EngineTime` for frame timing (31.25 ms resolution).
- **Logging:** `ModLog(n"NightMap", ...)`. Lines land in `bin/x64/plugins/cyber_engine_tweaks/gamelog.log` as `[NightMap] ...`.
- **Default keys:**

  | Action | Key |
  |---|---|
  | Toggle | `IK_Backslash` |
  | Pan | `IK_NumPad8/2/4/6` (diagonals 7/9/1/3 fixed) |
  | Zoom | `IK_NumPlus` / `IK_NumMinus` |
  | Recenter | `IK_NumPad5` |
  | Act | `IK_NumPad0` |

  Arrow keys are ignored, because they drive vehicles.
- **Debug chords** (only when the Debug setting is on), all on the toggle key:

  | Chord | Action |
  |---|---|
  | Ctrl | self-test |
  | Shift | performance suite |
  | Alt | calibration dump |
  | Ctrl+Shift | toggle the debug layer |
- **Performance target:** with 50,000 items, the open map stays within baseline + 3 ms average and + 6 ms p95. Zero work while closed.
- **Visuals:** hologram palette, centered panel 70% × 71%, map area = left 70% of the panel, docked card = right 30%, pointy-top hex chips. Fonts: Orbitron for headings, Rajdhani for body.
- **Python:** the pipeline lives in `tools/tiles/nmtiles/`. Tests run with `cd tools/tiles && python3 -m pytest -q`. Downloaded or extracted game files are read with `python3 -I`-style isolation (no scripts executed from extracted dirs).

## Review Focus

1. **NumLock off** — numpad keys may arrive as arrow/Home keys. Expected: the map never pans from arrow keys (arrows steer the car) and the hint bar asks for NumLock. Pinned by `SelfTest.InputCases` (Task 10).
2. **Loading a save or quitting to menu while the map is open** — the old session's system detaches. Expected: the panel is removed, the loop stops, and no orphan widgets are left on the HUD. Pinned by Task 10 (`OnDetach` closes) and Checkpoint 1, step 6.
3. **Items at grid edges / outside the world / moved across cells** — expected: in-bounds edge positions are accepted, out-of-bounds positions are rejected with one log line, and counts, sums and tallies stay exact after moves. Pinned by `SelfTest.GridCases` (Task 9).
4. **Removing the selected item, or hiding its layer** — expected: the selection clears and the card shows "NO SELECTION" on the next frame; nothing references a dead id. Pinned by `SelfTest.PickCases` (Task 14).
5. **Non-16:9 windows (21:9, 16:10)** — expected: the panel, map area and card stay inside the window with positive sizes. Pinned by `SelfTest.LayoutCases` (Task 10).

---

## File Structure

```
nightmap/
  README.md
  .gitignore
  tools/
    check.sh                    offline redscript compile (scc under Wine, sandboxed)
    install.sh                  check + copy scripts/archive into the game
    results.py                  PerfSuite RESULT lines -> table + pass/fail
    tiles/
      nmtiles/__init__.py
      nmtiles/glb.py            GLB reader (numpy only) + LOD filter
      nmtiles/world.py          Transform: glTF -> world XY (axis signs + offset), json load/save
      nmtiles/export.py         WolvenKit uncook of 3dmap meshes; style_for(name)
      nmtiles/style.py          hologram colors per style + draw order
      nmtiles/render.py         LevelGrid, rasterize_mask, render_level, slice_tiles
      nmtiles/calib.py          gamelog CALIB parser, transform fit, gate (CLI)
      nmtiles/ui_atlas.py       hex chips, cluster hexes, ring, player arrow, brackets, glyph icons
      nmtiles/resources.py      xbm / inkatlas JSON generation from templates
      nmtiles/encode.py         texconv (-nogpu) BC7 batch encode
      nmtiles/pack.py           WolvenKit convert d + pack -> archive
      nmtiles/manifest.py       emit Generated/TileManifest.reds
      nmtiles/build.py          end-to-end CLI
      templates/tile.xbm.json   CBitmapTexture template (BC7, 1 mip)
      templates/atlas.inkatlas.json  inkTextureAtlas template (3 slots, 1 part)
      calibration.json          current mesh->world transform (default identity-with-flip)
      tests/glbutil.py, tests/test_*.py
  r6/scripts/NightMap/
    Core/Log.reds  Core/Optional.reds (RedIMG clock + image resolve, compiled only if present)
    Core/Math.reds  Core/Theme.reds  Core/Camera.reds
    Core/Settings.reds  Core/Input.reds  Core/NightMapSystem.reds
    Api/NightMap.reds  Api/NightMapItem.reds  Api/NightMapDetails.reds
    Api/NightMapLayerListener.reds  Api/NightMapLayer.reds  Api/Grid.reds
    Render/Ui.reds  Render/Panel.reds  Render/TileLayer.reds  Render/ItemRenderer.reds
    Render/Crosshair.reds  Render/InfoCard.reds  Render/PlayerMarker.reds
    Generated/TileManifest.reds
    Debug/SelfTest.reds  Debug/DebugLayer.reds  Debug/PerfSuite.reds  Debug/Calibration.reds
  archive/pc/mod/NightMap.archive   build output (gitignored; rebuilt by build.py)
  docs/api.md
```

`archive/` and `tools/tiles/build/` are gitignored; `Generated/TileManifest.reds` is committed, because scripts can't compile without it.

---

### Task 1: Repo scaffold, offline compile check, install script

**Files:**
- Create: `README.md`, `.gitignore`, `tools/check.sh`, `tools/install.sh`, `r6/scripts/NightMap/Core/Log.reds`

**Interfaces:**
- Produces: `NMLog.Info(msg: String)`, `NMLog.Error(msg: String)`; `tools/check.sh` (exit 0 = compiles, prints `COMPILE OK`); `tools/install.sh [--uninstall]`.

- [ ] **Step 1: Write `.gitignore` and `README.md`**

`.gitignore`:
```
.superpowers/
archive/
tools/tiles/build/
__pycache__/
*.pyc
```

`README.md`:
```markdown
# NightMap

Hologram-style 2D world map overlay for Cyberpunk 2077 (redscript + Codeware). Opens on `\` alongside the vanilla map.

- Spec: docs/superpowers/specs/2026-10-11-nightmap-core-design.md
- Plan: docs/superpowers/plans/2026-10-11-nightmap-core.md

## Build & install
    cd tools/tiles && python3 -m nmtiles.build --game ~/cyberpunk_symlink   # tiles + UI atlas -> archive + manifest
    tools/check.sh                                                          # offline redscript compile
    tools/install.sh                                                        # check + copy into the game
```

- [ ] **Step 2: Write `tools/check.sh`**

```bash
#!/usr/bin/env bash
# Compile-check NightMap offline with the game's own redscript compiler under Wine.
# Sandbox copy of scc + vanilla final.redscripts; the game install is never touched.
set -euo pipefail

GAME="${GAME:-$HOME/cyberpunk_symlink}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="${SANDBOX:-/tmp/nightmap-scc}"

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/engine/tools" "$SANDBOX/r6/cache" "$SANDBOX/r6/scripts"/{Codeware,RedIMGRetriever,ModSettings}
cp "$GAME/engine/tools/scc.exe" "$GAME/engine/tools/scc_lib.dll" "$SANDBOX/engine/tools/"
cp "$GAME/r6/cache/final.redscripts" "$SANDBOX/r6/cache/"
cp "$GAME"/red4ext/plugins/Codeware/Scripts/*.reds "$SANDBOX/r6/scripts/Codeware/"
cp "$GAME"/r6/scripts/RedIMGRetriever/*.reds "$SANDBOX/r6/scripts/RedIMGRetriever/"
cp "$GAME"/red4ext/plugins/mod_settings/*.reds "$SANDBOX/r6/scripts/ModSettings/"
cp -r "$HERE/r6/scripts/NightMap" "$SANDBOX/r6/scripts/NightMap"

# scc only scans the scripts dir reliably when given a path relative to its own tree.
(cd "$SANDBOX" && WINEDEBUG=-all wine engine/tools/scc.exe -compile 'r6\scripts' \
   -customCacheDir 'r6\cache' >/dev/null 2>&1) || true

LOG="$SANDBOX/r6/logs/redscript_rCURRENT.log"
[ -f "$LOG" ] || { echo "no compiler log at $LOG"; exit 1; }
grep -vE '\.reds$' "$LOG" | grep -v '^\[INFO' || true
if grep -q "ERROR" "$LOG"; then echo "COMPILE FAILED"; exit 1; fi
grep -q "NightMap" "$LOG" || { echo "NightMap was not compiled"; exit 1; }
echo "COMPILE OK"
```

- [ ] **Step 3: Write `tools/install.sh`**

```bash
#!/usr/bin/env bash
# Copy NightMap into the game, or remove it with --uninstall.
set -euo pipefail
GAME="${GAME:-$HOME/cyberpunk_symlink}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$GAME/r6/scripts/NightMap"
ARCH="$GAME/archive/pc/mod/NightMap.archive"

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$DEST" "$ARCH"; echo "removed $DEST and $ARCH"; exit 0
fi
"$HERE/tools/check.sh"
rm -rf "$DEST"; cp -r "$HERE/r6/scripts/NightMap" "$DEST"
if [ -f "$HERE/archive/pc/mod/NightMap.archive" ]; then
  mkdir -p "$(dirname "$ARCH")"; cp "$HERE/archive/pc/mod/NightMap.archive" "$ARCH"
  echo "installed archive -> $ARCH"
else
  echo "WARNING: no archive built yet (run tools/tiles build); map will show the fallback grid"
fi
echo "installed scripts -> $DEST (restart the game to compile)"
```

- [ ] **Step 4: Write `r6/scripts/NightMap/Core/Log.reds`**

```swift
module NightMap

// All NightMap output goes to CET's gamelog.log as "[NightMap] ..." lines.
public abstract class NMLog {
    public static func Info(msg: String) {
        ModLog(n"NightMap", msg);
    }

    public static func Error(msg: String) {
        ModLog(n"NightMap", "ERROR|" + msg);
    }
}
```

- [ ] **Step 5: Verify the checker passes, then that it catches errors**

Run: `chmod +x tools/*.sh && tools/check.sh`
Expected: last line `COMPILE OK`.

Run: `echo 'func Broken() { let x: Int32 = NoSuchFunc(); }' >> r6/scripts/NightMap/Core/Log.reds && tools/check.sh; git checkout r6/scripts/NightMap/Core/Log.reds`
Expected: `UNRESOLVED_FN ... NoSuchFunc` then `COMPILE FAILED` (exit 1); file restored.

- [ ] **Step 6: Commit**

```bash
git add .gitignore README.md tools/check.sh tools/install.sh r6/scripts/NightMap/Core/Log.reds
git commit -m "Scaffold NightMap: offline compile check, install script, logger"
```

---

### Task 2: GLB reader, LOD filter, world transform, mesh export

**Files:**
- Create: `tools/tiles/nmtiles/__init__.py`, `nmtiles/glb.py`, `nmtiles/world.py`, `nmtiles/export.py`, `tools/tiles/calibration.json`, `tests/__init__.py`, `tests/glbutil.py`, `tests/test_glb.py`, `tests/test_export.py`, `tools/tiles/pytest.ini`

**Interfaces:**
- Produces:
  - `Mesh(name: str, positions: np.ndarray[N,3] float64, triangles: np.ndarray[M,3] int64)`; `read_glb(path) -> list[Mesh]`; `keep_best_lod(meshes) -> list[Mesh]`
  - `Transform(sx=1.0, sy=-1.0, dx=0.0, dy=0.0)` with `.apply(pos[N,3]) -> np.ndarray[N,2]` (world XY), `Transform.load(path)`, `.save(path)`
  - `export_meshes(game_dir: Path, out_dir: Path, wolvenkit: str = "WolvenKit.CLI") -> list[Path]`; `style_for(stem: str) -> str | None`
  - test helper `make_glb(nodes: list[tuple[str, array, array]]) -> bytes`

- [ ] **Step 1: Write the test helper and failing tests**

`tools/tiles/pytest.ini`:
```ini
[pytest]
testpaths = tests
markers =
    slow: needs wine/texconv/WolvenKit (run with NIGHTMAP_SLOW=1)
```

`tools/tiles/tests/__init__.py`: empty file.

`tools/tiles/tests/glbutil.py`:
```python
"""Build minimal GLB files in memory for tests."""
import json
import struct

import numpy as np


def make_glb(nodes):
    """nodes: list of (name, positions (N,3), indices (M,3))."""
    bin_ = b""
    views, accessors, meshes, gnodes = [], [], [], []
    for i, (name, pos, idx) in enumerate(nodes):
        pos = np.asarray(pos, np.float32)
        idx = np.asarray(idx, np.uint32).reshape(-1)
        views.append({"buffer": 0, "byteOffset": len(bin_), "byteLength": pos.nbytes})
        bin_ += pos.tobytes()
        accessors.append({"bufferView": len(views) - 1, "componentType": 5126, "count": len(pos),
                          "type": "VEC3", "min": pos.min(0).tolist(), "max": pos.max(0).tolist()})
        views.append({"buffer": 0, "byteOffset": len(bin_), "byteLength": idx.nbytes})
        bin_ += idx.tobytes()
        accessors.append({"bufferView": len(views) - 1, "componentType": 5125, "count": len(idx), "type": "SCALAR"})
        meshes.append({"primitives": [{"attributes": {"POSITION": len(accessors) - 2}, "indices": len(accessors) - 1}]})
        gnodes.append({"name": name, "mesh": i})
    while len(bin_) % 4:
        bin_ += b"\0"
    js = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": len(bin_)}], "bufferViews": views,
          "accessors": accessors, "meshes": meshes, "nodes": gnodes}
    jb = json.dumps(js).encode()
    jb += b" " * ((4 - len(jb) % 4) % 4)
    total = 12 + 8 + len(jb) + 8 + len(bin_)
    return (struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(jb), 0x4E4F534A) + jb
            + struct.pack("<II", len(bin_), 0x004E4942) + bin_)


def square(x0, z0, x1, z1, y=0.0):
    """Two triangles covering glTF x in [x0,x1], z in [z0,z1] at height y."""
    pos = [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]
    return pos, [(0, 1, 2), (0, 2, 3)]
```

`tools/tiles/tests/test_glb.py`:
```python
import numpy as np
import pytest

from nmtiles.glb import Mesh, keep_best_lod, read_glb
from nmtiles.world import Transform
from tests.glbutil import make_glb, square


def test_read_glb_roundtrip(tmp_path):
    pos, idx = square(0, -10, 10, 0, y=5)
    p = tmp_path / "a.glb"
    p.write_bytes(make_glb([("submesh_00_LOD_1", pos, idx)]))
    meshes = read_glb(p)
    assert len(meshes) == 1
    assert meshes[0].name == "submesh_00_LOD_1"
    assert meshes[0].positions.shape == (4, 3)
    assert meshes[0].triangles.tolist() == [[0, 1, 2], [0, 2, 3]]
    assert meshes[0].positions[:, 1].tolist() == [5, 5, 5, 5]


def test_read_glb_rejects_non_glb(tmp_path):
    p = tmp_path / "x.glb"
    p.write_bytes(b"not a glb at all")
    with pytest.raises(ValueError):
        read_glb(p)


def test_keep_best_lod_drops_coarser_lods():
    z = np.zeros((3, 3))
    t = np.zeros((1, 3), np.int64)
    meshes = [Mesh("submesh_00_LOD_1", z, t), Mesh("submesh_00_LOD_2", z, t),
              Mesh("submesh_01_LOD_2", z, t), Mesh("plain", z, t)]
    names = [m.name for m in keep_best_lod(meshes)]
    assert names == ["submesh_00_LOD_1", "submesh_01_LOD_2", "plain"]


def test_default_transform_flips_gltf_z_to_world_y():
    pos = np.array([[1.0, 50.0, -2.0], [-3.0, 0.0, 4.0]])
    xy = Transform().apply(pos)
    assert xy.tolist() == [[1.0, 2.0], [-3.0, -4.0]]


def test_transform_save_load(tmp_path):
    t = Transform(1.0, -1.0, 12.5, -6.0)
    p = tmp_path / "c.json"
    t.save(p)
    assert Transform.load(p) == t
```

`tools/tiles/tests/test_export.py`:
```python
from nmtiles.export import style_for


def test_style_for_known_meshes():
    assert style_for("3dmap_terrain") == "land"
    assert style_for("3dmap_water") == "water"
    assert style_for("3dmap_cliffs") == "cliff"
    assert style_for("3dmap_roads") == "road"
    assert style_for("3dmap_roads_borders") == "road_border"
    assert style_for("3dmap_metro") == "metro"


def test_style_for_skips_collision_and_helpers():
    assert style_for("3dmap_coll_buildings2") is None
    assert style_for("3dmap_coll_roads") is None
    assert style_for("mappin_geo_bulb") is None
    assert style_for("3dmap_cursor") is None


def test_style_for_everything_else_is_building():
    assert style_for("3dmap_triangle_soup") == "building"
    assert style_for("rcr_park_ferris_wheel") == "building"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd tools/tiles && python3 -m pytest -q`
Expected: collection errors `ModuleNotFoundError: No module named 'nmtiles'`.

- [ ] **Step 3: Implement**

`tools/tiles/nmtiles/__init__.py`: empty file.

`tools/tiles/nmtiles/glb.py`:
```python
"""Minimal glTF-binary reader (positions + triangle indices), numpy only."""
from __future__ import annotations

import json
import re
import struct
from dataclasses import dataclass
from pathlib import Path

import numpy as np

_COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
_NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
_LOD = re.compile(r"^(?P<base>.*)_LOD_(?P<lod>\d+)$")


@dataclass
class Mesh:
    name: str
    positions: np.ndarray  # (N,3) float64, glTF space (Y up)
    triangles: np.ndarray  # (M,3) int64


def _accessor(js: dict, bin_: bytes, idx: int) -> np.ndarray:
    a = js["accessors"][idx]
    view = js["bufferViews"][a["bufferView"]]
    dtype = np.dtype(_COMP[a["componentType"]])
    n = _NCOMP[a["type"]]
    start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    item = dtype.itemsize * n
    stride = view.get("byteStride") or item
    if stride != item:
        raw = np.frombuffer(bin_, np.uint8, count=stride * a["count"], offset=start).reshape(a["count"], stride)
        return raw[:, :item].copy().view(dtype).reshape(a["count"], n)
    return np.frombuffer(bin_, dtype, count=a["count"] * n, offset=start).reshape(a["count"], n)


def read_glb(path: Path | str) -> list[Mesh]:
    data = Path(path).read_bytes()
    if len(data) < 20 or struct.unpack_from("<I", data, 0)[0] != 0x46546C67:
        raise ValueError(f"{path}: not a GLB file")
    jlen, _ = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen, _ = struct.unpack_from("<II", data, off)
    bin_ = data[off + 8: off + 8 + blen]
    meshes: list[Mesh] = []
    for node in js.get("nodes", []):
        if "mesh" not in node:
            continue
        if any(k in node for k in ("matrix", "translation", "rotation", "scale")):
            raise ValueError(f"{path}: node {node.get('name')} has a transform (unsupported)")
        gm = js["meshes"][node["mesh"]]
        for prim in gm["primitives"]:
            if prim.get("mode", 4) != 4:
                continue
            pos = _accessor(js, bin_, prim["attributes"]["POSITION"]).astype(np.float64)
            if "indices" in prim:
                tri = _accessor(js, bin_, prim["indices"]).astype(np.int64).reshape(-1, 3)
            else:
                tri = np.arange(len(pos), dtype=np.int64).reshape(-1, 3)
            meshes.append(Mesh(node.get("name", gm.get("name", "")), pos, tri))
    return meshes


def _base_lod(name: str) -> tuple[str, int]:
    m = _LOD.match(name)
    return (m["base"], int(m["lod"])) if m else (name, 0)


def keep_best_lod(meshes: list[Mesh]) -> list[Mesh]:
    """Keep only the finest LOD per submesh (names like submesh_00_LOD_1)."""
    best: dict[str, int] = {}
    for m in meshes:
        base, lod = _base_lod(m.name)
        best[base] = min(best.get(base, lod), lod)
    return [m for m in meshes if _base_lod(m.name)[1] == best[_base_lod(m.name)[0]]]
```

`tools/tiles/nmtiles/world.py`:
```python
"""glTF (Y-up, exported by WolvenKit) -> game world XY (meters, X east, Y north)."""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np


@dataclass(frozen=True)
class Transform:
    sx: float = 1.0    # world_x = sx * gltf_x + dx
    sy: float = -1.0   # world_y = sy * gltf_z + dy   (WolvenKit writes red_y as -gltf_z)
    dx: float = 0.0
    dy: float = 0.0

    def apply(self, pos: np.ndarray) -> np.ndarray:
        return np.column_stack((self.sx * pos[:, 0] + self.dx, self.sy * pos[:, 2] + self.dy))

    def save(self, path: Path | str) -> None:
        Path(path).write_text(json.dumps(asdict(self), indent=2) + "\n")

    @staticmethod
    def load(path: Path | str) -> "Transform":
        p = Path(path)
        if not p.exists():
            return Transform()
        return Transform(**json.loads(p.read_text()))
```

`tools/tiles/nmtiles/export.py`:
```python
"""Export the vanilla 3D-map meshes to GLB with WolvenKit CLI and classify them by style."""
from __future__ import annotations

import subprocess
from pathlib import Path

MESH_REGEX = r"base\\entities\\cameras\\3dmap\\[^\\]+\.mesh$"
_EXACT = {
    "3dmap_terrain": "land",
    "3dmap_water": "water",
    "3dmap_cliffs": "cliff",
    "3dmap_roads": "road",
    "3dmap_roads_borders": "road_border",
    "3dmap_metro": "metro",
}


def style_for(stem: str) -> str | None:
    n = stem.lower()
    if n.startswith("3dmap_coll_") or n.startswith("mappin_geo") or n == "3dmap_cursor":
        return None
    return _EXACT.get(n, "building")


def export_meshes(game_dir: Path, out_dir: Path, wolvenkit: str = "WolvenKit.CLI") -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    for sub in ("content", "ep1"):
        archives = game_dir / "archive" / "pc" / sub
        if not archives.is_dir():
            continue
        subprocess.run([wolvenkit, "uncook", str(archives), "-r", MESH_REGEX, "-o", str(out_dir),
                        "-gp", str(game_dir)], check=True, stdout=subprocess.DEVNULL)
    glbs = sorted(out_dir.rglob("*.glb"))
    if not glbs:
        raise RuntimeError(f"WolvenKit exported no meshes into {out_dir}")
    return glbs
```

`tools/tiles/calibration.json`:
```json
{
  "sx": 1.0,
  "sy": -1.0,
  "dx": 0.0,
  "dy": 0.0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd tools/tiles && python3 -m pytest -q`
Expected: `8 passed`.

- [ ] **Step 5: Verify the real export (one-off, ~1 min)**

Run: `cd tools/tiles && python3 -c "from pathlib import Path; from nmtiles.export import export_meshes; from nmtiles.glb import read_glb, keep_best_lod; ps=export_meshes(Path.home()/'cyberpunk_symlink', Path('build/meshes')); print(len(ps)); m=keep_best_lod(read_glb([p for p in ps if p.stem=='3dmap_roads'][0])); import numpy as np; a=np.vstack([x.positions for x in m]); print(a.min(0), a.max(0))"`
Expected: about 20 GLBs; roads bounds near `[-6012, -28, -7381] .. [4589, 229, 4608]`.

- [ ] **Step 6: Commit**

```bash
git add tools/tiles
git commit -m "Tile pipeline: GLB reader, LOD filter, world transform, mesh export"
```

---

### Task 3: Hologram rasterizer

**Files:**
- Create: `tools/tiles/nmtiles/style.py`, `nmtiles/render.py`, `tests/test_render.py`

**Interfaces:**
- Consumes: `Mesh`, `Transform` (Task 2).
- Produces:
  - `LevelGrid(mpp: float, origin_x: float, origin_top: float, nx: int, ny: int, tile: int = 512)`, with `.width`, `.height` and `.tile_world` (= `tile * mpp`)
  - `level_grid(bounds: tuple[minx, miny, maxx, maxy], mpp: float, tile: int = 512) -> LevelGrid`
  - `rasterize_mask(meshes, tf, origin_x, origin_top, mpp, width, height) -> np.ndarray[bool]`
  - `render_level(styled: dict[str, list[Mesh]], tf, grid) -> PIL.Image (RGBA)`
  - `slice_tiles(img, grid) -> dict[tuple[int, int], PIL.Image]` (empty tiles omitted)
  - `STYLE` dict in style.py

- [ ] **Step 1: Write failing tests**

`tools/tiles/tests/test_render.py`:
```python
import numpy as np

from nmtiles.glb import Mesh
from nmtiles.render import level_grid, rasterize_mask, render_level, slice_tiles
from nmtiles.world import Transform
from tests.glbutil import square


def _mesh(x0, y0, x1, y1, h=0.0, name="m"):
    # world y = -gltf z, so world [y0,y1] is gltf z [-y1,-y0]
    pos, idx = square(x0, -y1, x1, -y0, y=h)
    return Mesh(name, np.array(pos, float), np.array(idx, np.int64))


def test_level_grid_aligns_to_tile_multiples():
    g = level_grid((10.0, -700.0, 1000.0, 100.0), mpp=2.0, tile=512)
    assert g.tile_world == 1024.0
    assert g.origin_x == 0.0          # floor(10/1024)*1024
    assert g.origin_top == 1024.0     # ceil(100/1024)*1024
    assert g.nx == 1 and g.ny == 2    # x 0..1024 ; y 1024..-1024
    assert (g.width, g.height) == (512, 1024)


def test_rasterize_mask_places_world_square_north_up():
    m = _mesh(0, 0, 100, 100)
    mask = rasterize_mask([m], Transform(), origin_x=0.0, origin_top=512.0, mpp=1.0, width=512, height=512)
    # world y in [0,100] -> rows 412..512 (top = 512 - y)
    assert mask[450, 50] and mask[500, 10]
    assert not mask[300, 50]   # world y = 212, outside
    assert not mask[450, 200]  # world x = 200, outside


def test_render_level_draws_styles_and_slices_skip_empty_tiles():
    grid = level_grid((0.0, 0.0, 2000.0, 1000.0), mpp=2.0)
    styled = {"road_border": [_mesh(0, 0, 200, 20)], "water": [_mesh(1200, 0, 1600, 400)]}
    img = render_level(styled, Transform(), grid)
    assert img.mode == "RGBA" and img.size == (grid.width, grid.height)
    tiles = slice_tiles(img, grid)
    assert (0, 0) in tiles and (1, 0) in tiles
    assert all(t.size == (512, 512) for t in tiles.values())
    alpha = np.asarray(img)[:, :, 3]
    assert alpha.max() > 150          # bright road border
    assert len(tiles) == 2            # grid is 2x1 here, both have content


def test_slice_tiles_omits_fully_transparent_tiles():
    grid = level_grid((0.0, 0.0, 4000.0, 1000.0), mpp=2.0)
    img = render_level({"water": [_mesh(10, 10, 50, 50)]}, Transform(), grid)
    tiles = slice_tiles(img, grid)
    assert list(tiles) == [(0, 0)]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_render.py`
Expected: `ModuleNotFoundError: No module named 'nmtiles.render'`.

- [ ] **Step 3: Implement**

`tools/tiles/nmtiles/style.py`:
```python
"""Hologram palette for baked map tiles (straight alpha RGBA). Order = back to front."""
STYLE = {
    "land":        {"order": 0, "fill": (40, 200, 255, 13)},
    "water":       {"order": 1, "fill": (40, 200, 255, 33)},
    "cliff":       {"order": 2, "fill": (80, 220, 255, 22)},
    "road":        {"order": 3, "fill": (80, 220, 255, 51)},
    "building":    {"order": 4, "fill": (80, 220, 255, 15), "outline": (120, 235, 255, 115), "height_alpha": 30},
    "road_border": {"order": 5, "fill": (120, 235, 255, 217), "glow": (120, 235, 255, 90)},
    "metro":       {"order": 6, "fill": (255, 79, 216, 200)},
}
```

`tools/tiles/nmtiles/render.py`:
```python
"""Top-down orthographic rasterization of styled map meshes into north-up tiles."""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

from nmtiles.glb import Mesh
from nmtiles.style import STYLE
from nmtiles.world import Transform


@dataclass(frozen=True)
class LevelGrid:
    mpp: float
    origin_x: float     # world x of the left edge of tile column 0
    origin_top: float   # world y of the top edge of tile row 0 (rows grow south)
    nx: int
    ny: int
    tile: int = 512

    @property
    def tile_world(self) -> float:
        return self.tile * self.mpp

    @property
    def width(self) -> int:
        return self.nx * self.tile

    @property
    def height(self) -> int:
        return self.ny * self.tile


def level_grid(bounds: tuple[float, float, float, float], mpp: float, tile: int = 512) -> LevelGrid:
    minx, miny, maxx, maxy = bounds
    tw = tile * mpp
    ox = math.floor(minx / tw) * tw
    otop = math.ceil(maxy / tw) * tw
    nx = max(1, math.ceil((maxx - ox) / tw))
    ny = max(1, math.ceil((otop - miny) / tw))
    return LevelGrid(mpp, ox, otop, nx, ny, tile)


def _to_px(xy: np.ndarray, origin_x: float, origin_top: float, mpp: float) -> np.ndarray:
    return np.column_stack(((xy[:, 0] - origin_x) / mpp, (origin_top - xy[:, 1]) / mpp))


def _draw_mesh(draw: ImageDraw.ImageDraw, mesh: Mesh, tf: Transform, origin_x: float, origin_top: float,
               mpp: float, width: int, height: int, fill, height_alpha: int = 0) -> None:
    px = _to_px(tf.apply(mesh.positions), origin_x, origin_top, mpp)
    tris = px[mesh.triangles]                       # (M,3,2)
    lo = tris.min(axis=1)
    hi = tris.max(axis=1)
    keep = (hi[:, 0] >= 0) & (lo[:, 0] < width) & (hi[:, 1] >= 0) & (lo[:, 1] < height)
    heights = mesh.positions[:, 1][mesh.triangles].mean(axis=1) if height_alpha else None
    for i in np.nonzero(keep)[0]:
        color = fill
        if height_alpha:
            h = float(np.clip(heights[i] / 150.0, 0.0, 1.0))
            color = (fill[0], fill[1], fill[2], int(fill[3] + height_alpha * h))
        draw.polygon([tuple(p) for p in tris[i]], fill=color)


def rasterize_mask(meshes: list[Mesh], tf: Transform, origin_x: float, origin_top: float, mpp: float,
                   width: int, height: int) -> np.ndarray:
    img = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(img)
    for m in meshes:
        _draw_mesh(draw, m, tf, origin_x, origin_top, mpp, width, height, 255)
    return np.asarray(img) > 0


def render_level(styled: dict[str, list[Mesh]], tf: Transform, grid: LevelGrid) -> Image.Image:
    w, h = grid.width, grid.height
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for style in sorted(styled, key=lambda s: STYLE[s]["order"]):
        spec = STYLE[style]
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        for m in styled[style]:
            _draw_mesh(draw, m, tf, grid.origin_x, grid.origin_top, grid.mpp, w, h, spec["fill"],
                       spec.get("height_alpha", 0))
        if "outline" in spec:
            edges = layer.getchannel("A").point(lambda a: 255 if a > 0 else 0).filter(ImageFilter.FIND_EDGES)
            outline = Image.new("RGBA", (w, h), spec["outline"])
            outline.putalpha(ImageChops.multiply(edges, Image.new("L", (w, h), spec["outline"][3])))
            layer = Image.alpha_composite(layer, outline)
        if "glow" in spec:
            radius = max(1.0, 6.0 / grid.mpp)
            glow = Image.new("RGBA", (w, h), spec["glow"])
            glow.putalpha(layer.getchannel("A").filter(ImageFilter.GaussianBlur(radius))
                          .point(lambda a: min(255, a * spec["glow"][3] // 255 * 2)))
            layer = Image.alpha_composite(glow, layer)
        out = Image.alpha_composite(out, layer)
    return out


def slice_tiles(img: Image.Image, grid: LevelGrid) -> dict[tuple[int, int], Image.Image]:
    tiles: dict[tuple[int, int], Image.Image] = {}
    t = grid.tile
    for iy in range(grid.ny):
        for ix in range(grid.nx):
            tile = img.crop((ix * t, iy * t, (ix + 1) * t, (iy + 1) * t))
            if tile.getchannel("A").getextrema()[1] > 0:
                tiles[(ix, iy)] = tile
    return tiles
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd tools/tiles && python3 -m pytest -q`
Expected: all pass (12).

- [ ] **Step 5: Commit**

```bash
git add tools/tiles
git commit -m "Tile pipeline: hologram rasterizer, level grid, tile slicing"
```

---

### Task 4: Calibration (mesh → world fit and gate)

**Files:**
- Create: `tools/tiles/nmtiles/calib.py`, `tests/test_calib.py`

**Interfaces:**
- Consumes: `Mesh`, `Transform` (Task 2), `rasterize_mask` (Task 3).
- Produces:
  - `parse_gamelog(text: str) -> list[tuple[str, float, float]]` (last occurrence per name wins)
  - `fit(points_xy: np.ndarray[N,2], road_meshes: list[Mesh], search=50.0, step=2.0, mpp=2.0) -> tuple[Transform, float]`
  - `GATE_METERS = 15.0`
  - CLI: `python3 -m nmtiles.calib --gamelog PATH --meshes DIR [--out calibration.json]` (exit 1 when the gate fails)
- The game writes `[NightMap] CALIB|<name>|<x>|<y>|<z>` lines (Task 15).

- [ ] **Step 1: Write failing tests**

`tools/tiles/tests/test_calib.py`:
```python
import numpy as np

from nmtiles.calib import GATE_METERS, fit, parse_gamelog
from nmtiles.glb import Mesh
from tests.glbutil import square


def _road(x0, y0, x1, y1):
    pos, idx = square(x0, -y1, x1, -y0)
    return Mesh("r", np.array(pos, float), np.array(idx, np.int64))


# Small 4x4 m markers at road intersections: unlike long strips, they pin the offset on both axes.
CROSSINGS = [(x, y) for x in (0, 250, 500, 750, 1000) for y in (0, 200, 400, 600)]
ROADS = [_road(x - 2, y - 2, x + 2, y + 2) for x, y in CROSSINGS]


def test_parse_gamelog_keeps_last_per_name():
    text = "\n".join([
        "[2026-10-11 10:00:00 UTC-03:00] [1] [NightMap] CALIB|Corpo Plaza|-1520.5|120.25|7.0",
        "[2026-10-11 10:00:00 UTC-03:00] [1] [Other] CALIB|ignored|1|2|3",
        "[2026-10-11 10:00:01 UTC-03:00] [1] [NightMap] CALIB|Corpo Plaza|-1521.0|121.0|7.0",
        "[2026-10-11 10:00:01 UTC-03:00] [1] [NightMap] CALIB|Kabuki|10|-20|0",
    ])
    assert parse_gamelog(text) == [("Corpo Plaza", -1521.0, 121.0), ("Kabuki", 10.0, -20.0)]


def test_fit_recovers_offset_of_points_near_roads():
    rng = np.random.default_rng(1)
    true_offset = np.array([12.0, -6.0])          # world = mesh + offset
    pts = np.array(CROSSINGS, float) + true_offset + rng.normal(0, 0.5, (len(CROSSINGS), 2))
    tf, median = fit(pts, ROADS, search=30.0, step=2.0, mpp=2.0)
    assert (tf.sx, tf.sy) == (1.0, -1.0)
    assert abs(tf.dx - 12.0) <= 3.0 and abs(tf.dy + 6.0) <= 3.0
    assert median <= GATE_METERS


def test_fit_reports_large_median_for_points_unrelated_to_roads():
    pts = np.array([[5000.0 + i * 37.0, 9000.0 - i * 53.0] for i in range(30)])
    _, median = fit(pts, ROADS, search=10.0, step=5.0, mpp=4.0)
    assert median > GATE_METERS
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_calib.py`
Expected: `ModuleNotFoundError: No module named 'nmtiles.calib'`.

- [ ] **Step 3: Implement**

`tools/tiles/nmtiles/calib.py`:
```python
"""Fit the mesh->world transform from in-game fast-travel positions (they sit beside roads)."""
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

import numpy as np
from scipy.ndimage import distance_transform_edt

from nmtiles.export import style_for
from nmtiles.glb import Mesh, keep_best_lod, read_glb
from nmtiles.render import rasterize_mask
from nmtiles.world import Transform

GATE_METERS = 15.0
_LINE = re.compile(r"\[NightMap\] CALIB\|(?P<name>[^|]*)\|(?P<x>-?[\d.]+)\|(?P<y>-?[\d.]+)\|(?P<z>-?[\d.]+)")
_SIGNS = [(1.0, -1.0), (1.0, 1.0), (-1.0, -1.0), (-1.0, 1.0)]


def parse_gamelog(text: str) -> list[tuple[str, float, float]]:
    found: dict[str, tuple[float, float]] = {}
    for line in text.splitlines():
        m = _LINE.search(line)
        if m:
            found.pop(m["name"], None)
            found[m["name"]] = (float(m["x"]), float(m["y"]))
    return [(n, x, y) for n, (x, y) in found.items()]


def fit(points_xy: np.ndarray, road_meshes: list[Mesh], search: float = 50.0, step: float = 2.0,
        mpp: float = 2.0) -> tuple[Transform, float]:
    best_tf, best_med = Transform(), math.inf
    offs = np.arange(-search, search + step / 2, step)
    for sx, sy in _SIGNS:
        base = Transform(sx, sy, 0.0, 0.0)
        world = np.vstack([base.apply(m.positions) for m in road_meshes])
        pad = search + 50.0
        minx = min(world[:, 0].min(), points_xy[:, 0].min()) - pad
        maxx = max(world[:, 0].max(), points_xy[:, 0].max()) + pad
        miny = min(world[:, 1].min(), points_xy[:, 1].min()) - pad
        maxy = max(world[:, 1].max(), points_xy[:, 1].max()) + pad
        w, h = int(math.ceil((maxx - minx) / mpp)), int(math.ceil((maxy - miny) / mpp))
        mask = rasterize_mask(road_meshes, base, minx, maxy, mpp, w, h)
        dist = distance_transform_edt(~mask) * mpp
        for dx in offs:
            for dy in offs:
                # mesh shifted by (dx,dy) == points shifted by (-dx,-dy)
                col = np.clip(((points_xy[:, 0] - dx - minx) / mpp).astype(int), 0, w - 1)
                row = np.clip(((maxy - (points_xy[:, 1] - dy)) / mpp).astype(int), 0, h - 1)
                med = float(np.median(dist[row, col]))
                if med < best_med:
                    best_med, best_tf = med, Transform(sx, sy, float(dx), float(dy))
    return best_tf, best_med


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--gamelog", type=Path,
                    default=Path.home() / "cyberpunk_symlink/bin/x64/plugins/cyber_engine_tweaks/gamelog.log")
    ap.add_argument("--meshes", type=Path, default=Path("build/meshes"))
    ap.add_argument("--out", type=Path, default=Path("calibration.json"))
    args = ap.parse_args(argv)
    pts = parse_gamelog(args.gamelog.read_text(errors="replace"))
    if len(pts) < 10:
        print(f"need >= 10 CALIB points, found {len(pts)} (Alt+\\ in game with Debug on)")
        return 1
    roads = [m for p in sorted(args.meshes.rglob("*.glb")) if style_for(p.stem) in ("road", "road_border")
             for m in keep_best_lod(read_glb(p))]
    tf, med = fit(np.array([[x, y] for _, x, y in pts]), roads)
    print(f"points={len(pts)} best={tf} median_road_distance={med:.1f} m (gate {GATE_METERS} m)")
    if med > GATE_METERS:
        print("CALIBRATION FAILED: fast-travel points do not sit near the roads under any tried transform")
        return 1
    tf.save(args.out)
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd tools/tiles && python3 -m pytest -q`
Expected: all pass (15).

- [ ] **Step 5: Commit**

```bash
git add tools/tiles
git commit -m "Tile pipeline: calibration fit against fast-travel points with 15 m gate"
```

---

### Task 5: UI atlas (hex chips, clusters, crosshair ring, player arrow, brackets, glyphs)

**Files:**
- Create: `tools/tiles/nmtiles/ui_atlas.py`, `tests/test_ui_atlas.py`

**Interfaces:**
- Produces: `build_ui_atlas() -> tuple[PIL.Image (1024x1024 RGBA), dict[str, tuple[int, int, int, int]]]` (part → left, top, right, bottom in px), and `SIZES: dict[str, int]` (square part sizes in 4K HUD units). Part names, with sizes that `NMTheme` (Task 8) must match exactly:

| part | size | part | size |
|---|---|---|---|
| `chip` | 112 | `ring` | 216 |
| `chip_sel` | 136 | `player` | 112 |
| `cluster` | 176 | `bracket_tl/tr/bl/br` | 110 |
| `cluster_sel` | 200 | `icon_quest/gig/vendor/ft/undisc/dot` | 48 |
| `mini` | 80 | | |

All parts are white (tinted at runtime). Hex fills are white at 16% value and 92% alpha; strokes are pure white.

- [ ] **Step 1: Write failing tests**

`tools/tiles/tests/test_ui_atlas.py`:
```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_ui_atlas.py`
Expected: `ModuleNotFoundError: No module named 'nmtiles.ui_atlas'`.

- [ ] **Step 3: Implement**

`tools/tiles/nmtiles/ui_atlas.py`:
```python
"""Procedural white UI atlas (tinted in game). Sizes are 4K HUD units and must match NMTheme."""
from __future__ import annotations

import math

from PIL import Image, ImageDraw, ImageFilter

SS = 4  # supersampling factor
SIZES = {
    "chip": 112, "chip_sel": 136, "cluster": 176, "cluster_sel": 200, "mini": 80,
    "ring": 216, "player": 112,
    "bracket_tl": 110, "bracket_tr": 110, "bracket_bl": 110, "bracket_br": 110,
    "icon_quest": 48, "icon_gig": 48, "icon_vendor": 48, "icon_ft": 48, "icon_undisc": 48, "icon_dot": 48,
}
# hex radius / stroke width per hex part (4K units)
_HEX = {"chip": (48, 5), "chip_sel": (60, 7), "cluster": (79, 6), "cluster_sel": (91, 7), "mini": (34, 4)}
_FILL = (41, 41, 41, 235)     # white * 0.16 value, 92% alpha -> tinted dark fill
_WHITE = (255, 255, 255, 255)


def _hex_points(cx: float, cy: float, r: float) -> list[tuple[float, float]]:
    return [(cx + r * math.cos(math.radians(60 * i + 30)), cy + r * math.sin(math.radians(60 * i + 30)))
            for i in range(6)]  # pointy-top: vertices at 90 and 270 degrees


def _canvas(size: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def _down(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def _hex(size: int, r: int, stroke: int) -> Image.Image:
    img, d = _canvas(size)
    c = size * SS / 2
    d.polygon(_hex_points(c, c, r * SS), fill=_FILL)
    pts = _hex_points(c, c, (r - stroke / 2) * SS)
    d.line(pts + [pts[0]], fill=_WHITE, width=stroke * SS, joint="curve")
    return _down(img, size)


def _glow(img: Image.Image, radius: float) -> Image.Image:
    halo = img.filter(ImageFilter.GaussianBlur(radius))
    return Image.alpha_composite(halo, img)


def _ring(size: int) -> Image.Image:
    img, d = _canvas(size)
    c, r, w = size * SS / 2, 96 * SS, 5 * SS
    d.ellipse((c - r, c - r, c + r, c + r), outline=_WHITE, width=w)
    return _glow(_down(img, size), 3)


def _player(size: int) -> Image.Image:
    img, d = _canvas(size)
    c = size * SS / 2
    d.ellipse((c - 52 * SS, c - 52 * SS, c + 52 * SS, c + 52 * SS), fill=(255, 255, 255, 46))
    k = SS
    d.polygon([(c, c - 40 * k), (c + 26 * k, c + 29 * k), (c, c + 12 * k), (c - 26 * k, c + 29 * k)], fill=_WHITE)
    return _down(img, size)


def _bracket(size: int, corner: str) -> Image.Image:
    img, d = _canvas(size)
    s, t, pad = size * SS, 9 * SS, 8 * SS
    d.rectangle((pad, pad, s - pad, pad + t), fill=_WHITE)       # horizontal arm (top-left form)
    d.rectangle((pad, pad, pad + t, s - pad), fill=_WHITE)       # vertical arm
    img = _glow(_down(img, size), 3)
    if corner == "tr":
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    elif corner == "bl":
        img = img.transpose(Image.FLIP_TOP_BOTTOM)
    elif corner == "br":
        img = img.transpose(Image.ROTATE_180)
    return img


def _icon(size: int, kind: str) -> Image.Image:
    img, d = _canvas(size)
    k = SS * size / 24.0   # glyphs authored on a 24-unit box centred at (12,12)
    w = int(2.4 * k)

    def P(x, y):
        return (x * k, y * k)

    if kind == "quest":
        d.polygon([P(12, 3), P(21, 12), P(12, 21), P(3, 12)], outline=_WHITE, width=w)
        d.line([P(12, 8), P(12, 13)], fill=_WHITE, width=w)
        d.ellipse((11 * k, 15.5 * k, 13 * k, 17.5 * k), fill=_WHITE)
    elif kind == "gig":
        d.rectangle((4 * k, 8 * k, 20 * k, 19 * k), outline=_WHITE, width=w)
        d.line([P(8, 8), P(8, 5), P(16, 5), P(16, 8)], fill=_WHITE, width=w)
    elif kind == "vendor":
        d.polygon([P(4, 9), P(20, 9), P(18, 20), P(6, 20)], outline=_WHITE, width=w)
        d.arc((8 * k, 3 * k, 16 * k, 13 * k), 180, 360, fill=_WHITE, width=w)
    elif kind == "ft":
        d.line([P(4, 9), P(18, 9)], fill=_WHITE, width=w)
        d.line([P(15, 6), P(18, 9), P(15, 12)], fill=_WHITE, width=w)
        d.line([P(20, 15), P(6, 15)], fill=_WHITE, width=w)
        d.line([P(9, 12), P(6, 15), P(9, 18)], fill=_WHITE, width=w)
    elif kind == "undisc":
        d.arc((7 * k, 3 * k, 17 * k, 13 * k), 180, 60, fill=_WHITE, width=w)
        d.line([P(12, 12), P(12, 15)], fill=_WHITE, width=w)
        d.ellipse((11 * k, 18 * k, 13 * k, 20 * k), fill=_WHITE)
    else:  # dot
        d.ellipse((7 * k, 7 * k, 17 * k, 17 * k), fill=_WHITE)
    return _down(img, size)


def _render(name: str) -> Image.Image:
    size = SIZES[name]
    if name in _HEX:
        return _hex(size, *_HEX[name])
    if name == "ring":
        return _ring(size)
    if name == "player":
        return _player(size)
    if name.startswith("bracket_"):
        return _bracket(size, name.split("_")[1])
    return _icon(size, name.split("_", 1)[1])


def build_ui_atlas() -> tuple[Image.Image, dict[str, tuple[int, int, int, int]]]:
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    parts: dict[str, tuple[int, int, int, int]] = {}
    x = y = row_h = 0
    gap = 4
    for name in sorted(SIZES, key=lambda n: (-SIZES[n], n)):   # shelf packing, largest first
        s = SIZES[name]
        if x + s > 1024:
            x, y, row_h = 0, y + row_h + gap, 0
        if y + s > 1024:
            raise RuntimeError("UI atlas overflow")
        atlas.paste(_render(name), (x, y))
        parts[name] = (x, y, x + s, y + s)
        x += s + gap
        row_h = max(row_h, s)
    return atlas, parts
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd tools/tiles && python3 -m pytest -q`
Expected: all pass (19).

- [ ] **Step 5: Eyeball the atlas once**

Run: `cd tools/tiles && python3 -c "from nmtiles.ui_atlas import build_ui_atlas; build_ui_atlas()[0].save('build/ui_preview.png')"` (create `build/` first), then open `build/ui_preview.png` with the Read tool.
Expected: pointy-top hexes in four sizes, a ring, an arrow with a halo, four L brackets, six glyphs. Everything white.

- [ ] **Step 6: Commit**

```bash
git add tools/tiles
git commit -m "Tile pipeline: procedural UI atlas (hex chips, clusters, ring, arrow, brackets, glyphs)"
```

---

### Task 6: Texture encode, resource JSON, archive packing

**Files:**
- Create: `tools/tiles/nmtiles/encode.py`, `nmtiles/resources.py`, `nmtiles/pack.py`, `tools/tiles/templates/tile.xbm.json`, `tools/tiles/templates/atlas.inkatlas.json`, `tests/test_resources.py`

**Interfaces:**
- Produces:
  - `bc7_layout(w, h) -> tuple[int, int]` (rowPitch, slicePitch)
  - `make_xbm_json(template: dict, w: int, h: int, payload: bytes) -> dict`
  - `make_inkatlas_json(template: dict, xbm_depot: str, parts: dict[str, tuple[int,int,int,int]], w: int, h: int) -> dict`
  - `encode_bc7(pngs: list[Path], out_dir: Path) -> dict[Path, bytes]` (png → raw BC7 payload)
  - `pack_archive(workspace: Path, out_archive: Path, wolvenkit="WolvenKit.CLI") -> Path`
  - `write_resource(workspace: Path, depot_path: str, js: dict, wolvenkit="WolvenKit.CLI")` (writes `<depot>.json`, converts it, deletes the json)
  - Templates under `tools/tiles/templates/`.

- [ ] **Step 1: Create the two templates**

The xbm template starts from the hologram mod's known-good BC7 texture JSON. Its pixel data is cleared because every use overwrites it:

```bash
cd tools/tiles && mkdir -p templates && python3 -I -c "
import json
j=json.load(open('/home/pdp/cyberpunk_hologram_mod/templates/fx_holo_map.xbm.json'))
j['Data']['RootChunk']['renderTextureResource']['renderResourceBlobPC']['Data']['textureData']['Bytes']=''
j['Header']['ArchiveFileName']=''
json.dump(j,open('templates/tile.xbm.json','w'),indent=1)"
```

The inkatlas template comes from a vanilla atlas, reduced to one part per slot:

```bash
cd tools/tiles && G=$(readlink -f ~/cyberpunk_symlink) && T=$(mktemp -d) && \
WolvenKit.CLI extract "$G/archive/pc/content" -r 'common\\shapes\\atlas_shapes_sync\.inkatlas$' -o "$T" >/dev/null && \
WolvenKit.CLI convert serialize "$(find "$T" -name '*.inkatlas')" -o "$T" >/dev/null && \
python3 -I -c "
import json,sys,glob
j=json.load(open(glob.glob(sys.argv[1]+'/*.inkatlas.json')[0]))
r=j['Data']['RootChunk']
for e in r['slots']['Elements']:
    e['parts']=e['parts'][:1]; e['slices']=[]
j['Header']['ArchiveFileName']=''
json.dump(j,open('templates/atlas.inkatlas.json','w'),indent=1)" "$T" && rm -rf "$T"
```

Expected: both files exist. `grep -c inkTextureAtlasMapper templates/atlas.inkatlas.json` prints `3`.

- [ ] **Step 2: Write failing tests**

`tools/tiles/tests/test_resources.py`:
```python
import base64
import json
import os
from pathlib import Path

import pytest

from nmtiles.resources import bc7_layout, make_inkatlas_json, make_xbm_json

TPL = Path(__file__).resolve().parents[1] / "templates"


def _tpl(name):
    return json.loads((TPL / name).read_text())


def test_bc7_layout_matches_known_template_and_512():
    assert bc7_layout(1028, 1028) == (4112, 1056784)   # values in the hologram template
    assert bc7_layout(512, 512) == (2048, 262144)
    assert bc7_layout(1024, 1024) == (4096, 1048576)


def test_make_xbm_json_sets_size_mips_and_payload():
    payload = bytes(range(256)) * 1024                   # 262144 bytes
    j = make_xbm_json(_tpl("tile.xbm.json"), 512, 512, payload)
    r = j["Data"]["RootChunk"]
    hd = r["renderTextureResource"]["renderResourceBlobPC"]["Data"]["header"]
    assert (r["width"], r["height"]) == (512, 512)
    assert (hd["sizeInfo"]["width"], hd["sizeInfo"]["height"]) == (512, 512)
    assert len(hd["mipMapInfo"]) == 1
    assert hd["mipMapInfo"][0]["layout"] == {**hd["mipMapInfo"][0]["layout"], "rowPitch": 2048, "slicePitch": 262144}
    assert hd["textureInfo"]["mipCount"] == 1 and hd["textureInfo"]["textureDataSize"] == 262144
    assert r["setup"]["hasMipchain"] == 0 and r["setup"]["compression"] == "TCM_QualityColor"
    blob = r["renderTextureResource"]["renderResourceBlobPC"]["Data"]["textureData"]["Bytes"]
    assert base64.b64decode(blob) == payload
    assert j["Data"]["BuildVersion"] == 262144


def test_make_xbm_json_rejects_wrong_payload_size():
    with pytest.raises(ValueError):
        make_xbm_json(_tpl("tile.xbm.json"), 512, 512, b"\0" * 100)


def test_make_inkatlas_json_points_all_slots_at_texture_with_uv_parts():
    parts = {"full": (0, 0, 512, 512), "chip": (0, 0, 112, 112)}
    j = make_inkatlas_json(_tpl("atlas.inkatlas.json"), r"nightmap\tiles\L0\t_1_2.xbm", parts, 512, 512)
    slots = j["Data"]["RootChunk"]["slots"]["Elements"]
    assert len(slots) == 3
    for s in slots:
        assert s["texture"]["DepotPath"]["$value"] == r"nightmap\tiles\L0\t_1_2.xbm"
        names = [p["partName"]["$value"] for p in s["parts"]]
        assert names == ["full", "chip"]
        chip = s["parts"][1]["clippingRectInUVCoords"]
        assert (chip["Left"], chip["Top"], chip["Right"], chip["Bottom"]) == (0.0, 0.0, 112 / 512, 112 / 512)


@pytest.mark.slow
@pytest.mark.skipif(os.environ.get("NIGHTMAP_SLOW") != "1", reason="needs wine/texconv/WolvenKit")
def test_encode_write_pack_roundtrip(tmp_path):
    from PIL import Image

    from nmtiles.encode import encode_bc7
    from nmtiles.pack import pack_archive, write_resource
    png = tmp_path / "t.png"
    Image.new("RGBA", (512, 512), (10, 40, 55, 180)).save(png)
    payload = encode_bc7([png], tmp_path / "dds")[png]
    assert len(payload) == 262144
    ws = tmp_path / "ws"
    write_resource(ws, r"nightmap\test\t.xbm", make_xbm_json(_tpl("tile.xbm.json"), 512, 512, payload))
    write_resource(ws, r"nightmap\test\t.inkatlas",
                   make_inkatlas_json(_tpl("atlas.inkatlas.json"), r"nightmap\test\t.xbm", {"full": (0, 0, 512, 512)}, 512, 512))
    assert (ws / "nightmap/test/t.xbm").stat().st_size > 262144
    arc = pack_archive(ws, tmp_path / "out" / "Test.archive")
    assert arc.stat().st_size > 262144
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_resources.py`
Expected: `ModuleNotFoundError: No module named 'nmtiles.resources'`.

- [ ] **Step 4: Implement**

`tools/tiles/nmtiles/resources.py`:
```python
"""Generate WolvenKit JSON for CBitmapTexture (BC7, 1 mip) and inkTextureAtlas resources."""
from __future__ import annotations

import base64
import copy


def bc7_layout(w: int, h: int) -> tuple[int, int]:
    row = max(1, (w + 3) // 4) * 16
    return row, row * max(1, (h + 3) // 4)


def make_xbm_json(template: dict, w: int, h: int, payload: bytes) -> dict:
    row, size = bc7_layout(w, h)
    if len(payload) != size:
        raise ValueError(f"BC7 payload is {len(payload)} bytes, expected {size} for {w}x{h}")
    j = copy.deepcopy(template)
    j["Data"]["BuildVersion"] = size   # the template stores the data size here; mirror it
    r = j["Data"]["RootChunk"]
    r["width"], r["height"] = w, h
    blob = r["renderTextureResource"]["renderResourceBlobPC"]["Data"]
    hd = blob["header"]
    hd["sizeInfo"]["width"], hd["sizeInfo"]["height"] = w, h
    mip = copy.deepcopy(hd["mipMapInfo"][0])
    mip["layout"]["rowPitch"], mip["layout"]["slicePitch"] = row, size
    mip["placement"]["offset"], mip["placement"]["size"] = 0, size
    hd["mipMapInfo"] = [mip]
    ti = hd["textureInfo"]
    ti["mipCount"], ti["sliceSize"], ti["textureDataSize"] = 1, size, size
    blob["textureData"]["Bytes"] = base64.b64encode(payload).decode("ascii")
    r["setup"]["hasMipchain"] = 0
    r["setup"]["compression"] = "TCM_QualityColor"
    return j


def make_inkatlas_json(template: dict, xbm_depot: str, parts: dict[str, tuple[int, int, int, int]],
                       w: int, h: int) -> dict:
    j = copy.deepcopy(template)
    r = j["Data"]["RootChunk"]
    proto_slot = r["slots"]["Elements"][0]
    proto_part = proto_slot["parts"][0]
    mappers = []
    for name, (left, top, right, bottom) in parts.items():
        m = copy.deepcopy(proto_part)
        m["clippingRectInUVCoords"] = {"$type": "RectF", "Left": left / w, "Top": top / h,
                                       "Right": right / w, "Bottom": bottom / h}
        m["partName"] = {"$type": "CName", "$storage": "string", "$value": name}
        mappers.append(m)
    slots = []
    for _ in range(3):   # 4K, 1080p and 720p slots all use the same texture
        s = copy.deepcopy(proto_slot)
        s["texture"]["DepotPath"]["$value"] = xbm_depot
        s["texture"]["DepotPath"]["$storage"] = "string"
        s["parts"] = copy.deepcopy(mappers)
        s["slices"] = []
        slots.append(s)
    r["slots"]["Elements"] = slots
    return j
```

`tools/tiles/nmtiles/encode.py`:
```python
"""BC7 encoding with Microsoft texconv under Wine (CPU codec; the GPU path crashes under Wine)."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

TEXCONV = Path.home() / ".local/bin/texconv.exe"
DDS_DX10_HEADER = 148
BATCH = 48


def encode_bc7(pngs: list[Path], out_dir: Path) -> dict[Path, bytes]:
    out_dir.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "WINEDEBUG": "-all"}
    for i in range(0, len(pngs), BATCH):
        chunk = pngs[i:i + BATCH]
        subprocess.run(["wine", str(TEXCONV), "-nogpu", "-f", "BC7_UNORM", "-m", "1", "-y", "-o", str(out_dir),
                        *map(str, chunk)], check=True, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result: dict[Path, bytes] = {}
    for png in pngs:
        dds = (out_dir / png.with_suffix(".dds").name).read_bytes()
        if dds[:4] != b"DDS ":
            raise RuntimeError(f"texconv wrote no DDS for {png}")
        result[png] = dds[DDS_DX10_HEADER:]
    return result
```

`tools/tiles/nmtiles/pack.py`:
```python
"""Turn WolvenKit JSON into CR2W resources and pack them into an .archive."""
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path


def write_resource(workspace: Path, depot_path: str, js: dict, wolvenkit: str = "WolvenKit.CLI") -> Path:
    target = workspace / Path(*depot_path.split("\\"))
    target.parent.mkdir(parents=True, exist_ok=True)
    jpath = target.with_name(target.name + ".json")
    jpath.write_text(json.dumps(js))
    subprocess.run([wolvenkit, "convert", "d", str(jpath)], check=True, cwd=workspace.parent,
                   stdout=subprocess.DEVNULL)
    jpath.unlink()
    if not target.is_file():
        raise RuntimeError(f"WolvenKit did not produce {target}")
    return target


def pack_archive(workspace: Path, out_archive: Path, wolvenkit: str = "WolvenKit.CLI") -> Path:
    out_dir = out_archive.parent / "_pack"
    shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True)
    subprocess.run([wolvenkit, "pack", str(workspace), "-o", str(out_dir)], check=True, stdout=subprocess.DEVNULL)
    produced = out_dir / f"{workspace.name}.archive"
    if not produced.is_file() or produced.stat().st_size == 0:
        raise RuntimeError("wolvenkit pack produced no archive")
    out_archive.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(produced, out_archive)
    shutil.rmtree(out_dir)
    return out_archive
```

- [ ] **Step 5: Run tests (fast, then slow)**

Run: `cd tools/tiles && python3 -m pytest -q`
Expected: all pass, with the slow test skipped.

Run: `cd tools/tiles && NIGHTMAP_SLOW=1 python3 -m pytest -q -m slow`
Expected: `1 passed` (about 30–60 s).

- [ ] **Step 6: Commit**

```bash
git add tools/tiles
git commit -m "Tile pipeline: BC7 encode (texconv/Wine), xbm+inkatlas JSON, archive packing"
```

---

### Task 7: Manifest emitter and end-to-end build

**Files:**
- Create: `tools/tiles/nmtiles/manifest.py`, `nmtiles/build.py`, `tests/test_manifest.py`, `r6/scripts/NightMap/Generated/TileManifest.reds` (generated, committed)

**Interfaces:**
- Consumes: everything from Tasks 2–6.
- Produces:
  - **Redscript class `NMTileManifest`** (the contract for Task 12):
    ```swift
    public abstract class NMTileManifest {
        public static func Available() -> Bool
        public static func SourceGameVersion() -> String
        public static func LevelCount() -> Int32
        public static func LevelMpp(i: Int32) -> Float        // ascending: 2, 4, 8, 16
        public static func LevelOriginX(i: Int32) -> Float
        public static func LevelOriginTop(i: Int32) -> Float
        public static func LevelNx(i: Int32) -> Int32
        public static func LevelNy(i: Int32) -> Int32
        public static func LevelTiles(i: Int32) -> array<Int32>  // present tiles as iy * nx + ix
        public static func WorldMinX() -> Float   // + WorldMinY/WorldMaxX/WorldMaxY
    }
    ```
  - **Depot paths:** tiles at `nightmap\tiles\L{i}\t_{ix}_{iy}.inkatlas` (part `full`); UI atlas at `nightmap\ui\ui.inkatlas`.
  - **Python:** `emit_manifest(levels: list[dict], world: tuple, game_version: str) -> str`; `emit_stub() -> str`.

- [ ] **Step 1: Write failing tests**

`tools/tiles/tests/test_manifest.py`:
```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd tools/tiles && python3 -m pytest -q tests/test_manifest.py`
Expected: `ModuleNotFoundError: No module named 'nmtiles.manifest'`.

- [ ] **Step 3: Implement the emitter**

`tools/tiles/nmtiles/manifest.py`:
```python
"""Emit r6/scripts/NightMap/Generated/TileManifest.reds."""
from __future__ import annotations


def _f(v: float) -> str:
    return f"{float(v):.1f}"


def _switch(name: str, ret: str, values: list[str], default: str) -> str:
    cases = "".join(f"            case {i}: return {v};\n" for i, v in enumerate(values))
    return (f"    public static func {name}(i: Int32) -> {ret} {{\n        switch i {{\n{cases}"
            f"            default: return {default};\n        }}\n    }}\n\n")


def _scalar(name: str, ret: str, value: str) -> str:
    return f"    public static func {name}() -> {ret} {{\n        return {value};\n    }}\n\n"


def emit_manifest(levels: list[dict], world: tuple[float, float, float, float], game_version: str) -> str:
    out = ["// GENERATED by tools/tiles (nmtiles.manifest) - do not edit.\nmodule NightMap\n\n",
           "public abstract class NMTileManifest {\n"]
    out.append(_scalar("Available", "Bool", "true"))
    out.append(_scalar("SourceGameVersion", "String", f'"{game_version}"'))
    out.append(_scalar("LevelCount", "Int32", str(len(levels))))
    out.append(_switch("LevelMpp", "Float", [_f(l["mpp"]) for l in levels], "0.0"))
    out.append(_switch("LevelOriginX", "Float", [_f(l["origin_x"]) for l in levels], "0.0"))
    out.append(_switch("LevelOriginTop", "Float", [_f(l["origin_top"]) for l in levels], "0.0"))
    out.append(_switch("LevelNx", "Int32", [str(l["nx"]) for l in levels], "0"))
    out.append(_switch("LevelNy", "Int32", [str(l["ny"]) for l in levels], "0"))
    cases = ""
    for i, l in enumerate(levels):
        idx = sorted(iy * l["nx"] + ix for ix, iy in l["tiles"])
        if idx:
            cases += f"            case {i}: return [{', '.join(map(str, idx))}];\n"
    out.append("    public static func LevelTiles(i: Int32) -> array<Int32> {\n        switch i {\n" + cases +
               "            default: break;\n        }\n        let empty: array<Int32>;\n        return empty;\n    }\n\n")
    for name, v in zip(("WorldMinX", "WorldMinY", "WorldMaxX", "WorldMaxY"), world):
        out.append(_scalar(name, "Float", _f(v)))
    out.append("}\n")
    return "".join(out)


def emit_stub() -> str:
    src = emit_manifest([], (-8000.0, -8000.0, 8000.0, 8000.0), "none")
    return src.replace("public static func Available() -> Bool {\n        return true;",
                       "public static func Available() -> Bool {\n        return false;")
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd tools/tiles && python3 -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Implement the build CLI**

`tools/tiles/nmtiles/build.py`:
```python
"""End-to-end tile build: meshes -> styled raster levels -> BC7 tiles + UI atlas -> NightMap.archive + manifest."""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import numpy as np

from nmtiles.encode import encode_bc7
from nmtiles.export import export_meshes, style_for
from nmtiles.glb import keep_best_lod, read_glb
from nmtiles.manifest import emit_manifest
from nmtiles.pack import pack_archive, write_resource
from nmtiles.render import level_grid, render_level, slice_tiles
from nmtiles.resources import make_inkatlas_json, make_xbm_json
from nmtiles.ui_atlas import build_ui_atlas
from nmtiles.world import Transform

HERE = Path(__file__).resolve().parents[1]
REPO = HERE.parents[1]
TPL = HERE / "templates"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--game", type=Path, default=Path.home() / "cyberpunk_symlink")
    ap.add_argument("--out", type=Path, default=HERE / "build")
    ap.add_argument("--levels", default="2,4,8,16")
    ap.add_argument("--skip-export", action="store_true", help="reuse build/meshes")
    ap.add_argument("--game-version", default="2.31")
    args = ap.parse_args(argv)
    game = args.game.resolve()
    out = args.out
    mesh_dir = out / "meshes"
    if not args.skip_export:
        shutil.rmtree(mesh_dir, ignore_errors=True)
        export_meshes(game, mesh_dir)

    styled: dict[str, list] = {}
    for p in sorted(mesh_dir.rglob("*.glb")):
        style = style_for(p.stem)
        if style:
            styled.setdefault(style, []).extend(keep_best_lod(read_glb(p)))
    tf = Transform.load(HERE / "calibration.json")
    world = np.vstack([tf.apply(m.positions) for s in ("land", "road", "building") for m in styled.get(s, [])])
    bounds = (float(world[:, 0].min()), float(world[:, 1].min()), float(world[:, 0].max()), float(world[:, 1].max()))
    print(f"styles={ {k: len(v) for k, v in styled.items()} } bounds={bounds} transform={tf}")

    png_dir = out / "png"
    shutil.rmtree(png_dir, ignore_errors=True)
    png_dir.mkdir(parents=True)
    levels, tile_pngs = [], []
    for li, mpp in enumerate(float(x) for x in args.levels.split(",")):
        grid = level_grid(bounds, mpp)
        tiles = slice_tiles(render_level(styled, tf, grid), grid)
        for (ix, iy), img in tiles.items():
            p = png_dir / f"L{li}_t_{ix}_{iy}.png"
            img.save(p)
            tile_pngs.append((li, ix, iy, p))
        levels.append({"mpp": mpp, "origin_x": grid.origin_x, "origin_top": grid.origin_top,
                       "nx": grid.nx, "ny": grid.ny, "tiles": sorted(tiles)})
        print(f"level {li}: {mpp} m/px grid {grid.nx}x{grid.ny} tiles={len(tiles)}")

    ui_img, ui_parts = build_ui_atlas()
    ui_png = png_dir / "ui.png"
    ui_img.save(ui_png)

    payloads = encode_bc7([p for *_, p in tile_pngs] + [ui_png], out / "dds")
    xbm_t = json.loads((TPL / "tile.xbm.json").read_text())
    atl_t = json.loads((TPL / "atlas.inkatlas.json").read_text())
    ws = out / "workspace"
    shutil.rmtree(ws, ignore_errors=True)
    for li, ix, iy, p in tile_pngs:
        base = f"nightmap\\tiles\\L{li}\\t_{ix}_{iy}"
        write_resource(ws, base + ".xbm", make_xbm_json(xbm_t, 512, 512, payloads[p]))
        write_resource(ws, base + ".inkatlas",
                       make_inkatlas_json(atl_t, base + ".xbm", {"full": (0, 0, 512, 512)}, 512, 512))
    write_resource(ws, "nightmap\\ui\\ui.xbm", make_xbm_json(xbm_t, 1024, 1024, payloads[ui_png]))
    write_resource(ws, "nightmap\\ui\\ui.inkatlas",
                   make_inkatlas_json(atl_t, "nightmap\\ui\\ui.xbm", ui_parts, 1024, 1024))

    archive = pack_archive(ws, REPO / "archive" / "pc" / "mod" / "NightMap.archive")
    manifest = REPO / "r6" / "scripts" / "NightMap" / "Generated" / "TileManifest.reds"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(emit_manifest(levels, bounds, args.game_version))
    mb = archive.stat().st_size / 1e6
    print(f"archive {archive} {mb:.1f} MB; manifest {manifest}")
    if mb > 60:
        print("WARNING: archive exceeds the 60 MB target")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 6: Run the real build**

Run: `cd tools/tiles && python3 -m nmtiles.build --game ~/cyberpunk_symlink`
Expected:
- 4 `level` lines (2 m/px with roughly 100–170 tiles)
- an `archive ... MB` line under 60 MB
- `r6/scripts/NightMap/Generated/TileManifest.reds` written

The run takes 5–20 minutes, with texconv as the slow part.

Then view one 2 m/px tile and one 16 m/px tile, e.g. `tools/tiles/build/png/L0_t_5_6.png` and `L3_t_0_0.png`, with the Read tool.
Expected: cyan road linework, faint building footprints, a pink metro line, water tint. North is up (Pacifica in the southwest, Badlands east).

- [ ] **Step 7: Compile check with the generated manifest**

Run: `tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 8: Commit**

```bash
git add tools/tiles r6/scripts/NightMap/Generated/TileManifest.reds
git commit -m "Tile pipeline: manifest emitter + end-to-end build; first generated manifest"
```

---

### Redscript testing model (read before Tasks 8–15)

Redscript only runs inside the game, so each runtime task uses this cycle:
1. **Write the test case** in `Debug/SelfTest.reds` (or the perf suite).
2. **Implement.**
3. **Run `tools/check.sh`.** This is the offline gate: type errors, unresolved functions and wrong signatures fail here.
4. **Commit.**

In-game execution of the self-tests (Ctrl+`\` with the Debug setting on) is batched into the two human checkpoints, Tasks 11 and 16, because each run needs a game restart. At a checkpoint, every `TEST|FAIL` line is a bug in the task that owns that case. Fix it there.

---

### Task 8: Theme, math, optional-module shims, camera, self-test harness

**Files:**
- Create: `r6/scripts/NightMap/Core/Theme.reds`, `Core/Math.reds`, `Core/Optional.reds`, `Core/Camera.reds`, `Debug/SelfTest.reds`

**Interfaces:**
- Consumes: `NMLog` (Task 1).
- Produces:
  - `NMTheme` static colors, fonts, `UiAtlas() -> ResRef` and sizes in 4K units (exact numbers below; they must match `ui_atlas.py SIZES`)
  - `NMRect.Create(minX, minY, maxX, maxY)` with `.Contains(x, y)`
  - `NMMath.HeadingDeg(fx, fy)`, `.NiceLength(maxMeters)`, `.FormatMeters(m)`, `.Lerp(a, b, t)`, `.EaseOut(t)`
  - `NMClock.NowMs() -> Float`, `NMClock.Precise() -> Bool`, `NMResolveImage(key: String) -> String`
  - `NMCamera` (fields `cx, cy, mpp, minMpp, maxMpp, viewW, viewH, follow, revision, bounds`) with methods:
    - `Create(viewW, viewH, bounds, minMpp, maxMpp)`
    - `WorldToMap(wx, wy) -> Vector2`, `MapToWorld(px, py) -> Vector2`
    - `VisibleRect(marginPx) -> ref<NMRect>`
    - `SetCenter(x, y)`, `SetMpp(m)`, `ZoomBy(factor)`, `PanPixels(dx, dy)`
    - `EaseTo(x, y, mpp, durMs)`, `IsEasing()`, `Tick(dtMs)`
  - `NMSelfTest` with `Run()`, `Check(name, ok, detail)`, `Near(a, b, eps)`

- [ ] **Step 1: Write the self-test harness with math and camera cases (the failing tests)**

`r6/scripts/NightMap/Debug/SelfTest.reds`:
```swift
module NightMap

// In-game assertions. Run with Ctrl + toggle key (Debug setting on). Output: [NightMap] TEST|PASS|... lines
// and a final TEST|SUMMARY|passed=N|failed=M line in CET's gamelog.log.
public class NMSelfTest {
    private let passed: Int32;
    private let failed: Int32;

    public func Run() {
        NMLog.Info("TEST|START");
        this.MathCases();
        this.CameraCases();
        NMLog.Info("TEST|SUMMARY|passed=" + ToString(this.passed) + "|failed=" + ToString(this.failed));
    }

    public func Check(name: String, ok: Bool, detail: String) {
        if ok {
            this.passed += 1;
            NMLog.Info("TEST|PASS|" + name);
        } else {
            this.failed += 1;
            NMLog.Info("TEST|FAIL|" + name + "|" + detail);
        }
    }

    public func Near(a: Float, b: Float, eps: Float) -> Bool {
        return AbsF(a - b) <= eps;
    }

    public func F(v: Float) -> String {
        return FloatToStringPrec(v, 3);
    }

    private func MathCases() {
        let a = AtanF(1.0, 0.0);
        this.Check("math.atan_order", this.Near(a, 1.5707963, 0.001), "AtanF(1,0)=" + this.F(a) + " (expected pi/2: AtanF(y,x))");
        this.Check("math.heading_north", this.Near(NMMath.HeadingDeg(0.0, 1.0), 0.0, 0.01), this.F(NMMath.HeadingDeg(0.0, 1.0)));
        this.Check("math.heading_east", this.Near(NMMath.HeadingDeg(1.0, 0.0), 90.0, 0.01), this.F(NMMath.HeadingDeg(1.0, 0.0)));
        this.Check("math.nice_length", NMMath.NiceLength(730.0) == 500.0 && NMMath.NiceLength(5.0) == 10.0, this.F(NMMath.NiceLength(730.0)));
        this.Check("math.format_meters", Equals(NMMath.FormatMeters(2000.0), "2 KM") && Equals(NMMath.FormatMeters(500.0), "500 M"),
            NMMath.FormatMeters(2000.0) + " / " + NMMath.FormatMeters(500.0));
        let r = NMRect.Create(0.0, 0.0, 10.0, 10.0);
        this.Check("math.rect_contains", r.Contains(10.0, 0.0) && !r.Contains(10.1, 0.0) && !r.Contains(5.0, -0.1), "");
    }

    private func CameraCases() {
        let b = NMRect.Create(-6000.0, -4600.0, 4600.0, 7400.0);
        let cam = NMCamera.Create(1880.0, 1480.0, b, 0.5, 16.0);
        cam.SetCenter(100.0, 200.0);
        let c = cam.WorldToMap(100.0, 200.0);
        this.Check("camera.center_maps_to_view_center", this.Near(c.X, 940.0, 0.01) && this.Near(c.Y, 740.0, 0.01), this.F(c.X) + "," + this.F(c.Y));
        let north = cam.WorldToMap(100.0, 300.0);
        this.Check("camera.north_up", north.Y < c.Y && this.Near(north.X, c.X, 0.01), this.F(north.Y));
        let ok = true;
        let mpps: array<Float> = [0.5, 2.0, 16.0];
        for m in mpps {
            cam.SetMpp(m);
            let p = cam.WorldToMap(-1234.5, 987.25);
            let w = cam.MapToWorld(p.X, p.Y);
            if !this.Near(w.X, -1234.5, 0.01) || !this.Near(w.Y, 987.25, 0.01) { ok = false; }
        }
        this.Check("camera.roundtrip", ok, "");
        cam.ZoomBy(100000.0);
        let zin = cam.mpp;
        cam.ZoomBy(0.000001);
        this.Check("camera.zoom_clamp", zin == 0.5 && cam.mpp == 16.0, this.F(zin) + "/" + this.F(cam.mpp));
        cam.SetCenter(99999.0, -99999.0);
        this.Check("camera.bounds_clamp", cam.cx == 4600.0 && cam.cy == -4600.0, this.F(cam.cx) + "," + this.F(cam.cy));
        cam.SetCenter(0.0, 0.0);
        cam.SetMpp(2.0);
        cam.follow = true;
        let rev = cam.revision;
        cam.PanPixels(10.0, 0.0);
        this.Check("camera.pan_disables_follow", !cam.follow && this.Near(cam.cx, 20.0, 0.01) && cam.revision > rev, this.F(cam.cx));
        cam.EaseTo(-500.0, 300.0, 4.0, 250.0);
        cam.Tick(100.0);
        let mid = cam.IsEasing();
        cam.Tick(200.0);
        this.Check("camera.ease_reaches_target", mid && !cam.IsEasing() && this.Near(cam.cx, -500.0, 0.01) && this.Near(cam.cy, 300.0, 0.01) && this.Near(cam.mpp, 4.0, 0.001),
            this.F(cam.cx) + "," + this.F(cam.cy) + "," + this.F(cam.mpp));
        let v = cam.VisibleRect(0.0);
        this.Check("camera.visible_rect", this.Near(v.maxX - v.minX, 1880.0 * 4.0, 0.1) && this.Near(v.maxY - v.minY, 1480.0 * 4.0, 0.1), "");
    }
}
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `tools/check.sh`
Expected: `COMPILE FAILED` with unresolved `NMMath`, `NMRect`, `NMCamera`.

- [ ] **Step 3: Implement**

`r6/scripts/NightMap/Core/Theme.reds`:
```swift
module NightMap

// Visual tokens. Sizes are 3840x2160 HUD units and MUST match tools/tiles/nmtiles/ui_atlas.py SIZES.
public abstract class NMTheme {
    public static func Cyan() -> HDRColor { return new HDRColor(0.478, 0.941, 1.0, 1.0); }
    public static func Text() -> HDRColor { return new HDRColor(0.784, 0.965, 1.0, 1.0); }
    public static func Pink() -> HDRColor { return new HDRColor(1.0, 0.310, 0.847, 1.0); }
    public static func Yellow() -> HDRColor { return new HDRColor(1.0, 0.878, 0.400, 1.0); }
    public static func Muted() -> HDRColor { return new HDRColor(0.667, 0.863, 0.922, 1.0); }
    public static func PanelBg() -> HDRColor { return new HDRColor(0.024, 0.078, 0.118, 1.0); }
    public static func CardBg() -> HDRColor { return new HDRColor(0.039, 0.157, 0.216, 1.0); }
    public static func CardOpacity() -> Float { return 0.5; }

    public static func HeadingFont() -> String { return "base\\gameplay\\gui\\fonts\\orbitron\\orbitron.inkfontfamily"; }
    public static func BodyFont() -> String { return "base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily"; }

    public static func UiAtlas() -> ResRef { return r"nightmap\\ui\\ui.inkatlas"; }

    public static func ChipSize() -> Float { return 112.0; }
    public static func ChipSelSize() -> Float { return 136.0; }
    public static func ClusterSize() -> Float { return 176.0; }
    public static func ClusterSelSize() -> Float { return 200.0; }
    public static func MiniSize() -> Float { return 80.0; }
    public static func IconSize() -> Float { return 48.0; }
    public static func RingSize() -> Float { return 216.0; }
    public static func PlayerSize() -> Float { return 112.0; }
    public static func BracketSize() -> Float { return 110.0; }
    public static func MiniOffsetY() -> Float { return -106.0; }
    public static func MiniSpacing() -> Float { return 67.0; }

    public static func HintHeight() -> Float { return 110.0; }
    public static func SelectRadius() -> Float { return 100.0; }
    public static func ClusterSpacing() -> Float { return 192.0; }
    public static func ChipBudget() -> Int32 { return 300; }
    public static func ClusterBudget() -> Int32 { return 80; }
    public static func MaxGlobalCategories() -> Int32 { return 64; }

    // 1.0 if ink rotates clockwise for positive angles; verified at Checkpoint 2.
    public static func PlayerRotationSign() -> Float { return 1.0; }
}
```

`r6/scripts/NightMap/Core/Math.reds`:
```swift
module NightMap

public class NMRect {
    public let minX: Float;
    public let minY: Float;
    public let maxX: Float;
    public let maxY: Float;

    public static func Create(minX: Float, minY: Float, maxX: Float, maxY: Float) -> ref<NMRect> {
        let r = new NMRect();
        r.minX = minX;
        r.minY = minY;
        r.maxX = maxX;
        r.maxY = maxY;
        return r;
    }

    public func Contains(x: Float, y: Float) -> Bool {
        return x >= this.minX && x <= this.maxX && y >= this.minY && y <= this.maxY;
    }
}

public abstract class NMMath {
    // Heading in degrees from a world forward vector: 0 = north (+Y), 90 = east (+X).
    public static func HeadingDeg(fx: Float, fy: Float) -> Float {
        return AtanF(fx, fy) * 57.2957795;
    }

    public static func NiceLength(maxMeters: Float) -> Float {
        let steps: array<Float> = [10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0];
        let best = 10.0;
        for s in steps {
            if s <= maxMeters {
                best = s;
            }
        }
        return best;
    }

    public static func FormatMeters(m: Float) -> String {
        if m >= 1000.0 {
            return FloatToStringPrec(m / 1000.0, 0) + " KM";
        }
        return FloatToStringPrec(m, 0) + " M";
    }

    public static func Lerp(a: Float, b: Float, t: Float) -> Float {
        return a + (b - a) * t;
    }

    public static func EaseOut(t: Float) -> Float {
        let u = 1.0 - t;
        return 1.0 - u * u;
    }
}
```

`r6/scripts/NightMap/Core/Optional.reds`:
```swift
module NightMap
@if(ModuleExists("RedIMGRetriever"))
import RedIMGRetriever.*

// Wall clock in ms. RedIMG's clock is precise; the fallback (EngineTime) only ticks every 31.25 ms.
public abstract class NMClock {
    public static func NowMs() -> Float {
        return NMClockNow();
    }

    public static func Precise() -> Bool {
        return NMClockPrecise();
    }
}

@if(ModuleExists("RedIMGRetriever"))
public func NMClockNow() -> Float {
    return RedIMG.NowMs();
}

@if(!ModuleExists("RedIMGRetriever"))
public func NMClockNow() -> Float {
    return EngineTime.ToFloat(GameInstance.GetEngineTime(GetGameInstance())) * 1000.0;
}

@if(ModuleExists("RedIMGRetriever"))
public func NMClockPrecise() -> Bool {
    return true;
}

@if(!ModuleExists("RedIMGRetriever"))
public func NMClockPrecise() -> Bool {
    return false;
}

// Image items: RedIMG key -> mounted atlas path ("" while loading or when RedIMG is absent).
@if(ModuleExists("RedIMGRetriever"))
public func NMResolveImage(key: String) -> String {
    return RedIMG.PrepareDocImage(key);
}

@if(!ModuleExists("RedIMGRetriever"))
public func NMResolveImage(key: String) -> String {
    return "";
}
```

`r6/scripts/NightMap/Core/Camera.reds`:
```swift
module NightMap

// North-up 2D camera. World meters <-> map-area units (window units). mpp = meters per unit.
public class NMCamera {
    public let cx: Float;
    public let cy: Float;
    public let mpp: Float;
    public let minMpp: Float;
    public let maxMpp: Float;
    public let viewW: Float;
    public let viewH: Float;
    public let follow: Bool;
    public let revision: Int32;
    public let bounds: ref<NMRect>;
    private let easing: Bool;
    private let e0x: Float;
    private let e0y: Float;
    private let e0m: Float;
    private let e1x: Float;
    private let e1y: Float;
    private let e1m: Float;
    private let eT: Float;
    private let eDur: Float;

    public static func Create(viewW: Float, viewH: Float, bounds: ref<NMRect>, minMpp: Float, maxMpp: Float) -> ref<NMCamera> {
        let c = new NMCamera();
        c.viewW = viewW;
        c.viewH = viewH;
        c.bounds = bounds;
        c.minMpp = minMpp;
        c.maxMpp = maxMpp;
        c.mpp = ClampF(4.0, minMpp, maxMpp);
        c.cx = (bounds.minX + bounds.maxX) * 0.5;
        c.cy = (bounds.minY + bounds.maxY) * 0.5;
        c.follow = true;
        return c;
    }

    public func WorldToMap(wx: Float, wy: Float) -> Vector2 {
        return new Vector2((wx - this.cx) / this.mpp + this.viewW * 0.5, (this.cy - wy) / this.mpp + this.viewH * 0.5);
    }

    public func MapToWorld(px: Float, py: Float) -> Vector2 {
        return new Vector2(this.cx + (px - this.viewW * 0.5) * this.mpp, this.cy - (py - this.viewH * 0.5) * this.mpp);
    }

    public func VisibleRect(marginPx: Float) -> ref<NMRect> {
        let hw = (this.viewW * 0.5 + marginPx) * this.mpp;
        let hh = (this.viewH * 0.5 + marginPx) * this.mpp;
        return NMRect.Create(this.cx - hw, this.cy - hh, this.cx + hw, this.cy + hh);
    }

    // The center stays inside the world bounds: at most half a view of empty space past the edge.
    public func SetCenter(x: Float, y: Float) {
        let nx = ClampF(x, this.bounds.minX, this.bounds.maxX);
        let ny = ClampF(y, this.bounds.minY, this.bounds.maxY);
        if nx != this.cx || ny != this.cy {
            this.cx = nx;
            this.cy = ny;
            this.revision += 1;
        }
    }

    public func SetMpp(m: Float) {
        let nm = ClampF(m, this.minMpp, this.maxMpp);
        if nm != this.mpp {
            this.mpp = nm;
            this.revision += 1;
        }
    }

    // factor > 1 zooms in.
    public func ZoomBy(factor: Float) {
        if factor > 0.0 {
            this.SetMpp(this.mpp / factor);
        }
    }

    public func PanPixels(dx: Float, dy: Float) {
        this.follow = false;
        this.easing = false;
        this.SetCenter(this.cx + dx * this.mpp, this.cy - dy * this.mpp);
    }

    public func EaseTo(x: Float, y: Float, m: Float, durMs: Float) {
        this.e0x = this.cx;
        this.e0y = this.cy;
        this.e0m = this.mpp;
        this.e1x = x;
        this.e1y = y;
        this.e1m = ClampF(m, this.minMpp, this.maxMpp);
        this.eT = 0.0;
        this.eDur = MaxF(durMs, 1.0);
        this.easing = true;
    }

    public func IsEasing() -> Bool {
        return this.easing;
    }

    public func Tick(dtMs: Float) {
        if !this.easing {
            return;
        }
        this.eT += dtMs;
        let t = MinF(this.eT / this.eDur, 1.0);
        let k = NMMath.EaseOut(t);
        this.SetMpp(NMMath.Lerp(this.e0m, this.e1m, k));
        this.SetCenter(NMMath.Lerp(this.e0x, this.e1x, k), NMMath.Lerp(this.e0y, this.e1y, k));
        if t >= 1.0 {
            this.easing = false;
        }
    }
}
```

- [ ] **Step 4: Run the compile check to verify it passes**

Run: `tools/check.sh`
Expected: `COMPILE OK`. If `@if` on the `import` line is rejected, move the `import` under a separate file guarded by `@if(ModuleExists("RedIMGRetriever"))` on each function, and reference `RedIMGRetriever.RedIMG` fully qualified; re-run.

- [ ] **Step 5: Commit**

```bash
git add r6/scripts/NightMap
git commit -m "Core: theme tokens, math, optional RedIMG shims, north-up camera, self-test harness"
```

---

### Task 9: Layer API with grid pyramid

**Files:**
- Create: `r6/scripts/NightMap/Api/Grid.reds`, `Api/NightMapItem.reds`, `Api/NightMapDetails.reds`, `Api/NightMapLayerListener.reds`, `Api/NightMapLayer.reds`, `Api/NightMap.reds`, `Core/NightMapSystem.reds` (minimal; extended in Task 10)
- Modify: `Debug/SelfTest.reds` (add `GridCases`, `ApiCases`)

**Interfaces:**
- Consumes: `NMRect`, `NMTheme`, `NMLog`, `NMTileManifest` (Task 7).
- Produces:
  - **`NMGrid`:** `OriginX()`/`OriginY()` (= -12000), `CellSize(level)` (250/1000/4000), `Side(level)` (96/24/6), `Base(level)` (0/9216/9792), `TotalCells()` (9828), `MaxCats()` (8), `CellIndex(level, x, y)`.
  - **`NightMapItem`:** `Create(pos: Vector4, category: CName, atlas: ResRef, part: CName)`, `Image(pos, category, imageKey: String)`, fluent `.WithLabel(String)`, `.WithTint(HDRColor)`, `.WithPriority(Int32)`.
  - **`NightMapDetails`:** `Create(category: String, title: String)`, fluent `.WithSubtitle`, `.AddRow(key, value)` (max 6), `.WithDescription`, `.AddAction(keyLabel, label)` (max 3). Fields `category, title, subtitle, description, rowKeys, rowValues, actionKeys, actionLabels`.
  - **`NightMapLayerListener`:** `GetDetails(id) -> ref<NightMapDetails>` (default null), `OnSelected(id)`, `OnActivated(id)`.
  - **`NightMapLayer`:**
    - API: `Add(item) -> Int32` (-1 on rejection), `Move(id, pos: Vector4) -> Bool`, `Remove(id) -> Bool`, `Clear()`, `SetVisible(Bool)`, `SetOpacity(Float)`, `SetZoomRange(minMpp, maxMpp)`, `SetClustering(Bool)`, `SetListener(ref<NightMapLayerListener>)`, `SetCategory(name, display, color)`, `IsAlive(id)`, `VisibleAt(mpp)`, `Position(id) -> Vector4`, `Label(id) -> String`, `CategoryOf(id) -> CName`.
    - Public fields used by the renderer: `id, index, priority, visible, opacity, clustering, listener, count, catGlobal, alive, px, py, cat, hasAtlas, atlas, part, image, imageResolved, hasTint, tint, label, head, cnt, sumX, sumY, tally, nextIn, cellOf`.
  - **`NightMap`:** `Create()`, `Get()`, `SetWorld(minX, minY, maxX, maxY)`, `InBounds(x, y)`, `CreateLayer(id, displayName, priority)`, `GetLayer(id)`, `RemoveLayer(id)`, `RegisterCategory(name, display, color, overwrite) -> Int32`, `SetCategoryIcon(name, atlas, part)`, `CategoryIndex(name)`, `Touch()`. Fields `layers, catNames, catDisplay, catColor, catHasIcon, catAtlas, catPart, revision, world`.
  - **`NightMapSystem`** (`ScriptableSystem`): `Api() -> ref<NightMap>`.

- [ ] **Step 1: Add the failing grid/API test cases**

In `Debug/SelfTest.reds`, change `Run()` to:
```swift
    public func Run() {
        NMLog.Info("TEST|START");
        this.MathCases();
        this.CameraCases();
        this.GridCases();
        this.ApiCases();
        NMLog.Info("TEST|SUMMARY|passed=" + ToString(this.passed) + "|failed=" + ToString(this.failed));
    }
```
and add these methods inside `NMSelfTest`:
```swift
    // Deterministic pseudo-random world coordinate in [-11000, 11000).
    private func Coord(i: Int32, mul: Int32) -> Float {
        return Cast<Float>((i * mul) % 22000 - 11000);
    }

    // Brute-force check of every pyramid level against the alive items.
    private func GridConsistent(L: ref<NightMapLayer>) -> String {
        let level = 0;
        while level < 3 {
            let base = NMGrid.Base(level);
            let n = NMGrid.Side(level) * NMGrid.Side(level);
            let cntB: array<Int32>;
            let sxB: array<Float>;
            ArrayResize(cntB, n);
            ArrayResize(sxB, n);
            let total = 0;
            let id = 0;
            while id < ArraySize(L.alive) {
                if L.alive[id] {
                    let c = NMGrid.CellIndex(level, L.px[id], L.py[id]);
                    if L.cellOf[id * 3 + level] != c { return "cellOf mismatch id=" + ToString(id) + " level=" + ToString(level); }
                    cntB[c - base] += 1;
                    sxB[c - base] += L.px[id];
                    // the item must be reachable from its cell's list head
                    let walk = L.head[c];
                    let found = false;
                    while walk >= 0 && !found {
                        if walk == id { found = true; }
                        walk = L.nextIn[walk * 3 + level];
                    }
                    if !found { return "id " + ToString(id) + " not linked at level " + ToString(level); }
                }
                id += 1;
            }
            let k = 0;
            while k < n {
                if L.cnt[base + k] != cntB[k] { return "count mismatch level=" + ToString(level) + " cell=" + ToString(k); }
                if AbsF(L.sumX[base + k] - sxB[k]) > 0.5 { return "sumX mismatch level=" + ToString(level) + " cell=" + ToString(k); }
                total += L.cnt[base + k];
                k += 1;
            }
            if total != L.count { return "total " + ToString(total) + " != count " + ToString(L.count); }
            level += 1;
        }
        return "";
    }

    private func GridCases() {
        let api = NightMap.Create();
        let L = api.CreateLayer(n"test.grid", "Grid test", 10);
        L.SetCategory(n"test.a", "A", NMTheme.Cyan());
        L.SetCategory(n"test.b", "B", NMTheme.Pink());
        let ids: array<Int32>;
        let i = 0;
        while i < 500 {
            let cat = i % 2 == 0 ? n"test.a" : n"test.b";
            ArrayPush(ids, L.Add(NightMapItem.Create(new Vector4(this.Coord(i, 7919), this.Coord(i, 104729), 0.0, 1.0), cat, r"base\\x.inkatlas", n"p")));
            i += 1;
        }
        this.Check("grid.add_count", L.count == 500 && ids[499] == 499, ToString(L.count));
        let err = this.GridConsistent(L);
        this.Check("grid.consistent_after_add", Equals(err, ""), err);
        let tallyA = 0;
        let c = 0;
        while c < 36 {
            tallyA += L.tally[(NMGrid.Base(2) + c) * NMGrid.MaxCats() + 0];
            c += 1;
        }
        this.Check("grid.tally_level2", tallyA == 250, ToString(tallyA));
        i = 0;
        while i < 100 {
            L.Move(ids[i], new Vector4(this.Coord(i + 900, 31), this.Coord(i + 900, 17), 0.0, 1.0));
            i += 1;
        }
        err = this.GridConsistent(L);
        this.Check("grid.consistent_after_move", Equals(err, ""), err);
        i = 100;
        while i < 200 {
            L.Remove(ids[i]);
            i += 1;
        }
        err = this.GridConsistent(L);
        this.Check("grid.consistent_after_remove", Equals(err, "") && L.count == 400, err);
        let reused = L.Add(NightMapItem.Create(new Vector4(0.0, 0.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
        this.Check("grid.id_recycled", reused >= 100 && reused < 200, ToString(reused));
        this.Check("grid.remove_twice_false", !L.Remove(ids[150]) && !L.Move(ids[150], new Vector4(0.0, 0.0, 0.0, 1.0)), "");
        // edges of the grid extent (world bounds default to the whole grid)
        let lo = L.Add(NightMapItem.Create(new Vector4(-12000.0, -12000.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
        let hi = L.Add(NightMapItem.Create(new Vector4(11999.0, 11999.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
        let out = L.Add(NightMapItem.Create(new Vector4(12000.0, 0.0, 0.0, 1.0), n"test.a", r"base\\x.inkatlas", n"p"));
        this.Check("grid.edges", lo >= 0 && hi >= 0 && out == -1, ToString(lo) + "/" + ToString(hi) + "/" + ToString(out));
        err = this.GridConsistent(L);
        this.Check("grid.consistent_at_edges", Equals(err, ""), err);
        L.Clear();
        let sum = 0;
        c = 0;
        while c < 36 {
            sum += L.cnt[NMGrid.Base(2) + c];
            c += 1;
        }
        this.Check("grid.clear", L.count == 0 && sum == 0, ToString(L.count));
    }

    private func ApiCases() {
        let api = NightMap.Create();
        api.SetWorld(-6000.0, -4600.0, 4600.0, 7400.0);
        let L = api.CreateLayer(n"test.api", "API test", 5);
        this.Check("api.create_layer_idempotent", api.CreateLayer(n"test.api", "again", 1) == L && ArraySize(api.layers) == 1, "");
        let inside = L.Add(NightMapItem.Create(new Vector4(5500.0, 0.0, 0.0, 1.0), n"x", r"base\\x.inkatlas", n"p"));
        let outside = L.Add(NightMapItem.Create(new Vector4(5700.0, 0.0, 0.0, 1.0), n"x", r"base\\x.inkatlas", n"p"));
        this.Check("api.world_bounds_plus_1km", inside >= 0 && outside == -1, ToString(inside) + "/" + ToString(outside));
        let i = 0;
        while i < 10 {
            L.Add(NightMapItem.Create(new Vector4(0.0, 0.0, 0.0, 1.0), StringToName("cat" + ToString(i)), r"base\\x.inkatlas", n"p"));
            i += 1;
        }
        this.Check("api.category_overflow_to_other", ArraySize(L.catNames) == NMGrid.MaxCats() && Equals(L.catNames[NMGrid.MaxCats() - 1], n"other"),
            ToString(ArraySize(L.catNames)));
        let g = api.CategoryIndex(n"x");
        this.Check("api.global_category", g >= 0 && Equals(api.catNames[g], n"x"), ToString(g));
        let rev = api.revision;
        L.SetOpacity(0.5);
        this.Check("api.revision_bumps", api.revision > rev && L.opacity == 0.5, "");
        let d = NightMapDetails.Create("GIG", "TITLE").AddRow("a", "1").AddRow("b", "2").AddRow("c", "3").AddRow("d", "4")
            .AddRow("e", "5").AddRow("f", "6").AddRow("g", "7").AddAction("K", "one").AddAction("K", "two").AddAction("K", "three").AddAction("K", "four");
        this.Check("api.details_caps", ArraySize(d.rowKeys) == 6 && ArraySize(d.actionKeys) == 3, "");
        api.RemoveLayer(n"test.api");
        this.Check("api.remove_layer", ArraySize(api.layers) == 0 && !IsDefined(api.GetLayer(n"test.api")), "");
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `tools/check.sh`
Expected: `COMPILE FAILED` (unresolved `NightMap`, `NightMapItem`, `NMGrid`, ...).

- [ ] **Step 3: Implement**

`r6/scripts/NightMap/Api/Grid.reds`:
```swift
module NightMap

// Fixed 24 km world grid pyramid shared by all layers. Level 0: 250 m (96x96), 1: 1 km (24x24), 2: 4 km (6x6).
// Cells of all levels live in one flat index space: Base(level) + gy * Side(level) + gx.
public abstract class NMGrid {
    public static func OriginX() -> Float { return -12000.0; }
    public static func OriginY() -> Float { return -12000.0; }
    public static func Levels() -> Int32 { return 3; }
    public static func TotalCells() -> Int32 { return 9828; }
    public static func MaxCats() -> Int32 { return 8; }

    public static func CellSize(level: Int32) -> Float {
        switch level {
            case 0: return 250.0;
            case 1: return 1000.0;
            default: return 4000.0;
        }
    }

    public static func Side(level: Int32) -> Int32 {
        switch level {
            case 0: return 96;
            case 1: return 24;
            default: return 6;
        }
    }

    public static func Base(level: Int32) -> Int32 {
        switch level {
            case 0: return 0;
            case 1: return 9216;
            default: return 9792;
        }
    }

    public static func CellIndex(level: Int32, x: Float, y: Float) -> Int32 {
        let cs = NMGrid.CellSize(level);
        let side = NMGrid.Side(level);
        let gx = Clamp(FloorF((x - NMGrid.OriginX()) / cs), 0, side - 1);
        let gy = Clamp(FloorF((y - NMGrid.OriginY()) / cs), 0, side - 1);
        return NMGrid.Base(level) + gy * side + gx;
    }
}
```

`r6/scripts/NightMap/Api/NightMapItem.reds`:
```swift
module NightMap

// A map item value. Positions are world meters (X east, Y north); Z is kept for future floor logic.
public class NightMapItem {
    public let x: Float;
    public let y: Float;
    public let z: Float;
    public let category: CName;
    public let hasAtlas: Bool;
    public let atlas: ResRef;
    public let part: CName;
    public let imageKey: String;
    public let hasTint: Bool;
    public let tint: HDRColor;
    public let label: String;
    public let priority: Int32;

    public static func Create(pos: Vector4, category: CName, atlas: ResRef, part: CName) -> ref<NightMapItem> {
        let it = new NightMapItem();
        it.x = pos.X;
        it.y = pos.Y;
        it.z = pos.Z;
        it.category = category;
        it.hasAtlas = true;
        it.atlas = atlas;
        it.part = part;
        return it;
    }

    // An item whose icon is a RedIMGRetriever image key (e.g. "shot://photo.png|max256x256").
    public static func Image(pos: Vector4, category: CName, imageKey: String) -> ref<NightMapItem> {
        let it = new NightMapItem();
        it.x = pos.X;
        it.y = pos.Y;
        it.z = pos.Z;
        it.category = category;
        it.imageKey = imageKey;
        return it;
    }

    public func WithLabel(label: String) -> ref<NightMapItem> {
        this.label = label;
        return this;
    }

    public func WithTint(color: HDRColor) -> ref<NightMapItem> {
        this.hasTint = true;
        this.tint = color;
        return this;
    }

    public func WithPriority(priority: Int32) -> ref<NightMapItem> {
        this.priority = priority;
        return this;
    }
}
```

`r6/scripts/NightMap/Api/NightMapDetails.reds`:
```swift
module NightMap

// Info-card payload returned by NightMapLayerListener.GetDetails.
public class NightMapDetails {
    public let category: String;
    public let title: String;
    public let subtitle: String;
    public let description: String;
    public let rowKeys: array<String>;
    public let rowValues: array<String>;
    public let actionKeys: array<String>;
    public let actionLabels: array<String>;

    public static func Create(category: String, title: String) -> ref<NightMapDetails> {
        let d = new NightMapDetails();
        d.category = category;
        d.title = title;
        return d;
    }

    public func WithSubtitle(s: String) -> ref<NightMapDetails> {
        this.subtitle = s;
        return this;
    }

    // At most 6 rows; extra rows are ignored.
    public func AddRow(key: String, value: String) -> ref<NightMapDetails> {
        if ArraySize(this.rowKeys) < 6 {
            ArrayPush(this.rowKeys, key);
            ArrayPush(this.rowValues, value);
        }
        return this;
    }

    public func WithDescription(s: String) -> ref<NightMapDetails> {
        this.description = s;
        return this;
    }

    // At most 3 actions; extra actions are ignored.
    public func AddAction(keyLabel: String, label: String) -> ref<NightMapDetails> {
        if ArraySize(this.actionKeys) < 3 {
            ArrayPush(this.actionKeys, keyLabel);
            ArrayPush(this.actionLabels, label);
        }
        return this;
    }
}
```

`r6/scripts/NightMap/Api/NightMapLayerListener.reds`:
```swift
module NightMap

// Subclass to react to selection/activation and to supply info-card content for a layer's items.
public abstract class NightMapLayerListener {
    public func GetDetails(id: Int32) -> ref<NightMapDetails> {
        return null;
    }

    public func OnSelected(id: Int32) {}

    public func OnActivated(id: Int32) {}
}
```

`r6/scripts/NightMap/Api/NightMapLayer.reds`:
```swift
module NightMap

// One source of map content. Items live in struct-of-arrays storage indexed by a stable id and are
// linked into the 3-level grid pyramid (NMGrid) so the renderer can aggregate by cell without scanning items.
public class NightMapLayer {
    public let id: CName;
    public let displayName: String;
    public let priority: Int32;
    public let index: Int32;
    public let visible: Bool = true;
    public let opacity: Float = 1.0;
    public let minMpp: Float = 0.0;
    public let maxMpp: Float = 100000.0;
    public let clustering: Bool = true;
    public let listener: ref<NightMapLayerListener>;
    public let revision: Int32;
    private let owner: wref<NightMap>;
    private let warned: array<String>;

    // local category slot -> global category index; the last slot is "other"
    public let catNames: array<CName>;
    public let catGlobal: array<Int32>;

    public let alive: array<Bool>;
    public let px: array<Float>;
    public let py: array<Float>;
    public let pz: array<Float>;
    public let cat: array<Int32>;
    public let hasAtlas: array<Bool>;
    public let atlas: array<ResRef>;
    public let part: array<CName>;
    public let image: array<String>;
    public let imageResolved: array<String>;
    public let hasTint: array<Bool>;
    public let tint: array<HDRColor>;
    public let label: array<String>;
    public let prio: array<Int32>;
    public let count: Int32;
    private let freeIds: array<Int32>;

    public let cellOf: array<Int32>;   // [id * 3 + level]
    public let nextIn: array<Int32>;   // [id * 3 + level]
    public let prevIn: array<Int32>;   // [id * 3 + level]
    public let head: array<Int32>;     // [cell]
    public let cnt: array<Int32>;      // [cell]
    public let sumX: array<Float>;     // [cell]
    public let sumY: array<Float>;     // [cell]
    public let tally: array<Int32>;    // [cell * MaxCats + local category]
    private let gridReady: Bool;

    public static func Create(owner: ref<NightMap>, id: CName, displayName: String, priority: Int32, index: Int32) -> ref<NightMapLayer> {
        let l = new NightMapLayer();
        l.owner = owner;
        l.id = id;
        l.displayName = displayName;
        l.priority = priority;
        l.index = index;
        return l;
    }

    // ---- public API -------------------------------------------------------------------------

    public func SetCategory(name: CName, display: String, color: HDRColor) {
        this.owner.RegisterCategory(name, display, color, true);
        this.LocalCat(name);
        this.Touch();
    }

    public func Add(item: ref<NightMapItem>) -> Int32 {
        if !IsDefined(item) {
            this.WarnOnce("null", "Add(null) ignored");
            return -1;
        }
        if !this.owner.InBounds(item.x, item.y) {
            this.WarnOnce("bounds", "item outside world bounds rejected (" + FloatToStringPrec(item.x, 0) + ", " + FloatToStringPrec(item.y, 0) + ")");
            return -1;
        }
        this.EnsureGrid();
        let id: Int32;
        if ArraySize(this.freeIds) > 0 {
            id = ArrayPop(this.freeIds);
        } else {
            id = ArraySize(this.alive);
            this.Grow();
        }
        this.alive[id] = true;
        this.px[id] = item.x;
        this.py[id] = item.y;
        this.pz[id] = item.z;
        this.cat[id] = this.LocalCat(item.category);
        this.hasAtlas[id] = item.hasAtlas;
        this.atlas[id] = item.atlas;
        this.part[id] = item.part;
        this.image[id] = item.imageKey;
        this.imageResolved[id] = "";
        this.hasTint[id] = item.hasTint;
        this.tint[id] = item.tint;
        this.label[id] = item.label;
        this.prio[id] = item.priority;
        this.Link(id);
        this.count += 1;
        this.Touch();
        return id;
    }

    public func Move(id: Int32, pos: Vector4) -> Bool {
        if !this.IsAlive(id) {
            return false;
        }
        if !this.owner.InBounds(pos.X, pos.Y) {
            this.WarnOnce("bounds", "move outside world bounds rejected");
            return false;
        }
        this.Unlink(id);
        this.px[id] = pos.X;
        this.py[id] = pos.Y;
        this.pz[id] = pos.Z;
        this.Link(id);
        this.Touch();
        return true;
    }

    public func Remove(id: Int32) -> Bool {
        if !this.IsAlive(id) {
            return false;
        }
        this.Unlink(id);
        this.alive[id] = false;
        ArrayPush(this.freeIds, id);
        this.count -= 1;
        this.Touch();
        return true;
    }

    public func Clear() {
        ArrayClear(this.alive);
        ArrayClear(this.px);
        ArrayClear(this.py);
        ArrayClear(this.pz);
        ArrayClear(this.cat);
        ArrayClear(this.hasAtlas);
        ArrayClear(this.atlas);
        ArrayClear(this.part);
        ArrayClear(this.image);
        ArrayClear(this.imageResolved);
        ArrayClear(this.hasTint);
        ArrayClear(this.tint);
        ArrayClear(this.label);
        ArrayClear(this.prio);
        ArrayClear(this.freeIds);
        ArrayClear(this.cellOf);
        ArrayClear(this.nextIn);
        ArrayClear(this.prevIn);
        this.count = 0;
        this.gridReady = false;
        this.EnsureGrid();
        this.Touch();
    }

    public func SetVisible(v: Bool) {
        this.visible = v;
        this.Touch();
    }

    public func SetOpacity(o: Float) {
        this.opacity = ClampF(o, 0.0, 1.0);
        this.Touch();
    }

    // Visible only while minMpp <= camera meters-per-unit <= maxMpp.
    public func SetZoomRange(minMpp: Float, maxMpp: Float) {
        this.minMpp = minMpp;
        this.maxMpp = maxMpp;
        this.Touch();
    }

    // Non-clustered layers always draw individual chips; keep them small (< 500 items).
    public func SetClustering(enabled: Bool) {
        this.clustering = enabled;
        this.Touch();
    }

    public func SetListener(l: ref<NightMapLayerListener>) {
        this.listener = l;
    }

    public func IsAlive(id: Int32) -> Bool {
        return id >= 0 && id < ArraySize(this.alive) && this.alive[id];
    }

    public func VisibleAt(mpp: Float) -> Bool {
        return this.visible && mpp >= this.minMpp && mpp <= this.maxMpp;
    }

    public func Position(id: Int32) -> Vector4 {
        return this.IsAlive(id) ? new Vector4(this.px[id], this.py[id], this.pz[id], 1.0) : new Vector4(0.0, 0.0, 0.0, 0.0);
    }

    public func Label(id: Int32) -> String {
        return this.IsAlive(id) ? this.label[id] : "";
    }

    public func CategoryOf(id: Int32) -> CName {
        return this.IsAlive(id) ? this.catNames[this.cat[id]] : n"";
    }

    // ---- internals --------------------------------------------------------------------------

    private func Touch() {
        this.revision += 1;
        this.owner.Touch();
    }

    private func WarnOnce(key: String, msg: String) {
        if !ArrayContains(this.warned, key) {
            ArrayPush(this.warned, key);
            NMLog.Error("layer " + NameToString(this.id) + ": " + msg);
        }
    }

    // Local category slot for a name; registers it globally with defaults if unseen.
    private func LocalCat(name: CName) -> Int32 {
        let i = 0;
        while i < ArraySize(this.catNames) {
            if Equals(this.catNames[i], name) {
                return i;
            }
            i += 1;
        }
        let max = NMGrid.MaxCats();
        if ArraySize(this.catNames) < max - 1 {
            ArrayPush(this.catNames, name);
            ArrayPush(this.catGlobal, this.owner.RegisterCategory(name, NameToString(name), NMTheme.Cyan(), false));
            return ArraySize(this.catNames) - 1;
        }
        if ArraySize(this.catNames) == max - 1 {
            ArrayPush(this.catNames, n"other");
            ArrayPush(this.catGlobal, this.owner.CategoryIndex(n"other"));
            this.WarnOnce("cats", "more than " + ToString(max - 1) + " categories; extra ones map to 'other'");
        }
        return max - 1;
    }

    private func EnsureGrid() {
        if this.gridReady {
            return;
        }
        let total = NMGrid.TotalCells();
        ArrayClear(this.head);
        ArrayClear(this.cnt);
        ArrayClear(this.sumX);
        ArrayClear(this.sumY);
        ArrayClear(this.tally);
        ArrayResize(this.head, total);
        ArrayResize(this.cnt, total);
        ArrayResize(this.sumX, total);
        ArrayResize(this.sumY, total);
        ArrayResize(this.tally, total * NMGrid.MaxCats());
        let c = 0;
        while c < total {
            this.head[c] = -1;
            c += 1;
        }
        this.gridReady = true;
    }

    private func Grow() {
        ArrayPush(this.alive, false);
        ArrayPush(this.px, 0.0);
        ArrayPush(this.py, 0.0);
        ArrayPush(this.pz, 0.0);
        ArrayPush(this.cat, 0);
        ArrayPush(this.hasAtlas, false);
        let emptyRef: ResRef;
        ArrayPush(this.atlas, emptyRef);
        ArrayPush(this.part, n"");
        ArrayPush(this.image, "");
        ArrayPush(this.imageResolved, "");
        ArrayPush(this.hasTint, false);
        ArrayPush(this.tint, new HDRColor(1.0, 1.0, 1.0, 1.0));
        ArrayPush(this.label, "");
        ArrayPush(this.prio, 0);
        let l = 0;
        while l < 3 {
            ArrayPush(this.cellOf, -1);
            ArrayPush(this.nextIn, -1);
            ArrayPush(this.prevIn, -1);
            l += 1;
        }
    }

    private func Link(id: Int32) {
        let l = 0;
        while l < 3 {
            let c = NMGrid.CellIndex(l, this.px[id], this.py[id]);
            let k = id * 3 + l;
            let h = this.head[c];
            this.cellOf[k] = c;
            this.nextIn[k] = h;
            this.prevIn[k] = -1;
            if h >= 0 {
                this.prevIn[h * 3 + l] = id;
            }
            this.head[c] = id;
            this.cnt[c] += 1;
            this.sumX[c] += this.px[id];
            this.sumY[c] += this.py[id];
            this.tally[c * NMGrid.MaxCats() + this.cat[id]] += 1;
            l += 1;
        }
    }

    private func Unlink(id: Int32) {
        let l = 0;
        while l < 3 {
            let k = id * 3 + l;
            let c = this.cellOf[k];
            let n = this.nextIn[k];
            let p = this.prevIn[k];
            if p >= 0 {
                this.nextIn[p * 3 + l] = n;
            } else {
                this.head[c] = n;
            }
            if n >= 0 {
                this.prevIn[n * 3 + l] = p;
            }
            this.cnt[c] -= 1;
            if this.cnt[c] == 0 {
                this.sumX[c] = 0.0;   // reset float drift
                this.sumY[c] = 0.0;
            } else {
                this.sumX[c] -= this.px[id];
                this.sumY[c] -= this.py[id];
            }
            this.tally[c * NMGrid.MaxCats() + this.cat[id]] -= 1;
            this.nextIn[k] = -1;
            this.prevIn[k] = -1;
            this.cellOf[k] = -1;
            l += 1;
        }
    }
}
```

`r6/scripts/NightMap/Api/NightMap.reds`:
```swift
module NightMap

// Public entry point: NightMap.Get() returns the live instance for the current session (null if not ready).
// Layers and categories are per session; create them again on Session/Ready.
public class NightMap {
    public let layers: array<ref<NightMapLayer>>;
    public let catNames: array<CName>;
    public let catDisplay: array<String>;
    public let catColor: array<HDRColor>;
    public let catHasIcon: array<Bool>;
    public let catAtlas: array<ResRef>;
    public let catPart: array<CName>;
    public let revision: Int32;
    public let world: ref<NMRect>;

    public static func Create() -> ref<NightMap> {
        let m = new NightMap();
        m.world = NMRect.Create(NMGrid.OriginX(), NMGrid.OriginY(), -NMGrid.OriginX() - 0.01, -NMGrid.OriginY() - 0.01);
        m.RegisterCategory(n"other", "OTHER", NMTheme.Muted(), false);
        return m;
    }

    public static func Get() -> ref<NightMap> {
        let sys = GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"NightMap.NightMapSystem") as NightMapSystem;
        return IsDefined(sys) ? sys.Api() : null;
    }

    // Items are accepted within the map's world bounds plus 1 km, never beyond the grid extent.
    public func SetWorld(minX: Float, minY: Float, maxX: Float, maxY: Float) {
        let gx0 = NMGrid.OriginX();
        let gy0 = NMGrid.OriginY();
        this.world = NMRect.Create(MaxF(minX - 1000.0, gx0), MaxF(minY - 1000.0, gy0),
            MinF(maxX + 1000.0, -gx0 - 0.01), MinF(maxY + 1000.0, -gy0 - 0.01));
    }

    public func InBounds(x: Float, y: Float) -> Bool {
        return this.world.Contains(x, y);
    }

    public func CreateLayer(id: CName, displayName: String, priority: Int32) -> ref<NightMapLayer> {
        let existing = this.GetLayer(id);
        if IsDefined(existing) {
            return existing;
        }
        let layer = NightMapLayer.Create(this, id, displayName, priority, ArraySize(this.layers));
        ArrayPush(this.layers, layer);
        this.Touch();
        return layer;
    }

    public func GetLayer(id: CName) -> ref<NightMapLayer> {
        for l in this.layers {
            if Equals(l.id, id) {
                return l;
            }
        }
        return null;
    }

    public func RemoveLayer(id: CName) {
        let i = 0;
        while i < ArraySize(this.layers) {
            if Equals(this.layers[i].id, id) {
                ArrayErase(this.layers, i);
                let k = 0;
                while k < ArraySize(this.layers) {
                    this.layers[k].index = k;
                    k += 1;
                }
                this.Touch();
                return;
            }
            i += 1;
        }
    }

    // Returns the global index. overwrite=false keeps an existing display name/color.
    public func RegisterCategory(name: CName, display: String, color: HDRColor, overwrite: Bool) -> Int32 {
        let i = this.CategoryIndex(name);
        if i >= 0 {
            if overwrite {
                this.catDisplay[i] = display;
                this.catColor[i] = color;
                this.Touch();
            }
            return i;
        }
        if ArraySize(this.catNames) >= NMTheme.MaxGlobalCategories() {
            NMLog.Error("more than " + ToString(NMTheme.MaxGlobalCategories()) + " categories; '" + NameToString(name) + "' maps to 'other'");
            return this.CategoryIndex(n"other");
        }
        ArrayPush(this.catNames, name);
        ArrayPush(this.catDisplay, display);
        ArrayPush(this.catColor, color);
        ArrayPush(this.catHasIcon, false);
        let emptyRef: ResRef;
        ArrayPush(this.catAtlas, emptyRef);
        ArrayPush(this.catPart, n"");
        this.Touch();
        return ArraySize(this.catNames) - 1;
    }

    // Default icon for items of this category that don't carry their own.
    public func SetCategoryIcon(name: CName, atlas: ResRef, part: CName) {
        let i = this.CategoryIndex(name);
        if i < 0 {
            i = this.RegisterCategory(name, NameToString(name), NMTheme.Cyan(), false);
        }
        this.catHasIcon[i] = true;
        this.catAtlas[i] = atlas;
        this.catPart[i] = part;
        this.Touch();
    }

    public func CategoryIndex(name: CName) -> Int32 {
        let i = 0;
        while i < ArraySize(this.catNames) {
            if Equals(this.catNames[i], name) {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    public func Touch() {
        this.revision += 1;
    }
}
```

`r6/scripts/NightMap/Core/NightMapSystem.reds` (minimal; Task 10 replaces it):
```swift
module NightMap

public class NightMapSystem extends ScriptableSystem {
    private let api: ref<NightMap>;

    private func OnAttach() {
        this.api = NightMap.Create();
    }

    public func Api() -> ref<NightMap> {
        return this.api;
    }
}
```

- [ ] **Step 4: Run the compile check to verify it passes**

Run: `tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 5: Commit**

```bash
git add r6/scripts/NightMap
git commit -m "API: NightMap/Layer/Item/Details/Listener with 3-level grid pyramid; grid self-tests"
```

---

### Task 10: Settings, input, panel, system lifecycle

**Files:**
- Create: `r6/scripts/NightMap/Core/Settings.reds`, `Core/Input.reds`, `Render/Ui.reds`, `Render/Panel.reds`
- Replace: `Core/NightMapSystem.reds`
- Modify: `Debug/SelfTest.reds` (add `InputCases`, `LayoutCases`)

**Interfaces:**
- Consumes: Tasks 7–9.
- Produces:
  - **`NightMapSettings`** (`ScriptableSystem`, Mod Settings): `keyToggle, keyPanUp, keyPanDown, keyPanLeft, keyPanRight, keyZoomIn, keyZoomOut, keyRecenter, keyAct: EInputKey`; `panelOpacity: Float`; `debug: Bool`; `NightMapSettings.Get(game)`.
  - **`NMInput`:**
    - `Handle(s, key, action, shift, ctrl, alt, mapOpen) -> Bool`, `PanVector() -> Vector2`, `ResetHeld()`, `NMInput.KeyName(key) -> String`, `NMInput.HintText(s) -> String`.
    - Flags: `toggle, recenter, act, zoomIn, zoomOut, debugSelfTest, debugPerf, debugCalib, debugLayer, arrowSeen`.
  - **`NMUi`:** `Canvas(parent, x, y, w, h)`, `Rect(parent, x, y, w, h, color, opacity)`, `Image(parent, part, x, y, size, color, centered)`, `Text(parent, font, style, size, color)`.
  - **`NMPanelLayout.Compute(winW, winH)`:** fields `winW, winH, scale, x, y, w, h, mapW, mapH, cardW, hintH`.
  - **`NMPanel.Build(window, layout, opacity)`:**
    - Fields: `root, mapContent, tiles, items, overlay, card, title, subtitle, warning, scaleBar, scaleLabel, hints, layout`.
    - Methods: `.Destroy(window)`, `.AddClipProbe()`.
  - **`NightMapSystem`:**
    - Methods: `Api()`, `IsOpen()`, `Camera()`, `Panel()`, `Open()`, `Close()`, `Tick()`.
    - Private hooks for later tasks: `OnOpened()`, `OnClosing()`, `UpdateModules(dt)`, `HandleDebug(s)`.

- [ ] **Step 1: Add the failing input/layout cases**

In `Debug/SelfTest.reds`, change `Run()` to also call `this.InputCases();` and `this.LayoutCases();` (after `ApiCases`), and add:
```swift
    private func InputCases() {
        let s = new NightMapSettings();
        let inp = new NMInput();
        let press = EInputAction.IACT_Press;
        let release = EInputAction.IACT_Release;
        this.Check("input.toggle", inp.Handle(s, EInputKey.IK_Backslash, press, false, false, false, false) && inp.toggle, "");
        inp.toggle = false;
        inp.Handle(s, EInputKey.IK_Backslash, press, false, true, false, false);
        this.Check("input.ctrl_toggle_is_selftest", inp.debugSelfTest && !inp.toggle, "");
        this.Check("input.ignored_when_closed", !inp.Handle(s, EInputKey.IK_NumPad8, press, false, false, false, false), "");
        let usedArrow = inp.Handle(s, EInputKey.IK_Up, press, false, false, false, true);
        let v0 = inp.PanVector();
        this.Check("input.arrows_never_pan", !usedArrow && v0.X == 0.0 && v0.Y == 0.0 && inp.arrowSeen, "");
        inp.Handle(s, EInputKey.IK_NumPad8, press, false, false, false, true);
        let v1 = inp.PanVector();
        inp.Handle(s, EInputKey.IK_NumPad8, release, false, false, false, true);
        let v2 = inp.PanVector();
        this.Check("input.numpad8_pans_up", v1.X == 0.0 && v1.Y == -1.0 && v2.Y == 0.0, this.F(v1.Y));
        inp.Handle(s, EInputKey.IK_NumPad9, press, false, false, false, true);
        let v3 = inp.PanVector();
        inp.ResetHeld();
        this.Check("input.numpad9_diagonal", v3.X == 1.0 && v3.Y == -1.0, this.F(v3.X) + "," + this.F(v3.Y));
        inp.Handle(s, EInputKey.IK_NumPlus, press, false, false, false, true);
        this.Check("input.zoom_held", inp.zoomIn && !inp.zoomOut, "");
        this.Check("input.key_names", Equals(NMInput.KeyName(EInputKey.IK_NumPad8), "NUM 8") && Equals(NMInput.KeyName(EInputKey.IK_Backslash), "\\")
            && Equals(NMInput.KeyName(EInputKey.IK_NumPlus), "NUM +"), NMInput.KeyName(EInputKey.IK_NumPad8));
    }

    private func LayoutCases() {
        let sizes: array<Vector2> = [new Vector2(3840.0, 2160.0), new Vector2(5120.0, 2160.0), new Vector2(2560.0, 1600.0), new Vector2(1920.0, 1080.0)];
        let ok = true;
        let detail = "";
        for sz in sizes {
            let l = NMPanelLayout.Compute(sz.X, sz.Y);
            let inside = l.x >= 0.0 && l.y >= 0.0 && l.x + l.w <= sz.X + 0.01 && l.y + l.h <= sz.Y + 0.01;
            let parts = l.mapW > 0.0 && l.mapH > 0.0 && l.cardW > 0.0 && this.Near(l.mapW, l.w * 0.70, 0.5);
            if !inside || !parts {
                ok = false;
                detail += this.F(sz.X) + "x" + this.F(sz.Y) + " ";
            }
        }
        this.Check("layout.fits_all_aspects", ok, detail);
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `tools/check.sh`
Expected: `COMPILE FAILED` (unresolved `NightMapSettings`, `NMInput`, `NMPanelLayout`).

- [ ] **Step 3: Implement settings and input**

`r6/scripts/NightMap/Core/Settings.reds`:
```swift
module NightMap

public class NightMapSettings extends ScriptableSystem {
    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Open / close map")
    @runtimeProperty("ModSettings.description", "Toggles the NightMap overlay. With Debug on: Ctrl = self-test, Shift = perf suite, Alt = calibration dump, Ctrl+Shift = debug layer.")
    public let keyToggle: EInputKey = EInputKey.IK_Backslash;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan up")
    @runtimeProperty("ModSettings.description", "Hold to pan north. Numpad 7/9/1/3 pan diagonally.")
    public let keyPanUp: EInputKey = EInputKey.IK_NumPad8;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan down")
    @runtimeProperty("ModSettings.description", "Hold to pan south.")
    public let keyPanDown: EInputKey = EInputKey.IK_NumPad2;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan left")
    @runtimeProperty("ModSettings.description", "Hold to pan west.")
    public let keyPanLeft: EInputKey = EInputKey.IK_NumPad4;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan right")
    @runtimeProperty("ModSettings.description", "Hold to pan east.")
    public let keyPanRight: EInputKey = EInputKey.IK_NumPad6;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Zoom in")
    @runtimeProperty("ModSettings.description", "Hold to zoom in.")
    public let keyZoomIn: EInputKey = EInputKey.IK_NumPlus;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Zoom out")
    @runtimeProperty("ModSettings.description", "Hold to zoom out.")
    public let keyZoomOut: EInputKey = EInputKey.IK_NumMinus;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Recenter on V")
    @runtimeProperty("ModSettings.description", "Centers the map on V and follows V again.")
    public let keyRecenter: EInputKey = EInputKey.IK_NumPad5;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Act on selection")
    @runtimeProperty("ModSettings.description", "Zooms into a selected cluster, or activates the selected item.")
    public let keyAct: EInputKey = EInputKey.IK_NumPad0;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Panel opacity")
    @runtimeProperty("ModSettings.description", "Background opacity of the map panel (applies on next open).")
    @runtimeProperty("ModSettings.step", "0.02")
    @runtimeProperty("ModSettings.min", "0.3")
    @runtimeProperty("ModSettings.max", "1.0")
    public let panelOpacity: Float = 0.74;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Debug")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Debug tools")
    @runtimeProperty("ModSettings.description", "Enables the debug key chords and the clip probe.")
    public let debug: Bool = false;

    private func OnAttach() {
        NightMapRegisterSettings(this);
    }

    private func OnDetach() {
        NightMapUnregisterSettings(this);
    }

    public static func Get(game: GameInstance) -> ref<NightMapSettings> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"NightMap.NightMapSettings") as NightMapSettings;
    }
}

@if(ModuleExists("ModSettingsModule"))
public func NightMapRegisterSettings(s: ref<NightMapSettings>) {
    ModSettings.RegisterListenerToClass(s);
}

@if(!ModuleExists("ModSettingsModule"))
public func NightMapRegisterSettings(s: ref<NightMapSettings>) {}

@if(ModuleExists("ModSettingsModule"))
public func NightMapUnregisterSettings(s: ref<NightMapSettings>) {
    ModSettings.UnregisterListenerToClass(s);
}

@if(!ModuleExists("ModSettingsModule"))
public func NightMapUnregisterSettings(s: ref<NightMapSettings>) {}
```

`r6/scripts/NightMap/Core/Input.reds`:
```swift
module NightMap

// Key state for the live overlay. Arrow keys are never used: they steer vehicles, and with NumLock off
// the numpad reports arrows, so seeing one sets arrowSeen (the hint bar then asks for NumLock).
public class NMInput {
    public let toggle: Bool;
    public let recenter: Bool;
    public let act: Bool;
    public let zoomIn: Bool;
    public let zoomOut: Bool;
    public let debugSelfTest: Bool;
    public let debugPerf: Bool;
    public let debugCalib: Bool;
    public let debugLayer: Bool;
    public let arrowSeen: Bool;
    private let up: Bool;
    private let down: Bool;
    private let left: Bool;
    private let right: Bool;
    private let d7: Bool;
    private let d9: Bool;
    private let d1: Bool;
    private let d3: Bool;

    // Returns true when NightMap uses the key.
    public func Handle(s: ref<NightMapSettings>, key: EInputKey, action: EInputAction, shift: Bool, ctrl: Bool, alt: Bool, mapOpen: Bool) -> Bool {
        let pressed = Equals(action, EInputAction.IACT_Press);
        let released = Equals(action, EInputAction.IACT_Release);
        if !pressed && !released {
            return false;
        }
        if Equals(key, s.keyToggle) {
            if pressed {
                if ctrl && shift {
                    this.debugLayer = true;
                } else if ctrl {
                    this.debugSelfTest = true;
                } else if shift {
                    this.debugPerf = true;
                } else if alt {
                    this.debugCalib = true;
                } else {
                    this.toggle = true;
                }
            }
            return true;
        }
        if !mapOpen {
            return false;
        }
        if Equals(key, EInputKey.IK_Up) || Equals(key, EInputKey.IK_Down) || Equals(key, EInputKey.IK_Left) || Equals(key, EInputKey.IK_Right) {
            if pressed {
                this.arrowSeen = true;
            }
            return false;
        }
        if Equals(key, s.keyPanUp) { this.up = pressed; return true; }
        if Equals(key, s.keyPanDown) { this.down = pressed; return true; }
        if Equals(key, s.keyPanLeft) { this.left = pressed; return true; }
        if Equals(key, s.keyPanRight) { this.right = pressed; return true; }
        if Equals(key, EInputKey.IK_NumPad7) { this.d7 = pressed; return true; }
        if Equals(key, EInputKey.IK_NumPad9) { this.d9 = pressed; return true; }
        if Equals(key, EInputKey.IK_NumPad1) { this.d1 = pressed; return true; }
        if Equals(key, EInputKey.IK_NumPad3) { this.d3 = pressed; return true; }
        if Equals(key, s.keyZoomIn) { this.zoomIn = pressed; return true; }
        if Equals(key, s.keyZoomOut) { this.zoomOut = pressed; return true; }
        if Equals(key, s.keyRecenter) {
            if pressed { this.recenter = true; }
            return true;
        }
        if Equals(key, s.keyAct) {
            if pressed { this.act = true; }
            return true;
        }
        return false;
    }

    // Unit pan direction in screen space (+Y = down/south).
    public func PanVector() -> Vector2 {
        let x = 0.0;
        let y = 0.0;
        if this.left || this.d7 || this.d1 { x -= 1.0; }
        if this.right || this.d9 || this.d3 { x += 1.0; }
        if this.up || this.d7 || this.d9 { y -= 1.0; }
        if this.down || this.d1 || this.d3 { y += 1.0; }
        return new Vector2(x, y);
    }

    public func ResetHeld() {
        this.up = false;
        this.down = false;
        this.left = false;
        this.right = false;
        this.d7 = false;
        this.d9 = false;
        this.d1 = false;
        this.d3 = false;
        this.zoomIn = false;
        this.zoomOut = false;
        this.recenter = false;
        this.act = false;
    }

    public static func KeyName(key: EInputKey) -> String {
        let s = EnumValueToString("EInputKey", EnumInt(key));
        if StrBeginsWith(s, "IK_") {
            s = StrMid(s, 3, StrLen(s) - 3);
        }
        if StrBeginsWith(s, "NumPad") {
            return "NUM " + StrMid(s, 6, StrLen(s) - 6);
        }
        if Equals(s, "NumPlus") { return "NUM +"; }
        if Equals(s, "NumMinus") { return "NUM -"; }
        if Equals(s, "NumStar") { return "NUM *"; }
        if Equals(s, "NumSlash") { return "NUM /"; }
        if Equals(s, "NumPeriod") { return "NUM ."; }
        if Equals(s, "Backslash") { return "\\"; }
        return StrUpper(s);
    }

    public static func HintText(s: ref<NightMapSettings>) -> String {
        return NMInput.KeyName(s.keyPanUp) + "/" + NMInput.KeyName(s.keyPanLeft) + "/" + NMInput.KeyName(s.keyPanRight) + "/" + NMInput.KeyName(s.keyPanDown) + " PAN"
            + "   ·   " + NMInput.KeyName(s.keyZoomIn) + " " + NMInput.KeyName(s.keyZoomOut) + " ZOOM"
            + "   ·   " + NMInput.KeyName(s.keyRecenter) + " FOLLOW"
            + "   ·   " + NMInput.KeyName(s.keyAct) + " ACT"
            + "   ·   " + NMInput.KeyName(s.keyToggle) + " CLOSE";
    }
}
```

- [ ] **Step 4: Implement UI helpers and the panel**

`r6/scripts/NightMap/Render/Ui.reds`:
```swift
module NightMap

public abstract class NMUi {
    public static func Canvas(parent: wref<inkCompoundWidget>, x: Float, y: Float, w: Float, h: Float) -> ref<inkCanvas> {
        let c = new inkCanvas();
        c.SetAnchor(inkEAnchor.TopLeft);
        c.SetSize(new Vector2(w, h));
        c.SetTranslation(new Vector2(x, y));
        c.SetInteractive(false);
        c.Reparent(parent);
        return c;
    }

    public static func Rect(parent: wref<inkCompoundWidget>, x: Float, y: Float, w: Float, h: Float, color: HDRColor, opacity: Float) -> ref<inkRectangle> {
        let r = new inkRectangle();
        r.SetAnchor(inkEAnchor.TopLeft);
        r.SetSize(new Vector2(w, h));
        r.SetTranslation(new Vector2(x, y));
        r.SetTintColor(color);
        r.SetOpacity(opacity);
        r.SetInteractive(false);
        r.Reparent(parent);
        return r;
    }

    // Square image from the NightMap UI atlas. centered=true positions the image's center at (x, y).
    public static func Image(parent: wref<inkCompoundWidget>, part: CName, x: Float, y: Float, size: Float, color: HDRColor, centered: Bool) -> ref<inkImage> {
        let img = new inkImage();
        img.SetAnchor(inkEAnchor.TopLeft);
        img.SetAtlasResource(NMTheme.UiAtlas());
        img.SetTexturePart(part);
        img.SetSize(new Vector2(size, size));
        if centered {
            img.SetAnchorPoint(new Vector2(0.5, 0.5));
        }
        img.SetTranslation(new Vector2(x, y));
        img.SetTintColor(color);
        img.SetInteractive(false);
        img.Reparent(parent);
        return img;
    }

    public static func Text(parent: wref<inkCompoundWidget>, font: String, style: CName, size: Int32, color: HDRColor) -> ref<inkText> {
        let t = new inkText();
        t.SetAnchor(inkEAnchor.TopLeft);
        t.SetFontFamily(font);
        t.SetFontStyle(style);
        t.SetFontSize(size);
        t.SetTintColor(color);
        t.SetInteractive(false);
        t.Reparent(parent);
        return t;
    }
}
```

`r6/scripts/NightMap/Render/Panel.reds`:
```swift
module NightMap

// Centered hologram panel: map area (left 70%, clipped), docked card (right 30%), hint bar at the bottom.
public class NMPanelLayout {
    public let winW: Float;
    public let winH: Float;
    public let scale: Float;
    public let x: Float;
    public let y: Float;
    public let w: Float;
    public let h: Float;
    public let mapW: Float;
    public let mapH: Float;
    public let cardW: Float;
    public let hintH: Float;

    public static func Compute(winW: Float, winH: Float) -> ref<NMPanelLayout> {
        let l = new NMPanelLayout();
        l.winW = winW;
        l.winH = winH;
        l.scale = MinF(winW / 3840.0, winH / 2160.0);
        l.w = winW * 0.70;
        l.h = winH * 0.711;
        if l.w > l.h * 1.75 {
            l.w = l.h * 1.75;   // keep the approved 1120x640 proportions on ultra-wide screens
        }
        l.x = (winW - l.w) * 0.5;
        l.y = (winH - l.h) * 0.5;
        l.hintH = NMTheme.HintHeight() * l.scale;
        l.mapW = l.w * 0.70;
        l.cardW = l.w - l.mapW;
        l.mapH = l.h - l.hintH;
        return l;
    }
}

public class NMPanel {
    public let layout: ref<NMPanelLayout>;
    public let root: ref<inkCanvas>;
    public let mapContent: ref<inkCanvas>;
    public let tiles: ref<inkCanvas>;
    public let items: ref<inkCanvas>;
    public let overlay: ref<inkCanvas>;
    public let card: ref<inkCanvas>;
    public let title: ref<inkText>;
    public let subtitle: ref<inkText>;
    public let warning: ref<inkText>;
    public let scaleBar: ref<inkRectangle>;
    public let scaleLabel: ref<inkText>;
    public let hints: ref<inkText>;

    public static func Build(window: wref<inkCompoundWidget>, layout: ref<NMPanelLayout>, opacity: Float) -> ref<NMPanel> {
        let p = new NMPanel();
        p.layout = layout;
        let s = layout.scale;
        p.root = NMUi.Canvas(window, layout.x, layout.y, layout.w, layout.h);
        p.root.SetName(n"NightMapPanel");
        NMUi.Rect(p.root, 0.0, 0.0, layout.w, layout.h, NMTheme.PanelBg(), opacity);

        // Clipped viewport (inkScrollArea's internal mask), same pattern as Codeware's text input viewport.
        let area = new inkScrollArea();
        area.SetAnchor(inkEAnchor.TopLeft);
        area.SetSize(new Vector2(layout.mapW, layout.mapH));
        area.SetConstrainContentPosition(false);
        area.SetUseInternalMask(true);
        area.SetInteractive(false);
        area.Reparent(p.root);
        p.mapContent = new inkCanvas();
        p.mapContent.SetSize(new Vector2(layout.mapW, layout.mapH));
        p.mapContent.SetInteractive(false);
        p.mapContent.Reparent(area);
        p.tiles = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        p.items = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);
        p.overlay = NMUi.Canvas(p.mapContent, 0.0, 0.0, layout.mapW, layout.mapH);

        // Card column and divider.
        NMUi.Rect(p.root, layout.mapW, 0.0, layout.cardW, layout.mapH, NMTheme.CardBg(), NMTheme.CardOpacity());
        NMUi.Rect(p.root, layout.mapW, 0.0, 2.0 * s, layout.mapH, NMTheme.Cyan(), 0.35);
        p.card = NMUi.Canvas(p.root, layout.mapW, 0.0, layout.cardW, layout.mapH);

        // Hint bar.
        NMUi.Rect(p.root, 0.0, layout.mapH, layout.w, layout.hintH, NMTheme.CardBg(), 0.6);
        p.hints = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(34.0 * s), NMTheme.Cyan());
        p.hints.SetTranslation(new Vector2(58.0 * s, layout.mapH + 34.0 * s));

        // Header over the map area.
        p.title = NMUi.Text(p.root, NMTheme.HeadingFont(), n"Bold", Cast<Int32>(62.0 * s), NMTheme.Text());
        p.title.SetText("NIGHT CITY");
        p.title.SetTranslation(new Vector2(67.0 * s, 46.0 * s));
        p.subtitle = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(34.0 * s), NMTheme.Cyan());
        p.subtitle.SetTranslation(new Vector2(67.0 * s, 128.0 * s));
        p.warning = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(32.0 * s), NMTheme.Pink());
        p.warning.SetTranslation(new Vector2(67.0 * s, 176.0 * s));
        p.warning.SetVisible(false);

        // Scale bar (top-right of the map area).
        p.scaleBar = NMUi.Rect(p.root, layout.mapW - 400.0 * s, 96.0 * s, 336.0 * s, 5.0 * s, NMTheme.Text(), 1.0);
        p.scaleLabel = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(32.0 * s), NMTheme.Text());
        p.scaleLabel.SetTranslation(new Vector2(layout.mapW - 300.0 * s, 108.0 * s));

        // Frame outline and glowing corner brackets.
        let t = 2.0 * s;
        NMUi.Rect(p.root, 0.0, 0.0, layout.w, t, NMTheme.Cyan(), 0.35);
        NMUi.Rect(p.root, 0.0, layout.h - t, layout.w, t, NMTheme.Cyan(), 0.35);
        NMUi.Rect(p.root, 0.0, 0.0, t, layout.h, NMTheme.Cyan(), 0.35);
        NMUi.Rect(p.root, layout.w - t, 0.0, t, layout.h, NMTheme.Cyan(), 0.35);
        let b = NMTheme.BracketSize() * s;
        NMUi.Image(p.root, n"bracket_tl", 0.0, 0.0, b, NMTheme.Cyan(), false);
        NMUi.Image(p.root, n"bracket_tr", layout.w - b, 0.0, b, NMTheme.Cyan(), false);
        NMUi.Image(p.root, n"bracket_bl", 0.0, layout.h - b, b, NMTheme.Cyan(), false);
        NMUi.Image(p.root, n"bracket_br", layout.w - b, layout.h - b, b, NMTheme.Cyan(), false);
        return p;
    }

    // Debug: a rectangle twice the map area; if clipping works only the part inside the map area shows.
    public func AddClipProbe() {
        let l = this.layout;
        NMUi.Rect(this.overlay, -0.5 * l.mapW, -0.5 * l.mapH, 2.0 * l.mapW, 2.0 * l.mapH, NMTheme.Pink(), 0.12);
    }

    public func Destroy(window: wref<inkCompoundWidget>) {
        if IsDefined(window) && IsDefined(this.root) {
            window.RemoveChild(this.root);
        }
    }
}
```

- [ ] **Step 5: Implement the system lifecycle**

Replace `r6/scripts/NightMap/Core/NightMapSystem.reds`:
```swift
module NightMap

public class NightMapFrame extends DelayCallback {
    public let system: wref<NightMapSystem>;

    public func Call() {
        if IsDefined(this.system) {
            this.system.Tick();
        }
    }
}

// Owns the overlay. Zero work while closed: only the Input/Key callback stays registered.
public class NightMapSystem extends ScriptableSystem {
    private let api: ref<NightMap>;
    private let input: ref<NMInput>;
    private let isOpen: Bool;
    private let loopAlive: Bool;
    private let panel: ref<NMPanel>;
    private let camera: ref<NMCamera>;
    private let lastMs: Float;
    private let holdMs: Float;
    private let savedMpp: Float = 4.0;
    private let frameNo: Int32;

    private func OnAttach() {
        this.api = NightMap.Create();
        if NMTileManifest.Available() {
            this.api.SetWorld(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        }
        this.input = new NMInput();
        GameInstance.GetCallbackSystem().RegisterCallback(n"Input/Key", this, n"OnKeyInput");
        NMLog.Info("loaded (tiles " + (NMTileManifest.Available() ? "present" : "missing") + ", precise clock " + ToString(NMClock.Precise()) + ")");
    }

    // Loading a save or quitting to menu ends the session: tear the overlay down so nothing is orphaned.
    private func OnDetach() {
        this.Close();
        GameInstance.GetCallbackSystem().UnregisterCallback(n"Input/Key", this);
    }

    public func Api() -> ref<NightMap> { return this.api; }
    public func IsOpen() -> Bool { return this.isOpen; }
    public func Camera() -> ref<NMCamera> { return this.camera; }
    public func Panel() -> ref<NMPanel> { return this.panel; }

    private func Settings() -> ref<NightMapSettings> {
        return NightMapSettings.Get(this.GetGameInstance());
    }

    private func HudWindow() -> wref<inkCompoundWidget> {
        return GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer").GetVirtualWindow();
    }

    private cb func OnKeyInput(evt: ref<KeyInputEvent>) {
        let s = this.Settings();
        if !IsDefined(s) {
            return;
        }
        this.input.Handle(s, evt.GetKey(), evt.GetAction(), evt.IsShiftDown(), evt.IsControlDown(), evt.IsAltDown(), this.isOpen);
        if this.input.toggle {
            this.input.toggle = false;
            if this.isOpen {
                this.Close();
            } else {
                this.Open();
            }
        }
        this.HandleDebug(s);
    }

    // Debug chords. Tasks 13 and 15 add the debug layer, perf suite and calibration dump.
    private func HandleDebug(s: ref<NightMapSettings>) {
        if this.input.debugSelfTest {
            this.input.debugSelfTest = false;
            if s.debug {
                let t = new NMSelfTest();
                t.Run();
            }
        }
        this.input.debugPerf = false;
        this.input.debugCalib = false;
        this.input.debugLayer = false;
    }

    public func Open() {
        if this.isOpen {
            return;
        }
        let window = this.HudWindow();
        if !IsDefined(window) {
            NMLog.Error("HUD layer not available");
            return;
        }
        let size = window.GetSize();
        if size.X < 100.0 || size.Y < 100.0 {
            size = new Vector2(3840.0, 2160.0);
        }
        let s = this.Settings();
        let layout = NMPanelLayout.Compute(size.X, size.Y);
        this.panel = NMPanel.Build(window, layout, IsDefined(s) ? s.panelOpacity : 0.74);
        let maxMpp = NMTileManifest.LevelCount() > 0 ? NMTileManifest.LevelMpp(NMTileManifest.LevelCount() - 1) : 16.0;
        let bounds = NMRect.Create(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        this.camera = NMCamera.Create(layout.mapW, layout.mapH, bounds, 0.5, maxMpp);
        this.camera.SetMpp(this.savedMpp);
        this.CenterOnPlayer(true);
        if IsDefined(s) {
            this.panel.hints.SetText(NMInput.HintText(s));
            if s.debug {
                this.panel.AddClipProbe();
            }
        }
        if !NMTileManifest.Available() {
            this.panel.warning.SetText("TILE ARCHIVE MISSING - run tools/tiles build");
            this.panel.warning.SetVisible(true);
        }
        this.isOpen = true;
        this.input.ResetHeld();
        this.OnOpened();
        this.EnsureLoop();
        NMLog.Info("open " + FloatToStringPrec(size.X, 0) + "x" + FloatToStringPrec(size.Y, 0));
    }

    public func Close() {
        if !this.isOpen {
            return;
        }
        this.isOpen = false;
        if IsDefined(this.camera) {
            this.savedMpp = this.camera.mpp;
        }
        this.OnClosing();
        if IsDefined(this.panel) {
            this.panel.Destroy(this.HudWindow());
        }
        this.panel = null;
        NMLog.Info("closed");
    }

    private func CenterOnPlayer(instant: Bool) {
        let player = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) || !IsDefined(this.camera) {
            return;
        }
        let pos = player.GetWorldPosition();
        if instant {
            this.camera.SetCenter(pos.X, pos.Y);
        } else {
            this.camera.EaseTo(pos.X, pos.Y, this.camera.mpp, 250.0);
        }
        this.camera.follow = true;
    }

    private func EnsureLoop() {
        if this.loopAlive {
            return;
        }
        this.loopAlive = true;
        this.lastMs = NMClock.NowMs();
        this.Schedule();
    }

    // Zero-delay timed callback: DelayCallbackNextFrame re-armed from a callback is silently dropped.
    private func Schedule() {
        let cb = new NightMapFrame();
        cb.system = this;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.0, false);
    }

    public func Tick() {
        if !this.isOpen {
            this.loopAlive = false;
            return;
        }
        let now = NMClock.NowMs();
        let dt = ClampF(now - this.lastMs, 0.0, 100.0);
        this.lastMs = now;
        this.frameNo += 1;
        this.DriveCamera(dt);
        this.UpdateModules(dt);
        this.Schedule();
    }

    private func DriveCamera(dt: Float) {
        let pan = this.input.PanVector();
        if pan.X != 0.0 || pan.Y != 0.0 {
            this.holdMs += dt;
            let accel = this.holdMs > 500.0 ? MinF(1.0 + (this.holdMs - 500.0) / 1000.0, 3.0) : 1.0;
            let step = 1500.0 * accel * dt / 1000.0;
            this.camera.PanPixels(pan.X * step, pan.Y * step);
        } else {
            this.holdMs = 0.0;
        }
        if this.input.zoomIn {
            this.camera.ZoomBy(PowF(1.5, dt / 1000.0));
        }
        if this.input.zoomOut {
            this.camera.ZoomBy(1.0 / PowF(1.5, dt / 1000.0));
        }
        if this.input.recenter {
            this.input.recenter = false;
            this.CenterOnPlayer(false);
        }
        if this.camera.follow && !this.camera.IsEasing() {
            this.CenterOnPlayer(true);
        }
        this.camera.Tick(dt);
    }

    // Module hooks; Tasks 12-14 fill these in.
    private func OnOpened() {}

    private func OnClosing() {}

    private func UpdateModules(dt: Float) {}
}
```

- [ ] **Step 6: Run the compile check**

Run: `tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 7: Commit**

```bash
git add r6/scripts/NightMap
git commit -m "Core: Mod Settings, numpad input (arrows ignored), panel layout/chrome with clipped map area, open/close lifecycle"
```

---

### Task 11: In-game checkpoint 1 (human-in-the-loop)

**Files:**
- Create: `notes/CHECKPOINTS.md`

The executor installs the build and asks the user to perform the in-game steps, then reads `gamelog.log` itself. No code changes here unless a step fails. In that case, fix the bug in the owning task's files, re-run `tools/check.sh`, reinstall, and repeat the failed step.

- [ ] **Step 1: Build tiles if not done, install**

Run: `tools/install.sh`
Expected: `COMPILE OK`, `installed archive -> ...`, `installed scripts -> ...`.

- [ ] **Step 2: User — basic open/close and visuals**

Ask the user to:
1. Restart the game and load a save.
2. In Mod Settings → NightMap, turn on Debug tools.
3. Press `\`.

Expected:
- A centered hologram panel with corner brackets, a "NIGHT CITY" header, the card column on the right, and the hint bar listing NUM keys. The map area is empty in this task.
- A faint pink probe rectangle visible **only inside the map area**, which proves clipping.
- Press `\` again → the panel disappears.

- [ ] **Step 3: Self-test**

Ask the user to open the map and press Ctrl+`\`. Then:

Run: `grep -a "\[NightMap\] TEST|" ~/cyberpunk_symlink/bin/x64/plugins/cyber_engine_tweaks/gamelog.log | tail -40`
Expected: `TEST|SUMMARY|passed=N|failed=0`. Any `FAIL` line names the case and the owning task.

- [ ] **Step 4: Controls while driving**

Ask the user to get in a car, open the map, then:
- Drive with WASD → the car drives and the map follows V.
- Hold Numpad 8 → the map pans north and follow stops.
- Press Numpad 5 → the map recenters and follows again.
- Hold Numpad +/- → zoom.

Also check with NumLock off: the numpad keys must not pan, and the car must still steer normally.

- [ ] **Step 5: HUD hiding**

With the map open, ask the user to:
- open the main menu (Esc) → the map hides with the HUD and is back after closing the menu
- enter photo mode → the map is hidden.

- [ ] **Step 6: Session teardown**

With the map open, ask the user to load a save. Then:

Run: `grep -a "\[NightMap\]" ~/cyberpunk_symlink/bin/x64/plugins/cyber_engine_tweaks/gamelog.log | tail -6`
Expected: `closed` logged before the new session's `loaded`. After the load, no panel is visible until `\` is pressed.

- [ ] **Step 7: Record and commit**

Write `notes/CHECKPOINTS.md` with a `## Checkpoint 1` section listing each step, its result (pass/fail plus the fix commit), the self-test summary line, and the NumLock-off observation.

```bash
git add notes/CHECKPOINTS.md
git commit -m "Checkpoint 1: in-game lifecycle, clipping, input and self-test results"
```

---

### Task 12: Tile layer

**Files:**
- Create: `r6/scripts/NightMap/Render/TileLayer.reds`
- Modify: `Core/NightMapSystem.reds` (`OnOpened`, `OnClosing`, `UpdateModules`, new field), `Debug/SelfTest.reds` (add `TileCases`)

**Interfaces:**
- Consumes: `NMTileManifest` (Task 7), `NMCamera` (Task 8), `NMPanel.tiles` (Task 10).
- Produces: `NMTileLayer.Create(parent: ref<inkCanvas>) -> ref<NMTileLayer>`, `.Update(cam)`, `.available: Bool`, `.level: Int32`, and `NMTileLayer.PickLevel(mpp) -> Int32` (the finest level whose texel ≥ the view unit; tiles only ever magnify).

- [ ] **Step 1: Add the failing tile cases**

In `Debug/SelfTest.reds`, add `this.TileCases();` to `Run()` after `LayoutCases`, and add:
```swift
    private func TileCases() {
        if !NMTileManifest.Available() {
            this.Check("tiles.manifest_available", false, "Generated/TileManifest.reds is the stub; run the tile build");
            return;
        }
        let n = NMTileManifest.LevelCount();
        let ascending = true;
        let i = 1;
        while i < n {
            if NMTileManifest.LevelMpp(i) <= NMTileManifest.LevelMpp(i - 1) { ascending = false; }
            i += 1;
        }
        this.Check("tiles.levels_ascending", n >= 1 && ascending, ToString(n));
        let first = NMTileManifest.LevelMpp(0);
        let last = NMTileManifest.LevelMpp(n - 1);
        this.Check("tiles.pick_level", NMTileLayer.PickLevel(first * 0.25) == 0 && NMTileLayer.PickLevel(first) == 0
            && (n < 2 || NMTileLayer.PickLevel(first * 1.01) == 1) && NMTileLayer.PickLevel(last * 10.0) == n - 1, "");
        this.Check("tiles.ui_atlas_in_depot", GameInstance.GetResourceDepot().ResourceExists(NMTheme.UiAtlas()), "nightmap\\ui\\ui.inkatlas not found: archive not installed?");
        this.Check("tiles.level0_has_tiles", ArraySize(NMTileManifest.LevelTiles(0)) > 0, "");
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `tools/check.sh`
Expected: `COMPILE FAILED` (unresolved `NMTileLayer`).

- [ ] **Step 3: Implement**

`r6/scripts/NightMap/Render/TileLayer.reds`:
```swift
module NightMap

// Background tiles from NightMap.archive. Pool of 64 images; slots keep their tile while it stays visible
// so panning never re-assigns textures. Without the archive, draws a plain 1 km / 2 km grid instead.
public class NMTileLayer {
    private let pool: array<ref<inkImage>>;
    private let shownKey: array<Int32>;
    private let present: array<Bool>;
    private let levelBase: array<Int32>;
    private let grid: array<ref<inkRectangle>>;
    private let lastRev: Int32 = -1;
    public let available: Bool;
    public let level: Int32 = -1;

    public static func Create(parent: ref<inkCanvas>) -> ref<NMTileLayer> {
        let t = new NMTileLayer();
        t.available = NMTileManifest.Available() && GameInstance.GetResourceDepot().ResourceExists(NMTheme.UiAtlas());
        if t.available {
            let base = 0;
            let i = 0;
            while i < NMTileManifest.LevelCount() {
                ArrayPush(t.levelBase, base);
                let n = NMTileManifest.LevelNx(i) * NMTileManifest.LevelNy(i);
                let k = 0;
                while k < n {
                    ArrayPush(t.present, false);
                    k += 1;
                }
                for idx in NMTileManifest.LevelTiles(i) {
                    t.present[base + idx] = true;
                }
                base += n;
                i += 1;
            }
            let p = 0;
            while p < 64 {
                let img = new inkImage();
                img.SetAnchor(inkEAnchor.TopLeft);
                img.SetVisible(false);
                img.SetInteractive(false);
                img.Reparent(parent);
                ArrayPush(t.pool, img);
                ArrayPush(t.shownKey, -1);
                p += 1;
            }
        } else {
            let g = 0;
            while g < 48 {
                let r = new inkRectangle();
                r.SetAnchor(inkEAnchor.TopLeft);
                r.SetTintColor(NMTheme.Cyan());
                r.SetOpacity(0.18);
                r.SetVisible(false);
                r.SetInteractive(false);
                r.Reparent(parent);
                ArrayPush(t.grid, r);
                g += 1;
            }
        }
        return t;
    }

    public static func PickLevel(mpp: Float) -> Int32 {
        let n = NMTileManifest.LevelCount();
        let i = 0;
        while i < n {
            if NMTileManifest.LevelMpp(i) >= mpp {
                return i;
            }
            i += 1;
        }
        return n - 1;
    }

    public func Update(cam: ref<NMCamera>) {
        if cam.revision == this.lastRev {
            return;
        }
        this.lastRev = cam.revision;
        if !this.available {
            this.UpdateGrid(cam);
            return;
        }
        let lv = NMTileLayer.PickLevel(cam.mpp);
        this.level = lv;
        let tw = 512.0 * NMTileManifest.LevelMpp(lv);
        let ox = NMTileManifest.LevelOriginX(lv);
        let otop = NMTileManifest.LevelOriginTop(lv);
        let nx = NMTileManifest.LevelNx(lv);
        let ny = NMTileManifest.LevelNy(lv);
        let vis = cam.VisibleRect(0.0);
        let ix0 = Max(FloorF((vis.minX - ox) / tw), 0);
        let ix1 = Min(FloorF((vis.maxX - ox) / tw), nx - 1);
        let iy0 = Max(FloorF((otop - vis.maxY) / tw), 0);
        let iy1 = Min(FloorF((otop - vis.minY) / tw), ny - 1);
        let want: array<Int32>;
        let iy = iy0;
        while iy <= iy1 {
            let ix = ix0;
            while ix <= ix1 {
                let key = this.levelBase[lv] + iy * nx + ix;
                if this.present[key] {
                    ArrayPush(want, key);
                }
                ix += 1;
            }
            iy += 1;
        }
        let s = 0;
        while s < ArraySize(this.pool) {
            if this.shownKey[s] >= 0 && !ArrayContains(want, this.shownKey[s]) {
                this.pool[s].SetVisible(false);
                this.shownKey[s] = -1;
            }
            s += 1;
        }
        let size = tw / cam.mpp + 1.0;   // +1 unit overlap hides seams
        for key in want {
            let slot = this.SlotFor(key);
            if slot < 0 {
                break;
            }
            let local = key - this.levelBase[lv];
            let tix = local % nx;
            let tiy = local / nx;
            let img = this.pool[slot];
            if this.shownKey[slot] != key {
                img.SetAtlasResource(ResRef.FromString("nightmap\\tiles\\L" + ToString(lv) + "\\t_" + ToString(tix) + "_" + ToString(tiy) + ".inkatlas"));
                img.SetTexturePart(n"full");
                img.SetVisible(true);
                this.shownKey[slot] = key;
            }
            img.SetTranslation(cam.WorldToMap(ox + Cast<Float>(tix) * tw, otop - Cast<Float>(tiy) * tw));
            img.SetSize(new Vector2(size, size));
        }
    }

    // The slot already showing this tile, else the first free slot, else -1.
    private func SlotFor(key: Int32) -> Int32 {
        let free = -1;
        let s = 0;
        while s < ArraySize(this.shownKey) {
            if this.shownKey[s] == key {
                return s;
            }
            if free < 0 && this.shownKey[s] < 0 {
                free = s;
            }
            s += 1;
        }
        return free;
    }

    private func UpdateGrid(cam: ref<NMCamera>) {
        let vis = cam.VisibleRect(0.0);
        let step = cam.mpp > 6.0 ? 2000.0 : 1000.0;
        let used = 0;
        let x = Cast<Float>(FloorF(vis.minX / step) + 1) * step;
        while x <= vis.maxX && used < ArraySize(this.grid) {
            let p = cam.WorldToMap(x, vis.maxY);
            let r = this.grid[used];
            r.SetTranslation(new Vector2(p.X, 0.0));
            r.SetSize(new Vector2(2.0, cam.viewH));
            r.SetVisible(true);
            used += 1;
            x += step;
        }
        let y = Cast<Float>(FloorF(vis.minY / step) + 1) * step;
        while y <= vis.maxY && used < ArraySize(this.grid) {
            let p = cam.WorldToMap(vis.minX, y);
            let r = this.grid[used];
            r.SetTranslation(new Vector2(0.0, p.Y));
            r.SetSize(new Vector2(cam.viewW, 2.0));
            r.SetVisible(true);
            used += 1;
            y += step;
        }
        while used < ArraySize(this.grid) {
            this.grid[used].SetVisible(false);
            used += 1;
        }
    }
}
```

In `Core/NightMapSystem.reds` add the field `private let tiles: ref<NMTileLayer>;` and replace the three hooks:
```swift
    private func OnOpened() {
        this.tiles = NMTileLayer.Create(this.panel.tiles);
    }

    private func OnClosing() {
        this.tiles = null;
    }

    private func UpdateModules(dt: Float) {
        this.tiles.Update(this.camera);
    }
```

- [ ] **Step 4: Run the compile check**

Run: `tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 5: Commit**

```bash
git add r6/scripts/NightMap
git commit -m "Render: tile layer with magnify-only LOD, stable slot reuse, grid fallback"
```

---

### Task 13: Item renderer (pools, culling, pyramid clustering) and debug layer

**Files:**
- Create: `r6/scripts/NightMap/Render/ItemRenderer.reds`, `Debug/DebugLayer.reds`
- Modify: `Core/NightMapSystem.reds` (renderer field, hooks, debug-layer chord), `Debug/SelfTest.reds` (add `RendererCases`)

**Interfaces:**
- Consumes: `NightMap`/`NightMapLayer` internals (Task 9), `NMCamera`, `NMTheme`, `NMUi`, `NMResolveImage` (Task 8).
- Produces:
  - **`NMItemRenderer`:**
    - Construction and updates: `Create(api, parent: ref<inkCanvas>, scale) -> ref<NMItemRenderer>`, `.Update(cam, viewW, viewH) -> Bool` (true = relaid out), `.Invalidate()`.
    - Candidate arrays: `candX, candY, candKind (0 = chip, 1 = cluster), candLayer, candItem, candSlot`.
    - Per cluster slot: `clWx, clWy, clWorld, clTotal`, plus `clCats`/`clCatCount` (`[slot * 6 + k]`, exact per-category counts) and `clCatN`.
    - Highlights and counters: `selChip, selCluster`, `chipsUsed, clustersUsed, pendingImages, relayouts`.
  - **`NMDebugLayer`:** `Id()`, `Fill(api, n) -> ref<NightMapLayer>`, `Remove(api)`; `NMDebugListener`.

- [ ] **Step 1: Add the failing renderer cases**

In `Debug/SelfTest.reds`, add `this.RendererCases();` to `Run()` after `TileCases`, and add:
```swift
    private func RendererCases() {
        let api = NightMap.Create();
        api.SetWorld(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        NMDebugLayer.Fill(api, 3000);
        let canvas = new inkCanvas();   // detached: widgets exist but are never drawn
        let r = NMItemRenderer.Create(api, canvas, 1.0);
        let bounds = NMRect.Create(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        let cam = NMCamera.Create(1880.0, 1480.0, bounds, 0.5, 16.0);
        let ok = true;
        let detail = "";
        let mpps: array<Float> = [0.6, 2.0, 6.0, 16.0];
        for m in mpps {
            cam.SetMpp(m);
            r.Update(cam, 1880.0, 1480.0);
            if r.chipsUsed > NMTheme.ChipBudget() || r.clustersUsed > NMTheme.ClusterBudget() {
                ok = false;
                detail += "mpp " + this.F(m) + ": chips " + ToString(r.chipsUsed) + " clusters " + ToString(r.clustersUsed) + "; ";
            }
            if ArraySize(r.candX) != r.chipsUsed + r.clustersUsed {
                ok = false;
                detail += "candidates mismatch at mpp " + this.F(m) + "; ";
            }
        }
        this.Check("renderer.budgets", ok, detail);
        // Whole city in view at 16 m/unit: every item is drawn exactly once, as a chip or inside a cluster.
        cam.SetCenter((bounds.minX + bounds.maxX) * 0.5, (bounds.minY + bounds.maxY) * 0.5);
        cam.SetMpp(16.0);
        r.Update(cam, 1880.0, 1480.0);
        let total = r.chipsUsed;
        let k = 0;
        while k < r.clustersUsed {
            total += r.clTotal[k];
            k += 1;
        }
        this.Check("renderer.conservation_overview", total == 3000, ToString(total) + " of 3000 (chips " + ToString(r.chipsUsed) + ")");
        this.Check("renderer.idle_skips_relayout", !r.Update(cam, 1880.0, 1480.0), "");
        let L = api.GetLayer(NMDebugLayer.Id());
        L.SetVisible(false);
        r.Update(cam, 1880.0, 1480.0);
        this.Check("renderer.hidden_layer_draws_nothing", r.chipsUsed == 0 && r.clustersUsed == 0, ToString(r.chipsUsed) + "/" + ToString(r.clustersUsed));
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `tools/check.sh`
Expected: `COMPILE FAILED` (unresolved `NMDebugLayer`, `NMItemRenderer`).

- [ ] **Step 3: Implement the renderer**

`r6/scripts/NightMap/Render/ItemRenderer.reds`:
```swift
module NightMap

public class NMIconRef {
    public let atlas: ResRef;
    public let part: CName;
    public let key: String;
    public let pending: Bool;
}

// Draws every visible layer through fixed widget pools.
// - Zoomed in (a 250 m cell >= ClusterSpacing on screen): individual chips, culled to the view.
// - Otherwise: screen-space blocks >= ClusterSpacing built from the grid pyramid; a block with one item
//   is a chip, larger blocks are a cluster hex with its top-3 categories.
// - A clustering layer that would overflow the chip budget is clustered at 250 m even when zoomed in.
// Relayout happens only when the camera or the API revision changed.
public class NMItemRenderer {
    private let api: wref<NightMap>;
    private let scale: Float;
    private let chipBg: array<ref<inkImage>>;
    private let chipIcon: array<ref<inkImage>>;
    private let chipOn: array<Bool>;
    private let chipCat: array<Int32>;
    private let chipIconKey: array<String>;
    private let chipAlpha: array<Float>;
    private let clBg: array<ref<inkImage>>;
    private let clText: array<ref<inkText>>;
    private let clShownCount: array<Int32>;
    private let clOn: array<Bool>;
    private let miniBg: array<ref<inkImage>>;
    private let miniIcon: array<ref<inkImage>>;
    private let miniCat: array<Int32>;
    private let miniOn: array<Bool>;
    public let selChip: ref<inkImage>;
    public let selCluster: ref<inkImage>;
    public let candX: array<Float>;
    public let candY: array<Float>;
    public let candKind: array<Int32>;
    public let candLayer: array<Int32>;
    public let candItem: array<Int32>;
    public let candSlot: array<Int32>;
    public let clWx: array<Float>;
    public let clWy: array<Float>;
    public let clWorld: array<Float>;
    public let clTotal: array<Int32>;
    public let clCats: array<Int32>;
    public let clCatCount: array<Int32>;
    public let clCatN: array<Int32>;
    private let bCount: array<Int32>;
    private let bSx: array<Float>;
    private let bSy: array<Float>;
    private let bAnyLayer: array<Int32>;
    private let bAnyCell: array<Int32>;
    private let bCat: array<Int32>;
    private let bTouched: array<Int32>;
    private let icon: ref<NMIconRef>;
    private let lastCamRev: Int32 = -1;
    private let lastApiRev: Int32 = -1;
    public let chipsUsed: Int32;
    public let clustersUsed: Int32;
    public let pendingImages: Int32;
    public let relayouts: Int32;

    public static func Create(api: ref<NightMap>, parent: ref<inkCanvas>, scale: Float) -> ref<NMItemRenderer> {
        let r = new NMItemRenderer();
        r.api = api;
        r.scale = scale;
        r.icon = new NMIconRef();
        // z-order (back to front): selected-cluster rim, clusters, selected-chip rim, chips
        r.selCluster = NMUi.Image(parent, n"cluster_sel", 0.0, 0.0, NMTheme.ClusterSelSize() * scale, NMTheme.Cyan(), true);
        r.selCluster.SetVisible(false);
        let i = 0;
        while i < NMTheme.ClusterBudget() {
            let bg = NMUi.Image(parent, n"cluster", 0.0, 0.0, NMTheme.ClusterSize() * scale, NMTheme.Cyan(), true);
            bg.SetVisible(false);
            ArrayPush(r.clBg, bg);
            let k = 0;
            while k < 3 {
                let mb = NMUi.Image(parent, n"mini", 0.0, 0.0, NMTheme.MiniSize() * scale, NMTheme.Cyan(), true);
                let mi = NMUi.Image(parent, n"icon_dot", 0.0, 0.0, NMTheme.IconSize() * 0.75 * scale, NMTheme.Cyan(), true);
                mb.SetVisible(false);
                mi.SetVisible(false);
                ArrayPush(r.miniBg, mb);
                ArrayPush(r.miniIcon, mi);
                ArrayPush(r.miniCat, -1);
                ArrayPush(r.miniOn, false);
                k += 1;
            }
            let t = NMUi.Text(parent, NMTheme.HeadingFont(), n"Bold", Cast<Int32>(52.0 * scale), NMTheme.Text());
            t.SetAnchorPoint(new Vector2(0.5, 0.5));
            t.SetHorizontalAlignment(textHorizontalAlignment.Center);
            t.SetVisible(false);
            ArrayPush(r.clText, t);
            ArrayPush(r.clShownCount, -1);
            ArrayPush(r.clOn, false);
            ArrayPush(r.clWx, 0.0);
            ArrayPush(r.clWy, 0.0);
            ArrayPush(r.clWorld, 0.0);
            ArrayPush(r.clTotal, 0);
            ArrayPush(r.clCatN, 0);
            let c = 0;
            while c < 6 {
                ArrayPush(r.clCats, -1);
                ArrayPush(r.clCatCount, 0);
                c += 1;
            }
            i += 1;
        }
        r.selChip = NMUi.Image(parent, n"chip_sel", 0.0, 0.0, NMTheme.ChipSelSize() * scale, NMTheme.Cyan(), true);
        r.selChip.SetVisible(false);
        i = 0;
        while i < NMTheme.ChipBudget() {
            let bg = NMUi.Image(parent, n"chip", 0.0, 0.0, NMTheme.ChipSize() * scale, NMTheme.Cyan(), true);
            let ic = NMUi.Image(parent, n"icon_dot", 0.0, 0.0, NMTheme.IconSize() * scale, NMTheme.Cyan(), true);
            bg.SetVisible(false);
            ic.SetVisible(false);
            ArrayPush(r.chipBg, bg);
            ArrayPush(r.chipIcon, ic);
            ArrayPush(r.chipOn, false);
            ArrayPush(r.chipCat, -1);
            ArrayPush(r.chipIconKey, "");
            ArrayPush(r.chipAlpha, 1.0);
            i += 1;
        }
        return r;
    }

    public func Invalidate() {
        this.lastCamRev = -1;
    }

    public func Update(cam: ref<NMCamera>, viewW: Float, viewH: Float) -> Bool {
        let api = this.api;
        if cam.revision == this.lastCamRev && api.revision == this.lastApiRev {
            return false;
        }
        this.lastCamRev = cam.revision;
        this.lastApiRev = api.revision;
        this.relayouts += 1;
        ArrayClear(this.candX);
        ArrayClear(this.candY);
        ArrayClear(this.candKind);
        ArrayClear(this.candLayer);
        ArrayClear(this.candItem);
        ArrayClear(this.candSlot);
        this.chipsUsed = 0;
        this.clustersUsed = 0;
        this.pendingImages = 0;
        let spacing = NMTheme.ClusterSpacing() * this.scale;
        let individual = NMGrid.CellSize(0) / cam.mpp >= spacing;
        let clusterLayers: array<Int32>;
        for li in this.LayerOrder() {
            let L = api.layers[li];
            if !L.VisibleAt(cam.mpp) || L.count == 0 {
                continue;
            }
            if !L.clustering {
                this.PlaceAllOf(L, cam, viewW, viewH);
                continue;
            }
            if individual && this.chipsUsed + this.CountVisible(L, cam) <= NMTheme.ChipBudget() {
                this.PlaceCellsOf(L, cam, viewW, viewH);
                continue;
            }
            ArrayPush(clusterLayers, li);
        }
        if ArraySize(clusterLayers) > 0 {
            this.PlaceClusters(clusterLayers, cam, viewW, viewH, individual);
        }
        this.HideUnused();
        return true;
    }

    // Layer indices by priority, highest first (highest gets the topmost chip slots).
    private func LayerOrder() -> array<Int32> {
        let order: array<Int32>;
        let i = 0;
        while i < ArraySize(this.api.layers) {
            let j = ArraySize(order);
            ArrayPush(order, i);
            while j > 0 && this.api.layers[order[j - 1]].priority < this.api.layers[i].priority {
                order[j] = order[j - 1];
                j -= 1;
            }
            order[j] = i;
            i += 1;
        }
        return order;
    }

    // [gx0, gy0, gx1, gy1] of cells at a level intersecting the view plus a margin.
    private func CellRange(level: Int32, cam: ref<NMCamera>, marginPx: Float) -> array<Int32> {
        let vis = cam.VisibleRect(marginPx);
        let cs = NMGrid.CellSize(level);
        let side = NMGrid.Side(level);
        let r: array<Int32>;
        ArrayPush(r, Clamp(FloorF((vis.minX - NMGrid.OriginX()) / cs), 0, side - 1));
        ArrayPush(r, Clamp(FloorF((vis.minY - NMGrid.OriginY()) / cs), 0, side - 1));
        ArrayPush(r, Clamp(FloorF((vis.maxX - NMGrid.OriginX()) / cs), 0, side - 1));
        ArrayPush(r, Clamp(FloorF((vis.maxY - NMGrid.OriginY()) / cs), 0, side - 1));
        return r;
    }

    private func CountVisible(L: ref<NightMapLayer>, cam: ref<NMCamera>) -> Int32 {
        let rg = this.CellRange(0, cam, 60.0 * this.scale);
        let side = NMGrid.Side(0);
        let n = 0;
        let gy = rg[1];
        while gy <= rg[3] {
            let gx = rg[0];
            while gx <= rg[2] {
                n += L.cnt[gy * side + gx];
                gx += 1;
            }
            gy += 1;
        }
        return n;
    }

    private func PlaceCellsOf(L: ref<NightMapLayer>, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        let rg = this.CellRange(0, cam, 60.0 * this.scale);
        let side = NMGrid.Side(0);
        let gy = rg[1];
        while gy <= rg[3] {
            let gx = rg[0];
            while gx <= rg[2] {
                let id = L.head[gy * side + gx];
                while id >= 0 {
                    this.PlaceChip(L, id, cam, viewW, viewH);
                    id = L.nextIn[id * 3];
                }
                gx += 1;
            }
            gy += 1;
        }
    }

    private func PlaceAllOf(L: ref<NightMapLayer>, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        let id = 0;
        while id < ArraySize(L.alive) {
            if L.alive[id] {
                this.PlaceChip(L, id, cam, viewW, viewH);
            }
            id += 1;
        }
    }

    private func ResolveIcon(L: ref<NightMapLayer>, id: Int32) {
        let ic = this.icon;
        ic.pending = false;
        if NotEquals(L.image[id], "") {
            if Equals(L.imageResolved[id], "") {
                L.imageResolved[id] = NMResolveImage(L.image[id]);
            }
            if NotEquals(L.imageResolved[id], "") {
                ic.atlas = ResRef.FromString(L.imageResolved[id]);
                ic.part = n"full";
                ic.key = L.imageResolved[id];
                return;
            }
            ic.pending = true;
        }
        if L.hasAtlas[id] {
            ic.atlas = L.atlas[id];
            ic.part = L.part[id];
            ic.key = ResRef.ToString(L.atlas[id]) + "|" + NameToString(L.part[id]);
            return;
        }
        let g = L.catGlobal[L.cat[id]];
        if this.api.catHasIcon[g] {
            ic.atlas = this.api.catAtlas[g];
            ic.part = this.api.catPart[g];
            ic.key = "cat" + ToString(g);
            return;
        }
        ic.atlas = NMTheme.UiAtlas();
        ic.part = n"icon_dot";
        ic.key = "dot";
    }

    private func PlaceChip(L: ref<NightMapLayer>, id: Int32, cam: ref<NMCamera>, viewW: Float, viewH: Float) -> Bool {
        if this.chipsUsed >= NMTheme.ChipBudget() {
            return false;
        }
        let p = cam.WorldToMap(L.px[id], L.py[id]);
        let m = 60.0 * this.scale;
        if p.X < -m || p.X > viewW + m || p.Y < -m || p.Y > viewH + m {
            return false;
        }
        let slot = NMTheme.ChipBudget() - 1 - this.chipsUsed;
        this.chipsUsed += 1;
        let bg = this.chipBg[slot];
        let ic = this.chipIcon[slot];
        let g = L.catGlobal[L.cat[id]];
        let color = this.api.catColor[g];
        if this.chipCat[slot] != g || L.hasTint[id] {
            bg.SetTintColor(color);
            ic.SetTintColor(L.hasTint[id] ? L.tint[id] : color);
            this.chipCat[slot] = L.hasTint[id] ? -1 : g;
        }
        this.ResolveIcon(L, id);
        if this.icon.pending {
            this.pendingImages += 1;
        }
        if NotEquals(this.chipIconKey[slot], this.icon.key) {
            ic.SetAtlasResource(this.icon.atlas);
            ic.SetTexturePart(this.icon.part);
            this.chipIconKey[slot] = this.icon.key;
        }
        if this.chipAlpha[slot] != L.opacity {
            bg.SetOpacity(L.opacity);
            ic.SetOpacity(L.opacity);
            this.chipAlpha[slot] = L.opacity;
        }
        bg.SetTranslation(p);
        ic.SetTranslation(p);
        if !this.chipOn[slot] {
            bg.SetVisible(true);
            ic.SetVisible(true);
            this.chipOn[slot] = true;
        }
        ArrayPush(this.candX, p.X);
        ArrayPush(this.candY, p.Y);
        ArrayPush(this.candKind, 0);
        ArrayPush(this.candLayer, L.index);
        ArrayPush(this.candItem, id);
        ArrayPush(this.candSlot, slot);
        return true;
    }

    private func PlaceClusters(layers: array<Int32>, cam: ref<NMCamera>, viewW: Float, viewH: Float, individual: Bool) {
        let sp = NMTheme.ClusterSpacing() * this.scale;
        let level = 0;
        let k = 1;
        if !individual {
            level = 2;
            while level > 0 && NMGrid.CellSize(level) / cam.mpp > sp {
                level -= 1;
            }
            k = Max(1, CeilF(sp / (NMGrid.CellSize(level) / cam.mpp)));
        }
        let rg = this.CellRange(level, cam, 200.0 * this.scale);
        let side = NMGrid.Side(level);
        let base = NMGrid.Base(level);
        let bx0 = rg[0] / k;
        let by0 = rg[1] / k;
        let bw = rg[2] / k - bx0 + 1;
        let bh = rg[3] / k - by0 + 1;
        let nb = bw * bh;
        let maxCats = NMTheme.MaxGlobalCategories();
        if ArraySize(this.bCount) < nb {
            ArrayResize(this.bCount, nb);
            ArrayResize(this.bSx, nb);
            ArrayResize(this.bSy, nb);
            ArrayResize(this.bAnyLayer, nb);
            ArrayResize(this.bAnyCell, nb);
            ArrayResize(this.bCat, nb * maxCats);
        }
        let b = 0;
        while b < nb {
            this.bCount[b] = 0;
            this.bSx[b] = 0.0;
            this.bSy[b] = 0.0;
            this.bAnyLayer[b] = -1;
            this.bAnyCell[b] = -1;
            b += 1;
        }
        for li in layers {
            let L = this.api.layers[li];
            let ncat = ArraySize(L.catGlobal);
            let gy = rg[1];
            while gy <= rg[3] {
                let gx = rg[0];
                while gx <= rg[2] {
                    let cell = base + gy * side + gx;
                    let c = L.cnt[cell];
                    if c > 0 {
                        b = (gy / k - by0) * bw + (gx / k - bx0);
                        this.bCount[b] += c;
                        this.bSx[b] += L.sumX[cell];
                        this.bSy[b] += L.sumY[cell];
                        this.bAnyLayer[b] = li;
                        this.bAnyCell[b] = cell;
                        let lc = 0;
                        while lc < ncat {
                            let t = L.tally[cell * NMGrid.MaxCats() + lc];
                            if t > 0 {
                                let gi = b * maxCats + L.catGlobal[lc];
                                if this.bCat[gi] == 0 {
                                    ArrayPush(this.bTouched, gi);
                                }
                                this.bCat[gi] += t;
                            }
                            lc += 1;
                        }
                    }
                    gx += 1;
                }
                gy += 1;
            }
        }
        let worldSize = Cast<Float>(k) * NMGrid.CellSize(level);
        b = 0;
        while b < nb {
            let n = this.bCount[b];
            if n == 1 {
                let L1 = this.api.layers[this.bAnyLayer[b]];
                this.PlaceChip(L1, L1.head[this.bAnyCell[b]], cam, viewW, viewH);
            } else if n > 1 {
                this.PlaceCluster(b, n, worldSize, cam, viewW, viewH);
            }
            b += 1;
        }
        for gi in this.bTouched {
            this.bCat[gi] = 0;
        }
        ArrayClear(this.bTouched);
    }

    private func PlaceCluster(b: Int32, n: Int32, worldSize: Float, cam: ref<NMCamera>, viewW: Float, viewH: Float) {
        if this.clustersUsed >= NMTheme.ClusterBudget() {
            return;
        }
        let wx = this.bSx[b] / Cast<Float>(n);
        let wy = this.bSy[b] / Cast<Float>(n);
        let p = cam.WorldToMap(wx, wy);
        let m = 100.0 * this.scale;
        if p.X < -m || p.X > viewW + m || p.Y < -m || p.Y > viewH + m {
            return;
        }
        let slot = this.clustersUsed;
        this.clustersUsed += 1;
        this.clWx[slot] = wx;
        this.clWy[slot] = wy;
        this.clWorld[slot] = worldSize;
        this.clTotal[slot] = n;
        // top 6 categories by count (repeated max over the 64 global slots)
        let maxCats = NMTheme.MaxGlobalCategories();
        let found = 0;
        let last = 2147483647;
        let lastIdx = -1;
        while found < 6 {
            let best = -1;
            let bestN = 0;
            let g = 0;
            while g < maxCats {
                let v = this.bCat[b * maxCats + g];
                let before = v < last || (v == last && g > lastIdx);
                if v > bestN && before {
                    best = g;
                    bestN = v;
                }
                g += 1;
            }
            if best < 0 {
                break;
            }
            this.clCats[slot * 6 + found] = best;
            this.clCatCount[slot * 6 + found] = bestN;
            last = bestN;
            lastIdx = best;
            found += 1;
        }
        this.clCatN[slot] = found;
        let c = found;
        while c < 6 {
            this.clCats[slot * 6 + c] = -1;
            this.clCatCount[slot * 6 + c] = 0;
            c += 1;
        }
        let bg = this.clBg[slot];
        let text = this.clText[slot];
        bg.SetTranslation(p);
        text.SetTranslation(p);
        if this.clShownCount[slot] != n {
            text.SetText(ToString(n));
            text.SetFontSize(Cast<Int32>((n >= 100 ? 40.0 : 52.0) * this.scale));
            this.clShownCount[slot] = n;
        }
        if !this.clOn[slot] {
            bg.SetVisible(true);
            text.SetVisible(true);
            this.clOn[slot] = true;
        }
        let shown = Min(found, 3);
        let mk = 0;
        while mk < 3 {
            let mi = slot * 3 + mk;
            if mk < shown {
                let g2 = this.clCats[slot * 6 + mk];
                let x = p.X + (Cast<Float>(mk) - Cast<Float>(shown - 1) * 0.5) * NMTheme.MiniSpacing() * this.scale;
                let y = p.Y + NMTheme.MiniOffsetY() * this.scale;
                this.miniBg[mi].SetTranslation(new Vector2(x, y));
                this.miniIcon[mi].SetTranslation(new Vector2(x, y));
                if this.miniCat[mi] != g2 {
                    let color = this.api.catColor[g2];
                    this.miniBg[mi].SetTintColor(color);
                    this.miniIcon[mi].SetTintColor(color);
                    if this.api.catHasIcon[g2] {
                        this.miniIcon[mi].SetAtlasResource(this.api.catAtlas[g2]);
                        this.miniIcon[mi].SetTexturePart(this.api.catPart[g2]);
                    } else {
                        this.miniIcon[mi].SetAtlasResource(NMTheme.UiAtlas());
                        this.miniIcon[mi].SetTexturePart(n"icon_dot");
                    }
                    this.miniCat[mi] = g2;
                }
                if !this.miniOn[mi] {
                    this.miniBg[mi].SetVisible(true);
                    this.miniIcon[mi].SetVisible(true);
                    this.miniOn[mi] = true;
                }
            } else if this.miniOn[mi] {
                this.miniBg[mi].SetVisible(false);
                this.miniIcon[mi].SetVisible(false);
                this.miniOn[mi] = false;
            }
            mk += 1;
        }
        ArrayPush(this.candX, p.X);
        ArrayPush(this.candY, p.Y);
        ArrayPush(this.candKind, 1);
        ArrayPush(this.candLayer, -1);
        ArrayPush(this.candItem, -1);
        ArrayPush(this.candSlot, slot);
    }

    private func HideUnused() {
        let firstUsed = NMTheme.ChipBudget() - this.chipsUsed;
        let s = 0;
        while s < firstUsed {
            if this.chipOn[s] {
                this.chipBg[s].SetVisible(false);
                this.chipIcon[s].SetVisible(false);
                this.chipOn[s] = false;
            }
            s += 1;
        }
        s = this.clustersUsed;
        while s < NMTheme.ClusterBudget() {
            if this.clOn[s] {
                this.clBg[s].SetVisible(false);
                this.clText[s].SetVisible(false);
                this.clOn[s] = false;
            }
            let mk = 0;
            while mk < 3 {
                let mi = s * 3 + mk;
                if this.miniOn[mi] {
                    this.miniBg[mi].SetVisible(false);
                    this.miniIcon[mi].SetVisible(false);
                    this.miniOn[mi] = false;
                }
                mk += 1;
            }
            s += 1;
        }
    }
}
```

- [ ] **Step 4: Implement the debug layer**

`r6/scripts/NightMap/Debug/DebugLayer.reds`:
```swift
module NightMap

public class NMDebugListener extends NightMapLayerListener {
    public let layer: wref<NightMapLayer>;
    public let api: wref<NightMap>;

    public func GetDetails(id: Int32) -> ref<NightMapDetails> {
        let L = this.layer;
        if !IsDefined(L) || !L.IsAlive(id) {
            return null;
        }
        let pos = L.Position(id);
        let g = this.api.CategoryIndex(L.CategoryOf(id));
        return NightMapDetails.Create(g >= 0 ? this.api.catDisplay[g] : "DEBUG", L.Label(id))
            .WithSubtitle("NightMap debug layer")
            .AddRow("ITEM", "#" + ToString(id))
            .AddRow("WORLD X", FloatToStringPrec(pos.X, 0))
            .AddRow("WORLD Y", FloatToStringPrec(pos.Y, 0))
            .WithDescription("Synthetic item used to test clustering, selection and performance.")
            .AddAction("ACT", "LOG THIS ITEM");
    }

    public func OnActivated(id: Int32) {
        NMLog.Info("DEBUG|activated|" + ToString(id));
    }
}

// Deterministic synthetic content: n items around 40 "neighbourhood" centers inside the map bounds.
public abstract class NMDebugLayer {
    public static func Id() -> CName {
        return n"NightMap.Debug";
    }

    public static func Fill(api: ref<NightMap>, n: Int32) -> ref<NightMapLayer> {
        let L = api.CreateLayer(NMDebugLayer.Id(), "Debug", 0);
        L.Clear();
        let names: array<CName> = [n"debug.quest", n"debug.gig", n"debug.vendor", n"debug.ft", n"debug.undisc"];
        let shows: array<String> = ["QUEST", "GIG", "VENDOR", "FAST TRAVEL", "UNDISCOVERED"];
        let parts: array<CName> = [n"icon_quest", n"icon_gig", n"icon_vendor", n"icon_ft", n"icon_undisc"];
        let colors: array<HDRColor> = [NMTheme.Yellow(), NMTheme.Pink(), NMTheme.Cyan(), NMTheme.Cyan(), NMTheme.Muted()];
        let c = 0;
        while c < 5 {
            L.SetCategory(names[c], shows[c], colors[c]);
            api.SetCategoryIcon(names[c], NMTheme.UiAtlas(), parts[c]);
            c += 1;
        }
        let minX = NMTileManifest.WorldMinX();
        let minY = NMTileManifest.WorldMinY();
        // Centers stay >= 1 km inside the bounds; offsets reach at most 1.8 km, and the API accepts bounds + 1 km.
        let spanX = NMTileManifest.WorldMaxX() - minX - 2000.0;
        let spanY = NMTileManifest.WorldMaxY() - minY - 2000.0;
        let seed = 12345;
        let bx: array<Float>;
        let by: array<Float>;
        let b = 0;
        while b < 40 {
            seed = (seed * 1103 + 12345) % 1000003;
            ArrayPush(bx, minX + 1000.0 + Cast<Float>(seed) / 1000003.0 * spanX);
            seed = (seed * 1103 + 12345) % 1000003;
            ArrayPush(by, minY + 1000.0 + Cast<Float>(seed) / 1000003.0 * spanY);
            b += 1;
        }
        let i = 0;
        while i < n {
            seed = (seed * 1103 + 12345) % 1000003;
            let k = seed % 40;
            let ox = 0.0;
            let oy = 0.0;
            let j = 0;
            while j < 3 {
                seed = (seed * 1103 + 12345) % 1000003;
                ox += (Cast<Float>(seed) / 1000003.0 - 0.5) * 1200.0;
                seed = (seed * 1103 + 12345) % 1000003;
                oy += (Cast<Float>(seed) / 1000003.0 - 0.5) * 1200.0;
                j += 1;
            }
            let ci = i % 5;
            L.Add(NightMapItem.Create(new Vector4(bx[k] + ox, by[k] + oy, 0.0, 1.0), names[ci], NMTheme.UiAtlas(), parts[ci])
                .WithLabel(shows[ci] + " " + ToString(i)));
            i += 1;
        }
        let listener = new NMDebugListener();
        listener.layer = L;
        listener.api = api;
        L.SetListener(listener);
        return L;
    }

    public static func Remove(api: ref<NightMap>) {
        api.RemoveLayer(NMDebugLayer.Id());
    }
}
```

- [ ] **Step 5: Wire into the system**

In `Core/NightMapSystem.reds` add the field `private let renderer: ref<NMItemRenderer>;` and replace the hooks and `HandleDebug`:
```swift
    private func OnOpened() {
        this.tiles = NMTileLayer.Create(this.panel.tiles);
        this.renderer = NMItemRenderer.Create(this.api, this.panel.items, this.panel.layout.scale);
    }

    private func OnClosing() {
        this.tiles = null;
        this.renderer = null;
    }

    private func UpdateModules(dt: Float) {
        this.tiles.Update(this.camera);
        if this.renderer.pendingImages > 0 && this.frameNo % 15 == 0 {
            this.renderer.Invalidate();   // poll RedIMG images that were still loading
        }
        this.renderer.Update(this.camera, this.panel.layout.mapW, this.panel.layout.mapH);
    }

    private func HandleDebug(s: ref<NightMapSettings>) {
        if this.input.debugSelfTest {
            this.input.debugSelfTest = false;
            if s.debug {
                let t = new NMSelfTest();
                t.Run();
            }
        }
        if this.input.debugLayer {
            this.input.debugLayer = false;
            if s.debug {
                if IsDefined(this.api.GetLayer(NMDebugLayer.Id())) {
                    NMDebugLayer.Remove(this.api);
                    NMLog.Info("debug layer off");
                } else {
                    NMDebugLayer.Fill(this.api, 5000);
                    NMLog.Info("debug layer on (5000 items)");
                }
            }
        }
        this.input.debugPerf = false;
        this.input.debugCalib = false;
    }
```

- [ ] **Step 6: Run the compile check**

Run: `tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 7: Commit**

```bash
git add r6/scripts/NightMap
git commit -m "Render: pooled item renderer with pyramid clustering and budgets; deterministic debug layer"
```

---

### Task 14: Crosshair, info card, player marker, act, header/scale/hints

**Files:**
- Create: `r6/scripts/NightMap/Render/Crosshair.reds`, `Render/InfoCard.reds`, `Render/PlayerMarker.reds`
- Modify: `Core/NightMapSystem.reds`, `Debug/SelfTest.reds` (add `PickCases`)

**Interfaces:**
- Consumes: `NMItemRenderer` candidates, highlights and cluster data (Task 13); `NightMapLayerListener`/`NightMapDetails` (Task 9); `NMPanel` widgets (Task 10).
- Produces:
  - **`NMCrosshair`:** `Create(parent, viewW, viewH, scale)`, `.Update(r, viewW, viewH, scale) -> Bool` (selection changed), fields `sel, selKind, selLayer, selItem, selX, selY`, static `Pick(xs, ys, kinds, layers, items, cx, cy, radius, prevKind, prevLayer, prevItem, prevX, prevY) -> Int32`.
  - **`NMInfoCard`:** `Create(parent, width, scale)`, `.ShowDetails(d, color)`, `.ShowCluster(total, cats, counts, api, actKey)`, `.ShowEmpty()`.
  - **`NMPlayerMarker`:** `Create(parent, scale)`, `.Update(cam, player, viewW, viewH)`.

- [ ] **Step 1: Add the failing pick cases**

In `Debug/SelfTest.reds`, add `this.PickCases();` to `Run()` after `RendererCases`, and add:
```swift
    private func PickCases() {
        let xs: array<Float> = [100.0, 130.0, 300.0];
        let ys: array<Float> = [100.0, 100.0, 100.0];
        let kinds: array<Int32> = [0, 0, 1];
        let layers: array<Int32> = [0, 0, -1];
        let items: array<Int32> = [5, 6, -1];
        this.Check("pick.nearest", NMCrosshair.Pick(xs, ys, kinds, layers, items, 114.0, 100.0, 50.0, -1, -1, -1, 0.0, 0.0) == 0, "");
        this.Check("pick.sticky_within_4px", NMCrosshair.Pick(xs, ys, kinds, layers, items, 116.0, 100.0, 50.0, 0, 0, 5, 100.0, 100.0) == 0, "");
        this.Check("pick.switches_beyond_4px", NMCrosshair.Pick(xs, ys, kinds, layers, items, 124.0, 100.0, 50.0, 0, 0, 5, 100.0, 100.0) == 1, "");
        this.Check("pick.removed_selection_falls_back", NMCrosshair.Pick(xs, ys, kinds, layers, items, 116.0, 100.0, 50.0, 0, 0, 7, 100.0, 100.0) == 1, "");
        this.Check("pick.none_in_radius", NMCrosshair.Pick(xs, ys, kinds, layers, items, 1000.0, 1000.0, 50.0, -1, -1, -1, 0.0, 0.0) == -1, "");
        this.Check("pick.cluster", NMCrosshair.Pick(xs, ys, kinds, layers, items, 290.0, 100.0, 50.0, 1, -1, -1, 300.0, 100.0) == 2, "");
        let empty: array<Float>;
        let emptyI: array<Int32>;
        this.Check("pick.empty_candidates", NMCrosshair.Pick(empty, empty, emptyI, emptyI, emptyI, 0.0, 0.0, 50.0, 0, 0, 5, 0.0, 0.0) == -1, "");
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `tools/check.sh`
Expected: `COMPILE FAILED` (unresolved `NMCrosshair`).

- [ ] **Step 3: Implement crosshair, card and marker**

`r6/scripts/NightMap/Render/Crosshair.reds`:
```swift
module NightMap

// Fixed reticle at the map-area center; selects the nearest candidate within SelectRadius.
public class NMCrosshair {
    public let sel: Int32 = -1;
    public let selKind: Int32 = -1;
    public let selLayer: Int32 = -1;
    public let selItem: Int32 = -1;
    public let selX: Float;
    public let selY: Float;

    public static func Create(parent: ref<inkCanvas>, viewW: Float, viewH: Float, scale: Float) -> ref<NMCrosshair> {
        let c = new NMCrosshair();
        let cx = viewW * 0.5;
        let cy = viewH * 0.5;
        NMUi.Image(parent, n"ring", cx, cy, NMTheme.RingSize() * scale, NMTheme.Cyan(), true);
        let a = 154.0 * scale;
        let len = 39.0 * scale;
        let w = 5.0 * scale;
        NMUi.Rect(parent, cx - a, cy - w * 0.5, len, w, NMTheme.Cyan(), 0.95);
        NMUi.Rect(parent, cx + a - len, cy - w * 0.5, len, w, NMTheme.Cyan(), 0.95);
        NMUi.Rect(parent, cx - w * 0.5, cy - a, w, len, NMTheme.Cyan(), 0.95);
        NMUi.Rect(parent, cx - w * 0.5, cy + a - len, w, len, NMTheme.Cyan(), 0.95);
        return c;
    }

    // Nearest candidate within radius; the previous selection is kept while it is within 4 units of the
    // nearest one (prevents flicker). Chips are identified by layer+item, clusters by screen position.
    public static func Pick(xs: array<Float>, ys: array<Float>, kinds: array<Int32>, layers: array<Int32>, items: array<Int32>,
                            cx: Float, cy: Float, radius: Float, prevKind: Int32, prevLayer: Int32, prevItem: Int32, prevX: Float, prevY: Float) -> Int32 {
        let r2 = radius * radius;
        let best = -1;
        let bestD = 0.0;
        let prev = -1;
        let prevD = 0.0;
        let i = 0;
        while i < ArraySize(xs) {
            let dx = xs[i] - cx;
            let dy = ys[i] - cy;
            let d = dx * dx + dy * dy;
            if d <= r2 {
                if best < 0 || d < bestD {
                    best = i;
                    bestD = d;
                }
                let same = false;
                if kinds[i] == prevKind {
                    if prevKind == 0 {
                        same = layers[i] == prevLayer && items[i] == prevItem;
                    } else {
                        same = AbsF(xs[i] - prevX) < 4.0 && AbsF(ys[i] - prevY) < 4.0;
                    }
                }
                if same {
                    prev = i;
                    prevD = d;
                }
            }
            i += 1;
        }
        if prev >= 0 && SqrtF(prevD) <= SqrtF(bestD) + 4.0 {
            return prev;
        }
        return best;
    }

    public func Update(r: ref<NMItemRenderer>, viewW: Float, viewH: Float, scale: Float) -> Bool {
        let idx = NMCrosshair.Pick(r.candX, r.candY, r.candKind, r.candLayer, r.candItem, viewW * 0.5, viewH * 0.5,
            NMTheme.SelectRadius() * scale, this.selKind, this.selLayer, this.selItem, this.selX, this.selY);
        let kind = idx >= 0 ? r.candKind[idx] : -1;
        let layer = idx >= 0 ? r.candLayer[idx] : -1;
        let item = idx >= 0 ? r.candItem[idx] : -1;
        let x = idx >= 0 ? r.candX[idx] : 0.0;
        let y = idx >= 0 ? r.candY[idx] : 0.0;
        let changed = kind != this.selKind || layer != this.selLayer || item != this.selItem
            || (kind == 1 && (AbsF(x - this.selX) >= 4.0 || AbsF(y - this.selY) >= 4.0));
        this.sel = idx;
        this.selKind = kind;
        this.selLayer = layer;
        this.selItem = item;
        this.selX = x;
        this.selY = y;
        r.selChip.SetVisible(kind == 0);
        r.selCluster.SetVisible(kind == 1);
        if kind == 0 {
            r.selChip.SetTranslation(new Vector2(x, y));
        } else if kind == 1 {
            r.selCluster.SetTranslation(new Vector2(x, y));
        }
        return changed;
    }
}
```

`r6/scripts/NightMap/Render/InfoCard.reds`:
```swift
module NightMap

// Docked card (right column). Fixed layout in 4K units * scale.
public class NMInfoCard {
    private let s: Float;
    private let pad: Float;
    private let category: ref<inkText>;
    private let title: ref<inkText>;
    private let subtitle: ref<inkText>;
    private let divider: ref<inkRectangle>;
    private let rowKey: array<ref<inkText>>;
    private let rowVal: array<ref<inkText>>;
    private let rowChip: array<ref<inkImage>>;
    private let rowIcon: array<ref<inkImage>>;
    private let desc: ref<inkText>;
    private let actBox: array<ref<inkRectangle>>;
    private let actKey: array<ref<inkText>>;
    private let actLabel: array<ref<inkText>>;
    private let empty: ref<inkText>;

    public static func Create(parent: ref<inkCanvas>, width: Float, scale: Float) -> ref<NMInfoCard> {
        let c = new NMInfoCard();
        let s = scale;
        c.s = s;
        c.pad = 62.0 * s;
        c.category = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(34.0 * s), NMTheme.Pink());
        c.category.SetTranslation(new Vector2(c.pad, 96.0 * s));
        c.title = NMUi.Text(parent, NMTheme.HeadingFont(), n"Bold", Cast<Int32>(58.0 * s), NMTheme.Text());
        c.title.SetTranslation(new Vector2(c.pad, 150.0 * s));
        c.subtitle = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(36.0 * s), NMTheme.Cyan());
        c.subtitle.SetTranslation(new Vector2(c.pad, 240.0 * s));
        c.divider = NMUi.Rect(parent, c.pad, 300.0 * s, width - 2.0 * c.pad, 2.0 * s, NMTheme.Cyan(), 0.35);
        let i = 0;
        while i < 6 {
            let y = 360.0 * s + Cast<Float>(i) * 80.0 * s;
            let k = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(31.0 * s), NMTheme.Muted());
            k.SetTranslation(new Vector2(c.pad, y));
            let v = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(36.0 * s), NMTheme.Text());
            v.SetTranslation(new Vector2(c.pad + 312.0 * s, y));
            let chip = NMUi.Image(parent, n"mini", c.pad + 26.0 * s, y + 20.0 * s, NMTheme.MiniSize() * 0.7 * s, NMTheme.Cyan(), true);
            let icon = NMUi.Image(parent, n"icon_dot", c.pad + 26.0 * s, y + 20.0 * s, NMTheme.IconSize() * 0.6 * s, NMTheme.Cyan(), true);
            ArrayPush(c.rowKey, k);
            ArrayPush(c.rowVal, v);
            ArrayPush(c.rowChip, chip);
            ArrayPush(c.rowIcon, icon);
            i += 1;
        }
        c.desc = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(31.0 * s), NMTheme.Text());
        c.desc.SetTranslation(new Vector2(c.pad, 860.0 * s));
        c.desc.SetWrapping(true, width - 2.0 * c.pad);
        c.desc.SetOpacity(0.8);
        i = 0;
        while i < 3 {
            let y = 1060.0 * s + Cast<Float>(i) * 100.0 * s;
            ArrayPush(c.actBox, NMUi.Rect(parent, c.pad, y, 130.0 * s, 70.0 * s, NMTheme.Cyan(), 0.15));
            let kt = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(30.0 * s), NMTheme.Cyan());
            kt.SetTranslation(new Vector2(c.pad + 16.0 * s, y + 16.0 * s));
            ArrayPush(c.actKey, kt);
            let lt = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(36.0 * s), NMTheme.Text());
            lt.SetTranslation(new Vector2(c.pad + 168.0 * s, y + 14.0 * s));
            ArrayPush(c.actLabel, lt);
            i += 1;
        }
        c.empty = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(34.0 * s), NMTheme.Muted());
        c.empty.SetTranslation(new Vector2(c.pad, 96.0 * s));
        c.empty.SetText("NO SELECTION");
        c.ShowEmpty();
        return c;
    }

    private func SetMain(visible: Bool) {
        this.category.SetVisible(visible);
        this.title.SetVisible(visible);
        this.subtitle.SetVisible(visible);
        this.divider.SetVisible(visible);
        this.empty.SetVisible(!visible);
    }

    private func SetRows(n: Int32, chips: Bool) {
        let i = 0;
        while i < 6 {
            let on = i < n;
            this.rowKey[i].SetVisible(on);
            this.rowVal[i].SetVisible(on);
            this.rowChip[i].SetVisible(on && chips);
            this.rowIcon[i].SetVisible(on && chips);
            let y = 360.0 * this.s + Cast<Float>(i) * 80.0 * this.s;
            this.rowKey[i].SetTranslation(new Vector2(this.pad + (chips ? 70.0 * this.s : 0.0), y));
            i += 1;
        }
    }

    private func SetActions(keys: array<String>, labels: array<String>) {
        let i = 0;
        while i < 3 {
            let on = i < ArraySize(keys);
            this.actBox[i].SetVisible(on);
            this.actKey[i].SetVisible(on);
            this.actLabel[i].SetVisible(on);
            if on {
                this.actKey[i].SetText(keys[i]);
                this.actLabel[i].SetText(StrUpper(labels[i]));
            }
            i += 1;
        }
    }

    public func ShowDetails(d: ref<NightMapDetails>, color: HDRColor) {
        this.SetMain(true);
        this.category.SetText(StrUpper(d.category));
        this.category.SetTintColor(color);
        this.title.SetText(StrUpper(d.title));
        this.subtitle.SetText(d.subtitle);
        let n = ArraySize(d.rowKeys);
        let i = 0;
        while i < n {
            this.rowKey[i].SetText(StrUpper(d.rowKeys[i]));
            this.rowVal[i].SetText(d.rowValues[i]);
            i += 1;
        }
        this.SetRows(n, false);
        this.desc.SetText(d.description);
        this.desc.SetVisible(NotEquals(d.description, ""));
        this.SetActions(d.actionKeys, d.actionLabels);
    }

    public func ShowCluster(total: Int32, cats: array<Int32>, counts: array<Int32>, api: ref<NightMap>, actKey: String) {
        this.SetMain(true);
        this.category.SetText("CLUSTER");
        this.category.SetTintColor(NMTheme.Cyan());
        this.title.SetText(ToString(total) + " LOCATIONS");
        this.subtitle.SetText("");
        let n = Min(ArraySize(cats), 6);
        let i = 0;
        while i < n {
            let g = cats[i];
            let color = api.catColor[g];
            this.rowKey[i].SetText(StrUpper(api.catDisplay[g]));
            this.rowVal[i].SetText(ToString(counts[i]));
            this.rowChip[i].SetTintColor(color);
            this.rowIcon[i].SetTintColor(color);
            if api.catHasIcon[g] {
                this.rowIcon[i].SetAtlasResource(api.catAtlas[g]);
                this.rowIcon[i].SetTexturePart(api.catPart[g]);
            } else {
                this.rowIcon[i].SetAtlasResource(NMTheme.UiAtlas());
                this.rowIcon[i].SetTexturePart(n"icon_dot");
            }
            i += 1;
        }
        this.SetRows(n, true);
        this.desc.SetVisible(false);
        let keys: array<String> = [actKey];
        let labels: array<String> = ["Zoom into cluster"];
        this.SetActions(keys, labels);
    }

    public func ShowEmpty() {
        this.SetMain(false);
        this.SetRows(0, false);
        this.desc.SetVisible(false);
        let none: array<String>;
        this.SetActions(none, none);
    }
}
```

`r6/scripts/NightMap/Render/PlayerMarker.reds`:
```swift
module NightMap

public class NMPlayerMarker {
    private let img: ref<inkImage>;
    private let shown: Bool;

    public static func Create(parent: ref<inkCanvas>, scale: Float) -> ref<NMPlayerMarker> {
        let m = new NMPlayerMarker();
        m.img = NMUi.Image(parent, n"player", 0.0, 0.0, NMTheme.PlayerSize() * scale, NMTheme.Cyan(), true);
        m.img.SetRenderTransformPivot(new Vector2(0.5, 0.5));
        m.img.SetVisible(false);
        return m;
    }

    public func Update(cam: ref<NMCamera>, player: ref<GameObject>, viewW: Float, viewH: Float) {
        let visible = false;
        if IsDefined(player) {
            let pos = player.GetWorldPosition();
            let fwd = player.GetWorldForward();
            let p = cam.WorldToMap(pos.X, pos.Y);
            visible = p.X >= 0.0 && p.X <= viewW && p.Y >= 0.0 && p.Y <= viewH;
            if visible {
                this.img.SetTranslation(p);
                this.img.SetRotation(NMMath.HeadingDeg(fwd.X, fwd.Y) * NMTheme.PlayerRotationSign());
            }
        }
        if visible != this.shown {
            this.img.SetVisible(visible);
            this.shown = visible;
        }
    }
}
```

- [ ] **Step 4: Wire into the system**

In `Core/NightMapSystem.reds` add fields:
```swift
    private let crosshair: ref<NMCrosshair>;
    private let card: ref<NMInfoCard>;
    private let marker: ref<NMPlayerMarker>;
    private let cardApiRev: Int32 = -1;
```
Replace `OnOpened`, `OnClosing` and `UpdateModules`, and add the helpers below them:
```swift
    private func OnOpened() {
        let l = this.panel.layout;
        this.tiles = NMTileLayer.Create(this.panel.tiles);
        this.renderer = NMItemRenderer.Create(this.api, this.panel.items, l.scale);
        this.marker = NMPlayerMarker.Create(this.panel.overlay, l.scale);
        this.crosshair = NMCrosshair.Create(this.panel.overlay, l.mapW, l.mapH, l.scale);
        this.card = NMInfoCard.Create(this.panel.card, l.cardW, l.scale);
        this.UpdateHeader();
    }

    private func OnClosing() {
        this.tiles = null;
        this.renderer = null;
        this.marker = null;
        this.crosshair = null;
        this.card = null;
    }

    private func UpdateModules(dt: Float) {
        let l = this.panel.layout;
        this.tiles.Update(this.camera);
        if this.renderer.pendingImages > 0 && this.frameNo % 15 == 0 {
            this.renderer.Invalidate();
        }
        let relaid = this.renderer.Update(this.camera, l.mapW, l.mapH);
        if relaid {
            let changed = this.crosshair.Update(this.renderer, l.mapW, l.mapH, l.scale);
            // Re-query card content only when the selection or the data changed, not on every pan frame.
            if changed || this.api.revision != this.cardApiRev {
                this.cardApiRev = this.api.revision;
                this.RefreshCard(changed);
            }
        }
        if this.input.act {
            this.input.act = false;
            this.Activate();
        }
        this.marker.Update(this.camera, GetPlayer(this.GetGameInstance()), l.mapW, l.mapH);
        if this.frameNo % 30 == 0 {
            this.UpdateHeader();
        }
    }

    private func RefreshCard(changed: Bool) {
        let c = this.crosshair;
        if c.selKind == 0 && c.selLayer >= 0 && c.selLayer < ArraySize(this.api.layers) {
            let L = this.api.layers[c.selLayer];
            if !L.IsAlive(c.selItem) {
                this.card.ShowEmpty();
                return;
            }
            let d: ref<NightMapDetails>;
            if IsDefined(L.listener) {
                d = L.listener.GetDetails(c.selItem);
                if changed {
                    L.listener.OnSelected(c.selItem);
                }
            }
            if !IsDefined(d) {
                d = this.DefaultDetails(L, c.selItem);
            }
            this.card.ShowDetails(d, this.api.catColor[L.catGlobal[L.cat[c.selItem]]]);
        } else if c.selKind == 1 && c.sel >= 0 {
            let slot = this.renderer.candSlot[c.sel];
            let cats: array<Int32>;
            let counts: array<Int32>;
            let k = 0;
            while k < this.renderer.clCatN[slot] {
                ArrayPush(cats, this.renderer.clCats[slot * 6 + k]);
                ArrayPush(counts, this.renderer.clCatCount[slot * 6 + k]);
                k += 1;
            }
            let s = this.Settings();
            this.card.ShowCluster(this.renderer.clTotal[slot], cats, counts, this.api, IsDefined(s) ? NMInput.KeyName(s.keyAct) : "ACT");
        } else {
            this.card.ShowEmpty();
        }
    }

    private func DefaultDetails(L: ref<NightMapLayer>, id: Int32) -> ref<NightMapDetails> {
        let g = L.catGlobal[L.cat[id]];
        let title = NotEquals(L.label[id], "") ? L.label[id] : this.api.catDisplay[g];
        let d = NightMapDetails.Create(this.api.catDisplay[g], title);
        let player = GetPlayer(this.GetGameInstance());
        if IsDefined(player) {
            let p = player.GetWorldPosition();
            let dx = L.px[id] - p.X;
            let dy = L.py[id] - p.Y;
            d.AddRow("Distance", NMMath.FormatMeters(SqrtF(dx * dx + dy * dy)));
        }
        return d;
    }

    private func Activate() {
        let c = this.crosshair;
        if c.selKind == 0 && c.selLayer >= 0 && c.selLayer < ArraySize(this.api.layers) {
            let L = this.api.layers[c.selLayer];
            if IsDefined(L.listener) && L.IsAlive(c.selItem) {
                L.listener.OnActivated(c.selItem);
            }
        } else if c.selKind == 1 && c.sel >= 0 {
            let slot = this.renderer.candSlot[c.sel];
            let l = this.panel.layout;
            let target = this.renderer.clWorld[slot] / (0.6 * MinF(l.mapW, l.mapH));
            this.camera.follow = false;
            this.camera.EaseTo(this.renderer.clWx[slot], this.renderer.clWy[slot], target, 300.0);
        }
    }

    private func UpdateHeader() {
        let s = this.Settings();
        let l = this.panel.layout;
        this.panel.subtitle.SetText(this.DistrictName());
        let maxMeters = 336.0 * l.scale * this.camera.mpp;
        let len = NMMath.NiceLength(maxMeters);
        this.panel.scaleBar.SetSize(new Vector2(len / this.camera.mpp, 5.0 * l.scale));
        this.panel.scaleLabel.SetText(NMMath.FormatMeters(len));
        if IsDefined(s) {
            let hint = NMInput.HintText(s);
            if this.input.arrowSeen {
                hint += "   ·   ARROW KEYS IGNORED - TURN NUMLOCK ON";
            }
            this.panel.hints.SetText(hint);
        }
    }

    private func DistrictName() -> String {
        let ps = GameInstance.GetScriptableSystemsContainer(this.GetGameInstance()).Get(n"PreventionSystem") as PreventionSystem;
        if !IsDefined(ps) {
            return "";
        }
        let d = ps.GetCurrentDistrict();
        if !IsDefined(d) {
            return "";
        }
        let rec = d.GetDistrictRecord();
        return IsDefined(rec) ? StrUpper(GetLocalizedText(rec.LocalizedName())) : "";
    }
```

- [ ] **Step 5: Run the compile check**

Run: `tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 6: Commit**

```bash
git add r6/scripts/NightMap
git commit -m "Render: crosshair selection (sticky), docked info card, player marker, act (cluster zoom / item activate), header/scale/hints"
```

---

### Task 15: Calibration dump, performance suite, results tool

**Files:**
- Create: `r6/scripts/NightMap/Debug/Calibration.reds`, `Debug/PerfSuite.reds`, `tools/results.py`, `tools/test_results.py`
- Modify: `Core/NightMapSystem.reds` (perf hooks, debug chords, hidden mode)

**Interfaces:**
- Consumes: `NMDebugLayer` (Task 13), `NMClock` (Task 8), and `NightMapSystem.Camera()` / `Api()`.
- Produces:
  - **`NMCalibration.Dump(game) -> Int32`:** logs `CALIB|<name>#<n>|x|y|z` lines plus `CALIB|DONE|n`.
  - **`NMPerfSuite`:** `.Start()`, `.Step(sys, dt, scriptMs)`, `.running`. Logs `PERF|SUITE|start`, `RESULT|<name>|items=..|frames=..|setup_ms=..|frame_avg=..|frame_p95=..|frame_p99=..|frame_max=..|script_avg=..|script_p95=..` and `PERF|SUITE|done`.
  - **`NightMapSystem.SetPerfHidden(Bool)`.**
  - **`tools/results.py [gamelog]`:** prints a table, exits 0 on PASS and 1 on FAIL. Its `parse(text) -> list[dict]` and `verdict(rows) -> tuple[bool, str]` are importable.

- [ ] **Step 1: Write the failing results-tool tests**

`tools/test_results.py`:
```python
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("results", Path(__file__).with_name("results.py"))
results = importlib.util.module_from_spec(spec)
spec.loader.exec_module(results)

LOG = """
[t] [1] [NightMap] PERF|SUITE|start
[t] [1] [NightMap] RESULT|closed_baseline|items=0|frames=300|setup_ms=0.1|frame_avg=20.0|frame_p95=29.0|frame_p99=40.0|frame_max=60.0|script_avg=0.01|script_p95=0.02
[t] [1] [NightMap] RESULT|items_50000|items=50000|frames=300|setup_ms=900.0|frame_avg=22.5|frame_p95=33.0|frame_p99=45.0|frame_max=70.0|script_avg=1.9|script_p95=3.0
[t] [1] [NightMap] PERF|SUITE|done
"""


def test_parse_reads_latest_suite():
    rows = results.parse("[t] [1] [NightMap] RESULT|old|items=1|frames=1|setup_ms=0|frame_avg=1|frame_p95=1|frame_p99=1|frame_max=1|script_avg=0|script_p95=0\n" + LOG)
    assert [r["name"] for r in rows] == ["closed_baseline", "items_50000"]
    assert rows[1]["frame_avg"] == 22.5


def test_verdict_pass_and_fail():
    ok, msg = results.verdict(results.parse(LOG))
    assert ok, msg
    bad = LOG.replace("frame_avg=22.5", "frame_avg=24.0")
    ok, msg = results.verdict(results.parse(bad))
    assert not ok and "avg" in msg


def test_verdict_requires_both_rows():
    ok, msg = results.verdict([])
    assert not ok
```

Run: `python3 -m pytest -q tools/test_results.py`
Expected: FAIL (`results.py` missing).

- [ ] **Step 2: Implement `tools/results.py`**

```python
#!/usr/bin/env python3
"""Summarize NightMap PerfSuite results from CET's gamelog.log (latest suite run) and judge the spec target."""
import re
import sys
from pathlib import Path

GAMELOG = Path.home() / "cyberpunk_symlink/bin/x64/plugins/cyber_engine_tweaks/gamelog.log"
AVG_BUDGET_MS = 3.0
P95_BUDGET_MS = 6.0


def parse(text: str) -> list[dict]:
    lines = [l for l in text.splitlines() if "[NightMap]" in l]
    starts = [i for i, l in enumerate(lines) if "PERF|SUITE|start" in l]
    run = lines[starts[-1]:] if starts else lines
    rows = []
    for l in run:
        m = re.search(r"RESULT\|([^|]+)\|(.*)$", l)
        if not m:
            continue
        row = {"name": m.group(1)}
        for part in m.group(2).split("|"):
            k, _, v = part.partition("=")
            row[k] = float(v)
        rows.append(row)
    return rows


def verdict(rows: list[dict]) -> tuple[bool, str]:
    by = {r["name"]: r for r in rows}
    if "closed_baseline" not in by or "items_50000" not in by:
        return False, "missing closed_baseline or items_50000 row"
    base, test = by["closed_baseline"], by["items_50000"]
    d_avg = test["frame_avg"] - base["frame_avg"]
    d_p95 = test["frame_p95"] - base["frame_p95"]
    ok = d_avg <= AVG_BUDGET_MS and d_p95 <= P95_BUDGET_MS
    return ok, f"items_50000: avg +{d_avg:.2f} ms (budget {AVG_BUDGET_MS}), p95 +{d_p95:.2f} ms (budget {P95_BUDGET_MS})"


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else GAMELOG
    rows = parse(path.read_text(errors="replace"))
    if not rows:
        print(f"no RESULT lines in {path}")
        return 1
    base = next((r["frame_avg"] for r in rows if r["name"] == "closed_baseline"), None)
    print(f"{'scenario':18} {'items':>7} {'setup ms':>9} {'avg':>7} {'+base':>7} {'p95':>7} {'p99':>7} {'max':>7} {'script':>7}")
    for r in rows:
        delta = f"{r['frame_avg'] - base:+.2f}" if base is not None else "?"
        print(f"{r['name']:18} {int(r['items']):>7} {r['setup_ms']:>9.1f} {r['frame_avg']:>7.2f} {delta:>7} "
              f"{r['frame_p95']:>7.2f} {r['frame_p99']:>7.2f} {r['frame_max']:>7.2f} {r['script_avg']:>7.2f}")
    ok, msg = verdict(rows)
    print(("PASS: " if ok else "FAIL: ") + msg)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
```

Run: `python3 -m pytest -q tools/test_results.py`
Expected: `3 passed`.

- [ ] **Step 3: Implement calibration and the perf suite**

`r6/scripts/NightMap/Debug/Calibration.reds`:
```swift
module NightMap

// Logs every fast-travel point's world position for tools/tiles (python3 -m nmtiles.calib).
public abstract class NMCalibration {
    public static func Dump(game: GameInstance) -> Int32 {
        let n = 0;
        for m in GameInstance.GetMappinSystem(game).GetAllMappins() {
            let ft = m as FastTravelMappin;
            if IsDefined(ft) {
                let pos = ft.GetWorldPosition();
                let data = ft.GetPointData();
                let name = IsDefined(data) ? data.GetPointDisplayName() : "ft";
                NMLog.Info("CALIB|" + name + "#" + ToString(n) + "|" + FloatToStringPrec(pos.X, 2) + "|" + FloatToStringPrec(pos.Y, 2) + "|" + FloatToStringPrec(pos.Z, 2));
                n += 1;
            }
        }
        NMLog.Info("CALIB|DONE|" + ToString(n));
        return n;
    }
}
```

`r6/scripts/NightMap/Debug/PerfSuite.reds`:
```swift
module NightMap

// Same camera path for every scenario: a 2.5 km circle with a zoom sweep across 1..16 m/unit.
// "closed" scenarios keep the frame loop running but hide the panel and skip all module work.
public class NMPerfSuite {
    public let running: Bool;
    private let names: array<String>;
    private let counts: array<Int32>;
    private let shows: array<Bool>;
    private let idx: Int32;
    private let phase: Int32;
    private let frames: Int32;
    private let setupMs: Float;
    private let samples: array<Float>;
    private let script: array<Float>;

    private func Add(name: String, count: Int32, show: Bool) {
        ArrayPush(this.names, name);
        ArrayPush(this.counts, count);
        ArrayPush(this.shows, show);
    }

    public func Start() {
        ArrayClear(this.names);
        ArrayClear(this.counts);
        ArrayClear(this.shows);
        this.Add("closed_baseline", 0, false);
        this.Add("open_empty", 0, true);
        this.Add("items_5000", 5000, true);
        this.Add("items_20000", 20000, true);
        this.Add("items_50000", 50000, true);
        this.Add("closed_end", 0, false);
        this.idx = 0;
        this.phase = 0;
        this.running = true;
        NMLog.Info("PERF|SUITE|start");
    }

    public func Step(sys: ref<NightMapSystem>, dt: Float, scriptMs: Float) {
        if this.phase == 0 {
            let t0 = NMClock.NowMs();
            if this.counts[this.idx] > 0 {
                NMDebugLayer.Fill(sys.Api(), this.counts[this.idx]);
            } else {
                NMDebugLayer.Remove(sys.Api());
            }
            this.setupMs = NMClock.NowMs() - t0;
            sys.SetPerfHidden(!this.shows[this.idx]);
            this.phase = 1;
            this.frames = 0;
            return;
        }
        this.frames += 1;
        if this.phase == 1 {
            if this.frames >= 30 {
                this.phase = 2;
                this.frames = 0;
                ArrayClear(this.samples);
                ArrayClear(this.script);
            }
            return;
        }
        let a = 6.2831853 * Cast<Float>(this.frames) / 300.0;
        let cam = sys.Camera();
        cam.follow = false;
        cam.SetCenter(-700.0 + 2500.0 * CosF(a), 1500.0 + 2500.0 * SinF(a));
        cam.SetMpp(PowF(16.0, 0.5 - 0.5 * CosF(2.0 * a)));
        ArrayPush(this.samples, dt);
        ArrayPush(this.script, scriptMs);
        if this.frames >= 300 {
            this.Report();
            this.idx += 1;
            this.phase = 0;
            if this.idx >= ArraySize(this.names) {
                this.running = false;
                NMDebugLayer.Remove(sys.Api());
                sys.SetPerfHidden(false);
                NMLog.Info("PERF|SUITE|done");
            }
        }
    }

    private func Report() {
        NMLog.Info("RESULT|" + this.names[this.idx] + "|items=" + ToString(this.counts[this.idx]) + "|frames=" + ToString(ArraySize(this.samples))
            + "|setup_ms=" + FloatToStringPrec(this.setupMs, 1) + "|" + NMPerfSuite.Stats("frame", this.samples, true) + "|" + NMPerfSuite.Stats("script", this.script, false));
    }

    // frame_avg|frame_p95|frame_p99|frame_max  (or script_avg|script_p95)
    public static func Stats(label: String, values: array<Float>, full: Bool) -> String {
        let n = ArraySize(values);
        if n == 0 {
            return label + "_avg=0|" + label + "_p95=0" + (full ? "|" + label + "_p99=0|" + label + "_max=0" : "");
        }
        let sorted: array<Float>;
        let sum = 0.0;
        for v in values {
            sum += v;
            let j = ArraySize(sorted);
            ArrayPush(sorted, v);
            while j > 0 && sorted[j - 1] > v {
                sorted[j] = sorted[j - 1];
                j -= 1;
            }
            sorted[j] = v;
        }
        let out = label + "_avg=" + FloatToStringPrec(sum / Cast<Float>(n), 3) + "|" + label + "_p95=" + FloatToStringPrec(sorted[(n * 95) / 100], 3);
        if full {
            out += "|" + label + "_p99=" + FloatToStringPrec(sorted[(n * 99) / 100], 3) + "|" + label + "_max=" + FloatToStringPrec(sorted[n - 1], 3);
        }
        return out;
    }
}
```

- [ ] **Step 4: Wire into the system**

In `Core/NightMapSystem.reds`:
- Add fields `private let perf: ref<NMPerfSuite>;` and `private let perfHidden: Bool;`.
- Add the method `SetPerfHidden`.
- Replace `Tick` so it measures module time and drives the suite.
- Extend `HandleDebug` with the perf and calibration chords.

```swift
    public func SetPerfHidden(hidden: Bool) {
        this.perfHidden = hidden;
        if IsDefined(this.panel) {
            this.panel.root.SetVisible(!hidden);
        }
    }

    public func Tick() {
        if !this.isOpen {
            this.loopAlive = false;
            return;
        }
        let now = NMClock.NowMs();
        let raw = now - this.lastMs;              // true frame time, recorded by the perf suite
        let dt = ClampF(raw, 0.0, 100.0);         // clamped step for camera motion
        this.lastMs = now;
        this.frameNo += 1;
        this.DriveCamera(dt);
        let t0 = NMClock.NowMs();
        if !this.perfHidden {
            this.UpdateModules(dt);
        }
        let scriptMs = NMClock.NowMs() - t0;
        if IsDefined(this.perf) && this.perf.running {
            this.perf.Step(this, raw, scriptMs);
        }
        this.Schedule();
    }
```

In `HandleDebug`, replace the two lines `this.input.debugPerf = false;` and `this.input.debugCalib = false;` with:
```swift
        if this.input.debugPerf {
            this.input.debugPerf = false;
            if s.debug {
                if !NMClock.Precise() {
                    NMLog.Error("perf suite needs RedIMGRetriever (precise clock)");
                } else {
                    if !this.isOpen {
                        this.Open();
                    }
                    this.perf = new NMPerfSuite();
                    this.perf.Start();
                }
            }
        }
        if this.input.debugCalib {
            this.input.debugCalib = false;
            if s.debug {
                NMLog.Info("calibration points: " + ToString(NMCalibration.Dump(this.GetGameInstance())));
            }
        }
```

- [ ] **Step 5: Run the compile check and tests**

Run: `tools/check.sh && python3 -m pytest -q tools/test_results.py`
Expected: `COMPILE OK`, `3 passed`.

- [ ] **Step 6: Commit**

```bash
git add r6/scripts/NightMap tools/results.py tools/test_results.py
git commit -m "Debug: fast-travel calibration dump, perf suite (closed/open/5k/20k/50k), results tool with spec budget verdict"
```

---

### Task 16: In-game checkpoint 2 (human-in-the-loop): visuals, alignment, performance

**Files:**
- Modify: `notes/CHECKPOINTS.md`; possibly `tools/tiles/calibration.json`, `Generated/TileManifest.reds` (rebuild); `Core/Theme.reds` (`PlayerRotationSign`) if the arrow is mirrored

- [ ] **Step 1: Install**

Run: `tools/install.sh`
Expected: `COMPILE OK` plus both install lines.

- [ ] **Step 2: Self-test**

Ask the user to restart the game, load a save, keep Debug on, open the map and press Ctrl+`\`. Then:

Run: `grep -a "\[NightMap\] TEST|" ~/cyberpunk_symlink/bin/x64/plugins/cyber_engine_tweaks/gamelog.log | tail -60`
Expected: `failed=0`. Fix any failure in its owning task and repeat.

- [ ] **Step 3: Calibration**

Ask the user to press Alt+`\` once while in game (any location). Then:

Run: `cd tools/tiles && python3 -m nmtiles.calib --out calibration.json && git diff --stat calibration.json`
Expected: `median_road_distance=... (gate 15.0 m)` and `wrote calibration.json`.

If the file changed (non-zero offset or different signs), rebuild and reinstall:
```bash
python3 -m nmtiles.build --skip-export && cd ../.. && tools/install.sh
```
Then restart the game.

- [ ] **Step 4: Visual review against the mockups**

Ask the user to press Ctrl+Shift+`\` (debug layer, 5,000 items), then compare against `docs/superpowers/specs/mockups/nightmap-overview.png` and `nightmap-street.png`:
- **Zoomed out:** hex clusters with counts and fans of the top 3 icons. Selecting a cluster shows "N LOCATIONS" and per-category rows in the card. Numpad 0 eases into the cluster.
- **Zoomed in:** individual hex chips tinted per category. The selected chip has a larger rim behind it, and the card shows the debug details with an action row.
- **Map tiles:**
  - roads line up with the vanilla map
  - V's arrow sits on the road V is standing on
  - drive north → the arrow points up
  - turn right → the arrow turns clockwise

  If the arrow is mirrored, set `PlayerRotationSign()` to `-1.0` in `Core/Theme.reds`, then run `tools/install.sh` and recheck.
- **Text:** the header shows the current district and the scale bar label changes with zoom.

Record which aspects differ from the mockups and fix them in the owning task's files.

- [ ] **Step 5: Performance**

Ask the user to stand still in a busy street, open the map and press Shift+`\`. The suite takes about 1–2 minutes; the panel hides during the "closed" scenarios. Then:

Run: `python3 tools/results.py`
Expected: a table and `PASS: items_50000: avg +x.xx ms (budget 3.0), p95 +y.yy ms (budget 6.0)`.

If it FAILs, profile from the per-scenario `script` column. The usual levers, in order:
1. lower `ChipBudget`/`ClusterBudget`
2. raise `ClusterSpacing`
3. skip mini fans when more than 40 clusters are on screen

Re-run until it passes, recording each attempt.

- [ ] **Step 6: Record and commit**

Append a `## Checkpoint 2` section to `notes/CHECKPOINTS.md` with:
- the self-test summary
- the calibration output (transform, median)
- the visual review notes and screenshots described in words
- the results table
- the PASS/FAIL line

```bash
git add notes/CHECKPOINTS.md tools/tiles/calibration.json r6/scripts/NightMap
git commit -m "Checkpoint 2: calibration, visual review vs mockups, perf suite results"
```

---

### Task 17: API documentation

**Files:**
- Create: `docs/api.md`
- Modify: `README.md`

- [ ] **Step 1: Write `docs/api.md`**

````markdown
# NightMap layer API

NightMap draws everything through layers. Any redscript mod can add its own; NightMap's own content
(vanilla pins, user markers, photos) uses the same API.

## Lifecycle
Layers live for one game session. Create them after the session is ready:

```swift
@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
    let r = wrappedMethod();
    let map = NightMap.Get();          // null if NightMap is not installed or not ready
    if IsDefined(map) { MyMod.FillLayer(map); }
    return r;
}
```

## Layers and items
```swift
let layer = map.CreateLayer(n"MyMod.Collectibles", "Collectibles", 50);   // id, display name, priority (higher draws on top)
layer.SetCategory(n"mymod.tarot", "TAROT", new HDRColor(1.0, 0.88, 0.4, 1.0));
map.SetCategoryIcon(n"mymod.tarot", r"mymod\\icons.inkatlas", n"tarot");    // default icon for the category
let id = layer.Add(NightMapItem.Create(new Vector4(x, y, z, 1.0), n"mymod.tarot", r"mymod\\icons.inkatlas", n"tarot")
    .WithLabel("Tarot: The Fool"));
layer.Move(id, newPos);
layer.Remove(id);
layer.Clear();
```

- Positions are world meters. Items outside the map bounds + 1 km are rejected; `Add` returns -1 and the layer logs once.
- Up to 7 categories per layer; further categories map to `other`. Up to 64 categories across all layers.
- Image items: `NightMapItem.Image(pos, category, "shot://photo.png|max256x256")` needs RedIMGRetriever. The icon appears once the image is loaded.

## Display controls
```swift
layer.SetVisible(false);
layer.SetOpacity(0.6);
layer.SetZoomRange(0.5, 4.0);     // only shown between 0.5 and 4 meters per unit (zoomed in)
layer.SetClustering(false);       // always individual chips; keep such layers under ~500 items
```

## Info card and activation
```swift
public class MyListener extends NightMapLayerListener {
    public func GetDetails(id: Int32) -> ref<NightMapDetails> {
        return NightMapDetails.Create("TAROT", "The Fool")
            .WithSubtitle("Watson · Kabuki")
            .AddRow("Status", "Not collected")
            .WithDescription("A graffiti tarot card.")
            .AddAction("NUM 0", "Set waypoint");
    }
    public func OnActivated(id: Int32) { /* numpad 0 on the selected item */ }
}
layer.SetListener(new MyListener());
```

Limits: 6 rows, 3 actions. Return `null` from `GetDetails` to get the default card (category, label, distance).

## Performance contract
Items cost nothing until visible. At most 300 chips and 80 clusters are drawn at once, whatever the item count.
The 50,000-item suite stays within +3 ms (see `tools/results.py`).
````

- [ ] **Step 2: Update `README.md`**

Append:
```markdown
## Using it
- `\` open/close · Numpad 8/4/6/2 (7/9/1/3) pan · Numpad +/- zoom · Numpad 5 follow V · Numpad 0 act. Rebind in Mod Settings → NightMap.
- Arrow keys are never used (they steer vehicles). Keep NumLock on.
- Debug (Mod Settings → NightMap → Debug tools): Ctrl+`\` self-test, Shift+`\` perf suite (`python3 tools/results.py`), Alt+`\` calibration dump (`cd tools/tiles && python3 -m nmtiles.calib`), Ctrl+Shift+`\` debug layer.

## For mod authors
See docs/api.md.
```

- [ ] **Step 3: Commit**

```bash
git add docs/api.md README.md
git commit -m "Docs: layer API guide and usage"
```

