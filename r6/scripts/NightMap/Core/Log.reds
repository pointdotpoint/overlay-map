module NightMap

// All NightMap output goes to CET's gamelog.log as "[NightMap] ..." lines.
public abstract class NMLog {
    public static func Info(msg: String) {
        ModLog(n"NightMap", msg);
    }

    public static func Error(msg: String) {
        ModLog(n"NightMap", "ERROR|" + msg);
    }
}
