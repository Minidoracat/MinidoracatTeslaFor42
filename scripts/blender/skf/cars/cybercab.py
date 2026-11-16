"""Cybercab (2026, the production car, gold): the mod's own body, built from Tesla's pictures alone by
scripts/blender/skf/prep_cybercab.py (no third-party model; temp/skf_cc/REPORT.md). CAR=cybercab. Keys as in model_y.py
(each is the module constant it sets). SRC is the prep's own .blend (one object per material, the glass per pane, every
face its panel in the face attribute `panel`: PANEL_PARTS), already on Tesla's size, track and tyres. A two-seater with
no front trunk (SEAT front_only, template MinidoracatTeslaCoreNoFrunk): two butterfly doors (DOOR_HINGE, a raked axis
at the A-pillar's foot: up and forward), the hatch-like trunk lid, the hood on the body (EngineDoor stays a part for
vanilla's mechanics, with no model: no animation). No steering wheel, column or pedals (DASH wheel None); the big
centre screen (rider guide 05). One paint, gold, on the rider guide's side view door (PAINT_CHART). Grid units,
pre-centre frame (+Y front, +Z up, -X car left, ground z 0; the prep's metres x 0.826) unless noted; numbers and
sources: references/cybercab.md, models-cybercab.md.
"""
import json
import math
import os
import pathlib

K = 0.826                                  # grid per metre (pzveh.K): the prep's numbers are metres


def _g(*m):
    return tuple(round(v * K, 4) for v in m)


def _axis(sd):
    """The butterfly hinge axis of the door on side sd (-1 left): raked back and in (rider guide p.5: the doors swing up
    and forward); the right one mirrored (its angle the other sign). With DOORS' 93 deg and DOOR_HINGE: fitted to the
    rider guide p.7's open door (rg-p07-x742, the camera on the wheels and the body: temp/skf_cc_car/pairs)."""
    x, y, z = -0.37 * sd, -0.43, 0.6
    n = math.sqrt(x * x + y * y + z * z)
    return (x / n, y / n, z / n)


# The prep's own numbers (metres in its frame: +Y front, ground 0): the body's bbox and the wheels (prep_report.json),
# the doors', trunk lid's, port's and tail lamp's lines (cybercab_lines.json). Every module that lists the cars
# (scripts/seat_anim.py: all of them, for any car's build) imports this file, so they come from a committed snapshot
# of those keys (cars/cybercab_body.json), not from temp/skf_cc (gitignored: absent from a clean checkout). A body round:
# copy the prep's four files into temp/skf_cc, `python scripts/blender/skf/cars/cybercab.py` (refreshes the snapshot),
# build (models-cybercab.md). A Cybercab build (CAR=cybercab) stops while the snapshot is behind temp/skf_cc.
_TMP = pathlib.Path(__file__).resolve().parents[4] / "temp" / "skf_cc"
_SNAP = pathlib.Path(__file__).with_name("cybercab_body.json")
_KEYS = {"prep_report.json": ("body_bbox", "wheels"),
         "cybercab_lines.json": ("door_left", "trunk", "charge_port_centre", "tail_lamp_side_red_left",
                                 "tail_lamp_side_red_right", "tail_lamp_grey_left", "tail_lamp_grey_right",
                                 "tail_lamp_centre", "spoiler_lamp_left", "spoiler_lamp_right")}


def _from_tmp():
    """The snapshot's keys as temp/skf_cc has them (None without the prep's files there)."""
    if not all((_TMP / f).exists() for f in _KEYS):
        return None
    return {f: {k: json.loads((_TMP / f).read_text())[k] for k in ks} for f, ks in _KEYS.items()}


if __name__ == "__main__":
    _now = _from_tmp()
    if _now is None:
        raise SystemExit(f"cars/cybercab.py: no prep output in {_TMP} (models-cybercab.md)")
    _SNAP.write_text("{\n" + ",\n".join(f" {json.dumps(f)}: {{\n" + ",\n".join(
        f"  {json.dumps(k)}: {json.dumps(v, separators=(',', ':'))}" for k, v in d.items()) + "\n }"
        for f, d in _now.items()) + "\n}\n", newline="\n")
    print(f"cars/cybercab.py: wrote {_SNAP}")
_SNAPD = json.loads(_SNAP.read_text())
if os.environ.get("CAR") == "cybercab" and _from_tmp() not in (None, _SNAPD):
    raise SystemExit(f"cars/cybercab.py: {_SNAP.name} is behind {_TMP}: python scripts/blender/skf/cars/cybercab.py")
_REP, _LN = _SNAPD["prep_report.json"], _SNAPD["cybercab_lines.json"]
_WF, _WR = _REP["wheels"]["front"], _REP["wheels"]["rear"]
_FA, _RA = _WF["y"], _WR["y"]              # the axles' y (metres)
_BB = _REP["body_bbox"]
# stage_build centres the mesh on its bbox: the shift from the pre-centre frame along y (grid). The cabin's numbers
# below are mesh (centred) coordinates; they were set on the ninth round's body, whose shift was 0.0009
_YC = (_BB[0][1] + _BB[1][1]) / 2 * K


def _cf(v):
    """A centred y set on the ninth round's body in the front half (the front axle and windscreen stayed): the same
    place on this body, centred."""
    return round(v + 0.0009 - _YC, 4)


def _cr(v):
    """A centred y set on the ninth round's body behind the doors: the same distance ahead of the rear axle (-1.3074 m
    then; the rear body moves with it), centred."""
    return round(v + 0.0009 + (_RA + 1.3074) * K - _YC, 4)


def _cross(line, z):
    """The y where the closed polyline `line` (cybercab_lines.json) crosses height z (metres), rearmost first."""
    p, ys = _LN[line], []
    for a, b in zip(p, p[1:] + p[:1]):
        if (a[2] - z) * (b[2] - z) < 0:
            ys.append(a[1] + (z - a[2]) / (b[2] - a[2]) * (b[1] - a[1]))
    return sorted(ys)


# the door's rear edge (B pillar) as a straight line through its crossings at z 0.65 and 0.95, out to 0.35 (the ninth
# round's hand-set line was that, to 3 mm: -0.28 at 0.35, -0.489 at 0.95)
_D65, _D95 = _cross("door_left", 0.65)[0], _cross("door_left", 0.95)[0]
_D35 = _D65 - (_D95 - _D65)
_TRUNK_X = max(abs(q[0]) for q in _LN["trunk"])
_PORT = _LN["charge_port_centre"]


def _box(*keys):
    """(lo, hi) of the closed loops `keys` (cybercab_lines.json, metres)."""
    p = [q for k in keys for q in _LN[k]]
    return [min(q[i] for q in p) for i in range(3)], [max(q[i] for q in p) for i in range(3)]


# The tail lamp band (eleventh round): the side's red runs (TailLight) and the rear face's grey runs (Glass_ReverseLens)
# are the tail lamps, lit with the head lamps; between the grey runs the dark centre (a run of the Trim, no object of
# its own: tail_lamp_centre) and the spoiler's two pale runs on the lid (Glass_SpoilerLamp) the brake lamps. The centre
# is cut out of the Trim along its loop's box (LAMPS brake_box): it shares the grey runs' inner edge
_CTR = _box("tail_lamp_centre")
_CX = _CTR[1][0]
if abs(_CX - min(abs(q[0]) for k in ("tail_lamp_grey_left", "tail_lamp_grey_right") for q in _LN[k])) > 0.002:
    raise SystemExit("cars/cybercab.py: tail_lamp_centre's |x| is not the grey runs' inner edge (cybercab_lines.json)")

CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_cc",
    NAME="MinidoracatTesla_Cybercab",
    SCRIPT_MARK="---- geometry (TeslaCybercab)",
    APP_CAR="app_car_cybercab_{}.png",
    # rider guide: width 1,754, height 1,408; length: the prep's body (its bbox; 01 side is a close perspective view,
    # decisions.md "Cybercab 外形")
    DIMS=(round(_BB[1][1] - _BB[0][1], 4), 1.754, 1.408),
    PORT_NOTE="real Cybercab: the rear bumper's driver side corner under the trunk lid (ERG p.6, rider guide 01 rear, "
              "07)",
    # the one production paint (rescue sheet); Core.lua Specs colors
    PAINTS=[("Gold", None)],
    # (dark, median, bright) sRGB of the rider guide's 01 side view door panel (its 10 / 50 / 90 % luminance pixels):
    # convert.py chart_ramp
    PAINT_CHART={"Gold": ((135, 109, 74), (173, 145, 102), (246, 216, 150))},
    # E2E look-cc-gold (CybercabE2E 2026-11-15, 0.90 skin, noon side view, nearest zoom, left door 9,050 px): game p50
    # (138,115,80) against the 01 side door's (171,144,99), same hue (R:G:B 1:0.833:0.580 / 1:0.842:0.579), 19 % dark;
    # 0.90 x 171/138, 144/115, 99/80
    CAL={"Gold": ((1.115, 1.127, 1.114), (0.0, 0.0, 0.0))},
    COMPOSITOR_MODEL="",
    OFFICIAL_OPTS="",
    RAMP=dict(t=(0.0, 1.0), u=(0.0, 1.0), wheels=()),   # (official_ramp: unused, no design-studio renders)
    # ---- pzveh: wheel. 215/60 R18 front, 225/60 R21 rear (third-party; the prep's tyres, prep_report.json wheels) under
    # flat gold covers nearly as big as the tyre (01 side): the cover's edge stands for the rim flange (prep Cover_*:
    # r 0.309 / 0.338 m), a flat face (WHEEL_FACETS, no shapes) 5 mm proud of the tyre's bulge, a small centre boss (the
    # hub cap). No spokes
    WHEEL_RIM=0.8641,                      # 0.309 / 0.3576
    WHEEL_RIM_REAR=0.8414,                 # 0.338 / 0.4017
    WHEEL_SPOKE=dict(n=0, shape=dict(outer=((0.22, 0.045), (1.0, 0.066)), inner=((1.0, 0.0),)),
                     cap=0.10, inset=-0.0107, dish=0.002, depth=0.004, sweep=0.0, at=0.0),
    WHEEL_FACETS=dict(sink=0.0, rings=4, face="facet", n=0, at=0.0, shapes=()),
    WHEEL_DISC=dict(rotor=0.5, hat=0.3),
    WHEEL_RGB=dict(spoke=60, cap=60, barrel=12, lip=14, rotor=20, hat=20, dark=10, gap=8, tire=(26, 32), tread=22,
                   facet=60, lit=60),
    # the covers' gold (01 side: front cover p50 179,148,99; the centre boss a shade lighter)
    WHEEL_TINT={"facet": (179, 148, 99), "cap": (190, 158, 106)},
    # the tyre's short sidewall under the covers: a small shoulder, the 8 mm bulge high up (prep TYRES bulge)
    TIRE_SHOULDER=(0.055, 0.012),
    TIRE_BULGE=(0.0066, 0.026),
    # ---- pzveh: vehicle script
    OY=0.1978,
    WHEEL_LIFT=0.11,
    TIRE_AXLES=dict(front=(_WF["r"], _WF["w"]), rear=(_WR["r"], _WR["w"])),
    # the prep's tyres stand with their 8 mm bulge out: the wheel centres that far in, on the prep's track
    # (prep_report.json wheels track_m)
    WHEEL_INSET=0.0066,
    # the cabin's physics box (mesh coords): from the windscreen's foot back to 0.157 m ahead of the rear axle
    CAB_BOX=(1.20, _cf(0.35), _cr(-0.95)),
    # two seats behind the door opening's middle by back (front only), x 0.27 (06 top view: two ~0.48-0.52 m seats
    # 0.09-0.10 m apart, K 0.826 grid per m; at 0.31 the gap was 0.24 m, cabin-r2); the passengers' pose: SEAT_POSE
    SEAT=dict(x=0.27, h=0.384, z=-0.222, back=(0.16,), out=0.30, front_only=True),
    # scripts/seat_anim.py POSES: the shared front pose (leant back, thighs down) and the hands from the wheel to the
    # lap (no steering wheel): upper arms down 35 put both hands on the thighs' middle, their lowest point 1.4 cm into
    # (male) / 2.0 cm over (female) the thigh top
    SEAT_POSE={"front": [("Bip01", 25.0), ("Bip01_L_Thigh", -10.0), ("Bip01_R_Thigh", -10.0),
                         ("Bip01_L_UpperArm", -35.0), ("Bip01_R_UpperArm", -35.0)]},
    BODY_W_Z=0.55,
    # butterfly doors about DOOR_HINGE along _axis, 93 deg, 2 s (fitted on rider guide p.7: the door's top 2.36 m up);
    # the trunk lid at its top edge, 45 deg (rider guide 04: 49.5 fitted on the photo; Main 2026-11-14: 45), 3 s like
    # the Model 3's powered lid. No EngineDoor: the hood stays on the body (no lid, no animation)
    DOORS={
        "DoorFrontLeft": (-1, _axis(-1), -93, 2.0), "DoorFrontRight": (1, _axis(1), 93, 2.0),
        "TrunkDoor": (0, (1, 0, 0), -45, 3.0),
    },
    # the hinges near the door's front top corner (prep door paint at z 0.95: y 0.919, x 0.807), with _axis fitted
    DOOR_HINGE={"DoorFrontLeft": _g(-0.84, 1.00, 1.04), "DoorFrontRight": _g(0.84, 1.00, 1.04)},
    GATE_IN=(0.0, 0.894, -0.447),
    GATE_HINGE="top",
    # ---- convert.py: the source (TMP, gitignored: a copy of the prep's output, temp/skf_cc in the main checkout)
    SRC=("cybercab_src.blend",),
    SRC_C=(0.0, 0.0),
    # the prep's frame is the build's (metres, +Y front, -X left, ground 0): SRC_YFRONT's matrix with both flips undone
    SRC_YFRONT=0.0,
    SRC_SCALE=1.0,
    SRC_STRETCH=(-1.0, -1.0, 1.0),
    SRC_FLIP=False,
    BELT_Z=round(0.95 * K, 4),             # the door glass's foot
    TIRE_OBJ="Tyre_",
    DROP=("Tyre_", "Cover_"),
    DROP_COMPS=(),
    ARCH_LINER=None,
    # the front wells (source frame: metres, z from the ground). Toe plates: the cabin's toe board (y 0.86-0.90, its
    # liner facing the cabin) is culled from the well, so the seated passengers' shins and shoes showed through the
    # front arches' top (main checkout temp/plan-next8-1114/e2e/shots/acc-cc-seat-4fb17dc.png: a blue-purple patch,
    # their trousers under the sky light); a plate facing forward just ahead of it, where every such sight line
    # crosses (temp/skf_cc/work/pax_leak.py: |x| 0.445-0.655, z 0.39-0.65 at y 0.87, Male and Female). Well plates:
    # the well has no inner or front wall seen from the wheel (the nose's side skin at |x| 0.41 faces in, the bumper
    # corner's at |x| 0.62-0.65 out), so from behind (W / N cameras) the arch's front half showed the ground under the
    # nose (temp/skf_cc/work/pix_ray.py); an inner plate facing out at |x| 0.33 (the tyre's inner face swings in to
    # 0.33 at full lock) from the underbody to 3 cm under the hood, and a front one facing back at y 1.53 (the tyre's
    # front reaches 1.49, 1.45 steered) out to inside the skin
    PLATES=tuple((f"ToePlate{s}", tuple((s * x, 0.88, z) for x, z in ((0.42, 0.34), (0.67, 0.34), (0.67, 0.68), (0.42, 0.68))),
                  (0, 1, 0), "arch_liner") for s in (-1, 1))
    + tuple((f"WellInner{s}", tuple((s * 0.33, y, z) for y, z in (
        (0.90, 0.16), (1.68, 0.16), (1.68, 0.52), (1.65, 0.535), (1.60, 0.57), (1.55, 0.595), (1.50, 0.62),
        (1.45, 0.645), (1.40, 0.665), (1.30, 0.695), (1.20, 0.71), (0.95, 0.72), (0.90, 0.72))), (s, 0, 0), "arch_liner")
            for s in (-1, 1))
    + tuple((f"WellFront{s}", tuple((s * x, 1.53, z) for x, z in (
        (0.33, 0.16), (0.60, 0.16), (0.62, 0.22), (0.65, 0.40), (0.65, 0.59), (0.63, 0.61), (0.33, 0.61))),
             (0, -1, 0), "arch_liner") for s in (-1, 1)),
    SEAL_CLIP=True,
    # none on the trunk lid and the doors (convert.py SEAL_NONE): their panels share their edges with the body (the
    # prep's grooves, no gap); clipped to dashes where they met the tail lamp bar, the lid's bottom edge's strips hung
    # under the open lid as a dashed black line; the doors' strips (2 cm past the edge, 8 mm behind) showed along the
    # open door's rear edge as a broken black line, mostly under a pixel wide (e2e cc8a SW all)
    SEAL_NONE=("TrunkDoor", "DoorFrontLeft", "DoorFrontRight"),
    RAIL=None,
    # the prep's 54k-triangle paint (a 3 mm cut mesh) collapsed to about the other cars' size: each object X
    # symmetric, its open edges, its panel seams and its flat underside's outline held (DECIMATE_KEEP_BOUNDARY,
    # DECIMATE_HOLD_UNDER: pzveh.decimate). Paint 16000 -> 24000: at 16000 the held seams left the panels so few
    # triangles that 3,400 faces stood off the surface and three more passes held patches of fine vertices (18.0k out,
    # the rear quarters and hood faceted); at 24000 one pass, the seams thinned after it (15.9k out). Trim 15000 ->
    # 35000 (frontlip batch): below ~27000 the collapse took held seam vertices, ~2000 faces stood off the surface and
    # three more passes held fine patches that the rest fanned round (the nose lip's corners crumpled, 19.8k out);
    # at 35000 one pass, 0 faces off (20.8k out). The Grille's 1.5k fins stay whole: halved they turned to spikes
    DECIMATE={"Paint": 24000, "Trim": 35000, "Liner": 4000, "Glass_Windshield": 1200, "Glass_Door": 700,
              "Glass_Quarter": 350, "Glass_ReverseLens": 300, "HeadLight": 800, "TailLight": 1000},
    DECIMATE_KEEP_BOUNDARY=True,
    DECIMATE_HOLD_UNDER=True,
    DECIMATE_THIN=(round(0.0003 * K, 6), round(0.02 * K, 4)),   # (pzveh.thin_seams: the cut's 1-2 mm seam vertices)
    DECIMATE_SNAP=round(0.001 * K, 6),     # (pzveh.decimate: a few held-seam collapses stood up to 19 cm off)
    # (pzveh.decimate smooth) the paint's corner normals the fine faces' mean within 4 cm: one fine face each gave a
    # vertex's corners different normals, and the prep's 3 mm ripples (the nose's plaid, the hood's bands) came along
    # Trim 4 cm (a12 r3): the rear bumper's face and the tail's groove read as big lit triangles and the nose's lower
    # lip as streaks (the trim's corners one fine face each; 2 cm left the groove's V); the 30 deg cap keeps the slats
    DECIMATE_SMOOTH={"Paint": round(0.04 * K, 4), "Trim": round(0.04 * K, 4)},
    # (pzveh.decimate crease) the side table's knee crease C cut into the paint, held through the collapse, and the
    # smoothing above kept to each side of it: across it the 4 cm mean drew the a12 door's crease (prep: 9-21 deg
    # within +-1.5 cm) out into a 4 cm ramp of 2-6 deg
    DECIMATE_CREASE={"Paint": ("cybercab_side.npz", 0.5)},
    # (convert.py share_seams) Paint and Trim each thinned their shared outlines on their own: along the belt band's
    # lower edge they parted by up to 0.36 mm (127 of 197 1 cm stations a crack); Paint / Liner the same round the
    # rear arch top (66 of 204 points, INTEGRATE a12's BOUNDARY_KNOWN)
    SEAM_SHARE=(("Paint", "Trim", round(0.001 * K, 6)), ("Paint", "Liner", round(0.001 * K, 6))),
    PAINT_MAT="Paint",
    UV_FILL=True,                          # (convert.py fill_slivers) texels the bake left black under sliver UVs
    UV_FILL_TONE=True,                     # (convert.py textures) the filled texels stay out of the paint's quantiles
    HGT_CORNER=True,                       # (convert.py textures: the collapsed body's big triangles drew steps)
    # the hood's seam groove (the hood stays on the body: no SEAM_LINE part) drawn as an even line along the prep's
    # own hood path instead of its 5 mm groove's ragged dark texels (convert.py groove_ink)
    GROOVE_INK=dict(file="cybercab_lines.json", lines=("hood",), w=round(0.006 * K, 4), k=0.6,
                    reach=round(0.012 * K, 4), rgb=(58, 58, 60)),
    # by day: the lower body, bumpers and seam grooves dark grey (01: sill p50 50), the wheel house liners and B pillar
    # black, the light bar grey (02 unlit: its upper half ~150 and the lens ~60-75 by paint ~240, i.e. 0.55-0.62 of the
    # paint; 128 read 0.73-0.77 of it on the a10 shell in the pairs' soft and rim light and the game's flat light), the
    # tail lamps' side runs a dark red unlit (01 rear: (64, 46, 46) by the tail paint's 145; 122 / 30 / 36 read 0.62 of
    # the paint, a bright red; lit they take the lights texture), the plate light grey, the side markers amber
    MAT_RGB={"Trim": (58, 58, 60), "Liner": (24, 24, 26), "Glass": (26, 30, 34), "HeadLight": (106, 108, 114),
             "TailLight": (88, 62, 62), "Plate": (206, 208, 212), "Marker": (196, 122, 44)},
    # (pane, box lo, hi, colour, object): the tail face's grey runs (01 rear: 115-124 by the tail paint's 145, 0.82;
    # 112 with AO read 0.5 and only their top 0.6 cm showed: LENS_FLAT) and the spoiler's paler runs (118 on the bar's
    # 90); the boxes on each object's own range (convert.py classify RECOLOR), the spoiler's one box a side: the rear
    # camera's glass between them (|x| < 0.01) stays dark. The head lamps' dots (the plate's material) dark grey unlit,
    # in their dark lens (02 unlit: lens p10-p90 31-78; lit they take the lights texture as before); the plate keeps
    # its colour (its own boxes miss it)
    RECOLOR=(("Glass", _g(-0.01, -0.01, -0.01), _g(0.01, 0.01, 0.01), (156, 156, 158), "Glass_ReverseLens"),
             ("Glass", _g(-0.01, -0.01, -0.01), _g(-0.29, 0.01, 0.01), (118, 118, 120), "Glass_SpoilerLamp"),
             ("Glass", _g(0.29, -0.01, -0.01), _g(0.01, 0.01, 0.01), (118, 118, 120), "Glass_SpoilerLamp"),
             ("Plate", _g(-0.01, -0.01, -0.01), _g(0.01, 0.01, 0.01), (84, 84, 88), "LampDots_Left"),
             ("Plate", _g(-0.01, -0.01, -0.01), _g(0.01, 0.01, 0.01), (84, 84, 88), "LampDots_Right")),
    # the shadow under the spoiler's duck lip (official 01 rear: 0.30 of the face under the lip, 0.90 at the fold),
    # by the texels' height between the lip's black face and the notch's ledge (convert.py lip_shade: both from the
    # shell); r13's CARBON box on the ledge's faces drew a brown line as ragged as the collapsed triangles
    CARBON=None,
    LIP_SHADE=dict(k=(0.30, 0.60), soft=round(0.004 * K, 4), reach=round(0.06 * K, 4)),
    GLASS_MATS=("Glass",),
    GLASS_OPAQUE=("Glass_ReverseLens", "Glass_SpoilerLamp", "RearCamera"),
    # objects flat like a badge (no AO) and lit as upright faces (convert.py _upright_normals): the grey runs' lower
    # half slants down into the groove, it read 77-85 of 112 and dark under the top light
    LENS_FLAT=("Glass_ReverseLens",),
    GLASS_BACKS=("WinLH", "WinLT", "WinRH", "WinRT"),
    ROOF_PANE="-",                         # (a body-colour roof)
    MIRROR_CAP="-",                        # (no mirrors: cameras)
    # lamps: the light bar and the wedge head lamps (HeadLight) with their dots (LampDots, the plate's material); tail
    # lamps (LightLT / RT) the side's red runs (TailLight) and the rear face's grey runs (tail_objs); brake lamps
    # (StopL / R) the centre run of the Trim (brake_box: its faces between the four planes, the Trim bisected along
    # them, so its edges are the loop's straight lines) and the spoiler's runs on the lid (brake_objs)
    LAMPS=dict(head=("HeadLight",), head_y=0.5, head_objs=("LampDots_Left", "LampDots_Right"),
               tail=("TailLight",), tail_z=0.3, tail_y=-1.0, blade=None, tail_objs=("Glass_ReverseLens",),
               brake_objs=("Glass_SpoilerLamp",),
               brake_box=dict(mat="Trim", cut=True, lo=_g(-_CX - 0.03, -9, _CTR[0][2] - 0.03),
                              hi=_g(_CX + 0.03, _CTR[1][1] + 0.03, _CTR[1][2] + 0.03),
                              below=((_g(0, 0, _CTR[0][2]), (0, 0, -1)), (_g(0, 0, _CTR[1][2]), (0, 0, 1)),
                                     (_g(_CX, 0, 0), (1, 0, 0)), (_g(-_CX, 0, 0), (-1, 0, 0))))),
    # part lines, side view (y, z): the door's rear edge, a straight line through the prep's door outline at z 0.65 and
    # 0.95 (cybercab_lines.json door_left), out to z 0.35
    LINES={"S": (_g(_D35, 0.35), _g(_D95, 0.95)), "BF": (_g(_D35, 0.35), _g(_D95, 0.95))},
    FRONT_Y=round(1.15 * K, 4), SILL_Z=round(0.30 * K, 4), ARCH=(0.0, -9.0),
    IN_DOOR=dict(up=round(0.95 * K, 4), x=0.40),
    IN_GATE=dict(y=-9.0, z=9.0, up=9.0, x_up=0.0),
    # door front edge and rear edge (B pillar) at the belt (the outline at 0.95), the cabin's ring cut behind the seats
    # (no door): 0.557 m ahead of the rear axle
    DOOR_Y=_g(0.919, _D95, _RA + 0.5574),
    GATE_Z=round(min(q[2] for q in _LN["trunk"]) * K, 4),   # the trunk lid's lower edge (its seam's lowest point)
    REAR_ARCH=(*_g(_RA, _WR["r"]), round(0.338 * K, 4)),
    GATE_X=round((_TRUNK_X - 0.034) * K, 4),   # (inside the trunk lid's seam; unused: IN_GATE off, no CUT_X)
    STOP_X=0.0,                            # (no brake lamps by |x|: LAMPS brake_objs / brake_box)
    PANELS=dict(x=9.0, z=-9.0, front=(9.0, 9.0), rear=(9.0, 9.0), gate=(-9.0, 9.0), lid=(9.0, 9.0)),   # (PANEL_PARTS)
    # the faces' panels (prep PANELS: Body, DoorFrontLeft, DoorFrontRight, TrunkDoor, EngineDoor, ChargePortDoor):
    # the doors and the trunk lid are parts, the hood and the port lid stay on the body
    PANEL_PARTS={1: "DoorFrontLeft", 2: "DoorFrontRight", 3: "TrunkDoor"},
    # rear guards from 0.857 m ahead of the rear axle (the rear quarter behind the door)
    GUARDS=dict(front=(round(0.95 * K, 4), 0.80, 0.45), rear=(round((_RA + 0.8574) * K, 4), 0.85, 0.45)),
    # damage zones of the rest of the body (EngineDoor's condition in front, TruckBed's behind; else Roof, never
    # damaged): the paint ahead of the front wheel arch's front (0.35 m ahead of the front axle) and the hood (panel 4)
    # in the front guards' zones, behind 0.543 m behind the rear axle (0.14 m behind its arch) in the rear guards';
    # the bumpers' dark trim there in Head / Tail (shell drawn untinted, as vanilla's bumpers)
    HEAD_TAIL=(round((_FA + 0.3505) * K, 4), round((_RA - 0.5426) * K, 4)),
    MASK_PAINT_GUARD=True,   # (convert.py mask_paint_guard) the nose lip's sliver trim under the paint: no Head on gold
    # (convert.py lamp_zones) the lamps' unlit faces in Head / Tail (HEAD_TAIL) into the light zones: the front corner
    # markers, the reverse lens and camera glass on the rear bumper, the tail lamps' unlit part, the light bar's
    # housing (Trim, the bumper's too: a box); on the tailgate (Boot, its damage shell in the paint's hue) the duck
    # lip's black rear face and the seams (Trim) into the light zones too: not a lamp (prep_cybercab SPOILER; the tail
    # lamp bar is under it on the body), gold at f503acb (E2E cc5h), a solid grey-green band in Tail (lamp_zones)
    LAMP_ZONES=dict(keep=("Marker", "Glass"),
                    boxes=((("Trim",), (0.0, -0.01, -0.017), (0.60, 0.01, 0.02), "HeadLight"),), trim=("Trim",)),
    # (pzveh damage_uv1) the tailgate's UV1 box (DAMAGE_BOX) fitted onto ModernCar's boot deck (UV1 island 36) and back
    # (12) only, and only their rear 0.75 of the length: ModernCar's whole Boot box reaches 26 cm further forward with
    # island 43 (four slanted triangles, |n.x| 0.79), so the front third of our long deck lay ahead of ModernCar's deck
    # and its UV1 ran on (extrapolated, bary to -1) into Veh_Damage2's flat dent blob (u 66-160, v 186-255 px of 512):
    # one flat orange patch mid-deck at condition < 40 (bb1f119 on). Islands only: the deck's front edge still on the
    # blob's tip (787 cm2); ModernCar's own deck front reaches u 82 there. 0.75: none (temp/skf_cc_car/blob_hit.py)
    DAMAGE_BOX_REF={11: dict(islands=(12, 36), y=(0.0, 0.75))},
    # (pzveh damage_own) body faces whose UV1 lands on opaque damage-map texels no ModernCar body panel owns (a lamp's
    # or nobody's) try the next 8 nearest ModernCar islands: the rear corner facet (r10 on) ran off ModernCar's tail
    # panel onto its tail lamp's hole (brown block at < 40), the duck lip's end cap onto a grey streak (white dot); one
    # then landing mostly on solid art takes a less opaque island (the corner's rear facets: a solid dent spot on
    # ModernCar's hood front, a grey-brown blob under the lip's end at < 60, e2e cc8a)
    DAMAGE_OWN=8,
    PANEL_ZONES={4: ("GuardLH", "GuardRH")},
    CUT={},
    PLANES={},
    CUT_X=("-",),
    CUT_X_Y=-9.0,
    DOOR_OBJS=(),
    GATE_OBJS=(),
    GATE_COMPS=(),
    GATE_CUT_COMPS=(),
    PART_OBJS={},
    PANES={"Body": {"WinT", "WinLT", "WinRT"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"},
           "TrunkDoor": set()},
    # badges: none drawn (the prep has the front camera, plate and grille)
    T_BADGE=None,
    TESLA=None,
    LENS_X=0.0,
    BADGE_Y=(-9.0, -9.0),
    BLADE=False,
    MODELY=None,
    PERF_BADGE=None,
    CALIPER=None,
    FRUNK_TUB=None,                        # (no front trunk)
    # charge port (ERG p.6, rider guide 01 rear / 07): the prep's port lid centre (cybercab_lines.json
    # charge_port_centre), from behind onto the bumper (pzveh PORT_X)
    PORT=_g(_PORT[1], _PORT[2]),
    PORT_X=round(_PORT[0] * K, 4),
    # ---- cabin.py (mesh coords, centred: _cf the front half's, _cr the rear's on this body)
    CABIN_FLOOR=-0.480,                    # (seat_head feet: the passengers' feet 6 mm into -0.474)
    CABIN_FRONT_Y=_cf(0.90),
    TRUNK_Y=_cr(-0.60),
    CABIN_ZC=-0.048,
    SEAM_CLEAR=0.065,
    # the trunk's sides from one profile (cabin.py trunk_walls, as Model S / X): the per-ray shell left black teeth
    # along them through the open lid
    TRUNK_WALL=True,
    HUMP_BACKS=False,
    # rider guide 04: the trunk's front wall (cabin.py TRUNK_BULKHEAD, on the first shell ring behind TRUNK_Y: the open
    # lid shows it, not the seats; from inside the dark wall behind them), its trunk side mid grey with light upright
    # ribs (ribs: cell, spacing, half span inside the trunk walls, the cell of their sides: side on through the rear
    # quarter window the outer rib's light side read as a 2 px grey upright, e2e cc8a SW shut)
    TRUNK_BULKHEAD=dict(z=0.05, cells=("liner", "bed_wall_hi"), ribs=("bed_rib", 0.10, 0.30, "floor")),
    # the front seats (06, ERG p.22, rider guide pp.10-12 / 05; cabin.py slim): a backrest 0.11 thick at its foot,
    # 0.08 at its top (back, back_top; ERG p.22 side 11-15 cm; 24-48 cm free behind it to the bulkhead and the floor),
    # its own headrest over a 2 cm neck gap (head: 0.16 high, 0.75 / 0.62 of the seat wide at its foot / top, 0.124 /
    # 0.085 deep, its front 6 deg more upright and its foot 0.03 behind the backrest's front; ERG p.22 side 19 cm high,
    # 15 cm deep, set back and upright, rider guide p.10 x1227 75 / 55 %; ERG's 15 deg put the fireman helmet's brim
    # 18-25 mm into it, this clears it by 4 mm, seat_head HEADREST what-if; back = backrest + gap + headrest, as tall as
    # the one-piece one was), three slightly convex bands between the
    # backrest's two seams (bulge; ERG p.22 front), its top corners rounded (shoulder), its sides a little forward
    # (wing: low wide bolsters, no tubes), a thick cushion ending in a waterfall roll (roll) with the dark trim on its
    # lower front (apron) on one low pedestal; 0.44 wide, 0.10 apart
    # (06 top view, cabin-r2); the cushion's front 4 cm back from the bucket's (front: 06 side view 0.392 of the
    # wheelbase behind the front axle, it was 0.362); its top where the bucket had it (06 reads it 0.22 m higher: the
    # head would stand 8 cm through the roof), recline kept 32 for the passengers' pose (the official reads ~26:
    # cabin-r1 d; at 26 seat_head back -70..-14, into their backs). Between them (centre: its top over the cushions'
    # top, length, top width; 05: a raised block filling the gap, the buckles at its rear sides) one console block
    # with the cup holders on its top
    SEATS=dict(front=dict(w=0.44, back=0.655, recline=32, dy=0.056, dz=-0.121, cushion=0.10,
                          slim=dict(back=0.11, back_top=0.08, ahead=0.0,
                                    head=(0.16, 0.02, (0.75, 0.62), (0.124, 0.085), 6, 0.03), seams=(0.57, 0.84),
                                    pedestal=(0.26, 0.30), round=0.045, front=0.26, roll=(0.06, 0.02),
                                    shoulder=(0.15, 0.10), bulge=0.006, wing=(0.6, 0.02), apron=(0.70, 0.55)),
                          centre=(0.04, 0.39, 0.09)),
               # 04: the sill plate over the opening's lower edge, the floor mat (bin) inside the trunk walls; its rear
               # half fitted 4 mm inside the body (its ends had stuck out of the tail face as two black blocks at the
               # grey runs' inner ends, official01_rear)
               sill=(0.80, 0.06, 0.004), bin=(0.66, 1.00)),
    PARCEL=None,
    # rider guide 05 / pp.7 / 11-14, ERG pp.19 / 23 (temp/plan-next8-1114/cabin-r1, -r2): a low dash, no console (the
    # footwell open), no steering wheel (wheel None). In 05 / p.7 x742's layers: the top and the lower body dark grey
    # (dash, dash_top), the cabin face a silver-white band (dash_up) with the dark air-vent groove across it (strip,
    # 05's label 4; 2.8 x the screen's width, 05), under it the body's dark lower edge; the ledge the big screen
    # (screen_size, 1.54:1, top 12 deg forward) stands on, no stand, its back dark (rear: 05 / ERG p.9 x99), the window
    # switches on the ledge under it (the detail model's marks: icons); vent: the detail model's groove in the lower
    # edge. Its ends 4 cm inside the door cards (x 0.64 at its height)
    DASH=dict(size=(1.18, 0.30, 0.16), console=None, dash=(0, _cf(0.80), 0.030), stand=None,
              screen=(0, _cf(0.597), 0.0455), screen_size=(0.42, 0.272), rear="screen_rear", wheel=None, vent=-0.022,
              parts=(((1.20, 0.075, 0.034), 0.015, "dash_top", (0, _cf(0.6625), 0.093)),
                     ((1.19, 0.016, 0.070), 0.006, "dash_up", (0, _cf(0.645), 0.040)),
                     ((1.176, 0.008, 0.008), 0.002, "strip", (0, _cf(0.6355), 0.047)),
                     ((0.24, 0.105, 0.030), 0.010, "dash", (0, _cf(0.6075), -0.103)),
                     ((0.10, 0.008, 0.014), 0.003, "switch", (0, _cf(0.5545), -0.097))),
              icons=((-0.022, _cf(0.5505), -0.097), (0.022, _cf(0.5505), -0.097))),
    # the door card (rider guide 05 / p.7 x795, ERG p.21 x198): the inner panel mid-dark grey (DOOR_INNER; p.7 x742
    # reads 70-83 in the open door), the darker pocket with the armrest under it and the pull handle in it, the
    # speaker grille low at the front
    DOOR_CARD={
        "front": [
            ("armrest pocket", "rear", 0.10, -0.205, 0.50, 0.085, 0.030, "base", 0.020),
            ("armrest", "rear", 0.12, -0.262, 0.44, 0.030, 0.070, "bed_wall_mid", 0.012),
            ("pull handle", "rear", 0.20, -0.195, 0.22, 0.020, 0.040, "screen_back", 0.008),
            ("door button", "rear", 0.43, -0.186, 0.035, 0.012, 0.050, "trim", 0.004),
            ("speaker grille", "front", 0.06, -0.47, 0.17, 0.13, 0.010, "wheel", 0.030),
        ],
    },
    DOOR_INNER=dict(cell="bed_floor"),
    # the doors' and the trunk lid's edge strips under the belt in the paint next to them, over it black (convert.py
    # pieces: the belt in the pieces' pre-centre frame; cabin-r2 D)
    SLAB_BELT_PRE=True,
    # the doors' edge strips on a paint / trim seam inside the skin (grid tolerance) and near the glass (grid) black:
    # the one under the window's belt took the paint and ran 2-3 cm in past the glass foot, a light line through the
    # glass from the front three-quarters (cc10a-3778b4a strip-E / strip-S; convert.py slab_seam_dark)
    SLAB_SEAM_DARK=(0.0015, round(0.06 * K, 4)),
    # the headliner, the pillars and the roof rails inside light grey (rider guide 05; the body's reversed faces over
    # the belt, ahead of the trunk)
    LINER_UP=dict(cell="bed_rib", dz=0.0, y=_cr(-0.60)),
    # the black trim behind the cabin (the rear arches' lips) seen from inside over the trunk walls' top: reversed
    # liner copies too, else through the windscreen's top corners its culled backs showed the ground (cabin-r2
    # e_windscreen's light triangles; convert.py pieces). From the trunk floor up, behind the cabin's rear wall
    TRIM_BACKS=(((-1.0, -2.5, -0.25), (1.0, _cr(-0.60), 0.5)),),
    # and every body trim face within 3 cm of a window pane (convert.py pieces): the door glass / quarter light
    # divider (from inside, a line of sky behind it: e2e cc7a vd-day-driver-e), the A pillars' feet at the windscreen's
    # lower corners (r11: ~1 cm of sky), the window surrounds; from the panes, not boxes (the body rounds move them)
    TRIM_BACKS_GLASS=round(0.03 * K, 4),
    # the A pillars' inner trim, light as the headliner (rider guide 05: white A pillars; 02 shows the far one grey
    # through the windscreen; convert.py pillar_cover): from each windscreen side edge in to a ridge behind
    # the gap and out to the door glass's front edge, wherever they are within 15 cm (r11: 5-20). r11 widened the
    # windscreen 4 cm onto the pillar: seen through it, the far pillar's skin stood edge on (a grey line, the ground
    # behind it through the door glass; at ae38316 a gold band)
    # a12 r3: cell "bed_rib" (120 grey) -> "silver" (226, the dash's bright strip): the guide's 05 pillars measure 202-220
    PILLAR_COVER=dict(pairs=(("WinT", "WinLH"), ("WinT", "WinRH")), gap=round(0.15 * K, 4), depth=0.5, cell="silver"),
    # the slot between the windscreen's foot and the dash closed (convert.py cowl_shelf): a dark strip from the glass's
    # bottom edge back and down at 45 degrees to the cabin within 40 cm. r11 (the same commit) widened it; through it,
    # from behind and the sides, the ground showed below (iso N/W/NW/NE/SW). r13 moved the foot 15 cm forward (under
    # the cowl trim, y 1.352 m on the centre line): the ray passes under the dash to the firewall, 32-37 cm (r11: 25 cm)
    COWL_SHELF=dict(reach=round(0.40 * K, 4), cell="liner"),
    # cabin.py: the parts' names -> palette cells (MinidoracatTesla_vehicle.frag CABIN; the detail model's: DETAIL_RGB
    # and DETAIL_RGB_EXTRA): the seats near black (rider guide 05 / p.7 x742; bed_wall_lo, a cell no other Cybercab
    # part takes: seat_head finds the seats by it), their seams darker, the dash's layers (the silver band appended to
    # the palette for it), the screen's dark back, the screen's car block the other cars' seat grey (screen_car)
    CABIN_CELL_MAP=dict(seat="bed_wall_lo", seam="screen_back", dash="dash", dash_top="dash", dash_up="silver",
                        strip="screen_back", screen_rear="screen_back", switch="screen_back", buckle="screen_back",
                        screen_car="seat"),
    DETAIL_CELL_MAP=dict(seat="liner", seam="mat", stitch="mat", dash_top="dash", dash_up="silver", strip="vent",
                         screen_rear="screen_back", switch="vent", buckle="vent", button="red", icon="chrome",
                         pod="headliner", lamp="pale", stop="red", stop_button="dash", camera="mirror"),
    # the detail model's own texture (pzveh.detail_texture: the shared cells, then these): the red of the buckles'
    # buttons and the STOP sign, the overhead console's grey (a step under the headliner's 120: under flat light its
    # shading in 05 / p.14 is all that shows it), its light strip, the dash band
    DETAIL_TEX="MinidoracatTesla_Cybercab_Detail",
    DETAIL_RGB_EXTRA=dict(red=(196, 30, 36), headliner=(92, 92, 98), pale=(228, 228, 224), silver=(226, 226, 230)),
    # the detail model's overhead console instead of a rear-view mirror (no rear window; rider guide 05: behind the
    # windscreen's top a bar across the headliner, deeper in the middle (the pod) with the camera housing under its
    # front and the capsule under its rear half; p.14 x1691 from the left seat: one long ridge, the headliner's grey,
    # the white capsule across it, the dark STOP button with its red triangle in the capsule's middle)
    ROOF_CONSOLE=dict(size=(0.30, 0.18, 0.070), bar=(0.96, 0.10, 0.030), strip=(0.13, 0.045), strip_y=-0.03,
                      stop=(0.040, 0.024), camera=(0.12, 0.06, 0.060)),
)
