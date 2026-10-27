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

local T = MinidoracatTesla
local K, S = T.Keys, T.Sentry
local R = {}
T.Remote = R
T.ServerCommands = T.ServerCommands or {}

-- Records and alerts live in a server-only GOS system (gos_MinidoracatTeslaApp.bin), not Global ModData: any logged-in
-- client can fetch a whole Global ModData table by name (GlobalModDataRequestPacket.java:15,32 -> GlobalModData.java:171;
-- family conventions.md). seen: tostring(keyId) -> last record; alerts: tostring(keyId) -> alerts, oldest first.
R.SYSTEM = "MinidoracatTeslaApp"
R.MAX_ALERTS = 10
R.HORN_MS = 1000 -- vanilla horn for one second
R.stats = { status = 0, actions = 0, denied = 0, horns = 0 }

local function isInt(n) return type(n) == "number" and n == n and math.floor(n) == n end
local db
local function store(name)
    if not db then
        local sys = SGlobalObjects.registerSystem(R.SYSTEM) -- loads the file the first time (SGlobalObjects.java:31-39)
        sys:setModDataKeys({ "seen", "alerts" }) -- only listed keys are saved
        sys:setObjectModDataKeys({})
        sys:setObjectSyncKeys({})
        db = sys:getModData()
        -- GOS calls these by rawget on this table (SGlobalObjectSystem.java:95-162): nothing goes to clients
        db.getInitialStateForClient = function() return nil end
        db.OnClientCommand = function() end
        db.isValidIsoObject = function() return false end
        db.OnChunkLoaded = function() end
        if type(db.seen) ~= "table" then db.seen = {} end
        if type(db.alerts) ~= "table" then db.alerts = {} end
    end
    return db[name]
end

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
-- on lock changes (Keys K.setLocked), after every app command and on each status asked over a live link.
function R.remember(v)
    local key = tostring(v:getKeyId())
    local all = store("seen")
    local r = all[key] or {}
    all[key] = r
    local part = T.Battery.part(v)
    local md = part and part:getModData() or {}
    local chg = md.chg
    local script = v:getScript()
    r.car = script and (script:getCarModelName() or script:getName()) or ""
    r.x, r.y, r.z = math.floor(v:getX()), math.floor(v:getY()), math.floor(v:getZ())
    local kwh, cap = part and T.Battery.kwh(part) or 0, part and T.Battery.capacity(part) or 1
    local left = 0
    if chg then kwh, _, left, cap = T.Battery.chargeEstimate(part, chg, T.hours()) end -- same as the HUD between settlements
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
-- silent: the 2 s poll must not write an ADMIN_BYPASS audit line every time (OwnershipSystem.lua:899-903).
local VM_REASONS = { RENT_LOCKED = true, FACTION_PAUSED = true, QUARANTINED = true }
function R.vmAllows(player, v, codes)
    local api = MinidoracatVehicleManagerAPI
    if not (api and api.canUse) then return true end
    local why
    for i = 1, #codes do
        local ok, r = api.canUse(player, v, codes[i], { mod = T.MODULE, silent = true })
        if ok then return true end
        why = why or r
    end
    return false, VM_REASONS[why] and why or "NOT_OWNER"
end
local TRACK = { "TRACK" }
-- where the car is and its alerts: with VehicleManager the TRACK right, which needs the car itself. An unloaded car can't
-- be asked, so nothing is shown rather than the record (fail closed; a revoked share stays revoked).
function R.mayTrack(player, v)
    local api = MinidoracatVehicleManagerAPI
    if not (api and api.canUse) then return true end
    if not v then return false, "UNVERIFIED" end
    return R.vmAllows(player, v, TRACK)
end
-- act -> the VehicleManager codes for the same thing in person; sentry keeps its own rule (T.legit, ParkModes.lua)
local VM_CODES = {
    lock = { "PASSENGER" }, unlock = { "PASSENGER" }, flash = { "PASSENGER" }, horn = { "PASSENGER" },
    trunk = { "CARGO" }, frunk = { "REPAIR", "SALVAGE" }, charge = { "FUEL" },
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
local function swing(id)
    return function(player, v)
        if not T.stopped(v) then return "MOVING" end
        local part = v:getPartById(id)
        local door = part and part:getInventoryItem() and part:getDoor()
        if not door then return "NO_DOOR" end
        local open = not door:isOpen()
        if open and door:isLocked() then
            if door:isLockBroken() then return "LOCK_BROKEN" end
            door:setLocked(false)
        end
        T.Liftgate.swing(v, part, open, player:getUsername())
        return nil, open -- the server toggles what is there now; the app says this, not what it guessed
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
    horn = function(_, v) R.horn(v) end,
    sentry = function(player, v, on)
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
R.ACTIONS = ACT

-- ------------------------------------------------------------------ commands
-- what the app shows: the record (refreshed first over a live link) plus how the phone reaches the car now
function R.state(player, key)
    local v = R.loadedCar(key)
    local ok, why = R.mayTrack(player, v)
    if not ok then return { key = key, deny = why } end
    local link = K.appReach(player, v)
    local r = link and R.remember(v) or store("seen")[tostring(key)]
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
            T.log("app " .. act .. " denied " .. why .. " key=" .. tostring(key) .. " by " .. player:getUsername())
        end
        T.send(player, "appDone", { key = key, act = act, why = why, on = on })
    end
    if not key then return done("NO_PHONE_KEY") end
    local v = R.loadedCar(key)
    if not K.appReach(player, v) then return done("NO_LINK") end
    local codes = VM_CODES[act]
    if codes then
        local ok, why = R.vmAllows(player, v, codes)
        if not ok then return done(why) end
    end
    local why, result = fn(player, v, args.on == true)
    if why then return done(why) end
    R.stats.actions = R.stats.actions + 1
    local mvm = MinidoracatVehicleManager -- AGENTS.md: touch after changing the car (ParkedGuard.lua:258-261)
    if mvm and mvm.Parked and mvm.Parked.touch then mvm.Parked.touch(v) end
    local onOff = (act == "sentry" or act == "charge") and (args.on == true and " on" or " off") or ""
    T.log("app " .. act .. onOff .. " vid=" .. v:getId() .. " by " .. player:getUsername())
    if result == nil and (act == "sentry" or act == "charge") then result = args.on == true end
    done(nil, result)
    T.send(player, "appState", R.state(player, key))
end

T.ServerCommands.appAlerts = function(player, args)
    local key = holder(player, args)
    if not key then return end
    if not R.mayTrack(player, R.loadedCar(key)) then return end
    T.send(player, "appAlerts", { key = key, list = store("alerts")[tostring(key)] or {} })
end

return R
