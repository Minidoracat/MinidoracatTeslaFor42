"""Blender 5.2 headless: Wall Connector + Mobile Connector Gen 3 + V4 Supercharger meshes + cable segments -> glb/fbx,
2D tile cells, icons, previews.

blender -b --factory-startup --python props_blender.py -- <temp dir> [--cpu] [wc mc sc cable]
  (build.py runs this; textures come from build.py). --cpu renders with Cycles on the CPU (EEVEE and Workbench crash
  without a GPU, e.g. the VM). Devices listed = only those are built; none = all.

Units: 1 Blender unit = 1 PZ tile edge. Heights are in the same unit (1 floor = 2.44949 units).
Wall Connector (IsoObject, glb): built for Facing S with spriteModels rotate (0,180,0): Blender +X = PZ east,
  +Y = PZ north (the wall), front toward -Y. Origin = tile centre on the floor (IsoObject.java:3540).
  Real unit H 345 x W 155 x D 110 mm (Tesla Gen 3 install manual); drawn 1.3x so it reads at game zoom.
Mobile Connector (IsoObject, glb): same frame, lying on the floor; control box 179.8 x 81.7 x 47.3 mm drawn 1.3x.
  The car cable ends on the floor at (0, MC_EXIT_Y, R_CABLE), where Cable.lua starts the floor run (h = 0, no hang).
Supercharger V4 (IsoObject, glb): same frame, real size 0.891 x 0.334 x 1.946 (datasheet), back on the tile's north
  edge; its car cable runs from the top of the east frame down to the floor at SC_EXIT (h = 0, no hang).
Cable segments (WorldItems, fbx, Render3DItem): model +X = the direction passed as the Render3DItem angle
  (atan2(dy, dx) in PZ degrees, ItemModelRenderer.java:260-268,908-921 + Core.java:2578-2587), +Z up; the model
  script has undoCoreScale so 1 mesh unit = 1 tile (ModelScript.java:106-108).
  Hang:  origin = floor point under the charger's cable exit; exit at (0,0,EXIT_Z); reaches the floor at +X HANG_REACH.
  Floor: straight, x -0.5..0.5 (origin = segment midpoint).
  Plug:  one per car (PLUGS: mesh name -> handle height); origin = floor point; rises and ends in the handle tip at
         (PLUG_REACH, 0, z) pointing +X (into the car).
Keep EXIT_Z/HANG_REACH/PLUG_REACH/MC_EXIT_Y/SC_EXIT in sync with Cable.lua and Chargers.lua cableExit, PLUGS with Core.lua
T.Specs plug (build.py --check).
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT = Path(ARGS[0]).resolve()
CPU = "--cpu" in ARGS
ONLY = {a for a in ARGS[1:] if not a.startswith("--")} or {"wc", "mc", "sc", "cable"}
MODMEDIA = OUT.parent.parent / "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media"
REPORT = []
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
         "MinidoracatTesla_CablePlugCybertruck": 0.90,        # Cybertruck (tesla-ctbody-1030c: port 0.902)
         "MinidoracatTesla_CablePlugModelS": 0.73,            # Model S
         "MinidoracatTesla_CablePlugModelX": 0.84}            # Model X (tesla-mx-1101b modelx-sp: port 0.837)
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
# Supercharger V4 post, Facing S frame, real size (Tesla datasheet 334 x 891 x 1946 mm, 1 unit ~ 1 m, not enlarged):
# back on the tile's north edge; black body whose plan is a U channel (west spine, east frame) holding the convex white
# shell, plinth at the floor, holster bracket on the west side (the post's left). Plugged in (the shipped mesh): empty
# holster, car cable out of the top of the east frame, down the east edge and onto the floor at SC_EXIT (Cable.lua's
# floor run starts there: Chargers.lua cableExit = (SC_EXIT[0], -SC_EXIT[1], 0), no hang). Official photo
# v4-official.jpg.
SC_W, SC_D, SC_H = 0.891, 0.334, 1.946        # width (x), depth (y), height
SC_BACK = 0.48                                # back face y; front of the shell at its centre = SC_BACK - SC_D
SC_EXIT = (0.40, 0.04)                        # car cable lies on the floor here, heading south (x east, y north)
# white shell, front view: centre x, half width, U tip z, top z, U depth, top corner radius, bulge (edges behind centre)
SC_SHELL = (0.015, 0.41, 0.18, 1.92, 0.40, 0.07, 0.05)
SC_LOGO_Z = (1.545, 1.685)                    # shell band textured from SLOGO (TESLA at twice SPANEL's texel density)
SC_LIGHT = (-0.35, -0.80, 0.50)               # light baked into the texture, model frame (front-left-top)
SPANEL = (4, 2, 124, 196)                     # Supercharger 256 px atlas: shell front (light baked by build.py)
SLOGO = (4, 204, 252, 252)                    # shell band SC_LOGO_Z across its full width, with the red TESLA
# ramps 120 x 12 px, dark (u 0) .. lit (u 1): every other Supercharger face samples its baked light (sc_shade) here
SSW = {"black": (132, 4), "base": (132, 20), "holster": (132, 36), "rubber": (132, 52), "white": (132, 68)}
SGRILLE = (132, 88, 252, 136)                 # side ribs: u = baked light like the ramps, v = 12 ribs across the depth


def ramp_uv(name, s):
    x, y = SSW[name]
    return (x + 2 + s * 116) / TEX, 1.0 - (y + 6) / TEX


def grille_uv(s, t):
    x0, y0, x1, y1 = SGRILLE
    return (x0 + 2 + s * (x1 - x0 - 4)) / TEX, 1.0 - (y0 + t * (y1 - y0)) / TEX


def sc_shade(p, n):
    """Baked light for the Supercharger (in daylight PZ lights a static model flat: basicEffect.frag clamps the sum
    to 1): key light SC_LIGHT, a brighter top, a sky sheen up the height, darker toward the floor."""
    s = 0.16 + 0.45 * max(0.0, n.dot(Vector(SC_LIGHT).normalized())) + 0.18 * max(0.0, n.z) + 0.14 * p[2] / SC_H
    return max(0.0, min(1.0, s * (0.55 + 0.45 * min(1.0, p[2] / 0.3))))


def newell(pts):
    n = Vector()
    for a, b in zip(pts, pts[1:] + pts[:1]):
        n += Vector(((a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])))
    return n.normalized()


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
        if isinstance(sw, str):                   # Supercharger ramp name: per-vertex baked light
            n = newell(pts)
            self.face(pts, [ramp_uv(sw, sc_shade(p, n)) for p in pts])
            return
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


# ---------------------------------------------------------------- Supercharger V4

def offset(outline, d):
    """Plan outline (XY, counter-clockwise from above) moved inward by d, mitred corners."""
    out = []
    for i, p in enumerate(outline):
        p, a, b = Vector(p), Vector(outline[i - 1]), Vector(outline[(i + 1) % len(outline)])
        e1, e2 = (p - a).normalized(), (b - p).normalized()
        n1, n2 = Vector((-e1.y, e1.x)), Vector((-e2.y, e2.x))
        m = (n1 + n2).normalized()
        out.append(p + m * (d / m.dot(n1)))
    return out


def column(mb, outline, rings, ramp, bottom=False):
    """Plan outline stacked at rings (z, inset, half width): inset pulls the ring inward (bevels), half width clamps |x|
    (rounded corners seen from the front); top cap, bottom cap if asked."""
    loops = [[(max(-hw, min(hw, p.x)), p.y, z) for p in offset(outline, d)] for z, d, hw in rings]
    if bottom:
        mb.patch(list(reversed(loops[0])), ramp)
    n = len(outline)
    for a, b in zip(loops, loops[1:]):
        for k in range(n):
            mb.patch([a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]], ramp)
    mb.patch(loops[-1], ramp)


def rect_xy(x0, y0, x1, y1, c):
    return [(x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c), (x0 + c, y0), (x1 - c, y0), (x1, y0 + c)]


def bevel_box(mb, lo, hi, c, ramp):
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    column(mb, rect_xy(x0, y0, x1, y1, c), [(z0, c, 9), (z0 + c, 0, 9), (z1 - c, 0, 9), (z1, c, 9)], ramp, bottom=True)


def supercharger(image, idle=False):
    """Facing S post on the tile's north edge (v4-official.jpg): black body whose plan is a U channel (west spine, east
    frame) with rounded top corners, plinth, convex white shell with a U-shaped bottom in the channel (TESLA on the
    atlas), holster bracket on the west side. Light is baked: shell in SPANEL/SLOGO (build.py), the rest per vertex
    through the ramps (sc_shade).
    idle=False (shipped, plugged in): empty holster; the car cable leaves the top of the east frame and runs down the east
    edge onto the floor at SC_EXIT, where Cable.lua carries on to the car's handle.
    idle=True (official idle look, not shipped): handle in the holster; the cable runs down the east edge, loops in
    front of the shell's bottom and up the west side into the handle."""
    mb = MB()
    y_front, y_back = SC_BACK - SC_D, SC_BACK
    hx, c = SC_W / 2, 0.012
    xc, r, zb, zt, rv, rc, bulge = SC_SHELL
    # plinth, its front lip 2.5 cm proud of the frames
    bevel_box(mb, (-hx, 0.165, 0), (hx, y_back, 0.07), c, "base")
    # body: spine (west) and frame (east) 4 cm in front of the channel back that holds the shell; top corners rounded
    yf, yc, xl, xr, c2 = 0.19, 0.23, xc - r - 0.003, xc + r + 0.003, 0.006
    plan = [(hx, y_back - c), (hx - c, y_back), (-hx + c, y_back), (-hx, y_back - c), (-hx, yf + c), (-hx + c, yf),
            (xl - c, yf), (xl, yf + c), (xl, yc), (xr, yc), (xr, yf + c2), (xr + c2, yf), (hx - c2, yf), (hx, yf + c2)]
    rt = 0.06
    top = [(SC_H - rt + rt * math.sin(math.radians(a)), 0, hx - rt * (1 - math.cos(math.radians(a)))) for a in (30, 60, 80)]
    column(mb, plan, [(0.07, 0, hx), (SC_H - rt, 0, hx)] + top + [(SC_H, 0.006, hx - rt)], "black")
    # lid over the channel above the shell: a thin black edge from the front (photo), no white rim seen from behind
    bevel_box(mb, (-(hx - rt), yf + 0.006, zt + 0.004), (hx - rt, yc + 0.004, SC_H - 0.002), 0.004, "black")
    # white shell: convex across its width, U-shaped bottom, rounded top corners; the TESLA band maps to SLOGO
    lz0, lz1 = SC_LOGO_Z
    rows = [(zb + rv * (1 - math.cos(a)), r * math.sin(a)) for a in (math.radians(d) for d in range(0, 90, 10))]
    rows += [(z, r) for z in sorted({zb + rv + (zt - rc - zb - rv) * k / 5 for k in range(5)} | {lz0, lz1})]
    rows += [(zt - rc + rc * math.sin(a), r - rc + rc * math.cos(a)) for a in (math.radians(d) for d in range(0, 91, 30))]
    cols = [-1 + 2 * j / 12 for j in range(13)]

    def yshell(x):
        return y_front + bulge * ((x - xc) / r) ** 2

    def front_uv(x, z, logo):
        if logo:
            return rect_uv(SLOGO, TEX, 0.5 + (x - xc) / (2 * r), (z - lz0) / (lz1 - lz0))
        return rect_uv(SPANEL, TEX, 0.5 + (x - xc) / (2 * r), (z - zb) / (zt - zb))

    grid = [[(xc + u * hw, z) for u in cols] for z, hw in rows]
    for lo, hi in zip(grid, grid[1:]):
        logo = lo[0][1] >= lz0 - 1e-6 and hi[0][1] <= lz1 + 1e-6
        for j in range(len(cols) - 1):
            xz = [lo[j], lo[j + 1], hi[j + 1], hi[j]]          # counter-clockwise seen from the front (-Y)
            mb.face([(x, yshell(x), z) for x, z in xz], [front_uv(x, z, logo) for x, z in xz])
    rim = [row[-1] for row in grid] + grid[-1][-2:0:-1] + [row[0] for row in reversed(grid)]
    for (ax, az), (bx, bz) in zip(rim, rim[1:]):
        if (ax, az) != (bx, bz):
            mb.patch([(ax, yshell(ax), az), (ax, yc + 0.01, az), (bx, yc + 0.01, bz), (bx, yshell(bx), bz)], "white")
    # cooling ribs down both sides (official close-up): quads just off the side faces, u = baked light, v = rib stripes
    g0, g1 = 0.205, 0.465
    for sx in (-1, 1):
        x, n = sx * (hx + 0.0008), Vector((sx, 0, 0))
        for z0, z1 in ((0.10, 0.30), (0.30, 1.0), (1.0, 1.86)):
            pts = [(x, g0, z0), (x, g1, z0), (x, g1, z1), (x, g0, z1)][::sx]
            mb.face(pts, [grille_uv(sc_shade(p, n), (p[1] - g0) / (g1 - g0)) for p in pts])
    # holster on the spine's west side at the front (official close-up): a wedge sloping down and out that the handle's
    # head sits under, a small rest below it
    prism(mb, [(-hx + 0.003, 1.235), (-hx + 0.003, 1.45), (-0.49, 1.33), (-0.51, 1.31), (-0.512, 1.27), (-0.50, 1.255)],
          0.16, 0.33, lambda x, z: ramp_uv("holster", sc_shade((x, 0, z), Vector((0, -1, 0)))), lambda *a: "holster",
          "holster")
    bevel_box(mb, (-0.478, 0.26, 0.95), (-hx + 0.003, 0.32, 1.02), 0.01, "holster")
    # car cable out of a boot at the top of the east frame, down the east edge
    ex, ey = SC_EXIT
    rr = R_CABLE
    tube(mb, [Vector((0.42, 0.31, 1.84)), Vector((0.468, 0.29, 1.80))], rr * 1.5, "holster", sides=10)
    down = [(0.45, 0.30, 1.82), (0.474, 0.26, 1.70), (0.478, 0.21, 1.35), (0.474, 0.18, 0.80)]
    if not idle:   # onto the floor at SC_EXIT heading south
        path = down + [(0.462, 0.15, 0.35), (0.44, 0.11, 0.10), (ex + 0.01, ey + 0.035, rr + 0.004), (ex, ey, rr)]
        tube(mb, catmull(path, 5), rr, "rubber")
        return mb.build("MinidoracatTesla_Supercharger", image)
    # idle: loop in front of the shell's bottom, up the west side into the handle hanging in the holster
    gx, gy = -0.488, 0.235
    path = down + [(0.45, 0.12, 0.38), (0.30, 0.06, 0.15), (0.0, 0.045, 0.10), (-0.30, 0.06, 0.16), (-0.47, 0.13, 0.42),
                   (-0.495, 0.20, 0.75), (gx, gy, 0.97)]
    tube(mb, catmull(path, 5), rr, "rubber")
    lofted(mb, squircle(0.022, 0.048, 16), [(0.96, 0.55), (1.0, 0.85), (1.06, 1.0), (1.22, 1.0), (1.30, 0.8)], (gx, gy),
           lambda p: ramp_uv("holster", 0.6), "holster", 9)
    return mb.build("MinidoracatTesla_SuperchargerIdle", image)


# ---------------------------------------------------------------- scene, export, render

def reset():
    """Knox Pass render_tiles.reset: EEVEE (Cycles CPU with --cpu), transparent film, PZ 2x iso camera (elevation 30,
    looking PZ NW)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    if CPU:
        sc.render.engine = "CYCLES"
        sc.cycles.device = "CPU"
        sc.cycles.samples = 48
    else:
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
    """Workbench, studio light, texture colour, orthographic 256 px transparent (items-and-icons.md section 4).
    --cpu: Cycles CPU under the white world of reset() (Workbench needs a GPU context too)."""
    sc = bpy.context.scene
    if not CPU:
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


def cells(prefix, glb, preview):
    """glb placed with each facing's spriteModels transform -> 2D cells + a preview (wall for the Wall Connector)."""
    for facing, rot in XFORM.items():
        reset()
        ob = import_glb(glb, pz_matrix((0, 0, 0), rot))
        REPORT.append(f"{prefix} cell {facing}: placed bbox {bbox(ob)}")
        aim((0, 0, 0), 64, 224, 128, 256)
        render(CELLS / f"{prefix}_{facing}.png")
        floor_and_wall(facing if prefix == "wc" else None)
        aim(*preview)
        render(PREV / f"{prefix}_{facing}_{'wall' if prefix == 'wc' else 'floor'}.png")


def asset(dev, name):
    """A mesh this run built (EXP) or, for a device not rebuilt, the one the MOD ships: a clean temp/props/export
    holds only this run's devices (build.py --only)."""
    if dev in ONLY:
        return EXP / name
    return MODMEDIA / "models_X" / ("WorldItems" if name.endswith(".fbx") else "IsoObject") / name


def place_cable(name, x, y):
    """Cable fbx laid toward PZ south (scene -Y) with its origin at scene (x, y)."""
    path = asset("cable", f"MinidoracatTesla_Cable{name}.fbx")
    ob = import_fbx(path)
    ob.matrix_world = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(-90), 4, "Z") @ ob.matrix_world
    return ob


def icon(ob, name, *view):
    for o in list(bpy.context.scene.objects):
        o.hide_render = o.type == "MESH" and o != ob
    render_icon(ob, ICONS / name, *view)


def main():
    EXP.mkdir(parents=True, exist_ok=True)
    reset()
    built = {}
    if "wc" in ONLY:
        built["wc"] = wall_connector(bpy.data.images.load(str(EXP / "MinidoracatTesla_WallConnector.png")))
    if "cable" in ONLY:
        cb_img = bpy.data.images.load(str(EXP / "MinidoracatTesla_Cable.png"))
        for ob in [cable_hang(cb_img), cable_floor(cb_img)] + [cable_plug(cb_img, n, z) for n, z in PLUGS.items()]:
            REPORT.append(f"{ob.name} bbox {bbox(ob)} verts {len(ob.data.vertices)}")
            export_fbx(ob, EXP / f"{ob.name}.fbx")
    if "mc" in ONLY:
        built["mc"] = mobile_connector(bpy.data.images.load(str(EXP / "MinidoracatTesla_MobileConnector.png")))
    if "sc" in ONLY:
        sc_img = bpy.data.images.load(str(EXP / "MinidoracatTesla_Supercharger.png"))
        built["sc"] = supercharger(sc_img)
        built["sc_idle"] = supercharger(sc_img, idle=True)   # preview only: build.py ships the plugged-in mesh
    for ob in built.values():
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        REPORT.append(f"{ob.name} bbox {bbox(ob)} verts {len(ob.data.vertices)} tris {tris}")
        export_glb(ob, EXP / f"{ob.name}.glb")
    # icons from the freshly built meshes (Facing S: front toward -Y)
    if "wc" in ONLY:
        icon(built["wc"], "wc_icon.png", 25, 8, 0.62)
    if "cable" in ONLY:
        icon(bpy.data.objects["MinidoracatTesla_CablePlug"], "cable_icon.png", 200, 20, 0.75)
    if "mc" in ONLY:
        icon(built["mc"], "mc_icon.png", 25, 40, 0.75)
    if "sc" in ONLY:
        icon(built["sc"], "sc_icon.png", 25, 12, 2.1)

    if "wc" in ONLY:
        cells("wc", EXP / "MinidoracatTesla_WallConnector.glb", ((0, 0, 0.5), 160, 200, 320, 320, 2.0))
    if "mc" in ONLY:
        cells("mc", EXP / "MinidoracatTesla_MobileConnector.glb", ((0, 0, 0), 160, 170, 320, 320, 3.0))
        # Facing S + the floor run Cable.lua starts at the exit (h = 0: no hang); exit PZ (0, -MC_EXIT_Y) = scene MC_EXIT_Y
        reset()
        import_glb(EXP / "MinidoracatTesla_MobileConnector.glb", pz_matrix((0, 0, 0), XFORM["S"]))
        floor_and_wall()
        place_cable("Floor", 0, MC_EXIT_Y - 0.5)
        aim((0, -0.4, 0), 160, 170, 320, 320, 3.0)
        render(PREV / "mc_cable.png")
    if "sc" in ONLY:
        cells("sc", EXP / "MinidoracatTesla_Supercharger.glb", ((0, 0, 0.8), 160, 160, 320, 320, 1.2))
        # Facing S + the floor run from SC_EXIT (h = 0: no hang) toward PZ south and a Model Y plug
        reset()
        import_glb(EXP / "MinidoracatTesla_Supercharger.glb", pz_matrix((0, 0, 0), XFORM["S"]))
        floor_and_wall()
        ex, ey = SC_EXIT
        for name, y in (("Floor", ey - 0.5), ("Floor", ey - 1.5), ("Plug", ey - 2.0)):
            place_cable(name, ex, y)
        aim((0.2, -0.8, 0.6), 200, 200, 400, 400, 1.3)
        render(PREV / "sc_cable.png")
        # the official idle look (handle in the holster, cable looped in front), for the user to compare
        reset()
        import_glb(EXP / "MinidoracatTesla_SuperchargerIdle.glb", pz_matrix((0, 0, 0), XFORM["S"]))
        floor_and_wall()
        aim((0, 0, 0.8), 160, 160, 320, 320, 1.2)
        render(PREV / "sc_idle_S_floor.png")
    if "wc" in ONLY or "cable" in ONLY:
        # read back the cable fbx: sizes in tiles, one assembled preview (charger S + hang + 2 floor + plug)
        reset()
        import_glb(asset("wc", "MinidoracatTesla_WallConnector.glb"), pz_matrix((0, 0, 0), XFORM["S"]))
        floor_and_wall("S")
        # Facing S forward = PZ south = scene -Y; the hang origin is the exit floor point, PZ (0,-EXIT_Y) = scene +EXIT_Y
        a = EXIT_Y - HANG_REACH
        for name, y in (("Hang", EXIT_Y), ("Floor", a - 0.5), ("Floor", a - 1.5), ("Plug", a - 2.0)):
            REPORT.append(f"fbx {name}: imported bbox {bbox(place_cable(name, 0, y))}")
        aim((0, -1.0, 0.4), 200, 220, 400, 400, 2.0)
        render(PREV / "cable_assembled.png")
    (OUT / "export" / "verify.txt").write_text("\n".join(REPORT) + "\n", encoding="utf-8")
    print("[props_blender] " + "\n[props_blender] ".join(REPORT))

main()
