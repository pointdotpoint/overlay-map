module NightMap

// Per-layer listener: maps item ids back to mirrored mappins (book) and forwards card/activation to NMVanilla.
public class NMVanillaListener extends NightMapLayerListener {
    public let owner: wref<NMVanilla>;
    public let slot: Int32;
    public let book: array<ref<NMVanillaEntry>>;

    public func Set(item: Int32, e: ref<NMVanillaEntry>) {
        while ArraySize(this.book) <= item {
            ArrayPush(this.book, null);
        }
        this.book[item] = e;
    }

    public func Get(item: Int32) -> ref<NMVanillaEntry> {
        return item >= 0 && item < ArraySize(this.book) ? this.book[item] : null;
    }

    public func GetDetails(id: Int32) -> ref<NightMapDetails> {
        return IsDefined(this.owner) ? this.owner.Details(this.Get(id)) : null;
    }

    public func OnActivated(id: Int32) {
        if IsDefined(this.owner) { this.owner.Activate(this.Get(id)); }
    }
}

// Mirrors the vanilla world-map markers into NightMap layers: one per vanilla filter (+ Other) and Vanilla.Pinned.
// Polls only when asked (the system calls Tick while the map is open), so it costs nothing while closed.
public class NMVanilla extends NMVanillaSink {
    public let catalog: ref<NMVanillaCatalog>;
    public let pinned: ref<NightMapLayer>;
    public let diff: ref<NMVanillaDiff>;
    private let api: wref<NightMap>;
    private let gi: GameInstance;
    private let layers: array<ref<NightMapLayer>>;          // index = filter slot (0..Count(), Count() = Other)
    private let listeners: array<ref<NMVanillaListener>>;   // same index; pinned listener separate
    private let pinnedListener: ref<NMVanillaListener>;
    private let lastPollMs: Float;
    private let polledOnce: Bool;
    public let pollMsLast: Float;   // duration of the last poll (GetMappins + diff + layer updates), ms
    public let pollMsMax: Float;    // max since ResetPollStats
    private let loggedVariants: array<Int32>;
    public let lastAction: String;
    public let enabled: Bool = true;
    private let filterView: Int32;
    private let filterSettings: ref<NightMapSettings>;

    public static func PollMs() -> Float { return 1500.0; }

    public static func Create(api: ref<NightMap>, gi: GameInstance) -> ref<NMVanilla> {
        let v = new NMVanilla();
        v.api = api;
        v.gi = gi;
        v.diff = NMVanillaDiff.Create();
        return v;
    }

    // Builds the catalogue and layers on first use (TweakDB is certainly ready by the first map open).
    private func EnsureLayers() {
        if IsDefined(this.catalog) { return; }
        this.catalog = NMVanillaCatalog.Build();
        let n = this.catalog.Count();
        let i = 0;
        while i <= n {
            let L = this.api.CreateLayer(this.catalog.LayerId(i), this.catalog.DisplayName(i), this.catalog.Priority(i));
            L.SetPinStyle(NightMapPinStyle.Icon);
            let cat = this.catalog.CategoryName(i);
            let isOther = this.catalog.IsOther(i);
            let first = isOther ? gamedataMappinVariant.Invalid : this.catalog.firstVariant[i];
            let color = isOther ? NMTheme.Muted() : NMVanillaStyle.Color(first, gamedataMappinPhase.DefaultPhase);
            L.SetCategory(cat, this.catalog.DisplayName(i), color);
            this.api.SetCategoryIcon(cat, NMTheme.MappinAtlas(), isOther ? n"quest" : NMVanillaStyle.PartOf(first));
            let li = new NMVanillaListener();
            li.owner = this;
            li.slot = i;
            L.SetListener(li);
            ArrayPush(this.layers, L);
            ArrayPush(this.listeners, li);
            i += 1;
        }
        this.pinned = this.api.CreateLayer(n"Vanilla.Pinned", "Tracked", 100);
        this.pinned.SetPinStyle(NightMapPinStyle.Icon);
        this.pinned.SetClustering(false);
        this.pinned.SetCategory(n"vanilla.pinned", "TRACKED", NMTheme.VanillaStateColor(n"Quest"));
        this.api.SetCategoryIcon(n"vanilla.pinned", NMTheme.MappinAtlas(), n"quest");
        this.pinnedListener = new NMVanillaListener();
        this.pinnedListener.owner = this;
        this.pinnedListener.slot = -2;
        this.pinned.SetListener(this.pinnedListener);
    }

    public func LayerForSlot(slot: Int32) -> ref<NightMapLayer> {
        if slot == -2 { return this.pinned; }
        return slot >= 0 && slot < ArraySize(this.layers) ? this.layers[slot] : null;
    }

    private func ListenerForSlot(slot: Int32) -> ref<NMVanillaListener> {
        if slot == -2 { return this.pinnedListener; }
        return slot >= 0 && slot < ArraySize(this.listeners) ? this.listeners[slot] : null;
    }

    public func EntryFor(slot: Int32, item: Int32) -> ref<NMVanillaEntry> {
        let li = this.ListenerForSlot(slot);
        return IsDefined(li) ? li.Get(item) : null;
    }

    // Shows/hides each filter layer; Vanilla.Pinned (tracked quest marker, waypoint) is always visible while enabled.
    // SetVisible bumps the API revision, so only call it on an actual change.
    public func ApplyFilters(view: Int32, s: ref<NightMapSettings>) {
        this.EnsureLayers();
        let i = 0;
        while i < ArraySize(this.layers) {
            let want = this.enabled && NMVanillaFilters.Visible(view, s, this.catalog.TypeOf(i), this.catalog.IsOther(i));
            if NotEquals(this.layers[i].visible, want) {
                this.layers[i].SetVisible(want);
            }
            i += 1;
        }
        if NotEquals(this.pinned.visible, this.enabled) {
            this.pinned.SetVisible(this.enabled);
        }
        this.filterView = view;
        this.filterSettings = s;
    }

    // Perf suite: off hides every vanilla layer and stops polling; on restores the last filters and re-polls.
    public func SetEnabled(on: Bool) {
        this.enabled = on;
        this.ApplyFilters(this.filterView, this.filterSettings);
        if on { this.Tick(NMClock.NowMs(), true); }
    }

    // Flag only: no filter pass, no poll. For the close path; the next OnOpened re-applies filters and force-polls.
    public func MarkEnabled() {
        this.enabled = true;
    }

    public func ResetPollStats() {
        this.pollMsLast = 0.0;
        this.pollMsMax = 0.0;
    }

    // Polls when forced or when PollMs has passed since the last poll. Returns true if it polled.
    public func Tick(nowMs: Float, force: Bool) -> Bool {
        if !this.enabled { return false; }
        if !force && this.polledOnce && nowMs - this.lastPollMs < NMVanilla.PollMs() {
            return false;
        }
        this.lastPollMs = nowMs;
        this.polledOnce = true;
        let t0 = NMClock.NowMs();
        let arr: array<ref<IMappin>>;
        let ms = GameInstance.GetMappinSystem(this.gi);
        ms.GetMappins(gamemappinsMappinTargetType.Map, arr);
        let manual = ms.GetManuallyTrackedMappinID();
        this.PollFrom(arr, manual.value);
        this.pollMsLast = NMClock.NowMs() - t0;
        if this.pollMsLast > this.pollMsMax { this.pollMsMax = this.pollMsLast; }
        return true;
    }

    public func PollFrom(arr: array<ref<IMappin>>, manualKey: Uint64) {
        this.EnsureLayers();
        let cat = this.catalog;
        this.diff.Begin();
        for m in arr {
            if IsDefined(m) {
                // A marker that is neither visible nor tracked is never shown: skip the rest of its reads.
                let visible = m.IsVisible();
                let id = m.GetNewMappinID();
                let tracked = m.IsPlayerTracked() || (manualKey != 0ul && id.value == manualKey);
                if visible || tracked {
                    let pos = m.GetWorldPosition();
                    let v = m.GetVariant();
                    let filter = cat.FilterIndexOf(v);
                    if visible && cat.IsOther(filter) {
                        this.LogOnce(v);
                    }
                    this.diff.Observe(id.value, pos.X, pos.Y, pos.Z, v, m.GetPhase(), visible, tracked, filter, this, NMVanilla.IsPolice(m));
                }
            }
        }
        this.diff.End(this);
        if this.diff.added + this.diff.removed > 0 {
            let drawn = this.diff.DrawnCount();   // only when logging: the steady state pays nothing
            NMLog.Info("vanilla|poll|n=" + ToString(ArraySize(arr)) + "|live=" + ToString(drawn) + "|rejected=" + ToString(this.diff.live - drawn) + "|added=" + ToString(this.diff.added)
                + "|changed=" + ToString(this.diff.changed) + "|removed=" + ToString(this.diff.removed));
        }
    }

    // Logs a variant the catalogue does not know, once per variant. Returns true when it logged.
    private func LogOnce(v: gamedataMappinVariant) -> Bool {
        let key = EnumInt(v);
        if ArrayContains(this.loggedVariants, key) {
            return false;
        }
        ArrayPush(this.loggedVariants, key);
        NMLog.Info("vanilla|unknown-variant|" + ToString(v) + "|shown in Other");
        return true;
    }

    public func LogOnceForTest(v: gamedataMappinVariant) -> Bool {
        return this.LogOnce(v);
    }

    // Police the minimap draws as light blue dots: chasing cars and MaxTac AVs (Zzz04_PreventionVehicleVariant,
    // MinimapPreventionVehicleMappinController) and police stub mappins (MinimapStubMappinController).
    public static func IsPolice(m: ref<IMappin>) -> Bool {
        if !IsDefined(m) { return false; }
        if Equals(m.GetVariant(), gamedataMappinVariant.Zzz04_PreventionVehicleVariant) { return true; }
        let stub = m as StubMappin;
        if !IsDefined(stub) { return false; }
        let t = stub.GetStubMappinType();
        return Equals(t, gameStubMappinType.Police) || Equals(t, gameStubMappinType.PoliceVehicle);
    }

    private func ItemFor(s: ref<NMVanillaSnap>, slot: Int32) -> ref<NightMapItem> {
        let catName = slot == -2 ? n"vanilla.pinned" : this.catalog.CategoryName(slot);
        if s.police {
            return NightMapItem.Create(new Vector4(s.x, s.y, s.z, 1.0), catName, NMTheme.MinimapAtlas(), n"enemyMappin-1")
                .WithTint(NMTheme.VanillaStateColor(n"Prevention_LightBlue"))
                .WithDot(true);
        }
        let completed = Equals(s.phase, gamedataMappinPhase.CompletedPhase);
        return NightMapItem.Create(new Vector4(s.x, s.y, s.z, 1.0), catName, NMTheme.MappinAtlas(), this.catalog.PartFor(s.variant))
            .WithTint(this.catalog.ColorFor(s.variant, s.phase))
            .WithEmphasis(s.tracked)
            .WithOpacity(completed ? NMVanillaStyle.CompletedOpacity() : 1.0);
    }

    // ---- NMVanillaSink ----
    public func OnAdd(e: ref<NMVanillaEntry>) {
        let L = this.LayerForSlot(e.slot);
        if !IsDefined(L) { return; }
        e.item = L.Add(this.ItemFor(e.snap, e.slot));
        if e.item >= 0 { this.ListenerForSlot(e.slot).Set(e.item, e); }
    }

    public func OnChange(e: ref<NMVanillaEntry>, s: ref<NMVanillaSnap>) {
        let newSlot = NMVanillaRules.Slot(s);
        if newSlot == e.slot && e.item >= 0 {
            this.LayerForSlot(e.slot).Update(e.item, this.ItemFor(s, newSlot));
            return;
        }
        this.OnRemove(e);
        let L = this.LayerForSlot(newSlot);
        if !IsDefined(L) { return; }
        e.item = L.Add(this.ItemFor(s, newSlot));
        if e.item >= 0 { this.ListenerForSlot(newSlot).Set(e.item, e); }
    }

    public func OnRemove(e: ref<NMVanillaEntry>) {
        let L = this.LayerForSlot(e.slot);
        if IsDefined(L) && e.item >= 0 {
            L.Remove(e.item);
            this.ListenerForSlot(e.slot).Set(e.item, null);
        }
        e.item = -1;
    }

    public func Resolve(e: ref<NMVanillaEntry>) -> ref<IMappin> {
        if !IsDefined(e) || e.key == 0ul { return null; }
        let id: NewMappinID;
        id.value = e.key;
        return GameInstance.GetMappinSystem(this.gi).GetMappin(id);
    }

    private func ActKey() -> String {
        let s = NightMapSettings.Get(this.gi);
        return IsDefined(s) ? NMInput.KeyName(s.keyAct) : "NUM 0";
    }

    public func Details(e: ref<NMVanillaEntry>) -> ref<NightMapDetails> {
        if !IsDefined(e) || !IsDefined(e.snap) { return null; }
        let s = e.snap;
        let m = this.Resolve(e);
        let filterSlot = s.filter >= 0 ? s.filter : this.catalog.Count();
        let d = NightMapDetails.Create(this.catalog.DisplayName(filterSlot), NMVanillaText.Title(m, s.variant))
            .WithColor(this.catalog.ColorFor(s.variant, s.phase));   // the marker's own colour, not the layer's
        if IsDefined(m) {
            let district = NMVanillaText.District(m);
            if StrLen(district) > 0 { d.WithSubtitle(district); }
            d.AddRow("Distance", NMMath.FormatMeters(m.GetDistanceToPlayer()));
        }
        if Equals(s.phase, gamedataMappinPhase.UndiscoveredPhase) { d.AddRow("Status", "Undiscovered"); }
        if Equals(s.phase, gamedataMappinPhase.CompletedPhase) { d.AddRow("Status", "Completed"); }
        let manual = e.key != 0ul && NMVanillaTracking.ManualKey(this.gi) == e.key;
        let info = NMVanillaTracking.QuestInfo(this.gi, m);
        if info.ok {
            if StrLen(info.title) > 0 { d.AddRow("Quest", info.title); }
            if StrLen(info.objective) > 0 { d.AddRow("Objective", info.objective); }
        }
        if NMVanillaTracking.CanTrackQuest(this.gi, m) {
            if NMVanillaTracking.IsQuestTracked(this.gi, m) {
                d.AddRow("Status", "Tracked");
            } else {
                d.AddAction(this.ActKey(), "Track quest");
            }
        } else if manual {
            d.AddRow("Status", "Tracked");
            d.AddAction(this.ActKey(), Equals(s.variant, gamedataMappinVariant.CustomPositionVariant) ? "Clear waypoint" : "Stop tracking");
        } else if IsDefined(NMFastTravel.PointOf(m)) {
            let st = NightMapSettings.Get(this.gi);
            if IsDefined(st) && st.teleportEnabled { d.AddAction(NMInput.KeyName(st.keyTeleport), "Fast travel"); }
        } else {
            d.AddRow("Waypoint", "Coming with the native plugin");
        }
        return d;
    }

    // NUM 0 on a vanilla marker: track its quest, or clear the manual waypoint/tracking. Re-polls immediately.
    public func Activate(e: ref<NMVanillaEntry>) {
        this.lastAction = "none";
        if !IsDefined(e) { return; }
        let m = this.Resolve(e);
        if NMVanillaTracking.CanTrackQuest(this.gi, m) && !NMVanillaTracking.IsQuestTracked(this.gi, m) {
            NMVanillaTracking.ClearCustomWaypoint(this.gi);   // vanilla TryTrackQuestOrSetWaypoint clears the waypoint first
            if NMVanillaTracking.TrackQuest(this.gi, m) { this.lastAction = "track"; }
        } else if e.key != 0ul && NMVanillaTracking.ManualKey(this.gi) == e.key {
            if NMVanillaTracking.ClearManual(this.gi) { this.lastAction = "clear"; }
        }
        if NotEquals(this.lastAction, "none") {
            NMLog.Info("vanilla|action|" + this.lastAction + "|" + ToString(e.snap.variant));
            this.Tick(NMClock.NowMs(), true);   // re-poll now; the current time keeps the 1.5 s cadence, no double poll
        }
    }
}
