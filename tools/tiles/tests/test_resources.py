import base64
import json
import os
from pathlib import Path

import pytest

from nmtiles.resources import bc7_layout, make_inkatlas_json, make_xbm_json

TPL = Path(__file__).resolve().parents[1] / "templates"


def _tpl(name):
    return json.loads((TPL / name).read_text())


def test_bc7_layout_matches_known_template_and_512():
    assert bc7_layout(1028, 1028) == (4112, 1056784)   # values in the hologram template
    assert bc7_layout(512, 512) == (2048, 262144)
    assert bc7_layout(1024, 1024) == (4096, 1048576)


def test_make_xbm_json_sets_size_mips_and_payload():
    payload = bytes(range(256)) * 1024                   # 262144 bytes
    j = make_xbm_json(_tpl("tile.xbm.json"), 512, 512, payload)
    r = j["Data"]["RootChunk"]
    hd = r["renderTextureResource"]["renderResourceBlobPC"]["Data"]["header"]
    assert (r["width"], r["height"]) == (512, 512)
    assert (hd["sizeInfo"]["width"], hd["sizeInfo"]["height"]) == (512, 512)
    assert len(hd["mipMapInfo"]) == 1
    assert hd["mipMapInfo"][0]["layout"] == {**hd["mipMapInfo"][0]["layout"], "rowPitch": 2048, "slicePitch": 262144}
    assert hd["textureInfo"]["mipCount"] == 1 and hd["textureInfo"]["textureDataSize"] == 262144
    assert r["setup"]["hasMipchain"] == 0 and r["setup"]["compression"] == "TCM_QualityColor"
    blob = r["renderTextureResource"]["renderResourceBlobPC"]["Data"]["textureData"]["Bytes"]
    assert base64.b64decode(blob) == payload
    assert j["Data"]["BuildVersion"] == 262144


def test_make_xbm_json_rejects_wrong_payload_size():
    with pytest.raises(ValueError):
        make_xbm_json(_tpl("tile.xbm.json"), 512, 512, b"\0" * 100)


def test_make_inkatlas_json_points_all_slots_at_texture_with_uv_parts():
    parts = {"full": (0, 0, 512, 512), "chip": (0, 0, 112, 112)}
    j = make_inkatlas_json(_tpl("atlas.inkatlas.json"), r"overlaymap\tiles\L0\t_1_2.xbm", parts, 512, 512)
    slots = j["Data"]["RootChunk"]["slots"]["Elements"]
    assert len(slots) == 3
    for s in slots:
        assert s["texture"]["DepotPath"]["$value"] == r"overlaymap\tiles\L0\t_1_2.xbm"
        names = [p["partName"]["$value"] for p in s["parts"]]
        assert names == ["full", "chip"]
        chip = s["parts"][1]["clippingRectInUVCoords"]
        assert (chip["Left"], chip["Top"], chip["Right"], chip["Bottom"]) == (0.0, 0.0, 112 / 512, 112 / 512)


@pytest.mark.slow
@pytest.mark.skipif(os.environ.get("OVERLAYMAP_SLOW") != "1", reason="needs wine/texconv/WolvenKit")
def test_encode_write_pack_roundtrip(tmp_path):
    from PIL import Image

    from nmtiles.encode import encode_bc7
    from nmtiles.pack import deserialize_all, pack_archive, write_resource
    png = tmp_path / "t.png"
    # noise, not a flat colour: the CR2W stores the payload Kraken-compressed, so a flat tile shrinks to ~1.7 KB
    Image.frombytes("RGBA", (512, 512), os.urandom(512 * 512 * 4)).save(png)
    payload = encode_bc7([png], tmp_path / "dds")[png]
    assert len(payload) == 262144
    ws = tmp_path / "ws"
    write_resource(ws, r"overlaymap\test\t.xbm", make_xbm_json(_tpl("tile.xbm.json"), 512, 512, payload))
    write_resource(ws, r"overlaymap\test\t.inkatlas",
                   make_inkatlas_json(_tpl("atlas.inkatlas.json"), r"overlaymap\test\t.xbm", {"full": (0, 0, 512, 512)}, 512, 512))
    deserialize_all(ws)
    assert (ws / "overlaymap/test/t.xbm").stat().st_size > 262144
    arc = pack_archive(ws, tmp_path / "out" / "Test.archive")
    assert arc.stat().st_size > 262144


def test_deserialize_all_runs_once_and_checks_targets(tmp_path, monkeypatch):
    import subprocess

    import pytest

    from nmtiles import pack

    ws = tmp_path / "ws"
    t1 = pack.write_resource(ws, r"a\b\x.xbm", {"k": 1})
    t2 = pack.write_resource(ws, r"a\y.inkatlas", {"k": 2})
    assert t1 == ws / "a" / "b" / "x.xbm" and not t1.exists()
    calls = []

    def fake_run(cmd, **kw):
        calls.append(cmd)
        for j in ws.rglob("*.json"):
            j.with_name(j.name[:-5]).write_bytes(b"cr2w")
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(pack.subprocess, "run", fake_run)
    assert set(pack.deserialize_all(ws)) == {t1, t2}
    assert len(calls) == 1 and calls[0][:3] == ["WolvenKit.CLI", "convert", "d"]
    assert t1.is_file() and not list(ws.rglob("*.json"))

    pack.write_resource(ws, r"a\z.xbm", {})
    monkeypatch.setattr(pack.subprocess, "run", lambda cmd, **kw: subprocess.CompletedProcess(cmd, 0))
    with pytest.raises(RuntimeError, match="did not produce"):
        pack.deserialize_all(ws)
