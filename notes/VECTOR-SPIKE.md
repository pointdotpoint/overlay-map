# Vector layer spike (sub-project 1b), 2026-10-12

The spike was throwaway code: `ShapeBench` in `~/cyberpunk_map_bench` on branch `spike/map-bench`, commits 5954359, 3e42d03 and ef10fc5. It ran in-game on CP2077 2.31 / Proton at 2560×1440, with a baseline frame time of about 14.7 ms.

## Findings

1. **Custom `vertexList` on an `inkShape` renders nothing.** This held in every setup tried:
   - absolute points in a large widget;
   - points relative to a bounds-sized widget;
   - a shape resource set but no preset;
   - points set after `SetShape`, where the async resource load overwrites them;
   - points set 30 frames after the resource loaded (spike 3, row B).

   The geometry can't be created or edited at runtime.
2. **Shapes from a shape resource render, smoothly.** The working path is `SetResource(<.inkshapecollection>)` plus `SetShape(<preset name>)`. A pipeline-built `inkShapeCollectionResource` works: we wrote the presets, ran `WolvenKit convert d` and packed it into our own archive.
   - Lines are anti-aliased.
   - Concave fills (an L shape) are correct.
   - A 49-point circle and a 200-point road look smooth.
3. **Scaling a parent canvas zooms cleanly.** At 4× the lines stay smooth. Line thickness scales with the canvas, so it must be compensated per zoom step with `SetLineThickness`, which is cheap.
4. **One preset is one path.** Joining separate rectangles into one preset with retraced bridges draws the bridges as visible lines in the Border variant, and the Fill variant draws nothing. Every closed outline (building, block, island) needs its own shape widget.
5. **Cost scales with drawn points and is paid every frame, even when static.**

   | scenario | points | Δ frame avg |
   |---|---|---|
   | 1000 × tri (preset) | 3k | +0.35 ms |
   | 300 × road_200 | 60k | +2.95 ms |
   | 100 × road_2000 | 200k | +16.3 ms |
   | 300 × road_2000 | 600k | +50.5 ms |
   | 300 × road_2000, animated parent pan+zoom | 600k | +52.0 ms (transform is free) |
   | 1000 drawn custom-vertex shapes (spike 2, V2 = preset triangles) | 3k | +2.1–2.4 ms |
   | 1000–4000 non-drawing widgets | 0 | ~0 to +1.7 ms |
   | 4000 inkRectangle / inkQuadShape (spike 1) | n/a | +25–35 ms (per-widget cost at high counts) |

   The rule of thumb is about 15–20k drawn points per ms. With the +2 ms map budget, that allows roughly **30k points on screen** and a few hundred widgets. Shapes probably cost the same off-screen, so only visible cells should be attached.
6. **The HUD virtual window is about 2560×1440 units at this resolution**, not 3840×2160.

## Consequences for the design

- **Geometry:** all of it is prebuilt by the pipeline into shape resources, organised per LOD level and grid cell, with presets named by cell and feature.
- **Pan and zoom:** handled by transforming a parent canvas. Line thickness is updated per zoom step, and points are never rebuilt at runtime.
- **Detail budget:** this comes from generalisation (simplification and LOD selection) in the pipeline. The budget is about 30k visible points and a few hundred visible shapes at any zoom.
