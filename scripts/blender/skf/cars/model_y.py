"""Model Y Performance (BloxBloger's "2026 Tesla Model Y Performance", Sketchfab, CC BY-NC 4.0, CREDITS.md): everything
the body pipeline needs to know about this car and its source model. Picked with CAR=model_y (the default,
pzveh.load). Each key is the module constant it sets: pzveh.use (paths, script, wheel, paints), convert.py (source
objects, part lines, badges), cabin.py (cabin layout). Grid units, pre-centre frame (+Y front, +Z up, -X car left,
ground z 0) unless noted; numbers and sources: .claude/skills/tesla-dev/references/models.md section 0.
"""
import math

_CUT_X = ("Plane.034", "Plane.044", "Plane.045", "Plane.036", "Plane.042", "Plane.043", "Plane.041")  # rear lamps

CAR = dict(
    # ---- pzveh: paths and names. TMP: work dir under temp/ (source in TMP/src, official renders in TMP/official)
    TMP="skf",
    NAME="MinidoracatTesla_ModelY",        # vehicle script, FBX and texture file name
    SCRIPT_MARK="---- geometry (TeslaModelY)",   # the vehicle script's line after which the geometry block is ours
    APP_CAR="app_car_{}.png",              # phone App car image per paint (PhoneApp.lua)
    DIMS=(4.790, 1.920, 1.624),            # official length, body width (no mirrors), height, metres
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
    # five Y spokes in dark graphite, open between them onto the brake rotor; staggered 255/35 R21 front / 275/35 R21
    # rear (one size here, the source tires'). Spokes and hub cap are geometry (the gaps really open: the vehiclewheel
    # shader has no alpha cutout), the tire, rim flange, barrel and the disc behind the spokes a surface of revolution
    # (wheel_profile). The disc closes the wheel at its middle (x = +-WHEEL_DISC_X): the brake rotor round the hub, dark
    # between rotor and barrel; the red calipers sit between it and the spokes but belong to the body (convert.py
    # calipers), they must not spin
    WHEEL_RIM=0.76,                        # rim flange radius / tire radius: 21" (266.7 mm bead + ~17 mm) / 356 mm
    # Y spoke in rr units (rr = WHEEL_RIM x tire radius), half-widths tangential: main arm from the hub to the fork,
    # then two arms spreading to +-spread at the barrel; front face `inset` grid inside the tire's half width at the
    # barrel, `dish` deeper at the hub; side walls `depth` grid deep. cap: hub cap radius; sweep: the spoke turned this
    # much more (rad) at the barrel than at the hub
    WHEEL_SPOKE=dict(n=5, hub=0.14, fork=0.50, spread=math.radians(17), main=(0.085, 0.065), arm=0.05, cap=0.17,
                     inset=0.020, dish=0.015, depth=0.018, sweep=0),
    WHEEL_DISC=dict(rotor=0.636, hat=0.30),   # brake rotor (355 mm) and its hat, rr units
    # Game-screen sRGB grey levels (calibration knob, compare with game screenshots); pzveh.wheel_texture turns each
    # into the texture value that renders it. Official RIMCLOSEUP: spokes 105-170 (studio light), windows ~28, black
    # tire; lighting comes from the spokes' own normals here
    WHEEL_RGB=dict(spoke=100, cap=40, barrel=28, lip=90, rotor=60, hat=35, dark=12, gap=8, tire=(22, 28), tread=20),
    # ---- pzveh: vehicle script
    OY=0.2878,            # model offset == centerOfMassOffset (unscaled) = height of the mesh centre above the physics
    #                       CoM. Not ModernCar's 0.1978: the body, wheels, seats and attachments all hang off the model
    #                       offset (VehicleScript.toBullet :586-588, BaseVehicle.getPassengerLocalPos /
    #                       getAttachmentLocalPos), so this only lowers the CoM; 0.09 lower brakes like SportsCar
    #                       (MinidoracatTesla_template.txt wheelFriction)
    WHEEL_LIFT=0.11,      # rendered wheel sits this much (grid) above its script offset at rest: vanilla arch centres
    #                       minus wheel offsets, ModernCar +0.10/+0.16, SUV +0.12/+0.10 (arch circle fit); calibration knob
    WHEEL_INSET=0.03,     # tire outer face this far inside the body's own tire (flush tires looked proud of the arch)
    CAB_BOX=(1.30, 0.45, -1.60),   # the cabin physics box: width, front y, rear y (mesh, grid)
    # passengers and seats (pzveh.geometry, cabin.py): side x, seat height over the ground (script) and its mesh z
    # (centred), seat y = middle of the door opening minus `back` (front, rear row), getting out this far off the body
    SEAT=dict(x=0.33, h=0.56, z=-0.19, back=(0.12, 0.08), out=0.30),
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

    # ---- convert.py: the source (gitignored): the OBJ inside the Sketchfab download, under TMP
    SRC=("src", "source", "Tesla Model Y Performance 2026.obj"),
    # OBJ (Blender import, -Z forward, Y up: front -X, left -Y) -> pre-centre frame, centres of the source bbox
    # (inspect prints them)
    SRC_C=(-1.0675, -1.787),               # source X (length) and Y (width) centre, metres; true to size (4.78 x 1.94 m)
    SRC_SCALE=1.0,                         # metres per source unit
    SRC_FLIP=False,                        # source front +X (glTF) instead of -X
    BELT_Z=0.88,                           # side window bottom (glass z min 0.878)
    TIRE_OBJ="Object005",                  # tires: wheel centres, radius and width (load_source)
    # what each source object is (names from the OBJ; sizes in the build log, or inspect)
    DROP=("Object005", "Cylinder", "Circle.", "Plane.027", "Plane.076", "Plane.088", "Plane.090", "Plane.026",
          "Plane.075", "Plane.087", "Plane.089",       # tires, rims, calipers, discs: the mod's procedural wheel stays
          "Object_11", "Object_12",                    # licence plates
          "Plane.031", "Plane.051", "Plane.053", "Plane.040",   # clear lamp covers: opaque in PZ, they'd hide the lamps
          "Plane.067", "Hyundai_KONA",   # BloxBloger's interior (tub, seats, dash): the mod's own cabin (cabin.py)
          "Tesla_Model_3"),              # rear TESLA: 1.2 cm block letters (E a solid block) sunk 4 cm under the blade
    DROP_COMPS=(),                         # (objects, lo, hi): drop their components centred in the box
    CARBON=None,                           # dict(rgb, zones): black paint zones (model_3.py); none on the Model Y
    ARCH_LINER=None,                       # dict(gap, inner, arc, n): procedural arch liners (the source has its own)
    PLATES=(),                             # (name, corners, facing, material): flat backing polygons
    # collapse-decimated before anything else (target tris): detail PZ cannot show at 1-4 px per cm
    DECIMATE={"Plane.045": 400,             # 29.5k-tri honeycomb under the tail light bar
              "Plane.034": 1200, "Plane.020": 1000, "Plane.016": 2600},
    PAINT_MAT="Material_#2125780493",       # the body paint (skin colour from the official renders, textures())
    # skin colour (sRGB 0-255) of the source's other materials
    MAT_RGB={"black_base": (34, 34, 36), "Material_#2125706098": (57, 61, 70),
             "Material_#2125774706": (26, 26, 28), "black_refl": (20, 20, 22), "Material_#2125780326": (22, 22, 24),
             "black": (20, 20, 22), "black.001": (20, 20, 22), "black.002": (20, 20, 22), "black222": (20, 20, 22),
             "Iron_Clean_Distorted": (60, 60, 64), "front_white_light": (226, 230, 236),
             "back_red_Light": (150, 12, 16), "red_plastic111": (120, 12, 16), "red_plastic": (120, 12, 16),
             "mirror": (58, 64, 72), "glass_base": (14, 14, 16), "Material_#2125773440": (14, 14, 16),
             "04_-_Default": (60, 60, 60)},
    GLASS_MATS=("glass_base", "Material_#2125773440"),
    GLASS_OPAQUE=("Plane.008",),           # glass_base on the B-pillar cover: opaque black
    GLASS_BACKS=(),                        # panes that get a reversed copy (one-sided in the source; these are slabs)
    ROOF_PANE="Plane.023",                 # the roof glass: zone LightBarL
    MIRROR_CAP="Plane.046",                # body colour (official FRONT34; the source paints it black_refl)
    # lamps: headlight materials; tail: the red light bar and the corner lamps (materials, faces above z / behind y),
    # and the smoked blade cover across the tailgate (its rear faces glow red at night like the real light blade)
    LAMPS=dict(head=("front_white_light",), tail=("back_red_Light", "red_plastic111"), tail_z=0.75, tail_y=-1.4,
               blade="Plane.034"),
    # part lines, side view (y, z); read off the source's panel edges (build log OUTLINE)
    LINES={
        "S": ((-0.150, 0.40), (-0.227, 0.90)),   # front / rear door seam below the belt
        "BF": ((-0.171, 0.90), (-0.266, 1.25)),  # B-pillar trim front edge (front door frame ends)
        "BR": ((-0.306, 0.90), (-0.360, 1.25)),  # B-pillar trim rear edge (rear door frame starts)
        "D": ((-0.955, 0.95), (-1.000, 1.20)),   # rear door glass / fixed quarter glass divider
        "R1": ((-0.956, 0.60), (-1.081, 0.90)),  # rear door rear edge above the wheel arch
    },
    FRONT_Y=0.83, SILL_Z=0.235, ARCH=(0.55, -0.79),   # front door front, door bottom, rear door above / ahead of arch
    IN_DOOR=dict(up=0.9, x=0.42),          # convert.in_door: frame lines (BF / BR / D) above z `up`; doors at |x| > x
    # convert.in_gate: tailgate behind y, above z; |x| under GATE_X, under x_up above z up (the spoiler)
    IN_GATE=dict(y=-1.45, z=0.52, up=0.93, x_up=0.62),
    # door openings for the cabin shell and the seats (pre-centre y): front door front, B pillar (middle of the seam S
    # between the cabin floor z 0.32 and the belt; the shell's B-pillar ring follows S itself), rear door rear
    DOOR_Y=(0.82, -0.181, -1.08),
    GATE_Z=0.525,                          # tailgate opening's lower edge (gate panel bottom)
    REAR_ARCH=(-1.175, 0.30, 0.40),        # rear wheel arch (y, z, r): rear tire centre, arch radius
    GATE_X=0.515,                          # tailgate side edge through the light bar (gate panel half width)
    STOP_X=0.645,                          # corner lamps inboard of this |x| are the brake lights, outboard the tail
    # paint panels by component centre (classify): side doors at |x| > x, below z, front / rear door y range; the
    # tailgate (behind y, above z) and the frunk lid (ahead of y, above z) within |x| < 0.1
    PANELS=dict(x=0.6, z=0.7, front=(-0.2, 0.6), rear=(-1.0, -0.2), gate=(-1.5, 0.5), lid=(0.9, 0.6)),
    # fenders (mask zones Guard*): front (ahead of y, below z, |x| > x), rear (behind y, below z, |x| > x)
    GUARDS=dict(front=(0.75, 0.95, 0.4), rear=(-1.0, 1.13, 0.45)),
    # components cut along the lines (object, tris after welding): the window surround, the rear side glass (door
    # pane and quarter glass in one piece)
    CUT={("Plane.005", 342): ("BF", "BR", "D")},
    PLANES={},                             # more cut planes for CUT: name -> (point, normal, cut faces behind y)
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
    T_BADGE=(1.85, 0.0644, 0.0677, 0.62, (0, 0.34, 0.94), (0, 0, -1)),   # centre y on the frunk lid (stem tip ~3 cm
    #                                       off its front edge), width, height, ray start z, the lid's normal there,
    #                                       ray (straight down; None: along -normal)
    TESLA=(0.93, 0.03, 0.11, 0.045),       # blade strip centre z, cap height, letter pitch, lens height
    LENS_X=0.46,                           # the blade's rear strip ends here (the corner lamps' lenses outboard)
    BADGE_Y=(-2.5, -1.7),                  # rear badges: blade ray start y, letter frame y (rays from 0.3 behind it)
    BLADE=True,                            # the light blade lens across the tailgate (Badge_BLADE)
    MODELY=("MODEL Y", -0.46, 0.555, 0.033),   # text, left x, baseline z, cap height (true ~2.4 cm): under the crease
    #                                        at z 0.60, inside the tailgate (|x| < 0.50 at this height)
    PERF_BADGE=None,                       # (x, z, w, h): a drawn Performance plate (here the source's Plane.086)
    # brake calipers (calipers()): front / rear (angle behind the top, half span) in degrees, radii and x from the
    # wheel's middle plane outward, grid. The real ones sit at 3 o'clock. A body-fixed front one there would swing
    # 0.11 grid out through the spokes at full lock, so the front pair keeps within ~0.08 grid of the steering axis in
    # plan: top or bottom of the wheel. From the game camera (30 deg down) a recess is seen through the gaps above it:
    # at the top the caliper hid behind the fender and the rim in 5 of 6 spin angles, at the bottom it showed in all 6
    # (offline view S, Quicksilver, 85-573 red px)
    CALIPER=dict(front=(176, 18), rear=(80, 15), r=(0.100, 0.168), x=(0.010, 0.045)),   # r: the front pair's
    #                                                             bottom stays above the body's lowest point (calipers())
    # frunk under the lid (frunk_tub(); user 2026-10-27 「前面是不是沒做置物箱的位置」): 2025 Model Y front trunk 117 L,
    # a tapered bin about 70 cm wide at the windshield end, 91 cm on its longest line, 35-43 cm deep (basenor.com
    # model-y-juniper-frunk-dimensions: owner measurements), framed by black trim panels over the cowl and shock
    # towers. The opening's jamb `ledge` down, a trim shelf in to the bin's `rim` (flange, `rim` wide), the bin's top
    # outline (rear / front y and half widths: a rounded trapezoid, corner radius `corner`), walls `taper` in to a
    # floor `depth` under the rim (a plane through the rear and front middles: the lid falls to the nose); `n` rays
    # round the plan centre resample the opening outline. build prints the volume (FRUNK ... L)
    FRUNK_TUB=dict(ledge=0.08, rim=0.025, y=(1.07, 1.80), half=(0.29, 0.18), corner=0.07, taper=0.11, depth=0.29,
                   n=128),

    # ---- cabin.py (mesh coords, centred; ground z -0.748)
    CABIN_FLOOR=-0.43,         # cabin floor
    CABIN_FRONT_Y=1.06,        # shell front wall: past the windscreen's lower edge (y 1.02 on the centre line)
    TRUNK_Y=-0.95,             # trunk floor starts behind the rear backrests (their foot is at its height)
    CABIN_ZC=-0.10,            # cabin axis the shell rays start from
    SEAM_CLEAR=0.065,          # grid: no ring this close to the B-pillar cut (the seam leans +-0.043 about it)
    # seats (front buckets: cushion / backrest width, backrest height, recline deg; rear bench: base width, cushions
    # (centre x, width), backrest height, recline), trunk sill plate and under-floor bin lid (width, depth)
    SEATS=dict(front=dict(w=0.42, back=0.50, recline=14),
               rear=dict(base=1.08, cushions=((-0.365, 0.36), (0, 0.33), (0.365, 0.36)), back=0.44, recline=18),
               sill=(1.00, 0.12), bin=(0.86, 0.40)),
    PARCEL=None,               # a sedan's parcel shelf (cabin.parcel_shelf); the hatch has none
    # dash, screen and steering wheel: centres (x, y, z); wheel = (y, z) of its hub, x = the driver's seat
    DASH=dict(console=(0, 0.12, -0.32), dash=(0, 0.80, -0.02), trim=(0, 0.627, -0.01), light=(0, 0.629, -0.033),
              stand=(0, 0.64, 0.09), screen=(0, 0.61, 0.17), wheel=(0.50, 0.04)),
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
