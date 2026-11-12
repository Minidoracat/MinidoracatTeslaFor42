"""Model 3 Performance source prep, run once before convert.py (CAR=model_3): RBLXSupercars' "2024 Tesla Model 3"
glTF (Sketchfab, CC BY 4.0; CREDITS.md) -> model_3.obj, the car at the owner's manual's size (US manual 2025-10
PDF p.215, Performance: length 4,724, width 1,850 without mirrors, height 1,431, wheelbase 2,875, front overhang 872,
rear 978, track 1,582 / 1,560) and on the official design-studio SIDE render through the fitted camera
(temp/fit-1112/m3, camera c2), by one continuous displacement field: no cuts, every source object keeps its
triangles (the config's (object, triangles) keys follow the decimation: the build's COMPS lines).
Against the source (grid frame below; metres): length 4,724, width 1,852, height 1,413, wheelbase 2,876, front
overhang 879, rear 969, sill bottom 106 over the ground:
- width scaled about the centre line onto FIELD width (the tyres keep their places);
- the body back `shift` against the wheels (SIDE: A seam, door handles, side camera, arches, tail lamp 8-16 mm ahead
  of the official), the nose's profile onto the official's (`nose`: the hood's leading edge forward, the bumper's
  middle back) and the tail's (`tail`), each end then put on the manual's overhang (the extreme point);
- the body up against the wheels (`lift`, by height: the sill 12 mm low on the official SIDE, the arches 4 mm, the
  belt on it), the glasshouse stretched up to the roof (`roof`, by y: 16-24 mm low), the hood's top a little
  (`hood`), the trunk lid's trailing edge back and up onto the official's spoiler (`spoiler`);
- the tyres (Object_19: convert.py only measures them, for the wheels' centres and outer faces) moved whole: the rear
  axle onto the wheelbase, each axle's outer faces so the track comes out at FIELD track with the config's
  TIRE_AXLES widths and WHEEL_INSET (pzveh geometry: centre |x| = outer - width / 2 - inset).
Normals: each corner's by the field's Jacobian, inverse transpose (finite differences).
Frame: convert.py's pre-centre grid (src_frame: +Y front, +Z up, -X car left, ground z 0); the field works in metres
of it (X, Y, Z = grid / K). The OBJ keeps the glTF importer's world axes (cars/model_3.py SRC_FLIP, SRC_C, SRC_SCALE
as for the glb).
    "$B" -b --factory-startup --python scripts/blender/skf/prep_model_3.py [-- <src.glb> <out.obj>]
    "$B" -b --factory-startup --python scripts/blender/skf/prep_model_3.py -- map <points.txt>
        lines "name x y z" (pre-centre grid, the config's frame) -> the same points through the field (body)
"""
import os
import runpy
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "temp", "skf_m3", "src", "source")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
MAP = args[1] if args[:1] == ["map"] else None
if MAP:
    args = []
SRC, OUT = (args + [os.path.join(SRC_DIR, "2024_tesla_model_3.glb"), os.path.join(SRC_DIR, "model_3.obj")][len(args):])[:2]
CFG = runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "cars", "model_3.py"))["CAR"]
K = 0.826                                   # pzveh.K: grid per metre
TYRES = "Object_19"                         # moved whole (cars/model_3.py TIRE_OBJ)
NOT_BODY = ("Object_19", "Object_15")       # tyres, rims (convert.py DROP: neither in the width nor moved by it)
MIRRORS = (0.70, 1.00)                      # m: the mirrors' (|x| over, z over) -- not in the top line
WIDTH_OBJ = "Object_11"                     # the paint shell: the widest kept part (rear arch shoulder, |x| 0.926 m);
#                                             other objects hold the source rims' 45 cm rings (convert.py DROP_COMPS)
# the field (metres). Source landmarks: front axle y 1.4831, rear -1.3923, nose 2.362 (z 0.544), tail -2.362
# (z 0.547), sill bottom 0.106, roof 1.4125 (y -0.5), the belt (window foot) 0.95, the trunk lid's trailing edge
# y -2.29 z 1.03. Calibration knobs, fitted on the official SIDE through camfit's c2 camera
FIELD = dict(
    width=1.850,                    # without mirrors (US manual; CN 1,848)
    wheelbase=2.875,
    front=0.872,                    # overhangs to the extreme points (the manual's)
    rear=0.978,
    track=(1.582, 1.560),           # wheel centres
    shift=-0.010,                   # the whole body back (the ends then onto the overhangs)
    # the nose's profile: y offsets by height (z, dy), full ahead of y nose_y[1], none behind nose_y[0]; then the
    # whole nose (that same weight) moved so the extreme lands on `front`
    nose_y=(1.80, 2.10),
    nose=((0.14, 0.006), (0.20, -0.002), (0.26, -0.012), (0.30, -0.016), (0.45, -0.016), (0.52, -0.012), (0.58, 0.004), (0.63, 0.012),
          (0.72, 0.010), (0.80, 0.013), (0.90, 0.016)),
    tail_y=(-1.95, -2.20),          # the tail's weight (behind -tail_y), its extreme onto `rear`
    tail=((0.30, 0.0), (0.50, 0.0)),
    # up by height (z, dz), everywhere on the body below the belt; above it the glasshouse stretched: `roof` (y, dz)
    # at the body's top line, lift(belt) at the belt
    lift=((0.08, 0.0125), (0.20, 0.007), (0.33, 0.003), (0.66, 0.006), (0.95, 0.0015)),
    # the sill between the axles another `d` (z, d) knots, full over y `mid` (inner), none past the outer pair: the
    # official SIDE has the sill 12 mm over the source's (lift), the manual's ground clearance 128 mm 22 mm over it
    # (the source has no underbody: the sill is the car's lowest point); the bumpers stay on the official SIDE
    sill=dict(z=((0.08, 0.009), (0.33, 0.0)), mid=(-1.05, -0.90, 1.00, 1.15)),
    belt=0.95,
    roof=((-2.30, 0.020), (-1.37, 0.020), (-0.97, 0.019), (-0.57, 0.0185), (-0.16, 0.016), (0.24, 0.013),
          (0.64, 0.016), (0.84, 0.016), (1.04, 0.012), (1.24, 0.004), (1.44, 0.0)),
    hood=dict(y=(1.45, 1.70, 2.25), z=(0.60, 0.80), d=0.005),   # up d x a bump over y x s(z)
    # the glasshouse forward d x the roof stretch's weight, full ahead of y[1], none behind y[0]: the official
    # windscreen and its header sit 16-24 mm ahead of the source's
    rake=dict(y=(-0.60, 0.0), d=0.020),
    # the trunk lid's trailing edge (the carbon spoiler): back d[0], up d[1] x s over -y (te[0] -> te[1]) x s(z),
    # fading out towards the spoiler's ends over |x| (else the tail lamps' tops and the lid's side seams shear)
    spoiler=dict(y=(-2.05, -2.29), z=(0.92, 1.00), x=(0.40, 0.60), d=(0.034, 0.012)),
    # then, where each point lands (metres of the output: these were fitted on it, official SIDE rows through the c2
    # camera): `low_nose` the bumper's old lip tip back (dy by height, weight over y) behind LIP's blade, which it
    # poked 3-4 px ahead of the official lip's underside; `tail_low` the diffuser's foot up (dz by height, weight over
    # -y), 2-3 px low under the tail; `tail_corner` its rear corner reshaped (dy by |x| in a height band `z` (in,
    # full, full, out), weight over -y): the source's corner bulged 5 px out at row 636 and fell 4 px short at 640
    low_nose=dict(y=(1.80, 2.10), z=((0.17, 0.0), (0.20, -0.012), (0.23, 0.0))),
    tail_low=dict(y=(1.80, 2.00), z=((0.16, 0.011), (0.25, 0.0))),
    tail_corner=dict(y=(1.95, 2.15), z=(0.18, 0.20, 0.25, 0.27), x=((0.40, 0.0), (0.50, 0.012), (0.58, 0.0), (0.66, -0.018))),
)
# the Performance front's black splitter blade (grid, pre-centre; official SIDE through the c2 camera): the source's
# lip tip sat 4-5 px low and its underside 1-2 px high. A wedge per station along the old tip's plan line (`tip`: |x|,
# y, read off the prepped bumper), from the bumper face at `root` z (a ray from ahead, `inset` in) to the tip at `zt`
# (by |x|) and back under to `back` behind the tip at `zb`; built after the field, so the nose's extreme (cn) ignores it
LIP = dict(name="Lip_M3", span=0.72, n=61, root=0.185, inset=0.004,
           tip=((0.0, 1.945), (0.1, 1.942), (0.2, 1.932), (0.3, 1.917), (0.35, 1.895), (0.4, 1.88), (0.45, 1.855),
                (0.5, 1.828), (0.55, 1.80), (0.6, 1.75), (0.65, 1.712), (0.7, 1.65)),
           zt=((0.0, 0.192), (0.35, 0.192), (0.70, 0.165)),
           back=((0.0, 0.04), (0.45, 0.045), (0.55, 0.03), (0.72, 0.04)),
           zb=((0.0, 0.134), (0.45, 0.135), (0.55, 0.133), (0.65, 0.126), (0.72, 0.115)))
# the rear diffuser's ledge (grid; official SIDE rows 620-628, REAR34's lit step across the black): a box strip `d`
# behind the diffuser's rear face (a ray from behind at the band's middle), `inset` into it, z `band`, |x| <= span
FIN = dict(name="Fin_M3", span=0.42, n=43, band=(0.215, 0.236), d=0.025, inset=0.01)
MAT_BLACK = "Georimblurlfsub01Mtl"            # cars/model_3.py MAT_RGB: the source's black trim


def s(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def smooth(u, knots):
    """Through the knots ((u, value) rows, u ascending), a smoothstep each span; flat past the ends."""
    x, v = np.array(knots).T
    i = np.clip(np.searchsorted(x, u) - 1, 0, len(x) - 2)
    return v[i] + (v[i + 1] - v[i]) * s(u, x[i], x[i + 1])


def frame():
    """convert.py src_frame() for this config: Blender world (glTF import) -> pre-centre grid, 3x4."""
    sc = K * CFG["SRC_SCALE"] * (-1 if CFG["SRC_FLIP"] else 1)
    c = CFG["SRC_C"]
    return np.array([(0, sc, 0, -sc * c[1]), (-sc, 0, 0, sc * c[0]), (0, 0, K * CFG["SRC_SCALE"], 0)])


class Field:
    """Source landmarks (metres) -> the displacement of body points (grid in, grid out)."""

    def __init__(self, body, tyres, paint):
        f = FIELD
        low = paint[paint[:, 2] < 0.55 * body[:, 2].max()]
        self.wk = f["width"] / (2 * np.abs(low[:, 0]).max())
        fr = tyres[tyres[:, 1] > 0]
        rr = tyres[tyres[:, 1] <= 0]
        self.yf, self.yr = [(t[:, 1].min() + t[:, 1].max()) / 2 for t in (fr, rr)]
        # the body's top line (max z per 2 cm of y), smoothed: the roof stretch reaches it
        b = np.round(body[:, 1] / 0.02).astype(int)
        top = np.full(b.max() - b.min() + 1, -np.inf)
        np.maximum.at(top, b - b.min(), body[:, 2])
        top = np.convolve(np.pad(top, 3, mode="edge"), np.ones(7) / 7, "valid")
        self.top = (np.arange(len(top)) + b.min()) * 0.02, top
        self.cn = self.ct = 0.0
        q = self.d(body) + body                                     # the ends onto the overhangs
        wn, wt = self.wn(body), self.wt(body)
        self.cn = self.yf + f["front"] - q[wn > 0.999, 1].max()
        self.ct = (self.yr + (self.yf - self.yr - f["wheelbase"])) - f["rear"] - q[wt > 0.999, 1].min()

    def wn(self, p):
        return s(p[:, 1], *FIELD["nose_y"])

    def wt(self, p):
        return s(-p[:, 1], *[-v for v in FIELD["tail_y"]])

    def d(self, p):
        """Metres in, metres out (N x 3)."""
        f = FIELD
        X, Y, Z = p.T
        dX = X * (self.wk - 1)
        wn, wt = self.wn(p), self.wt(p)
        dY = f["shift"] + wn * (smooth(Z, f["nose"]) + self.cn) + wt * (smooth(Z, f["tail"]) + self.ct)
        sp = f["spoiler"]
        wsp = s(-Y, -sp["y"][0], -sp["y"][1]) * s(Z, *sp["z"]) * s(-np.abs(X), -sp["x"][1], -sp["x"][0])
        dY = dY - sp["d"][0] * wsp
        sl = f["sill"]
        base = smooth(np.minimum(Z, f["belt"]), f["lift"]) + smooth(Z, sl["z"]) \
            * s(Y, sl["mid"][0], sl["mid"][1]) * (1 - s(Y, sl["mid"][2], sl["mid"][3]))
        top = np.interp(Y, *self.top)
        k = s((Z - f["belt"]) / np.maximum(top - f["belt"], 0.02), 0, 1)   # 0 at the belt, 1 on the top line
        dZ = base + (smooth(Y, f["roof"]) - smooth(np.array([f["belt"]]), f["lift"])) * k
        dY = dY + f["rake"]["d"] * k * s(Y, *f["rake"]["y"])
        h = f["hood"]
        dZ = dZ + h["d"] * s(Y, h["y"][0], h["y"][1]) * (1 - s(Y, h["y"][1], h["y"][2])) * s(Z, *h["z"])
        dZ = dZ + sp["d"][1] * wsp
        Q = p + np.stack([dX, dY, dZ], 1)                          # the post terms, where the point lands
        ln, tl, tc = f["low_nose"], f["tail_low"], f["tail_corner"]
        dY = dY + s(Q[:, 1], *ln["y"]) * smooth(Q[:, 2], ln["z"]) + s(-Q[:, 1], *tc["y"]) * s(Q[:, 2], *tc["z"][:2]) \
            * (1 - s(Q[:, 2], *tc["z"][2:])) * smooth(np.abs(Q[:, 0]), tc["x"])
        dZ = dZ + s(-Q[:, 1], *tl["y"]) * smooth(Q[:, 2], tl["z"])
        return np.stack([dX, dY, dZ], 1)


def field_grid(fld, g):
    return fld.d(g / K) * K


def move(fld, g):
    """New grid points and the Jacobian (N x 3 x 3) of body points g (grid)."""
    E = 1e-4
    J = np.empty((len(g), 3, 3))
    for j in range(3):
        e = np.zeros(3)
        e[j] = E
        J[:, :, j] = (field_grid(fld, g + e) - field_grid(fld, g - e)) / (2 * E)
    J += np.eye(3)
    return g + field_grid(fld, g), J


def tyre_moves(fld, tyres_by_obj):
    """Per tyre point set (grid) the x / y translation (grid): the rear axle onto the wheelbase, the outer faces so the
    track comes out (TIRE_AXLES widths, WHEEL_INSET)."""
    f = FIELD
    ta, inset = CFG["TIRE_AXLES"], CFG["WHEEL_INSET"]
    out = {}
    for front in (True, False):
        sel = [g for g in tyres_by_obj if (g[:, 1].mean() > 0) == front]
        xo = np.mean([max(-g[:, 0].min(), g[:, 0].max()) for g in sel])
        w = ta["front" if front else "rear"][1] * K
        want = f["track"][0 if front else 1] * K / 2 + w / 2 + inset
        dy = 0.0 if front else (fld.yf - fld.yr - f["wheelbase"]) * K
        for g in sel:
            out[id(g)] = np.array([np.sign(g[:, 0].mean()) * (want - xo), dy, 0.0])
    return out


def load():
    """The glb in Blender: (objects, world points per object, grid points per object)."""
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    F = frame()
    grid = {}
    for o in obs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        o.data.transform(mw)
        o.matrix_world.identity()
        w = np.empty(len(o.data.vertices) * 3)
        o.data.vertices.foreach_get("co", w)
        grid[o] = w.reshape(-1, 3) @ F[:, :3].T + F[:, 3]
    return obs, grid


def landmarks(obs, grid):
    body = np.concatenate([g for o, g in grid.items() if not o.name.startswith(NOT_BODY)]) / K
    body = body[~((np.abs(body[:, 0]) > MIRRORS[0]) & (body[:, 2] > MIRRORS[1]))]
    paint = np.concatenate([g for o, g in grid.items() if o.name.startswith(WIDTH_OBJ)]) / K
    tyres = np.concatenate([g for o, g in grid.items() if o.name.startswith(TYRES)]) / K
    return Field(body, tyres, paint)


def map_points():
    obs, grid = load()
    fld = landmarks(obs, grid)
    for line in open(MAP):
        w = line.split()
        if len(w) < 4 or line.startswith("#"):
            continue
        g = np.array([[float(x) for x in w[1:4]]])
        n = move(fld, g)[0][0]
        print("MAP %-14s (%.4f, %.4f, %.4f) -> (%.4f, %.4f, %.4f)  d %+.4f %+.4f %+.4f" % (w[0], *g[0], *n, *(n - g[0])))


def strips(S):
    """Stations x section points (grid, a convex section each, stations along x) -> faces facing out: a quad per
    section edge and station step (out from the section's centroid), and both end caps."""
    F = []
    m, k = S.shape[:2]
    idx = np.arange(m * k).reshape(m, k)
    c = S.mean(1)
    for i in range(m - 1):
        for j in range(k - 1):                  # open between the last point and the first (inside the body)
            q = [idx[i, j], idx[i, j + 1], idx[i + 1, j + 1], idx[i + 1, j]]
            p = S.reshape(-1, 3)[q]
            out = p.mean(0) - (c[i] + c[i + 1]) / 2
            F.append(q if np.cross(p[1] - p[0], p[2] - p[0]) @ out > 0 else q[::-1])
    for i, sd in ((0, -1), (m - 1, 1)):
        q = list(idx[i])
        p = S[i]
        F.append(q if np.cross(p[1] - p[0], p[2] - p[0])[0] * sd > 0 else q[::-1])
    return S.reshape(-1, 3), F


def lip(bvh, ymax):
    """LIP's wedge (grid): stations x (root on the bumper face, tip, underside)."""
    from mathutils import Vector
    L = LIP
    S = []
    for x in np.linspace(-L["span"], L["span"], L["n"]):
        ax = abs(x)
        yt = min(np.interp(ax, *np.array(L["tip"]).T), ymax - 0.001)     # never the nose's extreme
        hit = bvh.ray_cast(Vector((x, 3.0, L["root"])), Vector((0, -1, 0)))[0]
        yr = hit.y - L["inset"] if hit is not None else yt - 0.03
        S.append([(x, yr, L["root"]), (x, yt, np.interp(ax, *np.array(L["zt"]).T)),
                  (x, yt - np.interp(ax, *np.array(L["back"]).T), np.interp(ax, *np.array(L["zb"]).T))])
    return strips(np.array(S))


def fin(bvh, ymin):
    """FIN's strip (grid): stations x (front top, rear top, rear bottom, front bottom); never past the tail's extreme
    ymin (the rear overhang is the body's)."""
    from mathutils import Vector
    f = FIN
    lo, hi = f["band"]
    S = []
    for x in np.linspace(-f["span"], f["span"], f["n"]):
        hit = bvh.ray_cast(Vector((x, -3.0, (lo + hi) / 2)), Vector((0, 1, 0)))[0]
        if hit is None:
            raise SystemExit(f"FIN: no diffuser ahead of x {x:.3f}")
        y = hit.y
        r = max(y - f["d"], ymin + 0.001)
        S.append([(x, y + f["inset"], hi), (x, r, hi), (x, r, lo), (x, y + f["inset"], lo)])
    return strips(np.array(S))


def main():
    import bpy
    obs, grid = load()
    fld = landmarks(obs, grid)
    F = frame()
    A, b = F[:, :3], F[:, 3]
    Ai = np.linalg.inv(A)
    R = A / np.linalg.norm(A[0])                       # rotation (uniform scale)
    tyre_obs = [o for o in obs if o.name.startswith(TYRES)]
    flips = 0
    moved = {}
    # the tyre object holds all four: split by side and axle (convert.py tire_groups)
    for o in obs:
        me = o.data
        g = grid[o]
        if o.name.startswith(NOT_BODY):
            q, J = g.copy(), np.broadcast_to(np.eye(3), (len(g), 3, 3)).copy()
            if o in tyre_obs:
                parts = [(g[:, 0] < 0) & (g[:, 1] > 0), (g[:, 0] >= 0) & (g[:, 1] > 0),
                         (g[:, 0] < 0) & (g[:, 1] <= 0), (g[:, 0] >= 0) & (g[:, 1] <= 0)]
                sets = [g[m] for m in parts]
                mv = tyre_moves(fld, sets)
                for m, gs in zip(parts, sets):
                    q[m] += mv[id(gs)]
        else:
            q, J = move(fld, g)
            # a face whose winding turns over is a fold of the field (a thin sliver sheared past itself)
            pv = np.array([p.vertices[:3] for p in me.polygons if len(p.vertices) >= 3])
            if len(pv):
                n0 = np.cross(g[pv[:, 1]] - g[pv[:, 0]], g[pv[:, 2]] - g[pv[:, 0]])
                n1 = np.cross(q[pv[:, 1]] - q[pv[:, 0]], q[pv[:, 2]] - q[pv[:, 0]])
                bad = np.einsum("ij,ij->i", n0, n1) < 0
                for c in g[pv[bad, 0]][:8]:
                    print("PREP flip %s at (%.3f, %.3f, %.3f)" % (o.name, *c))
                flips += int(bad.sum())
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.corner_normals.foreach_get("vector", cn)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        ng = cn.reshape(-1, 3) @ R.T                   # world -> grid
        ng = np.einsum("lij,li->lj", np.linalg.inv(J)[lv], ng)   # n' = J^-T n (row vector n J^-1)
        nw = ng @ R
        nw /= np.maximum(np.linalg.norm(nw, axis=1, keepdims=True), 1e-12)
        me.vertices.foreach_set("co", ((q - b) @ Ai.T).ravel())
        moved[o] = q
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", nw.astype(np.float32).ravel())
        me.update()
    # the blade and the ledge on the prepped body (grid; rays through BVHs of those objects as moved)
    from mathutils.bvhtree import BVHTree

    def bvh_of(names):
        sel = [o for o in obs if o.name.startswith(names)]
        k = np.cumsum([0] + [len(moved[o]) for o in sel])
        return BVHTree.FromPolygons([tuple(v) for o in sel for v in moved[o]],
                                    [[i + k0 for i in p.vertices] for o, k0 in zip(sel, k) for p in o.data.polygons])
    body = [moved[o][:, 1] for o in obs if not o.name.startswith(NOT_BODY)]
    ymax, ymin = max(y.max() for y in body), min(y.min() for y in body)
    for name, (V, Fc) in ((LIP["name"], lip(bvh_of(("Object_11",)), ymax)),
                          (FIN["name"], fin(bvh_of(("Object_11", "Object_13")), ymin))):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in (V - b) @ Ai.T], [], Fc)
        me.materials.append(bpy.data.materials[MAT_BLACK])
        me.update()
        bo = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(bo)
        obs.append(bo)
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.ops.wm.obj_export(filepath=OUT, export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y",
                          export_uv=False, export_normals=True, export_materials=True, apply_modifiers=False,
                          export_triangulated_mesh=False)
    print("PREP width x %.5f, axles y %.4f / %.4f m, nose %+.4f, tail %+.4f m, %d folded faces -> %s"
          % (fld.wk, fld.yf, fld.yr, fld.cn, fld.ct, flips, OUT))


if __name__ == "__main__":
    if MAP:
        map_points()
    else:
        main()
