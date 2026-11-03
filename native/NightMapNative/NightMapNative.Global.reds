// NightMapNative natives (root module: see NightMapNative.reds).
public static native func NightMapNative_Version() -> Int32
// Diagnostics: the four world-map natives' bodies as RVAs, and why the engine calls are (un)available.
public static native func NightMapNative_Rvas() -> String
public static native func NightMapNative_Why() -> String
// True when the plugin recognised this game build's mappin tracking code; false → never call TrackMappin.
public static native func NightMapNative_Available() -> Bool
// Tracks a mappin as the world map does (GPS route, objective). False if refused (unknown build, bad id). A mappin
// registered this frame isn't resolvable yet: track it once MappinSystem.GetMappin(id) returns it.
public static native func NightMapNative_TrackMappin(system: ref<MappinSystem>, id: NewMappinID) -> Bool
