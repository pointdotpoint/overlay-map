module NightMap

// Self-test groups for sub-project 2 (vanilla markers). Called from NMSelfTest.Run().
public abstract class NMVanillaTests {
    public static func Run(t: ref<NMSelfTest>) {
        NMVanillaTests.PinApiCases(t);
        NMVanillaTests.IconStyleCases(t);
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
}
