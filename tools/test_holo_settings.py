"""Source-level guards for the hologram settings (the in-game self-tests cannot run offline)."""
import re
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / "r6" / "scripts" / "OverlayMap"


def test_panel_opacity_default_is_half_and_matches_theme():
    settings = (SCRIPTS / "Core" / "Settings.reds").read_text()
    theme = (SCRIPTS / "Core" / "Theme.reds").read_text()
    assert re.search(r"public let panelOpacity: Float = 0\.5;", settings)
    assert re.search(r"func DefaultPanelOpacity\(\) -> Float \{ return 0\.5; \}", theme)


def test_map_marker_size_lives_under_display_and_defaults_to_half():
    s = (SCRIPTS / "Core" / "Settings.reds").read_text()
    assert "public let markerSize: Float = 0.5;" in s
    b = _block(s, "markerSize")
    assert '"ModSettings.category", "Display"' in b and '"ModSettings.displayName", "Map marker size"' in b
    assert '"ModSettings.min", "0.25"' in b and '"ModSettings.max", "1.5"' in b and '"ModSettings.step", "0.05"' in b


def _block(src: str, field: str) -> str:
    """The annotation block (everything since the previous field) that declares `field`."""
    head = src[:src.index(f"public let {field}:")]
    return head[head.rindex(";") + 1:]


def test_hologram_settings_live_under_display_with_the_right_defaults():
    s = (SCRIPTS / "Core" / "Settings.reds").read_text()
    assert "public let holoColor: OverlayMapHoloColor = OverlayMapHoloColor.Cyan;" in s
    assert "public let hologramEffects: Bool = true;" in s and "greenHologram" not in s
    assert re.search(r"enum OverlayMapHoloColor \{\s*Cyan = 0,\s*Green = 1,\s*Red = 2,\s*Purple = 3,\s*Amber = 4\s*\}", s)
    for field, name in (("holoColor", "Hologram colour"), ("hologramEffects", "Hologram effects")):
        b = _block(s, field)
        assert '"ModSettings.category", "Display"' in b and f'"ModSettings.displayName", "{name}"' in b
    b = _block(s, "holoColor")
    for v in ("Cyan", "Green", "Red", "Purple", "Amber"):
        assert f'"ModSettings.displayValues.{v}", "{v}"' in b
    system = (SCRIPTS / "Core" / "OverlayMapSystem.reds").read_text()
    assert "NMTheme.ThemeIndex(s.holoColor)" in system


def test_vhs_settings_live_under_display_with_their_defaults():
    s = (SCRIPTS / "Core" / "Settings.reds").read_text()
    sliders = (
        ("scanlineStrength", "Scanline strength", "0.3", "0", "0.6", "0.02"),
        ("glowStrength", "Glow strength", "1.5", "0", "3", "0.1"),
    )
    for field, name, default, lo, hi, step in sliders:
        assert f"public let {field}: Float = {default};" in s
        b = _block(s, field)
        assert '"ModSettings.category", "Display"' in b and f'"ModSettings.displayName", "{name}"' in b
        assert f'"ModSettings.min", "{lo}"' in b and f'"ModSettings.max", "{hi}"' in b and f'"ModSettings.step", "{step}"' in b
    for field, name in (("vhsTracking", "VHS tracking band"), ("vhsGlitch", "VHS glitch")):
        assert f"public let {field}: Bool = true;" in s
        b = _block(s, field)
        assert '"ModSettings.category", "Display"' in b and f'"ModSettings.displayName", "{name}"' in b
    # Every knob is read into one config and handed to the panel and the layer stack.
    system = (SCRIPTS / "Core" / "OverlayMapSystem.reds").read_text()
    assert "NMHoloFx.From(s)" in system


def test_ncart_filter_is_a_map_filter_off_by_default():
    s = (SCRIPTS / "Core" / "Settings.reds").read_text()
    assert "public let filterNcart: Bool = false;" in s
    b = _block(s, "filterNcart")
    assert '"ModSettings.category", "Map filters"' in b and '"ModSettings.displayName", "NCART lines"' in b
    system = (SCRIPTS / "Core" / "OverlayMapSystem.reds").read_text()
    assert ".filterNcart)" in system      # handed to NMLayerStack.Create
