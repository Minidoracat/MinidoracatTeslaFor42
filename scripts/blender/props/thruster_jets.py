"""TeslaThruster's jets (part TeslaThruster, models Lift / Side / Rear; roadster2.md): one static mesh per group in
the body's frame (part model offset 0, as armor.py), an open cone per nozzle on the shared gradient
MinidoracatTesla/Jet (not under Vehicles/: verify_local reads those as car skins), drawn by shader MinidoracatTesla_jet
(unlit, edge-faded, alpha-tested). Also writes
the landing fog marker MinidoracatTesla/JetFog (client ThrusterFx.lua).

Nozzles: `nozzles` of temp/skf_r2/roadster2_lines.json (R2Body's prep frame: metres, +Y front, +Z up, -X car left,
ground z = 0, y = 0 at mid-length) taken to the mesh frame with temp/skf_r2/geometry.json (centre_y, zmid; grid);
either file missing -> the estimate below (no official dimensions yet). A cone's u runs 0 at the nozzle to 1 at its
far end, v around it.

    "$B" -b --factory-startup --python scripts/blender/props/thruster_jets.py -- [--lines F] [--geom F] [--out DIR]
"""
import json, math, os, sys
import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MEDIA = os.path.join(REPO, "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media")
K = 0.826                       # grid per metre (pzveh.K)
NAME = "MinidoracatTesla_Roadster2_Jet"
# Estimate (metres, prep frame) for a ~4.3 m car: lift under the wheels, side at the nose corners, rear four in the
# diffuser. Replace by R2Body's nozzles once the body exists.
ESTIMATE = {"lift": [[-0.55, 1.30, 0.22], [0.55, 1.30, 0.22], [-0.55, -1.30, 0.22], [0.55, -1.30, 0.22]],
            "side": [[-0.95, 1.75, 0.45], [0.95, 1.75, 0.45]],
            "rear": [[-0.62, -2.15, 0.45], [-0.25, -2.15, 0.45], [0.25, -2.15, 0.45], [0.62, -2.15, 0.45]],
            "r": 0.06}
GEOM_ESTIMATE = {"centre_y": 0.0, "zmid": 0.50}
# Per group: direction (mesh frame; side: outward by the nozzle's x), length and far-end radius, metres. The official
# film's columns run to the ground and spread to about a metre across (f2-kickflip-replay 11m27).
SHAPE = {"lift": ((0, 0, -1), 3.0, 0.50), "side": (None, 1.4, 0.28), "rear": ((0, -1, 0), 2.6, 0.55)}
RINGS, SIDES = 10, 16


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"lines": os.path.join(REPO, "temp/skf_r2/roadster2_lines.json"),
         "geom": os.path.join(REPO, "temp/skf_r2/geometry.json"), "out": MEDIA}
    for k, v in zip(a[::2], a[1::2]):
        o[k.lstrip("-")] = v
    return o


def table(o):
    noz, geom = ESTIMATE, GEOM_ESTIMATE
    if os.path.isfile(o["lines"]):
        noz = json.load(open(o["lines"], encoding="utf-8")).get("nozzles") or ESTIMATE
    if os.path.isfile(o["geom"]):
        geom = json.load(open(o["geom"], encoding="utf-8"))
    src = "lines" if noz is not ESTIMATE else "estimate"
    print(f"jets: nozzles from {src}, centre_y={geom['centre_y']:.3f} zmid={geom['zmid']:.3f}")
    to_mesh = lambda p: np.array([p[0] * K, p[1] * K - geom["centre_y"], p[2] * K - geom["zmid"]])  # noqa: E731
    return {g: [to_mesh(p) for p in noz[g]] for g in ("lift", "side", "rear")}, noz.get("r", 0.06) * K


def cone(p0, d, length, r0, r1):
    """Open tube from p0 along unit d: verts, quads (outward), uv per quad corner."""
    d = np.asarray(d, float)
    a = np.array([1.0, 0, 0]) if abs(d[0]) < 0.9 else np.array([0, 1.0, 0])
    e1 = np.cross(d, a); e1 /= np.linalg.norm(e1)
    e2 = np.cross(d, e1)
    verts, quads, uvs = [], [], []
    for i in range(RINGS + 1):
        t = i / RINGS
        r = r0 + (r1 - r0) * t ** 0.75
        for j in range(SIDES + 1):          # seam duplicated so v runs 0..1
            th = 2 * math.pi * j / SIDES
            verts.append(p0 + d * length * t + r * (math.cos(th) * e1 + math.sin(th) * e2))
    for i in range(RINGS):
        for j in range(SIDES):
            a0, b0 = i * (SIDES + 1) + j, (i + 1) * (SIDES + 1) + j
            quads.append((a0, a0 + 1, b0 + 1, b0))      # e1 x e2 = d: counter-clockwise seen from outside
            uvs.append([(i / RINGS, j / SIDES), (i / RINGS, (j + 1) / SIDES), ((i + 1) / RINGS, (j + 1) / SIDES),
                        ((i + 1) / RINGS, j / SIDES)])
    return verts, quads, uvs


def build(group, nozzles, r0):
    d0, length, r1 = SHAPE[group]
    V, Q, U = [], [], []
    for p in nozzles:
        d = d0 or (float(np.sign(p[0])), 0.0, 0.0)
        v, q, u = cone(p, d, length * K, r0, r1 * K)
        Q += [tuple(k + len(V) for k in f) for f in q]
        V += v
        U += u
    me = bpy.data.meshes.new(group)
    me.from_pydata([tuple(x) for x in V], [], Q)
    uv = me.uv_layers.new(name="UVMap")
    uv.data.foreach_set("uv", np.array(U, np.float32).ravel())
    me.update()
    ob = bpy.data.objects.new(NAME + group.capitalize(), me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def export_fbx(ob, path):
    """pzveh.export_fbx (same axes as the body, so offset 0 lines up)."""
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", bake_space_transform=True,
                             axis_forward="-Z", axis_up="Y", mesh_smooth_type="OFF",
                             add_leaf_bones=False, bake_anim=False, path_mode="STRIP")


def save_png(arr, path):
    """arr: rows bottom-up (Blender pixel order), RGBA 0..1."""
    h, w = arr.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(arr, np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()


def periodic_noise(shape, octaves, seed):
    """Sum of random sine waves, periodic across v (axis 0) so the seam does not show; 0..1."""
    rng = np.random.default_rng(seed)
    h, w = shape
    v, u = np.meshgrid(np.arange(h) / h, np.arange(w) / w, indexing="ij")
    n = np.zeros(shape)
    for k in octaves:
        for _ in range(3):
            n += np.sin(2 * math.pi * (k * v + rng.uniform(1, 4) * k * 0.5 * u + rng.uniform()))
    n -= n.min()
    return n / n.max()


def jet_texture(path):
    """u (x, 256 px): white core at the nozzle to pale cyan-blue, alpha rising over the first few percent then fading
    to nothing; v (y, 64 px, periodic): soft streaks."""
    h, w = 64, 256
    t = np.arange(w) / (w - 1)
    alpha = np.clip(t / 0.04, 0, 1) * (1 - t) ** 1.5 * 0.9
    streak = 0.7 + 0.3 * periodic_noise((h, w), (2, 3, 5), 7)
    a = alpha[None, :] * streak
    col0, col1 = np.array([1.0, 1.0, 1.0]), np.array([0.62, 0.86, 1.0])
    rgb = col0 + (col1 - col0) * (t ** 0.6)[:, None]
    arr = np.zeros((h, w, 4))
    arr[..., :3] = rgb[None, :, :]
    arr[..., 3] = a
    save_png(arr, path)


def fog_texture(path):
    """Landing fog standing on the ground (IsoMarkers draws it at its own size, bottom centre on the tile): a wide,
    low cloud of soft puffs, densest at the base, white with a faint blue."""
    h, w = 256, 512
    rng = np.random.default_rng(11)
    y, x = np.meshgrid(np.arange(h) + 0.5, np.arange(w) + 0.5, indexing="ij")   # y up from the bottom row
    d = np.zeros((h, w))
    for _ in range(30):
        cx = rng.normal(w / 2, w * 0.17)
        cy = abs(rng.normal(0, h * 0.2)) + h * 0.14
        r = rng.uniform(0.09, 0.18) * w * (1 - abs(cx - w / 2) / w)
        d += np.exp(-(((x - cx) / r) ** 2 + ((y - cy) / (r * 0.7)) ** 2))
    d = 1 - np.exp(-0.75 * d)         # overlapping puffs saturate instead of showing their seams
    d *= np.clip(1 - np.abs(x - w / 2) / (w / 2), 0, 1) ** 0.5 * np.clip(1 - y / h, 0, 1) ** 0.7
    arr = np.zeros((h, w, 4))
    arr[..., 0], arr[..., 1], arr[..., 2] = 0.94, 0.97, 1.0
    arr[..., 3] = np.clip(d * 0.85, 0, 1)
    save_png(arr, path)


def main():
    o = args()
    groups, r0 = table(o)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    for g, noz in groups.items():
        ob = build(g, noz, r0)
        export_fbx(ob, os.path.join(o["out"], "models_X", "vehicles", ob.name + ".fbx"))
        print(f"jets: {ob.name} {len(noz)} cones")
    jet_texture(os.path.join(o["out"], "textures", "MinidoracatTesla", "Jet.png"))
    fog_texture(os.path.join(o["out"], "textures", "MinidoracatTesla", "JetFog.png"))


main()
