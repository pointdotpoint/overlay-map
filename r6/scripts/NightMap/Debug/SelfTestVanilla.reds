module NightMap

// Self-test groups for sub-project 2 (vanilla markers). Called from NMSelfTest.Run().
public abstract class NMVanillaTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMVanillaTests.PinApiCases(t);
        NMVanillaTests.IconStyleCases(t);
        NMVanillaTests.StyleCases(t);
        NMVanillaTests.DiffCases(t);
        NMVanillaTests.LiveCases(t);
        NMVanillaTests.CardCases(t);
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
}

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
