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
