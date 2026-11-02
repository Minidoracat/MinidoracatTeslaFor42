"""Texel density, UV use and paint / black borders of a shipped car (body + doors FBX and one skin) as the game camera
sees it: "$B" -b --factory-startup --python scripts/blender/skf/texel_audit.py -- <NAME> <paint> <out.json> [media dir]
Visible = a ray from the face centre towards one of the 8 game camera directions (30 deg up) misses every opaque face
(glass ignored: what is behind it shows). Classes by UV1 u (convert.uv1_class): 0 paint / trim, 1 cabin, 2 glass.
Paint = skin alpha < 255 at the face's UV0 centroid; dark = not paint, luminance < 0.3. Writes px/cm (2048) of the
visible paint per mesh, the UV square's use, and how much of the visible paint / non-paint border runs inside a UV
island (texel steps) against on a seam (models.md 10. 已知坑, the Model X entry). Borders of a face under 0.5 cm wide
across the edge are skipped: slivers (Cybertruck's panel gap bevels, 0.3 mm) never show and their centroid's texel is
a neighbour's."""
import bpy, json, math, os, sys
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

name, colour, out = sys.argv[sys.argv.index("--") + 1:][:3]
M = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "MOD",
                                 "MinidoracatTeslaFor42", "Contents", "mods", "MinidoracatTeslaFor42", "42", "media"))
if len(sys.argv[sys.argv.index("--") + 1:]) > 3:
    M = sys.argv[sys.argv.index("--") + 4]
K = 0.826                                   # grid units per metre
bpy.ops.wm.read_factory_settings(use_empty=True)
for f in (name, name + "_Doors", name + "_Glass"):
    bpy.ops.import_scene.fbx(filepath=f"{M}/models_X/vehicles/{f}.fbx")
for o in bpy.data.objects:
    if o.type == "ARMATURE":
        o.data.pose_position = "REST"
dg = bpy.context.evaluated_depsgraph_get()
img = bpy.data.images.load(f"{M}/textures/Vehicles/{name}_{colour}.png")
W, H = img.size
px = np.array(img.pixels[:], np.float32).reshape(H, W, 4)
P, UV0, UV1, OBJ = [], [], [], []
names = []
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    me = o.evaluated_get(dg).to_mesh()
    me.calc_loop_triangles()
    co = np.array([o.matrix_world @ v.co for v in me.vertices])
    if o.parent and o.parent.type == "ARMATURE":   # door pieces sit in the bone frame (Y up) at rest: body (x, -z, y)
        co = np.c_[co[:, 0], -co[:, 2], co[:, 1]]
    lt = np.array([t.loops[:] for t in me.loop_triangles])
    lv = np.array([l.vertex_index for l in me.loops])
    uvs = []
    for k in range(2):
        u = np.empty(len(me.loops) * 2)
        me.uv_layers[k].data.foreach_get("uv", u)
        uvs.append(u.reshape(-1, 2)[lt])
    P.append(co[lv[lt]]); UV0.append(uvs[0]); UV1.append(uvs[1]); OBJ += [len(names)] * len(lt)
    names.append(o.name)
P, UV0, UV1, OBJ = np.concatenate(P), np.concatenate(UV0), np.concatenate(UV1), np.array(OBJ)
u1 = UV1[:, 0, 0]
cls = np.where(u1 < -1.25, 1, np.where(u1 > 1.5, 2, 0))
n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
area = np.linalg.norm(n, axis=1) / 2
n /= np.maximum(2 * area, 1e-12)[:, None]
cen = P.mean(1)
# opaque BVH (everything but glass)
op = np.flatnonzero(cls != 2)
verts = P[op].reshape(-1, 3)
bvh = BVHTree.FromPolygons([Vector(v) for v in verts], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(op))])
el = math.radians(30)
dirs = [np.array([math.cos(el) * math.cos(a), math.cos(el) * math.sin(a), math.sin(el)])
        for a in np.radians(np.arange(0, 360, 45))]
vis = np.zeros(len(P), bool)
for i in np.flatnonzero((cls == 0) & (area > 1e-9)):
    for d in dirs:
        if n[i] @ d > 0.05:
            s = Vector(cen[i] + n[i] * 2e-3 + d * 1e-3)
            if bvh.ray_cast(s, Vector(d))[0] is None:
                vis[i] = True
                break
uvc = UV0.mean(1)
ix = np.clip((uvc[:, 0] * W).astype(int), 0, W - 1)
iy = np.clip((uvc[:, 1] * H).astype(int), 0, H - 1)
samp = px[iy, ix]
paint = samp[:, 3] < 0.999
lum = samp[:, :3] @ np.array([0.2126, 0.7152, 0.0722])
dark = ~paint & (lum < 0.3)
uva = np.abs(np.cross(UV0[:, 1] - UV0[:, 0], UV0[:, 2] - UV0[:, 0])) / 2
cm2 = area / K ** 2 * 1e4
res = dict(car=name, tris=int(len(P)), meshes=names)


def dens(sel):
    a, u = cm2[sel].sum(), uva[sel].sum() * 2048 ** 2
    return dict(px_per_cm=round(float(math.sqrt(u / a)), 3) if a else None, m2=round(float(a / 1e4), 2),
                tris=int(sel.sum()))


res["visible_paint"] = dens(vis & paint & (cls == 0))
res["visible_dark"] = dens(vis & dark & (cls == 0))
res["per_mesh_visible_paint"] = {nm: dens(vis & paint & (cls == 0) & (OBJ == k)) for k, nm in enumerate(names)}
res["hidden_class0"] = dens(~vis & (cls == 0))
# UV square use at 1024: 1 visible class 0, 2 hidden class 0, 3 glass, 4 cabin (max priority by order)
R = 1024
lab = np.zeros((R, R), np.uint8)
for pri, sel in ((4, cls == 1), (3, cls == 2), (2, (cls == 0) & ~vis), (1, (cls == 0) & vis)):
    for t in UV0[sel] * R:
        x0, y0 = np.floor(t.min(0)).astype(int); x1, y1 = np.ceil(t.max(0)).astype(int)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, R), min(y1, R)
        if x1 <= x0 or y1 <= y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        a, b, c = t
        def side(p, q):
            return (q[0] - p[0]) * (gy - p[1]) - (q[1] - p[1]) * (gx - p[0])
        s1, s2, s3 = side(a, b), side(b, c), side(c, a)
        inside = ((s1 >= 0) & (s2 >= 0) & (s3 >= 0)) | ((s1 <= 0) & (s2 <= 0) & (s3 <= 0))
        sub = lab[y0:y1, x0:x1]
        sub[inside] = pri
res["uv_use"] = {k: round(float((lab == v).mean()), 4) for k, v in
                 (("visible_exterior", 1), ("hidden_exterior", 2), ("glass", 3), ("cabin", 4), ("empty", 0))}
# paint / non-paint borders between two visible class-0 faces: UV continuous (texel border) or a seam (geometric)
sel = np.flatnonzero(vis & (cls == 0))
edges = {}
for i in sel:
    for a, b in ((0, 1), (1, 2), (2, 0)):
        ka, kb = tuple(np.round(P[i, a], 4)), tuple(np.round(P[i, b], 4))
        key = (ka, kb) if ka < kb else (kb, ka)
        edges.setdefault(key, []).append((i, a, b) if ka < kb else (i, b, a))
tex_len = seam_len = 0.0
for key, fs in edges.items():
    if len(fs) != 2:
        continue
    (i, a, b), (j, c, d) = fs
    if paint[i] == paint[j]:
        continue
    L = float(np.linalg.norm(P[i, a] - P[i, b])) / K * 100
    if min(cm2[i], cm2[j]) * 2 / L < 0.5:
        continue
    same = np.allclose(UV0[i, a], UV0[j, c], atol=1e-5) and np.allclose(UV0[i, b], UV0[j, d], atol=1e-5)
    if same:
        tex_len += L
    else:
        seam_len += L
res["paint_border_cm"] = dict(in_island=round(tex_len), seam=round(seam_len),
                              in_island_share=round(tex_len / max(tex_len + seam_len, 1e-9), 3))
json.dump(res, open(out, "w"), indent=1)
print("MEASURE", json.dumps(res))
