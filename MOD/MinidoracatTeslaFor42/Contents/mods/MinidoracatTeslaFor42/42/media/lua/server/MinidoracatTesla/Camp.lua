-- Camp Mode (server). Heater keeps running with the motor off, drawing from the main pack, with auto climate
-- (heat or cool toward C.COMFORT unless the player set the knob); the 12V part update (DC-DC top-up) also lives here.
-- Rides the vanilla per-game-minute part update: the Engine part update (TeslaLogic) calls Camp.onEngineUpdate, which
-- keeps needPartsUpdate on while camping, eases the boredom of everyone awake inside (the screen), and turns camp off
-- when the cabin is empty, the motor runs, or the pack drops below the sandbox limit (C.minPct).
if isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/CampPower"
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
    -- one tap from a running car, like shifting into Park: the vanilla shut-off (ISShutOffVehicleEngine.lua:30). Its
    -- ShuttingDown switches the heater off on the spot (BaseVehicle.java:7469-7473, SP :7560-7563), so it goes first;
    -- MP clients parse the engine state before part modData in one update packet (VehicleUpdatePacket.java:104,124)
    if vehicle:isEngineRunning() then vehicle:shutOff() end
    -- engine shutdown switched the heater off; turn it back on
    local h = vehicle:getPartById("Heater")
    if h then
        local hd = h:getModData()
        hd.active = true
        -- auto climate unless the player set the knob: nothing set yet, or still the stop auto climate picked last time
        if not tonumber(hd.temperature) or hd.temperature == 0 or hd.temperature == hd.auto then
            hd.temperature = C.autoTemp(vehicle)
            hd.auto = hd.temperature
        else
            hd.auto = nil
        end
        vehicle:transmitPartModData(h)
    end
    C.cabinLight(vehicle, true)
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
    C.cabinLight(vehicle, false)
    vehicle:transmitPartModData(part)
    T.log("camp off vid=" .. vehicle:getId() .. " " .. tostring(reason))
    if reason == "lowBattery" then
        local e = T.Inbox.entry(vehicle, "lowBattery", "camp")
        e.pct = C.minPct() -- the card title's %1
        T.Inbox.notify(c.by, e)
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
    if T.Battery.pct(bp) < C.minPct() then return C.stop(vehicle, bp, "lowBattery") end
    vehicle:setNeedPartsUpdate(true)
    -- the screen: boredom eases for everyone awake inside (asleep: no TV either, ISRadioInteractions.lua:189). Stats are
    -- the server's in MP (IsoPlayer.java:3046-3050) and reach the client with the periodic PlayerStats packet
    -- (NetworkPlayerManager.java:34-35). C.BOREDOM_RATE is per GameTime multiplier unit, which sums to 48 per real
    -- second (0.8 x fpsMultiplier 60/fps per frame: GameTime.java:986, FPSTracking.java:39); a game minute lasts
    -- minutesPerDay x 60 / 1440 real seconds.
    local units = 48 * minutes * getGameTime():getMinutesPerDay() * 60 / 1440
    for i = 0, vehicle:getMaxPassengers() - 1 do
        local chr = vehicle:getCharacter(i)
        if chr and not chr:isAsleep() then chr:getStats():remove(CharacterStat.BOREDOM, C.BOREDOM_RATE * units) end
    end
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
    local bp = vehicle:getPartById("GasTank")
    local camp = bp ~= nil and bp:getModData().camp ~= nil
    if camp and hd.auto ~= nil then
        if hd.temperature ~= hd.auto then
            hd.auto = nil -- the player turned the knob (vanilla toggleHeater, VehicleCommands.lua:91-99): theirs from now on
        else
            local t = C.autoTemp(vehicle) -- day and night: follow the outside air
            if t ~= hd.auto then
                hd.temperature, hd.auto = t, t
                vehicle:transmitPartModData(part)
            end
        end
    end
    local target = hd.temperature
    local powered = vehicle:isEngineRunning() or camp
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
    if running and target ~= 0 then drawMain(vehicle, C.HEATER_KW * elapsedMinutes / 60) end
    -- same sync throttle as vanilla: rounded value moved and more than 2 minutes since the last send
    local id = vehicle:getId()
    local acc = (heaterMinutes[id] or 0) + elapsedMinutes
    heaterMinutes[id] = acc
    if isServer() and acc > 2 and VehicleUtils.compareFloats(previous, pcData.temperature, 2) then
        heaterMinutes[id] = 0
        vehicle:transmitPartModData(pc)
    end
end

-- Battery (12V) part update: vanilla first, then the DC-DC top-up from the main pack whenever it holds >= 5%
-- (Battery.lua B.dcdc; radio, lights and the alarm all need 12V > 0: VehiclePart.java:744-746, BaseVehicle.java:9398).
-- A parked car runs part updates once a driver sits down (BaseVehicle.java:1806-1808), so a long-parked Tesla
-- with a charged pack starts; camp and sentry keep updates on while parked.
function T.Update.Battery12V(vehicle, part, elapsedMinutes)
    Vehicles.Update.Battery(vehicle, part, elapsedMinutes)
    T.Battery.dcdc(vehicle)
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

-- MP sleep in a car: the client picks the bed quality (ISWorldObjectContextMenu.lua:1058,1085; our client wraps
-- getBedQuality) and only tells the server "asleep" (player/onVehicleSleep, server/ClientCommands.lua:636-639), but the
-- sleep itself is the server's: fatigue recovery reads the server copy's bed type (IsoPlayer.java:3046-3050,3080-3097)
-- and the stats sync back. Vanilla never sets that copy (IsoGameCharacter.java:628 default "averageBed"), so put the
-- client's camping value there too, and the default back when sleeping in a car without camp.
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "player" or command ~= "onVehicleSleep" or not (args and args.isAsleep) or not player then return end
    local v = player:getVehicle()
    player:setBedType(C.bedType(player, v) or "averageBed")
end)
