"""Model X source prep, run once before convert.py (CAR=model_x): Abdul.Hannan's 'sketchfab tesla.blend' (a half
model: Mirror + Subsurf + Auto Smooth modifiers) -> the OBJ cars/model_x.py SRC reads, every modifier applied (the
Mirror makes the whole car; Subsurf at level 1 on the body parts, 0 on the tyres and rims; Back Door not welded across
the roof's middle, so each falcon wing door stays its own component for SIDE_PARTS), then the big parts
collapse-decimated with every material border and open edge held (a plain collapse left the paint / black trim borders
as a sawtooth: the diffuser, the sills). Ground (lowest tyre vertex) at z 0.
    "$B" -b --factory-startup --python scripts/blender/skf/prep_model_x.py [-- <src .blend> <out .obj>]
Defaults: temp/skf_mx/src/source/sketchfab tesla.blend -> temp/skf_mx/src/source/model_x.obj (+ .mtl).
"""
import bmesh
import bpy
import os
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "temp", "skf_mx", "src", "source")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
src, out = (args + [os.path.join(SRC_DIR, "sketchfab tesla.blend"), os.path.join(SRC_DIR, "model_x.obj")][len(args):])[:2]
TARGET = {"Car Body": 26000, "Front Door": 4400, "Trunk": 3200, "Bonnet": 1200}   # triangles after the collapse
bpy.ops.wm.open_mainfile(filepath=src)
for o in bpy.data.objects:
    for m in getattr(o, "modifiers", []):
        if m.type == "SUBSURF":
            m.levels = 0 if o.name.startswith(("Tyre", "Rim")) else 1
        if m.type == "MIRROR" and o.name == "Back Door":
            m.use_mirror_merge = False
dg = bpy.context.evaluated_depsgraph_get()
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    o.modifiers.clear()
    o.data = me


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


for o in meshes:
    if o.name not in TARGET:
        continue
    bpy.context.view_layer.objects.active = o
    for _ in range(3):                      # the ratio is on triangles: repeat until within 3 %
        n = tris(o)
        if n <= TARGET[o.name] * 1.03:
            break
        bm = bmesh.new()
        bm.from_mesh(o.data)
        held = {v.index for e in bm.edges if len(e.link_faces) != 2
                or e.link_faces[0].material_index != e.link_faces[1].material_index for v in e.verts}
        bm.free()
        if "interior" in o.vertex_groups:
            o.vertex_groups.remove(o.vertex_groups["interior"])
        o.vertex_groups.new(name="interior").add([i for i in range(len(o.data.vertices)) if i not in held], 1.0,
                                                 "REPLACE")
        m = o.modifiers.new("dec", "DECIMATE")
        m.decimate_type, m.ratio = "COLLAPSE", TARGET[o.name] / n
        m.use_symmetry, m.symmetry_axis = True, "Y"          # the source's mirror plane is local y 0
        m.vertex_group, m.vertex_group_factor = "interior", 1000.0
        bpy.ops.object.modifier_apply(modifier=m.name)
    print("PREP decimated", o.name, tris(o), "tris")
ground = min(min((o.matrix_world @ v.co).z for v in o.data.vertices) for o in meshes if o.name.startswith("Tyre"))
for o in bpy.data.objects:
    if o.parent is None:
        o.location.z -= ground
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.ops.wm.obj_export(filepath=out, export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y",
                      export_uv=False, export_normals=True, export_materials=True, apply_modifiers=True,
                      export_triangulated_mesh=False)
print("PREP ground", ground, "->", out)
