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
    # the tail corners rounder (official FRONT34 / REAR34 / SIDE through the camcheck cameras, fit to the three tail
    # outlines: ours 4-5 cm too far out at the 40-46 deg corner, 1.5-2 cm long at the near rear 17 deg): evaluated on
    # the points the terms above moved. Each point moves toward the corner centre (|x| xc, u uc; u metres forward of
    # the tail-most point `tail`) by a(h) x sin^2(2 phi) (phi from straight back, 0 / 90 deg = the rear face / the
    # side, so the length and the width stay), none within r[0] of the centre; the rear face (u under u[0], fading by
    # u[1]) forward by du(h) (0 at the tail-most point's height `hu[2]`: the length stays); Catmull-Rom between knots
    corner=dict(xc=0.40, uc=0.80, tail=-2.5293, r=(0.10, 0.22), hcut=(0.03, 0.10, 1.25, 1.40),
                gate=dict(x=(0.68, 0.80), h=(0.52, 0.60, 0.80, 0.95)),
                h=(0.20, 0.32, 0.45, 0.60, 0.75, 0.90, 1.05, 1.20),
                a=(0.0, 0.045, 0.042, 0.026, 0.030, 0.033, 0.044, 0.032),
                hu=(0.15, 0.30, 0.42, 0.60, 0.75, 0.90, 1.05, 1.20),
                du=(0.0, -0.007, 0.0, 0.017, 0.007, 0.011, -0.003, -0.002), u=(0.35, 0.70)),
)
# after the decimation (cars/model_s.py POST_FIELD -> post()): what the decimation sees stays the field's above, so
# these do not re-run its collapse order (a waist term in FIELD moved which edge pairs collapse; the symmetric collapse
# then tore the left rear door's skin open, models-model-s.md). Metres on the field's output.
POST = dict(
    # the door sides in (official door seams triangulated SIDE + FRONT34 and SIDE + REAR34, epipolar, and the handles,
    # tri8 points, through the camcheck cameras: the B pillar seam h 0.42-0.90 +2.2 / +1.8-2.1 cm inboard of ours, the
    # handles +1.8-2.4; ahead of the front doors (A seam, side repeater) the two pairs disagree, so none there; the
    # mirrors stay): |x| in by d, full over y[1..2] (y[0..1] / y[2..3] ramps; under the rear arch's top, h under
    # hr[0], the rear ramp is yl: the rear door's lower rear corner and the flare stay, so does the widest point over
    # the rear fenders) and h (h[1..2]; ramps h[0..1], h[2..3]: under the belt, the glass stays), only the skin (|x|
    # over ax: the door inner trims stay)
    waist=dict(d=0.022, y=(-1.36, -1.14, 0.15, 0.40), yl=(-0.80, -0.55), hr=(0.74, 0.84), h=(0.30, 0.42, 0.92, 0.99),
               ax=(0.84, 0.88)),
    # the mirrors' outer ends in by d over |x| x (only they stand past the body's 0.9935): the decimation that holds
    # open edges kept their tips (width over the mirrors 2,190.4, manual 2,189)
    mirror=dict(d=0.0007, x=(1.00, 1.09)),
)


def s(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def cr(x, xs, ys):
    """Catmull-Rom through (xs, ys) (end slopes one-sided), flat outside."""
    xs, ys = np.asarray(xs, float), np.asarray(ys, float)
    m = np.gradient(ys, xs)
    i = np.clip(np.searchsorted(xs, x) - 1, 0, len(xs) - 2)
    h = xs[i + 1] - xs[i]
    t = np.clip((x - xs[i]) / h, 0, 1)
    t2, t3 = t * t, t * t * t
    return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1]
            + (t3 - t2) * h * m[i + 1])


def corner(x, y, h):
    """FIELD corner on metres (already moved by the other terms) -> (dx, dy) metres."""
    c = FIELD["corner"]
    u = y - c["tail"]
    ox, ou = np.abs(x) - c["xc"], c["uc"] - u
    r = np.hypot(ox, ou)
    phi = np.arctan2(ox, ou)
    w = np.where((phi > 0) & (phi < np.pi / 2), np.sin(2 * phi) ** 2, 0.0)
    hc = c["hcut"]
    d = cr(h, c["h"], c["a"]) * w * s(r, *c["r"]) * s(h, hc[0], hc[1]) * (1 - s(h, hc[2], hc[3]))
    g = c["gate"]                      # not on the liftgate's lower half: its skin and lining part at the corners
    d = d * (1 - (1 - s(np.abs(x), *g["x"])) * s(h, *g["h"][:2]) * (1 - s(h, *g["h"][2:])))
    rr = np.maximum(r, 1e-9)
    return -np.sign(x) * d * ox / rr, d * ou / rr + cr(h, c["hu"], c["du"]) * (1 - s(u, *c["u"]))


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
    cx, cy = corner(x + dx, y + dy, h + dz)
    return np.stack([dx + cx, dy + cy, dz], 1) * K


def moved_plane(p, n):
    """A cut plane (point p, normal n; pre-centre grid) through the field and POST: the point moved, the normal by the
    Jacobian's inverse transpose there (the planes that stand in the tail's corner term turn with it)."""
    q = np.array([p], float)
    J = jacobian(q + field(q), fn=post_field)[0] @ jacobian(q)[0]
    m = np.linalg.inv(J).T @ np.asarray(n, float)
    return moved(*p), tuple(round(float(v), 4) for v in m / np.linalg.norm(m))


def moved(x, y, z, post=True):
    """One source pre-centre grid point through the field and (post) POST (cars/model_s.py's positions; post False:
    what the build reads before the decimation, the DROP boxes)."""
    p = np.array([[x, y, z]], float)
    p = p + field(p)
    if post:
        p = p + post_field(p)
    return tuple(round(float(v), 4) for v in p[0])


def jacobian(p, E=1e-4, fn=field):
    """d(p + fn(p)) / dp per point (n, 3, 3), central differences."""
    J = np.zeros((len(p), 3, 3))
    for j in range(3):
        e = np.zeros(3)
        e[j] = E
        J[:, :, j] = (fn(p + e) - fn(p - e)) / (2 * E)
    return J + np.eye(3)


def post_field(p):
    """POST (waist, mirror) on grid points (n, 3) of the decimated mesh (through field() already) -> displacement,
    grid units."""
    wa = POST["waist"]
    x, y, h = p[:, 0] / K, p[:, 1] / K, p[:, 2] / K
    t = s(h, *wa["hr"])                # the rear ramp: yl under the arch's top, y over it
    yr = s(y, *(lo + t * (hi - lo) for lo, hi in zip(wa["yl"], wa["y"][:2])))
    d = wa["d"] * yr * (1 - s(y, *wa["y"][2:])) * s(h, *wa["h"][:2]) * (1 - s(h, *wa["h"][2:])) \
        * s(np.abs(x), *wa["ax"])
    d = d + POST["mirror"]["d"] * s(np.abs(x), *POST["mirror"]["x"])
    return np.stack([-np.sign(x) * d, 0 * d, 0 * d], 1) * K


def post(o):
    """cars/model_s.py POST_FIELD (convert.py load_source, each object after its decimation; mesh in the pre-centre
    grid): post_field() on the points, the corner normals by its Jacobian's inverse transpose."""
    me = o.data
    g = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", g)
    g = g.reshape(-1, 3)
    lv = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", lv)
    cn = np.empty(len(me.loops) * 3, np.float32)
    me.attributes["custom_normal"].data.foreach_get("vector", cn)
    n = np.einsum("lij,li->lj", np.linalg.inv(jacobian(g, fn=post_field))[lv], cn.reshape(-1, 3))
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    me.vertices.foreach_set("co", (g + post_field(g)).ravel())
    me.attributes["custom_normal"].data.foreach_set("vector", n.astype(np.float32).ravel())
    me.update()


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
