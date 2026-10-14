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
            let counted = obj as JournalQuestObjective;
            let cur = IsDefined(counted) ? jm.GetObjectiveCurrentCounter(counted) : 0;
            let total = IsDefined(counted) ? jm.GetObjectiveTotalCounter(counted) : 0;
            h.objective = NMQuestHeader.FormatObjective(NMVanillaText.Loc(obj.GetDescription()), cur, total);
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
