"""Source-level guards for the hologram settings (the in-game self-tests cannot run offline)."""
import re
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / "r6" / "scripts" / "NightMap"


def test_panel_opacity_default_is_see_through_and_matches_theme():
    settings = (SCRIPTS / "Core" / "Settings.reds").read_text()
    theme = (SCRIPTS / "Core" / "Theme.reds").read_text()
    assert re.search(r"public let panelOpacity: Float = 0\.45;", settings)
    assert re.search(r"func DefaultPanelOpacity\(\) -> Float \{ return 0\.45; \}", theme)


def _block(src: str, field: str) -> str:
    """The annotation block (everything since the previous field) that declares `field`."""
    head = src[:src.index(f"public let {field}:")]
    return head[head.rindex(";") + 1:]


def test_hologram_settings_live_under_display_with_the_right_defaults():
    s = (SCRIPTS / "Core" / "Settings.reds").read_text()
    assert "public let greenHologram: Bool = false;" in s and "public let hologramEffects: Bool = true;" in s
    for field, name in (("greenHologram", "Green hologram"), ("hologramEffects", "Hologram effects")):
        b = _block(s, field)
        assert '"ModSettings.category", "Display"' in b and f'"ModSettings.displayName", "{name}"' in b
