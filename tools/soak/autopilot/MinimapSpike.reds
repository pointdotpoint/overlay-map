module NightMap
import SoakBootstrap.*

// Corner-minimap parity spike (Task 1 of the corner-minimap plan). Overlaid into the scripts ONLY during a campaign
// build (tools/soak/builds.py) and the --soak compile check; never shipped. It wraps the vanilla minimap's own mappin
// controllers to inventory, in-game, what the vanilla minimap draws and whether script can read it, and adds widget
// probes (tree/visibility/palette/mask) driven by the Soak_Mm* commands in SystemBody.inc. The findings become the
// parity checklist in docs/superpowers/specs/2026-11-02-corner-minimap-spike/FINDINGS.md.

// A session-lived registry the controller wraps push the latest sample into, keyed by concrete controller class and
// instance. Counts are "distinct instances seen since the last mm_reset"; a scenario resets, waits, then reads.
public class NMMinimapSpikeReg extends ScriptableService {
    private let recClass: array<CName>;
    private let recInst: array<wref<IScriptable>>;
    private let recLine: array<String>;
    // Palette probes: hidden rectangles bound to MainColors.* slots, read back one or more frames later.
    public let probe: array<wref<inkWidget>>;
    public let probeSlot: array<CName>;
    // The live vanilla minimap container (a HUD game controller, not a widget controller), stashed from OnPlayerAttach.
    public let container: wref<MinimapContainerController>;

    public static func Get() -> ref<NMMinimapSpikeReg> {
        return GameInstance.GetScriptableServiceContainer().GetService(n"NightMap.NMMinimapSpikeReg") as NMMinimapSpikeReg;
    }

    public func Reset() {
        ArrayClear(this.recClass);
        ArrayClear(this.recInst);
        ArrayClear(this.recLine);
    }

    // Upsert the sample for one controller instance.
    public func Record(cls: CName, inst: wref<IScriptable>, line: String) {
        let i = 0;
        while i < ArraySize(this.recInst) {
            if Equals(this.recInst[i], inst) {
                this.recLine[i] = line;
                return;
            }
            i += 1;
        }
        ArrayPush(this.recClass, cls);
        ArrayPush(this.recInst, inst);
        ArrayPush(this.recLine, line);
    }

    public func Size() -> Int32 { return ArraySize(this.recInst); }

    // Per-class counts, as "Class=N" tokens joined by spaces; also the first sample line for each class, dumped.
    public func Dump(dump: ref<NMSoakDump>) -> String {
        let seen: array<CName>;
        let count: array<Int32>;
        let i = 0;
        while i < ArraySize(this.recClass) {
            let c = this.recClass[i];
            let k = 0;
            let found = false;
            while k < ArraySize(seen) {
                if Equals(seen[k], c) { count[k] += 1; found = true; }
                k += 1;
            }
            if !found {
                ArrayPush(seen, c);
                ArrayPush(count, 1);
                dump.Line("ctrl|" + NameToString(c) + "|" + this.recLine[i]);
            }
            i += 1;
        }
        let summary = "";
        let j = 0;
        while j < ArraySize(seen) {
            summary += NameToString(seen[j]) + "=" + IntToString(count[j]) + " ";
            j += 1;
        }
        return summary;
    }

    // Dump every stealth-class sample line (one hostile NPC each).
    public func DumpStealth(dump: ref<NMSoakDump>) -> Int32 {
        let n = 0;
        let i = 0;
        while i < ArraySize(this.recClass) {
            if Equals(this.recClass[i], n"MinimapStealthMappinController") {
                dump.Line("stealth|" + this.recLine[i]);
                n += 1;
            }
            i += 1;
        }
        return n;
    }
}

// Widget-side probes (tree, visibility chain, palette read-back, circular mask), called from the Soak_Mm* methods in
// SystemBody.inc, which pass the HUD window.
public abstract class NMMinimapSpike {
    public static func VecS(v: Vector4) -> String {
        return FloatToStringPrec(v.X, 1) + "," + FloatToStringPrec(v.Y, 1) + "," + FloatToStringPrec(v.Z, 1);
    }

    public static func ColS(c: HDRColor) -> String {
        return FloatToStringPrec(c.Red, 3) + "," + FloatToStringPrec(c.Green, 3) + "," + FloatToStringPrec(c.Blue, 3)
            + "," + FloatToStringPrec(c.Alpha, 3);
    }

    // Absolute box of a widget in window units: top-left and size, via WidgetUtils.LocalToGlobal.
    public static func BoxS(w: wref<inkWidget>) -> String {
        let tl = WidgetUtils.LocalToGlobal(w, new Vector2(0.0, 0.0));
        let br = WidgetUtils.LocalToGlobal(w, w.GetSize());
        return FloatToStringPrec(tl.X, 1) + "," + FloatToStringPrec(tl.Y, 1) + " "
            + FloatToStringPrec(br.X - tl.X, 1) + "x" + FloatToStringPrec(br.Y - tl.Y, 1);
    }

    // The controller class CName on a widget, or "-".
    public static func CtrlName(w: wref<inkWidget>) -> String {
        let c = w.GetController();
        if IsDefined(c) { return NameToString(c.GetClassName()); }
        return "-";
    }

    // The vanilla minimap's root widget, via the stashed container (null until OnPlayerAttach has run).
    public static func MinimapRoot() -> wref<inkWidget> {
        let reg = NMMinimapSpikeReg.Get();
        if !IsDefined(reg) || !IsDefined(reg.container) { return null; }
        return reg.container.NMSpikeRoot();
    }

    public static func Walk(w: wref<inkWidget>, depth: Int32, max: Int32, dump: ref<NMSoakDump>) {
        let pad = "";
        let k = 0;
        while k < depth { pad += "  "; k += 1; }
        dump.Line(pad + NameToString(w.GetName()) + " [" + NameToString(w.GetClassName()) + "] ctrl=" + NMMinimapSpike.CtrlName(w)
            + " box=" + NMMinimapSpike.BoxS(w) + " vis=" + (w.IsVisible() ? "1" : "0") + " op=" + FloatToStringPrec(w.GetOpacity(), 2));
        if depth >= max { return; }
        let comp = w as inkCompoundWidget;
        if IsDefined(comp) {
            let i = 0;
            while i < comp.GetNumChildren() {
                NMMinimapSpike.Walk(comp.GetWidget(i), depth + 1, max, dump);
                i += 1;
            }
        }
    }

    // mm_tree: the minimap subtree (or the whole window if the container has not attached yet), to `max` depth.
    public static func Tree(window: wref<inkCompoundWidget>, max: Int32) -> String {
        if !IsDefined(window) { return "no window"; }
        let dump = NMSoakDump.Open("mm_tree.txt");
        let mini = NMMinimapSpike.MinimapRoot();
        if IsDefined(mini) {
            dump.Line("# minimap subtree");
            NMMinimapSpike.Walk(mini, 0, max, dump);
            dump.Flush();
            return "minimap box=" + NMMinimapSpike.BoxS(mini) + " vis=" + (mini.IsVisible() ? "1" : "0");
        }
        dump.Line("# container not attached yet; whole HUD window");
        NMMinimapSpike.Walk(window, 0, max, dump);
        dump.Flush();
        return "container not attached|window children " + IntToString(window.GetNumChildren());
    }

    // mm_vis: the visibility/opacity chain from the minimap widget up to the window root.
    public static func Vis(window: wref<inkCompoundWidget>) -> String {
        let mini = NMMinimapSpike.MinimapRoot();
        if !IsDefined(mini) { return "container not attached"; }
        let dump = NMSoakDump.Open("mm_vis.txt");
        let w: wref<inkWidget> = mini;
        let line = "";
        let n = 0;
        while IsDefined(w) && n < 24 {
            dump.Line(NameToString(w.GetName()) + " [" + NameToString(w.GetClassName()) + "] vis=" + (w.IsVisible() ? "1" : "0")
                + " op=" + FloatToStringPrec(w.GetOpacity(), 2) + " ctrl=" + NMMinimapSpike.CtrlName(w));
            line += (w.IsVisible() ? "1" : "0") + NameToString(w.GetName()) + " ";
            w = w.GetParentWidget();
            n += 1;
        }
        dump.Flush();
        return "chain " + IntToString(n) + "|" + line;
    }

    // palette_probe: create hidden rectangles bound to MainColors.* slots; read them back with palette_read.
    public static func PaletteProbe(window: wref<inkCompoundWidget>) -> String {
        if !IsDefined(window) { return "no window"; }
        let reg = NMMinimapSpikeReg.Get();
        if !IsDefined(reg) { return "no reg"; }
        ArrayClear(reg.probe);
        ArrayClear(reg.probeSlot);
        let slots = [n"MainColors.Blue", n"MainColors.Yellow", n"MainColors.Red", n"MainColors.White",
            n"MainColors.EnemyMinimapBase", n"MainColors.DarkBlue", n"MainColors.Neutral", n"MainColors.ActiveBlue",
            n"MainColors.PanelDarkBlue", n"MainColors.PanelBlack", n"MainColors.MildBlue", n"MainColors.SupBlue",
            n"MainColors.ActiveGreen", n"MainColors.FastTravel", n"MainColors.RelicColor"];
        for slot in slots {
            let r = new inkRectangle();
            r.SetSize(new Vector2(2.0, 2.0));
            r.SetOpacity(0.0);
            r.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
            r.BindProperty(n"tintColor", slot);
            r.Reparent(window);
            ArrayPush(reg.probe, r);
            ArrayPush(reg.probeSlot, slot);
        }
        return "created " + IntToString(ArraySize(slots));
    }

    public static func PaletteRead() -> String {
        let reg = NMMinimapSpikeReg.Get();
        if !IsDefined(reg) { return "no reg"; }
        if ArraySize(reg.probe) == 0 { return "no probes"; }
        let dump = NMSoakDump.Open("palette.txt");
        let i = 0;
        while i < ArraySize(reg.probe) {
            let w = reg.probe[i];
            let shape = w as inkRectangle;
            let col = IsDefined(shape) ? shape.GetTintColor() : new HDRColor(0.0, 0.0, 0.0, 0.0);
            dump.Line(NameToString(reg.probeSlot[i]) + "|" + NMMinimapSpike.ColS(col));
            i += 1;
        }
        dump.Flush();
        // Summarise the first slot so the one-line answer shows a non-zero read when it works.
        let first = reg.probe[0] as inkRectangle;
        return "read " + IntToString(ArraySize(reg.probe)) + "|Blue=" + (IsDefined(first) ? NMMinimapSpike.ColS(first.GetTintColor()) : "-");
    }
}

// ---- controller wraps: inventory what the vanilla minimap draws ----

// Fires polymorphically for every BaseMinimapMappinController whose Update() calls super.Update() (device, quest area,
// security area, POI, stub, prevention vehicle, ...). this.GetClassName() reports the concrete class.
@wrapMethod(BaseMinimapMappinController)
protected func Update() -> Void {
    wrappedMethod();
    let reg = NMMinimapSpikeReg.Get();
    if !IsDefined(reg) { return; }
    let m = this.GetMappin();
    let pos = IsDefined(m) ? this.VecOf(m) : "-";
    let variant = IsDefined(m) ? ToString(m.GetVariant()) : "-";
    let line = variant + "|pos " + pos + "|clamped " + (this.IsClamped() ? "1" : "0")
        + "|vert " + ToString(this.GetVerticalRelationToPlayer()) + "|dist " + FloatToStringPrec(this.GetDistanceToPlayer(), 1)
        + "|tracked " + (this.IsTracked() ? "1" : "0");
    reg.Record(this.GetClassName(), this, line);
}

// A helper added to the class so the wrap can read the mappin position in-class scope.
@addMethod(BaseMinimapMappinController)
protected func VecOf(m: wref<IMappin>) -> String {
    return NMMinimapSpike.VecS(m.GetWorldPosition());
}

// Hostile NPC mappins: dot + vision cone + detection state. The cone geometry and detection come from the public
// StealthMappin API; the controller's own state fields confirm colour and visibility decisions.
@wrapMethod(MinimapStealthMappinController)
protected func Update() -> Void {
    wrappedMethod();
    let reg = NMMinimapSpikeReg.Get();
    if !IsDefined(reg) { return; }
    reg.Record(n"MinimapStealthMappinController", this, this.NMSpikeLine());
}

@addMethod(MinimapStealthMappinController)
protected func NMSpikeLine() -> String {
    let sm = this.m_stealthMappin;
    let core = "mappinState " + NameToString(this.m_mappinState) + "|preventionState " + NameToString(this.m_preventionState)
        + "|coneColor " + NameToString(this.m_preventionVisionConeColor) + "|showCone " + (this.m_shouldShowVisionCone ? "1" : "0")
        + "|detAbove0 " + (this.m_detectionAboveZero ? "1" : "0") + "|clamped " + (this.IsClamped() ? "1" : "0");
    if !IsDefined(sm) { return core + "|stealthMappin -"; }
    let go = sm.GetGameObject();
    let cone = sm.GetSenseCone();
    return core
        + "|pos " + (IsDefined(go) ? NMMinimapSpike.VecS(go.GetWorldPosition()) : "-")
        + "|attitude " + ToString(sm.GetAttitudeTowardsPlayer())
        + "|highLevel " + ToString(sm.GetHighLevelState())
        + "|awareness " + ToString(sm.GetStealthAwarenessState())
        + "|canSee " + (sm.CanSeePlayer() ? "1" : "0")
        + "|aggressive " + (sm.IsAggressive() ? "1" : "0")
        + "|squadCombat " + (sm.IsSquadInCombat() ? "1" : "0")
        + "|detection " + FloatToStringPrec(sm.GetDetectionProgress(), 2)
        + "|coneLen " + FloatToStringPrec(cone.length, 1)
        + "|coneWidth " + FloatToStringPrec(cone.width, 1)
        + "|coneDeg " + FloatToStringPrec(cone.angleDegrees, 1)
        + "|conePos1 " + NMMinimapSpike.VecS(cone.position1)
        + "|conePos2 " + NMMinimapSpike.VecS(cone.position2);
}

// mm_zone: read the security-zone label, type and vignette, which live INSIDE the minimap container widget, plus the
// location/district text. Added to MinimapContainerController so the fields are in reach; called via Soak_MmZone.
// Stash the live container so the widget probes can reach its root widget and its zone fields. Chains with the
// MinimapContainerController wraps in Vanilla/Gps.reds.
@wrapMethod(MinimapContainerController)
protected cb func OnPlayerAttach(player: ref<GameObject>) -> Bool {
    let r = wrappedMethod(player);
    let reg = NMMinimapSpikeReg.Get();
    if IsDefined(reg) { reg.container = this; }
    return r;
}

@addMethod(MinimapContainerController)
public func NMSpikeRoot() -> wref<inkWidget> {
    return this.GetRootWidget();
}

@addMethod(MinimapContainerController)
public func NMSpikeZone() -> String {
    return "zoneType " + ToString(this.m_currentZoneType)
        + "|inPublicOrRestricted " + (this.m_inPublicOrRestrictedZone ? "1" : "0")
        + "|securityText '" + inkTextRef.GetText(this.m_securityAreaText) + "'"
        + "|vignetteValid " + (inkWidgetRef.IsValid(this.m_securityAreaVignetteWidget) ? "1" : "0")
        + "|vignetteOpacity " + FloatToStringPrec(inkWidgetRef.IsValid(this.m_securityAreaVignetteWidget) ? inkWidgetRef.GetOpacity(this.m_securityAreaVignetteWidget) : -1.0, 2)
        + "|locationText '" + inkTextRef.GetText(this.m_locationTextWidget) + "'"
        + "|combatHighlightValid " + (inkWidgetRef.IsValid(this.m_combatModeHighlight) ? "1" : "0");
}

// Security / restricted / hostile zones: the area shape and its type-state (the label text comes from mm_zone).
@wrapMethod(MinimapSecurityAreaMappinController)
protected func Update() -> Void {
    wrappedMethod();
    let reg = NMMinimapSpikeReg.Get();
    if !IsDefined(reg) { return; }
    let m = this.GetMappin();
    let line = "area|playerInArea " + (this.playerInArea ? "1" : "0")
        + "|hasShape " + (inkWidgetRef.IsValid(this.areaShapeWidget) ? "1" : "0")
        + (IsDefined(m) ? "|pos " + NMMinimapSpike.VecS(m.GetWorldPosition()) : "");
    reg.Record(n"MinimapSecurityAreaMappinController", this, line);
}
