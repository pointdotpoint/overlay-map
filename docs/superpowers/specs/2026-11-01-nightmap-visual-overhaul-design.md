# NightMap visual overhaul: design

Date: 2026-11-01
Mockups: `docs/superpowers/specs/2026-11-01-visual-overhaul/`

## 1. Intent

NightMap works, but it looks flat and washed out (`current-frame.jpg`). Everything is one wash of cyan. Building fills
are brighter than the roads. The world shows through the panel at 45 % opacity, and vanilla icons (car, NCPD, gig)
nearly vanish into the map. When zoomed out, clustering covers the city in hex count badges and rows of mini icons
(`current-clusters.jpg`).

The goal is a map that looks state of the art: a hologram that glows, uses vibrant colour and keeps strong contrast
with its background, so the important information is obvious at a glance. The user's three references (a Fallout 4
Pip-Boy map, an Evgeny Rodygin topographic hologram, a stock "hologram city" render) share these traits:

- a dark, quiet background;
- one cool base hue at a few brightness steps;
- glowing, hot-cored points of interest;
- subtle texture (scanlines, dot matrix, fine grid) that makes it read as projected light.

**What the eye lands on first: the markers and the roads.** Every decision below serves that order.

## 2. Goals, non-goals, anti-goals

Goals
- New look for the map surface: brightness ladder, dot-matrix buildings, scanlines, background texture (§4).
- Vanilla icons readable on any background via a dark disc behind each one (§5).
- New look for our own pins: the collectible chips (§5.3).
- Restyled frame: panel background, sidebar details card, hint bar keycaps, header, scale bar, outline and brackets (§6).
- Clustering replaced by tiered scale-and-hide on zoom (§7).

Non-goals
- No change to vanilla icon artwork or colours. They must match the game's map and minimap, because that's what the
  player already knows. This covers icon parts, colours (`NMTheme.VanillaStateColor`), and the idle 50 % / emphasised
  1.3× behaviour.
- No change to the panel layout geometry: panel size and position, 25 % sidebar, hint bar height, map clip.
- No change to controls, keybinds, pad behaviour, filters, GPS routing, teleport, fast travel, photos or collectibles
  logic. Only how they look.
- Photo pins (thumbnails) keep their current look. Only their zoom behaviour changes (§7). *(My call.)*
- No text labels on the map: no district names, no quest name beside its marker (user: "we don't need district
  labels for now"). The labels in `map-look.jpg` are mockup decoration. The tracked quest's name lives in the sidebar
  tracking block (§6). *(Quest labels left out: my call.)*

Anti-goals: the work fails if any of these happen, even if it "works"
- Markers or the route lose to the map: any vanilla colour (blue fast travel, teal gig) blends into the roads.
- Any existing feature is lost or behaves differently. Clustering is the one deliberate exception.
- A measurable frame-time regression in `NMPerfSuite` against the current main build.
- The look depends on a new runtime dependency (RED4ext plugin, shader mod, etc.).

## 3. Constraints

- Stack as today: redscript + Codeware, ink widgets, tiles baked by `tools/tiles` (BC7, six levels 0.5–16 m/px) and
  tinted at runtime from `NMTheme` (`TileTint` / `TileOpacity`).
- A tile rebuild is allowed (dot matrix and road classes need one). Rebuilding needs the user's game install. The
  archive can only be replaced while the game is closed.
- Existing settings keep working:
  - `holoColor` (Cyan / Green): the Green theme gets the same treatment in green.
  - `hologramEffects` off: no scanlines, bloom, bar, flicker or edge glow, but the brightness ladder, plates and
    frame stay.
  - `panelOpacity`
  - `showRoutes`, `showPhotos`
  - all filters and collectible toggles
- Public API (`docs/api.md`) stays source-compatible for other mods: `SetClustering` keeps compiling (see §7.3).
- Self tests (`Debug/SelfTest*.reds`) keep passing. Tests that assert cluster behaviour are rewritten for tiers, not
  deleted silently.

## 4. Map surface

Reference: `map-look.jpg` (with plates) and `map-look-no-plates.jpg` (the rejected variant, kept for contrast).

### 4.1 Brightness ladder (dimmest to brightest)

| Layer | Treatment | Mockup values (starting points, tune in-game) |
|---|---|---|
| Background | Deep navy radial gradient, darker at the edges | centre `#0a1a2c` → edge `#02050a` |
| Background texture | Fine dot grid; faint range rings around V | dots `rgba(90,170,255,.08)` every 24 px; rings `.10` |
| Building fill | Faint solid fill + **dot matrix** on top | fill `#123a5e` @ .35; dots `#4aa8ff` @ .35, 2 px dots on a 5 px staggered grid |
| Building outline | Thin, dim | `#3a8fd0` @ .40 |
| Minor roads | Mid blue, soft glow | `#2a86d8` body @ .60; glow @ .25, ~4 px blur |
| Major roads | Near-white, bloom | `#8fdcff` body @ .90; bloom `#2f9cff` @ .50, ~9 px blur |
| Route | Quest colour, dark casing, glow (as today, quest colour from vanilla) | 5 px line, 11 px `#000c` casing, glow |
| Markers | §5. Always above everything on the map | |

The user chose the **subtle** strength: buildings keep a faint solid fill under the dots, and scanlines are faint.

### 4.2 Road classes

Today the build has only `road` (plus `stroke`, by thickness, in `minimap.py:classify`). The ladder needs
**major/minor** roads. The mockup split them by width: erode the road mask about 5 px at 2 m/px, then dilate it
back. Wide roads are major. How the build derives the classes and stores them (a new tile set, or a channel in an
existing one) is left to the builder. Each class gets its own runtime tint and opacity.

### 4.3 Dot matrix

The dot matrix is part of the **base map**: it stays when `hologramEffects` is off, so it can be baked into the
building tiles. The background dot grid and the range rings around V are **effects**: they go away when effects are
off, like the grid today. *(My call.)*

The dot pattern has to stay a constant size on screen (about a 5 px pitch at 1080p) at every zoom level. Baking it into
the building tiles per level is the expected route, so it costs nothing at runtime. The builder confirms the
approach.

### 4.4 Hologram layer (effects on)

- Scanlines over the whole map, markers included (2 px dark lines on a 4 px pitch, `rgba(0,0,0,.14)`, subtle).
  `NMHolo.AddScan` exists; retune it and decide its z-order.
- The existing scan bar, noise flicker and grid stay, retuned to sit under the new ladder. The edge vignette darkens
  the map toward the frame.
- Bloom on major roads may reuse the `glow` set (a coarser level upscaled). If it can't be limited to major roads,
  the builder proposes an alternative.

### 4.5 Panel background

The map background becomes nearly opaque so the world can't wash it out (mockup: `rgba(2,6,12,.92)`). The
**default** `panelOpacity` changes, and the setting still works for anyone who wants see-through. Existing installs
that still hold exactly the old default (0.45) are moved to the new default once. Any other saved value is the
player's choice and is kept. *(My call: otherwise the user's own install would keep the washed-out look.)*

## 5. Markers

### 5.1 Vanilla icons: plates

Each vanilla icon keeps its artwork and colour and gets:
- a **dark disc** behind it, about 1.75× the icon radius, `rgba(1,4,9,.92)`, that cuts out the city;
- a soft dark falloff around the disc (out to about 3.4×), so nearby roads dim slightly;
- a **thin ring** in the icon's own colour at the disc edge (about 2 px, 70 % opacity);
- the icon's own glow.

This replaces or extends the current `ShadowAtlas` blob (`VanillaShadowSize` / `VanillaShadowOpacity`). The
vanilla idle 50 % / selected 100 % at 1.3× rules still apply to the icon. The plate follows the icon's scale.

### 5.2 Hovered / selected marker

- The marker scales up (vanilla emphasis rule).
- **Corner brackets** frame it (light `#d8f4ff` with a cyan glow). The existing reticle/crosshair is restyled, not
  replaced.
- Optional: a thin dotted leader line from the marker to the sidebar card. It was barely visible in the mockup; keep
  it only if it reads well in-game.

### 5.3 Collectible chips (ours)

- One shared shape for all six categories: a hexagon outline with a centre dot, each in its existing category colour
  (`NMCollect.Color`).
- A dark hex plate behind it, the same idea as §5.1.
- Smaller and quieter than vanilla icons, so they never compete with quests.
- Collected spots (when `collectShowCollected` is on) stay visibly dimmed, as today.

The user approved this as mocked (`map-look.jpg`, small hexes).

### 5.4 Player

White arrow with a soft glow in the vanilla player colour (`#29FFB9`). Same placement and behaviour as today.

## 6. Frame

Reference: `frame.jpg` against `current-frame.jpg`. Geometry is unchanged (§2). Styling:

- **Outline and brackets**: thinner outline (about 35 % opacity), sharper and brighter corner brackets, and a soft outer
  edge glow. The game's HUD curve on the panel stays.
- **Top-left header**: the district as a large title (about 34 px at 1080p, letter-spaced) with the sub-district and
  city under it, smaller and in the accent colour. Today the district sits in the bottom-right header; it moves here.
- **Scale bar**: top-right of the map view, with end ticks and the label centred under it.
- **Sidebar**: frosted dark glass over the map (`rgba(3,9,18,.80)` plus a blur if ink allows one cheaply; otherwise
  just the darker fill). It has a bright 1.5 px left edge and a soft inner gradient.
  - **Hovered card** (top):
    - small "HOVERED" label;
    - the marker's icon on its plate;
    - title (bold, white);
    - category · district in the marker's colour;
    - distance right-aligned;
    - divider;
    - description;
    - rows;
    - actions as **keycap chips** (key in a small outlined box, label beside it).

    This is the data `NightMapDetails` already carries (category, title, subtitle, description, rows, actions). When
    nothing is hovered, the card area stays empty or shows a single quiet line. "POINT AT A MARKER" as the only
    content goes away.
  - **Tracking block** (bottom, pinned): "TRACKING" label, a quest-yellow diamond, the quest title in quest yellow, and
    the objective wrapped to the sidebar width (two lines max, as `NMQuestHeader.Clip` does today).
- **Hint bar**: one keycap per binding, then a label, with spacing between groups. CLOSE sits on the far right. Today
  this is a single string (`NMInput.HintText` / `NMPad.HintText`). It becomes a row of widgets, with key names still
  coming from the user's bindings and the keyboard/pad switch working as now. FILTER shows the current view
  (e.g. FILTER · ALL).
- **Typography**: the game's Rajdhani (`NMTheme.BodyFont`). Uppercase, letter-spaced labels; sentence case for
  description and objective text.
- **Warning text** (version mismatch) and other existing panel text keep their function; restyle them to match.

## 7. Zoom: tiered scale-and-hide (replaces clustering)

### 7.1 Behaviour

- Clustering is removed: no hex count badges, no mini-icon rows.
- As the map zooms out, markers **scale down** smoothly with the map, to a minimum size, and then **fade out** over a
  short zoom range. Nothing pops.
- Hiding happens in **tiers** (the user's call):

| Tier | Contents | Hides |
|---|---|---|
| Always | Tracked quest marker, the route, V (player) | never |
| Major | Quests (main / side), fast travel | latest |
| Minor | Vendors, gigs, cyberpsychos and other vanilla services, NCPD/police dots, our collectible chips, photo pins, third-party layers by default | first |

**Filters promote their categories.** When a filter view other than ALL is active (`NMVanillaFilters`: JOBS,
SERVICES), every category that view shows moves up to the Major tier. Under SERVICES, vendors stay visible as long
as fast travel does. Under JOBS, gigs and cyberpsychos stay visible as long as quests do. So the tier is worked out
from the current view, not fixed per layer. Without this, filters would be nearly useless at far zoom, which would
break the "no feature behaves differently" anti-goal. *(My call. The user didn't answer this one; confirm when
reviewing.)*

Exact zoom thresholds and minimum sizes are left to the builder. Tune them in-game so the far view of the whole city
shows only the Major tier and stays uncluttered.

### 7.2 Hover and selection

A hidden marker can't be hovered or selected. While a tier is fading, its markers stay selectable until they are
fully hidden.

### 7.3 API and performance

- Third-party layers default to the Minor tier. Add a way for a layer to choose its tier (API shape left to the
  builder; document it in `docs/api.md`).
- `SetClustering(...)` still compiles and is ignored. Document it as deprecated.
- The draw budget (`ChipBudget` 300) stays as a safety cap. Tiered hiding should keep far zoom well under it.
  Remove `ClusterBudget` and the cluster code paths.

## 8. Motion

My call; the user didn't specify. Keep the existing subtle animations (scan bar, noise flicker), retuned. No new
looping motion on markers, apart from the existing emphasis grow. A short open animation (a fade or sweep of a couple
hundred ms) is allowed if it costs nothing measurable.

## 9. Left to the builder

- How major/minor roads and the dot matrix get into the tiles (§4.2, §4.3).
- How bloom is limited to major roads (§4.4).
- How plates are drawn: a new atlas part, a reused shadow blob plus a ring part, or similar.
- Exact colour and opacity values. The tables are starting points from browser mockups, and ink HDR colours will
  read differently in-game.
- Zoom thresholds, minimum marker sizes and fade ranges per tier.
- The tier API shape for third-party layers.
- The Green theme values (same structure, green hue).

## 10. Verification

- In-game screenshots, before and after, at three zooms (close, mid, whole city), with markers on screen and one
  hovered. Compare them with `map-look.jpg` and `frame.jpg`.
- `NMPerfSuite`: every scenario's frame time is no worse than current main, within noise. Report the numbers.
- All self tests pass, with cluster tests replaced by tier tests.
- Checks:
  - effects off: the ladder, plates and frame still look right;
  - Green theme;
  - `panelOpacity` at a low value;
  - pad hint bar;
  - photo pins, the GPS route, collectibles, teleport and fast travel all still work.
