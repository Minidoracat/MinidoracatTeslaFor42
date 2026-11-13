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
FRONT_X = SEAT.get("front_x", SEAT_X)   # optional: the front row's side x (passengers, buckets, wheel, mats); default x
DASH_BOX = ((1.24, 0.34, 0.16), 0.06)   # dash: full size (x, y, z), edge radius; centre DASH["dash"]
COLUMN_IN, COLUMN_EDGE, COLUMN_MAX_DEG = 0.02, 0.02, 10.0


def column_ends():
    """Steering column (mesh coords): from the wheel's hub to a point COLUMN_IN inside the dash's rear face, at the
    height where the wheel's axis meets that face, kept COLUMN_EDGE inside the dash's height. -> (hub, end, degrees
    off the wheel's axis). SystemExit when the end is not inside the dash or the column turns more than
    COLUMN_MAX_DEG off the axis (then the wheel's tilt or a column shroud is the call, not a bent column)."""
    (_, dy, dz), r = DASH_BOX
    cx, cy, cz = DASH["dash"]
    hub = np.array([-FRONT_X, *DASH["wheel"]])
    axis = np.array([0, math.sin(math.radians(70)), -math.cos(math.radians(70))])   # the wheel's local -z (70 deg)
    face = cy - dy / 2
    z = hub[2] + axis[2] * (face - hub[1]) / axis[1]
    end = np.array([hub[0], face + COLUMN_IN, min(max(z, cz - dz / 2 + COLUMN_EDGE), cz + dz / 2 - COLUMN_EDGE)])
    ang = math.degrees(math.acos(np.clip((end - hub) @ axis / np.linalg.norm(end - hub), -1, 1)))
    q = np.abs(end - DASH["dash"]) - (np.array(DASH_BOX[0]) / 2 - r)               # rounded box: inside when <= 0
    depth = r - np.linalg.norm(np.maximum(q, 0)) - min(q.max(), 0)                  # mm into the dash's surface
    if depth <= 0 or ang > COLUMN_MAX_DEG:
        raise SystemExit(f"cabin: steering column end {np.round(end, 3)} {depth * 1000:.0f} mm into the dash, "
                         f"{ang:.1f} deg off the wheel's axis (max {COLUMN_MAX_DEG}): DASH wheel / dash")
    print(f"COLUMN {NAME} length {np.linalg.norm(end - hub):.3f} angle {ang:.1f} deg, end {depth * 1000:.0f} mm "
          "into the dash")
    return hub, end, ang


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


TRUNK_SLOTS = (3, 2, 6)    # trunk_walls: rays on the arch hump's inner wall, on its top, on the outer wall up to the top


def trunk_walls(pts, kind, who, ys, lim, belt, trunk_floor, arch, y0, y1=None, trunk=True, lining=True, inside=False):
    """TRUNK_WALL (a hatch: light and dark bands and teeth on the far trunk wall through the open tailgate, user
    2026-11-01). On the ray grid the rear arch hump's step fell between different rays from ring to ring and the wall's
    top was cut cell by cell at the belt: a saw-tooth of up- and side-facing cells, and over it the body's own inside
    (quarter panel, pillar). Behind y0 (the rear doors' rear edge; the rings ahead are the doors') each side's rays from
    the floor up to the wall's top become one profile with TRUNK_SLOTS rays per feature, so a ray index stays on its
    feature along the car: the hump's inner wall (x_in: the rays' median), its flat top on the arch circle (`arch`,
    offset to where the rays found it), the outer wall (the rays' hits, by height) up to the top line: two lines fitted
    along y to where the rays stop hitting body, the one over the belt (never under it) and the one under it towards
    the tailgate's side edges, whichever is lower. The rays above keep their order over the slots left (the tailgate's
    inner panel keeps its door code), body hits over the top go. y1 (the B-pillar ring, REAR_DOOR_WALL): the rings
    from there back to y0 too, the rear door's inner panel part of the wall, its top the belt (the hump in the door
    opening stays when the door opens, inside the arch circle: the same saw-tooth through it, user 2026-11-01);
    trunk False: only those. lining False (GATE_LINING): the tailgate's inner panel over the top goes too (a liftgate
    from the roof whose panel runs far down the sides, Model S: the rows found it 1 to 8+ rays long, so a slot was panel
    in one ring, glass in the next, and the shader keeps the panel's code under GATE_Z with the gate open: spikes over
    the wall's top, user 2026-11-01). inside True (TRUNK_WALL_INSIDE): over the outer wall's last hit its slots
    are pulled along their rays onto the chords between this side's hits (they held the last hit's x up to the top
    line, outside a body that tapers in there: Model Y L, a 42 mm nub at the spoiler's root, 2026-11-12). In place."""
    n = pts.shape[1]
    m, (na, nb, nc) = (n - 2) // 2, TRUNK_SLOTS
    k = na + nb + nc
    rows = [i for i, y in enumerate(ys) if y < (y0 if y1 is None else y1) - 1e-6 and (trunk or y > y0 - 1e-6)]
    floor = {i: CABIN_FLOOR if ys[i] > TRUNK_Y else trunk_floor for i in rows}
    dr = {i for i in rows if ys[i] > y0 - 1e-6}         # rear door rings: its inner panel is wall
    sides = [(list(range(1, m + 1)), 0), (list(range(n - 2, n - 2 - m, -1)), n - 1)]   # rays from the floor up, extra
    wall = {}                                                                         # floor point
    for i in rows:
        ok = ("body", "floor", "door") if i in dr else ("body", "floor")
        for js, _ in sides:
            s = next((t for t, j in enumerate(js) if kind[i, j] not in ok), m)
            wall[i, js[0]] = s, np.abs(pts[i, js[:s], 0]), pts[i, js[:s], 2]
    dy2 = lambda y: arch[2] ** 2 - (y - arch[0]) ** 2                          # noqa: E731
    circle = lambda y: arch[1] + math.sqrt(dy2(y)) if dy2(y) > 0 else -9.0     # noqa: E731
    hrow = [(i, j0) for (i, j0), (s, x, z) in wall.items() if s and circle(ys[i]) > floor[i] + 0.03]
    x_in = float(np.median([wall[w][1][0] for w in hrow])) if hrow else None
    off = []
    for w in hrow:                      # the step: the last ray on the inner wall, the next one's height
        s, x, z = wall[w]
        t = next((t for t in range(s) if abs(x[t] - x_in) > 0.03), s)
        if 0 < t < s:
            off.append((z[t - 1] + z[t]) / 2 - circle(ys[w[0]]))
    off = float(np.median(off)) if off else -CABIN_INSET
    stops = [(ys[i], z.max()) for (i, _), (s, x, z) in wall.items() if s and i not in dr]
    fit = lambda p: np.polyfit(*np.array(p).T, 1) if len({y for y, _ in p}) > 1 else None   # noqa: E731
    hi, lo = fit([p for p in stops if p[1] >= belt - 0.01]), fit([p for p in stops if p[1] < belt - 0.01])
    top = lambda y: min(belt if hi is None else max(belt, np.polyval(hi, y)),          # noqa: E731
                        9.0 if lo is None else np.polyval(lo, y))
    def hull(px, pz, H):                # (px, pz) onto the first chord between the hits H its ray from the axis crosses
        u = np.array([px, pz - CABIN_ZC])
        r = float(np.hypot(*u))
        u /= r
        A = np.c_[np.abs(H[:, 0]), H[:, 2] - CABIN_ZC]
        D, A = A[1:] - A[:-1], A[:-1]
        den = u[0] * D[:, 1] - u[1] * D[:, 0]
        den = np.where(np.abs(den) < 1e-12, np.nan, den)
        s, t = (A[:, 0] * u[1] - A[:, 1] * u[0]) / den, (A[:, 0] * D[:, 1] - A[:, 1] * D[:, 0]) / den
        t = t[(s >= 0) & (s <= 1) & (t > 0)]
        return (px, pz) if not len(t) or r <= t.min() else (u[0] * t.min(), CABIN_ZC + u[1] * t.min())

    for i in rows:
        f = floor[i]
        zt = max(belt if i in dr else top(ys[i]), f + 0.02)
        for js, j0 in sides:
            s, x, z = wall[i, js[0]]
            ws = who[i, js[:s]]
            dw = int(np.bincount(ws[ws > 0]).argmax()) if (ws > 0).any() else 0   # the door's number stays on its wall
            if not s:                                   # no wall: the floor corner
                x, z = np.abs(pts[i, j0, :1]), np.array([f])
            out = x > (x_in or 0) + 0.04
            xo, zo = (x[out], z[out]) if out.any() else (x[-1:], z[-1:])
            fl = zo <= f + 1e-4                             # on the floor: the outermost; then each a new height
            if fl.any():                                    # (the wall turning in)
                xo, zo = np.r_[xo[fl].max(), xo[~fl]], np.r_[f, zo[~fl]]
            up = zo > np.maximum.accumulate(np.r_[-9.0, zo[:-1]])
            xo, zo = xo[up], zo[up]
            zh = min(max(circle(ys[i]) + off, f), zt) if x_in else f
            # FLOOR_IN (Model 3): the floor corner that much in (straight under the wall's lowest hit it stood out
            # through the sill's undercut under the rear doors: a 1 px black dash in game)
            xc = x_in if zh > f + 1e-3 else float(np.interp(f, zo, xo)) - pv.CAR.get("FLOOR_IN", 0.0)
            xh = float(np.interp(zh, zo, xo)) - (pv.CAR.get("FLOOR_IN", 0.0) if zh <= f + 1e-3 else 0.0)
            prof = ([(xc, f + (zh - f) * t / na) for t in range(na + 1)]
                    + [(xc + (xh - xc) * t / nb, zh) for t in range(1, nb + 1)]
                    + [(float(np.interp(zh + (zt - zh) * t / nc, zo, xo)), zh + (zt - zh) * t / nc)
                       for t in range(1, nc + 1)])
            if inside:                                      # this side's rays untouched yet (the other side's differ)
                prof[-nc:] = [hull(px, pz, pts[i, js]) if pz > zo[-1] + 1e-6 else (px, pz) for px, pz in prof[-nc:]]
            src = js[s:]                                    # the rays above the wall onto the slots left
            P, K, W = pts[i, src].copy(), kind[i, src].copy(), who[i, src].copy()
            sgn = -1 if j0 == 0 else 1
            for t, (px, pz) in enumerate(prof):
                j = j0 if t == 0 else js[t - 1]
                pts[i, j] = (sgn * px, ys[i], pz)
                kind[i, j], who[i, j], lim[i, j] = ("floor" if pz <= f + 1e-4 else "body"), dw, zt + 1e-6
            for t, j in enumerate(js[k:]):
                if not len(src):
                    pts[i, j], kind[i, j] = pts[i, js[k - 1]], "none"
                    continue
                q = round(t * (len(src) - 1) / max(m - k - 1, 1))
                pts[i, j], kind[i, j], who[i, j] = P[q], K[q], W[q]
                if P[q][2] > zt + 1e-3 and (K[q] == "body" or (not lining and K[q] == "door" and W[q] == 5
                                                               and i not in dr)):
                    kind[i, j] = "none"
    print(f"CABIN trunk walls: x_in {x_in or 0:.3f}, hump {off:+.3f} on the arch circle ({len(hrow)} sides), top",
          [round(float(belt if i in dr else top(ys[i])), 3) for i in rows])

# the cabin detail model (detail_mesh; drawn only under Viewpoint, ViewpointCabin.lua, models.md 8): every furniture
# part GROW larger all round than its coarse twin in the body (which it hides; seat seams and a sag's chords stay under
# 1 mm of it, detail stage check), its bevels FINE x finer; seams SEAM_HALF wide each side, SEAM_PROUD off the face,
# sampled every SEAM_STEP (grid)
GROW, FINE = 0.004, 3
SEAM_HALF, SEAM_PROUD, SEAM_STEP = 0.0016, 0.0012, 0.012


def lay(bvh, origins, d, half, proud):
    """A ribbon on a surface: each origin cast along d onto `bvh`, `half` either side of the line through the hits,
    `proud` off the surface, its faces looking out like the faces hit. -> verts, quads."""
    P, N = [], []
    for o in origins:
        hit, nrm = bvh.ray_cast(Vector(o), Vector(d))[:2]
        if hit is None:
            raise SystemExit(f"cabin detail: nothing from {np.round(o, 3)} along {d}")
        P.append(hit[:])
        N.append(nrm[:])
    P, N = np.array(P), np.array(N)
    side = np.cross(N, np.gradient(P, axis=0))
    side /= np.linalg.norm(side, axis=1, keepdims=True)
    k = len(P)
    V = np.concatenate([P + N * proud + side * half, P + N * proud - side * half])
    F = []
    for i in range(k - 1):
        q = [i, i + 1, k + i + 1, k + i]
        if np.cross(V[q[1]] - V[q[0]], V[q[2]] - V[q[0]]) @ N[i] < 0:
            q.reverse()
        F.append(q)
    return V, F


def channels(across, span, a=0.31):
    """A seat face's stitched channels in face fractions (x, then depth or height): lines across it at `across`
    between the insert's sides at x +-a, and those sides over `span`."""
    return tuple(((-a, b), (a, b)) for b in across) + tuple(((s * a, span[0]), (s * a, span[1])) for s in (-1, 1))


def seam_strips(v, f, c, size, face, lines):
    """Stitched channels on a grown part (local coords, shaped, not yet placed): each line ((a0, b0), (a1, b1)) in
    face fractions ("top": x, y of the +z face; "front": x, z of the +y face) laid on the part as a ribbon (lay),
    cell "stitch". -> v, faces, per-face cells (the part's `c`, then the seams')."""
    from mathutils.bvhtree import BVHTree
    bvh = BVHTree.FromPolygons(v.tolist(), f)
    ax, d = ((0, 1), (0, 0, -1)) if face == "top" else ((0, 2), (0, -1, 0))
    V, F, cells, n = [v], [list(p) for p in f], [c] * len(f), len(v)
    for (a0, b0), (a1, b1) in lines:
        k = max(2, int(round(np.hypot((a1 - a0) * size[ax[0]], (b1 - b0) * size[ax[1]]) / SEAM_STEP)) + 1)
        origins = []
        for t in np.linspace(0, 1, k):
            o = -np.array(d, float)
            o[ax[0]], o[ax[1]] = (a0 + (a1 - a0) * t) * size[ax[0]], (b0 + (b1 - b0) * t) * size[ax[1]]
            origins.append(o)
        rv, rf = lay(bvh, origins, d, SEAM_HALF, SEAM_PROUD)
        V.append(rv)
        F += [[i + n for i in q] for q in rf]
        cells += ["stitch"] * len(rf)
        n += len(rv)
    return np.concatenate(V), F, cells


def furniture(add, opening, grow=0.0, fine=1, between=None):
    """The cabin's furniture (mesh coords), smooth rounded parts: front buckets, rear bench (Model X: its 2nd and 3rd
    row buckets), centre console, dash with its trim strip and light line, the screen on its stand with its picture,
    steering wheel and column; add(v, f, cell or per-face cells) takes each part. between(part) runs after the light
    line (cabin_mesh's trunk plates and parcel shelf: the body's faces keep their order). grow > 0 (detail_mesh): each
    part `grow` larger all round with `fine` x the bevel segments, shaped on its coarse size, so it hides the coarse
    part in the body, stitched channels on the seats; the screen's picture is detail_mesh's then. -> front / rear
    (that row's seat y and z0), wr (the steering wheel's matrix), dash / console (those parts' verts and faces), last
    (the last row's lowest y)."""
    row, out = [], {}

    def box(size, r, cuts=(0, 0, 0), seg=2):
        return rbox(np.add(size, 2 * grow), r + grow, cuts, seg * fine) if grow else rbox(size, r, cuts, seg)

    def part(size, r, c, at, cuts=(0, 0, 0), sag=0.0, bend=0.0, taper=0.0, tilt=None, seg=2, seams=None, fit=None):
        """rbox + shaping: `sag` dips the top's middle (x), `bend` brings the sides forward (+y), `taper` narrows the
        top; `tilt` = (pivot y, pivot z, deg) reclines about a line along x (top to the rear). Shaped on `size`, so a
        grown part follows its coarse one; seams = (face, lines) for seam_strips, grown parts only; `fit(v)` moves the
        placed points last (the trunk sill onto the body's lip)."""
        v, f = box(size, r, cuts, seg)
        x = 2 * v[:, 0] / size[0]
        if sag:
            v[:, 2] -= sag * np.clip(1 - x * x, 0, 1) * (v[:, 2] > 0)
        v[:, 1] += bend * x * x
        v[:, 0] *= 1 - taper * (v[:, 2] / size[2] + 0.5)
        cells = c
        if grow and seams:
            v, f, cells = seam_strips(v, f, c, size, *seams)
        v += at
        if tilt:
            py, pz, deg = tilt
            v = (v - [0, py, pz]) @ rot_x(deg).T + [0, py, pz]
        if fit is not None:
            v = fit(v)
        add(v, f, cells)
        row.append(v)
        return v, f

    # seats where pzveh.geometry puts the passengers: middle of the door opening minus SEAT["back"]
    yf, yb, yr = opening["y"]
    seat_y = ((yf + yb) / 2 - SEAT["back"][0], (yb + yr) / 2 - SEAT["back"][1]) if not SEAT.get("front_only") else \
        ((yf + yb) / 2 - SEAT["back"][0],)
    z0 = SEAT_Z
    fs, rs = SEATS["front"], SEATS.get("rear")         # widths, backrest heights, recline (deg)
    # optional per row: dy / dz move that row's seat (not its passengers) forward / up, to fit the passenger's pose
    # (seat_head.py sit / back numbers; the clips are scripts/seat_anim.py's)
    def bucket(cx, fy, b, bolster=(0.185, 0.19), z0=z0):   # a bucket seat: base, cushion, backrest, headrest, bolsters
        fy, z0 = fy + b.get("dy", 0), z0 + b.get("dz", 0)
        rec = (fy - 0.11, z0 - 0.03, b["recline"])
        # (a cushion on the floor, the Roadster: the base no thinner than 1 cm, under the floor)
        part((0.30, 0.30, max(z0 - 0.10 - CABIN_FLOOR, 0.01)), 0.02, "base", (cx, fy + 0.05, (z0 - 0.10 + CABIN_FLOOR) / 2),
             seg=1)
        part((b["w"], 0.40, 0.09), 0.035, "seat", (cx, fy + 0.08, z0 - 0.06), cuts=(2, 0, 0), sag=0.025,
             seams=("top", channels((-0.28, -0.10, 0.08, 0.26), (-0.40, 0.40))))
        # backrest 8 cm thick, its front where the 11 cm one had it: the knees of the passenger behind (seat_head.py knees)
        part((b["w"], 0.08, b["back"]), 0.035, "seat", (cx, fy - 0.155, z0 + 0.22), cuts=(2, 0, 0), bend=0.05, taper=0.12,
             tilt=rec, seams=("front", channels((-0.30, -0.15, 0.0, 0.15, 0.30), (-0.42, 0.42))))
        part((0.25, 0.10, 0.17), 0.05, "seat", (cx, fy - 0.18, z0 + b.get("head", 0.54)), taper=0.1, tilt=rec, seg=3)
        for e in (-1, 1):
            part((0.07, 0.34, 0.07), 0.03, "seat", (cx + e * bolster[0], fy + 0.07, z0 - 0.01))
            part((0.07, 0.13, 0.32), 0.03, "seat", (cx + e * bolster[1], fy - 0.11, z0 + 0.15), tilt=rec)
        if b.get("arms"):   # (Model Y L 2nd row) an armrest on the aisle side: (height over the cushion, length, width)
            ah, al, aw = b["arms"]
            ax = cx - math.copysign(b["w"] / 2 + aw / 2 + 0.005, cx)
            part((aw, al, 0.05), 0.02, "seat", (ax, fy - 0.115 + al / 2, z0 - 0.04 + ah))
            part((aw * 0.7, 0.07, ah + 0.065), 0.015, "seat", (ax, fy - 0.08, z0 - 0.105 + (ah + 0.065) / 2))
        return fy, z0
    out["front"] = [bucket(s * FRONT_X, seat_y[0], fs) for s in (-1, 1)][0]     # front buckets
    ry, z1 = seat_y[-1], z0 - SEAT.get("rear", 0)      # the 2nd row sits SEAT["rear"] lower (pzveh.geometry, same)
    if SEAT.get("front_only"):  # a two-seater (SEAT front_only, PassengerSeat2): the front row is the last row (`last`
        out["rear"] = out["front"]   # below: its backrests' rear; the detail model's 2nd-row mats then span nothing)
    elif "middle" in SEATS:     # 6 seats (Model X): the 2nd row's two monopost seats, the 3rd row's two `back` behind the
        t3 = SEAT["third"]      # rear doors' rear edge, narrower (pzveh.geometry seats the passengers there)
        for (y_, b, sx, z_) in ((ry, SEATS["middle"], SEAT_X, z1), (yr - t3["back"], SEATS["third"], t3["x"], z0 - t3["drop"])):
            row.clear()
            placed = [bucket(s * sx, y_, b, (b["w"] / 2 - 0.025, b["w"] / 2 - 0.02), z_) for s in (-1, 1)][0]
            out.setdefault("rear", placed)
    else:                       # rear bench: three cushions, three backs, three headrests
        row.clear()
        ry, z1 = ry + rs.get("dy", 0), z1 + rs.get("dz", 0)
        out["rear"] = (ry, z1)
        rec = (ry - 0.11, z1 - 0.03, rs["recline"])
        part((rs["base"], 0.36, z1 - 0.10 - CABIN_FLOOR), 0.02, "base", (0, ry + 0.06, (z1 - 0.10 + CABIN_FLOOR) / 2),
             seg=1)
        for cx, wd in rs["cushions"]:                   # (centre x, width)
            part((wd, 0.40, 0.09), 0.035, "seat", (cx, ry + 0.08, z1 - 0.06), cuts=(1, 0, 0), sag=0.015,
                 seams=("top", channels((-0.20, 0.0, 0.20), (-0.36, 0.36), 0.36)))
            part((wd, 0.11, rs["back"]), 0.04, "seat", (cx, ry - 0.17, z1 + 0.19), cuts=(1, 0, 0), bend=0.02, tilt=rec,
                 seams=("front", channels((-0.25, 0.0, 0.25), (-0.40, 0.40), 0.36)))
            part((0.20 if cx else 0.17, 0.09, 0.12), 0.045, "seat", (cx, ry - 0.18, z1 + 0.48), tilt=rec, seg=3)
    out["last"] = min(v[:, 1].min() for v in row)
    if SEAT.get("front_only") and out["last"] < TRUNK_Y:     # behind the front backrests: the trunk's floor (TRUNK_Y)
        raise SystemExit(f"cabin: the front backrests (y {out['last']:.3f}) reach behind TRUNK_Y {TRUNK_Y}")
    out["console"] = part((0.20, 0.80, 0.22), 0.04, "console", DASH["console"])     # centre console
    out["dash"] = part(*DASH_BOX, "dash", DASH["dash"])                               # dash, trim strip on its face
    part((1.16, 0.02, 0.035), 0.008, "trim", DASH["trim"])
    part((1.10, 0.012, 0.006), 0.002, "screen", DASH["light"], seg=1)          # ambient light line under the trim
    if between:
        between(part)
    part((0.05, 0.04, 0.09), 0.012, "screen_back", DASH["stand"])               # screen stand
    v, f = box((0.30, 0.022, 0.19), 0.012)                                        # 15.4" landscape screen
    v = v @ rot_x(-12).T + DASH["screen"]
    fn = np.array([np.cross(v[fc[1]] - v[fc[0]], v[fc[2]] - v[fc[0]]) for fc in f])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True)
    add(v, f, ["screen" if k < -0.9 else "screen_back" for k in fn[:, 1]])
    # its picture in blocks just in front of the lit face (one flat light panel before, user image 12): the dark dock
    # along the bottom, the car view on the driver's third (dark ground, the car a lit block), a route line on the map
    for size, at, c in ((() if grow else                # the detail model has the picture itself (detail_mesh)
                         (((0.296, 0.003, 0.026), (0, -0.0125, -0.080), "screen_back"),
                          ((0.100, 0.003, 0.160), (-0.098, -0.0125, 0.012), "console"),
                          ((0.034, 0.003, 0.070), (-0.098, -0.0140, 0.020), "seat"),
                          ((0.120, 0.003, 0.006), (0.050, -0.0125, 0.020), "trim"),
                          ((0.006, 0.003, 0.060), (0.110, -0.0125, 0.047), "trim")))):
        v, f = rbox(size, 0.001, seg=1)
        add((v + at) @ rot_x(-12).T + DASH["screen"], f, c)
    # steering wheel in front of the driver, tilted 70 deg back from horizontal: rim torus, hub, three spokes
    wr = out["wr"] = Matrix.Translation((-FRONT_X, *DASH["wheel"])) @ Matrix.Rotation(math.radians(70), 4, "X")
    nu, nv, tube = (20 * fine, 6 * (2 if grow else 1), 0.024 + grow)
    tv = [wr @ Vector(((0.15 + tube * math.cos(b)) * math.cos(a), (0.15 + tube * math.cos(b)) * math.sin(a),
                       tube * math.sin(b)))
          for a in np.linspace(0, 2 * math.pi, nu, endpoint=False) for b in np.linspace(0, 2 * math.pi, nv, endpoint=False)]
    add([p[:] for p in tv], [[i * nv + j, i * nv + (j + 1) % nv, ((i + 1) % nu) * nv + (j + 1) % nv, ((i + 1) % nu) * nv + j]
                             for i in range(nu) for j in range(nv)], "wheel")
    for size, at in (((0.11, 0.09, 0.05), (0, 0, 0)), ((0.26, 0.03, 0.02), (0, -0.02, 0)), ((0.03, 0.13, 0.02), (0, -0.08, 0))):
        v, f = box(size, min(size) * 0.45)
        add([(wr @ Vector(p + np.array(at)))[:] for p in v], f, "wheel")
    # column: from the hub into the dash's rear face (user 2026-11-02 img13: a fixed 0.22 column ended in mid air,
    # 0.06-0.11 short of the dash on every car, over its top on the Cybertruck)
    hub, end, ang = column_ends()
    axis = (end - hub) / np.linalg.norm(end - hub)
    rot = np.c_[(1, 0, 0), np.cross(axis, (1, 0, 0)), axis]          # local z along the column, x stays the car's x
    v, f = box((0.05, 0.05, np.linalg.norm(end - hub)), 0.0225)
    add(v @ rot.T + (hub + end) / 2, f, "wheel")
    return out



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
    ys = ys[ys >= trunk_end]        # a pickup's cabin ends ahead of its rear doors' rear edge (the bed's front wall)
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
    # cells along the trunk's sides, black teeth through the open tailgate: user 2026-10-25); higher cells go.
    lim = np.full(pts.shape[:2], belt)
    if pv.CAR.get("TRUNK_WALL") or pv.CAR.get("REAR_DOOR_WALL"):
        trunk_walls(pts, kind, who, ys, lim, belt, trunk_floor, arch, opening["y"][2],
                    opening["y"][1] if pv.CAR.get("REAR_DOOR_WALL") else None, bool(pv.CAR.get("TRUNK_WALL")),
                    pv.CAR.get("GATE_LINING", True), pv.CAR.get("TRUNK_WALL_INSIDE", False))
    near = (pts[..., 2] <= lim + 0.08) & np.isin(kind, ("body", "door"))
    pts[..., 2] = np.where(near, np.minimum(pts[..., 2], lim), pts[..., 2])
    sv, sf, sc = pts.reshape(-1, 3), [], []
    lv = lim.reshape(-1)
    keep = lambda q: all(kind.flat[x] in ("body", "door", "floor") and sv[x][2] <= lv[x] for x in q)   # noqa: E731
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
    # TRUNK_WALL rings (not the tailgate's faces) turn to the axis at their own y, kept off the rear wall: towards
    # y -1.0, the hump's rear slope and the step at the rear doors' edge turned forward, away from the open tailgate
    y_tw = opening["y"][2] if pv.CAR.get("TRUNK_WALL") else -9.0
    for f in sf:                                        # every shell face looks at the axis, raised to the belt: the
        a, b, c = sv[f[0]], sv[f[1]], sv[f[2]]          # wheel-arch humps' tops sit at the ray axis's height (z -0.10),
        cen = sv[f].mean(0)                             # where turning to it was a coin toss (holes over the arches)
        tw = cen[1] < y_tw and max(f) < nr * n and not (who.flat[f] == 5).any()
        tgt = np.array([0, max(cen[1], trunk_end + 0.12) if tw else min(max(cen[1], -1.0), 0.7), belt])
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
    backs = pv.CAR.get("HUMP_BACKS", True)
    y_hump = {True: 9.0, "trunk": opening["y"][2], False: -9.0}[backs]
    hump = [i for i, (f, k) in enumerate(zip(sf, sc)) if k == "liner" for cen in (sv[f].mean(0),)
            if abs(cen[0]) > 0.3 and np.hypot(cen[1] - arch[0], cen[2] - arch[1]) < arch[2] + 0.15 and cen[1] < y_hump]
    print("CABIN shell triangles", len(sf), "turned to the axis", turned, "two-sided over the rear arches", len(hump),
          "in door openings", {nm: door.count(k + 1) for k, nm in enumerate(SHELL_DOORS)})
    add(sv, sf, sc, smooth=False, door=door)
    # the humps over the rear arches fold on the coarse ray grid (holes through the open tailgate): both sides drawn
    # there, the back copy on its own vertices (the mesh drops a face on the same vertices as another); a pickup's
    # cabin ends ahead of them. In the rear door openings the back copies inside the arch circle (kept with the door
    # open, UV1 d > 0) faced the camera, and the circle's edge ran cell by cell: a staircase of liner cells over the
    # seats through an open rear door and the side windows (user 2026-11-01, Model X). HUMP_BACKS "trunk": only behind
    # the rear doors' rear edge; False: none (a TRUNK_WALL trunk's humps don't fold; its faces turn to the axis at
    # their own y above)
    if hump:
        add(sv[np.ravel([sf[i] for i in hump])], [[3 * k + 2, 3 * k + 1, 3 * k] for k in range(len(hump))], "liner",
            smooth=False, door=[door[i] for i in hump])
    shell_n = len(sf) + len(hump)

    def trunk_plates(part):
        # trunk: sill plate over the opening's lower edge (the floor ends TRUNK_DROP under it, CABIN_INSET short of the
        # tailgate's inner panel) and the under-floor bin's lid (SEATS sill / bin: width, depth); an optional third
        # sill value fits the plate's rear half that far inside the body or the shut lid behind it (rays back from the
        # plate's middle, 24 loops across): Model 3's lip curves forward to the corners, and a square plate deep enough
        # to close the lip stuck out of the rear face at the trunk lid's lower corners (2026-11-12)
        if SEATS["sill"]:                               # (a pickup's cabin has no trunk)
            (sw, sd, *fit), (bw, bd) = SEATS["sill"], SEATS["bin"]
            yc = trunk_end + 0.02

            def to_lip(v):
                for i in np.nonzero(v[:, 1] < yc)[0]:
                    o = Vector((v[i, 0], yc, v[i, 2]))
                    hs = [h.y for h in (bvh[k].ray_cast(o, Vector((0, -1, 0)), 1.0)[0] for k in ("body", "door")) if h]
                    if hs:
                        v[i, 1] = max(v[i, 1], max(hs) + fit[0])
                return v
            part((sw, sd, TRUNK_DROP + 0.005), 0.01, "base", (0, yc, trunk_floor + TRUNK_DROP / 2), seg=1,
                 **(dict(cuts=(24, 0, 0), fit=to_lip) if fit else {}))
            part((bw, bd, 0.012), 0.004, "console", (0, (TRUNK_Y + trunk_end) / 2 - 0.04, trunk_floor + 0.006), seg=1)
        if PARCEL:
            parcel_shelf(add, bvh)

    if furniture(add, opening, between=trunk_plates)["last"] < trunk_end:     # the last row stays ahead of the wall
        raise SystemExit(f"cabin: the rear seats cross the rear wall (y {trunk_end:.3f}): SEAT back / SEATS recline")
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


def cylinder(r, h, n=24):
    """Closed cylinder on the origin along z: radius r, height h, n sides. -> verts, faces."""
    a = np.linspace(0, 2 * math.pi, n, endpoint=False)
    ring = np.c_[r * np.cos(a), r * np.sin(a), np.zeros(n)]
    V = np.concatenate([ring - [0, 0, h / 2], ring + [0, 0, h / 2]])
    return V, [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)] + [list(range(n))[::-1], list(range(n, 2 * n))]


def rot_z(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def detail_mesh(opening, windscreen):
    """The cabin detail model (part CabinDetail, model Detail; drawn only under Project Viewpoint, ViewpointCabin.lua,
    models.md 8): the furniture grown over the body's coarse parts (furniture grow, seat seams) and what the coarse
    cabin leaves out: the screen's picture, the wheel's scroll wheels and T, the dash's air vent, the console's phone
    pads, cup holders, armrest seam and rear screen, floor mats, the rear-view mirror on the windscreen (windscreen:
    its verts and tris, mesh coords). UV0 = UV1 = the face's cell centre in the shared texture (pzveh.detail_uv), the
    picture's own over DETAIL_PICTURE. Checks that no coarse furniture part pokes out of its grown twin. -> object."""
    from mathutils.bvhtree import BVHTree
    V, F, C, UV, FLAT, RIB, parts = [], [], [], [], [], [], []

    def add(v, f, c, uv=None, flat=False, rib=False):
        """rib: an open ribbon (lay), its faces' side kept (a closed part's are made outward)."""
        n = sum(len(x) for x in V)
        cells = [c] * len(f) if isinstance(c, str) else c
        V.append(np.asarray(v, float))
        F.extend([[i + n for i in fc] for fc in f])
        C.extend(cells)
        UV.append(np.zeros((len(v), 2)) if uv is None else uv)
        FLAT.extend([flat] * len(f))
        RIB.extend([rib or k == "stitch" for k in cells])
        parts.append((V[-1], f, cells))

    placed = furniture(add, opening, GROW, FINE)
    grown = list(parts)
    # the screen's picture: a thin panel just proud of the grown screen and of the coarse picture blocks, its front
    # DETAIL_PICTURE (u along +x: the car view on the driver's side), the rest the screen's black
    pw, ph = 0.302, 0.192
    v, f = rbox((pw, 0.003, ph), 0.0012)
    (u0, v0, u1, v1), e = pv.DETAIL_PICTURE, 0.5 / pv.DETAIL_PX
    uv = np.c_[u0 + e + (v[:, 0] / pw + 0.5) * (u1 - u0 - 2 * e), v0 + e + (v[:, 2] / ph + 0.5) * (v1 - v0 - 2 * e)]
    fn = np.array([np.cross(v[q[1]] - v[q[0]], v[q[2]] - v[q[0]]) for q in f])
    front = fn[:, 1] / np.linalg.norm(fn, axis=1) < -0.9
    add((v + [0, -0.0172, 0]) @ rot_x(-12).T + DASH["screen"], f, ["picture" if k else "screen_back" for k in front], uv)
    # steering wheel: scroll wheels on the cross spoke at the thumbs, a T on the hub (wheel frame: +z to the driver)
    wr = placed["wr"]
    wheel = lambda v, at: [(wr @ Vector(p + np.array(at)))[:] for p in v]   # noqa: E731
    for s in (-1, 1):
        v, f = cylinder(0.010, 0.007, 16)
        add(wheel(v[:, [2, 1, 0]], (s * 0.09, -0.02, 0.01 + GROW + 0.004)), f, "chrome", flat=True)
    for size, at in (((0.034, 0.007, 0.002), (0, 0.013, 0)), ((0.007, 0.030, 0.002), (0, -0.003, 0))):
        v, f = rbox(size, 0.0008, seg=1)
        add(wheel(v, np.add(at, (0, 0, 0.025 + GROW + 0.001))), f, "chrome")
    # the dash's air vent: a dark slot along its cabin face over the trim strip
    dv, df = placed["dash"]
    zv = DASH["trim"][2] + 0.0175 + 0.011
    rv, rf = lay(BVHTree.FromPolygons(dv.tolist(), df), [(x, DASH["dash"][1] - 1.0, zv) for x in np.linspace(-0.55, 0.55, 45)],
                 (0, 1, 0), 0.0035, 0.001)
    add(rv, rf, "vent", rib=True)
    # console: two phone pads at the front, two cup holders behind them, the armrest lid's seam; the rear screen
    cx, cy, cz = DASH["console"]
    top, nose = cz + 0.11 + GROW, cy + 0.40
    for s in (-1, 1):
        v, f = rbox((0.050, 0.12, 0.003), 0.0012, seg=1)
        add(v + [s * 0.03, nose - 0.11, top + 0.0012], f, "screen_back")
        v, f = cylinder(0.028, 0.003, 24)                # (flat: smooth caps read as domes, not holes)
        add(v + [s * 0.03, nose - 0.27, top + 0.0012], f, "vent", flat=True)
    v, f = rbox((0.15, 0.004, 0.002), 0.0008, seg=1)
    add(v + [cx, nose - 0.38, top + 0.0008], f, "screen_back")
    v, f = rbox((0.13, 0.004, 0.075), 0.0015, seg=1)
    add(v + [cx, cy - 0.40 - GROW - 0.0018, cz + 0.03], f, "screen")
    # floor mats: in front of each front seat to under the dash, and in front of each 2nd-row seat to the front seats
    fy, ry = placed["front"][0], placed["rear"][0]
    for y0, y1, sx in ((fy + 0.30, min(fy + 0.74, CABIN_FRONT_Y - 0.10), FRONT_X), (ry + 0.30, fy - 0.12, SEAT_X)):
        for s in (-1, 1):
            if y1 - y0 > 0.12:
                v, f = rbox((0.40, y1 - y0, 0.008), 0.004, seg=1)
                add(v + [s * sx, (y0 + y1) / 2, CABIN_FLOOR + 0.004], f, "mat")
    # rear-view mirror: 6.5 cm under the windscreen's top on the centre line (no higher than 33 cm over the dash: Model
    # X's windscreen runs over the heads), turned 12 deg to the driver, on a stem square to the glass
    wv, wt = windscreen
    wb = BVHTree.FromPolygons(wv.tolist(), wt.tolist())
    zm = min(wv[np.abs(wv[:, 0]) < 0.08][:, 2].max() - 0.065, DASH["dash"][2] + 0.08 + 0.33)
    hit, nrm = wb.ray_cast(Vector((0, DASH["dash"][1] - 0.6, zm)), Vector((0, 1, 0)))[:2]
    if hit is None:
        raise SystemExit(f"cabin detail: no windscreen in front of the mirror (z {zm:.3f})")
    ym = hit.y - 0.06
    for size, r, at, c in (((0.165, 0.024, 0.050), 0.010, (0, 0, 0), "mirror"),
                           ((0.152, 0.003, 0.040), 0.0012, (0, -0.0132, 0), "mirror_glass")):
        v, f = rbox(size, r)
        add((v + at) @ rot_z(-12).T + [0, ym, zm], f, c)
    back = np.array([0, ym + 0.010, zm])
    d = np.array(nrm[:]) * (1 if nrm.y > 0 else -1)                       # into the glass, square to it
    end = wb.ray_cast(Vector(back), Vector(d))[0]
    if end is None:                                                       # (the glass's top edge: straight ahead)
        d, end = np.array([0.0, 1.0, 0.0]), hit
    ln = (np.array(end[:]) - back) @ d - 0.001
    v, f = rbox((0.018, ln, 0.012), 0.004)
    q = np.array(Vector((0, 1, 0)).rotation_difference(Vector(d)).to_matrix())
    add(v @ q.T + back + d * ln / 2, f, "mirror")

    # no coarse part pokes out of its grown twin: furniture adds them in the same order, the coarse picture blocks
    # (5, after the screen) aside; signed distance of each coarse vertex to its twin's surface, the twin's normals made
    # outward first (furniture leaves the wheel rim's to cabin_mesh), seams aside
    coarse = []
    furniture(lambda v, f, c, **_: coarse.append(np.asarray(v, float)), opening)
    k = next(i for i, (_, _, c) in enumerate(grown) if "screen" in c and "screen_back" in c)
    coarse = coarse[:k + 1] + coarse[k + 6:]
    worst = (-1.0, None)
    for cv, (gv, gf, gc) in zip(coarse, grown):
        bm = bmesh.new()
        bv = [bm.verts.new(p) for p in gv]
        for p, c in zip(gf, gc):
            if c != "stitch":
                bm.faces.new([bv[i] for i in p])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        b = BVHTree.FromBMesh(bm)
        bm.free()
        for p in cv:
            loc, n = b.find_nearest(Vector(p))[:2]
            s = (Vector(p) - loc).dot(n)
            if s > worst[0]:
                worst = (s, np.round(p, 3))
    if len(coarse) != len(grown) or worst[0] > -0.0005:
        raise SystemExit(f"cabin detail: a coarse part is {worst[0] * 1000:+.1f} mm off its grown twin's surface at "
                         f"{worst[1]} ({len(coarse)} coarse parts, {len(grown)} grown)")
    print(f"DETAIL coarse furniture inside the grown: worst {worst[0] * 1000:+.2f} mm at {worst[1]}")

    names = list(pv.DETAIL_RGB) + ["picture"]
    me = bpy.data.meshes.new(NAME + "_Detail")
    me.from_pydata(np.concatenate(V).tolist(), [], F)
    me.polygons.foreach_set("material_index", np.array([names.index(c) for c in C], np.int64))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=[f for f, rib in zip(bm.faces, RIB) if not rib])
    for f, flat in zip(bm.faces, FLAT):
        f.smooth = not flat
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    ci = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("material_index", ci)
    vi = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", vi)
    cells = np.repeat(ci, [p.loop_total for p in me.polygons])
    uv = np.array([pv.detail_uv(c) for c in names[:-1]] + [(0, 0)])[cells]
    pic = cells == len(names) - 1
    uv[pic] = np.concatenate(UV)[vi[pic]]
    for nm in ("UV0", "UV1"):
        me.uv_layers.new(name=nm).data.foreach_set("uv", uv.ravel())
    me.polygons.foreach_set("material_index", np.zeros(len(me.polygons), np.int64))
    me.update()
    cn = np.empty(len(me.loops) * 3, np.float32)
    me.corner_normals.foreach_get("vector", cn)
    me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", cn)
    ob = bpy.data.objects.new(NAME + "_Detail", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(bpy.data.materials.new(NAME + "_Detail"))
    print("DETAIL", NAME, "triangles", len(me.polygons), "cells", {c: int((ci == i).sum()) for i, c in enumerate(names)})
    return ob



# ---------------------------------------------------------------- script numbers, previews, verify
