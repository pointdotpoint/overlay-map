module NightMap

// Subclass to react to selection/activation and to supply tooltip content for a layer's items.
public abstract class NightMapLayerListener {
    public func GetDetails(id: Int32) -> ref<NightMapDetails> {
        return null;
    }

    public func OnSelected(id: Int32) {}

    public func OnActivated(id: Int32) {}
}
