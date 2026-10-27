module NightMap

// One read of both routes, world space. An empty array means no route.
public class NMGpsReading {
    public let quest: array<Vector2>;
    public let tracked: array<Vector2>;
}

// The HUD minimap's GPS routes in world space. Transform measured in the spike (2026-10-27-gps-route-spike/FINDINGS.md):
// v[0] = s * (P.y, P.x) and v[i] - v[0] = s * R(c) * flipY(W[i] - P), with c the camera yaw (never the player yaw).
// The minimap controller registers itself through the wraps below; nothing runs while NightMap is closed.
public class NMGps {
    private let ctrl: wref<MinimapContainerController>;
    private let lastScale: Float;          // last accepted s this open; 0 = none
    private let lastQuest: array<Vector2>;
    private let lastTracked: array<Vector2>;
    private let loggedNoMinimap: Bool;
    private let loggedReject: Bool;
    public let readMsLast: Float;
    public let readMsMax: Float;

    public func SetMinimap(c: ref<MinimapContainerController>) { this.ctrl = c; }

    public func ClearMinimap(c: ref<MinimapContainerController>) {
        let cur: ref<MinimapContainerController> = this.ctrl;
        if Equals(cur, c) { this.ctrl = null; }
    }

    // Per-open state: a fresh scale fallback, fresh routes and the log-once flags.
    public func BeginOpen() {
        this.lastScale = 0.0;
        ArrayClear(this.lastQuest);
        ArrayClear(this.lastTracked);
        this.loggedNoMinimap = false;
        this.loggedReject = false;
    }

    public func ResetReadStats() {
        this.readMsLast = 0.0;
        this.readMsMax = 0.0;
    }

    // Both routes in world space; never null. A path the minimap does not show comes back empty.
    public func Read(player: ref<GameObject>) -> ref<NMGpsReading> {
        let t0 = NMClock.NowMs();
        let r = new NMGpsReading();
        if !IsDefined(this.ctrl) || !IsDefined(player) {
            if !IsDefined(this.ctrl) && !this.loggedNoMinimap {
                this.loggedNoMinimap = true;
                NMLog.Info("gps|no minimap");
            }
            return r;
        }
        let pos = player.GetWorldPosition();
        let camYaw = NMGps.CameraYaw(GameInstance.GetCameraSystem(player.GetGame()).GetActiveCameraForward());
        r.quest = this.Path(this.ctrl.gpsQuestPathWidget.widget, pos.X, pos.Y, camYaw, this.lastQuest);
        this.lastQuest = r.quest;
        r.tracked = this.Path(this.ctrl.gpsPlayerTrackedPathWidget.widget, pos.X, pos.Y, camYaw, this.lastTracked);
        this.lastTracked = r.tracked;
        this.readMsLast = NMClock.NowMs() - t0;
        this.readMsMax = MaxF(this.readMsMax, this.readMsLast);
        return r;
    }

    // The look of the minimap's GPS path widget (quest path, else the tracked path); null without a minimap.
    public func PathStyle() -> ref<NMRouteStyle> {
        if !IsDefined(this.ctrl) { return null; }
        let lp = this.ctrl.gpsQuestPathWidget.widget as inkLinePattern;
        if !IsDefined(lp) { lp = this.ctrl.gpsPlayerTrackedPathWidget.widget as inkLinePattern; }
        return IsDefined(lp) ? NMRouteStyle.From(lp) : null;
    }

    // One path widget to world space; a rejected reading keeps the previous accepted polyline.
    private func Path(w: wref<inkWidget>, px: Float, py: Float, camYaw: Float, previous: array<Vector2>) -> array<Vector2> {
        let out: array<Vector2>;
        let lp = w as inkLinePattern;
        if !IsDefined(lp) || !lp.IsVisible() || ArraySize(lp.vertexList) < 2 { return out; }
        let vs = lp.vertexList;
        let v0 = vs[0].int;
        let s = NMGps.Scale(v0, px, py);
        if s < 0.0 {
            if this.lastScale <= 0.0 {
                this.LogReject("near_origin");
                return previous;
            }
            s = this.lastScale;
        }
        let why = NMGps.Reject(v0, px, py, s);
        if StrLen(why) > 0 {
            this.LogReject(why);
            return previous;
        }
        this.lastScale = s;
        for v in vs {
            ArrayPush(out, NMGps.ToWorld(v.int, v0, px, py, camYaw, s));
        }
        return out;
    }

    private func LogReject(why: String) {
        if !this.loggedReject {
            this.loggedReject = true;
            NMLog.Info("gps|reject|" + why);
        }
    }
    // Camera yaw in degrees, the GetWorldYaw convention: 0 = +Y, positive = counter-clockwise.
    public static func CameraYaw(fwd: Vector4) -> Float {
        return Rad2Deg(AtanF(-fwd.X, fwd.Y));
    }

    // Minimap units per metre from the player's own vertex; -1 near the world origin, where it is unstable.
    public static func Scale(v0: Vector2, px: Float, py: Float) -> Float {
        let p = SqrtF(px * px + py * py);
        if p < 50.0 { return -1.0; }
        return SqrtF(v0.X * v0.X + v0.Y * v0.Y) / p;
    }

    // W = P + flipY(R(-c) * (v - v0)) / s
    public static func ToWorld(v: Vector2, v0: Vector2, px: Float, py: Float, camYaw: Float, s: Float) -> Vector2 {
        let rx = v.X - v0.X;
        let ry = v.Y - v0.Y;
        let r = Deg2Rad(camYaw);
        let c = CosF(r);
        let sn = SinF(r);
        let ux = rx * c + ry * sn;
        let uy = ry * c - rx * sn;
        return new Vector2(px + ux / s, py - uy / s);
    }

    // "" accepts the reading; otherwise the first failed rule: scale_range, axis_mismatch, first_far.
    // first_far: the player's own vertex, decoded with s (v0 / s = (P.y, P.x)), lands more than 15 m from the player:
    // a stale or foreign reading (e.g. right after fast travel, or a mirrored v0 whose axis ratios still agree).
    public static func Reject(v0: Vector2, px: Float, py: Float, s: Float) -> String {
        if s < 0.2 || s > 10.0 { return "scale_range"; }
        if AbsF(px) >= 50.0 && AbsF(py) >= 50.0 {
            let ax = v0.X / py;
            let ay = v0.Y / px;
            if AbsF(ax - ay) > 0.05 * MaxF(AbsF(ax), AbsF(ay)) { return "axis_mismatch"; }
        }
        let dx = v0.Y / s - px;
        let dy = v0.X / s - py;
        if dx * dx + dy * dy > 225.0 { return "first_far"; }
        return "";
    }
}

@wrapMethod(MinimapContainerController)
protected cb func OnPlayerAttach(player: ref<GameObject>) -> Bool {
    let r = wrappedMethod(player);
    let sys = NightMapSystem.Get(player.GetGame());
    if IsDefined(sys) { sys.Gps().SetMinimap(this); }
    return r;
}

@wrapMethod(MinimapContainerController)
protected cb func OnPlayerDetach(player: ref<GameObject>) -> Bool {
    let sys = NightMapSystem.Get(player.GetGame());
    if IsDefined(sys) { sys.Gps().ClearMinimap(this); }
    return wrappedMethod(player);
}
