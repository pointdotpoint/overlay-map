module NightMap

// Where the corner map sits: the vanilla minimap's box (window units), scaled about its top-right corner, with the map
// area and (SquareStrip) the info strip inside it.
public class NMCornerLayout {
    public let winW: Float;
    public let winH: Float;
    public let scale: Float;   // as NMPanelLayout.scale: 1.0 at 3840x2160
    public let x: Float;
    public let y: Float;
    public let w: Float;
    public let h: Float;
    public let mapX: Float;    // map area, relative to (x, y)
    public let mapY: Float;
    public let mapW: Float;
    public let mapH: Float;
    public let stripH: Float;  // 0 unless SquareStrip
    public let round: Bool;

    public static func StripHeight() -> Float { return 44.0; }   // 4K units, at text size 1

    // null when there is no box yet: the corner never draws at a guessed position.
    public static func Compute(box: ref<NMRect>, style: NightMapCornerStyle, cornerScale: Float, textSize: Float, winW: Float, winH: Float) -> ref<NMCornerLayout> {
        if !IsDefined(box) { return null; }
        let bw = (box.maxX - box.minX) * cornerScale;
        let bh = (box.maxY - box.minY) * cornerScale;
        if bw < 8.0 || bh < 8.0 { return null; }
        let l = new NMCornerLayout();
        l.winW = winW;
        l.winH = winH;
        l.scale = MinF(winW / 3840.0, winH / 2160.0);
        l.x = box.maxX - bw;   // grown from the top-right corner
        l.y = box.minY;
        l.w = bw;
        l.h = bh;
        l.round = Equals(style, NightMapCornerStyle.Circle);
        if l.round {
            let d = MinF(bw, bh);
            l.mapW = d;
            l.mapH = d;
            l.mapX = bw - d;   // keep it against the right edge
            l.mapY = 0.0;
            return l;
        }
        l.mapX = 0.0;
        l.mapY = 0.0;
        l.mapW = bw;
        l.stripH = Equals(style, NightMapCornerStyle.SquareStrip) ? NMCornerLayout.StripHeight() * l.scale * textSize : 0.0;
        l.mapH = bh - l.stripH;
        return l;
    }

    // For NMItemRenderer.UpdateFor and the other panel-shaped consumers: the map area, no sidebar.
    public func AsPanelLayout() -> ref<NMPanelLayout> {
        let p = new NMPanelLayout();
        p.winW = this.winW;
        p.winH = this.winH;
        p.scale = this.scale;
        p.x = this.x + this.mapX;
        p.y = this.y + this.mapY;
        p.w = this.mapW;
        p.h = this.mapH;
        p.mapW = this.mapW;
        p.mapH = this.mapH;
        p.hintH = 0.0;
        p.sideW = 0.0;
        p.viewW = this.mapW;
        return p;
    }
}
