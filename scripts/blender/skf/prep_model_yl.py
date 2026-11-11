"""Model Y L source prep, run once before convert.py (CAR=model_yl): BloxBloger's "2025 Tesla Model Y" (the standard
car, Sketchfab, CC BY-NC 4.0; CREDITS.md) -> the six-seat long-wheelbase Model Y L, by one continuous displacement field
(no cuts, no new faces: the wheel arches stay round, every source object and component keeps its triangles, so the
config's CUT / GATE_COMPS keys hold). Official Model Y L against Model Y (owner's manual: wheelbase 3,040 against
2,890, rear overhang 1,040 against 1,011, height 1,668 against 1,624; the design studio's SIDE renders, same camera:
temp/plan-yl-1111 specs.md section 3, engine-feasibility.md 4.1): nose to B pillar the same; the rear wheel and its
arch 150 mm back (the rear door's lower half stretched with it, its upper half and window where they were); the tail
177 mm back (the quarter window and C pillar stretched over it); the roof raised from the B pillar back (FIELD roof).
The duck lip is the Y L blade's place and size once moved (side_iou rear rows; cars/model_yl.py CARBON paints it
black). Normals: each corner's by the field's Jacobian, inverse transpose (finite differences).
Frame here: the OBJ's own (the importer leaves its axes in each object's rotation): x along the car, front -x,
metres; y up, ground 0; z across. u = metres behind the nose, h = height. Check: scripts/blender/skf/side_iou.py
against yl_MTY87_PN01_SIDE.png.
"""
import os
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "temp", "skf_yl", "src", "source")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
src, out = (args + [os.path.join(SRC_DIR, "tesla.obj"), os.path.join(SRC_DIR, "model_yl.obj")][len(args):])[:2]

# the field (metres; u behind the nose, h over the ground). Source landmarks: rear wheel centre u 3.812 h 0.354, its
# arch trim radius ~0.50; rear door u 2.58-3.70 (rear edge R1 above the arch at u ~3.72), its window's rear bar u ~3.6;
# belt h 1.06; roof glass ends u 3.74, tail u 4.79. Calibration knobs, fitted on side_iou
FIELD = dict(
    wheel=(3.812, 0.354, 0.505, 0.03),   # rear arch: centre u, h, the trim's outer radius (whole shift inside), fade
    rear=0.150,                     # rear axle (and arch) back: wheelbase 3,040 - 2,890
    door=(2.85, 3.50, 0.55, 0.86),  # lower shift ramps from u door[0] (low) / door[1] (above the arch) to the arch; the
    #                                 two blend over h door[2]..door[3]
    band=(0.86, 1.06),              # lower (arch) shift below h band[0], upper (quarter window) shift above band[1]
    upper=(3.62, 4.45, 0.195),      # upper shift ramps over u (window bar -> tail lamp front): the tail lamps ~195 mm back
    over=(4.30, 4.65, 0.027),       # rear overhang +27 mm behind the arch (lower): 150 + 27 = 177 at the bumper
    roof=((2.30, 0.0), (2.55, 0.010), (2.90, 0.036), (3.30, 0.072), (3.66, 0.100), (3.95, 0.112), (4.20, 0.100),
          (4.40, 0.085), (4.60, 0.050), (4.80, 0.035)),   # raise at the top (source u)
    roof_h=1.00,                    # the raise fades to 0 at this height (under the belt): top(u) gets all of it
)


def s(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def top_profile(a, b):
    """Source top height per u: the upper envelope of the edges (a, b: their ends, (u, h) rows) in 2 cm bins, each
    edge sampled every cm (the roof is a few big triangles: its vertices alone left most bins on the cabin below),
    smoothed over 10 cm."""
    n = np.maximum(np.ceil(np.abs(b[:, 0] - a[:, 0]) / 0.01).astype(int), 1)
    k = np.repeat(np.arange(len(a)), n + 1)
    t = np.concatenate([np.arange(m + 1) / m for m in n])
    p = a[k] + (b[k] - a[k]) * t[:, None]
    edges = np.arange(-0.05, p[:, 0].max() + 0.07, 0.02)
    i = np.clip(np.digitize(p[:, 0], edges) - 1, 0, len(edges) - 2)
    top = np.full(len(edges) - 1, -np.inf)
    np.maximum.at(top, i, p[:, 1])
    ok = np.isfinite(top)
    top = np.interp(np.arange(len(top)), np.flatnonzero(ok), top[ok])
    top = np.convolve(np.pad(top, 2, mode="edge"), np.ones(5) / 5, "valid")
    return edges[:-1] + 0.01, top


def field(u, h, prof):
    """(du, dh): rearward and upward displacement of points (u, h)."""
    f = FIELD
    uw, hw, rw, fade = f["wheel"]
    up_h = s(h, f["door"][2], f["door"][3])                       # 0 low on the door, 1 above the arch
    a = f["door"][0] + (f["door"][1] - f["door"][0]) * up_h
    dh = np.clip(np.abs(h - hw), 0, rw * 0.999)
    front = uw - np.sqrt(rw * rw - dh * dh)                       # the arch's front at h (its top above it)
    b = np.maximum(np.where(h < hw + rw, front, uw), a + 0.08)
    # the arch and its trim move whole (round), the door and quarter panel round it take up the stretch
    arch = 1 - s(np.hypot(u - uw, h - hw), rw, rw + fade)
    low = f["rear"] * np.maximum(s(u, a, b), arch) + f["over"][2] * s(u, *f["over"][:2])
    upper = f["upper"][2] * s(u, *f["upper"][:2])
    w = s(h, *f["band"])
    du = low * (1 - w) + upper * w
    ru, rz = np.array(f["roof"]).T
    top = np.interp(u, *prof)
    dz = np.interp(u, ru, rz) * np.clip((h - f["roof_h"]) / np.maximum(top - f["roof_h"], 0.05), 0, 1)
    return du, dz


def main():
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=src, forward_axis="NEGATIVE_Z", up_axis="Y")
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    co = {o: np.array([v.co[:] for v in o.data.vertices]) for o in obs}      # OBJ coordinates (x, y up, z)
    allc = np.concatenate([c for o, c in co.items() if not o.name.startswith(("Object_11", "Object_12"))])
    nose = allc[:, 0].min()
    ends = []
    for o, c in co.items():
        if not o.name.startswith(("Object_11", "Object_12")):
            e = np.empty(len(o.data.edges) * 2, np.int64)
            o.data.edges.foreach_get("vertices", e)
            ends.append(c[e.reshape(-1, 2)][:, :, :2] - (nose, 0))
    ends = np.concatenate(ends)
    prof = top_profile(ends[:, 0], ends[:, 1])
    # the ground: the lowest tyre vertex (the source's tyres sink 14.5 mm under y 0; the script's wheels and the seat
    # heights take the ground as the tyres' bottom, seat_head.py's depth reference)
    lift = -min(c[:, 1].min() for o, c in co.items() if o.name.startswith("Object005"))
    E = 1e-4
    for o in obs:
        me = o.data
        p = co[o]
        u, h = p[:, 0] - nose, p[:, 1]
        du, dz = field(u, h, prof)
        # Jacobian of (x, y, z) -> (x + du, y + dz, z) by central differences
        dxu = [(a - b) / (2 * E) for a, b in zip(field(u + E, h, prof), field(u - E, h, prof))]
        dxh = [(a - b) / (2 * E) for a, b in zip(field(u, h + E, prof), field(u, h - E, prof))]
        J = np.zeros((len(p), 3, 3))
        J[:, 0, 0], J[:, 0, 1] = 1 + dxu[0], dxh[0]
        J[:, 1, 0], J[:, 1, 1] = dxu[1], 1 + dxh[1]
        J[:, 2, 2] = 1
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.corner_normals.foreach_get("vector", cn)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        n = np.einsum("lij,li->lj", np.linalg.inv(J)[lv], cn.reshape(-1, 3))   # n' = J^-T n (row vector n J^-1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        p2 = p.copy()
        p2[:, 0] += du
        p2[:, 1] += dz + lift
        me.vertices.foreach_set("co", p2.ravel())
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", n.astype(np.float32).ravel())
        me.update()
    new = np.concatenate([np.array([v.co[:] for v in o.data.vertices]) for o in obs
                          if not o.name.startswith(("Object_11", "Object_12"))])
    print("PREP length %.4f -> %.4f m, height %.4f -> %.4f m, lifted %.4f m onto the tyres" % (
        np.ptp(allc[:, 0]), np.ptp(new[:, 0]), allc[:, 1].max(), new[:, 1].max(), lift))
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.ops.wm.obj_export(filepath=out, export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y",
                          export_uv=False, export_normals=True, export_materials=True, apply_modifiers=False,
                          export_triangulated_mesh=False)
    print("PREP ->", out)


if __name__ == "__main__":
    main()
