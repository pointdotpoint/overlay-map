module NightMap

public class NightMapFrame extends DelayCallback {
    public let system: wref<NightMapSystem>;

    public func Call() {
        if IsDefined(this.system) {
            this.system.Tick();
        }
    }
}

// Owns the overlay. Zero work while closed: only the Input/Key callback stays registered.
public class NightMapSystem extends ScriptableSystem {
    private let api: ref<NightMap>;
    private let input: ref<NMInput>;
    private let isOpen: Bool;
    private let loopAlive: Bool;
    private let panel: ref<NMPanel>;
    private let camera: ref<NMCamera>;
    private let lastMs: Float;
    private let holdMs: Float;
    private let savedMpp: Float = 4.0;
    private let frameNo: Int32;
    private let tiles: ref<NMTileLayer>;
    private let renderer: ref<NMItemRenderer>;
    private let crosshair: ref<NMCrosshair>;
    private let card: ref<NMInfoCard>;
    private let marker: ref<NMPlayerMarker>;
    private let cardApiRev: Int32;
    private let scaleRev: Int32;
    private let perf: ref<NMPerfSuite>;
    private let perfHidden: Bool;
    private let cacheTotal: Int32;
    private let cacheN: Int32;
    private let cacheCats: array<Int32>;
    private let cacheCounts: array<Int32>;
    private let versionLogged: Bool;
    private let layerEpoch: Int32;
    private let imageRetries: Int32;
    private let imageRev: Int32;

    private func OnAttach() {
        this.api = NightMap.Create();
        if NMTileManifest.Available() {
            this.api.SetWorld(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        }
        this.input = new NMInput();
        GameInstance.GetCallbackSystem().RegisterCallback(n"Input/Key", this, n"OnKeyInput");
        NMLog.Info("loaded (tiles " + (NMTileManifest.Available() ? "present" : "missing") + ", precise clock " + ToString(NMClock.Precise()) + ")");
    }

    // Loading a save or quitting to menu ends the session: tear the overlay down so nothing is orphaned.
    private func OnDetach() {
        GameInstance.GetCallbackSystem().UnregisterCallback(n"Input/Key", this);
        this.Close();
    }

    public func Api() -> ref<NightMap> { return this.api; }
    public func IsOpen() -> Bool { return this.isOpen; }
    public func Camera() -> ref<NMCamera> { return this.camera; }
    public func Panel() -> ref<NMPanel> { return this.panel; }

    private func Settings() -> ref<NightMapSettings> {
        return NightMapSettings.Get(this.GetGameInstance());
    }

    private func HudWindow() -> wref<inkCompoundWidget> {
        let layer = GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer");
        if !IsDefined(layer) {
            return null;
        }
        return layer.GetVirtualWindow();
    }

    private cb func OnKeyInput(evt: ref<KeyInputEvent>) {
        let s = this.Settings();
        if !IsDefined(s) {
            return;
        }
        this.input.Handle(s, evt.GetKey(), evt.GetAction(), evt.IsShiftDown(), evt.IsControlDown(), evt.IsAltDown(), this.isOpen);
        if this.input.toggle {
            this.input.toggle = false;
            if this.isOpen {
                this.Close();
            } else {
                this.Open();
            }
        }
        this.HandleDebug(s);
    }

    // Debug chords: self-test, debug layer, perf suite, calibration dump.
    private func HandleDebug(s: ref<NightMapSettings>) {
        if this.input.debugSelfTest {
            this.input.debugSelfTest = false;
            if s.debug {
                let t = new NMSelfTest();
                t.Run();
            }
        }
        if this.input.debugLayer {
            this.input.debugLayer = false;
            if s.debug {
                if IsDefined(this.api.GetLayer(NMDebugLayer.Id())) {
                    NMDebugLayer.Remove(this.api);
                    NMLog.Info("debug layer off");
                } else {
                    NMDebugLayer.Fill(this.api, 5000);
                    NMLog.Info("debug layer on (5000 items)");
                }
            }
        }
        if this.input.debugPerf {
            this.input.debugPerf = false;
            if s.debug {
                if !NMClock.Precise() {
                    NMLog.Error("perf suite needs RedIMGRetriever (precise clock)");
                } else {
                    if !this.isOpen {
                        this.Open();
                    }
                    if this.isOpen {
                        this.perf = new NMPerfSuite();
                        this.perf.Start();
                    } else {
                        this.perf = null;
                        NMLog.Error("perf suite not started: panel failed to open");
                    }
                }
            }
        }
        if this.input.debugCalib {
            this.input.debugCalib = false;
            if s.debug {
                NMLog.Info("calibration points: " + ToString(NMCalibration.Dump(this.GetGameInstance())));
            }
        }
    }

    public func Open() {
        if this.isOpen {
            return;
        }
        let window = this.HudWindow();
        if !IsDefined(window) {
            NMLog.Error("HUD layer not available");
            return;
        }
        let size = window.GetSize();
        if size.X < 100.0 || size.Y < 100.0 {
            size = new Vector2(3840.0, 2160.0);
        }
        let s = this.Settings();
        let layout = NMPanelLayout.Compute(size.X, size.Y);
        this.panel = NMPanel.Build(window, layout, IsDefined(s) ? s.panelOpacity : 0.74);
        let maxMpp = NMTileManifest.LevelCount() > 0 ? NMTileManifest.LevelMpp(NMTileManifest.LevelCount() - 1) : 16.0;
        let bounds = NMRect.Create(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        this.camera = NMCamera.Create(layout.mapW, layout.mapH, bounds, 0.5, maxMpp);
        this.camera.SetMpp(this.savedMpp);
        this.CenterOnPlayer(true);
        if IsDefined(s) {
            this.panel.hints.SetText(NMInput.HintText(s));
            if s.debug {
                this.panel.AddClipProbe();
            }
        }
        this.isOpen = true;
        this.input.ResetHeld();
        this.OnOpened();
        this.UpdateWarning();
        this.EnsureLoop();
        NMLog.Info("open " + FloatToStringPrec(size.X, 0) + "x" + FloatToStringPrec(size.Y, 0));
    }

    // Tile problems (non-blocking): missing manifest, manifest present but archive not loaded, tiles built for another game version.
    private func UpdateWarning() {
        let text = "";
        if !NMTileManifest.Available() {
            text = "TILE ARCHIVE MISSING - run tools/tiles build";
        } else if IsDefined(this.tiles) && !this.tiles.available {
            text = "Map tiles not found: install NightMap.archive";
        }
        let built = NMTileManifest.SourceGameVersion();
        let handler = GameInstance.GetSystemRequestsHandler();
        if IsDefined(handler) && NotEquals(built, "") {
            let running = handler.GetGameVersion();
            let a = NightMapSystem.MajorMinor(built);
            let b = NightMapSystem.MajorMinor(running);
            if NotEquals(b, "") && NotEquals(a, b) {
                if !this.versionLogged {
                    this.versionLogged = true;
                    NMLog.Info("game version mismatch: tiles built for " + built + ", game is " + running);
                }
                if NotEquals(text, "") {
                    text += "  |  ";
                }
                text += "Tiles built for " + a + ", game is " + b + " - rebuild tiles";
            }
        }
        if NotEquals(text, "") {
            this.panel.warning.SetText(text);
            this.panel.warning.SetVisible(true);
        }
    }

    // Leading "major.minor" of a version string ("2.31", "v2.31.1" -> "2.31"; "2.3.1" -> "2.3").
    public static func MajorMinor(v: String) -> String {
        let s = StrReplaceAll(v, "v", "");
        let first = StrFindFirst(s, ".");
        if first < 0 {
            return s;
        }
        let rest = StrAfterFirst(s, ".");
        let second = StrFindFirst(rest, ".");
        if second < 0 {
            return s;
        }
        return StrBeforeFirst(s, ".") + "." + StrLeft(rest, second);
    }

    public func Close() {
        if !this.isOpen {
            return;
        }
        this.isOpen = false;
        if IsDefined(this.camera) {
            this.savedMpp = this.camera.mpp;
        }
        if IsDefined(this.input) {
            this.input.ResetHeld();
        }
        this.OnClosing();
        if IsDefined(this.panel) {
            this.panel.Destroy();
        }
        this.panel = null;
        NMLog.Info("closed");
    }

    private func CenterOnPlayer(instant: Bool) {
        let player = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) || !IsDefined(this.camera) {
            return;
        }
        let pos = player.GetWorldPosition();
        if instant {
            this.camera.SetCenter(pos.X, pos.Y);
        } else {
            this.camera.EaseTo(pos.X, pos.Y, this.camera.mpp, 250.0);
        }
        this.camera.follow = true;
    }

    private func EnsureLoop() {
        if this.loopAlive {
            return;
        }
        this.loopAlive = true;
        this.lastMs = NMClock.NowMs();
        this.Schedule();
    }

    // Zero-delay timed callback: DelayCallbackNextFrame re-armed from a callback is silently dropped.
    private func Schedule() {
        let cb = new NightMapFrame();
        cb.system = this;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.0, false);
    }

    public func SetPerfHidden(hidden: Bool) {
        this.perfHidden = hidden;
        if IsDefined(this.panel) {
            this.panel.root.SetVisible(!hidden);
        }
    }

    public func Tick() {
        if !this.isOpen {
            this.loopAlive = false;
            return;
        }
        let now = NMClock.NowMs();
        let raw = now - this.lastMs;              // true frame time, recorded by the perf suite
        let dt = ClampF(raw, 0.0, 100.0);         // clamped step for camera motion
        this.lastMs = now;
        this.frameNo += 1;
        this.DriveCamera(dt);
        let t0 = NMClock.NowMs();
        if !this.perfHidden {
            this.UpdateModules(dt);
        }
        let scriptMs = NMClock.NowMs() - t0;
        if IsDefined(this.perf) && this.perf.running {
            this.perf.Step(this, raw, scriptMs);
        }
        this.Schedule();
    }

    private func DriveCamera(dt: Float) {
        let pan = this.input.PanVector();
        if pan.X != 0.0 || pan.Y != 0.0 {
            this.holdMs += dt;
            let accel = this.holdMs > 500.0 ? MinF(1.0 + (this.holdMs - 500.0) / 1000.0, 3.0) : 1.0;
            let step = 1500.0 * accel * dt / 1000.0;
            this.camera.PanPixels(pan.X * step, pan.Y * step);
        } else {
            this.holdMs = 0.0;
        }
        if this.input.zoomIn {
            this.camera.ZoomBy(PowF(1.5, dt / 1000.0));
        }
        if this.input.zoomOut {
            this.camera.ZoomBy(1.0 / PowF(1.5, dt / 1000.0));
        }
        if this.input.recenter {
            this.input.recenter = false;
            this.CenterOnPlayer(false);
        }
        if this.camera.follow && !this.camera.IsEasing() {
            this.CenterOnPlayer(true);
        }
        this.camera.Tick(dt);
    }

    private func OnOpened() {
        this.cardApiRev = -1;
        this.scaleRev = -1;
        this.cacheTotal = -1;
        this.imageRetries = 0;
        this.imageRev = this.api.revision;
        this.layerEpoch = this.api.layerEpoch;
        let l = this.panel.layout;
        this.tiles = NMTileLayer.Create(this.panel.tiles);
        this.renderer = NMItemRenderer.Create(this.api, this.panel.items, l.scale);
        this.marker = NMPlayerMarker.Create(this.panel.overlay, l.scale);
        this.crosshair = NMCrosshair.Create(this.panel.overlay, l.mapW, l.mapH, l.scale);
        this.card = NMInfoCard.Create(this.panel.card, l.cardW, l.scale);
        this.UpdateHeader();
    }

    private func OnClosing() {
        if IsDefined(this.perf) && this.perf.running {
            NMDebugLayer.Remove(this.api);
        }
        this.perf = null;
        this.perfHidden = false;
        this.tiles = null;
        this.renderer = null;
        this.marker = null;
        this.crosshair = null;
        this.card = null;
    }

    private func UpdateModules(dt: Float) {
        let l = this.panel.layout;
        this.tiles.Update(this.camera);
        if this.api.revision != this.imageRev {
            this.imageRev = this.api.revision;
            this.imageRetries = 0;
        }
        // Retry unresolved images every 15 frames, at most 20 times (about 5 s) per data revision.
        if this.renderer.pendingImages > 0 && this.frameNo % 15 == 0 && this.imageRetries < 20 {
            this.imageRetries += 1;
            this.renderer.Invalidate();
        }
        // RemoveLayer renumbers layer indices: drop the stale selection so the crosshair re-picks.
        if this.api.layerEpoch != this.layerEpoch {
            this.layerEpoch = this.api.layerEpoch;
            this.crosshair.Reset();
            this.cardApiRev = -1;
        }
        let relaid = this.renderer.Update(this.camera, l.mapW, l.mapH);
        if relaid {
            let changed = this.crosshair.Update(this.renderer, l.mapW, l.mapH, l.scale);
            // Re-query card content only when the selection or the data changed, not on every pan frame.
            if changed || this.api.revision != this.cardApiRev || this.ClusterStale() {
                this.cardApiRev = this.api.revision;
                this.RefreshCard(changed);
            }
        }
        if this.input.act {
            this.input.act = false;
            this.Activate();
        }
        this.marker.Update(this.camera, GetPlayer(this.GetGameInstance()), l.mapW, l.mapH);
        if this.camera.revision != this.scaleRev {
            this.UpdateScale();
        }
        if this.frameNo % 30 == 0 {
            this.UpdateHeader();
        }
    }

    // True when the selected cluster's displayed total or category counts differ from the cached ones.
    private func ClusterStale() -> Bool {
        let c = this.crosshair;
        if c.selKind != 1 || c.sel < 0 {
            return false;
        }
        let slot = this.renderer.candSlot[c.sel];
        let n = this.renderer.clCatN[slot];
        if this.renderer.clTotal[slot] != this.cacheTotal || n != this.cacheN {
            return true;
        }
        let k = 0;
        while k < n {
            if this.renderer.clCats[slot * 6 + k] != this.cacheCats[k] || this.renderer.clCatCount[slot * 6 + k] != this.cacheCounts[k] {
                return true;
            }
            k += 1;
        }
        return false;
    }

    private func RefreshCard(changed: Bool) {
        let c = this.crosshair;
        if c.selKind == 0 && c.selLayer >= 0 && c.selLayer < ArraySize(this.api.layers) {
            let L = this.api.layers[c.selLayer];
            if !L.IsAlive(c.selItem) {
                this.card.ShowEmpty();
                return;
            }
            let d: ref<NightMapDetails>;
            if IsDefined(L.listener) {
                if changed {
                    L.listener.OnSelected(c.selItem);
                }
                d = L.listener.GetDetails(c.selItem);
            }
            if !IsDefined(d) {
                d = this.DefaultDetails(L, c.selItem);
            }
            this.card.ShowDetails(d, this.api.catColor[L.catGlobal[L.cat[c.selItem]]]);
        } else if c.selKind == 1 && c.sel >= 0 {
            let slot = this.renderer.candSlot[c.sel];
            let cats: array<Int32>;
            let counts: array<Int32>;
            let k = 0;
            while k < this.renderer.clCatN[slot] {
                ArrayPush(cats, this.renderer.clCats[slot * 6 + k]);
                ArrayPush(counts, this.renderer.clCatCount[slot * 6 + k]);
                k += 1;
            }
            this.cacheTotal = this.renderer.clTotal[slot];
            this.cacheN = this.renderer.clCatN[slot];
            this.cacheCats = cats;
            this.cacheCounts = counts;
            let s = this.Settings();
            this.card.ShowCluster(this.renderer.clTotal[slot], cats, counts, this.api, IsDefined(s) ? NMInput.KeyName(s.keyAct) : "ACT");
        } else {
            this.card.ShowEmpty();
        }
    }

    private func DefaultDetails(L: ref<NightMapLayer>, id: Int32) -> ref<NightMapDetails> {
        let g = L.catGlobal[L.cat[id]];
        let title = NotEquals(L.label[id], "") ? L.label[id] : this.api.catDisplay[g];
        let d = NightMapDetails.Create(this.api.catDisplay[g], title);
        let player = GetPlayer(this.GetGameInstance());
        if IsDefined(player) {
            let p = player.GetWorldPosition();
            let dx = L.px[id] - p.X;
            let dy = L.py[id] - p.Y;
            d.AddRow("Distance", NMMath.FormatMeters(SqrtF(dx * dx + dy * dy)));
        }
        return d;
    }

    private func Activate() {
        let c = this.crosshair;
        if c.selKind == 0 && c.selLayer >= 0 && c.selLayer < ArraySize(this.api.layers) {
            let L = this.api.layers[c.selLayer];
            if IsDefined(L.listener) && L.IsAlive(c.selItem) {
                L.listener.OnActivated(c.selItem);
            }
        } else if c.selKind == 1 && c.sel >= 0 {
            let slot = this.renderer.candSlot[c.sel];
            let l = this.panel.layout;
            let target = this.renderer.clWorld[slot] / (0.6 * MinF(l.mapW, l.mapH));
            this.camera.follow = false;
            this.camera.EaseTo(this.renderer.clWx[slot], this.renderer.clWy[slot], target, 300.0);
        }
    }

    private func UpdateScale() {
        let l = this.panel.layout;
        this.scaleRev = this.camera.revision;
        let maxMeters = 336.0 * l.scale * this.camera.mpp;
        let len = NMMath.NiceLength(maxMeters);
        this.panel.scaleBar.SetSize(new Vector2(len / this.camera.mpp, 5.0 * l.scale));
        this.panel.scaleLabel.SetText(NMMath.FormatMeters(len));
    }

    private func UpdateHeader() {
        let s = this.Settings();
        this.panel.subtitle.SetText(this.DistrictName());
        this.UpdateScale();
        if IsDefined(s) {
            let hint = NMInput.HintText(s);
            if this.input.arrowSeen {
                hint += "   ·   ARROW KEYS IGNORED - TURN NUMLOCK ON";
            }
            this.panel.hints.SetText(hint);
        }
    }

    private func DistrictName() -> String {
        let ps = GameInstance.GetScriptableSystemsContainer(this.GetGameInstance()).Get(n"PreventionSystem") as PreventionSystem;
        if !IsDefined(ps) {
            return "";
        }
        let d = ps.GetCurrentDistrict();
        if !IsDefined(d) {
            return "";
        }
        let rec = d.GetDistrictRecord();
        return IsDefined(rec) ? StrUpper(GetLocalizedText(rec.LocalizedName())) : "";
    }
}
