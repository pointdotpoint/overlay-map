"""Turn WolvenKit JSON into CR2W resources and pack them into an .archive."""
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path


def write_resource(workspace: Path, depot_path: str, js: dict) -> Path:
    """Write the WolvenKit JSON for a resource; returns the expected CR2W target path.

    Call deserialize_all() once after writing every resource to convert them in one pass.
    """
    target = workspace / Path(*depot_path.split("\\"))
    target.parent.mkdir(parents=True, exist_ok=True)
    target.with_name(target.name + ".json").write_text(json.dumps(js))
    return target


def deserialize_all(workspace: Path, wolvenkit: str = "WolvenKit.CLI") -> list[Path]:
    """Convert every *.json under workspace to CR2W in one WolvenKit run, then delete the JSON."""
    jsons = sorted(workspace.rglob("*.json"))
    targets = [j.with_name(j.name[: -len(".json")]) for j in jsons]
    subprocess.run([wolvenkit, "convert", "d", str(workspace)], check=True, cwd=workspace.parent,
                   stdout=subprocess.DEVNULL)
    for j in jsons:
        j.unlink(missing_ok=True)
    missing = [t for t in targets if not t.is_file()]
    if missing:
        raise RuntimeError(f"WolvenKit did not produce {len(missing)} resources: {[str(m) for m in missing[:10]]}")
    return targets


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
