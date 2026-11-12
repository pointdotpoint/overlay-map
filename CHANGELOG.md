# Changelog

## 1.0.1

### Added
- Shop pins show the shop's real name in the sidebar (Ginger Panda, El Coyote Cojo, Kraviz's Clinic). A shop
  without a name of its own shows the named area it stands in (Red Dirt, Jinguji), else its shopkeeper's name
  (Darius Clarke, Santiago Molina, Chiyo Omoto). All names come from the game's own data and follow the game's
  language; shops the game only labels "Food Vendor" or "Gun Vendor" keep their type.
- RESIDENCES filter view (NUM / cycles ALL → JOBS → SERVICES → RESIDENCES): V's Apartment (H10), Northside,
  Japantown, Glen and Corpo Plaza apartments, and the Dogtown Hideout, which the game itself doesn't mark.
- Residence pins name their apartment in the sidebar ("Northside Apartment").
- Controller: choose the open button in Mod Settings → Controller: Hold View, Hold Menu (replaces the game's
  hold-for-world-map) or LB + View.
- Vehicle pins name the vehicle under the title.
- Quest-only collectibles name the quest they belong to.
- Welcome screen on first run, with a suggestion to rebind the open key and pick a control mode.
- Mouse only control mode; Controls is now the first setting.
- Optional Shift/Ctrl modifier for the open key.
- Mouse panning while the map holds the keyboard, on by default; mouse-look keeps working while the map is open.
- Teleport on Q in the any-keyboard layout; holding to teleport shows a TELEPORTING bar.
- Map brightness, contrast and whole-map opacity settings.

### Changed
- Your apartment pins are drawn larger and win space over other pins.
- Apartments for rent and your apartments always show, in every filter view and at every zoom.
- Teleporting to a residence lands V at its door, out of the car (before, H10 put V on the roof).
- Smoother panning and zooming on dense parts of the map.

### Fixed
- DualSense with the game's native support: the Options button now works as View (hold to open, tap to pause).
- A controller can take over a map opened with the keyboard.
- Markers no longer vanish after a long pan.
- Fast travel no longer ends on a black screen.
- V is handed back only after the closing key is released.
- Hint labels and the scale bar follow the colour theme.
- Photo pins are kept without RedFileSystem, and the sidebar names the teleport key the map actually uses.

## 1.0.0 — 2026-11-07

First release.
