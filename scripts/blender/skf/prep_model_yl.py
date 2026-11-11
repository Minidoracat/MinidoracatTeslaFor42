"""Model Y L source prep, run once before convert.py (CAR=model_yl): BloxBloger's "2025 Tesla Model Y" (the standard
car, Sketchfab, CC BY-NC 4.0; CREDITS.md) -> the six-seat long-wheelbase Model Y L at the owner's manual's size
(temp/plan-yl-1111 specs.md: length 4,969 without the plate bracket, width 1,920 without mirrors, height 1,668,
wheelbase 3,040, front overhang 889, rear 1,040; tyres 255/45 R19 front, 275/45 R19 rear), by one continuous
displacement field (no cuts: every source object and component keeps its triangles, so the config's CUT / GATE_COMPS
keys hold) plus one new object, the blade spoiler. Against the source (a Model Y 4,789 long, 1,944 wide over the rear
arch trims, front overhang 911, wheelbase 2,902, tyres 369 mm):
- width scaled about the centre line onto FIELD width;
- the bumper ahead of the front arch shortened onto the front overhang (FIELD nose);
- the front end lowered onto the official SIDE (FIELD nose_drop), the mirrors moved down and forward (FIELD mirror), the
  front splitter in its own lighter black (FIELD splitter);
- the rear wheel and its arch moved back onto the wheelbase, turned along itself (FIELD turn: a round arch stays round)
  so the rear door's rear edge, kept where the source has it (FIELD edge), meets it at about ten o'clock like the
  official SIDE render; the rear door's lower half, the sill and the quarter panel round the arch take the stretch: a
  harmonic (smoothest) field between those fixed parts (lower_grid), so the door's edge has no kinks;
- the tail moved back onto the rear overhang (FIELD tail, upper); the roof raised from the B pillar back (FIELD roof);
- the roof rails pulled up to the glass roof's crown (FIELD rail), the quarter window's tip moved back (quarter_tip);
- the source's duck lip lowered (FIELD gate, lip) and the spoiler built over it (blade(): a gloss black blade on a body
  colour ducktail down to the tail lamps, its own object, convert.py puts it on the tailgate by GATE_OBJS);
- the tail lamps' lower half raised (FIELD lamp);
- the rear bumper's lower black cladding: its corner fins pulled in onto the bumper (FIELD fins);
- the tyres (dropped by convert.py, only measured for the wheel) scaled about their centres to FIELD tyre, and the car
  set on them (the lowest tyre point = ground 0).
Normals: each corner's by the field's Jacobian, inverse transpose (finite differences).
Frame here: the OBJ's own (the importer leaves its axes in each object's rotation): x along the car, front -x,
metres; y up, ground 0; z across. u = metres behind the nose, h = height. Check: scripts/blender/skf/side_iou.py
against yl_MTY87_PN01_SIDE.png; the numbers: .claude/skills/tesla-dev/references/models-model-yl.md.
"""
import os
import sys

import numpy as np

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "temp", "skf_yl", "src", "source")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
src, out = (args + [os.path.join(SRC_DIR, "tesla.obj"), os.path.join(SRC_DIR, "model_yl.obj")][len(args):])[:2]

PLATES = ("Object_11", "Object_12")
TYRES = "Object005"
MIRRORS = ("Plane.046", "Plane.047", "Plane.048", "Plane.049", "Plane.050")
WHEEL = ("Object005", "Circle", "Cylinder", "Line0", "Object43")     # tyres, covers, rotors, calipers: moved whole
NOT_BODY = WHEEL + PLATES + MIRRORS + ("Interior", "Hyundai_KONA", "Plane.067")   # (convert.py DROP) for the width
# the field (metres; u behind the source's nose, h over the ground). Source landmarks: rear wheel centre u 3.812
# h 0.354, its arch trim radius 0.505 (the paint's opening 0.487); rear door u 2.57-3.70, its rear edge from the window
# corner (3.66, 1.18) down to the arch at (3.62, 0.81); belt h 1.06; roof glass ends u 3.74, tail u 4.79 (the lower
# cladding's corner fins; the bumper 4.73). Calibration knobs, fitted on side_iou and the official SIDE render
FIELD = dict(
    width=1.920,                    # without mirrors, over the rear arch trims (the widest part)
    tyre=0.356,                     # 255/45 R19 (the front's; the rear 275/45 R19 is 365: one wheel model per car)
    front=0.889,                    # front overhang: the bumper ahead of u nose[1] shortened, ramp from nose[0]
    nose=(0.02, 0.40),
    # the front end sat high against the official SIDE (hood edge, light bar 40-45 mm, lower lamp slot 30 mm, nose's
    # bottom 15 mm, front arch top 25 mm; the sill and the belt match): down d[0] + d[1] x s(h over h), fading out over
    # u (the windscreen's foot stays)
    nose_drop=dict(u=(0.75, 1.20), h=(0.30, 0.80), d=(0.016, 0.026)),
    # the front splitter (the lower cladding ahead of the front arches, source u < u, h < h) in its own material: the
    # official FRONT34 reads it as a lit grey lip under the near-black intake, the source's black ran on as one band
    splitter=dict(objs=("Plane.021",), u=0.37, h=0.33, mat="splitter_black"),
    # the mirror (cap, arm, glass ring, glass): forward, down onto the official SIDE's (it sat 31 mm high, 12 mm back),
    # x s(|z| over z): the arm's foot on the door (and the sail) stays, the arm shears, the head moves whole
    mirror=dict(objs=("Plane.046", "Plane.048", "Plane.049", "Plane.050"), d=(-0.012, -0.030), z=(0.78, 0.86)),
    wheelbase=3.040,
    wheel=(0.354, 0.505),           # rear arch centre h (u: the tyres'), the trim's outer radius: moved whole inside
    turn=(-23.3, -9.5, 110.0),      # inside: a point at angle phi (deg from the top, + rearward) turned to phi + d,
    #                                 d = turn[1] at turn[0] (the door's corner), 0 past +-turn[2]
    door=(2.75, 3.45, 0.030),       # everything (all h) behind the rear door's front ramps door[2] back: the Y L's rear
    #                                 door is that much longer than the Y's at its handle, window bar and rear edge
    edge=((3.642, 0.870), (3.658, 0.930), (3.673, 0.985), (3.688, 1.041), (3.695, 1.071), (3.704, 1.100)),
    edge_du=(0.020, 1.00, 1.06),    # rear door's rear edge (source vertices): the lower field there edge_du[0] under h
    #                                 edge_du[1], 0 over edge_du[2] (with `door`: upright like the official's)
    fixed=2.75,                     # the lower field is 0 ahead of this u (the rear door's front edge, sill)
    tail=(4.70, 0.95, 0.116),      # behind u tail[0], under h tail[1]: the bumper moves whole, tail[2] more than the
    #                                 arch (rear overhang 1,040)
    band=(0.86, 1.06),              # lower field below h band[0], upper shift above band[1]
    upper=(3.62, 4.20, 0.184),      # upper shift (over `door`) ramps over u (window bar -> behind the quarter window's
                                    # tip: the Y L's quarter window is that much longer than the Y's; on to the tail
                                    # lamps a plain shift)
    # the quarter window's lower edge brought down to the official SIDE's (it sits 2.5-6.5 cm high after the stretch):
    # down d x a bump over source u (up over u[0..1], down over u[2..3]) x a tent over the height after the other
    # terms (up over h[0..1], down over h[2..3]: the belt and the roof rail stay) x the side (|z| over z: the rear
    # glass, |z| <= 0.55, stays)
    quarter=dict(u=(3.64, 3.85, 4.02, 4.14), h=(1.12, 1.30, 1.40, 1.56), z=(0.555, 0.605), d=0.065),
    # its tip (source (4.046, 1.345), the frame's) 70 mm short and 20 mm low on the official SIDE through the fitted
    # camera (the earlier de-perspective overlay scaled the official about the image centre, so it read the near side's
    # tip that much forward): moved d x a bump (smoothstep in the ellipse's radius: u ahead / behind, h) x the side
    quarter_tip=dict(c=(4.046, 1.345), u=(0.35, 0.25), h=0.14, z=(0.555, 0.605), d=(0.070, 0.020)),
    roof=((2.30, 0.0), (2.55, 0.008), (2.90, 0.031), (3.30, 0.067), (3.66, 0.097), (3.95, 0.112), (4.20, 0.100),
          (4.40, 0.085), (4.60, 0.050), (4.80, 0.035)),   # raise at the top (source u)
    roof_h=1.00,                    # the raise fades to 0 at this height (under the belt): top(u) gets all of it
    # the roof rails up to the glass: the source's glass crowns 30-35 mm over its body-colour rails, so the official
    # FRONT34 / REAR34 (cameras at roof height) see a rail band 25-30 mm taller and no glass over it (SIDE: the band
    # over the side windows 11-15 px, the source's 7-9). Points pulled up k of their way to the crown (top(u) + roof:
    # nothing passes it, the height holds) x a bump over u (the glass roof's length) x the top band (h over the crown
    # minus h[0]..h[1]: the side windows and their frame stay) x the side (|z| over z: the glass flattens to its edges)
    rail=dict(u=(2.15, 2.40, 3.70, 3.95), h=(0.065, 0.035), z=(0.30, 0.55), k=0.8),
    gate=(4.30, 4.50, 1.15, 1.30, 1.48, 0.070),   # the tailgate's top lowered onto the Y L's (its rear glass reaches
    #                                 lower, the blade over the joint): behind u gate[0]..[1], h gate[2]..[4] (source)
    #                                 squashed down, gate[5] at h gate[3] (the glass's end), the tail lamps under it kept
    lip=(4.60, 4.73, 1.15, 1.22, 0.030),   # the duck lip (the tailgate's top edge under the blade) back to the Y L's:
    #                                 points behind u lip[0]..[1] and over h lip[2]..[3] (source) lip[4] forward
    lamp=(4.20, 4.32, 0.90, 0.97, 1.08, 0.025),   # the tail lamps' lower half up onto the Y L's (official SIDE: the
    #                                 lamp's foot 16-28 mm higher; REAR34's corner lamps sit ~45 mm low top and bottom
    #                                 alike, its camera pitch is less sure: SIDE wins): behind u lamp[0]..[1], h
    #                                 lamp[2]..[4] (source) up by lamp[5] at h lamp[3] (their bottom), the shelf kept
    # the spoiler (blade()): a gloss black blade over a body colour ducktail (official REAR34 / SIDE in all six
    # colours: the blade's trailing face and top are the same black in each, the face under it down to the tail lamps
    # takes the paint), from the rear glass frame's end (BLADE_ROOT, final frame) to the trailing edge. Final u, h
    # (metres), z across: half span; the trailing edge's u, its top and its bottom h, each (middle, x z^2); the chord
    # at most `chord` (the root follows the glass's end, which curves forward much more than the trailing edge); the
    # root's thickness over the body; the ducktail's rear face from the trailing edge's bottom down to its foot at h
    # `foot` (the tail lamps' top, found from behind, at most `reach` ahead of the trailing edge: the ends overhang the
    # narrowing tail), hollowed `concave` forward at mid height. Trailing edge to the tips as f = (1 - |z / span| ^
    # tip[0]) ^ tip[1] (rounded in plan); stations each side. Fitted on REAR34 (trailing face h 1.288-1.335 at the
    # middle; far tip x 1501) and SIDE (near tip u 4.90, h 1.29 at |z| 0.58)
    blade=dict(span=0.66, te=(4.95, -0.18), chord=0.21, top=(1.335, -0.12), bot=(1.288, -0.06), root=0.020,
               foot=1.150, reach=0.08, concave=0.030, tip=(30.0, 0.5), n=12),
    # dark strips inside door gaps that one sees through from the side (blackout()): the rear door's rear edge where
    # it runs over the quarter's shoulder, above the belt (the two panels end in return flanges 3 mm apart, so one sees
    # between them into the cabin; convert.py's panel-gap strips lie along the flanges, edge-on), and the lower ends
    # of the B pillar's gap and the front door's front gap, under the cabin's floor. Source (u, h, |z|) of each gap's
    # outer edge; a strip `inset` inboard of it, `half` either side of it along u
    blackout=dict(lines=(((3.636, 1.215, 0.728), (3.6456, 1.1817, 0.7359), (3.6852, 1.145, 0.7538),
                          (3.7045, 1.0998, 0.8549), (3.6952, 1.0712, 0.8702), (3.6878, 1.0412, 0.8849),
                          (3.6729, 0.9851, 0.9123)),
                         ((2.5735, 0.578, 0.910), (2.5728, 0.4884, 0.925), (2.5813, 0.4183, 0.904),
                          (2.5902, 0.3491, 0.882), (2.598, 0.3006, 0.874), (2.598, 0.27, 0.870)),
                         ((1.4025, 0.5456, 0.941), (1.4182, 0.4002, 0.928), (1.4235, 0.3604, 0.919),
                          (1.429, 0.3204, 0.911), (1.4343, 0.2785, 0.902), (1.436, 0.25, 0.898))),
                  inset=0.04, half=0.025),
    # the rear bumper's lower cladding's corner lip stuck 5-10 cm out past the bumper in the side view (a spike): its
    # points behind u zone[0], h zone[1]..zone[2] held at most `margin` behind the reference parts' rearmost point
    # within `near` (h, z) of them (source frame, before the field). (The diffuser's lip, Plane.026, the other spike
    # and the teeth under the bumper seen low from behind: cars/model_yl.py DROP)
    fins=dict(objs=("Plane.021",), ref=("Plane", "Plane.022"), zone=(4.40, 0.15, 0.70), near=(0.03, 0.05),
              margin=0.01),
)
GRID = (2.40, 5.20, -0.10, 1.10, 0.01)   # lower_grid: u0, u1, h0, h1, step
BLADE_ROOT = "Plane.006"           # the rear glass frame: the blade's leading edge along its rear end
BLADE_MAT = "spoiler_black"        # cars/model_yl.py MAT_RGB
BLADE_PAINT = "Material_#2125765635"   # the body paint (cars/model_yl.py PAINT_MAT): the ducktail under the blade
BLADE_HULL = ("Plane", "Plane.006", "Plane.011", "Plane.034", "Plane.041", "Plane.043")   # what blade() sits on
BLACKOUT_MAT = "black_base"        # the source's black trim


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


def door(u):
    f = FIELD["door"]
    return f[2] * s(u, f[0], f[1])


def upper(u):
    f = FIELD["upper"]
    return f[2] * s(u, f[0], f[1])


def turn(u, h, uw, rear):
    """(du, dh) of the arch disc: moved `rear` back, a point at angle phi turned to phi + d(phi) about the centre."""
    hw = FIELD["wheel"][0]
    pc, pd, pe = FIELD["turn"]
    du0, dh0 = u - uw, h - hw
    r = np.hypot(du0, dh0)
    phi = np.degrees(np.arctan2(du0, dh0))
    d = np.where(phi < pc, pd * s(phi, -pe, pc), pd * (1 - s(phi, pc, pe)))
    p2 = np.radians(phi + d)
    return rear + r * np.sin(p2) - du0, r * np.cos(p2) - dh0


def lower_grid(uw, rear):
    """The field under the band on a grid: harmonic (du, dh) between the fixed parts (Dirichlet): nothing ahead of
    `fixed`, the arch disc (turn()), the rear door's edge (0), the bumper (rear + tail[2]), the band's top (upper());
    the ground row free (mirrored). Red-black SOR."""
    u0, u1, h0, h1, st = GRID
    U, H = np.meshgrid(np.arange(u0, u1 + st / 2, st), np.arange(h0, h1 + st / 2, st))
    fu, fh = np.zeros_like(U), np.zeros_like(U)
    fix = U <= FIELD["fixed"]
    dd = door(U)                                           # (field() adds it on top)
    t0, t1, t2 = FIELD["tail"]
    m = (U >= t0) & (H <= t1)
    fu[m], fix = (rear + t2 - dd)[m], fix | m
    m = np.hypot(U - uw, H - FIELD["wheel"][0]) <= FIELD["wheel"][1]
    fu[m], fh[m] = turn(U[m], H[m], uw, rear)
    fu[m] -= dd[m]
    fix |= m
    e, (ev, e0, e1) = np.array(FIELD["edge"]), FIELD["edge_du"]
    for (ua, ha), (ub, hb) in zip(e[:-1], e[1:]):          # the edge's nodes: within a cell of its segments
        t = np.clip(((U - ua) * (ub - ua) + (H - ha) * (hb - ha)) / ((ub - ua) ** 2 + (hb - ha) ** 2), 0, 1)
        m = np.hypot(U - ua - t * (ub - ua), H - ha - t * (hb - ha)) <= st * 0.75
        fu[m], fh[m], fix = ev * (1 - s(H[m], e0, e1)), 0, fix | m
    fu[-1], fh[-1] = upper(U[-1]), 0
    fix[-1] = True
    fix[:, -1] = True
    fu[:, -1] = np.where(H[:, -1] <= t1, rear + t2 - dd[:, -1], upper(U[:, -1]))
    red = (np.add.outer(np.arange(U.shape[0]), np.arange(U.shape[1])) % 2 == 0)
    for f in (fu, fh):
        for it in range(4000):
            last = f.copy() if it % 200 == 0 else None
            for colour in (red, ~red):
                nb = np.zeros_like(f)
                nb[1:-1, 1:-1] = (f[:-2, 1:-1] + f[2:, 1:-1] + f[1:-1, :-2] + f[1:-1, 2:]) / 4
                nb[0, 1:-1] = (2 * f[1, 1:-1] + f[0, :-2] + f[0, 2:]) / 4   # the ground row: mirrored (no flux)
                upd = colour & ~fix
                upd[-1] = upd[:, 0] = upd[:, -1] = False
                f[upd] += 1.9 * (nb[upd] - f[upd])
            if last is not None and np.abs(f - last).max() < 1e-7:
                break
    return U[0], H[:, 0], fu, fh


def sample(g, u, h):
    """Bilinear sample of a lower_grid field (us, hs, fu, fh) at points (u, h), clamped to the grid."""
    us, hs, fu, fh = g
    st = us[1] - us[0]
    x = np.clip((u - us[0]) / st, 0, len(us) - 1.000001)
    y = np.clip((h - hs[0]) / st, 0, len(hs) - 1.000001)
    i, j = x.astype(int), y.astype(int)
    a, b = x - i, y - j
    out = []
    for f in (fu, fh):
        out.append(f[j, i] * (1 - a) * (1 - b) + f[j, i + 1] * a * (1 - b) + f[j + 1, i] * (1 - a) * b
                   + f[j + 1, i + 1] * a * b)
    return out


def field(u, h, az, prof, g, nose):
    """(du, dh): rearward and upward displacement of points (u, h, |z - zc| = az)."""
    f = FIELD
    lu, lh = sample(g, u, h)
    w = s(h, *f["band"])
    l0, l1, h0, h1, ld = f["lip"]
    du = nose * (1 - s(u, *f["nose"])) + door(u) + lu * (1 - w) + upper(u) * w - ld * s(u, l0, l1) * s(h, h0, h1)
    ru, rz = np.array(f["roof"]).T
    top = np.interp(u, *prof)
    g0, g1, gh0, ghm, gh1, gd = f["gate"]
    nd = f["nose_drop"]
    m0, m1, mh0, mhm, mh1, md = f["lamp"]
    dz = lh * (1 - w) + np.interp(u, ru, rz) * np.clip((h - f["roof_h"]) / np.maximum(top - f["roof_h"], 0.05), 0, 1) \
        - gd * s(u, g0, g1) * s(h, gh0, ghm) * (1 - s(h, ghm, gh1)) \
        - (nd["d"][0] + nd["d"][1] * s(h, *nd["h"])) * (1 - s(u, *nd["u"])) \
        + md * s(u, m0, m1) * s(h, mh0, mhm) * (1 - s(h, mhm, mh1))
    q = f["quarter"]
    h1 = h + dz
    dz = dz - q["d"] * s(u, *q["u"][:2]) * (1 - s(u, *q["u"][2:])) * s(h1, *q["h"][:2]) * (1 - s(h1, *q["h"][2:])) \
        * s(az, *q["z"])
    qt = f["quarter_tip"]
    qb = s(np.hypot((u - qt["c"][0]) / np.where(u < qt["c"][0], *qt["u"]), (h - qt["c"][1]) / qt["h"]), 1, 0) \
        * s(az, *qt["z"])
    du, dz = du + qt["d"][0] * qb, dz + qt["d"][1] * qb
    r = f["rail"]
    t = top + np.interp(u, ru, rz)                        # the crown after the roof raise
    dz = dz + r["k"] * (t - h - dz) * s(u, *r["u"][:2]) * (1 - s(u, *r["u"][2:])) \
        * s(h + dz, t - r["h"][0], t - r["h"][1]) * s(az, *r["z"])
    return du, dz


def base(o):
    return o.name.split("_Mesh")[0]


def fins(co, nose):
    """Pull the FIELD fins points in (co: object -> OBJ points, changed in place). Returns how many moved."""
    f = FIELD["fins"]
    u0, h0, h1 = f["zone"]
    u0 += nose
    ref = np.concatenate([c for o, c in co.items() if base(o) in f["ref"]])
    ref = ref[ref[:, 0] > u0 - 0.2]
    n = 0
    for o, c in co.items():
        if base(o) not in f["objs"]:
            continue
        for i in np.flatnonzero((c[:, 0] > u0) & (c[:, 1] > h0) & (c[:, 1] < h1)):
            m = (np.abs(ref[:, 1] - c[i, 1]) < f["near"][0]) & (np.abs(ref[:, 2] - c[i, 2]) < f["near"][1])
            if m.any() and c[i, 0] > ref[m, 0].max() + f["margin"]:
                c[i, 0] = ref[m, 0].max() + f["margin"]
                n += 1
    return n


def blackout(fld, wk, lift, nose, zc):
    """The strips inside the FIELD blackout gaps, both sides (final frame, OBJ axes): (vertices, faces)."""
    b = FIELD["blackout"]
    V, F = [], []
    for line in b["lines"]:
        p = np.array(line)
        for side in (-1, 1):
            o = len(V)
            for u, h, z in p:
                for du0 in (-b["half"], b["half"]):
                    du, dz = fld(np.array([u + du0]), np.array([h]), np.array([z]))
                    V.append((nose + u + du0 + du[0], h + dz[0] + lift, zc + side * (z - b["inset"]) * wk))
            for i in range(len(p) - 1):
                q = (o + 2 * i, o + 2 * i + 1, o + 2 * i + 3, o + 2 * i + 2)
                F.append(q if side > 0 else q[::-1])
    return np.array(V), F


def new_nose(new):
    return min(p2[:, 0].min() for o, (p2, n) in new.items() if not o.name.startswith(PLATES))


def blade(frame, nose, zc, bvh):
    """The spoiler's mesh (final frame, OBJ axes): stations across, a six-sided section each, black blade over a body
    colour ducktail. Root on the rear glass frame's end (frame: that object's points), a little into the body (bvh: the
    body as prepped); the blade's top up to the trailing edge, its blunt trailing face; under it the ducktail's
    concave rear face down to its foot on the tail lamps' top (found from behind, a little in); open at the bottom,
    inside the body. End caps. Returns (vertices, faces, black: per face)."""
    from mathutils import Vector
    b = FIELD["blade"]
    u, h, z = frame[:, 0] - nose, frame[:, 1], frame[:, 2] - zc
    zs = b["span"] * np.linspace(-1, 1, 2 * b["n"] + 1)
    pts = []                                    # the frame's rear end across the glass, its bottom edge (the side
    h0 = h[(np.abs(z) < 0.05) & (u > 4.3)].min()   # pieces run up the C pillars): u as a quadratic in z
    for x in np.linspace(-0.5, 0.5, 21):
        m = (np.abs(z - x) < 0.04) & (u > 4.3) & (h > 1.1) & (h < h0 + 0.03)
        if m.any():
            k = np.flatnonzero(m)[np.argmax(u[m])]
            pts.append((z[k], u[k], h[k]))
    q = np.array(pts)
    te = b["te"][0] + b["te"][1] * zs ** 2
    ru = np.maximum(np.polyval(np.polyfit(q[:, 0] ** 2, q[:, 1], 1), zs ** 2) - 0.020, te - b["chord"])
    f = (1 - np.abs(zs / b["span"]) ** b["tip"][0]) ** b["tip"][1]     # the tips rounded in plan
    te = ru + (te - ru) * np.maximum(f, 0.15)
    tt = b["top"][0] + b["top"][1] * zs ** 2
    tb = tt - (tt - b["bot"][0] - b["bot"][1] * zs ** 2) * np.maximum(f, 0.3)

    def hit(o, d):
        p = bvh.ray_cast(Vector(o), Vector(d))[0]
        if p is None:
            raise SystemExit(f"blade: no body from {np.round(o, 3).tolist()} along {d}")
        return p
    rh = np.array([hit((nose + a, 2.5, zc + c), (0, -1, 0)).y for a, c in zip(ru, zs)]) - 0.015
    fu = np.array([hit((nose + 6.0, b["foot"], zc + c), (-1, 0, 0)).x - nose for c in zs]) - 0.010
    fu = np.maximum(fu, te - b["reach"])       # the ends overhang the narrowing tail: their foot on the lamps' top
    uh = (tb + b["foot"]) / 2                  # the hollow's middle, kept 6 mm behind the tailgate's own top (the two
    gu = [bvh.ray_cast(Vector((nose + 6.0, a, zc + c)), Vector((-1, 0, 0)))[0] for a, c in zip(uh, zs)]   # fought)
    uu = np.maximum((te + fu) / 2 - b["concave"], [p.x - nose + 0.006 if p else -9 for p in gu])
    sec = [np.stack([ru, rh]), np.stack([ru - 0.004, rh + 0.015 + b["root"]]), np.stack([te, tt]),
           np.stack([te - 0.002, tb]), np.stack([uu, uh]), np.stack([fu, np.full_like(zs, b["foot"])])]
    #                                            L, LT, TT, TB, U, S: (u, h) rows
    m = len(zs)
    V = [np.stack([p[0] + nose, p[1], zs + zc], 1) for p in sec]
    F, black = [], []
    for i in range(5):                          # top, trailing face: black; the leading face (body colour where it
        a, c = i * m, (i + 1) * m               # shows, at the ends), the rear face: paint; no bottom (inside the
        F += [(a + k, a + k + 1, c + k + 1, c + k) for k in range(m - 1)]   # body)
        black += [i in (1, 2)] * (m - 1)
    for k, w in ((0, 1), (m - 1, -1)):          # end caps: paint (the official SIDE: body colour where the blade
        F += [tuple(np.array((1, 2, 3))[::w] * m + k), tuple(np.array((0, 1, 3, 4, 5))[::w] * m + k)]   # ends)
        black += [False, False]
    return np.concatenate(V), F, black


def main():
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=src, forward_axis="NEGATIVE_Z", up_axis="Y")
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    co = {o: np.array([v.co[:] for v in o.data.vertices]) for o in obs}      # OBJ coordinates (x, y up, z)
    allc = np.concatenate([c for o, c in co.items() if not o.name.startswith(PLATES)])
    nose = allc[:, 0].min()
    zc = (allc[:, 2].min() + allc[:, 2].max()) / 2
    body = np.concatenate([c for o, c in co.items() if not o.name.startswith(NOT_BODY)])
    wk = FIELD["width"] / (2 * np.abs(body[:, 2] - zc).max())
    nfin = fins(co, nose)
    tyre = np.concatenate([c for o, c in co.items() if o.name.startswith(TYRES)])
    ax = {k: (tyre[m, 0].min() + tyre[m, 0].max()) / 2 - nose for k, m in
          (("f", tyre[:, 0] - nose < 2.5), ("r", tyre[:, 0] - nose >= 2.5))}
    hw = {k: (tyre[m, 1].min() + tyre[m, 1].max()) / 2 for k, m in
          (("f", tyre[:, 0] - nose < 2.5), ("r", tyre[:, 0] - nose >= 2.5))}
    tk = FIELD["tyre"] / (np.ptp(tyre[tyre[:, 0] - nose < 2.5, 1]) / 2)
    shorten = ax["f"] - FIELD["front"]                      # the nose moves this far back
    rear = ax["f"] + FIELD["wheelbase"] - ax["r"]           # the rear axle this far
    ends = []
    for o, c in co.items():
        if not o.name.startswith(PLATES):
            e = np.empty(len(o.data.edges) * 2, np.int64)
            o.data.edges.foreach_get("vertices", e)
            ends.append(c[e.reshape(-1, 2)][:, :, :2] - (nose, 0))
    ends = np.concatenate(ends)
    prof = top_profile(ends[:, 0], ends[:, 1])
    g = lower_grid(ax["r"], rear)
    fld = lambda u, h, az: field(u, h, az, prof, g, shorten)
    E = 1e-4
    new = {}
    for o in obs:
        me = o.data
        p = co[o]
        u, h, az = p[:, 0] - nose, p[:, 1], np.abs(p[:, 2] - zc)
        J = np.zeros((len(p), 3, 3))
        J[:, 2, 2] = wk
        if o.name.startswith(WHEEL):        # wheels: moved whole with their axle; the tyres scaled to FIELD tyre
            k = "f" if u.mean() < 2.5 else "r"
            sc = tk if o.name.startswith(TYRES) else 1.0
            du = (ax[k] + (u - ax[k]) * sc - u) + (rear if k == "r" else 0)
            dz = (hw[k] + (h - hw[k]) * sc) - h
            J[:, 0, 0] = J[:, 1, 1] = sc
        else:
            du, dz = fld(u, h, az)
            if o.name.startswith(FIELD["mirror"]["objs"]):   # the Jacobian skips it: the arm's shear is black trim
                k = s(az, *FIELD["mirror"]["z"])
                du, dz = du + k * FIELD["mirror"]["d"][0], dz + k * FIELD["mirror"]["d"][1]
            # Jacobian of (x, y, z) -> (x + du, y + dz, z wk) by central differences
            dxu = [(a - b) / (2 * E) for a, b in zip(fld(u + E, h, az), fld(u - E, h, az))]
            dxh = [(a - b) / (2 * E) for a, b in zip(fld(u, h + E, az), fld(u, h - E, az))]
            dxz = [(a - b) / (2 * E) for a, b in zip(fld(u, h, az + E), fld(u, h, az - E))]
            J[:, 0, 0], J[:, 0, 1], J[:, 0, 2] = 1 + dxu[0], dxh[0], dxz[0] * np.sign(p[:, 2] - zc)
            J[:, 1, 0], J[:, 1, 1], J[:, 1, 2] = dxu[1], 1 + dxh[1], dxz[1] * np.sign(p[:, 2] - zc)
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.corner_normals.foreach_get("vector", cn)
        lv = np.empty(len(me.loops), np.int64)
        me.loops.foreach_get("vertex_index", lv)
        n = np.einsum("lij,li->lj", np.linalg.inv(J)[lv], cn.reshape(-1, 3))   # n' = J^-T n (row vector n J^-1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        p2 = p.copy()
        p2[:, 0] += du
        p2[:, 1] += dz
        p2[:, 2] = zc + (p[:, 2] - zc) * wk
        new[o] = (p2, n)
    # the ground: the lowest tyre vertex (the script's wheels and the seat heights take the ground as the tyres'
    # bottom, seat_head.py's depth reference)
    lift = -min(p2[:, 1].min() for o, (p2, n) in new.items() if o.name.startswith(TYRES))
    for o, (p2, n) in new.items():
        me = o.data
        p2[:, 1] += lift
        me.vertices.foreach_set("co", p2.ravel())
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", n.astype(np.float32).ravel())
        me.update()
    sp = FIELD["splitter"]
    for o in obs:
        if base(o) in sp["objs"]:
            me, c = o.data, co[o]
            me.materials.append(bpy.data.materials.get(sp["mat"]) or bpy.data.materials.new(sp["mat"]))
            for poly in me.polygons:
                q = c[list(poly.vertices)].mean(0)
                if q[0] - nose < sp["u"] and q[1] < sp["h"]:
                    poly.material_index = len(me.materials) - 1
    from mathutils.bvhtree import BVHTree
    hull = [o for o in obs if base(o) in BLADE_HULL]
    k = np.cumsum([0] + [len(new[o][0]) for o in hull])
    bvh = BVHTree.FromPolygons([tuple(v) for o in hull for v in new[o][0]],
                               [[i + k0 for i in p.vertices] for o, k0 in zip(hull, k) for p in o.data.polygons])
    bv, bf, black = blade(new[[o for o in obs if base(o) == BLADE_ROOT][0]][0], new_nose(new), zc, bvh)
    for name, (bv, bf, mi), mats in (
            ("Blade_YL", (bv, bf, np.logical_not(black).astype(int)), (BLADE_MAT, BLADE_PAINT)),
            ("Blackout_YL", blackout(fld, wk, lift, nose, zc) + (None,), (BLACKOUT_MAT,))):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in bv], [], bf)
        for mat in mats:
            me.materials.append(bpy.data.materials.get(mat) or bpy.data.materials.new(mat))
        if mi is not None:                      # the ducktail's faces smooth (its concave face read faceted)
            me.polygons.foreach_set("material_index", mi)
            me.polygons.foreach_set("use_smooth", [bool(m == 1 and len(f) == 4) for m, f in zip(mi, bf)])
        me.update()
        bo = bpy.data.objects.new(name, me)
        bo.matrix_world = obs[0].matrix_world.copy()          # the importer's axes, as every source object
        bpy.context.scene.collection.objects.link(bo)
        obs.append(bo)
    print("PREP nose %.4f back, rear axle %.4f back, width x %.5f, tyres x %.4f, lifted %.4f, fins %d points" % (
        shorten, rear, wk, tk, lift, nfin))
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.ops.wm.obj_export(filepath=out, export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y",
                          export_uv=False, export_normals=True, export_materials=True, apply_modifiers=False,
                          export_triangulated_mesh=False)
    print("PREP ->", out)


if __name__ == "__main__":
    main()
