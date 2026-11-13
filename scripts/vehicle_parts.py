"""Expand the Tesla vehicle scripts the way the engine loads them (offline) and compare two revisions.

    python scripts/vehicle_parts.py [--against REV] [--json DIR]

Each MOD vehicle (media/scripts/vehicles/MinidoracatTesla_*.txt) is loaded like VehicleScript.Load (pz/ 42.22.2):
`template! = X` loads X's body in place (:288-294), `template = X` copies every area, part, passenger, sound key, wheel
and the physics of X's own loaded script, `template = X/part/Y` that one part (:1156-1295: a copy replaces a part of
the same id in place, else appends), a `part` block merges into the part of its id or appends one (LoadPart :909-988:
values override, lua and door and window replace, container / anims / models / tables merge, an empty table value
deletes the key :1135-1150), `part Seat*` merges into every part the glob matches at that point (:310-322). Vanilla
templates come from the game's media/scripts. Prints, per car, whether the resolved part list (ids, order, every
field), passengers, areas, scalars and sound are the same in the worktree and in REV (default main).
--json DIR also writes each car's resolved script (worktree side) for reading.
"""
import copy
import glob
import json
import os
import re
import subprocess
import sys

PZ = "D:/SteamLibrary/steamapps/common/ProjectZomboid/media/scripts"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
VEH = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/scripts/vehicles"


def strip_comments(s):
    return re.sub(r"/\*.*?\*/", "", s, flags=re.S)   # the MOD and vanilla scripts nest none (ScriptParser.stripComments)


def read_block(s, start, block):
    """ScriptParser.readBlock: a value ends at ',', a block header is the text before '{'; text before '}' is dropped."""
    i = start
    while i < len(s):
        c = s[i]
        if c == "{":
            head = s[start:i].split()
            child = dict(type=head[0], id=head[1] if len(head) > 1 else None, values=[], children=[], elements=[])
            block["children"].append(child)
            block["elements"].append(child)
            i = read_block(s, i + 1, child)
            start = i
            continue
        if c == "}":
            return i + 1
        if c == ",":
            v = s[start:i]
            block["values"].append(v)
            block["elements"].append(v)
            start = i + 1
        i += 1
    return i


def parse(text):
    root = dict(type=None, id=None, values=[], children=[], elements=[])
    read_block(strip_comments(text), 0, root)
    return root


def kv(v):
    k, _, rest = v.partition("=")
    return k.strip(), rest.split("=")[0].strip()      # Load: ss = split("="), v = ss[1]


def merge_values(d, values):
    for v in values:
        k, x = kv(v)
        if k == "soundMap":                             # LoadContainer: a map keyed by its first word
            w = x.split()
            if len(w) == 2:
                d["soundMap " + w[0]] = w[1]
        else:
            d[k] = x


def merge_block(d, block):
    """generic merge (passenger, area, wheel, model, anim): values override, child blocks merge by (type, id)"""
    merge_values(d.setdefault("values", {}), block["values"])
    for ch in block["children"]:
        merge_block(d.setdefault("children", {}).setdefault(f"{ch['type']} {ch['id']}", {}), ch)
    return d


def load_table(t, block):
    for v in block["values"]:
        k, x = kv(v)
        if x:
            t[k] = x
        else:
            t.pop(k, None)                               # rawset(k, null)
    for ch in block["children"]:
        sub = t.get(ch["type"])
        t[ch["type"]] = load_table(sub if isinstance(sub, dict) else {}, ch)
    return t


def glob_match(pat, s):
    return re.fullmatch(pat.replace("*", ".*"), s) is not None


class Script:
    def __init__(self, reg):
        self.reg = reg
        self.scalars, self.sound, self.parts, self.passengers, self.areas, self.wheels = {}, {}, {}, {}, {}, {}
        self.physics, self.skins, self.models, self.attachments, self.other = [], [], {}, {}, []

    # ---- VehicleScript.Load
    def load(self, block):
        for el in block["elements"]:
            if isinstance(el, str):
                k, v = kv(el)
                if k == "template":
                    self.load_template(v)
                elif k == "template!":
                    self.load(self.reg[v])
                else:
                    self.scalars[k] = v
                continue
            t, i = el["type"], el["id"]
            if t == "part":
                for pid in ([p for p in self.parts if glob_match(i, p)] if "*" in i else [i]):
                    self.load_part(pid, el)
            elif t == "passenger":
                for pid in ([p for p in self.passengers if glob_match(i, p)] if "*" in i else [i]):
                    merge_block(self.passengers.setdefault(pid, {}), el)
            elif t == "area":
                merge_block(self.areas.setdefault(i, {}), el)
            elif t in ("wheel", "crawlThroughWheel"):
                merge_block(self.wheels.setdefault(f"{t} {i}", {}), el)
            elif t == "model":
                merge_block(self.models.setdefault(i, {}), el)
            elif t == "attachment":
                merge_block(self.attachments.setdefault(i, {}), el)
            elif t == "physics":
                if len(self.physics) < 10:
                    self.physics.append(merge_block({"id": i}, el))
            elif t == "skin":
                self.skins.append(merge_block({}, el))
            elif t == "sound":
                for v in el["values"]:
                    k, x = kv(v)
                    if k in ("alarm", "alarmLoop"):        # these add to a list
                        self.sound.setdefault(k, []).extend(x.split())
                    else:
                        self.sound[k] = x
            else:
                self.other.append(merge_block({"type": t, "id": i}, el))

    def load_part(self, pid, block):
        p = self.parts.setdefault(pid, {"values": {}})
        merge_values(p["values"], block["values"])
        for ch in block["children"]:
            t = ch["type"]
            if t == "anim":
                merge_block(p.setdefault("anims", {}).setdefault(ch["id"], {}), ch)
            elif t == "container":
                merge_values(p.setdefault("container", {}), ch["values"])
            elif t in ("door", "window", "lua"):             # LoadDoor / LoadWindow / LoadLuaFunctions: a new one
                p[t] = {}
                merge_values(p[t], ch["values"])
            elif t == "model":
                merge_block(p.setdefault("models", {}).setdefault(ch["id"], {}), ch)
            elif t == "table":
                tabs = p.setdefault("tables", {})
                tabs[ch["id"]] = load_table(tabs.get(ch["id"]) or {}, ch)

    def load_template(self, v):
        ss = [s.strip() for s in v.split("/")]
        src = self.reg.script(ss[0])
        if len(ss) == 1:
            for name in ("areas", "parts", "passengers", "wheels"):
                getattr(self, name).update(copy.deepcopy(getattr(src, name)))   # dict: in place or appended
            self.sound.update(copy.deepcopy(src.sound))
            self.physics = copy.deepcopy(src.physics)
            return
        kind = {"part": "parts", "area": "areas", "passenger": "passengers", "wheel": "wheels"}.get(ss[1])
        if kind:
            getattr(self, kind)[ss[2]] = copy.deepcopy(getattr(src, kind)[ss[2]])
        elif ss[1] == "physics":
            self.physics = copy.deepcopy(src.physics)
        else:
            raise SystemExit(f"template {v}: unknown kind")

    def resolved(self):
        return dict(parts=[[k, v] for k, v in self.parts.items()], passengers=self.passengers, areas=self.areas,
                    scalars=self.scalars, sound=self.sound, wheels=self.wheels, physics=self.physics,
                    models=self.models, attachments=self.attachments, skins=self.skins, other=self.other)


class Registry(dict):
    """template vehicle name -> its parsed block; script(name) = VehicleTemplate.getScript (loaded once)"""
    def __init__(self, texts):
        super().__init__()
        self.cache = {}
        for text in texts:   # the header "template vehicle NAME" (ScriptManager reads it by tokens)
            s = strip_comments(text)
            for m in re.finditer(r"template\s+vehicle\s+(\w+)\s*\{", s):
                b = dict(type=None, id=None, values=[], children=[], elements=[])
                read_block(s, m.end(), b)
                self[m[1]] = b

    def script(self, name):
        if name not in self.cache:
            s = Script(self)
            s.load(self[name])
            self.cache[name] = s
        return self.cache[name]


def car_blocks(text):
    s = strip_comments(text)
    for m in re.finditer(r"(?<!template )\bvehicle\s+(\w+)\s*\{", s):
        b = dict(type=None, id=None, values=[], children=[], elements=[])
        read_block(s, m.end(), b)
        yield m[1], b


def resolve(mod_texts, vanilla):
    reg = Registry(vanilla + list(mod_texts.values()))
    out = {}
    for fn, text in sorted(mod_texts.items()):
        for name, b in car_blocks(text):
            s = Script(reg)
            s.load(b)
            out[name] = s.resolved()
    return out


def main(argv):
    rev = argv[argv.index("--against") + 1] if "--against" in argv else "main"
    vanilla = [open(p, encoding="utf-8", errors="replace").read()
               for p in glob.glob(os.path.join(PZ, "**", "*.txt"), recursive=True)
               if "template vehicle" in open(p, encoding="utf-8", errors="replace").read()]
    new = {os.path.basename(p): open(p, encoding="utf-8").read() for p in glob.glob(os.path.join(ROOT, VEH, "*.txt"))}
    names = subprocess.run(["git", "-C", ROOT, "ls-tree", "--name-only", rev, VEH + "/"], capture_output=True, text=True,
                           check=True).stdout.split()
    old = {os.path.basename(p): subprocess.run(["git", "-C", ROOT, "show", f"{rev}:{p}"], capture_output=True,
                                               text=True, encoding="utf-8", check=True).stdout for p in names}
    a, b = resolve(old, vanilla), resolve(new, vanilla)
    bad = 0
    print(f"vehicle_parts: {rev} -> worktree, {len(vanilla)} vanilla template files")
    for car in sorted(set(a) | set(b)):
        if car not in a or car not in b:
            print(f"  {car}: only in {'worktree' if car in b else rev}")
            continue
        ra, rb = a[car], b[car]
        diff = [k for k in ra if json.dumps(ra[k], sort_keys=True) != json.dumps(rb[k], sort_keys=True)]
        ids = [p for p, _ in rb["parts"]]
        print(f"  {car}: {'SAME' if not diff else 'DIFF ' + ','.join(diff)}; {len(ids)} parts, "
              f"{len(rb['passengers'])} passengers, {len(rb['areas'])} areas, part order "
              f"{'same' if ids == [p for p, _ in ra['parts']] else 'CHANGED'}")
        bad += bool(diff)
        if "--json" in argv:
            d = argv[argv.index("--json") + 1]
            os.makedirs(d, exist_ok=True)
            json.dump(rb, open(os.path.join(d, car + ".json"), "w", encoding="utf-8"), indent=1, sort_keys=True)
    if "--core" in argv:   # what a car on Core alone resolves to (a two-seater's template part list)
        core = Registry(vanilla + list(new.values())).script("MinidoracatTeslaCore")
        print("  MinidoracatTeslaCore parts:", ", ".join(core.parts))
        base = Registry(vanilla + list(new.values())).script("MinidoracatTeslaBase")
        print("  MinidoracatTeslaBase parts:", ", ".join(base.parts))
    print("vehicle_parts:", "FAIL" if bad else "OK")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
