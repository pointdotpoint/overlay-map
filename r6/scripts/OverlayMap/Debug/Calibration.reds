module OverlayMap

// Logs every fast-travel point's world position for tools/tiles (python3 -m nmtiles.calib).
public abstract class NMCalibration {
    public static func Dump(game: GameInstance) -> Int32 {
        let n = 0;
        for m in GameInstance.GetMappinSystem(game).GetAllMappins() {
            let ft = m as FastTravelMappin;
            if IsDefined(ft) {
                let pos = ft.GetWorldPosition();
                let data = ft.GetPointData();
                let name = IsDefined(data) ? data.GetPointDisplayName() : "ft";
                NMLog.Info("CALIB|" + name + "#" + ToString(n) + "|" + FloatToStringPrec(pos.X, 2) + "|" + FloatToStringPrec(pos.Y, 2) + "|" + FloatToStringPrec(pos.Z, 2));
                n += 1;
            }
        }
        NMLog.Info("CALIB|DONE|" + ToString(n));
        return n;
    }
}
