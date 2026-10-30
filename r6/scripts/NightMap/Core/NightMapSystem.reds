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
    private let savedMpp: Float = 0.0;   // 0 = not opened yet this session: start fully zoomed in
    private let frameNo: Int32;
    private let layers: ref<NMLayerStack>;
    private let holoTheme: Int32;      // NMTheme.ThemeIndex(NightMapSettings.holoColor), read once per open
    private let holoEffects: Bool;     // NightMapSettings.hologramEffects, read once per open
    private let renderer: ref<NMItemRenderer>;
    private let crosshair: ref<NMCrosshair>;
    private let tooltip: ref<NMTooltip>;
    private let drawer: ref<NMPhotoDrawer>;
    private let reticle: ref<NMReticle>;
    private let wasPanning: Bool;
    private let drawerShift: Float;   // px the focus point sits left of the map-area centre (middle of the map left of the sidebar)
    private let marker: ref<NMPlayerMarker>;
    private let tipApiRev: Int32;
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
    private let vanilla: ref<NMVanilla>;
    private let gps: ref<NMGps>;
    private let routes: ref<NMRouteLayer>;
    private let routesOff: Bool;          // perf suite override (SetRoutesEnabled)
    private let photos: ref<NMPhotos>;
    private let hud: ref<NMHudHider>;     // set while the map is open with "Hide HUD while open" on
    private let lastRouteReadMs: Float;
    private let filterView: Int32;
    // Header change-cache: SetText / tint only when the value changed (reset in OnOpened).
    private let hdrSubtitle: String;
    private let hdrQuestState: Int32;   // -1 unknown, 0 hidden, 1 shown
    private let hdrQuestTitle: String;
    private let hdrQuestObjective: String;
    private let hdrQuestIsQuest: Bool;
    private let hdrHint: String;
    private let hdrScaleLabel: String;

    private func OnAttach() {
        this.api = NightMap.Create();
        if NMTileManifest.Available() {
            this.api.SetWorld(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        }
        this.vanilla = NMVanilla.Create(this.api, this.GetGameInstance());
        this.input = new NMInput();
        GameInstance.GetCallbackSystem().RegisterCallback(n"Input/Key", this, n"OnKeyInput");
        NMLog.Info("loaded (tiles " + (NMTileManifest.Available() ? "present" : "missing") + ", precise clock " + ToString(NMClock.Precise()) + ")");
    }

    // Loading a save or quitting to menu ends the session: tear the overlay down so nothing is orphaned.
    private func OnDetach() {
        GameInstance.GetCallbackSystem().UnregisterCallback(n"Input/Key", this);
        this.Close();
    }

    public static func Get(gi: GameInstance) -> ref<NightMapSystem> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"NightMap.NightMapSystem") as NightMapSystem;
    }

    public func Api() -> ref<NightMap> { return this.api; }
    public func Vanilla() -> ref<NMVanilla> { return this.vanilla; }

    // Created on first use: the minimap may attach before this system's OnAttach.
    // Created on first use: photo mode and the minimap may call in before this system's OnAttach.
    public func Photos() -> ref<NMPhotos> {
        if !IsDefined(this.photos) { this.photos = new NMPhotos(); }
        return this.photos;
    }
    public func Gps() -> ref<NMGps> {
        if !IsDefined(this.gps) { this.gps = new NMGps(); }
        return this.gps;
    }
    public func SetVanillaEnabled(on: Bool) { this.vanilla.SetEnabled(on); }
    public func SetRoutesEnabled(on: Bool) { this.routesOff = !on; }
    public func RoutesOn() -> Bool { return !this.routesOff; }

    // Perf-suite overrides never outlive the map: a suite closed mid-run must not leave routes off for the session.
    public func ClearPerfOverrides() {
        this.routesOff = false;
        this.Photos().EndPerfSeed();   // never leave seeded spots (teleport targets) behind
    }
    public func Routes() -> ref<NMRouteLayer> { return this.routes; }
    public func IsOpen() -> Bool { return this.isOpen; }
    public func Camera() -> ref<NMCamera> { return this.camera; }
    public func Panel() -> ref<NMPanel> { return this.panel; }

    private func Settings() -> ref<NightMapSettings> {
        return NightMapSettings.Get(this.GetGameInstance());
    }

    // Past the finest tiles (0.5 m/px), which magnify: this zoom exists to see photo thumbnails bigger.
    public static func MinMpp() -> Float { return 0.1; }

    // The first open of a session, and the closest view the map's tiles are sharp at.
    public static func OpenMpp() -> Float {
        return NMTileManifest.LevelCount() > 0 ? NMTileManifest.LevelMpp(0) : 0.5;
    }

    public static func MaxMpp() -> Float {
        return NMTileManifest.LevelCount() > 0 ? NMTileManifest.LevelMpp(NMTileManifest.LevelCount() - 1) : 16.0;
    }

    public func Layers() -> ref<NMLayerStack> { return this.layers; }

    // Re-applies NMTheme to the open map's tile layers (a no-op while closed).
    public func ApplyTheme() {
        if IsDefined(this.layers) {
            this.layers.ApplyTheme(this.holoTheme);
        }
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
        this.holoTheme = IsDefined(s) ? NMTheme.ThemeIndex(s.holoColor) : 0;
        this.holoEffects = IsDefined(s) ? s.hologramEffects : true;
        this.panel = NMPanel.Build(window, layout, IsDefined(s) ? s.panelOpacity : NMTheme.DefaultPanelOpacity(), this.holoTheme, this.holoEffects);
        if !IsDefined(s) || s.hideHud {
            this.hud = NMHudHider.Hide(window, this.panel.root);
        }
        let bounds = NMRect.Create(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        this.camera = NMCamera.Create(layout.mapW, layout.mapH, bounds, NightMapSystem.MinMpp(), NightMapSystem.MaxMpp());
        this.camera.SetMpp(this.savedMpp > 0.0 ? this.savedMpp : NightMapSystem.OpenMpp());
        this.CenterOnPlayer(true);
        if IsDefined(s) {
            this.panel.hints.SetText(NMInput.HintText(s, NMVanillaFilters.ViewName(this.filterView), "FAST TRAVEL"));
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
        } else if IsDefined(this.layers) && !this.layers.available {
            text = "Map tiles not found: install NightMap.archive";
        }
        let built = NMTileManifest.SourceGameVersion();
        let handler = GameInstance.GetSystemRequestsHandler();
        if IsDefined(handler) && NotEquals(built, "") {
            let running = handler.GetGameVersion();
            let a = NightMapSystem.Normalise(built);
            let b = NightMapSystem.Normalise(running);
            if Equals(a, "") || Equals(b, "") {
                if !this.versionLogged {
                    this.versionLogged = true;
                    NMLog.Info("game version not comparable: tiles built for '" + built + "', game reports '" + running + "'");
                }
            } else if NotEquals(a, b) {
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

    // Canonical "major.minor" from the leading digits.digits token ("" = unknown, which never warns). A one-digit minor
    // is joined with the patch number ("2.3.1" -> "2.31", as the game's 2.31 is spelled); a one-digit minor with no
    // patch is ambiguous ("2.3") and unknown.
    public static func Normalise(v: String) -> String {
        let digits = "0123456789";
        let n = StrLen(v);
        let i = 0;
        while i < n && StrFindFirst(digits, StrMid(v, i, 1)) < 0 {
            i += 1;
        }
        let major = "";
        while i < n && StrFindFirst(digits, StrMid(v, i, 1)) >= 0 {
            major += StrMid(v, i, 1);
            i += 1;
        }
        if Equals(major, "") || i >= n || NotEquals(StrMid(v, i, 1), ".") {
            return "";
        }
        i += 1;
        let minor = "";
        while i < n && StrFindFirst(digits, StrMid(v, i, 1)) >= 0 {
            minor += StrMid(v, i, 1);
            i += 1;
        }
        if Equals(minor, "") {
            return "";
        }
        if StrLen(minor) == 1 {
            if i + 1 < n && Equals(StrMid(v, i, 1), ".") && StrFindFirst(digits, StrMid(v, i + 1, 1)) >= 0 {
                i += 1;
                while i < n && StrFindFirst(digits, StrMid(v, i, 1)) >= 0 {
                    minor += StrMid(v, i, 1);
                    i += 1;
                }
            } else {
                return "";
            }
        }
        return major + "." + minor;
    }

    // Fast travels to the selected vanilla fast travel marker with the game's own FastTravelSystem. Closes the map
    // when the request is sent; every refusal is logged and leaves the map open.
    public func StartFastTravel() -> Bool {
        let gi = this.GetGameInstance();
        let player = GetPlayer(gi);
        if !IsDefined(player) || !IsDefined(this.crosshair) || !IsDefined(this.vanilla) {
            NMLog.Info("fasttravel|refused|not ready");
            return false;
        }
        let m = this.SelectedMappin();
        let why = NMFastTravel.Check(gi, m, player);
        if StrLen(why) > 0 {
            NMLog.Info("fasttravel|refused|" + why);
            return false;
        }
        NMLog.Info("fasttravel|start|" + NMVanillaText.Title(m, m.GetVariant()));
        this.Close();
        NMFastTravel.Travel(gi, m, player);
        return true;
    }

    // The photo spot behind the crosshair's selected item, when it is a photo pin; else null.
    private func SelectedPhoto() -> ref<NMPhotoSpot> {
        let c = this.crosshair;
        if !IsDefined(c) || c.selKind != 0 || c.selLayer < 0 || c.selLayer >= ArraySize(this.api.layers) {
            return null;
        }
        let L = this.api.layers[c.selLayer];
        if !Equals(L.id, NMPhotos.LayerId()) || !L.IsAlive(c.selItem) {
            return null;
        }
        return this.Photos().SpotOf(c.selItem);
    }

    private func TeleportLabel() -> String {
        return this.SelectedPhoto() != null ? "TELEPORT" : "FAST TRAVEL";
    }

    // Teleports V on foot to the selected photo's spot; closes the map. Refusals are logged and keep the map open.
    public func StartPhotoTeleport() -> Bool {
        let gi = this.GetGameInstance();
        let player = GetPlayer(gi);
        let spot = this.SelectedPhoto();
        let why = NMPhotoTeleport.Refusal(spot != null, IsDefined(player) && IsDefined(GetMountedVehicle(player)), IsDefined(player));
        if StrLen(why) > 0 {
            NMLog.Info("photo|teleport|refused|" + why);
            return false;
        }
        NMLog.Info("photo|teleport|start|" + ToString(spot.hash));
        this.Close();
        NMPhotoTeleport.Go(gi, player, spot);
        return true;
    }

    // The game mappin behind the crosshair's selected item, when it is a mirrored vanilla marker; else null.
    private func SelectedMappin() -> ref<IMappin> {
        let c = this.crosshair;
        if c.selKind != 0 || c.selLayer < 0 || c.selLayer >= ArraySize(this.api.layers) {
            return null;
        }
        let L = this.api.layers[c.selLayer];
        let vl = L.listener as NMVanillaListener;
        if !IsDefined(vl) || !L.IsAlive(c.selItem) {
            return null;
        }
        return this.vanilla.Resolve(vl.Get(c.selItem));
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
        if IsDefined(this.hud) {
            this.hud.Restore();
            this.hud = null;
        }
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
        let panning = pan.X != 0.0 || pan.Y != 0.0;
        let c = this.crosshair;
        if NMInput.SnapOnRelease(this.wasPanning, panning, IsDefined(c) && c.selKind >= 0) {
            let w = this.camera.MapToWorld(c.selX, c.selY);
            this.camera.follow = false;
            this.camera.EaseTo(w.X, w.Y, this.camera.mpp, NMTheme.SnapMs());
        }
        this.wasPanning = panning;
        if panning {
            this.holdMs += dt;
            let accel = this.holdMs > 500.0 ? MinF(1.0 + (this.holdMs - 500.0) / 1000.0, 3.0) : 1.0;
            let step = 1500.0 * accel * dt / 1000.0;
            this.camera.PanPixels(pan.X * step, pan.Y * step);
        } else {
            this.holdMs = 0.0;
        }
        if this.input.zoomIn {
            this.camera.ZoomBy(PowF(NMTheme.ZoomRatePerSecond(), dt / 1000.0));
        }
        if this.input.zoomOut {
            this.camera.ZoomBy(1.0 / PowF(NMTheme.ZoomRatePerSecond(), dt / 1000.0));
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
        this.Photos().OnMapOpened();
        this.tipApiRev = -1;
        this.scaleRev = -1;
        this.hdrSubtitle = "\n";   // sentinels no real text equals: force the first header write
        this.hdrQuestTitle = "\n";
        this.hdrQuestObjective = "\n";
        this.hdrHint = "\n";
        this.hdrScaleLabel = "\n";
        this.hdrQuestState = -1;
        this.hdrQuestIsQuest = false;
        this.cacheTotal = -1;
        this.imageRetries = 0;
        this.imageRev = this.api.revision;
        this.layerEpoch = this.api.layerEpoch;
        let l = this.panel.layout;
        this.layers = NMLayerStack.Create(this.panel.tiles, this.holoTheme, this.holoEffects);
        this.renderer = NMItemRenderer.Create(this.api, this.panel.items, l.scale);
        this.renderer.SetHalo(this.holoEffects);
        this.renderer.SetShotHandler(this.Photos().Handler());
        this.Photos().SyncLayer(this.api, this.PhotosVisible());
        this.marker = NMPlayerMarker.Create(this.panel.overlay, l.scale);
        this.crosshair = NMCrosshair.Create();
        // The sidebar is always visible; marker details dock in it. The focus point is the middle of the map left of it.
        this.reticle = NMReticle.Create(this.panel.overlay, l.scale, this.holoTheme);   // under the sidebar
        this.drawer = NMPhotoDrawer.Create(this.panel.overlay, l, this.holoTheme);
        this.tooltip = NMTooltip.CreateDocked(this.drawer.Root(), 40.0 * l.scale, 40.0 * l.scale, l.sideW - 80.0 * l.scale, l.scale);
        this.drawerShift = NMPhotoDrawer.FocusShift(l);
        this.camera.SetScreenShift(this.drawerShift);
        this.UpdateHeader();
        this.vanilla.ApplyFilters(this.filterView, this.Settings());
        this.vanilla.Tick(NMClock.NowMs(), true);
        this.Gps().BeginOpen();
        this.routes = NMRouteLayer.Create(this.panel.routes, l.scale, this.holoEffects);
        this.lastRouteReadMs = 0.0;
        if this.RoutesWanted() {
            this.ReadRoutes();   // routes on the first frame, not 500 ms later
        }
    }

    // Photo pins show in the ALL filter view only, unless switched off in Mod Settings.
    private func PhotosVisible() -> Bool {
        let s = this.Settings();
        return this.filterView == 0 && (!IsDefined(s) || s.showPhotos);
    }

    private func RoutesWanted() -> Bool {
        let s = this.Settings();
        return !this.routesOff && (!IsDefined(s) || s.showRoutes);
    }

    // The minimap's routes in world space, coloured by the tracked quest's type (Quest yellow / Gigs teal).
    private func ReadRoutes() {
        let gi = this.GetGameInstance();
        let r = this.Gps().Read(GetPlayer(gi));
        let hdr = NMQuestHeader.Read(gi);
        let color = IsDefined(hdr) && !hdr.isQuest ? NMTheme.VanillaStateColor(n"Gigs") : NMTheme.VanillaStateColor(n"Quest");
        if !this.routes.HasStyle() {
            let st = this.Gps().PathStyle();
            if IsDefined(st) {
                NMLog.Info("gps|style|" + st.Describe());
                this.routes.SetStyle(st);
            }
        }
        this.routes.SetRoutes(r.quest, color, r.tracked);
        this.lastRouteReadMs = NMClock.NowMs();
    }

    private func OnClosing() {
        if IsDefined(this.perf) && this.perf.running {
            NMDebugLayer.Remove(this.api);
        }
        // Perf suite may have vanilla markers off; never leave them disabled. Flag only, no poll while closed.
        this.vanilla.MarkEnabled();
        this.ClearPerfOverrides();
        let h = this.Photos().Handler();
        if IsDefined(h) {
            h.CancelGameScreenshotRequests();   // pending thumbnail and drawer loads
        }
        this.perf = null;
        this.perfHidden = false;
        this.layers = null;
        this.renderer = null;
        this.marker = null;
        this.crosshair = null;
        this.tooltip = null;
        this.drawer = null;
        this.reticle = null;
        this.drawerShift = 0.0;
        this.routes = null;
    }

    private func UpdateModules(dt: Float) {
        // First: a started fast travel closes the map, and nothing below may run on the destroyed panel.
        if this.input.teleport {
            this.input.teleport = false;
            if this.SelectedPhoto() != null {
                if this.StartPhotoTeleport() {
                    return;
                }
            } else if this.StartFastTravel() {
                return;
            }
        }
        let l = this.panel.layout;
        this.vanilla.Tick(NMClock.NowMs(), false);
        if IsDefined(this.layers) {
            this.layers.Update(this.camera, dt);
        }
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
            this.tipApiRev = -1;
        }
        this.UpdateRoutes(dt);
        if this.Photos().Revision() != this.Photos().SyncedRevision() {
            this.Photos().SyncLayer(this.api, this.PhotosVisible());
        }
        let relaid = this.renderer.Update(this.camera, l.mapW, l.mapH);
        if relaid {
            let changed = this.crosshair.Update(this.renderer, l.mapW, l.mapH, l.scale, this.drawerShift);
            // Re-query tooltip content only when the selection or the data changed, not on every pan frame.
            if changed || this.api.revision != this.tipApiRev || this.ClusterStale() {
                this.tipApiRev = this.api.revision;
                this.RefreshTooltip(changed);
            }
            // The camera moved (relayout): selX/selY changed, so follow the marker. No-op while hidden.
            this.tooltip.Reposition(this.crosshair.selX, this.crosshair.selY);
        }
        this.renderer.ApplySelection(this.crosshair.sel, this.crosshair.selKind, dt);
        let c = this.crosshair;
        let isPhoto = c.selKind == 0 && c.selLayer >= 0 && c.selLayer < ArraySize(this.api.layers)
            && Equals(this.api.layers[c.selLayer].id, NMPhotos.LayerId());
        this.reticle.Update(l.mapW * 0.5 - this.drawerShift, l.mapH * 0.5, c.selKind >= 0, c.selX, c.selY, isPhoto,
            NMItemRenderer.ThumbZoom(this.camera.mpp), dt);
        if this.input.act {
            this.input.act = false;
            this.Activate();
            this.tipApiRev = -1;      // refresh the tooltip next frame (tracked state, action label), spec 7
            this.renderer.Invalidate();
            this.UpdateHeader();
        }
        if this.input.filter {
            this.input.filter = false;
            this.filterView = (this.filterView + 1) % NMVanillaFilters.ViewCount();
            this.vanilla.ApplyFilters(this.filterView, this.Settings());
            this.Photos().SyncLayer(this.api, this.PhotosVisible());
            this.UpdateHeader();
        }
        this.marker.Update(this.camera, GetPlayer(this.GetGameInstance()), l.mapW, l.mapH);
        if this.camera.revision != this.scaleRev {
            this.UpdateScale();
        }
        if this.frameNo % 30 == 0 {
            this.UpdateHeader();
            if IsDefined(this.hud) { this.hud.Refresh(); }
        }
    }

    // Read every 500 ms; trim, project and flow every frame. Hidden (and no reads) when the setting is off.
    private func UpdateRoutes(dt: Float) {
        let player = GetPlayer(this.GetGameInstance());
        if !this.RoutesWanted() || !IsDefined(player) {
            this.routes.SetVisible(false);
            return;
        }
        this.routes.SetVisible(true);
        if NMClock.NowMs() - this.lastRouteReadMs >= 500.0 {
            this.ReadRoutes();
        }
        let l = this.panel.layout;
        let p = player.GetWorldPosition();
        this.routes.Update(this.camera, p.X, p.Y, dt, l.mapW, l.mapH);
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

    private func RefreshTooltip(changed: Bool) {
        this.RefreshSidebar(changed);
        this.drawer.SetEmpty(!this.tooltip.IsShown() && !this.drawer.IsShown());
    }

    private func RefreshSidebar(changed: Bool) {
        let c = this.crosshair;
        if changed {
            this.UpdateHeader();   // the hint's teleport label follows the selection
        }
        if c.selKind == 0 && c.selLayer >= 0 && c.selLayer < ArraySize(this.api.layers) {
            let L = this.api.layers[c.selLayer];
            if !L.IsAlive(c.selItem) {
                this.tooltip.Hide();
                this.drawer.Hide();
                return;
            }
            if Equals(L.id, NMPhotos.LayerId()) {
                let spot = this.Photos().SpotOf(c.selItem);
                if IsDefined(spot) {
                    this.ShowDrawer(spot);
                    return;
                }
            }
            this.drawer.Hide();
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
            this.tooltip.ShowDetails(d, d.hasColor ? d.color : this.api.catColor[L.catGlobal[L.cat[c.selItem]]]);
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
            this.tooltip.ShowCluster(this.renderer.clTotal[slot], IsDefined(s) ? NMInput.KeyName(s.keyAct) : "ACT");
            this.drawer.Hide();
        } else {
            this.tooltip.Hide();
            this.drawer.Hide();
        }
    }

    private func ShowDrawer(spot: ref<NMPhotoSpot>) {
        this.tooltip.Hide();
        let dist = "";
        let player = GetPlayer(this.GetGameInstance());
        if IsDefined(player) {
            let p = player.GetWorldPosition();
            let dx = spot.x - p.X;
            let dy = spot.y - p.Y;
            dist = NMMath.FormatMeters(SqrtF(dx * dx + dy * dy));
        }
        let s = this.Settings();
        this.drawer.Show(spot, dist, spot.district, IsDefined(s) ? NMInput.KeyName(s.keyTeleport) : "TELEPORT", this.Photos().Handler());
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
        let label = NMMath.FormatMeters(len);
        if NotEquals(label, this.hdrScaleLabel) {
            this.panel.scaleLabel.SetText(label);
            this.hdrScaleLabel = label;
        }
    }

    private func UpdateHeader() {
        let s = this.Settings();
        let district = this.DistrictName();
        let subtitle = this.filterView == 0 ? district : district + "   ·   " + NMVanillaFilters.ViewName(this.filterView);
        if NotEquals(subtitle, this.hdrSubtitle) {
            this.panel.subtitle.SetText(subtitle);
            this.hdrSubtitle = subtitle;
        }
        let q = NMQuestHeader.Read(this.GetGameInstance());
        let qState = q.visible ? 1 : 0;
        if qState != this.hdrQuestState {
            this.panel.questTitle.SetVisible(q.visible);
            this.hdrQuestState = qState;
            this.hdrQuestObjective = "\n";   // visibility of the objective follows its text: re-evaluate below
        }
        if q.visible {
            let title = StrUpper(q.title);
            let titleChanged = NotEquals(title, this.hdrQuestTitle);
            if titleChanged {
                this.panel.questTitle.SetText(title);
                this.hdrQuestTitle = title;
            }
            if titleChanged || NotEquals(q.isQuest, this.hdrQuestIsQuest) {
                this.panel.questTitle.SetTintColor(NMTheme.VanillaStateColor(q.isQuest ? n"Quest" : n"Gigs"));
                this.hdrQuestIsQuest = q.isQuest;
            }
        }
        let objective = q.visible ? NMQuestHeader.Clip(q.objective, 130) : "";
        if NotEquals(objective, this.hdrQuestObjective) {
            this.panel.questObjective.SetVisible(StrLen(objective) > 0);
            if StrLen(objective) > 0 { this.panel.questObjective.SetText(objective); }
            this.hdrQuestObjective = objective;
        }
        this.UpdateScale();
        if IsDefined(s) {
            let hint = NMInput.HintText(s, NMVanillaFilters.ViewName(this.filterView), this.TeleportLabel());
            if this.input.arrowSeen {
                hint += "   ·   ARROW KEYS IGNORED - TURN NUMLOCK ON";
            }
            if NotEquals(hint, this.hdrHint) {
                this.panel.hints.SetText(hint);
                this.hdrHint = hint;
            }
        }
    }

    public func DistrictName() -> String {
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
