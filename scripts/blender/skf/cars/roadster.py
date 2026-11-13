"""Roadster 2.5 Sport (2012, the last first-generation Roadster): the_86_guy's "2008 Tesla Roadster" (Sketchfab, CC BY
4.0, CREDITS.md). CAR=roadster. Keys as in model_y.py (each is the module constant it sets). SRC is
scripts/blender/skf/prep_roadster.py's output: the source FBX on the 2.5 owner's manual (length, wheelbase, overhangs,
track, height; the 2.5 nose, intakes and diffuser), one object per material, the paint split into shell, doors,
mirrors, hoop, port lid, hood and trunk lid, the hard top as the soft top's strips. A two-seater (SEAT front_only,
template MinidoracatTeslaCore): two doors, the trunk lid, the hood, and the soft top (DOORS SoftTop "stow": strips
over the roll hoop and down into the body, SOFT_TOP). Paints from the 2013 colour chart (PAINT_CHART: no
design-studio renders exist). Grid units, pre-centre frame (+Y front, +Z up, -X car left, ground z 0; SRC_C (0, 0):
grid = the prep's metres x 0.826) unless noted; numbers and sources: temp/plan-next-1114/build/RoadsterBody.md
(knowledge base models-roadster.md).
"""
import math


def _below(a, b):
    """The plane along x through the (|x|, z) points a, b on each side (+x, -x): (point, normal up) (model_3.py)."""
    (x1, z1), (x2, z2) = a, b
    n = math.hypot(z1 - z2, x2 - x1)
    return [((sd * x1, 0, z1), (sd * (z1 - z2) / n, 0, (x2 - x1) / n)) for sd in (1, -1)]


# the 2.5's wide black intake (owner's manual 2-2 front view, tm2013-front-intake-closeup-blue.jpg): its outline
# (|x|, z) over the 2008 smile, flat on top, widest two thirds down, rounding in to the lip (prep NOSE: body colour)
_INTAKE = ((0.0, 0.318), (0.388, 0.318), (0.438, 0.306), (0.496, 0.256), (0.504, 0.223), (0.483, 0.190))
# the corner side intakes (manual 2-2 side view: a slot ahead of the front arch leaning back at the top), (y, z) of
# its front and rear edges' ends
_SLOT = (((1.338, 0.388), (1.429, 0.198)), ((1.289, 0.388), (1.371, 0.198)))


def _edge(a, b, sd):
    """The plane along x through the side-view (y, z) points a, b; normal forward (sd 1) or back (-1)."""
    (y1, z1), (y2, z2) = a, b
    n = math.hypot(z1 - z2, y2 - y1) * sd
    return (0, y1, z1), (0, (z1 - z2) / n, (y2 - y1) / n)


CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_rd",
    NAME="MinidoracatTesla_Roadster",
    SCRIPT_MARK="---- geometry (TeslaRoadster)",
    APP_CAR="app_car_roadster_{}.png",
    # 2.5 owner's manual 10-15: length, body width w/o mirrors (not published: the source's 1,716), height (mid load)
    DIMS=(3.946, 1.716, 1.127),
    PORT_NOTE="real Roadster 2.5: the left rear fender behind the door, owner's manual 2-2 item 2, 5-7",
    # the 2013 tesla.com colour chart's 17 paints in its order (Core.lua Specs colors; skin index is saved: only
    # append after release). No design-studio renders: code None, the ramp from PAINT_CHART. Paint codes (service
    # manual IDENTIFICATION NUMBERS, temp/skf_rd/SOURCE.md 5): 3OG00, 3BU00, 3WT00, 3GY00, 3BK00, -, 2SV00, 2RD00,
    # 2BU00, 2BU01, 2YW00, 2BK00, 1RD00, 1GN00, -, -, -
    PAINTS=[("VeryOrange", None), ("ElectricBlue", None), ("ArcticWhite", None), ("ThunderGray", None),
            ("JetBlack", None), ("LightningGreen", None), ("SterlingSilver", None), ("RadiantRed", None),
            ("GlacierBlue", None), ("TwilightBlue", None), ("BrilliantYellow", None), ("ObsidianBlack", None),
            ("FusionRed", None), ("RacingGreen", None), ("GalacticGray", None), ("MagmaOrange", None),
            ("CosmicBlack", None)],
    # (dark, median, bright) sRGB of each car on the 2013 chart (tm2013-exteriorcolors2.jpg; temp/skf_rd/colors/
    # colors.json: the 5-15 %, 40-60 %, 85-95 % luminance bands of its body panels): convert.py chart_ramp
    PAINT_CHART={
        "VeryOrange": ((200, 95, 2), (231, 120, 10), (245, 149, 41)),
        "ElectricBlue": ((1, 76, 126), (7, 117, 174), (49, 163, 216)),
        "ArcticWhite": ((180, 183, 183), (206, 210, 210), (229, 232, 233)),
        "ThunderGray": ((91, 94, 106), (130, 132, 143), (164, 166, 174)),
        "JetBlack": ((8, 8, 8), (22, 22, 22), (56, 56, 56)),
        "LightningGreen": ((16, 116, 33), (44, 143, 62), (105, 194, 123)),
        "SterlingSilver": ((154, 150, 156), (191, 189, 192), (219, 218, 219)),
        "RadiantRed": ((142, 24, 26), (196, 48, 51), (211, 88, 89)),
        "GlacierBlue": ((84, 109, 133), (127, 148, 168), (173, 194, 212)),
        "TwilightBlue": ((25, 21, 50), (57, 53, 81), (94, 90, 116)),
        "BrilliantYellow": ((205, 156, 21), (232, 186, 34), (245, 207, 78)),
        "ObsidianBlack": ((29, 29, 29), (50, 50, 50), (88, 88, 88)),
        "FusionRed": ((142, 27, 14), (205, 47, 28), (222, 89, 71)),
        "RacingGreen": ((2, 46, 36), (24, 78, 66), (75, 130, 121)),
        "GalacticGray": ((43, 43, 41), (72, 72, 68), (115, 116, 113)),
        "MagmaOrange": ((177, 68, 1), (205, 92, 1), (224, 128, 20)),
        "CosmicBlack": ((5, 6, 12), (26, 26, 36), (62, 63, 74)),
    },
    # offline (no game capture yet): each channel's slope so the skin's paint median x GAIN (pzveh: the game's day
    # screen over the texture) meets PAINT_CHART's median; 1.0 where the skin's median is already 255 (Very Orange,
    # Brilliant Yellow red); the near-black channels take the colour's other slopes (RoadsterBody.md: dE2000 per paint)
    CAL={
        "VeryOrange": ((1.0, 1.049, 1.024), (0.0, 0.0, 0.0)),
        "ElectricBlue": ((1.072, 1.081, 1.063), (0.0, 0.0, 0.0)),
        "ArcticWhite": ((1.027, 1.029, 1.029), (0.0, 0.0, 0.0)),
        "ThunderGray": ((1.07, 1.064, 1.055), (0.0, 0.0, 0.0)),
        "JetBlack": ((1.136, 1.136, 1.136), (0.0, 0.0, 0.0)),
        "LightningGreen": ((1.163, 1.042, 1.118), (0.0, 0.0, 0.0)),
        "SterlingSilver": ((1.043, 1.048, 1.044), (0.0, 0.0, 0.0)),
        "RadiantRed": ((1.061, 1.113, 1.115), (0.0, 0.0, 0.0)),
        "GlacierBlue": ((1.077, 1.058, 1.049), (0.0, 0.0, 0.0)),
        "TwilightBlue": ((1.136, 1.136, 1.083), (0.0, 0.0, 0.0)),
        "BrilliantYellow": ((1.0, 1.036, 1.104), (0.0, 0.0, 0.0)),
        "ObsidianBlack": ((1.093, 1.093, 1.093), (0.0, 0.0, 0.0)),
        "FusionRed": ((1.069, 1.09, 1.136), (0.0, 0.0, 0.0)),
        "RacingGreen": ((1.24, 1.094, 1.103), (0.0, 0.0, 0.0)),
        "GalacticGray": ((1.091, 1.091, 1.088), (0.0, 0.0, 0.0)),
        "MagmaOrange": ((1.031, 1.056, 1.043), (0.0, 0.0, 0.0)),
        "CosmicBlack": ((1.231, 1.182, 1.169), (0.0, 0.0, 0.0)),
    },
    COMPOSITOR_MODEL="",
    OFFICIAL_OPTS="",
    RAMP=dict(t=(0.0, 1.0), u=(0.0, 1.0), wheels=()),   # (official_ramp: unused, no design-studio renders)
    # ---- pzveh: wheel, the Sport's black forged wheel (2013 tesla.com forgedwheel_black.jpg, wheel.png on the car):
    # seven swept blade spokes, gloss black, the silver drilled rotors between them. 16" front (195/50 R16), 17" rear
    # (225/45 R17): rim flange = bead + ~17 mm over the tyre radius
    WHEEL_RIM=0.732,                       # (203.2 + 17) / 300.7
    WHEEL_RIM_REAR=0.735,                  # (215.9 + 17) / 317.15 (convert.py: the rear its own rim)
    WHEEL_SPOKE=dict(n=7, shape=dict(outer=((0.22, 0.045), (0.40, 0.042), (0.70, 0.048), (0.92, 0.060), (1.0, 0.066)),
                                     inner=((1.0, 0.0),)),
                     cap=0.20, cap_n=10, inset=0.010, dish=0.018, depth=0.018, sweep=0.42, at=0.0),
    WHEEL_DISC=dict(rotor=0.64, hat=0.30),
    WHEEL_RGB=dict(spoke=26, cap=22, barrel=14, lip=30, rotor=104, hat=50, dark=10, gap=8, tire=(22, 28), tread=20),
    # ---- pzveh: vehicle script
    OY=0.1978,
    WHEEL_LIFT=0.11,
    # 195/50 R16 front (r 300.7 mm), 225/45 R17 rear (317.2 mm), owner's manual 10-4; widths less wheel_profile's
    # 2 x 2.65 mm bulge (model_3.py). The prep put the outer faces at the manual's track (1,455.6 / 1,484.5)
    TIRE_AXLES=dict(front=(0.3007, 0.1897), rear=(0.31715, 0.2197)),
    WHEEL_INSET=0.0,
    CAB_BOX=(1.10, 0.45, -0.55),
    # two seats (TwoDoorBase.md): passengers / seats behind the door opening's middle by back (front only); low (h)
    # and in the Roadster's own pose (SEAT_POSE): the shared front pose leaves the head over the soft top (seat_head.py)
    SEAT=dict(x=0.242, h=0.27, z=-0.255, back=(0.05,), out=0.30, front_only=True),
    # scripts/seat_anim.py POSES: the whole body leant back further, the thighs lower than the shared front pose
    SEAT_POSE={"front": [("Bip01", 42.0), ("Bip01_L_Thigh", -20.0), ("Bip01_R_Thigh", -20.0)]},
    BODY_W_Z=0.55,
    # doors hinge at their front edge; the trunk lid at its front edge (gas struts, owner's manual 4-6); the hood at
    # the windscreen; the soft top stows into the body behind the roll hoop (SOFT_TOP)
    DOORS={
        "DoorFrontLeft": (-1, (0, 0, 1), -65, 0.8), "DoorFrontRight": (1, (0, 0, 1), 65, 0.8),
        "TrunkDoor": (0, (1, 0, 0), -60, 1.0), "EngineDoor": (0, (1, 0, 0), 55, 1.0),
        "SoftTop": (0, (1, 0, 0), "stow", 4.0),
    },
    GATE_IN=(0.0, 0.9, -0.44),
    GATE_HINGE="front",
    # the soft top's strips (convert.py soft_strips / stow_pose): n strips (prep_roadster.py SOFT); after the top's
    # centre line their front edges follow this path (y, z): a little up over the roll hoop (the strips' sides hang
    # 0.11 under their middle, clear of its sails and the rear window), down behind it through the deck, on down
    # behind the cabin's rear wall and back low in the body, where the stowed top lies, out of sight (convert.py view
    # soft against HIDE=SoftTop: a leg back at z 0.48 to y -1.42 left the first strip behind the rear window's lower
    # corners, seen from the front; to -1.62 its corners showed past the tail from above and through the rear bumper;
    # folded forward again, the reversed strips' sides stood up behind the rear window)
    SOFT_TOP=dict(n=12, path=((-0.475, 0.950), (-0.56, 0.985), (-0.66, 0.985), (-0.74, 0.86), (-0.80, 0.58),
                              (-0.84, 0.30), (-1.30, 0.30))),
    # ---- convert.py: the source (TMP/src, gitignored; temp/sketchfab-roadster in the main checkout)
    SRC=("src", "source", "roadster_prep.fbx"),
    SRC_C=(0.0, 0.0),
    SRC_YFRONT=-0.0018,                    # the source's tyre bottoms, source z
    SRC_SCALE=1.0,
    SRC_STRETCH=(1.0, 1.0, 1.0),
    SRC_FLIP=False,
    BELT_Z=0.645,                          # the door skin's top edge (the side glass's visible foot)
    TIRE_OBJ="Tire_",
    DROP=("Tire_",),
    DROP_COMPS=(),
    ARCH_LINER=None,
    PLATES=(),
    SEAL_CLIP=True,
    RAIL=None,
    # collapse targets (tris; the build prints the components' new sizes, COMPS): specific names before "Paint"
    DECIMATE={"PaintMirror": 1400, "PaintHoop": 1600, "PaintHood": 1700, "PaintTrunk": 1200, "PaintDoor": 1800,
              "PaintPort": 99999, "Paint": 14000, "Trim": 9000, "Glass": 2600, "light_reflector_bowl": 900,
              "Projector_lights": 500, "Emissive_lights": 500, "Taillight_glass": 1000, "Tesla_text": 900,
              "SoftTop": 3000},
    PAINT_MAT="Paint",
    # the head lamps' case is the source's black glass lens over the bowls (drawn opaque here): a smoked grey that
    # reads as a lens, lit with the head lamps (LAMPS head)
    MAT_RGB={"Trim": (20, 20, 22), "Grill": (14, 14, 16), "Headllight case": (96, 100, 106),
             "light reflector bowl": (190, 192, 196), "Projector lights": (120, 122, 126),
             "Emissive lights": (232, 234, 236), "Emissive lights (orange)": (196, 124, 52), "Mirrors": (110, 116, 122),
             "Fender lights (orange)": (196, 118, 44), "Fender lights (red)": (140, 22, 26),
             "Fender lights LED": (200, 200, 200), "Taillight glass": (124, 30, 34), "Rear lights": (150, 20, 24),
             "Signal lights": (196, 124, 52), "Reverse lights": (210, 210, 210), "Reflector": (120, 16, 20),
             "3rd taillight": (90, 18, 22), "Tesla text": (200, 204, 210), "Tesla logo": (200, 204, 210),
             "SoftTop": (24, 24, 26), "SoftTopLining": (40, 40, 42),
             "Intake bar": (84, 88, 94), "Diffuser": (44, 46, 50)},   # (prep NOSE: the 2.5's bars, louvres, plate)
    GLASS_MATS=("Glass",),
    GLASS_OPAQUE=(),
    GLASS_BACKS=(),
    ROOF_PANE="-",                         # (no glass roof)
    MIRROR_CAP="PaintMirror",              # body-colour mirror caps and arms on the doors, outer faces only
    # lamps: the head lamps' lens case, emitters and bowls; the tail lamps' round lenses (inner tail, middle and outer
    # brake: LAMPS brake |x| over 0.40) and the third brake light on the hoop (STOP_X)
    LAMPS=dict(head=("Headllight case", "Emissive lights", "Emissive lights (orange)", "light reflector bowl"), head_y=0.5,
               tail=("Taillight glass", "3rd taillight"), tail_z=0.55, tail_y=-0.5, blade=None,
               brake=("Taillight_glass", 0.40)),
    # part lines, side view (y, z): the door skin's rear edge (prep geometry)
    LINES={"S": ((-0.339, 0.29), (-0.464, 0.61)), "BF": ((-0.339, 0.29), (-0.464, 0.61))},
    FRONT_Y=0.4868, SILL_Z=0.235, ARCH=(0.0, -9.0),
    IN_DOOR=dict(up=0.645, x=0.38),
    IN_GATE=dict(y=-1.38, z=0.64, up=9.0, x_up=0.31),
    # door front edge, rear edge (B pillar), the cabin's ring cut behind the seats (no door)
    DOOR_Y=(0.4868, -0.40, -0.52),
    GATE_Z=0.6464,                         # the trunk lid's lower edge
    REAR_ARCH=(-1.032, 0.262, 0.34),
    GATE_X=0.31,
    STOP_X=0.2,
    PANELS=dict(x=0.45, z=0.80, front=(-0.45, 0.50), rear=(-0.45, -0.45), gate=(-1.38, 0.6), lid=(0.55, 0.45)),
    GUARDS=dict(front=(0.49, 0.75, 0.35), rear=(-0.45, 0.75, 0.35)),
    CUT={},
    PLANES={},
    CUT_X=("-",),
    CUT_X_Y=-9.0,
    DOOR_OBJS=("Glass", "Trim", "Mirrors", "PaintMirror"),
    GATE_OBJS=(),
    GATE_COMPS=(),
    GATE_CUT_COMPS=(),
    PART_OBJS={"SoftTop": ("SoftTop",)},  # the soft top: the whole prep object (its strips, soft_strips)
    # the 2.5's black paint: the intake's surround over the smile (below _INTAKE, over the lip) and the corner side
    # intakes (between _SLOT's edges), cut along their edges
    CARBON=dict(rgb=(20, 20, 22), zones=(
        dict(lo=(-0.52, 1.30, 0.194), hi=(0.52, 9.0, 0.33), facing=((0, 1, 0), (0.25, 1.0)), cut=True,
             below=tuple(pn for ln in zip(_INTAKE[:-1], _INTAKE[1:]) for pn in _below(*ln))),
        *(dict(lo=(0.40 if sd > 0 else -0.75, 1.25, 0.19), hi=(0.75 if sd > 0 else -0.40, 1.45, 0.40),
               facing=((sd, 0, 0), (0.4, 1.0)), cut=True,
               below=(((0, 0, 0.388), (0, 0, 1)), ((0, 0, 0.198), (0, 0, -1)), _edge(*_SLOT[0], 1), _edge(*_SLOT[1], -1)))
          for sd in (1, -1)))),
    PANES={"Body": {"WinT", "WinH"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"}, "TrunkDoor": set(),
           "EngineDoor": set(), "SoftTop": set()},
    # badges: the source's own (the T on the nose, T E S L A across the tail)
    T_BADGE=None,
    TESLA=None,
    LENS_X=0.0,
    BADGE_Y=(-9.0, -9.0),
    BLADE=False,
    MODELY=None,
    PERF_BADGE=None,
    CALIPER=None,
    # no frunk in the real car: the smallest bin under the hood (outer: the hood's outline past its vent strips' own
    # edges)
    FRUNK_TUB=dict(ledge=0.05, rim=0.025, y=(0.84, 1.30), half=(0.30, 0.24), corner=0.06, taper=0.05, depth=0.10,
                   n=128, outer=True),
    # charge port (owner's manual 2-2 item 2, 5-7): the left rear fender's round lid (prep PaintPort's centre)
    PORT=(-0.566, 0.75),
    # ---- cabin.py (mesh coords, centred)
    CABIN_FLOOR=-0.40,                     # the underbody (ground clearance): the hips sit at floor level
    CABIN_FRONT_Y=0.70,
    TRUNK_Y=-0.62,
    CABIN_ZC=-0.10,
    SEAM_CLEAR=0.065,
    SEATS=dict(front=dict(w=0.40, back=0.36, recline=28, head=0.47, dy=-0.066, dz=-0.085), sill=None, bin=None),
    PARCEL=None,
    DASH=dict(console=(0, 0.0, -0.25), dash=(0, 0.50, 0.06), trim=(0, 0.367, 0.075), light=(0, 0.369, 0.051),
              stand=(0, 0.40, 0.05), screen=(0, 0.362, 0.05), wheel=(0.307, 0.033)),
    DOOR_CARD={
        "front": [
            ("upper trim", "end", (0.08, 0.10), -0.050, None, 0.060, 0.030, "dash", 0.012),
            ("armrest", "rear", 0.07, -0.215, 0.44, 0.050, 0.085, "seat", 0.018),
            ("pull handle", "rear", 0.13, -0.165, 0.26, 0.026, 0.050, "dash", 0.010),
            ("window switches", "rear", 0.31, -0.188, 0.13, 0.012, 0.060, "screen_back", 0.004),
            ("map pocket", "end", (0.10, 0.30), -0.320, None, 0.070, 0.040, "base", 0.015),
        ],
    },
)
