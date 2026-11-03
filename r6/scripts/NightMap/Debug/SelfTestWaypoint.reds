module NightMap

// NMSelfTest.Run(): the waypoint key's pure parts. Nothing is registered or tracked here.
public abstract class NMWaypointTests {
    public static func Run(t: ref<NMSelfTest>) {
        // Decide(hasSel, isMappin, questTrackable, questTracked, isTrackedNow, plugin)
        let none = NMWaypointAction.None;
        let quest = NMWaypointAction.TrackQuest;
        let custom = NMWaypointAction.SetCustom;
        let track = NMWaypointAction.TrackMappin;
        let clear = NMWaypointAction.Clear;
        t.Check("wp.decide_empty_spot", Equals(NMWaypoint.Decide(false, false, false, false, false, true), custom), "");
        t.Check("wp.decide_quest", Equals(NMWaypoint.Decide(true, true, true, false, false, true), quest), "");
        t.Check("wp.decide_quest_tracked", Equals(NMWaypoint.Decide(true, true, true, true, false, true), none), "");
        t.Check("wp.decide_vendor", Equals(NMWaypoint.Decide(true, true, false, false, false, true), track), "");
        t.Check("wp.decide_vendor_tracked", Equals(NMWaypoint.Decide(true, true, false, false, true, true), clear), "");
        t.Check("wp.decide_custom_itself", Equals(NMWaypoint.Decide(true, true, false, false, true, true), clear), "");
        t.Check("wp.decide_photo_pin", Equals(NMWaypoint.Decide(true, false, false, false, false, true), custom), "");
        // Without the plugin only the quest action remains (it needs no engine call).
        t.Check("wp.decide_no_plugin",
            Equals(NMWaypoint.Decide(true, true, true, false, false, false), quest)
            && Equals(NMWaypoint.Decide(false, false, false, false, false, false), none)
            && Equals(NMWaypoint.Decide(true, true, false, false, false, false), none)
            && Equals(NMWaypoint.Decide(true, true, false, false, true, false), none)
            && Equals(NMWaypoint.Decide(true, false, false, false, false, false), none), "");

        t.Check("wp.labels",
            Equals(NMWaypoint.Label(quest), "TRACK QUEST") && Equals(NMWaypoint.Label(custom), "SET WAYPOINT")
            && Equals(NMWaypoint.Label(track), "TRACK") && Equals(NMWaypoint.Label(clear), "CLEAR WAYPOINT")
            && Equals(NMWaypoint.Label(none), ""), "");

        // Height: the baked street level, never NaN; open sea / off the grid reads 0.
        let z = NMWaypoint.GroundZ(-1858.7, -1936.7);
        t.Check("wp.ground_z_finite", z == z && z > -500.0 && z < 1000.0, FloatToStringPrec(z, 1));
        t.Check("wp.ground_z_fallback", NMWaypoint.GroundZ(100000.0, 100000.0) == 0.0, "");

        // The hint sits right after ACT and only when there is something to do.
        let s = NMSelfTest.HintSettings(false);
        let base = NMInput.Hints(s, "ALL", "TELEPORT");
        let with = NMWaypoint.WithHint(base, "ENTER", "SET WAYPOINT");
        let ok = ArraySize(with) == ArraySize(base) + 1;
        if ok {
            let h3 = with[3];
            let h4 = with[4];
            ok = Equals(h3.label, "ACT") && Equals(h4.label, "SET WAYPOINT") && Equals(h4.key, "ENTER");
        }
        t.Check("wp.hint_after_act", ok, NMHints.Join(with));
        t.Check("wp.hint_hidden_when_none", ArraySize(NMWaypoint.WithHint(base, "ENTER", "")) == ArraySize(base), "");
        t.Check("wp.key_name_enter", Equals(NMInput.KeyName(EInputKey.IK_Enter), "ENTER"), NMInput.KeyName(EInputKey.IK_Enter));

        // Enter is common: it only belongs to NightMap while the map is open.
        let ws = NMSelfTest.HintSettings(false);
        let closed = new NMInput();
        let usedClosed = closed.Handle(ws, ws.keyWaypoint, EInputAction.IACT_Press, false, false, false, false);
        let open = new NMInput();
        let usedOpen = open.Handle(ws, ws.keyWaypoint, EInputAction.IACT_Press, false, false, false, true);
        t.Check("input.waypoint_only_open", !usedClosed && !closed.waypoint && usedOpen && open.waypoint, "");
        t.Check("input.waypoint_default_enter", Equals(new NightMapSettings().keyWaypoint, EInputKey.IK_Enter), "");
    }
}
