module NightMap

// Corner minimap cost while the map is closed (the perf suite measures the open panel). With Debug on, the system feeds
// every corner frame here and logs a RESULT|corner line per window: frame time, the corner's own script time
// (budget: script_avg <= 0.5 ms, spec "Performance pass bar") and how many vanilla markers the mirror holds.
public class NMCornerPerf {
    private let frames: array<Float>;
    private let script: array<Float>;
    private let split: array<Float>;   // summed tiles, routes, items, vanilla poll, mirror over the window

    public static func Window() -> Int32 { return 600; }

    public func AddSplit(tiles: Float, routes: Float, items: Float, vanilla: Float, mirror: Float) {
        if ArraySize(this.split) < 5 {
            ArrayClear(this.split);
            ArrayPush(this.split, 0.0); ArrayPush(this.split, 0.0); ArrayPush(this.split, 0.0); ArrayPush(this.split, 0.0); ArrayPush(this.split, 0.0);
        }
        this.split[0] += tiles;
        this.split[1] += routes;
        this.split[2] += items;
        this.split[3] += vanilla;
        this.split[4] += mirror;
    }

    // Returns the RESULT line when this sample closes a window, else "".
    public func Add(frameMs: Float, scriptMs: Float, mirrorCount: Int32) -> String {
        ArrayPush(this.frames, frameMs);
        ArrayPush(this.script, scriptMs);
        if ArraySize(this.frames) < NMCornerPerf.Window() { return ""; }
        let line = "RESULT|corner|frames=" + IntToString(ArraySize(this.frames)) + "|" + NMPerfSuite.Stats("frame", this.frames, true)
            + "|" + NMPerfSuite.Stats("script", this.script, true) + "|mirror=" + IntToString(mirrorCount) + this.SplitText();
        ArrayClear(this.split);
        ArrayClear(this.frames);
        ArrayClear(this.script);
        return line;
    }

    private func SplitText() -> String {
        if ArraySize(this.split) < 5 { return ""; }
        let n = Cast<Float>(ArraySize(this.frames));
        return "|tiles_avg=" + FloatToStringPrec(this.split[0] / n, 3) + "|routes_avg=" + FloatToStringPrec(this.split[1] / n, 3)
            + "|items_avg=" + FloatToStringPrec(this.split[2] / n, 3) + "|vanilla_avg=" + FloatToStringPrec(this.split[3] / n, 3)
            + "|mirror_avg=" + FloatToStringPrec(this.split[4] / n, 3);
    }

    public func Count() -> Int32 { return ArraySize(this.frames); }
}
