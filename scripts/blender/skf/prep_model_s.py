"""Model S Plaid source prep, run once before convert.py (CAR=model_s): ValentunW's (Lals) "Tesla Model S Plaid"
glTF (Sketchfab, CC BY 4.0; CREDITS.md) -> the same glTF moved by one continuous displacement field (as
prep_model_y.py: no cuts, every object and component keeps its triangles; normals by the field's Jacobian, inverse
transpose).
    "$B" -b --factory-startup --python scripts/blender/skf/prep_model_s.py            -> TMP/src/source/model_s.glb
    "$B" -b --factory-startup --python scripts/blender/skf/prep_model_s.py -- dump <out.npz>   (source points, no field)
    python scripts/blender/skf/prep_model_s.py map < points    (no Blender: "name x y z" pre-centre grid -> moved)
Frame: convert.py's pre-centre grid (+y front, +z up, -x the car's left, ground z 0; cars/model_s.py SRC_C, SRC_SCALE,
SRC_Z); the field itself works in metres: y_m = y / K, h = z / K, ax = |x| / K. Numbers and the same-camera
comparison: .claude/skills/tesla-dev/references/models-model-s.md.
"""
import os
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "temp", "skf_ms", "src", "source")
SRC = os.path.join(SRC_DIR, "tesla_model_s_plaid.glb")
OUT = os.path.join(SRC_DIR, "model_s.glb")
K = 0.826                                   # pzveh.K: grid per metre


def car_cfg():
    """cars/model_s.py's CAR (SRC_C, SRC_SCALE, SRC_Z: the source -> pre-centre grid frame)."""
    import runpy
    return runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "cars", "model_s.py"))["CAR"]


def frame():
    """convert.py src_frame() for this car (SRC_FLIP False): 4x4 source world -> pre-centre grid."""
    c = car_cfg()
    s = K * c["SRC_SCALE"]
    return np.array(((0, s, 0, -s * c["SRC_C"][1]), (-s, 0, 0, s * c["SRC_C"][0]), (0, 0, s, -s * c["SRC_Z"]),
                     (0, 0, 0, 1)))


# the field, metres (y forward of the source's centre, h over the ground, ax = |x|). Source landmarks (after the
# config's SRC_*): nose y 2.523, tail -2.523 (5,046 long), front axle y 1.5536, rear -1.4153 (the TIRE centres),
# widest 1,997 over the rear fenders (y -1.4, h 0.75), roof glass top 1.456, lowest body point between the axles
# 0.117 (the spats ahead of the rear tyres) / 0.138 (the floor)
FA, RA, WH = 1.5536, -1.4153, 0.352         # front / rear axle y, the source's wheel centre height (m)
FIELD = dict(
    width=1.987 / 1.997,            # manual width w/o mirrors over the source's 1,997 (the rear fenders): about x 0
    # the body (not the wheels) down: L(h) = lo + (hi - lo) x s(h over h): official SIDE through camera A had the
    # sills 16-20 mm high, handles / side cameras / arch tops 20-28, the belt 24-40, the roof 23-32 (height +31; the
    # tyre re-seat in the config takes 5 mm of it)
    lower=dict(lo=0.011, hi=0.026, h=(0.20, 1.45)),
    # between the axles the floor stays at the manual's clearance (126): under h[1] the drop blends into a rise of
    # `up` at h[0] (the spats ahead of the rear tyres, 117 in the source), weighted over y (none at the wheels)
    floor=dict(h=(0.115, 0.160), up=0.009, y=(RA + 0.22, RA + 0.30, FA - 0.30, FA - 0.22)),
    # the overhangs (manual 963 / 1,123, wheelbase 2,960; the source 969.3 / 1,107.7 / 2,968.8 with the length right):
    # the nose back `nose` ahead of y[0..1], the tail back `tail` behind y[0..1], the rear wheel's arch forward
    # `arch` within r[0] of its centre (none past r[1])
    nose=dict(d=0.0063, y=(2.02, 2.20)),
    tail=dict(d=0.0063, y=(-2.20, -2.02)),
    arch=dict(d=0.009, r=(0.47, 0.62)),
    # the rear bumper's lower edge (official SIDE through camera A: 4-5 px, 16-20 mm, high from the rear arch back, its
    # rear end 5 px short at the bottom): down `dz` behind y[0..1] under h (fading out upward), back `dy` behind
    # yb[0..1] under hb
    diffuser=dict(dz=0.018, y=(-1.92, -1.80), h=(0.22, 0.40), dy=0.020, yb=(-2.45, -2.30), hb=(0.22, 0.32)),
    # the spats ahead of the front tyres (black trim, 123 mm in the source): official SIDE's bottom there 5 px (20 mm)
    # higher: up `up` under h[0], fading out by h[1], over y (ramps in and out)
    spat=dict(up=0.020, h=(0.12, 0.16), y=(1.84, 1.90, 2.08, 2.14)),
)


def s(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def field(p):
    """Grid points (n, 3) -> displacement (n, 3), grid units."""
    f = FIELD
    x, y, h = p[:, 0] / K, p[:, 1] / K, p[:, 2] / K
    lw, fl = f["lower"], f["floor"]
    drop = -(lw["lo"] + (lw["hi"] - lw["lo"]) * s(h, *lw["h"]))
    w = s(h, *fl["h"][:2])
    b = s(y, fl["y"][0], fl["y"][1]) * (1 - s(y, fl["y"][2], fl["y"][3]))
    dz = drop + b * (1 - w) * (fl["up"] - drop)
    dy = -f["nose"]["d"] * s(y, *f["nose"]["y"]) - f["tail"]["d"] * (1 - s(y, *f["tail"]["y"])) \
        + f["arch"]["d"] * (1 - s(np.hypot(y - RA, h - WH), *f["arch"]["r"]))
    sp = f["spat"]
    dz = dz + sp["up"] * (1 - s(h, *sp["h"])) * s(y, *sp["y"][:2]) * (1 - s(y, *sp["y"][2:]))
    df = f["diffuser"]
    dz = dz - df["dz"] * (1 - s(y, *df["y"])) * (1 - s(h, *df["h"]))
    dy = dy - df["dy"] * (1 - s(y, *df["yb"])) * (1 - s(h, *df["hb"]))
    dx = x * (f["width"] - 1)
    return np.stack([dx, dy, dz], 1) * K


def moved(x, y, z):
    """One source pre-centre grid point through the field (cars/model_s.py's positions)."""
    p = np.array([[x, y, z]], float)
    return tuple(round(float(v), 4) for v in (p + field(p))[0])


def jacobian(p, E=1e-4):
    """d(p + field(p)) / dp per point (n, 3, 3), central differences."""
    J = np.zeros((len(p), 3, 3))
    for j in range(3):
        e = np.zeros(3)
        e[j] = E
        J[:, :, j] = (field(p + e) - field(p - e)) / (2 * E)
    return J + np.eye(3)


def map_points():
    for line in sys.stdin:
        w = line.split()
        if len(w) < 4:
            continue
        g = np.array([[float(x) for x in w[1:4]]])
        n = g[0] + field(g)[0]
        print("%-12s (%.4f, %.4f, %.4f) -> (%.4f, %.4f, %.4f)  d %+.4f %+.4f %+.4f" % (w[0], *g[0], *n, *(n - g[0])))


def load():
    """The glTF into an empty scene, meshes unparented, each mesh's points in its world frame (object matrix applied,
    so mesh = world: the exporter writes what the importer gave)."""
    import bpy
    from mathutils import Matrix
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in obs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix()
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    return obs


def main():
    import bpy
    obs = load()
    P = frame()
    Pi = np.linalg.inv(P)
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if args[:1] == ["dump"]:
        pts = {}
        for o in obs:
            w = np.array([v.co[:] for v in o.data.vertices])
            pts[o.name] = w @ P[:3, :3].T + P[:3, 3]
        np.savez(args[1], **pts)
        print("PREP dump", args[1], len(pts), "objects")
        return
    moved = 0.0
    for o in obs:
        me = o.data
        w = np.array([v.co[:] for v in me.vertices])
        g = w @ P[:3, :3].T + P[:3, 3]
        d = field(g)
        J = Pi[:3, :3] @ jacobian(g) @ P[:3, :3]          # in the source frame
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.corner_normals.foreach_get("vector", cn)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        n = np.einsum("lij,li->lj", np.linalg.inv(J)[lv], cn.reshape(-1, 3))   # n' = J^-T n (row vector n J^-1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        me.vertices.foreach_set("co", ((g + d) @ Pi[:3, :3].T + Pi[:3, 3]).ravel())
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", n.astype(np.float32).ravel())
        me.update()
        moved = max(moved, float(np.abs(d).max()) if len(d) else 0.0)
    print("PREP field max %.4f grid" % moved)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_normals=True,
                              export_tangents=False, export_materials="EXPORT", export_apply=False,
                              export_yup=True, export_texcoords=True)
    print("PREP ->", OUT)


if __name__ == "__main__":
    if sys.argv[1:2] == ["map"]:
        map_points()
    else:
        main()
