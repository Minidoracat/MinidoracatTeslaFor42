-- Sentry and Camp rules shared by the server handlers and the client menus (radial, context menu).
-- State lives in the battery part (GasTank) modData: sentry = { by, at, kwh }, camp = { by, at }.
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
T.Sentry = T.Sentry or {}
T.Camp = T.Camp or {}
local S, C = T.Sentry, T.Camp

S.MIN_PCT = 20      -- arm needs >= 20%; settle turns sentry off below it (Tesla owner's manual)
S.KW = 0.25         -- standby draw, kW of game time
S.RANGE = 10        -- arm/disarm from outside: tiles between player and car
C.MIN_PCT = 20
C.HEATER_KW = 1.5   -- heater draw from the main pack while it runs
C.DEFAULT_TEMP = 15 -- heater knob value when the player never set one (ISVehicleACUI.lua:76-82 knob stops)

-- Legit user of this car: the account that armed sentry, a holder of this car's key, or a VehicleManager
-- user with PASSENGER rights on a claimed car. T.authorized also says yes for UNCLAIMED (VehicleManager),
-- EASY_USE (sandbox VehicleEasyUse) and keys left in the ignition ("KEY" without a key in hand); none of
-- those count here, otherwise any stranger pulling the door handle would disarm sentry.
function T.legit(player, vehicle, by)
    if by and player:getUsername() == by then return true end
    if player:getInventory():haveThisKeyId(vehicle:getKeyId()) then return true end -- ISOpenVehicleDoor.lua:86
    local ok, why = T.authorized(player, vehicle, "PASSENGER")
    return ok == true and why ~= "UNCLAIMED" and why ~= "EASY_USE" and why ~= "KEY"
end

function S.canArm(player, vehicle)
    local part = T.Battery.part(vehicle)
    if not part then return false end
    if player:getVehicle() then return false, "OCCUPIED" end
    if player:DistTo(vehicle) > S.RANGE then return false, "TOO_FAR" end
    if not T.legit(player, vehicle) then return false, "NOT_OWNER" end
    if vehicle:isEngineRunning() then return false, "ENGINE_ON" end
    if vehicle:hasPassenger() then return false, "OCCUPIED" end
    if not vehicle:areAllDoorsLocked() then return false, "UNLOCKED" end
    if T.Battery.pct(part) < S.MIN_PCT then return false, "LOW_BATTERY" end
    return true
end

function S.canDisarm(player, vehicle)
    local part = T.Battery.part(vehicle)
    local s = part and part:getModData().sentry
    if not s then return false end
    if player:getVehicle() ~= vehicle and player:DistTo(vehicle) > S.RANGE then return false, "TOO_FAR" end
    if not T.legit(player, vehicle, s.by) then return false, "NOT_OWNER" end
    return true
end

function C.canEnable(player, vehicle)
    local part = T.Battery.part(vehicle)
    if not part then return false end
    if player:getVehicle() ~= vehicle then return false, "NOT_INSIDE" end
    if not T.legit(player, vehicle) then return false, "NOT_OWNER" end
    if vehicle:isEngineRunning() then return false, "ENGINE_ON" end
    if T.Battery.pct(part) < C.MIN_PCT then return false, "LOW_BATTERY" end
    return true
end

function C.canDisable(player, vehicle)
    local part = T.Battery.part(vehicle)
    local c = part and part:getModData().camp
    if not c then return false end
    if player:getVehicle() ~= vehicle and not T.legit(player, vehicle, c.by) then return false, "NOT_OWNER" end
    return true
end
