"""Model Y L (six seats, China $MTY87): BloxBloger's "2025 Tesla Model Y" (the standard car, Sketchfab, CC BY-NC 4.0,
CREDITS.md) lengthened by scripts/blender/skf/prep_model_yl.py (run it first: TMP/src/source/tesla.obj ->
model_yl.obj). CAR=model_yl. Keys as in model_y.py (each is the module constant it sets); SEAT third / SEATS middle and
third as model_x.py (six seats), SEATS middle arms (the 2nd row's armrests, cabin.py). The source has the Model Y's
object names, but not all of them mean the same parts (the window glass, the rear glass and its frame, the badges):
read off this source's inspect. Its front to the B pillar is the source's own: Model Y values ahead of the B pillar are
the Performance source's + 0.081 in y (the two sources sit 0.081 apart; B-pillar trims, seam S). Grid units,
pre-centre frame (+Y front, +Z up, -X car left, ground z 0) unless noted; numbers and sources:
.claude/skills/tesla-dev/references/models-model-yl.md.
"""
import math

_CUT_X = ("Plane.034", "Plane.044", "Plane.045", "Plane.036", "Plane.042", "Plane.043", "Plane.041")  # rear lamps

CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_yl",
    NAME="MinidoracatTesla_ModelYL",
    SCRIPT_MARK="---- geometry (TeslaModelYL)",
    APP_CAR="app_car_modelyl_{}.png",
    DIMS=(4.969, 1.920, 1.668),            # owner's manual (US 2026.38 p.244: length without the plate bracket; China
    #                                        2026.26 p.202: width without mirrors, height)
    PORT_NOTE="real Model Y L, China owner's manual p.166",
    # China's six ($MTY87) and the US Marine Blue ($MTY83): order = Core.lua Specs colors (skin index is saved: only
    # append after release)
    PAINTS=[("StealthGrey", "PN01"), ("PearlWhite", "PPSW"), ("DiamondBlack", "PX02"), ("UltraRed", "PR01"),
            ("CosmicSilver", "PN03"), ("GlacierBlue", "PB01"), ("MarineBlue", "PB02")],
    # tex = a x official-ramp colour / GAIN + b (model_y.py CAL, the same skin pipeline: PAINT_Q, PAINT_TARGET, no
    # RAMP_SPLIT). Fitted in game (2026-11-11, 4a067bd body): modely-skin-sp --define views=S,N --define out=0 (option
    # 2, closest zoom) against the official FRONT34 / REAR34 with perf/paint_sheet.py --car MinidoracatTesla_ModelYL.
    # Slopes kept (the front fit asks 0.65-1.15, the rear the 1.6 clamp: no slope serves both views); offsets only, from
    # the Model Y start: round 1 put each channel's game p50 on FRONT34 through the measured skin-p50 -> game-p50 curve
    # (game ~ skin - 13 levels in the dark, ~ skin from 70 up), round 2 moved each channel toward its REAR34 residual
    # while keeping FRONT34 within 2 levels (tesla-ylb-skin1 / -skin2). Game p50 minus official now -3..+2 levels
    # front, -2..+7 rear (MOD repo temp/e2e-yl/paint/yl-paint-front.png, -rear.png). Calibration knob
    CAL={
        "StealthGrey": ((0.88, 0.88, 0.88), (0.092, 0.084, 0.077)),
        "PearlWhite": ((0.80, 0.80, 0.80), (0.201, 0.185, 0.185)),
        "DiamondBlack": ((0.99, 0.99, 0.99), (0.113, 0.108, 0.104)),
        "UltraRed": ((0.97, 0.97, 0.97), (0.071, 0.082, 0.093)),
        "CosmicSilver": ((0.90, 0.90, 0.90), (0.041, 0.037, 0.040)),
        "GlacierBlue": ((0.80, 0.80, 0.80), (0.095, 0.099, 0.101)),
        "MarineBlue": ((0.81, 0.81, 0.81), (0.117, 0.117, 0.108)),
    },
    # design studio (China; MarineBlue is only on the US $MTY83: its renders, same camera, were fetched by hand to
    # TMP/official, so `official` fails on it)
    COMPOSITOR_MODEL="my",
    OFFICIAL_OPTS="$MDLY,$MTY87,$STY6S,${},$WY19L,$IPB9",
    RAMP=dict(t=(0.40, 0.74), u=(0.04, 0.96), wheels=(0.18, 0.79), wt=0.80, wr=0.13),
    # ---- pzveh: wheel, 19" Machina 2.0 ($WY19L, official RIMCLOSEUP): a black aero cover, a five-pointed black star
    # of spokes (each forking into two thin blades to the rim), between the spokes five silver chevrons pointing in
    # (the spokes' machined side faces), a silver ring at the rim's edge. Here: the black face (WHEEL_FACETS) with the
    # Y spokes standing out of it as a dark grey star, the chevrons silver polygons on it. 255/45 R19 front, 275/45 R19
    # rear: one wheel model, the front's radius (the prep scales the source tyres to it)
    WHEEL_RIM=0.725,                       # 19" (241 mm bead + 17 mm flange) / 356 mm tyre radius
    WHEEL_SPOKE=dict(n=5, hub=0.16, fork=0.42, spread=math.radians(16), main=(0.20, 0.15), arm=0.07, cap=0.17,
                     inset=0.010, dish=0.008, depth=0.020, sweep=0.0),
    WHEEL_FACETS=dict(n=5, at=36, sink=0.008, rings=3, tip=0.55, notch=0.80, out_a=16, in_a=5, face="barrel"),
    WHEEL_DISC=dict(rotor=0.74, hat=0.30),
    WHEEL_RGB=dict(spoke=34, cap=30, barrel=10, lip=170, rotor=10, hat=10, dark=10, gap=8, tire=(22, 28), tread=20,
                   facet=170),             # the face (barrel swatch) darker than the star (spoke), silver chevrons
    # ---- pzveh: vehicle script
    OY=0.2878,
    WHEEL_LIFT=0.11,
    WHEEL_INSET=0.03,
    CAB_BOX=(1.30, 0.53, -1.70),
    # passengers / seats: front and 2nd row from the door openings (back: front, 2nd row); third: the 3rd row `back`
    # behind the rear doors' rear edge, over the rear axle (official interior renders), at side x (shoulder room 1,089
    # against 1,384 mm in the 2nd row, China owner's manual p.202), `drop` under the front (seat_head.py)
    SEAT=dict(x=0.326, h=0.5517, z=-0.2009, back=(0.12, -0.03), out=0.30, rear=0.017,
              third=dict(back=0.15, x=0.2766, drop=0.029)),
    BODY_W_Z=0.55,
    DOORS={
        "DoorFrontLeft": (-1, (0, 0, 1), -65, 0.8), "DoorFrontRight": (1, (0, 0, 1), 65, 0.8),
        "DoorRearLeft": (-1, (0, 0, 1), -65, 0.8), "DoorRearRight": (1, (0, 0, 1), 65, 0.8),
        "TrunkDoor": (0, (1, 0, 0), -75, 3.6), "EngineDoor": (0, (1, 0, 0), 55, 1.0),
    },
    GATE_IN=(0.0, 0.894, -0.447),
    GATE_HINGE="top",

    # ---- convert.py: the source (TMP/src, gitignored; temp/sketchfab-modely-std in the main checkout)
    SRC=("src", "source", "model_yl.obj"),
    SRC_C=(-1.0845, -1.7659),              # source X (length) and Y (width) centre, metres (inspect src_c, after the prep)
    SRC_SCALE=1.0,
    SRC_FLIP=False,
    BELT_Z=0.8717,                         # side window bottom (front door glass z min 0.870)
    TIRE_OBJ="Object005",
    DROP=("Object005", "Circle", "Cylinder", "Line0", "Object43",   # tyres, aero covers, rotors, calipers
          "Object_11", "Object_12",                                 # licence plates
          "Plane.031", "Plane.040", "Plane.051",   # clear lamp covers: opaque in PZ, they'd hide the lamps
          "Interior", "Hyundai_KONA", "Plane.067",   # BloxBloger's interior: the mod's own cabin (cabin.py)
          "Tesla_Model_3",               # rear TESLA: block letters sunk under the blade (Badge_TESLA instead)
          "Plane.072"),                  # DUAL MOTOR letters on the gate's right: the China Model Y L has none
    DROP_COMPS=(),
    CARBON=None,                           # (the blade spoiler is its own object, Blade_YL: prep_model_yl.py blade())
    ARCH_LINER=None,
    PLATES=(),
    SEAL_CLIP=False,
    RAIL=None,
    SEAM_SHADE=dict(reach=0.02, width=0.010, k=0.35, steep=0.5,
                    parts=("DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight", "EngineDoor"),
                    any_slope={"EngineDoor": 0.6}),
    DECIMATE={"Plane.045": 400,             # 29.5k-tri honeycomb under the tail light bar
              "Plane.034": 1200},
    PAINT_MAT="Material_#2125765635",       # the body paint (the mirror caps too)
    MAT_RGB={"black_base": (34, 34, 36), "black_reflection": (20, 20, 22), "black": (20, 20, 22),
             "Material_#2125767099": (26, 26, 28), "front_white_light": (226, 230, 236), "back_red_Light": (150, 12, 16),
             "red_plastic": (120, 12, 16), "M22": (120, 12, 16), "mirror": (58, 64, 72), "chrome": (96, 98, 104),
             "glass_base": (14, 14, 16), "glass_roof_panorama": (14, 14, 16),
             "spoiler_black": (12, 12, 14)},     # the blade spoiler (prep_model_yl.py BLADE_MAT): gloss black
    GLASS_MATS=("glass_base", "glass_roof_panorama"),
    GLASS_OPAQUE=(),
    GLASS_BACKS=(),
    ROOF_PANE="Plane.023",
    MIRROR_CAP="Plane.046",                # already body paint in this source
    LAMPS=dict(head=("front_white_light",), tail=("back_red_Light", "red_plastic", "M22"), tail_z=0.75, tail_y=-1.5,
               blade="Plane.034"),
    # part lines, side view (y, z): S, BF, BR off this source's panel edges (B pillar: unchanged by the prep); D the
    # rear door glass / quarter glass divider bar's middle; R1 (z ascending) the rear door's rear edge, upright from
    # the belt to the arch since the prep (work/outline.py)
    LINES={
        "S": ((-0.069, 0.4016), (-0.146, 0.9014)),
        "BF": ((-0.098, 0.9314), (-0.1925, 1.2894)),
        "BR": ((-0.2303, 0.9410), (-0.2815, 1.2989)),
        "D": ((-0.9048, 0.9511), (-0.9418, 1.2495)),
        "R1": ((-0.996, 0.632), (-0.999, 0.712), (-1.005, 0.770), (-1.011, 0.812), (-1.020, 0.868), (-1.029, 0.897),
               (-1.037, 0.923), (-1.018, 0.969), (-0.994, 0.999)),
    },
    FRONT_Y=0.91, SILL_Z=0.2217, ARCH=(0.5517, -0.91),
    IN_DOOR=dict(up=0.9017, x=0.42),
    IN_GATE=dict(y=-1.56, z=0.5017, up=0.9517, x_up=0.6124),
    DOOR_Y=(0.901, -0.100, -1.00),
    GATE_Z=0.5147,
    REAR_ARCH=(-1.2123, 0.2941, 0.40),
    GATE_X=0.5087,
    STOP_X=0.6371,
    PANELS=dict(x=0.6, z=0.7, front=(-0.2, 0.6), rear=(-1.0, -0.2), gate=(-1.5, 0.5), lid=(0.9, 0.6)),
    GUARDS=dict(front=(0.83, 0.9517, 0.4), rear=(-0.95, 1.1817, 0.45)),
    # components cut along the lines (object, tris): the window surround; the rear door glass and the quarter glass
    # are one component here
    CUT={("Plane.004", 342): ("BF", "BR", "D"), ("Plane.011", 268): ("D",)},
    PLANES={},
    CUT_X=_CUT_X,
    CUT_X_Y=None,
    DOOR_OBJS=("Plane.011", "Plane.004", "Plane.070", "Plane.019", "Plane.002", "Plane.046", "Plane.047", "Plane.048",
               "Plane.049", "Plane.050"),
    GATE_OBJS=_CUT_X + ("Blade_YL",),     # the blade spoiler rides the tailgate
    GATE_COMPS=(("Plane.011", 248, -1), ("Plane.006", 102, -1)),   # rear window and its frame (y sign of the centre)
    GATE_CUT_COMPS=(),
    PANES={"Body": {"WinT", "LightBarL", "WinLT", "WinRT"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"},
           "DoorRearLeft": {"WinLT"}, "DoorRearRight": {"WinRT"}, "TrunkDoor": {"WinH"}, "EngineDoor": set()},
    # badges (model_y.py): T on the frunk lid, TESLA on the light blade, and on the gate's lower left MODEL Y and the
    # Model Y L's three slanted bars (China $MTY87 REAR34: no 特斯拉 here, no Performance badge)
    T_BADGE=(1.914, 0.0644, 0.0677, 0.632, (0, 0.34, 0.94), (0, 0, -1)),
    TESLA=(0.9517, 0.03, 0.11, 0.045),
    LENS_X=0.4544,
    BADGE_Y=(-2.6, -1.85),
    BLADE=True,
    MODELY=("MODEL Y///", -0.4544, 0.5572, 0.033),
    PERF_BADGE=None,
    CALIPER=None,                          # the aero cover hides them (and the Y L's are not red)
    FRUNK_TUB=dict(ledge=0.08, rim=0.025, y=(1.151, 1.875), half=(0.29, 0.18), corner=0.07, taper=0.11, depth=0.29,
                   n=128),

    # ---- cabin.py (mesh coords, centred; ground z -0.751): the Model Y's front cabin + 0.100 in y (0.081 between the
    # two sources, 0.019 the prep's shorter nose and longer tail moving the mesh centre), - 0.001 in z
    CABIN_FLOOR=-0.4209,
    CABIN_FRONT_Y=1.1602,
    TRUNK_Y=-1.4308,           # trunk floor behind the 3rd row backrests
    TRUNK_WALL=True,
    HUMP_BACKS=False,
    REAR_DOOR_WALL=True,
    CABIN_ZC=-0.1009,
    SEAM_CLEAR=0.065,
    # seats: front buckets as the Model Y; the 2nd row two separate seats with an armrest each on the aisle side
    # (arms: height over the cushion, length, width; China owner's manual p.45 "armrests"), the 3rd row two seats
    # (model_x.py); `rear` (the bench) unused with `middle`
    SEATS=dict(front=dict(w=0.42, back=0.50, recline=32, dy=0.055, dz=-0.083),
               rear=dict(base=1.08, cushions=((-0.365, 0.36), (0, 0.33), (0.365, 0.36)), back=0.44, recline=10, dy=0.04,
                         dz=-0.077),
               middle=dict(w=0.42, back=0.50, recline=10, dy=0.035, dz=-0.068, arms=(0.16, 0.30, 0.05)),
               third=dict(w=0.36, back=0.34, head=0.42, recline=10, dy=0.028, dz=-0.068),
               sill=(1.00, 0.12), bin=(0.86, 0.20)),
    PARCEL=None,
    DASH=dict(console=(0, 0.2202, -0.3209), dash=(0, 0.9002, -0.0209), trim=(0, 0.7272, -0.0109),
              light=(0, 0.7292, -0.0339), stand=(0, 0.7402, 0.0891), screen=(0, 0.7102, 0.1691), wheel=(0.4572, 0.1311)),
    DOOR_CARD={
        "front": [
            ("upper trim", "end", (0.05, 0.10), -0.050, None, 0.060, 0.030, "dash", 0.012),
            ("ambient light", "end", (0.07, 0.16), -0.086, None, 0.007, 0.012, "screen", 0.002),
            ("armrest", "rear", 0.07, -0.215, 0.44, 0.050, 0.085, "seat", 0.018),
            ("pull handle", "rear", 0.13, -0.165, 0.26, 0.026, 0.050, "dash", 0.010),
            ("window switches", "rear", 0.31, -0.188, 0.13, 0.012, 0.060, "screen_back", 0.004),
            ("door button", "rear", 0.43, -0.186, 0.035, 0.012, 0.050, "trim", 0.004),
            ("map pocket", "end", (0.10, 0.30), -0.545, None, 0.085, 0.045, "base", 0.015),
            ("speaker grille", "front", 0.20, -0.400, 0.17, 0.150, 0.018, "console", 0.050),
        ],
        "rear": [
            ("upper trim", "end", (0.05, 0.05), -0.050, None, 0.060, 0.030, "dash", 0.012),
            ("ambient light", "end", (0.07, 0.07), -0.086, None, 0.007, 0.012, "screen", 0.002),
            ("armrest", "front", 0.06, -0.215, 0.38, 0.050, 0.080, "seat", 0.018),
            ("pull handle", "front", 0.10, -0.165, 0.22, 0.026, 0.050, "dash", 0.010),
            ("window switches", "front", 0.32, -0.188, 0.09, 0.012, 0.055, "screen_back", 0.004),
            ("map pocket", "end", (0.32, 0.05), -0.500, None, 0.080, 0.040, "base", 0.015),   # rear end: wheel arch
            ("speaker grille", "front", 0.08, -0.370, 0.14, 0.120, 0.018, "console", 0.045),
        ],
    },
)
