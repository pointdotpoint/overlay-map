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
    private let loggedVariants: array<Int32>;

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

    // Polls when forced or when PollMs has passed since the last poll. Returns true if it polled.
    public func Tick(nowMs: Float, force: Bool) -> Bool {
        if !force && this.polledOnce && nowMs - this.lastPollMs < NMVanilla.PollMs() {
            return false;
        }
        this.lastPollMs = nowMs;
        this.polledOnce = true;
        let arr: array<ref<IMappin>>;
        let ms = GameInstance.GetMappinSystem(this.gi);
        ms.GetMappins(gamemappinsMappinTargetType.Map, arr);
        let manual = ms.GetManuallyTrackedMappinID();
        this.PollFrom(arr, manual.value);
        return true;
    }

    public func PollFrom(arr: array<ref<IMappin>>, manualKey: Uint64) {
        this.EnsureLayers();
        let snaps: array<ref<NMVanillaSnap>>;
        for m in arr {
            if IsDefined(m) {
                let id = m.GetNewMappinID();
                let pos = m.GetWorldPosition();
                let v = m.GetVariant();
                let filter = this.catalog.FilterIndexOf(v);
                if this.catalog.IsOther(filter) && m.IsVisible() {
                    this.LogOnce(v);
                }
                let tracked = m.IsPlayerTracked() || (manualKey != 0ul && id.value == manualKey);
                let s = NMVanillaSnap.Make(id.value, pos.X, pos.Y, v, m.GetPhase(), m.IsVisible(), tracked, filter);
                s.z = pos.Z;
                ArrayPush(snaps, s);
            }
        }
        this.diff.Apply(snaps, this);
        if this.diff.added + this.diff.removed > 0 {
            NMLog.Info("vanilla|poll|n=" + ToString(ArraySize(arr)) + "|live=" + ToString(this.diff.live) + "|added=" + ToString(this.diff.added)
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

    private func ItemFor(s: ref<NMVanillaSnap>, slot: Int32) -> ref<NightMapItem> {
        let catName = slot == -2 ? n"vanilla.pinned" : this.catalog.CategoryName(slot);
        let completed = Equals(s.phase, gamedataMappinPhase.CompletedPhase);
        return NightMapItem.Create(new Vector4(s.x, s.y, s.z, 1.0), catName, NMTheme.MappinAtlas(), NMVanillaStyle.PartOf(s.variant))
            .WithTint(NMVanillaStyle.Color(s.variant, s.phase))
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

    // Card and activation: implemented in Task 6.
    public func Details(e: ref<NMVanillaEntry>) -> ref<NightMapDetails> { return null; }
    public func Activate(e: ref<NMVanillaEntry>) {}
}
