module NightMap

// Item scenarios share one camera path: a 2.5 km circle with a zoom sweep across 1..16 m/unit. The idle_* scenarios
// hold a fixed downtown view at 0.5 / 2 / 8 m/unit; panzoom_0p5_16 sweeps the whole tile range (0.5..16).
// "closed" scenarios keep the frame loop running but hide the panel and skip all module work.
public class NMPerfSuite {
    public let running: Bool;
    private let names: array<String>;
    private let counts: array<Int32>;
    private let shows: array<Bool>;
    private let modes: array<Int32>;      // 0 = circle + 1..16 sweep, 1 = fixed downtown view, 2 = circle + 0.5..16 sweep
    private let mpps: array<Float>;
    private let vanillas: array<Bool>;   // vanilla map markers enabled during the scenario
    private let idx: Int32;
    private let phase: Int32;
    private let frames: Int32;
    private let setupMs: Float;
    private let samples: array<Float>;
    private let script: array<Float>;
    private let savedFollow: Bool;
    private let savedMpp: Float;
    private let savedX: Float;
    private let savedY: Float;
    private let saved: Bool;

    private func Add(name: String, count: Int32, show: Bool, mode: Int32, mpp: Float, vanilla: Bool) {
        ArrayPush(this.names, name);
        ArrayPush(this.counts, count);
        ArrayPush(this.shows, show);
        ArrayPush(this.modes, mode);
        ArrayPush(this.mpps, mpp);
        ArrayPush(this.vanillas, vanilla);
    }

    public func Start() {
        ArrayClear(this.names);
        ArrayClear(this.counts);
        ArrayClear(this.shows);
        ArrayClear(this.modes);
        ArrayClear(this.mpps);
        ArrayClear(this.vanillas);
        this.Add("closed_baseline", 0, false, 0, 0.0, false);
        this.Add("open_empty", 0, true, 0, 0.0, false);
        this.Add("vanilla_open", 0, true, 0, 0.0, true);
        this.Add("items_5000", 5000, true, 0, 0.0, false);
        this.Add("items_20000", 20000, true, 0, 0.0, false);
        this.Add("items_50000", 50000, true, 0, 0.0, false);
        this.Add("idle_0p5", 0, true, 1, 0.5, false);
        this.Add("idle_2", 0, true, 1, 2.0, false);
        this.Add("idle_8", 0, true, 1, 8.0, false);
        this.Add("panzoom_0p5_16", 0, true, 2, 0.0, false);
        this.Add("closed_end", 0, false, 0, 0.0, false);
        this.idx = 0;
        this.phase = 0;
        this.saved = false;
        this.running = true;
        NMLog.Info("PERF|SUITE|start");
    }

    public func Step(sys: ref<NightMapSystem>, dt: Float, scriptMs: Float) {
        if !this.saved {
            let c0 = sys.Camera();
            this.savedFollow = c0.follow;
            this.savedMpp = c0.mpp;
            this.savedX = c0.cx;
            this.savedY = c0.cy;
            this.saved = true;
        }
        if this.phase == 0 {
            let t0 = NMClock.NowMs();
            if this.counts[this.idx] > 0 {
                NMDebugLayer.Fill(sys.Api(), this.counts[this.idx]);
            } else {
                NMDebugLayer.Remove(sys.Api());
            }
            this.setupMs = NMClock.NowMs() - t0;
            sys.SetPerfHidden(!this.shows[this.idx]);
            sys.SetVanillaEnabled(this.vanillas[this.idx]);
            this.phase = 1;
            this.frames = 0;
            return;
        }
        this.frames += 1;
        if this.phase == 1 {
            // Idle scenarios move to their fixed view during warm-up, so load and fade stay out of the measurement.
            if this.modes[this.idx] == 1 {
                let wc = sys.Camera();
                wc.follow = false;
                wc.SetCenter(-1800.0, 150.0);
                wc.SetMpp(this.mpps[this.idx]);
            }
            if this.frames >= 30 {
                this.phase = 2;
                this.frames = 0;
                ArrayClear(this.samples);
                ArrayClear(this.script);
                sys.Vanilla().ResetPollStats();   // poll_ms_max covers the measured frames only
            }
            return;
        }
        let a = 6.2831853 * Cast<Float>(this.frames) / 300.0;
        let cam = sys.Camera();
        cam.follow = false;
        let mode = this.modes[this.idx];
        if mode == 1 {
            cam.SetCenter(-1800.0, 150.0);
            cam.SetMpp(this.mpps[this.idx]);
        } else {
            cam.SetCenter(-700.0 + 2500.0 * CosF(a), 1500.0 + 2500.0 * SinF(a));
            if mode == 2 {
                cam.SetMpp(0.5 * PowF(32.0, 0.5 - 0.5 * CosF(2.0 * a)));
            } else {
                cam.SetMpp(PowF(16.0, 0.5 - 0.5 * CosF(2.0 * a)));
            }
        }
        ArrayPush(this.samples, dt);
        ArrayPush(this.script, scriptMs);
        if this.frames >= 300 {
            this.Report(sys);
            this.idx += 1;
            this.phase = 0;
            if this.idx >= ArraySize(this.names) {
                this.running = false;
                NMDebugLayer.Remove(sys.Api());
                sys.SetPerfHidden(false);
                sys.SetVanillaEnabled(true);
                cam.SetMpp(this.savedMpp);
                cam.SetCenter(this.savedX, this.savedY);
                cam.follow = this.savedFollow;
                NMLog.Info("PERF|SUITE|done");
            }
        }
    }

    private func Report(sys: ref<NightMapSystem>) {
        NMLog.Info("RESULT|" + this.names[this.idx] + "|items=" + ToString(this.counts[this.idx]) + "|frames=" + ToString(ArraySize(this.samples))
            + "|setup_ms=" + FloatToStringPrec(this.setupMs, 1) + "|" + NMPerfSuite.Stats("frame", this.samples, true) + "|" + NMPerfSuite.Stats("script", this.script, false)
            + "|script_max=" + FloatToStringPrec(NMPerfSuite.MaxOf(this.script), 3)
            + "|poll_ms_max=" + FloatToStringPrec(this.vanillas[this.idx] ? sys.Vanilla().pollMsMax : 0.0, 3));
    }

    private static func MaxOf(values: array<Float>) -> Float {
        let m = 0.0;
        for v in values {
            if v > m { m = v; }
        }
        return m;
    }

    // frame_avg|frame_p95|frame_p99|frame_max  (or script_avg|script_p95)
    public static func Stats(label: String, values: array<Float>, full: Bool) -> String {
        let n = ArraySize(values);
        if n == 0 {
            return label + "_avg=0|" + label + "_p95=0" + (full ? "|" + label + "_p99=0|" + label + "_max=0" : "");
        }
        let sorted: array<Float>;
        let sum = 0.0;
        for v in values {
            sum += v;
            let j = ArraySize(sorted);
            ArrayPush(sorted, v);
            while j > 0 && sorted[j - 1] > v {
                sorted[j] = sorted[j - 1];
                j -= 1;
            }
            sorted[j] = v;
        }
        let out = label + "_avg=" + FloatToStringPrec(sum / Cast<Float>(n), 3) + "|" + label + "_p95=" + FloatToStringPrec(sorted[(n * 95) / 100], 3);
        if full {
            out += "|" + label + "_p99=" + FloatToStringPrec(sorted[(n * 99) / 100], 3) + "|" + label + "_max=" + FloatToStringPrec(sorted[n - 1], 3);
        }
        return out;
    }
}
