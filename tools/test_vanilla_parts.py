"""Offline check (spec 11): every map-marker variant the game groups must draw an icon that exists in the mappin atlas.

variant_table.txt / atlas_parts.tsv come from the in-game spike; the fallbacks are parsed out of NMVanillaStyle.PartOf
in Style.reds, so adding a remap there is the only thing that keeps this test green for a new missing part.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPIKE = ROOT / "docs/superpowers/specs/2026-10-13-vanilla-markers-spike"
STYLE = ROOT / "r6/scripts/OverlayMap/Vanilla/Style.reds"


def atlas_parts() -> set[str]:
    rows = (SPIKE / "atlas_parts.tsv").read_text().splitlines()[1:]
    return {r.split("\t")[0] for r in rows if r.strip()}


def grouped_variants(only_grouped: bool = True) -> list[tuple[str, str]]:
    """(variant, part); by default only variants with a real group (group != none/none)."""
    out = []
    for line in (SPIKE / "variant_table.txt").read_text().splitlines():
        if not line.startswith("VARIANT|"):
            continue
        f = line.split("|")
        fields = dict(x.split("=", 1) for x in f[3:] if "=" in x)
        if not only_grouped or fields.get("group") != "none/none":
            out.append((f[2], fields["part"]))
    return out


def remaps() -> dict[str, str]:
    """{game part: fallback part} from PartOf's `if Equals(p, n"a") { return n"b"; }` lines."""
    src = STYLE.read_text()
    body = src[src.index("func PartOf"):]
    body = body[:body.index("\n    }\n")]
    return dict(re.findall(r'Equals\(p, n"([^"]+)"\) \{ return n"([^"]+)"; \}', body))


def test_remap_list_is_parsed():
    r = remaps()
    assert r.get("PhoneCall") == "quest" and "relic_dataterm" in r and "failed_crossing" in r


def test_fallback_targets_exist_in_the_atlas():
    parts = atlas_parts()
    for src, dst in remaps().items():
        assert dst in parts, f"PartOf maps {src} -> {dst}, which is not an atlas part"


def test_every_grouped_variant_draws_an_existing_part():
    parts, fallbacks = atlas_parts(), remaps()
    assert len(grouped_variants()) > 30
    missing = [(v, p) for v, p in grouped_variants()
               if p not in parts and p not in fallbacks and p not in ("invalid", "", "None")]
    assert not missing, f"no atlas part and no PartOf fallback: {missing}"


def test_every_variant_even_ungrouped_draws_an_existing_part():
    # Ungrouped variants can still appear (Vanilla.Other shows any visible map mappin), e.g. PhoneCallVariant.
    parts, fallbacks = atlas_parts(), remaps()
    assert len(grouped_variants(False)) > 140
    missing = [(v, p) for v, p in grouped_variants(False)
               if p not in parts and p not in fallbacks and p not in ("invalid", "", "None")]
    assert not missing, f"no atlas part and no PartOf fallback: {missing}"


def test_invalid_part_variants_fall_back_to_quest():
    # PartOf maps invalid/""/None to `quest`, which must exist.
    assert "quest" in atlas_parts()
    src = STYLE.read_text()
    assert 'n"invalid"' in src and 'return n"quest"' in src
