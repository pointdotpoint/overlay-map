module NightMap

// Draws the mirrored vanilla minimap markers north-up at NightMap's zoom: device effect rings, vision cones, then the
// icons, each copied from the vanilla widget (atlas, part, tint, opacity) every update. Pooled images.
public class NMShapeLayer {
    private let root: ref<inkCanvas>;
    private let ringCanvas: ref<inkCanvas>;
    private let coneCanvas: ref<inkCanvas>;
    private let iconCanvas: ref<inkCanvas>;
    private let rings: array<ref<inkImage>>;
    private let cones: array<ref<inkImage>>;
    private let icons: array<ref<inkImage>>;
    private let markerSize: Float;
    public let drawnIcons: Int32;
    public let drawnCones: Int32;

    // Sign of the camera yaw added to a vanilla widget's rotation to make it north-up. The vanilla minimap turns with
    // the camera (NMGps transform); settled at the first hand test.
    public static func RotationSign() -> Float { return 1.0; }

    public static func Create(parent: ref<inkCanvas>, markerSize: Float) -> ref<NMShapeLayer> {
        let l = new NMShapeLayer();
        let size = parent.GetSize();
        l.root = NMUi.Canvas(parent, 0.0, 0.0, size.X, size.Y);
        l.root.SetName(n"MinimapMirror");
        l.ringCanvas = NMUi.Canvas(l.root, 0.0, 0.0, size.X, size.Y);
        l.coneCanvas = NMUi.Canvas(l.root, 0.0, 0.0, size.X, size.Y);
        l.iconCanvas = NMUi.Canvas(l.root, 0.0, 0.0, size.X, size.Y);
        l.markerSize = markerSize;
        return l;
    }

    // Kinds shown: enemies (with cones) and police by their switches; devices and the rest always.
    public static func Wanted(kind: NMMiniKind, enemies: Bool, police: Bool) -> Bool {
        if Equals(kind, NMMiniKind.Enemy) { return enemies; }
        if Equals(kind, NMMiniKind.Police) { return police; }
        return Equals(kind, NMMiniKind.Device) || Equals(kind, NMMiniKind.Other);
    }

    // Vanilla minimap px -> NightMap px. sMini: vanilla px per metre (NMGps scale, 0 = unknown); fallback: the cone's
    // longest side spans its sense-cone length.
    public static func ConeScale(mpp: Float, sMini: Float, coneLen: Float, maxSide: Float) -> Float {
        if sMini > 0.0 { return 1.0 / (mpp * sMini); }
        if coneLen > 0.0 && maxSide > 0.0 { return (coneLen / mpp) / maxSide; }
        return 1.0;
    }

    public static func ConeRotation(vanillaRot: Float, camYaw: Float) -> Float {
        return vanillaRot + NMShapeLayer.RotationSign() * camYaw;
    }

    private func Slot(pool: script_ref<array<ref<inkImage>>>, parent: ref<inkCanvas>, i: Int32) -> ref<inkImage> {
        if i < ArraySize(Deref(pool)) { return Deref(pool)[i]; }
        let img = new inkImage();
        img.SetAnchor(inkEAnchor.TopLeft);
        img.SetInteractive(false);
        img.Reparent(parent);
        ArrayPush(Deref(pool), img);
        return img;
    }

    // Copies a vanilla image's look onto `dst` (atlas and part only when the part changed).
    private static func CopyLook(src: wref<inkImage>, dst: ref<inkImage>, opacity: Float) {
        let part = src.GetTexturePart();
        if NotEquals(part, dst.GetTexturePart()) {
            let ar = src.textureAtlas;
            dst.SetAtlasResource(ResourceAsyncRef.GetPath(ar));
            dst.SetTexturePart(part);
        }
        dst.SetTintColor(src.GetTintColor());
        dst.SetOpacity(opacity);
    }

    private static func Hide(pool: array<ref<inkImage>>, from: Int32) {
        let i = from;
        while i < ArraySize(pool) {
            if pool[i].IsVisible() { pool[i].SetVisible(false); }
            i += 1;
        }
    }

    private let ni: Int32;
    private let nc: Int32;
    private let nr: Int32;

    public func Update(cam: ref<NMCamera>, mirror: ref<NMMinimapMirror>, viewW: Float, viewH: Float, enemies: Bool, police: Bool,
                       sMini: Float, camYaw: Float, skip: ref<NMVanillaDiff>) {
        this.ni = 0;
        this.nc = 0;
        this.nr = 0;
        if IsDefined(mirror) {
            for e in mirror.All() {
                if NMShapeLayer.Wanted(e.kind, enemies, police) && e.Shown() && !(IsDefined(skip) && IsDefined(skip.Find(e.key))) {
                    this.Draw(e, cam, viewW, viewH, sMini, camYaw);
                }
            }
        }
        NMShapeLayer.Hide(this.rings, this.nr);
        NMShapeLayer.Hide(this.cones, this.nc);
        NMShapeLayer.Hide(this.icons, this.ni);
        this.drawnIcons = this.ni;
        this.drawnCones = this.nc;
    }

    private func Draw(e: ref<NMMiniEntry>, cam: ref<NMCamera>, viewW: Float, viewH: Float, sMini: Float, camYaw: Float) {
        let margin = 80.0;
        let w = e.Position();
        let p = cam.WorldToMap(w.X, w.Y);
        if p.X < -margin || p.Y < -margin || p.X > viewW + margin || p.Y > viewH + margin { return; }
        let rootOp = e.root.GetOpacity();
        if e.radius > 0.0 {
            let ring = this.Slot(this.rings, this.ringCanvas, this.nr);
            if NotEquals(ring.GetTexturePart(), n"holo_ring") {
                ring.SetAtlasResource(NMTheme.HoloAtlas());
                ring.SetTexturePart(n"holo_ring");
                ring.SetAnchorPoint(new Vector2(0.5, 0.5));
            }
            let d = 2.0 * e.radius / cam.mpp;
            ring.SetSize(new Vector2(d, d));
            ring.SetTranslation(p);
            ring.SetTintColor(IsDefined(e.icon) ? e.icon.GetTintColor() : NMTheme.HoloAccent(0));
            ring.SetOpacity(0.5 * rootOp);
            ring.SetVisible(true);
            this.nr += 1;
        }
        if IsDefined(e.cone) && e.cone.IsVisible() && e.cone.GetOpacity() > 0.01 {
            let cone = this.Slot(this.cones, this.coneCanvas, this.nc);
            NMShapeLayer.CopyLook(e.cone, cone, e.cone.GetOpacity() * rootOp);
            let size = e.cone.GetSize();
            let k = NMShapeLayer.ConeScale(cam.mpp, sMini, e.coneLen, MaxF(size.X, size.Y));
            cone.SetSize(new Vector2(size.X * k, size.Y * k));
            cone.SetAnchorPoint(e.cone.GetAnchorPoint());
            cone.SetRenderTransformPivot(e.cone.GetRenderTransformPivot());
            cone.SetRotation(NMShapeLayer.ConeRotation(e.cone.GetRotation(), camYaw));
            cone.SetTranslation(p);
            cone.SetVisible(true);
            this.nc += 1;
        }
        if IsDefined(e.icon) && (e.icon.IsVisible() || e.clamped) {
            let icon = this.Slot(this.icons, this.iconCanvas, this.ni);
            NMShapeLayer.CopyLook(e.icon, icon, e.icon.GetOpacity() * rootOp);
            let s = e.icon.GetSize();
            icon.SetSize(new Vector2(s.X * this.markerSize, s.Y * this.markerSize));
            icon.SetAnchorPoint(new Vector2(0.5, 0.5));
            icon.SetTranslation(p);
            icon.SetVisible(true);
            this.ni += 1;
        }
    }

    public func SetVisible(on: Bool) { this.root.SetVisible(on); }
}
