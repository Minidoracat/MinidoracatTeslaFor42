"""Tesla Semi's 53 ft dry van (Base.MinidoracatTesla_SemiTrailer): body and dual-tyre FBX, skin / mask / lights / wheel
textures, the vehicle script and its model script. White, no markings. Stand-alone (no pzveh.py).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python scripts/blender/semi_trailer/build.py [-- render <dir>]

Units as the stage-1 prototype (branch proto/semi-1117, scripts/blender/semi_proto/build.py): Blender +Y front, +Z up,
+X the trailer's right (script +x = left), 1 unit = 1 grid (K grid per metre); script = metres x K / S. The mesh stands
on the ground at z 0 with its body centre at y 0; the model offset puts the centre of mass (physics origin) H_COM above
the ground and COM_Z behind the body centre. Wheels as pzveh (WHEEL_LIFT, physics radius - 0.015).
Physics fields are the prototype's MTSemiProtoTrailerT3 (impl-rulings 2026-11-18, semi.md section 2); check_physics()
compares them line by line with the prototype's script when its worktree is there.
Sizes (specs.md 5, XTRA / Premier 53 ft plates): 16.154 x 2.6 x 4.115 m, coupler 1.19 m (47 in), kingpin 0.914 m (36 in)
behind the nose, tandem slider at the back (axles 12.47 / 13.72 m), 295/75R22.5 duals (r 0.49, w 0.27).
Looks as the trailer in tesla.com/semi's hero photo (temp/plan-semi-1117/img/teslacom/Semi-Main-Hero-Desktop-v3.jpg):
sheet-and-post sides, tall polished lower rail with spaced tape, radiused polished nose corners, nose vent, aero side
skirts, white steel wheels. No maker's badge. The rear is a generic swing-door dry van (no official photo shows it)."""
import bpy, bmesh, math, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MEDIA = os.path.join(REPO, "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media")
VEH_DIR = os.path.join(MEDIA, "models_X", "vehicles")
TEX_DIR = os.path.join(MEDIA, "textures", "Vehicles")
PROTO = os.path.join(REPO, "..", "wt-semi-proto", "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media",
                     "scripts", "vehicles", "MTSemiProto.txt")
NAME = "MinidoracatTesla_SemiTrailer"
K, S, LIFT = 0.826, 1.82, 0.11

# ---- physics: the prototype's T3 (do not change without a new stage-1 run) ----
MASS, WHEEL_FRICTION, ROLL, STOP_FORCE, STIFF = 400, 4.0, 0.3, 2.0, 40.0
H_COM = 1.0                              # centre of mass above the ground (m)
NOSE_SHARE = 0.12                        # static load on the kingpin: COM 12 % of kingpin-tandem ahead of the tandem

# ---- geometry (metres; d = distance behind the nose) ----
R_TIRE, W_TIRE = 0.49, 0.27
DUAL, DUAL_GAP = 0.925, 0.167            # dual pair centre (physics wheel), each tyre that far either side of it
TL, TW, TH, T_FLOOR = 16.154, 2.6, 4.115, 1.25
T_AX = (12.47, 13.72)
KINGPIN, FIFTH_H = 0.914, 1.19
LEG_D, LEG_LEN, LEG_W, LEG_X, LEG_LOW = 3.2, 0.3, 0.25, 0.9, 0.15
REAR = TL - 0.04                         # door face (the rear frame stands 4 cm proud of it)
TAPE = (0.18, 0.28)                      # DOT-C2 conspicuity tape: red, white segment lengths
NOSE_R = 0.16                            # nose corner radius
RAIL_H = 0.36                            # lower side rail above the floor line
SKIRT = (LEG_D + 0.65, T_AX[0] - R_TIRE - 0.30, 0.36)   # aero skirt: from, to (d), lower edge above the ground


def sc(m):            # metres -> script units
    return m * K / S


def g(m):             # metres -> grid
    return m * K


def f4(*v):
    return " ".join(f"{x:.4f}" for x in v)


# ---------------- UV0 atlas (u, v in 0..1, v up) ----------------
# islands: planar maps of the big faces; swatches: flat colours, every loop at the cell centre
SIDE_UV = ((0.004, 0.996), (0.565, 0.985))     # u along d, v along z (T_FLOOR..TH); both sides share it
ROOF_UV = ((0.004, 0.996), (0.430, 0.545))     # u along d, v along x
REAR_UV = ((0.005, 0.355), (0.005, 0.395))     # u along x (left to right seen from behind), v along z
FRONT_UV = ((0.385, 0.735), (0.005, 0.395))    # u along x (left to right seen from the front), v along z
SW_U0, SW_V0, SW_CELL, SW_COLS = 0.76, 0.005, 32 / 1024, 7
SWATCH = {   # sRGB 0..1
    "alu": (0.78, 0.79, 0.80), "frame": (0.86, 0.87, 0.87), "steel": (0.42, 0.43, 0.44), "chassis": (0.10, 0.10, 0.11),
    "under": (0.20, 0.20, 0.21), "rubber": (0.06, 0.06, 0.06), "tape_r": (0.80, 0.08, 0.07), "tape_w": (0.95, 0.95, 0.93),
    "lens_l": (0.62, 0.05, 0.05), "lens_r": (0.62, 0.05, 0.05), "marker_r": (0.70, 0.08, 0.06),
    "marker_a": (0.95, 0.55, 0.08), "galv": (0.58, 0.60, 0.60), "plate": (0.16, 0.16, 0.17), "white": (0.90, 0.90, 0.89),
}
LENS_ZONE = {"lens_l": (0.50, 0.75, 0.00), "lens_r": (0.50, 0.25, 0.00)}   # mask StopLights L / R (vehicle_common.frag.h)
LIT_RGB = (1.0, 0.12, 0.12)


def swatch_uv(name):
    i = list(SWATCH).index(name)
    return (SW_U0 + (i % SW_COLS + 0.5) * SW_CELL, SW_V0 + (i // SW_COLS + 0.5) * SW_CELL)


def lerp(r, t):
    return r[0] + (r[1] - r[0]) * t


def uv0(kind, x, d, z):
    if kind == "side":
        return lerp(SIDE_UV[0], d / TL), lerp(SIDE_UV[1], (z - T_FLOOR) / (TH - T_FLOOR))
    if kind == "roof":
        return lerp(ROOF_UV[0], d / TL), lerp(ROOF_UV[1], (x + TW / 2) / TW)
    if kind == "rear":       # seen from behind the trailer's left is on the viewer's right
        return lerp(REAR_UV[0], (-x + TW / 2) / TW), lerp(REAR_UV[1], (z - T_FLOOR) / (TH - T_FLOOR))
    if kind == "front":
        return lerp(FRONT_UV[0], (x + TW / 2) / TW), lerp(FRONT_UV[1], (z - T_FLOOR) / (TH - T_FLOOR))
    return swatch_uv(kind)


# UV1: the shared 512 maps (Veh_Damage1/2, Veh_Rust, Veh_Blood_*) in vanilla Vehicle_StepVan's layout, the vanilla box
# body nearest to this one (its UV1 plotted on Veh_Damage1): sides on the top strip, roof on its roof panel, ends on a
# rear panel. The trailer is cut in thirds along its length (each about StepVan's 5.1 m) so the pattern keeps StepVan's
# density. Only rust really shows: the trailer has no part behind any damage zone (TrailerTrunk is not TruckBed,
# BaseVehicle.java:6221-6297), same as vanilla Trailer.
THIRD = TL / 3


def uv1(axis, x, d, z, k):
    t = (d - k * THIRD) / THIRD
    if axis == 0:
        return 0.03 + 0.74 * t, 0.87 + 0.115 * min(max((z - 0.15) / (TH - 0.15), 0), 1)
    if axis == 2:
        return 0.094 + 0.236 * t, 0.47 + 0.18 * (x + 1.32) / 2.64
    return 0.57 + 0.15 * (x + 1.32) / 2.64, 0.346 + 0.09 * min(max((z - 0.15) / (TH - 0.15), 0), 1)


# ---------------- mesh ----------------
class Mesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv0 = self.bm.loops.layers.uv.new("UV0")
        self.uv1 = self.bm.loops.layers.uv.new("UV1")

    def quad(self, pts, out, kind, smooth=False):
        """pts: 4 (x, d, z) metres; out: wanted outward normal (mesh axes); kind: UV0 island or swatch."""
        vs = [self.bm.verts.new((g(x), g(TL / 2 - d), g(z))) for x, d, z in pts]
        f = self.bm.faces.new(vs)
        f.normal_update()
        if f.normal.dot(out) < 0:
            f.normal_flip()
        f.smooth = smooth
        ax = max(range(3), key=lambda i: abs(out[i]))
        cd = sum(p[1] for p in pts) / len(pts)
        k = min(int(cd // THIRD), 2)
        for lp in f.loops:
            x, y, z = (c / K for c in lp.vert.co)
            d = TL / 2 - y
            lp[self.uv0].uv = uv0(kind, x, d, z)
            lp[self.uv1].uv = uv1(ax, x, d, z, k)
        return f

    def box(self, x0, x1, d0, d1, z0, z1, kind, faces="xyzXYZ", side_kind=None):
        """Axis box; faces: which sides (lower = -, upper = + in mesh axes: x right, y front, z up)."""
        sides = {
            "x": ([(x0, d0, z0), (x0, d1, z0), (x0, d1, z1), (x0, d0, z1)], (-1, 0, 0)),
            "X": ([(x1, d0, z0), (x1, d1, z0), (x1, d1, z1), (x1, d0, z1)], (1, 0, 0)),
            "y": ([(x0, d1, z0), (x1, d1, z0), (x1, d1, z1), (x0, d1, z1)], (0, -1, 0)),   # rear (larger d)
            "Y": ([(x0, d0, z0), (x1, d0, z0), (x1, d0, z1), (x0, d0, z1)], (0, 1, 0)),    # front
            "z": ([(x0, d0, z0), (x1, d0, z0), (x1, d1, z0), (x0, d1, z0)], (0, 0, -1)),
            "Z": ([(x0, d0, z1), (x1, d0, z1), (x1, d1, z1), (x0, d1, z1)], (0, 0, 1)),
        }
        for key in faces:
            pts, out = sides[key]
            self.quad(pts, out, (side_kind or {}).get(key, kind))

    def tape(self, x, d0, d1, z0, z1, out, gap=0.0):
        """Red / white conspicuity tape along d on a face at x (out = +-1), red first; gap: bare rail after each pair."""
        d, red = d0, True
        while d < d1 - 0.01:
            e = min(d + TAPE[0 if red else 1], d1)
            self.quad([(x, d, z0), (x, e, z0), (x, e, z1), (x, d, z1)], (out, 0, 0), "tape_r" if red else "tape_w")
            d, red = (e, False) if red else (e + gap, True)

    def tape_x(self, d, x0, x1, z0, z1, horizontal=True):
        """Tape on a rear-facing face at d: along x (horizontal) or along z (vertical, x0..x1 its width)."""
        a, b = (x0, x1) if horizontal else (z0, z1)
        t, red = a, True
        while t < b - 0.01:
            e = min(t + TAPE[0 if red else 1], b)
            pts = ([(t, d, z0), (e, d, z0), (e, d, z1), (t, d, z1)] if horizontal
                   else [(x0, d, t), (x1, d, t), (x1, d, e), (x0, d, e)])
            self.quad(pts, (0, -1, 0), "tape_r" if red else "tape_w")
            t, red = e, not red

    def slab(self, a, b, z0, z1, s, kind, t=0.03):
        """Upright panel from a to b ((x, d) of its outer face, a in front, on side s = +-1), t thick inwards."""
        (xa, da), (xb, db) = a, b
        nx, nd = db - da, xa - xb
        if nx * s < 0:
            nx, nd = -nx, -nd
        ix, id_ = -nx / math.hypot(nx, nd) * t, -nd / math.hypot(nx, nd) * t
        self.quad([(xa, da, z0), (xb, db, z0), (xb, db, z1), (xa, da, z1)], (nx, -nd, 0), kind)
        self.quad([(xa + ix, da + id_, z0), (xb + ix, db + id_, z0), (xb + ix, db + id_, z1), (xa + ix, da + id_, z1)],
                  (-nx, nd, 0), kind)
        self.quad([(xa, da, z0), (xb, db, z0), (xb + ix, db + id_, z0), (xa + ix, da + id_, z0)], (0, 0, -1), kind)
        for x, d, o in ((xa, da, 1), (xb, db, -1)):
            self.quad([(x, d, z0), (x + ix, d + id_, z0), (x + ix, d + id_, z1), (x, d, z1)], (0, o, 0), kind)

    def finish(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def body():
    m = Mesh()
    hw = TW / 2
    R, W = NOSE_R, NOSE_R + 0.02          # nose corners: the skin, the polished wrap standing 2 cm proud of it
    wrap_d, nx = R + 0.12, hw - R - 0.10  # where the wrap ends on the side (d) and on the nose (x)

    def arc(s, r, n=4):                   # (x, d) from the nose face round to the side
        return [(s * (hw - R + r * math.sin(t)), R - r * math.cos(t)) for t in np.linspace(0, math.pi / 2, n + 1)]

    # box: sides and roof in thirds (UV1 thirds); the rear face is the doors, the bottom the floor's underside; the
    # first third's roof and floor follow the radiused nose corners
    for k in range(3):
        a, b = k * THIRD, min((k + 1) * THIRD, REAR)
        if k:
            m.box(-hw, hw, a, b, T_FLOOR, TH, "side", faces="xXzZ", side_kind={"z": "under", "Z": "roof"})
            continue
        m.box(-hw, hw, R, b, T_FLOOR, TH, "side", faces="xX")
        for z, up, kind in ((TH, 1, "roof"), (T_FLOOR, -1, "under")):
            m.quad([(-hw + R, 0, z), (hw - R, 0, z), (hw - R, b, z), (-hw + R, b, z)], (0, 0, up), kind)
            for s in (-1, 1):
                m.quad([(s * (hw - R), R, z), (s * hw, R, z), (s * hw, b, z), (s * (hw - R), b, z)], (0, 0, up), kind)
                p = arc(s, R)
                for i in range(len(p) - 1):
                    m.quad([(s * (hw - R), R, z), (*p[i], z), (*p[i + 1], z)], (0, 0, up), kind)
    m.quad([(-hw + R, 0, T_FLOOR), (hw - R, 0, T_FLOOR), (hw - R, 0, TH), (-hw + R, 0, TH)], (0, 1, 0), "front")
    m.quad([(-hw, REAR, T_FLOOR), (hw, REAR, T_FLOOR), (hw, REAR, TH), (-hw, REAR, TH)], (0, -1, 0), "rear")
    # rails: top and bottom along both sides and across the nose; spaced tape on the tall bottom rails
    for s in (-1, 1):
        xo, xi = s * (hw + 0.015), s * hw
        m.box(min(xo, xi), max(xo, xi), wrap_d, REAR, TH - 0.115, TH, "alu", faces="xXzZ")
        x2 = s * (hw + 0.035)             # upper amber clearance lamp at the front of the side
        m.box(min(xo, x2), max(xo, x2), wrap_d + 0.06, wrap_d + 0.16, TH - 0.085, TH - 0.035, "marker_a")
        xo = s * (hw + 0.02)
        m.box(min(xo, xi), max(xo, xi), wrap_d, REAR, T_FLOOR - 0.08, T_FLOOR + RAIL_H, "alu", faces="xXzZ")
        m.tape(xo + s * 0.002, 0.46, REAR - 0.3, T_FLOOR + 0.025, T_FLOOR + 0.075, s, gap=sum(TAPE))
        # polished wrap round the nose corner, full height: nose flat, arc, side flat; end and top caps
        outer = [(s * nx, -0.02)] + arc(s, W) + [(s * (hw + 0.02), wrap_d)]
        inner = [(s * nx, 0)] + arc(s, R) + [(s * hw, wrap_d)]
        for i in range(len(outer) - 1):
            (x0, d0), (x1, d1) = outer[i], outer[i + 1]
            out = ((x0 + x1) / 2 - s * (hw - R), R - (d0 + d1) / 2, 0)
            m.quad([(x0, d0, T_FLOOR - 0.08), (x1, d1, T_FLOOR - 0.08), (x1, d1, TH), (x0, d0, TH)], out, "alu")
            m.quad([(*inner[i], TH), (x0, d0, TH), (x1, d1, TH), (*inner[i + 1], TH)], (0, 0, 1), "alu")
        m.quad([(s * nx, -0.02, T_FLOOR - 0.08), (s * nx, 0, T_FLOOR - 0.08), (s * nx, 0, TH), (s * nx, -0.02, TH)],
               (-s, 0, 0), "alu")
        m.quad([(s * hw, wrap_d, T_FLOOR - 0.08), (s * (hw + 0.02), wrap_d, T_FLOOR - 0.08), (s * (hw + 0.02), wrap_d, TH),
                (s * hw, wrap_d, TH)], (0, -1, 0), "alu")
        # side marker lamps: amber at the front and the middle, red at the rear (on the bottom rail, above the tape)
        for dd, kind in ((0.40, "marker_a"), (TL / 2, "marker_a"), (REAR - 0.25, "marker_r")):
            m.box(min(xo, x2), max(xo, x2), dd - 0.05, dd + 0.05, T_FLOOR + 0.11, T_FLOOR + 0.16, kind)
    m.box(-nx, nx, -0.015, 0, TH - 0.115, TH, "alu", faces="YzZ")
    m.box(-nx, nx, -0.02, 0, T_FLOOR - 0.08, T_FLOOR + 0.15, "alu", faces="YzZ")
    # front: upper amber clearance lamps; on the driver's (left) side the vent with its louvres, the document box and
    # the electrical / air connection plate with the 7-way socket
    for s in (-1, 1):
        m.box(s * (nx - 0.10) - 0.04, s * (nx - 0.10) + 0.04, -0.03, -0.015, TH - 0.10, TH - 0.04, "marker_a", faces="xXYzZ")
    m.box(-hw + 0.30, -hw + 0.64, -0.035, 0, TH - 0.44, TH - 0.15, "galv", faces="xXYzZ")
    for zc in np.arange(TH - 0.40, TH - 0.18, 0.055):
        m.quad([(-hw + 0.33, -0.037, zc), (-hw + 0.61, -0.037, zc), (-hw + 0.61, -0.037, zc + 0.025),
                (-hw + 0.33, -0.037, zc + 0.025)], (0, 1, 0), "plate")
    m.box(-hw + 0.30, -hw + 0.50, -0.06, 0, 1.88, 2.22, "plate", faces="xXYzZ")
    m.box(-hw + 0.28, -hw + 0.52, -0.02, 0, 1.48, 1.70, "galv", faces="xXYzZ")
    m.box(-hw + 0.36, -hw + 0.44, -0.05, -0.02, 1.55, 1.63, "plate", faces="xXYzZ")
    # rear frame: corner posts, header, sill (lamps and tape on it)
    for s in (-1, 1):
        a, b = sorted((s * (hw - 0.14), s * (hw + 0.02)))
        m.box(a, b, REAR - 0.04, TL, 1.0, TH, "frame", faces="xXyZ")
        # vertical tape on the upper corners, red marker lamps on top of the posts
        c, e = sorted((s * (hw - 0.12), s * (hw - 0.02)))
        m.tape_x(TL + 0.002, c, e, TH - 0.62, TH - 0.06, horizontal=False)
        m.box(c, e, TL - 0.01, TL + 0.03, TH - 0.05, TH - 0.01, "marker_r", faces="xXyzZ")
    m.box(-hw + 0.14, hw - 0.14, REAR - 0.02, TL, TH - 0.18, TH, "frame", faces="yzZ")
    m.box(-hw - 0.02, hw + 0.02, REAR - 0.06, TL, 1.0, T_FLOOR + 0.06, "plate", faces="xXyzZ")
    m.tape_x(TL + 0.002, -hw + 0.32, hw - 0.32, T_FLOOR - 0.02, T_FLOOR + 0.05)
    for x in (-0.15, 0.0, 0.15):          # three ID lamps on the header
        m.box(x - 0.04, x + 0.04, TL - 0.0, TL + 0.03, TH - 0.12, TH - 0.07, "marker_r", faces="xXyzZ")
    for s, lens in ((-1, "lens_l"), (1, "lens_r")):    # two stop / tail lamps a side on the sill
        for xc in (0.86, 1.06):
            m.box(s * xc - 0.07, s * xc + 0.07, TL, TL + 0.025, 1.06, 1.19, lens, faces="xXyzZ")
    # doors: four lock rods with cam keepers and handles, hinges on the outer edges
    for xc in (-1.0, -0.32, 0.32, 1.0):
        m.box(xc - 0.018, xc + 0.018, REAR, REAR + 0.035, 1.33, TH - 0.2, "galv", faces="xXyzZ")
        for zc in (1.36, TH - 0.23):
            m.box(xc - 0.05, xc + 0.05, REAR, REAR + 0.025, zc - 0.035, zc + 0.035, "steel", faces="xXyzZ")
        hx = xc + (0.22 if xc < 0 else -0.22)          # handle lever towards the door's middle
        m.box(min(xc, hx), max(xc, hx), REAR + 0.035, REAR + 0.06, 1.62, 1.67, "galv", faces="xXyzZ")
    for s in (-1, 1):
        for zc in (1.55, 2.15, 2.75, 3.35, 3.85):
            a, b = sorted((s * (hw - 0.30), s * (hw - 0.14)))
            m.box(a, b, REAR, REAR + 0.02, zc - 0.05, zc + 0.05, "steel", faces="xXyzZ")
    # underframe: coupler plate with the kingpin, main beams
    m.box(-hw + 0.08, hw - 0.08, 0.02, 1.7, FIFTH_H, T_FLOOR, "plate", faces="xXyYz")
    m.box(-0.045, 0.045, KINGPIN - 0.045, KINGPIN + 0.045, FIFTH_H - 0.07, FIFTH_H, "steel", faces="xXyYz")
    for s in (-1, 1):
        a, b = sorted((s * 0.42, s * 0.56))
        m.box(a, b, 1.7, REAR - 0.3, 0.98, T_FLOOR, "chassis", faces="xXyYz")
    for dd in np.arange(2.0, REAR - 0.3, 1.2):          # crossmember ends showing under the side rail
        for s in (-1, 1):
            a, b = sorted((s * 0.56, s * (hw - 0.05)))
            m.box(a, b, dd - 0.04, dd + 0.04, T_FLOOR - 0.12, T_FLOOR, "chassis", faces="xXyYz")
    # aero side skirts between the landing gear and the tandem, toed in at the front, rubber lower edge
    k0, k1, kz = SKIRT
    for s in (-1, 1):
        for a, b in (((s * (hw - 0.40), k0), (s * (hw - 0.02), k0 + 1.1)), ((s * (hw - 0.02), k0 + 1.1), (s * (hw - 0.02), k1))):
            m.slab(a, b, kz, kz + 0.06, s, "rubber")
            m.slab(a, b, kz + 0.06, T_FLOOR - 0.08, s, "frame")
    # landing gear: outer tube, inner leg, sand shoe (the collision box: 0.25 x 0.30, bottom LEG_LOW), cross shaft,
    # brace to the main beam; gear box and crank handle on the curb (right) side
    for s in (-1, 1):
        xc = s * LEG_X
        m.box(xc - 0.075, xc + 0.075, LEG_D - 0.075, LEG_D + 0.075, 0.55, T_FLOOR, "galv", faces="xXyYz")
        m.box(xc - 0.05, xc + 0.05, LEG_D - 0.05, LEG_D + 0.05, LEG_LOW + 0.05, 0.55, "steel", faces="xXyY")
        m.box(xc - LEG_W / 2, xc + LEG_W / 2, LEG_D - LEG_LEN / 2, LEG_D + LEG_LEN / 2, LEG_LOW, LEG_LOW + 0.05, "steel")
        a, b = sorted((s * 0.56, s * (LEG_X - 0.075)))
        m.box(a, b, LEG_D - 0.025, LEG_D + 0.025, 0.85, 0.90, "galv", faces="yYzZ")
    m.box(-LEG_X + 0.075, LEG_X - 0.075, LEG_D - 0.02, LEG_D + 0.02, 0.97, 1.01, "steel", faces="yYzZ")
    m.box(LEG_X + 0.075, LEG_X + 0.20, LEG_D - 0.09, LEG_D + 0.09, 0.88, 1.10, "galv")
    m.box(LEG_X + 0.20, LEG_X + 0.23, LEG_D - 0.02, LEG_D + 0.02, 0.62, 1.00, "steel", faces="xXyYz")
    m.box(LEG_X + 0.20, LEG_X + 0.36, LEG_D - 0.02, LEG_D + 0.02, 0.60, 0.64, "rubber")
    # tandem slider: rails, crossmembers, axle tubes, hangers, air springs
    s0, s1 = T_AX[0] - 0.8, T_AX[1] + 0.6
    for s in (-1, 1):
        a, b = sorted((s * 0.40, s * 0.60))
        m.box(a, b, s0, s1, 0.92, T_FLOOR - 0.12, "chassis", faces="xXyYz")
    for dd in (s0 + 0.2, (s0 + s1) / 2, s1 - 0.2):
        m.box(-0.40, 0.40, dd - 0.05, dd + 0.05, 1.0, 1.12, "chassis", faces="yYz")
    inner = DUAL - DUAL_GAP - W_TIRE / 2 - 0.01
    for ax in T_AX:
        m.box(-inner, inner, ax - 0.06, ax + 0.06, R_TIRE - 0.06, R_TIRE + 0.06, "chassis", faces="yYzZ")
        for s in (-1, 1):
            a, b = sorted((s * 0.44, s * 0.56))
            m.box(a, b, ax - 0.30, ax - 0.20, R_TIRE + 0.06, 0.92, "steel", faces="xXyYz")     # hanger
            m.box(a, b, ax - 0.30, ax + 0.06, R_TIRE - 0.02, R_TIRE + 0.06, "steel", faces="xXyYz")  # trailing arm
            m.box(a - 0.02, b + 0.02, ax + 0.14, ax + 0.36, R_TIRE + 0.10, 0.92, "rubber", faces="xXyYz")  # air spring
    # mud flaps behind the rear axle on a bar
    fd = T_AX[1] + R_TIRE + 0.18
    m.box(-hw + 0.05, hw - 0.05, fd - 0.03, fd + 0.03, 0.95, 1.0, "alu", faces="xXyYzZ")
    for s in (-1, 1):
        a, b = sorted((s * (DUAL - 0.32), s * (DUAL + 0.32)))
        m.box(a, b, fd, fd + 0.012, 0.25, 0.95, "rubber", faces="xXyYz")
    # rear impact guard (ICC bar) with tape on its back
    bd = TL - 0.32
    m.box(-hw + 0.12, hw - 0.12, bd - 0.05, bd + 0.05, 0.45, 0.58, "chassis")
    m.tape_x(bd + 0.052, -hw + 0.16, hw - 0.16, 0.465, 0.565)
    for s in (-1, 1):
        a, b = sorted((s * 0.62, s * 0.72))
        m.box(a, b, bd - 0.04, bd + 0.04, 0.58, 1.0, "chassis", faces="xXyY")
        m.box(a, b, bd - 0.04, REAR - 0.06, 0.94, 1.0, "chassis", faces="xXyz")
    return m.finish(NAME)


# ---------------- dual tyres ----------------
WHEEL = {"tread": (0.07, 0.07, 0.07), "side": (0.13, 0.13, 0.14), "rim": (0.88, 0.88, 0.87), "disc": (0.84, 0.84, 0.83),
         "hole": (0.05, 0.05, 0.05), "hub": (0.30, 0.30, 0.31), "nut": (0.85, 0.85, 0.86)}
W_CELLS = 4


def wheel_uv(name):
    i = list(WHEEL).index(name)
    return ((i % W_CELLS + 0.5) / W_CELLS, (i // W_CELLS + 0.5) / W_CELLS)


# half profile, outer face to the tyre's mid plane: (radius, x from the mid plane, swatch of the band ending here,
# smooth). Mirrored for the inner face; 22.5 in rim (r 0.286), 10 hand holes on the disc
def wheel_profile():
    r, h = R_TIRE, W_TIRE / 2
    return [(0.0, h - 0.035, None, False), (0.07, h - 0.035, "hub", False), (0.09, h - 0.055, "hub", False),
            (0.15, h - 0.055, "disc", False), (0.21, h - 0.055, "holes", False), (0.255, h - 0.05, "disc", False),
            (0.285, h - 0.012, "rim", False), (0.30, h - 0.005, "rim", False), (r - 0.06, h, "side", True),
            (r - 0.015, h - 0.025, "side", True), (r, h - 0.045, "tread", True), (r, 0.0, "tread", True)]


def wheel():
    bm = bmesh.new()
    uvl = [bm.loops.layers.uv.new(n) for n in ("UV0", "UV1")]     # two equal layers (vehiclewheel reads location 3)
    n = 20
    half = wheel_profile()
    for xc in (-g(DUAL_GAP), g(DUAL_GAP)):
        prof = [(rad, x, sw, sm) for rad, x, sw, sm in half] + \
               [(rad, -x, sw, sm) for rad, x, sw, sm in reversed(half[:-1])]
        bands = [prof[i + 1][2] if i < len(half) - 1 else prof[i][2] for i in range(len(prof) - 1)]
        smooth = [prof[i + 1][3] if i < len(half) - 1 else prof[i][3] for i in range(len(prof) - 1)]
        rings = []
        for rad, x, _, _ in prof:
            if rad == 0:
                rings.append([bm.verts.new((xc + g(x), 0, 0))])
            else:
                rings.append([bm.verts.new((xc + g(x), g(rad) * math.cos(2 * math.pi * j / n),
                                            g(rad) * math.sin(2 * math.pi * j / n))) for j in range(n)])
        for i, sw in enumerate(bands):
            a, b = rings[i], rings[i + 1]
            for j in range(n):
                k = (j + 1) % n
                if len(a) == 1:
                    vs = (a[0], b[j], b[k])
                elif len(b) == 1:
                    vs = (a[j], a[k], b[0])
                else:
                    vs = (a[j], a[k], b[k], b[j])
                f = bm.faces.new(vs)
                f.smooth = smooth[i]
                name = ("hole" if j % 2 == 0 else "disc") if sw == "holes" else sw
                for lp in f.loops:
                    for L in uvl:
                        lp[L].uv = wheel_uv(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)     # each tyre is one closed surface
    me = bpy.data.meshes.new(NAME + "_Wheel")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(me.name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ---------------- textures ----------------
def save_png(name, rgba):
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(rgba, np.float32).ravel())
    img.filepath_raw = os.path.join(TEX_DIR, name + ".png")
    img.file_format = "PNG"
    img.save()
    return img


def region(n, r, pad=6):
    """Pixel slices (rows = v from the bottom, cols = u) of a UV rect ((u0, u1), (v0, v1)) grown by pad px, and the
    island coordinates (0..1, clamped in the pad) of every pixel centre."""
    (u0, u1), (v0, v1) = r
    c0, c1 = max(int(u0 * n) - pad, 0), min(int(math.ceil(u1 * n)) + pad, n)
    r0, r1 = max(int(v0 * n) - pad, 0), min(int(math.ceil(v1 * n)) + pad, n)
    uu = np.clip(((np.arange(c0, c1) + 0.5) / n - u0) / (u1 - u0), 0, 1)
    vv = np.clip(((np.arange(r0, r1) + 0.5) / n - v0) / (v1 - v0), 0, 1)
    return (slice(r0, r1), slice(c0, c1)), np.meshgrid(uu, vv)


def lines(t, at, width):
    """1 where t (metres) is within width/2 of any of at."""
    return (np.abs(t[..., None] - np.asarray(at)) < width / 2).any(-1)


def skin(n=1024):
    px = np.zeros((n, n, 4), np.float32)
    px[..., :3], px[..., 3] = 0.5, 1.0
    white = np.array(SWATCH["white"], np.float32)
    # sides: sheet and post, posts every 0.61 m (24 in) with two rivet rows each, sheet laps every 1.22 m; road grime
    # on the lowest 0.5 m
    sl, (u, v) = region(n, SIDE_UV)
    d, z = u * TL, T_FLOOR + v * (TH - T_FLOOR)
    c = np.broadcast_to(white, d.shape + (3,)).copy()
    post = np.arange(0.305, TL, 0.61)
    rivet = lines(d, np.concatenate((post - 0.04, post + 0.04)), 0.022) & (np.abs(((z - T_FLOOR) / 0.1) % 1 - 0.5) < 0.13)
    c[lines(d, np.arange(1.22, TL, 1.22), 0.02)] *= 0.93
    c[rivet] *= 0.74
    c *= (1 - 0.10 * np.clip((T_FLOOR + 0.5 - z) / 0.5, 0, 1))[..., None]
    px[sl][..., :3] = c
    # roof: translucent-white panel with the roof bows every 0.6 m
    sl, (u, v) = region(n, ROOF_UV)
    d = u * TL
    c = np.broadcast_to(np.array((0.82, 0.83, 0.84), np.float32), d.shape + (3,)).copy()
    c[lines(d, np.arange(0.3, TL, 0.6), 0.05)] *= 0.90
    px[sl][..., :3] = c
    # rear doors: two leaves meeting at the middle (dark gap), edge shadows at the frame, grime at the bottom
    sl, (u, v) = region(n, REAR_UV)
    x, z = u * TW - TW / 2, T_FLOOR + v * (TH - T_FLOOR)
    c = np.broadcast_to(white, x.shape + (3,)).copy()
    c[np.abs(x) < 0.012] = 0.18
    c[np.abs(x) > TW / 2 - 0.16] *= 0.80
    c[z > TH - 0.2] *= 0.85
    c[lines(z, (1.95, 2.85), 0.02)] *= 0.93
    c *= (1 - 0.12 * np.clip((T_FLOOR + 0.4 - z) / 0.4, 0, 1))[..., None]
    px[sl][..., :3] = c
    # front wall: plain, a little grime low down
    sl, (u, v) = region(n, FRONT_UV)
    z = T_FLOOR + v * (TH - T_FLOOR)
    c = np.broadcast_to(white, z.shape + (3,)).copy()
    c *= (1 - 0.15 * np.clip((T_FLOOR + 0.6 - z) / 0.6, 0, 1))[..., None]
    px[sl][..., :3] = c
    for name, rgb in SWATCH.items():
        su, sv = swatch_uv(name)
        h = SW_CELL / 2
        sl, _ = region(n, ((su - h, su + h), (sv - h, sv + h)), pad=0)
        px[sl][..., :3] = rgb
    # the four corners in pzveh.CABIN_UV0_RGB (scripts/skin_check.py gates every Tesla skin; Viewpoint reads them);
    # no face of this trailer samples there (the rear island's corner is behind the right corner post)
    for rs in (slice(0, 12), slice(n - 12, n)):
        for cs in (slice(0, 12), slice(n - 12, n)):
            px[rs, cs, :3] = np.array((52, 52, 56)) / 255
    return px


def zone_maps(n=512):
    """Mask (Roof everywhere, the tail lamp lenses StopLights L / R) and lights (lens red, alpha 1; rest clear)."""
    mask = np.zeros((n, n, 4), np.float32)
    mask[..., 3] = 1.0
    lit = np.zeros((n, n, 4), np.float32)
    for name, zone in LENS_ZONE.items():
        su, sv = swatch_uv(name)
        h = SW_CELL / 2
        sl, _ = region(n, ((su - h, su + h), (sv - h, sv + h)), pad=0)
        mask[sl][..., :3] = zone
        lit[sl] = (*LIT_RGB, 1.0)
    return mask, lit


def wheel_tex(n=64):
    px = np.zeros((n, n, 4), np.float32)
    c = n // W_CELLS
    for i, rgb in enumerate(WHEEL.values()):
        cx, cy = i % W_CELLS, i // W_CELLS
        px[cy * c:(cy + 1) * c, cx * c:(cx + 1) * c] = (*rgb, 1.0)
    return px


def export(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.fbx(filepath=os.path.join(VEH_DIR, ob.name + ".fbx"), use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", bake_space_transform=True, axis_forward="-Z",
                             axis_up="Y", mesh_smooth_type="OFF", add_leaf_bones=False, bake_anim=False, path_mode="STRIP")


# ---------------- scripts (physics as the prototype's T3) ----------------
def wheel_lines(name, front, x_m, z_m):
    return [f"        wheel {name}", "        {", f"            front = {'true' if front else 'false'},",
            f"            offset = {f4(sc(x_m), (g(R_TIRE) - LIFT) / S, sc(z_m))},",
            f"            radius = {(g(R_TIRE) - 0.015) / S:.4f},", f"            width = {g(W_TIRE):.4f},", "        }"]


def pbox(x_m, z_m, w_m, l_m, h0, h1, com_z):
    return ["        physics box", "        {", f"            offset = {f4(sc(x_m), (g((h0 + h1) / 2) - g(H_COM)) / S, sc(z_m - com_z))},",
            f"            extents = {f4(sc(w_m), sc(h1 - h0), sc(l_m))},", "        }"]


def attach(name, x_m, h_m, z_m, can=None):
    return [f"        attachment {name}", "        {", f"            offset = {f4(sc(x_m), sc(h_m), sc(z_m))},",
            "            rotate = 0.0 0.0 0.0,", *([f"            canAttach = {can},"] if can else []), "        }"]


def area_at(name, x, y, w, h):
    return [f"        area {name}", "        {", f"            xywh = {f4(x, y, w, h)},", "        }"]


def vehicle_script():
    zc = TL / 2
    z1, z2 = (zc - a for a in T_AX)
    aw = 0.4725
    sx = sc(TW / 2) + aw / 2
    tan = sum(T_AX) / 2
    cz = zc - (tan - NOSE_SHARE * (tan - KINGPIN))     # COM along the body (+ = ahead of the body centre)
    h = g(H_COM)
    out = ["/* GENERATED by scripts/blender/semi_trailer/build.py: do not edit; change the generator and rebuild */",
           "module Base", "{", f"    vehicle {NAME}", "    {",
           "        /* Tesla Semi's 53 ft dry van. Physics = stage-1 prototype MTSemiProtoTrailerT3 (semi.md 2); only the",
           "           Semi hitches it (mtsemi_kingpin <-> mtsemi_fifthwheel, no vanilla trailer attachment) */",
           "        neverSpawnKey = true,", "        mechanicType = 1,", "        offRoadEfficiency = 0.8,",
           "        engineRepairLevel = 4,", "        playerDamageProtection = 0.8,",
           "        forcedColor = 0.0 0.0 0.9,",
           "        model", "        {", f"            file = {NAME},", f"            scale = {S},",
           f"            offset = {f4(0, -h / S, -sc(cz))},", "        }",
           "        skin", "        {", f"            texture = Vehicles/{NAME},", "        }",
           f"        textureMask = Vehicles/{NAME}_mask,", f"        textureLights = Vehicles/{NAME}_lights,",
           "        textureDamage1Overlay = Vehicles/Veh_Blood_Mask,", "        textureDamage2Overlay = Vehicles/Veh_Blood_Hvy,",
           "        textureDamage1Shell = Vehicles/Veh_Damage1,", "        textureDamage2Shell = Vehicles/Veh_Damage2,",
           "        textureRust = Vehicles/Veh_Rust,",
           f"        extents = {f4(sc(TW), sc(TH), sc(TL))},", f"        physicsChassisShape = {f4(sc(TW), sc(TH), sc(TL))},",
           f"        centerOfMassOffset = {f4(0, (g(TH / 2) - h) / S, -sc(cz))},",
           f"        shadowExtents = {f4(sc(TW), sc(TL))},", f"        shadowOffset = {f4(0, -sc(cz))},",
           f"        mass = {MASS},", "        engineForce = 3600,", "        engineQuality = 60,", "        engineLoudness = 55,",
           "        maxSpeed = 105.0,", "        brakingForce = 1,", f"        stoppingMovementForce = {STOP_FORCE},",
           f"        rollInfluence = {ROLL},", "        steeringIncrement = 0.03,", "        steeringClamp = 0.3,",
           f"        suspensionStiffness = {STIFF},", "        suspensionCompression = 3.83,",
           "        suspensionDamping = 4.88,", "        maxSuspensionTravelCm = 10.0,", "        suspensionRestLength = 0.2,",
           f"        wheelFriction = {WHEEL_FRICTION},", "        frontEndHealth = 150,", "        rearEndHealth = 150,",
           "        seats = 2,",
           # a whole `template = X` clears the physics boxes and resets useChassisPhysicsCollision
           # (VehicleScript.java:1226-1241,1298-1305): every whole template before both
           "        template = Trunk/part/TrailerTrunk,", "        template = Tire,", "        template = Brake,",
           "        template = Suspension,",
           # after its template line: a template line copies over the part (VehicleScript.java:1271-1295)
           "        /* 300: the user's pick 2026-11-18 (vanilla's trailer 100, StepVan 160). Vanilla writes it into the trunk item */",
           "        /* on spawn (Vehicles.lua:1181-1183); a spare TrailerTrunk fitted later holds its own 100 */",
           "        part TrailerTrunk", "        {", "            container", "            {",
           "                capacity = 300,", "            }", "        }",
           "        useChassisPhysicsCollision = false,",
           *pbox(0, 0, TW, TL, T_FLOOR, TH, cz),
           *pbox(LEG_X, zc - LEG_D, LEG_W, LEG_LEN, LEG_LOW, T_FLOOR, cz),
           *pbox(-LEG_X, zc - LEG_D, LEG_W, LEG_LEN, LEG_LOW, T_FLOOR, cz),
           *wheel_lines("FrontLeft", True, DUAL, z1), *wheel_lines("FrontRight", True, -DUAL, z1),
           *wheel_lines("RearLeft", False, DUAL, z2), *wheel_lines("RearRight", False, -DUAL, z2)]
    out += area_at("TruckBed", 0, -(sc(TL / 2) + aw / 2) - sc(cz), sc(TW), aw)
    for nm, x, z in (("FrontLeft", sx, z1), ("FrontRight", -sx, z1), ("RearLeft", sx, z2), ("RearRight", -sx, z2)):
        out += area_at("Tire" + nm, x, sc(z) - sc(cz), aw, aw)
    out += ["        part Tire*", "        {", "            model InflatedTirePlusWheel", "            {",
            f"                file = {NAME}_Wheel,", "            }", "        }"]
    out += attach("mtsemi_kingpin", 0, FIFTH_H, zc - KINGPIN, "mtsemi_fifthwheel")
    out += ["    }", "}", ""]
    return out


def model_script():
    return ["/* GENERATED by scripts/blender/semi_trailer/build.py. Meshes in grid units: model scale 1 / vehicle scale 1.82 */",
            "module Base", "{", f"    model {NAME}", "    {", f"        mesh = vehicles/{NAME},", "        shader = vehicle,",
            "        static = true,", "        invertX = false,", f"        scale = {1 / S:.4f},", "    }", "",
            f"    model {NAME}_Wheel", "    {", f"        mesh = vehicles/{NAME}_Wheel,",
            f"        texture = Vehicles/{NAME}_wheel,", "        shader = vehiclewheel,", f"        scale = {1 / S:.4f},",
            "    }", "}", ""]


def check_physics(lines):
    """The script's lines equal MTSemiProtoTrailerT3's but for names, textures, the comment, the dropped vanilla
    `attachment trailer`, the prototype's measuring points and the trunk's capacity (the user's pick; the cargo's
    weight is the load's, no script field). Prints the table; fails on any other difference."""
    if not os.path.exists(PROTO):
        print("PHYSICS proto script not found, skipped:", PROTO)
        return
    t = open(PROTO, encoding="utf-8").read().split("\n")
    a = t.index("    vehicle MTSemiProtoTrailerT3")
    proto = t[a:t.index("    }", a) + 1]

    def norm(ls):
        out, skip, depth = [], False, 0
        for s in ls:
            s = s.strip()
            if s.startswith("/*") or s.startswith("Semi hitches") or s == "forcedColor = 0.0 0.0 0.9,":
                continue
            if s in ("attachment trailer", "part TrailerTrunk") or s.startswith(("attachment mtsemi_leg", "attachment mtsemi_c_")):
                skip = True
            if skip:
                depth += (s == "{") - (s == "}")
                skip = not (s == "}" and depth == 0)
                continue
            for old, new in (("MTSemiProtoTrailerT3", NAME), ("MTSemiProto_Trailer", NAME), ("MTSemiProto_shell", NAME),
                             ("MTSemiProto_mask", NAME + "_mask"), ("MTSemiProto_lights", NAME + "_lights"),
                             ("MTSemiProto_Dual", NAME + "_Wheel")):
                s = s.replace(old, new)
            out.append(s)
        return out
    ours = lines[lines.index(f"    vehicle {NAME}"):lines.index("    }", lines.index(f"    vehicle {NAME}")) + 1]
    p, o = norm(proto), norm(ours)
    keys = ("mass", "engineForce", "maxSpeed", "brakingForce", "stoppingMovementForce", "rollInfluence", "steeringClamp",
            "suspensionStiffness", "suspensionCompression", "suspensionDamping", "maxSuspensionTravelCm",
            "suspensionRestLength", "wheelFriction", "extents", "physicsChassisShape", "centerOfMassOffset", "offset",
            "radius", "width", "front", "xywh")
    print("PHYSICS lines compared", len(o), "proto", len(p), "equal", p == o)
    for x, y in zip(p, o):
        if x.split(" = ")[0] in keys:
            print(f"PHYSICS {x:<48} | {y}")
    if p != o:
        import difflib
        print("\n".join(difflib.unified_diff(p, o, "MTSemiProtoTrailerT3", NAME, lineterm="")))
        raise SystemExit("PHYSICS differs from MTSemiProtoTrailerT3")


def write_scripts():
    vs = vehicle_script()
    check_physics(vs)
    open(os.path.join(MEDIA, "scripts", "vehicles", NAME + ".txt"), "w", newline="\n").write("\n".join(vs))
    open(os.path.join(MEDIA, "scripts", "models", NAME + ".txt"), "w", newline="\n").write("\n".join(model_script()))


# ---------------- offline renders (Workbench, textures as in game, no shader lighting) ----------------
def render(out_dir, ob, wob):
    import mathutils
    os.makedirs(out_dir, exist_ok=True)
    sc_ = bpy.context.scene
    tex = bpy.data.images.load(os.path.join(TEX_DIR, NAME + ".png"))
    wtex = bpy.data.images.load(os.path.join(TEX_DIR, NAME + "_wheel.png"))
    for o, im in ((ob, tex), (wob, wtex)):
        mat = bpy.data.materials.new(o.name)
        mat.use_nodes = True
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image, node.interpolation = im, "Closest" if im is wtex else "Linear"
        mat.node_tree.links.new(node.outputs[0], mat.node_tree.nodes["Principled BSDF"].inputs[0])
        mat.node_tree.nodes.active = node
        o.data.materials.append(mat)
        o.data.uv_layers.active = o.data.uv_layers["UV0"]
    wob.hide_render = True
    for i, (xm, ax) in enumerate(((DUAL, T_AX[0]), (-DUAL, T_AX[0]), (DUAL, T_AX[1]), (-DUAL, T_AX[1]))):
        w = bpy.data.objects.new(f"w{i}", wob.data)
        w.location = (g(xm), g(TL / 2 - ax), g(R_TIRE))
        sc_.collection.objects.link(w)
    ground = bpy.data.meshes.new("ground")
    ground.from_pydata([(-30, -30, 0), (30, -30, 0), (30, 30, 0), (-30, 30, 0)], [], [(0, 1, 2, 3)])
    gob = bpy.data.objects.new("ground", ground)
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.20, 0.21, 0.20, 1)
    gob.data.materials.append(gm)
    sc_.collection.objects.link(gob)
    # Cycles on the CPU: Workbench / EEVEE need a GPU context, which crashes blender -b here (GPU_fence_signal)
    sc_.render.engine = "CYCLES"
    sc_.cycles.device, sc_.cycles.samples = "CPU", 32
    sc_.render.resolution_x, sc_.render.resolution_y = 1600, 900
    sc_.world = bpy.data.worlds.new("w")
    sc_.world.use_nodes = True
    sc_.world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.80, 0.88, 1)
    sc_.world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(40), math.radians(15), math.radians(-35))
    sc_.collection.objects.link(sun)
    sc_.view_settings.view_transform = "Standard"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc_.collection.objects.link(cam)
    sc_.camera = cam
    L, Hh = g(TL), g(TH)
    views = {   # name: (location, look-at, ortho scale or None = perspective lens mm)
        "front": ((0, 40, Hh / 2), (0, 0, Hh / 2), g(8.0)),     # ortho scale spans the 16:9 width
        "rear": ((0, -40, Hh / 2), (0, 0, Hh / 2), g(8.0)),
        "left": ((-40, 0, Hh / 2), (0, 0, Hh / 2), L * 1.08),
        "top": ((0, 0, 60), (0, 0, 0), L * 1.08),
        "34": ((-g(9.5), g(16.0), g(5.2)), (0, g(1.5), g(1.4)), None),
        "34rear": ((g(7.5), -g(15.0), g(4.5)), (0, -g(3.0), g(1.6)), None),
        "hero": ((-g(4.5), g(TL / 2 + 5.5), g(1.5)), (-g(TW / 2), g(TL / 2 - 6.0), g(2.2)), None),   # as the hero photo
    }
    for nm, (loc, at, ortho) in views.items():
        cam.location = loc
        dirv = mathutils.Vector(at) - mathutils.Vector(loc)
        cam.rotation_euler = dirv.to_track_quat("-Z", "Y" if nm != "top" else "Y").to_euler()
        if nm == "top":
            cam.rotation_euler = (0, 0, -math.pi / 2)
        cam.data.type = "ORTHO" if ortho else "PERSP"
        if ortho:
            cam.data.ortho_scale = ortho
        else:
            cam.data.lens = 28
        cam.data.clip_end = 200
        sc_.render.filepath = os.path.join(out_dir, f"trailer-{nm}.png")
        bpy.ops.render.render(write_still=True)
        print("RENDER", sc_.render.filepath)


def faces(ob):
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    return len(ob.data.polygons), tris


bpy.ops.wm.read_factory_settings(use_empty=True)
os.makedirs(VEH_DIR, exist_ok=True)
save_png(NAME, skin())
mask, lit = zone_maps()
save_png(NAME + "_mask", mask)
save_png(NAME + "_lights", lit)
save_png(NAME + "_wheel", wheel_tex())
body_ob, wheel_ob = body(), wheel()
for o in (body_ob, wheel_ob):
    export(o)
    print("FACES", o.name, "polygons %d triangles %d" % faces(o))
write_scripts()
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if argv[:1] == ["render"]:
    render(argv[1], body_ob, wheel_ob)
print("SEMITRAILER built")
