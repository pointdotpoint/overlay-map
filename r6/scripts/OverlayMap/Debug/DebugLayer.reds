module OverlayMap

public class NMDebugListener extends OverlayMapLayerListener {
    public let layer: wref<OverlayMapLayer>;
    public let api: wref<OverlayMap>;

    public func GetDetails(id: Int32) -> ref<OverlayMapDetails> {
        let L = this.layer;
        if !IsDefined(L) || !L.IsAlive(id) {
            return null;
        }
        let pos = L.Position(id);
        let g = this.api.CategoryIndex(L.CategoryOf(id));
        return OverlayMapDetails.Create(g >= 0 ? this.api.catDisplay[g] : "DEBUG", L.Label(id))
            .WithSubtitle("OverlayMap debug layer")
            .AddRow("ITEM", "#" + ToString(id))
            .AddRow("WORLD X", FloatToStringPrec(pos.X, 0))
            .AddRow("WORLD Y", FloatToStringPrec(pos.Y, 0))
            .WithDescription("Synthetic item used to test tiers, selection and performance.")
            .AddAction("ACT", "LOG THIS ITEM");
    }

    public func OnActivated(id: Int32) {
        NMLog.Info("DEBUG|activated|" + ToString(id));
    }
}

// Deterministic synthetic content: n items around 40 "neighbourhood" centers inside the map bounds.
public abstract class NMDebugLayer {
    public static func Id() -> CName {
        return n"OverlayMap.Debug";
    }

    public static func Fill(api: ref<OverlayMap>, n: Int32) -> ref<OverlayMapLayer> {
        let L = api.CreateLayer(NMDebugLayer.Id(), "Debug", 0);
        L.Clear();
        let names: array<CName> = [n"debug.quest", n"debug.gig", n"debug.vendor", n"debug.ft", n"debug.undisc"];
        let shows: array<String> = ["QUEST", "GIG", "VENDOR", "FAST TRAVEL", "UNDISCOVERED"];
        let parts: array<CName> = [n"icon_quest", n"icon_gig", n"icon_vendor", n"icon_ft", n"icon_undisc"];
        let colors: array<HDRColor> = [NMTheme.Yellow(), NMTheme.Pink(), NMTheme.Cyan(), NMTheme.Cyan(), NMTheme.Muted()];
        let c = 0;
        while c < 5 {
            L.SetCategory(names[c], shows[c], colors[c]);
            api.SetCategoryIcon(names[c], NMTheme.UiAtlas(), parts[c]);
            c += 1;
        }
        let minX = NMTileManifest.WorldMinX();
        let minY = NMTileManifest.WorldMinY();
        // Centers stay >= 1 km inside the bounds; offsets reach at most 1.8 km, and the API accepts bounds + 1 km.
        let spanX = NMTileManifest.WorldMaxX() - minX - 2000.0;
        let spanY = NMTileManifest.WorldMaxY() - minY - 2000.0;
        let seed = 12345;
        let bx: array<Float>;
        let by: array<Float>;
        let b = 0;
        while b < 40 {
            seed = (seed * 1103 + 12345) % 1000003;
            ArrayPush(bx, minX + 1000.0 + Cast<Float>(seed) / 1000003.0 * spanX);
            seed = (seed * 1103 + 12345) % 1000003;
            ArrayPush(by, minY + 1000.0 + Cast<Float>(seed) / 1000003.0 * spanY);
            b += 1;
        }
        let i = 0;
        while i < n {
            seed = (seed * 1103 + 12345) % 1000003;
            let k = seed % 40;
            let ox = 0.0;
            let oy = 0.0;
            let j = 0;
            while j < 3 {
                seed = (seed * 1103 + 12345) % 1000003;
                ox += (Cast<Float>(seed) / 1000003.0 - 0.5) * 1200.0;
                seed = (seed * 1103 + 12345) % 1000003;
                oy += (Cast<Float>(seed) / 1000003.0 - 0.5) * 1200.0;
                j += 1;
            }
            let ci = i % 5;
            L.Add(OverlayMapItem.Create(new Vector4(bx[k] + ox, by[k] + oy, 0.0, 1.0), names[ci], NMTheme.UiAtlas(), parts[ci])
                .WithLabel(shows[ci] + " " + ToString(i)));
            i += 1;
        }
        let listener = new NMDebugListener();
        listener.layer = L;
        listener.api = api;
        L.SetListener(listener);
        return L;
    }

    public static func Remove(api: ref<OverlayMap>) {
        api.RemoveLayer(NMDebugLayer.Id());
    }
}
