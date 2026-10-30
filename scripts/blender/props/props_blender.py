"""Blender 5.2 headless: Wall Connector + Mobile Connector Gen 3 meshes + cable segments -> glb/fbx, 2D tile cells,
icons, previews.

blender -b --factory-startup --python props_blender.py -- <temp dir>   (build.py runs this; textures come from build.py)

Units: 1 Blender unit = 1 PZ tile edge. Heights are in the same unit (1 floor = 2.44949 units).
Wall Connector (IsoObject, glb): built for Facing S with spriteModels rotate (0,180,0): Blender +X = PZ east,
  +Y = PZ north (the wall), front toward -Y. Origin = tile centre on the floor (IsoObject.java:3540).
  Real unit H 345 x W 155 x D 110 mm (Tesla Gen 3 install manual); drawn 1.3x so it reads at game zoom.
Mobile Connector (IsoObject, glb): same frame, lying on the floor; control box 179.8 x 81.7 x 47.3 mm drawn 1.3x.
  The car cable ends on the floor at (0, MC_EXIT_Y, R_CABLE), where Cable.lua starts the floor run (h = 0, no hang).
Cable segments (WorldItems, fbx, Render3DItem): model +X = the direction passed as the Render3DItem angle
  (atan2(dy, dx) in PZ degrees, ItemModelRenderer.java:260-268,908-921 + Core.java:2578-2587), +Z up; the model
  script has undoCoreScale so 1 mesh unit = 1 tile (ModelScript.java:106-108).
  Hang:  origin = floor point under the charger's cable exit; exit at (0,0,EXIT_Z); reaches the floor at +X HANG_REACH.
  Floor: straight, x -0.5..0.5 (origin = segment midpoint).
  Plug:  one per car (PLUGS: mesh name -> handle height); origin = floor point; rises and ends in the handle tip at
         (PLUG_REACH, 0, z) pointing +X (into the car).
Keep EXIT_Z/HANG_REACH/PLUG_REACH/MC_EXIT_Y in sync with Cable.lua and Chargers.lua cableExit, PLUGS with Core.lua
T.Specs plug (build.py --check).
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

OUT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
EXP, CELLS, ICONS, PREV = OUT / "export", OUT / "cells", OUT / "icons", OUT / "previews"
PX = 128 / math.sqrt(2)             # px per tile unit at 2x (tiles-and-sprite-models.md section 7)

# Wall Connector, Facing S frame
WC_W, WC_H, WC_Z0 = 0.20, 0.45, 0.80          # width, height, bottom edge above the floor
Y_WALL, Y_SHELL, Y_PANEL = 0.47, 0.37, 0.33   # back (wall side), shell front, panel front
EXIT_Y = 0.40                                 # cable exit: bottom centre of the shell
EXIT_Z = WC_Z0
# cable
R_CABLE = 0.026
HANG_REACH = 0.40
# Plug handle height per car = its chargeport above the floor, units (E2E integration-mp `port`; Core.lua T.Specs plug)
PLUGS = {"MinidoracatTesla_CablePlug": 0.909,                 # Model Y (tesla-integ-1026a, models.md 0)
         "MinidoracatTesla_CablePlugModel3": 0.74,            # Model 3
         "MinidoracatTesla_CablePlugCybertruck": 0.90}        # Cybertruck (tesla-ctbody-1030c: port 0.902)
PLUG_REACH = 0.36                             # handle tip reaches +x (into the car flank)
XFORM = {"S": (0.0, 180.0, 0.0), "E": (0.0, -90.0, 0.0), "N": (0.0, 0.0, 0.0), "W": (0.0, 90.0, 0.0)}
# Mobile Connector Gen 3, Facing S frame, lying on the floor: control box 179.8 x 81.7 x 47.3 mm (official.md 1.2) x 1.3
MC_L, MC_W, MC_H = 0.234, 0.106, 0.062        # box length (along y), width, height
MC_Y = -0.03                                  # box centre y; car cable leaves the south end (-y), adapter the north end
MC_EXIT_Y = -0.20                             # car cable ends on the floor here: Chargers.lua cableExit = (0, -MC_EXIT_Y, 0)

# atlas layout (build.py draws the same rects): 256 px
TEX = 256
PANEL = (8, 2, 120, 254)
SW = {"white": (136, 8), "black": (196, 8), "rubber": (136, 68), "handle": (196, 68), "holster": (136, 128)}
CTEX = 64
CSW = {"rubber": (0, 0), "handle": (32, 0), "ring": (0, 32)}
MTOP = (8, 8, 120, 248)                       # Mobile Connector 256 px atlas: box top (logo + status LEDs)
MSW = {"black": (136, 8), "rubber": (136, 68), "metal": (196, 8), "adapter": (196, 68)}


def rect_uv(rect, tex, u, v):
    x0, y0, x1, y1 = rect
    return ((x0 + u * (x1 - x0)) / tex, 1.0 - (y1 - v * (y1 - y0)) / tex)


def swatch(name, table=SW, size=56, tex=TEX):
    x, y = table[name]
    return (x + 6, y + 6, x + size - 6, y + size - 6), tex


class MB:
    """Per-face vertices (flat shading), every loop carries its UV (Knox Pass build_models.py MB)."""

    def __init__(self):
        self.verts, self.faces, self.uvs = [], [], []

    def face(self, pts, uvs):
        base = len(self.verts)
        self.verts += [tuple(p) for p in pts]
        self.faces.append(list(range(base, base + len(pts))))
        self.uvs.append(list(uvs))

    def patch(self, pts, sw):
        rect, tex = sw
        n = len(pts)
        uvs = [rect_uv(rect, tex, 0.5 + 0.4 * math.cos(2 * math.pi * k / n), 0.5 + 0.4 * math.sin(2 * math.pi * k / n))
               for k in range(n)]
        self.face(pts, uvs)

    def build(self, name, image):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        uv = me.uv_layers.new(name="UVMap")
        for poly, fuv in zip(me.polygons, self.uvs):
            for k, loop in enumerate(poly.loop_indices):
                uv.data[loop].uv = fuv[k]
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        img = mat.node_tree.nodes.new("ShaderNodeTexImage")
        img.image = image
        mat.node_tree.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.45
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


# ---------------------------------------------------------------- Wall Connector

def shield(scale=1.0, n=56):
    """Front outline in the XZ plane (counter-clockwise seen from -Y): rounded shield, widest in the upper third,
    narrower at the bottom (official front photo). Superellipse corners."""
    pts = []
    zc = WC_Z0 + WC_H / 2
    for k in range(n):
        a = 2 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        z = zc + (WC_H / 2) * scale * math.copysign(abs(s) ** (2 / 5), s)
        t = (z - WC_Z0) / WC_H
        hw = (WC_W / 2) * scale * (0.80 + 0.20 * math.sin(math.pi * min(1.0, t / 0.85) * 0.5) - 0.08 * max(0, t - 0.85) / 0.15)
        pts.append((hw * math.copysign(abs(c) ** (2 / 5), c), z))
    return pts


def prism(mb, outline, y_front, y_back, front_uv, side_sw, back_sw):
    """outline: XZ points counter-clockwise seen from the front (-Y)."""
    front = [(x, y_front, z) for x, z in outline]
    mb.face(front, [front_uv(x, z) for x, z in outline])
    back = [(x, y_back, z) for x, z in reversed(outline)]
    mb.patch(back, back_sw)
    for i in range(len(outline)):
        (ax, az), (bx, bz) = outline[i], outline[(i + 1) % len(outline)]
        quad = [(ax, y_front, az), (ax, y_back, az), (bx, y_back, bz), (bx, y_front, bz)]
        nx = (bz - az)                                    # outward normal x of this side (ccw outline)
        mb.patch(quad, side_sw(nx, ax, bx))


def wall_connector(image):
    mb = MB()

    def panel_uv(x, z):
        return rect_uv(PANEL, TEX, 0.5 + x / (WC_W * 1.04), (z - WC_Z0) / WC_H)

    outer = shield(1.0)
    inner = shield(0.95)
    # glass panel: bevelled front (inner ring pushed forward) + thin white edge
    prism(mb, outer, Y_PANEL + 0.012, Y_SHELL, panel_uv, lambda nx, ax, bx: swatch("white"), swatch("white"))
    front = [(x, Y_PANEL, z) for x, z in inner]
    mb.face(front, [panel_uv(x, z) for x, z in inner])
    for i in range(len(outer)):
        (ox0, oz0), (ox1, oz1) = outer[i], outer[(i + 1) % len(outer)]
        (ix0, iz0), (ix1, iz1) = inner[i], inner[(i + 1) % len(inner)]
        q = [(ox0, Y_PANEL + 0.012, oz0), (ox1, Y_PANEL + 0.012, oz1), (ix1, Y_PANEL, iz1), (ix0, Y_PANEL, iz0)]
        mb.face(q, [panel_uv(ox0, oz0), panel_uv(ox1, oz1), panel_uv(ix1, iz1), panel_uv(ix0, iz0)])
    # black shell behind the glass; the holster (device's left = PZ east for Facing S) is on its +X flank
    shell = shield(0.90)

    def shell_side(nx, ax, bx):
        return swatch("holster") if nx > 0 and min(ax, bx) > 0.04 else swatch("black")

    prism(mb, shell, Y_SHELL, Y_WALL, lambda x, z: rect_uv(*swatch("black"), 0.5, 0.5), shell_side, swatch("black"))
    # spare cable coiled behind the unit (garage photo): elliptical ring in the wall plane
    zc = WC_Z0 + WC_H / 2 + 0.02
    ring = [Vector((0.205 * math.cos(2 * math.pi * k / 28), (Y_SHELL + Y_WALL) / 2 + 0.01,
                    zc + 0.25 * math.sin(2 * math.pi * k / 28))) for k in range(29)]
    tube(mb, ring, R_CABLE * 0.9, swatch("rubber"), caps=False)
    return mb.build("MinidoracatTesla_WallConnector", image)


# ---------------------------------------------------------------- cables

def catmull(points, per=6):
    p = [Vector(v) for v in points]
    p = [p[0] * 2 - p[1]] + p + [p[-1] * 2 - p[-2]]
    out = []
    for i in range(1, len(p) - 2):
        for k in range(per):
            t = k / per
            a, b, c, d = p[i - 1], p[i], p[i + 1], p[i + 2]
            out.append(0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t
                              + (-a + 3 * b - 3 * c + d) * t ** 3))
    out.append(p[-2])
    return out


def tube(mb, path, radius, sw, sides=8, caps=True, radii=None):
    """Swept tube along path (list of Vector); parallel-transport frames."""
    tangents = [(path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized() for i in range(len(path))]
    ref = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((0, 1, 0))
    normal = tangents[0].cross(ref).normalized()
    rings = []
    for i, (p, t) in enumerate(zip(path, tangents)):
        normal = (normal - t * normal.dot(t)).normalized()
        binormal = t.cross(normal)
        r = radii[i] if radii else radius
        rings.append([p + (normal * math.cos(2 * math.pi * k / sides) + binormal * math.sin(2 * math.pi * k / sides)) * r
                      for k in range(sides)])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            mb.patch([a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]], sw)
    if caps:
        mb.patch(list(reversed(rings[0])), sw)
        mb.patch(rings[-1], sw)


def cable_hang(image):
    mb = MB()
    r = R_CABLE
    path = catmull([(0, 0, EXIT_Z + 0.03), (0, 0, EXIT_Z - 0.20), (0.04, 0, 0.30), (0.16, 0, 0.08),
                    (0.30, 0, r), (HANG_REACH, 0, r)])
    tube(mb, path, r, swatch("rubber", CSW, 32, CTEX))
    # strain relief boot where the cable leaves the unit
    tube(mb, [Vector((0, 0, EXIT_Z + 0.02)), Vector((0, 0, EXIT_Z - 0.06))], r * 1.5, swatch("handle", CSW, 32, CTEX))
    return mb.build("MinidoracatTesla_CableHang", image)


def cable_floor(image):
    mb = MB()
    tube(mb, [Vector((-0.5 + 0.5 * k / 2, 0, R_CABLE)) for k in range(5)], R_CABLE, swatch("rubber", CSW, 32, CTEX))
    return mb.build("MinidoracatTesla_CableFloor", image)


def cable_plug(image, name, plug_z):
    mb = MB()
    r = R_CABLE
    h0 = PLUG_REACH - 0.17                               # handle starts here
    path = catmull([(0, 0, r), (0.07, 0, r), (0.15, 0, 0.10), (0.17, 0, plug_z * 0.55), (0.15, 0, plug_z - 0.07),
                    (h0, 0, plug_z)])
    tube(mb, path, r, swatch("rubber", CSW, 32, CTEX))
    # NACS handle: thick grip tapering to the nose, slightly bent down like the official handle
    grip = [Vector((h0 - 0.01 + 0.17 * k / 6, 0, plug_z + 0.012 * math.sin(math.pi * k / 6))) for k in range(7)]
    tube(mb, grip, 0, swatch("handle", CSW, 32, CTEX), sides=10,
         radii=[0.030, 0.040, 0.044, 0.044, 0.042, 0.036, 0.030])
    tube(mb, [grip[-1], grip[-1] + Vector((0.012, 0, 0))], 0.026, swatch("ring", CSW, 32, CTEX), sides=10)
    return mb.build(name, image)


# ---------------------------------------------------------------- Mobile Connector

def squircle(hx, hy, n=40):
    """XY outline counter-clockwise seen from above (+Z): superellipse, exponent 4."""
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        pts.append((hx * math.copysign(abs(c) ** 0.5, c), hy * math.copysign(abs(s) ** 0.5, s)))
    return pts


def lofted(mb, outline, profile, centre, top_uv, side_sw, top_from):
    """Rounded slab: outline (XY around 0) scaled per (z, scale) of profile, moved to centre (x, y); bottom + top caps.
    Faces starting at z >= top_from and the top cap take the planar top_uv(point)."""
    cx, cy = centre
    rings = [[(cx + x * s, cy + y * s, z) for x, y in outline] for z, s in profile]
    n = len(outline)
    mb.patch(list(reversed(rings[0])), side_sw)
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            q = [a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]]
            if a[0][2] >= top_from:
                mb.face(q, [top_uv(p) for p in q])
            else:
                mb.patch(q, side_sw)
    mb.face(rings[-1], [top_uv(p) for p in rings[-1]])


def cuboid(mb, lo, hi, sw):
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    for q in (((x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)), ((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)),
              ((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)), ((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)),
              ((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)), ((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1))):
        mb.patch(list(q), sw)


def mobile_connector(image):
    """Facing S, on the floor: control box at the tile centre; car cable out of its south end to the exit floor point
    (0, MC_EXIT_Y); pluggable adapter + short cord + round wall plug off its north end; spare cable coiled on its east
    side. No car handle: while plugged in, Cable.lua draws the run from the exit to the car."""
    mb = MB()

    def msw(name):
        return swatch(name, MSW)

    def flat(name):
        return lambda p: rect_uv(*msw(name), 0.5, 0.5)

    hx, hy, r = MC_W / 2, MC_L / 2, R_CABLE
    # control box: rounded slab, a little narrower at the cable end, soft domed top that carries the logo + LEDs
    outline = [(x * (0.92 + 0.08 * y / hy), y) for x, y in squircle(hx, hy)]
    lofted(mb, outline, [(0.0, 0.86), (0.008, 0.97), (0.024, 1.0), (0.042, 0.97), (0.055, 0.88), (MC_H, 0.72)],
           (0, MC_Y), lambda p: rect_uv(MTOP, TEX, 0.5 + p[0] / MC_W, 0.5 + (p[1] - MC_Y) / MC_L), msw("black"), 0.042)
    # car cable: strain relief boot, then down to the floor at the exit (same radius as the CableFloor run)
    ys, zc = MC_Y - hy, MC_H / 2
    tube(mb, [Vector((0, ys + 0.012, zc)), Vector((0, ys - 0.03, zc))], r * 1.15, msw("black"), sides=10)
    tube(mb, catmull([(0, ys - 0.02, zc), (0, (ys + MC_EXIT_Y) / 2, r + 0.002), (0, MC_EXIT_Y, r)], 4), r, msw("rubber"))
    # adapter: collar on the box end, short cord, round wall plug with its pins pointing north
    yn, r2 = MC_Y + hy, 0.013
    lofted(mb, squircle(0.026, 0.022, 24), [(0.004, 1.0), (0.044, 1.0), (0.048, 0.8)], (0, yn + 0.012),
           flat("adapter"), msw("adapter"), 1.0)
    tube(mb, catmull([(0, yn + 0.03, 0.022), (0, yn + 0.07, r2 + 0.003), (0.035, yn + 0.13, r2), (0.03, yn + 0.18, r2)], 5),
         r2, msw("rubber"))
    bx, by, bz = 0.03, yn + 0.215, 0.032
    circle = [(0.036 * math.cos(2 * math.pi * k / 20), 0.036 * math.sin(2 * math.pi * k / 20)) for k in range(20)]
    lofted(mb, circle, [(bz + 0.03 * math.sin(math.radians(t)), math.cos(math.radians(t))) for t in range(-80, 81, 20)],
           (bx, by), flat("adapter"), msw("adapter"), 1.0)
    for x0, z0, w, h in ((-0.014, bz - 0.002, 0.004, 0.014), (0.010, bz - 0.002, 0.004, 0.014), (-0.004, bz - 0.016, 0.008, 0.008)):
        cuboid(mb, (bx + x0, by + 0.028, z0), (bx + x0 + w, by + 0.062, z0 + h), msw("metal"))
    # spare cable coiled flat beside the box: three loosely stacked loops, thinner than the exaggerated floor run so
    # the coil does not outweigh the box
    rc = r * 0.65
    for dx, dy, rx, ry, z in ((0, 0, 0.080, 0.105, rc), (-0.012, 0.010, 0.068, 0.094, rc), (0.010, -0.008, 0.075, 0.100, rc * 2.2)):
        ring = [Vector((0.20 + dx + rx * math.cos(2 * math.pi * k / 28), MC_Y + dy + ry * math.sin(2 * math.pi * k / 28), z))
                for k in range(29)]
        tube(mb, ring, rc, msw("rubber"), caps=False)
    return mb.build("MinidoracatTesla_MobileConnector", image)


# ---------------------------------------------------------------- scene, export, render

def reset():
    """Knox Pass render_tiles.reset: EEVEE, transparent film, PZ 2x iso camera (elevation 30, looking PZ NW)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.eevee.taa_render_samples = 32
    sc.render.film_transparent = True
    sc.render.filter_size = 1.0
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.color = (1, 1, 1)
    if w.node_tree:
        w.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
        w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 2.0
    sun.data.angle = math.radians(5)
    sun.rotation_euler = Vector((0.45, 0.75, -0.75)).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(sun)
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.clip_end = 100
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    d = Vector((-math.cos(math.radians(30)) / math.sqrt(2), math.cos(math.radians(30)) / math.sqrt(2),
                -math.sin(math.radians(30))))
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam["dir"] = d
    return sc


def aim(point, px, py, w, h, zoom=1.0):
    sc = bpy.context.scene
    cam = sc.camera
    sc.render.resolution_x, sc.render.resolution_y = w, h
    cam.data.sensor_fit = "AUTO"
    cam.data.ortho_scale = max(w, h) / (PX * zoom)
    rot = cam.rotation_euler.to_matrix()
    right, up, d = rot.col[0], rot.col[1], Vector(cam["dir"])
    centre = Vector(point) + right * ((w / 2 - px) / (PX * zoom)) + up * ((py - h / 2) / (PX * zoom))
    cam.location = centre - d * 30


def render(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def pz_matrix(translate, rotate):
    """glb model -> scene (x east, y north, z up) as IsoObjectModelDrawer places it (Knox Pass render_tiles.py,
    calibrated on vanilla fence gates): L = (x, z, y); M = Rx(rx) Ry(-ry) Rz(rz) L; offset (tx - M.x, -(tz + M.z))."""
    S = Matrix(((1, 0, 0), (0, 0, 1), (0, 1, 0)))
    R = (Matrix.Rotation(math.radians(rotate[0]), 3, "X") @ Matrix.Rotation(math.radians(-rotate[1]), 3, "Y")
         @ Matrix.Rotation(math.radians(rotate[2]), 3, "Z"))
    P = Matrix(((-1, 0, 0), (0, 0, -1), (0, 1, 0)))
    m = (P @ R @ S).to_4x4()
    m.translation = Vector((translate[0], -translate[2], translate[1]))
    return m


def select_only(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def export_glb(ob, path):
    select_only(ob)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_texcoords=True, export_normals=True,
                              export_materials="EXPORT", export_image_format="AUTO", export_skins=False,
                              export_animations=False, export_cameras=False, export_lights=False)


def export_fbx(ob, path):
    select_only(ob)
    bpy.ops.export_scene.fbx(filepath=str(path), use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", bake_space_transform=True,
                             axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE",
                             add_leaf_bones=False, bake_anim=False, path_mode="STRIP")


def bbox(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    return [round(min(v[i] for v in vs), 4) for i in range(3)], [round(max(v[i] for v in vs), 4) for i in range(3)]


def import_glb(path, matrix):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in bpy.data.objects if o not in before]
    root = next(o for o in new if o.parent is None)
    root.matrix_world = matrix
    return root


def import_fbx(path):
    """Fbx importer adds a Y-up -> Z-up object rotation; keep it (blender-headless.md section 7)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(path))
    return next(o for o in bpy.data.objects if o not in before and o.type == "MESH")


def floor_and_wall(facing=None):
    """Preview context: a 3x3 floor and, for a facing, the wall it needs, one floor high."""
    bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
    fl = bpy.context.object
    m = bpy.data.materials.new("floor")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.30, 0.28, 1)
    fl.data.materials.append(m)
    if facing is None:
        return
    loc = {"S": ((0, 0.53, 1.2247), 0), "N": ((0, -0.53, 1.2247), 0), "E": ((-0.53, 0, 1.2247), 90),
           "W": ((0.53, 0, 1.2247), 90)}[facing]
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc[0], rotation=(0, 0, math.radians(loc[1])))
    wall = bpy.context.object
    wall.scale = (3, 0.06, 2.44949)
    m2 = bpy.data.materials.new("wall")
    m2.use_nodes = True
    m2.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.72, 0.66, 1)
    wall.data.materials.append(m2)


def render_icon(ob, out, az, el, ortho):
    """Workbench, studio light, texture colour, orthographic 256 px transparent (items-and-icons.md section 4)."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_cavity = False
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 256
    lo, hi = bbox(ob)
    target = (Vector(lo) + Vector(hi)) / 2
    cd = bpy.data.cameras.new("IconCam")
    cd.type = "ORTHO"
    cd.ortho_scale = ortho
    cam = bpy.data.objects.new("IconCam", cd)
    sc.collection.objects.link(cam)
    a, e = math.radians(az), math.radians(el)
    cam.location = target + Vector((math.cos(e) * math.sin(a), -math.cos(e) * math.cos(a), math.sin(e))) * 3
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    render(out)


def main():
    EXP.mkdir(parents=True, exist_ok=True)
    report = []
    reset()
    wc_img = bpy.data.images.load(str(EXP / "MinidoracatTesla_WallConnector.png"))
    cb_img = bpy.data.images.load(str(EXP / "MinidoracatTesla_Cable.png"))
    wc = wall_connector(wc_img)
    report.append(f"WallConnector bbox {bbox(wc)} verts {len(wc.data.vertices)}")
    export_glb(wc, EXP / "MinidoracatTesla_WallConnector.glb")
    for ob in [cable_hang(cb_img), cable_floor(cb_img)] + [cable_plug(cb_img, n, z) for n, z in PLUGS.items()]:
        report.append(f"{ob.name} bbox {bbox(ob)} verts {len(ob.data.vertices)}")
        export_fbx(ob, EXP / f"{ob.name}.fbx")
    mc = mobile_connector(bpy.data.images.load(str(EXP / "MinidoracatTesla_MobileConnector.png")))
    report.append(f"MobileConnector bbox {bbox(mc)} verts {len(mc.data.vertices)}")
    export_glb(mc, EXP / "MinidoracatTesla_MobileConnector.glb")
    # icons from the freshly built meshes (Facing S: front toward -Y)
    for o in list(bpy.context.scene.objects):
        o.hide_render = o.name != "MinidoracatTesla_WallConnector" and o.type == "MESH"
    render_icon(wc, ICONS / "wc_icon.png", 25, 8, 0.62)
    for o in list(bpy.context.scene.objects):
        o.hide_render = o.name != "MinidoracatTesla_CablePlug" and o.type == "MESH"
    render_icon(bpy.data.objects["MinidoracatTesla_CablePlug"], ICONS / "cable_icon.png", 200, 20, 0.75)
    for o in list(bpy.context.scene.objects):
        o.hide_render = o.name != "MinidoracatTesla_MobileConnector" and o.type == "MESH"
    render_icon(mc, ICONS / "mc_icon.png", 25, 40, 0.75)

    # read back: glb placed with each facing's spriteModels transform -> 2D cells (and a preview with wall + floor)
    for facing, rot in XFORM.items():
        reset()
        ob = import_glb(EXP / "MinidoracatTesla_WallConnector.glb", pz_matrix((0, 0, 0), rot))
        report.append(f"cell {facing}: placed bbox {bbox(ob)}")
        aim((0, 0, 0), 64, 224, 128, 256)
        render(CELLS / f"wc_{facing}.png")
        floor_and_wall(facing)
        aim((0, 0, 0.5), 160, 200, 320, 320, 2.0)
        render(PREV / f"wc_{facing}_wall.png")
    # Mobile Connector: same placement on the floor, cells + floor previews
    for facing, rot in XFORM.items():
        reset()
        ob = import_glb(EXP / "MinidoracatTesla_MobileConnector.glb", pz_matrix((0, 0, 0), rot))
        report.append(f"mc cell {facing}: placed bbox {bbox(ob)}")
        aim((0, 0, 0), 64, 224, 128, 256)
        render(CELLS / f"mc_{facing}.png")
        floor_and_wall()
        aim((0, 0, 0), 160, 170, 320, 320, 3.0)
        render(PREV / f"mc_{facing}_floor.png")
    # Facing S + the floor run Cable.lua starts at the exit (h = 0: no hang); exit PZ (0, -MC_EXIT_Y) = scene MC_EXIT_Y
    reset()
    import_glb(EXP / "MinidoracatTesla_MobileConnector.glb", pz_matrix((0, 0, 0), XFORM["S"]))
    floor_and_wall()
    ob = import_fbx(EXP / "MinidoracatTesla_CableFloor.fbx")
    ob.matrix_world = Matrix.Translation((0, MC_EXIT_Y - 0.5, 0)) @ Matrix.Rotation(math.radians(-90), 4, "Z") @ ob.matrix_world
    aim((0, -0.4, 0), 160, 170, 320, 320, 3.0)
    render(PREV / "mc_cable.png")
    # read back the cable fbx: sizes in tiles, one assembled preview (charger S + hang + 2 floor + plug)
    reset()
    import_glb(EXP / "MinidoracatTesla_WallConnector.glb", pz_matrix((0, 0, 0), XFORM["S"]))
    floor_and_wall("S")
    # Facing S forward = PZ south = scene -Y; the hang origin is the exit floor point, PZ (0,-EXIT_Y) = scene +EXIT_Y
    a = EXIT_Y - HANG_REACH
    for name, y in (("Hang", EXIT_Y), ("Floor", a - 0.5), ("Floor", a - 1.5), ("Plug", a - 2.0)):
        ob = import_fbx(EXP / f"MinidoracatTesla_Cable{name}.fbx")
        report.append(f"fbx {name}: imported bbox {bbox(ob)}")
        ob.matrix_world = Matrix.Translation((0, y, 0)) @ Matrix.Rotation(math.radians(-90), 4, "Z") @ ob.matrix_world
    aim((0, -1.0, 0.4), 200, 220, 400, 400, 2.0)
    render(PREV / "cable_assembled.png")
    (OUT / "export" / "verify.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("[props_blender] " + "\n[props_blender] ".join(report))


main()
