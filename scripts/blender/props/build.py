# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10"]
# ///
"""Tesla Gen 3 Wall Connector + Mobile Connector + V4 Supercharger + charge cable: Blender renders -> .pack + .tiles +
spriteModels + meshes + icons.

usage (repo root):
  uv run scripts/blender/props/build.py            # textures -> Blender (model, export, cells, icons) -> MOD files
  uv run scripts/blender/props/build.py --check    # read the MOD files back and assert the contract

Contract (knowledge base references/charger-art.md; Lua: shared/MinidoracatTesla/Chargers.lua cableExit,
client/MinidoracatTesla/Cable.lua):
  tileset minidoracat_tesla_01, tiledef MinidoracatTesla_tiles 7431, pack MinidoracatTesla. Sprite names are published:
  index 0..3 = Wall Connector, 8..11 = Mobile Connector, 16..19 = Supercharger (Facing S E N W each); 12 = Powershare's
  hidden generator (no image, only GeneratorSound). 0..3 and 16..19 draw the idle mesh (handle in the holster); 4..7
  and 20..23 are their plugged-in tiles (empty holster, CustomName "... Plugged"; Chargers.lua busy), which the server
  swaps in on plug / unplug.
  Wall Connector: Moveables WallObject, no wall flags (ISMoveableSpriteProps.lua:132-147,1782-1855). Mobile Connector:
  default MoveType Object (on the floor, ISMoveableSpriteProps.lua:143,1747-1772), no tools. Supercharger: on the floor,
  Electrician 6, solid (solidtrans + BlocksPlacement). The engine links the 4 faces of each by GroupName + CustomName
  (IsoWorld.java:1064-1160).
  spriteModels (common/media only, SpriteModelManager.java:30-41): model origin = tile centre on the floor; meshes are
  built for Facing S (Wall Connector back on the tile's north edge, front toward PZ south) with rotate (0,180,0);
  E/N/W turn it.
"""
from __future__ import annotations

import argparse
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pzfmt  # noqa: E402

REPO = HERE.parent.parent.parent
TEMP = REPO / "temp" / "props"
MODROOT = REPO / "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42"
MEDIA = MODROOT / "42" / "media"
COMMON = MODROOT / "common" / "media"
BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")

PACK = "MinidoracatTesla"
TILEDEF = "MinidoracatTesla_tiles"
FILE_NUMBER = 7431                 # family registry pz-family-docs/repos.md (7429 Economy, 7430 Knox Pass)
TILESET = "minidoracat_tesla_01"
TILESET_NUMBER = 1
CELL_W, CELL_H = 128, 256
FACINGS = ("S", "E", "N", "W")     # sprite index base + 0..3
# spriteModels rotate per facing (engine transform: tiles-and-sprite-models.md section 5; props_blender.pz_matrix):
# S (0,180,0) Blender +X = PZ east, +Y = north; E (0,-90,0) +X = north, +Y = west; N (0,0,0) +X = west, +Y = south;
# W (0,90,0) +X = south, +Y = east. The mesh's back sits at Blender +Y, so it lands on the wall each facing needs.
XFORM = {"S": (0.0, 180.0, 0.0), "E": (0.0, -90.0, 0.0), "N": (0.0, 0.0, 0.0), "W": (0.0, 90.0, 0.0)}
WC_MODEL = "MinidoracatTesla_WallConnector"
MC_MODEL = "MinidoracatTesla_MobileConnector"
SC_MODEL = "MinidoracatTesla_Supercharger"
# plugged-in meshes (empty holster): the server swaps a charger's idle <-> plugged tiles on plug / unplug (Chargers.lua
# busy, user 2026-11-09); they share the idle model's texture
WC_PLUGGED, SC_PLUGGED = WC_MODEL + "Plugged", SC_MODEL + "Plugged"
CABLE_MODELS = ("MinidoracatTesla_CableHang", "MinidoracatTesla_CableFloor")   # + one plug per car: cable_models()
ITEM_ICONS = {WC_MODEL: "wc_icon.png", "MinidoracatTesla_Cable": "cable_icon.png", MC_MODEL: "mc_icon.png",
              SC_MODEL: "sc_icon.png"}
# released icons this build leaves as shipped, not re-rendered: the Wall Connector's (Main 2026-11-09) and the cable's
# (shipped hook-shaped cable from 7704382; today's cable_icon.png render is a plain straight cable)
KEPT_ICONS = {WC_MODEL, "MinidoracatTesla_Cable"}
DEV = {WC_MODEL: "wc", WC_PLUGGED: "wc", MC_MODEL: "mc", SC_MODEL: "sc", SC_PLUGGED: "sc",
       "MinidoracatTesla_Cable": "cable"}   # model/icon -> device
ALL_DEVICES = ("wc", "mc", "sc", "cable")     # build.py --only / props_blender.py device names
# per-icon tone (gamma, lift) applied after fit_icon: the black Mobile Connector all but vanished on the crafting
# window's dark panel (mean RGB 28); user 2026-10-28 picked "B" from icon-compare.png (mean ~76, the Wall Connector's)
ICON_TONE = {MC_MODEL: (0.62, 0.06)}


def wc_props(facing: str) -> dict[str, str]:
    # Moveables: IsMoveAble/CustomName/GroupName/Facing/MoveType/CustomItem/Pick*/PlaceTool
    # (ISMoveableSpriteProps.lua:132-147); Electrician = screwdriver + Electricity level (ISMoveableDefinitions.lua:313,
    # ISMoveableSpriteProps.lua:485-492; PickUpLevel gates pick up and place). No WallN/WallW: placed as a plain
    # IsoObject (ISMoveableSpriteProps.lua:2330-2346). No CanScrap: the crafted charger cannot be scrapped for parts.
    return {"IsMoveAble": "", "CustomName": "Wall Connector", "GroupName": "Tesla", "Facing": facing,
            "MoveType": "WallObject", "CustomItem": f"Base.{WC_MODEL}",
            "PickUpTool": "Electrician", "PlaceTool": "Electrician", "PickUpLevel": "3"}


def mc_props(facing: str) -> dict[str, str]:
    # No MoveType: default Object, placed on the floor (ISMoveableSpriteProps.lua:143,1747-1772); no tools or level:
    # picked up and placed by hand.
    return {"IsMoveAble": "", "CustomName": "Mobile Connector", "GroupName": "Tesla", "Facing": facing,
            "CustomItem": f"Base.{MC_MODEL}"}


def sc_props(facing: str) -> dict[str, str]:
    # On the floor (default MoveType Object) like the Mobile Connector; Electrician 6 (contract). PickUpWeight = item
    # Weight 40 x 10 (ISMoveableSpriteProps.lua:148-149; the CustomItem script weight wins on pick up, Moveable.java:128).
    # Under 50: picking up needs room in the main inventory, capacity 50 (ISMoveableSpriteProps.lua:1207,
    # ItemContainer.java:237-269), so 50 with the screwdriver in hand never fits (E2E tesla-scart-1109a).
    # solidtrans + BlocksPlacement: blocks people, cars and building while the mod is loaded; placing a solid moveable
    # makes an IsoThumpable (ISMoveableSpriteProps.lua:2330-2399), whose own blocking flags Chargers.lua clears so a
    # removed mod leaves no invisible wall (contract "實心但移除 MOD 後不留隱形牆").
    return {"IsMoveAble": "", "CustomName": "Supercharger", "GroupName": "Tesla", "Facing": facing,
            "CustomItem": f"Base.{SC_MODEL}", "PickUpTool": "Electrician", "PlaceTool": "Electrician",
            "PickUpLevel": "6", "PickUpWeight": "400", "solidtrans": "", "BlocksPlacement": ""}


def plugged(props):
    """Plugged-in tiles: the idle tile's props with CustomName + " Plugged", so the engine links their four faces as a
    group of their own (IsoWorld.java:1064-1160)."""
    return lambda f: props(f) | {"CustomName": props(f)["CustomName"] + " Plugged"}


# first sprite index -> temp cell, model, props: idle and plugged-in Wall Connector and Supercharger
DEVICES = {0: ("wc", WC_MODEL, wc_props), 4: ("wcp", WC_PLUGGED, plugged(wc_props)), 8: ("mc", MC_MODEL, mc_props),
           16: ("sc", SC_MODEL, sc_props), 20: ("scp", SC_PLUGGED, plugged(sc_props))}
SPRITES = [(base + k, cell, model, props(f), f) for base, (cell, model, props) in DEVICES.items()
           for k, f in enumerate(FACINGS)]                                  # (index, temp cell, model, tile props, facing)
# Cybertruck Powershare's generator (Lua Chargers.lua T.PS_SPRITE; server Powershare.lua): an IsoGenerator on this tile.
# No image in the pack, so nothing is drawn or picked (IsoSprite.hasNoTextures, IsoSprite.java:850,1383-1385); the only
# property names its sounds (IsoGenerator.getSoundPrefix, IsoGenerator.java:744-751; scripts/sounds
# MinidoracatTesla_Powershare*). No solid / BlocksPlacement: it never blocks a square.
PS_INDEX = 12
PS_PROPS = {"GeneratorSound": "MinidoracatTesla_Powershare"}


def tile_list() -> list[dict[str, str]]:
    """One props dict per index 0..last; the unused indexes in between are empty tiles, as in vanilla tilesets."""
    tiles = [{} for _ in range(max(PS_INDEX, SPRITES[-1][0]) + 1)]
    for i, _, _, props, _ in SPRITES:
        tiles[i] = props
    tiles[PS_INDEX] = PS_PROPS
    return tiles


def check_powershare() -> None:
    """tile PS_INDEX = Chargers.lua T.PS_SPRITE = the hidden item's WorldObjectSprite (base:generator tag)."""
    sprite = f"{TILESET}_{PS_INDEX}"
    ch = (MEDIA / "lua" / "shared" / "MinidoracatTesla" / "Chargers.lua").read_text(encoding="utf-8")
    assert f'T.PS_SPRITE = "{sprite}"' in ch, f"Chargers.lua T.PS_SPRITE != {sprite}"
    items = (MEDIA / "scripts" / "items" / "MinidoracatTesla_items.txt").read_text(encoding="ascii")
    block = re.search(r"item MinidoracatTesla_Powershare\n\s*\{([^}]*)\}", items)
    assert block and f"WorldObjectSprite = {sprite}," in block.group(1) and "Tags = base:generator," in block.group(1), \
        "items.txt MinidoracatTesla_Powershare: base:generator with the Powershare sprite"
    sounds = (MEDIA / "scripts" / "sounds" / "MinidoracatTesla_sounds.txt").read_text(encoding="ascii")
    for s in ("Loop", "Starting", "Stopping"):
        assert f"sound {PS_PROPS['GeneratorSound']}{s}\n" in sounds, f"sound {PS_PROPS['GeneratorSound']}{s}"


# atlas rects shared with props_blender.py (PANEL, SW, CSW, MTOP, MSW): 256 px Wall Connector and Mobile Connector,
# 64 px cable. Model textures load at 256 by default (items-and-icons.md section 5), so the chargers ship at 256.
PANEL = (8, 2, 120, 254)
# rubber at 58 (was 40) on the Wall Connector and the drawn cable alike: daylight crushes darks to about half
# (charger-art.md), the idle mesh's wrapped cable is most of its outline, and the drawn cable continues its spare ring.
# white = the glass's thin rim: 240 came out 255 in daylight (tesla-scpolish-1109-art-d), so a grey edge round the glass
SW = {"white": ((136, 8), (208, 210, 213)), "black": ((196, 8), (32, 33, 36)), "rubber": ((136, 68), (58, 59, 63)),
      "handle": ((196, 68), (26, 26, 28)), "holster": ((136, 128), (14, 14, 16))}
CSW = {"rubber": ((0, 0), (58, 59, 63)), "handle": ((32, 0), (24, 24, 26)), "ring": ((0, 32), (92, 96, 100))}
MTOP = (8, 8, 120, 248)            # Mobile Connector 256 px atlas: box top
MSW = {"black": ((136, 8), (30, 31, 34)), "rubber": ((136, 68), (36, 37, 40)), "metal": ((196, 8), (176, 178, 182)),
       "adapter": ((196, 68), (26, 26, 28))}
SPANEL = (4, 2, 124, 196)          # Supercharger 256 px atlas: shell front (props_blender SC_SHELL, light baked here)
SLOGO = (4, 204, 252, 252)         # the shell band SC_LOGO_Z with the red TESLA, at twice SPANEL's texel density
# ramps 120 x 12 px, dark (u 0) .. lit (u 1); props_blender.sc_shade picks u per vertex (baked light). Daylight crushes
# the darks (charger-art.md): from 12 the east side came out 16 and the top 40 (tesla-scpolish-1109-art-a), so from 24.
SSW = {"black": ((132, 4), ((24, 24, 27), (140, 142, 148))), "base": ((132, 20), ((16, 16, 18), (104, 105, 110))),
       "holster": ((132, 36), ((28, 28, 31), (156, 158, 164))), "rubber": ((132, 52), ((22, 22, 24), (110, 112, 116))),
       "white": ((132, 68), ((112, 114, 116), (230, 231, 231)))}
SGRILLE = (132, 88, 252, 136)      # side ribs: the "black" ramp across, 12 ribs (4 px: 2 lit, 2 groove) down


def textures() -> None:
    from PIL import ImageDraw
    exp = TEMP / "export"
    exp.mkdir(parents=True, exist_ok=True)
    k = 4                                          # supersample, then LANCZOS down (items-and-icons.md section 5)
    im = Image.new("RGB", (256 * k, 256 * k), (32, 33, 36))
    d = ImageDraw.Draw(im)
    for name, ((x, y), rgb) in SW.items():
        d.rectangle((x * k, y * k, (x + 56) * k, (y + 56) * k), fill=rgb)
    x0, y0, x1, y1 = (v * k for v in PANEL)
    # glass with the light baked in, as on the Supercharger: daylight lifts the brights (texel 221 -> 241, >= 239 -> 255)
    # and the old 246 .. 224 glass came out a flat 255 (tesla-scpolish-1109-art-d), so it stays <= 234: lit from the
    # upper left front, greyer toward the shield outline (props_blender.shield, superellipse power 5) and the bottom,
    # a soft reflection left of centre
    b = blender_consts()
    w = b["WC_W"]
    for py in range(y0 - 2 * k, y1 + 2 * k, k):
        zt = min(1.0, max(0.0, 1 - (py / k + 0.5 - PANEL[1]) / (PANEL[3] - PANEL[1])))   # 0 bottom .. 1 top
        hw = (w / 2) * 0.95 * (0.80 + 0.20 * math.sin(math.pi * min(1.0, zt / 0.85) * 0.5) - 0.08 * max(0, zt - 0.85) / 0.15)
        for px in range(x0 - 2 * k, x1 + 2 * k, k):
            xn = ((px / k + 0.5 - PANEL[0]) / (PANEL[2] - PANEL[0]) - 0.5) * w * 1.04 / hw
            q = min(1.0, (abs(xn) ** 5 + (abs(2 * zt - 1) / 0.95) ** 5) ** 0.2)
            g = (214 + 14 * zt) * (0.86 + 0.14 * max(0.0, 1 - max(0.0, (q - 0.70) / 0.30)) ** 1.5)
            g = min(234.0, g + 9 * math.exp(-((xn + 0.42) / 0.16) ** 2))
            d.rectangle((px, py, px + k - 1, py + k - 1), fill=(round(g - 3), round(g - 1), round(g + 1)))
    cx, pw, ph = (x0 + x1) / 2, x1 - x0, y1 - y0
    # grey TESLA, 46 % of the panel wide, 28 % down (official front); texels are 538 / 560 px per unit across / down
    sx = pw * 0.46 / TESLA_W
    tesla(d, cx - pw * 0.23, y0 + ph * 0.28, sx, sx * (560 / 538.5), (128, 132, 138))
    for py in range(round(y0 + ph * 0.58), round(y0 + ph * 0.83)):  # green status strip, fading downward
        f = 1 - (py - (y0 + ph * 0.58)) / (ph * 0.25)
        d.rectangle((cx - 1.2 * k, py, cx + 1.2 * k, py), fill=(round(200 - 150 * f), 255 - round(30 * (1 - f)),
                                                                   round(200 - 140 * f)))
    im.resize((256, 256), Image.LANCZOS).save(exp / f"{WC_MODEL}.png", optimize=True)
    c = Image.new("RGB", (64, 64), (40, 41, 44))
    cd = ImageDraw.Draw(c)
    for (x, y), rgb in CSW.values():
        cd.rectangle((x, y, x + 31, y + 31), fill=rgb)
    c.save(exp / "MinidoracatTesla_Cable.png", optimize=True)
    m = Image.new("RGB", (256 * k, 256 * k), (30, 31, 34))
    d = ImageDraw.Draw(m)
    for (x, y), rgb in MSW.values():
        d.rectangle((x * k, y * k, (x + 56) * k, (y + 56) * k), fill=rgb)
    x0, y0, x1, y1 = (v * k for v in MTOP)
    cx, cy, pw, ph = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
    for py in range(y0, y1, k):                    # matte black top, a soft sheen toward the middle
        for px in range(x0, x1, k):
            g = round(52 - 20 * min(1.0, math.hypot((px - cx) / pw * 2, (py - cy) / ph * 2)))
            d.rectangle((px, py, px + k - 1, py + k - 1), fill=(g, g + 1, g + 4))
    lw, ly, grey = pw * 0.40, y0 + ph * 0.16, (150, 154, 160)   # T logo (north half): arched bar + tapering stem
    d.polygon([(cx - lw / 2, ly + lw * 0.12), (cx, ly), (cx + lw / 2, ly + lw * 0.12), (cx + lw / 2, ly + lw * 0.22),
               (cx, ly + lw * 0.12), (cx - lw / 2, ly + lw * 0.22)], fill=grey)
    d.polygon([(cx - lw * 0.10, ly + lw * 0.20), (cx + lw * 0.10, ly + lw * 0.20), (cx + lw * 0.035, ly + lw * 1.1),
               (cx - lw * 0.035, ly + lw * 1.1)], fill=grey)
    for i in range(5):                             # status lights: a row of 5 green LEDs down the middle (south half)
        sy = y0 + ph * (0.54 + 0.065 * i)
        d.rounded_rectangle((cx - 5 * k, sy, cx + 5 * k, sy + ph * 0.052), radius=2 * k, fill=(80, 235, 110))
    m.resize((256, 256), Image.LANCZOS).save(exp / f"{MC_MODEL}.png", optimize=True)
    sc_texture(exp, k)


# TESLA as drawn on the V4 shell (official photo v4-official.jpg): per letter (width, polygons) in units of the letter
# height, y down from the letter's top; letters 1.05 h apart. Bars end in a slant like the photo's. No font file.
TESLA = (
    (1.20, [[(0, 0), (1.2, 0), (1.14, 0.19), (0.06, 0.19)], [(0.51, 0.19), (0.69, 0.19), (0.69, 1), (0.51, 1)]]),
    (1.05, [[(0, y), (1.05, y), (1.0, y + 0.19), (0.05, y + 0.19)] for y in (0, 0.405, 0.81)]),
    (1.05, [[(0, 0), (1.05, 0), (1.05, 0.19), (0.19, 0.19), (0.19, 0.405), (1.05, 0.405), (1.05, 1), (-0.04, 1),
             (0, 0.81), (0.86, 0.81), (0.86, 0.595), (0, 0.595)]]),
    (0.95, [[(0, 0), (0.19, 0), (0.19, 0.81), (0.95, 0.81), (0.91, 1), (0, 1)]]),
    (1.05, [[(0, 0), (1.05, 0), (1.0, 0.19), (0.05, 0.19)],
            [(0, 0.39), (1.05, 0.39), (1.05, 1), (0.86, 1), (0.86, 0.58), (0.19, 0.58), (0.19, 1), (0, 1)]]),
)
TESLA_GAP, TESLA_H = 1.05, 0.05     # letter gap (letter heights) and the Supercharger's letter height (m)
TESLA_W = sum(w for w, _ in TESLA) + TESLA_GAP * (len(TESLA) - 1)     # word width, 9.5 h: 58 % of the shell


def tesla(d, left: float, top: float, sx: float, sy: float, fill) -> None:
    """The TESLA polygons with the word's top-left at (left, top), sx / sy px per letter height across / down."""
    for w, polys in TESLA:
        for poly in polys:
            d.polygon([(left + px * sx, top + py * sy) for px, py in poly], fill=fill)
        left += (w + TESLA_GAP) * sx


def sc_texture(exp: Path, k: int) -> None:
    """Supercharger atlas: shell (SPANEL) and its TESLA band (SLOGO) with the light baked in (convex shell lit from
    SC_LIGHT, greyer toward its outline, a soft reflection left of centre); ramps for every other face."""
    from PIL import ImageDraw
    b = blender_consts()
    xc, r, zb, zt, rv, rc, bulge = b["SC_SHELL"]
    lz0, lz1 = b["SC_LOGO_Z"]
    lx, ly, lz = b["SC_LIGHT"]
    ln = math.sqrt(lx * lx + ly * ly + lz * lz)

    def shell(x: float, z: float) -> float:
        u = (x - xc) / r
        slope = 2 * bulge * u / r                           # shell normal (slope, -1, 0) / |.|
        diff = max(0.0, (slope * lx - ly) / math.sqrt(slope * slope + 1) / ln)
        d = min(r - abs(x - xc), zt - z)
        if z < zb + rv:
            d = min(d, (1 - math.hypot(u, (z - zb - rv) / rv)) * min(r, rv))
        # in game the brights go up (texel 221 -> 241, art-a): the flanks and the outline need to be well below the centre
        v = (120 + 125 * diff) * (0.80 + 0.20 * min(1.0, max(0.0, d) / 0.10) ** 0.6)
        v += 7 * (z - zb) / (zt - zb) - 5 + 9 * math.exp(-((u + 0.35) / 0.12) ** 2)
        return min(234.0, v)

    s = Image.new("RGB", (256 * k, 256 * k), (26, 27, 30))
    d = ImageDraw.Draw(s)

    def ramp(lo, hi, px: int, x: int, width: int):
        t = min(1.0, max(0.0, (px / k + 0.5 - x - 2) / (width - 4)))
        return [a + (c - a) * t for a, c in zip(lo, hi)]

    for (x, y), (lo, hi) in SSW.values():
        for px in range(x * k, (x + 120) * k, k):
            d.rectangle((px, y * k, px + k - 1, (y + 12) * k - 1), fill=tuple(round(c) for c in ramp(lo, hi, px, x, 120)))
    x0, y0, x1, y1 = SGRILLE
    for py in range((y0 - 2) * k, (y1 + 2) * k, k):
        f = 1.0 if (py // k - y0) % 4 < 2 else 0.55       # rib face, groove
        for px in range(x0 * k, x1 * k, k):
            rgb = ramp(*SSW["black"][1], px, x0, x1 - x0)
            d.rectangle((px, py, px + k - 1, py + k - 1), fill=tuple(round(c * f) for c in rgb))
    for rect, z0, z1 in ((SPANEL, zb, zt), (SLOGO, lz0, lz1)):
        x0, y0, x1, y1 = rect
        for py in range((y0 - 2) * k, (y1 + 2) * k, k):
            z = z0 + (y1 - (py / k + 0.5)) / (y1 - y0) * (z1 - z0)
            for px in range((x0 - 2) * k, (x1 + 2) * k, k):
                g = shell(xc - r + (px / k + 0.5 - x0) / (x1 - x0) * 2 * r, z)
                d.rectangle((px, py, px + k - 1, py + k - 1), fill=(round(g - 2), round(g - 1), round(g)))
    x0, y0, x1, y1 = SLOGO
    sx, sy = TESLA_H * (x1 - x0) / (2 * r) * k, TESLA_H * (y1 - y0) / (lz1 - lz0) * k   # px per letter height
    tesla(d, (x0 + (x1 - x0) / 2) * k - sx * TESLA_W / 2, (y0 + y1) / 2 * k - sy / 2, sx, sy, (196, 32, 42))
    s.resize((256, 256), Image.LANCZOS).save(exp / f"{SC_MODEL}.png", optimize=True)


def fmt3(v) -> str:
    return " ".join(f"{x:.4f}" for x in v)


def sprite_models() -> str:
    tiles = "".join(
        "        tile\n        {\n"
        f"            xy = {i % 8} {i // 8},\n"
        f"            modelScript = Base.{model},\n"
        "            translate = 0.0000 0.0000 0.0000,\n"
        f"            rotate = {fmt3(XFORM[f])},\n"
        "            scale = 1.0000,\n"
        "        }\n" for i, _, model, _, f in SPRITES)
    return ("spriteModel\n{\n    VERSION = 1,\n\n    tileset\n    {\n"
            f"        name = {TILESET},\n\n" + tiles + "    }\n}\n")


def assets() -> list[tuple[str, Path, Path]]:
    """(device, temp export, MOD path) of every model asset."""
    exp = TEMP / "export"
    out = [(DEV[m], exp / f"{m}.glb", MEDIA / "models_X" / "IsoObject" / f"{m}.glb") for _, m, _ in DEVICES.values()]
    out += [(DEV[m], exp / f"{m}.png", MEDIA / "textures" / "IsoObject" / f"{m}.png")
            for m in (WC_MODEL, MC_MODEL, SC_MODEL)]                        # the plugged meshes share these
    out += [("cable", exp / f"{m}.fbx", MEDIA / "models_X" / "WorldItems" / f"{m}.fbx") for m in cable_models()]
    out.append(("cable", exp / "MinidoracatTesla_Cable.png",
                MEDIA / "textures" / "WorldItems" / "MinidoracatTesla_Cable.png"))
    return out


def run_blender(only: set[str], cpu: bool) -> None:
    TEMP.mkdir(parents=True, exist_ok=True)
    cmd = [str(BLENDER), "-b", "--factory-startup", "--python", str(HERE / "props_blender.py"), "--", str(TEMP),
           *(["--cpu"] if cpu else []), *sorted(only)]
    subprocess.run(cmd, check=True)


def pack_cells() -> dict[int, Image.Image]:
    """The 128x256 cells in the MOD's current .pack, by sprite index (devices not rebuilt keep their exact pixels)."""
    out = {}
    for p in pzfmt.read_pack((MEDIA / "texturepacks" / f"{PACK}.pack").read_bytes()):
        for name, x, y, w, h, ox, oy, fx, fy in p["entries"]:
            c = Image.new("RGBA", (fx, fy), (0, 0, 0, 0))
            c.paste(p["image"].convert("RGBA").crop((x, y, x + w, y + h)), (ox, oy))
            out[int(name.rsplit("_", 1)[1])] = c
    return out


# sha256[:16] of each released cell's 128x256 RGBA pixels (pack_cells), taken from the 0.5.0 pack: --check fails if a
# rebuild changes a published 2D cell (rebuild one device with --only; a deliberate redraw updates the hash here).
FROZEN = {0: "1ddc6f8a86f22169", 1: "dc88bfbcfb84a63d", 2: "49ea9e0fb2e547db", 3: "1569c9f779641eae",
          8: "1e527b0e058a8210", 9: "dab4382cc6741891", 10: "d253843dbf463101", 11: "6ccd337485e90974"}


def fit_icon(img: Image.Image, size: int = 32) -> Image.Image:
    """Item icon (items-and-icons.md section 4): 32x32 transparent, content ~28 px centred, 1 px dark outline."""
    from PIL import ImageFilter
    img = img.convert("RGBA")
    img = img.crop(img.getbbox())
    s = (size - 4) / max(img.size)
    img = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
    a = img.getchannel("A").point(lambda v: 255 if v >= 96 else 0)
    img.putalpha(a)
    body = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    body.paste(img, ((size - img.width) // 2, (size - img.height) // 2), img)
    edge = body.getchannel("A").filter(ImageFilter.MaxFilter(3))
    out = Image.new("RGBA", (size, size), (0x1c, 0x1a, 0x18, 0))
    out.putalpha(edge)
    out.alpha_composite(body)
    return out


def tone(img: Image.Image, gamma: float, lift: float) -> Image.Image:
    """Lift dark RGB: c' = lift + (1 - lift) * c ** gamma (0..1); alpha untouched."""
    lut = [round(255 * (lift + (1 - lift) * (v / 255) ** gamma)) for v in range(256)]
    r, g, b, a = img.split()
    return Image.merge("RGBA", (r.point(lut), g.point(lut), b.point(lut), a))


def build(skip_blender: bool, only: set[str], cpu: bool) -> None:
    if not skip_blender:
        textures()
        run_blender(only, cpu)
    old = pack_cells()
    # a rebuilt device's new cells, except published ones (FROZEN keeps their 0.5.0 pixels; the Wall Connector's idle
    # 0..3 are drawn only by the build cursor, Main 2026-11-09; a deliberate redraw edits FROZEN)
    cells = [(i, Image.open(TEMP / "cells" / f"{cell}_{f}.png").convert("RGBA")
              if DEV[model] in only and i not in FROZEN else old[i]) for i, cell, model, _, f in SPRITES]
    for _, c in cells:
        assert c.size == (CELL_W, CELL_H), c.size
    sheet = Image.new("RGBA", (CELL_W * 8, CELL_H * (SPRITES[-1][0] // 8 + 1)), (0, 0, 0, 0))
    entries = []
    for i, c in cells:
        cx, cy = i % 8 * CELL_W, i // 8 * CELL_H
        sheet.paste(c, (cx, cy))
        x0, y0, x1, y1 = c.getbbox() or (0, 0, 1, 1)
        entries.append((f"{TILESET}_{i}", cx + x0, cy + y0, x1 - x0, y1 - y0, x0, y0, CELL_W, CELL_H))
    (MEDIA / "texturepacks").mkdir(parents=True, exist_ok=True)
    (MEDIA / "texturepacks" / f"{PACK}.pack").write_bytes(pzfmt.write_pack([(f"{PACK}0", sheet, entries)]))
    ts = {"name": TILESET, "image": f"{TILESET}.png", "w": 8, "h": sheet.height // CELL_H, "number": TILESET_NUMBER,
          "tiles": tile_list()}
    (MEDIA / f"{TILEDEF}.tiles").write_bytes(pzfmt.write_tiles([ts]))
    if skip_blender:
        print(f"wrote {PACK}.pack + {TILEDEF}.tiles only (--skip-blender)")
        return
    COMMON.mkdir(parents=True, exist_ok=True)
    (COMMON / "spriteModels.txt").write_text(sprite_models(), encoding="ascii", newline="\n")
    copied = [(src, dst) for dev, src, dst in assets() if dev in only]
    for src, dst in copied:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
    icons = {item: src for item, src in ITEM_ICONS.items() if DEV[item] in only and item not in KEPT_ICONS}
    for item, src in icons.items():
        icon = fit_icon(Image.open(TEMP / "icons" / src))
        if item in ICON_TONE:
            icon = tone(icon, *ICON_TONE[item])
        icon.save(MEDIA / "textures" / f"Item_{item}.png", optimize=True)
    print(f"wrote {len(cells)} sprites ({sorted(only)} rebuilt), {PACK}.pack, {TILEDEF}.tiles, spriteModels.txt, "
          f"{len(copied)} assets, {len(icons)} icons")


def blender_consts() -> dict:
    """Top-level literal assignments of props_blender.py (it imports bpy, so it is parsed, not imported)."""
    import ast
    out = {}
    for node in ast.parse((HERE / "props_blender.py").read_text(encoding="utf-8")).body:
        if isinstance(node, ast.Assign):
            try:
                value = ast.literal_eval(node.value)
            except (ValueError, TypeError, SyntaxError):
                continue
            t = node.targets[0]
            names = [e.id for e in t.elts] if isinstance(t, ast.Tuple) else [t.id]
            values = value if isinstance(t, ast.Tuple) else (value,)
            out |= dict(zip(names, values))
    return out


def cable_models() -> tuple[str, ...]:
    return (*CABLE_MODELS, *blender_consts()["PLUGS"])


def check_geometry() -> None:
    """One set of numbers: props_blender.py meshes = build.py atlas/spriteModels = Cable.lua = Chargers.lua sprites and
    cableExit = Core.lua T.Specs plug."""
    b = blender_consts()
    assert b["XFORM"] == XFORM and b["PANEL"] == PANEL and b["MTOP"] == MTOP and b["SPANEL"] == SPANEL \
        and b["SLOGO"] == SLOGO and b["SGRILLE"] == SGRILLE, "props_blender.py XFORM or atlas rects differ"
    assert b["MSW"] == {k: xy for k, (xy, _) in MSW.items()}, "Mobile Connector atlas"
    assert b["SSW"] == {k: xy for k, (xy, _) in SSW.items()}, "Supercharger atlas"
    assert b["SW"] == {k: xy for k, (xy, _) in SW.items()} and b["CSW"] == {k: xy for k, (xy, _) in CSW.items()}, "atlas"
    b["EXIT_Z"] = b["WC_Z0"]
    lua = (MEDIA / "lua" / "client" / "MinidoracatTesla" / "Cable.lua").read_text(encoding="utf-8")
    lv = {k: float(v) for k, v in re.findall(r"^C\.(\w+) = ([0-9.]+)", lua, re.M)}
    assert lv["HANG_REACH"] == b["HANG_REACH"] and lv["PLUG_REACH"] == b["PLUG_REACH"], (lv, b)
    # one plug per car: props_blender.py PLUGS (mesh -> handle height) = Core.lua T.Specs plug { item, z }, and each
    # plug item draws its own model
    core = (MEDIA / "lua" / "shared" / "MinidoracatTesla" / "Core.lua").read_text(encoding="utf-8")
    specs = {m: float(z) for m, z in re.findall(r'plug = \{ item = "Base\.(\w+)", z = ([0-9.]+) \}', core)}
    assert specs == b["PLUGS"], f"Core.lua T.Specs plug {specs} != props_blender.py PLUGS {b['PLUGS']}"
    assert len(specs) == core.count("plug = {"), "Core.lua: a plug entry not in the { item = ..., z = ... } form"
    items = (MEDIA / "scripts" / "items" / "MinidoracatTesla_cable.txt").read_text(encoding="ascii")
    for m in specs:
        assert re.search(rf"item {m}\n\s*\{{[^}}]*WorldStaticModel = Base\.{m},[^}}]*Hidden = true,", items), f"item {m}"
    # Chargers.lua: each kind's sprites = our idle tile names per facing, busy = the plugged ones (only kinds that have
    # a plugged mesh), cableExit = the mesh's exit point (the plugged mesh's: Cable.lua draws from it)
    ch = (MEDIA / "lua" / "shared" / "MinidoracatTesla" / "Chargers.lua").read_text(encoding="utf-8")
    blocks = dict(re.findall(r'kind = "(\w+)",(.*?)\n    \},', ch, re.S))
    kinds = {model.removeprefix("MinidoracatTesla_"): model for model in (WC_MODEL, MC_MODEL, SC_MODEL)}
    busy = {WC_MODEL: WC_PLUGGED, SC_MODEL: SC_PLUGGED}
    assert blocks.keys() == kinds.keys() and ch.count("cableExit =") == len(kinds), (blocks.keys(), kinds)
    want_exit = {"WallConnector": (0.0, -b["EXIT_Y"], round(b["EXIT_Z"] / 2.44949, 3)),
                 "MobileConnector": (0.0, -b["MC_EXIT_Y"], 0.0),
                 "Supercharger": (b["SC_EXIT"][0], -b["SC_EXIT"][1], 0.0)}   # on the floor: no hang segment
    for kind, body in blocks.items():
        for key, model in (("sprites", kinds[kind]), ("busy", busy.get(kinds[kind]))):
            want = {f: f"{TILESET}_{i}" for i, _, m, _, f in SPRITES if m == model}
            table = re.search(rf"\b{key} = \{{([^}}]*)\}}", body)
            got = dict(re.findall(r'(\w) = "(\w+)"', table.group(1))) if table else {}
            assert got == want, f"Chargers.lua {kind} {key} {got} != {want}"
        want = {f: f"{TILESET}_{i}" for i, _, m, _, f in SPRITES if m == kinds[kind]}
        m = re.search(r"cableExit\s*=\s*\{\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*\}", body)
        got = m and tuple(float(x) for x in m.groups())
        assert got == want_exit[kind], f"Chargers.lua {kind} cableExit {got} != {want_exit[kind]}"
        # the item placed from the inventory: Chargers.lua item = tile CustomItem, and the item script's WorldObjectSprite
        # is this device's Facing S sprite (ISMoveablesAction finds the item by it; a wrong one places the wrong tile, or nothing)
        assert re.search(rf'item = "Base\.{kinds[kind]}"', body), f"Chargers.lua {kind} item"
        moveables = (MEDIA / "scripts" / "items" / "MinidoracatTesla_items.txt").read_text(encoding="ascii")
        block = re.search(rf"item {kinds[kind]}\n\s*\{{([^}}]*)\}}", moveables)
        assert block and f"WorldObjectSprite = {want['S']}," in block.group(1) and "ItemType = base:moveable," in block.group(1), \
            f"items.txt {kinds[kind]}: moveable with WorldObjectSprite = {want['S']}"
        # a tile PickUpWeight = the item's Weight x 10 (what the cursor shows and checks, ISMoveableSpriteProps.lua:148-149)
        # and under the 50 main inventory capacity, or it can never be picked up (ISMoveableSpriteProps.lua:1207)
        puw = props_of(model=kinds[kind]).get("PickUpWeight")
        if puw:
            w = re.search(r"Weight = ([0-9.]+),", block.group(1))
            assert w and float(w.group(1)) * 10 == float(puw) and float(w.group(1)) < 50, \
                f"items.txt {kinds[kind]} Weight {w and w.group(1)} vs tile PickUpWeight {puw}"


def props_of(model: str) -> dict[str, str]:
    return next(props for _, _, m, props, _ in SPRITES if m == model)


def check() -> None:
    tiles = pzfmt.read_tiles((MEDIA / f"{TILEDEF}.tiles").read_bytes())
    assert [t["name"] for t in tiles] == [TILESET] and tiles[0]["number"] == TILESET_NUMBER, tiles
    assert tiles[0]["tiles"] == tile_list(), tiles[0]["tiles"]
    assert [i for i, *_ in SPRITES] == [*range(0, 8), *range(8, 12), *range(16, 24)], \
        "sprite indexes changed (0..3, 8..11, 16..19 are published)"
    solid = {"solidtrans", "BlocksPlacement"}
    for i, t in enumerate(tiles[0]["tiles"]):
        assert not {"WallN", "WallW", "solid", "CanScrap"} & t.keys(), t
        # only the Supercharger blocks (Chargers.lua clears the IsoThumpable's own flags: no wall left after removal)
        assert solid & t.keys() == (solid if 16 <= i <= 23 else set()), (i, t)
    pages = pzfmt.read_pack((MEDIA / "texturepacks" / f"{PACK}.pack").read_bytes())
    names = [e[0] for p in pages for e in p["entries"]]
    assert names == [f"{TILESET}_{i}" for i, *_ in SPRITES], names
    for p in pages:
        for e in p["entries"]:
            assert e[7:] == (CELL_W, CELL_H) and e[3] > 8 and e[4] > 8, e     # not an empty cell
    import hashlib
    got = {i: hashlib.sha256(c.tobytes()).hexdigest()[:16] for i, c in pack_cells().items() if i in FROZEN}
    assert got == FROZEN, f"published 2D cells changed: {got}"
    info = (MEDIA.parent / "mod.info").read_text(encoding="utf-8")
    assert f"pack={PACK}\n" in info and f"tiledef={TILEDEF} {FILE_NUMBER}\n" in info, "mod.info pack=/tiledef="
    sm = (COMMON / "spriteModels.txt").read_text(encoding="ascii")
    assert sm == sprite_models(), "spriteModels.txt is stale: rebuild"
    xyz = re.findall(r"xy = (\d) (\d),\s*modelScript = Base\.(\w+),\s*translate = [^,]+,\s*rotate = ([^,]+),", sm)
    assert xyz == [(str(i % 8), str(i // 8), m, fmt3(XFORM[f])) for i, _, m, _, f in SPRITES], xyz
    models = (MEDIA / "scripts" / "models" / "MinidoracatTesla_props.txt").read_text(encoding="ascii")
    for _, m, _ in DEVICES.values():       # static IsoObject models for spriteModels; plugged ones use the idle texture
        tex = m.removesuffix("Plugged")
        assert re.search(rf"model {m}\n\s*\{{\s*mesh = IsoObject/{m},\s*texture = IsoObject/{tex},\s*static = true,"
                         rf"\s*scale = 1\.0,\s*undoCoreScale = true,\s*\}}", models), m
    for m in cable_models():
        assert f"model {m}\n" in models, m
    for _, _, dst in assets():
        assert dst.exists() and dst.stat().st_size > 0, dst
    for item in ITEM_ICONS:
        icon = Image.open(MEDIA / "textures" / f"Item_{item}.png")
        assert icon.size == (32, 32) and icon.mode == "RGBA", (item, icon.size, icon.mode)
    check_geometry()
    check_powershare()
    print("check OK: tiles, pack, published cells, mod.info, spriteModels, model script, assets, icons, geometry "
          "constants, Powershare tile")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--skip-blender", action="store_true", help="rebuild .pack/.tiles from existing temp cells")
    ap.add_argument("--only", nargs="+", choices=ALL_DEVICES, default=list(ALL_DEVICES),
                    help="rebuild only these devices; the others keep their MOD files and 2D cells")
    ap.add_argument("--cpu", action="store_true", help="render with Cycles on the CPU (no GPU, e.g. the VM)")
    a = ap.parse_args()
    check() if a.check else build(a.skip_blender, set(a.only), a.cpu)
