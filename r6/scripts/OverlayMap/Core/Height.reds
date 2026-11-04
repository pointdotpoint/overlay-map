module OverlayMap

// The baked lowest and highest surface of the cell under a point (tools/tiles/nmtiles/heightmap.py). An estimate: V is
// only sent near these heights and a ray finds the real surface. Open sea has no data and reads 0.
public abstract class NMHeight {
    // Four characters a cell: `field` 0 = low, 1 = high.
    private static func Read(x: Float, y: Float, field: Int32) -> Float {
        let col = FloorF((x - NMHeightData.X0()) / NMHeightData.Cell());
        let row = FloorF((y - NMHeightData.Y0()) / NMHeightData.Cell());
        let cc = NMHeightData.ChunkCells();
        let side = cc * NMHeightData.Chunks();
        if col < 0 || row < 0 || col >= side || row >= side {
            return 0.0;
        }
        let chunk = NMHeightData.Chunk(row / cc * NMHeightData.Chunks() + col / cc);
        if StrLen(chunk) == 0 {
            return 0.0;
        }
        let at = (row % cc * cc + col % cc) * 4 + field * 2;
        let alphabet = NMHeightData.Alphabet();
        let high = StrFindFirst(alphabet, StrMid(chunk, at, 1));
        let low = StrFindFirst(alphabet, StrMid(chunk, at + 1, 1));
        return Cast<Float>(high * StrLen(alphabet) + low) + NMHeightData.Floor();
    }

    public static func Low(x: Float, y: Float) -> Float { return NMHeight.Read(x, y, 0); }
    public static func High(x: Float, y: Float) -> Float { return NMHeight.Read(x, y, 1); }
}
