
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
    private let soakDropsCluster: Int32;
    private let soakDropsDead: Int32;
    private let soakDropsBare: Int32;
    private let soakBack: Int32;
    private let soakBackGap: Int32;
    private let soakMoved: Int32;
    private let soakLoads0: Int32;
    private let soakBudgetFrames: Int32;
    private let soakClusterFrames: Int32;
    private let soakChipsMax: Int32;
    private let soakLogged: Int32;
    private let soakHidden: Int32;
    private let soakHiddenMax: Int32;
    private let soakClDrops: Int32;
    private let soakClMoved: Int32;
    private let soakHolds: Int32;
    private let soakHoldMax: Int32;
    private let soakHoldLeft: Float;
    private let soakLoadsSeen: Int32;

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
        this.soakDropsCluster = 0;
        this.soakDropsDead = 0;
        this.soakDropsBare = 0;
        this.soakBack = 0;
        this.soakBackGap = 0;
        this.soakMoved = 0;
        this.soakBudgetFrames = 0;
        this.soakClusterFrames = 0;
        this.soakChipsMax = 0;
        this.soakLogged = 0;
        this.soakLoads0 = this.renderer.soakIconLoads;
        this.soakLoadsSeen = this.soakLoads0;
        this.soakHidden = 0;
        this.soakHiddenMax = 0;
        this.soakClDrops = 0;
        this.soakClMoved = 0;
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
                + "|budget " + IntToString(this.soakDropsBudget) + "|cluster " + IntToString(this.soakDropsCluster)
                + "|dead " + IntToString(this.soakDropsDead) + "|back " + IntToString(this.soakBack)
                + "|backgap " + IntToString(this.soakBackGap) + "|moved " + IntToString(this.soakMoved)
                + "|iconloads " + IntToString(this.renderer.soakIconLoads - this.soakLoads0)
                + "|budgetframes " + IntToString(this.soakBudgetFrames)
                + "|clusterframes " + IntToString(this.soakClusterFrames)
                + "|chipsmax " + IntToString(this.soakChipsMax)
                + "|cldrops " + IntToString(this.soakClDrops) + "|clmoved " + IntToString(this.soakClMoved)
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
            // Clusters carry layer -1 and their cell key: negative keys, so they never decode as markers.
            ArrayPush(cur, r.candKind[i] == 0 ? r.candLayer[i] * 100000 + r.candItem[i] : -1 - r.candItem[i]);
            i += 1;
        }
        if r.chipsUsed > this.soakChipsMax { this.soakChipsMax = r.chipsUsed; }
        let hidden = r.Soak_Hidden();
        this.soakHidden += hidden;
        if hidden > this.soakHiddenMax { this.soakHiddenMax = hidden; }
        let full = r.chipsUsed >= NMTheme.ChipBudget();
        let clustered = r.clustersUsed > 0;
        if full { this.soakBudgetFrames += 1; }
        if clustered { this.soakClusterFrames += 1; }
        let p = 0;
        while p < ArraySize(this.soakPrevKeys) {
            let key = this.soakPrevKeys[p];
            let at = ArrayFindFirst(cur, key);
            if at < 0 {
                this.Soak_Dropped(key, full, clustered);
            } else if r.candSlot[at] != this.soakPrevSlots[p] {
                if key < 0 { this.soakClMoved += 1; } else { this.soakMoved += 1; }
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

    private func Soak_Dropped(key: Int32, full: Bool, clustered: Bool) {
        if key < 0 {
            this.soakClDrops += 1;
            return;
        }
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
        if clustered { this.soakDropsCluster += 1; }
        if !full && !clustered { this.soakDropsBare += 1; }
        ArrayPush(this.soakRecent, key);
        ArrayPush(this.soakRecentFrame, this.soakFrames);
        if this.soakLogged < 25 {
            this.soakLogged += 1;
            NMSoak.Report("sweep_drop", this.soakTag + "|f" + IntToString(this.soakFrames) + "|L" + IntToString(li) + "#" + IntToString(item)
                + "|at " + FloatToStringPrec(at.X, 0) + "," + FloatToStringPrec(at.Y, 0) + "|chips " + IntToString(this.renderer.chipsUsed)
                + "|clusters " + IntToString(this.renderer.clustersUsed));
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
        if !IsDefined(this.camera) || !this.isOpen { return "map closed|pad " + (this.padOwned ? "owned" : "free") + " ctx " + (this.padCtx ? "held" : "free"); }
        let x = this.camera.cx; let y = this.camera.cy; let m = this.camera.mpp;
        return "cam " + FloatToStringPrec(x, 1) + " " + FloatToStringPrec(y, 1) + " " + FloatToStringPrec(m, 3) + " " + (this.camera.follow ? "follow" : "free")
            + "|pad " + (this.padOwned ? "owned" : "free") + " ctx " + (this.padCtx ? "held" : "free");
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

    // Pause menus NightMap opened for a View tap.
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
        if StrBeginsWith(k, "IK_Pad") && AbsF(evt.GetValue()) > 0.05 && StrLen(this.soakAxis) < 1500 {
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
        return "chips " + IntToString(this.renderer.chipsUsed) + "|clusters " + IntToString(this.renderer.clustersUsed)
            + "|mpp " + FloatToStringPrec(this.camera.mpp, 2);
    }

    public func Soak_SeedPhotos(n: Int32) -> String {
        this.Photos().SeedForPerf(n);
        return "seeded";
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
        // Tiles alone: markers change with the zoom by design (clusters to pins), and a selection can move the view.
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
            if this.soakMode == 1 { this.renderer.Soak_ChurnMinis(false); }
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
                this.renderer.Soak_ChurnMinis(this.soakFlip);
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
