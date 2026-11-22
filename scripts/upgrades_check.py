# -*- coding: utf-8 -*-
"""升級件（防護件 TeslaArmor、車用冰箱 TeslaFridge）的腳本契約：scripts/verify_local.py 會呼叫；單獨跑
`python scripts/upgrades_check.py`。每台車照 scripts/vehicle_parts.py 解析完範本與覆寫後檢查（references/upgrades.md）。

- 容器零件的 id 不是 fridge／freezer：容器類型就是零件 id，這兩個名字會被引擎當成家用冰箱、冷凍庫（ItemContainer.java:3872-3881）
- 兩個升級件九台車都有；install／uninstall 都有 test（沒有就裝不上、拆不下，BaseVehicle.java:8459-8478）；
  category 不是 door／bodywork（殭屍與近戰挑這兩類，空零件也挑，BaseVehicle.java:9596-9599）；mechanicRequireKey；
  沒有 skills（門檻只放在配方；有 skills 就有失敗機率，Vehicles.lua:1463-1485）
- TeslaFridge：capacity = 0（沒裝時打不開，BaseVehicle.java:8439-8453）、conditionAffectsCapacity = false、拆卸 requireEmpty
- itemType 的物品都存在、ConditionMax = 100；TeslaArmor 的 itemType 等於 Upgrades.lua 的 T.Armor.K 鍵集
- TeslaArmor 的 model Armor（有外觀件）：九台都要在本車腳本寫，file 是本車的 <車>_Armor、那個 model 區塊的 mesh 是
  vehicles/<車>_Armor（不借別台的護桿）、fbx 存在、兩層 UV（vehiclewheel 著色器讀第二層，verify_mod 第 17 項同理）、
  texture 是共用色盤 Vehicles/MinidoracatTesla_Armor 且圖檔存在
- 三個升級件物品的 Icon 有對應的 textures/Item_<Icon>.png（不借原版圖示）
- 三條配方存在、產物與技能門檻照方案（MetalWelding:3／MetalWelding:5／Electricity:4）；本 MOD 每條 craftRecipe
  都列在 Recipes.lua 的 RECIPES（漏列的話專用伺服器上進度條跑完卻做不出東西）
- MOD/ 沒有試做殘留（S0 的 ArmorTrial／FridgeTrial 等名稱與 TRIAL 註解）
- Charging.lua C.UPGRADE_LOOT 的戰利品清單名稱都在原版 ProceduralDistributions.lua（injectLoot 遇到不存在的名稱會靜默略過）

只靠本 repo 的檢查先跑（含九台車的 model Armor）；每台車的零件檢查（範本要用原版腳本解析）要原版腳本、戰利品清單名稱
要原版 ProceduralDistributions.lua，各自缺哪個就只 SKIP 那一段，其他檢查照常判定。車數不是 9 台就 FAIL（腳本搬家或
改名時不會一條都沒查卻通過）。
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vehicle_parts as vp  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(REPO, "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media")
UPGRADES = ("TeslaArmor", "TeslaFridge")
RESIDUE = ("ArmorTrial", "ArmorS0", "FridgeTrial", "UpgTest", "UpgBox", "TRIAL")

items = {}
for p in glob.glob(os.path.join(MEDIA, "scripts", "items", "*.txt")):
    body = vp.strip_comments(open(p, encoding="utf-8").read())
    for m in re.finditer(r"\bitem\s+(\w+)\s*\{([^{}]*)\}", body):
        items["Base." + m[1]] = {k: v.strip() for k, v in re.findall(r"(\w+)\s*=\s*([^,\n]*)", m[2])}
lua = open(os.path.join(MEDIA, "lua/shared/MinidoracatTesla/Upgrades.lua"), encoding="utf-8").read()
kblock = re.search(r"\bA\.K\s*=\s*\{(.*?)\n\}", lua, re.S)
armor_k = set(re.findall(r'\["([\w.]+)"\]\s*=', kblock[1])) if kblock else set()
models = {}
for p in glob.glob(os.path.join(MEDIA, "scripts", "models", "*.txt")):
    for m in re.finditer(r"\bmodel\s+(\w+)\s*\{([^{}]*)\}", vp.strip_comments(open(p, encoding="utf-8").read())):
        models[m[1]] = dict(re.findall(r"(\w+)\s*=\s*([^,\n]*)", m[2]))

bad = []
for base, _, files in os.walk(os.path.join(REPO, "MOD")):
    for name in files:
        if os.path.splitext(name)[1] not in (".lua", ".txt", ".json", ".xml"):
            continue
        path = os.path.join(base, name)
        text = open(path, encoding="utf-8", errors="replace").read()
        bad += [f"{os.path.relpath(path, REPO)}: 試做殘留 {w}" for w in RESIDUE if w in name or re.search(rf"\b{w}\b", text)]

KITS = {"MinidoracatTesla_MakeArmorInner": ("Base.MinidoracatTesla_ArmorInner", "MetalWelding:3"),
        "MinidoracatTesla_MakeArmorOuter": ("Base.MinidoracatTesla_ArmorOuter", "MetalWelding:5"),
        "MinidoracatTesla_MakeFridge": ("Base.MinidoracatTesla_Fridge", "Electricity:4")}
for recipe, (item, _) in KITS.items():
    icon = items.get(item, {}).get("Icon", "")
    if not os.path.isfile(os.path.join(MEDIA, "textures", f"Item_{icon}.png")):
        bad.append(f"{item}: Icon {icon or '（沒有）'} 找不到 textures/Item_{icon}.png")
recipes = {}
for p in glob.glob(os.path.join(MEDIA, "scripts", "recipes", "*.txt")):
    for chunk in re.split(r"\bcraftRecipe\s+", vp.strip_comments(open(p, encoding="utf-8").read()))[1:]:
        name, body = re.match(r"(\w+)\s*\{(.*)", chunk, re.S).groups()
        out = re.search(r"\boutputs\s*\{([^{}]*)\}", body)
        skill = re.search(r"\bSkillRequired\s*=\s*([^,\n]*)", body)
        recipes[name] = (re.findall(r"\bitem\s+\d+\s+([\w.]+)", out[1]) if out else [], skill[1].strip() if skill else "")
for recipe, (item, skill) in KITS.items():
    got = recipes.get(recipe)
    if not got or got[0] != [item] or got[1] != skill:
        bad.append(f"配方 {recipe} 要產出 {item}、SkillRequired = {skill}（實際 {got}）")
learn = open(os.path.join(MEDIA, "lua/server/MinidoracatTesla/Recipes.lua"), encoding="utf-8").read()
listed = re.search(r"\blocal RECIPES\s*=\s*\{(.*?)\}", learn, re.S)
listed = set(re.findall(r'"(\w+)"', listed[1])) if listed else set()
bad += [f"配方 {r} 沒列在 Recipes.lua 的 RECIPES" for r in sorted(set(recipes) - listed)]

DISTS = os.path.join(os.path.dirname(vp.PZ), "lua", "server", "Items", "ProceduralDistributions.lua")
charging = open(os.path.join(MEDIA, "lua/server/MinidoracatTesla/Charging.lua"), encoding="utf-8").read()
loot = re.search(r"\bC\.UPGRADE_LOOT\s*=\s*\{(.*?)\n\}", charging, re.S)
loot_lists = set(re.findall(r"(\w+)\s*=\s*[\d.]+", loot[1])) if loot else set()
if not loot_lists:
    bad.append("Charging.lua 找不到 C.UPGRADE_LOOT 的清單名稱")

# local: each car's own script names its model Armor (the template has none: a model without a file throws)
CARS = 9   # Model Y / 3 / S / X / YL, Roadster, Cybertruck, Cybercab, Semi (its trailer is a separate script)
ARMOR_TEX = "Vehicles/MinidoracatTesla_Armor"
if not os.path.isfile(os.path.join(MEDIA, "textures", ARMOR_TEX + ".png")):
    bad.append(f"共用色盤 textures/{ARMOR_TEX}.png 不存在")
local = []
for path in sorted(glob.glob(os.path.join(REPO, vp.VEH, "*.txt"))):
    for car, b in vp.car_blocks(open(path, encoding="utf-8").read()):
        if car.endswith("Trailer"):
            continue
        local.append(car)
        part = next((c for c in b["children"] if c["type"] == "part" and c["id"] == "TeslaArmor"), None)
        model = part and next((c for c in part["children"] if c["type"] == "model" and c["id"] == "Armor"), None)
        f = dict(vp.kv(x) for x in model["values"]).get("file") if model else None
        m = models.get(f, {})
        mesh = m.get("mesh", "").strip()
        fbx = os.path.join(MEDIA, "models_X", mesh + ".fbx")
        if not f:
            bad.append(f"{car}: 本車腳本的 part TeslaArmor 沒有 model Armor 的 file")
        elif f != car + "_Armor" or mesh != f"vehicles/{car}_Armor":
            bad.append(f"{car}: TeslaArmor model Armor 要用本車的 {car}_Armor（file {f}、mesh {mesh or '（沒有）'}）")
        elif not os.path.isfile(fbx):
            bad.append(f"{car}: TeslaArmor model Armor 的 fbx 不存在（{mesh}）")
        elif open(fbx, "rb").read().count(b"\x0eLayerElementUV") < 2:
            bad.append(f"{car}: {mesh}.fbx 不到兩層 UV")
        if f and m.get("texture", "").strip() != ARMOR_TEX:
            bad.append(f"{car}: model {f} 的 texture 要是共用色盤 {ARMOR_TEX}（{m.get('texture')}）")
if len(local) != CARS:
    bad.append(f"{vp.VEH} 讀到 {len(local)} 台車（要 {CARS} 台）")

skips, checked = [], 0
vanilla = [t for t in (open(p, encoding="utf-8", errors="replace").read()
                       for p in glob.glob(os.path.join(vp.PZ, "**", "*.txt"), recursive=True)) if "template vehicle" in t]
if not vanilla:
    skips.append(f"SKIP 每台車的升級零件（找不到原版範本 {vp.PZ}）")
else:
    cars = vp.resolve({os.path.basename(p): open(p, encoding="utf-8").read()
                       for p in glob.glob(os.path.join(REPO, vp.VEH, "*.txt"))}, vanilla)
    for car, r in sorted(cars.items()):
        if car.endswith("Trailer"):   # the Semi's trailer has its own script, not template Cab
            continue
        checked += 1
        parts = dict(r["parts"])
        bad += [f"{car}: 容器零件 {pid} 的 id 是 {pid.lower()}" for pid, p in parts.items()
                if "container" in p and pid.lower() in ("fridge", "freezer")]
        for pid in UPGRADES:
            p = parts.get(pid)
            if not p:
                bad.append(f"{car}: 沒有 part {pid}")
                continue
            v, tabs = p["values"], p.get("tables", {})
            if v.get("category") in ("door", "bodywork"):
                bad.append(f"{car}: {pid} category = {v.get('category')}")
            if v.get("mechanicRequireKey") != "true":
                bad.append(f"{car}: {pid} 沒有 mechanicRequireKey = true")
            for t in ("install", "uninstall"):
                if not tabs.get(t, {}).get("test"):
                    bad.append(f"{car}: {pid} 的 {t} 表沒有 test")
                if "skills" in tabs.get(t, {}):
                    bad.append(f"{car}: {pid} 的 {t} 表有 skills")
            types = [x.strip() for x in v.get("itemType", "").split(";") if x.strip()]
            bad += [f"{car}: {pid} itemType {x} 沒有定義或 ConditionMax 不是 100" for x in types
                    if items.get(x, {}).get("ConditionMax") != "100"]
            if pid == "TeslaArmor" and set(types) != armor_k:
                bad.append(f"{car}: TeslaArmor itemType {sorted(types)} 和 Upgrades.lua T.Armor.K {sorted(armor_k)} 不同")
            if pid == "TeslaFridge":
                c = p.get("container", {})
                if c.get("capacity") != "0" or c.get("conditionAffectsCapacity") != "false":
                    bad.append(f"{car}: TeslaFridge container 要 capacity = 0、conditionAffectsCapacity = false（{c}）")
                if tabs.get("uninstall", {}).get("requireEmpty") != "true":
                    bad.append(f"{car}: TeslaFridge 拆卸沒有 requireEmpty = true")
    if checked != CARS:
        bad.append(f"原版範本解析出 {checked} 台車（要 {CARS} 台）")
if os.path.isfile(DISTS):
    lists = set(re.findall(r"^\t(\w+)\s*=\s*\{", open(DISTS, encoding="utf-8", errors="replace").read(), re.M))
    bad += [f"C.UPGRADE_LOOT 的清單 {n} 不在原版 ProceduralDistributions.lua" for n in sorted(loot_lists - lists)]
else:
    skips.append(f"SKIP 戰利品清單名稱（找不到 {DISTS}）")
skipped = "；".join(skips)

if bad:
    print("升級件腳本契約不符：" + "；".join(bad) + (f"；{skipped}" if skipped else ""))
    sys.exit(1)
print(f"升級件腳本契約（本地 {len(local)} 台車、原版範本解析 {checked} 台、{len(loot_lists)} 張戰利品清單）"
      + (f"；{skipped}" if skipped else ""))
