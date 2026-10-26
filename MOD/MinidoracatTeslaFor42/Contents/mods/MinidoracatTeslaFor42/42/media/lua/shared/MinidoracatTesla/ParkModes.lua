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
C.MAX_KMH = 1       -- "in Park": the HUD shows N below 1 km/h too (Liftgate.MAX_KMH)
C.HEATER_KW = 1.5   -- heater draw from the main pack while it heats or cools
C.COMFORT = 22      -- auto climate aims the cabin here (ClimateManager.java:716-744 pivots on 22 C too)
-- Heater "temperature" is the cabin's offset from outside; the vanilla knob only has these stops (ISVehicleACUI.lua:76-82)
C.KNOB = { -25, -15, -8, 0, 8, 15, 25 }
-- screen entertainment, boredom removed per GameTime multiplier unit (vanilla stat rates use the same unit,
-- BodyDamage.java:1916-1921). Vanilla TV: a BOR-1 line takes 5 boredom (ISRadioInteractions.lua:25), 32 % of the
-- 13166 broadcast lines carry BOR-1 (RadioData.xml) and a line airs for up to 300/1.25 = 240 units
-- (RadioChannel.java:221,244-248): about 5 per 757 units = 0.0066. The screen has no broadcast content: half of that.
C.BOREDOM_RATE = 0.0033

-- Auto climate: the knob stop that brings the cabin closest to C.COMFORT. The cabin sits on the square's air
-- temperature with the car (greenhouse above 22 C) plus the heater offset (ClimateManager.java:710-760).
function C.autoTemp(vehicle)
    local sq = vehicle:getSquare()
    if not sq then return 0 end
    local off = vehicle:getInsideTemperature() -- BaseVehicle.java:9801
    if sq:isInARoom() and off < 0 then off = 0 end -- indoors only a positive offset counts (:758)
    local need = C.COMFORT - (getClimateManager():getAirTemperatureForSquare(sq, vehicle) - off)
    local best = 0
    for _, k in ipairs(C.KNOB) do
        if math.abs(k - need) < math.abs(best - need) then best = k end
    end
    return best
end

-- Bed quality while camping: an average bed (vanilla rates every car seat a bad bed,
-- ISWorldObjectContextMenu.lua:2923-2934), with a pillow in hand or on the seat as vanilla checks. nil = not camping.
function C.bedType(player, vehicle)
    local part = vehicle and T.Battery.part(vehicle)
    if not (part and part:getModData().camp) then return nil end
    local function pillow(item) return item ~= nil and item:hasTag(ItemTag.PILLOW) end
    local has = pillow(player:getPrimaryHandItem()) or pillow(player:getSecondaryHandItem())
    if not has then
        local seat = vehicle:getPartForSeatContainer(vehicle:getSeat(player))
        local cont = seat and seat:getItemContainer()
        has = cont ~= nil and cont:containsTag(ItemTag.PILLOW)
    end
    return has and "averageBedPillow" or "averageBed"
end

-- Legit user of this car (sentry): the account that armed sentry, a holder of this car's key, or a VehicleManager
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
    -- a key left in the ignition is in nobody's hand: say so instead of NOT_OWNER (the owner's own key ends up there,
    -- see C.canEnable)
    if not T.legit(player, vehicle) then return false, vehicle:isKeysInIgnition() and "KEY_IN_IGNITION" or "NOT_OWNER" end
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
    -- seated: whoever may ride this car may run its climate. Not T.legit: starting the motor moves the driver's key from
    -- the inventory into the ignition (BaseVehicle.java:7484,7503 -> setKeysInIgnition :8647-8675) and the "leave key
    -- in ignition" option keeps it there after shutdown (:7556-7558), so the owner held no key and got NOT_OWNER
    -- (user 2026-10-25 playtest). VehicleManager's canUse still decides when it is installed.
    if not T.authorized(player, vehicle, "PASSENGER") then return false, "NOT_OWNER" end
    -- the real car offers Camp Mode only in Park (owner's manual, "Keep Climate On, Pet Mode, and Camp Mode"): a running
    -- motor is fine (C.start shuts it off in the same tap), a moving car is not
    if math.abs(vehicle:getCurrentSpeedKmHour()) > C.MAX_KMH then return false, "MOVING" end
    -- shutting the motor off stays the driver's call, like the vanilla shut-off (ISShutOffVehicleEngine.lua:5-8)
    if vehicle:isEngineRunning() and vehicle:getDriver() ~= player then return false, "NOT_DRIVER" end
    if T.Battery.pct(part) < C.minPct() then return false, "CAMP_LOW_BATTERY" end
    return true
end

function C.canDisable(player, vehicle)
    local part = T.Battery.part(vehicle)
    local c = part and part:getModData().camp
    if not c then return false end
    if player:getVehicle() ~= vehicle and not T.legit(player, vehicle, c.by) then return false, "NOT_OWNER" end
    return true
end
