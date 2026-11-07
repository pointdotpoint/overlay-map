# Overlay Map: feature ideas

Brainstorm from 2026-11-07, after the 1.0.0 release. None of these has had a feasibility check in game yet; the notes
say what each would build on. Most reuse data the mod already reads: the vanilla building boxes and their heights, the
area outlines, the route, collectibles and the NCART lines.

## Jaw-dropping

1. **Tilt into a 3D hologram.** Hold a key and the flat map tilts into a perspective view, with buildings rising from
   the floor as glowing blocks. Builds on the building heights from the vanilla boxes and the in-world hologram panel.
   The screenshot that sells the mod, and the hardest idea here: needs a research spike before it is known to be doable.
2. **Police and danger shown live.** When V is wanted, NCPD units show as moving red dots with a search area around
   them. Gang combat zones glow as warning areas (the sector data already has combat-zone areas). Needs a check that the
   game exposes live police positions.
3. **Scanner pulse.** Press a key and a sonar ring sweeps outward through the 30 rings, briefly showing nearby enemies,
   loot and cameras. Matches the hologram style and V's cyberware.
4. **Fog of war and exploration.** Places V hasn't been stay dim and light up as V explores. The sidebar shows e.g.
   "Watson 64% explored", using the area outlines. Gives the map a reason to exist beyond navigation.

## Very cool, more realistic

5. **Live NCART trains.** Trains moving along the lines already drawn, with the time until the next one at each station.
6. **Gang territory.** Each district shaded in its gang's colour, using the area outlines. The vanilla map already lists
   the main gangs per district.
7. **Route preview.** A quick camera flight along the tracked route, plus estimated travel time by car and on foot.
8. **Your vehicles on the map.** Where V's owned cars are, and a button to call one.
9. **Multi-stop route planner and distance tool.** Chain several waypoints and see the total distance.
10. **Travel history.** A fading trail of where V has been, or a heatmap of all time spent.

## Polish

11. **Sun-matched shadows.** Building shadows follow the in-game time of day: bake a few light directions and switch
    between them.
12. **Weather on the hologram.** Rain streaks and interference on the map when it rains.

## Also queued for 1.1

- **M key:** tap M opens Overlay Map, hold M opens the vanilla map (needs a check that the mod can stop the game's own
  map from opening on M).

## Recommendation

- **Biggest impact:** the 3D tilt (1), after a research spike.
- **Best value, lower risk:** the scanner pulse (3) and fog of war (4); both are mostly our own drawing on top of systems
  the mod already has.
- **Quick wins for 1.1:** gang territory (6), live trains (5), and the M key.
