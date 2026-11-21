# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10"]
# ///
"""Upgrade kit item icons (Item_MinidoracatTesla_ArmorInner / ArmorOuter / Fridge.png): primitives in Blender, the
Workbench render and 32 px fit of drive_unit_icon.py (build.fit_icon). Drawn here, no Tesla artwork.

    uv run scripts/blender/props/upgrade_icons.py          # renders temp/props/icons/<kind>_icon.png, writes the MOD icons
    uv run scripts/blender/props/upgrade_icons.py --cpu    # no GPU (Workbench needs one): Cycles CPU as build.py --cpu
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
KINDS = ("ArmorInner", "ArmorOuter", "Fridge")


def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)                    # Workbench MATERIAL colour
    m.use_nodes = True                             # Cycles (--cpu)
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = 0.85  # the white world would grey out the dark parts
    bsdf.inputs["Specular IOR Level"].default_value = 0.15
    return m


def add(kind, loc, rot, m, scale=None, **kw):
    getattr(bpy.ops.mesh, f"primitive_{kind}_add")(location=loc, rotation=rot, **kw)
    ob = bpy.context.object
    if scale:
        ob.scale = scale
    ob.data.materials.append(m)
    return ob


def tube(a, b, m, r):
    """A cylinder from point a to point b (x, y, z)."""
    a, b = Vector(a), Vector(b)
    ob = add("cylinder", (a + b) / 2, (0, 0, 0), m, radius=r, depth=(b - a).length, vertices=24)
    ob.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    return ob


def armor_inner():
    """Reinforcement kit: three steel plates fanned out, bolt holes along the top plate's edges, a few bolts."""
    steel, edge, hole, bolt = (mat("steel", (0.50, 0.52, 0.55)), mat("edge", (0.34, 0.36, 0.38)),
                               mat("hole", (0.08, 0.08, 0.09)), mat("bolt", (0.62, 0.55, 0.30)))
    for i, (dz, rz) in enumerate(((0.0, -12), (0.12, 0), (0.24, 12))):
        add("cube", (0, 0, dz), (0, 0, math.radians(rz)), steel if i == 2 else edge, (1.0, 0.62, 0.04), size=1)
    r = math.radians(12)
    for sx in (-0.42, 0.42):
        for sy in (-0.22, 0, 0.22):
            x, y = sx * math.cos(r) - sy * math.sin(r), sx * math.sin(r) + sy * math.cos(r)
            add("cylinder", (x, y, 0.265), (0, 0, 0), hole, radius=0.04, depth=0.02, vertices=16)
    for x, y in ((0.62, -0.42), (0.74, -0.28), (0.56, -0.22)):      # loose bolts next to the stack
        add("cylinder", (x, y, 0.05), (0, 0, 0), bolt, radius=0.06, depth=0.08, vertices=6)
        add("cylinder", (x, y, 0.13), (0, 0, 0), bolt, radius=0.025, depth=0.12, vertices=12)


def armor_outer():
    """Bull bar, wide and low: black tubes (bottom bar, centre hoop, grille bars, side wings) on steel brackets."""
    black, mount = mat("black", (0.04, 0.04, 0.045)), mat("mount", (0.50, 0.52, 0.55))
    r = 0.085
    tube((-0.7, 0, 0), (0.7, 0, 0), black, r * 1.2)                                   # bottom bar
    for s in (-1, 1):
        tube((s * 0.3, 0, 0), (s * 0.3, 0, 0.5), black, r)                            # hoop uprights
        tube((s * 0.1, 0, 0), (s * 0.1, 0, 0.75), black, r * 0.8)                     # grille bars
        tube((s * 0.3, 0, 0.45), (s * 0.68, 0, 0.02), black, r)                       # side wings
        add("cube", (s * 0.3, 0.2, 0.05), (0, 0, 0), mount, (0.16, 0.34, 0.22), size=1)  # mounting brackets
    add("torus", (0, 0, 0.5), (math.radians(90), 0, 0), black, major_radius=0.3, minor_radius=r,
        major_segments=48, minor_segments=16)
    hoop = bpy.context.object
    cut = add("cube", (0, 0, 0.2), (0, 0, 0), black, (1.0, 0.4, 0.6), size=1)        # keep the hoop's top half
    b = hoop.modifiers.new("cut", "BOOLEAN")
    b.operation, b.object = "DIFFERENCE", cut
    bpy.context.view_layer.objects.active = hoop
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(cut)


def fridge():
    """Car fridge: charcoal box, light grey lid with a handle recess, blue display, fold-down side handles."""
    body, lid, dark, blue = (mat("body", (0.025, 0.025, 0.028)), mat("lid", (0.45, 0.47, 0.49)),
                             mat("dark", (0.006, 0.006, 0.006)), mat("blue", (0.05, 0.40, 1.0)))
    add("cube", (0, 0, 0), (0, 0, 0), body, (1.3, 0.7, 0.62), size=1)
    add("cube", (0, 0, 0.37), (0, 0, 0), lid, (1.34, 0.74, 0.14), size=1)
    add("cube", (0, 0, 0.445), (0, 0, 0), dark, (0.5, 0.14, 0.02), size=1)            # lid handle recess
    add("cube", (0, -0.36, 0.38), (0, 0, 0), dark, (1.0, 0.02, 0.03), size=1)          # lid seam
    add("cube", (0.3, -0.355, 0.08), (0, 0, 0), lid, (0.42, 0.02, 0.24), size=1)       # control panel
    add("cube", (0.25, -0.37, 0.1), (0, 0, 0), blue, (0.2, 0.01, 0.11), size=1)        # display
    for i in range(4):                                                                   # front vents
        add("cube", (-0.3, -0.355, 0.16 - i * 0.09), (0, 0, 0), dark, (0.42, 0.02, 0.035), size=1)
    for s in (-1, 1):                                                                    # side handles
        tube((s * 0.68, -0.25, 0.12), (s * 0.68, 0.25, 0.12), lid, 0.035)
        add("cube", (0, s * 0.25, -0.34), (0, 0, 0), dark, (1.2, 0.1, 0.06), size=1)  # feet


def scene(kind):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    {"ArmorInner": armor_inner, "ArmorOuter": armor_outer, "Fridge": fridge}[kind]()
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    bpy.ops.object.shade_smooth()
    return bpy.context.object


def render(ob, out, cpu):
    sc = bpy.context.scene
    if cpu:                                        # props_blender.reset()'s white world and sun, dimmed to keep the darks
        sc.render.engine, sc.cycles.device, sc.cycles.samples = "CYCLES", "CPU", 48
        sc.view_settings.view_transform = "Standard"
        w = sc.world = bpy.data.worlds.new("W")
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
        w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
        sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
        sun.data.energy = 1.8
        sun.rotation_euler = Vector((0.45, 0.75, -0.75)).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(sun)
    else:
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
    sc.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)


if bpy:
    args = sys.argv[sys.argv.index("--") + 1:]
    render(scene(args[0]), RAW / f"{args[0]}_icon.png", "--cpu" in args)
else:
    sys.path.insert(0, str(HERE))
    from build import BLENDER, fit_icon
    from PIL import Image
    RAW.mkdir(parents=True, exist_ok=True)
    for kind in KINDS:
        subprocess.run([str(BLENDER), "-b", "--factory-startup", "--python", __file__, "--", kind, *sys.argv[1:]],
                       check=True)
        icon = TEX / f"Item_MinidoracatTesla_{kind}.png"
        fit_icon(Image.open(RAW / f"{kind}_icon.png")).save(icon)
        print(f"wrote {icon}")
