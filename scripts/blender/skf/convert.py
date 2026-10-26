"""Model Y from BloxBloger's "2026 Tesla Model Y Performance" (Sketchfab, CC BY-NC 4.0, CREDITS.md): source OBJ ->
PZ body FBX (the mod's cabin and the body glass inside), doors FBX (VehicleSkeleton, "<Part>_closing" clips), wheel
FBX, 8 skins, mask, lights, and the geometry block of the vehicle script.

    B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
    "$B" -b --factory-startup --python scripts/blender/skf/convert.py -- official   # design-studio renders (once)
    "$B" -b --factory-startup --python scripts/blender/skf/convert.py -- build      # everything else, ~20 s
    "$B" -b --factory-startup --python scripts/blender/skf/convert.py -- view <out_prefix> <N,NE,..> <shut|all|gate|frunk|fl|..>

Source (gitignored): temp/skf/src/source/Tesla Model Y Performance 2026.obj (+ .mtl), the OBJ inside the Sketchfab
download. Its materials are flat colours, its panels separate components (door skins, hood, tailgate cut along the
real panel lines), so parts and zones come from components and a few side-view lines, colours from materials; AO and
normals are baked for the paint's light. The cabin and trunk are the mod's own (cabin.py), not the source's interior;
shared code (door slab, skeleton export, damage UV1, wheel, script block) in scripts/blender/common/pzveh.py.
Frame: +Y front, +Z up, -X car left, 1 unit = 1 grid (vanilla raw FBX coords), pre-centre ground z = 0.
"""
import bpy, bmesh, colorsys, json, math, os, re, sys
import numpy as np
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "common"))
sys.path.insert(0, HERE)
import pzveh as pv  # noqa: E402
import cabin as cab  # noqa: E402
TMP = pv.TMP
SRC = os.path.join(TMP, "src", "source", "Tesla Model Y Performance 2026.obj")
K = pv.K                                   # grid per metre; the source is in metres, true to size (4.78 x 1.94 m)
# OBJ (Blender import, -Z forward, Y up: front -X, left -Y) -> pre-centre frame, centres of the source bbox
SRC_C = (-1.0675, -1.787)                   # source X (length) and Y (width) centre, metres
BELT_Z = 0.88                               # grid: side window bottom (glass z min 0.878)
SKIN, MASK = 2048, 512

# ---- what each source object is (names from the OBJ; sizes in the build log) ----
DROP = ("Object005", "Cylinder", "Circle.", "Plane.027", "Plane.076", "Plane.088", "Plane.090", "Plane.026",
        "Plane.075", "Plane.087", "Plane.089",       # tires, rims, calipers, discs: the mod's procedural wheel stays
        "Object_11", "Object_12",                    # licence plates
        "Plane.031", "Plane.051", "Plane.053", "Plane.040",   # clear lamp covers: opaque in PZ, they'd hide the lamps
        "Plane.067", "Hyundai_KONA",   # BloxBloger's interior (tub, seats, dash): the mod's own cabin (cabin.py) instead
        "Tesla_Model_3")               # rear TESLA: 1.2 cm block letters (E a solid block) sunk 4 cm under the blade
# collapse-decimated before anything else (target tris): detail PZ cannot show at 1-4 px per cm
DECIMATE = {"Plane.045": 400,             # 29.5k-tri honeycomb under the tail light bar
            "Plane.034": 1200, "Plane.020": 1000, "Plane.016": 2600}
# skin colour (sRGB 0-255) per material; paint comes from the official renders (textures())
MAT_RGB = {"Material_#2125780493": None, "black_base": (34, 34, 36), "Material_#2125706098": (57, 61, 70),
           "Material_#2125774706": (26, 26, 28), "black_refl": (20, 20, 22), "Material_#2125780326": (22, 22, 24),
           "black": (20, 20, 22), "black.001": (20, 20, 22), "black.002": (20, 20, 22), "black222": (20, 20, 22),
           "Iron_Clean_Distorted": (60, 60, 64), "front_white_light": (226, 230, 236), "back_red_Light": (150, 12, 16),
           "red_plastic111": (120, 12, 16), "red_plastic": (120, 12, 16), "mirror": (58, 64, 72),
           "glass_base": (14, 14, 16), "Material_#2125773440": (14, 14, 16), "04_-_Default": (60, 60, 60),
           "badge_chrome": (196, 200, 206), "badge_black": (8, 8, 10),
           "caliper_red": (180, 20, 28)}             # Performance calipers (official RIMCLOSEUP, lit side)
# chrome badges mirror the surroundings: bright on a dark paint, grey on a light one (median V >= 0.55: PearlWhite
# read 196 on ~210 paint, gone)
CHROME = ((200, 204, 210), (104, 108, 114))
GLASS_MATS = ("glass_base", "Material_#2125773440")  # glass_base on Plane.008 is the B-pillar cover: opaque black
# paint light (textures()): official-render paint quantile q = (base + up x upness(nz) + band x shoulder(nz) + lobe x
# softbox(n . PAINT_LIGHT) + height x h) x AO term: (base, up, band strength, band nz centre, band width, lobe, lobe
# width, height); h = face centre height, 0 at the lowest face, 1 at the roof. Calibration knob. A texel-rank mapping
# put the large hood on the render's highlight quantiles (pink, tesla-skf-after-1025b); without the lobe flat panels
# were one quantile (tesla-skf-after-1025c "沒甚麼反光").
# PAINT_Q, PAINT_TARGET and pv.CAL are fitted together (exp/paint-gloss-1026): the paint seen from the game camera
# (heading S, closest zoom) should spread like the official FRONT34 render's paint, p25 / p50 / p75 within a few
# levels. The previous set (0.12, 0.10, 0.55, 0.30, 0.20, 0.20, 0.05) / (.12 .27 .48 .70 .84 .90) left hood and sides
# on one quantile band: in game p75 only 4-11 levels over p50 (official 20-56), p25-p75 0.47-0.60 x official
# (tesla-gloss-skinA-1026a). A fit on the spread alone lit the lower doors and the bumper brightest (FRONT34 is a low
# side view, the game camera looks down): the height term keeps the lower body below the waist
PAINT_Q = (0.12, 0.168, 0.361, 0.265, 0.155, 0.101, 0.05, 0.3)
# percentiles of all paint texels -> quantile of the official ramp (pv.official_ramp)
PAINT_TARGET = ((10, 0.093), (25, 0.262), (50, 0.415), (75, 0.568), (90, 0.89), (97, 0.918))
PAINT_LIGHT = (0.0, 0.45, 0.89)            # softbox above, ahead: x-symmetric so both sides match at every heading
# rear haunch (user 2026-10-27 「每台車這裡白白有點突兀」, white on Diamond Black): the band's nz range also covers the
# whole rear fender above the arch and the tailgate's lower half, broad panels that landed on the ramp's highlight
# quantiles (Diamond Black p90 151 against 64 on the rear door). Behind y [0] -> [1] and below z [2] -> [3] (centred
# frame; the belt is z 0.13) the band keeps 1 - [4] of itself: the haunch median sits on the rear door's (official
# REAR34: haunch and tailgate in the doors' tone), the shoulder crease above it keeps its line. Calibration knob
HAUNCH = (-0.80, -0.95, 0.12, 0.20, 0.55)
OFFICIAL = pv.OFFICIAL                     # design-studio renders (stage official)
LIGHT_RGB = {"head": (255, 250, 240), "tail": (255, 30, 30)}

# ---- part lines, side view (y, z), pre-centre grid; read off the source's panel edges (build log OUTLINE) ----
LINES = {
    "S": ((-0.150, 0.40), (-0.227, 0.90)),   # front / rear door seam below the belt
    "BF": ((-0.171, 0.90), (-0.266, 1.25)),  # B-pillar trim front edge (front door frame ends)
    "BR": ((-0.306, 0.90), (-0.360, 1.25)),  # B-pillar trim rear edge (rear door frame starts)
    "D": ((-0.955, 0.95), (-1.000, 1.20)),   # rear door glass / fixed quarter glass divider
    "R1": ((-0.956, 0.60), (-1.081, 0.90)),  # rear door rear edge above the wheel arch
}
FRONT_Y, SILL_Z, ARCH = 0.83, 0.235, (0.55, -0.79)   # front door front, door bottom, rear door above / ahead of arch
# door openings for the cabin shell and the seats (pre-centre y): front door front, B pillar (middle of the seam S
# between the cabin floor z 0.32 and the belt; the shell's B-pillar ring follows S itself), rear door rear
DOOR_Y = (0.82, -0.181, -1.08)
SEAL = (0.008, 0.02)                       # grid: dark strip behind every panel edge (depth, reach past the edge):
#                                             the source's panel gaps are real gaps, the ground showed through them
GATE_Z = 0.525                             # tailgate opening's lower edge (gate panel bottom), pre-centre
REAR_ARCH = (-1.175, 0.30, 0.40)           # rear wheel arch (y, z, r), pre-centre: rear tire centre, arch radius
GATE_X = 0.515                             # tailgate side edge through the light bar (gate panel half width)
STOP_X = 0.645                             # corner lamps inboard of this |x| are the brake lights, outboard the tail
# components cut along the lines (object, tris after welding): the window surround, the rear side glass (door pane
# and quarter glass in one piece)
CUT = {("Plane.005", 342): ("BF", "BR", "D"), ("Plane.062", 268): ("D",)}
CUT_X = ("Plane.034", "Plane.044", "Plane.045", "Plane.036", "Plane.042", "Plane.043", "Plane.041")  # rear lamps
DOOR_OBJS = ("Plane.062", "Plane.005", "Plane.002", "Plane.046", "Plane.048", "Plane.050", "Plane.047")
GATE_OBJS = CUT_X + ("Plane.022", "Plane.086")
# Plane.086 (its only face material Material_#2125706098): the Performance badge on the tailgate's lower right
# (service manual "Badge - Performance"; the mod's Model Y is the Performance, AGENTS.md rule 7). The real one is a
# navy starburst in a chrome rim, 11 x 5 cm, ~16 x 7 px at the closest zoom: a flat plate in its mean colour
# (57, 61, 70; median 32, 36, 47, drive.com.au photo), the rim (~0.4 px) left out
# badges (user 2026-10-26; Model Y 2025 service manual ch. 1205 "Badges and Films"), drawn in badges(): T on the frunk
# lid (OEM 1494949-00-A, chrome, 7.8 x 8.2 cm), TESLA in black across the light blade (letters ~2 cm tall, 42 cm
# span), MODEL Y in chrome on the tailgate's lower left (jig on its left and lower edges). Letters are scaled for the
# closest zoom, where 1 cm is about 1.5 px: true-size letters would be one or two pixels tall
BADGE_OFF = 0.003                          # grid off the surface (no depth fight)
T_BADGE = (1.85, 0.0644, 0.0677)           # centre y on the frunk lid (stem tip ~3 cm off its front edge), width, height
TESLA = (0.93, 0.03, 0.11, 0.045)          # blade strip centre z (pre-centre), cap height, letter pitch, lens height
SWATCH = ("Badge_T", "Badge_TESLA", "Badge_MODELY", "Caliper")   # one flat-colour UV spot each (unwrap())
# brake calipers (calipers()): front / rear (angle behind the top, half span) in degrees, radii and x from the
# wheel's middle plane outward, grid. The real ones sit at 3 o'clock. A body-fixed front one there would swing 0.11
# grid out through the spokes at full lock, so the front pair keeps within ~0.08 grid of the steering axis in plan:
# top or bottom of the wheel. From the game camera (30 deg down) a recess is seen through the gaps above it: at the
# top the caliper hid behind the fender and the rim in 5 of 6 spin angles, at the bottom it showed in all 6 (offline
# view S, Quicksilver, 85-573 red px)
CALIPER = dict(front=(176, 18), rear=(80, 15), r=(0.100, 0.168), x=(0.010, 0.045))   # r: the front pair's
#                                                             bottom stays above the body's lowest point (calipers())
SWATCH_U = 0.03                            # UV0 strip kept for them at u > 1 - SWATCH_U
LENS_X = 0.46                              # the blade's rear strip ends here (the corner lamps' lenses outboard)
MODELY = (-0.46, 0.555, 0.033)            # left x, baseline z, cap height (true ~2.4 cm): under the crease at z 0.60,
#                                            inside the tailgate (|x| < 0.50 at this height)
SMOKE_RGB = (62, 58, 60)                   # the light blade by day: smoked lens, so the black letters read
GATE_COMPS = (("Plane.062", 248, -1), ("Plane.014", 102, -1))   # rear window and its frame (y sign of the centre)
PARTS = ["Body"] + list(pv.DOORS)          # part index: 0 body, 1.. DOORS order (FL, FR, RL, RR, TrunkDoor, EngineDoor)
# frunk under the lid (frunk_tub(); user 2026-10-27 「前面是不是沒做置物箱的位置」): 2025 Model Y front trunk 117 L, a
# tapered bin about 70 cm wide at the windshield end, 91 cm on its longest line, 35-43 cm deep (basenor.com
# model-y-juniper-frunk-dimensions: owner measurements), framed by black trim panels over the cowl and shock towers.
# Grid, pre-centre: the opening's jamb `ledge` down, a trim shelf in to the bin's `rim` (flange, `rim` wide), the
# bin's top outline (rear / front y and half widths: a rounded trapezoid, corner radius `corner`), walls `taper` in to
# a floor `depth` under the rim (a plane through the rear and front middles: the lid falls to the nose); `n` rays
# round the plan centre resample the opening outline. build prints the volume (FRUNK ... L)
FRUNK_TUB = dict(ledge=0.08, rim=0.025, y=(1.07, 1.80), half=(0.29, 0.18), corner=0.07, taper=0.11, depth=0.29, n=128)
ZN = list(pv.Z)                            # zone index -> name
CELL = {c: i for i, c in enumerate(pv.CABIN_CELLS)}
GLASS_ZONES = ("WinT", "WinH", "WinLH", "WinLT", "WinRH", "WinRT", "LightBarL")   # UV1 glass code order (the frag's
#                                                                                  GLASS_ZONE[], feat/edges-1025)


def lin(name, z):
    (y1, z1), (y2, z2) = LINES[name]
    return y1 + (y2 - y1) * (z - z1) / (z2 - z1)


def plane(name):
    """(co, no) of the bisect plane of a cut: side-view lines are planes along x."""
    (y1, z1), (y2, z2) = LINES[name]
    n = Vector((0, z2 - z1, -(y2 - y1))).normalized()
    return (0, y1, z1), tuple(n)


def in_door(p, t=0.0):
    """Door index 1-4 (DOORS order) of points p (N x 3) by the side-view lines, 0 outside; t widens every bound."""
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    up = z > 0.9
    fd = (y < FRONT_Y + t) & (z > SILL_Z - t) & (y > np.where(up, lin("BF", z), lin("S", z)) - t)
    rd = (z > SILL_Z - t) & np.where(up, (y < lin("BR", z) + t) & (y > lin("D", z) - t),
                                     (y < lin("S", z) + t) & (y > lin("R1", z) - t) & ((z > ARCH[0] - t) | (y > ARCH[1] - t)))
    side = np.abs(x) > 0.42
    left = x < 0
    return np.where(side & fd, np.where(left, 1, 2), np.where(side & rd, np.where(left, 3, 4), 0))


def in_gate(p, t=0.0):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    return (y < -1.45 + t) & (z > 0.52 - t) & (np.abs(x) < np.where(z > 0.93, 0.62, GATE_X) + t)


# ---------------------------------------------------------------- source

def load_source():
    """OBJ -> one mesh 'car' in the pre-centre frame, free corner normals, face attributes src (object index) and comp
    (welded connected component within the object). Returns the object names (src index -> name)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=SRC, forward_axis="NEGATIVE_Z", up_axis="Y")
    P = Matrix(((0, K, 0, K * -SRC_C[1]), (-K, 0, 0, K * SRC_C[0]), (0, 0, K, 0), (0, 0, 0, 1)))
    tires = []
    names, obs = [], []
    for o in sorted((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: o.name):
        me = o.data
        if o.name.startswith("Object005"):         # tires: wheel centres and outer faces for the script
            co = np.array([(P @ o.matrix_world @ v.co)[:] for v in me.vertices])
            tires.append((co.min(0), co.max(0)))
        if o.name.startswith(DROP):
            bpy.data.objects.remove(o)
            continue
        M = P @ o.matrix_world
        R = M.to_3x3().normalized()
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.corner_normals.foreach_get("vector", cn)
        cn = cn.reshape(-1, 3) @ np.array(R).T
        me.transform(M)
        o.matrix_world = Matrix()
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", cn.ravel())
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        bm.to_mesh(me)
        bm.free()
        target = next((t for p, t in DECIMATE.items() if o.name.startswith(p)), None)
        if target:
            pv.decimate(o, target)
        _label(o, len(names))
        names.append(o.name.split("_Mesh")[0] if "_Mesh" in o.name else o.name)
        obs.append(o)
    # wheels: (side, centre y, centre z, outer |x|) per tire, pre-centre frame, and the tire's radius and width (the
    # procedural wheel is built to them: the arches were modelled round these tires)
    wl = sorted(((-1 if hi[0] + lo[0] < 0 else 1, float((lo[1] + hi[1]) / 2), float((lo[2] + hi[2]) / 2),
                  float(max(-lo[0], hi[0]))) for lo, hi in tires), key=lambda w: (-w[1], w[0]))   # FL, FR, RL, RR
    size = np.array([(hi - lo) for lo, hi in tires])
    tire = (float(size[:, 1:].mean() / 2), float(size[:, 0].mean()))
    print("SOURCE tires: radius %.4f width %.4f centres" % tire, [np.round(w, 3).tolist() for w in wl])
    badges(obs, names)
    calipers(obs, names, wl, tire)
    pv.select_only(*obs)
    bpy.ops.object.join()
    car = bpy.context.view_layer.objects.active
    car.name = pv.NAME
    return car, names, wl, tire


def _label(o, src):
    """Triangulate o and tag its faces: src (object index) and comp (connected component within the object)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    si, ci = bm.faces.layers.int.new("src"), bm.faces.layers.int.new("comp")
    bm.faces.ensure_lookup_table()
    seen, k = np.full(len(bm.faces), -1), 0
    for f in bm.faces:
        if seen[f.index] >= 0:
            continue
        st = [f]
        seen[f.index] = k
        while st:
            g = st.pop()
            for e in g.edges:
                for h in e.link_faces:
                    if seen[h.index] < 0:
                        seen[h.index] = k
                        st.append(h)
        k += 1
    for f in bm.faces:
        f[si], f[ci] = src, int(seen[f.index])
    bm.to_mesh(o.data)
    bm.free()


def _flat_normals(me):
    """custom_normal = face normal on every corner (the badges are flat)."""
    me.update()
    lt = [p.loop_total for p in me.polygons]
    fn = np.array([p.normal[:] for p in me.polygons], np.float32)
    if "custom_normal" in me.attributes:
        me.attributes.remove(me.attributes["custom_normal"])
    me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", np.repeat(fn, lt, 0).ravel())


def _material(me, name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    me.materials.clear()
    me.materials.append(m)
    me.polygons.foreach_set("material_index", np.zeros(len(me.polygons), np.int64))


def t_logo():
    """The Tesla T as one outline (u right, v up; 1 wide, crossbar top at v 0.42, stem tip at -0.52): a crossbar arched
    up, its ends hooked down, a tapered stem."""
    top = [(u, 0.36 + 0.06 * (1 - (2 * u) ** 2)) for u in np.linspace(-0.5, 0.5, 9)]
    under = lambda a, b: [(u, 0.27 + 0.03 * (0.46 - abs(u)) / 0.37) for u in np.linspace(a, b, 5)]  # noqa: E731
    return [top + [(0.5, 0.30)] + under(0.46, 0.09) + [(0.05, -0.52), (-0.05, -0.52)] + under(-0.09, -0.46)
            + [(-0.5, 0.30)]]


def _ring(cx, cy, r, a0, a1, n):
    return [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in np.linspace(a0, a1, n)]


# stroke fonts, cap height 1: char -> (advance, polylines). SANS: a thin geometric sans for MODEL Y. WORDMARK: Tesla's
# rear lettering, wide and squared (E three bars, S three bars joined left-top and right-bottom, A a squared arch)
SANS = {"M": (1.0, [[(0, 0), (0, 1), (0.5, 0.3), (1, 1), (1, 0)]]),
        "O": (1.0, [_ring(0.5, 0.5, 0.5, 0, 2 * math.pi, 21)]),
        "D": (0.9, [[(0, 0), (0, 1), (0.4, 1)] + _ring(0.4, 0.5, 0.5, math.pi / 2, -math.pi / 2, 9) + [(0, 0)]]),
        "E": (0.75, [[(0.75, 1), (0, 1), (0, 0), (0.75, 0)], [(0, 0.5), (0.65, 0.5)]]),
        "L": (0.7, [[(0, 1), (0, 0), (0.7, 0)]]),
        "Y": (0.9, [[(0, 1), (0.45, 0.5), (0.9, 1)], [(0.45, 0.5), (0.45, 0)]]),
        " ": (0.5, [])}
WORDMARK = {"T": (1.3, [[(0, 1), (1.3, 1)], [(0.65, 1), (0.65, 0)]]),
            "E": (1.3, [[(0, 1), (1.3, 1)], [(0, 0.5), (1.3, 0.5)], [(0, 0), (1.3, 0)]]),
            "S": (1.3, [[(1.3, 1), (0, 1), (0, 0.5), (1.3, 0.5), (1.3, 0), (0, 0)]]),
            "L": (1.3, [[(0, 1), (0, 0), (1.3, 0)]]),
            "A": (1.3, [[(0, 0), (0, 1), (1.3, 1), (1.3, 0)], [(0, 0.5), (1.3, 0.5)]])}


def stroke_text(text, font, w, gap=0.28, pitch=None):
    """Strokes as square-capped quads, one list per letter (u right, v up, baseline 0); -> (letters, width)."""
    letters, x = [], 0.0
    for ch in text:
        adv, lines = font[ch]
        quads = []
        for line in lines:
            for a, b in zip(line, line[1:]):
                a, b = np.array(a) + (x, 0), np.array(b) + (x, 0)
                if np.allclose(a, b):
                    continue
                d = (b - a) / np.linalg.norm(b - a) * w / 2
                nrm = np.array((-d[1], d[0]))
                a, b = a - d, b + d
                quads.append([tuple(a - nrm), tuple(b - nrm), tuple(b + nrm), tuple(a + nrm)])
        letters.append(quads)
        x += pitch or adv + gap
    return letters, x - (pitch or gap) + (adv if pitch else 0)


def _add(obs, names, name, pts, faces, want, mat):
    """New source-like object from verts and faces, each face wound to face `want` (one vector or one per face), flat
    normals, src / comp tagged (_label)."""
    me = bpy.data.meshes.new(name)
    me.from_pydata(pts, [], faces)
    me.update()
    for k, f in enumerate(me.polygons):
        if f.normal.dot(want[k] if isinstance(want, list) else want) < 0:
            f.flip()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    _material(me, mat)
    _flat_normals(me)
    _label(ob, len(names))
    names.append(name)
    obs.append(ob)
    print("ADDED", name, len(me.polygons), "faces")


def calipers(obs, names, wl, tire):
    """Red brake calipers (Performance), one per wheel, in the body: they stay put while the wheel spins and steers.
    An annular sector between the wheel's middle disc and its spokes (CALIPER), centred `angle` behind the top. The
    wheel model turns about the vertical through its centre, up to 0.9 rad standing still (VehicleScript.java:1678-1686,
    BaseVehicle.java:4480-4490): a front caliper must stay behind the spokes' front faces and inside the barrel at every
    angle, checked here (it may cut into the solid spokes and the disc: hidden there)."""
    r, width = tire
    rr, hw = pv.WHEEL_RIM * r, width / 2
    rb = rr - 0.004
    pts, faces, want = [], [], []
    for side, yc, zc, xo in wl:
        front = yc > 0
        ang, span = CALIPER["front" if front else "rear"]
        (r1, r2), (x1, x2) = CALIPER["r"], CALIPER["x"]
        cx = side * (xo - width / 2 - pv.WHEEL_INSET)
        psi = np.radians(np.linspace(ang - span, ang + span, 4))
        k = len(pts)
        for p in psi:
            for rad in (r1, r2):
                for xa in (x1, x2):
                    pts.append((cx + side * xa, yc - rad * math.sin(p), zc + rad * math.cos(p)))
        v = lambda i, j, q: k + 4 * i + 2 * j + q    # psi step, radius (0 in, 1 out), x (0 in, 1 out)  # noqa: E731
        radial = lambda p: Vector((0, -math.sin(p), math.cos(p)))                                  # noqa: E731
        for i in range(3):
            pm = (psi[i] + psi[i + 1]) / 2
            faces += [(v(i, 0, 1), v(i, 1, 1), v(i + 1, 1, 1), v(i + 1, 0, 1)),     # outboard face
                      (v(i, 1, 0), v(i, 1, 1), v(i + 1, 1, 1), v(i + 1, 1, 0)),     # outer rim
                      (v(i, 0, 0), v(i, 0, 1), v(i + 1, 0, 1), v(i + 1, 0, 0))]     # inner rim
            want += [Vector((side, 0, 0)), radial(pm), -radial(pm)]
        for i, sgn in ((0, -1), (3, 1)):                 # ends
            faces.append((v(i, 0, 0), v(i, 1, 0), v(i, 1, 1), v(i, 0, 1)))
            want.append(sgn * Vector((0, -math.cos(psi[i]), -math.sin(psi[i]))))
        if front:                                        # clearance to the spokes at full lock, both ways
            c = np.array(pts[k:]) - (cx, yc, zc)
            c[:, 0] *= side                              # outboard positive
            worst = 1.0
            for th in np.linspace(-0.9, 0.9, 37):
                xw = c[:, 0] * math.cos(th) + c[:, 1] * math.sin(th)
                yw = -c[:, 0] * math.sin(th) + c[:, 1] * math.cos(th)
                rad = np.hypot(yw, c[:, 2])
                worst = min(worst, float((pv.spoke_x(rad, rr, hw) - 0.004 - xw).min()), float((rb - rad).min()))
            print("CALIPER front clearance at full lock %.4f grid" % worst)
            if worst < 0.003:
                raise SystemExit(f"front caliper hits the spokes or the barrel when steering: clearance {worst:.4f}")
    # the body's bbox sets the model centre and the script's extents and wheel offsets: the calipers stay inside it
    floor = min(min(v.co.z for v in o.data.vertices) for o in obs)
    if min(p[2] for p in pts) < floor:
        raise SystemExit(f"calipers reach below the body ({min(p[2] for p in pts):.4f} < {floor:.4f}): smaller CALIPER r")
    _add(obs, names, "Caliper", pts, faces, want, "caliper_red")


def badges(obs, names):
    """T on the frunk lid, the blade lens with TESLA on it, MODEL Y on the tailgate (see BADGE_OFF): new objects, src
    and comp tagged like the source's."""
    from mathutils.bvhtree import BVHTree
    from mathutils.geometry import tessellate_polygon

    def tree():
        verts, polys = [], []
        for o in obs:
            k = len(verts)
            verts += [v.co.copy() for v in o.data.vertices]
            polys += [[k + i for i in p.vertices] for p in o.data.polygons]
        return BVHTree.FromPolygons(verts, polys)

    def flat(name, groups, frame, mat, ray=None, planar=False):
        """Polygons (u, v) in frame (origin, u, v, badge normal) laid on what a ray (default -normal) meets, BADGE_OFF
        out: vertex by vertex, or with planar each group flat, on its mean hit normal through its outermost hit (a
        stroke laid by its ends would sink into a curve or crease mid-stroke)."""
        p0, eu, ev, n = (Vector(a).normalized() if i else Vector(a) for i, a in enumerate(frame))
        r = Vector(ray) if ray else -n
        pts, tris = [], []
        for group in filter(None, groups):         # (a space is an empty group)
            qs = [p0 + float(u) * eu + float(v) * ev for poly in group for u, v in poly]
            hits = []
            for q in qs:
                hit, hn, _, _ = bvh.ray_cast(q - 0.3 * r, r)
                if hit is None:
                    raise SystemExit(f"badge {name}: no surface under {np.round(q[:], 3).tolist()}")
                hits.append((hit, hn if hn.dot(n) > 0 else -hn))
            if planar:
                nl = sum((hn for _, hn in hits), Vector()).normalized()
                d = max(hit.dot(nl) for hit, _ in hits) + BADGE_OFF
                lay = [q + (d - q.dot(nl)) / r.dot(nl) * r for q in qs]   # along the ray: the outline stays put
            else:
                lay = [hit + BADGE_OFF * hn for hit, hn in hits]
            k = len(pts)
            pts += lay
            for poly in group:
                tris += [[k + i for i in t] for t in tessellate_polygon([[Vector((u, v, 0)) for u, v in poly]])]
                k += len(poly)
        _add(obs, names, name, pts, tris, n, mat)

    bvh = tree()
    # T: read from ahead of the car (u = -x), its top toward the windshield, on the lid's slope; rays straight down
    # (along the lid normal, the stem tip's ray would pass the lid's front edge onto the light bar)
    y, tw, th = T_BADGE
    n = Vector((0, 0.34, 0.94)).normalized()
    flat("Badge_T", [[[(u * tw, (v + 0.05) * th / 0.94) for u, v in t_logo()[0]]]],
         ((0, y, 0.62), (-1, 0, 0), (0, -n.z, n.y), n), "badge_chrome", ray=(0, 0, -1))
    # the blade lens: the source's blade faces back on a 1.5 cm strip (z 0.922-0.937; the underside and a sloped
    # housing below it), the real blade is ~4.5 cm with the letters inside. A plate over the strip across the
    # tailgate, upright, following the bar's curve in plan; it is the blade (smoked, glows as a tail light)
    zc, ch, pitch, lh = TESLA
    xs = np.linspace(-LENS_X, LENS_X, 21)
    ys = [bvh.ray_cast(Vector((x, -2.5, zc)), Vector((0, 1, 0)))[0].y - BADGE_OFF / 2 for x in xs]
    _add(obs, names, "Badge_BLADE", [Vector((x, y, zc + s * lh / 2)) for x, y in zip(xs, ys) for s in (-1, 1)],
        [(2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1) for i in range(len(xs) - 1)], Vector((0, -1, 0)), "badge_black")
    bvh = tree()
    # rear lettering, read from behind (u = +x)
    letters, wid = stroke_text("TESLA", WORDMARK, 0.22, pitch=pitch / ch)
    flat("Badge_TESLA", [[[(u * ch, v * ch) for u, v in q] for q in g] for g in letters],
         ((-wid * ch / 2, -1.7, zc - ch / 2), (1, 0, 0), (0, 0, 1), (0, -1, 0)), "badge_black", planar=True)
    x0, z0, ch = MODELY
    letters, _ = stroke_text("MODEL Y", SANS, 0.16)
    flat("Badge_MODELY", [[[(u * ch, v * ch) for u, v in q] for q in g] for g in letters],
         ((x0, -1.7, z0), (1, 0, 0), (0, 0, 1), (0, -1, 0)), "badge_chrome", planar=True)


def edit(car, names):
    """Cut in bmesh: bisect the straddling components along LINES, the rear lamps at the gate edge."""
    bm = bmesh.new()
    bm.from_mesh(car.data)
    si, ci = bm.faces.layers.int["src"], bm.faces.layers.int["comp"]
    bm.faces.ensure_lookup_table()
    groups = {}
    for f in bm.faces:
        groups.setdefault((f[si], f[ci]), []).append(f)
    for (s, c), fs in groups.items():
        key = (names[s], len(fs))
        cuts = CUT.get(key, ())
        if names[s].startswith(CUT_X):
            cuts = ("X+", "X-")
        for cname in cuts:
            if cname in ("X+", "X-"):
                co, no = (GATE_X if cname == "X+" else -GATE_X, 0, 0), (1, 0, 0)
            else:
                co, no = plane(cname)
            fs = [f for f in bm.faces if f.is_valid and f[si] == s and f[ci] == c]
            geom = list({*fs, *[e for f in fs for e in f.edges], *[v for f in fs for v in f.verts]})
            bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=co, plane_no=no)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    sizes = {k: len(v) for k, v in groups.items()}
    bm.to_mesh(car.data)
    bm.free()
    # custom normals of split corners: zero after the bisect interpolation fails -> face normal
    me = car.data
    cn = np.empty(len(me.loops) * 3, np.float32)
    me.attributes["custom_normal"].data.foreach_get("vector", cn)
    cn = cn.reshape(-1, 3)
    bad = np.linalg.norm(cn, axis=1) < 0.5
    if bad.any():
        fn = np.empty(len(me.polygons) * 3)
        me.polygons.foreach_get("normal", fn)
        lt = np.array([p.loop_total for p in me.polygons])
        cn[bad] = np.repeat(fn.reshape(-1, 3), lt, 0)[bad]
        me.attributes["custom_normal"].data.foreach_set("vector", cn.ravel())
    print("EDIT corners with lost normals", int(bad.sum()))
    return sizes


def classify(car, names, sizes):
    """Per face: part, zone (ZN index), skin colour, paint flag, lamp kind, glass flag and pane (GLASS_ZONES index)."""
    me = car.data
    n = len(me.polygons)
    src, comp = (np.empty(n, np.int64) for _ in range(2))
    me.attributes["src"].data.foreach_get("value", src)
    me.attributes["comp"].data.foreach_get("value", comp)
    mi = np.empty(n, np.int64)
    me.polygons.foreach_get("material_index", mi)
    mname = [m.name for m in me.materials]
    mat = np.array([mname[i] for i in mi], object)
    obj = np.array(names, object)[src]
    cen = pv.face_centres(car)
    co = pv.mesh_co(car)
    fv = np.array([p.vertices[:] for p in me.polygons])
    key = src * 100000 + comp
    ukey, inv = np.unique(key, return_inverse=True)
    csize = np.array([sizes[(int(k // 100000), int(k % 100000))] for k in ukey])[inv]   # comp size before cuts
    cc = np.stack([np.bincount(inv, cen[:, i]) for i in range(3)], 1) / np.bincount(inv)[:, None]
    ccen = cc[inv]
    paint = mat == "Material_#2125780493"
    glass = np.isin(mat, GLASS_MATS) & (obj != "Plane.008")
    part = np.zeros(n, np.int64)
    ax, ay, az = np.abs(ccen[:, 0]), ccen[:, 1], ccen[:, 2]
    left = ccen[:, 0] < 0
    # body panels by component
    fd = paint & (ax > 0.6) & (ay > -0.2) & (ay < 0.6) & (az < 0.7)
    part[fd] = np.where(left, 1, 2)[fd]
    rd = paint & (ax > 0.6) & (ay > -1.0) & (ay <= -0.2) & (az < 0.7)
    part[rd] = np.where(left, 3, 4)[rd]
    part[paint & (ax < 0.1) & (ay < -1.5) & (az > 0.5)] = 5
    part[paint & (ax < 0.1) & (ay > 0.9) & (az > 0.6)] = 6
    # door hardware, frames and panes: whole components inside a door (2.5 cm slack), cut components face by face. A
    # strip that runs past its one door's edge (the belt mouldings end under the B-pillar and quarter trim) goes face
    # by face too: whole on the body it was a black bar across the far window, seen through the roof glass with the
    # far door hidden behind that glass's depth (user 2026-10-25 images 10, 11, 13)
    cut = np.array([(o, s) in CUT for o, s in zip(obj, csize)])
    cand = np.isin(obj, DOOR_OBJS) & ~paint
    whole = cand & ~cut
    for k in np.unique(key[whole]):
        f = np.flatnonzero(key == k)
        d = in_door(co[np.unique(fv[f])], 0.025)
        if (d == d[0]).all() and d[0]:
            part[f] = d[0]
        elif not glass[f[0]] and len(np.unique(d[d > 0])) == 1:
            part[f] = in_door(cen[f])
    sel = cand & cut
    part[sel] = in_door(cen[sel])
    # the mirror cap is body colour (official FRONT34; the source paints it black_refl), its base and glass stay;
    # set after the door split, which takes door hardware by its non-paint material
    mirror = (obj == "Plane.046") & (part > 0)
    paint = paint | mirror
    gate = np.isin(obj, GATE_OBJS)
    for o, s, sy in GATE_COMPS:
        gate |= (obj == o) & (csize == s) & (np.sign(ay) == sy) & (ax < 0.1)
    gsel = gate & ((obj == "Plane.062") | (obj == "Plane.014") | in_gate(cen))
    part[gsel | np.isin(obj, ("Badge_BLADE", "Badge_TESLA", "Badge_MODELY"))] = 5
    part[obj == "Badge_T"] = 6
    # lamps. Tail: the red light bar (a 1 cm strip on the spoiler's lower lip, about a pixel in game), the corner
    # lamps, and the rear face of the smoked light-bar cover across the tailgate (Plane.034, black_base), which glows
    # red at night like the real light blade (night-N showed one corner patch only)
    head = mat == "front_white_light"
    tail = np.isin(mat, ("back_red_Light", "red_plastic111")) & (cen[:, 2] > 0.75) & (cen[:, 1] < -1.4)
    fnorm = np.array([p.normal[:] for p in me.polygons])
    blade = (obj == "Plane.034") & (fnorm[:, 1] < -0.5) | (obj == "Badge_BLADE")
    tail |= blade
    lamp = np.where(head, 1, np.where(tail, 2, 0))
    # zones
    zone = np.full(n, ZN.index("Roof"))
    L = cen[:, 0] < 0
    def put(m, l, r):
        zone[m & L] = ZN.index(l)
        zone[m & ~L] = ZN.index(r)
    put(paint & (part == 0) & (cen[:, 1] > 0.75) & (cen[:, 2] < 0.95) & (np.abs(cen[:, 0]) > 0.4), "GuardLH", "GuardRH")
    put(paint & (part == 0) & (cen[:, 1] < -1.0) & (cen[:, 2] < 1.13) & (np.abs(cen[:, 0]) > 0.45), "GuardLT", "GuardRT")
    for k, (l, r) in {1: ("DoorLH", "DoorLH"), 2: ("DoorRH", "DoorRH"), 3: ("DoorLT", "DoorLT"),
                      4: ("DoorRT", "DoorRT")}.items():
        put(part == k, l, r)
    put(part == 5, "Boot", "Boot")
    put(part == 6, "Hood", "Hood")
    put(head, "LightLH", "LightRH")
    # tail lights (lit with the headlights, HeadlightRear* parts: BaseVehicle.java:5858-5882) on the bar, the blade and
    # the corner lamps' outboard ends; brake lights (Stop, :5883-5895) on their inboard part
    stop = tail & (part == 0) & ~blade & (np.abs(cen[:, 0]) < STOP_X)
    put(tail & ~stop, "LightLT", "LightRT")
    put(stop, "StopL", "StopR")
    # glass zones: the mask zone and the UV1 pane code (GLASS_ZONES)
    gzn = np.where(obj == "Plane.023", "LightBarL",
                   np.where((ax < 0.1) & (ay > 0), "WinT", np.where(ax < 0.1, "WinH",
                   np.where(np.isin(part, (1, 2)), np.where(L, "WinLH", "WinRH"), np.where(L, "WinLT", "WinRT")))))
    zone[glass] = [ZN.index(z) for z in gzn[glass]]
    pane = np.full(n, -1)
    pane[glass] = [GLASS_ZONES.index(z) for z in gzn[glass]]
    rgb = np.array([MAT_RGB.get(m) or (0, 0, 0) for m in mat], float) / 255
    rgb[blade] = np.array(SMOKE_RGB) / 255
    print("CLASSIFY parts", {PARTS[k]: int((part == k).sum()) for k in range(len(PARTS))}, "glass", int(glass.sum()),
          "lamps head/tail", int(head.sum()), int(tail.sum()))
    return dict(part=part, zone=zone, rgb=rgb, paint=paint, lamp=lamp, glass=glass, pane=pane, obj=obj, csize=csize,
                badge=np.array([o.startswith(("Badge_", "Caliper")) for o in obj]),
                mat=mat, mirror=mirror)


# ---------------------------------------------------------------- textures

def split_zone_edges(car, zone):
    """Cut the mesh where the mask zone changes, so no UV island straddles two zones (the mask is sampled bilinearly
    and an edge texel between zones reads as none)."""
    bm = bmesh.new()
    bm.from_mesh(car.data)
    bm.faces.ensure_lookup_table()
    es = [e for e in bm.edges if len(e.link_faces) == 2 and zone[e.link_faces[0].index] != zone[e.link_faces[1].index]]
    bmesh.ops.split_edges(bm, edges=es)
    bm.to_mesh(car.data)
    bm.free()


def unwrap(car, obj):
    """UV0: smart projection of every face, packed; UV1 starts as a copy (damage_uv1 rewrites it). Badge faces (obj
    in SWATCH) all map onto one small triangle per badge in a strip kept free at the right edge: their strokes are
    narrower than a texel (5 mm; ~1 cm at 2048, 4 cm at 512), so on own islands they took the neighbours' colours."""
    me = car.data
    for nm in [u.name for u in me.uv_layers]:
        me.uv_layers.remove(me.uv_layers[nm])
    me.uv_layers.new(name="UV0")
    pv.select_only(car)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002, area_weight=0.0, scale_to_bounds=False)
    # 4 mask texels (512) between islands: the bake's margin meets halfway, and the shader samples the mask
    # bilinearly, so at 2 a zone's edge texels mixed in the neighbour island's zone colour
    bpy.ops.uv.pack_islands(rotate=True, margin=0.008)
    bpy.ops.object.mode_set(mode="OBJECT")
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers["UV0"].data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    uv[:, 0] *= 1 - SWATCH_U
    ls = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("loop_start", ls)
    for k, name in enumerate(SWATCH):       # 4 texels (2048) a side: the bake's margin fills the rest of the strip
        cu, cv, h = 1 - SWATCH_U / 2, (k + 0.5) / len(SWATCH), 2 / SKIN
        for i, d in enumerate(((-h, -h), (h, -h), (0, h))):
            uv[ls[obj == name] + i] = (cu + d[0], cv + d[1])
    uv = uv.ravel()
    me.uv_layers["UV0"].data.foreach_set("uv", uv)
    me.uv_layers.new(name="UV1").data.foreach_set("uv", uv)


def bake(car, layers, ao=True):
    """Bake per-face colour layers (name -> N x 3 array, emission) and AO at SKIN size; -> {name: H x W x 4}."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.bake.margin = 16
    sc.render.bake.margin_type = "EXTEND"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("bake")
    sc.world.light_settings.distance = 0.35
    me = car.data
    lt = np.array([p.loop_total for p in me.polygons])
    mat = bpy.data.materials.new("bake")
    mat.use_nodes = True
    nt = mat.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    at = nt.nodes.new("ShaderNodeAttribute")
    em = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(at.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs[0])
    tex = nt.nodes.new("ShaderNodeTexImage")
    nt.nodes.active = tex
    saved = [m for m in me.materials]
    mi = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("material_index", mi)
    me.materials.clear()
    me.materials.append(mat)
    me.polygons.foreach_set("material_index", np.zeros(len(mi), np.int64))
    pv.select_only(car)
    res = {}
    jobs = [(k, "EMIT") for k in layers] + ([("ao", "AO"), ("nrm", "NORMAL")] if ao else [])
    for name, kind in jobs:
        if kind == "EMIT":
            a = me.color_attributes.new("b_" + name, "FLOAT_COLOR", "CORNER")
            c = np.concatenate([np.repeat(layers[name], lt, 0), np.ones((lt.sum(), 1))], 1)
            a.data.foreach_set("color", c.astype(np.float32).ravel())
            at.attribute_name = "b_" + name
        img = bpy.data.images.new("bake_" + name, SKIN, SKIN, alpha=True, float_buffer=True)
        tex.image = img
        sc.cycles.samples = 1 if kind == "EMIT" else 32
        if kind == "NORMAL":
            bpy.ops.object.bake(type=kind, normal_space="OBJECT", use_clear=True)
        else:
            bpy.ops.object.bake(type=kind, use_clear=True)
        res[name] = pv.img_np(img)
        bpy.data.images.remove(img)
        print("BAKE", name, "done")
    me.materials.clear()
    for m in saved:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", mi)
    return res


def paint_hsv(hsvs):
    """Splice the damage-tint HSV of each paint into Core.lua's colors table (MinidoracatTesla.Specs, one line per
    paint in skin order; Create.Motor sets it with the skin)."""
    path = os.path.join(pv.MEDIA, "lua", "shared", "MinidoracatTesla", "Core.lua")
    text = open(path, encoding="utf-8").read()
    for p, code in pv.PAINTS:
        h, s, v = hsvs[p]
        text, n = re.subn(r'\{ name = "%s", code = "%s", h = [0-9.]+, s = [0-9.]+, v = [0-9.]+ \}' % (p, code),
                          f'{{ name = "{p}", code = "{code}", h = {h}, s = {s}, v = {v} }}', text)
        if n != 1:
            raise SystemExit(f"Core.lua: {n} colour lines for {p}")
    open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("LUA colors", hsvs)


def textures(car, c):
    zone_rgb = np.array([pv.Z[z] for z in ZN], float)
    aux = np.stack([c["paint"].astype(float), (c["lamp"] > 0).astype(float), (c["lamp"] == 2).astype(float)], 1)
    fz = pv.face_centres(car)
    hgt = np.repeat(((fz[:, 2] - fz[:, 2].min()) / np.ptp(fz[:, 2]))[:, None], 3, 1)    # 0 at the lowest face, 1 at the roof
    b = bake(car, {"col": c["rgb"], "zone": zone_rgb[c["zone"]], "aux": aux, "hgt": hgt, "pos": fz,
                   "badge": np.repeat(np.where(c["mat"] == "badge_chrome", 1.0, 0.5 * c["badge"])[:, None], 3, 1)})
    col, zon, aux, ao = b["col"][..., :3], b["zone"][..., :3], b["aux"][..., :3], b["ao"][..., 0]
    nrm = b["nrm"][..., :3] * 2 - 1
    nz = nrm[..., 2]
    paint = aux[..., 0] > 0.5
    # badges flat: their strokes overlap at the joints, coplanar faces whose AO rays start on each other (dark specks)
    shade = np.where(b["badge"][..., 0] > 0.25, 1.0, 0.55 + 0.45 * ao)
    chrome = b["badge"][..., 0] > 0.75
    # paint: the source is one flat colour, so its light comes from a matcap on the baked normal (sides low in the
    # official render's paint quantiles, hood and roof above the middle, a bright band on the shoulder) and the height
    # (the lower body reflects the ground) times AO; the quantile picks the official render's paint colour there
    # (official_ramp), then CAL / GAIN
    lit = 0.55 + 0.45 * ao
    band = PAINT_Q[2] * np.exp(-((nz - PAINT_Q[3]) / PAINT_Q[4]) ** 2)
    q = (PAINT_Q[0] + PAINT_Q[1] * np.clip((nz + 0.3) / 1.2, 0, 1) + band
         + PAINT_Q[5] * np.exp(-(1 - nrm @ np.array(PAINT_LIGHT)) / PAINT_Q[6])
         + PAINT_Q[7] * b["hgt"][..., 0]) * lit
    fade = HAUNCH[4] * (1 - pv.smoothstep(HAUNCH[1], HAUNCH[0], b["pos"][..., 1])) \
        * (1 - pv.smoothstep(HAUNCH[2], HAUNCH[3], b["pos"][..., 2]))
    # AO samples are noisy and the ramp is steep in places: blurred inside the paint (about 6 px of 2048), else flat
    # panels came out speckled
    pm = paint.astype(np.float32)
    den = np.maximum(pv.box_blur(pv.box_blur(pm, 3), 3), 1e-6)
    blur = lambda a: (pv.box_blur(pv.box_blur(a * pm, 3), 3) / den)[paint]  # noqa: E731
    # spread: a monotone remap of the full q's percentiles onto PAINT_TARGET, so the paint keeps the previous skin's
    # brightness and contrast; equal q stay equal (no texel-rank ties). The haunch fade goes through the same anchors:
    # every texel outside it keeps its colour
    q0, q = blur(q), blur(q - band * fade * lit)
    pc, tg = zip(*PAINT_TARGET)
    q = np.interp(q, [q0.min(), *np.percentile(q0, pc), q0.max()], [0.03, *tg, 0.97])
    hsvs = {}
    for p, code in pv.PAINTS:
        ramp = pv.official_ramp(code)
        xp = (np.arange(len(ramp)) + 0.5) / len(ramp)
        a_, b_ = (np.array(t, np.float32) for t in pv.CAL[p])
        s = col * shade[..., None]
        s[paint] = np.clip(a_ * np.stack([np.interp(q, xp, ramp[:, i]) for i in range(3)], -1) / pv.GAIN + b_, 0, 1)
        s[chrome] = np.array(CHROME[int(np.median(s[paint].max(-1)) >= 0.55)]) / 255
        pv.save_png(np.concatenate([np.clip(s, 0, 1), np.ones(s.shape[:2] + (1,))], -1),
                    os.path.join(pv.TEX_DIR, f"{pv.NAME}_{p}.png"), p)
        # setColorHSV for the damage overlays: the shader gives Veh_Damage* texels the paint hue and S / V offsets
        # (vehicle_common.frag.glsl:6-15); their median S 0.03, V 0.45 should land on this skin's median paint
        h_, s_, v_ = colorsys.rgb_to_hsv(*map(float, np.median(s[paint], 0)))
        hsvs[p] = (round(h_, 3), round(min(1.0, s_ + 0.47), 3), round(min(1.0, v_ + 0.05), 3))
    paint_hsv(hsvs)
    f = SKIN // MASK
    zc = zon[f // 2::f, f // 2::f]
    near = np.argmin(((zc[:, :, None, :] - zone_rgb[None, None]) ** 2).sum(-1), -1)   # snap: exact zone colours
    m = np.concatenate([zone_rgb[near], np.ones(near.shape + (1,))], -1)
    pv.save_png(m, os.path.join(pv.TEX_DIR, pv.NAME + "_mask.png"), "mask")
    lx = aux[f // 2::f, f // 2::f]
    lamp = lx[..., 1] > 0.5
    lrgb = np.where((lx[..., 2] > 0.5)[..., None], np.array(LIGHT_RGB["tail"]) / 255, np.array(LIGHT_RGB["head"]) / 255)
    pv.save_png(np.concatenate([lrgb * lamp[..., None], lamp[..., None].astype(float)], -1),
                os.path.join(pv.TEX_DIR, pv.NAME + "_lights.png"), "lights")
    print("TEX zones px", {ZN[k]: int((near == k).sum()) for k in np.unique(near)}, "AO median paint",
          float(np.median(ao[paint])))


# ---------------------------------------------------------------- build

def stage_build():
    os.makedirs(TMP, exist_ok=True)
    car, names, wheels, tire = load_source()
    sizes = edit(car, names)
    c = classify(car, names, sizes)
    split_zone_edges(car, c["zone"])
    c = classify(car, names, sizes)         # same faces, new vertex split
    # centre the bbox (mesh centre == model offset == centerOfMassOffset, vanilla convention)
    co = pv.mesh_co(car)
    ctr = (co.min(0) + co.max(0)) / 2
    zmid = float(ctr[2])
    shift = np.array([0.0, ctr[1], zmid])
    pv.set_co(car, co - shift)
    unwrap(car, c["obj"])
    textures(car, c)
    # UV1: vanilla ModernCar's damage layout (damage_uv1); glass faces + 2 + 2 x pane (the frag's glass class and
    # GLASS_ZONE[])
    me = car.data
    me.attributes.new("liner", "BOOLEAN", "FACE")      # geometry() / soup() read it; nothing is liner here
    pv.damage_uv1(car, np.array(ZN, object)[c["zone"]])
    lt = np.array([p.loop_total for p in me.polygons])
    u1 = np.empty(len(me.loops) * 2)
    me.uv_layers["UV1"].data.foreach_get("uv", u1)
    u1 = u1.reshape(-1, 2)
    lp = np.repeat(c["pane"], lt)
    u1[lp >= 0, 0] += pv.GLASS_UV1_SHIFT + 2 * lp[lp >= 0]
    me.uv_layers["UV1"].data.foreach_set("uv", u1.ravel())
    # vehicle script geometry block
    fc = pv.face_centres(car)
    corner = (c["lamp"] == 2) & (c["part"] == 0) & (c["obj"] != "Plane.034") & (fc[:, 0] < 0)
    sc_ = fc[corner]
    o = sc_[np.argsort(sc_[:, 0])[: max(1, len(sc_) // 5)]].mean(0)      # outboard end of the left corner lamp
    wl = [(sx, yc - ctr[1], zc, xo) for sx, yc, zc, xo in wheels]
    g = pv.geometry(car, zmid, wl, tire[0], tire[1], BELT_Z, tuple(y - ctr[1] for y in DOOR_Y),
                    (float(o[1]), float(o[2] + zmid)))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TMP, "skf_whole.blend"))
    g |= {"centre_y": float(ctr[1]), "zmid": zmid, "tris": pieces(car, c, shift)}
    g["tris"]["Wheel"] = pv.stage_wheel(*tire)
    json.dump(g, open(os.path.join(TMP, "geometry.json"), "w"), indent=1)
    print("GEOMETRY", json.dumps(g))


def two_sided(P, attr_of):
    """Triangles (N x 3 x 3 points), both faces on their own vertices; attr_of(normals N x 3) -> N x 3 x 7."""
    n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    V = np.concatenate([P.reshape(-1, 3), P[:, [0, 2, 1]].reshape(-1, 3)])
    return V, np.arange(len(V)).reshape(-1, 3), np.concatenate([attr_of(n), attr_of(-n)])


def corners(attr, n):
    """Per-face attribute rows (N x 7 or 7) with normals n on all three corners."""
    a = np.broadcast_to(attr, (len(n), 7))[:, None].repeat(3, 1).copy()
    a[..., 4:] = n[:, None]
    return a


def seals(V, T, sel, attr, glass_bvh):
    """Dark strips SEAL[0] behind every open edge of the faces sel (open by position: the zone split doubled the
    vertices there), reaching SEAL[1] past the edge, both sides: the source's panel gaps are real gaps, the ground
    showed through them. Not along a pane (glass_bvh within 1.2 cm of the strip's far edge): the pane closes that
    gap, and the strips lay on the glass as black spikes round the roof rails and A-pillars."""
    tri = T[sel]
    ed = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]])
    owner = np.tile(np.arange(len(tri)), 3)
    pid = np.unique(np.round(V / 1e-5).astype(np.int64), axis=0, return_inverse=True)[1].ravel()
    _, inv, cnt = np.unique(np.sort(pid[ed], 1), axis=0, return_inverse=True, return_counts=True)
    b = cnt[inv.ravel()] == 1
    a_, b_ = V[ed[b, 0]], V[ed[b, 1]]
    fn = np.cross(V[tri[:, 1]] - V[tri[:, 0]], V[tri[:, 2]] - V[tri[:, 0]])
    fn = (fn / np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12))[owner[b]]
    t = np.cross(b_ - a_, fn)                     # in the face's plane, away from it
    t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-12)
    far = (a_ + b_) / 2 + t * SEAL[1]
    keep = np.array([glass_bvh.find_nearest(Vector(p), 0.012)[0] is None for p in far], bool)
    a_, b_, fn, t = a_[keep], b_[keep], fn[keep], t[keep]
    p1, p2 = a_ - fn * SEAL[0], b_ - fn * SEAL[0]
    p3, p4 = p2 + t * SEAL[1], p1 + t * SEAL[1]
    P = np.concatenate([np.stack([p1, p3, p2], 1), np.stack([p1, p4, p3], 1)])
    return two_sided(P, lambda n: corners(attr, n))


def uv1_class(a):
    """0 paint, 1 cabin, 2 glass per triangle (attributes N x 3 x 7) by UV1 u at its first corner (pzveh face_classes)."""
    u = a[:, 0, 2]
    return np.where(u < pv.CABIN_UV1_U / 2, 1, np.where(u > pv.GLASS_UV1_SHIFT * 0.75, 2, 0))


def bvh_of(parts):
    """BVH of (points, tris) pairs, one frame."""
    from mathutils.bvhtree import BVHTree
    V, F, n = [], [], 0
    for P, t in parts:
        V += P.tolist()
        F += (t + n).tolist()
        n += len(P)
    return BVHTree.FromPolygons(V, F)


def rounded(pts, r, k=8):
    """Convex CCW polygon (M x 2) with its corners rounded to radius r: outline points, k per corner."""
    out = []
    for i in range(len(pts)):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % len(pts)]
        n1, n2 = ((np.array([e[1], -e[0]]) / np.linalg.norm(e)) for e in (p1 - p0, p2 - p1))   # outward normals
        c = p1 - r * (n1 + n2) / (1 + n1 @ n2)                   # r inside both edges
        a1, a2 = math.atan2(n1[1], n1[0]), math.atan2(n2[1], n2[0])
        a2 += 2 * math.pi * (a2 < a1)
        out += [c + r * np.array([math.cos(a), math.sin(a)]) for a in np.linspace(a1, a2, k)]
    return np.array(out)


def frunk_tub(V, T, lid, body_tris, attr):
    """The front trunk under the lid (FRUNK_TUB), in the body: jamb, black trim shelf, the bin's rim, tapered walls and
    floor, every face towards the opening (back-face culled from outside). Rings are sampled on rays from the bin's
    plan centre (the opening and the bin are star-shaped about it). attr(cell) -> 7 attributes. -> (points, tris,
    attributes) pre-centre, a soup. Fails when the bin leaves the opening or crosses the body's outer skin."""
    f = FRUNK_TUB
    tri = T[lid]
    pid = np.unique(np.round(V / 1e-5).astype(np.int64), axis=0, return_inverse=True)[1].ravel()
    ed = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]])
    _, inv, cnt = np.unique(np.sort(pid[ed], 1), axis=0, return_inverse=True, return_counts=True)
    ed = ed[cnt[inv.ravel()] == 1]                       # the opening's edge (by position: zone splits double vertices)
    C = np.array([0.0, sum(f["y"]) / 2])
    th = np.linspace(0, 2 * math.pi, f["n"], endpoint=False)
    d = np.stack([np.cos(th), np.sin(th)], 1)
    cross = lambda a, b: a[..., 0] * b[..., 1] - a[..., 1] * b[..., 0]  # noqa: E731

    def ring(P, Q, zP, zQ):
        """Nearest crossing of each ray with segments P -> Q (plan): radius and interpolated z."""
        e, w = (Q - P)[None], (P - C)[None]
        den = cross(d[:, None], e)
        with np.errstate(divide="ignore", invalid="ignore"):
            t, s = cross(w, e) / den, cross(w, d[:, None]) / den
        t = np.where((s >= 0) & (s <= 1) & (t > 1e-6), t, np.inf)
        k = np.argmin(t, 1)
        r, s = t[np.arange(len(th)), k], s[np.arange(len(th)), k]
        if not np.isfinite(r).all():
            raise SystemExit("frunk: a ray misses an outline")
        return r, zP[k] + s * (zQ[k] - zP[k])

    def outline(y0, y1, hr, hf, cr):
        p = rounded(np.array([[-hr, y0], [hr, y0], [hf, y1], [-hf, y1]]), cr)
        return ring(p, np.roll(p, -1, 0), np.zeros(len(p)), np.zeros(len(p)))[0]
    r_o, z_o = ring(V[ed[:, 0], :2], V[ed[:, 1], :2], V[ed[:, 0], 2], V[ed[:, 1], 2])
    (y0, y1), (hr, hf), tp = f["y"], f["half"], f["taper"]
    r_t = outline(y0, y1, hr, hf, f["corner"])
    r_f = outline(y0 + tp, y1 - tp, hr - tp, hf - tp, max(f["corner"] - tp, 0.02))
    if (r_t + f["rim"] > r_o - 0.01).any():
        raise SystemExit(f"frunk: the bin's rim reaches the opening (margin {(r_o - r_t - f['rim']).min():.3f})")
    z_s = z_o - f["ledge"]                               # trim shelf and the bin's rim
    pt = lambda r, z: np.column_stack([C + d * r[:, None], np.broadcast_to(z, r.shape)])  # noqa: E731
    rim = pt(r_t, z_s)
    # the floor: a plane `depth` under the rim's rear and front middles (the lid falls 0.3 grid to the nose; a level
    # floor left the front 3 cm deep)
    (yr, zr), (yf, zf) = ((rim[i, 1], z_s[i] - f["depth"]) for i in np.argmin(np.abs(th[:, None] - [1.5 * math.pi,
                                                                                                   0.5 * math.pi]), 0))
    plane = lambda p: np.column_stack([p[:, :2], zr + (p[:, 1] - yr) * (zf - zr) / (yf - yr)])  # noqa: E731
    rings = [pt(r_o, z_o), pt(r_o, z_s), pt(r_t + f["rim"], z_s), rim, plane(pt(r_f, 0.0))]
    # (cell, faces up): jamb, shelf, rim, wall; the floor "dash", up
    bands = [("base", False), ("base", True), ("console", True), ("dash", False)]
    tris, cl, up = [], [], []
    for (a, b), (c, u) in zip(zip(rings, rings[1:]), bands):
        b1, a1 = np.roll(b, -1, 0), np.roll(a, -1, 0)
        tris += [np.stack([a, a1, b1], 1), np.stack([a, b1, b], 1)]
        cl += [c] * 2 * len(th)
        up += [u] * 2 * len(th)
    fl = rings[-1]
    tris.append(np.stack([np.broadcast_to(plane(np.array([[*C, 0.0]]))[0], fl.shape), fl, np.roll(fl, -1, 0)], 1))
    cl += ["dash"] * len(th)
    up = np.array(up + [True] * len(th))
    P = np.concatenate(tris)
    n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    want = np.where(up[:, None], [[0, 0, 1.0]], np.column_stack([C - P.mean(1)[:, :2], np.zeros(len(P))]))
    flip = (n * want).sum(1) < 0
    P[flip] = P[flip][:, [0, 2, 1]]
    n[flip] *= -1
    # the shelf and rim twist between rays (z follows the opening edge): their two triangles per quad tilt opposite
    # ways and lit as stripes; they shade straight up (the floor is one plane)
    n[:-len(th)][up[:-len(th)]] = (0, 0, 1)
    # poke-through: from inside the bin (floor centre, 2 cm up) to every bin vertex nothing of the body's skin is crossed
    tree, o = bvh_of([(V, body_tris)]), Vector(plane(np.array([[*C, 0.0]]))[0] + [0, 0, 0.02])
    for p in np.concatenate(rings[2:]):
        v = Vector(p) - o
        hit = tree.ray_cast(o, v.normalized(), v.length - 1e-4)
        if hit[0] is not None:
            raise SystemExit(f"frunk: the bin crosses the body at {np.round(hit[0], 3).tolist()}")
    area = lambda r: 0.5 * (r * np.roll(r, -1)).sum() * math.sin(2 * math.pi / len(th))  # noqa: E731  (fan of rays)
    top, bot, dep = area(r_t), area(r_f), z_s.mean() - fl[:, 2].mean()
    vol = (top + bot + math.sqrt(top * bot)) / 3 * dep / K ** 3 * 1000
    print(f"FRUNK opening y {C[1] + (d[:, 1] * r_o).min():.3f}..{C[1] + (d[:, 1] * r_o).max():.3f} z {z_o.min():.3f}.."
          f"{z_o.max():.3f}, floor z {zr:.3f} (rear)..{zf:.3f} (front), bin {top / K ** 2:.2f} m2 top, "
          f"{f['depth'] / K * 100:.0f} cm deep, ~{vol:.0f} L, {len(P)} tris")
    return P.reshape(-1, 3), np.arange(3 * len(P)).reshape(-1, 3), corners(np.array([attr(c) for c in cl]), n)


def build_cabin(bodyV, Tb, Ab, meshes, shift):
    """The mod's own cabin and trunk (cabin.py) inside this body: shell rays against the closed car (centred), shell
    faces in a door opening coded for the shader. -> (points, tris, attrs) centred, to join the body."""
    cy, zmid = shift[1], shift[2]
    cls = uv1_class(Ab)
    doors = {p: (P, t[uv1_class(a) == 0]) for p, P, t, a in meshes}
    bvh = {"body": bvh_of([(bodyV, Tb[cls == 0])]),
           "glass": bvh_of([(bodyV, Tb[cls == 2])] + [(P, t[uv1_class(a) == 2]) for _, P, t, a in meshes]),
           "door": bvh_of(list(doors.values()))}
    belt, trunk_floor = BELT_Z - zmid, GATE_Z - zmid - cab.TRUNK_DROP
    o = Vector((0, cab.TRUNK_Y, trunk_floor + 0.1))       # the shell's rear end: tailgate inner panel / bumper behind
    rear = min(h[3] for b in bvh.values() for h in (b.ray_cast(o, Vector((0, -1, 0))),) if h[0] is not None)
    trunk_end = cab.TRUNK_Y - rear + cab.CABIN_INSET
    arch = (REAR_ARCH[0] - cy, REAR_ARCH[1] - zmid, REAR_ARCH[2])
    (y0, z0), (y1, z1) = LINES["S"]
    opening = dict(y=tuple(y - cy for y in DOOR_Y), sill=SILL_Z - zmid, gate=GATE_Z - zmid,
                   seam=lambda z: y0 + (y1 - y0) * (z + zmid - z0) / (z1 - z0) - cy,
                   each={p: bvh_of([d]) for p, d in doors.items()})
    print(f"CABIN trunk floor z {trunk_floor:.3f}, rear wall y {trunk_end:.3f}")
    ob = cab.cabin_mesh(bvh, belt, trunk_floor, trunk_end, arch, opening)
    ob.data.attributes.new("liner", "BOOLEAN", "FACE")
    V, T, A, _ = pv.soup(ob, np.zeros(3))
    bpy.data.objects.remove(ob)
    return V, T, A


def pieces(car, c, shift):
    """Whole car -> body FBX and doors FBX (slab doors, VehicleSkeleton, hinge keys). -> triangles per piece."""
    V, T, A, _ = pv.soup(car, shift)
    me = car.data
    tf = np.repeat(np.arange(len(me.polygons)), [p.loop_total - 2 for p in me.polygons])
    part, glass, paint, mirror = c["part"][tf], c["glass"][tf], c["paint"][tf], c["mirror"][tf]

    def cab_attr(cell):
        return np.array([0, 0, pv.CABIN_UV1_U - CELL[cell], 0, 0, 0, 1], float)
    back_liner = ~glass & ((part == 0) & paint | (part > 0) & ~paint)

    def backs(sel, recolour, base):
        """Reversed copies on their own vertices (the FBX import keeps one of two faces on the same vertices)."""
        n = int(sel.sum())
        a = A[sel][:, [0, 2, 1]].copy()
        a[..., 4:] *= -1
        if recolour:
            a[..., :4] = cab_attr("liner")[:4]
        return V[T[sel][:, [0, 2, 1]]].reshape(-1, 3), base + np.arange(3 * n).reshape(-1, 3), a
    # no reversed glass: every source pane is a closed slab (outer and inner face 0.9 mm apart, the rim), so its inner
    # face already shows the glass from inside; a reversed outer face on top put two layers there (darker, and the
    # two crossed where their triangulations differ)
    back_sets = lambda sel: ((sel & back_liner, True),)  # noqa: E731
    body_t, body_a, bodyV = [T[part == 0]], [A[part == 0]], V
    adds = [backs(sel, rec, 0) for sel, rec in back_sets(part == 0)]
    gb = bvh_of([(V, T[glass])])
    adds += [seals(V, T, (part == 0) & paint, cab_attr("base"), gb)]
    for v, t, a in adds:
        body_t.append(t + len(bodyV))
        bodyV = np.concatenate([bodyV, v])
        body_a.append(a)
    conv = np.array(Matrix.Rotation(-math.pi / 2, 3, "X"))
    meshes, hinges = [], {}
    mat = bpy.data.materials.new(pv.NAME)
    for k, (pname, (sd, axis, ang, secs)) in enumerate(pv.DOORS.items(), 1):
        sel = part == k
        lid = pname == "EngineDoor"
        off = (np.array([-sd, 0, 0]) if sd else np.array((0, 0, -1) if lid else pv.GATE_IN)) * pv.DOOR_T
        skin = sel & paint & ~mirror                     # the mirror cap: outer faces only (a closed shell)
        P, t, a, _ = pv.slab(V, T, A, skin, off, cab_attr("dash"), BELT_Z - shift[2], outer_extra=sel & ~skin)
        extra = [backs(bsel, rec, 0) for bsel, rec in back_sets(sel)] + [seals(V, T, skin, cab_attr("base"), gb)]
        for v, bt, ba in extra:
            t = np.concatenate([t, bt + len(P)])
            P = np.concatenate([P, v])
            a = np.concatenate([a, ba])
        if sd:      # door card details on the inner panel (the slab alone was one flat grey sheet: user image 12)
            front = pname.startswith("DoorFront")
            ys = (DOOR_Y[1], DOOR_Y[0]) if front else (DOOR_Y[2], DOOR_Y[1])
            ob = cab.door_card(bvh_of([(P, t)]), sd, ys, BELT_Z, "front" if front else "rear")
            v, bt, ba, _ = pv.soup(ob, np.zeros(3))
            bpy.data.objects.remove(ob)
            t = np.concatenate([t, bt + len(P)])
            P = np.concatenate([P, v])
            a = np.concatenate([a, ba])
        if lid:     # the front trunk in the body, under the lid's outline
            Pt, tt, at_ = frunk_tub(V, T, skin, T[part == 0], cab_attr)
            body_t.append(tt + len(bodyV))
            bodyV = np.concatenate([bodyV, Pt])
            body_a.append(at_)
        dv = V[np.unique(T[sel])]
        if sd:
            low = dv[dv[:, 2] < BELT_Z]
            yh = low[:, 1].max()
            near = low[low[:, 1] > yh - 0.05]
            h = np.array([sd * (sd * near[:, 0]).max(), yh, 0.0])
        elif lid:
            mid = dv[np.abs(dv[:, 0]) < 0.08]
            h = np.array([0.0, *mid[np.argmin(mid[:, 1]), 1:]])
        else:
            h = np.array([0.0, dv[:, 1].max(), dv[:, 2].max()])
        hinges[pname] = h - shift
        meshes.append((pname, P - shift, t, a))
        print(f"DOOR {pname}: {int(sel.sum())} faces, {len(t)} tris, hinge {np.round(h, 3).tolist()}")
    bpy.data.objects.remove(car)
    cv, ct, ca = build_cabin(bodyV - shift, np.concatenate(body_t), np.concatenate(body_a), meshes, shift)
    body_t.append(ct + len(bodyV))
    bodyV = np.concatenate([bodyV, cv + shift])
    body_a.append(ca)
    body = pv.soup_object(pv.NAME, bodyV - shift, np.concatenate(body_t), np.concatenate(body_a), mat)
    arm = bpy.data.objects.new("VehicleSkeleton", bpy.data.armatures.new("VehicleSkeleton"))
    bpy.context.scene.collection.objects.link(arm)
    pv.select_only(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    for pname in pv.DOORS:          # bones at the origin, unrotated: bind = identity (models.md 9)
        eb = arm.data.edit_bones.new(pname + "_bone")
        eb.head, eb.tail = Vector((0, 0, 0)), Vector((0, 0.3, 0))
    bpy.ops.object.mode_set(mode="OBJECT")
    obs = [arm]
    for pname, P, t, a in meshes:
        af = a.copy()
        af[..., 4:] = a[..., 4:] @ conv.T
        ob = pv.soup_object(pname, P @ conv.T, t, af, mat)
        ob.vertex_groups.new(name=pname + "_bone").add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
        ob.parent = arm
        ob.modifiers.new("arm", "ARMATURE").object = arm
        obs.append(ob)
    sc = bpy.context.scene
    sc.render.fps = pv.CLIP_FPS
    ad = arm.animation_data_create()
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    def hinge_pose(pname, deg):
        q = Quaternion(Vector(conv @ np.array(pv.DOORS[pname][1], float)), math.radians(deg))
        h = Vector(conv @ hinges[pname])
        return h - q @ h, q
    end = 1
    for pname, (_, _, ang, secs) in pv.DOORS.items():
        act = bpy.data.actions.new(pname + "_closing")
        act.use_fake_user = True
        ad.action = act
        last = 1 + round(secs * pv.CLIP_FPS)
        end = max(end, last)
        for fr in range(1, last + 1):
            u = (fr - 1) / (last - 1)
            deg = ang * (1 - u * u * (3 - 2 * u))
            for pb in arm.pose.bones:
                pb.location, pb.rotation_quaternion = hinge_pose(pname, deg) if pb.name == pname + "_bone" else \
                    (Vector((0, 0, 0)), Quaternion())
                pb.keyframe_insert("location", frame=fr)
                pb.keyframe_insert("rotation_quaternion", frame=fr)
        act.frame_range = (1, last)
    ad.action = None
    for pb in arm.pose.bones:
        pb.location, pb.rotation_quaternion = (0, 0, 0), (1, 0, 0, 0)
    sc.frame_start, sc.frame_end = 1, end
    for o in [body] + obs[1:]:
        pv.order_faces(o)
    pv.export_fbx(body, os.path.join(pv.VEH_DIR, pv.NAME + ".fbx"))
    pv.export_doors(obs)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TMP, "skf_doors.blend"))
    counts = {o.name: pv.tris(o) for o in [body] + obs[1:]}
    cls = {o.name: [int((pv.face_classes(o) == k).sum()) for k in range(3)] for o in [body] + obs[1:]}
    print("TRIS", counts, "total", sum(counts.values()), "paint/cabin/glass", cls)
    # read back: two UV layers, one bone group per door, faces still paint -> cabin -> glass
    def zones(o):
        """Glass panes in o (GLASS_ZONES names) read back from UV1: the frag's floor((u - 2) / 2)."""
        u = np.empty(len(o.data.loops) * 2)
        o.data.uv_layers["UV1"].data.foreach_get("uv", u)
        ls = np.empty(len(o.data.polygons), np.int64)
        o.data.polygons.foreach_get("loop_start", ls)
        fu = u[0::2][ls]
        return {GLASS_ZONES[int(k)] for k in np.floor((fu[fu > 1.5] - pv.GLASS_UV1_SHIFT) / 2)}
    info = lambda o: (o.name, pv.tris(o), len(o.vertex_groups), [u.name for u in o.data.uv_layers],  # noqa: E731
                      pv.face_classes(o), zones(o))
    got = [info(pv.import_fbx(os.path.join(pv.VEH_DIR, pv.NAME + ".fbx")))]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(pv.VEH_DIR, pv.DOORS_FBX + ".fbx"), automatic_bone_orientation=False)
    got += sorted(info(o) for o in bpy.data.objects if o.type == "MESH")
    want = {pv.NAME: {"WinT", "LightBarL", "WinLT", "WinRT"}, "DoorFrontLeft": {"WinLH"}, "DoorFrontRight": {"WinRH"},
            "DoorRearLeft": {"WinLT"}, "DoorRearRight": {"WinRT"}, "TrunkDoor": {"WinH"}, "EngineDoor": set()}
    for nm, t, vg, uv, cl, gz in got:
        print("CHECK FBX", nm, "tris", t, "groups", vg, "uv", uv, "glass", sorted(gz))
        if (uv[:2] != ["UV0", "UV1"] or (cl[1:] < cl[:-1]).any() or (vg != 1) != (nm == pv.NAME) or gz != want[nm]
                or t != counts[nm]):    # the importer drops a triangle on the same vertices as another
            raise SystemExit(f"{nm}: uv {uv}, groups {vg}, classes out of order {(cl[1:] < cl[:-1]).sum()}, glass {gz}, "
                             f"tris {t} of {counts[nm]}")
    if sorted(nm for nm, *_ in got[1:]) != sorted(pv.DOORS):
        raise SystemExit(f"doors FBX meshes {[nm for nm, *_ in got[1:]]}, want {sorted(pv.DOORS)}")
    json.dump({"tris": counts, "total": sum(counts.values()), "classes": cls},
              open(os.path.join(TMP, "tris.json"), "w"), indent=1)
    return counts


# ---------------------------------------------------------------- offline view (game camera, culled, magenta = hole)

def stage_view(out, heads, state, skin="UltraRed"):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(TMP, "skf_doors.blend"))
    arm = bpy.data.objects["VehicleSkeleton"]
    body = bpy.data.objects[pv.NAME]
    doors = [bpy.data.objects[p] for p in pv.DOORS]
    arm.matrix_world = Matrix.Rotation(math.pi / 2, 4, "X")
    openp = {"all": list(pv.DOORS)[:4], "gate": ["TrunkDoor"], "frunk": ["EngineDoor"], "shut": [],
             "fl": ["DoorFrontLeft"], "fr": ["DoorFrontRight"], "rl": ["DoorRearLeft"], "rr": ["DoorRearRight"]}[state]
    ad = arm.animation_data
    poses = {}
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        if pb.name[:-5] in openp:
            ad.action = bpy.data.actions[pb.name[:-5] + "_closing"]
            bpy.context.scene.frame_set(1)
            poses[pb.name] = (pb.location.copy(), pb.rotation_quaternion.copy())
    ad.action = None
    for pb in arm.pose.bones:
        pb.location, pb.rotation_quaternion = poses.get(pb.name, (Vector(), (1, 0, 0, 0)))
    bpy.context.view_layer.update()
    img = bpy.data.images.load(os.path.join(pv.TEX_DIR, f"{pv.NAME}_{skin}.png"))
    CAB = [(22, 22, 24), (40, 40, 44), (100, 100, 106), (30, 30, 32), (58, 58, 62), (112, 106, 98), (46, 46, 50),
           (28, 28, 30), (16, 16, 18), (170, 192, 214)]

    def mat(name, rgb=None, tex=False):
        m = bpy.data.materials.new(name)
        m.use_backface_culling = True
        m.use_nodes = True
        bs = m.node_tree.nodes["Principled BSDF"]
        if tex:
            nd = m.node_tree.nodes.new("ShaderNodeTexImage")
            nd.image = img
            m.node_tree.links.new(nd.outputs[0], bs.inputs[0])
        else:
            m.diffuse_color = (*[(x / 255) ** 2.2 for x in rgb], 1)
        return m
    M = [mat("paint", tex=True), mat("glass", (40, 230, 230))] + [mat(f"cab{i}", x) for i, x in enumerate(CAB)]
    glass_mode = os.environ.get("GLASS", "opaque")
    # TINT=1: body shell and reversed paint (liner) green, every door piece's inside orange (where they cross, both show)
    tint = os.environ.get("TINT") == "1"
    MB = M[:3] + [mat("liner_tint", (40, 200, 60))] + M[4:] if tint else M
    MD = M[:2] + [mat("door_tint", (240, 140, 30))] * len(CAB) if tint else M
    for o in [body] + doors:
        me = o.data
        me.uv_layers.active = me.uv_layers["UV0"]
        u1 = np.empty(len(me.loops) * 2)
        me.uv_layers["UV1"].data.foreach_get("uv", u1)
        ls = np.empty(len(me.polygons), np.int64)
        me.polygons.foreach_get("loop_start", ls)
        fu = u1[0::2][ls]
        idx = np.where(fu > 1.5, 1, np.where(fu < -1.0, 2 + np.clip((-fu - 2.0).astype(int), 0, 9), 0))
        o.data.materials.clear()
        for m in (MB if o is body else MD):
            o.data.materials.append(m)
        me.polygons.foreach_set("material_index", idx)
        if glass_mode == "hide":
            pv.keep_faces(o, idx != 1)
    # HIDE=DoorFrontRight,..: leave pieces out (in game a far door is hidden behind the near body glass's depth)
    hide = set(filter(None, os.environ.get("HIDE", "").split(",")))
    for o in bpy.data.objects:
        o.hide_render = o.type == "MESH" and (not (o is body or o in doors) or o.name in hide)
    # WHEELS=1: the wheel FBX at the four script offsets (rendered centre = offset + WHEEL_LIFT), STEER=<rad> turns the
    # front pair about the vertical (the game's m.rotationY, BaseVehicle.java:7440), SPIN=<rad> turns all about the axle
    if os.environ.get("WHEELS") == "1":
        bpy.ops.import_scene.fbx(filepath=os.path.join(pv.VEH_DIR, pv.NAME + "_Wheel.fbx"), axis_forward="-Z",
                                 axis_up="Y")
        wheel = bpy.context.selected_objects[0]
        wm = bpy.data.materials.new("wheel")
        wm.use_backface_culling = True
        wm.use_nodes = True
        tx = wm.node_tree.nodes.new("ShaderNodeTexImage")
        tx.image = bpy.data.images.load(os.path.join(pv.TEX_DIR, pv.NAME + "_wheel.png"))
        tx.interpolation = "Closest"
        wm.node_tree.links.new(tx.outputs[0], wm.node_tree.nodes["Principled BSDF"].inputs[0])
        wheel.data.materials.clear()
        wheel.data.materials.append(wm)
        block = open(os.path.join(TMP, "geometry_block.txt"), encoding="utf-8").read()
        steer, spin = float(os.environ.get("STEER", 0)), float(os.environ.get("SPIN", 0))
        for front, ox, oy, oz in re.findall(r"front = (\w+),\s+offset = (\S+) (\S+) (\S+),", block):
            w = wheel.copy()
            bpy.context.scene.collection.objects.link(w)
            w.matrix_world = (Matrix.Translation((-float(ox) * pv.S, float(oz) * pv.S, float(oy) * pv.S + float(os.environ.get("WLIFT", pv.WHEEL_LIFT))))
                              @ Matrix.Rotation(steer if front == "true" else 0.0, 4, "Z") @ Matrix.Rotation(spin, 4, "X"))
            w.hide_render = False
        wheel.hide_render = True
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.view_settings.view_transform = "Standard"
    sh = sc.display.shading
    sh.light = os.environ.get("LIGHT", "STUDIO")
    sh.color_type = "TEXTURE"
    sh.show_backface_culling = True
    sh.background_type = "VIEWPORT"
    sh.background_color = (1, 0, 1)
    sc.render.resolution_x, sc.render.resolution_y = int(os.environ.get("RX", 1600)), int(os.environ.get("RY", 1000))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = float(os.environ.get("ORTHO", 5.2))
    sc.camera = cam
    F = {"N": (0, -1), "NE": (1, -1), "E": (1, 0), "SE": (1, 1), "S": (0, 1), "SW": (-1, 1), "W": (-1, 0), "NW": (-1, -1)}
    for h in heads:
        f = np.array(F[h], float)
        f /= np.linalg.norm(f)
        right = np.array([-f[1], f[0]])
        cxy = np.array([1, 1]) / math.sqrt(2)
        d = Vector((cxy @ right * math.cos(math.radians(30)), cxy @ f * math.cos(math.radians(30)),
                    math.sin(math.radians(30))))
        cam.location = Vector([float(v) for v in os.environ.get("CENTRE", "0,0,0").split(",")]) + d * 30
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{out}_{h}_{state}.png"
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv[0] == "official":
        pv.stage_official()
    elif argv[0] == "build":
        stage_build()
    elif argv[0] == "view":
        stage_view(argv[1], argv[2].split(","), argv[3], *argv[4:])
