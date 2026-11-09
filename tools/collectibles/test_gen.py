"""gen.py: categories, tarot names, loot table reach, duplicates and the generated script."""
import sys
from pathlib import Path

import importlib.util

sys.path.insert(0, str(Path(__file__).resolve().parent))
# Loaded by path under its own name: tools/areas has a gen.py too, and a plain "import gen" gets whichever ran first.
_spec = importlib.util.spec_from_file_location("collectibles_gen", Path(__file__).with_name("gen.py"))
gen = importlib.util.module_from_spec(_spec)
sys.modules["collectibles_gen"] = gen   # dataclasses look their module up here
_spec.loader.exec_module(gen)

DUMP = """i|Items.shard_a|Item_Record|Gen_Readable|Common||J:onscreens/shards/a|Shard A
i|Items.Preset_Gun_Iconic|WeaponItem_Record|Wea_Handgun|Legendary|IconicWeapon,Weapon,||Gun
i|Items.Preset_Gun_Plain|WeaponItem_Record|Wea_Handgun|Rare|Weapon,||Plain gun
i|Items.Leg_Arm|Item_Record|Cyberware|Legendary|Cyberware,||Arm
i|Items.Rare_Arm|Item_Record|Cyberware|Rare|Cyberware,||Rare arm
i|Items.Leg_Jacket|Clothing_Record|Clo_OuterChest|Legendary|Clothing,||Jacket
i|Items.BodySkill_Skillbook|Item_Record|Gen_Readable|Rare|||Skill Shard: Solo
i|Items.Recipe_X|RecipeItem_Record|Gen_Misc|Rare||Items.X,|Spec
t|LootTables.once|Items.Preset_Gun_Iconic,||
t|LootTables.wide|Items.Leg_Arm,||
t|LootTables.parent||LootTables.child,
t|LootTables.child|Items.Leg_Jacket,||
tarot|tarot_cards/mq033_the_fool1|0|The Fool|Inactive|mq033_the_fool1
tarot|tarot_cards/mq033_the_fool2|0|The Fool|Inactive|mq033_the_fool2
tarot|tarot_cards/mq033_page_of_the_swords|0|Page of Swords|Inactive|mq033_page_of_the_swords
tarot|tarot_cards/mq033_ep1_king_of_the_wands|0|King of Wands|Inactive|mq033_ep1_king_of_the_wands
end|8|4
"""


def row(ids, x=1.0, name="", tpl=""):
    return {"s": "exterior_0_0_0_0", "n": name, "tpl": tpl, "ids": ids, "p": [[x, 2.0, 3.0]]}


def test_categories(tmp_path):
    p = tmp_path / "d.txt"
    p.write_text(DUMP)
    d = gen.load_dump(p)
    assert gen.category(d.items["Items.shard_a"]) == "S"
    assert gen.category(d.items["Items.Preset_Gun_Iconic"]) == "W"
    assert gen.category(d.items["Items.Preset_Gun_Plain"]) is None
    assert gen.category(d.items["Items.Leg_Arm"]) == "C"
    assert gen.category(d.items["Items.Rare_Arm"]) is None
    assert gen.category(d.items["Items.Leg_Jacket"]) == "L"
    assert gen.category(d.items["Items.BodySkill_Skillbook"]) == "K"
    assert gen.category(d.items["Items.Recipe_X"]) is None


def test_tarot_names():
    ids = {"mq033_the_fool1", "mq033_the_fool2", "mq033_page_of_the_swords", "mq033_ep1_king_of_the_wands"}
    assert gen.tarot_ref("mq033_the_fool", ids) == "mq033_the_fool1+mq033_the_fool2"
    assert gen.tarot_ref("mq033_minor_page_of_swords", ids) == "mq033_page_of_the_swords"
    assert gen.tarot_ref("{mq033_ep1_king_of_the_wands}", ids) == "mq033_ep1_king_of_the_wands"
    assert gen.tarot_ref("mq033_minor_reward_wands", ids) is None
    assert gen.tarot_ref("misty_tarot_deck", ids) is None


def test_collect_reach_and_duplicates(tmp_path):
    p = tmp_path / "d.txt"
    p.write_text(DUMP)
    d = gen.load_dump(p)
    rows = [row(["Items.shard_a"]), row(["Items.shard_a"], x=1.2),   # same shard within 1 m: one pin
            row(["Items.shard_a"], x=50.0),                           # another case: its own pin
            row(["LootTables.once"]), row(["LootTables.parent"])]
    rows += [row(["LootTables.wide"], x=float(i * 10)) for i in range(4)]   # placed 4 times: random drop, skipped
    rows.append(row([], name="mq033_minor_page_of_swords", tpl="x.ent"))
    out = gen.collect(rows, d)
    got = sorted((e.cat, e.ref, e.x) for e in out)
    assert got == [("L", "Items.Leg_Jacket", 1.0), ("S", "Items.shard_a", 1.0), ("S", "Items.shard_a", 50.0),
                   ("T", "mq033_page_of_the_swords", 1.0), ("W", "Items.Preset_Gun_Iconic", 1.0)]


def test_emit_chunks():
    es = [gen.Entry("S", float(i), -2.5, 3.25, f"Items.s{i:03}") for i in range(250)]
    text = gen.emit(es, chunk=100)
    assert "public static func Count() -> Int32 { return 250; }" in text
    assert "public static func Chunks() -> Int32 { return 3; }" in text
    assert "case 2: return \"S,200.00,-2.50,3.25,Items.s200;" in text
    assert text.count("case ") == 3


QUESTS = {"q304_stadium": [79421, "MainQuest", 1], "q304_deal": [86832, "MainQuest", 1],
          "q105_dollhouse": [8627, "MainQuest", 0], "q105_04_judys": [8630, "MainQuest", 0],
          "sq024_city_race": [500, "SideQuest", 0], "sq024_badlands_race": [501, "SideQuest", 0],
          "mq006_rollercoaster": [9001, "MinorQuest", 0]}


def test_quest_notes():
    # The longest journal quest id the item id starts with wins, even when the code has other quests.
    assert gen.quest_note("Items.Q304_stadium_archived_convesation", QUESTS) == "M1:79421"
    # One quest under the code: that quest.
    assert gen.quest_note("Items.mq006_body_shard", QUESTS) == "m0:9001"
    # Several quests share the code and the id names none: every candidate, keys sorted; the type when shared.
    assert gen.quest_note("Items.q105_01_guards_chat", QUESTS) == "M0:8627+8630"
    assert gen.quest_note("Items.sq024_book_shard", QUESTS) == "S0:500+501"
    # A quest-named item with no journal quest still notes that a quest owns it.
    assert gen.quest_note("Items.mq034_dead_man_shard", QUESTS) == "Q0:"
    # Not a quest item.
    assert gen.quest_note("Items.ep1_generic_cz_article_shard", QUESTS) is None
    assert gen.quest_note("mq033_the_fool1", QUESTS) is None   # tarot refs are journal ids, not items


def test_emit_quest_field():
    es = [gen.Entry("S", 1.0, 2.0, 3.0, "Items.Q304_stadium_x"), gen.Entry("S", 4.0, 5.0, 6.0, "Items.plain")]
    text = gen.emit(es, quests=QUESTS)
    assert "S,1.00,2.00,3.00,Items.Q304_stadium_x,M1:79421;S,4.00,5.00,6.00,Items.plain\"" in text
