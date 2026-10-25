# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10"]
# ///
"""Drive Unit Parts item icon (Item_MinidoracatTesla_DriveUnitParts.png): primitives in Blender, same Workbench render
and 32 px fit as the Wall Connector icon (props_blender.render_icon, build.fit_icon).

    uv run scripts/blender/props/drive_unit_icon.py    # renders temp/props/icons/du_icon.png, writes the MOD icon
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
RAW = ROOT / "temp" / "props" / "icons" / "du_icon.png"
ICON = ROOT / "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/textures/Item_MinidoracatTesla_DriveUnitParts.png"


def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    return m


def add(kind, loc, rot, m, **kw):
    getattr(bpy.ops.mesh, f"primitive_{kind}_add")(location=loc, rotation=rot, **kw)
    ob = bpy.context.object
    ob.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return ob


def scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    alu, dark, orange, steel = (mat("alu", (0.62, 0.63, 0.65)), mat("dark", (0.16, 0.16, 0.17)),
                                mat("hv", (0.95, 0.42, 0.05)), mat("steel", (0.80, 0.80, 0.82)))
    y90 = (0, math.radians(90), 0)
    add("cylinder", (-0.35, 0, 0), y90, alu, radius=0.42, depth=0.9, vertices=48)            # motor housing
    for x in (-0.62, -0.38, -0.14):                                                           # cooling ribs
        add("torus", (x, 0, 0), y90, dark, major_radius=0.43, minor_radius=0.025)
    add("cylinder", (0.38, 0, -0.05), y90, alu, radius=0.5, depth=0.55, vertices=48)          # gearbox
    add("cylinder", (0.75, 0, -0.05), y90, steel, radius=0.1, depth=0.4, vertices=24)         # output shaft
    add("cylinder", (-0.9, 0, 0), y90, steel, radius=0.1, depth=0.3, vertices=24)
    inv = add("cube", (-0.25, 0, 0.5), (0, 0, 0), dark, size=1)                               # inverter
    inv.scale = (0.75, 0.55, 0.16)
    add("cylinder", (0.05, -0.2, 0.62), (0, 0, 0), orange, radius=0.07, depth=0.14, vertices=24)  # HV connectors
    add("cylinder", (0.05, 0.05, 0.62), (0, 0, 0), orange, radius=0.07, depth=0.14, vertices=24)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.join()
    return bpy.context.object


def render(ob):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light, sh.color_type, sh.show_cavity = "STUDIO", "MATERIAL", False
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 256
    cs = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    target = sum(cs, Vector()) / 8
    cd = bpy.data.cameras.new("IconCam")
    cd.type, cd.ortho_scale = "ORTHO", 2.4
    cam = bpy.data.objects.new("IconCam", cd)
    sc.collection.objects.link(cam)
    a, e = math.radians(30), math.radians(25)
    cam.location = target + Vector((math.cos(e) * math.sin(a), -math.cos(e) * math.cos(a), math.sin(e))) * 5
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    RAW.parent.mkdir(parents=True, exist_ok=True)
    sc.render.filepath = str(RAW)
    bpy.ops.render.render(write_still=True)


if bpy:
    render(scene())
else:
    sys.path.insert(0, str(HERE))
    from build import BLENDER, fit_icon
    from PIL import Image
    subprocess.run([str(BLENDER), "-b", "--factory-startup", "--python", __file__], check=True)
    fit_icon(Image.open(RAW)).save(ICON)
    print(f"wrote {ICON}")
