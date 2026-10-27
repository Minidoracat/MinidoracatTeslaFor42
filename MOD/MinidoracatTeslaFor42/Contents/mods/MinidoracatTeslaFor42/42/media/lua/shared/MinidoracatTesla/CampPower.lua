-- Camp Mode outlets and cabin light (shared).
-- Outlets: Camp Mode keeps the USB ports and the 12V socket powered (owner's manual, "Keep Climate On, Pet Mode, and
-- Camp Mode"), so a seated player charges dry cells and car batteries from the drive pack. Timed action; the energy
-- moves in complete() (what the item needs) or, when interrupted, in serverStop / SP stop() (charging time so far).
-- Complete() and serverStop() run on the server only (LuaTimedActionNew.java:164-170, NetTimedAction.java:94-115).
-- Cabin light: part CabinLight (vehicle template). The engine draws every light part of every loaded car each frame
-- (LightingJNI.java:467-474) and drops the light with the car (:476-484); VehicleLights syncs it (setLightActive,
-- VehiclePart.java:725-729). The server switches it with camp (Camp.lua C.start / C.stop).
require "TimedActions/ISBaseTimedAction"
require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"

local T = MinidoracatTesla
local C = T.Camp
T.Init = T.Init or {}

-- kwh: full charge, kw: charging power.
-- Dry cell: AA NiMH 1.2 V x 2.5 Ah = 3 Wh, charged at 0.5 C from USB: 2 h from empty.
-- Car battery: 12 V x 60 Ah = 0.72 kWh, from the 12V socket's "12A continuous draw" (the same on both cars: Model Y
-- owner's manual, Interior Electronics, GUID-A1DF67DE; tesla.cn Model 3 owner's manual 2026 p.14, 12A continuous /
-- 16A peak): 0.144 kW, 5 h from empty (vanilla's car battery charger: 6 h, IsoCarBatteryCharger.java:39).
local CELL = { kwh = 0.003, kw = 0.0015 }
local CAR = { kwh = 0.72, kw = 0.144 }
C.Chargeable = {
    ["Base.Battery"] = CELL,
    ["Base.CarBattery1"] = CAR,
    ["Base.CarBattery2"] = CAR,
    ["Base.CarBattery3"] = CAR,
}

-- kWh the item still takes (0: full or not chargeable)
function C.itemNeed(item)
    local s = item and C.Chargeable[item:getFullType()]
    if not s then return 0 end
    return math.max(0, 1 - item:getCurrentUsesFloat()) * s.kwh
end

function C.canChargeItem(player, vehicle, item)
    local part = T.Battery.part(vehicle)
    if not part then return false end
    if player:getVehicle() ~= vehicle then return false, "NOT_INSIDE" end
    if not part:getModData().camp then return false, "NOT_CAMPING" end
    if T.Battery.pct(part) < C.minPct() and not T.Battery.onCharger(part) then return false, "CAMP_LOW_BATTERY" end
    if C.itemNeed(item) <= 0 then return false, "FULL" end
    return true
end

-- Server / SP: move up to `hours` of charging (nil: all it needs) from the drive pack (or a powered charger,
-- Battery.draw) into the item. Returns kWh.
-- The item keeps whole uses (setCurrentUsesFloat rounds to UseDelta, DrainableComboItem.java:83-87; a dry cell is
-- 0.007 per use), so the pack pays for what the item actually gained.
function C.chargeItem(player, vehicle, item, hours)
    local part = T.Battery.part(vehicle)
    local s = item and C.Chargeable[item:getFullType()]
    if not part or not s then return 0 end
    local kwh = C.itemNeed(item)
    if hours then kwh = math.min(kwh, s.kw * hours) end
    if not T.Battery.onCharger(part) then kwh = math.min(kwh, T.Battery.kwh(part)) end
    if kwh <= 0 then return 0 end
    local before = item:getCurrentUsesFloat()
    item:setUsedDelta(math.min(1, before + kwh / s.kwh)) -- Vehicles.lua:515
    kwh = math.max(0, item:getCurrentUsesFloat() - before) * s.kwh
    if kwh <= 0 then return 0 end
    T.Battery.draw(vehicle, part, kwh)
    syncItemFields(player, item) -- ISGetCompost.lua:48-49
    T.log(string.format("camp outlet vid=%d %s +%.6f kWh -> %.4f", vehicle:getId(), item:getFullType(), kwh,
        item:getCurrentUsesFloat()))
    return kwh
end

-- CabinLight part init (both sides, every load: VehicleLight saves only active/offset/intensity/dist,
-- VehicleLight.java:85-102). Car centre, dot -1 = all round, 3000 K warm white (255,180,107). Radius 6 / 0.5
-- (user 2026-10-26 「亮一點」): ground next to the car ~1.5x the old 4 / 0.35 and lit 2 tiles further.
C.LIGHT_DIST = 6
C.LIGHT_INTENSITY = 0.5
function T.Init.CabinLight(vehicle, part)
    part:createSpotLightColor(0, 0, C.LIGHT_DIST, C.LIGHT_INTENSITY, -1, 0, 1.0, 0.706, 0.42)
end

-- Server: camp on / off switches the cabin light (Camp.lua).
function C.cabinLight(vehicle, on)
    local p = vehicle:getPartById("CabinLight")
    if p then p:setLightActive(on) end
end

-- ------------------------------------------------------------------ timed action
ISMinidoracatTeslaChargeItem = ISBaseTimedAction:derive("ISMinidoracatTeslaChargeItem")

function ISMinidoracatTeslaChargeItem:isValid()
    return C.canChargeItem(self.character, self.vehicle, self.item) == true
end

-- server (MP serverStart) or SP (start): the authoritative check and the clock. Locals, not methods: begin() and
-- friends are ISBaseTimedAction's own (ISBaseTimedAction.lua:83).
local function open(a)
    a.t0 = T.hours()
    local ok, why = C.canChargeItem(a.character, a.vehicle, a.item)
    if ok and not a.character:getInventory():containsRecursive(a.item) then ok, why = false, nil end
    a.ok = ok == true
    if not ok and why then T.deny(a.character, why, a.vehicle:getId()) end
end

-- full: completed, the item gets all it needs; otherwise the charging time so far
local function close(a, full)
    if not a.ok or a.done then return end
    a.done = true
    C.chargeItem(a.character, a.vehicle, a.item, not full and (T.hours() - a.t0) or nil)
end

function ISMinidoracatTeslaChargeItem:start()
    if not isClient() then open(self) end
end

function ISMinidoracatTeslaChargeItem:serverStart()
    open(self)
end

function ISMinidoracatTeslaChargeItem:stop()
    if not isClient() then close(self, false) end
    ISBaseTimedAction.stop(self)
end

function ISMinidoracatTeslaChargeItem:serverStop()
    close(self, false)
end

function ISMinidoracatTeslaChargeItem:perform()
    ISBaseTimedAction.perform(self)
end

function ISMinidoracatTeslaChargeItem:complete()
    close(self, true)
    return true
end

-- charging time in game minutes -> action time, as ISReadABook:getDuration (ISReadABook.lua:457-458)
function ISMinidoracatTeslaChargeItem:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    local s = C.Chargeable[self.item:getFullType()]
    local hours = s and C.itemNeed(self.item) / s.kw or 0
    return math.max(1, hours * 60 * getGameTime():getMinutesPerDay() * 2)
end

function ISMinidoracatTeslaChargeItem:new(character, vehicle, item)
    local o = ISBaseTimedAction.new(self, character)
    o.vehicle = vehicle
    o.item = item
    o.maxTime = o:getDuration()
    return o
end
