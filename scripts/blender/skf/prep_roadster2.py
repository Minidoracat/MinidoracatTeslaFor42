"""Roadster 2 (Rocket) body shell from scratch (no model file is read): drawn on Tesla's own pictures only
(temp/plan-next-1114/assets/official-roadster2/: 02 side, 03 front, 01 / 00 rear, 08 front 3/4, extra Slide-2 rear
deck, x-sawyer rear 3/4 with the wing up; the 2026-11-19 unveil stream 05:40 / 05:44 plan views).
Shape: one signed distance field (SDF) sampled on a grid and meshed by surface nets (as prep_cybercab.py), the
vertices pulled onto the zero level, normals from the field's gradient:
  - SIDE: 02's side silhouette (read as orthographic at the near wheels' plane; 1,949 px = L) as a 2-D distance in (y, z);
  - TOP: the top surface z = ztop(x, y): the hood dipped between the two fender crowns (03), the glass canopy nearly
    flat across (03), the rear glass falling into the V deck between the two flying buttresses (01, Slide-2, 05:40);
  - the section: |x| <= hw(y, z): the plan HW below the shoulder (tucked under), the greenhouse / buttresses leaning
    in above it to their top edge's half width;
  - smooth max of the three (rounded edges), the wheel houses carved out.
Every face gets a material from region rules (paint, glass, black trim, wheel house liner, head light, tail light).
The wing (the rear deck behind the seam, with the tail light bar on its trailing face) is its own object, cut out of
the body. Small parts: 4 bell nozzles and 4 fans in the rear face, 6 spoke wheels (front / rear tyres differ).
Sizes (round 1, R2Body): L 4.10 from the plate (US 12 x 6 in: rear face 1.74 m) and 02's ratios; see
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
CELL = 0.011
GRID = dict(half=1.0, y=(-2.12, 2.12), z=(0.0, 1.16))

# ---- tables (02 side read at 475.4 px/m, ground through the two tyre bottoms; 03 front; 01 rear at the plate's scale)
# side silhouette top (y, z): nose tip, fender crown, cowl, windshield, roof, buttress tops, tail top
TOP = [(2.05, 0.44), (2.0, 0.478), (1.831, 0.572), (1.663, 0.634), (1.495, 0.682), (1.326, 0.724), (1.19, 0.753),
       (1.074, 0.79), (0.906, 0.853), (0.737, 0.916), (0.569, 0.968), (0.401, 1.02), (0.232, 1.061), (0.064, 1.09),
       (-0.083, 1.10), (-0.293, 1.095), (-0.525, 1.073), (-0.777, 1.052), (-0.946, 1.032), (-1.24, 0.983),
       (-1.45, 0.944), (-1.703, 0.891), (-1.955, 0.844), (-2.05, 0.829)]
# the rest of the side outline, tail top down the rear face, under the car forward, up the nose
SIDE_REST = [(-2.055, 0.70), (-2.05, 0.59), (-2.03, 0.30), (-1.96, 0.16), (-1.80, 0.13), (-1.03, 0.13),
             (0.95, 0.13), (1.58, 0.10), (2.0, 0.12), (2.04, 0.16), (2.055, 0.30), (2.058, 0.40)]
# plan half width below the shoulder (y, hw): fender pods 0.94 (03: 860 px at 457 px/m), the rear face 0.87 (01);
# nose and tail corners rounded in plan (08 nose corner, 40 / 01 tail corners)
HW = [(2.058, 0.74), (2.02, 0.82), (1.97, 0.88), (1.75, 0.93), (1.27, 0.94), (0.75, 0.93), (0.0, 0.905),
      (-0.75, 0.92), (-1.39, 0.94), (-1.80, 0.925), (-1.93, 0.91), (-2.00, 0.885), (-2.04, 0.85), (-2.055, 0.80)]
# shoulder height (y, z): where the side stops being vertical and leans in (fender crown, belt, rear haunch);
# 03 reaches the full width only below z 0.72 and is 0.77 wide at z 0.79
SHOULDER = [(2.06, 0.42), (1.80, 0.55), (1.50, 0.64), (1.19, 0.70), (0.65, 0.71), (0.0, 0.72), (-0.52, 0.72),
            (-1.20, 0.73), (-2.06, 0.74)]
# the side glass's lower edge (02)
BELT = [(1.19, 0.745), (0.65, 0.765), (0.0, 0.785), (-0.52, 0.805), (-1.20, 0.815)]
# half width of the top edge (roof rail / buttress top) (y, hw): canopy 0.50 (03 roof 420 px), buttresses 0.58 at the
# roof's end widening to the tail corners (01)
TOP_HW = [(1.19, 0.80), (0.90, 0.66), (0.50, 0.54), (0.0, 0.50), (-0.50, 0.52), (-1.00, 0.58), (-1.50, 0.68),
          (-1.85, 0.78), (-2.06, 0.86)]
COWL = 1.19                    # the windshield's base (02: 1745 px)
HOOD_DIP = [(2.06, 0.05), (1.19, 0.055)]                       # hood centre under the fender crowns (03)
HOOD_HW = [(2.06, 0.64), (1.19, 0.47)]                         # hood / fender crease (03: 815 -> 893 px)
# rear: the glass falls from the roof (y -0.45) into the deck's apex (y -1.15); the deck then flat to the tail
REAR_C = [(-0.45, 1.082), (-0.80, 0.975), (-1.15, 0.875), (-1.60, 0.858), (-2.06, 0.835)]
FIN_IN = [(-0.45, 0.47), (-0.80, 0.33), (-1.15, 0.20), (-1.60, 0.50), (-2.00, 0.84), (-2.06, 0.86)]
GLASS_END = -1.15

TYRES = dict(front=dict(y=1.272, r=0.307, w=0.255, disc=0.262, x=0.80),      # 03: contacts 750 px / bar 590 px
             rear=dict(y=-1.392, r=0.337, w=0.305, disc=0.265, x=0.755))
ARCH = dict(front=(1.272, 0.307, 0.350), rear=(-1.392, 0.337, 0.355))      # (y, z, radius): 02 arch tops 0.654 / 0.688
# rear face (01 at the plate's scale, camera ~19 deg above): lamp bar on the wing's trailing face, plate, nozzles, fans
LAMP_Z = (0.772, 0.792)
PLATE = dict(z=0.58, w=0.3048, h=0.1524)
NOZZLE_X = (-0.354, -0.118, 0.118, 0.354)
NOZZLE = dict(z=0.40, r_exit=0.036, r_throat=0.018, length=0.075, y_exit=-2.075)
FAN = dict(z=0.29, r=0.055, y=-2.035)
WING = dict(seam_c=-1.20, seam_s=-1.78, thick=0.045, trail=0.10)


def interp(tab, x):
    t = np.asarray(tab, float)
    if t[0, 0] > t[-1, 0]:
        t = t[::-1]
    return np.interp(x, t[:, 0], t[:, 1])


def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def smax(a, b, k):
    h = np.clip(0.5 - 0.5 * (b - a) / k, 0.0, 1.0)
    return a * h + b * (1 - h) + k * h * (1 - h)


def poly_sdf(poly, py, pz):
    """Signed distance (negative inside) of points (py, pz) to a closed polygon [(y, z), ...]."""
    q, inv = np.unique(np.stack([py, pz], 1), axis=0, return_inverse=True)     # grid slices repeat (y, z) along x
    P = np.asarray(poly, float)
    A, B = P, np.roll(P, -1, 0)
    d2 = np.full(len(q), np.inf)
    inside = np.zeros(len(q), bool)
    for a, b in zip(A, B):
        e = b - a
        w = q - a
        t = np.clip((w @ e) / (e @ e), 0, 1)
        d2 = np.minimum(d2, ((w - t[:, None] * e) ** 2).sum(1))
        c = ((a[1] > q[:, 1]) != (b[1] > q[:, 1])) & (q[:, 0] < (b[0] - a[0]) * (q[:, 1] - a[1]) / (b[1] - a[1] + 1e-30) + a[0])
        inside ^= c
    return (np.where(inside, -1, 1) * np.sqrt(d2))[inv.ravel()]


SIDE = [(y, z + 0.04) for y, z in TOP] + SIDE_REST      # the top line above TOP: ztop draws the real top


def ztop(ax, y):
    """Top surface height at (|x|, y)."""
    top = interp(TOP, y)
    # front: hood dipped between the fender crowns
    dip = interp(HOOD_DIP, y)
    hx = interp(HOOD_HW, y)
    front = top - dip * (1 - ss(hx - 0.01, hx + 0.03, ax))        # a crisp hood / pod crease (08)
    # canopy: nearly flat across (03: full roof width within 1 cm of its top)
    thw = interp(TOP_HW, y)
    cab = top - 0.015 * (ax / np.maximum(thw, 0.3)) ** 2
    # rear: glass / deck in the middle, buttresses outside
    zc = interp(REAR_C, y)
    xi = interp(FIN_IN, y)
    fin = top - 0.02 * (ax / np.maximum(thw, 0.3)) ** 2
    rear = zc + (fin - zc) * ss(xi - 0.02, xi + 0.10, ax)
    w_front = ss(COWL - 0.03, COWL + 0.03, y)
    w_rear = ss(-0.40, -0.50, y)
    z = cab
    z = np.where(y > COWL - 0.03, front * w_front + cab * (1 - w_front), z)
    z = np.where(y < -0.40, rear * w_rear + cab * (1 - w_rear), z)
    return z


def hw(y, z):
    """Half width at (y, z): the plan below the shoulder (tucked under), leaning in to the top edge above it."""
    b = interp(HW, y) - 0.045 * ss(0.30, 0.13, z)
    zs = interp(SHOULDER, y)
    zt = np.maximum(interp(TOP, y), zs + 0.02)
    t = np.clip((z - zs) / (zt - zs), 0, 1.2)
    # in front of the cowl the fender pods stand straight up to their crown; behind it the side rolls in fast just
    # above the shoulder, then runs straight to the rail (03: 0.92 at z 0.72, 0.77 at 0.79, 0.48 at the roof)
    lean = np.where(y > COWL, 0.25, 1.0)
    t = np.where(y > COWL, t, t ** 0.6)
    return np.where(z < zs, b, b + (interp(TOP_HW, y) - b) * t * lean - 0.04 * t * (1 - lean))


def wing_mask_y(ax):
    """The wing's leading edge (the seam, Slide-2: from the glass corner diagonally back to the side)."""
    return WING["seam_c"] + (WING["seam_s"] - WING["seam_c"]) * np.clip((ax - 0.20) / 0.66, 0, 1)


class Field:
    k = 0.008

    def raw(self, P):
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        ax = np.abs(x)
        d_side = poly_sdf(SIDE, y, z)
        d_top = z - ztop(ax, y)
        d_w = ax - hw(y, z)
        f = smax(smax(d_side, d_top, self.k), d_w, self.k)
        for nm, (yw, zw, ra) in ARCH.items():
            r = np.sqrt((y - yw) ** 2 + (z - zw) ** 2)
            hole = np.maximum(r - ra, 0.42 - ax)
            f = np.maximum(f, -hole)
        return f

    def wing(self, P):
        """The wing's volume (negative inside): the top layer behind the seam."""
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        ax = np.abs(x)
        zt = ztop(ax, y)
        th = WING["thick"] + (WING["trail"] - WING["thick"]) * ss(-1.85, -2.05, y)
        # the underside follows the lowest top within 6 cm across, so the steps beside the rear glass stay thick
        zb = np.minimum.reduce([ztop(np.abs(ax + o), y) for o in (-0.06, -0.03, 0.0, 0.03, 0.06)]) - th
        d = np.maximum(z - zt, zb - z)
        d = np.maximum(d, y - wing_mask_y(ax))
        d = np.maximum(d, poly_sdf(SIDE, y, z))
        d = np.maximum(d, ax - hw(y, z))
        return d

    def __call__(self, P):
        # the body ends one cell short of the wing all round (a gap the surface nets can resolve)
        return np.maximum(self.raw(P), CELL - self.wing(P))


def surface_nets(fn, h, bounds):
    """Quads of the zero level of fn on a grid of cell h (prep_cybercab.surface_nets)."""
    ax = [np.arange(b0, b1 + h * 0.5, h) for b0, b1 in bounds]
    nx, ny, nz = (len(a) for a in ax)
    val = np.empty((nx, ny, nz), np.float32)
    X, Z = np.meshgrid(ax[0], ax[2], indexing="ij")
    for j in range(ny):
        P = np.stack([X.ravel(), np.full(X.size, ax[1][j]), Z.ravel()], 1)
        val[:, j, :] = fn(P).reshape(nx, nz)
    inside = val < 0
    c = np.zeros((nx - 1, ny - 1, nz - 1), np.uint8)
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                c += inside[dx:nx - 1 + dx, dy:ny - 1 + dy, dz:nz - 1 + dz]
    act = (c > 0) & (c < 8)
    idx = -np.ones(act.shape, np.int64)
    ci = np.argwhere(act)
    idx[act] = np.arange(len(ci))
    acc = np.zeros((len(ci), 3))
    cnt = np.zeros(len(ci))
    corners = [(i, j, k) for i in (0, 1) for j in (0, 1) for k in (0, 1)]
    edges = [(a, b) for a in range(8) for b in range(a + 1, 8)
             if sum(abs(corners[a][q] - corners[b][q]) for q in range(3)) == 1]
    for a, b in edges:
        ca, cb = np.array(corners[a]), np.array(corners[b])
        va = val[ci[:, 0] + ca[0], ci[:, 1] + ca[1], ci[:, 2] + ca[2]]
        vb = val[ci[:, 0] + cb[0], ci[:, 1] + cb[1], ci[:, 2] + cb[2]]
        m = (va < 0) != (vb < 0)
        t = va[m] / (va[m] - vb[m])
        acc[m] += ca[None] + t[:, None] * (cb - ca)[None]
        cnt[m] += 1
    loc = acc / cnt[:, None]
    verts = np.stack([ax[q][0] + (ci[:, q] + loc[:, q]) * h for q in range(3)], 1)
    quads = []
    for axis in range(3):
        o = [q for q in range(3) if q != axis]
        s0, s1 = [slice(None)] * 3, [slice(None)] * 3
        s0[axis], s1[axis] = slice(0, -1), slice(1, None)
        e = inside[tuple(s0)] != inside[tuple(s1)]
        for q in o:
            ss_ = [slice(None)] * 3
            ss_[q] = 0
            e[tuple(ss_)] = False
            ss_[q] = -1
            e[tuple(ss_)] = False
        ei = np.argwhere(e)
        low_in = inside[tuple(ei.T)]
        cells = []
        for d0, d1 in ((0, 0), (1, 0), (1, 1), (0, 1)):
            cc = ei.copy()
            cc[:, o[0]] -= d0
            cc[:, o[1]] -= d1
            cells.append(idx[tuple(cc.T)])
        q4 = np.stack(cells, 1)
        rh = (o[0], o[1], axis) in ((0, 1, 2), (1, 2, 0), (2, 0, 1))
        rev = low_in != rh
        q4[rev] = q4[rev][:, ::-1]
        quads.append(q4)
    return verts, np.concatenate(quads)


def gradient(fn, v, eps=2e-4):
    g = np.stack([(fn(v + e) - fn(v - e)) / (2 * eps) for e in np.eye(3) * eps], 1)
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)


def project(fn, v, steps=3, eps=2e-4, cap=0.5 * CELL):
    p = v
    for _ in range(steps):
        d = fn(p)
        g = np.stack([(fn(p + e) - fn(p - e)) / (2 * eps) for e in np.eye(3) * eps], 1)
        p = p - (d / np.maximum((g ** 2).sum(1), 1e-12))[:, None] * g
    return np.where((np.abs(p - v).max(1) < cap)[:, None], p, v)


def mesh_of(fn, bounds, h=CELL):
    """Triangles of fn's zero level (each quad split along its shorter diagonal), x symmetric grid."""
    n = int(math.ceil(bounds[0] / h))
    v, q = surface_nets(fn, h, ((-(n - 0.5) * h, (n - 0.5) * h), bounds[1], bounds[2]))
    v = project(fn, v, cap=0.5 * h)
    d02 = np.linalg.norm(v[q[:, 0]] - v[q[:, 2]], axis=1)
    d13 = np.linalg.norm(v[q[:, 1]] - v[q[:, 3]], axis=1)
    t = np.where((d13 < d02)[:, None, None],
                 np.stack([q[:, [0, 1, 3]], q[:, [1, 2, 3]]], 1), np.stack([q[:, [0, 1, 2]], q[:, [0, 2, 3]]], 1))
    return v, t.reshape(-1, 3)


# ---- regions
MATS = ("Paint", "Glass", "Trim", "Liner", "HeadLight", "TailLight")


def classify(v, t, fn, wing=False):
    """Material per face from its centre and normal."""
    c = v[t].mean(1)
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    ax = np.abs(x)
    n = gradient(fn, c)
    mat = np.zeros(len(t), np.int8)
    zt = ztop(ax, y)
    on_top = (zt - z < 0.03) & (n[:, 2] > 0.25)
    # glass: canopy top inside the rails (windshield, roof, rear glass), side windows between belt and rail
    thw = interp(TOP_HW, y)
    canopy = on_top & (y < COWL - 0.01) & (y > GLASS_END) & (ax < np.where(y < -0.45, interp(FIN_IN, y) - 0.015,
                                                                              thw - 0.05))
    belt = interp(BELT, y)
    zs = belt - 0.025
    side_win = ((z > belt) & (z < interp(TOP, y) - 0.05) & (ax > 0.3) & (n[:, 2] < 0.85) & (y < 1.12)
                & (y > interp([(0.75, -0.95), (0.95, -0.80), (1.05, -0.70)], z)) & ~on_top)
    a_pillar = (np.abs(y - (COWL - 0.03 - (z - zs) * 0.75)) < 0.018) & (y > 0.5)
    b_pillar = (np.abs(y - (-0.378)) < 0.010) & side_win
    mat[(canopy | side_win) & ~a_pillar & ~b_pillar] = 1
    # trim: sills (02's paint / black line), splitter, diffuser and the front grille under the lamp bar
    sill = z < interp([(2.1, 0.20), (0.95, 0.275), (0.0, 0.30), (-1.03, 0.37), (-1.9, 0.34), (-2.1, 0.30)], y)
    rear_low = (y < -1.85) & (z < 0.50)
    grille = (y > 1.90) & (z < 0.375) & (z > 0.16) & (ax < 0.66) & (n[:, 1] > 0.4)
    mat[(sill | rear_low | grille) & (mat == 0)] = 2
    # liner: inside the wheel houses
    for nm, (yw, zw, ra) in ARCH.items():
        r = np.sqrt((y - yw) ** 2 + (z - zw) ** 2)
        mat[(r < ra + 0.004) & (ax < interp(HW, y) - 0.012) & (ax > 0.40)] = 3
    # head lights: the full width bar on the nose (03: y 610 px) and the lamps in the pods' V notches
    bar = (y > 1.95) & (np.abs(z - 0.385) < 0.009) & (ax < 0.64) & (n[:, 1] > 0.3)
    pod = (y > 1.88) & (np.abs(z - 0.52) < 0.028) & (np.abs(ax - 0.66) < 0.06) & (n[:, 1] > 0.2)
    mat[bar | pod] = 4
    if wing:
        tl = (y < -1.98) & (z > LAMP_Z[0]) & (z < LAMP_Z[1]) & (n[:, 1] < -0.3)
        mat[tl] = 5
    return mat


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
    """{name: (vertices, triangles, material)} in place; computed for the left wheel, mirrored for the right."""
    out = {}
    for axle, tag in (("front", "F"), ("rear", "R")):
        ty = TYRES[axle]
        r, w, rd, xc = ty["r"], ty["w"], ty["disc"], ty["x"]
        rim = rd + 0.016
        tv, tt = revolve(tyre_profile(r, w, rim), seg)
        # rim lip, the light disc a little in, the hub
        lip = revolve([(-w / 2 + 0.012, rim), (-w / 2 + 0.004, rim), (-w / 2 + 0.006, rd), (-w / 2 + 0.030, rd - 0.004)], seg)
        disc = revolve([(-w / 2 + 0.030, rd - 0.004), (-w / 2 + 0.026, 0.06), (-w / 2 + 0.012, 0.045), (-w / 2 + 0.010, 0.0005)], seg)
        hub = revolve([(-w / 2 + 0.010, 0.045), (-w / 2 - 0.004, 0.040), (-w / 2 - 0.010, 0.02), (-w / 2 - 0.011, 0.0005)], 24)
        spokes = []
        for k in range(6):
            a = k * np.pi / 3 + np.pi / 2
            ca, sa = np.cos(a), np.sin(a)
            # a spoke: wide at the hub, narrowing out to the lip (02: black, dished), triangle-ish in side view
            prof = [(0.04, -0.030), (rd - 0.002, -0.012), (rd - 0.002, 0.012), (0.04, 0.030)]
            p2 = np.array([[rr * ca - tt_ * sa, rr * sa + tt_ * ca] for rr, tt_ in prof])
            sv, st = prism(p2, -w / 2 - 0.004, -w / 2 + 0.026)
            spokes.append((sv, st))
        parts = {"Tyre": ((tv, tt), "Tyre"), "Rim": ((merge([lip, hub] + spokes)), "Spoke"), "Disc": (disc, "Disc")}
        mid = xc
        for lr, sx in (("L", -1), ("R", 1)):
            for nm, ((vv, tt_), mat) in parts.items():
                p = vv.copy()
                p[:, 0] = -mid + vv[:, 0] if sx < 0 else mid - vv[:, 0]      # lateral -w/2: the outer face
                p[:, 1] += ty["y"]
                p[:, 2] += ty["r"]
                tri = tt_ if sx < 0 else tt_[:, ::-1]
                out[f"{nm}_{tag}{lr}"] = (p, tri, mat)
    return out


def rear_parts():
    """Nozzles (bells, axis -y), fans (discs with blades) and the plate."""
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
    pv[:, 1] = -2.045 - pv[:, 1]
    out["Plate"] = (pv, pt, "Plate")
    return out


# ---- lines (the car's left; door_right mirrored)
def surface_x(fn, y, z, x0=-1.1):
    """The body's left surface at (y, z): march from outside in."""
    xs = np.linspace(x0, 0, 800)
    P = np.stack([xs, np.full_like(xs, y), np.full_like(xs, z)], 1)
    d = fn(P)
    i = np.argmax(d < 0)
    if d[i] >= 0:
        return None
    a, b = xs[i - 1], xs[i]
    return float(a + (b - a) * d[i - 1] / (d[i - 1] - d[i]))


def surface_z(fn, x, y, z0=1.3):
    zs = np.linspace(z0, 0, 1300)
    P = np.stack([np.full_like(zs, x), np.full_like(zs, y), zs], 1)
    d = fn(P)
    i = np.argmax(d < 0)
    if d[i] >= 0:
        return None
    return float(zs[i - 1] + (zs[i] - zs[i - 1]) * d[i - 1] / (d[i - 1] - d[i]))


def lines(fn):
    out = {}
    # the butterfly door (02): front cut behind the front arch, up the A pillar, along the rail, down the B pillar
    side_pts = [(0.73, 0.20), (0.745, 0.45), (0.76, 0.66), (0.79, 0.74)]
    rail = [(0.70, 0.93), (0.40, 1.02), (0.10, 1.07), (-0.20, 1.08), (-0.378, 1.07)]
    back = [(-0.378, 0.80), (-0.33, 0.55), (-0.28, 0.30), (-0.26, 0.20)]
    door = []
    for y, z in side_pts:
        x = surface_x(fn, y, z)
        door.append([x, y, z])
    for y, zz in rail:
        x = -interp(TOP_HW, y) + 0.04
        z = surface_z(fn, x, y)
        door.append([x, y, z])
    for y, z in back:
        door.append([surface_x(fn, y, z), y, z])
    door.append(door[0])
    out["door_left"] = door
    out["door_right"] = [[-p[0], p[1], p[2]] for p in door]
    # the wing: outline of its top (seam, the side, the trailing edge) and the hinge axis (the seam's front, middle)
    wf = Field().wing
    ring = []
    for ax in np.linspace(0, 0.86, 10):
        y = float(wing_mask_y(ax))
        ring.append([-ax, y, float(ztop(np.array([ax]), np.array([y]))[0])])
    for y in np.linspace(float(wing_mask_y(0.86)), -2.05, 4)[1:]:
        ring.append([-float(interp(HW, y)) + 0.01, float(y), float(ztop(np.array([0.85]), np.array([y]))[0])])
    ring += [[x, -2.05, float(ztop(np.array([abs(x)]), np.array([-2.05]))[0])] for x in np.linspace(-0.84, 0.84, 9)]
    ring += [[-p[0], p[1], p[2]] for p in ring[::-1] if p[0] < -1e-6 and p[1] > -2.049]
    out["wing"] = ring
    yh = WING["seam_c"]
    out["wing_hinge"] = [[-0.20, yh, float(ztop(np.array([0.2]), np.array([yh]))[0])],
                         [0.20, yh, float(ztop(np.array([0.2]), np.array([yh]))[0])]]
    # charge port: no Tesla picture shows it; the rear left corner as on the family's other cars, a 12 x 9 cm door in
    # the deck under the wing (a guess, to be decided with the other cars' plug side)
    cy, cx = -1.86, -0.66
    cz = float(ztop(np.array([0.66]), np.array([cy]))[0]) - WING["thick"] - CELL
    out["charge_port"] = [[cx - 0.06, cy - 0.045, cz], [cx + 0.06, cy - 0.045, cz], [cx + 0.06, cy + 0.045, cz],
                          [cx - 0.06, cy + 0.045, cz], [cx - 0.06, cy - 0.045, cz]]
    out["charge_port_centre"] = [cx, cy, cz]
    out["head_light_bar"] = [[-0.64, 2.03, 0.385], [0.64, 2.03, 0.385]]
    out["tail_light_bar"] = [[-0.86, -2.06, 0.782], [0.86, -2.06, 0.782]]
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


def build(h=CELL):
    f = Field()
    bv, bt = mesh_of(f, (GRID["half"], GRID["y"], GRID["z"]), h)
    wfn = f.wing
    wv, wt = mesh_of(wfn, (0.95, (-2.12, -1.10), (0.6, 1.05)), h * 0.6)
    return dict(field=f, body=(bv, bt, classify(bv, bt, f)), wing=(wv, wt, classify(wv, wt, wfn, wing=True)),
                wheels=wheel_parts(), rear=rear_parts(), lines=lines(f))


# ---- Blender
COLORS = dict(Paint=((0.80, 0.80, 0.80), 0.35, 0.30), Glass=((0.03, 0.03, 0.035), 0.0, 0.12),
              Trim=((0.025, 0.025, 0.028), 0.0, 0.55), Liner=((0.015, 0.015, 0.016), 0.0, 0.85),
              HeadLight=((0.95, 0.96, 0.98), 0.0, 0.15), TailLight=((0.55, 0.02, 0.03), 0.0, 0.25),
              Tyre=((0.02, 0.02, 0.022), 0.0, 0.8), Disc=((0.45, 0.46, 0.48), 0.6, 0.35),
              Spoke=((0.03, 0.03, 0.035), 0.3, 0.35), Nozzle=((0.55, 0.50, 0.45), 1.0, 0.3),
              Fan=((0.05, 0.05, 0.05), 0.5, 0.5), Plate=((0.75, 0.76, 0.78), 0.3, 0.4))


def mesh_check(v, t):
    """Open edges, non-manifold edges, degenerate faces (a closed body: all zero)."""
    e = np.sort(np.concatenate([t[:, [0, 1]], t[:, [1, 2]], t[:, [2, 0]]]), 1)
    _, cnt = np.unique(e, axis=0, return_counts=True)
    area = np.linalg.norm(np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]]), axis=1) / 2
    return dict(open_edges=int((cnt == 1).sum()), nonmanifold_edges=int((cnt > 2).sum()),
                degenerate=int((area < 1e-10).sum()))


def main():
    import bpy
    from mathutils.bvhtree import BVHTree

    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = (args + [OUT_DIR])[0]
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    B = build()
    f = B["field"]
    mats = {}
    for nm, (rgb, metal, rough) in COLORS.items():
        m = bpy.data.materials.new(nm)
        m.use_nodes = True
        bs = m.node_tree.nodes["Principled BSDF"]
        bs.inputs["Base Color"].default_value = (*rgb, 1)
        bs.inputs["Metallic"].default_value = metal
        bs.inputs["Roughness"].default_value = rough
        m.diffuse_color = (*rgb, 1)
        mats[nm] = m

    def make(name, vv, tt, matnames, matidx=None, normals=None):
        used, inv = np.unique(tt, return_inverse=True)
        tt = inv.reshape(-1, 3)
        vv = vv[used]
        me = bpy.data.meshes.new(name)
        me.vertices.add(len(vv))
        me.vertices.foreach_set("co", vv.astype(np.float32).ravel())
        me.loops.add(tt.size)
        me.loops.foreach_set("vertex_index", tt.astype(np.int32).ravel())
        me.polygons.add(len(tt))
        me.polygons.foreach_set("loop_start", (np.arange(len(tt)) * 3).astype(np.int32))
        me.polygons.foreach_set("loop_total", np.full(len(tt), 3, np.int32))
        me.update()
        for m in matnames:
            me.materials.append(mats[m])
        if matidx is not None:
            me.polygons.foreach_set("material_index", np.asarray(matidx, np.int32))
        if normals is not None:
            me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set(
                "vector", normals[used][tt].astype(np.float32).ravel() if normals.ndim == 2 else normals.ravel())
        me.polygons.foreach_set("use_smooth", np.ones(len(tt), bool))
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob

    report = dict(objects={}, checks={})
    for nm, (v, t, mat), fn in (("Body", B["body"], f), ("Wing", B["wing"], f.wing)):
        nrm = gradient(fn, v)
        # a face whose corners' field normals turn away from it (sharp edges): faceted
        fn_ = np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]])
        fn_ /= np.maximum(np.linalg.norm(fn_, axis=1, keepdims=True), 1e-15)
        cn = nrm[t]
        cn = np.where(((cn * fn_[:, None]).sum(2) < 0.5)[..., None], fn_[:, None], cn)
        report["checks"][nm] = mesh_check(v, t)
        tree = BVHTree.FromPolygons(v.tolist(), t.tolist(), all_triangles=True)
        pairs = np.array(tree.overlap(tree), np.int64).reshape(-1, 2)
        pairs = pairs[pairs[:, 0] < pairs[:, 1]]
        # neighbours touch along a shared corner; only pairs sharing no corner are real crossings
        shared = (t[pairs[:, 0], :, None] == t[pairs[:, 1], None, :]).any((1, 2))
        report["checks"][nm]["self_intersections"] = int((~shared).sum())
        names = [MATS[i] for i in range(len(MATS))]
        make(nm, v, t, names, mat, cn)
    for grp in ("wheels", "rear"):
        for nm, (vv, tt, mn) in B[grp].items():
            make(nm, vv, tt, [mn])
    for ob in bpy.context.scene.objects:
        report["objects"][ob.name] = len(ob.data.polygons)
    bv = B["body"][0]
    report["body_bbox"] = [bv.min(0).round(4).tolist(), bv.max(0).round(4).tolist()]
    report["sizes"] = dict(L=L, W=WIDTH, H=HEIGHT, wheelbase=round(TYRES["front"]["y"] - TYRES["rear"]["y"], 4),
                           tyres={k: dict(d=round(2 * v_["r"], 3), w=v_["w"], track=round(2 * v_["x"], 3))
                                  for k, v_ in TYRES.items()})
    json.dump(report, open(os.path.join(out, "prep_report.json"), "w"), indent=1)
    ln = B["lines"]
    json.dump(dict(frame="metres, +Y front, +Z up, -X the car's left, ground 0 (prep_roadster2.py)", **ln),
              open(os.path.join(out, "roadster2_lines.json"), "w"), indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "roadster2_src.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "roadster2_src.glb"), export_format="GLB")
    print("PREP", {k: v_ for k, v_ in report["checks"].items()}, "bbox", report["body_bbox"])


if __name__ == "__main__":
    main()
