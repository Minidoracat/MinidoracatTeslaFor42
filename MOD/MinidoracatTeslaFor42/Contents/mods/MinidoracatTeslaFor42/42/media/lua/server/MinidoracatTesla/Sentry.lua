-- Sentry Mode (server). Two tiers (user decision 2026-10-23):
--   touch (open door, unlock): stranger -> headlights flash 3 times + owner notified; legit user -> disarm.
--   break (smash window, hotwire, uninstall part, tow; any window losing condition): stranger -> vanilla alarm;
--   sentry stays armed.
-- No polling: standby drain is settled on events (arm/disarm, touch, break, plug-in, vehicle load). Windows hit with no
-- event (weapons in SP, zombies, crashes) are found by one look a game minute at the armed, loaded cars (S.scan).
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
    if free > 0 and md.chg and md.chg.power ~= "grid" then md.chg.fed = (md.chg.fed or 0) + free * S.KW end
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
    S.markWindows(vehicle)
    S.armed[vehicle:getId()] = true
    S.forget(vehicle:getId())
    T.Battery.topUp12V(vehicle)
    vehicle:transmitPartModData(part)
    T.log("sentry armed vid=" .. vehicle:getId() .. " by " .. player:getUsername())
end

function S.disarm(vehicle, who)
    local part = T.Battery.part(vehicle)
    if not part or not part:getModData().sentry then return end
    S.settle(vehicle)
    part:getModData().sentry = nil
    S.forget(vehicle:getId())
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

-- The window baseline (sentry.win: part id -> condition at the last check), taken on arming and after every alert, so
-- the scan never counts a hit twice (Armor Glass takes 3: Truck.lua).
function S.markWindows(vehicle)
    local s = armedState(vehicle)
    if not s then return end
    local win = {}
    for i = 0, vehicle:getPartCount() - 1 do
        local p = vehicle:getPartByIndex(i)
        if p:getWindow() then win[p:getId()] = p:getCondition() end -- VehicleWindow health = part condition (VehicleWindow.java:30-36)
    end
    s.win = win
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

-- actor nil: a window found broken by the scan with nobody to blame (a crash, a zombie, a weapon in SP); the alert
-- names nobody (Inbox.entry). A legit actor (the owner fixing or smashing their own glass) only moves the baseline.
function S.onBreak(vehicle, actor, what, partId)
    if not armedState(vehicle) then return end
    S.settle(vehicle)
    local s = armedState(vehicle)
    if not s then return end
    if actor and T.legit(actor, vehicle, s.by) then return S.markWindows(vehicle) end
    -- triggerAlarm only rings when alarmed and not previouslyEntered; setAlarmed(true) clears the latter
    -- (BaseVehicle.java:9379-9384, 9406-9413). Sentry itself stays in modData, i.e. re-armed.
    vehicle:setAlarmed(true)
    vehicle:triggerAlarm()
    vehicle:transmitAlarmed()
    -- the name is the client's own (respawn can pick any offline name); the account is what the owner's card shows
    T.log("sentry alarm vid=" .. vehicle:getId() .. " " .. what .. " by " .. (actor and actor:getUsername() or "-")
        .. " account=" .. tostring(actor and (T.account(actor) or "unverified") or "-"))
    T.Inbox.notify(s.by, T.Inbox.entry(vehicle, "break", what, actor, partId))
    S.markWindows(vehicle) -- this hit is the new baseline: the next scan does not count it again
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

-- ISOpenVehicleDoor.lua:61, ISUnlockVehicleDoor.lua:55, ISHotwireVehicle.lua:32, ISUninstallVehiclePart.lua:40
-- (media/lua/shared/Vehicles/TimedActions/), ISSmashWindow.lua:46 (media/lua/shared/TimedActions/)
hook(ISOpenVehicleDoor, "ISOpenVehicleDoor", function(a) S.onTouch(a.vehicle, a.character, "door", partId(a.part)) end)
hook(ISUnlockVehicleDoor, "ISUnlockVehicleDoor", function(a) S.onTouch(a.vehicle, a.character, "unlock", partId(a.part)) end)
-- Smashing a car window is ISSmashWindow(player, window, part): ISVehiclePartMenu.onSmashWindow (:367-378), from the
-- outside radial (ISVehicleMenu.lua:343-351) and the mechanics window (ISVehicleMechanics.lua:286). Vanilla never queues
-- ISSmashVehicleWindow (no caller in media/lua or the Java). The window's own car (window:getPart(), not the action's
-- part field). Every hit is a break attempt: Armor Glass (Truck.lua, wrapped from shared, so its hit has landed by now)
-- rings on the first of its 3 hits, `windowHit` while the glass holds, `window` once it is gone. A window still
-- rolled down and whole was not hit (Truck.lua refuses it on an armoured car).
hook(ISSmashWindow, "ISSmashWindow", function(a)
    local w = a.window
    if not instanceof(w, "VehicleWindow") then return end -- a house window
    if w:isOpen() and not w:isDestroyed() then return end
    local part = w:getPart()
    S.onBreak(part:getVehicle(), a.character, w:isDestroyed() and "window" or "windowHit", part:getId())
end)
hook(ISHotwireVehicle, "ISHotwireVehicle", function(a) S.onBreak(a.character:getVehicle(), a.character, "hotwire") end)
hook(ISUninstallVehiclePart, "ISUninstallVehiclePart", function(a) S.onBreak(a.vehicle, a.character, "part", partId(a.part)) end)
-- Fitting glass is no break, whoever does it: the installed part takes the item's condition (VehiclePart.java:202;
-- uninstalling left the old one, :215-222), so a worse pane would read as a hit on the next scan. That window only, and
-- only when it went in: a failed skill check also returns true from complete (ISInstallVehiclePart.lua:102-114,120)
-- and must not wash out a break the scan has not seen yet.
hook(ISInstallVehiclePart, "ISInstallVehiclePart", function(a)
    local s, part = armedState(a.vehicle), a.part
    if s and s.win and part and part:getWindow() and a.item and part:getInventoryItem() == a.item then
        s.win[part:getId()] = part:getCondition()
    end
end)

-- ------------------------------------------------------------------ windows without an event, towing
-- Every window loss ends in VehicleWindow.damage (VehicleWindow.java:76-109): weapons (BaseVehicle.processHit,
-- :11307-11366), zombies (AttackVehicleState.java:123-166), crashes (addDamageFront / Rear, BaseVehicle.java:4813-4888).
-- None has a Lua event, and its own alarm check is off while sentry is armed (setAlarmed(false) in S.arm). A parked,
-- empty car's parts stop updating (Vehicles.lua:557-559), so once a game minute (GameTime.java:637-643, both sides;
-- about 3.75 s at the default day length) the armed, loaded cars compare their windows with the baseline: lower = a
-- break ("window" once the glass is gone), higher (repaired, new glass) = a new baseline only. An empty list costs
-- one loop with nothing in it, like Store.lua's scan.
S.armed = {}   -- vehicle id -> true: armed and loaded (S.arm, OnSpawnVehicleEnd); dropped on the next scan once not
S.lastHit = {} -- vehicle id -> { account = T.account, at = world hour }: the last trusted MP weapon hit (damageWindow)
S.HIT_HOURS = 2 / 60 -- the server's own PlayerHitVehicle pass may take more glass later with no event: same player
S.tow = {}     -- vehicle id -> world hour of the last tow report (attachTrailer below)

-- per-car memory keyed by id (ids are reused, VehicleIDMap.java:49-62): cleared on arm, disarm, load, leaving the list
function S.forget(id) S.lastHit[id], S.tow[id] = nil, nil end

-- SP: vanilla's smash breaks the glass mid-swing in Java (SmashWindowState.java:120-125) and complete (our hook, with
-- the name) runs after the animation. A scan in between would ring once more naming nobody: skip the car until then.
function S.smashing(vehicle)
    if isServer() or isClient() or not ISTimedActionQueue then return false end
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        local q = p and ISTimedActionQueue.getTimedActionQueue(p).queue -- the running action is first (ISTimedActionQueue.lua:39-44)
        local a = q and q[1]
        if a and a.Type == "ISSmashWindow" and instanceof(a.window, "VehicleWindow")
            and a.window:getPart():getVehicle() == vehicle then return true end
    end
    return false
end

function S.checkWindows(vehicle, actor)
    local s = armedState(vehicle)
    if not s then return end
    if not s.win then return S.markWindows(vehicle) end -- armed before windows were watched
    local hitId, hitCond
    for i = 0, vehicle:getPartCount() - 1 do
        local p = vehicle:getPartByIndex(i)
        if p:getWindow() then
            local id, c = p:getId(), p:getCondition()
            local was = s.win[id]
            if was and c < was then
                if not hitCond or c < hitCond then hitId, hitCond = id, c end
            elseif was ~= c then
                s.win[id] = c
            end
        end
    end
    if not hitId or S.smashing(vehicle) then return end
    S.onBreak(vehicle, actor, hitCond <= 0 and "window" or "windowHit", hitId) -- one alert per look, the worst window
end

-- the player behind the trusted hit of the last S.HIT_HOURS, if still online: matched by account (conventions: the
-- principal, never a bare username; getPlayerFromUsername is client-only anyway, LuaManager.java:9142-9147)
local function lastHitter(id, t)
    local hit = S.lastHit[id]
    if not hit then return nil end
    if t - hit.at > S.HIT_HOURS then S.lastHit[id] = nil; return nil end
    local ps = getOnlinePlayers()
    for i = 0, (ps and ps:size() or 0) - 1 do
        if T.account(ps:get(i)) == hit.account then return ps:get(i) end
    end
end

function S.scan()
    local t, gone = now(), nil
    for id in pairs(S.armed) do
        local v = getVehicleById(id)
        if v and armedState(v) then
            S.checkWindows(v, lastHitter(id, t))
        else -- unloaded, disarmed, or the id now names another car (VehicleIDMap.java:49-62)
            gone = gone or {}
            gone[#gone + 1] = id
        end
    end
    if gone then
        for _, id in ipairs(gone) do S.armed[id] = nil; S.forget(id) end
    end
end
Events.EveryOneMinute.Add(S.scan)

Events.OnSpawnVehicleEnd.Add(function(vehicle) -- every load (BaseVehicle.java:904)
    S.forget(vehicle:getId())
    if armedState(vehicle) then S.armed[vehicle:getId()] = true end
end)

-- Who sent a damageWindow is not always who hit: the client sends it with no player (VehicleWindow.java:79-81), the
-- server takes the connection's first one (GameServer.java:2280-2283, 2322-2326), and a zombie on an occupied car
-- goes the same way from the client running it (AttackVehicleState.java:158-159). Trusted only when the sender has a
-- verified account (T.account: none for a split-screen guest or an unverified Steam name), is the one player on its
-- connection (connection = floor(onlineID / 4): GameServer.java:2686, ConnectCoopPacket.java:125), on foot on the
-- car's floor within reach of it, and no other player or zombie is.
S.NAME_RANGE = 4 -- tiles, straight line from the car's centre: a 5-tile car (2.5 to a bumper) plus a swing
local function near(vehicle, o, r)
    if math.floor(o:getZ()) ~= math.floor(vehicle:getZ()) then return false end
    local dx, dy = o:getX() - vehicle:getX(), o:getY() - vehicle:getY()
    return dx * dx + dy * dy <= r * r -- not DistTo: that one is Manhattan (IsoMovingObject.java:605-607)
end
function S.trusted(vehicle, player)
    local r = S.NAME_RANGE
    if player:getVehicle() or not T.account(player) or not near(vehicle, player, r) then return false end
    local conn = math.floor(player:getOnlineID() / 4)
    local ps = getOnlinePlayers()
    for i = 0, (ps and ps:size() or 0) - 1 do
        local o = ps:get(i)
        if o ~= player and (math.floor(o:getOnlineID() / 4) == conn or near(vehicle, o, r)) then return false end
    end
    local cell = getCell()
    local x0, y0, z = math.floor(vehicle:getX()), math.floor(vehicle:getY()), math.floor(vehicle:getZ())
    for x = x0 - r, x0 + r do
        for y = y0 - r, y0 + r do
            local sq = cell:getGridSquare(x, y, z)
            local mo = sq and sq:getMovingObjects()
            for k = 0, (mo and mo:size() or 0) - 1 do
                if instanceof(mo:get(k), "IsoZombie") then return false end
            end
        end
    end
    return true
end

-- Towing: owner's manuals, "a lot of jerky movement like when getting towed" sounds the alarm (the break tier). The
-- only vanilla way to hook up is attachTrailer (ISAttachTrailerToVehicle.lua:42-48; the radial's three branches,
-- ISVehicleMenu.lua:492-588), which checks no key or owner (VehicleCommands.lua:399-411). The menu swaps A and B by
-- hitch (:530-560): look at both. Legit (the owner, a key, VehicleManager's PASSENGER) takes the car away: disarm,
-- always. A stranger's tow alerts once per car per S.towHours(), whatever it is hooked to: vanilla unhooks and hooks
-- again on every send (BaseVehicle.java:10047-10062) and the "vehicle" module skips CmdRate, so attach / detach in a
-- loop must not flood the owner, and a link broken elsewhere (a third car's attach, a hitch mismatch :10059-10067, a
-- spontaneous detach) leaves nothing to clear. The window is vanilla's own alarm length: it rings until
-- startTime + 0.66 x getDeltaMinutesPerDay() world hours (VehicleAlarm.java:85; GameTime.java:433-435), about 13 game
-- minutes at the default 90-minute day; past it the car is quiet again and a new tow rings again.
function S.towHours() return 0.66 * getGameTime():getDeltaMinutesPerDay() end
local function onTow(vehicle, player)
    local s = armedState(vehicle)
    if not s then return end
    if T.legit(player, vehicle, s.by) then return S.disarm(vehicle, player:getUsername()) end
    local id, t = vehicle:getId(), now()
    if S.tow[id] and t - S.tow[id] < S.towHours() then return end
    S.tow[id] = t
    S.onBreak(vehicle, player, "tow")
end

-- Vanilla "vehicle" commands, after vanilla handled them (server/Vehicles/VehicleCommands.lua loads before this file);
-- read only, never refused. VehicleManager's gate (shared, first) empties args and sets vehicle / vehicleA / vehicleB
-- to -1 when it refuses (MinidoracatVehicleManager_CommandGate.lua:271-279), so a refused try never reaches here,
-- like the other sentry hooks. SP routes sendClientCommand here too. Other mods' ways of carrying a car off
-- (VehicleManager's CommandGate.lua:157-158: Autotsar, rSemiTruck loadVehicle) do not come this way.
--   attachTrailer: the tow, once vanilla linked the two (addPointConstraint sets the link at once, BaseVehicle.java:10104-10106).
--   damageWindow: MP only, a client works out a weapon hit and sends it (VehicleWindow.java:79-81); vanilla applied it
--   (VehicleCommands.lua:169-185; nothing for amount <= 0 or no such window, VehicleWindow.java:77). It speaks for its
--   own drop only: S.preHit (shared ParkModes.lua, before vanilla) is the condition the server held when it came in.
--   The sender is named, or kept quiet when legit, only if the car stood at its baseline then (that window at
--   preHit, every other window untouched) and S.trusted holds; otherwise a loss nobody saw is in the mix (the clamp at
--   0 hides how much was this packet's): it rings, unnamed. No snapshot (another mod's listener order): unnamed.
function S.onDamageWindow(player, args)
    local pre = S.preHit
    S.preHit = nil
    local v = getVehicleById(tonumber(args.vehicle) or -1)
    local s = v and armedState(v)
    if not s then return end
    local id = v:getId()
    S.armed[id] = true
    local amount = tonumber(args.amount)
    if not amount or amount <= 0 then return end -- vanilla ignored it; any other loss is the scan's, unnamed
    local part = type(args.part) == "string" and v:getPartById(args.part)
    local was = s.win and part and part:getWindow() and s.win[args.part]
    if not was then return end
    if not (pre and pre.player == player and pre.vid == id and pre.part == args.part) then pre = nil end
    local cond = part:getCondition()
    -- glass already gone when the packet came in (that window under its baseline, or any other window): nobody this
    -- packet can speak for. Drop the last trusted hit too, or the next scan would hand that loss to it (a legit
    -- one = silence); ring now, unnamed. Checked before "took nothing": a packet on glass already at 0 takes nothing.
    local unseen = pre ~= nil and pre.cond < was
    for i = 0, v:getPartCount() - 1 do
        local p = v:getPartByIndex(i)
        local base = p:getWindow() and p:getId() ~= args.part and s.win[p:getId()]
        if base and p:getCondition() < base then unseen = true end
    end
    local took = cond < (pre and pre.cond or was)
    if not unseen and not took then return end -- took nothing, nothing else gone
    local actor = pre ~= nil and not unseen and S.trusted(v, player) and player or nil
    S.lastHit[id] = actor and { account = T.account(player), at = now() } or nil
    local dx, dy = player:getX() - v:getX(), player:getY() - v:getY()
    T.log("sentry damageWindow vid=" .. id .. " " .. args.part .. " from " .. player:getUsername()
        .. (actor and " trusted" or " untrusted") .. string.format(" dist=%.1f", math.sqrt(dx * dx + dy * dy))
        .. " base=" .. tostring(was) .. " pre=" .. tostring(pre and pre.cond) .. " now=" .. tostring(cond)
        .. " amount=" .. tostring(amount) .. (unseen and " unseen" or ""))
    S.checkWindows(v, actor)
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "vehicle" or not player or type(args) ~= "table" then return end
    if command ~= "attachTrailer" and command ~= "damageWindow" then return end
    local ok, err = pcall(function()
        if command == "attachTrailer" then
            local a, b = getVehicleById(tonumber(args.vehicleA) or -1), getVehicleById(tonumber(args.vehicleB) or -1)
            if not (a and b and a:getVehicleTowing() == b) then return end
            onTow(a, player)
            onTow(b, player)
        else
            S.onDamageWindow(player, args)
        end
    end)
    if not ok then T.log("sentry " .. command .. " error " .. tostring(err)) end
end)

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
