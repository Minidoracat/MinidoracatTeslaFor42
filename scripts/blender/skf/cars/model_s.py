"""Model S Plaid ($MTS23, the 2021 refresh as sold until 2026-05): ValentunW's (Lals) "Tesla Model S Plaid" (Sketchfab,
CC BY 4.0, CREDITS.md). CAR=model_s. Keys as in model_y.py (each is the module constant it sets); the keys only this car
has are read with C.get and are off for the others: SRC_Z (the glTF is centred on the car, not on the ground), TIRE
centres (the tyres are components of the black trim object), LAMPS head_y (one lamp material front and rear),
TESLA_MAT (chrome letters on the black band), GATE_BY_COMP (the tail lamps' liftgate and body halves overlap in x).
The source (a Roblox export, decisions.md) is the Sketchfab glTF: 22 objects "Object_<n>", one per material; doors,
frunk lid and liftgate are components of the paint object (Object_2), and the interior shares objects with the
exterior (paint seats, black trim cabin tub), so parts come from components (DROP_COMPS boxes, CUT keys).
Grid units, pre-centre frame (+Y front, +Z up, -X car left, ground z 0) unless noted; numbers and sources:
.claude/skills/tesla-dev/references/models-model-s.md.
"""
import math

_PAINT = "Color1Mtl"
_LAMP = "MeshesteslaMdoelStrunk2mesh2400622Mtl"     # head and tail lamp housings (smoked)
_BLACK = "Wiper11Mtl"                               # black trim, tyres, brakes, cabin tub
_GLASS = "MeshesteslaMdoelSwindowlf2mesh021Mtl"
_SIDES = (-1, 1)

CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_ms",
    NAME="MinidoracatTesla_ModelS",
    SCRIPT_MARK="---- geometry (TeslaModelS)",
    APP_CAR="app_car_models_{}.png",       # six paints share names with Model Y / Model 3
    DIMS=(5.046, 1.987, 1.430),            # owner's manual (HTML, 2026-07): Plaid length, width w/o mirrors, height Medium
    PORT_NOTE='real Model S: behind the left tail light\'s cover, owner\'s manual p.172',
    # US design studio 2026-03-06 (the last before the end of production) plus the China pre-refresh Solid Black and
    # Deep Blue (user 2026-10-31, add2). Same names and order as Model X. Skin index is saved: only append after release
    PAINTS=[("StealthGrey", "PN01"), ("LunarSilver", "PN02"), ("PearlWhite", "PPSW"), ("UltraRed", "PR01"),
            ("DiamondBlack", "PX02"), ("FrostBlue", "PB00"), ("SolidBlack", "PBSB"), ("DeepBlue", "PPSB")],
    # paint tone (model_y.py CAL): fitted on models-body-sp paint-<i>-<name>-fl-max (zoom 0.5, heading S) against the
    # official FRONT34 with paint_sheet.py --car MinidoracatTesla_ModelS: one slope per paint (the fit's mean, held to
    # 0.85-1.15), per-channel offsets put the game p50 on the official p50 (models.md 0b, Model 3 "車漆"); a second pass
    # (tesla-msbody-1101b) moved the offsets by its residual
    CAL={
        "StealthGrey": ((1.15, 1.15, 1.15), (0.009, -0.002, -0.022)),
        "LunarSilver": ((1.15, 1.15, 1.15), (-0.101, -0.122, -0.133)),
        "PearlWhite": ((0.977, 0.977, 0.977), (-0.023, -0.04, -0.047)),
        "UltraRed": ((1.15, 1.15, 1.15), (-0.006, 0.103, 0.084)),
        "DiamondBlack": ((0.853, 0.853, 0.853), (0.083, 0.075, 0.061)),
        "FrostBlue": ((1.15, 1.15, 1.15), (-0.062, -0.071, -0.101)),
        "SolidBlack": ((0.867, 0.867, 0.867), (0.06, 0.051, 0.045)),
        "DeepBlue": ((1.15, 1.15, 1.15), (0.107, 0.011, -0.107)),
    },
    # design studio: Plaid ($MTS23), 19" Magnetite ($WS94), black carbon interior ($IBC02), round wheel ($ST06); the
    # two China paints from the pre-refresh $MTS19 (colour only: its nose differs). The renders were fetched by hand
    # (TMP/official/<code>_<SIDE|FRONT34|REAR34>.png; models-model-s.md), `official` would ask one option set for all
    COMPOSITOR_MODEL="ms",
    OFFICIAL_OPTS="$MDLS,$MTS23,${},$WS94,$IBC02,$ST06",
    # official_ramp: the SIDE render's paint rows / columns (car bbox fractions) and the wheel arches cut out
    RAMP=dict(t=(0.40, 0.76), u=(0.04, 0.96), wheels=(0.166, 0.80), wt=0.75, wr=0.12),
    # ---- pzveh: wheel, 19" Magnetite (official RIMCLOSEUP): a black wheel, five wide swept blades with machined
    # silver edges, open between them onto the red caliper. 255/45 R19 front, 285/40 R19 rear (~356 mm radius)
    WHEEL_RIM=0.725,                       # rim flange radius / tire radius: 19" (241.3 mm bead + ~17 mm) / 356 mm
    WHEEL_SPOKE=dict(n=5, hub=0.13, fork=0.30, spread=math.radians(15), main=(0.08, 0.09), arm=0.055, cap=0.14,
                     inset=0.018, dish=0.020, depth=0.018, sweep=math.radians(40)),
    WHEEL_DISC=dict(rotor=0.70, hat=0.30),     # 395 mm front rotor (owner's manual) / 258 mm flange
    WHEEL_RGB=dict(spoke=78, cap=26, barrel=18, lip=96, rotor=36, hat=28, dark=12, gap=8, tire=(22, 28), tread=20),
    # 255/45 R19 front, 285/40 R19 rear (owner's manual p.210): radius ~356 mm, one width per car (their mean), track
    # 1,690 mm; the axles where the source has them (its tyres sit in the black trim object, dropped below)
    TIRE=dict(r=0.3557, w=0.270, track=1.690, centres=((1.2833, 0.2925), (-1.169, 0.2895))),
    # ---- pzveh: vehicle script
    OY=0.1978,                             # Model 3's (a sedan's CoM)
    WHEEL_LIFT=0.11,
    WHEEL_INSET=0.03,
    CAB_BOX=(1.30, 0.45, -1.40),
    # the seats sit further back in the door openings than Model 3's (the source's seats and yoke)
    SEAT=dict(x=0.34, h=0.47, z=-0.123, back=(0.25, 0.20), out=0.30),
    BODY_W_Z=0.55,
    # the power liftgate hinges at the roof (rear glass with it) and swings up (-)
    DOORS={
        "DoorFrontLeft": (-1, (0, 0, 1), -65, 0.8), "DoorFrontRight": (1, (0, 0, 1), 65, 0.8),
        "DoorRearLeft": (-1, (0, 0, 1), -65, 0.8), "DoorRearRight": (1, (0, 0, 1), 65, 0.8),
        "TrunkDoor": (0, (1, 0, 0), -75, 3.6), "EngineDoor": (0, (1, 0, 0), 55, 1.0),
    },
    GATE_IN=(0.0, 0.8, -0.6),              # liftgate inner panel: forward under the glass, down behind the rear face
    GATE_HINGE="top",
    # ---- convert.py: the source (TMP/src, gitignored; temp/sketchfab-model-s-plaid in the main checkout)
    SRC=("src", "source", "tesla_model_s_plaid.glb"),
    SRC_C=(0.3293, -0.2435),               # source bbox centre, x (length) and y (width), source units
    SRC_SCALE=5.046 / 20.707,              # metres per source unit: official length / source length
    SRC_FLIP=False,                        # front -X as imported (the PLAID badge on the liftgate's right)
    SRC_Z=-0.2544 / (0.826 * 5.046 / 20.707),   # the ground (tyre bottoms) in source z: the glTF is centred on the car
    BELT_Z=0.80,
    TIRE_OBJ="-",                          # (TIRE centres)
    # interior objects (the mod's cabin.py): door cards, dash, yoke, screens, headliner; the source's rims and their
    # tyre-lettering discs (the mod's procedural wheel)
    DROP=("Object_12", "Object_13", "Object_14", "Object_15", "Object_16", "Object_19", "Object_4", "Object_5",
          "Object_6", "Object_7", "Object_8", "Object_9"),
    # components dropped by bbox centre (objects, lo, hi)
    DROP_COMPS=(
        # paint: rear bench, front seats and cushions, console, the doors' inner trims, dash bits, under-hood panels
        (("Object_2",), (-0.3, -0.9, 0.5), (0.3, -0.6, 0.9)),
        *((("Object_2",), (-0.45 if s < 0 else 0.2, -0.3, 0.6), (-0.2 if s < 0 else 0.45, -0.1, 0.8))
          for s in _SIDES),
        *((("Object_2",), (-0.45 if s < 0 else 0.2, 0.0, 0.3), (-0.2 if s < 0 else 0.45, 0.15, 0.45)) for s in _SIDES),
        (("Object_2",), (-0.12, -0.25, 0.45), (0.12, 0.08, 0.6)),
        *((("Object_2",), (-0.68 if s < 0 else 0.5, -1.0, 0.5), (-0.5 if s < 0 else 0.68, 0.7, 0.8)) for s in _SIDES),
        (("Object_2",), (-0.55, 0.45, 0.6), (0.65, 0.56, 0.8)),
        (("Object_2",), (-0.1, 1.25, 0.70), (0.1, 1.5, 0.78)),
        # black: tyres, brake discs, calipers and wheel bolts at each wheel
        *((("Object_23",), (-0.85 if s < 0 else 0.6, y - 0.25, 0.15), (-0.6 if s < 0 else 0.85, y + 0.25, 0.42))
          for s in _SIDES for y in (1.2833, -1.169)),
        # black: the cabin tub, headliner, seat backs, B-pillar inner trims; footwells; dash top; frunk and trunk tubs
        (("Object_23",), (-0.58, -1.15, 0.40), (0.58, 0.62, 1.20)),
        *((("Object_23",), (-0.15 if s < 0 else 0.08, -0.1, 0.3), (-0.08 if s < 0 else 0.15, 0.0, 0.45))
          for s in _SIDES),
        (("Object_23",), (-0.55, 0.5, 0.3), (0.55, 0.75, 0.4)),
        (("Object_23",), (-0.5, 0.62, 0.3), (0.5, 0.95, 0.70)),   # pedals (not the front wheel wells, centred y 1.08)
        (("Object_23",), (-0.2, 0.6, 0.8), (0.2, 0.9, 0.95)),
        (("Object_23",), (-0.1, 1.3, 0.5), (0.1, 1.55, 0.65)),
        (("Object_23",), (-0.6, 1.3, 0.6), (-0.5, 1.45, 0.75)),
        (("Object_23",), (0.5, 1.5, 0.6), (0.65, 1.62, 0.72)),
        (("Object_23",), (-0.62, 1.08, 0.55), (0.62, 1.95, 0.80)),   # under the hood (frunk_tub's place)
        (("Object_23",), (-0.1, -1.6, 0.55), (0.1, -1.3, 0.7)),
        (("Object_23",), (0.45, -1.7, 0.6), (0.55, -1.5, 0.7)),
        # black: the wipers (official renders: hidden under the hood's rear edge)
        (("Object_23",), (-0.6, 0.85, 0.77), (0.6, 1.05, 0.86)),
        # black: the source's TESLA letters (black on the black band; badges() draws chrome ones)
        (("Object_23",), (-0.13, -2.01, 0.715), (0.13, -1.99, 0.745)),
        # badges: the source's T on the nose (badges() draws ours) and on the liftgate (none on the real one, official
        # REAR34); door handles inside and sill-plate letters (the rest of Object_20 is the tail lamps' red bars)
        (("Object_20",), (-0.05, 2.0, 0.45), (0.05, 2.06, 0.55)),
        (("Object_20",), (-0.05, -2.01, 0.76), (0.05, -1.98, 0.85)),
        (("Object_20",), (-0.6, -1.0, 0.5), (0.6, 0.0, 0.7)),
        (("Object_20",), (-0.3, 0.45, 0.7), (0.3, 0.65, 0.9)),
        *((("Object_20",), (-0.9 if s < 0 else 0.75, 0.38, 0.8), (-0.75 if s < 0 else 0.9, 0.48, 0.88)) for s in _SIDES),
        *((("Object_20",), (-0.65 if s < 0 else 0.6, 0.25, 0.3), (-0.6 if s < 0 else 0.65, 0.42, 0.36))
          for s in _SIDES),
    ),
    # the hood is a closed shell: its underside goes (frunk_tub needs the lid's outline; the slab gives it depth)
    DROP_FACES_COMPS=((("Object_2", 3066), (-0.8, 0.8, 0.4), (0.8, 2.1, 0.9), (0, 0, 1), (-2.0, -0.15)),),
    ARCH_LINER=None,                       # the source has its own wheel wells (Object_23)
    # black plate behind the lower grille's slats (else the ground showed between them)
    PLATES=(("GrillePlate", ((-0.55, 1.90, 0.08), (0.55, 1.90, 0.08), (0.55, 1.90, 0.34), (-0.55, 1.90, 0.34)),
             (0, 1, 0), "arch_liner"),
            ("GrilleFloor", ((-0.55, 1.70, 0.09), (0.55, 1.70, 0.09), (0.55, 1.90, 0.09), (-0.55, 1.90, 0.09)),
             (0, 0, 1), "arch_liner")),
    SEAL_CLIP=True,
    # the roof is glass, so the paint up there is the roof rails (model_3.py RAIL)
    RAIL=(0.95, 1.08),
    DECIMATE={"Object_23": 9000, "Object_2": 16000},   # (prefix match: Object_23 first)
    PAINT_MAT=_PAINT,
    MAT_RGB={_LAMP: (40, 36, 38),                     # smoked lamp housings (official: dark lamps)
             "I1Mtl": (232, 236, 240),                 # the headlamps' running-light strip
             "Meshpart7Mtl": (160, 16, 20),            # the tail lamps' light bars (the T badges dropped)
             "Stop1Mtl": (130, 12, 16), "Meshpart16Mtl": (110, 10, 14), "Meshpart18Mtl": (110, 10, 14),
             _BLACK: (20, 20, 22), "PlaidBadge2Mtl": (58, 60, 64), _GLASS: (14, 14, 16)},
    GLASS_MATS=(_GLASS,),
    GLASS_OPAQUE=(),
    GLASS_BACKS=(),
    ROOF_PANE=("Object_11", 452),          # the glass roof
    MIRROR_CAP=("Object_2", (230, 231)),   # (decimated sizes)
    LAMPS=dict(head=(_LAMP, "I1Mtl"), head_y=0.0, tail=(_LAMP, "Meshpart7Mtl", "Stop1Mtl"), tail_z=0.6, tail_y=-1.4,
               tail_rgb=(40, 24, 28),           # the tail lamps' smoked red (official REAR34 lamp median 37 28 31)
               blade=None),
    # part lines, side view (y, z), read off the source's door skins and windows (temp/skf_ms/outline.py)
    LINES={
        "S": ((-0.170, 0.20), (-0.194, 0.82)),   # front / rear door seam below the belt
        "BF": ((-0.150, 0.80), (-0.262, 1.12)),  # front door glass rear edge
        "BR": ((-0.289, 0.80), (-0.350, 1.12)),  # rear door glass front edge
        "D": ((-1.215, 0.82), (-1.215, 1.12)),   # rear door frame rear edge, behind its fixed quarter glass
        "R1": ((-0.633, 0.20), (-0.722, 0.30), (-0.782, 0.40), (-0.870, 0.50), (-0.926, 0.60), (-1.026, 0.70),
               (-1.072, 0.80), (-1.10, 0.86)),   # rear door rear edge below the belt (a polyline)
    },
    FRONT_Y=0.765, SILL_Z=0.19, ARCH=(0.0, -9.0),
    IN_DOOR=dict(up=0.82, x=0.50),
    IN_GATE=dict(y=-1.06, z=0.49, up=9.0, x_up=0.575),
    GATE_BY_COMP=True,
    DOOR_Y=(0.765, -0.18, -1.0),
    GATE_Z=0.50,
    REAR_ARCH=(-1.169, 0.29, 0.38),
    GATE_X=0.575,
    STOP_X=0.66,
    PANELS=dict(x=0.6, z=0.9, front=(-0.16, 0.6), rear=(-1.1, -0.16), gate=(-1.3, 0.6), lid=(0.9, 0.6)),
    GUARDS=dict(front=(0.765, 0.85, 0.45), rear=(-0.95, 0.95, 0.45)),
    CUT={},
    PLANES={},
    CUT_X=("-",),
    CUT_X_Y=None,
    DOOR_OBJS=("Object_23", "Object_11", "Object_20"),
    GATE_OBJS=("Object_10", "Object_11", "Object_20", "Object_21", "Object_22", "Object_23"),
    GATE_COMPS=(),
    GATE_CUT_COMPS=(),
    # black: the Plaid's carbon spoiler is a black part (Object_23) already; the black lower front lip too
    CARBON=None,
    PANES={"Body": {"WinT", "LightBarL"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"},
           "DoorRearLeft": {"WinLT"}, "DoorRearRight": {"WinRT"}, "TrunkDoor": {"WinH"}, "EngineDoor": set()},
    # badges: T on the nose (where the source has it), TESLA in chrome across the black band between the tail lamps
    # (official REAR34); the source's PLAID plate (Object_21) on the liftgate's lower right stays
    T_BADGE=(2.04, 0.060, 0.063, 0.495, (0, 0.92, 0.39), None),
    TESLA=(0.73, 0.022, 0.08, 0.04),
    TESLA_MAT="badge_chrome",
    LENS_X=0.46,
    BADGE_Y=(-2.3, -2.0),
    BLADE=False,
    MODELY=None,
    PERF_BADGE=None,
    CALIPER=dict(front=(176, 12), rear=(80, 15), r=(0.100, 0.168), x=(0.008, 0.040)),
    # frunk 89 L (owner's manual p.207) under the lid
    FRUNK_TUB=dict(ledge=0.06, rim=0.025, y=(1.21, 1.72), half=(0.34, 0.22), corner=0.07, taper=0.07, depth=0.22,
                   n=128),
    # ---- cabin.py (mesh coords, centred)
    CABIN_FLOOR=-0.32,
    CABIN_FRONT_Y=1.05,
    TRUNK_Y=-1.05,
    TRUNK_TOP=True,                        # trunk side walls up to the quarter glass (cabin.py; user 2026-11-01)
    CABIN_ZC=-0.04,
    SEAM_CLEAR=0.065,
    SEATS=dict(front=dict(w=0.43, back=0.52, recline=14),
               rear=dict(base=1.12, cushions=((-0.38, 0.37), (0, 0.34), (0.38, 0.37)), back=0.46, recline=20),
               sill=(1.04, 0.12), bin=(0.90, 0.40)),
    PARCEL=None,                           # a liftgate: no parcel shelf
    DASH=dict(console=(0, -0.02, -0.25), dash=(0, 0.66, 0.06), trim=(0, 0.487, 0.07), light=(0, 0.489, 0.045),
              stand=(0, 0.50, 0.17), screen=(0, 0.47, 0.25), wheel=(0.34, 0.12)),
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
            ("window switches", "front", 0.32, -0.188, 0.09, 0.012, 0.055, "screen_back", 0.004),
            ("map pocket", "end", (0.32, 0.05), -0.440, None, 0.080, 0.040, "base", 0.015),
            ("speaker grille", "front", 0.08, -0.330, 0.14, 0.110, 0.018, "console", 0.045),
        ],
    },
)
