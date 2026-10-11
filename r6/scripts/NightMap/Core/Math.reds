module NightMap

public class NMRect {
    public let minX: Float;
    public let minY: Float;
    public let maxX: Float;
    public let maxY: Float;

    public static func Create(minX: Float, minY: Float, maxX: Float, maxY: Float) -> ref<NMRect> {
        let r = new NMRect();
        r.minX = minX;
        r.minY = minY;
        r.maxX = maxX;
        r.maxY = maxY;
        return r;
    }

    public func Contains(x: Float, y: Float) -> Bool {
        return x >= this.minX && x <= this.maxX && y >= this.minY && y <= this.maxY;
    }
}

public abstract class NMMath {
    // Heading in degrees from a world forward vector: 0 = north (+Y), 90 = east (+X).
    public static func HeadingDeg(fx: Float, fy: Float) -> Float {
        return AtanF(fx, fy) * 57.2957795;
    }

    public static func NiceLength(maxMeters: Float) -> Float {
        let steps: array<Float> = [10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0];
        let best = 10.0;
        for s in steps {
            if s <= maxMeters {
                best = s;
            }
        }
        return best;
    }

    public static func FormatMeters(m: Float) -> String {
        if m >= 1000.0 {
            return FloatToStringPrec(m / 1000.0, 0) + " KM";
        }
        return FloatToStringPrec(m, 0) + " M";
    }

    public static func Lerp(a: Float, b: Float, t: Float) -> Float {
        return a + (b - a) * t;
    }

    public static func EaseOut(t: Float) -> Float {
        let u = 1.0 - t;
        return 1.0 - u * u;
    }
}
