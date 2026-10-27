module NightMap

// Fades every other widget in the HUD window to zero opacity while NightMap is open, and gives each its own opacity
// back on close. Opacity, not visibility: the minimap keeps running, and the GPS routes are read from it.
public class NMHudHider {
    private let window: wref<inkCompoundWidget>;
    private let keep: wref<inkWidget>;
    private let hidden: array<wref<inkWidget>>;
    private let opacity: array<Float>;

    public static func Hide(window: wref<inkCompoundWidget>, keep: ref<inkWidget>) -> ref<NMHudHider> {
        let h = new NMHudHider();
        h.window = window;
        h.keep = keep;
        h.Refresh();
        return h;
    }

    // Fades widgets added since, and any a HUD controller faded back in. Cheap; call every few frames.
    public func Refresh() {
        if !IsDefined(this.window) { return; }
        let keep: ref<inkWidget> = this.keep;
        let i = 0;
        while i < this.window.GetNumChildren() {
            let w: ref<inkWidget> = this.window.GetWidget(i);
            if IsDefined(w) && !Equals(w, keep) {
                if this.IndexOf(w) < 0 {
                    ArrayPush(this.hidden, w);
                    ArrayPush(this.opacity, w.GetOpacity());
                }
                if w.GetOpacity() != 0.0 { w.SetOpacity(0.0); }
            }
            i += 1;
        }
    }

    public func Restore() {
        let i = 0;
        while i < ArraySize(this.hidden) {
            let w: ref<inkWidget> = this.hidden[i];
            if IsDefined(w) { w.SetOpacity(this.opacity[i]); }
            i += 1;
        }
        ArrayClear(this.hidden);
        ArrayClear(this.opacity);
    }

    private func IndexOf(w: ref<inkWidget>) -> Int32 {
        let i = 0;
        while i < ArraySize(this.hidden) {
            let h: ref<inkWidget> = this.hidden[i];
            if Equals(h, w) { return i; }
            i += 1;
        }
        return -1;
    }
}
