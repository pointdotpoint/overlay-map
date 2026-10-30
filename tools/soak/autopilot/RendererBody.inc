
    // ---- soak harness (tools/soak/autopilot/RendererBody.inc, spliced in at build time) ----
    public let soakIconLoads: Int32;   // chips whose icon was set again: its texture loads asynchronously
    public let soakLoadAt: Vector2;

    // Forces what panning does to cluster icons, on a still map: every on-screen mini gets another category's atlas.
    public func Soak_ChurnMinis(flip: Bool) {
        let n = ArraySize(this.api.catColor);
        let i = 0;
        while i < ArraySize(this.miniOn) {
            if this.miniOn[i] && this.miniCat[i] >= 0 {
                let g = flip ? (this.miniCat[i] + 1) % n : this.miniCat[i];
                if this.api.catHasIcon[g] {
                    this.miniIcon[i].SetAtlasResource(this.api.catAtlas[g]);
                    this.miniIcon[i].SetTexturePart(this.api.catPart[g]);
                }
            }
            i += 1;
        }
    }

    // Chips placed this layout whose widgets are hidden: on screen as far as the code knows, invisible to the player.
    public func Soak_Hidden() -> Int32 {
        let n = 0;
        let i = 0;
        while i < ArraySize(this.candKind) {
            if this.candKind[i] == 0 {
                let slot = this.candSlot[i];
                if this.chipStyle[slot] != 3 && (!this.chipIcon[slot].IsVisible() || !this.chipBg[slot].IsVisible()) { n += 1; }
            }
            i += 1;
        }
        return n;
    }
