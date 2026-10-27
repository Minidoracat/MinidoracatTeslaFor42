-- Tesla app on the phone key, server side (client: client/MinidoracatTesla/PhoneApp.lua; reach: Keys.appReach).
--   * appStatus { key }: every 2 s while a holder has the app open. The car as it is when the server has it loaded and
--     the phone reaches it (grid up: any distance; grid down: Bluetooth Keys.BT_RANGE); else its last record.
--   * appAction { key, act, on }: lock, unlock, flash, horn, sentry, charge, frunk, trunk. Holder, reach, the
--     VehicleManager right for doing the same thing in person, and the action's own rules are checked every time.
--   * appAlerts { key }: the car's last sentry / camp alerts.
-- Only players carrying the phone key for `key` get an answer about that car. Every command names its car by keyId;
-- nothing here assumes one phone = one car.
if isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Keys"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/Liftgate"
require "MinidoracatTesla/Store"

local T = MinidoracatTesla
local K, S = T.Keys, T.Sentry
local R = {}
T.Remote = R
T.ServerCommands = T.ServerCommands or {}

-- records ("seen") and alerts live in the server-only store (Store.lua), never Global ModData
R.MAX_ALERTS = 10
R.HORN_MS = 1000 -- vanilla horn for one second
R.stats = { status = 0, actions = 0, denied = 0, horns = 0 }

local function isInt(n) return type(n) == "number" and n == n and math.floor(n) == n end
local store = T.Store.get

-- ------------------------------------------------------------------ loaded cars and their last record
-- tostring(keyId) -> vehicle id while loaded. Ids are reused after an unload, so the keyId is checked on every use.
local loaded = {}

function R.loadedCar(keyId)
    local id = loaded[tostring(keyId)]
    local v = id and getVehicleById(id)
    if v and v:getKeyId() == keyId and T.isTesla(v) then return v end
    return nil
end

local function chargeState(chg)
    if not chg then return nil end
    if chg.paused == "full" or chg.paused == "nopower" then return chg.paused end
    return chg.paused and "stopped" or "charging"
end

local function doorOpen(v, id)
    local part = v:getPartById(id)
    local door = part and part:getDoor()
    return door ~= nil and door:isOpen()
end

-- The car as it is now, written over its record. Called on load, from the battery part update (driving, charging),
-- on lock changes (Keys K.setLocked), after every app command and on each status asked over a live link. Only the
-- last two (`create`) start a record: parked Teslas the world spawns (Spawns.lua) never get one.
function R.remember(v, create)
    local key = tostring(v:getKeyId())
    local all = store("seen")
    local r = all[key]
    if not r then
        if not create then return nil end
        r = {}
        all[key] = r
    end
    local part = T.Battery.part(v)
    local md = part and part:getModData() or {}
    local chg = md.chg
    local script = v:getScript()
    r.car = script and (script:getCarModelName() or script:getName()) or ""
    r.skin = v:getSkinIndex() -- the app draws the car in its paint (Core.lua colors[skin + 1]); older records lack it
    r.x, r.y, r.z = math.floor(v:getX()), math.floor(v:getY()), math.floor(v:getZ())
    local kwh, cap = part and T.Battery.kwh(part) or 0, part and T.Battery.capacity(part) or 1
    local left = 0
    if chg then
        local added -- unused here
        kwh, added, left, cap = T.Battery.chargeEstimate(part, chg, T.hours())
    end -- same as the HUD between settlements
    r.pct = math.floor(math.min(100, kwh * 100 / math.max(1, cap)) + 0.5)
    r.km = math.floor(kwh * T.kmPerKwh(v) + 0.5)
    r.locked = v:areAllDoorsLocked()
    r.sentry = md.sentry ~= nil
    r.drive = v:isEngineRunning()
    r.frunk, r.trunk = doorOpen(v, "EngineDoor"), doorOpen(v, "TrunkDoor")
    r.chg = chargeState(chg)
    r.kw, r.target, r.mins = nil, nil, nil
    if chg then
        r.kw = math.floor((chg.kw or 0) * 10 + 0.5) / 10
        r.target = chg.target or 90
        if r.chg == "charging" and (chg.kw or 0) > 0 then r.mins = math.floor(left * 60 + 0.5) end
    end
    r.h = T.hours()
    return r
end

function R.record(keyId) return store("seen")[tostring(keyId)] end

-- OnSpawnVehicleEnd fires on every load, new or from the save (BaseVehicle.java:904, 7952-7964)
function R.onLoad(v)
    if not T.isTesla(v) then return end
    loaded[tostring(v:getKeyId())] = v:getId()
    R.remember(v)
end
Events.OnSpawnVehicleEnd.Add(R.onLoad)

-- Inbox.notify: every sentry / camp alert also goes into its car's list
function R.logAlert(e)
    if not isInt(e.key) then return end
    local all = store("alerts")
    local k = tostring(e.key)
    local list = all[k] or {}
    all[k] = list
    list[#list + 1] = e
    while #list > R.MAX_ALERTS do table.remove(list, 1) end
end

-- ------------------------------------------------------------------ who may
-- the keyId from the client, only if the player really carries that phone key (bags too, Keys.phoneKeyFor)
local function holder(player, args)
    local key = args.key
    if not player or not isInt(key) or not K.phoneKeyFor(player, key) then return nil end
    return key
end

-- VehicleManager present: also its right for doing the same thing in person (MinidoracatVehicleManager_Actions.lua:
-- 20-53); unclaimed cars answer true, "UNCLAIMED" (OwnershipSystem.lua:875-877), so only the phone key counts then.
-- T.authorized is not enough: with VehicleManager it asks only VehicleManager, and an unclaimed car passes anyone.
-- silent only for TRACK: the 2 s poll must not write an ADMIN_BYPASS audit line every time
-- (OwnershipSystem.lua:899-903); an admin's remote unlock or liftgate is audited like in person.
local VM_REASONS = { RENT_LOCKED = true, FACTION_PAUSED = true, QUARANTINED = true }
local TRACK = { "TRACK" }
function R.vmAllows(player, v, codes)
    local api = MinidoracatVehicleManagerAPI
    if not (api and api.canUse) then return true end
    local why
    local ctx = { mod = T.MODULE, silent = codes == TRACK }
    for i = 1, #codes do
        local ok, r = api.canUse(player, v, codes[i], ctx)
        if ok then return true end
        why = why or r
    end
    return false, VM_REASONS[why] and why or "NOT_OWNER"
end
-- where the car is and its alerts: with VehicleManager the TRACK right, which needs the car itself. An unloaded car can't
-- be asked, so nothing is shown rather than the record (fail closed; a revoked share stays revoked).
function R.mayTrack(player, v)
    local api = MinidoracatVehicleManagerAPI
    if not (api and api.canUse) then return true end
    if not v then return false, "UNVERIFIED" end
    return R.vmAllows(player, v, TRACK)
end
-- act -> the VehicleManager codes for the same thing in person. Sentry: T.legit (ParkModes.lua) counts an old phone
-- key, so a car since claimed by someone else also needs PASSENGER here, like a remote lock.
local VM_CODES = {
    lock = { "PASSENGER" }, unlock = { "PASSENGER" }, flash = { "PASSENGER" }, horn = { "PASSENGER" },
    sentry = { "PASSENGER" }, trunk = { "CARGO" }, frunk = { "REPAIR", "SALVAGE" }, charge = { "FUEL" },
}

-- ------------------------------------------------------------------ horn: vanilla, one second
-- onHornStart adds the vanilla 150-tile world sound (zombies hear it) and syncs the horn to clients
-- (BaseVehicle.java:8947-8975). The stop is a one-shot OnTick removed when the last horn ends.
local horns = {} -- { v, at }
local function hornTick()
    local now = getTimestampMs()
    for i = #horns, 1, -1 do
        if now >= horns[i].at then
            horns[i].v:onHornStop()
            table.remove(horns, i)
        end
    end
    if #horns == 0 then Events.OnTick.Remove(hornTick) end
end
function R.horn(v)
    for _, h in ipairs(horns) do if h.v == v then return end end -- already sounding
    if #horns == 0 then Events.OnTick.Add(hornTick) end
    horns[#horns + 1] = { v = v, at = getTimestampMs() + R.HORN_MS }
    v:onHornStart()
    R.stats.horns = R.stats.horns + 1
end
function R.hornCount() return #horns end

-- ------------------------------------------------------------------ actions: nil = done (lids: nil, open), else a deny reason
-- `on` is the state asked for: already so = done, nothing moves (the app's view can be 2 s old, or a double press);
-- the third value says so, and nothing is logged. Closing relocks the lid on a locked car (Liftgate.relock).
local function swing(id)
    return function(player, v, open)
        if not T.stopped(v) then return "MOVING" end
        local part = v:getPartById(id)
        local door = part and part:getInventoryItem() and part:getDoor()
        if not door then return "NO_DOOR" end
        if door:isOpen() == open then return nil, open, true end
        if open and door:isLocked() then
            if door:isLockBroken() then return "LOCK_BROKEN" end
            door:setLocked(false)
        end
        T.Liftgate.swing(v, part, open, player:getUsername())
        return nil, open
    end
end

local ACT = {
    -- same as the key card tap (KeyActions.lua keyTap): flash, chirp / beep; an unlock by the owner disarms sentry
    lock = function(_, v) K.setLocked(v, true); K.signal(v, true) end,
    unlock = function(player, v)
        K.setLocked(v, false)
        K.signal(v, false)
        local part = T.Battery.part(v)
        if part and part:getModData().sentry then S.disarm(v, player:getUsername()) end
    end,
    flash = function(_, v) S.flash(v) end,
    horn = function(_, v) -- the vanilla horn needs 12 V too (ISVehicleMenu.lua:143, 1703-1706)
        if v:getBatteryCharge() <= 0 then return "NO_12V" end
        R.horn(v)
    end,
    sentry = function(player, v, on)
        local part = T.Battery.part(v)
        if on and part and part:getModData().sentry then return nil, true, true end -- already on: S.arm would keep it
        local ok, why
        if on then ok, why = S.canArm(player, v, true) else ok, why = S.canDisarm(player, v, true) end
        if not ok then return why or (on and "NO_PACK" or "SENTRY_OFF") end
        if on then S.arm(player, v, true) else S.disarm(v, player:getUsername()) end
    end,
    charge = function(_, v, on)
        local f = T.Charge and T.Charge.setStopped
        if not f then return "NOT_PLUGGED" end
        local ok, why = f(v, not on)
        if not ok then return why end
    end,
    frunk = swing("EngineDoor"),
    trunk = swing("TrunkDoor"),
}

-- ------------------------------------------------------------------ commands
-- what the app shows: the record (refreshed first over a live link) plus how the phone reaches the car now
function R.state(player, key)
    local v = R.loadedCar(key)
    local ok, why = R.mayTrack(player, v)
    if not ok then return { key = key, deny = why } end
    local link = K.appReach(player, v)
    local r = link and R.remember(v, true) or R.record(key)
    -- grid: the phone's own network (status bar), apart from whether it reaches this car
    local out = { key = key, link = link, grid = getWorld():isHydroPowerOn() }
    if r then for k, val in pairs(r) do out[k] = val end end
    return out
end

T.ServerCommands.appStatus = function(player, args)
    local key = holder(player, args)
    if not key then return end -- not this phone key's holder: nothing about the car
    R.stats.status = R.stats.status + 1
    T.send(player, "appState", R.state(player, key))
end

T.ServerCommands.appAction = function(player, args)
    local act = args.act
    local fn = type(act) == "string" and ACT[act]
    if not fn or not player then return end
    local key = holder(player, args)
    local function done(why, on)
        if why then
            R.stats.denied = R.stats.denied + 1
            -- not a holder: counted, not logged (anyone can send these; a log line each would flood the console)
            if why ~= "NO_PHONE_KEY" then T.log("app " .. act .. " denied " .. why .. " key=" .. tostring(key) .. " by " .. player:getUsername()) end
        end
        T.send(player, "appDone", { key = key, act = act, why = why, on = on })
    end
    if not key then return done("NO_PHONE_KEY") end
    local v = R.loadedCar(key)
    if not v then return done("NOT_LOADED") end -- the server doesn't have the car: nobody can act on it
    if not K.appReach(player, v) then return done("NO_LINK") end
    local codes = VM_CODES[act]
    if codes then
        local ok, why = R.vmAllows(player, v, codes)
        if not ok then return done(why) end
    end
    local why, result, noop = fn(player, v, args.on == true)
    if why then return done(why) end
    if noop then -- already as asked: nothing changed, nothing to log or touch
        done(nil, result)
        return T.send(player, "appState", R.state(player, key))
    end
    R.stats.actions = R.stats.actions + 1
    local mvm = MinidoracatVehicleManager -- AGENTS.md: touch after changing the car (ParkedGuard.lua:258-261)
    if mvm and mvm.Parked and mvm.Parked.touch then mvm.Parked.touch(v) end
    local onOff = (act == "sentry" or act == "charge") and (args.on == true and " on" or " off") or ""
    T.log("app " .. act .. onOff .. " vid=" .. v:getId() .. " by " .. player:getUsername())
    if result == nil and (act == "sentry" or act == "charge") then result = args.on == true end
    done(nil, result)
    T.send(player, "appState", R.state(player, key)) -- creates the record over the live link
end

T.ServerCommands.appAlerts = function(player, args)
    local key = holder(player, args)
    if not key then return end
    local ok, why = R.mayTrack(player, R.loadedCar(key))
    if not ok then return T.send(player, "appAlerts", { key = key, deny = why }) end -- the holder hears why
    T.send(player, "appAlerts", { key = key, list = store("alerts")[tostring(key)] or {} })
end

return R
