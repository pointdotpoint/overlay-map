
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
