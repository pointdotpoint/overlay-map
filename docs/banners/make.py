"""Promo banner mockups for Overlay Map, built from the user's in-game screenshots.

Crops the map out of each theme's screenshot, writes one HTML page per banner in the map's own UI language
(corner brackets, key-cap chips, tracked caps, scanlines), and renders each with headless Chrome.
"""
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).parent
# Work files (crops, HTML, renders, Chrome profile) go to BANNER_OUT, default ./out; finished banners are copied here.
OUT = Path(os.environ.get("BANNER_OUT", ROOT / "out"))
ASSETS = OUT / "assets"
SHOTS = Path.home() / ".local/share/Steam/userdata/82605613/760/remote/1091500/screenshots"
K = 1.28  # the screenshots are 2560 wide; coordinates below are in 2000-wide space, as in the user's messages

BIG = (225, 170, 900)    # (unused x, top, bottom) of the map area: 90%-wide panel
SMALL = (0, 228, 842)    # same for the smaller panel

# name, colour, screenshot, top/bottom of the map, centre x of the crop (2000-space)
THEMES = [
    ("CYAN", "#63d8f2", "20261107204701_1.jpg", BIG, 1010),
    ("RED", "#ff6a8c", "20261108100107_1.jpg", SMALL, 730),
    ("GREEN", "#66f2a4", "20261108095710_1.jpg", SMALL, 800),
    ("PURPLE", "#c77bff", "20261108095143_1.jpg", BIG, 760),
    ("AMBER", "#ffc56e", "20261108095648_1.jpg", SMALL, 760),
]
BOUNDS = {BIG: (104, 1448), SMALL: (240, 1380)}


def crop(name: str, shot: str, band, cx: float, aspect: float, tag: str) -> str:
    """Map-only crop of the given width/height aspect, the full map height, centred on cx and kept inside the map."""
    im = Image.open(SHOTS / shot).convert("RGB")
    top, bottom = band[1], band[2]
    if tag == "strip":                   # a landscape crop takes a slice of the height, not all of it
        h = (bottom - top) * 0.62
        top = top + (bottom - top) * 0.2
        bottom = top + h
    w = (bottom - top) * aspect
    lo, hi = BOUNDS[band]
    x0 = min(max(cx - w / 2, lo), hi - w)
    box = tuple(round(v * K) for v in (x0, top, x0 + w, bottom))
    file = f"{name.lower()}_{tag}.jpg"
    im.crop(box).save(ASSETS / file, quality=96)
    return file


CSS = f"""
@font-face {{ font-family: R; font-weight: 700; src: url('{ROOT}/fonts/Rajdhani-Bold.ttf'); }}
@font-face {{ font-family: R; font-weight: 600; src: url('{ROOT}/fonts/Rajdhani-SemiBold.ttf'); }}
@font-face {{ font-family: R; font-weight: 500; src: url('{ROOT}/fonts/Rajdhani-Medium.ttf'); }}
* {{ box-sizing: border-box; margin: 0; }}
html, body {{ background: #050a11; overflow: hidden; font-family: R, sans-serif; color: #eaf6fb; }}
.stage {{ position: relative; overflow: hidden; }}
.abs {{ position: absolute; }}
.scan {{ position: absolute; inset: 0; pointer-events: none;
  background: repeating-linear-gradient(0deg, rgba(0,0,0,.20) 0 1px, transparent 1px 3px); }}
.dots {{ position: absolute; inset: 0;
  background-image: radial-gradient(rgba(120,200,235,.13) 1px, transparent 1.4px); background-size: 16px 16px; }}
.title {{ font-weight: 700; letter-spacing: .16em; line-height: 1; white-space: nowrap; }}
.sub {{ font-weight: 500; letter-spacing: .3em; white-space: nowrap; color: #9fc4d4; }}
.chip {{ display: inline-block; border: 1.5px solid var(--c); padding: .18em .7em .1em; font-weight: 600;
  letter-spacing: .16em; color: var(--c); background: rgba(6,18,28,.72); white-space: nowrap; }}
"""


def brackets(x, y, w, h, c, arm=46, t=3):
    """The corner brackets of the map panel, as a positioned SVG."""
    p = (f"M{x},{y+arm}V{y}H{x+arm} M{x+w-arm},{y}H{x+w}V{y+arm} "
         f"M{x+w},{y+h-arm}V{y+h}H{x+w-arm} M{x+arm},{y+h}H{x}V{y+h-arm}")
    return f'<path d="{p}" fill="none" stroke="{c}" stroke-width="{t}" style="filter:drop-shadow(0 0 7px {c})"/>'


def spectrum(x, y, w, h=4, gap=6):
    """The five theme colours as one segmented bar: the banners' shared signature."""
    seg = (w - gap * 4) / 5
    return "".join(f'<div class="abs" style="left:{x + i * (seg + gap)}px;top:{y}px;width:{seg}px;height:{h}px;'
                   f'background:{t[1]};box-shadow:0 0 12px {t[1]}"></div>' for i, t in enumerate(THEMES))


def page(name, w, h, body):
    f = OUT / f"{name}.html"
    f.write_text(f'<!doctype html><meta charset=utf-8><style>{CSS}</style>'
                 f'<div class="stage" style="width:{w}px;height:{h}px">{body}</div>')
    subprocess.run(["google-chrome-stable", "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
                    f"--user-data-dir={OUT}/.chrome", "--allow-file-access-from-files", "--force-device-scale-factor=1",
                    f"--window-size={w},{h}", "--virtual-time-budget=4000", f"--screenshot={OUT / (name + '.png')}",
                    f"file://{f}"], check=True, capture_output=True)


def columns(w, h, slant, tag, aspect, extra):
    """Five full-height columns with slanted dividers, in the user's order."""
    cw = w / 5
    out, lines = "", ""
    for i, (name, col, shot, band, cx) in enumerate(THEMES):
        img = crop(name, shot, band, cx, aspect, tag)
        l, r = cw * i, cw * (i + 1)
        tl, tr = (l + slant if i else -200), (r + slant if i < 4 else w + 200)
        bl, br = (l - slant if i else -200), (r - slant if i < 4 else w + 200)
        iw = h * aspect
        out += (f'<div class="abs" style="inset:0;clip-path:polygon({tl}px 0,{tr}px 0,{br}px {h}px,{bl}px {h}px)">'
                f'<img src="{ASSETS / img}" class="abs" style="left:{(l + r) / 2 - iw / 2}px;top:0;width:{iw}px;height:{h}px;'
                f'object-fit:cover"></div>')
        if i:
            lines += (f'<line x1="{l + slant}" y1="0" x2="{l - slant}" y2="{h}" stroke="#05090f" stroke-width="9"/>'
                      f'<line x1="{l + slant}" y1="0" x2="{l - slant}" y2="{h}" stroke="#dff6ff" stroke-width="1.5" '
                      f'style="filter:drop-shadow(0 0 6px #bfefff)"/>')
    return out + f'<svg class="abs" style="inset:0" width="{w}" height="{h}">{lines}</svg>' + extra


def themes_1080():
    w, h, slant = 1920, 1080, 42
    labels = ""
    for i, t in enumerate(THEMES):
        cx = w / 5 * (i + .5) - slant * .62
        labels += (f'<div class="abs" style="left:{cx - 150}px;width:300px;top:944px;text-align:center;--c:{t[1]}">'
                   f'<div style="font:500 20px R;letter-spacing:.34em;color:#cfe3ec">THEME 0{i + 1}</div>'
                   f'<div style="font:700 58px R;letter-spacing:.16em;line-height:1.1;color:{t[1]};'
                   f'text-shadow:0 0 22px {t[1]}">{t[0]}</div></div>')
    extra = (f'<div class="abs" style="inset:0;background:linear-gradient(180deg,rgba(4,9,15,.96) 0,rgba(4,9,15,.84) 15%,'
             f'rgba(4,9,15,0) 33%,rgba(4,9,15,0) 72%,rgba(4,9,15,.94) 90%)"></div>'
             f'<div class="scan"></div>'
             f'<div class="abs title" style="left:0;right:0;top:52px;text-align:center;font-size:124px;'
             f'text-shadow:0 0 30px rgba(120,225,255,.6)">OVERLAY MAP</div>'
             + spectrum(660, 228, 600) + labels +
             f'<svg class="abs" style="inset:0" width="{w}" height="{h}">{brackets(24, 24, w - 48, h - 48, "#eaf6fb")}</svg>')
    page("1_themes_1920x1080", w, h, columns(w, h, slant, "tall", (w / 5 + 150) / h, extra))


def themes_strip():
    w, h, slant = 1920, 480, 30
    labels = ""
    for i, t in enumerate(THEMES):
        cx = w / 5 * (i + .5) - slant * .55
        labels += (f'<div class="abs" style="left:{cx - 120}px;width:240px;top:424px;text-align:center;'
                   f'font:700 28px R;letter-spacing:.24em;color:{t[1]};text-shadow:0 0 14px {t[1]},0 0 3px #000">{t[0]}</div>')
    panel_w, panel_h, x, y = 820, 190, 550, 128
    extra = (f'<div class="abs" style="inset:0;background:linear-gradient(180deg,rgba(4,9,15,.1) 60%,rgba(4,9,15,.92) 92%)"></div>'
             f'<div class="scan"></div>'
             f'<div class="abs" style="left:{x}px;top:{y}px;width:{panel_w}px;height:{panel_h}px;background:rgba(5,12,20,.86);'
             f'backdrop-filter:blur(7px)"></div>'
             f'<div class="abs title" style="left:{x}px;width:{panel_w}px;top:{y + 30}px;text-align:center;font-size:88px;'
             f'text-shadow:0 0 22px rgba(120,225,255,.55)">OVERLAY MAP</div>'
             f'<div class="abs sub" style="left:{x}px;width:{panel_w}px;top:{y + 124}px;text-align:center;font-size:20px">'
             f'HOLOGRAM WORLD MAP FOR CYBERPUNK 2077</div>' + labels +
             f'<svg class="abs" style="inset:0" width="{w}" height="{h}">'
             f'{brackets(x, y, panel_w, panel_h, "#eaf6fb", 30, 2.5)}</svg>')
    page("2_themes_strip_1920x480", w, h, columns(w, h, slant, "strip", (w / 5 + 110) / h, extra))


PANEL = "M97,135 Q1000,178 1903,135 L1903,990 Q1000,950 97,990 Z"


def cut_panel(shot):
    """The curved panel from a screenshot, cut away from the game world, in a 2000 x 1125 box."""
    return (f'<div class="abs" style="left:0;top:0;width:2000px;height:1125px;clip-path:path(\'{PANEL}\')">'
            f'<img src="{SHOTS / shot}" style="width:2000px;height:1125px;display:block"></div>')


def hero():
    w, h = 1920, 1080
    c = THEMES[0][1]
    chips = ["OPENS OVER GAMEPLAY", "VANILLA MARKERS", "GPS ROUTES", "WAYPOINTS", "FAST TRAVEL", "PHOTO PINS"]
    chip_html = "".join(f'<div class="chip" style="font-size:21px;margin:0 10px 13px 0;--c:{c}">{t}</div>' for t in chips)
    s = .84
    body = (f'<div class="dots"></div>'
            f'<div class="abs" style="left:520px;top:-120px;width:1500px;height:1320px;'
            f'background:radial-gradient(closest-side,rgba(40,140,200,.34),transparent)"></div>'
            f'<div class="abs" style="left:690px;top:-22px;width:0;height:0;perspective:1700px;perspective-origin:600px 562px">'
            f'<div style="width:2000px;height:1125px;transform-origin:0 50%;'
            f'transform:rotateY(-21deg) rotateX(3deg) scale({s});filter:drop-shadow(0 0 26px rgba(90,210,255,.75))">'
            f'{cut_panel(THEMES[0][2])}</div></div>'
            f'<div class="abs" style="inset:0;background:linear-gradient(90deg,#050a11 0,#050a11 30%,rgba(5,10,17,.7) 36%,transparent 42%)"></div>'
            f'<div class="scan" style="opacity:.55"></div>'
            f'<div class="abs title" style="left:90px;top:292px;font-size:122px;line-height:.92;'
            f'text-shadow:0 0 30px rgba(120,225,255,.6)">OVERLAY<br>MAP</div>'
            f'<div class="abs" style="left:92px;top:536px;font:500 31px/1.28 R;letter-spacing:.05em;color:#cfe3ec;width:610px">'
            f'Built to be lightweight, so you can use it<br>without pausing your gameplay.</div>'
            + spectrum(92, 636, 470, 5, 8) +
            f'<div class="abs" style="left:92px;top:676px;width:600px">{chip_html}</div>'
            f'<svg class="abs" style="inset:0" width="{w}" height="{h}">{brackets(24, 24, w - 48, h - 48, c)}</svg>')
    page("3_hero_1920x1080", w, h, body)


def callouts():
    w, h = 1920, 1080
    c = THEMES[0][1]
    s, ox, oy = .78, 180, 104
    # label centre x, row (0 top, 1 bottom), target in 2000-space, heading, detail
    items = [
        (350, 0, (225, 183), "AREA NAMES", "under your cursor"),
        (720, 0, (653, 338), "VANILLA ICONS", "the game's own markers"),
        (1090, 0, (1132, 395), "GPS ROUTES", "mirrors your navigation"),
        (1560, 0, (1810, 186), "PHOTO PINS", "snapshots on the map"),
        (330, 1, (170, 970), "PAN + ZOOM", "keyboard, mouse or pad"),
        (690, 1, (606, 950), "WAYPOINTS", "set one anywhere"),
        (1480, 1, (1688, 807), "QUEST TRACKING", "always in view"),
    ]
    svg, labels = "", ""
    for lx, row, (tx, ty), head, sub in items:
        px, py = ox + tx * s, oy + ty * s
        ly, turn, top = (126, 168, 60) if row == 0 else (938, 908, 946)
        svg += (f'<polyline points="{lx},{ly} {lx},{turn} {px},{turn} {px},{py}" fill="none" stroke="#fff" stroke-width="1.6" '
                f'style="filter:drop-shadow(0 0 4px {c})"/>'
                f'<circle cx="{px}" cy="{py}" r="6" fill="#06121c" stroke="#fff" stroke-width="2"/>'
                f'<circle cx="{px}" cy="{py}" r="2" fill="#fff"/>')
        labels += (f'<div class="abs" style="left:{lx - 200}px;width:400px;top:{top}px;text-align:center">'
                   f'<div style="font:700 33px/1 R;letter-spacing:.14em;color:{c};text-shadow:0 0 14px {c}">{head}</div>'
                   f'<div style="font:500 21px/1.25 R;letter-spacing:.06em;color:#cfe3ec">{sub}</div></div>')
    labels += (f'<div class="abs title" style="left:875px;width:400px;top:950px;text-align:center;font-size:42px;'
               f'text-shadow:0 0 16px rgba(120,225,255,.6)">OVERLAY MAP</div>' + spectrum(965, 1000, 220, 3, 4))
    body = (f'<div class="dots"></div>'
            f'<div class="abs" style="left:{ox}px;top:{oy}px;width:0;height:0">'
            f'<div style="width:2000px;height:1125px;transform-origin:0 0;transform:scale({s});'
            f'filter:drop-shadow(0 0 20px rgba(90,210,255,.65))">{cut_panel(THEMES[0][2])}</div></div>'
            f'<svg class="abs" style="inset:0" width="{w}" height="{h}">{svg}</svg>{labels}')
    page("4_features_1920x1080", w, h, body)


def thumb():
    """The hero for the Nexus thumbnail: the card shows it ~430 px wide (x0.22), so the text is 1.5-2.5x the hero's."""
    w, h = 1920, 1080
    c = THEMES[0][1]
    chips = ["OPENS OVER GAMEPLAY", "VANILLA MARKERS"]
    chip_html = "".join(f'<div class="chip" style="font-size:44px;border-width:3px;margin:0 0 22px 0;--c:{c}">{t}</div><br>'
                        for t in chips)
    s = .84
    body = (f'<div class="dots"></div>'
            f'<div class="abs" style="left:720px;top:-120px;width:1500px;height:1320px;'
            f'background:radial-gradient(closest-side,rgba(40,140,200,.34),transparent)"></div>'
            f'<div class="abs" style="left:930px;top:-22px;width:0;height:0;perspective:1700px;perspective-origin:600px 562px">'
            f'<div style="width:2000px;height:1125px;transform-origin:0 50%;'
            f'transform:rotateY(-21deg) rotateX(3deg) scale({s});filter:drop-shadow(0 0 26px rgba(90,210,255,.75))">'
            f'{cut_panel(THEMES[0][2])}</div></div>'
            f'<div class="abs" style="inset:0;background:linear-gradient(90deg,#050a11 0,#050a11 40%,rgba(5,10,17,.75) 47%,transparent 54%)"></div>'
            f'<div class="scan" style="opacity:.45"></div>'
            f'<div class="abs title" style="left:84px;top:150px;font-size:196px;line-height:.9;letter-spacing:.07em;'
            f'text-shadow:0 0 40px rgba(120,225,255,.65)">OVERLAY<br>MAP</div>'
            f'<div class="abs" style="left:90px;top:528px;font:600 64px/1.12 R;letter-spacing:.03em;color:#e4f3f9">'
            f'Hologram map.<br>Game keeps running.</div>'
            + spectrum(92, 708, 700, 9, 12) +
            f'<div class="abs" style="left:92px;top:762px;width:820px">{chip_html}</div>'
            f'<svg class="abs" style="inset:0" width="{w}" height="{h}">{brackets(24, 24, w - 48, h - 48, c, 70, 5)}</svg>')
    page("5_thumb_1920x1080", w, h, body)


BANNERS = {"themes": themes_1080, "strip": themes_strip, "hero": hero, "features": callouts, "thumb": thumb}
if __name__ == "__main__":
    ASSETS.mkdir(parents=True, exist_ok=True)
    for key in sys.argv[1:] or BANNERS:   # e.g. `python3 make.py thumb`; none = all
        BANNERS[key]()
    for p in sorted(OUT.glob("*.png")):
        print(p.name, Image.open(p).size)
