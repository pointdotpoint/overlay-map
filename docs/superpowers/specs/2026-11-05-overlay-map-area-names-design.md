# Overlay Map: area names under the cursor (design)

2026-11-05. Request: "I'm standing in the middle of the landfill and I want the right sidebar to say Landfill (while the
cursor is in the area and I'm not hovering any map marker)."

## Behaviour

- The map's cursor is the focus point: the camera centre `(camera.cx, camera.cy)`, drawn as the reticle in the middle
  of the view left of the sidebar.
- When no marker is selected and the focus lies inside a named area, the sidebar shows an area card: the parent chain
  as the label line (e.g. `BADLANDS · RED PEAKS`), the area name as the title, and an optional description.
- A selected marker always wins: its card replaces the area card, and the area card comes back when the selection
  ends, without needing another pan. The photo drawer wins the same way.
- Where areas overlap, the smallest one wins (Afterlife over Little China, Downtown over City Center).
- Outside every area the sidebar stays empty, as today.
- The top-left district title is unchanged (it still follows V through the PreventionSystem).

## Data

- Game areas come from the world sectors, not from any online source. The mod ships on Nexus, so only game-file data
  may ship. A scrape of Piggyback's paid map exists but is excluded.
- Every node carrying a `worldLocationAreaNotifier` has a `districtID` (a `Districts.*` TweakDB record). Its outline
  is the `AreaShapeOutline.buffer`: uint32 count, then count Vector4 points. The `points` field is often a stale unit
  square. The points are multiplied by the nodeData `scale`, rotated by `transform.orientation` and offset by
  `transform.position`.
- Sectors must be converted with WolvenKit 10. 8.19 fails on most of them.
- The 2026-11-05 survey found 205 outlines and 107 IDs, from sub-districts (Rocky Ridge 21 km²) down to interiors
  (Afterlife, Totentanz). Parent districts such as Watson, Pacifica and Badlands have no outline of their own.
- Dropped:
  - Empty or `0` IDs, e.g. `{combat_zone_loc_area}`.
  - Virtual or quest-only IDs matching `(?i)cyberspace|VR_Tutorial|SpaceStation`.
  - The stacked Arasaka Tower floors `^Districts\.ArasakaTower(?!Lobby$)`. A 2D cursor cannot pick a floor.
  - Superseded shapes: when an ID has outlines whose debug name ends in `_new`, only those are kept. This applies to
    Coastview and West Wind Estate, whose old shapes covered Dogtown.
- Game area names are resolved at runtime with `TweakDBInterface.GetDistrictRecord(id).LocalizedName()`, so they
  follow the game language. The parent chain comes from `ParentDistrict()`. An area whose name resolves empty is
  skipped, and the next larger area under the focus is used instead.
- Custom areas, for places the game does not name, live in `tools/areas/custom_areas.json`. Each one has a key, an
  English name, a parent `Districts.*` ID, an optional description and a polygon. The first is Landfill (parent
  `Districts.RedPeaks`). Its polygon is the convex hull of the sector nodes whose debug name contains
  `landfill_pile`, reviewed on a preview render.
- Output is `r6/scripts/OverlayMap/Generated/AreaData.reds`, generated like `CollectData.reds`: chunked strings, no
  runtime file IO.
