# NightMap markers spike: vanilla mappin research

Source: `~/nightmap/.scratch/refs/cp-scripts/scripts/` (mid-2025 sources). All paths below are relative to that dir.
Abbreviations: `WM` = `cyberpunk/UI/fullscreen/map/worldMap.script`, `WMT` = `cyberpunk/UI/fullscreen/map/worldMapTooltips.script`,
`MU` = `cyberpunk/UI/mappins/mappinUtils.script`, `MS` = `core/systems/mappinSystem.script`, `JM` = `core/systems/journalManager.script`,
`TDBR` = `core/data/tweakDBRecords.script`, `TDBE` = `core/data/tweakDBEnums.script`.
"[inferred]" = not read in script, deduced.

KEY STRUCTURAL FACT: the world map menu does NOT hand script a list of mappins. Mappin widgets are spawned **natively** by the engine
(`MappinsContainerController` is an `import class`; script only supplies `CreateMappinUIProfile` which says which `.inkwidget` to use per mappin).
Script sees each mappin only through the per-widget controller (`BaseWorldMapMappinController.GetMappin()`), so the exact set the vanilla map shows is
decided native-side (filter + zoom level + phase + group collection). We have to rebuild that decision ourselves from `IMappin` data + TweakDB filter records.

---

## 1. Data source

### 1.1 How the vanilla menu gets mappins
- `WorldMapMenuGameController extends MappinsContainerController` (`WM:59`, `cyberpunk/UI/mappins/mappinsContainers.script:1`). `MappinsContainerController extends inkProjectedHUDGameController`
  and exposes only `GetSpawnContainer()`, `psmVision/psmCombat/psmZone` and the virtual `CreateMappinUIProfile(...)`. Spawning, projection and lifecycle are native.
- The menu's override (`WM:1535`):
  `public override function CreateMappinUIProfile( mappin : weak< IMappin >, mappinVariant : gamedataMappinVariant, customData : MappinControllerCustomData ) : MappinUIProfile`
  returns for EVERY mappin the same widget: `R"base\gameplay\gui\fullscreen\world_map\mappins\default_mappin.inkwidget"` (or `...\player_mappin.inkwidget` when `customData.IsA('gameuiWorldMapPlayerInitData')`),
  spawn profile `T"MappinUISpawnProfile.Always"`, runtime profile `T"MapMappinUIProfile.Default"`. So "which mappins are on the map" is not in script; no `None()` filtering here. Contrast: the in-world container returns `MappinUIProfile.None()` for Stealth/Stub/PreventionVehicle/RoadBlockade (`mappinsContainers.script:54-170`), the world map does not.
- Per-widget class: `BaseWorldMapMappinController extends BaseInteractionMappinController` (`WM:1730`), `WorldMapPlayerMappinController` (`WM:1985`).
  Native-set fields: `selected`, `inZoomLevel`, `inCustomFilter`, `hasCustomFilter`, `isFastTravelEnabled`, `isVisibleInFilterAndZoom`, `groupState : gameuiMappinGroupState` (Ungrouped/Grouped/GroupedCollection/GroupedHidden, `WM:31`), `collectionCount : Uint8`;
  `IsGrouped()/IsCollection()/IsInCollection()` (`WM:1750-1752`).

### 1.2 Script-visible enumeration
`MappinSystem` (`MS:15`, obtained with `GameInstance.GetMappinSystem(game) : MappinSystem`, `core/systems/gameInstance.script:28`) has:
```
public import function GetMappins( targetType : gamemappinsMappinTargetType, out mappins : array< IMappin > );      // MS:33
public import function GetMappinEntries( targetType : gamemappinsMappinTargetType, out mappins : array< MappinEntry > ); // MS:32  (MappinEntry {id: NewMappinID; worldPosition: Vector4}, MS:7-11)
public import function GetMappin( mappinId : NewMappinID ) : IMappin;                                                // MS:34
import enum gamemappinsMappinTargetType { World, Minimap, Map }                                                       // MS:1-6
```
- There is **no `GetAllMappins()`**. The only bulk enumeration is `GetMappins(Map|Minimap|World, out array<IMappin>)`.
- No vanilla script ever calls `GetMappins`/`GetMappinEntries` (rg over all scripts: only the declarations). So semantics of `Map` are [inferred]: the set of mappins registered as visible on the world-map target (presumably what the menu then wraps in widgets). Must be probed in game (see section 9).
- Other lookups: `GetMappinFromQuest(questEntry) : weak<IMappin>` (`MS:42`), `GetMappinFromObjective(phaseEntry, objectiveEntry)` (`MS:41`), `GetQuestMappinPositionsByObjective(objectiveHash : Uint32, out positions : array<Vector3>) : Bool` (`MS:37`, used by `WM:UpdateTrackedQuest` to get objective positions), `GetQuestMappinPosition(mappinHash, out pos)` (`MS:43`), `GetPointOfInterestMappinSavedState(hash : Uint32, out phase : Uint16, out variant : Uint16, out active : Bool) : Bool` (`MS:36`; keyed by POI hash, usable for static POIs even if they are not instantiated, used in `journalNotification.script:630`), `DebugDiscoverAllPoiMappins()` (`MS:49`).

### 1.3 Are static POIs included?
- Class evidence: `PointOfInterestMappin extends IMappin` (`cyberpunk/UI/mappins/mappins.script:173`) is the type of static POIs (fixers `FixerVariant`, service points, `QuestGiver/gig`, `MinorActivity/NCPD`, `HuntForPsycho`, drop points, vehicles/apartments for purchase, Tarot, ...). `mappinsContainers.script:96` uses `IsExactlyA('gamemappinsPointOfInterestMappin')` for service points/fixers/world encounters in world HUD. The tooltip code casts `data.mappin` to `PointOfInterestMappin` for `Zzz01/02_*ForPurchase`, `Zzz05_ApartmentToPurchase` (`WMT:687-710`, `WM:821 GetCodexEntryForMappin`), so the world map definitely consumes POI mappins; i.e. they ARE `IMappin` instances. Whether `GetMappins(Map, ...)` returns them is [inferred yes], verify at runtime.
- `FastTravelMappin extends RuntimeMappin` (`mappins.script:155`), registered by `FastTravelSystem` via `RegisterFastTravelMappin(mappinData, nodeData)` (`core/systems/fastTravelSystem.script:589`); `FastTravelPointData.ShouldShowMappinOnWorldMap()` / `ShouldShowMappinInWorld()` (`fastTravelSystem.script:27-35`) read TweakDB `FastTravelPoint.ShowOnWorldMap`/`ShowInWorld`, so some fast-travel mappins exist only for the world, not the map. Metro NCART = `Zzz17_NCARTVariant`.
- Drop points: `dropPointSystem.script:484` registers `Mappins.DropPointStaticMappin`, variant `ServicePointDropPointVariant` via `RegisterMappin`.
- Quest mappins: `QuestMappin extends IMappin` (`mappins.script:50`); `IsQuestMappin/IsQuestNPCMappin/IsQuestEntityMappin/IsQuestAreaMappin`.
- Per `IMappin` there is also `IsStatic()`. Native-only items [inferred]: the grouping into "collections" (`gameuiMappinGroupState`), the player arrow (`player_mappin`), districts/subdistricts overlays (`WorldMapDistrictLogicController`, `WM:2011`), gang info. Grouping is purely a render concept; each member is still its own IMappin.

### 1.4 How vanilla decides what is shown (script-visible parts)
All in `BaseWorldMapMappinController` (`WM:1754-1925`) using native-computed flags:
- `GetDesiredOpacityAndInteractivity` (`WM:1852`): `interactive = hasCustomFilter ? (inCustomFilter && !m_isCompletedPhase) || IsTracked() : (inZoomLevel && !m_isCompletedPhase) || IsTracked()`; `visibleInGroup = groupState != GroupedHidden`; opacity = interactive ? 1 : 0. So: **CompletedPhase mappins are hidden (not interactive)** unless tracked; tracked mappins are always shown; the rest depends on filter and zoom level.
- `UpdateVisibility` (`WM:1782`): `m_isCompletedPhase = phase == CompletedPhase`; for `QuestMappin` the root widget visibility = `questMappin.IsActive()`.
- `UpdateIsNew` (`WM:1832`): `isNew = !m_mappin.IsVisited() && !IsCollection()` plays the `OnNew` library animation (the "NEW" pulse).
- Filter: `inCustomFilter` = native check of the mappin's filter group against the custom filter bitmask (`GetCustomFilters() : Uint32`, `HasCustomFilter(filter)`); else the **quick filter** (`GetQuickFilter()`), data = TweakDB `MappinUIFilterGroup` list (section 4).
- Zoom: `inZoomLevel` = the mappin's variant belongs to one of `WorldMapZoomLevel_Record.MappinFilterGroups` of the current zoom level (`TDBR:11666-11672`; `WorldMapSettings_Record.ZoomLevels` `TDBR:11650`). `WorldMapSettings_Record` (`TDBR:11644`): `ZoomLevels`, `NCPDEventsVisibilityRange() : Float` (NCPD events only appear within this range) (`TDBR:11662`), `EnableGroupTransitionAnimations`. Zoom record: `Zoom()`, `Fov()`, `IconScale()`, `ShowDistricts()`, `ShowSubDistricts()`, `CanChangeFilters()`. Fetch via `WorldMapMenuGameController.GetSettings()` (protected native, `WM:63`), but the record is also readable by TweakDB path [inferred: `T"WorldMap.<...>"`; only `WorldMap.WorldMapQuickFiltersList` and `WorldMap.WorldMapCustomFiltersList` IDs appear in script, `WM:237,337`].
- Distance: `IMappin.GetDistanceToPlayer()` exists but the world map does not use distance for visibility (spawn profile `Always`). The tooltip does not show distance either (only `GetTravelDistance()` for Delamain/fast travel cost, `WM:83`).
- Player-tracked: `BaseMappinBaseController.IsTracked()/IsPlayerTracked()/IsCustomPositionTracked()/IsDelamainTaxiTracked()` (`mappinsControllers.script:33-36`), `IMappin.IsPlayerTracked()` (`mappins.script:30`).

---

## 2. Per-mappin data

### 2.1 `IMappin` (`cyberpunk/UI/mappins/mappins.script:20-42`)
```
IsStatic() : Bool                IsVisible() : Bool            IsActive() : Bool          IsVisited() : Bool
IsQuestMappin() / IsQuestNPCMappin() / IsQuestEntityMappin() / IsQuestAreaMappin() : Bool
IsPlayerTracked() : Bool         GetWorldPosition() : Vector4  GetDisplayName() : String  GetDistanceToPlayer() : Float
GetVerticalRelationToPlayer() : gamemappinsVerticalPositioning {Above,Same,Below}
GetNewMappinID() : NewMappinID   GetEntityID() : EntityID      GetPhase() : gamedataMappinPhase   GetVariant() : gamedataMappinVariant
GetScriptData() : weak<MappinScriptData>    IsQuestImportant() const : Bool    IsQuestPath() : Bool
```
- `NewMappinID { import var value : Uint64 }` (`core/data/mappinData.script:25`). Usable as a stable key (compare `.value`). Persistent POI key: `PointOfInterestMappin.GetJournalPathHash()`.
- `MappinScriptData` (`mappinData.script:1`; just `statPoolType`); `GameplayRoleMappinData extends MappinScriptData` (`core/components/scriptComponents/gameplayRoleComponent.script:54`) is for in-world device/NPC role pins (not map markers).
- `IsVisible()`/`IsActive()` semantics not documented [inferred]: `IsActive` is the SetMappinActive flag (QuestMappin root visibility uses it, `WM:1795`); `IsVisible` = engine visibility; probe both.

### 2.2 Subclasses
- `QuestMappin extends IMappin` (`mappins.script:50`): `GetJournalPathHash() : Uint32`, `IsInsideTrigger()`, `IsUIAnimation()`, `GetUIAnimationRecordID() : TweakDBID`, `GetOwnerObjectMarkerVisibility()`.
- `PointOfInterestMappin extends IMappin` (`mappins.script:173`): `GetJournalPathHash() : Uint32`, `GetJournalQuestPathHash() : Uint32`, `GetCharacterRecordID() : TweakDBID` (fixers), `GetSlotName() : CName` (vehicle codex slot: used as `"codex/glossary/vehicles/" + slotName`, `WM:821-832`), `IsInsideSecurityAreaTrigger()`.
- `RuntimeMappin extends IMappin` (`mappins.script:59`): `EnableVisibilityThroughWalls`, `GetOwnerObjectMarkerPossibility`. Children: `InteractionMappin` (`GetIconRecordID`), `GrenadeMappin`, `VehicleMappin` (`GetVehicle() : weak<VehicleObject>`, `CanSeePlayer`...), `StealthMappin` (NPC detection; huge API, not map markers), `FastTravelMappin` (`GetPointData() : FastTravelPointData`), `RemotePlayerMappin`, `PingSystemMappin` (CPO).
- `StubMappin extends IMappin` (`GetStubMappinType() : gameStubMappinType {None,Police,PoliceVehicle,Vehicle}`, `mappins.script:8,150`).
- `FastTravelPointData` (`core/systems/fastTravelSystem.script:1`): `GetPointDisplayName()`, `GetPointDisplayDescription()`, `GetDistrictDisplayName()`, `IsSubway()`, `ShouldShowMappinOnWorldMap()`, `IsValid()`, `var mappinID : NewMappinID`.
- Class discrimination in script: `(QuestMappin)mappin` cast then null check (pattern used at `WM:1618-1634`), or `mappin.IsExactlyA('gamemappinsPointOfInterestMappin')` (`mappinsContainers.script:96`; native class names: `gamemappinsStealthMappin`, `gamemappinsStubMappin`, `gamemappinsRemotePlayerMappin`, `gamemappinsPingSystemMappin`, `gamemappinsInteractionMappin`).

### 2.3 Enums
- `gamedataMappinVariant` (`TDBE:154`, alphabetical, ~190 values incl. `Zzz*`; `Count`, `Invalid` at end). Map-relevant: `DefaultVariant, DefaultQuestVariant, QuestGiverVariant, ConversationVariant, ExclamationMarkVariant, MinorActivityVariant, Zzz06_NCPDGigVariant, GangWatchVariant, OutpostVariant, ResourceVariant, HiddenStashVariant, HuntForPsychoVariant, SmugglersDenVariant, WanderingMerchantVariant, ConvoyVariant, FixerVariant, DropboxVariant, ApartmentVariant, Zzz05_ApartmentToPurchaseVariant, ServicePoint*Variant (Bar, Clothes, Cyberware?, DropPoint, Food, Guns, Junk, Meds, MeleeTrainer, NetTrainer, Prostitute, Ripperdoc, Tech), Zzz14_ServicePointBlackMarketVariant, FastTravelVariant, Zzz17_NCARTVariant, VehicleVariant, Zzz03_MotorcycleVariant, Zzz01_CarForPurchaseVariant, Zzz02_MotorcycleForPurchaseVariant, CustomPositionVariant, TarotVariant, FailedCrossingVariant, Zzz09_CourierSandboxActivityVariant, Zzz12_WorldEncounterVariant, Zzz13_DogtownGateVariant, Zzz16_RelicDeviceBasic/SpecialVariant, Zzz18_RacingVariant, Zzz19_DelamainTaxiVariant, Zzz20_DelamainTaxiDestinationVariant, Zzz07_PlayerStashVariant, Zzz08_WardrobeVariant, DynamicEventVariant, GPSPortalVariant, GPSForcedPathVariant`.
  (`ServicePointCyberwareVariant` and `Zzz07/08` exist in the enum but have no entry in `MappinToTexturePart`, so they render 'invalid' or are not map pins.)
- `gamedataMappinPhase` (`TDBE:307`): `CompletedPhase, DefaultPhase, DiscoveredPhase, UndiscoveredPhase, Count, Invalid`.
  Semantics read from script: `UndiscoveredPhase` -> tooltip title "UI-MappinTypes-Undiscovered" / gig placeholder (`WMT:337-345`); `CompletedPhase` -> state `QuestComplete`, hidden unless tracked; `Discovered/Default` -> normal. Note `MappinToTexturePart(variant, phase)` ignores phase (`MU:53`): the "?" look for undiscovered is **not** a different texture part from script; it is a widget root state / native [inferred], see section 3.5.
- `gamedataWorldMapFilter` (`TDBE:4097`): `ApartmentToPurchaseFilter, AutofixerFilter, CommonFilter, Courier, CustomFilter, DogtownGateFilter, DropPoint, ExplorationFilter, FastTravel, Gigs, NoFilter, Outpost, PsychoFilter, Quest, RelicDeviceFilter, RipperdocFilter, ServicePoint, Story, TarotFilter, VehicleForSaleFilter, VendorFilter, Count, Invalid`.
- `gameJournalQuestType` (`JM:140`): `MainQuest, SideQuest, MinorQuest, StreetStory, CyberPsycho, Contract, VehicleQuest, ApartmentQuest, CourierQuest, CourierSideQuest`.

### 2.4 Quest/journal association (mapping a mappin to a JournalEntry)
`WM:1607-1636` (private to the menu, copy this logic):
```
GetMappinJournalPathHash(mappin) : Uint32 { QuestMappin -> .GetJournalPathHash(); PointOfInterestMappin -> .GetJournalPathHash(); else 0 }
GetMappinJournalEntry(mappin) : JournalEntry { hash != 0 ? journalManager.GetEntry(hash) : NULL }   // JournalManager.GetEntry( hash : Uint32 ) : weak<JournalEntry>, JM:410
```
The resulting entry is a `JournalQuestMapPin` (tooltip casts it, `WMT:329`); its parents: `GetParentEntry(mapPin)` -> `JournalQuestObjective` -> `JournalQuestPhase` -> `JournalQuest` (`WMT:330-341`).

---

## 3. Look (how a mappin widget is built)

### 3.1 What script tells us / does not
- The actual widget is `base\gameplay\gui\fullscreen\world_map\mappins\default_mappin.inkwidget` (`WM:1537`), and the player marker `...\player_mappin.inkwidget` (`WM:1543`). Their internals (atlas path, frame images, widget names, states, animations `OnNew`/`OnSelect`/`OnUnselect`) live in the `.inkwidget` resource, **not in these scripts**. No `.inkatlas` path appears anywhere in the script dump (rg -i inkatlas over mappin/map scripts: no hits). So: atlas resource path is **UNKNOWN from scripts**; must be extracted from the game archive with WolvenKit (inspect `default_mappin.inkwidget`, and `base\gameplay\gui\common\icons\mappin_icons.inkatlas` is the likely atlas [inferred from community knowledge, unverified]).
- Script DOES give: which texture-part name per variant, tint, root widget state name per group, and logic for selected/tracked/new.

### 3.2 Icon texture part
`MappinUIUtils.MappinToTexturePart` (`MU:48-58`, `MU:58-237`):
```
public static function MappinToTexturePart( mappin : weak< IMappin > ) : CName                                   // MU:48
public static function MappinToTexturePart( mappinVariant, mappinPhase ) : CName   // MU:53 -> ignores phase
public static function MappinToTexturePart( mappinVariant : gamedataMappinVariant ) : CName                      // MU:58 big switch
```
Applied by `inkImageRef.SetTexturePart( iconWidget, texturePart )` in `UpdateIcon` (`WM:1810-1830`). Mapping (variant -> part), complete from `MU:58-237`:
- quest-ish: Default, DefaultInteraction, ExclamationMark, GPSPortal -> `quest`; DefaultQuest -> `minor_quest`; Conversation, Speech -> `talk`
- gigs (`gigs`): QuestGiver, Retrieving, Thievery, Sabotage, ClientInDistress, BountyHunt, Courier, Convoy
- NCPD/bounty (`map_bounty`): MinorActivity, Zzz06_NCPDGig, GangWatch, Outpost, HiddenStash, Zzz04_PreventionVehicle
- other POIs: Resource `resource`; HuntForPsycho `hunt_for_psycho`; SmugglersDen `smugglers`; WanderingMerchant `wandering_merchant`; Fixer `fixer`; Dropbox/EffectDropPoint/ServicePointDropPoint `dropbox`; Apartment `apartment`; Zzz05_ApartmentToPurchase `apartment_to_buy`; FailedCrossing `failed_crossing`; Tarot `tarot_card`; Zzz09_CourierSandboxActivity `courier`; Zzz10_RemoteControlDriving `remote_control`; Zzz12_WorldEncounter `outpost`; Zzz13_DogtownGate `dogtown_gate`; Zzz16_RelicDeviceBasic `relic_access_point`; Zzz16_RelicDeviceSpecial `relic_dataterm`; Zzz17_NCART `fast_travel_metro`; Zzz18_Racing `racing`; Zzz19/Zzz20_Delamain* `delamain`; Zzz11_RoadBlockade `roadblock`; CustomPosition `dynamic_event` (the custom-waypoint icon); Invalid `invalid`
- service points: Clothes `clothes`; Food `food_vendor`; Bar `bar`; Guns `gun`; Zzz14_BlackMarket `black_market_vendor`; Meds `medicine`; MeleeTrainer `melee`; NetTrainer `netservice`; Prostitute `prostitute`; Ripperdoc `ripperdoc`; Tech `tech`; Junk `junk_shop`
- vehicles: Vehicle `car`; Zzz03_Motorcycle `motorcycle`; Zzz01_CarForPurchase `car_to_buy`; Zzz02_MotorcycleForPurchase `motorcycle_to_buy`; Grenade `grenade`
- FastTravel `fast_travel`
- interaction prompts (Sit, GetIn, Use, ... -> PascalCase parts) are not map markers.
- default -> `invalid`.

### 3.3 Colour / style
- `MappinUIUtils.MappinToColor( mappinVariant ) : CName` (`MU:239`): only `Zzz20_DelamainTaxiDestinationVariant` -> `'MainColors.Purple'`; everything else `''` (no explicit tint). Applied as `inkImageRef.Get(iconWidget).BindProperty('tintColor', color)` (`WM:1822`). Hence the **colour per type is driven by the widget root state**, not by tint.
- Root state: `ComputeRootState()` (`WM:1888-1919`), set by `UpdateRootState()` -> `GetRootWidget().SetState( state )` (`mappinsControllers.script:39-48`):
```
state = ''
if m_isCompletedPhase                        -> 'QuestComplete'
if variant == Zzz17_NCARTVariant             -> 'FastTravelMetro'     (note: written as if/else-if, so this overrides above)
else if variant == Zzz16_RelicDeviceBasicVariant -> 'Relic'
else if MappinsGroup record exists           -> mappinsGroup.WidgetState()     // TweakDB MappinsGroup.WidgetState : CName
if state == '' -> 'Quest'
```
  `MappinUtils.GetMappinsGroup( variant ) : weak<MappinsGroup_Record>` (`MU:5`, native); `MappinsGroup_Record` (`TDBR:5775`): `GroupName() : CName`, `WidgetState() : CName`, `Mappins(...)`. Group names seen in script: `'Quest'`, `'SecondaryQuest'` (`WM:1655`). The state names themselves ("Quest", "Gigs", "Default", "QuestComplete", "FastTravelMetro", "Relic") are style-state names that map to colours defined in the .inkwidget / `.inkstyle`; **the full `WidgetState` list and RGB values are not in scripts**: read at runtime via `MappinUtils.GetMappinsGroup(v).WidgetState()` for each variant (cheap, offline-able), and take colours from the inkstyle/widget (WolvenKit). Known colour semantics from the tracked-quest header: state `'Quest'` (quest colour) vs `'Gigs'` (`WM:432-441`).
- Other states used: `GetRootWidget().SetState('Default')` fallback (`mappinsControllers.script:44`); tooltip root states `Default/Quest/Gig/Fixer` (`WMT`); filter item states `Default/Hover/Selected` (`WM:2170`).

### 3.4 Frames/brackets/selection/tracked/new
- Tracked: `playerTrackedWidget : inkWidgetRef` (visible when `IsTracked()`, `WM:1824`) plus `m_taggedWidgets` (`mappinsControllers.script:15,50-77`, shown when profile `ShowTrackedIcon()` and tracked and not clamped); `m_animPlayerTrackedWidget` animation player.
- Selected / hover: library animations `OnSelect` / `OnUnselect` (`WM:1951-1975`); controller does `SelectMappin()` when `IsTracked()` (`WM:1796`), so tracked pins look "selected" permanently.
- New / unvisited: library animation `OnNew` when `!IsVisited()` (`WM:1832`). Visited is set by the menu via native `SetMappinVisited(controller)` (`WM:84,579`) on selection. A script-only equivalent is [not found]; `JournalManager.SetEntryVisited(entry, true)` exists for journal entries (`JM:415`). `IMappin.IsVisited()` is read-only.
- Fade in/out: `inkAnimTransparency` to opacity 0/1 with duration `m_fadeInOutDelay` (`WM:1921-1941`).
- Completed: root state `QuestComplete`, `MappinUIGlobalProfile_Record.CompletedPOIOpacity() : Float` (`TDBR:5685`, fetch `MappinUtils.GetGlobalProfile()`, `MU:3`).
- Undiscovered ("?" look): not a texture part (since `MappinToTexturePart` ignores phase). Tooltip title uses `UI-MappinTypes-Undiscovered`. How the widget draws it ('?' glyph or desaturated state) is in the .inkwidget [inferred: phase-driven state/visibility inside `default_mappin.inkwidget`]. Probe in WolvenKit.
- Frames/brackets per type: tooltip has "Police"/"Default"; no per-type bracket logic in scripts. Icon sizes: `WorldMapSettings.ZoomLevels[i].IconScale()` (`TDBR:11676`) scales icons per zoom level; `Free/TopDownCamera.IconScaleMin/Max` (`TDBR:11618-11643`).

### 3.5 Recipe to replicate with plain inkImage/inkText [inferred, minus the unknown atlas]
1. For each `IMappin m`: `part = MappinUIUtils.MappinToTexturePart(m)` (public static, callable from mod script); `state = group.WidgetState()` with `group = MappinUtils.GetMappinsGroup(m.GetVariant())` (public static). 
2. Create `inkImage` with atlas = the mappin atlas (find in `default_mappin.inkwidget` via WolvenKit), `SetTexturePart(part)`; tint by a table `state -> colour` that we copy from the game's style.
3. Tracked ring/overlay if `m.IsPlayerTracked()`; dim/hide if `phase == CompletedPhase`; "new" pulse if `!m.IsVisited()`.
4. For undiscovered, copy what the .inkwidget does (to be extracted).

---

## 4. Filters

- Mapping: `MappinUtils.GetFilterGroup( mappinVariant : gamedataMappinVariant ) : weak<MappinUIFilterGroup_Record>` and `GetFilterGroup( filter : gamedataWorldMapFilter )` (`MU:9-19`; backed by private natives `GetFilterGroupFromVariant/GetFilterGroupFromFilter`, `MU:6-7`; both public static wrappers callable from mod script). 
- `MappinUIFilterGroup_Record` (`TDBR:5672`): `FilterType() : weak<WorldMapFilter_Record>` (`.Type() : gamedataWorldMapFilter`, `.EnumName()`, `TDBR:11590s`), `FilterName() : CName` (localization key, rendered with `inkTextRef.SetLocalizedTextScript( ref, filterGroup.FilterName() )`, `WM:296,2178`), `Mappins(out array<weak<MappinVariant_Record>>)`, `GetMappinsCount/GetMappinsItem(i)` (`MappinVariant_Record.Type() : gamedataMappinVariant`), `MappinsContains`, `ShouldCollectMappins() : Bool` (collection/group clustering flag).
- Quick filters (the left/right arrow cycle): TweakDB list `T"WorldMap.WorldMapQuickFiltersList"` -> `TweakDBInterface.GetWorldMapFiltersListRecord(...)` cast `WorldMapFiltersList_Record` (`WM:237-240`); iterate `GetListCount()` / `GetListItem(i) : weak<MappinUIFilterGroup_Record>` (`TDBR:11609-11616`). Order = TweakDB list order [display order is the same list: `InitializeQuickFiltersList`, `WM:232-265`]; wraps around with `CycleQuickFilterPrev/Next` (`WM:687-698`) [not read in detail]. Exact names/order list is TweakDB data, **not in scripts**: dump at runtime (section 9). `gamedataWorldMapFilter.NoFilter` = "show everything"/no-filter state (selector 'Default'), any other = selector state 'Selected' (`WM:312-323`); `CustomFilter` quick filter reveals the custom checklist.
- Custom filters (checklist): `T"WorldMap.WorldMapCustomFiltersList"` (`WM:337`), same record type; item = `WorldMapFiltersListItem` (`WM:2089`): checker widget, name `inkTextRef.SetLocalizedTextScript(m_filterName, filterGroup.FilterName())`, states `Default/Hover/Selected`.
- State storage: **native**, on the menu controller: `GetQuickFilter()/SetQuickFilter(filter)/SetQuickFilterFromRecord(group)`, `HasCustomFilter/GetCustomFilters() : Uint32 bitmask/SetCustomFilter/ClearCustomFilter`, `SaveFilters()` (called in `OnUninitialize` unless fast-travel, `WM:67-73,208-212`). All `protected import` on `WorldMapMenuGameController`. Persistence lives in engine, not accessible from script outside the menu. NightMap should keep its own filter state (quick-filter index + custom bitset), likely persisted by our own mod settings/persistent field; initialise from the same TweakDB lists. Filter-by-variant test on our side: `MappinUtils.GetFilterGroup(m.GetVariant()).FilterType().Type()` compared against the active filter(s) and `quickGroup.MappinsContains(...)`/`GetMappinsItem(i).Type()`.
- Zoom-level filtering (separate from quick filters) uses `WorldMapZoomLevel_Record.MappinFilterGroups` (section 1.4).

---

## 5. Tracking

### 5.1 In the vanilla menu (`WM:935-1011 TryTrackQuestOrSetWaypoint`)
Decision: `CanQuestTrackMappin(mappin)` = mappin has a journal entry AND its `MappinsGroup.GroupName()` is `'Quest'` or `'SecondaryQuest'` and variant != `Zzz18_RacingVariant` (`WM:1638-1660`). 
- Quest-trackable and not already tracked: `UntrackCustomPositionMappin(); TrackQuestMappin(controller)`:
```
private function TrackQuestMappin( controller : BaseMappinBaseController )   // WM:998
{   journalEntry = GetMappinJournalEntry( controller.GetMappin() );  if( journalEntry == NULL ) return;
    m_journalManager.TrackEntry( journalEntry ); }
```
- Not quest-trackable (`CanPlayerTrackMappin = !CanQuestTrackMappin`): toggles: if `IsCustomPositionTracked()` -> `UntrackCustomPositionMappin()`; else `UntrackCustomPositionMappin(); TrackMappin( selectedMappin )`.
- Nothing selected (clicking empty map): `TrackCustomPositionMappin()` (places/sets the custom waypoint at the cursor position, native).
- Note a vanilla bug: `IsMappinQuestTracked` (`WM:1671`) discards `IsEntryTracked` result and always returns false.

### 5.2 Native signatures (all `protected import` on `WorldMapMenuGameController`, `WM:75-82`)
```
TrackMappin( mappinController : BaseMappinBaseController )   UntrackMappin()
TrackCustomPositionMappin()   UntrackCustomPositionMappin()   TrackDelamainTaxiMappin()   UntrackDelamainTaxiMappin()
ConfirmDelamainTaxiMappinPosition()  CancelDelamainTaxiMappinPosition()
```
These take the cursor position / selected widget internally; they exist only on the menu controller and are `protected`, so **not callable from NightMap** (not even via `@wrapMethod` unless we have an instance of that menu running).

### 5.3 What IS callable from script outside the menu
- Quest tracking: `JournalManager.TrackEntry( entry : weak<JournalEntry> )`, `UntrackEntry()`, `IsEntryTracked(entry) : Bool`, `GetTrackedEntry() : weak<JournalEntry>`, `TrackPrevNextEntry(next : Bool)` (`JM:418-422`). `GameInstance.GetJournalManager(game)`. This fully covers "track quest from a quest mappin" (entry from `GetEntry(questMappin.GetJournalPathHash())`; vanilla tracks the **JournalQuestMapPin** entry, not the objective directly).
- Non-quest tracking: `MappinSystem.UntrackMappin()` (`MS:46`, used in `autoDriveSystem.script:377`), `GetManuallyTrackedMappinID() : NewMappinID` (`MS:44`), `SetMappinTrackingAlternative(id, targetId)` (`MS:45`). **There is no `TrackMappin(IMappin)` on MappinSystem** in these scripts. Hence "track a non-quest mappin" has no direct script API; options: [inferred] (a) register our own runtime mappin and treat as custom waypoint, (b) emulate by custom waypoint at the mappin position.
- Custom waypoint from script (the vanilla one is native in the menu): `MappinSystem.RegisterMappin( data : MappinData, position : Vector4 ) : NewMappinID` (`MS:25`) with `MappinData{ mappinType : TweakDBID; variant = gamedataMappinVariant.CustomPositionVariant; active = true; visibleThroughWalls; ... }` (`mappinData.script:15-23`), clear with `UnregisterMappin(id)`, move with `SetMappinPosition(id, pos)` (`MS:21`). Existing precedent: `autoDriveSystem.script:373-376` treats the *manually tracked* mappin as CustomPositionVariant and unregisters it by `GetManuallyTrackedMappinID()`; so clearing a vanilla waypoint from script works: `if( ms.GetMappin( ms.GetManuallyTrackedMappinID() ).GetVariant() == CustomPositionVariant ) ms.UnregisterMappin( ms.GetManuallyTrackedMappinID() )`. 
  - `mappinType` TweakDBID for the custom pin is **unknown** (no `T"Mappins.<CustomPosition...>"` in scripts; only `Mappins.InteractionMappinDefinition` and `Mappins.DropPointStaticMappin` appear). Needs a runtime probe: read the tracked custom pin's `GetScriptData()`/definition, or guess `T"Mappins.CustomPositionMappinDefinition"` [guess].
  - Whether a script-registered CustomPositionVariant mappin becomes the "tracked" (GPS route / minimap) one is unverified: minimap has special-case for `CustomPositionVariant` (`minimap.script:476`). Registering does not by itself set tracked state (there is no script `TrackMappin(id)`); [inferred] it will show as a pin but not draw the GPS path. Probe in game.
- Delamain Taxi: separate `DelamainTaxiSystem` (ignore).

---

## 6. Tracked-quest header (`WM:411-452 UpdateTrackedQuest`; the same logic in `cyberpunk/UI/quests/quest_tracker.script:228-262`)

```
journalManager = GameInstance.GetJournalManager( game );                                  // WM:174
m_trackedObjective = (JournalQuestObjectiveBase) journalManager.GetTrackedEntry();           // JM:418  weak<JournalEntry>
objective text  = m_trackedObjective.GetDescription();                                       // JM:89  JournalQuestObjectiveBase.GetDescription() : String (already localized)
phase           = (JournalQuestPhase) journalManager.GetParentEntry( objective );            // JM:409
quest           = (JournalQuest)      journalManager.GetParentEntry( phase );
quest title     = quest.GetTitle( journalManager );                                          // JM:156  JournalQuest.GetTitle( IJournalManager ) : String
questType       = journalManager.GetQuestType( quest );                                      // JM:432  gameJournalQuestType
isQuestType     = questType in { MainQuest, SideQuest, CourierSideQuest, MinorQuest }        // else (Contract/gig/NCPD/etc.) -> 'Gigs' style
title text state = isQuestType ? 'Quest' : 'Gigs'   (applied to title inkText and to objective frame widget)
objective positions on map = mappinSystem.GetQuestMappinPositionsByObjective( (Uint32) journalManager.GetEntryHash( objective ), out array<Vector3> )   // MS:37, JM:417
```
- Counters: `journalManager.GetObjectiveCurrentCounter(obj)/GetObjectiveTotalCounter(obj)` (`JM:426-427`, `JournalQuestObjectiveBase.HasCounter()` `JM:90`); optional: `GetIsObjectiveOptional(obj)` (`JM:433`); `GetRecommendedLevel(entry)` (`JM:430`).
- Strings returned are already localized (no `GetLocalizedText` call), so just use them in `inkText`.
- Change notification: `journalManager.RegisterScriptCallback( this, 'OnTrackedEntryChanges', gameJournalListenerType.Tracked )` with handler `protected event OnTrackedEntryChanges( hash : Uint32, className : CName, notifyOption : JournalNotifyOption, changeType : JournalChangeType )` (`WM:394`, `quest_tracker.script:38,103`; enum `cyberpunk/UI/quests/journalTypes.script:10`: `State, Visited, Tracked, Untracked, Counter, StateDelay, ObjectiveOptional, ChoiceEntry`). Also `OnStateChanges` (State) and `OnCounterChanged` (Counter) as in quest_tracker (`quest_tracker.script:37-40`). `UnregisterScriptCallback(obj, fn)` (`JM:438`).
- Tracked non-quest mappin (e.g. custom waypoint): `UI_System.TrackedMappin` blackboard variant -> `IMappin` (section 8); header text from `MappinUIUtils.MappinToString(variant)` + `MappinToObjectiveString(variant)` (`quest_tracker.script:182-191`).
- Quest-colour state names: 'Quest' / 'Gigs' (see 3.3).

---

## 7. Tooltip content (`WMT:235-760 WorldMapTooltipController.SetData`)

Input struct `WorldMapTooltipData` (`WMT:1-17`): `controller, mappin, journalEntry, fastTravelEnabled, delamainTaxiEnabled, travelCost, playerMoney, readJournal, moreInfo, isCollection`. Built in `WM:1447 UpdateTooltip`: `journalEntry = GetMappinJournalEntry(mappin)`, `readJournal = CanOpenJournalForMappin`, `moreInfo = CanOpenCodexPopup` (vehicle POIs with a `codex/glossary/vehicles/<slot>` entry), `isCollection = controller.IsCollection()`.
Fields shown: title (`m_titleText`), description (`m_descText`), warning (`m_warningText`), additional desc, icons (`m_icon`, `m_fixerIcon`, `m_ep1Icon`, `m_linkImage` preview image), threat level panel, fixer progress bar, travel cost, input hints. Resolution order:
1. **VehicleMappin**: title = `vehicleObject.GetDisplayName()`, desc = `UI-MappinTypes-PersonalVehicleDescription` (if unlocked, `IsVehicleUnlocked` `WMT:667`), else fallback `UI-MappinTypes-PersonalVehicle`.
2. **FastTravelMappin**: title = `pointData.GetPointDisplayName()` (or `UI-MappinTypes-FastTravelDescription` when grouped as a collection), desc = `UI-MappinTypes-FastTravel`; interact hint if fast travel enabled. District: `pointData.GetDistrictDisplayName()` exists but is not used by the tooltip.
3. **Undiscovered + gig variants** (`QuestGiver, Retrieving, HuntForPsycho, Thievery, Sabotage, ClientInDistress, Courier, Zzz09_CourierSandboxActivity, BountyHunt, Convoy, Zzz02_MotorcycleForPurchase, Zzz06_NCPDGig, Zzz05_ApartmentToPurchase, Zzz12_WorldEncounter`, `WMT:308-312`): title `UI-MappinTypes-Gig`, desc `UI-MappinTypes-GigDescription`. Other undiscovered: title `UI-MappinTypes-Undiscovered`, no desc.
4. **Discovered with journal entry** (cast `JournalQuestMapPin`): objective -> phase -> quest chain; title = `quest.GetTitle(jm)`, desc = `objective.GetDescription()`, tooltip root state `Quest`; gig variants: fixer icon via `QuestLogUtils.GetFixerData(jm, objective)` -> `UIIcon_Record.AtlasPartName()`; root state `Gig` for gig group.
5. Special variants: `FixerVariant` -> `MappinUIUtils.GetFixerVariantData(questSystem, mappin)` (`MU:415`: `TweakDBInterface.GetCharacterRecord(poi.GetCharacterRecordID()).FullDisplayName()`, tooltip avatar, `amountOfQuests`, `factCounterName` fact via `GameInstance.GetQuestsSystem(game).GetFact`, progress bar; state `Fixer`); `Zzz01/02_*ForPurchase` -> `VehicleOffer_Record` (price `€$N`, preview image); `Zzz05_ApartmentToPurchase` -> `PurchaseOffer_Record`; `ServicePointRipperdoc` -> `RipperdocMappin_Record` via `TDBID.Create("Mappins." + journalEntry.GetId())` (name, atlas part); `Zzz18_Racing` -> `RacingMappin_Record` Title/Description; `Zzz20_DelamainTaxiDestination` -> cost/warning; `Zzz09_CourierSandboxActivity` -> fact `CourierDiscovered` selects locale keys.
6. Fallbacks: title empty -> `MappinUIUtils.MappinToString(variant, phase)` (`MU:250-414`, locale keys `UI-MappinTypes-<Name>`, e.g. `ServicePointFood -> UI-MappinTypes-FoodServicePoint`, `Fixer -> UI-MappinTypes-Fixer`, `FastTravel -> UI-MappinTypes-FastTravel`, `CustomPosition -> UI-MappinTypes-CustomLocation`, `Zzz17_NCART -> UI-Ncart-ncart_mappin_name`); desc empty -> `MappinUIUtils.MappinToDescriptionString(variant)` (`MU:474-631`, `UI-MappinTypes-<Name>Description`, `...-Description` for interaction ones; service-point food/clothes/guns/meds/melee/bar and Fixer are empty ''). Both public static, return CName locale keys -> `GetLocalizedTextByKey(cname)` / `GetLocalizedText(string)` / `inkTextRef.SetLocalizedTextScript`. `MappinToObjectiveString(variant)` (`MU:632`) only for NCPD/PSycho/Smuggler/Stash/Outpost/Resource/FailedCrossing/CustomPosition/Tarot.
7. Level/danger: `recommendedLvl = journalManager.GetRecommendedLevel(entry)`; overridden by `ContentAssignment_Record.PowerLevelMod()` curve (`StatsDataSystem.GetValueFromCurve`) or `LevelAssignmentSystem.GetLevelAssignment(contentID)`; `levelState = QuestLogUtils.GetLevelState(playerLevel, recommendedLvl)`; show threat panel only for `'ThreatHigh'` -> `UI-Tooltips-ThreatHigh`, `'ThreatVeryHigh'` -> `UI-Tooltips-ThreatVeryHigh` (`WMT:488-528`). Player level: `StatsSystem.GetStatValue(player.GetEntityID(), gamedataStatType.Level)`.
8. EP1 badge: `journalManager.IsEp1Entry(entry)` (`JM:416`).
9. Police tooltip (`WorldMapPoliceTooltipController`, `WMT:783`) used for variants `GangWatch, Outpost, Resource, HiddenStash, SmugglersDen, FailedCrossing` (`WM:1331-1357 IsPoliceTooltip`): title `UI-MappinTypes-Undiscovered` if undiscovered, else quest/variant names + recommended level threat.
- Distance: **not shown** in world-map tooltip. `IMappin.GetDistanceToPlayer()` is available if we want it.
- Raw `IMappin.GetDisplayName() : String` exists (`mappins.script:32`); the map tooltip does not use it (it builds titles from quest/variant). Usefulness unknown; probe.

---

## 8. Change notification

No script-side "mappin added/removed" listener exists in these sources. What exists:
- `JournalManager.RegisterScriptCallback(obj, fn, gameJournalListenerType.{State|Visited|Tracked|Untracked|Counter|StateDelay|ObjectiveOptional|ChoiceEntry})` (`JM:437`): quest-state changes (new/finished objectives) drive quest-mappin churn. Handler signature `(hash : Uint32, className : CName, notifyOption : JournalNotifyOption, changeType : JournalChangeType)`.
- Blackboard `UI_System.TrackedMappin : BlackboardID_Variant` (`core/blackboard/blackboardDefinitions.script:595`): variant holding the tracked `IMappin`. Listener: `blackboard = GetBlackboardSystem().Get( GetAllBlackboardDefs().UI_System ); id = blackboard.RegisterListenerVariant( bb.TrackedMappin, this, 'OnTrackedMappinUpdated' )`, handler `OnTrackedMappinUpdated( value : Variant )` with `m_currentMappin = ( ( weak< weak< IMappin > > )( ( ( IScriptable )value ) ) )` (`quest_tracker.script:44,167-169`; also `RegisterDelayedListenerVariant`, `journalNotification.script:160,201`). Fires for custom waypoint / manually tracked non-quest mappins as well [inferred].
- `UI_Map` blackboard (`blackboardDefinitions.script:1515`): `currentLocation`, `currentLocationEnumName`, `newLocationDiscovered : Bool`, `currentState`, `minimapLayerHighlightRequest` (not mappin lists; `newLocationDiscovered` is a district discovery signal).
- Menu-level events (only while our own UI would be the host; not delivered to us): `OnFiltersChanged` (native, per mappin controller), `OnCustomFilterChanged`, `OnZoomLevelChanged`.
- Fast travel: `FastTravelSystem` registers/unregisters its mappins itself (`fastTravelSystem.script:589,599`); no event.
- Conclusion: **no push for add/remove/phase-change of arbitrary mappins in script**. Practical approach [inferred]: poll `GetMappins(Map, out arr)` on a low-frequency timer (e.g. on map open, on `Tracked`/`State` journal callbacks, and every N seconds while the overlay is open) and diff by `NewMappinID.value`, `GetPhase()`, `IsActive()`, `IsVisited()`, `IsPlayerTracked()`, position. Combine with the journal callbacks and TrackedMappin blackboard for immediate refresh. Player position updates are separate (not a mappin).
- Static POIs change (discover) via journal/state changes and mappin phase; also `GetPointOfInterestMappinSavedState(hash,...)` for offline state. The vanilla "new" tag comes from `IsVisited()`.

---

## 9. Unknowns to probe in-game

Write a debug-only probe (log via `FTLog`/`LogChannel`) triggered by a hotkey. Items that can only be learned at runtime:
1. `GetMappins(gamemappinsMappinTargetType.Map, arr)`: size; same for `World`, `Minimap`. Do all three differ? Are static POIs (fixers, service points, gigs "?", NCPD "?", cyberpsycho, drop points, vehicles for purchase, apartments, tarot, fast travel, NCART) in `Map`? Do they depend on the world map ever having been opened (lazy creation) or on the loaded district/streaming?
2. Histogram per `GetVariant()` x `GetPhase()` x class name (`IsExactlyA` for `gamemappinsPointOfInterestMappin/QuestMappin/FastTravelMappin/InteractionMappin/RuntimeMappin/StealthMappin/StubMappin/VehicleMappin`) for each target type, so we know which classes must be skipped (Stealth/Stub/Interaction/Grenade/gameplay-role devices will pollute `World`/`Minimap`).
3. For each mappin: `IsVisible()` vs `IsActive()` vs `IsStatic()` vs `IsVisited()` values and how they correlate with what vanilla shows. Does `IsVisible()` mean "visible on map"?
4. `GetDisplayName()` content (empty? localized?), `GetEntityID()` validity for POIs, `GetWorldPosition()` Z for interiors.
5. Do undiscovered POIs appear in the list at all with `UndiscoveredPhase`, and does `IsActive()` hide them like `QuestMappin`? Is the vanilla "gig '?'" a Variant (QuestGiver etc.) + `UndiscoveredPhase`?
6. Completed-phase POIs: present in list? (Vanilla hides unless tracked.)
7. Distance/zoom: NCPD events visibility range (`WorldMapSettings.NCPDEventsVisibilityRange`) and the actual per-zoom-level filter-group lists. Dump via TweakDB: find the WorldMapSettings record ID, then `GetZoomLevelsCount()`, per level `MappinFilterGroups`.
8. Quick-filter list: dump `TweakDBInterface.GetWorldMapFiltersListRecord(T"WorldMap.WorldMapQuickFiltersList")` items: `FilterName()` loc keys, `FilterType().Type()`, `GetMappinsCount()` and members; the same for `WorldMap.WorldMapCustomFiltersList`; localized display names via `GetLocalizedTextByKey(FilterName())`.
9. For every variant in the enum: `MappinUtils.GetMappinsGroup(v)` -> `GroupName()` + `WidgetState()` (the colour/state table); `MappinUtils.GetFilterGroup(v)` -> filter type. Also `MappinUIGlobalProfile.CompletedPOIOpacity()`.
10. Tracking: (a) does `JournalManager.TrackEntry(GetEntry(questMappin.GetJournalPathHash()))` track correctly from our overlay (it is what vanilla does), (b) after `RegisterMappin(CustomPositionVariant, ...)` with a guessed `mappinType`, does `GetManuallyTrackedMappinID()` become that ID, and does the route/minimap show it? (c) find the real TweakDB `mappinType` for the vanilla custom waypoint (read `GetScriptData()`/inspect the mappin that appears after setting a waypoint in the vanilla map); (d) is a non-quest, non-custom mappin trackable by any script call (`SetMappinTrackingAlternative`?).
11. Does `TrackedMappin` blackboard fire when vanilla map sets/clears the custom waypoint, and with what value?
12. Mappin atlas path, texture-part names present in it, frame/bracket/"?" element names, root states and their colours: **not in scripts**; extract from `default_mappin.inkwidget` (WolvenKit: `base\gameplay\gui\fullscreen\world_map\mappins\default_mappin.inkwidget`) and the inkstyle; verify each `MappinToTexturePart` result exists as a part in that atlas (`inkImageRef.IsTexturePartExist`, used in `mappinsContainers.script:43`).
13. Whether `IMappin` references stay valid across frames (weak<IMappin>); safe to cache by `NewMappinID` and re-resolve with `GetMappin(id)` instead.
14. Perf: cost of `GetMappins(Map)` per call (hundreds of POIs); decide poll interval.
