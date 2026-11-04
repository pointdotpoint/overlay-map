module OverlayMap

// A map item value. Positions are world meters (X east, Y north); Z is kept for future floor logic.
public class OverlayMapItem {
    public let x: Float;
    public let y: Float;
    public let z: Float;
    public let category: CName;
    public let hasAtlas: Bool;
    public let atlas: ResRef;
    public let part: CName;
    public let imageKey: String;
    public let shotHash: Uint32;
    public let hasTint: Bool;
    public let tint: HDRColor;
    public let label: String;
    public let priority: Int32;
    public let emphasis: Bool;
    public let opacity: Float = 1.0;
    public let struck: Bool;
    public let dot: Bool;

    public static func Create(pos: Vector4, category: CName, atlas: ResRef, part: CName) -> ref<OverlayMapItem> {
        let it = new OverlayMapItem();
        it.x = pos.X;
        it.y = pos.Y;
        it.z = pos.Z;
        it.category = category;
        it.hasAtlas = true;
        it.atlas = atlas;
        it.part = part;
        return it;
    }

    // An item whose icon is a RedIMGRetriever image key (e.g. "shot://photo.png|max256x256").
    public static func Image(pos: Vector4, category: CName, imageKey: String) -> ref<OverlayMapItem> {
        let it = new OverlayMapItem();
        it.x = pos.X;
        it.y = pos.Y;
        it.z = pos.Z;
        it.category = category;
        it.imageKey = imageKey;
        return it;
    }

    // An item whose icon is a photo mode shot, loaded by the game's screenshot hash (photo pins).
    public static func Shot(pos: Vector4, category: CName, hash: Uint32) -> ref<OverlayMapItem> {
        let it = new OverlayMapItem();
        it.x = pos.X;
        it.y = pos.Y;
        it.z = pos.Z;
        it.category = category;
        it.shotHash = hash;
        return it;
    }

    public func WithLabel(label: String) -> ref<OverlayMapItem> {
        this.label = label;
        return this;
    }

    public func WithTint(color: HDRColor) -> ref<OverlayMapItem> {
        this.hasTint = true;
        this.tint = color;
        return this;
    }

    public func WithPriority(priority: Int32) -> ref<OverlayMapItem> {
        this.priority = priority;
        return this;
    }

    // Always drawn at full strength (and, for Icon-style layers, at the emphasis scale), like a tracked marker.
    public func WithEmphasis(on: Bool) -> ref<OverlayMapItem> {
        this.emphasis = on;
        return this;
    }

    // Per-item opacity multiplier (layer opacity still applies), clamped to 0..1.
    public func WithOpacity(a: Float) -> ref<OverlayMapItem> {
        this.opacity = ClampF(a, 0.0, 1.0);
        return this;
    }

    // Drawn as a small dot at full strength, with no shadow (a police car, like the vanilla minimap).
    public func WithDot(on: Bool) -> ref<OverlayMapItem> {
        this.dot = on;
        return this;
    }

    // Drawn with a diagonal scratch over the icon (a collected collectible).
    public func WithStruck(on: Bool) -> ref<OverlayMapItem> {
        this.struck = on;
        return this;
    }
}
