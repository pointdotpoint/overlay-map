# NightMap: teleport to the map point

**Status:** design agreed in conversation on 2026-10-27, builder-checked. Awaits user review.
**Branch:** `feat/teleport`, from `main` at be791aa (GPS routes merged).

## 1. Intent and user decisions

The user wants to move NightMap to any spot and press a key to teleport V there: "any random spot on the map, i want
to be able to teleport anywhere". It is a convenience and cheat feature for the user's own single-player game.

Decided by the user:
- **Anywhere:** any point on the map, not only markers.
- **Roofs are fine:** when the spot is a building, V may land on its roof.
- **Vehicles:** when V is driving, the car (or bike) comes along with V in it.
- **Merge the GPS work first**, then build this on its own branch. Done.

Corrected in conversation: Numpad 0 does not set a waypoint on an empty spot today (that stays the native-plugin
item). Teleport is a separate key and does not depend on waypoints.

## 2. Goals, non-goals, anti-goals

**Goals**
- One key teleports V (and V's vehicle) to the point the map is pointing at.
- On a vanilla marker, land at the marker's exact position.
- On an empty spot, land on the first solid surface below that point (ground or roof).

**Non-goals**
- Choosing street level over rooftops.
- Setting waypoints from NightMap.
- Blocking teleport during scenes, missions or combat. Like any teleport mod it can break quest scripting; when to
  use it is the user's call.
- Teleporting while the map is closed.

**Anti-goals** (a failure even if it technically works)
- V left falling, stuck inside geometry, under the map or in the void.
- Fall damage or death from the landing.
- V separated from the car when driving, or the car left behind.
- A press that does nothing and gives no sign why.

## 3. Facts the design rests on

- `GameInstance.GetTeleportationFacility(gi).Teleport(obj: GameObject, position: Vector4, orientation: EulerAngles)`
  exists in vanilla script.
- `GameInstance.GetSpatialQueriesSystem(gi).SyncRaycastByCollisionGroup(start, end, group, out TraceResult,
  staticOnly, dynamicOnly) -> Bool` exists. It only hits collision that is streamed in, which is why the landing is in
  two steps.
- NightMap items are `Vector4` positions. Vanilla marker items (layers `Vanilla.*`) carry the mappin's real Z from
  `GetWorldPosition()`. Items from other mods' layers may not have a meaningful Z.
- "Where the map is pointing" is the crosshair at the map centre. The crosshair snaps a selection to the nearest item
  (`selKind == 0`) or cluster (`selKind == 1`); the tooltip shows the selected item.

## 4. Behaviour

### 4.1 The key
- New setting `keyTeleport` under Keys, display name "Teleport", default **Numpad .** (`IK_NumPeriod`, next to
  Numpad 0, not used by NightMap today), rebindable like the others. *(Spec author's call: Numpad Enter was proposed
  in conversation, but `EInputKey` has no separate Numpad Enter; it reports `IK_Enter`, which the game uses.)*
- New setting `teleportEnabled` under Display, "Teleport key", **on** by default. Off: the key does nothing and the
  hint is not shown.
- The hint bar gains `<key> TELEPORT` after ACT. Add it before CLOSE.
- One press teleports; no confirmation, no hold.

### 4.2 Target
- **Selected vanilla marker, on foot** (`selKind == 0` on a `Vanilla.*` layer other than `Vanilla.Pinned` and
  `Vanilla.Other`): the marker's X, Y and Z, plus a small upward offset (§4.4). Single step, no raycast needed.
  *(Spec author's call: `Vanilla.Pinned` holds the custom waypoint and tracked quest pin, whose Z may not be a floor,
  and `Vanilla.Other` can hold markers that ride NPCs or vehicles; those use the marker's X/Y on the empty-spot path.
  If a marker landing still puts V inside geometry in testing, move that layer to the empty-spot path too.)*
- **Selected vanilla marker, in a vehicle:** the marker's X/Y on the empty-spot path. *(Spec author's call: many
  markers are indoors or on walkways, where a car placed at the marker's Z would end up inside a building.)*
- **Anything else** (no selection, a cluster, an item from another mod's layer): the map centre's world X/Y,
  empty-spot path.
- Near a marker the crosshair snaps to it, so the target is the marker, not the exact centre; zooming in avoids the
  snap. This is the existing selection behaviour and is not changed.
- The map closes as the teleport starts.

### 4.3 Empty spot: two-step landing
1. **Lift:** teleport V (or the vehicle) to (X, Y, `LiftZ`), keeping the current yaw. `LiftZ` is above the tallest
   structure in Night City *(builder picks and documents the value; about 600 m is the starting guess)*.
2. **Settle:** each frame for up to `SettleTimeout` (*about 5 s*), raycast straight down from just under V's current
   position to well below the lowest ground (*about −200 m*), static collision only. On the first hit, teleport V
   (or the vehicle) to the hit point plus the offset (§4.4). That second teleport also zeroes the fall.
3. **Hold during settle:** V must not hit the ground before the raycast succeeds. The builder chooses how: re-lift
   to `LiftZ` each frame until a hit, or freeze V if a safe way exists. Falling for a few seconds from 600 m is not
   fatal by itself, but landing before the settle teleport is.
4. **Water** *(user decision: "land in the water")*: after a hit, ask
   `AIScriptUtils.GetWaterLevel(gi, (X, Y, hitZ), out level)`. If it reports water and `level` is above the hit, land
   at `level` instead of the hit: V swims at the surface, and a vehicle lands on the water and behaves as vehicles do
   in water in this game (it sinks). Log `teleport|ok|water|...`.
5. **Timeout:** no hit within `SettleTimeout` (not streamed, the void): teleport V back to where they started and log
   `teleport|failed|no ground`.
6. **Outside the map:** a target outside the tile manifest's world bounds is refused before any teleport, with
   `teleport|refused|outside map`.

The settle needs a per-frame tick after the map has closed. NightMap's loop stops when the map closes, so the builder
adds a small teleport driver that keeps ticking until it lands or times out.

### 4.4 Landing offset and orientation
- Land at hit Z plus a small offset (*about 0.5 m on foot, 1 m for a vehicle*) so V is not inside the surface.
- Keep V's (or the vehicle's) current yaw; level pitch and roll for a vehicle.

### 4.5 Vehicles
- If V is mounted in a vehicle, the object teleported in every step is the **vehicle**, with V still in it. This
  applies whether V is the driver or a passenger; any NPC driver comes along. *(Spec author's call, following "the car
  comes along".)*
- Roofs are allowed for vehicles too, as for V; the user can teleport again from there. *(Spec author's call.)*
- `Teleport` returns nothing, so "refused" means: after the lift teleport, the vehicle's position has not moved
  toward `LiftZ` by the next frame.
- Zero the vehicle's velocity on the final placement so it does not land rolling or flipping, if the game allows it
  from script; the builder checks what is available.
- If the game refuses or the vehicle cannot be moved (for example a scripted drive), cancel the teleport, leave
  everything where it was, and log `teleport|refused|vehicle`.

### 4.6 Feedback
- Every outcome logs one line: `teleport|ok|<marker|ground>|x,y,z`, `teleport|failed|...`, `teleport|refused|...`.
- *(Spec author's call)* No on-screen notification in this release; the map closing and V moving is the feedback.
  A failure puts V back where they were, which is visible.

## 5. Testing

- Self-tests (offline, no teleport performed): target choice (fixed vanilla marker on foot → marker position;
  `Vanilla.Pinned` / `Vanilla.Other`, in a vehicle, cluster, none, or another mod's layer → empty-spot path),
  outside-bounds refusal, water-over-hit chooses the water level, hint text includes TELEPORT only when enabled, settle state machine with a
  fake raycast (hit on frame N → lands at hit + offset; no hit → returns to start after the timeout).
- In-game checkpoint:
  1. On foot, empty street spot 1 km away: lands on the street, no damage.
  2. On foot, spot on a tall building: lands on the roof.
  3. On foot, a vanilla marker (fast travel point): lands at it.
  4. Driving, empty road 1 km away: car and V arrive together, car upright and not rolling.
  5. A spot out at sea: V lands at the water surface and swims; log says water. Repeat in a car: the car lands on
     the water.
  6. A spot outside the map bounds: nothing happens; log says refused.
  7. Teleport setting off: key does nothing, hint hidden.

## 6. Left to the builder
- `LiftZ`, `SettleTimeout`, the raycast start and end, the collision group (vanilla ground checks use `'Static'` or
  `'PlayerBlocker'`), and the offsets.
- How to hold V during the settle (§4.3 step 3).
- Zeroing vehicle velocity (§4.5), if possible.
- Where the teleport driver lives and how it ticks after the map closes.

## 7. Review focus (most likely to bite a user)
1. Landing before the settle teleport: fall damage or death.
2. Landing inside geometry: a raycast that hits a surface V cannot stand on (glass, a sign, a bridge underside).
3. The vehicle path: V dismounted, car left behind, or car flipped.
4. Teleporting during a scripted scene or mission area: allowed by design, but it must not crash.
