# NightMap Vanilla Markers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show every vanilla world-map marker on the NightMap overlay with the vanilla look, plus info-card details,
quest tracking, filters and a tracked-quest header.

**Architecture:**
- A new `r6/scripts/NightMap/Vanilla/` module polls the game's mappin system while the map is open. It diffs the
  snapshot by `NewMappinID.value` in an `inkHashMap`, and mirrors visible markers into one NightMap layer per vanilla
  filter category, plus a `Vanilla.Pinned` layer for tracked markers.
- The public layer API gains a per-layer **Icon pin style** (the vanilla icon over a shadow blob, with idle dimming and
  emphasis), per-item emphasis and opacity, and in-place `Update`.
- Everything is built on the existing renderer pools, so it costs nothing while the map is closed.

**Tech Stack:**
- redscript (game 2.31) with Codeware, compiled offline by `tools/check.sh`.
- In-game self-tests (`Debug/SelfTest.reds`, Ctrl + toggle key with Debug on).
- Python 3 + pytest for `tools/results.py`.

**Spec:** `docs/superpowers/specs/2026-10-13-nightmap-vanilla-markers-design.md`. Spike evidence is in
`docs/superpowers/specs/2026-10-13-vanilla-markers-spike/`: `FINDINGS.md`, `RESEARCH.md`, `LOOK.md`,
`variant_table.txt` and `filters.txt`.

## Global Constraints

**Spec and branch**
- Spec §1 decisions are binding:
  - the vanilla look (vanilla icon, colour and opacity behaviour); hex chips only for clusters and other mods' items;
  - waypoint creation and non-quest tracking are deferred to sub-project 3;
  - overlapping markers cluster when zoomed out;
  - the first open starts fully zoomed in (already done, f407623).
- Product constraints (spec 1b §11.5): very light at runtime, a state-of-the-art look, themeable, layers ready for
  photos, widgets and POIs.
- Branch `feat/vanilla-markers`. Never commit to `main` or `feat/vector-layer`.

**redscript rules**
- These constructs are not allowed:
  - `continue`;
  - Bool `!=` (use `NotEquals(a, b)`);
  - negative field defaults;
  - static field access;
  - array literals longer than 128.
- `ArraySize(...)` or a field access on a function-call temporary reads 0 or the default. Always bind to a local first.
- All files declare `module NightMap`.
- Log only through `NMLog.Info` / `NMLog.Error`. Machine-readable lines use `|` separators.

**Checks and commands**
- Compile check: `nice -n 19 tools/check.sh` must print `COMPILE OK`.
- Python: `cd tools && nice -n 19 python3 -m pytest -q` must pass.
- Run every heavy command at `nice -n 19`.
- Never write to `/tmp`. Scratch goes in `~/nightmap/.scratch/`.
- Never run `tools/install.sh` (the controller installs, with the game closed). Never run the tile build.

**Commits**
- Commit messages end with a blank line, then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Performance**
- Zero work while the map is closed. While open, the marker poll runs at most every 1500 ms.
- Perf gates (from `tools/results.py`):

  | rows | avg | p95 |
  |---|---|---|
  | `open_empty`, `panzoom_0p5_16`, new `vanilla_open` | +1.5 ms | +3.0 ms |
  | idle rows | +1.0 ms | +2.0 ms |
  | `items_50000` | +3 ms | +6 ms |

  The verdict is the median of 3 runs, with the drift rule.

**Vanilla data**
- Icon atlas: `base\gameplay\gui\common\icons\mappin_icons.inkatlas`. Shadow: `base\gameplay\gui\common\shadow_blobs.inkatlas`,
  part `shadowBlobSquare_big`.
- Atlas parts missing from the game: `failed_crossing`, `relic_dataterm`.

## Review Focus

1. **A visible vanilla marker of a variant missing from the filter catalogue** must still show, in `Vanilla.Other`, and
   be logged once. Test: Task 3 `vanilla.catalog_unknown_is_other`; Task 5 `vanilla.unknown_variant_logged_once`.
2. **A marker whose phase, visibility or tracked state changes between polls** must update (move layer, hide or show),
   not go stale. Test: Task 4 diff cases `diff.phase_completed_removes`, `diff.tracked_moves_to_pinned`,
   `diff.invisible_removes`.
3. **NUM 0 on a POI** whose journal hash resolves to an entry outside the Quest/SecondaryQuest groups must not track
   anything. Test: Task 3 `vanilla.track_rules`; Task 6 `vanilla.no_track_action_for_vendor`.
4. **Icon variants** whose atlas part is missing or `invalid` must draw a fallback, never a blank or crash. Test: Task 3
   `vanilla.part_fallback`.
5. **A reused renderer slot** must not keep the previous item's grow scale or style (selection moves on, then pan).
   Test: Task 2 `icons.grow_resets_on_reselect`, `icons.style_switch_resets_size`.

---

## File structure

| File | Status | Responsibility |
|---|---|---|
| `r6/scripts/NightMap/Api/NightMapItem.reds` | modify | `emphasis`, `opacity` fields + `WithEmphasis`, `WithOpacity` |
| `r6/scripts/NightMap/Api/NightMapLayer.reds` | modify | `NightMapPinStyle` enum, `pinStyle`, per-item `emph`/`alpha`, `SetPinStyle`, `Update`, shared `Store` |
| `r6/scripts/NightMap/Core/Theme.reds` | modify | vanilla atlas paths, sizes, opacities, state → colour table |
| `r6/scripts/NightMap/Render/ItemRenderer.reds` | modify | Icon style in `PlaceChip`, per-slot style cache, selection grow (`ApplySelection`) |
| `r6/scripts/NightMap/Vanilla/Style.reds` | create | `NMVanillaStyle`: variant/phase → state, colour, icon part (with fallback), quest-trackable |
| `r6/scripts/NightMap/Vanilla/Catalog.reds` | create | `NMVanillaCatalog`: the 12 vanilla custom filters from TweakDB, variant → filter index, layer ids, priorities |
| `r6/scripts/NightMap/Vanilla/Diff.reds` | create | `NMVanillaSnap`, `NMVanillaEntry`, `NMVanillaRules`, `NMVanillaSink`, `NMVanillaDiff` (pure, no game state) |
| `r6/scripts/NightMap/Vanilla/Vanilla.reds` | create | `NMVanilla`: owns layers, polls MappinSystem, applies diffs, filters, details, actions; `NMVanillaListener` |
| `r6/scripts/NightMap/Vanilla/Text.reds` | create | `NMVanillaText`: LocKey resolution, titles |
| `r6/scripts/NightMap/Vanilla/Tracking.reds` | create | `NMVanillaTracking`, `NMQuestInfo`: journal lookup, track quest, clear/untrack |
| `r6/scripts/NightMap/Vanilla/QuestHeader.reds` | create | `NMQuestHeader`, `NMQuestHeaderInfo` |
| `r6/scripts/NightMap/Vanilla/Filters.reds` | create | `NMVanillaFilters`: quick views × settings toggles |
| `r6/scripts/NightMap/Core/Settings.reds` | modify | `keyFilter` + 12 filter Bools ("Map filters") |
| `r6/scripts/NightMap/Core/Input.reds` | modify | `filter` flag, hint text |
| `r6/scripts/NightMap/Render/Panel.reds` | modify | quest header texts |
| `r6/scripts/NightMap/Core/NightMapSystem.reds` | modify | own `NMVanilla`, poll in `UpdateModules`, `ApplySelection`, header, filter key, `SetVanillaEnabled` |
| `r6/scripts/NightMap/Debug/SelfTestVanilla.reds` | create | `NMVanillaTests`: all new self-test groups (keeps `SelfTest.reds` from growing) |
| `r6/scripts/NightMap/Debug/SelfTest.reds` | modify | call `NMVanillaTests.Run(this)`; make `Check`/`Near` usable (already public) |
| `r6/scripts/NightMap/Debug/PerfSuite.reds` | modify | per-scenario vanilla on/off, `vanilla_open` row, `script_max` |
| `tools/results.py`, `tools/test_results.py` | modify | gate `vanilla_open` as a sweep row |
| `docs/api.md`, `README.md` | modify | new API, markers and filters |

---

### Task 1: Layer API: pin style, emphasis, per-item opacity, in-place Update

**Files:**
- Modify: `r6/scripts/NightMap/Api/NightMapItem.reds`
- Modify: `r6/scripts/NightMap/Api/NightMapLayer.reds`. Add fields after `prio` (line 36). `Add` is at lines 68-104,
  `Clear` at 135-158 and `Grow` at 268-291.
- Create: `r6/scripts/NightMap/Debug/SelfTestVanilla.reds`
- Modify: `r6/scripts/NightMap/Debug/SelfTest.reds` (`Run()`, line 9)
- Modify: `docs/api.md`

**Interfaces:**
- Consumes: the existing `NightMapLayer` storage, `Link`/`Unlink`, `LocalCat`, `Touch` and `WarnOnce`.
- Produces:
  - `public enum NightMapPinStyle { Hex = 0, Icon = 1 }`
  - `NightMapLayer.pinStyle: Int32` (0 hex, 1 icon); `NightMapLayer.emph: array<Bool>`; `NightMapLayer.alpha: array<Float>`
  - `NightMapLayer.SetPinStyle(style: NightMapPinStyle)`
  - `NightMapLayer.Update(id: Int32, item: ref<NightMapItem>) -> Bool`
  - `NightMapItem.emphasis: Bool`; `NightMapItem.opacity: Float` (default 1.0)
  - `NightMapItem.WithEmphasis(on: Bool) -> ref<NightMapItem>`; `NightMapItem.WithOpacity(a: Float) -> ref<NightMapItem>` (clamped 0..1)
  - `public abstract class NMVanillaTests { public static func Run(t: ref<NMSelfTest>) }`

- [ ] **Step 1: Write the failing self-tests**

Create `r6/scripts/NightMap/Debug/SelfTestVanilla.reds`:

```swift
module NightMap

// Self-test groups for sub-project 2 (vanilla markers). Called from NMSelfTest.Run().
public abstract class NMVanillaTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMVanillaTests.PinApiCases(t);
    }

    private static func TestApi() -> ref<NightMap> {
        let api = NightMap.Create();
        api.SetWorld(-6000.0, -4600.0, 4600.0, 7400.0);
        return api;
    }

    private static func PinApiCases(t: ref<NMSelfTest>) {
        let api = NMVanillaTests.TestApi();
        let L = api.CreateLayer(n"test.pins", "Pins", 5);
        t.Check("pins.default_style_hex", L.pinStyle == 0, "");
        let rev = api.revision;
        L.SetPinStyle(NightMapPinStyle.Icon);
        t.Check("pins.set_style_icon", L.pinStyle == 1 && api.revision > rev, ToString(L.pinStyle));
        let it = NightMapItem.Create(new Vector4(10.0, 20.0, 0.0, 1.0), n"a", r"x\\y.inkatlas", n"p");
        let id = L.Add(it);
        t.Check("pins.item_defaults", !L.emph[id] && L.alpha[id] == 1.0, "");
        let it2 = NightMapItem.Create(new Vector4(30.0, 40.0, 0.0, 1.0), n"b", r"x\\y.inkatlas", n"q").WithEmphasis(true).WithOpacity(0.7).WithLabel("two");
        rev = api.revision;
        let ok = L.Update(id, it2);
        t.Check("pins.update_in_place", ok && L.emph[id] && t.Near(L.alpha[id], 0.7, 0.001) && Equals(L.part[id], n"q")
            && L.px[id] == 30.0 && L.py[id] == 40.0 && Equals(L.Label(id), "two") && L.count == 1 && api.revision > rev, "");
        t.Check("pins.update_dead_id_fails", !L.Update(99, it2), "");
        let far = NightMapItem.Create(new Vector4(90000.0, 0.0, 0.0, 1.0), n"a", r"x\\y.inkatlas", n"p");
        t.Check("pins.update_out_of_bounds_fails", !L.Update(id, far) && L.px[id] == 30.0, "");
        let clampHi = NightMapItem.Create(new Vector4(0.0, 0.0, 0.0, 1.0), n"a", r"x\\y.inkatlas", n"p").WithOpacity(3.0);
        let clampLo = NightMapItem.Create(new Vector4(0.0, 0.0, 0.0, 1.0), n"a", r"x\\y.inkatlas", n"p").WithOpacity(-1.0);
        t.Check("pins.opacity_clamped", clampHi.opacity == 1.0 && clampLo.opacity == 0.0, "");
        L.Remove(id);
        let id3 = L.Add(it);
        t.Check("pins.reused_id_resets", id3 == id && !L.emph[id3] && L.alpha[id3] == 1.0, "");
        L.Clear();
        t.Check("pins.clear_empties_arrays", ArraySize(L.emph) == 0 && ArraySize(L.alpha) == 0, "");
    }
}
```

In `r6/scripts/NightMap/Debug/SelfTest.reds` `Run()`, add `NMVanillaTests.Run(this);` immediately before the
`TEST|SUMMARY` log line. If `Check` or `Near` is not `public`, make it `public`.

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE FAILED`, with unresolved `pinStyle`, `SetPinStyle`, `emph`, `WithEmphasis`, `Update` and `NightMapPinStyle`.

- [ ] **Step 3: Implement the item and layer changes**

In `Api/NightMapItem.reds`, add these fields after `priority`:

```swift
    public let emphasis: Bool;
    public let opacity: Float = 1.0;
```

and these builders after `WithPriority`:

```swift
    // Always drawn at full strength (and, for Icon-style layers, at the emphasis scale), like a tracked marker.
    public func WithEmphasis(on: Bool) -> ref<NightMapItem> {
        this.emphasis = on;
        return this;
    }

    // Per-item opacity multiplier (layer opacity still applies), clamped to 0..1.
    public func WithOpacity(a: Float) -> ref<NightMapItem> {
        this.opacity = ClampF(a, 0.0, 1.0);
        return this;
    }
```

In `Api/NightMapLayer.reds`:

1. Above `public class NightMapLayer`, add:

```swift
// How a layer's individual items are drawn. Clusters are always hexes.
public enum NightMapPinStyle {
    Hex = 0,
    Icon = 1
}
```

2. Add a field after `clustering`: `public let pinStyle: Int32;` (0 = Hex, 1 = Icon).
3. Add per-item fields after `public let prio: array<Int32>;`:

```swift
    public let emph: array<Bool>;
    public let alpha: array<Float>;
```

4. Replace the body of `Add` from `this.alive[id] = true;` through `this.prio[id] = item.priority;` with
   `this.alive[id] = true;` followed by `this.Store(id, item);`, keeping the `Link`, `count`, `Touch` and `return`
   lines. Add `Store` as a private function:

```swift
    // Copies an item's fields into slot id (position, category, icon, tint, label, priority, emphasis, opacity).
    private func Store(id: Int32, item: ref<NightMapItem>) {
        this.px[id] = item.x;
        this.py[id] = item.y;
        this.pz[id] = item.z;
        this.cat[id] = this.LocalCat(item.category);
        this.hasAtlas[id] = item.hasAtlas;
        this.atlas[id] = item.atlas;
        this.part[id] = item.part;
        this.image[id] = item.imageKey;
        this.imageResolved[id] = "";
        this.hasTint[id] = item.hasTint;
        this.tint[id] = item.tint;
        this.label[id] = item.label;
        this.prio[id] = item.priority;
        this.emph[id] = item.emphasis;
        this.alpha[id] = item.opacity;
    }
```

5. Add the public API after `Move`:

```swift
    // Replaces an item's content in place (position, category, icon, tint, label, emphasis, opacity). The id stays valid.
    public func Update(id: Int32, item: ref<NightMapItem>) -> Bool {
        if !this.IsAlive(id) || !IsDefined(item) {
            return false;
        }
        if !this.owner.InBounds(item.x, item.y) {
            this.WarnOnce("bounds", "update outside world bounds rejected");
            return false;
        }
        this.Unlink(id);
        this.Store(id, item);
        this.Link(id);
        this.Touch();
        return true;
    }

    public func SetPinStyle(style: NightMapPinStyle) {
        this.pinStyle = Cast<Int32>(EnumInt(style));
        this.Touch();
    }
```

6. In `Clear()`, add `ArrayClear(this.emph);` and `ArrayClear(this.alpha);` after `ArrayClear(this.prio);`.
7. In `Grow()`, add `ArrayPush(this.emph, false);` and `ArrayPush(this.alpha, 1.0);` after `ArrayPush(this.prio, 0);`.

- [ ] **Step 4: Run the compile check to verify it passes**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 5: Document the API**

In `docs/api.md`, append to the "Layers and items" bullet list:

```markdown
- `layer.Update(id, item)` replaces an item's content in place (position, icon, tint, label, emphasis, opacity) and keeps its id. Returns `false` for dead ids or out-of-bounds positions.
- `WithEmphasis(true)` draws the item at full strength (and enlarged on Icon-style layers), e.g. for a tracked marker. `WithOpacity(a)` multiplies the item's opacity (0..1) on top of the layer opacity.
```

In "Display controls", after `layer.SetClustering(false);`, add `layer.SetPinStyle(NightMapPinStyle.Icon);` to the code
block. Below the block, add:

```markdown
`NightMapPinStyle.Icon` draws each item like the vanilla world map: the icon over a soft shadow, dimmed to 50 % until it is selected or emphasised, then full strength at 1.3×. `Hex` (the default) draws hologram hex chips. Clusters are hexes in both styles.
```

- [ ] **Step 6: Commit**

```bash
git add r6/scripts/NightMap/Api/NightMapItem.reds r6/scripts/NightMap/Api/NightMapLayer.reds r6/scripts/NightMap/Debug/SelfTestVanilla.reds r6/scripts/NightMap/Debug/SelfTest.reds docs/api.md
git commit -m "feat(api): pin style, item emphasis/opacity, in-place layer Update

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Renderer: Icon pin style and selection grow

**Files:**
- Modify: `r6/scripts/NightMap/Core/Theme.reds`
- Modify: `r6/scripts/NightMap/Render/ItemRenderer.reds`:
  - pool fields at lines 19-24;
  - pool creation at lines 104-134;
  - `PlaceChip` at lines 332-380;
  - `HideUnused` at line 590.
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds` (`UpdateModules`, lines 399-439)
- Modify: `r6/scripts/NightMap/Debug/SelfTestVanilla.reds`

**Interfaces:**
- Consumes (Task 1): `L.pinStyle`, `L.emph[id]`, `L.alpha[id]`.
- Produces:
  - `NMTheme.MappinAtlas() -> ResRef`, `NMTheme.ShadowAtlas() -> ResRef`
  - `NMTheme.VanillaIconSize() -> Float` (64), `VanillaShadowSize()` (180), `VanillaShadowOpacity()` (0.8),
    `VanillaIdleOpacity()` (0.5), `VanillaEmphScale()` (1.3), `VanillaGrowMs()` (150)
  - `NMTheme.ShadowColor() -> HDRColor` (black)
  - `NMItemRenderer.chipStyle: array<Int32>`: -1 unset, 0 hex, 1 icon idle, 2 icon emphasised
  - `NMItemRenderer.growSlot: Int32`, `NMItemRenderer.growT: Float`
  - `NMItemRenderer.ApplySelection(cand: Int32, kind: Int32, dtMs: Float)`

- [ ] **Step 1: Write the failing self-tests**

In `SelfTestVanilla.reds`, add `NMVanillaTests.IconStyleCases(t);` to `Run`, and add:

```swift
    // Finds the renderer slot that drew item id of layer index li, or -1.
    private static func SlotOf(r: ref<NMItemRenderer>, li: Int32, id: Int32) -> Int32 {
        let i = 0;
        let n = ArraySize(r.candItem);
        while i < n {
            if r.candKind[i] == 0 && r.candLayer[i] == li && r.candItem[i] == id {
                return r.candSlot[i];
            }
            i += 1;
        }
        return -1;
    }

    private static func CandOf(r: ref<NMItemRenderer>, li: Int32, id: Int32) -> Int32 {
        let i = 0;
        let n = ArraySize(r.candItem);
        while i < n {
            if r.candKind[i] == 0 && r.candLayer[i] == li && r.candItem[i] == id {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    private static func IconStyleCases(t: ref<NMSelfTest>) {
        let api = NMVanillaTests.TestApi();
        let L = api.CreateLayer(n"test.icons", "Icons", 5);
        L.SetPinStyle(NightMapPinStyle.Icon);
        let H = api.CreateLayer(n"test.hex", "Hex", 4);
        let a = L.Add(NightMapItem.Create(new Vector4(-1800.0, 150.0, 0.0, 1.0), n"v", NMTheme.MappinAtlas(), n"fast_travel"));
        let b = L.Add(NightMapItem.Create(new Vector4(-1780.0, 150.0, 0.0, 1.0), n"v", NMTheme.MappinAtlas(), n"quest").WithEmphasis(true));
        let c = L.Add(NightMapItem.Create(new Vector4(-1760.0, 150.0, 0.0, 1.0), n"v", NMTheme.MappinAtlas(), n"gigs").WithOpacity(0.7));
        let h = H.Add(NightMapItem.Create(new Vector4(-1820.0, 150.0, 0.0, 1.0), n"h", NMTheme.UiAtlas(), n"icon_dot"));
        let canvas = new inkCanvas();
        let r = NMItemRenderer.Create(api, canvas, 1.0);
        let cam = NMCamera.Create(1880.0, 1480.0, NMRect.Create(-6000.0, -4600.0, 4600.0, 7400.0), 0.5, 16.0);
        cam.SetCenter(-1800.0, 150.0);
        cam.SetMpp(0.5);
        r.Update(cam, 1880.0, 1480.0);
        let sa = NMVanillaTests.SlotOf(r, L.index, a);
        let sb = NMVanillaTests.SlotOf(r, L.index, b);
        let sc = NMVanillaTests.SlotOf(r, L.index, c);
        let sh = NMVanillaTests.SlotOf(r, H.index, h);
        t.Check("icons.all_placed", sa >= 0 && sb >= 0 && sc >= 0 && sh >= 0, ToString(r.chipsUsed));
        t.Check("icons.styles", r.chipStyle[sa] == 1 && r.chipStyle[sb] == 2 && r.chipStyle[sh] == 0, "");
        t.Check("icons.idle_dimmed", t.Near(r.chipAlpha[sa], 0.5, 0.001) && t.Near(r.chipAlpha[sb], 1.0, 0.001)
            && t.Near(r.chipAlpha[sc], 0.35, 0.001) && t.Near(r.chipAlpha[sh], 1.0, 0.001), t.F(r.chipAlpha[sa]) + "," + t.F(r.chipAlpha[sc]));
        let sizeB = r.chipIcon[sb].GetSize();
        let sizeA = r.chipIcon[sa].GetSize();
        let sizeH = r.chipBg[sh].GetSize();
        t.Check("icons.sizes", t.Near(sizeA.X, NMTheme.VanillaIconSize(), 0.01) && t.Near(sizeB.X, NMTheme.VanillaIconSize() * NMTheme.VanillaEmphScale(), 0.01)
            && t.Near(sizeH.X, NMTheme.ChipSize(), 0.01), t.F(sizeA.X) + "," + t.F(sizeB.X));
        // Selection grow: half the grow time gives half the extra scale; the rim stays hidden for icon pins.
        let ca = NMVanillaTests.CandOf(r, L.index, a);
        r.selChip.SetVisible(true);
        r.ApplySelection(ca, 0, NMTheme.VanillaGrowMs() * 0.5);
        let sc1 = r.chipIcon[sa].GetScale();
        t.Check("icons.grow_half", r.growSlot == sa && t.Near(sc1.X, 1.0 + (NMTheme.VanillaEmphScale() - 1.0) * 0.5, 0.01) && !r.selChip.IsVisible(), t.F(sc1.X));
        r.ApplySelection(ca, 0, NMTheme.VanillaGrowMs());
        let sc2 = r.chipIcon[sa].GetScale();
        t.Check("icons.grow_full", t.Near(sc2.X, NMTheme.VanillaEmphScale(), 0.01), t.F(sc2.X));
        // Selecting another item (or nothing) restores the old slot.
        let cb = NMVanillaTests.CandOf(r, L.index, c);
        r.ApplySelection(cb, 0, 16.0);
        let sc3 = r.chipIcon[sa].GetScale();
        t.Check("icons.grow_resets_on_reselect", t.Near(sc3.X, 1.0, 0.001) && r.growSlot == sc, t.F(sc3.X));
        r.ApplySelection(-1, -1, 16.0);
        let sc4 = r.chipIcon[sc].GetScale();
        t.Check("icons.grow_resets_on_deselect", t.Near(sc4.X, 1.0, 0.001) && r.growSlot == -1, "");
        // A hex selection keeps its rim and never grows.
        let ch = NMVanillaTests.CandOf(r, H.index, h);
        r.selChip.SetVisible(true);
        r.ApplySelection(ch, 0, 200.0);
        t.Check("icons.hex_keeps_rim", r.selChip.IsVisible() && r.growSlot == -1, "");
        // Style switch on a reused slot resets size: make the icon layer hex and relayout.
        L.SetPinStyle(NightMapPinStyle.Hex);
        r.Update(cam, 1880.0, 1480.0);
        let sa2 = NMVanillaTests.SlotOf(r, L.index, a);
        let sizeA2 = r.chipBg[sa2].GetSize();
        t.Check("icons.style_switch_resets_size", r.chipStyle[sa2] == 0 && t.Near(sizeA2.X, NMTheme.ChipSize(), 0.01), t.F(sizeA2.X));
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE FAILED`, with unresolved `MappinAtlas`, `chipStyle`, `ApplySelection`, `growSlot` and similar.

- [ ] **Step 3: Add the Theme constants**

In `Core/Theme.reds`, inside `NMTheme`, add:

```swift
    // ---- vanilla map markers (sub-project 2): values extracted from the vanilla world map (spike LOOK.md) ----
    public static func MappinAtlas() -> ResRef { return r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas"; }
    public static func ShadowAtlas() -> ResRef { return r"base\\gameplay\\gui\\common\\shadow_blobs.inkatlas"; }
    public static func VanillaIconSize() -> Float { return 64.0; }        // 4K units, as the vanilla world map
    public static func VanillaShadowSize() -> Float { return 180.0; }     // soft blob under the icon; tune at checkpoint 4
    public static func VanillaShadowOpacity() -> Float { return 0.8; }
    public static func VanillaIdleOpacity() -> Float { return 0.5; }      // vanilla Mappin state opacity
    public static func VanillaEmphScale() -> Float { return 1.3; }        // vanilla OnSelect end scale
    public static func VanillaGrowMs() -> Float { return 150.0; }
    public static func ShadowColor() -> HDRColor { return new HDRColor(0.0, 0.0, 0.0, 1.0); }
```

- [ ] **Step 4: Implement the Icon style in the renderer**

In `Render/ItemRenderer.reds`:

0. Make `chipBg`, `chipIcon` and `chipAlpha` `public let`, because the self-tests read them, like `chipsUsed` and the
   `cand*` arrays.
1. Add these fields after `chipAlpha`:

```swift
    public let chipStyle: array<Int32>;   // -1 unset, 0 hex, 1 icon idle, 2 icon emphasised
    public let growSlot: Int32;           // slot currently growing/grown for the selection (icon idle pins), -1 none
    public let growT: Float;              // 0..1 progress of the selection grow
    private let growLayer: Int32;
    private let growItem: Int32;
```

2. In `Create`, inside the chip pool loop, add `ArrayPush(r.chipStyle, -1);` after `ArrayPush(r.chipAlpha, 1.0);`.
   After the loop, set `r.growSlot = -1; r.growLayer = -1; r.growItem = -1;`.

3. In `PlaceChip`, replace everything from `let g = L.catGlobal[L.cat[id]];` up to and including the opacity block that
   ends with `this.chipAlpha[slot] = L.opacity;\n    }` with:

```swift
    let g = L.catGlobal[L.cat[id]];
    let color = this.api.catColor[g];
    let style = L.pinStyle == 1 ? (L.emph[id] ? 2 : 1) : 0;
    if this.chipStyle[slot] != style {
        this.ApplyChipStyle(slot, style);
        this.chipCat[slot] = -2;        // force the tint refresh below
        this.chipAlpha[slot] = -1.0;    // force the opacity refresh below
    }
    if this.chipCat[slot] != g || L.hasTint[id] {
        bg.SetTintColor(style == 0 ? color : NMTheme.ShadowColor());
        ic.SetTintColor(L.hasTint[id] ? L.tint[id] : color);
        this.chipCat[slot] = L.hasTint[id] ? -1 : g;
    }
    this.ResolveIcon(L, id);
    if this.icon.pending { this.pendingImages += 1; }
    if NotEquals(this.chipIconKey[slot], this.icon.key) {
        ic.SetAtlasResource(this.icon.atlas);
        ic.SetTexturePart(this.icon.part);
        this.chipIconKey[slot] = this.icon.key;
    }
    let a = L.opacity * L.alpha[id];
    if style == 1 {
        a *= NMTheme.VanillaIdleOpacity();
    }
    if this.chipAlpha[slot] != a {
        bg.SetOpacity(style == 0 ? a : a * NMTheme.VanillaShadowOpacity());
        ic.SetOpacity(a);
        this.chipAlpha[slot] = a;
    }
```

   Keep the remaining lines (`SetTranslation`, visibility and cand pushes) unchanged.

4. Add the style and grow helpers (private, except `ApplySelection`):

```swift
    // Switches a pooled chip between the hologram hex (0) and the vanilla icon look (1 idle, 2 emphasised).
    private func ApplyChipStyle(slot: Int32, style: Int32) {
        let bg = this.chipBg[slot];
        let ic = this.chipIcon[slot];
        if style == 0 {
            bg.SetAtlasResource(NMTheme.UiAtlas());
            bg.SetTexturePart(n"chip");
            bg.SetSize(new Vector2(NMTheme.ChipSize() * this.scale, NMTheme.ChipSize() * this.scale));
            ic.SetSize(new Vector2(NMTheme.IconSize() * this.scale, NMTheme.IconSize() * this.scale));
        } else {
            let k = style == 2 ? NMTheme.VanillaEmphScale() : 1.0;
            bg.SetAtlasResource(NMTheme.ShadowAtlas());
            bg.SetTexturePart(n"shadowBlobSquare_big");
            bg.SetSize(new Vector2(NMTheme.VanillaShadowSize() * k * this.scale, NMTheme.VanillaShadowSize() * k * this.scale));
            ic.SetSize(new Vector2(NMTheme.VanillaIconSize() * k * this.scale, NMTheme.VanillaIconSize() * k * this.scale));
        }
        bg.SetScale(new Vector2(1.0, 1.0));
        ic.SetScale(new Vector2(1.0, 1.0));
        if slot == this.growSlot {
            this.growSlot = -1;
        }
        this.chipStyle[slot] = style;
    }

    // t in 0..1: scale 1 -> VanillaEmphScale and opacity idle -> full, like the vanilla OnSelect animation.
    private func SetGrow(slot: Int32, t: Float) {
        let k = 1.0 + (NMTheme.VanillaEmphScale() - 1.0) * t;
        let base = this.chipAlpha[slot];
        let full = MinF(1.0, base / NMTheme.VanillaIdleOpacity());
        let o = base + (full - base) * t;
        this.chipBg[slot].SetScale(new Vector2(k, k));
        this.chipIcon[slot].SetScale(new Vector2(k, k));
        this.chipIcon[slot].SetOpacity(o);
        this.chipBg[slot].SetOpacity(o * NMTheme.VanillaShadowOpacity());
    }

    // Called every frame after the crosshair pick. Icon pins have no selection rim; an idle icon pin grows to the
    // emphasis look over VanillaGrowMs. cand indexes the cand* arrays (-1 none); kind is the crosshair's selKind.
    public func ApplySelection(cand: Int32, kind: Int32, dtMs: Float) {
        let slot = -1;
        let layer = -1;
        let item = -1;
        if cand >= 0 && kind == 0 && cand < ArraySize(this.candSlot) {
            slot = this.candSlot[cand];
            layer = this.candLayer[cand];
            item = this.candItem[cand];
        }
        let isIcon = slot >= 0 && this.chipStyle[slot] >= 1;
        if isIcon {
            this.selChip.SetVisible(false);
        }
        let target = isIcon && this.chipStyle[slot] == 1 ? slot : -1;
        let sameItem = layer == this.growLayer && item == this.growItem;
        if target != this.growSlot || !sameItem {
            if this.growSlot >= 0 {
                this.SetGrow(this.growSlot, 0.0);
            }
            if !sameItem {
                this.growT = 0.0;
            }
            this.growSlot = target;
            this.growLayer = target >= 0 ? layer : -1;
            this.growItem = target >= 0 ? item : -1;
            if target >= 0 && this.growT > 0.0 {
                this.SetGrow(target, this.growT);   // same item moved to another slot: keep its progress
            }
        }
        if this.growSlot >= 0 && this.growT < 1.0 {
            this.growT = MinF(1.0, this.growT + MaxF(dtMs, 0.0) / NMTheme.VanillaGrowMs());
            this.SetGrow(this.growSlot, this.growT);
        }
    }
```

5. In `HideUnused`, inside `if this.chipOn[s] { ... }`, also reset a grown slot. Add before `this.chipOn[s] = false;`:

```swift
                if s == this.growSlot {
                    this.SetGrow(s, 0.0);
                    this.growSlot = -1;
                }
```

6. In `PlaceChip`, when a slot is reused for a *different* layer/item than `growLayer`/`growItem` while it is
   `growSlot`, its scale must reset. After `let ic = this.chipIcon[slot];`, add:

```swift
    if slot == this.growSlot && (L.index != this.growLayer || id != this.growItem) {
        this.SetGrow(slot, 0.0);
        this.growSlot = -1;
    }
```

   The `this.SetGrow(slot, 0.0)` call uses the slot's old alpha. `PlaceChip` then sets the new alpha.

- [ ] **Step 5: Call ApplySelection every frame**

In `Core/NightMapSystem.reds` `UpdateModules`, insert directly after the `if relaid { ... }` block (before
`if this.input.act {`):

```swift
        this.renderer.ApplySelection(this.crosshair.sel, this.crosshair.selKind, dt);
```

`crosshair.sel` must be -1 when nothing is selected. If `NMCrosshair.Reset()` does not set `sel = -1`, add
`this.sel = -1;` to `Reset()`, and default the field with `public let sel: Int32;` set to -1 in `Create`. Field
defaults cannot be negative.

- [ ] **Step 6: Run the compile check to verify it passes**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 7: Commit**

```bash
git add r6/scripts/NightMap/Core/Theme.reds r6/scripts/NightMap/Render/ItemRenderer.reds r6/scripts/NightMap/Render/Crosshair.reds r6/scripts/NightMap/Core/NightMapSystem.reds r6/scripts/NightMap/Debug/SelfTestVanilla.reds
git commit -m "feat(render): vanilla Icon pin style with idle dimming and selection grow

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Vanilla style and filter catalogue

**Files:**
- Modify: `r6/scripts/NightMap/Core/Theme.reds`
- Create: `r6/scripts/NightMap/Vanilla/Style.reds`
- Create: `r6/scripts/NightMap/Vanilla/Catalog.reds`
- Modify: `r6/scripts/NightMap/Debug/SelfTestVanilla.reds`

**Interfaces:**
- Consumes: the game (`MappinUtils.GetMappinsGroup(v)` → `.GroupName()`/`.WidgetState()`;
  `MappinUIUtils.MappinToTexturePart(v)`; `TweakDBInterface.GetWorldMapFiltersListRecord(t"WorldMap.WorldMapCustomFiltersList")`
  → `GetListCount()`, `GetListItem(i)` → `MappinUIFilterGroup_Record` with `FilterName()`, `FilterType().Type()`,
  `GetMappinsCount()`, `GetMappinsItem(i).Type()`).
- Produces:
  - `NMTheme.VanillaStateColor(state: CName) -> HDRColor`
  - `NMVanillaStyle.StateOf(v: gamedataMappinVariant, phase: gamedataMappinPhase) -> CName`
  - `NMVanillaStyle.Color(v, phase) -> HDRColor`
  - `NMVanillaStyle.PartOf(v: gamedataMappinVariant) -> CName` (never a missing part)
  - `NMVanillaStyle.CanQuestTrack(v: gamedataMappinVariant) -> Bool`
  - `NMVanillaStyle.CompletedOpacity() -> Float` (0.7)
  - `NMVanillaCatalog.Build() -> ref<NMVanillaCatalog>`; fields `types: array<gamedataWorldMapFilter>`,
    `names: array<String>`, `firstVariant: array<gamedataMappinVariant>`
  - `catalog.Count() -> Int32` (number of vanilla filters; index `Count()` is "Other")
  - `catalog.FilterIndexOf(v) -> Int32` (0..Count()-1, or `Count()` for Other)
  - `catalog.LayerId(i) -> CName`, `catalog.CategoryName(i) -> CName`, `catalog.DisplayName(i) -> String`,
    `catalog.Priority(i) -> Int32`, `catalog.IsOther(i) -> Bool`, `catalog.TypeOf(i) -> gamedataWorldMapFilter`

- [ ] **Step 1: Write the failing self-tests**

In `SelfTestVanilla.reds`, add `NMVanillaTests.StyleCases(t);` to `Run`, and add:

```swift
    private static func StyleCases(t: ref<NMSelfTest>) {
        let def = gamedataMappinPhase.DefaultPhase;
        t.Check("vanilla.state_completed", Equals(NMVanillaStyle.StateOf(gamedataMappinVariant.GangWatchVariant, gamedataMappinPhase.CompletedPhase), n"QuestComplete"), "");
        t.Check("vanilla.state_metro", Equals(NMVanillaStyle.StateOf(gamedataMappinVariant.Zzz17_NCARTVariant, def), n"FastTravelMetro"), "");
        t.Check("vanilla.state_quest", Equals(NMVanillaStyle.StateOf(gamedataMappinVariant.DefaultQuestVariant, def), n"Quest"), ToString(NMVanillaStyle.StateOf(gamedataMappinVariant.DefaultQuestVariant, def)));
        t.Check("vanilla.state_vendor", Equals(NMVanillaStyle.StateOf(gamedataMappinVariant.ServicePointFoodVariant, def), n"ServicePoint"), "");
        let q = NMTheme.VanillaStateColor(n"Quest");
        let unknown = NMTheme.VanillaStateColor(n"NoSuchState");
        t.Check("vanilla.color_table", t.Near(q.Red, 1.0, 0.01) && t.Near(q.Blue, 0.306, 0.01) && t.Near(unknown.Green, 1.0, 0.01), "");
        t.Check("vanilla.part_fast_travel", Equals(NMVanillaStyle.PartOf(gamedataMappinVariant.FastTravelVariant), n"fast_travel"), "");
        t.Check("vanilla.part_fallback", Equals(NMVanillaStyle.PartOf(gamedataMappinVariant.Zzz16_RelicDeviceSpecialVariant), n"relic_access_point")
            && NotEquals(NMVanillaStyle.PartOf(gamedataMappinVariant.ActionScanVariant), n"invalid"), ToString(NMVanillaStyle.PartOf(gamedataMappinVariant.ActionScanVariant)));
        t.Check("vanilla.track_rules", NMVanillaStyle.CanQuestTrack(gamedataMappinVariant.DefaultQuestVariant)
            && NMVanillaStyle.CanQuestTrack(gamedataMappinVariant.RetrievingVariant)
            && !NMVanillaStyle.CanQuestTrack(gamedataMappinVariant.Zzz18_RacingVariant)
            && !NMVanillaStyle.CanQuestTrack(gamedataMappinVariant.FastTravelVariant)
            && !NMVanillaStyle.CanQuestTrack(gamedataMappinVariant.ServicePointFoodVariant), "");
        let cat = NMVanillaCatalog.Build();
        let n = cat.Count();
        t.Check("vanilla.catalog_twelve", n == 12, ToString(n));
        let ft = cat.FilterIndexOf(gamedataMappinVariant.FastTravelVariant);
        let gw = cat.FilterIndexOf(gamedataMappinVariant.GangWatchVariant);
        let dp = cat.FilterIndexOf(gamedataMappinVariant.ServicePointDropPointVariant);
        let wp = cat.FilterIndexOf(gamedataMappinVariant.CustomPositionVariant);
        t.Check("vanilla.catalog_members", Equals(cat.TypeOf(ft), gamedataWorldMapFilter.FastTravel) && Equals(cat.TypeOf(gw), gamedataWorldMapFilter.Story)
            && Equals(cat.TypeOf(dp), gamedataWorldMapFilter.DropPoint) && Equals(cat.TypeOf(wp), gamedataWorldMapFilter.CommonFilter), "");
        let other = cat.FilterIndexOf(gamedataMappinVariant.Zzz16_RelicDeviceBasicVariant);
        t.Check("vanilla.catalog_unknown_is_other", other == n && cat.IsOther(other) && Equals(cat.LayerId(other), n"Vanilla.Other"), ToString(other));
        t.Check("vanilla.catalog_names", StrLen(cat.DisplayName(ft)) > 0 && Equals(cat.LayerId(ft), n"Vanilla.FastTravel") && cat.Priority(gw) > cat.Priority(ft), cat.DisplayName(ft));
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE FAILED` (unresolved `NMVanillaStyle`, `NMVanillaCatalog`, `VanillaStateColor`).

- [ ] **Step 3: Add the state colour table to Theme**

In `Core/Theme.reds`, add the following. Values come from `mappins.inkstyle` (spike LOOK.md §2); HDR > 1 is clamped.

```swift
    // Vanilla map-marker colour per widget state (MappinsGroup.WidgetState). Unknown states are white.
    public static func VanillaStateColor(state: CName) -> HDRColor {
        if Equals(state, n"Quest") { return new HDRColor(1.0, 1.0, 0.306, 1.0); }            // #FFFF4E
        if Equals(state, n"Gigs") { return new HDRColor(0.0, 1.0, 0.835, 1.0); }             // #00FFD5
        if Equals(state, n"Default") { return new HDRColor(1.0, 0.443, 0.404, 1.0); }        // #FF7167
        if Equals(state, n"QuestComplete") { return new HDRColor(0.42, 0.424, 0.424, 1.0); } // #6B6C6C
        if Equals(state, n"QuestUntracked") { return new HDRColor(0.847, 0.349, 0.071, 1.0); } // #D85912
        if Equals(state, n"Story") { return new HDRColor(0.369, 0.965, 1.0, 1.0); }          // #5EF6FF
        if Equals(state, n"FastTravel") { return new HDRColor(0.349, 0.706, 1.0, 1.0); }     // #59B4FF
        if Equals(state, n"FastTravelMetro") { return new HDRColor(0.8, 0.506, 1.0, 1.0); }  // #CC81FF
        if Equals(state, n"Relic") { return new HDRColor(0.471, 0.678, 1.0, 1.0); }          // #78ADFF
        if Equals(state, n"Player") { return new HDRColor(0.161, 1.0, 0.725, 1.0); }         // #29FFB9
        return new HDRColor(1.0, 1.0, 1.0, 1.0);   // ServicePoint, Vehicle, VehicleForPurchase and anything unknown
    }
```

- [ ] **Step 4: Implement NMVanillaStyle**

Create `r6/scripts/NightMap/Vanilla/Style.reds`:

```swift
module NightMap

// Variant/phase -> vanilla look and rules. Mirrors worldMap.script (BaseWorldMapMappinController) and mappinUtils.script.
public abstract class NMVanillaStyle {
    public static func StateOf(v: gamedataMappinVariant, phase: gamedataMappinPhase) -> CName {
        if Equals(phase, gamedataMappinPhase.CompletedPhase) { return n"QuestComplete"; }
        if Equals(v, gamedataMappinVariant.Zzz17_NCARTVariant) { return n"FastTravelMetro"; }
        if Equals(v, gamedataMappinVariant.Zzz16_RelicDeviceBasicVariant) { return n"Relic"; }
        let g = MappinUtils.GetMappinsGroup(v);
        if !IsDefined(g) { return n"Quest"; }
        let st = g.WidgetState();
        return Equals(st, n"") || Equals(st, n"None") ? n"Quest" : st;
    }

    public static func Color(v: gamedataMappinVariant, phase: gamedataMappinPhase) -> HDRColor {
        return NMTheme.VanillaStateColor(NMVanillaStyle.StateOf(v, phase));
    }

    // Icon part in NMTheme.MappinAtlas(). Parts the game names but does not ship fall back to a close match.
    public static func PartOf(v: gamedataMappinVariant) -> CName {
        let p = MappinUIUtils.MappinToTexturePart(v);
        if Equals(p, n"relic_dataterm") { return n"relic_access_point"; }
        if Equals(p, n"failed_crossing") { return n"dogtown_gate"; }
        if Equals(p, n"invalid") || Equals(p, n"") || Equals(p, n"None") { return n"quest"; }
        return p;
    }

    // Vanilla CanQuestTrackMappin: Quest/SecondaryQuest groups, except racing (worldMap.script:1638-1660).
    // The caller must also check that the mappin's journal entry resolves.
    public static func CanQuestTrack(v: gamedataMappinVariant) -> Bool {
        if Equals(v, gamedataMappinVariant.Zzz18_RacingVariant) { return false; }
        let g = MappinUtils.GetMappinsGroup(v);
        if !IsDefined(g) { return false; }
        let name = g.GroupName();
        return Equals(name, n"Quest") || Equals(name, n"SecondaryQuest");
    }

    public static func CompletedOpacity() -> Float { return 0.7; }   // MappinUIGlobalProfile.CompletedPOIOpacity
}
```

- [ ] **Step 5: Implement NMVanillaCatalog**

Create `r6/scripts/NightMap/Vanilla/Catalog.reds`:

```swift
module NightMap

// The vanilla world map's custom filter list (TweakDB WorldMap.WorldMapCustomFiltersList, 12 entries in 2.31):
// one NightMap layer per filter, plus index Count() = "Other" for map variants no filter lists.
public class NMVanillaCatalog {
    public let types: array<gamedataWorldMapFilter>;
    public let names: array<String>;
    public let firstVariant: array<gamedataMappinVariant>;
    private let memberVariant: array<Int32>;   // flattened (variant, filter index) pairs
    private let memberFilter: array<Int32>;

    public static func Build() -> ref<NMVanillaCatalog> {
        let c = new NMVanillaCatalog();
        let rec = TweakDBInterface.GetWorldMapFiltersListRecord(t"WorldMap.WorldMapCustomFiltersList");
        if !IsDefined(rec) {
            NMLog.Error("vanilla|catalog|WorldMapCustomFiltersList missing; all markers go to Other");
            return c;
        }
        let n = rec.GetListCount();
        let i = 0;
        while i < n {
            let g = rec.GetListItem(i);
            if IsDefined(g) {
                let ft = g.FilterType();
                let idx = ArraySize(c.types);
                ArrayPush(c.types, IsDefined(ft) ? ft.Type() : gamedataWorldMapFilter.CustomFilter);
                ArrayPush(c.names, GetLocalizedTextByKey(g.FilterName()));
                let first = gamedataMappinVariant.Invalid;
                let m = g.GetMappinsCount();
                let k = 0;
                while k < m {
                    let mv = g.GetMappinsItem(k);
                    if IsDefined(mv) {
                        let v = mv.Type();
                        if k == 0 { first = v; }
                        ArrayPush(c.memberVariant, Cast<Int32>(EnumInt(v)));
                        ArrayPush(c.memberFilter, idx);
                    }
                    k += 1;
                }
                ArrayPush(c.firstVariant, first);
            }
            i += 1;
        }
        return c;
    }

    public func Count() -> Int32 { return ArraySize(this.types); }

    public func IsOther(i: Int32) -> Bool { return i >= ArraySize(this.types); }

    // First filter (TweakDB order) listing v, else Count() (Other).
    public func FilterIndexOf(v: gamedataMappinVariant) -> Int32 {
        let key = Cast<Int32>(EnumInt(v));
        let i = 0;
        let n = ArraySize(this.memberVariant);
        while i < n {
            if this.memberVariant[i] == key {
                return this.memberFilter[i];
            }
            i += 1;
        }
        return ArraySize(this.types);
    }

    public func TypeOf(i: Int32) -> gamedataWorldMapFilter {
        return this.IsOther(i) ? gamedataWorldMapFilter.NoFilter : this.types[i];
    }

    public func LayerId(i: Int32) -> CName {
        return this.IsOther(i) ? n"Vanilla.Other" : StringToName("Vanilla." + ToString(this.types[i]));
    }

    public func CategoryName(i: Int32) -> CName {
        return this.IsOther(i) ? n"vanilla.other" : StringToName("vanilla." + ToString(this.types[i]));
    }

    public func DisplayName(i: Int32) -> String {
        if this.IsOther(i) { return "Other"; }
        let s = this.names[i];
        return StrLen(s) > 0 ? s : ToString(this.types[i]);
    }

    // Draw priority (higher on top): jobs above services, as the vanilla map layers them.
    public func Priority(i: Int32) -> Int32 {
        let t = this.TypeOf(i);
        if Equals(t, gamedataWorldMapFilter.Quest) { return 90; }
        if Equals(t, gamedataWorldMapFilter.Gigs) { return 85; }
        if Equals(t, gamedataWorldMapFilter.PsychoFilter) { return 84; }
        if Equals(t, gamedataWorldMapFilter.Story) { return 80; }
        if Equals(t, gamedataWorldMapFilter.FastTravel) { return 70; }
        if Equals(t, gamedataWorldMapFilter.TarotFilter) { return 55; }
        if this.IsOther(i) { return 50; }
        return 60;
    }
}
```

- [ ] **Step 6: Run the compile check to verify it passes**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE OK`. If `MappinUIFilterGroup_Record`, `GetMappinsItem` or another name fails, copy the exact form from
`.scratch/markers_spike/probe/NightMapProbe/TweakDump.reds`, which compiled and ran in game.

- [ ] **Step 7: Commit**

```bash
git add r6/scripts/NightMap/Core/Theme.reds r6/scripts/NightMap/Vanilla/Style.reds r6/scripts/NightMap/Vanilla/Catalog.reds r6/scripts/NightMap/Debug/SelfTestVanilla.reds
git commit -m "feat(vanilla): marker style table and filter catalogue

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Snapshot, visibility rules and diff (pure)

**Files:**
- Create: `r6/scripts/NightMap/Vanilla/Diff.reds`
- Modify: `r6/scripts/NightMap/Debug/SelfTestVanilla.reds`

**Interfaces:**
- Consumes: nothing from the game, except the `inkHashMap` native.
- Produces:
  - `public class NMVanillaSnap`: `key: Uint64`, `x, y, z: Float`, `variant: gamedataMappinVariant`,
    `phase: gamedataMappinPhase`, `visible: Bool`, `tracked: Bool`, `filter: Int32` (catalogue index; Other =
    `Count()`; -1 = skip)
  - `NMVanillaSnap.Make(key: Uint64, x: Float, y: Float, variant, phase, visible: Bool, tracked: Bool, filter: Int32) -> ref<NMVanillaSnap>`
  - `public class NMVanillaEntry extends IScriptable`: `key: Uint64`, `snap: ref<NMVanillaSnap>`, `slot: Int32`
    (layer slot: filter index, or -2 for pinned), `item: Int32`, `gen: Int32`
  - `NMVanillaRules.Shown(s) -> Bool`, `NMVanillaRules.Slot(s) -> Int32` (-2 = pinned)
  - `public abstract class NMVanillaSink extends IScriptable`: `OnAdd(e)`, `OnChange(e, s: ref<NMVanillaSnap>)`
    (called **before** `e.snap`/`e.slot` are updated), `OnRemove(e)`
  - `NMVanillaDiff.Create() -> ref<NMVanillaDiff>`
  - `diff.Apply(snaps: array<ref<NMVanillaSnap>>, sink: ref<NMVanillaSink>)`
  - `diff.added`, `diff.changed`, `diff.removed`, `diff.live: Int32`
  - `diff.Find(key: Uint64) -> ref<NMVanillaEntry>`

- [ ] **Step 1: Write the failing self-tests**

In `SelfTestVanilla.reds`, add `NMVanillaTests.DiffCases(t);` to `Run`, and add the recording sink and cases:

```swift
public class NMVanillaTestSink extends NMVanillaSink {
    public let adds: Int32;
    public let changes: Int32;
    public let removes: Int32;
    public let relayers: Int32;
    public let nextItem: Int32;

    public func OnAdd(e: ref<NMVanillaEntry>) {
        this.adds += 1;
        e.item = this.nextItem;
        this.nextItem += 1;
    }

    public func OnChange(e: ref<NMVanillaEntry>, s: ref<NMVanillaSnap>) {
        this.changes += 1;
        if e.slot != NMVanillaRules.Slot(s) { this.relayers += 1; }
    }

    public func OnRemove(e: ref<NMVanillaEntry>) {
        this.removes += 1;
    }
}
```

(This class goes at file scope in `SelfTestVanilla.reds`, after `NMVanillaTests`.) Add the cases to `NMVanillaTests`:

```swift
    private static func Snap(key: Uint64, x: Float, phase: gamedataMappinPhase, visible: Bool, tracked: Bool, filter: Int32) -> ref<NMVanillaSnap> {
        return NMVanillaSnap.Make(key, x, 100.0, gamedataMappinVariant.FastTravelVariant, phase, visible, tracked, filter);
    }

    private static func DiffCases(t: ref<NMSelfTest>) {
        let def = gamedataMappinPhase.DefaultPhase;
        let done = gamedataMappinPhase.CompletedPhase;
        // Rules truth table.
        t.Check("rules.visible_shown", NMVanillaRules.Shown(NMVanillaTests.Snap(1ul, 0.0, def, true, false, 3)), "");
        t.Check("rules.invisible_hidden", !NMVanillaRules.Shown(NMVanillaTests.Snap(1ul, 0.0, def, false, false, 3)), "");
        t.Check("rules.completed_hidden", !NMVanillaRules.Shown(NMVanillaTests.Snap(1ul, 0.0, done, true, false, 3)), "");
        t.Check("rules.tracked_always", NMVanillaRules.Shown(NMVanillaTests.Snap(1ul, 0.0, done, false, true, 3)), "");
        t.Check("rules.skip_filter", !NMVanillaRules.Shown(NMVanillaTests.Snap(1ul, 0.0, def, true, false, -1)), "");
        t.Check("rules.slots", NMVanillaRules.Slot(NMVanillaTests.Snap(1ul, 0.0, def, true, true, 3)) == -2
            && NMVanillaRules.Slot(NMVanillaTests.Snap(1ul, 0.0, def, true, false, 3)) == 3, "");
        // Diff.
        let d = NMVanillaDiff.Create();
        let sink = new NMVanillaTestSink();
        let s1: array<ref<NMVanillaSnap>>;
        ArrayPush(s1, NMVanillaTests.Snap(10ul, 0.0, def, true, false, 1));
        ArrayPush(s1, NMVanillaTests.Snap(11ul, 50.0, def, true, false, 2));
        ArrayPush(s1, NMVanillaTests.Snap(12ul, 90.0, def, false, false, 2));   // invisible: never added
        d.Apply(s1, sink);
        t.Check("diff.first_adds", sink.adds == 2 && d.added == 2 && d.live == 2, ToString(sink.adds));
        let s2: array<ref<NMVanillaSnap>>;
        ArrayPush(s2, NMVanillaTests.Snap(10ul, 0.2, def, true, false, 1));     // 0.2 m: below the move threshold
        ArrayPush(s2, NMVanillaTests.Snap(11ul, 50.0, def, true, false, 2));
        d.Apply(s2, sink);
        t.Check("diff.steady_no_changes", d.added == 0 && d.changed == 0 && d.removed == 0, ToString(d.changed));
        let s3: array<ref<NMVanillaSnap>>;
        ArrayPush(s3, NMVanillaTests.Snap(10ul, 10.0, def, true, false, 1));    // moved 10 m
        ArrayPush(s3, NMVanillaTests.Snap(11ul, 50.0, def, true, true, 2));     // now tracked -> pinned
        d.Apply(s3, sink);
        t.Check("diff.move_changes", d.changed == 2, ToString(d.changed));
        t.Check("diff.tracked_moves_to_pinned", sink.relayers == 1 && d.Find(11ul).slot == -2, "");
        let s4: array<ref<NMVanillaSnap>>;
        ArrayPush(s4, NMVanillaTests.Snap(10ul, 10.0, done, true, false, 1));   // completed + untracked -> hidden
        ArrayPush(s4, NMVanillaTests.Snap(11ul, 50.0, def, false, false, 2));   // untracked + invisible -> hidden
        d.Apply(s4, sink);
        t.Check("diff.phase_completed_removes", d.removed == 2 && d.live == 0 && !IsDefined(d.Find(10ul)), ToString(d.removed));
        t.Check("diff.invisible_removes", sink.removes == 2, "");
        let s5: array<ref<NMVanillaSnap>>;
        ArrayPush(s5, NMVanillaTests.Snap(10ul, 10.0, def, true, false, 1));
        d.Apply(s5, sink);
        let s6: array<ref<NMVanillaSnap>>;
        d.Apply(s6, sink);                                                       // gone from the list
        t.Check("diff.missing_removes", d.removed == 1 && d.live == 0, "");
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE FAILED` (unresolved `NMVanillaSnap`, `NMVanillaDiff`, `NMVanillaSink`, `NMVanillaRules`).

- [ ] **Step 3: Implement Diff.reds**

Create `r6/scripts/NightMap/Vanilla/Diff.reds`:

```swift
module NightMap

// One vanilla mappin as read in a poll. filter: catalogue index (Other = catalog.Count()), -1 = never show.
public class NMVanillaSnap {
    public let key: Uint64;
    public let x: Float;
    public let y: Float;
    public let z: Float;
    public let variant: gamedataMappinVariant;
    public let phase: gamedataMappinPhase;
    public let visible: Bool;
    public let tracked: Bool;
    public let filter: Int32;

    public static func Make(key: Uint64, x: Float, y: Float, variant: gamedataMappinVariant, phase: gamedataMappinPhase,
                            visible: Bool, tracked: Bool, filter: Int32) -> ref<NMVanillaSnap> {
        let s = new NMVanillaSnap();
        s.key = key;
        s.x = x;
        s.y = y;
        s.variant = variant;
        s.phase = phase;
        s.visible = visible;
        s.tracked = tracked;
        s.filter = filter;
        return s;
    }
}

// A mirrored mappin: which NightMap layer slot and item it lives in.
public class NMVanillaEntry extends IScriptable {
    public let key: Uint64;
    public let snap: ref<NMVanillaSnap>;
    public let slot: Int32;    // filter index, or -2 = Vanilla.Pinned
    public let item: Int32;
    public let gen: Int32;
}

// Spec §6 visibility rule.
public abstract class NMVanillaRules {
    public static func Shown(s: ref<NMVanillaSnap>) -> Bool {
        if s.tracked { return true; }
        if !s.visible || s.filter < 0 { return false; }
        return !Equals(s.phase, gamedataMappinPhase.CompletedPhase);
    }

    public static func Slot(s: ref<NMVanillaSnap>) -> Int32 {
        return s.tracked ? -2 : s.filter;
    }

    // A change worth touching the layer for: moved > 0.5 m, or variant/phase/tracked/filter changed.
    public static func Differs(a: ref<NMVanillaSnap>, b: ref<NMVanillaSnap>) -> Bool {
        if AbsF(a.x - b.x) > 0.5 || AbsF(a.y - b.y) > 0.5 { return true; }
        if NotEquals(a.variant, b.variant) || NotEquals(a.phase, b.phase) { return true; }
        return NotEquals(a.tracked, b.tracked) || a.filter != b.filter;
    }
}

// Receives the diff. OnChange runs before the entry's snap/slot are replaced, so e.slot is still the old slot.
public abstract class NMVanillaSink extends IScriptable {
    public func OnAdd(e: ref<NMVanillaEntry>) {}
    public func OnChange(e: ref<NMVanillaEntry>, s: ref<NMVanillaSnap>) {}
    public func OnRemove(e: ref<NMVanillaEntry>) {}
}

// Keyed by NewMappinID.value: inkHashMap lookup per mappin, one sweep for removals. No per-frame work.
public class NMVanillaDiff {
    private let map: ref<inkHashMap>;
    private let entries: array<ref<NMVanillaEntry>>;
    private let gen: Int32;
    public let added: Int32;
    public let changed: Int32;
    public let removed: Int32;
    public let live: Int32;

    public static func Create() -> ref<NMVanillaDiff> {
        let d = new NMVanillaDiff();
        d.map = new inkHashMap();
        return d;
    }

    public func Find(key: Uint64) -> ref<NMVanillaEntry> {
        if !this.map.KeyExist(key) {
            return null;
        }
        return this.map.Get(key) as NMVanillaEntry;
    }

    public func Apply(snaps: array<ref<NMVanillaSnap>>, sink: ref<NMVanillaSink>) {
        this.gen += 1;
        this.added = 0;
        this.changed = 0;
        this.removed = 0;
        for s in snaps {
            if IsDefined(s) && NMVanillaRules.Shown(s) {
                let e = this.Find(s.key);
                if !IsDefined(e) {
                    e = new NMVanillaEntry();
                    e.key = s.key;
                    e.snap = s;
                    e.slot = NMVanillaRules.Slot(s);
                    e.item = -1;
                    e.gen = this.gen;
                    sink.OnAdd(e);
                    this.map.Insert(s.key, e);
                    ArrayPush(this.entries, e);
                    this.added += 1;
                } else {
                    e.gen = this.gen;
                    if NMVanillaRules.Differs(e.snap, s) {
                        sink.OnChange(e, s);
                        e.snap = s;
                        e.slot = NMVanillaRules.Slot(s);
                        this.changed += 1;
                    }
                }
            }
        }
        // Sweep: anything not seen (or no longer shown) this generation goes away. Swap-remove keeps it O(n).
        let i = ArraySize(this.entries) - 1;
        while i >= 0 {
            let e = this.entries[i];
            if e.gen != this.gen {
                sink.OnRemove(e);
                this.map.Remove(e.key);
                let last = ArraySize(this.entries) - 1;
                this.entries[i] = this.entries[last];
                ArrayPop(this.entries);
                this.removed += 1;
            }
            i -= 1;
        }
        this.live = ArraySize(this.entries);
    }
}
```

- [ ] **Step 4: Run the compile check to verify it passes**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 5: Commit**

```bash
git add r6/scripts/NightMap/Vanilla/Diff.reds r6/scripts/NightMap/Debug/SelfTestVanilla.reds
git commit -m "feat(vanilla): snapshot diff with visibility rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Vanilla layers, mappin polling and system wiring

**Files:**
- Create: `r6/scripts/NightMap/Vanilla/Vanilla.reds`
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds`:
  - fields;
  - `OnAttach` (lines 43-51);
  - `OnOpened` (line 370);
  - `UpdateModules` (lines 399-439).
- Modify: `r6/scripts/NightMap/Debug/SelfTestVanilla.reds`

**Interfaces:**
- Consumes:
  - Task 1: `SetPinStyle`, `Update`, `WithEmphasis`, `WithOpacity`.
  - Task 3: `NMVanillaStyle.*`, `NMVanillaCatalog.*`.
  - Task 4: `NMVanillaDiff`, `NMVanillaSink`, `NMVanillaSnap`, `NMVanillaEntry`, `NMVanillaRules`.
  - The game: `GameInstance.GetMappinSystem(gi).GetMappins(gamemappinsMappinTargetType.Map, arr)` with
    `arr: array<ref<IMappin>>`; `GetManuallyTrackedMappinID() -> NewMappinID`; `IMappin.GetNewMappinID()`,
    `GetWorldPosition()`, `GetVariant()`, `GetPhase()`, `IsVisible()`, `IsPlayerTracked()`.
- Produces:
  - `public class NMVanilla extends NMVanillaSink`
  - `NMVanilla.Create(api: ref<NightMap>, gi: GameInstance) -> ref<NMVanilla>`
  - `vanilla.Tick(nowMs: Float, force: Bool) -> Bool` (true if it polled)
  - `vanilla.PollFrom(arr: array<ref<IMappin>>, manualKey: Uint64)`
  - `vanilla.catalog: ref<NMVanillaCatalog>`; `vanilla.pinned: ref<NightMapLayer>`
  - `vanilla.LayerForSlot(slot: Int32) -> ref<NightMapLayer>`; `vanilla.EntryFor(slot: Int32, item: Int32) -> ref<NMVanillaEntry>`
  - `vanilla.diff: ref<NMVanillaDiff>`
  - `public class NMVanillaListener extends NightMapLayerListener`: `owner: wref<NMVanilla>`, `slot: Int32`,
    `book: array<ref<NMVanillaEntry>>` (indexed by item id)
  - `NMVanilla.PollMs() -> Float` (1500)

- [ ] **Step 1: Write the failing self-tests**

In `SelfTestVanilla.reds`, add `NMVanillaTests.LiveCases(t);` to `Run`, and add:

```swift
    // Uses the live MappinSystem (run the self-test in a loaded save) against a standalone test API.
    private static func LiveCases(t: ref<NMSelfTest>) {
        let api = NMVanillaTests.TestApi();
        let v = NMVanilla.Create(api, GetGameInstance());
        t.Check("vanilla.tick_polls_when_forced", v.Tick(0.0, true), "");
        t.Check("vanilla.tick_throttled", !v.Tick(10.0, false) && v.Tick(NMVanilla.PollMs() + 1.0, false), "");
        let n = v.catalog.Count();
        t.Check("vanilla.layers_created", IsDefined(api.GetLayer(n"Vanilla.FastTravel")) && IsDefined(api.GetLayer(n"Vanilla.Other"))
            && IsDefined(api.GetLayer(n"Vanilla.Pinned")) && ArraySize(api.layers) == n + 2, ToString(ArraySize(api.layers)));
        let ft = api.GetLayer(n"Vanilla.FastTravel");
        t.Check("vanilla.layer_style_icon", ft.pinStyle == 1 && !v.pinned.clustering, "");
        t.Check("vanilla.markers_mirrored", v.diff.live > 0 && ft.count > 0, ToString(v.diff.live));
        // Every mirrored item's book entry points back at the same key.
        let ok = true;
        let i = 0;
        while i < ArraySize(ft.alive) {
            if ft.alive[i] {
                let e = v.EntryFor(v.catalog.FilterIndexOf(gamedataMappinVariant.FastTravelVariant), i);
                if !IsDefined(e) || e.item != i { ok = false; }
            }
            i += 1;
        }
        t.Check("vanilla.book_consistent", ok, "");
        // A synthetic unknown variant goes to Other and is logged once.
        let fake: array<ref<IMappin>>;
        v.PollFrom(fake, 0ul);
        t.Check("vanilla.empty_poll_removes_all", v.diff.live == 0 && ft.count == 0, ToString(v.diff.live));
        t.Check("vanilla.unknown_variant_logged_once", v.LogOnceForTest(gamedataMappinVariant.Zzz16_RelicDeviceBasicVariant)
            && !v.LogOnceForTest(gamedataMappinVariant.Zzz16_RelicDeviceBasicVariant), "");
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE FAILED` (unresolved `NMVanilla`).

- [ ] **Step 3: Implement Vanilla.reds**

Create `r6/scripts/NightMap/Vanilla/Vanilla.reds`:

```swift
module NightMap

// Per-layer listener: maps item ids back to mirrored mappins (book) and forwards card/activation to NMVanilla.
public class NMVanillaListener extends NightMapLayerListener {
    public let owner: wref<NMVanilla>;
    public let slot: Int32;
    public let book: array<ref<NMVanillaEntry>>;

    public func Set(item: Int32, e: ref<NMVanillaEntry>) {
        while ArraySize(this.book) <= item {
            ArrayPush(this.book, null);
        }
        this.book[item] = e;
    }

    public func Get(item: Int32) -> ref<NMVanillaEntry> {
        return item >= 0 && item < ArraySize(this.book) ? this.book[item] : null;
    }

    public func GetDetails(id: Int32) -> ref<NightMapDetails> {
        return IsDefined(this.owner) ? this.owner.Details(this.Get(id)) : null;
    }

    public func OnActivated(id: Int32) {
        if IsDefined(this.owner) { this.owner.Activate(this.Get(id)); }
    }
}

// Mirrors the vanilla world-map markers into NightMap layers: one per vanilla filter (+ Other) and Vanilla.Pinned.
// Polls only when asked (the system calls Tick while the map is open), so it costs nothing while closed.
public class NMVanilla extends NMVanillaSink {
    public let catalog: ref<NMVanillaCatalog>;
    public let pinned: ref<NightMapLayer>;
    public let diff: ref<NMVanillaDiff>;
    private let api: wref<NightMap>;
    private let gi: GameInstance;
    private let layers: array<ref<NightMapLayer>>;          // index = filter slot (0..Count(), Count() = Other)
    private let listeners: array<ref<NMVanillaListener>>;   // same index; pinned listener separate
    private let pinnedListener: ref<NMVanillaListener>;
    private let lastPollMs: Float;
    private let polledOnce: Bool;
    private let loggedVariants: array<Int32>;

    public static func PollMs() -> Float { return 1500.0; }

    public static func Create(api: ref<NightMap>, gi: GameInstance) -> ref<NMVanilla> {
        let v = new NMVanilla();
        v.api = api;
        v.gi = gi;
        v.diff = NMVanillaDiff.Create();
        return v;
    }

    // Builds the catalogue and layers on first use (TweakDB is certainly ready by the first map open).
    private func EnsureLayers() {
        if IsDefined(this.catalog) { return; }
        this.catalog = NMVanillaCatalog.Build();
        let n = this.catalog.Count();
        let i = 0;
        while i <= n {
            let L = this.api.CreateLayer(this.catalog.LayerId(i), this.catalog.DisplayName(i), this.catalog.Priority(i));
            L.SetPinStyle(NightMapPinStyle.Icon);
            let cat = this.catalog.CategoryName(i);
            let isOther = this.catalog.IsOther(i);
            let first = isOther ? gamedataMappinVariant.Invalid : this.catalog.firstVariant[i];
            let color = isOther ? NMTheme.Muted() : NMVanillaStyle.Color(first, gamedataMappinPhase.DefaultPhase);
            L.SetCategory(cat, this.catalog.DisplayName(i), color);
            this.api.SetCategoryIcon(cat, NMTheme.MappinAtlas(), isOther ? n"quest" : NMVanillaStyle.PartOf(first));
            let li = new NMVanillaListener();
            li.owner = this;
            li.slot = i;
            L.SetListener(li);
            ArrayPush(this.layers, L);
            ArrayPush(this.listeners, li);
            i += 1;
        }
        this.pinned = this.api.CreateLayer(n"Vanilla.Pinned", "Tracked", 100);
        this.pinned.SetPinStyle(NightMapPinStyle.Icon);
        this.pinned.SetClustering(false);
        this.pinned.SetCategory(n"vanilla.pinned", "TRACKED", NMTheme.VanillaStateColor(n"Quest"));
        this.api.SetCategoryIcon(n"vanilla.pinned", NMTheme.MappinAtlas(), n"quest");
        this.pinnedListener = new NMVanillaListener();
        this.pinnedListener.owner = this;
        this.pinnedListener.slot = -2;
        this.pinned.SetListener(this.pinnedListener);
    }

    public func LayerForSlot(slot: Int32) -> ref<NightMapLayer> {
        if slot == -2 { return this.pinned; }
        return slot >= 0 && slot < ArraySize(this.layers) ? this.layers[slot] : null;
    }

    private func ListenerForSlot(slot: Int32) -> ref<NMVanillaListener> {
        if slot == -2 { return this.pinnedListener; }
        return slot >= 0 && slot < ArraySize(this.listeners) ? this.listeners[slot] : null;
    }

    public func EntryFor(slot: Int32, item: Int32) -> ref<NMVanillaEntry> {
        let li = this.ListenerForSlot(slot);
        return IsDefined(li) ? li.Get(item) : null;
    }

    // Polls when forced or when PollMs has passed since the last poll. Returns true if it polled.
    public func Tick(nowMs: Float, force: Bool) -> Bool {
        if !force && this.polledOnce && nowMs - this.lastPollMs < NMVanilla.PollMs() {
            return false;
        }
        this.lastPollMs = nowMs;
        this.polledOnce = true;
        let arr: array<ref<IMappin>>;
        let ms = GameInstance.GetMappinSystem(this.gi);
        ms.GetMappins(gamemappinsMappinTargetType.Map, arr);
        let manual = ms.GetManuallyTrackedMappinID();
        this.PollFrom(arr, manual.value);
        return true;
    }

    public func PollFrom(arr: array<ref<IMappin>>, manualKey: Uint64) {
        this.EnsureLayers();
        let snaps: array<ref<NMVanillaSnap>>;
        for m in arr {
            if IsDefined(m) {
                let id = m.GetNewMappinID();
                let pos = m.GetWorldPosition();
                let v = m.GetVariant();
                let filter = this.catalog.FilterIndexOf(v);
                if this.catalog.IsOther(filter) && m.IsVisible() {
                    this.LogOnce(v);
                }
                let tracked = m.IsPlayerTracked() || (manualKey != 0ul && id.value == manualKey);
                let s = NMVanillaSnap.Make(id.value, pos.X, pos.Y, v, m.GetPhase(), m.IsVisible(), tracked, filter);
                s.z = pos.Z;
                ArrayPush(snaps, s);
            }
        }
        this.diff.Apply(snaps, this);
        if this.diff.added + this.diff.removed > 0 {
            NMLog.Info("vanilla|poll|n=" + ToString(ArraySize(arr)) + "|live=" + ToString(this.diff.live) + "|added=" + ToString(this.diff.added)
                + "|changed=" + ToString(this.diff.changed) + "|removed=" + ToString(this.diff.removed));
        }
    }

    // Logs a variant the catalogue does not know, once per variant. Returns true when it logged.
    private func LogOnce(v: gamedataMappinVariant) -> Bool {
        let key = Cast<Int32>(EnumInt(v));
        if ArrayContains(this.loggedVariants, key) {
            return false;
        }
        ArrayPush(this.loggedVariants, key);
        NMLog.Info("vanilla|unknown-variant|" + ToString(v) + "|shown in Other");
        return true;
    }

    public func LogOnceForTest(v: gamedataMappinVariant) -> Bool {
        return this.LogOnce(v);
    }

    private func ItemFor(s: ref<NMVanillaSnap>, slot: Int32) -> ref<NightMapItem> {
        let catName = slot == -2 ? n"vanilla.pinned" : this.catalog.CategoryName(slot);
        let completed = Equals(s.phase, gamedataMappinPhase.CompletedPhase);
        return NightMapItem.Create(new Vector4(s.x, s.y, s.z, 1.0), catName, NMTheme.MappinAtlas(), NMVanillaStyle.PartOf(s.variant))
            .WithTint(NMVanillaStyle.Color(s.variant, s.phase))
            .WithEmphasis(s.tracked)
            .WithOpacity(completed ? NMVanillaStyle.CompletedOpacity() : 1.0);
    }

    // ---- NMVanillaSink ----
    public func OnAdd(e: ref<NMVanillaEntry>) {
        let L = this.LayerForSlot(e.slot);
        if !IsDefined(L) { return; }
        e.item = L.Add(this.ItemFor(e.snap, e.slot));
        if e.item >= 0 { this.ListenerForSlot(e.slot).Set(e.item, e); }
    }

    public func OnChange(e: ref<NMVanillaEntry>, s: ref<NMVanillaSnap>) {
        let newSlot = NMVanillaRules.Slot(s);
        if newSlot == e.slot && e.item >= 0 {
            this.LayerForSlot(e.slot).Update(e.item, this.ItemFor(s, newSlot));
            return;
        }
        this.OnRemove(e);
        let L = this.LayerForSlot(newSlot);
        if !IsDefined(L) { return; }
        e.item = L.Add(this.ItemFor(s, newSlot));
        if e.item >= 0 { this.ListenerForSlot(newSlot).Set(e.item, e); }
    }

    public func OnRemove(e: ref<NMVanillaEntry>) {
        let L = this.LayerForSlot(e.slot);
        if IsDefined(L) && e.item >= 0 {
            L.Remove(e.item);
            this.ListenerForSlot(e.slot).Set(e.item, null);
        }
        e.item = -1;
    }

    // Card and activation: implemented in Task 6.
    public func Details(e: ref<NMVanillaEntry>) -> ref<NightMapDetails> { return null; }
    public func Activate(e: ref<NMVanillaEntry>) {}
}
```

- [ ] **Step 4: Wire it into the system**

In `Core/NightMapSystem.reds`:
1. Add a field: `private let vanilla: ref<NMVanilla>;` and an accessor `public func Vanilla() -> ref<NMVanilla> { return this.vanilla; }`.
2. In `OnAttach`, after the `SetWorld` block: `this.vanilla = NMVanilla.Create(this.api, this.GetGameInstance());`.
3. At the end of `OnOpened`: `this.vanilla.Tick(NMClock.NowMs(), true);`.
4. At the top of `UpdateModules` (after `let l = this.panel.layout;`): `this.vanilla.Tick(NMClock.NowMs(), false);`.

- [ ] **Step 5: Run the compile check to verify it passes**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 6: Commit**

```bash
git add r6/scripts/NightMap/Vanilla/Vanilla.reds r6/scripts/NightMap/Core/NightMapSystem.reds r6/scripts/NightMap/Debug/SelfTestVanilla.reds
git commit -m "feat(vanilla): mirror vanilla map markers into icon-style layers while open

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Info card details and actions (track quest, clear waypoint)

**Files:**
- Create: `r6/scripts/NightMap/Vanilla/Text.reds`
- Create: `r6/scripts/NightMap/Vanilla/Tracking.reds`
- Modify: `r6/scripts/NightMap/Vanilla/Vanilla.reds` (replace the `Details` and `Activate` stubs)
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds` (refresh the header and poll after `Activate()`)
- Modify: `r6/scripts/NightMap/Debug/SelfTestVanilla.reds`

**Interfaces:**
- Consumes:
  - `NMMath.FormatMeters(m: Float) -> String`;
  - `NightMapDetails.Create/WithSubtitle/AddRow/AddAction`;
  - `NMInput.KeyName(key)`, `NightMapSettings.Get(gi).keyAct`;
  - `GameInstance.GetJournalManager(gi)`: `GetEntry(hash: Uint32)`, `GetParentEntry(e)`, `GetTrackedEntry()`,
    `TrackEntry(e)`, `GetEntryHash(e) -> Int32`, `GetQuestType(q)`;
  - `JournalQuest.GetTitle(jm)`, `JournalQuestObjectiveBase.GetDescription()`;
  - `MappinSystem.GetMappin(id: NewMappinID)`, `UnregisterMappin(id)`, `UntrackMappin()`,
    `GetManuallyTrackedMappinID()`;
  - `FastTravelMappin.GetPointData()` → `GetPointDisplayName()`, `GetDistrictDisplayName()`;
  - `MappinUIUtils.MappinToString(v) -> CName`.
- Produces:
  - `NMVanillaText.Loc(s: String) -> String`; `NMVanillaText.Title(m: ref<IMappin>, v: gamedataMappinVariant) -> String`;
    `NMVanillaText.LabelOf(v) -> String`
  - `public class NMQuestInfo { ok: Bool; title: String; objective: String; entry: wref<JournalEntry> }`
  - `NMVanillaTracking.JournalHash(m) -> Uint32`
  - `NMVanillaTracking.QuestInfo(gi, m) -> ref<NMQuestInfo>`
  - `NMVanillaTracking.CanTrackQuest(gi, m) -> Bool`
  - `NMVanillaTracking.IsQuestTracked(gi, m) -> Bool`
  - `NMVanillaTracking.TrackQuest(gi, m) -> Bool`
  - `NMVanillaTracking.ClearManual(gi) -> Bool`
  - `NMVanillaTracking.ManualKey(gi) -> Uint64`
  - `NMVanilla.Resolve(e) -> ref<IMappin>`; `NMVanilla.lastAction: String` (for tests/log)

- [ ] **Step 1: Write the failing self-tests**

In `SelfTestVanilla.reds`, add `NMVanillaTests.CardCases(t);` to `Run`, and add:

```swift
    private static func CardCases(t: ref<NMSelfTest>) {
        t.Check("text.loc_passthrough", Equals(NMVanillaText.Loc("Plain"), "Plain") && Equals(NMVanillaText.Loc(""), ""), "");
        t.Check("text.loc_key_resolves", NotEquals(NMVanillaText.Loc("LocKey#44637"), "LocKey#44637"), NMVanillaText.Loc("LocKey#44637"));
        t.Check("text.label_fallback", StrLen(NMVanillaText.LabelOf(gamedataMappinVariant.ServicePointDropPointVariant)) > 0, NMVanillaText.LabelOf(gamedataMappinVariant.ServicePointDropPointVariant));
        let none = NMVanillaTracking.QuestInfo(GetGameInstance(), null);
        t.Check("tracking.null_safe", !none.ok && !NMVanillaTracking.CanTrackQuest(GetGameInstance(), null), "");
        // Details for a mirrored entry without a live mappin (key 0): falls back to the variant label, no actions.
        let api = NMVanillaTests.TestApi();
        let v = NMVanilla.Create(api, GetGameInstance());
        let empty: array<ref<IMappin>>;
        v.PollFrom(empty, 0ul);   // builds catalogue and layers
        let e = new NMVanillaEntry();
        e.key = 0ul;
        e.slot = v.catalog.FilterIndexOf(gamedataMappinVariant.ServicePointFoodVariant);
        e.snap = NMVanillaSnap.Make(0ul, 0.0, 0.0, gamedataMappinVariant.ServicePointFoodVariant, gamedataMappinPhase.DefaultPhase, true, false, e.slot);
        let d = v.Details(e);
        t.Check("vanilla.card_defined", IsDefined(d) && StrLen(d.title) > 0 && Equals(d.category, v.catalog.DisplayName(e.slot)), IsDefined(d) ? d.title : "null");
        t.Check("vanilla.no_track_action_for_vendor", IsDefined(d) && ArraySize(d.actionKeys) == 0, "");
        v.Activate(e);
        t.Check("vanilla.activate_vendor_noop", Equals(v.lastAction, "none"), v.lastAction);
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE FAILED` (unresolved `NMVanillaText`, `NMVanillaTracking`, `lastAction`).

- [ ] **Step 3: Implement Text.reds**

```swift
module NightMap

public abstract class NMVanillaText {
    // Mappin and journal strings arrive as "LocKey#NNN"; resolve those, pass anything else through.
    public static func Loc(s: String) -> String {
        if StrBeginsWith(s, "LocKey#") {
            return GetLocalizedText(s);
        }
        return s;
    }

    // Localized type label, e.g. "Drop Point" (UI-MappinTypes-*).
    public static func LabelOf(v: gamedataMappinVariant) -> String {
        let key = MappinUIUtils.MappinToString(v);
        let s = GetLocalizedTextByKey(key);
        return StrLen(s) > 0 ? s : ToString(v);
    }

    // Fast-travel point name, else the mappin's display name, else the type label.
    public static func Title(m: ref<IMappin>, v: gamedataMappinVariant) -> String {
        if IsDefined(m) {
            let ft = m as FastTravelMappin;
            if IsDefined(ft) {
                let pd = ft.GetPointData();
                if IsDefined(pd) {
                    let n = NMVanillaText.Loc(pd.GetPointDisplayName());
                    if StrLen(n) > 0 { return n; }
                }
            }
            let dn = NMVanillaText.Loc(m.GetDisplayName());
            if StrLen(dn) > 0 { return dn; }
        }
        return NMVanillaText.LabelOf(v);
    }

    public static func District(m: ref<IMappin>) -> String {
        let ft = m as FastTravelMappin;
        if IsDefined(ft) {
            let pd = ft.GetPointData();
            if IsDefined(pd) { return NMVanillaText.Loc(pd.GetDistrictDisplayName()); }
        }
        return "";
    }
}
```

- [ ] **Step 4: Implement Tracking.reds**

```swift
module NightMap

public class NMQuestInfo {
    public let ok: Bool;
    public let title: String;
    public let objective: String;
    public let entry: wref<JournalEntry>;   // the mappin's JournalQuestMapPin (what vanilla passes to TrackEntry)
}

// Quest tracking and the manually tracked pin. Mirrors worldMap.script TryTrackQuestOrSetWaypoint (tracking part)
// and autoDriveSystem.script:373-379 (clearing). Creating waypoints needs the native plugin (sub-project 3).
public abstract class NMVanillaTracking {
    public static func JournalHash(m: ref<IMappin>) -> Uint32 {
        let q = m as QuestMappin;
        if IsDefined(q) { return q.GetJournalPathHash(); }
        let p = m as PointOfInterestMappin;
        if IsDefined(p) { return p.GetJournalPathHash(); }
        return 0u;
    }

    public static func QuestInfo(gi: GameInstance, m: ref<IMappin>) -> ref<NMQuestInfo> {
        let info = new NMQuestInfo();
        if !IsDefined(m) { return info; }
        let hash = NMVanillaTracking.JournalHash(m);
        if hash == 0u { return info; }
        let jm = GameInstance.GetJournalManager(gi);
        let pin = jm.GetEntry(hash);
        if !IsDefined(pin) { return info; }
        info.entry = pin;
        let obj = jm.GetParentEntry(pin) as JournalQuestObjectiveBase;
        if IsDefined(obj) {
            info.objective = NMVanillaText.Loc(obj.GetDescription());
            let phase = jm.GetParentEntry(obj);
            let quest = jm.GetParentEntry(phase) as JournalQuest;
            if IsDefined(quest) { info.title = NMVanillaText.Loc(quest.GetTitle(jm)); }
        }
        info.ok = true;
        return info;
    }

    public static func CanTrackQuest(gi: GameInstance, m: ref<IMappin>) -> Bool {
        if !IsDefined(m) || !NMVanillaStyle.CanQuestTrack(m.GetVariant()) { return false; }
        let info = NMVanillaTracking.QuestInfo(gi, m);
        return info.ok && IsDefined(info.entry);
    }

    // True when the mappin's objective is the tracked journal entry.
    public static func IsQuestTracked(gi: GameInstance, m: ref<IMappin>) -> Bool {
        let info = NMVanillaTracking.QuestInfo(gi, m);
        if !info.ok { return false; }
        let jm = GameInstance.GetJournalManager(gi);
        let tracked = jm.GetTrackedEntry();
        let obj = jm.GetParentEntry(info.entry);
        return IsDefined(tracked) && IsDefined(obj) && jm.GetEntryHash(tracked) == jm.GetEntryHash(obj);
    }

    public static func TrackQuest(gi: GameInstance, m: ref<IMappin>) -> Bool {
        if !NMVanillaTracking.CanTrackQuest(gi, m) { return false; }
        let info = NMVanillaTracking.QuestInfo(gi, m);
        GameInstance.GetJournalManager(gi).TrackEntry(info.entry);
        return true;
    }

    public static func ManualKey(gi: GameInstance) -> Uint64 {
        let id = GameInstance.GetMappinSystem(gi).GetManuallyTrackedMappinID();
        return id.value;
    }

    // Clears the vanilla custom waypoint, or stops tracking a manually tracked non-quest pin.
    public static func ClearManual(gi: GameInstance) -> Bool {
        let ms = GameInstance.GetMappinSystem(gi);
        let id = ms.GetManuallyTrackedMappinID();
        if id.value == 0ul { return false; }
        let m = ms.GetMappin(id);
        if IsDefined(m) && Equals(m.GetVariant(), gamedataMappinVariant.CustomPositionVariant) {
            ms.UnregisterMappin(id);
        } else {
            ms.UntrackMappin();
        }
        return true;
    }
}
```

- [ ] **Step 5: Replace the Details/Activate stubs in Vanilla.reds**

Add the field `public let lastAction: String;` to `NMVanilla`, and replace the two stub functions with:

```swift
    public func Resolve(e: ref<NMVanillaEntry>) -> ref<IMappin> {
        if !IsDefined(e) || e.key == 0ul { return null; }
        let id: NewMappinID;
        id.value = e.key;
        return GameInstance.GetMappinSystem(this.gi).GetMappin(id);
    }

    private func ActKey() -> String {
        let s = NightMapSettings.Get(this.gi);
        return IsDefined(s) ? NMInput.KeyName(s.keyAct) : "NUM 0";
    }

    public func Details(e: ref<NMVanillaEntry>) -> ref<NightMapDetails> {
        if !IsDefined(e) || !IsDefined(e.snap) { return null; }
        let s = e.snap;
        let m = this.Resolve(e);
        let filterSlot = s.filter >= 0 ? s.filter : this.catalog.Count();
        let d = NightMapDetails.Create(this.catalog.DisplayName(filterSlot), NMVanillaText.Title(m, s.variant));
        if IsDefined(m) {
            let district = NMVanillaText.District(m);
            if StrLen(district) > 0 { d.WithSubtitle(district); }
            d.AddRow("Distance", NMMath.FormatMeters(m.GetDistanceToPlayer()));
        }
        if Equals(s.phase, gamedataMappinPhase.UndiscoveredPhase) { d.AddRow("Status", "Undiscovered"); }
        if Equals(s.phase, gamedataMappinPhase.CompletedPhase) { d.AddRow("Status", "Completed"); }
        let manual = e.key != 0ul && NMVanillaTracking.ManualKey(this.gi) == e.key;
        let info = NMVanillaTracking.QuestInfo(this.gi, m);
        if info.ok {
            if StrLen(info.title) > 0 { d.AddRow("Quest", info.title); }
            if StrLen(info.objective) > 0 { d.AddRow("Objective", info.objective); }
        }
        if NMVanillaTracking.CanTrackQuest(this.gi, m) {
            if NMVanillaTracking.IsQuestTracked(this.gi, m) {
                d.AddRow("Status", "Tracked");
            } else {
                d.AddAction(this.ActKey(), "Track quest");
            }
        } else if manual {
            d.AddRow("Status", "Tracked");
            d.AddAction(this.ActKey(), Equals(s.variant, gamedataMappinVariant.CustomPositionVariant) ? "Clear waypoint" : "Stop tracking");
        } else {
            d.AddRow("Waypoint", "Coming with the native plugin");
        }
        return d;
    }

    // NUM 0 on a vanilla marker: track its quest, or clear the manual waypoint/tracking. Re-polls immediately.
    public func Activate(e: ref<NMVanillaEntry>) {
        this.lastAction = "none";
        if !IsDefined(e) { return; }
        let m = this.Resolve(e);
        if NMVanillaTracking.CanTrackQuest(this.gi, m) && !NMVanillaTracking.IsQuestTracked(this.gi, m) {
            if NMVanillaTracking.TrackQuest(this.gi, m) { this.lastAction = "track"; }
        } else if e.key != 0ul && NMVanillaTracking.ManualKey(this.gi) == e.key {
            if NMVanillaTracking.ClearManual(this.gi) { this.lastAction = "clear"; }
        }
        if NotEquals(this.lastAction, "none") {
            NMLog.Info("vanilla|action|" + this.lastAction + "|" + ToString(e.snap.variant));
            this.Tick(0.0, true);
        }
    }
```

- [ ] **Step 6: Refresh the header after an action**

In `NightMapSystem.UpdateModules`, change the act block to:

```swift
        if this.input.act {
            this.input.act = false;
            this.Activate();
            this.UpdateHeader();
        }
```

- [ ] **Step 7: Run the compile check to verify it passes**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE OK`. If `JournalQuestObjectiveBase`, `GetEntryHash` or `GetPointData` names fail, check
`.scratch/refs/cp-scripts/scripts/core/systems/journalManager.script` and `core/systems/fastTravelSystem.script` for the
exact names, and keep the behaviour.

- [ ] **Step 8: Commit**

```bash
git add r6/scripts/NightMap/Vanilla/Text.reds r6/scripts/NightMap/Vanilla/Tracking.reds r6/scripts/NightMap/Vanilla/Vanilla.reds r6/scripts/NightMap/Core/NightMapSystem.reds r6/scripts/NightMap/Debug/SelfTestVanilla.reds
git commit -m "feat(vanilla): marker info card, track quest, clear waypoint

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Tracked-quest header

**Files:**
- Create: `r6/scripts/NightMap/Vanilla/QuestHeader.reds`
- Modify: `r6/scripts/NightMap/Render/Panel.reds`: fields, plus the header creation at lines 361-369.
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds`: `UpdateHeader`, at lines 541-552.
- Modify: `r6/scripts/NightMap/Debug/SelfTestVanilla.reds`

**Interfaces:**
- Consumes: the JournalManager (`GetTrackedEntry`, `GetParentEntry`, `GetQuestType`, `GetObjectiveCurrentCounter`,
  `GetObjectiveTotalCounter`); `NMVanillaText.Loc/LabelOf`; `NMVanillaTracking.ManualKey`.
- Produces:
  - `public class NMQuestHeaderInfo { visible: Bool; title: String; objective: String; isQuest: Bool }`
  - `NMQuestHeader.Read(gi: GameInstance) -> ref<NMQuestHeaderInfo>`
  - `NMQuestHeader.FormatObjective(text: String, cur: Int32, total: Int32) -> String`
  - `NMPanel.questTitle: ref<inkText>`, `NMPanel.questObjective: ref<inkText>`

Ruling: spec §9 names a journal Tracked callback. This plan refreshes the header from the existing 30-frame
`UpdateHeader`, on open, and after a NightMap action instead. The behaviour is the same, it does nothing while closed,
and there is no callback registration lifecycle.

- [ ] **Step 1: Write the failing self-tests**

In `SelfTestVanilla.reds`, add `NMVanillaTests.HeaderCases(t);` to `Run`, and add:

```swift
    private static func HeaderCases(t: ref<NMSelfTest>) {
        t.Check("header.objective_plain", Equals(NMQuestHeader.FormatObjective("Talk to Judy", 0, 0), "Talk to Judy"), "");
        t.Check("header.objective_counter", Equals(NMQuestHeader.FormatObjective("Collect parts", 2, 5), "Collect parts (2/5)"), NMQuestHeader.FormatObjective("Collect parts", 2, 5));
        let info = NMQuestHeader.Read(GetGameInstance());
        t.Check("header.read_safe", IsDefined(info) && (!info.visible || StrLen(info.title) > 0), IsDefined(info) ? info.title : "null");
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE FAILED` (unresolved `NMQuestHeader`).

- [ ] **Step 3: Implement QuestHeader.reds**

```swift
module NightMap

public class NMQuestHeaderInfo {
    public let visible: Bool;
    public let title: String;
    public let objective: String;
    public let isQuest: Bool;   // Quest colour (main/side/minor/courier side) vs Gigs colour (gigs, NCPD, contracts)
}

// Tracked quest + objective for the panel header (worldMap.script UpdateTrackedQuest, quest_tracker.script:228-262).
public abstract class NMQuestHeader {
    public static func FormatObjective(text: String, cur: Int32, total: Int32) -> String {
        return total > 0 ? text + " (" + ToString(cur) + "/" + ToString(total) + ")" : text;
    }

    public static func Read(gi: GameInstance) -> ref<NMQuestHeaderInfo> {
        let h = new NMQuestHeaderInfo();
        let jm = GameInstance.GetJournalManager(gi);
        let obj = jm.GetTrackedEntry() as JournalQuestObjectiveBase;
        if IsDefined(obj) {
            let phase = jm.GetParentEntry(obj);
            let quest = jm.GetParentEntry(phase) as JournalQuest;
            h.objective = NMQuestHeader.FormatObjective(NMVanillaText.Loc(obj.GetDescription()),
                jm.GetObjectiveCurrentCounter(obj), jm.GetObjectiveTotalCounter(obj));
            if IsDefined(quest) {
                h.title = NMVanillaText.Loc(quest.GetTitle(jm));
                let qt = jm.GetQuestType(quest);
                h.isQuest = Equals(qt, gameJournalQuestType.MainQuest) || Equals(qt, gameJournalQuestType.SideQuest)
                    || Equals(qt, gameJournalQuestType.MinorQuest) || Equals(qt, gameJournalQuestType.CourierSideQuest);
            }
            h.visible = StrLen(h.title) > 0 || StrLen(h.objective) > 0;
            return h;
        }
        if NMVanillaTracking.ManualKey(gi) != 0ul {
            h.visible = true;
            h.isQuest = true;
            h.title = NMVanillaText.LabelOf(gamedataMappinVariant.CustomPositionVariant);
        }
        return h;
    }
}
```

- [ ] **Step 4: Add the header widgets to the panel**

In `Render/Panel.reds`, add the fields `public let questTitle: ref<inkText>;` and `public let questObjective: ref<inkText>;`.
In the header block (lines 361-369), insert before `p.warning = ...`:

```swift
    p.questTitle = NMUi.Text(p.root, NMTheme.HeadingFont(), n"Bold", Cast<Int32>(34.0 * s), NMTheme.VanillaStateColor(n"Quest"));
    p.questTitle.SetTranslation(new Vector2(67.0 * s, 178.0 * s));
    p.questTitle.SetVisible(false);
    p.questObjective = NMUi.Text(p.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(30.0 * s), NMTheme.Text());
    p.questObjective.SetTranslation(new Vector2(67.0 * s, 222.0 * s));
    p.questObjective.SetVisible(false);
```

Change the warning translation from `176.0 * s` to `270.0 * s`.

- [ ] **Step 5: Update the header**

In `NightMapSystem.UpdateHeader()`, after `this.panel.subtitle.SetText(this.DistrictName());`, add:

```swift
        let q = NMQuestHeader.Read(this.GetGameInstance());
        this.panel.questTitle.SetVisible(q.visible);
        this.panel.questObjective.SetVisible(q.visible && StrLen(q.objective) > 0);
        if q.visible {
            this.panel.questTitle.SetText(StrUpper(q.title));
            this.panel.questTitle.SetTintColor(NMTheme.VanillaStateColor(q.isQuest ? n"Quest" : n"Gigs"));
            this.panel.questObjective.SetText(q.objective);
        }
```

- [ ] **Step 6: Run the compile check to verify it passes**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 7: Commit**

```bash
git add r6/scripts/NightMap/Vanilla/QuestHeader.reds r6/scripts/NightMap/Render/Panel.reds r6/scripts/NightMap/Core/NightMapSystem.reds r6/scripts/NightMap/Debug/SelfTestVanilla.reds
git commit -m "feat(vanilla): tracked quest and objective in the map header

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Filters (NUM / quick views, Mod Settings toggles)

**Files:**
- Create: `r6/scripts/NightMap/Vanilla/Filters.reds`
- Modify: `r6/scripts/NightMap/Core/Settings.reds`: `keyFilter` and 12 Bools. The Debug category order becomes `"3"`.
- Modify: `r6/scripts/NightMap/Core/Input.reds`:
  - the `filter` flag;
  - `ResetHeld`;
  - the `Handle` line before `return false`;
  - `HintText`.
- Modify: `r6/scripts/NightMap/Vanilla/Vanilla.reds`: `ApplyFilters`, `SetEnabled`.
- Modify: `r6/scripts/NightMap/Core/NightMapSystem.reds`:
  - a `filterView` field;
  - filter key handling in `UpdateModules`;
  - apply on open;
  - subtitle.
- Modify: `r6/scripts/NightMap/Debug/SelfTestVanilla.reds`
- Modify: `README.md`

**Interfaces:**
- Consumes: `NMVanillaCatalog.TypeOf/IsOther/Count`, `NMVanilla.LayerForSlot`.
- Produces:
  - `NightMapSettings.keyFilter: EInputKey = EInputKey.IK_NumSlash`
  - Bools, all default `true`: `filterJobs`, `filterGigs`, `filterPsycho`, `filterNcpd`, `filterFastTravel`,
    `filterRipperdoc`, `filterVendor`, `filterAutofixer`, `filterDropPoint`, `filterApartmentRent`, `filterTarot`,
    `filterYourProperty`
  - `NMInput.filter: Bool`
  - `NMVanillaFilters.ViewCount() -> Int32` (3); `ViewName(view: Int32) -> String` ("ALL", "JOBS", "SERVICES")
  - `NMVanillaFilters.InView(view: Int32, t: gamedataWorldMapFilter, isOther: Bool) -> Bool`
  - `NMVanillaFilters.Enabled(s: ref<NightMapSettings>, t: gamedataWorldMapFilter) -> Bool`
  - `NMVanillaFilters.Visible(view, s, t, isOther) -> Bool`
  - `NMVanilla.ApplyFilters(view: Int32, s: ref<NightMapSettings>)`; `NMVanilla.SetEnabled(on: Bool)`;
    `NMVanilla.enabled: Bool`

- [ ] **Step 1: Write the failing self-tests**

In `SelfTestVanilla.reds`, add `NMVanillaTests.FilterCases(t);` to `Run`, and add:

```swift
    private static func FilterCases(t: ref<NMSelfTest>) {
        t.Check("filter.views", NMVanillaFilters.ViewCount() == 3 && Equals(NMVanillaFilters.ViewName(1), "JOBS"), "");
        t.Check("filter.all_has_everything", NMVanillaFilters.InView(0, gamedataWorldMapFilter.TarotFilter, false) && NMVanillaFilters.InView(0, gamedataWorldMapFilter.NoFilter, true), "");
        t.Check("filter.jobs", NMVanillaFilters.InView(1, gamedataWorldMapFilter.Gigs, false) && NMVanillaFilters.InView(1, gamedataWorldMapFilter.Story, false)
            && !NMVanillaFilters.InView(1, gamedataWorldMapFilter.VendorFilter, false) && !NMVanillaFilters.InView(1, gamedataWorldMapFilter.NoFilter, true), "");
        t.Check("filter.services", NMVanillaFilters.InView(2, gamedataWorldMapFilter.FastTravel, false) && NMVanillaFilters.InView(2, gamedataWorldMapFilter.DropPoint, false)
            && !NMVanillaFilters.InView(2, gamedataWorldMapFilter.Quest, false) && !NMVanillaFilters.InView(2, gamedataWorldMapFilter.TarotFilter, false), "");
        let s = new NightMapSettings();
        s.filterVendor = false;
        t.Check("filter.toggle_off", !NMVanillaFilters.Visible(0, s, gamedataWorldMapFilter.VendorFilter, false) && NMVanillaFilters.Visible(0, s, gamedataWorldMapFilter.FastTravel, false), "");
        t.Check("filter.other_ignores_toggles", NMVanillaFilters.Visible(0, s, gamedataWorldMapFilter.NoFilter, true), "");
        // Layer visibility applied, pinned always visible, disabled hides everything.
        let api = NMVanillaTests.TestApi();
        let v = NMVanilla.Create(api, GetGameInstance());
        let empty: array<ref<IMappin>>;
        v.PollFrom(empty, 0ul);
        v.ApplyFilters(1, s);
        let vend = v.LayerForSlot(v.catalog.FilterIndexOf(gamedataMappinVariant.ServicePointFoodVariant));
        let gigs = v.LayerForSlot(v.catalog.FilterIndexOf(gamedataMappinVariant.RetrievingVariant));
        t.Check("filter.apply_layers", !vend.visible && gigs.visible && v.pinned.visible, "");
        v.SetEnabled(false);
        t.Check("filter.disabled_hides_all", !gigs.visible && !v.pinned.visible && !v.Tick(999999.0, false), "");
        v.SetEnabled(true);
        t.Check("filter.reenabled", v.pinned.visible, "");
        // Input: the filter key sets the flag only while the map is open.
        let ks = new NightMapSettings();
        ks.keyFilter = EInputKey.IK_NumSlash;
        let inp = new NMInput();
        inp.Handle(ks, EInputKey.IK_NumSlash, EInputAction.IACT_Press, false, false, false, false);
        let closedIgnored = !inp.filter;
        inp.Handle(ks, EInputKey.IK_NumSlash, EInputAction.IACT_Press, false, false, false, true);
        t.Check("filter.key", closedIgnored && inp.filter, "");
    }
```

- [ ] **Step 2: Run the compile check to verify it fails**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE FAILED`.

- [ ] **Step 3: Add the settings**

In `Core/Settings.reds`, after `keyAct` in "Keys":

```swift
    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Cycle marker filter")
    @runtimeProperty("ModSettings.description", "Cycles the map markers shown: All, Jobs, Services.")
    public let keyFilter: EInputKey = EInputKey.IK_NumSlash;
```

Then add 12 Bools in a new category, all of this form, with `ModSettings.category` `"Map filters"` and
`ModSettings.category.order` `"2"`:

```swift
    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Jobs")
    @runtimeProperty("ModSettings.description", "Show main and side job markers.")
    public let filterJobs: Bool = true;
```

| field | displayName | description |
|---|---|---|
| `filterJobs` | Jobs | Show main and side job markers. |
| `filterGigs` | Gigs | Show gig and fixer markers. |
| `filterPsycho` | Cyberpsycho Sighting | Show cyberpsycho sightings. |
| `filterNcpd` | NCPD Scanner | Show NCPD scanner hustles, stashes and outposts. |
| `filterFastTravel` | Fast Travel | Show fast-travel points and NCART stations. |
| `filterRipperdoc` | Ripperdoc | Show ripperdocs. |
| `filterVendor` | Vendor | Show vendors. |
| `filterAutofixer` | Autofixer | Show vehicles for sale. |
| `filterDropPoint` | Drop Point | Show drop points. |
| `filterApartmentRent` | Apartment for Rent | Show apartments for rent. |
| `filterTarot` | TAROT | Show tarot graffiti. |
| `filterYourProperty` | Your Apartments | Show your apartments, vehicles and waypoint. |

Change the Debug setting's `ModSettings.category.order` from `"2"` to `"3"`.

- [ ] **Step 4: Implement Filters.reds**

```swift
module NightMap

// Quick views (NUM /) x per-category Mod Settings toggles. View 0 = all; Other and TAROT appear only in view 0.
public abstract class NMVanillaFilters {
    public static func ViewCount() -> Int32 { return 3; }

    public static func ViewName(view: Int32) -> String {
        if view == 1 { return "JOBS"; }
        if view == 2 { return "SERVICES"; }
        return "ALL";
    }

    public static func InView(view: Int32, t: gamedataWorldMapFilter, isOther: Bool) -> Bool {
        if view == 0 { return true; }
        if isOther { return false; }
        if view == 1 {
            return Equals(t, gamedataWorldMapFilter.Quest) || Equals(t, gamedataWorldMapFilter.Gigs)
                || Equals(t, gamedataWorldMapFilter.PsychoFilter) || Equals(t, gamedataWorldMapFilter.Story);
        }
        return Equals(t, gamedataWorldMapFilter.RipperdocFilter) || Equals(t, gamedataWorldMapFilter.VendorFilter)
            || Equals(t, gamedataWorldMapFilter.AutofixerFilter) || Equals(t, gamedataWorldMapFilter.DropPoint)
            || Equals(t, gamedataWorldMapFilter.FastTravel) || Equals(t, gamedataWorldMapFilter.ApartmentToPurchaseFilter)
            || Equals(t, gamedataWorldMapFilter.CommonFilter);
    }

    public static func Enabled(s: ref<NightMapSettings>, t: gamedataWorldMapFilter) -> Bool {
        if !IsDefined(s) { return true; }
        if Equals(t, gamedataWorldMapFilter.Quest) { return s.filterJobs; }
        if Equals(t, gamedataWorldMapFilter.Gigs) { return s.filterGigs; }
        if Equals(t, gamedataWorldMapFilter.PsychoFilter) { return s.filterPsycho; }
        if Equals(t, gamedataWorldMapFilter.Story) { return s.filterNcpd; }
        if Equals(t, gamedataWorldMapFilter.FastTravel) { return s.filterFastTravel; }
        if Equals(t, gamedataWorldMapFilter.RipperdocFilter) { return s.filterRipperdoc; }
        if Equals(t, gamedataWorldMapFilter.VendorFilter) { return s.filterVendor; }
        if Equals(t, gamedataWorldMapFilter.AutofixerFilter) { return s.filterAutofixer; }
        if Equals(t, gamedataWorldMapFilter.DropPoint) { return s.filterDropPoint; }
        if Equals(t, gamedataWorldMapFilter.ApartmentToPurchaseFilter) { return s.filterApartmentRent; }
        if Equals(t, gamedataWorldMapFilter.TarotFilter) { return s.filterTarot; }
        if Equals(t, gamedataWorldMapFilter.CommonFilter) { return s.filterYourProperty; }
        return true;
    }

    public static func Visible(view: Int32, s: ref<NightMapSettings>, t: gamedataWorldMapFilter, isOther: Bool) -> Bool {
        return NMVanillaFilters.InView(view, t, isOther) && (isOther || NMVanillaFilters.Enabled(s, t));
    }
}
```

- [ ] **Step 5: Add ApplyFilters and SetEnabled to NMVanilla**

Add the field `public let enabled: Bool = true;` and these methods. Also make `Tick` return `false` immediately when
`!this.enabled`: add `if !this.enabled { return false; }` as its first line.

```swift
    // Shows/hides each filter layer; Vanilla.Pinned (tracked quest marker, waypoint) is always visible while enabled.
    // SetVisible bumps the API revision, so only call it on an actual change.
    public func ApplyFilters(view: Int32, s: ref<NightMapSettings>) {
        this.EnsureLayers();
        let i = 0;
        while i < ArraySize(this.layers) {
            let want = this.enabled && NMVanillaFilters.Visible(view, s, this.catalog.TypeOf(i), this.catalog.IsOther(i));
            if NotEquals(this.layers[i].visible, want) {
                this.layers[i].SetVisible(want);
            }
            i += 1;
        }
        if NotEquals(this.pinned.visible, this.enabled) {
            this.pinned.SetVisible(this.enabled);
        }
        this.filterView = view;
        this.filterSettings = s;
    }

    // Perf suite: off hides every vanilla layer and stops polling; on restores the last filters and re-polls.
    public func SetEnabled(on: Bool) {
        this.enabled = on;
        this.ApplyFilters(this.filterView, this.filterSettings);
        if on { this.Tick(0.0, true); }
    }
```

Add the fields `private let filterView: Int32;` and `private let filterSettings: ref<NightMapSettings>;`.

- [ ] **Step 6: Wire the input and system**

In `Core/Input.reds`:
- Add `public let filter: Bool;`.
- In `ResetHeld()`, add `this.filter = false;`.
- In `Handle`, right after the `keyAct` block, add:

```swift
        if Equals(key, s.keyFilter) {
            if pressed { this.filter = true; }
            return true;
        }
```

  (This sits after the `if !mapOpen { return false; }` guard, like `keyAct`.)
- In `HintText`, add `+ "   ·   " + NMInput.KeyName(s.keyFilter) + " FILTER"` before the `CLOSE` segment.

In `Core/NightMapSystem.reds`:
- Add the field `private let filterView: Int32;`.
- At the end of `OnOpened`, before the vanilla `Tick`, call
  `this.vanilla.ApplyFilters(this.filterView, this.Settings());`.
- In `UpdateModules`, after the act block:

```swift
        if this.input.filter {
            this.input.filter = false;
            this.filterView = (this.filterView + 1) % NMVanillaFilters.ViewCount();
            this.vanilla.ApplyFilters(this.filterView, this.Settings());
            this.UpdateHeader();
        }
```

- In `UpdateHeader`, change the subtitle to show the view when it is not ALL:

```swift
        let district = this.DistrictName();
        this.panel.subtitle.SetText(this.filterView == 0 ? district : district + "   ·   " + NMVanillaFilters.ViewName(this.filterView));
```

- Add a public method for the perf suite: `public func SetVanillaEnabled(on: Bool) { this.vanilla.SetEnabled(on); }`.

- [ ] **Step 7: README**

In `README.md` "Using it", add:

```markdown
- The game's own map markers (quests, gigs, NCPD, vendors, fast travel, …) appear with their vanilla icons. Crosshair a marker for details; `Numpad 0` tracks its quest, or clears your vanilla waypoint. Setting new waypoints comes with the optional native plugin (later).
- `Numpad /` cycles the markers shown: All → Jobs → Services. Mod Settings → NightMap → Map filters turns each vanilla category on or off.
- The header shows the tracked quest and its current objective.
```

- [ ] **Step 8: Run the compile check to verify it passes**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 9: Commit**

```bash
git add r6/scripts/NightMap/Vanilla/Filters.reds r6/scripts/NightMap/Vanilla/Vanilla.reds r6/scripts/NightMap/Core/Settings.reds r6/scripts/NightMap/Core/Input.reds r6/scripts/NightMap/Core/NightMapSystem.reds r6/scripts/NightMap/Debug/SelfTestVanilla.reds README.md
git commit -m "feat(vanilla): quick-view filter key and per-category Mod Settings toggles

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Perf scenario `vanilla_open` and gate

**Files:**
- Modify: `r6/scripts/NightMap/Debug/PerfSuite.reds`: `Add` at line 25, the list at lines 39-48, phase 0 setup, the
  end of the suite, `Report`/`Stats` at line 129.
- Modify: `tools/results.py`
- Modify: `tools/test_results.py`

**Interfaces:**
- Consumes: `NightMapSystem.SetVanillaEnabled(on: Bool)` (Task 8).
- Produces:
  - The `RESULT|vanilla_open|...` row.
  - The new key `script_max=` on every RESULT line.
  - `results.py`: `SWEEP_ROWS` now includes `"vanilla_open"`.

- [ ] **Step 1: Write the failing Python test**

In `tools/test_results.py`, update the `_tiles(...)` helper so the rows it builds include a `vanilla_open` row (same
budget class as `open_empty`). Add `vanilla_avg`/`vanilla_p95` keyword parameters, defaulting to the same in-budget
values as `open_avg`/`open_p95`. Then add:

```python
def test_vanilla_open_is_gated_with_the_sweep_budget():
    ok = results.verdict(results.parse(_tiles(vanilla_avg=21.4, vanilla_p95=31.9)))
    assert ok[0], ok[1]
    bad = results.verdict(results.parse(_tiles(vanilla_avg=21.6)))
    assert not bad[0] and "vanilla_open" in bad[1]


def test_missing_vanilla_row_fails():
    status, msg = results.judge(_suites(_tiles(), _tiles(skip=("vanilla_open",)), _tiles()), 3)
    assert status == "FAIL" and "vanilla_open: row missing" in msg
```

Use the baseline value the existing helpers use: a closed_baseline avg of 20.0 makes +1.4 pass and +1.6 fail. If
`_tiles` uses a different baseline, set `vanilla_avg` to baseline + 1.4 and baseline + 1.6.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd tools && nice -n 19 python3 -m pytest -q test_results.py -k vanilla`
Expected: FAIL, because `vanilla_open` is not gated.

- [ ] **Step 3: Gate the row**

In `tools/results.py`, change:

```python
SWEEP_ROWS = ("open_empty", "vanilla_open", "panzoom_0p5_16")   # open_empty: cold sweep, no markers; vanilla_open: real markers
```

- [ ] **Step 4: Run all Python tests**

Run: `cd tools && nice -n 19 python3 -m pytest -q`
Expected: all pass.

- [ ] **Step 5: Add the scenario to the perf suite**

In `Debug/PerfSuite.reds`:
1. Add a parallel array `private let vanillas: array<Bool>;`, and give `Add` a sixth parameter `vanilla: Bool` that is
   pushed to it. Every existing `Add` call passes `false`. Clear `vanillas` in `Start()` like the other arrays.
2. Insert, right after `open_empty`:

```swift
        this.Add("vanilla_open", 0, true, 0, 0.0, true);
```

3. In phase 0 (setup), after `sys.SetPerfHidden(!this.shows[this.idx]);`, add `sys.SetVanillaEnabled(this.vanillas[this.idx]);`.
4. Where the suite ends (the block that removes the debug layer and restores the camera), add `sys.SetVanillaEnabled(true);`.
5. In `Report`, append `"|script_max=" + FloatToStringPrec(<max of this.script>, 3)` to the RESULT line. Compute the
   max with a loop over `this.script`.

- [ ] **Step 6: Run the compile check**

Run: `nice -n 19 tools/check.sh`
Expected: `COMPILE OK`.

- [ ] **Step 7: Commit**

```bash
git add r6/scripts/NightMap/Debug/PerfSuite.reds tools/results.py tools/test_results.py
git commit -m "feat(perf): vanilla_open scenario with real markers, gated as a sweep row

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Checkpoint 4 (human, in-game)

**Files:**
- Modify: `notes/CHECKPOINTS.md` (a new "Checkpoint 4" section)

The controller runs this with the user. There is no subagent.

- [ ] **Step 1:** With the game closed, run `tools/install.sh`. It refuses if the game is running. Confirm that the
  installed scripts match the repo.
- [ ] **Step 2:** The user launches the game and loads a save. With the map closed: Ctrl + `'` runs the self-test.
  Expect `TEST|SUMMARY|... failed=0`. Fix any failure before continuing.
- [ ] **Step 3: Side-by-side.** Vanilla map and NightMap at the same spot and zoom (downtown and one other district).
  Compare:
  - the icons, colours and visible set;
  - undiscovered gigs and the NCPD colour (Story #5EF6FF in LOOK.md vs the user's memory of red);
  - icon and shadow sizes.

  Tune `VanillaIconSize` / `VanillaShadowSize` / `VanillaShadowOpacity` if needed. Each tune is its own commit, and the
  game must be closed to reinstall.
- [ ] **Step 4: Interactions.**
  - Crosshair a vendor, a fast-travel point and a gig: check the card content.
  - NUM 0 on a gig/quest marker: check that the HUD tracker and minimap switch to it and the header updates.
  - Set a waypoint in the vanilla map, then NUM 0 on it in NightMap: check that it clears.
  - NUM / cycles All, Jobs, Services.
  - A Mod Settings toggle (e.g. Vendor off) hides vendors after reopening the map.
- [ ] **Step 5: Perf.** Shift + `'` three times in one session, standing still in the same spot. Then
  `python3 tools/results.py` must print PASS. `vanilla_open` is gated at +1.5 / +3.0 ms, and `script_max` on
  `vanilla_open` should be under 1 ms.
- [ ] **Step 6:** Write `notes/CHECKPOINTS.md` "Checkpoint 4" with the results table, the screenshots described, and
  any tuning. Commit:

```bash
git add notes/CHECKPOINTS.md
git commit -m "docs(checkpoints): checkpoint 4, vanilla markers in-game

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
