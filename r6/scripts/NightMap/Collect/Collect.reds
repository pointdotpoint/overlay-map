module NightMap

// One collectible spot from NMCollectData. ref: a TweakDB item name, or tarot journal ids joined with '+'.
public class NMCollectSpot {
    public let cat: Int32;
    public let pos: Vector4;
    public let ref: String;
    public let item: TweakDBID;
    public let journal: wref<JournalEntry>;   // a shard's journal entry, once resolved
    public let collected: Bool;
}

// Category tables (spec 2026-10-31-nightmap-collectibles-design.md). Index = position in Codes().
public abstract class NMCollectCats {
    public static func Codes() -> String { return "STWCLK"; }
    public static func Count() -> Int32 { return 6; }
    public static func Shard() -> Int32 { return 0; }
    public static func Tarot() -> Int32 { return 1; }

    public static func Of(code: String) -> Int32 { return StrFindFirst(NMCollectCats.Codes(), code); }

    public static func Name(c: Int32) -> String {
        switch c {
            case 0: return "SHARD";
            case 1: return "TAROT";
            case 2: return "ICONIC WEAPON";
            case 3: return "CYBERWARE";
            case 4: return "CLOTHING";
            case 5: return "SKILL SHARD";
        }
        return "COLLECTIBLE";
    }

    public static func LayerId(c: Int32) -> CName {
        switch c {
            case 0: return n"Collect.Shard";
            case 1: return n"Collect.Tarot";
            case 2: return n"Collect.Weapon";
            case 3: return n"Collect.Cyberware";
            case 4: return n"Collect.Clothing";
            case 5: return n"Collect.Skill";
        }
        return n"Collect.Other";
    }

    public static func Category(c: Int32) -> CName {
        switch c {
            case 0: return n"collect.shard";
            case 1: return n"collect.tarot";
            case 2: return n"collect.weapon";
            case 3: return n"collect.cyberware";
            case 4: return n"collect.clothing";
            case 5: return n"collect.skill";
        }
        return n"other";
    }

    // The category glyph (icon_c_*). The map draws every category as a hex chip with a centre dot instead.
    public static func Part(c: Int32) -> CName {
        switch c {
            case 0: return n"icon_c_shard";
            case 1: return n"icon_c_tarot";
            case 2: return n"icon_c_weapon";
            case 3: return n"icon_c_cyber";
            case 4: return n"icon_c_cloth";
            case 5: return n"icon_c_skill";
        }
        return n"icon_dot";
    }

    public static func Color(c: Int32) -> HDRColor {
        switch c {
            case 0: return new HDRColor(0.62, 0.86, 1.0, 1.0);    // #9EDBFF
            case 1: return new HDRColor(0.75, 0.55, 1.0, 1.0);    // #BF8CFF
            case 2: return new HDRColor(1.0, 0.72, 0.25, 1.0);    // #FFB840
            case 3: return new HDRColor(1.0, 0.36, 0.42, 1.0);    // #FF5C6B
            case 4: return new HDRColor(0.5, 1.0, 0.6, 1.0);      // #80FF99
            case 5: return new HDRColor(1.0, 0.5, 0.85, 1.0);     // #FF80D9
        }
        return NMTheme.Muted();
    }

    public static func Enabled(s: ref<NightMapSettings>, c: Int32) -> Bool {
        if !IsDefined(s) { return true; }
        switch c {
            case 0: return s.collectShards;
            case 1: return s.collectTarot;
            case 2: return s.collectWeapons;
            case 3: return s.collectCyberware;
            case 4: return s.collectClothing;
            case 5: return s.collectSkill;
        }
        return true;
    }
}

// Maps a collectible layer's item ids back to spots.
public class NMCollectListener extends NightMapLayerListener {
    public let owner: wref<NMCollect>;
    public let spot: array<Int32>;   // layer item id -> index into NMCollect.spots (-1 free)

    public func Set(item: Int32, idx: Int32) {
        while ArraySize(this.spot) <= item { ArrayPush(this.spot, -1); }
        this.spot[item] = idx;
    }

    public func Get(item: Int32) -> Int32 {
        return item >= 0 && item < ArraySize(this.spot) ? this.spot[item] : -1;
    }

    public func GetDetails(id: Int32) -> ref<NightMapDetails> {
        return IsDefined(this.owner) ? this.owner.Details(this.Get(id)) : null;
    }
}

// Collectible pins: one layer per category, built on the first map open of a session. Each open re-checks what V has
// collected (journal for shards and tarot, the per-save seen list for items) and rebuilds the layers only if that or
// the settings changed.
public class NMCollect extends IScriptable {
    public let spots: array<ref<NMCollectSpot>>;
    private let journalReady: Bool;
    private let tarot: ref<inkHashMap>;               // tarot journal id hash -> its JournalEntry (NMCollectEntry)
    private let tracked: ref<inkHashMap>;             // item record hash -> anything: items whose pickup counts
    private let listeners: array<ref<NMCollectListener>>;
    private let built: Bool;
    private let shownSig: String;
    public let collectedN: Int32;

    public static func Parse(chunk: String) -> array<ref<NMCollectSpot>> {
        let out: array<ref<NMCollectSpot>>;
        if StrLen(chunk) == 0 { return out; }
        for e in StrSplit(chunk, ";") {
            let f = StrSplit(e, ",");
            if ArraySize(f) == 5 {
                let s = new NMCollectSpot();
                s.cat = NMCollectCats.Of(f[0]);
                s.pos = new Vector4(StringToFloat(f[1]), StringToFloat(f[2]), StringToFloat(f[3]), 1.0);
                s.ref = f[4];
                if s.cat != NMCollectCats.Tarot() { s.item = TDBID.Create(s.ref); }
                if s.cat >= 0 { ArrayPush(out, s); }
            }
        }
        return out;
    }

    public static func IsCollectLayer(id: CName) -> Bool {
        return StrBeginsWith(NameToString(id), "Collect.");
    }

    // Item records a pickup counts for (every kind but shards and tarot, whose journal says it).
    public func Tracks(id: TweakDBID) -> Bool {
        this.EnsureSpots();
        return this.tracked.KeyExist(TDBID.ToNumber(id));
    }

    public func EnsureSpots() {
        if ArraySize(this.spots) > 0 { return; }
        this.tracked = new inkHashMap();
        let k = 0;
        while k < NMCollectData.Chunks() {
            for s in NMCollect.Parse(NMCollectData.Chunk(k)) {
                ArrayPush(this.spots, s);
                if s.cat != NMCollectCats.Shard() && s.cat != NMCollectCats.Tarot() {
                    let h = TDBID.ToNumber(s.item);
                    if !this.tracked.KeyExist(h) { this.tracked.Insert(h, s); }
                }
            }
            k += 1;
        }
    }

    private func EnsureJournal(gi: GameInstance) {
        if this.journalReady { return; }
        this.journalReady = true;
        let jm = GameInstance.GetJournalManager(gi);
        for s in this.spots {
            if s.cat == NMCollectCats.Shard() && IsDefined(jm) {
                let rec = TweakDBInterface.GetItemRecord(s.item);
                let act = IsDefined(rec) ? rec.ItemSecondaryAction() : null;
                if IsDefined(act) {
                    let path = TweakDBInterface.GetString(act.GetID() + t".journalEntry", "");
                    if StrLen(path) > 0 { s.journal = jm.GetEntryByString(path, "gameJournalOnscreen"); }
                }
            }
        }
        this.tarot = new inkHashMap();
        if !IsDefined(jm) { return; }
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
                let h = TDBID.ToNumber(TDBID.Create(c.GetId()));
                if !this.tarot.KeyExist(h) {
                    let w = new NMCollectEntry();
                    w.entry = c;
                    this.tarot.Insert(h, w);
                }
            }
        }
    }

    private func TarotEntry(id: String) -> wref<JournalEntry> {
        let h = TDBID.ToNumber(TDBID.Create(id));
        if !IsDefined(this.tarot) || !this.tarot.KeyExist(h) { return null; }
        let w = this.tarot.Get(h) as NMCollectEntry;
        return IsDefined(w) ? w.entry : null;
    }

    // Re-reads collected state. seen: item records V has had (NightMapSystem's per-save list).
    public func Refresh(gi: GameInstance, seen: ref<inkHashMap>) {
        this.EnsureSpots();
        this.EnsureJournal(gi);
        let jm = GameInstance.GetJournalManager(gi);
        let n = 0;
        let i = 0;
        while i < ArraySize(this.spots) {
            let s = this.spots[i];
            let got = false;
            if s.cat == NMCollectCats.Shard() {
                got = IsDefined(jm) && IsDefined(s.journal) && NotEquals(jm.GetEntryState(s.journal), gameJournalEntryState.Inactive);
            } else if s.cat == NMCollectCats.Tarot() {
                for id in StrSplit(s.ref, "+") {
                    let e = this.TarotEntry(id);
                    if IsDefined(jm) && IsDefined(e) && NotEquals(jm.GetEntryState(e), gameJournalEntryState.Inactive) { got = true; }
                }
            } else {
                got = IsDefined(seen) && seen.KeyExist(TDBID.ToNumber(s.item));
            }
            s.collected = got;
            if got { n += 1; }
            i += 1;
        }
        this.collectedN = n;
    }

    private static func Signature(view: Int32, s: ref<NightMapSettings>, collectedN: Int32) -> String {
        let sig = ToString(view) + "|" + ToString(!IsDefined(s) || s.collectShowCollected) + "|" + ToString(collectedN);
        let c = 0;
        while c < NMCollectCats.Count() {
            sig += NMCollectCats.Enabled(s, c) ? "1" : "0";
            c += 1;
        }
        return sig;
    }

    public func SyncWouldRebuild(view: Int32, s: ref<NightMapSettings>) -> Bool {
        return !this.built || NotEquals(NMCollect.Signature(view, s, this.collectedN), this.shownSig) || this.Changed();
    }

    // Builds or rebuilds the layers when the collected state or the settings changed since the last sync.
    public func Sync(api: ref<NightMap>, view: Int32, s: ref<NightMapSettings>) {
        this.EnsureSpots();
        let showCollected = !IsDefined(s) || s.collectShowCollected;
        let sig = NMCollect.Signature(view, s, this.collectedN);
        let c = 0;
        if this.built && Equals(sig, this.shownSig) && !this.Changed() { return; }
        this.built = true;
        this.shownSig = sig;
        let layers: array<ref<NightMapLayer>>;
        c = 0;
        while c < NMCollectCats.Count() {
            let L = api.CreateLayer(NMCollectCats.LayerId(c), NMCollectCats.Name(c), 40);
            L.SetTier(NightMapTier.Minor);
            L.SetPinStyle(NightMapPinStyle.Hex);   // small hex chips with a centre dot (spec 2026-11-01 section 5.3)
            L.SetCategory(NMCollectCats.Category(c), NMCollectCats.Name(c), NMCollectCats.Color(c));
            api.SetCategoryIcon(NMCollectCats.Category(c), NMTheme.UiAtlas(), n"icon_dot");
            L.Clear();
            if ArraySize(this.listeners) <= c {
                let li = new NMCollectListener();
                li.owner = this;
                ArrayPush(this.listeners, li);
            }
            ArrayClear(this.listeners[c].spot);
            L.SetListener(this.listeners[c]);
            L.SetVisible(view == 0 && NMCollectCats.Enabled(s, c));
            ArrayPush(layers, L);
            c += 1;
        }
        let i = 0;
        while i < ArraySize(this.spots) {
            let sp = this.spots[i];
            if !sp.collected || showCollected {
                let id = layers[sp.cat].Add(NMCollect.ItemOf(sp));
                if id >= 0 { this.listeners[sp.cat].Set(id, i); }
            }
            i += 1;
        }
        this.MarkSynced();
    }

    public static func ItemOf(sp: ref<NMCollectSpot>) -> ref<NightMapItem> {
        return NightMapItem.Create(sp.pos, NMCollectCats.Category(sp.cat), NMTheme.UiAtlas(), n"icon_dot")
            .WithTint(NMCollectCats.Color(sp.cat))
            .WithStruck(sp.collected)
            .WithOpacity(sp.collected ? NMCollect.CollectedOpacity() : 1.0);
    }

    // Collected pins are half as strong as uncollected ones in the same state (spec).
    public static func CollectedOpacity() -> Float { return 0.5; }

    // Collected flags as drawn: a rebuild is due when any flag differs from the last build.
    private let drawnFlags: array<Bool>;

    private func Changed() -> Bool {
        if ArraySize(this.drawnFlags) != ArraySize(this.spots) { return true; }
        let i = 0;
        while i < ArraySize(this.spots) {
            if NotEquals(this.drawnFlags[i], this.spots[i].collected) { return true; }
            i += 1;
        }
        return false;
    }

    private func MarkSynced() {
        ArrayClear(this.drawnFlags);
        for s in this.spots { ArrayPush(this.drawnFlags, s.collected); }
    }

    public func Spot(idx: Int32) -> ref<NMCollectSpot> {
        return idx >= 0 && idx < ArraySize(this.spots) ? this.spots[idx] : null;
    }

    public func Title(sp: ref<NMCollectSpot>) -> String {
        if sp.cat == NMCollectCats.Tarot() {
            let ids = StrSplit(sp.ref, "+");   // bound to a local: indexing a call temporary reads garbage in-game
            let e = this.TarotEntry(ids[0]) as JournalTarot;
            if IsDefined(e) { return GetLocalizedText(e.GetName()); }
            return sp.ref;
        }
        let shard = sp.journal as JournalOnscreen;
        if IsDefined(shard) {
            let title = GetLocalizedText(shard.GetTitle());
            if StrLen(title) > 0 { return title; }
        }
        let rec = TweakDBInterface.GetItemRecord(sp.item);
        if IsDefined(rec) {
            let name = GetLocalizedTextByKey(rec.DisplayName());
            if StrLen(name) > 0 { return name; }
        }
        return sp.ref;
    }

    public func Details(idx: Int32) -> ref<NightMapDetails> {
        let sp = this.Spot(idx);
        if !IsDefined(sp) { return null; }
        let d = NightMapDetails.Create(NMCollectCats.Name(sp.cat), this.Title(sp)).WithColor(NMCollectCats.Color(sp.cat));
        d.AddRow("Status", sp.collected ? "Collected" : "Not collected");
        let player = GetPlayer(GetGameInstance());
        if IsDefined(player) {
            let p = player.GetWorldPosition();
            let dx = sp.pos.X - p.X;
            let dy = sp.pos.Y - p.Y;
            d.AddRow("Distance", NMMath.FormatMeters(SqrtF(dx * dx + dy * dy)));
        }
        return d;
    }
}

// inkHashMap holds IScriptable values: a journal entry in a box.
public class NMCollectEntry extends IScriptable {
    public let entry: wref<JournalEntry>;
}
