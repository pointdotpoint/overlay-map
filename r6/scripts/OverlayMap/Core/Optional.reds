module OverlayMap
@if(ModuleExists("RedIMGRetriever"))
import RedIMGRetriever.*

// Wall clock in ms. Our plugin's clock (OverlayMapNative) or RedIMG's is precise; the fallback (EngineTime) only ticks
// every 31.25 ms, so per-frame motion would stutter above 32 FPS.
public abstract class NMClock {
    public static func NowMs() -> Float {
        return NMClockNow();
    }
    public static func Precise() -> Bool {
        return NMClockPrecise();
    }
}

@if(ModuleExists("OverlayMapNative"))
public func NMClockNow() -> Float {
    return OverlayMapNative_NowMs();
}

@if(!ModuleExists("OverlayMapNative") && ModuleExists("RedIMGRetriever"))
public func NMClockNow() -> Float {
    return RedIMG.NowMs();
}

@if(!ModuleExists("OverlayMapNative") && !ModuleExists("RedIMGRetriever"))
public func NMClockNow() -> Float {
    return EngineTime.ToFloat(GameInstance.GetEngineTime(GetGameInstance())) * 1000.0;
}

@if(ModuleExists("OverlayMapNative") || ModuleExists("RedIMGRetriever"))
public func NMClockPrecise() -> Bool {
    return true;
}

@if(!ModuleExists("OverlayMapNative") && !ModuleExists("RedIMGRetriever"))
public func NMClockPrecise() -> Bool {
    return false;
}

// Image items: RedIMG key -> mounted atlas path ("" while loading or when RedIMG is absent).
@if(ModuleExists("RedIMGRetriever"))
public func NMResolveImage(key: String) -> String {
    return RedIMG.PrepareDocImage(key);
}

@if(!ModuleExists("RedIMGRetriever"))
public func NMResolveImage(key: String) -> String {
    return "";
}

// True when image items can ever resolve (RedIMG installed); otherwise they stay on the fallback icon without retrying.
@if(ModuleExists("RedIMGRetriever"))
public func NMImagesAvailable() -> Bool {
    return true;
}

@if(!ModuleExists("RedIMGRetriever"))
public func NMImagesAvailable() -> Bool {
    return false;
}
