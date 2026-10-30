"""Cybertruck Cyberbeast: adamsochi2010's (Mr3DDD) "Tesla CyberTruck" (Sketchfab, CC BY 4.0, CREDITS.md). CAR=cybertruck.
Keys as in model_y.py (each is the module constant it sets); the keys only this car has are read with C.get and are off
for the others: SRC_YFRONT / SRC_STRETCH (an FBX source, scaled onto the official size), DROP_FACES, FACE_PARTS,
PART_OBJS, TIRE, PORT, CERBERUS, BED_TUB, ROOF_BAR, LIGHTS, TONNEAU_T, FILMS, FILM_MIX, PAINT_ALPHAS, EXTRA_AREAS. The
source's body is one welded shell with real 4 mm panel gaps, so its doors are split face by face along those gaps
(FACE_PARTS); the frunk lid (Body.012), tailgate (Body.005) and tonneau (Body.004, two triangles) are their own objects.
The source has no cargo bed (a flat panel closes it under the tonneau) and no wheel-arch liners: BED_TUB and ARCH_LINER
build them.
Grid units, pre-centre frame (+Y front, +Z up, -X car left, ground z 0) unless noted; numbers and sources:
.claude/skills/tesla-dev/references/models.md "Cybertruck".
"""
import math

CAR = dict(
    # ---- pzveh: paths and names
    TMP="skf_ct",
    NAME="MinidoracatTesla_Cybertruck",
    SCRIPT_MARK="---- geometry (TeslaCybertruck)",
    APP_CAR="app_car_cybertruck_{}.png",
    DIMS=(5.6829, 2.0316, 1.7938),         # owner's manual p.245: length, width w/o mirrors, height (Medium ride height)
    PORT_NOTE="real Cybertruck: above the driver's side rear wheel, owner's manual p.190",
    # Cyberbeast is stainless only ($PDD, US design studio 2026-07-10); the other 11 are Tesla's Color Paint Film wraps
    # (shop 2024-06). Order = Core.lua Specs colors (skin index is saved: only append after release). code None: a
    # film, its tone from the shop image (FILMS)
    PAINTS=[("Stainless", "PDD"), ("SatinStealthBlack", None), ("SatinCeramicWhite", None), ("SatinRoseGold", None),
            ("SatinTacticalGreen", None), ("SatinDarkGrey", None), ("SatinForestGreen", None),
            ("SatinAbyssBlue", None), ("CopperTintedClear", None), ("SatinCrimsonRed", None),
            ("SatinIridescentPurple", None), ("SlipGrey", None)],
    # shop images (temp/plan-cybertruck-1030/img/films, copied to TMP/official/films): the paint ramp per film
    FILMS={"SatinStealthBlack": "Satin-Stealth-Black-CT.png", "SatinCeramicWhite": "Satin-Ceramic-White-CT.png",
           "SatinRoseGold": "Satin-Rose-Gold-CT.png", "SatinTacticalGreen": "Satin-Tactical-Green-CT.png",
           "SatinDarkGrey": "Matte-Dark-Grey-CT.png", "SatinForestGreen": "Satin-Forrest-Green-CT.png",
           "SatinAbyssBlue": "Satin-Abyss-Blue-CT.png", "CopperTintedClear": "Copper-Tinted-Clear-CT.png",
           "SatinCrimsonRed": "Satin-Crimson-Red-CT.png", "SatinIridescentPurple": "Iridescent-Purple-CT.png",
           "SlipGrey": "Slip-Grey-CT.png"},
    # skin alpha of the paint texels = the shader's finish flag (MinidoracatTesla_vehicle.frag): 253 brushed stainless
    # (and the copper-tinted clear film over it: the steel's brushed sheen shows through, shop image), 252 satin film,
    # 254 gloss (Slip Grey reads glossy in the shop image: sharp reflections down the side)
    PAINT_ALPHAS={"Stainless": 253, "CopperTintedClear": 253, "SlipGrey": 254},
    PAINT_ALPHA_DEFAULT=252,
    # paint tone spread (convert.py PAINT_TARGET): wider than the cars' so the up-facing roof, hood and sails take the
    # official stainless render's bright end and the flanks its dark middle (FRONT34: sides ~70, sails ~190)
    PAINT_TARGET=((10, 0.14), (25, 0.28), (50, 0.45), (75, 0.66), (90, 0.78), (97, 0.86)),
    PAINT_ENDS=(0.03, 0.92),
    # paint tone (convert.py: a x ramp / GAIN + b, sRGB 0-1): offsets only, so the ramp's spread stays the shop
    # image's; fitted on the front door of the in-game screenshots (cybertruck-body-sp fl-max, zoom 0.5; satin
    # door ~ skin - 17 per channel) against the shop image's door. Calibration knob: refit after changing the paint
    # light or the films (models.md "Cybertruck" 車漆)
    CAL={
        "Stainless": ((1.0, 1.0, 1.0), (0.019, -0.004, -0.004)),
        # (B: near black the game answers ~2x per level; 0.038 left the hood olive, 48 49 44)
        "SatinStealthBlack": ((1.0, 1.0, 1.0), (0.061, 0.053, 0.042)),
        "SatinCeramicWhite": ((1.0, 1.0, 1.0), (-0.043, -0.053, -0.065)),
        "SatinRoseGold": ((1.0, 1.0, 1.0), (0.031, 0.023, 0.015)),
        "SatinTacticalGreen": ((1.0, 1.0, 1.0), (0.042, 0.03, 0.027)),
        "SatinDarkGrey": ((1.0, 1.0, 1.0), (0.046, 0.038, 0.027)),
        "SatinForestGreen": ((1.0, 1.0, 1.0), (0.038, 0.034, 0.034)),
        "SatinAbyssBlue": ((1.0, 1.0, 1.0), (0.061, 0.045, 0.027)),
        "CopperTintedClear": ((1.0, 1.0, 1.0), (0.088, 0.057, 0.038)),
        "SatinCrimsonRed": ((1.0, 1.0, 1.0), (0.065, 0.055, 0.047)),
        # Iridescent: gain too (its mixed ramp, FILM_MIX): door (12, 12, 15) and hood (83, 89, 120) from the shop image
        "SatinIridescentPurple": ((0.571, 0.652, 0.739), (0.079, 0.061, 0.048)),
        "SlipGrey": ((1.0, 1.0, 1.0), (-0.001, -0.019, -0.026)),
    },
    COMPOSITOR_MODEL="ct",
    OFFICIAL_OPTS="",                      # official renders: copied from temp/plan-cybertruck-1028 (PDD_SIDE.png ...)
    # official_ramp on PDD_SIDE.png: doors, rear quarter and the sail (the bright upper flank), the rear arch's cladding
    # and the windows cut out
    RAMP=dict(t=(0.12, 0.74), u=(0.25, 0.97), wheels=(0.795,), wt=0.70, wr=0.155, cut=((0.0, 0.63, 0.0, 0.30),)),
    # film ramps: the shop image's door panels (box in fractions of the car's bbox in the image; front 3/4 view)
    FILM_BOX=dict(u=(0.52, 0.84), t=(0.30, 0.60)),
    # Iridescent's shop image: doors near black (12, 12, 15), the colour only on the lit up-facing surfaces (the sail
    # (83, 89, 120), hue 230-238): the ramp's top 30 % from the sail, so the game's hood, roof edges and sails (q above
    # ~0.7) take it and the flanks stay dark (pzveh.film_ramp mix)
    FILM_MIX={"SatinIridescentPurple": ((dict(u=(0.52, 0.84), t=(0.30, 0.60)), 0.7),
                                        (dict(u=(0.82, 0.95), t=(0.14, 0.21)), 0.3))},
    # ---- pzveh: wheel, 20" Core with its aero cover (official RIMCLOSEUP): a matt black cover of six wide angular
    # blades round a hexagonal hub, 285/65 R20 all-terrain tyres (owner's manual p.238)
    WHEEL_RIM=0.62,                        # 20" (254 mm bead + 17 mm flange) / 439 mm tyre radius
    WHEEL_SPOKE=dict(n=6, hub=0.20, fork=0.60, spread=math.radians(6), main=(0.11, 0.13), arm=0.075, cap=0.22,
                     inset=0.012, dish=0.010, depth=0.020, sweep=math.radians(8)),
    WHEEL_DISC=dict(rotor=0.80, hat=0.35),
    WHEEL_RGB=dict(spoke=46, cap=34, barrel=14, lip=30, rotor=18, hat=16, dark=10, gap=8, tire=(24, 30), tread=22),
    # 285/65 R20: radius 439 mm, width 285 mm; track 1,772 mm (owner's manual p.238, p.245): the source's tyres are
    # 6 % bigger and 2.5 cm further out
    TIRE=dict(r=0.4393, w=0.285, track=1.772),
    # ---- pzveh: vehicle script
    OY=0.1978,
    WHEEL_LIFT=0.11,
    WHEEL_INSET=0.03,
    CAB_BOX=(1.40, 0.95, -0.95),
    SEAT=dict(x=0.36, h=0.60, z=-0.215, back=(0.12, 0.08), out=0.30),
    BODY_W_Z=0.55,
    # the tailgate hinges at its lower edge and folds down and back (owner's manual p.60-61: the struts lower it);
    # the tonneau rolls into its canister at the bed's front: ROLL_N strips slide forward and stack (tonneau_strips)
    DOORS={
        "DoorFrontLeft": (-1, (0, 0, 1), -65, 0.8), "DoorFrontRight": (1, (0, 0, 1), 65, 0.8),
        "DoorRearLeft": (-1, (0, 0, 1), -65, 0.8), "DoorRearRight": (1, (0, 0, 1), 65, 0.8),
        "TrunkDoor": (0, (1, 0, 0), 90, 2.0), "EngineDoor": (0, (1, 0, 0), 55, 1.0),
        "TrunkTonneau": (0, (0, 1, 0), "roll", 4.0),
    },
    GATE_IN=(0.0, 1.0, 0.0),               # tailgate inner panel: forward into the bed
    GATE_HINGE="bottom",
    TONNEAU_T=0.025,                       # tonneau slab: about 3 cm (the real cover's slats)
    # ---- convert.py: the source (TMP/src, gitignored; temp/sketchfab-cybertruck in the main checkout)
    SRC=("src", "source", "forFUBfbx.fbx"),
    SRC_C=(0.0, 0.0041),                   # source bbox centre, x (width) and y (length), source units (inspect)
    SRC_YFRONT=-0.939,                     # the source's ground (tyre bottoms), source z
    SRC_SCALE=5.6829 / 5.6797,             # metres per source unit: official length / source length
    # width over the arch cladding 2.002 m -> 2,031.6, height 1.877 -> 1,793.8 (Medium; the source sits ~8 cm higher
    # on bigger tyres)
    SRC_STRETCH=(2.0316 / 2.002, 1.0, 1.7938 / 1.8773),
    SRC_FLIP=False,
    BELT_Z=1.05,                           # side glass lower edge, sloped 0.98 (front) .. 1.13 (rear): the doors' mean
    TIRE_OBJ="Tire",
    # interior (the mod's cabin.py), tyres, tyre lettering, wheel covers (the procedural wheel), underbody plates, the
    # source's cross-car wheel-well boxes (ARCH_LINER instead), arch cameras and the tailgate camera's 2,000-triangle
    # cylinder (its housing Cube.009 stays)
    DROP=("Tire", "Plane.001", "Plane.003", "Plane.006", "Plane.007", "Plane.008", "Plane.009", "Plane.010",
          "Plane.011", "Sphere", "Cylinder", "Cube.01", "Cube.02"),
    # 2 x 2,240 triangles of tow-hook detail in the bumper
    DROP_COMPS=((("Cube",), (-0.7, 2.1, 0.3), (0.7, 2.3, 0.5)),),
    # faces dropped by centre and normal (objects, lo, hi, axis, (dot min, dot max)): the flat panel that closes the
    # source's bed under the tonneau (BED_TUB is the bed), the frunk lid's underside and edges (the pipeline's slab
    # gives it thickness; frunk_tub needs its outline)
    DROP_FACES=((("Body",), (-0.62, -2.28, 1.00), (0.62, -0.97, 1.40), (0, 0, 1), (0.5, 2.0)),
                (("Body.012",), (-0.8, 1.6, 0.7), (0.8, 2.4, 1.1), (0, 0, 1), (-2.0, 0.5))),
    ARCH_LINER=dict(gap=0.04, inner=0.06, arc=(0, 180), n=17, x=0.82),   # inside the cladding (|x| 0.839)
    PLATES=(),
    SEAL_CLIP=True,
    RAIL=None,
    DECIMATE={"Cube.006": 400, "Cube.008": 400, "Plane.004": 1400, "Plane.005": 1000},
    PAINT_MAT="Metal",
    MAT_RGB={"Black Plastick": (24, 24, 26), "Trim": (36, 36, 38), "Bed Top": (30, 30, 32),
             "White headlights": (236, 236, 232), "Car Reflection White": (150, 18, 22), "Orange Light": (196, 112, 32),
             "Miror": (120, 126, 132), "Glass Black": (14, 14, 16), "Gluss Button": (40, 40, 44),
             "Inside Grey": (40, 40, 42)},
    GLASS_MATS=("Glass Clear", "Glass Tented"),
    GLASS_OPAQUE=(),
    GLASS_BACKS=("WinLH", "WinLT", "WinRH", "WinRT"),
    ROOF_PANE=("Body.008", 16),
    MIRROR_CAP="-",                        # black mirror housings (official FRONT34): no body-colour cap
    LAMPS=dict(head=("White headlights",), tail=("Car Reflection White",), tail_z=0.3, tail_y=-1.5, blade=None),
    # the front light bar: a plate across the top of the nose face, under the hood's edge (z 0.84) (z, height, half
    # width). The source's bar is lit only at its ends from the game's camera (tesla-ctbody-1030c night-S)
    HEADBAR=(0.815, 0.035, 0.72),
    # part lines, side view (y, z): the source's 4 mm panel gaps. A line of 3+ points is a polyline (z ascending)
    LINES={
        "S": ((0.185, 0.30), (0.185, 1.00)),     # front / rear door seam (vertical); above the belt the B-pillar split
        "BF": ((0.185, 0.30), (0.185, 1.00)),
        "BR": ((0.185, 0.30), (0.185, 1.00)),
        "D": ((-0.7205, 1.043), (-0.709, 1.14)),  # rear door's rear edge above the belt (into the glass)
        "R1": ((-0.682, 0.362), (-0.7285, 0.53), (-0.7205, 1.043)),   # ... and below it
        "FQ": ((1.0995, 0.30), (1.0995, 1.00)),  # front door's front edge carried up the glass: the fixed quarter glass
    },
    FRONT_Y=1.0995, SILL_Z=0.35, ARCH=(0.0, -9.0),
    IN_DOOR=dict(up=1.0, x=0.55),
    IN_GATE=dict(y=-2.20, z=0.60, up=1.10, x_up=0.67),   # tailgate; the light bar's middle on its top edge
    DOOR_Y=(1.0995, 0.185, -0.72),
    GATE_Z=0.621,                          # tailgate's lower edge = the bed floor
    REAR_ARCH=(-1.41, 0.37, 0.40),
    GATE_X=0.76,
    STOP_X=0.80,                           # the bumper's corner lamps are the brake lights, the tailgate bar the tail
    PANELS=dict(x=0.70, z=1.15, front=(0.185, 1.10), rear=(-0.73, 0.185), gate=(-2.2, 0.6), lid=(1.6, 0.8)),
    GUARDS=dict(front=(1.10, 1.0, 0.5), rear=(-0.72, 1.3, 0.5)),
    # paint faces of these objects split face by face (the source's doors are not separate): doors by in_door(centre)
    # outside |x| PANELS x and under PANELS z
    FACE_PARTS=("Body",),
    PART_OBJS={"TrunkTonneau": ("Body.004",)},
    # side glass (one sheet per side from the A-pillar tip to the C-pillar), the B-pillar applique and the mirror's
    # black sail cut at the door edges
    CUT={("Body.009", 22): ("FQ", "S", "D"), ("Body.010", 444): ("S",), ("Body.010", 108): ("FQ",),
         ("Body.010", 396): ("D",)},
    PLANES={},
    CUT_X=("-",),
    CUT_X_Y=-9.0,
    DOOR_OBJS=("Body.009", "Body.010", "Cube.006", "Cube.007"),
    GATE_OBJS=("Body.005", "Body.003", "Cube.030", "Cube.009"),
    GATE_COMPS=(),
    GATE_CUT_COMPS=(),
    CARBON=None,
    # the fixed quarter glass ahead of the front door: no window part (the real one is fixed), so the roof glass's
    # zone; as WinLT / WinRT (the default for body glass) it went with the rear window
    FIXED_GLASS_Y=1.0995,
    PANES={"Body": {"WinT", "LightBarL", "WinLT", "WinRT"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"},
           "DoorRearLeft": {"WinLT"}, "DoorRearRight": {"WinRT"}, "TrunkDoor": set(), "EngineDoor": set(),
           "TrunkTonneau": set()},
    # badges: none on the nose or tailgate (official FRONT34 / STUD_REAR); Cyberbeast's laser-etched Cerberus on the
    # tailgate's lower right (official STUD_REAR; tesla.com 2026-10-30): centre x, z, width (grid), on the tailgate
    T_BADGE=None,
    TESLA=None,
    LENS_X=0.0,
    BADGE_Y=(-2.6, -2.33),
    BLADE=False,
    MODELY=None,
    PERF_BADGE=None,
    # three wolf heads, traced off STUD_REAR (about 23 x 18 px there, ~12 cm wide) and mirrored
    CERBERUS=dict(x=0.60, z=0.76, w=0.10, bitmap=(
        ".......##...##.......", "......###...###......", "......####.####......", "...###############...",
        "..#################..", "#####################", "#####################", "#####################",
        "###.#############.###", ".#...###########...#.", ".....###########.....", ".....###########.....",
        "....##..##.##..##....", "...###..##.##..###...", "..........#..........", ".........###.........",
        ".........###.........")),
    CALIPER=None,                          # behind the closed aero covers
    # frunk 200 L (owner's manual p.249) under the lid (Body.012)
    FRUNK_TUB=dict(ledge=0.05, rim=0.025, y=(1.82, 2.20), half=(0.42, 0.36), corner=0.08, taper=0.12, depth=(0.26, 0.17),
                   n=128),
    # the cargo bed (vault; owner's manual p.246, p.249: floor 1,824.6 x 1,295.4 mm between the wheel humps, 1,589 L);
    # here the source's length between the cabin and the tailgate. y front .. rear (the tailgate's inner panel), floor
    # z (the tailgate's lower edge), the rails' inner edge x and the walls' top z along y (polylines (y, value), y
    # ascending: where the dropped cover met the rails, stepped like it), wheel humps ((front y, rear y), half width
    # inside = the floor's 1,295 mm, top z), lining (cabin palette cell)
    BED_TUB=dict(y=(-0.99, -2.18), z=0.625, rail_x=((-2.26, 0.63), (-0.99, 0.57)),
                 top=((-2.26, 1.105), (-1.675, 1.105), (-1.668, 1.19), (-1.17, 1.19), (-1.164, 1.235), (-0.99, 1.25)),
                 hump=((-1.08, -1.78), 0.535, 0.86), cell="dash"),
    # the off-road light bar (official accessory, every Cybertruck here) on the roof's front edge over the windscreen:
    # centre y, width (~46"), depth, height (grid); the lens's cabin palette cell
    ROOF_BAR=dict(y=0.22, w=0.96, d=0.05, h=0.035, lens="seat"),
    # light spots (Truck.lua T.Init.BedLight / RoofLight): (x, y) in half extents, "bed" = the bed's centre; the roof
    # bar like vanilla's headlights (yOffset 2.0, Vehicles.lua:1504-1505)
    LIGHTS={"BedLight": (0.0, "bed"), "RoofLight": (0.0, 2.0)},
    # charge port (owner's manual p.190): above the driver's side rear wheel, on the arch's upper trim edge (mesh y
    # pre-centre, z; the rear axle at y -1.43)
    PORT=(-1.43, 0.88),
    # ---- cabin.py (mesh coords, centred)
    CABIN_FLOOR=-0.43,
    CABIN_FRONT_Y=1.45,
    TRUNK_Y=-1.50,                         # (no trunk: the cabin floor runs to its rear wall)
    CABIN_REAR_Y=-0.94,                    # the cabin's rear wall: 5 cm inside the bed's front wall
    CABIN_ZC=-0.08,
    SEAM_CLEAR=0.065,
    SEATS=dict(front=dict(w=0.44, back=0.52, recline=14),
               rear=dict(base=1.20, cushions=((-0.40, 0.38), (0, 0.36), (0.40, 0.38)), back=0.46, recline=18),
               sill=None, bin=None),
    PARCEL=None,
    DASH=dict(console=(0, 0.45, -0.32), dash=(0, 1.15, -0.02), trim=(0, 0.975, -0.01), light=(0, 0.977, -0.04),
              stand=(0, 0.98, 0.10), screen=(0, 0.95, 0.18), wheel=(0.80, 0.07)),
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
