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
import os
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


def build(name, dst):
    anim = read_anim(SRC)
    bones, parent, edits = anim[0], dict(anim[0]), CLIPS[name]
    rot = {}
    for b in dict.fromkeys(b for b, _ in edits):
        qs = []
        for tick in anim[1][b]["R"][0]:
            G = articulate(bones, pose(anim, tick), edits)
            qs.append(quat((G[b] @ np.linalg.inv(G[parent[b]]))[:3, :3]))
        rot[b] = qs
    write_anim(SRC, dst, name, rot)
    # self-check: at every key of an edited bone the written clip poses the skeleton as articulate() does
    new = read_anim(dst)
    for b in rot:
        for tick in anim[1][b]["R"][0]:
            want, got = articulate(bones, pose(anim, tick), edits), pose(new, tick)
            bad = max(np.abs(got[x] - want[x]).max() for x, _ in bones)
            assert bad < 1e-4, f"{name} tick {tick}: posed bones off by {bad}"


def main():
    check = "--check" in sys.argv
    stale = []
    for name in CLIPS:
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
