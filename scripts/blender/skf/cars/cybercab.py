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
import pathlib

K = 0.826                                  # grid per metre (pzveh.K): the prep's numbers are metres


def _g(*m):
    return tuple(round(v * K, 4) for v in m)


def _axis(sd):
    """The butterfly hinge axis of the door on side sd (-1 left): up the A-pillar, raked back and in (rider guide p.5:
    the doors swing up and forward); the right one mirrored (its angle the other sign)."""
    x, y, z = -0.3 * sd, -0.75, 0.6
    n = math.sqrt(x * x + y * y + z * z)
    return (x / n, y / n, z / n)


def _red():
    """The tail lamp's red ring on the car's left (prep cybercab_lines.json tail_lamp_red_left, metres, five points):
    the rear face's corner from its inner |x| (rider guide 01 rear: 0.665) round to its y on the side (01 side: only the
    corner's last 7-8 cm is red: -1.95); ahead of it the side's run is smoked grey. The ring's inner |x| and front y
    bound the red; the prep owns them (these numbers until its lines have the key)."""
    p = pathlib.Path(__file__).resolve().parents[4] / "temp" / "skf_cc" / "cybercab_lines.json"
    ring = json.loads(p.read_text()).get("tail_lamp_red_left") if p.exists() else None
    if not ring:
        return dict(x=0.665, y=-1.95)
    return dict(x=round(min(abs(q[0]) for q in ring), 4), y=round(max(q[1] for q in ring), 4))


_RED = _red()

CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_cc",
    NAME="MinidoracatTesla_Cybercab",
    SCRIPT_MARK="---- geometry (TeslaCybercab)",
    APP_CAR="app_car_cybercab_{}.png",
    # rider guide: width 1,754, height 1,408; length off the 01 side view (REPORT.md)
    DIMS=(4.278, 1.754, 1.408),
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
    TIRE_AXLES=dict(front=(0.3576, 0.215), rear=(0.4017, 0.225)),
    # the prep's tyres stand with their 8 mm bulge out (outer |x| 0.854 / 0.808): the wheel centres that far in, on the
    # prep's track (1.477 / 1.375)
    WHEEL_INSET=0.0066,
    CAB_BOX=(1.20, 0.35, -0.95),
    # two seats behind the door opening's middle by back (front only), x 0.27 (06 top view: two ~0.48-0.52 m seats
    # 0.09-0.10 m apart, K 0.826 grid per m; at 0.31 the gap was 0.24 m, cabin-r2); the passengers' pose: SEAT_POSE
    SEAT=dict(x=0.27, h=0.384, z=-0.222, back=(0.16,), out=0.30, front_only=True),
    # scripts/seat_anim.py POSES: the shared front pose (leant back, thighs down) and the hands from the wheel to the
    # lap (no steering wheel): upper arms down 35 put both hands on the thighs' middle, their lowest point 1.4 cm into
    # (male) / 2.0 cm over (female) the thigh top
    SEAT_POSE={"front": [("Bip01", 25.0), ("Bip01_L_Thigh", -10.0), ("Bip01_R_Thigh", -10.0),
                         ("Bip01_L_UpperArm", -35.0), ("Bip01_R_UpperArm", -35.0)]},
    BODY_W_Z=0.55,
    # butterfly doors about DOOR_HINGE along _axis, 2 s; the trunk lid at its top edge, 50 deg (rider guide 04: 49.5
    # fitted), 3 s like the Model 3's powered lid. No EngineDoor: the hood stays on the body (no lid, no animation)
    DOORS={
        "DoorFrontLeft": (-1, _axis(-1), -85, 2.0), "DoorFrontRight": (1, _axis(1), 85, 2.0),
        "TrunkDoor": (0, (1, 0, 0), -50, 3.0),
    },
    # the hinges at the door's front top corner, at the A-pillar's foot (prep door paint at z 0.95: y 0.919, x 0.807)
    DOOR_HINGE={"DoorFrontLeft": _g(-0.80, 0.93, 0.96), "DoorFrontRight": _g(0.80, 0.93, 0.96)},
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
    RAIL=None,
    # the prep's 146k-triangle body (a 3 mm cut mesh) collapsed to about the other cars' size: each object X
    # symmetric, its open edges, its panel seams and its flat underside's outline held (DECIMATE_KEEP_BOUNDARY,
    # DECIMATE_HOLD_UNDER: pzveh.decimate)
    DECIMATE={"Paint": 16000, "Trim": 15000, "Liner": 4000, "Glass_Windshield": 1200, "Glass_Door": 700,
              "Glass_Quarter": 350, "Glass_ReverseLens": 300, "HeadLight": 800, "TailLight": 1000, "Grille": 700},
    DECIMATE_KEEP_BOUNDARY=True,
    DECIMATE_HOLD_UNDER=True,
    DECIMATE_THIN=(round(0.0003 * K, 6), round(0.02 * K, 4)),   # (pzveh.thin_seams: the cut's 1-2 mm seam vertices)
    DECIMATE_SNAP=round(0.001 * K, 6),     # (pzveh.decimate: a few held-seam collapses stood up to 19 cm off)
    PAINT_MAT="Paint",
    UV_FILL=True,                          # (convert.py fill_slivers) texels the bake left black under sliver UVs
    UV_FILL_TONE=True,                     # (convert.py textures) the filled texels stay out of the paint's quantiles
    HGT_CORNER=True,                       # (convert.py textures: the collapsed body's big triangles drew steps)
    # the hood's seam groove (the hood stays on the body: no SEAM_LINE part) drawn as an even line along the prep's
    # own hood path instead of its 5 mm groove's ragged dark texels (convert.py groove_ink)
    GROOVE_INK=dict(file="cybercab_lines.json", lines=("hood",), w=round(0.006 * K, 4), k=0.6,
                    reach=round(0.012 * K, 4), rgb=(58, 58, 60)),
    # by day: the lower body, bumpers and seam grooves dark grey (01: sill p50 50), the wheel house liners and B pillar
    # black, the light bar white, the tail bar smoked grey (its corners red: LAMPS areas), the plate light grey, the
    # side markers amber
    MAT_RGB={"Trim": (58, 58, 60), "Liner": (24, 24, 26), "Glass": (26, 30, 34), "HeadLight": (226, 228, 232),
             "TailLight": (104, 104, 108), "Plate": (206, 208, 212), "Marker": (196, 122, 44)},
    # (pane, box lo, hi, colour): the reverse lens bar under the tail face, grey, dark in its middle (01 rear)
    RECOLOR=(("Glass", _g(-0.53, -2.2, 0.49), _g(0.53, -2.0, 0.56), (112, 112, 116)),
             ("Glass", _g(-0.354, -2.2, 0.49), _g(0.354, -2.0, 0.56), (40, 40, 42))),
    GLASS_MATS=("Glass",),
    GLASS_OPAQUE=("Glass_ReverseLens", "RearCamera"),
    GLASS_BACKS=("WinLH", "WinLT", "WinRH", "WinRT"),
    ROOF_PANE="-",                         # (a body-colour roof)
    MIRROR_CAP="-",                        # (no mirrors: cameras)
    # lamps: the light bar and the wedge head lamps (HeadLight) with their dots (LampDots, the plate's material); the
    # tail bar (TailLight): its corners red tail lamps (LightLT / RT), its smoked inner part brake lamps (|x| under
    # STOP_X: StopL / R), its run along the side ahead of the red smoked and dark (rider guide 01 side)
    LAMPS=dict(head=("HeadLight",), head_y=0.5, head_objs=("LampDots_Left", "LampDots_Right"),
               tail=("TailLight",), tail_z=0.3, tail_y=-1.0, blade=None,
               areas=((dict(lo=_g(-9, -9, -9), hi=_g(-_RED["x"], _RED["y"], 9)), (122, 30, 36), True),
                      (dict(lo=_g(_RED["x"], -9, -9), hi=_g(9, _RED["y"], 9)), (122, 30, 36), True),
                      (dict(lo=_g(-9, _RED["y"], -9), hi=_g(9, -1.0, 9)), (46, 46, 48), False))),
    # part lines, side view (y, z): the door's rear edge (prep door paint: y -0.28 at z 0.35 to -0.489 at 0.95)
    LINES={"S": (_g(-0.28, 0.35), _g(-0.489, 0.95)), "BF": (_g(-0.28, 0.35), _g(-0.489, 0.95))},
    FRONT_Y=round(1.15 * K, 4), SILL_Z=round(0.30 * K, 4), ARCH=(0.0, -9.0),
    IN_DOOR=dict(up=round(0.95 * K, 4), x=0.40),
    IN_GATE=dict(y=-9.0, z=9.0, up=9.0, x_up=0.0),
    # door front edge and rear edge (B pillar) at the belt, the cabin's ring cut behind the seats (no door)
    DOOR_Y=_g(0.919, -0.489, -0.75),
    GATE_Z=round(0.466 * K, 4),            # the trunk lid's lower edge (prep panel 3)
    REAR_ARCH=(*_g(-1.3074, 0.4017), round(0.338 * K, 4)),
    GATE_X=0.55,
    STOP_X=round(_RED["x"] * K, 4),
    PANELS=dict(x=9.0, z=-9.0, front=(9.0, 9.0), rear=(9.0, 9.0), gate=(-9.0, 9.0), lid=(9.0, 9.0)),   # (PANEL_PARTS)
    # the faces' panels (prep PANELS: Body, DoorFrontLeft, DoorFrontRight, TrunkDoor, EngineDoor, ChargePortDoor):
    # the doors and the trunk lid are parts, the hood and the port lid stay on the body
    PANEL_PARTS={1: "DoorFrontLeft", 2: "DoorFrontRight", 3: "TrunkDoor"},
    GUARDS=dict(front=(round(0.95 * K, 4), 0.80, 0.45), rear=(round(-0.45 * K, 4), 0.85, 0.45)),
    # damage zones of the rest of the body (EngineDoor's condition in front, TruckBed's behind; else Roof, never
    # damaged): the paint ahead of 1.80 m and the hood (panel 4) in the front guards' zones, behind -1.85 m in the
    # rear guards'; the bumpers' dark trim there in Head / Tail (shell drawn untinted, as vanilla's bumpers)
    HEAD_TAIL=(round(1.80 * K, 4), round(-1.85 * K, 4)),
    MASK_PAINT_GUARD=True,   # (convert.py mask_paint_guard) the nose lip's sliver trim under the paint: no Head on gold
    # (convert.py lamp_zones) the lamps' unlit faces in Head / Tail (HEAD_TAIL) into the light zones: the front corner
    # markers, the reverse lens and camera glass on the rear bumper, the tail lamps' unlit part, the light bar's
    # housing (Trim, the bumper's too: a box); on the tailgate (Boot, its damage shell in the paint's hue) the duck
    # lip's black rear face and the seams (Trim) into the light zones too: not a lamp (prep_cybercab SPOILER; the tail
    # lamp bar is under it on the body), gold at f503acb (E2E cc5h), a solid grey-green band in Tail (lamp_zones)
    LAMP_ZONES=dict(keep=("Marker", "Glass"), boxes=((("Trim",), (0.0, 1.58, -0.14), (0.60, 1.74, -0.05)),),
                    trim=("Trim",)),
    # (pzveh damage_uv1) the tailgate's UV1 box (DAMAGE_BOX) fitted onto ModernCar's boot deck (UV1 island 36) and back
    # (12) only, and only their rear 0.75 of the length: ModernCar's whole Boot box reaches 26 cm further forward with
    # island 43 (four slanted triangles, |n.x| 0.79), so the front third of our long deck lay ahead of ModernCar's deck
    # and its UV1 ran on (extrapolated, bary to -1) into Veh_Damage2's flat dent blob (u 66-160, v 186-255 px of 512):
    # one flat orange patch mid-deck at condition < 40 (bb1f119 on). Islands only: the deck's front edge still on the
    # blob's tip (787 cm2); ModernCar's own deck front reaches u 82 there. 0.75: none (temp/skf_cc_car/blob_hit.py)
    DAMAGE_BOX_REF={11: dict(islands=(12, 36), y=(0.0, 0.75))},
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
    CARBON=None,
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
    # charge_port_centre x -0.7228, y -1.9943, z 0.3968), from behind onto the bumper (pzveh PORT_X)
    PORT=_g(-1.9943, 0.3968),
    PORT_X=round(-0.7228 * K, 4),
    # ---- cabin.py (mesh coords, centred)
    CABIN_FLOOR=-0.480,                    # (seat_head feet: the passengers' feet 6 mm into -0.474)
    CABIN_FRONT_Y=0.90,
    TRUNK_Y=-0.60,
    CABIN_ZC=-0.048,
    SEAM_CLEAR=0.065,
    # the trunk's sides from one profile (cabin.py trunk_walls, as Model S / X): the per-ray shell left black teeth
    # along them through the open lid
    TRUNK_WALL=True,
    HUMP_BACKS=False,
    # the front seats (06, ERG p.22, rider guide pp.10-12; cabin.py slim): a thin backrest in three slightly convex
    # sections between its two seams (bulge), its top corners rounded in towards the headrest (shoulder), low side
    # bolsters on the backrest and the cushion (side), the headrest on it narrower, a thick cushion ending in a
    # waterfall roll (roll) on one low pedestal; 0.44 wide, 0.10 apart (06 top view, cabin-r2); the cushion's front
    # 4 cm back from the bucket's (front: 06 side view 0.392 of the wheelbase behind the front axle, it was 0.362);
    # its top and the headrest's top where the bucket had them, the sections' crowns 3 mm ahead of the r1 flat
    # backrest; recline kept 32 for the passengers' pose (the official reads ~26: cabin-r1 d; at 26 seat_head back
    # -70..-14, into their backs). Between them (centre: the armrest pad's top over the cushions, length, width) the
    # bench piece with the cup holders and buckles, the armrest pad over it (06 top view: ~0.16 long, from between
    # the backrests)
    SEATS=dict(front=dict(w=0.44, back=0.50, recline=32, dy=0.056, dz=-0.121, cushion=0.10,
                          slim=dict(back=0.06, ahead=0.0, head=(0.26, 0.155, 0.08), seams=(0.36, 0.68),
                                    pedestal=(0.26, 0.30), round=0.045, front=0.26, roll=(0.06, 0.02),
                                    shoulder=(0.25, 0.23), bulge=0.008, side=(0.04, 0.025)),
                          centre=(0.14, 0.16, 0.09)),
               sill=None, bin=None),
    PARCEL=None,
    # rider guide 05 / pp.11-14, ERG pp.19 / 23 (temp/plan-next8-1114/cabin-r1, -r2): a low dash (narrower than the
    # default so its ends stay off the A-pillars), no console (the footwell open), no steering wheel (wheel None). In
    # 05's layers: its top and the lip over the cabin face dark (dash, dash_top: the game's view down through the
    # windscreen), the cabin face mid grey (dash_up) with a bright thin line across it (strip, 05's label 4), under it
    # the body's dark lower edge; the ledge the big screen (screen_size, 1.54:1, top 12 deg forward) stands on, no
    # stand, its back dark (rear: 05 / ERG p.9 x99), the window switches on the ledge under it (the detail model's
    # marks: icons); vent: the detail model's groove in the lower edge
    DASH=dict(size=(1.10, 0.30, 0.16), console=None, dash=(0, 0.80, 0.030), stand=None, screen=(0, 0.597, 0.0455),
              screen_size=(0.42, 0.272), rear="screen_rear", wheel=None, vent=-0.022,
              parts=(((1.12, 0.075, 0.034), 0.015, "dash_top", (0, 0.6625, 0.093)),
                     ((1.08, 0.016, 0.070), 0.006, "dash_up", (0, 0.645, 0.040)),
                     ((1.02, 0.008, 0.008), 0.002, "strip", (0, 0.6355, 0.047)),
                     ((0.24, 0.105, 0.030), 0.010, "dash", (0, 0.6075, -0.103)),
                     ((0.10, 0.008, 0.014), 0.003, "switch", (0, 0.5545, -0.097))),
              icons=((-0.022, 0.5505, -0.097), (0.022, 0.5505, -0.097))),
    # the door card (rider guide 05 / p.7 x795, ERG p.21 x198): all dark, the inner panel one step over the carpet
    # (DOOR_INNER), the darker pocket with the armrest under it and the pull handle in it, the speaker grille low at the
    # front
    DOOR_CARD={
        "front": [
            ("armrest pocket", "rear", 0.10, -0.205, 0.50, 0.085, 0.030, "base", 0.020),
            ("armrest", "rear", 0.12, -0.262, 0.44, 0.030, 0.070, "bed_wall_mid", 0.012),
            ("pull handle", "rear", 0.20, -0.195, 0.22, 0.020, 0.040, "screen_back", 0.008),
            ("door button", "rear", 0.43, -0.186, 0.035, 0.012, 0.050, "trim", 0.004),
            ("speaker grille", "front", 0.06, -0.47, 0.17, 0.13, 0.010, "wheel", 0.030),
        ],
    },
    DOOR_INNER=dict(cell="console"),
    # the doors' and the trunk lid's edge strips under the belt in the paint next to them, over it black (convert.py
    # pieces: the belt in the pieces' pre-centre frame; cabin-r2 D)
    SLAB_BELT_PRE=True,
    # the headliner, the pillars and the roof rails inside light grey (rider guide 05; the body's reversed faces over
    # the belt, ahead of the trunk)
    LINER_UP=dict(cell="bed_rib", dz=0.0, y=-0.60),
    # cabin.py: the parts' names -> palette cells (MinidoracatTesla_vehicle.frag CABIN; the detail model's: DETAIL_RGB
    # and DETAIL_RGB_EXTRA): the seats darker than the other cars' (ERG p.9 through the windscreen: mid-dark grey),
    # their seams, the dash's layers, the screen's dark back, the screen's car block the other cars' seat grey
    # (screen_car: the seats' cell is darker here)
    CABIN_CELL_MAP=dict(seat="bed_wall_hi", seam="liner", dash="base", dash_top="base", dash_up="bed_floor",
                        strip="bed_rim", screen_rear="screen_back", switch="screen_back", buckle="screen_back",
                        screen_car="seat"),
    DETAIL_CELL_MAP=dict(seam="mat", stitch="mat", dash="base", dash_top="base", dash_up="stitch", strip="chrome",
                         screen_rear="screen_back", switch="vent", buckle="vent", button="red", icon="chrome",
                         pod="headliner", lamp="pale", stop="red", stop_button="dash", camera="mirror"),
    # the detail model's own texture (pzveh.detail_texture: the shared cells, then these): the red of the buckles'
    # buttons and the STOP sign, the headliner's light grey for the overhead console, its light strip
    DETAIL_TEX="MinidoracatTesla_Cybercab_Detail",
    DETAIL_RGB_EXTRA=dict(red=(196, 30, 36), headliner=(120, 120, 126), pale=(228, 228, 224)),
    # the detail model's overhead console instead of a rear-view mirror (no rear window; rider guide 05: the camera
    # housing at the windscreen's top; p.14 x1691: the pod the headliner's grey, near its rear end a white capsule
    # across it, the dark STOP button with its red triangle in the capsule's middle)
    ROOF_CONSOLE=dict(size=(0.16, 0.36, 0.035), strip=(0.11, 0.045), strip_y=-0.10, stop=(0.040, 0.024),
                      camera=(0.07, 0.06, 0.045)),
)
