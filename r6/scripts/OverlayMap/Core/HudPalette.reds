module OverlayMap

// The roles OverlayMap colours play, each answered by one HUD palette slot when "Follow HUD Painter colours" is on.
public enum NMColorRole {
    Accent = 0,
    Highlight = 1,
    Background = 2,
    PanelBg = 3,
    Text = 4,
    Muted = 5,
    Warn = 6,
    Route = 7,
    Enemy = 8,
    Police = 9,
    Player = 10,
    Road = 11,
    Floor = 12,
    Wall = 13,
    FastTravel = 14,
    Relic = 15,
    Count = 16
}

// Reads the game's HUD palette (base\gameplay\gui\common\main_colors.inkstyle, which HUD Painter patches in place) back
// from hidden probe rectangles style-bound to MainColors.* slots. A probe still showing the sentinel tint has not been
// resolved by ink yet: Has() is false and NMTheme keeps today's colour for that role.
public class NMHudPalette {
    private let probes: array<ref<inkRectangle>>;
    private let colors: array<HDRColor>;
    private let known: array<Bool>;
    private let logged: Bool;

    public static func StylePath() -> ResRef { return r"base\\gameplay\\gui\\common\\main_colors.inkstyle"; }
    public static func Sentinel() -> HDRColor { return new HDRColor(0.123, 0.456, 0.789, 0.5); }

    public static func Slot(role: NMColorRole) -> CName {
        switch role {
            case NMColorRole.Accent: return n"MainColors.Blue";
            case NMColorRole.Highlight: return n"MainColors.ActiveBlue";
            case NMColorRole.Background: return n"MainColors.PanelBlack";   // not PanelDarkBlue: it equals DarkBlue (roads)
            case NMColorRole.PanelBg: return n"MainColors.PanelBlack";
            case NMColorRole.Text: return n"MainColors.White";
            case NMColorRole.Muted: return n"MainColors.MildBlue";
            case NMColorRole.Warn: return n"MainColors.Red";
            case NMColorRole.Route: return n"MainColors.Yellow";
            case NMColorRole.Enemy: return n"MainColors.EnemyMinimapBase";
            case NMColorRole.Police: return n"MainColors.SupBlue";
            case NMColorRole.Player: return n"MainColors.ActiveGreen";
            case NMColorRole.Road: return n"MainColors.DarkBlue";   // Road / Floor / Wall: HUD Painter's own minimap mapping
            case NMColorRole.Floor: return n"MainColors.PanelDarkGrey";   // HUD Painter uses White on the vanilla floor; on filled buildings it glares
            case NMColorRole.Wall: return n"MainColors.Neutral";
            case NMColorRole.FastTravel: return n"MainColors.FastTravel";
            case NMColorRole.Relic: return n"MainColors.RelicColor";
        }
        return n"MainColors.White";
    }

    private static func Empty() -> ref<NMHudPalette> {
        let p = new NMHudPalette();
        let i = 0;
        while i < EnumInt(NMColorRole.Count) {
            ArrayPush(p.colors, new HDRColor(1.0, 1.0, 1.0, 1.0));
            ArrayPush(p.known, false);
            i += 1;
        }
        return p;
    }

    // Probes in `parent` (the HUD window), invisible: opacity 0, 2x2 units.
    public static func Create(parent: wref<inkCompoundWidget>) -> ref<NMHudPalette> {
        let p = NMHudPalette.Empty();
        let i = 0;
        while i < EnumInt(NMColorRole.Count) {
            let r = new inkRectangle();
            r.SetName(n"OverlayMapPaletteProbe");
            r.SetSize(new Vector2(2.0, 2.0));
            r.SetOpacity(0.0);
            r.SetInteractive(false);
            r.SetTintColor(NMHudPalette.Sentinel());
            r.SetStyle(NMHudPalette.StylePath());
            r.BindProperty(n"tintColor", NMHudPalette.Slot(IntEnum<NMColorRole>(i)));
            r.Reparent(parent);
            ArrayPush(p.probes, r);
            i += 1;
        }
        return p;
    }

    // Every role answered by `c` (tests).
    public static func Fixed(c: HDRColor) -> ref<NMHudPalette> {
        let p = NMHudPalette.Empty();
        let i = 0;
        while i < EnumInt(NMColorRole.Count) {
            p.Set(IntEnum<NMColorRole>(i), c);   // not p.colors[i] = c: in game that write lost the green channel
            i += 1;
        }
        return p;
    }

    public func Set(role: NMColorRole, c: HDRColor) {
        let i = EnumInt(role);
        this.colors[i] = c;
        this.known[i] = true;
    }

    // Re-reads every probe; true when any role's colour changed (or became known).
    public func Refresh() -> Bool {
        let changed = false;
        let sent = NMHudPalette.Sentinel();
        let i = 0;
        while i < ArraySize(this.probes) {
            let c = this.probes[i].GetTintColor();
            let ok = !NMHudPalette.Near(c, sent);
            if ok && (!this.known[i] || NMHudPalette.Differs(this.colors[i], c)) {
                this.colors[i] = new HDRColor(c.Red, c.Green, c.Blue, 1.0);
                this.known[i] = true;
                changed = true;
            }
            i += 1;
        }
        if changed && !this.logged {
            this.logged = true;
            NMLog.Info("palette|resolved|Accent " + FloatToStringPrec(this.colors[0].Red, 2) + "," + FloatToStringPrec(this.colors[0].Green, 2)
                + "," + FloatToStringPrec(this.colors[0].Blue, 2));
        }
        return changed;
    }

    public func Has(role: NMColorRole) -> Bool { return this.known[EnumInt(role)]; }
    public func Get(role: NMColorRole) -> HDRColor { return this.colors[EnumInt(role)]; }
    public func ProbeCount() -> Int32 { return ArraySize(this.probes); }

    public func Destroy() {
        for r in this.probes {
            let parent = r.GetParentWidget() as inkCompoundWidget;
            if IsDefined(parent) { parent.RemoveChild(r); }
        }
        ArrayClear(this.probes);
    }

    // A real colour change: RGB only (stored colours keep alpha 1; a preset's alpha is not a change).
    public static func Differs(stored: HDRColor, read: HDRColor) -> Bool {
        return AbsF(stored.Red - read.Red) >= 0.002 || AbsF(stored.Green - read.Green) >= 0.002 || AbsF(stored.Blue - read.Blue) >= 0.002;
    }

    public static func Near(a: HDRColor, b: HDRColor) -> Bool {
        return AbsF(a.Red - b.Red) < 0.002 && AbsF(a.Green - b.Green) < 0.002 && AbsF(a.Blue - b.Blue) < 0.002 && AbsF(a.Alpha - b.Alpha) < 0.002;
    }
}
