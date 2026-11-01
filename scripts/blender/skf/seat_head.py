"""Seated passengers against the car, every seat of every car (offline): heads, hair and hats against the shell; the
body against its own seat; the feet against the cabin floor; the legs against the rest of the cabin.

    B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
    "$B" -b --factory-startup --python scripts/blender/skf/seat_head.py -- [car ...] [--json out.json] [--sweep]
        [--vanilla-pose]
    cars: ModelY Model3 ModelS ModelX Cybertruck (default: all); vanilla CarNormal ModernCar SportsCar always (baseline).
    --sweep: for a red seat, how many mm lower it has to go for the head set (and the legs there).
    --vanilla-pose: every Tesla seat in vanilla Bob_IdleDriving instead of the MOD's clips (the state before them).
    SHIFT="Model3/Rear:dy:dz ..." (env): what-if, those passengers moved (grid) before a rebuild; DIAG: see the code.
Exit 1 when a Tesla seat shows the head, a cap or helmet in COMMON, or a hairstyle that clears vanilla ModernCar's
driver (ModernCar does not fit mohawks, liberty spikes or the tall hats in TALL either; those may clip), or when sit /
back / feet / knees leave FIT (README: the knowledge base's seating.md "坐姿與車頂").

How a passenger is drawn (pz/ = decompiled 42.21.0): the seat's clip (vanilla Bob_IdleDriving, player-vehicle idle;
Tesla seats the MOD's clips, scripts/seat_anim.py CLIPS) puts the pelvis at the model origin; it is placed at the
seat's `position inside` offset (x vehicle scale, VehicleScript.java:498, plus the model offset, BaseVehicle.java:
1908-1911), turned 180 deg and scaled 1.5 (Model.java:214-226). Static hats ride the Bip01_Head model transform x their
.X frame matrix (AnimatedModel.java:1446-1489). The car is the body + doors FBX (doors at rest = closed) minus cabin
faces (UV1 u < -1.25: seats, dash, door cards); vanilla cars: the whole mesh (vanilla never draws passengers:
showPassenger is false unless a script sets it, so they are a geometry baseline only).
For every vertex P of a set: clearance = (where the ray from Bip01_Spine1 through P leaves the shell) - |P - spine|;
negative = P is outside the shell = drawn over the roof / pillar / glass. Printed in mm (k 0.826 grid per metre).
legs: calf and foot vertices the same way. sit / back / feet / knees: fit() (the cabin's closed parts by UV1 cell).
"""
import bpy, glob, json, os, re, sys
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "common"))
import vanilla  # noqa: E402
from xanim import articulate, pose, read_anim, read_x, skin  # noqa: E402
sys.path.insert(0, os.path.join(HERE, "..", ".."))
import seat_anim  # noqa: E402  (the MOD's seated clips: CLIPS, written by scripts/seat_anim.py)

PZ = vanilla.PZ
M = os.path.normpath(os.path.join(HERE, "..", "..", "..", "MOD", "MinidoracatTeslaFor42", "Contents", "mods",
                                  "MinidoracatTeslaFor42", "42", "media"))
K, CHAR_SCALE = 0.826, 1.5
TESLA = ("ModelY", "Model3", "ModelS", "ModelX", "Cybertruck")
VANILLA = {"ModernCar": "vehicle_car_modern", "CarNormal": "vehicle_car_normal", "SportsCar": "vehicle_car_sports"}
VANILLA_ANIM = f"{PZ}/anims_X/Bob/Bob_IdleDriving.x"
FRONT, REAR = "MinidoracatTesla_IdleDrivingRecline", "MinidoracatTesla_IdleDrivingRear"
UPPER = ("Bip01_Head", "Bip01_Neck", "Bip01_HeadNub")          # body vertices whose main bone is one of these
HEAD_LOCS = {"hat", "fullhat", "fullsuithead", "jackethat", "jackethat_bulky", "sweaterhat", "maskfull", "mask"}
CAP = "Hat_BaseballCap"
COMMON = (CAP, "Hat_HardHat", "Hat_Fireman", "Hat_CrashHelmet", "Hat_CrashHelmetFULL", "Hat_Army", "Hat_RiotHelmet",
          "Hat_FootballHelmet")   # caps and helmets that have to fit (2026-11-01 Main / user: tall hats may clip)
TALL = ("Hat_Stovepipe", "Hat_Spiffo", "Hat_DeerHeadress", "Hat_TinFoilHat", "Hat_BunnyEarsBlack", "Hat_Wizard")
# sit / back / feet limits, mm (min over both bodies >= lo, max <= hi; negative = into the seat / under the floor).
# 25 mm is about 3 px at the closest zoom (the user's screenshot user-1104-seat-body.png: about 135 px a grid); the
# backs that showed sunk into the seat there measured -78..-20 (Model S driver, 2026-11-01). A gap shows as daylight: sit and back
# allow less of it than of sinking (clothes sit 5-15 mm off the body and fill some).
FIT = {"sit": (-25, 10), "back": (-25, 20), "feet": (-25, 25), "knees": (-25, float("inf"))}
CELLS = ("floor", "liner", "seat", "base", "dash", "trim", "console", "wheel")   # pzveh.py CABIN_CELLS (the first 8)
CABIN_UV1_U = -2.5                                                                # pzveh.py CABIN_UV1_U
PARTS = ("seat", "base", "dash", "console", "wheel")   # closed cabin parts (cabin.py part() / the wheel's torus)


_MODELS = {}


def model_path(rel):
    if not _MODELS:
        for p in glob.glob(f"{PZ}/models_X/**/*.[xX]", recursive=True):
            _MODELS[os.path.relpath(p, f"{PZ}/models_X")[:-2].replace("\\", "/").lower()] = p
    rel = re.sub(r"^media/models_x/|\.x$", "", rel.replace("\\", "/").lower())
    return _MODELS.get(rel)


# ---- character sets in .X model space (posed): {name: vertices}
def character(clip):
    """clip: a seat_anim.CLIPS name, None = vanilla Bob_IdleDriving"""
    anim = read_anim(VANILLA_ANIM)
    G = pose(anim)
    if clip:
        G = articulate(anim[0], G, seat_anim.CLIPS[clip])
    sets = {}
    for b in ("MaleBody", "FemaleBody"):
        V, sw, _ = read_x(f"{PZ}/models_X/Skinned/{b}.x")
        P = skin(V, sw, G)
        wmax, main = np.zeros(len(V)), np.full(len(V), "", object)
        for bone, (idx, w, _) in sw.items():
            up = w > wmax[idx]
            wmax[idx[up]], main[idx[up]] = w[up], bone
        sets[f"body:{b}"] = P[np.isin(main, UPPER)]
        sets[f"legs:{b}"] = P[np.array([m.startswith(("Bip01_L_Calf", "Bip01_R_Calf", "Bip01_L_Foot", "Bip01_R_Foot",
                                                       "Bip01_L_Toe", "Bip01_R_Toe")) for m in main])]
        sets[f"butt:{b}"] = P[np.isin(main, ("Bip01_Pelvis", "Bip01_L_Thigh", "Bip01_R_Thigh"))]
        sets[f"back:{b}"] = P[np.isin(main, ("Bip01_Spine", "Bip01_Spine1", "Bip01_L_Clavicle", "Bip01_R_Clavicle",
                                             "Bip01_BackPack", "Bip01_DressBack", "Bip01_DressBack02"))]
        sets[f"feet:{b}"] = P[np.isin(main, ("Bip01_L_Foot", "Bip01_R_Foot"))]
    neck = G["Bip01_Neck"][3, 1]                     # hair and hats: what is above the neck (suits and long hair hang lower)
    for p in sorted(glob.glob(f"{PZ}/models_X/Skinned/Hair/*.x")):
        V, sw, _ = read_x(p)
        P = skin(V, sw, G)
        sets[f"hair:{os.path.basename(p)[:-2]}"] = P[P[:, 1] > neck]
    # head clothing: item scripts with a head BodyLocation -> ClothingItem XML -> male / female model
    items = {}
    for p in glob.glob(f"{PZ}/scripts/**/*.txt", recursive=True):
        t = open(p, encoding="utf-8", errors="ignore").read()
        for m in re.finditer(r"\n\s*item (\w+)\s*\{(.*?)\n\s*\}", t, re.S):
            loc = re.search(r"BodyLocation\s*=\s*(?:\w+:)?(\w+)", m[2])
            ci = re.search(r"ClothingItem\s*=\s*(\w+)", m[2])
            if loc and ci and loc[1].lower() in HEAD_LOCS:
                items.setdefault(ci[1], m[1])
    hats, missing = {}, []
    for ci in sorted(items):
        x = f"{PZ}/clothing/clothingItems/{ci}.xml"
        if not os.path.exists(x):
            missing.append(ci)
            continue
        t = open(x, encoding="utf-8-sig", errors="ignore").read()
        static = "<m_Static>true" in t
        bone = (re.search(r"<m_AttachBone>(\w+)", t) or [None, "Bip01_Head"])[1]
        for sex in ("Male", "Female"):
            rel = (re.search(rf"<m_{sex}Model>([^<]+)", t) or [None, ""])[1].strip()
            path = rel and model_path(rel)
            if not path:
                missing.append(f"{ci}:{sex}:{rel}") if rel else None
                continue
            V, sw, F = read_x(path)
            P = skin(V, sw, G) if sw and not static else (np.c_[V, np.ones(len(V))] @ F @ G[bone])[:, :3]
            hats[f"hat:{ci}:{sex[0]}"] = P[P[:, 1] > neck]
    return G, sets, hats, items, missing


# ---- cars: shell BVH and seats in mesh coordinates (grid units: +Y front, +Z up, -X left)
def script_seats(path):
    t = open(path, encoding="utf-8", errors="ignore").read()
    seats = []
    for m in re.finditer(r"passenger (\w+)\s*\{.*?position inside\s*\{\s*offset\s*=\s*([-\d. ]+),", t, re.S):
        sx, sy, sz = map(float, m[2].split())
        seats.append((m[1], np.array([sx, sy, sz])))
    scale = float(re.search(r"model\s*\{[^}]*?scale\s*=\s*([\d.]+)", t, re.S)[1])
    return seats, scale


def shell_tesla(car):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    name = f"MinidoracatTesla_{car}"
    for f in (name, name + "_Doors"):
        bpy.ops.import_scene.fbx(filepath=f"{M}/models_X/vehicles/{f}.fbx")
    for o in bpy.data.objects:
        if o.type == "ARMATURE":
            o.data.pose_position = "REST"
    dg = bpy.context.evaluated_depsgraph_get()
    tris, cab, seat, floor = [], [], [], []
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        co = np.array([o.matrix_world @ v.co for v in me.vertices])
        if o.parent and o.parent.type == "ARMATURE":   # door pieces sit in the bone frame (Y up) at rest (texel_audit.py)
            co = np.c_[co[:, 0], -co[:, 2], co[:, 1]]
        lt = np.array([t.loops[:] for t in me.loop_triangles])
        lv = np.array([lp.vertex_index for lp in me.loops])
        u = np.empty(len(me.loops) * 2)
        me.uv_layers[1].data.foreach_get("uv", u)
        u = u.reshape(-1, 2)[lt][:, 0, 0]
        keep = u >= -1.25                                       # cabin faces (seats, dash, door cards) are not the shell
        tris.append(co[lv[lt[keep]]])
        cab.append(co[lv[lt[~keep]]])
        cell = np.round(CABIN_UV1_U - u).astype(int)          # cabin.py cell_object / UV1: u = CABIN_UV1_U - cell
        for c in PARTS:                                       # closed parts the legs may run into
            idx = lv[lt[~keep & (cell == CELLS.index(c))]]
            if len(idx):
                seat.extend((c, p) for p in components(co, idx))
        floor.append(co[lv[lt[~keep & (cell == CELLS.index("floor"))]]])
    return (np.concatenate(tris), np.concatenate(cab), *script_seats(f"{M}/scripts/vehicles/{name}.txt"),
            dict(parts=seat, floor=np.concatenate(floor)))


def components(co, idx):
    """closed cabin parts (cabin.py part(): one rounded box each on its own vertices; the wheel's torus) -> [triangles
    (n,3,3)]; open pieces (door cards, flat-shaded strips on split vertices) are left out: no inside to measure"""
    root = {}

    def find(a):
        while root.setdefault(a, a) != a:
            root[a] = root[root[a]]
            a = root[a]
        return a
    for a, b, c in idx:
        root[find(b)] = find(a)
        root[find(c)] = find(a)
    lab = np.array([find(t[0]) for t in idx])
    out = []
    for k in np.unique(lab):
        f = idx[lab == k]
        e = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), 1)
        if len(f) >= 12 and (np.unique(e, axis=0, return_counts=True)[1] == 2).all():   # every edge on two faces
            out.append(co[f])
    return out


def shell_vanilla(car):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ob = vanilla.load(f"Vehicles_{car}", uv=False)
    me = ob.data
    me.calc_loop_triangles()
    co = np.array([v.co for v in me.vertices])
    tris = co[np.array([t.vertices[:] for t in me.loop_triangles])]
    return tris, tris, *script_seats(f"{PZ}/scripts/generated/vehicles/{VANILLA[car]}.txt"), None


def bvh(tris):
    return BVHTree.FromPolygons([Vector(v) for v in tris.reshape(-1, 3)], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(tris))])


def place(P, seat, scale, drop=0.0):
    """.X model-space vertices -> car mesh coordinates (see the docstring); drop: mm lower than the script seat"""
    sx, sy, sz = seat * scale
    sy -= drop / 1000 * K
    return np.c_[-sx - CHAR_SCALE * P[:, 0], sz - CHAR_SCALE * P[:, 2], sy + CHAR_SCALE * P[:, 1]]


def exit_hit(tree, a, d, far):
    """first face the ray leaves the shell through (normal along the ray): skips the inner side of a double shell
    (vanilla headliners, our reversed liner copies and two-sided glass) and vanilla's seats; (point, normal, dist)"""
    o, gone = a, 0.0
    for _ in range(64):
        p, n, _, t = tree.ray_cast(o, d, far - gone)
        if p is None:
            return None
        if n.dot(d) > 0:
            return p, n, gone + t
        gone += t + 1e-4
        o = p + d * 1e-4
    return None


def clearance(tree, A, P, diag=None):
    """min over P of (shell exit distance along spine->P) - |P - spine|, in mm; +inf when no ray meets the shell"""
    best, worst = np.inf, None
    a = Vector(A)
    for p in P:
        d = Vector(p) - a
        L = d.length
        hit = exit_hit(tree, a, d.normalized(), L + 0.5)
        if hit and hit[2] - L < best:
            best, worst = hit[2] - L, (p, hit[0], hit[1])
    if diag and worst:
        print("DIAG", diag, "spine", np.round(A, 3), "vertex", np.round(worst[0], 3), "hit", np.round(worst[1], 3),
              "normal", np.round(worst[2], 2))
    return best / K * 1000


def signed(tree, P):
    """mm, min over P of the distance to a closed part's surface, negative inside it (by the depth). Inside = the first
    face straight up is seen from behind (the nearest face's normal alone flips at the rounded boxes' edges)"""
    best, up = np.inf, Vector((0, 0, 1))
    for p in P:
        p = Vector(p)
        d = tree.find_nearest(p)[3]
        h = tree.ray_cast(p, up)
        best = min(best, -d if h[0] is not None and h[1].dot(up) > 0 else d)
    return best / K * 1000


def along(tree, P, d):
    """mm, min over P of how far each vertex sits off the part's surface along d: inside (the first face along d seen
    from behind) -> minus the way out along d (a cushion's 9 cm: the nearest face would be its underside); outside ->
    the gap back along -d to the face it rests on (inf when none)"""
    best, d = np.inf, Vector(d)
    for p in P:
        p = Vector(p)
        h = tree.ray_cast(p, d)
        if h[0] is not None and h[1].dot(d) > 0:
            best = min(best, -h[3])
        else:
            g = tree.ray_cast(p, -d)
            if g[0] is not None and g[1].dot(d) > 0:
                best = min(best, g[3])
    return best / K * 1000


def first_part(parts, o, d):
    hits = [(t, i) for i, tr in enumerate(parts) for _, _, _, t in [tr.ray_cast(Vector(o), Vector(d), 1.5)] if t is not None]
    return parts[min(hits)[1]] if hits else None


def fit(fx, G, sets, seat, scale, drop=0.0):
    """mm: sit = buttocks and thighs against the cushion under the pelvis (measured straight up / down), back = back and
    shoulders against the backrest behind Bip01_Spine1 (measured forward / back); negative: sunk into it by that much,
    positive: a gap; (min, max) over the two bodies. feet = the lowest foot against the cabin floor straight under / over
    it (negative: through the floor); knees = thighs, calves and feet against every other closed cabin part (the seat
    ahead, the dash, the console, the wheel; negative: in it, by the distance to its nearest face)."""
    at = lambda b: place(np.array([G[b][3, :3]]), seat, scale, drop)[0]
    pel, sp = at("Bip01_Pelvis"), at("Bip01_Spine1")
    seats = [t for c, t, _ in fx["parts"] if c == "seat"]
    cushion = first_part(seats, pel + (0, 0.10, 0.4), (0, 0, -1))
    backrest = first_part(seats, sp, (0, -1, 0))
    out = {}
    for key, part, d in (("sit", cushion, (0, 0, 1)), ("back", backrest, (0, 1, 0))):
        v = [along(part, place(sets[f"{'butt' if key == 'sit' else 'back'}:{b}"], seat, scale, drop), d) if part else np.nan
             for b in ("MaleBody", "FemaleBody")]
        out[key] = (min(v), max(v))
    # the passenger's own seat (cushion, backrest, bolsters, base; a bench's one base): parts centred within its footprint
    other = [(c, t, m) for c, t, m in fx["parts"] if not (c in ("seat", "base") and abs(m[1] - pel[1]) < 0.35
                                                          and (abs(m[0] - pel[0]) < 0.25 or c == "base"))]
    legs = [place(np.concatenate([sets[f"legs:{b}"], sets[f"butt:{b}"]]), seat, scale, drop) for b in ("MaleBody", "FemaleBody")]
    kn = [(signed(t, P), c, tuple(np.round(m - pel, 2))) for c, t, m in other for P in legs]
    out["knees"] = min(kn)[0]
    if os.environ.get("DIAG") == "knees":
        print("DIAG knees (mm, part, its centre - pelvis)", sorted((round(v), c, m) for v, c, m in kn if v < 0)[:4])
    down, up, feet = Vector((0, 0, -1)), Vector((0, 0, 1)), np.inf
    for b in ("MaleBody", "FemaleBody"):
        for p in place(sets[f"feet:{b}"], seat, scale, drop):
            h = fx["floor"].ray_cast(Vector(p), down, 0.5)
            if h[0] is not None:
                feet = min(feet, h[3])
            else:
                h = fx["floor"].ray_cast(Vector(p), up, 0.5)
                if h[0] is not None:
                    feet = min(feet, -h[3])
    out["feet"] = feet / K * 1000
    return out


def seat_report(car, nm, tree, seat, scale, sets, spine, drop=0.0, keys=None):
    A = place(spine, seat, scale, drop)[0]
    dg = os.environ.get("DIAG", "")
    return {k: clearance(tree, A, place(v, seat, scale, drop), f"{car}/{nm}/{k}" if dg and f"{car}/{nm}/{k}".startswith(dg) else None)
            for k, v in sets.items() if keys is None or k in keys}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[argv.index("--json") + 1] if "--json" in argv else None
    cars = [a for a in argv if a in TESLA] or list(TESLA)
    # SeatPose.lua: the front seats play FRONT, the rear rows REAR (AnimSets/player-vehicle/idle/MinidoracatTesla_idle_
    # recline.xml / _rear.xml, clips by scripts/seat_anim.py); --vanilla-pose: Bob_IdleDriving everywhere (before)
    van = "--vanilla-pose" in argv
    print("POSE tesla seats:", "vanilla Bob_IdleDriving" if van else f"{FRONT} {seat_anim.CLIPS[FRONT]} / {REAR} "
          f"{seat_anim.CLIPS[REAR]}")
    poses = {None: character(None)}
    if not van:
        poses[FRONT], poses[REAR] = character(FRONT), character(REAR)
    _, _, hats, items, missing = poses[None]
    print("HATS", len(items), "items", len(hats), "models; missing", missing)
    res, red, base_ok = {}, [], None
    for car in list(VANILLA) + cars:
        tris, cabt, seats, scale, fx = shell_vanilla(car) if car in VANILLA else shell_tesla(car)
        tree = bvh(tris)
        if fx:
            fx = dict(parts=[(c, bvh(t), t.reshape(-1, 3).mean(0)) for c, t in fx["parts"]], floor=bvh(fx["floor"]))
        for nm, seat in seats:
            # what-if: SHIFT="Model3/Rear:dy:dz ..." moves those passengers dy forward / dz up (mesh grid units) before
            # a rebuild (head, hats, feet and knees hold; sit / back need the seat moved too: rebuild and rerun)
            for w in os.environ.get("SHIFT", "").split():
                key, dy, dz = w.split(":")
                if f"{car}/{nm}".startswith(key):
                    seat = seat + (0, float(dz) / scale, float(dy) / scale)
            clip = None if van or car not in TESLA else FRONT if nm.startswith("Front") else REAR
            G, sets, hats, _, _ = poses[clip]
            allsets, spine = {**sets, **hats}, np.array([G["Bip01_Spine1"][3, :3]])
            c = seat_report(car, nm, tree, seat, scale, allsets, spine)
            if car == "ModernCar" and nm == "FrontLeft":    # the hair and hats that clear vanilla's ModernCar driver
                base_ok = sorted(k for k, v in c.items() if k.startswith(("hair:", "hat:")) and v >= 0)
            body = min(c["body:MaleBody"], c["body:FemaleBody"])
            legs = min(c["legs:MaleBody"], c["legs:FemaleBody"])
            f = fit(fx, G, sets, seat, scale) if fx else None
            hair = [k for k in c if k.startswith("hair:")]
            hk = min(hair, key=c.get)
            cap = min(c[f"hat:{CAP}:M"], c[f"hat:{CAP}:F"])
            hr = sorted((k for k in c if k.startswith("hat:")), key=c.get)
            need = {"body:MaleBody", "body:FemaleBody", *(f"hat:{h}:{s}" for h in COMMON for s in "MF"),
                    *(k for k in base_ok if k.startswith("hair:"))}
            ok_red = sorted(k for k in need if c[k] < 0)
            tall = " ".join(f"{h[4:]} {min(c[f'hat:{h}:M'], c[f'hat:{h}:F']):.0f}" for h in TALL)
            fs = (f"sit {f['sit'][0]:4.0f}..{f['sit'][1]:<4.0f} back {f['back'][0]:4.0f}..{f['back'][1]:<4.0f} "
                  f"feet {f['feet']:4.0f} knees {f['knees']:4.0f}") if f else "-"
            print(f"SEAT {car:10s} {nm:12s} head {body:5.0f} cap {cap:5.0f} fit {min(c[k] for k in need):5.0f} legs {legs:5.0f} | {fs} | "
                  f"hair<0 {sum(c[k] < 0 for k in hair)}/{len(hair)} worst {c[hk]:5.0f} ({hk[5:]}) | hats<0 "
                  f"{sum(c[k] < 0 for k in hr)}/{len(hr)} | must-fit <0: {len(ok_red)} {' '.join(ok_red[:3])} | ModernCar-ok hats <0: "
                  f"{sum(c[k] < 0 for k in base_ok if k.startswith('hat:'))} | {tall}")
            res[f"{car}/{nm}"] = dict(clear={k: round(float(v), 1) for k, v in c.items()}, fit=f)
            span = {k: (v if isinstance(v, tuple) else (v, v)) for k, v in (f or {}).items()}
            off = [k for k, (lo, hi) in FIT.items() if f and not (lo <= span[k][0] and span[k][1] <= hi)]
            if off and car in TESLA:
                print(f"FIT {car}/{nm} outside {', '.join(off)} (limits mm {FIT})")
                red.append(f"{car}/{nm}:{'/'.join(off)}")
            if car in TESLA and ok_red:
                red.append(f"{car}/{nm}")
                if "--sweep" in argv:   # mm lower the seat must go for the must-fit set
                    keys = need
                    lo, hi = 0.0, 250.0
                    while hi - lo > 2:
                        mid = (lo + hi) / 2
                        cc = seat_report(car, nm, tree, seat, scale, allsets, spine, mid, keys)
                        lo, hi = (lo, mid) if min(cc.values()) >= 0 else (mid, hi)
                    cc = seat_report(car, nm, tree, seat, scale, allsets, spine, hi, {"legs:MaleBody", "legs:FemaleBody"})
                    print(f"SWEEP {car:10s} {nm:12s} drop {hi:4.0f} mm -> legs {min(cc.values()):5.0f} (the cabin seat "
                          "moves with the passenger when rebuilt: rerun after the build for sit / back / feet)")
    if out:
        json.dump(dict(pose=None if van else {k: seat_anim.CLIPS[k] for k in (FRONT, REAR)}, seats=res,
                       vanilla_ok=base_ok), open(out, "w"), indent=0)
    print("RESULT", "FAIL " + " ".join(red) if red else "PASS")
    sys.exit(1 if red else 0)


main()
