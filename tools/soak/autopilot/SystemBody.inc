
    // ---- soak harness (tools/soak/autopilot/SystemBody.inc, spliced in at build time) ----

    // Centres the map on the discovered fast travel point farthest from V, close enough in for the crosshair to
    // select it.
    public func Soak_FocusFastTravel() -> String {
        let gi = this.GetGameInstance();
        let player = GetPlayer(gi);
        if !IsDefined(player) || !IsDefined(this.camera) { return "map closed"; }
        let here = player.GetWorldPosition();
        let best: ref<IMappin>;
        let bestD = -1.0;
        let points = 0;
        for L in this.api.layers {
            let vl = L.listener as NMVanillaListener;
            if IsDefined(vl) {
                for e in vl.book {
                    let m = this.vanilla.Resolve(e);
                    if IsDefined(m as FastTravelMappin) && Equals(NMFastTravel.Check(gi, m, player), "") {
                        points += 1;
                        let d = Vector4.Distance(here, m.GetWorldPosition());
                        if d > bestD {
                            bestD = d;
                            best = m;
                        }
                    }
                }
            }
        }
        if !IsDefined(best) { return "none|points " + IntToString(points); }
        let p = best.GetWorldPosition();
        this.camera.follow = false;
        this.camera.SetMpp(0.5);
        this.camera.SetCenter(p.X, p.Y);
        return "ok|" + NMVanillaText.Title(best, best.GetVariant()) + "|" + FloatToStringPrec(bestD, 0) + "m|points "
            + IntToString(points);
    }

    public func Soak_Selected() -> String {
        if IsDefined(this.SelectedPhoto()) { return "photo"; }
        let c = this.crosshair;
        if IsDefined(c) && c.selKind == 0 && c.selLayer >= 0 && c.selLayer < ArraySize(this.api.layers)
            && NMCollect.IsCollectLayer(this.api.layers[c.selLayer].id) {
            let d = this.api.layers[c.selLayer].listener.GetDetails(c.selItem);
            return "collect|" + d.category + "|" + d.title + "|" + d.rowValues[0];
        }
        let m = this.SelectedMappin();
        if !IsDefined(m) { return "none"; }
        let title = NMVanillaText.Title(m, m.GetVariant());
        if IsDefined(m as FastTravelMappin) { return "ft|" + title; }
        return "other|" + title;
    }

    // ---- marker sweep: the map driven over the city at one zoom; any chip that leaves while still on screen is logged ----

    private let soakOn: Bool;
    private let soakTag: String;
    private let soakT: Float;
    private let soakEnd: Float;
    private let soakMpp: Float;
    private let soakOx: Float;
    private let soakOy: Float;
    private let soakPrevKeys: array<Int32>;
    private let soakPrevSlots: array<Int32>;
    private let soakRecent: array<Int32>;
    private let soakRecentFrame: array<Int32>;
    private let soakFrames: Int32;
    private let soakDrops: Int32;
    private let soakDropsBudget: Int32;
    private let soakDropsDead: Int32;
    private let soakDropsBare: Int32;
    private let soakBack: Int32;
    private let soakBackGap: Int32;
    private let soakMoved: Int32;
    private let soakLoads0: Int32;
    private let soakBudgetFrames: Int32;
    private let soakChipsMax: Int32;
    private let soakLogged: Int32;
    private let soakHidden: Int32;
    private let soakHiddenMax: Int32;
    private let soakHolds: Int32;
    private let soakHoldMax: Int32;
    private let soakHoldLeft: Float;
    private let soakLoadsSeen: Int32;

    // What the sidebar's area card shows: "marker" while a marker or photo is selected, else the area or "none".
    public func Soak_Area() -> String {
        let c = this.crosshair;
        if IsDefined(this.SelectedPhoto()) || (IsDefined(c) && c.selKind >= 0) { return "marker"; }
        if this.areaAt < 0 || !IsDefined(this.areas) { return "none"; }
        return "area|" + this.areas.Label(this.areaAt) + "|" + this.areas.Title(this.areaAt);
    }

    // Every area's resolved names, one AREA| line each, for reviewing the localized titles.
    public func Soak_AreaNames() -> String {
        if !IsDefined(this.areas) { this.areas = NMAreaIndex.Load(); }
        let i = 0;
        while i < this.areas.Count() {
            NMLog.Info("AREA|" + this.areas.Key(i) + "|" + this.areas.Label(i) + "|" + this.areas.Title(i));
            i += 1;
        }
        return "areas " + ToString(this.areas.Count());
    }

    public func Soak_StartSweep(tag: String, mpp: Float, seconds: Float, holds: Int32) -> String {
        if !IsDefined(this.camera) || !IsDefined(this.renderer) { return "map closed"; }
        let p = GetPlayer(this.GetGameInstance()).GetWorldPosition();
        this.soakOx = p.X;
        this.soakOy = p.Y;
        this.soakTag = tag;
        this.soakT = 0.0;
        this.soakEnd = seconds;
        this.soakMpp = mpp;
        this.soakFrames = 0;
        this.soakDrops = 0;
        this.soakDropsBudget = 0;
        this.soakDropsDead = 0;
        this.soakDropsBare = 0;
        this.soakBack = 0;
        this.soakBackGap = 0;
        this.soakMoved = 0;
        this.soakBudgetFrames = 0;
        this.soakChipsMax = 0;
        this.soakLogged = 0;
        this.soakLoads0 = this.renderer.soakIconLoads;
        this.soakLoadsSeen = this.soakLoads0;
        this.soakHidden = 0;
        this.soakHiddenMax = 0;
        this.soakHolds = 0;
        this.soakHoldMax = holds;
        this.soakHoldLeft = 0.0;
        ArrayClear(this.soakPrevKeys);
        ArrayClear(this.soakPrevSlots);
        ArrayClear(this.soakRecent);
        ArrayClear(this.soakRecentFrame);
        this.camera.follow = false;
        this.camera.SetMpp(mpp);
        this.soakOn = true;
        return "started";
    }

    private func Soak_Frame(dt: Float) {
        this.Soak_PerfFrame();
        if this.soakMode > 0 && IsDefined(this.renderer) {
            this.Soak_ModeFrame(dt);
            return;
        }
        if !this.soakOn || !IsDefined(this.renderer) { return; }
        this.Soak_Compare();
        this.soakFrames += 1;
        if this.soakHoldLeft > 0.0 {
            this.soakHoldLeft -= dt / 1000.0;
            return;
        }
        this.Soak_MaybeHold();
        this.soakT += dt / 1000.0;
        if this.soakT >= this.soakEnd {
            this.soakOn = false;
            NMSoak.Report("sweep_done_" + this.soakTag, "frames " + IntToString(this.soakFrames)
                + "|drops " + IntToString(this.soakDrops) + "|bare " + IntToString(this.soakDropsBare)
                + "|budget " + IntToString(this.soakDropsBudget)
                + "|dead " + IntToString(this.soakDropsDead) + "|back " + IntToString(this.soakBack)
                + "|backgap " + IntToString(this.soakBackGap) + "|moved " + IntToString(this.soakMoved)
                + "|iconloads " + IntToString(this.renderer.soakIconLoads - this.soakLoads0)
                + "|budgetframes " + IntToString(this.soakBudgetFrames)
                + "|chipsmax " + IntToString(this.soakChipsMax)
                + "|holds " + IntToString(this.soakHolds)
                + "|hidden " + IntToString(this.soakHidden) + "|hiddenmax " + IntToString(this.soakHiddenMax));
            return;
        }
        let m = this.soakMpp;
        this.camera.SetCenter(this.soakOx + 800.0 * m * SinF(this.soakT * 0.7), this.soakOy + 600.0 * m * SinF(this.soakT * 1.1));
    }

    // An icon just reloaded on screen: stop here so the supervisor can photograph that spot.
    private func Soak_MaybeHold() {
        let r = this.renderer;
        let loaded = r.soakIconLoads != this.soakLoadsSeen;
        this.soakLoadsSeen = r.soakIconLoads;
        if !loaded || this.soakHolds >= this.soakHoldMax { return; }
        let at = r.soakLoadAt;
        let m = 120.0;
        if at.X < m || at.Y < m || at.X > this.camera.viewW * 0.72 - m || at.Y > this.camera.viewH - m { return; }
        this.soakHolds += 1;
        this.soakHoldLeft = 1.5;
        NMSoak.Report("hold", IntToString(this.soakHolds) + "|" + FloatToStringPrec(at.X, 0) + "," + FloatToStringPrec(at.Y, 0)
            + "|view " + FloatToStringPrec(this.camera.viewW, 0) + "x" + FloatToStringPrec(this.camera.viewH, 0));
    }

    private func Soak_Compare() {
        let r = this.renderer;
        let cur: array<Int32>;
        let i = 0;
        while i < ArraySize(r.candLayer) {
            ArrayPush(cur, r.candLayer[i] * 100000 + r.candItem[i]);
            i += 1;
        }
        if r.chipsUsed > this.soakChipsMax { this.soakChipsMax = r.chipsUsed; }
        let hidden = r.Soak_Hidden();
        this.soakHidden += hidden;
        if hidden > this.soakHiddenMax { this.soakHiddenMax = hidden; }
        let full = r.chipsUsed >= NMTheme.ChipBudget();
        if full { this.soakBudgetFrames += 1; }
        let p = 0;
        while p < ArraySize(this.soakPrevKeys) {
            let key = this.soakPrevKeys[p];
            let at = ArrayFindFirst(cur, key);
            if at < 0 {
                this.Soak_Dropped(key, full);
            } else if r.candSlot[at] != this.soakPrevSlots[p] {
                this.soakMoved += 1;
            }
            p += 1;
        }
        if ArraySize(this.soakRecent) > 0 {
            for key in cur {
                let was = ArrayFindFirst(this.soakRecent, key);
                if was >= 0 {
                    this.soakBack += 1;
                    let gap = this.soakFrames - this.soakRecentFrame[was];
                    if gap > this.soakBackGap { this.soakBackGap = gap; }
                    ArrayErase(this.soakRecent, was);
                    ArrayErase(this.soakRecentFrame, was);
                }
            }
        }
        this.soakPrevKeys = cur;
        this.soakPrevSlots = r.candSlot;
    }

    private func Soak_Dropped(key: Int32, full: Bool) {
        let li = key / 100000;
        let item = key - li * 100000;
        if li < 0 || li >= ArraySize(this.api.layers) { return; }
        let L = this.api.layers[li];
        if !L.IsAlive(item) {
            this.soakDropsDead += 1;
            return;
        }
        let at = this.camera.WorldToMap(L.px[item], L.py[item]);
        let m = 100.0;
        if at.X < m || at.Y < m || at.X > this.camera.viewW - m || at.Y > this.camera.viewH - m { return; }
        this.soakDrops += 1;
        if full { this.soakDropsBudget += 1; }
        if !full { this.soakDropsBare += 1; }
        ArrayPush(this.soakRecent, key);
        ArrayPush(this.soakRecentFrame, this.soakFrames);
        if this.soakLogged < 25 {
            this.soakLogged += 1;
            NMSoak.Report("sweep_drop", this.soakTag + "|f" + IntToString(this.soakFrames) + "|L" + IntToString(li) + "#" + IntToString(item)
                + "|at " + FloatToStringPrec(at.X, 0) + "," + FloatToStringPrec(at.Y, 0) + "|chips " + IntToString(this.renderer.chipsUsed)
                + "|mpp " + FloatToStringPrec(this.camera.mpp, 2));
        }
    }

    // ---- icon churn on a still map; zoom loop over fresh tiles ----

    private let soakMode: Int32;   // 0 sweep, 1 churn, 2 zoom loop
    private let soakLayerOn: array<Bool>;
    private let soakCrossing: Bool;
    private let soakCrossMs: Float;
    private let soakFlip: Bool;
    private let soakResMax: Int32;
    private let soakLevels: Int32;
    private let soakLastLv: Int32;

    public func Soak_StartChurn(tag: String, mpp: Float, seconds: Float) -> String {
        if !IsDefined(this.camera) { return "map closed"; }
        let p = GetPlayer(this.GetGameInstance()).GetWorldPosition();
        this.camera.follow = false;
        this.camera.SetMpp(mpp);
        this.camera.SetCenter(p.X, p.Y);
        this.soakTag = tag;
        this.soakT = 0.0;
        this.soakEnd = seconds;
        this.soakMode = 1;
        return "started";
    }

    // Centres the map on the saved photo spot nearest V, at this zoom.
    public func Soak_FocusPhoto(mpp: Float) -> String {
        if !IsDefined(this.camera) { return "map closed"; }
        let here = GetPlayer(this.GetGameInstance()).GetWorldPosition();
        let best: ref<NMPhotoSpot>;
        let bestD = -1.0;
        for s in this.Photos().Spots() {
            let d = Vector4.Distance(here, s.Position());
            if bestD < 0.0 || d < bestD {
                bestD = d;
                best = s;
            }
        }
        if !IsDefined(best) { return "none"; }
        this.camera.follow = false;
        this.camera.SetMpp(mpp);
        this.camera.SetCenter(best.x, best.y);
        return "ok|" + FloatToStringPrec(bestD, 0) + "m";
    }

    // ---- save round trip ----

    private let soakSaves: ref<NMSoakSaves>;

    public func Soak_SavesListener() -> ref<NMSoakSaves> {
        if !IsDefined(this.soakSaves) { this.soakSaves = new NMSoakSaves(); }
        return this.soakSaves;
    }

    // Whether a collectible item counts as collected now, and whether V carries it (it must not, for the seen list
    // to be what is tested).
    public func Soak_CollectState(ref: String) -> String {
        let id = TDBID.Create(ref);
        this.Collect().Refresh(this.GetGameInstance(), this.CollectSeen());
        let collected = false;
        for s in this.Collect().spots {
            if s.item == id && s.collected { collected = true; }
        }
        let carried = false;
        let player = GetPlayer(this.GetGameInstance());
        let ts = GameInstance.GetTransactionSystem(this.GetGameInstance());
        let list: array<wref<gameItemData>>;
        ts.GetItemList(player, list);
        for d in list {
            if IsDefined(d) && ItemID.GetTDBID(d.GetID()) == id { carried = true; }
        }
        return "collected " + ToString(collected) + "|carried " + ToString(carried) + "|seen " + IntToString(ArraySize(this.collectSeen));
    }

    // ---- police ----

    // Raises (or with 0 clears) V's wanted level through the prevention system's console request.
    public func Soak_Wanted(level: Int32) -> String {
        let ps = GameInstance.GetScriptableSystemsContainer(this.GetGameInstance()).Get(n"PreventionSystem") as PreventionSystem;
        if !IsDefined(ps) { return "no prevention system"; }
        let req = new PreventionConsoleInstructionRequest();
        req.instruction = level > 0 ? EPreventionSystemInstruction.Active : EPreventionSystemInstruction.Safe;
        req.heatStage = IntEnum<EPreventionHeatStage>(level);
        ps.QueueRequest(req);
        return "wanted " + IntToString(level);
    }

    // Police markers mirrored on the map, and how many of them are drawn as dots.
    public func Soak_Police() -> String {
        let n = 0;
        let dots = 0;
        for L in this.api.layers {
            let vl = L.listener as NMVanillaListener;
            if IsDefined(vl) {
                for e in vl.book {
                    if IsDefined(e) && IsDefined(e.snap) && e.snap.police && e.item >= 0 {
                        n += 1;
                        if L.dot[e.item] { dots += 1; }
                    }
                }
            }
        }
        let raw: array<ref<IMappin>>;
        GameInstance.GetMappinSystem(this.GetGameInstance()).GetMappins(gamemappinsMappinTargetType.Map, raw);
        let inList = 0;
        for m in raw {
            if NMVanilla.IsPolice(m) { inList += 1; }
        }
        let ps = GameInstance.GetScriptableSystemsContainer(this.GetGameInstance()).Get(n"PreventionSystem") as PreventionSystem;
        return "police " + IntToString(n) + "|dots " + IntToString(dots) + "|in map list " + IntToString(inList)
            + "|heat " + (IsDefined(ps) ? ToString(ps.GetHeatStage()) : "-");
    }

    // ---- collectibles ----

    public func Soak_Collect() -> String {
        let c = this.Collect();
        let out = "spots " + IntToString(ArraySize(c.spots)) + "|collected " + IntToString(c.collectedN) + "|layers";
        let k = 0;
        while k < NMCollectCats.Count() {
            let L = this.api.GetLayer(NMCollectCats.LayerId(k));
            out += " " + (IsDefined(L) ? IntToString(L.count) + (L.visible ? "v" : "h") : "-");
            k += 1;
        }
        return out;
    }

    // Centres the map on the first spot of a category, close enough for the crosshair to select it.
    public func Soak_CollectFocus(cat: Int32) -> String {
        if !IsDefined(this.camera) { return "map closed"; }
        let c = this.Collect();
        for s in c.spots {
            if s.cat == cat {
                this.camera.follow = false;
                this.camera.SetMpp(0.5);
                this.camera.SetCenter(s.pos.X, s.pos.Y);
                return "ok|" + s.ref + "|" + c.Title(s);
            }
        }
        return "none";
    }

    // Marks an item record as seen, as a pickup would, and redraws.
    public func Soak_CollectSeen(ref: String) -> String {
        this.NoteItem(TDBID.Create(ref));
        this.Collect().Refresh(this.GetGameInstance(), this.CollectSeen());
        this.SyncCollect();
        return this.Soak_Collect();
    }

    public func Soak_SetZoom(mpp: Float) -> String {
        if !IsDefined(this.camera) { return "map closed"; }
        this.camera.follow = false;
        this.camera.SetMpp(mpp);
        return "mpp " + FloatToStringPrec(this.camera.mpp, 2);
    }

    // The tp probe: how long after a jump collision appears, per group, and what the ray then finds.
    private let tpX: Float;
    private let tpY: Float;
    private let tpFrom: Float;
    private let tpTo: Float;
    private let tpStart: Float;
    private let tpFrames: Int32;
    private let tpLog: String;
    private let tpLastStatic: Float;
    private let tpHp: Float;
    private let tpRunning: Bool;
    private let tpStable: Int32;
    private let tpLanded: Bool;
    private let tpLandFrame: Int32;

    private func Soak_Now() -> Float { return EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGameInstance())); }

    private func Soak_Hp() -> Float {
        let p = GetPlayer(this.GetGameInstance());
        return GameInstance.GetStatPoolsSystem(this.GetGameInstance()).GetStatPoolValue(Cast<StatsObjectID>(p.GetEntityID()), gamedataStatPoolType.Health, true);
    }

    public func Soak_Tp(x: Float, y: Float, hop: Float, from: Float, to: Float) -> String {
        let p = GetPlayer(this.GetGameInstance());
        this.tpX = x; this.tpY = y; this.tpFrom = from; this.tpTo = to;
        this.tpFrames = 0; this.tpLog = ""; this.tpStable = 0; this.tpLanded = false; this.tpLastStatic = -9999.0;
        this.tpHp = this.Soak_Hp();
        this.tpStart = this.Soak_Now();
        let rot = new EulerAngles();
        GameInstance.GetTeleportationFacility(this.GetGameInstance()).Teleport(p, new Vector4(x, y, hop, 1.0), rot);
        if !this.tpRunning {
            this.tpRunning = true;
            this.Soak_TpArm();
        }
        return "sent";
    }

    private func Soak_TpArm() {
        let cb = new NMSoakTpFrame();
        cb.system = this;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.0, false);
    }

    private func Soak_TpRay(group: CName, out z: Float) -> Bool {
        let t: TraceResult;
        let ok = GameInstance.GetSpatialQueriesSystem(this.GetGameInstance()).SyncRaycastByCollisionGroup(new Vector4(this.tpX, this.tpY, this.tpFrom, 1.0), new Vector4(this.tpX, this.tpY, this.tpTo, 1.0), group, t, false, false) && TraceResult.IsValid(t);
        if ok { z = t.position.Z; }
        return ok;
    }

    public func Soak_TpTick() {
        this.tpFrames += 1;
        let ms = (this.Soak_Now() - this.tpStart) * 1000.0;
        let at = "f" + IntToString(this.tpFrames) + "@" + FloatToStringPrec(ms, 0);
        let pos = GetPlayer(this.GetGameInstance()).GetWorldPosition();
        let vz = pos.Z;
        let best = -9999.0;
        let z: Float;
        if this.Soak_TpRay(n"Static", z) { best = z; }
        let st = best;
        if this.Soak_TpRay(n"Terrain", z) { best = MaxF(best, z); }
        if best > -9000.0 && AbsF(best - this.tpLastStatic) > 0.2 {
            this.tpLog += " " + at + "=" + FloatToStringPrec(best, 1) + (st > -9000.0 ? "s" : "t") + "/v" + FloatToStringPrec(vz, 1);
        }
        if best > -9000.0 && AbsF(best - this.tpLastStatic) <= 0.2 { this.tpStable += 1; } else { this.tpStable = 0; }
        this.tpLastStatic = best;
        if !this.tpLanded && this.tpStable >= 2 {
            this.tpLanded = true;
            this.tpLandFrame = this.tpFrames;
            let rot = new EulerAngles();
            let p: ref<GameObject> = GetPlayer(this.GetGameInstance());
            GameInstance.GetTeleportationFacility(this.GetGameInstance()).Teleport(p, new Vector4(this.tpX, this.tpY, best + 0.5, 1.0), rot);
            this.tpLog += " LAND@" + at + "=" + FloatToStringPrec(best + 0.5, 1);
        }
        if this.tpLanded && this.tpFrames == this.tpLandFrame + 90 {
            this.tpLog += " after=" + FloatToStringPrec(vz, 1);
        }
        if this.tpFrames < 420 { this.Soak_TpArm(); } else { this.tpRunning = false; }
    }

    // Point the open map at a spot, as panning there would.
    public func Soak_Aim(x: Float, y: Float) -> String {
        if !IsDefined(this.camera) { return "map closed"; }
        this.camera.follow = false;
        this.camera.SetCenter(x, y);
        return "aimed";
    }

    public func Soak_VPos() -> String {
        let pos = GetPlayer(this.GetGameInstance()).GetWorldPosition();
        let x = pos.X; let y = pos.Y; let z = pos.Z;
        return "v " + FloatToStringPrec(x, 1) + " " + FloatToStringPrec(y, 1) + " " + FloatToStringPrec(z, 1) + " hp " + FloatToStringPrec(this.Soak_Hp(), 0);
    }

    public func Soak_TpResult() -> String {
        let w: Float; let w2: Float;
        let water = AIScriptUtils.GetWaterLevel(this.GetGameInstance(), new Vector3(this.tpX, this.tpY, this.tpLastStatic), w);
        let water2 = AIScriptUtils.GetWaterLevel(this.GetGameInstance(), new Vector3(this.tpX, this.tpY, 0.0), w2);
        let pos = GetPlayer(this.GetGameInstance()).GetWorldPosition();
        let vz = pos.Z;
        return "frames " + IntToString(this.tpFrames) + " vz " + FloatToStringPrec(vz, 1) + " water " + (water ? FloatToStringPrec(w, 1) : "-") + "/" + (water2 ? FloatToStringPrec(w2, 1) : "-")
            + " hp " + FloatToStringPrec(this.tpHp, 0) + ">" + FloatToStringPrec(this.Soak_Hp(), 0) + " |" + this.tpLog;
    }

    public func Soak_IsOpen() -> String { return this.isOpen ? "open" : "closed"; }

    private let soakMarkV: Vector4;
    private let soakMarkCx: Float;
    private let soakMarkCy: Float;
    private let soakMarkMpp: Float;

    public func Soak_VMark() -> String {
        this.soakMarkV = GetPlayer(this.GetGameInstance()).GetWorldPosition();
        return "marked";
    }

    // Puts the focus point on a world spot (follow off): "focus x y".
    public func Soak_FocusAt(x: Float, y: Float, mpp: Float) -> String {
        if !IsDefined(this.camera) || !this.isOpen { return "map closed"; }
        this.camera.follow = false;
        this.camera.SetMpp(mpp);
        this.camera.SetCenter(x, y);
        return "focus " + FloatToStringPrec(x, 1) + " " + FloatToStringPrec(y, 1);
    }

    // Focuses the nearest spot to (cx, cy), on a 20 m grid out to 300 m, with no layer item within 30 m.
    // The nearest spot (20 m grid, up to 300 m out) where the crosshair at this zoom picks nothing: clear of every item
    // by the pick radius in metres (SelectRadius map units at this m/unit), plus a margin.
    public func Soak_FocusEmpty(cx: Float, cy: Float, mpp: Float) -> String {
        if !IsDefined(this.camera) || !this.isOpen { return "map closed"; }
        let clear = NMTheme.SelectRadius() * this.panel.layout.scale * mpp * 1.25;
        let ring = 0;
        while ring <= 15 {
            let i = -ring;
            while i <= ring {
                let j = -ring;
                while j <= ring {
                    if AbsF(Cast<Float>(i)) == Cast<Float>(ring) || AbsF(Cast<Float>(j)) == Cast<Float>(ring) {
                        let x = cx + 20.0 * Cast<Float>(i);
                        let y = cy + 20.0 * Cast<Float>(j);
                        if this.Soak_Clear(x, y, clear) { return this.Soak_FocusAt(x, y, mpp); }
                    }
                    j += 1;
                }
                i += 1;
            }
            ring += 1;
        }
        return "no empty spot";
    }

    private func Soak_Clear(x: Float, y: Float, r: Float) -> Bool {
        for L in this.api.layers {
            let k = 0;
            while k < ArraySize(L.alive) {
                if L.alive[k] {
                    let dx = L.px[k] - x;
                    let dy = L.py[k] - y;
                    if dx * dx + dy * dy < r * r { return false; }
                }
                k += 1;
            }
        }
        return true;
    }

    // GPS route points read from the vanilla minimap: "gps quest <n> tracked <n>".
    public func Soak_GpsRoute() -> String {
        let r = this.Gps().Read(GetPlayer(this.GetGameInstance()));
        if !IsDefined(r) { return "gps none"; }
        return "gps quest " + ArraySize(r.quest) + " tracked " + ArraySize(r.tracked);
    }

    // Distance V moved since vmark: "still 0.1" under half a metre, else "moved 3.4".
    public func Soak_VDist() -> String {
        let d = Vector4.Distance(this.soakMarkV, GetPlayer(this.GetGameInstance()).GetWorldPosition());
        return (d < 0.5 ? "still " : "moved ") + FloatToStringPrec(d, 1);
    }

    public func Soak_CMark() -> String {
        if !IsDefined(this.camera) || !this.isOpen { return "map closed"; }
        this.soakMarkCx = this.camera.cx;
        this.soakMarkCy = this.camera.cy;
        this.soakMarkMpp = this.camera.mpp;
        return "marked";
    }

    // Camera change since cmark: "pan <metres> dx <m> dy <m> zoom <in|out|same> <ratio>".
    public func Soak_CDist() -> String {
        if !IsDefined(this.camera) || !this.isOpen { return "map closed"; }
        let dx = this.camera.cx - this.soakMarkCx;
        let dy = this.camera.cy - this.soakMarkCy;
        let r = this.camera.mpp / this.soakMarkMpp;
        let z = r < 0.95 ? "in" : (r > 1.05 ? "out" : "same");
        return "pan " + FloatToStringPrec(SqrtF(dx * dx + dy * dy), 0) + " dx " + FloatToStringPrec(dx, 0) + " dy " + FloatToStringPrec(dy, 0)
            + " zoom " + z + " " + FloatToStringPrec(r, 2);
    }

    // Camera centre, zoom and follow, plus the pad state: "cam x y mpp follow|pad owned ctx".
    public func Soak_Cam() -> String {
        if !IsDefined(this.camera) || !this.isOpen { return "map closed|pad " + (this.padOwned ? "owned" : "free") + " kb " + (this.kbOwned ? "owned" : "free") + " ctx " + (this.padCtx ? "held" : "free"); }
        let x = this.camera.cx; let y = this.camera.cy; let m = this.camera.mpp;
        return "cam " + FloatToStringPrec(x, 1) + " " + FloatToStringPrec(y, 1) + " " + FloatToStringPrec(m, 3) + " " + (this.camera.follow ? "follow" : "free")
            + "|pad " + (this.padOwned ? "owned" : "free") + " kb " + (this.kbOwned ? "owned" : "free") + " ctx " + (this.padCtx ? "held" : "free");
    }

    // Probe: the player state machine's UI input context, as non-pausing tutorial popups use it.
    public func Soak_UiCtx(on: Bool) -> String {
        let e = new PSMPostponedParameterBool();
        e.id = on ? n"OnUIContextActive" : n"OnUIContextInactive";
        e.value = true;
        GetPlayer(this.GetGameInstance()).QueueEvent(e);
        return on ? "ui on" : "ui off";
    }

    public func Soak_Se(name: String, on: Bool) -> String {
        let player = GetPlayer(this.GetGameInstance());
        let id = TDBID.Create("GameplayRestriction." + name);
        if on { StatusEffectHelper.ApplyStatusEffect(player, id); } else { StatusEffectHelper.RemoveStatusEffect(player, id); }
        return (on ? "se on " : "se off ") + name;
    }

    // Camera heading in degrees (0 = +Y), for telling whether the right stick still turns the view.
    public func Soak_Yaw() -> String {
        let f = GameInstance.GetCameraSystem(this.GetGameInstance()).GetActiveCameraForward();
        let fx = f.X; let fy = f.Y;
        return "yaw " + FloatToStringPrec(Rad2Deg(AtanF(fx, fy)), 1);
    }

    // Player state machine values, for finding what holds V after a close.
    public func Soak_Psm() -> String {
        let player = GetPlayer(this.GetGameInstance()) as PlayerPuppet;
        let bb = player.GetPlayerStateMachineBlackboard();
        let d = GetAllBlackboardDefs().PlayerStateMachine;
        return "loco " + IntToString(bb.GetInt(d.Locomotion)) + " det " + IntToString(bb.GetInt(d.LocomotionDetailed))
            + " high " + IntToString(bb.GetInt(d.HighLevel)) + " upper " + IntToString(bb.GetInt(d.UpperBody))
            + " ui " + IntToString(bb.GetInt(d.UI)) + " dil " + IntToString(bb.GetInt(d.TimeDilation))
            + " tier " + IntToString(bb.GetInt(d.SceneTier)) + " zones " + IntToString(bb.GetInt(d.Zones))
            + " combat " + IntToString(bb.GetInt(d.Combat)) + " vision " + IntToString(bb.GetInt(d.Vision))
            + " cons " + IntToString(bb.GetInt(d.Consumable)) + " gadget " + IntToString(bb.GetInt(d.CombatGadget))
            + " uizoom " + ToString(bb.GetBool(d.IsUIZoomDevice)) + " mg " + ToString(bb.GetBool(d.IsInMinigame));
    }

    // Pause menus OverlayMap opened for a View tap.
    public func Soak_Pauses() -> String { return "pauses " + IntToString(this.padPauses); }

    // Which keys the game itself reports, for telling "the key never arrived" from "the map ignored it".
    private let soakKeys: String;

    public func Soak_WatchKeys() -> String {
        GameInstance.GetCallbackSystem().RegisterCallback(n"Input/Key", this, n"Soak_OnKey");
        return "watching";
    }

    private cb func Soak_OnKey(evt: ref<KeyInputEvent>) {
        this.soakKeys += ToString(evt.GetKey()) + ":" + ToString(evt.GetAction()) + " ";
    }

    private let soakAxis: String;
    private let soakCtx: Bool;

    // Stick and trigger events from the pad (mouse axes are skipped): key and value, capped so a held stick can't grow it.
    public func Soak_WatchAxis() -> String {
        GameInstance.GetCallbackSystem().RegisterCallback(n"Input/Axis", this, n"Soak_OnAxis");
        return "watching";
    }

    private cb func Soak_OnAxis(evt: ref<AxisInputEvent>) {
        let k = ToString(evt.GetKey());
        let wheelAxis = StrContains(k, "Wheel") || Equals(k, "IK_MouseZ");
        if (StrBeginsWith(k, "IK_Pad") || wheelAxis) && AbsF(evt.GetValue()) > 0.05 && StrLen(this.soakAxis) < 1500 {
            this.soakAxis += k + "=" + FloatToStringPrec(evt.GetValue(), 2) + " ";
        }
    }

    public func Soak_LastAxis() -> String {
        let seen = this.soakAxis;
        this.soakAxis = "";
        return StrLen(seen) > 0 ? seen : "none";
    }

    // Whether a full-screen game menu (the vanilla map, hub, pause menu) is up.
    public func Soak_InMenu() -> String {
        let bb = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_System);
        return bb.GetBool(GetAllBlackboardDefs().UI_System.IsInMenu) ? "menu" : "game";
    }

    // Holds the game's actions off with the modal popup context, as the vehicle radio list does.
    public func Soak_HoldCtx(on: Bool) -> String {
        if Equals(on, this.soakCtx) { return on ? "held" : "free"; }
        this.soakCtx = on;
        let ui = GameInstance.GetUISystem(this.GetGameInstance());
        if on { ui.PushGameContext(UIGameContext.ModalPopup); } else { ui.PopGameContext(UIGameContext.ModalPopup); }
        return on ? "held" : "free";
    }

    // Desktop-mode xdotool presses never reach the game (Wayland drops them): feed one press + release of a bound key
    // through the same HandleKey the game's Input/Key callback uses. Names the action, not the key, so rebinds hold.
    public func Soak_PressBound(what: String) -> String {
        let s = this.Settings();
        let key = EInputKey.IK_None;
        if Equals(what, "waypoint") { key = s.keyWaypoint; }
        if Equals(what, "act") { key = s.keyAct; }
        if Equals(what, "toggle") { key = s.keyToggle; }
        if Equals(what, "teleport") { key = s.keyTeleport; }
        if Equals(what, "filter") { key = s.keyFilter; }
        if Equals(key, EInputKey.IK_None) { return "usage: press waypoint|act|toggle|teleport|filter"; }
        // The open key needs the player's Open map modifier (Ctrl, Shift or both) to open; held for every toggle press.
        let m = s.keyToggleMod;
        let isToggle = Equals(what, "toggle");
        let shift = isToggle && (Equals(m, OverlayMapOpenModifier.Shift) || Equals(m, OverlayMapOpenModifier.ShiftCtrl));
        let ctrl = isToggle && (Equals(m, OverlayMapOpenModifier.Ctrl) || Equals(m, OverlayMapOpenModifier.ShiftCtrl));
        let used = this.HandleKey(key, EInputAction.IACT_Press, shift, ctrl, false);
        this.HandleKey(key, EInputAction.IACT_Release, shift, ctrl, false);
        return "pressed " + NMInput.KeyName(key) + " used=" + ToString(used);
    }

    public func Soak_LastKeys() -> String {
        let seen = this.soakKeys;
        this.soakKeys = "";
        return StrLen(seen) > 0 ? seen : "none";
    }

    // For this launch only: the setting is not saved.
    public func Soak_HoldMode() -> String {
        this.Settings().holdToShow = true;
        return "hold";
    }

    public func Soak_Counts() -> String {
        if !IsDefined(this.renderer) { return "map closed"; }
        return "chips " + IntToString(this.renderer.chipsUsed)
            + "|mpp " + FloatToStringPrec(this.camera.mpp, 2) + "|culled " + IntToString(this.renderer.culled);
    }

    // The ACT key's effect without a key event (tracks the selected vanilla marker, as NUM 0 does).
    public func Soak_Act() -> String {
        if !this.isOpen { return "map closed"; }
        this.input.act = true;
        return "ok";
    }

    // Centres the map on the item of the first layer whose id contains `part` nearest to V (a hover for look shots).
    // Centres on the nearest vanilla entry Enter would track as a quest (a job or gig not already tracked).
    public func Soak_FocusQuest(mpp: Float) -> String {
        if !IsDefined(this.camera) || !IsDefined(this.vanilla) { return "map closed"; }
        let gi = this.GetGameInstance();
        let here = GetPlayer(gi).GetWorldPosition();
        let bestL = -1;
        let best = -1;
        let bestD = 0.0;
        let li = 0;
        while li < ArraySize(this.api.layers) {
            let L = this.api.layers[li];
            if StrBeginsWith(NameToString(L.id), "Vanilla.") {
                let i = 0;
                while i < ArraySize(L.alive) {
                    if L.alive[i] {
                        let m = this.vanilla.MappinAt(L, i);
                        if IsDefined(m) && NMVanillaTracking.CanTrackQuest(gi, m) && !NMVanillaTracking.IsQuestTracked(gi, m) {
                            let dx = L.px[i] - here.X;
                            let dy = L.py[i] - here.Y;
                            let d = dx * dx + dy * dy;
                            if best < 0 || d < bestD { bestL = li; best = i; bestD = d; }
                        }
                    }
                    i += 1;
                }
            }
            li += 1;
        }
        if best < 0 { return "none"; }
        let B = this.api.layers[bestL];
        this.camera.follow = false;
        this.camera.SetMpp(mpp);
        this.camera.SetCenter(B.px[best], B.py[best]);
        return "ok|" + NameToString(B.id) + "|" + FloatToStringPrec(SqrtF(bestD), 0) + "m";
    }

    public func Soak_FocusLayer(part: String, mpp: Float) -> String {
        if !IsDefined(this.camera) { return "map closed"; }
        let here = GetPlayer(this.GetGameInstance()).GetWorldPosition();
        for L in this.api.layers {
            if L.count > 0 && StrContains(NameToString(L.id), part) {
                let best = -1;
                let bestD = 0.0;
                let i = 0;
                while i < ArraySize(L.alive) {
                    if L.alive[i] {
                        let dx = L.px[i] - here.X;
                        let dy = L.py[i] - here.Y;
                        let d = dx * dx + dy * dy;
                        if best < 0 || d < bestD {
                            best = i;
                            bestD = d;
                        }
                    }
                    i += 1;
                }
                if best >= 0 {
                    this.camera.follow = false;
                    this.camera.SetMpp(mpp);
                    this.camera.SetCenter(L.px[best], L.py[best]);
                    return "ok|" + NameToString(L.id) + "|" + FloatToStringPrec(SqrtF(bestD), 0) + "m";
                }
            }
        }
        return "none";
    }

    // Per layer with items: id, effective tier, priority, items, markers placed in the last relayout. For density tuning.
    public func Soak_Layers() -> String {
        if !IsDefined(this.renderer) { return "map closed"; }
        let placed: array<Int32>;
        ArrayResize(placed, ArraySize(this.api.layers));
        for li in this.renderer.candLayer {
            if li >= 0 && li < ArraySize(placed) { placed[li] += 1; }
        }
        let out = "mpp " + FloatToStringPrec(this.camera.mpp, 2) + "|culled " + IntToString(this.renderer.culled);
        let i = 0;
        while i < ArraySize(this.api.layers) {
            let L = this.api.layers[i];
            if L.count > 0 {
                out += "|" + NameToString(L.id) + ":" + IntToString(L.EffectiveTier()) + ":" + IntToString(L.priority)
                    + ":" + IntToString(L.count) + ":" + IntToString(placed[i]);
            }
            i += 1;
        }
        return out;
    }

    // corner off|shown|hidden|box x,y wxh|mpp m|vanilla_op o (first faded child)|mirror n|icons i|cones c|palette k
    public func Soak_Corner() -> String {
        let h = this.cornerHost;
        if !h.Active() {
            return "corner off|probe " + (IsDefined(h.probe) ? "held" : "none") + "|minimap " + (IsDefined(this.Gps().Minimap()) ? "attached" : "none");
        }
        let c = h.corner;
        let l = c.layout;
        let root = h.probe.Root() as inkCompoundWidget;
        let vop = IsDefined(root) && root.GetNumChildren() > 0 ? root.GetWidgetByIndex(0).GetOpacity() : -1.0;
        let known = 0;
        if IsDefined(this.palette) {
            let i = 0;
            while i < EnumInt(NMColorRole.Count) {
                if this.palette.Has(IntEnum<NMColorRole>(i)) { known += 1; }
                i += 1;
            }
        }
        return "corner " + (c.IsShown() ? "shown" : "hidden") + "|style " + ToString(c.cfg.style)
            + "|box " + FloatToStringPrec(l.x, 0) + "," + FloatToStringPrec(l.y, 0) + " " + FloatToStringPrec(l.w, 0) + "x" + FloatToStringPrec(l.h, 0)
            + "|mpp " + FloatToStringPrec(c.Mpp(), 2) + "|vanilla_op " + FloatToStringPrec(vop, 2)
            + "|game_shows " + (h.probe.ShownByGame() ? "1" : "0")
            + "|mirror " + IntToString(this.mirror.Count()) + "|icons " + IntToString(c.mirrorLayer.drawnIcons)
            + "|cones " + IntToString(c.mirrorLayer.drawnCones) + "|gps_scale " + FloatToStringPrec(this.MiniScale(GetPlayer(this.GetGameInstance())), 3)
            + "|palette " + IntToString(known);
    }

    // hud_find: where the vanilla minimap's virtual window sits in the HUD window (the minimap root's own boxes are
    // local to that window). Dumps the HUD window to depth 3 into hud_tree.txt, marking the minimap's ancestors.
    public func Soak_HudFind() -> String {
        let window = this.HudWindow();
        let ctrl = this.Gps().Minimap();
        if !IsDefined(window) || !IsDefined(ctrl) { return "no window or minimap"; }
        let root = ctrl.NMRoot();
        let vw = IsDefined(root) ? root.GetParentWidget() : null;
        let dump = NMSoakDump.Open("hud_tree.txt");
        let found = this.Soak_HudWalk(window, root, vw, 0, 3, dump, "");
        dump.Flush();
        return "found " + found + "|vw " + (IsDefined(vw) ? NameToString(vw.GetClassName()) : "-")
            + "|root " + (IsDefined(root) ? NMMinimapSpike.BoxS(root) : "-") + "|window " + NMMinimapSpike.BoxS(window);
    }

    private func Soak_HudWalk(w: wref<inkWidget>, root: wref<inkWidget>, vw: wref<inkWidget>, depth: Int32, max: Int32, dump: ref<NMSoakDump>, path: String) -> String {
        let mark = Equals(w, root) ? " <ROOT>" : (Equals(w, vw) ? " <VW>" : "");
        let pad = "";
        let k = 0;
        while k < depth { pad += "  "; k += 1; }
        let here = path + "/" + NameToString(w.GetName());
        dump.Line(pad + NameToString(w.GetName()) + " [" + NameToString(w.GetClassName()) + "] ctrl=" + NMMinimapSpike.CtrlName(w)
            + " box=" + NMMinimapSpike.BoxS(w) + " vis=" + (w.IsVisible() ? "1" : "0") + " op=" + FloatToStringPrec(w.GetOpacity(), 2) + mark);
        let found = StrLen(mark) > 0 ? here + " " + NMMinimapSpike.BoxS(w) : "";
        let comp = w as inkCompoundWidget;
        if IsDefined(comp) && depth < max {
            let i = 0;
            while i < comp.GetNumChildren() {
                let f = this.Soak_HudWalk(comp.GetWidgetByIndex(i), root, vw, depth + 1, max, dump, here);
                if StrLen(f) > 0 && StrLen(found) == 0 { found = f; }
                i += 1;
            }
        }
        return found;
    }

    // mirror_dump: enemy / police / device entries as the shape layer sees them (up to 12), into mirror.txt; the answer
    // counts them by kind and how many pass Shown().
    public func Soak_MirrorDump() -> String {
        let dump = NMSoakDump.Open("mirror.txt");
        let n = 0;
        let shown = 0;
        let kinds = "";
        let k = 0;
        while k < 7 {
            let c = 0;
            for e in this.mirror.All() {
                if EnumInt(e.kind) == k { c += 1; }
            }
            kinds += IntToString(k) + "=" + IntToString(c) + " ";
            k += 1;
        }
        let player = GetPlayer(this.GetGameInstance());
        let pp = player.GetWorldPosition();
        for e in this.mirror.All() {
            if e.Shown() { shown += 1; }
            if n < 12 && (Equals(e.kind, NMMiniKind.Enemy) || Equals(e.kind, NMMiniKind.Police) || Equals(e.kind, NMMiniKind.Device)) {
                let w = e.Position();
                let ic = e.icon;
                let co = e.cone;
                dump.Line(NameToString(e.cls) + "|kind " + IntToString(EnumInt(e.kind)) + "|shown " + ToString(e.Shown())
                    + "|root " + (IsDefined(e.root) ? (ToString(e.root.IsVisible()) + " " + FloatToStringPrec(e.root.GetOpacity(), 2)) : "-")
                    + "|icon " + (IsDefined(ic) ? (NameToString(ic.GetTexturePart()) + " " + ToString(ic.IsVisible()) + " " + FloatToStringPrec(ic.GetOpacity(), 2)) : "-")
                    + "|cone " + (IsDefined(co) ? (NameToString(co.GetTexturePart()) + " " + ToString(co.IsVisible()) + " " + FloatToStringPrec(co.GetOpacity(), 2)
                        + " rot " + FloatToStringPrec(co.GetRotation(), 0)) : "-")
                    + "|obj " + ToString(IsDefined(e.obj)) + "|d " + FloatToStringPrec(Vector4.Distance2D(w, pp), 1) + "|coneLen " + FloatToStringPrec(e.coneLen, 1));
                n += 1;
            }
        }
        dump.Flush();
        return "mirror " + IntToString(this.mirror.Count()) + "|shown " + IntToString(shown) + "|kinds " + kinds;
    }

    // god: V can't die (enemy campaigns).
    public func Soak_God() -> String {
        StatusEffectHelper.ApplyStatusEffect(GetPlayer(this.GetGameInstance()), t"BaseStatusEffect.Invulnerable");
        return "god";
    }

    public func Soak_SeedPhotos(n: Int32) -> String {
        this.Photos().SeedForPerf(n);
        return "seeded";
    }

    // Look checks: a setting changed in memory (the harness restores the settings file after the campaign). The panel
    // reads these on open, so close and open after a change. effects 0|1, theme cyan|green|red|purple|amber, opacity <float>.
    // Photo pin storage through the plugin: pins read now, then one test pin appended and read back. The campaign
    // restores r6/storages/OverlayMap afterwards, so the test pin doesn't stay.
    public func Soak_PhotoStore() -> String {
        // Results held in locals: ArraySize() straight on a call's returned array read 0 in game.
        let a = NMPhotoStore.Load();
        let before = ArraySize(a);
        let ok = NMPhotoStore.Append(NMPhotoSpot.Create(4242u, "photomode_soaktest.png", new Vector4(0.0, 0.0, 10.0, 1.0), 0.0, 1ul));
        let b = NMPhotoStore.Load();
        let after = ArraySize(b);
        return "photostore before " + ToString(before) + " appended " + ToString(ok) + " after " + ToString(after)
            + " skipped " + ToString(NMPhotoStore.Skipped());
    }

    public func Soak_Set(name: String, value: String) -> String {
        let s = this.Settings();
        if !IsDefined(s) { return "no settings"; }
        if Equals(name, "effects") { s.hologramEffects = Equals(value, "1"); return "effects " + ToString(s.hologramEffects); }
        if Equals(name, "theme") {
            s.holoColor = OverlayMapHoloColor.Cyan;
            if Equals(value, "green") { s.holoColor = OverlayMapHoloColor.Green; }
            if Equals(value, "red") { s.holoColor = OverlayMapHoloColor.Red; }
            if Equals(value, "purple") { s.holoColor = OverlayMapHoloColor.Purple; }
            if Equals(value, "amber") { s.holoColor = OverlayMapHoloColor.Amber; }
            return "theme " + ToString(NMTheme.ThemeIndex(s.holoColor));
        }
        if Equals(name, "opacity") { s.panelOpacity = StringToFloat(value); return "opacity " + FloatToStringPrec(s.panelOpacity, 2); }
        // nomodal 1: take the keyboard without the modal popup game context (mouse-look probe).
        if Equals(name, "nomodal") { this.soakNoModal = Equals(value, "1"); return "nomodal " + ToString(this.soakNoModal); }
        // Map look: mapop <float> (whole panel), bright <float>, contrast <float>.
        if Equals(name, "mapop") { s.mapOpacity = StringToFloat(value); return "mapop " + FloatToStringPrec(s.mapOpacity, 2); }
        if Equals(name, "bright") { s.mapBrightness = StringToFloat(value); return "bright " + FloatToStringPrec(s.mapBrightness, 2); }
        if Equals(name, "contrast") { s.mapContrast = StringToFloat(value); return "contrast " + FloatToStringPrec(s.mapContrast, 2); }
        // VHS look: scan <float>, glow <float>, tracking 0|1, glitch 0|1.
        if Equals(name, "scan") { s.scanlineStrength = StringToFloat(value); return "scan " + FloatToStringPrec(s.scanlineStrength, 2); }
        if Equals(name, "glow") { s.glowStrength = StringToFloat(value); return "glow " + FloatToStringPrec(s.glowStrength, 2); }
        if Equals(name, "tracking") { s.vhsTracking = Equals(value, "1"); return "tracking " + ToString(s.vhsTracking); }
        if Equals(name, "glitch") { s.vhsGlitch = Equals(value, "1"); return "glitch " + ToString(s.vhsGlitch); }
        if Equals(name, "ncart") { s.filterNcart = Equals(value, "1"); return "ncart " + ToString(s.filterNcart); }
        // Controller open: view|off. Pad steps set it explicitly, so they don't depend on the player's saved choice.
        if Equals(name, "mousepan") { s.mousePan = Equals(value, "1"); return "mousepan " + ToString(s.mousePan); }
        if Equals(name, "padopen") {
            s.padOpen = Equals(value, "off") ? OverlayMapPadOpen.Off : OverlayMapPadOpen.HoldView;
            return "padopen " + ToString(s.padOpen);
        }
        // Corner minimap: replace 0|1, style circle|square|strip, hudpainter 0|1, debug 0|1, enemies 0|1. The corner poll
        // picks a change up within a second.
        if Equals(name, "replace") { s.replaceMinimap = Equals(value, "1"); return "replace " + ToString(s.replaceMinimap); }
        if Equals(name, "style") {
            s.cornerStyle = Equals(value, "circle") ? OverlayMapCornerStyle.Circle : (Equals(value, "square") ? OverlayMapCornerStyle.Square : OverlayMapCornerStyle.SquareStrip);
            return "style " + ToString(s.cornerStyle);
        }
        if Equals(name, "hudpainter") { s.followHudPainter = Equals(value, "1"); return "hudpainter " + ToString(s.followHudPainter); }
        if Equals(name, "debug") { s.debug = Equals(value, "1"); return "debug " + ToString(s.debug); }
        if Equals(name, "fadeop") {
            if !this.cornerHost.Active() { return "no corner"; }
            this.cornerHost.probe.SetFadeTarget(StringToFloat(value));
            this.cornerHost.probe.Fade();
            return "fadeop " + value;
        }
        if Equals(name, "enemies") { s.cornerEnemies = Equals(value, "1"); return "enemies " + ToString(s.cornerEnemies); }
        return "unknown setting";
    }

    // NMPerfSuite without the debug chord: opens the map, starts the suite, and reports perf_done once it ends. The
    // RESULT| and PERF| lines go to CET's gamelog.log, which the harness keeps with the run (gamelog-tail.log).
    private let soakPerfWatch: Bool;

    public func Soak_Perf(only: String) -> String {
        if !NMClock.Precise() { return "no precise clock"; }
        if !this.isOpen { this.Open(); }
        if !this.isOpen { return "not open"; }
        this.perf = new NMPerfSuite();
        this.perf.StartOnly(only);
        this.soakPerfWatch = true;
        return "started";
    }

    // Soak_Frame runs only while the panel draws: the suite's hidden scenarios skip it, and the end restores it.
    private func Soak_PerfFrame() {
        if this.soakPerfWatch && IsDefined(this.perf) && !this.perf.running {
            this.soakPerfWatch = false;
            NMSoak.Report("perf_done", "suite done");
        }
    }

    public func Soak_StartZoomLoop(tag: String, seconds: Float, holds: Int32) -> String {
        if !IsDefined(this.camera) { return "map closed"; }
        let p = GetPlayer(this.GetGameInstance()).GetWorldPosition();
        this.soakOx = p.X;
        this.soakOy = p.Y;
        this.camera.follow = false;
        this.soakTag = tag;
        this.soakT = 0.0;
        this.soakEnd = seconds;
        this.soakResMax = 0;
        this.soakLevels = 0;
        this.soakLastLv = -1;
        this.soakHolds = 0;
        this.soakHoldMax = holds;
        this.soakHoldLeft = 0.0;
        // Tiles alone: markers change with the zoom by design (tiers fade them), and a selection can move the view.
        ArrayClear(this.soakLayerOn);
        for L in this.api.layers {
            ArrayPush(this.soakLayerOn, L.visible);
            L.SetVisible(false);
        }
        this.soakMode = 2;
        return "started";
    }

    // Every tile set on its new level and nothing left to load: what is on screen now is the settled picture, so any
    // difference from a later one is a stale or missing tile. Until then the old level legitimately still shows.
    private func Soak_Crossed() -> Bool {
        let names: array<String> = ["glow", "road", "bfill", "outline"];
        for name in names {
            let t = this.layers.Layer(name) as NMTileLayer;
            if IsDefined(t) && (t.Waiting() > 0 || t.PreviousLevel() >= 0 || t.Alpha() < 1.0) { return false; }
        }
        return true;
    }

    private func Soak_ModeFrame(dt: Float) {
        if this.soakHoldLeft > 0.0 {
            this.soakHoldLeft -= dt / 1000.0;
            if this.soakCrossing {
                this.soakCrossMs += dt;
                if this.Soak_Crossed() {
                    this.soakCrossing = false;
                    NMSoak.Report("hold", IntToString(this.soakHolds) + "|L" + IntToString(this.soakLastLv) + "|crossed in "
                        + FloatToStringPrec(this.soakCrossMs, 0) + " ms");
                }
            }
            return;
        }
        this.soakT += dt / 1000.0;
        if this.soakT >= this.soakEnd {
            if this.soakMode == 1 { this.renderer.Soak_ChurnIcons(false); }
            if this.soakMode == 2 {
                let i = 0;
                while i < ArraySize(this.soakLayerOn) {
                    this.api.layers[i].SetVisible(this.soakLayerOn[i]);
                    i += 1;
                }
            }
            let detail = this.soakMode == 2 ? "levels " + IntToString(this.soakLevels) + "|residentmax " + IntToString(this.soakResMax) : "";
            this.soakMode = 0;
            NMSoak.Report("mode_done_" + this.soakTag, detail);
            return;
        }
        if this.soakMode == 1 {
            if this.soakT >= 6.0 {
                this.soakFlip = !this.soakFlip;
                this.renderer.Soak_ChurnIcons(this.soakFlip);
            }
            return;
        }
        let m = 1.5 * PowF(2.0, SinF(this.soakT * 2.4));
        this.camera.SetMpp(m);
        this.camera.SetCenter(this.soakOx + 90.0 * this.soakT, this.soakOy + 40.0 * this.soakT);
        let road = this.layers.Layer("road") as NMTileLayer;
        if IsDefined(road) {
            if road.Resident() > this.soakResMax { this.soakResMax = road.Resident(); }
            if road.CurrentLevel() != this.soakLastLv {
                this.soakLastLv = road.CurrentLevel();
                this.soakLevels += 1;
                if this.soakHolds < this.soakHoldMax {   // the level just changed: stop here until it has crossed
                    this.soakHolds += 1;
                    this.soakHoldLeft = 14.0;
                    this.soakCrossing = true;
                    this.soakCrossMs = 0.0;
                }
            }
        }
    }

    // ---- corner-minimap parity spike (MinimapSpike.reds does the work; these pass the HUD window) ----

    public func Soak_MmTree(depth: Int32) -> String {
        return NMMinimapSpike.Tree(this.HudWindow(), depth > 0 ? depth : 6);
    }

    public func Soak_MmVis() -> String {
        return NMMinimapSpike.Vis(this.HudWindow());
    }

    public func Soak_MmReset() -> String {
        let reg = NMMinimapSpikeReg.Get();
        if !IsDefined(reg) { return "no reg"; }
        reg.Reset();
        return "reset";
    }

    public func Soak_MmCtrls() -> String {
        let reg = NMMinimapSpikeReg.Get();
        if !IsDefined(reg) { return "no reg"; }
        let out = NMSoakDump.Open("mm_ctrls.txt");
        let summary = reg.Dump(out);
        out.Flush();
        return "ctrls " + IntToString(reg.Size()) + "|" + summary;
    }

    public func Soak_MmStealth() -> String {
        let reg = NMMinimapSpikeReg.Get();
        if !IsDefined(reg) { return "no reg"; }
        let out = NMSoakDump.Open("mm_stealth.txt");
        let n = reg.DumpStealth(out);
        out.Flush();
        return "stealth " + IntToString(n);
    }

    public func Soak_MmZone() -> String {
        let reg = NMMinimapSpikeReg.Get();
        if !IsDefined(reg) || !IsDefined(reg.container) { return "container not attached"; }
        return reg.container.NMSpikeZone();
    }

    public func Soak_PaletteProbe() -> String {
        return NMMinimapSpike.PaletteProbe(this.HudWindow());
    }

    public func Soak_PaletteRead() -> String {
        return NMMinimapSpike.PaletteRead();
    }

    // Positive control for corner clipping: an oversized bright rectangle clipped by inkScrollArea's internal mask (the
    // Square/SquareStrip pattern from NMPanel). A screenshot shows the clip. Circle style needs its own radial mask.
    public func Soak_MaskProbe() -> String {
        let window = this.HudWindow();
        if !IsDefined(window) { return "no window"; }
        let area = new inkScrollArea();
        area.SetName(n"NMMaskProbe");
        area.SetAnchor(inkEAnchor.TopLeft);
        area.SetSize(new Vector2(400.0, 400.0));
        area.SetTranslation(new Vector2(200.0, 200.0));
        area.SetUseInternalMask(true);
        area.SetInteractive(false);
        area.Reparent(window);
        let inner = new inkCanvas();
        inner.SetSize(new Vector2(400.0, 400.0));
        inner.SetInteractive(false);
        inner.Reparent(area);
        NMUi.Rect(inner, -100.0, -100.0, 600.0, 600.0, new HDRColor(1.0, 0.0, 1.0, 1.0), 1.0);
        return "mask probe placed 400x400 at 200,200 (magenta clipped to the box)";
    }

    // Spike for script-attached engine effects (NMFx): blur the tile canvas or glitch the whole map content at a fixed
    // intensity, so a screenshot shows whether the renderer applies an effect pushed onto inkWidget.effects at runtime.
    public func Soak_FxProbe(mode: String, v: Float) -> String {
        if !IsDefined(this.panel) { return "map not open"; }
        if Equals(mode, "blur") {
            NMFx.AddBlur2D(this.panel.tiles, v, 16);
            this.panel.tiles.SetEffectEnabled(inkEffectType.BoxBlur, NMFx.BlurName(inkEBlurDimension.Horizontal), true);
            this.panel.tiles.SetEffectEnabled(inkEffectType.BoxBlur, NMFx.BlurName(inkEBlurDimension.Vertical), true);
            return "blur effects=" + NMFx.EffectCount(this.panel.tiles) + " on=" + ToString(this.panel.tiles.GetEffectEnabled(inkEffectType.BoxBlur, NMFx.BlurName(inkEBlurDimension.Horizontal)));
        }
        if Equals(mode, "glitch") {
            NMFx.AddGlitch(this.panel.mapContent, this.panel.mapContent.GetWidth(), this.panel.mapContent.GetHeight());
            this.panel.mapContent.SetEffectEnabled(inkEffectType.Glitch, NMFx.GlitchName(), true);
            let r = this.panel.mapContent.SetEffectParamValue(inkEffectType.Glitch, NMFx.GlitchName(), n"intensity", v);
            return "glitch effects=" + NMFx.EffectCount(this.panel.mapContent) + " set=" + FloatToStringPrec(r, 2)
                + " read=" + FloatToStringPrec(this.panel.mapContent.GetEffectParamValue(inkEffectType.Glitch, NMFx.GlitchName(), n"intensity"), 2);
        }
        if Equals(mode, "bloom") {
            // v = 1 / 0: switch the glow layer's engine blur on or off, and report what that layer is.
            let g = IsDefined(this.layers) ? this.layers.Layer("glow") : null;
            if !IsDefined(g) || !IsDefined(g.Root()) { return "bloom no glow layer"; }
            let root = g.Root();
            let on = v > 0.5;
            root.SetEffectEnabled(inkEffectType.BoxBlur, NMFx.BlurName(inkEBlurDimension.Horizontal), on);
            root.SetEffectEnabled(inkEffectType.BoxBlur, NMFx.BlurName(inkEBlurDimension.Vertical), on);
            let tint = root.GetTintColor();
            return "bloom on=" + ToString(root.GetEffectEnabled(inkEffectType.BoxBlur, NMFx.BlurName(inkEBlurDimension.Horizontal)))
                + " effects=" + NMFx.EffectCount(root) + " op=" + FloatToStringPrec(root.GetOpacity(), 2)
                + " tint=" + FloatToStringPrec(tint.Red, 2) + "," + FloatToStringPrec(tint.Green, 2) + "," + FloatToStringPrec(tint.Blue, 2)
                + " size=" + FloatToStringPrec(root.GetWidth(), 0) + "x" + FloatToStringPrec(root.GetHeight(), 0);
        }
        return "usage: fx_probe blur|glitch|bloom <value>";
    }

    // NCART station positions for tools/tiles (nmtiles.ncart): one NCART| line per station mappin, record id first.
    public func Soak_NcartDump() -> String {
        let n = 0;
        for m in GameInstance.GetMappinSystem(this.GetGameInstance()).GetAllMappins() {
            let ft = m as FastTravelMappin;
            let data = IsDefined(ft) ? ft.GetPointData() : null;
            let rec = IsDefined(data) ? TDBID.ToStringDEBUG(data.GetPointRecord()) : "none";
            if IsDefined(ft) && (Equals(m.GetVariant(), gamedataMappinVariant.Zzz17_NCARTVariant) || StrContains(rec, "metro")) {
                let pos = ft.GetWorldPosition();
                let name = IsDefined(data) ? data.GetPointDisplayName() : "";
                NMLog.Info("NCART|" + rec + "|" + name + "|" + EnumValueToString("gamedataMappinVariant", Cast<Int64>(EnumInt(m.GetVariant()))) + "|" + FloatToStringPrec(pos.X, 2) + "|" + FloatToStringPrec(pos.Y, 2) + "|" + FloatToStringPrec(pos.Z, 2));
                n += 1;
            }
        }
        // Every registered fast-travel node with "metro" in its record, mapped or not (no position: markerRef only).
        let fts = GameInstance.GetScriptableSystemsContainer(this.GetGameInstance()).Get(n"FastTravelSystem") as FastTravelSystem;
        if IsDefined(fts) {
            for pd in fts.GetFastTravelPoints() {
                let r = TDBID.ToStringDEBUG(pd.GetPointRecord());
                if StrContains(r, "metro") { NMLog.Info("NCARTNODE|" + r + "|" + pd.GetPointDisplayName()); }
            }
        }
        NMLog.Info("NCART|DONE|" + ToString(n));
        return "ncart " + ToString(n);
    }

    // Live state of the engine-animated VHS widgets: where the tracking band is and how bright, and the glitch intensity.
    // Our gameplay restrictions on V (NMRestrict) and whether the map thinks it holds them.
    public func Soak_Restrict() -> String {
        return "restrict " + ToString(NMRestrict.Count(GetPlayer(this.GetGameInstance()))) + " held " + ToString(this.kbRestricted)
            + " uictx " + ToString(this.psmUiCtx) + " modal " + ToString(this.modalPushed);
    }

    // Map look as applied on open: the tile canvas's colour correction and the panel root's opacity.
    public func Soak_LookState() -> String {
        if !IsDefined(this.panel) { return "map not open"; }
        let out = "op=" + FloatToStringPrec(this.panel.root.GetOpacity(), 2) + " fx=" + ToString(NMFx.EffectCount(this.panel.tiles));
        let i = 0;
        while i < NMFx.EffectCount(this.panel.tiles) {
            let cc = this.panel.tiles.effects[i] as inkColorCorrectionEffect;
            if IsDefined(cc) {
                out += " cc=" + FloatToStringPrec(cc.brightness, 2) + "/" + ToString(cc.isEnabled);
            }
            i += 1;
        }
        let bg = this.panel.mapBg.GetTintColor();
        out += " bg=" + FloatToStringPrec(bg.Red, 3) + "," + FloatToStringPrec(bg.Green, 3) + "," + FloatToStringPrec(bg.Blue, 3);
        let road = IsDefined(this.layers) ? this.layers.Layer("road") as NMTileLayer : null;
        if IsDefined(road) {
            let rt = road.Tint();
            out += " road=" + FloatToStringPrec(rt.Red, 3) + "," + FloatToStringPrec(rt.Green, 3) + "," + FloatToStringPrec(rt.Blue, 3);
        }
        return out;
    }

    public func Soak_FxState() -> String {
        if !IsDefined(this.panel) || !IsDefined(this.panel.holo) { return "map not open"; }
        let s = "track=";
        let tr = this.panel.holo.track;
        if IsDefined(tr) {
            let p = tr.GetTranslation();
            s += "y" + FloatToStringPrec(p.Y, 0) + "/h" + FloatToStringPrec(tr.GetHeight(), 0) + "/o" + FloatToStringPrec(tr.GetOpacity(), 2);
        } else {
            s += "none";
        }
        let br = this.panel.holo.bar;
        if IsDefined(br) {
            let bp = br.GetTranslation();
            s += " bar=y" + FloatToStringPrec(bp.Y, 0) + "/o" + FloatToStringPrec(br.GetOpacity(), 3);
        }
        return s + " glitch=" + FloatToStringPrec(this.panel.mapContent.GetEffectParamValue(inkEffectType.Glitch, NMFx.GlitchName(), n"intensity"), 2);
    }

