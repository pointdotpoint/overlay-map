module NightMap

// Photo mode session hooks: entering records where V stands (V cannot move in photo mode), leaving resolves new
// shots. OnShow/OnHide run on every visit (intro/outro animations); OnInitialize/OnUninitialize only once per game.
@wrapMethod(gameuiPhotoModeMenuController)
protected cb func OnShow(reversedUI: Bool) -> Bool {
    let r = wrappedMethod(reversedUI);
    let sys = NightMapSystem.Get(GetGameInstance());
    let player = GetPlayer(GetGameInstance());
    if IsDefined(sys) && IsDefined(player) {
        sys.Photos().OnPhotoModeOpened(player.GetWorldPosition(), player.GetWorldYaw(), sys.DistrictName());
    }
    return r;
}

@wrapMethod(gameuiPhotoModeMenuController)
protected cb func OnHide() -> Bool {
    let r = wrappedMethod();
    let sys = NightMapSystem.Get(GetGameInstance());
    if IsDefined(sys) {
        sys.Photos().OnPhotoModeClosed();
    }
    return r;
}
