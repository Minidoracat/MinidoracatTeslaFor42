# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""Tesla seated poses from vanilla Bob_IdleDriving (the only player-vehicle idle clip, AnimSets/player-vehicle/idle/
default.xml), so a seated passenger fits the low Tesla cabins: head and caps under the roof, buttocks on the cushion,
back on the backrest, feet on the floor (models.md / seating.md "坐姿與車頂"; offline check scripts/blender/skf/
seat_head.py). Each clip is a list of rigid turns about model X (xanim.articulate): the front seats lean the whole body
back (Bip01 about the pelvis, the clip's origin), both clips lift the thighs at the hips and open the knees, so the
feet come up to the floor of a seat that sits lower than vanilla's chair pose. Only the edited bones' rotation keys
change: new local = G'[b] @ inv(G'[parent]).

    uv run scripts/seat_anim.py           write the clips into MOD media/anims_X/Bob/
    uv run scripts/seat_anim.py --check   exit 1 when a shipped clip differs from a fresh build (after a game update)

The files go in anims_X/Bob: a MOD's own anims_X folders (not Bob / Kate / Zombie) are read only when the MOD also has a
common/media/anims_X (ModelManager.loadHumanAnimations returns early, ModelManager.java:1807-1823; this MOD has no
common folder), while Bob is read from the version folder by itself (loadModAnimations, ModelManager.java:1678-1699).
E2E tesla-seathead-1101d: from anims_X/MinidoracatTesla the node matched and played no clip (character in bind pose).
"""
import glob
import os
import runpy
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "blender", "common"))
from xanim import articulate, pose, quat, read_anim, write_anim  # noqa: E402

PZ = "D:/SteamLibrary/steamapps/common/ProjectZomboid/media"
SRC = f"{PZ}/anims_X/Bob/Bob_IdleDriving.x"
OUT = os.path.join(HERE, "..", "MOD", "MinidoracatTeslaFor42", "Contents", "mods", "MinidoracatTeslaFor42", "42", "media",
                   "anims_X", "Bob")
# {clip: [(bone, deg)]}: front seats (AnimSets .../idle/MinidoracatTesla_idle_recline.xml), rear rows (.../idle/
# MinidoracatTesla_idle_rear.xml); seat_head.py poses the passengers from this table
CLIPS = {
    "MinidoracatTesla_IdleDrivingRecline": [("Bip01", 25.0), ("Bip01_L_Thigh", -10.0), ("Bip01_R_Thigh", -10.0)],
    "MinidoracatTesla_IdleDrivingRear": [("Bip01_L_Thigh", 30.0), ("Bip01_R_Thigh", 30.0),
                                         ("Bip01_L_Calf", -40.0), ("Bip01_R_Calf", -40.0)],
}
FRONT, REAR = "MinidoracatTesla_IdleDrivingRecline", "MinidoracatTesla_IdleDrivingRear"
# Seated passengers' depth (seating.md 1b): the engine depth-references a passenger on the ground under its seat point,
# so the body draws E = H sin 30 - 0.042 grid too far (H = the seat point over the physics ground = SEAT h + WHEEL_LIFT
# - PASSENGER_REF). A car whose cars/<car>.py SEAT has `lift` puts every seat point DROP lower in the vehicle script
# (pzveh.geometry; the front ones at SEAT_REF_H, E = 0; the rear rows sit lower, E -0.01), and its own copies of the
# clips lift the body by DROP (/ 1.5: the character's scale, Model.java:225), so the body draws where it did and the
# cabin needs no depth push (cabin.py). Vanilla's chair clips need no lift: Bob_SatChairOut (exit, played at the inside
# position until ISExitVehicle:perform moves the character out) and Bob_SatChairIn (switch seat at the old seat; enter
# at the outside position, BaseVehicle.enter :2510) have their origin at the feet, the seated pelvis 0.315 above it,
# so around a lowered seat point they sit within 0.03 grid of the lifted idle (around a high one they pop up 0.47).
# ponytail: one copy of each clip per lifted car (DROP differs per car); prototype proto/seatref-1102, Model Y only.
PASSENGER_REF, SEAT_REF_H, CHAR_SCALE = 0.078, 0.084, 1.5
CARS = os.path.join(HERE, "blender", "skf", "cars")


def seat_drop(cfg, force=False):
    """grid: how much lower the car's seat points sit in the vehicle script (0: not lifted; force: as if it were)"""
    s = cfg["SEAT"]
    return s["h"] + cfg["WHEEL_LIFT"] - PASSENGER_REF - SEAT_REF_H if s.get("lift") or force else 0.0


def lifted(force=False):
    """{car short name (vehicle script name after MinidoracatTesla_): DROP grid} for every lifted car (force: every
    car, as if lifted: seat_head.py WHATIF_LIFT)"""
    out = {}
    for p in sorted(glob.glob(os.path.join(CARS, "*.py"))):
        cfg = runpy.run_path(p)["CAR"]
        if seat_drop(cfg, force):
            out[cfg["NAME"].split("_", 1)[1]] = seat_drop(cfg, force)
    return out


# {clip: (CLIPS clip it copies, lift in model units)}
LIFTS = {f"{c}_{car}": (c, d / CHAR_SCALE) for car, d in lifted().items() for c in (FRONT, REAR)}


def posed(bones, G, clip):
    """pose() matrices of `clip` (CLIPS or LIFTS) from Bob_IdleDriving's: CLIPS' turns, then a LIFTS clip moves Bip01 and
    everything under it up (model +Y) by its lift"""
    base, up = LIFTS.get(clip, (clip, 0.0))
    G = articulate(bones, G, CLIPS[base])
    if up:
        parent = dict(bones)
        for b, _ in bones:
            a = b
            while a and a != "Bip01":
                a = parent[a]
            if a:
                G[b] = G[b].copy()
                G[b][3, 1] += up
    return G


def build(name, dst):
    anim = read_anim(SRC)
    bones, parent = anim[0], dict(anim[0])
    base, up = LIFTS.get(name, (name, 0.0))
    rot, pos = {}, {}
    for b in dict.fromkeys(b for b, _ in CLIPS[base]):
        qs = []
        for tick in anim[1][b]["R"][0]:
            G = posed(bones, pose(anim, tick), name)
            qs.append(quat((G[b] @ np.linalg.inv(G[parent[b]]))[:3, :3]))
        rot[b] = qs
    if up:   # Bip01's own position keys (its parent Dummy01 turns model space: local = G[Bip01] @ inv(G[Dummy01]))
        pos["Bip01"] = [(posed(bones, pose(anim, t), name)["Bip01"] @ np.linalg.inv(pose(anim, t)["Dummy01"]))[3, :3]
                        for t in anim[1]["Bip01"]["T"][0]]
    write_anim(SRC, dst, name, rot, pos)
    # self-check: at every key of an edited bone the written clip poses the skeleton as posed() does
    new = read_anim(dst)
    for b in [*rot, *pos]:
        for tick in anim[1][b]["R" if b in rot else "T"][0]:
            want, got = posed(bones, pose(anim, tick), name), pose(new, tick)
            bad = max(np.abs(got[x] - want[x]).max() for x, _ in bones)
            assert bad < 1e-4, f"{name} tick {tick}: posed bones off by {bad}"


def main():
    check = "--check" in sys.argv
    stale = []
    for name in [*CLIPS, *LIFTS]:
        out = os.path.join(OUT, name + ".x")
        if check:
            with tempfile.TemporaryDirectory() as d:
                tmp = os.path.join(d, name + ".x")
                build(name, tmp)
                if not os.path.exists(out) or open(tmp, "rb").read() != open(out, "rb").read():
                    stale.append(out)
        else:
            os.makedirs(OUT, exist_ok=True)
            build(name, out)
            print("seat_anim: wrote", os.path.normpath(out))
    if check:
        print("seat_anim: " + (f"{stale} differ from a fresh build: run without --check" if stale else "up to date"))
        sys.exit(1 if stale else 0)


if __name__ == "__main__":
    main()
