"""Model X Plaid: Abdul.Hannan's "Tesla Model X" (Sketchfab, CC BY 4.0, CREDITS.md). CAR=model_x.
Keys as in model_y.py (each is the module constant it sets); the keys only this car has are read with C.get and are off
for the others: DROP_MATS, PART_OBJS / SIDE_PARTS (whole source objects are the doors and lids), CAMERA,
FALCON (DOORS axis "falcon": the rear doors), SEAT third (six seats: pzveh.geometry, cabin.py SEATS middle / third),
SPLIT_COLOURS (the paint / trim borders in the skin: convert.py) and SEAM_SHADE (the door gaps in the skin; Model S / Y /
3 have it too).
The source is a half model with Mirror + Subsurf + Auto Smooth modifiers in a .blend: scripts/blender/skf/prep_model_x.py
applies them (Subsurf level 1) and writes TMP/src/source/model_x.obj, front +X, left +Y, ground z 0. Its shape is the
2016-2020 car; the last (2025+) Model X Plaid's is close: chrome trim black (Aluminum), the front bumper camera
(CAMERA), the nose's T (T_BADGE). Grid units, pre-centre frame (+Y front, +Z up, -X car left, ground z 0)
unless noted; numbers and sources: .claude/skills/tesla-dev/references/models-model-x.md.
"""
import math

# 20" wheel (pzveh.spoke_outline `polar`, as model_s.py's Magnetite): five black blades, each edged on both sides by a
# thin grey line (the official's "pairs" of thin spokes), read off the official SIDE front wheel (PPSW, polar unwrap
# round the fitted rim lip, the five folded, median: temp/skf_mx/work/polar.py): screen angle (deg, counter-clockwise
# from the rear) at r (rr units) of the grey lines' window side. A: the blade's first edge (a window's far edge) from the
# window's apex out to the lip; B: the next window's near edge
_BLADE_A = ((0.23, 33), (0.26, 36), (0.32, 51.5), (0.38, 53), (0.44, 54), (0.50, 54), (0.62, 53), (0.74, 51),
            (0.86, 47), (1.0, 44.5))
_BLADE_B = ((0.23, 105), (0.26, 97.5), (0.32, 90.5), (0.38, 83), (0.44, 80), (0.50, 78), (0.62, 75), (0.74, 74.5),
            (0.86, 74), (1.0, 74))


def _blade(w):
    """One blade, w (rr units) in from both window edges (the black face over the grey edge band; 0: the whole blade).
    Screen angle t is the wheel's (y, z) angle 126 - t (model_s.py _blade), the list reversed to stay counter-clockwise."""
    a = [(r, t + math.degrees(w / r)) for r, t in _BLADE_A]
    b = [(r, t - math.degrees(w / r)) for r, t in _BLADE_B]
    rim = [(1.0, a[-1][1] + (b[-1][1] - a[-1][1]) * i / 8) for i in range(1, 8)]   # along the barrel, not a chord
    pts = [(0.13, _BLADE_A[0][1])] + a + rim + b[::-1] + [(0.13, _BLADE_B[0][1])]
    return dict(polar=[(r, 126 - t) for r, t in reversed(pts)])


# the tail lamp decals' halves on the tailgate (prep_model_x.py FIELD decals Tail*_X: <name>_T)
TAIL_T = tuple(n + "_T" for n in ("TailLamp_X", "TailGuide_X", "TailRefl_X", "TailLampS_X", "TailReflS_X"))

CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_mx",
    NAME="MinidoracatTesla_ModelX",
    SCRIPT_MARK="---- geometry (TeslaModelX)",
    APP_CAR="app_car_modelx_{}.png",
    DIMS=(5.057, 1.999, 1.680),            # owner's manual (2021+, tesla.com 2026-11-01): length, width w/o mirrors, height
    PORT_NOTE="real Model X, owner's manual p.189",
    # (y, z pre-centre) where the left corner lamp's outboard end put it before 2026-11-12 (the lamps are prep decals
    # now: their red guide's end sat 11 cm back, 4 cm up; plug.z 0.84 against the real 0.837 stays)
    PORT=(-1.802, 0.807),
    # the last US design studio's six (Lexicon 2026-03-06) and China's pre-refresh two (2025-03); order = Core.lua Specs
    # colors (skin index is saved: only append after release)
    PAINTS=[("StealthGrey", "PN01"), ("LunarSilver", "PN02"), ("PearlWhite", "PPSW"), ("UltraRed", "PR01"),
            ("DiamondBlack", "PX02"), ("FrostBlue", "PB00"), ("SolidBlack", "PBSB"), ("DeepBlue", "PPSB")],
    # Pearl White's sun lobe at 0.62 (skin alpha 251, MinidoracatTesla_vehicle.frag SHEEN_SOFT_GAIN, the flag Model S
    # brought): the game showed 31.5 % of its lit paint >= 250 against the official FRONT34's 14.4 % at p50 218 / 214
    # (Main, 2026-11-12). The other paints stay 254
    PAINT_ALPHAS={"PearlWhite": 251},
    # convert.py fill_slivers (from fix/m3): the texels a triangle's UV touches that the bake left empty take its own
    # values (1,419 triangles sampled the skin's black, 656 of them on the front end; the game's 1 px dark points)
    UV_FILL=True,
    UV_FILL_TONE=True,                     # (convert.py textures) the filled texels out of the paint's blur and quantiles
    PAINT_ALPHA_DEFAULT=254,
    # tex = a * official-ramp colour / GAIN (model_y.py CAL), b 0: per-channel gains only, a = official FRONT34 p50 over
    # the game's at a = 1 (perf/paint_sheet.py on modelx-sp paint-<i>-<name>-fl-max, tesla-mx-1101b; Ultra Red and Deep
    # Blue refit on fl-max and rr-max against FRONT34 / REAR34, tesla-mx-1101f: Deep Blue came out cyan, G 72 / 67 against
    # 59 / 53, Ultra Red's shaded lower doors pink, G B 22 33 against 14 19). An offset (the
    # first fit) clipped the dark lower doors to another hue (Ultra Red R < 0 -> grey-green). RAMP_SPLIT (convert.py):
    # the gains act on the paint colour only, the ramp's grey (floor reflection, highlights) gets their mean.
    # Calibration knob: refit after changing the paint light
    CAL={
        # (round 8) Stealth Grey, Lunar Silver and Ultra Red per channel by the game's p50 against the official FRONT34's
        # (modelx-sp paint, 824bf64: [52 52 59] / [60 59 66], [131 134 142] / [141 142 150], [93 24 30] / [101 30 34];
        # temp/fit-1112/game/after-6e52fea/mx/RESULT.txt); the others as they were
        "StealthGrey": ((0.946, 0.885, 0.839), (0.0, 0.0, 0.0)),
        "LunarSilver": ((0.818, 0.795, 0.792), (0.0, 0.0, 0.0)),
        # Pearl White x 1.4 round the visible paint's median 230 (the offset): Model S's frag sun-lobe model
        # (temp/wt-fix-ms/temp/skf_ms/work/sheenfit.py, k 0.93 c 0.22 x 0.62 for flag 251) on this car's offline game S
        # view predicts game p50 214 and 14 % >= 250 (official FRONT34 214 / 14.4 %; at 0.92 / 0 it was 214 / 8 %), the
        # skin's p5 171 -> ~147 (the other cars 140-151). An estimate: measure in game (paint_sheet.py)
        "PearlWhite": ((1.288, 1.274, 1.274), (-0.361, -0.361, -0.361)),
        "UltraRed": ((0.8145, 1.675, 1.065), (0.0, 0.0, 0.0)),
        "DiamondBlack": ((1.16, 1.09, 0.98), (0.0, 0.0, 0.0)),
        "FrostBlue": ((1.06, 1.02, 0.98), (0.0, 0.0, 0.0)),
        "SolidBlack": ((1.02, 1.0, 0.94), (0.0, 0.0, 0.0)),
        "DeepBlue": ((2.43, 0.80, 0.80), (0.0, 0.0, 0.0)),
    },
    RAMP_SPLIT=True,
    # design studio: Plaid, 20" Perihelix, black interior, six seats. The two China paints are the pre-refresh car's
    # ($MTX19,$WX01,$IBC00): their renders were fetched by hand (temp/plan-sx-1031/assets/official), used for the colour
    COMPOSITOR_MODEL="mx",
    OFFICIAL_OPTS="$MDLX,$MTX23,${},$WX03,$IBC02,$CC02,$ST06",
    RAMP=dict(t=(0.36, 0.78), u=(0.08, 0.95), wheels=(0.172, 0.808), wt=0.76, wr=0.115),
    # ---- pzveh: wheel ($WX03, official SIDE / RIMCLOSEUP): five swept black blades edged in thin grey lines (_blade),
    # the brake disc dark through the windows; 265/45 R20 front, 275/45 R20 rear (TIRE_AXLES). Game-screen levels
    # (pzveh WHEEL_RGB) from the official SIDE front wheel's polar unwrap: blade face 6-17, window (disc) 17-37, hub 21-31,
    # the grey edges peak 85-107 and the lip 88-106 there, both 1-2 px anti-aliased (the game draws them unblended).
    # Round 3: the edges 130 -> 108 (same-camera SIDE r/R 0.65-0.95 p95 110-119 against the official's 96-107) and
    # their band _blade 0.04 -> 0.024 rr (1.6 -> 1.0 px at the game's closest zoom, 180.7 px / grid unit).
    # Round 6: the blades read as thin grey lines on black (the face 11 and the windows' disc 14 alike; official SIDE:
    # face 6-17, disc 17-37): the band back to 0.04, the disc and barrel lighter, the face darker. Polar unwrap folded
    # over the five blades (each round its own fitted rim lip), r/R 0.20-0.95: correlation with the official front /
    # rear 0.727 / 0.619 -> 0.705 / 0.624, p50 23 / 21 -> 31 / 28 (official 30 / 33); the edges' grey stays 108
    # Round 8: the blade face 9 -> 50 (game SW front wheel rim p50 / p75 21 / 26 against the official 38 / 63, the grey
    # edges at the official's p90: modelx-sp 824bf64, RESULT.txt). Round 9: 50 -> 43 (GameMX2, 6acfe7e: the face
    # read 60 against the official's 52 inside 35-90, p75 60 / 63 matched)
    WHEEL_RIM=0.727,                       # 20" (254 mm bead + 17 mm flange) / 373 mm tyre radius
    WHEEL_SPOKE=dict(n=5, shape=_blade(0.0), lit=_blade(0.04), cap=0.13, inset=0.016, dish=0.020, depth=0.018,
                     sweep=0),
    WHEEL_LIP=True,                        # the grey lip ring in the flat `lip` grey
    WHEEL_TURN=True,                       # one part all round: the right wheels show the left's pattern, not a mirror
    WHEEL_DISC=dict(rotor=0.70, hat=0.30),
    WHEEL_RGB=dict(spoke=43, edge=108, cap=18, barrel=16, lip=105, rotor=22, hat=20, dark=6, gap=6, tire=(22, 28),
                   tread=20),
    # ---- pzveh: vehicle script
    OY=0.2878,
    WHEEL_LIFT=0.11,
    # 265/45 R20 front (r 373.3), 275/45 R20 rear (r 377.8), owner's manual p.234: prep_model_x.py scales the source's
    # tyres to those on the manual's track, a wheel model per axle (models.md TIRE_AXLES)
    TIRE_AXLES=dict(front=(0.3733, 0.265), rear=(0.3778, 0.275)),
    WHEEL_INSET=0.0,                       # the prep puts the tyres on the manual's track (centres)
    CAB_BOX=(1.32, 0.45, -1.75),
    # passengers / seats (cabin.py): front and 2nd row from the door openings (back: front, 2nd row); third: the 3rd row
    # `back` behind the falcon doors' rear edge, at side x (3rd row shoulder room 1,033 mm against 1,442 in the 2nd,
    # owner's manual Dimensions)
    # heights (scripts/blender/skf/seat_head.py, 2026-11-01): heads and caps under the roof, the feet on CABIN_FLOOR in
    # the seated clips (scripts/seat_anim.py), the 2nd row `rear` and the 3rd row `third drop` under the front; SEATS
    # dz / dy put the cushions and backrests against the body
    SEAT=dict(x=0.35, h=0.464, z=-0.306, back=(0.12, -0.04), out=0.30, rear=0.017,
              third=dict(back=0.09, x=0.27, drop=0.017)),   # back (seat_head 3rd row knees on the round 2 body: 0.07
    #                                                         -23 / -24 mm, 0.075 -24 / -22, 0.08 -23 / -24, 0.085 -21 / -23, 0.09 -20 / -22, 0.10 -22 / -30 fail)
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
    # (convert.py pieces) the hinge 3 cm under the tailgate's top edge: the roof's crown put the front edge's sides 2-4
    # cm under a hinge at its top, so open they swung back and up off the roof: from the front, over the roof, the
    # ground showed through under the raised gate (game SE 751 px, b9fe78a 156; 0.01 / 0.02 / 0.03: 294 / 63 / 1)
    GATE_HINGE_DROP=0.03,
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
    # the front bumper's dark lower lip (official SIDE: the white ends at y 629 over x 391-462, h 0.28 m; the source's
    # white ran down to 0.23 m): the paint below z 0.233 ahead of the front arch cut and dark grey (as Trim_Grey)
    # round 9: lower towards the middle (official FRONT34: under the grille a white lip 12-15 px tall, then the dark
    # splitter from h ~0.25 m on the centre line; ours was dark from the grille down): z 0.2065 on the centre line
    # rising to 0.233 at |x| 0.58 and level out from there (one zone per side: a face goes below every plane)
    CARBON=dict(rgb=(40, 40, 43), zones=tuple(
        dict(lo=(lx, 1.62, -0.1), hi=(hx, 2.4, 0.30), below=(((0.0, 2.0, 0.233), (0.0, 0.0, 1.0)),
                                                          ((0.0, 2.0, 0.2065), (sx * 0.0457, 0.0, 1.0))), cut=True)
        for lx, hx, sx in ((-1.2, 0.0, 1.0), (0.0, 1.2, -1.0)))),
    ARCH_LINER=None,
    # the trunk's sill under the open tailgate (pre-centre z 0.55, the cargo floor's rear wall back to the bumper's
    # inside): the ground showed between them through the open trunk (game N / NE / SW / W 54 / 267 / 308 / 35 px)
    PLATES=(("SillPlate", ((-0.47, -2.025, 0.550), (0.45, -2.025, 0.550), (0.45, -2.052, 0.550), (0.30, -2.067, 0.550),
                           (0.15, -2.077, 0.550), (0.0, -2.087, 0.550), (-0.15, -2.077, 0.550), (-0.30, -2.067, 0.550),
                           (-0.47, -2.052, 0.550)), (0, 0, 1), "arch_liner"),
            # (as model_s.py) under the 1 px cracks at the headlamps' top inner corners (fascia, round 3: game NW 4 px)
            *((f"LampCrack{'L' if sx < 0 else 'R'}", tuple((sx * x, y, 0.692) for x, y in
                                                         ((0.72, 1.60), (0.60, 1.60), (0.60, 1.73), (0.72, 1.73))),
               (0, 0, 1), "arch_liner") for sx in (-1, 1)),
            # (round 5) under the frunk lid / fender gap over those corners (shut NW 1 px), the cowl corner by the
            # A-pillar's foot (the front door open: SE 9 px, b9fe78a 3) and the rear door opening's lower rear corner,
            # where the sill meets the rear arch (both falcon doors open: SW, the ground through a 6 mm gap)
            *((f"LidCrack{'L' if sx < 0 else 'R'}", tuple((sx * x, y, 0.715) for x, y in
                                                        ((0.70, 1.62), (0.57, 1.62), (0.57, 1.80), (0.70, 1.80))),
               (0, 0, 1), "arch_liner") for sx in (-1, 1)),
            *((f"CowlCrack{'L' if sx < 0 else 'R'}", tuple((sx * x, y, 0.83) for x, y in
                                                         ((0.77, 0.74), (0.66, 0.74), (0.66, 0.90), (0.77, 0.90))),
               (0, 0, 1), "arch_liner") for sx in (-1, 1)),
            *((f"ArchCorner{'L' if sx < 0 else 'R'}", tuple((sx * x, y, 0.19) for x, y in
                                                          ((0.64, -0.84), (0.44, -0.84), (0.44, -0.66), (0.64, -0.66))),
               (0, 0, 1), "arch_liner") for sx in (-1, 1)),
            # (round 6) under the 4 mm gap where the falcon door's rear top corner, the tailgate's front edge and the
            # roof meet (the front right door open: W 3 px, through the cabin and out of the door opening); a patch,
            # not a header across (RoofHeader, round 4: it closed the sky between the open falcon doors and the roof)
            *((f"GateCrack{'L' if sx < 0 else 'R'}", tuple((sx * x, y, 1.29) for x, y in
                                                         ((0.42, -1.22), (0.26, -1.22), (0.26, -1.13), (0.42, -1.13))),
               (0, 0, 1), "arch_liner") for sx in (-1, 1))),
    SEAL_CLIP=True,                        # (the strips through a panel showed outside: B-pillar roof seam, arch lips)
    # the strips 45 deg into the body (convert.py seals): in the panel's plane they stood up to 27 mm past the outline
    # at the roof, tail lamp and arch seams (temp/fit-1112/seals)
    SEAL_TILT=math.radians(45),
    # the body is one mesh in several materials (the source .blend), so the paint / black trim borders (rear glass
    # frame, tail lamp surrounds, window sills) ran inside UV islands as texel steps, blurred at 512: cut the islands
    # at every skin colour border (convert.py stage_build; user 2026-11-01, models.md)
    SPLIT_COLOURS=True,
    # the gaps as the official's continuous grey line (convert.py seam_lines, as model_s.py): half on each side of
    # every gap between two parts, half the paint's median (round 4: SEAL_RIBBON's 6.5 mm strip on one panel drew a
    # dashed line at 512 without antialiasing); no seal strip whose far edge has nothing over it within 3 cm, the
    # strips' reach cut back inside the game cameras' outline (SEAL_TRIM)
    # flat (round 5, as model_s.py): each half at its own corner's height (game NW: B-pillar 37 -> 76 %, front door's
    # front 77 -> 95 % by the Model S seam_bl measure; same-camera SIDE front door's front 90 -> 75 %, official 71 %)
    SEAM_LINE=dict(w=0.004, over=0.002, bridge=0.003, lift=0.0010, gap=0.025, glass=0.03, step=0.006, chain=0.04,
                   tone=0.5, flat=True),
    SEAL_TRIM=True,
    SEAL_COVER=0.03,
    SEAL_FULL=("TrunkDoor",),              # but the liftgate's: open, they close its gap to the pillars
    SEAL=(0.008, 0.008),
    RAIL=None,
    DECIMATE={},                           # done in the prep (material borders held)
    PAINT_MAT="Car_Paint",
    MAT_RGB={"Black_Car_Paint": (24, 24, 26), "Aluminum": (28, 28, 30), "Light_Glass": (30, 30, 32),
             "Light": (210, 210, 214), "Red_Light_Glass": (100, 24, 27), "Mirror": (58, 64, 72),
             "Window_Glass": (14, 14, 16), "badge_cam": (96, 98, 104),
             # prep_model_x.py FIELD decals (official renders sampled)
             # (round 8) the smoked lens 60 -> 92 (same-camera FRONT34 grey 48-56 against the official 74), the light
             # strip's dark rim (official: a thin dark line round the lamp)
             "Lamp_Lens": (92, 92, 98), "Lamp_DRL": (244, 247, 252), "Lamp_Rim": (26, 26, 28),
             # (round 8) the red guide's G B 128 / 124 -> 105 / 102: same-camera red pixels' mean REAR34 (202, 100, 98) /
             # SIDE (173, 82, 80) against the official (202, 85, 85) / (172, 62, 67): it read pink
             "Tail_Guide": (255, 105, 102),
             # (round 6) the tail lamp housing 23 -> 33 and its reflector bar 100 -> 88: same-camera grey 21 / 54 against
             # the official REAR34 42 / 47, SIDE 40 / 31 (now 29-30 / 49-56)
             "Lamp_Housing": (33, 32, 35), "Lamp_Reflector": (88, 22, 25),
             "Cam_Black": (36, 36, 39), "Slot_Black": (18, 18, 19), "Marker_Red": (36, 18, 17),
             "Band_Black": (14, 14, 16), "Intake_Black": (18, 18, 20),
             # (round 6) the tailgate band between the lamps dark grey (official REAR34 42; Band_Black drew 9, round 6's
             # 46 drew 24, round 7's 72 draws 39; round 8: 72 read 36.7 in the game against the official's 41-53, 84 by
             # the line ~43) and the rear bumper reflector slits (official 34-37 red over the dark,
             # mostly in the bumper lip shadow)
             "Gate_Band": (84, 84, 88), "Bump_Refl": (62, 17, 19),
             # the lower trim (prep_model_x.py FIELD trim_grey; official SIDE sills 30-37, arch lips 45-67)
             "Trim_Grey": (40, 40, 43),
             # (round 9) the arch lips' own grey (prep FIELD arch_lip lip: they were black, the well's wall too;
             # official SIDE lips 45-95, median ~65)
             "Lip_Grey": (64, 64, 68)},
    GLASS_MATS=("Window_Glass",),
    GLASS_OPAQUE=(),
    GLASS_BACKS=("WinLH", "WinLT", "WinRH", "WinRT"),   # the source's panes are one-sided
    ROOF_PANE="-",
    MIRROR_CAP="-",
    LAMPS=dict(head=("Lamp_Lens", "Lamp_DRL"), tail=("Tail_Guide",), tail_z=0.6, tail_y=-1.5, blade=None),
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
    # (the prep's spoiler, the tailgate band and the tail lamp decals' halves on the gate ride the tailgate; round 7:
    # GateBand_X (round 6) had stayed on the body, a dark strip hanging where the closed gate was once it opened)
    PART_OBJS={"EngineDoor": ("Bonnet",), "TrunkDoor": ("Trunk", "Spoiler_X", "GateBand_X", *TAIL_T)},
    SIDE_PARTS={"Front_Door": ("DoorFrontLeft", "DoorFrontRight"), "Back_Door": ("DoorRearLeft", "DoorRearRight"),
                "Mirror_X": ("DoorFrontLeft", "DoorFrontRight")},
    # the mirrors (the prep cuts them out of the front doors): outer faces only, no slab inner copy (it stood 6 cm in
    # off the housing's back, a cabin-grey shell round the glass: official black)
    SHELL_OBJS=("Mirror_X", "Spoiler_X", "GateBand_X", *TAIL_T),
    CUT={},
    PLANES={},
    CUT_X=("-",),
    CUT_X_Y=None,
    DOOR_OBJS=(),
    GATE_OBJS=(),
    GATE_COMPS=(),
    GATE_CUT_COMPS=(),
    # the band round the nose's T, the bumper's slots and grille: prep_model_x.py FIELD decals
    # the front bumper camera (2025+ Model X, official FRONT34): prep_model_x.py FIELD decals CamRing_X (CAMERA's flat
    # ring stood 16 mm off the bumper)
    CAMERA=None,
    PANES={"Body": {"WinT"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"},
           "DoorRearLeft": {"WinLT"}, "DoorRearRight": {"WinRT"}, "TrunkDoor": {"WinH"}, "EngineDoor": set()},
    # (round 8) the nose's T flat on the band (the source's 3D chrome T sat in the pre-2021 nose cone's pocket: faired
    # out, prep FIELD fair): centre on the faired nose at h 0.735 m (official FRONT34 T 0.708-0.763 m on the centre
    # line), the surface's normal there; 5.8 x 6.1 cm (official ~5.5 cm, a little over: the game's closest zoom)
    T_BADGE=(2.0628, 0.048, 0.050, 0.6081, (0, 0.857, 0.514), None),
    # (round 9, convert.py textures) the T's chrome the same on every paint: it lies on the black band, but the shared
    # rule (dark chrome 104 on light paints) drew it 96 on Pearl White against 194 on black and red in the game (GameMX2,
    # 6acfe7e); official FRONT34 T glyph p50 / p90 99-120 / 133-135 on white, red, grey (black 120 / 234)
    CHROME_RGB=(140, 144, 150),
    TESLA=None,
    LENS_X=0.0,
    BADGE_Y=(-2.6, -2.2),
    BLADE=False,
    MODELY=None,
    PERF_BADGE=None,
    CALIPER=dict(front=(176, 18), rear=(80, 15), r=(0.085, 0.145), x=(0.010, 0.045)),   # r: above the body floor (z 0.161)
    # the frunk lid's inner panel tilted back at its front lip (convert.py pieces(): straight down, the lip's twin stood
    # 14 mm out of the nose under it, a dark band across the nose in FRONT34)
    LID_TILT=(1.85, 2.0, 1.0),
    # frunk 183 L (owner's manual Dimensions) under the lid (Bonnet)
    FRUNK_TUB=dict(ledge=0.06, rim=0.025, y=(1.30, 1.78), half=(0.34, 0.19), corner=0.07, taper=0.10, depth=(0.37, 0.25),
                   n=128),
    # ---- cabin.py (mesh coords, centred)
    CABIN_FLOOR=-0.526,                    # under the seated feet (seat_head.py feet)
    CABIN_FRONT_Y=1.00,
    TRUNK_Y=-1.55,
    TRUNK_WALL=True,                       # trunk side walls from one profile (cabin.py trunk_walls; user 2026-11-01)
    # (cabin.py trunk_walls, as Model Y L) over the outer wall's last hit, the slots on the chords between its hits: the
    # last ring's wall held that hit's x up to its top and stood 7.2 mm out of the rear bumper's corner (seals)
    TRUNK_WALL_INSIDE=True,
    HUMP_BACKS=False,                      # no two-sided arch humps (cabin.py; staircase in the rear doors, 2026-11-01)
    REAR_DOOR_WALL=True,                   # TRUNK_WALL's profile through the rear door openings too (user 2026-11-01)
    CABIN_ZC=-0.05,
    SEAM_CLEAR=0.065,
    SEATS=dict(front=dict(w=0.42, back=0.52, recline=32, dy=0.056, dz=-0.084),
               rear=dict(base=1.10, cushions=((-0.37, 0.36), (0, 0.33), (0.37, 0.36)), back=0.46, recline=18),
               middle=dict(w=0.42, back=0.50, recline=10, dy=0.035, dz=-0.068),
               third=dict(w=0.36, back=0.34, head=0.42, recline=10, dy=0.028, dz=-0.068),
               sill=(0.90, 0.08), bin=(0.86, 0.20)),
    PARCEL=None,
    DASH=dict(console=(0, 0.12, -0.28), dash=(0, 0.80, 0.02), trim=(0, 0.627, 0.03), light=(0, 0.629, 0.007),
              stand=(0, 0.64, 0.13), screen=(0, 0.61, 0.21), wheel=(0.357, 0.027)),   # wheel: the reclined driver's hands
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
