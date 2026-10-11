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
