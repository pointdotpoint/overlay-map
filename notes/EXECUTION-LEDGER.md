# SDD ledger — plan: docs/superpowers/plans/2026-10-11-overlaymap-core.md

Spec: docs/superpowers/specs/2026-10-11-overlaymap-core-design.md (reachable, approved)
Branch: feat/overlaymap-core (from main @ 09a91b7)

## Preflight rulings
- Ruling: all subagents (implementers, task reviewers, re-reviewers, final reviewer) run on model `sonnet` — user's explicit instruction ("subagent-driven using sonnet 5.5 for the subagents") overrides the skill's "most capable model for final review" — cost if wrong: final review may miss subtle cross-task issues a stronger model would catch.
- Ruling: plan deviations D1–D6 are accepted — user set the goal "execute the plan" after the plan presented them for review — cost if wrong: rework of calibration gate / tile format / cluster rule / budgets if the user objects later.
- Ruling: Tasks 11 and 16 (human in-game checkpoints) are run by the controller with the user, not by subagents — subagents cannot drive the game — cost if wrong: none (they produce only notes/CHECKPOINTS.md; any fixes go back through implementer dispatches).
- Ruling: Task 1 overwrites the existing one-line .gitignore with the plan's version (which still includes .superpowers/) — the plan's version is a superset — cost if wrong: none.

## Preflight scan
| Tasks | Shared file / interface | Producer → consumer | Finding |
|---|---|---|---|
| T5 ↔ T8 | UI atlas part sizes | ui_atlas.SIZES → NMTheme.*Size() | match (112/136/176/200/80/216/112/110/48) |
| T5/T7 ↔ T8/T10/T13/T14 | UI atlas part names | ui_atlas parts → NMUi.Image parts | match (chip, chip_sel, cluster, cluster_sel, mini, ring, player, bracket_*, icon_*) |
| T6 ↔ T7 | templates/tile.xbm.json, atlas.inkatlas.json | T6 creates → build.py loads | match |
| T7 ↔ T8–T15 | Generated/TileManifest.reds | emit_manifest functions → NMTileManifest.* calls | all called functions emitted (Available, LevelCount/Mpp/OriginX/OriginTop/Nx/Ny/Tiles, WorldMin/Max) |
| T7 ↔ T12 | tile depot path `overlaymap\tiles\L{i}\t_{ix}_{iy}.inkatlas` part `full` | build.py → TileLayer ResRef string | match |
| T1 ↔ T8+ | tools/check.sh deps (Codeware, RedIMG, ModSettings scripts) | check.sh → @if(ModuleExists) code | match |
| T8 ↔ T9,T10,T12,T13,T14 | Debug/SelfTest.reds Run() | each task appends a case group call | consistent append order |
| T9 ↔ T10 | Core/OverlayMapSystem.reds | T9 minimal → T10 replaces whole file (keeps Api()) | consistent |
| T10 ↔ T12/T13/T14 | OnOpened/OnClosing/UpdateModules hooks | T10 empty hooks → later full replacements | each replacement supersedes prior, consistent |
| T13 ↔ T15 | HandleDebug | T13 version ends with debugPerf/debugCalib=false lines → T15 replaces those two lines | consistent |
| T10 ↔ T15 | Tick() | T10 defines → T15 replaces (adds perf, raw dt) | consistent |
| T13 ↔ T14 | renderer candidates, candSlot, clCats/clCatCount/clCatN, clWx/Wy/World/Total, selChip/selCluster | renderer fields → crosshair/card/Activate | names match |
| T9 ↔ T13 | layer internals (cnt,sumX,sumY,tally,head,nextIn,catGlobal,...) | OverlayMapLayer public fields → renderer | names match |
| T13 ↔ T15 | NMDebugLayer.Fill/Remove/Id | debug layer → perf suite | match |

| Task | Self-consistency (tests vs code, files created vs touched) |
|---|---|
| T1 | ok; .gitignore pre-exists (ruled above) |
| T2 | 8 tests ↔ glb/world/export code consistent; real-export step writes gitignored build/ |
| T3 | test grid math (nx=2,ny=1 → 2 tiles) consistent with level_grid |
| T4 | test uses 4x4 crossing markers; fit search covers ±30 m offsets; consistent |
| T5 | SIZES fit 1024 shelf pack; pointy-top test coordinates consistent with _hex_points |
| T6 | bc7_layout values match template (4112/1056784); slow test opt-in |
| T7 | manifest tests match emitter formatting; build writes manifest path used by T8+ |
| T8 | Step 4 carries an explicit fallback if `@if` on import is rejected |
| T9 | GridCases ids/edges consistent with NMGrid extent & default world |
| T10 | Input/Layout cases consistent with NMInput/NMPanelLayout |
| T11 | human checkpoint (controller-run) |
| T12 | TileCases need real manifest (T7 ran) — else reports a clear FAIL |
| T13 | RendererCases conservation relies on DebugLayer margins (1 km inside bounds) — consistent |
| T14 | PickCases consistent with Pick stickiness rule (≤ best+4) |
| T15 | results tests consistent with parse/verdict; Tick raw dt fixed in plan |
| T16 | human checkpoint (controller-run) |
| T17 | docs only |

## Progress
Task 1: dispatched (base 09a91b7, implementer sonnet)
Task 1: complete (commits 09a91b7..31446a3, review clean) — deviation: check.sh wraps scc in `timeout -k 5 90` (scc hangs after compile errors)
Task 1: minor (deferred): check.sh failing path waits full 90s; could poll log for ERROR and kill early
Task 1: minor (deferred): check.sh `grep -q "ERROR"` unanchored (plan-mandated); `^\[ERROR` more robust
Task 1: minor (deferred): install.sh rm -rf before cp is non-atomic
Task 2: dispatched (base 31446a3, implementer sonnet)
Task 2: complete (commits 31446a3..b46cc23, review clean)
Task 2: minor (deferred): glb.py doesn't validate chunk types/bounds; bare numpy error if index count % 3 != 0
Task 2: minor (deferred): Transform.load silently returns default when calibration.json missing (plan-mandated)
Task 2: minor (deferred): no tests for strided/non-indexed primitives or node-transform rejection
Task 3: dispatched (base b46cc23, implementer sonnet)
Task 3: complete (commits b46cc23..2e14729, review clean)
Task 3: minor (deferred): FIND_EDGES leaves 1px border unprocessed -> spurious outline at level edge
Task 3: minor (deferred): building height normalization hardcoded /150 from untransformed y
Task 3: minor (deferred): glow alpha math truncates (a*g//255*2); no tests for outline/glow/height paths; per-triangle Python loop slow
Task 4: dispatched (base 2e14729, implementer sonnet)
Task 4: complete (commits 2e14729..fc26dd1, review clean)
Task 4: minor (deferred): calib parser float() can raise on malformed numbers; rejects exponent/+ forms
Task 4: minor (deferred): calib CLI: no guards for missing gamelog / no road meshes (np.vstack([]) traceback); no warning when best offset hits ±search edge
Task 5: dispatched (base fc26dd1, implementer sonnet)
Task 5: review approved (fc26dd1..c89fa6d) with 2 plan-mandated cosmetic findings
Ruling: fix Task 5's plan-mandated glow (blur RGB toward black -> muddy halos) and hex vertex speck (unclosed stroke polyline) now — these parts carry the user-approved visuals and the fix is one file — cost if wrong: one small extra fix round.
Task 5: minor (deferred): SIZES test compares constant to itself; visible-pixels test weak; no bracket-flip asymmetry test
Task 5: fix round 1/5 (2 addressed, 0 open — glow halo white, hex vertex join; commits c89fa6d..687b86d)
Task 5: complete (commits fc26dd1..687b86d, review clean)
Task 6: dispatched (base 687b86d, implementer sonnet)
Ruling: accept Task 6 plan corrections — encode.py maps paths to Z:\ for texconv (leading / parsed as a switch under Wine); slow test uses random-noise PNG because WolvenKit Kraken-compresses xbm buffers — plan text was wrong, behaviour unchanged — cost if wrong: none
Task 6: complete (commits 687b86d..20cfa29, review clean) — ⚠️ archive ≤60MB checked in Task 7 build; BuildVersion=size verified in-game at Checkpoint 1/2 (tiles load)
Task 6: minor (deferred): encode.py missing-DDS raises FileNotFoundError before RuntimeError; texconv stderr discarded
Task 6: minor (deferred): pack.write_resource leaves stale .json on convert failure (no try/finally); slow test checks sizes only, no payload round-trip
Task 7: dispatched (base 20cfa29, implementer sonnet)
Ruling: Task 7 pack batches WolvenKit `convert d <workspace>` once instead of one process per resource (682×~12 s ≈ 2 h → ~12 s); verified byte-identical xbm/inkatlas output — cost if wrong: none (fallback is per-file loop)
Ruling: building footprints are missing because the 3dmap mesh set holds no building geometry (triangle_soup/coll_buildings are stubs; landmarks are local-space props at origin) — spec §tile pipeline assumed otherwise; approved street mockup shows buildings, so they are NOT dropped: a research subagent finds the real source (world proxy/sector geometry) in parallel; the fix lands as a pipeline follow-up task (T7b) before Checkpoint 2's visual review, and local-space landmark meshes get excluded there — cost if wrong: Checkpoint 1 sees roads/metro/water only (acceptable; it tests the panel, not visuals)
Task 7: review dispatched (sonnet); building-source research dispatched (sonnet, read-only, scratchpad/buildings/FINDINGS.md)
Task 7: complete (commits 20cfa29..1d45816, review clean) — deviation: pack batches `convert d` (ruled above); archive 3.4 MB; L0 256 tiles (±8 km terrain bounds)
Task 7: minor (deferred → fold into T7b): encode_bc7 has no cache (~35 min re-encode even with --skip-export)
Task 7: minor (deferred): opaque np.vstack error when no meshes styled; >60 MB only warns; _f .1f origin formatting; no build.py test
Task 8: dispatched (base 1d45816, implementer sonnet)
Task 8: implementer DONE (21757c3); controller verified !ModuleExists(RedIMG) fallback compiles; review dispatched (sonnet)
Task 8: review approved (1d45816..21757c3)
Ruling: fold two reviewer minors into Task 8 now — SelfTest counter reset per Run (plan-mandated bug: repeat runs misreport) and ZoomBy/SetCenter/SetMpp cancel an active ease (user zoom during recenter would be overwritten) — both are user-visible at Checkpoint 1 — cost if wrong: one tiny fix round
Task 8: minor (deferred): pan dy sign / visible_rect center+margin / ease midpoint untested; Create no guard minMpp<=0, hardcoded initial mpp 4.0; mpp lerped linearly not log-space; HeadingDeg (-180,180] undocumented; Theme allocs HDRColor per call
Task 8: fix round 1/5 dispatched (resume implementer)
Task 8: fix round 1/5 (2 addressed per implementer, d897844) — re-review dispatched
Note: T9/T10+/T12–T14 Run() replacements in the plan predate the counter reset — each dispatch must keep the passed/failed reset lines; Camera SetCenter/SetMpp now cancel ease (Tick uses private ApplyCenter/ApplyMpp)
Task 8: complete (commits 1d45816..d897844, review clean after fix round 1)
Task 8: minor (deferred): SetMpp cancels ease even at clamp limit (follow path already guards with !IsEasing, plan l.3726); PanPixels redundant easing=false
Task 9: dispatched (base d897844, implementer sonnet)
Task 9: implementer DONE (7c81b59); review dispatched (sonnet)
Task 9: fix round 1/5 (3 addressed per implementer, e48585b) — re-review dispatched
Task 9: complete (commits d897844..e48585b, review clean after fix round 1)
Task 9: minor (deferred): SelfTest per-item reachability walk has no step cap (hangs only on already-corrupt lists); 0.5 sum tolerance may false-fail at very high per-cell counts
Task 10: dispatched (base e48585b, implementer sonnet)
Task 10: implementer DONE_WITH_CONCERNS (0d57a76; Close() null-guard at session end; clip/HudWindow/settings lookup unverified in-game); review dispatched (sonnet)
Task 10: review needs fixes (e48585b..0d57a76): Important — unguarded HudWindow chain on teardown (OnDetach→Close); held keys not reset on Close
Ruling: accept plan-mandated panel scale MinF(winW/3840, winH/2160) over the Global Constraint's winW/3840 — correct for 16:10/ultrawide, constraint wording was loose — cost if wrong: none visible at 16:9
Ruling: fold diagonal-pan normalization + chord-priority self-test cases into Task 10 fix round 1 — cheap, user-visible — cost if wrong: none
Task 10: minor (deferred): arrowSeen NumLock hint never displayed; layout self-test tautological (mapW==w*0.70); Ctrl+Alt+\ counts as self-test; Shift/Ctrl+\ swallowed with Debug off; no auto-close on loading/menu; dead frameNo field
Task 10: fix round 1/5 dispatched (resume implementer)
Task 10: fix round 1/5 (3 addressed per implementer, 222efc7) — re-review dispatched
Task 10: complete (commits e48585b..222efc7, review clean after fix round 1)
Task 11: installed (HEAD 222efc7, archive 3.4 MB); gamelog baseline 6952 lines; waiting on user in-game steps
Building research 1 (proxy meshes): partial — worldBuildingProxyMeshNode proxies cover west/north only; downtown core is modular kit pieces (impractical). Scratch: scratchpad/buildings/
Building research 2 (controller): vanilla per-district building-outline masks found — base\fx\textures\3dmap\static\*_m.xbm (BC4 512², city_center/heywood/santo_domingo/ep1_dogtown/ep1_spaceport/c_watson/c_westbrook/c_pacifica); decoded in scratchpad/m3d/masks.png. Placement research dispatched (sonnet).
Task 11: user step 2 — panel renders (2560x1440): header, scale bar, card column, hint bar; pink clip probe confined to map area (clipping OK); map area empty as expected pre-T12. User rebound Toggle to IK_SingleQuote (user.ini).
Task 11: self-test — all math/camera/grid/api PASS; input.toggle + input.ctrl_toggle_is_selftest FAIL: ModSettings applies saved values to class defaults so `new OverlayMapSettings()` carries the user's SingleQuote binding — test bug. Remaining lines (+SUMMARY) not yet in gamelog (game running; log likely unflushed).
Task 10: checkpoint fix round 2 dispatched — InputCases pins explicit key bindings
Ruling: Task 10 checkpoint fix round 2 (c313f03, +10 test-only lines pinning key bindings) re-reviewed by controller directly instead of a subagent — trivial, fully visible diff — cost if wrong: in-game re-run of self-test catches it
Task 10: checkpoint fix round 2 verified (222efc7..c313f03); reinstalled (applies on next game launch)
Building research 3: placement is explicit — 3dmap_triangle_soup.mesh local materials (3d_map_cubes.mt: WorldPosTex=*_data.xbm, TransMin/Max, CubeSize) + 3dmap_view.ent offsets; *_data.xbm = per-pixel oriented boxes (pos/quat/dims sections). Verified overlay m3d/box_full.png. Road frame is world=(-gltf_x,+gltf_z) (0.72 vs 0.27 density corr).
Ruling: add Task 7b (pipeline): bake vanilla building boxes as the spec's building-footprint layer, set calibration.json to sx=-1 sy=+1 (provisional; Checkpoint 2 calibration confirms), drop local-space landmark meshes, add encode cache — spec requires footprints; this is the vanilla data — cost if wrong: one more pipeline rebuild after calibration
Ruling: skip ep1_spaceport boxes (staging offset, location unconfirmed) — cost if wrong: spaceport area lacks buildings until fixed
Ruling: T7b runs before T12 (sequential implementers; T12 consumes the regenerated manifest) while Checkpoint 1 awaits the user — cost if wrong: none
Task 7b: dispatched (base c313f03, implementer sonnet)
Task 11: user results — step 4: numpad has no effect on driving (no conflict); map pan visibility deferred to Checkpoint 2 (map empty); step 5 HUD hiding pass; step 6 teardown pass (closed 20:50:30 → loaded 20:50:31); self-test re-run passed=43 failed=0
Ruling: default toggle key → IK_SingleQuote (user confirmed `\` unusable on their ABNT2 layout; user asked) — spec/plan text says `\`; docs updated in T17 — cost if wrong: US users get `'` instead of `\` (rebindable)
Task 11: notes/CHECKPOINTS.md written; commit queued until T7b implementer finishes (avoid concurrent commits); default-key change queued as a small fix after T7b
Task 7b: implementer DONE_WITH_CONCERNS (6a097e4, 049b827): 246,802 boxes, 7 districts, archive 4.6 MB, cold 50.6 min / cached 40 s; previews checked by controller (city matches mockup); review dispatched (sonnet)
Task 11: complete (notes/CHECKPOINTS.md committed e0d6975); default-key change dispatched (sonnet)
Default key: f606d0c (keyToggle IK_SingleQuote, KeyName ' mapping, key_names case) — controller verified diff
Task 12: dispatched (base f606d0c, implementer sonnet)
Task 7b: review approved (c313f03..049b827) with 2 Important guardrails: no yaw-direction-discriminating test (45°); zero boxes doesn't fail the build
Ruling: Task 7b fix round 1 queued until Task 12's implementer finishes (no parallel implementers in one worktree) — fixes are guardrails, not present defects — cost if wrong: none
Task 7b: minor (fold into fix round): encode sidecar written even if DDS missing/stale → require DDS exists & newer than PNG; --skip-export without build/bdata gives bare FileNotFoundError
Task 7b: minor (deferred): bounds from land+road only clip boxes outside silently; ep1 override relies on WolvenKit overwrite; alpha not clamped to 255
Task 12: implementer DONE_WITH_CONCERNS (f3c2e9e; field default -1 rejected by scc → set in Create); review dispatched; Task 7b fix round 1 dispatched (resume T7b implementer)
Task 12: complete (commits f606d0c..f3c2e9e, review clean)
Task 12: minor (deferred): UpdateModules no IsDefined(tiles) guard (plan-mandated, safe today); >64 tiles / 48 grid lines silently truncated; no placement-math self-test
Task 7b: fix round 1/5 (4 addressed per implementer, 32c6449) — re-review dispatched; Task 13 dispatched (base 32c6449, implementer sonnet)
Task 7b: complete (commits c313f03..32c6449 excl. r6 commits f606d0c/f3c2e9e from other tasks; review clean after fix round 1; reviewer mutation-tested the 45° tests)
Task 7b: minor (deferred): --skip-export checks only 3dmap_view.ent.json (missing soup mesh JSON → bare FileNotFoundError; missing meshes dir → np.vstack error); DDS-older-than-PNG branch untested
Task 13: implementer DONE_WITH_CONCERNS (0116def; no 'continue' in scc → if/else; -1 defaults in Create); review dispatched (sonnet)
Task 13: review needs fixes (32c6449..0116def): Important — over-budget drops raster-biased; top-6 category scan O(80×64×6) per camera frame; PlaceAllOf O(items) per relayout (plan-mandated)
Ruling: Task 13 fix — centre-outward block/chip order; top-6 from touched entries; PlaceAllOf kept + documented as small-layer-only (plan-mandated, perf measured at Checkpoint 2); fold cull-margin ≥ block size — cost if wrong: perf suite flags it at Checkpoint 2
Task 13: minor (deferred): category colour cache by index only (SetCategory recolour won't retint); cluster minis z-order under later cluster bg; DebugLayer.Fill without manifest unusable; weak LCG spread
Task 13: fix round 1/5 dispatched (resume implementer)
Task 13: fix round 1/5 (4 addressed per implementer, 28a9711; candidates now ring-ordered — T14 pick is nearest-within-radius, order-independent) — re-review dispatched
Task 13: complete (commits 32c6449..28a9711, review clean after fix round 1)
Task 13: minor (deferred): RingOrder recomputed per clustering layer; edge-clamped ring walk iterates out-of-range coords
Task 14: dispatched (base 28a9711, implementer sonnet)
Task 14: implementer DONE_WITH_CONCERNS (dfe2f39; scc: no Bool !=, -1 defaults moved; rows clamped to 6); review dispatched (sonnet)
Task 14: review approved (28a9711..dfe2f39) with 2 Important: stale cluster card on slow pan/zoom; OnSelected after GetDetails (plan-mandated)
Ruling: fold both Important + scale-bar-on-camera-revision into Task 14 fix round 1 — user-visible at Checkpoint 2 visual review — cost if wrong: one small fix round
Task 14: minor (deferred): NiceLength 10 m floor overflows bar at tiny mpp; DefaultDetails distance not live; card text has no truncation/height clamp; no OnDeselected; tie-break undocumented
Task 14: fix round 1/5 dispatched (resume implementer)
Task 14: fix round 1/5 (3 addressed per implementer, abfcdf6) — re-review dispatched
Task 14: complete (commits 28a9711..abfcdf6, review clean after fix round 1)
Task 15: dispatched (base abfcdf6, implementer sonnet)
Task 15: implementer DONE (2bc0cbf; added OnClosing perf reset); review dispatched (sonnet)
Task 15: review needs fixes (abfcdf6..2bc0cbf): Important — mid-suite close leaks debug layer; results.py judges incomplete/mixed runs, crashes on malformed lines
Ruling: fold minor "restore camera follow/mpp after suite" + "clear perf on failed Open" into fix round 1 — cheap — cost if wrong: none
Task 15: minor (deferred): suite removes debug layer even if it was on before; user pan perturbs suite path; no closed_end drift check; single 300-frame pass p95 noise; '|' in localized names
Task 15: fix round 1/5 dispatched (resume implementer)
Task 15: fix round 1/5 (c9ed69a) — re-review dispatched
Task 15: complete (commits abfcdf6..c9ed69a, review clean after fix round 1)
Task 15: minor (deferred): Close() mid-suite saves the suite's mpp as user zoom; lazy camera save cancels an active ease
Task 16: installed (HEAD c9ed69a, archive 4.6 MB); gamelog baseline 7126 lines; game currently running (needs restart); waiting on user
Ruling: run Task 17 (docs) while Checkpoint 2 awaits the user — docs-only, independent of checkpoint results; perf claim phrased as the gate target, not a result; checkpoint fixes may require a small doc touch-up later — cost if wrong: one doc edit
Task 17: dispatched (base c9ed69a, implementer sonnet)
Ruling: Task 17 (docs-only, 81 lines) reviewed by controller directly (toggle key, perf wording as gate target, commands exist) — the whole-branch final review also covers docs — cost if wrong: doc fix in final wave
Task 17: complete (commits c9ed69a..b151ca5)
Ruling: dispatch the final whole-branch review (sonnet, per user instruction) while Checkpoint 2 awaits the user; its findings and checkpoint fixes go into one fix wave, then a scoped re-review — cost if wrong: checkpoint fixes land after the review and are covered only by the scoped re-review
Final review: dispatched (base 09a91b7, head b151ca5)
Final review: With fixes — Important: missing-archive warning absent when manifest present; game-version check (spec §9) unimplemented; calibration dx/dy not applied to building boxes
Ruling: final fix wave = 3 Important + cluster identity by block key, image-retry cap, clear selection on layer removal, dashed metro (spec §5 / approved mockup), README requirements, api.md ModuleExists note — cost if wrong: one scoped re-review round
Ruling: apply only calibration translation (dx,dy) to building boxes, not axis signs — boxes already sit in the rotated 3dmap frame alongside roads — cost if wrong: buildings offset from roads by the calibrated delta (visible at Checkpoint 2 rebuild)
Ruling: defer — key handler firing in menus/text fields (panel already hides with HUD; low impact); stale plan wording (scale formula, `\` key) — plan is historical, README/code are right — cost if wrong: toggle can flip while typing `'` in a text field
Ruling: no tile rebuild in the fix wave; controller rebuilds once after Checkpoint 2 calibration (covers dashed metro + any transform change) — cost if wrong: none
Final fix wave: dispatched (sonnet)
Final fix wave: done (549d4f7; 9/9 items; tiles 46 passed/1 skipped, results 8 passed, COMPILE OK) — scoped re-review dispatched
Rebuild 2 (dashed metro, transform unchanged sx=-1 sy=1) started in background by controller
Final re-review: 8/9 addressed; open — version compare false-warns on "2.3.1" / "2.31 (build …)"
Ruling: residual is load-bearing (false "rebuild tiles" warning to every user if the runtime format differs) — fix with silence-on-uncertainty normalisation + self-test cases, controller verifies the small diff — cost if wrong: in-game check at Checkpoint 2 shows the raw version in the log
Final review: minor (deferred): dash axis per triangle wrong for thick shapes (platforms); dash phase across tiles / solid fallback untested; images resolving after retry cap show on next relayout
Final residual fixed (8b51d7a): Normalise() leading digits.digits, 1-digit minor joined with patch, unknown → silent + one log; 6 self-test cases — controller verified diff
Final review: complete (b151ca5..8b51d7a: fix wave 549d4f7 + residual 8b51d7a)
Task 16: reinstalled final build (HEAD 8b51d7a, rebuild 2 archive 4.6 MB, dashed metro); waiting on user
Task 16: user ran checkpoint 2 (2026-10-12 08:35–08:40). Self-test passed=65 failed=1 (tiles.level0_has_tiles). Calibration: 137 FT points; calib fit signs sx=-1 sy=+1 (confirms T7b frame fix), offset (-10,16) median 0.0 m.
Ruling: keep calibration offset (0,0) — the offset surface is flat (controller check: median 4.47 m at both (0,0) and (-10,16); mean 12.4 vs 13.1 m; best-mean (6,12) only 0.5 m better) so the fitted offset is noise; D1 gate met (median ≤ 15 m, signs fitted, offset within ±50) — cost if wrong: ≤ ~15 m map shift, fixable by a calib re-run + cached rebuild
Task 16: perf PASS (run 1, 08:37): items_50000 avg +0.90 ms (budget 3.0), p95 +3.70 ms (budget 6.0); run 2 (08:39) incomplete (no done), partial numbers similar
Task 16: self-test FAIL tiles.level0_has_tiles — LevelTiles(0) 256-element array literal empty at runtime (hypothesis: >255 literal limit) → L0 (finest) tiles never shown; fix dispatched (chunked literals ≤128, regenerate manifest, sonnet)
Task 16: level-0 fix ddf036c (chunked literals ≤128; manifest diff only L0) verified by controller; reinstalled; gamelog baseline 8332; awaiting user re-check + visual answers
Task 16: re-run after ddf036c (compiled 08:50:49, version cases present) still FAIL tiles.level0_has_tiles → >255-literal hypothesis refuted (chunking kept, harmless). LevelMpp switch works. New hypothesis: ArraySize(<call temporary>) reads 0; test flawed, TileLayer (for-in) may be fine. Diagnostic self-test dispatched (locals + per-level counts + temp-form comparison). User visual answer (zoomed-in tiles?) also decides it.
Task 16: diagnostic 1a15458 + TileLayer local binding (controller edit) installed
Task 16: perf run 3 (08:53, complete): PASS: items_50000: avg +0.69 ms (budget 3.0), p95 +3.43 ms (budget 6.0)
Task 16: user screenshots 09:37 — L0 tiles DO render (self-test was flawed; level0 fixed via local binding/diagnostic), header district "LITTLE CHINA" + scale bar (2 KM / 100 M) live, clipping OK.
Task 16 bugs: (1) low-alpha tiles render near-opaque light blue — ink blends premultiplied, tiles are straight alpha (D2 wrong); (2) tiles vertically flipped (seam gap = top/bottom transparent margins; city at far edges). Title readable once colours fixed (z-order fine).
Ruling: fix both in the encode step for ALL textures incl. UI atlas (premultiply + vflip), cache key includes options, full re-encode (~50 min) — D2 "straight alpha" overturned by in-game evidence — cost if wrong: one more re-encode
Task 16: encode fix dispatched (sonnet)
Task 16: encode fix f209012 (texconv -pmalpha -vflip, verified by decode; archive 5.5 MB); installed
Task 16: user screenshot 10:58 after encode fix — colours now translucent hologram, no row gap, city layout plausible, player arrow near Little China (header matches), cluster card works ("4 LOCATIONS", per-category rows, NUM 0 action). Map tinted pink by the checkpoint-1 clip probe overlay.
Task 16: user issues — (a) map pixelated, wants smooth "SVG-like"; (b) zoom too slow (1.5×/s); (c) "markers all over the place" = debug layer's 5,000 random synthetic items (expected; real pins are sub-project 2)
Ruling: zoom rate → 4×/s (NMTheme constant); remove clip probe — cost if wrong: none (tunable)
Task 16: zoom/probe fix dispatched (sonnet); smoothness = design decision → asked user
Task 16: diagnostic self-test 11:44 — passed=67 failed=0; per-level counts 256/64/16/4; level0_temp_count=0 → root cause confirmed: ArraySize(<call temporary>) returns 0 in-game (test bug; TileLayer for-in already worked, now bound to a local anyway)
Task 16: zoom 4×/s + probe removal (36b12de) installed
User decision: pixelation → "Vector shapes up close" (inkShape vector layer at close zoom; tiles for far zoom) = new sub-project 1b (brainstorm/spec/plan after this branch); inkShape API confirmed in Codeware (vertexList, lineThickness, fill/border)
Task 16: CHECKPOINTS.md checkpoint-2 section drafted (arrow/NumLock/zoom-feel pending user)
Task 16: user — arrow correct, NumLock off OK, zoom 4×/s good. Checkpoint 2 notes committed. Task 16: complete (pending scoped review of 8b51d7a..36b12de)
Checkpoint-fix review (8b51d7a..36b12de): findings adjudicated — (c) UI atlas vflip OK per in-game evidence (brackets/icons upright, arrow confirmed); (a) LayerOrder for-in works in-game (chips render) but bound to a local for consistency + temp-count diagnostic removed (12d6dd1, controller edit, COMPILE OK); (b) pmalpha tinting fine
Task 16: complete
All tasks complete.
