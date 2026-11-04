module OverlayMap

// The live vanilla minimap: its box, whether the game shows it, and fading its contents. The container root is never
// faded: the game's own visibility/opacity on it stays readable (FINDINGS "Hiding"), and the corner is drawn inside it.
// Its other children are faded, by opacity only, so the minimap keeps running (GPS routes, mirrored markers).
public class NMMinimapProbe {
    private let root: wref<inkWidget>;
    private let window: wref<inkCompoundWidget>;
    private let faded: array<wref<inkWidget>>;
    private let opacity: array<Float>;
    private let logged: Bool;
    private let target: Float;      // opacity the vanilla children are faded to (0 unless the harness asks otherwise)
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

    // The minimap root's own box, in its local units (the corner is drawn inside the root, FINDINGS "Placement");
    // null when missing or under 8 units.
    public func Box() -> ref<NMRect> {
        if this.fixed { return this.fixedBox; }
        if !IsDefined(this.root) { return null; }
        let size = this.root.GetSize();
        if size.X < 8.0 || size.Y < 8.0 { return null; }
        return NMRect.Create(0.0, 0.0, size.X, size.Y);
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
            if IsDefined(w) && !Equals(w.GetName(), n"OverlayMapCorner") {
                if this.IndexOf(w) < 0 {
                    ArrayPush(this.faded, w);
                    ArrayPush(this.opacity, w.GetOpacity());
                }
                if w.GetOpacity() != this.target { w.SetOpacity(this.target); }
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

    public func SetFadeTarget(op: Float) { this.target = op; }

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
