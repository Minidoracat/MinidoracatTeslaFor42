"""Model X Plaid: Abdul.Hannan's "Tesla Model X" (Sketchfab, CC BY 4.0, CREDITS.md). CAR=model_x.
Keys as in model_y.py (each is the module constant it sets); the keys only this car has are read with C.get and are off
for the others: DROP_MATS, PART_OBJS / SIDE_PARTS (whole source objects are the doors and lids), RECOLOR, CAMERA,
FALCON (DOORS axis "falcon": the rear doors), SEAT third (six seats: pzveh.geometry, cabin.py SEATS middle / third).
The source is a half model with Mirror + Subsurf + Auto Smooth modifiers in a .blend: scripts/blender/skf/prep_model_x.py
applies them (Subsurf level 1) and writes TMP/src/source/model_x.obj, front +X, left +Y, ground z 0. Its shape is the
2016-2020 car; the last (2025+) Model X Plaid's is close: chrome trim black (Aluminum), the front bumper camera
(CAMERA), the nose's T chrome (RECOLOR). Grid units, pre-centre frame (+Y front, +Z up, -X car left, ground z 0)
unless noted; numbers and sources: .claude/skills/tesla-dev/references/models-model-x.md.
"""
import math

CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_mx",
    NAME="MinidoracatTesla_ModelX",
    SCRIPT_MARK="---- geometry (TeslaModelX)",
    APP_CAR="app_car_modelx_{}.png",
    DIMS=(5.057, 1.999, 1.680),            # owner's manual (2021+, tesla.com 2026-11-01): length, width w/o mirrors, height
    PORT_NOTE="real Model X, owner's manual p.189",
    # the last US design studio's six (Lexicon 2026-03-06) and China's pre-refresh two (2025-03); order = Core.lua Specs
    # colors (skin index is saved: only append after release)
    PAINTS=[("StealthGrey", "PN01"), ("LunarSilver", "PN02"), ("PearlWhite", "PPSW"), ("UltraRed", "PR01"),
            ("DiamondBlack", "PX02"), ("FrostBlue", "PB00"), ("SolidBlack", "PBSB"), ("DeepBlue", "PPSB")],
    # tex = a * official-ramp colour / GAIN (model_y.py CAL), b 0: per-channel gains only, a = official FRONT34 p50 over
    # the game's at a = 1 (perf/paint_sheet.py on modelx-sp paint-<i>-<name>-fl-max, tesla-mx-1101b). An offset (the
    # first fit) clipped the dark lower doors to another hue (Ultra Red R < 0 -> grey-green). RAMP_SPLIT (convert.py):
    # the gains act on the paint colour only, the ramp's grey (floor reflection, highlights) gets their mean.
    # Calibration knob: refit after changing the paint light
    CAL={
        "StealthGrey": ((0.82, 0.78, 0.75), (0.0, 0.0, 0.0)),
        "LunarSilver": ((0.76, 0.75, 0.75), (0.0, 0.0, 0.0)),
        "PearlWhite": ((0.92, 0.91, 0.91), (0.0, 0.0, 0.0)),
        "UltraRed": ((0.75, 1.58, 1.17), (0.0, 0.0, 0.0)),
        "DiamondBlack": ((1.16, 1.09, 0.98), (0.0, 0.0, 0.0)),
        "FrostBlue": ((1.06, 1.02, 0.98), (0.0, 0.0, 0.0)),
        "SolidBlack": ((1.02, 1.0, 0.94), (0.0, 0.0, 0.0)),
        "DeepBlue": ((2.25, 1.0, 0.83), (0.0, 0.0, 0.0)),
    },
    RAMP_SPLIT=True,
    # design studio: Plaid, 20" Perihelix, black interior, six seats. The two China paints are the pre-refresh car's
    # ($MTX19,$WX01,$IBC00): their renders were fetched by hand (temp/plan-sx-1031/assets/official), used for the colour
    COMPOSITOR_MODEL="mx",
    OFFICIAL_OPTS="$MDLX,$MTX23,${},$WX03,$IBC02,$CC02,$ST06",
    RAMP=dict(t=(0.36, 0.78), u=(0.08, 0.95), wheels=(0.172, 0.808), wt=0.76, wr=0.115),
    # ---- pzveh: wheel, 20" Perihelix ($WX03, official RIMCLOSEUP): five wide swept blades in dark grey, each lighter
    # along its face, open between them onto the red caliper; 265/45 R20 front, 275/45 R20 rear (one size here, the
    # source tyres': radius 0.311, 1 % over the official 373 mm)
    WHEEL_RIM=0.727,                       # 20" (254 mm bead + 17 mm flange) / 373 mm tyre radius
    WHEEL_SPOKE=dict(n=5, hub=0.16, fork=0.80, spread=math.radians(5), main=(0.095, 0.15), arm=0.085, cap=0.17,
                     inset=0.016, dish=0.020, depth=0.020, sweep=math.radians(42)),
    WHEEL_DISC=dict(rotor=0.70, hat=0.30),
    WHEEL_RGB=dict(spoke=66, cap=34, barrel=20, lip=52, rotor=44, hat=30, dark=10, gap=8, tire=(22, 28), tread=20),
    # ---- pzveh: vehicle script
    OY=0.2878,
    WHEEL_LIFT=0.11,
    WHEEL_INSET=0.03,
    CAB_BOX=(1.32, 0.45, -1.75),
    # passengers / seats (cabin.py): front and 2nd row from the door openings (back: front, 2nd row); third: the 3rd row
    # `back` behind the falcon doors' rear edge, at side x (3rd row shoulder room 1,033 mm against 1,442 in the 2nd,
    # owner's manual Dimensions)
    # third drop: the 3rd row sits lower, so its passengers' heads stay under the sloping roof (they showed through it)
    SEAT=dict(x=0.35, h=0.62, z=-0.15, back=(0.12, -0.04), out=0.30, third=dict(back=0.10, x=0.27, drop=0.08)),
    BODY_W_Z=0.55,
    # falcon wing doors (axis "falcon": (roof hinge deg, elbow fold deg), clip seconds): the upper part turns up about
    # its hinge by the roof's spine, the lower part folds back out at the elbow (owner's manual p.31-33: two hinges).
    # Full open ~1.8 grid (owner measurements 230 cm = 1.9; a level is 2.45, Core.java:151)
    DOORS={
        "DoorFrontLeft": (-1, (0, 0, 1), -65, 0.8), "DoorFrontRight": (1, (0, 0, 1), 65, 0.8),
        "DoorRearLeft": (-1, "falcon", (80, -30), 2.4), "DoorRearRight": (1, "falcon", (-80, 30), 2.4),
        "TrunkDoor": (0, (1, 0, 0), -75, 3.6), "EngineDoor": (0, (1, 0, 0), 55, 1.0),
    },
    FALCON=dict(hinge=(0.14, 1.37), elbow=(0.55, 1.30), side=(0.75, 0.86)),
    GATE_IN=(0.0, 0.894, -0.447),
    GATE_HINGE="top",
    # ---- convert.py: the source (TMP/src, gitignored; temp/sketchfab-model-x-plaid in the main checkout)
    SRC=("src", "source", "model_x.obj"),
    SRC_C=(1.5579, -0.448),                # source length / width centre (the mirror plane), source units
    SRC_SCALE=5.057 / 3.1184,              # metres per source unit: official length / source length
    SRC_FLIP=True,                         # front +X, left +Y
    BELT_Z=0.90,
    TIRE_OBJ="Tyre",
    DROP=("Tyre", "Rim"),                  # the procedural wheel instead
    DROP_MATS=("Door_Inside",),            # the source's door cards and trunk lining: the mod's slab, door_card, cabin
    DROP_COMPS=(),
    CARBON=None,
    ARCH_LINER=None,
    PLATES=(),
    SEAL_CLIP=False,
    RAIL=None,
    DECIMATE={},                           # done in the prep (material borders held)
    PAINT_MAT="Car_Paint",
    MAT_RGB={"Black_Car_Paint": (24, 24, 26), "Aluminum": (28, 28, 30), "Light_Glass": (30, 30, 32),
             "Light": (210, 210, 214), "Light_Glass_Simple": (226, 230, 236), "Red_Light_Glass": (150, 14, 18),
             "Mirror": (58, 64, 72), "Window_Glass": (14, 14, 16), "badge_cam": (96, 98, 104)},
    GLASS_MATS=("Window_Glass",),
    GLASS_OPAQUE=(),
    GLASS_BACKS=("WinLH", "WinLT", "WinRH", "WinRT"),   # the source's panes are one-sided
    ROOF_PANE="-",
    MIRROR_CAP="-",
    LAMPS=dict(head=("Light_Glass_Simple",), tail=("Red_Light_Glass",), tail_z=0.6, tail_y=-1.5, blade=None),
    # side-view lines (y, z): only the B-pillar seam S is used (the cabin shell's ring); the doors are source objects
    LINES={
        "S": ((-0.150, 0.20), (-0.214, 0.90)),
        "BF": ((-0.214, 0.90), (-0.280, 1.30)),
        "BR": ((-0.214, 0.90), (-0.280, 1.30)),
        "D": ((-1.19, 0.90), (-1.19, 1.30)),
        "R1": ((-1.16, 0.70), (-1.19, 0.90)),
    },
    FRONT_Y=0.83, SILL_Z=0.25, ARCH=(0.70, -0.70),
    IN_DOOR=dict(up=0.9, x=0.55),
    IN_GATE=dict(y=-1.2, z=0.57, up=1.2, x_up=0.55),
    DOOR_Y=(0.83, -0.18, -1.19),
    GATE_Z=0.57,
    REAR_ARCH=(-1.18, 0.31, 0.45),
    GATE_X=0.555,
    STOP_X=0.64,
    # door panels by component centre are off: PART_OBJS / SIDE_PARTS give whole objects
    PANELS=dict(x=9.0, z=0.0, front=(9.0, 9.0), rear=(9.0, 9.0), gate=(-9.0, 9.0), lid=(9.0, 9.0)),
    GUARDS=dict(front=(0.85, 0.95, 0.45), rear=(-1.19, 1.15, 0.50)),
    PART_OBJS={"EngineDoor": ("Bonnet",), "TrunkDoor": ("Trunk",)},
    SIDE_PARTS={"Front_Door": ("DoorFrontLeft", "DoorFrontRight"), "Back_Door": ("DoorRearLeft", "DoorRearRight")},
    CUT={},
    PLANES={},
    CUT_X=("-",),
    CUT_X_Y=None,
    DOOR_OBJS=(),
    GATE_OBJS=(),
    GATE_COMPS=(),
    GATE_CUT_COMPS=(),
    # the nose's T stays chrome (official FRONT34); the rest of the chrome trim is black on the last Model X
    # nose T chrome; the pre-refresh fog lamps (Light / Light_Glass in the bumper's corner pockets) black: the 2021+
    # car has none there, only a black air-curtain inlet (official FRONT34)
    RECOLOR=(("Aluminum", (-0.045, 1.98, 0.55), (0.045, 2.10, 0.67), (196, 200, 206)),
             *((m, (lo, 1.84, 0.22), (hi, 1.96, 0.34), (16, 16, 18)) for m in ("Light", "Light_Glass")
               for lo, hi in ((-0.68, -0.48), (0.48, 0.68)))),
    # the front bumper camera (2025+ Model X, official FRONT34): grey ring on the lower grille's middle (y: ray start
    # ahead of the bumper, z, ring radius and width)
    CAMERA=dict(y=2.2, z=0.32, r=0.022, w=0.008),
    PANES={"Body": {"WinT"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"},
           "DoorRearLeft": {"WinLT"}, "DoorRearRight": {"WinRT"}, "TrunkDoor": {"WinH"}, "EngineDoor": set()},
    T_BADGE=None,
    TESLA=None,
    LENS_X=0.0,
    BADGE_Y=(-2.6, -2.2),
    BLADE=False,
    MODELY=None,
    PERF_BADGE=None,
    CALIPER=dict(front=(176, 18), rear=(80, 15), r=(0.085, 0.145), x=(0.010, 0.045)),   # r: above the body floor (z 0.161)
    # frunk 183 L (owner's manual Dimensions) under the lid (Bonnet)
    FRUNK_TUB=dict(ledge=0.06, rim=0.025, y=(1.30, 1.78), half=(0.34, 0.19), corner=0.07, taper=0.10, depth=(0.40, 0.28),
                   n=128),
    # ---- cabin.py (mesh coords, centred)
    CABIN_FLOOR=-0.41,
    CABIN_FRONT_Y=1.00,
    TRUNK_Y=-1.55,
    CABIN_ZC=-0.05,
    SEAM_CLEAR=0.065,
    SEATS=dict(front=dict(w=0.42, back=0.52, recline=14),
               rear=dict(base=1.10, cushions=((-0.37, 0.36), (0, 0.33), (0.37, 0.36)), back=0.46, recline=18),
               middle=dict(w=0.42, back=0.50, recline=16), third=dict(w=0.36, back=0.34, head=0.42, recline=18),
               sill=(1.00, 0.12), bin=(0.86, 0.20)),
    PARCEL=None,
    DASH=dict(console=(0, 0.12, -0.28), dash=(0, 0.80, 0.02), trim=(0, 0.627, 0.03), light=(0, 0.629, 0.007),
              stand=(0, 0.64, 0.13), screen=(0, 0.61, 0.21), wheel=(0.50, 0.08)),
    DOOR_CARD={
        "front": [
            ("upper trim", "end", (0.05, 0.10), -0.050, None, 0.060, 0.030, "dash", 0.012),
            ("ambient light", "end", (0.07, 0.16), -0.086, None, 0.007, 0.012, "screen", 0.002),
            ("armrest", "rear", 0.07, -0.215, 0.44, 0.050, 0.085, "seat", 0.018),
            ("pull handle", "rear", 0.13, -0.165, 0.26, 0.026, 0.050, "dash", 0.010),
            ("window switches", "rear", 0.31, -0.188, 0.13, 0.012, 0.060, "screen_back", 0.004),
            ("door button", "rear", 0.43, -0.186, 0.035, 0.012, 0.050, "trim", 0.004),
            ("map pocket", "end", (0.10, 0.30), -0.475, None, 0.085, 0.045, "base", 0.015),
            ("speaker grille", "front", 0.20, -0.350, 0.17, 0.130, 0.018, "console", 0.050),
        ],
        "rear": [
            ("upper trim", "end", (0.05, 0.05), -0.050, None, 0.060, 0.030, "dash", 0.012),
            ("ambient light", "end", (0.07, 0.07), -0.086, None, 0.007, 0.012, "screen", 0.002),
            ("armrest", "front", 0.06, -0.215, 0.38, 0.050, 0.080, "seat", 0.018),
            ("pull handle", "front", 0.10, -0.165, 0.22, 0.026, 0.050, "dash", 0.010),
            ("map pocket", "end", (0.47, 0.05), -0.440, None, 0.080, 0.040, "base", 0.015),   # rear end: the arch cut
            ("speaker grille", "front", 0.08, -0.330, 0.14, 0.110, 0.018, "console", 0.045),
        ],
    },
)
