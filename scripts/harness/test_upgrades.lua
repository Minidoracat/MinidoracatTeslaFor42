-- Upgrades.lua (references/upgrades.md): which parts the protection kits shield, each kit's k, the bull bar's
-- visibility with the glass drawn after it, the fridge's zeroed content amount and its state dropped on removal,
-- and the server hooks called only when they exist. The part and item contract is scripts/upgrades_check.py.
local check = H.check
local T = MinidoracatTesla
H.require("MinidoracatTesla/Upgrades")
local A, F = T.Armor, T.Fridge

local function part(id, o)
    o = o or {}
    local p = { id = id, cat = o.cat, item = o.item, window = o.window, light = o.light, md = {}, shown = {}, log = {} }
    function p:getId() return self.id end
    function p:getCategory() return self.cat end
    function p:getWindow() return self.window end
    function p:getLight() return self.light end
    function p:getInventoryItem() return self.item end
    function p:getModData() return self.md end
    function p:setModelVisible(m, b) self.shown[m] = b; self.log[#self.log + 1] = m .. "=" .. tostring(b) end
    function p:setContainerContentAmount(v) self.content = v end
    return p
end
local function item(full)
    local it = { full = full, cap = 12 }
    function it:getFullType() return self.full end
    function it:setItemCapacity(c) self.cap = c end
    return it
end
local function car(parts)
    local v = { parts = {}, tx = 0 }
    for _, p in ipairs(parts) do v.parts[p.id] = p end
    function v:getPartById(id) return self.parts[id] end
    function v:transmitPartModData() self.tx = self.tx + 1 end
    return v
end

H.section("Upgrades: armor")
local shielded = { part("DoorFrontLeft", { cat = "door" }), part("EngineDoor", { cat = "bodywork" }),
    part("WindowFrontLeft", { window = {} }), part("HeadlightLeft", { light = {} }), part("Engine"), part("GasTank") }
local bare = { part("TireFrontLeft", { cat = "tire" }), part("BrakeFrontLeft", { cat = "brakes" }),
    part("SeatFrontLeft", { cat = "seat" }), part("TeslaArmor", { cat = "upgrade" }) }
local okIn, okOut = true, true
for _, p in ipairs(shielded) do okIn = okIn and A.covers(p) end
for _, p in ipairs(bare) do okOut = okOut and not A.covers(p) end
check(okIn and okOut, "covers: door / bodywork, windows, lights, Engine, GasTank; not tyres, brakes, seats or itself")

local glass, armor = part("CabinGlass"), part("TeslaArmor")
local v = car({ glass, armor })
check(A.k(v) == nil and A.k(car({})) == nil, "no kit (or no part): k nil")
armor.item = item("Base.MinidoracatTesla_ArmorInner")
check(A.k(v) == 0.5, "Inner kit: k 0.5")
local tracked, untracked = 0, 0
A.track, A.untrack = function() tracked = tracked + 1 end, function() untracked = untracked + 1 end
T.Init.Armor(v, armor)
check(armor.shown.Armor == false and #glass.log == 0 and tracked == 1, "Inner fitted: no bull bar, glass untouched, tracked")
armor.item = item("Base.MinidoracatTesla_ArmorOuter")
T.Init.Armor(v, armor)
check(A.k(v) == 0.25 and armor.shown.Armor == true and table.concat(glass.log, ",") == "Glass=false,Glass=true" and tracked == 2,
    "Outer fitted: k 0.25, bull bar shown, glass drawn after it, tracked")
T.InstallComplete.Armor(v, armor)
check(armor.shown.Armor == true and tracked == 3, "install complete: bull bar shown, tracked")
armor.item = nil
T.UninstallComplete.Armor(v, armor)
check(armor.shown.Armor == false and untracked == 1, "uninstall complete (item already gone): bull bar hidden, untracked")
A.track, A.untrack = nil, nil
armor.item = item("Base.MinidoracatTesla_ArmorOuter")
T.Init.Armor(v, armor)
check(armor.shown.Armor == true, "no server hooks (a client): init still syncs the bull bar")

H.section("Upgrades: fridge")
local fr = part("TeslaFridge", { item = item("Base.MinidoracatTesla_Fridge") })
local fv = car({ fr })
check(F.part(fv) == fr and F.part(car({ part("TeslaFridge") })) == nil and F.part(car({})) == nil, "part: the fitted fridge only")
T.Init.Fridge(fv, fr)
check(fr.content == 0 and fr.item.cap == 0, "init: content amount and item capacity zeroed (requireEmpty reads them)")
fr.md.fridge = { mode = "cool", items = {} }
local dropped = 0
F.untrack = function() dropped = dropped + 1 end
fr.item = nil
T.UninstallComplete.Fridge(fv, fr)
check(fr.md.fridge == nil and fv.tx == 1 and dropped == 1, "uninstall complete: state dropped and sent, untracked")
F.untrack = nil
T.UninstallComplete.Fridge(fv, fr)
check(fv.tx == 2, "no server hook: uninstall complete still clears")
local sv = SandboxVars
SandboxVars = { FridgeFactor = 5, FoodRotSpeed = 1 }
local a, b = F.fridgeFactor(), F.rotSpeed()
SandboxVars = {}
check(a == 0.03 and b == 1.7 and F.fridgeFactor() == 0.2 and F.rotSpeed() == 1.0,
    "sandbox tables: FridgeFactor 5 = 0.03, FoodRotSpeed 1 = 1.7, unset = the default 3")
SandboxVars = sv
