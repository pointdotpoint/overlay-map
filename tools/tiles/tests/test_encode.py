import subprocess

from nmtiles import encode


def _fake_texconv(calls):
    def run(cmd, **kw):
        calls.append(cmd)
        out = [a for a in cmd if a.endswith(".png") or ".png" in a]
        outdir = cmd[cmd.index("-o") + 1]
        from pathlib import Path
        d = Path(outdir.removeprefix("Z:").replace("\\", "/"))
        for a in out:
            name = Path(a.removeprefix("Z:").replace("\\", "/")).with_suffix(".dds").name
            (d / name).write_bytes(b"DDS " + b"\0" * 144 + b"payload-" + name.encode())
        return subprocess.CompletedProcess(cmd, 0)
    return run


def test_encode_cache_skips_texconv_when_png_unchanged(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(encode.subprocess, "run", _fake_texconv(calls))
    a, b = tmp_path / "a.png", tmp_path / "b.png"
    a.write_bytes(b"one")
    b.write_bytes(b"two")
    out = tmp_path / "dds"
    first = encode.encode_bc7([a, b], out)
    assert len(calls) == 1 and (out / "a.sha1").exists()
    second = encode.encode_bc7([a, b], out)
    assert len(calls) == 1                                    # nothing re-encoded
    assert second == first
    b.write_bytes(b"changed")
    encode.encode_bc7([a, b], out)
    assert len(calls) == 2 and sum(".png" in x for x in calls[1]) == 1   # only b re-encoded


def test_no_sidecar_when_texconv_wrote_no_dds(tmp_path, monkeypatch):
    monkeypatch.setattr(encode.subprocess, "run", lambda cmd, **kw: subprocess.CompletedProcess(cmd, 0))
    a = tmp_path / "a.png"
    a.write_bytes(b"one")
    import pytest
    with pytest.raises(FileNotFoundError):
        encode.encode_bc7([a], tmp_path / "dds")
    assert not (tmp_path / "dds" / "a.sha1").exists()


def test_texconv_gets_premultiply_and_flip_flags(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(encode.subprocess, "run", _fake_texconv(calls))
    a = tmp_path / "a.png"
    a.write_bytes(b"one")
    encode.encode_bc7([a], tmp_path / "dds")
    assert "-pmalpha" in calls[0] and "-vflip" in calls[0]


def test_changed_options_invalidate_cache(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(encode.subprocess, "run", _fake_texconv(calls))
    a = tmp_path / "a.png"
    a.write_bytes(b"one")
    out = tmp_path / "dds"
    encode.encode_bc7([a], out)
    encode.encode_bc7([a], out)
    assert len(calls) == 1
    monkeypatch.setattr(encode, "TEXCONV_OPTS", ["-pmalpha"])
    encode.encode_bc7([a], out)
    assert len(calls) == 2
