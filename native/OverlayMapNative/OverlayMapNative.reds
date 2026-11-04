// OverlayMapNative: optional engine calls for OverlayMap (waypoints). Shipped by the plugin and loaded only when its DLL
// loads (RED4ext script registration), so OverlayMap guards every use with @if(ModuleExists("OverlayMapNative")).
// The natives themselves live in OverlayMapNative.Global.reds: on game 2.5 a global native declared inside a module
// crashes the game at script load (waypoints spike FINDINGS); this module only marks the plugin as present.
module OverlayMapNative

public abstract class OverlayMapNativeMarker {}
