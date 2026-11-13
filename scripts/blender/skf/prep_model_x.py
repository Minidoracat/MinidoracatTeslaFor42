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
        # (its bottom @x430-450 +4..+5 px); round 3: kept (without them FRONT34 IoU 0.9687 -> 0.9679), the rest of
        # the bumper is FIELD fascia's
        dict(d=(-0.026, 0), u=(-1, -0.5, 0.10, 0.20), h=(0.20, 0.225, 0.25, 0.28)),
        dict(d=(0, 0.018), u=(0.10, 0.18, 0.26, 0.33), h=(0.24, 0.205)),
        # the roof's rear end up (official SIDE roof @x1400 / x1480 +4 / +5 px, the tail top @x1520 +3): round 4, behind
        # u 4.28 (an earlier one from u 4.10 lifted the roof ahead of it, @x1300 -3 -> -4) and back to the spoiler's legs
        # (a lift under them left the legs' rays starting inside the tailgate: the prep crashed); the spoiler `top` +12 mm
        dict(d=(0, 0.023), u=(4.28, 4.50, 4.78, 4.95), h=(1.10, 1.24)),
        # round 7 (cameras refit, below): the three official cameras now agree on the side (two-view triangulations of
        # the fender camera, door handles and tail lamp tip within 1.4 cm of each other); against them the model's
        # fender at the side camera stood 2.9-3.5 cm out, the tail lamp's front tip 4.6 cm in (round 6's -5 cm "tail's
        # sides in" came from the old REAR34: gone) and both rear corners 4-5 cm out (REAR34's far outline +10..+17
        # px, FRONT34's near one +2..+8). The tail's plan rounder from behind the lamps' front tip (u 4.5) back, a
        # ramp over az (no step: round 6's 6 cm local pull dented the quarter); the fender in behind the front arch
        # (above the lip: the 1,999 width is the lip's; under the A-pillar foot, whose crack plates stay put: up to h
        # 1.10 it opened fl SE 0 -> 3 px; ending at u 1.65, ahead of the front door's seam, cost that seam NW 59 -> 46
        # %); the bumper's side ahead of the front arch in (FRONT34's arch band at 175-220 deg -11..-5 -> -2..+3 px:
        # the bumper bulged over the arch moulding's front)
        dict(d=(0, 0, -0.03), u=(4.50, 4.95), h=(0.20, 0.35, 1.20, 1.40), az=(0.35, 0.95)),
        dict(d=(0, 0, -0.03), u=(1.05, 1.25, 1.55, 1.85), h=(0.60, 0.72, 0.92, 1.00), az=(0.60, 0.85)),
        dict(d=(0, 0, -0.04), u=(0.30, 0.45, 0.60, 0.70), h=(0.22, 0.32, 0.70, 0.80), az=(0.70, 0.90)),
        # round 11: the rear roof's middle down (a/silpt.py: per column the official's top outline against ours and
        # what our outline ray touches). REAR34 saw the middle at u 3.4-3.9 4-5 px high, the shoulders (az 0.57-0.59)
        # at u 3.9-4.6 6-10 px and FRONT34 the shoulders (az 0.6) at u 4.0-4.5 4-8 px, while SIDE's outline is the near
        # shoulder (az 0.51-0.61) and was right (-1..+2): the whole rear roof down 2.5 cm put SIDE at +5..+8 px. Down
        # to the tailgate (u 4.70) with the shoulders too it fitted all three (REAR34 -4..-6, SIDE <= +3) but opened the
        # cargo bay's side wall (the tailgate open N / W 0 -> 50 px, through the quarter glass) and, ending before the
        # tailgate's front edge with the shoulders still down, the roof / falcon door / tailgate corner (SE 1 -> 75): the
        # middle only, ending ahead of the tailgate. The roof's top (the manual's 1,680.6 at u 3.03) stays
        dict(d=(0, -0.025), u=(3.15, 3.55, 3.65, 3.85), h=(1.30, 1.40), az=(0.60, 0.45)),
        # round 11: the nose's corners forward (a/nosesec.py: per image row the outline's nose end, official against
        # ours, across the ray at that depth; SIDE the near corner, FRONT34 the far one, both az 0.4-0.6): the bumper's
        # middle (h 0.44-0.55: SIDE +1.8..+2.9, FRONT34 +1.5..+3.5 cm, ours inside) and the splitter's corners (h
        # 0.22-0.28: SIDE +3.2..+3.8, FRONT34 +2.4..+5.7 cm) -> -3..+2 / -2..+6 px. Not the lamps' height (h 0.74:
        # +2.2..+3.1 cm, under the lid's lip) nor the far fender's top (h 0.94-1.05, FRONT34 only, +5..+8 cm: SIDE sees
        # that side's lip right). The fascia's P-spline spreads a term ~4 cm up: the windows end low
        dict(d=(-0.02, 0), u=(-1, -0.5, 0.25, 0.40), h=(0.36, 0.42, 0.47, 0.53), az=(0.30, 0.42, 0.62, 0.75)),
        dict(d=(-0.035, 0), u=(-1, -0.5, 0.25, 0.40), h=(0.18, 0.21, 0.26, 0.30), az=(0.10, 0.25, 0.62, 0.75)),
    ),
    # faces recoloured by box (source frame, before the field): obj, mat -> to; u, h, az windows (lo, hi).
    # The tail lamps body colour, lens and housing (the source's lamp sat 5-16 px low and had another shape: official
    # REAR34 / SIDE); the lamps are FIELD decals Tail*_X
    recolour=(*(dict(obj=o, mat=m, to="Car Paint", u=(4.5, 9), h=(0.80, 1.11), az=(0.38, 0.95))
                for o in ("Car Body", "Trunk") for m in ("Red Light Glass", "Black Car Paint")),
              # the rear bumper's reflectors trim grey (round 6: they sat 10 px right and 5 px over the official's
              # thin slits, REAR34; FIELD decals BumpRefl_X)
              dict(obj="Car Body", mat="Red Light Glass", to="Trim Grey", u=(4.8, 9), h=(0.35, 0.65)),
              # the pre-2021 fog lamp pockets in the front bumper's corners body colour (official FRONT34: smooth,
              # with the air curtain slot above: FIELD decals Slot_X)
              *(dict(obj="Car Body", mat=m, to="Car Paint", u=(-1, 0.45), h=(0.34, 0.64), az=(0.58, 0.95), fill=True)
                for m in ("Black Car Paint", "Light", "Light Glass")),
              # the headlamps body colour: the source's lens (its lamp 7 cm longer, 1 cm higher than the official's,
              # SIDE + FRONT34 triangulated) and the black round it; the lamps are FIELD decals Lens_X / LensSide_X
              dict(obj="Car Body", mat="Light Glass Simple", to="Car Paint", u=(-1, 0.8), h=(0.6, 1.0)),
              dict(obj="Car Body", mat="Black Car Paint", to="Car Paint", u=(0.1, 0.7), h=(0.74, 0.93), az=(0.45, 0.95)),
              # the nose cone's trim body colour, the T too (round 8: cars/model_x.py T_BADGE; FIELD decals Band_X)
              dict(obj="Car Body", mat="Aluminum", to="Car Paint", u=(-1, 0.6), h=(0.6, 0.85)),
              # round 9: the chin's front body colour under the grille (official FRONT34: a white lip 12-15 px tall
              # between the grille and the dark splitter; the splitter's top is cars/model_x.py CARBON's)
              dict(obj="Car Body", mat="Black Car Paint", to="Car Paint", u=(-1, 0.35), h=(0.16, 0.33), az=(-1, 0.60))),
    # the raised spoiler (spoiler(); official SIDE / REAR34 triangulated: tips u 4.90 h 1.29 |z| 0.61, blade over the
    # tailgate's rear edge ~0.2 m chord, legs near the tips)
    spoiler=dict(span=0.61, te=(4.89, 0.09), chord=0.17, top=(1.317, -0.012), thick=0.014, n=24, leg=0.52,
                 leg_u=(0.30, 0.75), leg_w=0.03, sink=0.02,
                 # round 2 (official REAR34 from below: a dark underside 15 px under the blade): the leading edge
                 # `rake` lower than the trailing, the underside black; optional: the last `tip` of the span curled
                 # down by `droop` (tried 0.12 / 0.05: the near tip read as a white wedge, official SIDE straight)
                 rake=0.035,
                 # round 9: the legs body colour (0; black 1 drew a 2 x 5 px black block under each tip from behind
                 # and a black arrowhead from the side in the game: GameMX NW / W / N, 824bf64)
                 leg_mat=0),
    # the frunk lid's lip below h[0] eased back (u: near the nose): the convert's frunk jamb hangs straight down from the
    # lid's edge and stood 11 mm out of the nose under it (seals analyze.py)
    lid_lip=dict(obj="Bonnet", d=0.030, h=(0.82, 0.76), u=(0.35, 0.20)),
    # the front bumper / nose one smooth surface (fascia(): the source's pre-2021 fog lamp pockets filled, the
    # decimation's and the field's lumps gone; official FRONT34 / SIDE smooth)
    fascia=dict(obj="Car Body", axis=1.0, u=(-1, -0.5, 0.45, 0.62), h=(0.20, 0.26, 0.72, 0.80), facing=0.3, grow=2,
                knots=(26, 14), lam=0.05, cap=0.15, carry=("Aluminum", "Black Car Paint", "Trim Grey"), align=0.5,
                step=0.012, seam=0.04, weld=0.008, fill=4,
                # (the nose's tip not ahead of where it was: the manual's length)
                tip=0.0),
    # round 8 (fair()): the nose's upper band (the pre-2021 nose cone and its T, recoloured above) and the headlamps'
    # surrounds (their recoloured lens and pockets) faired: crumpled facets and dark specks in the studio light (same
    # camera FRONT34) and the game's sheen. Not the panels more than `under` m below the lid, nor black / grey trim not
    # seen from outside; the lamps' insides left under the lid's edge dropped; nothing in the nose's middle (|az| <
    # `ahead_az`) more than `ahead` m forward (unclamped it bulged 14 px past the official SIDE outline; round 9: 0.40 -> 0.75,
    # at 0.44 m out the band's far end stood 3 cm ahead, a spike past the official FRONT34 outline). Round 9: nor what
    # lies `jamb` m or more under the lid and is seen from nowhere with it shut (the opening's sides: faired, they met
    # the convert's frunk jamb, a white / black comb with the lid open: GameMX2, 6acfe7e S / SE / E)
    fair=(dict(obj="Car Body", lid="Bonnet", under=0.06, jamb=0.003, ahead=0.005, ahead_az=0.75,
               mats=("Car Paint", "Aluminum", "Light", "Light Glass", "Black Car Paint", "Trim Grey"),
               paint=("Light", "Light Glass", "Black Car Paint", "Trim Grey"), seen=("Black Car Paint", "Trim Grey"),
               drop=("Light", "Light Glass"),
               boxes=(dict(u=(-1, -0.5, 0.55, 0.62), h=(0.62, 0.68)), dict(u=(-1, -0.5, 0.72, 0.80), h=(0.74, 0.80)))),),
    # round 8 (smooth_normals()): the frunk lid's and the front's normals smoothed (the source's subsurf level 1 lid lit
    # as flat patches; same camera FRONT34 paint normal deviation > 8 deg 3.3 -> 1.5 %)
    smooth_normals=(dict(obj="Bonnet", angle=25.0, iters=8),
                    dict(obj="Car Body", angle=25.0, iters=8, u=(-1, -0.5, 1.80, 2.0), h=(0.50, 0.58)),
                    # round 9: the tailgate and the body behind the rear doors (same camera REAR34 paint: facets lit as
                    # grey patches, normal deviation > 8 deg 3.2 %)
                    dict(obj="Trunk", angle=20.0, iters=8),
                    dict(obj="Car Body", angle=20.0, iters=8, u=(3.9, 4.1, 9, 9), h=(0.25, 0.32))),
    # the lower black trim (sills, arch lips, the bumpers' lower parts: source Black Car Paint under h) dark grey (official
    # SIDE: sills 30-37 grading to 17-27, arch lips 45-67, rear bumper 43-49 against the build's flat 22): the faces
    # black before arch_inner (its wheel wells stay black) and still black after `recolour`
    trim_grey=dict(objs=("Car Body", "Front Door", "Back Door", "Trunk"), mat="Black Car Paint", to="Trim Grey", h=0.75),
    # the arch lips' paint border (arch_lip(); round 5): the official SIDE's first paint past each near tyre (PPSW grey
    # > 110, sub-px) as (image angle deg, radius px) round the tyre's rim-lip ring centre, every 5 deg from the start
    # angle. The faces of `objs` in `mats` outboard of `az` m (the front fender is narrower than its lip) with a corner
    # facing the camera by `facing` within `inn` px inside / `out` px outside the border are cut along it (projected
    # through the SIDE camera, both sides) and recoloured: paint inside trim grey, trim outside paint, black outside
    # paint when every corner is in that band, faces the camera by `black`[0] and lies outboard of `black`[1] m
    # (arch_inner took some of the flare's faces; not the wells' walls, which project outside the border too). The
    # source's black flare ran 10-14 px wider behind the rear wheel (down to the bumper corner) and round the front
    # arch's rear, the lip 6-13 px narrower over the rear wheel; recolouring whole faces by box bit a sawtooth into it
    # (round 4). The front ring's first two angles extrapolated (the official's ray there leaves the car), its 285-290
    # and the rear's 315-325 interpolated over a highlight on the lip.
    arch_lip=dict(objs=("Car Body", "Back Door", "Front Door"), mats=("Car Paint", "Trim Grey", "Black Car Paint"),
                  view="SIDE", az=0.50, facing=0.15, black=(0.3, 0.85), inn=40, out=24,
                  # round 9: the lip itself (inside the border, outboard of `az` m, its face normal out sideways by
                  # `facing`) in its own dark grey (the source's lip face was black like the well's wall) out from its
                  # inner edge: the official SIDE's first lip pixel past the dark well (lum >= 30 scanning in from the
                  # paint, D:/temp-bitcmp/FixModelXR9/a/rings.py), radius px round each ring's centre from its start
                  # angle every 5 deg (None: no lip there, the paint meets the well); inside it black
                  lip=dict(to="Lip Grey", mats=("Car Paint", "Trim Grey", "Black Car Paint"), az=0.90, facing=0.4,
                           inner=((None, None, None, 120.3, 109.3, 109.3, 108.3, 108.3, 108.2, 108.2, 107.2, 107.1,
                                   106.1, 106.1, 106.0, 105.0, 105.0, 105.0, 105.0, 104.0, 104.0, 104.0, 103.0, 103.0,
                                   103.0, 103.0, 104.1, 104.1, 104.1, 104.2, 105.2, 105.2, 106.3, 105.3, 106.3, 106.3,
                                   106.3, 112.0, 116.0, 120.0, 124.3, 127.3),
                                  (None, None, 107.4, 106.2, 106.1, 104.9, 105.9, 105.8, 104.8, 104.9, 105.0, 105.2,
                                   105.4, 105.6, 105.8, 105.1, 105.4, 105.7, 106.0, 106.2, 106.5, 107.7, 106.9, 108.0,
                                   108.1, 109.1, 109.1, 111.1, 110.9, 111.8, 111.6, 111.3, 111.1, 111.8, 111.5,
                                   112.2))),
                  rings=(((574.7, 608.4), 160, (124.0, 123.3, 122.3, 120.8, 119.8, 118.8, 118.8, 118.2, 118.2, 117.7,
                                                117.6, 117.1, 116.6, 116.0, 116.0, 115.5, 115.0, 114.9, 114.4, 113.9,
                                                113.9, 113.9, 114.0, 113.5, 114.0, 114.0, 114.1, 114.6, 115.1, 115.7,
                                                116.2, 116.2, 117.3, 117.8, 118.3, 119.3, 120.3, 121.3, 121.8, 123.3,
                                                124.8, 127.3)),
                        ((1316.5, 608.6), 180, (122.4, 121.2, 120.4, 119.7, 119.1, 118.9, 118.8, 118.3, 118.3, 118.4,
                                                118.0, 118.1, 117.8, 118.0, 117.8, 118.1, 117.8, 118.1, 118.4, 118.7,
                                                118.9, 119.2, 119.3, 120.0, 120.6, 121.1, 121.6, 122.1, 122.6, 123.0,
                                                123.5, 123.8, 124.6, 125.3, 126.5, 128.2)))),
    # the rear bumper's paint / dark trim border (rear_trim(); round 6): the official's, SIDE (x 1444-1532) and REAR34
    # (x 1104-1446, both sides) back-projected onto the prepped body, as height h (m) over theta (deg) round a vertical
    # axis at u `axis`: 0 out to the side, 90 at the centre line (the two views agree within 7 mm). The source's trim
    # top stepped up 13-14 px behind the rear arch (SIDE x 1444-1455) and rose 4-12 px early / high under the tail
    # lamps (REAR34 x 1244-1316). Faces of `mats` behind u `u` with every corner within `band` m of the border and
    # outside the rear arch's paint border (arch_lip's ring, + `clear` px: the lip is arch_lip's) are cut along it:
    # paint over it, trim grey under it
    rear_trim=dict(obj="Car Body", mats=("Car Paint", "Trim Grey"), u=4.40, band=0.10, clear=0.0, axis=4.3,
                   table=((8, 0.421), (12, 0.419), (16, 0.420), (20, 0.425), (24, 0.429), (28, 0.434), (32, 0.439),
                          (36, 0.446), (40, 0.452), (43, 0.459), (46, 0.465), (47.6, 0.479), (49, 0.484),
                          (50.4, 0.503), (53.5, 0.507), (58.7, 0.510), (64, 0.514), (75, 0.517), (90, 0.518))),
    # round 10: the A pillar's foot body colour down to the belt (px_cut(); official FRONT34: the pillar's white runs
    # down to the belt along this line, only a small black triangle at the mirror's root behind it; the source's black
    # sail filled the pillar's lower 3 cm between the windscreen's corner and the mirror)
    px_cut=(dict(name="pillar foot", obj="Car Body", mats=("Black Car Paint",), to="Car Paint", view="FRONT34",
                 line=((928.0, 450.5), (961.5, 408.0)), u=(1.30, 1.65), h=(0.98, 1.20), az=0.70),),
    # round 10: the tailgate's side seams out onto the official's (gate_slide(); REAR34 a/gseam.py: the official's
    # side seam 11-16 px left of ours, 0..+3 after), the gate and the body round it slid together on the surface. Its
    # bottom (4-8 px under the official's) stays: raised 1.9 cm the convert's cabin wall came through the bumper's
    # top at the corner as a dark wedge. `side` in 0.10: at 0.20 the rear glass's frame on the gate moved off the glass
    # (1 px holes in every state E); 0.06 tore the gate open (SE 1 -> 14 px). Round 11: fade 1.15-1.30 -> 1.08-1.22
    # (above 1.22 the skin round the gate's top corner faces sideways: slid sideways along u it kinked the upper seam;
    # 1.25-1.45 tore it open; `facing`, the slide weighted by the skin's u-facing, also bent the side seam)
    gate_slide=dict(objs=("Car Body", "Trunk"), u=4.3, da=0.05, side=(0.10, 0.12), h_lo=0.65, fade=(1.08, 1.22),
                    reach=0.15),
    # round 11: the frunk lid's side edge over the headlamps up onto the official's lamp top (lid_slide(); the top:
    # LampRim_X's outline 3 px up, whose ring the official lamp's edge is: on it the body's gutter under the lid's edge
    # still showed white between the lid and the ring)
    lid_slide=dict(objs=("Car Body", "Bonnet"), lid="Bonnet", view="FRONT34", x=(572, 752), fade=12, band=(30, 24),
                   top=((571.5, 524.5), (600, 511.5), (650, 501.5), (700, 492.5), (738, 489.5), (747, 491.5)),
                   u=(-1, 1.2), h=(0.60, 0.95), reach=0.06),
    # the fitted official cameras (temp/skf_mx/work/camfit/cams.json: R world -> OpenCV, C, f, w, h in the scene's grid
    # frame; anchor: the front wheel centre y and the ground there) for FIELD decals. FRONT34 / REAR34 refit
    # 2026-11-12 (round 2) with their height held at SIDE's (fit.py HOLD: one studio rig): FRONT34 had sat 20 cm lower,
    # IoU 0.9421 -> 0.9682. Round 7 (camfit/fit7.py): REAR34 refit on body-independent marks -- the tyres' silhouettes
    # (the far rear one under the bumper too), the centre line (TESLA's S, the plate), the rim lip -- plus the side
    # marks' heights and the roof top; the old one put the centre line 15.9 px and the far rear tyre 14 px off (its rim
    # lip radius had drifted to 312 mm, now 272 = SIDE's). FRONT34 then on the side marks triangulated by SIDE + REAR34
    # (it moved 1 cm). Round 10 (camfit/fit10.py): FRONT34 refit -- the near wheels and the centre line leave its
    # distance / focal trade-off free (fit7 all ran 2.6 m out), so the far side's outline (the symmetric prep body's
    # projection vs the official alpha edge, weight 0.5) joins the tyres, rims, nose T / V, held height and side marks:
    # 12 cm further, f +42; far outline rms 13.7 / 8.8 -> 9.3 / 6.4 px, nose T -4.0 -> +0.5 px, IoU 0.9715 -> 0.9727
    cams=dict(
        SIDE=dict(R=((-0.0614609, -0.9980892, 0.0063593), (-0.0737313, -0.0018138, -0.9972765),
                     (0.9953825, -0.0617624, -0.0734789)), C=(-5.568395, 0.311058, 0.128667), f=1464.931, w=1920, h=1080),
        FRONT34=dict(R=((-0.6366169, -0.7711789, -0.0014041), (-0.0422436, 0.0366904, -0.9984334),
                        (0.7700223, -0.6355603, -0.0559351)), C=(-5.115084, 4.468957, 0.129196), f=1946.007, w=1920,
                     h=1080),
        REAR34=dict(R=((0.7079705, -0.7061538, -0.0111645), (-0.0390861, -0.0233928, -0.9989620),
                       (0.7051596, 0.7076720, -0.0441622)), C=(-5.485325, -5.786292, 0.128223), f=2287.880, w=1920,
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
        # (round 8) the lamp's thin dark rim round the lens and the light strip (official FRONT34: the white strip reads
        # off the white paint by it). Round 10: a ring, the lens and the strip cut out (`holes`, their union): a whole
        # plate 2 mm under the lens poked through its chords on the curve (the game's lit lamp at night half dark).
        # Round 11: its outer tip from x 577 (lid_slide uncovered it: a black wedge past the lamp's end)
        dict(name="LampRim_X", view="FRONT34", compete=("SIDE",), mat="Lamp_Rim", on=("Car Body",), off=0.006, u=(0.1, 0.75),
             outline=((577, 525.3), (600, 514.5), (650, 504.5), (700, 495.5), (738, 492.5), (747, 494.5), (757.5, 500),
                      (744, 516.5), (703, 533.5), (650, 541.5), (600, 540.5), (577, 533)),
             holes=(((574, 527), (600, 516), (650, 506), (700, 497), (738, 494), (745, 496), (750, 497.5), (755, 500.5),
                     (742, 515), (702, 532), (650, 540), (600, 539), (573, 530)),)),
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
             outline=((1198.3, 460), (1202.8, 447), (1209.5, 435.2), (1221, 428.6), (1253.3, 426.7), (1299, 429),
                      (1307.8, 438.3), (1307, 442), (1300, 440), (1296.7, 436.7), (1253.3, 435), (1228, 436.5),
                      (1224, 441), (1220, 453.3), (1221.7, 455), (1275, 455), (1318.3, 453.3), (1317.5, 463), (1200, 464.2))),
        dict(name="TailRefl_X", view="REAR34", mat="Lamp_Reflector", on=("Car Body", "Trunk"), off=0.010,
             u=(4.3, 5.2), outline=((1143, 466.5), (1186, 464), (1186, 470.5), (1143, 471))),
        # (step 2, round 6: at the default 6 px the faces round the vertices past the car's outline went, a paint gap at
        # the housing's top rear corner in SIDE and REAR34)
        dict(name="TailLampS_X", view="SIDE", mat="Lamp_Housing", on=("Car Body", "Trunk"), off=0.004, u=(4.3, 5.2), step=2.0,
             outline=((1456.3, 465.6), (1477.5, 450), (1496.3, 438.8), (1510, 430.6), (1515, 427.5), (1525, 426.9),
                      (1528.8, 430), (1530.6, 460), (1530, 471.3), (1515, 473.1), (1477.5, 471.9), (1460, 468.8))),
        dict(name="TailReflS_X", view="SIDE", mat="Lamp_Reflector", on=("Car Body", "Trunk"), off=0.006,
             u=(4.3, 5.2), outline=((1468.8, 458.1), (1503.8, 456.9), (1503.8, 463.1), (1468.8, 463.1))),
        # the front bumper camera (2025+, official FRONT34): a grey ring on the lower grille's middle (as a decal on
        # the bumper: convert.py CAMERA's flat ring stood 16 mm off it) and its dark lens, on the model's centre line (x
        # 463: at the official's 478 its mirror copy stood 24 px apart); on the nose's tip: `front` (the ring 6 mm off
        # it made the game model 5,062.4 long), Intake_X holed under them
        dict(name="CamRing_X", view="FRONT34", mat="badge_cam", on=("Car Body",), off=0.002, front=0.001, step=1.0,
             outline=tuple((463 + 5.0 * np.cos(t), 638 + 4.0 * np.sin(t)) for t in np.linspace(0, 2 * np.pi, 16, endpoint=False)),
             holes=(tuple((463 + 3.0 * np.cos(t), 638 + 2.4 * np.sin(t)) for t in np.linspace(0, 2 * np.pi, 12, endpoint=False)),)),
        dict(name="CamLens_X", view="FRONT34", mat="Intake_Black", on=("Car Body",), off=0.002, front=0.001,
             step=1.0,
             outline=tuple((463 + 3.0 * np.cos(t), 638 + 2.4 * np.sin(t)) for t in np.linspace(0, 2 * np.pi, 12, endpoint=False))),
        # the black band across the tailgate between the lamps (official REAR34 y 439-461; the source's trim 8 px)
        dict(name="GateBand_X", view="REAR34", mat="Gate_Band", on=("Trunk",), off=0.004, u=(4.3, 5.2),
             outline=((1288, 441), (1330, 440), (1420, 440), (1450, 442), (1462, 445), (1462, 459), (1420, 461),
                      (1330, 461), (1288, 466))),
        # the rear bumper's reflector: a thin slit under the bumper's lip (official REAR34, x 1267-1310 y 618-625)
        dict(name="BumpRefl_X", view="REAR34", mat="Bump_Refl", on=("Car Body",), off=0.003, step=2.0,
             outline=((1266, 626), (1272, 622.5), (1290, 619), (1311, 617.5), (1311, 620.5), (1290, 623), (1272, 626.5))),
        # the lower grille across the front (official FRONT34; the mirror copy covers the other half)
        dict(name="Intake_X", view="FRONT34", mat="Intake_Black", on=("Car Body",), off=0.003, front=0.0008, step=3.0,
             # (round 9: its top 5-7 px lower, its bottom on the official's: official FRONT34 x 445-580 per 15 px)
             outline=((430, 625), (445, 626), (475, 632), (505, 636), (550, 640), (565, 645), (580, 662), (588, 670),
                      (565, 669), (535, 667), (505, 663), (475, 659), (445, 651), (430, 648)),
             holes=(tuple((463 + 5.0 * np.cos(t), 638 + 4.0 * np.sin(t)) for t in np.linspace(0, 2 * np.pi, 16, endpoint=False)),)),
    ),
    # the wheel arches' openings: round the axle, towards it by d x k(angle from the top, deg: + rearward) x win(rho);
    # `to` (round 9): out sideways to that az (m) x the same weight
    arches=(
        dict(ax="r", d=0.064, rho=(0.40, 0.47, 0.58, 0.80), ang=((-180, 0.0), (-110, 0.0), (-90, 0.5), (0, 1.0),
                                                                    (90, 0.0), (180, 0.0)), az=(0.55, 0.65)),
        dict(ax="f", d=-0.012, rho=(0.40, 0.45, 0.55, 0.70), ang=((-180, 0.0), (-60, 0.0), (0, 1.0), (60, 0.0),
                                                                     (180, 0.0)), az=(0.55, 0.65)),   # top +3 px
        # round 9: the front lip's lower edge down towards the tyre over its upper rear (official SIDE / FRONT34: the lip
        # 11 px wide from 14 px past the tyre at 290-340 deg; ours 2-6 px wide, the well's wall seen 10 px above the
        # tyre): the edge's outboard vertices only, the paint border (SIDE, arch_lip) where it was
        dict(ax="f", d=0.04, rho=(0.40, 0.43, 0.48, 0.51), ang=((-180, 0.0), (15, 0.0), (35, 1.0), (80, 1.0),
                                                                     (100, 0.0), (180, 0.0)), az=(0.80, 0.90)),
        # round 9: the rear lip and the flank round it out over the tyre (the rear tyres' outer faces at 0.992 m stood
        # 2-3 cm out of the lip's rear half, 0.964-0.972: official REAR34 the lip hides the tread's rear, ours showed
        # it, 30 px of tyre where the official has the grey lip); the front lips (0.9995) stay the widest
        dict(ax="r", d=0.0, to=0.997, rho=(0.36, 0.40, 0.505, 0.515), ang=((-180, 0.0), (-20, 0.0), (20, 0.4),
                                                                             (80, 1.0), (130, 1.0), (160, 0.0),
                                                                             (180, 0.0)), az=(0.80, 0.90)),
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
            du, dh, da = du - a["d"] * k * x / rho, dh - a["d"] * k * y / rho, da + np.maximum(a.get("to", 0.0) - az, 0.0) * k
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
    official's underside reads body colour from the low studio cameras); two legs (`leg_mat`) at |z| `leg` down onto the tailgate (a ray down
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
            [sp.get("leg_mat", black)] * 6)
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


def bspline(x, lo, hi, k):
    """uniform cubic B-spline basis: (len(x), k), k functions over [lo, hi] (k - 3 spans)"""
    t = (np.clip(x, lo, hi) - lo) / (hi - lo) * (k - 3)
    i0 = np.clip(np.floor(t).astype(int), 0, k - 4)
    f = t - i0
    w = np.stack([(1 - f) ** 3, 3 * f ** 3 - 6 * f ** 2 + 4, -3 * f ** 3 + 3 * f ** 2 + 3 * f + 1, f ** 3], 1) / 6
    B = np.zeros((len(x), k))
    for j in range(4):
        B[np.arange(len(x)), i0 + j] = w[:, j]
    return B


def in_tris(pts, T):
    """points (m, 2) inside any of the triangles T (n, 3, 2)"""
    if not len(T) or not len(pts):
        return np.zeros(len(pts), bool)
    a, b, c = T[:, 0][None], T[:, 1][None], T[:, 2][None]
    cr = lambda o, p_, r_: (p_[..., 0] - o[..., 0]) * (r_[..., 1] - o[..., 1]) - (p_[..., 1] - o[..., 1]) * (r_[..., 0] - o[..., 0])  # noqa
    out = []
    for i in range(0, len(pts), 256):
        q = pts[i:i + 256, None]
        d1, d2, d3 = cr(a, b, q), cr(b, c, q), cr(c, a, q)
        out.append((((d1 >= 0) & (d2 >= 0) & (d3 >= 0)) | ((d1 <= 0) & (d2 <= 0) & (d3 <= 0))).any(1))
    return np.concatenate(out)


def pspline(x, z, y, knots, lam):
    """y(x, z) as a tensor cubic P-spline over the samples' box (knots per axis, 2nd-difference penalty lam), Huber
    reweighted (the outliers: pockets, lumps); -> fit(x, z), clamped to the box"""
    kt, kh = knots
    lo, hi = (x.min(), z.min()), (x.max(), z.max())

    def basis(t, s_):
        Bt, Bh = bspline(t, lo[0], hi[0], kt), bspline(s_, lo[1], hi[1], kh)
        return (Bt[:, :, None] * Bh[:, None, :]).reshape(len(t), -1)

    B = basis(x, z)
    D = lambda k: np.diff(np.eye(k), 2, axis=0)      # noqa: E731
    pen = lam * (np.kron(D(kt).T @ D(kt), np.eye(kh)) + np.kron(np.eye(kt), D(kh).T @ D(kh)))
    w = np.ones(len(y))
    for _ in range(8):
        c = np.linalg.solve(B.T @ (B * w[:, None]) + pen, B.T @ (w * y))
        res = y - B @ c
        sd = 1.4826 * np.median(np.abs(res)) + 1e-4
        w = np.minimum(1, 2 * sd / np.maximum(np.abs(res), 1e-9))
    return lambda t, s_: basis(t, s_) @ c


def rebuild(me, F, fit, nose, yc, inner, P2, rm):
    """FIELD fascia's pockets (`inner`: the filled faces and `grow` rings round them) made afresh on the fitted
    surface: their faces out (moved onto it the walls fold over face down and coincide: dark specks, dark AO), the
    hole they leave in the (arc, h) plane P2 triangulated again (constrained Delaunay of the rim and a `step` grid)
    where no face on the surface covers it, the new vertices on the surface."""
    import bmesh
    from mathutils import Vector
    from mathutils.geometry import delaunay_2d_cdt
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    pin = {bm.verts[i] for i in np.flatnonzero(inner)}
    paint = {i for i, m in enumerate(me.materials) if m and m.name == "Car Paint"}
    gone = {f for f in bm.faces if f.material_index in paint and all(v in pin for v in f.verts)}
    # (the source's pockets are loose shells over open seams: moved onto the surface the seams gape; the paint faces
    # on an open edge near a pocket go too, so the new faces span the seam)
    pp = P2[[v.index for v in pin]]
    ov = {v for e_ in bm.edges if len(e_.link_faces) == 1 for v in e_.verts
          if inner[v.index] or np.min(np.linalg.norm(pp - P2[v.index], axis=1)) < F["seam"]}
    gone |= {f for v in ov for f in v.link_faces if f.material_index in paint}

    def tris(faces):
        return np.array([P2[[f.verts[0].index, f.verts[j].index, f.verts[j + 1].index]]
                         for f in faces for j in range(1, len(f.verts) - 1)]).reshape(-1, 3, 2)

    co = np.array([v.co[:] for v in bm.verts])
    u, h, a = (nose - co[:, 0]) * S, co[:, 2] * S, (co[:, 1] - yc) * S
    surf = np.abs(fit(np.arctan2(a, F["axis"] - u), h) - np.hypot(F["axis"] - u, a)) < 0.002
    surf &= win(u, F["u"]) * win(h, F["h"]) > 0
    bm.normal_update()
    for f in bm.faces:                               # on the surface but wound inwards (a pocket's undercut wall): out
        if f not in gone and f.material_index in paint and any(v in pin for v in f.verts) and \
                all(surf[v.index] for v in f.verts):
            t_ = np.mean([np.arctan2(a[v.index], F["axis"] - u[v.index]) for v in f.verts])
            if f.normal.x * np.cos(t_) + f.normal.y * np.sin(t_) < 0:
                gone.add(f)
    G = tris(gone)
    lo, hi = G.reshape(-1, 2).min(0) - 0.05, G.reshape(-1, 2).max(0) + 0.05
    stay = tris([f for f in bm.faces if f not in gone and all(surf[v.index] for v in f.verts)
                 and all((P2[v.index] > lo).all() and (P2[v.index] < hi).all() for v in f.verts)])
    # (and the trim near it, facing out: the lower lip, the arch lips; not filled over)
    dr = np.abs(fit(np.arctan2(a, F["axis"] - u), h) - np.hypot(F["axis"] - u, a))
    trim = []
    for f in bm.faces:
        if f in gone or not all(dr[v.index] < 0.03 and (P2[v.index] > lo).all() and (P2[v.index] < hi).all()
                                for v in f.verts):
            continue
        t_ = np.mean([np.arctan2(a[v.index], F["axis"] - u[v.index]) for v in f.verts])
        if f.normal.x * np.cos(t_) + f.normal.y * np.sin(t_) > 0:
            trim.append(f)
    stay = np.concatenate([stay, tris(trim)])
    rim_e = [e_ for e_ in bm.edges if any(f in gone for f in e_.link_faces) and any(f not in gone for f in e_.link_faces)]
    rim_v = sorted({v for e_ in rim_e for v in e_.verts}, key=lambda v: v.index)
    at = {v: i for i, v in enumerate(rim_v)}
    st = F["step"]
    # where to fill: the pockets' footprint (and 2 cells round it: no slivers at the rim), not what the surface covers
    xs, ys = np.arange(lo[0], hi[0], st / 2), np.arange(lo[1], hi[1], st / 2)
    cc = np.stack(np.meshgrid(xs, ys), -1).reshape(-1, 2)
    fillm = in_tris(cc, G).reshape(len(ys), len(xs))
    for _ in range(2):
        m_ = fillm.copy()
        fillm[1:] |= m_[:-1]; fillm[:-1] |= m_[1:]; fillm[:, 1:] |= m_[:, :-1]; fillm[:, :-1] |= m_[:, 1:]  # noqa: E702
    fillm &= ~in_tris(cc, stay).reshape(len(ys), len(xs))
    infill = lambda x: fillm[np.clip(np.round((x[:, 1] - lo[1]) / (st / 2)).astype(int), 0, len(ys) - 1),   # noqa
                             np.clip(np.round((x[:, 0] - lo[0]) / (st / 2)).astype(int), 0, len(xs) - 1)]
    g = np.stack(np.meshgrid(np.arange(lo[0], hi[0], st), np.arange(lo[1], hi[1], st)), -1).reshape(-1, 2)
    rp = P2[[v.index for v in rim_v]]
    g = g[infill(g) & ~in_tris(g, stay)]
    g = g[np.min(np.linalg.norm(g[:, None] - rp[None], axis=2), 1) > st / 2] if len(g) and len(rp) else g
    V, _, Fs, orig, *_ = delaunay_2d_cdt([Vector(x) for x in (*rp, *g)], [(at[e_.verts[0]], at[e_.verts[1]]) for e_ in rim_e],
                                         [], 0, 1e-7)
    V = np.array([x[:] for x in V])
    keep = [f for f in Fs if len(f) == 3 and infill(V[list(f)].mean(0)[None])[0]
            and not in_tris(V[list(f)].mean(0)[None], stay)[0]]
    bmesh.ops.delete(bm, geom=list(gone), context="FACES")
    made, pslot = {}, next(i for i, m in enumerate(me.materials) if m and m.name == "Car Paint")

    def vert(i):
        if i not in made:
            src = [j for j in orig[i] if j < len(rim_v)]
            if src and rim_v[src[0]].is_valid:
                made[i] = rim_v[src[0]]
            else:
                t_, z_ = V[i][0] / rm, V[i][1]
                r_ = fit(np.array([t_]), np.array([z_]))[0]
                made[i] = bm.verts.new((nose - (F["axis"] - r_ * np.cos(t_)) / S, yc + r_ * np.sin(t_) / S, z_ / S))
        return made[i]

    n = 0
    for f in keep:
        vs = [vert(i) for i in f]
        if len(set(vs)) < 3 or bm.faces.get(vs):
            continue
        nf = bm.faces.new(vs)
        nf.material_index = pslot
        nf.normal_update()
        t_ = np.mean([np.arctan2((v.co.y - yc) * S, F["axis"] - (nose - v.co.x) * S) for v in vs])
        if nf.normal.x * np.cos(t_) + nf.normal.y * np.sin(t_) < 0:
            nf.normal_flip()
        n += 1
    # the seams left open round them (loose shells meeting the new faces): their vertices within `weld` m merged
    lo_, hi_ = lo - 0.02, hi + 0.02
    win_ = lambda v: lo_[1] < v.co.z * S < hi_[1] and \
        lo_[0] < np.arctan2((v.co.y - yc) * S, F["axis"] - (nose - v.co.x) * S) * rm < hi_[0]   # noqa: E731
    ends = [v for e_ in bm.edges if len(e_.link_faces) == 1 for v in e_.verts if v.is_valid and win_(v)]
    nv = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=list(dict.fromkeys(ends)), dist=F["weld"] / S)   # (edge order: a set's ran per run)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-6, edges=bm.edges[:])
    print("PREP fascia: %d seam vertices welded" % (nv - len(bm.verts)))
    # the slivers the weld left open (whole thin triangles missing, 12-65 mm long: from outside the liner showed
    # through, three dark scratches on each lower corner): loops of at most `fill` open edges closed in paint (a
    # wider weld closed two of three but opened the bumper's side)
    rim2 = [e_ for e_ in bm.edges if len(e_.link_faces) == 1 and all(win_(v) for v in e_.verts)]
    made_ = bmesh.ops.holes_fill(bm, edges=rim2, sides=F["fill"])["faces"]
    for f_ in made_:
        f_.material_index = pslot
    print("PREP fascia: %d slivers filled" % len(made_))
    bm.to_mesh(me)
    bm.free()
    cn = np.empty(len(me.loops) * 3, np.float32)     # (their corners' normals: the face's)
    me.attributes["custom_normal"].data.foreach_get("vector", cn)
    cn = cn.reshape(-1, 3)
    bad = np.linalg.norm(cn, axis=1) < 0.5
    if bad.any():
        lt = np.empty(len(me.polygons), np.int64)
        me.polygons.foreach_get("loop_total", lt)
        fn = np.empty(len(me.polygons) * 3)
        me.polygons.foreach_get("normal", fn)
        cn[bad] = np.repeat(fn.reshape(-1, 3), lt, 0)[bad]
        me.attributes["custom_normal"].data.foreach_set("vector", cn.ravel())
    me.update()
    print("PREP fascia: pockets made afresh, %d faces out, %d in (%d rim edges, %d grid points)" % (
        len(gone), n, len(rim_e), len(g)))


def fascia(meshes, nose, yc, filled):
    """FIELD fascia: the front bumper / nose as one smooth surface. Seen from a vertical axis behind the nose (`axis` u)
    the fascia is a radial height field r(theta, h); its paint vertices facing out (`facing`, not the filled fog lamp
    pockets `filled` and `grow` rings round them) fit a P-spline (`knots`, `lam`, Huber reweighted), then every paint
    vertex in the window (u, h) moves radially onto it (the pockets fill, the decimation's and the field's lumps go),
    `carry` materials' vertices ride along by the neighbours' mean move; the paint corners get the surface's normal."""
    F = FIELD["fascia"]
    o = next(o for o in meshes if o.name == F["obj"])
    me = o.data
    p = np.array([v.co[:] for v in me.vertices])
    u, h, a = (nose - p[:, 0]) * S, p[:, 2] * S, (p[:, 1] - yc) * S
    th, r = np.arctan2(a, F["axis"] - u), np.hypot(F["axis"] - u, a)
    mi = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("material_index", mi)
    lv = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", lv)
    lt = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("loop_total", lt)
    lf = np.repeat(np.arange(len(me.polygons)), lt)                   # face of each loop
    pu, ph, paz, pn, psg = face_frame(me, nose, yc)
    rd = np.stack([F["axis"] - pu, psg * paz], 1)
    facing = (pn[:, 0] * rd[:, 0] + pn[:, 1] * rd[:, 1]) / np.maximum(np.linalg.norm(rd, axis=1), 1e-9)
    paint = np.isin(mi, slots(me, "Car Paint"))
    wv = win(u, F["u"]) * win(h, F["h"])
    near = np.zeros(len(p), bool)                    # the pockets and `grow` rings round them: no samples
    near[lv[filled[lf]]] = True
    for _ in range(F["grow"]):
        near[lv[np.bincount(lf, near[lv], len(lt))[lf] > 0]] = True
    sv = np.zeros(len(p), bool)
    sv[lv[(paint & (facing > F["facing"]))[lf]]] = True
    sv &= ~near & (wv > 0.5)
    fit = pspline(th[sv], h[sv], r[sv], F["knots"], F["lam"])
    # the pockets' leftovers (walls, the lamps' other materials) body colour, onto the surface whatever they were
    trim = np.isin(mi, [i for m in F["carry"] for i in slots(me, m)])
    mi[(np.bincount(lf, near[lv], len(lt)) == lt) & ~trim] = slots(me, "Car Paint")[0]
    me.polygons.foreach_set("material_index", mi)
    paint = np.isin(mi, slots(me, "Car Paint"))
    mv = np.zeros(len(p), bool)
    mv[lv[paint[lf]]] = True
    mv = (mv | near) & (wv > 0)
    e = np.array([(ed.vertices[0], ed.vertices[1]) for ed in me.edges])
    cnt = np.maximum(np.bincount(e[:, 0], minlength=len(p)) + np.bincount(e[:, 1], minlength=len(p)), 1)
    nb = lambda x: (np.bincount(e[:, 0], x[e[:, 1]], len(p)) + np.bincount(e[:, 1], x[e[:, 0]], len(p))) / cnt  # noqa
    d = np.zeros(len(p))
    d[mv] = np.clip(fit(th[mv], h[mv]) - r[mv], -F["cap"], F["cap"]) * wv[mv]
    ride = np.zeros(len(p), bool)                    # carried trim: the neighbours' mean move (Jacobi)
    ride[lv[np.isin(mi, [i for m in F["carry"] for i in slots(me, m)])[lf]]] = True
    ride &= ~mv & (wv > 0)
    for _ in range(60):
        d[ride] = nb(d)[ride] * wv[ride]
    r2 = r + d
    u2, a2 = F["axis"] - r2 * np.cos(th), r2 * np.sin(th)
    u2 = np.where(mv, np.maximum(u2, u.min() + F["tip"]), u2)   # (the manual's length: the nose `tip` back)
    q = np.stack([nose - u2 / S, yc + a2 / S, h / S], 1)
    me.vertices.foreach_set("co", q.ravel())
    me.update()
    rebuild(me, F, fit, nose, yc, near & (wv > 0.999), np.stack([th * np.median(r[sv]), h], 1), np.median(r[sv]))
    # the surface's normal at the paint corners on it: X(theta, h) = (r cos - axis, r sin, h) forward / left / up
    p = np.array([v.co[:] for v in me.vertices])
    u, h, a = (nose - p[:, 0]) * S, p[:, 2] * S, (p[:, 1] - yc) * S
    th, r = np.arctan2(a, F["axis"] - u), np.hypot(F["axis"] - u, a)
    wv = win(u, F["u"]) * win(h, F["h"])
    mi = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("material_index", mi)
    lv = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", lv)
    lt = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("loop_total", lt)
    lf = np.repeat(np.arange(len(me.polygons)), lt)
    on = (wv > 0) & (np.abs(fit(th, h) - r) < 0.002)
    k = np.isin(mi, slots(me, "Car Paint"))[lf] & on[lv]
    E = 1e-4
    t0, z0 = th[lv[k]], h[lv[k]]
    rr = fit(t0, z0)
    rt, rh = (fit(t0 + E, z0) - fit(t0 - E, z0)) / (2 * E), (fit(t0, z0 + E) - fit(t0, z0 - E)) / (2 * E)
    ct, st = np.cos(t0), np.sin(t0)
    dt = np.stack([rt * ct - rr * st, rt * st + rr * ct, np.zeros_like(rr)], 1)
    dz = np.stack([rh * ct, rh * st, np.ones_like(rr)], 1)
    n = np.cross(dt, dz)
    n *= np.sign((n[:, 0] * ct + n[:, 1] * st))[:, None]
    n /= np.linalg.norm(n, axis=1, keepdims=True)
    fn = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("normal", fn)
    fn = fn.reshape(-1, 3)[lf[k]]
    cn = np.empty(len(me.loops) * 3, np.float32)
    me.attributes["custom_normal"].data.foreach_get("vector", cn)
    cn = cn.reshape(-1, 3)
    # (not the faces folding under or round the corner, unless every corner of the face is on the surface)
    full = (np.bincount(lf, k, len(lt)) == lt)[lf[k]]
    al = wv[lv[k]][:, None] * (((fn * n).sum(1) > F["align"]) | full)[:, None]
    m = al * n + (1 - al) * cn[k]
    cn[k] = m / np.maximum(np.linalg.norm(m, axis=1, keepdims=True), 1e-9)
    me.attributes["custom_normal"].data.foreach_set("vector", cn.ravel())
    me.update()
    print("PREP fascia: %d samples, %d moved (|d| p50 %.1f p99 %.1f max %.1f mm), %d carried, %d corners" % (
        sv.sum(), mv.sum(), np.median(np.abs(d[mv])) * 1000, np.percentile(np.abs(d[mv]), 99) * 1000,
        np.abs(d[mv]).max() * 1000, ride.sum(), k.sum()))


def fair(meshes, nose, yc):
    """FIELD fair (round 8): each box's vertices of `obj` (u, h windows; not on an open edge: the lid gap stays; every
    face round them in `mats` and not under the `lid`: the panels below it) moved to the smoothest surface through what
    is round them (minimum |L x|^2, uniform Laplacian L, the rest fixed: C1 onto the neighbours), their corners'
    normals the new mesh's; the source's lumps there (the pre-2021 nose cone, the headlamp pockets, recoloured body
    colour) read as crumpled facets in the studio light and the game's sheen. Loose pieces left with nothing fixed (the
    lamps' reflectors inside their pockets) go; the `paint` materials moved become body colour."""
    import bmesh
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    for F in FIELD["fair"]:
        o = next(o for o in meshes if o.name == F["obj"])
        me = o.data
        lid = next(o_ for o_ in meshes if o_.name == F["lid"]).data
        cover = BVHTree.FromPolygons([v.co[:] for v in lid.vertices], [p_.vertices[:] for p_ in lid.polygons])
        objs = [o_ for o_ in meshes if not o_.name.startswith(("Tyre", "Rim"))]
        k0 = np.cumsum([0] + [len(o_.data.vertices) for o_ in objs])
        hull = BVHTree.FromPolygons([v.co[:] for o_ in objs for v in o_.data.vertices],
                                    [[i + k for i in p_.vertices] for o_, k in zip(objs, k0) for p_ in o_.data.polygons])
        g = (np.sqrt(5) - 1) / 2                      # directions round the car, none from under it
        dirs = [Vector((np.cos(2 * np.pi * g * i) * np.sqrt(1 - z * z), np.sin(2 * np.pi * g * i) * np.sqrt(1 - z * z),
                        z)) for i, z in enumerate(np.linspace(-0.3, 0.98, 48))]
        dirs_j = [Vector((np.cos(2 * np.pi * g * i) * np.sqrt(1 - z * z), np.sin(2 * np.pi * g * i) * np.sqrt(1 - z * z),
                          z)) for i, z in enumerate(np.linspace(-0.3, 0.995, 400))]   # (finer: the lamp's top under the lip)
        ok_m = np.array([bool(m) and m.name in F["mats"] for m in me.materials])
        seen_m = np.array([bool(m) and m.name in F.get("seen", ()) for m in me.materials])
        for _ in range(2):                            # (again once the loose pieces are gone)
            p = np.array([v.co[:] for v in me.vertices])
            u, h, a = (nose - p[:, 0]) * S, p[:, 2] * S, np.abs(p[:, 1] - yc) * S
            e = np.array([ed.vertices[:] for ed in me.edges])
            nf = np.zeros(len(e), np.int64)          # faces per edge: open edges (1) pinned
            ek = {tuple(sorted(x)): i for i, x in enumerate(e.tolist())}
            for poly in me.polygons:
                for k_ in poly.edge_keys:
                    nf[ek[k_]] += 1
            box = np.zeros(len(p), bool)
            for b in F["boxes"]:
                box |= (win(u, b["u"]) > 0.999) & (win(h, b["h"]) > 0.999) & (win(a, b.get("az")) > 0.999)
            bad = np.zeros(len(p), bool)              # a vertex with a face it may not move
            for poly in me.polygons:
                vs = list(poly.vertices)
                if not box[vs].any():
                    continue
                c, n = poly.center, poly.normal
                hidden = lambda ds=dirs: all(hull.ray_cast(c + n * (0.0005 / S), d, 3.0 / S)[0] is not None   # noqa: E731
                                             for d in ds if d.dot(n) > 0.15)
                if not ok_m[poly.material_index] or cover.ray_cast(c + Vector((0, 0, F["under"] / S)), Vector((0, 0, 1)),
                                                                    0.4 / S)[0] is not None:
                    bad[vs] = True                    # (more than `under` m below the lid)
                elif seen_m[poly.material_index] and hidden():
                    bad[vs] = True                    # (`seen` materials: only where seen from outside)
                elif F.get("jamb") and cover.ray_cast(c + Vector((0, 0, F["jamb"] / S)), Vector((0, 0, 1)), 0.4 / S)[0] \
                        is not None and hidden(dirs_j):
                    bad[vs] = True                    # (round 9: under the lid and unseen with it shut: the opening's sides)
            free = box & ~bad
            free[e[nf == 1].ravel()] = False
            lab = np.where(free, np.arange(len(p)), -1)   # free pieces touching no fixed vertex: loose
            fe = e[free[e[:, 0]] & free[e[:, 1]]]
            for _ in range(500):
                m_ = np.minimum(lab[fe[:, 0]], lab[fe[:, 1]])
                new = lab.copy()
                np.minimum.at(new, fe[:, 0], m_)
                np.minimum.at(new, fe[:, 1], m_)
                if (new == lab).all():
                    break
                lab = new
            edge_fix = (free[e[:, 0]] & ~free[e[:, 1]]) | (~free[e[:, 0]] & free[e[:, 1]])
            held = np.unique(lab[e[edge_fix].ravel()])
            loose = free & ~np.isin(lab, held[held >= 0])
            if not loose.any():
                break
            bm = bmesh.new()
            bm.from_mesh(me)
            bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[bm.verts[i] for i in np.flatnonzero(loose)], context="VERTS")
            bm.to_mesh(me)
            bm.free()
            me.update()
            print("PREP fair %s: %d loose vertices out" % (F["obj"], loose.sum()))
        deg = np.maximum(np.bincount(e[:, 0], minlength=len(p)) + np.bincount(e[:, 1], minlength=len(p)), 1)

        def lap(x):                                   # x - neighbours' mean, per column
            s_ = np.stack([np.bincount(e[:, 0], x[e[:, 1], c], len(p)) + np.bincount(e[:, 1], x[e[:, 0], c], len(p))
                           for c in range(3)], 1)
            return x - s_ / deg[:, None]

        def lapT(y):                                  # L^T y = y - sum over neighbours j of y_j / deg_j
            z_ = y / deg[:, None]
            s_ = np.stack([np.bincount(e[:, 0], z_[e[:, 1], c], len(p)) + np.bincount(e[:, 1], z_[e[:, 0], c], len(p))
                           for c in range(3)], 1)
            return y - s_

        def A(v):
            x = np.zeros_like(p)
            x[free] = v
            return lapT(lap(x))[free]
        for rnd in range(6):                          # (the nose's middle: no vertex `ahead` m forward)
            x0 = p.copy()
            x0[free] = 0
            rhs = -lapT(lap(x0))[free]
            v = p[free].copy()                        # conjugate gradients from where they are
            rr = rhs - A(v)
            d = rr.copy()
            r2 = (rr * rr).sum(0)
            for it in range(F.get("iters", 3000)):
                Ad = A(d)
                al = r2 / np.maximum((d * Ad).sum(0), 1e-30)
                v += d * al
                rr -= Ad * al
                r2n = (rr * rr).sum(0)
                if np.sqrt(r2n.max()) < 1e-9:
                    break
                d = rr + d * (r2n / np.maximum(r2, 1e-30))
                r2 = r2n
            q = p.copy()
            q[free] = v
            ahead = free & ((q[:, 0] - p[:, 0]) * S > F.get("ahead", 9.0)) & (a < F.get("ahead_az", 9.0))
            if not ahead.any():
                break
            free &= ~ahead
        me.vertices.foreach_set("co", q.ravel())
        me.update()
        # the corners of every face touching a moved vertex: the area-weighted vertex normal of the new mesh
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        lt = np.empty(len(me.polygons), np.int64)
        me.polygons.foreach_get("loop_total", lt)
        lf = np.repeat(np.arange(len(me.polygons)), lt)
        fn = np.empty(len(me.polygons) * 3)
        me.polygons.foreach_get("normal", fn)
        ar = np.empty(len(me.polygons))
        me.polygons.foreach_get("area", ar)
        fn = fn.reshape(-1, 3) * ar[:, None]
        vn = np.stack([np.bincount(lv, fn[lf, c], len(p)) for c in range(3)], 1)
        vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.attributes["custom_normal"].data.foreach_get("vector", cn)
        cn = cn.reshape(-1, 3)
        k = free[lv]
        cn[k] = vn[lv[k]]
        me.attributes["custom_normal"].data.foreach_set("vector", cn.ravel())
        allf = np.bincount(lf, free[lv], len(lt)) == lt   # faces of moved vertices only
        mi = np.empty(len(me.polygons), np.int64)
        me.polygons.foreach_get("material_index", mi)
        mi[allf & np.isin(mi, [i for m in F.get("paint", ()) for i in slots(me, m)])] = slots(me, "Car Paint")[0]
        me.polygons.foreach_set("material_index", mi)
        me.update()
        mv = np.stack([np.bincount(lf, vn[lv, c], len(lt)) for c in range(3)], 1)
        fold = allf & ((fn * mv).sum(1) < 0)
        # the `drop` materials left in the box unmoved (the lamps' insides under the lid's edge) go: the faired skin
        # sank under them
        inbox = np.bincount(lf, box[lv], len(lt)) > 0
        gone = inbox & ~allf & np.isin(mi, [i for m in F.get("drop", ()) for i in slots(me, m)])
        if gone.any():
            bm = bmesh.new()
            bm.from_mesh(me)
            bm.faces.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.flatnonzero(gone)], context="FACES_ONLY")
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
            bm.to_mesh(me)
            bm.free()
            me.update()
        print("PREP fair %s: %d vertices, %d CG steps, max move %.1f mm, %d faces folded over" % (
            F["obj"], free.sum(), it + 1, np.linalg.norm(q - p, axis=1).max() * S * 1000, int(fold.sum())),
              "%d left inside dropped" % gone.sum())


def smooth_normals(meshes, nose, yc):
    """FIELD smooth_normals (round 8): each `obj`'s vertex normals (the mean of its corners') averaged with its
    neighbours' `iters` times, in its box (u, h windows) and only across neighbours within `angle` deg (the lid's lip and
    the panels' creases stay); a corner within `angle` of its vertex's takes it. The source's subsurf level 1 mesh lit
    as patches of flat light on the frunk lid (official smooth)"""
    for F in FIELD["smooth_normals"]:
        me = next(o for o in meshes if o.name == F["obj"]).data
        p = np.array([v.co[:] for v in me.vertices])
        u, h = (nose - p[:, 0]) * S, p[:, 2] * S
        box = (win(u, F.get("u")) > 0.999) & (win(h, F.get("h")) > 0.999)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.attributes["custom_normal"].data.foreach_get("vector", cn)
        cn = cn.reshape(-1, 3).astype(float)
        vn = np.stack([np.bincount(lv, cn[:, c], len(p)) for c in range(3)], 1)
        vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
        e = np.array([ed.vertices[:] for ed in me.edges])
        ca = np.cos(np.radians(F["angle"]))
        for _ in range(F["iters"]):
            ok = ((vn[e[:, 0]] * vn[e[:, 1]]).sum(1) > ca)[:, None]
            s_ = vn.copy()
            np.add.at(s_, e[:, 0], vn[e[:, 1]] * ok)
            np.add.at(s_, e[:, 1], vn[e[:, 0]] * ok)
            s_ /= np.maximum(np.linalg.norm(s_, axis=1, keepdims=True), 1e-12)
            vn = np.where(box[:, None], s_, vn)
        k = box[lv] & ((cn * vn[lv]).sum(1) > ca)
        cn[k] = vn[lv[k]]
        me.attributes["custom_normal"].data.foreach_set("vector", cn.astype(np.float32).ravel())
        me.update()
        print("PREP smooth normals %s: %d corners" % (F["obj"], k.sum()))


def cam_px(P, view, yc, ftyre_x):
    """world points (source units, n x 3) -> FIELD cams[view] pixels (n x 2), each on the camera's side of the centre
    line (mirrored: both sides of the car alike), and that side's camera centre (world); decals()'s world() inverted"""
    c, (fy, gnd) = FIELD["cams"][view], FIELD["anchor"]
    R, C = np.array(c["R"]), np.array(c["C"])
    dy, dz = fy / K - S * (ftyre_x - SRC_C[0]), gnd / K
    eye = np.array([(C[1] / K - dy) / S + SRC_C[0], SRC_C[1] - C[0] / K / S, (C[2] / K - dz) / S])
    y = yc + np.sign(eye[1] - yc) * np.abs(P[:, 1] - yc)
    g = K * np.stack([(SRC_C[1] - y) * S, (P[:, 0] - SRC_C[0]) * S + dy, P[:, 2] * S + dz], 1)
    q = (g - C) @ R.T
    return np.stack([c["f"] * q[:, 0] / q[:, 2] + c["w"] / 2, c["f"] * q[:, 1] / q[:, 2] + c["h"] / 2], 1), eye


def arch_lip(meshes, nose, yc, ftyre_x):
    """FIELD arch_lip: the paint / trim faces round each arch cut along the official's paint border (a level set: per
    vertex, its distance in px past the border radius at its angle round the ring in the view; edges crossing it split
    where it crosses, the split points joined across each face) and recoloured by side: inside trim, outside paint.
    A face goes when its vertices are all within the rings' angles and one of them is in the band (a long face reaching
    past `out` kept the old colour: a step at the flare's foot)."""
    import bmesh
    A = FIELD["arch_lip"]
    for o in (o for o in meshes if o.name in A["objs"]):
        me = o.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.verts.ensure_lookup_table()
        bm.normal_update()
        P = np.array([v.co[:] for v in bm.verts])
        N = np.array([v.normal[:] for v in bm.verts])
        px, eye = cam_px(P, A["view"], yc, ftyre_x)
        sd = np.sign(eye[1] - yc)                      # the camera's side: every vertex and normal mirrored onto it
        e = eye - np.c_[P[:, 0], yc + sd * np.abs(P[:, 1] - yc), P[:, 2]]
        face = (N * np.c_[e[:, 0], sd * np.sign(P[:, 1] - yc + 1e-12) * e[:, 1], e[:, 2]]).sum(1) / np.linalg.norm(e, axis=1)
        f, g, band = np.full(len(P), np.nan), np.full(len(P), np.nan), np.zeros(len(P), bool)
        lip, ln = A.get("lip"), [0, 0]
        for j, ((cx, cy), a0, rs) in enumerate(A["rings"]):
            ang = (np.degrees(np.arctan2(px[:, 1] - cy, px[:, 0] - cx)) - a0) % 360 + a0
            r = np.hypot(px[:, 0] - cx, px[:, 1] - cy)
            d = r - np.interp(ang, a0 + 5 * np.arange(len(rs)), rs)
            k = (ang <= a0 + 5 * (len(rs) - 1)) & (d < 3 * A["out"]) & (np.abs(P[:, 1] - yc) * S > A["az"])
            f[k] = d[k]
            band |= k & (d > -A["inn"]) & (d < A["out"]) & (face > A["facing"])
            if lip:                                    # the lip's inner edge (None: none there)
                ri = np.array([np.nan if x is None else x for x in lip["inner"][j]])
                g[k] = (r - np.interp(ang, a0 + 5 * np.arange(len(ri)), ri))[k]
        ms = [i for m in A["mats"] for i in slots(me, m)]
        trim, paint = slot(me, "Trim Grey"), slot(me, "Car Paint")
        fv, gv, bv, fa = ({v: x[v.index] for v in bm.verts} for x in (f, g, band, face))
        cand = lambda fc: fc.material_index in ms and all(np.isfinite(fv[v]) for v in fc.verts) and \
            any(bv[v] for v in fc.verts)   # noqa: E731
        new = []
        for lv, other in ((fv, gv), (gv, fv)) if lip else ((fv, gv),):
            bm.edges.index_update()                    # (the first pass's new edges: else ties, set order per run)
            cut = {e for fc in bm.faces if cand(fc) for e in fc.edges if lv[e.verts[0]] * lv[e.verts[1]] < 0}
            nw = []
            for e in sorted(cut, key=lambda e: e.index):  # (index order: the split's vertex order is the build's)
                a, b = e.verts
                t = lv[a] / (lv[a] - lv[b])
                _, nv = bmesh.utils.edge_split(e, a, t)
                lv[nv], other[nv] = 0.0, other[a] + t * (other[b] - other[a])
                bv[nv], fa[nv] = True, (fa[a] + fa[b]) / 2
                nw.append(nv)
            bmesh.ops.connect_verts(bm, verts=nw)
            new += nw
        if lip:
            bm.normal_update()
            ls, keep = slot(me, lip["to"]), [i for m in lip["mats"] for i in slots(me, m)]
            black = slot(me, "Black Car Paint")
        n = [0, 0]
        for fc in bm.faces:
            if not cand(fc):
                continue
            m = np.mean([fv[v] for v in fc.verts])
            mg = np.mean([gv[v] for v in fc.verts])
            c = fc.calc_center_median()
            if lip and m < 0 and fc.material_index in keep and fc.normal.y * np.sign(c.y - yc) > lip["facing"] and \
                    all(abs(v.co.y - yc) * S > lip["az"] for v in fc.verts):
                if mg < 0:                             # inside the official lip: the well
                    fc.material_index, ln[1] = black, ln[1] + 1
                else:
                    fc.material_index, ln[0] = ls, ln[0] + 1
            elif lip and m < 0 and mg < 0 and fc.material_index in (trim, paint):
                fc.material_index, ln[1] = black, ln[1] + 1
            elif m < 0 and fc.material_index == paint:
                fc.material_index, n[0] = trim, n[0] + 1
            elif m > 0 and (fc.material_index == trim or all(bv[v] and fa[v] > A["black"][0] and
                                                               abs(v.co.y - yc) * S > A["black"][1] for v in fc.verts)):
                fc.material_index, n[1] = paint, n[1] + 1
        bm.to_mesh(me)
        bm.free()
        print("PREP arch lip %s: %d edges cut, %d faces to trim, %d to paint, %d to the lip, %d to the well, "
              "%d corners without a normal" % (o.name, len(new), n[0], n[1], ln[0], ln[1], split_normals(me)))


def rear_trim(meshes, nose, yc, ftyre_x):
    """FIELD rear_trim: the rear bumper's paint / trim border cut along the official's (a level set as arch_lip's, in
    metres: per vertex its height over the border's at its angle round the axis) and recoloured by side."""
    import bmesh
    A, ((cx, cy), a0, rs) = FIELD["rear_trim"], FIELD["arch_lip"]["rings"][1]
    me = next(o for o in meshes if o.name == A["obj"]).data
    bm = bmesh.new()
    bm.from_mesh(me)
    P = np.array([v.co[:] for v in bm.verts])
    u, h, az = (nose - P[:, 0]) * S, P[:, 2] * S, np.abs(P[:, 1] - yc) * S
    f = h - np.interp(np.degrees(np.arctan2(u - A["axis"], az)), *zip(*A["table"]))
    px, _ = cam_px(P, "SIDE", yc, ftyre_x)
    ang = (np.degrees(np.arctan2(px[:, 1] - cy, px[:, 0] - cx)) - a0) % 360 + a0
    lip = np.hypot(px[:, 0] - cx, px[:, 1] - cy) < np.interp(ang, a0 + 5 * np.arange(len(rs)), rs) + A["clear"]
    ok = (u > A["u"]) & (np.abs(f) < A["band"]) & ~lip
    ms = [i for m in A["mats"] for i in slots(me, m)]
    trim, paint = slot(me, "Trim Grey"), slot(me, "Car Paint")
    fv, kv = ({v: x[v.index] for v in bm.verts} for x in (f, ok))
    cand = lambda fc: fc.material_index in ms and all(kv[v] for v in fc.verts)   # noqa: E731
    cut = {e for fc in bm.faces if cand(fc) for e in fc.edges if fv[e.verts[0]] * fv[e.verts[1]] < 0}
    new = []
    for e in sorted(cut, key=lambda e: e.index):
        a, b = e.verts
        _, nv = bmesh.utils.edge_split(e, a, fv[a] / (fv[a] - fv[b]))
        fv[nv], kv[nv] = 0.0, True
        new.append(nv)
    bmesh.ops.connect_verts(bm, verts=new)
    n = [0, 0]
    for fc in bm.faces:
        if cand(fc):
            to = trim if np.mean([fv[v] for v in fc.verts]) < 0 else paint
            n[to == paint] += fc.material_index != to
            fc.material_index = to
    bm.to_mesh(me)
    bm.free()
    print("PREP rear trim: %d edges cut, %d faces to trim, %d to paint, %d corners without a normal"
          % (len(new), n[0], n[1], split_normals(me)))


def gate_slide(meshes, nose, yc):
    """FIELD gate_slide: the tailgate's side seams moved out on the surface (the body round them and the tailgate both,
    so the seam stays closed): by `da` (m, lateral) in a tent `side` (in, out) round the seam's az at that height, over
    h from `h_lo` and fading over `fade`; each moved vertex of the skin back onto the old surface along u (the rear face
    a height field there), its normals the old surface's there; the rest (the lamps' pockets, the jambs, the liners
    under the skin) shifted with the skin over them (round 11: projected onto the skin too they folded over it, dark
    specks round the lamps' lower edge and a crease on the C pillar, same camera REAR34)."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    A = FIELD.get("gate_slide")
    if not A:
        return
    ms = [o for o in meshes if o.name in A["objs"]]
    tr = next(o for o in ms if o.name == "Trunk").data
    edges = {}
    for p in tr.polygons:
        for k in p.edge_keys:
            edges[k] = edges.get(k, 0) + 1
    bv = np.array([tr.vertices[i].co[:] for k, c in edges.items() if c == 1 for i in k])
    bh, baz = bv[:, 2] * S, np.abs(bv[:, 1] - yc) * S
    hs = np.arange(0.60, 1.60, 0.02)                  # the seam: per h its widest az
    side = np.array([baz[np.abs(bh - x) < 0.02].max() if (np.abs(bh - x) < 0.02).any() else np.nan for x in hs])
    hs, side = hs[np.isfinite(side)], side[np.isfinite(side)]
    tent = lambda x, a, b: np.clip(np.minimum(1 + x / a, 1 - x / b), 0, 1)   # noqa: E731  (1 at 0, 0 at -a / +b)

    def target(o, p):
        u, h, az = (nose - p[:, 0]) * S, p[:, 2] * S, np.abs(p[:, 1] - yc) * S
        da = A["da"] * tent(az - np.interp(h, hs, side), *A["side"]) * \
            s(h, A["fade"][1], A["fade"][0]) * (h > A["h_lo"])
        i = np.flatnonzero((u > A["u"]) & (da > 1e-6))
        o0 = np.c_[np.full(len(i), nose - 6.0 / S), p[i, 1], p[i, 2]]
        o1 = o0 + np.c_[np.zeros(len(i)), np.sign(p[i, 1] - yc + 1e-12) * da[i] / S, np.zeros(len(i))]
        d = np.tile((1.0, 0, 0), (len(i), 1))
        return i, o0, d, o1, d
    print("PREP gate slide: seam az %.3f-%.3f (h %.2f-%.2f), %d vertices moved"
          % (side.min(), side.max(), hs.min(), hs.max(), resurface(ms, target, A["reach"])))

def lid_slide(meshes, nose, yc, ftyre_x):
    """FIELD lid_slide (round 11): the frunk lid's side edge over the headlamps moved up onto the official's lamp top
    (official FRONT34: the lid's edge is the lamp's top edge; ours came down over the lamp's top 3-9 px, the lens decal
    under it hidden and the lid's edge read as white specks over the lamp). Per image column in `x` the lid's lowest
    visible pixel against the `top` chain (px) gives how far up; the lid and the body round the edge (a tent `band`
    px above / below it, faded over `fade` px at the columns' ends) slide up together in the view, back onto the old
    surface along the camera's rays (resurface()), both sides alike (the far side through the mirrored camera)."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    A = FIELD.get("lid_slide")
    if not A:
        return
    ms = [o for o in meshes if o.name in A["objs"]]
    c = FIELD["cams"][A["view"]]
    R, C, (fy, gnd) = np.array(c["R"]), np.array(c["C"]), FIELD["anchor"]
    dy, dz = fy / K - S * (ftyre_x - SRC_C[0]), gnd / K
    world = lambda g: np.array([(g[1] / K - dy) / S + SRC_C[0], SRC_C[1] - g[0] / K / S, (g[2] / K - dz) / S])  # noqa
    eye = world(C)
    side = np.sign(eye[1] - yc)

    def ray(x, y):                                    # pixel -> unit direction (world), the camera's side
        d = world(C + R.T @ np.array([(x - c["w"] / 2) / c["f"], (y - c["h"] / 2) / c["f"], 1.0])) - eye
        return d / np.linalg.norm(d)
    k0 = np.cumsum([0] + [len(o.data.vertices) for o in ms])
    bvh = BVHTree.FromPolygons([v.co[:] for o in ms for v in o.data.vertices],
                               [[i + k for i in f.vertices] for o, k in zip(ms, k0) for f in o.data.polygons])
    lid = np.repeat([o.name == A["lid"] for o in ms], [len(o.data.polygons) for o in ms])
    top = np.array(A["top"], float)
    xs = np.arange(A["x"][0], A["x"][1] + 1.0)
    up = np.zeros(len(xs))
    for j, x in enumerate(xs):                        # the lid's lowest pixel near the official top, 0.25 px steps
        yt = np.interp(x, top[:, 0], top[:, 1])
        ys = [y for y in np.arange(yt - 20, yt + 20, 0.25)
              if (h := bvh.ray_cast(Vector(eye), Vector(ray(x, y))))[0] is not None and lid[h[2]]]
        up[j] = max(max(ys) - yt, 0.0) if ys else 0.0
    up = np.convolve(np.pad(up, 2, mode="edge"), np.ones(5) / 5, mode="valid")
    up *= np.clip(np.minimum(xs - xs[0], xs[-1] - xs) / A["fade"], 0, 1)
    yb = np.interp(xs, top[:, 0], top[:, 1]) + up    # the lid's edge now

    def target(o, p):
        px, _ = cam_px(p, A["view"], yc, ftyre_x)
        u, h = (nose - p[:, 0]) * S, p[:, 2] * S
        e = px[:, 1] - np.interp(px[:, 0], xs, yb)   # px below the lid's edge
        w = np.clip(np.minimum(1 + e / A["band"][0], 1 - e / A["band"][1]), 0, 1)
        dv = np.interp(px[:, 0], xs, up, left=0, right=0) * w * (u > A["u"][0]) * (u < A["u"][1]) * \
            (h > A["h"][0]) * (h < A["h"][1])
        i = np.flatnonzero(dv > 0.05)
        far = np.sign(p[i, 1] - yc) != side
        eo = np.where(far[:, None], eye * (1, -1, 1) + (0, 2 * yc, 0), eye)
        d0 = p[i] - eo
        d0 /= np.linalg.norm(d0, axis=1, keepdims=True)
        d1 = np.array([ray(x, y - v) for (x, y), v in zip(px[i], dv[i])]).reshape(-1, 3)
        d1[far, 1] *= -1
        return i, eo, d0, eo, d1
    print("PREP lid slide: up to %.1f px (x %d-%d), %d vertices moved"
          % (up.max(), xs[0], xs[-1], resurface(ms, target, A["reach"])))



def resurface(ms, target, reach, skin=0.003):
    """the vertices target(o, p) picks (-> indices; per vertex its own ray (origin, direction) through it and the ray
    it moves to; world) moved onto the objects' old surface: a skin vertex (its own ray's first hit within `skin` m of
    it, its normal facing the ray) to the new ray's first hit if within `reach` (m) of where it was, its corner normals
    the old surface's there (barycentric on the hit triangle's); any other by the skin's move over it (new hit - own
    hit; none past `reach`), its normals kept -> how many moved"""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    old, tn = [], []                                  # (vertices, triangles) per object; the triangles' corner normals
    for o in ms:
        me = o.data
        me.calc_loop_triangles()
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.attributes["custom_normal"].data.foreach_get("vector", cn)
        old.append((np.array([v.co[:] for v in me.vertices]), np.array([t.vertices[:] for t in me.loop_triangles])))
        tn.append(cn.reshape(-1, 3)[np.array([t.loops[:] for t in me.loop_triangles])])
    allv = np.concatenate([v for v, _ in old])
    off = np.cumsum([0] + [len(v) for v, _ in old])
    allt = np.concatenate([t + off[i] for i, (_, t) in enumerate(old)])
    alln = np.concatenate(tn)
    bvh = BVHTree.FromPolygons([Vector(p) for p in allv], allt.tolist())
    n_moved = 0
    for o, (p, _) in zip(ms, old):
        idx, org0, drn0, org1, drn1 = target(o, p)
        me = o.data
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.attributes["custom_normal"].data.foreach_get("vector", cn)
        cn = cn.reshape(-1, 3)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        vn = np.zeros_like(p)                         # the vertices' normals: their corners' mean
        np.add.at(vn, lv, cn)
        q = p.copy()
        for i, a0, d0, a1, d1 in zip(idx, org0, drn0, org1, drn1):
            hit = bvh.ray_cast(Vector(a1), Vector(d1))
            own = bvh.ray_cast(Vector(a0), Vector(d0))
            if own[0] is not None and np.linalg.norm(np.array(own[0][:]) - p[i]) * S < skin and vn[i] @ d0 < 0:
                if hit[0] is None or np.linalg.norm(np.array(hit[0][:]) - p[i]) * S > reach:
                    continue
                q[i] = hit[0][:]
                a_, b_, c_ = allv[allt[hit[2]]]
                w = np.linalg.lstsq(np.c_[a_ - c_, b_ - c_], np.array(hit[0][:]) - c_, rcond=None)[0]
                nn = alln[hit[2]].T @ np.r_[w, 1 - w.sum()]
                cn[lv == i] = nn / max(np.linalg.norm(nn), 1e-9)
            elif hit[0] is not None and own[0] is not None:
                m = np.array(hit[0][:]) - np.array(own[0][:])
                q[i] = p[i] + (m if np.linalg.norm(m) * S < reach else (a1 - a0))
            else:
                q[i] = p[i] + (a1 - a0)
            n_moved += 1
        me.vertices.foreach_set("co", q.ravel())
        me.attributes["custom_normal"].data.foreach_set("vector", cn.ravel())
        me.update()
    return n_moved


def px_cut(meshes, nose, yc, ftyre_x):
    """FIELD px_cut: faces of `mats` within the u / h / az windows cut along a straight line in an official view (px;
    a level set as arch_lip's: per vertex its signed distance to the line, `to` on its left going a -> b) and the left
    side recoloured `to`."""
    import bmesh
    for A in FIELD.get("px_cut", ()):
        me = next(o for o in meshes if o.name == A["obj"]).data
        bm = bmesh.new()
        bm.from_mesh(me)
        P = np.array([v.co[:] for v in bm.verts])
        u, h, az = (nose - P[:, 0]) * S, P[:, 2] * S, np.abs(P[:, 1] - yc) * S
        px, _ = cam_px(P, A["view"], yc, ftyre_x)
        a, b = np.array(A["line"], float)
        d = (b - a) / np.linalg.norm(b - a)
        f = (px[:, 0] - a[0]) * d[1] - (px[:, 1] - a[1]) * d[0]      # > 0: left of a -> b (image y down)
        ok = (u > A["u"][0]) & (u < A["u"][1]) & (h > A["h"][0]) & (h < A["h"][1]) & (az > A["az"])
        ms = [i for m in A["mats"] for i in slots(me, m)]
        fv, kv = ({v: x[v.index] for v in bm.verts} for x in (f, ok))
        cand = lambda fc: fc.material_index in ms and all(kv[v] for v in fc.verts)   # noqa: E731
        cut = {e for fc in bm.faces if cand(fc) for e in fc.edges if fv[e.verts[0]] * fv[e.verts[1]] < 0}
        new = []
        for e in sorted(cut, key=lambda e: e.index):
            v0, v1 = e.verts
            _, nv = bmesh.utils.edge_split(e, v0, fv[v0] / (fv[v0] - fv[v1]))
            fv[nv], kv[nv] = 0.0, True
            new.append(nv)
        bmesh.ops.connect_verts(bm, verts=new)
        to, n = slot(me, A["to"]), 0
        for fc in bm.faces:
            if cand(fc) and np.mean([fv[v] for v in fc.verts]) > 0:
                fc.material_index, n = to, n + 1
        bm.to_mesh(me)
        bm.free()
        print("PREP px cut %s: %d edges cut, %d faces to %s, %d corners without a normal"
              % (A["name"], len(new), n, A["to"], split_normals(me)))


def split_normals(me):
    """the corners a split made: normals interpolated, else (none) the face's; -> how many were missing"""
    cn = np.empty(len(me.loops) * 3, np.float32)
    me.attributes["custom_normal"].data.foreach_get("vector", cn)
    cn = cn.reshape(-1, 3)
    bad = np.linalg.norm(cn, axis=1) < 0.5
    if bad.any():
        lt = np.empty(len(me.polygons), np.int64)
        me.polygons.foreach_get("loop_total", lt)
        fn = np.empty(len(me.polygons) * 3)
        me.polygons.foreach_get("normal", fn)
        cn[bad] = np.repeat(fn.reshape(-1, 3), lt, 0)[bad]
        me.attributes["custom_normal"].data.foreach_set("vector", cn.ravel())
    me.update()
    return int(bad.sum())


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
    initial>` riding it (cars/model_x.py PART_OBJS / SHELL_OBJS). `holes`: loops cut out of the outline; `front`: no
    vertex past the body's nose by more than it (m)."""
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
    tip = max(v.co.x for v in next(o for o in meshes if o.name == "Car Body").data.vertices)
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
            if "front" in dc:                         # not past the nose's tip by more than `front` m (the length)
                v.co.x = min(v.co.x, tip + dc["front"] / S)
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
    filled = None                                     # the faces `fill` recolours (FIELD fascia: no samples there)
    for r in FIELD["recolour"]:
        o = next(o for o in meshes if o.name == r["obj"])
        u, h, az, _, _ = face_frame(o.data, nose, yc)
        mi = np.empty(len(o.data.polygons), np.int64)
        o.data.polygons.foreach_get("material_index", mi)
        a_ = r.get("az", (-1, 9))
        k = np.isin(mi, slots(o.data, r["mat"])) & (u > r["u"][0]) & (u < r["u"][1]) & (h > r["h"][0]) & \
            (h < r["h"][1]) & (az > a_[0]) & (az < a_[1])
        mi[k] = slot(o.data, r["to"])
        if r.get("fill"):
            filled = k if filled is None else filled | k
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
    gate_slide(meshes, nose, yc)
    if FIELD.get("fascia"):
        fascia(meshes, nose, yc, filled)
    if FIELD.get("fair"):
        fair(meshes, nose, yc)
    if FIELD.get("smooth_normals"):
        smooth_normals(meshes, nose, yc)
    ftyre = next(o for o in meshes if o.name.startswith("Tyre") and (nose - pts(o)[:, 0].mean()) * S < 2.5)
    fx = pts(ftyre)[:, 0]
    lid_slide(meshes, nose, yc, (fx.min() + fx.max()) / 2)
    arch_lip(meshes, nose, yc, (fx.min() + fx.max()) / 2)
    rear_trim(meshes, nose, yc, (fx.min() + fx.max()) / 2)
    px_cut(meshes, nose, yc, (fx.min() + fx.max()) / 2)
    meshes.append(spoiler(bpy, meshes, nose, yc))
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
