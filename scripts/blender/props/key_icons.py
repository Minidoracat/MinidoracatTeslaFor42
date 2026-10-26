# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10"]
# ///
"""Key card and phone item icons (Item_MinidoracatTesla_KeyCard.png, Item_MinidoracatTesla_Phone.png; the paired
phone key reuses the phone icon). Primitives in Blender, same Workbench render and 32 px fit as drive_unit_icon.py.
No Tesla logo on either (user 2026-10-26).

    uv run scripts/blender/props/key_icons.py    # renders temp/props/icons/{card,phone}.png, writes the MOD icons
"""
import math
import subprocess
import sys
from pathlib import Path

try:
    import bpy
    from mathutils import Vector
except ImportError:
    bpy = None

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
RAW = ROOT / "temp" / "props" / "icons"
TEX = ROOT / "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/textures"
ICONS = {"card": "Item_MinidoracatTesla_KeyCard.png", "phone": "Item_MinidoracatTesla_Phone.png"}


def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    return m


def slab(loc, size, m, bevel):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    ob = bpy.context.object
    ob.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width, mod.segments, mod.affect = bevel, 6, "EDGES"
        bpy.ops.object.modifier_apply(modifier="bevel")
    ob.data.materials.append(m)
    return ob


def card():
    # 85.6 x 54 mm card standing up, face towards the camera (-Y): black body, silver chip, white stripe
    body = slab((0, 0, 0), (1.0, 0.02, 0.63), mat("black", (0.05, 0.05, 0.06)), 0.06)
    slab((-0.28, -0.012, 0.06), (0.16, 0.004, 0.13), mat("chip", (0.78, 0.70, 0.42)), 0.02)
    slab((0.0, -0.012, -0.2), (0.8, 0.004, 0.04), mat("stripe", (0.85, 0.85, 0.87)), 0)
    return body


def phone():
    # handset standing up: black slab, dark glass screen with a bluish lock screen, camera dot
    body = slab((0, 0, 0), (0.5, 0.06, 1.0), mat("black", (0.08, 0.08, 0.09)), 0.025)
    slab((0, -0.032, 0.0), (0.44, 0.004, 0.88), mat("screen", (0.10, 0.20, 0.38)), 0.05)
    slab((0, -0.036, 0.25), (0.26, 0.004, 0.08), mat("clock", (0.80, 0.86, 0.95)), 0.01)
    bpy.ops.mesh.primitive_cylinder_add(location=(0, -0.034, 0.46), rotation=(math.radians(90), 0, 0),
                                        radius=0.02, depth=0.01)
    bpy.ops.object.transform_apply(rotation=True) # join keeps the active object's transform, rotated below
    bpy.context.object.data.materials.append(mat("cam", (0.01, 0.01, 0.01)))
    return body


def render(build, out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.join()
    ob = bpy.context.object
    ob.rotation_euler = (math.radians(-12), 0, math.radians(18))
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light, sh.color_type, sh.show_cavity = "STUDIO", "MATERIAL", False
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 256
    bpy.context.view_layer.update()
    cs = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    target = sum(cs, Vector()) / 8
    cd = bpy.data.cameras.new("IconCam")
    cd.type, cd.ortho_scale = "ORTHO", 1.4
    cam = bpy.data.objects.new("IconCam", cd)
    sc.collection.objects.link(cam)
    a, e = math.radians(15), math.radians(20)
    cam.location = target + Vector((math.cos(e) * math.sin(a), -math.cos(e) * math.cos(a), math.sin(e))) * 5
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)


if bpy:
    RAW.mkdir(parents=True, exist_ok=True)
    render(card, RAW / "card.png")
    render(phone, RAW / "phone.png")
else:
    sys.path.insert(0, str(HERE))
    from build import BLENDER, fit_icon
    from PIL import Image
    subprocess.run([str(BLENDER), "-b", "--factory-startup", "--python", __file__], check=True)
    for raw, name in ICONS.items():
        fit_icon(Image.open(RAW / f"{raw}.png")).save(TEX / name)
        print(f"wrote {TEX / name}")
