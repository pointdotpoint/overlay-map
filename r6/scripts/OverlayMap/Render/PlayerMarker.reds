module OverlayMap

// V's marker, rebuilt from the vanilla world map's player_mappin.inkwidget with the game's own atlas parts
// (spike tree: .scratch/markers_spike/look/tree_player_mappin.txt). Bottom to top: a soft black shadow blob, the
// view cone (apex at V, opening along the heading), two faint pulse circles and the chevron. Every size is the
// part's native 4K size, as the vanilla widget (fitToContent), times the HUD scale. The blob and circles are round
// and stay put; the cone and chevron turn with V.
public class NMPlayerMarker {
    private let blob: ref<inkImage>;
    private let cone: ref<inkImage>;
    private let circle: ref<inkImage>;
    private let circle2: ref<inkImage>;
    private let img: ref<inkImage>;
    private let rings: ref<inkImage>;
    private let shown: Bool;
    private let ringsK: Float;   // the RingsFade last applied (Create draws them at 1)

    public static func ShadowAtlas() -> ResRef { return r"base\\gameplay\\gui\\common\\shadow_blobs.inkatlas"; }
    public static func CircleAtlas() -> ResRef { return r"base\\gameplay\\gui\\common\\icons\\braindance_icons.inkatlas"; }

    // Native part sizes in 4K units (atlas_minimap player 51x46, playerCone 166x143, braindance recording1 71x71).
    public static func ChevronSize() -> Vector2 { return new Vector2(51.0, 46.0); }
    public static func ConeSize() -> Vector2 { return new Vector2(166.0, 143.0); }
    public static func CircleSize() -> Float { return 71.0; }
    public static func BlobSize() -> Float { return 110.0; }   // iconBlack: 100 box at scale 1.1
    // The cone's apex sits this far behind V's centre (4K units), measured off a vanilla map screenshot at 1440p.
    public static func ConeApexBack() -> Float { return 26.0; }
    // MainColors.Green, the pulse circles' tint in the vanilla widget.
    public static func CircleColor() -> HDRColor { return new HDRColor(0.114, 0.929, 0.514, 1.0); }

    private static func Part(parent: ref<inkCanvas>, atlas: ResRef, part: CName, w: Float, h: Float, color: HDRColor, opacity: Float) -> ref<inkImage> {
        let img = new inkImage();
        img.SetAnchor(inkEAnchor.TopLeft);
        img.SetAtlasResource(atlas);
        img.SetTexturePart(part);
        img.SetSize(new Vector2(w, h));
        img.SetAnchorPoint(new Vector2(0.5, 0.5));
        img.SetRenderTransformPivot(new Vector2(0.5, 0.5));
        img.SetTintColor(color);
        img.SetOpacity(opacity);
        img.SetInteractive(false);
        img.SetVisible(false);
        img.Reparent(parent);
        return img;
    }

    public static func Create(parent: ref<inkCanvas>, scale: Float, effects: Bool, theme: Int32) -> ref<NMPlayerMarker> {
        let m = new NMPlayerMarker();
        if effects {
            let rs = NMTheme.RingsSize() * scale;
            m.rings = NMUi.HoloImage(parent, n"holo_rings", 0.0, 0.0, rs, rs, NMTheme.HoloAccent(theme), NMTheme.RingsOpacity(), inkBrushTileType.NoTile);
            m.rings.SetAnchorPoint(new Vector2(0.5, 0.5));
            m.rings.SetVisible(false);
            m.ringsK = 1.0;
        }
        let green = NMTheme.VanillaStateColor(n"Player");
        let bs = NMPlayerMarker.BlobSize() * scale;
        m.blob = NMPlayerMarker.Part(parent, NMPlayerMarker.ShadowAtlas(), n"shadowBlobSquare_big", bs, bs, new HDRColor(0.0, 0.0, 0.0, 1.0), 1.0);
        let cs = NMPlayerMarker.ConeSize();
        m.cone = NMPlayerMarker.Part(parent, NMTheme.MinimapAtlas(), n"playerCone", cs.X * scale, cs.Y * scale, green, 1.0);
        // Anchor and pivot on V's centre, which lies ConeApexBack inside the cone from its apex (the bottom edge).
        let ay = (cs.Y - NMPlayerMarker.ConeApexBack()) / cs.Y;
        m.cone.SetAnchorPoint(new Vector2(0.5, ay));
        m.cone.SetRenderTransformPivot(new Vector2(0.5, ay));
        let r1 = NMPlayerMarker.CircleSize() * 1.2 * scale;
        let r2 = NMPlayerMarker.CircleSize() * 1.7 * scale;
        m.circle = NMPlayerMarker.Part(parent, NMPlayerMarker.CircleAtlas(), n"recording1", r1, r1, NMPlayerMarker.CircleColor(), 0.07);
        m.circle2 = NMPlayerMarker.Part(parent, NMPlayerMarker.CircleAtlas(), n"recording1", r2, r2, NMPlayerMarker.CircleColor(), 0.005);
        let ch = NMPlayerMarker.ChevronSize();
        m.img = NMPlayerMarker.Part(parent, NMTheme.MinimapAtlas(), n"player", ch.X * scale, ch.Y * scale, green, 1.0);
        return m;
    }

    public func ArrowTint() -> HDRColor { return this.img.GetTintColor(); }
    public func ConeTint() -> HDRColor { return this.cone.GetTintColor(); }
    public func HasRings() -> Bool { return IsDefined(this.rings); }
    public func RingsTranslation() -> Vector2 { return this.rings.GetTranslation(); }
    public func ArrowTranslation() -> Vector2 { return this.img.GetTranslation(); }
    public func ConeTranslation() -> Vector2 { return this.cone.GetTranslation(); }
    public func ArrowRotation() -> Float { return this.img.GetRotation(); }
    public func ConeRotation() -> Float { return this.cone.GetRotation(); }

    public func Update(cam: ref<NMCamera>, player: ref<GameObject>, viewW: Float, viewH: Float) {
        let visible = false;
        if IsDefined(player) {
            let pos = player.GetWorldPosition();
            let fwd = player.GetWorldForward();
            let p = cam.WorldToMap(pos.X, pos.Y);
            visible = p.X >= 0.0 && p.X <= viewW && p.Y >= 0.0 && p.Y <= viewH;
            if visible {
                this.blob.SetTranslation(p);
                this.cone.SetTranslation(p);
                this.circle.SetTranslation(p);
                this.circle2.SetTranslation(p);
                this.img.SetTranslation(p);
                if IsDefined(this.rings) {
                    this.rings.SetTranslation(p);
                    let k = NMTheme.RingsFade(cam.mpp);
                    if AbsF(k - this.ringsK) > 0.01 {
                        this.ringsK = k;
                        this.rings.SetOpacity(NMTheme.RingsOpacity() * k);
                    }
                }
                let rot = NMMath.HeadingDeg(fwd.X, fwd.Y) * NMTheme.PlayerRotationSign();
                this.cone.SetRotation(rot);
                this.img.SetRotation(rot);
            }
        }
        if NotEquals(visible, this.shown) {
            this.blob.SetVisible(visible);
            this.cone.SetVisible(visible);
            this.circle.SetVisible(visible);
            this.circle2.SetVisible(visible);
            this.img.SetVisible(visible);
            if IsDefined(this.rings) {
                this.rings.SetVisible(visible);
            }
            this.shown = visible;
        }
    }
}
