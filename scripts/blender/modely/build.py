"""Model Y v2: Tripo H3.1 high-poly GLB -> PZ body FBX (UV0 + UV1), wheel FBX, 8 paint skins / mask / lights / wheel PNGs.

    blender -b --factory-startup --python scripts/blender/modely/build.py -- <stage> [args]

stages (each reads the previous one's .blend in temp/modely/):
  prep            tripo_hi.glb -> axes, scale, body / front-left-wheel sources        -> v2_prep.blend, prev/prep_*.png
  tiers N,N,...   decimated bodies (+ liners, high-poly normals, UV0, UV1 = UV0)     -> v2_tiers.blend, tiers/*.fbx
  wheel           procedural 255/45R19 tire + recessed Photon aero cover (surface of revolution, closed), procedural
                  64 texture (disc + tread strip), two UV layers                       -> MOD wheel FBX + PNG
  official        official design-studio renders of the 8 paints                       -> temp/modely/official/
  final N         bake N-tri body at 4096 (cached in bake_N.npz; delete it after a tiers rerun: new UV0), one 2048
                  skin per paint (colour from the official render; glass panes show Tripo's cabin through a tint, black
                  frit band, normals from a quadric per pane; head / rear light bars on smoothed centre lines; satin
                  black trims, rear diffuser and front lip by geometry, body-colour spoiler), 512 mask / lights,
                  UV1 on the shared damage maps from vanilla ModernCar, geometry block spliced into the vehicle script
                  (copy in temp/modely/geometry_block.txt), whole body -> v2_final.blend, then runs doors, verify.txt,
                  prev/*.png
  doors           v2_final.blend -> body FBX with the four doors and the tailgate cut out (+ jambs), doors FBX (one
                  skinned mesh per door on VehicleSkeleton, "<Part>_closing" clips)  -> MOD FBX, prev/doors_*.png

Axes (Blender): +Y front, +Z up, -X = car left (driver side), 1 unit = 1 grid; same as vanilla raw FBX coords
(scripts/blender/modely/vanilla.py). Vehicle script: x = -mesh x, y = mesh z, z = mesh y, unscaled = grid / 1.82.
Numbers and sources: .claude/skills/tesla-dev/references/models.md.
"""
import bpy, bmesh, colorsys, json, math, os, sys
import numpy as np
from bpy_extras import mesh_utils
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
import preview  # noqa: E402
import vanilla  # noqa: E402

TMP = os.path.join(REPO, "temp", "modely")
PREV = os.path.join(TMP, "prev")
MEDIA = os.path.join(REPO, "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media")
VEH_DIR = os.path.join(MEDIA, "models_X", "vehicles")
TEX_DIR = os.path.join(MEDIA, "textures", "Vehicles")
SRC = os.path.join(TMP, "tripo_hi.glb")
NAME = "MinidoracatTesla_ModelY"

K = 0.826                                   # grid per metre (R5 3), calibration knob
L, W, H = 4.790 * K, 1.920 * K, 1.624 * K   # official length, body width (no mirrors), height
DIM_TOL = 0.02                              # allowed error vs official x K (Main 2026-10-23); only that much squash
TIRE_W = 0.255 * K                          # 255/45R19
BAKE = 4096
LINER_SEG = 16
MIN_ISLAND = 1 / 150                        # UV0 projection islands under this share of the faces are merged
UNDER_Z = 0.40                              # grid: only the underbody gets the quarter-density "D" projection; higher
#                                             down-facing faces (tail-light recess, under the spoiler / bar / mirrors)
#                                             take their horizontal axis
# head bar centre line (|x|, y, z grid, ground z = 0): medians of the bar's bright bake texels per 5 cm of x (v > 0.75,
# y > 1.6, z 0.60-0.74; lamps() seeds), left and right averaged, 1-2-1 smoothed, 4 cm added past the end. UV0 unrolls a
# band of HEAD_BAND round it into one island (project_uv); lamps() still draws the bar from the bake's own seeds
HEAD_LINE = ((0.00, 1.950, 0.649), (0.05, 1.949, 0.649), (0.10, 1.948, 0.649), (0.15, 1.944, 0.648),
             (0.20, 1.940, 0.648), (0.25, 1.934, 0.648), (0.30, 1.928, 0.648), (0.35, 1.913, 0.649),
             (0.40, 1.882, 0.654), (0.45, 1.848, 0.659), (0.50, 1.811, 0.665), (0.55, 1.763, 0.673),
             (0.60, 1.715, 0.679), (0.65, 1.665, 0.688), (0.70, 1.611, 0.704), (0.74, 1.568, 0.717))
HEAD_BAND = 0.045                           # grid: bar 0.9 cm + ring 0.6 cm + 3 cm speckle repaint, with margin
# UV1 (shared Veh_Damage1/2, Veh_Rust, Veh_Blood_* 512 maps): taken over from this vanilla car (damage_uv1)
DAMAGE_REF, DAMAGE_REF_MASK = "Vehicles_ModernCar", "vehicle_carmodern_mask.png"
WHEEL_TEX, WHEEL_SS = 64, 8                 # wheel texture size; drawn WHEEL_SS times larger, then box-averaged
# wheel texture, all procedural (Tripo's wheel bake had smeared lug nuts and specks in the slots and sat 8.5 mm off the
# axis). Official 19" Photon aero wheel: matte charcoal face, 5 turbine
# slots with a lit blade edge (official/*_FRONT34.png). Slot edges theta(r) fitted on the Tripo bake: luminance 5-fold
# median about its own centre, re-centred, per-radius dark run, quadratic rms 0.3 / 0.4 deg. r in wheel_r units,
# theta in the old planar layout's image axes (x = -y / r, y = -z / r: x right, y down)
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
# Model Y body lines (grid, ground z=0, centre y=0), checked on prev/mask_*.png against the panel gaps of the bake
DOOR_FRONT_Y, B_PILLAR_Y, DOOR_REAR_Y, BELT_Z = 0.83, -0.14, -1.05, 0.92
# animated doors (stage doors). Pre-centre grid frame (ground z = 0). Door skins go down to DOOR_SILL_Z (the rocker
# under it stays body); above the belt a door takes its window and the frit round it up to DOOR_TOP_Z, forward to
# DOOR_A_LINE (front edge of the front window + frit, (z, y) points), back to the B-pillar trim (B_PILLAR_WIN: the trim
# stays body) and, on the rear door, to the quarter-glass divider (DIVIDER[0]). The tailgate is Boot + rear glass + the
# tail bar: |x| < GATE x below top_z, < top_x (rear glass 0.48 + frit) above; the corner lamps stay body. Mask Door /
# Boot zones match these cuts (classify), so no zone of a removable part is left on the body (a removed part paints
# its zones 0.2 grey, vehicle_multiuv.frag:175)
DOOR_SILL_Z, DOOR_TOP_Z = 0.20, 1.30
DOOR_A_LINE = ((0.95, 0.83), (1.00, 0.67), (1.04, 0.625), (1.08, 0.585), (1.12, 0.52), (1.16, 0.39), (1.20, 0.32),
               (1.24, 0.245), (1.28, 0.17), (1.32, 0.09))
GATE = dict(y=-1.40, z=0.55, x=0.60, top_z=0.95, top_x=0.51)
# glass panes (grid, same frame), read off the bake's top / side views: the windscreen / roof-glass seam is Tripo's seam
# line y = a + b x^2 (fit resid 1 cm), the roof-glass / rear-glass seam is straight; the black B-pillar trim between the
# door windows runs from y -0.275 to its front edge -0.15 - 0.27 (z - 1); a thin black divider splits the rear door
# window from the fixed quarter glass at y -0.985; side-island dark texels behind the quarter-glass tip (y -1.30) are
# tail-light / spoiler trim, and those more than MIRROR_OUT outside the fitted window surface are the mirror. The
# windscreen ends at y = a + b x^2 + c x^4 (its edge in the bake, resid 3 mm); from there to the hood's top surface
# (+COWL_W) runs the hood's rear lip and the cowl trough: black, |x| < WS_BASE_X (the A-pillar feet). Tripo's normals
# are lumpy there, so the old "rear-facing" test cut ragged polygon notches into the hood (preview 2026-10-24)
WS_SEAM = (0.2633, -0.255)
RW_SEAM_Y = -1.032
B_PILLAR_WIN = (-0.275, -0.15, -0.27)
DIVIDER = (-0.985, 0.008)
QUARTER_TIP_Y = -1.30
MIRROR_OUT = 0.04
WS_BASE = (1.0886, -0.1632, -0.4133)
COWL_W = 0.016
WS_BASE_X = 0.57
PANE_SMOOTH = 8                 # px: pane outlines are a 2 x box(8) blur of the dark mask > 0.5 (notches < ~2 cm go)
# lamps: the LED bars along the hood's front edge and across the tailgate are strips round a smoothed centre line
# through Tripo's bright / red texels (median per 1 cm of x, moving average over `win` cm; Tripo painted them as noisy
# dots and zigzags), the corner tail lamps are the convex hull of Tripo's red blobs
HEAD_BAR = dict(half=0.009, ring=0.006, glow=0.006, win=5)   # glow: mask light zone past the ring (lamps())
TAIL_BAR = dict(half=0.016, ring=0.010, win=5)   # rear light bar 3.2 cm, housing 1 cm; mask light zone = both (lamps())
TAIL_BAR_X = 0.60               # |x| beyond this the red is the corner lamps (StopL / StopR)
HEAD_RGB, LAMP_RGB = (0.90, 0.92, 0.95), (0.36, 0.03, 0.04)
FRIT = 0.022                    # grid: black band round every pane (2.7 cm), 3-D distance from the pane edge
GLASS = (0.15, 0.15, 0.16)      # window panes; the shader adds 30 % sky reflection (vehicle_multiuv.frag:146-152,
#                                 refWindows 0.4 BaseVehicle.java:5987-5988)
GLASS_BASE = (0.06, 0.06, 0.07)  # panes that show the cabin: base + transmission x cabin luminance (Tripo's painting)
# roof glass is mask Roof (no PZ part): body zones get 14 % of sky / 4 instead of the windows' 30 % sky, so its skin
# carries the sky tint. Day light on the roof L ~0.95 (E2E tesla-modely-glass-1024b: skin 86 108 141 read 68 97 123);
# with the sky read off calibration run tesla-modely-glasscal-1024a (roof in WinT read 43 56 73, like the side
# windows) a full day match would be about 50 64 83. This skin sits darker (read 26 35 44 next to windows 43 56 75,
# E2E tesla-modely-glass-1024c): the real roof glass is tinted darker than the windows, and a baked tint does not
# darken with the night sky the windows reflect (the 1024b skin glowed light blue in night-N; vehicle_multiuv.frag:146-153).
# Screen and skin are not proportional (half the skin read 0.38 x): re-measure, do not scale. Calibration knob
ROOF_GLASS = (0.16, 0.19, 0.24)
FRIT_RGB = (0.035, 0.035, 0.04)
TRIM_RGB, TRIM_V = (0.085, 0.085, 0.09), 0.12   # black plastics; Tripo's trim V ~0.10-0.16 maps to x1
# mirror (grid, ground z = 0): the head is beyond |x| base_x, or beyond root_x above root_z (the cap's root by the window
# sits higher than the base arm: Tripo painted it dark, a plain |x| cut left a black patch on the cap); door skin |x|
# p95 0.726 at z 0.85-0.95; bake texels past |x| 0.80 span y 0.51-0.65, z 0.89-1.00
MIRROR = dict(base_x=0.745, root_x=0.705, root_z=0.95, y=(0.48, 0.70), z=(0.86, 1.02))
CAMERA = (0.85, 1.00, 0.68, 0.76)           # side repeater box (y, y, z, z): Tripo's dark wedge y 0.93-0.99, z 0.69-0.74,
#                                             its streaked tail back to the door gap
# rear diffuser (grid): black plastic below the bumper crease (z 0.515-0.525 for |x| < 0.45) out to the outer edge of
# its flange, which runs down and out from (0.54, 0.52) to (0.65, 0.30): |x| < x0 - k z. Tripo painted the whole
# assembly darker than the bumper (V ~0.20 against 0.30-0.41) but above the trim cut, so its panel and flange came out
# body colour; the official renders (official/*_REAR34.png) are black from the crease down, the corners body colour
# down to the lower trim, whose top is an up-facing step at z 0.31-0.33 from the diffuser to the wheel arch (corner_*)
DIFFUSER = dict(y=-1.75, z=0.52, x0=0.80, k=0.50, corner_y=-1.5, corner_x=0.45, corner_z=0.335)
# spoiler (grid): the body-colour ducktail between the rear glass (z 1.045) and the lip over the light housing (z 0.935),
# its top facing up, its back face back. Tripo shaded the back face dark (V 0.17-0.25): above BELT_Z that is "dark",
# and off the glass islands dark is trim, so it came out as black blotches with a grey patch; official renders show
# body colour down to the black light housing
SPOILER = dict(y=-1.6, z=(0.935, 1.045), x=0.5)
# front lip (grid): black below the bumper's body colour, which ends at z 0.360-0.365 for |x| < 0.40 and sweeps down
# from there (0.345 at 0.43, 0.27 at 0.49: the corners stay; cutting to |x| 0.45 squared off the intake's corners);
# Tripo left an isolated body-colour patch on the lip's lower edge (x -0.25..-0.15, z 0.22-0.25), a dark red blob
# under the grille
FRONT_LIP = dict(y=1.7, x=0.40, z=0.355)
# official Model Y paints (decisions.md "車款外觀"): skin order = vehicle script skin index = Core.lua colors order;
# saved games store the index (BaseVehicle.java:2635/2741), so after release only append
PAINTS = [("StealthGrey", "PN01"), ("PearlWhite", "PPSW"), ("DiamondBlack", "PX02"), ("Quicksilver", "PN00"),
          ("UltraRed", "PR01"), ("GlacierBlue", "PB01"), ("MarineBlue", "PB02"), ("FrostBlue", "PB00")]
SKIN = 2048                                 # option 4 cap; the default option 2 shrinks it to 512 on load
GAIN = 0.88                                 # in-game day screen / texture sRGB (E2E tesla-modely-skin-1024c/d: red
#                                             0.80-0.86, white 0.90-0.97), calibration knob
# per-paint, per-channel sRGB tone fix of the paint texels, tex' = a * tex + b: in-game screenshots of the car heading
# S (E2E tesla-modely-1024e option 2, tesla-modely-skin-1024e4 option 4, closest zoom) against the official FRONT34
# render of the same paint (same three-quarter angle; paint pixels = the ones that change between colours): slope
# a = official / game p25-p75 spread (clamped 0.6-1.6), offset b puts the game p50 on the official p50 (/ GAIN).
# Before: Quicksilver, Glacier Blue 35% too light, Diamond Black and Marine Blue crushed (p50 12 vs 30, R 9 vs 26).
# Ultra Red G keeps slope 1 (fit 1.6 is the clamp: its p25-p75 spread is ~3 levels, the slope lit the A-pillar orange)
# Calibration knob: re-measure after changing the paint mapping (.claude/skills/tesla-e2e/perf/paint_sheet.py)
CAL = {
    "StealthGrey": ((0.77, 0.76, 0.76), (0.054, 0.049, 0.049)), "PearlWhite": ((0.92, 0.96, 0.93), (0.034, -0.005, 0.018)),
    "DiamondBlack": ((0.93, 0.93, 0.87), (0.082, 0.080, 0.079)), "Quicksilver": ((0.81, 0.81, 0.84), (-0.041, -0.049, -0.069)),
    "UltraRed": ((0.84, 1.0, 0.79), (0.030, 0.058, 0.069)), "GlacierBlue": ((0.66, 0.71, 0.77), (0.048, 0.025, -0.003)),
    "MarineBlue": ((0.98, 0.72, 0.73), (0.076, 0.079, 0.061)), "FrostBlue": ((0.71, 0.73, 0.74), (0.096, 0.108, 0.134)),
}
OFFICIAL = os.path.join(TMP, "official")
COMPOSITOR = ("https://static-assets.tesla.cn/configurator/compositor?context=design_studio_2&options={}&view={}"
              "&model=my&size=1920&bkba_opt=1&crop=0,0,0,0&overlay=0&")

Z = {  # mask zone colours (media/shaders/vehicle_common.frag.h colZone*)
    "Head": (1, 0, 0), "Tail": (0, 1, 0), "DoorRH": (0, 1, 1), "DoorRT": (1, 1, 0), "DoorLH": (1, 0, 1), "DoorLT": (0, 0, 1),
    "WinRH": (0, .5, .5), "WinRT": (.5, .5, 0), "WinLH": (.5, 0, .5), "WinLT": (0, 0, .5), "WinT": (.5, 0, 0), "WinH": (0, .5, 0),
    "GuardRH": (0, .75, .75), "GuardRT": (.75, .75, 0), "GuardLH": (.75, 0, .75), "GuardLT": (0, 0, .75), "Roof": (0, 0, 0),
    "LightRH": (.25, 0, 0), "LightLH": (.75, 0, 0), "LightRT": (0, .75, 0), "LightLT": (0, .25, 0),
    "StopR": (.5, .25, 0), "StopL": (.5, .75, 0), "Hood": (1, 0, .5), "Boot": (0, 1, .5),
}


# ---------------------------------------------------------------- helpers

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


def decimate(ob, target):
    select_only(ob)
    for _ in range(3):                      # ratio is on triangles; repeat until within 3 %
        n = tris(ob)
        if n <= target * 1.03:
            break
        m = ob.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = target / n
        m.use_symmetry, m.symmetry_axis = True, "X"
        bpy.ops.object.modifier_apply(modifier=m.name)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=0.0005)
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


def to_srgb(lin):
    lin = np.clip(lin, 0, 1)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)


def box_blur(a, r):
    """Separable box blur (radius r px) of a 2-D array, edges clamped."""
    for ax in (0, 1):
        p = np.pad(a, [(r + 1, r) if i == ax else (0, 0) for i in range(2)], mode="edge")
        c = np.cumsum(p, axis=ax)
        a = (np.take(c, np.arange(2 * r + 1, c.shape[ax]), axis=ax) - np.take(c, np.arange(0, c.shape[ax] - 2 * r - 1), axis=ax)) / (2 * r + 1)
    return a


def grow(m, n=2):
    for _ in range(n):
        g = m.copy()
        g[1:] |= m[:-1]
        g[:-1] |= m[1:]
        g[:, 1:] |= m[:, :-1]
        g[:, :-1] |= m[:, 1:]
        m = g
    return m


def downsample(a, f):
    h, w = a.shape[:2]
    return a.reshape(h // f, f, w // f, f, *a.shape[2:]).mean((1, 3))


def emission_from_base(ob):
    """Cycles DIFFUSE colour = base x (1 - metallic) and Tripo paint is metallic: bake base colour as emission."""
    for m in ob.data.materials:
        nt = m.node_tree
        b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        nt.links.new(b.inputs["Base Color"].links[0].from_socket, b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 1.0


def bake_maps(target, source, size, maps, margin=16):
    """maps: list of (name, kind) with kind in pos / nrm / col / ao. Returns {name: HxWx4 float array}."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.bake.margin = margin
    sc.render.bake.margin_type = "EXTEND"
    if sc.world is None:                    # AO ray distance is a world setting
        sc.world = bpy.data.worlds.new("bake")
    sc.world.light_settings.distance = 0.4
    for o in bpy.data.objects:              # other tiers overlap the surface and would occlude every AO ray
        o.hide_render = o not in (target, source)
    mat = bpy.data.materials.new("bake_" + target.name)
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    mat.node_tree.nodes.active = node
    target.data.materials.clear()
    target.data.materials.append(mat)
    for attr in ("visible_camera", "visible_diffuse", "visible_glossy", "visible_transmission", "visible_shadow"):
        setattr(target, attr, False)        # AO rays must only see the high-poly
    out = {}
    for name, kind in maps:
        img = bpy.data.images.new("bake_" + name, size, size, alpha=True, float_buffer=True)
        node.image = img
        if kind == "pos":
            select_only(target); sc.cycles.samples = 1
            bpy.ops.object.bake(type="POSITION", use_clear=True)
        elif kind == "nrm":
            select_only(target); sc.cycles.samples = 1
            bpy.ops.object.bake(type="NORMAL", normal_space="OBJECT", use_clear=True)
        else:
            select_only(source, target)
            sc.cycles.samples = 1 if kind == "col" else 24
            bpy.ops.object.bake(type="EMIT" if kind == "col" else "AO", use_selected_to_active=True, use_clear=True,
                                cage_extrusion=0.03, max_ray_distance=0.12)
        out[name] = img_np(img)
        bpy.data.images.remove(img)
    return out


def export_fbx(ob, path):
    select_only(ob)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", bake_space_transform=True,
                             axis_forward="-Z", axis_up="Y", mesh_smooth_type="OFF",
                             add_leaf_bones=False, bake_anim=False, path_mode="STRIP")


# ---------------------------------------------------------------- prep

def stage_prep():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    hi = [o for o in bpy.data.objects if o.type == "MESH"][0]
    hi.name = "hi"
    # Tripo glTF: front -Y, left +X  ->  rotate 180 deg about Z (front +Y, left -X)
    hi.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ hi.matrix_world
    select_only(hi)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new()                                # glTF splits vertices at every UV / normal seam: weld them so the
    bm.from_mesh(hi.data)                           # surface is connected (decimation and UV islands need that)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(hi.data)
    bm.free()
    co = mesh_co(hi)
    co -= [(co[:, 0].min() + co[:, 0].max()) / 2, (co[:, 1].min() + co[:, 1].max()) / 2, co[:, 2].min()]
    h = co[:, 2].max()
    w = 2 * np.abs(co[co[:, 2] < 0.55 * h][:, 0]).max()          # below the mirrors
    s = L / np.ptp(co[:, 1])                                      # length is exact
    fac = []
    for cur, tgt in ((w * s, W), (h * s, H)):                    # squash only down to the +2 % limit
        r = cur / tgt
        fac.append((1 + DIM_TOL) / r if r > 1 + DIM_TOL else (1 - DIM_TOL) / r if r < 1 - DIM_TOL else 1.0)
    scale = np.array([s * fac[0], s, s * fac[1]])
    co = co * scale
    set_co(hi, co)
    info = {"uniform_scale": s, "x_factor": fac[0], "z_factor": fac[1],
            "uniform_size": [w * s, L, h * s], "final_size": [w * s * fac[0], L, h * s * fac[1]], "official": [W, L, H]}
    # wheels: contact patches (z < 0.02) front / rear; tire outer x; axle height from the cut wheel
    low = co[co[:, 2] < 0.02]
    wheels = []
    for fy in (1, -1):
        yc = float(np.median(low[low[:, 1] * fy > 0][:, 1]))
        near = co[(np.abs(co[:, 1] - yc) < 0.12) & (co[:, 2] < 0.25)]
        wheels.append((yc, float(np.abs(near[:, 0]).max())))
    r0 = 0.356 * K * scale[2] / s                                  # spec radius, squashed like the mesh
    fc = face_centres(hi)
    wl = [(sx, yc, xo) for (yc, xo) in wheels for sx in (-1, 1)]

    def in_wheel(c, sx, yc, xo, pad):
        return (c[:, 0] * sx > xo - TIRE_W - 0.09) & ((c[:, 1] - yc) ** 2 + ((c[:, 2] - r0) * s / scale[2]) ** 2 < (0.356 * K + pad) ** 2)
    wheel_any = np.zeros(len(fc), bool)
    for sx, yc, xo in wl:
        wheel_any |= in_wheel(fc, sx, yc, xo, 0.02)
    fl = in_wheel(fc, -1, wheels[0][0], wheels[0][1], 0.02)
    body = dup(hi, "hi_body")
    keep_faces(body, ~wheel_any)
    wheel = dup(hi, "hi_wheel")
    keep_faces(wheel, fl)
    wc = mesh_co(wheel)
    band = wc[wc[:, 0] < wc[:, 0].min() + 0.025]                  # outermost sidewall bulge = tire silhouette
    info["wheels"] = wheels
    info["wheel_cut"] = {"x": [float(wc[:, 0].min()), float(wc[:, 0].max())], "y": [float(band[:, 1].min()), float(band[:, 1].max())],
                         "z": [float(band[:, 2].min()), float(band[:, 2].max())]}
    bpy.data.objects.remove(hi)
    bpy.context.scene["info"] = json.dumps(info)
    print("PREP", json.dumps(info))
    os.makedirs(PREV, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TMP, "v2_prep.blend"))
    preview.render_views(os.path.join(PREV, "prep"), ortho=4.4, center=Vector((0, 0, H / 2)), res=(2048, 1024),
                         views={"left": Vector((-1, 0, 0)), "iso": Vector((-1, 1, 1.15))})


# ---------------------------------------------------------------- body

def add_liners(bm, wl, r):
    """Dark wheel-well liner per wheel: arc shell over the tire + inner wall (faces tagged liner=1)."""
    lay = bm.faces.layers.int["liner"]
    new = []
    rl = r + 0.05
    a0, a1 = math.radians(-15), math.radians(195)
    for sx, yc, zc, xo in wl:
        xi, xe = sx * (xo - TIRE_W - 0.06), sx * (xo - 0.01)
        ai, ae = [], []
        for i in range(LINER_SEG + 1):
            a = a0 + (a1 - a0) * i / LINER_SEG
            y, z = yc + rl * math.cos(a), zc + rl * math.sin(a)
            ai.append(bm.verts.new((xi, y, z)))
            ae.append(bm.verts.new((xe, y, z)))
        hub = bm.verts.new((xi, yc, zc))
        for i in range(LINER_SEG):
            f = bm.faces.new([ai[i], ai[i + 1], ae[i + 1], ae[i]])
            f.normal_update()
            c = f.calc_center_median()
            if f.normal.dot(Vector((c.x, yc, zc)) - c) < 0:
                f.normal_flip()
            g = bm.faces.new([hub, ai[i], ai[i + 1]])
            g.normal_update()
            if g.normal.x * sx < 0:
                g.normal_flip()
            new += [f, g]
    for f in new:
        f[lay] = 1
    bmesh.ops.triangulate(bm, faces=new)


def head_line():
    """HEAD_LINE as one polyline from the left end to the right end."""
    h = np.array(HEAD_LINE)
    return np.vstack([h[:0:-1] * [-1, 1, 1], h])


def strip_coords(p, q, chunk=40000):
    """(arc length along polyline q, signed distance from it; + up) of points p (N x 3)."""
    if len(p) > chunk:
        parts = [strip_coords(p[i:i + chunk], q, chunk) for i in range(0, len(p), chunk)]
        return np.concatenate([a for a, _ in parts]), np.concatenate([b for _, b in parts])
    seg = q[1:] - q[:-1]
    ln = np.linalg.norm(seg, axis=1)
    t = seg / ln[:, None]
    a = np.clip(((p[:, None] - q[None, :-1]) * t).sum(-1), 0, ln)
    foot = q[None, :-1] + a[..., None] * t
    d = np.linalg.norm(p[:, None] - foot, axis=-1)
    k = d.argmin(1)
    i = np.arange(len(p))
    up = np.array([0, 0, 1.0]) - t[:, 2:3] * t
    up /= np.linalg.norm(up, axis=1)[:, None]
    s0 = np.concatenate([[0], np.cumsum(ln)])
    side = np.where(((p - foot[i, k]) * up[k]).sum(-1) < 0, -1, 1)
    return s0[k] + a[i, k], side * d[i, k]


def project_uv(me):
    """UV0 by planar projection per dominant normal axis (left, right, top, bottom: underbody only, front, back), merged
    into a few large islands like vanilla (ModernCar UV0 50 islands, SUV 39; v1 Smart UV had 587 and bled at every
    edge), plus one island unrolled along the head bar."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()

    def axis(n, p):
        a = (abs(n.x), abs(n.y), abs(n.z))
        if a[2] >= max(a[0], a[1]) * 0.9 and (n.z > 0 or p.z < UNDER_Z):
            return "T" if n.z > 0 else "D"
        if a[0] >= a[1]:
            return "L" if n.x < 0 else "R"
        return "F" if n.y > 0 else "B"
    own = [axis(f.normal, f.calc_center_median()) for f in bm.faces]
    liner = bm.faces.layers.int.get("liner")
    # the head bar runs along the hood / bumper seam and round the front corners: on the top, front and side
    # projections its faces edge on (a staircase island border through the bar on the top island, stripes on the side
    # islands: E2E tesla-modely-glass-1024c). A band round its centre line gets its own island unrolled along it
    hq = head_line()
    fc = np.array([f.calc_center_median() for f in bm.faces])
    _, fd = strip_coords(fc, hq)
    band = {f.index for f in bm.faces if abs(fd[f.index]) < HEAD_BAND and fc[f.index][1] > 1.3 and not f[liner]}
    cls = ["S" if i in band else c for i, c in enumerate(own)]
    for _ in range(4):
        new = cls[:]
        for f in bm.faces:
            if cls[f.index] == "S":
                continue
            nb = [cls[g.index] for e in f.edges for g in e.link_faces if g is not f and cls[g.index] != "S"]
            if nb:
                best = max(set(nb), key=nb.count)
                if nb.count(best) >= 2:
                    new[f.index] = best
        cls = new
    for f in bm.faces:
        if f[liner]:
            cls[f.index] = "L" if f.calc_center_median().x < 0 else "R"

    def components():
        seen, out = set(), []
        for f in bm.faces:
            if f.index in seen:
                continue
            c, stack, part = cls[f.index], [f], []
            seen.add(f.index)
            while stack:
                g = stack.pop()
                part.append(g.index)
                for e in g.edges:
                    for h2 in e.link_faces:
                        if h2.index not in seen and cls[h2.index] == c:
                            seen.add(h2.index)
                            stack.append(h2)
            out.append((c, part))
        return out
    for _ in range(10):
        changed = False
        for c, part in components():
            if c == "S" or len(part) >= max(24, len(bm.faces) * MIN_ISLAND):
                continue
            nb = [cls[h2.index] for i in part for e in bm.faces[i].edges for h2 in e.link_faces
                  if cls[h2.index] not in (c, "S")]
            if nb:
                best = max(set(nb), key=nb.count)
                for i in part:
                    cls[i] = best
                changed = True
        if not changed:
            break
    sv = sorted({lp.vert.index for i in band for lp in bm.faces[i].loops})
    su, sd = strip_coords(np.array([bm.verts[i].co for i in sv]) if sv else np.zeros((0, 3)), hq)
    suv = dict(zip(sv, zip(su, sd)))
    uv = bm.loops.layers.uv.new("UV0")
    proj = {"L": lambda p: (-p.y, p.z), "R": lambda p: (p.y, p.z), "T": lambda p: (p.x, p.y), "D": lambda p: (p.x, -p.y),
            "F": lambda p: (p.x, p.z), "B": lambda p: (-p.x, p.z)}       # every projection seen from outside
    for f in bm.faces:
        if cls[f.index] == "S":                    # (arc length along the bar, signed distance from it)
            for lp in f.loops:
                lp[uv].uv = suv[lp.vert.index]
            continue
        pr = proj[cls[f.index]]
        k = 0.25 if cls[f.index] == "D" else 1.0   # underside: never seen from the iso camera, quarter texel density
        for lp in f.loops:
            lp[uv].uv = [k * t for t in pr(lp.vert.co)]
    n = len(components())
    bm.to_mesh(me)
    bm.free()
    return n


def unwrap(ob):
    me = ob.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    n = project_uv(me)
    me.uv_layers.active = me.uv_layers["UV0"]
    select_only(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(margin=0.006, rotate=True, shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")
    me.uv_layers.new(name="UV1")      # placeholder copy of UV0 (vehicle shaders read two layers); final: damage_uv1
    me.uv_layers.active = me.uv_layers["UV0"]
    me.uv_layers["UV0"].active_render = True
    return n


def transfer_normals(low, hi):
    """Vertex (loop) normals from the high-poly surface: PZ has no normal map, shading comes from these."""
    vg = low.vertex_groups.new(name="body")
    liner = np.array([d.value for d in low.data.attributes["liner"].data], bool)
    verts = sorted({i for k, p in enumerate(low.data.polygons) if not liner[k] for i in p.vertices})
    vg.add(verts, 1.0, "REPLACE")
    select_only(low)
    m = low.modifiers.new("nt", "DATA_TRANSFER")
    m.object = hi
    m.use_loop_data = True
    m.data_types_loops = {"CUSTOM_NORMAL"}
    m.loop_mapping = "POLYINTERP_NEAREST"
    m.vertex_group = "body"
    bpy.ops.object.modifier_apply(modifier=m.name)


def stage_tiers(targets):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(TMP, "v2_prep.blend"))
    info = json.loads(bpy.context.scene["info"])
    hi = bpy.data.objects["hi_body"]
    cut = info["wheel_cut"]
    r = (cut["y"][1] - cut["y"][0]) / 2
    zc = info["wheel_axle_z"] = (cut["z"][0] + cut["z"][1]) / 2
    wl = [(sx, yc, zc, xo) for (yc, xo) in info["wheels"] for sx in (-1, 1)]
    os.makedirs(os.path.join(TMP, "tiers"), exist_ok=True)
    src = hi
    for n in sorted(targets, reverse=True):                          # each tier decimates the previous one
        low = dup(src, f"body_{n}")
        decimate(low, n)
        nb = tris(low)
        bm = bmesh.new()
        bm.from_mesh(low.data)
        bm.faces.layers.int.new("liner")
        add_liners(bm, wl, r)
        bm.to_mesh(low.data)
        bm.free()
        transfer_normals(low, hi)
        islands = unwrap(low)
        print(f"TIER {n}: body {nb} + liner {tris(low) - nb} tris, UV0 islands {islands}")
        export_fbx(low, os.path.join(TMP, "tiers", f"{NAME}_{n}.fbx"))
        src = low
    bpy.context.scene["info"] = json.dumps(info | {"wheel_r": r, "wl": wl})
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TMP, "v2_tiers.blend"))


# ---------------------------------------------------------------- wheel

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


def stage_wheel():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(TMP, "v2_tiers.blend"))
    info = json.loads(bpy.context.scene["info"])
    for o in [o for o in bpy.data.objects if o.name.startswith((NAME + "_Wheel", "wheel_outer", "wheel_src"))]:
        bpy.data.objects.remove(o)                       # re-runnable: the tiers blend keeps the last wheel
    # A surface of revolution, not the Tripo cut: the decimated, mirrored cut left the tread open (319 boundary edges,
    # 101 on the mirror seam) and the road showed through as a white line along the tire's lower edge in game
    r = info["wheel_r"]                                  # tire radius off the high-poly's sidewall (models.md 2)
    rr = WHEEL_SLOT["rim"] * r                           # 19" rim: where the texture's cover ends
    strips = wheel_profile(r, rr, TIRE_W / 2)
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
    print("WHEEL tris", tris(low), "radius", r, "rim", round(rr, 4), "width", TIRE_W)
    bpy.context.scene["info"] = json.dumps(info | {"wheel_tris": tris(low)})
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TMP, "v2_tiers.blend"))


# ---------------------------------------------------------------- final

def raster_liner(ob, size):
    me = ob.data
    att = me.attributes["liner"].data
    uv = me.uv_layers["UV0"].data
    m = np.zeros((size, size), bool)
    for p in me.polygons:
        if att[p.index].value:
            t = np.array([uv[li].uv[:] for li in p.loop_indices]) * size
            x0, y0 = np.floor(t.min(0)).astype(int) - 6
            x1, y1 = np.ceil(t.max(0)).astype(int) + 6
            m[max(y0, 0):min(y1, size), max(x0, 0):min(x1, size)] = True
    return m


def hsv(rgb):
    mx, mn = rgb.max(-1), rgb.min(-1)
    return mx, np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0)


FILL_RES = 150   # px per grid of the ortho rasters for the glass fill (~30 texels of the 4096 bake per pixel)


def enclosed(u, v, sel, dark):
    """Texels of sel whose ortho pixel (u, v) is mostly dark or cut off from the raster border by dark pixels."""
    if not sel.any():
        return np.zeros(u.shape, bool)
    uu = ((u[sel] - u[sel].min()) * FILL_RES).astype(np.int64) + 1
    vv = ((v[sel] - v[sel].min()) * FILL_RES).astype(np.int64) + 1
    W, H = int(uu.max()) + 2, int(vv.max()) + 2
    k = vv * W + uu
    wall = (np.bincount(k, dark[sel], W * H) > 0.5 * np.bincount(k, None, W * H)).reshape(H, W)
    out = np.zeros((H, W), bool)
    out[0] = out[-1] = True
    out[:, 0] = out[:, -1] = True
    while True:                                                    # flood fill from the border around the walls
        g = grow(out, 1) & ~wall
        if (g == out).all():
            break
        out = g
    res = np.zeros(u.shape, bool)
    res[sel] = ~out.reshape(-1)[k]
    return res


def uv_raster(me, size):
    """Per bake texel (same centres as the Cycles bake, row 0 = v 0): polygon index and UV0 island index, -1 where no
    polygon covers the texel (the bake margin)."""
    me.uv_layers.active = me.uv_layers["UV0"]
    pid_isl = np.empty(len(me.polygons), np.int32)
    for k, faces in enumerate(mesh_utils.mesh_linked_uv_islands(me)):
        pid_isl[faces] = k
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers["UV0"].data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2) * size - 0.5
    fid = np.full((size, size), -1, np.int32)
    for p in me.polygons:
        li = list(p.loop_indices)
        for a, b in zip(li[1:-1], li[2:]):
            t = uv[[li[0], a, b]]
            x0, y0 = np.maximum(np.floor(t.min(0)).astype(int), 0)
            x1, y1 = np.minimum(np.ceil(t.max(0)).astype(int), size - 1)
            (ax, ay), (bx, by), (cx, cy) = t
            d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if x1 < x0 or y1 < y0 or abs(d) < 1e-12:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
            l1 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / d
            l2 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / d
            ins = (l1 >= -1e-6) & (l2 >= -1e-6) & (l1 + l2 <= 1 + 1e-6)
            fid[gy[ins], gx[ins]] = p.index
    return fid, np.where(fid >= 0, pid_isl[np.maximum(fid, 0)], -1)


def nearest_src(valid, n=20):
    """Flat index of the nearest valid texel (n 4-neighbour steps) for every texel, itself where valid or out of reach:
    fills the bake margin from final values, like the bake's EXTEND margin."""
    h, w = valid.shape
    idx = np.arange(h * w, dtype=np.int32).reshape(h, w)
    src = np.where(valid, idx, -1)
    for _ in range(n):
        miss = src < 0
        for sh in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            s2 = np.roll(src, sh, (0, 1))
            take = miss & (s2 >= 0)
            src[take] = s2[take]
            miss &= ~take
    return np.where(src >= 0, src, idx).ravel()


def quad_terms(u, v):
    return np.stack([np.ones_like(u), u, v, u * u, u * v, v * v], -1)


def quad_fit(P, n_hint):
    """Height h = f(u, v), a quadric in the frame of the mean normal, least squares dropping points beyond 3 rms (4
    rounds). Returns the fit and every point's residual (+ = outwards)."""
    n0 = n_hint / np.linalg.norm(n_hint)
    t1 = np.cross((0.0, 0.0, 1.0) if abs(n0[2]) < 0.9 else (1.0, 0.0, 0.0), n0)
    t1 /= np.linalg.norm(t1)
    t2 = np.cross(n0, t1)
    c0 = P.mean(0)
    Q = P - c0
    A, h = quad_terms(Q @ t1, Q @ t2), Q @ n0
    keep = np.ones(len(P), bool)
    for _ in range(4):
        cf = np.linalg.lstsq(A[keep], h[keep], rcond=None)[0]
        r = h - A @ cf
        rms = float(np.sqrt((r[keep] ** 2).mean()))
        keep = np.abs(r) < max(3 * rms, 0.01)
    return (c0, n0, t1, t2, cf, rms), r


def quad_normal(fit, P):
    c0, n0, t1, t2, cf, _ = fit
    Q = P - c0
    u, v = Q @ t1, Q @ t2
    n = n0 - (cf[1] + 2 * cf[3] * u + cf[4] * v)[:, None] * t1 - (cf[2] + cf[4] * u + 2 * cf[5] * v)[:, None] * t2
    return n / np.linalg.norm(n, axis=1, keepdims=True)


P_WS, P_ROOF, P_RW, P_LF, P_LR, P_RF, P_RR, P_BPIL = range(1, 9)   # glass pane codes (P_BPIL: black B-pillar trim)
PANE_ZONE = {P_WS: "WinT", P_ROOF: "Roof", P_RW: "WinH", P_LF: "WinLH", P_LR: "WinLT", P_RF: "WinRH", P_RR: "WinRT",
             P_BPIL: "Roof"}
# cabin transmission per pane: front glass clearer, rear privacy glass darker as on the car. Calibration knob
INTERIOR = {P_WS: 0.55, P_LF: 0.5, P_RF: 0.5, P_LR: 0.4, P_RR: 0.4, P_RW: 0.4}


def bbox_op(m, pad, fn):
    """fn on the bounding box of m grown by pad (the 4096 box blurs are slow on the full map)."""
    out = np.zeros(m.shape, bool)
    rows, cols = np.flatnonzero(m.any(1)), np.flatnonzero(m.any(0))
    if len(rows):
        r0, r1 = max(rows[0] - pad, 0), min(rows[-1] + pad + 1, m.shape[0])
        c0, c1 = max(cols[0] - pad, 0), min(cols[-1] + pad + 1, m.shape[1])
        out[r0:r1, c0:c1] = fn(m[r0:r1, c0:c1])
    return out


def closing(m, r=10):
    return box_blur((box_blur(m.astype(np.float32), r) > 1e-4).astype(np.float32), r) > 1 - 1e-4


def smooth_mask(m, region, r):
    """m (inside region) with a smooth outline: 2 x box(r) blur normalised by the region (no erosion along the island
    border), > 0.5."""
    out = np.zeros(m.shape, bool)
    rows, cols = np.flatnonzero(m.any(1)), np.flatnonzero(m.any(0))
    if len(rows):
        p = 2 * r + 2
        r0, r1 = max(rows[0] - p, 0), min(rows[-1] + p + 1, m.shape[0])
        c0, c1 = max(cols[0] - p, 0), min(cols[-1] + p + 1, m.shape[1])
        sr = region[r0:r1, c0:c1].astype(np.float32)
        num = box_blur(box_blur(m[r0:r1, c0:c1].astype(np.float32), r), r)
        out[r0:r1, c0:c1] = (num > 0.5 * box_blur(box_blur(sr, r), r)) & (sr > 0)
    return out


def glass_panes(pos, nrm, dark, iid, covered, liner):
    """Pane code per texel (0 = not glass) and the cowl strip. Panes follow the UV islands (top: windscreen, roof glass,
    rear glass split at the seams; the two big side islands: door windows split at the B-pillar trim), not texel
    normals: Tripo moulded the cabin into the glass, so normal thresholds punched holes in the windscreen and smeared
    side-window zones onto the roof edges (v2 mask). Dark texels elsewhere (mirrors, spoiler and tail-light trim) are
    not glass. Outlines: specks closed, then smoothed (Tripo's dark edges are ragged)."""
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    ok = covered & ~liner

    def island(m):                                                  # the island holding most of these texels
        return int(np.argmax(np.bincount(iid[m & (iid >= 0)])))

    def clean(m, region):
        return smooth_mask(m | (bbox_op(m, 24, closing) & region), region, PANE_SMOOTH)
    pane = np.zeros(x.shape, np.int8)
    top = (iid == island(covered & (nrm[..., 2] > 0.7) & (z > 1.15))) & ok
    t = clean(dark & top, top)
    yb = WS_BASE[0] + WS_BASE[1] * x * x + WS_BASE[2] * x ** 4
    foot = top & (np.abs(x) < WS_BASE_X) & (z > 0.85)
    t = (t & ~(foot & (y > yb))) | (foot & (y > yb - 0.012) & (y <= yb))
    cowl = foot & (y > yb) & (y < yb + COWL_W)
    ws = WS_SEAM[0] + WS_SEAM[1] * x * x
    pane[t & (y > ws)] = P_WS
    pane[t & (y <= ws) & (y >= RW_SEAM_Y)] = P_ROOF
    pane[t & (y < RW_SEAM_Y)] = P_RW
    front = B_PILLAR_WIN[1] + B_PILLAR_WIN[2] * (z - 1.0)
    for sgn, pf, pr in ((-1, P_LF, P_LR), (1, P_RF, P_RR)):
        isl = (iid == island(covered & (sgn * nrm[..., 0] > 0.7) & (z > 0.95) & (z < 1.2))) & ok
        s = dark & isl & (y >= QUARTER_TIP_Y)
        mirror = np.zeros(x.shape, bool)
        mirror[s] = quad_fit(pos[s], nrm[s].mean(0))[1] > MIRROR_OUT
        s = clean(s & ~mirror, isl & ~mirror) & (y >= QUARTER_TIP_Y)
        pane[s & (y > front)] = pf
        pane[s & (y < B_PILLAR_WIN[0])] = pr
        pane[s & (y >= B_PILLAR_WIN[0]) & (y <= front)] = P_BPIL
    return pane, cowl


def strip(pos, seed, cand, win):
    """3-D distance (grid; inf outside cand) from every cand texel to the centre line through the seed texels.
    Centre = median y, z per 1 cm of x (bins under 20 seeds are interpolated: Tripo's bar fades at the corners and a
    few speckles pulled the line 1 cm off there), moving average over win bins, sampled every 2 mm of x; then three
    rounds of moving each sample onto the nearest cand texel and averaging over 1 cm (an averaged line floats off a
    curved surface)."""
    P = pos[seed]
    bins = np.arange(P[:, 0].min(), P[:, 0].max() + 1e-6, 0.01)
    rows = [(xv, np.median(P[m, 1]), np.median(P[m, 2]))
            for xv in bins for m in [np.abs(P[:, 0] - xv) <= 0.005] if m.sum() >= 20]
    xs, cy, cz = np.array(rows).T
    k = np.ones(win) / win
    cy, cz = (np.convolve(np.pad(a, win // 2, mode="edge"), k, "valid") for a in (cy, cz))
    xd = np.arange(xs[0], xs[-1] + 1e-6, 0.002)
    line = np.stack([xd, np.interp(xd, xs, cy), np.interp(xd, xs, cz)], -1).astype(np.float32)
    idx = np.flatnonzero(cand.ravel())
    Q = pos.reshape(-1, 3)[idx]

    def nearest(fn):                                   # chunks of cand x line distances: (cand chunk, samples)
        for i in range(0, len(Q), 4000):
            fn(i, ((Q[i:i + 4000, None, :] - line[None]) ** 2).sum(-1))
    k5 = np.ones(5) / 5
    for _ in range(3):
        best = np.full(len(line), np.inf, np.float32)
        snap = line.copy()

        def keep_best(i, dd):
            j = dd.argmin(0)
            dj = dd[j, np.arange(len(line))]
            upd = dj < best
            best[upd], snap[upd] = dj[upd], Q[i:i + 4000][j[upd]]
        nearest(keep_best)
        for c in (1, 2):
            line[:, c] = np.convolve(np.pad(snap[:, c], 2, mode="edge"), k5, "valid")
    d = np.empty(len(Q), np.float32)

    def dist(i, dd):
        d[i:i + 4000] = np.sqrt(dd.min(1))
    nearest(dist)
    out = np.full(cand.size, np.inf, np.float32)
    out[idx] = d
    return out.reshape(cand.shape)


def hull2(p):
    """Convex hull (counter-clockwise) of 2-D points, Andrew's monotone chain."""
    p = np.unique(np.round(p, 4), axis=0)

    def chain(ps):
        out = []
        for q in ps:
            while len(out) >= 2 and ((out[-1][0] - out[-2][0]) * (q[1] - out[-2][1])
                                     - (out[-1][1] - out[-2][1]) * (q[0] - out[-2][0])) <= 0:
                out.pop()
            out.append(q)
        return out
    return np.array(chain(p)[:-1] + chain(p[::-1])[:-1])


def lamps(pos, nrm, col, v, covered, liner):
    """Head bar, rear light bar, corner tail lamps and the black housing round them (masks)."""
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    ok = covered & ~liner
    # head bar seeds: the surface within 1.2 cm of HEAD_LINE (Tripo's bright texels, left and right averaged and
    # smoothed): straight from them, the line jogged 1 cm where Tripo's dots strayed (E2E tesla-modely-glass-1024c)
    hc = ok & (y > 1.45) & (z > 0.58) & (z < 0.78)
    seed = np.zeros(x.shape, bool)
    seed[hc] = np.abs(strip_coords(pos[hc], head_line())[1]) < 0.012
    dh = strip(pos, seed, hc, HEAD_BAR["win"])
    head = dh < HEAD_BAR["half"]
    ring = dh < HEAD_BAR["half"] + HEAD_BAR["ring"]
    # round the bar (its UV0 band) Tripo painted highlight and groove speckles (the bright ones took the paint's top
    # highlight: white blotches by the corners; the dark ones turned trim: dashes under the bar); stage_final repaints
    # them as the surrounding paint
    soft = (dh < HEAD_BAND) & ~ring & ok
    red = covered & (col[..., 0] > 0.3) & (col[..., 0] > 1.8 * col[..., 1]) & (y < -1.4) & (z > 0.78) & (z < 0.94)
    bar = np.abs(x) <= TAIL_BAR_X
    # rear light bar: Tripo's red band (z 0.86-0.90, facing back) is a ragged zigzag; a clean bar round its centre line,
    # on every face of the recess (on the back wall alone the spoiler lip hides it from the iso camera: a dotted dark line
    # at night, E2E tesla-modely-tex-1024b), in a black housing that also takes the rest of Tripo's red (left as dark
    # red blotches otherwise). The recess used to sit in a quarter-density "underside" UV island (squashed in height)
    # until project_uv kept that projection for the underbody (UNDER_Z)
    dt = strip(pos, red & bar, ok & (y < -1.4) & (z > 0.76) & (z < 0.98), TAIL_BAR["win"])
    tail = (dt < TAIL_BAR["half"]) & bar & ok
    ring |= ((dt < TAIL_BAR["half"] + TAIL_BAR["ring"]) | red) & bar & ok & ~tail
    # corner lamps: convex hull, in the side view (y, z), of Tripo's red past the bar on both sides (its blobs are
    # ragged and its right lamp is a third of the left one), on the corner surfaces past the bar
    stop = hull_mask(red & ~bar, ok & ~bar & (y < -1.5) & (z > 0.78) & (z < 0.96), pos)
    ring = (ring | (grow(stop, 4) & ok)) & ok & ~(head | tail | stop)
    # mask light zones are wider than the bars: the mask is sampled bilinearly and a texel only counts for a zone within
    # 0.01 of its colour (vehicle_multiuv.frag:99-127), so a 1-2 px bar on the 512 mask fell into the blend with its
    # black housing and stayed dark at night (E2E tesla-modely-tex-1024a night-N); the lights alpha draws the bar
    hz = (dh < HEAD_BAR["half"] + HEAD_BAR["ring"] + HEAD_BAR["glow"]) & ok
    tz = (dt < TAIL_BAR["half"] + TAIL_BAR["ring"]) & bar & ok & ~stop
    return head, tail & ~stop, stop, ring, soft & ~(head | tail | stop | ring), hz, tz


def hull_mask(seed, cand, pos, tol=0.003):
    """cand texels within tol (grid) of the convex hull, in the side view (y, z), of the seed texels."""
    h = hull2(pos[seed][:, 1:])
    e = np.roll(h, -1, 0) - h
    out = np.stack([e[:, 1], -e[:, 0]], -1) / np.linalg.norm(e, axis=1, keepdims=True)
    m = np.zeros(seed.shape, bool)
    m[cand] = (((pos[cand][:, None, 1:] - h[None]) * out[None]).sum(-1) <= tol).all(1)
    return m


def median3(a, m, rows=512):
    """3 x 3 median of a where the whole window lies in m (elsewhere a), in row chunks (the 4096^2 stack is 600 MB)."""
    out = a.copy()
    h, w = a.shape
    for r0 in range(1, h - 1, rows):
        r1 = min(r0 + rows, h - 1)
        win = [(dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1)]
        full = np.logical_and.reduce([m[r0 + dy:r1 + dy, 1 + dx:w - 1 + dx] for dy, dx in win])
        med = np.median(np.stack([a[r0 + dy:r1 + dy, 1 + dx:w - 1 + dx] for dy, dx in win]), 0)
        out[r0:r1, 1:-1] = np.where(full, med, a[r0:r1, 1:-1])
    return out


def mirror_head(pos):
    """Mirror head texels (cap, glass, underside), outboard of the door skin and the base arm (MIRROR)."""
    ax, y, z = np.abs(pos[..., 0]), pos[..., 1], pos[..., 2]
    box = (y > MIRROR["y"][0]) & (y < MIRROR["y"][1]) & (z > MIRROR["z"][0]) & (z < MIRROR["z"][1])
    return box & (ax > MIRROR["root_x"]) & ((ax > MIRROR["base_x"]) | (z > MIRROR["root_z"]))


def frit_band(pane, vis, pos, width):
    """Texels of each pane within width (grid) of anything else, geodesic over the texel grid with 3-D steps (8
    neighbours), polygon texels only (vis): a fixed texel radius drew the band twice as wide where the roof edge
    curves down (the top projection squeezes steep surfaces)."""
    band = np.zeros(pane.shape, bool)
    steps = [(dr, dc) for dr in (-1, 0, 1) for dc in (-1, 0, 1) if dr or dc]
    for k in range(P_WS, P_BPIL):
        m = (pane == k) & vis
        rows, cols = np.flatnonzero(m.any(1)), np.flatnonzero(m.any(0))
        if not len(rows):
            continue
        r0, r1 = max(rows[0] - 2, 0), min(rows[-1] + 3, m.shape[0])
        c0, c1 = max(cols[0] - 2, 0), min(cols[-1] + 3, m.shape[1])
        sm, sp = m[r0:r1, c0:c1], pos[r0:r1, c0:c1]
        d = np.where(sm, np.inf, 0.0).astype(np.float32)
        lens = [np.linalg.norm(sp - np.roll(sp, s, (0, 1)), axis=-1) for s in steps]
        for _ in range(int(width * 910 * 1.6) + 2):          # 910 px / grid; steep parts need fewer px
            for s, ln in zip(steps, lens):
                np.minimum(d, np.roll(d, s, (0, 1)) + ln, out=d)
        band[r0:r1, c0:c1] |= sm & (d < width)
    return band


def smooth_glass_normals(ob, pane, fid, x):
    """Corner normals of the glass faces from one quadric per pane group (windscreen, roof, rear, each side with its
    B-pillar): Tripo moulded seats, headrests and the dash into the glass and the transferred high-poly normals carried
    those bumps, which the shader's 3-step light quantise and sphere-map reflection drew as contour blobs on the
    windscreen. Body faces keep their normals; 'custom_normal' becomes free per-corner normals (FLOAT_VECTOR)."""
    me = ob.data
    grp = np.array([0, 1, 2, 3, 4, 4, 5, 5, 0], np.int64)[pane]
    grp[(pane == P_BPIL) & (x < 0)] = 4
    grp[(pane == P_BPIL) & (x >= 0)] = 5
    vis = fid >= 0
    nf = len(me.polygons)
    cnt = np.bincount(fid[vis].astype(np.int64) * 6 + grp[vis], minlength=nf * 6).reshape(nf, 6)
    fg = np.where(cnt.max(1) * 2 > cnt.sum(1), cnt.argmax(1), 0)          # the group of most of the face's texels
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    fn = np.empty(nf * 3)
    me.polygons.foreach_get("normal", fn)
    fn = fn.reshape(-1, 3)
    lv = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", lv)
    lf = np.empty(len(me.loops), np.int64)
    for p in me.polygons:
        lf[p.loop_start:p.loop_start + p.loop_total] = p.index
    cn = np.empty(len(me.loops) * 3, np.float32)
    me.corner_normals.foreach_get("vector", cn)
    cn = cn.reshape(-1, 3)
    stats = []
    for g in range(1, 6):
        faces = np.flatnonzero(fg == g)
        loops = np.flatnonzero(fg[lf] == g)
        if not len(faces):
            continue
        fit = quad_fit(co[np.unique(lv[loops])], fn[faces].mean(0))[0]
        cn[loops] = quad_normal(fit, co[lv[loops]])
        stats.append(f"{g}:{len(faces)}f/rms {fit[5]:.4f}")
    me.attributes.remove(me.attributes["custom_normal"])
    me.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER").data.foreach_set("vector", cn.ravel())
    me.update()
    print("GLASS normals", " ".join(stats))


def classify(pos, nrm, col, liner, iid, iidf):
    """iid: UV0 island per polygon texel (-1 in the bake margin), iidf: the same filled into the margin."""
    covered = np.abs(np.linalg.norm(nrm, axis=-1) - 1) < 0.2     # unbaked texels decode to (-1,-1,-1)
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    nx, ny, nz = nrm[..., 0], nrm[..., 1], nrm[..., 2]
    v, s = hsv(col)
    left = x < 0
    side = np.abs(nx) > 0.45
    zone = np.full(x.shape, "Roof", dtype=object)

    def put(cond, l, r):
        cond = cond & covered
        zone[cond & left] = l
        zone[cond & ~left] = r
    put((y > DOOR_FRONT_Y) & (z < BELT_Z + 0.05), "GuardLH", "GuardRH")
    put((y < DOOR_REAR_Y) & (z < BELT_Z + 0.05), "GuardLT", "GuardRT")
    put(side & (y <= DOOR_FRONT_Y) & (y > B_PILLAR_Y) & (z > DOOR_SILL_Z) & (z < BELT_Z + 0.1), "DoorLH", "DoorRH")
    put(side & (y <= B_PILLAR_Y) & (y >= DOOR_REAR_Y) & (z > DOOR_SILL_Z) & (z < BELT_Z + 0.1), "DoorLT", "DoorRT")
    put((y > 0.75) & (z > 0.58) & (z < BELT_Z + 0.02) & (nz > 0.35), "Hood", "Hood")
    put((y > 1.5) & (z <= 0.62) & ((ny > 0.3) | (y > 1.85)), "Head", "Head")
    put((y < -1.45) & (z > 0.55) & ((ny < -0.2) | (nz > 0.3)) & (np.abs(x) < np.where(z < GATE["top_z"], GATE["x"],
                                                                                       GATE["top_x"])), "Boot", "Boot")
    put((y < -1.45) & (z <= 0.55) & ((ny < -0.3) | (y < -1.85)), "Tail", "Tail")
    # dark (glass-like): V < 0.215; on the roof Tripo's glass carries sky reflections (V p95 0.40) while the body-colour
    # roof rails read V 0.43-0.64, so up there the test runs on blurred V < 0.4. Tripo also shows the cabin through the
    # windscreen (dashboard: the light block at its foot read as paint): whatever the dark glass encloses in the top,
    # front and back ortho views (by dominant normal) is dark too. Not the side views: the mirrors project into the
    # side windows there. Which dark texels are glass, and which pane, is glass_panes' call
    up = covered & (z > BELT_Z - 0.04) & ~liner
    dark = up & np.where((nz > 0.3) & (z > BELT_Z + 0.12), box_blur(v, 10) < 0.4, v < 0.215)
    ax = np.argmax(np.abs(nrm), -1)
    glass = dark.copy()
    for sel, iu, iv in ((up & (ax == 2) & (nz > 0), 1, 0), (up & (ax == 1) & (ny > 0), 0, 2), (up & (ax == 1) & (ny < 0), 0, 2)):
        glass |= enclosed(pos[..., iu], pos[..., iv], sel, dark)
    glass = (box_blur(glass.astype(np.float32), 10) > 0.5) & covered & ~liner     # majority: no ragged rail edge
    pane, cowl = glass_panes(pos, nrm, glass, iidf, covered, liner)
    # the mirror heads sit outboard of the side glass (|x| <= 0.73 there) but Tripo's dark blotches on their caps read
    # as glass in the side island: never glass
    mh = mirror_head(pos)
    pane[mh] = 0
    for k, zn in PANE_ZONE.items():
        zone[pane == k] = zn
    # black: the frit band round every pane, the B-pillar trim and the quarter-glass divider. Mask Roof (body): they
    # stay when a window is removed (a frame round the 0.2 grey, vehicle_multiuv.frag:175) and the mask's bilinear
    # zone edge (flags 256, no nearest bit: TextureID.java:424-442) falls inside black instead of across the glass
    rear = (pane == P_LR) | (pane == P_RR)
    black = frit_band(pane, iid >= 0, pos, FRIT) | (pane == P_BPIL) | (rear & (np.abs(y - DIVIDER[0]) < DIVIDER[1]))
    black &= ~mh                             # the band walks the texel grid: the caps sit next to the side glass in UV
    zone[black | cowl] = "Roof"
    head, tail, stop, ring, soft, hz, tz = lamps(pos, nrm, col, v, covered, liner)
    put(hz, "LightLH", "LightRH")
    put(tz, "LightLT", "LightRT")
    put(stop, "StopL", "StopR")
    zone[liner] = "Roof"
    return zone, pane, black, cowl, glass, dict(head=head, tail=tail, stop=stop, ring=ring, soft=soft), covered


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


def face_zones(fid, mask, nf):
    """Mask zone per polygon: majority over the bake texels it covers ("" for polygons under one texel)."""
    c = zone_codes(mask)
    ok = (fid >= 0) & (c >= 0)
    cnt = np.bincount(fid[ok].astype(np.int64) * 125 + c[ok], minlength=nf * 125).reshape(nf, 125)
    return np.where(cnt.max(1) > 0, ZCODE[cnt.argmax(1)], "")


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


def stage_final(n):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(TMP, "v2_tiers.blend"))
    info = json.loads(bpy.context.scene["info"])
    hi = bpy.data.objects["hi_body"]
    body = bpy.data.objects[f"body_{n}"]
    body.name = NAME
    cache = os.path.join(TMP, f"bake_{n}.npz")      # the 4096 Cycles bake takes minutes; texture passes reuse it
    if os.path.exists(cache):
        c = np.load(cache)
        pos, nrm, col, ao = (c[k].astype(np.float32) for k in ("pos", "nrm", "col", "ao"))
        liner = c["liner"]
    else:
        emission_from_base(hi)
        b = bake_maps(body, hi, BAKE, [("pos", "pos"), ("nrm", "nrm"), ("col", "col")])
        ao = bake_maps(body, hi, BAKE // 2, [("ao", "ao")])["ao"][..., 0]
        ao = np.repeat(np.repeat(ao, 2, 0), 2, 1)
        liner = raster_liner(body, BAKE)
        col = to_srgb(b["col"][..., :3])
        pos, nrm = b["pos"][..., :3], b["nrm"][..., :3] * 2 - 1
        np.savez(cache, pos=pos.astype(np.float16), nrm=nrm.astype(np.float16), col=col.astype(np.float16),
                 ao=ao.astype(np.float16), liner=liner)
    fid, iid = uv_raster(body.data, BAKE)
    src = nearest_src(fid >= 0)            # bake margin <- nearest polygon texel: island map now, final textures below
    iidf = iid.ravel()[src].reshape(iid.shape)
    zone, pane, black, cowl, dark, lamp, covered = classify(pos, nrm, col, liner, iid, iidf)
    glass = pane > 0
    lights = lamp["head"] | lamp["tail"] | lamp["stop"] | lamp["ring"]
    v, s = hsv(col)
    # paint = body grey; decided on blurred V so Tripo's dark reflection patches on the hood stay paint, while the
    # black plastics (rocker, diffuser, grille: V 0.10-0.16) do not (door V p5 0.29, hood p5 0.16). The blur skips
    # dark texels (else the mirror caps and pillars by the dark glass turned trim). No upper V cap: Tripo's highlights
    # by the headlight strip are paint. 7x7 majority: no ragged teeth on the glass / trim edges. Dark texels that are
    # not glass (mirror base, spoiler and tail-light trim) stay trim
    ng = (covered & ~dark).astype(np.float32)
    vb = box_blur(v * ng, 24) / np.maximum(box_blur(ng, 24), 1e-3)
    free = covered & ~glass & ~lights & ~liner & ~cowl
    paint = free & ~dark & (vb > 0.19) & (s < 0.3)
    paint = (box_blur(paint.astype(np.float32), 3) > 0.5) & free & ~dark
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    # mirrors: the cap is body colour (Tripo's dark reflection blotches on it turned trim or the darkest paint), the
    # glass faces back, the underside and the base arm by the window stay black. Side repeater camera on each front
    # fender: Tripo's dark wedge has light streaks in it; the convex hull (y, z) of its darker texels is solid black
    mr = free & mirror_head(pos)
    mglass = mr & (nrm[..., 1] < -0.5)
    cap = mr & ~mglass & (nrm[..., 2] > -0.3)
    paint &= ~(mr & ~cap)
    sd = free & (np.abs(nrm[..., 0]) > 0.4) & (y > CAMERA[0]) & (y < CAMERA[1]) & (z > CAMERA[2]) & (z < CAMERA[3])
    badge = hull_mask(sd & (v < 0.25), sd, pos)
    paint = (paint | cap) & ~(mglass | badge)
    # lower black plastics: rear diffuser from the bumper crease down between the outer edges of its flange, the lower
    # trim under both rear corners (DIFFUSER), and the front lip under the bumper (FRONT_LIP)
    ax_ = np.abs(x)
    dif = (y < DIFFUSER["y"]) & (z < DIFFUSER["z"]) & (ax_ < DIFFUSER["x0"] - DIFFUSER["k"] * z)
    dif |= (y < DIFFUSER["corner_y"]) & (ax_ > DIFFUSER["corner_x"]) & (z < DIFFUSER["corner_z"])
    dif |= (y > FRONT_LIP["y"]) & (ax_ < FRONT_LIP["x"]) & (z < FRONT_LIP["z"])
    paint &= ~(dif & free)
    # spoiler: all body colour; dark texels on its back face lifted to the tailgate's median, on its top to the top's
    sp = free & ~black & (y < SPOILER["y"]) & (z > SPOILER["z"][0]) & (z < SPOILER["z"][1]) & (np.abs(x) < SPOILER["x"])
    sp_back, sp_top = sp & (nrm[..., 1] < -0.5), sp & (nrm[..., 1] >= -0.5)
    gate = paint & (y < DIFFUSER["y"]) & (z > 0.55) & (z < 0.8) & (np.abs(x) < SPOILER["x"])
    lift_back, lift_top = np.median(v[gate]), np.median(v[sp_top & paint])
    paint |= sp
    # Tripo's speckles along the head bar (lamp["soft"]) become paint at the brightness of the paint round them; the
    # mirror cap keeps its highlights, its darker half is lifted to the cap's median
    soft = lamp["soft"] & free
    keep = paint & ~soft & ~cap
    kf = keep.astype(np.float32)
    near, w = (box_blur(a, 32) for a in (v * kf, kf))
    far = box_blur(v * kf, 96) / np.maximum(box_blur(kf, 96), 1e-3)            # mid-band, 3 cm from any paint
    vk = np.where(soft, np.where(w > 0.02, near / np.maximum(w, 1e-3), far), v)
    if cap.any():
        vk = np.where(cap, np.maximum(v, np.median(v[cap])), vk)
    vk = np.where(sp_back, np.maximum(v, lift_back), np.where(sp_top, np.maximum(v, lift_top), vk))
    paint |= soft
    vk = median3(vk, paint)          # Tripo's single-texel paint speckle; gap lines (>= 2 px) and highlights stay
    base = np.concatenate([col, np.ones(col.shape[:2] + (1,))], -1).astype(np.float32)
    # glass: the cabin Tripo painted through it (dash, centre screen, wheel, seats, rear headrests) seen through a tint:
    # its luminance, smoothed inside the panes (normalised blur: no frit or paint bleeds in), x the pane's transmission
    # over a dark base. The blotches it used to make were the bumpy normals under the 3-step light quantise, flattened
    # by smooth_glass_normals. Black frit band, B-pillar trim and quarter divider; the roof glass (Tripo painted it
    # plain) bakes in the reflection the window zones get from the shader. Lamps and the cowl strip are flat too
    # (Tripo's were noisy dots and zigzags)
    base[glass, :3] = GLASS
    seen = np.isin(pane, list(INTERIOR)) & ~black
    sf = seen.astype(np.float32)
    cab = box_blur((col @ np.array([0.2126, 0.7152, 0.0722], np.float32)) * sf, 3) / np.maximum(box_blur(sf, 3), 1e-3)
    trans = np.zeros(pane.shape, np.float32)
    for k, t in INTERIOR.items():
        trans[pane == k] = t
    base[seen, :3] = np.array(GLASS_BASE, np.float32) + (trans * cab)[seen][:, None] * [1, 1, 1.04]
    base[pane == P_ROOF, :3] = ROOF_GLASS
    base[black | cowl | lamp["ring"], :3] = FRIT_RGB
    base[lamp["head"], :3] = HEAD_RGB
    base[lamp["tail"], :3] = LAMP_RGB
    base[lamp["stop"], :3] = LAMP_RGB
    # trim (rocker, diffuser, grille, arch edges, mirror base): satin black plastic, AO shaded, with Tripo's light kept
    # only as a 9 x 9 normalised blur inside the trim (+-40 %: grille slats stay, its speckle and streaks go)
    trim = free & ~paint & ~mglass & ~badge
    tf = trim.astype(np.float32)
    rel = np.clip(box_blur(v * tf, 4) / np.maximum(box_blur(tf, 4), 1e-3) / TRIM_V, 0.6, 1.4)
    base[trim, :3] = (np.array(TRIM_RGB, np.float32) * (rel * (0.55 + 0.45 * ao))[..., None])[trim]
    base[mglass, :3] = GLASS
    base[badge, :3] = FRIT_RGB
    base[liner, :3] = 0.03
    mask = np.zeros(zone.shape + (4,), np.float32)
    mask[..., 3] = 1
    for k, c in Z.items():
        mask[zone == k, :3] = np.round(np.array(c) * 255) / 255
    lit = np.zeros(zone.shape + (4,), np.float32)
    for k, c in (("LightLH", (1, 1, .95)), ("LightRH", (1, 1, .95)), ("LightLT", (1, .12, .08)), ("LightRT", (1, .12, .08)),
                 ("StopL", (1, 0, 0)), ("StopR", (1, 0, 0))):
        lit[zone == k] = c + (1,)
    # inside the wider head-light zone the bar glows at full strength, the black ring round it at 0.4; the rear zone
    # glows whole (bar and housing): from the iso camera the spoiler lip hides most of the recess, and the bar alone read
    # as a thin dim line at night (E2E tesla-modely-tex-1024c night-N); by day the skin still shows the thin bar
    lit[..., 3] = np.where(np.isin(zone, ["LightLH", "LightRH"]) & ~lamp["head"], 0.4 * lit[..., 3], lit[..., 3])
    os.makedirs(TEX_DIR, exist_ok=True)
    # one full-colour skin per official paint, alpha 255 everywhere, so the engine's shrink to the player's "vehicle
    # texture size" cap (premultiplied alpha, TextureID.java:348-375, ImageData.java:291-297,468-482) keeps the colour.
    # Paint texels keep the high-poly light: rank of Tripo V x AO over all paint texels -> colour at that V quantile of
    # the official render's paint (official_ramp), divided by the in-game day gain
    key = vk[paint] * (0.5 + 0.5 * ao[paint])
    q = np.empty(key.size)
    q[np.argsort(key, kind="stable")] = (np.arange(key.size) + 0.5) / key.size
    hsvs = {}
    for pname, code in PAINTS:
        ramp = official_ramp(code)
        xp = (np.arange(len(ramp)) + 0.5) / len(ramp)
        a, b = (np.array(t, np.float32) for t in CAL[pname])
        tone = lambda c: np.clip(a * c / GAIN + b, 0, 1)                  # noqa: E731
        sk = base.copy()
        sk[paint, :3] = tone(np.stack([np.interp(q, xp, ramp[:, i]) for i in range(3)], -1))
        sk = sk.reshape(-1, 4)[src].reshape(sk.shape)
        save_png(downsample(sk, BAKE // SKIN), os.path.join(TEX_DIR, f"{NAME}_{pname}.png"), pname)
        # setColorHSV for the damage overlays: the shader gives Veh_Damage* texels the paint hue and S / V offsets
        # (vehicle_common.frag.glsl:6-15); their median S 0.03, V 0.45 should land on this skin's median paint
        h, s_, v_ = colorsys.rgb_to_hsv(*tone(ramp[len(ramp) // 2]))
        hsvs[pname] = [round(h, 3), round(min(1.0, s_ + 0.47), 3), round(min(1.0, v_ + 0.05), 3)]
    print("LUA colors", "\n".join(f'{{ name = "{p}", code = "{c}", h = {hsvs[p][0]}, s = {hsvs[p][1]}, v = {hsvs[p][2]} }},'
                                  for p, c in PAINTS))
    # mask / lights load with flag 256 too (BaseVehicle.java:595-615): 512 = the default cap (Core.java:266,3489-3495);
    # option 1 (256) shrinks them, harmless (mask alpha 255, lights RGB only matter where alpha is 1). The mask takes
    # each 8x8 block's centre texel (the 512 texel's own centre; the top-left one shifted every zone edge half a texel)
    f = BAKE // 512
    mask, lit = (a.reshape(-1, 4)[src].reshape(a.shape) for a in (mask, lit))
    zone = zone.ravel()[src].reshape(zone.shape)
    save_png(mask[f // 2::f, f // 2::f], os.path.join(TEX_DIR, NAME + "_mask.png"), "mask")
    save_png(downsample(lit, f), os.path.join(TEX_DIR, NAME + "_lights.png"), "lights")
    counts = {k: int((zone[f // 2::f, f // 2::f] == k).sum()) for k in Z}
    print("ZONES px", counts)
    print("PANES px", {k: int((pane[f // 2::f, f // 2::f] == k).sum()) for k in range(P_WS, P_BPIL + 1)})
    smooth_glass_normals(body, pane, fid, pos[..., 0])
    # centre the body bbox like vanilla (mesh centre == model offset == centerOfMassOffset)
    co = mesh_co(body)
    c = (co.min(0) + co.max(0)) / 2
    zmid = float(c[2])
    set_co(body, co - [0, c[1], zmid])
    wl = [(sx, yc - c[1], zc, xo) for sx, yc, zc, xo in info["wl"]]
    mat = bpy.data.materials.new(NAME)
    body.data.materials.clear()
    body.data.materials.append(mat)
    damage_uv1(body, face_zones(fid, mask, len(body.data.polygons)))   # before stage doors cuts them out of the body
    g = geometry(body, zmid, wl, info["wheel_r"])
    g |= {"tris_body": tris(body), "tris_wheel": info["wheel_tris"], "skin": SKIN, "skins": [p for p, _ in PAINTS],
          "scale": {k: info[k] for k in ("uniform_scale", "x_factor", "z_factor", "final_size", "official")}}
    json.dump(g, open(os.path.join(TMP, "geometry.json"), "w"), indent=1)
    print("GEOMETRY", json.dumps(g))
    # whole body (doors on) for stage doors, which exports the body FBX without them
    bpy.context.scene["info"] = json.dumps(info | {"centre_y": float(c[1]), "zmid": zmid})
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(TMP, "v2_final.blend"))
    previews(body, wl, zmid, info["wheel_r"])
    stage_doors()
    verify(n)

# ---------------------------------------------------------------- doors

# Vanilla layout (SportsCarWithDoors.fbx, ModernCarWithDoors_ez.fbx): one FBX, armature "VehicleSkeleton" (the root
# ImportedSkeleton.java:57-60 looks up), one bone "<Part>_bone" per door, one mesh per door weighted 1.0 to its bone
# ("<file>|<mesh>", ProcessedAiScene.java:97-124), one clip per door; the take name is cut at its first '|'
# (ImportedSkeleton.java:336-340), Blender writes "VehicleSkeleton|<action>". Skinned meshes carry pos, normal,
# weights, indices, UV0, UV1 (ImportedSkinnedMesh.java:74-82) = vehicle_multiuv_noreflect.vert's locations; the MOD's
# media/shaders/vehicle_multiuv.vert is the skinned twin vanilla lacks (ShaderProgram.java:278-281 asks for it when
# static = false and reflections are on, ModelManager.java:1298-1309). A part model draws with the parent car's skin,
# mask, damage and uninstall uniforms (Model.java:534-585), so the doors keep the body's UV0 / UV1 and textures.
# part: side (-1 = left, x < 0; 0 = tailgate), hinge axis, open angle (deg; sign swings the door out, the gate up),
# clip seconds. Hinge points come from the cut (front edge on the outer skin; the gate's top edge). The clips run
# open -> closed ("<Part>_closing", vanilla's naming; Open plays it reversed). updateAnimationPlayer advances the clip
# 0.8 x real time x rate (BaseVehicle.java:3901-3904): doors ~1 s, the gate ~4.5 s like an electric tailgate
DOORS = {
    "DoorFrontLeft": (-1, (0, 0, 1), -65, 0.8), "DoorFrontRight": (1, (0, 0, 1), 65, 0.8),
    "DoorRearLeft": (-1, (0, 0, 1), -65, 0.8), "DoorRearRight": (1, (0, 0, 1), 65, 0.8),
    "TrunkDoor": (0, (1, 0, 0), -75, 3.6),
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


def cut(V, T, A, L, n, d, pred):
    """Split the triangles whose centroid passes pred and that the plane n.p = d crosses, along the plane; neighbours
    sharing a split edge are split too (one more triangle each), so no T-junction opens a crack."""
    s = V @ np.asarray(n, float) - d
    s[np.abs(s) < 1e-7] = 0
    sg = np.sign(s)
    st = sg[T]
    todo = np.flatnonzero((st.max(1) > 0) & (st.min(1) < 0) & pred(V[T].mean(1)))
    pts, newv = {}, []
    for t in todo:
        for i in range(3):
            a, b = T[t, i], T[t, (i + 1) % 3]
            key = (min(a, b), max(a, b))
            if sg[a] * sg[b] < 0 and key not in pts:
                pts[key] = len(V) + len(newv)
                newv.append(V[a] + (V[b] - V[a]) * (s[a] / (s[a] - s[b])))
    if not pts:
        return V, T, A, L
    V = np.concatenate([V, np.array(newv)])
    keep, nt, na, nl = np.ones(len(T), bool), [], [], []
    ends = np.unique(np.array(list(pts)))
    for t in np.flatnonzero(np.isin(T, ends).sum(1) >= 2):
        hit = [i for i in range(3) if (min(T[t, i], T[t, (i + 1) % 3]), max(T[t, i], T[t, (i + 1) % 3])) in pts]
        if not hit:
            continue
        keep[t] = False
        poly = []                                        # (vertex, attributes) round the triangle with edge points
        for i in range(3):
            a, b = T[t, i], T[t, (i + 1) % 3]
            poly.append((a, A[t, i]))
            if i in hit:
                m = pts[(min(a, b), max(a, b))]
                f = np.linalg.norm(V[m] - V[a]) / np.linalg.norm(V[b] - V[a])
                poly.append((m, A[t, i] + (A[t, (i + 1) % 3] - A[t, i]) * f))
        if len(hit) == 1:                                # fan from the edge point
            j = next(k for k, (v, _) in enumerate(poly) if v not in T[t])
            tri = [(j, (j + 1) % 4, (j + 2) % 4), (j, (j + 2) % 4, (j + 3) % 4)]
        else:                                            # the lone corner (between both edge points) gets a triangle
            j = next(k for k in range(5) if poly[k][0] in T[t] and poly[(k + 1) % 5][0] not in T[t]
                     and poly[(k - 1) % 5][0] not in T[t])
            tri = [((j - 1) % 5, j, (j + 1) % 5), ((j + 1) % 5, (j + 2) % 5, (j + 3) % 5),
                   ((j + 1) % 5, (j + 3) % 5, (j - 1) % 5)]
        for q in tri:
            nt.append([poly[k][0] for k in q])
            na.append([poly[k][1] for k in q])
            nl.append(L[t])
    return (V, np.concatenate([T[keep], np.array(nt)]), np.concatenate([A[keep], np.array(na)]),
            np.concatenate([L[keep], np.array(nl, bool)]))


def door_cuts():
    """(plane normal, d, centroid predicate): the door / gate outlines that run across painted panels; the rest of the
    outline (A-line, roof edge) follows face centroids through black frit, seamless while closed."""
    ax = lambda c: np.abs(c[:, 0])                                   # noqa: E731
    b = np.array([0, 1, -B_PILLAR_WIN[2]])
    bn = np.linalg.norm(b)
    side = lambda c, lo=-9, hi=9: (ax(c) > 0.4) & (c[:, 2] > lo) & (c[:, 2] < hi)   # noqa: E731
    g = GATE
    return [((0, 1, 0), DOOR_FRONT_Y, lambda c: side(c, hi=0.97)),
            ((0, 1, 0), B_PILLAR_Y, lambda c: side(c, hi=BELT_Z + 0.03)),
            ((0, 1, 0), DOOR_REAR_Y, lambda c: side(c, hi=BELT_Z + 0.12)),
            (b / bn, (B_PILLAR_WIN[1] - B_PILLAR_WIN[2]) / bn, lambda c: side(c, lo=BELT_Z - 0.03)),
            ((0, 1, 0), B_PILLAR_WIN[0], lambda c: side(c, lo=BELT_Z - 0.03)),
            ((0, 1, 0), DIVIDER[0], lambda c: side(c, lo=BELT_Z - 0.03)),
            ((0, 0, 1), DOOR_SILL_Z, lambda c: side(c) & (c[:, 1] > DOOR_REAR_Y - 0.05) & (c[:, 1] < DOOR_FRONT_Y + 0.05)),
            ((0, 0, 1), g["z"], lambda c: c[:, 1] < g["y"]),
            ((1, 0, 0), g["x"], lambda c: (c[:, 1] < g["y"]) & (c[:, 2] > g["z"] - 0.05) & (c[:, 2] < g["top_z"] + 0.03)),
            ((1, 0, 0), -g["x"], lambda c: (c[:, 1] < g["y"]) & (c[:, 2] > g["z"] - 0.05) & (c[:, 2] < g["top_z"] + 0.03)),
            ((1, 0, 0), g["top_x"], lambda c: (c[:, 1] < RW_SEAM_Y + 0.05) & (c[:, 2] > g["top_z"] - 0.03)),
            ((1, 0, 0), -g["top_x"], lambda c: (c[:, 1] < RW_SEAM_Y + 0.05) & (c[:, 2] > g["top_z"] - 0.03)),
            ((0, 0, 1), g["top_z"], lambda c: (c[:, 1] < g["y"]) & (ax(c) > g["top_x"] - 0.03) & (ax(c) < g["x"] + 0.03)),
            ((0, 1, 0), RW_SEAM_Y, lambda c: (c[:, 2] > 1.1) & (ax(c) < g["top_x"] + 0.03))]


def door_pieces(tp, fn, zone, liner):
    """Piece per triangle (tp: its 3 corner points): 0 body, k = k-th DOORS entry. Below the belt the door panel by
    geometry (a superset of the mask's Door zones, which also need a side-facing texel), the window by its mask zone,
    the black frame only within FRIT (+1.5 cm) of that window (else the roof rail went with the door), the mirror (door
    mounted on the Model Y); the gate by its outline plus the Boot / rear glass / tail-bar zones."""
    cen = tp.mean(1)
    x, y, z = cen.T
    nx = fn[:, 0]
    zs, ys = zip(*DOOR_A_LINE)
    yfront = np.where(z < zs[0], DOOR_FRONT_Y, np.interp(z, zs, ys))
    bfront = B_PILLAR_WIN[1] + B_PILLAR_WIN[2] * (z - 1.0)
    frame = (zone == "Roof") & (z > BELT_Z - 0.03) & (z < DOOR_TOP_Z)
    panel = (z > DOOR_SILL_Z) & (z < BELT_Z + 0.1)
    g = GATE
    gx = np.where(z < g["top_z"], g["x"], g["top_x"])
    out = np.zeros(len(cen), np.int64)
    for k, (part, (sd, _, _, _)) in enumerate(DOORS.items(), 1):
        if sd:
            lr, out_side = ("L" if sd < 0 else "R"), sd * x > 0.4
            # door skin |x| >= 0.6 (the hood's rear corners and the cowl reach 0.55); above the belt only outward faces
            panel_s = panel & (sd * x > 0.55) & ((z < BELT_Z) | (sd * nx > 0.3))
            if part.startswith("DoorFront"):
                win = (zone == f"Win{lr}H") & out_side
                sel = win | (panel_s & (y <= DOOR_FRONT_Y) & (y > B_PILLAR_Y)) | mirror_head(cen)
                fr = frame & (y < yfront) & (y > bfront)
            else:
                win = (zone == f"Win{lr}T") & (y > DIVIDER[0]) & out_side
                sel = win | (panel_s & (y <= np.where(z < BELT_Z + 0.03, B_PILLAR_Y, B_PILLAR_WIN[0])) & (y >= DOOR_REAR_Y))
                fr = frame & (y < B_PILLAR_WIN[0]) & (y > DIVIDER[0])
            wp = tp[win].reshape(-1, 3)
            fr &= out_side
            for i in np.flatnonzero(fr):
                fr[i] = ((wp - cen[i]) ** 2).sum(1).min() < (FRIT + 0.015) ** 2
            sel = (sel | fr) & out_side
        else:
            geo = (z > g["z"]) & (np.abs(x) < gx) & (np.abs(nx) < 0.7)
            sel = (geo & ((y < g["y"]) | ((z > g["top_z"]) & (y < RW_SEAM_Y)))) | np.isin(zone, ["Boot", "WinH"])
            sel |= np.isin(zone, ["LightLT", "LightRT"]) & (y < g["y"])
        out[sel & ~liner & (out == 0)] = k
    return drop_specks(tp, out)


def drop_specks(tp, piece, min_faces=25):
    """Pieces keep only their edge-connected parts of at least min_faces triangles (frit-band and outline tests leave
    loose triangles on the roof rail and the C pillars, which flew off with the door, E2E tesla-doors-1024a). The
    mirror is its own part of the front door (100+ triangles) and stays."""
    key = np.round(tp * 1e5).astype(np.int64)              # shared corners have identical coordinates
    _, vid = np.unique(key.reshape(-1, 3), axis=0, return_inverse=True)
    vid = vid.reshape(-1, 3)
    for k in range(1, piece.max() + 1):
        idx = np.flatnonzero(piece == k)
        e = np.sort(np.concatenate([vid[idx][:, [0, 1]], vid[idx][:, [1, 2]], vid[idx][:, [2, 0]]]), 1)
        f = np.tile(np.arange(len(idx)), 3)
        o = np.lexsort((e[:, 1], e[:, 0]))
        e, f = e[o], f[o]
        par = np.arange(len(idx))

        def root(a):
            while par[a] != a:
                par[a] = par[par[a]]
                a = par[a]
            return a
        for a, b in zip(f[:-1][np.all(e[1:] == e[:-1], 1)], f[1:][np.all(e[1:] == e[:-1], 1)]):
            par[root(a)] = root(b)
        lab = np.array([root(a) for a in range(len(idx))])
        _, inv, cnt = np.unique(lab, return_inverse=True, return_counts=True)
        piece[idx[cnt[inv] < min_faces]] = 0
    return piece


def slab(V, T, A, sel, off, liner_attr, outer_extra=None):
    """Door piece: its outer faces, an inner panel DOOR_T in along off (liner black, normals in) and edge strips that
    close the slab (each takes the colour just inside its outer edge). outer_extra: faces with no inner panel (the
    mirror). Returns points, tris, attributes and the boundary edges (directed as in the piece) for the body's jamb."""
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
    fa = frame_black(pull_in(ea[bnd], att.mean(1)[np.tile(np.arange(len(tri)), 3)[bnd]]), V[a], V[b], liner_attr)
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


def frame_black(edge_attr, pa, pb, liner_attr):
    """Strips along an edge above the belt are black (window frames and their seals): there the outline runs through
    frit and roof-rail triangles, and their colours made a red-and-black comb along the door top (tesla-doors-1024a)."""
    out = edge_attr.copy()
    up = (pa[:, 2] > BELT_Z + 0.02) & (pb[:, 2] > BELT_Z + 0.02)
    out[up, :, :4] = liner_attr[:4]
    return out


def jamb(V, T, A, edges, body_edges, off, liner_attr):
    """Body side of a door opening: a strip from each boundary edge the body shares (piece direction a -> b; the body
    face runs b -> a) JAMB_T in along off, facing into the opening, coloured like the body face at that edge."""
    rows = [(k, *body_edges[(b, a)]) for k, (a, b) in enumerate(edges) if (b, a) in body_edges]
    k, u, i = (np.array(c, np.int64) for c in zip(*rows))
    a, b = edges[k, 0], edges[k, 1]
    ea = frame_black(pull_in(np.stack([A[u, (i + 1) % 3], A[u, i]], 1), A[u].mean(1)), V[a], V[b], liner_attr)
    base = len(V)
    newv = np.concatenate([V[a] + off, V[b] + off])
    ia, ib = base + np.arange(len(a)), base + len(a) + np.arange(len(a))
    st = np.concatenate([np.stack([a, b, ib], 1), np.stack([a, ib, ia], 1)])
    sa = np.concatenate([np.stack([ea[:, 0], ea[:, 1], ea[:, 1]], 1), np.stack([ea[:, 0], ea[:, 1], ea[:, 0]], 1)])
    P = np.concatenate([V, newv])
    nrm = np.cross(P[st[:, 1]] - P[st[:, 0]], P[st[:, 2]] - P[st[:, 0]])
    sa[..., 4:] = (nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12))[:, None]
    return newv, st, sa


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


def stage_doors():
    """v2_final.blend (whole body) -> body FBX without doors / tailgate (+ jambs), doors FBX (skinned, clips),
    prev/doors_*.png. The cut planes follow the panel lines, so closed doors overlay the old surface exactly."""
    bpy.ops.wm.open_mainfile(filepath=os.path.join(TMP, "v2_final.blend"))
    info = json.loads(bpy.context.scene["info"])
    shift = np.array([0, info["centre_y"], info["zmid"]])
    body = bpy.data.objects[NAME]
    mat = body.data.materials[0]
    V, T, A, L = soup(body, shift)
    for n, d, pred in door_cuts():
        V, T, A, L = cut(V, T, A, L, n, d, pred)
    m = img_np(bpy.data.images.load(os.path.join(TEX_DIR, NAME + "_mask.png")))       # rows from v = 0
    names = {tuple(np.round(np.array(c) * 255).astype(int)): k for k, c in Z.items()}
    uv = A[:, :, :2].mean(1)
    px = m[np.clip((uv[:, 1] * 512).astype(int), 0, 511), np.clip((uv[:, 0] * 512).astype(int), 0, 511), :3]
    zone = np.array([names.get(tuple(p), "Roof") for p in np.round(px * 255).astype(int)], dtype=object)
    cen = V[T].mean(1)
    fn = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    piece = door_pieces(V[T], fn, zone, L)
    liner_attr = A[L][0].mean(0) if L.any() else A[0, 0]       # one liner face: near black, mask Roof
    conv = np.array(Matrix.Rotation(-math.pi / 2, 3, "X"))   # Blender Z-up -> FBX Y-up (what axis_forward -Z does)
    body_t, body_a, bodyV = [T[piece == 0]], [A[piece == 0]], V
    body_edges = {(tr[i], tr[(i + 1) % 3]): (u, i) for u in np.flatnonzero(piece == 0) for tr in (T[u],)
                  for i in range(3)}
    meshes, hinges = [], {}
    mir = mirror_head(cen)
    for k, (part, (sd, axis, ang, secs)) in enumerate(DOORS.items(), 1):
        sel = piece == k
        off = (np.array([-sd, 0, 0]) if sd else np.array(GATE_IN)) * DOOR_T
        P, t, a, edges = slab(V, T, A, sel & ~mir, off, liner_attr, outer_extra=sel & mir)
        newv, jt, ja = jamb(bodyV, T, A, edges, body_edges, off / DOOR_T * JAMB_T, liner_attr)
        bodyV = np.concatenate([bodyV, newv])
        body_t.append(jt)
        body_a.append(ja)
        dv = V[np.unique(T[sel])]
        if sd:      # front edge on the outer skin, below the belt
            low = dv[dv[:, 2] < BELT_Z]
            yh = low[:, 1].max()
            near = low[low[:, 1] > yh - 0.05]
            h = np.array([sd * (sd * near[:, 0]).max(), yh, 0.0])
        else:       # top edge of the gate
            h = np.array([0.0, dv[:, 1].max(), dv[:, 2].max()])
        hinges[part] = h - shift
        meshes.append((part, P - shift, t, a))
        print(f"DOOR {part}: {int(sel.sum())} outer tris, {len(t)} total, hinge {np.round(h, 3).tolist()}")
    print(f"DOOR body {int((piece == 0).sum())} + jamb {sum(len(j) for j in body_t[1:])} tris (was {len(T)} after cuts)")
    # body FBX (same export as the whole body had)
    bpy.data.objects.remove(body)
    cut_body = soup_object(NAME, bodyV - shift, np.concatenate(body_t), np.concatenate(body_a), mat)
    export_fbx(cut_body, os.path.join(VEH_DIR, NAME + ".fbx"))
    # doors: everything built in FBX space (Y up) and exported with identity axes; FBX's bake_space_transform is
    # unsafe with armatures (Blender's own warning)
    arm = bpy.data.objects.new("VehicleSkeleton", bpy.data.armatures.new("VehicleSkeleton"))
    bpy.context.scene.collection.objects.link(arm)
    select_only(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    for part, (_, axis, _, _) in DOORS.items():
        eb = arm.data.edit_bones.new(part + "_bone")      # bone Y = hinge axis: open = rotation about local Y
        eb.head = Vector(conv @ hinges[part])
        eb.tail = Vector(conv @ (hinges[part] + np.array(axis) * 0.3))
    bpy.ops.object.mode_set(mode="OBJECT")
    obs = [arm]
    for part, P, t, a in meshes:
        Pf = P @ conv.T
        af = a.copy()
        af[..., 4:] = a[..., 4:] @ conv.T
        ob = soup_object(part, Pf, t, af, mat)
        vg = ob.vertex_groups.new(name=part + "_bone")
        vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
        ob.parent = arm
        ob.modifiers.new("arm", "ARMATURE").object = arm
        obs.append(ob)
    sc = bpy.context.scene
    sc.render.fps = CLIP_FPS
    ad = arm.animation_data_create()
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    end = 1
    for part, (_, _, ang, secs) in DOORS.items():
        act = bpy.data.actions.new(part + "_closing")
        act.use_fake_user = True
        ad.action = act
        last = 1 + round(secs * CLIP_FPS)
        end = max(end, last)
        for fr, deg in ((1, ang), (last, 0)):        # every bone keyed: the other doors stay shut in this take
            for pb in arm.pose.bones:
                pb.rotation_quaternion = Quaternion((0, 1, 0), math.radians(deg if pb.name == part + "_bone" else 0))
                pb.keyframe_insert("rotation_quaternion", frame=fr)
        act.frame_range = (1, last)
    ad.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
    sc.frame_start, sc.frame_end = 1, end
    select_only(*obs)
    bpy.ops.export_scene.fbx(filepath=os.path.join(VEH_DIR, DOORS_FBX + ".fbx"), use_selection=True,
                             object_types={"ARMATURE", "MESH"}, apply_scale_options="FBX_SCALE_UNITS",
                             bake_space_transform=False, axis_forward="Y", axis_up="Z", mesh_smooth_type="OFF",
                             add_leaf_bones=False, primary_bone_axis="Y", secondary_bone_axis="X",
                             armature_nodetype="NULL", bake_anim=True, bake_anim_use_all_bones=True,
                             bake_anim_use_nla_strips=False, bake_anim_use_all_actions=True,
                             bake_anim_force_startend_keying=True, bake_anim_step=1.0, bake_anim_simplify_factor=0.0,
                             path_mode="STRIP")
    door_previews(cut_body, arm, obs[1:])


def door_previews(body, arm, doors):
    """prev/doors_<pose>_<view>.png: Ultra Red skin on the cut body and the doors, shut and open (each door's clip at
    its first frame). Doors are in FBX space: shown through the armature's inverse axis turn."""
    arm.matrix_world = Matrix.Rotation(math.pi / 2, 4, "X")
    mat = body.data.materials[0]
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = bpy.data.images.load(os.path.join(TEX_DIR, f"{NAME}_UltraRed.png"))
    mat.node_tree.links.new(node.outputs[0], mat.node_tree.nodes["Principled BSDF"].inputs[0])
    for o in bpy.data.objects:
        o.hide_render = o.type != "MESH" or not (o is body or o in doors)
    views = {"iso": Vector((-1, 1, 1.15)), "iso_rear": Vector((1, -1, 1.15)), "left": Vector((-1, 0, 0))}
    preview.render_views(os.path.join(PREV, "doors_shut"), ortho=5.0, center=Vector((0, 0, 0)), res=(1600, 900), views=views)
    for pb in arm.pose.bones:
        part = pb.name[:-5]
        pb.rotation_quaternion = Quaternion((0, 1, 0), math.radians(DOORS[part][2]))
    bpy.context.view_layer.update()
    preview.render_views(os.path.join(PREV, "doors_open"), ortho=5.0, center=Vector((0, 0, 0)), res=(1600, 900), views=views)



# ---------------------------------------------------------------- script numbers, previews, verify

S = 1.82              # vehicle scale (R5 3), model script scale = 1/S
OY = 0.1978           # model offset == centerOfMassOffset (unscaled), ModernCar convention
WHEEL_LIFT = 0.11     # rendered wheel sits this much (grid) above its script offset at rest: vanilla arch centres
#                       minus wheel offsets, ModernCar +0.10/+0.16, SUV +0.12/+0.10 (arch circle fit); calibration knob
WHEEL_INSET = 0.03    # tire outer face inside the measured Tripo tire (v1 E2E: flush tires looked proud of the arch)
PORT = (-1.74, 0.865)  # charge port (mesh y, ground z, grid): inside the side end of the left tail light (real Model Y);
#                        the red lens there spans y -1.72..-1.76, z 0.83-0.90 (bake texels R > 1.8 G, |nx| > 0.45)


def f4(*v):
    return " ".join(f"{x:.4f}" for x in v)


def geometry(body, zmid, wl, r):
    """Vehicle script geometry block. Mesh (x,y,z rel. mesh centre) -> script (-x, z, y) / S."""
    from mathutils.bvhtree import BVHTree
    co = mesh_co(body)
    me = body.data
    liner = np.array([d.value for d in me.attributes["liner"].data], bool)
    bc = co[sorted({i for k, p in enumerate(me.polygons) if not liner[k] for i in p.vertices})]
    w_body = 2 * np.abs(bc[bc[:, 2] < 0.55 * H - zmid][:, 0]).max()
    hgt, ln = bc[:, 2].max() - bc[:, 2].min(), np.ptp(bc[:, 1])
    ext = (w_body / S, hgt / S, ln / S)
    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    hit = bvh.ray_cast(Vector((-3, PORT[0], PORT[1] - zmid)), Vector((1, 0, 0)))[0]
    port = (-hit.x / S, (PORT[1] - zmid) / S, PORT[0] / S)
    belt = BELT_Z - zmid
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
                f"            offset = {f4(-sxn * (xo - TIRE_W / 2 - WHEEL_INSET) / S, (zc - zmid - WHEEL_LIFT) / S, yc / S)},",
                f"            radius = {(r - 0.015) / S:.4f},", f"            width = {TIRE_W:.4f},", "        }"]
    out += ["        part Tire*", "        {", "            model InflatedTirePlusWheel", "            {",
            f"                file = {NAME}_Wheel,", "            }", "        }"]
    seat_y, ground = (0.56 - zmid) / S, -zmid / S
    fz, rz = (DOOR_FRONT_Y + B_PILLAR_Y) / 2 - 0.12, (B_PILLAR_Y + DOOR_REAR_Y) / 2 - 0.08
    seats = (("FrontLeft", 1, fz, (DOOR_FRONT_Y, B_PILLAR_Y)), ("FrontRight", -1, fz, (DOOR_FRONT_Y, B_PILLAR_Y)),
             ("RearLeft", 1, rz, (B_PILLAR_Y, DOOR_REAR_Y)), ("RearRight", -1, rz, (B_PILLAR_Y, DOOR_REAR_Y)))
    for nm, side, z, door in seats:
        out += [f"        passenger {nm}", "        {", "            position inside", "            {",
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
    # animated doors (stage doors): the clip runs open -> closed, so Open plays it reversed, Closed holds its end
    # (reversed, not animated) and Opened its start (vanilla vehicle_car_sports_ez.txt layout); ISOpenVehicleDoor /
    # ISCloseVehicleDoor play Open / Close, a new model instance holds Opened / Closed (BaseVehicle.java:3926-3930)
    for part in DOORS:
        clip = part + "_closing"
        out += [f"        part {part}", "        {", "            model Default", "            {",
                f"                file = {NAME}_{part},", "            }"]
        for anim, rev, live in (("Close", False, True), ("Open", True, True), ("Closed", True, False),
                                ("Opened", False, False)):
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
    return {"zmid_ground": zmid, "body_width": w_body, "body_height": hgt, "length": ln, "port_mesh": [hit.x, PORT[0], PORT[1]],
            "wheelbase": wl[0][1] - wl[2][1], "wheel_radius": r}


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


def previews(body, wl, zmid, r):
    wheel = bpy.data.objects[NAME + "_Wheel"]
    wimg = bpy.data.images.load(os.path.join(TEX_DIR, NAME + "_wheel.png"))
    wm = bpy.data.materials.new("prev_wheel")
    wm.use_nodes = True
    wn = wm.node_tree.nodes.new("ShaderNodeTexImage")
    wn.image = wimg
    wm.node_tree.links.new(wn.outputs[0], wm.node_tree.nodes["Principled BSDF"].inputs[0])
    for sx, yc, zc, xo in wl:
        w = dup(wheel, "w")
        w.data.materials.clear()
        w.data.materials.append(wm)
        w.location = (sx * (xo - TIRE_W / 2 - WHEEL_INSET), yc, zc - zmid)
    for o in bpy.data.objects:
        o.hide_render = not (o is body or o.name.startswith("w."))
    mat = body.data.materials[0]
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    mat.node_tree.links.new(node.outputs[0], mat.node_tree.nodes["Principled BSDF"].inputs[0])
    mat.node_tree.nodes.active = node
    iso = {"iso": Vector((-1, 1, 1.15)), "iso_rear": Vector((1, -1, 1.15))}
    for pname, _ in PAINTS:
        node.image = bpy.data.images.load(os.path.join(TEX_DIR, f"{NAME}_{pname}.png"))
        more = {"left": Vector((-1, 0, 0)), "front": Vector((0, 1, 0.3))} if pname in ("StealthGrey", "UltraRed") else {}
        preview.render_views(os.path.join(PREV, pname), ortho=4.4, center=Vector((0, 0, 0)), res=(1600, 800),
                             views=iso | more)
    node.image = bpy.data.images.load(os.path.join(TEX_DIR, NAME + "_mask.png"))
    preview.render_views(os.path.join(PREV, "mask"), ortho=4.4, center=Vector((0, 0, 0)), res=(1600, 800),
                         views={"iso": Vector((-1, 1, 1.15)), "iso_rear": Vector((1, -1, 1.15))})


def verify(n):
    lines = []
    for p in (os.path.join(VEH_DIR, NAME + ".fbx"), os.path.join(VEH_DIR, NAME + "_Wheel.fbx"),
              os.path.join(VEH_DIR, DOORS_FBX + ".fbx")):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=p)
        for o in bpy.data.objects:
            if o.type == "ARMATURE":
                lines += [f"{os.path.basename(p)} bone {b.name}: head={np.round(b.head_local, 3).tolist()} "
                          f"axis={np.round((b.tail_local - b.head_local).normalized(), 3).tolist()}" for b in o.data.bones]
            if o.type != "MESH":
                continue
            me = o.data
            co = np.array([(o.matrix_world @ v.co)[:] for v in me.vertices])
            uvs = []
            for u in me.uv_layers:
                a = np.empty(len(me.loops) * 2)
                u.data.foreach_get("uv", a)
                uvs.append(f"{u.name}[{a.min():.3f},{a.max():.3f}]")
            lines.append(f"{os.path.basename(p)} {o.name}: tris={tris(o)} verts={len(me.vertices)} uv={' '.join(uvs)} "
                         f"size={np.round(np.ptp(co, 0), 3).tolist()} groups={[g.name for g in o.vertex_groups]}")
        lines += [f"{os.path.basename(p)} take {a.name}: frames {tuple(a.frame_range)}" for a in bpy.data.actions]
    m = np.round(img_np(bpy.data.images.load(os.path.join(TEX_DIR, NAME + "_mask.png")))[..., :3] * 255)
    allowed = np.array([np.round(np.array(c) * 255) for c in Z.values()])
    flat = m.reshape(-1, 3)[::5]
    bad = int((np.abs(flat[:, None, :] - allowed[None]).sum(-1).min(1) > 0).sum())
    lines.append(f"mask pixels outside the 27 zone colours (1/5 sample): {bad}")
    open(os.path.join(TMP, "verify.txt"), "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    st = args[0] if args else ""
    if st == "prep":
        stage_prep()
    elif st == "tiers":
        stage_tiers([int(x) for x in args[1].split(",")])
    elif st == "wheel":
        stage_wheel()
    elif st == "official":
        stage_official()
    elif st == "final":
        stage_final(int(args[1]))
    elif st == "doors":
        stage_doors()
        verify(0)
    else:
        print(__doc__)
