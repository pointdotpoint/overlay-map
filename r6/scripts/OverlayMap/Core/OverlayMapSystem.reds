module OverlayMap

public class OverlayMapFrame extends DelayCallback {
    public let system: wref<OverlayMapSystem>;

    public func Call() {
        if IsDefined(this.system) {
            this.system.Tick();
        }
    }
}

// Owns the overlay. Zero work while closed: only the Input/Key callback stays registered.
// Polls the View hold while it is down (the frame loop only runs while the map is open).
public class OverlayMapPadPoll extends DelayCallback {
    public let system: wref<OverlayMapSystem>;

    public func Call() {
        if IsDefined(this.system) {
            this.system.PadPoll();
        }
    }
}

public class OverlayMapPadPauseCheck extends DelayCallback {
    public let system: wref<OverlayMapSystem>;

    public func Call() {
        if IsDefined(this.system) {
            this.system.PadPauseCheck();
        }
    }
}

// Corner minimap housekeeping, once a second while a player is attached: create / rebuild / remove the corner from the
// settings, and re-fade the vanilla minimap. Reads a few settings when the option is off; no frame loop.
public class OverlayMapCornerPoll extends DelayCallback {
    public let system: wref<OverlayMapSystem>;
    public let gen: Int32;

    public func Call() {
        if IsDefined(this.system) {
            this.system.CornerPoll(this.gen);
        }
    }
}

// Gives the game its actions back after the map closed, once the closing button's release has gone by.
public class OverlayMapPadRelease extends DelayCallback {
    public let system: wref<OverlayMapSystem>;
    public let token: Int32;

    public func Call() {
        if IsDefined(this.system) {
            this.system.PadReleaseCtx(this.token);
        }
    }
}

public class OverlayMapSystem extends ScriptableSystem {
    private let api: ref<OverlayMap>;
    private let input: ref<NMInput>;
    private let pad: ref<NMPad>;
    private let padFromPad: Bool;     // the open map was opened with the pad
    private let padOwned: Bool;       // the map holds the pad: the game's actions are held off
    private let padCtx: Bool;         // UIGameContext.ModalPopup pushed by OverlayMap
    private let padCtxToken: Int32;   // invalidates a scheduled release when the map takes the pad again
    private let padReleaseWait: Bool; // closed by a pad button: release the context after that button's release
    private let padPolling: Bool;
    private let padPauseSuppressed: Bool;   // the game's pause menu was held back for this View press
    private let padPauses: Int32;           // pause menus OverlayMap opened for a View tap (harness counter)
    private let padListener: wref<GameObject>;
    private let isOpen: Bool;
    private let loopAlive: Bool;
    private let panel: ref<NMPanel>;
    private let camera: ref<NMCamera>;
    private let lastMs: Float;
    private let holdMs: Float;
    private let teleport: ref<NMTeleportDriver>;
    private let teleportLastMs: Float;
    private let savedMpp: Float = 0.0;   // 0 = not opened yet this session: start fully zoomed in
    private let frameNo: Int32;
    private let layers: ref<NMLayerStack>;
    private let holoTheme: Int32;      // NMTheme.ThemeIndex(OverlayMapSettings.holoColor), read once per open
    private let holoEffects: Bool;     // OverlayMapSettings.hologramEffects, read once per open
    private let holoFx: ref<NMHoloFx>; // the VHS knobs (scanlines, glow, tracking band, glitch), read once per open
    private let renderer: ref<NMItemRenderer>;
    private let crosshair: ref<NMCrosshair>;
    private let tooltip: ref<NMTooltip>;
    private let drawer: ref<NMPhotoDrawer>;
    private let reticle: ref<NMReticle>;
    private let wasPanning: Bool;
    private let drawerShift: Float;   // px the focus point sits left of the map-area centre (middle of the map left of the sidebar)
    private let marker: ref<NMPlayerMarker>;
    private let tipApiRev: Int32;
    private let areas: ref<NMAreaIndex>;   // named areas under the focus, loaded on first use
    private let areaAt: Int32;             // the area the sidebar card shows, -1 none
    private let scaleRev: Int32;
    private let perf: ref<NMPerfSuite>;
    private let perfHidden: Bool;
    public let perfTileMs: Float;   // this frame's tile layers and item relayout, timed only while the perf suite runs
    public let perfItemMs: Float;
    public let perfRouteMs: Float;   // UpdateRoutes, likewise
    private let versionLogged: Bool;
    private let layerEpoch: Int32;
    private let imageRetries: Int32;
    private let imageRev: Int32;
    private let vanilla: ref<NMVanilla>;
    private let gps: ref<NMGps>;
    private let waypoint: ref<NMWaypoint>;
    private let routes: ref<NMRouteLayer>;
    private let routesOff: Bool;          // perf suite override (SetRoutesEnabled)
    private let photos: ref<NMPhotos>;
    private let collect: ref<NMCollect>;
    // Collectible item records V has had, saved with the game (an iconic sold later still counts as collected).
    private persistent let collectSeen: array<TweakDBID>;
    // Corner minimap (OverlayMapSettings.replaceMinimap). The zoom is saved with the game.
    private persistent let cornerMpp: Float;
    private let cornerHost: ref<NMCornerHost>;
    private let cornerPollGen: Int32;
    private let cornerRouteMs: Float;
    private let cornerDistrict: String;
    private let palette: ref<NMHudPalette>;
    private let mirror: ref<NMMinimapMirror>;
    private let cornerPerf: ref<NMCornerPerf>;   // Debug on: RESULT|corner lines while the corner runs
    public let lastCornerPerf: String;            // the last RESULT|corner line (harness)
    public let cornerMsVanilla: Float;            // this corner frame's vanilla poll and mirror draw (profiling)
    public let cornerMsMirror: Float;
    private let panelMirror: ref<NMShapeLayer>;   // vanilla minimap markers, fed by Minimap/Wraps.reds while a view is live   // set while "Follow HUD Painter colours" is on
    private let cornerObjectiveM: Float;   // -1 = nothing tracked (set in PrepareCornerMarkers)
    private let collectSeenMap: ref<inkHashMap>;
    private let hud: ref<NMHudHider>;     // set while the map is open with "Hide HUD while open" on
    private let lastRouteReadMs: Float;
    private let filterView: Int32;
    // Header change-cache: SetText / tint only when the value changed (reset in OnOpened).
    private let hdrDistrict: String;
    private let hdrFilter: String;
    private let hdrQuestState: Int32;   // -1 unknown, 0 hidden, 1 shown
    private let hdrQuestTitle: String;
    private let hdrQuestObjective: String;
    private let hdrQuestIsQuest: Bool;
    private let hdrScaleLabel: String;

    private func OnAttach() {
        this.api = OverlayMap.Create();
        if NMTileManifest.Available() {
            this.api.SetWorld(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        }
        this.vanilla = NMVanilla.Create(this.api, this.GetGameInstance());
        this.collect = new NMCollect();
        this.input = new NMInput();
        this.pad = new NMPad();
        this.cornerHost = new NMCornerHost();
        this.mirror = NMMinimapMirror.Create();
        GameInstance.GetCallbackSystem().RegisterCallback(n"Input/Key", this, n"OnKeyInput");
        GameInstance.GetCallbackSystem().RegisterCallback(n"Input/Axis", this, n"OnAxisInput");
        NMLog.Info("loaded (tiles " + (NMTileManifest.Available() ? "present" : "missing") + ", precise clock " + ToString(NMClock.Precise()) + ")");
    }

    // The save's seen list has just been read: drop a set built before it.
    private func OnRestored(saveVersion: Int32, gameVersion: Int32) {
        this.collectSeenMap = null;
    }

    // Loading a save or quitting to menu ends the session: tear the overlay down so nothing is orphaned.
    private func OnDetach() {
        GameInstance.GetCallbackSystem().UnregisterCallback(n"Input/Key", this);
        GameInstance.GetCallbackSystem().UnregisterCallback(n"Input/Axis", this);
        this.Close();
        this.cornerPollGen += 1;
        this.cornerHost.Detach();
        if IsDefined(this.palette) {
            this.palette.Destroy();
            this.palette = null;
        }
        this.PadReleaseCtx(this.padCtxToken);
    }

    public static func Get(gi: GameInstance) -> ref<OverlayMapSystem> {
        return GameInstance.GetScriptableSystemsContainer(gi).Get(n"OverlayMap.OverlayMapSystem") as OverlayMapSystem;
    }

    public func Api() -> ref<OverlayMap> { return this.api; }
    public func Vanilla() -> ref<NMVanilla> { return this.vanilla; }

    // Created on first use: the minimap may attach before this system's OnAttach.
    // Created on first use: photo mode and the minimap may call in before this system's OnAttach.
    public func Photos() -> ref<NMPhotos> {
        if !IsDefined(this.photos) { this.photos = new NMPhotos(); }
        return this.photos;
    }
    public func Collect() -> ref<NMCollect> {
        if !IsDefined(this.collect) { this.collect = new NMCollect(); }
        return this.collect;
    }

    // The seen list as a set, built on first use: the persistent array is only restored after OnAttach.
    public func CollectSeen() -> ref<inkHashMap> {
        if !IsDefined(this.collectSeenMap) {
            this.collectSeenMap = new inkHashMap();
            for id in this.collectSeen {
                let h = TDBID.ToNumber(id);
                if !this.collectSeenMap.KeyExist(h) { this.collectSeenMap.Insert(h, this); }
            }
        }
        return this.collectSeenMap;
    }

    // An item reached V's inventory: remember it if a collectible pin stands for it.
    public func NoteItem(id: TweakDBID) {
        if !TDBID.IsValid(id) || !this.Collect().Tracks(id) { return; }
        let h = TDBID.ToNumber(id);
        let seen = this.CollectSeen();
        if seen.KeyExist(h) { return; }
        seen.Insert(h, this);
        ArrayPush(this.collectSeen, id);
        NMLog.Info("collect|seen|" + TDBID.ToStringDEBUG(id));
    }

    // Everything V carries now (covers items picked up before this version, if still carried).
    private func NoteInventory() {
        let player = GetPlayer(this.GetGameInstance());
        let ts = GameInstance.GetTransactionSystem(this.GetGameInstance());
        if !IsDefined(player) || !IsDefined(ts) { return; }
        let list: array<wref<gameItemData>>;
        ts.GetItemList(player, list);
        for d in list {
            if IsDefined(d) { this.NoteItem(ItemID.GetTDBID(d.GetID())); }
        }
    }

    private func SyncCollect() {
        let s = this.Settings();
        this.Collect().Sync(this.api, this.filterView, s);
    }

    public func Waypoint() -> ref<NMWaypoint> {
        if !IsDefined(this.waypoint) { this.waypoint = NMWaypoint.Create(this.GetGameInstance()); }
        return this.waypoint;
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

    private func Settings() -> ref<OverlayMapSettings> {
        return OverlayMapSettings.Get(this.GetGameInstance());
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
        this.HandleKey(evt.GetKey(), evt.GetAction(), evt.IsShiftDown(), evt.IsControlDown(), evt.IsAltDown());
    }

    // One key event, from the game's Input/Key callback (or the soak harness, which can't send real keys on a desktop).
    public func HandleKey(key: EInputKey, action: EInputAction, shift: Bool, ctrl: Bool, alt: Bool) -> Bool {
        let s = this.Settings();
        if !IsDefined(s) {
            return false;
        }
        if NMPad.IsPad(key) && (Equals(s.padOpen, OverlayMapPadOpen.HoldView) || this.padOwned || this.padCtx) {
            this.OnPadButton(s, key, action);
            return true;
        }
        let used = this.input.Handle(s, key, action, shift, ctrl, alt, this.isOpen);
        if used && this.isOpen {
            this.pad.lastWasPad = false;
        }
        if this.input.toggle {
            this.input.toggle = false;
            if this.isOpen {
                this.Close();
            } else {
                this.Open();
            }
        }
        this.HandleDebug(s);
        return used;
    }

    // View is also the game's pause button, and the pause menu opens on its release. On the press, hold that release
    // back (as the game's own phone and radio popups do); a tap then opens the pause menu here, a hold opens the map,
    // and closing the map with View doesn't pause. Escape is untouched: only a press while View is down counts.
    private func OnPlayerAttach(request: ref<PlayerAttachRequest>) {
        let player = request.owner;
        if IsDefined(player) && player.IsPlayer() {
            if IsDefined(this.padListener) {
                this.padListener.UnregisterInputListener(this, n"OpenPauseMenu");
            }
            player.RegisterInputListener(this, n"OpenPauseMenu");
            this.padListener = player;
            this.cornerPollGen += 1;
            this.ScheduleCornerPoll(1.0);
        }
    }

    private func OnPlayerDetach(request: ref<PlayerDetachRequest>) {
        if IsDefined(this.padListener) {
            this.padListener.UnregisterInputListener(this, n"OpenPauseMenu");
            this.padListener = null;
        }
    }

    // The action can arrive before or after the raw View press, so the pad is also recognised by the game's own
    // last-used-device flag. If no View press shows up after all, the pause menu opens anyway (PadPauseCheck).
    protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
        if ListenerAction.IsAction(action, n"OpenPauseMenu") && Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_PRESSED)
            && IsDefined(this.pad) && (this.pad.IsHeld(EInputKey.IK_Pad_Back_Select) || (IsDefined(this.padListener) && this.padListener.PlayerLastUsedPad())) {
            let s = this.Settings();
            if IsDefined(s) && Equals(s.padOpen, OverlayMapPadOpen.HoldView) {
                ListenerActionConsumer.DontSendReleaseEvent(consumer);
                this.padPauseSuppressed = true;
                let cb = new OverlayMapPadPauseCheck();
                cb.system = this;
                GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.3, false);
            }
        }
        return false;
    }

    // The pause menu was held back but View is not down: it wasn't a View press after all, so open it now.
    public func PadPauseCheck() {
        if this.padPauseSuppressed && !this.pad.IsHeld(EInputKey.IK_Pad_Back_Select) {
            this.padPauseSuppressed = false;
            this.OpenPauseMenu();
        }
    }

    private func OpenPauseMenu() {
        let e = new inkMenuInstance_SpawnEvent();
        e.Init(n"OnOpenPauseMenu");
        GameInstance.GetUISystem(this.GetGameInstance()).QueueEvent(e);
        this.padPauses += 1;
    }

    // Sticks and triggers. Mouse axes arrive here every frame too: the pad check comes first and costs an int compare.
    private cb func OnAxisInput(evt: ref<AxisInputEvent>) {
        let key = evt.GetKey();
        if NMPad.IsPad(key) {
            this.pad.Axis(key, evt.GetValue());
        }
    }

    private func OnPadButton(s: ref<OverlayMapSettings>, key: EInputKey, action: EInputAction) {
        this.pad.Button(key, action, NMClock.NowMs(), this.isOpen, this.padFromPad, this.padOwned, s.holdToShow, true);
        if Equals(key, EInputKey.IK_Pad_Back_Select) && Equals(action, EInputAction.IACT_Release) {
            if this.pad.tap && this.padPauseSuppressed {
                this.OpenPauseMenu();
            }
            this.pad.tap = false;
            this.padPauseSuppressed = false;
        }
        if !this.isOpen && this.padReleaseWait && this.pad.HeldCount() == 0 {
            this.padReleaseWait = false;
            this.SchedulePadRelease(0.1);
        }
        if this.pad.close {
            this.pad.close = false;
            this.Close();
            return;
        }
        if this.pad.act { this.pad.act = false; this.input.act = true; }
        if this.pad.waypoint { this.pad.waypoint = false; this.input.waypoint = true; }
        if this.pad.teleport {
            this.pad.teleport = false;
            if s.teleportEnabled { this.input.teleport = true; }
        }
        if this.pad.filter { this.pad.filter = false; this.input.filter = true; }
        if this.pad.recenter { this.pad.recenter = false; this.input.recenter = true; }
        if this.pad.HoldPending() && !this.padPolling {
            this.padPolling = true;
            this.SchedulePadPoll();
        }
    }

    private func SchedulePadPoll() {
        let cb = new OverlayMapPadPoll();
        cb.system = this;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.05, false);
    }

    public func PadPoll() {
        this.padPolling = false;
        if this.pad.PollHold(NMClock.NowMs(), this.isOpen, this.padFromPad, this.padOwned) {
            if this.isOpen {
                this.Close();
            } else {
                this.OpenFromPad();
            }
            return;
        }
        if this.pad.HoldPending() {
            this.padPolling = true;
            this.SchedulePadPoll();
        }
    }

    // Opened by holding View. In a car with pass-through on, the map opens without taking the pad.
    private func OpenFromPad() {
        this.Open();
        if !this.isOpen {
            return;
        }
        this.padFromPad = true;
        this.pad.lastWasPad = true;
        this.pad.ClearAxes();
        let player = GetPlayer(this.GetGameInstance());
        let inCar = IsDefined(player) && IsDefined(GetMountedVehicle(player));
        if !(inCar && NMPad.CarPassThrough()) {
            this.padOwned = true;
            this.padCtxToken += 1;
            if !this.padCtx {
                this.padCtx = true;
                GameInstance.GetUISystem(this.GetGameInstance()).PushGameContext(UIGameContext.ModalPopup);
                this.SetPlayerUiContext(true);
            }
        }
    }

    private func SchedulePadRelease(seconds: Float) {
        let cb = new OverlayMapPadRelease();
        cb.system = this;
        cb.token = this.padCtxToken;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, seconds, false);
    }

    public func PadReleaseCtx(token: Int32) {
        if !this.padCtx || token != this.padCtxToken || this.padOwned {
            return;
        }
        this.padCtx = false;
        this.padReleaseWait = false;
        this.pad.ClearHeld();
        GameInstance.GetUISystem(this.GetGameInstance()).PopGameContext(UIGameContext.ModalPopup);
        this.SetPlayerUiContext(false);
    }

    // The player state machine's UI input context, as the game's non-pausing tutorial popups use it: V doesn't walk,
    // look, jump or fight while it is on, and the game keeps running. (The modal popup context alone left V walking.)
    private func SetPlayerUiContext(on: Bool) {
        let player = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return;
        }
        let e = new PSMPostponedParameterBool();
        e.id = on ? n"OnUIContextActive" : n"OnUIContextInactive";
        e.value = true;
        player.QueueEvent(e);
    }

    // Debug chords: self-test, debug layer, perf suite, calibration dump.
    private func HandleDebug(s: ref<OverlayMapSettings>) {
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
        if IsDefined(s) {
            s.panelOpacity = NMTheme.MigratePanelOpacity(s.panelOpacity);   // a saved old default moves to the new one
        }
        let layout = NMPanelLayout.Compute(size.X, size.Y, IsDefined(s) ? s.expandedScale : 1.0);
        let cornerZoom = this.cornerHost.Expanding();
        this.holoTheme = IsDefined(s) ? NMTheme.ThemeIndex(s.holoColor) : 0;
        this.holoEffects = IsDefined(s) ? s.hologramEffects : true;
        this.holoFx = NMHoloFx.From(s);
        this.panel = NMPanel.Build(window, layout, IsDefined(s) ? s.panelOpacity : NMTheme.DefaultPanelOpacity(), this.holoTheme, this.holoEffects, this.holoFx);
        if !IsDefined(s) || s.hideHud {
            this.hud = NMHudHider.Hide(window, this.panel.root);
        }
        let bounds = NMRect.Create(NMTileManifest.WorldMinX(), NMTileManifest.WorldMinY(), NMTileManifest.WorldMaxX(), NMTileManifest.WorldMaxY());
        this.camera = NMCamera.Create(layout.mapW, layout.mapH, bounds, OverlayMapSystem.MinMpp(), OverlayMapSystem.MaxMpp());
        if this.cornerHost.Active() && cornerZoom > 0.0 {
            this.camera.SetMpp(cornerZoom);
        } else {
            this.camera.SetMpp(this.savedMpp > 0.0 ? this.savedMpp : OverlayMapSystem.OpenMpp());
        }
        this.CenterOnPlayer(true);
        if IsDefined(s) {
            this.panel.hintBar.Set(NMInput.Hints(s, NMVanillaFilters.ViewName(this.filterView), "FAST TRAVEL"));
        }
        this.isOpen = true;
        this.input.ResetHeld();
        this.OnOpened();
        this.UpdateWarning();
        this.EnsureLoop();
        NMLog.Info("open " + FloatToStringPrec(size.X, 0) + "x" + FloatToStringPrec(size.Y, 0)
            + " opacity=" + FloatToStringPrec(IsDefined(s) ? s.panelOpacity : NMTheme.DefaultPanelOpacity(), 2));
    }

    // Tile problems (non-blocking): missing manifest, manifest present but archive not loaded, tiles built for another game version.
    private func UpdateWarning() {
        let text = "";
        if !NMTileManifest.Available() {
            text = "TILE ARCHIVE MISSING - run tools/tiles build";
        } else if IsDefined(this.layers) && !this.layers.available {
            text = "Map tiles not found: install OverlayMap.archive";
        }
        let built = NMTileManifest.SourceGameVersion();
        let handler = GameInstance.GetSystemRequestsHandler();
        if IsDefined(handler) && NotEquals(built, "") {
            let running = handler.GetGameVersion();
            let a = OverlayMapSystem.Normalise(built);
            let b = OverlayMapSystem.Normalise(running);
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
        return IsDefined(NMFastTravel.PointOf(this.SelectedMappin())) ? "FAST TRAVEL" : "TELEPORT";
    }

    // Teleports to the selected marker or, with none, the map centre; closes the map. V's vehicle comes along.
    public func StartTeleport() -> Bool {
        if IsDefined(this.teleport) {
            NMLog.Info("teleport|refused|busy");
            return false;
        }
        let gi = this.GetGameInstance();
        let player = GetPlayer(gi);
        if !IsDefined(player) || !IsDefined(this.camera) || !IsDefined(this.crosshair) {
            NMLog.Info("teleport|refused|no player");
            return false;
        }
        let vehicle: ref<VehicleObject> = GetMountedVehicle(player);
        let inVehicle = IsDefined(vehicle);
        let c = this.crosshair;
        let kind = -1;
        let layerId = n"";
        let marker = new Vector4(0.0, 0.0, 0.0, 1.0);
        if c.selKind == 0 && c.selLayer >= 0 && c.selLayer < ArraySize(this.api.layers) && this.api.layers[c.selLayer].IsAlive(c.selItem) {
            let L = this.api.layers[c.selLayer];
            kind = 0;
            layerId = L.id;
            marker = L.Position(c.selItem);
        }
        let t = NMTeleport.Choose(kind, layerId, marker, this.camera.cx, this.camera.cy, inVehicle);
        if !NMTeleport.InBounds(t.x, t.y) {
            NMLog.Info("teleport|refused|outside map");
            return false;
        }
        NMLog.Info("teleport|start|" + FloatToStringPrec(t.x, 1) + "," + FloatToStringPrec(t.y, 1) + "|exact=" + ToString(t.exact)
            + "|vehicle=" + ToString(inVehicle));
        let obj: ref<GameObject> = inVehicle ? vehicle : player;
        this.teleport = NMTeleportDriver.Create(t, NMGameMover.Create(obj), NMWorldGround.Create(gi), inVehicle);
        this.Close();
        this.teleportLastMs = NMClock.NowMs();
        this.ScheduleTeleport();
        return true;
    }

    public func TeleportTick() {
        if !IsDefined(this.teleport) {
            return;
        }
        let now = NMClock.NowMs();
        let dt = ClampF(now - this.teleportLastMs, 0.0, 100.0);
        this.teleportLastMs = now;
        if this.teleport.Step(dt) == 1 {
            NMLog.Info("teleport|" + this.teleport.result);
            this.teleport = null;
            return;
        }
        this.ScheduleTeleport();
    }

    private func ScheduleTeleport() {
        let cb = new OverlayMapTeleportFrame();
        cb.system = this;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.0, false);
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
        // Every close path (key, pad, teleport, fast travel, teardown) hands the zoom back to the corner.
        if this.cornerHost.Active() {
            this.cornerHost.Collapsed(IsDefined(this.camera) ? this.camera.mpp : 0.0);
            this.cornerMpp = this.cornerHost.mpp;
            this.cornerRouteMs = 0.0;
        } else {
            this.cornerHost.Collapsed(0.0);
        }
        if IsDefined(this.input) {
            this.input.ResetHeld();
        }
        if IsDefined(this.pad) {
            this.pad.ClearAxes();
        }
        this.padFromPad = false;
        if this.padOwned {
            this.padOwned = false;
            // Pad buttons still down (B, View, X that closed it): wait for their release (OnPadButton), with a
            // fallback in case a release never arrives; else release shortly.
            this.padReleaseWait = this.pad.HeldCount() > 0;
            this.SchedulePadRelease(this.padReleaseWait ? 1.5 : 0.1);
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
        if this.cornerHost.Active() {
            this.EnsureLoop();
        }
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
        let cb = new OverlayMapFrame();
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
        if !this.isOpen && !this.cornerHost.Active() {
            this.loopAlive = false;
            this.mirror.live = false;
            return;
        }
        let now = NMClock.NowMs();
        let raw = now - this.lastMs;              // true frame time, recorded by the perf suite
        let dt = ClampF(raw, 0.0, 100.0);         // clamped step for camera motion
        this.lastMs = now;
        this.frameNo += 1;
        // Parity markers belong to the corner option: with it off the open map is exactly as before.
        let ms = this.Settings();
        this.mirror.live = NMCornerHost.Enabled(ms);
        if this.frameNo % 30 == 0 { this.mirror.Sweep(); }
        if !this.isOpen {
            let s = this.Settings();
            let c0 = NMClock.NowMs();
            this.CornerTick(dt);
            if IsDefined(s) && s.debug {
                if !IsDefined(this.cornerPerf) { this.cornerPerf = new NMCornerPerf(); }
                let cc = this.cornerHost.corner;
                if IsDefined(cc) {
                    this.cornerPerf.AddSplit(cc.msTiles, cc.msRoutes, cc.msItems, this.cornerMsVanilla, this.cornerMsMirror);
                }
                let line = this.cornerPerf.Add(raw, NMClock.NowMs() - c0, this.mirror.Count());
                if StrLen(line) > 0 {
                    NMLog.Info(line);
                    this.lastCornerPerf = line;
                }
            }
            this.Schedule();
            return;
        }
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
        if this.padOwned {
            let pp = this.pad.PanVector();
            pan = new Vector2(ClampF(pan.X + pp.X, -1.0, 1.0), ClampF(pan.Y + pp.Y, -1.0, 1.0));
        }
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
        let padZoom = this.padOwned ? this.pad.ZoomRate() : 0.0;
        if padZoom != 0.0 {
            this.camera.ZoomBy(PowF(NMTheme.ZoomRatePerSecond(), padZoom * dt / 1000.0));
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
        this.areaAt = -1;
        this.scaleRev = -1;
        this.hdrDistrict = "\n";   // sentinels no real text equals: force the first header write
        this.hdrFilter = "\n";
        this.hdrQuestTitle = "\n";
        this.hdrQuestObjective = "\n";
        this.hdrScaleLabel = "\n";
        this.hdrQuestState = -1;
        this.hdrQuestIsQuest = false;
        this.imageRetries = 0;
        this.imageRev = this.api.revision;
        this.layerEpoch = this.api.layerEpoch;
        let l = this.panel.layout;
        let ms = this.Settings();
        // The glow layer follows Glow strength, not Hologram effects: a plain map can still glow.
        this.layers = NMLayerStack.Create(this.panel.tiles, this.holoTheme, IsDefined(this.holoFx) && this.holoFx.WantsGlow(), IsDefined(ms) && ms.filterNcart);
        this.layers.SetGlow(this.holoFx);
        let markerSize = IsDefined(ms) ? ms.markerSize : 0.5;
        this.renderer = NMItemRenderer.Create(this.api, this.panel.items, NMTheme.MapMarkerScale(l.scale, markerSize));
        this.renderer.SetShotHandler(this.Photos().Handler());
        this.Photos().SyncLayer(this.api, this.PhotosVisible());
        let t0 = NMClock.NowMs();
        this.NoteInventory();
        this.Collect().Refresh(this.GetGameInstance(), this.CollectSeen());
        let t1 = NMClock.NowMs();
        if this.Collect().SyncWouldRebuild(this.filterView, this.Settings()) {
            this.SyncCollect();
            NMLog.Info("collect|built|" + IntToString(this.Collect().collectedN) + "/" + IntToString(ArraySize(this.Collect().spots))
                + " collected|refresh " + FloatToStringPrec(t1 - t0, 1) + " ms|build " + FloatToStringPrec(NMClock.NowMs() - t1, 1) + " ms");
        }
        this.marker = NMPlayerMarker.Create(this.panel.overlay, l.scale, this.holoEffects, this.holoTheme);
        this.crosshair = NMCrosshair.Create();
        // The sidebar is always visible; marker details dock in it. The focus point is the middle of the map left of it.
        this.reticle = NMReticle.Create(this.panel.overlay, l.scale, this.holoTheme);   // under the sidebar
        this.drawer = NMPhotoDrawer.Create(this.panel.sidebar, l, this.holoTheme);
        let pad = NMPanel.SidebarPad() * l.scale;
        this.tooltip = NMTooltip.CreateDocked(this.drawer.Root(), pad, pad, l.sideW - 2.0 * pad, l.scale, this.holoTheme);
        this.drawerShift = NMPhotoDrawer.FocusShift(l);
        this.camera.SetScreenShift(this.drawerShift);
        this.UpdateHeader();
        this.vanilla.ApplyFilters(this.filterView, this.Settings());
        this.vanilla.Tick(NMClock.NowMs(), true);
        this.Gps().BeginOpen();
        this.routes = NMRouteLayer.Create(this.panel.routes, l.scale, this.holoEffects);
        let ps = this.Settings();
        if NMCornerHost.Enabled(ps) {
            this.panelMirror = NMShapeLayer.Create(this.panel.shapes, ClampF(markerSize, 0.25, 1.5));
            this.panelMirror.SetRim(false, 40.0 * l.scale, l.scale);
        }
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
        this.panelMirror = null;
    }

    private func UpdateModules(dt: Float) {
        // First: a started teleport or fast travel closes the map, and nothing below may run on the destroyed panel.
        if this.input.teleport {
            this.input.teleport = false;
            if this.SelectedPhoto() != null {
                if this.StartPhotoTeleport() {
                    return;
                }
            } else if IsDefined(NMFastTravel.PointOf(this.SelectedMappin())) {
                if this.StartFastTravel() {
                    return;
                }
            } else if this.StartTeleport() {
                return;
            }
        }
        let l = this.panel.layout;
        this.vanilla.Tick(NMClock.NowMs(), false);
        let prof = IsDefined(this.perf) && this.perf.running;
        let tp = prof ? NMClock.NowMs() : 0.0;
        if IsDefined(this.layers) {
            this.layers.Update(this.camera, dt);
        }
        if prof { this.perfTileMs = NMClock.NowMs() - tp; }
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
        let rp = prof ? NMClock.NowMs() : 0.0;
        if IsDefined(this.routes) { this.routes.profile = prof; }
        this.UpdateRoutes(dt);
        if prof { this.perfRouteMs = NMClock.NowMs() - rp; }
        if IsDefined(this.panelMirror) { this.panelMirror.Update(this.camera, this.mirror, l.viewW, l.mapH, true, true, this.MiniScale(GetPlayer(this.GetGameInstance())), this.CameraYaw(), this.vanilla.diff); }
        if this.Photos().Revision() != this.Photos().SyncedRevision() {
            this.Photos().SyncLayer(this.api, this.PhotosVisible());
        }
        let ip = prof ? NMClock.NowMs() : 0.0;
        let relaid = this.renderer.UpdateFor(this.camera, l);
        if prof { this.perfItemMs = NMClock.NowMs() - ip; }
        if relaid {
            // mapW, not viewW: the focus is the map-area centre less the sidebar shift, i.e. the middle of the culled view
            // (NMCrosshair.FocusX, pick.focus_mid_view).
            let changed = this.crosshair.Update(this.renderer, l.mapW, l.mapH, l.scale, this.drawerShift);
            let a = this.AreaAtFocus();
            // Re-query tooltip content only when the selection, the area under the focus or the data changed,
            // not on every pan frame.
            if changed || a != this.areaAt || this.api.revision != this.tipApiRev {
                this.tipApiRev = this.api.revision;
                this.areaAt = a;
                this.RefreshSidebar(changed);
            }
            // The camera moved (relayout): selX/selY changed, so follow the marker. No-op while hidden.
            this.tooltip.Reposition(this.crosshair.selX, this.crosshair.selY);
        }
        this.renderer.ApplySelection(this.crosshair.sel, this.crosshair.selKind, dt);
        let c = this.crosshair;
        let isPhoto = c.selKind == 0 && c.selLayer >= 0 && c.selLayer < ArraySize(this.api.layers)
            && Equals(this.api.layers[c.selLayer].id, NMPhotos.LayerId());
        // A pin shrinks with its tier as the map zooms out; the reticle box follows the drawn picture or the slot's scale.
        let photoK = isPhoto ? NMTiers.Scale(this.api.layers[c.selLayer].EffectiveTier(), this.camera.mpp) : 1.0;
        let pinK = isPhoto ? 1.0 : this.renderer.CandScale(c.sel);
        this.reticle.Update(l.mapW * 0.5 - this.drawerShift, l.mapH * 0.5, c.selKind >= 0, c.selX, c.selY, isPhoto,
            NMItemRenderer.ThumbZoom(this.camera.mpp) * photoK, pinK, dt);
        if this.input.act {
            this.input.act = false;
            this.Activate();
            this.tipApiRev = -1;      // refresh the tooltip next frame (tracked state, action label), spec 7
            this.renderer.Invalidate();
            this.UpdateHeader();
        }
        if IsDefined(this.waypoint) && this.waypoint.Pending() { this.waypoint.TryPending(); }
        if this.input.waypoint {
            this.input.waypoint = false;
            this.DoWaypoint();
            this.tipApiRev = -1;
            this.renderer.Invalidate();
            this.UpdateHeader();
        }
        if this.input.filter {
            this.input.filter = false;
            this.filterView = (this.filterView + 1) % NMVanillaFilters.ViewCount();
            this.vanilla.ApplyFilters(this.filterView, this.Settings());
            this.Photos().SyncLayer(this.api, this.PhotosVisible());
            this.SyncCollect();
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
            let d: ref<OverlayMapDetails>;
            if IsDefined(L.listener) {
                if changed {
                    L.listener.OnSelected(c.selItem);
                }
                d = L.listener.GetDetails(c.selItem);
            }
            if !IsDefined(d) {
                d = this.DefaultDetails(L, c.selItem);
            }
            let id = c.selItem;
            let cat = this.api.catColor[L.catGlobal[L.cat[id]]];
            // The card's icon as the map draws it: on its plate in the icon colour, or a hex chip in the category colour.
            this.tooltip.ShowCard(d, d.hasColor ? d.color : cat, this.renderer.IconOf(L, id), L.hasTint[id] ? L.tint[id] : cat,
                L.pinStyle != 1);
        } else {
            this.drawer.Hide();
            // No marker: name the area under the focus (smallest first), or leave the sidebar empty.
            if this.areaAt >= 0 {
                this.tooltip.ShowDetails(OverlayMapDetails.Create(this.areas.Label(this.areaAt), this.areas.Title(this.areaAt))
                    .WithDescription(this.areas.Desc(this.areaAt)), NMTheme.Cyan());
            } else {
                this.tooltip.Hide();
            }
        }
    }

    private func AreaAtFocus() -> Int32 {
        if !IsDefined(this.areas) {
            this.areas = NMAreaIndex.Load();
        }
        return this.areas.At(this.camera.cx, this.camera.cy);
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

    private func DefaultDetails(L: ref<OverlayMapLayer>, id: Int32) -> ref<OverlayMapDetails> {
        let g = L.catGlobal[L.cat[id]];
        let title = NotEquals(L.label[id], "") ? L.label[id] : this.api.catDisplay[g];
        let d = OverlayMapDetails.Create(this.api.catDisplay[g], title);
        let player = GetPlayer(this.GetGameInstance());
        if IsDefined(player) {
            let p = player.GetWorldPosition();
            let dx = L.px[id] - p.X;
            let dy = L.py[id] - p.Y;
            d.AddRow("Distance", NMMath.FormatMeters(SqrtF(dx * dx + dy * dy)));
        }
        return d;
    }

    // What the waypoint key does for the current selection: the vanilla mappin under it (if any) and the point a custom
    // waypoint would go (the pin, else the focus point at street level).
    private func WaypointPlan(out pos: Vector4, out m: ref<IMappin>) -> NMWaypointAction {
        let gi = this.GetGameInstance();
        let c = this.crosshair;
        pos = new Vector4(this.camera.cx, this.camera.cy, NMWaypoint.GroundZ(this.camera.cx, this.camera.cy), 1.0);
        let hasSel = false;
        if c.selKind == 0 && c.selLayer >= 0 && c.selLayer < ArraySize(this.api.layers) && this.api.layers[c.selLayer].IsAlive(c.selItem) {
            let L = this.api.layers[c.selLayer];
            hasSel = true;
            let p = L.Position(c.selItem);
            pos = new Vector4(p.X, p.Y, p.Z != 0.0 ? p.Z : NMWaypoint.GroundZ(p.X, p.Y), 1.0);
            if IsDefined(this.vanilla) { m = this.vanilla.MappinAt(L, c.selItem); }
        }
        let isMappin = IsDefined(m);
        let questTrackable = isMappin && NMVanillaTracking.CanTrackQuest(gi, m);
        let questTracked = questTrackable && NMVanillaTracking.IsQuestTracked(gi, m);
        let trackedNow = false;
        if isMappin {
            let id = m.GetNewMappinID();
            trackedNow = id.value != 0ul && NMVanillaTracking.ManualKey(gi) == id.value;
        }
        let a = NMWaypoint.Decide(hasSel, isMappin, questTrackable, questTracked, trackedNow, NMWaypoint.Available());
        // An empty spot off the city (open sea, past the edge) gets no waypoint, as teleport refuses it.
        if Equals(a, NMWaypointAction.SetCustom) && !hasSel && !NMTeleport.InBounds(pos.X, pos.Y) {
            return NMWaypointAction.None;
        }
        return a;
    }

    private func WaypointLabel() -> String {
        if !IsDefined(this.crosshair) || !IsDefined(this.camera) { return ""; }
        let pos: Vector4;
        let m: ref<IMappin>;
        return NMWaypoint.Label(this.WaypointPlan(pos, m));
    }

    // Enter / pad RB: set the custom waypoint, track the quest or the marker, or clear what is tracked.
    private func DoWaypoint() {
        if !IsDefined(this.crosshair) || !IsDefined(this.camera) { return; }
        let gi = this.GetGameInstance();
        let pos: Vector4;
        let m: ref<IMappin>;
        let a = this.WaypointPlan(pos, m);
        let w = this.Waypoint();
        let ok = false;
        switch a {
            case NMWaypointAction.TrackQuest:
                w.CancelPending();
                NMWaypoint.UnregisterCustom(gi);   // vanilla TryTrackQuestOrSetWaypoint drops the custom waypoint first
                ok = NMVanillaTracking.TrackQuest(gi, m);
                w.lastAction = ok ? "quest" : "refused";
                break;
            case NMWaypointAction.SetCustom:
                ok = w.SetCustom(pos.X, pos.Y, pos.Z);
                break;
            case NMWaypointAction.TrackMappin:
                ok = w.Track(m);
                break;
            case NMWaypointAction.Clear:
                ok = w.Clear();
                break;
            default:
                return;
        }
        NMLog.Info("waypoint|" + NMWaypoint.Label(a) + "|" + ToString(ok) + "|" + w.lastAction);
        if IsDefined(this.vanilla) { this.vanilla.Repoll(); }
    }

    private func Activate() {
        let c = this.crosshair;
        if c.selKind == 0 && c.selLayer >= 0 && c.selLayer < ArraySize(this.api.layers) {
            let L = this.api.layers[c.selLayer];
            if IsDefined(L.listener) && L.IsAlive(c.selItem) {
                L.listener.OnActivated(c.selItem);
            }
        }
    }

    private func UpdateScale() {
        let l = this.panel.layout;
        this.scaleRev = this.camera.revision;
        let maxMeters = NMPanel.ScaleBarMax(l.scale) * this.camera.mpp;
        let len = NMMath.NiceLength(maxMeters);
        this.panel.SetScaleBar(len / this.camera.mpp);
        let label = NMMath.FormatMeters(len);
        if NotEquals(label, this.hdrScaleLabel) {
            this.panel.scaleLabel.SetText(label);
            this.hdrScaleLabel = label;
        }
    }

    private func UpdateHeader() {
        let s = this.Settings();
        let district = this.DistrictName();
        if NotEquals(district, this.hdrDistrict) {
            this.panel.districtTitle.SetText(district);
            this.hdrDistrict = district;
        }
        let filter = this.filterView == 0 ? "" : "FILTER · " + NMVanillaFilters.ViewName(this.filterView);
        if NotEquals(filter, this.hdrFilter) {
            this.panel.districtSub.SetText(filter);
            this.panel.districtSub.SetVisible(StrLen(filter) > 0);
            this.hdrFilter = filter;
        }
        let q = NMQuestHeader.Read(this.GetGameInstance());
        let qState = q.visible ? 1 : 0;
        if qState != this.hdrQuestState {
            this.panel.tracking.SetVisible(q.visible);
            this.hdrQuestState = qState;
            this.hdrQuestObjective = "\n";   // visibility of the objective follows its text: re-evaluate below
        }
        if q.visible {
            let title = NMTooltip.Truncate(StrUpper(q.title), this.panel.QuestTitleChars());
            let titleChanged = NotEquals(title, this.hdrQuestTitle);
            if titleChanged {
                this.panel.questTitle.SetText(title);
                this.hdrQuestTitle = title;
            }
            if titleChanged || NotEquals(q.isQuest, this.hdrQuestIsQuest) {
                let qc = NMTheme.VanillaStateColor(q.isQuest ? n"Quest" : n"Gigs");
                this.panel.questTitle.SetTintColor(qc);
                this.panel.questDiamond.SetTintColor(qc);
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
        if IsDefined(this.renderer) {
            this.renderer.SetReserved(this.panel.HeaderRects());   // markers keep clear of the header text
        }
        if IsDefined(s) {
            let view = NMVanillaFilters.ViewName(this.filterView);
            let hints = NMInput.Hints(s, view, this.TeleportLabel());
            if this.padOwned && this.pad.lastWasPad {
                hints = NMPad.Hints(view, this.TeleportLabel(), s.teleportEnabled, s.holdToShow);
            } else if this.padFromPad && !this.padOwned {
                hints = NMPad.PassThroughHints(hints);
            }
            let padHints = this.padOwned && this.pad.lastWasPad;
            hints = NMWaypoint.WithHint(hints, padHints ? "RB" : NMInput.KeyName(s.keyWaypoint), this.WaypointLabel());
            if this.input.arrowSeen {
                hints = NMInput.NumLockHints(hints);
            }
            this.panel.hintBar.Set(hints);   // rebuilds only when the hints changed
        }
    }

    public func CornerHost() -> ref<NMCornerHost> { return this.cornerHost; }

    // Vanilla minimap px per metre: measured on the GPS route when one is read, else estimated from a mirrored marker.
    private func MiniScale(player: ref<GameObject>) -> Float {
        let s = this.Gps().Scale();
        if s > 0.0 || !IsDefined(player) { return s; }
        return this.mirror.EstimateScale(player.GetWorldPosition());
    }

    public func CameraYaw() -> Float {
        return NMGps.CameraYaw(GameInstance.GetCameraSystem(this.GetGameInstance()).GetActiveCameraForward());
    }
    public func Palette() -> ref<NMHudPalette> { return this.palette; }
    public func Mirror() -> ref<NMMinimapMirror> { return this.mirror; }
    public func UsePalette(p: ref<NMHudPalette>) { this.palette = p; }

    // Follow HUD Painter colours: probes live in the HUD window while the setting is on; a palette change re-tints the
    // open panel's layers and rebuilds the corner.
    private func SyncPalette(s: ref<OverlayMapSettings>) {
        let want = IsDefined(s) && s.followHudPainter;
        let changed = false;
        if want && !IsDefined(this.palette) {
            let window = this.HudWindow();
            if IsDefined(window) { this.palette = NMHudPalette.Create(window); }
        } else if !want && IsDefined(this.palette) {
            this.palette.Destroy();
            this.palette = null;
            changed = true;
        }
        if IsDefined(this.palette) && this.palette.Refresh() {
            changed = true;
        }
        if changed {
            this.ApplyTheme();
            this.cornerHost.Invalidate();
        }
    }
    public func CornerActive() -> Bool { return this.cornerHost.Active(); }

    private func ScheduleCornerPoll(seconds: Float) {
        let cb = new OverlayMapCornerPoll();
        cb.system = this;
        cb.gen = this.cornerPollGen;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, seconds, false);
    }

    public func CornerPoll(gen: Int32) {
        if gen != this.cornerPollGen { return; }
        let s = this.Settings();
        let window = this.HudWindow();
        if this.cornerHost.mpp <= 0.0 && this.cornerMpp > 0.0 {
            this.cornerHost.mpp = this.cornerMpp;
        }
        this.SyncPalette(s);
        this.mirror.Sweep();
        let probe = this.cornerHost.Active() ? this.cornerHost.probe : NMMinimapProbe.Find(window, this.Gps().Minimap());
        let r = this.cornerHost.Sync(NMCornerHost.Enabled(s) ? s : null, window, probe, this.api);   // null: shelved or off
        if r == 1 || r == 3 {
            this.PrepareCornerMarkers();
            NMLog.Info("corner|" + (r == 1 ? "on" : "rebuilt") + "|style " + ToString(s.cornerStyle));
            this.EnsureLoop();
        } else if r == 2 {
            NMLog.Info("corner|off");
        }
        if this.cornerHost.Active() {
            this.cornerHost.probe.Fade();   // HUD animations fade vanilla pieces back in
            if IsDefined(s) && s.debug { this.cornerHost.probe.LogOnce(); }
        }
        this.ScheduleCornerPoll(1.0);
    }

    // What OnOpened does for the panel's markers, for a corner built while the map is closed.
    private func PrepareCornerMarkers() {
        this.NoteInventory();
        this.Collect().Refresh(this.GetGameInstance(), this.CollectSeen());
        if this.Collect().SyncWouldRebuild(this.filterView, this.Settings()) {
            this.SyncCollect();
        }
        this.Photos().SyncLayer(this.api, this.PhotosVisible());
        this.vanilla.ApplyFilters(this.filterView, this.Settings());
        this.vanilla.Tick(NMClock.NowMs(), true);
        this.Gps().BeginOpen();
        this.cornerRouteMs = 0.0;
        this.cornerDistrict = "";
        this.cornerObjectiveM = -1.0;
    }

    // The map is closed and the corner is live: markers, routes, strip. Hidden whenever the game hides its minimap.
    private func CornerTick(dt: Float) {
        let c = this.cornerHost.corner;
        let player = GetPlayer(this.GetGameInstance());
        let shown = this.cornerHost.probe.ShownByGame();
        c.SetShown(shown);
        if !shown || !IsDefined(player) { return; }
        let now = NMClock.NowMs();
        this.vanilla.Tick(now, false);
        this.cornerMsVanilla = NMClock.NowMs() - now;
        if this.Photos().Revision() != this.Photos().SyncedRevision() {
            this.Photos().SyncLayer(this.api, this.PhotosVisible());
        }
        let reading: ref<NMGpsReading>;
        let color = NMTheme.VanillaStateColor(n"Quest");
        let style: ref<NMRouteStyle>;
        let routesOn = this.RoutesWanted();
        if routesOn && now - this.cornerRouteMs >= 500.0 {
            reading = this.Gps().Read(player);
            let hdr = NMQuestHeader.Read(this.GetGameInstance());
            color = IsDefined(hdr) && !hdr.isQuest ? NMTheme.VanillaStateColor(n"Gigs") : NMTheme.VanillaStateColor(n"Quest");
            style = this.Gps().PathStyle();
            this.cornerRouteMs = now;
            this.cornerObjectiveM = NMCornerHost.ObjectiveDistance(reading, player.GetWorldPosition());
        }
        if this.frameNo % 30 == 0 || StrLen(this.cornerDistrict) == 0 {
            this.cornerDistrict = this.DistrictName();
        }
        c.Update(player, dt, reading, color, style, routesOn, this.cornerDistrict, this.cornerObjectiveM);
        let tm = NMClock.NowMs();
        c.UpdateMirror(this.mirror, this.MiniScale(player), this.CameraYaw(), this.vanilla.diff);
        this.cornerMsMirror = NMClock.NowMs() - tm;
        if this.frameNo % 10 == 0 {
            let ctrl = this.Gps().Minimap();
            if IsDefined(ctrl) { c.SetZone(ctrl.NMZone()); }
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
