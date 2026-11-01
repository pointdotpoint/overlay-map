
    // ---- soak harness (tools/soak/autopilot/RendererBody.inc, spliced in at build time) ----
    public let soakIconLoads: Int32;   // chips whose icon was set again: its texture loads asynchronously
    public let soakLoadAt: Vector2;

    // Forces what panning does to pin icons, on a still map: every placed pin gets the next category's atlas (flip);
    // unflipped, the next relayout sets every pin's own icon again.
    public func Soak_ChurnIcons(flip: Bool) {
        let n = ArraySize(this.api.catColor);
        let i = 0;
        while i < ArraySize(this.candSlot) {
            let slot = this.candSlot[i];
            if !flip {
                this.chipIconKey[slot] = "";
            } else if this.chipStyle[slot] != 3 && this.api.layers[this.candLayer[i]].IsAlive(this.candItem[i]) {
                let L = this.api.layers[this.candLayer[i]];
                let g = (L.catGlobal[L.cat[this.candItem[i]]] + 1) % n;
                if this.api.catHasIcon[g] {
                    this.chipIcon[slot].SetAtlasResource(this.api.catAtlas[g]);
                    this.chipIcon[slot].SetTexturePart(this.api.catPart[g]);
                    this.chipIconKey[slot] = "";
                }
            }
            i += 1;
        }
        if !flip { this.Invalidate(); }
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
