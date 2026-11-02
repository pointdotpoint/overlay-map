module NightMap

// Owns the corner's lifetime: create / rebuild / destroy from the settings and the vanilla minimap probe, and the
// expand / collapse hand-over of the zoom. NightMapSystem delegates here; the self-tests drive it with a fake minimap.
public class NMCornerHost {
    public let corner: ref<NMCorner>;
    public let probe: ref<NMMinimapProbe>;
    public let cfg: ref<NMCornerConfig>;
    public let mpp: Float;          // the corner zoom; 0 = never set (NMCorner.DefaultMpp)
    public let expanded: Bool;
    private let box: ref<NMRect>;

    public func Active() -> Bool { return IsDefined(this.corner); }

    // The next Sync rebuilds the corner (colours changed under it).
    public func Invalidate() {
        if this.Active() { this.cfg = new NMCornerConfig(); }
    }

    // 0 nothing, 1 created, 2 destroyed, 3 rebuilt. probe: the live minimap (null while it has not attached).
    public func Sync(s: ref<NightMapSettings>, window: wref<inkCompoundWidget>, probe: ref<NMMinimapProbe>, api: ref<NightMap>) -> Int32 {
        if !IsDefined(s) || !s.replaceMinimap {
            if this.Active() || IsDefined(this.probe) {
                let had = this.Active();
                this.Detach();
                return had ? 2 : 0;
            }
            return 0;
        }
        let cfg = NMCornerConfig.From(s);
        if this.Active() {
            let box = this.probe.Box();
            if cfg.Same(this.cfg) && NMCornerHost.SameBox(box, this.box) {
                return 0;
            }
            let keep = this.probe;
            this.DestroyCorner();
            if this.Create(cfg, window, keep, api) { return 3; }
            // No box this poll: give the vanilla minimap back rather than leave it faded with no corner.
            keep.Restore();
            this.probe = null;
            return 2;
        }
        return this.Create(cfg, window, probe, api) ? 1 : 0;
    }

    private func Create(cfg: ref<NMCornerConfig>, window: wref<inkCompoundWidget>, probe: ref<NMMinimapProbe>, api: ref<NightMap>) -> Bool {
        if !IsDefined(probe) { return false; }
        // Drawn inside the vanilla minimap's root, in its local units: wherever the game or a HUD mod puts the minimap,
        // the corner is there, at its size, and hidden with it. Those units are the HUD's 3840x2160 space.
        let parent = probe.Root() as inkCompoundWidget;
        if !IsDefined(parent) { return false; }
        let box = probe.Box();
        let size = new Vector2(3840.0, 2160.0);
        let layout = NMCornerLayout.Compute(box, cfg.style, cfg.scale, cfg.textSize, size.X, size.Y);
        if !IsDefined(layout) || !NMCornerHost.Plausible(box, size) { return false; }
        this.probe = probe;
        this.cfg = cfg;
        this.box = box;
        this.corner = NMCorner.Build(parent, layout, cfg, api, this.mpp);
        this.corner.SetShown(!this.expanded);
        this.probe.Fade();
        return true;
    }

    // Straight-line metres from V to the end of the quest route (or the tracked route); -1 with no route.
    public static func ObjectiveDistance(r: ref<NMGpsReading>, p: Vector4) -> Float {
        if !IsDefined(r) { return -1.0; }
        let pts = ArraySize(r.quest) > 0 ? r.quest : r.tracked;
        let n = ArraySize(pts);
        if n == 0 { return -1.0; }
        let e = pts[n - 1];
        let dx = e.X - p.X;
        let dy = e.Y - p.Y;
        return SqrtF(dx * dx + dy * dy);
    }

    // The vanilla minimap's box is a corner widget: anything wider or taller than a third of the window is some other
    // canvas (a HUD mod, a full-screen root) and is not drawn over.
    public static func Plausible(box: ref<NMRect>, win: Vector2) -> Bool {
        return IsDefined(box) && box.maxX - box.minX <= win.X / 3.0 && box.maxY - box.minY <= win.Y / 3.0;
    }

    public static func SameBox(a: ref<NMRect>, b: ref<NMRect>) -> Bool {
        if !IsDefined(a) || !IsDefined(b) { return !IsDefined(a) && !IsDefined(b); }
        return AbsF(a.minX - b.minX) < 1.0 && AbsF(a.minY - b.minY) < 1.0 && AbsF(a.maxX - b.maxX) < 1.0 && AbsF(a.maxY - b.maxY) < 1.0;
    }

    // The expanded panel opens: hide the corner; the panel starts at the corner's zoom (0 = the panel's own default).
    public func Expanding() -> Float {
        this.expanded = true;
        if this.Active() { this.corner.SetShown(false); }
        return this.mpp;
    }

    // The expanded panel closed (any path): take its zoom, show the corner again.
    public func Collapsed(panelMpp: Float) {
        this.expanded = false;
        if panelMpp > 0.0 { this.mpp = panelMpp; }
        if this.Active() {
            this.corner.SetMpp(this.mpp);
            this.corner.SetShown(true);
        }
    }

    // Corner gone, vanilla minimap back as it was.
    public func Detach() {
        if IsDefined(this.probe) { this.probe.Restore(); }
        this.DestroyCorner();
        this.probe = null;
    }

    private func DestroyCorner() {
        if IsDefined(this.corner) { this.corner.Destroy(); }
        this.corner = null;
        this.cfg = null;
        this.box = null;
    }
}
