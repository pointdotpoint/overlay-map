module OverlayMap

// What the vanilla minimap shows around its map (FINDINGS #5-#9): the security-zone label and vignette state, combat,
// autodrive and the courier countdown. Read from the container controller, which keeps updating at opacity 0.
public class NMZoneInfo {
    public let state: CName;   // vignette state: Safe / Default / Dangerous / Combat; n"" = none
    public let label: String;  // localized zone text when vanilla shows it, else ""
    public let combat: Bool;
    public let autodrive: Bool;
    public let timer: String;  // courier countdown text while active, else ""

    public func Key() -> String {
        return NameToString(this.state) + "|" + this.label + "|" + (this.autodrive ? "1" : "0") + "|" + this.timer;
    }
}

@addMethod(MinimapContainerController)
public func NMZone() -> ref<NMZoneInfo> {
    let z = new NMZoneInfo();
    z.combat = this.m_playerInCombat;
    z.autodrive = this.m_autoDriveEnabled;
    if z.combat {
        z.state = n"Combat";
        z.label = GetLocalizedTextByKey(n"Story-base-gameplay-gui-widgets-minimap-zones-Combat");
    } else {
        if NotEquals(this.m_currentZoneType, ESecurityAreaType.DISABLED) {
            z.state = this.ZoneToState(this.m_currentZoneType);
        }
        if !this.m_inPublicOrRestrictedZone && inkWidgetRef.IsVisible(this.m_securityAreaText) {
            z.label = GetLocalizedTextByKey(this.ZoneToTextKey(this.m_currentZoneType));
        }
    }
    if inkWidgetRef.IsVisible(this.m_courierTimerContainer) {
        z.timer = inkTextRef.GetText(this.m_courierTimerText);
    }
    return z;
}
