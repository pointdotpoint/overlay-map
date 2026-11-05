module OverlayMap

// Item scenarios share one camera path: a 2.5 km circle with a zoom sweep across 1..16 m/unit. The idle_* scenarios
// hold a fixed downtown view at 0.5 / 2 / 8 m/unit; panzoom_0p5_16 sweeps the whole tile range (0.5..16).
// "closed" scenarios keep the frame loop running but hide the panel and skip all module work.
public class NMPerfSuite {
    public let running: Bool;
    private let names: array<String>;
    private let counts: array<Int32>;
    private let shows: array<Bool>;
    private let modes: array<Int32>;      // 0 = circle + 1..16 sweep, 1 = fixed downtown view, 2 = circle + 0.5..16 sweep,
                                          // 3 = circle at a fixed m/unit (pan only)
    private let mpps: array<Float>;
    private let vanillas: array<Bool>;   // vanilla map markers enabled during the scenario
    private let routeRows: array<Bool>;  // GPS routes enabled during the scenario (route_open only)
    private let routeDrawn: Bool;        // a route was on screen at the first measured frame
    private let photoCounts: array<Int32>;  // seeded photo spots during the scenario (photos_500 only; others none)
    private let idx: Int32;
    private let phase: Int32;
    private let frames: Int32;
    private let setupMs: Float;
    private let samples: array<Float>;
    private let script: array<Float>;
    private let tiles: array<Float>;   // the tile layers' share of script (sys.perfTileMs)
    private let items: array<Float>;   // the item relayout's share (sys.perfItemMs)
    private let route: array<Float>;   // UpdateRoutes (sys.perfRouteMs) and its stages
    private let routeProj: array<Float>;
    private let routeLay: array<Float>;
    private let routePlace: array<Float>;
    private let rTrim: array<Float>;
    private let rMap: array<Float>;
    private let rSimp: array<Float>;
    private let rSmooth: array<Float>;
    private let routeIters: Int32;     // max per frame
    private let routeWorld: Int32;
    private let routeScreen: Int32;
    private let savedFollow: Bool;
    private let savedMpp: Float;
    private let savedX: Float;
    private let savedY: Float;
    private let saved: Bool;

    private func Add(name: String, count: Int32, show: Bool, mode: Int32, mpp: Float, vanilla: Bool, routes: Bool) {
        ArrayPush(this.names, name);
        ArrayPush(this.counts, count);
        ArrayPush(this.shows, show);
        ArrayPush(this.modes, mode);
        ArrayPush(this.mpps, mpp);
        ArrayPush(this.vanillas, vanilla);
        ArrayPush(this.routeRows, routes);
        ArrayPush(this.photoCounts, 0);
    }

    private let only: String;   // StartOnly: keep the scenarios whose name contains this, plus the closed baselines

    public func StartOnly(only: String) {
        this.only = only;
        this.Start();
    }

    private func Filter() {
        if StrLen(this.only) == 0 { return; }
        let i = ArraySize(this.names) - 1;
        while i >= 0 {
            if !StrContains(this.names[i], this.only) && !StrBeginsWith(this.names[i], "closed_") {
                ArrayErase(this.names, i);
                ArrayErase(this.counts, i);
                ArrayErase(this.shows, i);
                ArrayErase(this.modes, i);
                ArrayErase(this.mpps, i);
                ArrayErase(this.vanillas, i);
                ArrayErase(this.routeRows, i);
                ArrayErase(this.photoCounts, i);
            }
            i -= 1;
        }
    }

    public func Start() {
        ArrayClear(this.names);
        ArrayClear(this.counts);
        ArrayClear(this.shows);
        ArrayClear(this.modes);
        ArrayClear(this.mpps);
        ArrayClear(this.vanillas);
        ArrayClear(this.routeRows);
        ArrayClear(this.photoCounts);
        this.Add("closed_baseline", 0, false, 0, 0.0, false, false);
        this.Add("open_empty", 0, true, 0, 0.0, false, false);
        this.Add("vanilla_open", 0, true, 0, 0.0, true, false);
        this.Add("route_open", 0, true, 0, 0.0, false, true);   // track a quest ~700 m away before starting the suite
        this.Add("pan_1", 0, true, 3, 1.0, false, false);       // pan only at 1 m/unit around V, no route
        this.Add("pan_vanilla_1", 0, true, 3, 1.0, true, false); // likewise with the vanilla map markers
        this.Add("route_pan_1", 0, true, 3, 1.0, false, true);  // the same route, pan only at 1 m/unit
        this.Add("photos_500", 0, true, 0, 0.0, false, false);  // 500 seeded photo spots, real shot hashes
        this.photoCounts[ArraySize(this.photoCounts) - 1] = 500;
        this.Add("items_5000", 5000, true, 0, 0.0, false, false);
        this.Add("items_20000", 20000, true, 0, 0.0, false, false);
        this.Add("items_50000", 50000, true, 0, 0.0, false, false);
        this.Add("idle_0p5", 0, true, 1, 0.5, false, false);
        this.Add("idle_2", 0, true, 1, 2.0, false, false);
        this.Add("idle_8", 0, true, 1, 8.0, false, false);
        this.Add("panzoom_0p5_16", 0, true, 2, 0.0, false, false);
        this.Add("closed_end", 0, false, 0, 0.0, false, false);
        this.Filter();
        this.idx = 0;
        this.phase = 0;
        this.saved = false;
        this.running = true;
        NMLog.Info("PERF|SUITE|start");
    }

    public func Step(sys: ref<OverlayMapSystem>, dt: Float, scriptMs: Float) {
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
            sys.SetRoutesEnabled(this.routeRows[this.idx]);
            sys.Photos().SeedForPerf(this.photoCounts[this.idx]);   // 0: no photo pins, like suites before photo pins
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
                ArrayClear(this.tiles);
                ArrayClear(this.items);
                ArrayClear(this.route);
                ArrayClear(this.routeProj);
                ArrayClear(this.routeLay);
                ArrayClear(this.routePlace);
                ArrayClear(this.rTrim);
                ArrayClear(this.rMap);
                ArrayClear(this.rSimp);
                ArrayClear(this.rSmooth);
                this.routeIters = 0;
                this.routeWorld = 0;
                this.routeScreen = 0;
                sys.Vanilla().ResetPollStats();   // poll_ms_max covers the measured frames only
                sys.Gps().ResetReadStats();       // route_read_ms_max likewise
                this.routeDrawn = this.routeRows[this.idx] && IsDefined(sys.Routes()) && sys.Routes().HasRoute();
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
            if mode == 3 {
                // Around where the map opened (V), so the tracked route stays on screen.
                cam.SetCenter(this.savedX + 300.0 * CosF(a), this.savedY + 300.0 * SinF(a));
                cam.SetMpp(this.mpps[this.idx]);
            } else {
                cam.SetCenter(-700.0 + 2500.0 * CosF(a), 1500.0 + 2500.0 * SinF(a));
                if mode == 2 {
                    cam.SetMpp(0.5 * PowF(32.0, 0.5 - 0.5 * CosF(2.0 * a)));
                } else {
                    cam.SetMpp(PowF(16.0, 0.5 - 0.5 * CosF(2.0 * a)));
                }
            }
        }
        ArrayPush(this.samples, dt);
        ArrayPush(this.script, scriptMs);
        ArrayPush(this.tiles, this.shows[this.idx] ? sys.perfTileMs : 0.0);
        ArrayPush(this.items, this.shows[this.idx] ? sys.perfItemMs : 0.0);
        let rl = sys.Routes();
        let on = this.shows[this.idx] && IsDefined(rl);
        ArrayPush(this.route, on ? sys.perfRouteMs : 0.0);
        ArrayPush(this.routeProj, on ? rl.projMs : 0.0);
        ArrayPush(this.routeLay, on ? rl.layoutMs : 0.0);
        ArrayPush(this.routePlace, on ? rl.placeMs : 0.0);
        ArrayPush(this.rTrim, on ? rl.trimMs : 0.0);
        ArrayPush(this.rMap, on ? rl.mapMs : 0.0);
        ArrayPush(this.rSimp, on ? rl.simpMs : 0.0);
        ArrayPush(this.rSmooth, on ? rl.smoothMs : 0.0);
        if on {
            this.routeIters = Max(this.routeIters, rl.iters);
            this.routeWorld = Max(this.routeWorld, rl.worldPts);
            this.routeScreen = Max(this.routeScreen, rl.screenPts);
        }
        if this.frames >= 300 {
            this.Report(sys);
            this.idx += 1;
            this.phase = 0;
            if this.idx >= ArraySize(this.names) {
                this.running = false;
                NMDebugLayer.Remove(sys.Api());
                sys.SetPerfHidden(false);
                sys.SetVanillaEnabled(true);
                sys.SetRoutesEnabled(true);
                sys.Photos().EndPerfSeed();
                cam.SetMpp(this.savedMpp);
                cam.SetCenter(this.savedX, this.savedY);
                cam.follow = this.savedFollow;
                NMLog.Info("PERF|SUITE|done");
            }
        }
    }

    private func Report(sys: ref<OverlayMapSystem>) {
        NMLog.Info("RESULT|" + this.names[this.idx] + "|items=" + ToString(this.counts[this.idx]) + "|frames=" + ToString(ArraySize(this.samples))
            + "|setup_ms=" + FloatToStringPrec(this.setupMs, 1) + "|" + NMPerfSuite.Stats("frame", this.samples, true) + "|" + NMPerfSuite.Stats("script", this.script, false)
            + "|script_max=" + FloatToStringPrec(NMPerfSuite.MaxOf(this.script), 3)
            + "|" + NMPerfSuite.Stats("tiles", this.tiles, false) + "|" + NMPerfSuite.Stats("items", this.items, false)
            + "|poll_ms_max=" + FloatToStringPrec(this.vanillas[this.idx] ? sys.Vanilla().pollMsMax : 0.0, 3)
            + "|route_drawn=" + (this.routeDrawn ? "1" : "0")
            + "|route_read_ms_max=" + FloatToStringPrec(this.routeRows[this.idx] ? sys.Gps().readMsMax : 0.0, 3)
            + "|" + NMPerfSuite.Stats("route", this.route, false) + "|" + NMPerfSuite.Stats("rproj", this.routeProj, false)
            + "|" + NMPerfSuite.Stats("rlay", this.routeLay, false) + "|" + NMPerfSuite.Stats("rplace", this.routePlace, false)
            + "|" + NMPerfSuite.Stats("rtrim", this.rTrim, false) + "|" + NMPerfSuite.Stats("rmap", this.rMap, false)
            + "|" + NMPerfSuite.Stats("rsimp", this.rSimp, false) + "|" + NMPerfSuite.Stats("rsmooth", this.rSmooth, false)
            + "|route_iters_max=" + ToString(this.routeIters) + "|route_world_pts=" + ToString(this.routeWorld)
            + "|route_screen_pts=" + ToString(this.routeScreen));
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
