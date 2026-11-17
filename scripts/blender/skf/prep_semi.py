"""Tesla Semi Long Range (2026 production) body shell from scratch (no model file is read): drawn on Tesla's own
pictures only (temp/plan-semi-1117/img: ERG 2026 side p04-x53, bottom p09-x110, front 3/4 p01-x2202, rescue sheet
rear 3/4 rs2026 p01-x892, tesla.com Semi-LR-Specs-Desktop; the roof by eye off ERG p08-x97, no picture to measure it).
Numbers: temp/skf_semi/PREP.md (sizes, cameras); the checks: temp/skf_semi/check_semi.py.
Cab: one signed distance field meshed by surface nets (prep_cybercab's helpers), the vertices pulled onto the zero
level, normals from the field's gradient:
  - the centreline profile (PROFILE: front / top, fitted to the side picture's silhouette with the nose's plan bow)
    as a 2-D distance in (y + bow, z), the bow (PLAN_NOSE: the bottom view's nose outline, scaled by height,
    BOW_Z) rounding the nose, windshield and roof front in plan;
  - |x| <= W(y, z): the side (2.517 wide), leaning in over the glass and the roof cap, the roof cap's front tucked
    in over the windshield (ROOF_TUCK), the black deflector at full width to the rear face with its side fins (FIN)
    standing above the roof's end, a smooth max rounding the roof shoulder (SHOULDER);
  - the rear face, the low box behind the cab, the front wheel house carved out (ARCH), the mirrors joined on.
Fit and gates: temp/skf_semi/PREP.md section 8.
Then every face gets a material (paint, glass, black trim, wheel house liner, light bar) and a panel (body, left /
right door; face attribute `panel`, PANELS) from region outlines cut into the mesh (split at each level's zero).
Frame, fifth wheel, fenders, drive units, tail lamps: plain boxes and prisms; tyres and covers: revolved meshes.
Door: rear hinged (the handle at the door's front edge by the side repeater: ERG p4 x53, p7 x82; MotorTrend first
drive "the large, rear-hinged door").
Frame (PREP.md): metres, +Y front, +Z up, -X the truck's left, origin the front axle's centre on the ground.
    "$B" -b --factory-startup --python scripts/blender/skf/prep_semi.py [-- <out dir>]
        -> <out dir>/semi_src.blend, semi_src.glb, semi_lines.json, prep_report.json   (default temp/skf_semi)
Everything above `# ---- Blender` is plain numpy (importable without bpy).
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prep_cybercab import poly_sdf, round_poly, smax, surface_nets, weld  # noqa: E402  (shared SDF helpers)

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT_DIR = os.path.join(REPO, "temp", "skf_semi")

W0 = 2.517 / 2                       # cab and skirt half width (bottom view, PREP 2.2)
# centreline front / top profile (z, y): the side picture's front and top silhouette solved for the centreline with
# the nose bow below (PREP 3.1 side camera), then one pass of row-by-row correction against the side mask; the
# mirror's rows (z 1.70-2.44) a straight windshield; the rear end lowered to the rear_left view's deflector bar
PROFILE = np.array((
    (0.26, 1.129), (0.30, 1.13), (0.36, 1.15), (0.44, 1.135), (0.52, 1.158), (0.60, 1.187), (0.69, 1.185),
    (0.81, 1.193), (0.93, 1.193), (0.97, 1.168), (1.01, 1.151), (1.055, 1.142), (1.10, 1.116), (1.14, 1.098),
    (1.18, 1.072), (1.26, 1.03), (1.34, 0.978), (1.42, 0.934), (1.50, 0.883), (1.59, 0.831), (1.668, 0.755),
    (2.00, 0.504), (2.25, 0.331), (2.484, 0.213), (2.525, 0.179), (2.607, 0.113), (2.688, 0.089), (2.77, -0.009),
    (2.851, -0.068), (2.933, -0.121), (3.014, -0.189), (3.096, -0.25), (3.177, -0.311), (3.259, -0.409),
    (3.34, -0.456), (3.422, -0.55), (3.503, -0.635), (3.585, -0.739), (3.666, -0.844), (3.747, -0.953),
    (3.828, -1.134), (3.869, -1.238), (3.909, -1.333), (3.949, -1.531), (3.989, -1.999), (4.028, -2.682),
    (3.99, -3.348), (4.00, -3.427)))
# the nose in plan (|x|, y): bottom view p09-x110 outline (203.9 px/m), 1.19 on the centreline
PLAN_NOSE = np.array(((0.0, 1.19), (0.44, 1.15), (0.61, 1.10), (0.73, 1.05), (0.825, 1.0), (0.915, 0.95),
                      (0.983, 0.90), (1.035, 0.85), (1.074, 0.80), (1.108, 0.75), (1.143, 0.70), (1.17, 0.65),
                      (1.192, 0.60), (1.20, 0.55), (1.206, 0.50), (1.23, 0.40), (W0, 0.30)))
# the deflector's rear edge at the cab's full width: the bottom view's outline (2.517 m down to y -3.64) and
# front_left both fit it best; the rear view p04-x57's taper (2.33 / 2.25, PREP 0-3) costs front_left 0.011 and
# rear_left 0.039 IoU, while rear_left alone would take a 2-4 cm flare (front_left -0.001 to -0.004)
REAR = dict(y=-3.64, box_y=-3.93, box_z=1.02, defl_y=-3.38, w_bot=W0, w_top=W0)
SKIRT_Z, BUMPER_Z = 0.09, 0.26       # skirt bottom (side row 516), lower bumper bottom
LEAN = ((1.85, 0.0), (2.75, 0.03), (4.0, 0.03))     # (z, inset): the side leans in over the glass and the roof cap
BOW_Z = ((0.9, 1.0), (1.3, 1.25), (2.0, 1.3), (3.0, 1.1), (3.6, 0.8))   # (z, scale): the nose bow by height:
#                                                   rounder hood corners, fuller roof front (both 3/4 front views)
SHOULDER = ((2.9, 0.03), (3.4, 0.30))               # (z, smax k): the roof shoulder's rounding, small below
ROOF_TUCK = dict(d=0.3, z=(2.8, 3.8), y=(-2.2, -0.7))   # the roof cap's front narrows in over the glass (rear_left)
FIN = ((W0 - 0.0585, -3.51, 2.62), (0.0585, 0.13, 1.42), 0.03)   # deflector side fins (centre, half size, rounding):
#                                                          4.04 m, above the white roof's end (side (615, 21))
ARCH = dict(y=-0.035, z=0.503, r=0.577, x_in=0.85)  # front wheel house: through the feet (+0.50 / -0.57, z 0.72)
#                                                   and the top (1.08), side p04-x53
ARCH_LIP = 0.04                      # the black lip round the front wheel house (side p04-x53)
MIRROR = dict(head=((1.43, 0.295, 2.04), (0.07, 0.095, 0.37), 0.04), arm=((1.29, 0.26, 1.74), (0.13, 0.04, 0.04), 0.02))
GRID = dict(half=1.53, y=(-3.98, 1.24), z=(0.05, 4.12))
CELL = 0.03                          # surface nets cell: about 210k cab triangles (Cybercab's source: 145k)

# regions (side p04-x53 back-projected, PREP 2.3)
GLASS = ((2.0, 1.66), (0.27, 1.66), (-0.66, 1.85), (-1.55, 2.08), (-1.63, 2.15), (-1.65, 2.46), (-1.60, 2.75),
         (2.0, 2.75))                                # side glass band (y, z); the windshield its front part
GLASS_FRAME = 0.03                   # black border round the glass band
A_PILLAR = (0.307, -0.514, 0.035)    # y at z 1.66, dy/dz, half width: windshield | vent window (side 165,280-210,192)
DOOR = dict(y=(-1.73, -0.66), z=(0.72, 2.77))       # door seams (u 395 / 262), its top the belt under the roof cap
SEAM2 = -2.79                        # second panel seam (u 527)
BELT = ((-1.73, 2.77), (-2.79, 2.79), (-3.37, 2.95))  # roof cap's lower edge behind the door
GROOVE = 0.003
WHITE_Z = 0.715                      # white body | black skirt and lower bumper (side rows 437-440)
WHITE_Y = -3.375                     # white roof / side end, black deflector behind (u 600)
HANDLE = (-0.88, -0.82, 1.08, 1.15)  # door handle recess (y0, y1, z0, z1): side (285, 388), p07-x82
REPEATER = (-0.52, -0.46, 1.09, 1.13)   # side repeater in front of the door
LAMP = dict(y=(0.95, 0.54), z0=(0.995, 1.035), z1=(1.025, 1.085))   # light bar: (front, rear) of its corner wedge

MATS = ("Paint", "Glass", "Trim", "Liner", "HeadLight", "TailLight")
PANELS = ("Body", "DoorFrontLeft", "DoorFrontRight")
PANES = ("Glass_Windshield", "Glass_DoorLeft", "Glass_DoorRight", "Glass_VentLeft", "Glass_VentRight")

# wheels (PREP 2.1 / 2.2): front single tyres, two drive axles of duals
TYRE_R = 0.49
FRONT = dict(y=0.0, x=2.19 / 2, w=0.285)
DRIVE = dict(y=(-4.42, -5.64), x=(1.092, 0.758), w=0.27)
RIM_R = 0.29

# chassis behind the cab (side p04-x53, bottom p09-x110)
BOXES = dict(   # name: (material, (x0, x1) on the right (mirrored), (y0, y1), (z0, z1))
    rail=("Trim", (0.33, 0.43), (-6.22, -3.64), (0.71, 1.01)),
    bracket=("Trim", (0.43, 0.55), (-5.30, -4.70), (0.60, 0.95)),
    crossmember=("Trim", (0.0, 0.55), (-6.22, -6.14), (0.65, 1.00)),
    drive=("Trim", (0.0, 0.33), (-6.10, -3.93), (0.35, 0.95)),
    axle_m=("Trim", (0.0, 0.62), (-4.51, -4.33), (0.40, 0.58)),
    axle_r=("Trim", (0.0, 0.62), (-5.73, -5.55), (0.40, 0.58)),
    fifth=("Trim", (0.0, 0.46), (-5.50, -4.67), (1.13, 1.19)),        # fifth wheel plate, top z 1.19
    fifth_mount=("Trim", (0.30, 0.42), (-5.30, -4.85), (1.01, 1.13)),
    tail_lamp=("TailLight", (0.20, 0.32), (-6.232, -6.22), (0.80, 0.88)),
)
PRISMS = dict(  # name: (material, (x0, x1), (y, z) outline): fenders between and behind the drive axles
    fender_mid=("Trim", (1.19, 1.23), ((-4.70, 1.03), (-5.22, 1.03), (-5.16, 0.50), (-5.10, 0.10), (-4.95, 0.10),
                                       (-4.89, 0.50))),
    fender_rear=("Trim", (0.62, 1.235), ((-6.02, 0.99), (-6.66, 0.90), (-6.66, 0.26), (-6.30, 0.22), (-6.12, 0.12),
                                         (-6.18, 0.30), (-6.18, 0.70), (-6.10, 0.90))),
)
CABIN = dict(floor_z=0.80, y=(0.25, -3.30))   # [INFERENCE] the door sill 0.72; front: the cowl, rear: inside the wall


def interp(tab, x):
    tab = np.asarray(tab, float)
    return np.interp(x, tab[:, 0], tab[:, 1])


def bow(ax, z):
    """How far the nose's outline sits back of its centreline at |x| and height z (the plan's rounding)."""
    return interp(BOW_Z, z) * (1.19 - interp(PLAN_NOSE, ax))


_PROF = np.r_[PROFILE[:, ::-1], [(-8.0, PROFILE[-1, 0]), (-8.0, SKIRT_Z), (-0.62, SKIRT_Z), (-0.55, BUMPER_Z),
                                 (0.95, BUMPER_Z)]]


def half_width(y, z):
    tuck = ROOF_TUCK["d"] * np.clip((z - ROOF_TUCK["z"][0]) / (ROOF_TUCK["z"][1] - ROOF_TUCK["z"][0]), 0, 1) * \
        np.clip((y - ROOF_TUCK["y"][0]) / (ROOF_TUCK["y"][1] - ROOF_TUCK["y"][0]), 0, 1)
    w = W0 - interp(LEAN, z) - tuck
    t = np.clip((REAR["defl_y"] - y) / (REAR["defl_y"] - REAR["y"]), 0, 1)
    wr = REAR["w_bot"] + (REAR["w_top"] - REAR["w_bot"]) * np.clip((z - 1.19) / 2.86, 0, 1)
    return np.where(z > REAR["box_z"], w + (wr - w) * t, W0)


def rbox(p, c, h, r):
    q = np.abs(p - np.asarray(c)) - (np.asarray(h) - r)
    return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(q.max(1), 0) - r


def cab_parts(p):
    """(cab, mirror) distances."""
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    ax = np.abs(x)
    d_prof = poly_sdf(_PROF, y + bow(ax, z), z)
    d_side = ax - half_width(y, z)
    d = smax(d_prof, d_side, interp(SHOULDER, z))
    d_rear = np.minimum(REAR["y"] - y, np.maximum(REAR["box_y"] - y, z - REAR["box_z"]))
    d = np.maximum(d, d_rear)
    d = np.minimum(d, rbox(np.c_[ax, y, z], *FIN))
    house = np.maximum(np.hypot(y - ARCH["y"], z - ARCH["z"]) - ARCH["r"], ARCH["x_in"] - ax)
    d = np.maximum(d, -house)
    pm = np.c_[ax, y, z]
    mir = np.minimum(rbox(pm, *MIRROR["head"]), rbox(pm, *MIRROR["arm"]))
    return d, mir


def field(p):
    return np.minimum(*cab_parts(p))


def project(v, steps=4, eps=2e-4, cap=0.5 * CELL):
    p = v
    for _ in range(steps):
        d = field(p)
        g = np.stack([(field(p + e) - field(p - e)) / (2 * eps) for e in np.eye(3) * eps], 1)
        p = p - (d / np.maximum((g ** 2).sum(1), 1e-12))[:, None] * g
    return np.where((np.abs(p - v).max(1) < cap)[:, None], p, v)


def normals(v, eps=2e-4):
    g = np.stack([(field(v + e) - field(v - e)) / (2 * eps) for e in np.eye(3) * eps], 1)
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)


def split(v, t, g):
    """Cut the triangles crossing g = 0 (g per vertex), the new vertices on the surface; orientation kept."""
    s = g[t] >= 0
    cnt = s.sum(1)
    cr = (cnt == 1) | (cnt == 2)
    if not cr.any():
        return v, t
    tc = t[cr]
    lone = np.where(cnt[cr] == 1, np.argmax(s[cr], 1), np.argmin(s[cr], 1))
    r = np.arange(len(tc))
    a, b, c = tc[r, lone], tc[r, (lone + 1) % 3], tc[r, (lone + 2) % 3]
    e = np.sort(np.concatenate([np.stack([a, b], 1), np.stack([a, c], 1)]), 1)
    ue, inv = np.unique(e, axis=0, return_inverse=True)
    w = g[ue[:, 0]] / (g[ue[:, 0]] - g[ue[:, 1]])
    nv = project(v[ue[:, 0]] + w[:, None] * (v[ue[:, 1]] - v[ue[:, 0]]))
    pab, pac = np.split(len(v) + inv.ravel(), 2)
    new = np.concatenate([np.stack([a, pab, pac], 1), np.stack([pab, b, c], 1), np.stack([pab, c, pac], 1)])
    return np.concatenate([v, nv]), np.concatenate([t[~cr], new])


_GLASS = round_poly(GLASS, r=0.04)


def levels():
    """Region outlines: name -> g(x, y, z, |x|), negative inside (each one cut into the mesh)."""
    def y_ap(z):
        return A_PILLAR[0] + A_PILLAR[1] * (z - 1.66)

    def box_g(lo_hi_y, lo_hi_z, x_min=0.9):
        (y0, y1), (z0, z1) = lo_hi_y, lo_hi_z
        return lambda x, y, z, ax: np.maximum.reduce([y0 - y, y - y1, z0 - z, z - z1, x_min - ax])

    return dict(
        glass=lambda x, y, z, ax: poly_sdf(_GLASS, y, z),
        glass_frame=lambda x, y, z, ax: poly_sdf(_GLASS, y, z) + GLASS_FRAME,
        ap_front=lambda x, y, z, ax: y_ap(z) + A_PILLAR[2] - y,
        ap_rear=lambda x, y, z, ax: y_ap(z) - A_PILLAR[2] - y,
        white_z=lambda x, y, z, ax: WHITE_Z - z,
        white_y=lambda x, y, z, ax: WHITE_Y - y,
        door=box_g(DOOR["y"], DOOR["z"]),
        seam2=lambda x, y, z, ax: np.maximum.reduce([y - SEAM2, WHITE_Z - z, z - interp(BELT[::-1], y), 0.9 - ax]),
        belt=lambda x, y, z, ax: np.maximum(z - interp(BELT[::-1], y), np.maximum(y - DOOR["y"][0], 0.9 - ax)),
        handle=box_g(HANDLE[:2], HANDLE[2:]),
        repeater=box_g(REPEATER[:2], REPEATER[2:]),
        lamp=lambda x, y, z, ax: np.maximum.reduce([LAMP["y"][1] - y,
                                                    interp(((0.0, LAMP["z0"][1]), (1.0, LAMP["z0"][0])), lamp_t(y)) - z,
                                                    z - interp(((0.0, LAMP["z1"][1]), (1.0, LAMP["z1"][0])), lamp_t(y))]),
        arch_lip=lambda x, y, z, ax: np.hypot(y - ARCH["y"], z - ARCH["z"]) - ARCH["r"] - ARCH_LIP,
    )


def lamp_t(y):
    """0 at the corner wedge's rear end, 1 from its front end on (the bar across the nose)."""
    return np.clip((y - LAMP["y"][1]) / (LAMP["y"][0] - LAMP["y"][1]), 0, 1)


SEAMS = ("door", "seam2", "belt")


def classify(v, t):
    c = v[t].mean(1)
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    ax = np.abs(x)
    cab, mir = cab_parts(c)
    s = {k: g(x, y, z, ax) < 0 for k, g in levels().items()}
    mat = np.zeros(len(t), np.int8)
    pan = np.zeros(len(t), np.int8)
    pane = np.full(len(t), -1, np.int8)
    glass = s["glass_frame"]
    ws = glass & s["ap_front"]
    vent = glass & ~s["ap_rear"] & (y > DOOR["y"][1] + 0.02)
    door_glass = glass & (y < DOOR["y"][1] - 0.02)
    mat[ws | vent | door_glass] = 1
    pane[ws] = 0
    pane[door_glass] = np.where(x[door_glass] < 0, 1, 2)
    pane[vent] = np.where(x[vent] < 0, 3, 4)
    mat[s["glass"] & (mat == 0)] = 2                 # frame, pillars, door glass frame
    mat[~s["white_z"] | ~s["white_y"]] = 2
    mat[s["handle"] | s["repeater"]] = 2
    mat[s["lamp"] & (mat == 0)] = 4
    house = np.hypot(y - ARCH["y"], z - ARCH["z"])
    liner = (house < ARCH["r"] + 0.004) & (ax < ARCH["x_in"] + 0.004) & (ax > 0.3) | \
            (house < ARCH["r"] + 0.004) & (ax < half_width(y, z) - 0.004)
    mat[s["arch_lip"] & (mat == 0)] = 2                # black arch lip
    mat[liner] = 3
    mat[mir < cab] = 2
    door = s["door"] & ~liner
    pan[door] = np.where(x[door] < 0, 1, 2)
    return mat, pan, pane


def grooves(v, t, mat):
    """Seam faces (a GROOVE wide strip either side of each seam) turn black: the seams read as thin dark lines."""
    c = v[t].mean(1)
    ax = np.abs(c[:, 0])
    lv = levels()
    near = np.zeros(len(t), bool)
    for k in SEAMS:
        near |= np.abs(lv[k](c[:, 0], c[:, 1], c[:, 2], ax)) < GROOVE
    return np.where(near & (mat == 0), 2, mat)


def cab_mesh(h=CELL):
    n = int(np.ceil(GRID["half"] / h))
    v, q = surface_nets(field, h, ((-(n - 0.5) * h, (n - 0.5) * h), GRID["y"], GRID["z"]))
    v = project(v, cap=0.5 * h)
    d02 = np.linalg.norm(v[q[:, 0]] - v[q[:, 2]], axis=1)
    d13 = np.linalg.norm(v[q[:, 1]] - v[q[:, 3]], axis=1)
    t = np.where((d13 < d02)[:, None], q[:, [0, 1, 3]], q[:, [0, 1, 2]])
    t2 = np.where((d13 < d02)[:, None], q[:, [1, 2, 3]], q[:, [0, 2, 3]])
    t = np.concatenate([t, t2])
    lv = levels()
    cuts = list(lv.items()) + [(k, (lambda g, o: lambda x, y, z, ax: g(x, y, z, ax) - o)(lv[k], o))
                               for k in SEAMS for o in (-GROOVE, GROOVE)]
    for _, g in cuts:
        v, t = split(v, t, g(v[:, 0], v[:, 1], v[:, 2], np.abs(v[:, 0])))
    v, t = weld(v, t)
    mat, pan, pane = classify(v, t)
    mat = grooves(v, t, mat)
    return v, t, mat, pan, pane


# ---- simple parts
def box(x, y, z):
    (x0, x1), (y0, y1), (z0, z1) = x, y, z
    v = np.array([(a, b, c) for a in (x0, x1) for b in (y0, y1) for c in (z0, z1)], float)
    t = np.array(((0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6),
                  (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)))
    return v, t


def prism(poly, x):
    """The (y, z) outline (star shaped from its centroid) extruded over x = (x0, x1)."""
    p = np.asarray(poly, float)
    n = len(p)
    c = p.mean(0)
    ring = lambda xx: np.c_[np.full(n + 1, xx), np.r_[p, [c]]]
    v = np.concatenate([ring(x[0]), ring(x[1])])
    i = np.arange(n)
    j = (i + 1) % n
    cap0 = np.stack([np.full(n, n), j, i], 1)
    cap1 = np.stack([np.full(n, n), i, j], 1) + n + 1
    side = np.concatenate([np.stack([i, j, j + n + 1], 1), np.stack([i, j + n + 1, i + n + 1], 1)])
    t = np.concatenate([cap0, cap1, side])
    e, f = p[j] - p[i], c - p[i]
    area = (e[:, 0] * f[:, 1] - e[:, 1] * f[:, 0]).sum()   # orient outward whatever the outline's direction
    return v, (t[:, ::-1] if area < 0 else t)


def mirror_x(v, t):
    return v * (-1, 1, 1), t[:, ::-1]


def lathe(prof, n=48):
    """Revolve (r, x) points round the x axis, returns vertices round the origin and triangles."""
    prof = np.asarray(prof, float)
    a = np.linspace(0, 2 * np.pi, n, endpoint=False)
    v = np.stack([np.repeat(prof[:, 1], n), np.outer(prof[:, 0], np.cos(a)).ravel(),
                  np.outer(prof[:, 0], np.sin(a)).ravel()], 1)
    k = np.arange(len(prof) - 1)[:, None] * n
    i = np.arange(n)[None]
    j = (i + 1) % n
    q = np.stack([k + i, k + j, k + n + j, k + n + i], -1).reshape(-1, 4)
    t = np.concatenate([q[:, [0, 1, 2]], q[:, [0, 2, 3]]])
    return v, t


def tyre(w, r=TYRE_R, rim=RIM_R, sh=0.035):
    return lathe(((rim, -w / 2), (r - sh, -w / 2), (r, -w / 2 + sh), (r, w / 2 - sh), (r - sh, w / 2), (rim, w / 2)))


def cover(rr, dish=0.02):
    v, t = lathe(((0.0, 0.0), (rr * 0.25, 0.0), (rr * 0.85, -dish * 0.3), (rr, -dish)))
    return v, t


def wheels():
    """name -> (origin, vertices relative to it, triangles, material). Drive tyres keep their axle's centre."""
    out = {}
    for side, sx in (("L", -1), ("R", 1)):
        o = np.array((0.0, FRONT["y"], TYRE_R))
        tv, tt = tyre(FRONT["w"])
        out[f"Tyre_F_{side}"] = (o, tv + (sx * FRONT["x"], 0, 0), tt, "Tyre")
        cv, ct = cover(RIM_R)
        face = sx * (FRONT["x"] + FRONT["w"] / 2 - 0.035)
        out[f"Cover_F_{side}"] = (o, cv * (sx, 1, 1) + (face, 0, 0), ct if sx > 0 else ct[:, ::-1], "Rim")
        for k, y in enumerate(DRIVE["y"], 1):
            o = np.array((0.0, y, TYRE_R))
            for io, x in (("O", DRIVE["x"][0]), ("I", DRIVE["x"][1])):
                tv, tt = tyre(DRIVE["w"])
                out[f"Tyre_D{k}_{side}{io}"] = (o, tv + (sx * x, 0, 0), tt, "Tyre")
            cv, ct = cover(0.31, dish=0.0)
            face = sx * (DRIVE["x"][0] + DRIVE["w"] / 2 - 0.01)
            out[f"Cover_D{k}_{side}O"] = (o, cv * (sx, 1, 1) + (face, 0, 0), ct if sx > 0 else ct[:, ::-1], "Cover")
    return out


def chassis():
    """name -> (vertices, triangles, material): both sides in one object each."""
    out = {}
    for nm, (m, x, y, z) in BOXES.items():
        v, t = box(x, y, z)
        if x[0] == 0.0:
            v, t = box((-x[1], x[1]), y, z)
            out[nm] = (v, t, m)
            continue
        v2, t2 = mirror_x(v, t)
        out[nm] = (np.concatenate([v, v2]), np.concatenate([t, t2 + len(v)]), m)
    for nm, (m, x, poly) in PRISMS.items():
        v, t = prism(poly, x)
        v2, t2 = mirror_x(v, t)
        out[nm] = (np.concatenate([v, v2]), np.concatenate([t, t2 + len(v)]), m)
    return out


def all_mesh():
    """Every triangle in one (v, t) for the silhouette checks (check_semi.py)."""
    v, t, *_ = cab_mesh()
    vs, ts = [v], [t]
    n = len(v)
    for vv, tt, _ in chassis().values():
        vs.append(vv)
        ts.append(tt + n)
        n += len(vv)
    for o, vv, tt, _ in wheels().values():
        vs.append(vv + o)
        ts.append(tt + n)
        n += len(vv)
    return np.concatenate(vs), np.concatenate(ts)


def lines():
    W, (y0, y1), (z0, z1) = W0, DOOR["y"], DOOR["z"]
    return dict(
        door_left=[[-W, y1, z0], [-W, y0, z0], [-W, y0, z1], [-W, y1, z1]],
        door_hinge_left=[[-W, y0, z0 + 0.10], [-W, y0, z1 - 0.15]],
        door_hinge="rear: the handle at the door's front edge (ERG p4 x53, p7 x82; MotorTrend 'rear-hinged door')",
        cabin_floor_z=CABIN["floor_z"], cabin_y=list(CABIN["y"]),
        cabin_note="[INFERENCE] floor from the door sill (z 0.72), not measured; driver seat on the centreline, "
                   "the folding seat behind it on the right (ERG p5)",
    )


# ---- Blender
COLORS = dict(Paint=((0.80, 0.81, 0.82), 0.0, 0.30), Glass=((0.02, 0.025, 0.03), 0.0, 0.08),
              Trim=((0.03, 0.03, 0.033), 0.0, 0.55), Liner=((0.012, 0.012, 0.013), 0.0, 0.85),
              HeadLight=((0.92, 0.94, 0.96), 0.0, 0.15), TailLight=((0.35, 0.02, 0.02), 0.0, 0.25),
              Tyre=((0.02, 0.02, 0.022), 0.0, 0.8), Rim=((0.62, 0.63, 0.65), 0.7, 0.35),
              Cover=((0.03, 0.03, 0.033), 0.2, 0.45))


def main():
    import bpy

    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = (args + [OUT_DIR])[0]
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
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

    def make(name, vv, tt, mat, panel=None, smooth=None, origin=(0.0, 0.0, 0.0)):
        """smooth: per-triangle bool, field normals on those (None: all), flat elsewhere."""
        used, inv = np.unique(tt, return_inverse=True)
        tt = inv.reshape(-1, 3)
        vv = vv[used]
        me = bpy.data.meshes.new(name)
        me.vertices.add(len(vv))
        me.vertices.foreach_set("co", (vv - origin).astype(np.float32).ravel())
        me.loops.add(tt.size)
        me.loops.foreach_set("vertex_index", tt.astype(np.int32).ravel())
        me.polygons.add(len(tt))
        me.polygons.foreach_set("loop_start", (np.arange(len(tt)) * 3).astype(np.int32))
        me.polygons.foreach_set("loop_total", np.full(len(tt), 3, np.int32))
        me.update()
        me.materials.append(mats[mat])
        if panel is not None:
            me.attributes.new("panel", "INT", "FACE").data.foreach_set("value", np.asarray(panel, np.int32))
        sm = np.broadcast_to(np.asarray(True if smooth is None else smooth, bool), len(tt)).copy()
        if sm.any():
            # field normals per corner on the smooth faces, the face's own on the rest (Blender 5.2: written straight
            # into the custom_normal attribute)
            p = vv[tt]
            fn = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
            n = np.repeat(fn / np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12), 3, 0)
            c = np.repeat(sm, 3)
            n[c] = normals(vv[tt[sm].ravel()])
            me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set(
                "vector", n.astype(np.float32).ravel())
        me.polygons.foreach_set("use_smooth", sm)
        ob = bpy.data.objects.new(name, me)
        ob.location = origin
        bpy.context.scene.collection.objects.link(ob)
        return ob

    v, t, mat, pan, pane = cab_mesh()
    keep = (t[:, 0] != t[:, 1]) & (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])
    v, t, mat, pan, pane = v, t[keep], mat[keep], pan[keep], pane[keep]
    # one object per material: the cab's faces (field normals) plus the chassis parts of that material (flat)
    parts = {}
    for i, nm in enumerate(MATS):
        sel = (mat == i) & (pane < 0)
        if nm != "Glass" and sel.any():
            parts[nm] = [(v, t[sel], pan[sel], True)]
    for vv, tt, m in chassis().values():
        parts.setdefault(m, []).append((vv, tt, np.zeros(len(tt), np.int32), False))
    for nm, lst in parts.items():
        n, vs, ts = 0, [], []
        for vv, tt, _, _ in lst:
            used, inv = np.unique(tt, return_inverse=True)
            vs.append(vv[used])
            ts.append(inv.reshape(-1, 3) + n)
            n += len(used)
        make(nm, np.concatenate(vs), np.concatenate(ts), nm, np.concatenate([p for _, _, p, _ in lst]),
             np.concatenate([np.full(len(tt), s) for _, tt, _, s in lst]))
    for i, nm in enumerate(PANES):
        sel = pane == i
        if sel.any():
            make(nm, v, t[sel], "Glass", pan[sel])
    for nm, (o, vv, tt, m) in wheels().items():
        make(nm, vv + o, tt, m, smooth=False, origin=o)
    # report / lines
    report = dict(objects={ob.name: len(ob.data.polygons) for ob in bpy.context.scene.objects})
    allv = np.concatenate([np.array([tuple(ob.matrix_world @ vv.co) for vv in ob.data.vertices])
                           for ob in bpy.context.scene.objects if not ob.name.startswith(("Tyre", "Cover"))])
    report["body_bbox"] = [allv.min(0).round(4).tolist(), allv.max(0).round(4).tolist()]
    report["body_tris"] = int(sum(n for k, n in report["objects"].items() if not k.startswith(("Tyre", "Cover"))))
    report["panels"] = PANELS
    report["wheels"] = dict(front=dict(y=FRONT["y"], r=TYRE_R, w=FRONT["w"], track_m=round(2 * FRONT["x"], 4)),
                            drive=dict(y=list(DRIVE["y"]), r=TYRE_R, w=DRIVE["w"], x=list(DRIVE["x"])),
                            note="PREP.md 2.1 / 2.2: bottom view p09-x110 and side p04-x53, not official")
    json.dump(report, open(os.path.join(out, "prep_report.json"), "w"), indent=1)
    json.dump(dict(frame="metres, +Y front, +Z up, -X the truck's left, origin the front axle's centre on the ground "
                         "(prep_semi.py)", **lines()), open(os.path.join(out, "semi_lines.json"), "w"), indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "semi_src.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "semi_src.glb"), export_format="GLB")
    print("PREP", report["body_tris"], "body triangles; bbox", report["body_bbox"])


if __name__ == "__main__":
    main()
