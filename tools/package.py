#!/usr/bin/env python3
"""Build the release zip players unzip into their Cyberpunk 2077 folder.

    python3 tools/package.py            # -> dist/OverlayMap-<VERSION>.zip

Layout (mirrors the game folder):
    archive/pc/mod/OverlayMap.archive
    r6/scripts/OverlayMap/...
    red4ext/plugins/OverlayMapNative/{OverlayMapNative.dll, Scripts/*.reds}

Build the inputs first: tile archive (tools/tiles build) and the waypoint plugin (tools/native/build.sh). The zip is
refused when the archive is missing or the plugin still carries debug info.
"""
import sys
import zipfile
from pathlib import Path

ARCHIVE = "archive/pc/mod/OverlayMap.archive"
SCRIPTS = "r6/scripts/OverlayMap"
PLUGIN_SRC = "dist-native/red4ext/plugins/OverlayMapNative"
PLUGIN_DST = "red4ext/plugins/OverlayMapNative"
SKIP_PARTS = {"__pycache__"}
SKIP_SUFFIXES = {".pyc", ".orig", ".rej", ".swp"}


class PackageError(Exception):
    pass


def _files(base: Path):
    for p in sorted(base.rglob("*")):
        if p.is_file() and not (SKIP_PARTS & set(p.relative_to(base).parts)) and p.suffix not in SKIP_SUFFIXES:
            yield p


def build(root: Path, out_dir: Path) -> Path:
    root = Path(root)
    version = (root / "VERSION").read_text().strip()
    archive = root / ARCHIVE
    if not archive.is_file():
        raise PackageError(f"{ARCHIVE} not built: run the tile build first")
    scripts = root / SCRIPTS
    if not scripts.is_dir():
        raise PackageError(f"{SCRIPTS} missing")
    plugin = root / PLUGIN_SRC
    dll = plugin / "OverlayMapNative.dll"
    if not dll.is_file():
        raise PackageError("OverlayMapNative.dll not built: run tools/native/build.sh")
    if b".debug_info" in dll.read_bytes():
        raise PackageError("OverlayMapNative.dll still has debug info: rebuild with tools/native/build.sh")

    entries: list[tuple[Path, str]] = [(archive, ARCHIVE)]
    entries += [(p, f"{SCRIPTS}/{p.relative_to(scripts).as_posix()}") for p in _files(scripts)]
    entries += [(p, f"{PLUGIN_DST}/{p.relative_to(plugin).as_posix()}") for p in _files(plugin)]

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"OverlayMap-{version}.zip"
    tmp = out.with_suffix(".zip.part")
    with zipfile.ZipFile(tmp, "w") as z:
        for src, name in entries:
            # The archive is already compressed: store it. Text compresses well.
            kind = zipfile.ZIP_STORED if name == ARCHIVE else zipfile.ZIP_DEFLATED
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = kind
            info.external_attr = 0o644 << 16
            z.writestr(info, src.read_bytes())
    tmp.replace(out)
    return out


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    try:
        out = build(root, root / "dist")
    except PackageError as e:
        print(f"package: {e}", file=sys.stderr)
        return 1
    with zipfile.ZipFile(out) as z:
        n = len(z.namelist())
    print(f"built {out} ({n} files, {out.stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
