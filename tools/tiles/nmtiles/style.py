"""Default theme for the colourless mask tile sets, used only by the build previews (spec 11.6).

The runtime takes its colours from NMTheme; tiles are white masks with alpha = coverage, except the lit buildings
(bfill), whose grey RGB is a brightness the tint multiplies.
"""
PREVIEW_BG = (8, 18, 26)                     # #08121a
# draw order, back to front: (rgb, alpha scale)
PREVIEW_SETS = {
    "glow":       ((0x4f, 0xe3, 0xff), 0.45),
    "bfill":      ((0x2f, 0x78, 0xbf), 0.90),
    "outline":    ((0x3a, 0x8f, 0xd0), 0.40),
    "road":       ((0x5c, 0xb1, 0xec), 0.90),
}
