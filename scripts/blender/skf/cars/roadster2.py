"""Roadster Rocket (the new Roadster's top version, 2026 unveiling): the mod's own body, built from Tesla's pictures alone
by scripts/blender/skf/prep_roadster2.py (no third-party model; references/roadster2.md). CAR=roadster2. Keys as in
model_y.py (each is the module constant it sets); built as cybercab.py (the prep's own .blend, every face its panel in
the face attribute `panel`: PANEL_PARTS). One seat (SEAT solo, template MinidoracatTeslaSoloNoFrunk: the passenger's
place holds the air tank), two butterfly doors, the trunk lid (the rear glass), the active rear wing (TeslaWing, the
charge port under it). One paint, Ano White. Grid units, pre-centre frame (+Y front, +Z up, -X car left, ground z 0;
the prep's metres x 0.826) unless noted. Milestone B2a: the butterfly doors' own axis, the wing on its struts, the
single seat and the air tank, the rear nozzles and fans (temp/plan-roadster2-1124/build/R2Body.md).
"""
import json
import math
import os
import pathlib

K = 0.826                                  # grid per metre (pzveh.K): the prep's numbers are metres


def _g(*m):
    return tuple(round(v * K, 4) for v in m)


def _door(sd, splay=15.0, up=90.0):
    """The butterfly door on side sd (-1 left): (axis, deg) of turning it `up` about the car's x through the A pillar's
    top, then `splay` outward about the vertical (official Slide-3 front over, x HVc6jW2XgAAULlb rear 3/4: the doors
    stand near upright over the opening's front, their tops a little out). R = Ry(-splay) Rx(-up) for the left door,
    its axis-angle with the sign turned (left: axis x > 0, deg < 0); the right one mirrors x and the angle."""
    cs, ss = math.cos(math.radians(splay)), math.sin(math.radians(splay))
    cu, su = math.cos(math.radians(up)), math.sin(math.radians(up))
    ax = (cs * su + su, ss * cu + ss, ss * su)
    n = math.sqrt(sum(a * a for a in ax))
    deg = math.degrees(math.acos((cs + cu + cs * cu - 1) / 2))
    return (round(-sd * ax[0] / n, 4), round(ax[1] / n, 4), round(ax[2] / n, 4)), round(sd * deg, 2)


# The prep's own numbers (metres in its frame: +Y front, ground 0) from a committed snapshot (cars/roadster2_body.json),
# as cybercab.py: a body round copies the prep's four files into temp/skf_r2, `python
# scripts/blender/skf/cars/roadster2.py` refreshes the snapshot, then build. A CAR=roadster2 build stops while the
# snapshot is behind temp/skf_r2.
_TMP = pathlib.Path(__file__).resolve().parents[4] / "temp" / "skf_r2"
_SNAP = pathlib.Path(__file__).with_name("roadster2_body.json")
_KEYS = {"prep_report.json": ("body_bbox", "wheels"),
         "roadster2_lines.json": ("door_left", "wing_hinge", "wing_lift", "charge_port_centre", "head_light_bar",
                                  "tail_light_bar", "seat", "copv")}


def _from_tmp():
    """The snapshot's keys as temp/skf_r2 has them (None without the prep's files there)."""
    if not all((_TMP / f).exists() for f in _KEYS):
        return None
    return {f: {k: json.loads((_TMP / f).read_text())[k] for k in ks} for f, ks in _KEYS.items()}


if __name__ == "__main__":
    _now = _from_tmp()
    if _now is None:
        raise SystemExit(f"cars/roadster2.py: no prep output in {_TMP}")
    _SNAP.write_text("{\n" + ",\n".join(f" {json.dumps(f)}: {{\n" + ",\n".join(
        f"  {json.dumps(k)}: {json.dumps(v, separators=(',', ':'))}" for k, v in d.items()) + "\n }"
        for f, d in _now.items()) + "\n}\n", newline="\n")
    print(f"cars/roadster2.py: wrote {_SNAP}")
_SNAPD = json.loads(_SNAP.read_text())
if os.environ.get("CAR") == "roadster2" and _from_tmp() not in (None, _SNAPD):
    raise SystemExit(f"cars/roadster2.py: {_SNAP.name} is behind {_TMP}: python scripts/blender/skf/cars/roadster2.py")
_REP, _LN = _SNAPD["prep_report.json"], _SNAPD["roadster2_lines.json"]
_WF, _WR = _REP["wheels"]["front"], _REP["wheels"]["rear"]
_FA, _RA = _WF["y"], _WR["y"]              # the axles' y (metres)
_BB = _REP["body_bbox"]
_YC = (_BB[0][1] + _BB[1][1]) / 2 * K     # stage_build centres the mesh on its bbox: the shift along y (grid)
_ZC = (_BB[0][2] + _BB[1][2]) / 2 * K     # ... and along z (GEOMETRY zmid)


def _c(y):
    """A pre-centre y (metres) as a centred mesh y (grid): the cabin's numbers."""
    return round(y * K - _YC, 4)


_DOOR = _LN["door_left"]
_DOOR_F = max(q[1] for q in _DOOR)         # the door's front (A pillar, 0.79) and rear (B pillar top) y
_DOOR_R = min(q[1] for q in _DOOR)
_PORT = _LN["charge_port_centre"]
_SEAT = _LN["seat"]                        # the H point (metres)
_WL = _LN["wing_lift"]                     # the wing open: move (metres), deg nose up
_TANK = _LN["copv"]                        # the air tank (metres)

CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_r2",
    NAME="MinidoracatTesla_Roadster2",
    SCRIPT_MARK="---- geometry (TeslaRoadster2)",
    APP_CAR="app_car_roadster2_{}.png",
    # length and height the prep's body (its bbox, on the 02 side view); width 1.88 (roadster2.md)
    DIMS=(round(_BB[1][1] - _BB[0][1], 4), round(_BB[1][0] - _BB[0][0], 4), round(_BB[1][2], 4)),
    PORT_NOTE="Roadster Rocket: under the rear wing, the left rear deck (Not a Tesla App #4850; roadster2.md)",
    PAINTS=[("AnoWhite", None)],
    # (dark, median, bright) sRGB: the official pictures are studio-dark (02 door p10 / p50 / p90 (42,42,52) /
    # (51,51,61) / (62,62,72): only the hue, 10 bluer than red); the Roadster 2.5's Arctic White chart (roadster.py)
    # cooled by that hue. [推測] until an E2E paint measure (CAL)
    PAINT_CHART={"AnoWhite": ((176, 181, 188), (202, 207, 214), (226, 230, 236))},
    # the Roadster's Arctic White fit (roadster.py CAL, same shader and white): [推測] until measured in game
    CAL={"AnoWhite": ((0.895, 0.882, 0.879), (0.0, 0.0, 0.0))},
    COMPOSITOR_MODEL="",
    OFFICIAL_OPTS="",
    RAMP=dict(t=(0.0, 1.0), u=(0.0, 1.0), wheels=()),   # (official_ramp: unused, no design-studio renders)
    # ---- pzveh: wheel (02): a dark grey flat disc nearly to the tyre (WHEEL_FACETS face), six straight black blades
    # from the hub to the rim, wider outward, a dark lip, a dark hub (B1: the light disc read near white in game, E2E
    # r2body-look-a3). Low-profile tyres: the rim flange 16 mm past the prep's disc (front 0.262, rear 0.265 m)
    WHEEL_RIM=round((0.262 + 0.016) / _WF["r"], 4),
    WHEEL_RIM_REAR=round((0.265 + 0.016) / _WR["r"], 4),
    WHEEL_SPOKE=dict(n=6, hub=0.12, shape=dict(outer=[(0.12, 0.06), (1.0, 0.10)], inner=[(1.0, 0.0)]), cap=0.12,
                     inset=0.010, dish=0.004, depth=0.012, sweep=0.10),
    WHEEL_FACETS=dict(sink=0.006, rings=4, face="facet", n=0, at=0.0, shapes=()),
    WHEEL_DISC=dict(rotor=0.5, hat=0.3),
    WHEEL_RGB=dict(spoke=10, cap=16, barrel=14, lip=20, rotor=20, hat=20, dark=10, gap=8, tire=(22, 28), tread=20,
                   facet=72, lit=72),
    # ---- pzveh: vehicle script
    OY=0.1978,
    WHEEL_LIFT=0.11,
    TIRE_AXLES=dict(front=(_WF["r"], _WF["w"]), rear=(_WR["r"], _WR["w"])),
    WHEEL_INSET=0.0,
    # the cabin's physics box (mesh coords): from the windscreen's foot to behind the seat
    CAB_BOX=(1.10, _c(0.75), _c(-0.92)),
    # one seat (solo: the driver's, the right side's place the air tank's), at the prep's H point (roadster2_lines.json
    # seat): behind the door opening's middle by back; low, in the Roadster's pose (SEAT_POSE)
    SEAT=dict(x=round(-_SEAT[0] * K, 4), h=0.27, z=-0.255,
              back=(round(((_c(_DOOR_F) + _c(_DOOR_R)) / 2 - _c(_SEAT[1])), 4),), out=0.30, front_only=True, solo=True),
    SEAT_POSE={"front": [("Bip01", 42.0), ("Bip01_L_Thigh", -20.0), ("Bip01_R_Thigh", -20.0)]},
    BODY_W_Z=0.55,
    # butterfly doors (_door); the trunk lid (the V rear glass, prep panel 4) about its front edge over the seat back
    # (prep REAR0, REAR_C), up; the wing (prep WING_LIFT, x HVc6jW2XgAAULlb / HVc6ftKXYAApLw-) lifted up and back on its
    # two struts (DOOR_LIFT: the move at full open) and its nose turned up about its front edge (wing_hinge)
    DOORS={
        "DoorFrontLeft": (-1, *_door(-1), 2.0), "DoorFrontRight": (1, *_door(1), 2.0),
        "TrunkDoor": (0, (1, 0, 0), -50, 1.0),
        "TeslaWing": (0, (1, 0, 0), _WL["deg"], 1.5),
    },
    DOOR_LIFT={"TeslaWing": _g(*_WL["move"])},
    DOOR_HINGE={"DoorFrontLeft": _g(-0.62, 0.72, 0.93), "DoorFrontRight": _g(0.62, 0.72, 0.93),
                "TrunkDoor": _g(0.0, -0.45, 1.06), "TeslaWing": _g(0.0, *_LN["wing_hinge"][0][1:])},
    GATE_IN=(0.0, 0.9, -0.44),
    GATE_HINGE="front",
    # ---- convert.py: the source (TMP, gitignored: a copy of the prep's output)
    SRC=("roadster2_src.blend",),
    SRC_C=(0.0, 0.0),
    SRC_YFRONT=0.0,
    SRC_SCALE=1.0,
    SRC_STRETCH=(-1.0, -1.0, 1.0),
    SRC_FLIP=False,
    BELT_Z=round(0.80 * K, 4),             # the side glass's foot
    TIRE_OBJ="Tyre_",
    # the tail's 4 bell nozzles (brass rings, x HVc6ftKXYAApLw- rear) over 4 fans in the black cavity
    DROP=("Tyre_", "Rim_", "Disc_"),
    DROP_COMPS=(),
    ARCH_LINER=None,
    PLATES=(),
    SEAL_CLIP=True,
    SEAL_NONE=("TeslaWing", "DoorFrontLeft", "DoorFrontRight"),
    RAIL=None,
    DECIMATE={},                           # (the prep's body is a few thousand faces)
    PAINT_MAT="Paint",
    # the doors' and wing's seams as SEAM_LINE strips (cybercab.py: a skin-drawn line breaks into dashes at game zoom)
    SEAM_LINE=dict(w=round(0.008 * K, 6), over=round(0.002 * K, 6), bridge=round(0.003 * K, 6), lift=round(0.001 * K, 6),
                   gap=round(0.025 * K, 6), glass=round(0.03 * K, 6), step=round(0.006 * K, 6), chain=round(0.04 * K, 6),
                   tone=0.5, flat=True, one_side=("DoorFrontLeft", "DoorFrontRight"),
                   wide={1: round(0.016 * K, 6), 2: round(0.016 * K, 6)}),
    # the lower body and nose band black-grey (03 / 08), the arches' liners black, the lamps' day colours (the head
    # lamps' slim lit bands white, the tail bar dark red), the rear plate light grey
    MAT_RGB={"Trim": (30, 30, 32), "Liner": (20, 20, 22), "Glass": (26, 30, 34), "HeadLight": (250, 252, 255),
             "TailLight": (112, 32, 36), "Dark": (14, 14, 16), "Plate": (206, 208, 212), "Nozzle": (150, 118, 72),
             "Fan": (46, 46, 50)},
    CARBON=None,
    GLASS_MATS=("Glass",),
    GLASS_OPAQUE=(),
    # the frag's darker glass level (pzveh GLASS_TINT_U; 1 mid, 2 deep): the official canopy reads near opaque, tea-brown
    GLASS_SHADE=1,
    GLASS_BACKS=("WinLH", "WinLT", "WinRH", "WinRT"),
    ROOF_PANE="GlassRoof",                 # the canopy behind the windscreen (prep ROOF_Y): zone LightBarL
    MIRROR_CAP="-",                        # (no mirrors: cameras)
    # brake: the tail bar's outer ends (|x| > 0.55 m x K; the bar's middle lit with the tail lights)
    LAMPS=dict(head=("HeadLight",), head_y=0.5, tail=("TailLight",), tail_z=0.3, tail_y=-1.0, blade=None,
               brake=("Body", round(0.55 * K, 4))),
    # part lines, side view (y, z): the door's rear edge (B pillar, prep door_outline)
    LINES={"S": (_g(-0.28, 0.33), _g(-0.378, 0.85)), "BF": (_g(-0.28, 0.33), _g(-0.378, 0.85))},
    FRONT_Y=round(0.95 * K, 4), SILL_Z=round(0.25 * K, 4), ARCH=(0.0, -9.0),
    IN_DOOR=dict(up=round(0.80 * K, 4), x=0.40),
    IN_GATE=dict(y=-9.0, z=9.0, up=9.0, x_up=0.0),
    # door front edge and rear edge (B pillar), the cabin's ring cut behind the seat (no door)
    DOOR_Y=_g(_DOOR_F, _DOOR_R, _RA + 0.55),
    GATE_Z=round(0.80 * K, 4),             # the wing's lower edge
    REAR_ARCH=(*_g(_RA, _WR["r"]), round(0.36 * K, 4)),
    GATE_X=0.0,
    STOP_X=0.0,
    PANELS=dict(x=9.0, z=-9.0, front=(9.0, 9.0), rear=(9.0, 9.0), gate=(-9.0, 9.0), lid=(9.0, 9.0)),   # (PANEL_PARTS)
    PANEL_PARTS={1: "DoorFrontLeft", 2: "DoorFrontRight", 3: "TeslaWing", 4: "TrunkDoor"},
    GUARDS=dict(front=(round(0.95 * K, 4), 0.80, 0.45), rear=(round((_RA + 0.75) * K, 4), 0.85, 0.45)),
    HEAD_TAIL=(round((_FA + 0.35) * K, 4), round((_RA - 0.45) * K, 4)),
    CUT={},
    PLANES={},
    CUT_X=("-",),
    CUT_X_Y=-9.0,
    DOOR_OBJS=(),
    GATE_OBJS=(),
    GATE_COMPS=(),
    GATE_CUT_COMPS=(),
    PART_OBJS={},
    # (the canopy: windscreen GlassTop WinT, roof GlassRoof LightBarL; the V rear glass the trunk lid's, GlassHatch)
    PANES={"Body": {"WinT", "LightBarL", "WinLT", "WinRT"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"},
           "TrunkDoor": {"WinH"}, "TeslaWing": set()},
    T_BADGE=None,
    TESLA=None,
    LENS_X=0.0,
    BADGE_Y=(-9.0, -9.0),
    BLADE=False,
    MODELY=None,
    PERF_BADGE=None,
    CALIPER=None,
    FRUNK_TUB=None,                        # (no front trunk)
    # charge port under the wing (roadster2_lines.json charge_port_centre)
    PORT=_g(_PORT[1], _PORT[2]),
    PORT_X=round(_PORT[0] * K, 4),
    # ---- cabin.py (mesh coords, centred): the Roadster 2.5's simple cabin (roadster.py) with one bucket (SEAT solo)
    # and the air tank (TANK, roadster2_lines.json copv) in the passenger's place, no centre console (the tank's side)
    CABIN_FLOOR=-0.37,
    CABIN_FRONT_Y=_c(0.95),
    TRUNK_Y=_c(-0.92),                     # behind the reclined backrest (cabin.py: -0.71 grid at -0.55 m)
    CABIN_ZC=-0.10,
    SEAM_CLEAR=0.065,
    SEATS=dict(front=dict(w=0.40, back=0.36, recline=28, head=0.47, dy=-0.066, dz=-0.085, cushion=0.035), sill=None,
               bin=None),
    PARCEL=None,
    DASH=dict(size=(0.84, 0.20, 0.16), console=None, dash=(0, _c(0.75), 0.04), trim=(0, _c(0.673), 0.075),
              light=(0, _c(0.675), 0.051), stand=(0, _c(0.71), 0.05), screen=(0, _c(0.665), 0.05),
              wheel=(round(-_SEAT[0] * K, 4), 0.033)),
    TANK=dict(at=(round(_TANK["centre"][0] * K, 4), _c(_TANK["centre"][1]), round(_TANK["centre"][2] * K - _ZC, 4)),
              r=round(_TANK["r"] * K, 4), half=round(_TANK["length"] / 2 * K, 4), dome=round(_TANK["dome"] * K, 4)),
    # the tank light grey (a metal liner's sheen: it reads through the mid glass), its straps black
    CABIN_CELL_MAP=dict(tank="bed_rim", strap="screen_back"),
    DETAIL_CELL_MAP=dict(tank="chrome", strap="mat"),
    DOOR_CARD={
        "front": [
            ("upper trim", "end", (0.08, 0.10), -0.050, None, 0.060, 0.030, "dash", 0.012),
            ("armrest", "rear", 0.07, -0.215, 0.44, 0.050, 0.085, "seat", 0.018),
            ("pull handle", "rear", 0.13, -0.165, 0.26, 0.026, 0.050, "dash", 0.010),
            ("map pocket", "end", (0.10, 0.30), -0.320, None, 0.070, 0.040, "base", 0.015),
        ],
    },
    # TeslaArmor's visible kit (armor.py; model_y.py ARMOR has the keys): steel tubes as the Roadster 2.5's, low over
    # the black nose band and the tail's black lower face, under the head lamps and the rear plate (keep: prep PLATE,
    # HEAD_LAMP; no front plate); the rear hoops outside the outer nozzles (x 0.354 m, r 0.036: 0.32 grid)
    ARMOR=dict(
        keep=dict(rear_plate=_g(0.153, 0.504, 0.656), head_lamps=_g(0.59, 0.66, 0.42, 0.50)),
        front=dict(z=0.13, top=0.28, x=0.52, corners=[(0.24, 0.40)], brackets=(0.15, 0.36), gap=0.025, r=0.020, sides=10,
                   bend=0.045),
        rear=dict(z=0.20, top=0.40, x=0.62, corners=[(0.36, 0.52)], brackets=(0.12, 0.30), gap=0.025, r=0.020, sides=10,
                  bend=0.045),
        sill=dict(z=0.16, y=(-0.70, 0.62), r=0.020, sides=10, gap=0.012, bend=0.045, brackets=(-0.40, 0.0, 0.40)),
        roof=None,
    ),
)
