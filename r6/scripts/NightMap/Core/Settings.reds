module NightMap

public enum NightMapHoloColor {
    Cyan = 0,
    Green = 1
}

public enum NightMapCornerStyle {
    Circle = 0,
    Square = 1,
    SquareStrip = 2
}

public enum NightMapPadOpen {
    HoldView = 0,
    Off = 1
}

public class NightMapSettings extends ScriptableSystem {
    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Open / close map")
    @runtimeProperty("ModSettings.description", "Toggles the NightMap overlay. With Debug on: Ctrl = self-test, Shift = perf suite, Alt = calibration dump, Ctrl+Shift = debug layer.")
    public let keyToggle: EInputKey = EInputKey.IK_SingleQuote;

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
    @runtimeProperty("ModSettings.description", "Activates the selected item.")
    public let keyAct: EInputKey = EInputKey.IK_NumPad0;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Cycle marker filter")
    @runtimeProperty("ModSettings.description", "Cycles the map markers shown: All, Jobs, Services.")
    public let keyFilter: EInputKey = EInputKey.IK_NumSlash;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Teleport")
    @runtimeProperty("ModSettings.description", "Fast travels on a fast travel marker, and teleports to the selected marker or the map centre anywhere else.")
    public let keyTeleport: EInputKey = EInputKey.IK_NumPeriod;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Controller")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Open map button")
    @runtimeProperty("ModSettings.description", "Hold View for half a second to open the map; a tap still does what it does in the game. While the map is open it takes the controller: left stick pans, LT/RT zoom, A acts, X teleports, Y cycles the filter, R3 follows V, B closes. Off: NightMap ignores the controller.")
    @runtimeProperty("ModSettings.displayValues.HoldView", "Hold View")
    @runtimeProperty("ModSettings.displayValues.Off", "Off")
    public let padOpen: NightMapPadOpen = NightMapPadOpen.HoldView;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Jobs")
    @runtimeProperty("ModSettings.description", "Show main and side job markers.")
    public let filterJobs: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Gigs")
    @runtimeProperty("ModSettings.description", "Show gig and fixer markers.")
    public let filterGigs: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Cyberpsycho Sighting")
    @runtimeProperty("ModSettings.description", "Show cyberpsycho sightings.")
    public let filterPsycho: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "NCPD Scanner")
    @runtimeProperty("ModSettings.description", "Show NCPD scanner hustles, stashes and outposts.")
    public let filterNcpd: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Fast Travel")
    @runtimeProperty("ModSettings.description", "Show fast-travel points and NCART stations.")
    public let filterFastTravel: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Ripperdoc")
    @runtimeProperty("ModSettings.description", "Show ripperdocs.")
    public let filterRipperdoc: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Vendor")
    @runtimeProperty("ModSettings.description", "Show vendors.")
    public let filterVendor: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Autofixer")
    @runtimeProperty("ModSettings.description", "Show vehicles for sale.")
    public let filterAutofixer: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Drop Point")
    @runtimeProperty("ModSettings.description", "Show drop points.")
    public let filterDropPoint: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Apartment for Rent")
    @runtimeProperty("ModSettings.description", "Show apartments for rent.")
    public let filterApartmentRent: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "TAROT")
    @runtimeProperty("ModSettings.description", "Show tarot graffiti.")
    public let filterTarot: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Your Apartments")
    @runtimeProperty("ModSettings.description", "Show your apartments, vehicles and waypoint.")
    public let filterYourProperty: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Panel opacity")
    @runtimeProperty("ModSettings.description", "Background opacity of the map panel; low values let the world show through (applies on next open).")
    @runtimeProperty("ModSettings.step", "0.02")
    @runtimeProperty("ModSettings.min", "0.3")
    @runtimeProperty("ModSettings.max", "1.0")
    public let panelOpacity: Float = 0.92;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Hologram colour")
    @runtimeProperty("ModSettings.description", "Tints the map tiles, overlays, frame and header text (applies on next open).")
    @runtimeProperty("ModSettings.displayValues.Cyan", "Cyan")
    @runtimeProperty("ModSettings.displayValues.Green", "Green")
    public let holoColor: NightMapHoloColor = NightMapHoloColor.Cyan;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Hologram effects")
    @runtimeProperty("ModSettings.description", "Glow, grid, scanlines, noise, scan bar, edge glow and marker halos, with their animations. Off looks like the plain map (applies on next open).")
    public let hologramEffects: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Follow HUD Painter colours")
    @runtimeProperty("ModSettings.description", "Take every NightMap colour from the game's HUD palette, so HUD Painter presets recolour the map. Off keeps NightMap's own colours.")
    public let followHudPainter: Bool = false;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "GPS routes")
    @runtimeProperty("ModSettings.description", "Show the waypoint and quest routes from the minimap.")
    public let showRoutes: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Photo pins")
    @runtimeProperty("ModSettings.description", "Show a thumbnail pin where each photo mode shot was taken (shows in the ALL filter view).")
    public let showPhotos: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Hide HUD while open")
    @runtimeProperty("ModSettings.description", "Fade out the game's HUD (minimap, quest tracker, hotkeys, prompts) while the map is open.")
    public let hideHud: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Hold key to show")
    @runtimeProperty("ModSettings.description", "Show the map only while the toggle key is held, instead of pressing it to open and again to close.")
    public let holdToShow: Bool = false;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Teleport key")
    @runtimeProperty("ModSettings.description", "Teleport from NightMap to any spot on the map: fast travels on a fast travel marker, teleports anywhere else.")
    public let teleportEnabled: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Shards")
    @runtimeProperty("ModSettings.description", "Show shards to read.")
    public let collectShards: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Tarot")
    @runtimeProperty("ModSettings.description", "Show tarot card graffiti.")
    public let collectTarot: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Iconic weapons")
    @runtimeProperty("ModSettings.description", "Show iconic weapons lying in the world.")
    public let collectWeapons: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Cyberware")
    @runtimeProperty("ModSettings.description", "Show legendary cyberware lying in the world.")
    public let collectCyberware: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Clothing")
    @runtimeProperty("ModSettings.description", "Show legendary clothing lying in the world.")
    public let collectClothing: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Skill shards")
    @runtimeProperty("ModSettings.description", "Show skill and perk shards.")
    public let collectSkill: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Show collected")
    @runtimeProperty("ModSettings.description", "Keep collected ones on the map, scratched out and faded.")
    public let collectShowCollected: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Minimap")
    @runtimeProperty("ModSettings.category.order", "6")
    @runtimeProperty("ModSettings.displayName", "Replace vanilla minimap")
    @runtimeProperty("ModSettings.description", "Show NightMap in place of the game's minimap. The Open / close map key expands it.")
    public let replaceMinimap: Bool = false;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Minimap")
    @runtimeProperty("ModSettings.category.order", "6")
    @runtimeProperty("ModSettings.displayName", "Corner map style")
    @runtimeProperty("ModSettings.description", "Circle, Square, or Square with a strip showing the district and the distance to the tracked objective.")
    @runtimeProperty("ModSettings.dependency", "replaceMinimap")
    @runtimeProperty("ModSettings.displayValues.Circle", "Circle")
    @runtimeProperty("ModSettings.displayValues.Square", "Square")
    @runtimeProperty("ModSettings.displayValues.SquareStrip", "Square + info strip")
    public let cornerStyle: NightMapCornerStyle = NightMapCornerStyle.SquareStrip;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Minimap")
    @runtimeProperty("ModSettings.category.order", "6")
    @runtimeProperty("ModSettings.displayName", "Corner map size")
    @runtimeProperty("ModSettings.description", "Size relative to the game's minimap, grown from its top-right corner.")
    @runtimeProperty("ModSettings.dependency", "replaceMinimap")
    @runtimeProperty("ModSettings.step", "0.05")
    @runtimeProperty("ModSettings.min", "0.75")
    @runtimeProperty("ModSettings.max", "1.5")
    public let cornerScale: Float = 1.0;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Minimap")
    @runtimeProperty("ModSettings.category.order", "6")
    @runtimeProperty("ModSettings.displayName", "Corner marker size")
    @runtimeProperty("ModSettings.description", "Marker size in the corner map.")
    @runtimeProperty("ModSettings.dependency", "replaceMinimap")
    @runtimeProperty("ModSettings.step", "0.1")
    @runtimeProperty("ModSettings.min", "0.5")
    @runtimeProperty("ModSettings.max", "2.0")
    public let cornerMarkerSize: Float = 1.0;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Minimap")
    @runtimeProperty("ModSettings.category.order", "6")
    @runtimeProperty("ModSettings.displayName", "Corner text size")
    @runtimeProperty("ModSettings.description", "Size of the corner map's labels and info strip.")
    @runtimeProperty("ModSettings.dependency", "replaceMinimap")
    @runtimeProperty("ModSettings.step", "0.1")
    @runtimeProperty("ModSettings.min", "0.5")
    @runtimeProperty("ModSettings.max", "2.0")
    public let cornerTextSize: Float = 1.0;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Minimap")
    @runtimeProperty("ModSettings.category.order", "6")
    @runtimeProperty("ModSettings.displayName", "Corner frame thickness")
    @runtimeProperty("ModSettings.description", "Thickness of the corner map's ring or brackets.")
    @runtimeProperty("ModSettings.dependency", "replaceMinimap")
    @runtimeProperty("ModSettings.step", "0.25")
    @runtimeProperty("ModSettings.min", "0.5")
    @runtimeProperty("ModSettings.max", "3.0")
    public let cornerFrameThickness: Float = 1.0;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Minimap")
    @runtimeProperty("ModSettings.category.order", "6")
    @runtimeProperty("ModSettings.displayName", "Corner map opacity")
    @runtimeProperty("ModSettings.description", "Background opacity of the corner map.")
    @runtimeProperty("ModSettings.dependency", "replaceMinimap")
    @runtimeProperty("ModSettings.step", "0.02")
    @runtimeProperty("ModSettings.min", "0.2")
    @runtimeProperty("ModSettings.max", "1.0")
    public let cornerOpacity: Float = 0.92;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Minimap")
    @runtimeProperty("ModSettings.category.order", "6")
    @runtimeProperty("ModSettings.displayName", "Enemies in corner map")
    @runtimeProperty("ModSettings.description", "Show enemy dots and vision cones in the corner map, whatever the filter view.")
    @runtimeProperty("ModSettings.dependency", "replaceMinimap")
    public let cornerEnemies: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Minimap")
    @runtimeProperty("ModSettings.category.order", "6")
    @runtimeProperty("ModSettings.displayName", "Police in corner map")
    @runtimeProperty("ModSettings.description", "Show police dots in the corner map.")
    @runtimeProperty("ModSettings.dependency", "replaceMinimap")
    public let cornerPolice: Bool = true;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Minimap")
    @runtimeProperty("ModSettings.category.order", "6")
    @runtimeProperty("ModSettings.displayName", "Expanded map size")
    @runtimeProperty("ModSettings.description", "Size of the expanded map panel (applies on next open).")
    @runtimeProperty("ModSettings.step", "0.05")
    @runtimeProperty("ModSettings.min", "0.7")
    @runtimeProperty("ModSettings.max", "1.0")
    public let expandedScale: Float = 1.0;

    @runtimeProperty("ModSettings.mod", "NightMap")
    @runtimeProperty("ModSettings.category", "Debug")
    @runtimeProperty("ModSettings.category.order", "5")
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
