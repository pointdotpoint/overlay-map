module OverlayMap

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

    // Unregisters the manually tracked pin only if it is a vanilla custom waypoint (CustomPositionVariant).
    public static func ClearCustomWaypoint(gi: GameInstance) -> Bool {
        let ms = GameInstance.GetMappinSystem(gi);
        let id = ms.GetManuallyTrackedMappinID();
        if id.value == 0ul { return false; }
        let m = ms.GetMappin(id);
        if IsDefined(m) && Equals(m.GetVariant(), gamedataMappinVariant.CustomPositionVariant) {
            ms.UnregisterMappin(id);
            return true;
        }
        return false;
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
