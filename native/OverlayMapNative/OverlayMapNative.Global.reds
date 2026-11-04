// OverlayMapNative natives (root module: see OverlayMapNative.reds).
public static native func OverlayMapNative_Version() -> Int32
// Diagnostics: the four world-map natives' bodies as RVAs, and why the engine calls are (un)available.
public static native func OverlayMapNative_Rvas() -> String
public static native func OverlayMapNative_Why() -> String
// True when the plugin recognised this game build's mappin tracking code. False → never call TrackMappin: on an
// unrecognised build it can't read its parameters, and calling it corrupts the caller's script.
public static native func OverlayMapNative_Available() -> Bool
// Tracks a mappin as the world map does (GPS route, objective). False if refused (bad id, wrong object). A mappin
// registered this frame isn't resolvable yet: track it once MappinSystem.GetMappin(id) returns it.
public static native func OverlayMapNative_TrackMappin(system: ref<MappinSystem>, id: NewMappinID) -> Bool
