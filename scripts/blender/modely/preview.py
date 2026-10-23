"""Workbench texture-colour previews of a mesh file: side/front/back/top/iso, one PNG strip per view.
blender -b --factory-startup --python preview.py -- <in.glb|in.fbx|in.blend> <out_prefix> [ortho_scale]
Also imported by build.py (render_views)."""
import bpy, math, sys
from mathutils import Vector

VIEWS = {  # name: camera direction (from target toward camera)
    "left": Vector((-1, 0, 0)), "right": Vector((1, 0, 0)), "front": Vector((0, 1, 0)), "back": Vector((0, -1, 0)),
    "top": Vector((0, 0, 1)), "iso": Vector((-1, 1, 1.15)), "iso_rear": Vector((1, -1, 1.15)),
}


def render_views(out_prefix, ortho=5.0, center=Vector((0, 0, 0.6)), res=(1024, 512), views=VIEWS):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.view_settings.view_transform = "Standard"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = res
    cam = bpy.data.objects.get("PrevCam") or bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho
    sc.camera = cam
    for name, d in views.items():
        d = d.normalized()
        cam.location = center + d * 20
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{out_prefix}_{name}.png"
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:]
    src, out = a[0], a[1]
    if src.endswith(".blend"):
        bpy.ops.wm.open_mainfile(filepath=src)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if src.endswith(".glb"):
            bpy.ops.import_scene.gltf(filepath=src)
        else:
            bpy.ops.import_scene.fbx(filepath=src)
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    ws = [o.matrix_world @ v.co for o in obs for v in o.data.vertices]
    c = Vector([(min(w[i] for w in ws) + max(w[i] for w in ws)) / 2 for i in range(3)])
    size = max(max(w[i] for w in ws) - min(w[i] for w in ws) for i in range(3))
    render_views(out, ortho=float(a[2]) if len(a) > 2 else size * 1.1, center=c)
