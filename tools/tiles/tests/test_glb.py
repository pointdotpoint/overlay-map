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
