module OverlayMap

public abstract class NMUi {
    public static func Canvas(parent: wref<inkCompoundWidget>, x: Float, y: Float, w: Float, h: Float) -> ref<inkCanvas> {
        let c = new inkCanvas();
        c.SetAnchor(inkEAnchor.TopLeft);
        c.SetSize(new Vector2(w, h));
        c.SetTranslation(new Vector2(x, y));
        c.SetInteractive(false);
        c.Reparent(parent);
        return c;
    }

    public static func Rect(parent: wref<inkCompoundWidget>, x: Float, y: Float, w: Float, h: Float, color: HDRColor, opacity: Float) -> ref<inkRectangle> {
        let r = new inkRectangle();
        r.SetAnchor(inkEAnchor.TopLeft);
        r.SetSize(new Vector2(w, h));
        r.SetTranslation(new Vector2(x, y));
        r.SetTintColor(color);
        r.SetOpacity(opacity);
        r.SetInteractive(false);
        r.Reparent(parent);
        return r;
    }

    // Square image from the OverlayMap UI atlas. centered=true positions the image's center at (x, y).
    public static func Image(parent: wref<inkCompoundWidget>, part: CName, x: Float, y: Float, size: Float, color: HDRColor, centered: Bool) -> ref<inkImage> {
        let img = new inkImage();
        img.SetAnchor(inkEAnchor.TopLeft);
        img.SetAtlasResource(NMTheme.UiAtlas());
        img.SetTexturePart(part);
        img.SetSize(new Vector2(size, size));
        if centered {
            img.SetAnchorPoint(new Vector2(0.5, 0.5));
        }
        img.SetTranslation(new Vector2(x, y));
        img.SetTintColor(color);
        img.SetInteractive(false);
        img.Reparent(parent);
        return img;
    }

    // Image from the hologram atlas (overlaymap\\ui\\holo.inkatlas), stretched to w x h, or tiled when tile != NoTile
    // (the part then repeats at its native size over the widget). Tint and opacity are set once; nothing updates per frame.
    public static func HoloImage(parent: wref<inkCompoundWidget>, part: CName, x: Float, y: Float, w: Float, h: Float, color: HDRColor, opacity: Float, tile: inkBrushTileType) -> ref<inkImage> {
        let img = new inkImage();
        img.SetAnchor(inkEAnchor.TopLeft);
        img.SetAtlasResource(NMTheme.HoloAtlas());
        img.SetTexturePart(part);
        img.SetBrushTileType(tile);
        img.SetSize(new Vector2(w, h));
        img.SetTranslation(new Vector2(x, y));
        img.SetTintColor(color);
        img.SetOpacity(opacity);
        img.SetInteractive(false);
        img.Reparent(parent);
        return img;
    }

    // Keycap chip (spec 6), shared by the sidebar card and the hint bar: the key in an outlined box (fill HoloHighlight
    // @ NMTheme.KeycapFillOpacity, 1 px edge @ KeycapEdgeOpacity), the label beside it, drawn at the parent's top-left.
    // Returns the width used (KeycapWidth: ink lays text out later). scale defaults to 1 (4K), theme to cyan.
    public static func Keycap(parent: ref<inkCompoundWidget>, key: String, label: String, opt scale: Float, opt theme: Int32) -> Float {
        let s = scale > 0.0 ? scale : 1.0;
        let hi = NMTheme.HoloHighlight(theme);
        let kw = NMUi.KeyBoxWidth(key, s);
        let kh = NMUi.KeycapHeight() * s;
        let e = 2.0 * s;   // 1 px at 1080p
        let eo = NMTheme.KeycapEdgeOpacity();
        NMUi.Rect(parent, 0.0, 0.0, kw, kh, hi, NMTheme.KeycapFillOpacity());
        NMUi.Rect(parent, 0.0, 0.0, kw, e, hi, eo);
        NMUi.Rect(parent, 0.0, kh - e, kw, e, hi, eo);
        NMUi.Rect(parent, 0.0, e, e, kh - 2.0 * e, hi, eo);
        NMUi.Rect(parent, kw - e, e, e, kh - 2.0 * e, hi, eo);
        let k = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(26.0 * s), NMTheme.HeaderTitle(theme));
        k.SetAnchorPoint(new Vector2(0.5, 0.0));   // centred: the box width is an estimate, the text's is not
        k.SetTranslation(new Vector2(kw * 0.5, 8.0 * s));
        k.SetTracking(Cast<Int32>(NMUi.KeyTracking() * s));   // Rajdhani's space is narrow: "8 4 6 2" read as "8462"
        k.SetText(key);
        NMUi.KeyLabel(parent, label, kw + NMUi.KeycapGap() * s, s, theme);
        return NMUi.KeycapWidth(key, label, s);
    }

    public static func KeycapHeight() -> Float { return 46.0; }   // 4K units
    public static func KeycapGap() -> Float { return 16.0; }      // 4K units between the box and its label

    public static func KeyTracking() -> Float { return 4.0; }   // 4K units of letter spacing in a keycap

    // Estimated widths at scale s (Rajdhani caps at 0.55 em, see NMTooltip.FitChars; a space is about 0.25 em).
    public static func KeyBoxWidth(key: String, s: Float) -> Float {
        let n = StrLen(key);
        let spaces = 0;
        let i = 0;
        while i < n {
            if Equals(StrMid(key, i, 1), " ") { spaces += 1; }
            i += 1;
        }
        return (24.0 + 17.0 * Cast<Float>(n - spaces) + 7.0 * Cast<Float>(spaces) + NMUi.KeyTracking() * Cast<Float>(n)) * s;
    }
    public static func KeyLabelWidth(label: String, s: Float) -> Float {
        return Cast<Float>(StrLen(label)) * (28.0 * 0.55 + 3.0) * s;
    }
    public static func KeycapWidth(key: String, label: String, s: Float) -> Float {
        return NMUi.KeyBoxWidth(key, s) + NMUi.KeycapGap() * s + NMUi.KeyLabelWidth(label, s);
    }

    // A keycap's label (Medium 28, letter-spaced, uppercase) at x; also the hint bar's plain text.
    public static func KeyLabel(parent: ref<inkCompoundWidget>, label: String, x: Float, s: Float, opt theme: Int32) -> ref<inkText> {
        let t = NMUi.Text(parent, NMTheme.BodyFont(), n"Medium", Cast<Int32>(28.0 * s), NMTheme.HoloText(theme));
        t.SetTranslation(new Vector2(x, 7.0 * s));
        t.SetTracking(Cast<Int32>(3.0 * s));
        t.SetText(StrUpper(label));
        return t;
    }

    public static func Text(parent: wref<inkCompoundWidget>, font: String, style: CName, size: Int32, color: HDRColor) -> ref<inkText> {
        let t = new inkText();
        t.SetAnchor(inkEAnchor.TopLeft);
        t.SetFontFamily(font);
        t.SetFontStyle(style);
        t.SetFontSize(size);
        t.SetTintColor(color);
        t.SetInteractive(false);
        t.Reparent(parent);
        return t;
    }
}
