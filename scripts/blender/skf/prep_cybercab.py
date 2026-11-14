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
    (2.1235, 0.3063), (2.1205, 0.5611), (2.1194, 0.5755), (2.1120, 0.5950),
    (2.1000, 0.6200), (2.0860, 0.6400), (2.0738, 0.6440),   # sharp leading edge, the light bar under it (02)
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
    zw=np.array([0.550, 0.550, 0.700, 0.780, 0.600, 0.570, 0.580, 0.590, 0.600, 0.620, 0.640, 0.660, 0.680, 0.700,
                 0.700]),     # height of the widest point (above the front arch at the axle: the 1,754 is there)
    alo=np.array([0.040, 0.050, 0.180, 0.200, 0.130, 0.090, 0.090, 0.090, 0.090, 0.070, 0.040, 0.030, 0.030, 0.040,
                  0.050]),    # tuck under at the bottom (metres in; the nose's bumper face near vertical, 02)
    plo=np.full(15, 2.2),     # its power
    b=np.array([0.150, 0.150, 0.100, 0.060, 0.050, 0.060, 0.080, 0.080, 0.060, 0.030, 0.020, 0.020, 0.020, 0.030,
                0.040]),      # inward slope from the widest point up to the shoulder
    zs=np.array([0.720, 0.740, 0.800, 0.900, 0.970, 0.980, 0.990, 1.000, 1.000, 1.010, 1.020, 1.020, 1.010, 1.000,
                 0.990]),     # shoulder (belt) height
    g=np.array([0.000, 0.000, 0.000, 0.000, 0.030, 0.090, 0.100, 0.100, 0.100, 0.090, 0.060, 0.030, 0.020, 0.020,
                0.020]),      # step in at the shoulder
    t=np.array([1.300, 1.300, 1.100, 0.800, 0.550, 0.400, 0.320, 0.300, 0.330, 0.420, 0.600, 0.800, 0.950, 1.050,
                1.050]),      # tumblehome above the shoulder
    crown=np.array([0.000, 0.000, 0.005, 0.012, 0.050, 0.100, 0.100, 0.100, 0.100, 0.100, 0.100, 0.100, 0.090,
                    0.080, 0.060]),   # roof / deck crown at the plan edge (the hood: hood_cap)
    k=np.array([0.008, 0.030, 0.050, 0.055, 0.045, 0.030, 0.025, 0.025, 0.025, 0.020, 0.015, 0.012, 0.012, 0.012,
                0.012]),      # edge rounding (the front fenders roll over into the side: 01 front)
)
# wheel houses (01: the arch openings 241 / 257 px about the hubs), inner wall, lip rounding
ARCH = dict(front=dict(R=0.421, x_in=0.50, lip=0.012), rear=dict(R=0.448, x_in=0.50, lip=0.012))
# front lower intake (01 front, 02: the black trapezoid under the plate, grille inside), recessed: half width at
# its top and bottom, z range, depth
INTAKE = dict(x=(0.62, 0.52), z=(0.292, 0.390), y=1.95, depth=0.035)   # 01 front: grille 0.29-0.39 above the lip

GRID = dict(y=(-2.20, 2.20), z=(-0.02, 1.46), half=0.92)
SIDE_H = 0.004                       # the side profile's distance grid (metres)
CELL = 0.0065                        # surface nets cell

# ---- regions and panels (metres; side features off 01 side, front / rear ones off 01 front / rear through the
# fitted cameras and the side view's heights at the nose and tail, REPORT.md)
MATS = ("Paint", "Glass", "Trim", "Liner", "HeadLight", "TailLight")
PANELS = ("Body", "DoorFrontLeft", "DoorFrontRight", "TrunkDoor", "EngineDoor", "ChargePortDoor")
SILL = (0.3425, -0.0407)             # black sill top z = a + b * y (between the arches)
# perimeter coordinates round the nose and the tail in plan (q): |x| across the face, then xc + r * angle round the
# corner (centre (xc, yc)); every front / rear region below is a function of q and z, so it wraps the corners
NOSE_C = (0.40, 1.80, 0.45)
TAIL_C = (0.50, -1.90, 0.40)
FRONT_BLACK = ((0.0, 0.390), (0.52, 0.390), (0.64, 0.305), (0.80, 0.285), (1.11, 0.268))   # (q, black top z)
REAR_BLACK = ((0.0, 0.512), (0.85, 0.512), (1.13, 0.505))    # rear bumper top by q (01 side: dark below 0.54)
BAR = (0.005, 0.011)                 # light bar: from / to depth under the leading edge (above it a dark shadow line)
HEAD_LAMP = ((0.48, 0.0), (0.62, 0.010), (0.75, 0.022), (0.86, 0.032), (0.95, 0.028), (1.06, 0.0))  # (q, lens depth):
                                     # a slim wedge growing to the corner (01 front, 02)
LAMP_SIDE = ((0.80, 0.0), (0.94, 1.0))   # q over which the lamp's top leaves the hood edge for SIDE_LAMP
SIDE_LAMP = ((1.84, 0.700), (1.885, 0.698), (1.99, 0.690), (2.06, 0.680), (2.141, 0.670))   # its top, side view
SPOILER = dict(z=((0.0, 0.812), (1.13, 0.812)), notch=(0.826, 0.850), set_back=0.030, q_end=0.98,
               bevel=(0.765, 0.30))  # the duck lip's black rear face: straight bottom edge at z across the tail, to
               # q_end (01 rear: full width, gold only at the very corners); the shadow notch under the lip (01 side:
               # the background shows through at 0.82-0.85); the face's top rounds forward from bevel[0] (03)
TAIL_LAMP = ((0.0, 0.546), (1.13, 0.546)), 0.33, 0.006, 0.52   # bar top z by q, |x| of its dark middle, middle
               # recess, |x| where the red starts (inboard of it the clear reversing lens, unlit grey: 07, 03, 01 rear)
TAIL_ROUND = 0.035                   # the tail face sets forward by this (|x| / 0.8)^2: convex in plan (03)
TAIL_CHAMFER = (0.74, 0.79)          # the tail's top corners cut where |x| + z > the sum, under the duck lip (01 rear)
RIDGE = (0.0025, 0.020)              # height, half width of the two shallow roof / deck ridges (01 rear, 03)
RIDGE_X = ((0.25, 0.52), (-0.845, 0.54), (-1.10, 0.49), (-1.50, 0.42), (-1.87, 0.40), (-2.06, 0.42))   # (y, |x|)
WINDSHIELD = dict(cowl=(1.064, 0.21), top=(0.324, 0.40), side=((0.21, 0.540), (0.97, 0.672)), z=0.92)
DIVIDER = ((-0.508, 1.319), (-0.455, 1.066))      # door glass rear edge (01 side)
DOOR = ((0.924, 0.932), (1.012, 0.828), (1.082, 0.744), (1.152, 0.668))   # front seam down to the arch
B_SEAM = ((-0.530, 1.062), (-0.274, 0.342))       # door rear seam below the belt
TRUNK_Y = -0.845                     # tailgate front seam across the roof (01 side: the roof's step)
TRUNK_PLAN = ((-0.845, 0.600), (-1.10, 0.545), (-1.29, 0.505), (-1.50, 0.470), (-1.70, 0.440), (-1.87, 0.450),
              (-2.00, 0.510), (-2.05, 0.555), (-2.20, 0.600))   # (y, |x|) its side seam on the deck: 03 / 04 traced,
                                                                # ray-cast onto the body through the fitted cameras
TRUNK_REAR = (0.60, 0.546)           # its lower part on the tail: |x| inside (04), z above the tail lamps
# hood (01 front through its camera: the seam ridges run from the A pillar base, |x| ~0.70, to the lamps' inner
# ends, |x| ~0.48; the bar's middle sits ~1 cm under the inner ends, the outer ends ~9 cm above): the hood is dished,
# its middle HOOD_DROP under the ridges (the side silhouette), the fenders fall away outboard of the ridge in a full
# convex roll, FENDER_DROP down at FENDER_X (the front view's outline), then the side section
HOOD_SEAM = ((0.96, 0.700), (1.10, 0.690), (1.40, 0.655), (1.70, 0.600), (1.90, 0.545), (2.05, 0.490),
             (2.20, 0.480))          # (y, |x|)
HOOD_DROP = ((1.08, 0.0), (1.25, 0.012), (1.50, 0.022), (1.80, 0.026), (2.00, 0.024), (2.07, 0.010), (2.09, 0.0))
FENDER_DROP = ((1.08, 0.0), (1.22, 0.040), (1.50, 0.045), (1.80, 0.030), (1.95, 0.012), (2.02, 0.0))
FENDER_X, FENDER_LIN = 0.80, 0.35   # |x| where the fender has fallen FENDER_DROP (01 front: at the hood's height
                                     # the outline is at |x| ~0.74); share of the fall that is linear (the crease)
CREASE = 0.015                      # rounding of the hood ridges and the shoulder crease (a few mesh cells)
NOSE_ROUND = 0.06                    # the nose's side profile slides back by this (|x| / 0.8)^2: round face in plan
SHOULDER = ((1.15, 0.790), (0.50, 0.850), (-0.42, 0.915), (-1.40, 0.925), (-2.10, 0.915))   # crease (y, z): 01 side
TUCK = (0.10, 0.012)                 # below the crease the side leans in: slope, at most
PORT = (-0.660, -0.530, 0.360, 0.470)            # charge port door (x0, x1, z0, z1), driver side: 07 (under the
                                                 # left lamp's inner part, by the tailgate's edge), 03 through its camera
DIFFUSER = (0.55, 0.305, 0.345, 0.015)          # rear bumper's lower step: |x|, z range, set in (01 rear, 03, 04)
# seams: the outlines of the doors, tailgate, hood and charge port door as V grooves (GROOVE: half width, depth)
SEAMS = ("door", "cowl", "hood_x", "hood_z", "trunk_y", "trunk_x", "tail_top", "port_x0", "port_x1", "port_z0",
         "port_z1")
GROOVE = (0.0025, 0.0020)
FENDER_CAM = ((1.230, 0.768), (1.126, 0.794), (1.178, 0.741), 0.028)   # tip, rear top, rear bottom, height
PLATE = (0.0, 0.430, 0.590, 0.155)               # plate (x, z0, z1, half width): 01 front, a US plate in its holder
LAMP_DOTS = 8                                    # small lamps in each head lamp lens (01 front, 02)
SIDE_MARKER = (1.885, 1.900, 0.330, 0.500)       # amber reflector strip ahead of the front wheel (y0, y1, z0, z1)
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


def plan_w(y):
    return np.interp(y, PLAN[:, 0], PLAN[:, 1], left=0.0, right=0.0)


def zsil(y):
    """The side silhouette's top over the hood (01 side)."""
    hm = (SIDE_TOP[:, 0] > 0.9) & (SIDE_TOP[:, 0] < 2.09)
    return np.interp(y, SIDE_TOP[hm, 0][::-1], SIDE_TOP[hm, 1][::-1])


def nose_y(ax, y):
    """The nose's side profile slides back with x^2 (where it is read: y + this): a slightly convex bumper face
    and leading edge rounding into the plan's corners (02, 06 top)."""
    return y + NOSE_ROUND * (ax / 0.80) ** 2 * ss((y - 1.97) / 0.06)


def hood_cap(ax, y):
    """Top of the hood and front fenders (z at (|x|, y), 1.08 < y < 2.09): a dished hood, its middle HOOD_DROP under
    the seam ridges at the side silhouette's height (read where nose_y slides it); outboard the fender falls in a
    convex roll, FENDER_DROP at FENDER_X (half as much again further out, where the side section takes over). The
    ridge is a smooth minimum (radius CREASE): a kink off the mesh's edges would shade as a saw tooth."""
    zc, D, xs = zsil(nose_y(ax, y)), interp_tab(HOOD_DROP, y), interp_tab(HOOD_SEAM, y)
    u = np.clip((ax - xs) / np.maximum(FENDER_X - xs, 0.02), -0.5, 1.7)
    fall = interp_tab(FENDER_DROP, y) * (FENDER_LIN * u + (1 - FENDER_LIN) * u ** 2)
    return -smax(-(zc - D * (1 - (ax / xs) ** 2)), -(zc - fall), CREASE)


def wrap_q(ax, y, c, front=True):
    """Perimeter coordinate round the nose (front) or the tail in plan: |x| inboard of the corner centre, then
    xc + r * angle (0 facing ahead / astern, pi/2 on the side)."""
    xc, yc, r = c
    th = np.arctan2(np.maximum(ax - xc, 0.0), np.maximum((y - yc) if front else (yc - y), 1e-4))
    return np.where(ax <= xc, ax, xc + r * th)


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
        self.gy, self.gz = gy / n, gz / n

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

    plan = staticmethod(plan_w)

    def hw(self, y, z, w):
        zw, alo, plo, b = (self.knot(k, y) for k in ("zw", "alo", "plo", "b"))
        zs, g, t = (self.knot(k, y) for k in ("zs", "g", "t"))
        lo = alo * np.clip((zw - z) / np.maximum(zw - 0.10, 0.05), 0, 2) ** plo
        # softplus instead of max(): a kink off the mesh's edges would shade as a saw tooth (02, 01 side)
        up = (b * CREASE * np.logaddexp(0, (z - zw) / CREASE) + g * ss((z - zs) / 0.06 + 0.5)
              + t * 0.02 * np.logaddexp(0, (z - zs) / 0.02))
        # shoulder crease (01 side, 02, 03): from behind the front arch up to the B pillar and along the haunch;
        # below it the side leans in a little
        lean = TUCK[0] * CREASE * np.logaddexp(0, (interp_tab(SHOULDER, y) - z) / CREASE)
        tuck = TUCK[1] * (1 - np.exp(-lean / TUCK[1])) * ss((1.25 - y) / 0.15)
        return w - np.where(z < zw, lo, 0.0) - up - tuck

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
        # the nose rounds in plan (nose_y); the tail face between the duck lip and the bumper ledge comes forward
        # with x^2 the same way (03)
        ys = (nose_y(x, y) - TAIL_ROUND * (x / 0.80) ** 2 * ss((-1.98 - y) / 0.06) * ss((z - 0.53) / 0.03)
              * ss((SPOILER["z"][0][1] + 0.005 - z) / 0.02))
        ds = self.samp(self.side, ys, z)
        nz = self.samp(self.gz, ys, z)
        w = self.plan(y)
        tx = np.clip(x / np.maximum(w, 1e-3), 0, 1.2)
        d1 = ds + self.knot("crown", y) * tx ** 2 * np.maximum(nz, 0)
        # two shallow ridges from the roof down the deck, inboard of the tailgate seams (01 rear, 03)
        rh, rw = RIDGE
        d1 = d1 - (rh * np.exp(-((x - interp_tab(RIDGE_X, y)) / rw) ** 2) * np.maximum(nz, 0)
                   * ss((0.25 - y) / 0.15) * ss((y + 2.05) / 0.04))
        d2 = x - self.hw(y, z, w)
        d = smax(d1, d2, self.knot("k", y))
        # the tail face's top corners cut on the diagonal, under the duck lip (01 rear)
        cx_, cz_ = TAIL_CHAMFER
        off = 2.0 * (1 - ss((-1.99 - y) / 0.04) * ss((SPOILER["z"][0][1] - z) / 0.02))   # away from it: no cut
        d = smax(d, ((x - cx_) + (z - cz_)) / math.sqrt(2) - off, 0.012)
        cap = smax(d, z - hood_cap(x, y), 0.004)
        d = np.where((y > 1.08) & (y < 2.09), cap, d)
        for nm, a in ARCH.items():
            ty = TYRES[nm]
            dc = np.hypot(y - ty["y"], z - ty["r"]) - a["R"]
            d = smax(d, -smax(dc, a["x_in"] - x, 0.02), a["lip"])
        it = INTAKE
        xi = it["x"][1] + (it["x"][0] - it["x"][1]) * np.clip((z - it["z"][0]) / (it["z"][1] - it["z"][0]), 0, 1)
        # depth eased out toward the opening's ends: the bumper corner behind is thin (a full-depth step there
        # meshes non-manifold)
        d = d + it["depth"] * (ss((xi - x) / 0.04) * ss((z - it["z"][0]) / 0.006) * ss((it["z"][1] - z) / 0.006)
                               * ss((y - it["y"]) / 0.04))
        # tail: a shadow notch under the duck lip (in the lip's black face), the tail lamp bar's dark middle set in
        # (01 side, 01 rear, 03)
        qt = wrap_q(x, y, TAIL_C, front=False)
        aft = ss((-2.00 - y) / 0.03) * ss((1.0 - qt) / 0.08)
        zb = interp_tab(SPOILER["z"], qt)
        n0, n1 = zb + np.array(SPOILER["notch"])[:, None] - SPOILER["z"][0][1]
        b0, bs = SPOILER["bevel"]
        d = d + aft * (SPOILER["set_back"] * ss((z - n0) / 0.004) * ss((n1 - z) / 0.004)
                       + bs * CREASE * np.logaddexp(0, (z - b0) / CREASE) * ss((zb + 0.004 - z) / 0.006))
        lt = interp_tab(TAIL_LAMP[0], qt)
        rb = interp_tab(REAR_BLACK, qt)
        dx, dz0, dz1, dd = DIFFUSER
        d = d + dd * (ss((dx - x) / 0.012) * ss((z - dz0) / 0.004) * ss((dz1 - z) / 0.004) * ss((-2.06 - y) / 0.02))
        return d + aft * TAIL_LAMP[2] * (ss((TAIL_LAMP[1] - x) / 0.006) * ss((z - rb) / 0.003)
                                          * ss((lt - z) / 0.003))


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


# ---- regions: every outline is a zero level of a function of position only (no normals), cut into the mesh
# (split_mesh) and tested at the face centres with the same function, so the region edges are the cut curves
def windshield(x, y):
    """Cowl and top edges (y at x) and the side edge (|x| at y)."""
    (s0y, s0x), (s1y, s1x) = WINDSHIELD["side"]
    return (WINDSHIELD["cowl"][0] - WINDSHIELD["cowl"][1] * x ** 2, WINDSHIELD["top"][0] - WINDSHIELD["top"][1] * x ** 2,
            s0x + (y - s0y) / (s1y - s0y) * (s1x - s0x))


def black_top(ax, y):
    """Top of the black lower body: the sill between the arches, FRONT_BLACK round the nose, REAR_BLACK round the
    tail (the blends sit inside the arch openings)."""
    wn, wt = ss((y - 1.80) / 0.08), ss((-1.66 - y) / 0.08)
    return ((SILL[0] + SILL[1] * y) * (1 - wn - wt) + wn * interp_tab(FRONT_BLACK, wrap_q(ax, y, NOSE_C))
            + wt * interp_tab(REAR_BLACK, wrap_q(ax, y, TAIL_C, front=False)))


def lamp_top(ax, y):
    """Top of the head lamp's light bar: just under the hood's leading edge across the nose, SIDE_LAMP on the
    side wrap (01 side, 01 front, 02)."""
    q = wrap_q(ax, y, NOSE_C)
    wq = interp_tab(LAMP_SIDE, q)
    return (1 - wq) * (hood_cap(ax, np.clip(y, 1.09, 2.08)) - BAR[0]) + wq * interp_tab(SIDE_LAMP, y)


def lip_y(ax):
    """The duck lip's rear edge (y): behind it the tail's top reads black (01 rear, 03)."""
    return -2.085 + 0.085 * ss((ax - 0.60) / 0.19)


def door_polygon():
    """The door's outline below the glass (side view (y, z)); its top overlaps the glass by 2 cm."""
    gy, gz = SIDE_GLASS.T
    belt = (gz < 1.10) & (gy > DIVIDER[1][0]) & (gy < DOOR[0][0])
    bo = np.argsort(gy[belt])
    yf = TYRES["front"]["y"]
    return np.concatenate([np.array(DOOR), [[yf - 0.30, 0.40]], [[yf - 0.43, SILL[0] + SILL[1] * (yf - 0.43)]],
                           [[B_SEAM[1][0], SILL[0] + SILL[1] * B_SEAM[1][0]]], [B_SEAM[1]], [B_SEAM[0]],
                           [DIVIDER[1]], np.stack([gy[belt][bo], gz[belt][bo] + 0.02], 1)])


def divider_y(z):
    (dy0, dz0), (dy1, dz1) = DIVIDER
    return dy0 + (z - dz0) / (dz1 - dz0) * (dy1 - dy0)


def levels(f):
    """{name: g(x, y, z, |x|)}: the region outlines (classify() reads the same functions' signs). A plane only
    needed in one place is bent off the body elsewhere (`far`): a cut running the car's length lands next to other
    cuts at a shallow angle and leaves slivers that mesh non-manifold. No two share a zero set (a cut over a cut)."""
    door = door_polygon()
    bw = BAR[1] - BAR[0]
    qn = lambda ax, y: wrap_q(ax, y, NOSE_C)
    qt = lambda ax, y: wrap_q(ax, y, TAIL_C, front=False)
    far = lambda a: 5.0 * np.maximum(a, 0)
    lt = lambda ax, y: lamp_top(ax, y) - far(1.80 - y)              # head lamp levels: only at the nose
    sz = lambda ax, y: interp_tab(SPOILER["z"], qt(ax, y)) - far(y + 1.95)   # tail levels: only at the tail
    return dict(
        glass=lambda x, y, z, ax: poly_sdf(SIDE_GLASS, y, z) + far(0.40 - ax),
        divider=lambda x, y, z, ax: y - divider_y(z),
        cowl=lambda x, y, z, ax: y - windshield(x, y)[0], ws_top=lambda x, y, z, ax: y - windshield(x, y)[1],
        ws_side=lambda x, y, z, ax: ax - windshield(x, y)[2],
        ws_z=lambda x, y, z, ax: z - WINDSHIELD["z"] - far(-y) - far(y - 1.25),
        black=lambda x, y, z, ax: z - black_top(ax, y),
        nose=lambda x, y, z, ax: y - 1.82, lamp_end=lambda x, y, z, ax: qn(ax, y) - HEAD_LAMP[-1][0],
        bar_top=lambda x, y, z, ax: z - lt(ax, y), bar_bot=lambda x, y, z, ax: z - lt(ax, y) + bw,
        bar_gap=lambda x, y, z, ax: z - lt(ax, y) - BAR[0] + 0.0015,
        lens_bot=lambda x, y, z, ax: z - lt(ax, y) + bw + interp_tab(HEAD_LAMP, qn(ax, y)),
        aft=lambda x, y, z, ax: y + 2.0,
        lip=lambda x, y, z, ax: y - lip_y(ax) + far(0.80 - z),   # (grazes the tail face below the lip)
        spoiler=lambda x, y, z, ax: z - sz(ax, y),
        notch_top=lambda x, y, z, ax: z - sz(ax, y) - (SPOILER["notch"][1] + 0.012 - SPOILER["z"][0][1]),
        spoil_end=lambda x, y, z, ax: qt(ax, y) - SPOILER["q_end"],
        tail_red=lambda x, y, z, ax: ax - TAIL_LAMP[3] - far(y + 2.0),
        tail_top=lambda x, y, z, ax: z - interp_tab(TAIL_LAMP[0], qt(ax, y)) + far(y + 1.95),   # also the
        tail_mid=lambda x, y, z, ax: ax - TAIL_LAMP[1] - far(y + 2.0),                       # tailgate's bottom
        liner=lambda x, y, z, ax: f.well(ax, y, z) - 0.004,
        door=lambda x, y, z, ax: poly_sdf(door, y, z) + far(0.35 - ax),
        trunk_y=lambda x, y, z, ax: y - TRUNK_Y,
        trunk_x=lambda x, y, z, ax: ax - interp_tab(TRUNK_PLAN, y) + far(0.50 - z) + far(y - TRUNK_Y),
        hood_x=lambda x, y, z, ax: ax - interp_tab(HOOD_SEAM, y) + far(0.60 - z) + far(1.00 - y),
        hood_z=lambda x, y, z, ax: z - hood_cap(ax, np.clip(y, 1.09, 2.08)) + BAR[0] + far(1.00 - y),
        # the port's outline: its four lines bent off the body beyond the box (not up the whole tail face)
        port_x0=lambda x, y, z, ax: x - PORT[0] + far(y + 2.0) + far(z - 0.50) + far(0.33 - z),
        port_x1=lambda x, y, z, ax: x - PORT[1] + far(y + 2.0) + far(z - 0.50) + far(0.33 - z),
        port_z0=lambda x, y, z, ax: z - PORT[2] + far(y + 2.0) + far(x + 0.45) + far(-0.75 - x),
        port_z1=lambda x, y, z, ax: z - PORT[3] + far(y + 2.0) + far(x + 0.45) + far(-0.75 - x))


def weld(v, t, eps=2e-5):
    """Merge the vertices a cut made on top of another (a cut through a vertex: zero length edges) and drop the
    triangles that collapse; two grid passes (the second shifted half a cell) catch pairs split by a cell wall."""
    for shift in (0.0, 0.5):
        _, idx, inv = np.unique(np.floor(v / eps + shift).astype(np.int64), axis=0, return_index=True,
                                return_inverse=True)
        v, t = v[idx], inv.ravel()[t]
        t = t[(t[:, 0] != t[:, 1]) & (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])]
    _, inv, cnt = np.unique(np.sort(t, 1), axis=0, return_inverse=True, return_counts=True)
    t = t[cnt[inv.ravel()] == 1]                    # a collapsed sliver pair (a fin): both go
    used, inv = np.unique(t, return_inverse=True)
    return v[used], inv.reshape(-1, 3)


def split_mesh(f, v, t, g):
    """Cut the triangles crossing g = 0 (g per vertex): new vertices where the edges cross, pulled onto the
    surface; each cut triangle becomes three, all on one side (orientation kept)."""
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
    nv = project(f, v[ue[:, 0]] + w[:, None] * (v[ue[:, 1]] - v[ue[:, 0]]), steps=2)
    pab, pac = np.split(len(v) + inv.ravel(), 2)
    new = np.concatenate([np.stack([a, pab, pac], 1), np.stack([pab, b, c], 1), np.stack([pab, c, pac], 1)])
    return np.concatenate([v, nv]), np.concatenate([t[~cr], new])


def classify(f, v, t):
    """Material and panel index per triangle (MATS / PANELS); glass panes get panel-like ids in `pane`.
    Only levels() signs at the face centres: every region edge is a cut curve."""
    c = v[t].mean(1)
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    ax = np.abs(x)
    s = {k: g(x, y, z, ax) < 0 for k, g in levels(f).items()}
    mat = np.zeros(len(t), np.int8)
    # glass: windshield, side windows (outboard of the windshield's side edge: the A pillar between)
    ws = s["cowl"] & ~s["ws_top"] & s["ws_side"] & ~s["ws_z"]
    in_side = s["glass"] & ~s["ws_side"]
    glass = ws | in_side
    mat[glass] = 1
    # black: lower body round the nose and tail; the duck lip's rear face and its shadow notch, across the tail to
    # the corners; tail lamp bar: dark middle, white reversing lens, red outboard
    aft = s["aft"]
    spoil = aft & ~s["spoiler"] & (s["lip"] | s["notch_top"]) & s["spoil_end"]
    tl = aft & ~s["black"] & s["tail_top"]
    mat[s["black"] | spoil | (tl & s["tail_mid"])] = 2
    mat[tl & ~s["tail_mid"] & s["tail_red"]] = 1    # glass (its pane: none; split out with the body's glass below)
    mat[tl & ~s["tail_red"]] = 5
    # head lamps: the light bar under the leading edge, the dark lens under it toward the corners, wrapping onto
    # the side (01 front, 02)
    nose = ~s["nose"] & s["lamp_end"]
    bar = nose & s["bar_top"] & ~s["bar_bot"]
    lens = nose & s["bar_bot"] & ~s["lens_bot"]
    shadow = nose & ~s["bar_top"] & s["bar_gap"]     # the leading edge's shadow line over the bar (01 front)
    mat[lens | shadow] = 2
    mat[bar] = 4
    liner = s["liner"]
    mat[liner] = 3
    # panels
    pan = np.zeros(len(t), np.int8)
    in_dg = in_side & ~s["divider"]
    door = ((s["door"] & ~s["liner"] & ~s["black"]) | in_dg) & ~liner
    pan[door] = np.where(x[door] < 0, 1, 2)
    tg = s["trunk_y"] & s["trunk_x"] & ~s["tail_top"] & ~liner & ~glass
    pan[tg] = 3
    hood = ~s["cowl"] & s["hood_x"] & ~s["hood_z"] & (mat == 0)
    pan[hood] = 4
    port = aft & ~s["port_x0"] & s["port_x1"] & ~s["port_z0"] & s["port_z1"]
    pan[port] = 5
    mat[port] = 2
    # glass panes: windshield 0, door glass 1 (left) / 2 (right), quarter glass 3 / 4, reversing lenses 5
    pane = np.full(len(t), -1, np.int8)
    pane[ws] = 0
    sg = glass & ~ws
    pane[sg & in_dg] = np.where(x[sg & in_dg] < 0, 1, 2)
    pane[sg & ~in_dg] = np.where(x[sg & ~in_dg] < 0, 3, 4)
    pane[(mat == 1) & ~glass] = 5
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


def ray_point(f, o, d, far=0.8, step=0.003):
    """First surface point from each o along d (N x 3): march, then bisect; and the normal there."""
    o, d = np.atleast_2d(np.asarray(o, float)), np.atleast_2d(np.asarray(d, float))
    d = np.broadcast_to(d, o.shape)
    ts = np.arange(0.0, far, step)
    ins = np.stack([f(o + t * d) < 0 for t in ts], 1)
    k = np.argmax(ins, 1)
    lo, hi = ts[np.maximum(k - 1, 0)], ts[k]
    for _ in range(25):
        mid = (lo + hi) / 2
        i = f(o + mid[:, None] * d) < 0
        hi, lo = np.where(i, mid, hi), np.where(i, lo, mid)
    p = o + hi[:, None] * d
    return p, gradient(f, p)


def box(lo, hi):
    """Axis-aligned box: 8 vertices, 12 outward triangles."""
    v = np.array([[(lo, hi)[i >> 2 & 1][0], (lo, hi)[i >> 1 & 1][1], (lo, hi)[i & 1][2]] for i in range(8)], float)
    t = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4),
         (1, 5, 7), (1, 7, 3)]
    return v, np.array(t)


def merge(parts):
    """[(vertices, triangles)] -> one (vertices, triangles)."""
    vs, ts, off = [], [], 0
    for v, t in parts:
        vs.append(v)
        ts.append(np.asarray(t) + off)
        off += len(v)
    return np.concatenate(vs), np.concatenate(ts)


def quad_on(p, n, half_u, half_v, lift):
    """A small flat quad lifted off the surface at p (normal n): u horizontal along the surface, v up it."""
    u = np.cross([0.0, 0.0, 1.0], n)
    u /= np.linalg.norm(u)
    w = np.cross(n, u)
    c = p + n * lift
    v = np.array([c - u * half_u - w * half_v, c + u * half_u - w * half_v, c + u * half_u + w * half_v,
                  c - u * half_u + w * half_v])
    return v, np.array([(0, 1, 2), (0, 2, 3)])


def front_parts(f):
    """Plate holder and plate on the bumper face, the intake's grille and camera (01 front, 02), the lamp dots in
    each lens and the amber side marker ahead of the front wheel (left; mirrored)."""
    out = {}
    x0, z0, z1, hw_ = PLATE
    yf = ray_point(f, [0, 2.6, (z0 + z1) / 2], [0, -1, 0])[0][0, 1]
    out["PlateHolder"] = box((-hw_ - 0.008, yf - 0.03, z0 - 0.008), (hw_ + 0.008, yf + 0.008, z1 + 0.008))
    out["Plate"] = box((-hw_, yf, z0), (hw_, yf + 0.011, z1))
    it = INTAKE
    za, zb = it["z"]
    xs = np.linspace(-0.58, 0.58, 30)
    yb = ray_point(f, np.stack([xs, np.full(30, 2.6), np.full(30, (za + zb) / 2)], 1), [0, -1, 0])[0][:, 1]
    bars = []
    for zz in np.linspace(za, zb, 5)[1:-1]:                     # horizontal slats
        xi = it["x"][1] + (it["x"][0] - it["x"][1]) * (zz - za) / (zb - za) - 0.06   # clear of the eased ends
        for i in range(29):
            a, b = max(xs[i], -xi), min(xs[i + 1], xi)
            if a < b:
                yy = min(yb[i], yb[i + 1])
                bars.append(box((a, yy - 0.004, zz - 0.0025), (b, yy + 0.026, zz + 0.0025)))
    for xx in np.linspace(-0.45, 0.45, 11):                     # dividers
        yy = np.interp(xx, xs, yb)
        bars.append(box((xx - 0.002, yy - 0.004, za + 0.004), (xx + 0.002, yy + 0.026, zb - 0.004)))
    out["Grille"] = merge(bars)
    yc = np.interp(0.0, xs, yb) + 0.026
    a = np.linspace(0, 2 * np.pi, 12, endpoint=False)
    ring = np.stack([0.016 * np.cos(a), np.zeros(12), (za + zb) / 2 + 0.016 * np.sin(a)], 1)
    cv = np.concatenate([ring + [0, yc - 0.03, 0], ring + [0, yc, 0], [[0, yc + 0.004, (za + zb) / 2]]])
    ct = [(i, (i + 1) % 12, 12 + (i + 1) % 12) for i in range(12)] + [(i, 12 + (i + 1) % 12, 12 + i) for i in range(12)]
    ct += [(12 + i, 12 + (i + 1) % 12, 24) for i in range(12)]
    out["FrontCamera"] = (cv, np.array(ct)[:, ::-1])
    # lamp dots: along the lens' middle (left lamp)
    xc, yc0, r = NOSE_C
    dots = []
    for q in np.linspace(0.58, 0.93, LAMP_DOTS):
        th = (q - xc) / r
        o = np.array([[-(xc + 0.8 * np.sin(th)), yc0 + 0.8 * np.cos(th), 0.66]])
        dr = np.array([[np.sin(th), -np.cos(th), 0.0]])
        for _ in range(2):                                     # the lens middle's z at the surface point
            p, n = ray_point(f, o, dr)
            ax_, y_ = np.abs(p[:, 0]), p[:, 1]
            o[:, 2] = (lamp_top(ax_, y_) - (BAR[1] - BAR[0]) - interp_tab(HEAD_LAMP, wrap_q(ax_, y_, NOSE_C)) / 2)
        p, n = ray_point(f, o, dr)
        dots.append(quad_on(p[0], n[0], 0.0045, 0.003, 0.0015))
    out["LampDots"] = merge(dots)
    nr = 12                                     # rows: a 17 cm strip on a curved corner sinks in as one quad
    ys, zs = np.meshgrid(SIDE_MARKER[:2], np.linspace(SIDE_MARKER[2], SIDE_MARKER[3], nr))
    p, n = side_point(f, ys.ravel(), zs.ravel())
    r = 2 * np.arange(nr - 1)[:, None]
    out["SideMarker"] = (p + n * 0.002, np.concatenate([r + [0, 1, 3], r + [0, 3, 2]]))
    return out


def rear_parts(f):
    """The tailgate camera in the duck lip's black face (01 rear)."""
    zc = interp_tab(SPOILER["z"], 0.0) + 0.030
    p, n = ray_point(f, [0, -2.6, zc], [0, 1, 0])
    a = np.linspace(0, 2 * np.pi, 12, endpoint=False)
    ring = np.stack([0.010 * np.cos(a), np.zeros(12), zc + 0.010 * np.sin(a)], 1)
    y0 = p[0, 1]
    v = np.concatenate([ring + [0, y0 + 0.004, 0], ring + [0, y0 - 0.003, 0], [[0, y0 - 0.005, zc]]])
    t = [(i, (i + 1) % 12, 12 + (i + 1) % 12) for i in range(12)] + [(i, 12 + (i + 1) % 12, 12 + i) for i in range(12)]
    t += [(12 + i, 12 + (i + 1) % 12, 24) for i in range(12)]
    return {"RearCamera": (v, np.array(t))}


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
    pts = [(-w / 2 + 0.016, rim), (-w / 2 + 0.004, rim + 0.22 * side), (-w / 2, rim + 0.50 * side),
           (-w / 2 + 0.004, rim + 0.72 * side), (-w / 2 + 0.014, rim + 0.88 * side), (-w / 2 + 0.030, r - 0.004),
           (-w / 2 + 0.050, r)]     # a round shoulder (02, 03: the sidewall reads as a black ring round the cover)
    return pts + [(-x, rr) for x, rr in pts[::-1]]


def wheel_parts(seg=72):
    """{name: (vertices, triangles)}: Tyre_<FL|FR|RL|RR> and Cover_<...> in place (the car frame)."""
    out = {}
    for axle, tag in (("front", "F"), ("rear", "R")):
        ty = TYRES[axle]
        r, w, rim, xc, rc = ty["r"], ty["w"], ty["rim"], WHEEL_X[axle], COVER_R[axle]
        # the cover reaches out over the sidewall (01 side: 0.85 of the tyre's radius), so the sidewall bulges
        # 6 mm inboard of the cover's ring face and only its shoulder shows beyond the ring (02, 03)
        mid = xc - 0.006 - w / 2
        tv, tq = revolve(tyre_profile(r, w, rim), seg)
        # cover (01 side, 02): a flat outer ring, a small step to a shallow domed disc and a small centre cone;
        # (lateral from WHEEL_X, radius)
        cprof = [(-0.016, rc - 0.010), (-0.006, rc), (-0.004, 0.98 * rc), (-0.003, 0.86 * rc), (-0.006, 0.84 * rc),
                 (-0.004, 0.55 * rc), (0.000, 0.16 * rc), (0.003, 0.11 * rc), (0.012, 0.05 * rc), (0.014, 0.0005)]
        cv, cq = revolve(cprof, seg)
        cv[:, 0] += xc - mid
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
def grooves(f, v, t, mat, pan):
    """Seams as V grooves: every vertex on an edge between two panels of one material (not glass) is pushed
    GROOVE[1] into the body; the cuts at +-GROOVE[0] beside each seam (build) bound the V. Returns the moved
    vertices and a per-face flag (the groove's faces: shaded flat)."""
    ue, fa, fb = edge_faces(t)
    o = np.maximum(fb, 0)
    seam = (fb >= 0) & (pan[fa] != pan[o]) & (mat[fa] == mat[o]) & (mat[fa] != MATS.index("Glass"))
    vb = np.unique(ue[seam])
    v = v.copy()
    v[vb] -= gradient(f, v[vb]) * GROOVE[1]
    return v, np.isin(t, vb).any(1)


def seam_loops(v, t, pan):
    """The cut lines for the build: each panel's outline (edges between its faces and the rest) chained into
    its longest closed loop, resampled to ~1 cm (metres; the door on the car's left, the right one mirrored)."""
    ue, fa, fb = edge_faces(t)
    out = {}
    for key, pid in (("door_left", 1), ("trunk", 3), ("hood", 4), ("charge_port", 5)):
        a, b = pan[fa] == pid, np.where(fb >= 0, pan[np.maximum(fb, 0)] == pid, False)
        e = ue[a != b]
        nb = {}
        for i, j in e:
            nb.setdefault(i, []).append(j)
            nb.setdefault(j, []).append(i)
        seen, best = set(), []
        for s in nb:
            if s in seen:
                continue
            loop, prev, cur = [s], None, s
            seen.add(s)
            while True:
                nxt = [k for k in nb[cur] if k != prev and k not in seen]
                if not nxt:
                    break
                prev, cur = cur, nxt[0]
                seen.add(cur)
                loop.append(cur)
            best = loop if len(loop) > len(best) else best
        p = v[best]
        keep = [0]
        for i in range(1, len(p)):
            if np.linalg.norm(p[i] - p[keep[-1]]) >= 0.01:
                keep.append(i)
        out[key] = p[keep].round(4).tolist() + [p[0].round(4).tolist()]
    out["door_right"] = [[-q[0], q[1], q[2]] for q in out["door_left"]]
    out["charge_port_centre"] = np.array(out["charge_port"]).mean(0).round(4).tolist()
    return out


def build(h=CELL):
    """Everything numpy: {'field', 'v', 't', 'mat', 'pan', 'pane', 'groove', 'parts', 'wheels', 'lines'}."""
    f, v, t = body_mesh(h)
    lv = levels(f)
    cuts = list(lv.values()) + [(lambda g, s: lambda x, y, z, ax: g(x, y, z, ax) - s)(lv[k], s)
                                for k in SEAMS for s in (-GROOVE[0], GROOVE[0])]
    for g in cuts:
        v, t = split_mesh(f, v, t, g(v[:, 0], v[:, 1], v[:, 2], np.abs(v[:, 0])))
    v, t = weld(v, t)
    mat, pan, pane = classify(f, v, t)
    lines = seam_loops(v, t, pan)
    v, groove = grooves(f, v, t, mat, pan)
    cam_v, cam_s, cam_l = fender_camera(f)
    btn_v, btn_t = button(f)
    return dict(field=f, v=v, t=t, mat=mat, pan=pan, pane=pane, groove=groove,
                parts=dict(camera=(cam_v, cam_s, cam_l), button=(btn_v, btn_t), front=front_parts(f),
                           rear=rear_parts(f)), wheels=wheel_parts(), lines=lines)


# ---- Blender
COLORS = dict(Paint=((0.76, 0.54, 0.25), 0.80, 0.36), Glass=((0.03, 0.035, 0.04), 0.0, 0.15),   # satin gold
              Trim=((0.035, 0.035, 0.038), 0.0, 0.55), Liner=((0.015, 0.015, 0.016), 0.0, 0.85),
              HeadLight=((0.92, 0.94, 0.96), 0.0, 0.15), TailLight=((0.22, 0.012, 0.018), 0.0, 0.25),
              Tyre=((0.02, 0.02, 0.022), 0.0, 0.8), Cover=((0.76, 0.54, 0.25), 0.80, 0.36),
              Plate=((0.55, 0.56, 0.58), 0.0, 0.5), Marker=((0.70, 0.22, 0.02), 0.0, 0.3))
# small parts: material, mirrored to the right side
PARTS = dict(PlateHolder=("Trim", False), Plate=("Plate", False), Grille=("Trim", False),
             FrontCamera=("Trim", False), LampDots=("HeadLight", True), SideMarker=("Marker", True),
             RearCamera=("Glass", False))
TARGET = 145000          # body triangles after decimation (both halves together)
PANES = ("Glass_Windshield", "Glass_DoorLeft", "Glass_DoorRight", "Glass_QuarterLeft", "Glass_QuarterRight",
         "Glass_ReverseLens")


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
        # degenerate or doubled triangles (cuts meeting at a vertex) would be dropped by validate() and shift the
        # per-face attributes
        keep = (tt[:, 0] != tt[:, 1]) & (tt[:, 1] != tt[:, 2]) & (tt[:, 0] != tt[:, 2])
        first = np.zeros(len(tt), bool)
        first[np.unique(np.sort(tt, 1), axis=0, return_index=True)[1]] = True
        keep &= first
        tt = tt[keep]
        panel = None if panel is None else np.asarray(panel)[keep]
        normals = None if normals is None else normals[keep]
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
    label = (B["mat"].astype(np.int32) * 64 + B["pan"].astype(np.int32) * 8 + (B["pane"].astype(np.int32) + 1)
             + B["groove"].astype(np.int32) * 512)        # the groove's faces: their own label, so its edges hold
    body = make("Body", v, t, "Paint")
    body.data.attributes.new("label", "INT", "FACE").data.foreach_set("value", label)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)       # (weld() merged the cuts' duplicates)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-5)
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
    bm = bmesh.new()                    # vertices a cut left within 0.05 mm of one another: one vertex
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=5e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(body.data)
    bm.free()
    v, t, lab = read(body)
    bpy.data.meshes.remove(body.data)
    fn = np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]])
    # a cut passing a fraction of a mm from a vertex the decimation kept can leave a needle fin (third vertex ~0.1 mm
    # off an edge two other faces share, its own two edges open): drop the tiny faces on 3-face edges
    e = np.sort(t[:, [0, 1, 1, 2, 2, 0]].reshape(-1, 2), 1)
    _, inv, cnt = np.unique(e, axis=0, return_inverse=True, return_counts=True)
    keep = ~((cnt[inv.ravel()].reshape(-1, 3) > 2).any(1) & (np.linalg.norm(fn, axis=1) < 2e-6))
    t, lab, fn = t[keep], lab[keep], fn[keep]
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-15)
    # field normals per corner, read a quarter of the way into the face: across a crease the mesh's edges do not
    # follow, each face takes its own side's normal instead of a blend (no saw tooth along the crease) ...
    cen = v[t].mean(1, keepdims=True)
    gv = gradient(f, (0.75 * v[t] + 0.25 * cen).reshape(-1, 3)).reshape(-1, 3, 3)
    nrm = np.where(((gv * fn[:, None]).sum(2) > 0.3)[..., None], gv, fn[:, None])   # ... faceted on sharp tips
    mat, pan, pane, groove = lab // 64 % 8, lab // 8 % 8, lab % 8 - 1, lab // 512 > 0
    nrm[groove] = fn[groove][:, None]                            # the seam grooves' flanks shade flat
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
    for nm, (vv, tt) in {**B["parts"]["front"], **B["parts"]["rear"]}.items():
        mn, mirrored = PARTS[nm]
        for sx, side in (((-1, "_Left"), (1, "_Right")) if mirrored else ((1, ""),)):
            p = vv * [-sx if mirrored else 1, 1, 1]          # computed on the left
            ob = make(nm + side, p, tt[:, ::-1] if (mirrored and sx > 0) else tt, mn)
            ob.data.polygons.foreach_set("use_smooth", np.zeros(len(ob.data.polygons), bool))
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
