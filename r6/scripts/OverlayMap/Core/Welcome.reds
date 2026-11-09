module OverlayMap

// First-run welcome screen: the game's own tutorial popup with the open key, the three Controls modes and the themes
// banner (overlaymap\ui\welcome.inkatlas) under the text. Shown once per install: the OverlayMapNative plugin keeps a
// flag file; without the plugin a quest fact keeps it per save. It waits for free gameplay (no menu, scene, combat or
// vehicle) and a few calm seconds before it opens.
public abstract class NMWelcome {
    public static func Title() -> String { return "OVERLAY MAP"; }
    public static func Atlas() -> ResRef { return r"overlaymap\\ui\\welcome.inkatlas"; }
    public static func FactName() -> CName { return n"overlay_map_welcome_seen"; }

    public static func Seen(game: GameInstance) -> Bool {
        if NMWelcomeSeenNativeImpl() { return true; }
        let q = GameInstance.GetQuestsSystem(game);
        return IsDefined(q) && q.GetFact(NMWelcome.FactName()) > 0;
    }

    public static func Mark(game: GameInstance) {
        NMWelcomeMarkNativeImpl();
        let q = GameInstance.GetQuestsSystem(game);
        if IsDefined(q) { q.SetFact(NMWelcome.FactName(), 1); }
    }

    public static func OpenKeyText(s: ref<OverlayMapSettings>) -> String {
        let key = NMInput.KeyName(s.keyToggle);
        if Equals(s.keyToggleMod, OverlayMapOpenModifier.Shift) { return "SHIFT + " + key; }
        if Equals(s.keyToggleMod, OverlayMapOpenModifier.Ctrl) { return "CTRL + " + key; }
        if Equals(s.keyToggleMod, OverlayMapOpenModifier.ShiftCtrl) { return "SHIFT + CTRL + " + key; }
        return key;
    }

    public static func ModeName(m: OverlayMapKeyboardMode) -> String {
        if Equals(m, OverlayMapKeyboardMode.KeepMoving) { return "Numpad"; }
        if Equals(m, OverlayMapKeyboardMode.MouseOnly) { return "Mouse only"; }
        return "WASD";
    }

    private static func Green(text: String) -> String {
        return "<Rich color=\"#00ff00\" style=\"Bold\">" + text + "</>";
    }

    public static func Message(s: ref<OverlayMapSettings>) -> String {
        return "A live map of Night City, drawn over your game.\nNo pause, no menu.\n\n"
            + NMWelcome.Green("Open / close: " + NMWelcome.OpenKeyText(s)) + "\n"
            + "You might want to change the default keybind to something more easily accessible.\n\n"
            + NMWelcome.Green("Controls") + " (Settings > Mods > Overlay Map):\n"
            + "Make sure to choose your preferred method of usage:\n"
            + "WASD - V stops; the keyboard drives the map.\n"
            + "Numpad - V keeps moving; the map uses the numpad.\n"
            + "Mouse only - V keeps moving; the mouse drives the map.\n\n"
            + NMWelcome.Green("Current: " + NMWelcome.ModeName(s.keyboardMode));
    }

    // Sends the popup through the UI blackboard, as the game's own tutorials do. False if the blackboard is missing.
    public static func Present(game: GameInstance, s: ref<OverlayMapSettings>) -> Bool {
        let ui = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);
        if !IsDefined(ui) { return false; }
        let settings: PopupSettings;
        settings.closeAtInput = true;
        settings.pauseGame = true;
        settings.fullscreen = true;
        settings.hideInMenu = true;
        settings.position = PopupPosition.Center;
        settings.margin = new inkMargin(0.0, 0.0, 0.0, 0.0);
        let data: PopupData;
        data.title = NMWelcome.Title();
        data.message = NMWelcome.Message(s);
        data.isModal = true;
        data.videoType = VideoType.Unknown;
        ui.SetVariant(GetAllBlackboardDefs().UIGameData.Popup_Settings, ToVariant(settings));
        ui.SetVariant(GetAllBlackboardDefs().UIGameData.Popup_Data, ToVariant(data));
        ui.SignalVariant(GetAllBlackboardDefs().UIGameData.Popup_Data);
        return true;
    }

    // Starts the wait for a calm moment. Called on every player attach (load, new game); does nothing once seen.
    public static func Schedule(player: ref<GameObject>) {
        if !IsDefined(player) || NMWelcome.Seen(player.GetGame()) { return; }
        let cue = new NMWelcomeCue();
        cue.player = player;
        GameInstance.GetDelaySystem(player.GetGame()).DelayCallback(cue, 10.0, false);
    }
}

@if(ModuleExists("OverlayMapNative"))
public func NMWelcomeSeenNativeImpl() -> Bool { return OverlayMapNative_WelcomeSeen(); }
@if(!ModuleExists("OverlayMapNative"))
public func NMWelcomeSeenNativeImpl() -> Bool { return false; }
@if(ModuleExists("OverlayMapNative"))
public func NMWelcomeMarkNativeImpl() { OverlayMapNative_MarkWelcomeSeen(); }
@if(!ModuleExists("OverlayMapNative"))
public func NMWelcomeMarkNativeImpl() {}

// Polls every 3 s until gameplay has been calm for three checks in a row, then shows the popup once. Gives up after
// about 20 minutes of scenes or menus (the next load tries again).
public class NMWelcomeCue extends DelayCallback {
    public let player: wref<GameObject>;
    public let calm: Int32;
    public let tries: Int32;

    private func Busy(game: GameInstance) -> Bool {
        let ui = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UI_System);
        if IsDefined(ui) && ui.GetBool(GetAllBlackboardDefs().UI_System.IsInMenu) { return true; }
        let photo = GameInstance.GetPhotoModeSystem(game);
        if IsDefined(photo) && photo.IsPhotoModeActive() { return true; }
        let psm = GameInstance.GetBlackboardSystem(game).GetLocalInstanced(this.player.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
        if !IsDefined(psm) { return true; }
        if psm.GetInt(GetAllBlackboardDefs().PlayerStateMachine.SceneTier) > 2 { return true; }
        if psm.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Combat) == EnumInt(gamePSMCombat.InCombat) { return true; }
        if IsDefined(GetMountedVehicle(this.player)) { return true; }
        let sys = OverlayMapSystem.Get(game);
        return IsDefined(sys) && sys.IsOpen();
    }

    public func Call() {
        if !IsDefined(this.player) { return; }
        let game = this.player.GetGame();
        if NMWelcome.Seen(game) { return; }
        if this.Busy(game) {
            this.calm = 0;
        } else {
            this.calm += 1;
        }
        if this.calm >= 3 {
            let s = OverlayMapSettings.Get(game);
            if IsDefined(s) && NMWelcome.Present(game, s) {
                NMWelcome.Mark(game);
                NMLog.Info("welcome|shown");
                return;
            }
        }
        if this.tries >= 400 { return; }
        let next = new NMWelcomeCue();
        next.player = this.player;
        next.calm = this.calm;
        next.tries = this.tries + 1;
        GameInstance.GetDelaySystem(game).DelayCallback(next, 3.0, false);
    }
}

// The banner goes under the text: the popup's image widget gets our atlas and moves to just after the message.
@wrapMethod(TutorialPopupDisplayController)
public func SetData(data: ref<TutorialPopupData>, inputDevice: InputDevice, inputScheme: InputScheme) {
    wrappedMethod(data, inputDevice, inputScheme);
    if !IsDefined(data) || NotEquals(data.title, NMWelcome.Title()) { return; }
    let img = inkWidgetRef.Get(this.m_image) as inkImage;
    let msg = inkWidgetRef.Get(this.m_message);
    if !IsDefined(img) || !IsDefined(msg) { return; }
    img.SetAtlasResource(NMWelcome.Atlas());
    img.SetTexturePart(n"welcome");
    img.SetVisible(true);
    let parent = msg.GetParentWidget() as inkCompoundWidget;
    if !IsDefined(parent) { return; }
    let n = parent.GetNumChildren();
    let i = 0;
    let at = -1;
    let imgAt = -1;
    while i < n {
        let w = parent.GetWidgetByIndex(i);
        if w == msg { at = i; }
        if w == img { imgAt = i; }
        i += 1;
    }
    if at < 0 { return; }
    if imgAt >= 0 {
        // Removing the image first shifts the message up by one when the image came before it.
        parent.ReorderChild(img, imgAt < at ? at : at + 1);
    } else {
        img.Reparent(parent, at + 1);
    }
}
