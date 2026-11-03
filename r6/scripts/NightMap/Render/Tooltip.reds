module NightMap

// Marker details card (spec 6), docked at the top of the sidebar: HOVERED label, the icon on its plate (a hex chip for
// our pins) beside the title and category line, a divider, the description (at most three lines), up to MaxRows rows
// and up to two actions as keycaps. 4K units * scale. Content is rebuilt only on selection/data change; Reposition
// runs only after a relayout. No per-frame work. The undocked form (a box next to the marker) is kept for tests.
public class NMTooltip {
    private let s: Float;
    private let theme: Int32;
    private let mapW: Float;
    private let mapH: Float;
    private let w: Float;
    private let h: Float;
    private let shown: Bool;
    private let root: ref<inkCanvas>;
    private let bg: ref<inkRectangle>;
    private let bar: ref<inkRectangle>;
    private let label: ref<inkText>;
    private let plate: ref<inkImage>;
    private let icon: ref<inkImage>;
    private let iconKey: String;
    private let iconPart: CName;
    private let category: ref<inkText>;
    private let title: ref<inkText>;
    private let divider: ref<inkRectangle>;
    private let desc: ref<inkText>;
    private let rowKey: array<ref<inkText>>;
    private let rowVal: array<ref<inkText>>;
    private let act: array<ref<inkCanvas>>;
    private let actKey: array<String>;
    private let actLabel: array<String>;
    private let docked: Bool;   // lives at a fixed spot in the sidebar instead of following the marker
    private let dock: Vector2;

    public static func MaxRows() -> Int32 { return 3; }
    public static func MaxActions() -> Int32 { return 2; }
    public static func MaxDescLines() -> Int32 { return 3; }
    public static func Width() -> Float { return 620.0; }
    public static func DescLineH() -> Float { return 40.0; }   // 4K units per description line
    public static func DescGap() -> Float { return 14.0; }     // 4K units under the description
    public static func IconBox() -> Float { return 104.0; }    // 4K units: the plate (or chip) beside the title

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

    // Uppercase characters of a font size (plus letter spacing) that fit a width: 0.55 em per character (Rajdhani Bold
    // caps measure about 0.51 em in-game).
    public static func FitChars(width: Float, size: Float, tracking: Float) -> Int32 {
        return Max(1, FloorF(width / (size * 0.55 + tracking)));
    }

    // Sentence-case characters per wrapped description line, less a word's slack for the break.
    private static func DescPerLine(width: Float, size: Float) -> Int32 {
        return Max(1, FloorF(width / (size * 0.45)) - 6);
    }

    public static func Create(parent: ref<inkCanvas>, mapW: Float, mapH: Float, scale: Float, opt theme: Int32) -> ref<NMTooltip> {
        let t = new NMTooltip();
        let s = scale;
        t.s = s;
        t.theme = theme;
        t.mapW = mapW;
        t.mapH = mapH;
        t.w = NMTooltip.Width() * s;
        t.root = NMUi.Canvas(parent, 0.0, 0.0, t.w, 100.0 * s);
        t.root.SetVisible(false);
        t.bg = NMUi.Rect(t.root, 0.0, 0.0, t.w, 100.0 * s, NMTheme.CardBg(t.theme), NMTheme.CardOpacity());
        t.bar = NMUi.Rect(t.root, 0.0, 0.0, 6.0 * s, 100.0 * s, NMTheme.Cyan(), 1.0);
        let hi = NMTheme.HoloHighlight(theme);
        t.label = NMUi.Text(t.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(28.0 * s), NMTheme.CardLabel(theme));
        t.label.SetTracking(Cast<Int32>(4.0 * s));
        t.label.SetText("HOVERED");
        t.plate = NMUi.Image(t.root, n"plate", 0.0, 0.0, NMTooltip.IconBox() * s, hi, false);
        t.icon = NMUi.Image(t.root, n"icon_dot", 0.0, 0.0, 44.0 * s, hi, true);
        t.title = NMUi.Text(t.root, NMTheme.BodyFont(), n"Bold", Cast<Int32>(52.0 * s), new HDRColor(1.0, 1.0, 1.0, 1.0));
        t.category = NMUi.Text(t.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(28.0 * s), NMTheme.Pink());
        t.category.SetTracking(Cast<Int32>(3.0 * s));
        t.divider = NMUi.Rect(t.root, 0.0, 0.0, t.w, 2.0 * s, hi, NMTheme.DividerOpacity());
        t.desc = NMUi.Text(t.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(32.0 * s), NMTheme.CardBody(theme));
        let i = 0;
        while i < NMTooltip.MaxRows() {
            let k = NMUi.Text(t.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(28.0 * s), NMTheme.Muted());
            let v = NMUi.Text(t.root, NMTheme.BodyFont(), n"Medium", Cast<Int32>(30.0 * s), NMTheme.Text());
            ArrayPush(t.rowKey, k);
            ArrayPush(t.rowVal, v);
            i += 1;
        }
        i = 0;
        while i < NMTooltip.MaxActions() {
            ArrayPush(t.act, NMUi.Canvas(t.root, 0.0, 0.0, 10.0, 10.0));
            ArrayPush(t.actKey, "\n");   // sentinel: no keycap built yet
            ArrayPush(t.actLabel, "\n");
            i += 1;
        }
        t.Hide();
        return t;
    }

    // A tooltip at a fixed spot of w wide (the sidebar's marker card): no box of its own, it sits on the sidebar glass.
    public static func CreateDocked(parent: ref<inkCanvas>, x: Float, y: Float, w: Float, scale: Float, opt theme: Int32) -> ref<NMTooltip> {
        let t = NMTooltip.Create(parent, w, 100000.0, scale, theme);
        t.w = w;
        t.docked = true;
        t.dock = new Vector2(x, y);
        t.root.SetTranslation(t.dock);
        t.root.SetSize(new Vector2(w, 100.0 * scale));
        t.bg.SetVisible(false);
        t.bar.SetVisible(false);
        return t;
    }

    public func Origin() -> Vector2 { return this.root.GetTranslation(); }
    public func CurrentWidth() -> Float { return this.w; }

    public func IsShown() -> Bool { return this.shown; }
    public func Height() -> Float { return this.h; }
    public func DescriptionShown() -> Bool { return this.desc.IsVisible(); }
    public func DescriptionText() -> String { return this.desc.GetText(); }
    public func RowsShown() -> Int32 {
        let n = 0;
        let i = 0;
        while i < NMTooltip.MaxRows() {
            if this.rowKey[i].IsVisible() { n += 1; }
            i += 1;
        }
        return n;
    }
    public func KeycapsShown() -> Int32 {
        let n = 0;
        for a in this.act {
            if a.IsVisible() { n += 1; }
        }
        return n;
    }

    public func Hide() {
        this.shown = false;
        this.root.SetVisible(false);
    }

    public func ShowDetails(d: ref<NightMapDetails>, color: HDRColor) {
        this.ShowCard(d, color, null, color, false);
    }

    // The card for a marker: icon (null = none) drawn on a plate tinted iconTint, or on a hex chip in the category colour.
    public func ShowCard(d: ref<NightMapDetails>, color: HDRColor, icon: ref<NMIconRef>, iconTint: HDRColor, hex: Bool) {
        let s = this.s;
        let x = this.docked ? 0.0 : 28.0 * s;
        let y = this.docked ? 0.0 : 16.0 * s;
        let cw = this.w - (this.docked ? 0.0 : 56.0 * s);   // content width
        this.label.SetTranslation(new Vector2(x, y));
        y += 48.0 * s;

        let hasIcon = IsDefined(icon);
        this.plate.SetVisible(hasIcon);
        this.icon.SetVisible(hasIcon);
        let tx = x;
        if hasIcon {
            let box = NMTooltip.IconBox() * s;
            this.plate.SetTexturePart(hex ? n"chip" : n"plate");
            this.plate.SetTintColor(hex ? color : iconTint);
            this.plate.SetTranslation(new Vector2(x, y));
            if NotEquals(this.iconKey, icon.key) {
                this.icon.SetAtlasResource(icon.atlas);
                this.iconKey = icon.key;
                this.iconPart = n"";
            }
            if NotEquals(this.iconPart, icon.part) {
                this.icon.SetTexturePart(icon.part);
                this.iconPart = icon.part;
            }
            let ik = hex ? NMTheme.IconSize() / NMTheme.ChipSize() : NMTheme.VanillaIconSize() / NMTheme.PlateSize();
            this.icon.SetSize(new Vector2(box * ik, box * ik));
            this.icon.SetTintColor(iconTint);
            this.icon.SetTranslation(new Vector2(x + box * 0.5, y + box * 0.5));
            tx = x + box + 24.0 * s;
        }
        let tw = cw - (tx - x);
        this.title.SetText(NMTooltip.Truncate(StrUpper(d.title), NMTooltip.FitChars(tw, 52.0 * s, 0.0)));
        this.title.SetTranslation(new Vector2(tx, y));
        let cat = StrLen(d.subtitle) > 0 ? d.category + " · " + d.subtitle : d.category;
        this.category.SetText(NMTooltip.Truncate(StrUpper(cat), NMTooltip.FitChars(tw, 28.0 * s, 3.0 * s)));
        this.category.SetTintColor(color);
        this.category.SetVisible(StrLen(cat) > 0);
        this.category.SetTranslation(new Vector2(tx, y + 64.0 * s));
        this.bar.SetTintColor(color);
        y += 112.0 * s;

        this.divider.SetTranslation(new Vector2(x, y));
        this.divider.SetSize(new Vector2(cw, 2.0 * s));
        y += 24.0 * s;

        let hasDesc = StrLen(d.description) > 0;
        this.desc.SetVisible(hasDesc);
        if hasDesc {
            let per = NMTooltip.DescPerLine(cw, 32.0 * s);
            let text = NMTooltip.Truncate(d.description, per * NMTooltip.MaxDescLines());
            let lines = Min(NMTooltip.MaxDescLines(), (StrLen(text) + per - 1) / per);
            this.desc.SetText(text);
            this.desc.SetWrappingAtPosition(cw);
            this.desc.SetTranslation(new Vector2(x, y));
            y += Cast<Float>(lines) * NMTooltip.DescLineH() * s + NMTooltip.DescGap() * s;
        }

        let n = Min(ArraySize(d.rowKeys), NMTooltip.MaxRows());
        let vw = cw - 200.0 * s;
        let i = 0;
        while i < NMTooltip.MaxRows() {
            let on = i < n;
            this.rowKey[i].SetVisible(on);
            this.rowVal[i].SetVisible(on);
            if on {
                this.rowKey[i].SetText(StrUpper(NMTooltip.Truncate(d.rowKeys[i], 12)));
                this.rowVal[i].SetText(NMTooltip.Truncate(d.rowValues[i], NMTooltip.FitChars(vw, 30.0 * s, 0.0)));
                this.rowKey[i].SetTranslation(new Vector2(x, y));
                this.rowVal[i].SetTranslation(new Vector2(x + 200.0 * s, y - 2.0 * s));
                y += 42.0 * s;
            }
            i += 1;
        }

        let na = Min(ArraySize(d.actionKeys), NMTooltip.MaxActions());
        if na > 0 {
            y += 10.0 * s;
        }
        i = 0;
        while i < NMTooltip.MaxActions() {
            let on = i < na;
            this.act[i].SetVisible(on);
            if on {
                if NotEquals(this.actKey[i], d.actionKeys[i]) || NotEquals(this.actLabel[i], d.actionLabels[i]) {
                    this.act[i].RemoveAllChildren();
                    NMUi.Keycap(this.act[i], d.actionKeys[i], d.actionLabels[i], s, this.theme);
                    this.actKey[i] = d.actionKeys[i];
                    this.actLabel[i] = d.actionLabels[i];
                }
                this.act[i].SetTranslation(new Vector2(x, y));
                y += 58.0 * s;
            }
            i += 1;
        }

        this.h = y + (this.docked ? 0.0 : 12.0 * s);
        this.root.SetSize(new Vector2(this.w, this.h));
        this.bg.SetSize(new Vector2(this.w, this.h));
        this.bar.SetSize(new Vector2(6.0 * s, this.h));
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
