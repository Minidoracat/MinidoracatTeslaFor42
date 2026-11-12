"""Model X source prep, run once before convert.py (CAR=model_x): Abdul.Hannan's 'sketchfab tesla.blend' (a half
model: Mirror + Subsurf + Auto Smooth modifiers) -> the OBJ cars/model_x.py SRC reads, every modifier applied (the
Mirror makes the whole car; Subsurf at level 1 on the body parts, 0 on the tyres and rims; Back Door not welded across
the roof's middle, so each falcon wing door stays its own component for SIDE_PARTS), then the big parts
collapse-decimated with every material border and open edge held (a plain collapse left the paint / black trim borders
as a sawtooth: the diffuser, the sills). Ground (lowest tyre vertex) at z 0.
Then the last Model X Plaid (2021+) against its owner's manual (2026.38.3 p.229 / p.234: length 5,057, width 1,999
without mirrors (2,271 with), height 1,680 (Medium), wheelbase 2,965, overhangs 988 / 1,104, track 1,705 / 1,710 at the
wheel centres, tyres 265/45 R20 front, 275/45 R20 rear) and the design studio's SIDE / FRONT34 / REAR34 renders through
the fitted cameras (.claude/skills/tesla-dev/references/models-model-x.md "對官方"): one continuous displacement field
(FIELD; as prep_model_yl.py: no cuts, every object keeps its triangles, normals by the field's Jacobian, inverse
transpose), some faces recoloured (FIELD arch_inner, mirror, ...) and the mod's own parts as new objects (FIELD spoiler,
...). The doors, lids and glass on the body's centre line (the source's sit 8 mm to the car's right).
    "$B" -b --factory-startup --python scripts/blender/skf/prep_model_x.py [-- <src .blend> <out .obj>]
    python scripts/blender/skf/prep_model_x.py map < points     # "name x y z" pre-centre grid -> through the field
Defaults: temp/skf_mx/src/source/sketchfab tesla.blend -> temp/skf_mx/src/source/model_x.obj (+ .mtl).
Frame: Blender world after the modifiers (x + front, y + car left, z up), source units; the FIELD in metres: u behind
the nose, h over the ground, az off the centre line.
"""
import os
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "temp", "skf_mx", "src", "source")
TARGET = {"Car Body": 26000, "Front Door": 4400, "Trunk": 3200, "Bonnet": 1200}   # triangles after the collapse
S = 5.057 / 3.1184                         # metres per source unit (cars/model_x.py SRC_SCALE)
K, SRC_C = 0.826, (1.5579, -0.448)          # pzveh.K; cars/model_x.py SRC_C (the pre-centre frame's origin)
CENTRED = ("Front Door", "Back Door", "Bonnet", "Trunk")   # onto Car_Body's mirror plane
# (the .blend's object and material names: the OBJ writes "Car Body" as Car_Body, "Car Paint" as Car_Paint.) Source landmarks (metres): nose u 0, front axle u 0.994, rear 3.957, tail 5.057; tyres r 0.3735 (the rear's bottom
# 6 mm up); half width 1.0158 over the front arch lips. Calibration knobs
FIELD = dict(
    width=1.999,                   # without mirrors (the arch lips are the widest)
    mirror=2.271,                  # with them: the mirror (FIELD mirror_obj) moved out onto it
    # tyres (radius, width) and the track at the wheel centres per axle
    tyre=dict(f=(0.3733, 0.265, 1.705), r=(0.3778, 0.275, 1.710)),
    # faces recoloured: the inside of the wheel arches (the source's wheel wells in Car_Paint: official black)
    arch_inner=dict(obj="Car Body", mat="Car Paint", to="Black Car Paint", rho=0.66, below=0.15, inward=-0.25, az=0.55,
                    out=0.5, wall=0.85),
    # the mirror cut out of the front doors (its own object: cars/model_x.py SIDE_PARTS / SHELL_OBJS, no slab inner
    # copy), its back round the glass and the arm black (official REAR34)
    mirror_obj=dict(obj="Front Door", name="Mirror_X", u=(1.56, 1.86), h=1.03, az=0.932, back=-0.45,
                    arm_h=1.085, to="Black Car Paint"),
    # displacement terms: d (back, up[, out]) x win(u) x win(h) x win(az) (win: see win()). Same-camera numbers in px
    # (official SIDE, near side ~4 mm / px; + = the model right / low) before -> the term's d
    terms=(
        dict(d=(0, -0.022), u=(-1, -0.5, 1.70, 2.10), h=(0.86, 0.95, 1.20, 1.40)),   # hood: top -5..-7 px
        dict(d=(0, -0.035), u=(-1, -0.5, 0.40, 0.80), h=(0.70, 0.86), az=(0.80, 0.60)),   # nose top: -9..-16 px
        dict(d=(0, 0.018), u=(2.65, 3.05, 4.30, 4.70), h=(1.30, 1.45)),            # roof: +3..+6 px
        dict(d=(0, 0.030), u=(3.85, 4.25, 5.2, 5.3), h=(1.15, 1.30), az=(0.68, 0.45)),   # rear roof: +10..+12 px
        dict(d=(0, -0.024), u=(1.55, 1.85, 3.20, 3.85), h=(1.02, 1.07, 1.10, 1.30)),   # belt: -5..-7 px
        dict(d=(0, -0.018), u=(1.30, 1.55, 3.55, 3.75), h=(0.32, 0.22)),           # skirt bottom: -4..-5 px
        dict(d=(-0.020, 0), u=(1.30, 1.53, 1.53, 1.78), h=(0.40, 0.55)),           # front door's front seam +5 px
        dict(d=(-0.026, 0), u=(2.35, 2.75, 2.75, 3.15)),                          # B seam +6..+7 px
        dict(d=(-0.020, 0), u=(3.70, 3.98, 3.98, 4.25), h=(0.62, 0.75)),           # falcon rear seam +3..+6 px
        dict(d=(0.17, 0), u=(4.55, 4.80), h=(0.25, 0.30, 0.72, 0.85), az=(0.45, 0.85)),   # tail corners -24..-29
        dict(d=(0.09, 0), u=(4.55, 4.80), h=(0.78, 0.88, 1.15, 1.25), az=(0.45, 0.85)),   # (lamps) -14..-15 px
    ),
    # the wheel arches' openings: round the axle, towards it by d x k(angle from the top, deg: + rearward) x win(rho)
    arches=(
        dict(ax="r", d=0.064, rho=(0.40, 0.47, 0.58, 0.80), ang=((-180, 0.0), (-110, 0.0), (-90, 0.5), (0, 1.0),
                                                                    (90, 0.0), (180, 0.0)), az=(0.55, 0.65)),
        dict(ax="f", d=-0.012, rho=(0.40, 0.45, 0.55, 0.70), ang=((-180, 0.0), (-60, 0.0), (0, 1.0), (60, 0.0),
                                                                     (180, 0.0)), az=(0.55, 0.65)),   # top +3 px
    ),
)


def s(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def win(x, k):
    """weight over x: None 1; (a, b) up from a to b; (a, b, c, d) up a..b, down c..d (a > b: down)"""
    if k is None:
        return np.ones_like(x)
    if len(k) == 2:
        return s(x, *k)
    return s(x, k[0], k[1]) * (1 - s(x, k[2], k[3]))


class Field:
    """(u, h, az) metres -> (du back, dh up, daz out), on top of the width scale."""

    def __init__(self, ax):
        self.ax = ax                       # axle u, h per "f" / "r"

    def __call__(self, u, h, az):
        du, dh, da = np.zeros_like(u), np.zeros_like(u), np.zeros_like(u)
        for t in FIELD["terms"]:
            w = win(u, t.get("u")) * win(h, t.get("h")) * win(az, t.get("az"))
            d = t["d"]
            du, dh, da = du + d[0] * w, dh + d[1] * w, da + (d[2] if len(d) > 2 else 0) * w
        for a in FIELD["arches"]:
            x, y = u - self.ax[a["ax"]][0], h - self.ax[a["ax"]][1]
            rho = np.maximum(np.hypot(x, y), 1e-6)
            k = np.interp(np.degrees(np.arctan2(x, y)), *zip(*a["ang"])) * win(rho, a["rho"]) * win(az, a["az"])
            du, dh = du - a["d"] * k * x / rho, dh - a["d"] * k * y / rho
        return du, dh, da


def jac(fld, u, h, az, wk):
    """d(x', y', z')/d(x, y, z) per point in the (u, h, az) frame (u is minus x: the signs stay as the frame's)"""
    E = 1e-4
    J = np.zeros((len(u), 3, 3))
    for j, (a, b) in enumerate(((fld(u + E, h, az), fld(u - E, h, az)), (fld(u, h + E, az), fld(u, h - E, az)),
                                (fld(u, h, az + E), fld(u, h, az - E)))):
        for i in range(3):
            J[:, i, j] = (a[i] - b[i]) / (2 * E)
    J[:, 0, 0] += 1
    J[:, 1, 1] += 1
    J[:, 2, 2] += wk
    return J


def slot(me, name):
    """the material slot of `name` in me (added when missing)"""
    import bpy
    for i, m in enumerate(me.materials):
        if m.name == name:
            return i
    me.materials.append(bpy.data.materials.get(name) or bpy.data.materials.new(name))
    return len(me.materials) - 1


def slots(me, name):
    """every material slot holding `name`"""
    return [i for i, m in enumerate(me.materials) if m and m.name == name]


def face_frame(me, nose, yc):
    """per polygon: centre (u, h, az) in metres and the world normal"""
    c = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("center", c)
    n = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("normal", n)
    c, n = c.reshape(-1, 3), n.reshape(-1, 3)
    return (nose - c[:, 0]) * S, c[:, 2] * S, np.abs(c[:, 1] - yc) * S, n, np.sign(c[:, 1] - yc)


def split_mirror(bpy, meshes, nose, yc):
    """FIELD mirror_obj: the mirrors' faces out of the front doors into their own object, back and arm black."""
    mo = FIELD["mirror_obj"]
    o = next(o for o in meshes if o.name == mo["obj"])
    u, h, az, n, _ = face_frame(o.data, nose, yc)
    sel = (u > mo["u"][0]) & (u < mo["u"][1]) & (h > mo["h"]) & (az > mo["az"])
    for p, v in zip(o.data.polygons, sel):
        p.select = bool(v)
    before = set(bpy.data.objects)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    m = next(iter(set(bpy.data.objects) - before))
    m.name = m.data.name = mo["name"]
    me = m.data
    u, h, az, n, _ = face_frame(me, nose, yc)
    paint, black = slots(me, "Car Paint"), slot(me, mo["to"])
    mi = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("material_index", mi)
    back = np.isin(mi, paint) & ((n[:, 0] < mo["back"]) | (h < mo["arm_h"]))
    mi[back] = black
    me.polygons.foreach_set("material_index", mi)
    me.update()
    print("PREP mirror: %d faces (%d black)" % (int(sel.sum()), int(back.sum())))
    return m


def recolour_arches(meshes, nose, yc, ax):
    """FIELD arch_inner: the wheel wells' paint faces black, round each axle (inside rho, above it less `below`): the
    well's roof (facing the axle, outboard of `az`) and its inboard wall (facing out, inboard of `wall`)."""
    a = FIELD["arch_inner"]
    o = next(o for o in meshes if o.name == a["obj"])
    me = o.data
    u, h, az, n, sg = face_frame(me, nose, yc)
    mi = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("material_index", mi)
    src, dst = slots(me, a["mat"]), slot(me, a["to"])
    hit = np.zeros(len(u), bool)
    out = n[:, 1] * sg                                        # the normal's outward part
    for u0, h0, _ in ax.values():
        x, y = u0 - u, h - h0                                 # (world x, z) off the axle: x = -u
        rho = np.maximum(np.hypot(x, y), 1e-9)
        inward = (n[:, 0] * x + n[:, 2] * y) / rho
        near = np.isin(mi, src) & (rho < a["rho"]) & (h > h0 - a["below"])
        hit |= near & (inward < a["inward"]) & (az > a["az"]) | near & (out > a["out"]) & (az < a["wall"])
    mi[hit] = dst
    me.polygons.foreach_set("material_index", mi)
    me.update()
    return int(hit.sum())


def main():
    import bmesh
    import bpy
    from mathutils import Matrix
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src, out = (args + [os.path.join(SRC_DIR, "sketchfab tesla.blend"), os.path.join(SRC_DIR, "model_x.obj")][len(args):])[:2]
    bpy.ops.wm.open_mainfile(filepath=src)
    for o in bpy.data.objects:
        for m in getattr(o, "modifiers", []):
            if m.type == "SUBSURF":
                m.levels = 0 if o.name.startswith(("Tyre", "Rim")) else 1
            if m.type == "MIRROR" and o.name == "Back Door":
                m.use_mirror_merge = False
    dg = bpy.context.evaluated_depsgraph_get()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        me = o.data = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        o.modifiers.clear()

    def tris(o):
        return sum(len(p.vertices) - 2 for p in o.data.polygons)

    for o in meshes:
        if o.name not in TARGET:
            continue
        bpy.context.view_layer.objects.active = o
        for _ in range(3):                      # the ratio is on triangles: repeat until within 3 %
            n = tris(o)
            if n <= TARGET[o.name] * 1.03:
                break
            bm = bmesh.new()
            bm.from_mesh(o.data)
            held = {v.index for e in bm.edges if len(e.link_faces) != 2
                    or e.link_faces[0].material_index != e.link_faces[1].material_index for v in e.verts}
            bm.free()
            if "interior" in o.vertex_groups:
                o.vertex_groups.remove(o.vertex_groups["interior"])
            o.vertex_groups.new(name="interior").add([i for i in range(len(o.data.vertices)) if i not in held], 1.0,
                                                     "REPLACE")
            m = o.modifiers.new("dec", "DECIMATE")
            m.decimate_type, m.ratio = "COLLAPSE", TARGET[o.name] / n
            m.use_symmetry, m.symmetry_axis = True, "Y"          # the source's mirror plane is local y 0
            m.vertex_group, m.vertex_group_factor = "interior", 1000.0
            bpy.ops.object.modifier_apply(modifier=m.name)
        print("PREP decimated", o.name, tris(o), "tris")
    # world frame from here on: every transform into the vertices, the ground at z 0
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix()
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    ground = min(min(v.co.z for v in o.data.vertices) for o in meshes if o.name.startswith("Tyre"))
    for o in meshes:
        o.data.transform(Matrix.Translation((0, 0, -ground)))
    pts = lambda o: np.array([v.co[:] for v in o.data.vertices])   # noqa: E731
    body = pts(next(o for o in meshes if o.name == "Car Body"))
    yc = (body[:, 1].min() + body[:, 1].max()) / 2                  # the mirror plane
    for o in meshes:
        if o.name in CENTRED:
            c = pts(o)
            o.data.transform(Matrix.Translation((0, yc - (c[:, 1].min() + c[:, 1].max()) / 2, 0)))
    nose = max(pts(o)[:, 0].max() for o in meshes if not o.name.startswith(("Tyre", "Rim")))
    tyre = {k: np.concatenate([c for c in (pts(o) for o in meshes if o.name.startswith("Tyre"))
                               if (c[:, 0].mean() > nose / 2) == f]) for k, f in (("f", True), ("r", False))}
    ax = {k: ((nose - (t[:, 0].min() + t[:, 0].max()) / 2) * S, (t[:, 2].min() + t[:, 2].max()) / 2 * S,
              np.ptp(t[:, 2]) / 2 * S) for k, t in tyre.items()}
    meshes.append(split_mirror(bpy, meshes, nose, yc))
    narch = recolour_arches(meshes, nose, yc, ax)
    fld = Field(ax)
    wk = FIELD["width"] / (2 * S * max(np.abs(pts(o)[:, 1] - yc).max() for o in meshes
                                       if not o.name.startswith(("Tyre", "Rim", "Mirror_X"))))
    for o in meshes:
        me, p = o.data, pts(o)
        cn = np.empty(len(me.loops) * 3, np.float32)             # the corner normals before the move
        me.corner_normals.foreach_get("vector", cn)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        u, h, az = (nose - p[:, 0]) * S, p[:, 2] * S, np.abs(p[:, 1] - yc) * S
        sg = np.where(p[:, 1] >= yc, 1.0, -1.0)
        if o.name.startswith(("Tyre", "Rim")):          # whole with their axle: the official tyre round its centre
            k = "f" if u.mean() < 2.5 else "r"
            r, w, track = FIELD["tyre"][k]
            u0, h0, r0 = ax[k]
            du0 = fld(np.array([u0]), np.array([h0]), np.array([0.0]))[0][0]
            tz = np.abs(pts(next(t for t in meshes if t.name.startswith("Tyre") and
                                 (np.sign(pts(t)[:, 1].mean() - yc) == sg[0]) and ((nose - pts(t)[:, 0].mean()) * S < 2.5) == (k == "f")))[:, 1] - yc) * S
            side, fz = (tz.min() + tz.max()) / 2, w / np.ptp(tz)
            f = r / r0
            uu, hh, aa = u0 + du0 + (u - u0) * f, r + (h - h0) * f, track / 2 + (az - side) * fz
            J = np.zeros((len(p), 3, 3))
            J[:, 0, 0] = J[:, 1, 1] = f
            J[:, 2, 2] = fz
        else:
            du, dh, da = fld(u, h, az)
            J = jac(fld, u, h, az, wk)
            uu, hh, aa = u + du, h + dh, az * wk + da
            if o.name == "Mirror_X":                     # out onto the width with mirrors
                aa = aa + FIELD["mirror"] / 2 - aa.max()
        q = np.stack([nose - uu / S, yc + sg * aa / S, hh / S], 1)
        # world Jacobian: (x', y', z') = P (u', h', az'), (u, h, az) = Q (x, y, z)
        P = np.zeros((len(p), 3, 3))
        P[:, 0, 0], P[:, 1, 2], P[:, 2, 1] = -1, sg, 1
        Q = np.zeros((len(p), 3, 3))
        Q[:, 0, 0], Q[:, 1, 2], Q[:, 2, 1] = -1, 1, sg
        Jw = P @ J @ Q
        me.vertices.foreach_set("co", q.ravel())
        n = np.einsum("lij,li->lj", np.linalg.inv(Jw)[lv], cn.reshape(-1, 3))   # n' = J^-T n (row vector n J^-1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", n.astype(np.float32).ravel())
        me.update()
    print("PREP width x %.5f, axles u %.4f / %.4f h %.4f / %.4f r %.4f / %.4f, doors centred on y %.4f, arch faces %d"
          % (wk, ax["f"][0], ax["r"][0], ax["f"][1], ax["r"][1], ax["f"][2], ax["r"][2], yc, narch))
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.ops.wm.obj_export(filepath=out, export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y",
                          export_uv=False, export_normals=True, export_materials=True, apply_modifiers=True,
                          export_triangulated_mesh=False)
    print("PREP ground", ground, "->", out)


if __name__ == "__main__":
    main()
