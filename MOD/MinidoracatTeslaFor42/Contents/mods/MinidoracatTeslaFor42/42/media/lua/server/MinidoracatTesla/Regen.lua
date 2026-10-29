-- Brake regen, no OnTick and no new packets.
-- MP: the driver's client sends vehicle/setStoplightsOn on press and release (CarController.java:866-889,
-- vanilla handler VehicleCommands.lua:123-129); we note the speed at both edges.
-- SP: no command is sent (CarController sets the lights directly), but the engine keeps the speed at which braking
-- started since the last part update (BaseVehicle.java:9110-9115, reset after updateParts :7868-7871).
-- The kinetic energy recovered is credited at the next battery update, capped by a budget fed by the energy used,
-- so accelerate/brake loops cannot make energy.
if isClient() then return end
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local R = {}
T.Regen = R

R.SHARE = 0.3      -- at most 30% of the energy used comes back
R.BUDGET_MAX = 0.5 -- kWh of unspent budget a car may hold, at the unit scale (x R.scale(), like the kinetic energy)

local pressKmh, pending, budget, keyOf = {}, {}, {}, {}

-- Vehicle ids are handed to other cars (BaseVehicle.java:793-801, VehicleIDMap.java:49-62): an id's entries belong to
-- the keyId noted with them, and another car under that id starts empty. A VirtualVehicle (SP, out of the loaded area,
-- VirtualVehicle.java) has no keyId and keeps the id its car had, which may be another car's by now (IsoChunk.java
-- 3232-3238 frees it on unload): no slot, so it neither clears nor takes that car's entries; nobody brakes it.
local function slot(vehicle)
    if not instanceof(vehicle, "BaseVehicle") then return nil end
    local id, k = vehicle:getId(), vehicle:getKeyId()
    if keyOf[id] ~= k then pressKmh[id], pending[id], budget[id], keyOf[id] = nil, nil, nil, k end
    return id
end

-- The drive draw is the calibrated coefficients (Core.lua DRIVE_SCALE, 10 x the 10-23 fit) times T.driveMul (vanilla
-- Gas Consumption / RangeMultiplier); the energy recovered gets the same factors, so braking gives back the same share
-- of the drive draw at any setting (2026-10-29 recalibration: unscaled it would have dropped to a tenth of that share).
function R.scale() return T.DRIVE_SCALE * T.driveMul() end

-- kWh recovered braking from v1 to v2 km/h
function R.kwh(spec, v1, v2)
    if not spec or v1 <= v2 then return 0 end
    local a, b = v1 / 3.6, v2 / 3.6
    return spec.regenEff * 0.5 * spec.massKg * (a * a - b * b) / 3600000 * R.scale()
end

-- brake pedal edge (MP)
function R.note(vehicle, on)
    local s = T.spec(vehicle)
    if not s then return end
    local id = slot(vehicle)
    if not id then return end
    local kmh = math.abs(vehicle:getCurrentSpeedKmHour())
    if on then
        pressKmh[id] = kmh
        return
    end
    local v1 = pressKmh[id]
    pressKmh[id] = nil
    if v1 then pending[id] = (pending[id] or 0) + R.kwh(s, v1, kmh) end
end

-- called by Update.Battery: returns the kWh to credit now
function R.take(vehicle, spec, used)
    local id = slot(vehicle)
    if not id then return 0 end
    local p = pending[id] or 0
    pending[id] = nil
    if not isServer() then
        local v1 = vehicle:getBrakeSpeedBetweenUpdate()
        if v1 > 0 then p = p + R.kwh(spec, v1, math.abs(vehicle:getCurrentSpeedKmHour())) end
    end
    local b = math.min(R.BUDGET_MAX * R.scale(), (budget[id] or 0) + used * R.SHARE)
    local credit = math.min(p, b)
    budget[id] = b - credit
    return credit
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "vehicle" or command ~= "setStoplightsOn" or type(args) ~= "table" then return end
    local v = player and player:getVehicle()
    if v and v:isDriver(player) and T.isTesla(v) then R.note(v, args.on == true) end
end)

return R
