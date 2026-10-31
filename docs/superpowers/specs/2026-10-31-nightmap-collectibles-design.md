# NightMap collectibles

## Intent

Show every fixed-spot collectible in Night City and Dogtown on NightMap, one icon per category, so a player can see
what is left to find. Collected ones stay on the map, scratched out at half their normal strength. NightMap is
published on Nexus, so the data comes from the game's own files, never from MapGenie or other fan maps.

## Goals

- Pins for shards, tarot graffiti, iconic weapons, legendary cyberware, legendary clothing and skill shards, at their
  exact world positions (with height).
- A new icon per category, drawn in NightMap's UI atlas, tinted per category.
- Collected pins: a diagonal scratch across the icon, and half the pin's normal opacity.
- A Mod Settings toggle per category; collectibles show in the ALL filter view only, like photo pins.
- Item names come from the game at runtime, so they follow the game's language.
- The sidebar shows the item's name, its category, collected or not, and the distance.
- Teleport to a collectible pin lands at its exact spot (as a fixed vanilla marker does).

## Non-goals

- MapGenie's "hidden gems" and "easter eggs": editors picked those spots; nothing in the game's data marks them.
- Crafting specs: in 2.x they come from randomised reward tables, not fixed spots.
- Items only given by quests, bosses or vendors: they have no fixed spot.
- Free vehicles and restricted data terminals: not in the world data this scan reads.

## Anti-goals

- Shipping any data scraped from a fan map.
- A pin that claims "collected" for something the player never had.
- Cost while the map is closed.

## Data pipeline (offline, `tools/collectibles/`)

1. `scan.py` converts every world streaming sector (base game and Phantom Liberty) with WolvenKit 10 (the 8.x and
   9.x releases cannot read the 2.3 sectors) and keeps each entity node that carries item or loot data, or a tarot
   name, with its position.
2. The soak harness command `lootdump` (tools/soak/autopilot) writes every item record (kind, type, quality, tags,
   shard journal path, name) and every loot table to `lootdump.txt` in a run's channel folder.
3. `gen.py` joins them. A node's items are its own item IDs plus the items of any loot table placed at most three
   times (wider tables are random drops). Categories:
   - shard: a readable item with a journal entry;
   - iconic weapon: tag `IconicWeapon`;
   - cyberware: cyberware of Legendary quality;
   - clothing: clothing of Legendary quality;
   - skill shard: `*Skillbook*` items;
   - tarot: nodes named `mq033_<card>`; minor cards are named `mq033_minor_<rank>_of_<suit>` in the world and
     `mq033_<rank>_of_the_<suit>` in the journal.
   Duplicates (same item within 2 m) collapse. Output: `r6/scripts/NightMap/Generated/CollectData.reds`, chunks of
   `category,x,y,z,ref` entries; `ref` is a TweakDB item name, or tarot journal ids joined with `+`.

## Runtime (`r6/scripts/NightMap/Collect/`)

- One layer per category (`Collect.<Category>`), Icon pin style, clustering on. Built once per session on first
  map open, then only collected state is re-checked on each open.
- Collected state:
  - shard: its journal entry (from the item's secondary action) is not Inactive;
  - tarot: any of its tarot journal entries is not Inactive;
  - items: the item's record ID is in a per-save `persistent` list on NightMapSystem, filled from V's inventory each
    time the map opens and from `ItemAddedEvent` on the player. Items sold before this version are not known.
- A collected item carries `WithStruck(true)` and `WithOpacity(0.5)`; the renderer draws the atlas part
  `icon_strike` over the icon, tinted and faded like it.

## Decided by the builder

- Category colours and glyph designs.
- Halving is relative: a collected icon is half as strong as an uncollected one in the same state (idle or selected).
- A "Show collected" toggle (on by default) beside the category toggles.
