module NightMap

// The live vanilla minimap: its box, whether the game shows it, and fading its contents. The container root is never
// faded: the game's own visibility/opacity on it stays readable (FINDINGS "Hiding"). Its children are, by opacity
// only, so the minimap keeps running (GPS routes, mirrored markers).
public class NMMinimapProbe {
    private let root: wref<inkWidget>;
    private let window: wref<inkCompoundWidget>;
    private let faded: array<wref<inkWidget>>;
    private let opacity: array<Float>;
    private let logged: Bool;
    private let fixed: Bool;        // tests: Box() answers fixedBox instead of measuring
    private let fixedBox: ref<NMRect>;

    // null until the container has attached (NMGps holds it from the OnPlayerAttach wrap).
    public static func Find(window: wref<inkCompoundWidget>, ctrl: wref<MinimapContainerController>) -> ref<NMMinimapProbe> {
        if !IsDefined(window) || !IsDefined(ctrl) { return null; }
        let root = ctrl.NMRoot();
        if !IsDefined(root) { return null; }
        let p = new NMMinimapProbe();
        p.window = window;
        p.root = root;
        return p;
    }

    // A probe on an arbitrary widget, for the self-tests.
    public static func ForWidget(window: wref<inkCompoundWidget>, root: wref<inkWidget>) -> ref<NMMinimapProbe> {
        let p = new NMMinimapProbe();
        p.window = window;
        p.root = root;
        return p;
    }

    // Tests: off-HUD widgets get no layout pass, so their box can't be measured.
    public static func ForWidgetBox(window: wref<inkCompoundWidget>, root: wref<inkWidget>, box: ref<NMRect>) -> ref<NMMinimapProbe> {
        let p = NMMinimapProbe.ForWidget(window, root);
        p.SetBoxForTest(box);
        return p;
    }

    public func SetBoxForTest(box: ref<NMRect>) {
        this.fixed = true;
        this.fixedBox = box;
    }

    public func Root() -> wref<inkWidget> { return this.root; }

    // Absolute box in the HUD window's units; null when missing or under 8 units.
    public func Box() -> ref<NMRect> {
        if this.fixed { return this.fixedBox; }
        if !IsDefined(this.root) || !IsDefined(this.window) { return null; }
        let wtl = WidgetUtils.LocalToGlobal(this.window, new Vector2(0.0, 0.0));
        let wbr = WidgetUtils.LocalToGlobal(this.window, this.window.GetSize());
        let gw = wbr.X - wtl.X;
        let gh = wbr.Y - wtl.Y;
        if gw < 1.0 || gh < 1.0 { return null; }
        let ws = this.window.GetSize();
        let kx = ws.X / gw;
        let ky = ws.Y / gh;
        let tl = WidgetUtils.LocalToGlobal(this.root, new Vector2(0.0, 0.0));
        let br = WidgetUtils.LocalToGlobal(this.root, this.root.GetSize());
        let r = NMRect.Create((tl.X - wtl.X) * kx, (tl.Y - wtl.Y) * ky, (br.X - wtl.X) * kx, (br.Y - wtl.Y) * ky);
        if r.maxX - r.minX < 8.0 || r.maxY - r.minY < 8.0 { return null; }
        return r;
    }

    // The game shows the minimap: the root and every ancestor up to the window visible and not faded out.
    public func ShownByGame() -> Bool {
        let w: wref<inkWidget> = this.root;
        let n = 0;
        while IsDefined(w) && n < 32 {
            if !w.IsVisible() || w.GetOpacity() < 0.01 { return false; }
            if Equals(w, this.window) { return true; }
            w = w.GetParentWidget();
            n += 1;
        }
        return IsDefined(this.root);
    }

    // Fades the root's children to 0, remembering each one's opacity the first time; re-applies to any a HUD animation
    // faded back in. Cheap; call every few frames.
    public func Fade() {
        let comp = this.root as inkCompoundWidget;
        if !IsDefined(comp) { return; }
        let i = 0;
        while i < comp.GetNumChildren() {
            let w: ref<inkWidget> = comp.GetWidgetByIndex(i);
            if IsDefined(w) {
                if this.IndexOf(w) < 0 {
                    ArrayPush(this.faded, w);
                    ArrayPush(this.opacity, w.GetOpacity());
                }
                if w.GetOpacity() != 0.0 { w.SetOpacity(0.0); }
            }
            i += 1;
        }
    }

    public func Restore() {
        let i = 0;
        while i < ArraySize(this.faded) {
            let w: ref<inkWidget> = this.faded[i];
            if IsDefined(w) { w.SetOpacity(this.opacity[i]); }
            i += 1;
        }
        ArrayClear(this.faded);
        ArrayClear(this.opacity);
    }

    public func FadedCount() -> Int32 { return ArraySize(this.faded); }

    // Debug: the root's box and its children's boxes, once (FINDINGS runtime rows).
    public func LogOnce() {
        if this.logged || !IsDefined(this.root) { return; }
        this.logged = true;
        let b = this.Box();
        NMLog.Info("corner|vanilla|root " + NameToString(this.root.GetName()) + "|box "
            + (IsDefined(b) ? FloatToStringPrec(b.minX, 0) + "," + FloatToStringPrec(b.minY, 0) + " " + FloatToStringPrec(b.maxX - b.minX, 0)
                + "x" + FloatToStringPrec(b.maxY - b.minY, 0) : "-"));
        let comp = this.root as inkCompoundWidget;
        if !IsDefined(comp) { return; }
        let i = 0;
        while i < comp.GetNumChildren() {
            let w = comp.GetWidgetByIndex(i);
            NMLog.Info("corner|vanilla|child " + IntToString(i) + "|" + NameToString(w.GetName()) + "|" + NameToString(w.GetClassName())
                + "|vis " + (w.IsVisible() ? "1" : "0") + "|op " + FloatToStringPrec(w.GetOpacity(), 2));
            i += 1;
        }
    }

    private func IndexOf(w: ref<inkWidget>) -> Int32 {
        let i = 0;
        while i < ArraySize(this.faded) {
            let h: ref<inkWidget> = this.faded[i];
            if Equals(h, w) { return i; }
            i += 1;
        }
        return -1;
    }
}

@addMethod(MinimapContainerController)
public func NMRoot() -> wref<inkWidget> {
    return this.GetRootWidget();
}
