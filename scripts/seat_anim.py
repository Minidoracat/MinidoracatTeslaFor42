# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""Tesla seated poses from vanilla Bob_IdleDriving (the only player-vehicle idle clip, AnimSets/player-vehicle/idle/
default.xml), so a seated passenger fits the low Tesla cabins: head and caps under the roof, buttocks on the cushion,
back on the backrest, feet on the floor (models.md / seating.md "坐姿與車頂"; offline check scripts/blender/skf/
seat_head.py). Each pose is a list of rigid turns about model X (xanim.articulate, CLIPS): the front seats lean the
whole body back (Bip01 about the pelvis, the clip's origin), both lift the thighs at the hips and open the knees, so the
feet come up to the floor of a seat that sits lower than vanilla's chair pose. Each car gets its own copy of both,
lifted (DROP below), and the AnimSet nodes that pick them.

    uv run scripts/seat_anim.py           write the clips into MOD media/anims_X/Bob/ and the nodes into
                                          media/AnimSets/player-vehicle/idle|aim/
    uv run scripts/seat_anim.py --check   exit 1 when a shipped clip or node differs from a fresh build (after a game
                                          update, a seat change in cars/<car>.py) or a stale one is left over

The clips go in anims_X/Bob: a MOD's own anims_X folders (not Bob / Kate / Zombie) are read only when the MOD also has a
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
MEDIA = os.path.join(HERE, "..", "MOD", "MinidoracatTeslaFor42", "Contents", "mods", "MinidoracatTeslaFor42", "42",
                     "media")
OUT = os.path.join(MEDIA, "anims_X", "Bob")
NODES = os.path.join(MEDIA, "AnimSets", "player-vehicle")
# {pose: [(bone, deg)]}: front seats, rear rows (Model X's 2nd and 3rd rows too); seat_head.py poses the passengers
# from this table (posed())
CLIPS = {
    "MinidoracatTesla_IdleDrivingRecline": [("Bip01", 25.0), ("Bip01_L_Thigh", -10.0), ("Bip01_R_Thigh", -10.0)],
    "MinidoracatTesla_IdleDrivingRear": [("Bip01_L_Thigh", 30.0), ("Bip01_R_Thigh", 30.0),
                                         ("Bip01_L_Calf", -40.0), ("Bip01_R_Calf", -40.0)],
}
FRONT, REAR = "MinidoracatTesla_IdleDrivingRecline", "MinidoracatTesla_IdleDrivingRear"
# Seated passengers' depth (seating.md "乘客的深度"): a character's depth reference is the square depth at its own
# x, y, z (ModelSlotRenderData.java:126-128, 224-233), for a passenger its seat's x, y on the car's floor level
# (BaseVehicle.java:3488-3494, 1922-1927), against its model origin, the seat point (ModelSlotRenderData.java:322-327,
# 829-835; Model.java:214-226). With the seat point H over the physics ground the body drew E = H sin 30 - 0.042 grid
# farther than the car around it and the seats wrapped it. So every seat point sits DROP lower in the vehicle script
# (pzveh.geometry): the front ones SEAT_REF_H over the physics ground (E = 0; H = SEAT h + WHEEL_LIFT - PASSENGER_REF:
# the physics wheels touch 0.015 lower than the drawn ones and sag 0.063 at rest, E2E seat-head-sp physZ), the rear
# rows SEAT rear / third drop lower (E -0.01). Each car's copies of the clips lift the body by DROP (/ 1.5: the
# character's scale, Model.java:225), so it draws where it would at the old seat point. DROP differs per car (0.33-0.57
# grid), so the clips do too: one shared clip would leave E +-0.06.
# Vanilla's chair clips need no lift: Bob_SatChairOut (exit, played at the inside position until ISExitVehicle:perform
# moves the character out) and Bob_SatChairIn (switch seat at the old seat; enter at the outside position,
# BaseVehicle.enter :2510) have their origin at the feet, the seated pelvis 0.315 above it, so around the lowered seat
# point they sit within 0.03 grid of the lifted idle (around the old one they rose 0.47 through the roof).
PASSENGER_REF, SEAT_REF_H, CHAR_SCALE = 0.078, 0.084, 1.5
CARS = os.path.join(HERE, "blender", "skf", "cars")


def seat_drop(cfg):
    """grid: how much lower every seat point of the car `cfg` (a cars/<car>.py CAR) sits in the vehicle script"""
    return cfg["SEAT"]["h"] + cfg["WHEEL_LIFT"] - PASSENGER_REF - SEAT_REF_H


def drops():
    """{car model name (vehicle script name after MinidoracatTesla_ = Core.lua Specs model): DROP grid}"""
    out = {}
    for p in sorted(glob.glob(os.path.join(CARS, "*.py"))):
        cfg = runpy.run_path(p)["CAR"]
        out[cfg["NAME"].split("_", 1)[1]] = seat_drop(cfg)
    return out


DROPS = drops()
# {clip: (CLIPS pose it copies, lift in model units)}: <pose>_<model> per car
LIFTS = {f"{c}_{car}": (c, d / CHAR_SCALE) for car, d in DROPS.items() for c in (FRONT, REAR)}
# AnimSet nodes per car ({folder: [(node, pose, condition variable, ConditionPriority)]}): the front seats' node (2) is
# checked before the rear rows' (1), which also matches a front seat; the first match wins (AnimNode.java:358-370,
# AnimState.java:40-53). Vanilla's idle/default.xml and aim nodes have no conditions and priority 0. In a car "aim"
# follows the aim key even with the window shut (IsoPlayer.java:4412-4446) and vanilla's aim nodes play standing clips
# (aim_default.xml: Bob_IdleAim1Hand, no bone mask): the aim nodes keep the seated clip. Driving, steering, the horn,
# a door opened from the seat and sleeping stay in idle (the player-vehicle actiongroup has no other state for them).
# The variables are set by client/MinidoracatTesla/SeatPose.lua.
NODE_KINDS = {"idle": [("idle_recline", FRONT, "MinidoracatTeslaRecline", 2),
                       ("idle_rear", REAR, "MinidoracatTeslaSeated", 1)],
              "aim": [("aim_recline", FRONT, "MinidoracatTeslaRecline", 2),
                      ("aim_seated", REAR, "MinidoracatTeslaSeated", 1)]}


def node_xml(folder, node, base, var, prio, car):
    """one player-vehicle node, written out in full (no x_extends: family pitfalls.md, Linux servers)"""
    aim = folder == "aim"
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        f"<!-- Written by scripts/seat_anim.py (NODE_KINDS): {car}, {'front seats' if base == FRONT else 'rear rows'}. -->",
        "<animNode>",
        f"\t<m_Name>MinidoracatTesla_{node}_{car}</m_Name>",
        *(["\t<m_Priority>4</m_Priority>"] if aim else []),
        f"\t<m_ConditionPriority>{prio}</m_ConditionPriority>",
        f"\t<m_AnimName>{base}_{car}</m_AnimName>",
        f"\t<m_BlendTime>{'0.30' if aim else '0.20'}</m_BlendTime>",
        "\t<m_SpeedScale>0.80</m_SpeedScale>",
        *(["\t<m_SyncTrackingEnabled>false</m_SyncTrackingEnabled>"] if aim else []),
        "\t<m_Conditions>", f"\t\t<m_Name>{var}</m_Name>", "\t\t<m_Type>BOOL</m_Type>", "\t\t<m_Value>true</m_Value>",
        "\t</m_Conditions>",
        "\t<m_Conditions>", "\t\t<m_Name>MinidoracatTeslaCar</m_Name>", "\t\t<m_Type>STRING</m_Type>",
        f"\t\t<m_Value>{car}</m_Value>", "\t</m_Conditions>",
        "</animNode>", ""]
    return "\r\n".join(lines)


def nodes():
    """{path: xml text} of every node"""
    return {os.path.join(NODES, folder, f"MinidoracatTesla_{node}_{car}.xml"): node_xml(folder, node, base, var, prio, car)
            for car in DROPS for folder, kinds in NODE_KINDS.items() for node, base, var, prio in kinds}


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
    want = {os.path.normpath(os.path.join(OUT, name + ".x")): name for name in LIFTS}
    xml = {os.path.normpath(p): t for p, t in nodes().items()}
    have = {os.path.normpath(p) for p in glob.glob(os.path.join(OUT, "MinidoracatTesla_*.x"))
            + glob.glob(os.path.join(NODES, "*", "MinidoracatTesla_*.xml"))}
    old = sorted(have - set(want) - set(xml))     # a renamed or dropped car's, the shared clips before per-car ones
    stale = list(old)
    with tempfile.TemporaryDirectory() as d:
        for out, name in want.items():
            tmp = os.path.join(d, name + ".x")
            build(name, tmp if check else out)
            if check and (not os.path.exists(out) or open(tmp, "rb").read() != open(out, "rb").read()):
                stale.append(out)
    for out, text in xml.items():
        same = os.path.exists(out) and open(out, encoding="utf-8").read().replace("\r\n", "\n") == text.replace("\r\n", "\n")
        if check and not same:
            stale.append(out)
        elif not check:
            open(out, "w", encoding="utf-8", newline="").write(text)
    if check:
        print("seat_anim: " + (f"{stale} differ from a fresh build or are left over: run without --check" if stale
                               else f"up to date ({len(want)} clips, {len(xml)} nodes)"))
        sys.exit(1 if stale else 0)
    for p in old:
        os.remove(p)
    print(f"seat_anim: wrote {len(want)} clips, {len(xml)} nodes; removed {len(old)}:",
          " ".join(os.path.basename(p) for p in old))


if __name__ == "__main__":
    main()
