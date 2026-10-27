"""Model 3 Performance (Highland, $MT371): RBLXSupercars' "2024 Tesla Model 3" (Sketchfab, as re-posted by brandonleong28,
CC BY 4.0, CREDITS.md). CAR=model_3. Keys as in model_y.py (each is the module constant it sets). The source is a glTF
whose meshes Sketchfab merged by material (18 objects "Object_<n>"): doors, frunk lid and trunk lid are components of
one paint object or not separate at all, and the interior shares objects with exterior trim, so parts come from
components (DROP_COMPS, CUT keys (object, triangles), ROOF_PANE / MIRROR_CAP pairs) and the trunk lid is cut out of the
body shell (PLANES, GATE_CUT_COMPS). Material names do not match their contents (Georimblurlfsub01Mtl is underbody,
wheel wells and interior). Grid units, pre-centre frame (+Y front, +Z up, -X car left, ground z 0) unless noted;
numbers and sources: .claude/skills/tesla-dev/references/models.md "Model 3".
"""
import math

CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_m3",
    NAME="MinidoracatTesla_Model3",
    SCRIPT_MARK="---- geometry (TeslaModel3)",
    APP_CAR="app_car_model3_{}.png",       # not app_car_<paint> (Model Y's): six paints share names
    DIMS=(4.724, 1.848, 1.430),            # China owner's manual p.172 (Performance): length, width w/o mirrors, height
    # Performance paints offered in the US, DE and TW design studios (research 2026-10-28); Model Y's order, Deep
    # Blue in Glacier Blue's slot. Skin index is saved: only append after release
    PAINTS=[("StealthGrey", "PN01"), ("PearlWhite", "PPSW"), ("DiamondBlack", "PX02"), ("Quicksilver", "PN00"),
            ("UltraRed", "PR01"), ("DeepBlue", "PPSB"), ("MarineBlue", "PB02"), ("FrostBlue", "PB00")],
    # paint tone (model_y.py CAL): fitted on Model 3 game screenshots (modely-skin-sp --define car=..., option 2)
    CAL={
        "StealthGrey": ((1.01, 1.01, 1.01), (0.012, 0.005, -0.004)),
        "PearlWhite": ((0.92, 0.92, 0.92), (-0.055, -0.053, -0.060)),
        "DiamondBlack": ((0.84, 0.84, 0.84), (0.067, 0.053, 0.052)),
        "Quicksilver": ((1.07, 1.07, 1.07), (-0.104, -0.104, -0.127)),
        "UltraRed": ((1.04, 1.04, 1.04), (-0.066, 0.115, 0.072)),
        "DeepBlue": ((0.92, 0.92, 0.92), (0.110, 0.075, -0.009)),
        "MarineBlue": ((0.92, 0.92, 0.92), (0.083, 0.077, 0.045)),
        "FrostBlue": ((0.91, 0.91, 0.91), (-0.005, -0.010, -0.031)),
    },
    # design studio: Performance ($MT371), 20" Warp ($W30P), summer tires ($T30S), black interior ($IPB4); all 8
    # paints return 200 (research 2026-10-28)
    COMPOSITOR_MODEL="m3",
    OFFICIAL_OPTS="$APFA,$MDL3,$W30P,$MT371,$CPF2,$SC04,$T30S,${},$IPB4",
    # official_ramp: the SIDE render's paint rows / columns (car bbox fractions) and the wheel arches cut out
    RAMP=dict(t=(0.40, 0.76), u=(0.04, 0.96), wheels=(0.175, 0.795), wt=0.80, wr=0.14),
    # ---- pzveh: wheel, 20" Warp (official RIMCLOSEUP): five pairs of thin swept spokes in dark grey, open onto the
    # red caliper and the rotor; 235/35 R20 front, 275/30 R20 rear (both ~336 mm radius; the source's tires, 345 mm,
    # set the size: the arches were modelled round them)
    WHEEL_RIM=0.80,                        # rim flange radius / tire radius: 20" (254 mm bead + ~17 mm) / 336 mm
    WHEEL_SPOKE=dict(n=5, hub=0.12, fork=0.22, spread=math.radians(13), main=(0.065, 0.05), arm=0.045, cap=0.14,
                     inset=0.018, dish=0.020, depth=0.018, sweep=math.radians(32)),
    WHEEL_DISC=dict(rotor=0.655, hat=0.30),   # 355 mm rotor (US owner's manual p.215) / 271 mm flange
    WHEEL_RGB=dict(spoke=82, cap=36, barrel=26, lip=70, rotor=60, hat=35, dark=12, gap=8, tire=(22, 28), tread=20),
    # ---- pzveh: vehicle script
    OY=0.2878,                             # as Model Y (model_y.py)
    WHEEL_LIFT=0.11,                       # calibration knob (model_y.py)
    WHEEL_INSET=0.03,
    CAB_BOX=(1.25, 0.40, -1.30),
    SEAT=dict(x=0.33, h=0.47, z=-0.123, back=(0.12, 0.08), out=0.30),
    BODY_W_Z=0.55,                         # body width measured below this fraction of DIMS height (no mirrors)
    # the trunk lid hinges at its front edge under the rear window and swings up (-), power trunk
    DOORS={
        "DoorFrontLeft": (-1, (0, 0, 1), -65, 0.8), "DoorFrontRight": (1, (0, 0, 1), 65, 0.8),
        "DoorRearLeft": (-1, (0, 0, 1), -65, 0.8), "DoorRearRight": (1, (0, 0, 1), 65, 0.8),
        "TrunkDoor": (0, (1, 0, 0), -60, 3.0), "EngineDoor": (0, (1, 0, 0), 55, 1.0),
    },
    GATE_IN=(0.0, 0.6, -0.8),              # trunk lid inner panel: down under the deck, forward behind the rear face
    GATE_HINGE="front",
    # ---- convert.py: the source (TMP/src, gitignored; temp/sketchfab-model3-perf/src in the main checkout)
    SRC=("src", "source", "2024_tesla_model_3.glb"),
    SRC_C=(-5.2665, -9.9305),              # source bbox centre, x (length) and y (width), source units
    SRC_SCALE=4.724 / 17.513,              # metres per source unit: official length / source length
    SRC_FLIP=True,                         # glTF import: front +X, left +Y
    BELT_Z=0.79,                           # side windows' visible lower edge (the panes run 6 cm deeper into the doors)
    TIRE_OBJ="Object_19",                  # all four tires in one object (tire_groups)
    DROP=("Object_19", "Object_15",        # tires, rims: the mod's procedural wheel
          "Object_2", "Object_3", "Object_4", "Object_5", "Object_8"),   # screens, interior trim: the mod's cabin
    # components dropped by bbox centre (objects, lo, hi): the interior and trunk lining (the mod's cabin), the frunk
    # tub and lid underside (frunk_tub, the lid slab), the clear lamp lenses (opaque in PZ), the source's badges
    # (TESLA, DUAL MOTOR, T: badges() draws ours)
    DROP_COMPS=((("Object_12", "Object_13", "Object_14", "Object_18"), (-0.62, -1.45, 0.25), (0.62, 0.92, 1.20)),
                (("Object_13", "Object_14"), (-0.35, 0.92, 0.50), (0.35, 1.95, 0.80)),
                (("Object_9",), (-0.9, -2.1, 0.0), (0.9, -1.3, 1.2)),
                (("Object_9",), (-0.9, 1.3, 0.0), (0.9, 2.1, 1.2)),
                (("Object_13",), (-0.45, -1.95, 0.70), (0.45, -1.85, 0.76)),
                (("Object_13",), (0.25, -1.90, 0.54), (0.42, -1.82, 0.57)),
                (("Object_12", "Object_13"), (-0.05, 1.77, 0.45), (0.05, 1.87, 0.56)),
                # fins behind the lower intake (z 0.36-0.40, y 1.42-1.70): the frunk bin's floor passes through them
                (("Object_13",), (-0.30, 1.40, 0.35), (0.30, 1.72, 0.41))),
    # the source has no wheel-arch liners (its wheel houses were the interior tub, dropped above)
    ARCH_LINER=dict(gap=0.05, inner=0.05, arc=(-20, 200), n=17),
    # black plates (polygons) behind the front intakes where nothing closes them (the fins dropped above; the slot over the lip
    # had nothing behind it): else they showed the ground
    PLATES=(("IntakePlate", ((-0.32, 1.70, 0.28), (0.32, 1.70, 0.28), (0.32, 1.70, 0.46), (-0.32, 1.70, 0.46)),
             (0, 1, 0), "arch_liner"),
            ("SlotPlate", ((-0.46, 1.76, 0.12), (0.46, 1.76, 0.12), (0.46, 1.76, 0.30), (-0.46, 1.76, 0.30)),
             (0, 1, 0), "arch_liner"),
            ("SlotFloor", ((-0.46, 1.50, 0.15), (0.46, 1.50, 0.15), (0.46, 1.73, 0.15), (0.30, 1.84, 0.15),
                           (0.0, 1.87, 0.15), (-0.30, 1.84, 0.15), (-0.46, 1.73, 0.15)), (0, 0, 1), "arch_liner")),
    # collapse-decimated after DROP_COMPS (target tris): underbody, arches, lamp housings and mirror housings at
    # 26k tris after the interior is gone; the build prints their components' new sizes (COMPS)
    DECIMATE={"Object_11": 13000, "Object_13": 6000, "Object_6": 2500},
    PAINT_MAT="Geohoodsub00021Mtl",
    MAT_RGB={"Geodoorl2sub11Mtl": (20, 20, 22),         # window frames, seals, door handles (black)
             "Geodoorl2sub31Mtl": (14, 14, 16), "Geodoorr2sub31Mtl": (14, 14, 16), "Geoextwindow0021Mtl": (14, 14, 16),
             "Geohoodsub00031Mtl": (150, 154, 160),     # headlamp reflectors, chrome bits
             "Georimblurlfsub01Mtl": (22, 22, 24),       # underbody, arches, grille, lamp housings, front lip
             "Ln12Mtl": (150, 12, 16), "Ln1Mtl": (190, 110, 40), "Ln7Mtl": (226, 230, 236)},
    GLASS_MATS=("Geodoorl2sub31Mtl", "Geodoorr2sub31Mtl", "Geoextwindow0021Mtl"),
    GLASS_OPAQUE=(),
    GLASS_BACKS=("WinH", "WinLH", "WinLT", "WinRH", "WinRT"),   # one-sided panes in the source: reversed copies
    ROOF_PANE=("Object_10", 256),          # the glass roof between windscreen and rear window
    MIRROR_CAP=("Object_11", (182, 183)),       # body-colour caps (both sides): on the front doors, no inner panel
    LAMPS=dict(head=("Ln7Mtl",), tail=("Ln12Mtl",), tail_z=0.6, tail_y=-1.4, blade=None),
    # part lines, side view (y, z), read off the source's panel gaps
    LINES={
        "S": ((-0.150, 0.22), (-0.185, 0.78)),   # front / rear door seam below the belt
        "BF": ((-0.137, 0.79), (-0.244, 1.09)),  # B-pillar trim front edge
        "BR": ((-0.264, 0.79), (-0.329, 1.09)),  # B-pillar trim rear edge
        "D": ((-0.939, 0.83), (-0.976, 1.03)),   # rear door frame rear edge (no quarter glass)
        "R1": ((-0.86, 0.37), (-1.078, 0.78)),   # rear door rear edge down to the wheel arch
    },
    FRONT_Y=0.80, SILL_Z=0.19, ARCH=(0.0, -9.0),     # R1 already clears the arch
    IN_DOOR=dict(up=0.80, x=0.42),
    IN_GATE=dict(y=-1.40, z=0.525, up=9.0, x_up=0.49),   # trunk lid: behind the rear window's foot, above its lower edge
    DOOR_Y=(0.79, -0.165, -1.0),
    GATE_Z=0.525,                          # trunk lid's lower edge (the plate recess bottom)
    REAR_ARCH=(-1.15, 0.285, 0.40),
    GATE_X=0.49,                           # trunk lid side seams (deck and rear face; through the tail lamps)
    STOP_X=0.57,
    PANELS=dict(x=0.6, z=0.85, front=(-0.2, 0.6), rear=(-1.0, -0.2), gate=(-9.0, 9.0), lid=(0.9, 0.55)),
    GUARDS=dict(front=(0.75, 0.80, 0.4), rear=(-0.95, 0.85, 0.45)),
    # the body shell (rear quarters, roof, rear face and the trunk lid in one) is cut along the lid's seams; the
    # window frame trim spans both doors and the C pillar
    CUT={("Object_11", 5889): ("X+", "X-", "GZ"), ("Object_6", 241): ("BF", "BR", "D")},
    PLANES={"GZ": ((0, 0, 0.525), (0, 0, 1), -1.30)},   # name: (point, normal, cut faces behind this y)
    CUT_X=("Object_12", "Object_13", "Object_14", "Object_16", "Object_17"),   # cut along +-GATE_X
    CUT_X_Y=-1.35,
    DOOR_OBJS=("Object_6", "Object_7", "Object_9", "Object_12", "Object_13", "Object_14", "Object_17", "Object_18"),
    GATE_OBJS=("Object_12", "Object_13", "Object_14", "Object_16", "Object_17"),
    GATE_COMPS=(),
    GATE_CUT_COMPS=(("Object_11", 5889),),
    CARBON=dict(x=0.62, y=-1.70, z=(0.805, 0.95), depth=0.035, rgb=(30, 30, 32)),   # Performance spoiler ($SLR1)
    PANES={"Body": {"WinT", "LightBarL", "WinH"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"},
           "DoorRearLeft": {"WinLT"}, "DoorRearRight": {"WinRT"}, "TrunkDoor": set(), "EngineDoor": set()},
    # badges: T on the nose (where the source has it), TESLA across the trunk lid between the tail lamps, the
    # Performance badge on the lid's lower right (service manual "Performance Badge - Rear"); no MODEL 3 (official
    # REAR34)
    T_BADGE=(1.83, 0.0644, 0.0677, 0.53, (0, 0.92, 0.39), None),   # y, width, height, z, normal, ray (None: -normal)
    TESLA=(0.738, 0.025, 0.11, 0.045),
    LENS_X=0.46,
    BADGE_Y=(-2.3, -2.0),
    BLADE=False,
    MODELY=None,
    PERF_BADGE=(0.34, 0.565, 0.09, 0.04),
    # model_y.py CALIPER; the wheel is 4 cm narrower, so the front pair spans less (at 18 deg / 4.5 cm it reached the
    # spokes at full lock)
    CALIPER=dict(front=(176, 12), rear=(80, 15), r=(0.100, 0.168), x=(0.008, 0.040)),
    # frunk 88 L (owner's manual p.173): the lid's rear edge arches forward to y 1.08 on the centre line, its side
    # seams close in to |x| 0.36 at the nose (cavity render of the source)
    FRUNK_TUB=dict(ledge=0.06, rim=0.025, y=(1.12, 1.64), half=(0.33, 0.22), corner=0.07, taper=0.07, depth=0.215,
                   n=128),
    # ---- cabin.py (mesh coords, centred)
    CABIN_FLOOR=-0.33,
    CABIN_FRONT_Y=1.08,
    TRUNK_Y=-1.0,
    CABIN_ZC=-0.04,
    SEAM_CLEAR=0.065,
    # Model 3 and Model Y share the front seats; the source's rear bench is 1.09 wide like Model Y's (model_y.py SEATS)
    SEATS=dict(front=dict(w=0.42, back=0.50, recline=14),
               rear=dict(base=1.08, cushions=((-0.365, 0.36), (0, 0.33), (0.365, 0.36)), back=0.44, recline=18),
               sill=(1.00, 0.12), bin=(0.86, 0.40)),
    # parcel shelf: from the rear backrests' top to the rear window's foot (z 0.906 pre-centre), top just under it
    PARCEL=dict(y=(-0.97, -1.62), z=0.27, t=0.03, n=9, inset=0.02),
    DASH=dict(console=(0, 0.12, -0.25), dash=(0, 0.80, 0.05), trim=(0, 0.627, 0.06), light=(0, 0.629, 0.035),
              stand=(0, 0.64, 0.16), screen=(0, 0.61, 0.24), wheel=(0.50, 0.11)),
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
