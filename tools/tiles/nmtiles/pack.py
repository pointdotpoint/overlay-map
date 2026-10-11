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
