# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Build the Tesla HUD atlas (1x and 2x PNG) and its Lua index.

    uv run scripts/hud/build_atlas.py

Outputs (overwritten):
  media/textures/MinidoracatTesla/HUD/atlas1x.png, atlas2x.png
  media/textures/MinidoracatTesla/HUD/radial_camp.png, radial_camp_off.png, radial_charge.png
  media/textures/MinidoracatTesla/HUD/app_arrow1x.png, app_arrow2x.png (phone app location page arrow, drawn rotated)
  media/textures/MinidoracatTesla/HUD/app_ring.png (phone app summon range: radar and pick map, tinted when drawn)
  media/textures/MinidoracatTesla/HUD/map_car.png, map_round.png (MiniMap car marker and its disc)
  media/lua/client/MinidoracatTesla/HUDAtlas.lua

Digits are rendered from Inter (SIL OFL 1.1, scripts/hud/fonts/OFL.txt). Font files never
go into MOD/. Icons are drawn here from 16-unit vector paths (all original artwork).
Also asserts the palette contrast ratios (the design's measured values) so a colour edit
that breaks readability fails the build.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MEDIA = os.path.join(REPO, "MOD", "MinidoracatTeslaFor42", "Contents", "mods", "MinidoracatTeslaFor42", "42", "media")
TEX_DIR = os.path.join(MEDIA, "textures", "MinidoracatTesla", "HUD")
LUA_OUT = os.path.join(MEDIA, "lua", "client", "MinidoracatTesla", "HUDAtlas.lua")
FONTS = os.path.join(HERE, "fonts")
SS = 8  # supersampling for vector art

# ---- palette (design tokens, plan-1023 .ts) -------------------------------------------
PAL = {
    "bg": "#121417", "surface": "#1E2227", "track": "#2E343B",
    "text": "#F3F5F7", "text2": "#AEB6BF", "text3": "#8E98A3",
    "accent": "#5B8CFF", "accentFill": "#3E6AE1",
    "ok": "#3DD68C", "warn": "#F5B544", "danger": "#FF6B6B", "red": "#EC1C24",
    # phone app: the real Tesla app (decisions.md "手機 App 第一版"); PhoneApp.lua keeps the same hex values
    "appBg": "#161718", "appText": "#F3F3F3", "appText2": "#8A8B8B", "appWeak": "#454546", "appLine": "#2E2F30",
    "appBlue": "#3268FE",
}


def _lum(hexc):
    c = [int(hexc[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4 for v in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def contrast(a, b):
    la, lb = sorted((_lum(a), _lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def check_contrast():
    # (fg, bg, minimum): text 4.5:1, icons/graphics 3:1 (WCAG 1.4.3 / 1.4.11)
    rules = [
        ("text", "bg", 4.5), ("text2", "bg", 4.5), ("text3", "bg", 4.5),
        ("text", "surface", 4.5), ("text2", "surface", 4.5), ("warn", "surface", 4.5),
        ("ok", "surface", 4.5), ("danger", "surface", 4.5),
        ("accent", "bg", 3.0), ("accent", "surface", 3.0), ("ok", "bg", 3.0),
        ("#FFFFFF", "accentFill", 4.5), ("text2", "track", 3.0), ("text", "track", 4.5),  # last: hover help
        ("appText", "appBg", 4.5), ("appText2", "appBg", 4.5), ("#FFFFFF", "appBlue", 4.5),  # phone app
    ]
    out = []
    for fg, bg, need in rules:
        a = PAL.get(fg, fg)
        b = PAL.get(bg, bg)
        r = contrast(a, b)
        out.append((fg, bg, round(r, 2)))
        assert r >= need, f"contrast {fg} on {bg} = {r:.2f} < {need}"
    return out


# ---- vector helpers (16-unit viewBox like the design mock) ----------------------------
def quad(p0, p1, p2, n=12):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in (i / n for i in range(1, n + 1))]


def path(cmds):
    """Tiny SVG-ish path: list of ("M",x,y) ("L",x,y) ("H",x) ("V",y) ("Q",cx,cy,x,y) ("Z",). Returns list of polylines."""
    polys, cur, start = [], [], None
    for c in cmds:
        k = c[0]
        if k == "M":
            if len(cur) > 1:
                polys.append((cur, False))
            cur = [(c[1], c[2])]
            start = cur[0]
        elif k == "L":
            cur.append((c[1], c[2]))
        elif k == "H":
            cur.append((c[1], cur[-1][1]))
        elif k == "V":
            cur.append((cur[-1][0], c[1]))
        elif k == "Q":
            cur.extend(quad(cur[-1], (c[1], c[2]), (c[3], c[4])))
        elif k == "Z":
            cur.append(start)
            polys.append((cur, True))
            cur = []
    if len(cur) > 1:
        polys.append((cur, False))
    return polys


class Canvas:
    """Draws in a `vw` x `vh` unit space onto a `pw` x `ph` pixel sprite (supersampled)."""

    def __init__(self, pw, ph, vw=16, vh=None):
        vh = vh or vw * ph / pw
        self.pw, self.ph = pw, ph
        self.sx, self.sy = pw * SS / vw, ph * SS / vh
        self.img = Image.new("RGBA", (pw * SS, ph * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def P(self, pts):
        return [(x * self.sx, y * self.sy) for x, y in pts]

    def stroke(self, cmds, w=1.5, color="#FFFFFF"):
        ww = max(1, round(w * self.sx))
        for pts, _closed in path(cmds):
            pp = self.P(pts)
            self.d.line(pp, fill=color, width=ww, joint="curve")
            r = ww / 2
            for x, y in (pp[0], pp[-1]):
                self.d.ellipse((x - r, y - r, x + r, y + r), fill=color)

    def fill(self, cmds, color="#FFFFFF"):
        for pts, _closed in path(cmds):
            self.d.polygon(self.P(pts), fill=color)

    def rrect(self, x, y, w, h, r, fill=None, outline=None, ow=1.5):
        box = (x * self.sx, y * self.sy, (x + w) * self.sx, (y + h) * self.sy)
        self.d.rounded_rectangle(box, radius=r * self.sx, fill=fill, outline=outline,
                                 width=max(1, round(ow * self.sx)) if outline else 0)

    def circle(self, cx, cy, r, fill=None, outline=None, ow=1.5):
        box = ((cx - r) * self.sx, (cy - r) * self.sy, (cx + r) * self.sx, (cy + r) * self.sy)
        self.d.ellipse(box, fill=fill, outline=outline, width=max(1, round(ow * self.sx)) if outline else 0)

    def out(self):
        im = self.img.convert("RGBa").resize((self.pw, self.ph), Image.LANCZOS)
        return im.convert("RGBA")


# icon painters: (canvas) -> None, drawn white in a 16-unit box
def ic_lock(c):
    c.rrect(3, 7, 10, 7, 1.5, outline="#FFFFFF")
    c.stroke([("M", 5, 7), ("V", 5), ("Q", 5, 2, 8, 2), ("Q", 11, 2, 11, 5), ("V", 7)])


def ic_unlock(c):
    c.rrect(3, 7, 10, 7, 1.5, outline="#FFFFFF")
    c.stroke([("M", 5, 7), ("V", 5), ("Q", 5, 2, 8, 2), ("Q", 10.6, 2, 11, 4.2)])


def ic_tent(c):
    c.stroke([("M", 1.5, 13.5), ("L", 8, 3), ("L", 14.5, 13.5), ("Z",)])
    c.stroke([("M", 5.5, 13.5), ("L", 8, 9.5), ("L", 10.5, 13.5)])


def ic_headlight(c):
    c.stroke([("M", 6, 4), ("Q", 2, 4, 2, 8), ("Q", 2, 12, 6, 12), ("Z",)])
    c.stroke([("M", 9, 5), ("H", 14)])
    c.stroke([("M", 9, 8), ("H", 14)])
    c.stroke([("M", 9, 11), ("H", 14)])


def ic_heater(c):
    for x in (5, 8, 11):
        c.stroke([("M", x, 3), ("Q", x - 2, 5, x, 7), ("Q", x + 2, 9, x, 11)])
    c.stroke([("M", 3, 13.5), ("H", 13)])


def ic_radio(c):
    c.rrect(2, 5, 12, 8, 1.5, outline="#FFFFFF")
    c.stroke([("M", 4, 5), ("L", 11, 2)])
    c.stroke([("M", 5, 9), ("H", 8)])
    c.circle(11, 9, 1.1, fill="#FFFFFF")


def ic_warn(c):
    c.stroke([("M", 8, 2), ("L", 14.5, 13.5), ("H", 1.5), ("Z",)])
    c.stroke([("M", 8, 6.5), ("V", 9.5)])
    c.circle(8, 11.7, 0.95, fill="#FFFFFF")


def ic_bolt(c):
    c.fill([("M", 9.5, 1), ("L", 3, 9), ("H", 7.2), ("L", 6.2, 15), ("L", 13, 6.6), ("H", 8.6), ("Z",)])


def ic_check(c):
    c.stroke([("M", 3, 8.5), ("L", 6.5, 12), ("L", 13, 4.5)], w=1.8)


def ic_ring(c):
    c.circle(8, 8, 6.3, outline="#FFFFFF", ow=2.0)


def ic_dot(c):
    c.circle(8, 8, 3.0, fill="#FFFFFF")


def ic_plug(c):
    c.stroke([("M", 6, 2), ("V", 5)])
    c.stroke([("M", 10, 2), ("V", 5)])
    c.stroke([("M", 4, 5), ("H", 12), ("V", 8), ("Q", 12, 11, 8, 11), ("Q", 4, 11, 4, 8), ("Z",)])
    c.stroke([("M", 8, 11), ("V", 14)])


def ic_power(c):  # IEC 60417-5009 standby symbol: a ring open at the top and a bar through the gap
    r, cx, cy = 5.6, 8, 8.8
    pts = [(cx + r * math.sin(math.radians(a)), cy - r * math.cos(math.radians(a))) for a in range(40, 321, 10)]
    c.stroke([("M", *pts[0])] + [("L", *p) for p in pts[1:]])
    c.stroke([("M", 8, 1.8), ("V", 8)])


def ic_cell(c):  # 24x12 battery outline (viewBox 24x12)
    c.rrect(0.9, 0.9, 20.2, 10.2, 2.5, outline="#FFFFFF", ow=1.4)
    c.rrect(21.8, 3.8, 1.8, 4.4, 0.8, fill="#FFFFFF")


def ic_round(c):
    c.circle(8, 8, 8, fill="#FFFFFF")


def ic_keybg(c):  # 40x40 rounded square, r=10
    c.rrect(0, 0, 16, 16, 4, fill="#FFFFFF")


# phone app (plan-phone-app-1027 mock)
def ic_horn(c):
    c.stroke([("M", 2, 6.5), ("H", 5), ("L", 10, 3), ("V", 13), ("L", 5, 9.5), ("H", 2), ("Z",)])
    c.stroke([("M", 12, 6), ("Q", 13.6, 8, 12, 10)])


# phone app, the restyle mock (temp/app-style/restyle.html): 1.3-unit strokes like the real Tesla app's line icons
def ic_frunk(c):  # front trunk: the lid's trapezoid over the body
    c.stroke([("M", 2, 10), ("L", 4, 6), ("H", 12), ("L", 14, 10), ("V", 12), ("H", 2), ("Z",)], w=1.3)
    c.stroke([("M", 4, 6), ("L", 6, 3), ("H", 10), ("L", 12, 6)], w=1.3)


def ic_trunk(c):  # liftgate raised
    c.stroke([("M", 2, 12), ("V", 8), ("L", 5, 5), ("H", 11), ("L", 14, 8), ("V", 12), ("Z",)], w=1.3)
    c.stroke([("M", 11, 5), ("L", 13, 2)], w=1.3)


def ic_lockfill(c):  # locked: solid body
    c.rrect(3.5, 7, 9, 7, 1.5, fill="#FFFFFF")
    c.stroke([("M", 5.5, 7), ("V", 5), ("Q", 5.5, 2.3, 8, 2.3), ("Q", 10.5, 2.3, 10.5, 5), ("V", 7)], w=1.4)


def ic_carfront(c):  # "Controls" row
    c.stroke([("M", 2, 11), ("L", 3.5, 7), ("H", 12.5), ("L", 14, 11), ("V", 13), ("H", 2), ("Z",)], w=1.3)
    c.circle(5, 11, 0.8, fill="#FFFFFF")
    c.circle(11, 11, 0.8, fill="#FFFFFF")


def ic_nav(c):  # "Location" row
    c.fill([("M", 8, 1.5), ("L", 13, 14), ("L", 8, 11), ("L", 3, 14), ("Z",)])


def ic_shield(c):  # "Security" row
    c.stroke([("M", 8, 1.5), ("L", 13.5, 3.5), ("V", 8), ("Q", 13.5, 12.5, 8, 14.5), ("Q", 2.5, 12.5, 2.5, 8),
              ("V", 3.5), ("Z",)], w=1.3)


def ic_chev(c):  # list row ">"
    c.stroke([("M", 6, 3), ("L", 11, 8), ("L", 6, 13)], w=1.4)


def ic_chevdown(c):  # app home: the car name's "v" (opens the car list)
    c.stroke([("M", 3.5, 6), ("L", 8, 10.5), ("L", 12.5, 6)], w=1.6)


def ic_back(c):  # sub page "<"
    c.stroke([("M", 10.5, 3), ("L", 5.5, 8), ("L", 10.5, 13)], w=1.6)


def ic_close(c):
    c.stroke([("M", 3.5, 3.5), ("L", 12.5, 12.5)], w=1.4)
    c.stroke([("M", 12.5, 3.5), ("L", 3.5, 12.5)], w=1.4)


def ic_wheel(c):  # "Summon" row: a steering wheel (the summon mock's icon)
    c.circle(8, 8, 6, outline="#FFFFFF", ow=1.3)
    c.circle(8, 8, 1.6, outline="#FFFFFF", ow=1.3)
    c.stroke([("M", 2.3, 7), ("H", 6.5)], w=1.3)
    c.stroke([("M", 9.5, 7), ("H", 13.7)], w=1.3)
    c.stroke([("M", 8, 9.6), ("V", 14)], w=1.3)


def ic_pin(c):  # summon target: a map pin with a hole (the mock's teardrop), tip at the bottom centre
    c.circle(8, 6.2, 4.6, fill="#FFFFFF")
    c.fill([("M", 4.2, 8.8), ("L", 8, 15), ("L", 11.8, 8.8), ("Z",)])
    c.circle(8, 6.2, 1.8, fill=(0, 0, 0, 0))


def app_ring():  # the summon range on the app's radar and its pick map: 10% disc, full ring; white, tinted when drawn
    n = 256
    big = Image.new("RGBA", (n * SS // 2, n * SS // 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    s = SS // 2
    w = 3 * s
    d.ellipse((w / 2, w / 2, n * s - w / 2, n * s - w / 2), fill=(255, 255, 255, 26))
    d.ellipse((w / 2, w / 2, n * s - w / 2, n * s - w / 2), outline=(255, 255, 255, 255), width=w)
    return big.resize((n, n), Image.LANCZOS)


def map_icons():  # MiniMap marker provider (MiniMapBridge.lua): whole textures, white, tinted when drawn
    out = {}
    for key, fn in (("map_car", ic_carfront), ("map_round", ic_round)):
        c = Canvas(32, 32, 16)
        fn(c)
        out[key] = c.out()
    return out


def app_arrow(k):  # 48 px at 1x, pointing up (the mock's "M8 1.5L13 14L8 11L3 14Z"), white: tinted when drawn
    c = Canvas(48 * k, 48 * k, 16)
    ic_nav(c)
    return c.out()



# ---- car (top view, nose to the right; left side of the car = top edge) ------------
# One sprite per car, car_<Specs model> (HUD.lua and the app's maps pick it by the car's model); the door overlays and
# the clickable zones (HUD.lua ZONES) line up with both. Units: viewBox 170x96 drawn at 150x85 px.
CAR_VB = (170, 96)
CAR_PX = (150, 85)


def car_wheels(c):
    for x, y in ((40, 16), (110, 16), (40, 72), (110, 72)):
        c.rrect(x, y, 19, 8, 2, fill="#0B0D0F", outline="#8E98A3", ow=1.1)


def b_pillar(c, y0, y1):  # B-pillar seam lines (door split) — subtle
    c.stroke([("M", 78, y0 + 0.6), ("V", y0 + 3)], w=1.0, color="#4A525B")
    c.stroke([("M", 78, y1 - 3), ("V", y1 - 0.6)], w=1.0, color="#4A525B")


def car_modely(c):  # Model Y: the glass roof runs into the liftgate glass (x 34-51)
    car_wheels(c)
    body = [("M", 34, 22), ("H", 122), ("Q", 142, 22, 146, 36), ("V", 60), ("Q", 142, 74, 122, 74),
            ("H", 34), ("Q", 22, 74, 22, 62), ("V", 34), ("Q", 22, 22, 34, 22), ("Z",)]
    c.fill(body, "#2A3037")
    c.stroke(body, w=1.3, color="#AEB6BF")
    c.fill([("M", 102, 29), ("Q", 117, 29, 120, 38), ("V", 58), ("Q", 117, 67, 102, 67), ("Z",)], "#15191E")
    c.fill([("M", 39, 31), ("H", 51), ("V", 65), ("H", 39), ("Q", 34, 65, 34, 60), ("V", 36), ("Q", 34, 31, 39, 31), ("Z",)], "#15191E")
    b_pillar(c, 22, 74)


def car_model3(c):
    """Model 3 (4,724 x 1,848 mm against the Model Y's 4,790 x 1,921: 98.6% as long, 96% as wide; same wheelbase
    class, so the same wheels): a sedan, the rear glass (x 43-56, up to where the rear doors' outline starts) behind
    the trunk lid's front seam (x 40), the lid (x 23-40) body colour. HUD.lua ZONES.Model3 follows these edges."""
    car_wheels(c)
    body = [("M", 36, 23), ("H", 121), ("Q", 141, 23, 145, 37), ("V", 59), ("Q", 141, 73, 121, 73),
            ("H", 36), ("Q", 23, 73, 23, 62), ("V", 34), ("Q", 23, 23, 36, 23), ("Z",)]
    c.fill(body, "#2A3037")
    c.stroke(body, w=1.3, color="#AEB6BF")
    c.fill([("M", 101, 30), ("Q", 116, 30, 119, 38), ("V", 58), ("Q", 116, 66, 101, 66), ("Z",)], "#15191E")
    c.fill([("M", 47, 31), ("H", 56), ("V", 65), ("H", 47), ("Q", 43, 65, 43, 60), ("V", 36), ("Q", 43, 31, 47, 31), ("Z",)], "#15191E")
    c.stroke([("M", 40, 29), ("Q", 38.5, 48, 40, 67)], w=1.0, color="#4A525B")  # trunk lid seam
    b_pillar(c, 23, 73)


CARS = {"ModelY": car_modely, "Model3": car_model3}


def dashed(c, x0, y0, x1, y1, w=1.8, dash=3.0, gap=2.0):
    L = math.hypot(x1 - x0, y1 - y0)
    ux, uy = (x1 - x0) / L, (y1 - y0) / L
    t = 0.0
    while t < L:
        e = min(L, t + dash)
        c.stroke([("M", x0 + ux * t, y0 + uy * t), ("L", x0 + ux * e, y0 + uy * e)], w=w)
        t = e + gap


def door_overlay(kind):
    def paint(c):
        if kind in ("FL", "RL", "FR", "RR"):
            front = kind[0] == "F"
            x0, x1 = (78, 100) if front else (56, 78)
            y = 22 if kind[1] == "L" else 74
            out = -17 if kind[1] == "L" else 17
            dashed(c, x0, y, x1, y)
            c.stroke([("M", x1, y), ("L", x1 - 18, y + out)], w=2.8)
        elif kind == "TR":  # trunk / tailgate (rear = left)
            dashed(c, 22, 36, 22, 60)
            c.stroke([("M", 16, 34), ("V", 62)], w=2.8)
        elif kind == "HD":  # hood (front = right)
            dashed(c, 146, 38, 146, 58)
            c.stroke([("M", 152, 36), ("V", 60)], w=2.8)
    return paint


# ---- glyphs -------------------------------------------------------------------------
GLYPH_SETS = [
    # name, font file, size(1x), chars, fixed-advance digits
    ("big", "Inter-Light.ttf", 58, "0123456789", True),
    ("mid", "Inter-SemiBold.ttf", 20, "0123456789%", True),
    ("sm", "Inter-Regular.ttf", 17, "0123456789PRND", True),
    ("smb", "Inter-SemiBold.ttf", 17, "PRND", False),
]
# key, font, size (1x), text, letter spacing (px at 1x); the phone app's footer wordmark and trim (restyle mock)
WORDS = [("kmh", "Inter-Regular.ttf", 14, "km/h", 0), ("km", "Inter-Regular.ttf", 17, "km", 0),
         ("wm_ModelY", "Inter-Light.ttf", 15, "MODEL Y", 5), ("trim_ModelY", "Inter-Regular.ttf", 13, "Performance", 0),
         ("wm_Model3", "Inter-Light.ttf", 15, "MODEL 3", 5), ("trim_Model3", "Inter-Regular.ttf", 13, "Performance", 0)]


def render_text(fontfile, size, s, track=0):
    f = ImageFont.truetype(os.path.join(FONTS, fontfile), size)
    cap = f.getbbox("H", anchor="ls")[1]
    if track:  # letter-spaced: each character at its own pen x, `track` added after every one
        xs, x = [], 0.0
        for ch in s:
            xs.append(x)
            x += f.getlength(ch) + track
        adv = x - track
        boxes = [f.getbbox(ch, anchor="ls") for ch in s if ch != " "]
        l, t, b = min(bb[0] for bb in boxes), min(bb[1] for bb in boxes), max(bb[3] for bb in boxes)
        r = math.ceil(xs[-1] + f.getbbox(s[-1], anchor="ls")[2])
        runs = list(zip(s, xs))
    else:
        l, t, r, b = f.getbbox(s, anchor="ls")
        adv, runs = f.getlength(s), [(s, 0)]
    w, h = max(1, r - l), max(1, b - t)
    im = Image.new("RGBA", (w + 2, h + 2), (255, 255, 255, 0))
    mask = Image.new("L", (w + 2, h + 2), 0)
    d = ImageDraw.Draw(mask)
    for text, px in runs:
        d.text((1 - l + px, 1 - t), text, font=f, fill=255, anchor="ls")
    im.putalpha(mask)
    return im, l - 1, t - 1 - cap, adv


def build_sprites(k):
    """Return dict name -> (image, ox, oy, adv) at scale k."""
    sp = {}
    for name, ff, size, chars, mono in GLYPH_SETS:
        imgs = {ch: render_text(ff, size * k, ch) for ch in chars}
        adv = max(v[3] for ch, v in imgs.items() if ch.isdigit()) if mono else None
        for ch, (im, ox, oy, a) in imgs.items():
            key = f"{name}_{'pct' if ch == '%' else ch}"
            if mono and ch.isdigit():  # centre inside the fixed cell
                ox += (adv - a) / 2
                a = adv
            sp[key] = (im, ox, oy, a)
    for key, ff, size, s, track in WORDS:
        sp[key] = render_text(ff, size * k, s, track * k)

    icons16 = {
        "lock": ic_lock, "unlock": ic_unlock, "tent": ic_tent, "headlight": ic_headlight,
        "heater": ic_heater, "radio": ic_radio, "warn": ic_warn, "bolt": ic_bolt, "check": ic_check,
        "ring": ic_ring, "dot": ic_dot, "plug": ic_plug, "power": ic_power,
        "horn": ic_horn, "frunk": ic_frunk, "trunk": ic_trunk, "lockfill": ic_lockfill, "carfront": ic_carfront,
        "nav": ic_nav, "shield": ic_shield, "chev": ic_chev, "chevdown": ic_chevdown, "back": ic_back, "close": ic_close,
        "wheel": ic_wheel, "pin": ic_pin,
    }
    for key, fn in icons16.items():
        c = Canvas(18 * k, 18 * k, 16)
        fn(c)
        sp["i_" + key] = (c.out(), 0, 0, 0)
    c = Canvas(24 * k, 12 * k, 24, 12)
    ic_cell(c)
    sp["cell"] = (c.out(), 0, 0, 0)
    c = Canvas(32 * k, 32 * k, 16)
    ic_round(c)
    sp["round"] = (c.out(), 0, 0, 0)
    c = Canvas(40 * k, 40 * k, 16)
    ic_keybg(c)
    sp["keybg"] = (c.out(), 0, 0, 0)
    sp["solid"] = (Image.new("RGBA", (4 * k, 4 * k), (255, 255, 255, 255)), 0, 0, 0)

    cw, ch = CAR_PX[0] * k, CAR_PX[1] * k
    for model, draw in CARS.items():
        c = Canvas(cw, ch, CAR_VB[0], CAR_VB[1])
        draw(c)
        sp["car_" + model] = (c.out(), 0, 0, 0)
    for kind in ("FL", "FR", "RL", "RR", "TR", "HD"):
        c = Canvas(cw, ch, CAR_VB[0], CAR_VB[1])
        door_overlay(kind)(c)
        im = c.out()
        bb = im.getbbox()
        sp["door_" + kind] = (im.crop(bb), bb[0], bb[1], 0)
    return sp


def pack(sprites, width, pad):
    order = sorted(sprites, key=lambda n: (-sprites[n][0].height, n))
    x = y = shelf = 0
    pos = {}
    for n in order:
        im = sprites[n][0]
        if x + im.width + pad > width:
            x, y, shelf = 0, y + shelf + pad, 0
        pos[n] = (x + pad, y + pad)
        x += im.width + pad
        shelf = max(shelf, im.height)
    height = 1
    while height < y + shelf + 2 * pad:
        height *= 2
    atlas = Image.new("RGBA", (width, height), (255, 255, 255, 0))
    for n, (px, py) in pos.items():
        atlas.paste(sprites[n][0], (px, py))
    return atlas, pos


def radial_icons():
    out = {}
    for key, fn, color in (("radial_camp", ic_tent, "#F3F5F7"), ("radial_camp_off", ic_tent, "#6B737C"),
                           ("radial_charge", ic_plug, "#F3F5F7")):
        c = Canvas(48, 48, 16)
        # draw at 1.5px scale-adjusted stroke so it reads at 48px like vanilla radial icons
        fn(c)
        im = c.out()
        r, g, b = (int(color[i:i + 2], 16) for i in (1, 3, 5))
        tint = Image.new("RGBA", im.size, (r, g, b, 255))
        tint.putalpha(im.getchannel("A"))
        out[key] = tint
    return out


def lua_entry(name, sp, pos, k):
    im, ox, oy, adv = sp[name]
    x, y = pos[name]
    # solid: sample the centre so linear filtering never reaches the transparent border
    if name == "solid":
        return "{%d,%d,%d,%d,0,0,0}" % (x + k, y + k, 2 * k, 2 * k)
    return "{%d,%d,%d,%d,%g,%g,%g}" % (x, y, im.width, im.height, round(ox, 2), round(oy, 2), round(adv, 2))


def main():
    contrasts = check_contrast()
    os.makedirs(TEX_DIR, exist_ok=True)
    lua = ["-- Generated by scripts/hud/build_atlas.py; do not edit by hand.",
           "-- Entry = { x, y, w, h, ox, oy, adv } in atlas pixels of that scale.",
           "MinidoracatTesla = MinidoracatTesla or {}",
           "MinidoracatTesla.HUDAtlas = {"]
    for k in (1, 2):
        sp = build_sprites(k)
        atlas, pos = pack(sp, 512 * k, 2 * k)
        fn = f"atlas{k}x.png"
        atlas.save(os.path.join(TEX_DIR, fn), optimize=True)
        lua.append("  [%d] = {" % k)
        lua.append('    tex = "media/textures/MinidoracatTesla/HUD/%s",' % fn)
        for name in sorted(sp):
            lua.append("    %s = %s," % (name, lua_entry(name, sp, pos, k)))
        lua.append("  },")
        print(f"atlas{k}x: {atlas.size[0]}x{atlas.size[1]}, {len(sp)} sprites")
    lua.append("}")
    for key, im in radial_icons().items():
        im.save(os.path.join(TEX_DIR, key + ".png"), optimize=True)
    for key, im in map_icons().items():
        im.save(os.path.join(TEX_DIR, key + ".png"), optimize=True)
    for k in (1, 2):
        app_arrow(k).save(os.path.join(TEX_DIR, f"app_arrow{k}x.png"), optimize=True)
    app_ring().save(os.path.join(TEX_DIR, "app_ring.png"), optimize=True)
    with open(LUA_OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lua) + "\n")
    print("contrast:", ", ".join(f"{a}/{b}={r}" for a, b, r in contrasts))


if __name__ == "__main__":
    main()
