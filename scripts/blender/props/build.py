# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10"]
# ///
"""Tesla Gen 3 Wall Connector + charge cable: Blender renders -> .pack + .tiles + spriteModels + meshes + icons.

usage (repo root):
  uv run scripts/blender/props/build.py            # textures -> Blender (model, export, cells, icons) -> MOD files
  uv run scripts/blender/props/build.py --check    # read the MOD files back and assert the contract

Contract (knowledge base references/charger-art.md; Lua: shared/MinidoracatTesla/Chargers.lua cableExit,
client/MinidoracatTesla/Cable.lua):
  tileset minidoracat_tesla_01, tiledef MinidoracatTesla_tiles 7431, pack MinidoracatTesla; index 0..3 = Facing S E N W.
  Moveables WallObject, no wall flags (ISMoveableSpriteProps.lua:132-147,1782-1855); the engine links the 4 faces by
  GroupName + CustomName (IsoWorld.java:1064-1160).
  spriteModels (common/media only, SpriteModelManager.java:30-41): model origin = tile centre on the floor; the mesh is
  built for Facing S (back on the tile's north edge, front toward PZ south) with rotate (0,180,0); E/N/W turn it.
"""
from __future__ import annotations

import argparse
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
FACINGS = ("S", "E", "N", "W")     # sprite index 0..3
# spriteModels rotate per facing (engine transform: tiles-and-sprite-models.md section 5; props_blender.pz_matrix):
# S (0,180,0) Blender +X = PZ east, +Y = north; E (0,-90,0) +X = north, +Y = west; N (0,0,0) +X = west, +Y = south;
# W (0,90,0) +X = south, +Y = east. The mesh's back sits at Blender +Y, so it lands on the wall each facing needs.
XFORM = {"S": (0.0, 180.0, 0.0), "E": (0.0, -90.0, 0.0), "N": (0.0, 0.0, 0.0), "W": (0.0, 90.0, 0.0)}
WC_MODEL = "MinidoracatTesla_WallConnector"
CABLE_MODELS = ("MinidoracatTesla_CableHang", "MinidoracatTesla_CableFloor")   # + one plug per car: cable_models()
ITEM_ICONS = {"MinidoracatTesla_WallConnector": "wc_icon.png", "MinidoracatTesla_Cable": "cable_icon.png"}


def tile_props(facing: str) -> dict[str, str]:
    # Moveables: IsMoveAble/CustomName/GroupName/Facing/MoveType/CustomItem/Pick*/PlaceTool
    # (ISMoveableSpriteProps.lua:132-147); Electrician = screwdriver + Electricity level (ISMoveableDefinitions.lua:313,
    # ISMoveableSpriteProps.lua:485-492; PickUpLevel gates pick up and place). No WallN/WallW: placed as a plain
    # IsoObject (ISMoveableSpriteProps.lua:2330-2346). No CanScrap: the crafted charger cannot be scrapped for parts.
    return {"IsMoveAble": "", "CustomName": "Wall Connector", "GroupName": "Tesla", "Facing": facing,
            "MoveType": "WallObject", "CustomItem": "Base.MinidoracatTesla_WallConnector",
            "PickUpTool": "Electrician", "PlaceTool": "Electrician", "PickUpLevel": "3"}

# atlas rects shared with props_blender.py (PANEL, SW, CSW): 256 px Wall Connector, 64 px cable. Model textures load
# at 256 by default (items-and-icons.md section 5), so the Wall Connector ships at 256.
PANEL = (8, 2, 120, 254)
SW = {"white": ((136, 8), (240, 242, 244)), "black": ((196, 8), (32, 33, 36)), "rubber": ((136, 68), (40, 41, 44)),
      "handle": ((196, 68), (26, 26, 28)), "holster": ((136, 128), (14, 14, 16))}
CSW = {"rubber": ((0, 0), (40, 41, 44)), "handle": ((32, 0), (24, 24, 26)), "ring": ((0, 32), (92, 96, 100))}


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



def fmt3(v) -> str:
    return " ".join(f"{x:.4f}" for x in v)


def sprite_models() -> str:
    tiles = "".join(
        "        tile\n        {\n"
        f"            xy = {i % 8} {i // 8},\n"
        f"            modelScript = Base.{WC_MODEL},\n"
        "            translate = 0.0000 0.0000 0.0000,\n"
        f"            rotate = {fmt3(XFORM[f])},\n"
        "            scale = 1.0000,\n"
        "        }\n" for i, f in enumerate(FACINGS))
    return ("spriteModel\n{\n    VERSION = 1,\n\n    tileset\n    {\n"
            f"        name = {TILESET},\n\n" + tiles + "    }\n}\n")


def assets() -> list[tuple[Path, Path]]:
    exp = TEMP / "export"
    out = [(exp / f"{WC_MODEL}.glb", MEDIA / "models_X" / "IsoObject" / f"{WC_MODEL}.glb"),
           (exp / f"{WC_MODEL}.png", MEDIA / "textures" / "IsoObject" / f"{WC_MODEL}.png")]
    out += [(exp / f"{m}.fbx", MEDIA / "models_X" / "WorldItems" / f"{m}.fbx") for m in cable_models()]
    out.append((exp / "MinidoracatTesla_Cable.png", MEDIA / "textures" / "WorldItems" / "MinidoracatTesla_Cable.png"))
    return out


def run_blender() -> None:
    TEMP.mkdir(parents=True, exist_ok=True)
    cmd = [str(BLENDER), "-b", "--factory-startup", "--python", str(HERE / "props_blender.py"), "--", str(TEMP)]
    subprocess.run(cmd, check=True)


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


def build(skip_blender: bool) -> None:
    if not skip_blender:
        textures()
        run_blender()
    cells = [Image.open(TEMP / "cells" / f"wc_{f}.png").convert("RGBA") for f in FACINGS]
    for c in cells:
        assert c.size == (CELL_W, CELL_H), c.size
    sheet = Image.new("RGBA", (CELL_W * 8, CELL_H), (0, 0, 0, 0))
    entries = []
    for i, c in enumerate(cells):
        sheet.paste(c, (i * CELL_W, 0))
        x0, y0, x1, y1 = c.getbbox() or (0, 0, 1, 1)
        entries.append((f"{TILESET}_{i}", i * CELL_W + x0, y0, x1 - x0, y1 - y0, x0, y0, CELL_W, CELL_H))
    (MEDIA / "texturepacks").mkdir(parents=True, exist_ok=True)
    (MEDIA / "texturepacks" / f"{PACK}.pack").write_bytes(pzfmt.write_pack([(f"{PACK}0", sheet, entries)]))
    ts = {"name": TILESET, "image": f"{TILESET}.png", "w": 8, "h": 1, "number": TILESET_NUMBER,
          "tiles": [tile_props(f) for f in FACINGS]}
    (MEDIA / f"{TILEDEF}.tiles").write_bytes(pzfmt.write_tiles([ts]))
    if skip_blender:
        print(f"wrote {PACK}.pack + {TILEDEF}.tiles only (--skip-blender)")
        return
    COMMON.mkdir(parents=True, exist_ok=True)
    (COMMON / "spriteModels.txt").write_text(sprite_models(), encoding="ascii", newline="\n")
    for src, dst in assets():
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
    for item, src in ITEM_ICONS.items():
        fit_icon(Image.open(TEMP / "icons" / src)).save(MEDIA / "textures" / f"Item_{item}.png", optimize=True)
    print(f"wrote {len(cells)} sprites, {PACK}.pack, {TILEDEF}.tiles, spriteModels.txt, {len(assets())} assets, "
          f"{len(ITEM_ICONS)} icons")


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
    """One set of numbers: props_blender.py meshes = build.py atlas/spriteModels = Cable.lua = Chargers.lua cableExit
    = Core.lua T.Specs plug."""
    b = blender_consts()
    assert b["XFORM"] == XFORM and b["PANEL"] == PANEL, "props_blender.py XFORM/PANEL differ from build.py"
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
    want = (0.0, -b["EXIT_Y"], round(b["EXIT_Z"] / 2.44949, 3))
    ch = MEDIA / "lua" / "shared" / "MinidoracatTesla" / "Chargers.lua"
    if ch.exists():
        m = re.search(r"cableExit\s*=\s*\{\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*\}", ch.read_text(encoding="utf-8"))
        assert m and tuple(float(x) for x in m.groups()) == want, f"Chargers.lua cableExit {m and m.groups()} != {want}"
    else:
        print(f"  note: Chargers.lua not written yet; cableExit must be {{ {want[0]:g}, {want[1]:g}, {want[2]:g} }}")


def check() -> None:
    tiles = pzfmt.read_tiles((MEDIA / f"{TILEDEF}.tiles").read_bytes())
    assert [t["name"] for t in tiles] == [TILESET] and tiles[0]["number"] == TILESET_NUMBER, tiles
    assert tiles[0]["tiles"] == [tile_props(f) for f in FACINGS], tiles[0]["tiles"]
    for t in tiles[0]["tiles"]:
        assert not {"WallN", "WallW", "solid", "solidtrans", "BlocksPlacement", "CanScrap"} & t.keys(), t
    pages = pzfmt.read_pack((MEDIA / "texturepacks" / f"{PACK}.pack").read_bytes())
    names = [e[0] for p in pages for e in p["entries"]]
    assert names == [f"{TILESET}_{i}" for i in range(len(FACINGS))], names
    for p in pages:
        for e in p["entries"]:
            assert e[7:] == (CELL_W, CELL_H) and e[3] > 8 and e[4] > 8, e     # not an empty cell
    info = (MEDIA.parent / "mod.info").read_text(encoding="utf-8")
    assert f"pack={PACK}\n" in info and f"tiledef={TILEDEF} {FILE_NUMBER}\n" in info, "mod.info pack=/tiledef="
    sm = (COMMON / "spriteModels.txt").read_text(encoding="ascii")
    assert sm == sprite_models(), "spriteModels.txt is stale: rebuild"
    rot = dict(re.findall(r"xy = (\d) 0,\s*modelScript = Base\.\w+,\s*translate = [^,]+,\s*rotate = ([^,]+),", sm))
    assert rot == {str(i): fmt3(XFORM[f]) for i, f in enumerate(FACINGS)}, rot
    models = (MEDIA / "scripts" / "models" / "MinidoracatTesla_props.txt").read_text(encoding="ascii")
    for m in (WC_MODEL, *cable_models()):
        assert f"model {m}\n" in models, m
    for _, dst in assets():
        assert dst.exists() and dst.stat().st_size > 0, dst
    for item in ITEM_ICONS:
        icon = Image.open(MEDIA / "textures" / f"Item_{item}.png")
        assert icon.size == (32, 32) and icon.mode == "RGBA", (item, icon.size, icon.mode)
    check_geometry()
    print("check OK: tiles, pack, mod.info, spriteModels, model script, assets, icons, geometry constants")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--skip-blender", action="store_true", help="rebuild .pack/.tiles from existing temp cells")
    a = ap.parse_args()
    check() if a.check else build(a.skip_blender)
