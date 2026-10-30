-- Tesla app on the phone key, server side (client: client/MinidoracatTesla/PhoneApp.lua; reach: Keys.appReach).
--   * appStatus { key }: every 2 s while a holder has the app open. The car as it is when the server has it loaded and
--     the phone reaches it (grid up: any distance; grid down: Bluetooth, Keys.btRange()); else its last record.
--   * appAction { key, act, on }: lock, unlock, flash, horn, sentry, charge, frunk, trunk, tonneau, summon (+ mode, x,
--     y, dir), powershare, outlet, psFloor (+ pct).
--     Holder, reach, the VehicleManager right for doing the same thing in person, and the action's own rules are
--     checked every time, but a summoner stopping their own summon skips reach and the VehicleManager.
--   * appAlerts { key }: the car's last sentry / camp alerts.
--   * appStatusAll { keys }: the app's car list (one phone, several cars) when it opens, up to MAX_BATCH cars a request.
-- Only players carrying the phone key for `key` get an answer about that car. Every command names its car by keyId
-- (Keys.pairedWith: any car the phone key is paired with).
if isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Keys"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/Liftgate"
require "MinidoracatTesla/Store"
require "MinidoracatTesla/Chargers"

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
    r.script = v:getScriptName() -- full type (BaseVehicle.java:1621): R.mayTrack asks VehicleManager about this model only
    r.skin = v:getSkinIndex() -- the app draws the car in its paint (Core.lua colors[skin + 1]); older records lack it
    r.x, r.y, r.z = math.floor(v:getX()), math.floor(v:getY()), math.floor(v:getZ())
    local kwh, cap = part and T.Battery.kwh(part) or 0, part and T.Battery.capacity(part) or 1
    local left = 0
    if chg then
        local added -- unused here
        kwh, added, left, cap = T.Battery.chargeEstimate(part, chg, T.hours())
    end -- same as the HUD between settlements
    r.pct = math.floor(math.min(100, kwh * 100 / math.max(1, cap)) + 0.5)
    local kmk = T.kmPerKwh(v) -- nil: no range limit (Gas Consumption 0), the app shows "--"; an empty pack is 0
    r.km = kmk and math.floor(kwh * kmk + 0.5) or (kwh <= 0 and 0 or nil)
    r.locked = v:areAllDoorsLocked()
    r.sentry = md.sentry ~= nil
    r.drive = v:isEngineRunning() and not chg -- plugged in = Park, as the HUD gear (HUD.lua:276)
    r.frunk, r.trunk = doorOpen(v, "EngineDoor"), doorOpen(v, "TrunkDoor")
    r.tonneau = doorOpen(v, "TrunkTonneau") -- Cybertruck; false on a car without one
    r.chg = chargeState(chg)
    r.kw, r.target, r.mins = nil, nil, nil
    if chg then
        r.kw = math.floor((chg.kw or 0) * 10 + 0.5) / 10
        r.target = chg.target or 90
        if r.chg == "charging" and (chg.kw or 0) > 0 then r.mins = math.floor(left * 60 + 0.5) end
    end
    -- Cybertruck: Powershare (T.psState, its limit, the house's load and hours left) and the bed outlet
    local s = T.spec(v)
    local ps = md.ps
    r.ps = s and s.powershare and T.psState(part) or nil
    r.psFloor = (s and (s.powershare or s.bedOutlet)) and T.psFloor(part) or nil
    r.psKw, r.psH = nil, nil
    if r.ps == "backup" and ps.house and T.Charge then
        local kw = ps.house + T.Charge.drawnKw(v) -- the house at its last fill, the cars it charges right now
        r.psKw = math.floor(kw * 100 + 0.5) / 100
        local avail = T.Powershare and T.Powershare.avail(v, part) or 0
        r.psH = kw > 0 and math.floor(avail / kw + 0.5) or nil
    end
    r.psWall = r.ps ~= nil and chg ~= nil and chg.kind == "WallConnector" or nil -- armed on a Wall Connector or not
    r.psStop = r.ps == "stopped" and T.psStopWhy(part) or nil -- "spot" / "floor"
    -- the outlet switched on, and why it gives nothing now (Chargers.lua T.outletWhy, which T.outletPowers asks too)
    r.outlet = s and s.bedOutlet and md.outlet == true or nil
    r.outletWhy = r.outlet and T.outletWhy(v, part) or nil
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
local VM_REASONS = T.VM_REASONS
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
-- where the car is and its alerts: with VehicleManager the TRACK right. A loaded car is asked through canUse; an unloaded
-- one through VehicleManager's keyId check on its own records (canTrackKeyId: same rules, no ADMIN_BYPASS line, fine for
-- the 2 s poll; denials still go into its per-minute DENY summary), so a revoked share stays revoked while the car is
-- away. The record's script narrows it to this model: an Autotsar trailer that once carried the car keeps its keyId.
-- An older VehicleManager without it: nothing is shown rather than the record (UNVERIFIED, fail closed). The client's
-- VehicleManager list never counts here.
function R.mayTrack(player, v, key)
    local api = MinidoracatVehicleManagerAPI
    if not (api and api.canUse) then return true end
    if v then return R.vmAllows(player, v, TRACK) end
    if type(api.canTrackKeyId) ~= "function" then return false, "UNVERIFIED" end
    local r = R.record(key)
    -- no r.script (records from before it, or no record yet: alerts need none): the model name from the record or the
    -- Tesla keyId registry (KeyActions K.register, same format), as a script only when it is one (PhoneApp.lua App.paint)
    local car = (r and r.car ~= "" and r.car) or store("keyIds")[tostring(key)]
    local script = r and r.script or (car and T.Specs["Base." .. car] and "Base." .. car) or nil
    local ok, why = api.canTrackKeyId(player, key, script)
    if ok then return true end
    return false, VM_REASONS[why] and why or "NOT_OWNER"
end
-- act -> the VehicleManager codes for the same thing in person. Sentry: PASSENGER, the code T.legit (ParkModes.lua)
-- asks in person on a claimed car (the card tap, KeyActions keyTap, too).
local VM_CODES = {
    lock = { "PASSENGER" }, unlock = { "PASSENGER" }, flash = { "PASSENGER" }, horn = { "PASSENGER" },
    sentry = { "PASSENGER" }, trunk = { "CARGO" }, tonneau = { "CARGO" }, frunk = { "REPAIR", "SALVAGE" },
    charge = { "FUEL" },
    summon = { "DRIVE" }, -- the car moves: the right to drive it (VehicleManager also wraps startSummon itself)
    powershare = { "FUEL" }, outlet = { "FUEL" }, psFloor = { "FUEL" }, -- the charge cable's right (T.mayUseCable)
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

-- ------------------------------------------------------------------ summon: AutoDrive drives the empty car
-- MinidoracatAutoDriveAPI (AutoDrive server/MDAD_Summon.lua, design temp/plan-summon-1027): startSummon checks again,
-- starts the motor, hands the car's physics to the summoner's game and ends every session through onEnd. Modes: "come"
-- (to the summoner, following them), "target" (a fixed ground point x, y), "dumb" (straight ahead dir = 1, or back -1).
function R.summonApi()
    local api = MinidoracatAutoDriveAPI
    if type(api) == "table" and (tonumber(api.summonApiVersion) or 0) >= 1 and type(api.startSummon) == "function"
        and type(api.stopSummon) == "function" and type(api.summonInfo) == "function" then return api end
    return nil
end
local SUMMON_MODES = { come = true, target = true, dumb = true }
-- a world square coordinate: a number, not NaN, on the map (no math.huge: Kahlua need not have it)
local function coord(n) return type(n) == "number" and n == n and n >= 0 and n < 1000000 end

-- every end (arrived, stopped, refused on the way): AutoDrive calls this once; the summoner (nil when gone) hears why.
-- v is nil when the car is gone (GONE): key = its keyId from the start, so the app still hears the end.
function R.summonEnded(v, code, player, key)
    key = key or v and v:getKeyId()
    -- the app first: an error below is swallowed by AutoDrive's pcall and must not leave the app on "driving"
    if player and key then T.send(player, "appDone", { key = key, act = "summonEnd", why = tostring(code) }) end
    T.log("summon end " .. tostring(code) .. " vid=" .. tostring(v and v:getId()) .. " key=" .. tostring(key) .. " by "
        .. (player and player:getUsername() or "-"))
    if v then
        T.Battery.summonEnd(v) -- the drive since the pack's last update (Battery.lua)
        local mvm = MinidoracatVehicleManager -- the car moved (ParkedGuard.lua:258-261)
        if mvm and mvm.Parked and mvm.Parked.touch then mvm.Parked.touch(v) end
    end
    -- the motor layers stop for everyone near (they started with the summon); a gone car: each listener's game goes
    -- quiet itself (no car loaded) and drops it after Sound.SUMMON_MS
    local sr = T.SoundRelay
    if sr and v then sr.summon(v, false) end
end

-- Is `player` the one running summon `info` (AutoDrive summonInfo, by = the summoner's username)? The session ends once
-- its summoner leaves or dies (MDAD_Summon.lua:223-225), so the name is someone online. A dedicated server keeps
-- online names unique (LoginPacket.java:140-150, ConnectCoopPacket.java:79-88): the name is enough. A Steam co-op host
-- checks only the SteamID at login (LoginPacket.java:78-90), so the name may be online twice: then only a main player
-- whose account (T.account, SteamID) is that name counts.
function R.isSummoner(player, info)
    if type(info) ~= "table" or info.by ~= player:getUsername() then return false end
    if not isServer() then return true end
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do
        local q = list:get(i)
        if q ~= player and q:getUsername() == info.by then
            return T.account(player) == info.by -- nil for a split-screen guest
        end
    end
    return true
end

-- on: start (a running summon: nothing, startSummon is called once) or stop it, whoever started it. Tesla's own rules
-- first, then AutoDrive's; refused by AutoDrive = its translation key (T.denyText shows it). Sentry is switched off
-- once the car is on its way, like the owner's unlock.
local function summon(player, v, on, args)
    local api = R.summonApi()
    if not api then return "NO_AUTODRIVE" end
    local info = api.summonInfo(v)
    if not on then
        if not info then return nil, false, true end
        api.stopSummon(v, "CANCELLED")
        return nil, false
    end
    if info then -- already on its way: once per summoner, someone else's is theirs
        if not R.isSummoner(player, info) then return "UI_MinidoracatAutoDrive_SummonBusy" end
        return nil, true, true
    end
    local mode = args.mode or "come"
    if not SUMMON_MODES[mode] then return "NO_TARGET" end
    local key = v:getKeyId()
    local opts = { mode = mode, startEngine = true, -- the phone key holder has the key
        onEnd = function(car, code, p) R.summonEnded(car, code, p, key) end }
    if mode == "target" then
        if not (coord(args.x) and coord(args.y)) then return "NO_TARGET" end
        -- grid down: the spot within Bluetooth too, like the app's ring (PhoneApp.lua summonRead); AutoDrive's
        -- startSummon checks its own summon range
        if not getWorld():isHydroPowerOn() then
            local dx, dy, r = args.x - player:getX(), args.y - player:getY(), K.btRange()
            if dx * dx + dy * dy > r * r then return "UI_MinidoracatAutoDrive_SummonTooFar" end
        end
        opts.x, opts.y = args.x, args.y
    elseif mode == "dumb" then
        if args.dir ~= 1 and args.dir ~= -1 then return "NO_TARGET" end
        opts.dir = args.dir
    end
    if player:getVehicle() then return "NOT_OUTSIDE" end
    if v:hasPassenger() then return "OCCUPIED" end -- any seat, the driver's too (BaseVehicle.java:1836-1845)
    local part = T.Battery.part(v)
    -- plugged in: the unmanned push would drag the cable (Charging.checkCable unplugs it)
    if part and part:getModData().chg then return "CABLE_PLUGGED" end
    if v:getVehicleTowing() or v:getVehicleTowedBy() then return "TOWED" end
    if v:getBatteryCharge() <= 0 then return "NO_12V" end
    if not v:isEngineRunning() and not v:isEngineWorking() then return "CANT_START" end -- empty pack, broken motor
    local ok, why = api.startSummon(player, v, opts)
    if not ok then return type(why) == "string" and why or "CANT_START" end
    local info = api.summonInfo(v)
    T.Battery.summonStart(v, info and info.startedMs) -- the drain counts the path from here (Battery.lua)
    if part and part:getModData().sentry then S.disarm(v, player:getUsername()) end
    -- nobody drives, so no beats: the server starts the motor whine and PWS for everyone near (SoundRelay.lua)
    local sr = T.SoundRelay
    if sr then sr.summon(v, true, opts.dir == -1) end
    return nil, true
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
    -- Cybertruck (Powershare.lua PS.set: the Specs, the cable rule, then the switch): nil = done, already so too
    powershare = function(player, v, on) return T.Powershare.set(player, v, "ps", on) end,
    outlet = function(player, v, on) return T.Powershare.set(player, v, "outlet", on) end,
    psFloor = function(player, v, _, args) return T.Powershare.set(player, v, "floor", nil, args.pct) end,
    frunk = swing("EngineDoor"),
    trunk = swing("TrunkDoor"),
    tonneau = swing("TrunkTonneau"), -- Cybertruck: the app opens the tonneau cover (owner's manual p.60)
    summon = summon,
}

-- ------------------------------------------------------------------ commands
-- what the app shows: the record (refreshed first over a live link) plus how the phone reaches the car now
function R.state(player, key)
    local v = R.loadedCar(key)
    local ok, why = R.mayTrack(player, v, key)
    if not ok then return { key = key, deny = why } end
    local link = K.appReach(player, v)
    local r = link and R.remember(v, true) or R.record(key)
    -- grid: the phone's own network (status bar), apart from whether it reaches this car
    local out = { key = key, link = link, grid = getWorld():isHydroPowerOn() }
    if r then for k, val in pairs(r) do out[k] = val end end
    if link then
        out.vid = v:getId() -- the app finds the car its game has loaded (summon page)
        local api = R.summonApi()
        local info = api and api.summonInfo(v)
        if info then out.summon = { phase = info.phase, mode = info.mode, mine = R.isSummoner(player, info) } end
    end
    return out
end

-- the app's car list (PhoneApp.lua): when the list opens (App.BATCH cars a request), every car in `keys` the player holds a phone key for,
-- each answered like appStatus (the same checks per car); others are left out, nothing said about them
R.MAX_BATCH = 16
T.ServerCommands.appStatusAll = function(player, args)
    local keys = args.keys
    if not player or type(keys) ~= "table" then return end
    local list, done = {}, {}
    for i = 1, math.min(#keys, R.MAX_BATCH) do
        local key = holder(player, { key = keys[i] })
        if key and not done[key] then -- each car once (a repeated key would cost a full state each)
            done[key] = true
            list[#list + 1] = R.state(player, key)
        end
    end
    R.stats.status = R.stats.status + #list
    T.send(player, "appStates", { list = list })
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
    -- the summoner stopping their own summon: always (the car may have driven past Bluetooth range with the grid
    -- down, or a share been taken back; "one tap starts, one tap stops" needs the stop to work)
    local api = act == "summon" and args.on ~= true and R.summonApi()
    local ownStop = api and R.isSummoner(player, api.summonInfo(v))
    if not ownStop then
        if not K.appReach(player, v) then return done("NO_LINK") end
        local codes = VM_CODES[act]
        if codes then
            local ok, why = R.vmAllows(player, v, codes)
            if not ok then return done(why) end
        end
    end
    local why, result, noop = fn(player, v, args.on == true, args)
    if why then return done(why) end
    if noop then -- already as asked: nothing changed, nothing to log or touch
        done(nil, result)
        return T.send(player, "appState", R.state(player, key))
    end
    R.stats.actions = R.stats.actions + 1
    local mvm = MinidoracatVehicleManager -- AGENTS.md: touch after changing the car (ParkedGuard.lua:258-261)
    if mvm and mvm.Parked and mvm.Parked.touch then mvm.Parked.touch(v) end
    local switch = act == "sentry" or act == "charge" or act == "powershare" or act == "outlet"
    local onOff = (switch or act == "summon") and (args.on == true and " on" or " off") or ""
    if act == "psFloor" then onOff = " " .. tostring(args.pct) end
    if act == "summon" and args.on == true then onOff = onOff .. " " .. tostring(args.mode or "come") end
    T.log("app " .. act .. onOff .. " vid=" .. v:getId() .. " by " .. player:getUsername())
    if result == nil and switch then result = args.on == true end
    done(nil, result)
    T.send(player, "appState", R.state(player, key)) -- creates the record over the live link
end

T.ServerCommands.appAlerts = function(player, args)
    local key = holder(player, args)
    if not key then return end
    local ok, why = R.mayTrack(player, R.loadedCar(key), key)
    if not ok then return T.send(player, "appAlerts", { key = key, deny = why }) end -- the holder hears why
    T.send(player, "appAlerts", { key = key, list = store("alerts")[tostring(key)] or {} })
end

return R
