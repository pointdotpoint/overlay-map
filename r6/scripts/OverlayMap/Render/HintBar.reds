module OverlayMap

// One hint: a key (shown in a keycap) and what it does. pre is plain text before the keycap (RELEASE, HOLD); an empty
// key makes the entry plain text (the NumLock notice).
public struct NMHint {
    public let key: String;
    public let label: String;
    public let pre: String;
}

public abstract class NMHints {
    public static func Of(key: String, label: String, opt pre: String) -> NMHint {
        let h: NMHint;
        h.key = key;
        h.label = label;
        h.pre = pre;
        return h;
    }

    public static func Separator() -> String { return "   ·   "; }

    public static func Text(h: NMHint) -> String {
        let t = StrLen(h.pre) > 0 ? h.pre + " " : "";
        if StrLen(h.key) > 0 {
            t += h.key + " ";
        }
        return t + h.label;
    }

    // The single-line copy (the old hint text, kept for tests and logs).
    public static func Join(h: array<NMHint>) -> String {
        let out = "";
        let i = 0;
        while i < ArraySize(h) {
            out += (i > 0 ? NMHints.Separator() : "") + NMHints.Text(h[i]);
            i += 1;
        }
        return out;
    }

    // A plain-text entry just before the last one, so CLOSE stays last.
    public static func Notice(h: array<NMHint>, text: String) -> array<NMHint> {
        let out: array<NMHint>;
        let n = ArraySize(h);
        let i = 0;
        while i < n {
            if i == n - 1 {
                ArrayPush(out, NMHints.Of("", text));
            }
            ArrayPush(out, h[i]);
            i += 1;
        }
        if n == 0 {
            ArrayPush(out, NMHints.Of("", text));
        }
        return out;
    }

    // "NUM 8/NUM 4/NUM 6/NUM 2" -> "8 4 6 2", "NUM + NUM -" -> "+ -"; "" when any key in it is not a numpad key.
    // KeyName writes every numpad key as "NUM " and one character; keys are joined by "/" or " ".
    public static func ShortKey(key: String) -> String {
        let n = StrLen(key);
        let out = "";
        let i = 0;
        while i < n {
            if i + 5 > n || NotEquals(StrMid(key, i, 4), "NUM ") {
                return "";
            }
            out += (StrLen(out) > 0 ? " " : "") + StrMid(key, i + 4, 1);
            i += 5;
            if i < n {
                let sep = StrMid(key, i, 1);
                if NotEquals(sep, "/") && NotEquals(sep, " ") {
                    return "";
                }
                i += 1;
            }
        }
        return out;
    }

    // Keycaps show numpad keys without "NUM " only when every map key is on the numpad, so a short "5" cannot be read
    // as the top-row 5. CLOSE entries (the toggle key, a separate bind) and plain text do not count.
    public static func Short(h: array<NMHint>) -> array<NMHint> {
        for e in h {
            if StrLen(e.key) > 0 && !NMHints.IsClose(e) && StrLen(NMHints.ShortKey(e.key)) == 0 {
                return h;
            }
        }
        let out: array<NMHint>;
        for e in h {
            let k = NMHints.ShortKey(e.key);
            ArrayPush(out, NMHints.Of(StrLen(k) > 0 ? k : e.key, e.label, e.pre));
        }
        return out;
    }

    public static func IsClose(h: NMHint) -> Bool {
        return StrEndsWith(h.label, "CLOSE");
    }
}

// The keycap hint bar (spec 6) along the panel's bottom: each key in its own keycap with its label, 60 * scale between
// entries, the last entry (CLOSE) flush right. Set rebuilds the widgets only when the hints changed (no per-frame work).
// Widths are estimates (NMUi.KeycapWidth): ink lays text out later.
public class NMHintBar {
    private let root: ref<inkCanvas>;
    private let s: Float;
    private let w: Float;
    private let h: Float;
    private let theme: Int32;
    private let text: String;        // NMHints.Join of the last Set
    private let kept: array<NMHint>; // what is drawn, after Short and Fit
    private let laidOut: Float;
    private let lastRight: Float;
    private let rebuilds: Int32;

    public static func Margin() -> Float { return 58.0; }   // 4K units at both ends
    public static func Gap() -> Float { return 60.0; }      // 4K units between entries

    public static func Create(parent: ref<inkCompoundWidget>, x: Float, y: Float, w: Float, h: Float, scale: Float, theme: Int32) -> ref<NMHintBar> {
        let b = new NMHintBar();
        b.root = NMUi.Canvas(parent, x, y, w, h);
        b.root.SetName(n"HintBar");
        b.s = scale;
        b.w = w;
        b.h = h;
        b.theme = theme;
        b.text = "\n";   // sentinel: the first Set always builds
        return b;
    }

    // The bar shows the FILTER entry as "FILTER · ALL", like the header (the joined copy keeps "FILTER: ALL").
    public static func Display(label: String) -> String {
        return StrReplace(label, ": ", " · ");
    }

    public static func EntryWidth(e: NMHint, s: Float) -> Float {
        let label = NMHintBar.Display(e.label);
        let x = StrLen(e.pre) > 0 ? NMUi.KeyLabelWidth(e.pre, s) + NMUi.KeycapGap() * s : 0.0;
        return x + (StrLen(e.key) > 0 ? NMUi.KeycapWidth(e.key, label, s) : NMUi.KeyLabelWidth(label, s));
    }

    // Width the row needs: both margins, every entry and a gap between each.
    public static func Needed(h: array<NMHint>, s: Float) -> Float {
        let n = ArraySize(h);
        let x = 2.0 * NMHintBar.Margin() * s + Cast<Float>(Max(0, n - 1)) * NMHintBar.Gap() * s;
        for e in h {
            x += NMHintBar.EntryWidth(e, s);
        }
        return x;
    }

    // Drops entries from the left (PAN, ZOOM, FOLLOW, ... : the basics learned first; the filter state, teleport and the
    // NumLock notice sit to the right) until the row fits w. The last entry (CLOSE) is never dropped.
    public static func Fit(h: array<NMHint>, w: Float, s: Float) -> array<NMHint> {
        let out: array<NMHint>;
        for e in h {
            ArrayPush(out, e);
        }
        while ArraySize(out) > 1 && NMHintBar.Needed(out, s) > w {
            ArrayErase(out, 0);
        }
        return out;
    }

    public func Set(h: array<NMHint>) {
        let text = NMHints.Join(h);
        if Equals(text, this.text) {
            return;
        }
        this.text = text;
        this.rebuilds += 1;
        this.kept = NMHintBar.Fit(NMHints.Short(h), this.w, this.s);
        this.root.RemoveAllChildren();
        let s = this.s;
        let y = (this.h - NMUi.KeycapHeight() * s) * 0.5;
        let n = ArraySize(this.kept);
        let x = NMHintBar.Margin() * s;
        let i = 0;
        while i < n - 1 {
            x += this.Draw(this.kept[i], x, y) + NMHintBar.Gap() * s;
            i += 1;
        }
        this.laidOut = NMHintBar.Needed(this.kept, s);
        this.lastRight = 0.0;
        if n > 0 {
            let lx = this.w - NMHintBar.Margin() * s - NMHintBar.EntryWidth(this.kept[n - 1], s);
            this.lastRight = lx + this.Draw(this.kept[n - 1], lx, y);
        }
    }

    // One entry at (x, y) in its own canvas; returns its width.
    private func Draw(e: NMHint, x: Float, y: Float) -> Float {
        let s = this.s;
        let c = NMUi.Canvas(this.root, x, y, NMHintBar.EntryWidth(e, s), NMUi.KeycapHeight() * s);
        let label = NMHintBar.Display(e.label);
        let kx = 0.0;
        if StrLen(e.pre) > 0 {
            NMUi.KeyLabel(c, e.pre, 0.0, s);
            kx = NMUi.KeyLabelWidth(e.pre, s) + NMUi.KeycapGap() * s;
        }
        if StrLen(e.key) > 0 {
            let k = NMUi.Canvas(c, kx, 0.0, NMUi.KeycapWidth(e.key, label, s), NMUi.KeycapHeight() * s);
            NMUi.Keycap(k, e.key, label, s, this.theme);
        } else {
            NMUi.KeyLabel(c, label, kx, s);
        }
        return NMHintBar.EntryWidth(e, s);
    }

    public func Shown() -> Int32 { return ArraySize(this.kept); }
    public func Kept() -> array<NMHint> { return this.kept; }
    public func Rebuilds() -> Int32 { return this.rebuilds; }
    public func LaidOutWidth() -> Float { return this.laidOut; }
    public func LastRight() -> Float { return this.lastRight; }
}
