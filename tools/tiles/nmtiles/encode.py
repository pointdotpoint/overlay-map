"""BC7 encoding with Microsoft texconv under Wine (CPU codec; the GPU path crashes under Wine)."""
from __future__ import annotations

import hashlib
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

TEXCONV = Path.home() / ".local/bin/texconv.exe"
DDS_DX10_HEADER = 148
BATCH = 48
WORKERS = 6     # concurrent wine/texconv processes
# Ink blends premultiplied alpha and samples textures with V flipped relative to PNG row order.
TEXCONV_OPTS = ["-pmalpha", "-vflip"]


def options_string() -> str:
    return "bc7|" + " ".join(TEXCONV_OPTS)


def _win(p: Path) -> str:
    """texconv treats a leading '/' as a switch, so hand it Wine drive paths (Z: is the Unix root)."""
    return "Z:" + str(p.resolve()).replace("/", "\\")


def _sha1(p: Path) -> str:
    """Cache key: hash of the PNG bytes plus the encode options, so option changes re-encode."""
    return hashlib.sha1(p.read_bytes() + b"\0" + options_string().encode()).hexdigest()


def _cached(png: Path, out_dir: Path) -> bool:
    """A DDS is reusable when its sidecar <name>.sha1 matches the PNG's current SHA-1."""
    dds, side = out_dir / png.with_suffix(".dds").name, out_dir / png.with_suffix(".sha1").name
    return dds.exists() and side.exists() and side.read_text().strip() == _sha1(png)


def encode_bc7(pngs: list[Path], out_dir: Path, workers: int = WORKERS) -> dict[Path, bytes]:
    out_dir.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "WINEDEBUG": "-all"}
    todo = [p for p in pngs if not _cached(p, out_dir)]
    def run(chunk: list[Path]) -> None:
        subprocess.run(["wine", str(TEXCONV), "-nogpu", "-f", "BC7_UNORM", "-m", "1", "-y", *TEXCONV_OPTS, "-o", _win(out_dir),
                        *map(_win, chunk)], check=True, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for png in chunk:
            dds = out_dir / png.with_suffix(".dds").name
            if dds.exists() and dds.stat().st_mtime_ns >= png.stat().st_mtime_ns:   # texconv really wrote it
                (out_dir / png.with_suffix(".sha1").name).write_text(_sha1(png) + "\n")

    chunks = [todo[i:i + BATCH] for i in range(0, len(todo), BATCH)]
    with ThreadPoolExecutor(workers) as ex:
        for n, _ in enumerate(ex.map(run, chunks), 1):
            if n % 10 == 0:
                print(f"  encoded {min(n * BATCH, len(todo))}/{len(todo)}", flush=True)
    result: dict[Path, bytes] = {}
    for png in pngs:
        dds = (out_dir / png.with_suffix(".dds").name).read_bytes()
        if dds[:4] != b"DDS ":
            raise RuntimeError(f"texconv wrote no DDS for {png}")
        result[png] = dds[DDS_DX10_HEADER:]
    return result
