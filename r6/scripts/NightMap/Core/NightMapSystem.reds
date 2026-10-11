module NightMap

public class NightMapSystem extends ScriptableSystem {
    private let api: ref<NightMap>;

    private func OnAttach() {
        this.api = NightMap.Create();
    }

    public func Api() -> ref<NightMap> {
        return this.api;
    }
}
