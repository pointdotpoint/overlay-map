"""Default theme for the colourless mask tile sets, used only by the build previews (spec 11.6).

The runtime takes its colours from NMTheme; tiles are white masks with alpha = coverage.
"""
PREVIEW_BG = (8, 18, 26)                     # #08121a
# draw order, back to front: (rgb, alpha scale)
PREVIEW_SETS = {
    "road":    ((0x1e, 0x8c, 0x96), 0.55),
    "bfill":   ((0x9f, 0xf3, 0xff), 0.12),
    "glow":    ((0x9f, 0xf3, 0xff), 0.35),
    "outline": ((0x9f, 0xf3, 0xff), 0.9),
}
