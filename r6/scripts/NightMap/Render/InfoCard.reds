module NightMap

// Docked card (right column). Fixed layout in 4K units * scale.
public class NMInfoCard {
    private let s: Float;
    private let pad: Float;
    private let category: ref<inkText>;
    private let title: ref<inkText>;
    private let subtitle: ref<inkText>;
    private let divider: ref<inkRectangle>;
    private let rowKey: array<ref<inkText>>;
    private let rowVal: array<ref<inkText>>;
    private let rowChip: array<ref<inkImage>>;
    private let rowIcon: array<ref<inkImage>>;
    private let desc: ref<inkText>;
    private let actBox: array<ref<inkRectangle>>;
    private let actKey: array<ref<inkText>>;
    private let actLabel: array<ref<inkText>>;
    private let empty: ref<inkText>;

    public static func Create(parent: ref<inkCanvas>, width: Float, scale: Float) -> ref<NMInfoCard> {
        let c = new NMInfoCard();
        let s = scale;
        c.s = s;
        c.pad = 62.0 * s;
        c.category = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(34.0 * s), NMTheme.Pink());
        c.category.SetTranslation(new Vector2(c.pad, 96.0 * s));
        c.title = NMUi.Text(parent, NMTheme.HeadingFont(), n"Bold", Cast<Int32>(58.0 * s), NMTheme.Text());
        c.title.SetTranslation(new Vector2(c.pad, 150.0 * s));
        c.subtitle = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(36.0 * s), NMTheme.Cyan());
        c.subtitle.SetTranslation(new Vector2(c.pad, 240.0 * s));
        c.divider = NMUi.Rect(parent, c.pad, 300.0 * s, width - 2.0 * c.pad, 2.0 * s, NMTheme.Cyan(), 0.35);
        let i = 0;
        while i < 6 {
            let y = 360.0 * s + Cast<Float>(i) * 80.0 * s;
            let k = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(31.0 * s), NMTheme.Muted());
            k.SetTranslation(new Vector2(c.pad, y));
            let v = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(36.0 * s), NMTheme.Text());
            v.SetTranslation(new Vector2(c.pad + 312.0 * s, y));
            let chip = NMUi.Image(parent, n"mini", c.pad + 26.0 * s, y + 20.0 * s, NMTheme.MiniSize() * 0.7 * s, NMTheme.Cyan(), true);
            let icon = NMUi.Image(parent, n"icon_dot", c.pad + 26.0 * s, y + 20.0 * s, NMTheme.IconSize() * 0.6 * s, NMTheme.Cyan(), true);
            ArrayPush(c.rowKey, k);
            ArrayPush(c.rowVal, v);
            ArrayPush(c.rowChip, chip);
            ArrayPush(c.rowIcon, icon);
            i += 1;
        }
        c.desc = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(31.0 * s), NMTheme.Text());
        c.desc.SetTranslation(new Vector2(c.pad, 860.0 * s));
        c.desc.SetWrapping(true, width - 2.0 * c.pad);
        c.desc.SetOpacity(0.8);
        i = 0;
        while i < 3 {
            let y = 1060.0 * s + Cast<Float>(i) * 100.0 * s;
            ArrayPush(c.actBox, NMUi.Rect(parent, c.pad, y, 130.0 * s, 70.0 * s, NMTheme.Cyan(), 0.15));
            let kt = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(30.0 * s), NMTheme.Cyan());
            kt.SetTranslation(new Vector2(c.pad + 16.0 * s, y + 16.0 * s));
            ArrayPush(c.actKey, kt);
            let lt = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(36.0 * s), NMTheme.Text());
            lt.SetTranslation(new Vector2(c.pad + 168.0 * s, y + 14.0 * s));
            ArrayPush(c.actLabel, lt);
            i += 1;
        }
        c.empty = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(34.0 * s), NMTheme.Muted());
        c.empty.SetTranslation(new Vector2(c.pad, 96.0 * s));
        c.empty.SetText("NO SELECTION");
        c.ShowEmpty();
        return c;
    }

    private func SetMain(visible: Bool) {
        this.category.SetVisible(visible);
        this.title.SetVisible(visible);
        this.subtitle.SetVisible(visible);
        this.divider.SetVisible(visible);
        this.empty.SetVisible(!visible);
    }

    private func SetRows(n: Int32, chips: Bool) {
        let i = 0;
        while i < 6 {
            let on = i < n;
            this.rowKey[i].SetVisible(on);
            this.rowVal[i].SetVisible(on);
            this.rowChip[i].SetVisible(on && chips);
            this.rowIcon[i].SetVisible(on && chips);
            let y = 360.0 * this.s + Cast<Float>(i) * 80.0 * this.s;
            this.rowKey[i].SetTranslation(new Vector2(this.pad + (chips ? 70.0 * this.s : 0.0), y));
            i += 1;
        }
    }

    private func SetActions(keys: array<String>, labels: array<String>) {
        let i = 0;
        while i < 3 {
            let on = i < ArraySize(keys);
            this.actBox[i].SetVisible(on);
            this.actKey[i].SetVisible(on);
            this.actLabel[i].SetVisible(on);
            if on {
                this.actKey[i].SetText(keys[i]);
                this.actLabel[i].SetText(StrUpper(labels[i]));
            }
            i += 1;
        }
    }

    public func ShowDetails(d: ref<NightMapDetails>, color: HDRColor) {
        this.SetMain(true);
        this.category.SetText(StrUpper(d.category));
        this.category.SetTintColor(color);
        this.title.SetText(StrUpper(d.title));
        this.subtitle.SetText(d.subtitle);
        let n = Min(ArraySize(d.rowKeys), 6);
        let i = 0;
        while i < n {
            this.rowKey[i].SetText(StrUpper(d.rowKeys[i]));
            this.rowVal[i].SetText(d.rowValues[i]);
            i += 1;
        }
        this.SetRows(n, false);
        this.desc.SetText(d.description);
        this.desc.SetVisible(NotEquals(d.description, ""));
        this.SetActions(d.actionKeys, d.actionLabels);
    }

    public func ShowCluster(total: Int32, cats: array<Int32>, counts: array<Int32>, api: ref<NightMap>, actKey: String) {
        this.SetMain(true);
        this.category.SetText("CLUSTER");
        this.category.SetTintColor(NMTheme.Cyan());
        this.title.SetText(ToString(total) + " LOCATIONS");
        this.subtitle.SetText("");
        let n = Min(ArraySize(cats), 6);
        let i = 0;
        while i < n {
            let g = cats[i];
            let color = api.catColor[g];
            this.rowKey[i].SetText(StrUpper(api.catDisplay[g]));
            this.rowVal[i].SetText(ToString(counts[i]));
            this.rowChip[i].SetTintColor(color);
            this.rowIcon[i].SetTintColor(color);
            if api.catHasIcon[g] {
                this.rowIcon[i].SetAtlasResource(api.catAtlas[g]);
                this.rowIcon[i].SetTexturePart(api.catPart[g]);
            } else {
                this.rowIcon[i].SetAtlasResource(NMTheme.UiAtlas());
                this.rowIcon[i].SetTexturePart(n"icon_dot");
            }
            i += 1;
        }
        this.SetRows(n, true);
        this.desc.SetVisible(false);
        let keys: array<String> = [actKey];
        let labels: array<String> = ["Zoom into cluster"];
        this.SetActions(keys, labels);
    }

    public func ShowEmpty() {
        this.SetMain(false);
        this.SetRows(0, false);
        this.desc.SetVisible(false);
        let none: array<String>;
        this.SetActions(none, none);
    }
}
