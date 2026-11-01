# Task 4 report

Status: DONE_WITH_CONCERNS.

## Chosen values (cyan / green)
- bfill: single tint #2f6fae (green #2fae59) at opacity 0.60 (one tint cannot carry both fill and dots; chosen so dots read and buildings stay the dimmest city layer, above nothing but outline in the test ladder).
- outline #3a8fd0 @ .40; road_minor #2a86d8 @ .60; road_major #8fdcff @ .90; glow #2f9cff @ .50 (glow no longer uses HoloAccent; green mirrors at hue 140, same lightness/saturation).
- Background cyan #050d18, green #041008. Scan .14, grid .08, rings .10, vignette .55, rings 1440 4K units.
- Dot grid: holo_grid 48px tile / 24px period tiles at native size in ink units (3840x2160 virtual canvas), so 24 px at 4K and 12 px at 1080p: inside 12-24 px target; no change needed.
- Stack: grid | tiles | vignette | noise | routes | items | scanlines | bar | overlay. Player rings sit under the arrow in the overlay.

## Tests
- Soak 20261101-024916-render: TEST|SUMMARY|passed=400|failed=0 (no new failures; the known failures did not appear in this run).
- New/changed PASS: tiles.five_sets_order, holo.effects_off_drops_glow_layer (4/5), theme.roads_brighter_than_buildings, holo.rings_only_with_effects, holo.rings_follow_player.
- RED was not captured separately (implemented tests and code together; check.sh compiled).
- render.json takes no screenshots (shoot_on hold never fired), so I ran a scratch plan (not committed) 20261101-025421-look: screens in .soak/results/20261101-025421-look/probe-1/screens/z0.5.png, z2.png, z8.png, z16.png. Read z2.png.

## Visual verdict (z2.png vs map-look.jpg)
Roads clearly over buildings, building dot matrix visible, outlines and glow present, vignette and rings faintly visible around the arrow. Concerns: the whole map reads far brighter and teal-green than the mockup because the panel background is see-through (default panel opacity 0.45, world shows through), not the dark navy of the mockup; the spec's map background opacity .92 is not applied by this task. Major/minor road contrast is modest. z0.5/z8/z16 not inspected.

## Fix round 1
Changes: bfill #1b4a78 @ 0.40 (green #1b783a); noise opacity 0.04 with flicker 0.027-0.047; scan bar 0.12; grid left at 0.08 (dots, small coverage) and edge glow untouched (frame edges only). Ladder test now road_major > road_minor > outline > bfill for both themes: buildings are dimmest, as the mockup reads (the old bfill > outline order made buildings a solid fill). Comments above AddNoise/AddScan fixed. Rings size = RingsSize() * l.scale, l.scale = min(winW/3840, winH/2160) (Panel.reds:22), so 720 px at 1080p (1440 units x 0.5 -> 720 screen px... in ink units 1440 x scale).
Self tests: soak 20261101-025856-render: TEST|SUMMARY|passed=400|failed=0.
look.json committed at tools/soak/plans/look.json; run 20261101-030344-look, screens in .soak/results/20261101-030344-look/probe-1/screens/ (z0.5.png, z2.png, z8.png, z16.png).

Verdicts vs map-look.jpg (panel is still see-through 0.45, Task 8, so the world shows through as a brown/teal tint; not tested at .92):
- z0.5: roads clearly over buildings; major roads (wide, pale cyan) clearly brighter than minor (mid blue); building outlines thin and dim; dots faintly visible on buildings; background dark navy-teal but world bleeds through on the left. Good.
- z2: roads over buildings, major vs minor readable, buildings dim, dots visible at this scale; wash much reduced vs first round; background still lifted by see-through.
- z8: city is a small dim cluster, roads visible as bright lines; rings strong and bar band visible mid-sweep (the sweep is the brightest overlay here); background dark navy.
- z16: same; tiny city, dark navy, rings prominent. Concern: the range rings read stronger than the 0.10 opacity suggests when zoomed out because they are screen-sized; Task 8/tuning may want them lower.
