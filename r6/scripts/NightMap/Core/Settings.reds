module NightMap

public class NightMapSettings extends ScriptableSystem {
    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Open / close map")
    @runtimeProperty("ModSettings.description", "Toggles the NightMap overlay. With Debug on: Ctrl = self-test, Shift = perf suite, Alt = calibration dump, Ctrl+Shift = debug layer.")
    public let keyToggle: EInputKey = EInputKey.IK_Backslash;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan up")
    @runtimeProperty("ModSettings.description", "Hold to pan north. Numpad 7/9/1/3 pan diagonally.")
    public let keyPanUp: EInputKey = EInputKey.IK_NumPad8;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan down")
    @runtimeProperty("ModSettings.description", "Hold to pan south.")
    public let keyPanDown: EInputKey = EInputKey.IK_NumPad2;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan left")
    @runtimeProperty("ModSettings.description", "Hold to pan west.")
    public let keyPanLeft: EInputKey = EInputKey.IK_NumPad4;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan right")
    @runtimeProperty("ModSettings.description", "Hold to pan east.")
    public let keyPanRight: EInputKey = EInputKey.IK_NumPad6;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Zoom in")
    @runtimeProperty("ModSettings.description", "Hold to zoom in.")
    public let keyZoomIn: EInputKey = EInputKey.IK_NumPlus;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Zoom out")
    @runtimeProperty("ModSettings.description", "Hold to zoom out.")
    public let keyZoomOut: EInputKey = EInputKey.IK_NumMinus;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Recenter on V")
    @runtimeProperty("ModSettings.description", "Centers the map on V and follows V again.")
    public let keyRecenter: EInputKey = EInputKey.IK_NumPad5;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Act on selection")
    @runtimeProperty("ModSettings.description", "Zooms into a selected cluster, or activates the selected item.")
    public let keyAct: EInputKey = EInputKey.IK_NumPad0;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Panel opacity")
    @runtimeProperty("ModSettings.description", "Background opacity of the map panel (applies on next open).")
    @runtimeProperty("ModSettings.step", "0.02")
    @runtimeProperty("ModSettings.min", "0.3")
    @runtimeProperty("ModSettings.max", "1.0")
    public let panelOpacity: Float = 0.74;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Debug")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Debug tools")
    @runtimeProperty("ModSettings.description", "Enables the debug key chords and the clip probe.")
    public let debug: Bool = false;

    private func OnAttach() {
        NightMapRegisterSettings(this);
    }

    private func OnDetach() {
        NightMapUnregisterSettings(this);
    }

    public static func Get(game: GameInstance) -> ref<NightMapSettings> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"NightMap.NightMapSettings") as NightMapSettings;
    }
}

@if(ModuleExists("ModSettingsModule"))
public func NightMapRegisterSettings(s: ref<NightMapSettings>) {
    ModSettings.RegisterListenerToClass(s);
}

@if(!ModuleExists("ModSettingsModule"))
public func NightMapRegisterSettings(s: ref<NightMapSettings>) {}

@if(ModuleExists("ModSettingsModule"))
public func NightMapUnregisterSettings(s: ref<NightMapSettings>) {
    ModSettings.UnregisterListenerToClass(s);
}

@if(!ModuleExists("ModSettingsModule"))
public func NightMapUnregisterSettings(s: ref<NightMapSettings>) {}
