-- Sentry Mode (server). Two tiers (user decision 2026-10-23):
--   touch (open door, unlock): stranger -> headlights flash 3 times + owner notified; legit user -> disarm.
--   break (smash window, hotwire, uninstall part): stranger -> vanilla alarm; sentry stays armed.
-- No polling: standby drain is settled on events (arm/disarm, touch, break, plug-in, vehicle load).
-- The only OnTick is the flash, added for its 2.4 s and removed when the last flash ends.
if isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/Inbox"

local T = MinidoracatTesla
local S = T.Sentry
T.ServerCommands = T.ServerCommands or {}

local function now() return getGameTime():getWorldAgeHours() end

-- Charge standby draw since the last settle; below MIN_PCT turn sentry off and tell the owner. A powered charger runs
-- standby (Battery.onCharger): free until `freeUntil` (world hour), by default until its power ended
-- (Charge.powerUntil: the grid shut-off, which an unloaded car can pass; without that module, while plugged in). On a
-- generator that standby costs its fuel (chg.fed, as Battery.draw).
function S.settle(vehicle, t, freeUntil)
    local part = T.Battery.part(vehicle)
    if not part then return end
    local md = part:getModData()
    local s = md.sentry
    if not s then return end
    t = t or now()
    local at = tonumber(s.at) or t
    local dt = math.max(0, t - at)
    if freeUntil == nil then
        local f = T.Charge and T.Charge.powerUntil
        if f then freeUntil = f(md.chg, t) elseif T.Battery.onCharger(part) then freeUntil = t end
    end
    local free = math.max(0, math.min(dt, (freeUntil or at) - at))
    local paid = dt - free
    if free > 0 and md.chg and md.chg.power == "generator" then md.chg.fed = (md.chg.fed or 0) + free * S.KW end
    local cur = T.Battery.kwh(part)
    local kwh = cur - paid * S.KW
    local floor = T.Battery.capacity(part) * S.MIN_PCT / 100
    local off = (freeUntil == nil or paid > 0) and kwh < floor
    if off then kwh = cur < floor and cur or floor end
    if kwh ~= cur then T.Battery.set(vehicle, part, kwh) end
    if off then
        md.sentry = nil
        T.log("sentry off low battery vid=" .. vehicle:getId())
        T.Inbox.notify(s.by, T.Inbox.entry(vehicle, "lowBattery", "sentry"))
    else
        s.at, s.kwh = t, kwh
    end
    T.Battery.topUp12V(vehicle) -- the vanilla alarm needs 12V > 0 (BaseVehicle.java:9397-9399)
    vehicle:transmitPartModData(part)
end

-- Already on: stays as it is. A fresh record would drop the standby drain since the last settle (`at`) and hand
-- the alerts to whoever pressed it again.
function S.arm(player, vehicle, remote)
    local part = T.Battery.part(vehicle)
    if part and part:getModData().sentry then return end
    local ok, why = S.canArm(player, vehicle, remote)
    if not ok then
        if why then T.deny(player, why, vehicle:getId()) end
        return
    end
    local md = part:getModData()
    if md.camp and T.Camp.stop then T.Camp.stop(vehicle, part) end
    -- Vanilla alarmed flag would turn a door pull into a full alarm (ISOpenVehicleDoor.lua:83-93);
    -- sentry decides the tier itself.
    vehicle:setAlarmed(false)
    vehicle:transmitAlarmed()
    local t = now()
    md.sentry = { by = T.account(player), at = t, kwh = T.Battery.kwh(part), since = t } -- by nil: nobody to tell
    T.Battery.topUp12V(vehicle)
    vehicle:transmitPartModData(part)
    T.log("sentry armed vid=" .. vehicle:getId() .. " by " .. player:getUsername())
end

function S.disarm(vehicle, who)
    local part = T.Battery.part(vehicle)
    if not part or not part:getModData().sentry then return end
    S.settle(vehicle)
    part:getModData().sentry = nil
    vehicle:transmitPartModData(part)
    T.log("sentry disarmed vid=" .. vehicle:getId() .. " by " .. tostring(who))
end

-- ------------------------------------------------------------------ headlight flash (touch tier)
-- Server toggles headlights + light parts; VehicleLights sync is ~100 ms (VehicleManager.java:128-152),
-- so 400 ms steps reach every client. setLightActive lights the ground, not only the lamp glass
-- (VehiclePart.java:725-729; parked cars only update parts whose light is already on, BaseVehicle.java:7874-7890).
S.FLASH_STEP_MS = 400
S.FLASH_TOGGLES = 6 -- on/off x3
S.stats = { flashes = 0, tickAdds = 0, tickRemoves = 0 }
local flashing = {} -- array of { v, id, n, nextAt, was, toggles }

local function setLights(v, on)
    v:setHeadlightsOn(on)
    for i = 0, v:getLightCount() - 1 do
        local lp = v:getLightByIndex(i)
        -- headlights only, like the engine's own switch (VehicleParts.java:373): the camp cabin light stays as it is
        if lp and lp:getId():find("Headlight") then lp:setLightActive(on) end
    end
end

local function flashTick()
    local t = getTimestampMs()
    for i = #flashing, 1, -1 do
        local f = flashing[i]
        if t >= f.nextAt then
            f.n = f.n + 1
            if f.n > f.toggles then
                setLights(f.v, f.was)
                table.remove(flashing, i)
                T.log("sentry flash done vid=" .. f.id)
            else
                setLights(f.v, f.n % 2 == 1)
                f.nextAt = t + S.FLASH_STEP_MS
            end
        end
    end
    if #flashing == 0 then
        Events.OnTick.Remove(flashTick)
        S.stats.tickRemoves = S.stats.tickRemoves + 1
        T.log("sentry flash OnTick removed (adds=" .. S.stats.tickAdds .. " removes=" .. S.stats.tickRemoves .. ")")
    end
end

function S.isFlashing(vehicle)
    local id = vehicle:getId()
    for i = 1, #flashing do
        if flashing[i].id == id then return true end
    end
    return false
end

-- toggles: on/off switches, default 3 flashes (key card / walk-away lock pass 2 or 4: KeyActions.lua)
function S.flash(vehicle, toggles)
    if S.isFlashing(vehicle) then return end
    flashing[#flashing + 1] = { v = vehicle, id = vehicle:getId(), n = 0, nextAt = 0, was = vehicle:getHeadlightsOn(),
        toggles = toggles or S.FLASH_TOGGLES }
    S.stats.flashes = S.stats.flashes + 1
    if #flashing == 1 then
        Events.OnTick.Add(flashTick)
        S.stats.tickAdds = S.stats.tickAdds + 1
    end
    T.log("sentry flash start vid=" .. vehicle:getId())
end

-- ------------------------------------------------------------------ triggers
local function armedState(vehicle)
    local part = vehicle and T.Battery.part(vehicle)
    return part and part:getModData().sentry
end

function S.onTouch(vehicle, actor, what, partId)
    if not armedState(vehicle) or not actor then return end
    S.settle(vehicle)
    local s = armedState(vehicle)
    if not s then return end
    if T.legit(actor, vehicle, s.by) then
        S.disarm(vehicle, actor:getUsername())
        return
    end
    -- the vanilla menu queues unlock then open (ISVehicleMenu.lua:1223-1232): one event per flash
    if S.isFlashing(vehicle) then return end
    S.flash(vehicle)
    T.Inbox.notify(s.by, T.Inbox.entry(vehicle, "touch", what, actor, partId))
end

function S.onBreak(vehicle, actor, what, partId)
    if not armedState(vehicle) or not actor then return end
    S.settle(vehicle)
    local s = armedState(vehicle)
    if not s or T.legit(actor, vehicle, s.by) then return end
    -- triggerAlarm only rings when alarmed and not previouslyEntered; setAlarmed(true) clears the latter
    -- (BaseVehicle.java:9379-9384, 9406-9413). Sentry itself stays in modData, i.e. re-armed.
    vehicle:setAlarmed(true)
    vehicle:triggerAlarm()
    vehicle:transmitAlarmed()
    -- the name is the client's own (respawn can pick any offline name); the account is what the owner's card shows
    T.log("sentry alarm vid=" .. vehicle:getId() .. " " .. what .. " by " .. actor:getUsername()
        .. " account=" .. tostring(T.account(actor) or "unverified"))
    T.Inbox.notify(s.by, T.Inbox.entry(vehicle, "break", what, actor, partId))
end

-- Wrap vanilla timed action complete() at load time; it runs on the server in MP
-- (NetTimedAction.java:132-134) and locally in SP. Loading now keeps VehicleManager's
-- OnServerStarted wrappers outside ours (R7 A3). A hook error must never break the vanilla action.
local function hook(cls, name, fn)
    if not cls or not cls.complete then
        T.log("sentry hook missing " .. name)
        return
    end
    local orig = cls.complete
    cls.complete = function(self)
        local r = orig(self)
        local ok, err = pcall(fn, self)
        if not ok then T.log("sentry hook " .. name .. " error " .. tostring(err)) end
        return r
    end
end

local function partId(part) return part and part:getId() or nil end

-- ISOpenVehicleDoor.lua:61, ISUnlockVehicleDoor.lua:55, ISSmashVehicleWindow.lua:55,
-- ISHotwireVehicle.lua:32, ISUninstallVehiclePart.lua:40 (media/lua/shared/Vehicles/TimedActions/)
hook(ISOpenVehicleDoor, "ISOpenVehicleDoor", function(a) S.onTouch(a.vehicle, a.character, "door", partId(a.part)) end)
hook(ISUnlockVehicleDoor, "ISUnlockVehicleDoor", function(a) S.onTouch(a.vehicle, a.character, "unlock", partId(a.part)) end)
hook(ISSmashVehicleWindow, "ISSmashVehicleWindow", function(a) S.onBreak(a.vehicle, a.character, "window", partId(a.part)) end)
hook(ISHotwireVehicle, "ISHotwireVehicle", function(a) S.onBreak(a.character:getVehicle(), a.character, "hotwire") end)
hook(ISUninstallVehiclePart, "ISUninstallVehiclePart", function(a) S.onBreak(a.vehicle, a.character, "part", partId(a.part)) end)

-- ------------------------------------------------------------------ commands
local function vehicleOf(args)
    local vid = args and tonumber(args.vid)
    return vid and getVehicleById(vid) or nil
end

T.ServerCommands.sentryArm = function(player, args)
    local v = vehicleOf(args)
    if player and v then S.arm(player, v) end
end

T.ServerCommands.sentryDisarm = function(player, args)
    local v = vehicleOf(args)
    if not (player and v) then return end
    local ok, why = S.canDisarm(player, v)
    if not ok then
        if why then T.deny(player, why, v:getId()) end
        return
    end
    S.disarm(v, player:getUsername())
end
