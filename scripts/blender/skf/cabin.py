"""The mod's own cabin and trunk, joined into the body mesh by convert.py pieces: below the belt a ray-cast shell
(floor, sills, firewall, door walls, trunk; above the belt the body's reversed paint faces are the inside), front
buckets, rear bench, dash, 15.4" screen, steering wheel, console, trunk sill plate and bin lid (user-approved
2026-10-24), a sedan's parcel shelf (PARCEL). Shell faces in a door opening carry the door in UV1 v: the shader drops
them while that door is open or removed (MinidoracatTesla_vehicle.frag, Liftgate.syncShell). The Sketchfab model's own
interior is not used (user 2026-10-25). Mesh coords (centred; Model Y ground z -0.748)."""
import math
import bmesh, bpy
import numpy as np
from mathutils import Matrix, Vector
import pzveh as pv

NAME, CABIN_CELLS, CABIN_UV1_U = pv.NAME, pv.CABIN_CELLS, pv.CABIN_UV1_U
SHELL_DOORS = ("DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight", "TrunkDoor")
CABIN_INSET = 0.05        # grid: the shell sits this far inside the surface its ray hit (door slab 0.06)
TRUNK_DROP = 0.03         # grid: trunk floor below the tailgate opening's lower edge; the sill plate fills it
CABIN_RES = (0.062, 49)   # shell: ring step along y (grid), rays per ring (200 -> -20 deg round the axis)
# the car's cabin layout (cars/<car>.py): floor, shell front wall, trunk floor start, shell ray axis, B-pillar ring
# clearance, seats (pzveh.geometry's passengers), dash / screen / steering wheel, door cards
CABIN_FLOOR, CABIN_FRONT_Y, TRUNK_Y, CABIN_ZC, SEAM_CLEAR = (pv.CAR[k] for k in (
    "CABIN_FLOOR", "CABIN_FRONT_Y", "TRUNK_Y", "CABIN_ZC", "SEAM_CLEAR"))
SEAT, DASH, DOOR_CARD, SEATS, PARCEL = pv.SEAT, pv.CAR["DASH"], pv.CAR["DOOR_CARD"], pv.CAR["SEATS"], pv.CAR["PARCEL"]
SEAT_X, SEAT_Z = SEAT["x"], SEAT["z"]


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


def door_card(bvh, side, ys, belt, kind):
    """Door card details on a side door's inner panel (mesh coords, shut pose): one rounded box per DOOR_CARD entry,
    bent along y to stay on the panel where rays from the cabin axis meet it every 8 cm (`bvh`: the door piece; the
    door curves gently in plan), one bevel segment (about 100 triangles a strip). side: -1 left, +1 right; ys: (rear, front) y of the card. -> object (UV1 cabin cells, v 0)."""
    rear, front = ys
    V, F, cells, nv = [], [], [], 0
    for name, at, pos, dz, ln, h, dep, cell, r in DOOR_CARD[kind]:
        if at == "end":
            y0, y1 = rear + pos[0], front - pos[1]
        elif at == "rear":
            y0, y1 = rear + pos, rear + pos + ln
        else:
            y0, y1 = front - pos - ln, front - pos
        z = belt + dz
        n = max(1, int(round((y1 - y0) / 0.08)))
        sy = np.linspace(y0, y1, n + 1)
        sx = []
        for y in sy:
            hit = bvh.ray_cast(Vector((0, y, z)), Vector((side, 0, 0)))[0]
            if hit is None:
                raise SystemExit(f"door card {kind} {name}: no inner panel at y {y:.3f} z {z:.3f}")
            sx.append(hit.x)
        v, f = rbox((dep, y1 - y0, h), min(r, dep / 2.2, h / 2.2, (y1 - y0) / 2.2), cuts=(0, n - 1, 0), seg=1)
        v += [0, (y0 + y1) / 2, z]
        v[:, 0] += np.interp(v[:, 1], sy, sx) - side * (dep / 2 - 0.004)
        F += [[k + nv for k in fc] for fc in f]
        V.append(v)
        nv += len(v)
        cells += [cell] * len(f)
    return cell_object(NAME + "_DoorCard", np.concatenate(V), F, cells)


def cell_object(name, V, F, cells):
    """Smooth-shaded triangle mesh object, UV0 zero, UV1 = (CABIN_UV1_U - cell, 0), free corner normals."""
    me = bpy.data.meshes.new(name)
    me.from_pydata(np.asarray(V).tolist(), [], F)
    names = list(CABIN_CELLS)
    me.polygons.foreach_set("material_index", np.array([names.index(c) for c in cells], np.int64))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(me)
    bm.free()
    ci = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("material_index", ci)
    me.uv_layers.new(name="UV0").data.foreach_set("uv", np.zeros(len(me.loops) * 2))
    uv1 = np.stack([CABIN_UV1_U - np.repeat(ci, 3), np.zeros(3 * len(ci))], 1)
    me.uv_layers.new(name="UV1").data.foreach_set("uv", uv1.ravel())
    me.polygons.foreach_set("material_index", np.zeros(len(me.polygons), np.int64))
    me.update()
    cn = np.empty(len(me.loops) * 3, np.float32)
    me.corner_normals.foreach_get("vector", cn)
    me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", cn)
    me.attributes.new("liner", "BOOLEAN", "FACE")
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def parcel_shelf(add, bvh):
    """A sedan's parcel shelf (PARCEL) between the cabin and the trunk: a slab `t` thick with its top at `z`, from the
    rear backrests' top (y[0]) back to the rear window's foot (y[1]), out to the body's sides less `inset` (a ray each
    side at n stations: the C pillars close in). The ray shell cannot give it: its faces look at the ray axis, so a
    shell clamped to a ceiling faces down and is culled from above, through the rear window (prototype
    prototype/model3-parcel-1028, scripts/blender/skf/proto_parcel.py)."""
    p = PARCEL
    zt, zb = p["z"], p["z"] - p["t"]
    V, F = [], []
    for i, y in enumerate(np.linspace(*p["y"], p["n"])):
        o = Vector((0, y, (zt + zb) / 2))
        d = [h[3] for b in (bvh["body"], bvh["door"]) for s in (-1, 1) for h in (b.ray_cast(o, Vector((s, 0, 0))),)
             if h[0] is not None]
        if not d:
            raise SystemExit(f"parcel shelf: no body beside y {y:.3f}")
        h = min(d) - p["inset"]
        V += [(-h, y, zt), (h, y, zt), (-h, y, zb), (h, y, zb)]
        if i:
            a, b = 4 * (i - 1), 4 * i
            F += [[a, a + 1, b + 1, b], [a + 2, b + 2, b + 3, a + 3], [a, b, b + 2, a + 2], [a + 1, a + 3, b + 3, b + 1]]
    F += [[0, 2, 3, 1], [len(V) - 4, len(V) - 3, len(V) - 1, len(V) - 2]]   # ends
    add(V, F, "dash", smooth=False)


def cabin_mesh(bvh, belt, trunk_floor, trunk_end, arch, opening):
    """Cabin and trunk (mesh coords, centred), smooth-shaded rounded parts: below the belt a shell CABIN_INSET inside
    the body and the doors (floor, sills, firewall, door walls, the trunk's sides and wheel-arch humps, its rear wall
    behind the tailgate's inner panel at `trunk_end`; none behind glass, so the far windows stay see-through), the
    floor at CABIN_FLOOR, behind the rear backrests (TRUNK_Y) at `trunk_floor`; Model Y front
    buckets (cushion and backrest side bolsters, curved backrest, integrated headrest), rear bench (three cushions and
    backs, three headrests), dash with its trim strip, 15.4" centre screen (lit face to the seats), steering wheel,
    centre console, the trunk's sill plate and its under-floor bin lid. Every shell face looks at the axis: from outside
    the near wall is a back face (culled: an open door shows the seats, the open tailgate the trunk) and the far wall
    stands in for the far door's inner panel (it sits inside it), which the near window, drawn first, would hide by
    depth. `bvh`: "body" / "glass" / "door" surfaces in Blender axes; `belt`: mesh z of the belt line; `opening`: the
    door openings (convert.py build_cabin) for the shell faces the shader drops while a door is open (UV1 v, see below)."""
    V, F, cell, flat, dk, shell_n = [], [], [], [], [], 0

    def add(v, f, c, smooth=True, door=0):
        n = sum(len(x) for x in V)
        V.append(np.asarray(v, float))
        F.extend([[i + n for i in fc] for fc in f])
        cell.extend([c] * len(f) if isinstance(c, str) else c)
        flat.extend([not smooth] * len(f))
        dk.extend([door] * len(f) if isinstance(door, int) else door)

    # shell: rings across y (one on each side door's y cut, so no face straddles two openings), rays from the axis;
    # each ray keeps what it hit first (body / glass / door). The B-pillar ring follows the slanted door seam
    # (opening["seam"], y of z; 4 cm of lean): a flat cut left a 4 cm sliver of wall in one opening and a gap in the
    # other, so its neighbours keep SEAM_CLEAR off it
    step, na = CABIN_RES
    ys = np.append(np.arange(CABIN_FRONT_Y, trunk_end + step / 2, -step), trunk_end)
    clear = np.array([step / 3, SEAM_CLEAR, step / 3])
    ys = np.sort(np.concatenate([ys[(np.abs(ys[:, None] - opening["y"]) > clear).all(1)], opening["y"]]))[::-1]
    ring = {k: int(np.argmin(np.abs(ys - y))) for k, y in zip(("front", "bpil", "rear"), opening["y"])}
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
    side_v = np.abs(pts[ring["bpil"], :, 0]) > 0.3             # B-pillar ring onto the seam (side walls only)
    pts[ring["bpil"], side_v, 1] = opening["seam"](pts[ring["bpil"], side_v, 2])
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
    # the face's door: a side door's when it lies on that door's side (where the rays hit it) between its rings; the
    # tailgate's when a rim corner hit it (the fans' axis corner hits nothing). The exact edge is per pixel: UV1 v
    # carries a distance to the opening's sill / arch / lower edge (below)
    span = {1: (ring["front"], ring["bpil"]), 2: (ring["front"], ring["bpil"]), 3: (ring["bpil"], ring["rear"]),
            4: (ring["bpil"], ring["rear"])}
    side = {k: np.sign(pts[..., 0][who == k].mean()) for k in span if (who == k).any()}
    door = []
    for f in sf:
        p = sv[f]
        ri = [x // n for x in f if x < nr * n]
        k = next((k for k in side if abs(p[:, 0].mean()) > 0.3 and np.sign(p[:, 0].mean()) == side[k]
                  and len(ri) == 3 and span[k][0] <= min(ri) and max(ri) <= span[k][1]), 0)
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
    shell_n = len(sf) + len(hump)

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

    # seats where pzveh.geometry puts the passengers: middle of the door opening minus SEAT["back"]
    yf, yb, yr = opening["y"]
    seat_y = ((yf + yb) / 2 - SEAT["back"][0], (yb + yr) / 2 - SEAT["back"][1])
    z0 = SEAT_Z
    fs, rs = SEATS["front"], SEATS["rear"]              # widths, backrest heights, recline (deg)
    for s in (-1, 1):                                   # front buckets
        cx, fy = s * SEAT_X, seat_y[0]
        rec = (fy - 0.11, z0 - 0.03, fs["recline"])
        part((0.30, 0.30, z0 - 0.10 - CABIN_FLOOR), 0.02, "base", (cx, fy + 0.05, (z0 - 0.10 + CABIN_FLOOR) / 2), seg=1)
        part((fs["w"], 0.40, 0.09), 0.035, "seat", (cx, fy + 0.08, z0 - 0.06), cuts=(2, 0, 0), sag=0.025)
        part((fs["w"], 0.11, fs["back"]), 0.04, "seat", (cx, fy - 0.17, z0 + 0.22), cuts=(2, 0, 0), bend=0.05, taper=0.12,
             tilt=rec)
        part((0.25, 0.10, 0.17), 0.05, "seat", (cx, fy - 0.18, z0 + 0.54), taper=0.1, tilt=rec, seg=3)
        for e in (-1, 1):
            part((0.07, 0.34, 0.07), 0.03, "seat", (cx + e * 0.185, fy + 0.07, z0 - 0.01))
            part((0.07, 0.13, 0.32), 0.03, "seat", (cx + e * 0.19, fy - 0.11, z0 + 0.15), tilt=rec)
    ry = seat_y[1]                                      # rear bench: three cushions, three backs, three headrests
    rec = (ry - 0.11, z0 - 0.03, rs["recline"])
    part((rs["base"], 0.36, z0 - 0.10 - CABIN_FLOOR), 0.02, "base", (0, ry + 0.06, (z0 - 0.10 + CABIN_FLOOR) / 2), seg=1)
    for cx, wd in rs["cushions"]:                       # (centre x, width)
        part((wd, 0.40, 0.09), 0.035, "seat", (cx, ry + 0.08, z0 - 0.06), cuts=(1, 0, 0), sag=0.015)
        part((wd, 0.11, rs["back"]), 0.04, "seat", (cx, ry - 0.17, z0 + 0.19), cuts=(1, 0, 0), bend=0.02, tilt=rec)
        part((0.20 if cx else 0.17, 0.09, 0.12), 0.045, "seat", (cx, ry - 0.18, z0 + 0.48), tilt=rec, seg=3)
    part((0.20, 0.80, 0.22), 0.04, "console", DASH["console"])                  # centre console
    part((1.24, 0.34, 0.16), 0.06, "dash", DASH["dash"])                        # dash, trim strip on its face
    part((1.16, 0.02, 0.035), 0.008, "trim", DASH["trim"])
    part((1.10, 0.012, 0.006), 0.002, "screen", DASH["light"], seg=1)          # ambient light line under the trim
    # trunk: sill plate over the opening's lower edge (the floor ends TRUNK_DROP under it, CABIN_INSET short of the
    # tailgate's inner panel) and the under-floor bin's lid (SEATS sill / bin: width, depth)
    if SEATS["sill"]:                                   # (a pickup's cabin has no trunk)
        (sw, sd), (bw, bd) = SEATS["sill"], SEATS["bin"]
        part((sw, sd, TRUNK_DROP + 0.005), 0.01, "base", (0, trunk_end + 0.02, trunk_floor + TRUNK_DROP / 2), seg=1)
        part((bw, bd, 0.012), 0.004, "console", (0, (TRUNK_Y + trunk_end) / 2 - 0.04, trunk_floor + 0.006), seg=1)
    if PARCEL:
        parcel_shelf(add, bvh)
    part((0.05, 0.04, 0.09), 0.012, "screen_back", DASH["stand"])               # screen stand
    v, f = rbox((0.30, 0.022, 0.19), 0.012)                                       # 15.4" landscape screen
    v = v @ rot_x(-12).T + DASH["screen"]
    fn = np.array([np.cross(v[fc[1]] - v[fc[0]], v[fc[2]] - v[fc[0]]) for fc in f])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True)
    add(v, f, ["screen" if k < -0.9 else "screen_back" for k in fn[:, 1]])
    # its picture in blocks just in front of the lit face (one flat light panel before, user image 12): the dark dock
    # along the bottom, the car view on the driver's third (dark ground, the car a lit block), a route line on the map
    for size, at, c in (((0.296, 0.003, 0.026), (0, -0.0125, -0.080), "screen_back"),
                        ((0.100, 0.003, 0.160), (-0.098, -0.0125, 0.012), "console"),
                        ((0.034, 0.003, 0.070), (-0.098, -0.0140, 0.020), "seat"),
                        ((0.120, 0.003, 0.006), (0.050, -0.0125, 0.020), "trim"),
                        ((0.006, 0.003, 0.060), (0.110, -0.0125, 0.047), "trim")):
        v, f = rbox(size, 0.001, seg=1)
        add((v + at) @ rot_x(-12).T + DASH["screen"], f, c)
    # steering wheel in front of the driver, tilted 70 deg back from horizontal: rim torus, hub, three spokes, column
    wr = Matrix.Translation((-SEAT_X, *DASH["wheel"])) @ Matrix.Rotation(math.radians(70), 4, "X")
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
