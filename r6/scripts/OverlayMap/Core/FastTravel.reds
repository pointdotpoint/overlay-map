module OverlayMap

// Fast travel to a selected vanilla fast travel marker through the game's own FastTravelSystem: the same request the
// world map and dataterms send, so the game picks the arrival spot and applies its own locks. Replaces the free
// teleport (lift + ground search), which could not find the ground reliably and let V die from the fall.
public abstract class NMFastTravel {
    // Why a press does nothing; "" = travel. Pure, for the self-tests.
    public static func Refusal(isPoint: Bool, discovered: Bool, inVehicle: Bool, unlocked: Bool) -> String {
        if !isPoint { return "not a fast travel point"; }
        if !discovered { return "undiscovered"; }
        if inVehicle { return "in vehicle"; }
        if !unlocked { return "locked"; }
        return "";
    }

    public static func System(gi: GameInstance) -> ref<FastTravelSystem> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"FastTravelSystem") as FastTravelSystem;
    }

    // The point data of a fast travel mappin, else null.
    public static func PointOf(m: ref<IMappin>) -> ref<FastTravelPointData> {
        let ft = m as FastTravelMappin;
        return IsDefined(ft) ? ft.GetPointData() : null;
    }

    // Refusal for this mappin right now ("" = can travel).
    public static func Check(gi: GameInstance, m: ref<IMappin>, player: ref<GameObject>) -> String {
        let pd = NMFastTravel.PointOf(m);
        let fts = NMFastTravel.System(gi);
        let discovered = IsDefined(pd) && IsDefined(fts) && fts.HasFastTravelPoint(pd);
        let unlocked = IsDefined(fts) && fts.IsFastTravelEnabled();
        return NMFastTravel.Refusal(IsDefined(pd), discovered, IsDefined(GetMountedVehicle(player)), unlocked);
    }

    // Sends the travel request. The game skips a trip whose destination equals the blackboard's StartingPoint (the
    // last dataterm used, which can be stale), so that is cleared first: V is not standing at a dataterm here.
    public static func Travel(gi: GameInstance, m: ref<IMappin>, player: ref<GameObject>) {
        let bb = GameInstance.GetBlackboardSystem(gi).Get(GetAllBlackboardDefs().FastTRavelSystem);
        bb.SetVariant(GetAllBlackboardDefs().FastTRavelSystem.StartingPoint, ToVariant(TDBID.None()));
        let request = new PerformFastTravelRequest();
        request.pointData = NMFastTravel.PointOf(m);
        request.player = player;
        NMFastTravel.System(gi).QueueRequest(request);
        // Without this the game teleports V but never starts its loading sequence, and the screen stays black for good.
        let loading = new inkSetNextLoadingScreenEvent();
        loading.SetNextLoadingScreenType(inkLoadingScreenType.FastTravel);
        GameInstance.GetUISystem(gi).QueueEvent(loading);
    }
}
