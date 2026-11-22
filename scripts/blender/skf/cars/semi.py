"""Tesla Semi (Long Range): the mod's own tractor body, built from Tesla's pictures alone by
scripts/blender/skf/prep_semi.py (no third-party model; temp/skf_semi/PREP.md). CAR=semi. Keys as in cybercab.py (each
is the module constant it sets). SRC is the prep's own .blend (one object per material, the glass per pane, every face
its panel in the face attribute `panel`: PANEL_PARTS). A two-seater on template MinidoracatTeslaCab (no trunk lid, no
front trunk): the driver's seat on the centre line, a folding seat behind it on the right (SEAT at), two rear-hinged
doors (DOOR_HINGE at their rear edge). Its physics (PHYS) is given, not read off the mesh: the first-gate prototype
MTSemiProto_A2S's (temp/skf_semi/PREP.md, references/semi.md), in the prep's metres. Grid units, pre-centre frame
(+Y front, +Z up, -X the truck's left, ground z 0, the front axle at y 0; the prep's metres x 0.826) unless noted.
"""
import json
import math
import os
import pathlib

K = 0.826                                  # grid per metre (pzveh.K): the prep's numbers are metres


def _g(*m):
    return tuple(round(v * K, 4) for v in m)


# The prep's own numbers (metres): the body's bbox and the wheels (prep_report.json), the door's and the cabin's lines
# (semi_lines.json). seat_anim.py imports every car file, so they come from a committed snapshot (cars/semi_body.json),
# not from temp/skf_semi (gitignored). A body round: copy the prep's output into temp/skf_semi,
# `python scripts/blender/skf/cars/semi.py` (refreshes the snapshot), build. A Semi build stops while the snapshot is
# behind temp/skf_semi.
_TMP = pathlib.Path(__file__).resolve().parents[4] / "temp" / "skf_semi"
_SNAP = pathlib.Path(__file__).with_name("semi_body.json")
_KEYS = {"prep_report.json": ("body_bbox", "wheels"),
         "semi_lines.json": ("door_left", "door_hinge_left", "cabin_floor_z", "cabin_y")}


def _from_tmp():
    """The snapshot's keys as temp/skf_semi has them (None without the prep's files there)."""
    if not all((_TMP / f).exists() for f in _KEYS):
        return None
    return {f: {k: json.loads((_TMP / f).read_text())[k] for k in ks} for f, ks in _KEYS.items()}


if __name__ == "__main__":
    _now = _from_tmp()
    if _now is None:
        raise SystemExit(f"cars/semi.py: no prep output in {_TMP}")
    _SNAP.write_text("{\n" + ",\n".join(f" {json.dumps(f)}: {{\n" + ",\n".join(
        f"  {json.dumps(k)}: {json.dumps(v, separators=(',', ':'))}" for k, v in d.items()) + "\n }"
        for f, d in _now.items()) + "\n}\n", newline="\n")
    print(f"cars/semi.py: wrote {_SNAP}")
_SNAPD = json.loads(_SNAP.read_text())
if os.environ.get("CAR") == "semi" and _from_tmp() not in (None, _SNAPD):
    raise SystemExit(f"cars/semi.py: {_SNAP.name} is behind {_TMP}: python scripts/blender/skf/cars/semi.py")
_REP, _LN = _SNAPD["prep_report.json"], _SNAPD["semi_lines.json"]
_WF, _WD = _REP["wheels"]["front"], _REP["wheels"]["drive"]
_BB = _REP["body_bbox"]
_DOOR_Y = (max(q[1] for q in _LN["door_left"]), min(q[1] for q in _LN["door_left"]))   # (front, rear) edge
_DOOR_Z = (min(q[2] for q in _LN["door_left"]), max(q[2] for q in _LN["door_left"]))   # (sill, top)
_HX, _HY, _ = _LN["door_hinge_left"][0]
# the cab floor (m) over semi_lines.json's 0.80 guess: ERG 2026 p.26 side line art (p26-x264.png, its axles 260.4 px/m:
# z = (1095.6 - row) / 260.4) draws the battery frame's top at 1.15 under the cab and p.24 (p24-x244.png, 174.4 px/m)
# the HV zone's top under the footwell at 1.195; the floor on them [INFERENCE: +-0.05, no section drawing of the floor]
_FLOOR = 1.20
_CAB_F, _CAB_R = _LN["cabin_y"]
# stage_build centres the mesh on its bbox: the cabin's numbers below are mesh (centred) coordinates
_YC, _ZC = (_BB[0][1] + _BB[1][1]) / 2 * K, (_BB[0][2] + _BB[1][2]) / 2 * K


def _c(y, z=None):
    """centred mesh y (and z) of a prep point in metres"""
    return round(y * K - _YC, 4) if z is None else (round(y * K - _YC, 4), round(z * K - _ZC, 4))


# the driver's hip (m): ERG p26-x264.png (y = (265.5 - column) / 260.4) draws the driver's cushion front at y -0.48 and
# the headrest's front at -1.10; this hip puts the game seat's 2 cm ahead / 3 cm behind them (seat_vs_official_side.png)
_HIP = _DOOR_Y[1] + 0.86
# the driver's seat drawn in p26-x264.png: the cushion's top at row 676 (1.61 m), the headrest's top at row 389
# (2.71 m); p24-x244.png 1.53-1.55 / 2.70-2.72. The folding seat: 1.58 / 2.51 (p26)
_CUSHION, _HEADREST, _JUMP_HEADREST = 1.61, 2.71, 2.51
_SIT = _CUSHION + 0.124 / K                # seat point (m): SEATS dz -0.109 and the cushion's 15 mm under its top
_WHEEL = (_HIP + 0.545, _SIT + 0.40)       # steering wheel hub (m): Model 3's hub to hip and seat point, on this cab
# the dash's fore-aft reference (m; the hub's y before the seat moved forward): the dash, its trim, the screens on it
# stay against the windshield (p26: the glass at y 0.18 at the dash's top, 2.16 m) and the wheel comes 0.175 m closer
# to them on a shorter column
_DASH_Y = _DOOR_Y[1] + 1.225
# the folding seat behind the driver on the right (SEAT at): p26 draws its cushion front 1.56 m behind the driver's and
# p03-x20.png (top view) its centre 0.46 x that apart to the right of the driver's [INFERENCE: +-0.05, no scale bar]
_JUMP_X, _JUMP_BACK = 0.72, 1.52


def _tall(top, recline=10):
    """SEATS head / back / back_z (cabin.py bucket, grid over the seat's z0) putting the headrest's top front edge `top`
    m up: z0 is 15 mm over the cushion's top, the recline turns about z0 - 0.03 and 0.02 ahead of the headrest's front,
    the 0.17 headrest's top 0.115 over that pivot past `head`; the backrest from its usual foot (z0 - 0.03) 2 cm into
    the headrest"""
    head = ((top - _CUSHION) * K + 0.015 + 0.02 * math.sin(math.radians(recline))) / math.cos(math.radians(recline)) \
        - 0.115
    back = head - 0.035
    return dict(head=round(head, 4), back=round(back, 4), back_z=round(back / 2 - 0.03, 4), recline=recline)


CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_semi",
    NAME="MinidoracatTesla_Semi",
    SCRIPT_MARK="---- geometry (TeslaSemi)",
    APP_CAR="app_car_semi_{}.png",
    DIMS=(round(1.19 + 6.67, 4), 2.517, 3.98),   # PREP.md 0: nose to tail, cab width (no mirrors), roof
    PORT_NOTE="[INFERENCE] the truck's left side behind the cab, at the frame's height (MCS port; not measured)",
    PAINTS=[("White", None)],
    # [INFERENCE] a white paint's dark / median / bright (no calibration shot yet: E2E)
    PAINT_CHART={"White": ((150, 152, 156), (206, 208, 211), (242, 243, 245))},
    CAL={"White": ((1.0, 1.0, 1.0), (0.0, 0.0, 0.0))},
    COMPOSITOR_MODEL="",
    OFFICIAL_OPTS="",
    RAMP=dict(t=(0.0, 1.0), u=(0.0, 1.0), wheels=()),   # (official_ramp: unused, no design-studio renders)
    # ---- pzveh: wheel. 22.5" aluminium disc wheels (prep RIM_R 0.29 m on 0.49 m tyres). Tesla's LR spec picture
    # (Semi-LR-Specs-Desktop.jpg, the front wheel at px 760-960 x 870-1060): the front a polished disc out to the tyre,
    # its dark hub to 0.37 of the rim's radius, ten lug nuts round 0.50 and ten round hand holes (radius 0.10) round
    # 0.77: the face on the disc's planar UV, those drawn in the texture (WHEEL_FACETS pattern, no faces). The drive
    # axles (px 1440-1720 x 800-1040): flat dark covers (axle_face, the `cap` grey) with a small lighter centre disc
    # (axle_cap: the hub cap in WHEEL_RGB `lit`)
    WHEEL_RIM=round(0.29 / 0.49, 4),
    WHEEL_SPOKE=dict(n=0, shape=dict(outer=((0.22, 0.045), (1.0, 0.066)), inner=((1.0, 0.0),)),
                     cap=0.22, inset=-0.0107, dish=0.002, depth=0.004, sweep=0.0, at=0.0),
    WHEEL_FACETS=dict(sink=0.0, rings=4, face="facet", n=0, at=0.0, shapes=(), axle_face="cap", axle_cap="lit",
                      pattern=dict(face="facet", marks=(("hat", 1, 0.0, 0.37, 0.37), ("spoke", 10, 0.50, 0.07, 0.07),
                                                        ("dark", 10, 0.77, 0.10, 0.10)))),
    WHEEL_DISC=dict(rotor=0.5, hat=0.3),
    WHEEL_RGB=dict(spoke=60, cap=60, barrel=12, lip=14, rotor=20, hat=20, dark=10, gap=8, tire=(26, 32), tread=22,
                   facet=60, lit=110),
    WHEEL_TINT={"facet": (235, 237, 242), "cap": (62, 62, 66)},          # facet: polished, near the top of the curve
    TIRE_SHOULDER=(0.055, 0.012),
    TIRE_BULGE=(0.0066, 0.026),
    # ---- pzveh: vehicle script (OY, CAB_BOX: unused, PHYS gives the boxes and the offsets)
    OY=0.0,
    WHEEL_LIFT=0.11,
    WHEEL_INSET=0.0,
    CAB_BOX=(0.0, 0.0, 0.0),
    # physics, prep metres (pzveh.geometry PHYS): the prototype MTSemiProto_A2S. body: the extents box (x, y, z ranges);
    # com: (y, height) the centre of mass, 40 % of the axles' load on the front (y = 0.40 x the drive axles' mean),
    # 0.55 grid up; boxes: the cab, the frame behind it, the two stops either side of the fifth wheel (a trailer's
    # nose stops on them); wheels: (name, x, y), the rear pair one wheel each on the centre line at the two drive
    # axles (drawn with the whole-axle model, axle: its four tyres' x); attach: (name, point, canAttach)
    PHYS=dict(
        com=(-0.40 * (4.42 + 5.64) / 2, 0.55 / K),
        body=((-1.2585, 1.2585), (-6.67, 1.19), (0.0, 3.98)),
        boxes=(((-1.2585, 1.2585), (-3.28, 1.19), (0.45, 3.98)),
               ((-1.2585, 1.2585), (-6.67, -3.28), (0.45, 1.01)),
               ((-1.48, -1.38), (-4.08, -3.28), (1.5, 3.5)),
               ((1.38, 1.48), (-4.08, -3.28), (1.5, 3.5))),
        wheels=(("FrontLeft", -_WF["track_m"] / 2, _WF["y"]), ("FrontRight", _WF["track_m"] / 2, _WF["y"]),
                ("RearLeft", 0.0, _WD["y"][0]), ("RearRight", 0.0, _WD["y"][1])),
        tyre=(0.49, 0.27),
        axle=(-_WD["x"][0], -_WD["x"][1], _WD["x"][1], _WD["x"][0]),
        attach=(("mtsemi_fifthwheel", (0.0, -5.08, 1.19), "mtsemi_kingpin"),),
    ),
    # seats: the driver on the centre line (front_x 0: the wheel and column there too), _HIP 0.325 m ahead of the door
    # opening's middle (back); the folding seat (SEATS jump) behind it on the right (_JUMP_X, _JUMP_BACK). at: each
    # front passenger's (mesh x, y shift[, SEATS entry]); FrontLeft the driver, FrontRight the folding seat
    # (PassengerSeat2). Both get in and out beside the driver's hip, in the door opening (pzveh: position outside)
    SEAT=dict(x=0.0, front_x=0.0, h=round(_SIT * K - 0.02, 4), z=round(_SIT * K - _ZC, 4),
              back=(round(((_DOOR_Y[0] + _DOOR_Y[1]) / 2 - _HIP) * K, 4),), out=0.30, front_only=True,
              at={"FrontLeft": (0.0, 0.0), "FrontRight": (round(_JUMP_X * K, 4), round(-_JUMP_BACK * K, 4), "jump")}),
    # a truck's upright seat (scripts/seat_anim.py POSES) against the backrest p26-x264.png draws, 10 deg back (_tall):
    # the body upright, the thighs and calves set back onto the cushion and the floor 0.41 m under it (seat_head.py
    # 2026-11-18: sit -12..4, back -20..-10 / -7..3, feet 2 mm; Bip01 10 left the back 51-95 mm in the backrest,
    # Bip01 -5 without the calves the feet 28 mm in the floor); this one fits both seats
    SEAT_POSE={"front": [("Bip01", -5.0), ("Bip01_L_Thigh", -8.0), ("Bip01_R_Thigh", -8.0),
                         ("Bip01_L_Calf", 14.0), ("Bip01_R_Calf", 14.0)]},
    BODY_W_Z=0.40,                         # (under the mirrors: 0.40 x 3.98 = 1.59 m, the mirror arms from 1.67)
    # rear-hinged doors (PREP.md: the handle at the front edge), 65 deg about the upright at their rear edge
    DOORS={"DoorFrontLeft": (-1, (0, 0, 1), 65, 0.8), "DoorFrontRight": (1, (0, 0, 1), -65, 0.8)},
    DOOR_HINGE={"DoorFrontLeft": _g(_HX, _HY, 0.0), "DoorFrontRight": _g(-_HX, _HY, 0.0)},
    GATE_IN=(0.0, 0.894, -0.447),
    GATE_HINGE="top",
    # ---- convert.py: the source (TMP, gitignored: a copy of the prep's output)
    SRC=("semi_src.blend",),
    SRC_C=(0.0, 0.0),
    SRC_YFRONT=0.0,
    SRC_SCALE=1.0,
    SRC_STRETCH=(-1.0, -1.0, 1.0),
    SRC_FLIP=False,
    BELT_Z=round(1.85 * K, 4),             # the door glass's foot (PREP.md)
    TIRE_OBJ="Tyre_",
    DROP=("Tyre_", "Cover_", "Hub_"),     # (the wheels are pzveh's: the shell's tyres, covers and hubs stay out)
    DROP_COMPS=(),
    ARCH_LINER=None,
    PLATES=(),
    SEAL_CLIP=True,
    SEAL_NONE=("DoorFrontLeft", "DoorFrontRight"),   # (the prep's grooves: the doors share their edges with the body)
    RAIL=None,
    # the whole car near the Model X's 123k triangles (the Cybercab ships 132k; models.md budget)
    DECIMATE={"Paint": 22000, "Trim": 5000, "Liner": 4000, "Frame": 6000, "SkirtGrey": 9000, "RearWall": 4000,
              "Glass_Windshield": 1200, "Glass_Door": 700, "Glass_Vent": 500, "HeadLight": 800},
    DECIMATE_KEEP_BOUNDARY=True,
    DECIMATE_HOLD_UNDER=True,
    DECIMATE_THIN=(round(0.0003 * K, 6), round(0.02 * K, 4)),
    DECIMATE_SNAP=round(0.001 * K, 6),
    DECIMATE_SMOOTH={"Paint": round(0.04 * K, 4), "Trim": round(0.04 * K, 4)},
    DECIMATE_CREASE={},
    # the shell is not quite X symmetric: the symmetric collapse folded 61 paint triangles over (the rear side panels'
    # dark diagonal stripes) and 58 on the skirts; the collapse leaves the winding as modelled, and the recalc after it
    # turned the cab liner's inward faces all outward (pzveh.decimate)
    DECIMATE_SYMMETRY=False,
    DECIMATE_RECALC=False,
    # the shell's nose and waist lines are shading only (prep_semi.shade_normals: the custom normals lean off the line);
    # load_source keeps the corner normals and the snap resamples them off the fine mesh, so they survive the collapse.
    # 31 of the source's mirror-arm corners point against their faces, and the snap took ~430 off thin parts' far sides
    # (Frame, Paint, Trim): those take their face's normal
    NORMALS_UNREVERSE=True,
    # the decimated objects' shared open edges (the shell's seams, 1 mm: Paint / Frame 5901 points, Paint / SkirtGrey
    # 922, RearWall / SkirtGrey 693, Paint / Trim 505, Liner / Trim 293, Liner / SkirtGrey 157, Frame / SkirtGrey 106)
    SEAM_SHARE=tuple((a, b, round(0.001 * K, 6)) for a, b in (
        ("Paint", "Frame"), ("Paint", "SkirtGrey"), ("RearWall", "SkirtGrey"), ("Paint", "Trim"), ("Liner", "Trim"),
        ("Liner", "SkirtGrey"), ("Frame", "SkirtGrey"))),
    PAINT_MAT="Paint",
    # a later shell's new material drawn as Trim until MAT_RGB names it (convert.py prints SRC_UNKNOWN)
    SRC_UNKNOWN="Trim",
    UV_FILL=True,
    UV_FILL_TONE=True,
    HGT_CORNER=True,
    GROOVE_INK=None,
    # sRGB 230 x the shell's ratio to the white paint (prep_semi.py COLORS: base = 0.80 x q ** 2.2): the skirts and
    # deflector 0.30, frames, pillars and mirrors 0.15, the rear wall 0.20, the fenders 0.50; the lamps' lenses unlit
    MAT_RGB={"Trim": (34, 34, 36), "Liner": (24, 24, 26), "Glass": (26, 30, 34), "HeadLight": (106, 108, 114),
             "SkirtGrey": (69, 69, 71), "Frame": (34, 34, 36), "Mirror": (34, 34, 36), "RearWall": (46, 46, 48),
             "Fender": (114, 114, 116), "TailLight": (125, 43, 43), "BrakeLight": (136, 48, 48),
             "MarkerLight": (220, 140, 50), "ReflectorRed": (186, 43, 43), "ReflectorWhite": (223, 223, 223)},
    RECOLOR=(),
    CARBON=None,
    LIP_SHADE=None,
    GLASS_MATS=("Glass",),
    GLASS_OPAQUE=(),
    LENS_FLAT=(),
    GLASS_BACKS=("WinLH", "WinLT", "WinRH", "WinRT"),
    ROOF_PANE="-",
    MIRROR_CAP="-",
    # lit with the headlights: the light bar and wedge lamps (HeadLight) and the five amber marker lights over the
    # windshield (MarkerLight, lit amber) in LightLH / LightRH, the round tail lamps' rings (TailLight, lit at 3/4 of
    # the brake red: the shell's emission 0.6 / 0.8) in LightLT / LightRT; lit when braking: the tail lamps' centres
    # (BrakeLight, the full tail red) in StopL / StopR. The reflectors stay unlit
    LAMPS=dict(head=("HeadLight", "MarkerLight"), tail=("TailLight",), tail_z=0.0, tail_y=0.0, blade=None,
               brake_objs=("BrakeLight",), lit_rgb={"MarkerLight": (255, 140, 20), "TailLight": (191, 22, 22)}),
    # part lines (y, z): the door's rear edge
    LINES={k: (_g(_DOOR_Y[1], _DOOR_Z[0]), _g(_DOOR_Y[1], _DOOR_Z[1])) for k in ("S", "BF")},
    FRONT_Y=round(_DOOR_Y[0] * K, 4), SILL_Z=round(_DOOR_Z[0] * K, 4), ARCH=(0.0, -9.0),
    IN_DOOR=dict(up=round(1.85 * K, 4), x=0.40),
    IN_GATE=dict(y=-9.0, z=9.0, up=9.0, x_up=0.0),
    # door front edge, rear edge, the cabin's ring cut (its rear wall inside, semi_lines.json cabin_y)
    DOOR_Y=_g(_DOOR_Y[0], _DOOR_Y[1], _CAB_R),
    GATE_Z=round(_FLOOR * K, 4),           # (no trunk lid: the cabin floor)
    REAR_ARCH=(*_g(_WD["y"][0], _WD["r"]), round(0.29 * K, 4)),
    GATE_X=0.0,
    STOP_X=0.0,
    PANELS=dict(x=9.0, z=-9.0, front=(9.0, 9.0), rear=(9.0, 9.0), gate=(-9.0, 9.0), lid=(9.0, 9.0)),   # (PANEL_PARTS)
    PANEL_PARTS={1: "DoorFrontLeft", 2: "DoorFrontRight"},
    # front guards ahead of the doors, rear guards behind the cab (the grey fenders: GUARD_REAR_MATS); the ends' trim
    # in Head / Tail
    GUARDS=dict(front=(round(_DOOR_Y[0] * K, 4), round(1.40 * K, 4), round(0.80 * K, 4)),
                rear=(round(-3.64 * K, 4), round(1.40 * K, 4), round(0.80 * K, 4))),
    GUARD_REAR_MATS=("Fender",),
    HEAD_TAIL=(round(0.60 * K, 4), round(-6.20 * K, 4)),
    DAMAGE_OWN=8,
    CUT={},
    PLANES={},
    CUT_X=("-",),
    CUT_X_Y=-9.0,
    DOOR_OBJS=(),
    GATE_OBJS=(),
    GATE_COMPS=(),
    GATE_CUT_COMPS=(),
    PART_OBJS={},
    PANES={"Body": {"WinT", "WinLT", "WinRT"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"}},
    T_BADGE=None,
    TESLA=None,
    LENS_X=0.0,
    BADGE_Y=(-9.0, -9.0),
    BLADE=False,
    MODELY=None,
    PERF_BADGE=None,
    CALIPER=None,
    FRUNK_TUB=None,
    PORT=_g(-3.45, 1.10),                  # (a ray from the left onto the side: pzveh PORT_X None)
    PORT_X=None,
    # ---- cabin.py (mesh coords, centred)
    CABIN_FLOOR=_c(0, _FLOOR)[1],
    CABIN_FRONT_Y=_c(_CAB_F),
    TRUNK_Y=_c(_CAB_R),
    CABIN_ZC=_c(0, 2.30)[1],
    SEAM_CLEAR=0.065,
    TRUNK_WALL=False,
    HUMP_BACKS=False,
    DOOR_RISER=True,                       # (cabin.py: the floor 0.48 m over the door openings' lower edge)
    # dz -0.109: the cushions 15 mm higher than the family's -0.121, under the upright pose's hips (seat_head.py sit);
    # tall truck seats, the headrests' tops where p26-x264.png draws them (_tall)
    SEATS=dict(front=dict(w=0.44, **_tall(_HEADREST), dy=0.059, dz=-0.109),
               jump=dict(w=0.40, **_tall(_JUMP_HEADREST), dy=0.048, dz=-0.109),
               sill=None, bin=None),
    PARCEL=None,
    # a wide dash across the cab (no console: the centre seat), the wheel on the centre line, a screen each side of it
    # turned toward the driver: ERG 2026 p.6 (p06-x73.png, the driver's view) draws two equal screens, each 0.92 of the
    # wheel's width wide and 0.50 tall, their centres 0.99 wheel widths out of the wheel's and a little over its hub; p.5
    # (p05-x66.png, from above) both turned in, ~25 deg [INFERENCE: sizes against this wheel (0.42 m), the screens
    # behind it drawn smaller: 0.40 x 0.22 m, centres +-0.45 m]
    DASH=dict(size=(1.80, 0.34, 0.16), console=None,
              dash=(0, _c(_DASH_Y + 0.525), _c(0, _WHEEL[1])[1] - 0.081),
              trim=(0, _c(_DASH_Y + 0.315), _c(0, _WHEEL[1])[1] - 0.061),
              light=(0, _c(_DASH_Y + 0.317), _c(0, _WHEEL[1])[1] - 0.085),
              stands=tuple((s * round(0.45 * K, 4), _c(_DASH_Y + 0.33), _c(0, _WHEEL[1])[1] + 0.013) for s in (-1, 1)),
              screens=tuple(((s * round(0.45 * K, 4), _c(_DASH_Y + 0.30), _c(0, _WHEEL[1])[1] + 0.10), -s * 25)
                            for s in (-1, 1)),
              screen_size=(round(0.40 * K, 4), round(0.22 * K, 4)),
              wheel=_c(*_WHEEL)),
    DOOR_CARD={
        "front": [
            ("armrest pocket", "rear", 0.10, -0.205, 0.50, 0.085, 0.030, "base", 0.020),
            ("armrest", "rear", 0.12, -0.262, 0.44, 0.030, 0.070, "bed_wall_mid", 0.012),
            ("pull handle", "rear", 0.20, -0.195, 0.22, 0.020, 0.040, "screen_back", 0.008),
            ("speaker grille", "front", 0.06, -0.47, 0.17, 0.13, 0.010, "wheel", 0.030),
        ],
    },
    DOOR_INNER=dict(cell="bed_floor"),
    SLAB_SEAM_DARK=(0.0015, round(0.06 * K, 4)),
    LINER_UP=dict(cell="bed_rib", dz=0.0, y=_c(_CAB_R)),
    TRIM_BACKS=(),
    TRIM_BACKS_GLASS=round(0.03 * K, 4),
    PILLAR_COVER=dict(pairs=(("WinT", "WinLT"), ("WinT", "WinRT")), gap=round(0.15 * K, 4), depth=0.5, cell="bed_rib"),
    COWL_SHELF=dict(reach=round(0.40 * K, 4), cell="liner"),
    # TeslaArmor's visible kit (armor.py; keys as model_y.py's ARMOR): the front guard only (user 2026-11-22; no rear,
    # sill or roof piece, the 53 ft trailer none). keep: the front plate (the source has none: on the black bumper band's
    # centre, |x| half width, z bottom, top). The bar runs over it and under the lamp strip (z 0.81-0.90), thicker tube
    ARMOR=dict(
        keep=dict(front_plate=(0.20, 0.26, 0.40)),
        front=dict(z=0.55, top=0.75, x=0.88, corners=[(0.60, 0.86)], brackets=(0.28, 0.52), gap=0.045, r=0.032, sides=12,
                   bend=0.06),
        rear=None, sill=None, roof=None,
    ),
)
