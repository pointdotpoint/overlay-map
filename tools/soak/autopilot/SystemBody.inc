
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

    private func Soak_ModeFrame(dt: Float) {
        if this.soakHoldLeft > 0.0 {
            this.soakHoldLeft -= dt / 1000.0;
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
                if this.soakHolds < this.soakHoldMax {   // the level just changed: stop here for a picture
                    this.soakHolds += 1;
                    this.soakHoldLeft = 14.0;
                    NMSoak.Report("hold", IntToString(this.soakHolds) + "|L" + IntToString(this.soakLastLv));
                }
            }
        }
    }
