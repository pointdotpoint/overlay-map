"""BC7 encoding with Microsoft texconv under Wine (CPU codec; the GPU path crashes under Wine)."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

TEXCONV = Path.home() / ".local/bin/texconv.exe"
DDS_DX10_HEADER = 148
BATCH = 48


def _win(p: Path) -> str:
    """texconv treats a leading '/' as a switch, so hand it Wine drive paths (Z: is the Unix root)."""
    return "Z:" + str(p.resolve()).replace("/", "\\")


def encode_bc7(pngs: list[Path], out_dir: Path) -> dict[Path, bytes]:
    out_dir.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "WINEDEBUG": "-all"}
    for i in range(0, len(pngs), BATCH):
        chunk = pngs[i:i + BATCH]
        subprocess.run(["wine", str(TEXCONV), "-nogpu", "-f", "BC7_UNORM", "-m", "1", "-y", "-o", _win(out_dir),
                        *map(_win, chunk)], check=True, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result: dict[Path, bytes] = {}
    for png in pngs:
        dds = (out_dir / png.with_suffix(".dds").name).read_bytes()
        if dds[:4] != b"DDS ":
            raise RuntimeError(f"texconv wrote no DDS for {png}")
        result[png] = dds[DDS_DX10_HEADER:]
    return result
