"""Offline cabin views of a built car (the cabin rounds' 官方｜before｜after sheets, .claude/skills/tesla-dev/references/
models-cybercab.md 車內): Workbench, a rasteriser that culls back faces before the depth test as the game does (Cycles
let the body's reversed liner copies, on the paint's own surface, fight it: a gold-and-black camouflage). game mode:
the shader's flat cells x the daylight's 0.85 (the lit screen not dimmed); shade mode: studio light for the shapes.
The glass blended at 0.25 over the cabin.

blender -b --factory-startup --python-use-system-env --python scripts/blender/skf/cabview.py -- <job.json>
job: {blend: the build's temp/skf_*/skf_doors.blend, skin: a body skin png, state: shut | all | fl | fr | rl | rr
      (doors open), mode: game | shade, extra: [ply, ...] (drawn blue: posed passengers), detail: [fbx, png] | null
      (the cabin detail model on its texture), isolate: null | "seats" (the body's seat cells alone: seat_cells, |x| <
      seat_x), body: the body object (default the one named MinidoracatTesla_<Car>), bg: [r, g, b],
      views: [{out, type: PERSP | ORTHO, loc, at, fov | ortho, res: [w, h], clip}]}"""
import json
import math
import re
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

job = json.load(open(sys.argv[sys.argv.index("--") + 1]))
bpy.ops.wm.open_mainfile(filepath=job["blend"])
arm = bpy.data.objects["VehicleSkeleton"]
arm.matrix_world = Matrix.Rotation(math.pi / 2, 4, "X")
# the body's shell bits per door (convert.py: UV1 v of a cabin face = its door's index + 1 here, dropped while open)
SHELL_DOORS = ("DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight", "TrunkDoor")
STATES = {"all": SHELL_DOORS[:4], "shut": (), "fl": ("DoorFrontLeft",), "fr": ("DoorFrontRight",),
          "rl": ("DoorRearLeft",), "rr": ("DoorRearRight",)}
openp = [d for d in STATES[job["state"]] if d + "_closing" in bpy.data.actions]
ad = arm.animation_data
poses = {}
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"
    bp = pb.name.partition("_bone")[0]
    if bp in openp:                 # frame 1 of the closing clip: open
        ad.action = bpy.data.actions[bp + "_closing"]
        bpy.context.scene.frame_set(1)
        poses[pb.name] = (pb.location.copy(), pb.rotation_quaternion.copy())
ad.action = None
for pb in arm.pose.bones:
    pb.location, pb.rotation_quaternion = poses.get(pb.name, (Vector(), (1, 0, 0, 0)))
bpy.context.view_layer.update()

# the coarse cabin's 16 cells (pzveh.CABIN_CELLS order; sRGB as MinidoracatTesla_vehicle.frag CABIN)
CAB = [(22, 22, 24), (40, 40, 44), (100, 100, 106), (30, 30, 32), (58, 58, 62), (112, 106, 98), (46, 46, 50),
       (28, 28, 30), (16, 16, 18), (170, 192, 214), (88, 88, 92), (120, 120, 126), (44, 44, 48), (58, 58, 62),
       (72, 72, 76), (128, 128, 134)]
GAME, mode = 0.85, job.get("mode", "game")
lin = lambda c: [(x / 255) ** 2.2 for x in c]   # noqa: E731
skin_img = bpy.data.images.load(job["skin"])


def material(name, rgb=None, img=None, alpha=1.0, glow=False, closest=False):
    m = bpy.data.materials.new(name)
    m.use_backface_culling = True
    m.use_nodes = True
    nt = m.node_tree
    if img is not None:
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image, tx.interpolation = img, "Closest" if closest else "Linear"
        nt.links.new(tx.outputs[0], nt.nodes["Principled BSDF"].inputs[0])
        nt.nodes.active = tx
    else:
        k = 1 / GAME if glow and mode == "game" else 1.0     # the lit screen: not dimmed by the daylight
        m.diffuse_color = (*[min(1.0, v * k) for v in lin(rgb)], alpha)
    if alpha < 1:
        m.surface_render_method = "BLENDED"
    return m


glass = [round(255 * c) for c in (0.06 * 0.7 + 0.50 * 0.3, 0.06 * 0.7 + 0.60 * 0.3, 0.07 * 0.7 + 0.75 * 0.3)]
M = [material("paint", img=skin_img), material("glass", glass, alpha=0.25)] + \
    [material(f"cab{i}", c, glow=(i == 9)) for i, c in enumerate(CAB)]
body = bpy.data.objects[job["body"]] if "body" in job else \
    next(o for o in bpy.data.objects if o.type == "MESH" and re.fullmatch(r"MinidoracatTesla_[A-Za-z0-9]+", o.name))
iso = job.get("isolate")
for o in [o for o in bpy.data.objects if o.type == "MESH"]:
    me = o.data
    u1 = np.empty(len(me.loops) * 2)
    me.uv_layers["UV1"].data.foreach_get("uv", u1)
    ls = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("loop_start", ls)
    fu, fv = u1[0::2][ls], u1[1::2][ls]
    # UV1 u: glass over 1.5, the cabin's cells under -1 (pzveh.CABIN_UV1_U - cell), the paint between
    idx = np.where(fu > 1.5, 1, np.where(fu < -1.0, 2 + np.clip(np.round(-fu - 2.5).astype(int), 0, 15), 0))
    me.materials.clear()
    for m in M:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", idx)
    keep = np.ones(len(idx), bool)
    if o is body:
        k = np.floor(fv + 0.5).astype(int)
        keep &= ~((fu < -1.0) & np.isin(k, [SHELL_DOORS.index(p) + 1 for p in openp]) & (fv < k))
    if iso == "seats":      # the seats alone (official studio pictures): their cells, behind the dash, off the walls
        if o is not body:
            keep[:] = False
        else:
            c = np.empty(len(me.polygons) * 3)
            me.polygons.foreach_get("center", c)
            c = c.reshape(-1, 3)
            keep &= (fu < -1.0) & np.isin(idx - 2, job.get("seat_cells", [1, 2, 3, 8, 14])) & (c[:, 1] < 0.45) & \
                (c[:, 1] > -0.7) & (c[:, 2] < 0.40) & (c[:, 2] > -0.47) & (np.abs(c[:, 0]) < job.get("seat_x", 0.56))
    if not keep.all():
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.nonzero(~keep)[0]], context="FACES")
        bm.to_mesh(me)
        bm.free()
    o.hide_render = False
for f in job.get("extra", []):
    bpy.ops.wm.ply_import(filepath=f)
    ob = bpy.context.selected_objects[0]
    ob.data.materials.clear()
    ob.data.materials.append(material("pax", (70, 130, 210)))
if job.get("detail"):
    fbx, png = job["detail"]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fbx)
    dimg = bpy.data.images.load(png)
    for ob in set(bpy.data.objects) - before:
        if ob.type == "MESH":
            ob.data.materials.clear()
            ob.data.materials.append(material("detail", img=dimg, closest=True))
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.view_settings.view_transform = "Standard"
sc.view_settings.exposure = math.log2(GAME) if mode == "game" else 0.0
sh = sc.display.shading
sh.light = "FLAT" if mode == "game" else "STUDIO"
sh.color_type = "TEXTURE"
sh.show_backface_culling = True
sh.background_type = "VIEWPORT"
sh.background_color = lin(job.get("bg", (255, 255, 255)))
sc.display.render_aa = "8"
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
for v in job["views"]:
    sc.render.resolution_x, sc.render.resolution_y = v["res"]
    cam.data.type = v.get("type", "PERSP")
    cam.data.clip_start = v.get("clip", 0.02)
    if cam.data.type == "ORTHO":
        cam.data.ortho_scale = v["ortho"]
    else:
        cam.data.sensor_fit = "HORIZONTAL"
        cam.data.angle = math.radians(v["fov"])
    cam.location = Vector(v["loc"])
    cam.rotation_euler = (Vector(v["at"]) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = v["out"]
    bpy.ops.render.render(write_still=True)
    print("WROTE", v["out"])
