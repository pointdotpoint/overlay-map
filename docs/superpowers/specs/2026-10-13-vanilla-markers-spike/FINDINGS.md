# Vanilla markers spike: findings (2026-10-13)

The probe is throwaway and has been removed from the game. Inputs:
- `RESEARCH.md`: CDPR script sources;
- `look/LOOK.md`: vanilla widget, atlas and colours;
- `probe_raw.log`, `probe_summary.txt`: in-game run, game 2.31.

## Data
- `GameInstance.GetMappinSystem(game).GetMappins(gamemappinsMappinTargetType.Map, out arr)` returns **560** mappins in a
  mid-game save. All of them are also in `GetAllMappins()`, which returns 582 and adds Stealth/Stub/NPC entries.
  - The 560 include static POIs: 120 fast travel, 102 drop points, 91 + 22 NCPD gang watch (discovered + completed),
    24 hidden stashes, 18 NCART, 18 cars for sale, 15 tarot, 16 outposts, fixers, apartments, vendors and quests.
  - Classes: PointOfInterestMappin 238, FastTravelMappin 138, RuntimeMappin 103, QuestMappin 81.
- **Undiscovered** gigs appear with `UndiscoveredPhase` (Retrieving, Thievery, BountyHunt, Sabotage, ClientInDistress).
  **Completed** NCPD/outposts appear with `CompletedPhase`. Vanilla dims completed pins with `CompletedPOIOpacity` 0.7,
  and hides them unless tracked.
- `IsVisible()`: 501 of 560 are visible. Static quest-giver gigs not yet available report `vis=0`. Use `IsVisible()` as
  the "on the map" rule, and also show the player-tracked pin.
- **Stable:** `Map` stayed at 560 through 5 minutes of play and a waypoint set and clear. `World`/`Minimap` change with
  proximity. Weak refs and `GetMappin(id)` both stay valid.
- **Cost:** `GetMappins(Map)` 0.025 ms per call, and touching all 560 for position/variant 0.29 ms. A poll every 1–2 s
  while the map is open, diffed by `NewMappinID.value`, is negligible.
- **Names:** `GetDisplayName()` returns a `LocKey#NNN`, which needs localising. It is empty for drop points; use the
  variant label key (`UI-MappinTypes-*`) instead.

## Look (LOOK.md)
- One vanilla widget for every pin: an icon from `base\gameplay\gui\common\icons\mappin_icons.inkatlas` (201 parts,
  64×64), tinted by the mappin group's widget state from `common\mappins.inkstyle`, over a `shadowBlobSquare_big` blob.
  - Idle opacity is 0.5; selected/tracked is 1.0 at 1.3× scale.
  - There are no frames.
- Icon part = `MappinUIUtils.MappinToTexturePart(variant)`, which works from script. Colour group =
  `MappinUtils.GetMappinsGroup(variant).WidgetState()`.
  - Quest #FFFF4E;
  - Gigs #00FFD5;
  - Story/NCPD (Default) #FF7167;
  - ServicePoint #FFFFFF;
  - FastTravel #59B4FF;
  - FastTravelMetro #CC81FF;
  - QuestComplete #6B6C6C.
- Two parts returned by the mapping are missing from the atlas: `failed_crossing` and `relic_dataterm`. Fall back to
  the group default.

## Filters (TweakDB `WorldMap.WorldMapCustomFiltersList`, 12 entries, localized names available)
- Jobs (Quest);
- Gigs;
- Cyberpsycho Sighting;
- NCPD Scanner;
- Fast Travel;
- Ripperdoc;
- Vendor;
- Autofixer;
- Drop Point;
- Apartment for Rent;
- TAROT;
- Your Apartments.

`MappinUtils.GetFilterGroup(variant)` maps each variant. Vanilla keeps filter state natively in the menu, so NightMap
keeps its own.

## Tracking
- **Quest:** tracked objective → quest mappin match by journal path hash works (1 match).
  `JournalManager.TrackEntry(GetEntry(hash))` is what vanilla calls, so it is scriptable.
- **Header:** tracked objective + parent quest titles are readable (LocKeys).
- **Vanilla custom waypoint:** a `RuntimeMappin` with `CustomPositionVariant`, part `dynamic_event`. It is
  `GetManuallyTrackedMappinID()` and is in all lists. Clearing it from script is possible
  (`UnregisterMappin(GetManuallyTrackedMappinID())`).
- **Creating a waypoint or tracking a non-quest pin from script failed.** `RegisterMappin` with `QuestDynamicMappinDefinition`
  or `DropPointStaticMappin` returned an id that never resolved. Vanilla's track calls are `protected import` on the menu
  controller. This belongs to the native plugin (roadmap sub-project 3).
- The `UI_System.TrackedMappin` blackboard did not fire.

## Zoom rules
The WorldMapSettings record was not found, so the vanilla per-zoom filter groups are unknown. NightMap defines its own
zoom/declutter rules on top of its existing clustering.
