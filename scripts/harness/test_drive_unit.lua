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

-- VehicleManager's adapter registration hooks, one fake event each (not fired here: H.fire would run every test's handlers)
local onServer, onGame, evBefore = {}, {}, { rawget(Events, "OnGameStart"), rawget(Events, "OnServerStarted") }
rawset(Events, "OnGameStart", { Add = function(fn) onGame[#onGame + 1] = fn end })
rawset(Events, "OnServerStarted", { Add = function(fn) onServer[#onServer + 1] = fn end })
require "MinidoracatTesla/DriveUnit"
rawset(Events, "OnGameStart", evBefore[1])
rawset(Events, "OnServerStarted", evBefore[2])
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

-- a kit (server/Armor.lua A.around) stands in here: records the car and the drive unit's condition when it settles
-- (before the action's change) and when it takes the new snapshot (after). owed = the condition the settle gives the
-- drive unit back to (what a kit owes from a hit since the last minute), once
local armor, arounds, te, owed = T.Armor, {}, nil, nil
T.Armor = { around = function(v, fn)
    if owed and te then te.cond, owed = owed, nil end
    local s = { v = v, before = te and te.cond }
    arounds[#arounds + 1] = s
    local r = fn()
    s.after = te and te.cond
    return r
end }

H.section("vanilla Engine Parts actions refuse a Tesla")
local tv
tv, te = car(nil, 50)
local who = mechanic(10, 3)
local act = ISRepairEngine:new(who, te, wrench, 300)
check(act:isValid() == false and act:complete() == false and not act.vanillaRan and te.cond == 50,
    "ISRepairEngine on a Tesla: isValid false, complete false (server), condition unchanged")
local take = ISTakeEngineParts:new(who, te, wrench, 300)
check(take:isValid() == false and take:complete() == false and not take.vanillaRan, "ISTakeEngineParts on a Tesla: refused")
check(#arounds == 0, "refused: no kit settling around it")
local nv, ne = car("Base.CarNormal", 50)
local va = ISRepairEngine:new(who, ne, wrench, 300)
check(va:isValid() == true and va:complete() == true and va.vanillaRan, "ISRepairEngine on a vanilla car: vanilla runs")
check(ISTakeEngineParts:new(who, ne, wrench, 300):complete() == true, "ISTakeEngineParts on a vanilla car: vanilla runs")
-- another mod reuses ISRepairEngine for a part without an item (Repair & Dismantle Any Car: heater, frunk)
local heater = { getId = function() return "Heater" end, getVehicle = function() return tv end }
arounds = {}
local ha = ISRepairEngine:new(who, heater, wrench, 300)
check(ha:isValid() == true and ha:complete() == true and ha.vanillaRan,
    "ISRepairEngine on a Tesla part that is not the Engine: not refused, the wrapped action runs")
local ht = ISTakeEngineParts:new(who, heater, wrench, 300)
check(ht:complete() == true and ht.vanillaRan and #arounds == 2 and arounds[1].v == tv and arounds[2].v == tv,
    "...both vanilla actions on it run inside the kit's settle / new snapshot (else a kit gives salvaged condition back)")

H.section("repair with Drive Unit Parts")
check(ISMinidoracatTeslaRepairDriveUnit:new(who, ne, wrench, 300):isValid() == false
    and ISMinidoracatTeslaRepairDriveUnit:new(who, ne, wrench, 300):complete() == false and ne.cond == 50,
    "our repair refuses a vanilla car")
local m6 = mechanic(6, 3)
local r = ISMinidoracatTeslaRepairDriveUnit:new(m6, te, wrench, 300)
check(r:isValid() and r.jobType == "IGUI_MinidoracatTesla_RepairDriveUnit" and r.maxTimeInit == 300, "new(): fields named as parameters, our job text")
arounds = {}
check(r:complete() == true and te.cond == 53 and m6.inv.removed == 3 and tv.condTx == 1 and m6.xp == 3,
    "level 6 (= repair level): +1 per part, 3 parts used, condition sent, 3 XP")
check(#arounds == 1 and arounds[1].v == tv and arounds[1].before == 50 and arounds[1].after == 53,
    "repair: the kit settles at 50, before the parts go in, and snapshots the repaired 53")
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
-- 2026-11-22 round 2: the kit's settle can make the drive unit whole (snapshot 100, 99 now, nothing kept)
te.cond, owed = 99, 100
local mFull = mechanic(10, 3)
local cTx = tv.condTx
check(ISMinidoracatTeslaRepairDriveUnit:new(mFull, te, wrench, 300):complete() == false and te.cond == 100
    and mFull.inv.n == 3 and mFull.inv.removed == 0 and mFull.xp == 0 and next(mFull.mech) == nil and tv.condTx == cTx,
    "repair, 99 given back to 100 by the kit's settle: refused, no part used, no XP, no mechanics item")
te.cond = 100
local mFull2 = mechanic(6, 2)
check(ISMinidoracatTeslaRepairDriveUnit:new(mFull2, te, wrench, 300):complete() == false and mFull2.inv.removed == 0
    and mFull2.xp == 0, "repair at 100 (someone finished first): refused the same way")
te.cond = 50

H.section("take Drive Unit Parts")
local zr = ZombRand
local rolled
ZombRand = function(a, b) rolled = { a, b }; return 10 end
te.cond = 64
local tm = mechanic(6, 0)
local tk = ISMinidoracatTeslaTakeDriveUnitParts:new(tm, te, wrench, 300)
check(tk:isValid() and tk.jobType == "IGUI_MinidoracatTesla_TakeDriveUnitParts", "take: valid on a Tesla, our job text")
arounds = {}
check(tk:complete() == true and tm.inv.added == 6 and te.cond == 0 and tm.xp == 3,
    "level 6: random(20/3, 20) -> 10 points a part, 64 -> 6 parts, condition 0, 6/2 XP")
check(#arounds == 1 and arounds[1].v == tv and arounds[1].before == 64 and arounds[1].after == 0,
    "take: the kit settles at 64 and snapshots the 0 (else it gives the salvaged condition back)")
-- the kit gives back 59 -> 65 before the take: parts counted from 65 (6), not 59 (5)
te.cond, owed = 59, 65
local tmK = mechanic(6, 0)
arounds = {}
check(ISMinidoracatTeslaTakeDriveUnitParts:new(tmK, te, wrench, 300):complete() == true and tmK.inv.added == 6
    and te.cond == 0 and #arounds == 1 and arounds[1].before == 65 and arounds[1].after == 0,
    "take right before the minute: what the kit gives back (59 -> 65) counts, 6 parts not 5, then 0")
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
T.Armor = armor

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

H.section("VehicleManager's action guard over our two actions")
local specs = {}
MinidoracatVehicleManagerAPI = { registerActionAdapter = function(spec) specs[#specs + 1] = spec end }
-- one event's handlers fired alone: the adapters they register, by class
local function fired(handlers)
    specs = {}
    for _, fn in ipairs(handlers) do fn() end
    local by = {}
    for _, s in ipairs(specs) do by[s.class] = s end
    return by, #specs
end
local probe = { part = te }
local function registersOurs(handlers)
    local by, n = fired(handlers)
    local sr, ss = by.ISMinidoracatTeslaRepairDriveUnit, by.ISMinidoracatTeslaTakeDriveUnitParts
    return n == 2 and sr ~= nil and ss ~= nil and sr.class == ISMinidoracatTeslaRepairDriveUnit.Type
        and ss.class == ISMinidoracatTeslaTakeDriveUnitParts.Type and sr.action == "REPAIR" and ss.action == "SALVAGE"
        and #sr.stages == 1 and sr.stages[1] == "complete" and #ss.stages == 1 and ss.stages[1] == "complete"
        and sr.vehicleOf(probe) == tv and sr.partOf(probe) == te and ss.vehicleOf({}) == nil
end
check(#onServer == 1 and registersOurs(onServer),
    "D1 OnServerStarted alone (a dedicated server): repair REPAIR, salvage SALVAGE, at complete")
check(#onGame == 1 and registersOurs(onGame), "D1 OnGameStart alone (SP, a client): repair REPAIR, salvage SALVAGE, at complete")
local byClass = fired(onGame) -- D3's guard below wraps these
local sr, ss = byClass.ISMinidoracatTeslaRepairDriveUnit, byClass.ISMinidoracatTeslaTakeDriveUnitParts
MinidoracatVehicleManagerAPI = nil
local quiet = pcall(onGame[1] or function() error("none") end)
MinidoracatVehicleManagerAPI = {}
quiet = quiet and pcall(onGame[1]) and pcall(onServer[1] or function() error("none") end)
check(quiet, "D2 no VehicleManager, or one without registerActionAdapter: nothing, no error")
MinidoracatVehicleManagerAPI = nil
-- VehicleManager's outer wrap (its ActionGuards.lua install/makeWrapper): canUse for the adapter's action; refused, false
local granted
local completeBefore = {}
for _, s in ipairs(specs) do
    local cls, inner = _G[s.class], _G[s.class].complete
    completeBefore[cls] = inner
    cls.complete = function(a) if s.action ~= granted then return false end return inner(a) end
end
granted = "REPAIR"
te.cond = 64
local dm = mechanic(6, 3)
check(ss and ISMinidoracatTeslaTakeDriveUnitParts:new(dm, te, wrench, 300):complete() == false and te.cond == 64
    and dm.inv.added == 0, "D3 REPAIR only: the salvage refused, condition and items untouched")
check(sr and ISMinidoracatTeslaRepairDriveUnit:new(dm, te, wrench, 300):complete() == true and te.cond > 64,
    "D3 REPAIR only: the repair runs")
granted = "SALVAGE"
local cond3 = te.cond
check(sr and ISMinidoracatTeslaRepairDriveUnit:new(mechanic(6, 3), te, wrench, 300):complete() == false and te.cond == cond3,
    "D3 SALVAGE only: the repair refused, condition untouched")
check(ss and ISMinidoracatTeslaTakeDriveUnitParts:new(mechanic(6, 0), te, wrench, 300):complete() == true and te.cond == 0,
    "D3 SALVAGE only: the salvage runs")
for cls, inner in pairs(completeBefore) do cls.complete = inner end

H.section("D4 the mechanics window asks VehicleManager before it queues (repair REPAIR, take SALVAGE)")
local globals = { "ISVehicleMenu", "VehicleUtils", "ItemTag", "ISVehiclePartMenu", "ISTimedActionQueue", "ISPathFindAction",
    "ISUnlockVehicleDoor", "ISOpenVehicleDoor", "ISCloseVehicleDoor", "HaloTextHelper", "MinidoracatVehicleManagerAPI" }
local before = {}
for i, g in ipairs(globals) do before[i] = rawget(_G, g) end
local queued, told, exited = {}, {}, 0
local function action(kind) return { new = function() return { kind = kind } end } end
ISVehicleMenu = { onExit = function() exited = exited + 1 end }
VehicleUtils = { getItems = function() return nil, { WRENCH = { wrench } } end, RequiredKeyNotFound = function() return true end }
ItemTag = { WRENCH = "WRENCH" }
ISVehiclePartMenu = { toPlayerInventory = function() end }
ISTimedActionQueue = { add = function(a) queued[#queued + 1] = a.kind or a.Type end }
ISPathFindAction = { pathToVehicleArea = function() return { kind = "path" } end }
ISUnlockVehicleDoor, ISOpenVehicleDoor, ISCloseVehicleDoor = action("unlock"), action("open"), action("close")
HaloTextHelper = { addBadText = function(chr, t) told[#told + 1] = { chr = chr, t = t } end }
-- the hood shut and locked, the mechanic seated, no key in hand (VehicleUtils.RequiredKeyNotFound above)
local hood = { locked = true, open = false }
function hood:isLocked() return self.locked end
function hood:isOpen() return self.open end
tv.parts.EngineDoor = { getId = function() return "EngineDoor" end, getVehicle = function() return tv end,
    getDoor = function() return hood end, getInventoryItem = function() return {} end }
local pm = mechanic(6, 1)
function pm:getVehicle() return tv end
function pm:getPlayerNum() return 0 end
function pm.inv:getFirstTypeRecurse() return {} end
local vmSays -- canUse's answer for each code
local vmAsks -- each question since ask(): code:query
local function ask(fn)
    queued, told, exited, vmAsks = {}, {}, 0, {}
    fn(pm, te)
    return table.concat(queued, ",")
end
local full = "path,unlock,open,"
MinidoracatVehicleManagerAPI = { canUse = function(_, _, code, ctx)
    vmAsks[#vmAsks + 1] = code .. ":" .. tostring(ctx and ctx.query)
    local a = vmSays[code] or { false, "NO_SHARE" }
    return a[1], a[2]
end }
vmSays = { REPAIR = { true, "OWNER" } }
local got = ask(DU.onTake)
check(got == "" and exited == 0 and hood.locked and not hood.open and #told == 1 and told[1].chr == pm
    and told[1].t == T.denyText("NOT_OWNER") and table.concat(vmAsks, ",") == "SALVAGE:true",
    "D4a SALVAGE refused, the hood shut and locked: nothing queued (no exit, unlock, open), still locked, the reason once; asked as a query")
vmSays = { REPAIR = { false, "RENT_LOCKED" }, SALVAGE = { true, "SHARED" } }
got = ask(DU.onRepair)
check(got == "" and exited == 0 and #told == 1 and told[1].t == T.denyText("RENT_LOCKED"),
    "D4b REPAIR refused for a rent lock: nothing queued, its own reason once")
vmSays = { SALVAGE = { true, "SHARED" } }
got = ask(DU.onTake)
check(got == full .. "ISMinidoracatTeslaTakeDriveUnitParts,close" and exited == 1 and #told == 0,
    "D4c SALVAGE granted: vanilla's queue (exit, walk, unlock, open, take, close), nothing said")
vmSays = { REPAIR = { true, "OWNER" } }
got = ask(DU.onRepair)
check(got == full .. "ISMinidoracatTeslaRepairDriveUnit,close" and #told == 0, "D4c REPAIR granted: vanilla's queue")
vmSays = { REPAIR = { true, "UNCLAIMED" }, SALVAGE = { true, "UNCLAIMED" } }
check(ask(DU.onTake) == full .. "ISMinidoracatTeslaTakeDriveUnitParts,close" and #told == 0, "D4d an unclaimed car: queued")
MinidoracatVehicleManagerAPI = nil
check(ask(DU.onTake) == full .. "ISMinidoracatTeslaTakeDriveUnitParts,close" and #told == 0, "D4d no VehicleManager: queued")
tv.parts.EngineDoor = nil
for i, g in ipairs(globals) do rawset(_G, g, before[i]) end
