"""Model X source prep, run once before convert.py (CAR=model_x): Abdul.Hannan's 'sketchfab tesla.blend' (a half
model: Mirror + Subsurf + Auto Smooth modifiers) -> the OBJ cars/model_x.py SRC reads, every modifier applied (the
Mirror makes the whole car; Subsurf at level 1 on the body parts, 0 on the tyres and rims; Back Door not welded across
the roof's middle, so each falcon wing door stays its own component for SIDE_PARTS), then the big parts
collapse-decimated with every material border and open edge held (a plain collapse left the paint / black trim borders
as a sawtooth: the diffuser, the sills). Ground (lowest tyre vertex) at z 0.
Then the last Model X Plaid (2021+) against its owner's manual (2026.38.3 p.229 / p.234: length 5,057, width 1,999
without mirrors (2,271 with), height 1,680 (Medium), wheelbase 2,965, overhangs 988 / 1,104, track 1,705 / 1,710 at the
wheel centres, tyres 265/45 R20 front, 275/45 R20 rear) and the design studio's SIDE / FRONT34 / REAR34 renders through
the fitted cameras (.claude/skills/tesla-dev/references/models-model-x.md "對官方"): one continuous displacement field
(FIELD; as prep_model_yl.py: no cuts, every object keeps its triangles, normals by the field's Jacobian, inverse
transpose), some faces recoloured (FIELD arch_inner, mirror, ...) and the mod's own parts as new objects (FIELD spoiler,
...). The doors, lids and glass on the body's centre line (the source's sit 8 mm to the car's right).
    "$B" -b --factory-startup --python scripts/blender/skf/prep_model_x.py [-- <src .blend> <out .obj>]
    python scripts/blender/skf/prep_model_x.py map < points     # "name x y z" pre-centre grid -> through the field
Defaults: temp/skf_mx/src/source/sketchfab tesla.blend -> temp/skf_mx/src/source/model_x.obj (+ .mtl).
Frame: Blender world after the modifiers (x + front, y + car left, z up), source units; the FIELD in metres: u behind
the nose, h over the ground, az off the centre line.
"""
import os
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "temp", "skf_mx", "src", "source")
# triangles after the collapse (2026-11-12 round 2: body 26,000 -> 30,000, tailgate 3,200 -> 6,400, frunk lid 1,200 ->
# 3,000: at the old counts the lid and the tailgate read as flat facets with dark creases, official smooth)
TARGET = {"Car Body": 30000, "Front Door": 4400, "Trunk": 6400, "Bonnet": 3000}
S = 5.057 / 3.1184                         # metres per source unit (cars/model_x.py SRC_SCALE)
K, SRC_C = 0.826, (1.5579, -0.448)          # pzveh.K; cars/model_x.py SRC_C (the pre-centre frame's origin)
CENTRED = ("Front Door", "Back Door", "Bonnet", "Trunk")   # onto Car_Body's mirror plane
# (the .blend's object and material names: the OBJ writes "Car Body" as Car_Body, "Car Paint" as Car_Paint.) Source landmarks (metres): nose u 0, front axle u 0.994, rear 3.957, tail 5.057; tyres r 0.3735 (the rear's bottom
# 6 mm up); half width 1.0158 over the front arch lips. Calibration knobs
FIELD = dict(
    width=1.999,                   # without mirrors (the arch lips are the widest)
    mirror=2.271,                  # with them: the mirror (FIELD mirror_obj) moved out onto it
    # tyres (radius, width) and the track at the wheel centres per axle
    tyre=dict(f=(0.3733, 0.265, 1.705), r=(0.3778, 0.275, 1.710)),
    # faces recoloured: the inside of the wheel arches (the source's wheel wells in Car_Paint: official black)
    arch_inner=dict(obj="Car Body", mat="Car Paint", to="Black Car Paint", rho=0.66, below=0.15, inward=-0.25, az=0.55,
                    out=0.5, wall=0.85),
    # the mirror cut out of the front doors (its own object: cars/model_x.py SIDE_PARTS / SHELL_OBJS, no slab inner
    # copy), its back round the glass and the arm black (official REAR34)
    mirror_obj=dict(obj="Front Door", name="Mirror_X", u=(1.56, 1.86), h=1.03, az=0.932, back=-0.45, out=(0.95, 1.02),
                    arm_h=1.085, to="Black Car Paint"),
    # displacement terms: d (back, up[, out]) x win(u) x win(h) x win(az) (win: see win()). Same-camera numbers in px
    # (official SIDE, near side ~4 mm / px; + = the model right / low) before -> the term's d
    terms=(
        dict(d=(0, -0.022), u=(-1, -0.5, 1.70, 2.10), h=(0.86, 0.95, 1.20, 1.40)),   # hood: top -5..-7 px
        dict(d=(0, -0.035), u=(-1, -0.5, 0.40, 0.80), h=(0.60, 0.86), az=(0.80, 0.60)),   # nose top: -9..-16 px
        dict(d=(0, 0.0195), u=(2.65, 3.05, 4.30, 4.70), h=(1.30, 1.45)),            # roof: +3..+6 px
        dict(d=(0, 0.030), u=(3.85, 4.25, 5.2, 5.3), h=(1.15, 1.30), az=(0.68, 0.45)),   # rear roof: +10..+12 px
        dict(d=(0, -0.024), u=(1.55, 1.85, 3.20, 3.85), h=(1.02, 1.07, 1.10, 1.30)),   # belt: -5..-7 px
        dict(d=(0, -0.026), u=(1.30, 1.55, 3.55, 3.75), h=(0.32, 0.22)),           # skirt bottom: -4..-5 px
        # the floor under the cabin (inboard of the sills, which the SIDE outline shows right): ground clearance 169.4
        # -> the manual's 166
        dict(d=(0, -0.0036), h=(0.26, 0.20), az=(0.80, 0.70)),
        dict(d=(-0.020, 0), u=(1.30, 1.53, 1.53, 1.78), h=(0.40, 0.55)),           # front door's front seam +5 px
        dict(d=(-0.026, 0), u=(2.35, 2.75, 2.75, 3.15)),                          # B seam +6..+7 px
        dict(d=(-0.020, 0), u=(3.70, 3.98, 3.98, 4.25), h=(0.62, 0.75)),           # falcon rear seam +3..+6 px
        # the rear's plan boxier, rising monotonic out to the corners (official SIDE tail -24..-29 px, lamps -14..-15;
        # REAR34 -28..-30): du over az, the bumper's full, the lamps' 0.55 of it (complementary h windows)
        dict(prof=((0, 0), (0.12, 0), (0.2, 0.012), (0.4, 0.04), (0.6, 0.08), (0.7, 0.11), (0.8, 0.15), (0.92, 0.17), (1.1, 0.17)),
             axis="az", u=(4.50, 4.85), h=(0.10, 0.22, 0.72, 0.88)),
        dict(prof=((0, 0), (0.12, 0), (0.2, 0.007), (0.4, 0.022), (0.6, 0.044), (0.7, 0.06), (0.8, 0.082), (0.92, 0.094),
                   (1.1, 0.094)), axis="az", u=(4.50, 4.85), h=(0.72, 0.88, 1.15, 1.25)),
        # the nose under the lid's lip forward (official SIDE nose @y520 +7 px; the frunk jamb under the lip stood 14 mm
        # out of it)
        dict(d=(-0.022, 0), u=(-1, -0.5, 0.25, 0.45), h=(0.56, 0.66, 0.705, 0.732), az=(0.75, 0.55)),
        # the nose's profile (official SIDE: the lid's front edge back over the band below it, which stands out most)
        dict(prof=((0.69, 0), (0.716, -0.016), (0.756, -0.032), (0.776, 0), (0.796, 0.024), (0.836, 0.052),
                   (0.876, 0.012), (0.90, 0)), u=(-1, -0.5, 0.15, 0.35), az=(0.70, 0.40)),
        # the chin's underside up (official SIDE: x 410-440 its bottom 4-6 px higher, the lip undercut at h 0.2)
        dict(d=(0, 0.02), u=(-1, -0.5, 0.30, 0.45), h=(0.26, 0.17)),
        # the front door's handle 4.5 cm longer forward (official SIDE: the handle strip's front end -12 px)
        dict(d=(-0.045, 0), u=(2.30, 2.52, 2.56, 2.73), h=(0.93, 0.97, 1.04, 1.07), az=(0.82, 0.86)),
        # the axles onto the manual's overhang and wheelbase (988 / 2,965; the source's 994 / 2,963), each with its arch
        dict(d=(-0.0062, 0), u=(0.30, 0.70, 1.30, 1.70)),
        dict(d=(-0.0041, 0), u=(3.30, 3.60, 4.30, 4.60)),
        # the chin (official SIDE: the white fascia runs down to h 0.29 then a black splitter; the source's rounds off
        # from 0.36 into a receding black chin: nose @y640 +20 px, bottom @x400 -14 px)
        dict(d=(-0.08, 0), u=(-1, -0.5, 0.25, 0.55), h=(0.18, 0.26, 0.30, 0.40), az=(0.45, 0.70)),
        dict(d=(0, -0.05), u=(-1, -0.5, 0.30, 0.60), h=(0.20, 0.36, 0.36, 0.50)),
        dict(d=(0, -0.04), u=(-1, -0.5, 0.30, 0.60), h=(0.30, 0.20), az=(0.55, 0.40)),
        # round 2 (new cameras): the nose's lower front forward (official SIDE nose @y640 +7 px) and the chin's lip up
        # (its bottom @x430-450 +4..+5 px, the lip @y650 23 px ahead of the official's sloping bottom)
        dict(d=(-0.026, 0), u=(-1, -0.5, 0.10, 0.20), h=(0.20, 0.225, 0.25, 0.28)),
        dict(d=(0, 0.018), u=(0.10, 0.18, 0.26, 0.33), h=(0.24, 0.205)),
        # the roof's rear end up (official SIDE roof @x1400 / x1480 +4 px, the tail top @x1520 +3)
        dict(d=(0, 0.018), u=(4.10, 4.30, 4.45, 4.62), h=(1.12, 1.24)),
    ),
    # faces recoloured by box (source frame, before the field): obj, mat -> to; u, h, az windows (lo, hi).
    # The tail lamps body colour, lens and housing (the source's lamp sat 5-16 px low and had another shape: official
    # REAR34 / SIDE); the lamps are FIELD decals Tail*_X
    recolour=(*(dict(obj=o, mat=m, to="Car Paint", u=(4.5, 9), h=(0.80, 1.11), az=(0.38, 0.95))
                for o in ("Car Body", "Trunk") for m in ("Red Light Glass", "Black Car Paint")),
              # the pre-2021 fog lamp pockets in the front bumper's corners body colour (official FRONT34: smooth,
              # with the air curtain slot above: FIELD decals Slot_X)
              *(dict(obj="Car Body", mat=m, to="Car Paint", u=(-1, 0.45), h=(0.34, 0.64), az=(0.58, 0.95))
                for m in ("Black Car Paint", "Light", "Light Glass")),
              # the headlamps body colour: the source's lens (its lamp 7 cm longer, 1 cm higher than the official's,
              # SIDE + FRONT34 triangulated) and the black round it; the lamps are FIELD decals Lens_X / LensSide_X
              dict(obj="Car Body", mat="Light Glass Simple", to="Car Paint", u=(-1, 0.8), h=(0.6, 1.0)),
              dict(obj="Car Body", mat="Black Car Paint", to="Car Paint", u=(0.1, 0.7), h=(0.74, 0.93), az=(0.45, 0.95)),
              # the front arch lip's lower front corner body colour (official SIDE: white down to y 635 at x 450, a
              # thin lip; the source's black ran 20 px ahead of the arch there)
              dict(obj="Car Body", mat="Black Car Paint", to="Car Paint", u=(0.30, 0.555), h=(0.26, 0.45), az=(0.60, 9)),
              # the nose cone's trim body colour but the T (FIELD decals Band_X)
              dict(obj="Car Body", mat="Aluminum", to="Car Paint", u=(-1, 0.6), h=(0.6, 0.85), az=(0.06, 1.0))),
    # the raised spoiler (spoiler(); official SIDE / REAR34 triangulated: tips u 4.90 h 1.29 |z| 0.61, blade over the
    # tailgate's rear edge ~0.2 m chord, legs near the tips)
    spoiler=dict(span=0.61, te=(4.89, 0.09), chord=0.17, top=(1.305, -0.012), thick=0.014, n=24, leg=0.52,
                 leg_u=(0.30, 0.75), leg_w=0.03, sink=0.02,
                 # round 2 (official REAR34 from below: a dark underside 15 px under the blade): the leading edge
                 # `rake` lower than the trailing, the underside black; optional: the last `tip` of the span curled
                 # down by `droop` (tried 0.12 / 0.05: the near tip read as a white wedge, official SIDE straight)
                 rake=0.035),
    # the frunk lid's lip below h[0] eased back (u: near the nose): the convert's frunk jamb hangs straight down from the
    # lid's edge and stood 11 mm out of the nose under it (seals analyze.py)
    lid_lip=dict(obj="Bonnet", d=0.030, h=(0.82, 0.76), u=(0.35, 0.20)),
    # the lower black trim (sills, arch lips, the bumpers' lower parts: source Black Car Paint under h) dark grey (official
    # SIDE: sills 30-37 grading to 17-27, arch lips 45-67, rear bumper 43-49 against the build's flat 22): the faces
    # black before arch_inner (its wheel wells stay black) and still black after `recolour`
    trim_grey=dict(objs=("Car Body", "Front Door", "Back Door", "Trunk"), mat="Black Car Paint", to="Trim Grey", h=0.75),
    # the fitted official cameras (temp/skf_mx/work/camfit/cams.json: R world -> OpenCV, C, f, w, h in the scene's grid
    # frame; anchor: the front wheel centre y and the ground there) for FIELD decals. FRONT34 / REAR34 refit
    # 2026-11-12 (round 2) with their height held at SIDE's (fit.py HOLD: one studio rig): FRONT34 had sat 20 cm lower,
    # IoU 0.9421 -> 0.9682
    cams=dict(
        SIDE=dict(R=((-0.0614609, -0.9980892, 0.0063593), (-0.0737313, -0.0018138, -0.9972765),
                     (0.9953825, -0.0617624, -0.0734789)), C=(-5.568395, 0.311058, 0.128667), f=1464.931, w=1920, h=1080),
        FRONT34=dict(R=((-0.6395837, -0.7687143, 0.0033001), (-0.0445775, 0.0328027, -0.9984672),
                        (0.7674278, -0.6387505, -0.0552474)), C=(-5.011238, 4.428743, 0.128402), f=1913.128, w=1920,
                     h=1080),
        REAR34=dict(R=((0.7066468, -0.7074291, -0.0139408), (-0.0434781, -0.0237479, -0.9987721),
                       (0.7062294, 0.7063852, -0.0475391)), C=(-5.159372, -5.496818, 0.128159), f=2126.391, w=1920,
                    h=1080)),
    anchor=(1.261078, -0.768273),
    # decals: name, the view and its outline (px), the objects they lie on, material, offset (m)
    decals=(
        # the fender camera (2021+, both sides; official SIDE x 655-693 y 479-494)
        dict(name="Cam_X", view="SIDE", mat="Cam_Black", on=("Car Body",), off=0.003,
             outline=((655, 480), (692.5, 479.5), (690, 483.5), (683, 487.5), (668, 494.5), (663, 494), (656, 485))),
        # the air curtain slot in the front bumper's corners (official FRONT34)
        dict(name="Slot_X", view="FRONT34", mat="Slot_Black", on=("Car Body",), off=0.003,
             outline=((590, 614), (610, 604), (645, 597.5), (696, 595), (695, 601), (691, 611), (645, 613), (600, 616))),
        # its side end: the dark red side marker (official SIDE)
        dict(name="Marker_X", view="SIDE", mat="Marker_Red", on=("Car Body",), off=0.005,
             outline=((396, 562.5), (425.5, 560.5), (425, 573.5), (385, 575.5))),
        # the nose cone's black band round the chrome T (official FRONT34; the source's wider band body colour)
        dict(name="Band_X", view="FRONT34", mat="Band_Black", on=("Car Body",), off=0.002, skip=("Aluminum",),
             outline=((428, 526), (440, 524.5), (470, 525), (500, 528), (520, 533), (535, 539), (542, 543.5),
                      (520, 542.5), (500, 541), (480, 542), (474, 548), (468, 557), (463, 550), (456, 542),
                      (445, 538), (432, 534), (428, 531))),
        # the headlamps' smoked lens (official FRONT34, SIDE)
        dict(name="Lens_X", view="FRONT34", compete=("SIDE",), mat="Lamp_Lens", on=("Car Body",), off=0.008, u=(0.1, 0.75),
             outline=((574, 527), (600, 516), (650, 506), (700, 497), (738, 494), (745, 496), (740, 500), (730, 510),
                      (700, 522), (650, 530), (600, 531), (580, 528.5))),
        dict(name="LensSide_X", view="SIDE", compete=("FRONT34",), mat="Lamp_Lens", on=("Car Body",), off=0.008, u=(0.1, 0.75),
             outline=((400, 503), (404, 498), (420, 492), (440, 487), (460, 483), (471, 481), (466, 488), (455, 497),
                      (440, 504), (420, 507), (405, 508))),
        # the headlamps' daytime light strip along their lower edge (official FRONT34: a smoked lamp, a white strip
        # under it running up round its outer end)
        dict(name="Drl_X", view="FRONT34", compete=("SIDE",), mat="Lamp_DRL", on=("Car Body",), off=0.008, u=(0.1, 0.75),
             outline=((574, 525.5), (600, 533.5), (650, 534.5), (700, 526.5), (737, 509.5), (750, 497.5), (755, 500.5),
                      (742, 515), (702, 532), (650, 540), (600, 539), (573, 530))),
        # its front end from the side: a hook down the lamp's front and along under it (official SIDE)
        dict(name="DrlSide_X", view="SIDE", compete=("FRONT34",), mat="Lamp_DRL", on=("Car Body",), off=0.008, u=(0.0, 0.6),
             outline=((396, 503), (401, 502), (402, 510), (430, 509), (455, 505), (456, 508), (430, 513), (403, 516),
                      (398, 517), (396, 510))),
        # the tail lamps (official REAR34, SIDE; REAR34's on top, the SIDE's under it add what REAR34 does not reach; the SIDE's red guide
        # fell outside REAR34's housing: REAR34's alone):
        # the black housing (its upper corner's grey in REAR34 is a reflection:
        # dark in SIDE), the red C light guide
        # (lit: cars/model_x.py LAMPS) and the dim reflector bar; across the tailgate's seam (_T halves on the gate)
        dict(name="TailLamp_X", view="REAR34", mat="Lamp_Housing", on=("Car Body", "Trunk"), off=0.007, u=(4.3, 5.2), step=3.0,
             outline=((1129.2, 473.3), (1150, 458.3), (1170, 446.7), (1190, 437.5), (1206.7, 430), (1220, 425.8),
                      (1253.3, 424.2), (1286.7, 425), (1303.3, 428.3), (1311.7, 438.3), (1320, 453.3), (1324, 464),
                      (1278, 468.3), (1266.7, 478.3), (1261.7, 481.7), (1203.3, 481.7), (1153.3, 481.7),
                      (1135, 479.2))),
        dict(name="TailGuide_X", view="REAR34", mat="Tail_Guide", on=("Car Body", "Trunk"), off=0.010, u=(4.3, 5.2), step=3.0,
             outline=((1198.3, 460), (1201.7, 446.7), (1208.3, 434.2), (1220, 427.5), (1253.3, 426.7), (1300, 428.3),
                      (1309.2, 438.3), (1308.3, 442.5), (1300, 440), (1296.7, 436.7), (1253.3, 435), (1226.7, 435),
                      (1221.7, 440), (1220, 453.3), (1221.7, 455), (1318.3, 455), (1319.2, 463.3), (1200, 464.2))),
        dict(name="TailRefl_X", view="REAR34", mat="Lamp_Reflector", on=("Car Body", "Trunk"), off=0.010,
             u=(4.3, 5.2), outline=((1143, 466.5), (1186, 464), (1186, 470.5), (1143, 471))),
        dict(name="TailLampS_X", view="SIDE", mat="Lamp_Housing", on=("Car Body", "Trunk"), off=0.004, u=(4.3, 5.2),
             outline=((1456.3, 465.6), (1477.5, 450), (1496.3, 438.8), (1510, 430.6), (1515, 427.5), (1525, 426.9),
                      (1528.8, 430), (1530.6, 460), (1530, 471.3), (1515, 473.1), (1477.5, 471.9), (1460, 468.8))),
        dict(name="TailReflS_X", view="SIDE", mat="Lamp_Reflector", on=("Car Body", "Trunk"), off=0.006,
             u=(4.3, 5.2), outline=((1468.8, 458.1), (1503.8, 456.9), (1503.8, 463.1), (1468.8, 463.1))),
        # the front bumper camera (2025+, official FRONT34): a grey ring on the lower grille's middle (as a decal on
        # the bumper: convert.py CAMERA's flat ring stood 16 mm off it); on the model's centre line (x 463: at the official's 478
        # its mirror copy stood 24 px apart)
        dict(name="CamRing_X", view="FRONT34", mat="badge_cam", on=("Car Body",), off=0.006, step=1.0,
             outline=tuple((463 + 5.0 * np.cos(t), 638 + 4.0 * np.sin(t)) for t in np.linspace(0, 2 * np.pi, 16, endpoint=False)),
             holes=(tuple((463 + 3.0 * np.cos(t), 638 + 2.4 * np.sin(t)) for t in np.linspace(0, 2 * np.pi, 12, endpoint=False)),)),
        # the black band across the tailgate between the lamps (official REAR34 y 439-461; the source's trim 8 px)
        dict(name="GateBand_X", view="REAR34", mat="Band_Black", on=("Trunk",), off=0.004, u=(4.3, 5.2),
             outline=((1288, 441), (1330, 440), (1420, 440), (1450, 442), (1462, 445), (1462, 459), (1420, 461),
                      (1330, 461), (1288, 466))),
        # the lower grille across the front (official FRONT34; the mirror copy covers the other half)
        dict(name="Intake_X", view="FRONT34", mat="Intake_Black", on=("Car Body",), off=0.003, step=3.0,
             outline=((430, 622.5), (550, 632.5), (556, 635), (570, 652.5), (585, 670), (560, 666), (495, 665),
                      (450, 661), (430, 647.5))),
    ),
    # the wheel arches' openings: round the axle, towards it by d x k(angle from the top, deg: + rearward) x win(rho)
    arches=(
        dict(ax="r", d=0.064, rho=(0.40, 0.47, 0.58, 0.80), ang=((-180, 0.0), (-110, 0.0), (-90, 0.5), (0, 1.0),
                                                                    (90, 0.0), (180, 0.0)), az=(0.55, 0.65)),
        dict(ax="f", d=-0.012, rho=(0.40, 0.45, 0.55, 0.70), ang=((-180, 0.0), (-60, 0.0), (0, 1.0), (60, 0.0),
                                                                     (180, 0.0)), az=(0.55, 0.65)),   # top +3 px
    ),
)


def s(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def win(x, k):
    """weight over x: None 1; (a, b) up from a to b; (a, b, c, d) up a..b, down c..d (a > b: down)"""
    if k is None:
        return np.ones_like(x)
    if len(k) == 2:
        return s(x, *k)
    return s(x, k[0], k[1]) * (1 - s(x, k[2], k[3]))


class Field:
    """(u, h, az) metres -> (du back, dh up, daz out), on top of the width scale."""

    def __init__(self, ax):
        self.ax = ax                       # axle u, h per "f" / "r"

    def __call__(self, u, h, az):
        du, dh, da = np.zeros_like(u), np.zeros_like(u), np.zeros_like(u)
        for t in FIELD["terms"]:
            w = win(u, t.get("u")) * win(h, t.get("h")) * win(az, t.get("az"))
            if "prof" in t:                # du over h (or `axis` az) from a table (x, du)
                du += np.interp(az if t.get("axis") == "az" else h, *zip(*t["prof"])) * w
                continue
            d = t["d"]
            du, dh, da = du + d[0] * w, dh + d[1] * w, da + (d[2] if len(d) > 2 else 0) * w
        for a in FIELD["arches"]:
            x, y = u - self.ax[a["ax"]][0], h - self.ax[a["ax"]][1]
            rho = np.maximum(np.hypot(x, y), 1e-6)
            k = np.interp(np.degrees(np.arctan2(x, y)), *zip(*a["ang"])) * win(rho, a["rho"]) * win(az, a["az"])
            du, dh = du - a["d"] * k * x / rho, dh - a["d"] * k * y / rho
        return du, dh, da


def jac(fld, u, h, az, wk):
    """d(x', y', z')/d(x, y, z) per point in the (u, h, az) frame (u is minus x: the signs stay as the frame's)"""
    E = 1e-4
    J = np.zeros((len(u), 3, 3))
    for j, (a, b) in enumerate(((fld(u + E, h, az), fld(u - E, h, az)), (fld(u, h + E, az), fld(u, h - E, az)),
                                (fld(u, h, az + E), fld(u, h, az - E)))):
        for i in range(3):
            J[:, i, j] = (a[i] - b[i]) / (2 * E)
    J[:, 0, 0] += 1
    J[:, 1, 1] += 1
    J[:, 2, 2] += wk
    return J


def slot(me, name):
    """the material slot of `name` in me (added when missing)"""
    import bpy
    for i, m in enumerate(me.materials):
        if m.name == name:
            return i
    me.materials.append(bpy.data.materials.get(name) or bpy.data.materials.new(name))
    return len(me.materials) - 1


def slots(me, name):
    """every material slot holding `name`"""
    return [i for i, m in enumerate(me.materials) if m and m.name == name]


def face_frame(me, nose, yc):
    """per polygon: centre (u, h, az) in metres and the world normal"""
    c = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("center", c)
    n = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("normal", n)
    c, n = c.reshape(-1, 3), n.reshape(-1, 3)
    return (nose - c[:, 0]) * S, c[:, 2] * S, np.abs(c[:, 1] - yc) * S, n, np.sign(c[:, 1] - yc)


def split_mirror(bpy, meshes, nose, yc):
    """FIELD mirror_obj: the mirrors' faces out of the front doors into their own object, back and arm black."""
    mo = FIELD["mirror_obj"]
    o = next(o for o in meshes if o.name == mo["obj"])
    u, h, az, n, _ = face_frame(o.data, nose, yc)
    sel = (u > mo["u"][0]) & (u < mo["u"][1]) & (h > mo["h"]) & (az > mo["az"])
    co = np.array([v.co[:] for v in o.data.vertices])
    far = np.array([((nose - co[list(p.vertices), 0]) * S).max() > mo["u"][1] + 0.05 for p in o.data.polygons])
    sel &= ~far                                       # (not the long window frame triangles reaching past it)
    keep = set()
    for p, v in zip(o.data.polygons, sel):
        p.select = bool(v)
        if v:
            keep.update(p.vertices)
    for v in o.data.vertices:                         # only those faces' (edit mode flushes vertex selection up)
        v.select = v.index in keep
    for e in o.data.edges:
        e.select = all(i in keep for i in e.vertices)
    before = set(bpy.data.objects)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    m = next(iter(set(bpy.data.objects) - before))
    m.name = m.data.name = mo["name"]
    me = m.data
    u, h, az, n, _ = face_frame(me, nose, yc)
    paint, black = slots(me, "Car Paint"), slot(me, mo["to"])
    mi = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("material_index", mi)
    back = np.isin(mi, paint) & ((n[:, 0] < mo["back"]) | (h < mo["arm_h"]))
    mi[back] = black
    me.polygons.foreach_set("material_index", mi)
    me.update()
    print("PREP mirror: %d faces (%d black)" % (int(sel.sum()), int(back.sum())))
    return m


def recolour_arches(meshes, nose, yc, ax):
    """FIELD arch_inner: the wheel wells' paint faces black, round each axle (inside rho, above it less `below`): the
    well's roof (facing the axle, outboard of `az`) and its inboard wall (facing out, inboard of `wall`)."""
    a = FIELD["arch_inner"]
    o = next(o for o in meshes if o.name == a["obj"])
    me = o.data
    u, h, az, n, sg = face_frame(me, nose, yc)
    mi = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("material_index", mi)
    src, dst = slots(me, a["mat"]), slot(me, a["to"])
    hit = np.zeros(len(u), bool)
    out = n[:, 1] * sg                                        # the normal's outward part
    for u0, h0, _ in ax.values():
        x, y = u0 - u, h - h0                                 # (world x, z) off the axle: x = -u
        rho = np.maximum(np.hypot(x, y), 1e-9)
        inward = (n[:, 0] * x + n[:, 2] * y) / rho
        near = np.isin(mi, src) & (rho < a["rho"]) & (h > h0 - a["below"])
        hit |= near & (inward < a["inward"]) & (az > a["az"]) | near & (out > a["out"]) & (az < a["wall"])
    mi[hit] = dst
    me.polygons.foreach_set("material_index", mi)
    me.update()
    return int(hit.sum())


def spoiler(bpy, meshes, nose, yc):
    """FIELD spoiler: the raised active spoiler over the tailgate's rear (official SIDE / REAR34; the source has none),
    its own object riding the tailgate (cars/model_x.py PART_OBJS TrunkDoor, SHELL_OBJS): a blade, stations across
    span (te: trailing edge u + k (z / span)^2, chord, top: h + k (z / span)^2, thick), body colour all round (the
    official's underside reads body colour from the low studio cameras); two black legs at |z| `leg` down onto the tailgate (a ray down
    from under the blade, `sink` into it)."""
    import bmesh
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    sp = FIELD["spoiler"]
    gate = next(o for o in meshes if o.name == "Trunk")
    bvh = BVHTree.FromPolygons([v.co[:] for v in gate.data.vertices], [p.vertices[:] for p in gate.data.polygons])
    to_w = lambda u, h, z: Vector((nose - u / S, yc + z / S, h / S))                      # noqa: E731
    bm = bmesh.new()
    paint, black = 0, 1

    def box(c, mats):
        """8 corners (u, h, z): bottom 4 then top 4, in order round; mats per side (bottom, top, 4 sides)"""
        v = [bm.verts.new(to_w(*q)) for q in c]
        quads = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        for q, m in zip(quads, mats):
            bm.faces.new([v[i] for i in q]).material_index = m
    zs = sp["span"] * np.linspace(-1, 1, sp["n"] + 1)
    sec = []
    for z in zs:
        f = (z / sp["span"]) ** 2
        te, top = sp["te"][0] + sp["te"][1] * f, sp["top"][0] + sp["top"][1] * f
        top -= sp.get("droop", 0) * s(abs(z), sp["span"] - sp.get("tip", 0), sp["span"]) if sp.get("tip") else 0
        le, rk = te - sp["chord"], sp.get("rake", 0)
        sec.append([(le, top - sp["thick"] - rk, z), (te, top - sp["thick"] * 0.6, z), (te, top, z), (le + 0.02, top - rk, z)])
    rows = [[bm.verts.new(to_w(*q)) for q in s_] for s_ in sec]
    for a_, b_ in zip(rows[:-1], rows[1:]):             # sides: 0-1 bottom, 1-2 trailing,
        for i in range(4):                              # 2-3 top, 3-0 leading: all body colour
            j = (i + 1) % 4
            bm.faces.new([a_[i], b_[i], b_[j], a_[j]]).material_index = black if i == 0 and sp.get("rake") else paint
    for r_ in (rows[0], rows[-1]):
        bm.faces.new(r_).material_index = paint
    for zc_ in (-sp["leg"], sp["leg"]):
        f = (zc_ / sp["span"]) ** 2
        te, top = sp["te"][0] + sp["te"][1] * f, sp["top"][0] + sp["top"][1] * f
        top -= sp.get("droop", 0) * s(abs(zc_), sp["span"] - sp.get("tip", 0), sp["span"]) if sp.get("tip") else 0
        u0, u1 = te - sp["chord"] * sp["leg_u"][1], te - sp["chord"] * sp["leg_u"][0]
        # the blade's underside over each end of the leg (its section's bottom edge, le to te)
        under = [top - sp["thick"] - sp.get("rake", 0) + (sp["thick"] * 0.4 + sp.get("rake", 0)) * (u_ - te + sp["chord"])
                 / sp["chord"] for u_ in (u0, u1)]
        hb = min(under)
        foot = []
        for u_ in (u0, u1):
            hit = bvh.ray_cast(to_w(u_, hb, zc_), Vector((0, 0, -1)))[0]
            if hit is None:
                raise SystemExit(f"spoiler: no tailgate under u {u_:.3f} z {zc_:.3f}")
            foot.append(hit.z * S - sp["sink"])
        w = sp["leg_w"] / 2
        box([(u0, foot[0], zc_ - w), (u1, foot[1], zc_ - w), (u1, foot[1], zc_ + w), (u0, foot[0], zc_ + w),
             (u0, under[0] + 0.003, zc_ - w), (u1, under[1] + 0.003, zc_ - w), (u1, under[1] + 0.003, zc_ + w),
             (u0, under[0] + 0.003, zc_ + w)],
            [black] * 6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Spoiler_X")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(bpy.data.materials["Car Paint"])
    me.materials.append(bpy.data.materials["Black Car Paint"])
    o = bpy.data.objects.new("Spoiler_X", me)
    bpy.context.scene.collection.objects.link(o)
    print("PREP spoiler: %d faces" % len(me.polygons))
    return o


def inside(p, loops):
    """even-odd: points p (n, 2) inside the loops (an outline and its holes)"""
    k = np.zeros(len(p), bool)
    for lp in loops:
        a, b = lp, np.roll(lp, -1, 0)
        for (x0, y0), (x1, y1) in zip(a, b):
            c = (y0 > p[:, 1]) != (y1 > p[:, 1])
            k ^= c & (p[:, 0] < x0 + (p[:, 1] - y0) * (x1 - x0) / np.where(y1 == y0, 1e-9, y1 - y0))
    return k


def decal_mesh(loops, step):
    """A decal's flat mesh in pixels: the loops resampled every `step`, a `step` grid inside, constrained Delaunay;
    -> (points, triangles)"""
    from mathutils import Vector
    from mathutils.geometry import delaunay_2d_cdt
    pts, edges = [], []
    for lp in loops:
        ring = []
        for a, b in zip(lp, np.roll(lp, -1, 0)):
            n = max(1, int(np.ceil(np.linalg.norm(b - a) / step)))
            ring += [a + (b - a) * t for t in np.arange(n) / n]
        i0 = len(pts)
        pts += ring
        edges += [(i0 + i, i0 + (i + 1) % len(ring)) for i in range(len(ring))]
    lo, hi = loops[0].min(0), loops[0].max(0)
    g = np.stack(np.meshgrid(np.arange(lo[0] + step / 2, hi[0], step), np.arange(lo[1] + step / 2, hi[1], step)),
                 -1).reshape(-1, 2)
    g = g[inside(g, loops)]
    b = np.array(pts)                                 # (grid points off the outline by half a step)
    g = g[np.min(np.linalg.norm(g[:, None] - b[None], axis=2), 1) > step / 2] if len(g) else g
    allp = [Vector(p) for p in [*pts, *g]]
    V, _, F, *_ = delaunay_2d_cdt(allp, edges, [], 0, 1e-6)
    V = np.array([v[:] for v in V])
    F = [f for f in F if inside(V[list(f)].mean(0)[None], loops)[0]]
    return V, F


def decals(bpy, meshes, nose, yc, ftyre_x):
    """FIELD decals: the mod's own flat pieces drawn in an official view's pixels (outline, VIEW) and cast from that
    view's fitted camera (FIELD cams) onto the car as prepped (the `on` objects), `off` towards the camera; both sides
    (mirrored across the centre line). One object per decal, its material `mat` (cars/model_x.py MAT_RGB); the faces
    lying on a lid or door (`on` beyond the body: the tailgate's lamp halves) in an object `<name>_<that object's
    initial>` riding it (cars/model_x.py PART_OBJS / SHELL_OBJS). `holes`: loops cut out of the outline."""
    import bmesh
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    cams, (fy, gnd) = FIELD["cams"], FIELD["anchor"]
    dy = fy / K - S * (ftyre_x - SRC_C[0])            # the cams' frame: the front tyre centre and the ground on its anchor
    dz = gnd / K

    def world(g):                                     # scene grid -> world (source units)
        X, Y, Z = np.asarray(g) / K
        return Vector(((Y - dy) / S + SRC_C[0], SRC_C[1] - X / S, (Z - dz) / S))
    made = []
    hull = [o for o in meshes if not o.name.startswith(("Tyre", "Rim"))]   # every surface stops a ray
    k = np.cumsum([0] + [len(o.data.vertices) for o in hull])
    bvh = BVHTree.FromPolygons([v.co[:] for o in hull for v in o.data.vertices],
                               [[i + k0 for i in p.vertices] for o, k0 in zip(hull, k) for p in o.data.polygons])
    owner = np.repeat([o.name for o in hull], [len(o.data.polygons) for o in hull])
    pmat = np.array([o.data.materials[p.material_index].name if o.data.materials else "" for o in hull
                     for p in o.data.polygons])
    for dc in FIELD["decals"]:
        c = cams[dc["view"]]
        R, C = np.array(c["R"]), np.array(c["C"])
        eye = world(C)
        bm = bmesh.new()
        loops = [np.array(lp, float) for lp in (dc["outline"], *dc.get("holes", ()))]
        P, E = decal_mesh(loops, dc.get("step", 6.0))
        vs = [bm.verts.new((x, y, 0)) for x, y in P]
        for t in E:
            bm.faces.new([vs[i] for i in t])
        off, lay, nrm = [], {}, {}                    # vertices whose ray met nothing or another part first; owners
        others = [world(cams[w]["C"]) for w in dc.get("compete", ())]
        for v in bm.verts:
            d = R.T @ np.array([(v.co.x - c["w"] / 2) / c["f"], (v.co.y - c["h"] / 2) / c["f"], 1.0])
            ray = (world(C + d) - eye).normalized()
            hit, n, fi, _ = bvh.ray_cast(eye, ray)
            if hit is None:                           # past the car's outline
                off.append(v)
                continue
            if owner[fi] not in dc["on"] or pmat[fi] in dc.get("skip", ()) or not dc.get("u", (-9, 9))[0] < (nose - hit.x) * S < dc.get("u", (-9, 9))[1]:
                off.append(v)
            lay[v] = owner[fi]
            n = n if n.dot(ray) < 0 else -n                # off the surface along its normal (a ray-wise offset
            nrm[v] = n                                     # sank in where the view grazes it)
            v.co = hit + n * (dc["off"] / S)
        bmesh.ops.delete(bm, geom=off, context="VERTS")
        if others:      # compete: views also drawing this part; a face stays where its own view meets it squarest
            drop = []
            for f in bm.faces:
                n = sum((nrm[v] for v in f.verts), Vector()).normalized()
                p = f.calc_center_median()
                own = n.dot((eye - p).normalized())
                if any(n.dot((e - p).normalized()) > own for e in others):
                    drop.append(f)
            bmesh.ops.delete(bm, geom=drop, context="FACES")
        rider = {f: next((lay[v] for v in f.verts if lay[v] != dc["on"][0]), dc["on"][0]) for f in bm.faces}
        bm.normal_update()
        for f in bm.faces:                            # facing the camera
            if f.normal.dot(eye - f.calc_center_median()) < 0:
                f.normal_flip()
        for on in dc["on"]:
            part = bm.copy()
            bmesh.ops.delete(part, geom=[f for f, g in zip(part.faces, bm.faces) if rider[g] != on], context="FACES")
            if not part.faces:
                part.free()
                continue
            mir = bmesh.ops.duplicate(part, geom=part.verts[:] + part.edges[:] + part.faces[:])["geom"]
            for e in mir:
                if isinstance(e, bmesh.types.BMVert):
                    e.co.y = 2 * yc - e.co.y
            for f in [e for e in mir if isinstance(e, bmesh.types.BMFace)]:
                f.normal_flip()
            part.normal_update()
            name = dc["name"] if on == dc["on"][0] else "%s_%s" % (dc["name"], on[0])
            me = bpy.data.meshes.new(name)
            part.to_mesh(me)
            part.free()
            me.materials.append(bpy.data.materials.get(dc["mat"]) or bpy.data.materials.new(dc["mat"]))
            o = bpy.data.objects.new(name, me)
            bpy.context.scene.collection.objects.link(o)
            made.append(o)
            print("PREP decal %s: %d faces" % (name, len(me.polygons)))
        bm.free()
    return made


def main():
    import bmesh
    import bpy
    from mathutils import Matrix
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src, out = (args + [os.path.join(SRC_DIR, "sketchfab tesla.blend"), os.path.join(SRC_DIR, "model_x.obj")][len(args):])[:2]
    bpy.ops.wm.open_mainfile(filepath=src)
    for o in bpy.data.objects:
        for m in getattr(o, "modifiers", []):
            if m.type == "SUBSURF":
                m.levels = 0 if o.name.startswith(("Tyre", "Rim")) else 1
            if m.type == "MIRROR" and o.name == "Back Door":
                m.use_mirror_merge = False
    dg = bpy.context.evaluated_depsgraph_get()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        me = o.data = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        o.modifiers.clear()

    def tris(o):
        return sum(len(p.vertices) - 2 for p in o.data.polygons)

    for o in meshes:
        if o.name not in TARGET:
            continue
        bpy.context.view_layer.objects.active = o
        for _ in range(3):                      # the ratio is on triangles: repeat until within 3 %
            n = tris(o)
            if n <= TARGET[o.name] * 1.03:
                break
            bm = bmesh.new()
            bm.from_mesh(o.data)
            held = {v.index for e in bm.edges if len(e.link_faces) != 2
                    or e.link_faces[0].material_index != e.link_faces[1].material_index for v in e.verts}
            bm.free()
            if "interior" in o.vertex_groups:
                o.vertex_groups.remove(o.vertex_groups["interior"])
            o.vertex_groups.new(name="interior").add([i for i in range(len(o.data.vertices)) if i not in held], 1.0,
                                                     "REPLACE")
            m = o.modifiers.new("dec", "DECIMATE")
            m.decimate_type, m.ratio = "COLLAPSE", TARGET[o.name] / n
            m.use_symmetry, m.symmetry_axis = True, "Y"          # the source's mirror plane is local y 0
            m.vertex_group, m.vertex_group_factor = "interior", 1000.0
            bpy.ops.object.modifier_apply(modifier=m.name)
        print("PREP decimated", o.name, tris(o), "tris")
    # world frame from here on: every transform into the vertices, the ground at z 0
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix()
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    ground = min(min(v.co.z for v in o.data.vertices) for o in meshes if o.name.startswith("Tyre"))
    for o in meshes:
        o.data.transform(Matrix.Translation((0, 0, -ground)))
    pts = lambda o: np.array([v.co[:] for v in o.data.vertices])   # noqa: E731
    body = pts(next(o for o in meshes if o.name == "Car Body"))
    yc = (body[:, 1].min() + body[:, 1].max()) / 2                  # the mirror plane
    for o in meshes:
        if o.name in CENTRED:
            c = pts(o)
            o.data.transform(Matrix.Translation((0, yc - (c[:, 1].min() + c[:, 1].max()) / 2, 0)))
    nose = max(pts(o)[:, 0].max() for o in meshes if not o.name.startswith(("Tyre", "Rim")))
    tyre = {k: np.concatenate([c for c in (pts(o) for o in meshes if o.name.startswith("Tyre"))
                               if (c[:, 0].mean() > nose / 2) == f]) for k, f in (("f", True), ("r", False))}
    ax = {k: ((nose - (t[:, 0].min() + t[:, 0].max()) / 2) * S, (t[:, 2].min() + t[:, 2].max()) / 2 * S,
              np.ptp(t[:, 2]) / 2 * S) for k, t in tyre.items()}
    meshes.append(split_mirror(bpy, meshes, nose, yc))
    tg, grey = FIELD["trim_grey"], {}
    for o in (o for o in meshes if o.name in tg["objs"]):     # the source's own black trim low down
        u, h, az, _, _ = face_frame(o.data, nose, yc)
        mi = np.empty(len(o.data.polygons), np.int64)
        o.data.polygons.foreach_get("material_index", mi)
        grey[o.name] = np.isin(mi, slots(o.data, tg["mat"])) & (h < tg["h"])
    narch = recolour_arches(meshes, nose, yc, ax)
    for r in FIELD["recolour"]:
        o = next(o for o in meshes if o.name == r["obj"])
        u, h, az, _, _ = face_frame(o.data, nose, yc)
        mi = np.empty(len(o.data.polygons), np.int64)
        o.data.polygons.foreach_get("material_index", mi)
        a_ = r.get("az", (-1, 9))
        k = np.isin(mi, slots(o.data, r["mat"])) & (u > r["u"][0]) & (u < r["u"][1]) & (h > r["h"][0]) & \
            (h < r["h"][1]) & (az > a_[0]) & (az < a_[1])
        mi[k] = slot(o.data, r["to"])
        o.data.polygons.foreach_set("material_index", mi)
        print("PREP recolour %s %s -> %s: %d faces" % (r["obj"], r["mat"], r["to"], int(k.sum())))
    for o in (o for o in meshes if o.name in grey):   # (not what the recolours above turned body colour)
        mi = np.empty(len(o.data.polygons), np.int64)
        o.data.polygons.foreach_get("material_index", mi)
        k = grey[o.name] & np.isin(mi, slots(o.data, tg["mat"]))
        mi[k] = slot(o.data, tg["to"])
        o.data.polygons.foreach_set("material_index", mi)
        print("PREP trim grey %s: %d faces" % (o.name, int(k.sum())))
    lip = FIELD["lid_lip"]                            # the frunk lid's lower lip back off the nose (its own move)
    o = next(o for o in meshes if o.name == lip["obj"])
    p = pts(o)
    du = lip["d"] * s(p[:, 2] * S, *lip["h"]) * s((nose - p[:, 0]) * S, *lip["u"])
    o.data.vertices.foreach_set("co", (p - np.outer(du / S, (1, 0, 0))).ravel())
    fld = Field(ax)
    wk = FIELD["width"] / (2 * S * max(np.abs(pts(o)[:, 1] - yc).max() for o in meshes
                                       if not o.name.startswith(("Tyre", "Rim", "Mirror_X"))))
    for o in meshes:
        me, p = o.data, pts(o)
        cn = np.empty(len(me.loops) * 3, np.float32)             # the corner normals before the move
        me.corner_normals.foreach_get("vector", cn)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        u, h, az = (nose - p[:, 0]) * S, p[:, 2] * S, np.abs(p[:, 1] - yc) * S
        sg = np.where(p[:, 1] >= yc, 1.0, -1.0)
        if o.name.startswith(("Tyre", "Rim")):          # whole with their axle: the official tyre round its centre
            k = "f" if u.mean() < 2.5 else "r"
            r, w, track = FIELD["tyre"][k]
            u0, h0, r0 = ax[k]
            du0 = fld(np.array([u0]), np.array([h0]), np.array([0.0]))[0][0]
            tz = np.abs(pts(next(t for t in meshes if t.name.startswith("Tyre") and
                                 (np.sign(pts(t)[:, 1].mean() - yc) == sg[0]) and ((nose - pts(t)[:, 0].mean()) * S < 2.5) == (k == "f")))[:, 1] - yc) * S
            side, fz = (tz.min() + tz.max()) / 2, w / np.ptp(tz)
            f = r / r0
            uu, hh, aa = u0 + du0 + (u - u0) * f, r + (h - h0) * f, track / 2 + (az - side) * fz
            J = np.zeros((len(p), 3, 3))
            J[:, 0, 0] = J[:, 1, 1] = f
            J[:, 2, 2] = fz
        else:
            du, dh, da = fld(u, h, az)
            J = jac(fld, u, h, az, wk)
            uu, hh, aa = u + du, h + dh, az * wk + da
            if o.name == "Mirror_X":                     # the cap out onto the width with mirrors (the base stays)
                aa = aa + (FIELD["mirror"] / 2 - aa.max()) * s(az, *FIELD["mirror_obj"]["out"])
        q = np.stack([nose - uu / S, yc + sg * aa / S, hh / S], 1)
        # world Jacobian: (x', y', z') = P (u', h', az'), (u, h, az) = Q (x, y, z)
        P = np.zeros((len(p), 3, 3))
        P[:, 0, 0], P[:, 1, 2], P[:, 2, 1] = -1, sg, 1
        Q = np.zeros((len(p), 3, 3))
        Q[:, 0, 0], Q[:, 1, 2], Q[:, 2, 1] = -1, 1, sg
        Jw = P @ J @ Q
        me.vertices.foreach_set("co", q.ravel())
        n = np.einsum("lij,li->lj", np.linalg.inv(Jw)[lv], cn.reshape(-1, 3))   # n' = J^-T n (row vector n J^-1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", n.astype(np.float32).ravel())
        me.update()
    meshes.append(spoiler(bpy, meshes, nose, yc))
    ftyre = next(o for o in meshes if o.name.startswith("Tyre") and (nose - pts(o)[:, 0].mean()) * S < 2.5)
    fx = pts(ftyre)[:, 0]
    meshes += decals(bpy, meshes, nose, yc, (fx.min() + fx.max()) / 2)
    print("PREP width x %.5f, axles u %.4f / %.4f h %.4f / %.4f r %.4f / %.4f, doors centred on y %.4f, arch faces %d"
          % (wk, ax["f"][0], ax["r"][0], ax["f"][1], ax["r"][1], ax["f"][2], ax["r"][2], yc, narch))
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.ops.wm.obj_export(filepath=out, export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y",
                          export_uv=False, export_normals=True, export_materials=True, apply_modifiers=True,
                          export_triangulated_mesh=False)
    print("PREP ground", ground, "->", out)


if __name__ == "__main__":
    main()
