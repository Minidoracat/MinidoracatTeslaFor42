"""Cybercab body shell from scratch (no model file is read): the production gold Cybercab drawn on Tesla's own
pictures only (temp/plan-next-1114/assets/official-cybercab/: rider guide side / front / rear 01, front 3/4 02,
rescue sheet rear 3/4 03, trunk open 04, rescue sheet top + side line art 06, ERG charge port 07).
Shape: one signed distance field (SDF) sampled on a grid and meshed by surface nets, the vertices pulled onto the
zero level, normals from the field's gradient:
  - the side profile (SIDE_TOP / SIDE_BOT: 01's side view, height scale 1,408 mm over the ground line through the
    two tyre bottoms) as a 2-D distance in (y, z), eroded with |x| by the crown (SECTION crown);
  - the plan (PLAN: 06's top view, widest point the official 1,754; the nose squared and the rear haunch widened on
    01 / 02 / 03, REPORT.md) and the section (SECTION knots along y: height of the widest point, the tuck under,
    the shoulder and the tumblehome above it) as |x| <= hw(y, z);
  - the two joined by a smooth max (rounded edges, SECTION k), the wheel houses carved out (ARCH), the front lower
    intake recessed (INTAKE).
Then (REGIONS) every face gets a material (paint, glass, black trim, wheel house liner, head light, tail light) and
a panel (body, doors, tailgate, hood, charge port door; face attribute `panel`, PANELS) from the region outlines;
the outlines between them are smoothed into real edges. The left half is decimated with every outline held and
mirrored (exactly symmetric, no cracks between materials), then split one object per material (glass per pane).
The fender cameras and B pillar buttons are small parts; tyres and flat wheel covers are revolved meshes.
Length / wheelbase: 01 side at the official height's scale (4,280 / 2,757 mm; 06's side view agrees to 0.3 %).
Frame (as prep_roadster): metres, +Y front, +Z up, -X the car's left, ground 0, y 0 half way along the car.
    "$B" -b --factory-startup --python scripts/blender/skf/prep_cybercab.py [-- <out dir>]
        -> <out dir>/cybercab_src.blend, cybercab_src.glb, cybercab_lines.json, prep_report.json
           (default temp/skf_cc; about a minute)
Everything above `# ---- Blender` is plain numpy (importable without bpy: the checks in temp/skf_cc/work).
How the numbers were measured: temp/skf_cc/REPORT.md.
"""
import json
import math
import os
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT_DIR = os.path.join(REPO, "temp", "skf_cc")

# official (rider guide p.15): width 1,754, height 1,408, ground clearance 144; length and wheelbase measured on 01
# (height scale; 06's side view agrees to 0.3 %), tyres third party (front 215/60 R18, rear 225/60 R21)
L, WIDTH, HEIGHT, CLEAR = 4.2799, 1.754, 1.408, 0.144
TYRES = dict(front=dict(y=1.4495, r=0.3576, w=0.215, rim=0.2286),
             rear=dict(y=-1.3074, r=0.4017, w=0.225, rim=0.2667))
WHEEL_X = dict(front=0.790, rear=0.730)        # outer face of the wheel cover (|x|), on 01's front and rear views
COVER_R = dict(front=0.309, rear=0.338)        # the covers' gold outline on 01 (178 / 195 px)

# ---- tables read off the official pictures (temp/skf_cc/work: tables.json, tables_lit.txt)
SIDE_TOP = np.array((
    (2.1400, 0.2765), (2.1310, 0.2859), (2.1273, 0.2911), (2.1249, 0.2973),
    (2.1235, 0.3063), (2.1205, 0.5611), (2.1194, 0.5755), (2.1161, 0.5854),
    (2.1027, 0.6043), (2.0898, 0.6292), (2.0841, 0.6356), (2.0738, 0.6440),
    (2.0159, 0.6847), (1.9523, 0.7255), (1.9096, 0.7508), (1.8683, 0.7736),
    (1.7949, 0.8102), (1.7362, 0.8358), (1.6850, 0.8555), (1.6229, 0.8756),
    (1.5798, 0.8872), (1.5390, 0.8970), (1.5022, 0.9042), (1.4476, 0.9131),
    (1.3579, 0.9218), (1.2904, 0.9242), (1.2546, 0.9267), (1.1184, 0.9259),
    (1.1105, 0.9265), (1.1038, 0.9283), (1.0967, 0.9314), (1.0866, 0.9373),
    (0.9424, 1.0310), (0.8377, 1.0958), (0.7236, 1.1617), (0.6797, 1.1864),
    (0.5929, 1.2326), (0.4875, 1.2850), (0.4460, 1.3042), (0.3731, 1.3345),
    (0.3387, 1.3475), (0.2905, 1.3633), (0.2429, 1.3760), (0.1991, 1.3855),
    (0.1507, 1.3939), (0.0632, 1.4033), (-0.0054, 1.4054), (-0.0401, 1.4080),
    (-0.1091, 1.4078), (-0.1478, 1.4047), (-0.1917, 1.4038), (-0.2373, 1.4017),
    (-0.3039, 1.3954), (-0.3491, 1.3923), (-0.4226, 1.3833), (-0.4613, 1.3776),
    (-0.4914, 1.3743), (-0.5239, 1.3686), (-0.5830, 1.3600), (-0.6098, 1.3546),
    (-0.6831, 1.3419), (-0.8124, 1.3151), (-0.8369, 1.3091), (-0.8841, 1.2992),
    (-1.0279, 1.2640), (-1.1507, 1.2314), (-1.2356, 1.2076), (-1.3786, 1.1660),
    (-1.5691, 1.1066), (-1.7704, 1.0403), (-1.9376, 0.9830), (-2.0707, 0.9358),
    (-2.0813, 0.9302), (-2.0871, 0.9235), (-2.0912, 0.9120), (-2.0934, 0.8952),
    (-2.0955, 0.5593), (-2.0964, 0.5421), (-2.0990, 0.5344), (-2.1039, 0.5298),
    (-2.1100, 0.5273), (-2.1296, 0.5217), (-2.1395, 0.5171),
))
SIDE_BOT = np.array((
    (2.1402, 0.2630), (2.1306, 0.2552), (2.1206, 0.2497), (2.0796, 0.2325),
    (2.0556, 0.2237), (2.0285, 0.2151), (1.9948, 0.2056), (1.9615, 0.1975),
    (1.9314, 0.1870), (1.9000, 0.1735), (1.8719, 0.1628), (1.8517, 0.1568),
    (1.8367, 0.1547), (1.0578, 0.1715), (1.0404, 0.1728), (1.0202, 0.1781),
    (1.0123, 0.1789), (0.9907, 0.1773), (-0.4274, 0.1708), (-0.4711, 0.1693),
    (-0.5287, 0.1705), (-0.7490, 0.1694), (-0.7698, 0.1685), (-0.7860, 0.1663),
    (-0.8080, 0.1600), (-0.8324, 0.1504), (-0.8463, 0.1460), (-0.8581, 0.1440),
    (-0.8728, 0.1442), (-1.7557, 0.2051), (-1.8020, 0.2112), (-1.8371, 0.2140),
    (-1.8831, 0.2201), (-1.9122, 0.2228), (-1.9520, 0.2300), (-1.9658, 0.2333),
    (-1.9814, 0.2388), (-2.0008, 0.2484), (-2.0120, 0.2555), (-2.0301, 0.2697),
    (-2.0375, 0.2742), (-2.0845, 0.2890), (-2.0930, 0.2935), (-2.0981, 0.2988),
    (-2.1006, 0.3050), (-2.1017, 0.3152), (-2.1038, 0.4561), (-2.1048, 0.4704),
    (-2.1063, 0.4751), (-2.1090, 0.4788), (-2.1277, 0.4903), (-2.1337, 0.4964),
    (-2.1407, 0.5057),
))
PLAN = np.array((
    (-2.1410, 0.7170), (-2.1250, 0.7487), (-2.1200, 0.7575), (-2.1150, 0.7648),
    (-2.1100, 0.7708), (-2.1050, 0.7758), (-2.0950, 0.7841), (-2.0900, 0.7875),
    (-2.0800, 0.7933), (-2.0700, 0.7977), (-2.0550, 0.8023), (-2.0400, 0.8050),
    (-1.9900, 0.8105), (-1.9400, 0.8171), (-1.7850, 0.8407), (-1.7150, 0.8503),
    (-1.6800, 0.8543), (-1.6450, 0.8576), (-1.6150, 0.8597), (-1.5800, 0.8613),
    (-1.5050, 0.8624), (-1.1600, 0.8625), (-1.0950, 0.8621), (-1.0450, 0.8608),
    (-0.9900, 0.8577), (-0.9250, 0.8523), (-0.8650, 0.8462), (-0.7350, 0.8314),
    (-0.6350, 0.8222), (-0.6000, 0.8199), (-0.5600, 0.8182), (-0.5150, 0.8170),
    (-0.4750, 0.8167), (-0.4050, 0.8173), (-0.0850, 0.8257), (0.0900, 0.8311),
    (0.6800, 0.8515), (1.2050, 0.8710), (1.3000, 0.8738), (1.4300, 0.8777),
    (1.4700, 0.8780), (1.5100, 0.8775), (1.5650, 0.8750), (1.6050, 0.8728),   # peak +1 mm: the edge rounding
    (1.6450, 0.8694), (1.7210, 0.8613), (1.7473, 0.8583), (1.7735, 0.8546),
    (1.7945, 0.8506), (1.8155, 0.8452), (1.8365, 0.8383), (1.8575, 0.8296),
    (1.8785, 0.8190), (1.8995, 0.8062), (1.9153, 0.7949), (1.9310, 0.7818),
    (1.9520, 0.7616), (1.9678, 0.7442), (1.9835, 0.7246), (1.9993, 0.7026),
    (2.0150, 0.6778), (2.0255, 0.6595), (2.0413, 0.6288), (2.0518, 0.6058),
    (2.0623, 0.5805), (2.0728, 0.5523), (2.0833, 0.5206), (2.0938, 0.4844),
    (2.1043, 0.4419), (2.1095, 0.4173), (2.1148, 0.3898), (2.1200, 0.3585),
    (2.1253, 0.3232), (2.1358, 0.2476), (2.1410, 0.0000),
))
# side windows (both panes; 01 side, (y, z)): the door glass ahead of DIVIDER, the fixed quarter glass behind it
SIDE_GLASS = np.array((
    (0.896, 0.944), (0.896, 0.954), (0.889, 0.956), (0.881, 0.962), (0.845, 0.993), (0.796, 1.032),
    (0.719, 1.089), (0.670, 1.121), (0.646, 1.128), (0.625, 1.150), (0.614, 1.158), (0.571, 1.184),
    (0.495, 1.225), (0.452, 1.247), (0.389, 1.275), (0.307, 1.306), (0.226, 1.328), (0.181, 1.337),
    (0.127, 1.346), (0.050, 1.354), (0.005, 1.356), (-0.151, 1.355), (-0.212, 1.353), (-0.273, 1.346),
    (-0.320, 1.344), (-0.400, 1.335), (-0.477, 1.325), (-0.487, 1.322), (-0.505, 1.314), (-0.531, 1.316),
    (-0.620, 1.302), (-0.763, 1.275), (-0.848, 1.258), (-0.991, 1.225), (-1.047, 1.210), (-1.070, 1.197),
    (-1.091, 1.198), (-1.091, 1.188), (-1.082, 1.184), (-1.047, 1.157), (-1.040, 1.155), (-1.017, 1.152),
    (-0.968, 1.136), (-0.898, 1.119), (-0.822, 1.105), (-0.781, 1.102), (-0.724, 1.094), (-0.656, 1.081),
    (-0.588, 1.070), (-0.526, 1.063), (-0.500, 1.062), (-0.493, 1.063), (-0.479, 1.070), (-0.472, 1.071),
    (-0.465, 1.069), (-0.448, 1.058), (-0.436, 1.055), (-0.429, 1.057), (-0.417, 1.065), (-0.411, 1.067),
    (-0.406, 1.065), (-0.390, 1.053), (-0.376, 1.049), (-0.238, 1.038), (-0.188, 1.032), (-0.142, 1.030),
    (-0.097, 1.024), (-0.053, 1.022), (0.093, 1.008), (0.139, 1.005), (0.189, 0.999), (0.296, 0.992),
    (0.343, 0.986), (0.388, 0.983), (0.435, 0.978), (0.521, 0.971), (0.565, 0.970), (0.582, 0.967),
    (0.601, 0.966), (0.626, 0.961), (0.692, 0.956), (0.720, 0.957), (0.814, 0.946), (0.853, 0.945),
    (0.870, 0.943),
))

# ---- section knots along y (nose -> tail), fitted on 01 front / rear and 02 / 03 (REPORT.md)
KY = np.array([2.14, 1.95, 1.70, 1.45, 1.10, 0.75, 0.35, -0.05, -0.45, -0.85, -1.15, -1.45, -1.75, -2.00, -2.14])
SECTION = dict(
    zw=np.array([0.460, 0.500, 0.700, 0.780, 0.600, 0.570, 0.580, 0.590, 0.600, 0.620, 0.640, 0.660, 0.680, 0.700,
                 0.700]),     # height of the widest point (above the front arch at the axle: the 1,754 is there)
    alo=np.array([0.180, 0.170, 0.180, 0.200, 0.130, 0.090, 0.090, 0.090, 0.090, 0.070, 0.040, 0.030, 0.030, 0.040,
                  0.050]),    # tuck under at the bottom (metres in)
    plo=np.full(15, 2.2),     # its power
    b=np.array([0.300, 0.260, 0.100, 0.060, 0.050, 0.060, 0.080, 0.080, 0.060, 0.030, 0.020, 0.020, 0.020, 0.030,
                0.040]),      # inward slope from the widest point up to the shoulder
    zs=np.array([0.720, 0.740, 0.800, 0.900, 0.970, 0.980, 0.990, 1.000, 1.000, 1.010, 1.020, 1.020, 1.010, 1.000,
                 0.990]),     # shoulder (belt) height
    g=np.array([0.000, 0.000, 0.000, 0.000, 0.030, 0.090, 0.100, 0.100, 0.100, 0.090, 0.060, 0.030, 0.020, 0.020,
                0.020]),      # step in at the shoulder
    t=np.array([1.300, 1.300, 1.100, 0.800, 0.550, 0.400, 0.320, 0.300, 0.330, 0.420, 0.600, 0.800, 0.950, 1.050,
                1.050]),      # tumblehome above the shoulder
    crown=np.array([0.040, 0.080, 0.090, 0.085, 0.090, 0.100, 0.100, 0.100, 0.100, 0.100, 0.100, 0.100, 0.090,
                    0.080, 0.060]),   # hood / roof / deck crown at the plan edge
    k=np.array([0.030, 0.030, 0.030, 0.030, 0.030, 0.025, 0.025, 0.025, 0.025, 0.020, 0.015, 0.012, 0.012, 0.012,
                0.012]),      # edge rounding
)
# wheel houses (01: the arch openings 241 / 257 px about the hubs), inner wall, lip rounding
ARCH = dict(front=dict(R=0.421, x_in=0.50, lip=0.012), rear=dict(R=0.448, x_in=0.50, lip=0.012))
# front lower intake (01 front: the black trapezoid below the plate), recessed
INTAKE = dict(x=0.60, z=(0.295, 0.360), y=1.95, depth=0.015)   # above the splitter lip (the length is at its tip)

GRID = dict(y=(-2.20, 2.20), z=(-0.02, 1.46), half=0.92)
SIDE_H = 0.004                       # the side profile's distance grid (metres)
CELL = 0.0065                        # surface nets cell

# ---- regions and panels (metres; side features off 01 side, front / rear ones off 01 front / rear through the
# fitted cameras and the side view's heights at the nose and tail, REPORT.md)
MATS = ("Paint", "Glass", "Trim", "Liner", "HeadLight", "TailLight")
PANELS = ("Body", "DoorFrontLeft", "DoorFrontRight", "TrunkDoor", "EngineDoor", "ChargePortDoor")
SILL = (0.3425, -0.0407)             # black sill top z = a + b * y (between the arches)
SIDE_BLACK = ((2.141, 0.50), (2.10, 0.38), (2.07, 0.32), (1.90, 0.306), (1.84, 0.305), (-1.70, 0.505),
              (-1.78, 0.507), (-2.09, 0.556), (-2.141, 0.56))       # nose / tail ends (the sill: SILL)
FRONT_BLACK = (0.366, 0.305, 0.60, 0.68)   # intake top z, corners z, |x| where the step starts and ends
REAR_BLACK = 0.500                   # bumper top on the tail
LIGHT_BAR = (0.630, 0.070, 0.75, 0.008)    # z = a + b (|x| / c)^4, half height
HEAD_LAMP = (0.50, 0.045)            # lens from |x| and its height under the bar
SIDE_LAMP = ((1.84, 0.700), (1.885, 0.690), (1.99, 0.660), (2.06, 0.655), (2.141, 0.650))   # its top, side view
SPOILER = (0.866, 0.935)             # black duck lip on the tail
TAIL_LAMP = (0.515, 0.551, 0.33)     # bar z range (from the step above the bumper lip), |x| from (black middle)
WINDSHIELD = dict(cowl=(1.064, 0.21), top=(0.324, 0.40), side=((0.21, 0.540), (0.97, 0.672)), z=0.92)
DIVIDER = ((-0.508, 1.319), (-0.455, 1.066))      # door glass rear edge (01 side)
DOOR = ((0.924, 0.932), (1.012, 0.828), (1.082, 0.744), (1.152, 0.668))   # front seam down to the arch
B_SEAM = ((-0.530, 1.062), (-0.274, 0.342))       # door rear seam below the belt
TRUNK_Y = -0.845                     # tailgate front seam across the roof (01 side: the roof's step)
TRUNK_PLAN = ((-0.845, 0.600), (-1.10, 0.545), (-1.29, 0.505), (-1.50, 0.470), (-1.70, 0.440), (-1.87, 0.450),
              (-2.00, 0.510), (-2.05, 0.555), (-2.20, 0.600))   # (y, |x|) its side seam on the deck: 03 / 04 traced,
                                                                # ray-cast onto the body through the fitted cameras
TRUNK_REAR = (0.60, 0.551)           # its lower part on the tail: |x| inside (04), z above the tail lamps
HOOD_SEAM = ((0.96, 0.796), (1.03, 0.778), (1.265, 0.723), (1.61, 0.651), (1.74, 0.616), (1.84, 0.587),
             (1.89, 0.566), (2.20, 0.566))       # (y, |x|) top view, 01 front through its camera
PORT = (-0.780, -0.670, 0.350, 0.460)            # charge port door (x0, x1, z0, z1), 01 rear / 07: driver side
FENDER_CAM = ((1.230, 0.768), (1.126, 0.794), (1.178, 0.741), 0.018)   # tip, rear top, rear bottom, height
BUTTON = (-0.490, 1.071, 0.030, 0.012)          # B pillar button (y, z, length, height), 01 side + rider guide p.5


def smax(a, b, k):
    """Smooth maximum (polynomial), rounding radius about k."""
    k = np.maximum(k, 1e-6)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return a + (b - a) * h + k * h * (1.0 - h)


def ss(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def poly_sdf(poly, py, pz, chunk=20000):
    """Signed distance (inside negative) of points (py, pz) to the closed polygon poly (N x 2)."""
    a = np.asarray(poly, float)
    b = np.roll(a, -1, axis=0)
    ab = b - a
    ll = np.maximum((ab ** 2).sum(1), 1e-12)
    den = np.where(ab[:, 1] == 0, 1e-12, ab[:, 1])
    out = np.empty(len(py))
    for s in range(0, len(py), chunk):
        p = np.stack([py[s:s + chunk], pz[s:s + chunk]], 1)
        ap = p[:, None, :] - a[None]
        t = np.clip((ap * ab[None]).sum(2) / ll[None], 0, 1)
        d2 = ((ap - t[..., None] * ab[None]) ** 2).sum(2).min(1)
        cond = (a[None, :, 1] > p[:, None, 1]) != (b[None, :, 1] > p[:, None, 1])
        xint = a[None, :, 0] + (p[:, None, 1] - a[None, :, 1]) * ab[None, :, 0] / den[None]
        inside = ((cond & (p[:, None, 0] < xint)).sum(1) % 2) == 1
        out[s:s + chunk] = np.where(inside, -1, 1) * np.sqrt(d2)
    return out


def interp_tab(tab, x):
    tab = np.asarray(tab, float)
    o = np.argsort(tab[:, 0])
    return np.interp(x, tab[o, 0], tab[o, 1])


class Field:
    """The body's SDF (built once: the side profile's distance grid)."""

    def __init__(self):
        poly = np.concatenate([SIDE_TOP, SIDE_BOT[::-1]])
        self.y0, self.z0 = GRID["y"][0] - 0.1, GRID["z"][0] - 0.1
        ny = int((GRID["y"][1] - GRID["y"][0] + 0.2) / SIDE_H) + 1
        nz = int((GRID["z"][1] - GRID["z"][0] + 0.2) / SIDE_H) + 1
        yy, zz = np.meshgrid(self.y0 + np.arange(ny) * SIDE_H, self.z0 + np.arange(nz) * SIDE_H, indexing="ij")
        self.side = poly_sdf(poly, yy.ravel(), zz.ravel()).reshape(ny, nz)
        gy, gz = np.gradient(self.side, SIDE_H)
        n = np.maximum(np.hypot(gy, gz), 1e-9)
        self.gz = gz / n

    def samp(self, g, y, z):
        fy = np.clip((y - self.y0) / SIDE_H, 0, g.shape[0] - 1.001)
        fz = np.clip((z - self.z0) / SIDE_H, 0, g.shape[1] - 1.001)
        i, j = fy.astype(int), fz.astype(int)
        ty, tz = fy - i, fz - j
        return (g[i, j] * (1 - ty) * (1 - tz) + g[i + 1, j] * ty * (1 - tz) + g[i, j + 1] * (1 - ty) * tz
                + g[i + 1, j + 1] * ty * tz)

    @staticmethod
    def knot(name, y):
        return np.interp(-y, -KY, SECTION[name])

    @staticmethod
    def plan(y):
        return np.interp(y, PLAN[:, 0], PLAN[:, 1], left=0.0, right=0.0)

    def hw(self, y, z, w):
        zw, alo, plo, b = (self.knot(k, y) for k in ("zw", "alo", "plo", "b"))
        zs, g, t = (self.knot(k, y) for k in ("zs", "g", "t"))
        lo = alo * np.clip((zw - z) / np.maximum(zw - 0.10, 0.05), 0, 2) ** plo
        up = (b * np.maximum(z - zw, 0) + g * ss((z - zs) / 0.06 + 0.5)
              + t * 0.02 * np.logaddexp(0, (z - zs) / 0.02))
        return w - np.where(z < zw, lo, up)

    def well(self, x, y, z):
        """Wheel houses (negative inside the carved volume)."""
        d = np.full(len(x), 1e3)
        for nm, a in ARCH.items():
            ty = TYRES[nm]
            dc = np.hypot(y - ty["y"], z - ty["r"]) - a["R"]
            d = np.minimum(d, smax(dc, a["x_in"] - x, 0.02))
        return d

    def __call__(self, p):
        x, y, z = np.abs(p[:, 0]), p[:, 1], p[:, 2]
        ds = self.samp(self.side, y, z)
        nz = self.samp(self.gz, y, z)
        w = self.plan(y)
        tx = np.clip(x / np.maximum(w, 1e-3), 0, 1.2)
        d1 = ds + self.knot("crown", y) * tx ** 2 * np.maximum(nz, 0)
        d2 = x - self.hw(y, z, w)
        d = smax(d1, d2, self.knot("k", y))
        for nm, a in ARCH.items():
            ty = TYRES[nm]
            dc = np.hypot(y - ty["y"], z - ty["r"]) - a["R"]
            d = smax(d, -smax(dc, a["x_in"] - x, 0.02), a["lip"])
        it = INTAKE
        m = (ss((it["x"] - x) / 0.012) * ss((z - it["z"][0]) / 0.010) * ss((it["z"][1] - z) / 0.010)
             * ss((y - it["y"]) / 0.04))
        return d + it["depth"] * m


def surface_nets(fn, h, bounds):
    """Quads of the zero level of fn on a grid of cell h over bounds ((x0, x1), (y0, y1), (z0, z1)).
    Returns vertices (N x 3) and quads (M x 4, counter-clockwise seen from outside)."""
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
    """Pull points onto the zero level (Newton steps along the numerical gradient). A point that would move
    further than cap stays: that jump lands on the far side of a thin part (the tail lip) and folds the mesh."""
    p = v
    for _ in range(steps):
        d = fn(p)
        g = np.stack([(fn(p + e) - fn(p - e)) / (2 * eps) for e in np.eye(3) * eps], 1)
        p = p - (d / np.maximum((g ** 2).sum(1), 1e-12))[:, None] * g
    return np.where((np.abs(p - v).max(1) < cap)[:, None], p, v)


def body_mesh(h=CELL, field=None):
    """The body's zero level: field, vertices, triangles (x symmetric: the grid's x nodes straddle 0)."""
    f = field or Field()
    n = int(math.ceil(GRID["half"] / h))
    v, q = surface_nets(f, h, ((-(n - 0.5) * h, (n - 0.5) * h), GRID["y"], GRID["z"]))
    v = project(f, v, cap=0.5 * h)
    t = np.concatenate([q[:, [0, 1, 2]], q[:, [0, 2, 3]]])
    # split each quad along its shorter diagonal (fewer slivers)
    d02 = np.linalg.norm(v[q[:, 0]] - v[q[:, 2]], axis=1)
    d13 = np.linalg.norm(v[q[:, 1]] - v[q[:, 3]], axis=1)
    alt = np.concatenate([q[:, [0, 1, 3]], q[:, [1, 2, 3]]])
    use = np.tile(d13 < d02, 2)
    t[use] = alt[use]
    return f, v, t


# ---- regions
def z_light_bar(x):
    a, b, c, _ = LIGHT_BAR
    return a + b * (np.abs(x) / c) ** 4


def classify(f, v, t):
    """Material and panel index per triangle (MATS / PANELS); glass panes get panel-like ids in `pane`."""
    c = v[t].mean(1)
    n = gradient(f, c)
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    ax = np.abs(x)
    nx, ny, nz = np.abs(n[:, 0]), n[:, 1], n[:, 2]
    side = (nx >= np.maximum(np.abs(ny), 0.25))
    front = ~side & (ny > 0.15) & (y > 0.8)
    rear = ~side & (ny < -0.15) & (y < -1.2)
    mat = np.zeros(len(t), np.int8)
    # glass: side windows, windshield
    in_side = poly_sdf(SIDE_GLASS, y, z) < 0
    yc = WINDSHIELD["cowl"][0] - WINDSHIELD["cowl"][1] * x ** 2
    yt = WINDSHIELD["top"][0] - WINDSHIELD["top"][1] * x ** 2
    (s0y, s0x), (s1y, s1x) = WINDSHIELD["side"]
    xs = s0x + (y - s0y) / (s1y - s0y) * (s1x - s0x)
    ws = (y < yc) & (y > yt) & (ax < xs) & (z > WINDSHIELD["z"]) & (nz > 0.2)
    glass = (in_side & (ax > 0.35) & (nx > 0.2) & (nz < 0.95)) | ws
    mat[glass] = 1
    # black: lower body, nose / tail ends, rear spoiler and lamp recess, underbody
    zs = np.where((y < 1.84) & (y > -1.70), SILL[0] + SILL[1] * y, interp_tab(SIDE_BLACK, y))
    a0, a1, x0, x1 = FRONT_BLACK
    zf = a0 + (a1 - a0) * ss((ax - x0) / (x1 - x0))
    wsum = nx + np.maximum(ny, 0) * (y > 1.5) + np.maximum(-ny, 0) * (y < -1.8) + 1e-6
    zb = (nx * zs + np.maximum(ny, 0) * (y > 1.5) * zf + np.maximum(-ny, 0) * (y < -1.8) * REAR_BLACK) / wsum
    black = (z < zb) | (nz < -0.6) | (z < CLEAR + 0.025)
    spoil = (rear & (z > SPOILER[0]) & (z < SPOILER[1])) | ((y < -2.04) & (z > SPOILER[0]) & (nz > 0.2))
    tl = rear & (z >= TAIL_LAMP[0]) & (z <= TAIL_LAMP[1])
    black |= spoil | (tl & (ax < TAIL_LAMP[2]))
    mat[black] = 2
    mat[tl & (ax >= TAIL_LAMP[2])] = 5
    # head lights: the bar across the nose, the lens under it at the corners, its wrap on the side
    zl = z_light_bar(x)
    bar = front & (np.abs(z - zl) < LIGHT_BAR[3]) & (y > 1.6)
    lens = front & (ax > HEAD_LAMP[0]) & (z < zl) & (z > zl - HEAD_LAMP[1] * ss((ax - HEAD_LAMP[0]) / 0.10))
    ztop = interp_tab(SIDE_LAMP, y)
    wrap = side & (y > SIDE_LAMP[0][0]) & (z < ztop) & (z > ztop - HEAD_LAMP[1])
    mat[(lens | wrap) & (y > 1.6)] = 2           # the lamp units read dark (01 front, 02); the bar is the light
    mat[bar] = 4
    # wheel house liner
    liner = (f.well(ax, y, z) < 0.004) & (ax < f.plan(y) - 0.006)
    mat[liner] = 3
    # panels
    pan = np.zeros(len(t), np.int8)
    gy, gz = SIDE_GLASS.T
    belt = (gz < 1.10) & (gy > DIVIDER[1][0]) & (gy < DOOR[0][0])   # glass bottom edge, overlapped 2 cm
    bo = np.argsort(gy[belt])
    door_body = np.concatenate([np.array(DOOR), [[TYRES["front"]["y"] - 0.30, 0.40]],
                                [[TYRES["front"]["y"] - 0.43, SILL[0] + SILL[1] * (TYRES["front"]["y"] - 0.43)]],
                                [[B_SEAM[1][0], SILL[0] + SILL[1] * B_SEAM[1][0]]], [B_SEAM[1]], [B_SEAM[0]],
                                [DIVIDER[1]], np.stack([gy[belt][bo], gz[belt][bo] + 0.02], 1)])
    in_db = (poly_sdf(door_body, y, z) < 0) & (f.well(ax, y, z) > 0.006) & (z > zs)
    (dy0, dz0), (dy1, dz1) = DIVIDER
    ydiv = dy0 + (z - dz0) / (dz1 - dz0) * (dy1 - dy0)
    in_dg = in_side & (y > ydiv)
    door = (in_db | in_dg) & (ax > 0.35) & (mat != 3)
    pan[door] = np.where(x[door] < 0, 1, 2)
    tg = (y < TRUNK_Y) & (ax < interp_tab(TRUNK_PLAN, y)) & (nz > 0.25)
    tg |= rear & (ax < TRUNK_REAR[0]) & (z > TRUNK_REAR[1]) & (y < -1.95)
    pan[tg & (mat != 3) & (mat != 1)] = 3
    xh = interp_tab(HOOD_SEAM, y)
    hood = (y > yc) & (ax < xh) & (z > zl + LIGHT_BAR[3]) & ~side
    pan[hood & (mat == 0)] = 4
    p0, p1, q0, q1 = PORT
    port = rear & (x > p0) & (x < p1) & (z > q0) & (z < q1)
    pan[port] = 5
    mat[port] = 2
    # glass panes: windshield 0, door glass 1 (left) / 2 (right), quarter glass 3 / 4
    pane = np.full(len(t), -1, np.int8)
    pane[glass & ws] = 0
    sg = glass & ~ws
    pane[sg & in_dg] = np.where(x[sg & in_dg] < 0, 1, 2)
    pane[sg & ~in_dg] = np.where(x[sg & ~in_dg] < 0, 3, 4)
    return mat, pan, pane


def edge_faces(t):
    """Undirected edges (E x 2, sorted) and, per edge, its first and second triangle (-1 if open)."""
    e = np.concatenate([t[:, [0, 1]], t[:, [1, 2]], t[:, [2, 0]]])
    f = np.tile(np.arange(len(t)), 3)
    e.sort(1)
    key = e[:, 0].astype(np.int64) * (int(t.max()) + 1) + e[:, 1]
    o = np.argsort(key, kind="stable")
    key, e, f = key[o], e[o], f[o]
    first = np.r_[True, key[1:] != key[:-1]]
    ids = np.cumsum(first) - 1
    ue = e[first]
    fa = np.full(len(ue), -1)
    fb = np.full(len(ue), -1)
    fa[ids[first]] = f[first]
    sec = ~first
    fb[ids[sec]] = f[sec]
    return ue, fa, fb


def smooth_outlines(f, v, t, label, h=CELL, iters=24, lam=0.5, mu=-0.53):
    """The outlines between differently labelled triangles: Taubin-smoothed along themselves (junctions held),
    pulled back onto the surface each step, each vertex kept within 0.4 cell of where it started (further, it
    passes its neighbours and the mesh folds); one ring of neighbours relaxed after."""
    ue, fa, fb = edge_faces(t)
    b = (fb >= 0) & (label[fa] != label[np.maximum(fb, 0)])
    be = ue[b]
    nb = np.bincount(be.ravel(), minlength=len(v))
    chain = nb == 2
    near = nb > 2                                 # junctions and two rings round them stay (they tangle there)
    for _ in range(2):
        near[t[np.isin(t, np.nonzero(near)[0]).any(1)].ravel()] = True
    chain &= ~near
    v0 = v[chain].copy()
    for it in range(iters):
        for k in (lam, mu):
            s = np.zeros_like(v)
            np.add.at(s, be[:, 0], v[be[:, 1]])
            np.add.at(s, be[:, 1], v[be[:, 0]])
            move = chain.copy()
            avg = s[move] / 2.0
            v[move] += k * (avg - v[move])
        p = project(f, v[chain], steps=2)
        d = p - v0
        v[chain] = v0 + d * np.minimum(1, 0.2 * h / np.maximum(np.linalg.norm(d, axis=1), 1e-12))[:, None]
    # relax two rings of triangles next to the outlines (interior vertices only): untangles them
    ring = nb > 0
    for _ in range(2):
        ring[t[np.isin(t, np.nonzero(ring)[0]).any(1)].ravel()] = True
    ring &= nb == 0
    e = np.concatenate([t[:, [0, 1]], t[:, [1, 2]], t[:, [2, 0]]])
    for _ in range(12):
        s = np.zeros_like(v)
        cnt = np.zeros(len(v))
        np.add.at(s, e[:, 0], v[e[:, 1]])
        np.add.at(cnt, e[:, 0], 1)
        np.add.at(s, e[:, 1], v[e[:, 0]])
        np.add.at(cnt, e[:, 1], 1)
        v[ring] += 0.5 * (s[ring] / cnt[ring, None] - v[ring])
        v[ring] = project(f, v[ring], steps=2)
    return v, be


# ---- small parts (on the car's left; mirrored)
def side_point(f, y, z, x0=-1.2):
    """The left side surface at (y, z): x by bisection, and its normal."""
    lo, hi = np.full(np.shape(y), x0), np.zeros(np.shape(y))
    for _ in range(40):
        mid = (lo + hi) / 2
        ins = f(np.stack([mid, y, z], -1).reshape(-1, 3)).reshape(np.shape(y)) < 0
        hi = np.where(ins, mid, hi)
        lo = np.where(ins, lo, mid)
    p = np.stack([hi, y, z], -1).reshape(-1, 3)
    return p, gradient(f, p)


def fender_camera(f):
    """A wedge on the front fender behind the arch pointing back, its rear face the dark lens (01 side, 02)."""
    tip, top, bot, hgt = FENDER_CAM
    ys, zs = np.array([tip[0], top[0], bot[0]]), np.array([tip[1], top[1], bot[1]])
    p, n = side_point(f, ys, zs)
    up = p[1:] + n[1:] * hgt
    v = np.concatenate([p, up])             # 0 tip, 1 top, 2 bottom, 3 top out, 4 bottom out
    shell = np.array([(0, 3, 4), (0, 1, 3), (0, 4, 2)])
    lens = np.array([(1, 2, 4), (1, 4, 3)])
    return v, shell, lens


def button(f):
    """B pillar button: a low rounded pad on the belt behind the door glass (rider guide p.5)."""
    y0, z0, ln, ht = BUTTON
    a = np.linspace(0, 2 * np.pi, 16, endpoint=False)
    ys, zs = y0 + ln / 2 * np.cos(a), z0 + ht / 2 * np.sin(a)
    p, n = side_point(f, ys, zs)
    q = p + n * 0.003
    c, cn = side_point(f, np.array([y0]), np.array([z0]))
    cc = c + cn * 0.0035
    v = np.concatenate([p, q, cc])
    tris = []
    for i in range(16):
        j = (i + 1) % 16
        tris += [(i, j, 16 + j), (i, 16 + j, 16 + i), (16 + i, 16 + j, 32)]
    return v, np.array(tris)


# ---- wheels
def revolve(prof, seg=72):
    """Surface of revolution about the x axis of a polyline [(lateral x, radius), ...]: vertices, quads."""
    prof = np.asarray(prof, float)
    a = np.linspace(0, 2 * np.pi, seg, endpoint=False)
    v = np.concatenate([np.stack([np.full(seg, x), r * np.cos(a), r * np.sin(a)], 1) for x, r in prof])
    q = []
    for i in range(len(prof) - 1):
        for j in range(seg):
            k = (j + 1) % seg
            q.append((i * seg + j, i * seg + k, (i + 1) * seg + k, (i + 1) * seg + j))
    return v, np.array(q)


def tyre_profile(r, w, rim):
    """Half section (lateral from the tyre's middle, radius) from the inner bead round the tread to the outer bead."""
    side = r - rim
    pts = [(-w / 2 + 0.014, rim), (-w / 2 + 0.004, rim + 0.25 * side), (-w / 2, rim + 0.55 * side),
           (-w / 2 + 0.006, rim + 0.80 * side), (-w / 2 + 0.020, r - 0.006), (-w / 2 + 0.040, r)]
    return pts + [(-x, rr) for x, rr in pts[::-1]]


def wheel_parts(seg=72):
    """{name: (vertices, triangles)}: Tyre_<FL|FR|RL|RR> and Cover_<...> in place (the car frame)."""
    out = {}
    for axle, tag in (("front", "F"), ("rear", "R")):
        ty = TYRES[axle]
        r, w, rim, xc, rc = ty["r"], ty["w"], ty["rim"], WHEEL_X[axle], COVER_R[axle]
        mid = xc - 0.004 - w / 2                      # sidewall bulge 4 mm inboard of the cover face
        tv, tq = revolve(tyre_profile(r, w, rim), seg)
        # nearly flat cover (its rim 2 mm behind the face: proud of the sidewall, 02's gold disc) with a low step
        # ring and a small hub dome (02: the inner disc and the centre bump)
        cprof = [(0.006, rc - 0.008), (0.011, rc), (0.013, rc - 0.004), (0.013, 0.80 * rc), (0.014, 0.79 * rc),
                 (0.014, 0.16 * rc), (0.020, 0.13 * rc), (0.026, 0.07 * rc), (0.028, 0.0005)]
        cv, cq = revolve(cprof, seg)
        cv[:, 0] += xc - mid - 0.014                  # the cover face at WHEEL_X
        for lr, sx in (("L", -1), ("R", 1)):
            for nm, (vv, qq) in (("Tyre", (tv, tq)), ("Cover", (cv, cq))):
                p = vv.copy()
                p[:, 0] = sx * (mid + p[:, 0])
                p[:, 1] += ty["y"]
                p[:, 2] += ty["r"]
                tt = np.concatenate([qq[:, [0, 1, 2]], qq[:, [0, 2, 3]]])
                if sx < 0:
                    tt = tt[:, ::-1]
                out[f"{nm}_{tag}{lr}"] = (p, tt)
    return out


# ---- seams for the build (metres, the car's left; mirror x for the right)
def lines(f):
    """Panel seams and the charge port as points on the surface."""
    out = {}
    # door: front seam, round the arch to the sill, sill, rear seam, belt jog, divider, glass top, A pillar
    fy, fz = np.array(DOOR).T
    ty = TYRES["front"]
    a0 = math.atan2(fz[-1] - ty["r"], fy[-1] - ty["y"])
    a1 = math.atan2(SILL[0] + SILL[1] * (ty["y"] - 0.43) - ty["r"], 0.43)
    aa = np.linspace(a0, a1, 12)
    R = ARCH["front"]["R"] + 0.004
    ay, az = ty["y"] + R * np.cos(aa), ty["r"] + R * np.sin(aa)
    sy = np.linspace(ay[-1], B_SEAM[1][0], 20)
    sz = SILL[0] + SILL[1] * sy
    gy, gz = SIDE_GLASS.T
    (dy0, dz0), (dy1, dz1) = DIVIDER
    top = (gz > 1.15) & (gy > dy0 - 0.01)
    ty_, tz_ = gy[top][::-1], gz[top][::-1]
    yy = np.concatenate([fy, ay[1:], sy[1:], [B_SEAM[0][0]], [dy1, dy0], ty_, gy[:6][::-1], [fy[0]]])
    zz = np.concatenate([fz, az[1:], sz[1:], [B_SEAM[0][1]], [dz1, dz0], tz_, gz[:6][::-1], [fz[0]]])
    p, _ = side_point(f, yy, zz)
    out["door_left"] = p.round(4).tolist()
    # tailgate: roof seam across, down the side line, round the tail above the lamps
    sy = np.linspace(TRUNK_Y, -2.08, 30)
    p = top_point(f, -interp_tab(TRUNK_PLAN, sy), sy)
    xs = np.linspace(p[0, 0], -p[0, 0], 21)
    roof = top_point(f, xs, np.full_like(xs, TRUNK_Y))
    zt = SPOILER[1] - 0.005
    rearp = rear_point(f, np.array([-TRUNK_REAR[0], -TRUNK_REAR[0], TRUNK_REAR[0], TRUNK_REAR[0]]),
                       np.array([zt, TRUNK_REAR[1], TRUNK_REAR[1], zt]))
    out["trunk_roof_seam"] = roof.round(4).tolist()
    out["trunk_side_left"] = p.round(4).tolist()
    out["trunk_rear"] = rearp.round(4).tolist()
    # hood seams (left), cowl
    hy = np.linspace(HOOD_SEAM[0][0], 1.89, 14)
    hx = -interp_tab(HOOD_SEAM, hy)
    out["hood_seam_left"] = top_point(f, hx, hy).round(4).tolist()
    # charge port door
    x0, x1, z0, z1 = PORT
    out["charge_port"] = rear_point(f, np.array([x0, x1, x1, x0]), np.array([z0, z0, z1, z1])).round(4).tolist()
    cp = rear_point(f, np.array([(x0 + x1) / 2]), np.array([(z0 + z1) / 2]))[0]
    out["charge_port_centre"] = cp.round(4).tolist()
    for k in [k for k in out if k.endswith("_left")]:
        out[k[:-5] + "_right"] = [[-p[0], p[1], p[2]] for p in out[k]]
    return out


def top_point(f, x, y, z0=1.6, step=0.004):
    """The first surface from above at (x, y): march down, then bisect."""
    zs = np.arange(z0, 0.0, -step)
    ins = np.stack([f(np.stack([x, y, np.full_like(x, zz)], -1)) < 0 for zz in zs], 1)
    k = np.argmax(ins, 1)
    lo, hi = zs[k] + step, zs[k]                  # outside, inside
    for _ in range(20):
        mid = (lo + hi) / 2
        i = f(np.stack([x, y, mid], -1)) < 0
        hi = np.where(i, mid, hi)
        lo = np.where(i, lo, mid)
    return np.stack([x, y, hi], -1)


def rear_point(f, x, z, y0=-2.3, step=0.004):
    """The first surface from behind at (x, z): march forward, then bisect."""
    ys = np.arange(y0, 0.0, step)
    ins = np.stack([f(np.stack([x, np.full_like(x, yy), z], -1)) < 0 for yy in ys], 1)
    k = np.argmax(ins, 1)
    lo, hi = ys[k] - step, ys[k]
    for _ in range(20):
        mid = (lo + hi) / 2
        i = f(np.stack([x, mid, z], -1)) < 0
        hi = np.where(i, mid, hi)
        lo = np.where(i, lo, mid)
    return np.stack([x, hi, z], -1)


def build(h=CELL):
    """Everything numpy: {'field', 'v', 't', 'mat', 'pan', 'pane', 'normals', 'parts', 'wheels', 'lines'}."""
    f, v, t = body_mesh(h)
    mat, pan, pane = classify(f, v, t)
    label = mat.astype(np.int32) * 64 + pan.astype(np.int32) * 8 + (pane.astype(np.int32) + 1)
    v, be = smooth_outlines(f, v, t, label, h)
    # (labels kept: the smoothed outlines run between exactly these faces)
    cam_v, cam_s, cam_l = fender_camera(f)
    btn_v, btn_t = button(f)
    return dict(field=f, v=v, t=t, mat=mat, pan=pan, pane=pane, normals=gradient(f, v),
                parts=dict(camera=(cam_v, cam_s, cam_l), button=(btn_v, btn_t)), wheels=wheel_parts(),
                lines=lines(f))


# ---- Blender
COLORS = dict(Paint=((0.55, 0.37, 0.14), 0.2, 0.45), Glass=((0.05, 0.06, 0.07), 0.0, 0.05),   # satin gold
              Trim=((0.035, 0.035, 0.038), 0.0, 0.55), Liner=((0.015, 0.015, 0.016), 0.0, 0.85),
              HeadLight=((0.92, 0.94, 0.96), 0.0, 0.15), TailLight=((0.55, 0.05, 0.06), 0.0, 0.2),
              Tyre=((0.02, 0.02, 0.022), 0.0, 0.8), Cover=((0.55, 0.37, 0.14), 0.2, 0.45))
TARGET = 145000          # body triangles after decimation (both halves together)
PANES = ("Glass_Windshield", "Glass_DoorLeft", "Glass_DoorRight", "Glass_QuarterLeft", "Glass_QuarterRight")


def main():
    import bmesh
    import bpy

    out = (sys.argv[sys.argv.index("--") + 1:] + [OUT_DIR])[0] if "--" in sys.argv else OUT_DIR
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    B = build()
    f, v, t = B["field"], B["v"], B["t"]
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

    def make(name, vv, tt, mat, panel=None, normals=None):
        """An object of the triangles tt (indices into vv), one material; normals: per-corner custom normals."""
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
        me.validate()
        for m in np.atleast_1d(mat):
            me.materials.append(mats[m])
        if panel is not None:
            me.attributes.new("panel", "INT", "FACE").data.foreach_set("value", np.asarray(panel, np.int32))
        if normals is not None:
            me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set(
                "vector", normals.astype(np.float32).ravel())
        me.polygons.foreach_set("use_smooth", np.ones(len(tt), bool))
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob

    def read(ob):
        """Triangles of an object: vertices, triangles, per-face label."""
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.to_mesh(ob.data)
        bm.free()
        me = ob.data
        co = np.empty(len(me.vertices) * 3, np.float32)
        me.vertices.foreach_get("co", co)
        lv = np.empty(len(me.loops), np.int32)
        me.loops.foreach_get("vertex_index", lv)
        lab = np.empty(len(me.polygons), np.int32)
        me.attributes["label"].data.foreach_get("value", lab)
        return co.reshape(-1, 3).astype(float), lv.reshape(-1, 3), lab

    def apply(ob, mod):
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)

    # one body mesh, the left half: decimated with every outline held, mirrored (exactly symmetric, no cracks
    # between materials), pulled back onto the field, then split one object per material (glass per pane)
    label = B["mat"].astype(np.int32) * 64 + B["pan"].astype(np.int32) * 8 + (B["pane"].astype(np.int32) + 1)
    body = make("Body", v, t, "Paint")
    body.data.attributes.new("label", "INT", "FACE").data.foreach_set("value", label)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                           plane_co=(0, 0, 0), plane_no=(1, 0, 0), clear_outer=True)
    bm.to_mesh(body.data)
    bm.free()
    hv, ht, hl = read(body)
    ue, fa, fb = edge_faces(ht)
    held = np.zeros(len(hv), bool)
    held[ue[(fb < 0) | (hl[fa] != hl[np.maximum(fb, 0)])].ravel()] = True     # the cut at x = 0, the outlines
    held |= np.abs(hv[:, 1]) > L / 2 - 0.012                                    # the nose and tail tips (length)
    g = body.vertex_groups.new(name="interior")
    g.add([int(i) for i in np.nonzero(~held)[0]], 1.0, "REPLACE")
    m = body.modifiers.new("dec", "DECIMATE")
    m.decimate_type, m.ratio = "COLLAPSE", TARGET / 2 / len(ht)
    m.vertex_group, m.vertex_group_factor = "interior", 1000.0
    apply(body, m)
    m = body.modifiers.new("mir", "MIRROR")
    m.use_axis[0], m.use_mirror_merge, m.merge_threshold, m.use_clip = True, True, 1e-5, True
    apply(body, m)
    v, t, lab = read(body)
    bpy.data.meshes.remove(body.data)
    fn = np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-15)
    gv = gradient(f, v)[t]                                       # field normals per corner ...
    nrm = np.where(((gv * fn[:, None]).sum(2) > 0.3)[..., None], gv, fn[:, None])   # ... faceted on sharp tips
    mat, pan, pane = lab // 64, lab // 8 % 8, lab % 8 - 1
    right = v[t][:, :, 0].mean(1) > 0                            # the mirror copied the left's names
    pan[right & (pan == PANELS.index("DoorFrontLeft"))] = PANELS.index("DoorFrontRight")
    pane[right & (pane == 1)], pane[right & (pane == 3)] = 2, 4
    pan[right & (pan == PANELS.index("ChargePortDoor"))] = PANELS.index("Body")    # one port: driver side
    report = dict(objects={})
    for mi, nm in enumerate(MATS):
        for pi, on in enumerate(PANES if nm == "Glass" else (nm,)):
            sel = (mat == mi) & ((pane == pi) if nm == "Glass" else True)
            if sel.any():
                make(on, v, t[sel], nm, panel=pan[sel], normals=nrm[sel])
    # small parts: fender camera housings (paint) and lenses, B pillar buttons (trim)
    cv, cs, cl = B["parts"]["camera"]
    bv, bt = B["parts"]["button"]
    for sx, side in ((-1, "Left"), (1, "Right")):
        p = cv * [sx, 1, 1]
        flip = (lambda a: a[:, ::-1]) if sx > 0 else (lambda a: a)
        make(f"FenderCam_{side}", p, flip(cs), "Paint")
        make(f"FenderCamLens_{side}", p, flip(cl), "Trim")
        make(f"Button_{side}", bv * [sx, 1, 1], flip(bt), "Trim")
    for nm, (vv, tt) in B["wheels"].items():
        ob = make(nm, vv, tt, "Tyre" if nm.startswith("Tyre") else "Cover")
        ob.data.polygons.foreach_set("use_smooth", np.ones(len(ob.data.polygons), bool))
    for ob in bpy.context.scene.objects:
        me = ob.data
        report["objects"][ob.name] = len(me.polygons)
    allv = np.concatenate([np.array([tuple(ob.matrix_world @ vv.co) for vv in ob.data.vertices])
                           for ob in bpy.context.scene.objects
                           if not ob.name.startswith(("Tyre", "Cover"))])
    report["body_bbox"] = [allv.min(0).round(4).tolist(), allv.max(0).round(4).tolist()]
    report["body_tris"] = int(sum(n for k, n in report["objects"].items() if not k.startswith(("Tyre", "Cover"))))
    report["panels"] = PANELS
    json.dump(report, open(os.path.join(out, "prep_report.json"), "w"), indent=1)
    json.dump(dict(frame="metres, +Y front, +Z up, -X the car's left, ground 0 (prep_cybercab.py)",
                   **B["lines"]), open(os.path.join(out, "cybercab_lines.json"), "w"), indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "cybercab_src.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "cybercab_src.glb"), export_format="GLB")
    print("PREP", report["body_tris"], "body triangles; bbox", report["body_bbox"])


if __name__ == "__main__":
    main()
