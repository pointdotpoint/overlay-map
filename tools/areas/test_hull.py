"""hull.py: convex hull of prefab positions."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hull import convex_hull, fnv1a64, node_positions  # noqa: E402


def test_hull_square_drops_inner_and_collinear():
    pts = [(0, 0), (2, 0), (1, 0), (2, 2), (0, 2), (1, 1)]
    assert convex_hull(pts) == [(0, 0), (2, 0), (2, 2), (0, 2)]


def test_hull_degenerate():
    assert convex_hull([(1, 1)]) == [(1, 1)]


def test_node_positions_match_debug_name_or_node_ref():
    ref = "$/03_night_city/se1/loc_q101_landfill_prefab/landfill_pile_prefab/None_001"
    pos = {"$type": "Vector4", "X": 1.0, "Y": 2.0, "Z": 3.0, "W": 0}
    doc = {"Data": {"RootChunk": {
        "nodes": [{"Data": {"$type": "worldCookedStaticMeshNode", "debugName": {"$value": "{x}"}}},
                  {"Data": {"$type": "worldStaticMeshNode", "debugName": {"$value": "{landfill_pile_b}"}}},
                  {"Data": {"$type": "worldStaticMeshNode", "debugName": {"$value": "{other}"}}}],
        "nodeRefs": [{"$type": "NodeRef", "$value": ref}],
        "nodeData": {"Data": [
            {"nodeIdx": "0", "globalNodeId": {"hash": str(fnv1a64(ref))}, "transform": {"position": pos}},
            {"nodeIdx": "1", "globalNodeId": {"hash": "5"}, "transform": {"position": dict(pos, X=7.0)}},
            {"nodeIdx": "2", "globalNodeId": {"hash": "6"}, "transform": {"position": dict(pos, X=9.0)}}]}}}}
    assert node_positions(doc, "landfill_pile") == [(1.0, 2.0), (7.0, 2.0)]
