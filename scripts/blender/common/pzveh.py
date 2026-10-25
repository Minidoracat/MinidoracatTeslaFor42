"""Shared Model Y build code (scripts/blender/skf/convert.py, cabin.py, damage_cover.py): paths, mesh helpers, the
door slab and skeleton export, damage-map UV1 from vanilla ModernCar, paint ramps from the official design-studio
renders, the procedural wheel, the vehicle-script geometry block. Axes (Blender): +Y front, +Z up, -X = car left
(driver side), 1 unit = 1 grid; same as vanilla raw FBX coords (vanilla.py). Vehicle script: x = -mesh x, y = mesh z,
z = mesh y, unscaled = grid / 1.82. Numbers and sources: .claude/skills/tesla-dev/references/models.md.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from bpy_extras import mesh_utils
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
import vanilla  # noqa: E402

TMP = os.path.join(REPO, "temp", "skf")
OFFICIAL = os.path.join(TMP, "official")    # design-studio renders (stage_official)
MEDIA = os.path.join(REPO, "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media")
VEH_DIR = os.path.join(MEDIA, "models_X", "vehicles")
TEX_DIR = os.path.join(MEDIA, "textures", "Vehicles")
NAME = "MinidoracatTesla_ModelY"
K = 0.826                                   # grid per metre (R5 3), calibration knob
L, W, H = 4.790 * K, 1.920 * K, 1.624 * K   # official length, body width (no mirrors), height
# UV1 (shared Veh_Damage1/2, Veh_Rust, Veh_Blood_* 512 maps): taken over from this vanilla car (damage_uv1)
DAMAGE_REF, DAMAGE_REF_MASK = "Vehicles_ModernCar", "vehicle_carmodern_mask.png"
WHEEL_TEX, WHEEL_SS = 64, 8                 # wheel texture size; drawn WHEEL_SS times larger, then box-averaged
# wheel texture, all procedural. Official 19" Photon aero wheel: matte charcoal face, 5 turbine slots with a lit blade
# edge (official/*_FRONT34.png). Slot edges theta(r): luminance 5-fold median of an earlier wheel bake about its own
# centre, re-centred, per-radius dark run, quadratic rms 0.3 / 0.4 deg. r in wheel_r units, theta in the planar
# layout's image axes (x = -y / r, y = -z / r: x right, y down)
WHEEL_SLOT = dict(p1=(-1.4223, 1.7184, 0.1445), p2=(0.5977, -0.2715, 1.1813), rc=0.20, rim=0.665)
WHEEL_UV = dict(c=(0.5, 0.43), rho=0.40, tread=(0.865, 0.125))  # disc centre, UV radius of wheel_r; tread strip v0, h
# Game-screen sRGB grey levels (calibration knob, compare with game screenshots); wheel_texture turns each into the
# texture value that renders it: the vehiclewheel output measured on ModernCar's vanilla wheel in the same scenario is
# 0.143 * tex ** 1.395 (texture 37 / 105 / 169 / 189 -> 22 / ~115 / 193 / 214, tesla-modely-tex-1024e scale-S-zoomin).
# Vehicle textures get no mipmaps (ModelManager.java:1320-1322, TextureID.java:427): a 512 wheel sampled at ~10 texels
# per pixel aliased into specks and dotted rings, so it is drawn at 8x and box-averaged to 64 (the vanilla wheel's disc
# is 36 texels across). Official Photon cover: dark charcoal blades (~40-70), black slots, black tire (~21). Measured in
# tesla-wheel-1024c: face 58-72 renders ~75-86 (the curve reads the cover ~1.2x dark), tire ~17-32, slots 0-7
WHEEL_RGB = dict(face=(58, 72), deep=6, wall=(18, 45), shadow=6, blade=125, cap=62, cap_ring=95, lip=80, gap=8,
                 tire=(22, 28), tread=20)
WHEEL_SEG = 30                              # segments round the axle: 12 deg, under 0.2 px off a circle at zoom 0.5
# official Model Y paints (decisions.md "車款外觀"): skin order = vehicle script skin index = Core.lua colors order;
# saved games store the index (BaseVehicle.java:2635/2741), so after release only append
PAINTS = [("StealthGrey", "PN01"), ("PearlWhite", "PPSW"), ("DiamondBlack", "PX02"), ("Quicksilver", "PN00"),
          ("UltraRed", "PR01"), ("GlacierBlue", "PB01"), ("MarineBlue", "PB02"), ("FrostBlue", "PB00")]
GAIN = 0.88                                 # in-game day screen / texture sRGB (E2E tesla-modely-skin-1024c/d: red
#                                             0.80-0.86, white 0.90-0.97), calibration knob
# per-paint sRGB tone of the paint texels, tex = a * official-ramp colour / GAIN + b, one slope a for all three
# channels (per-channel slopes turned the colour along the ramp: Ultra Red's G slope above R / B made its highlights
# orange) and per-channel offsets b that put the in-game p50 on the official FRONT34 p50. a sets the p25-p75 spread
# against FRONT34; Pearl White takes a = 0.8 (a = 1 burns 12% of its texels to 255). Fitted with skf/convert.py
# PAINT_Q / PAINT_TARGET on in-game screenshots of the car heading S (modely-skin-sp, option 2, closest zoom;
# tesla-gloss-skinA-1026a) and the game camera's visible texels (offline view). Calibration knob: refit after
# changing the paint light; check with e2e/.../perf/paint_sheet.py
CAL = {
    "StealthGrey": ((0.88, 0.88, 0.88), (0.030, 0.016, 0.012)),
    "PearlWhite": ((0.80, 0.80, 0.80), (0.134, 0.129, 0.129)),
    "DiamondBlack": ((0.99, 0.99, 0.99), (0.073, 0.067, 0.063)),
    "Quicksilver": ((0.93, 0.93, 0.93), (-0.105, -0.114, -0.126)),
    "UltraRed": ((0.97, 0.97, 0.97), (-0.067, 0.078, 0.062)),
    "GlacierBlue": ((0.80, 0.80, 0.80), (0.003, -0.017, -0.029)),
    "MarineBlue": ((0.81, 0.81, 0.81), (0.084, 0.069, 0.039)),
    "FrostBlue": ((0.79, 0.79, 0.79), (0.072, 0.077, 0.100)),
}
COMPOSITOR = ("https://static-assets.tesla.cn/configurator/compositor?context=design_studio_2&options={}&view={}"
              "&model=my&size=1920&bkba_opt=1&crop=0,0,0,0&overlay=0&")
Z = {  # mask zone colours (media/shaders/vehicle_common.frag.h colZone*)
    "Head": (1, 0, 0), "Tail": (0, 1, 0), "DoorRH": (0, 1, 1), "DoorRT": (1, 1, 0), "DoorLH": (1, 0, 1), "DoorLT": (0, 0, 1),
    "WinRH": (0, .5, .5), "WinRT": (.5, .5, 0), "WinLH": (.5, 0, .5), "WinLT": (0, 0, .5), "WinT": (.5, 0, 0), "WinH": (0, .5, 0),
    "GuardRH": (0, .75, .75), "GuardRT": (.75, .75, 0), "GuardLH": (.75, 0, .75), "GuardLT": (0, 0, .75), "Roof": (0, 0, 0),
    "LightRH": (.25, 0, 0), "LightLH": (.75, 0, 0), "LightRT": (0, .75, 0), "LightLT": (0, .25, 0),
    "StopR": (.5, .25, 0), "StopL": (.5, .75, 0), "Hood": (1, 0, .5), "Boot": (0, 1, .5),
    "LightBarL": (.25, .25, .25),   # Tesla lights no LightBar: the roof glass's zone (no part, no damage)
}


def mesh_co(ob):
    a = np.empty(len(ob.data.vertices) * 3)
    ob.data.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def set_co(ob, co):
    ob.data.vertices.foreach_set("co", np.ascontiguousarray(co).ravel())
    ob.data.update()


def face_centres(ob):
    a = np.empty(len(ob.data.polygons) * 3)
    ob.data.polygons.foreach_get("center", a)
    return a.reshape(-1, 3)


def select_only(*obs):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in obs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = obs[-1]


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def dup(ob, name):
    d = ob.copy()
    d.data = ob.data.copy()
    d.name = name
    bpy.context.scene.collection.objects.link(d)
    return d


def keep_faces(ob, mask):
    """Delete the faces where mask is False (numpy bool per polygon)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f, k in zip(bm.faces, mask) if not k], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()


def decimate(ob, target, keep_boundary=False):
    """Collapse to target triangles (X symmetric). keep_boundary: open-edge vertices are left out of the decimate
    modifier's vertex group at factor 1000, so collapsing their edges costs that much more and the outline stays."""
    select_only(ob)
    for _ in range(3):                      # ratio is on triangles; repeat until within 3 %
        n = tris(ob)
        if n <= target * 1.03:
            break
        m = ob.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = target / n
        m.use_symmetry, m.symmetry_axis = True, "X"
        if keep_boundary:
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            edge = {v.index for e in bm.edges if e.is_boundary for v in e.verts}
            bm.free()
            if "interior" in ob.vertex_groups:
                ob.vertex_groups.remove(ob.vertex_groups["interior"])
            ob.vertex_groups.new(name="interior").add([i for i in range(len(ob.data.vertices)) if i not in edge],
                                                      1.0, "REPLACE")
            m.vertex_group, m.vertex_group_factor = "interior", 1000.0
        bpy.ops.object.modifier_apply(modifier=m.name)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=0.0005)
    # a collapse can fold two triangles onto the same three vertices; the FBX importer keeps one of them (readback
    # was 4 short), and the pair z-fights in game
    seen, twins = set(), []
    for f in bm.faces:
        k = frozenset(v.index for v in f.verts)
        if k in seen:
            twins.append(f)
        seen.add(k)
    bmesh.ops.delete(bm, geom=twins, context="FACES_ONLY")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def img_np(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)


def save_png(arr, path, name):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(arr, dtype=np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def box_blur(a, r):
    """Separable box blur (radius r px) of a 2-D array, edges clamped."""
    for ax in (0, 1):
        p = np.pad(a, [(r + 1, r) if i == ax else (0, 0) for i in range(2)], mode="edge")
        c = np.cumsum(p, axis=ax)
        a = (np.take(c, np.arange(2 * r + 1, c.shape[ax]), axis=ax) - np.take(c, np.arange(0, c.shape[ax] - 2 * r - 1), axis=ax)) / (2 * r + 1)
    return a


def export_fbx(ob, path):
    select_only(ob)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", bake_space_transform=True,
                             axis_forward="-Z", axis_up="Y", mesh_smooth_type="OFF",
                             add_leaf_bones=False, bake_anim=False, path_mode="STRIP")


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def wheel_slots(x, y, aa, widen=0.0):
    """Coverage (antialiased over aa) of the 5 turbine slots and the position across the covering slot (0 at the
    theta1 edge .. 1 at theta2); x / y in wheel_r units on WHEEL_SLOT axes, widen (rad) moves the theta1 edges out."""
    p1, p2, rc, rim = np.array(WHEEL_SLOT["p1"]), np.array(WHEEL_SLOT["p2"]), WHEEL_SLOT["rc"], WHEEL_SLOT["rim"]
    p1 = p1 - [0, 0, widen]
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    rcl = np.clip(r, rc, rim)
    cov = np.zeros_like(r)
    pos = np.zeros_like(r)
    for k in range(5):
        base = k * 2 * np.pi / 5
        t1, t2 = np.polyval(p1, rcl) + base, np.polyval(p2, rcl) + base
        hw = (t2 - t1) / 2
        d = np.angle(np.exp(1j * (th - (t1 + t2) / 2)))                 # signed angle to the slot centreline
        band = (np.abs(d) - hw) * r                                      # > 0 outside, wheel_r units
        tc = (np.polyval(p1, rc) + np.polyval(p2, rc)) / 2 + base        # rounded inner end
        cap = np.hypot(x - rc * np.cos(tc), y - rc * np.sin(tc)) - (np.polyval(p2, rc) - np.polyval(p1, rc)) / 2 * rc
        c = np.clip(0.5 - np.maximum(np.where(r >= rc, band, cap), r - rim) / aa, 0, 1)
        up = c > cov
        cov = np.where(up, c, cov)
        pos = np.where(up, np.clip((d + hw) / (2 * hw), 0, 1), pos)
    return cov, pos


def wheel_texture(r_out):
    """WHEEL_TEX^2 grey texture values (0..1), rows top-down, in the WHEEL_UV layout: the disc (rim face and sidewall,
    planar) and the tread strip (around x across). r_out = tire radius / wheel_r."""
    n, g = WHEEL_TEX * WHEEL_SS, {k: (np.array(v, float) / 0.143) ** (1 / 1.395) / 255 for k, v in WHEEL_RGB.items()}
    (cu, cv), rho, (v0, h) = WHEEL_UV["c"], WHEEL_UV["rho"], WHEEL_UV["tread"]
    U, V = np.meshgrid((np.arange(n) + 0.5) / n, 1 - (np.arange(n) + 0.5) / n)
    x, y = (U - cu) / rho, (cv - V) / rho
    r = np.hypot(x, y)
    aa = 1.5 / (n * rho)                                                # 1.5 px in wheel_r units
    inside = lambda e: np.clip((e - r) / aa + 0.5, 0, 1)                 # coverage of r < e
    mix = lambda a, b, t: a + (b - a) * t
    cov, pos = wheel_slots(x, y, aa)
    lit = np.clip(wheel_slots(x, y, aa, math.radians(5))[0] - cov, 0, 1)    # blade edge before the deep side
    slot = np.where(pos < 0.5, g["deep"], mix(g["wall"][0], g["wall"][1], smoothstep(0.5, 0.9, pos)))
    slot = mix(slot, g["shadow"], smoothstep(0.95, 1.0, pos))
    img = mix(mix(g["face"][0], g["face"][1], np.clip((r - 0.12) / 0.5, 0, 1)), slot, cov)
    img = mix(img, g["blade"], 0.85 * lit)
    rim = WHEEL_SLOT["rim"]
    img = mix(img, g["lip"], 1 - inside(rim - 0.022))
    img = mix(img, g["cap_ring"], inside(0.088))
    img = mix(img, g["cap"], inside(0.075))
    t = np.clip((r - rim) / (r_out - rim), 0, 1)
    side = mix(g["tire"][0], g["tire"][1], np.sin(np.pi * t) ** 2)     # faint sheen mid-sidewall (round: it spins)
    side = mix(side, g["gap"], inside(rim + 0.02))                     # dark joint between the cover and the bead
    img = mix(side, img, inside(rim))
    b = (V - v0) / h                                                    # tread: 0..1 across, U around
    tr = g["tread"] * (0.8 + 0.2 * smoothstep(0.0, 0.08, np.minimum(b, 1 - b)))   # rounded shoulders
    img = np.where((b > -0.02) & (b < 1.02), tr, img)
    img = np.where((r > r_out + 0.02) & ((b < -0.02) | (b > 1.02)), g["tire"][0], img)
    return img.reshape(WHEEL_TEX, WHEEL_SS, WHEEL_TEX, WHEEL_SS).mean((1, 3))


def wheel_profile(R, rr, hw):
    """Outer half (x >= 0) of the wheel's cross-section as (x, radius) strips from the tread centre to the hub: the
    tire (tread, shoulder, bulging sidewall, bead, rim flange), the step from the flange down to the aero cover, and
    the dished cover, recessed ~2 cm behind the sidewall bulge so a sliver of sidewall shows on the far side. Normals
    are smooth along a strip and split between strips. Grid units: R tire radius, rr rim radius, hw half tire width."""
    tire = [(0.0, R), (0.075, R - 0.0045)]
    for a in (45, 90):                                   # shoulder, radius 0.03
        t = math.radians(a)
        tire.append((0.075 + 0.030 * math.sin(t), R - 0.0345 + 0.030 * math.cos(t)))
    tire += [(hw + 0.0020, R - 0.052), (hw + 0.0022, R - 0.070), (hw - 0.0075, rr + 0.006), (hw - 0.0100, rr + 0.002)]
    step = [tire[-1], (hw - 0.0150, rr - 0.004)]
    cover = [step[-1], (hw - 0.0185, 0.55 * rr), (hw - 0.0200, 0.16 * rr), (hw - 0.0190, 0.0)]
    return tire, step, cover


def stage_wheel(r, width):
    """Procedural wheel, a closed surface of revolution (axle along X, vanilla Vehicles_Wheel convention): tire radius r
    and width in grid, 19" Photon aero cover; MOD wheel FBX (two equal UV layers) + 64^2 texture. -> triangle count.
    Fresh scene: the caller saves its own .blend first."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rr = WHEEL_SLOT["rim"] * r                           # rim: where the texture's cover ends
    strips = wheel_profile(r, rr, width / 2)
    n = WHEEL_SEG
    (cu, cv), rho, (v0, h) = WHEEL_UV["c"], WHEEL_UV["rho"], WHEEL_UV["tread"]
    xw = strips[0][3][0]                                 # the tread strip spans the tread and both shoulders
    ang = [2 * math.pi * j / n - math.pi for j in range(n + 1)]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UV0")
    rings, loop_n, loop_v = {}, [], []

    def ring(x, rad):
        key = (round(x, 6), round(rad, 6))
        if key not in rings:
            rings[key] = [bm.verts.new((x, rad * math.cos(a), rad * math.sin(a))) for a in ang[:n]] if rad > 1e-9 \
                else [bm.verts.new((x, 0.0, 0.0))] * n
        return rings[key]

    for side in (1, -1):
        for si, pts in enumerate(strips):
            p = np.array(pts, float)
            t = np.gradient(p, axis=0)
            nrm = np.stack([-t[:, 1], t[:, 0]], 1)       # outward (x, radius) normal of the profile walked hub-wards
            nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
            for i in range(len(pts) - 1):
                ra, rb = ring(side * p[i, 0], p[i, 1]), ring(side * p[i + 1, 0], p[i + 1, 1])
                tread = si == 0 and i < 3
                for j in range(n):
                    corners = [(ra, i, j), (ra, i, j + 1), (rb, i + 1, j + 1), (rb, i + 1, j)]
                    if side < 0:
                        corners.reverse()                # mirrored half: keep the winding outward
                    corners = [c for k, c in enumerate(corners) if c[0][c[2] % n] not in
                               [d[0][d[2] % n] for d in corners[:k]]]          # the hub ring is one vertex
                    f = bm.faces.new([c[0][c[2] % n] for c in corners])
                    for lp, (rg, pi, col) in zip(f.loops, corners):
                        x, y, z = lp.vert.co
                        lp[uv].uv = (col / n, v0 + (x / xw * 0.5 + 0.5) * h) if tread else \
                            (cu - y / r * rho, cv + z / r * rho)
                        nx, nr = nrm[pi]
                        loop_n.append((side * nx, nr * math.cos(ang[col]), nr * math.sin(ang[col])))
                        loop_v.append(lp.vert)
    me = bpy.data.meshes.new(NAME + "_Wheel")
    bm.verts.index_update()
    loop_v = [v.index for v in loop_v]
    bm.to_mesh(me)
    bm.free()
    low = bpy.data.objects.new(NAME + "_Wheel", me)
    bpy.context.scene.collection.objects.link(low)
    lv = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", lv)
    assert lv.tolist() == loop_v, "bmesh -> mesh reordered the loops"
    me.shade_smooth()
    me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set(
        "vector", np.array(loop_n, np.float32).ravel())
    me.update()
    # vehiclewheel_static.vert reads uv at location 3 (location 2 is the tangent of the vanilla wheels' .txt meshes), but
    # an FBX static mesh is pos, normal, UV0, UV1, bound by element index (ImportedStaticMesh.java:29-35,
    # VertexBufferObject.java:324-345). With one UV map the shader read attribute 3 left over from an earlier draw:
    # garbage UVs. UV1 = UV0 puts the wheel's own UVs there
    me.uv_layers.new(name="UV1")
    grey = wheel_texture(strips[0][3][1] / r)[::-1]      # planar disc ends at the shoulder; rows run bottom-up
    save_png(np.dstack([grey, grey, grey, np.ones_like(grey)]), os.path.join(TEX_DIR, NAME + "_wheel.png"), "wheel")
    mat = bpy.data.materials.new(NAME + "_Wheel")
    me.materials.append(mat)
    export_fbx(low, os.path.join(VEH_DIR, NAME + "_Wheel.fbx"))
    print("WHEEL tris", tris(low), "radius", r, "rim", round(rr, 4), "width", width)
    return tris(low)


# zones that take UV1 only from the same ModernCar zones (the maps draw cracks and broken-lamp holes there); everything
# else takes the body panels. ModernCar has one UV1 triangle per lamp (its tail lamps are the Stop zones) and our head
# bar is 1.5 grid wide: our lamps (along, z) tile round that triangle at DAMAGE_PX (DAMAGE_LAMPS; by nearest surface
# the corner lamps landed off it on blank texels). ModernCar's boot is a long deck with a
# short back while our tailgate is mostly upright: by nearest surface it took the dent blob on the boot's back
# (Veh_Damage1 58% vs ModernCar 18%), so its bounding box is first fitted onto ModernCar's (DAMAGE_BOX)
DAMAGE_GROUPS = (("WinT",), ("WinH",), ("WinLH",), ("WinLT",), ("WinRH",), ("WinRT",),
                 ("LightLH",), ("LightRH",), ("LightLT", "StopL"), ("LightRT", "StopR"), ("Boot",))
DAMAGE_LAMPS, DAMAGE_BOX = (7, 8, 9, 10), (11,)          # group numbers (index in DAMAGE_GROUPS + 1)
DAMAGE_PX = 80                                           # lamp UV1 density, px of 512 per grid (vanilla panels 75-100)
GROUP_OF = {z: i + 1 for i, zs in enumerate(DAMAGE_GROUPS) for z in zs}
ZCODE = np.array([""] * 125, object)            # mask colour (channels in quarters) -> zone name
for _k, _c in Z.items():
    ZCODE[int(np.rint(np.array(_c) * 4) @ [25, 5, 1])] = _k


def zone_codes(rgba):
    """Zone code (index into ZCODE) per mask texel, -1 off the 27 colours (antialiased edges) or where alpha < 0.5."""
    q = rgba[..., :3] * 4
    c = np.rint(q).astype(np.int64) @ [25, 5, 1]
    ok = (np.abs(q - np.rint(q)).max(-1) < 0.08) & (rgba[..., 3] > 0.5) & (ZCODE[c] != "")
    return np.where(ok, c, -1)


def fan_tris(me):
    """Loop-index triples of every polygon's fan triangulation, and each triangle's polygon."""
    ls, lt = (np.empty(len(me.polygons), np.int64) for _ in range(2))
    me.polygons.foreach_get("loop_start", ls)
    me.polygons.foreach_get("loop_total", lt)
    t, p = [], []
    for k in range(1, lt.max() - 1):
        s = np.flatnonzero(lt > k + 1)
        t.append(np.stack([ls[s], ls[s] + k, ls[s] + k + 1], 1))
        p.append(s)
    return np.concatenate(t), np.concatenate(p)


def loop_data(me, uv_names):
    lv = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", lv)
    uvs = []
    for nm in uv_names:
        a = np.empty(len(me.loops) * 2)
        me.uv_layers[nm].data.foreach_get("uv", a)
        uvs.append(a.reshape(-1, 2))
    return lv, uvs


def tri_dist(p, a, b, c):
    """Squared distance from p to triangle abc and the barycentric weights (..., 3) of p projected on its plane, not
    clamped to the triangle (broadcasts)."""
    ab, ac, ap = b - a, c - a, p - a
    d00, d01, d11 = (ab * ab).sum(-1), (ab * ac).sum(-1), (ac * ac).sum(-1)
    d20, d21 = (ap * ab).sum(-1), (ap * ac).sum(-1)
    den = np.maximum(d00 * d11 - d01 * d01, 1e-12)
    v, w = (d11 * d20 - d01 * d21) / den, (d00 * d21 - d01 * d20) / den
    plane = np.stack([1 - v - w, v, w], -1)
    d = np.where((v >= 0) & (w >= 0) & (v + w <= 1), ((ap - v[..., None] * ab - w[..., None] * ac) ** 2).sum(-1), np.inf)
    vs = (a, b, c)
    for i, j in ((0, 1), (0, 2), (1, 2)):                 # outside: nearest point of an edge
        e = vs[j] - vs[i]
        t = np.clip(((p - vs[i]) * e).sum(-1) / np.maximum((e * e).sum(-1), 1e-12), 0, 1)
        d = np.minimum(d, ((p - vs[i] - t[..., None] * e) ** 2).sum(-1))
    return d, plane


def nearest_tri(p, tri, chunk=256, normals=None, tn=None):
    """Index of the triangle (M x 3 x 3) nearest to each point (N x 3) and the point's barycentric weights on its plane
    (extrapolated past its edges: clamped to the edge, a third of the faces collapsed to a line where our surface
    reaches past ModernCar's, e.g. our door bottoms 14 cm below its side strip; capping the extrapolation at 15 cm
    collapsed more). With normals: only triangles within 73 deg (|cos| > 0.3) of the point's normal, all of them where
    none is."""
    idx, bary = np.empty(len(p), np.int64), np.empty((len(p), 3))
    for s in range(0, len(p), chunk):
        d, bc = tri_dist(p[s:s + chunk, None], tri[None, :, 0], tri[None, :, 1], tri[None, :, 2])
        if normals is not None:
            ok = np.abs(normals[s:s + chunk] @ tn.T) > 0.3
            d = np.where(ok | ~ok.any(1, keepdims=True), d, np.inf)
        k = d.argmin(1)
        idx[s:s + chunk], bary[s:s + chunk] = k, bc[np.arange(len(k)), k]
    return idx, bary


def damage_uv1(body, fzone):
    """UV1 of the body (the shared Veh_Damage1/2, Veh_Rust and Veh_Blood_* 512 maps) taken over from vanilla ModernCar:
    its skin is stretched onto ours (length and height by bbox, width by the half width below the belt) and every face
    takes ModernCar's UV1 nearby: DAMAGE_GROUPS zones only from the same ModernCar zones, the rest only from its body
    panels. Each face picks one ModernCar UV1 island (nearest triangle within 73 deg of its normal) and each corner takes
    the UV1 of that island's nearest triangle at its projection (nearest_tri), so the pattern runs on across a panel and
    never stretches over an island seam. Both sides share ModernCar's side strip, as in vanilla. UV0 x 0.56 (before
    2026-10-24) put the car in the maps' empty lower-left corner: windscreen and left windows never cracked.
    fzone: mask zone per polygon (face_zones).
    Must run before the doors are cut out of the body: the door meshes keep the body's UV0 / UV1."""
    ref = vanilla.load(DAMAGE_REF)
    rm = ref.data
    rm.uv_layers.active = rm.uv_layers["UV1"]
    pisl = np.empty(len(rm.polygons), np.int64)
    for k, faces in enumerate(mesh_utils.mesh_linked_uv_islands(rm)):
        pisl[faces] = k
    rt, rp = fan_tris(rm)
    lv, (u0, u1) = loop_data(rm, ("UV0", "UV1"))
    rco, ru0, ru1, risl = mesh_co(ref)[lv][rt], u0[rt], u1[rt], pisl[rp]
    bpy.data.objects.remove(ref)
    # zone of each ModernCar triangle: majority of 64 samples on its mask. Skin = painted at most of them (its interior,
    # underbody and wheel wells are not, and the nearest surface must be the outside) and a real UV1 triangle: 176 of
    # its 406 skin triangles (4.2 of 18.4 grid^2: edges, jambs, part of the hood and boot) have UV1 collapsed to a point
    # (under 20 px of the 512 maps per grid, vs 75-100 on the panels); our faces nearest to them got one texel
    r = np.random.default_rng(0).random((64, 2))
    r[r.sum(1) > 1] = 1 - r[r.sum(1) > 1]
    uv = np.einsum("sk,tkc->tsc", np.stack([1 - r.sum(1), r[:, 0], r[:, 1]], 1), ru0)
    msk = img_np(bpy.data.images.load(os.path.join(vanilla.PZ, "textures", "Vehicles", DAMAGE_REF_MASK)))
    h, w = msk.shape[:2]
    c = zone_codes(msk[np.clip((uv[..., 1] * h).astype(int), 0, h - 1), np.clip((uv[..., 0] * w).astype(int), 0, w - 1)])
    e, f = ru1[:, 1] - ru1[:, 0], ru1[:, 2] - ru1[:, 0]
    a3 = np.linalg.norm(np.cross(rco[:, 1] - rco[:, 0], rco[:, 2] - rco[:, 0]), axis=1)
    skin = ((c >= 0).mean(1) > 0.5) & (np.abs(e[:, 0] * f[:, 1] - e[:, 1] * f[:, 0]) * 512 ** 2 > 20 ** 2 * a3)
    cnt = np.stack([(c == k).sum(1) for k in range(125)], 1)
    rzone = ZCODE[cnt.argmax(1)]
    grp = lambda zn: np.array([GROUP_OF.get(z, 0) for z in zn])  # noqa: E731
    rcls = np.where(skin, grp(rzone), -1)
    # stretch ModernCar onto the body
    co = mesh_co(body)

    def frame(v):
        lo, hi = v.min(0), v.max(0)
        return lo, hi, np.abs(v[v[:, 2] < lo[2] + 0.55 * (hi[2] - lo[2]), 0]).max()   # below the belt: no mirrors
    (blo, bhi, bw), (rlo, rhi, rw) = frame(co), frame(rco[skin].reshape(-1, 3))
    s = np.array([bw / rw, *((bhi - blo) / (rhi - rlo))[1:]])
    off = np.array([0, *(blo - rlo * s)[1:]])
    rco = rco * s + off
    rn = np.cross(rco[:, 1] - rco[:, 0], rco[:, 2] - rco[:, 0])
    rn /= np.maximum(np.linalg.norm(rn, axis=1, keepdims=True), 1e-12)
    me = body.data
    fn = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("normal", fn)
    fn, fc = fn.reshape(-1, 3), face_centres(body)
    fcls = grp(fzone)
    blv, _ = loop_data(me, ())
    lt = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("loop_total", lt)
    lf = np.repeat(np.arange(len(lt)), lt)
    box = {}                                        # group -> (our min, size, ModernCar min, size)
    for g in DAMAGE_BOX:
        p, q = co[blv[fcls[lf] == g]], rco[rcls == g].reshape(-1, 3)
        if len(p) and len(q):
            box[g] = (p.min(0), np.maximum(np.ptp(p, 0), 1e-6), q.min(0), np.ptp(q, 0))
    put = lambda p, g: (p - box[g][0]) / box[g][1] * box[g][3] + box[g][2] if g in box else p  # noqa: E731
    fgrp, fisl = fcls.copy(), np.empty(len(fc), np.int64)
    for g in range(len(DAMAGE_GROUPS) + 1):
        F = np.flatnonzero(fcls == g)
        T = np.flatnonzero(rcls == g)
        if not len(T):
            T, fgrp[F] = np.flatnonzero(rcls == 0), 0
        k, _ = nearest_tri(put(fc[F], g), rco[T], normals=fn[F], tn=rn[T])
        fisl[F] = risl[T[k]]
    # corners: the face's island (its triangles of the same group), UV1 of the nearest one's plane there
    out = np.empty((len(blv), 2))
    key = fisl[lf] * 16 + fgrp[lf]
    for kk in np.unique(key):
        L = np.flatnonzero(key == kk)
        T = np.flatnonzero((risl == kk // 16) & (rcls == kk % 16))
        vv, inv = np.unique(blv[L], return_inverse=True)
        k, bc = nearest_tri(put(co[vv], kk % 16), rco[T])
        out[L] = np.einsum("nk,nkc->nc", bc, ru1[T[k]])[inv]
    for g in DAMAGE_LAMPS:      # lamps: tiled at panel density round ModernCar's lamp triangle, our corner lamp at its
        L = np.flatnonzero(fgrp[lf] == g)      # centre (else the bar's middle): the box round it is half blank
        if not len(L):
            continue
        p = co[blv[L]]
        a = [int(np.argmax(np.ptp(p[:, :2], 0))), 2]         # along the lamp (x or y), across it (z)
        q = ru1[rcls == g].reshape(-1, 2)
        s = np.argsort(-np.ptp(q, 0))                       # the UV box's long, short side
        size = np.ptp(q, 0)[s]
        fl = lf[L]
        stop = np.isin(fzone[fl], ("StopL", "StopR"))
        o = p[stop].mean(0) if stop.any() else (p.min(0) + p.max(0)) / 2
        t = (p[:, a] - o[a]) * DAMAGE_PX / 512
        cen = np.stack([np.bincount(fl, t[:, i]) for i in range(2)], 1)[fl] / np.bincount(fl)[fl, None]
        out[L[:, None], s] = q.mean(0)[s] + t - np.round(cen / size) * size    # whole faces per tile
    me.uv_layers["UV1"].data.foreach_set("uv", out.ravel())
    print("UV1 from", DAMAGE_REF, "islands", len(np.unique(fisl)), "faces per own-zone group",
          {"/".join(zs): int((fgrp == i + 1).sum()) for i, zs in enumerate(DAMAGE_GROUPS)})


# Vanilla layout (SportsCarWithDoors.fbx, ModernCarWithDoors_ez.fbx): one FBX, armature "VehicleSkeleton" (the root
# ImportedSkeleton.java:57-60 looks up), one bone "<Part>_bone" per door, one mesh per door weighted 1.0 to its bone
# ("<file>|<mesh>", ProcessedAiScene.java:97-124), one clip per door; the take name is cut at its first '|'
# (ImportedSkeleton.java:336-340), Blender writes "VehicleSkeleton|<action>". Skinned meshes carry pos, normal,
# weights, indices, UV0, UV1 (ImportedSkinnedMesh.java:74-82) = vehicle_multiuv_noreflect.vert's locations, read by
# the MOD's media/shaders/MinidoracatTesla_vehicle.vert (static = false picks <name>.vert, ShaderProgram.java:278-286).
# A part model draws with the parent car's skin, mask, damage and uninstall uniforms (Model.java:534-585), so the doors
# keep the body's UV0 / UV1 and textures.
# part: side (-1 = left, x < 0; 0 = tailgate), hinge axis, open angle (deg; sign swings the door out, the gate up),
# clip seconds. Hinge points come from the cut (front edge on the outer skin; the gate's top edge; the frunk lid's
# rear edge at the cowl, front rising like the real lid). The clips run open -> closed ("<Part>_closing", vanilla's
# naming; Open plays it reversed). updateAnimationPlayer advances the clip 0.8 x real time x rate
# (BaseVehicle.java:3901-3904): doors ~1 s, the gate ~4.5 s like an electric tailgate, the lid ~1.25 s
DOORS = {
    "DoorFrontLeft": (-1, (0, 0, 1), -65, 0.8), "DoorFrontRight": (1, (0, 0, 1), 65, 0.8),
    "DoorRearLeft": (-1, (0, 0, 1), -65, 0.8), "DoorRearRight": (1, (0, 0, 1), 65, 0.8),
    "TrunkDoor": (0, (1, 0, 0), -75, 3.6), "EngineDoor": (0, (1, 0, 0), 55, 1.0),
}
DOORS_FBX = NAME + "_Doors"
DOOR_T, JAMB_T = 0.06, 0.08       # grid: door slab thickness (inner panel offset), body jamb depth
GATE_IN = (0.0, 0.894, -0.447)    # tailgate inward direction (forward and down: the glass leans, the panel stands)
CLIP_FPS = 30


def soup(ob, shift):
    """Triangle soup of a mesh: positions (+shift), tris, per-corner UV0 / UV1 / normal (7 floats), liner flag."""
    me = ob.data
    nl = len(me.loops)
    lv = np.empty(nl, np.int64)
    me.loops.foreach_get("vertex_index", lv)
    attr = []
    for nm in ("UV0", "UV1"):
        a = np.empty(nl * 2)
        me.uv_layers[nm].data.foreach_get("uv", a)
        attr.append(a.reshape(-1, 2))
    cn = np.empty(nl * 3, np.float32)
    me.corner_normals.foreach_get("vector", cn)
    attr = np.concatenate(attr + [cn.reshape(-1, 3)], 1)
    ls, lt = (np.empty(len(me.polygons), np.int64) for _ in range(2))
    me.polygons.foreach_get("loop_start", ls)
    me.polygons.foreach_get("loop_total", lt)
    lin = np.array([d.value for d in me.attributes["liner"].data], bool)
    tl, tf = [], []
    for p, (s, n) in enumerate(zip(ls, lt)):            # fan (liners are quads)
        for i in range(1, n - 1):
            tl.append((s, s + i, s + i + 1))
            tf.append(p)
    tl = np.array(tl)
    return mesh_co(ob) + shift, lv[tl], attr[tl], lin[tf]


def slab(V, T, A, sel, off, liner_attr, belt, outer_extra=None):
    """Door piece: its outer faces, an inner panel DOOR_T in along off (liner_attr colour, normals in) and edge strips
    that close the slab (each takes the colour just inside its outer edge; above `belt` z liner_attr). outer_extra:
    faces with no inner panel (the mirror). Returns points, tris, attributes and the boundary edges (directed as in
    the piece)."""
    tri, att = T[sel], A[sel]
    ed = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]])
    ea = np.concatenate([att[:, [0, 1]], att[:, [1, 2]], att[:, [2, 0]]])
    und = np.sort(ed, 1)
    _, inv, cnt = np.unique(und, axis=0, return_inverse=True, return_counts=True)
    bnd = cnt[inv.ravel()] == 1
    base = len(V)
    inner_v = V + off                                    # vertex i's inner twin is base + i
    it = tri[:, [0, 2, 1]] + base
    ia = np.repeat(liner_attr[None, None], len(tri) * 3, 0).reshape(len(tri), 3, -1).copy()
    ia[..., 4:] = -att[:, [0, 2, 1], 4:]
    a, b = ed[bnd, 0], ed[bnd, 1]
    st = np.concatenate([np.stack([b, a, a + base], 1), np.stack([b, a + base, b + base], 1)])
    fa = frame_black(pull_in(ea[bnd], att.mean(1)[np.tile(np.arange(len(tri)), 3)[bnd]]), V[a], V[b], liner_attr, belt)
    sa = np.concatenate([np.stack([fa[:, 1], fa[:, 0], fa[:, 0]], 1), np.stack([fa[:, 1], fa[:, 0], fa[:, 1]], 1)])
    P = np.concatenate([V, inner_v])
    nrm = np.cross(P[st[:, 1]] - P[st[:, 0]], P[st[:, 2]] - P[st[:, 0]])
    sa[..., 4:] = (nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12))[:, None]
    parts_t, parts_a = [tri, it, st], [att, ia, sa]
    if outer_extra is not None:
        parts_t.insert(0, T[outer_extra])
        parts_a.insert(0, A[outer_extra])
    return P, np.concatenate(parts_t), np.concatenate(parts_a), np.stack([a, b], 1)


def pull_in(corner_attr, centre_attr, f=0.3):
    """Edge-strip UVs a little inside the face they continue: the mask is sampled bilinearly, and an edge UV on a
    zone border would put a body jamb in the door's zone (painted 0.2 grey once the door is removed)."""
    out = corner_attr.copy()
    out[..., :4] += (centre_attr[:, None, :4] - corner_attr[..., :4]) * f
    return out


def frame_black(edge_attr, pa, pb, liner_attr, belt):
    """Strips along an edge above the belt are black (window frames and their seals): there the outline runs through
    frit and roof-rail triangles, and their colours made a red-and-black comb along the door top (tesla-doors-1024a)."""
    out = edge_attr.copy()
    up = (pa[:, 2] > belt + 0.02) & (pb[:, 2] > belt + 0.02)
    out[up, :, :4] = liner_attr[:4]
    return out


def soup_object(name, V, T, A, mat):
    """Mesh object from a triangle soup (unused vertices dropped), UV0 / UV1 and free corner normals."""
    used, T = np.unique(T.ravel(), return_inverse=True)
    T = T.reshape(-1, 3)
    me = bpy.data.meshes.new(name)
    me.from_pydata(V[used].tolist(), [], T.tolist())
    for k, nm in ((0, "UV0"), (2, "UV1")):
        me.uv_layers.new(name=nm).data.foreach_set("uv", np.ascontiguousarray(A[..., k:k + 2]).ravel())
    me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set(
        "vector", np.ascontiguousarray(A[..., 4:7], np.float32).ravel())
    me.materials.append(mat)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def export_doors(obs):
    """Doors FBX: the armature, its skinned meshes and every action as a take (convert.py pieces)."""
    select_only(*obs)
    bpy.ops.export_scene.fbx(filepath=os.path.join(VEH_DIR, DOORS_FBX + ".fbx"), use_selection=True,
                             object_types={"ARMATURE", "MESH"}, apply_scale_options="FBX_SCALE_UNITS",
                             bake_space_transform=False, axis_forward="Y", axis_up="Z", mesh_smooth_type="OFF",
                             add_leaf_bones=False, primary_bone_axis="Y", secondary_bone_axis="X",
                             armature_nodetype="NULL", bake_anim=True, bake_anim_use_all_bones=True,
                             bake_anim_use_nla_strips=False, bake_anim_use_all_actions=True,
                             bake_anim_force_startend_keying=True, bake_anim_step=1.0, bake_anim_simplify_factor=0.0,
                             path_mode="STRIP")


# cabin palette cells, in MinidoracatTesla_vehicle.frag CABIN[] order (the colours live there): a cabin face carries
# UV1 = (CABIN_UV1_U - cell, 0) (the loader flips v, ImportedStaticMesh.java:59)
CABIN_CELLS = ("floor", "liner", "seat", "base", "dash", "trim", "console", "wheel", "screen_back", "screen")
CABIN_UV1_U = -2.5
GLASS_UV1_SHIFT = 2.0     # glass faces: UV1 u + this (the shader takes it back off for the damage maps)


def face_classes(ob):
    """Per face: 0 paint, 1 cabin, 2 glass, from UV1 u at its first corner (MinidoracatTesla_vehicle.frag)."""
    me = ob.data
    u = np.empty(len(me.loops) * 2)
    me.uv_layers["UV1"].data.foreach_get("uv", u)
    ls = np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get("loop_start", ls)
    fu = u[0::2][ls]
    return np.where(fu < CABIN_UV1_U / 2, 1, np.where(fu > GLASS_UV1_SHIFT * 0.75, 2, 0))


def order_faces(ob):
    """Faces sorted paint, cabin, glass (stable), one material: a mesh draws its triangles in index order (FBX polygon
    order; the loader's post-process steps keep it, FileTask_LoadMesh.java:54-62), so the glass blends over the cabin
    and over the characters seated in it, drawn before the car."""
    cls = face_classes(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    rank = {f: int(c) * len(cls) + i for i, (f, c) in enumerate(zip(bm.faces, cls))}
    bm.faces.sort(key=lambda f: rank[f])
    bm.faces.index_update()
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.polygons.foreach_set("material_index", np.zeros(len(ob.data.polygons), np.int64))
    while len(ob.data.materials) > 1:
        ob.data.materials.pop()
    if (np.diff(face_classes(ob)) < 0).any():
        raise SystemExit(f"{ob.name}: faces still out of paint / cabin / glass order")


def import_fbx(path):
    """FBX -> mesh in Blender axes (identity transform), the inverse of export_fbx; fresh scene."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path, axis_forward="-Z", axis_up="Y", bake_space_transform=True)
    return [o for o in bpy.data.objects if o.type == "MESH"][0]


def inside(bvh, p):
    """Point enclosed by the car (body, doors, glass): rays to both sides and up all hit it. The parts together are not
    one closed surface (door gaps, jambs), so a parity count is meaningless."""
    return all(bvh.ray_cast(Vector(p), Vector(d))[0] is not None for d in ((1, 0, 0), (-1, 0, 0), (0, 0, 1)))


S = 1.82              # vehicle scale (R5 3), model script scale = 1/S
OY = 0.1978           # model offset == centerOfMassOffset (unscaled), ModernCar convention
WHEEL_LIFT = 0.11     # rendered wheel sits this much (grid) above its script offset at rest: vanilla arch centres
#                       minus wheel offsets, ModernCar +0.10/+0.16, SUV +0.12/+0.10 (arch circle fit); calibration knob
WHEEL_INSET = 0.03    # tire outer face this far inside the body's own tire (flush tires looked proud of the arch)


def f4(*v):
    return " ".join(f"{x:.4f}" for x in v)


def geometry(body, zmid, wl, r, tire_w, belt_z, doors_y, port_yz):
    """Vehicle script geometry block, spliced into the vehicle script (copy in TMP/geometry_block.txt). Mesh (x, y, z
    rel. mesh centre) -> script (-x, z, y) / S. wl: (side, centre y, centre z pre-centre, outer |x|) per wheel; r,
    tire_w: tire radius and width (grid); belt_z: window bottom (pre-centre z); doors_y: (front door front, B pillar,
    rear door rear) mesh y; port_yz: charge port (mesh y, pre-centre z), x from a ray onto the left side."""
    from mathutils.bvhtree import BVHTree
    co = mesh_co(body)
    me = body.data
    liner = np.array([d.value for d in me.attributes["liner"].data], bool)
    bc = co[sorted({i for k, p in enumerate(me.polygons) if not liner[k] for i in p.vertices})]
    w_body = 2 * np.abs(bc[bc[:, 2] < 0.55 * H - zmid][:, 0]).max()
    hgt, ln = bc[:, 2].max() - bc[:, 2].min(), np.ptp(bc[:, 1])
    ext = (w_body / S, hgt / S, ln / S)
    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    hit = bvh.ray_cast(Vector((-3, port_yz[0], port_yz[1] - zmid)), Vector((1, 0, 0)))[0]
    port = (-hit.x / S, (port_yz[1] - zmid) / S, port_yz[0] / S)
    belt = belt_z - zmid
    front_y, bpil_y, rear_y = doors_y
    lo = (bc[:, 2].min() + belt) / 2
    cab = ((belt + bc[:, 2].max()) / 2, 1.30, 0.45, -1.60)
    aw, ah = 0.4725, 0.4725
    sx = ext[0] / 2 + aw / 2
    out = [
        "        model", "        {", f"            file = {NAME},", f"            scale = {S},", f"            offset = {f4(0, OY, 0)},", "        }",
        *[ln for p, _ in PAINTS for ln in ("        skin", "        {", f"            texture = Vehicles/{NAME}_{p},", "        }")],
        f"        textureMask = Vehicles/{NAME}_mask,", f"        textureLights = Vehicles/{NAME}_lights,",
        "        textureDamage1Overlay = Vehicles/Veh_Blood_Mask,", "        textureDamage2Overlay = Vehicles/Veh_Blood_Hvy,",
        "        textureDamage1Shell = Vehicles/Veh_Damage1,", "        textureDamage2Shell = Vehicles/Veh_Damage2,",
        "        textureRust = Vehicles/Veh_Rust,",
        "        template = PassengerSeat4,",
        f"        extents = {f4(*ext)},", f"        physicsChassisShape = {f4(*ext)},",
        f"        centerOfMassOffset = {f4(0, OY, 0)},",
        f"        shadowExtents = {f4(ext[0], ext[2])},", "        shadowOffset = 0.0 0.0,",
        "        useChassisPhysicsCollision = false,",
        "        physics box", "        {", f"            offset = {f4(0, lo / S + OY, 0)},",
        f"            extents = {f4((w_body - 0.03) / S, (belt - bc[:, 2].min()) / S, (ln - 0.06) / S)},", "        }",
        "        physics box", "        {", f"            offset = {f4(0, cab[0] / S + OY, (cab[2] + cab[3]) / 2 / S)},",
        f"            extents = {f4(cab[1] / S, (bc[:, 2].max() - belt) / S, (cab[2] - cab[3]) / S)},", "        }",
    ]
    names = {(-1, 1): "FrontLeft", (1, 1): "FrontRight", (-1, -1): "RearLeft", (1, -1): "RearRight"}
    for sxn, yc, zc, xo in wl:
        nm = names[(sxn, 1 if yc > 0 else -1)]
        out += [f"        wheel {nm}", "        {", f"            front = {'true' if yc > 0 else 'false'},",
                f"            offset = {f4(-sxn * (xo - tire_w / 2 - WHEEL_INSET) / S, (zc - zmid - WHEEL_LIFT) / S, yc / S)},",
                f"            radius = {(r - 0.015) / S:.4f},", f"            width = {tire_w:.4f},", "        }"]
    out += ["        part Tire*", "        {", "            model InflatedTirePlusWheel", "            {",
            f"                file = {NAME}_Wheel,", "            }", "        }"]
    seat_y, ground = (0.56 - zmid) / S, -zmid / S
    fz, rz = (front_y + bpil_y) / 2 - 0.12, (bpil_y + rear_y) / 2 - 0.08
    seats = (("FrontLeft", 1, fz, (front_y, bpil_y)), ("FrontRight", -1, fz, (front_y, bpil_y)),
             ("RearLeft", 1, rz, (bpil_y, rear_y)), ("RearRight", -1, rz, (bpil_y, rear_y)))
    for nm, side, z, door in seats:        # showPassenger: the 3-D cabin shows whoever sits there through the glass
        out += [f"        passenger {nm}", "        {", "            showPassenger = true,", "            position inside", "            {",
                f"                offset = {f4(side * 0.33 / S, seat_y, z / S)},", "                rotate = 0.0 0.0 0.0,", "            }",
                "            position outside", "            {",
                f"                offset = {f4(side * (w_body / 2 + 0.30) / S, ground, z / S)},", "                rotate = 0.0 0.0 0.0,",
                f"                area = Seat{nm},", "            }", "        }"]
    areas = [("Engine", 0, ext[2] / 2 + ah / 2, ext[0], ah), ("TruckBed", 0, -(ext[2] / 2 + ah / 2), ext[0], ah),
             ("GasTank", sx, port[2], aw, ah)]
    for nm, side, z, door in seats:
        areas.append(("Seat" + nm, side * sx, ((door[0] + door[1]) / 2) / S, aw, (door[0] - door[1]) / S))
    for sxn, yc, zc, xo in wl:
        areas.append(("Tire" + names[(sxn, 1 if yc > 0 else -1)], -sxn * sx, yc / S, aw, ah))
    for nm, ax, az, w, h in areas:
        out += [f"        area {nm}", "        {", f"            xywh = {f4(ax, az, w, h)},", "        }"]
    tow = (bc[:, 2].min() + 0.08) / S
    out += ["        attachment trailer", "        {", f"            offset = {f4(0, tow, -(ln / 2 + 0.03) / S)},",
            "            rotate = 0.0 0.0 0.0,", "            zoffset = -1.0,", "        }",
            "        attachment trailerfront", "        {", f"            offset = {f4(0, tow, (ln / 2 + 0.03) / S)},",
            "            rotate = 0.0 0.0 0.0,", "            zoffset = 1.0,", "        }",
            "        /* charge port: side end of the left tail light (real Model Y) */",
            "        attachment chargeport", "        {", f"            offset = {f4(*port)},", "            rotate = 0.0 0.0 0.0,", "        }"]
    # animated doors (convert.py pieces): the clip runs open -> closed, so Open plays it reversed and Opened holds its start
    # (not animated; vanilla vehicle_car_sports_ez.txt layout); ISOpenVehicleDoor / ISCloseVehicleDoor play Open /
    # Close, a new model instance of an open door holds Opened (BaseVehicle.java:3926-3930). No Closed: a shut door
    # then has no track, and AnimationPlayer skips the skeleton when it has none (AnimationPlayer.java:512-529), where a
    # Closed pose track (animate = false, never finishes) made every loaded car compute 6 skeletons every frame
    # (models.md 9). The pose of a shut door is the mesh's own (bind pose = shut) or Close's last frame.
    # One model per door, its window in the door mesh: each door's AnimationPlayer advances once a frame (postupdate,
    # BaseVehicle.java:3777-3780), so every clip runs at rate 1 with or without its window
    for part in DOORS:
        clip = part + "_closing"
        out += [f"        part {part}", "        {", "            model Default", "            {",
                f"                file = {NAME}_{part},", "            }"]
        for anim, rev, live in (("Close", False, True), ("Open", True, True), ("Opened", False, False)):
            out += [f"            anim {anim}", "            {", f"                anim = {clip},"]
            out += ["                reverse = true,"] * rev
            out += ["                rate = 1.0,"] if live else ["                animate = false,"]
            out += ["            }"]
        out += ["        }"]
    block = "\n".join(out) + "\n"
    open(os.path.join(TMP, "geometry_block.txt"), "w", newline="\n").write(block)
    # splice into the vehicle script: everything after the geometry marker up to the vehicle's closing brace is ours
    path = os.path.join(MEDIA, "scripts", "vehicles", NAME + ".txt")
    text = open(path, encoding="utf-8").read()
    head = text.index("\n", text.index("---- geometry (TeslaModelY)")) + 1
    tail = text.rindex("    }\n}")
    open(path, "w", encoding="utf-8", newline="\n").write(text[:head] + block + text[tail:])
    return {"zmid_ground": zmid, "body_width": w_body, "body_height": hgt, "length": ln,
            "port_mesh": [hit.x, port_yz[0], port_yz[1]], "wheelbase": wl[0][1] - wl[2][1], "wheel_radius": r}


def official_ramp(code, n=32):
    """sRGB paint colour per V quantile (n bins) of the official design-studio SIDE render of `code` (stage official):
    body side below the belt (car bbox rows 36-74%, columns 4-96%), wheel arches and rocker cut out, nose left."""
    a = img_np(bpy.data.images.load(os.path.join(OFFICIAL, f"{code}_SIDE.png")))[::-1].astype(np.float64)  # rows top-down
    m = a[..., 3] > 0.9
    ys, xs = np.nonzero(m)
    x0, y0, w, h = xs.min(), ys.min(), np.ptp(xs), np.ptp(ys)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    u, t = (xx - x0) / w, (yy - y0) / h
    keep = m & (t > 0.36) & (t < 0.74) & (u > 0.04) & (u < 0.96)
    for cu in (0.165, 0.80):                                             # wheels + arches
        keep &= ((u - cu) * w) ** 2 + ((t - 0.80) * h) ** 2 > (0.135 * w) ** 2
    px = a[..., :3][keep]
    px = px[np.argsort(px.max(1), kind="stable")]
    e = np.linspace(0, len(px), n + 1).astype(int)
    return np.array([px[e[i]:e[i + 1]].mean(0) for i in range(n)])


def stage_official():
    """Download the design-studio renders (SIDE for official_ramp, FRONT34 / REAR34 for comparison sheets)."""
    import urllib.request
    os.makedirs(OFFICIAL, exist_ok=True)
    for _, code in PAINTS:
        # $PB00 Frost Blue only exists on the Performance trim: with $MTY79 the compositor answers 412
        opts = "$MTY70,$PB00,$WY21A,$IPB14" if code == "PB00" else f"$MTY79,${code},$WY19P,$IPB15"
        for view in ("SIDE", "FRONT34", "REAR34"):
            req = urllib.request.Request(COMPOSITOR.format(opts, view), headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=60) as r, open(os.path.join(OFFICIAL, f"{code}_{view}.png"), "wb") as f:
                f.write(r.read())
