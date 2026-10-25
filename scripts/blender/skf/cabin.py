"""Cabin and trunk for the converted body (convert.py pieces): modely/build.py's cabin_mesh, lining and rbox as on
branch feat/edges-1025 (40e6107: shell faces in a door opening carry the door in UV1 v, the shader drops them while that
door is open or removed), the user-approved cabin of 2026-10-24 (seats, dash, wheel, screen, console, trunk), with
this body's numbers. The Sketchfab model's own interior is not used (user 2026-10-25)."""
import math
import bmesh, bpy
import numpy as np
from mathutils import Matrix, Vector
import build as mb  # noqa: E402  (modely/build.py, on sys.path via convert.py)
from build import dup, face_centres, keep_faces, select_only, tris  # noqa: F401

NAME, CABIN_CELLS, CABIN_UV1_U = mb.NAME, mb.CABIN_CELLS, mb.CABIN_UV1_U
SHELL_DOORS = ("DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight", "TrunkDoor")
# mesh coords (centred; this body: ground z -0.748). Values as modely unless noted
CABIN_FLOOR = -0.43       # cabin floor
CABIN_INSET = 0.05        # grid: the shell sits this far inside the surface its ray hit (door slab 0.06)
LINING_TRIS, LINING_IN = 700, 0.015
CABIN_FRONT_Y = 1.06      # shell front wall: past the windscreen's lower edge (this body: y 1.02 on the centre line)
TRUNK_Y = -0.95           # trunk floor starts behind the rear backrests
TRUNK_DROP = 0.03
CABIN_ZC = -0.10          # cabin axis the shell rays start from
CABIN_RES = (0.062, 49)
SEAT_X, SEAT_Z = 0.33, -0.19
SEAT_Y = (0.195, -0.715)  # front / rear seat (modely: (door front + B pillar) / 2 - 0.12, (B pillar + door rear) / 2 - 0.08)


def decimate_keep(ob, target):
    """Collapse to target triangles (X symmetric), open-edge vertices kept (feat/edges-1025 decimate keep_boundary:
    out of the modifier's vertex group at factor 1000, so the lining's outline stays on the glass edge)."""
    select_only(ob)
    for _ in range(3):
        n = tris(ob)
        if n <= target * 1.03:
            break
        m = ob.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = target / n
        m.use_symmetry, m.symmetry_axis = True, "X"
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        edge = {v.index for e in bm.edges if e.is_boundary for v in e.verts}
        bm.free()
        if "interior" in ob.vertex_groups:
            ob.vertex_groups.remove(ob.vertex_groups["interior"])
        ob.vertex_groups.new(name="interior").add([i for i in range(len(ob.data.vertices)) if i not in edge], 1.0, "REPLACE")
        m.vertex_group, m.vertex_group_factor = "interior", 1000.0
        bpy.ops.object.modifier_apply(modifier=m.name)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def rbox(size, r, cuts=(0, 0, 0), seg=2):
    """Rounded box on the origin: full size (x, y, z), edge radius r; `cuts` extra loops per axis give later bends
    vertices to move. -> verts (N x 3), faces (index lists), outward."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for ax, n in enumerate(cuts):
        if n:
            es = [e for e in bm.edges if abs(e.verts[0].co[ax] - e.verts[1].co[ax]) > 0.5]
            bmesh.ops.subdivide_edges(bm, edges=es, cuts=n, use_grid_fill=True)
    for v in bm.verts:
        v.co = Vector([v.co[i] * size[i] for i in range(3)])
    bm.normal_update()
    rim = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0) > 0.5]
    bmesh.ops.bevel(bm, geom=rim + list({v for e in rim for v in e.verts}), offset=r, segments=seg, profile=0.5,
                    affect="EDGES", clamp_overlap=True)
    bm.verts.index_update()
    V = np.array([v.co[:] for v in bm.verts])
    F = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    return V, F


def rot_x(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def lining(body, belt, rear_y):
    """Inner side of the body above the belt inside the cabin (pillars, roof rails, the bars round the roof glass): its
    outer paint faces after the glass split (not the jambs: turned inward they stood up as black teeth behind the
    glass), decimated to LINING_TRIS with the outline kept, turned to the cabin axis and pulled LINING_IN inside. From
    outside the near side faces away (culled); through the glass the far side shows a dark lining whose edges follow the
    glass's own (a ray-grid shell there left a staircase along every window, E2E TeslaCabin-cab-after-1024c)."""
    ob = dup(body, "lining")
    c = face_centres(ob)
    keep_faces(ob, (c[:, 2] > belt) & (c[:, 1] < CABIN_FRONT_Y) & (c[:, 1] > rear_y))
    n0 = tris(ob)
    decimate_keep(ob, LINING_TRIS)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.normal_update()
    for f in bm.faces:                                  # face the axis (decimate's recalc picks either side)
        cen = f.calc_center_median()
        if f.normal.dot(Vector((0, min(max(cen.y, -1.0), 0.7), CABIN_ZC)) - cen) < 0:
            f.normal_flip()
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * LINING_IN
    print("CABIN lining tris", n0, "->", len(bm.faces))
    bm.verts.index_update()
    V = np.array([v.co[:] for v in bm.verts])
    F = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    bpy.data.objects.remove(ob)
    return V, F


def cabin_mesh(bvh, belt, lining, trunk_floor, trunk_end, arch, opening):
    """Cabin and trunk (mesh coords, centred), smooth-shaded rounded parts: below the belt a shell CABIN_INSET inside
    the body and the doors (floor, sills, firewall, door walls, the trunk's sides and wheel-arch humps, its rear wall
    behind the tailgate's inner panel at `trunk_end`; none behind glass, so the far windows stay see-through), the
    floor at CABIN_FLOOR, behind the rear backrests (TRUNK_Y) at `trunk_floor`; above the belt `lining`; Model Y front
    buckets (cushion and backrest side bolsters, curved backrest, integrated headrest), rear bench (three cushions and
    backs, three headrests), dash with its trim strip, 15.4" centre screen (lit face to the seats), steering wheel,
    centre console, the trunk's sill plate and its under-floor bin lid. Every shell face looks at the axis: from outside
    the near wall is a back face (culled: an open door shows the seats, the open tailgate the trunk) and the far wall
    stands in for the far door's inner panel (it sits inside it), which the near window, drawn first, would hide by
    depth. `bvh`: "body" / "glass" / "door" surfaces in Blender axes; `belt`: mesh z of the belt line; `opening`: the
    door openings (stage cabin) for the shell faces the shader drops while a door is open (UV1 v, see below)."""
    V, F, cell, flat, dk, shell_n = [], [], [], [], [], 0

    def add(v, f, c, smooth=True, door=0):
        n = sum(len(x) for x in V)
        V.append(np.asarray(v, float))
        F.extend([[i + n for i in fc] for fc in f])
        cell.extend([c] * len(f) if isinstance(c, str) else c)
        flat.extend([not smooth] * len(f))
        dk.extend([door] * len(f) if isinstance(door, int) else door)

    # shell: rings across y (one on each side door's y cut, so no face straddles two openings), rays from the axis;
    # each ray keeps what it hit first (body / glass / door)
    step, na = CABIN_RES
    ys = np.append(np.arange(CABIN_FRONT_Y, trunk_end + step / 2, -step), trunk_end)
    ys = np.sort(np.concatenate([ys[np.abs(ys[:, None] - opening["y"]).min(1) > step / 3], opening["y"]]))[::-1]
    nr = len(ys)
    pts, kind, who = np.zeros((nr, na + 2, 3)), np.zeros((nr, na + 2), object), np.zeros((nr, na + 2), int)
    for i, y in enumerate(ys):
        floor = CABIN_FLOOR if y > TRUNK_Y else trunk_floor
        o = Vector((0, y, CABIN_ZC))
        for j, t in enumerate(np.radians(np.linspace(200, -20, na)), 1):
            d = Vector((math.cos(t), 0, math.sin(t)))
            hits = [(h[3], k, h[0]) for k, b in bvh.items() for h in (b.ray_cast(o, d),) if h[0] is not None]
            dist, k, p = min(hits) if hits else (1.0, "none", o + d)
            p = p - d * CABIN_INSET
            pts[i, j] = (p.x, y, max(p.z, floor))
            kind[i, j] = "floor" if p.z <= floor else k
            if kind[i, j] == "door":                     # which door: SHELL_DOORS number (0: the frunk lid)
                h = min((b.ray_cast(o, d)[3] or 9.0, nm) for nm, b in opening["each"].items())
                who[i, j] = SHELL_DOORS.index(h[1]) + 1 if h[1] in SHELL_DOORS and h[0] <= dist + 1e-4 else 0
        pts[i, 0], pts[i, -1] = (pts[i, 1, 0], y, floor), (pts[i, -2, 0], y, floor)
        kind[i, 0] = kind[i, -1] = "floor"
    n = na + 2
    # the top edge: a cell reaching up to 8 cm over the belt is pulled down onto it (dropping it left a staircase of
    # cells along the trunk's sides, black teeth through the open tailgate: user 2026-10-25); higher cells go
    near = (pts[..., 2] <= belt + 0.08) & np.isin(kind, ("body", "door"))
    pts[..., 2] = np.where(near, np.minimum(pts[..., 2], belt), pts[..., 2])
    sv, sf, sc = pts.reshape(-1, 3), [], []
    keep = lambda q: all(kind.flat[x] in ("body", "door", "floor") and sv[x][2] <= belt for x in q)   # noqa: E731
    for i in range(nr - 1):
        for j in range(n):
            q = [i * n + j, (i + 1) * n + j, (i + 1) * n + (j + 1) % n, i * n + (j + 1) % n]
            ks = [kind.flat[x] for x in q]
            if keep(q):     # two triangles, each turned to the axis below: a quad folded where neighbouring rays hit
                sf += [q[:3], [q[0], q[2], q[3]]]       # different surfaces, and a half facing out was culled
                sc += ["floor" if all(k == "floor" for k in ks) else "liner"] * 2
    for i in (0, nr - 1):                               # firewall and the trunk's rear wall: fans round the axis
        c = len(sv)
        sv = np.concatenate([sv, [[0, pts[i, 0, 1], CABIN_ZC]]])
        for j in range(n):
            if keep([i * n + j, i * n + (j + 1) % n]):
                sf.append([c, i * n + j, i * n + (j + 1) % n])
                sc.append("liner")
    turned = 0
    for f in sf:                                        # every shell face looks at the axis, raised to the belt: the
        a, b, c = sv[f[0]], sv[f[1]], sv[f[2]]          # wheel-arch humps' tops sit at the ray axis's height (z -0.10),
        cen = sv[f].mean(0)                             # where turning to it was a coin toss (holes over the arches)
        tgt = np.array([0, min(max(cen[1], -1.0), 0.7), belt])
        if np.dot(np.cross(b - a, c - a), tgt - cen) < 0:
            f.reverse()
            turned += 1
    # the face's door: a side door's when it lies on that door's side (where the rays hit it) between its y cuts; the
    # tailgate's when a rim corner hit it (the fans' axis corner hits nothing). The exact edge is per pixel: UV1 v
    # carries a distance to the opening's sill / arch / lower edge (below)
    yf, yb, yr = opening["y"]
    span = {1: (yb, yf), 2: (yb, yf), 3: (yr, yb), 4: (yr, yb)}
    side = {k: np.sign(pts[..., 0][who == k].mean()) for k in span if (who == k).any()}
    door = []
    for f in sf:
        p = sv[f]
        k = next((k for k in side if abs(p[:, 0].mean()) > 0.3 and np.sign(p[:, 0].mean()) == side[k]
                  and span[k][0] - 1e-6 <= p[:, 1].min() and p[:, 1].max() <= span[k][1] + 1e-6), 0)
        door.append(k or (5 if any(who.flat[x] == 5 for x in f if x < nr * n) else 0))
    hump = [i for i, (f, k) in enumerate(zip(sf, sc)) if k == "liner" for cen in (sv[f].mean(0),)
            if abs(cen[0]) > 0.3 and np.hypot(cen[1] - arch[0], cen[2] - arch[1]) < arch[2] + 0.15]
    print("CABIN shell triangles", len(sf), "turned to the axis", turned, "two-sided over the rear arches", len(hump),
          "in door openings", {nm: door.count(k + 1) for k, nm in enumerate(SHELL_DOORS)})
    add(sv, sf, sc, smooth=False, door=door)
    # the humps over the rear arches fold on the coarse ray grid (holes through the open tailgate): both sides drawn
    # there, the back copy on its own vertices (the mesh drops a face on the same vertices as another)
    add(sv[np.ravel([sf[i] for i in hump])], [[3 * k + 2, 3 * k + 1, 3 * k] for k in range(len(hump))], "liner",
        smooth=False, door=[door[i] for i in hump])
    add(*lining, "liner", smooth=False)
    shell_n = len(sf) + len(hump) + len(lining[1])

    def part(size, r, c, at, cuts=(0, 0, 0), sag=0.0, bend=0.0, taper=0.0, tilt=None, seg=2):
        """rbox + shaping: `sag` dips the top's middle (x), `bend` brings the sides forward (+y), `taper` narrows the
        top; `tilt` = (pivot y, pivot z, deg) reclines about a line along x (top to the rear)."""
        v, f = rbox(size, r, cuts, seg)
        x = 2 * v[:, 0] / size[0]
        if sag:
            v[:, 2] -= sag * np.clip(1 - x * x, 0, 1) * (v[:, 2] > 0)
        v[:, 1] += bend * x * x
        v[:, 0] *= 1 - taper * (v[:, 2] / size[2] + 0.5)
        v += at
        if tilt:
            py, pz, deg = tilt
            v = (v - [0, py, pz]) @ rot_x(deg).T + [0, py, pz]
        add(v, f, c)
        return v, f

    z0 = SEAT_Z
    for s in (-1, 1):                                   # front buckets
        cx, fy = s * SEAT_X, SEAT_Y[0]
        rec = (fy - 0.11, z0 - 0.03, 14)
        part((0.30, 0.30, z0 - 0.10 - CABIN_FLOOR), 0.02, "base", (cx, fy + 0.05, (z0 - 0.10 + CABIN_FLOOR) / 2), seg=1)
        part((0.42, 0.40, 0.09), 0.035, "seat", (cx, fy + 0.08, z0 - 0.06), cuts=(2, 0, 0), sag=0.025)
        part((0.42, 0.11, 0.50), 0.04, "seat", (cx, fy - 0.17, z0 + 0.22), cuts=(2, 0, 0), bend=0.05, taper=0.12, tilt=rec)
        part((0.25, 0.10, 0.17), 0.05, "seat", (cx, fy - 0.18, z0 + 0.54), taper=0.1, tilt=rec, seg=3)
        for e in (-1, 1):
            part((0.07, 0.34, 0.07), 0.03, "seat", (cx + e * 0.185, fy + 0.07, z0 - 0.01))
            part((0.07, 0.13, 0.32), 0.03, "seat", (cx + e * 0.19, fy - 0.11, z0 + 0.15), tilt=rec)
    ry = SEAT_Y[1]                                      # rear bench: three cushions, three backs, three headrests
    rec = (ry - 0.11, z0 - 0.03, 18)
    part((1.08, 0.36, z0 - 0.10 - CABIN_FLOOR), 0.02, "base", (0, ry + 0.06, (z0 - 0.10 + CABIN_FLOOR) / 2), seg=1)
    for cx, wd in ((-0.365, 0.36), (0, 0.33), (0.365, 0.36)):
        part((wd, 0.40, 0.09), 0.035, "seat", (cx, ry + 0.08, z0 - 0.06), cuts=(1, 0, 0), sag=0.015)
        part((wd, 0.11, 0.44), 0.04, "seat", (cx, ry - 0.17, z0 + 0.19), cuts=(1, 0, 0), bend=0.02, tilt=rec)
        part((0.20 if cx else 0.17, 0.09, 0.12), 0.045, "seat", (cx, ry - 0.18, z0 + 0.48), tilt=rec, seg=3)
    part((0.20, 0.80, 0.22), 0.04, "console", (0, 0.12, -0.32))                  # centre console
    part((1.24, 0.34, 0.16), 0.06, "dash", (0, 0.80, -0.02))                     # dash, trim strip on its face
    part((1.16, 0.02, 0.035), 0.008, "trim", (0, 0.627, -0.01))
    # trunk: sill plate over the opening's lower edge (the floor ends TRUNK_DROP under it, CABIN_INSET short of the
    # tailgate's inner panel) and the under-floor bin's lid
    part((1.00, 0.12, TRUNK_DROP + 0.005), 0.01, "base", (0, trunk_end + 0.02, trunk_floor + TRUNK_DROP / 2), seg=1)
    part((0.86, 0.40, 0.012), 0.004, "console", (0, (TRUNK_Y + trunk_end) / 2 - 0.04, trunk_floor + 0.006), seg=1)
    part((0.05, 0.04, 0.09), 0.012, "screen_back", (0, 0.64, 0.09))              # screen stand
    v, f = rbox((0.30, 0.022, 0.19), 0.012)                                       # 15.4" landscape screen
    v = v @ rot_x(-12).T + [0, 0.61, 0.17]
    fn = np.array([np.cross(v[fc[1]] - v[fc[0]], v[fc[2]] - v[fc[0]]) for fc in f])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True)
    add(v, f, ["screen" if k < -0.9 else "screen_back" for k in fn[:, 1]])
    # steering wheel in front of the driver, tilted 70 deg back from horizontal: rim torus, hub, three spokes, column
    wr = Matrix.Translation((-SEAT_X, 0.50, 0.04)) @ Matrix.Rotation(math.radians(70), 4, "X")
    nu, nv = 20, 6
    tv = [wr @ Vector(((0.15 + 0.024 * math.cos(b)) * math.cos(a), (0.15 + 0.024 * math.cos(b)) * math.sin(a),
                       0.024 * math.sin(b)))
          for a in np.linspace(0, 2 * math.pi, nu, endpoint=False) for b in np.linspace(0, 2 * math.pi, nv, endpoint=False)]
    add([p[:] for p in tv], [[i * nv + j, i * nv + (j + 1) % nv, ((i + 1) % nu) * nv + (j + 1) % nv, ((i + 1) % nu) * nv + j]
                             for i in range(nu) for j in range(nv)], "wheel")
    for size, at in (((0.11, 0.09, 0.05), (0, 0, 0)), ((0.26, 0.03, 0.02), (0, -0.02, 0)), ((0.03, 0.13, 0.02), (0, -0.08, 0)),
                     ((0.05, 0.05, 0.22), (0, 0, -0.12))):
        v, f = rbox(size, min(size) * 0.45)
        add([(wr @ Vector(p + np.array(at)))[:] for p in v], f, "wheel")
    # mesh: tris, normals made consistent (outward) on the closed parts, shell faces kept looking at the axis
    me = bpy.data.meshes.new(NAME + "_Cabin")
    me.from_pydata(np.concatenate(V).tolist(), [], F)
    names = list(CABIN_CELLS)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[shell_n:])
    for f, c, fl, k in zip(bm.faces, cell, flat, dk):
        f.material_index = names.index(c) + 16 * k        # cell and door through triangulate (reset below)
        f.smooth = not fl
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    ci = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("material_index", ci)
    lt = [p.loop_total for p in me.polygons]
    # UV0: any texel (the shader's cabin class reads no texture); UV1 = (CABIN_UV1_U - cell, door + d): d (+-0.45) is
    # how far the corner is outside the opening (below the sill, inside the rear arch, below the tailgate's lower
    # edge), linear over a triangle, so the shader cuts the shell along the opening per pixel
    me.uv_layers.new(name="UV0").data.foreach_set("uv", np.zeros(len(me.loops) * 2))
    vi = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", vi)
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    y, z = co.reshape(-1, 3)[vi, 1], co.reshape(-1, 3)[vi, 2]
    k = np.repeat(ci // 16, lt)
    d = np.where(k == 5, opening["gate"] - z, opening["sill"] - z)
    d = np.where((k == 3) | (k == 4), np.maximum(d, arch[2] - np.hypot(y - arch[0], z - arch[1])), d)
    uv1 = np.stack([CABIN_UV1_U - np.repeat(ci % 16, lt), np.where(k > 0, k + np.clip(d, -0.45, 0.45), 0)], 1)
    me.uv_layers.new(name="UV1").data.foreach_set("uv", uv1.ravel())
    me.polygons.foreach_set("material_index", np.zeros(len(me.polygons), np.int64))
    me.update()
    cn = np.empty(len(me.loops) * 3, np.float32)       # the body's free corner normals (joined into it): smooth / flat
    me.corner_normals.foreach_get("vector", cn)
    me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", cn)
    ob = bpy.data.objects.new(NAME + "_Cabin", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(bpy.data.materials.new(NAME + "_Cabin"))
    print("CABIN shell faces", shell_n, "of", nr * n, "cells", {c: cell.count(c) for c in names})
    return ob


# ---------------------------------------------------------------- script numbers, previews, verify
