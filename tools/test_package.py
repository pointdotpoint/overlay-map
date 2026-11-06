"""The release zip: the layout players unzip into the game folder, and nothing that must not ship."""
import zipfile
from pathlib import Path
import importlib.util

import pytest

_spec = importlib.util.spec_from_file_location("package", Path(__file__).with_name("package.py"))
package = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(package)

ROOT = Path(__file__).resolve().parent.parent


def fake_tree(tmp: Path, *, debug_dll: bool = False, stale: bool = False) -> Path:
    (tmp / "archive/pc/mod").mkdir(parents=True)
    (tmp / "archive/pc/mod/OverlayMap.archive").write_bytes(b"RDAR" + b"\0" * 64)
    scripts = tmp / "r6/scripts/OverlayMap/Core"
    scripts.mkdir(parents=True)
    (scripts / "Settings.reds").write_text("module OverlayMap\n")
    (tmp / "r6/scripts/OverlayMap/Core/__pycache__").mkdir()
    (tmp / "r6/scripts/OverlayMap/Core/__pycache__/x.pyc").write_bytes(b"x")
    plugin = tmp / "dist-native/red4ext/plugins/OverlayMapNative"
    (plugin / "Scripts").mkdir(parents=True)
    (plugin / "OverlayMapNative.dll").write_bytes(b"MZ" + (b".debug_info" if debug_dll else b"") + b"\0" * 64)
    (plugin / "Scripts/OverlayMapNative.reds").write_text("module OverlayMapNative\n")
    if stale:
        old = tmp / "dist-native/red4ext/plugins/NightMapNative"
        old.mkdir(parents=True)
        (old / "NightMapNative.dll").write_bytes(b"MZ")
    (tmp / "VERSION").write_text("1.2.3\n")
    return tmp


def names(zpath: Path) -> list[str]:
    with zipfile.ZipFile(zpath) as z:
        return sorted(z.namelist())


def test_zip_has_the_game_folder_layout(tmp_path):
    root = fake_tree(tmp_path / "repo")
    out = package.build(root, tmp_path / "out")
    assert out.name == "OverlayMap-1.2.3.zip"
    assert names(out) == [
        "archive/pc/mod/OverlayMap.archive",
        "r6/scripts/OverlayMap/Core/Settings.reds",
        "red4ext/plugins/OverlayMapNative/OverlayMapNative.dll",
        "red4ext/plugins/OverlayMapNative/Scripts/OverlayMapNative.reds",
    ]


def test_old_nightmap_plugin_never_ships(tmp_path):
    root = fake_tree(tmp_path / "repo", stale=True)
    assert not any("NightMap" in n for n in names(package.build(root, tmp_path / "out")))


def test_refuses_a_plugin_with_debug_info(tmp_path):
    root = fake_tree(tmp_path / "repo", debug_dll=True)
    with pytest.raises(package.PackageError, match="debug info"):
        package.build(root, tmp_path / "out")


def test_refuses_without_the_archive(tmp_path):
    root = fake_tree(tmp_path / "repo")
    (root / "archive/pc/mod/OverlayMap.archive").unlink()
    with pytest.raises(package.PackageError, match="OverlayMap.archive"):
        package.build(root, tmp_path / "out")


def test_repo_has_a_version():
    v = (ROOT / "VERSION").read_text().strip()
    assert v.count(".") == 2 and all(p.isdigit() for p in v.split("."))
