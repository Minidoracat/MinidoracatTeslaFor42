-- Camp Mode (server). Heater keeps running with the motor off, drawing from the main pack; 12V is kept
-- topped up from the main pack while camp or sentry is on. Rides the vanilla per-game-minute part update:
-- the Engine part update (TeslaLogic) calls Camp.onEngineUpdate, which keeps needPartsUpdate on while
-- camping and turns camp off when the cabin is empty, the motor runs, or the pack drops below 20%.
if isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/Inbox"

local T = MinidoracatTesla
local C = T.Camp
T.Update = T.Update or {}
T.ServerCommands = T.ServerCommands or {}

local function heaterOff(vehicle)
    local h = vehicle:getPartById("Heater")
    if h and h:getModData().active and not vehicle:isEngineRunning() then
        h:getModData().active = false
        vehicle:transmitPartModData(h)
    end
end

function C.start(player, vehicle)
    local ok, why = C.canEnable(player, vehicle)
    if not ok then
        if why then T.deny(player, why, vehicle:getId()) end
        return
    end
    local part = T.Battery.part(vehicle)
    local md = part:getModData()
    if md.sentry then T.Sentry.disarm(vehicle, "camp") end -- the two modes are exclusive (Tesla manual)
    md.camp = { by = player:getUsername(), at = getGameTime():getWorldAgeHours() }
    -- engine shutdown switched the heater off (BaseVehicle.java:7469-7473); turn it back on
    local h = vehicle:getPartById("Heater")
    if h then
        local hd = h:getModData()
        hd.active = true
        if not tonumber(hd.temperature) or hd.temperature == 0 then hd.temperature = C.DEFAULT_TEMP end
        vehicle:transmitPartModData(h)
    end
    vehicle:setNeedPartsUpdate(true)
    vehicle:transmitPartModData(part)
    T.log("camp on vid=" .. vehicle:getId() .. " by " .. player:getUsername())
end

-- reason: nil (manual / motor started / sentry armed), "left", "lowBattery"
function C.stop(vehicle, part, reason)
    part = part or T.Battery.part(vehicle)
    local c = part and part:getModData().camp
    if not c then return end
    part:getModData().camp = nil
    heaterOff(vehicle)
    vehicle:transmitPartModData(part)
    T.log("camp off vid=" .. vehicle:getId() .. " " .. tostring(reason))
    if reason == "lowBattery" then
        T.Inbox.notify(c.by, T.Inbox.entry(vehicle, "lowBattery", "camp"))
    end
end

-- Called at the end of MinidoracatTesla.Update.Engine (architecture.md section 5).
-- needPartsUpdate is not saved and vanilla clears it when the engine is cold (Vehicles.lua:557-559).
function C.onEngineUpdate(vehicle, part, minutes)
    local bp = vehicle:getPartById("GasTank")
    if not bp or not bp:getModData().camp then return end
    if vehicle:isEngineRunning() then return C.stop(vehicle, bp) end
    -- no exit event on the server (VehicleExitPacket.java:68-73; OnExitVehicle is client-only).
    -- SP may hand in a VirtualVehicle (unloaded car, VirtualVehicle.java) that has no hasPassenger: nobody inside.
    if not vehicle.hasPassenger or not vehicle:hasPassenger() then return C.stop(vehicle, bp, "left") end
    if T.Battery.pct(bp) < C.MIN_PCT then return C.stop(vehicle, bp, "lowBattery") end
    vehicle:setNeedPartsUpdate(true)
end

-- Vehicle (re)load after restart or chunk reload: needPartsUpdate starts false (BaseVehicle.java:380),
-- so a camping car would never update again. Re-enable; the next engine update checks occupants.
Events.OnSpawnVehicleEnd.Add(function(vehicle) -- BaseVehicle.java:904
    local bp = vehicle:getPartById("GasTank")
    if bp and bp:getModData().camp then vehicle:setNeedPartsUpdate(true) end
end)

local function drawMain(vehicle, kwh)
    local p = T.Battery.part(vehicle)
    if not p or kwh <= 0 then return end
    local left = T.Battery.kwh(p) - kwh
    T.Battery.set(vehicle, p, left > 0 and left or 0)
end

-- Heater part update: vanilla Vehicles.Update.Heater (Vehicles.lua:577-623) with an EV heat pump:
-- powered when the motor runs or camp is on, no engine-temperature gate, draws the main pack not the 12V.
local heaterMinutes = {} -- per vehicle id, vanilla's sync throttle (Vehicles.elaspedMinutesForHeater)
function T.Update.Heater(vehicle, part, elapsedMinutes)
    local pc = vehicle:getPartById("PassengerCompartment")
    if not pc then return end
    local pcData = pc:getModData()
    if not tonumber(pcData.temperature) then pcData.temperature = 0.0 end
    local hd = part:getModData()
    if not tonumber(hd.temperature) then hd.temperature = 0 end
    local target = hd.temperature
    local bp = vehicle:getPartById("GasTank")
    local powered = vehicle:isEngineRunning() or (bp ~= nil and bp:getModData().camp ~= nil)
    local previous = pcData.temperature
    local running = hd.active and powered -- the Heater part has no item (template_heater.txt), like vanilla
    if running and target > 0 and pcData.temperature < target then
        pcData.temperature = math.min(pcData.temperature + elapsedMinutes, target)
    elseif running and target < 0 and pcData.temperature > target then
        pcData.temperature = math.max(pcData.temperature - elapsedMinutes, target)
    elseif not (running and target ~= 0) then
        if pcData.temperature > 0 then
            pcData.temperature = math.max(pcData.temperature - 0.1 * elapsedMinutes, 0)
        else
            pcData.temperature = math.min(pcData.temperature + 0.1 * elapsedMinutes, 0)
        end
    end
    if running then drawMain(vehicle, C.HEATER_KW * elapsedMinutes / 60) end
    -- same sync throttle as vanilla: rounded value moved and more than 2 minutes since the last send
    local id = vehicle:getId()
    local acc = (heaterMinutes[id] or 0) + elapsedMinutes
    heaterMinutes[id] = acc
    if isServer() and acc > 2 and VehicleUtils.compareFloats(previous, pcData.temperature, 2) then
        heaterMinutes[id] = 0
        vehicle:transmitPartModData(pc)
    end
end

-- Battery (12V) part update: vanilla first, then keep it topped up from the main pack while parked in
-- camp or sentry (radio, lights and the alarm all need 12V > 0: VehiclePart.java:744-746, BaseVehicle.java:9398).
function T.Update.Battery12V(vehicle, part, elapsedMinutes)
    Vehicles.Update.Battery(vehicle, part, elapsedMinutes)
    local bp = vehicle:getPartById("GasTank")
    local md = bp and bp:getModData()
    if not md or not (md.camp or md.sentry) then return end
    local item = part:getInventoryItem()
    if item and item:getCurrentUsesFloat() < 0.95 then T.Battery.topUp12V(vehicle) end
end

-- ------------------------------------------------------------------ commands
local function vehicleOf(args)
    local vid = args and tonumber(args.vid)
    return vid and getVehicleById(vid) or nil
end

T.ServerCommands.campOn = function(player, args)
    local v = vehicleOf(args)
    if player and v then C.start(player, v) end
end

T.ServerCommands.campOff = function(player, args)
    local v = vehicleOf(args)
    if not (player and v) then return end
    local ok, why = C.canDisable(player, v)
    if not ok then
        if why then T.deny(player, why, v:getId()) end
        return
    end
    C.stop(v)
end
