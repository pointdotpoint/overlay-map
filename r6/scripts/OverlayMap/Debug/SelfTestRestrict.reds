module OverlayMap

// Map open on foot with the keyboard taken: V is held by gameplay restrictions, not the player state machine's UI
// context, so the mouse still turns the camera (NoCameraControl is never applied).
public abstract class NMRestrictTests {
    public static func Run(t: ref<NMSelfTest>) {
        let ids = NMRestrict.Ids();
        let hasMove = false;
        let hasCam = false;
        let allDefined = true;
        let missing = "";
        for id in ids {
            if id == t"GameplayRestriction.NoMovement" { hasMove = true; }
            if id == t"GameplayRestriction.NoCameraControl" { hasCam = true; }
            if !IsDefined(TweakDBInterface.GetStatusEffectRecord(id)) {
                allDefined = false;
                missing += TDBID.ToStringDEBUG(id) + " ";
            }
        }
        t.Check("restrict.blocks_movement_not_camera", hasMove && !hasCam, ToString(ArraySize(ids)));
        t.Check("restrict.records_exist", allDefined, missing);
        let player = GetPlayer(GetGameInstance());
        if !IsDefined(player) {
            t.Check("restrict.player", false, "no player");
            return;
        }
        // The game applies status effects a moment later, so apply-then-count in one frame reads 0 (in game); the
        // mouse-look soak plan checks the live count. Here: none of ours may be left on V while the map is closed.
        t.Check("restrict.none_left_while_closed", NMRestrict.Count(player) == 0, ToString(NMRestrict.Count(player)));
    }
}
