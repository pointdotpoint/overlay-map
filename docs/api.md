# OverlayMap layer API

OverlayMap draws everything through layers. Any redscript mod can add its own; OverlayMap's own content
(vanilla pins, user markers, photos) uses the same API.

## Lifecycle
Layers and categories live for one game session. Create them after the session is ready.

Every script that names a OverlayMap type must be guarded with `@if(ModuleExists("OverlayMap"))` (OverlayMap declares
`module OverlayMap`). Unguarded references fail to compile when OverlayMap is not installed, which breaks all redscript
mods. Provide an `@if(!ModuleExists("OverlayMap"))` twin of each function so callers compile either way:

```swift
module MyMod
@if(ModuleExists("OverlayMap"))
import OverlayMap.*

@if(ModuleExists("OverlayMap"))
public func MyModFillOverlayMap() {
    let map = OverlayMap.Get();          // null if OverlayMap is not ready yet
    if IsDefined(map) { MyMod.FillLayer(map); }   // FillLayer must be guarded the same way
}

@if(!ModuleExists("OverlayMap"))
public func MyModFillOverlayMap() {}

@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
    let r = wrappedMethod();
    MyModFillOverlayMap();
    return r;
}
```

## Layers and items
```swift
let layer = map.CreateLayer(n"MyMod.Collectibles", "Collectibles", 50);   // id, display name, priority (higher draws on top)
layer.SetCategory(n"mymod.tarot", "TAROT", new HDRColor(1.0, 0.88, 0.4, 1.0));
map.SetCategoryIcon(n"mymod.tarot", r"mymod\\icons.inkatlas", n"tarot");    // default icon for the category
let id = layer.Add(OverlayMapItem.Create(new Vector4(x, y, z, 1.0), n"mymod.tarot", r"mymod\\icons.inkatlas", n"tarot")
    .WithLabel("Tarot: The Fool"));
layer.Move(id, newPos);     // returns Bool
layer.Remove(id);           // returns Bool
layer.Clear();
```

- Positions are world meters. Items outside the map bounds + 1 km are rejected; `Add` returns -1 and the layer logs once.
- Item ids are plain indices. After `Remove` or `Clear`, ids can be reused by later `Add` calls, so drop any id you removed.
- Up to 7 categories per layer; further categories map to `other`. Up to 64 categories across all layers.
- Optional item modifiers: `WithTint(color)` and `WithPriority(priority)`.
- `layer.Update(id, item)` replaces an item's content in place (position, icon, tint, label, emphasis, opacity) and keeps its id. Returns `false` for dead ids or out-of-bounds positions.
- `WithEmphasis(true)` draws the item at full strength (and enlarged on Icon-style layers), e.g. for a tracked marker. `WithOpacity(a)` multiplies the item's opacity (0..1) on top of the layer opacity.
- Image items: `OverlayMapItem.Image(pos, category, "shot://photo.png|max256x256")` needs RedIMGRetriever. The icon appears once the image is loaded.

## Display controls
```swift
layer.SetVisible(false);
layer.SetOpacity(0.6);
layer.SetZoomRange(0.5, 4.0);     // only shown while the camera is between 0.5 and 4 meters per unit
layer.SetClustering(false);       // deprecated and ignored: there is no clustering any more
layer.SetTier(OverlayMapTier.Major); // Always / Major / Minor (default Minor): Minor markers fade out first when zooming out
layer.SetAmbient(true);           // a numerous background Minor layer: fades out at 2.5 to 4 m/unit, before other Minor ones
layer.SetPinStyle(OverlayMapPinStyle.Icon);
```

`OverlayMapPinStyle.Icon` draws each item like the vanilla world map: the icon over a soft shadow, dimmed to 50 % until it is selected or emphasised, then full strength at 1.3×. `Hex` (the default) draws hologram hex chips.

There is no clustering. As the map zooms out, Minor and Major markers shrink to 70 % and fade out by tier: Minor 4 to
6 m/unit (an ambient Minor layer 2.5 to 4), Major 24 to 32 (past the map's widest zoom of 16, so Major markers stay
visible at every zoom), Always never. A faded-out marker can't be hovered or selected. A layer of up to 64
items is scanned in full on every relayout; larger layers are placed cell by cell, nearest the view centre first.

Markers don't overlap. Layers are placed in tier order (Always, then Major, then Minor), and by priority within a tier;
a marker that would overlap one already placed, or the district title and scale bar, is skipped. The selected marker and
Always markers are never skipped. To bound the cost, Major layers together stop after 160 skipped markers, and each Minor
layer stops after 24 of its own, so a dense layer shows its markers nearest the view centre.

## Tooltip and activation
```swift
public class MyListener extends OverlayMapLayerListener {
    public func OnSelected(id: Int32) { /* called when the item is selected, before GetDetails(id) */ }
    public func GetDetails(id: Int32) -> ref<OverlayMapDetails> {
        return OverlayMapDetails.Create("TAROT", "The Fool")
            .WithSubtitle("Watson · Kabuki")
            .AddRow("Status", "Not collected")
            .WithDescription("A graffiti tarot card.")
            .AddAction("NUM 0", "Set waypoint");
    }
    public func OnActivated(id: Int32) { /* numpad 0 on the selected item */ }
}
layer.SetListener(new MyListener());
```

`OnSelected(id)` fires first, so you can refresh state that `GetDetails(id)` then reads.
`OverlayMapDetails.WithColor(color)` overrides the tooltip's category colour (default: the layer category colour).
Limits: 6 rows, 3 actions (extras are ignored). The hover tooltip shows the category, title, the first 3 rows and the first action; the description, subtitle and the rest stay in the API. Return `null` from `GetDetails` to get the default tooltip (category, label, distance).

## Performance contract
Items cost nothing until visible, and a layer faded out by its tier costs nothing at all. At most 300 markers are
drawn at once, whatever the item count; higher tiers and priorities are placed first, and within a layer the
nearest to the view centre win.
The perf suite gates the 50,000-item scenario at +3 ms avg / +6 ms p95 over the closed baseline (see `tools/results.py`).
