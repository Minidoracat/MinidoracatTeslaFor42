"""Cybercab body shell from scratch (no model file is read): the production gold Cybercab drawn on Tesla's own
pictures only (temp/plan-next-1114/assets/official-cybercab/: rider guide side / front / rear 01, front 3/4 02,
rescue sheet rear 3/4 03, trunk open 04, rescue sheet top + side line art 06, ERG charge port 07).
Shape: one signed distance field (SDF) sampled on a grid and meshed by surface nets, the vertices pulled onto the
zero level, normals from the field's gradient:
  - the side profile (SIDE_TOP / SIDE_BOT: 01's side view, height scale 1,408 mm over the ground line through the
    two tyre bottoms) as a 2-D distance in (y, z), eroded with |x| by the crown (SECTION crown);
  - the plan (PLAN: x92's outline, Tesla's ERG bottom view, scaled by the official 1,754 width; the nose B's own
    table NOSE_PLAN_B) and the section (SECTION knots along y: height of the widest point, the tuck under,
    the shoulder and the tumblehome above it) as |x| <= hw(y, z); the tail's rounded end a bow (tail_bow);
  - the two joined by a smooth max (rounded edges, SECTION k), the wheel houses carved out (ARCH), the front lower
    intake recessed (INTAKE).
Then (REGIONS) every face gets a material (paint, glass, black trim, wheel house liner, head light, tail light) and
a panel (body, doors, tailgate, hood, charge port door; face attribute `panel`, PANELS) from the region outlines;
the outlines between them are smoothed into real edges. The left half is decimated with every outline held and
mirrored (exactly symmetric, no cracks between materials), then split one object per material (glass per pane).
The fender cameras and B pillar buttons are small parts; tyres and flat wheel covers are revolved meshes.
Length / wheelbase: x92 (near orthographic: its tyres measure 215 / 715 mm at that scale): wheelbase 2,700, overhangs
0.88 / 0.97, 4.55 m long. The car is built in round 9's frame (01 side read as orthographic: 4,280 / 2,757 mm, but 01
side is a close perspective, its near side 2.5-3.8 % long), then out_y() moves every y: the nose B 19 cm longer, the
middle between the wheel arches 5.7 cm shorter, the tail behind the rear arch 13.7 cm longer (FRAME).
Frame (as prep_roadster): metres, +Y front, +Z up, -X the car's left, ground 0, y 0 half way along A's car.
    "$B" -b --factory-startup --python scripts/blender/skf/prep_cybercab.py [-- <out dir> [nose=A]]
        -> <out dir>/cybercab_src.blend, cybercab_src.glb, cybercab_lines.json, prep_report.json
           (default temp/skf_cc, nose B; about a minute)
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

# official (rider guide p.15): width 1,754, height 1,408, ground clearance 144; L: round 9's length on 01 (height
# scale), the build frame's (FRAME: 4.55 m out); tyres third party (front 215/60 R18, rear 225/60 R21). y in the
# build frame: out_y() puts the rear axle at -1.2505 (wheelbase 2.700, x92)
L, WIDTH, HEIGHT, CLEAR = 4.2799, 1.754, 1.408, 0.144
TYRES = dict(front=dict(y=1.4495, r=0.3576, w=0.215, rim=0.2286),
             rear=dict(y=-1.3074, r=0.4017, w=0.225, rim=0.2667))
# outer face of the wheel cover (|x|): 01 front's tyre contact widths back-projected through its fitted camera put the
# front tyres' outer faces at |x| 0.846 (track ~1.48 m, x92 1.489); the rear track 1.31 m: x92's rear / front track
# ratio 0.883 (four tyres at one depth: free of the perspective; x92 direct 1.315; round 9's 1.375 off 01 rear's
# fitted camera). Not official figures. Front sidewalls 30 mm inside the body side over the arch (02, 03: near flush)
WHEEL_X = dict(front=0.852, rear=0.7735)
COVER_R = dict(front=0.309, rear=0.338)        # the covers' gold outline on 01 (178 / 195 px)

# ---- tables read off the official pictures (temp/skf_cc/work: tables.json, tables_lit.txt)
# round 13 (Main's wheel-anchored 01 side, FINDINGS A / B; nose_main.json): the nose's lip 4 cm lower, a 1.5 cm blade
# at z 0.224-0.239 (Main's 01 side + 02 lip fit, its leading edge NOSE_SET's lip_s; the face over it NOSE_SET's s),
# the hood 1 cm lower over y 1.1-1.6 (<= 0.901 on the middle, 01 side 4-5 px)
SIDE_TOP = np.array((
    (2.1407, 0.2390), (2.1330, 0.2430), (2.1273, 0.2450), (2.1249, 0.2500),
    (2.1235, 0.2563), (2.1211, 0.5381), (2.1194, 0.5525), (2.1120, 0.5720),   # (0.5381: 2.1205 -> 2.1211, the
    # plate's face read there at 2.3300 again, the length; with the lip 4 cm lower the curve under it bent 0.6 mm in)
    (2.1000, 0.5900), (2.0860, 0.6080), (2.0738, 0.6120),   # sharp leading edge, the light bar under it (02)
    (2.0159, 0.6647), (1.9523, 0.7155), (1.9096, 0.7458), (1.8683, 0.7736),
    (1.7949, 0.8102), (1.7362, 0.8358), (1.6850, 0.8555), (1.6229, 0.8751),
    (1.5798, 0.8844), (1.5390, 0.8912), (1.5022, 0.8959), (1.4476, 0.9031),
    (1.3579, 0.9118), (1.2904, 0.9142), (1.2546, 0.9167), (1.1184, 0.9165),
    (1.1105, 0.9180), (1.1038, 0.9208), (1.0967, 0.9252), (1.0866, 0.9329),
    (0.9424, 1.0310), (0.8377, 1.0958), (0.7236, 1.1617), (0.6797, 1.1864),
    (0.5929, 1.2326), (0.4875, 1.2850), (0.4460, 1.3042), (0.3731, 1.3345),
    (0.3387, 1.3475), (0.2905, 1.3633), (0.2429, 1.3760), (0.1991, 1.3855),
    (0.1507, 1.3939), (0.0632, 1.4033), (-0.0054, 1.4054), (-0.0401, 1.4080),
    (-0.1091, 1.4078), (-0.1478, 1.4047), (-0.1917, 1.4038), (-0.2373, 1.4017),
    (-0.3039, 1.3954), (-0.3491, 1.3923), (-0.4226, 1.3833), (-0.4613, 1.3776),
    (-0.4914, 1.3743), (-0.5239, 1.3686), (-0.5830, 1.3600), (-0.6098, 1.3546),
    (-0.6831, 1.3419), (-0.8124, 1.3151), (-0.8369, 1.3091), (-0.8841, 1.2992),
    (-1.0279, 1.2640), (-1.1507, 1.2314), (-1.2356, 1.2076), (-1.3786, 1.1660),
    (-1.5691, 1.1116), (-1.7704, 1.0503), (-1.9376, 0.9910), (-2.0628, 0.9418),
    (-2.0734, 0.9342), (-2.0792, 0.9255), (-2.0833, 0.9120), (-2.0855, 0.8952),
    (-2.0876, 0.4940), (-2.1310, 0.4940), (-2.1360, 0.4935), (-2.1376, 0.4915),
    (-2.1378, 0.4890),   # (round 13: the lip 5.1 cm lower, TAIL_SHELF; the deck 5-10 mm higher over y -1.57..-1.77
                         # (01 side cols 2200-2300 with the rail lower, crown) and 2-8 mm at its end (rows 452-476
                         # 10-16 px short)
))
# round 11: the leading edge 3.2 cm lower, eased out 20 cm back (01 side through r10c3n: the nose's top 3-5 cm under
# the model's over its first 15 cm, 0.5 cm at 20 cm; 02 / 01 front: the bar 3.1-3.5 cm lower, the edge right over it,
# erg p24's corner pictures)
SIDE_BOT = np.array((
    (2.1407, 0.2240), (2.1306, 0.2170), (2.1206, 0.2085), (2.0796, 0.2105),
    (2.0556, 0.2093), (2.0285, 0.2042), (1.9948, 0.2009), (1.9615, 0.1971),
    (1.9314, 0.1870), (1.9000, 0.1735), (1.8719, 0.1628), (1.8517, 0.1568),
    (1.8367, 0.1547), (1.0578, 0.1715), (1.0404, 0.1728), (1.0202, 0.1781),
    (1.0123, 0.1789), (0.9907, 0.1773), (-0.4274, 0.1708), (-0.4711, 0.1693),
    (-0.5287, 0.1705), (-0.7490, 0.1694), (-0.7698, 0.1685), (-0.7860, 0.1663),
    (-0.8080, 0.1600), (-0.8324, 0.1504), (-0.8463, 0.1460), (-0.8581, 0.1440),
    (-0.8728, 0.1442), (-1.7557, 0.1931), (-1.8020, 0.2002), (-1.8371, 0.2030),
    (-1.8831, 0.2091), (-1.9122, 0.2108), (-1.9520, 0.2100), (-1.9658, 0.2053),
    (-1.9814, 0.2048), (-2.0008, 0.2084), (-2.0120, 0.2115), (-2.0301, 0.2207),
    (-2.0375, 0.2242), (-2.0745, 0.2530), (-2.0850, 0.2600), (-2.0930, 0.2665), (-2.0995, 0.2735),
    (-2.1005, 0.2830), (-2.0960, 0.2920), (-2.0820, 0.2990), (-2.0797, 0.3152), (-2.0818, 0.4550), (-2.0925, 0.4613),
    (-2.1075, 0.4665), (-2.1225, 0.4715), (-2.1305, 0.4755), (-2.1350, 0.4810),
    (-2.1378, 0.4860),   # (round 13: the bumper's face and small lower lip 1-2.2 cm forward (t4: the lip's foot left
                         # behind folded, 20 self-intersections), the lip 4.75 cm lower, its underside up to the
                         # bumper's face at 0.455: TAIL_BUMPER, TAIL_SHELF)
))
# round 12 (Main's tail correction; TAIL_FACE): the face at x 0 0.79 cm further forward (the strip's face at output
# -2.160, the gold under it 1 cm further in), straight down to the lip's top, a flat shelf at TAIL_SHELF[0] back to a
# 2 cm thick tip (01 rear: the lens right under the gold, the black shelf under it; 01 side: the tip 2 cm, the
# underside sloping in to the bumper's face)
# round 11 (01 side through r10c3n's camera, the dark mask's lower edge): behind the rear arch the bumper's lower
# edge 1.1-1.2 cm lower, 3.4-5.0 cm lower 25-35 cm ahead of the tip, 3.6 cm at its rear end; a small lip juts 2 cm
# back under the rear face (z 0.27-0.30: 01 side, the light grey face's foot)
# the plan (half width): x92, Tesla's ERG bottom view (near orthographic; temp/plan-next-1114/raw/img-cc2/x92_plan.md,
# scaled by the official 1,754 width), (x92 column, half width): column 31 is the nose's tip, 1573 the tail's
# (NOSE_TIP, TAIL_TIP), linear between in the output frame; along the body a 9-point running mean (its 3 mm pixel
# steps), held to 1.2 mm; capped at 0.877 over the fender camera's bump 25-31 cm behind the front axle. Round 9's
# plan (06 top view, the rear haunch widened on 01 / 02 / 03) was 2-4 cm wider behind the rear doors, 1-2 cm narrower
# along the middle. Ahead of y 1.615 the nose's own (NOSE_PLAN_B, PLAN_NOSE_A); the tail's round end: tail_bow().
# Columns 231-407 (the widest, over the front wheel) 0.8765: the mesh then measures the official 1,754 (x92's 0.8755
# is its outline half a pixel in)
X92_PLAN = np.array((
    (231, 0.8765), (407, 0.8765), (427, 0.8746), (495, 0.8631), (807, 0.8402), (939, 0.8294),
    (1091, 0.8133), (1319, 0.7962), (1367, 0.7904), (1387, 0.7841), (1407, 0.7720), (1423, 0.7576),
    (1463, 0.7281), (1467, 0.7222), (1503, 0.6957), (1511, 0.6839), (1519, 0.6544), (1539, 0.5660),
    (1543, 0.5454), (1555, 0.4746), (1559, 0.4451), (1563, 0.4068), (1567, 0.3449), (1571, 0.2417),
    (1573, 0.0)))
# what the section takes off the plan's width at the body's widest (the tuck under, the shoulder's lean; over the rear
# arch, where the arch carves the body below z ~0.85, the round hip's softplus up to 4.7 cm), measured on the field
# (build frame y, metres): the plan is x92 plus this. Round 13 (HANDOFF_SHELL5 5, 01 rear row 320 6 px wide each
# side, x92 at -2.00 1.0 cm wide): behind -1.92 1.2 mm less. More takes the top corner down with it (2.5 mm: row
# 320 -4 but top col 80 +5 -> +7); the -2.00 knot's zs up to hold the corner raised the deck's edge 3-5 mm at -1.90
PLAN_PAD = np.array((
    (-1.990, 0.0158), (-1.980, 0.0138), (-1.950, 0.0136), (-1.940, 0.0126), (-1.930, 0.0098), (-1.920, 0.0092),
    (-1.880, 0.0113), (-1.810, 0.0155), (-1.750, 0.0156), (-1.730, 0.0162), (-1.680, 0.0205), (-1.560, 0.0362),
    (-1.510, 0.0418), (-1.450, 0.0467), (-1.410, 0.0474), (-1.360, 0.0466), (-1.310, 0.0444), (-1.200, 0.0356),
    (-1.180, 0.0320), (-1.140, 0.0196), (-1.120, 0.0144), (-1.100, 0.0118), (-1.060, 0.0089), (-0.890, 0.0097),
    (-0.790, 0.0113), (0.790, 0.0110), (1.110, 0.0101), (1.220, 0.0039), (1.360, 0.0028), (1.450, 0.0010),
    (1.540, 0.0026), (1.610, 0.0031)))
# nose A's plan ahead of the front tyres (06 top: half width 1.04 (d / 0.514)^0.413, d from the tip; round 7 tried it
# 3-4 cm wider by the tyre for 02's side marker (37 -> 18 px): the far front corner's outline went 20 -> 25 px)
PLAN_NOSE_A = np.array((
    (1.6450, 0.8694), (1.7210, 0.8613), (1.7473, 0.8583), (1.7735, 0.8546), (1.7945, 0.8506), (1.8155, 0.8452),
    (1.8365, 0.8383), (1.8910, 0.7720), (1.9410, 0.7040), (1.9810, 0.6420), (2.0110, 0.5890), (2.0410, 0.5290),
    (2.0610, 0.4820), (2.0810, 0.4280), (2.0960, 0.3800), (2.1110, 0.3220), (2.1210, 0.2720), (2.1310, 0.2040),
    (2.1360, 0.1535), (2.1390, 0.1050), (2.1410, 0.0000)))
# side windows (both panes; 01 side, (y, z)): the door glass ahead of DIVIDER, the fixed quarter glass behind it. Round
# 6: the two tips 2 cm tall (1 cm, under two mesh cells, their cut came out mm off) and the trace's 5-10 mm wiggles at
# the B pillar straightened (a notch in the edge on 02)
SIDE_GLASS = np.array((
    (0.896, 0.938), (0.893, 0.958), (0.887, 0.961), (0.881, 0.964), (0.845, 0.993), (0.796, 1.032),
    (0.719, 1.089), (0.670, 1.121), (0.646, 1.136), (0.625, 1.150), (0.614, 1.158), (0.571, 1.184),
    (0.495, 1.225), (0.452, 1.247), (0.389, 1.275), (0.307, 1.306), (0.226, 1.328), (0.181, 1.337),
    (0.127, 1.346), (0.050, 1.354), (0.005, 1.356), (-0.151, 1.355), (-0.212, 1.353), (-0.273, 1.346),
    (-0.320, 1.344), (-0.400, 1.335), (-0.477, 1.325), (-0.487, 1.322), (-0.505, 1.320), (-0.531, 1.316),
    (-0.620, 1.302), (-0.763, 1.275), (-0.848, 1.258), (-0.991, 1.225), (-1.047, 1.210), (-1.047, 1.210),
    (-1.075, 1.203), (-1.066, 1.168), (-1.047, 1.157), (-1.047, 1.157), (-1.040, 1.155), (-1.017, 1.152),
    (-0.968, 1.136), (-0.898, 1.119), (-0.822, 1.105), (-0.781, 1.102), (-0.724, 1.094), (-0.656, 1.081),
    (-0.588, 1.070), (-0.526, 1.063), (-0.500, 1.061), (-0.493, 1.060), (-0.479, 1.059), (-0.472, 1.058),
    (-0.465, 1.057), (-0.448, 1.056), (-0.436, 1.055), (-0.429, 1.054), (-0.417, 1.053), (-0.411, 1.052),
    (-0.406, 1.052), (-0.390, 1.050), (-0.376, 1.049), (-0.238, 1.038), (-0.188, 1.032), (-0.142, 1.030),
    (-0.097, 1.024), (-0.053, 1.022), (0.093, 1.008), (0.139, 1.005), (0.189, 0.999), (0.296, 0.992),
    (0.343, 0.986), (0.388, 0.983), (0.435, 0.978), (0.521, 0.971), (0.565, 0.970), (0.582, 0.967),
    (0.601, 0.966), (0.626, 0.961), (0.692, 0.956), (0.720, 0.957), (0.814, 0.946), (0.853, 0.945),
    (0.870, 0.943),
))
GLASS_BOTTOM = 37                    # SIDE_GLASS from here on: the lower edge, tail to nose
# round 5 (feature lines on 01 side): the quarter glass's lower edge toward its tip sat ~2 cm under the official's;
# eased out over the last 6 cm (raised at the tip itself it crossed over the top edge: a bow tie, its cut mm off)
_y = SIDE_GLASS[:, 0]
SIDE_GLASS[GLASS_BOTTOM:, 1] += (0.020 * np.clip((-0.50 - _y[GLASS_BOTTOM:]) / 0.25, 0, 1)
                                 * np.clip((_y[GLASS_BOTTOM:] + 1.075) / 0.06, 0, 1))
# round 8: the door glass's lower edge one smooth curve (the trace's 1-2 mm wiggles kinked the cut: a wavy edge on 02)
_m = (np.arange(len(SIDE_GLASS)) >= GLASS_BOTTOM) & (_y > -0.45)
SIDE_GLASS[_m, 1] = np.polyval(np.polyfit(_y[_m], SIDE_GLASS[_m, 1], 2), _y[_m])
# round 6: its top edge over the roof 9 mm higher (01 side; 02 too, against 03), on a fuller roof edge (crown);
# all the way to the tip (eased there, the edge bent in a cell and its cut ran 0.9 mm off)
SIDE_GLASS[:GLASS_BOTTOM, 1] += 0.009 * np.clip((0.60 - _y[:GLASS_BOTTOM]) / 0.12, 0, 1)

# ---- section knots along y (nose -> tail), fitted on 01 front / rear and 02 / 03 (REPORT.md)
# (round 13, the deck: knots at -1.60 and -1.875 added; -1.875 holds t8's section, so the tail behind it is as it was)
KY = np.array([2.14, 1.95, 1.70, 1.45, 1.10, 0.75, 0.35, -0.05, -0.45, -0.85, -1.15, -1.45, -1.60, -1.75, -1.875, -2.00,
               -2.14])
SECTION = dict(
    zw=np.array([0.550, 0.550, 0.700, 0.780, 0.600, 0.570, 0.580, 0.590, 0.600, 0.620, 0.640, 0.660, 0.630, 0.600, 0.600,
                 0.600, 0.700]),     # height of the widest point (above the front arch at the axle: the 1,754 is there)
    alo=np.array([0.040, 0.000, 0.180, 0.200, 0.130, 0.090, 0.090, 0.090, 0.090, 0.070, 0.040, 0.030, 0.030, 0.030, 0.050,
                  0.070, 0.080]),    # tuck under at the bottom (metres in; the nose's bumper face near vertical, 02; round
                              # 13 none at 1.95: the lip carries x92's outline, the face over it set back, NOSE_SET;
                              # at the tail 0.04 / 0.05 -> 0.07 / 0.08: 01 rear rows 760-800 8-11 px wide, FINDINGS F)
    plo=np.full(17, 2.2),     # its power
    b=np.array([0.150, 0.150, 0.100, 0.060, 0.050, 0.060, 0.080, 0.080, 0.060, 0.030, 0.020, 0.020, 0.050, 0.080, 0.080,
                0.080, 0.040]),      # inward slope from the widest point up to the shoulder (round 13 at the tail the widest
                              # point 8-10 cm lower, the slope steeper: 01 rear rows 300-480 6-11 px wide; at -1.75
                              # 0.08, rows 300-320 5-6 px wide at 0.06, row 280 then 4-5 px narrow)
    b2=np.array([0.000, 0.385, 1.100, 1.100, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
                 0.000, 0.000]),     # the front fender's upper half further in from 4 cm over the widest point (a ramp 6 mm
                              # soft, hw): round 12, 01 front's outline through r10c3n over z 0.78-0.89 (the fender at
                              # y 1.45-1.66) 1.0-3.6 cm inside the model's -> within 0.8 cm; the widest point (x92's
                              # 1,754 at y 1.45, z 0.79) kept
    zs=np.array([0.720, 0.740, 0.800, 0.900, 0.915, 0.927, 0.948, 0.985, 1.000, 1.010, 0.950, 0.920, 0.917, 0.944, 0.920,
                 0.920, 0.920]),     # shoulder (belt) height; behind the glass the hip's top (SHOULDER). Under the glass the
                              # step (g, zs +-3 cm) ends where the glass starts: a glass edge cut across the step's
                              # near-flat middle runs at a grazing angle and shades as a saw tooth (02)
    g=np.array([0.000, 0.000, 0.000, 0.000, 0.020, 0.050, 0.060, 0.060, 0.050, 0.035, 0.010, 0.000, 0.000, 0.000, 0.000,
                0.000, 0.000]),      # step in at the shoulder (behind the quarter glass none: 03's haunch is one round bulge;
                              # round 6 from 9-10 cm to 5-6: the glass sits further out on a steeper wall, 01 front /
                              # 01 rear / 02 / 03 outlines all closer; less of 03's fold under the quarter glass;
                              # round 9 under the quarter glass 6 / 5 / 2 -> 5 / 3.5 / 1 cm: 03's glass bottom lower)
    t=np.array([1.300, 1.300, 1.100, 0.800, 0.500, 0.350, 0.280, 0.310, 0.460, 0.600, 0.750, 0.962, 1.138, 1.159, 0.464,
                0.680, 0.680]),      # tumblehome above the shoulder (01 front, 02: the windshield's sides further out; 01
                              # rear: narrower over the C pillars; much wider and the side glass wraps over the roof's
                              # edge, 02); behind the glass it meets
                              # the near-flat deck in a crease on TRUNK_PLAN's line (03, 06 top view: the haunch
                              # stands out below it). Round 9 over the doors 0.33 / 0.36 -> 0.28 / 0.31: a wider
                              # roof, a gold rail between the roof glass and the side glass (02; at 0.75 too, the front
                              # door's seam at the shoulder came out 2 mm off its cut). Round 13 at the tail 1.0 ->
                              # 0.68: the deck's rear corners out (01 rear rows 260-280 9-12 px narrow, col 80 14 px
                              # low), sat at 1.75 up to keep the hip's S (rows 240-260)
    crown=np.array([0.000, 0.000, 0.005, 0.012, 0.050, 0.005, 0.005, 0.030, 0.015, 0.000, -0.030, -0.030, -0.005, -0.043,
                    -0.005, 0.020, 0.020]),   # roof / deck crown at the plan edge (the hood: hood_cap; the deck near flat;
                                      # over the rear seats a fuller edge: the roof's outline on 02 and 03; rounds 8-9
                                      # over the doors 0.10 -> 0.005, a flat roof: on 01 side the gold edge, not the
                                      # roof glass, between the side glass and the roof line; at the cowl (1.10) less
                                      # left the windshield's corner cuts mm off). Round 13 (FINDINGS D, 01 side cols
                                      # 1500-2300 8-17 px low): over the rear roof and deck the edge (the rail, |x|
                                      # ~0.55) stands up to 2.5 cm over the middle (negative); at the hatch's front
                                      # seam 0 (01 rear col 340: the rail there 8 px high); at 1.75 -0.03 with the
                                      # middle higher (SIDE_TOP: 01 rear row 240 and cols 140-160 the rail 7-15 px out)
    k=np.array([0.008, 0.030, 0.035, 0.035, 0.045, 0.030, 0.025, 0.025, 0.025, 0.020, 0.040, 0.040, 0.0325, 0.025, 0.0185,
                0.012, 0.012]),      # edge rounding (the front fenders roll over into the side: 01 front; ahead of the tail
                              # the deck rolls over into the haunch: 03, one convex roll, no flat band under a crease;
                              # rounds 8-9 rounder there, 0.030 / 0.035 / 0.030 -> 0.080 / 0.090 / 0.070: 03's broad
                              # rounded ridge behind the C pillar; round 12 over the front fender 0.050 / 0.055 ->
                              # 0.035: 01 front's fender top rolls in sharper; round 13 the rail sharper over the
                              # haunch, 0.080 / 0.090 / 0.070 -> 0.040 / 0.040 / 0.025: FINDINGS D)
    # round 13 (FINDINGS D, 01 rear: over the haunch the outline a concave S, the model's straight line 16-43 px out,
    # vertices up to 4.9 cm outside): above the shoulder the side steps in sat (metres) over the first lam or so of
    # height, then rises steep to the rail (a flatter face between the rail and the hip)
    # Round 13 t9 (HANDOFF_SHELL5 1, deckcheck.py): t8 sank the deck's side 4-12 cm over output y -1.5..-1.85 and rose
    # again behind it (the rail in to |x| 0.42-0.50 there); t / sat / lam / zs / crown at -1.45..-1.875 fitted on the
    # field so the side stays 0-3 cm under 01 rear's outline (lim01r_top) falling all the way, the widths at z 0.70-0.88
    # held to 3 mm (k as it was: sharper, the bottom's corner at -1.70 stood out 3-4 px on 01 rear row 800)
    sat=np.array([0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.050, 0.050, 0.060, 0.075, 0.053, 0.070, 0.164,
                  0.000, 0.000]),
    lam=np.array([0.040, 0.040, 0.040, 0.040, 0.040, 0.040, 0.040, 0.040, 0.040, 0.040, 0.035, 0.038, 0.061, 0.059, 0.080,
                  0.040, 0.040]),
)
# wheel houses (01: the arch openings 241 / 257 px about the hubs), inner wall, lip rounding; fl: the opening's front
# lower quarter that much smaller (round 12, CybercabFit r11n: the rear arch's front-lower edge 2.2 cm too far forward,
# 01 side 10.9 / 03 6.0 px -> 0.7 / 1.2 px with it; its top and rear as they were)
ARCH = dict(front=dict(R=0.421, x_in=0.50, lip=0.012, fl=0.0), rear=dict(R=0.448, x_in=0.50, lip=0.016, fl=0.022))
# front lower intake (01 front, 02: the black trapezoid under the plate, grille inside), recessed: half width at
# its top and bottom, z range, depth
INTAKE = dict(x=(0.60, 0.52), z=(0.292, 0.337), y=1.95, depth=0.035)   # 01 front: grille under the black's top
                                     # (round 12: its top 3.5 cm lower with the gold's edge, the bottom on the chin's top
                                     # as it was: 02 through r10c3n, the chin's top within 3 px of the official's)

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
FRONT_BLACK = ((0.0, 0.378), (0.15, 0.375), (0.30, 0.352), (0.45, 0.346), (0.74, 0.345), (0.81, 0.300),
               (0.95, 0.276), (1.11, 0.300))   # (q, black top z): the gold face's lower edge (01 front; 01 side 0.31
                                     # at the corner). Round 11 (02, erg p24's corner pictures): past the intake's outer
                                     # end (q 0.71-0.74) a short step, a thin black at the corner. Round 12 (02 / x253
                                     # through r10c3n): under the plate at its bottom, past it 3.5-4 cm lower (02 20-28
                                     # px), the corner 1-1.5 cm lower
BAR = (0.009, 0.015, 0.0045)        # light bar: from / to depth under the leading edge, and its dark shadow line's top
                                     # (all on the face under the edge's 4 mm rounding: cut in the rounding, a plane
                                     # lying along the surface lands mm off, the boundary check)
# head lamp: the bar runs on along the lens' top, which leaves the bar's line at LAMP[0] (q, z) and rises straight
# (eased in over 10 cm of q) to the tip LAMP[1] (q, z); the lens' bottom LAMP[2] (q, z); the outer end leans back
# LAMP[3] in q per metre up (01 front, 01 side: top 0.627 -> 0.692, bottom 0.603 -> 0.624; 02: a slim wedge, the
# bar's extension). Round 10: the tip round the corner to q 1.00 (|x| ~0.78, y ~1.89): 01 front puts the outer end
# at |x| 0.795, 01 side at y 1.873, 02 + x253 triangulated (0.83, 1.89). Round 11 (r10c3b triangulated; erg p24's
# corner pictures: thick at the outer end, cut on a slant, narrowing inboard into the bar): from its inner tip
# (0.553, 2.198, 0.616: q 0.66) to its outer tip (0.826, 1.902, 0.683: q 1.01), its top 2-3 cm lower along the outer
# half (it ran along the edge, 0.688)
LAMP = ((0.66, 0.612), (1.01, 0.683), ((0.48, 0.640), (0.62, 0.625), (0.70, 0.603), (0.85, 0.610), (1.00, 0.622),
                                       (1.08, 0.630)), 0.8)   # (the bottom crosses the bar's at q ~0.675, not grazing)
# round 12 (erg p24 x222 / x230, x253): a short seam from the head lamp's outer end back along the fender's side to the
# arch's lip, rising a little: (output y, z) of its two ends, 8 mm short of the lamp's end cut, 2 cm short of the arch
FENDER_SEAM = ((1.875, 0.685), (1.690, 0.712))
# the duck lip's black rear face, right under the deck's trailing edge, from crease to crease: black from z (by q) up
# to top; its upper part upright, its lower part (TAIL_FACE bev) the lip's underside sloping in to the gold face.
# Round 12 (Main's tail correction: 01 side's end cap z 0.858-0.923, 03 ~20 px, 01 rear far taller: the underside
# seen from below; round 11's 0.882-0.930 too thin; its top at 0.930 still 6 px high on 03). lamp: |x| of the two
# lighter (lens) segments either side of the camera, along the strip's top, and their height (01 rear rows 266-280:
# 1.8 cm; 03). Round 13 (FINDINGS E.5, wheel-anchored 01 side): the end cap z 0.846-0.928
SPOILER = dict(z=((0.0, 0.846), (1.13, 0.846)), top=0.928, lamp=((0.070, 0.245), 0.018))
# the tail lamp (round 12, Main's tail correction: 01 rear, 01 side, 03 one picture): a lens (Main ~2 cm) on the gold face
# right under the gold, a black shelf under it back to the lip's tip (TAIL_SHELF). TAIL_LAMP: its top along the face
# by |x| (corner 0.537, 03 / 01 side triangulated) and along the side by output y (01 side: 0.511 at -1.79, rising to
# the corner's), the lens' height (the black under it; 01 rear rows 604-618: 1.6 cm, 4 mm over the shelf's edge), the
# |x| where the dark middle turns grey and the grey red (01 rear row 608: cols 393-861 dark, 152-392 grey, 74-150 red;
# 03: the red 11 cm onto the face past the crease), the dark middle's recess. Red on the face and on the side (one
# lamp round the corner). Round 13 (FINDINGS E.3, Main: the lens 2.1 cm): its top 0.546 inboard of |x| 0.45, 0.533 at
# the corner (along the side 0.507 at -1.79), a 2.0 (corner) - 2.75 cm (middle) dark gap under it (the face set in,
# TAIL_FACE gap; the lip's top held at 0.494 by 01 side row 716, wider than FINDINGS' 1.5 cm) down to
# the lip's top (TAIL_SHELF)
TAIL_LAMP = (((0.0, 0.546), (0.45, 0.546), (0.70, 0.533)), ((-1.79, 0.507), (-1.995, 0.533)), 0.021,
             (0.28, 0.585), 0.006)
# for the game's texture (cybercab_lines.json tail_lamp_red_left): the red side segment, from y[0] (01 side: exposed
# from -1.79) back to the crease (output frame), band z (bottom, top) at either end
TAIL_RED_GAME = dict(y=(-1.79, -1.995), z=((0.486, 0.507), (0.512, 0.533)))
# region outlines boundary_off() may miss without failing prep: (|x|, y, z) in the build frame, radius, largest miss
# (m). Round 10 (x92's plan moved the side 1-4 cm): the door glass's front (y 0.89), a 1.6 cm rounded turn
# (round_poly) under a 6.5 mm cell, one chord's middle 0.6 mm off its cut. The front black's top (FRONT_BLACK) where
# it runs into the arch's inner rim (|x| 0.50): 0.7 mm. Round 12 tail (Main's correction): the strip's lens's lower
# outer corner (|x| 0.245, z 0.905: its end and bottom cut at right angles on the strip's face, 4 corner vertices
# 1.6-2.4 mm off, unchanged sharp or rounded 4 mm, t6 / t7). Round 13 (t12, all 1.02 mm or less; round 12's entries
# that no longer caught a vertex went): the same lens's lower inner corner (|x| 0.073); the quarter glass's rear tip
# (round 10's turn, at -1.072 now); the strip's end at the crease's top (z 0.909: its top cut into the crease's
# snapped vertices where the hardness eases off); the lamp's grey | red split (|x| 0.585) on the lamp's bottom
# cut, right angles under a 6.5 mm cell; the recess's lower edge at the crease (0.63, -2.00, 0.795), one side only
BOUNDARY_KNOWN = (((0.8000, 0.8944, 0.9517), 0.010, 0.0010), ((0.500, 1.8365, 0.2776), 0.008, 0.0010),
                  ((0.2447, -2.0775, 0.9072), 0.010, 0.0025), ((0.0725, -2.0822, 0.9110), 0.006, 0.0012),
                  ((0.5605, -1.0722, 1.2062), 0.006, 0.0012), ((0.6745, -1.9932, 0.9086), 0.006, 0.0012),
                  ((0.5848, -2.0109, 0.5231), 0.006, 0.0012), ((0.6305, -2.0018, 0.7949), 0.006, 0.0012))
TAIL_BOW = (0.185, 0.692, 3.43)      # the lip (TAIL_SHELF's shelf and tip) sets forward a (|x| / b)^p (output metres):
                                     # x92's outline within a of its tip (half width 0 -> b, where the lip turns into
                                     # the side; rms 4.5 mm, at most 8.6 mm in |x| over x92's 0.004-0.21 m); round 9's
                                     # a (|x| / 1.16)^3.46 off 06 top had p alike, a 0.55 (x92: 1.16). Past b the bow
                                     # runs on under the plan's side (no crease where it stops), cut at 0.80 off the body
                                     # (a table of x92 points kinked the face: vertical shading bands). Round 13 a
                                     # 0.197 -> 0.185: 01 side row 722, the lip at |x| 0.40 6-8 px short
# round 12 (Main's tail correction: 01 rear, 01 side and 03 one picture, on x92's outline): the face, the lip and the
# bumper each bow forward their own way, the side profile read that much further back. The face (above the shelf):
# output y + (crease y - y) (|x| / crease |x|)^p, the crease (z, y, |x|) where the gold side ends (01 rear col 67.5
# rows 420-580 upright; 01 side cols 2443 / 2453 / 2460; 03; x92 0.6986 at -2.00), p through the lamp's top on the
# face (0.58, -2.057; 0.277, -2.129); the strip's upright part bev[2] further back than the gold under it inboard of
# |x| bev[3], flush at the corners (bev[3] + 0.20: the end out there left x92's outline 3 cm), the lip's underside
# between bev[0] and bev[1]. The side comes in over `taper` (output y, length) ahead of the crease to its |x|.
# Round 13 (FINDINGS E, wheel-anchored 01 side / 01 rear): the crease 1.6-2.3 cm further forward and 1.5-2.2 cm in,
# the face (x 0 at the strip's -2.157, flush, p 3.9) touching 01 side's sightline (|x| 0.45, -2.128; 0.30, -2.178
# ... 0.60, -2.078); gap: under the lens from gap[1] over its bottom the face set gap[0] in (over gap[2]; 01 side rows
# 710-716 8-10 px in); notch: under the end cap (z notch[1]-notch[2], ramps notch[3]) the face notch[0] further in,
# the full width (Main: 01 rear's lit fold at rows 380-382, z 0.80-0.81, the recess deepest at 0.815-0.835, 01 side
# rows 536-548; nose_main.json lim01s_tail: at 0.80 1.1-1.7 cm over with its bottom at 0.803); cham: the end cap's
# lower part forward, cham[0] at its bottom (z cham[1]) easing to 0 at cham[2] (rows 512-524: the cap's face leans
# back). The top step 6-10 mm over the black's bottom cut (SPOILER 0.846): on it the cut ran up to 3.4 mm off, 378
# vertices (t3)
TAIL_FACE = dict(y=-2.157, p=3.9, bev=(0.846, 0.875, 0.0, 0.45), taper=(-1.97, 0.04),
                 crease=((0.50, -1.982, 0.697), (0.555, -1.985, 0.696), (0.607, -1.992, 0.694), (0.660, -1.998, 0.691),
                         (0.712, -2.003, 0.690), (0.764, -2.009, 0.688), (0.816, -2.013, 0.688), (0.86, -2.016, 0.690),
                         (0.95, -2.022, 0.692)),   # (over the end cap 0.69: 01 rear rows 260-280, col 80)
                 gap=(0.017, 0.010, 0.005), notch=(0.030, 0.795, 0.856, 0.004), cham=(0.022, 0.856, 0.92))
# the bumper's face under the lip (zs < TAIL_SHELF[1]): output y + a (|x| / b)^p, square at the corner (round 11
# reached -1.971 at |x| 0.70, z 0.46: 01 rear rows 640-780), on the side out to hw (01 rear cols 59-62, the gold
# body's 67.5) from z0 up to the shelf's black. Round 13 (FINDINGS E.4: 01 side rows 752-820 2.5-2.9 cm out, the
# official in line with the gold face): its face 2.7 cm further forward on the middle (SIDE_BOT), a 2.7 cm less;
# z0 0.27 -> 0.29 (01 rear row 760 4-5 px wide)
TAIL_BUMPER = dict(y=-2.180, a=0.138, b=0.70, p=4.0, hw=0.708, z0=0.29)   # (under its face the small lower lip
# on the lip's bow: TAIL_SHELF[3], no further back than x92)
# the lip's shelf: the profile's flat top (z at x 0; along the face it follows the lamp, TAIL_LAMP: the lip's z warped
# by the lamp top's drop times TAIL_WARP[4] over TAIL_WARP), the lip | bumper bow blend's z (the underside). Round 13
# (FINDINGS E.3: 01 side's lip tip rows 722-734, round 12's 3 cm high): the lip 5.1 cm lower, its top 0.545 -> 0.494
# (01 side row 716, z 0.4977 at the tail's tip: at 0.502 the lip's top over |x| 0.24 showed 17 px past the face, at
# 0.4975 the built mesh's rounded edge 9 px), its underside up to the bumper's face at 0.455 (01 side rows 746-752;
# the charge port reaches 0.447)
TAIL_SHELF = (0.494, 0.475, 0.458, 0.305)
TAIL_WARP = (0.42, 0.05, 0.62, 0.08, 0.4)  # z the warp fades in from, over, out to, over, its share of the lamp's drop
# (the bumper's face and the lip's underside under it as they were: under the port's top its cut ran jagged over the
# warped underside)
# the side and face meet at a hard max where `hard` (output y) and z between `lip` (round 12: the lip's underside;
# from the step's top its corner rounded k: k over the 1 cm lip ate a 5 cm slot in, z 0.513-0.525 at |x| 0.62-0.69)
# and `top` (the deck's trailing edge rounds as before); the mesh's vertices are snapped onto the crease (body_mesh),
# the normals split there (main: read a quarter into each face). Under the step (the shelf at the corner) the crease
# level is a plane across at `foot` (output y)
TAIL_CREASE = dict(step=(0.4935, 0.4995), hard=(-1.95, -1.98), lip=0.430, top=0.935, foot=-2.00)   # (round 13: the
# step and lip 2 / 4 cm lower with the lip)
# round 12 (Main's tail correction: 01 rear, the body's bottom over the middle 20 px over the tyres' (round 10 16,
# round 11 under them; 01 side right): the rear overhang's underside inboard of floor[1] at round 10's (build y, z),
# 4 mm higher (under the bumper's face 1 cm: there it was the lowest, row 838); outboard of floor[1] + floor[2] the
# side profile's (round 11, 01 side). Read on the bumper's bow
REAR_FLOOR = (((-1.68, 0.100), (-1.72, 0.196), (-1.7557, 0.209), (-1.8020, 0.215), (-1.8371, 0.218),
               (-1.8831, 0.224), (-1.9122, 0.227), (-1.9520, 0.234), (-1.9658, 0.237), (-1.9814, 0.243),
               (-2.0008, 0.252), (-2.0120, 0.259), (-2.0301, 0.274), (-2.0375, 0.278), (-2.0625, 0.291),
               (-2.0780, 0.275), (-2.1080, 0.272), (-2.1500, 0.000)), 0.45, 0.17)   # (round 13: its end 2.2 cm
# forward with the small lower lip, SIDE_BOT)
# the small lower lip under the bumper inboard of REAR_FLOOR's |x| (fading out as it does) read dz lower in the profile
# (it stands that much higher) under z1 (over w), behind build y0 (over wy, on the bumper's bow): 01 rear its bottom
# row 836 (the tyres' 856; dz 0.036 left it at 0.294 behind y -2.17, row 836.5), the band rows 815-836; 03 the band
# right across (removed, 03's IoU 0.917 -> 0.910)
TAIL_LOWLIP = dict(dz=0.039, z1=0.345, w=0.03, y0=-2.048, wy=0.015)   # (round 13: y0 -2.07 -> -2.048 with the lip)
WINDSHIELD = dict(cowl=((0.0, 1.352), (0.16, 1.347), (0.256, 1.337), (0.352, 1.323), (0.448, 1.304), (0.544, 1.2775),
                        (0.616, 1.2505), (0.688, 1.214), (0.736, 1.182), (0.784, 1.142), (0.84, 1.080)),
                  top=((0.0, 0.4206), (0.064, 0.4206), (0.136, 0.4165), (0.208, 0.4123), (0.28, 0.4040),
                       (0.352, 0.3946), (0.424, 0.3821), (0.50, 0.3654), (0.57, 0.3424), (0.65, 0.3184),
                       (0.75, 0.2849), (0.85, 0.2493)),
                  side=((0.21, 0.578), (1.098, 0.757)), z=0.88)   # side: 01
# front (round 7 tried its top 3.5 cm in for a broader A pillar on 02: 01 front's side lines 7.7 / 12.7 -> 13 / 18 px).
# Round 11 (r10c3b triangulated, 02 / 01 front): the bottom corners (0.757, 1.098, 0.899) where the cap is 0.892 (were
# (0.709, 1.014, 0.958)), the sides ~4 cm out along their length. Round 13 (FINDINGS B, 06 top view registered on
# x92, 02 / x99 the same line): the hood's rear edge (cowl: (|x|, y)) an arc bowing forward, 15 cm ahead of round 12's
# on the middle, 4.4 cm at the corner; between it and the old base the near-level cowl is glass (dark), the
# windshield's pane down to the arc
# (t10: the arc a least squares even sextic in |x| through FINDINGS B's eight points, at most 6 mm off them: their
# 0.62 point 1.243 bent the seam 6 mm in at |x| 0.58, a kink on 02)
# Round 13 (Main G, CybercabFit: 02 and x253 anchored, triangulated; 06's double arc within 0-2.2 cm): the top edge
# (top: (|x|, build y)) an arc 9.3 cm (middle) to 14.5 cm (0.57) ahead of round 12's (0.324 - 0.40 x^2), out of 0.57
# on the same arc to the roof's edge
# round 13 (Main G): the windshield's middle and the roof's front up to ~6 cm (ROOF_RISE: (build y, m) on the middle,
# eased out to |x| x by (1 - (|x| / x)^2)^2, over z): 01 side's top outline bounds the middle (z <= 0.907 at y 1.254
# ... 1.353 at 0.463, 1.405 at 0.308), the top edge 1.367 on the middle (02, x253, 01 side alike), 1.344 at 0.35-0.57
# (01 side's bound; round 12's 1.343 there kept): the glass's top an arc, high in the middle. Its base level to y 1.25
# and only 1.4 cm up at 1.20 (01 side cols 640-660: the glass's near half there 4-5 px over the outline)
ROOF_RISE = dict(y=((1.352, 0.0), (1.254, 0.0), (1.200, 0.014), (1.158, 0.042), (1.061, 0.0428), (0.964, 0.0478),
                    (0.867, 0.0556),
                    (0.769, 0.0556), (0.690, 0.0520), (0.610, 0.0493), (0.531, 0.0479), (0.451, 0.0432),
                    (0.421, 0.0455), (0.371, 0.0398), (0.330, 0.0386), (0.289, 0.0351), (0.228, 0.0242),
                    (0.176, 0.0162), (0.071, 0.0045), (-0.034, 0.0)), x=0.50, z=(0.85, 0.05))
DIVIDER = ((-0.508, 1.319), (-0.455, 1.066))      # door glass rear edge (01 side)
DOOR = ((0.938, 0.932), (1.026, 0.828), (1.082, 0.744), (1.152, 0.668), (1.20, 0.62))   # front seam down into the
                                     # arch (its corner inside the wheel house: on the lip, its chord ran mm off the cut;
                                     # round 11: its top 1.4 cm forward, r10c3b's (0.855, 0.977, 0.869))
B_SEAM = ((-0.530, 1.077), (-0.274, 0.342))       # door rear seam below the belt; its top runs 1.2 cm inside the
                                     # quarter glass to the divider (along the glass's lower edge the two cuts crossed
                                     # back and forth: slivers; under it, a groove of its own on 02)
B_PILLAR = 0.007                     # the B pillar between the door and quarter glass: a matte black frame +-7 mm on
                                     # DIVIDER (01 side: a dark line ~8 px, 03)
TRUNK_Y = -0.845                     # tailgate front seam across the roof (01 side: the roof's step)
TRUNK_PLAN = ((-0.845, 0.605), (-0.930, 0.600), (-1.050, 0.594), (-1.194, 0.581), (-1.338, 0.576), (-1.482, 0.566),
              (-1.626, 0.557), (-1.770, 0.550), (-1.868, 0.557), (-1.932, 0.586), (-1.978, 0.613), (-2.009, 0.635),
              (-2.044, 0.645), (-2.20, 0.645))   # (y, |x|) its side seam: along the
              # deck's edge to the tail (01 side's seam line read back onto the surface, 03, 06 top view), then down
              # the face just inside the corner (a cut through the corner's rounding folds the mesh) with no groove
              # there (grooves(): 01 rear shows no line). Round 9 up to 3.5 cm inboard over the haunch: on the deck,
              # off the wider edge rounding (k), and 01 side's seam 1-2 cm higher (it sat under the official's);
              # round 10 moved with the plan (x92: 2-6.5 cm narrower, the deck's crease with it), down the face x 0.865;
              # round 11: down the face 2.5 cm inside the crease's top (TAIL_CREASE; its 0.605 ran along the crease);
              # round 13 (FINDINGS D): 06 top view's line (registered on x92), 0.607 -> 0.550 at output -1.71 -> 0.635
              # at -2.05, read back to the build frame; down the face 0.645 (3.5 cm inside the crease)
# hood (01 front, 02): a low dome, its middle on the side silhouette, falling HOOD_VALLEY to the seams; the seams lie
# in shallow valleys between the hood and the fenders' crests (02: the bright band from the A pillar's base down over
# the lamp), which rise back to the silhouette's height FENDER_CREST of the way out to FENDER_X, then roll down,
# FENDER_DROP at FENDER_X (quadratic). Seam route: the lamps' inner ends (|x| ~0.48) up over the fender crest (01
# front: 55 px outside the windshield's corner) and back in to the windshield's corner, the hood's rear edge the
# cowl line only across the glass (01 front / 02: no seam on the A pillar's base). A Catmull-Rom curve through the
# knots, sampled 8 per span (a polyline's kinks moved the cut 2-3 mm side to side round the turn)
def _smooth_tab(knots, n=8):
    p = np.asarray(knots, float)
    p = np.vstack([2 * p[0] - p[1], p, 2 * p[-1] - p[-2]])
    s = np.linspace(0, 1, n, endpoint=False)[:, None]
    out = [0.5 * (2 * p1 + (p2 - p0) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s ** 2 + (3 * p1 - p0 - 3 * p2 + p3) * s ** 3)
           for p0, p1, p2, p3 in zip(p[:-3], p[1:-2], p[2:-1], p[3:])]
    return np.vstack(out + [p[-2:-1]])


HOOD_SEAM = _smooth_tab(((0.96, 0.800), (1.05, 0.808), (1.191, 0.809), (1.287, 0.806), (1.407, 0.794),
                         (1.527, 0.775), (1.647, 0.749), (1.767, 0.716), (1.9043, 0.676), (1.9651, 0.640),
                         (2.0063, 0.598), (2.0397, 0.564), (2.12, 0.535), (2.20, 0.525)))   # (y, |x|)
# round 11: its rear end on the windshield's new corner, its front on the head lamp's inner tip (r10c3b: 0.553 at
# y 2.198 out), the front half eased out 4-6 cm (was 0.735 at 1.08 ... 0.570 at 1.90, 0.490 at 2.05). Round 13
# (FINDINGS C, 06 top view; x99 the same line): 0-4.5 cm further out, 06's line read back to the build frame and,
# ahead of y 1.8, to where the set-back nose is read (nose_wy at the hood's surface: 2.2-3.1 cm further ahead); its
# rear end on the hood's new rear edge (WINDSHIELD cowl's arc) outside the windshield's corner
assert (np.diff(HOOD_SEAM[:, 0]) > 0).all()
HOOD_VALLEY = ((1.08, 0.0), (1.18, 0.010), (1.90, 0.012), (2.04, 0.006), (2.09, 0.0))
HOOD_COWL = ((1.12, 0.0), (1.20, 0.020), (1.30, 0.016), (1.50, 0.0))   # the dome's middle dips just ahead of the
                                     # windshield's base (on the cap too): the base shows over it across (01 front, 02)
FENDER_DROP = ((1.08, 0.0), (1.16, 0.006), (1.26, 0.018), (1.40, 0.026), (1.55, 0.030), (1.80, 0.023), (1.95, 0.008),
               (2.02, 0.0))          # eased in from the cowl (a steep start twists the crest: a wavy reflection, 02);
                                     # round 7 halved: the far front corner's fender top stood under 02's outline
FENDER_X, FENDER_CREST = 0.86, 0.4
CREASE = 0.015                      # rounding of the hood ridges and the shoulder crease (a few mesh cells)
NOSE_ROUND = 0.06                    # the nose's side profile slides back by this (|x| / 0.8)^2: round face in plan
SHOULDER = ((1.15, 0.790), (0.50, 0.850), (-0.42, 0.915), (-1.40, 0.925), (-2.10, 0.915))   # crease (y, z): 01 side
TUCK = (0.10, 0.012)                 # below the crease the side leans in: slope, at most
PORT = (-0.698, -0.600, 0.352, 0.447)            # charge port door (x0, x1, z0, z1), driver side: the square cover
                                                 # at the bumper's outer corner under the red (01 rear cols 72-150,
                                                 # rows 654-750; mirrored: a blank cover). Main round 12: z 0.36-0.49
                                                 # (at 0.490 its inner top corner on the lip's underside left a
                                                 # sub-mm sliver, one open edge, t9). Round 13: rows 654-750 through
                                                 # the anchored 01 rear 0.352-0.470; its top under the bumper face's
                                                 # (0.455, the lip 4 cm lower)
DIFFUSER = (0.475, 0.305, 0.345, 0.015)         # rear bumper's lower step: |x|, z range, set in (01 rear, 03, 04)
# seams: the outlines of the doors, tailgate, hood and charge port door as V grooves (GROOVE: half width, depth)
SEAMS = ("door", "cowl", "hood_x", "hood_z", "trunk_y", "trunk_x", "tail_top", "port_x0", "port_x1", "port_z0",
         "port_z1")
GROOVE = (0.0025, 0.0020)
FENDER_CAM = ((1.230, 0.768), (1.126, 0.794), (1.178, 0.741), 0.028)   # tip, rear top, rear bottom, height
PLATE = (0.0, 0.423, 0.580, 0.150)               # plate (x, z0, z1, half width): round 11 the corners 02 / x253 / 03
                                                 # triangulated (r10c3b: |x| 0.150-0.151, z 0.379-0.536 with nose B)
LAMP_DOTS = 8                                    # small lamps in each head lamp lens (01 front, 02)
# red reflector strip ahead of the front wheel, leaning with the arch's front edge (erg p24 x222, Main round 12: z
# 0.32-0.505; the old fixed y 1.868-1.893 ran off the skin into the arch under z 0.40): its rear edge `gap` (output y)
# ahead of the arch liner's cut, `w` wide (output y; bottom, top: x222's 16-17 px rows), `lift` off the skin
SIDE_MARKER = dict(z=(0.320, 0.505), w=(0.017, 0.024), gap=0.001, lift=0.0025, rows=12)
BUTTON = (-0.490, 1.071, 0.030, 0.012)          # B pillar button (y, z, length, height), 01 side + rider guide p.5

# ---- the nose (round 10). The official pictures come in two families that disagree on its length (temp/skf_cc/
# review10/STEP1.md): "A" is 01 side's (x55 and 06's side view agree), 4.28 m long; "B" (the default) is 02 and
# x253's (two views triangulate the plate 19-20 cm further ahead, 4.4 cm lower) with the plan outline of 06's top view
# and x92's bottom view (each scaled by the 1,754 width: the two agree within 1 cm). Wheels, track, width, height,
# glass, doors and tail are the same in both. Choose with `-- <out dir> nose=A`.
NOSE = next((a[5:] for a in sys.argv[1:] if a.startswith("nose=")), "B")
assert NOSE in ("A", "B"), NOSE
# B: the car is built in A's frame, then every point ahead of y0 moves forward d * smoothstep((y - y0) / (y1 - y0)):
# the face (plate, intake, the bar's middle) d ahead, the hood's front and the corners stretched. y0 just ahead of
# the front arch (its edge at 1.87 moves 1 mm) and of the lamps' outer ends (1.873: the three views put them within
# 4 cm of A's); d: the plate triangulated +0.196 (02, x253), x92's front overhang +0.18 at its wheelbase
NOSE_B = dict(y=(1.86, 2.08), d=0.190, plate_dz=-0.044)
# B's plan ahead of the front wheel: half width (m) at d m behind the nose's tip; 06 top and x92 (bottom view)
NOSE_PLAN_B = ((0.0, 0.0), (0.005, 0.107), (0.01, 0.170), (0.02, 0.258), (0.04, 0.367), (0.06, 0.447),
               (0.086, 0.515), (0.10, 0.545), (0.15, 0.621), (0.20, 0.684), (0.25, 0.735), (0.30, 0.780),
               (0.35, 0.817), (0.40, 0.846), (0.45, 0.862), (0.50, 0.871), (0.60, 0.876), (0.70, 0.877))
# round 13 (FINDINGS A, Main's wheel-anchored 01 side): the gold face and the hood's leading edge stand 3.4-8.1 cm
# behind the lip's outline on the corners (01 side's nose outline is the corners', |x| 0.4-0.7). The nose is read that
# much further ahead (nose_wy: the face set back, the plan's corners with it): s (output m) by z, gated in on output y
# (from gate's y by z, over gw), times smoothstep((|x| - fade[0]) / fade[1]) (Main, nose_main.json: on the middle the
# bar, the bumper face and the plate stay where round 12 had them, 02 / x253's bar there on r12's). Under the lip's
# top (z0 - dz * smoothstep((|x| - x0) / xw), over wz) the lip's own retreat instead: lip_s (|x|, output m), its leading
# edge on Main's 01 side + 02 fit (nose_main.json lip_edge: y 2.268 at x 0 ... 2.219 at 0.55, then x92's outline; top
# 0.236, bottom 0.221; here 3 mm higher, 0.239 / 0.224, the mesh's rounding: 01 side rows 848-854 6 px proud, 02's
# bottom 3-5 px low): on the middle it is no longer x92's outline (the plate is, 2.330). lip_s: x92's outline at z
# 0.2285 less lip_edge, read off the field without it. s under 0.27 1.2 cm more, at 0.335 / 0.558 8 mm more (Main
# item 3: lim01s, 01 side's forward limit per height, t2 over it 1.5-2.6 cm at z 0.26-0.33, |x| 0.35-0.55; now at
# most 0.5 cm over)
NOSE_SET = dict(s=((0.0, 0.078), (0.27, 0.078), (0.285, 0.066), (0.30, 0.055), (0.315, 0.045), (0.335, 0.050),
                   (0.36, 0.043), (0.38, 0.041), (0.43, 0.040), (0.465, 0.038), (0.50, 0.034), (0.545, 0.034),
                   (0.558, 0.052), (0.577, 0.059), (0.615, 0.065), (0.656, 0.068), (0.69, 0.081), (0.728, 0.049),
                   (0.763, 0.022), (0.80, 0.010), (0.85, 0.0)),
                lip=(0.239, 0.0, 0.0, 0.22, 0.010), gate=((0.0, 1.87), (0.62, 1.87), (0.72, 1.76), (1.0, 1.76)),
                gw=0.13, corner=(0.5, 0.55, 0.10, 0.50, 0.06), fade=(0.08, 0.30),
                lip_s=((0.0, 0.0349), (0.1, 0.0323), (0.2, 0.0364), (0.3, 0.0434), (0.35, 0.0409), (0.4, 0.0319),
                       (0.45, 0.0179), (0.5, 0.0105), (0.55, 0.0025), (0.62, 0.0), (0.7, 0.0)))
# (corner: s times 1 - k on the corners (|x| from x0 over xw) under z1 (over zw): 02 left edge rows 660-700, the far
# corner at |x| 0.63-0.80, z 0.38-0.43, 8-10 px inside; higher up 02's rows 540-600 want it too, but 01 side rows
# 620-640 then stand 10-16 px proud: left)
# round 13 t10-t11 (HANDOFF_SHELL5 3, nose_main.json lip_edge_v2: 01 side + 02 + x253b fitted together): the lip's
# front 2.7 / 3.0 / 2.2 / 0.9 / 0.3 / 0.5 cm further forward at |x| 0 / 0.1 / 0.2 / 0.3 / 0.4 / 0.5 than t8's mesh
# (lip_s). lip_s cut the profile's 1.5 cm blade off: the front stood 2.4-3.3 cm tall, its underside 1 cm under v2's
# bottom (02's lower edge 6-9 px low) and its top 0.5 cm over v2's (01 side row 860 8 px proud at |x| 0.38). Its top
# LIP_LIFT (|x|, m: the field read that much lower under z 0.28 ahead of output y 2.15), its underside chamfered up to
# LIP_EDGE's bottom zb (|x|, z) at its front y (|x|, output y), rising `slope` toward it (02 sees down 0.17-0.2)
LIP_LIFT = ((0.0, 0.009), (0.1, 0.009), (0.2, 0.004), (0.3, -0.007), (0.4, -0.003), (0.5, -0.005), (0.6, -0.004),
            (0.7, 0.0))
LIP_EDGE = dict(y=((0.0, 2.295), (0.1, 2.293), (0.2, 2.278), (0.3, 2.257), (0.4, 2.247), (0.5, 2.236), (0.6, 2.200),
                   (0.684, 2.130), (0.735, 2.080)),
                zb=((0.0, 0.230), (0.1, 0.230), (0.2, 0.225), (0.3, 0.219), (0.4, 0.222), (0.5, 0.220), (0.735, 0.220)),
                slope=0.25)
# round 13 (FINDINGS B, 01 side: the official top rises from col 650, the model's from 672; cols 680-740 12-16 px
# low): the windshield and A pillar's base 4 cm further forward, the body over z0 read d further back (full over
# y a[0] + a[1] .. b[0] - b[1], eased in over a[1] and out over b[1]); the region outlines stay
# (t11: z 0.86 over 0.04 -> 0.84 over 0.08: its 4 cm in 4 cm of height folded the fender top's ramp up into the A
# pillar's base, at (0.80, 1.12, 0.88) five sheets over one another, a hole and slivers on 02)
WS_SHIFT = dict(d=0.04, a=(0.80, 0.30), b=(1.35, 0.15), z=(0.84, 0.08))


def smax(a, b, k):
    """Smooth maximum (polynomial), rounding radius about k."""
    k = np.maximum(k, 1e-6)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return a + (b - a) * h + k * h * (1.0 - h)


def ss(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---- the output frame (round 10). The car is built in round 9's frame (A's: 01 side read as orthographic), then
# out_y() moves every y: nose B forward (NOSE_B); the middle between the wheel arches shorter to the wheelbase (x92
# 2.702), a smoothstep over FRAME["mid"], whose ends stay clear of the arches and their lips (the arches stay round,
# the rear arch and wheels move whole); the tail behind the rear arch longer, its tip to TAIL_TIP (x92's rear overhang
# 0.973), a smoothstep over FRAME["tail"] (the face, bumper and lip at its end move near whole). The checks run in
# the build frame; normals scale y by the stretch's inverse.
NOSE_TIP, TAIL_TIP = 2.330, -2.220            # the output car's ends (x92 columns 31 / 1573; nose A ends at 2.141)
TIP_A = -2.140                                 # the tail's tip in the build frame (SIDE_TOP / SIDE_BOT at x 0)
FRAME = dict(wheelbase=2.700, mid=(-0.84, 1.00), tail=(-1.775, -2.14))
_SW = TYRES["front"]["y"] - TYRES["rear"]["y"] - FRAME["wheelbase"]   # the rear axle moves forward this
_ST = TIP_A + _SW - TAIL_TIP                                          # the tail grows this


def ss_d(t):
    """d ss / dt."""
    t = np.clip(t, 0.0, 1.0)
    return 6.0 * t * (1.0 - t)


def out_y(y):
    """The build frame -> the output frame (y)."""
    y = np.asarray(y, float)
    (m0, m1), (t0, t1) = FRAME["mid"], FRAME["tail"]
    o = y + _SW * (1.0 - ss((y - m0) / (m1 - m0))) - _ST * ss((t0 - y) / (t0 - t1))
    if NOSE == "B":
        (y0, y1), d = NOSE_B["y"], NOSE_B["d"]
        o = o + d * ss((y - y0) / (y1 - y0))
    return o


def out_jy(y):
    """d out_y / dy (the stretch; normals scale y by its inverse)."""
    y = np.asarray(y, float)
    (m0, m1), (t0, t1) = FRAME["mid"], FRAME["tail"]
    j = 1.0 - _SW * ss_d((y - m0) / (m1 - m0)) / (m1 - m0) + _ST * ss_d((t0 - y) / (t0 - t1)) / (t0 - t1)
    if NOSE == "B":
        (y0, y1), d = NOSE_B["y"], NOSE_B["d"]
        j = j + d * ss_d((y - y0) / (y1 - y0)) / (y1 - y0)
    return j


_G = np.linspace(-2.6, 2.6, 26001)
_OG = out_y(_G)


def in_y(y):
    """The output frame -> the build frame (y)."""
    return np.interp(y, _OG, _G)


def out_pts(p):
    """Points (..., 3) to the output frame."""
    p = np.array(p, float)
    p[..., 1] = out_y(p[..., 1])
    return p


def x92_w(yo):
    """x92's half width at output y."""
    return np.interp(31 + (NOSE_TIP - yo) / (NOSE_TIP - TAIL_TIP) * (1573 - 31), X92_PLAN[:, 0], X92_PLAN[:, 1])


# the plan in the build frame: x92 plus what the section takes off (PLAN_PAD); within TAIL_BOW a of the tail's tip held
# at the face's corner (the bow shapes the end there); ahead of 1.615 the nose's own (B stays near its full width
# further forward: 0.871 at y 1.83, A 0.84). B: the side marker keeps its place on the output car; the plate lower
# (02, x253)
_y = np.r_[TIP_A - 0.001, np.arange(-2.13, 1.6151, 0.01)]
PLAN = np.c_[_y, x92_w(np.maximum(out_y(_y), TAIL_TIP + TAIL_BOW[0])) + np.interp(_y, *PLAN_PAD.T)]
if NOSE == "B":
    _y = np.r_[np.arange(1.62, 2.12, 0.005), np.arange(2.12, 2.1405, 0.0025), 2.141]
    PLAN = np.concatenate([PLAN, np.c_[_y, np.interp(out_y(2.141) - out_y(_y), *np.array(NOSE_PLAN_B).T)]])
    PLATE = (PLATE[0], PLATE[1] + NOSE_B["plate_dz"], PLATE[2] + NOSE_B["plate_dz"], PLATE[3])
else:
    PLAN = np.concatenate([PLAN, PLAN_NOSE_A])
# round 12: behind the rear doors a 3 cm Gaussian over the plan (x92's knots and PLAN_PAD's, linear between: their
# slope steps up to 0.25 -> 0.5 in 1.2 cm shaded the side ahead of the crease as upright bands, 03 / rear 3/4); at
# most 3.5 mm off, the held corner (TAIL_BOW) untouched
_m = (PLAN[:, 0] > in_y(np.array([TAIL_TIP + TAIL_BOW[0]]))[0]) & (PLAN[:, 0] < -1.0)
_k = np.exp(-0.5 * (np.arange(-9, 10) / 3.0) ** 2)
PLAN[_m, 1] = np.convolve(np.pad(PLAN[:, 1], 9, mode="edge"), _k / _k.sum(), "valid")[_m]


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


def round_poly(poly, r=0.012, n=6):
    """The closed polygon with each corner replaced by a quadratic arc from r before it to r after (at most half
    an edge): an outline cut into the mesh bends no tighter than ~r (a sharp corner's chord runs mm off it)."""
    p = np.asarray(poly, float)
    t = np.linspace(0, 1, n)[:, None]
    out = []
    for i in range(len(p)):
        p0, p1, p2 = p[i - 1], p[i], p[(i + 1) % len(p)]
        a = p1 + (p0 - p1) * min(r / max(np.linalg.norm(p0 - p1), 1e-9), 0.5)
        b = p1 + (p2 - p1) * min(r / max(np.linalg.norm(p2 - p1), 1e-9), 0.5)
        out.append((1 - t) ** 2 * a + 2 * (1 - t) * t * p1 + t ** 2 * b)
    return np.concatenate(out)


def interp_tab(tab, x):
    tab = np.asarray(tab, float)
    o = np.argsort(tab[:, 0])
    return np.interp(x, tab[o, 0], tab[o, 1])


def arch_dc(nm, y, z):
    """Distance outside the wheel arch's circle (ARCH / TYRES), its front-lower quarter smaller by ARCH fl."""
    a, ty = ARCH[nm], TYRES[nm]
    dy, dz = y - ty["y"], z - ty["r"]
    d = np.hypot(dy, dz)
    c = np.maximum(d, 1e-9)
    return d - a["R"] + a["fl"] * ss((dy / c - 0.5) / 0.4) * ss((0.75 - dz / c) / 0.4)


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


def nose_wy(ax, y, z):
    """Build y the nose is read at (NOSE_SET): ahead by s(z) in the output frame, gated in toward the nose; the face,
    the leading edge and the plan's corners stand back on the corners, the lip by its own table."""
    ns = NOSE_SET
    z0, dz, x0, xw, wz = ns["lip"]
    g = np.asarray(ns["gate"], float)
    yo = out_y(y)
    k, cx, cw, cz, czw = ns["corner"]
    face = (interp_tab(ns["s"], z) * ss((ax - ns["fade"][0]) / ns["fade"][1])
            * (1 - k * ss((ax - cx) / cw) * ss((cz - z) / czw)))
    w = ss((z - z0 + dz * ss((ax - x0) / xw)) / wz)
    s = (face * w + interp_tab(ns["lip_s"], ax) * (1 - w)) * ss((yo - np.interp(z, g[:, 0], g[:, 1])) / ns["gw"])
    return in_y(yo + s)


def body_wy(ax, y, z):
    """Build y the body's field is read at: the nose set back (nose_wy), the windshield's base forward (WS_SHIFT)."""
    w = WS_SHIFT
    d = (w["d"] * ss((y - w["a"][0]) / w["a"][1]) * ss((w["b"][0] - y) / w["b"][1])
         * ss((z - w["z"][0]) / w["z"][1]))
    return nose_wy(ax, y, z) - d


def roof_rise(ax, y, z):
    """How far the windshield's middle and the roof's front stand up (ROOF_RISE; build y, before body_wy)."""
    r = ROOF_RISE
    w = np.clip(1 - (ax / r["x"]) ** 2, 0, 1) ** 2
    return interp_tab(r["y"], y) * w * ss((z - r["z"][0]) / r["z"][1])


def tail_bow(ax):
    """How far the lip sets forward at |x| in the build frame (TAIL_BOW, read back through out_y)."""
    a, b, p = TAIL_BOW
    return in_y(TAIL_TIP + a * (np.minimum(ax, 0.80) / b) ** p) - TIP_A


def face_bow(ax, z):
    """How far the face (above the shelf) sets forward at (|x|, z) in the build frame (TAIL_FACE): 0 for the strip's
    upright part at x 0, where the side profile has it; the gap under the lens and the notch under the end cap set
    further in, the end cap's lower part leaning forward (round 13)."""
    tf = TAIL_FACE
    c = np.asarray(tf["crease"])
    yc, xc = np.interp(z, c[:, 0], c[:, 1]), np.interp(z, c[:, 0], c[:, 2])
    z0, z1, bev, bx = tf["bev"]
    yo = (tf["y"] + (yc - tf["y"]) * (np.minimum(ax, 0.80) / xc) ** tf["p"]
          - bev * ss((z - z0) / (z1 - z0)) * (1 - ss((ax - bx) / 0.20)))
    g, n, (ch, c0, c1) = tf["gap"], tf["notch"], tf["cham"]
    lb = interp_tab(TAIL_LAMP[0], ax) - TAIL_LAMP[2]
    corner = 1 - ss((ax - 0.64) / 0.04)    # (notch and cham eased out at the crease: across its cuts, t4; from 0.58
    #                                         01 side rows 536-548 stood 10-11 px short)
    return (in_y(yo) - in_y(tf["y"] - bev) + g[0] * ss((lb + g[1] - z) / g[2])
            + corner * (n[0] * ss((z - n[1]) / n[3]) * ss((n[2] - z) / n[3])
                        + ch * (1 - ss((z - c0) / (c1 - c0))) * ss((z - c0 + 0.004) / 0.003)))


def bumper_bow(ax):
    """How far the bumper's face (under the lip) sets forward at |x| in the build frame (TAIL_BUMPER)."""
    tb = TAIL_BUMPER
    return in_y(tb["y"] + tb["a"] * (np.minimum(ax, 0.80) / tb["b"]) ** tb["p"]) - in_y(tb["y"])


def tail_lamp_top(ax, y):
    """Top of the tail lamp's lens at (|x|, build y): along the face by |x|, along the side by y (TAIL_LAMP)."""
    face, side = TAIL_LAMP[0], TAIL_LAMP[1]
    return interp_tab(face, ax) + interp_tab(side, out_y(y)) - side[-1][1]


# round 13 (HANDOFF_SHELL5 5, 01 side tail row 722 8 px short: there the outline is the shelf's top at |x| 0.36, z
# 0.494, rounded off under the official's corner): the shelf and lip read lower by this (|x|, m) from z 0.48 up (4 mm:
# 722 -7 -> -2 on the field's own outline; 8 mm overshot 728, a ramp from |x| 0.10 lifted row 716 15 px)
TAIL_LIPRISE = ((0.20, 0.0), (0.40, 0.004), (0.52, 0.004), (0.62, 0.0))


def tail_zs(ax, y, z):
    """The z the side profile is read at round the tail: the lip and its shelf follow the lamp's top down toward the
    corners (TAIL_WARP; the face and the bumper's face upright there, unchanged); inboard the small lower lip under
    the bumper stands higher (TAIL_LOWLIP); the shelf's corner up TAIL_LIPRISE."""
    z0, w0, z1, w1, k = TAIL_WARP
    dz = interp_tab(TAIL_LAMP[0], ax) - TAIL_LAMP[0][0][1]
    fade = ss((-1.75 - y) / 0.10)
    tl, (_, fx, fw) = TAIL_LOWLIP, REAR_FLOOR
    low = (tl["dz"] * ss((fx + fw - ax) / fw) * ss((tl["z1"] - z) / tl["w"])
           * ss((tl["y0"] - y + bumper_bow(ax) * fade) / tl["wy"]))
    rise = interp_tab(TAIL_LIPRISE, ax) * ss((z - 0.482) / 0.010) * ss((0.62 - z) / 0.08)
    return z - (k * dz * ss((z - z0) / w0) * ss((z1 - z) / w1) + rise) * fade - low


def hood_cap(ax, y):
    """Top of the hood and front fenders (z at (|x|, y), 1.08 < y < 2.09): the hood a low dome on the side
    silhouette (read where nose_y slides it) falling HOOD_VALLEY to the seam; the fender rising from the same valley
    to the silhouette's height at its crest, then rolling down, FENDER_DROP at FENDER_X. The valley is a smooth
    maximum (radius CREASE): a kink off the mesh's edges would shade as a saw tooth."""
    zc, V, xs = zsil(nose_y(ax, y)), interp_tab(HOOD_VALLEY, y), interp_tab(HOOD_SEAM, y)
    xc = xs + np.maximum(FENDER_CREST * (FENDER_X - xs), 0.05)    # a narrower crest twists into a saddle (02)
    hood = zc - V * (ax / xs) ** 2 - interp_tab(HOOD_COWL, y) * (1 - np.minimum(ax / xs, 1) ** 2)
    u = np.clip((ax - xc) / np.maximum(FENDER_X - xc, 0.01), 0.0, 1.3)
    fender = np.where(ax < xc, zc - V * ((xc - ax) / (xc - xs)) ** 2, zc - interp_tab(FENDER_DROP, y) * u ** 2)
    return smax(hood, fender, CREASE)


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
        # the lip's read (Field.parts): the profile with the tail face's drop to the shelf taken out (a block over the
        # lip; the shelf's top is put back behind the face where the face's own read has it)
        i = int(np.nonzero((SIDE_TOP[:, 0] < -2.0) & (SIDE_TOP[:, 1] <= TAIL_SHELF[0] + 1e-6))[0][0])
        self.foot = SIDE_TOP[i, 0]
        top = np.concatenate([SIDE_TOP[:i], [(SIDE_TOP[i + 1, 0], SIDE_TOP[i - 1, 1])], SIDE_TOP[i + 1:]])
        self.lip = poly_sdf(np.concatenate([top, SIDE_BOT[::-1]]), yy.ravel(), zz.ravel()).reshape(ny, nz)

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
        zw, alo, plo, b, b2 = (self.knot(k, y) for k in ("zw", "alo", "plo", "b", "b2"))
        zs, g, t, sat, lam = (self.knot(k, y) for k in ("zs", "g", "t", "sat", "lam"))
        lo = alo * np.clip((zw - z) / np.maximum(zw - 0.10, 0.05), 0, 2) ** plo
        # softplus instead of max(): a kink off the mesh's edges would shade as a saw tooth (02, 01 side); behind the
        # glass the haunch rolls into the steep tumblehome over ~7 cm (03: a round hip, the crease only at the deck);
        # over the haunch the side steps in sat first, from zs up (round 13: the concave S, SECTION sat / lam; its own
        # 1.5 cm rounding: the tumblehome's softer one reached down to the arch, x92's plan 2.6-4.4 cm narrower)
        sr = 0.02 + 0.08 * ss((-1.05 - y) / 0.15) * ss((y + 1.95) / 0.15)
        sp = sr * np.logaddexp(0, (z - zs) / sr)
        sq = 0.015 * np.logaddexp(0, (z - zs) / 0.015)
        up = (b * CREASE * np.logaddexp(0, (z - zw) / CREASE) + b2 * 0.006 * np.logaddexp(0, (z - zw - 0.04) / 0.006)
              + g * ss((z - zs) / 0.06 + 0.5) + t * sp + sat * (1 - np.exp(-sq / lam)))
        # shoulder crease (01 side, 02, 03): from behind the front arch up to the B pillar and along the haunch;
        # below it the side leans in a little
        lean = TUCK[0] * CREASE * np.logaddexp(0, (interp_tab(SHOULDER, y) - z) / CREASE)
        tuck = TUCK[1] * (1 - np.exp(-lean / TUCK[1])) * ss((1.25 - y) / 0.15)
        return w - np.where(z < zw, lo, 0.0) - up - tuck

    def well(self, x, y, z):
        """Wheel houses (negative inside the carved volume)."""
        d = np.full(len(x), 1e3)
        for nm, a in ARCH.items():
            dc = arch_dc(nm, y, z)
            d = np.minimum(d, smax(dc, a["x_in"] - x, 0.02))
        return d

    def corner(self, y, z):
        """How hard the tail's side | face edge is at build y (TAIL_CREASE; 0: the k rounding, 1: a crease)."""
        tc = TAIL_CREASE
        (h0, h1), z0 = tc["hard"], tc["lip"]
        return ss((h0 - out_y(y)) / (h0 - h1)) * ss((z - z0) / 0.006) * ss((tc["top"] - z) / 0.008)

    def parts(self, p):
        """The side profile's (d1) and the plan's (d2) distances, and the corner's hardness (corner())."""
        x, y, z = np.abs(p[:, 0]), p[:, 1], p[:, 2]
        # the nose rounds in plan (nose_y); round the tail the side profile is read further back by how far each part
        # bows forward toward its corners: above the shelf the face (face_bow), under it the lip (tail_bow) and,
        # under the lip's underside, the bumper (bumper_bow); the lip's z follows the lamp (tail_zs). The shelf is
        # flat in the profile (TAIL_SHELF[0]): over it the face's read, under it the lip's, the two meeting on it
        zs = tail_zs(x, y, z)
        lip, bump = tail_bow(x), bumper_bow(x)
        bump = bump + (np.maximum(bump, lip) - bump) * ss((TAIL_SHELF[3] - zs) / 0.015)   # (the small lower lip)
        fb, s0, fade = face_bow(x, z), TAIL_SHELF[0], ss((-1.75 - y) / 0.10)
        sh = np.where(zs > s0, fb, lip + (bump - lip) * ss((TAIL_SHELF[1] - zs) / (TAIL_SHELF[1] - TAIL_SHELF[2])))
        ys = nose_y(x, y) - sh * fade
        # under the shelf the lip's block, its top behind where the face stands (the profile's own face, read on the
        # lip's bow, stood 3.5 cm ahead of it at the corners: the band's side rounded 7-12 mm in toward it)
        ds = np.where(zs > s0, self.samp(self.side, ys, zs),
                      np.maximum(self.samp(self.lip, ys, zs), np.minimum(zs - s0, self.foot + (fb - sh) * fade - ys)))
        nz = self.samp(self.gz, ys, zs)
        w = self.plan(y)
        tx = np.clip(x / np.maximum(w, 1e-3), 0, 1.2)
        # (the deck's crown; round the tail not on the lip's shelf: there it dropped the shelf 2 cm at the side, a slot
        # 5-8 cm deep at z 0.51-0.525 behind output y -1.93)
        crown = self.knot("crown", y) * (1 - ss((-1.80 - out_y(y)) / 0.05) * ss((0.70 - zs) / 0.05))
        d1 = ds + crown * tx ** 2 * np.maximum(nz, 0)
        hw = self.hw(y, z, w)
        yo, tc, tf = out_y(y), TAIL_CREASE, TAIL_FACE
        # above the shelf the side comes in to the crease's |x| over the last few cm ahead of it
        c = np.asarray(tf["crease"])
        n = (np.maximum(hw - np.interp(z, c[:, 0], c[:, 2]), 0.0) * ss((tf["taper"][0] - yo) / tf["taper"][1])
             * ss((z - tc["step"][0]) / (tc["step"][1] - tc["step"][0])))
        # the bumper under the lamp's black stands out to TAIL_BUMPER hw on the side round the tail's corner
        tb = TAIL_BUMPER
        bt = tail_lamp_top(x, y) - TAIL_LAMP[2] - 0.004
        wb = ss((z - tb["z0"]) / 0.06) * ss((bt - z) / 0.010) * ss((-1.86 - yo) / 0.06)
        d2 = x - hw + n - wb * 0.003 * np.logaddexp(0, (tb["hw"] - hw) / 0.003)
        return d1, d2, self.corner(y, z)

    def crease(self, p):
        """d1 - d2: zero where the tail face meets the side (and along every other edge between the two)."""
        d1, d2, _ = self.parts(p)
        return d1 - d2

    def __call__(self, p):
        rise = roof_rise(np.abs(p[:, 0]), p[:, 1], p[:, 2])
        ax, yo, z0 = np.abs(p[:, 0]), out_y(p[:, 1]), p[:, 2]
        zl = z0 - interp_tab(LIP_LIFT, ax) * ss((yo - 2.15) / 0.05) * ss((0.28 - z0) / 0.03)   # (the lip's top: LIP_LIFT)
        p = np.column_stack([p[:, 0], body_wy(ax, p[:, 1], zl), zl])   # (round 13)
        x, y, z = np.abs(p[:, 0]), p[:, 1], p[:, 2]
        d1, d2, hard = self.parts(p)
        d = smax(d1, d2, self.knot("k", y) * (1.0 - hard))
        # behind the cap's rear edge (y 1.08) it lifts away up a ramp steeper than the windshield: the fender top runs
        # up into the A pillar's base (it stopped at a step: a flat ledge outside the windshield's corners, 01 front)
        yb = np.maximum(1.08 - y, 0.0)
        cap = smax(d, z - hood_cap(x, np.clip(y, 1.08, 2.09)) - (1.0 * yb + 3.0 * yb ** 2), 0.004)
        d = np.where(y < 2.09, cap, d) - rise
        for nm, a in ARCH.items():
            dc = arch_dc(nm, y, z)
            d = smax(d, -smax(dc, a["x_in"] - x, 0.02), a["lip"])
        it = INTAKE
        xi = it["x"][1] + (it["x"][0] - it["x"][1]) * np.clip((z - it["z"][0]) / (it["z"][1] - it["z"][0]), 0, 1)
        # depth eased out over 6 cm toward the opening's ends: they wrap round the nose's corners, where the bumper
        # is thin (a full-depth step there folds the mesh); the whole opening inside the black (a step into the gold
        # reads as a dent: 02)
        d = d + it["depth"] * (ss((xi - x) / 0.06) * ss((z - it["z"][0]) / 0.006) * ss((it["z"][1] - z) / 0.006)
                               * ss((y - it["y"]) / 0.04))
        # the nose's lip: its underside chamfered up to its front's bottom (LIP_EDGE), off the corners past |x| 0.72
        le = LIP_EDGE
        d = smax(d, interp_tab(le["zb"], ax) - z0 - le["slope"] * (interp_tab(le["y"], ax) - yo)
                 - 5.0 * np.maximum(2.05 - yo, 0) - 5.0 * np.maximum(ax - 0.72, 0), 0.003)
        # tail: the tail lamp's dark middle set in (01 rear, 03); the rear overhang's underside up inboard (REAR_FLOOR)
        qt = wrap_q(x, y, TAIL_C, front=False)
        yt = y - tail_bow(x)                    # the tail's own y: its features keep their place on the bow
        aft = ss((-2.00 - yt) / 0.03) * ss((1.0 - qt) / 0.08)
        lt = tail_lamp_top(x, y)
        rb = lt - TAIL_LAMP[2]
        fl, fx, fw = REAR_FLOOR
        yf = y - bumper_bow(x) * ss((-1.75 - y) / 0.10)
        d = smax(d, interp_tab(fl, yf) - 0.3 * (1 - ss((fx + fw - x) / fw)) - z, 0.008)
        dx, dz0, dz1, dd = DIFFUSER
        zs = tail_zs(x, y, z)                   # (in the profile's z: over the small lower lip)
        d = d + dd * (ss((dx - x) / 0.012) * ss((zs - dz0) / 0.004) * ss((dz1 - zs) / 0.004)
                      * ss((-2.06 - yt) / 0.02))
        # the recess's steps sit 4-7 mm inside its outline's cuts (a cut along a step runs grazing: mm off)
        return d + aft * TAIL_LAMP[4] * (ss((TAIL_LAMP[3][0] - 0.004 - x) / 0.006) * ss((z - rb - 0.004) / 0.003)
                                          * ss((lt - 0.004 - z) / 0.003))


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


def crease_snap(f, v, lo, h, eps=2e-4, tol=0.02):
    """Where the field has a hard crease (Field.corner): each surface nets cell the crease passes through (its
    corners straddle both f = 0 and d1 = d2) gets its vertex on the crease (Newton on both, min norm steps), so
    the mesh's edges follow it (a dual contouring of the one sharp feature). lo: the cells' low corners.
    Returns the snapped vertex indices."""
    cand = np.nonzero(f.corner(v[:, 1], v[:, 2]) > 0.98)[0]
    if not len(cand):
        return cand
    off = np.array([(i, j, k) for i in (0, 1) for j in (0, 1) for k in (0, 1)], float) * h
    pc_ = (lo[cand][:, None] + off[None]).reshape(-1, 3)
    fv, cv = f(pc_).reshape(-1, 8), f.crease(pc_).reshape(-1, 8)
    cand = cand[(fv.min(1) < 0) & (fv.max(1) >= 0) & (cv.min(1) < 0) & (cv.max(1) >= 0)]
    p = lo[cand] + 0.5 * h                  # from the cell's centre: the crease point in it, not the vertex's nearest
    for _ in range(12):
        F = np.stack([f(p), f.crease(p)], 1)
        J = np.stack([np.stack([(fn(p + e) - fn(p - e)) / (2 * eps) for e in np.eye(3) * eps], 1)
                      for fn in (f, f.crease)], 1)                        # (n, 2, 3)
        JJ = J @ J.transpose(0, 2, 1)
        dp = (J.transpose(0, 2, 1) @ np.linalg.solve(JJ + 1e-12 * np.eye(2), F[..., None]))[..., 0]
        p = p - dp
    F = np.abs(np.stack([f(p), f.crease(p)], 1)).max(1)
    ok = ((F < 1e-6) & ((p > lo[cand] - tol * h) & (p < lo[cand] + (1 + tol) * h)).all(1)
          & (f.corner(p[:, 1], p[:, 2]) > 0.98))
    v[cand[ok]] = p[ok]
    return cand[ok]


def body_mesh(h=CELL, field=None):
    """The body's zero level: field, vertices, triangles (x symmetric: the grid's x nodes straddle 0)."""
    f = field or Field()
    n = int(math.ceil(GRID["half"] / h))
    org = np.array([-(n - 0.5) * h, GRID["y"][0], GRID["z"][0]])
    v, q = surface_nets(f, h, ((-(n - 0.5) * h, (n - 0.5) * h), GRID["y"], GRID["z"]))
    lo = org + np.floor((v - org) / h) * h                  # each vertex's cell (surface nets: inside it)
    v = project(f, v, cap=0.5 * h)
    v0 = v.copy()
    on = np.zeros(len(v), bool)
    on[crease_snap(f, v, lo, h)] = True
    t = np.concatenate([q[:, [0, 1, 2]], q[:, [0, 2, 3]]])
    alt = np.concatenate([q[:, [0, 1, 3]], q[:, [1, 2, 3]]])
    # split each quad along its shorter diagonal (fewer slivers); round the tail's crease the diagonal whose two
    # triangles face out best (field normal at their centres): the other one folds the quad over the crease, or
    # leaves a flat triangle along it. Where neither does (the crease through all four cells round a grid edge) its
    # vertex moved furthest goes back
    d02 = np.linalg.norm(v[q[:, 0]] - v[q[:, 2]], axis=1)
    d13 = np.linalg.norm(v[q[:, 1]] - v[q[:, 3]], axis=1)
    use13 = d13 < d02
    m = len(q)

    def facing(tt):
        n = np.cross(v[tt[:, 1]] - v[tt[:, 0]], v[tt[:, 2]] - v[tt[:, 0]])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-15)
        return (n * gradient(f, v[tt].mean(1))).sum(1)
    for _ in range(4):
        near = np.nonzero(on[q].any(1))[0]
        if not len(near):
            break
        q02 = np.minimum(facing(t[near]), facing(t[near + m]))
        q13 = np.minimum(facing(alt[near]), facing(alt[near + m]))
        use13[near] = q13 > q02
        bad = near[np.maximum(q02, q13) < 0.2]
        if not len(bad):
            break
        mv = np.where(on[q[bad]], np.linalg.norm(v[q[bad]] - v0[q[bad]], axis=2), -1.0)
        back = q[bad, np.argmax(mv, 1)]
        v[back], on[back] = v0[back], False
    use = np.tile(use13, 2)
    t[use] = alt[use]
    return f, v, t


# ---- regions: every outline is a zero level of a function of position only (no normals), cut into the mesh
# (split_mesh) and tested at the face centres with the same function, so the region edges are the cut curves
def windshield(x, y):
    """Cowl and top edges (y at x) and the side edge (|x| at y)."""
    (s0y, s0x), (s1y, s1x) = WINDSHIELD["side"]
    return (interp_tab(WINDSHIELD["cowl"], np.abs(x)), interp_tab(WINDSHIELD["top"], np.abs(x)),
            s0x + (y - s0y) / (s1y - s0y) * (s1x - s0x))


def black_top(ax, y):
    """Top of the black lower body: the sill between the arches, FRONT_BLACK round the nose, the tail lamp's lens
    bottom round the tail (the blends sit inside the arch openings)."""
    wn, wt = ss((y - 1.80) / 0.08), ss((-1.66 - y) / 0.08)
    return ((SILL[0] + SILL[1] * y) * (1 - wn - wt) + wn * interp_tab(FRONT_BLACK, wrap_q(ax, y, NOSE_C))
            + wt * (tail_lamp_top(ax, y) - TAIL_LAMP[2]))


def lamp_top(ax, y):
    """Top of the head lamp's light bar: just under the hood's leading edge across the nose; from LAMP[0] on it
    rises straight to the tip under the fender's front face (01 front, 01 side, 02)."""
    q = wrap_q(ax, y, NOSE_C)
    e = hood_cap(ax, np.clip(y, 1.09, 2.08)) - BAR[0]
    (q0, z0), (q1, z1) = LAMP[:2]
    s = ss((q - q0) / 0.10)                     # (eased: a kink where it starts rising is a corner in its cuts)
    return np.minimum(e, (1 - s) * e + s * (z0 + (q - q0) * (z1 - z0) / (q1 - q0)))


def lens_bottom(ax, y):
    """Bottom of the head lamp's dark lens (LAMP[2]; inboard it closes on the bar)."""
    return np.minimum(lamp_top(ax, y) - (BAR[1] - BAR[0]), interp_tab(LAMP[2], wrap_q(ax, y, NOSE_C)))


def door_polygon():
    """The door's outline below the glass (side view (y, z)); its top overlaps the glass by 2 cm."""
    gy, gz = SIDE_GLASS[GLASS_BOTTOM:].T    # the bottom edge only: the top edge's points by the A pillar sorted in
    belt = (gy > DIVIDER[1][0]) & (gy < DOOR[0][0])   # with it zigzag the outline (a saw tooth seam, 01 side)
    bo = np.argsort(gy[belt])
    yf = TYRES["front"]["y"]
    return np.concatenate([np.array(DOOR), [[yf - 0.30, 0.40]], [[yf - 0.43, SILL[0] + SILL[1] * (yf - 0.43)]],
                           [[B_SEAM[1][0], SILL[0] + SILL[1] * B_SEAM[1][0]]], [B_SEAM[1]], [B_SEAM[0]],
                           [[DIVIDER[1][0] + 0.003, B_SEAM[0][1]]], np.stack([gy[belt][bo], gz[belt][bo] + 0.02], 1)])


def divider_y(z):
    (dy0, dz0), (dy1, dz1) = DIVIDER
    return dy0 + (z - dz0) / (dz1 - dz0) * (dy1 - dy0)


def levels(f):
    """{name: g(x, y, z, |x|)}: the region outlines (classify() reads the same functions' signs). A plane only
    needed in one place is bent off the body elsewhere (`far`): a cut running the car's length lands next to other
    cuts at a shallow angle and leaves slivers that mesh non-manifold. No two share a zero set (a cut over a cut)."""
    door, side_glass = round_poly(door_polygon()), round_poly(SIDE_GLASS, 0.016)   # (the quarter glass's 4 cm end)
    bw = BAR[1] - BAR[0]
    qn = lambda ax, y: wrap_q(ax, y, NOSE_C)
    qt = lambda ax, y: wrap_q(ax, y, TAIL_C, front=False)
    far = lambda a: 5.0 * np.maximum(a, 0)
    lt = lambda ax, y: lamp_top(ax, y) - far(1.80 - y)              # head lamp levels: only at the nose
    yt = lambda ax, y: y - tail_bow(ax)                              # tail levels: only at the tail (on its bow)
    sz = lambda ax, y: interp_tab(SPOILER["z"], qt(ax, y)) - far(yt(ax, y) + 1.95)
    (ya, za), (yb, zb) = ((float(in_y(np.array([y_]))[0]), z_) for y_, z_ in FENDER_SEAM)

    def seam_d(y, z):                   # distance in (y, z) to FENDER_SEAM's segment
        dy, dz = yb - ya, zb - za
        s = np.clip(((y - ya) * dy + (z - za) * dz) / (dy * dy + dz * dz), 0, 1)
        return np.hypot(y - ya - s * dy, z - za - s * dz)
    lv = dict(
        glass=lambda x, y, z, ax: poly_sdf(side_glass, y, z) + far(0.40 - ax),
        divider=lambda x, y, z, ax: y - divider_y(z),
        pillar=lambda x, y, z, ax: np.abs(y - divider_y(z)) - B_PILLAR + far(0.40 - ax) + far(1.0 - z),
        cowl=lambda x, y, z, ax: y - windshield(x, y)[0], ws_top=lambda x, y, z, ax: y - windshield(x, y)[1],
        ws_side=lambda x, y, z, ax: ax - windshield(x, y)[2],
        ws_z=lambda x, y, z, ax: (z - WINDSHIELD["z"] + 0.08 * ss((y - 1.10) / 0.03) - far(-y)
                                  - far(y - 1.40)),   # (round 13: the pane to y 1.352; ahead of 1.10 at 0.80, under
        # the pane's corners: at 0.88 it ran on the fender top's 0.877-0.889 behind the A pillar, slivers, a hole)
        black=lambda x, y, z, ax: z - black_top(ax, y),
        nose=lambda x, y, z, ax: y - 1.82,
        lamp_end=lambda x, y, z, ax: (qn(ax, y) - LAMP[1][0] - LAMP[3] * (z - LAMP[1][1]) + far(0.58 - z)
                                      + far(z - 0.76) + far(1.70 - y)),
        bar_top=lambda x, y, z, ax: z - lt(ax, y), bar_bot=lambda x, y, z, ax: z - lt(ax, y) + bw,
        bar_gap=lambda x, y, z, ax: z - lt(ax, y) - BAR[0] + BAR[2],
        lens_bot=lambda x, y, z, ax: z - lens_bottom(ax, y) + far(1.80 - y),
        # (round 11: on the side 3 cm further back, the band's front end at y -1.794: 01 side)
        aft=lambda x, y, z, ax: yt(ax, y) + 2.0 + 0.030 * ss((ax - 0.70) / 0.04),
        lip=lambda x, y, z, ax: z - SPOILER["top"] + far(yt(ax, y) + 1.95),   # the strip's top: the deck's rear edge
        spoiler=lambda x, y, z, ax: z - sz(ax, y),
        # the strip's lenses: a box rounded 4 mm (its bottom a distance too: a plateau over a steep bend reads cm off
        # its cut; a sharp corner 2.4 mm), bent off over the deck (a closed loop)
        spoiler_lamp=lambda x, y, z, ax: (smax(np.abs(ax - sum(SPOILER["lamp"][0]) / 2)
                                               - (SPOILER["lamp"][0][1] - SPOILER["lamp"][0][0]) / 2,
                                               SPOILER["top"] - SPOILER["lamp"][1] - z, 0.004)
                                          + far(z - 0.95) + far(yt(ax, y) + 1.95)),
        # the tail face | side (Field.crease; its vertices snapped on, body_mesh): the band's red, the strip's ends.
        # Under the step the lip's corner rounds off tangent to the side (d1 - d2 ~ 0 for cm, its cut mm off): there
        # a plane across at the crease's foot, added with the sign d1 - d2 has on face and side (no new zero set
        # there). Ahead of the corner bent under (the side stays negative; across the deck a closed loop)
        crease=lambda x, y, z, ax: (f.crease(np.stack([x, y, z], 1)) - far(y - in_y(TAIL_CREASE["hard"][0]))
                                    + (1 - ss((z - TAIL_CREASE["step"][0])
                                              / (TAIL_CREASE["step"][1] - TAIL_CREASE["step"][0])))
                                    * (in_y(TAIL_CREASE["foot"]) - y)),
        # the lens' segments: bent up off the body over the lens (the tailgate's side seam runs down the face)
        tail_red=lambda x, y, z, ax: ax - TAIL_LAMP[3][1] - far(yt(ax, y) + 2.0) - far(z - 0.575),
        tail_top=lambda x, y, z, ax: z - tail_lamp_top(ax, y) + far(yt(ax, y) + 1.95),   # also the tailgate's bottom
        tail_mid=lambda x, y, z, ax: ax - TAIL_LAMP[3][0] - far(yt(ax, y) + 2.0) - far(z - 0.575),
        liner=lambda x, y, z, ax: f.well(ax, y, z) - 0.010,   # over the lip's rounding, past its tangent start
        door=lambda x, y, z, ax: poly_sdf(door, y, z) + far(0.35 - ax),
        trunk_y=lambda x, y, z, ax: y - TRUNK_Y,
        trunk_x=lambda x, y, z, ax: ax - interp_tab(TRUNK_PLAN, y) + far(0.50 - z) + far(y - TRUNK_Y),
        hood_x=lambda x, y, z, ax: ax - interp_tab(HOOD_SEAM, y) + far(0.56 - z) + far(0.99 - y),   # (it meets the
        # cowl at the windshield's corner, y 1.098; bent away behind that: bent where it meets it, the cuts ran together;
        # bent off under the bar, round 11 at 0.56: at 0.60 the bend lay on the lowered bar's cuts, a crack)
        # the hood's leading edge only (y > 1.85): further back the surface dips under the cap beside the seams and
        # the cut ran there, its rear edge a seam ahead of the windshield (a flat strip, 01 front); now the cowl
        hood_z=lambda x, y, z, ax: (z - hood_cap(ax, np.clip(y, 1.09, 2.08)) + BAR[0] + far(1.85 - y)
                                    + far(ax - 0.62 - 4 * np.maximum(1.9 - y, 0))),   # (off the fenders at the nose)
        # the port's outline: its four lines bent off the body beyond the box (not up the whole tail face)
        port_x0=lambda x, y, z, ax: x - PORT[0] + far(yt(ax, y) + 2.0) + far(4 * (z - 0.505)) + far(0.30 - z),
        port_x1=lambda x, y, z, ax: x - PORT[1] + far(yt(ax, y) + 2.0) + far(4 * (z - 0.505)) + far(0.30 - z),
        port_z0=lambda x, y, z, ax: z - PORT[2] + far(yt(ax, y) + 2.0) + far(x + 0.50) + far(-0.745 - x),
        port_z1=lambda x, y, z, ax: z - PORT[3] + far(yt(ax, y) + 2.0) + far(x + 0.50) + far(-0.745 - x),
        # the short seam from the head lamp's outer end back to the arch: a closed slot (round ends) on the side, its
        # inside a dark line (grooves(); nothing open-ended: a plane cut stopped short would run on somewhere)
        fender_seam=lambda x, y, z, ax: seam_d(y, z) - GROOVE[0] + far(0.70 - ax))
    # round 13: every outline read where the body is (nose_wy: the face's lamps, bar, black and seams set back with it)
    return {k: (lambda g: lambda x, y, z, ax: g(x, nose_wy(ax, y, z), z, ax))(g) for k, g in lv.items()}


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
    bpil = in_side & s["pillar"]
    glass = ws | (in_side & ~bpil)
    mat[glass] = 1
    # black: lower body round the nose and tail; the duck lip's rear face, from crease to crease (two lighter lens
    # segments along its top); tail lamp lens: dark middle, light grey (reversing) lens, red from TAIL_LAMP[3][1] on
    # round the corner and along the side (round 12, Main's tail correction: 01 rear, 01 side, 03)
    aft = s["aft"]
    face = ~s["crease"]
    spoil = aft & ~s["spoiler"] & s["lip"] & face
    slamp = spoil & s["spoiler_lamp"]
    tl = aft & ~s["black"] & s["tail_top"]
    mat[s["black"] | spoil | (tl & s["tail_mid"])] = 2
    mat[tl & ~s["tail_mid"] & s["tail_red"]] = 1   # glass (its pane: none; split out with the body's glass below)
    mat[tl & ~s["tail_red"]] = 5
    mat[slamp] = 1
    # head lamps: the light bar under the leading edge, the dark lens under it toward the corners, wrapping onto
    # the side (01 front, 02)
    nose = ~s["nose"] & s["lamp_end"]
    bar = nose & s["bar_top"] & ~s["bar_bot"]
    lens = nose & s["bar_bot"] & ~s["lens_bot"]
    shadow = nose & ~s["bar_top"] & s["bar_gap"]     # the leading edge's shadow line over the bar (01 front)
    mat[lens | shadow] = 2
    mat[bar] = 4
    liner = s["liner"] & ~s["black"]                 # (under the black's top the wheel house is black: there the liner's
    # cut ran into the floor and the inner wall's corner, mm off)
    mat[liner | bpil] = 3
    # panels
    pan = np.zeros(len(t), np.int8)
    in_dg = in_side & ~s["divider"]
    door = ((s["door"] & ~s["liner"] & ~s["black"] & ~(in_side & s["divider"])) | in_dg) & ~liner   # (not the
    # quarter glass the outline's top reaches into)
    pan[door] = np.where(x[door] < 0, 1, 2)
    tg = s["trunk_y"] & s["trunk_x"] & ~s["tail_top"] & ~liner & ~glass & ~s["black"]   # (round 11: the black trim
    # behind the rear arch went up with the tailgate, CybercabCar)
    pan[tg | spoil] = 3              # (round 12: the strip whole, out to the creases: split at the seam's |x| its two
    # black pieces met in a groove ring over the strip's ends, 03 / rear 3/4; now gold | black, no groove)
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
    pane[slamp] = 6
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


def boundary_off(f, v, t, key, tol=5e-4):
    """Region outlines that left their cut: on every edge between two regions (key: classify()'s material, panel,
    pane), its ends farther than tol from every levels() zero set, its middle farther than tol from its ends' own
    zero set, as a distance |g| / |grad g| on the left half, read on the surface (a chord's middle sits under it).
    An edge from one cut to another spans the corner where they meet: its middle lies on neither (not counted).
    Returns (points, distances) of the misses."""
    ue, fa, fb = edge_faces(t)
    o = np.maximum(fb, 0)
    e2 = ue[(fb >= 0) & (key[fa] != key[o])]
    ends, inv = np.unique(e2, return_inverse=True)
    inv = inv.reshape(-1, 2)
    q = np.concatenate([v[ends], v[e2].mean(1)])
    x, y, z = project(f, np.c_[-np.abs(q[:, 0]), q[:, 1], q[:, 2]]).T
    e = 1e-4
    dd = []
    for g in levels(f).values():
        ev = lambda dx, dy, dz: g(x + dx, y + dy, z + dz, np.abs(x + dx))
        gn = np.sqrt(sum(((ev(*s) - ev(*(-np.array(s)))) / (2 * e)) ** 2 for s in np.eye(3) * e))
        dd.append(np.abs(ev(0, 0, 0)) / np.maximum(gn, 1e-9))
    dd = np.stack(dd, 1)
    de, dm = dd[:len(ends)], dd[len(ends):]
    own = de.argmin(1)[inv]                          # each end's nearest cut
    same = own[:, 0] == own[:, 1]
    d = np.concatenate([de.min(1), np.where(same, dm[np.arange(len(dm)), own[:, 0]], 0.0)])
    return q[d > tol], d[d > tol]


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
    each lens and the red side marker ahead of the front wheel (left; mirrored)."""
    out = {}
    x0, z0, z1, hw_ = PLATE
    yf = ray_point(f, [0, 2.6, (z0 + z1) / 2], [0, -1, 0])[0][0, 1]
    # (round 11: 7 mm further out, its face at the body's tip: triangulated 1.1-2.1 cm out, the length held)
    out["PlateHolder"] = box((-hw_ - 0.008, yf - 0.03, z0 - 0.008), (hw_ + 0.008, yf + 0.015, z1 + 0.008))
    out["Plate"] = box((-hw_, yf + 0.007, z0), (hw_, yf + 0.018, z1))
    it = INTAKE
    za, zb = it["z"]
    xs = np.linspace(-0.58, 0.58, 30)
    zl = np.linspace(za, zb, 6)
    # (round 13: the opening's back read at each slat's height: with the face set back by z, NOSE_SET, one read at
    # the middle left the lower slats 1-2 cm proud of the opening, 01 side row 820)
    yz = [ray_point(f, np.stack([xs, np.full(30, 2.6), np.full(30, zz)], 1), [0, -1, 0])[0][:, 1]
          for zz in np.clip(zl, za + 0.006, zb - 0.006)]
    yb = np.min(yz, axis=0)
    # the face over the opening: the bars stay 6 mm behind it (round 13: toward the opening's ends, where its depth
    # eases out, the bars stood 1.2 cm proud of the set-back face, 01 side rows 816-824; under the opening the face
    # is set back further still, NOSE_SET)
    yo = ray_point(f, np.stack([xs, np.full(30, 2.6), np.full(30, zb + 0.012)], 1), [0, -1, 0])[0][:, 1] - 0.006
    bars = []
    # a fine dark grid set well back in the opening (01 front: thin slats, never level with the face)
    for zz, yr in zip(zl[1:-1], yz[1:-1]):                       # horizontal slats
        xi = it["x"][1] + (it["x"][0] - it["x"][1]) * (zz - za) / (zb - za) - 0.03   # clear of the opening's edge
        for i in range(29):
            a, b = max(xs[i], -xi), min(xs[i + 1], xi)
            if a < b:
                y1 = min(yr[i] + 0.012, yr[i + 1] + 0.012, yo[i], yo[i + 1])
                bars.append(box((a, y1 - 0.016, zz - 0.0015), (b, y1, zz + 0.0015)))
    for xx in np.linspace(-0.48, 0.48, 17):                     # dividers
        y1 = min(np.interp(xx, xs, yb) + 0.012, np.interp(xx, xs, yo))
        bars.append(box((xx - 0.0015, y1 - 0.016, za + 0.004), (xx + 0.0015, y1, zb - 0.004)))
    out["Grille"] = merge(bars)
    yc = np.interp(0.0, xs, yb) + 0.018
    a = np.linspace(0, 2 * np.pi, 12, endpoint=False)
    ring = np.stack([0.016 * np.cos(a), np.zeros(12), (za + zb) / 2 + 0.016 * np.sin(a)], 1)
    cv = np.concatenate([ring + [0, yc - 0.03, 0], ring + [0, yc, 0], [[0, yc + 0.004, (za + zb) / 2]]])
    ct = [(i, (i + 1) % 12, 12 + (i + 1) % 12) for i in range(12)] + [(i, 12 + (i + 1) % 12, 12 + i) for i in range(12)]
    ct += [(12 + i, 12 + (i + 1) % 12, 24) for i in range(12)]
    out["FrontCamera"] = (cv, np.array(ct)[:, ::-1])
    # lamp dots: along the lens' middle (left lamp)
    xc, yc0, r = NOSE_C
    dots = []
    for q in np.linspace(0.58, 0.98, LAMP_DOTS):
        th = (q - xc) / r
        o = np.array([[-(xc + 0.8 * np.sin(th)), yc0 + 0.8 * np.cos(th), 0.66]])
        dr = np.array([[np.sin(th), -np.cos(th), 0.0]])
        for _ in range(2):                                     # the lens middle's z at the surface point
            p, n = ray_point(f, o, dr)
            ax_ = np.abs(p[:, 0])
            y_ = nose_wy(ax_, p[:, 1], p[:, 2])                # (round 13: where the lamp's outlines are read)
            o[:, 2] = (lamp_top(ax_, y_) - (BAR[1] - BAR[0]) + lens_bottom(ax_, y_)) / 2
        p, n = ray_point(f, o, dr)
        dots.append(quad_on(p[0], n[0], 0.003, 0.002, 0.001))
    out["LampDots"] = merge(dots)
    out["SideMarker"] = side_marker(f)
    return out


def side_marker(f):
    """The red strip ahead of the left front wheel (SIDE_MARKER): rows up the arch's front edge, each from the liner's
    cut + gap forward, on the first surface seen from outside (the skin, never the arch's inside), lifted off it."""
    sm = SIDE_MARKER
    zs = np.linspace(*sm["z"], sm["rows"])
    lo, hi = np.full(sm["rows"], in_y(1.80)), np.full(sm["rows"], in_y(1.95))
    for _ in range(30):                          # the liner's cut: f.well 0.010 (the `liner` level) along the skin
        mid = (lo + hi) / 2
        p, _n = ray_point(f, np.c_[np.full(sm["rows"], -1.2), mid, zs], [1, 0, 0], far=0.8)
        ahead = f.well(np.abs(p[:, 0]), p[:, 1], p[:, 2]) > 0.010
        hi, lo = np.where(ahead, mid, hi), np.where(ahead, lo, mid)
    y0 = out_y(hi) + sm["gap"]
    y1 = y0 + np.interp(zs, sm["z"], sm["w"])
    ys = in_y(np.stack([y0, y1], 1)).ravel()
    p, n = ray_point(f, np.c_[np.full(len(ys), -1.2), ys, np.repeat(zs, 2)], [1, 0, 0], far=0.8)
    r = 2 * np.arange(sm["rows"] - 1)[:, None]
    return p + n * sm["lift"], np.concatenate([r + [0, 1, 3], r + [0, 3, 2]])
    return out


def rear_parts(f):
    """The tailgate camera in the duck lip's black face (01 rear)."""
    zc = 0.901                                                   # (triangulated: 02 / 03 / x253 / x59)
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


def tyre_profile(r, w, rim, bulge=0.008):
    """Half section (lateral from the tyre's middle, radius) from the inner bead round the tread to the outer bead.
    The sidewall bulges `bulge` past the bead line at mid height: over the cover's ring (02, 03 see the covers 5-8 %
    smaller than 01 side's 0.338: the bulge hides their edge at a slant)."""
    side = r - rim
    pts = [(-w / 2 + 0.016, rim), (-w / 2 + 0.004, rim + 0.22 * side), (-w / 2 - bulge, rim + 0.50 * side),
           (-w / 2 + 0.002 - bulge, rim + 0.72 * side), (-w / 2 + 0.014, rim + 0.88 * side),
           (-w / 2 + 0.030, r - 0.004), (-w / 2 + 0.050, r)]   # a round shoulder (02, 03: the sidewall reads as a
    return pts + [(-x, rr) for x, rr in pts[::-1]]        # black ring round the cover)


def wheel_parts(seg=72):
    """{name: (vertices, triangles)}: Tyre_<FL|FR|RL|RR> and Cover_<...> in place (the car frame)."""
    out = {}
    for axle, tag in (("front", "F"), ("rear", "R")):
        ty = TYRES[axle]
        r, w, rim, xc, rc = ty["r"], ty["w"], ty["rim"], WHEEL_X[axle], COVER_R[axle]
        # the cover reaches out over the sidewall (01 side: 0.85 of the tyre's radius); the sidewall's bulge stands
        # 2 mm past the cover's ring, over its edge (tyre_profile)
        mid = xc - 0.006 - w / 2
        tv, tq = revolve(tyre_profile(r, w, rim), seg)
        # cover (01 side, 02): a flat outer ring, a thin step down to a near flat disc and a small centre bump
        # (official: no visible dish; a coarse dish profile shades as rings); (lateral from WHEEL_X, radius)
        cprof = [(-0.016, rc - 0.010), (-0.006, rc), (-0.004, 0.975 * rc), (-0.003, 0.955 * rc),
                 (-0.0025, 0.75 * rc), (-0.0015, 0.45 * rc), (-0.0005, 0.16 * rc), (0.002, 0.11 * rc),
                 (0.006, 0.06 * rc), (0.0075, 0.0005)]
        cv, cq = revolve(cprof, seg)
        cv[:, 0] += xc - mid
        for lr, sx in (("L", -1), ("R", 1)):
            for nm, (vv, qq) in (("Tyre", (tv, tq)), ("Cover", (cv, cq))):
                p = vv.copy()
                p[:, 0] = sx * (mid + p[:, 0])
                p[:, 1] += out_y(ty["y"])
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
    vertices and a per-face flag (the groove's faces: shaded flat): the whole band between the two side cuts,
    grown from the faces on the seam (only those would end on the surface mesh's own vertices inside the band, a
    wavy dark edge). The tailgate's sides down the tail face stay a panel edge only (01 rear, 03: no line shows
    there, the gap hides in the corner)."""
    ue, fa, fb = edge_faces(t)
    o = np.maximum(fb, 0)
    seam = (fb >= 0) & (pan[fa] != pan[o]) & (mat[fa] == mat[o]) & (mat[fa] != MATS.index("Glass"))
    c = v[ue].mean(1)
    seam &= ~((c[:, 1] - tail_bow(np.abs(c[:, 0])) < -2.06) & (c[:, 2] > 0.50) & (c[:, 2] < 0.90)   # (round 11: from
              & (np.abs(c[:, 0]) > 0.5))      # the band's top, a notch was left over it: 03)
    vb = np.unique(ue[seam])
    cc = v[t].mean(1)
    lv = levels(f)
    band = np.min([np.abs(lv[k](cc[:, 0], cc[:, 1], cc[:, 2], np.abs(cc[:, 0]))) for k in SEAMS], 0) < GROOVE[0]
    # ... and beside a seam (within ~3-8 mm of its vertices: 3 mm cells, the 27 round each): the bands follow their
    # levels past the panels' outlines (across the bumper face)
    key = lambda p: (np.floor(p / 0.003).astype(np.int64) + 2 ** 20) @ np.array([1, 2 ** 21, 2 ** 42], np.int64)
    marked = np.unique(key(v[vb]))
    cell = np.floor(cc / 0.003).astype(np.int64) + 2 ** 20
    near = np.zeros(len(t), bool)
    for off in np.stack(np.meshgrid(*[[-1, 0, 1]] * 3), -1).reshape(-1, 3):
        near |= np.isin((cell + off) @ np.array([1, 2 ** 21, 2 ** 42], np.int64), marked)
    band &= near
    flag = np.isin(t, vb).any(1) & band          # (at a seam's end its vertex fans out past the side cuts)
    inner = fb >= 0
    while True:                       # grow across shared edges, inside the band, never onto the glass
        add = np.zeros(len(t), bool)
        add[fb[inner & flag[fa]]] = True
        add[fa[inner & flag[o]]] = True
        add &= band & ~flag & (mat != MATS.index("Glass"))
        if not add.any():
            break
        flag |= add
    # the fender's short seam (FENDER_SEAM): the slot's faces, flush (its 5 mm sits between two cuts, no vertex inside)
    flag |= (lv["fender_seam"](cc[:, 0], cc[:, 1], cc[:, 2], np.abs(cc[:, 0])) < 0) & (mat == MATS.index("Paint"))
    v = v.copy()
    v[vb] -= gradient(f, v[vb]) * GROOVE[1]
    return v, flag


def region_loop(v, ue, fa, fb, sel):
    """The outline of the faces sel (edges between them and the rest) chained into its longest closed loop,
    resampled to ~1 cm (metres). Walked edge by edge: where the region touches itself at a vertex (round 12: the side
    red's rear end at the crease's foot) the walk runs on through it (by vertex it stopped there, half the loop lost)."""
    a, b = sel[fa], np.where(fb >= 0, sel[np.maximum(fb, 0)], False)
    edges = ue[a != b]
    nb = {}
    for k, (i, j) in enumerate(edges):
        nb.setdefault(i, []).append(k)
        nb.setdefault(j, []).append(k)
    used, best = np.zeros(len(edges), bool), []

    def walk(s):
        loop, cur = [s], s
        while True:
            nxt = [k for k in nb[cur] if not used[k]]
            if not nxt:
                return loop
            used[nxt[0]] = True
            i, j = edges[nxt[0]]
            cur = j if i == cur else i
            loop.append(cur)

    for s in nb:
        loop, n = walk(s), 0
        while n < len(loop):            # a lobe left at a pinch: walked from it and spliced in there
            if any(not used[k] for k in nb[loop[n]]):
                loop = loop[:n] + walk(loop[n]) + loop[n + 1:]
            n += 1
        if len(loop) > 1 and loop[-1] == s:
            loop.pop()                      # (closed: back at its start)
        best = loop if len(loop) > len(best) else best
    p = v[best]
    keep = [0]
    for i in range(1, len(p)):
        if np.linalg.norm(p[i] - p[keep[-1]]) >= 0.01:
            keep.append(i)
    return p[keep].round(4).tolist() + [p[0].round(4).tolist()]


def seam_loops(f, v, t, mat, pan, pane):
    """The cut lines for the build: each panel's outline (the door on the car's left, the right one mirrored); and
    for the game's lamp zones (round 11) the tail lamp's parts: red on each side, the grey lens each side of the
    dark middle, the dark middle, the strip's two lens segments (tail lamps: red and grey; brake: middle, strip)."""
    ue, fa, fb = edge_faces(t)
    out = {}
    for key, pid in (("door_left", 1), ("trunk", 3), ("hood", 4), ("charge_port", 5)):
        out[key] = region_loop(v, ue, fa, fb, pan == pid)
    out["door_right"] = [[-q[0], q[1], q[2]] for q in out["door_left"]]
    out["charge_port_centre"] = np.array(out["charge_port"]).mean(0).round(4).tolist()
    c = v[t].mean(1)
    lv = levels(f)
    s = {k: lv[k](c[:, 0], c[:, 1], c[:, 2], np.abs(c[:, 0])) < 0 for k in ("aft", "black", "tail_top", "tail_mid")}
    left = c[:, 0] < 0
    for side, m in (("left", left), ("right", ~left)):
        out[f"tail_lamp_side_red_{side}"] = region_loop(v, ue, fa, fb, (mat == MATS.index("TailLight")) & m)
        out[f"tail_lamp_grey_{side}"] = region_loop(v, ue, fa, fb, (mat == MATS.index("Glass")) & (pane == 5) & m)
        out[f"spoiler_lamp_{side}"] = region_loop(v, ue, fa, fb, (pane == 6) & m)
    out["tail_lamp_centre"] = region_loop(v, ue, fa, fb, s["aft"] & ~s["black"] & s["tail_top"] & s["tail_mid"])
    return out


def tail_red_outline(f):
    """The official tail lamp's red part on the car's left (TAIL_RED_GAME), for the game's texture: a closed loop
    on the side surface, top / bottom at its front end, then bottom / top at the crease (metres)."""
    (z0f, z1f), (z0c, z1c) = TAIL_RED_GAME["z"]
    yf, yc = in_y(np.array(TAIL_RED_GAME["y"]))
    p = side_point(f, np.array([yf, yf, yc, yc]), np.array([z1f, z0f, z0c, z1c]))[0]
    return np.concatenate([p, p[:1]]).round(4).tolist()


def build(h=CELL):
    """Everything numpy: {'field', 'v', 't', 'mat', 'pan', 'pane', 'groove', 'boundary', 'parts', 'wheels', 'lines'}
    (boundary: boundary_off() on the cut mesh, before the grooves move the seams; the decimation keeps every
    outline vertex and edge)."""
    f, v, t = body_mesh(h)
    lv = levels(f)
    cuts = list(lv.values()) + [(lambda g, s: lambda x, y, z, ax: g(x, y, z, ax) - s)(lv[k], s)
                                for k in SEAMS for s in (-GROOVE[0], GROOVE[0])]
    for g in cuts:
        v, t = split_mesh(f, v, t, g(v[:, 0], v[:, 1], v[:, 2], np.abs(v[:, 0])))
    v, t = weld(v, t)
    mat, pan, pane = classify(f, v, t)
    boundary = boundary_off(f, v, t, mat.astype(np.int32) * 64 + pan * 8 + pane + 1)
    lines = seam_loops(f, v, t, mat, pan, pane)
    lines["tail_lamp_red_left"] = tail_red_outline(f)
    v, groove = grooves(f, v, t, mat, pan)
    mat = np.where(groove, MATS.index("Trim"), mat)        # the seams read as thin dark lines (a gap), not facets
    cam_v, cam_s, cam_l = fender_camera(f)
    btn_v, btn_t = button(f)
    return dict(field=f, v=v, t=t, mat=mat, pan=pan, pane=pane, groove=groove, boundary=boundary,
                parts=dict(camera=(cam_v, cam_s, cam_l), button=(btn_v, btn_t), front=front_parts(f),
                           rear=rear_parts(f)), wheels=wheel_parts(), lines=lines)


# ---- Blender
COLORS = dict(Paint=((0.76, 0.54, 0.25), 0.80, 0.36), Glass=((0.03, 0.035, 0.04), 0.0, 0.15),   # satin gold
              Trim=((0.035, 0.035, 0.038), 0.0, 0.55), Liner=((0.015, 0.015, 0.016), 0.0, 0.85),
              HeadLight=((0.92, 0.94, 0.96), 0.0, 0.15), TailLight=((0.22, 0.012, 0.018), 0.0, 0.25),
              Tyre=((0.02, 0.02, 0.022), 0.0, 0.8), Cover=((0.76, 0.54, 0.25), 0.80, 0.36),
              Plate=((0.55, 0.56, 0.58), 0.0, 0.5), Marker=((0.42, 0.13, 0.02), 0.0, 0.35))
# small parts: material, mirrored to the right side
PARTS = dict(PlateHolder=("Trim", False), Plate=("Plate", False), Grille=("Trim", False),
             FrontCamera=("Trim", False), LampDots=("Plate", True), SideMarker=("Marker", True),
             RearCamera=("Glass", False))
TARGET = 145000          # body triangles after decimation (both halves together)
PANES = ("Glass_Windshield", "Glass_DoorLeft", "Glass_DoorRight", "Glass_QuarterLeft", "Glass_QuarterRight",
         "Glass_ReverseLens", "Glass_SpoilerLamp")


def uncross(v, t, lab, tol=4e-4):
    """Faces that touch or cross a face they share no vertex with: where two cuts cross at a grazing angle they leave
    vertex pairs 0.1-0.3 mm apart joined by sliver faces, which can touch (A, rear deck) or, stretched by nose B,
    cross (the light bar's end). Merge the closest vertex pair of each such face pair (under tol, v in the output
    frame) and drop the faces that collapse. Returns t, lab and the number of face pairs found."""
    from mathutils.bvhtree import BVHTree
    found = 0
    for _ in range(4):
        tree = BVHTree.FromPolygons(v.tolist(), t.tolist(), all_triangles=True)
        fs = [set(f_) for f_ in t.tolist()]
        pairs = [(a, b) for a, b in {tuple(sorted(p)) for p in tree.overlap(tree)} if not fs[a] & fs[b]]
        if not pairs:
            break
        found += len(pairs)
        remap = np.arange(len(v))
        for a, b in pairs:
            d = np.linalg.norm(v[t[a]][:, None] - v[t[b]][None], axis=2)
            i, j = np.unravel_index(np.argmin(d), d.shape)
            if d[i, j] < tol:
                remap[remap[t[b][j]]] = remap[t[a][i]]
        t = remap[remap[t]]
        keep = (t[:, 0] != t[:, 1]) & (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])
        t, lab = t[keep], lab[keep]
    return t, lab, found


def close_pinholes(t, lab, v, size=6e-3, area=1e-6):
    """Sliver holes (round 11: where the light bar's top meets the hood's edge cut at the lamp's inner end, one edge
    4-5 mm long on one side, three on the other a tenth of a mm off its line: four open edges a side) under `size`
    across and `area` (m^2): filled with a fan of faces wound as their neighbours, labelled as the first. Returns t,
    lab and the number of holes filled."""
    d = t[:, [0, 1, 1, 2, 2, 0]].reshape(-1, 2)
    key = np.sort(d, 1)
    _, inv, cnt = np.unique(key, axis=0, return_inverse=True, return_counts=True)
    one = cnt[inv.ravel()] == 1
    nxt = {int(b): int(a) for a, b in d[one].tolist()}      # the hole runs against its neighbours' edges
    face = {int(b): i // 3 for i, (a, b) in zip(np.nonzero(one)[0], d[one].tolist())}
    have = {tuple(k) for k in key.tolist()}
    seen, add, addl, filled = set(), [], [], 0
    for s in list(nxt):
        if s in seen:
            continue
        loop, i = [s], nxt[s]
        while i != s and i in nxt and len(loop) < 64:
            loop.append(i)
            i = nxt[i]
        seen.update(loop)
        if i != s or len(loop) < 3:
            continue
        p = v[loop]
        a = 0.5 * np.linalg.norm(sum(np.cross(p[k] - p[0], p[k + 1] - p[0]) for k in range(1, len(p) - 1)))
        if np.ptp(p, axis=0).max() < size and a < area:
            for r in range(len(loop)):         # a fan whose diagonals are not edges already (a fin's: non-manifold)
                lr = loop[r:] + loop[:r]
                if not any(tuple(sorted((lr[0], lr[k]))) in have for k in range(2, len(lr) - 1)):
                    break
            else:
                continue
            add += [(lr[0], lr[k], lr[k + 1]) for k in range(1, len(lr) - 1)]
            addl += [lab[face[s]]] * (len(lr) - 2)
            filled += 1
    if add:
        t, lab = np.vstack([t, np.array(add, t.dtype)]), np.concatenate([lab, np.array(addl, lab.dtype)])
    return t, lab, filled


def main():
    import bmesh
    import bpy

    args = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("nose=")] if "--" in sys.argv else []
    out = (args + [OUT_DIR])[0]
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
            # a sliver's face normal read in float32 can turn over the float64 one the facet test used: faceted again
            fn = np.empty(len(tt) * 3, np.float32)
            me.polygons.foreach_get("normal", fn)
            fn = fn.reshape(-1, 1, 3)
            normals = np.where(((normals * fn).sum(2) < 0.05)[..., None], fn, normals)
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
    held |= ((f.corner(hv[:, 1], hv[:, 2]) > 0.98) & (np.abs(f.crease(hv)) < 1e-5)   # the tail's crease
             & (np.abs(f(hv)) < 1e-5))
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
    # one charge port (driver side): the mirror's copy of its groove on the right pulled back onto the surface (a
    # blank face; the game's ambient occlusion would draw the groove as a dark frame)
    rp = ((v[:, 0] > -PORT[1] - 0.04) & (v[:, 0] < -PORT[0] + 0.04) & (v[:, 1] < -1.85) & (v[:, 2] > 0.30)
          & (v[:, 2] < 0.50))
    v[rp] = project(f, v[rp])
    lab = np.where(rp[t].all(1) & (lab // 512 % 2 > 0), lab - 512, lab)
    bpy.data.meshes.remove(body.data)
    fn = np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]])
    # a cut passing a fraction of a mm from a vertex the decimation kept can leave a needle fin (third vertex ~0.1 mm
    # off an edge two other faces share, its own two edges open): drop the tiny faces on 3-face edges
    e = np.sort(t[:, [0, 1, 1, 2, 2, 0]].reshape(-1, 2), 1)
    _, inv, cnt = np.unique(e, axis=0, return_inverse=True, return_counts=True)
    keep = ~((cnt[inv.ravel()].reshape(-1, 3) > 2).any(1) & (np.linalg.norm(fn, axis=1) < 2e-6))
    t, lab = t[keep], lab[keep]
    t, lab, crossed = uncross(out_pts(v), t, lab)
    t, lab, holes = close_pinholes(t, lab, v)
    fn = np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-15)
    # field normals per corner, read a quarter of the way into the face: across a crease the mesh's edges do not
    # follow, each face takes its own side's normal instead of a blend (no saw tooth along the crease) ...
    cen = v[t].mean(1, keepdims=True)
    gv = gradient(f, (0.75 * v[t] + 0.25 * cen).reshape(-1, 3)).reshape(-1, 3, 3)
    nrm = np.where(((gv * fn[:, None]).sum(2) > 0.3)[..., None], gv, fn[:, None])   # ... faceted on sharp tips
    mat, pan, pane, groove = lab // 64 % 8, lab // 8 % 8, lab % 8 - 1, lab // 512 % 2 > 0
    nrm[groove] = fn[groove][:, None]                            # the seam grooves' flanks shade flat
    right = v[t][:, :, 0].mean(1) > 0                            # the mirror copied the left's names
    pan[right & (pan == PANELS.index("DoorFrontLeft"))] = PANELS.index("DoorFrontRight")
    pane[right & (pane == 1)], pane[right & (pane == 3)] = 2, 4
    pan[right & (pan == PANELS.index("ChargePortDoor"))] = PANELS.index("Body")    # one port: driver side
    off, dist = B["boundary"]                                # every region outline on its cut (0.5 mm) ...
    known = np.zeros(len(off), bool)                         # ... but the known misses (BOUNDARY_KNOWN)
    for p, r, dmax in BOUNDARY_KNOWN:
        known |= (np.linalg.norm(np.c_[np.abs(off[:, 0]), off[:, 1:]] - p, axis=1) < r) & (dist < dmax)
    known_at = off[known].round(4).tolist()
    off, dist = off[~known], dist[~known]
    cells, cn = np.unique(np.round(np.c_[np.abs(off[:, 0]), off[:, 1], off[:, 2]], 1).reshape(-1, 3), axis=0,
                          return_counts=True)
    report = dict(objects={}, boundary_off=dict(count=int(len(off)), max_mm=round(float(dist.max(initial=0)) * 1e3, 2),
                                                at=off[np.argsort(-dist)[:40]].round(4).tolist(),
                                                cells=[[*c.tolist(), int(n)] for c, n in
                                                       zip(cells[np.argsort(-cn)[:30]], np.sort(cn)[::-1][:30])]),
                  boundary_known=known_at, nose=NOSE, uncrossed=crossed, pinholes=holes)
    # to the output frame (the checks above ran in the build frame); normals scale y by the stretch's inverse
    jy = out_jy(v[t][:, :, 1])[..., None]
    nrm = nrm * np.concatenate([np.ones_like(jy), 1.0 / jy, np.ones_like(jy)], -1)
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    v = out_pts(v)
    # a sliver the stretch bent past its field normal: that face faceted (B: 2 corners on the bar's shadow line)
    fo = np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]])
    fo /= np.maximum(np.linalg.norm(fo, axis=1, keepdims=True), 1e-15)
    nrm = np.where(((nrm * fo[:, None]).sum(2) < 0.05)[..., None], fo[:, None], nrm)
    for mi, nm in enumerate(MATS):
        for pi, on in enumerate(PANES if nm == "Glass" else (nm,)):
            sel = (mat == mi) & ((pane == pi) if nm == "Glass" else True)
            if sel.any():
                make(on, v, t[sel], nm, panel=pan[sel], normals=nrm[sel])
    # small parts: fender camera housings (paint) and lenses, B pillar buttons (trim)
    cv, cs, cl = B["parts"]["camera"]
    bv, bt = B["parts"]["button"]
    for sx, side in ((-1, "Left"), (1, "Right")):
        p = out_pts(cv * [sx, 1, 1])
        flip = (lambda a: a[:, ::-1]) if sx > 0 else (lambda a: a)
        make(f"FenderCam_{side}", p, flip(cs), "Paint")
        make(f"FenderCamLens_{side}", p, flip(cl), "Trim")
        make(f"Button_{side}", out_pts(bv * [sx, 1, 1]), flip(bt), "Trim")
    for nm, (vv, tt) in {**B["parts"]["front"], **B["parts"]["rear"]}.items():
        mn, mirrored = PARTS[nm]
        for sx, side in (((-1, "_Left"), (1, "_Right")) if mirrored else ((1, ""),)):
            p = out_pts(vv * [-sx if mirrored else 1, 1, 1])          # computed on the left
            ob = make(nm + side, p, tt[:, ::-1] if (mirrored and sx > 0) else tt, mn)
            ob.data.polygons.foreach_set("use_smooth", np.zeros(len(ob.data.polygons), bool))
    for nm, (vv, tt) in B["wheels"].items():
        ob = make(nm, vv, tt, "Tyre" if nm.startswith("Tyre") else "Cover")
        ob.data.polygons.foreach_set("use_smooth", np.ones(len(ob.data.polygons), bool))
    # the side markers on the skin: from every vertex nothing of the body further out along the strip's outward normal,
    # and the skin within lift + 1.5 mm under it (Main round 12: x222 showed the old strip half under the fender and 5
    # of its vertices in the arch)
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromPolygons(v.tolist(), t.tolist(), all_triangles=True)
    buried, off_skin, gap = [], [], []
    for side in ("Left", "Right"):
        me = bpy.data.objects["SideMarker_" + side].data
        for vx in me.vertices:
            p, nv = np.array(vx.co), np.array(vx.normal)
            nv = nv * np.sign(nv[0] * p[0])                          # outward: away from the car's middle
            if tree.ray_cast((p + nv * 1e-4).tolist(), nv.tolist(), 0.5)[0] is not None:
                buried.append(p.round(4).tolist())
            hit = tree.ray_cast(p.tolist(), (-nv).tolist(), SIDE_MARKER["lift"] + 0.0015)
            if hit[0] is None:
                off_skin.append(p.round(4).tolist())
            else:
                gap.append(hit[3])
    report["side_marker"] = dict(buried=buried, off_skin=off_skin,
                                 lift_mm=[round(min(gap, default=0) * 1e3, 2), round(max(gap, default=0) * 1e3, 2)])
    for ob in bpy.context.scene.objects:
        me = ob.data
        report["objects"][ob.name] = len(me.polygons)
    allv = np.concatenate([np.array([tuple(ob.matrix_world @ vv.co) for vv in ob.data.vertices])
                           for ob in bpy.context.scene.objects
                           if not ob.name.startswith(("Tyre", "Cover"))])
    report["body_bbox"] = [allv.min(0).round(4).tolist(), allv.max(0).round(4).tolist()]
    report["body_tris"] = int(sum(n for k, n in report["objects"].items() if not k.startswith(("Tyre", "Cover"))))
    report["panels"] = PANELS
    report["wheels"] = {ax: dict(track_m=round(2 * (WHEEL_X[ax] - 0.006 - TYRES[ax]["w"] / 2), 4),
                                 y=round(float(out_y(TYRES[ax]["y"])), 4),
                                 r=TYRES[ax]["r"], w=TYRES[ax]["w"]) for ax in TYRES}
    report["wheels"]["note"] = "track: front off 01 front's fitted camera, rear x92's rear / front ratio; not official"
    json.dump(report, open(os.path.join(out, "prep_report.json"), "w"), indent=1)
    lines = {k: out_pts(p).round(4).tolist() for k, p in B["lines"].items()}
    json.dump(dict(frame="metres, +Y front, +Z up, -X the car's left, ground 0 (prep_cybercab.py)",
                   **lines), open(os.path.join(out, "cybercab_lines.json"), "w"), indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "cybercab_src.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "cybercab_src.glb"), export_format="GLB")
    print("PREP", report["body_tris"], "body triangles; bbox", report["body_bbox"])
    sm = report["side_marker"]
    print("SIDE_MARKER", len(sm["buried"]), "vertices under the body,", len(sm["off_skin"]), "off the skin; lift",
          sm["lift_mm"], "mm")
    if len(off):
        raise SystemExit(f"BOUNDARY_OFF {len(off)} points, up to {dist.max() * 1e3:.2f} mm off their cut "
                         "(prep_report.json boundary_off)")
    if sm["buried"] or sm["off_skin"]:
        raise SystemExit("SIDE_MARKER: vertices under the body or off the skin (prep_report.json side_marker)")


if __name__ == "__main__":
    main()
