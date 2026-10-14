# NightMap: Sub-project 2, vanilla map markers

**Status:** design approved in conversation on 2026-10-13. The written spec awaits user review.
**Branch:** `feat/vanilla-markers`, forked from `feat/vector-layer` at 11497de. Sub-project 1b is not merged yet; its
final performance verdict was deferred by the user.
**Parent spec:** `2026-10-11-nightmap-core-design.md`, §1 roadmap item 2.
**Spike evidence**, in `2026-10-13-vanilla-markers-spike/`:
- `FINDINGS.md`: the summary;
- `RESEARCH.md`: script APIs with CDPR source refs;
- `LOOK.md`: the vanilla widget, atlas and colours;
- `variant_table.txt`: variant → group, state, filter, icon part, label;
- `filters.txt`: the vanilla quick and custom filter lists;
- `look_mock.png`.

## 1. Goal and user decisions

Show every map marker that the vanilla world map shows on the NightMap overlay, **with the vanilla look**, so players
recognise markers immediately ("we need to use the same map markers from the game if possible because the user is used
to them").

| Topic | Decision (user, 2026-10-13) |
|---|---|
| Look | **Vanilla look.** The same icon, colour and opacity behaviour as the vanilla world map. NightMap hex chips remain only for clusters and other mods' items. |
| Scope | Show all markers, plus: info-card details; track quest; filters; tracked-quest header. |
| Approach | Rebuild the vanilla look from the game's own atlas and colours with NightMap's pooled widgets. Do not spawn vanilla widgets. |
| Waypoints | Setting a custom waypoint or tracking a non-quest marker is **deferred to the native plugin (sub-project 3)**. This release tracks quests/gigs, and shows and clears the vanilla custom waypoint. |
| Clustering | Overlapping markers merge into the existing cluster hex when zoomed out. |
| Default zoom | The first open of a session starts fully zoomed in (done on this branch, f407623). |

The binding product constraints from sub-project 1b (spec `2026-10-12-...` §11.5) apply:
- very light at runtime;
- a state-of-the-art look;
- themeable;
- layers ready for photos, widgets and collectible POIs.

## 2. Non-goals
- Creating custom waypoints, or tracking vendors, fast-travel points and other non-quest markers (sub-project 3).
- Fast travel from the map, district labels and outlines (sub-project 4).
- Quest/gig *areas*: vanilla's quest area circles, `IsQuestAreaMappin`.
- Player vehicles and NPC/stealth/stub/device pins. These are not in the `Map` target list.
- Controller support.

## 3. Facts the design rests on (spike, game 2.31)
- **Source.** `GameInstance.GetMappinSystem(game).GetMappins(gamemappinsMappinTargetType.Map, out arr)` returns every
  world-map marker: 560 in a mid-game save. It includes static POIs, undiscovered gigs (`UndiscoveredPhase`) and
  completed activities (`CompletedPhase`).
  - Classes: `PointOfInterestMappin`, `FastTravelMappin`, `RuntimeMappin`, `QuestMappin`.
  - The list is stable over minutes of play. `NewMappinID.value` (Uint64) is a stable key, and `GetMappin(id)`
    re-resolves.
- **Cost.** One `GetMappins(Map)` call takes 0.025 ms. Reading position and variant for all 560 takes 0.29 ms.
- **Visibility.** `IsVisible()` is the engine's map visibility (501 of 560 true). `IsPlayerTracked()` marks the tracked
  pin.
- **Icon.** `MappinUIUtils.MappinToTexturePart(variant)` gives a part in `base\gameplay\gui\common\icons\mappin_icons.inkatlas`
  (201 parts, 64×64). `failed_crossing` and `relic_dataterm` are not in the atlas.
- **Colour.** `MappinUtils.GetMappinsGroup(variant).WidgetState()` is a state name in `base\gameplay\gui\common\mappins.inkstyle`.
  Values are in LOOK.md; the main ones:
  - Quest #FFFF4E;
  - Gigs #00FFD5;
  - Default (NCPD) #FF7167;
  - ServicePoint #FFFFFF;
  - FastTravel #59B4FF;
  - FastTravelMetro #CC81FF;
  - QuestComplete #6B6C6C.
  - `CompletedPOIOpacity` = 0.7.
- **Vanilla widget.**
  - An 80×80 canvas: a black `shadowBlobSquare_big` blob, then the icon.
  - Idle opacity 0.5; selected/tracked opacity 1.0 at 1.3× (the OnSelect animation end state).
  - No frame.
- **Filters.** `MappinUtils.GetFilterGroup(variant)` gives a `gamedataWorldMapFilter`.
  - The 12 custom filters in `WorldMap.WorldMapCustomFiltersList` have localized names: Jobs, Gigs, Cyberpsycho Sighting,
    NCPD Scanner, Fast Travel, Ripperdoc, Vendor, Autofixer, Drop Point, Apartment for Rent, TAROT, Your Apartments.
  - The quick list in `WorldMap.WorldMapQuickFiltersList` is Dynamic (all), Jobs, Service Point.
- **Quest link.** `QuestMappin`/`PointOfInterestMappin.GetJournalPathHash()` → `JournalManager.GetEntry(hash)` gives the
  map pin's journal entry. Vanilla tracks with `JournalManager.TrackEntry(entry)` when the mappin's group is `Quest` or
  `SecondaryQuest` and the variant is not `Zzz18_RacingVariant`. Verified match: the tracked objective has 1 quest
  mappin.
- **Header.**
  - `GetTrackedEntry()` → objective (`GetDescription()`).
  - `GetParentEntry` ×2 → `JournalQuest.GetTitle(jm)`, already localized.
  - The style is Quest if the type is MainQuest/SideQuest/MinorQuest/CourierSideQuest, else Gigs.
  - Change callback: `RegisterScriptCallback(obj, 'OnTrackedEntryChanges', gameJournalListenerType.Tracked)`.
- **Custom waypoint.**
  - The vanilla one is a `RuntimeMappin` with `CustomPositionVariant`, part `dynamic_event`, and it is
    `GetManuallyTrackedMappinID()`.
  - Clearing it from script works with `UnregisterMappin(GetManuallyTrackedMappinID())`, as `autoDriveSystem` does.
  - Creating one from script failed.
- **Names.** `GetDisplayName()` returns a loc key, which needs `GetLocalizedText`. It is empty for drop points; fall back
  to the variant label key `UI-MappinTypes-*` (`variant_table.txt`).
  - Fast travel: `FastTravelMappin.GetPointData().GetPointDisplayName()` and `GetDistrictDisplayName()`.

## 4. Architecture

New module folder `r6/scripts/NightMap/Vanilla/`. It is built-in content that uses the public layer API like any mod
would. The API gains only what the vanilla look needs, and the additions are useful to other mods too.

| Unit | Responsibility | Depends on |
|---|---|---|
| `Vanilla/MarkerStyle.reds` (`NMVanillaStyle`) | Pure mapping from variant + phase + flags to {icon part (with fallback), colour state → HDRColor, filter category, label key, trackable?}. A table-driven function; no game state. | §3 tables, Theme |
| `Vanilla/MarkerSource.reds` (`NMVanillaSource`) | Reads `GetMappins(Map)`, applies the visibility rule (§6), diffs against the previous snapshot by `NewMappinID.value`, and emits add/move/update/remove. Poll: on map open, then every 1.5 s while open. Nothing while closed. | MappinSystem |
| `Vanilla/MarkerLayers.reds` (`NMVanillaLayers`) | Owns one NightMap layer per vanilla filter category (12) plus `Vanilla.Pinned` (tracked quest marker + custom waypoint, never filtered). Applies source diffs to items. Maps item id ↔ mappin id. Implements the layer listener (card + action). | layer API, Style, Source |
| `Vanilla/Tracking.reds` (`NMVanillaTracking`) | Quest track from a mappin (journal lookup + `TrackEntry`), clear the custom waypoint, `CanTrack`. | JournalManager, MappinSystem |
| `Vanilla/QuestHeader.reds` (`NMQuestHeader`) | Tracked quest title + objective + style for the header. Refreshes on the journal Tracked callback and on map open. | JournalManager |
| `Vanilla/Filters.reds` (`NMVanillaFilters`) | Quick view cycle (All → Jobs → Services) × per-category Mod Settings toggles → layer visibility. | Settings |
| Renderer (existing `ItemRenderer.reds`) | New per-layer **pin style `Icon`**: no hex; icon + shadow blob; idle opacity; selected/emphasised at 1.0 and 1.3× with a short grow; per-item dimming (completed). Clusters stay hex for every style. | — |

**Public API additions** (documented in `docs/api.md`):
- `layer.SetPinStyle(NightMapPinStyle.Hex | NightMapPinStyle.Icon)`;
- `item.WithEmphasis(Bool)`: always full opacity and 1.3×, as for a tracked marker;
- `item.WithOpacity(Float)`: e.g. 0.7 for completed;
- `layer.Update(id, item)`: in-place change of icon, tint, emphasis or label without remove/add, if not already
  expressible via `Move` plus re-add.

The plan decides the exact form. Existing item limits hold: 7 categories per layer, which is why there is one layer per
filter category. The 50k-item performance contract holds.

**Why one layer per filter category:** filters become `layer.SetVisible`, and each layer stays within the 7-category
limit (categories = colour groups inside a filter). Other mods can toggle or inspect vanilla categories by layer id
`Vanilla.<FilterName>`. Clustering already works across layers.

## 5. Look
- Icon: the vanilla atlas part, tinted with the vanilla state colour. HDR values above 1.0 are clamped to 1, since the
  overlay has no bloom.
- The shadow blob is drawn under the icon at vanilla proportions.
- Size: constant on screen. The default icon size is the vanilla world map's icon size relative to the screen, scaled to
  NightMap's panel. Tune it at the checkpoint against a side-by-side screenshot.
- Opacity:
  - idle 0.5;
  - selected by the crosshair or tracked (emphasis): 1.0 at 1.3×, with a ~0.15 s grow;
  - completed: hidden unless tracked; if tracked, 0.7 opacity with the QuestComplete grey.
- Undiscovered gigs: the variant's normal icon and colour, as vanilla does (verify at the checkpoint).
- Missing atlas parts (`failed_crossing`, `relic_dataterm`, or any part the renderer cannot find) fall back to the
  group's default part. The fallback table lives in `NMVanillaStyle`.
- Colours live in `NMTheme`, in a vanilla-marker table keyed by state name, so theming (sub-project 5) can recolour
  them. The default is vanilla.
- Clusters: the existing hex cluster with a count and its top-3 icons, drawn as vanilla icons.

## 6. Visibility rule (per mappin, per poll)
Shown if all of these hold:
- in the `Map` list and `IsVisible()`, **or** player-tracked (`IsPlayerTracked()`, or it is
  `GetManuallyTrackedMappinID()`);
- not `CompletedPhase`, unless tracked;
- the variant maps to a known filter category, or is `CustomPositionVariant`. Unknown variants are skipped and logged
  once per variant.
- its layer is visible under the filters (§8). Tracked markers live in `Vanilla.Pinned` and are always visible.

## 7. Info card and actions
`GetDetails(id)` for a vanilla item:
- **Category line:** the localized filter name, in the marker's colour.
- **Title:** the localized display name. For fast travel, the point name. If empty, the localized variant label.
- **Subtitle:** the district (fast travel: `GetDistrictDisplayName()`), else empty.
- **Rows:**
  - Distance (m/km, from `GetDistanceToPlayer()`);
  - Status: Undiscovered, Completed or Tracked, when applicable;
  - for quest-linked markers, Quest (title) and Objective (description).
- **Actions:**
  - quest-trackable → `NUM 0 Track quest`, or "Tracked" when it already is;
  - custom waypoint → `NUM 0 Clear waypoint`;
  - otherwise no action, plus a row "Waypoints: coming with the native plugin" (the wording is final at the checkpoint).

`OnActivated(id)`: track or clear as above. Refresh the card and the header immediately; there is no need to wait for
the next poll.

## 8. Filters
- **Quick view, NUM /** (`IK_Divide`; the core spec reserved it for filter cycling). Cycles All → Jobs → Services →
  All. The definitions come from the vanilla quick list:
  - Jobs = filter categories Jobs, Gigs, Cyberpsycho Sighting, NCPD Scanner;
  - Services = Ripperdoc, Vendor, Autofixer, Drop Point, Fast Travel, Apartment for Rent, Your Apartments.
  - TAROT shows only in All.
  - The current view shows in the header and on the key-hint bar.
- **Mod Settings → NightMap → Map filters:** one Bool per category (12), default on, persisted by Mod Settings. A
  category is visible only if its toggle is on and the quick view includes it.
- The key binding is configurable like the other keys (`keyFilter`, default `IK_Divide`). The hint bar gains
  `NUM / FILTER`.

## 9. Tracked-quest header
- Under "NIGHT CITY" / district:
  - the tracked quest title in the Quest (yellow) or Gigs (teal) colour;
  - below it, the objective text with a counter "(n/m)" when the objective has one.
- Hidden when nothing is tracked. If the custom waypoint is the tracked thing, show the localized
  `MappinToString(CustomPositionVariant)`.
- Updates on the journal Tracked callback (registered while the map system lives; unregistered on detach), on map
  open, and after a NightMap track action.

## 10. Performance
- Closed: zero cost. No polling, and the journal callback only sets a dirty flag.
- Open:
  - the poll every 1.5 s costs about 0.3 ms per poll, spread over one frame, which is acceptable at 1 in ~90 frames;
  - the diff touches only changed items;
  - rendering goes through the existing pools (300 chips / 80 clusters).
- New perf suite row `vanilla_open`: the map open on the circle sweep with the real vanilla layers on, no synthetic items.
  It is gated like `open_empty` (+1.5 / +3.0 ms) with the existing 3-run median and drift rules. Also extend
  `results.py`.
- The script cost of the poll frame is reported separately, as max script ms over the run: it should stay under 1 ms.

## 11. Testing
- **Self-tests** (in-game Ctrl chord):
  - `NMVanillaStyle` table: every variant in `variant_table.txt` with a non-none group maps to a category and an
    existing atlas part (`IsTexturePartExist`) or a fallback;
  - the visibility rule truth table;
  - diff (add, move, remove, phase change, tracked change);
  - filter composition (quick view × toggles);
  - the header formatting with and without a counter.
- **Offline:** `tools/check.sh` compile. A Python test generates and checks the style table from `variant_table.txt`, so
  the table stays in sync if it is generated.
- **Checkpoint 4 (in-game):**
  1. Vanilla map and NightMap at the same spot and zoom, screenshots side by side. Icons, colours and visible set
     should match.
  2. Track a quest from NightMap, and check that the HUD and minimap follow.
  3. Clear a vanilla waypoint from NightMap.
  4. Filters: the quick cycle and a Mod Settings toggle.
  5. The header updates.
  6. Perf suite 3 runs: `vanilla_open` passes.

## 12. Review focus (most likely to bite a user)
1. A marker the vanilla map shows is missing. Variants absent from the table, or `IsVisible()` semantics in other
   saves: log unknown variants once, and compare at the checkpoint.
2. Stale markers after quest progress or discovery. The poll must pick up phase, visibility and tracked changes, not
   only add/remove.
3. Tracking the wrong quest from a POI with an unrelated journal hash. Only track when the group is Quest or
   SecondaryQuest and the entry resolves.
4. Colour or icon mismatches for HDR states and the missing atlas parts.
5. The cost of the poll frame on low-end CPUs. Keep the diff allocation-light; no per-frame work while idle.
