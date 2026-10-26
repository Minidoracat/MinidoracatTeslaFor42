-- Drive battery (GasTank part, kWh): writers and part lua hooks. Server / SP only.
-- Part hooks run once per game minute on the server (VehicleParts.java:370-414); in SP the car may be a
-- VirtualVehicle, so hooks only use VehiclePartOwner methods (VirtualVehicle.java:185-336).
if isClient() then return end
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local B = T.Battery

T.MAX_ELAPSED = 10 -- cap per update: chunk reload hands in the whole unloaded time (GameTime.java:1374-1376)
T.V12_KWH = 15.5 * 6.9 / 1000 -- Model Y low voltage battery: lithium-ion 15.5 V, 6.9 Ah (owner's manual, R10)
T.DCDC_MIN_PCT = 5   -- the drive pack keeps the 12V topped up while it holds at least this much
T.BRAKE_WEAR = 0.5   -- regen does most of the braking (owner's manual, Maintenance Service Intervals)
T.InstallComplete = T.InstallComplete or {}

-- Clamp, store, and transmit only when it moved >= 1% of capacity (or hit empty / full).
function B.set(vehicle, part, kwh)
    local cap = B.capacity(part)
    if type(kwh) ~= "number" or kwh ~= kwh then kwh = 0 end
    kwh = math.max(0, math.min(kwh, cap))
    part:setContainerContentAmount(kwh) -- VehiclePart.java:387-408
    local md = part:getModData()
    local sent = md.sentKwh
    if type(sent) ~= "number" or math.abs(kwh - sent) >= cap / 100
        or (kwh == 0 and sent ~= 0) or (kwh == cap and sent ~= cap) then
        md.sentKwh = kwh
        vehicle:transmitPartModData(part) -- whole part modData, flag 16 (BaseVehicle.java:8225-8232)
    end
    return kwh
end

-- Add up to kwh without passing targetPct (0-100, default 100). Returns the kWh actually added.
function B.add(vehicle, kwh, targetPct)
    local part = B.part(vehicle)
    if not part or not part:getInventoryItem() or kwh <= 0 then return 0 end
    local cap = B.capacity(part)
    local limit = cap * math.max(0, math.min(100, targetPct or 100)) / 100
    local now = B.kwh(part)
    if now >= limit then return 0 end
    local after = B.set(vehicle, part, math.min(limit, now + kwh))
    return after - now
end

-- The car's own loads (climate, camp outlets, 12V, sentry): from the charger while it has power (B.onCharger), else
-- from the pack down to empty. Returns the kWh taken from the pack.
function B.draw(vehicle, part, kwh)
    if kwh <= 0 or B.onCharger(part) then return 0 end
    local now = B.kwh(part)
    return now - B.set(vehicle, part, now - kwh)
end

-- Refill the 12V battery from the drive pack (or the charger, B.draw). Returns the kWh taken from the pack.
function B.topUp12V(vehicle)
    local bat = vehicle:getBattery() -- VehiclePartOwner.java:76
    local item = bat and bat:getInventoryItem()
    local part = B.part(vehicle)
    if not item or not part then return 0 end
    local charge = item:getCurrentUsesFloat() -- same accessor as Vehicles.Update.Battery (Vehicles.lua:507)
    if charge >= 0.99 then return 0 end
    local need = (1 - charge) * T.V12_KWH
    local take = B.onCharger(part) and need or math.min(need, B.kwh(part))
    if take <= 0 then return 0 end
    local paid = B.draw(vehicle, part, take)
    item:setUsedDelta(math.min(1, charge + take / T.V12_KWH)) -- Vehicles.lua:515
    vehicle:transmitPartUsedDelta(bat)                      -- Vehicles.lua:517
    return paid
end

-- DC-DC converter: refill the 12V from the drive pack (>= DCDC_MIN_PCT, or any level on a powered charger) once it
-- drops below 95%.
-- Returns the kWh taken from the pack.
function B.dcdc(vehicle)
    local bat = vehicle:getBattery()
    local item = bat and bat:getInventoryItem()
    if not item or item:getCurrentUsesFloat() >= 0.95 then return 0 end
    local part = B.part(vehicle)
    if B.pct(part) < T.DCDC_MIN_PCT and not B.onCharger(part) then return 0 end
    return B.topUp12V(vehicle)
end

-- ---- part hooks ----

-- GasTank create: the pack item (VehicleUtils.createPartInventoryItem, Vehicles.lua:1153-1194), then a start charge.
function T.Create.Battery(vehicle, part)
    local item = VehicleUtils.createPartInventoryItem(part)
    if not item then return end
    local frac
    if SandboxVars.VehicleEasyUse then
        frac = 1
    elseif vehicle:isGoodCar() then -- Vehicles.lua:225-227
        frac = ZombRandFloat(0.6, 1)
    else
        frac = ZombRandFloat(0.05, 0.6)
    end
    B.set(vehicle, part, B.capacity(part) * frac)
    B.dcdc(vehicle) -- the 12V starts charged too (whichever of the two parts is created last does it)
end

-- Battery (12V) create: vanilla age-based charge (Vehicles.lua:120-130), then the DC-DC top-up.
function T.Create.Battery12V(vehicle, part)
    Vehicles.Create.Battery(vehicle, part)
    B.dcdc(vehicle)
end

-- GasTank install complete (server, ISInstallVehiclePart:complete). The charge rides on the pack item: uninstall
-- stores it (ISUninstallVehiclePart.lua:63) and install restores it (VehiclePart.java:184-193), clamped to the
-- item's int MaxCapacity. Clamp to the exact kWh and send the part modData.
function T.InstallComplete.Battery(vehicle, part)
    part:getModData().sentKwh = nil
    B.set(vehicle, part, B.kwh(part))
end

-- Engine create (new cars only): quality 100 so it starts first try in the cold (VehicleEngine.java:317,326-340), the
-- script engineForce (the one power each car has; vanilla repair() resets it to the same value, VehiclePart.java:999-1005);
-- loudness as vanilla Vehicles.Create.Engine (Vehicles.lua:279-287); a factory paint from the spec: skin index plus
-- the damage tint HSV. Parts are created after every engine skin / colour pick (random skin BaseVehicle.java:822-825,
-- zone or story skins IsoChunk.java:1346-1348 and RandomizedWorldBase.java:167-168 before addToWorld, script colour
-- :1575-1577; createParts :868), so this wins. Transmit as vanilla Commands.setHSV / setSkinIndex
-- (VehicleCommands.lua:440-455): server-only flag 4096 sends both (BaseVehicle.java:9209-9219, VehicleProperties.java:71-74).
function T.Create.Motor(vehicle, part)
    if not SandboxVars.VehicleEasyUse then part:setRandomCondition(nil) end
    local script = vehicle:getScript()
    local loud = (script:getEngineLoudness() or 100) * (SandboxVars.ZombieAttractionMultiplier or 1)
    vehicle:setEngineFeature(100, loud, script:getEngineForce())
    local s = T.spec(vehicle)
    local colors = s and s.colors
    if colors and #colors > 0 then
        local i = ZombRand(#colors) + 1
        local c = colors[i]
        vehicle:setSkinIndex(i - 1)
        vehicle:setColorHSV(c.h, c.s, c.v)
        vehicle:transmitSkinIndex()
        vehicle:transmitColorHSV()
    end
end

-- Brake update: vanilla wear (Vehicles.lua:709-718) run half the time.
function T.Update.Brakes(vehicle, part, elapsedMinutes)
    if ZombRandFloat(0, 1) < T.BRAKE_WEAR then Vehicles.Update.Brakes(vehicle, part, elapsedMinutes) end
end

-- GasTank update: drive draw minus brake regen, every game minute while the car's parts update; cable length check.
-- A plugged-in car stands still in Park, so its running motor is standby only, and that runs on a powered charger.
function T.Update.Battery(vehicle, part, elapsedMinutes)
    if not part:getInventoryItem() then return end
    local chg = part:getModData().chg
    if chg and T.Charge then T.Charge.checkCable(vehicle, part, chg) end
    local m = math.min(elapsedMinutes or 0, T.MAX_ELAPSED)
    if m <= 0 then return end
    local s = T.spec(vehicle)
    if not s then return end
    local used = 0
    if vehicle:isEngineRunning() and not B.onCharger(part) then
        local kmh = math.abs(vehicle:getCurrentSpeedKmHour())
        used = (s.idleKw + s.kwPerKmh * kmh) * m / 60 / T.rangeMul()
    end
    local regen = T.Regen and T.Regen.take(vehicle, s, used) or 0
    if used == 0 and regen == 0 then return end
    B.set(vehicle, part, B.kwh(part) - used + regen)
end

-- Engine update: vanilla temperature and needPartsUpdate shut-off (Vehicles.lua:526-560), then camp mode.
function T.Update.Engine(vehicle, part, elapsedMinutes)
    Vehicles.Update.Engine(vehicle, part, elapsedMinutes)
    local f = T.Camp and T.Camp.onEngineUpdate
    if f then f(vehicle, part, elapsedMinutes) end
end
