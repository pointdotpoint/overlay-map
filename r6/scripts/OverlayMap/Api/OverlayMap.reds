module OverlayMap

// Public entry point: OverlayMap.Get() returns the live instance for the current session (null if not ready).
// Layers and categories are per session; create them again on Session/Ready.
public class OverlayMap {
    public let layers: array<ref<OverlayMapLayer>>;
    public let catNames: array<CName>;
    public let catDisplay: array<String>;
    public let catColor: array<HDRColor>;
    public let catHasIcon: array<Bool>;
    public let catAtlas: array<ResRef>;
    public let catPart: array<CName>;
    public let catKey: array<String>;   // "cat<i>": the renderer's atlas identity for a category icon (no per-frame string build)
    public let revision: Int32;
    // Bumped when layers are removed or reordered (indices change).
    public let layerEpoch: Int32;
    public let world: ref<NMRect>;

    public static func Create() -> ref<OverlayMap> {
        let m = new OverlayMap();
        m.world = NMRect.Create(NMGrid.OriginX(), NMGrid.OriginY(), -NMGrid.OriginX() - 0.01, -NMGrid.OriginY() - 0.01);
        m.RegisterCategory(n"other", "OTHER", NMTheme.Muted(), false);
        return m;
    }

    public static func Get() -> ref<OverlayMap> {
        let sys = GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"OverlayMap.OverlayMapSystem") as OverlayMapSystem;
        return IsDefined(sys) ? sys.Api() : null;
    }

    // Items are accepted within the map's world bounds plus 1 km, never beyond the grid extent.
    public func SetWorld(minX: Float, minY: Float, maxX: Float, maxY: Float) {
        let gx0 = NMGrid.OriginX();
        let gy0 = NMGrid.OriginY();
        this.world = NMRect.Create(MaxF(minX - 1000.0, gx0), MaxF(minY - 1000.0, gy0),
            MinF(maxX + 1000.0, -gx0 - 0.01), MinF(maxY + 1000.0, -gy0 - 0.01));
    }

    public func InBounds(x: Float, y: Float) -> Bool {
        return this.world.Contains(x, y);
    }

    public func CreateLayer(id: CName, displayName: String, priority: Int32) -> ref<OverlayMapLayer> {
        let existing = this.GetLayer(id);
        if IsDefined(existing) {
            return existing;
        }
        let layer = OverlayMapLayer.Create(this, id, displayName, priority, ArraySize(this.layers));
        ArrayPush(this.layers, layer);
        this.Touch();
        return layer;
    }

    public func GetLayer(id: CName) -> ref<OverlayMapLayer> {
        for l in this.layers {
            if Equals(l.id, id) {
                return l;
            }
        }
        return null;
    }

    public func RemoveLayer(id: CName) {
        let i = 0;
        while i < ArraySize(this.layers) {
            if Equals(this.layers[i].id, id) {
                ArrayErase(this.layers, i);
                let k = 0;
                while k < ArraySize(this.layers) {
                    this.layers[k].index = k;
                    k += 1;
                }
                this.layerEpoch += 1;
                this.Touch();
                return;
            }
            i += 1;
        }
    }

    // Returns the global index. overwrite=false keeps an existing display name/color.
    public func RegisterCategory(name: CName, display: String, color: HDRColor, overwrite: Bool) -> Int32 {
        let i = this.CategoryIndex(name);
        if i >= 0 {
            if overwrite {
                this.catDisplay[i] = display;
                this.catColor[i] = color;
                this.Touch();
            }
            return i;
        }
        if ArraySize(this.catNames) >= NMTheme.MaxGlobalCategories() {
            NMLog.Error("more than " + ToString(NMTheme.MaxGlobalCategories()) + " categories; '" + NameToString(name) + "' maps to 'other'");
            return this.CategoryIndex(n"other");
        }
        ArrayPush(this.catNames, name);
        ArrayPush(this.catDisplay, display);
        ArrayPush(this.catColor, color);
        ArrayPush(this.catHasIcon, false);
        let emptyRef: ResRef;
        ArrayPush(this.catAtlas, emptyRef);
        ArrayPush(this.catPart, n"");
        ArrayPush(this.catKey, "cat" + ToString(ArraySize(this.catNames) - 1));
        this.Touch();
        return ArraySize(this.catNames) - 1;
    }

    // Default icon for items of this category that don't carry their own.
    public func SetCategoryIcon(name: CName, atlas: ResRef, part: CName) {
        let i = this.CategoryIndex(name);
        if i < 0 {
            i = this.RegisterCategory(name, NameToString(name), NMTheme.Cyan(), false);
        }
        this.catHasIcon[i] = true;
        this.catAtlas[i] = atlas;
        this.catPart[i] = part;
        this.Touch();
    }

    public func CategoryIndex(name: CName) -> Int32 {
        let i = 0;
        while i < ArraySize(this.catNames) {
            if Equals(this.catNames[i], name) {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    public func Touch() {
        this.revision += 1;
    }
}
