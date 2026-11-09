# Overlay Map

A hologram-style 2D world map for Cyberpunk 2077 that opens over the game with one key, so you can check the map
without leaving gameplay. It draws the vanilla map's own roads and buildings, shows the game's markers with their
vanilla icons, mirrors your GPS routes, names the area under the cursor, and lets you set waypoints, fast travel and
teleport from it.

Developers and mod authors: see [docs/DEVELOPING.md](docs/DEVELOPING.md) and [docs/api.md](docs/api.md).

## Requirements

- Cyberpunk 2077 **2.5**. The map is built from 2.5's game data; on another version the map shows a notice that some
  places may not match.
- [redscript](https://www.nexusmods.com/cyberpunk2077/mods/1511)
- [Codeware](https://www.nexusmods.com/cyberpunk2077/mods/7780)
- [RED4ext](https://www.nexusmods.com/cyberpunk2077/mods/2380) (Codeware needs it too)

Optional:

- [Mod Settings](https://www.nexusmods.com/cyberpunk2077/mods/4885): the settings menu and key rebinding. Without it
  every option keeps its default.

## Install

Unzip into your Cyberpunk 2077 folder (the one with `bin`, `archive` and `r6`), or install with Vortex or Mod Organizer.
The zip adds:

    archive/pc/mod/OverlayMap.archive
    r6/scripts/OverlayMap/
    red4ext/plugins/OverlayMapNative/

To uninstall, delete those three.

## Controls

`O` opens and closes the map. It does nothing in menus or photo mode, where the game uses O itself.
Change it under Mod Settings → Overlay Map → Keys → Open / close map. To open it with a combo such as Ctrl+M, also set
Open map modifier there; the key alone then closes the map.

**Mouse pans the map** (Keys (map takes keyboard)): moving the mouse pans the map instead of turning V's camera, with
its own speed slider. On by default; turn it off to keep turning the camera with the mouse while the map is open.

**Keyboard (default).** While the map is open it takes the keyboard and mouse, so V stops:

| Action | Key |
|---|---|
| Pan | W A S D, or the arrow keys |
| Zoom | Mouse wheel |
| Follow V again | Space |
| Act on the selected marker | F |
| Set waypoint / track | E or Enter |
| Teleport / fast travel | Q |
| Cycle marker filter | R |

**Numpad.** Mod Settings → Overlay Map → Keys → Controls → *Numpad*: the map uses only the numpad, so V keeps full
control of movement and the mouse while it is open. Numpad 8 4 6 2 pan (7 9 1 3 diagonally), + and − zoom, 5 follows V,
0 acts, Enter sets a waypoint, / cycles the filter, . teleports. Keep NumLock on.

**Mouse only.** Controls → *Mouse only*: V keeps walking or driving with the keyboard while the mouse drives the map.
Moving the mouse pans, the wheel zooms, left click acts, holding left click for 2 seconds teleports (a ring fills
around the crosshair) and right click sets a waypoint. Follow and the filter keep their numpad keys.

**Controller.** Hold View for half a second to open the map (a tap still opens the pause menu). Left stick pans, LT/RT
zoom, A acts, RB sets a waypoint, X teleports, Y cycles the filter, R3 follows V, B closes.

Every key can be rebound in Mod Settings → Overlay Map.

## What it does

- **The map.** Roads and buildings come from the vanilla map's own data, with Dogtown and the Badlands included. It
  zooms from single buildings to the whole city.
- **Markers.** The game's markers (quests, gigs, NCPD, vendors, fast travel and more) appear with their vanilla icons.
  Move the map so a marker is nearest the centre to see its details in the sidebar. Minor markers fade out first as you
  zoom out; the tracked quest and V never do. Map filters in Mod Settings turn each category on or off.
- **Waypoints.** E (or Enter) works like right-clicking on the vanilla map: on an empty spot it sets the game's custom
  waypoint with its GPS route, on a job or gig it makes that quest active, on another marker it tracks it, and on what is
  already tracked it clears it. Everything except tracking quests needs RED4ext.
- **GPS routes.** Your waypoint route (white) and the tracked quest's route (yellow, teal for gigs) are drawn as
  flowing dots.
- **Area names.** With no marker selected, the sidebar names the area under the cursor and its district, in your game
  language. A few places the game doesn't name, such as the Landfill, are named too (in English).
- **Collectibles.** Every shard, tarot graffiti, iconic weapon, legendary cyberware and clothing piece, and skill shard
  placed in the world has its own pin. Collected ones stay on the map, scratched out.
- **Teleport and fast travel.** Q on a fast travel marker fast travels there the game's way. Anywhere else it teleports
  V (and V's car) to the spot. Turn the teleport key off under Display → Teleport key.
- **NCART lines.** Map filters → NCART lines (off by default) draws the five metro lines in their colours.
- **Photo pins.** Photos taken in photo mode are pinned where you took them and kept between sessions.
- **Look.** Five colour themes (Cyan, Green, Red, Purple, Amber), or follow your [HUD
  Painter](https://www.nexusmods.com/cyberpunk2077/mods/14935) colours. Panel size and opacity, the opacity of the
  whole map, map brightness and contrast, road glow, scanlines and an optional VHS tracking band and glitch (off by
  default) are all under Display.
- **Hold to show.** Display → Hold key to show keeps the map up only while the open key is held.
- **For mod authors.** Other mods can add their own items to the map through a layer API.

## Known issues

- The waypoint plugin has been tested on game 2.5 under Proton (Linux). If it can't find the game function it needs,
  waypoints switch off and everything else keeps working.
- The game's HUD fades out while the map is open (Display → Hide HUD while open turns that off).
