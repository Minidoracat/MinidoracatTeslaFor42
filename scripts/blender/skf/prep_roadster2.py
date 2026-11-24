"""Roadster 2 (Rocket) body shell from scratch (no model file is read): drawn on Tesla's own pictures only
(temp/plan-next-1114/assets/official-roadster2/: 02 side, 03 front, 01 / 00 rear, 08 front 3/4, extra Slide-2 rear
deck, x-sawyer rear 3/4 with the wing up; the 2026-11-19 unveil stream 05:40 / 05:44 plan views).
Shape (round 4 on): the car is folded flat facets, so the body is a loft of cross sections whose vertices each carry
one feature line (sill top, lower crease, shoulder, belt, fender ridge, hood edge, roof rail, buttress edges ...):
  - section(y): 12 points per side (u0 floor centre .. u11 top centre), mirrored; faces between stations are flat
    quads, so a feature line is a mesh edge and a material boundary falls on edges;
  - nose / tail: the end stations capped, split at the sill top (black below);
  - Blender exact booleans cut the wheel houses, the recess under the hood's lamp bar, the tail lamp band, the plate
    recess and the black cavity with the nozzles; the cutters carry their own materials;
  - smooth shading split at 25 deg: a crease renders as one line.
The wing (the deck plate between the flying buttresses, behind the seam) is its own object; the body's deck under it
is lowered and black. Small parts: 4 bell nozzles and 4 fans in the cavity, wheels (light disc, 6 dark blades).
Sizes (fixed by the main agent, 2026-11-24): L 4.10, W 1.88, H 1.10, wheelbase 2.664; see
temp/plan-roadster2-1124/build/R2Body.md.
Frame (as prep_roadster / prep_cybercab): metres, +Y front, +Z up, -X the car's left, ground 0, y 0 half way.
    "$B" -b --factory-startup --python scripts/blender/skf/prep_roadster2.py [-- <out dir>]
        -> <out dir>/roadster2_src.blend, roadster2_src.glb, roadster2_lines.json, prep_report.json
           (default temp/skf_r2)
Everything above `# ---- Blender` is plain numpy (importable without bpy).
"""
import json
import math
import os
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT_DIR = os.path.join(REPO, "temp", "skf_r2")

L, WIDTH, HEIGHT = 4.10, 1.88, 1.10

# ---- tables (y, value); 02 side read at 475.4 px/m (ground through the two tyre bottoms), 03 front, 01 rear at the
# plate's scale, 08 front 3/4 (hood corners triangulated near / far)
# side silhouette top: fender ridge, windshield, roof, buttress tops
TOP = [(2.05, 0.44), (2.0, 0.478), (1.831, 0.572), (1.663, 0.634), (1.495, 0.682), (1.326, 0.724), (1.19, 0.753),
       (1.074, 0.79), (0.906, 0.853), (0.737, 0.916), (0.569, 0.968), (0.401, 1.02), (0.232, 1.061), (0.064, 1.09),
       (-0.083, 1.10), (-0.293, 1.095), (-0.525, 1.073), (-0.777, 1.052), (-0.946, 1.032), (-1.24, 0.983),
       (-1.45, 0.944), (-1.703, 0.891), (-1.955, 0.844), (-2.055, 0.829)]
# plan half width of the vertical side: the nose corners chamfered from the bar ends back to the pods (03: 0.94),
# the tail corners chamfered into the rear face (825: a vertical crease, then the corner facet)
HW = [(2.05, 0.66), (1.95, 0.78), (1.80, 0.88), (1.60, 0.94), (1.27, 0.94), (0.95, 0.93), (0.75, 0.92), (0.0, 0.905),
      (-0.75, 0.92), (-1.39, 0.94), (-1.80, 0.925), (-1.95, 0.905), (-2.055, 0.84)]
FLOOR = [(2.05, 0.13), (1.58, 0.10), (0.95, 0.13), (-1.80, 0.13), (-2.055, 0.18)]
# black sill's top edge, rising to the rear wheel (02: 0.225 at y 0.94, 0.37 at -1.03); behind it the black rear
# corners and the lower rear (825, 01); the nose below the lamp bar is all dark (03, 08: the caps, see main)
SILL = [(2.05, 0.21), (0.94, 0.225), (-1.03, 0.37), (-1.40, 0.47), (-1.80, 0.55), (-2.055, 0.63)]
# the door's lower crease (02: 0.387 at y 0.77, 0.475 at -1.0); the facet below it faces down and out
LOW = [(2.05, 0.24), (1.60, 0.28), (0.95, 0.36), (0.77, 0.39), (-1.0, 0.475), (-1.40, 0.55), (-2.055, 0.66)]
# shoulder crease (02 / 08: rising to the rear); 03: the pods reach the full width below z 0.60
SHOULDER = [(2.05, 0.30), (1.75, 0.47), (1.45, 0.56), (1.19, 0.60), (0.90, 0.68), (0.5, 0.70), (0.0, 0.71),
            (-1.0, 0.74), (-1.6, 0.77), (-2.055, 0.79)]
# the side glass's lower edge (02: 0.755 at y 1.12 to the window's tip, 0.923 at -0.986), then the haunch
BELT = [(1.19, 0.75), (-0.986, 0.923), (-2.055, 0.80)]
DLO = [(-0.30, 1.095), (-0.986, 0.923)]       # the side window's top edge behind the roof (02)
DLO_END = -0.986
# roof rail / buttress top half width: canopy 0.50 (03), buttresses widening to the tail corners (01)
TOP_HW = [(1.19, 0.80), (0.90, 0.66), (0.50, 0.54), (0.0, 0.50), (-0.50, 0.52), (-1.00, 0.58), (-1.50, 0.68),
          (-1.85, 0.75), (-2.055, 0.78)]
# front clip (03 + 08): the hood a flat trapezoid from the lamp bar to its rear corners; the fender pods' top facets
# are inverted triangles (hood corner, A pillar base, bar end); the ridge V -> AB is the side silhouette (02)
COWL = 1.19                            # the A pillars' base (02: 1745 px)
V = (0.656, 2.05, 0.39)                # bar end / notch point (03: bar 817-1400 px, row 607)
HC = (0.49, 1.40, 0.705)               # hood rear corner: 08 near / far, z capped by 02's silhouette (R2Body.md)
AB = (0.82, 1.19, 0.75)                # A pillar base (03: 1481.7, 436.7)
RIDGE = [(2.05, 0.39), (2.0, 0.478), (1.831, 0.572), (1.663, 0.634), (1.495, 0.682), (1.40, 0.706), (1.326, 0.724),
         (1.19, 0.753)]
# centre line: hood, the glass between the pods, windshield, roof (TOP), rear glass and deck (01, Slide-2)
REAR0 = -0.45
REAR_C = [(-0.45, 1.082), (-0.80, 0.98), (-1.15, 0.89), (-1.40, 0.845), (-1.60, 0.84), (-2.055, 0.83)]
ZC = [(2.05, 0.39), (1.40, 0.705), (1.074, 0.79)] + [p for p in TOP if -0.45 < p[0] < 1.0] + REAR_C
# the buttresses' inner walls (paint) frame the V rear glass: 01 glass 0.40 half wide at the roof, 0.28 at its foot
FIN_IN = [(-0.45, 0.47), (-0.80, 0.40), (-1.40, 0.28), (-1.60, 0.45), (-2.00, 0.72), (-2.055, 0.74)]
GLASS_END = -1.40                      # the rear glass runs down to the wing's leading edge (01, 825)
WING = dict(seam=-1.40, thick=0.045, thick_tail=0.030, gap=0.006, trail_y=-2.075)

TYRES = dict(front=dict(y=1.272, r=0.307, w=0.255, disc=0.262, x=0.80),      # 03: contacts 750 px / bar 590 px
             rear=dict(y=-1.392, r=0.337, w=0.305, disc=0.265, x=0.755))
ARCH = dict(front=(1.272, 0.307, 0.350), rear=(-1.392, 0.337, 0.355))      # (y, z, radius): 02 arch tops 0.654 / 0.688
# rear face (01 at the plate's scale): lamp band under the wing's lip, plate, the black cavity with nozzles and fans
LAMP_Z = (0.757, 0.793)
PLATE = dict(z=0.58, w=0.3048, h=0.1524)
CAVITY = dict(hw=0.78, top=0.48, back=-2.0)
TAIL_BLACK = ((0.26, 0.48), (0.84, 0.63))   # the tail's black edge (|x|, z): flat under the plate, rising to the corners
# 03 silhouette above the pods (boosted 03, 461 px/m): pod face 0.94 up to z 0.65, pod corner (0.826, 0.75), then the
# A-pillar line to (0.477, 1.067); nothing of the cabin or the haunches shows outside it, so their sections stay inside
SIL03 = ((0.65, 0.75, 1.20), (0.94, 0.826, 0.331))
NOZZLE_X = (-0.354, -0.118, 0.118, 0.354)
NOZZLE = dict(z=0.40, r_exit=0.036, r_throat=0.018, length=0.075, y_exit=-2.075)
FAN = dict(z=0.29, r=0.055, y=-2.0)
STATIONS = [2.05, 2.02, 1.98, 1.94, 1.90, 1.85, 1.80, 1.72, 1.64, 1.56, 1.48, 1.40, 1.33, 1.26, 1.19, 1.12, 1.04,
            0.95, 0.85, 0.75, 0.60, 0.45, 0.30, 0.15, 0.0, -0.15, -0.30, -0.45, -0.58, -0.70, -0.82, -0.94, -0.986,
            -1.06, -1.15, -1.22, -1.31, -1.40, -1.40, -1.48, -1.56, -1.66, -1.78, -1.90, -1.98, -2.03, -2.055]
MATS = ("Paint", "Glass", "Trim", "Liner", "HeadLight", "TailLight", "Dark")


def interp(tab, x):
    t = np.asarray(tab, float)
    if t[0, 0] > t[-1, 0]:
        t = t[::-1]
    return float(np.interp(x, t[:, 0], t[:, 1]))


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def wing_thick(y):
    return WING["thick"] + (WING["thick_tail"] - WING["thick"]) * np.clip((WING["seam"] - y) / (WING["seam"] + 2.055), 0, 1)


def deck_z(y, lowered):
    z = interp(REAR_C, y)
    return z - wing_thick(y) - WING["gap"] if lowered else z


def section(y, lowered=False):
    """The left half section at station y: 12 (|x|, z) points, u0 floor centre .. u11 top centre."""
    hw = interp(HW, y)
    fl = interp(FLOOR, y)
    u = [(0.0, fl), (hw - 0.20, fl), (hw - 0.09, fl + 0.02), (hw - 0.07, interp(SILL, y)),
         (hw - 0.005, interp(LOW, y)), (hw, interp(SHOULDER, y))]
    if y > COWL - 1e-9:
        t = (V[1] - y) / (V[1] - AB[1])
        ridge = (V[0] + (AB[0] - V[0]) * t, interp(RIDGE, y))
        if y >= HC[1]:                                   # hood edge V -> HC
            s = (V[1] - y) / (V[1] - HC[1])
            edge = (V[0] + (HC[0] - V[0]) * s, V[2] + (HC[2] - V[2]) * s)
            zc = edge[1]
        else:                                            # the glass's edge HC -> AB, between the pods
            s = (HC[1] - y) / (HC[1] - AB[1])
            edge = (HC[0] + (AB[0] - HC[0]) * s, HC[2] + (AB[2] - HC[2]) * s)
            zc = interp(ZC, y)
        x5, z5 = u[5]
        # the pod's outer face stands near vertical up to z ~0.72 (03: half width 0.92 there), then the top facet
        u += [(x5 + 0.15 * (ridge[0] - x5), z5 + 0.75 * (ridge[1] - z5)), ridge, edge,
              (0.62 * edge[0], zc), (0.30 * edge[0], zc), (0.0, zc)]
        return u
    xe = interp(TOP_HW, y)
    if y > REAR0:
        ze = zc = interp(ZC, y)
    else:
        ze = interp(TOP, y)
    lim = lambda z: float(np.interp(z, *SIL03))
    u[5] = (min(hw, lim(u[5][1])), u[5][1])              # tumblehome: the shoulder crease stays at its 02 height
    zb = interp(BELT, y)
    belt = (max(min(hw - 0.12, lim(zb)), xe + 0.02), zb)
    rail = (xe, ze)
    if y >= -0.15:
        t7 = 0.5
    elif y >= -0.30:
        t7 = 0.5 + 0.5 * (-0.15 - y) / 0.15
    elif y > DLO_END:
        t7 = np.clip((interp(DLO, y) - belt[1]) / (ze - belt[1]), 0, 1)
    else:
        t7 = 0.35
    u += [belt, lerp(belt, rail, t7), rail]
    if y > REAR0:
        x9 = min(0.47 * xe / 0.52, xe - 0.03)
        u += [(x9, zc), (0.5 * x9, zc), (0.0, zc)]
    else:
        fi = interp(FIN_IN, y)
        zd = min(deck_z(y, lowered), ze)                 # the walls never fold over (y -0.45: 1.082 vs 1.080)
        u += [(fi, ze), (fi, zd), (0.0, zd)]
    return u


def face_mat(k, y):
    """Material of the strip between u_k and u_k+1 at mid station y."""
    if k <= 2:
        return "Trim"
    if k <= 5:
        return "Paint"
    if y > COWL:
        if k == 6:
            return "Paint"
        if k == 7:
            return "HeadLight" if y > 1.85 else "Paint"
        return "Paint" if y > HC[1] else "Glass"
    if y > REAR0:
        if k == 6 and y > 1.12:   # pod top to belt behind the cowl: paint, else a glass spike shows in 03 / 08
            return "Paint"
        return "Glass" if (k != 7 or y > -0.30) else "Paint"
    if k == 6:
        return "Glass" if y > DLO_END else "Paint"
    if k < 10:          # the buttresses incl. their inner walls stay paint (01: lit white beside the glass)
        return "Paint"
    if y > GLASS_END:   # the V rear glass, down to the wing's leading edge (01, 825)
        return "Glass"
    return "Paint" if y > WING["seam"] else "Trim"


def loft():
    """Body loft: vertices, quads (outward order not guaranteed), quad materials, nose / tail ring indices."""
    seam_seen = False
    rings, V_ = [], []
    for y in STATIONS:
        low = y < WING["seam"] - 1e-9 or (abs(y - WING["seam"]) < 1e-9 and seam_seen)
        seam_seen |= abs(y - WING["seam"]) < 1e-9
        s = section(y, low)
        ring = [(0.0, y, s[0][1])] + [(-ax, y, z) for ax, z in s[1:11]] + [(0.0, y, s[11][1])] + \
               [(ax, y, z) for ax, z in s[10:0:-1]]
        rings.append(list(range(len(V_), len(V_) + len(ring))))
        V_ += ring
    quads, qm = [], []
    n = len(rings[0])
    for j in range(len(rings) - 1):
        ym = 0.5 * (STATIONS[j] + STATIONS[j + 1])
        for p in range(n):
            q = (p + 1) % n
            quads.append((rings[j][p], rings[j][q], rings[j + 1][q], rings[j + 1][p]))
            qm.append(face_mat(p if p <= 10 else 21 - p, ym))
    return np.array(V_), quads, qm, rings[0], rings[-1]


def wing_loft():
    """The wing: a plate between the buttresses' inner walls, top = the deck, its trailing lip over the lamp band."""
    ys = [y for y in STATIONS if y <= WING["seam"]]
    ys = sorted(set(ys), reverse=True) + [WING["trail_y"]]
    V_, rings = [], []
    for y in ys:
        yy = max(y, -2.055)
        w = interp(FIN_IN, yy) - WING["gap"]
        zt = interp(REAR_C, yy)
        zb = zt - wing_thick(yy)
        rings.append(list(range(len(V_), len(V_) + 4)))
        V_ += [(-w, y, zt), (w, y, zt), (w, y, zb), (-w, y, zb)]
    quads = [(r0[p], r0[(p + 1) % 4], r1[(p + 1) % 4], r1[p]) for r0, r1 in zip(rings[:-1], rings[1:]) for p in range(4)]
    return np.array(V_), quads + [tuple(rings[0]), tuple(rings[-1][::-1])]


def box(x0, x1, y0, y1, z0, z1):
    return [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]


def cutters():
    """(name, convex point set, material): solids taken out of the body."""
    out = []
    for nm, (yw, zw, ra) in ARCH.items():
        a = np.linspace(0, 2 * np.pi, 64, endpoint=False)
        for sx in (-1, 1):
            out.append((f"arch_{nm}_{sx}", [(sx * x, yw + ra * np.cos(t), zw + ra * np.sin(t)) for x in (0.50, 1.3)
                                            for t in a], "Liner"))
    # under the hood's lamp bar: a recessed face sloping back and down, the black intake, the lip below (03, 08)
    out.append(("front_recess", [(sx * 0.70, y, z) for sx in (-1, 1) for y, z in
                                 ((2.30, 0.372), (2.052, 0.372), (1.975, 0.26), (1.975, 0.17), (2.30, 0.17))], "Trim"))
    out.append(("lamp_band", box(-0.85, 0.85, -2.30, -2.025, LAMP_Z[0], LAMP_Z[1]), "TailLight"))
    out.append(("plate_recess", box(-0.17, 0.17, -2.30, -2.040, 0.493, 0.667), "Trim"))
    out.append(("cavity", box(-CAVITY["hw"], CAVITY["hw"], -2.40, CAVITY["back"], -0.1, CAVITY["top"]), "Trim"))
    return out


# ---- wheels and small parts
def revolve(prof, seg=72, axis="x"):
    prof = np.asarray(prof, float)
    a = np.linspace(0, 2 * np.pi, seg, endpoint=False)
    v = np.concatenate([np.stack([np.full(seg, x), r * np.cos(a), r * np.sin(a)], 1) for x, r in prof])
    q = []
    for i in range(len(prof) - 1):
        for j in range(seg):
            k = (j + 1) % seg
            q.append((i * seg + j, i * seg + k, (i + 1) * seg + k, (i + 1) * seg + j))
    q = np.array(q)
    t = np.concatenate([q[:, [0, 1, 2]], q[:, [0, 2, 3]]])
    if axis == "y":                     # lateral along y: (x, y, z) <- (r cos, lateral, r sin)
        v = v[:, [1, 0, 2]]
        t = t[:, ::-1]
    return v, t


def tyre_profile(r, w, rim):
    side = r - rim
    pts = [(-w / 2 + 0.012, rim), (-w / 2, rim + 0.3 * side), (-w / 2 - 0.004, rim + 0.6 * side),
           (-w / 2 + 0.006, rim + 0.9 * side), (-w / 2 + 0.025, r - 0.003), (-w / 2 + 0.045, r)]
    return pts + [(-x, rr) for x, rr in pts[::-1]]


def prism(poly2, x0, x1):
    """A closed prism: polygon (u = y, v = z) between x0 and x1 (lateral)."""
    p = np.asarray(poly2, float)
    n = len(p)
    v = np.concatenate([np.c_[np.full(n, x0), p], np.c_[np.full(n, x1), p]])
    t = [(0, i, i + 1) for i in range(1, n - 1)] + [(n, n + i + 1, n + i) for i in range(1, n - 1)]
    for i in range(n):
        j = (i + 1) % n
        t += [(i, n + i, n + j), (i, n + j, j)]
    return v, np.array(t)


def merge(parts):
    vs, ts, o = [], [], 0
    for v, t in parts:
        vs.append(v)
        ts.append(t + o)
        o += len(v)
    return np.concatenate(vs), np.concatenate(ts)


def wheel_parts(seg=72):
    """{name: (vertices, triangles, material)} in place; computed for the left wheel, mirrored for the right.
    825 / x-sawyer / 02: a light flat disc, 6 dark blades from the dark hub out to the dark rim lip, swept a little."""
    out = {}
    for axle, tag in (("front", "F"), ("rear", "R")):
        ty = TYRES[axle]
        r, w, rd, xc = ty["r"], ty["w"], ty["disc"], ty["x"]
        rim = rd + 0.016
        tv, tt = revolve(tyre_profile(r, w, rim), seg)
        lip = revolve([(-w / 2 + 0.012, rim), (-w / 2 + 0.004, rim), (-w / 2 + 0.006, rd), (-w / 2 + 0.030, rd - 0.004)], seg)
        disc = revolve([(-w / 2 + 0.030, rd - 0.004), (-w / 2 + 0.026, 0.06), (-w / 2 + 0.012, 0.045), (-w / 2 + 0.010, 0.0005)], seg)
        hub = revolve([(-w / 2 + 0.010, 0.045), (-w / 2 - 0.004, 0.040), (-w / 2 - 0.010, 0.02), (-w / 2 - 0.011, 0.0005)], 24)
        blades = []
        for k in range(6):
            a0 = k * np.pi / 3 + np.pi / 2
            prof = [(0.04, -0.045), (rd - 0.002, -0.014), (rd - 0.002, 0.014), (0.04, 0.045)]
            p2 = []
            for rr, tt_ in prof:
                a = a0 + 0.45 * (rr - 0.04) / (rd - 0.04)          # swept: the tips trail
                p2.append([rr * np.cos(a) - tt_ * np.sin(a), rr * np.sin(a) + tt_ * np.cos(a)])
            blades.append(prism(p2, -w / 2 - 0.006, -w / 2 + 0.026))
        parts = {"Tyre": ((tv, tt), "Tyre"), "Rim": ((merge([lip, hub] + blades)), "Spoke"), "Disc": (disc, "Disc")}
        for lr, sx in (("L", -1), ("R", 1)):
            for nm, ((vv, tt_), mat) in parts.items():
                p = vv.copy()
                p[:, 0] = -xc + vv[:, 0] if sx < 0 else xc - vv[:, 0]      # lateral -w/2: the outer face
                p[:, 1] += ty["y"]
                p[:, 2] += ty["r"]
                tri = tt_ if sx < 0 else tt_[:, ::-1]
                out[f"{nm}_{tag}{lr}"] = (p, tri, mat)
    return out


def rear_parts():
    """Nozzles (bells, axis -y) out of the cavity's back wall, fans on it, and the plate in its recess."""
    out = {}
    nz = NOZZLE
    bell = [(0.0, nz["r_throat"] + 0.004), (0.0, nz["r_throat"]), (-0.03, nz["r_throat"] * 1.25),
            (-nz["length"] * 0.75, nz["r_exit"] * 0.85), (-nz["length"], nz["r_exit"]),
            (-nz["length"], nz["r_exit"] + 0.004), (-nz["length"] * 0.7, nz["r_exit"] * 0.92),
            (-0.02, nz["r_throat"] * 1.6), (0.0, nz["r_throat"] + 0.004)]
    bv, bt = revolve(bell, 48, axis="y")
    fan_v, fan_t = revolve([(0.0, FAN["r"]), (0.0, FAN["r"] - 0.006), (-0.004, FAN["r"] - 0.006), (-0.004, 0.0005)], 48, "y")
    for i, x in enumerate(NOZZLE_X):
        p = bv.copy()
        p[:, 0] += x
        p[:, 1] += nz["y_exit"] + nz["length"]
        p[:, 2] += nz["z"]
        out[f"Nozzle_{i + 1}"] = (p, bt, "Nozzle")
        fv = fan_v.copy()
        fv[:, 0] += x
        fv[:, 1] += FAN["y"]
        fv[:, 2] += FAN["z"]
        out[f"Fan_{i + 1}"] = (fv, fan_t, "Fan")
    pw, ph = PLATE["w"], PLATE["h"]
    pv, pt = prism([(-pw / 2, PLATE["z"] - ph / 2), (pw / 2, PLATE["z"] - ph / 2), (pw / 2, PLATE["z"] + ph / 2),
                    (-pw / 2, PLATE["z"] + ph / 2)], 0, 0.006)
    pv = pv[:, [1, 0, 2]]                      # prism lateral axis -> y
    pv[:, 1] = -2.040 - pv[:, 1]
    out["Plate"] = (pv, pt, "Plate")
    return out


# ---- lines (the car's left; door_right mirrored)
def surface_x(y, z):
    """The left side's x at (y, z): along the section from the sill up to the rail."""
    s = section(y)[2:9]
    for (x0, z0), (x1, z1) in zip(s[:-1], s[1:]):
        if z1 != z0 and min(z0, z1) <= z <= max(z0, z1):
            return -(x0 + (x1 - x0) * (z - z0) / (z1 - z0))
    return -s[0][0]


def lines():
    out = {}
    # the butterfly door (02): front cut behind the front arch, up the A pillar, along the rail, down the B pillar
    door = [[surface_x(y, z), y, z] for y, z in ((0.73, 0.24), (0.745, 0.45), (0.76, 0.66), (0.79, 0.74))]
    for y in (0.70, 0.40, 0.10, -0.20, -0.378):
        door.append([-(interp(TOP_HW, y) - 0.04), y, interp(ZC, y)])
    door += [[surface_x(y, z), y, z] for y, z in ((-0.378, 0.85), (-0.33, 0.55), (-0.28, 0.30), (-0.26, 0.24))]
    door.append(door[0])
    out["door_left"] = door
    out["door_right"] = [[-p[0], p[1], p[2]] for p in door]
    # the wing: outline of its top (seam, the left side, the trailing lip, the right side) and the hinge axis (seam)
    wv, _ = wing_loft()
    top = wv.reshape(-1, 4, 3)[:, :2]                    # per station: left / right top corners
    ring = [p.tolist() for p in top[:, 0]] + [p.tolist() for p in top[::-1, 1]] + [top[0, 0].tolist()]
    out["wing"] = [[round(c, 4) for c in p] for p in ring]
    ys = WING["seam"]
    out["wing_hinge"] = [[-0.20, ys, interp(REAR_C, ys)], [0.20, ys, interp(REAR_C, ys)]]
    # charge port: no Tesla picture shows it; the rear left corner as on the family's other cars (a guess, to be
    # decided with the other cars' plug side): a 12 x 9 cm door in the deck under the wing
    cy, cx = -1.86, -0.60
    cz = round(deck_z(cy, True), 4)
    out["charge_port"] = [[cx - 0.06, cy - 0.045, cz], [cx + 0.06, cy - 0.045, cz], [cx + 0.06, cy + 0.045, cz],
                          [cx - 0.06, cy + 0.045, cz], [cx - 0.06, cy - 0.045, cz]]
    out["charge_port_centre"] = [cx, cy, cz]
    out["head_light_bar"] = [[-0.64, 2.05, 0.381], [0.64, 2.05, 0.381]]
    out["tail_light_bar"] = [[-0.85, -2.025, 0.775], [0.85, -2.025, 0.775]]
    # thrusters (exit centres; dir per group): lift 4 corners down, side 2 at the front, rear 4 the bells
    out["nozzles"] = dict(
        lift=[[-0.62, 1.78, 0.14], [0.62, 1.78, 0.14], [-0.62, -1.80, 0.14], [0.62, -1.80, 0.14]],
        side=[[-0.92, 1.62, 0.30], [0.92, 1.62, 0.30]],
        rear=[[x, NOZZLE["y_exit"], NOZZLE["z"]] for x in NOZZLE_X],
        r=NOZZLE["r_exit"],
        dir=dict(lift=[0, 0, -1], side=[[-1, 0, 0], [1, 0, 0]], rear=[0, -1, 0]))
    out["fans"] = [[x, FAN["y"], FAN["z"]] for x in NOZZLE_X]
    # single seat (driver, left) H point; the passenger side holds the 400 L COPV (centre, axis, radius, length)
    out["seat"] = [-0.36, -0.22, 0.27]
    out["copv"] = dict(centre=[0.36, -0.25, 0.42], axis=[0, 1, 0], r=0.30, length=1.42)
    return out


def mesh_check(v, t):
    """Open edges, non-manifold edges, degenerate faces (a closed body: all zero)."""
    e = np.sort(np.concatenate([t[:, [0, 1]], t[:, [1, 2]], t[:, [2, 0]]]), 1)
    _, cnt = np.unique(e, axis=0, return_counts=True)
    area = np.linalg.norm(np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]]), axis=1) / 2
    return dict(open_edges=int((cnt == 1).sum()), nonmanifold_edges=int((cnt > 2).sum()),
                degenerate=int((area < 1e-10).sum()))


# ---- Blender
COLORS = dict(Paint=((0.80, 0.80, 0.80), 0.35, 0.30), Glass=((0.025, 0.02, 0.017), 0.0, 0.12),
              Trim=((0.025, 0.025, 0.028), 0.0, 0.55), Liner=((0.015, 0.015, 0.016), 0.0, 0.85),
              HeadLight=((0.70, 0.85, 1.00), 0.0, 0.15), TailLight=((0.55, 0.02, 0.03), 0.0, 0.25),
              Dark=((0.10, 0.10, 0.11), 0.2, 0.40),
              Tyre=((0.02, 0.02, 0.022), 0.0, 0.8), Disc=((0.78, 0.79, 0.80), 0.5, 0.30),
              Spoke=((0.03, 0.03, 0.035), 0.3, 0.35), Nozzle=((0.55, 0.50, 0.45), 1.0, 0.3),
              Fan=((0.05, 0.05, 0.05), 0.5, 0.5), Plate=((0.75, 0.76, 0.78), 0.3, 0.4))


def main():
    import bmesh
    import bpy
    from mathutils.bvhtree import BVHTree

    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = (args + [OUT_DIR])[0]
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    mats = {}
    for nm, (rgb, metal, rough) in COLORS.items():
        m = bpy.data.materials.new(nm)
        m.use_nodes = True
        bs = m.node_tree.nodes["Principled BSDF"]
        bs.inputs["Base Color"].default_value = (*rgb, 1)
        bs.inputs["Metallic"].default_value = metal
        bs.inputs["Roughness"].default_value = rough
        m.diffuse_color = (*rgb, 1)
        if nm in ("HeadLight", "TailLight"):     # lit lamps (03 / 01): the strips read against the paint
            bs.inputs["Emission Color"].default_value = (*rgb, 1)
            bs.inputs["Emission Strength"].default_value = 3.0
        mats[nm] = m

    def link(name, bm, matnames, coll=None):
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for m in matnames:
            me.materials.append(mats[m])
        ob = bpy.data.objects.new(name, me)
        (coll or scn.collection).objects.link(ob)
        return ob

    def closed(bm):
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # body loft, caps split at the sill top (black below)
    V_, quads, qm, nose, tail = loft()
    bm = bmesh.new()
    bv = [bm.verts.new(p) for p in V_]
    for q, m in zip(quads, qm):
        if len({tuple(V_[i]) for i in q}) >= 3:
            bm.faces.new([bv[i] for i in q]).material_index = MATS.index(m)
    for ring in (nose, tail):
        bm.faces.new([bv[i] for i in ring]).material_index = MATS.index("Paint")
    closed(bm)
    # cap materials: the nose all dark below the lamp bar (03, 08); the tail's black lower half rises from under the
    # plate to the corners (825), so its edge is a polyline (planes) cut into the cap, not one horizontal line
    zb_nose = lambda ax: V[2] - 0.018
    zb_tail = lambda ax: TAIL_BLACK[0][1] + max(ax - TAIL_BLACK[0][0], 0) * (TAIL_BLACK[1][1] - TAIL_BLACK[0][1]) / \
        (TAIL_BLACK[1][0] - TAIL_BLACK[0][0])
    (x0, z0), (x1, z1) = TAIL_BLACK
    nz = np.array([-(z1 - z0), 0.0, x1 - x0]) / math.hypot(z1 - z0, x1 - x0)
    for yc, zb, planes in ((STATIONS[0], zb_nose, [((0, 0, V[2] - 0.018), (0, 0, 1))]),
                           (STATIONS[-1], zb_tail, [((0, 0, z0), (0, 0, 1)), ((x0, 0, z0), tuple(nz)),
                                                    ((-x0, 0, z0), (-nz[0], 0, nz[2]))])):
        on_cap = lambda f: abs(f.normal.y) > 0.999 and abs(f.calc_center_median().y - yc) < 1e-6
        for co, no in planes:
            cap = [f for f in bm.faces if on_cap(f)]
            geom = cap + list({e for f in cap for e in f.edges}) + list({v for f in cap for v in f.verts})
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no)
        for f in bm.faces:
            c = f.calc_center_median()
            if on_cap(f) and c.z < zb(abs(c.x)):
                f.material_index = MATS.index("Trim")
    bmesh.ops.triangulate(bm, faces=bm.faces[:])    # planar input: the boolean's n-gons stay flat (no crossings)
    body = link("Body", bm, MATS)

    # cutters (exact booleans; their faces become the recesses, materials transferred)
    cc = bpy.data.collections.new("cutters")
    scn.collection.children.link(cc)
    for nm, pts, mat in cutters():
        bm = bmesh.new()
        for p in pts:
            bm.verts.new(p)
        bmesh.ops.convex_hull(bm, input=bm.verts)
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), verts=bm.verts, edges=bm.edges)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        if nm == "front_recess":            # the face sloping back under the bar: dark paint, not black
            for f in bm.faces:
                f.material_index = 1 if (f.normal.y < -0.5 and f.normal.z < -0.5) else 0
            link(nm, bm, [mat, "Dark"], cc)
        else:
            link(nm, bm, [mat], cc)
    md = body.modifiers.new("cut", "BOOLEAN")
    md.operation, md.solver, md.operand_type = "DIFFERENCE", "EXACT", "COLLECTION"
    md.collection = cc
    md.material_mode = "TRANSFER"
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(body.evaluated_get(dg))
    body.modifiers.clear()
    old = body.data
    body.data = me
    bpy.data.meshes.remove(old)
    for o in list(cc.objects):
        bpy.data.objects.remove(o)
    bpy.data.collections.remove(cc)
    me.name = "Body"
    idx = {m.name: i for i, m in enumerate(me.materials)}
    for p in me.polygons:                    # the lamp bar: the nose face left above the recess (03: row 605-610)
        c = p.center
        if p.normal.y > 0.9 and c.y > 2.0 and 0.370 < c.z < 0.395 and abs(c.x) < 0.66:
            p.material_index = idx["HeadLight"]

    # wing
    wv, wq = wing_loft()
    bm = bmesh.new()
    bw = [bm.verts.new(p) for p in wv]
    for q in wq:
        bm.faces.new([bw[i] for i in q])
    closed(bm)
    wing = link("Wing", bm, ["Paint"])

    report = dict(objects={}, checks={})
    for ob in (body, wing):
        m = ob.data
        m.polygons.foreach_set("use_smooth", np.ones(len(m.polygons), bool))
        m.set_sharp_from_angle(angle=math.radians(25))
        m.calc_loop_triangles()
        v = np.array([x.co[:] for x in m.vertices])
        t = np.array([lt.vertices[:] for lt in m.loop_triangles])
        report["checks"][ob.name] = mesh_check(v, t)
        tree = BVHTree.FromPolygons(v.tolist(), t.tolist(), all_triangles=True)
        pairs = np.array(tree.overlap(tree), np.int64).reshape(-1, 2)
        pairs = pairs[pairs[:, 0] < pairs[:, 1]]
        shared = (t[pairs[:, 0], :, None] == t[pairs[:, 1], None, :]).any((1, 2))
        report["checks"][ob.name]["self_intersections"] = int((~shared).sum())

    def make(name, vv, tt, matname):
        used, inv = np.unique(tt, return_inverse=True)
        tt = inv.reshape(-1, 3)
        vv = vv[used]
        m = bpy.data.meshes.new(name)
        m.vertices.add(len(vv))
        m.vertices.foreach_set("co", vv.astype(np.float32).ravel())
        m.loops.add(tt.size)
        m.loops.foreach_set("vertex_index", tt.astype(np.int32).ravel())
        m.polygons.add(len(tt))
        m.polygons.foreach_set("loop_start", (np.arange(len(tt)) * 3).astype(np.int32))
        m.polygons.foreach_set("loop_total", np.full(len(tt), 3, np.int32))
        m.update()
        m.materials.append(mats[matname])
        m.polygons.foreach_set("use_smooth", np.ones(len(tt), bool))
        m.set_sharp_from_angle(angle=math.radians(40))
        ob = bpy.data.objects.new(name, m)
        scn.collection.objects.link(ob)

    for grp in (wheel_parts(), rear_parts()):
        for nm, (vv, tt, mn) in grp.items():
            make(nm, vv, tt, mn)
    for ob in scn.objects:
        report["objects"][ob.name] = len(ob.data.polygons)
    bv_ = np.array([x.co[:] for x in body.data.vertices])
    report["body_bbox"] = [bv_.min(0).round(4).tolist(), bv_.max(0).round(4).tolist()]
    report["sizes"] = dict(L=L, W=WIDTH, H=HEIGHT, wheelbase=round(TYRES["front"]["y"] - TYRES["rear"]["y"], 4),
                           tyres={k: dict(d=round(2 * v_["r"], 3), w=v_["w"], track=round(2 * v_["x"], 3))
                                  for k, v_ in TYRES.items()})
    json.dump(report, open(os.path.join(out, "prep_report.json"), "w"), indent=1)
    json.dump(dict(frame="metres, +Y front, +Z up, -X the car's left, ground 0 (prep_roadster2.py)", **lines()),
              open(os.path.join(out, "roadster2_lines.json"), "w"), indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "roadster2_src.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "roadster2_src.glb"), export_format="GLB")
    print("PREP", report["checks"], "bbox", report["body_bbox"])


if __name__ == "__main__":
    main()
