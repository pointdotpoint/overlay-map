#!/usr/bin/env python3
"""Shop names for the sidebar: which vendor record names each shop pin, from the game's own data.

  gen.py --journal base.json [--journal ep1.json] --flats vendors.json [--loc loc.json]
         [--out r6/scripts/OverlayMap/Generated/VendorData.reds]

A shop pin's journal id usually names its vendor record (Vendors.<id>.localizedName), and the runtime reads that
directly. This script covers the rest:
  * aliases: the pin and its record spell the shop type differently ("wbr_jpn_food_04" vs "wbr_jpn_foodshop_04").
    Matched on district prefix + normalized type + number, kept only when the record has a real name.
  * generic keys: LocKeys whose English text two or more vendor records share ("Food Vendor", "Gun Vendor"). A pin
    whose record holds one of these keeps the type label instead.
  * keepers: the shopkeeper's own name (Character.<id>.displayName, "Darius Clarke") for a pin whose vendor record
    has no shop name. Matched like the aliases; names three or more characters share ("Bartender", "Robot") and
    the vendors' generic wording are skipped.

Inputs (see tools/vendors/README.md for the extraction steps):
  --journal  WolvenKit JSON of base/journal/cooked_journal.journal (and ep1's)
  --flats    {"Vendors.<id>.localizedName": "LocKey#N" | text | null} for every Vendors flat (tdbdump on tweakdb_ep1.bin)
  --loc      {"N": "English text"} from the en-us onscreens, to tell generic wording apart
  --chars    {"Character.<id>.displayName": "LocKey#N" | null} for every Character record (tdbdump)
"""
from __future__ import annotations

import argparse
import collections
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "r6/scripts/OverlayMap/Generated/VendorData.reds"

TYPES = [
    ("food", "food|foodshop|foodstore|bar"),
    ("cloth", "cloth|clothing|clothingshop|clothingstore"),
    ("guns", "guns|gunsmith"),
    ("medic", "medic|medicstore|meds"),
    ("rip", "ripperdoc|ripdoc|rippdoc"),
    ("junk", "junk|junkshop"),
    ("net", "netrun|netrunner"),
    ("melee", "melee|ws_melee"),
]
VARIANT_TYPE = {
    "ServicePointFoodVariant": "food", "ServicePointBarVariant": "food", "ServicePointClothesVariant": "cloth",
    "ServicePointGunsVariant": "guns", "ServicePointMedsVariant": "medic", "ServicePointRipperdocVariant": "rip",
    "ServicePointJunkVariant": "junk", "ServicePointNetTrainerVariant": "net", "ServicePointMeleeTrainerVariant": "melee",
}
ID = re.compile(r"^([a-z0-9]+_[a-z0-9]+(?:_se\d)?)_(.*?)_?0*(\d+)$")
JUNK_NAMES = {"DELETE", "!DELETE", "!NOT NEEDED"}


def shop_key(ident: str):
    """(district prefix, type, number), or None when the id has no such shape."""
    m = ID.match(ident)
    if not m:
        return None
    pre, body, num = m.groups()
    for name, pat in TYPES:
        if re.search(rf"(^|_)(?:{pat})(_|$)", body):
            return pre, name, int(num)
    return pre, body, int(num)


def service_pins(doc: dict) -> list[tuple[str, str]]:
    """(journal id, mappin variant) of every point of interest under points_of_interest/service_points."""
    out = []

    def walk(o, path):
        if isinstance(o, dict):
            if o.get("$type") == "gameJournalPointOfInterestMappin" and "service_points" in path:
                v = o["mappinData"]["typedVariant"]["Data"].get("variant", "")
                if "ServicePoint" in v:
                    out.append((o["id"], v))
            p = path + [str(o["id"])] if "id" in o else path
            for v in o.values():
                walk(v, p)
        elif isinstance(o, list):
            for v in o:
                walk(v, path)

    walk(doc, [])
    return out


def build(pins, flats, loc):
    names = {k.split(".")[1]: v for k, v in flats.items() if v}

    def text(v):
        return loc.get(v[7:], v) if v.startswith("LocKey#") else v

    # Generic = the same wording on two or more records, whichever key carries it (the game repeats
    # "Food Vendor" under many keys).
    uses = collections.Counter(text(v) for v in names.values())
    generic = {v for v in names.values() if v.startswith("LocKey#") and uses[text(v)] >= 2}

    def real(v):
        return v and v not in generic and v not in JUNK_NAMES

    by_key = collections.defaultdict(list)
    for rec in sorted(names):
        k = shop_key(rec)
        if k:
            by_key[k].append(rec)
    aliases = {}
    for pin, variant in pins:
        key = shop_key(pin)
        want = VARIANT_TYPE.get(variant)
        # The pin's own record counts when its id names the pin's type (one id can carry two services: Fingers
        # M.D.'s ripperdoc pin has the id of Chang-Hoon Nam's netrunner record).
        own_ok = real(names.get(pin)) and (not key or not want or key[1] == want)
        if own_ok:
            continue
        known = key is not None and key[1] in {t for t, _ in TYPES}
        keys = ([(key[0], want, key[2])] if known and want else []) + ([key] if key else [])
        found = next((rec for k in keys for rec in by_key.get(k, []) if rec != pin and real(names.get(rec))), None)
        if found:
            aliases[pin] = found
        elif real(names.get(pin)):
            aliases[pin] = "-"   # its own record names a different service: keep the type label
    return aliases, generic, names


KEEPER_SHARED = 3   # a name on this many characters is a role ("Bartender"), not a person


def keepers(pins, aliases, generic, names, chars, loc):
    """{pin: "LocKey#N"} naming the shopkeeper of every pin that has no shop name of its own."""
    def text(v):
        return loc.get(v[7:]) if v and v.startswith("LocKey#") else None

    chars = {k.split(".")[1]: v for k, v in chars.items() if v and v.startswith("LocKey#")}
    uses = collections.Counter(text(v) for v in chars.values())
    vendor_generic = {text(g) for g in generic}
    by_key = collections.defaultdict(list)
    for rec in sorted(chars):
        k = shop_key(rec)
        if k:
            by_key[k].append(rec)

    def person(rec):
        t = text(chars.get(rec))
        return bool(t) and uses[t] < KEEPER_SHARED and t not in vendor_generic and t not in JUNK_NAMES

    out = {}
    for pin, variant in pins:
        alias = aliases.get(pin)
        own = names.get(alias if alias not in (None, "-") else pin)
        if alias != "-" and own and own not in generic and own not in JUNK_NAMES:
            continue   # the shop has its own name
        key = shop_key(pin)
        want = VARIANT_TYPE.get(variant)
        known = key is not None and key[1] in {t for t, _ in TYPES}
        cands = [rec for k in ([(key[0], want, key[2])] if known and want else []) for rec in by_key.get(k, [])]
        # The pin's own id only when it names the pin's type (see Fingers M.D. in build()).
        if not key or not want or key[1] == want or not known:
            cands.append(pin)
        if alias not in (None, "-"):
            cands.append(alias)
        found = next((c for c in cands if c in chars and person(c)), None)
        if found:
            out[pin] = chars[found]
    return out


def reds(aliases: dict, generic: set, keeper: dict | None = None) -> str:
    lines = [
        "module OverlayMap",
        "",
        "// Generated by tools/vendors/gen.py from the game's journal and Vendors records. Do not edit.",
        "public abstract class NMVendorData {",
        "    // The vendor record that names a shop pin whose journal id is spelled differently; \"-\" for a pin whose own",
        "    // record names another service (keep the type label); \"\" when the pin's own id is the record.",
        "    public static func Alias(pin: String) -> String {",
        "        switch pin {",
    ]
    for pin in sorted(aliases):
        lines.append(f'            case "{pin}": return "{aliases[pin]}";')
    lines += [
        "            default: return \"\";",
        "        }",
        "    }",
        "",
        "    // A name the game shares between many vendors (\"Food Vendor\"): not a shop's own name.",
        "    public static func IsGeneric(raw: String) -> Bool {",
        "        switch raw {",
    ]
    for key in sorted(generic, key=lambda s: int(s[7:])):
        lines.append(f'            case "{key}":')
    lines += [
        "                return true;",
        "            default: return false;",
        "        }",
        "    }",
        "",
        "    // The shopkeeper's own name (a LocKey) for a shop pin without a shop name; \"\" when the game has none.",
        "    public static func Keeper(pin: String) -> String {",
        "        switch pin {",
    ]
    for pin in sorted(keeper or {}):
        lines.append(f'            case "{pin}": return "{keeper[pin]}";')
    lines += [
        "            default: return \"\";",
        "        }",
        "    }",
        "}",
        "",
    ]
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--journal", type=Path, action="append", required=True)
    ap.add_argument("--flats", type=Path, required=True)
    ap.add_argument("--loc", type=Path, required=True)
    ap.add_argument("--chars", type=Path, required=True)
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args(argv)
    pins = [p for j in args.journal for p in service_pins(json.loads(j.read_text()))]
    flats = json.loads(args.flats.read_text())
    loc = json.loads(args.loc.read_text())
    aliases, generic, names = build(pins, flats, loc)
    keeper = keepers(pins, aliases, generic, names, json.loads(args.chars.read_text()), loc)
    args.out.write_text(reds(aliases, generic, keeper))

    def en(v):
        return loc.get(v[7:], v) if v and v.startswith("LocKey#") else v

    direct = sum(1 for p, _ in pins if names.get(p) and names[p] not in generic and names[p] not in JUNK_NAMES)
    print(f"shop pins {len(pins)}: direct {direct}, alias {len(aliases)}, rest {len(pins) - direct - len(aliases)}")
    for pin in sorted(aliases):
        print(f"  alias {pin} -> {aliases[pin]} ({en(names.get(aliases[pin]))})")
    print(f"keepers {len(keeper)}:", ", ".join(f"{p}={en(keeper[p])}" for p in sorted(keeper)))
    print("generic:", ", ".join(sorted({str(en(g)) for g in generic})))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
