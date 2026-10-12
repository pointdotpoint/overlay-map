module NightMap
@if(ModuleExists("RedFileSystem"))
import RedFileSystem.*

// Diagnostic trace written straight to r6/storages/NightMap/trace.txt (the folder must exist), so it survives a
// hard crash that wipes CET's 4 KB gamelog buffer. Each line is written BEFORE the native call it describes.
// Only active when the Debug setting is on; needs RedFileSystem; at most 4000 lines per session.
public class NMTrace {
    // State lives in NightMapSettings.traceLeft: scc cannot read or assign static fields.
    public static func Reset(msg: String, enabled: Bool) {
        let s = NightMapSettings.Get(GetGameInstance());
        if !IsDefined(s) {
            return;
        }
        s.traceLeft = enabled ? 4000 : 0;
        if enabled {
            NMTrace.Write(msg, true);
        }
    }

    public static func Line(msg: String) {
        let s = NightMapSettings.Get(GetGameInstance());
        if !IsDefined(s) || s.traceLeft <= 0 {
            return;
        }
        s.traceLeft -= 1;
        NMTrace.Write(msg, false);
    }

    @if(ModuleExists("RedFileSystem"))
    private static func Write(msg: String, truncate: Bool) {
        let storage = FileSystem.GetStorage("NightMap");
        if !IsDefined(storage) {
            return;
        }
        let file = storage.GetFile("trace.txt");
        if IsDefined(file) {
            file.WriteText(msg + "\n", truncate ? FileSystemWriteMode.Truncate : FileSystemWriteMode.Append);
        }
    }

    @if(!ModuleExists("RedFileSystem"))
    private static func Write(msg: String, truncate: Bool) {}
}
