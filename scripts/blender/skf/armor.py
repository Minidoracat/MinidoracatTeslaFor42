"""TeslaArmor's visible kit (model Armor, file <NAME>_Armor; upgrades.md 4): front guard, both sill guards, rear guard
and roof rack in one static mesh in the body's frame (part model offset 0), on the shared palette texture
MinidoracatTesla_Armor (a face's UV0 at its cell's centre, UV1 the same: vehiclewheel reads location 3, models.md 0).

The car's ARMOR (cars/<car>.py) says where each piece goes (heights over the ground, |x|, y, pre-centre like the rest of
the config) and its style; ARMOR_STYLE=<key> builds another style of it. Every piece stands its gap off the surface it
faces, measured by rays on the built body and the shut doors, gate and frunk lid (TMP/skf_doors.blend), so a rebuilt
body moves the kit with it. check() then proves what it must clear: no triangle crosses the body, nor any door, the
gate or the frunk lid at any frame of its clip, nor the tyres over full steering lock and the suspension's travel;
lamps, plates and the charge port lose nothing to it from the game's eight views. It stops the build if any fails.

    "$B" -b --factory-startup --python scripts/blender/skf/convert.py -- armor      # this only, from the built car
"""
import json, math, os, re
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
import pzveh as pv

TEX, TEX_PX, CELL_PX = "MinidoracatTesla_Armor", 64, 16
RGB = {"steel": (46, 47, 50),     # matte black powder-coated steel
       "mount": (30, 30, 32),     # brackets and feet
       "rubber": (18, 18, 19)}    # roof rack foot pads
TRAVEL = 0.10      # wheel travel each way checked (template maxSuspensionTravelCm = 10)
STEER = 0.9        # full lock, rad (BaseVehicle steering clamp the views use, models.md)
MIN_GAP = {"piece": 0.008, "mount": 0.001, "moving": 0.008, "tyre": 0.02}   # grid; 0.008 ~ 1 cm; mounts bolt on
STANDOFF = 0.005  # where a bracket or foot stops off the panel it is bolted to, measured on its own axis


# ---- geometry primitives ----
def circle(r, n):
    return [(r * math.cos(2 * math.pi * (k + 0.5) / n), r * math.sin(2 * math.pi * (k + 0.5) / n)) for k in range(n)]


def rect(b0, b1, n0, n1):
    """Profile from b0 to b1 across, n0 to n1 up (counter-clockwise)."""
    return [(b0, n0), (b1, n0), (b1, n1), (b0, n1)]


def fillet(P, rad, n=4, closed=False):
    """Polyline P with each corner rounded to radius rad (n segments per arc)."""
    P = [np.asarray(p, float) for p in P]
    m = len(P)
    out = [] if closed else [P[0]]
    for i in (range(m) if closed else range(1, m - 1)):
        a, b, c = P[i - 1], P[i], P[(i + 1) % m]
        u, w = (a - b) / np.linalg.norm(a - b), (c - b) / np.linalg.norm(c - b)
        phi = math.acos(np.clip(u @ w, -1, 1))
        if rad <= 0 or phi > math.pi - 1e-3:
            out.append(b)
            continue
        d = min(rad / math.tan(phi / 2), np.linalg.norm(a - b) / 2, np.linalg.norm(c - b) / 2)
        r = d * math.tan(phi / 2)
        ctr = b + (u + w) / np.linalg.norm(u + w) * (r / math.sin(phi / 2))
        v1, v2 = b + u * d - ctr, b + w * d - ctr
        ang = math.acos(np.clip(v1 @ v2 / (r * r), -1, 1))
        out += [ctr + (math.sin((1 - s) * ang) * v1 + math.sin(s * ang) * v2) / math.sin(ang)
                for s in np.linspace(0, 1, n + 1)]
    return out if closed else out + [P[-1]]


class Kit:
    """Triangles with a palette cell and a piece tag each ("mount" pieces may come within MIN_GAP["mount"])."""

    def __init__(self):
        self.V, self.T, self.cell, self.tag = [], [], [], []

    def add(self, V, T, cell, tag):
        self.T.append(np.asarray(T) + sum(len(v) for v in self.V))
        self.V.append(np.asarray(V, float))
        self.cell += [cell] * len(T)
        self.tag += [tag] * len(T)

    def sweep(self, path, prof, cell="steel", tag="piece", up=(0, 0, 1), closed=False, smooth=True):
        """Sweep the profile (b, n) along the path, mitred at its joints: n starts nearest `up`, b = direction x n.
        smooth: one ring of shared vertices (a tube); else each profile edge its own strip (flat sides)."""
        P = np.asarray(path, float)
        m = len(P)
        D = (np.roll(P, -1, 0) - P) if closed else P[1:] - P[:-1]
        D /= np.linalg.norm(D, axis=1)[:, None]
        up = np.asarray(up, float)
        nv = up - D[0] * (up @ D[0])
        nv /= np.linalg.norm(nv)
        N = [nv]
        for k in range(1, len(D)):          # parallel transport
            ax = np.cross(D[k - 1], D[k])
            s = np.linalg.norm(ax)
            if s > 1e-9:
                nv = np.array(Matrix.Rotation(math.atan2(s, D[k - 1] @ D[k]), 3, Vector(ax / s)) @ Vector(nv))
            N.append(nv)
        prof = np.asarray(prof, float)
        rings = []
        for i in range(m):
            k_in = (i - 1) % len(D) if (closed or i > 0) else 0
            a = D[k_in]
            b_, n_ = np.cross(a, N[k_in]), N[k_in]
            off = prof[:, :1] * b_ + prof[:, 1:] * n_
            if closed or 0 < i < m - 1:     # onto the joint's bisecting plane
                t = a + D[i % len(D)]
                t /= np.linalg.norm(t)
                off = off - np.outer(off @ t / (a @ t), a)
            rings.append(P[i] + off)
        R = np.array(rings)                 # m x M x 3
        M = len(prof)
        steps = [(i, (i + 1) % m) for i in range(m if closed else m - 1)]
        if smooth:
            V, base = R.reshape(-1, 3), lambda i, j: i * M + j % M
            T = [t for i, i2 in steps for j in range(M)
                 for t in ((base(i, j), base(i2, j), base(i, j + 1)), (base(i, j + 1), base(i2, j), base(i2, j + 1)))]
            self.add(V, T, cell, tag)
        else:
            for j in range(M):
                V = np.stack([R[:, j], R[:, (j + 1) % M]], 1).reshape(-1, 3)
                T = [t for i, i2 in steps for t in ((2 * i, 2 * i2, 2 * i + 1), (2 * i + 1, 2 * i2, 2 * i2 + 1))]
                self.add(V, T, cell, tag)
        if not closed:
            for ring, flip in ((R[0], False), (R[-1], True)):
                T = [(0, j + 1, j) if flip else (0, j, j + 1) for j in range(1, M - 1)]
                self.add(ring, T, cell, tag)


# ---- the car it fits ----
class Car:
    """The built body, glass and shut doors (world frame = body mesh frame), the doors' clips, and rays on them."""

    def __init__(self):
        bpy.ops.wm.open_mainfile(filepath=os.path.join(pv.TMP, "skf_doors.blend"))
        self.arm = bpy.data.objects["VehicleSkeleton"]
        self.arm.matrix_world = Matrix.Rotation(math.pi / 2, 4, "X")
        self.arm.animation_data.action = None
        self.doors = [bpy.data.objects[p] for p in pv.DOORS]
        self.body = bpy.data.objects[pv.NAME]
        self.fixed = [self.body, bpy.data.objects[pv.NAME + "_Glass"]]
        self.bvh = BVHTree.FromPolygons(*self.merged(self.fixed + self.doors))

    def world(self, ob):
        bpy.context.view_layer.update()
        e = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me = e.to_mesh()
        me.calc_loop_triangles()
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        tri = np.empty(len(me.loop_triangles) * 3, np.int64)
        me.loop_triangles.foreach_get("vertices", tri)
        M = np.array(ob.matrix_world)
        out = co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3], tri.reshape(-1, 3)
        e.to_mesh_clear()
        return out

    def merged(self, obs):
        V, T, n = [], [], 0
        for o in obs:
            v, t = self.world(o)
            V.append(v)
            T.append(t + n)
            n += len(v)
        return np.concatenate(V).tolist(), np.concatenate(T).tolist()

    def poses(self, part):
        """(frame, world vertices, triangles) of the part at every frame of its clip."""
        act = bpy.data.actions[part + "_closing"]
        self.arm.animation_data.action = act
        ob = bpy.data.objects[part]
        for f in range(int(act.frame_range[0]), int(act.frame_range[1]) + 1):
            bpy.context.scene.frame_set(f)
            yield (f, *self.world(ob))
        self.arm.animation_data.action = None
        bpy.context.scene.frame_set(1)

    def hit(self, o, d):
        loc = self.bvh.ray_cast(Vector(o), Vector(d))[0]
        return None if loc is None else np.array(loc)

    def front(self, x, z0, z1, sign):
        """Outermost |y| (sign +1 front, -1 rear) of the surface over heights z0..z1 at x (rays along y)."""
        ys = [h[1] * sign for z in np.linspace(z0, z1, max(2, int((z1 - z0) / 0.01) + 1))
              for h in [self.hit((x, 4 * sign, z), (0, -sign, 0))] if h is not None]
        return max(ys) if ys else None

    def side(self, y, z0, z1):
        """Outermost |x| of the surface over heights z0..z1 at y, both sides."""
        xs = [abs(h[0]) for z in np.linspace(z0, z1, max(2, int((z1 - z0) / 0.01) + 1)) for s in (1, -1)
              for h in [self.hit((4 * s, y, z), (-s, 0, 0))] if h is not None]
        return max(xs) if xs else None

    def roof(self, x, y):
        h = self.hit((x, y, 4), (0, 0, -1))
        return None if h is None else h[2]


# ---- the pieces ----
def envelope(xs, req):
    """Smallest even quartic y(x) = c0 + c2 x^2 + c4 x^4 (least squares shape, lifted) on or above every requirement."""
    A = np.stack([np.ones_like(xs), xs ** 2, xs ** 4], 1)
    c = np.linalg.lstsq(A, req, rcond=None)[0]
    c[0] += (req - A @ c).max()
    return lambda x: c[0] + c[1] * x ** 2 + c[2] * x ** 4


def guard(kit, car, g, sign, Z):
    """Front (sign +1) or rear (-1) guard: a low bar across, two corner pieces (tube loops or folded panels) rising to
    `top`, brackets back to the bumper."""
    z_lo, z_top, xe = Z(g["z"]), Z(g["top"]), g["x"]
    loops = [(s * a, s * b) for a, b in g["corners"] for s in (1, -1)]
    half = g["r"] if g["kind"] == "tube" else g["t"] / 2
    hb = 2 * g["r"] if g["kind"] == "tube" else g["h"]                  # the low bar's height
    z_band = (z_lo - hb / 2 - 0.01, z_lo + hb / 2 + 0.01)
    xs = np.linspace(-xe, xe, 25)
    req = []
    for x in xs:
        hi = z_top + half + 0.01 if any(min(a, b) - 0.02 <= x <= max(a, b) + 0.02 for a, b in loops) else z_band[1]
        req.append(car.front(x, z_band[0], hi, sign) + g["gap"] + half)
    Y = envelope(xs, np.array(req))
    yw = lambda x: sign * Y(x)             # noqa: E731  (mesh y)
    order = xs if sign > 0 else xs[::-1]   # b = direction x up points into the car (front +x, rear -x)
    if g["kind"] == "tube":
        circ = circle(g["r"], g["sides"])
        kit.sweep([(x, yw(x), z_lo) for x in order], circ)
        for a, b in loops:
            kit.sweep(fillet([(a, yw(a), z_lo), (a, yw(a), z_top), (b, yw(b), z_top), (b, yw(b), z_lo)], g["bend"]),
                      circ, up=(0, sign, 0))
    else:
        t, h, fl = g["t"], g["h"], g["flange"]
        line = [(x, yw(x), z_lo) for x in order]
        kit.sweep(line, rect(-t / 2, t / 2, -h / 2, h / 2), smooth=False)
        kit.sweep(line, rect(-t / 2 - fl, t / 2, -h / 2, -h / 2 + t), smooth=False)       # lower lip folded out
        for a, b in loops:                 # corner panels stand on the band (no coplanar faces with it)
            hp = (z_top - z_lo - h / 2) / 2
            seg = [(x, yw(x), z_top - hp) for x in np.linspace(a, b, 6)]
            seg = seg if (b - a) * sign > 0 else seg[::-1]
            kit.sweep(seg, rect(-t / 2, t / 2, -hp, hp), smooth=False)
            kit.sweep(seg, rect(-t / 2 - fl, t / 2, hp - t, hp), smooth=False)          # top edge folded out
    for x in [s * v for v in g["brackets"] for s in (1, -1)]:            # brackets back to the bumper face
        face = max(car.front(x + dx, z_lo - 0.012, z_lo + 0.012, sign) for dx in (-0.015, 0, 0.015))
        kit.sweep([(x, yw(x), z_lo), (x, sign * (face + STANDOFF), z_lo)],
                  rect(-0.015, 0.015, -0.012, 0.012), cell="mount", tag="mount", smooth=False)


def sills(kit, car, g, Z, Ysh):
    """Both sill guards: a tube or a step board along the rocker below the doors, `gap` off its tapering face, ends and
    brackets to the rocker."""
    z, y0, y1 = Z(g["z"]), g["y"][0] + Ysh, g["y"][1] + Ysh          # y: (rear, front)
    half = g["r"] if g["kind"] == "tube" else g["t"] / 2
    bend = g.get("bend", 0.0)
    # the rocker's outer face over the straight run (the arch lips past it flare out), a quartic in y lifted onto
    # every station: the piece follows the rocker's taper (narrower mid-door than at the lips) instead of standing off
    # its widest point
    ys = np.linspace(y0 + bend, y1 - bend, 17)
    req = np.array([car.side(y, z - half - 0.01, z + half + 0.01) for y in ys])
    c = np.polyfit(ys, req, 4)
    c[-1] += (req - np.polyval(c, ys)).max()
    rock = lambda y: float(np.polyval(c, y)) + g["gap"]   # noqa: E731  (the piece's inner face)
    for s in (1, -1):                       # path along +y on the right, -y on the left: b = outward
        along = (y0, y1) if s > 0 else (y1, y0)
        if g["kind"] == "tube":
            r = g["r"]
            inner = lambda y: rock(y) + r   # noqa: E731  (centre line)
            mid = [(s * inner(y), y, z) for y in np.linspace(along[0] + s * bend, along[1] - s * bend, 7)]
            # each end turns in to the rocker, then out in 2 mm steps until its centre line is r + MIN_GAP["piece"] +
            # 2 mm off the car (rays miss the arch lips' edges)
            ends = [car.side(y, z - r, z + r) for y in along]
            bent = lambda i: (fillet([(s * ends[0], along[0], z), mid[0], mid[1]], bend)[:-1] if i == 0  # noqa: E731
                              else fillet([mid[-2], mid[-1], (s * ends[1], along[1], z)], bend)[1:])
            for i in (0, 1):
                for _ in range(50):         # at most 10 cm out; armor.check reports what still comes too close
                    if min(car.bvh.find_nearest(Vector(q))[3] for q in bent(i)) >= r + MIN_GAP["piece"] + 0.002:
                        break
                    ends[i] += 0.002
            kit.sweep(bent(0) + mid[1:-1] + bent(1), circle(r, g["sides"]))
        else:
            w, t = g["w"], g["t"]
            line = [(s * rock(y), y, z) for y in np.linspace(*along, 7)]
            kit.sweep(line, rect(0, w, -t / 2, t / 2), smooth=False)
            kit.sweep(line, rect(w - t, w, -t / 2 - g["lip"], t / 2), smooth=False)     # outer edge folded down
            inner = lambda y: rock(y) + t   # noqa: E731
        for y in [y + Ysh for y in g["brackets"]]:
            face = max(car.side(y + dy, z - 0.012, z + 0.012) for dy in (-0.015, 0, 0.015))
            kit.sweep([(s * inner(y), y, z), (s * (face + STANDOFF), y, z)],
                      rect(-0.015, 0.015, -0.012, 0.012), cell="mount", tag="mount", smooth=False)


def roof(kit, car, g, Ysh):
    """Roof rack on four feet: two crossbars, then a basket (tube frame, rail, posts, slats) or a low platform (flat-bar
    frame, plank slats)."""
    xf, (yr, yf) = g["feet_x"], (g["y"][0] + Ysh, g["y"][1] + Ysh)
    bars = [y + Ysh for y in g["bars"]]
    xb = g["x"]
    top = max(z for x in np.linspace(-xb, xb, 17) for y in np.linspace(yr, yf, 23) for z in [car.roof(x, y)] if z)
    cb_h = g["bar"][1]
    z_cb = top + g["gap"] + cb_h / 2       # crossbar centre: its underside the gap over the highest roof under the rack
    for y in bars:
        kit.sweep([(-xf - 0.03, y, z_cb), (xf + 0.03, y, z_cb)], rect(-g["bar"][0] / 2, g["bar"][0] / 2, -cb_h / 2, cb_h / 2),
                  smooth=False)
        for x in (-xf, xf):
            zr = max(car.roof(x + dx, y + dy) for dx in (-0.03, 0, 0.03) for dy in (-0.03, 0, 0.03))
            kit.sweep([(x, y, zr + STANDOFF), (x, y, z_cb - cb_h / 2)],
                      rect(-0.022, 0.022, -0.03, 0.03), cell="rubber", tag="mount", up=(0, 1, 0), smooth=False)
    z_f = z_cb + cb_h / 2
    frame = [(-xb, yr), (xb, yr), (xb, yf), (-xb, yf)]
    if g["kind"] == "basket":
        r, c = g["r"], circle(g["r"], g["sides"])
        z0, z1 = z_f + r, z_f + r + g["rail"]
        for zz in (z0, z1):
            kit.sweep(fillet([(x, y, zz) for x, y in frame], g["corner"], closed=True), c, closed=True)
        for x, y in [(sx * xb, y) for sx in (1, -1) for y in (yr + g["corner"], (yr + yf) / 2, yf - g["corner"])] + \
                [(0, yr), (0, yf)]:
            kit.sweep([(x, y, z0), (x, y, z1)], c, up=(0, 1, 0))
        for x in g["slats"]:
            kit.sweep([(x, yr, z0), (x, yf, z0)], circle(g["slat_r"], g["sides"]))
    else:
        h, t = g["frame"]
        z0 = z_f + h / 2
        kit.sweep(fillet([(x, y, z0) for x, y in frame], g["corner"], closed=True), rect(-t / 2, t / 2, -h / 2, h / 2),
                  closed=True, smooth=False)
        w, pt = g["plank"]
        for y in np.linspace(yr + g["corner"], yf - g["corner"], g["planks"]):
            kit.sweep([(-xb + t, y, z_f + pt / 2), (xb - t, y, z_f + pt / 2)], rect(-w / 2, w / 2, -pt / 2, pt / 2),
                      smooth=False)


def style():
    a = pv.CAR["ARMOR"]
    key = os.environ.get("ARMOR_STYLE", a["style"])
    return key, a[key]


def build_kit(car, zmid, cy):
    key, st = style()
    Z = lambda z: z - zmid                 # noqa: E731  (heights over the ground -> mesh z)
    kit = Kit()
    guard(kit, car, st["front"], 1, Z)
    guard(kit, car, st["rear"], -1, Z)
    sills(kit, car, st["sill"], Z, -cy)
    roof(kit, car, st["roof"], -cy)
    return key, kit


# ---- texture, mesh, export ----
def cell_uv(cell):
    k, per = list(RGB).index(cell), TEX_PX // CELL_PX
    return (k % per + 0.5) * CELL_PX / TEX_PX, 1 - (k // per + 0.5) * CELL_PX / TEX_PX


def texture():
    img = np.zeros((TEX_PX, TEX_PX, 4))
    img[..., 3] = 1.0
    img[..., :3] = np.array(RGB["steel"]) / 255         # filtering past a cell's edge stays steel
    for c, rgb in RGB.items():
        u, v = cell_uv(c)
        x, y, h = int(u * TEX_PX), int(v * TEX_PX), CELL_PX // 2
        img[y - h:y + h, x - h:x + h, :3] = np.array(rgb) / 255
    pv.save_png(img, os.path.join(pv.TEX_DIR, TEX + ".png"), "armor")


def mesh(kit):
    V, T = np.concatenate(kit.V), np.concatenate(kit.T)
    me = bpy.data.meshes.new(pv.NAME + "_Armor")
    me.from_pydata(V.tolist(), [], T.tolist())
    uv = np.repeat(np.array([cell_uv(c) for c in kit.cell]), 3, axis=0).ravel()
    for name in ("UV0", "UV1"):
        me.uv_layers.new(name=name).data.foreach_set("uv", uv)
    me.polygons.foreach_set("use_smooth", np.ones(len(T), bool))
    me.validate()
    ob = bpy.data.objects.new(pv.NAME + "_Armor", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ---- what it must clear ----
def lamp_points(car):
    """Centres of the body's lamp faces (lit texels of <NAME>_lights.png at their UV0)."""
    me = car.body.data
    tri = np.empty(len(me.polygons) * 3, np.int64)
    me.polygons.foreach_get("vertices", tri)
    co = np.array(car.world(car.body)[0])
    fc = co[tri.reshape(-1, 3)].mean(1)
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers["UV0"].data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 3, 2).mean(1)
    img = bpy.data.images.load(os.path.join(pv.TEX_DIR, pv.NAME + "_lights.png"))
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)
    lit = px[np.clip((uv[:, 1] * h).astype(int), 0, h - 1), np.clip((uv[:, 0] * w).astype(int), 0, w - 1), :3].max(1) > 0.05
    return {"front lamps": fc[lit & (fc[:, 1] > 0)], "rear lamps": fc[lit & (fc[:, 1] < 0)]}


def check(car, ob, kit, zmid, cy, geo):
    V, T = np.concatenate(kit.V), np.concatenate(kit.T)
    tag = np.array(kit.tag)
    abvh = BVHTree.FromPolygons(V.tolist(), T.tolist())
    samp = np.concatenate([V[T].mean(1), V[T].reshape(-1, 3)])
    stag = np.concatenate([tag, np.repeat(tag, 3)])
    res, bad = {}, []

    def gap(bvh, verts, cap=0.3, where=None):
        """Smallest distance between the kit and a mesh (kit samples to it, its vertices near the kit back); where: a
        dict to get the spot of each."""
        d = {"piece": cap, "mount": cap}
        at = {} if where is None else where
        for p, t in zip(samp, stag):
            n = bvh.find_nearest(Vector(p), d[t])
            if n[0] is not None and n[3] < d[t]:
                d[t], at[t + "_at"] = n[3], p.round(3).tolist()
        lo, hi = V.min(0) - cap, V.max(0) + cap
        for p in verts[((verts > lo) & (verts < hi)).all(1)]:
            n = abvh.find_nearest(Vector(p), cap)
            if n[0] is not None and n[3] < d[tag[n[2]]]:
                d[tag[n[2]]], at[tag[n[2]] + "_at"] = n[3], p.round(3).tolist()
        return d

    def note(name, pairs, d, kind):
        """pairs: abvh.overlap() of the kit and that mesh (kit triangle first)."""
        at = sorted({tuple(V[T[i]].mean(0).round(2)) for i, _ in pairs})
        res[name] = {"overlaps": len(pairs), **({"at": at[:8]} if at else {}), **{k: round(v, 4) for k, v in d.items()}}
        if pairs or d["piece"] < MIN_GAP[kind] or d["mount"] < MIN_GAP["mount"]:
            bad.append(name)

    fv, ft = car.merged(car.fixed)
    fbvh = BVHTree.FromPolygons(fv, ft)
    where = {}
    note("body", abvh.overlap(fbvh), gap(fbvh, np.array(fv), where=where), "piece")
    res["body"].update(where)
    for part in pv.DOORS:
        worst, pairs = {"piece": 9, "mount": 9}, []
        for f, v, t in car.poses(part):
            b = BVHTree.FromPolygons(v.tolist(), t.tolist())
            pairs += abvh.overlap(b)
            for k, x in gap(b, v).items():
                if x < worst[k]:
                    worst[k], worst[k + "_frame"] = x, f
        note(part + " (every frame)", pairs, {k: v for k, v in worst.items() if not k.endswith("_frame")}, "moving")
        res[part + " (every frame)"].update({k: v for k, v in worst.items() if k.endswith("_frame")})
    # tyres: cylinders at the script's wheel offsets (convert.py stage_view's WHEELS), front ones over the steering
    block = open(os.path.join(pv.TMP, "geometry_block.txt"), encoding="utf-8").read()
    for name, front, ox, oy, oz, wid in re.findall(
            r"wheel (\w+)\s*\{\s*front = (\w+),\s+offset = (\S+) (\S+) (\S+),\s+radius = \S+,\s+width = (\S+),", block):
        c = Vector((-float(ox) * pv.S, float(oz) * pv.S, float(oy) * pv.S + pv.WHEEL_LIFT))
        r = geo["wheel_radius_rear"] if front == "false" and "wheel_radius_rear" in geo else geo["wheel_radius"]
        n, w = 24, float(wid)
        ring = [(sx, r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n)) for sx in (-w / 2, w / 2) for k in range(n)]
        tris = [(k, (k + 1) % n, n + k) for k in range(n)] + [((k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)] + \
               [(0, k + 1, k) for k in range(1, n - 1)] + [(n, n + k, n + k + 1) for k in range(1, n - 1)]
        worst, pairs = {"piece": 9, "mount": 9}, []
        for st in (np.linspace(-STEER, STEER, 13) if front == "true" else [0.0]):
            for lift in (-TRAVEL, 0, TRAVEL):
                M = Matrix.Translation(c + Vector((0, 0, lift))) @ Matrix.Rotation(st, 4, "Z")
                v = np.array([M @ Vector(p) for p in ring])
                b = BVHTree.FromPolygons(v.tolist(), tris)
                pairs += abvh.overlap(b)
                for k, x in gap(b, v).items():
                    worst[k] = min(worst[k], x)
        note(f"tyre {name} (steer +-{STEER if front == 'true' else 0}, travel +-{TRAVEL})", pairs, worst, "tyre")
    # what the game's eight views must still see: lamps, plates and headlamp pockets (ARMOR keep), the charge port
    keep = pv.CAR["ARMOR"]["keep"]
    pts = lamp_points(car)
    for nm, sign in (("front plate", 1), ("rear plate", -1)):
        hx, z0, z1 = keep[nm.replace(" ", "_")]
        pts[nm] = np.array([h for x in np.linspace(-hx, hx, 9) for z in np.linspace(z0 - zmid, z1 - zmid, 5)
                            for h in [car.hit((x, 4 * sign, z), (0, -sign, 0))] if h is not None])
    if "head_lamps" in keep:
        x0, x1, z0, z1 = keep["head_lamps"]
        pts["head lamps"] = np.array([h for s in (1, -1) for x in np.linspace(x0, x1, 7) for z in np.linspace(z0 - zmid, z1 - zmid, 5)
                                      for h in [car.hit((s * x, 4, z), (0, -1, 0))] if h is not None])
    px, py, pz = geo["port_mesh"]
    pts["charge port"] = np.array([h for a in np.linspace(0, 2 * math.pi, 9)[:-1] for rr in (0, 0.03)
                                   for h in [car.hit((4 * np.sign(px), py + rr * math.cos(a), pz - zmid + rr * math.sin(a)),
                                                     (-np.sign(px), 0, 0))] if h is not None])
    el = math.radians(30)
    views = {k * 45: Vector((math.sin(math.radians(k * 45)) * math.cos(el), math.cos(math.radians(k * 45)) * math.cos(el),
                              math.sin(el))) for k in range(8)}
    for nm, P in pts.items():
        hidden = {}
        for deg, d in views.items():
            seen = [p for p in P if car.bvh.ray_cast(Vector(p) + d * 1e-3, d)[0] is None]
            hidden[deg] = sum(abvh.ray_cast(Vector(p) + d * 1e-3, d)[0] is not None for p in seen) / max(1, len(seen))
        res[nm] = {"samples": len(P), "hidden_by_view_deg": {k: round(v, 3) for k, v in hidden.items()}}
        # plates and the headlamp pockets count from the views within 45 deg of facing them (side on, they're edge-on
        # in their pockets); the rest from all
        sign = {"front plate": 1, "rear plate": -1, "head lamps": 1}.get(nm)
        if max(v for k, v in hidden.items() if sign is None or math.cos(math.radians(k)) * sign > 0.7) > 0:
            bad.append(nm)
    return res, bad


def build(zmid=None, cy=None):
    """Build the car's kit (its ARMOR style, or ARMOR_STYLE), check it, write <NAME>_Armor.fbx and the palette.
    zmid, cy: the body's centring (stage_build's), else TMP/geometry.json's. -> its triangles."""
    geo = json.load(open(os.path.join(pv.TMP, "geometry.json")))
    zmid = geo["zmid"] if zmid is None else zmid
    cy = geo["centre_y"] if cy is None else cy
    car = Car()
    key, kit = build_kit(car, zmid, cy)
    ob = mesh(kit)
    res, bad = check(car, ob, kit, zmid, cy, geo)
    V = np.concatenate(kit.V)
    res = {"style": key, "tris": len(ob.data.polygons), "bbox": [V.min(0).round(4).tolist(), V.max(0).round(4).tolist()],
           **res}
    json.dump(res, open(os.path.join(pv.TMP, f"armor_check_{key}.json"), "w"), indent=1)
    print("ARMOR", json.dumps(res))
    if bad:
        raise SystemExit(f"{pv.NAME} armour {key}: fails {bad} (TMP/armor_check_{key}.json)")
    texture()
    pv.export_fbx(ob, os.path.join(pv.VEH_DIR, pv.NAME + "_Armor.fbx"))
    return len(ob.data.polygons)
