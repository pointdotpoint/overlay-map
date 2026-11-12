# Shop names (VendorData.reds)

`gen.py` writes `r6/scripts/OverlayMap/Generated/VendorData.reds` from the game's own data. Rerun it after a game
patch. `G` is the game folder, `WK` is WolvenKit 10 (`~/.local/share/nightmap-tools/wk10`).

1. Journal (shop pins and their ids):
   `WK extract G/archive/pc/content/basegame_4_gamedata.archive -r '\.journal$' -o raw`, the same for
   `G/archive/pc/ep1/ep1_2_gamedata.archive`, then `WK convert s raw/base -o json` and `WK convert s raw/ep1 -o json_ep1`.
2. Vendor names: every `Vendors.<id>.localizedName` flat name (grep them from a TweakDB name list such as CET's
   `tweakdbstr`), read from `G/r6/cache/tweakdb_ep1.bin` with a TweakDB reader (WolvenKit's `TweakDBReader`) into
   `{"Vendors.<id>.localizedName": value}`.
3. English text: extract `onscreens*.json` from both `lang_en_text.archive` files, `WK convert s` them, and write
   `{"<primaryKey>": "<femaleVariant>"}`.
4. `python3 -I tools/vendors/gen.py --journal base.json --journal ep1.json --flats vendors.json --loc loc.json`

The localization's `secondaryKey` shows where each string belongs, which is how shop names that live in
`Districts.*` area records (for example `fastTravel-districts-GunORama_localizedName`) were found. The runtime names those
shops from the area the pin stands in (`NMAreaIndex.VenueAt`).
