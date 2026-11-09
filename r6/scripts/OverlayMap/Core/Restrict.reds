module OverlayMap

// While the map holds the keyboard on foot, V is stopped with the game's own gameplay restrictions (the way carrying a
// body or a phone call stops V) instead of the player state machine's UI input context, which also froze mouse-look.
// NoCameraControl is never applied, so the mouse still turns the camera. Every restriction is applied with our own
// instigator id, so Remove only lifts ours and leaves any a quest applied.
public abstract class NMRestrict {
    public static func Instigator() -> TweakDBID { return t"OverlayMap.MapOpen"; }

    // W A S D (movement), Space (jump), the wheel, Q, R and the mouse buttons (weapons, radial menus), F (interact),
    // Tab (scanner) and the phone.
    public static func Ids() -> array<TweakDBID> {
        return [
            t"GameplayRestriction.NoMovement",
            t"GameplayRestriction.NoJump",
            t"GameplayRestriction.NoWeapons",
            t"GameplayRestriction.NoRadialMenus",
            t"GameplayRestriction.NoWorldInteractions",
            t"GameplayRestriction.NoScanning",
            t"GameplayRestriction.NoPhone"
        ];
    }

    // Mouse only: V keeps walking and driving; the camera stays still (the mouse pans the map) and the mouse buttons and
    // wheel don't shoot, aim or switch weapons.
    public static func MouseIds() -> array<TweakDBID> {
        return [
            t"GameplayRestriction.NoCameraControl",
            t"GameplayRestriction.NoWeapons"
        ];
    }

    // How many were applied (a missing record is skipped).
    public static func Apply(player: wref<GameObject>) -> Int32 {
        return NMRestrict.ApplyIds(player, NMRestrict.Ids());
    }

    public static func ApplyIds(player: wref<GameObject>, ids: array<TweakDBID>) -> Int32 {
        if !IsDefined(player) {
            return 0;
        }
        let n = 0;
        for id in ids {
            if IsDefined(TweakDBInterface.GetStatusEffectRecord(id)) && StatusEffectHelper.ApplyStatusEffect(player, id, NMRestrict.Instigator()) {
                n += 1;
            }
        }
        return n;
    }

    public static func Remove(player: wref<GameObject>) {
        if !IsDefined(player) {
            return;
        }
        let ses = GameInstance.GetStatusEffectSystem(player.GetGame());
        let applied: array<ref<StatusEffect>>;
        ses.GetAppliedEffects(player.GetEntityID(), applied);
        for e in applied {
            if IsDefined(e) && e.GetInstigatorStaticDataID() == NMRestrict.Instigator() {
                ses.RemoveStatusEffect(player.GetEntityID(), e.GetRecord().GetID(), e.GetStackCount());
            }
        }
    }

    // Our restrictions currently on V.
    public static func Count(player: wref<GameObject>) -> Int32 {
        if !IsDefined(player) {
            return 0;
        }
        let applied: array<ref<StatusEffect>>;
        GameInstance.GetStatusEffectSystem(player.GetGame()).GetAppliedEffects(player.GetEntityID(), applied);
        let n = 0;
        for e in applied {
            if IsDefined(e) && e.GetInstigatorStaticDataID() == NMRestrict.Instigator() {
                n += 1;
            }
        }
        return n;
    }
}

// The wheel zooms the map, but the game also gets it and tries to switch weapons, which NoWeapons blocks with a
// "You can't do that right now" notification. While the map holds V those notifications are dropped.
@wrapMethod(UIInGameNotificationQueue)
protected cb func OnUINotification(evt: ref<UIInGameNotificationEvent>) -> Bool {
    if IsDefined(evt) && Equals(evt.m_notificationType, UIInGameNotificationType.ActionRestriction) {
        let player = this.GetPlayerControlledObject();
        let sys = IsDefined(player) ? OverlayMapSystem.Get(player.GetGame()) : null;
        if IsDefined(sys) && sys.HoldsV() {
            return false;
        }
    }
    return wrappedMethod(evt);
}
