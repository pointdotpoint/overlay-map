module NightMap

// The waypoint key (Enter / pad RB) on the expanded map: set the vanilla custom waypoint, track a job's quest, track
// any other marker, or clear what is tracked. Spec: docs/superpowers/specs/2026-11-02-nightmap-waypoints-design.md.
// The custom waypoint is registered from script exactly as the world map does (record + variant); tracking a mappin
// needs the optional NightMapNative plugin, which calls the mappin system's own track function (FINDINGS).
public enum NMWaypointAction {
    None = 0,
    TrackQuest = 1,
    SetCustom = 2,
    TrackMappin = 3,
    Clear = 4,
}

// The plugin's track call, or false when the plugin isn't installed (compiled both ways).
@if(ModuleExists("NightMapNative"))
public abstract class NMWaypointNative {
    public static func Available() -> Bool { return NightMapNative_Available(); }
    public static func Track(ms: ref<MappinSystem>, id: NewMappinID) -> Bool { return NightMapNative_TrackMappin(ms, id); }
    public static func Why() -> String { return NightMapNative_Why(); }
}

@if(!ModuleExists("NightMapNative"))
public abstract class NMWaypointNative {
    public static func Available() -> Bool { return false; }
    public static func Track(ms: ref<MappinSystem>, id: NewMappinID) -> Bool { return false; }
    public static func Why() -> String { return "plugin not installed"; }
}

// Retries a pending track each frame: a mappin registered this frame isn't resolvable until the system has added it.
public class NMWaypointRetry extends DelayCallback {
    public let owner: wref<NMWaypoint>;
    public func Call() {
        if IsDefined(this.owner) { this.owner.OnRetry(); }
    }
}

public class NMWaypoint {
    private let gi: GameInstance;
    private let pending: NewMappinID;
    private let pendingFrames: Int32;
    private let scheduled: Bool;   // one delay callback in flight at most
    private let loggedUnavailable: Bool;
    public let lastAction: String;

    public static func MaxPendingFrames() -> Int32 { return 120; }

    public static func Create(gi: GameInstance) -> ref<NMWaypoint> {
        let w = new NMWaypoint();
        w.gi = gi;
        w.lastAction = "none";
        return w;
    }

    // What the key does for the current selection. isMappin: the selection is a vanilla mappin; isTrackedNow: it is the
    // manually tracked pin (the custom waypoint or a tracked marker). Without the plugin only quest tracking remains.
    public static func Decide(hasSel: Bool, isMappin: Bool, questTrackable: Bool, questTracked: Bool, isTrackedNow: Bool,
        plugin: Bool) -> NMWaypointAction {
        if hasSel && isMappin && questTrackable {
            return questTracked ? NMWaypointAction.None : NMWaypointAction.TrackQuest;
        }
        if !plugin { return NMWaypointAction.None; }
        if !hasSel || !isMappin { return NMWaypointAction.SetCustom; }   // an empty spot, a photo / collectible pin
        return isTrackedNow ? NMWaypointAction.Clear : NMWaypointAction.TrackMappin;
    }

    public static func Label(a: NMWaypointAction) -> String {
        switch a {
            case NMWaypointAction.TrackQuest: return "TRACK QUEST";
            case NMWaypointAction.SetCustom: return "SET WAYPOINT";
            case NMWaypointAction.TrackMappin: return "TRACK";
            case NMWaypointAction.Clear: return "CLEAR WAYPOINT";
            default: return "";
        }
    }

    public static func Available() -> Bool { return NMWaypointNative.Available(); }

    // The waypoint's height on an empty spot: the cell's baked street level (open sea and off the grid read 0).
    public static func GroundZ(x: Float, y: Float) -> Float { return NMHeight.Low(x, y); }

    // The waypoint hint, right after ACT; nothing when there is nothing to do.
    public static func WithHint(hints: array<NMHint>, key: String, label: String) -> array<NMHint> {
        if StrLen(label) == 0 { return hints; }
        let out: array<NMHint>;
        let placed = false;
        for h in hints {
            ArrayPush(out, h);
            if !placed && Equals(h.label, "ACT") {
                ArrayPush(out, NMHints.Of(key, label));
                placed = true;
            }
        }
        if !placed { ArrayPush(out, NMHints.Of(key, label)); }
        return out;
    }

    // Unregisters every vanilla custom waypoint (there is only ever one: vanilla replaces it). Returns how many.
    public static func UnregisterCustom(gi: GameInstance) -> Int32 {
        let ms = GameInstance.GetMappinSystem(gi);
        let all: array<ref<IMappin>>;
        ms.GetMappins(gamemappinsMappinTargetType.Map, all);
        let n = 0;
        for m in all {
            if Equals(m.GetVariant(), gamedataMappinVariant.CustomPositionVariant) {
                let id = m.GetNewMappinID();
                ms.UnregisterMappin(id);
                n += 1;
            }
        }
        return n;
    }

    // Vanilla TrackCustomPositionMappin: move the tracked custom waypoint, else register one and track it once the
    // mappin system has it.
    public func SetCustom(x: Float, y: Float, z: Float) -> Bool {
        if !this.Ready() { return false; }
        let ms = GameInstance.GetMappinSystem(this.gi);
        let pos = new Vector4(x, y, z, 1.0);
        let cur = ms.GetManuallyTrackedMappinID();
        if cur.value != 0ul {
            let m = ms.GetMappin(cur);
            if IsDefined(m) && Equals(m.GetVariant(), gamedataMappinVariant.CustomPositionVariant) {
                ms.SetMappinPosition(cur, pos);
                this.lastAction = "moved";
                return true;
            }
        }
        NMWaypoint.UnregisterCustom(this.gi);
        let data: MappinData;
        data.mappinType = t"Mappins.CustomPositionMappinDefinition";
        data.variant = gamedataMappinVariant.CustomPositionVariant;
        data.active = true;
        data.visibleThroughWalls = true;
        this.pending = ms.RegisterMappin(data, pos);
        this.pendingFrames = 0;
        this.lastAction = "registered";
        this.Schedule();
        return this.pending.value != 0ul;
    }

    // Vanilla TrackMappin: the custom waypoint goes (vanilla UntrackCustomPositionMappin), then the marker is tracked.
    public func Track(m: ref<IMappin>) -> Bool {
        if !this.Ready() || !IsDefined(m) { return false; }
        let id = m.GetNewMappinID();   // bound to a local: a field read off the call's temporary is 0 in-game
        if id.value == 0ul { return false; }
        NMWaypoint.UnregisterCustom(this.gi);
        let ok = NMWaypointNative.Track(GameInstance.GetMappinSystem(this.gi), id);
        this.lastAction = ok ? "tracked" : "refused";
        return ok;
    }

    public func Clear() -> Bool {
        let ok = NMVanillaTracking.ClearManual(this.gi);
        this.lastAction = ok ? "cleared" : "nothing";
        return ok;
    }

    public func TryPending() {
        if this.pending.value == 0ul { return; }
        let ms = GameInstance.GetMappinSystem(this.gi);
        let id = this.pending;
        let m = ms.GetMappin(id);
        if IsDefined(m) {
            let none: NewMappinID;
            this.pending = none;
            let ok = NMWaypointNative.Track(ms, id);
            this.lastAction = ok ? "set" : "refused";
            if !ok {
                ms.UnregisterMappin(id);   // never leave an untracked pin behind
                NMLog.Info("waypoint|track refused|" + NMWaypointNative.Why());
            }
            return;
        }
        this.pendingFrames += 1;
        if this.pendingFrames > NMWaypoint.MaxPendingFrames() {
            let none: NewMappinID;
            this.pending = none;
            ms.UnregisterMappin(id);
            this.lastAction = "timeout";
            NMLog.Info("waypoint|never registered");
            return;
        }
        this.Schedule();
    }

    public func Pending() -> Bool { return this.pending.value != 0ul; }

    public func OnRetry() {
        this.scheduled = false;
        this.TryPending();
    }

    // The delay system covers the closed map; the open map (the game may be paused) also calls TryPending each frame.
    private func Schedule() {
        if this.scheduled { return; }
        this.scheduled = true;
        let cb = new NMWaypointRetry();
        cb.owner = this;
        GameInstance.GetDelaySystem(this.gi).DelayCallbackNextFrame(cb);
    }

    // The plugin answers for this game build; logs once when it doesn't.
    private func Ready() -> Bool {
        if NMWaypointNative.Available() { return true; }
        if !this.loggedUnavailable {
            this.loggedUnavailable = true;
            NMLog.Info("waypoint|unavailable|" + NMWaypointNative.Why());
        }
        this.lastAction = "unavailable";
        return false;
    }
}
