# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Build the Tesla HUD atlas (1x and 2x PNG) and its Lua index.

    uv run scripts/hud/build_atlas.py   (a Pillow with libraqm: see below)

Outputs (overwritten):
  media/textures/MinidoracatTesla/HUD/atlas1x.png, atlas2x.png
  media/textures/MinidoracatTesla/HUD/radial_camp.png, radial_camp_off.png, radial_charge.png, radial_lightbar.png,
  radial_powershare(_off).png, radial_outlet(_off).png, radial_bdm.png, radial_chill.png
  media/textures/MinidoracatTesla/HUD/app_arrow1x.png, app_arrow2x.png (phone app location page arrow, drawn rotated)
  media/textures/MinidoracatTesla/HUD/app_ring.png (phone app summon range: radar and pick map, tinted when drawn)
  media/textures/MinidoracatTesla/HUD/map_car.png, map_round.png (MiniMap car marker and its disc)
  media/lua/client/MinidoracatTesla/HUDAtlas.lua

Digits are rendered from Inter (SIL OFL 1.1, scripts/hud/fonts/OFL.txt). Font files never
go into MOD/. Icons are drawn here from 16-unit vector paths (all original artwork).
Also asserts the palette contrast ratios (the design's measured values) so a colour edit
that breaks readability fails the build.

Text is laid out by Pillow's libraqm (fractional advances); without it Pillow falls back to hinted whole-pixel advances
and every glyph's metrics in HUDAtlas.lua change, so the build stops. PyPI's Windows wheels have no libraqm: use
MSYS2's mingw-w64-x86_64-python-pillow (its python.exe with mingw64/bin on PATH).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont, features

assert features.check("raqm"), "Pillow without libraqm: HUDAtlas.lua glyph metrics would change (see the docstring)"

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


def ic_tonneau(c):  # Cybertruck side view: the bed's open top, the cover rolled up at its front wall
    c.stroke([("M", 1.5, 12), ("V", 8), ("H", 8), ("L", 10, 4), ("L", 14.5, 8), ("V", 12), ("Z",)], w=1.3)
    c.circle(8.2, 6.2, 1.3, fill="#FFFFFF")
    c.stroke([("M", 2.5, 6), ("H", 6)], w=1.3)


def ic_falcon(c):  # Model X falcon wing doors, seen from behind: the body, both wings raised from the roof
    c.stroke([("M", 3, 14), ("V", 11), ("L", 5, 8.5), ("H", 11), ("L", 13, 11), ("V", 14), ("Z",)], w=1.3)
    c.stroke([("M", 7, 8.5), ("L", 4, 3), ("L", 1.5, 5.5)], w=1.3)
    c.stroke([("M", 9, 8.5), ("L", 12, 3), ("L", 14.5, 5.5)], w=1.3)


def ic_softtop(c):  # Roadster side view, top down: the low body on its wheels, the windscreen, the top folded behind
    c.stroke([("M", 1.5, 11), ("V", 8.5), ("H", 9), ("L", 14.5, 9.8), ("V", 11), ("Z",)], w=1.3)
    c.stroke([("M", 9, 8.5), ("L", 7.6, 4.8)], w=1.3)
    c.rrect(2.3, 6.2, 3.6, 2.0, 1.0, fill="#FFFFFF")
    for x in (4.4, 11.6):
        c.circle(x, 11.9, 1.7, fill="#FFFFFF")


def ic_lightbar(c):  # roof light bar: the bar and its beams ahead
    c.rrect(2, 2.5, 12, 3, 1.2, outline="#FFFFFF", ow=1.3)
    for x0, x1 in ((4, 2.5), (8, 8), (12, 13.5)):
        c.stroke([("M", x0, 7.5), ("L", x1, 13.5)], w=1.3)


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


def ic_house(c):  # Cybertruck Powershare (app cell, radial): a house with a bolt in it
    c.stroke([("M", 1.8, 8.2), ("L", 8, 2.4), ("L", 14.2, 8.2)], w=1.3)
    c.stroke([("M", 3.6, 6.8), ("V", 14), ("H", 12.4), ("V", 6.8)], w=1.3)
    c.fill([("M", 8.9, 6.6), ("L", 5.9, 10.8), ("H", 7.8), ("L", 7.1, 13.4), ("L", 10.1, 9.2), ("H", 8.2), ("Z",)])


def ic_outlet(c):  # Cybertruck bed outlet (radial): a socket face, two slots and the ground hole
    c.rrect(2.2, 2.2, 11.6, 11.6, 2.6, outline="#FFFFFF", ow=1.3)
    c.stroke([("M", 6, 5.4), ("V", 8.6)], w=1.3)
    c.stroke([("M", 10, 5.4), ("V", 8.6)], w=1.3)
    c.circle(8, 11.2, 1.0, fill="#FFFFFF")


def ic_biohazard(c):  # Bioweapon Defense Mode (radial): three rings around a centre ring, the biohazard trefoil
    cx, cy = 8, 8.6
    for a in (90, 210, 330):
        c.circle(cx + 3.1 * math.cos(math.radians(a)), cy - 3.1 * math.sin(math.radians(a)), 3.3, outline="#FFFFFF", ow=1.3)
    c.circle(cx, cy, 1.3, fill="#FFFFFF")


def ic_chill(c):  # Chill (radial): a speedometer arc with the needle resting low
    r, cx, cy = 6.2, 8, 9.5
    pts = [(cx + r * math.cos(math.radians(a)), cy - r * math.sin(math.radians(a))) for a in range(210, -31, -10)]
    c.stroke([("M", *pts[0])] + [("L", *p) for p in pts[1:]], w=1.3)
    a = math.radians(160)
    c.stroke([("M", cx, cy), ("L", cx + 4.3 * math.cos(a), cy - 4.3 * math.sin(a))], w=1.5)
    c.circle(cx, cy, 1.2, fill="#FFFFFF")


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


def car_modelyl(c):
    """Model Y L (owner's manual: 4,969 x 1,920 mm, wheelbase 3,040, overhangs front 889 / rear 1,040; 255/45R19 front,
    275/45R19 rear) at the Model Y's 0.0259 viewBox units per mm, nose on the Model Y's (x 146): as wide as the Model
    Y, the same from the nose to the B-pillar (windscreen, front doors, x 78 seam). Behind it 179 mm longer: the
    rear 17.3, the axles on the official wheelbase (x 123 and 44.2), the rear doors' lower half 150 mm further back
    (DOOR_GEOM rear from x 52.1) and a longer roof to the liftgate glass (x 29.4-46.4, the Model Y's moved back with
    the tail). HUD.lua ZONES.ModelYL follows these edges."""
    for x0, w in ((113.8, 18.4), (34.8, 18.9)):  # front 712 mm, rear 730 mm tyres on the axles
        for y in (16, 72):
            c.rrect(x0, y, w, 8, 2, fill="#0B0D0F", outline="#8E98A3", ow=1.1)
    body = [("M", 29.3, 22), ("H", 122), ("Q", 142, 22, 146, 36), ("V", 60), ("Q", 142, 74, 122, 74),
            ("H", 29.3), ("Q", 17.3, 74, 17.3, 62), ("V", 34), ("Q", 17.3, 22, 29.3, 22), ("Z",)]
    c.fill(body, "#2A3037")
    c.stroke(body, w=1.3, color="#AEB6BF")
    c.fill([("M", 102, 29), ("Q", 117, 29, 120, 38), ("V", 58), ("Q", 117, 67, 102, 67), ("Z",)], "#15191E")
    c.fill([("M", 34.4, 31), ("H", 46.4), ("V", 65), ("H", 34.4), ("Q", 29.4, 65, 29.4, 60), ("V", 36),
            ("Q", 29.4, 31, 34.4, 31), ("Z",)], "#15191E")
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


def car_cybertruck(c):
    """Cyberbeast (owner's manual p.245-246: 5,683 x 2,032 mm, wheelbase 3,635, overhangs front 878 / rear 1,170; bed
    floor 1,825 long, p.249) at 0.0257 viewBox units per mm: as wide as the Model Y here, 2.80 times as long. Rear 8,
    nose 154; the tailgate (x 8-9.5), the bed under the tonneau's slats (x 9.5-56.4) to the bed's front wall, the rear
    glass (x 58-62), the doors split at x 87 and the front doors end at the frunk lid (x 118); the glass roof runs from
    the rear glass to the windscreen's foot. HUD.lua ZONES.Cybertruck follows these edges."""
    for x in (26.6, 120.0):  # 35" tyres (890 mm) on the axles, x 38.1 and 131.5
        for y in (16, 72):
            c.rrect(x, y, 23, 8, 2, fill="#0B0D0F", outline="#8E98A3", ow=1.1)
    body = [("M", 8, 22), ("H", 149), ("L", 154, 30), ("V", 66), ("L", 149, 74), ("H", 8), ("Z",)]
    c.fill(body, "#2A3037")
    c.stroke(body, w=1.3, color="#AEB6BF")
    c.fill([("M", 9.5, 25), ("H", 56.4), ("V", 71), ("H", 9.5), ("Z",)], "#323941")  # tonneau over the bed
    for x in range(14, 56, 5):  # its slats
        c.stroke([("M", x, 26), ("V", 70)], w=0.8, color="#262B31")
    c.stroke([("M", 56.4, 25), ("V", 71)], w=1.0, color="#4A525B")  # bed front wall
    c.fill([("M", 62, 29), ("L", 120, 31), ("V", 65), ("L", 62, 67), ("Z",)], "#15191E")  # glass roof, windscreen
    c.fill([("M", 58, 30), ("H", 61), ("V", 66), ("H", 58), ("Z",)], "#15191E")  # rear glass
    c.stroke([("M", 9.5, 23), ("V", 73)], w=1.0, color="#4A525B")  # tailgate seam
    c.stroke([("M", 118, 25), ("L", 120, 31)], w=1.0, color="#4A525B")  # frunk lid seams
    c.stroke([("M", 118, 71), ("L", 120, 65)], w=1.0, color="#4A525B")
    for y0, y1 in ((22, 25), (71, 74)):  # B-pillar seam
        c.stroke([("M", 87, y0 + 0.6), ("V", y1 - 0.6)], w=1.0, color="#4A525B")


def car_models(c):
    """Model S Plaid (owner's manual 2026: 5,046 x 1,987 mm, wheelbase 2,960, overhangs front 963 / rear 1,123) at the
    Model Y's 0.0259 viewBox units per mm: rear 16.4, nose 147; 19" wheels (712 mm) on the axles, x 45.5 and 122. A
    liftback: the liftgate (x 16.4-48.4) carries the rear glass, from the roof hinge back; the glass roof runs on to
    the windscreen's foot (x 114), the frunk lid from there to the nose. Doors split at x 76.4 (rear doors from 48.1,
    front doors to 105.3). HUD.lua ZONES.ModelS follows these edges."""
    for x in (36.3, 112.8):
        for y in (16, 72):
            c.rrect(x, y, 18.4, 8, 2, fill="#0B0D0F", outline="#8E98A3", ow=1.1)
    body = [("M", 30, 23), ("H", 125), ("Q", 145, 23, 147, 38), ("V", 58), ("Q", 145, 73, 125, 73),
            ("H", 30), ("Q", 16.4, 73, 16.4, 61), ("V", 35), ("Q", 16.4, 23, 30, 23), ("Z",)]
    c.fill(body, "#2A3037")
    c.stroke(body, w=1.3, color="#AEB6BF")
    c.fill([("M", 30, 30), ("H", 108), ("Q", 113, 30, 114.4, 38), ("V", 58), ("Q", 113, 66, 108, 66), ("H", 30),
            ("Q", 26, 66, 26, 60), ("V", 36), ("Q", 26, 30, 30, 30), ("Z",)], "#15191E")   # rear glass, roof, windscreen
    c.stroke([("M", 48.4, 30), ("V", 66)], w=1.0, color="#4A525B")  # liftgate hinge (rear glass / roof glass)
    for y0, y1 in ((23, 26), (70, 73)):  # B-pillar seam
        c.stroke([("M", 76.4, y0 + 0.6), ("V", y1 - 0.6)], w=1.0, color="#4A525B")


def car_modelx(c):
    """Model X (owner's manual p.222: 5,057 x 1,999 mm, wheelbase 2,965, overhangs front 988 / rear 1,104) at 0.026
    viewBox units per mm: as wide as the Model Y here. Rear 18, nose 149, axles x 46.7 and 123.8. The liftgate (x
    18-49.9) carries the rear glass; each falcon wing door runs from the roof's spine (y 46.5 / 49.5) down its side,
    from the liftgate's seam (x 49.9) to the B-pillar (x 85), its glass on the roof; the panoramic windscreen runs from
    the B-pillar to the frunk lid (x 120). HUD.lua ZONES.ModelX follows these edges."""
    for x in (37.2, 114.3):  # 20" wheels (about 755 mm) on the axles
        for y in (16, 72):
            c.rrect(x, y, 19, 8, 2, fill="#0B0D0F", outline="#8E98A3", ow=1.1)
    body = [("M", 32, 22), ("H", 128), ("Q", 147, 22, 149, 38), ("V", 58), ("Q", 147, 74, 128, 74),
            ("H", 32), ("Q", 18, 74, 18, 62), ("V", 34), ("Q", 18, 22, 32, 22), ("Z",)]
    c.fill(body, "#2A3037")
    c.stroke(body, w=1.3, color="#AEB6BF")
    c.fill([("M", 86, 28), ("H", 104), ("Q", 117, 29, 120, 38), ("V", 58), ("Q", 117, 67, 104, 68), ("H", 86), ("Z",)],
           "#15191E")  # windscreen over the front seats
    c.rrect(51.5, 27, 32.5, 19.5, 3, fill="#15191E")  # falcon wing glass, left (top) and right
    c.rrect(51.5, 49.5, 32.5, 19.5, 3, fill="#15191E")
    c.fill([("M", 27, 31), ("H", 47), ("V", 65), ("H", 27), ("Q", 23, 65, 23, 60), ("V", 36), ("Q", 23, 31, 27, 31), ("Z",)],
           "#15191E")  # liftgate glass
    c.stroke([("M", 49.9, 22.6), ("V", 73.4)], w=1.0, color="#4A525B")  # liftgate / falcon wing seam
    c.stroke([("M", 51, 48), ("H", 84)], w=1.0, color="#4A525B")  # the wings' roof hinge (spine)
    for y0, y1 in ((22, 27), (69, 74)):  # B-pillar seam
        c.stroke([("M", 85, y0 + 0.6), ("V", y1 - 0.6)], w=1.0, color="#4A525B")


def car_roadster(c):
    """Roadster 2.5 (owner's manual 10-15: 3,946 x 1,851 mm with mirrors, wheelbase 2,351, overhangs front 871 / rear 723;
    195/50 R16 front, 225/45 R17 rear, 10-4) at the Model Y's 0.0259 viewBox units per mm, nose on the Model Y's (x 146):
    rear 43.8, axles x 123.4 and 62.6. The body without mirrors about 1,730 mm wide (y 25-71). The car model's edges
    (scripts/blender/skf/cars/roadster.py; the manual's side view draws the wheels nearer than the ends, its seams sit
    off by up to 35 cm): the trunk lid from x 51.2, the soft top over the seats (x 80.3-99.8, from the roll hoop to the
    windscreen's top), the windscreen to its foot (x 119.1), the doors x 80.3-110.2, the hood ahead. HUD.lua
    ZONES.Roadster follows these edges."""
    for x0, w in ((115.6, 15.6), (54.4, 16.4)):  # front 601 mm, rear 634 mm tyres on the axles
        for y in (19, 69):
            c.rrect(x0, y, w, 8, 2, fill="#0B0D0F", outline="#8E98A3", ow=1.1)
    body = [("M", 56, 25), ("H", 124), ("Q", 142, 26, 146, 40), ("V", 56), ("Q", 142, 70, 124, 71),
            ("H", 56), ("Q", 43.8, 71, 43.8, 60), ("V", 36), ("Q", 43.8, 25, 56, 25), ("Z",)]
    c.fill(body, "#2A3037")
    c.stroke(body, w=1.3, color="#AEB6BF")
    c.fill([("M", 99.8, 33), ("L", 116.5, 31), ("Q", 119.6, 48, 116.5, 65), ("L", 99.8, 63), ("Z",)], "#15191E")  # windscreen
    c.rrect(80.3, 34, 19.5, 28.3, 3, fill="#1B1F24")  # soft top
    c.stroke([("M", 81.1, 34.6), ("V", 61.7)], w=1.0, color="#4A525B")  # its rear edge, the roll hoop
    c.stroke([("M", 51.2, 28), ("Q", 49.7, 48, 51.2, 68)], w=1.0, color="#4A525B")  # trunk lid seam
    for y0, y1 in ((25, 28), (68, 71)):  # door seams
        for x in (80.3, 110.2):
            c.stroke([("M", x, y0 + 0.6), ("V", y1 - 0.6)], w=1.0, color="#4A525B")


CARS = {"ModelY": car_modely, "Model3": car_model3, "Cybertruck": car_cybertruck, "ModelS": car_models, "ModelX": car_modelx,
        "ModelYL": car_modelyl, "Roadster": car_roadster}


def dashed(c, x0, y0, x1, y1, w=1.8, dash=3.0, gap=2.0):
    L = math.hypot(x1 - x0, y1 - y0)
    ux, uy = (x1 - x0) / L, (y1 - y0) / L
    t = 0.0
    while t < L:
        e = min(L, t + dash)
        c.stroke([("M", x0 + ux * t, y0 + uy * t), ("L", x0 + ux * e, y0 + uy * e)], w=w)
        t = e + gap


# door overlay geometry (viewBox): front / rear door spans, the car's left and right edges, the rear lid's closed and
# open lines, the hood's; a car not listed uses the Model Y / Model 3 one and the plain door_<kind> sprites
DOOR_GEOM = {
    None: {"front": (78, 100), "rear": (56, 78), "y": (22, 74), "tr": ((22, 36, 60), (16, 34, 62)),
           "hd": ((146, 38, 58), (152, 36, 60)), "kinds": ("FL", "FR", "RL", "RR", "TR", "HD")},
    # the tailgate folds down behind the bed; the tonneau rolls into its canister at the bed's front wall
    "Cybertruck": {"front": (87, 118), "rear": (62, 87), "y": (22, 74), "tr": ((8, 28, 68), (2, 26, 70)),
                   "hd": ((154, 34, 62), (159, 32, 64)), "kinds": ("FL", "FR", "RL", "RR", "TR", "TN", "HD")},
    # Model S: doors at its own seams, the liftgate's rear edge at x 16.4, the nose at 147 (car_models)
    "ModelS": {"front": (76.4, 105.3), "rear": (48.1, 76.4), "y": (23, 73), "tr": ((16.4, 36, 60), (10.5, 34, 62)),
               "hd": ((147, 38, 58), (153, 36, 60)), "kinds": ("FL", "FR", "RL", "RR", "TR", "HD")},
    # falcon: the rear doors are the Model X's falcon wings (spine y 48), drawn raised instead of swung out
    "ModelX": {"front": (85, 113), "rear": (49.9, 85), "y": (22, 74), "falcon": 48, "tr": ((18, 36, 60), (12, 34, 62)),
               "hd": ((149, 38, 58), (155, 36, 60)), "kinds": ("FL", "FR", "RL", "RR", "TR", "HD")},
    # Model Y L: the Model Y's front doors and frunk lid (door_FL / FR / HD); its rear doors reach 150 mm further back
    # (x 52.1) and the liftgate's rear edge is the longer tail (x 17.3, car_modelyl)
    "ModelYL": {"front": (78, 100), "rear": (52.1, 78), "y": (22, 74), "tr": ((17.3, 36, 60), (11.3, 34, 62)),
                "hd": ((146, 38, 58), (152, 36, 60)), "kinds": ("RL", "RR", "TR")},
    # Roadster: two doors (x 80.3-110.2) on its narrower body (y 25 / 71), the trunk lid's rear edge at x 43.8, the soft
    # top over the seats (st: x0 its rear edge, the roll hoop, where it folds; x1 the windscreen's top; y0, y1); the hood
    # is the Model Y's (nose x 146: plain door_HD)
    "Roadster": {"front": (80.3, 110.2), "rear": (80.3, 80.3), "y": (25, 71), "tr": ((43.8, 38, 58), (37.8, 36, 60)),
                 "st": (80.3, 99.8, 34, 62.3), "kinds": ("FL", "FR", "TR", "ST")},
}


def door_overlay(kind, g):
    def paint(c):
        if kind in ("RL", "RR") and g.get("falcon"):  # falcon wing: its footprint dashed, the raised wing up on the spine
            x0, x1 = g["rear"]
            side, spine = (g["y"][0], g["falcon"] - 1.5) if kind == "RL" else (g["y"][1], g["falcon"] + 1.5)
            for a, b, cc, d in ((x0, side, x1, side), (x0, side, x0, spine), (x1, side, x1, spine)):
                dashed(c, a, b, cc, d)
            tip = spine + (-8 if kind == "RL" else 8)  # the folded lower panel stands out a little past the hinge
            c.stroke([("M", x0 + 2, tip), ("L", x0 + 2, spine), ("H", x1 - 2), ("L", x1 - 2, tip)], w=2.8)
        elif kind in ("FL", "RL", "FR", "RR"):
            x0, x1 = g["front"] if kind[0] == "F" else g["rear"]
            y = g["y"][0] if kind[1] == "L" else g["y"][1]
            out = -17 if kind[1] == "L" else 17
            dashed(c, x0, y, x1, y)
            c.stroke([("M", x1, y), ("L", x1 - 18, y + out)], w=2.8)
        elif kind == "TR":  # trunk / tailgate (rear = left)
            (dx, dy0, dy1), (sx, sy0, sy1) = g["tr"]
            dashed(c, dx, dy0, dx, dy1)
            c.stroke([("M", sx, sy0), ("V", sy1)], w=2.8)
        elif kind == "TN":  # tonneau: the bed's outline, the cover rolled up at the front wall
            for x0, y0, x1, y1 in ((10, 25, 55, 25), (10, 71, 55, 71), (10, 25, 10, 71)):
                dashed(c, x0, y0, x1, y1)
            c.stroke([("M", 55, 24), ("V", 72)], w=2.8)
        elif kind == "ST":  # soft top: the roof's outline dashed, the top folded down at its rear edge
            x0, x1, y0, y1 = g["st"]
            for a, b, cc, d in ((x0, y0, x1, y0), (x0, y1, x1, y1), (x1, y0, x1, y1)):
                dashed(c, a, b, cc, d)
            c.stroke([("M", x0, y0 - 1), ("V", y1 + 1)], w=2.8)
        elif kind == "HD":  # hood (front = right)
            (dx, dy0, dy1), (sx, sy0, sy1) = g["hd"]
            dashed(c, dx, dy0, dx, dy1)
            c.stroke([("M", sx, sy0), ("V", sy1)], w=2.8)
    return paint


# ---- glyphs -------------------------------------------------------------------------
GLYPH_SETS = [
    # name, font file, size(1x), chars, fixed-advance digits
    ("big", "Inter-Light.ttf", 58, "0123456789", True),
    ("mid", "Inter-SemiBold.ttf", 20, "0123456789%", True),
    ("sm", "Inter-Regular.ttf", 17, "0123456789PRND", True),
    ("smb", "Inter-SemiBold.ttf", 17, "PRND", False),
]
# key, font, size (1x), text, letter spacing (px at 1x); the phone app's footer wordmark and trim (restyle mock);
# inf: the dashboard range with no limit (vanilla Gas Consumption 0, HUD.lua; the game's own fonts have no U+221E)
WORDS = [("kmh", "Inter-Regular.ttf", 14, "km/h", 0), ("km", "Inter-Regular.ttf", 17, "km", 0),
         ("inf", "Inter-Regular.ttf", 17, "\u221e", 0),
         ("wm_ModelY", "Inter-Light.ttf", 15, "MODEL Y", 5), ("trim_ModelY", "Inter-Regular.ttf", 13, "Performance", 0),
         ("wm_Model3", "Inter-Light.ttf", 15, "MODEL 3", 5), ("trim_Model3", "Inter-Regular.ttf", 13, "Performance", 0),
         ("wm_Cybertruck", "Inter-Light.ttf", 15, "CYBERTRUCK", 3), ("trim_Cybertruck", "Inter-Regular.ttf", 13, "Cyberbeast", 0),
         ("wm_ModelS", "Inter-Light.ttf", 15, "MODEL S", 5), ("trim_ModelS", "Inter-Regular.ttf", 13, "Plaid", 0),
         ("wm_ModelX", "Inter-Light.ttf", 15, "MODEL X", 5), ("trim_ModelX", "Inter-Regular.ttf", 13, "Plaid", 0),
         # the Model Y L comes in one version (Long Range All-Wheel Drive; "Model Y L AWD" / "Premium All-Wheel Drive")
         ("wm_ModelYL", "Inter-Light.ttf", 15, "MODEL Y L", 5),
         ("trim_ModelYL", "Inter-Regular.ttf", 13, "All-Wheel Drive", 0),
         # the Roadster 2.5 Sport (the car's own badge reads "Roadster Sport")
         ("wm_Roadster", "Inter-Light.ttf", 15, "ROADSTER", 5), ("trim_Roadster", "Inter-Regular.ttf", 13, "2.5 Sport", 0)]


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
        "falcon": ic_falcon,
        "nav": ic_nav, "shield": ic_shield, "chev": ic_chev, "chevdown": ic_chevdown, "back": ic_back, "close": ic_close,
        "wheel": ic_wheel, "pin": ic_pin, "tonneau": ic_tonneau, "powershare": ic_house, "softtop": ic_softtop,
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
    for model, g in DOOR_GEOM.items():
        for kind in g["kinds"]:
            c = Canvas(cw, ch, CAR_VB[0], CAR_VB[1])
            door_overlay(kind, g)(c)
            im = c.out()
            bb = im.getbbox()
            sp["door_" + kind + ("_" + model if model else "")] = (im.crop(bb), bb[0], bb[1], 0)
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
                           ("radial_charge", ic_plug, "#F3F5F7"), ("radial_lightbar", ic_lightbar, "#F3F5F7"),
                           ("radial_powershare", ic_house, "#F3F5F7"), ("radial_powershare_off", ic_house, "#6B737C"),
                           ("radial_outlet", ic_outlet, "#F3F5F7"), ("radial_outlet_off", ic_outlet, "#6B737C"),
                           ("radial_bdm", ic_biohazard, "#F3F5F7"), ("radial_chill", ic_chill, "#F3F5F7")):
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
