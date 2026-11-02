module NightMap

// Copies each vanilla minimap marker into the NMMinimapMirror after its controller has decided how to draw it.
// Only while a NightMap view is live (mirror.live); otherwise one system lookup per call and out.
public abstract class NMMinimapWraps {
    public static func Mirror() -> ref<NMMinimapMirror> {
        let sys = NightMapSystem.Get(GetGameInstance());
        return IsDefined(sys) ? sys.Mirror() : null;
    }

    // -1: not copied (remote players: multiplayer only). Shadow: quest / POI markers and police stubs / vehicles already
    // come from the world-map mirroring (NMVanilla); only their rim clamp and above / below arrow are taken from here.
    public static func KindOf(cls: CName) -> Int32 {
        if Equals(cls, n"MinimapStealthMappinController") { return EnumInt(NMMiniKind.Enemy); }
        if Equals(cls, n"MinimapDeviceMappinController") { return EnumInt(NMMiniKind.Device); }
        if Equals(cls, n"RoadBlockadeMappinController") { return EnumInt(NMMiniKind.Police); }
        if Equals(cls, n"MinimapQuestAreaMappinController") { return EnumInt(NMMiniKind.Area); }
        if Equals(cls, n"MinimapSecurityAreaMappinController") { return EnumInt(NMMiniKind.Zone); }
        if Equals(cls, n"MinimapQuestMappinController") || Equals(cls, n"MinimapPOIMappinController")
            || Equals(cls, n"MinimapStubMappinController") || Equals(cls, n"MinimapPreventionVehicleMappinController") {
            return EnumInt(NMMiniKind.Shadow);
        }
        if Equals(cls, n"MinimapRemotePlayerMappinController") { return -1; }
        return EnumInt(NMMiniKind.Other);   // ping, dynamic events, and anything added later
    }

    public static func Vertical(v: gamemappinsVerticalPositioning) -> Int32 {
        if Equals(v, gamemappinsVerticalPositioning.Above) { return 1; }
        if Equals(v, gamemappinsVerticalPositioning.Below) { return -1; }
        return 0;
    }
}

@wrapMethod(BaseMinimapMappinController)
protected func Update() -> Void {
    wrappedMethod();
    let mirror = NMMinimapWraps.Mirror();
    if !IsDefined(mirror) || !mirror.live { return; }
    let cls = this.GetClassName();
    let kind = NMMinimapWraps.KindOf(cls);
    if kind < 0 { return; }
    let m = this.GetMappin();
    if !IsDefined(m) { return; }
    let id = m.GetNewMappinID();
    if id.value == 0ul { return; }
    let e = mirror.Upsert(id.value);
    if !Equals(e.cls, cls) {
        e.cls = cls;
        e.kind = IntEnum<NMMiniKind>(kind);
    }
    e.mappin = m;
    e.root = this.GetRootWidget();
    e.icon = inkImageRef.Get(this.iconWidget) as inkImage;
    e.tracked = this.IsTracked();
    e.clamped = this.IsClamped();
    e.clampable = this.ShouldClamp();
    e.vertical = NMMinimapWraps.Vertical(this.GetVerticalRelationToPlayer());
}

// Hostile NPCs, cameras, turrets, loot: the NPC itself (position, facing), the vision cone and its sense-cone length.
@wrapMethod(MinimapStealthMappinController)
protected func Update() -> Void {
    wrappedMethod();
    let mirror = NMMinimapWraps.Mirror();
    if !IsDefined(mirror) || !mirror.live { return; }
    let m = this.GetMappin();
    if !IsDefined(m) { return; }
    let e = mirror.Find(m.GetNewMappinID().value);
    if !IsDefined(e) { return; }
    let sm = this.m_stealthMappin;
    if IsDefined(sm) {
        e.obj = sm.GetGameObject();
        e.coneLen = sm.GetSenseCone().length;
    }
    e.cone = inkImageRef.Get(this.visionConeWidget) as inkImage;
    if this.m_isPrevention {
        e.kind = NMMiniKind.Police;
    } else if this.m_isDevice {
        e.kind = NMMiniKind.Device;
    } else {
        e.kind = NMMiniKind.Enemy;
    }
}

// Cameras, turrets and other devices: the effect area while targeted or tagged.
@wrapMethod(MinimapDeviceMappinController)
protected func Update() -> Void {
    wrappedMethod();
    let mirror = NMMinimapWraps.Mirror();
    if !IsDefined(mirror) || !mirror.live { return; }
    let m = this.GetMappin();
    if !IsDefined(m) { return; }
    let e = mirror.Find(m.GetNewMappinID().value);
    if !IsDefined(e) { return; }
    let d = this.GetVisualData();
    e.radius = IsDefined(d) && d.m_showOnMiniMap && (d.m_isCurrentTarget || d.m_isTagged) ? d.m_range : 0.0;
}
