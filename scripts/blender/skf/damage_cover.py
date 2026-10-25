"""Damage-map coverage per mask zone: the share of the surface (area-weighted samples) whose UV1 lands on an opaque texel
(alpha > 0.1) of each shared Veh_* map, vanilla ModernCar next to our body (whole, doors on). Check after changing
damage_uv1 or the zones (models.md, coverage table).

    blender -b --factory-startup --python scripts/blender/skf/damage_cover.py [-- <body.blend|.fbx> <mask.png>]

Defaults: temp/skf/skf_whole.blend (convert.py build) and the MOD mask. Columns per map: ModernCar / ModernCar on its triangles whose
UV1 is not collapsed to a point (damage_uv1 skips those) / ours.
"""
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "common"))
from pzveh import NAME, TEX_DIR, TMP, Z, fan_tris, img_np, loop_data, mesh_co, vanilla  # noqa: E402

VTEX = os.path.join(vanilla.PZ, "textures", "Vehicles")
MAPS = ("Veh_Damage1", "Veh_Damage2", "Veh_Rust", "Veh_Blood_Mask")


def look(a, uv):
    h, w = a.shape[:2]
    return a[np.clip((uv[:, 1] % 1 * h).astype(int), 0, h - 1), np.clip((uv[:, 0] % 1 * w).astype(int), 0, w - 1)]


def coverage(ob, mask, n=600000):
    t, _ = fan_tris(ob.data)
    lv, (u0, u1) = loop_data(ob.data, ("UV0", "UV1"))
    P, U0, U1 = mesh_co(ob)[lv][t], u0[t], u1[t]
    area = np.linalg.norm(np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0]), axis=1) / 2
    e, f = U1[:, 1] - U1[:, 0], U1[:, 2] - U1[:, 0]
    valid = np.abs(e[:, 0] * f[:, 1] - e[:, 1] * f[:, 0]) / 2 * 512 ** 2 > 20 ** 2 * area
    rng = np.random.default_rng(1)
    ti = rng.choice(len(area), n, p=area / area.sum())
    r = rng.random((n, 2))
    r[r.sum(1) > 1] = 1 - r[r.sum(1) > 1]
    b = np.stack([1 - r.sum(1), r[:, 0], r[:, 1]], 1)[..., None]
    mc = look(mask, (U0[ti] * b).sum(1))[:, :3]
    uv1 = (U1[ti] * b).sum(1)
    hit = {m: look(img_np(bpy.data.images.load(os.path.join(VTEX, m + ".png"))), uv1)[:, 3] > 0.1 for m in MAPS}
    out = {}
    for k, c in Z.items():
        sel = np.abs(mc - np.array(c)).max(1) < 0.02
        if sel.sum() >= 50:
            sv = sel & valid[ti]
            out[k] = {m: (hit[m][sel].mean(), hit[m][sv].mean() if sv.any() else np.nan) for m in MAPS}
    return out


if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src = a[0] if a else os.path.join(TMP, "skf_whole.blend")
    mpath = a[1] if len(a) > 1 else os.path.join(TEX_DIR, NAME + "_mask.png")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ref = coverage(vanilla.load("Vehicles_ModernCar"), img_np(bpy.data.images.load(os.path.join(VTEX, "vehicle_carmodern_mask.png"))))
    if src.endswith(".blend"):
        with bpy.data.libraries.load(src) as (_, dst):
            dst.objects = [NAME]
        ob = dst.objects[0]
    else:
        old = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=src)
        ob = [o for o in bpy.data.objects if o.type == "MESH" and o not in old][0]
    ours = coverage(ob, img_np(bpy.data.images.load(mpath)))
    print("COVER zone    " + "".join(f"{m[4:]:>26}" for m in MAPS))
    for k in Z:
        if k in ref or k in ours:
            cells = [f"{ref[k][m][0] if k in ref else np.nan:8.3f}/{ref[k][m][1] if k in ref else np.nan:.3f}/"
                     f"{ours[k][m][0] if k in ours else np.nan:.3f}" for m in MAPS]
            print(f"COVER {k:8}" + "".join(f"{c:>26}" for c in cells))
