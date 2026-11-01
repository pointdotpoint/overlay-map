module NightMap

public class NMPlayerMarker {
    private let img: ref<inkImage>;
    private let rings: ref<inkImage>;
    private let shown: Bool;

    public static func Create(parent: ref<inkCanvas>, scale: Float, effects: Bool, theme: Int32) -> ref<NMPlayerMarker> {
        let m = new NMPlayerMarker();
        if effects {
            let rs = NMTheme.RingsSize() * scale;
            m.rings = NMUi.HoloImage(parent, n"holo_rings", 0.0, 0.0, rs, rs, NMTheme.HoloAccent(theme), NMTheme.RingsOpacity(), inkBrushTileType.NoTile);
            m.rings.SetAnchorPoint(new Vector2(0.5, 0.5));
            m.rings.SetVisible(false);
        }
        m.img = NMUi.Image(parent, n"player", 0.0, 0.0, NMTheme.PlayerSize() * scale, NMTheme.Cyan(), true);
        m.img.SetRenderTransformPivot(new Vector2(0.5, 0.5));
        m.img.SetVisible(false);
        return m;
    }

    public func HasRings() -> Bool { return IsDefined(this.rings); }
    public func RingsTranslation() -> Vector2 { return this.rings.GetTranslation(); }
    public func ArrowTranslation() -> Vector2 { return this.img.GetTranslation(); }

    public func Update(cam: ref<NMCamera>, player: ref<GameObject>, viewW: Float, viewH: Float) {
        let visible = false;
        if IsDefined(player) {
            let pos = player.GetWorldPosition();
            let fwd = player.GetWorldForward();
            let p = cam.WorldToMap(pos.X, pos.Y);
            visible = p.X >= 0.0 && p.X <= viewW && p.Y >= 0.0 && p.Y <= viewH;
            if visible {
                this.img.SetTranslation(p);
                if IsDefined(this.rings) {
                    this.rings.SetTranslation(p);
                }
                this.img.SetRotation(NMMath.HeadingDeg(fwd.X, fwd.Y) * NMTheme.PlayerRotationSign());
            }
        }
        if NotEquals(visible, this.shown) {
            this.img.SetVisible(visible);
            if IsDefined(this.rings) {
                this.rings.SetVisible(visible);
            }
            this.shown = visible;
        }
    }
}
