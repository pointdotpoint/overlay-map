module NightMap

// Corner minimap cost while the map is closed (the perf suite measures the open panel). With Debug on, the system feeds
// every corner frame here and logs a RESULT|corner line per window: frame time, the corner's own script time
// (budget: script_avg <= 0.5 ms, spec "Performance pass bar") and how many vanilla markers the mirror holds.
public class NMCornerPerf {
    private let frames: array<Float>;
    private let script: array<Float>;

    public static func Window() -> Int32 { return 600; }

    // Returns the RESULT line when this sample closes a window, else "".
    public func Add(frameMs: Float, scriptMs: Float, mirrorCount: Int32) -> String {
        ArrayPush(this.frames, frameMs);
        ArrayPush(this.script, scriptMs);
        if ArraySize(this.frames) < NMCornerPerf.Window() { return ""; }
        let line = "RESULT|corner|frames=" + IntToString(ArraySize(this.frames)) + "|" + NMPerfSuite.Stats("frame", this.frames, true)
            + "|" + NMPerfSuite.Stats("script", this.script, true) + "|mirror=" + IntToString(mirrorCount);
        ArrayClear(this.frames);
        ArrayClear(this.script);
        return line;
    }

    public func Count() -> Int32 { return ArraySize(this.frames); }
}
