import pytest

from nmtiles.build import main, require_boxes
from nmtiles.buildings import Boxes


def test_require_boxes_rejects_empty():
    with pytest.raises(SystemExit, match="no building boxes"):
        require_boxes(Boxes.concat([]))


def test_skip_export_without_building_data_explains(tmp_path):
    (tmp_path / "meshes").mkdir()
    with pytest.raises(SystemExit, match="without --skip-export"):
        main(["--game", str(tmp_path), "--out", str(tmp_path), "--skip-export"])
