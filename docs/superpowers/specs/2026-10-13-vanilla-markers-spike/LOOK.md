# Vanilla world-map mappin look (extracted from basegame_1_engine.archive, EP1 does not override)

All paths are inside the game archive unless marked `LOCAL`. Local dir: `~/nightmap/.scratch/markers_spike/look/`.
Raw dumps: `raw/js/*.json` (WolvenKit CR2W->JSON), `raw/png/*.png` (decoded textures), trees `tree_*.txt`, resolved styles `styles_resolved.txt`, parts `atlas_parts.tsv` / `atlas_parts.json` (name -> x,y,x2,y2 px box in the 1120x792 4K atlas), contact sheet `atlas_parts.png`, mock `look_mock.png`.

Colour convention: ink HDRColor channel values are used as `value*255` (1.0 = 255, values above 1.0 are HDR boost). Hex below is the clamped value (e.g. MainColors.Red 1.176,0.381,0.348 = #FF6159, matches the known game colour). Real in-game bloom/HDR brightness is NOT reproduced by the clamped hex.

## 1. The widget: `base\gameplay\gui\fullscreen\world_map\mappins\default_mappin.inkwidget`

Verified path. It is the ONLY mappin widget the world map spawns (`worldMap.script:1538`) apart from `player_mappin.inkwidget` (`:1543`). rootResolution = UltraHD_3840_2160. Controller: `gameuiBaseWorldMapMappinController` (native class), `fadeInOutDelay=0.3`, `iconWidget -> "icon"`, `canvasWidgetName="Canvas"`, `arrowWidgetName="Arrow"`. All other widget refs (playerTrackedWidget, taggedWidgets, groupContainerWidget, groupCountTextWidget, scaleWidget, animPlayer*) are null.

Tree (units = ink units in the 3840x2160 root space; 1 unit = 1 px at 4K):

```
Root [inkCanvas] 80x80, anchor TopLeft, state Default (set at runtime), style=base\gameplay\gui\common\mappins.inkstyle
|   propertyBinding: tintColor <- MainColors.ActiveYellow (unused by children)
+- shadow2 [inkImage] size 32x32 (fitToContent=1), anchor Fill, margin L/T/R/B = -100, center/center,
|    renderTransform scale 0.5 (pivot .5,.5), tint black (0,0,0,1) op 1
|    atlas base\gameplay\gui\common\shadow_blobs.inkatlas part shadowBlobSquare_big (282x282 px soft round blob, alpha peak ~215/255)
+- Canvas [inkCanvas] size 0x0, anchor Centered, fill
|  +- icon [inkImage] size 2x2 (fitToContent=1 -> uses part size), anchor Centered, center/center, margin 0, opacity 0.5 (bound, see below)
|       atlas base\gameplay\gui\common\icons\mappin_icons.inkatlas, part = MappinToTexturePart result (design-time default "quest")
|       tint default (1.37,0.444,0.405) = ActiveRed, then style bindings:
|         tintColor <- Mappin.IconColor ; opacity <- Mappin.Opacity
+- Arrow [inkCanvas] 10x10, Centered     (edge-clamp arrow, shown when the pin is clamped to the map edge)
   +- arrowimage_3dmap [inkImage] size 0x0 fit, margin B=50, mirror=Both, tint bound Mappin.IconColor
        atlas base\gameplay\gui\widgets\mappins\atlas_map_pins.inkatlas part interaction (18x10 px at 4K)
```

What is NOT in the widget (important for replication):
- No frame/bracket/ring image, no "?" glyph element, no tracked indicator, no selection/hover ring, no completed overlay, no text. Every state is expressed by (a) the icon part, (b) tint via root state, (c) opacity, (d) scale animation. "Tracked" = the controller calls SelectMappin() (plays OnSelect, stays at opacity 1 / scale 1.3). `playerTrackedWidget` and `taggedWidgets` are unbound in this widget.
- The "?" look is a texture part (see 3 and 5), not a separate element. The "undiscovered" part exists in the atlas but no script maps a variant to it, so which variant/phase draws a "?" is UNCERTAIN (candidates: `minor_activity` boxed ?, `hidden_stash` hex ?, `undiscovered` plain ?). `MappinToTexturePart(variant, phase)` ignores the phase.
- Opacity: icon is 0.5 (Mappin.Opacity = 0.5 in Default/Quest/ServicePoint/FastTravel/Story/Vehicle states; `FastTravelMetro` = 1.0; `Player` and others unspecified -> inherit Default 0.5 presumably). Mappin.IconOpacity (1.0, 0.8 in ShardRead) is defined but nothing binds it here.
- Animations: library `base\gameplay\gui\fullscreen\world_map\mappins\default_mappin_animations.inkanim` (5 sequences, targets are unnamed handles; apply to icon + canvas):
  - `OnSelect`: scale 1 -> 1.3 (0.116 s, delay 0.029, EasyInOut Quadratic) and 0.077 s on the second target; opacity 0.5 -> 1 (0.083 s, delay 0.062, EasyIn Linear).
  - `OnUnselect`: scale 1.3 -> 1 (0.078 s, delay 0.041 / 0.059 s) ; opacity 1 -> 0.5 (0.116 s, EasyIn Linear).
  - `OnNew` (unvisited pin attention pulse, ~5.6 s): 3 repeating pulses at t = 0.7 / 2.5 / 4.3 s: opacity 0.5 -> 1 (0.4 s) then 1 -> 0.5 (0.9 s) and scale 1 -> 1.2 (0.4 s) -> 1 (0.9 s); a second target pulses 0.5 -> 0.8/0.9 and scale 1 -> 1.15 at t = 0.85 / 2.15 / 3.45 s (0.15 s up, 0.9 s down) like a halo.
  - `OnCollectionCountChange`: scale 1 -> 1.25 (0.25 s) -> 1 (0.25 s). `OnCollectionClear`: scale 1 -> 1.25 (0.1 s) -> 0 (0.15 s).
- Script-side fades (not in the widget): `PlayFadeAnimation` transparency 0/1 over 0.3 s (filter/zoom visibility); completed POIs use `MappinUIGlobalProfile.CompletedPOIOpacity()` (value not extracted).
- Zoom scaling: `WorldMapSettings.ZoomLevels[i].IconScale()` multiplies the whole pin (values not extracted).

Icon pixel size: part size at the 4K slot = 64x64 (one part 64x63). `mappin_icons_1080p.xbm` and `_720p.xbm` are lower-res variants of the same atlas (same part UVs, so ~32px and ~21px); the engine picks the slot by UI resolution. Visual size in the default 4K-reference space: 64 units, i.e. 1.67 % of screen width. Exact on-screen px at other resolutions UNCERTAIN.

## 2. Styles / states

Root style `base\gameplay\gui\common\mappins.inkstyle` (imports `main_colors.inkstyle`, `rarity_hud.inkstyle`; no themes inside; main_colors has 10 colour themes e.g. Johnny, ColorBlind*, which would recolour pins). Style id `Mappin`, properties `Mappin.IconColor`, `Mappin.AreaColor`, `Mappin.Opacity`, `Mappin.IconOpacity`. The root's state name (set by script `SetState(...)`) selects the row. Missing properties fall back to Default (0.5 opacity). Full dump with raw floats: `styles_resolved.txt`.

States relevant to world-map pins (IconColor; Opacity):
| state | colour source | hex | opacity |
|---|---|---|---|
| Default | MainColors.ActiveRed | #FF7167 | 0.5 |
| Quest (also script fallback when WidgetState is empty) | MainColors.ActiveYellow | #FFFF4E | 0.5 |
| Gigs | MainColors.StreetCred | #00FFD5 | (0.5) |
| QuestComplete | literal | #6B6C6C | (0.5) |
| QuestUntracked | MainColors.DarkGold | #D85912 | (0.5) |
| Story | MainColors.Blue | #5EF6FF | 0.5 |
| ServicePoint | MainColors.White | #FFFFFF | 0.5 |
| Vehicle / VehicleForPurchase | MainColors.White | #FFFFFF | 0.5 |
| FastTravel | MainColors.StrongFastTravel | #59B4FF (raw 0.35,0.707,1.414) | 0.5 |
| FastTravelMetro (Zzz17_NCART) | literal | #CC81FF (raw 0.8,0.505,1.5) | 1.0 |
| Relic (Zzz16_RelicDeviceBasic) | MainColors.RelicColor | #78ADFF | (0.5) |
| Player (player_mappin only) | MainColors.ActiveGreen | #29FFB9 | (0.5; player widget has its own tint) |
| PlayerTracked | MainColors.DamageTypeChemical_Critical | #04FF52 | - |
| InteractionDefault / Autodrive / RemoteControlDriving | ActiveBlue | #28FFFF | 0.5 |
| Inactive / Unavailable | MainColors.Grey | #A09A96 | - |
| Impossible / Available | ActiveRed | #FF7167 | - |
| Shard / ShardRead | literal / DarkGrey | #FFFDE3 / #757575 (IconOpacity 0.8) | - |
| rarity states Common..Legendary, Iconic | RarityColor.Strong* | #FFFAFA #0AFFC0 #92F5FF #FFC0FF #FF853B #FFFF73 | - |
(grenade/explosion/distraction states exist for the 3D world mappins, not map pins.) All alpha = 1.00. Tint is set by `Mappin.IconColor`; `MappinToColor()` only overrides to `MainColors.Purple` for Delamain taxi destination.

Variant -> state: from `MappinsGroup.WidgetState()` in TweakDB (`MappinUtils.GetMappinsGroup(variant).WidgetState()`, `worldMap.script:1888-1919`); `QuestComplete` if phase Completed, `FastTravelMetro` for NCART, `Relic` for relic device. The per-group WidgetState values live in `r6\cache\tweakdb.bin` and were NOT extracted (not parsed offline). Inferred (unverified) assignment from state names: quest groups -> Quest; gig variants -> Gigs; NCPD/minor activity/bounty/hidden stash/etc. -> Default (red); service points (vendors, ripperdoc, clothes...) -> ServicePoint (white); vehicles -> Vehicle; FastTravel -> FastTravel; Story groups -> Story. The existing probe (`probe/NightMapProbe/Util.reds:41`) can dump the real group/state per variant in game; do that to confirm.

## 3. Icon atlas

- Atlas: `base\gameplay\gui\common\icons\mappin_icons.inkatlas` (3 slots, same 201 part names). Textures: `mappin_icons.xbm` 1120x792 (4K slot, BC7), `mappin_icons_1080p.xbm`, `mappin_icons_720p.xbm`. Parts are white-on-alpha glyphs, recoloured by tint.
- 201 parts, 200 are 64x64 and `fast_travel_metro` is 64x63. Full list with px rects: `atlas_parts.tsv`; eyeball sheet: `atlas_parts.png` (every part cropped, labelled name + WxH). The non-map ones (lifepaths, loot_*, grenades, interaction verbs like Sit/GetIn) are also in the atlas.
- Decoding gotcha: the .xbm data is bottom-up (vertically flipped) relative to the inkatlas UVs; script `xbm2png.py` flips it. Textures decoded by building a DX10/BC7 DDS around the blob (`WolvenKit.CLI export` fails on this machine: DirectXTexNet native init error). UV to px: x=Left*1120, y=Top*792.
- Map-relevant parts (all 64x64): quest (circle "!"), minor_quest (circle "!" outline), talk (speech bubble), quest_giver (person with "!"), quest_excmark ("!"), gigs ("!" on a page), map_bounty (NCPD badge), minor_activity (boxed "?"), hidden_stash (hex "?"), undiscovered (bare "?"), completed (circle with check), verified (boxed check), failed (boxed X), street_story, metaquest, clue, fast_travel (pin with hex), fast_travel_unactive (pin outline), fast_travel_metro (purple "M" hex, 64x63), fixer (handshake), vendor_owned, car, motorcycle, car_to_buy, motorcycle_to_buy, apartment, apartment_to_buy, ripperdoc, clothes, food_vendor, bar, gun, tech, junk_shop, medicine, melee, netservice, prostitute, black_market_vendor, dropbox, resource, smugglers, wandering_merchant, outpost, racing, delamain, relic_access_point, dogtown_gate, tarot_card, shard, remote_control, dynamic_event, custom_position, invalid (pink INVALID checker).
- `MappinToTexturePart` results that do NOT exist in the atlas: `failed_crossing`, `relic_dataterm` (engine falls back / uses invalid). All other parts named in RESEARCH 3.2 exist.
- Other textures used by the map pin: `base\gameplay\gui\common\shadow_blobs.inkatlas` (`shadow_blobs.xbm`, 944x656 BC3; shadowBlobSquare_big = 282x282 at (655,1)); `base\gameplay\gui\widgets\mappins\atlas_map_pins.inkatlas` (`atlas_map_pins.xbm` 264x256; `interaction` 18x10 edge arrow, `tagged_left` 14x24, `tagged_right` 14x~24 unused here); player pin: `base\gameplay\gui\widgets\minimap\atlas_minimap.inkatlas` parts `player` (51x46 chevron) and `playerCone` (166x143).

## 4. Other widgets (map vs minimap)

World map: only `default_mappin.inkwidget` (all quest / POI / gig / vendor / fast-travel pins, no separate quest_mappin, poi_mappin or fast_travel_mappin) and `player_mappin.inkwidget`. A pin is differentiated purely by part + state, as in 1-3.

`base\gameplay\gui\fullscreen\world_map\mappins\player_mappin.inkwidget`: Root 64x64 canvas, style mappins.inkstyle, state `Player` (#29FFB9). Visible children: `iconBlack` shadow blob (state Player, scale 1.1, black), `icon` 64x64 `atlas_minimap.player` tint (0.161,1.314,0.726) = #29FFB9, `cone` `atlas_minimap.playerCone` same tint (margin T=-120), two faint pulse circles `circle` (op 0.07, scale 1.2) and `circle2` (op 0.005, scale 1.7) from `braindance_icons.inkatlas` part `recording1` tint (0.114,0.929,0.514); hidden: name "PLAYER"/distance text (raj font, size 24/20, tint (1.119,0.844,0.257)), edge Arrow (hidden). `CanSelectMappin()` false. Full tree: `tree_player_mappin.txt`.

Minimap widgets (`base\gameplay\gui\widgets\minimap\`, NOT the world map; listed for reference, trees in `tree_minimap_*.txt`): `minimap_quest_mappin`, `minimap_poi_mappin`, `minimap_dynamic_event_mappin` (+`_animations.inkanim`), plus courier/stealth/device/hazard/security-area/quest-area/world-encounter/stub variants. Quest and POI minimap pins are 48x48 roots with a 32x32 `icon` from `mappin_icons.inkatlas` (default tint ActiveRed 1.37,0.444,0.405; opacity 1), `above`/`below` 15x11 `braindance_icons.back_indicator` arrows (floor indicators, rot -90/+90), `clampArrow` 24x16 `atlas_minimap.arrow`, POI adds `taggedLeft/Right` (atlas_map_pins tagged_*) and a 256x256 `pulse` (`atlas_minimap.gradient_pulse`, tint (0.369,0.965,1.0), op 0.2). Same icon atlas, tint from state, no frame or bracket either.

## 5. Mock

`look_mock.png` (1800x490): 12 markers, row 1 idle (opacity 0.5, scale 1), row 2 selected/tracked state (opacity 1, scale 1.3, OnSelect end state). Each = shadow blob (141 px, black) + 64 px icon tinted by the state colour; HDR clamped (no bloom). `quest tracked*` = quest part in selected state. Markers marked `[guess]` have an unverified part/state assignment.

## Uncertain / still unknown
1. Per-variant `WidgetState` (TweakDB MappinsGroup) -> state table (only inferred); confirm with the in-game probe.
2. Which variant/phase renders the "?" glyph (atlas has `undiscovered`, `minor_activity`, `hidden_stash`); `MappinToTexturePart` never returns `undiscovered`. Possibly the game swaps variants to the "?" variant for undiscovered phase through TweakDB variants instead.
3. Whether shadow2 really renders at ~141 px (anchor Fill with -100 margins + scale 0.5 + fitToContent interplay) and its alpha in game.
4. On-screen pixel size/DPI scaling at non-4K, per-zoom IconScale, CompletedPOIOpacity value.
5. Whether icon opacity 0.5 is the visible idle opacity (HDR>1 tints plus bloom in game likely make idle pins look brighter than the mock's row 1).
6. Style opacity inheritance for states without Mappin.Opacity (assumed Default 0.5).
7. Colours under non-default colour themes (main_colors_*.inkstyle) were not resolved.
