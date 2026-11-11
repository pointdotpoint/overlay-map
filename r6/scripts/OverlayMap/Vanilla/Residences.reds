module OverlayMap

public class NMResidenceListener extends OverlayMapLayerListener {
    public let owner: wref<NMResidences>;

    public func GetDetails(id: Int32) -> ref<OverlayMapDetails> {
        return IsDefined(this.owner) ? this.owner.Details(id) : null;
    }
}

// Every residence, from a fixed table: H10, the four apartments for rent (apartmentoffers.tweak) and the Dogtown
// hideout, which the game never pins. Points are the doors (AMM's locations; H10 at its vanilla pin, whose Z is the
// door). The RESIDENCES view shows them all and nothing else; the other views show only the ones the game has no pin
// for, so nothing doubles. A residence the game pins as V's (ApartmentVariant) takes that icon, else the for-rent one.
public class NMResidences {
    private let layer: wref<OverlayMapLayer>;
    private let listener: ref<NMResidenceListener>;
    private let gi: GameInstance;
    private let item: array<Int32>;        // per residence: its layer item, -1 not shown
    private let state: array<Int32>;       // per residence: 0 no vanilla pin, 1 V's home pin, 2 for-rent pin
    private let shownSig: String;

    public static func LayerId() -> CName { return n"Residences"; }
    public static func Category() -> CName { return n"residences"; }
    public static func View() -> Int32 { return 3; }
    public static func Count() -> Int32 { return 6; }

    public static func AreaId(i: Int32) -> String {
        let ids = ["Districts.VApartment", "Districts.NID_apart", "Districts.JPN_apart", "Districts.Glen_apart", "Districts.Corpo_apart", "Districts.Hideout"];
        return ids[i];
    }

    public static func Door(i: Int32) -> Vector4 {
        let xs = [-1383.7, -1503.8, -785.3, -1524.0, -1599.9, -2240.0];
        let ys = [1267.4, 2224.9, 992.6, -992.6, 345.7, -2553.3];
        let zs = [123.1, 22.2, 12.0, 9.1, 8.2, 80.3];
        return new Vector4(xs[i], ys[i], zs[i], 1.0);
    }

    // Owned without renting: H10 from the start, the hideout through Phantom Liberty.
    public static func Owned(i: Int32) -> Bool { return i == 0 || i == 5; }

    // The variant whose icon and colour the residence takes, given its vanilla state.
    public static func VariantOf(i: Int32, state: Int32) -> gamedataMappinVariant {
        if state == 1 || (state == 0 && NMResidences.Owned(i)) { return gamedataMappinVariant.ApartmentVariant; }
        return gamedataMappinVariant.Zzz05_ApartmentToPurchaseVariant;
    }

    // Shown in this view: all in RESIDENCES; elsewhere only the ones the game does not pin, under their usual toggle.
    public static func Shown(i: Int32, state: Int32, view: Int32, s: ref<OverlayMapSettings>) -> Bool {
        if view == NMResidences.View() { return true; }
        if state != 0 { return false; }
        if !IsDefined(s) { return true; }
        return NMResidences.Owned(i) ? s.filterYourProperty : s.filterApartmentRent;
    }

    public static func Create(gi: GameInstance) -> ref<NMResidences> {
        let r = new NMResidences();
        r.gi = gi;
        return r;
    }

    // Rebuilds the layer when the view, the toggles or the vanilla residence pins changed. Cheap otherwise.
    public func Sync(api: ref<OverlayMap>, vanilla: ref<NMVanilla>, view: Int32, s: ref<OverlayMapSettings>) {
        let L = api.CreateLayer(NMResidences.LayerId(), "Residences", 80);
        if !IsDefined(this.listener) {
            L.SetPinStyle(OverlayMapPinStyle.Icon);
            L.SetClustering(false);
            L.SetTier(OverlayMapTier.Always);
            let home = gamedataMappinVariant.ApartmentVariant;
            L.SetCategory(NMResidences.Category(), "Residences", NMVanillaStyle.Color(home, gamedataMappinPhase.DefaultPhase));
            api.SetCategoryIcon(NMResidences.Category(), NMTheme.MappinAtlas(), NMVanillaStyle.PartOf(home));
            this.listener = new NMResidenceListener();
            this.listener.owner = this;
            L.SetListener(this.listener);
            let i = 0;
            while i < NMResidences.Count() {
                ArrayPush(this.item, -1);
                ArrayPush(this.state, -1);
                i += 1;
            }
        }
        this.layer = L;
        let sig = ToString(view) + "|" + ToString(IsDefined(vanilla) ? vanilla.residenceRev : -1);
        if IsDefined(s) { sig += "|" + ToString(s.filterYourProperty) + ToString(s.filterApartmentRent); }
        if Equals(sig, this.shownSig) { return; }
        this.shownSig = sig;
        let i = 0;
        while i < NMResidences.Count() {
            let p = NMResidences.Door(i);
            let st = IsDefined(vanilla) ? vanilla.ResidenceAt(p.X, p.Y, NMVanillaText.HomeReach()) : 0;
            let want = NMResidences.Shown(i, st, view, s);
            if !want {
                if this.item[i] >= 0 {
                    L.Remove(this.item[i]);
                    this.item[i] = -1;
                }
            } else {
                let v = NMResidences.VariantOf(i, st);
                let it = OverlayMapItem.Create(p, NMResidences.Category(), NMTheme.MappinAtlas(), NMVanillaStyle.PartOf(v))
                    .WithTint(NMVanillaStyle.Color(v, gamedataMappinPhase.DefaultPhase))
                    .WithEmphasis(NMVanillaStyle.IsHome(v));
                if this.item[i] < 0 {
                    this.item[i] = L.Add(it);
                } else if st != this.state[i] {
                    L.Update(this.item[i], it);
                }
            }
            this.state[i] = st;
            i += 1;
        }
        L.SetVisible(true);
    }

    public func IndexOf(itemId: Int32) -> Int32 {
        let i = 0;
        while i < ArraySize(this.item) {
            if this.item[i] == itemId && itemId >= 0 { return i; }
            i += 1;
        }
        return -1;
    }

    public func Details(itemId: Int32) -> ref<OverlayMapDetails> {
        let i = this.IndexOf(itemId);
        if i < 0 { return null; }
        let v = NMResidences.VariantOf(i, this.state[i]);
        let name = NMAreaIndex.DistrictName(NMResidences.AreaId(i));
        let d = OverlayMapDetails.Create(NMVanillaText.LabelOf(v), StrLen(name) > 0 ? name : NMVanillaText.LabelOf(v))
            .WithColor(NMVanillaStyle.Color(v, gamedataMappinPhase.DefaultPhase));
        let player = GetPlayer(this.gi);
        if IsDefined(player) {
            d.AddRow("Distance", NMMath.FormatMeters(Vector4.Distance(player.GetWorldPosition(), NMResidences.Door(i))));
        }
        return d;
    }
}
