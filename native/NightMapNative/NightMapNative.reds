// NightMapNative: optional engine calls for NightMap (waypoints). Shipped by the plugin and loaded only when its DLL
// loads (RED4ext script registration), so NightMap guards every use with @if(ModuleExists("NightMapNative")).
// The natives themselves live in NightMapNative.Global.reds: on game 2.5 a global native declared inside a module
// crashes the game at script load (waypoints spike FINDINGS); this module only marks the plugin as present.
module NightMapNative

public abstract class NightMapNativeMarker {}
