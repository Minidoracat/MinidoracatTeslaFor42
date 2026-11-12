"""Model S Plaid ($MTS23, the 2021 refresh as sold until 2026-05): ValentunW's (Lals) "Tesla Model S Plaid" (Sketchfab,
CC BY 4.0, CREDITS.md). CAR=model_s. Keys as in model_y.py (each is the module constant it sets); the keys only this car
has are read with C.get and are off for the others: SRC_Z (the glTF is centred on the car, not on the ground), TIRE
centres (the tyres are components of the black trim object), LAMPS head_y (one lamp material front and rear),
TESLA_MAT (chrome letters on the black band), GATE_BY_COMP (the tail lamps' liftgate and body halves overlap in x),
DROP_COVERED (paint lying under the tail lamp housings: a depth fight in game), CARBON zones' `of` / `facing` (the
jamb's top under the liftgate's hinge corners), SEAM_LINE (the panel gaps as a continuous dark line; convert.py
seam_lines), SEAL_COVER (convert.py seals), LAMPS `areas` / `head_rgb`, CARBON `cut`, TIRE `centre_track`,
WHEEL_SPOKE `polar`.
The source (a Roblox export, decisions.md) is the Sketchfab glTF: 22 objects "Object_<n>", one per material; doors,
frunk lid and liftgate are components of the paint object (Object_2), and the interior shares objects with the
exterior (paint seats, black trim cabin tub), so parts come from components (DROP_COMPS boxes, CUT keys).
Grid units, pre-centre frame (+Y front, +Z up, -X car left, ground z 0) unless noted; numbers and sources:
.claude/skills/tesla-dev/references/models-model-s.md.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from prep_model_s import moved, moved_plane  # noqa: E402  (the build reads prep_model_s.py's output; see the end)

_PAINT = "Color1Mtl"
_LAMP = "MeshesteslaMdoelStrunk2mesh2400622Mtl"     # head and tail lamp housings (smoked)
_BLACK = "Wiper11Mtl"                               # black trim, tyres, brakes, cabin tub
_GLASS = "MeshesteslaMdoelSwindowlf2mesh021Mtl"
_SIDES = (-1, 1)


def _lr(zn):
    """A left-side zone (lo, hi, below planes) and its mirror on the right."""
    def mx(v):
        return (-v[0], *v[1:])
    return zn, dict(zn, lo=(-zn["hi"][0], *zn["lo"][1:]), hi=(-zn["lo"][0], *zn["hi"][1:]),
                    below=tuple((mx(p), mx(n)) for p, n in zn.get("below", ())))


# the lamps as the official renders draw them (LAMPS areas, left side; the planes' points and the official outlines
# through the fitted cameras onto the model, temp/skf_ms/work/lampzones.py). Head: the lens dark, the DRL strip along
# its top edge white, the outboard end behind the lens (SIDE; FRONT34's DRL down stroke) light. Tail: the clear upper
# lens over the outboard half grey, a red bar under it, the inboard C (lit in the renders) pink round a dark inner
_DRL_IN = dict(lo=(-0.693, 1.701, 0.512), hi=(-0.362, 2.005, 0.716),
               below=(((-0.4573, 1.9133, 0.5473), (-0.4043, 0.1247, -0.9061)),),
               cut=True)
_DRL_OUT = dict(lo=(-0.804, 1.5, 0.573), hi=(-0.623, 1.785, 0.716),
                below=(((-0.6489, 1.7423, 0.6093), (-0.3, 0.0676, -0.9515)),),
                cut=True)


def _band(zn, d):
    """zn's first plane's side cut down to a band d (grid) wide: the official DRL is a 1 cm strip under the housing's
    black brow, not the lens's whole top"""
    (p, n), = zn["below"]
    return dict(zn, below=((p, n), (tuple(a - b * d for a, b in zip(p, n)), tuple(-b for b in n))))


_DRL_IN, _DRL_OUT = _band(_DRL_IN, 0.010), _band(_DRL_OUT, 0.010)
# the J's lower stroke (official FRONT34 x 656-718 along the lens's lower edge, through the fitted camera onto the
# model): a band over the stroke's lower edge
_DRL_LOW = _band(dict(lo=(-0.716, 1.723, 0.50), hi=(-0.591, 1.845, 0.591),
                      below=(((-0.5906, 1.8449, 0.5295), (-0.0659, -0.0245, -0.9975)),), cut=True), 0.010)
_REAR = dict(lo=(-0.804, 1.5, 0.472), hi=(-0.663, 1.737, 0.716),
             below=(((-0.7037, 1.6498, 0.6317), (0.3021, 0.6531, 0.6944)),),
             cut=True)
_T_UPPER = dict(lo=(-0.955, -2.045, 0.614), hi=(-0.402, -1.55, 0.818),
                below=(((-0.6699, -1.8, 0.7363), (0.7139, -0.7002, 0.)),
                       ((-0.7035, -1.6994, 0.7281), (-0., -0., -1.))),
                cut=True)
_T_BAR = dict(lo=(-0.955, -2.045, 0.614), hi=(-0.402, -1.55, 0.818),
              below=(((-0.6699, -1.8, 0.7363), (0.7139, -0.7002, 0.)),
                     ((-0.7035, -1.6994, 0.7159), (0., 0., 1.)),
                     ((-0.7035, -1.6994, 0.7023), (-0., -0., -1.)),
                     ((-0.7243, -1.6555, 0.7057), (-0.7139, 0.7002, -0.))),
              cut=True)
_T_C = dict(lo=(-0.955, -2.045, 0.614), hi=(-0.402, -1.55, 0.818),
            below=(((-0.6699, -1.8, 0.7363), (-0.7139, 0.7002, -0.)),
                   ((-0.603, -1.8448, 0.7702), (0., 0., 1.)),
                   ((-0.603, -1.8448, 0.7031), (-0., -0., -1.))),
            cut=True)
_T_INNER = dict(lo=(-0.955, -2.045, 0.614), hi=(-0.402, -1.55, 0.818),
                below=(((-0.6455, -1.8209, 0.7363), (-0.7139, 0.7002, -0.)),
                       ((-0.603, -1.8448, 0.7515), (0., 0., 1.)),
                       ((-0.603, -1.8448, 0.7225), (-0., -0., -1.))),
                cut=True)
_SLOTS = dict(lo=(-0.82, 1.50, 0.0), hi=(-0.40, 2.15, 0.45))   # the bumper's lamp-material slots (side intakes)


# the rear zones' planes on the body (_poly_zones `at`; the source's surface read off the built body, prep field undone):
# the back face's y by |x|, the bumper sides' |x| by |y|
_AT_BACK = ((0.0, 0.1437, 0.3699, 0.5055, 0.5789, 0.6261, 0.678), (-2.0709, -2.0709, -2.0298, -1.9834, -1.9386, -1.8821, -1.84))
_AT_SIDE = ((1.5058, 1.5884, 1.6710, 1.7536, 1.8362, 1.9188, 2.0014), (0.7961, 0.7662, 0.7339, 0.6982, 0.6508, 0.5844, 0.3578))


def _poly_zones(poly, ax, rng, at=None):
    """CARBON zones (convert.py `cut`): the paint inside a convex polygon, its corners in coordinates ax (two of 0 x,
    1 y, 2 z) on the left (pre-centre grid, the source's), between rng on the third axis; and its mirror on the right.
    The box is the polygon's with 0.06 to spare (the planes draw the border). at: ((|first axis|...), (third...)):
    each edge's plane through its midpoint at the body's surface (interpolated over the midpoint's |first axis|), so
    the field moves and turns it where it cuts (else the range's middle)."""
    third, out = 3 - ax[0] - ax[1], []

    def p3(a, b, t):
        v = [0.0, 0.0, 0.0]
        v[ax[0]], v[ax[1]], v[third] = a, b, t
        return tuple(v)
    for s in _SIDES:
        pts = [(s * a, b) for a, b in poly] if ax[0] == 0 else list(poly)
        r = rng if third != 0 or s < 0 else (-rng[1], -rng[0])
        if sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1])) < 0:
            pts = pts[::-1]                # counter-clockwise: the outward normal is (db, -da)
        u, w = [q[0] for q in pts], [q[1] for q in pts]
        mids = [((a[0] + b[0]) / 2, (a[1] + b[1]) / 2) for a, b in zip(pts, pts[1:] + pts[:1])]
        ts = [((s * float(np.interp(abs(m[0]), *at)) if third == 0 else float(np.interp(abs(m[0]), *at)))
               if at else (r[0] + r[1]) / 2) for m in mids]
        out.append(dict(lo=p3(min(u) - 0.06, min(w) - 0.06, r[0]), hi=p3(max(u) + 0.06, max(w) + 0.06, r[1]), cut=True,
                        below=tuple((p3(*(m if at else a), t), p3(b[1] - a[1], a[0] - b[0], 0.0))
                                    for a, b, m, t in zip(pts, pts[1:] + pts[:1], mids, ts))))
    return tuple(out)

# 19" Magnetite blade (pzveh.spoke_outline `polar`): the silver machined edges of the windows between the blades, read
# off the official SIDE front wheel (PPSW, polar unwrap round the fitted rim lip, the five folded, median:
# work/polar.py),
# screen angle (deg, counter-clockwise from the rear) at r (rr units). A: one window's trailing edge from its apex (r
# 0.21) out to the lip; B: the next window's leading edge (one blade between). The windows reach in to r 0.21, the hub
# inside it is solid
_MAG_A = ((0.21, -3), (0.26, 10.5), (0.34, 20.5), (0.42, 27.5), (0.50, 31.5), (0.62, 35), (0.74, 36.5), (0.86, 38),
          (1.0, 39.5))
_MAG_B = ((0.21, 69), (0.26, 58.5), (0.34, 55), (0.42, 55), (0.50, 57.5), (0.62, 63.5), (0.74, 68), (0.86, 71.5),
          (1.0, 74.5))


def _blade(w):
    """One blade, w (rr units) in from both window edges (the black face over the silver edge band; 0: the whole
    blade). The SIDE sees the wheel's -x face, front to the left: screen angle t is the wheel's (y, z) angle 126 - t
    (mirrored; the 126 put the folded pattern on the official's, work/polar.py), so the list is reversed to stay
    counter-clockwise (pzveh)."""
    a = [(r, t + math.degrees(w / r)) for r, t in _MAG_A]
    b = [(r, t - math.degrees(w / r)) for r, t in _MAG_B]
    rim = [(1.0, a[-1][1] + (b[-1][1] - a[-1][1]) * i / 8) for i in range(1, 8)]   # along the barrel, not a chord
    pts = [(0.13, _MAG_A[0][1])] + a + rim + b[::-1] + [(0.13, _MAG_B[0][1])]
    return dict(polar=[(r, 126 - t) for r, t in reversed(pts)])


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
    # Pearl White's sun lobe at 0.62 (skin alpha 251, MinidoracatTesla_vehicle.frag SHEEN_SOFT_GAIN): the game showed 31
    # %
    # of its lit paint >= 250 against the official 5.6 % at the same p50 (Main, 2026-11-12). The skin can't fix it: its
    # seen paint is already tight (p50 234, p95 238); squeezing the upper half onto the median moved a model of the
    # frag's lobe (work/sheenfit.py: the S view's normals and skin, fitted gain 0.22 = SHEEN_SKY) only 32 -> 28 %;
    # the lobe at 0.62 x -> ~6 %. The other paints stay 254 (p95 <= 170: no clipping). In game 0.62 was still too
    # bright and 0.45 fits (GameMS), but Model X's Pearl White, which shared the flag 251, needs 0.62 (11.8 % against
    # the official 14 %; 0 % at 0.41, GameMX): Model S takes its own flag 250 (frag SHEEN_SOFT2_GAIN)
    PAINT_ALPHAS={"PearlWhite": 250},
    PAINT_ALPHA_DEFAULT=254,
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
    # ---- pzveh: wheel, 19" Magnetite (official RIMCLOSEUP): five wide black blades swept round the hub, the windows
    # between them edged in machined silver, a thin silver lip ring; the red caliper behind. 255/45 R19 front, 285/40
    # R19 rear (~356 mm radius)
    WHEEL_RIM=0.725,                       # rim flange radius / tire radius: the fitted lip ring 0.2586 m / 356 mm
    # the blade (_blade: whole) in the `edge` silver, its face (_blade(0.025): 6.5 mm in from each window edge) in the
    # `spoke` black over it; the windows' silver edges are what is left
    WHEEL_SPOKE=dict(n=5, shape=_blade(0.0), lit=_blade(0.025), cap=0.13, inset=0.018, dish=0.020, depth=0.018,
                     sweep=0),
    WHEEL_LIP=True,                        # the silver lip ring in the flat `lip` grey (official SIDE ~88-106, 2 px)
    WHEEL_TURN=True,                       # one part all round: the right wheels show the left's pattern, not a mirror
    WHEEL_DISC=dict(rotor=0.70, hat=0.30),     # 395 mm front rotor (owner's manual) / 258 mm flange
    # game-screen levels (pzveh WHEEL_RGB) = the official SIDE's (PPSW front, work/polar.py): blade face 12, windows
    # 6-12, hub 9; the silver edges peak 100-127 and the lip 88-111 there, both 1-2 px anti-aliased (the game draws them
    # unblended: brighter). Offline (Workbench) the dark ones read ~+13 (v12: blade 25, window 29, hub 22)
    WHEEL_RGB=dict(spoke=11, edge=130, cap=9, barrel=10, lip=115, rotor=12, hat=10, dark=6, gap=6, tire=(22, 28),
                   tread=20),
    # 255/45 R19 front, 285/40 R19 rear (owner's manual p.210): radius ~356 mm, one width per car (their mean), track
    # 1,690 mm; the axles where the source has them (its tyres sit in the black trim object, dropped below)
    TIRE=dict(r=0.3557, w=0.270, track=1.690, centres=((1.2833, 0.2938), (-1.16157, 0.2938)), centre_track=True),
    TIRE_AXLES=dict(front=(0.3560, 0.2497), rear=(0.3553, 0.2797)),
    # ---- pzveh: vehicle script
    OY=0.1978,                             # Model 3's (a sedan's CoM)
    WHEEL_LIFT=0.11,
    WHEEL_INSET=0.03,
    CAB_BOX=(1.30, 0.45, -1.40),
    # the seats sit further back in the door openings than Model 3's (the source's seats and yoke)
    # heights (scripts/blender/skf/seat_head.py, 2026-11-01; the user's driver showed her hair above the windscreen
    # header): heads and caps under the roof, the feet on CABIN_FLOOR in the seated clips (scripts/seat_anim.py), rear
    # row `rear` lower; SEATS dz / dy put the cushions and backrests against the body
    SEAT=dict(x=0.34, h=0.386, z=-0.207, back=(0.25, 0.20), out=0.30, rear=0.017),
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
    SRC=("src", "source", "model_s.glb"),            # prep_model_s.py's output
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
    # paint lying under the tail lamp housings' inner ends at the liftgate opening's sides (0.3 mm apart in the
    # source: in game a ragged white ring at the opening's rear corners): (object, objects over it, gap)
    DROP_COVERED=(("Object_2", ("Object_10",), 0.002),),
    ARCH_LINER=None,                       # the source has its own wheel wells (Object_23)
    # black plate behind the lower grille's slats (else the ground showed between them); from 0.13 up: lower it stood
    # out under the raised lip (the field's spat) as a black wedge, at 0.15 the ground showed through the lip's slots
    PLATES=(("GrillePlate", ((-0.55, 1.90, 0.13), (0.55, 1.90, 0.13), (0.55, 1.90, 0.34), (-0.55, 1.90, 0.34)),
             (0, 1, 0), "arch_liner"),
            ("GrilleFloor", ((-0.55, 1.70, 0.13), (0.55, 1.70, 0.13), (0.55, 1.90, 0.13), (-0.55, 1.90, 0.13)),
             (0, 0, 1), "arch_liner"),
            # r4: under the source's two cracks the game's SW / W cameras saw the ground through (1 px each; the r3
            # SEAL_RIBBON lay over them by chance): the headlamp's top corner, the sill's crease ahead of the door
            *((f"LampCrack{'L' if sx < 0 else 'R'}", tuple((sx * x, y, 0.6426) for x, y in
                                                         ((0.7256, 1.55), (0.7035, 1.55), (0.7035, 1.6), (0.7256, 1.6))),
               (0, 0, 1), "arch_liner") for sx in (-1, 1)),
            *((f"SillCrack{'L' if sx < 0 else 'R'}", tuple((sx * x, y, 0.1641) for x, y in
                                                         ((0.7387, 0.62), (0.7035, 0.62), (0.7035, 0.8), (0.7387, 0.8))),
               (0, 0, 1), "arch_liner") for sx in (-1, 1)),
            # r6: four doors open, NW: the ground between the open rear door's front edge and the sill's outer face
            # at the front door opening (sightlines 2-3 mm outside the sill, 9 px); a 7 mm shelf off the sill under them
            *((f"SillSlit{'L' if sx < 0 else 'R'}", tuple((sx * x, y, 0.1708) for x, y in
                                                        ((0.7665, 0.345), (0.7540, 0.345), (0.7540, 0.435), (0.7665, 0.435))),
               (0, 0, 1), "arch_liner") for sx in (-1, 1))),
    SEAL_CLIP=True,
    # the gaps as the official's continuous dark line (convert.py seam_lines): half on each side of every gap between
    # two parts, 4.8 mm each, overlapping 2.4 mm past the middle (r4: one 4 mm hairline on the later part broke into
    # dots in game, the door bottoms' in their own plane out of sight), half the paint's median (official SIDE seam
    # contrast 0.45-0.64 of the paint; a console-cell line was 0.80, a black line on Pearl White); and no seal strip whose far
    # edge has nothing over it within 3 cm (one stood 21 mm out of the outline behind the front fender,
    # temp/fit-1112/seals); `flat` (r5): each half's gap end at its own corner's height: the right front door stands
    # 1.5 mm proud of the rear one at the B-pillar (the left ones are flush), its half sloped down under its own edge
    # and the rear door's faced backwards (game E / SE 66 % / 68 % continuous; flat: 100 % / 95 %); 3 mm wide broke
    # the B-pillar in game (N 85 %, E 88 %), 2 mm more (E 68 %, NW 62 %)
    SEAM_LINE=dict(w=0.004, over=0.002, bridge=0.003, lift=0.0010, gap=0.025, glass=0.03, step=0.006, chain=0.04,
                   tone=0.5, flat=True),
    SEAL_COVER=0.03,
    SEAL_COVER_EDGE=True,                  # (convert.py seals) its far corners too, none down past a bottom edge
    UV_FILL=True,                          # (convert.py fill_slivers) texels the bake left black under sliver UVs
    UV_FILL_TONE=True,                     # (convert.py textures) the filled texels stay out of the paint's quantiles
    SEAL_TRIM=True,                        # (convert.py seals) reach cut back to inside the game cameras' outline
    # (convert.py seals) but round the liftgate, both sides of its gap: open, they close its gap to the C-pillar (the
    # body's side went with SEAL_COVER and the short reach: the ground showed there)
    SEAL_FULL=("TrunkDoor",),
    SEAL=(0.008, 0.008),                   # (convert.py SEAL) reach 1 cm: its gaps are 1-5 mm; at 2 cm the strips showed
    #                                        below the door sills and at the A-pillar's foot as black blocks
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
    MIRROR_CAP=("Object_2", (222,)),        # (decimated sizes)
    # lamp colours: official medians (PPSW / PN01 / PR01 alike): head lens FRONT34 33 32 35; tail black band and lower
    # part SIDE 15-19; clear upper lens SIDE 191 / REAR34 70 (between: the game looks down on it); red bar 190 25 28;
    # C 254 121 120 (lit), its inner 21 20 22
    LAMPS=dict(head=(_LAMP, "I1Mtl"), head_y=0.0, tail=(_LAMP, "Meshpart7Mtl", "Stop1Mtl"), tail_z=0.6, tail_y=-1.4,
               tail_rgb=(17, 15, 17), head_rgb=(33, 32, 35), blade=None,
               areas=tuple((zn, rgb, lit) for z, rgb, lit in (
                   (_SLOTS, (20, 20, 22), False), (_DRL_IN, (240, 242, 246), True), (_DRL_OUT, (240, 242, 246), True),
                   (_REAR, (205, 207, 212), True), (_DRL_LOW, (240, 242, 246), True), (_T_UPPER, (130, 130, 134), True), (_T_BAR, (190, 25, 28), True),
                   (_T_C, (254, 121, 120), True), (_T_INNER, (21, 20, 22), True)) for zn in _lr(z))),
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
    # black: the Plaid's carbon spoiler is a black part (Object_23) already; the black lower front lip too. Black
    # here: the body skin's top under the liftgate's hinge corners (the jamb's flange, up-facing, under the shut
    # gate's corners; open, its ragged decimated end showed as white chips between the black hinge parts, TrunkShell
    # 2026-11-01; dropped, it bared the clutter under it). Its component is 4659 triangles as decimated
    CARBON=dict(rgb=(20, 20, 22), zones=tuple(
        dict(lo=(0.47 if s > 0 else -0.545, -1.13, 1.02), hi=(0.545 if s > 0 else -0.47, -1.06, 1.075),
             of=("Object_2", 4666), facing=((0, 0, 1), (0.75, 1.0))) for s in _SIDES)
        # the Plaid's front (official FRONT34 PPSW, its outline through the fitted camera onto the model): the lower
        # intake running down into the black splitter, the white fang between it and the tall side intake, a white
        # strip under the side intake, the splitter under that; the band over the fang joins the two intakes. Round 3:
        # the fang's inner edge, the side intake's outer edge and the splitter's top re-read off FRONT34 (<= 3 px a column)
        + _poly_zones(((0.0, 0.3022), (-0.36, 0.2993), (-0.5572, 0.1587), (-0.6281, 0.0891), (0.0, 0.0891)), (0, 2),
                      (1.60, 2.40))
        + _poly_zones(((-0.5116, 0.3097), (-0.6191, 0.2061), (-0.7690, 0.1966), (-0.7434, 0.3643)), (0, 2), (1.55, 2.40))
        + _poly_zones(((-0.5528, 0.159), (-0.727, 0.1494), (-0.804, 0.1342), (-0.804, 0.0891), (-0.5528, 0.0891)), (0, 2),
                      (1.55, 2.40))
        + _poly_zones(((-0.375, 0.2850), (-0.565, 0.2852), (-0.565, 0.3171), (-0.375, 0.2908)), (0, 2), (1.60, 2.40))
        # the Plaid's rear (official REAR34 and SIDE, the same way): the diffuser's black up to the bumper's lower
        # crease across the rear face (seen from behind), round the corners and along the sides to the rear arch
        + _poly_zones(((0.0, 0.3936), (-0.2874, 0.3886), (-0.4523, 0.3825), (-0.5588, 0.3608), (-0.599, 0.3343),
                       (-0.6533, 0.2597), (-0.7035, 0.024), (0.0, 0.024)), (0, 2), (-2.70, -1.82), _AT_BACK)
        + _poly_zones(((-1.9648, 0.3557), (-1.7854, 0.2293), (-1.7854, 0.024), (-1.9648, 0.024)), (1, 2), (-0.95, -0.55),
                      _AT_SIDE)
        + _poly_zones(((-1.7854, 0.2293), (-1.4874, 0.1731), (-1.4874, 0.01), (-1.7854, 0.01)), (1, 2), (-0.95, -0.55),
                      _AT_SIDE)),
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
    # (deg behind the top) the rear where the official SIDE shows it through the windows (~28 deg above the axle's
    # level, rear side). The official front one sits there too (64 deg), but a caliper in the body must clear the
    # spokes at full lock: -0.084 grid there, >= 0.003 only within 9 deg of the top or the bottom (convert.py calipers);
    # the bottom, as model_y.py (seen from the game camera; at the top the fender hides it)
    CALIPER=dict(front=(176, 12), rear=(62, 15), r=(0.100, 0.168), x=(0.008, 0.040)),
    # frunk 89 L (owner's manual p.207) under the lid
    FRUNK_TUB=dict(ledge=0.06, rim=0.025, y=(1.21, 1.72), half=(0.34, 0.22), corner=0.07, taper=0.07, depth=0.22,
                   n=128),
    # ---- cabin.py (mesh coords, centred)
    CABIN_FLOOR=-0.477,                    # under the seated feet (seat_head.py feet)
    CABIN_FRONT_Y=1.05,
    TRUNK_Y=-1.05,
    TRUNK_WALL=True,                       # trunk side walls from one profile (cabin.py trunk_walls; user 2026-11-01)
    HUMP_BACKS=False,                      # no two-sided arch humps (cabin.py; staircase in the rear doors, 2026-11-01)
    REAR_DOOR_WALL=True,                   # TRUNK_WALL's profile through the rear door openings too (user 2026-11-01)
    GATE_LINING=False,                     # no liftgate inner panel over the trunk walls' top (cabin.py; spikes, 2026-11-01)
    CABIN_ZC=-0.04,
    SEAM_CLEAR=0.065,
    # rear base 1.08: at 1.12 its lower corners stood 8 mm out under the sills ahead of the rear wheels (the cabin
    # lowered _CAB, the body there less)
    SEATS=dict(front=dict(w=0.43, back=0.52, recline=32, dy=0.060, dz=-0.142),
               rear=dict(base=1.08, cushions=((-0.38, 0.37), (0, 0.34), (0.38, 0.37)), back=0.46, recline=10, dy=0.03,
                         dz=-0.135),
               sill=(0.90, 0.12), bin=(0.90, 0.40)),   # sill depth 0.12: at 0.08 the open liftgate's gap showed by it
    PARCEL=None,                           # a liftgate: no parcel shelf
    DASH=dict(console=(0, -0.02, -0.25), dash=(0, 0.66, 0.06), trim=(0, 0.487, 0.07), light=(0, 0.489, 0.045),
              stand=(0, 0.50, 0.17), screen=(0, 0.47, 0.25), wheel=(0.197, 0.139)),   # wheel: the reclined driver's hands
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


def _moved_positions(c):
    """The positions in CAR are the source glTF's (pre-centre grid, read off it with outline.py / inspect); the build
    reads prep_model_s.py's output, so they move with its field: points and (y, z) lines at the body side, levels at
    the side (y 0) unless they belong to the tail / nose, |x| limits, boxes corner by corner."""
    def z(v, y=0.0, x=0.80):
        return moved(x, y, v)[2]

    def y(v, zz=0.5, x=0.80):
        return moved(x, v, zz)[1]

    def x(v, yy=0.0, zz=0.6):
        return moved(v, yy, zz)[0]

    def box(lo, hi):                    # corner by corner (the field keeps the order)
        return moved(*lo), moved(*hi)

    def _plane(p, n):                   # behind the rear axle the planes turn with the tail's corner term
        return moved_plane(p, n) if p[1] < -1.2 else (moved(*p), n)

    c["BELT_Z"], c["SILL_Z"], c["GATE_Z"] = z(c["BELT_Z"]), z(c["SILL_Z"]), z(c["GATE_Z"], -1.9, 0.0)
    c["LINES"] = {k: tuple(moved(0.80, *p)[1:] for p in v) for k, v in c["LINES"].items()}
    c["FRONT_Y"], c["DOOR_Y"] = y(c["FRONT_Y"]), tuple(y(v) for v in c["DOOR_Y"])
    c["IN_DOOR"] = dict(c["IN_DOOR"], up=z(c["IN_DOOR"]["up"]), x=x(c["IN_DOOR"]["x"]))
    g = c["IN_GATE"]
    c["IN_GATE"] = dict(g, y=y(g["y"], g["z"], 0.0), z=z(g["z"], g["y"], 0.0), x_up=x(g["x_up"], g["y"]))
    c["REAR_ARCH"] = (*moved(0.80, *c["REAR_ARCH"][:2])[1:], c["REAR_ARCH"][2])
    c["GATE_X"], c["STOP_X"], c["LENS_X"] = x(c["GATE_X"], -1.9), x(c["STOP_X"], -1.9), x(c["LENS_X"], -2.0)
    pn = c["PANELS"]
    c["PANELS"] = dict(x=x(pn["x"]), z=z(pn["z"]), front=tuple(y(v) for v in pn["front"]),
                       rear=tuple(y(v) for v in pn["rear"]), gate=(y(pn["gate"][0], 0.6, 0.0), z(pn["gate"][1], -1.3, 0.0)),
                       lid=(y(pn["lid"][0], 0.6, 0.0), z(pn["lid"][1], 0.9, 0.0)))
    c["GUARDS"] = {k: (y(gy, gz), z(gz, gy), x(gx, gy, gz)) for k, (gy, gz, gx) in c["GUARDS"].items()}
    c["RAIL"] = tuple(z(v, -0.3, 0.70) for v in c["RAIL"])
    c["LAMPS"] = dict(c["LAMPS"], tail_z=z(c["LAMPS"]["tail_z"], -2.0, 0.6), tail_y=y(c["LAMPS"]["tail_y"], 0.6, 0.6),
                      areas=tuple((dict(zn, **dict(zip(("lo", "hi"), box(zn["lo"], zn["hi"]))),
                                        below=tuple(_plane(p, n) for p, n in zn.get("below", ()))), rgb, lit)
                                  for zn, rgb, lit in c["LAMPS"]["areas"]))
    t = c["T_BADGE"]
    c["T_BADGE"] = (*moved(0.0, t[0], t[3])[1:2], t[1], t[2], moved(0.0, t[0], t[3])[2], *t[4:])
    c["TESLA"] = (z(c["TESLA"][0], -2.0, 0.0), *c["TESLA"][1:])
    c["BADGE_Y"] = tuple(y(v, c["TESLA"][0], 0.0) for v in c["BADGE_Y"])
    c["FRUNK_TUB"] = dict(c["FRUNK_TUB"], y=tuple(y(v, 0.65, 0.0) for v in c["FRUNK_TUB"]["y"]))
    c["PLATES"] = tuple((n, tuple(moved(*q) for q in poly), w, m) for n, poly, w, m in c["PLATES"])
    c["DROP_COMPS"] = tuple((o, *box(lo, hi)) for o, lo, hi in c["DROP_COMPS"])
    c["DROP_FACES_COMPS"] = tuple((o, *box(lo, hi), a, d) for o, lo, hi, a, d in c["DROP_FACES_COMPS"])
    c["CARBON"] = dict(c["CARBON"], zones=tuple(dict(zn, **dict(zip(("lo", "hi"), box(zn["lo"], zn["hi"]))),
                                                     **({"below": tuple(_plane(p, nrm) for p, nrm in zn["below"])}
                                                        if "below" in zn else {}))
                                                 for zn in c["CARBON"]["zones"]))


# the cabin with the body (grid): the field brings the body round the cabin down about _CAB (seat height 13 mm, belt
# 21, roof 26; the cabin is rigid: the seat_head.py heads and the sit / back / feet fits set it), so the passengers'
# SEAT h (over the ground) by _CAB; cabin.py's heights are over the built body's bbox centre (geometry.json zmid),
# which the field moved from _ZMID[0] to _ZMID[1] (its lowest point is the rear bumper's now): those by the difference
_CAB, _ZMID = -0.0219, (0.6414, 0.6397)


def _cabin_down(c):
    dz = _CAB - (_ZMID[1] - _ZMID[0])
    c["SEAT"] = dict(c["SEAT"], h=round(c["SEAT"]["h"] + _CAB, 4), z=round(c["SEAT"]["z"] + dz, 4))
    c["CABIN_FLOOR"], c["CABIN_ZC"] = round(c["CABIN_FLOOR"] + dz, 4), round(c["CABIN_ZC"] + dz, 4)
    c["DASH"] = {k: (*v[:-1], round(v[-1] + dz, 4)) for k, v in c["DASH"].items()}


_moved_positions(CAR)
_cabin_down(CAR)
