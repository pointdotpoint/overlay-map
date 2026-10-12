module NightMap

public class NMPlayerMarker {
    private let img: ref<inkImage>;
    private let shown: Bool;

    public static func Create(parent: ref<inkCanvas>, scale: Float) -> ref<NMPlayerMarker> {
        let m = new NMPlayerMarker();
        m.img = NMUi.Image(parent, n"player", 0.0, 0.0, NMTheme.PlayerSize() * scale, NMTheme.Cyan(), true);
        m.img.SetRenderTransformPivot(new Vector2(0.5, 0.5));
        m.img.SetVisible(false);
        return m;
    }

    public func Update(cam: ref<NMCamera>, player: ref<GameObject>, viewW: Float, viewH: Float) {
        let visible = false;
        if IsDefined(player) {
            let pos = player.GetWorldPosition();
            let fwd = player.GetWorldForward();
            let p = cam.WorldToMap(pos.X, pos.Y);
            visible = p.X >= 0.0 && p.X <= viewW && p.Y >= 0.0 && p.Y <= viewH;
            if visible {
                this.img.SetTranslation(p);
                this.img.SetRotation(NMMath.HeadingDeg(fwd.X, fwd.Y) * NMTheme.PlayerRotationSign());
            }
        }
        if NotEquals(visible, this.shown) {
            this.img.SetVisible(visible);
            this.shown = visible;
        }
    }
}
