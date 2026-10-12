"""BC7 encoding with Microsoft texconv under Wine (CPU codec; the GPU path crashes under Wine)."""
from __future__ import annotations

import hashlib
import os
import subprocess
from pathlib import Path

TEXCONV = Path.home() / ".local/bin/texconv.exe"
DDS_DX10_HEADER = 148
BATCH = 48


def _win(p: Path) -> str:
    """texconv treats a leading '/' as a switch, so hand it Wine drive paths (Z: is the Unix root)."""
    return "Z:" + str(p.resolve()).replace("/", "\\")


def _sha1(p: Path) -> str:
    return hashlib.sha1(p.read_bytes()).hexdigest()


def _cached(png: Path, out_dir: Path) -> bool:
    """A DDS is reusable when its sidecar <name>.sha1 matches the PNG's current SHA-1."""
    dds, side = out_dir / png.with_suffix(".dds").name, out_dir / png.with_suffix(".sha1").name
    return dds.exists() and side.exists() and side.read_text().strip() == _sha1(png)


def encode_bc7(pngs: list[Path], out_dir: Path) -> dict[Path, bytes]:
    out_dir.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "WINEDEBUG": "-all"}
    todo = [p for p in pngs if not _cached(p, out_dir)]
    for i in range(0, len(todo), BATCH):
        chunk = todo[i:i + BATCH]
        subprocess.run(["wine", str(TEXCONV), "-nogpu", "-f", "BC7_UNORM", "-m", "1", "-y", "-o", _win(out_dir),
                        *map(_win, chunk)], check=True, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for png in chunk:
            dds = out_dir / png.with_suffix(".dds").name
            if dds.exists() and dds.stat().st_mtime_ns >= png.stat().st_mtime_ns:   # texconv really wrote it
                (out_dir / png.with_suffix(".sha1").name).write_text(_sha1(png) + "\n")
    result: dict[Path, bytes] = {}
    for png in pngs:
        dds = (out_dir / png.with_suffix(".dds").name).read_bytes()
        if dds[:4] != b"DDS ":
            raise RuntimeError(f"texconv wrote no DDS for {png}")
        result[png] = dds[DDS_DX10_HEADER:]
    return result
