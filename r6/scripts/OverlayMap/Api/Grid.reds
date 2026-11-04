module OverlayMap

// Fixed 24 km world grid pyramid shared by all layers. Level 0: 250 m (96x96), 1: 1 km (24x24), 2: 4 km (6x6).
// Cells of all levels live in one flat index space: Base(level) + gy * Side(level) + gx.
public abstract class NMGrid {
    public static func OriginX() -> Float { return -12000.0; }
    public static func OriginY() -> Float { return -12000.0; }
    public static func Levels() -> Int32 { return 3; }
    public static func TotalCells() -> Int32 { return 9828; }
    public static func MaxCats() -> Int32 { return 8; }

    public static func CellSize(level: Int32) -> Float {
        switch level {
            case 0: return 250.0;
            case 1: return 1000.0;
            default: return 4000.0;
        }
    }

    public static func Side(level: Int32) -> Int32 {
        switch level {
            case 0: return 96;
            case 1: return 24;
            default: return 6;
        }
    }

    public static func Base(level: Int32) -> Int32 {
        switch level {
            case 0: return 0;
            case 1: return 9216;
            default: return 9792;
        }
    }

    public static func CellIndex(level: Int32, x: Float, y: Float) -> Int32 {
        let cs = NMGrid.CellSize(level);
        let side = NMGrid.Side(level);
        let gx = Clamp(FloorF((x - NMGrid.OriginX()) / cs), 0, side - 1);
        let gy = Clamp(FloorF((y - NMGrid.OriginY()) / cs), 0, side - 1);
        return NMGrid.Base(level) + gy * side + gx;
    }
}
