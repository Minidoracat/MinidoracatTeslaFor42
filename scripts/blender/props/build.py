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
  hidden generator (no image, only GeneratorSound).
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
CABLE_MODELS = ("MinidoracatTesla_CableHang", "MinidoracatTesla_CableFloor")   # + one plug per car: cable_models()
ITEM_ICONS = {WC_MODEL: "wc_icon.png", "MinidoracatTesla_Cable": "cable_icon.png", MC_MODEL: "mc_icon.png",
              SC_MODEL: "sc_icon.png"}
DEV = {WC_MODEL: "wc", MC_MODEL: "mc", SC_MODEL: "sc", "MinidoracatTesla_Cable": "cable"}   # model/icon -> device
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


# first sprite index -> cell, model, props
DEVICES = {0: ("wc", WC_MODEL, wc_props), 8: ("mc", MC_MODEL, mc_props), 16: ("sc", SC_MODEL, sc_props)}
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
SW = {"white": ((136, 8), (240, 242, 244)), "black": ((196, 8), (32, 33, 36)), "rubber": ((136, 68), (40, 41, 44)),
      "handle": ((196, 68), (26, 26, 28)), "holster": ((136, 128), (14, 14, 16))}
CSW = {"rubber": ((0, 0), (40, 41, 44)), "handle": ((32, 0), (24, 24, 26)), "ring": ((0, 32), (92, 96, 100))}
MTOP = (8, 8, 120, 248)            # Mobile Connector 256 px atlas: box top
MSW = {"black": ((136, 8), (30, 31, 34)), "rubber": ((136, 68), (36, 37, 40)), "metal": ((196, 8), (176, 178, 182)),
       "adapter": ((196, 68), (26, 26, 28))}
SPANEL = (8, 2, 120, 254)          # Supercharger 256 px atlas: shell front, x -0.40..0.40, z 0.16 (U tip)..1.90
SSW = {"white": ((136, 8), (226, 228, 228)), "black": ((196, 8), (26, 27, 30)), "base": ((136, 68), (16, 16, 18)),
       "rubber": ((196, 68), (34, 35, 38)), "holster": ((136, 128), (12, 12, 14))}


def wordmark(d, x0: float, y0: float, w: float, h: float, fill) -> None:
    """Geometric T E S L A (the logo is allowed: decisions.md 2026-10-23); letters are bars, no font file."""
    lw = w / 9.0                                   # letter width; 5 letters + 4 gaps
    t = h * 0.22                                   # stroke

    def bar(x, y, bw, bh):
        d.rectangle((x, y, x + bw, y + bh), fill=fill)
    xs = [x0 + i * lw * 2 for i in range(5)]
    bar(xs[0], y0, lw, t)                                                   # T
    bar(xs[0] + lw / 2 - t / 2, y0 + t * 1.4, t, h - t * 1.4)
    for k in (0, 0.5, 1):                                                   # E: three bars
        bar(xs[1], y0 + k * (h - t), lw, t)
    bar(xs[2], y0, lw, t)                                                   # S
    bar(xs[2], y0, t, h / 2)
    bar(xs[2], y0 + h / 2 - t / 2, lw, t)
    bar(xs[2] + lw - t, y0 + h / 2, t, h / 2)
    bar(xs[2], y0 + h - t, lw, t)
    bar(xs[3], y0, t, h)                                                    # L
    bar(xs[3], y0 + h - t, lw, t)
    d.polygon([(xs[4], y0 + h), (xs[4] + lw / 2 - t / 2, y0 + t * 1.4), (xs[4] + lw / 2 + t / 2, y0 + t * 1.4),
               (xs[4] + lw, y0 + h), (xs[4] + lw - t, y0 + h), (xs[4] + lw / 2, y0 + t * 2.6),
               (xs[4] + t, y0 + h)], fill=fill)                             # A: chevron + top bar
    bar(xs[4], y0, lw, t)


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
    for py in range(y0 - 2 * k, y1 + 2 * k):      # glass: cool white, darker toward the bottom and the flanks
        t = (py - y0) / (y1 - y0)
        for px in range(x0 - 2 * k, x1 + 2 * k, k):
            e = abs((px - (x0 + x1) / 2) / ((x1 - x0) / 2))
            g = 246 - 22 * t - 26 * max(0.0, e - 0.55) / 0.45
            d.rectangle((px, py, px + k - 1, py), fill=(round(g - 3), round(g - 1), round(g + 1)))
    cx, pw, ph = (x0 + x1) / 2, x1 - x0, y1 - y0
    wordmark(d, cx - pw * 0.23, y0 + ph * 0.28, pw * 0.46, ph * 0.026, (128, 132, 138))
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
    s = Image.new("RGB", (256 * k, 256 * k), (26, 27, 30))
    d = ImageDraw.Draw(s)
    for (x, y), rgb in SSW.values():
        d.rectangle((x * k, y * k, (x + 56) * k, (y + 56) * k), fill=rgb)
    x0, y0, x1, y1 = (v * k for v in SPANEL)
    cx, pw, ph = (x0 + x1) / 2, x1 - x0, y1 - y0
    for px in range(x0 - 2 * k, x1 + 2 * k, k):  # pearl white shell: darker toward the curved flanks, a soft highlight
        e = (px - cx) / (pw / 2)
        g = 244 - 26 * e * e + 6 * math.exp(-((e + 0.25) / 0.18) ** 2)
        for py in range(y0 - 2 * k, y1 + 2 * k, k):
            t = (py - y0) / ph                     # 0 top .. 1 bottom (U tip)
            v = min(255.0, g - 8 * t)
            d.rectangle((px, py, px + k - 1, py + k - 1), fill=(round(v - 2), round(v - 1), round(v)))
    # red TESLA across the upper shell (official photo: ~45 % of the width, about 1.68 m up)
    wordmark(d, cx - pw * 0.24, y0 + ph * 0.115, pw * 0.48, ph * 0.026, (196, 32, 42))
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
    out = [(DEV[m], exp / f"{m}{ext}", MEDIA / sub / "IsoObject" / f"{m}{ext}")
           for m in (WC_MODEL, MC_MODEL, SC_MODEL) for sub, ext in (("models_X", ".glb"), ("textures", ".png"))]
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
    cells = [(i, Image.open(TEMP / "cells" / f"{cell}_{f}.png").convert("RGBA") if cell in only else old[i])
             for i, cell, _, _, f in SPRITES]
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
    icons = {item: src for item, src in ITEM_ICONS.items() if DEV[item] in only}
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
    assert b["XFORM"] == XFORM and b["PANEL"] == PANEL and b["MTOP"] == MTOP and b["SPANEL"] == SPANEL, \
        "props_blender.py XFORM/PANEL/MTOP/SPANEL differ"
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
    # Chargers.lua: each kind's sprites = our tile names per facing, cableExit = the mesh's exit point
    ch = (MEDIA / "lua" / "shared" / "MinidoracatTesla" / "Chargers.lua").read_text(encoding="utf-8")
    blocks = dict(re.findall(r'kind = "(\w+)",(.*?)\n    \},', ch, re.S))
    kinds = {model.removeprefix("MinidoracatTesla_"): model for _, model, _ in DEVICES.values()}
    assert blocks.keys() == kinds.keys() and ch.count("cableExit =") == len(kinds), (blocks.keys(), kinds)
    want_exit = {"WallConnector": (0.0, -b["EXIT_Y"], round(b["EXIT_Z"] / 2.44949, 3)),
                 "MobileConnector": (0.0, -b["MC_EXIT_Y"], 0.0),
                 "Supercharger": (b["SC_EXIT"][0], -b["SC_EXIT"][1], 0.0)}   # on the floor: no hang segment
    for kind, body in blocks.items():
        want = {f: f"{TILESET}_{i}" for i, _, model, _, f in SPRITES if model == kinds[kind]}
        got = dict(re.findall(r'(\w) = "(\w+)"', re.search(r"sprites = \{([^}]*)\}", body).group(1)))
        assert got == want, f"Chargers.lua {kind} sprites {got} != {want}"
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
    assert [i for i, *_ in SPRITES] == [0, 1, 2, 3, 8, 9, 10, 11, 16, 17, 18, 19], "published sprite indexes changed"
    solid = {"solidtrans", "BlocksPlacement"}
    for i, t in enumerate(tiles[0]["tiles"]):
        assert not {"WallN", "WallW", "solid", "CanScrap"} & t.keys(), t
        # only the Supercharger blocks (Chargers.lua clears the IsoThumpable's own flags: no wall left after removal)
        assert solid & t.keys() == (solid if 16 <= i <= 19 else set()), (i, t)
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
    for m in (WC_MODEL, MC_MODEL, SC_MODEL):       # static IsoObject models for spriteModels
        assert re.search(rf"model {m}\n\s*\{{\s*mesh = IsoObject/{m},\s*texture = IsoObject/{m},\s*static = true,"
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
