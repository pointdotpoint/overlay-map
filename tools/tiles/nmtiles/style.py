"""Hologram palette for baked map tiles (straight alpha RGBA). Order = back to front."""
STYLE = {
    "land":        {"order": 0, "fill": (40, 200, 255, 13)},
    "water":       {"order": 1, "fill": (40, 200, 255, 33)},
    "cliff":       {"order": 2, "fill": (80, 220, 255, 22)},
    "road":        {"order": 3, "fill": (80, 220, 255, 51)},
    "building":    {"order": 4, "fill": (80, 220, 255, 15), "outline": (120, 235, 255, 115), "height_alpha": 30},
    "road_border": {"order": 5, "fill": (120, 235, 255, 217), "glow": (120, 235, 255, 90)},
    "metro":       {"order": 6, "fill": (255, 79, 216, 200)},
}
