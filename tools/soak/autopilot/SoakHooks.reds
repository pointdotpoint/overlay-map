module NightMap
import SoakBootstrap.*

// The soak harness's commands, overlaid into the scripts only during a campaign (tools/soak/builds.py); never shipped.
// tools/soak/runner.py sends one command at a time and reads the answer as a "done" state. redscript's annotations
// can't target classes defined in scripts, so the bootstrap calls this directly and NightMapSystem's Soak_* methods are
// spliced into the staged class from SystemBody.inc, which gives them its private fields.
public abstract class NMSoak {
    public static func Run(command: String) -> String {
        let sys = NightMapSystem.Get(GetGameInstance());
        if !IsDefined(sys) { return "no system"; }
        if Equals(command, "open") {
            sys.Open();
            return "open";
        }
        if Equals(command, "close") {
            sys.Close();
            return "closed";
        }
        if Equals(command, "focus_ft far") { return sys.Soak_FocusFastTravel(); }
        if Equals(command, "selected") { return sys.Soak_Selected(); }
        if Equals(command, "counts") { return sys.Soak_Counts(); }
        if Equals(command, "is_open") { return sys.Soak_IsOpen(); }
        if Equals(command, "watch_keys") { return sys.Soak_WatchKeys(); }
        if Equals(command, "last_keys") { return sys.Soak_LastKeys(); }
        if Equals(command, "hold_mode") { return sys.Soak_HoldMode(); }
        // Bind StrSplit to a local: indexing a call temporary reads garbage in-game.
        if StrBeginsWith(command, "focus_photo ") {
            let f = StrSplit(command, " ");
            return sys.Soak_FocusPhoto(StringToFloat(f[1]));
        }
        // tp x y hop from to: send V to (x, y, hop), then watch rays from `from` down to `to` frame by frame.
        if StrBeginsWith(command, "tp ") {
            let a = StrSplit(command, " ");
            return sys.Soak_Tp(StringToFloat(a[1]), StringToFloat(a[2]), StringToFloat(a[3]), StringToFloat(a[4]), StringToFloat(a[5]));
        }
        if Equals(command, "tp_result") { return sys.Soak_TpResult(); }
        if Equals(command, "vpos") { return sys.Soak_VPos(); }
        if StrBeginsWith(command, "aim ") {
            let v = StrSplit(command, " ");
            return sys.Soak_Aim(StringToFloat(v[1]), StringToFloat(v[2]));
        }
        if StrBeginsWith(command, "zoom ") {
            let m = StrSplit(command, " ");
            return sys.Soak_SetZoom(StringToFloat(m[1]));
        }
        if Equals(command, "selftest") {
            let t = new NMSelfTest();
            t.Run();
            return "ran";
        }
        if StrBeginsWith(command, "sweep ") {
            let a = StrSplit(command, " ");
            return sys.Soak_StartSweep(a[1], StringToFloat(a[2]), StringToFloat(a[3]), ArraySize(a) > 4 ? StringToInt(a[4]) : 0);
        }
        if StrBeginsWith(command, "seed_photos ") {
            let n = StrSplit(command, " ");
            return sys.Soak_SeedPhotos(StringToInt(n[1]));
        }
        if StrBeginsWith(command, "churn ") {
            let c = StrSplit(command, " ");
            return sys.Soak_StartChurn(c[1], StringToFloat(c[2]), StringToFloat(c[3]));
        }
        if StrBeginsWith(command, "zoomloop ") {
            let z = StrSplit(command, " ");
            return sys.Soak_StartZoomLoop(z[1], StringToFloat(z[2]), ArraySize(z) > 3 ? StringToInt(z[3]) : 0);
        }
        return "unknown";
    }

    // A state line for the supervisor; survives a killed game, unlike the game log.
    public static func Report(state: String, detail: String) {
        let channel = SoakChannel.Get();
        if IsDefined(channel) { channel.State(state, detail); }
    }
}

// One frame of the tp probe, re-armed from Soak_TpTick.
public class NMSoakTpFrame extends DelayCallback {
    public let system: wref<NightMapSystem>;
    public func Call() {
        if IsDefined(this.system) { this.system.Soak_TpTick(); }
    }
}
