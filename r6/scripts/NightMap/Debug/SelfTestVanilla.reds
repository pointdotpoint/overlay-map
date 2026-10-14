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
