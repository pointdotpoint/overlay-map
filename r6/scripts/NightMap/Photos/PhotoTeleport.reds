module NightMap

// Teleport to a photo spot (spec §6.6, §10): one exact teleport, on foot only. The spike showed V lands and stays.
public abstract class NMPhotoTeleport {
    // Checked in this order: player state first, then the selection, then the vehicle.
    public static func Refusal(isPhoto: Bool, inVehicle: Bool, playerReady: Bool) -> String {
        if !playerReady { return "not ready"; }
        if !isPhoto { return "not a photo"; }
        if inVehicle { return "in vehicle"; }
        return "";
    }

    public static func Go(gi: GameInstance, player: ref<GameObject>, spot: ref<NMPhotoSpot>) {
        let rot = new EulerAngles();
        rot.Yaw = spot.yaw;
        GameInstance.GetTeleportationFacility(gi).Teleport(player, spot.Position(), rot);
    }
}
