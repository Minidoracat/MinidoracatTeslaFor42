"""Parse a vanilla ASCII FBX vehicle body (Blender 5.2 refuses ASCII FBX) into a Blender mesh in grid units.

Axes after conversion match our build: +Y = vehicle front, +Z = up, +X = ? (printed by measure()).
Grid = raw vertex * model scale (0.008) * vehicle scale (1.82)  (R5 section 1, BaseVehicle.java:4390-4402).
"""
import bpy
from mathutils import Vector

PZ = "D:/SteamLibrary/steamapps/common/ProjectZomboid/media"


def _arr(t, start):
    b = t.index("a:", start)
    e = t.index("}", b)
    return [float(x) for x in t[b + 2:e].replace("\n", "").split(",") if x.strip()]


def load(name="Vehicles_ModernCar", k=0.008 * 1.82, uv=True):
    t = open(f"{PZ}/models_X/vehicles/{name}.fbx", encoding="latin-1").read()
    s = t.index("Geometry: ")
    v = _arr(t, t.index("Vertices:", s))
    pvi = [int(x) for x in _arr(t, t.index("PolygonVertexIndex:", s))]
    # PreRotation -90 X turns Max Z-up into Y-up; FBX -Z is the car front (vehicle-part-models.md 2).
    # Max raw coords: x, y, z(up). After -90 X: (x, z, -y). FBX front -Z  => raw +y is front.
    verts = [Vector((v[i], v[i + 1], v[i + 2])) * k for i in range(0, len(v), 3)]
    polys, cur = [], []
    for i in pvi:
        if i < 0:
            cur.append(~i)
            polys.append(cur)
            cur = []
        else:
            cur.append(i)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], polys)
    if uv:
        for layer in (0, 1):
            key = f"LayerElementUV: {layer}"
            if key not in t:
                continue
            p = t.index(key)
            uvs = _arr(t, t.index("UV:", p))
            idx = [int(x) for x in _arr(t, t.index("UVIndex:", p))]
            ul = me.uv_layers.new(name=f"UV{layer}")
            for li, ui in enumerate(idx):
                ul.data[li].uv = (uvs[ui * 2], uvs[ui * 2 + 1])
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def bbox(ob):
    ws = [ob.matrix_world @ v.co for v in ob.data.vertices]
    return (Vector([min(w[i] for w in ws) for i in range(3)]), Vector([max(w[i] for w in ws) for i in range(3)]))


if __name__ == "__main__":
    import sys
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ob = load(sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "Vehicles_ModernCar")
    mn, mx = bbox(ob)
    print("BBOX", tuple(round(x, 3) for x in mn), tuple(round(x, 3) for x in mx))
    # lowest vertices per quarter, to locate wheel arches
    vs = [v.co for v in ob.data.vertices]
    for zband in (0.10, 0.25, 0.40):
        sel = [c for c in vs if c.z < mn.z + zband]
        print("z<", zband, "n", len(sel), "y-range", round(min(c.y for c in sel), 3), round(max(c.y for c in sel), 3))
    # side profile: lowest z at each y slice (arches show as raised bottoms)
    for i in range(0, 44):
        y0 = mn.y + i * 0.1
        sl = [c for c in vs if y0 <= c.y < y0 + 0.1 and abs(c.x) > 0.6]
        if sl:
            print("Y %.2f minZ %.3f maxZ %.3f maxX %.3f" % (y0, min(c.z for c in sl), max(c.z for c in sl), max(abs(c.x) for c in sl)))
