module NightMap

// Photo mode session hooks: open records where V stands (V cannot move in photo mode), close resolves new shots.
@wrapMethod(gameuiPhotoModeMenuController)
protected cb func OnInitialize() -> Bool {
    let r = wrappedMethod();
    let sys = NightMapSystem.Get(GetGameInstance());
    let player = GetPlayer(GetGameInstance());
    if IsDefined(sys) && IsDefined(player) {
        sys.Photos().OnPhotoModeOpened(player.GetWorldPosition(), player.GetWorldYaw());
    }
    return r;
}

@wrapMethod(gameuiPhotoModeMenuController)
protected cb func OnUninitialize() -> Bool {
    let r = wrappedMethod();
    let sys = NightMapSystem.Get(GetGameInstance());
    if IsDefined(sys) {
        sys.Photos().OnPhotoModeClosed();
    }
    return r;
}
