module NightMap

// THROWAWAY spike for the photo pins feature (plan 2026-10-28, Task 1). Deleted in Task 7.
// Logs `photoprobe|...`: the capture, the game's screenshot list (from photo mode and from the HUD minimap
// controller), a by-hash thumbnail load outside the gallery, and an exact teleport to the last capture.
public class NMPhotoProbe extends IScriptable {
    public let lastPos: Vector4;
    public let lastYaw: Float;
    public let hasCapture: Bool;
    public let captures: Int32;
    public let newestHash: Uint32;
    public let newest: array<Uint32>;
    public let source: String;
    public let images: array<ref<inkImage>>;
    public let loadStart: Float;
    public let loadsDone: Int32;
    public let loadsWanted: Int32;
    public let minimap: wref<MinimapContainerController>;

    public func OnCapture(pos: Vector4, yaw: Float) {
        this.lastPos = pos;
        this.lastYaw = yaw;
        this.hasCapture = true;
        this.captures += 1;
        NMLog.Info("photoprobe|capture|" + ToString(this.captures) + "|" + ToString(pos.X) + "," + ToString(pos.Y) + ","
            + ToString(pos.Z) + "|yaw " + ToString(yaw) + "|t " + ToString(NMClock.NowMs()));
    }

    public func RequestList(h: wref<inkISystemRequestsHandler>, source: String) {
        if !IsDefined(h) {
            NMLog.Info("photoprobe|list|" + source + "|no handler");
            return;
        }
        this.source = source;
        h.RegisterToCallback(n"OnScreenshotsForLoadReady", this, n"OnList");
        h.RequestGameScreenshotsForLoad();
        NMLog.Info("photoprobe|list|" + source + "|requested");
    }

    protected cb func OnList(infos: array<GameScreenshotInfo>) -> Bool {
        NMLog.Info("photoprobe|list|" + this.source + "|ready|count " + ToString(ArraySize(infos)));
        // The 3 newest by creationDate.
        let picked: array<Int32>;
        let k = 0;
        while k < 3 {
            let best = -1;
            let i = 0;
            while i < ArraySize(infos) {
                if !ArrayContains(picked, i) && (best < 0 || infos[i].creationDate > infos[best].creationDate) {
                    best = i;
                }
                i += 1;
            }
            if best < 0 { break; }
            ArrayPush(picked, best);
            k += 1;
        }
        ArrayClear(this.newest);
        let h = this.Handler();
        for i in picked {
            let inf = infos[i];
            let ph = IsDefined(h) ? h.GetPathHash(inf.path) : 0u;
            NMLog.Info("photoprobe|entry|" + inf.path + "|created " + ToString(inf.creationDate) + "|pathHash "
                + ToString(inf.pathHash) + "|GetPathHash " + ToString(ph) + "|index " + ToString(inf.screenshotIndex)
                + "|aspect " + ToString(inf.aspectRatioType));
            ArrayPush(this.newest, inf.pathHash);
        }
        if ArraySize(this.newest) > 0 {
            this.newestHash = this.newest[0];
        }
        return true;
    }

    public func Handler() -> wref<inkISystemRequestsHandler> {
        if IsDefined(this.minimap) {
            return this.minimap.GetSystemRequestsHandler();
        }
        return null;
    }

    // On map open: list from the HUD controller, then one big load and (next open) 20 small ones.
    public func OnMapOpened(parent: ref<inkCanvas>) {
        this.RequestList(this.Handler(), "hud");
        if this.newestHash == 0u || !IsDefined(parent) {
            NMLog.Info("photoprobe|load|skipped (no hash yet, reopen the map)");
            return;
        }
        let h = this.Handler();
        ArrayClear(this.images);
        this.loadsDone = 0;
        this.loadStart = NMClock.NowMs();
        let big = new inkImage();
        big.SetSize(new Vector2(640.0, 360.0));
        big.SetTranslation(new Vector2(100.0, 100.0));
        big.Reparent(parent);
        ArrayPush(this.images, big);
        let ok = h.RequestGameScreenshotByHash(this.newestHash, big, this, n"OnLoaded");
        this.loadsWanted = 1;
        let i = 0;
        while i < 20 {
            let hash = this.newest[i % ArraySize(this.newest)];
            let im = new inkImage();
            im.SetSize(new Vector2(68.0, 48.0));
            im.SetTranslation(new Vector2(100.0 + Cast<Float>(i) * 72.0, 480.0));
            im.Reparent(parent);
            ArrayPush(this.images, im);
            if h.RequestGameScreenshotByHash(hash, im, this, n"OnLoaded") {
                this.loadsWanted += 1;
            }
            i += 1;
        }
        NMLog.Info("photoprobe|load|requested|big " + ToString(ok) + "|wanted " + ToString(this.loadsWanted));
    }

    protected cb func OnLoaded(size: Vector2, err: Int32) -> Bool {
        this.loadsDone += 1;
        NMLog.Info("photoprobe|load|done " + ToString(this.loadsDone) + "/" + ToString(this.loadsWanted) + "|size "
            + ToString(size.X) + "x" + ToString(size.Y) + "|err " + ToString(err) + "|ms "
            + ToString(NMClock.NowMs() - this.loadStart));
        return true;
    }

    public func TeleportBack(gi: GameInstance) {
        let player = GetPlayer(gi);
        if !this.hasCapture || !IsDefined(player) {
            NMLog.Info("photoprobe|tp|no capture");
            return;
        }
        let from = player.GetWorldPosition();
        let dx = from.X - this.lastPos.X;
        let dy = from.Y - this.lastPos.Y;
        NMLog.Info("photoprobe|tp|start|dist " + ToString(SqrtF(dx * dx + dy * dy)) + "|target z " + ToString(this.lastPos.Z));
        let rot = new EulerAngles();
        rot.Yaw = this.lastYaw;
        GameInstance.GetTeleportationFacility(gi).Teleport(player, this.lastPos, rot);
        let i = 1;
        while i <= 30 {
            let cb = new NMPhotoProbeZ();
            cb.probe = this;
            cb.step = i;
            GameInstance.GetDelaySystem(gi).DelayCallback(cb, 0.1 * Cast<Float>(i), false);
            i += 1;
        }
    }

    public func LogZ(step: Int32) {
        let player = GetPlayer(GetGameInstance());
        if !IsDefined(player) { return; }
        let p = player.GetWorldPosition();
        NMLog.Info("photoprobe|tp|z|" + ToString(step * 100) + "ms|" + ToString(p.X) + "," + ToString(p.Y) + "," + ToString(p.Z)
            + "|dz " + ToString(p.Z - this.lastPos.Z));
    }
}

public class NMPhotoProbeZ extends DelayCallback {
    public let probe: ref<NMPhotoProbe>;
    public let step: Int32;

    public func Call() {
        this.probe.LogZ(this.step);
    }
}

@wrapMethod(gameuiPhotoModeMenuController)
protected cb func OnHideForScreenshot() -> Bool {
    let r = wrappedMethod();
    let sys = NightMapSystem.Get(GetGameInstance());
    let player = GetPlayer(GetGameInstance());
    if IsDefined(sys) && IsDefined(player) {
        sys.PhotoProbe().OnCapture(player.GetWorldPosition(), player.GetWorldYaw());
    }
    return r;
}

@wrapMethod(gameuiPhotoModeMenuController)
protected cb func OnUninitialize() -> Bool {
    let r = wrappedMethod();
    let sys = NightMapSystem.Get(GetGameInstance());
    if IsDefined(sys) {
        sys.PhotoProbe().RequestList(this.GetSystemRequestsHandler(), "photomode");
    }
    return r;
}

@wrapMethod(MinimapContainerController)
protected cb func OnPlayerAttach(player: ref<GameObject>) -> Bool {
    let r = wrappedMethod(player);
    let sys = NightMapSystem.Get(player.GetGame());
    if IsDefined(sys) { sys.PhotoProbe().minimap = this; }
    return r;
}
