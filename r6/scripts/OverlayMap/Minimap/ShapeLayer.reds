module OverlayMap

// Draws the mirrored vanilla minimap markers north-up at OverlayMap's zoom: device effect rings, vision cones, then the
// icons, each copied from the vanilla widget (atlas, part, tint, opacity) every update. Pooled images.
public class NMShapeLayer {
    private let root: ref<inkCanvas>;
    private let ringCanvas: ref<inkCanvas>;
    private let coneCanvas: ref<inkCanvas>;
    private let iconCanvas: ref<inkCanvas>;
    private let rings: array<ref<inkImage>>;
    private let cones: array<ref<inkImage>>;
    private let icons: array<ref<inkImage>>;
    private let arrows: array<ref<inkImage>>;
    private let arrowCanvas: ref<inkCanvas>;
    private let areaCanvas: ref<inkCanvas>;
    private let areas: array<ref<inkShape>>;
    private let nz: Int32;
    private let loggedArea: Bool;
    private let round: Bool;      // the view is a disc (Circle style)
    private let rimInset: Float;  // px inside the rim where clamped markers sit
    private let scale: Float;     // as NMPanelLayout.scale
    private let na: Int32;
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
        l.areaCanvas = NMUi.Canvas(l.root, 0.0, 0.0, size.X, size.Y);
        l.ringCanvas = NMUi.Canvas(l.root, 0.0, 0.0, size.X, size.Y);
        l.coneCanvas = NMUi.Canvas(l.root, 0.0, 0.0, size.X, size.Y);
        l.iconCanvas = NMUi.Canvas(l.root, 0.0, 0.0, size.X, size.Y);
        l.arrowCanvas = NMUi.Canvas(l.root, 0.0, 0.0, size.X, size.Y);
        l.scale = 1.0;
        l.rimInset = 30.0;
        l.markerSize = markerSize;
        return l;
    }

    public func SetRim(round: Bool, inset: Float, scale: Float) {
        this.round = round;
        this.rimInset = inset;
        this.scale = scale;
    }

    public static func ArrowSize() -> Float { return 22.0; }   // 4K units

    // Kinds shown: enemies (with cones) and police by their switches; devices and the rest always.
    public static func Wanted(kind: NMMiniKind, enemies: Bool, police: Bool) -> Bool {
        if Equals(kind, NMMiniKind.Enemy) { return enemies; }
        if Equals(kind, NMMiniKind.Police) { return police; }
        return Equals(kind, NMMiniKind.Device) || Equals(kind, NMMiniKind.Other) || Equals(kind, NMMiniKind.Area) || Equals(kind, NMMiniKind.Zone);
    }

    // Vanilla minimap px -> OverlayMap px. sMini: vanilla px per metre (NMGps scale, 0 = unknown); fallback: the cone's
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
        this.na = 0;
        this.nz = 0;
        if IsDefined(mirror) {
            for e in mirror.All() {
                let shadow = Equals(e.kind, NMMiniKind.Shadow) || (IsDefined(skip) && IsDefined(skip.Find(e.key)));
                if e.Shown() && (shadow || NMShapeLayer.Wanted(e.kind, enemies, police)) {
                    this.Draw(e, cam, viewW, viewH, sMini, camYaw, shadow);
                }
            }
        }
        NMShapeLayer.Hide(this.arrows, this.na);
        let i = this.nz;
        while i < ArraySize(this.areas) {
            if this.areas[i].IsVisible() { this.areas[i].SetVisible(false); }
            i += 1;
        }
        NMShapeLayer.Hide(this.rings, this.nr);
        NMShapeLayer.Hide(this.cones, this.nc);
        NMShapeLayer.Hide(this.icons, this.ni);
        this.drawnIcons = this.ni;
        this.drawnCones = this.nc;
    }

    private func Arrow(at: Vector2, rotation: Float, tint: HDRColor, opacity: Float) {
        let a = this.Slot(this.arrows, this.arrowCanvas, this.na);
        if NotEquals(a.GetTexturePart(), n"holo_arrow") {
            a.SetAtlasResource(NMTheme.HoloAtlas());
            a.SetTexturePart(n"holo_arrow");
            a.SetAnchorPoint(new Vector2(0.5, 0.5));
            a.SetRenderTransformPivot(new Vector2(0.5, 0.5));
        }
        let sz = NMShapeLayer.ArrowSize() * this.scale * this.markerSize;
        a.SetSize(new Vector2(sz, sz));
        a.SetTranslation(at);
        a.SetRotation(rotation);
        a.SetTintColor(tint);
        a.SetOpacity(opacity);
        a.SetVisible(true);
        this.na += 1;
    }

    // shadow: NMVanilla draws the marker itself; only its rim clamp and above / below arrow come from here.
    private func Draw(e: ref<NMMiniEntry>, cam: ref<NMCamera>, viewW: Float, viewH: Float, sMini: Float, camYaw: Float, shadow: Bool) {
        let w = e.Position();
        if Equals(e.kind, NMMiniKind.Area) || Equals(e.kind, NMMiniKind.Zone) {
            this.DrawArea(e, cam, w, sMini, camYaw);
            return;
        }
        let p = cam.WorldToMap(w.X, w.Y);
        let rootOp = e.root.GetOpacity();
        let tint = IsDefined(e.icon) ? e.icon.GetTintColor() : NMTheme.HoloAccent(0);
        if NMParity.IsOff(p.X, p.Y, viewW, viewH, this.round, this.rimInset) {
            if !(e.clampable || e.tracked) || !IsDefined(e.icon) { return; }
            let rim = NMParity.ClampToRim(p.X, p.Y, viewW, viewH, this.round, this.rimInset);
            let icon = this.Slot(this.icons, this.iconCanvas, this.ni);
            NMShapeLayer.CopyLook(e.icon, icon, rootOp);
            let s = e.icon.GetSize();
            icon.SetSize(new Vector2(s.X * this.markerSize, s.Y * this.markerSize));
            icon.SetAnchorPoint(new Vector2(0.5, 0.5));
            icon.SetTranslation(rim);
            icon.SetVisible(true);
            this.ni += 1;
            let ang = NMParity.ArrowAngle(p.X, p.Y, viewW, viewH);
            let r = Deg2Rad(ang);
            let off = MaxF(s.X, s.Y) * this.markerSize * 0.5;
            this.Arrow(new Vector2(rim.X + SinF(r) * off, rim.Y - CosF(r) * off), ang, tint, rootOp);
            return;
        }
        if e.vertical != 0 {
            let s = IsDefined(e.icon) ? e.icon.GetSize() : new Vector2(32.0, 32.0);
            let off = MaxF(s.X, s.Y) * this.markerSize * 0.5;
            this.Arrow(new Vector2(p.X + off, p.Y - off), NMParity.VerticalRotation(e.vertical), tint, rootOp);
        }
        if shadow { return; }
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

    // The vanilla area polygon, vertex by vertex into map px, with its own variant, tint and opacity.
    private func DrawArea(e: ref<NMMiniEntry>, cam: ref<NMCamera>, w: Vector4, sMini: Float, camYaw: Float) {
        let src = e.shape as inkShape;
        if !IsDefined(src) || !src.IsVisible() || sMini <= 0.0 { return; }
        let vs = src.GetVertexList();
        if ArraySize(vs) < 3 {
            if !this.loggedArea {
                this.loggedArea = true;
                NMLog.Info("parity|area|no vertices|" + NameToString(e.cls));
            }
            return;
        }
        let pts: array<Vector2>;
        for v in vs {
            let wv = NMParity.AreaToWorld(v, w.X, w.Y, camYaw, sMini);
            ArrayPush(pts, cam.WorldToMap(wv.X, wv.Y));
        }
        let dst: ref<inkShape>;
        if this.nz < ArraySize(this.areas) {
            dst = this.areas[this.nz];
        } else {
            dst = new inkShape();
            dst.SetAnchor(inkEAnchor.TopLeft);
            dst.SetInteractive(false);
            dst.SetSize(this.root.GetSize());
            dst.Reparent(this.areaCanvas);
            ArrayPush(this.areas, dst);
        }
        dst.SetVariant(src.GetVariant());
        dst.SetVertexList(pts);
        dst.SetTintColor(src.GetTintColor());
        dst.SetOpacity(src.GetOpacity() * e.root.GetOpacity());
        dst.SetVisible(true);
        this.nz += 1;
    }

    public func SetVisible(on: Bool) { this.root.SetVisible(on); }
}
