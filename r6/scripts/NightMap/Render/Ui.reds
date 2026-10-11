module NightMap

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

    // Square image from the NightMap UI atlas. centered=true positions the image's center at (x, y).
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
