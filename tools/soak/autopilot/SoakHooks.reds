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
        if StrBeginsWith(command, "focus_photo ") { return sys.Soak_FocusPhoto(StringToFloat(StrSplit(command, " ")[1])); }
        if StrBeginsWith(command, "zoom ") { return sys.Soak_SetZoom(StringToFloat(StrSplit(command, " ")[1])); }
        if Equals(command, "selftest") {
            let t = new NMSelfTest();
            t.Run();
            return "ran";
        }
        if StrBeginsWith(command, "sweep ") {
            let a = StrSplit(command, " ");
            return sys.Soak_StartSweep(a[1], StringToFloat(a[2]), StringToFloat(a[3]), ArraySize(a) > 4 ? StringToInt(a[4]) : 0);
        }
        if StrBeginsWith(command, "seed_photos ") { return sys.Soak_SeedPhotos(StringToInt(StrSplit(command, " ")[1])); }
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
