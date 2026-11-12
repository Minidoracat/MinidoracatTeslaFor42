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

# components by (object, triangles) after prep_model_3.py and the decimation (the build's COMPS lines): they change
# whenever the prep's field does
_SHELL = ("Object_11", 5913)               # the body shell: roof, rear quarters, tail, trunk lid
_BUMPER = ("Object_11", 1574)              # the front bumper
_MIRRORS = ("Object_11", (188, 186))       # the mirror caps (left, right)
_FRAMES = (245, 239)                       # Object_6: the window frame trims along both doors (left, right)
_DIFFUSER = ("Object_13", 506)            # the black rear diffuser under the bumper
# the Performance front's black lower intake (CARBON, official FRONT34 through camfit's c2 camera, 2026-11-12): its
# top edge (|x|, z) falls from z 0.28 in the middle to 0.145 at the corners; the shipped box (|x| 0.60, z 0.28)
# blacked the near corner, which the official has in body colour, and sat 17-43 mm high
_FRONT_BLACK = ((0.15, 0.28), (0.40, 0.25), (0.56, 0.145))
_FRONT_LINES = tuple(zip(_FRONT_BLACK[:-1], _FRONT_BLACK[1:]))
_FRONT_LIP = 0.185                           # z: the black lip under the bumper corners (CARBON third zone)
# the rear diffuser's black top edge (|x|, z), official REAR34 through camfit's c2 camera (2026-11-13): z 0.355 in the
# middle, down the bumper's corners to 0.17 at |x| 0.565 (the source's black ran 1-3 cm low in the middle, 2 cm high
# at the corners); concave, so "below every line" is the region under it
_REAR_BLACK = ((0.0, 0.355), (0.2, 0.352), (0.30, 0.344), (0.41, 0.328), (0.45, 0.317), (0.475, 0.302), (0.50, 0.279),
               (0.52, 0.254), (0.565, 0.17))
_REAR_LINES = tuple(zip(_REAR_BLACK[:-1], _REAR_BLACK[1:]))


def _below(a, b):
    """The plane along x through the (|x|, z) points a, b on each side (+x, -x): (point, normal up)."""
    (x1, z1), (x2, z2) = a, b
    n = math.hypot(z1 - z2, x2 - x1)
    return [((sd * x1, 0, z1), (sd * (z1 - z2) / n, 0, (x2 - x1) / n)) for sd in (1, -1)]


_REAR_PLANES = tuple(pn for ln in _REAR_LINES for pn in _below(*ln))
_RB = tuple(f"RB{i}{c}" for i in range(len(_REAR_LINES)) for c in "+-")   # their PLANES names, middle lines first


CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_m3",
    NAME="MinidoracatTesla_Model3",
    SCRIPT_MARK="---- geometry (TeslaModel3)",
    APP_CAR="app_car_model3_{}.png",       # not app_car_<paint> (Model Y's): six paints share names
    # US owner's manual 2025-10 PDF p.215 (Performance; the 2026-11 China manual p.183: width 1,848, height 1,430):
    # length, width w/o mirrors, height, what prep_model_3.py fits the body to
    DIMS=(4.724, 1.850, 1.431),
    PORT_NOTE='real Model 3, owner\'s manual "Charging Instructions"',
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
    # ---- pzveh: wheel, 20" Warp (official RIMCLOSEUP): a dark wheel read by its ten thin grey spokes, in five swept V
    # pairs from the hub (a Y spoke with thin arms: model_y.py WHEEL_SPOKE), round matte-black aero faces and the red
    # caliper. Five wide grey blades (spoke 44 over a 60 rotor) read in game as a flat grey disc with red dots (user
    # 2026-10-28). Thin dark arms since 2026-11-13 (official SIDE front wheel: wheel mean luminance 32, ours 35; arms
    # 3-4 px; the old 95-grey swept blades read as a pinwheel). 235/35 R20 front, 275/30 R20 rear (both ~336 mm radius; the source's tires, 345 mm, set the size:
    # the arches were modelled round them)
    WHEEL_RIM=0.80,                        # rim flange radius / tire radius: 20" (254 mm bead + ~17 mm) / 336 mm
    WHEEL_SPOKE=dict(n=5, hub=0.12, fork=0.30, spread=math.radians(17), main=(0.055, 0.06), arm=0.024, cap=0.14,
                     inset=0.018, dish=0.020, depth=0.018, sweep=math.radians(14)),
    WHEEL_DISC=dict(rotor=0.655, hat=0.30),   # 355 mm rotor (US owner's manual p.215) / 271 mm flange
    WHEEL_RGB=dict(spoke=52, cap=30, barrel=22, lip=110, rotor=20, hat=18, dark=12, gap=8, tire=(22, 28), tread=20),
    # ---- pzveh: vehicle script
    OY=0.1978,                             # CoM = mesh centre - OY; brake knob (model_y.py). The sedan's lower body and
    #                                        higher wheel mounts put Model Y's 0.2878 ~0.09 nearer the ground: braking
    #                                        unloads the rear wheels less and it stopped 17% shorter than SportsCar
    WHEEL_LIFT=0.11,                       # calibration knob (model_y.py)
    # the tyres (US owner's manual 2025-10 PDF p.219, Performance 20"): 235/35 R20 front (r 254 + 0.35 x 235 = 336.3
    # mm), 275/30 R20 rear (336.5 mm); a wheel model each (models.md TIRE_AXLES). Widths less 5.3 mm: pzveh
    # wheel_profile's sidewall bulges 0.0022 grid past the width a side, so the wheel reads 235 / 275 across. The
    # track (p.215: 1,582 / 1,560 mm, wheel centres) by the inset: the source's tyres' outer faces 921 / 930 mm off the
    # centre line
    TIRE_AXLES=dict(front=(0.3363, 0.2297), rear=(0.3365, 0.2697)),
    WHEEL_INSET=0.0105,
    CAB_BOX=(1.25, 0.40, -1.30),
    # seats (scripts/blender/skf/seat_head.py, 2026-11-01; the driver's head was 116 mm through the roof): heads and caps
    # under the roof, the feet on CABIN_FLOOR in the seated clips (scripts/seat_anim.py), rear row `rear` lower; SEATS
    # dz / dy put the cushions and backrests against the body
    SEAT=dict(x=0.33, h=0.384, z=-0.222, back=(0.16, 0.08), out=0.30, rear=0.027),
    BODY_W_Z=0.55,                         # body width measured below this fraction of DIMS height (no mirrors)
    # the trunk lid hinges at its front edge under the rear window and swings up (-), power trunk
    DOORS={
        "DoorFrontLeft": (-1, (0, 0, 1), -65, 0.8), "DoorFrontRight": (1, (0, 0, 1), 65, 0.8),
        "DoorRearLeft": (-1, (0, 0, 1), -65, 0.8), "DoorRearRight": (1, (0, 0, 1), 65, 0.8),
        "TrunkDoor": (0, (1, 0, 0), -60, 3.0), "EngineDoor": (0, (1, 0, 0), 55, 1.0),
    },
    # trunk lid inner panel: down under the deck, forward behind the rear face; mostly forward: (0, 0.6, -0.8)
    # carried the plate recess ledge's panel 17 mm out through the recess wall (seals analyze.py, from the side)
    GATE_IN=(0.0, 0.9, -0.44),
    GATE_HINGE="front",
    # ---- convert.py: the source (TMP/src, gitignored; temp/sketchfab-model3-perf/src in the main checkout)
    SRC=("src", "source", "model_3.obj"),  # prep_model_3.py's output from 2024_tesla_model_3.glb (run it first)
    SRC_C=(-5.2665, -9.9305),              # source bbox centre, x (length) and y (width), source units
    SRC_SCALE=4.724 / 17.513,              # metres per source unit: official length / source length
    SRC_FLIP=True,                         # glTF import: front +X, left +Y
    BELT_Z=0.791,                           # side windows' visible lower edge (the panes run 6 cm deeper into the doors)
    TIRE_OBJ="Object_19",                  # all four tires in one object (tire_groups)
    DROP=("Object_19", "Object_15",        # tires, rims: the mod's procedural wheel
          "Object_2", "Object_3", "Object_4", "Object_5", "Object_8"),   # screens, interior trim: the mod's cabin
    # components dropped by bbox centre (objects, lo, hi): the interior and trunk lining (the mod's cabin), the frunk
    # tub and lid underside (frunk_tub, the lid slab), the clear lamp lenses (opaque in PZ), the source's badges
    # (TESLA, DUAL MOTOR, T: badges() draws ours). The interior box leaves out the B pillars' outer band (|x| > 0.58,
    # z > 0.88, y -0.36..-0.13): the black B-pillar trim (Object_13, 112 tris a side, centre |x| 0.595) and its two
    # edge seals (Object_13 / Object_14, 8-24 tris) sit there; one box to |x| 0.62 dropped them and from outside there
    # was nothing between the front and rear door glass (2026-11-12, in game since release)
    DROP_COMPS=(*((("Object_12", "Object_13", "Object_14", "Object_18"), lo, hi) for lo, hi in (
                    ((-0.62, -1.45, 0.25), (0.62, 0.91, 0.88)), ((-0.58, -1.45, 0.88), (0.58, 0.91, 1.20)),
                    *(((s0, y0, 0.88), (s1, y1, 1.20)) for s0, s1 in ((-0.62, -0.58), (0.58, 0.62))
                      for y0, y1 in ((-1.45, -0.36), (-0.13, 0.91))))),
                (("Object_13", "Object_14"), (-0.35, 0.92, 0.50), (0.35, 1.95, 0.80)),
                (("Object_9",), (-0.9, -2.1, 0.0), (0.9, -1.3, 1.2)),
                (("Object_9",), (-0.9, 1.3, 0.0), (0.9, 2.1, 1.2)),
                (("Object_13",), (-0.45, -1.95, 0.70), (0.45, -1.85, 0.76)),
                (("Object_13",), (0.25, -1.90, 0.54), (0.42, -1.82, 0.57)),
                (("Object_12", "Object_13"), (-0.05, 1.77, 0.45), (0.05, 1.87, 0.56)),
                # fins behind the lower intake (z 0.36-0.40, y 1.42-1.70): the frunk bin's floor passes through them
                (("Object_13",), (-0.30, 1.40, 0.35), (0.30, 1.72, 0.41)),
                # the source rims' leftovers on each axle (hub, brake disc, a 45 cm black ring in the rim's outer
                # plane): in front of the mod's wheel they hid its hub and lip (a black disc in game)
                *((("Object_13",), (x - 0.09, y - 0.05, 0.25), (x + 0.09, y + 0.05, 0.32))
                  for x in (-0.71, 0.71) for y in (1.225, -1.15))),
    # the source has no wheel-arch liners (its wheel houses were the interior tub, dropped above)
    ARCH_LINER=dict(gap=0.05, inner=0.05, arc=(-20, 200), n=17),
    # black plates (polygons) behind the front intakes where nothing closes them (the fins dropped above; the slot over the lip
    # had nothing behind it): else they showed the ground
    PLATES=(("IntakePlate", ((-0.32, 1.692, 0.2825), (0.32, 1.692, 0.2825), (0.32, 1.692, 0.4644), (-0.32, 1.692, 0.4644)),
             (0, 1, 0), "arch_liner"),
            ("SlotPlate", ((-0.46, 1.749, 0.128), (0.46, 1.749, 0.128), (0.46, 1.749, 0.3025), (-0.46, 1.749, 0.3025)),
             (0, 1, 0), "arch_liner"),
            ("SlotFloor", ((-0.46, 1.492, 0.156), (0.46, 1.492, 0.156), (0.46, 1.72, 0.156), (0.30, 1.83, 0.156),
                           (0.0, 1.86, 0.156), (-0.30, 1.83, 0.156), (-0.46, 1.72, 0.156)), (0, 0, 1), "arch_liner"),
            # behind the B pillar trim's rear edge (BR, leaning with the glass): there the trim, its edge seals (a few
            # mm, turned forward) and the rear door glass leave a slit, and through the rear window the seals read as a
            # dotted black line on the cabin's grey (NE, 2026-11-13); without the seals it was see-through
            *((f"BPillarGap{'LR'[sd > 0]}", ((sd * 0.633, -0.300, 0.80), (sd * 0.633, -0.245, 0.80),
                                             (sd * 0.523, -0.300, 1.09), (sd * 0.523, -0.355, 1.09)),
               (sd * 0.93, 0, 0.36), "arch_liner") for sd in (-1, 1))),
    # the paint is a thin shell folded round every panel edge (outer face, hem, inner face a few mm behind), so the
    # inner face's open edge got a seal strip "behind" it, out through the outer face: 1-2 px black dashes along the
    # door seams in game. Seal strips that pass through any surface are dropped
    SEAL_CLIP=True,
    SEAL_COVER=0.015,                       # convert.py seals(): the strips past the sills' and arch lips' outer edges stuck out
    # the roof is glass, so the paint up there is the roof rails (from the A- and C-pillar tops): facing up at the top
    # of the car they took the brightest paint tone (convert.textures: up + height terms) and the game lights up-facing
    # faces more, a bright white band over the side windows where the official SIDE has a thin body-colour line. Paint
    # centred above z (pre-centre) takes the paint's median tone, blended in from z0 (no step along the pillars)
    RAIL=(0.926, 1.032),
    # the panel gaps shaded in the skin (convert.py seam_shade, model_y.py): a dotted line at the closest zoom
    SEAM_SHADE=dict(reach=0.02, width=0.010, k=0.35, steep=0.5,
                    parts=("DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight", "EngineDoor"),
                    any_slope={"EngineDoor": 0.6}),
    # collapse-decimated after DROP_COMPS (target tris): underbody, arches, lamp housings and mirror housings at
    # 26k tris after the interior is gone; the build prints their components' new sizes (COMPS)
    DECIMATE={"Object_11": 13000, "Object_13": 6000, "Object_6": 2500},
    PAINT_MAT="Geohoodsub00021Mtl",
    MAT_RGB={"Geodoorl2sub11Mtl": (20, 20, 22),         # window frames, seals, door handles (black)
             "Geodoorl2sub31Mtl": (14, 14, 16), "Geodoorr2sub31Mtl": (14, 14, 16), "Geoextwindow0021Mtl": (14, 14, 16),
             "Geohoodsub00031Mtl": (150, 154, 160),     # headlamp reflectors, chrome bits
             "Georimblurlfsub01Mtl": (22, 22, 24),       # underbody, arches, grille, lamp housings, front lip
             # Ln1Mtl: the headlamps' inner lower strip, dark like the official FRONT34 there (72, 72, 76 rendered;
             # it was amber, 190 110 40, which the official never shows)
             "Ln12Mtl": (150, 12, 16), "Ln1Mtl": (112, 112, 110), "Ln7Mtl": (226, 230, 236)},
    GLASS_MATS=("Geodoorl2sub31Mtl", "Geodoorr2sub31Mtl", "Geoextwindow0021Mtl"),
    GLASS_OPAQUE=(),
    GLASS_BACKS=("WinH", "WinLH", "WinLT", "WinRH", "WinRT"),   # one-sided panes in the source: reversed copies
    ROOF_PANE=("Object_10", 256),          # the glass roof between windscreen and rear window
    MIRROR_CAP=_MIRRORS,       # body-colour caps (both sides): on the front doors, no inner panel
    LAMPS=dict(head=("Ln7Mtl",), tail=("Ln12Mtl",), tail_z=0.6045, tail_y=-1.408, blade=None),
    # part lines, side view (y, z), read off the source's panel gaps
    LINES={
        "S": ((-0.158, 0.225), (-0.193, 0.781)),   # front / rear door seam below the belt
        "BF": ((-0.145, 0.791), (-0.244, 1.103)),  # B-pillar trim front edge
        "BR": ((-0.272, 0.791), (-0.333, 1.104)),  # B-pillar trim rear edge
        "D": ((-0.947, 0.832), (-0.984, 1.045)),   # rear door frame rear edge (no quarter glass)
        "R1": ((-0.868, 0.373), (-1.086, 0.781)),   # rear door rear edge down to the wheel arch
    },
    FRONT_Y=0.792, SILL_Z=0.198, ARCH=(0.0, -9.0),     # R1 already clears the arch
    IN_DOOR=dict(up=0.801, x=0.42),
    IN_GATE=dict(y=-1.408, z=0.530, up=9.0, x_up=0.4895),   # trunk lid: behind the rear window's foot, above its lower edge
    DOOR_Y=(0.782, -0.173, -1.008),
    GATE_Z=0.530,                          # trunk lid's lower edge (the plate recess bottom)
    REAR_ARCH=(-1.158, 0.2875, 0.40),
    GATE_X=0.4895,                           # trunk lid side seams (deck and rear face; through the tail lamps)
    STOP_X=0.569,
    PANELS=dict(x=0.599, z=0.852, front=(-0.208, 0.592), rear=(-1.008, -0.208), gate=(-9.0, 9.0), lid=(0.892, 0.555)),
    GUARDS=dict(front=(0.742, 0.8025, 0.4), rear=(-0.958, 0.853, 0.45)),
    # the body shell (rear quarters, roof, rear face and the trunk lid in one) is cut along the lid's seams; the
    # window frame trim spans both doors and the C pillar
    CUT={_SHELL: ("X+", "X-", "GZ", "CZ", "GY", *_RB[:8]), **{("Object_6", n): ("BF", "BR", "D") for n in _FRAMES},
         _BUMPER: ("FZ", "FX+", "FX-", "FL", *(f"FS{i}{c}" for i in range(len(_FRONT_LINES)) for c in "+-")),
         _DIFFUSER: _RB},
    # name: (point, normal, cut faces centred behind this y); GZ: the trunk lid's lower edge; FZ / FX+-: the edges of
    # the black lower front intake, CZ: the spoiler band's lower edge on the lid's rear face (CARBON), so their
    # borders run straight instead of along big triangles (CZ only behind y -1.85: the body's tail-lamp tops beside
    # the lid's corners, cut there, grew SEAL strips that stood out of them as black wedges); GY: the lid's front edge (IN_GATE y): uncut, the lid's
    # front corners went along the triangles, a stair of jamb teeth and body slivers in the opening once it lifted
    PLANES={"GZ": ((0, 0, 0.530), (0, 0, 1), -1.308), "FZ": ((0, 0, _FRONT_BLACK[0][1]), (0, 0, 1), 9.0),
            "FX+": ((0.60, 0, 0), (1, 0, 0), 9.0), "FX-": ((-0.60, 0, 0), (1, 0, 0), 9.0), "FL": ((0, 0, _FRONT_LIP), (0, 0, 1), 9.0),
            **{f"FS{i}{'+-'[k]}": (*pn, 9.0) for i, ln in enumerate(_FRONT_LINES) for k, pn in enumerate(_below(*ln))},
            "CZ": ((0, 0, 0.827), (0, 0, 1), -1.85), "GY": ((0, -1.408, 0), (0, 1, 0), -1.308),
            # the rear diffuser's black top (_REAR_BLACK); the shell only along the four middle lines (the corner ones
            # would cross the whole tail behind y -1.6)
            **{nm: (*pn, -1.6) for nm, pn in zip(_RB, _REAR_PLANES)}},
    CUT_X=("Object_12", "Object_13", "Object_14", "Object_16", "Object_17"),   # cut along +-GATE_X
    CUT_X_Y=-1.308,                         # the lid's side seams from ahead of its front edge (GY) back
    DOOR_OBJS=("Object_6", "Object_7", "Object_9", "Object_12", "Object_13", "Object_14", "Object_17", "Object_18"),
    GATE_OBJS=("Object_12", "Object_13", "Object_14", "Object_16", "Object_17"),
    GATE_COMPS=(),
    GATE_CUT_COMPS=(_SHELL,),
    # black paint zones (convert.classify): the carbon spoiler ($SLR1) as a band 3.5 cm deep along the trunk lid's
    # trailing edge; the Performance front's black lower intake across the bumper under _FRONT_BLACK (official
    # FRONT34; the corners stay body colour)
    CARBON=dict(rgb=(30, 30, 32), zones=(dict(lo=(-0.62, -9.0, 0.827), hi=(0.62, -1.708, 0.975), edge=(1, 0.035)),
                                        dict(lo=(-0.60, 1.60, 0.0), hi=(0.60, 9.0, _FRONT_BLACK[0][1]),
                                             below=tuple(pn for ln in _FRONT_LINES for pn in _below(*ln))),
                                        # the black lip under the corners to the front wheels (official FRONT34): the
                                        # body-coloured corner fins stand between it and the intake
                                        dict(lo=(-0.82, 1.50, 0.0), hi=(0.82, 9.0, _FRONT_LIP), of=_BUMPER),
                                        # the rear diffuser's black up to _REAR_BLACK on the bumper's middle
                                        dict(lo=(-0.62, -9.0, 0.0), hi=(0.62, -1.60, 0.40), of=_SHELL,
                                             below=_REAR_PLANES))),
    # ... and its corners body colour above it (the source's black ran 2 cm higher there)
    PAINT_OVER=(dict(of=_DIFFUSER, lo=(-0.62, -9.0, 0.175), hi=(0.62, -1.60, 0.40), above=_REAR_PLANES,
                     facing=((0, -1, 0), (0.28, 1.0))),),
    PANES={"Body": {"WinT", "LightBarL", "WinH"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"},
           "DoorRearLeft": {"WinLT"}, "DoorRearRight": {"WinRT"}, "TrunkDoor": set(), "EngineDoor": set()},
    # badges: T on the nose (where the source has it), TESLA across the trunk lid between the tail lamps, the
    # Performance badge on the lid's lower right (service manual "Performance Badge - Rear"); no MODEL 3 (official
    # REAR34)
    T_BADGE=(1.840, 0.0644, 0.0677, 0.535, (0, 0.92, 0.39), None),   # y, width, height, z, normal, ray (None: -normal)
    TESLA=(0.7396, 0.025, 0.11, 0.045),
    LENS_X=0.46,
    BADGE_Y=(-2.3, -2.0),
    BLADE=False,
    MODELY=None,
    PERF_BADGE=(0.3396, 0.570, 0.09, 0.04),
    # model_y.py CALIPER; the wheel is 4 cm narrower, so the front pair spans less (at 18 deg / 4.5 cm it reached the
    # spokes at full lock)
    CALIPER=dict(front=(176, 12), rear=(80, 15), r=(0.100, 0.168), x=(0.008, 0.040)),
    # frunk 88 L (owner's manual p.173): the lid's rear edge arches forward to y 1.08 on the centre line, its side
    # seams close in to |x| 0.36 at the nose (cavity render of the source)
    FRUNK_TUB=dict(ledge=0.06, rim=0.025, y=(1.112, 1.645), half=(0.33, 0.22), corner=0.07, taper=0.07, depth=0.215,
                   n=128),
    # ---- cabin.py (mesh coords, centred; prep_model_3.py moved the centre: y -0.0059, zmid +0.0127, the values
    # below follow the body through it, `prep_model_3.py -- map`)
    CABIN_FLOOR=-0.474,                    # under the seated feet (seat_head.py feet), just over the underbody
    # cabin.py trunk_walls: the rear doors' walls' floor corner 12 mm in (straight under the wall's lowest ray hit it
    # stood 2-3 mm out of the sill's undercut, below the rear doors: a 1 px black dash in game, SW, 2026-11-13)
    FLOOR_IN=0.012,
    CABIN_FRONT_Y=1.078,
    TRUNK_Y=-1.002,
    REAR_DOOR_WALL=True,                   # cabin.py trunk_walls through the rear door openings (user 2026-11-01)
    HUMP_BACKS="trunk",                    # two-sided arch humps only in the trunk (cabin.py; rear doors, 2026-11-01)
    CABIN_ZC=-0.048,
    SEAM_CLEAR=0.065,
    # Model 3 and Model Y share the front seats; the source's rear bench is 1.09 wide like Model Y's (model_y.py SEATS)
    SEATS=dict(front=dict(w=0.42, back=0.50, recline=32, dy=0.059, dz=-0.121),
               rear=dict(base=1.08, cushions=((-0.365, 0.36), (0, 0.33), (0.365, 0.36)), back=0.44, recline=10, dy=0.03,
                         dz=-0.112),
               sill=(1.00, 0.12, 0.004), bin=(0.86, 0.40)),
    # parcel shelf: from the rear backrests' top to the rear window's foot (z 0.921 pre-centre), top just under it
    PARCEL=dict(y=(-0.972, -1.622), z=0.267, t=0.03, n=9, inset=0.02),
    DASH=dict(console=(0, 0.1176, -0.2594), dash=(0, 0.7976, 0.030), trim=(0, 0.6246, 0.050), light=(0, 0.6266, 0.0256),
              stand=(0, 0.6376, 0.1236), screen=(0, 0.6076, 0.2109), wheel=(0.3146, 0.1108)),   # wheel: the reclined driver's hands
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
