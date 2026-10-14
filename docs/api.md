# NightMap layer API

NightMap draws everything through layers. Any redscript mod can add its own; NightMap's own content
(vanilla pins, user markers, photos) uses the same API.

## Lifecycle
Layers and categories live for one game session. Create them after the session is ready.

Every script that names a NightMap type must be guarded with `@if(ModuleExists("NightMap"))` (NightMap declares
`module NightMap`). Unguarded references fail to compile when NightMap is not installed, which breaks all redscript
mods. Provide an `@if(!ModuleExists("NightMap"))` twin of each function so callers compile either way:

```swift
module MyMod
@if(ModuleExists("NightMap"))
import NightMap.*

@if(ModuleExists("NightMap"))
public func MyModFillNightMap() {
    let map = NightMap.Get();          // null if NightMap is not ready yet
    if IsDefined(map) { MyMod.FillLayer(map); }   // FillLayer must be guarded the same way
}

@if(!ModuleExists("NightMap"))
public func MyModFillNightMap() {}

@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
    let r = wrappedMethod();
    MyModFillNightMap();
    return r;
}
```

## Layers and items
```swift
let layer = map.CreateLayer(n"MyMod.Collectibles", "Collectibles", 50);   // id, display name, priority (higher draws on top)
layer.SetCategory(n"mymod.tarot", "TAROT", new HDRColor(1.0, 0.88, 0.4, 1.0));
map.SetCategoryIcon(n"mymod.tarot", r"mymod\\icons.inkatlas", n"tarot");    // default icon for the category
let id = layer.Add(NightMapItem.Create(new Vector4(x, y, z, 1.0), n"mymod.tarot", r"mymod\\icons.inkatlas", n"tarot")
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
- Image items: `NightMapItem.Image(pos, category, "shot://photo.png|max256x256")` needs RedIMGRetriever. The icon appears once the image is loaded.

## Display controls
```swift
layer.SetVisible(false);
layer.SetOpacity(0.6);
layer.SetZoomRange(0.5, 4.0);     // only shown while the camera is between 0.5 and 4 meters per unit
layer.SetClustering(false);       // always individual chips
layer.SetPinStyle(NightMapPinStyle.Icon);
```

`NightMapPinStyle.Icon` draws each item like the vanilla world map: the icon over a soft shadow, dimmed to 50 % until it is selected or emphasised, then full strength at 1.3×. `Hex` (the default) draws hologram hex chips. Clusters are hexes in both styles.

Non-clustering layers are scanned in full on every relayout, so keep them small (under ~500 items).

## Info card and activation
```swift
public class MyListener extends NightMapLayerListener {
    public func OnSelected(id: Int32) { /* called when the item is selected, before GetDetails(id) */ }
    public func GetDetails(id: Int32) -> ref<NightMapDetails> {
        return NightMapDetails.Create("TAROT", "The Fool")
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
Limits: 6 rows, 3 actions (extras are ignored). Return `null` from `GetDetails` to get the default card (category, label, distance).

## Performance contract
Items cost nothing until visible. At most 300 chips and 80 clusters are drawn at once, whatever the item count.
The perf suite gates the 50,000-item scenario at +3 ms avg / +6 ms p95 over the closed baseline (see `tools/results.py`).
