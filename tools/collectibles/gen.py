#!/usr/bin/env python3
"""Join the world scan (scan.py) with the item dump (soak `lootdump`) into OverlayMap's collectible pins.

  gen.py --scan ~/.cache/overlaymap-sectors/scan --dump .soak/results/<run>/dump-1/channel/lootdump.txt
writes r6/scripts/OverlayMap/Generated/CollectData.reds (spec 2026-10-31-overlaymap-collectibles-design.md).
"""
from __future__ import annotations

import argparse
import collections
import functools
import json
import re
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "r6/scripts/OverlayMap/Generated/CollectData.reds"
DUPLICATE_M = 2.0   # the same item this close to another copy is one pin
TABLE_REACH = 3   # a loot table placed more often than this is a random drop, not a fixed collectible
CATEGORIES = "STWCLK"   # shard, tarot, iconic weapon, cyberware, clothing, skill shard
QUESTS = Path(__file__).with_name("journal_quests.json")   # from quests.py
QUEST_ITEM = re.compile(r"Items\.((?:q|sq|mq)\d+)", re.I)
QUEST_TYPES = {"MainQuest": "M", "SideQuest": "S", "MinorQuest": "m", "StreetStory": "G"}   # anything else: Q


@dataclass
class Item:
    id: str
    kind: str
    type: str
    quality: str
    tags: frozenset
    extra: str
    name: str


@dataclass
class Dump:
    items: dict
    tables: dict
    tarot: set


@dataclass(frozen=True)
class Entry:
    cat: str
    x: float
    y: float
    z: float
    ref: str


def load_dump(path: Path) -> Dump:
    items, tables, tarot = {}, {}, set()
    for line in path.read_text().splitlines():
        f = line.split("|")
        if f[0] == "i" and len(f) >= 8:
            items[f[1]] = Item(f[1], f[2], f[3], f[4], frozenset(x for x in f[5].split(",") if x), f[6], f[7])
        elif f[0] == "t" and len(f) >= 4:
            tables[f[1]] = ([x for x in f[2].split(",") if x], [x for x in f[3].split(",") if x])
        elif f[0] == "tarot" and len(f) >= 2:
            tarot.add(f[1].split("/")[-1])
    return Dump(items, tables, tarot)


def load_scan(folder: Path) -> list[dict]:
    return [json.loads(line) for p in sorted(folder.glob("b*.jsonl")) for line in p.read_text().splitlines() if line]


def category(it: Item) -> str | None:
    if it.kind == "RecipeItem_Record":
        return None
    if "Skillbook" in it.id:
        return "K"
    if it.type == "Gen_Readable" and it.extra.startswith("J:"):
        return "S"
    if "IconicWeapon" in it.tags:
        return "W"
    legendary = it.quality.startswith("Legendary")
    if legendary and (it.type == "Cyberware" or it.type.startswith("Cyb_")):
        return "C"
    if legendary and it.kind == "Clothing_Record":
        return "L"
    return None


def tarot_ref(node_name: str, ids: set) -> str | None:
    """The tarot journal ids behind a world node name (minor cards are named differently in the world), or None."""
    n = node_name.strip("{}")
    m = re.fullmatch(r"mq033_minor_(page|knight|queen|king)_of_(\w+)", n)
    if m:
        n = f"mq033_{m.group(1)}_of_the_{m.group(2)}"
    found = sorted(i for i in ids if i == n or re.fullmatch(re.escape(n) + r"\d", i))
    return "+".join(found) if found else None


def quest_note(ref: str, quests: dict) -> str | None:
    """The quest an item belongs to, from its id, as "<type><pl>:<title keys>"; None for a non-quest item.

    type: M main, S side, m minor, G gig, Q other or mixed; pl: 1 when every candidate is Phantom Liberty. The keys
    are journal title LocKeys joined by '+': the longest quest id the item id starts with, else every quest under
    the item's code (q105, sq024...) when the id names none of them. No keys: a quest owns it, but which is unknown.
    """
    m = QUEST_ITEM.match(ref)
    if not m:
        return None
    s, code = ref[len("Items."):].lower(), m.group(1).lower()
    named = [q for q in quests if s == q or s.startswith(q + "_")]
    found = [max(named, key=len)] if named else sorted(q for q in quests if q.split("_")[0] == code)
    types = {QUEST_TYPES.get(quests[q][1], "Q") for q in found}
    kind = types.pop() if len(types) == 1 else "Q"
    pl = int(bool(found) and all(quests[q][2] for q in found))
    return f"{kind}{pl}:" + "+".join(str(k) for k in sorted({quests[q][0] for q in found}))


def collect(rows: list[dict], d: Dump) -> list[Entry]:
    @functools.lru_cache(None)
    def expand(t: str, depth: int = 0) -> frozenset:
        if t not in d.tables or depth > 8:
            return frozenset()
        its, inc = d.tables[t]
        s = set(its)
        for c in inc:
            s |= expand(c, depth + 1)
        return frozenset(s)

    placed = collections.Counter(i for r in rows for i in set(r["ids"]) if i.startswith("LootTables."))
    placed_at: dict = collections.defaultdict(list)
    out: list[Entry] = []

    def add(cat: str, p: list, ref: str) -> None:
        near = placed_at[(cat, ref)]
        if any(sum((a - b) ** 2 for a, b in zip(q, p)) < DUPLICATE_M ** 2 for q in near):
            return
        near.append(p)
        out.append(Entry(cat, float(p[0]), float(p[1]), float(p[2]), ref))

    for r in rows:
        if not r.get("p"):
            continue
        p = r["p"][0]
        ref = tarot_ref(r.get("n", ""), d.tarot) if "mq033" in r.get("n", "") else None
        if ref:
            add("T", p, ref)
        contents = {i for i in r["ids"] if i.startswith("Items.")}
        for t in r["ids"]:
            if t.startswith("LootTables.") and placed[t] <= TABLE_REACH:
                contents |= expand(t)
        for i in sorted(contents):
            it = d.items.get(i)
            cat = category(it) if it else None
            if cat:
                add(cat, p, i)
    return out


def emit(entries: list[Entry], chunk: int = 100, quests: dict | None = None) -> str:
    es = sorted(entries, key=lambda e: (CATEGORIES.index(e.cat), e.ref, e.x, e.y))
    chunks = [es[i:i + chunk] for i in range(0, len(es), chunk)]

    def note(e: Entry) -> str:
        q = quest_note(e.ref, quests) if quests and e.cat != "T" else None
        return f",{q}" if q is not None else ""

    lines = ["module OverlayMap", "",
             "// Generated by tools/collectibles/gen.py from the game's world sectors and item records. Do not edit.",
             "// An entry is category,x,y,z,ref[,quest]; entries are joined by ';'. Categories: " + CATEGORIES + ".",
             "// quest (quest items only): <type><pl>:<title LocKeys joined by '+'>, see quest_note in gen.py.",
             "public abstract class NMCollectData {",
             f"    public static func Count() -> Int32 {{ return {len(es)}; }}",
             f"    public static func Chunks() -> Int32 {{ return {len(chunks)}; }}", "",
             "    public static func Chunk(index: Int32) -> String {", "        switch index {"]
    for k, c in enumerate(chunks):
        body = ";".join(f"{e.cat},{e.x:.2f},{e.y:.2f},{e.z:.2f},{e.ref}" + note(e) for e in c)
        lines.append(f"            case {k}: return \"{body}\";")
    lines += ["        }", "        return \"\";", "    }", "}", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scan", type=Path, required=True)
    ap.add_argument("--dump", type=Path, required=True)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--quests", type=Path, default=QUESTS)
    args = ap.parse_args(argv)
    d = load_dump(args.dump)
    entries = collect(load_scan(args.scan), d)
    quests = json.loads(args.quests.read_text())
    args.out.write_text(emit(entries, quests=quests))
    counts = collections.Counter(e.cat for e in entries)
    print(" ".join(f"{c}={counts[c]}" for c in CATEGORIES), f"total={len(entries)} -> {args.out}")
    missing = sorted(d.tarot - {r for e in entries if e.cat == "T" for r in e.ref.split("+")})
    print("tarot without a world spot:", ", ".join(missing) or "none")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
