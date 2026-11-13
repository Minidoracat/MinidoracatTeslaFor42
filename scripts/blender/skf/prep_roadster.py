"""Roadster 2.5 Sport source prep, run once before convert.py (CAR=roadster): the_86_guy's "2008 Tesla Roadster" FBX
(Sketchfab, CC BY 4.0; CREDITS.md) -> roadster_prep.fbx, the 2008 car made a 2.5 Sport on the 2.5 owner's manual
(10-15 dimensions, 10-4 tyres, 2-2 exterior) and the 2013 teslamotors.com photos (temp/skf_rd/SOURCE.md 3.8):
  - the body 50 mm higher on its wheels (manual height 1,127 and the drawing's arch gaps; the source's 1,077) and
    0.48 % wider (SX: width over the mirrors 1,842.2 -> 1,851);
  - lengthwise a piecewise linear map through the axles: wheelbase 2,363.9 -> 2,351, front overhang 855.6 -> 871.5,
    rear 712.4 -> 723.5 (length 3,946); the wheels with their axle and out to the manual's track (1,455.6 / 1,484.5);
  - one object per material (the source's body is one object), the interior and the lamp internals dropped (the mod's
    cabin; filaments and cork are a third of the source), the paint split into shell, doors, mirrors, hoop, charge
    port lid, hood (with its vents) and trunk lid (the source cuts neither lid: here along its seams);
  - the 2.5 nose and tail: the 2008 smile's lower lip in body colour, two grey bars and the tow eye across the intake,
    the rear grille's middle as the diffuser's centre plate with louvres either side (NOSE; the black around the
    intake and the corner side intakes: cars/roadster.py CARBON zones, cut after the decimation);
  - the hard top (Roof) as the black soft top (SoftTop, its lining SoftTopLining) cut into SOFT strips across its
    length for the stowing animation (convert.py SOFT_TOP).
Every mesh triangulated (the config's component keys count triangles). Frame: the build's pre-centre grid without
the 0.826 (convert.py src_frame, SRC_YFRONT branch with SRC_C (0, 0)): metres, +Y front, +Z up, -X the car's left,
ground 0; the FBX is written back in its own frame (front -Y, left +X, ground z -0.0018).
    "$B" -b --factory-startup --python scripts/blender/skf/prep_roadster.py            # -> roadster_prep.fbx
Numbers: temp/plan-next-1114/build/RoadsterBody.md (knowledge base models-roadster.md).
"""
import json
import math
import os
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "temp", "skf_rd", "src", "source")
SRC = os.path.join(SRC_DIR, "roadster_src.fbx")       # the Sketchfab download's source/2008 tesla roadster.fbx
OUT = os.path.join(SRC_DIR, "roadster_prep.fbx")
GROUND = -0.0018                                       # the source's tyre bottoms, source z

LIFT = 0.050                                           # body over the wheels (SOURCE.md 3.3)
SX = 1.851 / 1.8422                                    # body across: the manual's width over the mirrors / the source's
# lengthwise knots (pipeline y, metres): tail, rear axle, front axle, nose -> the manual's
Y_OLD = (-1.9681, -1.2557, 1.1082, 1.9638)
Y_NEW = (-1.97275, -1.24925, 1.10175, 1.97325)
# (centre track, tyre width less wheel_profile's 2 x 2.65 mm sidewall bulge) per axle: the outer face convert.py keeps
TRACK = {"front": (1.4556, 0.195 - 0.0053), "rear": (1.4845, 0.225 - 0.0053)}

# materials the build never sees: the source's cabin (cabin.py builds ours) and the lamps' insides
DROP_MATS = ("Interior", "Interior trim", "Leather pattern", "Carbon fiber", "Symbol", "Screen", "Radio buttons",
             "Leather", "Cluster gauge", "Cluster gauge glass", "Seat", "Tungsten", "Coil", "Light cork",
             "Light metal", "Light glass", "Light glass (orange)", "Needle")
DROP_OBJS = ("Steering wheel", "RPM", "Speed", "FL caliper", "FR caliper", "RL caliper", "RR caliper")
# trim components wholly inside the cabin box (pipeline metres, pre-map): dash, console, door-card bits
CABIN_BOX = ((-0.66, -0.62, 0.10), (0.66, 0.96, 0.99))

# paint components (pre-map bbox centre tests) and lid regions
HOOD = dict(z=0.50, side=((0.69, 0.545), (1.65, 0.38)), front=((0.0, 1.72), (0.20, 1.705), (0.38, 1.655)))
TRUNK = dict(x=0.365, y=(-1.685, -1.700), z=0.735)    # front crease y at x 0 / at |x| x; rear-face crease z
DOOR_X = 0.70                                          # the door skin's outer faces (the cabin's side wall is inboard)

SOFT = dict(n=12, y=(-0.5645, 0.1895))                 # strips across the roof (pipeline y extent)

# the 2.5 nose and tail (owner's manual 2-2 front / rear views, tm2013-front-intake-closeup-blue.jpg; pipeline metres
# after the move): the smile's lower lip (the Trim component reaching y > lip_y under z lip_z) joins the paint; bars
# (z rows, |x| span, height) on the grille / lip surface `out` proud of it, the tow eye (z, outer and inner radius) on
# the lower one; the rear grille's faces within |x| plate the diffuser's centre plate, louvres either side
NOSE = dict(lip_y=1.90, lip_z=0.25, bars=(0.290, 0.330), bar_x=0.53, bar_h=0.012, eye=(0.290, 0.026, 0.014),
            plate=0.22, louvres=(0.300, 0.335, 0.370), louvre_x=(0.26, 0.50), louvre_h=0.010, out=0.006, n=24)


def hull2(p):
    """Convex hull of 2-D points, counter-clockwise (monotone chain)."""
    p = p[np.lexsort((p[:, 1], p[:, 0]))]
    out = []
    for seq in (p, p[::-1]):
        h = []
        for q in seq:
            while len(h) > 1 and ((h[-1][0] - h[-2][0]) * (q[1] - h[-2][1])
                                  - (h[-1][1] - h[-2][1]) * (q[0] - h[-2][0])) <= 0:
                h.pop()
            h.append(q)
        out += h[:-1]
    return np.array(out)


def inside_hull(h, p):
    """Points p (N x 2) inside the counter-clockwise hull h."""
    ok = np.ones(len(p), bool)
    for a, b in zip(h, np.roll(h, -1, 0)):
        ok &= (b[0] - a[0]) * (p[:, 1] - a[1]) - (b[1] - a[1]) * (p[:, 0] - a[0]) >= 0
    return ok


def frame_pts(co):
    """Source world -> pipeline metres."""
    return np.c_[-co[:, 0], -co[:, 1], co[:, 2] - GROUND]


def world_pts(g):
    return np.c_[-g[:, 0], -g[:, 1], g[:, 2] + GROUND]


def ymap(y):
    """Lengthwise map and its slope (piecewise linear, the end segments extended)."""
    xo, xn = np.array(Y_OLD), np.array(Y_NEW)
    k = np.clip(np.searchsorted(xo, y) - 1, 0, len(xo) - 2)
    s = (xn[k + 1] - xn[k]) / (xo[k + 1] - xo[k])
    return xn[k] + (y - xo[k]) * s, s


def obj_g(o):
    me = o.data
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    M = np.array(o.matrix_world)
    return frame_pts(co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3])


def set_g(o, g):
    M = np.linalg.inv(np.array(o.matrix_world))
    w = world_pts(g)
    o.data.vertices.foreach_set("co", (w @ M[:3, :3].T + M[:3, 3]).ravel())
    o.data.update()


def face_centres(o):
    g = obj_g(o)
    return np.array([g[list(p.vertices)].mean(0) for p in o.data.polygons])


def keep_faces(o, keep):
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not keep[f.index]], context="FACES")
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()


def split_off(o, mask, name):
    """Faces of o under mask -> a new object `name` (same mesh data copied); o keeps the rest."""
    import bpy
    n = bpy.data.objects.new(name, o.data.copy())
    n.matrix_world = o.matrix_world.copy()
    bpy.context.scene.collection.objects.link(n)
    keep_faces(n, mask)
    keep_faces(o, ~mask)
    return n


def components(o):
    """Welded (1e-5) connected component of every face (vertices at the same rounded spot are one; remove_doubles
    would drop the faces it collapses)."""
    me = o.data
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    vid = np.unique(np.round(co.reshape(-1, 3) / 1e-5).astype(np.int64), axis=0, return_inverse=True)[1].ravel()
    parent = np.arange(vid.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for p in me.polygons:
        vs = [vid[v] for v in p.vertices]
        r = find(vs[0])
        for v in vs[1:]:
            rv = find(v)
            if rv != r:
                parent[rv] = r
    root = np.array([find(vid[p.vertices[0]]) for p in me.polygons])
    return np.unique(root, return_inverse=True)[1].ravel()


def comp_boxes(o, comp):
    g = obj_g(o)
    lo = np.full((comp.max() + 1, 3), np.inf)
    hi = -lo
    for p, c in zip(o.data.polygons, comp):
        v = g[list(p.vertices)]
        lo[c] = np.minimum(lo[c], v.min(0))
        hi[c] = np.maximum(hi[c], v.max(0))
    return lo, hi


def mat_name(m):
    return "".join(ch if ch.isalnum() else "_" for ch in m).strip("_")


def interp_x(pts, ax):
    """Polyline (|x|, y) points -> y at |x| ax (held flat past its ends)."""
    p = np.array(pts)
    return np.interp(ax, p[:, 0], p[:, 1])


def join(dst, src):
    """src's faces into dst (both copies of the source mesh: same frame and material slots); src removed."""
    import bmesh
    import bpy
    bm = bmesh.new()
    bm.from_mesh(dst.data)
    bm.from_mesh(src.data)
    bm.to_mesh(dst.data)
    bm.free()
    bpy.data.objects.remove(src)


def strip(tree, pts, d, h, out):
    """A bar on the surface: rays from pts along d, their hits `out` proud of it, h tall -> verts, quads facing back
    along d."""
    from mathutils import Vector
    d = np.array(d, float)
    P = np.array([tree.ray_cast(Vector(p), Vector(d))[0][:] for p in pts]) - d * out
    n = len(P)
    V = np.concatenate([P - (0, 0, h / 2), P + (0, 0, h / 2)])
    F = [(i, i + 1, n + i + 1, n + i) for i in range(n - 1)]
    if np.cross(V[1] - V[0], V[n] - V[0]) @ d > 0:
        F = [f[::-1] for f in F]
    return V, F


def ring(c, r0, r1, n=16):
    """A flat ring (radii r0 > r1) round c across x-z, facing +y -> verts, quads."""
    t = np.linspace(0, 2 * np.pi, n, endpoint=False)
    V = np.concatenate([c + np.c_[r * np.cos(t), np.zeros(n), r * np.sin(t)] for r in (r0, r1)])
    return V, [(i + n, (i + 1) % n + n, (i + 1) % n, i) for i in range(n)]


def nose(obs):
    """The 2.5 nose and tail (NOSE) on the moved objects."""
    import bpy
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    N = NOSE
    tr, gr, pt = obs["Trim"], obs["Grill"], obs["Paint"]
    comp = components(tr)
    lo, hi = comp_boxes(tr, comp)
    lip = (hi[:, 1] > N["lip_y"]) & (hi[:, 2] < N["lip_z"])
    if lip.sum() != 1:
        raise SystemExit(f"prep: {lip.sum()} lip components (NOSE lip_y / lip_z)")
    join(pt, split_off(tr, lip[comp], "Lip"))
    fc = face_centres(gr)
    plate = split_off(gr, (fc[:, 1] < -1.6) & (np.abs(fc[:, 0]) < N["plate"]), "Diffuser")
    plate.data.materials[0] = bpy.data.materials.new("Diffuser")
    V, F = [], []
    for o in (pt, tr, gr, plate):
        off = sum(map(len, V))
        F += [[off + i for i in p.vertices] for p in o.data.polygons]
        V.append(obj_g(o))
    tree = BVHTree.FromPolygons(np.concatenate(V).tolist(), F)
    parts = [strip(tree, [(x, 3.0, z) for x in np.linspace(-N["bar_x"], N["bar_x"], 2 * N["n"] + 1)], (0, -1, 0),
                   N["bar_h"], N["out"]) for z in N["bars"]]
    z, r0, r1 = N["eye"]
    parts.append(ring(np.array(tree.ray_cast(Vector((0, 3.0, z)), Vector((0, -1, 0)))[0][:]) + (0, 2 * N["out"], 0),
                      r0, r1))
    parts += [strip(tree, [(x, -3.0, z) for x in sd * np.linspace(*N["louvre_x"], N["n"])], (0, 1, 0),
                    N["louvre_h"], N["out"]) for z in N["louvres"] for sd in (1, -1)]
    V, F = [], []
    for pv, pf in parts:
        F += [[len(V) + i for i in f] for f in pf]
        V += pv.tolist()
    me = bpy.data.meshes.new("Intake_bar")
    me.from_pydata(world_pts(np.array(V)).tolist(), [], F)
    me.materials.append(bpy.data.materials.new("Intake bar"))
    bpy.context.scene.collection.objects.link(bpy.data.objects.new("Intake_bar", me))



def main():
    import bmesh
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=SRC)
    for nm in DROP_OBJS:
        bpy.data.objects.remove(bpy.data.objects[nm])
    # one object per material
    body = bpy.data.objects["2008 Tesla Roadster"]
    for o in bpy.context.view_layer.objects:
        o.select_set(o == body)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("2008 Tesla Roadster")]
    for o in parts:
        used = {p.material_index for p in o.data.polygons}
        mats = [o.data.materials[i].name for i in used]
        assert len(mats) == 1, (o.name, mats)
        if mats[0] in DROP_MATS:
            bpy.data.objects.remove(o)
            continue
        o.name = mat_name(mats[0])
    report = {}
    # trim: the cabin's components
    tr = bpy.data.objects["Trim"]
    comp = components(tr)
    lo, hi = comp_boxes(tr, comp)
    inside = (lo > CABIN_BOX[0]).all(1) & (hi < CABIN_BOX[1]).all(1)
    keep_faces(tr, ~inside[comp])
    report["trim dropped"] = [(int((comp == c).sum()), np.round(lo[c], 3).tolist(), np.round(hi[c], 3).tolist())
                              for c in np.flatnonzero(inside)]
    # paint: shell, doors, mirrors, hoop, port lid, hood (+ vents), trunk lid
    pt = bpy.data.objects["Paint"]
    comp = components(pt)
    lo, hi = comp_boxes(pt, comp)
    cen, size = (lo + hi) / 2, np.bincount(comp)
    big = np.argmax(size)
    fc = face_centres(pt)
    groups = {
        "PaintDoor": (np.abs(cen[:, 0]) > 0.6) & (np.abs(cen[:, 0]) < 0.75) & (np.abs(cen[:, 1]) < 0.1)
                     & (cen[:, 2] < 0.55),
        "PaintMirror": (np.abs(cen[:, 0]) > 0.65) & (cen[:, 1] > 0.2) & (cen[:, 1] < 0.4) & (cen[:, 2] > 0.7),
        "PaintHoop": (np.abs(cen[:, 0]) < 0.05) & (cen[:, 1] < -0.6) & (cen[:, 1] > -0.7) & (cen[:, 2] > 0.95),
        "PaintPort": (cen[:, 0] < -0.5) & (cen[:, 1] < -0.6) & (cen[:, 1] > -0.8) & (size < 200),
        "PaintVent": (np.abs(cen[:, 0]) < 0.05) & (cen[:, 1] > 0.9) & (cen[:, 1] < 1.4) & (size < 1000),
    }
    for nm, sel in groups.items():
        sel[big] = False
        report[nm] = [(int(size[c]), np.round(lo[c], 3).tolist(), np.round(hi[c], 3).tolist())
                      for c in np.flatnonzero(sel)]
        split_off(pt, sel[comp], nm)
        comp = comp[~sel[comp]]
    # the door skins: the source's door is its hem band (PaintDoor's component, round the edges) and the outer skin
    # inside it, which is part of the shell: the shell's outer faces (|x| > DOOR_X) inside the band's side-view hull
    dg = obj_g(bpy.data.objects["PaintDoor"])
    fc = face_centres(pt)
    door = np.zeros(len(fc), bool)
    for sd in (-1, 1):
        h = hull2(dg[np.sign(dg[:, 0]) == sd][:, 1:])
        door |= (np.sign(fc[:, 0]) == sd) & (np.abs(fc[:, 0]) > DOOR_X) & inside_hull(h, fc[:, 1:])
    report["door skin faces"] = int(door.sum())
    join(bpy.data.objects["PaintDoor"], split_off(pt, door, "PaintDoorSkin"))
    fc = face_centres(pt)
    # the lids out of the shell, by face centre along their seams (the hood's sides and front, the trunk lid's front
    # crease, rear-face crease and sides are edges of the source: no new cuts)
    ax = np.abs(fc[:, 0])
    (y0, x0), (y1, x1) = HOOD["side"]
    xs = x0 + (x1 - x0) * (fc[:, 1] - y0) / (y1 - y0)
    hood = (fc[:, 2] > HOOD["z"]) & (fc[:, 1] > 0.6) & (ax < xs) & (fc[:, 1] < interp_x(HOOD["front"], ax))
    split_off(pt, hood, "PaintHood")
    fc = face_centres(pt)
    ax = np.abs(fc[:, 0])
    yf = TRUNK["y"][0] + (TRUNK["y"][1] - TRUNK["y"][0]) * (ax / TRUNK["x"]) ** 2
    trunk = (ax < TRUNK["x"]) & (fc[:, 1] < yf) & (fc[:, 2] > TRUNK["z"])
    split_off(pt, trunk, "PaintTrunk")
    hd = bpy.data.objects["PaintHood"]             # the hood's vents ride the hood
    join(hd, bpy.data.objects["PaintVent"])
    report["hood faces"], report["trunk faces"] = len(hd.data.polygons), int(trunk.sum())
    # the soft top: the hard top's shape, black fabric outside, its lining inside, cut into strips across
    roof = bpy.data.objects["Roof"]
    roof.name = "SoftTop"
    for i, m in enumerate(roof.data.materials):
        roof.data.materials[i] = bpy.data.materials.new("SoftTop" if m.name == "Paint" else "SoftTopLining")
    # wheels: renamed (convert.py TIRE_OBJ / DROP), each with its axle, out to the manual's track
    for nm in ("FL", "FR", "RL", "RR"):
        w = bpy.data.objects[f"{nm} wheel"]
        w.name = f"Tire_{nm}"
    # move: every body object lengthwise and up; the wheels with their axle
    for o in [o for o in bpy.data.objects if o.type == "MESH"]:
        me = o.data
        g = obj_g(o)
        if o.name.startswith("Tire_"):
            front = g[:, 1].mean() > 0
            q = g.copy()
            q[:, 1] += ymap(np.array([Y_OLD[2 if front else 1]]))[0][0] - Y_OLD[2 if front else 1]
            tr_, w_ = TRACK["front" if front else "rear"]
            xo = np.abs(g[:, 0]).max()
            q[:, 0] += np.sign(g[:, 0].mean()) * (tr_ / 2 + w_ / 2 - xo)
            s, sx = np.ones(len(g)), 1.0
        else:
            q = g.copy()
            q[:, 1], s = ymap(g[:, 1])
            q[:, 0] *= SX
            q[:, 2] += LIFT
            sx = SX
        # normals (grid frame), inverse transpose of diag(sx, s, 1); custom normals kept per corner
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.corner_normals.foreach_get("vector", cn)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        R = np.array(o.matrix_world)[:3, :3]
        n = cn.reshape(-1, 3) @ R.T                    # world (rotation only in this FBX)
        n = np.c_[-n[:, 0], -n[:, 1], n[:, 2]]
        n[:, 0] /= sx
        n[:, 1] /= s[lv]
        n /= np.linalg.norm(n, axis=1, keepdims=True)
        n = np.c_[-n[:, 0], -n[:, 1], n[:, 2]] @ np.linalg.inv(R).T
        set_g(o, q)
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector",
                                                                                       n.astype(np.float32).ravel())
    nose({o.name: o for o in bpy.data.objects if o.type == "MESH"})
    # soft top strips (after the move: SOFT y is the mapped roof)
    roof = bpy.data.objects["SoftTop"]
    bm = bmesh.new()
    bm.from_mesh(roof.data)
    M = np.array(roof.matrix_world)
    ya, yb = (ymap(np.array([v]))[0][0] for v in SOFT["y"])
    for k in range(1, SOFT["n"]):
        y = ya + (yb - ya) * k / SOFT["n"]
        p = np.linalg.inv(M) @ np.array([0.0, -y, 0.0, 1.0])       # source frame: y -> -y
        nrm = np.linalg.inv(M[:3, :3]).T @ np.array([0.0, 1.0, 0.0])
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=p[:3], plane_no=nrm)
    bm.to_mesh(roof.data)
    bm.free()
    # triangulate everything (component keys count triangles)
    for o in [o for o in bpy.data.objects if o.type == "MESH"]:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.to_mesh(o.data)
        bm.free()
        o.data.update()
    for o in [o for o in bpy.data.objects if o.type == "MESH" and not len(o.data.polygons)]:
        bpy.data.objects.remove(o)
    report["objects"] = {o.name: len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH"}
    report["bbox"] = {o.name: (np.round(obj_g(o).min(0), 4).tolist(), np.round(obj_g(o).max(0), 4).tolist())
                      for o in bpy.data.objects if o.type == "MESH"}
    json.dump(report, open(os.path.join(SRC_DIR, "prep_report.json"), "w"), indent=1)
    bpy.ops.export_scene.fbx(filepath=OUT, use_selection=False, object_types={"MESH"}, mesh_smooth_type="OFF",
                             use_custom_props=False)
    print("PREP objects", report["objects"])
    print("PREP ->", OUT)


if __name__ == "__main__":
    main()
