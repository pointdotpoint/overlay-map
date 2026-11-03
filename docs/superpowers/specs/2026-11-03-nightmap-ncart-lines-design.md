# NightMap: NCART lines overlay — design

Status: approved by the user's goal on 2026-11-03: "build the metro overlay and verify it ingame. the main goal is that
it should look FLAWLESS and beautiful". Visual quality is the ship bar: judge it on in-game screenshots at several
zooms, not only on tests.

## Intent

The player wants to see the NCART metro network on NightMap the way the official NCART service diagram shows it:
five coloured lines, side by side where they share track, but drawn where the tracks really run under the city, so the
lines connect NightMap's NCART station markers. It is one more map filter: switch it on to plan a metro ride, off to
keep the map clean.

Reference look: the NCART service diagram the user supplied (`/mnt/ssd_220gb/pic/NCART_Map_CP2077.webp`; neon lines,
parallel where they share track, colours A red, B yellow, C cyan, D green, E orange).

## Goals

1. **One filter switch.** Mod Settings → NightMap → Map filters → "NCART lines" (user: one switch for all five lines).
   Off by default (my call; the user did not object). Applies on the next open like the other filters, or live if
   cheap.
2. **Real positions.** Each line follows the real track geometry and passes through its stations, so it lines up with
   NightMap's NCART station markers (fast-travel layer) at every zoom.
3. **Looks like the diagram** (user):
   - each line in its own fixed colour, whatever NightMap theme is active (my call: also ignores "Follow HUD Painter
     colours"; the lines are NCART's branding, not HUD colours);
   - where lines share track they run **side by side**, parallel, each in its colour, like the diagram;
   - a slight neon glow (my call; baked into the line tiles, see How);
   - a readable width at every zoom (my call): a fixed pixel width per tile level, so it varies by up to 2x between
     levels like the roads, never vanishing or swelling.
4. **Layering** (my call): above roads and buildings, below markers, the GPS route and the reticle.

## Non-goals

- No station dots, names or line badges (MA..ME) on the lines (user: NightMap's own NCART markers are enough).
- No per-line switches, no service direction, no live train positions.
- No corner minimap (shelved).
- No change to the NCART station markers themselves.

## Anti-goals (would make it a failure even if it "works")

- Lines visibly off the tracks or missing the station markers.
- Shared stretches drawn as one blended line, or lines on top of each other so a colour is hidden.
- A noticeable frame cost while the map is open, or any cost while it is closed or the filter is off.
- Changing how anything else looks when the filter is off.

## What exists (facts found while designing)

- **Track geometry:** the vanilla 3D map ships the whole NCART track network as one mesh, `3dmap_metro`, already
  exported by the tile build (`tools/tiles/build/meshes/base/entities/cameras/3dmap/3dmap_metro.glb`; transform in
  `nmtiles/heightmap.MESHES["3dmap_metro"]`, 12,825 triangles, xy bounds about (-2574, -1925)..(517, 2880), z -21..112).
  Rendered from above it matches the diagram's topology. It is one piece: it carries **no per-line information**.
  It may stop short in the south (bounds end at y ≈ -1925) — the builder must check the B/C southern terminus
  (Pacifica – Stadium) and any other station against it.
- **Lines:** the game defines lines for its in-train service display: `ncartLineListDef { m_lineNumber, m_lineColor,
  m_stationsList: array<ENcartStations>, m_lineIsLooped }` in
  `.scratch/refs/cp-scripts/scripts/cyberpunk/vehicles/metroLinelist.script`; the values live in the controller's
  `.inkwidget` (`NcartTrainLineListInkController.m_LinesList`). `ENcartStations` lists the 19 stations. The NCART
  service map UI is `UI/fullscreen/metro_map/ncartMetroMap.script` (lines A..E). The supplied diagram is the fallback
  reference for station order and colours if the game data cannot be read.
- **Stations:** NightMap already shows the NCART stations as vanilla mappins (fast-travel filter, "Show fast-travel
  points and NCART stations").
- **Filters:** map filters are `NightMapSettings` booleans in the "Map filters" Mod Settings category (`filterJobs`,
  `filterFastTravel`, ...). Offline settings checks live in `tools/test_holo_settings.py`-style tests.
- **Drawing:** the GPS route is drawn at runtime as a vector layer (`Render/RouteLayer.reds`) with a constant
  on-screen width and deliberately no glow (overlapping translucent pieces band). The map tiles are white masks per
  set (`nmtiles/render_minimap.py`, BC7-encoded), tinted at runtime by `NMTheme.TileTint`.

## How (decided)

- The line routes are computed **offline** from game data (track mesh + line station lists + station positions)
  (my call: no track analysis at runtime).
- **Baked into a full-colour tile set** `metro` (my call, after the builder check; replaces "runtime vectors"): the
  runtime route layer has no glow on purpose (overlapping translucent pieces band), and "flawless" needs proper
  antialiasing, a soft glow and clean parallels. So each level's tiles are rendered offline with the lines in their
  own colours (RGBA, not a white mask; tint white at runtime, theme- and HUD-Painter-independent), the side-by-side
  offsets computed in pixels at that level, a soft glow under each line. Shown only when the filter is on; drawn
  above the road tiles and under everything else, like the other tile sets. Line width therefore varies by up to 2x
  between zoom levels like the roads do, instead of being exactly constant (accepted trade-off).
- On shared track each line has a fixed slot (consistent order, so a line keeps its side through a shared stretch);
  where lines split, offsets ease smoothly, no zig-zags.
- **Stations** (my call): lines stay on the real track. The build measures every NCART marker's distance to its
  line; a marker visibly off the track (more than a few metres at close zoom) gets a short smooth spur from the
  track to the marker. The build log lists every station's distance.
- **Hologram/VHS effects** (my call) play over the lines like over the rest of the map; "fixed colours" only means
  no theme or HUD Painter tint.

## Left to the builder

- Extracting the line definitions (station order, colours, loops) from the game's `.inkwidget`, and the station world
  positions (NCART mappins / fast-travel records), or falling back to the diagram.
- Turning the track mesh into a centreline graph, snapping stations to it, and routing each line between its
  consecutive stations (shortest path along the track graph); handling gaps where the mesh is missing (straight
  segment to the station, flagged in the build log).
- The order of lines on shared stretches and how the offsets join where lines split (should look like the diagram's
  smooth parallels, no zig-zags at junctions).
- Simplifying the polylines to a sensible point count; draw cost budget (measure with the existing perf tooling).
- Tests: offline (route extraction, offsets, generated data) and in-game self-tests; an in-game screenshot check that
  the lines meet the station markers. Ask the user before every in-game run when they may be playing.
