module NightMap

// Hover tooltip next to the selected marker. Fixed width, content-fitted height, 4K units * scale.
// Content is rebuilt only on selection/data change; Reposition runs only after a relayout. No per-frame work.
public class NMTooltip {
    private let s: Float;
    private let mapW: Float;
    private let mapH: Float;
    private let w: Float;
    private let h: Float;
    private let shown: Bool;
    private let root: ref<inkCanvas>;
    private let bg: ref<inkRectangle>;
    private let bar: ref<inkRectangle>;
    private let category: ref<inkText>;
    private let title: ref<inkText>;
    private let rowKey: array<ref<inkText>>;
    private let rowVal: array<ref<inkText>>;
    private let actBox: ref<inkRectangle>;
    private let actKey: ref<inkText>;
    private let actLabel: ref<inkText>;
    private let docked: Bool;   // lives at a fixed spot in the sidebar instead of following the marker
    private let dock: Vector2;

    public static func MaxRows() -> Int32 { return 3; }
    public static func Width() -> Float { return 620.0; }

    // Top-left corner of a w*h tooltip for a marker at (mx, my): right of the marker (left edge at mx + 60*s), vertically
    // centred on it; flipped to the left side when it would cross the right edge; clamped inside [0, mapH] vertically.
    public static func Place(mx: Float, my: Float, w: Float, h: Float, mapW: Float, mapH: Float, s: Float) -> Vector2 {
        let x = mx + 60.0 * s;
        if x + w > mapW {
            x = mx - 60.0 * s - w;
        }
        let y = my - h * 0.5;
        if y + h > mapH {
            y = mapH - h;
        }
        if y < 0.0 {
            y = 0.0;
        }
        return new Vector2(x, y);
    }

    // "abc…" when longer than max characters.
    public static func Truncate(str: String, max: Int32) -> String {
        if StrLen(str) <= max {
            return str;
        }
        return StrLeft(str, max - 1) + "…";
    }

    public static func Create(parent: ref<inkCanvas>, mapW: Float, mapH: Float, scale: Float) -> ref<NMTooltip> {
        let t = new NMTooltip();
        let s = scale;
        t.s = s;
        t.mapW = mapW;
        t.mapH = mapH;
        t.w = NMTooltip.Width() * s;
        t.root = NMUi.Canvas(parent, 0.0, 0.0, t.w, 100.0 * s);
        t.root.SetVisible(false);
        t.bg = NMUi.Rect(t.root, 0.0, 0.0, t.w, 100.0 * s, NMTheme.CardBg(), NMTheme.CardOpacity());
        t.bar = NMUi.Rect(t.root, 0.0, 0.0, 6.0 * s, 100.0 * s, NMTheme.Cyan(), 1.0);
        t.category = NMUi.Text(t.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(28.0 * s), NMTheme.Pink());
        t.title = NMUi.Text(t.root, NMTheme.BodyFont(), n"Bold", Cast<Int32>(44.0 * s), NMTheme.Text());
        let i = 0;
        while i < NMTooltip.MaxRows() {
            let k = NMUi.Text(t.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(28.0 * s), NMTheme.Muted());
            let v = NMUi.Text(t.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(30.0 * s), NMTheme.Text());
            ArrayPush(t.rowKey, k);
            ArrayPush(t.rowVal, v);
            i += 1;
        }
        t.actBox = NMUi.Rect(t.root, 0.0, 0.0, 10.0 * s, 46.0 * s, NMTheme.Cyan(), 0.15);
        t.actKey = NMUi.Text(t.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(26.0 * s), NMTheme.Cyan());
        t.actLabel = NMUi.Text(t.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(28.0 * s), NMTheme.Text());
        t.Hide();
        return t;
    }

    // A tooltip at a fixed spot of w wide (the sidebar's marker details).
    public static func CreateDocked(parent: ref<inkCanvas>, x: Float, y: Float, w: Float, scale: Float) -> ref<NMTooltip> {
        let t = NMTooltip.Create(parent, w, 100000.0, scale);
        t.w = w;
        t.docked = true;
        t.dock = new Vector2(x, y);
        t.root.SetTranslation(t.dock);
        t.root.SetSize(new Vector2(w, 100.0 * scale));
        t.bg.SetSize(new Vector2(w, 100.0 * scale));
        return t;
    }

    public func Origin() -> Vector2 { return this.root.GetTranslation(); }
    public func CurrentWidth() -> Float { return this.w; }

    public func IsShown() -> Bool { return this.shown; }
    public func Height() -> Float { return this.h; }
    public func RowsShown() -> Int32 {
        let n = 0;
        let i = 0;
        while i < NMTooltip.MaxRows() {
            if this.rowKey[i].IsVisible() { n += 1; }
            i += 1;
        }
        return n;
    }

    public func Hide() {
        this.shown = false;
        this.root.SetVisible(false);
    }

    // Lays out the visible parts top to bottom and sizes the box to fit.
    private func Layout(hasCat: Bool, rows: Int32, hasAct: Bool) {
        let s = this.s;
        let x = 28.0 * s;
        let y = 16.0 * s;
        this.category.SetVisible(hasCat);
        if hasCat {
            this.category.SetTranslation(new Vector2(x, y));
            y += 38.0 * s;
        }
        this.title.SetTranslation(new Vector2(x, y));
        y += 62.0 * s;
        let i = 0;
        while i < NMTooltip.MaxRows() {
            let on = i < rows;
            this.rowKey[i].SetVisible(on);
            this.rowVal[i].SetVisible(on);
            if on {
                this.rowKey[i].SetTranslation(new Vector2(x, y));
                this.rowVal[i].SetTranslation(new Vector2(x + 190.0 * s, y - 2.0 * s));
                y += 40.0 * s;
            }
            i += 1;
        }
        this.actBox.SetVisible(hasAct);
        this.actKey.SetVisible(hasAct);
        this.actLabel.SetVisible(hasAct);
        if hasAct {
            y += 8.0 * s;
            this.actBox.SetTranslation(new Vector2(x, y));
            this.actKey.SetTranslation(new Vector2(x + 10.0 * s, y + 8.0 * s));
            y += 54.0 * s;
        }
        this.h = y + 12.0 * s;
        this.root.SetSize(new Vector2(this.w, this.h));
        this.bg.SetSize(new Vector2(this.w, this.h));
        this.bar.SetSize(new Vector2(6.0 * this.s, this.h));
    }

    // First action: key chip + label. Chip width follows the key text length (about 17 units per character).
    private func SetAction(key: String, label: String) {
        let s = this.s;
        let cw = (24.0 + 17.0 * Cast<Float>(StrLen(key))) * s;
        this.actBox.SetSize(new Vector2(cw, 46.0 * s));
        this.actKey.SetText(key);
        this.actLabel.SetText(StrUpper(label));
        let p = this.actBox.GetTranslation();
        this.actLabel.SetTranslation(new Vector2(p.X + cw + 16.0 * s, p.Y + 7.0 * s));
    }

    public func ShowDetails(d: ref<NightMapDetails>, color: HDRColor) {
        let n = Min(ArraySize(d.rowKeys), NMTooltip.MaxRows());
        let hasAct = ArraySize(d.actionKeys) > 0;
        this.Layout(true, n, hasAct);
        this.category.SetText(StrUpper(d.category));
        this.category.SetTintColor(color);
        this.bar.SetTintColor(color);
        this.title.SetText(NMTooltip.Truncate(StrUpper(d.title), 22));
        let i = 0;
        while i < n {
            this.rowKey[i].SetText(StrUpper(NMTooltip.Truncate(d.rowKeys[i], 12)));
            this.rowVal[i].SetText(NMTooltip.Truncate(d.rowValues[i], 24));
            i += 1;
        }
        if hasAct {
            this.SetAction(d.actionKeys[0], d.actionLabels[0]);
        }
        this.Present();
    }

    public func ShowCluster(total: Int32, actKey: String) {
        this.Layout(false, 0, true);
        this.bar.SetTintColor(NMTheme.Cyan());
        this.title.SetText(ToString(total) + " MARKERS");
        this.SetAction(actKey, "Zoom");
        this.Present();
    }

    private func Present() {
        this.shown = true;
        this.root.SetVisible(true);
    }

    // Moves the box next to the marker at (mx, my) in map-area coordinates.
    public func Reposition(mx: Float, my: Float) {
        if !this.shown || this.docked {
            return;
        }
        this.root.SetTranslation(NMTooltip.Place(mx, my, this.w, this.h, this.mapW, this.mapH, this.s));
    }
}
