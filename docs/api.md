# NightMap layer API

NightMap draws everything through layers. Any redscript mod can add its own; NightMap's own content
(vanilla pins, user markers, photos) uses the same API.

## Lifecycle
Layers and categories live for one game session. Create them after the session is ready:

```swift
@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
    let r = wrappedMethod();
    let map = NightMap.Get();          // null if NightMap is not installed or not ready
    if IsDefined(map) { MyMod.FillLayer(map); }
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
- Image items: `NightMapItem.Image(pos, category, "shot://photo.png|max256x256")` needs RedIMGRetriever. The icon appears once the image is loaded.

## Display controls
```swift
layer.SetVisible(false);
layer.SetOpacity(0.6);
layer.SetZoomRange(0.5, 4.0);     // only shown while the camera is between 0.5 and 4 meters per unit
layer.SetClustering(false);       // always individual chips
```

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
