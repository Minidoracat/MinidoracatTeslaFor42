-- Drive unit: Tesla repair / salvage with Drive Unit Parts (vanilla formulas), vanilla Engine Parts actions refused
-- on a Tesla, mechanics menu options swapped on a Tesla only. Real menu, real actions and MP: E2E drive-unit-sp / -mp.
local T = MinidoracatTesla
local check = H.check
H.side(false, true)

-- ---- fakes: vanilla classes (ISBaseObject:derive, ISRepairEngine:new) and the objects complete() touches
local Base = {}
function Base:derive(t) local o = setmetatable({}, self); self.__index = self; o.Type = t; return o end
local function vanillaNew(jobType)
    return function(self, character, part, item, maxTimeInit)
        local o = setmetatable({}, self); self.__index = self
        o.character, o.part, o.vehicle, o.item, o.maxTimeInit = character, part, part and part:getVehicle(), item, maxTimeInit
        o.jobType = jobType
        return o
    end
end
ISRepairEngine = Base:derive("ISRepairEngine")
ISRepairEngine.isValid = function() return true end
ISRepairEngine.complete = function(self) self.vanillaRan = true; return true end
ISRepairEngine.new = vanillaNew("IGUI_RepairEngine")
ISTakeEngineParts = Base:derive("ISTakeEngineParts")
ISTakeEngineParts.isValid = ISRepairEngine.isValid
ISTakeEngineParts.complete = ISRepairEngine.complete
ISTakeEngineParts.new = vanillaNew("IGUI_TakeEngineParts")
H.stub("Vehicles/TimedActions/ISRepairEngine")
H.stub("Vehicles/TimedActions/ISTakeEngineParts")

Perks = { Mechanics = "Mechanics" }
IsoObjectChange = { MECHANIC_ACTION_DONE = 1 }
function addXp(chr, perk, n) chr.xp = chr.xp + n end
function sendRemoveItemFromContainer() end
function sendAddItemsToContainer() end
getGameTime().getCalender = function() return { getTimeInMillis = function() return 0 end } end

require "MinidoracatTesla/DriveUnit"
local DU = T.DriveUnit

local function car(script, cond)
    local v = H.vehicle({ script = script })
    v.condTx = 0
    function v:getMechanicalID() return "M" .. self.id end
    function v:transmitPartCondition() self.condTx = self.condTx + 1 end
    function v:getScript() return { getEngineRepairLevel = function() return 6 end } end
    local e = v.parts.Engine
    e.cond = cond
    function e:getVehicle() return v end
    function e:getCondition() return self.cond end
    function e:setCondition(c) self.cond = c end
    function e:getArea() return "Engine" end
    return v, e
end
local function mechanic(level, parts)
    local inv = { n = parts, removed = 0, added = 0 }
    function inv:getNumberOfItem(t) return t == DU.ITEM and self.n or 0 end
    function inv:getSomeTypeRecurse(t, k)
        local list = {}
        for i = 1, math.min(k, self.n) do list[i] = { getContainer = function() return inv end } end
        return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
    end
    function inv:DoRemoveItem() self.n = self.n - 1; self.removed = self.removed + 1 end
    function inv:AddItems(t, k) assert(t == DU.ITEM, t); self.n = self.n + k; self.added = self.added + k; return {} end
    local c = { level = level, xp = 0, mech = {}, inv = inv }
    function c:getPerkLevel() return self.level end
    function c:getInventory() return self.inv end
    function c:getMechanicsItem(id) return self.mech[id] end
    function c:addMechanicsItem(id) self.mech[id] = true end
    function c:sendObjectChange() end
    return c
end
local wrench = { getID = function() return 9 end, setJobType = function() end }

H.section("vanilla Engine Parts actions refuse a Tesla")
local tv, te = car(nil, 50)
local who = mechanic(10, 3)
local act = ISRepairEngine:new(who, te, wrench, 300)
check(act:isValid() == false and act:complete() == false and not act.vanillaRan and te.cond == 50,
    "ISRepairEngine on a Tesla: isValid false, complete false (server), condition unchanged")
local take = ISTakeEngineParts:new(who, te, wrench, 300)
check(take:isValid() == false and take:complete() == false and not take.vanillaRan, "ISTakeEngineParts on a Tesla: refused")
local nv, ne = car("Base.CarNormal", 50)
local va = ISRepairEngine:new(who, ne, wrench, 300)
check(va:isValid() == true and va:complete() == true and va.vanillaRan, "ISRepairEngine on a vanilla car: vanilla runs")
check(ISTakeEngineParts:new(who, ne, wrench, 300):complete() == true, "ISTakeEngineParts on a vanilla car: vanilla runs")

H.section("repair with Drive Unit Parts")
check(ISMinidoracatTeslaRepairDriveUnit:new(who, ne, wrench, 300):isValid() == false
    and ISMinidoracatTeslaRepairDriveUnit:new(who, ne, wrench, 300):complete() == false and ne.cond == 50,
    "our repair refuses a vanilla car")
local m6 = mechanic(6, 3)
local r = ISMinidoracatTeslaRepairDriveUnit:new(m6, te, wrench, 300)
check(r:isValid() and r.jobType == "IGUI_MinidoracatTesla_RepairDriveUnit" and r.maxTimeInit == 300, "new(): fields named as parameters, our job text")
check(r:complete() == true and te.cond == 53 and m6.inv.removed == 3 and tv.condTx == 1 and m6.xp == 3,
    "level 6 (= repair level): +1 per part, 3 parts used, condition sent, 3 XP")
local again = ISMinidoracatTeslaRepairDriveUnit:new(mechanic(6, 1), te, wrench, 300)
again.character.mech["M" .. tv.id .. "2"] = true
again:complete()
check(again.character.xp == 0 and te.cond == 54, "repeat repair on the same car: no XP (vanilla mechanics item 2)")
te.cond = 95
local m10 = mechanic(10, 5)
ISMinidoracatTeslaRepairDriveUnit:new(m10, te, wrench, 300):complete()
check(te.cond == 100 and m10.inv.removed == 2 and m10.inv.n == 3, "level 10: +3 per part, stops at 100 (2 of 5 used)")
local capped = { c = 0, getCondition = function(s) return s.c end, setCondition = function(s, c) s.c = c end }
check(DU.repair(capped, 1, 12) == 1 and capped.c == 5, "per-part gain capped at 5")
te.cond = 50
local m0 = mechanic(6, 0)
check(ISMinidoracatTeslaRepairDriveUnit:new(m0, te, wrench, 300):complete() == true and te.cond == 50 and m0.xp == 2,
    "no parts: nothing repaired, vanilla's 1 + 1 XP")
local low = mechanic(5, 3)
check(ISMinidoracatTeslaRepairDriveUnit:new(low, te, wrench, 300):complete() == false and te.cond == 50 and low.inv.n == 3,
    "under the repair level: refused on the server")

H.section("take Drive Unit Parts")
local zr = ZombRand
local rolled
ZombRand = function(a, b) rolled = { a, b }; return 10 end
te.cond = 64
local tm = mechanic(6, 0)
local tk = ISMinidoracatTeslaTakeDriveUnitParts:new(tm, te, wrench, 300)
check(tk:isValid() and tk.jobType == "IGUI_MinidoracatTesla_TakeDriveUnitParts", "take: valid on a Tesla, our job text")
check(tk:complete() == true and tm.inv.added == 6 and te.cond == 0 and tm.xp == 3,
    "level 6: random(20/3, 20) -> 10 points a part, 64 -> 6 parts, condition 0, 6/2 XP")
check(rolled[1] == 20 / 3 and rolled[2] == 20, "roll range is vanilla's c/3..c with c = 20 - skill")
DU.salvage(50, 30)
check(rolled[2] == 5, "c never below 5")
te.cond = 64
local tm2 = mechanic(6, 0)
tm2.mech["M" .. tv.id .. "3"] = true
ISMinidoracatTeslaTakeDriveUnitParts:new(tm2, te, wrench, 300):complete()
check(tm2.xp == 0, "repeat salvage on the same car: no XP")
te.cond = 5
local tm3 = mechanic(6, 0)
ISMinidoracatTeslaTakeDriveUnitParts:new(tm3, te, wrench, 300):complete()
check(tm3.inv.added == 0 and te.cond == 0 and tm3.xp == 2, "condition below one part: none given, 1 + 1 XP")
check(ISMinidoracatTeslaTakeDriveUnitParts:new(mechanic(5, 0), te, wrench, 300):complete() == false, "under the repair level: refused")
check(ISMinidoracatTeslaTakeDriveUnitParts:new(tm, ne, wrench, 300):complete() == false, "vanilla car: refused")
ZombRand = zr

H.section("menu requirements (ISVehicleMechanics.lua:325,333)")
te.cond = 50
check(DU.canRepair(mechanic(6, 1), te, wrench) and DU.canTake(mechanic(6, 0), te, wrench), "level 6, wrench, part: both available")
check(not DU.canRepair(mechanic(6, 0), te, wrench), "repair: needs a part")
check(not DU.canRepair(mechanic(5, 1), te, wrench) and not DU.canTake(mechanic(5, 0), te, wrench), "under level 6: neither")
check(not DU.canRepair(mechanic(6, 1), te, nil) and not DU.canTake(mechanic(6, 0), te, nil), "no wrench: neither")
te.cond = 100
check(not DU.canRepair(mechanic(6, 1), te, wrench), "repair: not at 100")
te.cond = 10
check(not DU.canTake(mechanic(6, 0), te, wrench), "take: needs condition above 10")

H.section("mechanics menu options")
H.stub("Vehicles/ISUI/ISVehicleMechanics")
local function opt(name) return { name = name, target = "vanilla", onSelect = "vanilla" } end
ISVehicleMechanics = { ghs = "<G>", bhs = "<B>",
    getWrench = function(_, chr) return chr.wrench end,
    doPartContextMenu = function(self)
        self.context = { options = { opt("ContextMenu_PartInfo"), opt("IGUI_TakeEngineParts"), opt("IGUI_RepairEngine") },
            setWidth = function(c, w) c.width = w end, calcWidth = function() return 123 end }
    end }
ISToolTip = { new = function() return { initialise = function() end, setVisible = function() end } end }
function getSpecificPlayer() return "player0" end
function getItemDisplayName(t) return t end
require "MinidoracatTesla/DriveUnitMenu"
te.cond = 50
local win = { chr = mechanic(6, 0), playerNum = 0 }
win.chr.wrench = wrench
ISVehicleMechanics.doPartContextMenu(win, te, 0, 0)
local o = win.context.options
check(o[2].name == "IGUI_MinidoracatTesla_TakeDriveUnitParts" and o[3].name == "IGUI_MinidoracatTesla_RepairDriveUnit"
    and o[1].name == "ContextMenu_PartInfo", "Tesla: both options renamed in place, order kept")
check(o[2].onSelect == DU.onTake and o[3].onSelect == DU.onRepair and o[2].param1 == te and o[2].target == "player0",
    "Tesla: options queue our actions")
check(o[2].notAvailable == false and o[3].notAvailable == true, "no Drive Unit Parts: take available, repair greyed")
check(o[3].toolTip.description:find("<B>" .. DU.ITEM .. " 0/1", 1, true) ~= nil
    and o[2].toolTip.description:find("Tooltip_MinidoracatTesla_TakeDriveUnitPartsWarning", 1, true) ~= nil
    and not o[3].toolTip.description:find("EngineParts", 1, true), "tooltips name our item and our warning")
check(win.context.width == 123, "menu width recomputed for the longer names")
local nwin = { chr = win.chr, playerNum = 0 }
ISVehicleMechanics.doPartContextMenu(nwin, ne, 0, 0)
check(nwin.context.options[2].name == "IGUI_TakeEngineParts" and nwin.context.options[3].onSelect == "vanilla",
    "vanilla car: vanilla options untouched")
