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
_FLOOR = _LN["cabin_floor_z"]
_CAB_F, _CAB_R = _LN["cabin_y"]
# stage_build centres the mesh on its bbox: the cabin's numbers below are mesh (centred) coordinates
_YC, _ZC = (_BB[0][1] + _BB[1][1]) / 2 * K, (_BB[0][2] + _BB[1][2]) / 2 * K


def _c(y, z=None):
    """centred mesh y (and z) of a prep point in metres"""
    return round(y * K - _YC, 4) if z is None else (round(y * K - _YC, 4), round(z * K - _ZC, 4))


_HIP = _DOOR_Y[1] + 0.68                  # the driver's hip (m): 0.15 m ahead of the door opening's middle
_CUSHION = _FLOOR + 0.45                   # the cushion's top (m) [INFERENCE: a truck seat over the 0.80 floor]
_WHEEL = (_HIP + 0.545, _CUSHION + 0.40)   # steering wheel hub (m): Model 3's hub to hip and cushion, on this cab

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
    # ---- pzveh: wheel. 22.5" aluminium disc wheels (prep RIM_R 0.29 m on 0.49 m tyres), a flat silver face with a hub
    WHEEL_RIM=round(0.29 / 0.49, 4),
    WHEEL_SPOKE=dict(n=0, shape=dict(outer=((0.22, 0.045), (1.0, 0.066)), inner=((1.0, 0.0),)),
                     cap=0.22, inset=-0.0107, dish=0.002, depth=0.004, sweep=0.0, at=0.0),
    WHEEL_FACETS=dict(sink=0.0, rings=4, face="facet", n=0, at=0.0, shapes=()),
    WHEEL_DISC=dict(rotor=0.5, hat=0.3),
    WHEEL_RGB=dict(spoke=60, cap=60, barrel=12, lip=14, rotor=20, hat=20, dark=10, gap=8, tire=(26, 32), tread=22,
                   facet=60, lit=60),
    WHEEL_TINT={"facet": (176, 178, 182), "cap": (120, 122, 126)},
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
    # seats: the driver on the centre line (front_x 0: the wheel and column there too), 0.15 m ahead of the door
    # opening's middle (back); the folding seat (SEATS jump) behind it on the right, 1.0 m back (ERG p5). at: each front
    # passenger's (mesh x, y shift[, SEATS entry]); FrontLeft the driver, FrontRight the folding seat (PassengerSeat2)
    SEAT=dict(x=0.0, front_x=0.0, h=round(_CUSHION * K - 0.02, 4), z=round(_CUSHION * K - _ZC, 4),
              back=(round(((_DOOR_Y[0] + _DOOR_Y[1]) / 2 - _HIP) * K, 4),), out=0.30, front_only=True,
              at={"FrontLeft": (0.0, 0.0), "FrontRight": (round(0.70 * K, 4), round(-1.0 * K, 4), "jump")}),
    # a truck's upright seat (scripts/seat_anim.py POSES): the shared front pose leans 25 deg and left the back 63-102 mm
    # in the backrest and the feet 157 mm over the cab floor (seat_head.py, 2026-11-18); this one fits both seats
    SEAT_POSE={"front": [("Bip01", 10.0), ("Bip01_L_Thigh", -10.0), ("Bip01_R_Thigh", -10.0)]},
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
    DROP=("Tyre_", "Cover_"),
    DROP_COMPS=(),
    ARCH_LINER=None,
    PLATES=(),
    SEAL_CLIP=True,
    SEAL_NONE=("DoorFrontLeft", "DoorFrontRight"),   # (the prep's grooves: the doors share their edges with the body)
    RAIL=None,
    # Paint / Trim: the whole car near the Model X's 123k triangles (the Cybercab ships 132k; models.md budget)
    DECIMATE={"Paint": 22000, "Trim": 24000, "Liner": 4000, "Glass_Windshield": 1200, "Glass_Door": 700,
              "Glass_Vent": 500, "HeadLight": 800},
    DECIMATE_KEEP_BOUNDARY=True,
    DECIMATE_HOLD_UNDER=True,
    DECIMATE_THIN=(round(0.0003 * K, 6), round(0.02 * K, 4)),
    DECIMATE_SNAP=round(0.001 * K, 6),
    DECIMATE_SMOOTH={"Paint": round(0.04 * K, 4), "Trim": round(0.04 * K, 4)},
    DECIMATE_CREASE={},
    SEAM_SHARE=(("Paint", "Trim", round(0.001 * K, 6)), ("Paint", "Liner", round(0.001 * K, 6))),
    PAINT_MAT="Paint",
    # the shell's later parts (round 2: new objects, new materials) drawn as Trim until MAT_RGB names them (convert.py)
    SRC_UNKNOWN="Trim",
    UV_FILL=True,
    UV_FILL_TONE=True,
    HGT_CORNER=True,
    GROOVE_INK=None,
    MAT_RGB={"Trim": (34, 34, 36), "Liner": (24, 24, 26), "Glass": (26, 30, 34), "HeadLight": (106, 108, 114),
             "TailLight": (88, 62, 62)},
    RECOLOR=(),
    CARBON=None,
    LIP_SHADE=None,
    GLASS_MATS=("Glass",),
    GLASS_OPAQUE=(),
    LENS_FLAT=(),
    GLASS_BACKS=("WinLH", "WinLT", "WinRH", "WinRT"),
    ROOF_PANE="-",
    MIRROR_CAP="-",
    # the light bar across the nose (HeadLight); the tail lamps on the frame's end (TailLight), no brake lamps by |x|
    LAMPS=dict(head=("HeadLight",), tail=("TailLight",), tail_z=0.0, tail_y=0.0, blade=None),
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
    # front guards ahead of the doors, rear guards behind the cab; the ends' trim in Head / Tail
    GUARDS=dict(front=(round(_DOOR_Y[0] * K, 4), round(1.40 * K, 4), round(0.80 * K, 4)),
                rear=(round(-3.64 * K, 4), round(1.40 * K, 4), round(0.80 * K, 4))),
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
    # dz -0.109: the cushions 15 mm higher than the family's -0.121, under the upright pose's hips (seat_head.py sit)
    SEATS=dict(front=dict(w=0.44, back=0.50, recline=20, dy=0.059, dz=-0.109),
               jump=dict(w=0.40, back=0.50, recline=20, dy=0.048, dz=-0.109),
               sill=None, bin=None),
    PARCEL=None,
    # a wide dash across the cab (no console: the centre seat), the wheel on the centre line, the screen on its right
    DASH=dict(size=(1.80, 0.34, 0.16), console=None,
              dash=(0, _c(_WHEEL[0] + 0.525), _c(0, _WHEEL[1])[1] - 0.081),
              trim=(0, _c(_WHEEL[0] + 0.315), _c(0, _WHEEL[1])[1] - 0.061),
              light=(0, _c(_WHEEL[0] + 0.317), _c(0, _WHEEL[1])[1] - 0.085),
              stand=(0.35, _c(_WHEEL[0] + 0.33), _c(0, _WHEEL[1])[1] + 0.013),
              screen=(0.35, _c(_WHEEL[0] + 0.30), _c(0, _WHEEL[1])[1] + 0.10),
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
    SLAB_BELT_PRE=True,
    SLAB_SEAM_DARK=(0.0015, round(0.06 * K, 4)),
    LINER_UP=dict(cell="bed_rib", dz=0.0, y=_c(_CAB_R)),
    TRIM_BACKS=(),
    TRIM_BACKS_GLASS=round(0.03 * K, 4),
    PILLAR_COVER=dict(pairs=(("WinT", "WinLT"), ("WinT", "WinRT")), gap=round(0.15 * K, 4), depth=0.5, cell="bed_rib"),
    COWL_SHELF=dict(reach=round(0.40 * K, 4), cell="liner"),
)
