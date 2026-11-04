module OverlayMap

// NMSelfTest.Run(). Nothing travels: only the pure refusal choice and the hint text.
public abstract class NMFastTravelTests {
    public static func Run(t: ref<NMSelfTest>) {
        // Refusal(isPoint, discovered, inVehicle, unlocked)
        t.Check("ft.ok", Equals(NMFastTravel.Refusal(true, true, false, true), ""), "");
        t.Check("ft.not_point", Equals(NMFastTravel.Refusal(false, true, false, true), "not a fast travel point"), "");
        t.Check("ft.undiscovered", Equals(NMFastTravel.Refusal(true, false, false, true), "undiscovered"), "");
        t.Check("ft.vehicle", Equals(NMFastTravel.Refusal(true, true, true, true), "in vehicle"), "");
        t.Check("ft.locked", Equals(NMFastTravel.Refusal(true, true, false, false), "locked"), "");
        // Not a point wins over everything else: nothing else is known about a non-point.
        t.Check("ft.not_point_first", Equals(NMFastTravel.Refusal(false, false, true, false), "not a fast travel point"), "");

        let s = new OverlayMapSettings();
        s.teleportEnabled = true;
        t.Check("ft.hint_on", StrContains(NMInput.HintText(s, "ALL", "FAST TRAVEL"), "FAST TRAVEL"), "");
        s.teleportEnabled = false;
        t.Check("ft.hint_off", !StrContains(NMInput.HintText(s, "ALL", "FAST TRAVEL"), "FAST TRAVEL"), "");
    }
}
