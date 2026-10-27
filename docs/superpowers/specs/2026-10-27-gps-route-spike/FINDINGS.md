# GPS route spike: findings

Probe: `r6/scripts/NightMap/Debug/GpsProbe.reds` (branch `spike/gps-probe`, throwaway). Two in-game sessions on
2026-10-27 (game 2.31, Codeware): about 10 minutes on foot and in a car, with a quest tracked about 790 m away.

## Answer
The HUD minimap's GPS route can be read from script and converted to world space. A native plugin is not needed.

## Source
- `MappinsContainerController` (the HUD minimap controller) has the native fields `gpsQuestPathWidget`,
  `gpsPlayerTrackedPathWidget`, `gpsDelamainPathWidget` and `autodrivePathWidget`. Codeware exposes them as
  `inkLinePatternRef`, with `.widget` giving an `inkLinePatternWidget`.
- `inkLinePattern.vertexList: array<inkLineVertex>` (Codeware) holds the live route. Each point is `.int: Vector2`.
- Catch the controller by wrapping `MinimapContainerController.OnPlayerAttach`/`OnPlayerDetach`.
- Widget chain: `gpsQuestPath` → `gpsPathContainer` → `maskedContainer` → `MiniMapContainer` → `Root`. Every level
  has rotation 0 and scale 1. The rotation and zoom are baked into the vertices.

## Extent
- It is the **whole route**, not only the part inside the minimap circle. A 790 m route had 329 to 390 points and
  ended 0.3 m from the tracked quest mappin.
- The count drops as the player gets closer (128 → 11 points over the drive).
- When nothing is tracked the path has 1 point and `IsVisible() == false`.

## Space (confirmed on both sessions)
For a reading with points `v[0..n-1]`, player world position `P` and camera yaw `c`:

- `v[0]` is the player: `v[0] = s * (P.y, P.x)`, with the axes swapped and no rotation. The widget's translation is
  `-v[0]`.
- The scale is `s = |v[0]| / |P.xy|`, in minimap units per metre. It is 3.18 on foot and 0.8 to 1.6 in a car, where
  the minimap zooms out with speed. Both axes agree to within 0.01. Read it per sample; it is not a constant.
- The rest of the points: `v[i] - v[0] = s * R(c) * flipY(W[i] - P)`.
- Inverse: `W[i] = P + flipY(R(-c) * (v[i] - v[0])) / s`, where `flipY(x, y) = (x, -y)`.
- `c` is the **camera** yaw, `atan2(-fwd.x, fwd.y)` of `CameraSystem.GetActiveCameraForward()`. It is not the player
  yaw:
  - On foot the two are usually equal. When they differ (camera turning), the camera yaw fits exactly and the player
    yaw is off by about 5°.
  - In a car the endpoint reconstructed with the camera yaw stays within about 5 m. With the player yaw it drifts by
    20 to 400 m.
  - Photo mode moves the camera freely and breaks the fit. That does not matter, because neither the minimap nor
    NightMap is used there.
- Accuracy: on foot, under 1 m. In a car at speed, about 5 m (minimap smoothing or a one-frame lag). That is invisible
  at NightMap zoom levels.

## Caveats for the design
- `s` divides by `|P|`. Near the world origin, keep the last good `s`.
- `gpsPlayerTrackedPath` uses the same transform. In both sessions it led to a GangWatch pin with
  `IsPlayerTracked() == true` (not a custom waypoint). The endpoint held at (-954.5, -788.3), about 4.5 m from the pin:
  the route ends at the nearest walkable point. It is the route to whatever pin the player tracked from the vanilla
  map.
- **Custom waypoint, confirmed** (third session, 13:46):
  - A `CustomPositionVariant` waypoint was set 441 m away at (-1489.3, -413.7). `gpsPlayerTrackedPath` switched to
    189 to 191 points.
  - Its converted endpoint was (-1489.4, -413.8), within 1 m on every tick.
  - Camera yaw fitted again on the ticks where it differed from player yaw.
  - Oddity: `GetManuallyTrackedMappinID()` did not match the waypoint's id in the probe (`manual false`). Do not key
    the route on it; read the widget.
- The minimap must exist (HUD on) for the vertex list to update. It kept updating while NightMap was open: from
  12:15:48 to 12:16:08 the player walked 35 m with the map open, and the endpoint held to within 1 m.
- The route is re-planned when the player strays: the count and shape change, so diff it per poll.
