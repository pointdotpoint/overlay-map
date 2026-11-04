module OverlayMap

// Every item that reaches V's inventory is offered to the collectible seen list (a cheap set lookup).
@wrapMethod(PlayerPuppet)
protected cb func OnItemAddedToInventory(evt: ref<ItemAddedEvent>) -> Bool {
    let r = wrappedMethod(evt);
    let sys = OverlayMapSystem.Get(this.GetGame());
    if IsDefined(sys) {
        sys.NoteItem(ItemID.GetTDBID(evt.itemID));
    }
    return r;
}
