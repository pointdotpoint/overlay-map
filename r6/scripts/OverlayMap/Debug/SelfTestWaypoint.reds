module OverlayMap

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

        // The hint sits right after FOLLOW and only when there is something to do.
        let s = NMSelfTest.HintSettings(false);
        let base = NMInput.Hints(s, "ALL", "TELEPORT");
        let with = NMWaypoint.WithHint(base, "ENTER", "SET WAYPOINT");
        let ok = ArraySize(with) == ArraySize(base) + 1;
        if ok {
            let h2 = with[2];
            let h3 = with[3];
            ok = Equals(h2.label, "FOLLOW") && Equals(h3.label, "SET WAYPOINT") && Equals(h3.key, "ENTER");
        }
        let noAct = true;
        for h in with { if Equals(h.label, "ACT") { noAct = false; } }
        t.Check("wp.hint_after_follow", ok && noAct, NMHints.Join(with));
        t.Check("wp.hint_hidden_when_none", ArraySize(NMWaypoint.WithHint(base, "ENTER", "")) == ArraySize(base), "");
        t.Check("wp.key_name_enter", Equals(NMInput.KeyName(EInputKey.IK_Enter), "ENTER"), NMInput.KeyName(EInputKey.IK_Enter));

        // Enter is common: it only belongs to OverlayMap while the map is open.
        let ws = NMSelfTest.HintSettings(false);
        let closed = new NMInput();
        let usedClosed = closed.Handle(ws, ws.keyWaypoint, EInputAction.IACT_Press, false, false, false, false);
        let open = new NMInput();
        let usedOpen = open.Handle(ws, ws.keyWaypoint, EInputAction.IACT_Press, false, false, false, true);
        t.Check("input.waypoint_only_open", !usedClosed && !closed.waypoint && usedOpen && open.waypoint, "");
        t.Check("input.waypoint_default_enter", Equals(new OverlayMapSettings().keyWaypoint, EInputKey.IK_Enter), "");

        // The pending track gives up by time, not frames (TryPending runs from the map update and the delay callback).
        let lim = NMWaypoint.PendingTimeoutMs();
        t.Check("wp.pending_timeout_time", !NMWaypoint.TimedOut(1000.0, 1000.0 + lim - 1.0)
            && NMWaypoint.TimedOut(1000.0, 1000.0 + lim + 1.0) && lim >= 2000.0, FloatToStringPrec(lim, 0));

        // Any other action cancels a pending custom waypoint, so it can't be tracked over the player's next choice.
        // A save that already tracks a custom waypoint takes the other path: SetCustom moves it (nothing pending). The
        // test used to assume no waypoint, failed on such a save, and left the player's waypoint 40 m off.
        if NMWaypoint.Available() {
            let gi = GetGameInstance();
            let ms = GameInstance.GetMappinSystem(gi);
            let cur = ms.GetManuallyTrackedMappinID();
            let m = cur.value != 0ul ? ms.GetMappin(cur) : null;
            let w = NMWaypoint.Create(gi);
            if IsDefined(m) && Equals(m.GetVariant(), gamedataMappinVariant.CustomPositionVariant) {
                let old = m.GetWorldPosition();
                let ok = w.SetCustom(old.X + 40.0, old.Y, old.Z);
                let action = w.lastAction;
                let pending = w.Pending();
                w.SetCustom(old.X, old.Y, old.Z);   // put the player's waypoint back
                // Moving gives the mappin a new id: check the tracked pin is still a custom waypoint, back in its place.
                let now = ms.GetMappin(ms.GetManuallyTrackedMappinID());
                let back = IsDefined(now) && Equals(now.GetVariant(), gamedataMappinVariant.CustomPositionVariant);
                let off = back ? Vector4.Distance(now.GetWorldPosition(), old) : -1.0;
                t.Check("wp.moves_tracked_custom", ok && Equals(action, "moved") && !pending && Equals(w.lastAction, "moved")
                    && back && off >= 0.0 && off < 1.0, action + "/" + ToString(pending) + "/" + w.lastAction + " off " + FloatToStringPrec(off, 2));
                NMLog.Info("TEST|INFO|wp.cancel_pending|skipped: the save tracks a custom waypoint");
            } else {
                let p = GetPlayer(gi).GetWorldPosition();
                w.SetCustom(p.X + 40.0, p.Y, p.Z);
                let wasPending = w.Pending();
                let action = w.lastAction;
                w.Clear();
                let afterClear = w.Pending();
                w.SetCustom(p.X + 40.0, p.Y, p.Z);
                w.CancelPending();
                t.Check("wp.cancel_pending", wasPending && !afterClear && !w.Pending(),
                    ToString(wasPending) + "/" + ToString(afterClear) + "/" + ToString(w.Pending()) + " " + action
                    + " tracked " + ToString(cur.value != 0ul));
            }
        }
    }
}
