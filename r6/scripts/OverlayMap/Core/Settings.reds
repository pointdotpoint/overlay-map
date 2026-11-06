module OverlayMap

public enum OverlayMapHoloColor {
    Cyan = 0,
    Green = 1,
    Red = 2,
    Purple = 3,
    Amber = 4
}

public enum OverlayMapCornerStyle {
    Circle = 0,
    Square = 1,
    SquareStrip = 2
}

public enum OverlayMapKeyboardMode {
    TakeKeys = 0,
    KeepMoving = 1
}

public enum OverlayMapPadOpen {
    HoldView = 0,
    Off = 1
}

public class OverlayMapSettings extends ScriptableSystem {
    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Open / close map")
    @runtimeProperty("ModSettings.description", "Toggles the OverlayMap overlay. With Debug on: Ctrl = self-test, Shift = perf suite, Alt = calibration dump, Ctrl+Shift = debug layer.")
    public let keyToggle: EInputKey = EInputKey.IK_SingleQuote;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan up")
    @runtimeProperty("ModSettings.description", "Hold to pan north. Numpad 7/9/1/3 pan diagonally.")
    public let keyPanUp: EInputKey = EInputKey.IK_NumPad8;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan down")
    @runtimeProperty("ModSettings.description", "Hold to pan south.")
    public let keyPanDown: EInputKey = EInputKey.IK_NumPad2;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan left")
    @runtimeProperty("ModSettings.description", "Hold to pan west.")
    public let keyPanLeft: EInputKey = EInputKey.IK_NumPad4;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Pan right")
    @runtimeProperty("ModSettings.description", "Hold to pan east.")
    public let keyPanRight: EInputKey = EInputKey.IK_NumPad6;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Zoom in")
    @runtimeProperty("ModSettings.description", "Hold to zoom in.")
    public let keyZoomIn: EInputKey = EInputKey.IK_NumPlus;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Zoom out")
    @runtimeProperty("ModSettings.description", "Hold to zoom out.")
    public let keyZoomOut: EInputKey = EInputKey.IK_NumMinus;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Recenter on V")
    @runtimeProperty("ModSettings.description", "Centers the map on V and follows V again.")
    public let keyRecenter: EInputKey = EInputKey.IK_NumPad5;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Act on selection")
    @runtimeProperty("ModSettings.description", "Activates the selected item.")
    public let keyAct: EInputKey = EInputKey.IK_NumPad0;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Set waypoint / track")
    @runtimeProperty("ModSettings.description", "On an empty spot or a pin: sets the custom waypoint there. On a job or gig: tracks its quest. On any other marker: tracks it. On the tracked one: clears it. Only while the map is open. Needs the OverlayMapNative plugin, except for quests.")
    public let keyWaypoint: EInputKey = EInputKey.IK_Enter;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Cycle marker filter")
    @runtimeProperty("ModSettings.description", "Cycles the map markers shown: All, Jobs, Services.")
    public let keyFilter: EInputKey = EInputKey.IK_NumSlash;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Teleport")
    @runtimeProperty("ModSettings.description", "Fast travels on a fast travel marker, and teleports to the selected marker or the map centre anywhere else.")
    public let keyTeleport: EInputKey = EInputKey.IK_NumPeriod;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys")
    @runtimeProperty("ModSettings.category.order", "0")
    @runtimeProperty("ModSettings.displayName", "Keyboard map")
    @runtimeProperty("ModSettings.description", "Takes keyboard and mouse: while the map is open V stops, and W A S D (or the arrows) pan, the mouse wheel zooms, Space follows V, F acts, T teleports and R cycles the filter; the numpad keys work too. Works on any keyboard. V keeps moving: the map only uses the numpad keys above, so V can walk and drive meanwhile.")
    @runtimeProperty("ModSettings.displayValues.TakeKeys", "Takes keyboard and mouse")
    @runtimeProperty("ModSettings.displayValues.KeepMoving", "V keeps moving (numpad)")
    public let keyboardMode: OverlayMapKeyboardMode = OverlayMapKeyboardMode.TakeKeys;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys (map takes keyboard)")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Pan up")
    @runtimeProperty("ModSettings.description", "Hold to pan north while the map takes the keyboard. The up arrow works too.")
    public let keyMapPanUp: EInputKey = EInputKey.IK_W;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys (map takes keyboard)")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Pan down")
    @runtimeProperty("ModSettings.description", "Hold to pan south while the map takes the keyboard. The down arrow works too.")
    public let keyMapPanDown: EInputKey = EInputKey.IK_S;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys (map takes keyboard)")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Pan left")
    @runtimeProperty("ModSettings.description", "Hold to pan west while the map takes the keyboard. The left arrow works too.")
    public let keyMapPanLeft: EInputKey = EInputKey.IK_A;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys (map takes keyboard)")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Pan right")
    @runtimeProperty("ModSettings.description", "Hold to pan east while the map takes the keyboard. The right arrow works too.")
    public let keyMapPanRight: EInputKey = EInputKey.IK_D;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys (map takes keyboard)")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Recenter on V")
    @runtimeProperty("ModSettings.description", "Centers the map on V and follows V again. The mouse wheel zooms.")
    public let keyMapRecenter: EInputKey = EInputKey.IK_Space;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys (map takes keyboard)")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Act on selection")
    @runtimeProperty("ModSettings.description", "Activates the selected item.")
    public let keyMapAct: EInputKey = EInputKey.IK_F;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys (map takes keyboard)")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Cycle marker filter")
    @runtimeProperty("ModSettings.description", "Cycles the map markers shown: All, Jobs, Services.")
    public let keyMapFilter: EInputKey = EInputKey.IK_R;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Keys (map takes keyboard)")
    @runtimeProperty("ModSettings.category.order", "1")
    @runtimeProperty("ModSettings.displayName", "Teleport")
    @runtimeProperty("ModSettings.description", "Fast travels on a fast travel marker, and teleports to the selected marker or the map centre anywhere else.")
    public let keyMapTeleport: EInputKey = EInputKey.IK_T;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Controller")
    @runtimeProperty("ModSettings.category.order", "2")
    @runtimeProperty("ModSettings.displayName", "Open map button")
    @runtimeProperty("ModSettings.description", "Hold View for half a second to open the map; a tap still does what it does in the game. While the map is open it takes the controller: left stick pans, LT/RT zoom, A acts, X teleports, Y cycles the filter, R3 follows V, B closes. Off: OverlayMap ignores the controller.")
    @runtimeProperty("ModSettings.displayValues.HoldView", "Hold View")
    @runtimeProperty("ModSettings.displayValues.Off", "Off")
    public let padOpen: OverlayMapPadOpen = OverlayMapPadOpen.HoldView;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Jobs")
    @runtimeProperty("ModSettings.description", "Show main and side job markers.")
    public let filterJobs: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Gigs")
    @runtimeProperty("ModSettings.description", "Show gig and fixer markers.")
    public let filterGigs: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Cyberpsycho Sighting")
    @runtimeProperty("ModSettings.description", "Show cyberpsycho sightings.")
    public let filterPsycho: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "NCPD Scanner")
    @runtimeProperty("ModSettings.description", "Show NCPD scanner hustles, stashes and outposts.")
    public let filterNcpd: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Fast Travel")
    @runtimeProperty("ModSettings.description", "Show fast-travel points and NCART stations.")
    public let filterFastTravel: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Ripperdoc")
    @runtimeProperty("ModSettings.description", "Show ripperdocs.")
    public let filterRipperdoc: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Vendor")
    @runtimeProperty("ModSettings.description", "Show vendors.")
    public let filterVendor: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Autofixer")
    @runtimeProperty("ModSettings.description", "Show vehicles for sale.")
    public let filterAutofixer: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Drop Point")
    @runtimeProperty("ModSettings.description", "Show drop points.")
    public let filterDropPoint: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Apartment for Rent")
    @runtimeProperty("ModSettings.description", "Show apartments for rent.")
    public let filterApartmentRent: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "TAROT")
    @runtimeProperty("ModSettings.description", "Show tarot graffiti.")
    public let filterTarot: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "NCART lines")
    @runtimeProperty("ModSettings.description", "Show the five NCART metro lines along their tracks (applies on next open).")
    public let filterNcart: Bool = false;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Map filters")
    @runtimeProperty("ModSettings.category.order", "4")
    @runtimeProperty("ModSettings.displayName", "Your Apartments")
    @runtimeProperty("ModSettings.description", "Show your apartments, vehicles and waypoint.")
    public let filterYourProperty: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Panel opacity")
    @runtimeProperty("ModSettings.description", "Background opacity of the map panel; low values let the world show through (applies on next open).")
    @runtimeProperty("ModSettings.step", "0.02")
    @runtimeProperty("ModSettings.min", "0.3")
    @runtimeProperty("ModSettings.max", "1.0")
    public let panelOpacity: Float = 0.5;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Map marker size")
    @runtimeProperty("ModSettings.description", "Size of the markers on the open map, where 1.0 is the original size (applies on next open). The corner map has its own Corner marker size.")
    @runtimeProperty("ModSettings.step", "0.05")
    @runtimeProperty("ModSettings.min", "0.25")
    @runtimeProperty("ModSettings.max", "1.5")
    public let markerSize: Float = 0.5;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Hologram colour")
    @runtimeProperty("ModSettings.description", "Tints the map tiles, overlays, frame and header text (applies on next open).")
    @runtimeProperty("ModSettings.displayValues.Cyan", "Cyan")
    @runtimeProperty("ModSettings.displayValues.Green", "Green")
    @runtimeProperty("ModSettings.displayValues.Red", "Red")
    @runtimeProperty("ModSettings.displayValues.Purple", "Purple")
    @runtimeProperty("ModSettings.displayValues.Amber", "Amber")
    public let holoColor: OverlayMapHoloColor = OverlayMapHoloColor.Cyan;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Hologram effects")
    @runtimeProperty("ModSettings.description", "Grid, scanlines, noise, scan bar, edge glow and marker halos, with their animations. Off gives a plain background. Glow strength is separate (applies on next open).")
    public let hologramEffects: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Scanline strength")
    @runtimeProperty("ModSettings.description", "How dark the moving scanlines over the map are. 0 hides them. Needs Hologram effects (applies on next open).")
    @runtimeProperty("ModSettings.step", "0.02")
    @runtimeProperty("ModSettings.min", "0")
    @runtimeProperty("ModSettings.max", "0.6")
    public let scanlineStrength: Float = 0.3;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Glow strength")
    @runtimeProperty("ModSettings.description", "How strongly the roads glow. 0 turns the glow off. Works with or without Hologram effects (applies on next open).")
    @runtimeProperty("ModSettings.step", "0.1")
    @runtimeProperty("ModSettings.min", "0")
    @runtimeProperty("ModSettings.max", "3")
    public let glowStrength: Float = 1.5;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "VHS tracking band")
    @runtimeProperty("ModSettings.description", "A noisy band that rolls down the map now and then, like a worn tape. Needs Hologram effects (applies on next open).")
    public let vhsTracking: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "VHS glitch")
    @runtimeProperty("ModSettings.description", "A short picture glitch every few seconds. Needs Hologram effects (applies on next open).")
    public let vhsGlitch: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Follow HUD Painter colours")
    @runtimeProperty("ModSettings.description", "Take every OverlayMap colour from the game's HUD palette, so HUD Painter presets recolour the map. Off keeps OverlayMap's own colours.")
    public let followHudPainter: Bool = false;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "GPS routes")
    @runtimeProperty("ModSettings.description", "Show the waypoint and quest routes from the minimap.")
    public let showRoutes: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Photo pins")
    @runtimeProperty("ModSettings.description", "Show a thumbnail pin where each photo mode shot was taken (shows in the ALL filter view).")
    public let showPhotos: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Hide HUD while open")
    @runtimeProperty("ModSettings.description", "Fade out the game's HUD (minimap, quest tracker, hotkeys, prompts) while the map is open.")
    public let hideHud: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Hold key to show")
    @runtimeProperty("ModSettings.description", "Show the map only while the toggle key is held, instead of pressing it to open and again to close.")
    public let holdToShow: Bool = false;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Teleport key")
    @runtimeProperty("ModSettings.description", "Teleport from OverlayMap to any spot on the map: fast travels on a fast travel marker, teleports anywhere else.")
    public let teleportEnabled: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "5")
    @runtimeProperty("ModSettings.displayName", "Shards")
    @runtimeProperty("ModSettings.description", "Show shards to read.")
    public let collectShards: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "5")
    @runtimeProperty("ModSettings.displayName", "Tarot")
    @runtimeProperty("ModSettings.description", "Show tarot card graffiti.")
    public let collectTarot: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "5")
    @runtimeProperty("ModSettings.displayName", "Iconic weapons")
    @runtimeProperty("ModSettings.description", "Show iconic weapons lying in the world.")
    public let collectWeapons: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "5")
    @runtimeProperty("ModSettings.displayName", "Cyberware")
    @runtimeProperty("ModSettings.description", "Show legendary cyberware lying in the world.")
    public let collectCyberware: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "5")
    @runtimeProperty("ModSettings.displayName", "Clothing")
    @runtimeProperty("ModSettings.description", "Show legendary clothing lying in the world.")
    public let collectClothing: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "5")
    @runtimeProperty("ModSettings.displayName", "Skill shards")
    @runtimeProperty("ModSettings.description", "Show skill and perk shards.")
    public let collectSkill: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Collectibles")
    @runtimeProperty("ModSettings.category.order", "5")
    @runtimeProperty("ModSettings.displayName", "Show collected")
    @runtimeProperty("ModSettings.description", "Keep collected ones on the map, scratched out and faded.")
    public let collectShowCollected: Bool = true;

    // Corner minimap: shelved 2026-11-03 (NMCornerHost.Shelved). Not shown in Mod Settings; kept so the code still builds
    // and the feature can come back. Defaults only.
    public let replaceMinimap: Bool = false;
    public let cornerStyle: OverlayMapCornerStyle = OverlayMapCornerStyle.SquareStrip;
    public let cornerScale: Float = 1.0;
    public let cornerMarkerSize: Float = 1.0;
    public let cornerTextSize: Float = 1.0;
    public let cornerFrameThickness: Float = 1.0;
    public let cornerOpacity: Float = 0.92;
    public let cornerEnemies: Bool = true;
    public let cornerPolice: Bool = true;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Display")
    @runtimeProperty("ModSettings.category.order", "3")
    @runtimeProperty("ModSettings.displayName", "Map size")
    @runtimeProperty("ModSettings.description", "Size of the map panel (applies on next open).")
    @runtimeProperty("ModSettings.step", "0.05")
    @runtimeProperty("ModSettings.min", "0.7")
    @runtimeProperty("ModSettings.max", "1.0")
    public let expandedScale: Float = 1.0;

    @runtimeProperty("ModSettings.mod", "Overlay Map")
    @runtimeProperty("ModSettings.category", "Debug")
    @runtimeProperty("ModSettings.category.order", "6")
    @runtimeProperty("ModSettings.displayName", "Debug tools")
    @runtimeProperty("ModSettings.description", "Enables the debug key chords and the clip probe.")
    public let debug: Bool = false;

    private func OnAttach() {
        OverlayMapRegisterSettings(this);
    }

    private func OnDetach() {
        OverlayMapUnregisterSettings(this);
    }

    public static func Get(game: GameInstance) -> ref<OverlayMapSettings> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"OverlayMap.OverlayMapSettings") as OverlayMapSettings;
    }
}

@if(ModuleExists("ModSettingsModule"))
public func OverlayMapRegisterSettings(s: ref<OverlayMapSettings>) {
    ModSettings.RegisterListenerToClass(s);
}

@if(!ModuleExists("ModSettingsModule"))
public func OverlayMapRegisterSettings(s: ref<OverlayMapSettings>) {}

@if(ModuleExists("ModSettingsModule"))
public func OverlayMapUnregisterSettings(s: ref<OverlayMapSettings>) {
    ModSettings.UnregisterListenerToClass(s);
}

@if(!ModuleExists("ModSettingsModule"))
public func OverlayMapUnregisterSettings(s: ref<OverlayMapSettings>) {}
