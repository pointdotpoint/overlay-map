// OverlayMapNative natives (root module: see OverlayMapNative.reds).
public static native func OverlayMapNative_Version() -> Int32
// Wall clock in ms since the plugin loaded (precise; the engine time scripts see ticks every 31.25 ms).
public static native func OverlayMapNative_NowMs() -> Float
// Photo pins: the whole of <game>/r6/storages/OverlayMap/photos.txt ("" when there is none yet), and an append to it.
public static native func OverlayMapNative_PhotoStoreRead() -> String
public static native func OverlayMapNative_PhotoStoreAppend(text: String) -> Bool
// True when the plugin can read native parameters on this game build. False → never call PhotoStoreAppend: it can't
// consume its argument, and the leftover bytecode crashes the caller's script.
public static native func OverlayMapNative_ParamsReadable() -> Bool
// Welcome screen: shown once per install (<game>/r6/storages/OverlayMap/welcome_seen).
public static native func OverlayMapNative_WelcomeSeen() -> Bool
public static native func OverlayMapNative_MarkWelcomeSeen() -> Bool
// Diagnostics: the four world-map natives' bodies as RVAs, and why the engine calls are (un)available.
public static native func OverlayMapNative_Rvas() -> String
public static native func OverlayMapNative_Why() -> String
// True when the plugin recognised this game build's mappin tracking code. False → never call TrackMappin: on an
// unrecognised build it can't read its parameters, and calling it corrupts the caller's script.
public static native func OverlayMapNative_Available() -> Bool
// Tracks a mappin as the world map does (GPS route, objective). False if refused (bad id, wrong object). A mappin
// registered this frame isn't resolvable yet: track it once MappinSystem.GetMappin(id) returns it.
public static native func OverlayMapNative_TrackMappin(system: ref<MappinSystem>, id: NewMappinID) -> Bool
