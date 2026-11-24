# -*- coding: utf-8 -*-
"""TallHats.lua (the tall hats hidden per Tesla seat) against the files it was measured on.

scripts/blender/skf/seat_head.py --tall-lua measures every seat of every car and writes TallHats.lua with one header
line per car (`-- input <car> <hash>`, plus `tool` for the measuring code); `uv run scripts/tall_hats.py` (verify_local,
verify_mod 19) recomputes the hashes and fails on any car whose inputs changed since.

Why: until 2026-11-18 each car's round copied only its own rows in, and nothing noticed when a car's shell or seated
pose changed later: Model 3, Model S, Model X, Cybertruck (body rounds of 2026-11-12/13) and Cybercab (neck bent
forward, 722d7c61) kept rows from before, so a spiked full helmet left the Cybercab roof 17 mm with nothing hiding it
and a wooly hat hid in the Model 3's right back seat with 26 mm to spare.

A car's rows depend on its body, door and glass FBX (the shell the hats are measured against), its vehicle script (the
seat points, the scale) and its two seated clips (seat_anim.py writes them from the same pose table seat_head reads;
`seat_anim.py --check` keeps them in step). Hashes are of the files as committed: text read with CRLF as LF (a Windows
checkout's .x clips are CRLF), FBX byte for byte, so any rebuild of a car's FBX asks for a rerun (about a minute) even
when only its timestamp moved. The game's own files (hats, bodies, vanilla cars) are left out on purpose: a game update
must not turn the repo's gate red (the 2026-11-06 update changed none of the rows).
"""
import hashlib
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media"
LUA = f"{MEDIA}/lua/shared/MinidoracatTesla/TallHats.lua"
# the cars with seats (vehicle script / Core.lua Specs model names); seat_head.py measures these
TESLA = ("ModelY", "Model3", "ModelS", "ModelX", "Cybertruck", "ModelYL", "Roadster", "Cybercab", "Semi", "Roadster2")
TOOL = ("scripts/blender/skf/seat_head.py", "scripts/blender/common/xanim.py")
TEXT = (".txt", ".x", ".py", ".lua")
CMD = ('"<Blender>" -b --factory-startup --python-use-system-env --python scripts/blender/skf/seat_head.py -- '
       f"--tall-lua {LUA}")


def files(car):
    """repo-relative inputs of `car`'s rows"""
    v = f"MinidoracatTesla_{car}"
    return (f"{MEDIA}/models_X/vehicles/{v}.fbx", f"{MEDIA}/models_X/vehicles/{v}_Doors.fbx",
            f"{MEDIA}/models_X/vehicles/{v}_Glass.fbx", f"{MEDIA}/scripts/vehicles/{v}.txt",
            f"{MEDIA}/anims_X/Bob/MinidoracatTesla_IdleDrivingRecline_{car}.x",
            f"{MEDIA}/anims_X/Bob/MinidoracatTesla_IdleDrivingRear_{car}.x")


def digest(paths):
    h = hashlib.sha256()
    for rel in paths:
        data = open(os.path.join(REPO, rel), "rb").read()
        if rel.endswith(TEXT):
            data = data.replace(b"\r\n", b"\n")
        h.update(rel.encode() + b"\0" + hashlib.sha256(data).digest())
    return h.hexdigest()[:16]


def inputs():
    """{"tool" | car: hash}, in the order the header lists them"""
    return {"tool": digest(TOOL), **{car: digest(files(car)) for car in TESLA}}


def header():
    return "".join(f"-- input {k} {v}\n" for k, v in inputs().items())


def main():
    text = open(os.path.join(REPO, LUA), encoding="utf-8").read()
    have = dict(re.findall(r"^-- input (\w+) ([0-9a-f]+)$", text, re.M))
    stale = [k for k, v in inputs().items() if have.get(k) != v]
    if stale:
        print(f"TallHats.lua 過期（{' '.join(stale)} 的輸入在產生後改過，或檔頭沒有紀錄）：重跑 {CMD}")
        return 1
    print(f"TallHats.lua 是最新的（{len(TESLA)} 台車與量測程式的輸入都沒變）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
