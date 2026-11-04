module OverlayMap

// All OverlayMap output goes to CET's gamelog.log as "[OverlayMap] ..." lines.
public abstract class NMLog {
    public static func Info(msg: String) {
        ModLog(n"OverlayMap", msg);
    }

    public static func Error(msg: String) {
        ModLog(n"OverlayMap", "ERROR|" + msg);
    }
}
