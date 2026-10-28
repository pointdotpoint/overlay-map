module NightMap

// Large preview of the focused photo pin over the right half of the map (spec §6.5). Replaces the tooltip for
// photo pins; the shot loads by hash into the drawer's own image.
public class NMPhotoDrawer {
    private let s: Float;
    private let root: ref<inkCanvas>;
    private let img: ref<inkImage>;
    private let imgFill: ref<inkRectangle>;
    private let category: ref<inkText>;
    private let title: ref<inkText>;
    private let rowKey: array<ref<inkText>>;
    private let rowVal: array<ref<inkText>>;
    private let actBox: ref<inkRectangle>;
    private let actKey: ref<inkText>;
    private let actLabel: ref<inkText>;
    private let shown: Bool;
    private let shownHash: Uint32;
    private let listener: ref<NMDrawerListener>;

    // The view and the focus point shift left by this much while the drawer is open (spec §6.5).
    public static func ShiftTarget(open: Bool, mapW: Float) -> Float {
        return open ? mapW * 0.25 : 0.0;
    }

    // Linear ease: covers the larger of |cur| and |target| in 150 ms.
    public static func EaseShift(cur: Float, target: Float, dtMs: Float) -> Float {
        let span = MaxF(AbsF(cur), AbsF(target));
        if span <= 0.0 { return target; }
        let step = span * MaxF(dtMs, 0.0) / 150.0;
        if AbsF(target - cur) <= step { return target; }
        return cur + (target > cur ? step : -step);
    }

    // Opening the drawer stops follow mode, which would re-centre and undo the shift every frame.
    public static func OnOpen(cam: ref<NMCamera>) {
        cam.follow = false;
    }

    // "photomode_DDMMYYYY_HHMMSS.png" -> "DD MON YYYY · HH:MM"; "" when the name does not match.
    public static func DateFromPath(path: String) -> String {
        let i = StrFindLast(path, "photomode_");
        if i < 0 || StrLen(path) < i + 25 { return ""; }
        let d = StrMid(path, i + 10, 15);   // DDMMYYYY_HHMMSS
        let k = 0;
        while k < 15 {
            let c = StrMid(d, k, 1);
            if k == 8 {
                if NotEquals(c, "_") { return ""; }
            } else if StrFindFirst("0123456789", c) < 0 {
                return "";
            }
            k += 1;
        }
        let month: Int32 = StringToInt(StrMid(d, 2, 2));
        if month < 1 || month > 12 { return ""; }
        let names = "JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC";
        return StrMid(d, 0, 2) + " " + StrMid(names, (month - 1) * 3, 3) + " " + StrMid(d, 4, 4) + " · "
            + StrMid(d, 9, 2) + ":" + StrMid(d, 11, 2);
    }

    public static func Create(parent: ref<inkCanvas>, l: ref<NMPanelLayout>) -> ref<NMPhotoDrawer> {
        let dr = new NMPhotoDrawer();
        let s = l.scale;
        dr.s = s;
        let w = l.mapW * 0.5;
        let h = l.mapH;
        let pad = 40.0 * s;
        dr.root = NMUi.Canvas(parent, l.mapW - w, 0.0, w, h);
        NMUi.Rect(dr.root, 0.0, 0.0, w, h, NMTheme.CardBg(), 0.92);
        NMUi.Rect(dr.root, 0.0, 0.0, 6.0 * s, h, NMTheme.Cyan(), 1.0);
        let iw = w - pad * 2.0;
        let ih = iw * 9.0 / 16.0;
        dr.imgFill = NMUi.Rect(dr.root, pad, pad, iw, ih, NMTheme.PanelBg(), 1.0);
        dr.img = new inkImage();
        dr.img.SetAnchor(inkEAnchor.TopLeft);
        dr.img.SetSize(new Vector2(iw, ih));
        dr.img.SetTranslation(new Vector2(pad, pad));
        dr.img.SetInteractive(false);
        dr.img.SetVisible(false);
        dr.img.Reparent(dr.root);
        let y = pad + ih + 30.0 * s;
        dr.category = NMUi.Text(dr.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(28.0 * s), NMTheme.Pink());
        dr.category.SetTranslation(new Vector2(pad, y));
        dr.category.SetText("PHOTO");
        dr.title = NMUi.Text(dr.root, NMTheme.BodyFont(), n"Bold", Cast<Int32>(44.0 * s), NMTheme.Text());
        dr.title.SetTranslation(new Vector2(pad, y + 36.0 * s));
        let ry = y + 100.0 * s;
        let i = 0;
        while i < 2 {
            let k = NMUi.Text(dr.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(28.0 * s), NMTheme.Muted());
            let v = NMUi.Text(dr.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(30.0 * s), NMTheme.Text());
            k.SetTranslation(new Vector2(pad, ry));
            v.SetTranslation(new Vector2(pad + 220.0 * s, ry));
            ArrayPush(dr.rowKey, k);
            ArrayPush(dr.rowVal, v);
            ry += 44.0 * s;
            i += 1;
        }
        dr.rowKey[0].SetText("DISTANCE");
        dr.rowKey[1].SetText("DISTRICT");
        let ay = ry + 20.0 * s;
        dr.actBox = NMUi.Rect(dr.root, pad, ay, 10.0 * s, 46.0 * s, NMTheme.Cyan(), 0.15);
        dr.actKey = NMUi.Text(dr.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(26.0 * s), NMTheme.Cyan());
        dr.actKey.SetTranslation(new Vector2(pad + 12.0 * s, ay + 8.0 * s));
        dr.actLabel = NMUi.Text(dr.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(28.0 * s), NMTheme.Text());
        dr.root.SetVisible(false);
        return dr;
    }

    public func IsShown() -> Bool { return this.shown; }
    public func ImageShown() -> Bool { return this.img.IsVisible(); }
    public func LastListener() -> ref<NMDrawerListener> { return this.listener; }

    // Test seam: a drawer on a canvas of its own (not on screen).
    public static func CreateDetached() -> ref<NMPhotoDrawer> {
        return NMPhotoDrawer.Create(new inkCanvas(), NMPanelLayout.Compute(3840.0, 2160.0));
    }

    public func Show(spot: ref<NMPhotoSpot>, distance: String, district: String, keyName: String, h: wref<inkISystemRequestsHandler>) {
        let date = NMPhotoDrawer.DateFromPath(spot.path);
        this.title.SetText(StrLen(date) > 0 ? date : "PHOTO SPOT");
        this.rowVal[0].SetText(distance);
        this.rowVal[1].SetText(StrUpper(district));
        let s = this.s;
        let cw = (24.0 + 17.0 * Cast<Float>(StrLen(keyName))) * s;
        this.actBox.SetSize(new Vector2(cw, 46.0 * s));
        this.actKey.SetText(keyName);
        this.actLabel.SetText("TELEPORT");
        let p = this.actBox.GetTranslation();
        this.actLabel.SetTranslation(new Vector2(p.X + cw + 16.0 * s, p.Y + 7.0 * s));
        if spot.hash != this.shownHash {
            this.shownHash = spot.hash;
            this.img.SetVisible(false);
            this.imgFill.SetVisible(true);
            // A fresh listener per request: a late image from the previous pin carries its own hash and is ignored.
            this.listener = new NMDrawerListener();
            this.listener.drawer = this;
            this.listener.hash = spot.hash;
            if IsDefined(h) {
                h.RequestGameScreenshotByHash(spot.hash, this.img, this.listener, n"OnLoaded");
            }
        }
        if !this.shown {
            this.root.SetVisible(true);
            this.shown = true;
        }
    }

    public func OnImage(hash: Uint32, size: Vector2, err: Int32) {
        if hash != this.shownHash || size.X <= 0.0 || err != 0 { return; }
        this.img.SetVisible(true);
        this.imgFill.SetVisible(false);
    }

    public func Hide() {
        if this.shown {
            this.root.SetVisible(false);
            this.shown = false;
        }
    }
}

public class NMDrawerListener extends IScriptable {
    public let drawer: wref<NMPhotoDrawer>;
    public let hash: Uint32;

    protected cb func OnLoaded(size: Vector2, err: Int32) -> Bool {
        if IsDefined(this.drawer) {
            this.drawer.OnImage(this.hash, size, err);
        }
        return true;
    }
}
