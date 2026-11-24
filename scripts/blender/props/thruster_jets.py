"""TeslaThruster's jets (part TeslaThruster, models Lift / Side / Rear; roadster2.md): one static mesh per group in
the body's frame (part model offset 0, as armor.py), per nozzle two open cones: a thin bright core (uv v 0..1) and a
wider faint sheath (v 2..3). Shader MinidoracatTesla_jet draws them procedurally (no texture: it runs as a vehicle
shader for the time uniform, and that path binds the car's skin, shaders/MinidoracatTesla_jet.frag).
Also writes the landing fog's mounds MinidoracatTesla/JetFog1..4 (tall, tall in another shape, mid, low) and the
ground glow JetGlow (client ThrusterFx.lua; not under Vehicles/: verify_local reads those as car skins).

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
# Per group: direction (mesh frame; side: outward by the nozzle's x), length (metres), far-end radius of the core and of
# the sheath, the core's share of the length. Narrow at the nozzle, the sheath opening wider than a wheel where the lift
# columns reach the ground from about 3 m, a soft white plume spreading into fog (f2-kickflip-replay 11m27); the boost
# jets are short and merged into one bundle a side (four side by side read as a comb, r2fx-sp-8; thrust-060 17m27).
SHAPE = {"lift": ((0, 0, -1), 4.0, 0.14, 0.60, 0.7), "side": (None, 1.2, 0.05, 0.24, 0.7),
         "rear": ((0, -1, 0), 1.6, 0.16, 0.50, 0.7)}
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


def cone(p0, d, length, r0, r1, v0=0.0):
    """Open tube from p0 along unit d: verts, quads (outward), uv per quad corner (u along, v around from v0)."""
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
            uvs.append([(i / RINGS, v0 + j / SIDES), (i / RINGS, v0 + (j + 1) / SIDES),
                        ((i + 1) / RINGS, v0 + (j + 1) / SIDES), ((i + 1) / RINGS, v0 + j / SIDES)])
    return verts, quads, uvs


def build(group, nozzles, r0):
    d0, length, r_core, r_sheath, core = SHAPE[group]
    if group == "rear" and len(nozzles) > 2:   # one bundle a side, as wide at the nozzle as the pair it covers
        sides = [[p for p in nozzles if p[0] < 0], [p for p in nozzles if p[0] >= 0]]
        r0 += max(abs(s[0][0] - s[-1][0]) for s in sides) / 2
        nozzles = [np.mean(s, axis=0) for s in sides]
    V, Q, U = [], [], []
    for p in nozzles:
        d = d0 or (float(np.sign(p[0])), 0.0, 0.0)
        for v, q, u in (cone(p, d, length * core * K, r0 * 0.8, r_core * K),
                        cone(p, d, length * K, r0 * 1.3, r_sheath * K, 2.0)):
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


def value_noise(h, w, cells, rng):
    """Smooth noise 0..1: random cells x cells grid, bicubic-ish (smoothstep) upsampled to h x w."""
    g = rng.random((cells + 1, cells + 1))
    y, x = np.meshgrid(np.linspace(0, cells, h, endpoint=False), np.linspace(0, cells, w, endpoint=False), indexing="ij")
    i, j = y.astype(int), x.astype(int)
    fy, fx = y - i, x - j
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    top = g[i, j] * (1 - fx) + g[i, j + 1] * fx
    bot = g[i + 1, j] * (1 - fx) + g[i + 1, j + 1] * fx
    return top * (1 - fy) + bot * fy


def mound_texture(path, w, h, seed, shift=0.0, expo=2.2, soft=0.6):
    """One mound of landing fog (IsoMarkers: bottom centre on its tile, its own size, no scaling;
    IsoSprite.renderTextureWithDepth): dense, piled higher in the middle, built from soft round lobes summed into a
    density with no threshold, so the outline is soft and uneven, neither the hard-edged cumulus of r2fx-sp-6b nor the
    thin strips of r2fx-sp-7. The bottom rows thin out with noise so no cut line shows. Lit from above: white top,
    slightly blue-grey underside (official fog is white with a cold tint, f1-ramp 07m18.5). The crest stands `shift`
    (of the half width) off centre and is broad and round (`expo`, `soft`): every mound peaking in its middle stacked
    into a pointed tree with even steps (r2fx-sp-11); a marker cannot move off its tile, so the offset is drawn in."""
    rng = np.random.default_rng(seed)
    y, x = np.meshgrid(np.arange(h) + 0.5, np.arange(w) + 0.5, indexing="ij")   # y up from the bottom row
    d, hi = np.zeros((h, w)), np.zeros((h, w))
    for count, (r_lo, r_hi) in ((5, (0.07, 0.10)), (70, (0.04, 0.09))):   # a few core lobes, many billows
        for _ in range(count):
            cx = rng.uniform(0.12, 0.88) * w
            xn = (2 * cx / w - 1 - shift) / (0.88 + abs(shift))
            top = h * (0.12 + 0.83 * max(0.0, 1 - abs(xn) ** expo) ** soft * rng.uniform(0.7, 1.0))
            r = min(rng.uniform(r_lo, r_hi) * (w + h), cx - 6, w - cx - 6, 0.5 * top)
            if r < 3:
                continue
            cy = top - r - rng.random() ** 1.5 * max(0.0, top - 2 * r)   # most at the surface, so the outline is lumpy
            q = ((x - cx) / (1.15 * r)) ** 2 + ((y - cy) / r) ** 2
            d += np.exp(-q ** 1.4)
            # each billow lit on its upper side, a soft crease under it, so the lumps read through the dense mass
            hi = np.maximum(hi, np.exp(-1.6 * q) * np.clip(0.45 + 0.65 * (y - cy) / r, 0, 1))
    n = 0.55 * value_noise(h, w, 5, rng) + 0.45 * value_noise(h, w, 12, rng)
    a = np.clip(1 - np.exp(-1.3 * d * (0.6 + 0.8 * n)) - 0.1, 0, 1) / 0.9
    # an uneven, rounded base fading over 18%: a straight bright base read as tiers where mounds on nearer tiles
    # overlap (r2fx-sp-10); the base is lit too, so no dark crease shows there
    base = h * (0.12 * value_noise(1, w, 6, rng)[0] + 0.25 * np.abs(2 * x / w - 1) ** 3)
    a *= np.clip((y - base) / (0.18 * h), 0, 1) * np.clip(np.minimum(x, w - x) / (0.06 * w), 0, 1)
    shade = np.clip(0.2 + 0.8 * hi + 0.1 * y / h + 0.2 * (n - 0.5), 0, 1)
    shade += (1 - shade) * 0.6 * np.clip(1 - (y - base) / (0.35 * h), 0, 1)
    arr = np.zeros((h, w, 4))
    for k, (lo, top_c) in enumerate(((0.62, 0.97), (0.70, 0.99), (0.78, 1.0))):
        arr[..., k] = lo + (top_c - lo) * shade
    arr[..., 3] = a * 0.92
    save_png(arr, path)


def glow_texture(path):
    """Ground glow under the jets at take-off: a 2:1 ellipse (a disc on the iso ground), white centre to cyan, fading
    to nothing at the edge. Stands on the tile 2 down-right of the car (ThrusterFx.lua) so its middle lands under the
    car."""
    h, w = 256, 512
    y, x = np.meshgrid((np.arange(h) + 0.5) / h * 2 - 1, (np.arange(w) + 0.5) / w * 2 - 1, indexing="ij")
    r2 = np.clip(x * x + y * y, 0, 1)
    g = (1 - r2) ** 2.5
    arr = np.zeros((h, w, 4))
    for k, c in enumerate((0.30, 0.85, 1.0)):
        arr[..., k] = c + (1 - c) * g ** 2
    arr[..., 3] = g * 0.85
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
    tex = os.path.join(o["out"], "textures", "MinidoracatTesla")
    # official touch-down fog (f1-ramp 07m18.5): about 3-4 car heights tall, 2.8 car lengths wide, dense core 1.6;
    # here the car's roof stands ~110 px over its tile at the default zoom, its length ~240 px across the screen.
    # (w, h), crest offset, roundness: tall, tall (other shape), mid, low, wide low (the flanks)
    for k, ((w, h), shift, expo, soft) in enumerate((((460, 280), -0.12, 2.2, 0.5), ((440, 260), 0.15, 2.2, 0.5),
                                                     ((420, 190), 0.10, 2.0, 0.6), ((416, 130), -0.05, 1.5, 0.7),
                                                     ((520, 150), -0.10, 2.5, 0.6)), 1):
        mound_texture(os.path.join(tex, f"JetFog{k}.png"), w, h, 30 + k, shift, expo, soft)
    glow_texture(os.path.join(tex, "JetGlow.png"))


main()
