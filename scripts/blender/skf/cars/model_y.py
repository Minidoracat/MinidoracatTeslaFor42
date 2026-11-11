"""Model Y Performance (BloxBloger's "2026 Tesla Model Y Performance", Sketchfab, CC BY-NC 4.0, CREDITS.md) brought to
the owner's manual's size and the official renders' shape by scripts/blender/skf/prep_model_y.py (run it first: TMP/src/
source/Tesla Model Y Performance 2026.obj -> model_y.obj): everything the body pipeline needs to know about this car
and its source model. Picked with CAR=model_y (the default, pzveh.load). Each key is the module constant it sets:
pzveh.use (paths, script, wheel, paints), convert.py (source objects, part lines, badges), cabin.py (cabin layout).
Grid units, pre-centre frame (+Y front, +Z up, -X car left, ground z 0) unless noted; positions are the prepped
model's (the source's through prep's field); numbers and sources: .claude/skills/tesla-dev/references/models.md
section 0.
"""
import math

_CUT_X = ("Plane.034", "Plane.044", "Plane.045", "Plane.036", "Plane.042", "Plane.043", "Plane.041")  # rear lamps
# the light bar between the tail lamps (2026-11-12, official REAR34: a bright red bar with round ends in a black recess,
# as the Model Y L's, models-model-yl.md "標誌與燈條"): True the red bar (LAMPS blade_*, TESLA in dark red ink in it,
# Plane.034 back to its black); False the earlier smoked cover with black TESLA (8803c8b)
_RED_BAR = True


def _mx(v):
    return (-v[0], *v[1:])


def _corners(zn):
    """A left rear bumper corner's zone (convert.py CARBON keys) and its mirror on the right."""
    right = dict(zn, lo=(-zn["hi"][0], *zn["lo"][1:]), hi=(-zn["lo"][0], *zn["hi"][1:]))
    if "below" in zn:
        right["below"] = tuple((_mx(p), _mx(n)) for p, n in zn["below"])
    return zn, right


# the rear bumper's corners (official REAR34, all paints): a rounded recess in the paint's shadow, lighter at the top,
# a thin dark line along its front edge behind the arch, a black lower edge. The source's corner panel (Plane, a
# 418-tri component each side, mirror images; 428 with prep_model_y.py's FIELD slit, which closes the 3 cm opening
# between its sunk part's step and lip: it showed the cabin shell) is sunk there too, but its shape and crease differ:
# the recess is drawn in the skin (RECESS). Left side, pre-centre grid, the prepped model. _BLACK_TOP: (point, normal)
# of the official's black top through the fitted REAR34 camera (8 points unprojected onto the panel, plane fit within
# 2 mm; the model's sat 3-4 cm lower). _OUTLINE: the official's recess outline through the same camera (its dark front
# line, then the rounded corner and the top edge, unprojected onto the panel) in (s, z), s = position . (0.4971,
# -0.8677, 0) (across the corner, rearward); the front line run on down to the black
_BLACK_TOP = ((-0.5981, -1.8355, 0.4542), (0.2492, 0.8045, 0.5392))
_OUTLINE = ((1.1130, 0.3000), (1.1209, 0.3467), (1.1302, 0.3905), (1.1371, 0.4449), (1.1451, 0.4836),
            (1.1484, 0.5141), (1.1567, 0.5364), (1.1808, 0.5541), (1.2105, 0.5596), (1.2631, 0.5666),
            (1.3138, 0.5740), (1.3647, 0.5785), (1.3935, 0.5804))
_CORNER = ("Plane", 430)

CAR = dict(
    # ---- pzveh: paths and names. TMP: work dir under temp/ (source in TMP/src, official renders in TMP/official)
    TMP="skf",
    NAME="MinidoracatTesla_ModelY",        # vehicle script, FBX and texture file name
    SCRIPT_MARK="---- geometry (TeslaModelY)",   # the vehicle script's line after which the geometry block is ours
    APP_CAR="app_car_{}.png",              # phone App car image per paint (PhoneApp.lua)
    DIMS=(4.796, 1.920, 1.611),            # official Performance length, body width (no mirrors), height, metres
    PORT_NOTE="real Model Y",              # source of the charge port spot, written into the vehicle script's comment
    # official Model Y paints (decisions.md "車款外觀"): skin order = vehicle script skin index = Core.lua colors order;
    # saved games store the index (BaseVehicle.java:2635/2741), so after release only append
    PAINTS=[("StealthGrey", "PN01"), ("PearlWhite", "PPSW"), ("DiamondBlack", "PX02"), ("Quicksilver", "PN00"),
            ("UltraRed", "PR01"), ("GlacierBlue", "PB01"), ("MarineBlue", "PB02"), ("FrostBlue", "PB00")],
    # per-paint sRGB tone of the paint texels, tex = a * official-ramp colour / GAIN + b, one slope a for all three
    # channels (per-channel slopes turned the colour along the ramp: Ultra Red's G slope above R / B made its
    # highlights orange) and per-channel offsets b that put the in-game p50 on the official FRONT34 p50. a sets the
    # p25-p75 spread against FRONT34; Pearl White takes a = 0.8 (a = 1 burns 12% of its texels to 255). Fitted with
    # skf/convert.py PAINT_Q / PAINT_TARGET on in-game screenshots of the car heading S (modely-skin-sp, option 2,
    # closest zoom; tesla-gloss-skinA-1026a) and the game camera's visible texels (offline view). Calibration knob:
    # refit after changing the paint light; check with e2e/.../perf/paint_sheet.py
    CAL={
        "StealthGrey": ((0.88, 0.88, 0.88), (0.030, 0.016, 0.012)),
        "PearlWhite": ((0.80, 0.80, 0.80), (0.134, 0.129, 0.129)),
        "DiamondBlack": ((0.99, 0.99, 0.99), (0.073, 0.067, 0.063)),
        "Quicksilver": ((0.93, 0.93, 0.93), (-0.105, -0.114, -0.126)),
        "UltraRed": ((0.97, 0.97, 0.97), (-0.067, 0.078, 0.062)),
        "GlacierBlue": ((0.80, 0.80, 0.80), (0.003, -0.017, -0.029)),
        "MarineBlue": ((0.81, 0.81, 0.81), (0.084, 0.069, 0.039)),
        "FrostBlue": ((0.79, 0.79, 0.79), (0.072, 0.077, 0.100)),
    },
    # design studio (pzveh.stage_official): compositor model, options per paint code. The Performance trim (AGENTS.md
    # rule 7; $WY21A 21" Arachnid 2.0). Until 2026-10-26 the Long Range ($MTY79, $WY19P): its SIDE paint ramps differ
    # from these by under 1 level, so CAL stayed
    COMPOSITOR_MODEL="my",
    OFFICIAL_OPTS="$MTY70,${},$WY21A,$IPB14",
    # official_ramp: the SIDE render's paint rows t / columns u (car bbox fractions), wheel arches cut out (circles
    # round u wheels at row wt, radius wr of the width)
    RAMP=dict(t=(0.36, 0.74), u=(0.04, 0.96), wheels=(0.165, 0.80), wt=0.80, wr=0.135),
    # ---- pzveh: wheel, the Model Y Performance's 21" Arachnid 2.0 (design studio $MTY70,$WY21A, view RIMCLOSEUP):
    # five Y spokes in dark graphite, open between them onto a near-black wheel well; staggered 255/35 R21 front (r 356) /
    # 275/35 R21 rear (r 363): prep_model_y.py scales the source's tyres to those, a wheel model per axle (TIRE_AXLES)
    # on one rim. Spokes and hub cap are geometry (the gaps really open: the
    # vehiclewheel shader has no alpha cutout), the tire, rim flange, barrel and the disc behind the spokes a surface of
    # revolution (wheel_profile). The disc closes the wheel at its middle (x = +-WHEEL_DISC_X): dark behind the spokes
    # (WHEEL_DISC); the red calipers sit between it and the spokes but belong to the body
    # (convert.py calipers), they must not spin
    WHEEL_RIM=0.79,                        # rim flange radius / tire radius: the official lip ring 282 mm (camfit SIDE /
    #                                        FRONT34 / REAR34 ring fit, cams.json ring_radius_m) / 356 mm
    # staggered tyres (US manual 2026.38.3 PDF p.249, CN manual PDF p.210, "21 in (Performance)"): 255/35 R21
    # front, 275/35 R21 rear, radius 266.7 + 0.35 x section; prep_model_y.py scales the source's tyres to these
    # radii (its FIELD tyre). Rear: its own wheel model on the front's rim (models.md TIRE_AXLES)
    TIRE_AXLES=dict(front=(0.3560, 0.255), rear=(0.3629, 0.275)),
    # Y spoke (pzveh.spoke_outline `shape`, rr units = WHEEL_RIM x tire radius, tangential half widths): the left edge
    # from under the hub cap out to the barrel, then the window between the two arms back down to its tip. Read off the
    # official SIDE front wheel (PPSW and PN01, the five Ys unwrapped round the hub and folded onto one, median): the
    # stem widens from the cap, the arms fork at 0.52 and flare to +-25.5 deg at the lip round a +-15.5 deg window. Front
    # face `inset` grid inside the tire's half width at the barrel, `dish` deeper at the hub; side walls `depth` grid
    # deep. cap: hub cap radius; sweep: the spoke turned this much more (rad) at the barrel than at the hub; at: the
    # first spoke's angle (deg), the official SIDE front wheel's phase (a parked car shows it)
    WHEEL_SPOKE=dict(n=5, shape=dict(outer=((0.13, 0.02), (0.35, 0.069), (0.50, 0.127), (0.70, 0.259), (0.85, 0.353),
                                            (1.0, 0.445)),
                                     inner=((1.0, 0.272), (0.88, 0.25), (0.75, 0.186), (0.62, 0.12), (0.55, 0.07),
                                            (0.51, 0.0))),
                     cap=0.15, inset=0.020, dish=0.015, depth=0.018, sweep=0, at=35.7,
                     # the lit band (pzveh `lit`): the official spokes are lit along their middle and dark at the edges
                     # and walls (SIDE: >60 grey on 0.20-0.21 of the face ring, 40-60 on another 0.09-0.13; a flat face
                     # read lit on 0.31-0.33). Each arm and the stem 0.6 x as wide about its own centreline: the lit
                     # area 0.62 x the face's
                     lit=dict(outer=((0.13, 0.012), (0.35, 0.041), (0.50, 0.076), (0.55, 0.142), (0.62, 0.189),
                                     (0.70, 0.239), (0.85, 0.329), (1.0, 0.41)),
                                inner=((1.0, 0.307), (0.88, 0.274), (0.75, 0.207), (0.65, 0.153), (0.51, 0.0)))),
    WHEEL_LIP=True,     # the flange-to-barrel step in the flat `lip` grey: the official lip ring (SIDE ~65, 2 px)
    # brake rotor and its hat (rr units) kept under the hub cap: the official renders are black between the spokes
    # (SIDE 1-11 grey near the hub; RIMCLOSEUP shows the rotor only faintly), a 0.636 rotor at 60 read as one big grey disc
    WHEEL_DISC=dict(rotor=0.14, hat=0.12),
    # Game-screen sRGB grey levels (calibration knob, compare with game screenshots); pzveh.wheel_texture turns each
    # into the texture value that renders it. Lighting comes from the spokes' own normals. Official SIDE (PPSW / PN01,
    # front and rear): the spokes' lit band ~94-99 (median of >60), its edges and walls 47-50, the hub cap 25-30, the
    # lip ring ~85-92 (p90), between the spokes 4-6 (p25). The game reads ~1.1 x these (E2E 2026-11-12: spoke 100 ->
    # 110); offline (camfit, Workbench) this set reads lit 89-90, edge ~50, cap ~29, lip ~80, between ~16
    WHEEL_RGB=dict(spoke=82, edge=40, cap=16, barrel=18, lip=72, rotor=60, hat=35, dark=8, gap=8, tire=(22, 28),
                   tread=20),
    # ---- pzveh: vehicle script
    OY=0.2878,            # model offset == centerOfMassOffset (unscaled) = height of the mesh centre above the physics
    #                       CoM. Not ModernCar's 0.1978: the body, wheels, seats and attachments all hang off the model
    #                       offset (VehicleScript.toBullet :586-588, BaseVehicle.getPassengerLocalPos /
    #                       getAttachmentLocalPos), so this only lowers the CoM; 0.09 lower brakes like SportsCar
    #                       (MinidoracatTesla_template.txt wheelFriction)
    WHEEL_LIFT=0.11,      # rendered wheel sits this much (grid) above its script offset at rest: vanilla arch centres
    #                       minus wheel offsets, ModernCar +0.10/+0.16, SUV +0.12/+0.10 (arch circle fit); calibration knob
    WHEEL_INSET=0.0,      # tire outer face this far inside the body's own tire: track 1,650 / 1,630 (manual CN 1,654 /
    #                       1,636, US 1,636 / 1,622). Same cameras, tyre edge against the arch: official FRONT34 front
    #                       +2.75 / rear +1.7 px further out than at 0, REAR34 rear 0.4 px in (2 px per 10 mm); 0.03
    #                       put it ~9 px inside. Steered to 0.9 rad the front tyre pokes 202 mm past the body width
    #                       (offline, 8803c8b's 1,538 track: 149), no outer panel inside it (ray check, 2026-11-12)
    CAB_BOX=(1.284, 0.468, -1.595),   # the cabin physics box: width, front y, rear y (mesh, grid)
    # passengers and seats (pzveh.geometry, cabin.py): side x, seat height over the ground (script) and its mesh z
    # (centred), seat y = middle of the door opening minus `back` (front, rear row), getting out this far off the body
    # rear: the rear row sits this much lower. Heights from scripts/blender/skf/seat_head.py (2026-11-01): the seated
    # heads and caps under the roof, the feet on CABIN_FLOOR in the seated clips (scripts/seat_anim.py; the floor and
    # both rows follow the clips' hip-to-sole heights), SEATS dz / dy put the cushions and backrests against the body
    # front_x: the front row 2 mm inboard of the 2nd row, the outer foot off the front wheel well's inner wall (|x| 0.490,
    # the source's; seat_head.py legs 123 / 28 -> 138 / 42 mm, the gap 8803c8b's width scale took)
    SEAT=dict(x=0.326, front_x=0.324, h=0.516, z=-0.204, back=(0.12, 0.08), out=0.30, rear=0.017),
    BODY_W_Z=0.55,                         # body width (script extents) measured below this fraction of DIMS height
    # part: side (-1 = left, x < 0; 0 = tailgate), hinge axis, open angle (deg; sign swings the door out, the gate up),
    # clip seconds. Hinge points come from the cut (front edge on the outer skin; the gate's top edge; the frunk lid's
    # rear edge at the cowl, front rising like the real lid). The clips run open -> closed ("<Part>_closing", vanilla's
    # naming; Open plays it reversed). updateAnimationPlayer advances the clip 0.8 x real time x rate
    # (BaseVehicle.java:3901-3904): doors ~1 s, the gate ~4.5 s like an electric tailgate, the lid ~1.25 s
    DOORS={
        "DoorFrontLeft": (-1, (0, 0, 1), -65, 0.8), "DoorFrontRight": (1, (0, 0, 1), 65, 0.8),
        "DoorRearLeft": (-1, (0, 0, 1), -65, 0.8), "DoorRearRight": (1, (0, 0, 1), 65, 0.8),
        "TrunkDoor": (0, (1, 0, 0), -75, 3.6), "EngineDoor": (0, (1, 0, 0), 55, 1.0),
    },
    GATE_IN=(0.0, 0.894, -0.447),   # tailgate inward direction (forward and down: the glass leans, the panel stands)
    GATE_HINGE="top",               # the tailgate hinges at its top edge (a sedan's lid: "front")

    # ---- convert.py: the source (gitignored): prep_model_y.py's output from the OBJ inside the Sketchfab download
    SRC=("src", "source", "model_y.obj"),
    # OBJ (Blender import, -Z forward, Y up: front -X, left -Y) -> pre-centre frame, centres of the source bbox
    # (inspect prints them)
    SRC_C=(-1.0675, -1.787),               # source X (length) and Y (width) centre, metres; true to size (4.78 x 1.94 m)
    SRC_SCALE=1.0,                         # metres per source unit
    SRC_FLIP=False,                        # source front +X (glTF) instead of -X
    BELT_Z=0.840,                           # side window bottom (glass z min 0.878)
    TIRE_OBJ="Object005",                  # tires: wheel centres, radius and width (load_source)
    # what each source object is (names from the OBJ; sizes in the build log, or inspect)
    DROP=("Object005", "Cylinder", "Circle.", "Plane.027", "Plane.076", "Plane.088", "Plane.090", "Plane.026",
          "Plane.075", "Plane.087", "Plane.089",       # tires, rims, calipers, discs: the mod's procedural wheel stays
          "Object_11", "Object_12",                    # licence plates
          "Plane.031", "Plane.051", "Plane.053", "Plane.040",   # clear lamp covers: opaque in PZ, they'd hide the lamps
          "Plane.067", "Hyundai_KONA",   # BloxBloger's interior (tub, seats, dash): the mod's own cabin (cabin.py)
          "Tesla_Model_3"),              # rear TESLA: 1.2 cm block letters (E a solid block) sunk 4 cm under the blade
    DROP_COMPS=(),                         # (objects, lo, hi): drop their components centred in the box
    # black paint zones (convert.py classify): the rear bumper corners under the official's black top (_BLACK_TOP
    # above; CUT along it), black like the bumper (black_base)
    CARBON=dict(rgb=(34, 34, 36), zones=_corners(dict(lo=(-0.80, -1.95, 0.25), hi=(-0.47, -1.70, 0.56), of=_CORNER,
                                                       below=(_BLACK_TOP,)))),
    # the recess (above) in the skin, every paint: k[0] x the paint under its top edge to k[1] `depth` (grid) below
    # (official REAR34 PPSW: about 0.7 to 0.47 of the paint over it; PN01, PR01, PB01 alike), the edge blended over
    # +-`soft` (sub-texel: a texel here is ~8 mm), the dark front line `line` (width, k) (convert.py recess)
    RECESS=dict(of=_CORNER, t=(0.4971, -0.8677, 0.0), outline=_OUTLINE, rim=5, k=(0.75, 0.5), depth=0.07, soft=0.006,
                line=(0.014, 0.6)),
    ARCH_LINER=None,                       # dict(gap, inner, arc, n): procedural arch liners (the source has its own)
    PLATES=(),                             # (name, corners, facing, material): flat backing polygons
    SEAL_CLIP=False,                       # drop seal strips that pass through a surface (model_3.py); kept as built
    RAIL=None,                             # (z0, z1): paint up there in the median tone (model_3.py roof rails)
    # the panel gaps shaded in the skin (convert.py seam_shade, as Model X / S): the door, fender and hood gaps are
    # 3-5 mm, under a pixel at the closest zoom, so the gap alone came out a dotted line (body-edges-sp 2026-11-01).
    # The hood's gaps run level (any_slope) and at the doors' k stayed dotted (tesla-seam-after-S): 0.6 there
    SEAM_SHADE=dict(reach=0.02, width=0.010, k=0.35, steep=0.5,
                    parts=("DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight", "EngineDoor"),
                    any_slope={"EngineDoor": 0.6}),
    # collapse-decimated before anything else (target tris): detail PZ cannot show at 1-4 px per cm
    DECIMATE={"Plane.045": 400,             # 29.5k-tri honeycomb under the tail light bar
              "Plane.034": 1200, "Plane.020": 1000, "Plane.016": 2600},
    PAINT_MAT="Material_#2125780493",       # the body paint (skin colour from the official renders, textures())
    # skin colour (sRGB 0-255) of the source's other materials. Unlit tail lamp parts smoked like the Model Y L's
    # (official REAR34 / SIDE by day: the corner lamps' lens grey with a red hint, 88-93 / 73-81 / 77-86 there where
    # the source's red_plastic111 read a red patch): red_plastic111 the corner lamps (its M22), red_plastic the
    # bumper's reflectors; the lights texture still lights them at night
    MAT_RGB={"black_base": (34, 34, 36), "Material_#2125706098": (57, 61, 70),
             "Material_#2125774706": (26, 26, 28), "black_refl": (20, 20, 22), "Material_#2125780326": (22, 22, 24),
             "black": (20, 20, 22), "black.001": (20, 20, 22), "black.002": (20, 20, 22), "black222": (20, 20, 22),
             "Iron_Clean_Distorted": (60, 60, 64), "front_white_light": (226, 230, 236),
             "back_red_Light": (150, 12, 16), "red_plastic111": (66, 34, 38), "red_plastic": (90, 16, 20),
             "mirror": (58, 64, 72), "glass_base": (14, 14, 16), "Material_#2125773440": (14, 14, 16),
             "04_-_Default": (60, 60, 60),
             "tesla_ink": (60, 22, 22)},       # TESLA in the red light bar (TESLA_MAT): dark red, the bar's own shade
    GLASS_MATS=("glass_base", "Material_#2125773440"),
    GLASS_OPAQUE=("Plane.008",),           # glass_base on the B-pillar cover: opaque black
    GLASS_BACKS=(),                        # panes that get a reversed copy (one-sided in the source; these are slabs)
    ROOF_PANE="Plane.023",                 # the roof glass: zone LightBarL
    MIRROR_CAP="Plane.046",                # body colour (official FRONT34; the source paints it black_refl)
    # lamps: headlight materials; tail: the red light bar and the corner lamps (materials, faces above z / behind y),
    # and the light bar across the tailgate (_RED_BAR: Badge_BLADE a bright red bar flush with the housing's shelf, one
    # swatch texel so the lights texture lights it whole, round ends of radius blade_round; blade_n stations and
    # blade_rays rays a station: past the source's strip ends (|x| 0.454) the bar steps 6 cm forward onto the lamp
    # housing, whose lip at |x| 0.50-0.58 came through the bar's lower half at 21 x 3; blade_lit: Plane.034's rear
    # faces outboard of the gate (the corner lamps' inner C) stay smoked and lit as on the cover; else the smoked cover,
    # Plane.034's rear faces with it), lit with the tail lights at night
    LAMPS=dict(head=("front_white_light",), tail=("back_red_Light", "red_plastic111"), tail_z=0.75, tail_y=-1.4,
               **(dict(blade="Badge_BLADE", blade_rgb=(236, 78, 44), blade_flush=True, blade_swatch=True,
                       blade_round=0.019, blade_n=57, blade_rays=9, blade_lit=("Plane.034", 0.509))
               if _RED_BAR else dict(blade="Plane.034"))),
    # part lines, side view (y, z); read off the source's panel edges (build log OUTLINE)
    LINES={
        "S": ((-0.150, 0.369), (-0.227, 0.860)),   # front / rear door seam below the belt
        "BF": ((-0.171, 0.860), (-0.266, 1.219)),  # B-pillar trim front edge (front door frame ends)
        "BR": ((-0.306, 0.861), (-0.360, 1.219)),  # B-pillar trim rear edge (rear door frame starts)
        "D": ((-0.944, 0.914), (-0.989, 1.171)),   # rear door glass / fixed quarter glass divider
        "R1": ((-0.945, 0.566), (-1.070, 0.862)),  # rear door rear edge above the wheel arch
    },
    FRONT_Y=0.832, SILL_Z=0.204, ARCH=(0.518, -0.782),   # front door front, door bottom, rear door above / ahead of arch
    IN_DOOR=dict(up=0.860, x=0.415),          # convert.in_door: frame lines (BF / BR / D) above z `up`; doors at |x| > x
    # convert.in_gate: tailgate behind y, above z; |x| under GATE_X, under x_up above z up (the spoiler)
    IN_GATE=dict(y=-1.436, z=0.492, up=0.895, x_up=0.612),
    # door openings for the cabin shell and the seats (pre-centre y): front door front, B pillar (middle of the seam S
    # between the cabin floor z 0.32 and the belt; the shell's B-pillar ring follows S itself), rear door rear
    DOOR_Y=(0.820, -0.181, -1.069),
    GATE_Z=0.497,                          # tailgate opening's lower edge (gate panel bottom)
    REAR_ARCH=(-1.164, 0.271, 0.40),        # rear wheel arch (y, z, r): rear tire centre, arch radius
    GATE_X=0.509,                          # tailgate side edge through the light bar (gate panel half width)
    STOP_X=0.637,                          # corner lamps inboard of this |x| are the brake lights, outboard the tail
    # paint panels by component centre (classify): side doors at |x| > x, below z, front / rear door y range; the
    # tailgate (behind y, above z) and the frunk lid (ahead of y, above z) within |x| < 0.1
    PANELS=dict(x=0.593, z=0.660, front=(-0.200, 0.600), rear=(-0.989, -0.200), gate=(-1.489, 0.472), lid=(0.900, 0.556)),
    # fenders (mask zones Guard*): front (ahead of y, below z, |x| > x), rear (behind y, below z, |x| > x)
    GUARDS=dict(front=(0.750, 0.910, 0.395), rear=(-0.989, 1.100, 0.444)),
    # components cut along the lines (object, tris after welding): the window surround
    CUT={("Plane.005", 342): ("BF", "BR", "D"), _CORNER: ("BlackTopL", "BlackTopR")},
    # more cut planes for CUT: name -> (point, normal, cut faces behind y)
    PLANES={"BlackTopL": (*_BLACK_TOP, -1.66), "BlackTopR": (_mx(_BLACK_TOP[0]), _mx(_BLACK_TOP[1]), -1.66)},
    CUT_X=_CUT_X,                          # cut along +-GATE_X
    CUT_X_Y=None,                          # ... only faces behind this y (None: all)
    DOOR_OBJS=("Plane.062", "Plane.005", "Plane.002", "Plane.046", "Plane.048", "Plane.050", "Plane.047"),
    # Plane.086 (its only face material Material_#2125706098): the Performance badge on the tailgate's lower right
    # (service manual "Badge - Performance"; the mod's Model Y is the Performance, AGENTS.md rule 7). The real one is a
    # navy starburst in a chrome rim, 11 x 5 cm, ~16 x 7 px at the closest zoom: a flat plate in its mean colour
    # (57, 61, 70; median 32, 36, 47, drive.com.au photo), the rim (~0.4 px) left out
    GATE_OBJS=_CUT_X + ("Plane.022", "Plane.086"),
    GATE_COMPS=(("Plane.062", 248, -1), ("Plane.014", 102, -1)),   # rear window and its frame (y sign of the centre)
    GATE_CUT_COMPS=(),                     # (object, tris): components whose faces in_gate are the gate's
    # glass panes each FBX mesh must carry (build's read-back; "Body" is the body mesh)
    PANES={"Body": {"WinT", "LightBarL", "WinLT", "WinRT"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"},
           "DoorRearLeft": {"WinLT"}, "DoorRearRight": {"WinRT"}, "TrunkDoor": {"WinH"}, "EngineDoor": set()},
    # badges (user 2026-10-26; Model Y 2025 service manual ch. 1205 "Badges and Films"), drawn in badges(): T on the
    # frunk lid (OEM 1494949-00-A, chrome, 7.8 x 8.2 cm), TESLA in black across the light blade (letters ~2 cm tall,
    # 42 cm span), MODEL Y in chrome on the tailgate's lower left (jig on its left and lower edges). Letters are scaled
    # for the closest zoom, where 1 cm is about 1.5 px: true-size letters would be one or two pixels tall
    T_BADGE=(1.840, 0.0644, 0.0677, 0.571, (0, 0.34, 0.94), (0, 0, -1)),   # centre y on the frunk lid (stem tip ~3 cm
    #                                       off its front edge), width, height, ray start z, the lid's normal there,
    #                                       ray (straight down; None: along -normal)
    # blade strip centre z, cap height, letter pitch, lens height; the red bar on the official REAR34's vivid line (13
    # px tall at x 1380, the smoked cover 16), its left end on the official's (x 1245, just inboard of the left lamp's
    # C): LENS_X into the corner lamps, 0.08 past GATE_X (10 cm; rides the tailgate); TESLA 3.0 cm at the Model Y L's
    # pitch (3.6 crowded the thinner bar there)
    TESLA=(0.895, 0.025, 0.092, 0.0375) if _RED_BAR else (0.895, 0.03, 0.11, 0.045),
    TESLA_MAT="tesla_ink" if _RED_BAR else "badge_black",
    LENS_X=0.59 if _RED_BAR else 0.454,     # the blade's rear strip ends here (smoked: the corner lamps' lenses outboard)
    BADGE_Y=(-2.5, -1.720),                  # rear badges: blade ray start y, letter frame y (rays from 0.3 behind it)
    BLADE=True,                            # the light blade lens across the tailgate (Badge_BLADE)
    MODELY=("MODEL Y", -0.454, 0.526, 0.033),   # text, left x, baseline z, cap height (true ~2.4 cm): under the crease
    #                                        at z 0.60, inside the tailgate (|x| < 0.50 at this height)
    PERF_BADGE=None,                       # (x, z, w, h): a drawn Performance plate (here the source's Plane.086)
    # brake calipers (calipers()): front / rear (angle behind the top, half span) in degrees, radii and x from the
    # wheel's middle plane outward, grid. The real ones sit at 3 o'clock. A body-fixed front one there would swing
    # 0.11 grid out through the spokes at full lock, so the front pair keeps within ~0.08 grid of the steering axis in
    # plan: top or bottom of the wheel. From the game camera (30 deg down) a recess is seen through the gaps above it:
    # at the top the caliper hid behind the fender and the rim in 5 of 6 spin angles, at the bottom it showed in all 6
    # (offline view S, Quicksilver, 85-573 red px)
    CALIPER=dict(front=(176, 18), rear=(80, 15), r=(0.097, 0.162), x=(0.008, 0.036)),   # r: the front pair's
    #                                                             bottom stays above the body's lowest point (calipers())
    # frunk under the lid (frunk_tub(); user 2026-10-27 「前面是不是沒做置物箱的位置」): 2025 Model Y front trunk 117 L,
    # a tapered bin about 70 cm wide at the windshield end, 91 cm on its longest line, 35-43 cm deep (basenor.com
    # model-y-juniper-frunk-dimensions: owner measurements), framed by black trim panels over the cowl and shock
    # towers. The opening's jamb `ledge` down, a trim shelf in to the bin's `rim` (flange, `rim` wide), the bin's top
    # outline (rear / front y and half widths: a rounded trapezoid, corner radius `corner`), walls `taper` in to a
    # floor `depth` under the rim (a plane through the rear and front middles: the lid falls to the nose); `n` rays
    # round the plan centre resample the opening outline. build prints the volume (FRUNK ... L)
    FRUNK_TUB=dict(ledge=0.08, rim=0.025, y=(1.074, 1.790), half=(0.286, 0.178), corner=0.07, taper=0.11, depth=0.29,
                   n=128),

    # ---- cabin.py (mesh coords, centred; ground z -0.748)
    CABIN_FLOOR=-0.424,         # cabin floor: under the seated feet (seat_head.py feet)
    CABIN_FRONT_Y=1.083,        # shell front wall: past the windscreen's lower edge (y 1.02 on the centre line)
    TRUNK_Y=-0.921,             # trunk floor starts behind the rear backrests (their foot is at its height)
    TRUNK_WALL=True,           # trunk side walls from one profile (cabin.py trunk_walls; user 2026-11-01)
    HUMP_BACKS=False,          # no two-sided arch humps (cabin.py; staircase in the rear doors, 2026-11-01)
    REAR_DOOR_WALL=True,       # TRUNK_WALL's profile through the rear door openings too (user 2026-11-01)
    CABIN_ZC=-0.108,            # cabin axis the shell rays start from
    SEAM_CLEAR=0.065,          # grid: no ring this close to the B-pillar cut (the seam leans +-0.043 about it)
    # seats (front buckets: cushion / backrest width, backrest height, recline deg; rear bench: base width, cushions
    # (centre x, width), backrest height, recline), trunk sill plate and under-floor bin lid (width, depth)
    SEATS=dict(front=dict(w=0.42, back=0.50, recline=32, dy=0.055, dz=-0.083),
               rear=dict(base=1.08, cushions=((-0.365, 0.36), (0, 0.33), (0.365, 0.36)), back=0.44, recline=10, dy=0.04,
                         dz=-0.077),
               sill=(1.00, 0.12), bin=(0.86, 0.40)),
    PARCEL=None,               # a sedan's parcel shelf (cabin.parcel_shelf); the hatch has none
    # dash, screen and steering wheel: centres (x, y, z); wheel = (y, z) of its hub, x = the driver's seat
    DASH=dict(console=(0, 0.138, -0.324), dash=(0, 0.818, -0.024), trim=(0, 0.645, -0.014), light=(0, 0.647, -0.037),
              stand=(0, 0.658, 0.086), screen=(0, 0.628, 0.166), wheel=(0.375, 0.128)),   # wheel: the reclined driver's hands
    # door cards (Model Y, black interior; official interior photos): (part, y from the card's front / rear end, z over
    # the belt, size along y, size z, depth off the panel, cell, edge radius). Front door ys = (rear, front) = (B
    # pillar, A pillar); rear door (rear end, B pillar). "end" entries span the card minus (a, b) at its rear and front
    DOOR_CARD={
        "front": [
            ("upper trim", "end", (0.05, 0.10), -0.050, None, 0.060, 0.030, "dash", 0.012),
            ("ambient light", "end", (0.07, 0.16), -0.086, None, 0.007, 0.012, "screen", 0.002),
            ("armrest", "rear", 0.07, -0.215, 0.44, 0.050, 0.085, "seat", 0.018),
            ("pull handle", "rear", 0.13, -0.165, 0.26, 0.026, 0.050, "dash", 0.010),
            ("window switches", "rear", 0.31, -0.188, 0.13, 0.012, 0.060, "screen_back", 0.004),
            ("door button", "rear", 0.43, -0.186, 0.035, 0.012, 0.050, "trim", 0.004),
            ("map pocket", "end", (0.10, 0.30), -0.545, None, 0.085, 0.045, "base", 0.015),
            ("speaker grille", "front", 0.20, -0.400, 0.17, 0.150, 0.018, "console", 0.050),
        ],
        "rear": [
            ("upper trim", "end", (0.05, 0.05), -0.050, None, 0.060, 0.030, "dash", 0.012),
            ("ambient light", "end", (0.07, 0.07), -0.086, None, 0.007, 0.012, "screen", 0.002),
            ("armrest", "front", 0.06, -0.215, 0.38, 0.050, 0.080, "seat", 0.018),
            ("pull handle", "front", 0.10, -0.165, 0.22, 0.026, 0.050, "dash", 0.010),
            ("window switches", "front", 0.32, -0.188, 0.09, 0.012, 0.055, "screen_back", 0.004),
            ("map pocket", "end", (0.32, 0.05), -0.500, None, 0.080, 0.040, "base", 0.015),   # rear end: wheel arch
            ("speaker grille", "front", 0.08, -0.370, 0.14, 0.120, 0.018, "console", 0.045),
        ],
    },
)
