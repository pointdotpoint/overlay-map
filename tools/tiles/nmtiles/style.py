"""Hologram palette for baked map tiles (straight alpha RGBA). Order = back to front."""
STYLE = {
    "land":        {"order": 0, "fill": (40, 200, 255, 13)},
    "water":       {"order": 1, "fill": (40, 200, 255, 33)},
    "cliff":       {"order": 2, "fill": (80, 220, 255, 22)},
    "road":        {"order": 3, "fill": (80, 220, 255, 51)},
    "building":    {"order": 4, "fill": (80, 220, 255, 15), "outline": (120, 235, 255, 115), "height_alpha": 30},
    "road_border": {"order": 5, "fill": (120, 235, 255, 217), "glow": (120, 235, 255, 90)},
    "metro":       {"order": 6, "fill": (255, 79, 216, 200), "dash": (24.0, 16.0)},   # dash = (on, off) in world metres
}

# The base tile set (spec 11.5): land, water and cliffs/coast of the 3D map; roads, road borders and buildings are off.
BASE_STYLES = ("land", "water", "cliff")

# Preview-only defaults for the colourless mask sets (the runtime takes these from NMTheme): rgb, alpha scale.
PREVIEW_BG = (8, 18, 26)                     # #08121a
PREVIEW_SETS = {
    "base":   ((40, 200, 255), 1.0),
    "road":   ((0x1e, 0x8c, 0x96), 0.55),
    "glow":   ((0x9f, 0xf3, 0xff), 0.35),
    "stroke": ((0x9f, 0xf3, 0xff), 0.9),
    "metro":  ((255, 79, 216), 200 / 255),
}
