"""A car's body from its Sketchfab source (scripts/blender/skf/cars/<CAR>.py, default model_y: BloxBloger's "2026
Tesla Model Y Performance", CC BY-NC 4.0, CREDITS.md): source OBJ -> PZ body FBX (the mod's cabin and the body glass
inside), doors FBX (VehicleSkeleton, "<Part>_closing" clips), wheel FBX, 8 skins, mask, lights, and the geometry block
of the vehicle script.

    B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
    "$B" -b --factory-startup --python scripts/blender/skf/convert.py -- official   # design-studio renders (once)
    "$B" -b --factory-startup --python scripts/blender/skf/convert.py -- build      # everything else, ~20 s
    "$B" -b --factory-startup --python scripts/blender/skf/convert.py -- view <out_prefix> <N,NE,..> <shut|all|gate|frunk|fl|..>
    "$B" -b --factory-startup --python scripts/blender/skf/convert.py -- appcar   # phone App car images, 8 paints
    "$B" -b --factory-startup --python scripts/blender/skf/convert.py -- inspect  # source objects -> TMP/inspect.json
    CAR=<car> "$B" ...                                                            # another cars/<car>.py

Source (gitignored): TMP/<the car's SRC>; Model Y: temp/skf/src/source/Tesla Model Y Performance 2026.obj (+ .mtl),
the OBJ inside the Sketchfab download. Its materials are flat colours, its panels separate components (door skins,
hood, tailgate cut along the real panel lines), so parts and zones come from components and a few side-view lines,
colours from materials; AO and normals are baked for the paint's light. The cabin and trunk are the mod's own
(cabin.py), not the source's interior; shared code (door slab, skeleton export, damage UV1, wheel, script block) in
scripts/blender/common/pzveh.py.
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
C = pv.CAR                                 # this car's values (cars/<car>.py; keys = the constants below)
SRC = os.path.join(TMP, *C["SRC"])
K = pv.K                                   # grid per metre; the source is in metres
SRC_C, BELT_Z, TIRE_OBJ = C["SRC_C"], C["BELT_Z"], C["TIRE_OBJ"]
SRC_SCALE, SRC_FLIP = C["SRC_SCALE"], C["SRC_FLIP"]
SKIN, MASK = 2048, 512

# ---- what each source object is (names from the OBJ; sizes in the build log or inspect) ----
DROP, DECIMATE, PAINT_MAT, GLASS_MATS, GLASS_OPAQUE, ROOF_PANE, MIRROR_CAP, LAMPS = (C[k] for k in (
    "DROP", "DECIMATE", "PAINT_MAT", "GLASS_MATS", "GLASS_OPAQUE", "ROOF_PANE", "MIRROR_CAP", "LAMPS"))
DROP_COMPS, CARBON, ARCH_LINER, PLATES, GLASS_BACKS, SEAL_CLIP, RAIL = (C[k] for k in (
    "DROP_COMPS", "CARBON", "ARCH_LINER", "PLATES", "GLASS_BACKS", "SEAL_CLIP", "RAIL"))
# skin colour (sRGB 0-255) per material: the source's (the car's MAT_RGB) and the mod's own; paint comes from the
# official renders (textures())
MAT_RGB = {**C["MAT_RGB"], "badge_chrome": (196, 200, 206), "badge_black": (8, 8, 10),
           "caliper_red": (180, 20, 28),             # Performance calipers (official RIMCLOSEUP, lit side)
           "badge_perf": (57, 61, 70),               # Performance badge plate (navy starburst, mean colour; models.md)
           "arch_liner": (16, 16, 18),               # arch_liners()
           "badge_etch": (150, 152, 156)}            # laser-etched badge (CERBERUS; textures(): a shade of the paint)
# chrome badges mirror the surroundings: bright on a dark paint, grey on a light one (median V >= 0.55: PearlWhite
# read 196 on ~210 paint, gone)
CHROME = ((200, 204, 210), (104, 108, 114))
# paint light (textures()): official-render paint quantile q = (base + up x upness(nz) + height x h) x AO term:
# (base, up, height); h = face centre height, 0 at the lowest face, 1 at the roof. Calibration knob. Only soft volume:
# the game lights a car by ambient alone in daylight (vehicle_multiuv.frag:72-96, no sun direction), so the skin keeps
# the shape (roof / hood over the sides, lower body darker where it reflects the ground, AO in the seams).
# The baked highlights that were here (B, b6f85cb: a shoulder band, a softbox lobe) sat on the same panels at every
# heading; on the rear haunch the band put the whole fender on the render's highlight quantiles (user 2026-10-27
# 「每台車這裡白白有點突兀」「反光效果不太自然」). A narrower set (0.12, 0.06, 0.3) / p10-p97 0.30-0.56 read as a flat
# sticker (tesla-sheen-1027e); a curvature term from the decimated mesh came out blotchy, smoothed it added nothing
PAINT_Q = (0.12, 0.25, 0.25)
# percentiles of all paint texels -> quantile of the official ramp (pv.official_ramp), plus the darkest / brightest
# texel's. Kept under the ramp's highlight end (Diamond Black's top 20 % of quantiles 47-192 sRGB): p50 where B had it
# (CAL's offsets stay valid), p10-p97 0.22-0.65 against B's 0.09-0.92
PAINT_TARGET = ((10, 0.22), (25, 0.31), (50, 0.415), (75, 0.51), (90, 0.59), (97, 0.65))
PAINT_ENDS = (0.03, 0.72)
PAINT_ALPHA = 254 / 255                    # skin alpha of the paint texels (textures(): the shader's paint flag)
LIGHT_RGB = {"head": (255, 250, 240), "tail": (255, 30, 30)}

# ---- part lines and panels, pre-centre grid (the car's; read off the source's panel edges, build log OUTLINE) ----
LINES, FRONT_Y, SILL_Z, ARCH, DOOR_Y, GATE_Z, REAR_ARCH, GATE_X, STOP_X = (C[k] for k in (
    "LINES", "FRONT_Y", "SILL_Z", "ARCH", "DOOR_Y", "GATE_Z", "REAR_ARCH", "GATE_X", "STOP_X"))
IN_DOOR, IN_GATE, PANELS, GUARDS, PANES = (C[k] for k in ("IN_DOOR", "IN_GATE", "PANELS", "GUARDS", "PANES"))
SEAL = (0.008, 0.02)                       # grid: dark strip behind every panel edge (depth, reach past the edge):
#                                             the source's panel gaps are real gaps, the ground showed through them
DOOR_REACH = 0.10                          # grid: a whole component goes to a door within this of its paint skin
#                                             (classify; the slab is pv.DOOR_T 0.06 deep, the farthest door part 0.08)
CUT, CUT_X, DOOR_OBJS, GATE_OBJS, GATE_COMPS = (C[k] for k in ("CUT", "CUT_X", "DOOR_OBJS", "GATE_OBJS", "GATE_COMPS"))
PLANES, CUT_X_Y, GATE_CUT_COMPS, GATE_HINGE = (C[k] for k in ("PLANES", "CUT_X_Y", "GATE_CUT_COMPS", "GATE_HINGE"))
# badges (badges(); the car's places): T on the frunk lid, TESLA on the light blade, MODEL Y on the tailgate
BADGE_OFF = 0.003                          # grid off the surface (no depth fight)
T_BADGE, TESLA, LENS_X, MODELY, CALIPER = (C[k] for k in ("T_BADGE", "TESLA", "LENS_X", "MODELY", "CALIPER"))
BADGE_Y, BLADE, PERF_BADGE = C["BADGE_Y"], C["BLADE"], C["PERF_BADGE"]
SWATCH = ("Badge_T", "Badge_TESLA", "Badge_MODELY", "Caliper") + (("Badge_CERB",) if C.get("CERBERUS") else ())
#                                            one flat-colour UV spot each (unwrap())
SWATCH_U = 0.03                            # UV0 strip kept for them at u > 1 - SWATCH_U
SMOKE_RGB = (62, 58, 60)                   # the light blade by day: smoked lens, so the black letters read
PARTS = ["Body"] + list(pv.DOORS)          # part index: 0 body, 1.. DOORS order (FL, FR, RL, RR, TrunkDoor, EngineDoor)
FRUNK_TUB = C["FRUNK_TUB"]                 # the bin under the frunk lid (frunk_tub())
ZN = list(pv.Z)                            # zone index -> name
CELL = {c: i for i, c in enumerate(pv.CABIN_CELLS)}
GLASS_ZONES = ("WinT", "WinH", "WinLH", "WinLT", "WinRH", "WinRT", "LightBarL")   # UV1 glass code order (the frag's
#                                                                                  GLASS_ZONE[], feat/edges-1025)
ROLL_N = 8                                 # a rolling tonneau's strips (tonneau_strips); strip 0 stays: the canister lid
BED_TUB, ROOF_BAR = C.get("BED_TUB"), C.get("ROOF_BAR")   # a pickup's bed and roof light bar (bed_tub, roof_bar)


def lin(name, z):
    if len(LINES[name]) > 2:               # a polyline (z ascending), held flat past its ends
        y, zz = np.array(LINES[name]).T
        return np.interp(z, zz, y)
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
    up = z > IN_DOOR["up"]
    fd = (y < FRONT_Y + t) & (z > SILL_Z - t) & (y > np.where(up, lin("BF", z), lin("S", z)) - t)
    rd = (z > SILL_Z - t) & np.where(up, (y < lin("BR", z) + t) & (y > lin("D", z) - t),
                                     (y < lin("S", z) + t) & (y > lin("R1", z) - t) & ((z > ARCH[0] - t) | (y > ARCH[1] - t)))
    side = np.abs(x) > IN_DOOR["x"]
    left = x < 0
    return np.where(side & fd, np.where(left, 1, 2), np.where(side & rd, np.where(left, 3, 4), 0))


def in_gate(p, t=0.0):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    g = IN_GATE
    return (y < g["y"] + t) & (z > g["z"] - t) & (np.abs(x) < np.where(z > g["up"], g["x_up"], GATE_X) + t)


CARBON_EDGE = {}                           # CARBON zone index -> its band's inner border (x, coordinate), edit()


def lower_hull(p, depth):
    """Lower convex hull (monotone chain) of points p (N x 2: x, coordinate), moved depth up the coordinate: the
    border of a CARBON edge band along a convex outline (the trunk lid's trailing edge seen from above)."""
    h = []
    for q in p[np.lexsort((p[:, 1], p[:, 0]))]:
        while len(h) > 1 and (h[-1][0] - h[-2][0]) * (q[1] - h[-2][1]) <= (h[-1][1] - h[-2][1]) * (q[0] - h[-2][0]):
            h.pop()
        if not h or q[0] > h[-1][0]:
            h.append(q)
    h = np.array(h)
    return h[:, 0], h[:, 1] + depth


def src_frame():
    """Source as imported (import_source) -> pre-centre grid frame, SRC_C centred. OBJ (-Z forward, Y up): front -X,
    left -Y; SRC_FLIP: front +X, left +Y (the glTF importer's Z up). SRC_SCALE: metres per source unit. SRC_YFRONT
    (an FBX, Z up): front -Y, left +X, SRC_C the source's (x, y) centre, ground at source z SRC_YFRONT, and
    SRC_STRETCH (width, length, height) factors onto the official size."""
    if C.get("SRC_YFRONT") is not None:
        sx, sy, sz = (K * SRC_SCALE * f for f in C["SRC_STRETCH"])
        return Matrix(((-sx, 0, 0, sx * SRC_C[0]), (0, -sy, 0, sy * SRC_C[1]), (0, 0, sz, -sz * C["SRC_YFRONT"]),
                       (0, 0, 0, 1)))
    s = K * SRC_SCALE * (-1 if SRC_FLIP else 1)
    return Matrix(((0, s, 0, -s * SRC_C[1]), (-s, 0, 0, s * SRC_C[0]), (0, 0, K * SRC_SCALE, 0), (0, 0, 0, 1)))


def import_source():
    """The source into an empty scene, OBJ, FBX or glTF; glTF / FBX nest meshes under empties: unparented in place."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if SRC.lower().endswith((".glb", ".gltf", ".fbx")):
        if SRC.lower().endswith(".fbx"):
            bpy.ops.import_scene.fbx(filepath=SRC)
        else:
            bpy.ops.import_scene.gltf(filepath=SRC)
        for o in [o for o in bpy.data.objects if o.type == "MESH"]:
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
        for o in [o for o in bpy.data.objects if SRC.lower().endswith(".fbx") and o.type == "MESH"
                  and not len(o.data.polygons)]:
            bpy.data.objects.remove(o)              # the FBX's empty meshes
    else:
        bpy.ops.wm.obj_import(filepath=SRC, forward_axis="NEGATIVE_Z", up_axis="Y")


def tire_groups(co):
    """The tires in one tire object's points: a glTF source merges all four into one object (by material), so split
    at the centre line and at gaps over 0.3 along y."""
    for c in (co[co[:, 0] < 0], co[co[:, 0] >= 0]):
        if not len(c):
            continue
        ys = np.sort(c[:, 1])
        gap = np.argmax(np.diff(ys)) if len(ys) > 1 else 0
        if len(ys) > 1 and ys[gap + 1] - ys[gap] > 0.3:
            yield from (c[c[:, 1] <= ys[gap]], c[c[:, 1] > ys[gap]])
        else:
            yield c


def drop_comps(o, name):
    """Delete the components of o whose bbox centre lies in a DROP_COMPS box naming it: a glTF source merges objects
    by material, so its interior and lamp lenses share objects with exterior parts."""
    boxes = [(np.array(lo), np.array(hi)) for objs, lo, hi in DROP_COMPS if name in objs]
    if not boxes:
        return
    me = o.data
    comp = np.empty(len(me.polygons), np.int64)
    me.attributes["comp"].data.foreach_get("value", comp)
    lv = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", lv)
    lc = np.repeat(comp, [p.loop_total for p in me.polygons])
    co = pv.mesh_co(o)[lv]
    lo, hi = np.full((comp.max() + 1, 3), np.inf), np.full((comp.max() + 1, 3), -np.inf)
    np.minimum.at(lo, lc, co)
    np.maximum.at(hi, lc, co)
    c = (lo + hi) / 2
    gone = np.zeros(len(c), bool)
    for blo, bhi in boxes:
        gone |= ((c > blo) & (c < bhi)).all(1)
    if gone[comp].any():
        pv.keep_faces(o, ~gone[comp])
        print("DROP_COMPS", name, int(gone[np.unique(comp)].sum()), "components", int(gone[comp].sum()), "faces")


# ---------------------------------------------------------------- source

def load_source():
    """Source -> one mesh 'car' in the pre-centre frame, free corner normals, face attributes src (object index) and
    comp (welded connected component within the object). Returns the object names (src index -> name)."""
    import_source()
    P = src_frame()
    tires = []
    names, obs = [], []
    for o in sorted((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: o.name):
        me = o.data
        if o.name.startswith(TIRE_OBJ):            # tires: wheel centres and outer faces for the script
            co = np.array([(P @ o.matrix_world @ v.co)[:] for v in me.vertices])
            tires += [(c.min(0), c.max(0)) for c in tire_groups(co)]
        if o.name.startswith(DROP):
            bpy.data.objects.remove(o)
            continue
        M = P @ o.matrix_world
        R = M.to_3x3().normalized()
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.corner_normals.foreach_get("vector", cn)
        if C.get("SRC_STRETCH"):        # unequal axes: normals by the inverse transpose (row vectors: n M^-1)
            cn = cn.reshape(-1, 3) @ np.linalg.inv(np.array(M.to_3x3()))
            cn /= np.maximum(np.linalg.norm(cn, axis=1, keepdims=True), 1e-12)
        else:
            cn = cn.reshape(-1, 3) @ np.array(R).T
        me.transform(M)
        o.matrix_world = Matrix()
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", cn.ravel())
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        # coincident copies (the glTF's tail lamp lens layers) weld onto the same vertices; the FBX importer keeps one
        # of two faces on the same vertices (build's read-back)
        bm.verts.index_update()
        seen, twins = set(), []
        for f in bm.faces:
            k = frozenset(v.index for v in f.verts)
            if k in seen:
                twins.append(f)
            seen.add(k)
        if twins:
            bmesh.ops.delete(bm, geom=twins, context="FACES_ONLY")
            print("TWINS", o.name, len(twins), "faces")
        bm.to_mesh(me)
        bm.free()
        for objs, lo, hi, ax, (d0, d1) in C.get("DROP_FACES", ()):   # faces by centre and normal (a car's config)
            if o.name in objs:
                me.update()
                fc, fn = pv.face_centres(o), np.array([p.normal[:] for p in me.polygons])
                d = fn @ np.array(ax, float)
                gone = (fc > lo).all(1) & (fc < hi).all(1) & (d >= d0) & (d <= d1)
                pv.keep_faces(o, ~gone)
                print("DROP_FACES", o.name, int(gone.sum()), "faces")
        name = o.name.split("_Mesh")[0] if "_Mesh" in o.name else o.name
        target = next((t for p, t in DECIMATE.items() if o.name.startswith(p)), None)
        if any(name in objs for objs, _, _ in DROP_COMPS):   # drop first, decimate what is left
            _label(o, len(names))
            drop_comps(o, name)
        if target:
            pv.decimate(o, target)
        _label(o, len(names))
        names.append(name)
        if target:          # the components' triangles now: CUT / GATE_CUT_COMPS / ROOF_PANE / MIRROR_CAP keys
            comp = np.array([d.value for d in me.attributes["comp"].data])
            fc, cnt = pv.face_centres(o), np.bincount(comp)
            big = [(int(cnt[k]), np.round(fc[comp == k].mean(0), 2).tolist()) for k in np.argsort(-cnt)[:12]]
            print("COMPS", name, "(tris, mean face centre)", big)
        obs.append(o)
    # wheels: (side, centre y, centre z, outer |x|) per tire, pre-centre frame, and the tire's radius and width (the
    # procedural wheel is built to them: the arches were modelled round these tires)
    wl = sorted(((-1 if hi[0] + lo[0] < 0 else 1, float((lo[1] + hi[1]) / 2), float((lo[2] + hi[2]) / 2),
                  float(max(-lo[0], hi[0]))) for lo, hi in tires), key=lambda w: (-w[1], w[0]))   # FL, FR, RL, RR
    size = np.array([(hi - lo) for lo, hi in tires])
    tire = (float(size[:, 1:].mean() / 2), float(size[:, 0].mean()))
    print("SOURCE tires: radius %.4f width %.4f centres" % tire, [np.round(w, 3).tolist() for w in wl])
    if C.get("TIRE"):   # the official tyre and track (metres) where the source's differ; the centres stay the source's
        t = C["TIRE"]
        tire = (t["r"] * K, t["w"] * K)
        wl = [(sd, yc, zc, t["track"] * K / 2 + tire[1] / 2 + pv.WHEEL_INSET) for sd, yc, zc, _ in wl]
        print("TIRE official: radius %.4f width %.4f outer |x| %.4f" % (*tire, wl[0][3]))
    badges(obs, names)
    if CALIPER:
        calipers(obs, names, wl, tire)
    if ARCH_LINER:
        arch_liners(obs, names, wl, tire)
    for name, poly, want, mat in PLATES:   # flat backing polygons where a dropped part left a see-through gap
        _add(obs, names, name, poly, [tuple(range(len(poly)))], Vector(want), mat)
    pv.select_only(*obs)
    bpy.ops.object.join()
    car = bpy.context.view_layer.objects.active
    car.name = pv.NAME
    return car, names, wl, tire


def stage_inspect():
    """Every source object as the build sees it, to fill a car's config: name (the short name CUT / DOOR_OBJS /
    GATE_OBJS use; DROP / DECIMATE / TIRE_OBJ match name prefixes), faces, triangles, materials, bbox in the
    pre-centre grid frame (with this config's SRC_C, SRC_SCALE, SRC_FLIP). Also the source's bbox centre in source
    units (SRC_C). Table on stdout, TMP/inspect.json with each object's welded components of 20+ triangles (tris =
    the CUT / GATE_COMPS key, bbox; a glTF source merges objects by material, so its parts are components). Size it
    first: size_m is in source units, SRC_SCALE = official length / size along the length."""
    import_source()
    P = np.array(src_frame())
    rows, raw = [], []
    for o in sorted((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: o.name):
        me = o.data
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        M = np.array(o.matrix_world)
        w = co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]           # as imported, metres
        g = w @ P[:3, :3].T + P[:3, 3]
        raw.append((w.min(0), w.max(0)))
        mi = np.empty(len(me.polygons), np.int64)
        me.polygons.foreach_get("material_index", mi)
        mats = sorted({(me.materials[i].name if i < len(me.materials) and me.materials[i] else "-") for i in np.unique(mi)})
        ob = o.copy()
        ob.data = me.copy()
        ob.data.transform(src_frame() @ o.matrix_world)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        bm.to_mesh(ob.data)
        bm.free()
        _label(ob, 0)
        comp = np.array([d.value for d in ob.data.attributes["comp"].data])
        cc = pv.mesh_co(ob)
        fv = [p.vertices[:] for p in ob.data.polygons]
        comps = []
        for k in np.unique(comp):
            f = np.flatnonzero(comp == k)
            if len(f) >= 20:
                v = cc[np.unique(np.concatenate([fv[i] for i in f]))]
                comps.append(dict(tris=len(f), min=np.round(v.min(0), 3).tolist(), max=np.round(v.max(0), 3).tolist()))
        rows.append(dict(name=o.name.split("_Mesh")[0], faces=len(me.polygons), tris=sum(p.loop_total - 2 for p in me.polygons),
                         materials=mats, min=np.round(g.min(0), 4).tolist(), max=np.round(g.max(0), 4).tolist(),
                         comps=sorted(comps, key=lambda r: -r["tris"])))
    lo, hi = np.min([r[0] for r in raw], 0), np.max([r[1] for r in raw], 0)
    src_c = np.round((lo[:2] + hi[:2]) / 2, 4).tolist()
    print(f"{'object':<34}{'faces':>8}{'tris':>8}  {'min x y z':<26}{'max x y z':<26}materials")
    for r in rows:
        print(f"{r['name']:<34}{r['faces']:>8}{r['tris']:>8}  {' '.join('%.3f' % v for v in r['min']):<26}"
              f"{' '.join('%.3f' % v for v in r['max']):<26}{', '.join(r['materials'])}")
    total = dict(objects=len(rows), faces=sum(r["faces"] for r in rows), tris=sum(r["tris"] for r in rows),
                 size_m=np.round(hi - lo, 4).tolist(), src_c=src_c)
    print("INSPECT", SRC, json.dumps(total), "(SRC_C in config:", list(SRC_C), ")")
    os.makedirs(TMP, exist_ok=True)
    json.dump(dict(src=SRC, total=total, objects=rows), open(os.path.join(TMP, "inspect.json"), "w"), indent=1)


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


def arch_liners(obs, names, wl, tire):
    """Black wheel-arch liners (ARCH_LINER, for a source without them): per wheel an arc `gap` outside the tire from
    `arc` deg (0 = ahead of the axle, 90 = over it) round to behind it, across from the tire's outer face to `inner`
    inboard of its inner face, and a wall closing the arc inboard; all of it faces the wheel. Without them the cabin
    shell's rays left through the arches onto the wheel parts (black wedges over the wheels) and the arches showed
    the ground."""
    g = ARCH_LINER
    r, width = tire
    R = r + g["gap"]
    th = np.radians(np.linspace(*g["arc"], g["n"]))
    pts, faces, want = [], [], []
    for side, yc, zc, xo in wl:
        if "x" in g:                                 # the liner's outer |x| (inside the cladding)
            xo = g["x"] + pv.WHEEL_INSET
        xa, xb = side * (xo - pv.WHEEL_INSET), side * (xo - pv.WHEEL_INSET - width - g["inner"])   # outer, inner
        k = len(pts)
        pts += [(x, yc + R * math.cos(t), zc + R * math.sin(t)) for t in th for x in (xa, xb)]
        pts.append((xb, yc, zc))                     # the wall's centre (the axle)
        for i in range(len(th) - 1):
            a, b, tm = k + 2 * i, k + 2 * i + 2, (th[i] + th[i + 1]) / 2
            faces += [(a, b, b + 1, a + 1), (a + 1, b + 1, len(pts) - 1)]
            want += [Vector((0, -math.cos(tm), -math.sin(tm))), Vector((side, 0, 0))]
    _add(obs, names, "ArchLiner", pts, faces, want, "arch_liner")


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
    # T: read from ahead of the car (u = -x), its top up the surface. Model Y: on the lid's slope, rays straight down
    # (along the lid normal, the stem tip's ray would pass the lid's front edge onto the light bar), so the outline is
    # stretched by 1 / normal z; ray None: along -normal
    if T_BADGE:
        y, tw, th, z0, nrm, ray = T_BADGE
        n = Vector(nrm).normalized()
        flat("Badge_T", [[[(u * tw, (v + 0.05) * th / (nrm[2] if ray else 1)) for u, v in t_logo()[0]]]],
             ((0, y, z0), (-1, 0, 0), (0, -n.z, n.y), n), "badge_chrome", ray=ray)
    # the blade lens (BLADE, Model Y): the source's blade faces back on a 1.5 cm strip (z 0.922-0.937; the underside
    # and a sloped housing below it), the real blade is ~4.5 cm with the letters inside. A plate over the strip across
    # the tailgate, upright, following the bar's curve in plan; it is the blade (smoked, glows as a tail light)
    ray_y, face_y = BADGE_Y                # rear badges: ray start y (behind the car), letter frame y
    if TESLA:
        zc, ch, pitch, lh = TESLA
        if BLADE:
            xs = np.linspace(-LENS_X, LENS_X, 21)
            ys = [bvh.ray_cast(Vector((x, ray_y, zc)), Vector((0, 1, 0)))[0].y - BADGE_OFF / 2 for x in xs]
            _add(obs, names, "Badge_BLADE", [Vector((x, y, zc + s * lh / 2)) for x, y in zip(xs, ys) for s in (-1, 1)],
                 [(2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1) for i in range(len(xs) - 1)], Vector((0, -1, 0)),
                 "badge_black")
            bvh = tree()
        # rear lettering, read from behind (u = +x)
        letters, wid = stroke_text("TESLA", WORDMARK, 0.22, pitch=pitch / ch)
        flat("Badge_TESLA", [[[(u * ch, v * ch) for u, v in q] for q in g] for g in letters],
             ((-wid * ch / 2, face_y, zc - ch / 2), (1, 0, 0), (0, 0, 1), (0, -1, 0)), "badge_black", planar=True)
    if MODELY:                             # (text, left x, baseline z, cap height)
        text, x0, z0, ch = MODELY
        letters, _ = stroke_text(text, SANS, 0.16)
        flat("Badge_MODELY", [[[(u * ch, v * ch) for u, v in q] for q in g] for g in letters],
             ((x0, face_y, z0), (1, 0, 0), (0, 0, 1), (0, -1, 0)), "badge_chrome", planar=True)
    if PERF_BADGE:                         # the Performance badge plate (centre x, z, width, height)
        x, z, w, h = PERF_BADGE
        flat("Badge_PERF", [[[(0, 0), (w, 0), (w, h), (0, h)]]],
             ((x - w / 2, face_y, z - h / 2), (1, 0, 0), (0, 0, 1), (0, -1, 0)), "badge_perf", planar=True)
    if C.get("CERBERUS"):                  # Cyberbeast's laser-etched Cerberus: bitmap rows (top first), runs as quads
        cb = C["CERBERUS"]
        rows = cb["bitmap"]
        px = cb["w"] / len(rows[0])
        quads = [[(i * px, (len(rows) - 1 - r) * px), ((j + 1) * px, (len(rows) - 1 - r) * px),
                  ((j + 1) * px, (len(rows) - r) * px), (i * px, (len(rows) - r) * px)]
                 for r, row in enumerate(rows) for i, j in _runs(row)]
        flat("Badge_CERB", [quads], ((cb["x"] - cb["w"] / 2, face_y, cb["z"] - len(rows) * px / 2), (1, 0, 0),
                                     (0, 0, 1), (0, -1, 0)), "badge_etch", planar=True)
    if C.get("HEADBAR"):                   # (z, height, half width): the front light bar (Cybertruck). The source's bar
        zc, lh, hx = C["HEADBAR"]          # is a strip under the hood's edge, lit only at its two ends from the game's
        xs = np.linspace(-hx, hx, 21)      # camera (tesla-ctbody-1030c night-S): an upright plate across the nose
        ys = [bvh.ray_cast(Vector((x, 4.0, zc)), Vector((0, -1, 0)))[0].y + BADGE_OFF / 2 for x in xs]
        _add(obs, names, "Badge_HEADBAR", [Vector((x, y, zc + s * lh / 2)) for x, y in zip(xs, ys) for s in (-1, 1)],
             [(2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1) for i in range(len(xs) - 1)], Vector((0, 1, 0)),
             LAMPS["head"][0])


def _runs(row):
    """(first, last) column of each run of '#' in a bitmap row."""
    out, i = [], 0
    while i < len(row):
        if row[i] == "#":
            j = i
            while j + 1 < len(row) and row[j + 1] == "#":
                j += 1
            out.append((i, j))
            i = j
        i += 1
    return out


def edit(car, names):
    """Cut in bmesh: bisect the straddling components along LINES, the rear lamps at the gate edge."""
    bm = bmesh.new()
    bm.from_mesh(car.data)
    si, ci = bm.faces.layers.int["src"], bm.faces.layers.int["comp"]
    bm.faces.ensure_lookup_table()
    groups = {}
    for f in bm.faces:
        groups.setdefault((f[si], f[ci]), []).append(f)
    # (object, triangles) keys follow the decimation: a key that no longer matches would silently skip its cuts
    missing = set(CUT) - {(names[s], len(fs)) for (s, _), fs in groups.items()}
    if missing:
        raise SystemExit(f"CUT keys match no component (sizes: the build's COMPS lines): {sorted(missing)}")
    for (s, c), fs in groups.items():
        key = (names[s], len(fs))
        cuts = CUT.get(key, ())
        if names[s].startswith(CUT_X):
            cuts = ("X+", "X-")
        for cname in cuts:
            ymax = None                    # PLANES and X+- (CUT_X_Y): only the faces centred behind this y
            if cname in ("X+", "X-"):
                co, no, ymax = (GATE_X if cname == "X+" else -GATE_X, 0, 0), (1, 0, 0), CUT_X_Y
            elif cname in PLANES:
                co, no, ymax = PLANES[cname]
            else:
                co, no = plane(cname)
            fs = [f for f in bm.faces if f.is_valid and f[si] == s and f[ci] == c
                  and (ymax is None or f.calc_center_median().y < ymax)]
            geom = list({*fs, *[e for f in fs for e in f.edges], *[v for f in fs for v in f.verts]})
            bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=co, plane_no=no)
    # CARBON zones with `edge`: cut the paint along the band's inner border, so the band runs along it instead of
    # along big triangles (their sawtooth showed on the trunk lid)
    pm = [m.name for m in car.data.materials].index(PAINT_MAT)
    for i, zn in enumerate(CARBON["zones"] if CARBON else ()):
        if "edge" not in zn:
            continue
        k, depth = zn["edge"]
        lo, hi = np.array(zn["lo"]), np.array(zn["hi"])
        fs = {f for f in bm.faces if f.material_index == pm and (lo < np.array(f.calc_center_median())).all()
              and (np.array(f.calc_center_median()) < hi).all()}
        bx, by = CARBON_EDGE[i] = lower_hull(np.array([(v.co.x, v.co[k]) for f in fs for v in f.verts]), depth)
        for x0, x1, y0, y1 in zip(bx[:-1], bx[1:], by[:-1], by[1:]):
            co, no = np.zeros(3), np.zeros(3)
            co[0], co[k], no[0], no[k] = x0, y0, y0 - y1, x1 - x0
            cut = [f for f in fs if f.is_valid and min(v.co.x for v in f.verts) < x1
                   and max(v.co.x for v in f.verts) > x0]
            geom = list({*cut, *[e for f in cut for e in f.edges], *[v for f in cut for v in f.verts]})
            res = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=co, plane_no=no)
            fs |= {g for g in res["geom"] if isinstance(g, bmesh.types.BMFace)}
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


def match(spec, obj, csize):
    """Faces of a source object (spec = name) or of its components of some sizes (spec = (name, triangles or a tuple
    of them; a decimated pair of mirror parts can differ by one)): a glTF source merges parts by material."""
    if isinstance(spec, str):
        return obj == spec
    m = (obj == spec[0]) & np.isin(csize, spec[1])
    if not m.any():                        # sizes follow the decimation: say so instead of matching nothing
        raise SystemExit(f"{spec} matches no component (sizes: the build's COMPS lines)")
    return m


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
    paint = mat == PAINT_MAT
    # CARBON: paint the real car has in black (Model 3 Performance's carbon spoiler $SLR1, its black lower front
    # intake): paint faces in each zone's box (lo, hi); with `edge` (axis, depth) only those within depth of the
    # outline's lowest coordinate on that axis (CARBON_EDGE: the lid's trailing edge curves forward towards the sides,
    # and edit() cut the faces along that border)
    carbon = np.zeros(n, bool)
    for i, zn in enumerate(CARBON["zones"] if CARBON else ()):
        box = paint & (cen > zn["lo"]).all(1) & (cen < zn["hi"]).all(1)
        if "edge" in zn:
            box &= cen[:, zn["edge"][0]] < np.interp(cen[:, 0], *CARBON_EDGE[i])
        carbon |= box
    paint &= ~carbon
    glass = np.isin(mat, GLASS_MATS) & ~np.isin(obj, GLASS_OPAQUE)
    part = np.zeros(n, np.int64)
    ax, ay, az = np.abs(ccen[:, 0]), ccen[:, 1], ccen[:, 2]
    left = ccen[:, 0] < 0
    # body panels by component (PANELS)
    pn = PANELS
    fd = paint & (ax > pn["x"]) & (ay > pn["front"][0]) & (ay < pn["front"][1]) & (az < pn["z"])
    part[fd] = np.where(left, 1, 2)[fd]
    rd = paint & (ax > pn["x"]) & (ay > pn["rear"][0]) & (ay <= pn["rear"][1]) & (az < pn["z"])
    part[rd] = np.where(left, 3, 4)[rd]
    part[paint & (ax < 0.1) & (ay < pn["gate"][0]) & (az > pn["gate"][1])] = 5
    part[paint & (ax < 0.1) & (ay > pn["lid"][0]) & (az > pn["lid"][1])] = 6
    # a source whose doors are not separate (FACE_PARTS objects): their paint faces by face centre, along the panel gaps
    fp = paint & np.isin(obj, C.get("FACE_PARTS", ())) & (np.abs(cen[:, 0]) > pn["x"]) & (cen[:, 2] < pn["z"])
    part[fp] = in_door(cen[fp])
    for pname, objs in C.get("PART_OBJS", {}).items():   # whole objects that are a part (the tonneau)
        part[np.isin(obj, objs)] = PARTS.index(pname)
    # door hardware, frames and panes: whole components inside a door (2.5 cm slack), cut components face by face. A
    # strip that runs past its one door's edge (the belt mouldings end under the B-pillar and quarter trim) goes face
    # by face too: whole on the body it was a black bar across the far window, seen through the roof glass with the
    # far door hidden behind that glass's depth (user 2026-10-25 images 10, 11, 13). A whole component also has to lie
    # within DOOR_REACH of that door's paint skin: the side-view window and |x| > IN_DOOR x also take cabin bits off an
    # object that mixes interior and trim (Model 3's Object_13: an underbody block at the B-pillar foot, 15 cm inboard
    # of the front door, swung out with it and floated under the open door)
    cut = np.array([(o, s) in CUT for o, s in zip(obj, csize)])
    cand = np.isin(obj, DOOR_OBJS) & ~paint | match(MIRROR_CAP, obj, csize)   # (a paint mirror cap: on its door)
    whole = cand & ~cut
    skin = {k: bvh_of([(co, fv[paint & (part == k)])]) for k in range(1, 5)}
    for k in np.unique(key[whole]):
        f = np.flatnonzero(key == k)
        vs = co[np.unique(fv[f])]
        d = in_door(vs, 0.025)
        door = np.unique(d[d > 0])
        if len(door) != 1 or all(skin[door[0]].find_nearest(v, DOOR_REACH)[0] is None for v in vs):
            continue
        if (d == d[0]).all():
            part[f] = d[0]
        elif not glass[f[0]]:
            part[f] = in_door(cen[f])
    sel = cand & cut
    part[sel] = in_door(cen[sel])
    # the mirror cap is body colour (official FRONT34; the source paints it black_refl), its base and glass stay;
    # set after the door split, which takes door hardware by its non-paint material
    mirror = match(MIRROR_CAP, obj, csize) & (part > 0)
    paint = paint | mirror
    gate = np.isin(obj, GATE_OBJS)
    for o, s, sy in GATE_COMPS:
        if not ((obj == o) & (csize == s)).any():
            raise SystemExit(f"GATE_COMPS {(o, s)} matches no component (sizes: the build's COMPS lines)")
        gate |= (obj == o) & (csize == s) & (np.sign(ay) == sy) & (ax < 0.1)
    gsel = gate & (np.isin(obj, [o for o, _, _ in GATE_COMPS]) | in_gate(cen))
    for o, s in GATE_CUT_COMPS:            # a lid cut out of a bigger panel (edit(): PLANES, X+-), by face centre
        if not ((obj == o) & (csize == s)).any():
            raise SystemExit(f"GATE_CUT_COMPS {(o, s)} matches no component (sizes: the build's COMPS lines)")
        gsel |= (obj == o) & (csize == s) & in_gate(cen)
    part[gsel | np.isin(obj, ("Badge_BLADE", "Badge_TESLA", "Badge_MODELY", "Badge_PERF"))] = 5
    part[obj == "Badge_T"] = 6
    # lamps. Tail: the red light bar (a 1 cm strip on the spoiler's lower lip, about a pixel in game), the corner
    # lamps, and the rear face of the smoked light-bar cover across the tailgate (LAMPS blade), which glows red at
    # night like the real light blade (night-N showed one corner patch only)
    head = np.isin(mat, LAMPS["head"])
    tail = np.isin(mat, LAMPS["tail"]) & (cen[:, 2] > LAMPS["tail_z"]) & (cen[:, 1] < LAMPS["tail_y"])
    fnorm = np.array([p.normal[:] for p in me.polygons])
    blade = (obj == LAMPS["blade"]) & (fnorm[:, 1] < -0.5) | (obj == "Badge_BLADE")
    tail |= blade
    lamp = np.where(head, 1, np.where(tail, 2, 0))
    # zones
    zone = np.full(n, ZN.index("Roof"))
    L = cen[:, 0] < 0
    def put(m, l, r):
        zone[m & L] = ZN.index(l)
        zone[m & ~L] = ZN.index(r)
    (gy, gz, gx), (ry, rz, rx) = GUARDS["front"], GUARDS["rear"]
    put(paint & (part == 0) & (cen[:, 1] > gy) & (cen[:, 2] < gz) & (np.abs(cen[:, 0]) > gx), "GuardLH", "GuardRH")
    put(paint & (part == 0) & (cen[:, 1] < ry) & (cen[:, 2] < rz) & (np.abs(cen[:, 0]) > rx), "GuardLT", "GuardRT")
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
    gzn = np.where(match(ROOF_PANE, obj, csize), "LightBarL",
                   np.where((ax < 0.1) & (ay > 0), "WinT", np.where(ax < 0.1, "WinH",
                   np.where(np.isin(part, (1, 2)), np.where(L, "WinLH", "WinRH"), np.where(L, "WinLT", "WinRT")))))
    zone[glass] = [ZN.index(z) for z in gzn[glass]]
    pane = np.full(n, -1)
    pane[glass] = [GLASS_ZONES.index(z) for z in gzn[glass]]
    rgb = np.array([MAT_RGB.get(m) or (0, 0, 0) for m in mat], float) / 255
    rgb[blade] = np.array(SMOKE_RGB) / 255
    if CARBON:
        rgb[carbon] = np.array(CARBON["rgb"]) / 255
    print("CLASSIFY parts", {PARTS[k]: int((part == k).sum()) for k in range(len(PARTS))}, "glass", int(glass.sum()),
          "lamps head/tail", int(head.sum()), int(tail.sum()))
    # RAIL: 0..1 weight of the median paint tone (textures()), body panels only
    rail = paint * (part == 0) * pv.smoothstep(*RAIL, cen[:, 2]) if RAIL else np.zeros(n)
    return dict(part=part, zone=zone, rgb=rgb, paint=paint, lamp=lamp, glass=glass, pane=pane, obj=obj, csize=csize,
                badge=np.array([o.startswith(("Badge_", "Caliper")) for o in obj]),
                mat=mat, mirror=mirror, carbon=carbon, rail=rail)


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
    paint in skin order; Create.Motor sets it with the skin). Only inside this car's Specs entry: another car's
    colors may carry the same paint lines."""
    path = os.path.join(pv.MEDIA, "lua", "shared", "MinidoracatTesla", "Core.lua")
    text = open(path, encoding="utf-8").read()
    key = '["Base.%s"] = {' % pv.NAME
    start = text.find(key)
    if start < 0:
        raise SystemExit(f"Core.lua: no Specs entry {key}")
    end = text.index("\n    },", start)               # the entry's closing brace
    block = text[start:end]
    for p, code in pv.PAINTS:
        h, s, v = hsvs[p]
        # (code and weight, when the line has them, stay as they are)
        block, n = re.subn(r'(\{ name = "%s"(?:, code = "[^"]*")?(?:, weight = \d+)?), h = [0-9.]+, s = [0-9.]+, '
                           r'v = [0-9.]+ \}' % p, lambda m: f"{m.group(1)}, h = {h}, s = {s}, v = {v} }}", block)
        if n != 1:
            raise SystemExit(f"Core.lua {key}: {n} colour lines for {p}")
    open(path, "w", encoding="utf-8", newline="\n").write(text[:start] + block + text[end:])
    print("LUA colors", hsvs)


def textures(car, c):
    zone_rgb = np.array([pv.Z[z] for z in ZN], float)
    aux = np.stack([c["paint"].astype(float), (c["lamp"] > 0).astype(float), (c["lamp"] == 2).astype(float)], 1)
    fz = pv.face_centres(car)
    hgt = np.repeat(((fz[:, 2] - fz[:, 2].min()) / np.ptp(fz[:, 2]))[:, None], 3, 1)    # 0 at the lowest face, 1 at the roof
    layers = {"col": c["rgb"], "zone": zone_rgb[c["zone"]], "aux": aux, "hgt": hgt,
              "badge": np.repeat(np.where(c["mat"] == "badge_chrome", 1.0, np.where(c["mat"] == "badge_etch", 0.62,
                                                                                    0.5 * c["badge"]))[:, None], 3, 1)}
    if c["rail"].any():
        layers["rail"] = np.repeat(c["rail"][:, None], 3, 1)
    b = bake(car, layers)
    col, zon, aux, ao = b["col"][..., :3], b["zone"][..., :3], b["aux"][..., :3], b["ao"][..., 0]
    nrm = b["nrm"][..., :3] * 2 - 1
    nz = nrm[..., 2]
    paint = aux[..., 0] > 0.5
    # badges flat: their strokes overlap at the joints, coplanar faces whose AO rays start on each other (dark specks)
    shade = np.where(b["badge"][..., 0] > 0.25, 1.0, 0.55 + 0.45 * ao)
    chrome = b["badge"][..., 0] > 0.75
    # paint: the source is one flat colour, so its shape comes from the baked normal (up-facing a little brighter)
    # and the height (the lower body reflects the ground) times AO (the seams); the quantile picks the official
    # render's paint colour there (official_ramp), then CAL / GAIN
    lit = 0.55 + 0.45 * ao
    q = (PAINT_Q[0] + PAINT_Q[1] * np.clip((nz + 0.3) / 1.2, 0, 1) + PAINT_Q[2] * b["hgt"][..., 0]) * lit
    # AO samples are noisy and the ramp is steep in places: blurred inside the paint (about 6 px of 2048), else flat
    # panels came out speckled
    pm = paint.astype(np.float32)
    den = np.maximum(pv.box_blur(pv.box_blur(pm, 3), 3), 1e-6)
    q = (pv.box_blur(pv.box_blur(q * pm, 3), 3) / den)[paint]
    # spread: a monotone remap of q's percentiles onto PAINT_TARGET; equal q stay equal (no texel-rank ties)
    # (a car may set its own: stainless reads dark on its flanks and bright on top in the official renders)
    pc, tg = zip(*C.get("PAINT_TARGET", PAINT_TARGET))
    ends = C.get("PAINT_ENDS", PAINT_ENDS)
    q = np.interp(q, [q.min(), *np.percentile(q, pc), q.max()], [ends[0], *tg, ends[1]])
    if "rail" in b:                        # RAIL: the median tone
        q += (dict(PAINT_TARGET)[50] - q) * b["rail"][..., 0][paint]
    # skin alpha 254 marks the paint for the shader's sheen (MinidoracatTesla_vehicle.frag): vanilla reads alpha only
    # as "1 - a of the paint tint" (vehicle_multiuv.frag:144), so the paint takes 1/255 of the tint, under a level
    badge = b["badge"][..., 0] > 0.25
    etch = (b["badge"][..., 0] > 0.56) & (b["badge"][..., 0] < 0.7) & bool(C.get("CERBERUS"))
    hsvs = {}
    for p, code in pv.PAINTS:
        # the finish flag: per paint where the car sets one (PAINT_ALPHAS: 253 stainless, 252 satin film)
        pa = C["PAINT_ALPHAS"].get(p, C["PAINT_ALPHA_DEFAULT"]) / 255 if C.get("PAINT_ALPHAS") else PAINT_ALPHA
        alpha = np.where(paint & ~badge, pa, 1.0)[..., None]
        ramp = pv.official_ramp(code) if code else pv.film_ramp(C["FILMS"][p])
        xp = (np.arange(len(ramp)) + 0.5) / len(ramp)
        a_, b_ = (np.array(t, np.float32) for t in pv.CAL[p])
        s = col * shade[..., None]
        s[paint] = np.clip(a_ * np.stack([np.interp(q, xp, ramp[:, i]) for i in range(3)], -1) / pv.GAIN + b_, 0, 1)
        s[chrome] = np.array(CHROME[int(np.median(s[paint].max(-1)) >= 0.55)]) / 255
        s[etch] = np.median(s[paint], 0) * 0.78     # etched into the steel (and seen through a film): a shade darker
        pv.save_png(np.concatenate([np.clip(s, 0, 1), alpha], -1),
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
    split_zone_edges(car, c["zone"] * 2 + c["carbon"])   # and the CARBON border: crisp, not texel steps
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
    corner = (c["lamp"] == 2) & (c["part"] == 0) & (c["obj"] != LAMPS["blade"]) & (fc[:, 0] < 0)
    sc_ = fc[corner]
    o = sc_[np.argsort(sc_[:, 0])[: max(1, len(sc_) // 5)]].mean(0)      # outboard end of the left corner lamp
    wl = [(sx, yc - ctr[1], zc, xo) for sx, yc, zc, xo in wheels]
    port = (C["PORT"][0] - ctr[1], C["PORT"][1]) if C.get("PORT") else (float(o[1]), float(o[2] + zmid))
    areas, extra = [], []
    if BED_TUB:          # the bed's flanks (ContainerAccess.Vault: reached from the side with the tonneau open)
        (by0, by1) = BED_TUB["y"]
        areas.append(("BedSide", (by0 + by1) / 2 - ctr[1], by0 - by1))
    half_len = np.ptp(co[:, 1]) / 2
    for lp_, (lx, ly) in C.get("LIGHTS", {}).items():   # light spots in half extents (IsoGameCharacter.java:17302)
        if ly == "bed":
            ly = ((sum(BED_TUB["y"]) / 2) - ctr[1]) / half_len
        extra += [f"        part {lp_}", "        {", "            table light", "            {",
                  f"                xOffset = {lx:.4f},", f"                yOffset = {ly:.4f},", "            }", "        }"]
    g = pv.geometry(car, zmid, wl, tire[0], tire[1], BELT_Z, tuple(y - ctr[1] for y in DOOR_Y), port, areas, extra)
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


def seals(V, T, sel, attr, glass_bvh, solid=None):
    """Dark strips SEAL[0] behind every open edge of the faces sel (open by position: the zone split doubled the
    vertices there), reaching SEAL[1] past the edge, both sides: the source's panel gaps are real gaps, the ground
    showed through them. Not along a pane (glass_bvh within 1.2 cm of the strip's far edge): the pane closes that
    gap, and the strips lay on the glass as black spikes round the roof rails and A-pillars. solid (SEAL_CLIP: BVH
    of the whole car): not where the strip passes through a surface (it showed on the far side)."""
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
    if solid is not None:
        def through(p, q):
            d = Vector(q - p)
            return solid.ray_cast(Vector(p), d.normalized(), d.length)[0] is not None
        m = (a_ + b_) / 2 - t * 0.001 - fn * 1e-4           # just inside the edge, behind its face
        back = m - fn * SEAL[0]
        keep &= ~np.array([through(*s) for s in zip(m, back)], bool)
        keep &= ~np.array([through(*s) for s in zip(back, back + t * SEAL[1])], bool)
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
    # floor left the front 3 cm deep); depth (rear, front): a floor rising to the nose (something under it there)
    deps = f["depth"] if isinstance(f["depth"], tuple) else (f["depth"],) * 2
    (yr, zr), (yf, zf) = ((rim[i, 1], z_s[i] - dp) for i, dp in zip(np.argmin(np.abs(th[:, None] - [1.5 * math.pi,
                                                                                                    0.5 * math.pi]), 0), deps))
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
          f"{deps[0] / K * 100:.0f}-{deps[1] / K * 100:.0f} cm deep, ~{vol:.0f} L, {len(P)} tris")
    return P.reshape(-1, 3), np.arange(3 * len(P)).reshape(-1, 3), corners(np.array([attr(c) for c in cl]), n)


def quads_soup(quads, cells, faces_in, attr, two_sided=()):
    """Flat quads (N x 4 x 3, pre-centre) as triangles wound to face faces_in (N x 3 directions), cabin palette cells,
    flat normals; the quads indexed in two_sided also get a reversed copy. -> (points, tris, attributes)."""
    Q = np.array(quads, float)
    P = np.concatenate([Q[:, [0, 1, 2]], Q[:, [0, 2, 3]]])
    want = np.concatenate([faces_in, faces_in])
    cl = list(cells) * 2
    n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    flip = (n * want).sum(1) < 0
    P[flip] = P[flip][:, [0, 2, 1]]
    n[flip] *= -1
    two = np.concatenate([np.isin(np.arange(len(Q)), two_sided)] * 2)
    P, n, cl = np.concatenate([P, P[two][:, [0, 2, 1]]]), np.concatenate([n, -n[two]]), cl + [c for c, t in zip(cl, two) if t]
    return P.reshape(-1, 3), np.arange(3 * len(P)).reshape(-1, 3), corners(np.array([attr(c) for c in cl]), n)


def tonneau_strips(dv, attr):
    """A rolling tonneau (the source's cover quad, corners dv) as ROLL_N boxes across its length, front (0) to rear,
    TONNEAU_T thick under its top face, the cover's cabin cell. The engine drops animation scale (AnimationPlayer.java:
    1209-1273 blends position and rotation only; tesla-ctbody-1030a: a scaled cover stood up whole), so the strips
    slide and stack instead, each on its own bone (pieces()). -> (points, tris, attrs, (strip per point, front
    direction, up normal, length)) pre-centre."""
    front = dv[:, 1] > dv[:, 1].mean()
    (FL, FR), (RL, RR) = (s[np.argsort(s[:, 0])][[0, -1]] for s in (dv[front], dv[~front]))
    n = np.cross(FR - FL, RL - FL)
    n /= np.linalg.norm(n) * np.sign(n[2])
    fwd = (FL + FR - RL - RR) / 2
    L = np.linalg.norm(fwd)
    fwd /= L
    side = (FR - FL) / np.linalg.norm(FR - FL)
    Q, out = [], []
    for k in range(ROLL_N):
        f0, f1 = k / ROLL_N, (k + 1) / ROLL_N
        top = [FL + (RL - FL) * f0, FR + (RR - FR) * f0, FR + (RR - FR) * f1, FL + (RL - FL) * f1]
        bot = [p - n * C["TONNEAU_T"] for p in top]
        Q += [top, bot, [top[0], top[1], bot[1], bot[0]], [top[3], top[2], bot[2], bot[3]],
              [top[0], top[3], bot[3], bot[0]], [top[1], top[2], bot[2], bot[1]]]
        out += [n, -n, fwd, -fwd, -side, side]
    P, t, a = quads_soup(Q, ["dash"] * len(Q), np.array(out), attr)
    strip = np.repeat(np.arange(len(Q)) // 6, 3)      # quads_soup: every quad's first triangle, then every second one
    return P, t, a, (np.concatenate([strip, strip]), fwd, n, L)


def bed_tub(V, Tb, attr):
    """A pickup's cargo bed (BED_TUB; the source has none): floor (two-sided: the camera sees under the rear), walls
    up to the rails' inner edge (x and top along y, polylines), wheel humps, the front wall; faces into the bed, the
    lining's cabin palette cell. The tailgate's inner panel closes it at the rear. -> (points, tris, attrs) pre-centre."""
    b = BED_TUB
    (y0, y1), z = b["y"], b["z"]
    xr = lambda y: np.interp(y, *np.array(b["rail_x"]).T)        # noqa: E731  (y ascending)
    top = lambda y: np.interp(y, *np.array(b["top"]).T)         # noqa: E731
    (hy0, hy1), hx, hz = b["hump"]
    ys = np.unique(np.concatenate([np.linspace(y1, y0, 9), [hy0, hy1], np.array(b["top"])[:, 0]]))
    ys = ys[(ys >= y1) & (ys <= y0)]
    Q, cell, inward, two = [], [], [], []

    def quad(p, d, two_sided=False):
        if two_sided:
            two.append(len(Q))
        Q.append(p)
        cell.append(b["cell"])
        inward.append(d)
    for ya, yb in zip(ys[:-1], ys[1:]):
        ym = (ya + yb) / 2
        quad([(-xr(ya), ya, z), (xr(ya), ya, z), (xr(yb), yb, z), (-xr(yb), yb, z)], (0, 0, 1), True)
        for s in (-1, 1):
            hump = hy1 <= ym <= hy0
            zb = hz if hump else z                     # the wall stands on the hump there
            quad([(s * xr(ya), ya, zb), (s * xr(yb), yb, zb), (s * xr(yb), yb, top(yb)), (s * xr(ya), ya, top(ya))],
                 (-s, 0, 0))
            if hump:                                   # the hump: top and inner face
                quad([(s * hx, ya, hz), (s * xr(ya), ya, hz), (s * xr(yb), yb, hz), (s * hx, yb, hz)], (0, 0, 1))
                quad([(s * hx, ya, z), (s * hx, yb, z), (s * hx, yb, hz), (s * hx, ya, hz)], (-s, 0, 0))
    for s in (-1, 1):                                  # the humps' front and rear faces
        for yh, d in ((hy0, -1), (hy1, 1)):
            quad([(s * hx, yh, z), (s * xr(yh), yh, z), (s * xr(yh), yh, hz), (s * hx, yh, hz)], (0, d, 0))
    quad([(-xr(y0), y0, z), (xr(y0), y0, z), (xr(y0), y0, top(y0)), (-xr(y0), y0, top(y0))], (0, -1, 0))   # front wall
    vol = sum((2 * xr((ya + yb) / 2)) * (yb - ya) * (top((ya + yb) / 2) - z) for ya, yb in zip(ys[:-1], ys[1:]))
    print(f"BED y {y1:.3f}..{y0:.3f}, floor z {z:.3f}, {len(Q)} quads, ~{vol / K ** 3 * 1000:.0f} L to the rails")
    return quads_soup(Q, cell, np.array(inward, float), attr, two)


def roof_bar(V, Tb, attr):
    """The off-road light bar on the roof's front edge (ROOF_BAR, every Cybertruck): a box on the roof (ray straight
    down at its centre), housing black, its front face the lens. -> (points, tris, attrs) pre-centre."""
    r = ROOF_BAR
    tree = bvh_of([(V, Tb)])
    hit = tree.ray_cast(Vector((0, r["y"], 5.0)), Vector((0, 0, -1)))[0]
    z0 = hit.z + 0.004
    x, y0, y1, z1 = r["w"] / 2, r["y"] - r["d"] / 2, r["y"] + r["d"] / 2, z0 + r["h"]
    Q = [[(-x, y0, z1), (x, y0, z1), (x, y1, z1), (-x, y1, z1)],               # top
         [(-x, y1, z0), (x, y1, z0), (x, y1, z1), (-x, y1, z1)],               # front: the lens
         [(-x, y0, z0), (x, y0, z0), (x, y0, z1), (-x, y0, z1)],               # back
         [(-x, y0, z0), (-x, y1, z0), (-x, y1, z1), (-x, y0, z1)], [(x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1)]]
    out = np.array([(0, 0, 1), (0, 1, 0), (0, -1, 0), (-1, 0, 0), (1, 0, 0)], float)
    print(f"ROOF_BAR y {r['y']:.3f} on the roof at z {z0:.3f}, {r['w']:.2f} x {r['d']:.3f} x {r['h']:.3f}")
    return quads_soup(Q, ["base", r["lens"], "base", "base", "base"], out, attr)


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
    if C.get("CABIN_REAR_Y") is not None:          # a pickup: the cabin ends at the bed's front wall (the bed is apart)
        trunk_end = C["CABIN_REAR_Y"]
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
    part, glass, mirror = c["part"][tf], c["glass"][tf], c["mirror"][tf]
    panel = (c["paint"] | c["carbon"])[tf]                # body panels, whatever their colour (CARBON's are black)

    def cab_attr(cell):
        return np.array([0, 0, pv.CABIN_UV1_U - CELL[cell], 0, 0, 0, 1], float)
    back_liner = ~glass & ((part == 0) & panel | (part > 0) & ~panel)

    def backs(sel, recolour, base):
        """Reversed copies on their own vertices (the FBX import keeps one of two faces on the same vertices)."""
        n = int(sel.sum())
        a = A[sel][:, [0, 2, 1]].copy()
        a[..., 4:] *= -1
        if recolour:
            a[..., :4] = cab_attr("liner")[:4]
        return V[T[sel][:, [0, 2, 1]]].reshape(-1, 3), base + np.arange(3 * n).reshape(-1, 3), a
    # no reversed glass on Model Y: every source pane is a closed slab (outer and inner face 0.9 mm apart, the rim), so
    # its inner face already shows the glass from inside; a reversed outer face on top put two layers there (darker,
    # and the two crossed where their triangulations differ). A source with one-sided panes (GLASS_BACKS) gets reversed
    # copies of those panes, drawn after the outer ones: else an open door's window and the far side's windows, seen
    # from inside or through the near glass, had no glass (feat/edges-1025 back_glass). Not the windscreen or roof:
    # the camera never sees their inside
    gback = glass & np.isin(c["pane"][tf], [GLASS_ZONES.index(z) for z in GLASS_BACKS])
    back_sets = lambda sel: ((sel & back_liner, True),) + (((sel & gback, False),) if gback.any() else ())  # noqa: E731
    body_t, body_a, bodyV = [T[part == 0]], [A[part == 0]], V
    adds = [backs(sel, rec, 0) for sel, rec in back_sets(part == 0)]
    gb = bvh_of([(V, T[glass])])
    solid = bvh_of([(V, T)]) if SEAL_CLIP else None
    adds += [seals(V, T, (part == 0) & panel, cab_attr("base"), gb, solid)]
    for v, t, a in adds:
        body_t.append(t + len(bodyV))
        bodyV = np.concatenate([bodyV, v])
        body_a.append(a)
    conv = np.array(Matrix.Rotation(-math.pi / 2, 3, "X"))
    meshes, hinges, strips = [], {}, {}
    mat = bpy.data.materials.new(pv.NAME)
    for k, (pname, (sd, axis, ang, secs)) in enumerate(pv.DOORS.items(), 1):
        sel = part == k
        lid = pname == "EngineDoor"
        off = (np.array([-sd, 0, 0]) if sd else np.array((0, 0, -1) if lid else pv.GATE_IN)) * pv.DOOR_T
        skin = sel & panel & ~mirror                     # the mirror cap: outer faces only (a closed shell)
        if ang == "roll":                                # the tonneau: strips of its own (tonneau_strips)
            P, t, a, strips[pname] = tonneau_strips(V[np.unique(T[sel])], cab_attr)
        else:
            P, t, a, _ = pv.slab(V, T, A, skin, off, cab_attr("dash"), BELT_Z - shift[2], outer_extra=sel & ~skin)
            extra = [backs(bsel, rec, 0) for bsel, rec in back_sets(sel)] + [
                seals(V, T, skin, cab_attr("base"), gb, solid)]
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
        elif ang == "roll":                 # the tonneau: its front edge (strip 0, the canister lid; not a hinge)
            mid = dv[np.abs(dv[:, 0]) < 0.08]
            h = np.array([0.0, *mid[np.argmax(mid[:, 1]), 1:]])
        elif GATE_HINGE == "front":         # sedan trunk lid: hinged under the rear window's foot, its front edge
            mid = dv[np.abs(dv[:, 0]) < 0.08]
            h = np.array([0.0, *mid[np.argmax(mid[:, 1]), 1:]])
        elif GATE_HINGE == "bottom":        # pickup tailgate: its lower edge, at the inner panel (level with the bed floor)
            low = dv[np.argmin(dv[:, 2])]
            h = np.array([0.0, low[1] + pv.DOOR_T * pv.GATE_IN[1], low[2]])
        else:                               # hatch: the tailgate's top edge
            h = np.array([0.0, dv[:, 1].max(), dv[:, 2].max()])
        hinges[pname] = h - shift
        meshes.append((pname, P - shift, t, a))
        print(f"DOOR {pname}: {int(sel.sum())} faces, {len(t)} tris, hinge {np.round(h, 3).tolist()}")
    for build, cfg in ((bed_tub, "BED_TUB"), (roof_bar, "ROOF_BAR")):   # a pickup's bed, its roof light bar
        if C.get(cfg):
            Pt, tt, at_ = build(bodyV, np.concatenate(body_t), cab_attr)
            body_t.append(tt + len(bodyV))
            bodyV = np.concatenate([bodyV, Pt])
            body_a.append(at_)
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
    for pname in pv.DOORS:          # bones at the origin, unrotated: bind = identity (models.md 9); a rolling cover's
        for s in range(ROLL_N if pname in strips else 1):    # strips 1.. get <part>_bone<s>
            eb = arm.data.edit_bones.new(pname + "_bone" + (str(s) if s else ""))
            eb.head, eb.tail = Vector((0, 0, 0)), Vector((0, 0.3, 0))
    bpy.ops.object.mode_set(mode="OBJECT")
    obs = [arm]
    for pname, P, t, a in meshes:
        af = a.copy()
        af[..., 4:] = a[..., 4:] @ conv.T
        ob = pv.soup_object(pname, P @ conv.T, t, af, mat)
        if pname in strips:
            for s in range(ROLL_N):
                ob.vertex_groups.new(name=pname + "_bone" + (str(s) if s else "")).add(
                    np.flatnonzero(strips[pname][0] == s).tolist(), 1.0, "REPLACE")
        else:
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

    def roll_pose(pname, s, o):
        """Strip s of a rolling cover, open by o (0..1): the cover slides to the front as one, each strip at most to
        strip 0's place, sinking under the strips ahead of it as it passes under strip 0 (a stack: the canister)."""
        _, fwd, n, L = strips[pname]
        w = L / ROLL_N
        d = o * (ROLL_N - 1) * w
        sink = s * 1.05 * C["TONNEAU_T"] * min(max(d / w - (s - 1), 0.0), 1.0)
        return Vector(conv @ (fwd * min(d, s * w) - n * sink)), Quaternion()
    end = 1
    for pname, (_, _, ang, secs) in pv.DOORS.items():
        act = bpy.data.actions.new(pname + "_closing")
        act.use_fake_user = True
        ad.action = act
        last = 1 + round(secs * pv.CLIP_FPS)
        end = max(end, last)
        for fr in range(1, last + 1):
            u = (fr - 1) / (last - 1)
            o = 1 - u * u * (3 - 2 * u)
            for pb in arm.pose.bones:
                bp, _, s = pb.name.partition("_bone")
                pb.location, pb.rotation_quaternion = (Vector((0, 0, 0)), Quaternion()) if bp != pname else \
                    roll_pose(pname, int(s or 0), o) if ang == "roll" else hinge_pose(pname, ang * o)
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
    want = {pv.NAME if k == "Body" else k: v for k, v in PANES.items()}
    for nm, t, vg, uv, cl, gz in got:
        print("CHECK FBX", nm, "tris", t, "groups", vg, "uv", uv, "glass", sorted(gz))
        groups = 0 if nm == pv.NAME else ROLL_N if nm in strips else 1     # the body: none; a rolling cover: per strip
        if (uv[:2] != ["UV0", "UV1"] or (cl[1:] < cl[:-1]).any() or (vg == 1 if groups == 0 else vg != groups)
                or gz != want[nm]
                or t != counts[nm]):    # the importer drops a triangle on the same vertices as another
            raise SystemExit(f"{nm}: uv {uv}, groups {vg}, classes out of order {(cl[1:] < cl[:-1]).sum()}, glass {gz}, "
                             f"tris {t} of {counts[nm]}")
    if sorted(nm for nm, *_ in got[1:]) != sorted(pv.DOORS):
        raise SystemExit(f"doors FBX meshes {[nm for nm, *_ in got[1:]]}, want {sorted(pv.DOORS)}")
    json.dump({"tris": counts, "total": sum(counts.values()), "classes": cls},
              open(os.path.join(TMP, "tris.json"), "w"), indent=1)
    return counts


# ---------------------------------------------------------------- offline view (game camera, culled, magenta = hole)

APP_SIZE, APP_MARGIN, APP_ELEV = (480, 240), 6, 12   # PhoneApp.lua's car image: px, margin left / right / bottom, deg
APP_GLASS = (32, 36, 43)                            # material sRGB; renders about 29-42 (blue-grey) under APP_LIGHT
APP_LIGHT, APP_EXPOSURE = "paint.sl", 0.5           # Workbench studio light: glossy studio look, brighter than the
#                                                    game view; PearlWhite's 95th percentile stays under 255
APP_DIR = os.path.join(pv.MEDIA, "textures", "MinidoracatTesla", "HUD")


def stage_view(out, heads, state, skin="UltraRed", app=False):
    """Game camera offline view; app=True: the phone App's car image at out (transparent, wheels, dark glass, low
    camera, framed by the projected mesh so every paint gets the same frame)."""
    bpy.ops.wm.open_mainfile(filepath=os.path.join(TMP, "skf_doors.blend"))
    arm = bpy.data.objects["VehicleSkeleton"]
    body = bpy.data.objects[pv.NAME]
    doors = [bpy.data.objects[p] for p in pv.DOORS]
    arm.matrix_world = Matrix.Rotation(math.pi / 2, 4, "X")
    openp = {"all": list(pv.DOORS)[:4], "gate": ["TrunkDoor"], "frunk": ["EngineDoor"], "shut": [],
             "fl": ["DoorFrontLeft"], "fr": ["DoorFrontRight"], "rl": ["DoorRearLeft"], "rr": ["DoorRearRight"],
             "tonneau": ["TrunkTonneau"], "bed": ["TrunkDoor", "TrunkTonneau"]}[state]
    ad = arm.animation_data
    poses = {}
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        bp = pb.name.partition("_bone")[0]
        if bp in openp:
            ad.action = bpy.data.actions[bp + "_closing"]
            bpy.context.scene.frame_set(int(os.environ.get("FRAME", 1)))     # FRAME: a frame of the clip (1 = open)
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
    M = [mat("paint", tex=True), mat("glass", APP_GLASS if app else (40, 230, 230))] + [mat(f"cab{i}", x) for i, x in enumerate(CAB)]
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
    if app or os.environ.get("WHEELS") == "1":
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
    sc.view_settings.exposure = APP_EXPOSURE if app else 0.0
    sh = sc.display.shading
    sh.light = os.environ.get("LIGHT", "STUDIO")
    sh.color_type = "TEXTURE"
    sh.show_backface_culling = True
    sh.background_type = "VIEWPORT"
    sh.background_color = (1, 0, 1)
    sc.render.film_transparent = app
    if app:
        sh.studio_light = APP_LIGHT
        sc.render.image_settings.color_mode = "RGBA"
        sc.display.render_aa = "32"
    sc.render.resolution_x, sc.render.resolution_y = APP_SIZE if app else (int(os.environ.get("RX", 1600)),
                                                                           int(os.environ.get("RY", 1000)))
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
        el = math.radians(APP_ELEV if app else 30)
        d = Vector((cxy @ right * math.cos(el), cxy @ f * math.cos(el), math.sin(el)))
        cam.location = Vector([float(v) for v in os.environ.get("CENTRE", "0,0,0").split(",")]) + d * 30
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = out if app else f"{out}_{h}_{state}.png"
        if app:
            app_frame(cam)
        bpy.ops.render.render(write_still=True)


def app_frame(cam):
    """Ortho scale and camera offset so the visible meshes' projection sits APP_MARGIN px off the left, right and
    bottom edges (or top, if height-limited), centred left-right."""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    inv = np.array(cam.matrix_world.inverted())
    pts = []
    for o in bpy.context.scene.objects:
        if o.type != "MESH" or o.hide_render:
            continue
        me = o.evaluated_get(dg).data
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        m = inv @ np.array(o.matrix_world)
        pts.append(co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3])
    p = np.concatenate(pts)
    lo, hi = p[:, :2].min(0), p[:, :2].max(0)
    (w, h), g = APP_SIZE, APP_MARGIN
    s = min((w - 2 * g) / (hi[0] - lo[0]), (h - 2 * g) / (hi[1] - lo[1]))   # px per unit
    cam.data.ortho_scale = w / s
    cam.location = cam.matrix_world @ Vector(((lo[0] + hi[0]) / 2, lo[1] + (h / 2 - g) / s, 0))


def stage_appcar(outdir=APP_DIR):
    for name, _ in pv.PAINTS:
        stage_view(os.path.join(outdir, C["APP_CAR"].format(name)), ["S"], "shut", name, app=True)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv[0] == "official":
        pv.stage_official()
    elif argv[0] == "build":
        stage_build()
    elif argv[0] == "view":
        stage_view(argv[1], argv[2].split(","), argv[3], *argv[4:])
    elif argv[0] == "appcar":
        stage_appcar(*argv[1:])
    elif argv[0] == "inspect":
        stage_inspect()
