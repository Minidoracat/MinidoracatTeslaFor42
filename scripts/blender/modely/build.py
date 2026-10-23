"""Model Y v2: Tripo H3.1 high-poly GLB -> PZ body FBX (UV0 + UV1), wheel FBX, 8 paint skins / mask / lights / wheel PNGs.

    blender -b --factory-startup --python scripts/blender/modely/build.py -- <stage> [args]

stages (each reads the previous one's .blend in temp/modely/):
  prep            tripo_hi.glb -> axes, scale, body / front-left-wheel sources        -> v2_prep.blend, prev/prep_*.png
  tiers N,N,...   decimated bodies (+ liners, normals from the high-poly, UV0/UV1)     -> v2_tiers.blend, tiers/*.fbx
  wheel           wheel from the high-poly (outer half mirrored), UV, 512 bake          -> MOD wheel FBX + PNG
  official        official design-studio renders of the 8 paints                       -> temp/modely/official/
  final N         bake N-tri body at 4096 (cached in bake_N.npz), one 2048 skin per paint (colour from the official
                  render), 512 mask / lights, body FBX, geometry block spliced into the vehicle script (copy in
                  temp/modely/geometry_block.txt), verify.txt, prev/*.png

Axes (Blender): +Y front, +Z up, -X = car left (driver side), 1 unit = 1 grid; same as vanilla raw FBX coords
(scripts/blender/modely/vanilla.py). Vehicle script: x = -mesh x, y = mesh z, z = mesh y, unscaled = grid / 1.82.
Numbers and sources: .claude/skills/tesla-dev/references/models.md.
"""
import bpy, bmesh, colorsys, json, math, os, sys
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
import preview  # noqa: E402

TMP = os.path.join(REPO, "temp", "modely")
PREV = os.path.join(TMP, "prev")
MEDIA = os.path.join(REPO, "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media")
VEH_DIR = os.path.join(MEDIA, "models_X", "vehicles")
TEX_DIR = os.path.join(MEDIA, "textures", "Vehicles")
SRC = os.path.join(TMP, "tripo_hi.glb")
NAME = "MinidoracatTesla_ModelY"

K = 0.826                                   # grid per metre (R5 3), calibration knob
L, W, H = 4.790 * K, 1.920 * K, 1.624 * K   # official length, body width (no mirrors), height
DIM_TOL = 0.02                              # allowed error vs official x K (Main 2026-10-23); only that much squash
TIRE_W = 0.255 * K                          # 255/45R19
RIM = 0.68                                  # rim / tire radius (19" rim 241.3 mm / 356 mm)
BAKE = 4096
LINER_SEG = 16
MIN_ISLAND = 1 / 150                        # UV0 projection islands under this share of the faces are merged
UV1_SCALE = 0.56                            # shared Veh_* 512 maps at ~vanilla density (R5: UV1 56-60 px/grid)
WHEEL_TRIS, WHEEL_TEX = 1400, 512
# Model Y body lines (grid, ground z=0, centre y=0), checked on prev/mask_*.png against the panel gaps of the bake
DOOR_FRONT_Y, B_PILLAR_Y, DOOR_REAR_Y, BELT_Z = 0.83, -0.14, -1.05, 0.92
# official Model Y paints (decisions.md "車款外觀"): skin order = vehicle script skin index = Core.lua colors order;
# saved games store the index (BaseVehicle.java:2635/2741), so after release only append
PAINTS = [("StealthGrey", "PN01"), ("PearlWhite", "PPSW"), ("DiamondBlack", "PX02"), ("Quicksilver", "PN00"),
          ("UltraRed", "PR01"), ("GlacierBlue", "PB01"), ("MarineBlue", "PB02"), ("FrostBlue", "PB00")]
SKIN = 2048                                 # option 4 cap; the default option 2 shrinks it to 512 on load
GAIN = 0.88                                 # in-game day screen / texture sRGB (E2E tesla-modely-skin-1024c/d: red
#                                             0.80-0.86, white 0.90-0.97), calibration knob
# per-paint, per-channel sRGB tone fix of the paint texels, tex' = a * tex + b: in-game screenshots of the car heading
# S (E2E tesla-modely-1024e option 2, tesla-modely-skin-1024e4 option 4, closest zoom) against the official FRONT34
# render of the same paint (same three-quarter angle; paint pixels = the ones that change between colours): slope
# a = official / game p25-p75 spread (clamped 0.6-1.6), offset b puts the game p50 on the official p50 (/ GAIN).
# Before: Quicksilver, Glacier Blue 35% too light, Diamond Black and Marine Blue crushed (p50 12 vs 30, R 9 vs 26).
# Ultra Red G keeps slope 1 (fit 1.6 is the clamp: its p25-p75 spread is ~3 levels, the slope lit the A-pillar orange)
# Calibration knob: re-measure after changing the paint mapping (.claude/skills/tesla-e2e/perf/paint_sheet.py)
CAL = {
    "StealthGrey": ((0.77, 0.76, 0.76), (0.054, 0.049, 0.049)), "PearlWhite": ((0.92, 0.96, 0.93), (0.034, -0.005, 0.018)),
    "DiamondBlack": ((0.93, 0.93, 0.87), (0.082, 0.080, 0.079)), "Quicksilver": ((0.81, 0.81, 0.84), (-0.041, -0.049, -0.069)),
    "UltraRed": ((0.84, 1.0, 0.79), (0.030, 0.058, 0.069)), "GlacierBlue": ((0.66, 0.71, 0.77), (0.048, 0.025, -0.003)),
    "MarineBlue": ((0.98, 0.72, 0.73), (0.076, 0.079, 0.061)), "FrostBlue": ((0.71, 0.73, 0.74), (0.096, 0.108, 0.134)),
}
OFFICIAL = os.path.join(TMP, "official")
COMPOSITOR = ("https://static-assets.tesla.cn/configurator/compositor?context=design_studio_2&options={}&view={}"
              "&model=my&size=1920&bkba_opt=1&crop=0,0,0,0&overlay=0&")

Z = {  # mask zone colours (media/shaders/vehicle_common.frag.h colZone*)
    "Head": (1, 0, 0), "Tail": (0, 1, 0), "DoorRH": (0, 1, 1), "DoorRT": (1, 1, 0), "DoorLH": (1, 0, 1), "DoorLT": (0, 0, 1),
    "WinRH": (0, .5, .5), "WinRT": (.5, .5, 0), "WinLH": (.5, 0, .5), "WinLT": (0, 0, .5), "WinT": (.5, 0, 0), "WinH": (0, .5, 0),
    "GuardRH": (0, .75, .75), "GuardRT": (.75, .75, 0), "GuardLH": (.75, 0, .75), "GuardLT": (0, 0, .75), "Roof": (0, 0, 0),
    "LightRH": (.25, 0, 0), "LightLH": (.75, 0, 0), "LightRT": (0, .75, 0), "LightLT": (0, .25, 0),
    "StopR": (.5, .25, 0), "StopL": (.5, .75, 0), "Hood": (1, 0, .5), "Boot": (0, 1, .5),
}


# ---------------------------------------------------------------- helpers

def mesh_co(ob):
    a = np.empty(len(ob.data.vertices) * 3)
    ob.data.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def set_co(ob, co):
    ob.data.vertices.foreach_set("co", np.ascontiguousarray(co).ravel())
    ob.data.update()


def face_centres(ob):
    a = np.empty(len(ob.data.polygons) * 3)
    ob.data.polygons.foreach_get("center", a)
    return a.reshape(-1, 3)


def select_only(*obs):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in obs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = obs[-1]


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def dup(ob, name):
    d = ob.copy()
    d.data = ob.data.copy()
    d.name = name
    bpy.context.scene.collection.objects.link(d)
    return d


def keep_faces(ob, mask):
    """Delete the faces where mask is False (numpy bool per polygon)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f, k in zip(bm.faces, mask) if not k], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()


def decimate(ob, target):
    select_only(ob)
    for _ in range(3):                      # ratio is on triangles; repeat until within 3 %
        n = tris(ob)
        if n <= target * 1.03:
            break
        m = ob.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = target / n
        m.use_symmetry, m.symmetry_axis = True, "X"
        bpy.ops.object.modifier_apply(modifier=m.name)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def img_np(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)


def save_png(arr, path, name):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(arr, dtype=np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def to_srgb(lin):
    lin = np.clip(lin, 0, 1)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)


def box_blur(a, r):
    """Separable box blur (radius r px) of a 2-D array, edges clamped."""
    for ax in (0, 1):
        p = np.pad(a, [(r + 1, r) if i == ax else (0, 0) for i in range(2)], mode="edge")
        c = np.cumsum(p, axis=ax)
        a = (np.take(c, np.arange(2 * r + 1, c.shape[ax]), axis=ax) - np.take(c, np.arange(0, c.shape[ax] - 2 * r - 1), axis=ax)) / (2 * r + 1)
    return a


def grow(m, n=2):
    for _ in range(n):
        g = m.copy()
        g[1:] |= m[:-1]
        g[:-1] |= m[1:]
        g[:, 1:] |= m[:, :-1]
        g[:, :-1] |= m[:, 1:]
        m = g
    return m


def downsample(a, f):
    h, w = a.shape[:2]
    return a.reshape(h // f, f, w // f, f, *a.shape[2:]).mean((1, 3))


def emission_from_base(ob):
    """Cycles DIFFUSE colour = base x (1 - metallic) and Tripo paint is metallic: bake base colour as emission."""
    for m in ob.data.materials:
        nt = m.node_tree
        b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        nt.links.new(b.inputs["Base Color"].links[0].from_socket, b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 1.0


def bake_maps(target, source, size, maps, margin=16):
    """maps: list of (name, kind) with kind in pos / nrm / col / ao. Returns {name: HxWx4 float array}."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.bake.margin = margin
    sc.render.bake.margin_type = "EXTEND"
    if sc.world is None:                    # AO ray distance is a world setting
        sc.world = bpy.data.worlds.new("bake")
    sc.world.light_settings.distance = 0.4
    for o in bpy.data.objects:              # other tiers overlap the surface and would occlude every AO ray
        o.hide_render = o not in (target, source)
    mat = bpy.data.materials.new("bake_" + target.name)
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    mat.node_tree.nodes.active = node
    target.data.materials.clear()
    target.data.materials.append(mat)
    for attr in ("visible_camera", "visible_diffuse", "visible_glossy", "visible_transmission", "visible_shadow"):
        setattr(target, attr, False)        # AO rays must only see the high-poly
    out = {}
    for name, kind in maps:
        img = bpy.data.images.new("bake_" + name, size, size, alpha=True, float_buffer=True)
        node.image = img
        if kind == "pos":
            select_only(target); sc.cycles.samples = 1
            bpy.ops.object.bake(type="POSITION", use_clear=True)
        elif kind == "nrm":
            select_only(target); sc.cycles.samples = 1
            bpy.ops.object.bake(type="NORMAL", normal_space="OBJECT", use_clear=True)
        else:
            select_only(source, target)
            sc.cycles.samples = 1 if kind == "col" else 24
            bpy.ops.object.bake(type="EMIT" if kind == "col" else "AO", use_selected_to_active=True, use_clear=True,
                                cage_extrusion=0.03, max_ray_distance=0.12)
        out[name] = img_np(img)
        bpy.data.images.remove(img)
    return out


def export_fbx(ob, path):
    select_only(ob)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", bake_space_transform=True,
                             axis_forward="-Z", axis_up="Y", mesh_smooth_type="OFF",
                             add_leaf_bones=False, bake_anim=False, path_mode="STRIP")


# ---------------------------------------------------------------- prep

def stage_prep():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    hi = [o for o in bpy.data.objects if o.type == "MESH"][0]
    hi.name = "hi"
    # Tripo glTF: front -Y, left +X  ->  rotate 180 deg about Z (front +Y, left -X)
    hi.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ hi.matrix_world
    select_only(hi)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new()                                # glTF splits vertices at every UV / normal seam: weld them so the
    bm.from_mesh(hi.data)                           # surface is connected (decimation and UV islands need that)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(hi.data)
    bm.free()
    co = mesh_co(hi)
    co -= [(co[:, 0].min() + co[:, 0].max()) / 2, (co[:, 1].min() + co[:, 1].max()) / 2, co[:, 2].min()]
    h = co[:, 2].max()
    w = 2 * np.abs(co[co[:, 2] < 0.55 * h][:, 0]).max()          # below the mirrors
    s = L / np.ptp(co[:, 1])                                      # length is exact
    fac = []
    for cur, tgt in ((w * s, W), (h * s, H)):                    # squash only down to the +2 % limit
        r = cur / tgt
        fac.append((1 + DIM_TOL) / r if r > 1 + DIM_TOL else (1 - DIM_TOL) / r if r < 1 - DIM_TOL else 1.0)
    scale = np.array([s * fac[0], s, s * fac[1]])
    co = co * scale
    set_co(hi, co)
    info = {"uniform_scale": s, "x_factor": fac[0], "z_factor": fac[1],
            "uniform_size": [w * s, L, h * s], "final_size": [w * s * fac[0], L, h * s * fac[1]], "official": [W, L, H]}
    # wheels: contact patches (z < 0.02) front / rear; tire outer x; axle height from the cut wheel
    low = co[co[:, 2] < 0.02]
    wheels = []
    for fy in (1, -1):
        yc = float(np.median(low[low[:, 1] * fy > 0][:, 1]))
        near = co[(np.abs(co[:, 1] - yc) < 0.12) & (co[:, 2] < 0.25)]
        wheels.append((yc, float(np.abs(near[:, 0]).max())))
    r0 = 0.356 * K * scale[2] / s                                  # spec radius, squashed like the mesh
    fc = face_centres(hi)
    wl = [(sx, yc, xo) for (yc, xo) in wheels for sx in (-1, 1)]

    def in_wheel(c, sx, yc, xo, pad):
        return (c[:, 0] * sx > xo - TIRE_W - 0.09) & ((c[:, 1] - yc) ** 2 + ((c[:, 2] - r0) * s / scale[2]) ** 2 < (0.356 * K + pad) ** 2)
    wheel_any = np.zeros(len(fc), bool)
    for sx, yc, xo in wl:
        wheel_any |= in_wheel(fc, sx, yc, xo, 0.02)
    fl = in_wheel(fc, -1, wheels[0][0], wheels[0][1], 0.02)
    body = dup(hi, "hi_body")
    keep_faces(body, ~wheel_any)
    wheel = dup(hi, "hi_wheel")
    keep_faces(wheel, fl)
    wc = mesh_co(wheel)
    band = wc[wc[:, 0] < wc[:, 0].min() + 0.025]                  # outermost sidewall bulge = tire silhouette
    info["wheels"] = wheels
    info["wheel_cut"] = {"x": [float(wc[:, 0].min()), float(wc[:, 0].max())], "y": [float(band[:, 1].min()), float(band[:, 1].max())],
                         "z": [float(band[:, 2].min()), float(band[:, 2].max())]}
    bpy.data.objects.remove(hi)
    bpy.context.scene["info"] = json.dumps(info)
    print("PREP", json.dumps(info))
    os.makedirs(PREV, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TMP, "v2_prep.blend"))
    preview.render_views(os.path.join(PREV, "prep"), ortho=4.4, center=Vector((0, 0, H / 2)), res=(2048, 1024),
                         views={"left": Vector((-1, 0, 0)), "iso": Vector((-1, 1, 1.15))})


# ---------------------------------------------------------------- body

def add_liners(bm, wl, r):
    """Dark wheel-well liner per wheel: arc shell over the tire + inner wall (faces tagged liner=1)."""
    lay = bm.faces.layers.int["liner"]
    new = []
    rl = r + 0.05
    a0, a1 = math.radians(-15), math.radians(195)
    for sx, yc, zc, xo in wl:
        xi, xe = sx * (xo - TIRE_W - 0.06), sx * (xo - 0.01)
        ai, ae = [], []
        for i in range(LINER_SEG + 1):
            a = a0 + (a1 - a0) * i / LINER_SEG
            y, z = yc + rl * math.cos(a), zc + rl * math.sin(a)
            ai.append(bm.verts.new((xi, y, z)))
            ae.append(bm.verts.new((xe, y, z)))
        hub = bm.verts.new((xi, yc, zc))
        for i in range(LINER_SEG):
            f = bm.faces.new([ai[i], ai[i + 1], ae[i + 1], ae[i]])
            f.normal_update()
            c = f.calc_center_median()
            if f.normal.dot(Vector((c.x, yc, zc)) - c) < 0:
                f.normal_flip()
            g = bm.faces.new([hub, ai[i], ai[i + 1]])
            g.normal_update()
            if g.normal.x * sx < 0:
                g.normal_flip()
            new += [f, g]
    for f in new:
        f[lay] = 1
    bmesh.ops.triangulate(bm, faces=new)


def project_uv(me):
    """UV0 by planar projection per dominant normal axis (left, right, top, bottom, front, back), merged into a few
    large islands like vanilla (ModernCar UV0 50 islands, SUV 39; v1 Smart UV had 587 and bled at every edge)."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()

    def axis(n):
        a = (abs(n.x), abs(n.y), abs(n.z))
        if a[2] >= max(a[0], a[1]) * 0.9:
            return "T" if n.z > 0 else "D"
        if a[0] >= a[1]:
            return "L" if n.x < 0 else "R"
        return "F" if n.y > 0 else "B"
    cls = [axis(f.normal) for f in bm.faces]
    for _ in range(4):
        new = cls[:]
        for f in bm.faces:
            nb = [cls[g.index] for e in f.edges for g in e.link_faces if g is not f]
            if nb:
                best = max(set(nb), key=nb.count)
                if nb.count(best) >= 2:
                    new[f.index] = best
        cls = new
    liner = bm.faces.layers.int.get("liner")
    for f in bm.faces:
        if f[liner]:
            cls[f.index] = "L" if f.calc_center_median().x < 0 else "R"

    def components():
        seen, out = set(), []
        for f in bm.faces:
            if f.index in seen:
                continue
            c, stack, part = cls[f.index], [f], []
            seen.add(f.index)
            while stack:
                g = stack.pop()
                part.append(g.index)
                for e in g.edges:
                    for h2 in e.link_faces:
                        if h2.index not in seen and cls[h2.index] == c:
                            seen.add(h2.index)
                            stack.append(h2)
            out.append((c, part))
        return out
    for _ in range(10):
        changed = False
        for c, part in components():
            if len(part) >= max(24, len(bm.faces) * MIN_ISLAND):
                continue
            nb = [cls[h2.index] for i in part for e in bm.faces[i].edges for h2 in e.link_faces if cls[h2.index] != c]
            if nb:
                best = max(set(nb), key=nb.count)
                for i in part:
                    cls[i] = best
                changed = True
        if not changed:
            break
    uv = bm.loops.layers.uv.new("UV0")
    proj = {"L": lambda p: (-p.y, p.z), "R": lambda p: (p.y, p.z), "T": lambda p: (p.x, p.y), "D": lambda p: (p.x, -p.y),
            "F": lambda p: (p.x, p.z), "B": lambda p: (-p.x, p.z)}       # every projection seen from outside
    for f in bm.faces:
        pr = proj[cls[f.index]]
        k = 0.25 if cls[f.index] == "D" else 1.0   # underside: never seen from the iso camera, quarter texel density
        for lp in f.loops:
            lp[uv].uv = [k * t for t in pr(lp.vert.co)]
    n = len(components())
    bm.to_mesh(me)
    bm.free()
    return n


def unwrap(ob):
    me = ob.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    n = project_uv(me)
    me.uv_layers.active = me.uv_layers["UV0"]
    select_only(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(margin=0.006, rotate=True, shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")
    uv1 = me.uv_layers.new(name="UV1")
    uv0 = me.uv_layers["UV0"]
    a = np.empty(len(me.loops) * 2)
    uv0.data.foreach_get("uv", a)
    uv1.data.foreach_set("uv", a * UV1_SCALE)
    me.uv_layers.active = uv0
    uv0.active_render = True
    return n


def transfer_normals(low, hi):
    """Vertex (loop) normals from the high-poly surface: PZ has no normal map, shading comes from these."""
    vg = low.vertex_groups.new(name="body")
    liner = np.array([d.value for d in low.data.attributes["liner"].data], bool)
    verts = sorted({i for k, p in enumerate(low.data.polygons) if not liner[k] for i in p.vertices})
    vg.add(verts, 1.0, "REPLACE")
    select_only(low)
    m = low.modifiers.new("nt", "DATA_TRANSFER")
    m.object = hi
    m.use_loop_data = True
    m.data_types_loops = {"CUSTOM_NORMAL"}
    m.loop_mapping = "POLYINTERP_NEAREST"
    m.vertex_group = "body"
    bpy.ops.object.modifier_apply(modifier=m.name)


def stage_tiers(targets):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(TMP, "v2_prep.blend"))
    info = json.loads(bpy.context.scene["info"])
    hi = bpy.data.objects["hi_body"]
    cut = info["wheel_cut"]
    r = (cut["y"][1] - cut["y"][0]) / 2
    zc = info["wheel_axle_z"] = (cut["z"][0] + cut["z"][1]) / 2
    wl = [(sx, yc, zc, xo) for (yc, xo) in info["wheels"] for sx in (-1, 1)]
    os.makedirs(os.path.join(TMP, "tiers"), exist_ok=True)
    src = hi
    for n in sorted(targets, reverse=True):                          # each tier decimates the previous one
        low = dup(src, f"body_{n}")
        decimate(low, n)
        nb = tris(low)
        bm = bmesh.new()
        bm.from_mesh(low.data)
        bm.faces.layers.int.new("liner")
        add_liners(bm, wl, r)
        bm.to_mesh(low.data)
        bm.free()
        transfer_normals(low, hi)
        islands = unwrap(low)
        print(f"TIER {n}: body {nb} + liner {tris(low) - nb} tris, UV0 islands {islands}")
        export_fbx(low, os.path.join(TMP, "tiers", f"{NAME}_{n}.fbx"))
        src = low
    bpy.context.scene["info"] = json.dumps(info | {"wheel_r": r, "wl": wl})
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TMP, "v2_tiers.blend"))


# ---------------------------------------------------------------- wheel

def stage_wheel():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(TMP, "v2_tiers.blend"))
    info = json.loads(bpy.context.scene["info"])
    for o in [o for o in bpy.data.objects if o.name.startswith((NAME + "_Wheel", "wheel_outer", "wheel_src"))]:
        bpy.data.objects.remove(o)                       # re-runnable: the tiers blend keeps the last wheel
    src = dup(bpy.data.objects["hi_wheel"], "wheel_src")
    cut = info["wheel_cut"]
    yc = (cut["y"][0] + cut["y"][1]) / 2
    zc = info["wheel_axle_z"]
    r = info["wheel_r"]
    xo = cut["x"][0]                                     # left wheel: outer face at min x
    xm = xo + TIRE_W / 2
    # centre on the axle, make it round (undo the body z squash), outer half only
    co = mesh_co(src) - [xm, yc, zc]
    co[:, 2] *= r / ((cut["z"][1] - cut["z"][0]) / 2)
    set_co(src, co)
    keep_faces(src, face_centres(src)[:, 0] <= 0.002)
    low = dup(src, NAME + "_Wheel")
    while low.data.uv_layers:                            # PZ reads the first UV layer: drop Tripo's
        low.data.uv_layers.remove(low.data.uv_layers[0])
    decimate(low, WHEEL_TRIS // 2)
    bm = bmesh.new()
    bm.from_mesh(low.data)
    for v in bm.verts:                                   # snap the cut plane so the mirror welds
        if v.co.x > -0.004:
            v.co.x = 0.0
    bmesh.ops.mirror(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], axis="X", merge_dist=0.003)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    uv = bm.loops.layers.uv.new("UV0")
    for f in bm.faces:                                   # planar Y/Z: both faces share the rim image, tread -> rubber ring
        for lp in f.loops:
            lp[uv].uv = (0.5 - lp.vert.co.y / (2 * r), 0.5 + lp.vert.co.z / (2 * r))
    bm.to_mesh(low.data)
    bm.free()
    low.data.shade_smooth()
    low.data.set_sharp_from_angle(angle=math.radians(50))
    outer = dup(low, "wheel_outer")                      # bake only the half that faces the source
    keep_faces(outer, face_centres(outer)[:, 0] <= 0.0)
    emission_from_base(src)
    b = bake_maps(outer, src, WHEEL_TEX, [("col", "col")], margin=8)
    col = to_srgb(b["col"][..., :3])
    yy, xx = (np.mgrid[0:WHEEL_TEX, 0:WHEEL_TEX] + 0.5) / WHEEL_TEX * 2 - 1
    rr = np.hypot(xx, yy)
    rubber = rr > RIM
    shade = (0.05 + 0.03 * np.clip((1 - rr) / (1 - RIM), 0, 1))[..., None]
    col[rubber] = shade[rubber] * np.array([1, 1, 1.04])
    wheel_tex = np.concatenate([col, np.ones(col.shape[:2] + (1,))], -1)
    save_png(wheel_tex, os.path.join(TEX_DIR, NAME + "_wheel.png"), "wheel")
    mat = bpy.data.materials.new(NAME + "_Wheel")
    low.data.materials.clear()
    low.data.materials.append(mat)
    export_fbx(low, os.path.join(VEH_DIR, NAME + "_Wheel.fbx"))
    print("WHEEL tris", tris(low), "radius", r, "width", TIRE_W)
    bpy.context.scene["info"] = json.dumps(info | {"wheel_tris": tris(low)})
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TMP, "v2_tiers.blend"))


# ---------------------------------------------------------------- final

def raster_liner(ob, size):
    me = ob.data
    att = me.attributes["liner"].data
    uv = me.uv_layers["UV0"].data
    m = np.zeros((size, size), bool)
    for p in me.polygons:
        if att[p.index].value:
            t = np.array([uv[li].uv[:] for li in p.loop_indices]) * size
            x0, y0 = np.floor(t.min(0)).astype(int) - 6
            x1, y1 = np.ceil(t.max(0)).astype(int) + 6
            m[max(y0, 0):min(y1, size), max(x0, 0):min(x1, size)] = True
    return m


def hsv(rgb):
    mx, mn = rgb.max(-1), rgb.min(-1)
    return mx, np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0)


FILL_RES = 150   # px per grid of the ortho rasters for the glass fill (~30 texels of the 4096 bake per pixel)


def enclosed(u, v, sel, dark):
    """Texels of sel whose ortho pixel (u, v) is mostly dark or cut off from the raster border by dark pixels."""
    if not sel.any():
        return np.zeros(u.shape, bool)
    uu = ((u[sel] - u[sel].min()) * FILL_RES).astype(np.int64) + 1
    vv = ((v[sel] - v[sel].min()) * FILL_RES).astype(np.int64) + 1
    W, H = int(uu.max()) + 2, int(vv.max()) + 2
    k = vv * W + uu
    wall = (np.bincount(k, dark[sel], W * H) > 0.5 * np.bincount(k, None, W * H)).reshape(H, W)
    out = np.zeros((H, W), bool)
    out[0] = out[-1] = True
    out[:, 0] = out[:, -1] = True
    while True:                                                    # flood fill from the border around the walls
        g = grow(out, 1) & ~wall
        if (g == out).all():
            break
        out = g
    res = np.zeros(u.shape, bool)
    res[sel] = ~out.reshape(-1)[k]
    return res


def classify(pos, nrm, col, liner):
    covered = np.abs(np.linalg.norm(nrm, axis=-1) - 1) < 0.2     # unbaked texels decode to (-1,-1,-1)
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    nx, ny, nz = nrm[..., 0], nrm[..., 1], nrm[..., 2]
    v, s = hsv(col)
    left = x < 0
    side = np.abs(nx) > 0.45
    zone = np.full(x.shape, "Roof", dtype=object)

    def put(cond, l, r):
        cond = cond & covered
        zone[cond & left] = l
        zone[cond & ~left] = r
    put((y > DOOR_FRONT_Y) & (z < BELT_Z + 0.05), "GuardLH", "GuardRH")
    put((y < DOOR_REAR_Y) & (z < BELT_Z + 0.05), "GuardLT", "GuardRT")
    put(side & (y <= DOOR_FRONT_Y) & (y > B_PILLAR_Y) & (z < BELT_Z + 0.1), "DoorLH", "DoorRH")
    put(side & (y <= B_PILLAR_Y) & (y >= DOOR_REAR_Y) & (z < BELT_Z + 0.1), "DoorLT", "DoorRT")
    put((y > 0.75) & (z > 0.58) & (z < BELT_Z + 0.02) & (nz > 0.35), "Hood", "Hood")
    put((y > 1.5) & (z <= 0.62) & ((ny > 0.3) | (y > 1.85)), "Head", "Head")
    put((y < -1.45) & (z > 0.55) & ((ny < -0.2) | (nz > 0.3)), "Boot", "Boot")
    put((y < -1.45) & (z <= 0.55) & ((ny < -0.3) | (y < -1.85)), "Tail", "Tail")
    # glass: dark (V < 0.215); on the roof Tripo's glass carries sky reflections (V p95 0.40) while the body-colour
    # roof rails read V 0.43-0.64, so up there the test runs on blurred V < 0.4. Tripo also shows the cabin through the
    # windscreen (dashboard: the light block at its foot read as paint): whatever the dark glass encloses in the top,
    # front and back ortho views (by dominant normal) is glass too. Not the side views: the mirrors project into the
    # side windows there
    up = covered & (z > BELT_Z - 0.04) & ~liner
    dark = up & np.where((nz > 0.3) & (z > BELT_Z + 0.12), box_blur(v, 10) < 0.4, v < 0.215)
    ax = np.argmax(np.abs(nrm), -1)
    glass = dark.copy()
    for sel, iu, iv in ((up & (ax == 2) & (nz > 0), 1, 0), (up & (ax == 1) & (ny > 0), 0, 2), (up & (ax == 1) & (ny < 0), 0, 2)):
        glass |= enclosed(pos[..., iu], pos[..., iv], sel, dark)
    glass = (box_blur(glass.astype(np.float32), 10) > 0.5) & covered & ~liner     # majority: no ragged rail edge
    put(glass & side & (y > B_PILLAR_Y), "WinLH", "WinRH")
    put(glass & side & (y <= B_PILLAR_Y), "WinLT", "WinRT")
    put(glass & ~side & (ny > 0.3) & (y > 0.3), "WinT", "WinT")
    put(glass & ~side & (ny < -0.3) & (y < -1.0), "WinH", "WinH")
    put(glass & ~side & (np.abs(ny) <= 0.3), "Roof", "Roof")
    head = grow(covered & (v > 0.75) & (y > 1.6) & (z > 0.6) & (z < 0.74), 3) & covered & (y > 1.55)
    red = grow(covered & (col[..., 0] > 0.3) & (col[..., 0] > 1.8 * col[..., 1]) & (y < -1.4) & (z > 0.78) & (z < 0.94), 3) \
        & covered & (y < -1.35)
    put(head, "LightLH", "LightRH")
    put(red & (np.abs(x) <= 0.5), "LightLT", "LightRT")
    put(red & (np.abs(x) > 0.5), "StopL", "StopR")
    zone[liner] = "Roof"
    return zone, glass, head | red, covered


def stage_final(n):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(TMP, "v2_tiers.blend"))
    info = json.loads(bpy.context.scene["info"])
    hi = bpy.data.objects["hi_body"]
    body = bpy.data.objects[f"body_{n}"]
    body.name = NAME
    cache = os.path.join(TMP, f"bake_{n}.npz")      # the 4096 Cycles bake takes minutes; texture passes reuse it
    if os.path.exists(cache):
        c = np.load(cache)
        pos, nrm, col, ao = (c[k].astype(np.float32) for k in ("pos", "nrm", "col", "ao"))
        liner = c["liner"]
    else:
        emission_from_base(hi)
        b = bake_maps(body, hi, BAKE, [("pos", "pos"), ("nrm", "nrm"), ("col", "col")])
        ao = bake_maps(body, hi, BAKE // 2, [("ao", "ao")])["ao"][..., 0]
        ao = np.repeat(np.repeat(ao, 2, 0), 2, 1)
        liner = raster_liner(body, BAKE)
        col = to_srgb(b["col"][..., :3])
        pos, nrm = b["pos"][..., :3], b["nrm"][..., :3] * 2 - 1
        np.savez(cache, pos=pos.astype(np.float16), nrm=nrm.astype(np.float16), col=col.astype(np.float16),
                 ao=ao.astype(np.float16), liner=liner)
    zone, glass, lights, covered = classify(pos, nrm, col, liner)
    v, s = hsv(col)
    # paint = body grey; decided on blurred V so Tripo's dark reflection patches on the hood stay paint, while the
    # black plastics (rocker, diffuser, grille: V 0.10-0.16) do not (door V p5 0.29, hood p5 0.16). The blur skips
    # glass texels (else the mirror caps and pillars by the dark glass turned trim). No upper V cap: Tripo's highlights
    # by the headlight strip are paint. 7x7 majority: no ragged teeth on the glass / trim edges
    ng = (covered & ~glass).astype(np.float32)
    vb = box_blur(v * ng, 24) / np.maximum(box_blur(ng, 24), 1e-3)
    # the rear-facing lip under the windscreen (y 1.07-1.15, z ~0.92) is the hidden cowl: black, not paint (as paint
    # it showed Tripo's stretched streaks in the rear three-quarter view)
    cowl = (nrm[..., 1] < -0.3) & (pos[..., 1] > 0.5) & (np.abs(pos[..., 0]) < 0.62) & (pos[..., 2] > 0.85) & (pos[..., 2] < 1.0)
    free = covered & ~glass & ~lights & ~liner & ~cowl
    paint = free & (vb > 0.19) & (s < 0.3)
    paint = (box_blur(paint.astype(np.float32), 3) > 0.5) & free
    base = np.concatenate([col, np.ones(col.shape[:2] + (1,))], -1).astype(np.float32)
    # glass: Tripo painted sky reflections into it; keep its tint, flatten, cap V, darken by AO
    gv = np.maximum(v, 1e-6)
    gtarget = np.clip(box_blur(v, 24), 0.05, 0.16) * (0.6 + 0.4 * ao)
    base[glass, :3] = (col * (gtarget / gv)[..., None])[glass]
    def darken(m, cap):                                                 # Tripo tint, V capped, AO shaded
        base[m, :3] = (col * np.minimum(1, cap / gv)[..., None] * (0.55 + 0.45 * ao[..., None]))[m]
    darken(free & ~paint, 0.3)                                          # trim
    darken(cowl & covered & ~glass & ~liner, 0.12)
    # the light zones are grown 3 px around the bright / red cores: that ring is the dark lamp housing, not Tripo's
    # grey body speckle
    darken(lights & (v < 0.6) & ~((col[..., 0] > 0.3) & (col[..., 0] > 1.8 * col[..., 1])), 0.12)
    base[liner, :3] = 0.03
    mask = np.zeros(zone.shape + (4,), np.float32)
    mask[..., 3] = 1
    for k, c in Z.items():
        mask[zone == k, :3] = np.round(np.array(c) * 255) / 255
    lit = np.zeros(zone.shape + (4,), np.float32)
    for k, c in (("LightLH", (1, 1, .95)), ("LightRH", (1, 1, .95)), ("LightLT", (1, .12, .08)), ("LightRT", (1, .12, .08)),
                 ("StopL", (1, 0, 0)), ("StopR", (1, 0, 0))):
        lit[zone == k] = c + (1,)
    os.makedirs(TEX_DIR, exist_ok=True)
    # one full-colour skin per official paint, alpha 255 everywhere, so the engine's shrink to the player's "vehicle
    # texture size" cap (premultiplied alpha, TextureID.java:348-375, ImageData.java:291-297,468-482) keeps the colour.
    # Paint texels keep the high-poly light: rank of Tripo V x AO over all paint texels -> colour at that V quantile of
    # the official render's paint (official_ramp), divided by the in-game day gain
    key = v[paint] * (0.5 + 0.5 * ao[paint])
    q = np.empty(key.size)
    q[np.argsort(key, kind="stable")] = (np.arange(key.size) + 0.5) / key.size
    hsvs = {}
    for pname, code in PAINTS:
        ramp = official_ramp(code)
        xp = (np.arange(len(ramp)) + 0.5) / len(ramp)
        a, b = (np.array(t, np.float32) for t in CAL[pname])
        tone = lambda c: np.clip(a * c / GAIN + b, 0, 1)                  # noqa: E731
        sk = base.copy()
        sk[paint, :3] = tone(np.stack([np.interp(q, xp, ramp[:, i]) for i in range(3)], -1))
        save_png(downsample(sk, BAKE // SKIN), os.path.join(TEX_DIR, f"{NAME}_{pname}.png"), pname)
        # setColorHSV for the damage overlays: the shader gives Veh_Damage* texels the paint hue and S / V offsets
        # (vehicle_common.frag.glsl:6-15); their median S 0.03, V 0.45 should land on this skin's median paint
        h, s_, v_ = colorsys.rgb_to_hsv(*tone(ramp[len(ramp) // 2]))
        hsvs[pname] = [round(h, 3), round(min(1.0, s_ + 0.47), 3), round(min(1.0, v_ + 0.05), 3)]
    print("LUA colors", "\n".join(f'{{ name = "{p}", code = "{c}", h = {hsvs[p][0]}, s = {hsvs[p][1]}, v = {hsvs[p][2]} }},'
                                  for p, c in PAINTS))
    # mask / lights load with flag 256 too (BaseVehicle.java:595-615): 512 = the default cap (Core.java:266,3489-3495);
    # option 1 (256) shrinks them, harmless (mask alpha 255, lights RGB only matter where alpha is 1)
    f = BAKE // 512
    save_png(mask[::f, ::f], os.path.join(TEX_DIR, NAME + "_mask.png"), "mask")
    save_png(downsample(lit, f), os.path.join(TEX_DIR, NAME + "_lights.png"), "lights")
    counts = {k: int((zone[::f, ::f] == k).sum()) for k in Z}
    print("ZONES px", counts)
    # centre the body bbox like vanilla (mesh centre == model offset == centerOfMassOffset)
    co = mesh_co(body)
    c = (co.min(0) + co.max(0)) / 2
    zmid = float(c[2])
    set_co(body, co - [0, c[1], zmid])
    wl = [(sx, yc - c[1], zc, xo) for sx, yc, zc, xo in info["wl"]]
    mat = bpy.data.materials.new(NAME)
    body.data.materials.clear()
    body.data.materials.append(mat)
    export_fbx(body, os.path.join(VEH_DIR, NAME + ".fbx"))
    g = geometry(body, zmid, wl, info["wheel_r"])
    g |= {"tris_body": tris(body), "tris_wheel": info["wheel_tris"], "skin": SKIN, "skins": [p for p, _ in PAINTS],
          "scale": {k: info[k] for k in ("uniform_scale", "x_factor", "z_factor", "final_size", "official")}}
    json.dump(g, open(os.path.join(TMP, "geometry.json"), "w"), indent=1)
    print("GEOMETRY", json.dumps(g))
    previews(body, wl, zmid, info["wheel_r"])
    verify(n)


# ---------------------------------------------------------------- script numbers, previews, verify

S = 1.82              # vehicle scale (R5 3), model script scale = 1/S
OY = 0.1978           # model offset == centerOfMassOffset (unscaled), ModernCar convention
WHEEL_LIFT = 0.11     # rendered wheel sits this much (grid) above its script offset at rest: vanilla arch centres
#                       minus wheel offsets, ModernCar +0.10/+0.16, SUV +0.12/+0.10 (arch circle fit); calibration knob
WHEEL_INSET = 0.03    # tire outer face inside the measured Tripo tire (v1 E2E: flush tires looked proud of the arch)
PORT = (-1.74, 0.865)  # charge port (mesh y, ground z, grid): inside the side end of the left tail light (real Model Y);
#                        the red lens there spans y -1.72..-1.76, z 0.83-0.90 (bake texels R > 1.8 G, |nx| > 0.45)


def f4(*v):
    return " ".join(f"{x:.4f}" for x in v)


def geometry(body, zmid, wl, r):
    """Vehicle script geometry block. Mesh (x,y,z rel. mesh centre) -> script (-x, z, y) / S."""
    from mathutils.bvhtree import BVHTree
    co = mesh_co(body)
    me = body.data
    liner = np.array([d.value for d in me.attributes["liner"].data], bool)
    bc = co[sorted({i for k, p in enumerate(me.polygons) if not liner[k] for i in p.vertices})]
    w_body = 2 * np.abs(bc[bc[:, 2] < 0.55 * H - zmid][:, 0]).max()
    hgt, ln = bc[:, 2].max() - bc[:, 2].min(), np.ptp(bc[:, 1])
    ext = (w_body / S, hgt / S, ln / S)
    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    hit = bvh.ray_cast(Vector((-3, PORT[0], PORT[1] - zmid)), Vector((1, 0, 0)))[0]
    port = (-hit.x / S, (PORT[1] - zmid) / S, PORT[0] / S)
    belt = BELT_Z - zmid
    lo = (bc[:, 2].min() + belt) / 2
    cab = ((belt + bc[:, 2].max()) / 2, 1.30, 0.45, -1.60)
    aw, ah = 0.4725, 0.4725
    sx = ext[0] / 2 + aw / 2
    out = [
        "        model", "        {", f"            file = {NAME},", f"            scale = {S},", f"            offset = {f4(0, OY, 0)},", "        }",
        *[ln for p, _ in PAINTS for ln in ("        skin", "        {", f"            texture = Vehicles/{NAME}_{p},", "        }")],
        f"        textureMask = Vehicles/{NAME}_mask,", f"        textureLights = Vehicles/{NAME}_lights,",
        "        textureDamage1Overlay = Vehicles/Veh_Blood_Mask,", "        textureDamage2Overlay = Vehicles/Veh_Blood_Hvy,",
        "        textureDamage1Shell = Vehicles/Veh_Damage1,", "        textureDamage2Shell = Vehicles/Veh_Damage2,",
        "        textureRust = Vehicles/Veh_Rust,",
        "        template = PassengerSeat4,",
        f"        extents = {f4(*ext)},", f"        physicsChassisShape = {f4(*ext)},",
        f"        centerOfMassOffset = {f4(0, OY, 0)},",
        f"        shadowExtents = {f4(ext[0], ext[2])},", "        shadowOffset = 0.0 0.0,",
        "        useChassisPhysicsCollision = false,",
        "        physics box", "        {", f"            offset = {f4(0, lo / S + OY, 0)},",
        f"            extents = {f4((w_body - 0.03) / S, (belt - bc[:, 2].min()) / S, (ln - 0.06) / S)},", "        }",
        "        physics box", "        {", f"            offset = {f4(0, cab[0] / S + OY, (cab[2] + cab[3]) / 2 / S)},",
        f"            extents = {f4(cab[1] / S, (bc[:, 2].max() - belt) / S, (cab[2] - cab[3]) / S)},", "        }",
    ]
    names = {(-1, 1): "FrontLeft", (1, 1): "FrontRight", (-1, -1): "RearLeft", (1, -1): "RearRight"}
    for sxn, yc, zc, xo in wl:
        nm = names[(sxn, 1 if yc > 0 else -1)]
        out += [f"        wheel {nm}", "        {", f"            front = {'true' if yc > 0 else 'false'},",
                f"            offset = {f4(-sxn * (xo - TIRE_W / 2 - WHEEL_INSET) / S, (zc - zmid - WHEEL_LIFT) / S, yc / S)},",
                f"            radius = {(r - 0.015) / S:.4f},", f"            width = {TIRE_W:.4f},", "        }"]
    out += ["        part Tire*", "        {", "            model InflatedTirePlusWheel", "            {",
            f"                file = {NAME}_Wheel,", "            }", "        }"]
    seat_y, ground = (0.56 - zmid) / S, -zmid / S
    fz, rz = (DOOR_FRONT_Y + B_PILLAR_Y) / 2 - 0.12, (B_PILLAR_Y + DOOR_REAR_Y) / 2 - 0.08
    seats = (("FrontLeft", 1, fz, (DOOR_FRONT_Y, B_PILLAR_Y)), ("FrontRight", -1, fz, (DOOR_FRONT_Y, B_PILLAR_Y)),
             ("RearLeft", 1, rz, (B_PILLAR_Y, DOOR_REAR_Y)), ("RearRight", -1, rz, (B_PILLAR_Y, DOOR_REAR_Y)))
    for nm, side, z, door in seats:
        out += [f"        passenger {nm}", "        {", "            position inside", "            {",
                f"                offset = {f4(side * 0.33 / S, seat_y, z / S)},", "                rotate = 0.0 0.0 0.0,", "            }",
                "            position outside", "            {",
                f"                offset = {f4(side * (w_body / 2 + 0.30) / S, ground, z / S)},", "                rotate = 0.0 0.0 0.0,",
                f"                area = Seat{nm},", "            }", "        }"]
    areas = [("Engine", 0, ext[2] / 2 + ah / 2, ext[0], ah), ("TruckBed", 0, -(ext[2] / 2 + ah / 2), ext[0], ah),
             ("GasTank", sx, port[2], aw, ah)]
    for nm, side, z, door in seats:
        areas.append(("Seat" + nm, side * sx, ((door[0] + door[1]) / 2) / S, aw, (door[0] - door[1]) / S))
    for sxn, yc, zc, xo in wl:
        areas.append(("Tire" + names[(sxn, 1 if yc > 0 else -1)], -sxn * sx, yc / S, aw, ah))
    for nm, ax, az, w, h in areas:
        out += [f"        area {nm}", "        {", f"            xywh = {f4(ax, az, w, h)},", "        }"]
    tow = (bc[:, 2].min() + 0.08) / S
    out += ["        attachment trailer", "        {", f"            offset = {f4(0, tow, -(ln / 2 + 0.03) / S)},",
            "            rotate = 0.0 0.0 0.0,", "            zoffset = -1.0,", "        }",
            "        attachment trailerfront", "        {", f"            offset = {f4(0, tow, (ln / 2 + 0.03) / S)},",
            "            rotate = 0.0 0.0 0.0,", "            zoffset = 1.0,", "        }",
            "        /* charge port: side end of the left tail light (real Model Y) */",
            "        attachment chargeport", "        {", f"            offset = {f4(*port)},", "            rotate = 0.0 0.0 0.0,", "        }"]
    block = "\n".join(out) + "\n"
    open(os.path.join(TMP, "geometry_block.txt"), "w", newline="\n").write(block)
    # splice into the vehicle script: everything after the geometry marker up to the vehicle's closing brace is ours
    path = os.path.join(MEDIA, "scripts", "vehicles", NAME + ".txt")
    text = open(path, encoding="utf-8").read()
    head = text.index("\n", text.index("---- geometry (TeslaModelY)")) + 1
    tail = text.rindex("    }\n}")
    open(path, "w", encoding="utf-8", newline="\n").write(text[:head] + block + text[tail:])
    return {"zmid_ground": zmid, "body_width": w_body, "body_height": hgt, "length": ln, "port_mesh": [hit.x, PORT[0], PORT[1]],
            "wheelbase": wl[0][1] - wl[2][1], "wheel_radius": r}


def official_ramp(code, n=32):
    """sRGB paint colour per V quantile (n bins) of the official design-studio SIDE render of `code` (stage official):
    body side below the belt (car bbox rows 36-74%, columns 4-96%), wheel arches and rocker cut out, nose left."""
    a = img_np(bpy.data.images.load(os.path.join(OFFICIAL, f"{code}_SIDE.png")))[::-1].astype(np.float64)  # rows top-down
    m = a[..., 3] > 0.9
    ys, xs = np.nonzero(m)
    x0, y0, w, h = xs.min(), ys.min(), np.ptp(xs), np.ptp(ys)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    u, t = (xx - x0) / w, (yy - y0) / h
    keep = m & (t > 0.36) & (t < 0.74) & (u > 0.04) & (u < 0.96)
    for cu in (0.165, 0.80):                                             # wheels + arches
        keep &= ((u - cu) * w) ** 2 + ((t - 0.80) * h) ** 2 > (0.135 * w) ** 2
    px = a[..., :3][keep]
    px = px[np.argsort(px.max(1), kind="stable")]
    e = np.linspace(0, len(px), n + 1).astype(int)
    return np.array([px[e[i]:e[i + 1]].mean(0) for i in range(n)])


def stage_official():
    """Download the design-studio renders (SIDE for official_ramp, FRONT34 / REAR34 for comparison sheets)."""
    import urllib.request
    os.makedirs(OFFICIAL, exist_ok=True)
    for _, code in PAINTS:
        # $PB00 Frost Blue only exists on the Performance trim: with $MTY79 the compositor answers 412
        opts = "$MTY70,$PB00,$WY21A,$IPB14" if code == "PB00" else f"$MTY79,${code},$WY19P,$IPB15"
        for view in ("SIDE", "FRONT34", "REAR34"):
            req = urllib.request.Request(COMPOSITOR.format(opts, view), headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=60) as r, open(os.path.join(OFFICIAL, f"{code}_{view}.png"), "wb") as f:
                f.write(r.read())


def previews(body, wl, zmid, r):
    wheel = bpy.data.objects[NAME + "_Wheel"]
    wimg = bpy.data.images.load(os.path.join(TEX_DIR, NAME + "_wheel.png"))
    wm = bpy.data.materials.new("prev_wheel")
    wm.use_nodes = True
    wn = wm.node_tree.nodes.new("ShaderNodeTexImage")
    wn.image = wimg
    wm.node_tree.links.new(wn.outputs[0], wm.node_tree.nodes["Principled BSDF"].inputs[0])
    for sx, yc, zc, xo in wl:
        w = dup(wheel, "w")
        w.data.materials.clear()
        w.data.materials.append(wm)
        w.location = (sx * (xo - TIRE_W / 2 - WHEEL_INSET), yc, zc - zmid)
    for o in bpy.data.objects:
        o.hide_render = not (o is body or o.name.startswith("w."))
    mat = body.data.materials[0]
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    mat.node_tree.links.new(node.outputs[0], mat.node_tree.nodes["Principled BSDF"].inputs[0])
    mat.node_tree.nodes.active = node
    iso = {"iso": Vector((-1, 1, 1.15)), "iso_rear": Vector((1, -1, 1.15))}
    for pname, _ in PAINTS:
        node.image = bpy.data.images.load(os.path.join(TEX_DIR, f"{NAME}_{pname}.png"))
        more = {"left": Vector((-1, 0, 0)), "front": Vector((0, 1, 0.3))} if pname in ("StealthGrey", "UltraRed") else {}
        preview.render_views(os.path.join(PREV, pname), ortho=4.4, center=Vector((0, 0, 0)), res=(1600, 800),
                             views=iso | more)
    node.image = bpy.data.images.load(os.path.join(TEX_DIR, NAME + "_mask.png"))
    preview.render_views(os.path.join(PREV, "mask"), ortho=4.4, center=Vector((0, 0, 0)), res=(1600, 800),
                         views={"iso": Vector((-1, 1, 1.15)), "iso_rear": Vector((1, -1, 1.15))})


def verify(n):
    lines = []
    for p in (os.path.join(VEH_DIR, NAME + ".fbx"), os.path.join(VEH_DIR, NAME + "_Wheel.fbx")):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=p)
        for o in bpy.data.objects:
            if o.type != "MESH":
                continue
            me = o.data
            co = np.array([(o.matrix_world @ v.co)[:] for v in me.vertices])
            uvs = []
            for u in me.uv_layers:
                a = np.empty(len(me.loops) * 2)
                u.data.foreach_get("uv", a)
                uvs.append(f"{u.name}[{a.min():.3f},{a.max():.3f}]")
            lines.append(f"{os.path.basename(p)} {o.name}: tris={tris(o)} verts={len(me.vertices)} uv={' '.join(uvs)} "
                         f"size={np.round(np.ptp(co, 0), 3).tolist()}")
    m = np.round(img_np(bpy.data.images.load(os.path.join(TEX_DIR, NAME + "_mask.png")))[..., :3] * 255)
    allowed = np.array([np.round(np.array(c) * 255) for c in Z.values()])
    flat = m.reshape(-1, 3)[::5]
    bad = int((np.abs(flat[:, None, :] - allowed[None]).sum(-1).min(1) > 0).sum())
    lines.append(f"mask pixels outside the 27 zone colours (1/5 sample): {bad}")
    open(os.path.join(TMP, "verify.txt"), "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    st = args[0] if args else ""
    if st == "prep":
        stage_prep()
    elif st == "tiers":
        stage_tiers([int(x) for x in args[1].split(",")])
    elif st == "wheel":
        stage_wheel()
    elif st == "official":
        stage_official()
    elif st == "final":
        stage_final(int(args[1]))
    else:
        print(__doc__)
