
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
