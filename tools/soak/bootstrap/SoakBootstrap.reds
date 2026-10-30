module SoakBootstrap
import RedFileSystem.*
@if(ModuleExists("NightMap"))
import NightMap.*

// Soak harness bootstrap, ported from ~/photomode_ui_improvements/scripts/soak/bootstrap. Installed only during a
// campaign, never shipped. Talks to the supervisor through r6/storages/SoakBootstrap (tools/soak/channel.py): reads
// plan.txt and command.txt, appends state.txt, rewrites heartbeat.txt. Does nothing without a complete plan.txt.
// OnLoad only registers callbacks: no files or game systems there.

public class SoakTick extends DelayCallback {
    public func Call() {
        let channel = SoakChannel.Get();
        if IsDefined(channel) { channel.OnTick(); }
    }
}

public class SoakChannel extends ScriptableService {
    private let m_attempted: Bool;
    private let m_storage: ref<FileSystemStorage>;
    private let m_planRead: Bool;
    private let m_run: String;
    private let m_save: String;
    private let m_seq: Int32;
    private let m_beats: Int32;
    private let m_loadRequested: Bool;
    private let m_ticking: Bool;
    private let m_worldReported: Bool;
    private let m_exiting: Bool;
    private let m_lastCommand: String;
    private let m_watch: array<ref<CallbackHandle>>;

    public static func Get() -> ref<SoakChannel> {
        return GameInstance.GetScriptableServiceContainer().GetService(n"SoakBootstrap.SoakChannel") as SoakChannel;
    }

    private cb func OnLoad() {
        GameInstance.GetCallbackSystem().RegisterCallback(n"Session/Ready", this, n"OnSessionReady")
            .SetLifetime(CallbackLifetime.Forever);
    }

    private func Storage() -> ref<FileSystemStorage> {
        if !this.m_attempted {
            this.m_attempted = true;
            this.m_storage = FileSystem.GetStorage("SoakBootstrap");
        }
        return this.m_storage;
    }

    // plan.txt: key=value lines ending with end=1 (one without it is still being written).
    public func ReadPlan() -> Bool {
        if this.m_planRead { return true; }
        let storage = this.Storage();
        if !IsDefined(storage) || NotEquals(storage.IsFile("plan.txt"), FileSystemStatus.True) { return false; }
        let complete = false;
        for line in storage.GetFile("plan.txt").ReadAsLines() {
            let eq = StrFindFirst(line, "=");
            if eq > 0 {
                let key = StrLeft(line, eq);
                let value = StrMid(line, eq + 1);
                if Equals(key, "run") { this.m_run = value; }
                if Equals(key, "save") { this.m_save = value; }
                if Equals(key, "end") { complete = true; }
            }
        }
        this.m_planRead = complete && StrLen(this.m_run) > 0;
        return this.m_planRead;
    }

    public func State(state: String, detail: String) {
        if !this.ReadPlan() { return; }
        this.m_seq += 1;
        let clean = StrReplaceAll(StrReplaceAll(detail, "\t", " "), "\n", " ");
        let line = this.m_run + "\t" + IntToString(this.m_seq) + "\t" + Soak_BuildId() + "\t" + IntToString(this.m_beats)
            + "\t" + state + "\t" + clean + "\n";
        this.Storage().GetFile("state.txt").WriteText(line, FileSystemWriteMode.Append);
    }

    public func Beat(mode: String, position: String) {
        if !this.ReadPlan() { return; }
        this.m_beats += 1;
        let line = this.m_run + "\t" + IntToString(this.m_beats) + "\t" + mode + "\t" + position + "\n";
        this.Storage().GetFile("heartbeat.txt").WriteText(line, FileSystemWriteMode.Truncate);
    }

    // command.txt: "<run>\t<command>"; another run's command is ignored.
    public func Command() -> String {
        if !this.ReadPlan() { return ""; }
        let storage = this.Storage();
        if NotEquals(storage.IsFile("command.txt"), FileSystemStatus.True) { return ""; }
        for line in storage.GetFile("command.txt").ReadAsLines() {
            let tab = StrFindFirst(line, "\t");
            if tab > 0 && Equals(StrLeft(line, tab), this.m_run) {
                return StrMid(line, tab + 1);
            }
        }
        return "";
    }

    // ---- main menu: load the plan's save ----

    public func OnMainMenu(menu: ref<SingleplayerMenuGameController>) {
        if this.m_loadRequested || !this.ReadPlan() { return; }
        this.State("menu", "");
        let handler = GameInstance.GetSystemRequestsHandler();
        handler.RegisterToCallback(n"OnSavesForLoadReady", menu, n"Soak_OnSaves");
        handler.RequestSavesForLoad();
    }

    public func OnSaves(saves: array<String>) {
        if this.m_loadRequested { return; }
        this.State("saves", IntToString(ArraySize(saves)));
        let index = ArrayFindFirst(saves, this.m_save);
        if index < 0 {
            this.State("infra_error", "save not listed: " + this.m_save);
            return;
        }
        this.m_loadRequested = true;
        this.State("save_found", IntToString(index));
        GameInstance.GetSystemRequestsHandler().LoadSavedGame(index);
        this.State("loading", "");
    }

    // ---- the world: settle, then a heartbeat with the player's position; commands; exit ----

    private cb func OnSessionReady(event: ref<GameSessionEvent>) {
        if event.IsPreGame() || !this.ReadPlan() { return; }
        this.State("session_ready", "");
        if !this.m_ticking {
            this.m_ticking = true;
            this.WatchFastTravel();
            this.Schedule(5.0);
        }
    }

    // The game's own view of a trip: which of these flags fires tells where a stuck trip stopped.
    private func WatchFastTravel() {
        let defs = GetAllBlackboardDefs().FastTRavelSystem;
        let bb = GameInstance.GetBlackboardSystem(GetGameInstance()).Get(defs);
        ArrayPush(this.m_watch, bb.RegisterListenerBool(defs.FastTravelStarted, this, n"OnFtStarted"));
        ArrayPush(this.m_watch, bb.RegisterListenerBool(defs.FastTravelLoadingScreenStarted, this, n"OnFtLoadStarted"));
        ArrayPush(this.m_watch, bb.RegisterListenerBool(defs.FastTravelLoadingScreenFinished, this, n"OnFtLoadFinished"));
    }

    protected cb func OnFtStarted(value: Bool) -> Bool { this.State("ft_started", ToString(value)); return true; }
    protected cb func OnFtLoadStarted(value: Bool) -> Bool { this.State("ft_load_started", ToString(value)); return true; }
    protected cb func OnFtLoadFinished(value: Bool) -> Bool { this.State("ft_load_finished", ToString(value)); return true; }

    private func Schedule(delay: Float) {
        GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(new SoakTick(), delay, false);
    }

    private func PositionText() -> String {
        let player = GetPlayer(GetGameInstance());
        if !IsDefined(player) { return ""; }
        let p = player.GetWorldPosition();
        return FloatToStringPrec(p.X, 2) + "," + FloatToStringPrec(p.Y, 2) + "," + FloatToStringPrec(p.Z, 2);
    }

    public func OnTick() {
        if !this.m_worldReported {
            this.m_worldReported = true;
            this.State("world", "");
        }
        this.Beat("world", this.PositionText());
        let command = this.Command();
        if !this.m_exiting && Equals(command, "exit") {
            this.m_exiting = true;
            this.State("exit_requested", "");
            GameInstance.GetSystemRequestsHandler().ExitGame();
            return;
        }
        if StrLen(command) > 0 && NotEquals(command, this.m_lastCommand) {
            this.m_lastCommand = command;
            let space = StrFindFirst(command, " ");
            let tag = StrLeft(command, space);
            this.State("done", tag + " " + Soak_RunCommand(StrMid(command, space + 1)));
        }
        this.Schedule(0.25);
    }
}

// The mod's commands (tools/soak/autopilot/SoakHooks.reds); a no-mod control run has none.
@if(ModuleExists("NightMap"))
public func Soak_RunCommand(command: String) -> String = NMSoak.Run(command)

@if(!ModuleExists("NightMap"))
public func Soak_RunCommand(command: String) -> String = "unknown"

@wrapMethod(SingleplayerMenuGameController)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    let channel = SoakChannel.Get();
    if IsDefined(channel) { channel.OnMainMenu(this); }
    return result;
}

@addMethod(SingleplayerMenuGameController)
protected cb func Soak_OnSaves(saves: array<String>) -> Bool {
    let channel = SoakChannel.Get();
    if IsDefined(channel) { channel.OnSaves(saves); }
    return true;
}

// A campaign restores the save folder afterwards, but with Steam Cloud on an autosave could upload first.
@wrapMethod(FastTravelSystem)
private func RequestAutoSaveWithDelay() {
    let channel = SoakChannel.Get();
    if IsDefined(channel) && channel.ReadPlan() {
        channel.State("autosave_blocked", "");
        return;
    }
    wrappedMethod();
}

// That the game took the request: the game log is lost when a hung game is killed, the channel is not.
@wrapMethod(FastTravelSystem)
private func OnPerformFastTravelRequest(request: ref<PerformFastTravelRequest>) {
    let channel = SoakChannel.Get();
    if IsDefined(channel) { channel.State("ft_request", ""); }
    wrappedMethod(request);
    if IsDefined(channel) { channel.State("ft_requested", ""); }
}
