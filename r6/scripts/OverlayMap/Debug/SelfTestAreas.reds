module OverlayMap

// NMSelfTest.Run(): the area index (names under the map focus). The fixture is custom-style, so no TweakDB lookup.
public abstract class NMAreaTests {
    public static func Run(t: ref<NMSelfTest>) {
        let chunks: array<String>;
        // Smallest first, as gen.py emits them. The Tot pair stacks two same-name outlines.
        ArrayPush(chunks, "Tot|Tot|||301,301,309,301,309,309,301,309;Tot|Tot|||300,300,310,300,310,310,300,310");
        ArrayPush(chunks, "Small|Small|||0,0,10,0,10,10,0,10;Blank||||200,200,210,200,210,210,200,210");
        ArrayPush(chunks, "Notch|Notch|||0,0,100,0,100,100,60,100,60,40,40,40,40,100,0,100;Big|Big|||-500,-500,500,-500,500,500,-500,500");
        let idx = NMAreaIndex.Parse(chunks);
        t.Check("areas.parse_count", idx.Count() == 6, ToString(idx.Count()));
        t.Check("areas.smallest_wins", idx.At(5.0, 5.0) == 2, ToString(idx.At(5.0, 5.0)));
        t.Check("areas.concave_notch", idx.At(50.0, 80.0) == 5 && idx.At(20.0, 80.0) == 4,
            ToString(idx.At(50.0, 80.0)) + "," + ToString(idx.At(20.0, 80.0)));
        t.Check("areas.empty_name_falls_through", idx.At(205.0, 205.0) == 5, ToString(idx.At(205.0, 205.0)));
        let inner = idx.At(305.0, 305.0);
        let outer = idx.At(300.5, 300.5);
        t.Check("areas.same_name_stack", inner == 0 && outer == 1 && Equals(idx.Title(inner), "Tot")
            && Equals(idx.Title(outer), "Tot"), ToString(inner) + "," + ToString(outer));
        t.Check("areas.outside_is_none", idx.At(900.0, 900.0) == -1, ToString(idx.At(900.0, 900.0)));

        // The shipped data: game areas resolve through TweakDB, so names follow the game language.
        let real = NMAreaIndex.Load();
        let afterlife = real.At(-1431.6, 997.0);
        let japantown = real.At(-373.8, 1038.6);
        t.Check("areas.real_data", real.Count() == NMAreaData.Count() && real.Count() > 50
            && real.At(-6000.0, 4000.0) == -1 && afterlife >= 0 && japantown >= 0
            && StrLen(real.Title(afterlife)) > 0 && StrLen(real.Title(japantown)) > 0
            && NotEquals(real.Title(afterlife), real.Title(japantown)),
            ToString(real.Count()) + "|" + real.Title(afterlife) + "|" + real.Title(japantown));
        // The probe is the Landfill hull's centroid (tools/areas/custom_areas.json).
        let landfill = real.At(1377.9, -1903.3);
        t.Check("areas.landfill", Equals(real.Title(landfill), "Landfill") && StrContains(real.Label(landfill), " · "),
            real.Title(landfill) + "|" + real.Label(landfill));
    }
}
