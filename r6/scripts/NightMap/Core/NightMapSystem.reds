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

    // Debug chords. Tasks 13 and 15 add the debug layer, perf suite and calibration dump.
    private func HandleDebug(s: ref<NightMapSettings>) {
        if this.input.debugSelfTest {
            this.input.debugSelfTest = false;
            if s.debug {
                let t = new NMSelfTest();
                t.Run();
            }
        }
        this.input.debugPerf = false;
        this.input.debugCalib = false;
        this.input.debugLayer = false;
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
        if !NMTileManifest.Available() {
            this.panel.warning.SetText("TILE ARCHIVE MISSING - run tools/tiles build");
            this.panel.warning.SetVisible(true);
        }
        this.isOpen = true;
        this.input.ResetHeld();
        this.OnOpened();
        this.EnsureLoop();
        NMLog.Info("open " + FloatToStringPrec(size.X, 0) + "x" + FloatToStringPrec(size.Y, 0));
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

    public func Tick() {
        if !this.isOpen {
            this.loopAlive = false;
            return;
        }
        let now = NMClock.NowMs();
        let dt = ClampF(now - this.lastMs, 0.0, 100.0);
        this.lastMs = now;
        this.frameNo += 1;
        this.DriveCamera(dt);
        this.UpdateModules(dt);
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

    // Module hooks; Tasks 12-14 fill these in.
    private func OnOpened() {
        this.tiles = NMTileLayer.Create(this.panel.tiles);
    }

    private func OnClosing() {
        this.tiles = null;
    }

    private func UpdateModules(dt: Float) {
        this.tiles.Update(this.camera);
    }
}
