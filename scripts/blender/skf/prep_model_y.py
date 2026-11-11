"""Model Y Performance source prep, run once before convert.py (CAR=model_y, the default): BloxBloger's "2026 Tesla
Model Y Performance" (Sketchfab, CC BY-NC 4.0; CREDITS.md) -> the Performance at the owner's manual's size (US manual
2026.38.3 p.244 / CN manual dimensions page, "Model Y Performance": length 4,796 without the plate bracket, width
1,920 without mirrors, height 1,611, wheelbase 2,890, front overhang 895, rear 1,011; tyres 255/35 R21 front,
275/35 R21 rear) by one continuous displacement field, as prep_model_yl.py: no cuts, every source object and
component keeps its triangles (the config's CUT / GATE_COMPS keys hold). Against the source (4,783 long, 1,944 wide
over the rear arch trims, 1,648 high, front overhang 911, wheelbase 2,903, rear overhang 969, tyres 369 mm):
- width scaled about the centre line onto FIELD width (the wheels keep the source's track);
- the bumper ahead of the front arch shortened onto the front overhang (FIELD nose);
- the wheelbase shortened behind the rear seat (FIELD wb: the cabin moves as one), the tail lengthened behind the
  rear arch (FIELD tail) and the diffuser's lower lip a little more (FIELD diffuser);
- the tyres (dropped by convert.py, measured for the wheel) scaled about their centres to FIELD tyre (front, rear)
  and set on the ground (each axle's lowest tyre point = ground 0: a 0.14 deg nose-down shear);
- the body (not the wheels) lowered onto the manual's height (FIELD lower: official SIDE through the fitted camera had
  everything over the wheels 8-15 px high), the waist a little more (FIELD mid), the front end more (nose_drop), the
  front arch's top pulled in over the tyre (FIELD arch).
Normals: each corner's by the field's Jacobian, inverse transpose (finite differences).
Frame: the OBJ's own: x along the car, front -x, metres; y up, ground 0; z across. u = metres behind the nose, h =
height. `python prep_model_y.py map` (no Blender) maps pre-centre grid points (stdin "name x y z", the config's
frame) through the same field (cars/model_y.py's positions were mapped so). Check: the six sizes as the build's
GEOMETRY; numbers and the same-camera comparison: .claude/skills/tesla-dev/references/models.md section 0.
"""
import os
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "temp", "skf", "src", "source")
SRC = os.path.join(SRC_DIR, "Tesla Model Y Performance 2026.obj")
OUT = os.path.join(SRC_DIR, "model_y.obj")

PLATES = ("Object_11", "Object_12")
TYRES = "Object005"
MIRRORS = ("Plane.046", "Plane.047", "Plane.048", "Plane.050")
# tyres, wheel covers, rims, calipers, rotors: moved whole with their axle (cars/model_y.py DROP)
WHEEL = ("Object005", "Circle.", "Cylinder", "Plane.026", "Plane.027", "Plane.075", "Plane.076", "Plane.087",
         "Plane.088", "Plane.089", "Plane.090")
DROP = WHEEL + PLATES + ("Plane.031", "Plane.051", "Plane.053", "Plane.040", "Plane.067", "Hyundai_KONA",
                         "Tesla_Model_3")              # cars/model_y.py DROP: not in the length / height
NOT_BODY = DROP + MIRRORS                               # ... nor in the width
K, SRC_C = 0.826, (-1.0675, -1.787)        # pzveh.K; cars/model_y.py SRC_C (the pre-centre frame's origin)
# the field (metres; u behind the source's nose, h over the ground). Source landmarks: front axle u 0.911, rear 3.814,
# tail 4.783 (the bumper's corner at h 0.62), tyres r 0.3685 (both axles). Calibration knobs
FIELD = dict(
    width=1.920,                    # without mirrors, over the rear arch trims (the widest part)
    tyre=(0.3560, 0.3629),          # 255/35 R21 front, 275/35 R21 rear (radius, m)
    front=0.895,                    # front overhang: the bumper ahead of u nose[1] shortened, ramp from nose[0]
    nose=(0.02, 0.40),
    wheelbase=2.890,
    # the wheelbase's shortening ramps over source u behind the rear seat (the rear door's rear half and the arch's
    # front; whole behind): the cabin, the dash and both rows move as one (seat_head knees / legs), and the official
    # SIDE's B pillar and rear door seams stay within 2 px
    wb=(2.90, 3.60),
    rear=1.011,                     # rear overhang: the tail behind u tail[0] lengthened, ramp to tail[1]
    tail=(3.85, 4.60),
    # the body (not the wheels) down this much: official SIDE through the fitted camera, everything over the wheels sat
    # 8-15 px (35-60 mm) high with the source's ride height (door bottoms, handles, arches, roof alike); this takes the
    # height onto the manual's 1,611 and the door bottoms / roof onto the official's
    lower=0.0291,
    # the waist (handles, side cameras, lamps, the glass's foot) 3-4 px high in all three official views through the
    # fitted cameras, the sill and the roof on them: down d x a tent over source h (0 at h[0] and h[2], all at h[1])
    mid=dict(h=(0.55, 0.95, 1.45), d=0.013),
    # the front end over that (official SIDE: hood edge 5-6 px, headlamp 4 px high): down d x s(h over h) fading out
    # over u (the windscreen's foot stays)
    nose_drop=dict(u=(0.70, 1.30), h=(0.40, 0.80), d=0.010),
    # the front arch's top 6 px (24 mm) high on the official SIDE (the Performance sits lower on its springs: a smaller
    # gap over the tyre): points round the front wheel's centre at r (source, m) pulled in by d x a bump over r (up
    # over r[0..1], down over r[1..2]) x within a[0] deg of the top (none past a[1])
    arch=dict(r=(0.37, 0.47, 0.60), d=0.013, a=(35.0, 80.0)),
    # the rear bumper's lower black (diffuser, under h[1]) 5-10 px short of the official SIDE's after the tail stretch:
    # back d behind u (ramp), fading out over h (the bumper's rearmost point, the length, stays)
    diffuser=dict(u=(4.40, 4.70), h=(0.30, 0.45), d=0.020),
)


def s(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


class Field:
    """(u, h, |z - zc|) -> (du, dh), from the source's landmarks (nose, axles, tyre radii, zc)."""

    def __init__(self, nose, zc, ax, r, tail):
        f = FIELD
        self.nose, self.zc, self.ax, self.r = nose, zc, ax, r
        self.short = ax["f"] - f["front"]                         # the nose moves this far back
        self.wbd = f["wheelbase"] - (ax["r"] - ax["f"])            # the rear axle this far (negative: forward)
        self.taild = f["rear"] - (tail - ax["r"])                  # the tail behind the rear axle grows this much
        # the car on the new tyres: drop[k] at each axle (the source's tyres all r[k]), linear in u
        self.drop = {k: r[k] - f["tyre"][i] for i, k in enumerate(("f", "r"))}

    def __call__(self, u, h, az):
        f = FIELD
        du = self.short * (1 - s(u, *f["nose"])) + self.wbd * s(u, *f["wb"]) + self.taild * s(u, *f["tail"])
        df = f["diffuser"]
        du = du + df["d"] * s(u, *df["u"]) * (1 - s(h, *df["h"]))
        a = np.clip((u - self.ax["f"]) / (self.ax["r"] - self.ax["f"]), -1, 2)
        m, nd, ar = f["mid"], f["nose_drop"], f["arch"]
        dh = -(self.drop["f"] + (self.drop["r"] - self.drop["f"]) * a) - f["lower"] \
            + 0 * az \
            - m["d"] * s(h, m["h"][0], m["h"][1]) * (1 - s(h, m["h"][1], m["h"][2])) \
            - nd["d"] * s(h, *nd["h"]) * (1 - s(u, *nd["u"]))
        x, y = u - self.ax["f"], h - self.r["f"]                   # about the front wheel's centre (source)
        rr = np.hypot(x, y)
        k = ar["d"] * s(rr, ar["r"][0], ar["r"][1]) * (1 - s(rr, ar["r"][1], ar["r"][2])) \
            * (1 - s(np.degrees(np.abs(np.arctan2(x, y))), *ar["a"])) / np.maximum(rr, 1e-6)
        return du - k * x, dh - k * y


def landmarks(objs):
    """objs: name -> OBJ points. Nose / tail u, zc, axle u and h, tyre radius per axle, width factor."""
    keep = np.concatenate([c for n, c in objs.items() if not n.startswith(DROP)])   # what convert.py keeps
    nose, tail = keep[:, 0].min(), keep[:, 0].max()
    zc = (keep[:, 2].min() + keep[:, 2].max()) / 2
    body = np.concatenate([c for n, c in objs.items() if not n.startswith(NOT_BODY)])
    wk = FIELD["width"] / (2 * np.abs(body[:, 2] - zc).max())
    tyre = np.concatenate([c for n, c in objs.items() if n.startswith(TYRES)])
    sel = {"f": tyre[:, 0] - nose < 2.5, "r": tyre[:, 0] - nose >= 2.5}
    ax = {k: (tyre[m, 0].min() + tyre[m, 0].max()) / 2 - nose for k, m in sel.items()}
    hw = {k: (tyre[m, 1].min() + tyre[m, 1].max()) / 2 for k, m in sel.items()}
    r = {k: np.ptp(tyre[m, 1]) / 2 for k, m in sel.items()}
    return Field(nose, zc, ax, r, tail - nose), wk, hw, r


def read_obj(path):
    vs, names, cur = [], [], None
    for line in open(path):
        if line.startswith("v "):
            vs.append([float(x) for x in line.split()[1:4]])
            names.append(cur)
        elif line.startswith("o "):
            cur = line[2:].strip()
    vs, names = np.array(vs), np.array(names, object)
    return {n: vs[names == n] for n in dict.fromkeys(names)}


def move(fld, wk, hw, name, p):
    """New OBJ points and the Jacobian (3x3 per point) of object `name`'s points p."""
    u, h, az = p[:, 0] - fld.nose, p[:, 1], np.abs(p[:, 2] - fld.zc)
    J = np.zeros((len(p), 3, 3))
    J[:, 2, 2] = wk
    if name.startswith(WHEEL):        # moved whole with the axle; the tyres scaled about their centres (u, h)
        k = "f" if u.mean() < 2.5 else "r"
        sc = FIELD["tyre"][0 if k == "f" else 1] / fld.r[k] if name.startswith(TYRES) else 1.0
        du0, _ = fld(np.array([fld.ax[k]]), np.array([hw[k]]), np.array([0.0]))
        du = (fld.ax[k] + (u - fld.ax[k]) * sc - u) + du0[0]
        dh = (hw[k] + (h - hw[k]) * sc - h) - fld.drop[k]       # on the ground (not the body fields)
        J[:, 0, 0] = J[:, 1, 1] = sc
        J[:, 2, 2] = 1.0              # across: kept (the source's track 1,611; the width scale would narrow it)
    else:
        du, dh = fld(u, h, az)
        E = 1e-4
        sg = np.sign(p[:, 2] - fld.zc)
        for j, (a, b) in enumerate(((fld(u + E, h, az), fld(u - E, h, az)), (fld(u, h + E, az), fld(u, h - E, az)),
                                    (fld(u, h, az + E), fld(u, h, az - E)))):
            d = [(x - y) / (2 * E) for x, y in zip(a, b)]
            J[:, 0, j], J[:, 1, j] = d[0] * (sg if j == 2 else 1), d[1] * (sg if j == 2 else 1)
        J[:, 0, 0] += 1
        J[:, 1, 1] += 1
    q = p.copy()
    q[:, 0] += du
    q[:, 1] += dh
    q[:, 2] = fld.zc + (p[:, 2] - fld.zc) * J[:, 2, 2]
    return q, J


def to_obj(g):
    return np.stack([SRC_C[0] - g[:, 1] / K, g[:, 2] / K, -SRC_C[1] - g[:, 0] / K], 1)


def to_grid(v):
    return np.stack([K * (-v[:, 2] - SRC_C[1]), K * (SRC_C[0] - v[:, 0]), K * v[:, 1]], 1)


def map_points():
    """stdin "name x y z" (pre-centre grid, the config's frame) -> the same points through the field (body)."""
    objs = read_obj(SRC)
    fld, wk, hw, r = landmarks(objs)
    for line in sys.stdin:
        w = line.split()
        if len(w) < 4:
            continue
        g = np.array([[float(x) for x in w[1:4]]])
        q, _ = move(fld, wk, hw, "body", to_obj(g))
        n = to_grid(q)[0]
        print("%-12s (%.4f, %.4f, %.4f) -> (%.4f, %.4f, %.4f)  d %+.4f %+.4f %+.4f" % (w[0], *g[0], *n, *(n - g[0])))


def main():
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=SRC, forward_axis="NEGATIVE_Z", up_axis="Y")
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    co = {o: np.array([v.co[:] for v in o.data.vertices]) for o in obs}      # OBJ coordinates (x, y up, z)
    fld, wk, hw, r = landmarks({o.name: c for o, c in co.items()})
    for o in obs:
        me = o.data
        q, J = move(fld, wk, hw, o.name, co[o])
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.corner_normals.foreach_get("vector", cn)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        n = np.einsum("lij,li->lj", np.linalg.inv(J)[lv], cn.reshape(-1, 3))   # n' = J^-T n (row vector n J^-1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        me.vertices.foreach_set("co", q.ravel())
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", n.astype(np.float32).ravel())
        me.update()
    print("PREP nose %.4f back, rear axle %+.4f, tail %+.4f, width x %.5f, tyres r %.4f / %.4f -> %.4f / %.4f, "
          "drop %.4f / %.4f" % (fld.short, fld.wbd, fld.taild, wk, r["f"], r["r"], *FIELD["tyre"], fld.drop["f"],
                                fld.drop["r"]))
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.ops.wm.obj_export(filepath=OUT, export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y",
                          export_uv=False, export_normals=True, export_materials=True, apply_modifiers=False,
                          export_triangulated_mesh=False)
    print("PREP ->", OUT)


if __name__ == "__main__":
    if sys.argv[1:2] == ["map"]:
        map_points()
    else:
        main()
