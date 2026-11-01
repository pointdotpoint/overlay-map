"""Source-level guards for the hologram settings (the in-game self-tests cannot run offline)."""
import re
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / "r6" / "scripts" / "NightMap"


def test_panel_opacity_default_is_nearly_opaque_and_matches_theme():
    settings = (SCRIPTS / "Core" / "Settings.reds").read_text()
    theme = (SCRIPTS / "Core" / "Theme.reds").read_text()
    assert re.search(r"public let panelOpacity: Float = 0\.92;", settings)
    assert re.search(r"func DefaultPanelOpacity\(\) -> Float \{ return 0\.92; \}", theme)


def _block(src: str, field: str) -> str:
    """The annotation block (everything since the previous field) that declares `field`."""
    head = src[:src.index(f"public let {field}:")]
    return head[head.rindex(";") + 1:]


def test_hologram_settings_live_under_display_with_the_right_defaults():
    s = (SCRIPTS / "Core" / "Settings.reds").read_text()
    assert "public let holoColor: NightMapHoloColor = NightMapHoloColor.Cyan;" in s
    assert "public let hologramEffects: Bool = true;" in s and "greenHologram" not in s
    assert re.search(r"enum NightMapHoloColor \{\s*Cyan = 0,\s*Green = 1\s*\}", s)
    for field, name in (("holoColor", "Hologram colour"), ("hologramEffects", "Hologram effects")):
        b = _block(s, field)
        assert '"ModSettings.category", "Display"' in b and f'"ModSettings.displayName", "{name}"' in b
    b = _block(s, "holoColor")
    assert '"ModSettings.displayValues.Cyan", "Cyan"' in b and '"ModSettings.displayValues.Green", "Green"' in b
    system = (SCRIPTS / "Core" / "NightMapSystem.reds").read_text()
    assert "NMTheme.ThemeIndex(s.holoColor)" in system
