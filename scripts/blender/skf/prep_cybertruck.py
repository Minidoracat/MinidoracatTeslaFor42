"""Cybertruck source prep, run once before convert.py (CAR=cybertruck): adamsochi2010's "Tesla CyberTruck" FBX
(Sketchfab, CC BY 4.0; CREDITS.md) -> the same FBX moved onto the owner's manual and the official design-studio side
render (cars/cybertruck.py SRC reads the output; the config's SRC_STRETCH still scales it onto the official size).
The truck is flat stainless panels between straight sharp creases, so the field is piecewise affine, not smooth: a
constrained Delaunay triangulation of control points in the side view (y, z), each point's old -> new position
(FIELD ctrl), every vertex mapped by its triangle's affine map (x kept). A panel whose side view lies in one triangle,
or whose plane holds the x axis (roof, hood, tonneau: a line side-on) stays flat; the triangles' edges are laid along
the creases (FIELD ctrl's chains are constraint edges). No cuts: every object and component keeps its triangles (the
config's CUT keys hold). The tyres (Tire: the wheel centres the build reads) move whole with their axle (FIELD axle).
Normals: each corner's by the map's Jacobian, inverse transpose. Frame: the build's pre-centre grid (convert.py
src_frame: +Y front, +Z up, -X the car's left, ground 0, 0.826 grid / m); the FBX is written back in its own frame.
    "$B" -b --factory-startup --python scripts/blender/skf/prep_cybertruck.py            # -> cybertruck_prep.fbx
    "$B" -b --factory-startup --python scripts/blender/skf/prep_cybertruck.py -- map     # stdin "name y z" -> mapped
Numbers, targets and the same-camera check: .claude/skills/tesla-dev/references/models-cybertruck.md.
"""
import json
import math
import os
import runpy
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "temp", "skf_ct", "src", "source")
SRC = os.path.join(SRC_DIR, "forFUBfbx.fbx")
OUT = os.path.join(SRC_DIR, "cybertruck_prep.fbx")
CFG = runpy.run_path(os.path.join(REPO, "scripts", "blender", "skf", "cars", "cybertruck.py"))["CAR"]
K = 0.826                                  # pzveh.K

# control points (pre-centre grid, side view): name -> ((y, z) source, (y, z) target[, objects]); a point with an
# object tuple only enters the maps of those objects (the arch trim's front leg narrows over the body's side). Chains:
# constraint edges. Targets read off the official SIDE render through the fitted camera at the feature's depth
# (temp/skf_ct/work/rect.py, edge.py), front axle fixed (the camera's anchor)
_FIX = lambda *p: (p, p)                                                                        # noqa: E731
DOOR_DROP = 0.020                          # the doors' and sill trim's joint lower (official SIDE: 21-28 mm)
FIELD = dict(
    # wheelbase 3,665.6 -> 3,635.0 (manual p.245): the rear axle forward; the nose and the tail out to 878.3 / 1,169.6
    axle=dict(front=0.0, rear=0.0253),
    ctrl={
        # background
        **{f"g{i}": _FIX(y, 0.0) for i, y in enumerate((-2.6, -1.4, -0.4, 0.6, 1.6, 2.6))},
        **{f"h{i}": _FIX(y, 2.0) for i, y in enumerate((-2.6, 0.0, 2.6))},
        **{f"nf{i}": _FIX(2.6, z) for i, z in enumerate((0.3, 0.9, 1.4))},
        **{f"tf{i}": _FIX(-2.6, z) for i, z in enumerate((0.3, 0.9, 1.4))},
        # nose: the bumper's top edge (the frontmost point, Plane.004 z 0.54) 6.9 mm back (front overhang 886.6 ->
        # 878.3), the stainless nose above it 2 cm back (official SIDE: 1.3 cm behind ours, the black bumper ahead of
        # it), the bumper's face below out 2.3 cm and its chin 2.5-3 cm (official SIDE 2-3 cm; its face at z 0.45-0.5
        # stays 2 cm short: further would pass the manual's length), its lowest corner (by the front tyre) down 1.1 cm
        # (and out 3 cm with the chin):
        # ground clearance 257 mm (manual p.245, Medium). The fender's front edge (y 2.12) moves with FIELD corner
        "n1": ((2.342, 0.834), (2.322, 0.834)), "n2": ((2.342, 0.780), (2.322, 0.780)),
        "n3": ((2.347, 0.540), (2.340, 0.540)), "n4": ((2.312, 0.370), (2.335, 0.370)),
        "n5": _FIX(2.12, 0.570), "n6": _FIX(2.12, 0.910), "n7": _FIX(2.13, 0.860),
        "n8": ((2.036, 0.230), (2.066, 0.219)), "n9": ((2.20, 0.300), (2.225, 0.289)),
        "n10": ((2.249, 0.350), (2.278, 0.348)),
        # front arch: the trim's outer line (A, x 0.76) and opening (C, x 0.84), tops up 4 cm, the front leg steeper
        "fA1": ((2.111, 0.569), (2.036, 0.575), ("Cube.004",)), "fA2": ((1.908, 0.834), (1.855, 0.874)),
        "fA3": ((1.341, 0.833), (1.327, 0.878)), "fA4": _FIX(1.133, 0.504),
        "fC1": ((2.018, 0.568), (2.005, 0.570)), "fC2": ((1.842, 0.785), (1.845, 0.812)),
        "fC3": ((1.385, 0.783), (1.364, 0.824)), "fC4": _FIX(1.201, 0.504),
        "fk1": _FIX(1.66, 0.93), "fk2": _FIX(1.38, 0.94), "fk3": _FIX(1.20, 0.95), "fk4": _FIX(1.10, 0.96),
        # doors' lower edge and the sill trim's joint down DOOR_DROP; the sill's bottom stays
        **{f"db{i}": ((y, 0.362), (y, 0.362 - DOOR_DROP)) for i, y in
           enumerate((1.201, 1.133, 1.03, 0.306, 0.186, -0.82, -0.89, -0.99))},
        **{f"sb{i}": _FIX(y, 0.238) for i, y in enumerate((1.201, 0.0, -0.99, -1.80))},
        **{f"dm{i}": _FIX(y, 0.53) for i, y in enumerate((0.306, 0.186))},
        "bs1": _FIX(0.186, 1.000), "bs2": _FIX(0.306, 0.994), "bs4": _FIX(0.186, 0.75),
        "fq1": _FIX(1.0995, 0.75), "fq2": _FIX(1.0995, 1.00),
        # the side glass's foot (the window opening's lower edge, x 0.72) 1 cm down (official SIDE: 10-18 mm)
        **{f"gf{i}": ((y, z), (y, z - 0.010)) for i, (y, z) in
           enumerate(((1.66, 0.998), (1.384, 1.014), (1.199, 1.025), (1.063, 1.033), (0.12, 1.088)))},
        # rear door's rear edge (R1 / D) and the side window's rear edge 6-8 cm forward (official: straight, upright)
        "d1": ((-0.682, 0.362), (-0.630, 0.362 - DOOR_DROP)), "d2": ((-0.7285, 0.530), (-0.641, 0.530)),
        "d3": ((-0.7205, 1.043), (-0.661, 1.043)), "d4": ((-0.709, 1.140), (-0.660, 1.130)),
        "w1": ((-0.713, 1.298), (-0.645, 1.322)), "w2": ((-0.713, 1.334), (-0.645, 1.355)),
        "w3": ((-0.713, 1.341), (-0.645, 1.362)),
        # the roof line behind the glass up 1.2 cm, its tail end (rails' ends, the tailgate's top, its light bar) down
        # (the rails' top one straight line from q1 to t3: the source's rails are one plane)
        # 1.6 cm (official SIDE top line: 3-5 px low mid-roof, 4 px high at the tail; REAR34 the bar 10-20 px high;
        # manual p.246 B: floor to the top at the tail 503.8)
        "q1": ((-0.99, 1.306), (-0.99, 1.318)), "q2": _FIX(-0.99, 1.06), "q3": ((-0.978, 1.245), (-0.978, 1.257)),
        # rear arch: tops up 5.5-6.5 cm, the trapezoid 4-6 cm narrower at the top (official SIDE)
        "rA1": ((-0.912, 0.529), (-0.885, 0.530)), "rA2": ((-1.137, 0.834), (-1.080, 0.888)),
        "rA3": ((-1.693, 0.834), (-1.635, 0.900)), "rA4": ((-1.906, 0.580), (-1.900, 0.585)),
        "rC1": ((-0.995, 0.529), (-0.990, 0.540)), "rC2": ((-1.181, 0.784), (-1.140, 0.838)),
        "rC3": ((-1.642, 0.785), (-1.605, 0.842)), "rC4": ((-1.825, 0.579), (-1.822, 0.580)),
        "rk1": _FIX(-1.175, 1.065), "rk2": _FIX(-1.673, 1.088), "rk3": ((-1.175, 1.280), (-1.175, 1.2894)),
        "rk4": ((-1.679, 1.213), (-1.679, 1.2114)), "rk5": ((-1.671, 1.154), (-1.671, 1.1524)),
        # tail: the bumper's back 6.9 mm out (rear overhang)
        "t1": ((-2.340, 0.440), (-2.347, 0.440)), "t2": ((-2.350, 0.560), (-2.357, 0.560)),
        "t3": ((-2.334, 1.126), (-2.334, 1.110)), "t4": ((-2.326, 1.066), (-2.326, 1.050)), "t5": _FIX(-2.25, 0.62),
        "t6": ((-2.265, 1.135), (-2.265, 1.1207)), "t7": ((-2.255, 1.071), (-2.255, 1.055)),
        # roof: the apex 8.4 cm forward and 5.8 mm up (official SIDE; manual height 1,793.8), the windscreen's top
        # edge along with it on the new windscreen line from the cowl
        "a1": ((0.306, 1.476), (0.390, 1.4818)), "a2": ((0.306, 1.469), (0.390, 1.4748)),
        "a3": ((0.306, 1.427), (0.390, 1.4388)), "a4": ((0.477, 1.423), (0.561, 1.4288)),
        "a5": _FIX(1.707, 1.037), "a6": ((0.306, 1.079), (0.306, 1.069)),
        # the side window's top edge ahead of the apex 1.2 cm up, the A-pillar's top (windscreen line) stays (official
        # SIDE: the pillar band 15-16 px, ours 18-19)
        "wt1": ((0.9, 1.252), (0.9, 1.264)), "wt2": ((1.3, 1.135), (1.3, 1.147)),
        "ap1": _FIX(0.9, 1.3128), "ap2": _FIX(1.3, 1.176),
    },
    chains=[],
    frame=((-4.0, -1.0), (4.0, 3.0)),      # fixed corners round everything
    # the nose's corner (|x| 0.76, y 2.12) 4.4 cm back and its top 1.7 cm down: official SIDE corner edge at y 2.076
    # (z 0.62-0.88) and top 0.89. Points |x| (hood front edge's inner corner P1, the lid's rear outer corner at the
    # cowl P2, the lid's front corner P3, on the hood plane z_h = z1 + (y1 - y) slope); d: P3's (dy, dz); the column
    # below the hood by s(|x|) t(y) and its top by u(z), above zlow
    corner=dict(p1=(0.458, 2.322, 0.835), p2=(0.715, 1.712, 1.039), p3=(0.759, 2.115, 0.9073), d=(-0.044, -0.017),
                slope=(1.039 - 0.835) / (2.322 - 1.712), band=0.012, zcut=0.83, t=(1.95, 2.11), u=(0.80, 0.907),
                zlow=0.56, skip=("Cube.004",)),
    # keep (move()): side-view boxes ((y, z) lo, hi) and |x| (none of the move inboard of x_in, all of it from x_out):
    # the front footwell's toe board behind the front arch (it moved with the arch's rear leg, 1-2 cm into the front
    # passengers' feet: seat_head.py legs -11 mm, 4 before)
    keep=(((0.90, 0.10), (1.70, 1.00), 0.70, 0.755),),
    # rear bumper's lower block (skid()): official SIDE bottom z 0.224-0.276 from y -1.85 back to -2.24, its rear face
    # leaning back to (-2.27, 0.375); REAR34 its back |x| 0.62 / 0.55
    skid=((-1.84, 0.31, 0.226, 0.79, 0.74), (-2.06, 0.37, 0.245, 0.76, 0.70), (-2.24, 0.40, 0.274, 0.60, 0.53),
          (-2.265, 0.40, 0.372, 0.60, 0.55)),
    # the off-road light bar (light_bar()) on the windshield, top at its visible upper edge (FIELD ctrl a4's target),
    # foot a point further down the glass (the windshield's lower edge at the cowl); ~1.3 m x 10 cm x 3.6 cm (the
    # glass's width between the A-pillars: service manual photos), 3 mm off the glass
    lightbar=dict(top=(0.561, 1.4288), foot=(1.702, 1.030), x=0.55, l=0.085, t=0.030, gap=0.003, lens="Gluss Button"),
    # the A-pillar wiper (Cube.008, parked up the driver's pillar) k x as tall off its foot along it (official SIDE:
    # its top 8-12 px over ours, on the pillar with no gap under it); the glass: its top edge, the cowl
    wiper=dict(obj="Cube.008", k=3.5, glass=((0.561, 1.4288), (1.702, 1.030))),
    # the tail bar's ends (tail_ends()): the corner blocks' rear face (y, z) and how far out, |x| from the tailgate's
    # edge to the corner, the band's and the red strip's z (the source's Body.003 / Cube.030 heights, mapped)
    tailends=dict(face=(-2.334, 1.1), off=0.002, x=(0.668, 0.760), band=(1.067, 1.135), strip=(1.105, 1.121),
                  mat="Car Reflection White"),
    # flat panels (flat_stats_of(), a report): the source's panels (normals within ang deg, one plane within tol grid,
    # area grid^2 or more) of these objects; flat shading of the faces flat in the source (main())
    flat=dict(objs=("Body", "Body.005", "Body.012", "Body.004", "Cube.002", "Cube.004", "Plane.004"), ang=0.5,
              tol=0.0008, area=0.004),
    # wheel wells (wells()): per arch its C line (ctrl keys, front to back) and the inner |x| (front: clear of the
    # front passengers' feet, seat_head.py legs; rear: the bed's wheel hump, BED_TUB hump x 0.535), out from the outline, the cladding's inside |x|
    wells=dict(arches=((("fC1", "fC2", "fC3", "fC4"), 0.545), (("rC1", "rC2", "rC3", "rC4"), 0.545)), off=0.012,
               x_out=0.83, mat="Black Plastick"),
    # front light bar (head_bar()): its centre under the face's top edge (middle, corner: over the source's strip),
    # height, out from the face (chamfer_tol: a chamfer hit further than that off its top edge's line is the corner
    # lamp's pocket), points corner to corner, how far (y) and in how many it runs on along the flanks
    headbar=dict(dz=(0.019, 0.029), h=0.025, off=0.004, chamfer_tol=0.012, n=41, wrap=0.06, n_side=3, mat="White headlights"),
)


def frame():
    """convert.py src_frame (SRC_YFRONT branch): FBX world -> pre-centre grid."""
    sx, sy, sz = (K * CFG["SRC_SCALE"] * f for f in CFG["SRC_STRETCH"])
    c = CFG["SRC_C"]
    return np.array(((-sx, 0, 0, sx * c[0]), (0, -sy, 0, sy * c[1]), (0, 0, sz, -sz * CFG["SRC_YFRONT"]),
                     (0, 0, 0, 1)))


class Map:
    """Piecewise affine (y, z) map from FIELD ctrl, for object `obj` (its own points too; None: the body's)."""

    def __init__(self, obj=None):
        from mathutils import Vector
        from mathutils.geometry import delaunay_2d_cdt
        (fy0, fz0), (fy1, fz1) = FIELD["frame"]
        names = [n for n, c in FIELD["ctrl"].items() if len(c) < 3 or obj in c[2]]
        old = [FIELD["ctrl"][n][0] for n in names] + [(fy0, fz0), (fy1, fz0), (fy1, fz1), (fy0, fz1)]
        new = [FIELD["ctrl"][n][1] for n in names] + old[len(names):]
        cons = [(names.index(a), names.index(b)) for ch in FIELD["chains"] for a, b in zip(ch[:-1], ch[1:])
                if a in names and b in names]
        vs, _, faces, orig, _, _ = delaunay_2d_cdt([Vector(p) for p in old], cons, [], 0, 1e-7)
        assert len(vs) == len(old), "FIELD chains cross: the triangulation added %d points" % (len(vs) - len(old))
        idx = [o[0] for o in orig]                      # output vertex -> input point
        self.tri = np.array([[idx[i] for i in f] for f in faces])
        self.old, self.new = np.array(old, float), np.array(new, float)
        # per triangle: new = A @ old + t
        self.A, self.t = [], []
        for f in self.tri:
            P = np.c_[self.old[f], np.ones(3)]
            S = np.linalg.solve(P, self.new[f])         # 3 x 2: rows y, z, 1
            self.A.append(S[:2].T)
            self.t.append(S[2])
        self.A, self.t = np.array(self.A), np.array(self.t)
        bad = np.linalg.det(self.A) <= 0
        assert not bad.any(), "FIELD folds over: triangles %s" % [[names[i] if i < len(names) else "frame"
                                                                   for i in f] for f in self.tri[bad]]

    def which(self, p):
        """Containing triangle of each (y, z) point (the first one: points on shared edges map alike)."""
        a, b, c = (self.old[self.tri[:, k]] for k in range(3))
        out = np.full(len(p), -1)
        for s in range(0, len(p), 4096):
            q = p[s:s + 4096, None, :]
            d = (b - a)[None]
            e = (c - a)[None]
            w = q - a[None]
            den = d[..., 0] * e[..., 1] - d[..., 1] * e[..., 0]
            u = (w[..., 0] * e[..., 1] - w[..., 1] * e[..., 0]) / den
            v = (d[..., 0] * w[..., 1] - d[..., 1] * w[..., 0]) / den
            inside = (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9)
            out[s:s + 4096] = np.where(inside.any(1), inside.argmax(1), -1)
        assert (out >= 0).all(), "points outside FIELD frame"
        return out

    def __call__(self, g):
        """g: N x 3 grid points -> (mapped points, Jacobians N x 3 x 3)."""
        k = self.which(g[:, 1:])
        q = g.copy()
        q[:, 1:] = np.einsum("nij,nj->ni", self.A[k], g[:, 1:]) + self.t[k]
        J = np.tile(np.eye(3), (len(g), 1, 1))
        J[:, 1:, 1:] = self.A[k]
        return q, J


def corner(g):
    """FIELD corner: the nose's corners back and down (x-dependent, after the side-view map). The hood plane (side-on a
    line, z_h(y)) keeps its centre; outboard of the crease P1-P2 its points go onto the facet through P1, P2 and the new
    corner (Delta y affine in plan over that triangle, so the facet is a plane); the front face's chamfer and the
    corner's column move Delta y * s(|x|) * t(y), their top Delta z * u(z)."""
    c = FIELD["corner"]
    q = g.copy()
    (x1, y1, z1), (x2, y2, z2), (x3, y3, z3) = c["p1"], c["p2"], c["p3"]
    dy, dz = c["d"]
    ax = np.abs(g[:, 0])
    zh = z1 + (y1 - g[:, 1]) * c["slope"]                        # the hood plane at y
    hood = (np.abs(g[:, 2] - zh) < c["band"]) & (g[:, 1] > y2 - 0.01) & (g[:, 2] > c["zcut"])
    # barycentric weight of P3 in plan (x outboard as |x|)
    den = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
    w3 = 1 - ((y2 - y3) * (ax - x3) + (x3 - x2) * (g[:, 1] - y3)) / den \
        - ((y3 - y1) * (ax - x3) + (x1 - x3) * (g[:, 1] - y3)) / den
    side = (x2 - x1) * (g[:, 1] - y1) - (y2 - y1) * (ax - x1)        # > 0: outboard of P1-P2 (toward the corner)
    sgn = np.sign((x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1))
    out = hood & (side * sgn > 0)
    w = np.clip(w3, 0, 1)
    yn = g[:, 1] + dy * w
    # the new facet plane z = a + b |x| + c y through P1, P2, P3' (P3 moved by d)
    A = np.array([[1, x1, y1], [1, x2, y2], [1, x3, y3 + dy]])
    a, b, cc = np.linalg.solve(A, [z1, z2, z3 + dz])
    q[out, 1] = yn[out]
    q[out, 2] = g[out, 2] + (a + b * ax[out] + cc * yn[out]) - zh[out]
    s = np.clip((ax - x1) / (x3 - x1), 0, 1)
    t = np.clip((g[:, 1] - c["t"][0]) / (c["t"][1] - c["t"][0]), 0, 1)
    u = np.clip((g[:, 2] - c["u"][0]) / (c["u"][1] - c["u"][0]), 0, 1)
    col = ~hood & (g[:, 2] > c["zlow"]) & (g[:, 2] < z3 + 0.01)
    q[col, 1] += dy * (s * t)[col]
    q[col, 2] += dz * (s * t * u)[col]
    return q


def move(maps, name, g, faces=None, flat_stats=None):
    """Grid points of object `name` -> (new points, Jacobians). maps: object -> Map, built on first use. FIELD keep:
    inside each side-view box the move fades out inboard, from all of it at |x| x_out to none at x_in (the body's
    inner panels behind the arches, the front footwell's toe board, stay where the cabin and the passengers' feet
    were fitted). faces: the object's polygons, for FIELD flat's report (after the side-view map, before the corner
    warp), appended to flat_stats."""
    q, J = _warp(maps, name, g, faces, flat_stats)
    for (y0, z0), (y1, z1), x_in, x_out in FIELD["keep"]:
        box = (g[:, 1] > y0) & (g[:, 1] < y1) & (g[:, 2] > z0) & (g[:, 2] < z1) & (np.abs(g[:, 0]) < x_out)
        if not box.any():
            continue
        ax = np.abs(g[box, 0])
        w = np.clip((ax - x_in) / (x_out - x_in), 0, 1)
        dw = np.where((ax > x_in) & (ax < x_out), np.sign(g[box, 0]) / (x_out - x_in), 0.0)
        d = q[box] - g[box]
        J[box] = np.eye(3) + w[:, None, None] * (J[box] - np.eye(3)) + d[:, :, None] * np.c_[dw, 0 * dw, 0 * dw][:, None, :]
        q[box] = g[box] + w[:, None] * d
    return q, J


def _warp(maps, name, g, faces=None, flat_stats=None):
    """move() before FIELD keep."""
    if name.startswith("Tire"):          # whole, with its axle
        q = g.copy()
        q[:, 1] += np.where(g[:, 1] > 0, FIELD["axle"]["front"], FIELD["axle"]["rear"])   # all four in one object
        return q, np.tile(np.eye(3), (len(g), 1, 1))
    key = name if any(len(c) > 2 and name in c[2] for c in FIELD["ctrl"].values()) else None
    if key not in maps:
        maps[key] = Map(key)
    q, J = maps[key](g)
    wp = FIELD["wiper"]
    if name.startswith(wp["obj"]):                    # thicker off the glass about its foot (FIELD wiper)
        (y0, z0), (y1, z1) = wp["glass"]
        n = np.array([0.0, z0 - z1, y1 - y0])
        n /= np.linalg.norm(n) * np.sign(n[2])
        h = (q - [0.0, y1, z1]) @ n
        yb = np.arange(q[:, 1].min(), q[:, 1].max() + 0.02, 0.02)      # its foot along it: per 2 cm the lowest
        hb = np.array([h[(q[:, 1] >= y) & (q[:, 1] < y + 0.02)].min(initial=np.inf) for y in yb])
        ok = np.isfinite(hb)
        q = q + np.outer((wp["k"] - 1) * (h - np.interp(q[:, 1], yb[ok] + 0.01, hb[ok])), n)
        J = np.einsum("ij,njk->nik", np.eye(3) + (wp["k"] - 1) * np.outer(n, n), J)
    fl = FIELD["flat"]
    if faces is not None and name.startswith(fl["objs"]):
        flat_stats += [dict(obj=name, **d) for d in flat_stats_of(g, q, faces, fl)]
    if name.startswith(FIELD["corner"]["skip"]):
        return q, J
    r = corner(q)
    Jc = np.zeros((len(q), 3, 3))                     # the corner warp's Jacobian, central differences
    for j in range(3):
        e = np.zeros(3)
        e[j] = 1e-5
        Jc[:, :, j] = (corner(q + e) - corner(q - e)) / 2e-5
    return r, np.einsum("nij,njk->nik", Jc, J)


def add_object(name, mat, verts, faces, P, fmat=None, convex=False):
    """New mesh (grid points verts, faces wound outward; convex: wound away from the points' mean instead) in the FBX's
    world frame, flat normals, material by name (mat: a name, or names with fmat each face's index into them)."""
    import bpy
    if convex:
        V, c = np.asarray(verts, float), np.mean(verts, 0)
        faces = [f if np.cross(V[f[1]] - V[f[0]], V[f[-1]] - V[f[0]]) @ (V[list(f)].mean(0) - c) > 0 else f[::-1]
                 for f in faces]
    Pi = np.linalg.inv(P)
    me = bpy.data.meshes.new(name)
    me.from_pydata((np.asarray(verts) @ Pi[:3, :3].T + Pi[:3, 3]).tolist(), [], faces)
    for m in ([mat] if isinstance(mat, str) else mat):
        me.materials.append(bpy.data.materials[m])
    if fmat is not None:
        me.polygons.foreach_set("material_index", fmat)
    me.update()
    fn = []
    V = np.asarray(verts)
    for f in faces:
        n = np.cross(V[f[1]] - V[f[0]], V[f[-1]] - V[f[0]])
        fn += [n / np.linalg.norm(n)] * len(f)
    nw = np.array(fn) @ P[:3, :3]                        # convert.py load_source: grid n = n_world M^-1
    nw /= np.linalg.norm(nw, axis=1, keepdims=True)
    me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", nw.astype(np.float32).ravel())
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return len(faces)


def skid(P):
    """FIELD skid: the black block under the rear bumper (official SIDE: the bumper's flank runs on down to a bottom
    edge 0.25 -> 0.29 grid and a rear face at y -2.18; REAR34: the face inset, its corners chamfered). Sections
    (y, top z, bottom z, half width top, bottom), front to back; the top stays inside the bumper."""
    S = FIELD["skid"]
    V = []
    for y, zt, zb, ht, hb in S:
        V += [(-ht, y, zt), (ht, y, zt), (hb, y, zb), (-hb, y, zb)]
    F = []
    for i in range(len(S) - 1):
        a, b = 4 * i, 4 * i + 4
        F += [(a + 1, a, b, b + 1), (a + 2, a + 1, b + 1, b + 2), (a + 3, a + 2, b + 2, b + 3), (a, a + 3, b + 3, b)]
    n = 4 * (len(S) - 1)
    F += [(0, 1, 2, 3), (n + 3, n + 2, n + 1, n)]
    return add_object("Trim_CT_skid", "Black Plastick", V, F, P, convex=True)


def tail_ends(P, fmap):
    """FIELD tailends: the tail light bar's ends on the body's rear corners (official REAR34: the black band with its
    red strip runs corner to corner, the ends on the body beside the tailgate): per side a black plate over the corner
    block's rear face and the red strip on it, at the tailgate bar's heights (Body.003, Cube.030 through the field)."""
    te = FIELD["tailends"]
    m = lambda y, z: fmap(np.array([[0.0, y, z]]))[0][0, 1:]          # noqa: E731
    yf = m(te["face"][0], te["face"][1])[0] - te["off"]
    zb0, zb1 = (m(te["face"][0], z)[1] for z in te["band"])
    zs0, zs1 = (m(te["face"][0], z)[1] for z in te["strip"])
    V, F, M = [], [], []
    for s in (-1, 1):
        for (z0, z1), dy, mi in (((zb0, zb1), 0.0, 0), ((zs0, zs1), -0.001, 1)):
            k = len(V)
            V += [(s * te["x"][0], yf + dy, z0), (s * te["x"][1], yf + dy, z0), (s * te["x"][1], yf + dy, z1),
                  (s * te["x"][0], yf + dy, z1)]
            f = (k, k + 1, k + 2, k + 3)
            F.append(f if s < 0 else f[::-1])            # face -y (rearward)
            M.append(mi)
    V = np.array(V)
    for i, f in enumerate(F):                            # wound to face the rear
        if np.cross(V[f[1]] - V[f[0]], V[f[-1]] - V[f[0]])[1] > 0:
            F[i] = f[::-1]
    return add_object("Lamp_CT_tailend", ["Black Plastick", te["mat"]], V.tolist(), F, P, M)


def wells(P):
    """FIELD wells: black wheel wells behind the arch openings (convert.py's ARCH_LINER is a circle round the axle; the
    raised trapezoid openings' upper corners lie outside it and showed through): per arch and side a band along the
    opening's outline (the FIELD C line's targets, `off` out) from the cladding's inside in to `x_in`, and a wall
    closing it there; all faces toward the wheel."""
    W = FIELD["wells"]
    V, F = [], []
    for keys, x_in in W["arches"]:
        L = np.array([FIELD["ctrl"][k][1] for k in keys], float)
        c = L.mean(0)
        nrm = []
        for i in range(len(L)):                          # vertex offset: the mean of its segments' outward normals
            ns = []
            for a_, b_ in ((L[max(i - 1, 0)], L[i]), (L[i], L[min(i + 1, len(L) - 1)])):
                if (a_ != b_).any():
                    t = (b_ - a_) / np.linalg.norm(b_ - a_)
                    n = np.array([-t[1], t[0]])
                    ns.append(n if n @ ((a_ + b_) / 2 - c) > 0 else -n)
            m = np.mean(ns, 0)
            nrm.append(m / (m @ ns[0]))                  # mitred: each segment moves `off`
        O = L + W["off"] * np.array(nrm)
        for s in (-1, 1):
            k = len(V)
            V += [(s * W["x_out"], y, z) for y, z in O] + [(s * x_in, y, z) for y, z in O]
            n = len(O)
            ctr = np.array([s * (W["x_out"] + x_in) / 2, *c])
            for i in range(n - 1):
                F.append(((k + i, k + i + 1, k + n + i + 1, k + n + i), ctr))
            kc = len(V)
            V.append((s * x_in, *c))
            for i in range(n - 1):                       # the wall: a fan from the outline's centroid
                F.append(((kc, k + n + i, k + n + i + 1), np.array([s * 2.0, *c])))
    V = np.array(V)
    out = []
    for f, toward in F:                                  # wound to face `toward`
        nf = np.cross(V[f[1]] - V[f[0]], V[f[-1]] - V[f[0]])
        out.append(f if nf @ (toward - V[list(f)].mean(0)) > 0 else f[::-1])
    return add_object("Trim_CT_well", W["mat"], V.tolist(), out, P)


def light_bar(P):
    """FIELD lightbar: Tesla's Cybertruck Off-Road Light Bar (every Cybertruck here, V wheel), on the windshield: its top
    at the windshield's upper edge, lying on the glass (service manual "Off Road Lightbar (Retrofit)": align the upper
    portion of the light bar with the upper exterior portion of the windshield; brackets to the roof at its ends). A box
    on the glass plane: half width, length down the glass, thickness; black housing, the lower (front) end the lens."""
    lb = FIELD["lightbar"]
    (y0, z0), (y1, z1) = lb["top"], lb["foot"]               # the glass's visible top edge, a point down its slope
    d = np.array([0.0, y1 - y0, z1 - z0])
    d /= np.linalg.norm(d)                                    # down the glass
    n = np.array([0.0, -d[2], d[1]])                          # out of the glass
    if n[2] < 0:
        n = -n
    o = np.array([0.0, y0, z0]) + n * lb["gap"]
    V = []
    for x in (-lb["x"], lb["x"]):
        for a, b in ((0, 0), (lb["l"], 0), (lb["l"], lb["t"]), (0, lb["t"])):
            V.append(tuple(o + np.array([x, 0, 0]) + d * a + n * b))
    # 0-3 left (top-back, foot, foot-up, top-up), 4-7 right
    F = [(0, 1, 2, 3)[::-1], (4, 5, 6, 7), (3, 2, 6, 7), (0, 3, 7, 4), (1, 0, 4, 5), (2, 1, 5, 6)]
    return add_object("Lamp_CT_roofbar", ["Black Plastick", lb["lens"]], V, F, P, [0, 0, 0, 0, 0, 1], convex=True)


def head_bar(P, body):
    """FIELD headbar: the front light bar, one strip `dz` under the nose face's top edge from corner to corner and on
    along each flank (official FRONT34: one line from the far corner to the near one under the hood's front edge,
    wrapping round it; the source's strip stops at |x| 0.456 and resumes as a stub on each corner). The top edge: the
    hood's front edge, flat to |x| `x0` then rising across the chamfer to the corner (FIELD corner p1, p3 + d). Rays
    onto the moved body (grid frame) square to the face (the chamfer's in plan), the strip `off` out from the outermost
    surface over its height (the source's own strip is tucked under the hood's lip, hidden from above). -> faces."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    hb, cn = FIELD["headbar"], FIELD["corner"]
    bvh = BVHTree.FromPolygons([Vector(p) for p in body[0]], body[1])
    h, off, wrap, n = hb["h"], hb["off"], hb["wrap"], hb["n"]
    x0, ytop, ztop = cn["p1"]
    x1, y1, z1 = cn["p3"][0], cn["p3"][1] + cn["d"][0], cn["p3"][2] + cn["d"][1]
    zc = lambda ax: np.interp(ax, (x0, x1), (ztop - hb["dz"][0], z1 - hb["dz"][1]))   # noqa: E731
    ch = np.array([x1 - x0, y1 - ytop]) / np.hypot(x1 - x0, y1 - ytop)       # the chamfer's run in plan (+x side)
    cnrm = np.array([-ch[1], ch[0]])                                         # its outward normal

    def hit(o, d):                                       # the outermost surface over the strip's height
        hs = [bvh.ray_cast(Vector(o) + Vector((0, 0, dz)), Vector(d)) for dz in np.linspace(-h / 2, h / 2, 5)]
        h_ = min((x for x in hs if x[0] is not None), key=lambda x: x[3])
        nrm = h_[1] if h_[1].dot(Vector(d)) < 0 else -h_[1]                 # toward the ray's origin
        q = np.array(h_[0]) - np.array((0, 0, h_[0].z - o[2]))
        return q - np.array(d) * off, (nrm.x, nrm.y)
    line = []
    for x in np.linspace(-x1, x1, n):
        ax, sx = abs(x), np.sign(x) or 1.0
        z = zc(ax)
        if ax <= x0:
            p, nr = hit((x, 4.0, z), (0, -1, 0))
        else:                                              # square to the chamfer, from out in front of it
            e = np.array([x0, ytop]) + ch * (ax - x0) / ch[0]   # its top edge's line at |x| ax
            q = e + cnrm * 1.0
            p, nr = hit((sx * q[0], q[1], z), (-sx * cnrm[0], -cnrm[1], 0))
            if abs((np.array([sx * p[0], p[1]]) - e) @ cnrm) > hb["chamfer_tol"]:   # into the corner lamp's pocket:
                p, nr = np.array([sx * (e[0] + cnrm[0] * hb["chamfer_tol"]),     # on the line, out by the tolerance
                                  e[1] + cnrm[1] * hb["chamfer_tol"], z]), (sx * cnrm[0], cnrm[1])
        line.append((p[0], p[1], z, nr))
    for side, ends in ((-1, 0), (1, len(line))):           # on along the flanks from the corner, back to front
        fl = []
        for k in range(hb["n_side"]):
            y0 = y1 - wrap * (k + 1) / hb["n_side"]
            p, nr = hit((side * 2.0, y0, zc(x1)), (-side, 0, 0))
            fl.append((p[0], p[1], zc(x1), nr))
        line = fl[::-1] + line if side < 0 else line + fl
    V, F = [], []
    for x, y, z, _ in line:
        V += [(x, y, z - h / 2), (x, y, z + h / 2)]
    for i in range(len(line) - 1):
        a = 2 * i
        F.append((a, a + 2, a + 3, a + 1))
    for i, (x, y, z, nrm) in enumerate(line[:-1]):       # wind each quad to face out (its surface normal)
        p = np.array([V[F[i][j]] for j in range(3)])
        nz = np.cross(p[1] - p[0], p[2] - p[0])
        if nz[0] * nrm[0] + nz[1] * nrm[1] < 0:
            F[i] = F[i][::-1]
    return add_object("Lamp_CT_head", hb["mat"], V, F, P)


def panels(g, faces, cfg):
    """The source's flat panels: faces joined across shared edges while their normals agree within cfg ang (deg) and
    they lie in one plane within cfg tol (grid); panels of at least cfg area (grid^2). -> (panel per face or -1,
    face normals, face areas)."""
    nf, ar, cen = [], [], []
    for f in faces:
        P = g[f]
        n = sum(np.cross(P[i] - P[0], P[i + 1] - P[0]) for i in range(1, len(f) - 1))
        a = np.linalg.norm(n)
        nf.append(n / a if a > 0 else n)
        ar.append(a / 2)
        cen.append(P.mean(0))
    nf, ar, cen = np.array(nf), np.array(ar), np.array(cen)
    par = list(range(len(faces)))

    def root(i):
        while par[i] != i:
            par[i] = par[par[i]]
            i = par[i]
        return i
    edge = {}
    for fi, f in enumerate(faces):
        for k in range(len(f)):
            edge.setdefault(tuple(sorted((f[k], f[(k + 1) % len(f)]))), []).append(fi)
    ca = math.cos(math.radians(cfg["ang"]))
    for fs in edge.values():
        for i in fs[1:]:
            a, b = fs[0], i
            if nf[a] @ nf[b] > ca and abs(nf[a] @ (cen[b] - cen[a])) < cfg["tol"]:
                par[root(a)] = root(b)
    lab = np.array([root(i) for i in range(len(faces))])
    out = np.full(len(faces), -1)
    for k, r in enumerate(np.unique(lab)):
        m = lab == r
        if ar[m].sum() >= cfg["area"]:
            out[m] = k
    return out, nf, ar


def plane_fit(P, w=None):
    c = np.average(P, 0, w)
    n = np.linalg.svd((P - c) * (np.sqrt(w)[:, None] if w is not None else 1))[2][2]
    return n, n @ c


def flat_stats_of(g, q, faces, cfg):
    """FIELD flat: how flat each source panel (panels()) stays through the side-view map: per panel its area, the
    source's and the moved points' max deviation from their best-fit plane (grid) and normal spread (deg). Report
    only (prep_flat.json): projecting the moved points back onto planes (tried, 2026-11-12) pulled the panels' shared
    edges apart (dark wedges on the sail); the creases the game showed were the normals (main())."""
    pan, _, ar = panels(g, faces, cfg)
    out = []
    for k in np.unique(pan[pan >= 0]):
        fs = np.nonzero(pan == k)[0]
        vs = np.unique(np.concatenate([faces[i] for i in fs]))
        st = []
        for P in (g, q):
            n, d = plane_fit(P[vs])
            st += [float(np.abs(P[vs] @ n - d).max()),
                   float(max(np.degrees(np.arccos(min(1.0, abs(n @ fn(P, faces[i]))))) for i in fs))]
        out.append(dict(panel=int(k), centre=np.round(q[vs].mean(0), 3).tolist(), area=float(ar[fs].sum()),
                        src=st[:2], moved=st[2:]))
    return out


def fn(P, f):
    n = sum(np.cross(P[f[i]] - P[f[0]], P[f[i + 1]] - P[f[0]]) for i in range(1, len(f) - 1))
    return n / max(np.linalg.norm(n), 1e-15)


def main():
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=SRC)
    P = frame()
    maps = {}
    n = 0
    body = None
    flat_stats = []
    for o in [o for o in bpy.data.objects if o.type == "MESH"]:
        me = o.data
        if not len(me.vertices):
            continue
        M = P @ np.array(o.matrix_world)
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        g = co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
        faces = [list(p.vertices) for p in me.polygons]
        q, J = move(maps, o.name, g, faces, flat_stats)
        if o.name == "Body":
            body = (q, faces)
        Mi = np.linalg.inv(M)
        me.vertices.foreach_set("co", (q @ Mi[:3, :3].T + Mi[:3, 3]).ravel())
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.corner_normals.foreach_get("vector", cn)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        M3, M3i = M[:3, :3], np.linalg.inv(M[:3, :3])
        # grid normal ng = M^-T n; mapped ng' = J^-T ng; back n' = M^T ng'   (row vectors: n M^-1 J^-1 M)
        nn = cn.reshape(-1, 3).astype(float) @ M3i
        nn = np.einsum("li,lij->lj", nn, np.linalg.inv(J)[lv]) @ M3
        nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-12)
        # flat in the source (its corners on the face normal): flat after the move too, the face's new normal (or
        # its panel's plane); else the per-corner Jacobian above (piecewise constant over the field's triangles,
        # it drew the field's edges across flat panels as shading creases)
        n0 = cn.reshape(-1, 3).astype(float) @ M3i
        n0 /= np.maximum(np.linalg.norm(n0, axis=1, keepdims=True), 1e-12)
        ls = np.empty(len(me.polygons), np.int64)
        me.polygons.foreach_get("loop_start", ls)
        for fi, f in enumerate(faces):
            lo = slice(ls[fi], ls[fi] + len(f))
            f0 = fn(g, f)
            if (n0[lo] @ f0).min() > math.cos(math.radians(FIELD["flat"]["ang"])):
                fq = fn(q, f)
                nn[lo] = (fq @ M3) / np.linalg.norm(fq @ M3)           # grid -> world (row vectors, as above)
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector",
                                                                                       nn.astype(np.float32).ravel())
        me.update()
        n += int((np.abs(q - g) > 1e-9).any(1).sum())
    for o in [o for o in bpy.data.objects if o.type == "MESH" and not len(o.data.polygons)]:
        bpy.data.objects.remove(o)
    json.dump(flat_stats, open(os.path.join(SRC_DIR, "prep_flat.json"), "w"), indent=0)
    nsk, nhb = skid(P), head_bar(P, body)
    light_bar(P)
    tail_ends(P, maps[None])
    wells(P)
    bpy.ops.export_scene.fbx(filepath=OUT, use_selection=False, object_types={"MESH"}, mesh_smooth_type="OFF",
                             use_custom_props=False)
    print("PREP %d points moved, %d triangles, axle front %+.4f rear %+.4f, skid %d faces, head bar %d faces -> %s"
          % (n, len(maps[None].tri), FIELD["axle"]["front"], FIELD["axle"]["rear"], nsk, nhb, OUT))


def map_points():
    """stdin "name y z" (pre-centre grid) -> mapped (body field)."""
    fmap = Map()
    for line in sys.stdin:
        w = line.split()
        if len(w) < 3:
            continue
        g = np.array([[0.0, float(w[1]), float(w[2])]])
        q, _ = fmap(g)
        print("%-12s (%.4f, %.4f) -> (%.4f, %.4f)  d %+.4f %+.4f" % (w[0], *g[0, 1:], *q[0, 1:], *(q - g)[0, 1:]))


if __name__ == "__main__":
    if sys.argv[-1:] == ["map"]:
        map_points()
    else:
        main()
