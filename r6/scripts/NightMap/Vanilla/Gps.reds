module NightMap

// The HUD minimap's GPS routes in world space. Transform measured in the spike (2026-10-27-gps-route-spike/FINDINGS.md):
// v[0] = s * (P.y, P.x) and v[i] - v[0] = s * R(c) * flipY(W[i] - P), with c the camera yaw (never the player yaw).
public abstract class NMGps {
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
    public static func Reject(v0: Vector2, px: Float, py: Float, s: Float, first: Vector2) -> String {
        if s < 0.2 || s > 10.0 { return "scale_range"; }
        if AbsF(px) >= 50.0 && AbsF(py) >= 50.0 {
            let ax = v0.X / py;
            let ay = v0.Y / px;
            if AbsF(ax - ay) > 0.05 * MaxF(AbsF(ax), AbsF(ay)) { return "axis_mismatch"; }
        }
        let dx = first.X - px;
        let dy = first.Y - py;
        if dx * dx + dy * dy > 225.0 { return "first_far"; }
        return "";
    }
}
