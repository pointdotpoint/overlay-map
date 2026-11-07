module OverlayMap

@if(ModuleExists("OverlayMapNative"))
import OverlayMapNative.*
import SoakBootstrap.*
import RedFileSystem.*

// The soak harness's commands, overlaid into the scripts only during a campaign (tools/soak/builds.py); never shipped.
// tools/soak/runner.py sends one command at a time and reads the answer as a "done" state. redscript's annotations
// can't target classes defined in scripts, so the bootstrap calls this directly and OverlayMapSystem's Soak_* methods are
// spliced into the staged class from SystemBody.inc, which gives them its private fields.
public abstract class NMSoak {
    public static func Run(command: String) -> String {
        let sys = OverlayMapSystem.Get(GetGameInstance());
        if !IsDefined(sys) { return "no system"; }
        if Equals(command, "open") {
            sys.Open();
            return "open";
        }
        if Equals(command, "close") {
            sys.Close();
            return "closed";
        }
        if Equals(command, "focus_ft far") { return sys.Soak_FocusFastTravel(); }
        if Equals(command, "selected") { return sys.Soak_Selected(); }
        if Equals(command, "area") { return sys.Soak_Area(); }
        if Equals(command, "area_names") { return sys.Soak_AreaNames(); }
        if Equals(command, "counts") { return sys.Soak_Counts(); }
        if Equals(command, "layers") { return sys.Soak_Layers(); }
        if Equals(command, "act") { return sys.Soak_Act(); }
        if Equals(command, "desc_probe") { return NMSoakDesc.Add(sys); }
        if StrBeginsWith(command, "focus_layer ") {
            let fl = StrSplit(command, " ");
            if ArraySize(fl) < 3 { return "usage: focus_layer <id part> <mpp>"; }
            return sys.Soak_FocusLayer(fl[1], StringToFloat(fl[2]));
        }
        if StrBeginsWith(command, "focus_quest ") { return sys.Soak_FocusQuest(StringToFloat(StrAfterFirst(command, " "))); }
        if Equals(command, "perf") { return sys.Soak_Perf(""); }
        if Equals(command, "perf_route") { return sys.Soak_Perf("route"); }
        if StrBeginsWith(command, "set ") {
            let sv = StrSplit(command, " ");
            if ArraySize(sv) < 3 { return "usage: set <name> <value>"; }
            return sys.Soak_Set(sv[1], sv[2]);
        }
        if Equals(command, "is_open") { return sys.Soak_IsOpen(); }
        if Equals(command, "watch_keys") { return sys.Soak_WatchKeys(); }
        if Equals(command, "last_keys") { return sys.Soak_LastKeys(); }
        if StrBeginsWith(command, "press ") { return sys.Soak_PressBound(StrAfterFirst(command, " ")); }
        if Equals(command, "hold_mode") { return sys.Soak_HoldMode(); }
        if Equals(command, "watch_axis") { return sys.Soak_WatchAxis(); }
        if Equals(command, "last_axis") { return sys.Soak_LastAxis(); }
        if Equals(command, "in_menu") { return sys.Soak_InMenu(); }
        if Equals(command, "cam") { return sys.Soak_Cam(); }
        if Equals(command, "pauses") { return sys.Soak_Pauses(); }
        if Equals(command, "uictx on") { return sys.Soak_UiCtx(true); }
        if Equals(command, "uictx off") { return sys.Soak_UiCtx(false); }
        if Equals(command, "yaw") { return sys.Soak_Yaw(); }
        if Equals(command, "psm") { return sys.Soak_Psm(); }
        if StrBeginsWith(command, "se_on ") {
            let sa = StrSplit(command, " ");
            return sys.Soak_Se(sa[1], true);
        }
        if StrBeginsWith(command, "se_off ") {
            let sb = StrSplit(command, " ");
            return sys.Soak_Se(sb[1], false);
        }
        if Equals(command, "vmark") { return sys.Soak_VMark(); }
        if Equals(command, "vdist") { return sys.Soak_VDist(); }
        if Equals(command, "cmark") { return sys.Soak_CMark(); }
        if Equals(command, "cdist") { return sys.Soak_CDist(); }
        if Equals(command, "hold_ctx on") { return sys.Soak_HoldCtx(true); }
        if Equals(command, "hold_ctx off") { return sys.Soak_HoldCtx(false); }
        // Bind StrSplit to a local: indexing a call temporary reads garbage in-game.
        if StrBeginsWith(command, "focus_photo ") {
            let f = StrSplit(command, " ");
            return sys.Soak_FocusPhoto(StringToFloat(f[1]));
        }
        // tp x y hop from to: send V to (x, y, hop), then watch rays from `from` down to `to` frame by frame.
        if StrBeginsWith(command, "tp ") {
            let a = StrSplit(command, " ");
            return sys.Soak_Tp(StringToFloat(a[1]), StringToFloat(a[2]), StringToFloat(a[3]), StringToFloat(a[4]), StringToFloat(a[5]));
        }
        if Equals(command, "tp_result") { return sys.Soak_TpResult(); }
        if Equals(command, "vpos") { return sys.Soak_VPos(); }
        if StrBeginsWith(command, "aim ") {
            let v = StrSplit(command, " ");
            return sys.Soak_Aim(StringToFloat(v[1]), StringToFloat(v[2]));
        }
        if StrBeginsWith(command, "zoom ") {
            let m = StrSplit(command, " ");
            return sys.Soak_SetZoom(StringToFloat(m[1]));
        }
        if Equals(command, "lootdump") { return NMSoak.LootDump(); }
        if Equals(command, "collect") { return sys.Soak_Collect(); }
        if Equals(command, "police") { return sys.Soak_Police(); }
        if Equals(command, "corner") { return sys.Soak_Corner(); }
        if Equals(command, "wp_version") { return NMSoakNative.Version(); }
        if Equals(command, "wp_rvas") { return NMSoakNative.Rvas(); }
        if StrBeginsWith(command, "wp_reg ") {
            let w = StrSplit(command, " ");
            if ArraySize(w) < 3 { return "usage: wp_reg <dx> <dy>"; }
            return NMSoakWp.Reg(StringToFloat(w[1]), StringToFloat(w[2]));
        }
        if Equals(command, "wp_state") { return NMSoakWp.State(); }
        if StrBeginsWith(command, "wp_track_nearest ") {
            let wt = StrSplit(command, " ");
            return NMSoakWp.TrackNearest(wt[1], StringToFloat(wt[2]));
        }
        if StrBeginsWith(command, "wp_set_near ") {
            let wn = StrSplit(command, " ");
            return NMSoakWp.SetNear(wn[1], StringToFloat(wn[2]));
        }
        if Equals(command, "wp_track_custom") {
            let ms3 = GameInstance.GetMappinSystem(GetGameInstance());
            let all3: array<ref<IMappin>>;
            ms3.GetMappins(gamemappinsMappinTargetType.Map, all3);
            for c3 in all3 {
                if Equals(c3.GetVariant(), gamedataMappinVariant.CustomPositionVariant) {
                    let cid = c3.GetNewMappinID();
                    return "track=" + NMSoakNative.Track(cid) + " id=" + ToString(cid.value);
                }
            }
            return "no custom pin";
        }
        if StrBeginsWith(command, "wp_unreg_custom") {
            let ms2 = GameInstance.GetMappinSystem(GetGameInstance());
            let all: array<ref<IMappin>>;
            ms2.GetMappins(gamemappinsMappinTargetType.Map, all);
            let n = 0;
            for c in all {
                if Equals(c.GetVariant(), gamedataMappinVariant.CustomPositionVariant) { ms2.UnregisterMappin(c.GetNewMappinID()); n += 1; }
            }
            return "unregistered " + n;
        }
        if StrBeginsWith(command, "fx_probe ") {
            let fp = StrSplit(command, " ");
            return sys.Soak_FxProbe(fp[1], ArraySize(fp) > 2 ? StringToFloat(fp[2]) : 1.0);
        }
        if Equals(command, "fx_state") { return sys.Soak_FxState(); }
        if Equals(command, "look_state") { return sys.Soak_LookState(); }
        if Equals(command, "ncart_dump") { return sys.Soak_NcartDump(); }
        if Equals(command, "gps") { return sys.Soak_GpsRoute(); }
        if StrBeginsWith(command, "focus_at ") {
            let fa = StrSplit(command, " ");
            return sys.Soak_FocusAt(StringToFloat(fa[1]), StringToFloat(fa[2]), StringToFloat(fa[3]));
        }
        if StrBeginsWith(command, "focus_empty ") {
            let fe = StrSplit(command, " ");
            return sys.Soak_FocusEmpty(StringToFloat(fe[1]), StringToFloat(fe[2]), StringToFloat(fe[3]));
        }
        if StrBeginsWith(command, "focus_custom ") {
            let fc = StrSplit(command, " ");
            let msf = GameInstance.GetMappinSystem(GetGameInstance());
            let allf: array<ref<IMappin>>;
            msf.GetMappins(gamemappinsMappinTargetType.Map, allf);
            for cf in allf {
                if Equals(cf.GetVariant(), gamedataMappinVariant.CustomPositionVariant) {
                    let wf = cf.GetWorldPosition();
                    return sys.Soak_FocusAt(wf.X, wf.Y, StringToFloat(fc[1]));
                }
            }
            return "no custom pin";
        }
        if Equals(command, "wp_count") {
            let msc = GameInstance.GetMappinSystem(GetGameInstance());
            let allc: array<ref<IMappin>>;
            msc.GetMappins(gamemappinsMappinTargetType.Map, allc);
            let nc = 0;
            let at = "";
            for cc in allc {
                if Equals(cc.GetVariant(), gamedataMappinVariant.CustomPositionVariant) {
                    nc += 1;
                    let wpos = cc.GetWorldPosition();
                    at += " " + FloatToStringPrec(wpos.X, 0) + "," + FloatToStringPrec(wpos.Y, 0);
                }
            }
            return "custom " + nc + at;
        }
        if Equals(command, "quest_hash") {
            let jmq = GameInstance.GetJournalManager(GetGameInstance());
            let te = jmq.GetTrackedEntry();
            return IsDefined(te) ? "quest " + ToString(jmq.GetEntryHash(te)) : "quest none";
        }
        if Equals(command, "wp_last") {
            let wl = sys.Waypoint();
            return "last=" + wl.lastAction + " pending=" + ToString(wl.Pending());
        }
        if Equals(command, "wp_why") { return NMSoakNative.Why(); }
        if StrBeginsWith(command, "wp_set ") {
            let ws = StrSplit(command, " ");
            if ArraySize(ws) < 3 { return "usage: wp_set <dx> <dy>"; }
            return NMSoakWp.Set(StringToFloat(ws[1]), StringToFloat(ws[2]));
        }
        if Equals(command, "wp_clear") { return NMVanillaTracking.ClearManual(GetGameInstance()) ? "cleared" : "nothing tracked"; }
        if Equals(command, "hud_find") { return sys.Soak_HudFind(); }
        if Equals(command, "mirror_dump") { return sys.Soak_MirrorDump(); }
        if Equals(command, "god") { return sys.Soak_God(); }
        if Equals(command, "corner_perf") { return StrLen(sys.lastCornerPerf) > 0 ? sys.lastCornerPerf : "none yet"; }
        if Equals(command, "saves_req") { return NMSoakSaves.Request(); }
        if Equals(command, "save_manual") { return NMSoakSaves.SaveNew(); }
        if Equals(command, "saves_new") { return NMSoakSaves.FindNew(); }
        if Equals(command, "load_new") { return NMSoakSaves.LoadNew(); }
        if Equals(command, "delete_new") { return NMSoakSaves.DeleteNew(); }
        if Equals(command, "saves_has_new") { return NMSoakSaves.HasNew(); }
        if StrBeginsWith(command, "collect_state ") {
            let st = StrSplit(command, " ");
            return sys.Soak_CollectState(st[1]);
        }
        if StrBeginsWith(command, "wanted ") {
            let wl = StrSplit(command, " ");
            return sys.Soak_Wanted(StringToInt(wl[1]));
        }
        if StrBeginsWith(command, "collect_focus ") {
            let cf = StrSplit(command, " ");
            return sys.Soak_CollectFocus(StringToInt(cf[1]));
        }
        if StrBeginsWith(command, "collect_seen ") {
            let cs = StrSplit(command, " ");
            return sys.Soak_CollectSeen(cs[1]);
        }
        if StrBeginsWith(command, "mm_tree") {
            let mt = StrSplit(command, " ");
            return sys.Soak_MmTree(ArraySize(mt) > 1 ? StringToInt(mt[1]) : 6);
        }
        if Equals(command, "mm_vis") { return sys.Soak_MmVis(); }
        if Equals(command, "mm_reset") { return sys.Soak_MmReset(); }
        if Equals(command, "mm_ctrls") { return sys.Soak_MmCtrls(); }
        if Equals(command, "mm_stealth") { return sys.Soak_MmStealth(); }
        if Equals(command, "mm_zone") { return sys.Soak_MmZone(); }
        if Equals(command, "palette_probe") { return sys.Soak_PaletteProbe(); }
        if Equals(command, "palette_read") { return sys.Soak_PaletteRead(); }
        if Equals(command, "mask_probe") { return sys.Soak_MaskProbe(); }
        if Equals(command, "selftest") {
            let t = new NMSelfTest();
            t.Run();
            return "ran|" + t.Summary();   // in the answer: CET's log can lose its tail when the harness closes the game
        }
        if StrBeginsWith(command, "sweep ") {
            let a = StrSplit(command, " ");
            return sys.Soak_StartSweep(a[1], StringToFloat(a[2]), StringToFloat(a[3]), ArraySize(a) > 4 ? StringToInt(a[4]) : 0);
        }
        if StrBeginsWith(command, "seed_photos ") {
            let n = StrSplit(command, " ");
            return sys.Soak_SeedPhotos(StringToInt(n[1]));
        }
        if StrBeginsWith(command, "churn ") {
            let c = StrSplit(command, " ");
            return sys.Soak_StartChurn(c[1], StringToFloat(c[2]), StringToFloat(c[3]));
        }
        if StrBeginsWith(command, "zoomloop ") {
            let z = StrSplit(command, " ");
            return sys.Soak_StartZoomLoop(z[1], StringToFloat(z[2]), ArraySize(z) > 3 ? StringToInt(z[3]) : 0);
        }
        return "unknown";
    }

    // Spike: every item and loot table, for joining offline with the world scan. Needs TweakXL's GetRecords.
    public static func LootDump() -> String {
        let out = NMSoakDump.Open("lootdump.txt");
        let items = 0;
        let kinds = [n"Item_Record", n"WeaponItem_Record", n"Gadget_Record", n"Clothing_Record", n"ConsumableItem_Record",
            n"ItemRecipe_Record", n"RecipeItem_Record"];
        for kind in kinds {
            for r in TweakDBInterface.GetRecords(kind) {
                let it = r as Item_Record;
                if IsDefined(it) {
                    let t = it.ItemType();
                    let q = it.Quality();
                    let tags = "";
                    for tag in it.Tags() { tags += NameToString(tag) + ","; }
                    let extra = "";
                    let rec = r as ItemRecipe_Record;
                    if IsDefined(rec) && IsDefined(rec.CraftingResult()) && IsDefined(rec.CraftingResult().Item()) {
                        extra = TDBID.ToStringDEBUG(rec.CraftingResult().Item().GetID());
                    }
                    let act = it.ItemSecondaryAction();
                    if IsDefined(act) {
                        let jp = TweakDBInterface.GetString(act.GetID() + t".journalEntry", "");
                        if StrLen(jp) > 0 { extra = "J:" + jp; }
                    }
                    let spec = r as RecipeItem_Record;
                    if IsDefined(spec) {
                        let cs: array<wref<Item_Record>>;
                        spec.CraftableItems(cs);
                        for c in cs { extra += TDBID.ToStringDEBUG(c.GetID()) + ","; }
                    }
                    out.Line("i|" + TDBID.ToStringDEBUG(r.GetID()) + "|" + NameToString(kind) + "|" + (IsDefined(t) ? ToString(t.Type()) : "-") + "|"
                        + (IsDefined(q) ? ToString(q.Type()) : "-") + "|" + tags + "|" + extra + "|" + GetLocalizedTextByKey(it.DisplayName()));
                    items += 1;
                }
            }
        }
        let tables = 0;
        for r in TweakDBInterface.GetRecords(n"LootTable_Record") {
            let lt = r as LootTable_Record;
            if IsDefined(lt) {
                let line = "t|" + TDBID.ToStringDEBUG(r.GetID()) + "|";
                let els: array<wref<LootItem_Record>>;
                lt.LootItems(els);
                for e in els {
                    let ir = e.ItemID();
                    if IsDefined(ir) { line += TDBID.ToStringDEBUG(ir.GetID()) + ","; }
                }
                line += "|";
                let incs: array<wref<LootTable_Record>>;
                lt.LootTableInclusions(incs);
                for c in incs { line += TDBID.ToStringDEBUG(c.GetID()) + ","; }
                out.Line(line);
                tables += 1;
            }
        }
        let jm = GameInstance.GetJournalManager(GetGameInstance());
        let ctx: JournalRequestContext;
        ctx.stateFilter.inactive = true;
        ctx.stateFilter.active = true;
        ctx.stateFilter.succeeded = true;
        ctx.stateFilter.failed = true;
        let groups: array<wref<JournalEntry>>;
        jm.GetTarots(ctx, groups);
        for g in groups {
            let cards: array<wref<JournalEntry>>;
            jm.GetChildren(g, ctx.stateFilter, cards);
            for c in cards {
                let tc = c as JournalTarot;
                out.Line("tarot|" + g.GetId() + "/" + c.GetId() + "|" + IntToString(IsDefined(tc) ? tc.GetIndex() : -1) + "|"
                    + (IsDefined(tc) ? GetLocalizedText(tc.GetName()) : "") + "|" + ToString(jm.GetEntryState(c)) + "|" + c.GetEditorName());
            }
        }
        out.Line("end|" + IntToString(items) + "|" + IntToString(tables));
        out.Flush();
        return "items " + IntToString(items) + " tables " + IntToString(tables);
    }

    // A state line for the supervisor; survives a killed game, unlike the game log.
    public static func Report(state: String, detail: String) {
        let channel = SoakChannel.Get();
        if IsDefined(channel) { channel.State(state, detail); }
    }
}

// One frame of the tp probe, re-armed from Soak_TpTick.
public class NMSoakTpFrame extends DelayCallback {
    public let system: wref<OverlayMapSystem>;
    public func Call() {
        if IsDefined(this.system) { this.system.Soak_TpTick(); }
    }
}

// Lines to a file in the channel storage, which the harness keeps with the run (the game log drops early lines).
public class NMSoakDump {
    private let file: ref<File>;
    private let buf: String;
    private let n: Int32;

    public static func Open(name: String) -> ref<NMSoakDump> {
        let d = new NMSoakDump();
        d.file = SoakChannel.Get().Storage().GetFile(name);
        d.file.WriteText("", FileSystemWriteMode.Truncate);
        return d;
    }

    public func Line(line: String) {
        this.buf += line + "\n";
        this.n += 1;
        if this.n >= 200 { this.Flush(); }
    }

    public func Flush() {
        this.file.WriteText(this.buf, FileSystemWriteMode.Append);
        this.buf = "";
        this.n = 0;
    }
}

// Save round trip for the collectible seen list: a new manual save (overwrites nothing), loaded, then deleted
// in-game before the game exits so Steam Cloud has nothing new to upload. Only a save whose name was not listed
// before the manual save is ever loaded or deleted. State lives in SoakChannel.note: it must survive the load.
public class NMSoakSaves extends IScriptable {
    public let saves: array<String>;
    public let ready: Bool;

    private static func Listener() -> ref<NMSoakSaves> {
        return OverlayMapSystem.Get(GetGameInstance()).Soak_SavesListener();
    }

    public cb func OnSaves(saves: array<String>) {
        this.saves = saves;
        this.ready = true;
    }

    public static func Request() -> String {
        let l = NMSoakSaves.Listener();
        l.ready = false;
        let handler = GameInstance.GetSystemRequestsHandler();
        handler.RegisterToCallback(n"OnSavesForLoadReady", l, n"OnSaves");
        handler.RequestSavesForLoad();
        return "requested";
    }

    private static func Joined(a: array<String>) -> String {
        let out = "|";
        for s in a { out += s + "|"; }
        return out;
    }

    public static func SaveNew() -> String {
        let l = NMSoakSaves.Listener();
        if !l.ready { return "no list"; }
        let handler = GameInstance.GetSystemRequestsHandler();
        if !handler.HasFreeSaveSlot("ManualSave-") { return "no free slot"; }
        SoakChannel.Get().note = "before=" + NMSoakSaves.Joined(l.saves);
        handler.ManualSave("ManualSave-");
        return "saving|listed " + IntToString(ArraySize(l.saves));
    }

    public static func FindNew() -> String {
        let l = NMSoakSaves.Listener();
        let channel = SoakChannel.Get();
        if !l.ready || !StrBeginsWith(channel.note, "before=") { return "not ready"; }
        let before = StrMid(channel.note, 7);
        let found: array<String>;
        for s in l.saves {
            if !StrContains(before, "|" + s + "|") { ArrayPush(found, s); }
        }
        if ArraySize(found) != 1 || !StrBeginsWith(found[0], "ManualSave-") {
            return "new " + IntToString(ArraySize(found)) + " " + NMSoakSaves.Joined(found);
        }
        channel.note = "new=" + found[0];
        return "new " + found[0];
    }

    private static func NewName() -> String {
        let note = SoakChannel.Get().note;
        return StrBeginsWith(note, "new=") ? StrMid(note, 4) : "";
    }

    private static func IndexOfNew() -> Int32 {
        let name = NMSoakSaves.NewName();
        let l = NMSoakSaves.Listener();
        if StrLen(name) == 0 || !l.ready { return -1; }
        return ArrayFindFirst(l.saves, name);
    }

    public static func LoadNew() -> String {
        let i = NMSoakSaves.IndexOfNew();
        if i < 0 { return "no new save"; }
        SoakChannel.Get().ExpectReload();
        GameInstance.GetSystemRequestsHandler().LoadSavedGame(i);
        return "loading " + NMSoakSaves.NewName();
    }

    public static func DeleteNew() -> String {
        let i = NMSoakSaves.IndexOfNew();
        if i < 0 { return "no new save"; }
        let name = NMSoakSaves.NewName();
        GameInstance.GetSystemRequestsHandler().DeleteSavedGame(i);
        return "deleted " + name;
    }

    public static func HasNew() -> String {
        let l = NMSoakSaves.Listener();
        if !l.ready { return "no list"; }
        return ArrayContains(l.saves, NMSoakSaves.NewName()) ? "present" : "absent";
    }
}

// A look check for the sidebar card's three-line description cap: one Always-tier marker next to V whose details carry a
// long description (no loaded vanilla marker has one), centred under the reticle.
public class NMSoakDesc extends OverlayMapLayerListener {
    public func GetDetails(id: Int32) -> ref<OverlayMapDetails> {
        let desc = "Wakako wants a shipment intercepted before it reaches the checkpoint. The convoy leaves Japantown at dusk; "
            + "stop it before the bridge, keep the cargo intact and bring the driver back alive for questioning.";
        return OverlayMapDetails.Create("Gig", "Shoot to Thrill").WithDescription(desc).AddRow("Distance", "640 M")
            .AddAction("NUM 0", "Track").AddAction("NUM .", "Fast travel");
    }

    public static func Add(sys: ref<OverlayMapSystem>) -> String {
        if !IsDefined(sys.Camera()) { return "map closed"; }
        let p = GetPlayer(GetGameInstance()).GetWorldPosition();
        let L = sys.Api().CreateLayer(n"Soak.Desc", "Soak", 99);
        L.SetTier(OverlayMapTier.Always);
        L.SetCategory(n"soak.desc", "GIG", NMTheme.Cyan());
        L.Add(OverlayMapItem.Create(new Vector4(p.X + 40.0, p.Y + 40.0, p.Z, 1.0), n"soak.desc", NMTheme.UiAtlas(), n"icon_dot"));
        L.SetListener(new NMSoakDesc());
        let cam = sys.Camera();
        cam.follow = false;
        cam.SetMpp(1.0);
        cam.SetCenter(p.X + 40.0, p.Y + 40.0);
        return "ok";
    }
}

// OverlayMapNative (optional plugin): answers "no plugin" when the plugin's module isn't loaded.
@if(ModuleExists("OverlayMapNative"))
public abstract class NMSoakNative {
    public static func Version() -> String { return IntToString(OverlayMapNative_Version()); }
    public static func Rvas() -> String { return OverlayMapNative_Rvas(); }
    public static func Why() -> String { return "available=" + ToString(OverlayMapNative_Available()) + " " + OverlayMapNative_Why(); }
    public static func Track(id: NewMappinID) -> String {
        let ms = GameInstance.GetMappinSystem(GetGameInstance());
        return ToString(OverlayMapNative_TrackMappin(ms, id));
    }
}

@if(!ModuleExists("OverlayMapNative"))
public abstract class NMSoakNative {
    public static func Version() -> String { return "no plugin"; }
    public static func Rvas() -> String { return "no plugin"; }
    public static func Why() -> String { return "no plugin"; }
    public static func Track(id: NewMappinID) -> String { return "no plugin"; }
}

// Waypoint probes: a vanilla custom waypoint registered from script (MappinSystem.RegisterMappin with the record and
// variant the world map's own TrackCustomPositionMappin uses), and the manually tracked pin's state.
public abstract class NMSoakWp {
    public static func Reg(dx: Float, dy: Float) -> String {
        let gi = GetGameInstance();
        let player = GetPlayer(gi);
        if !IsDefined(player) { return "no player"; }
        let p = player.GetWorldPosition();
        let pos = new Vector4(p.X + dx, p.Y + dy, p.Z, 1.0);
        let data: MappinData;
        data.mappinType = t"Mappins.CustomPositionMappinDefinition";
        data.variant = gamedataMappinVariant.CustomPositionVariant;
        data.active = true;
        data.visibleThroughWalls = true;
        let ms = GameInstance.GetMappinSystem(gi);
        let id = ms.RegisterMappin(data, pos);
        let tracked = ms.GetManuallyTrackedMappinID();
        return "id=" + ToString(id.value) + " tracked=" + ToString(tracked.value);
    }

    // Vanilla's TrackCustomPositionMappin: move the tracked custom pin if there is one, else register and track.
    public static func Set(dx: Float, dy: Float) -> String {
        let player = GetPlayer(GetGameInstance());
        if !IsDefined(player) { return "no player"; }
        let p = player.GetWorldPosition();
        return NMSoakWp.SetAt(new Vector4(p.X + dx, p.Y + dy, p.Z, 1.0));
    }

    // Through OverlayMap's own waypoint code (register, then track once the mappin system has the pin).
    public static func SetAt(pos: Vector4) -> String {
        let sys = OverlayMapSystem.Get(GetGameInstance());
        let w = sys.Waypoint();
        let ok = w.SetCustom(pos.X, pos.Y, pos.Z);
        return "set=" + ToString(ok) + " " + w.lastAction;
    }

    // The nearest map mappin at least `minDist` m away whose variant name contains `part` (e.g. FastTravel).
    public static func Nearest(part: String, minDist: Float) -> ref<IMappin> {
        let ms = GameInstance.GetMappinSystem(GetGameInstance());
        let arr: array<ref<IMappin>>;
        ms.GetMappins(gamemappinsMappinTargetType.Map, arr);
        let best: ref<IMappin>;
        let bestD = 1000000000.0;
        for m in arr {
            let name = EnumValueToString("gamedataMappinVariant", Cast<Int64>(EnumInt(m.GetVariant())));
            let d = m.GetDistanceToPlayer();
            if StrContains(name, part) && d >= minDist && d < bestD { best = m; bestD = d; }
        }
        return best;
    }

    public static func TrackNearest(part: String, minDist: Float) -> String {
        let m = NMSoakWp.Nearest(part, minDist);
        if !IsDefined(m) { return "none"; }
        let id = m.GetNewMappinID();
        return "track=" + NMSoakNative.Track(id) + " id=" + ToString(id.value) + " dist=" + FloatToStringPrec(m.GetDistanceToPlayer(), 0);
    }

    // A custom waypoint 3 m beside the nearest matching mappin (a routable spot).
    public static func SetNear(part: String, minDist: Float) -> String {
        let m = NMSoakWp.Nearest(part, minDist);
        if !IsDefined(m) { return "none"; }
        let w = m.GetWorldPosition();
        return NMSoakWp.SetAt(new Vector4(w.X, w.Y, w.Z, 1.0)) + " near=" + FloatToStringPrec(m.GetDistanceToPlayer(), 0);
    }

    public static func State() -> String {
        let gi = GetGameInstance();
        let ms = GameInstance.GetMappinSystem(gi);
        let id = ms.GetManuallyTrackedMappinID();
        if id.value == 0ul { return "tracked=0"; }
        let m = ms.GetMappin(id);
        if !IsDefined(m) { return "tracked=" + ToString(id.value) + " (no mappin)"; }
        let w = m.GetWorldPosition();
        return "tracked=" + ToString(id.value) + " variant=" + EnumValueToString("gamedataMappinVariant", Cast<Int64>(EnumInt(m.GetVariant())))
            + " playerTracked=" + ToString(m.IsPlayerTracked()) + " pos=" + FloatToStringPrec(w.X, 1) + "," + FloatToStringPrec(w.Y, 1)
            + " dist=" + FloatToStringPrec(m.GetDistanceToPlayer(), 1);
    }
}
