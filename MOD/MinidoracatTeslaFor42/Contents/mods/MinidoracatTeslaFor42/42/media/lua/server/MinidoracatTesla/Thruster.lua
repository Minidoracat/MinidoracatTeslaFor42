-- Thrusters, server side (and SP): approve an action (`thrust`, the driver; H.appShow, the phone app's show of the
-- empty car), bill the air tank, end it (`thrustEnd`) or, when the holder's machine never says so, have someone near
-- land it. The flying itself runs on the machine with the car's physics (client Thruster.lua). Shared rules: shared
-- Thruster.lua; design: .claude/skills/tesla-dev/references/roadster2.md. No watchdog: each action has due times
-- (D1 lift-off, D2 end, D3 the helper's landing), checked by a one-shot OnTick that is gone when none is left.
if isClient() then return end
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local H = T.Thruster
local B = T.Battery
T.ServerCommands = T.ServerCommands or {}
local cmds = T.ServerCommands

-- heard like the horn: radius 150, volume 150 (BaseVehicle.java:9001); once on approval, then each game minute in flight
local SOUND_R, SOUND_V = 150, 150
local FX = { kickflip = "flip", backflip = "flip", boost = "boost", land = "lift", fly = "lift" }
-- D2, real ms past approval (the show: past the handover): the approach (the driver's roll-up stops at 3 s; the show's
-- takes about 1 s, poc/APP.md) + the action's profile (client Thruster.lua PROF; land: its 12 s cap) + 2 s. Flying:
-- its seconds of air + the landing (6 s) instead of the profile.
local ROLL_MS, APPROACH_MS, SLACK_MS, FLY_LAND_MS = 3000, 1000, 2000, 6000
local PROF_MS = { kickflip = 3800, backflip = 2800, boost = 1500, land = 12000 }
local LIFT_MS = 1500   -- D1 (the show): this long after the approach the car is off the ground, or it never will be
local HELP_MS = 6000   -- D3: the helper's landing (its land controller rights the car first), then over whatever
local START_MS, START_TRIES = 2000, 3 -- tryStartEngine takes 1.7 s; 15 of 16 start first time (poc/APP.md)
local LIFTED = 0.06    -- floors over where it stood: off the ground (poc/APP.md)

-- [vid] = { act, player, ms = approved at (getTimestampMs), cost = air taken, due = ms of the next check or nil, on =
-- what that check runs, h0 = getDebugZ where it stood (nil: land, already up), app = the phone show, eng = the server
-- started the motor, held = the online id this file gave the car's physics to, helper = who lands it, orphan = up with
-- nobody near }. Server memory only: a busy flag without an entry here (a restart, an unload, SP reload) is stale.
local pending = {}
H.pending = pending

local function fx(v, mode)
    local f = T.ThrusterFx and T.ThrusterFx.set
    if f then f(v, mode) end
end

local function noise(v)
    addSound(v, math.floor(v:getX()), math.floor(v:getY()), math.floor(v:getZ()), SOUND_R, SOUND_V)
end

-- Bring the tank up to now: the refill since `at`, paid from the pack (B.draw: a powered charger pays instead). Off a
-- charger the pack never goes under the 12V floor for it (T.DCDC_MIN_PCT): what it can't pay is not refilled.
-- Returns thr and whether the client's copy (gas + the same refill estimate) is now wrong.
function H.settle(v, part)
    local md, now = part:getModData(), T.hours()
    local thr = md.thr
    if type(thr) ~= "table" or type(thr.gas) ~= "number" then
        thr = { gas = 1, at = now }
        md.thr = thr
        return thr, true
    end
    local add, cut = H.gasNow(thr, now) - thr.gas, false
    if add > 0 then
        local kwh = add * H.refillKwh()
        if kwh > 0 and not B.onCharger(part) then
            local spare = math.max(0, B.kwh(part) - B.capacity(part) * T.DCDC_MIN_PCT / 100)
            if spare < kwh then add, kwh, cut = add * spare / kwh, spare, true end
        end
        B.draw(v, part, kwh)
        thr.gas = math.min(1, thr.gas + add)
    end
    thr.at = now
    return thr, cut
end

-- the show's caller: how it went (PhoneApp.lua appDone shows the reason)
local function appTell(p, why)
    T.send(p.player, "appDone", { key = p.key, act = p.act, why = why })
end

local function finish(v, p, done, sec)
    pending[v:getId()] = nil
    local part = B.part(v)
    local thr = part and part:getModData().thr
    if type(thr) == "table" then
        if not done then
            thr.gas = math.min(1, (thr.gas or 0) + p.cost) -- never left the ground: the air back
        elseif p.act == "fly" and not H.freeFlight() then
            -- the seconds flown, never more than have passed since approval (a modified client can't stretch them)
            local real = (getTimestampMs() - p.ms) / 1000
            local s = type(sec) == "number" and sec == sec and math.min(math.max(0, sec), real) or real
            thr.gas = math.max(0, (thr.gas or 0) - s / H.flightSeconds())
        end
        thr.busy, thr.at = nil, T.hours() -- no refill while it ran (r2f-sp-1124b: a 16 s flight got 0.16 back)
        v:transmitPartModData(part)
    end
    fx(v, done and p.act ~= "boost" and "land" or nil)
    -- the physics this file handed out goes back to the server (BaseVehicle.java:10175-10180); a driver who got in
    -- meanwhile gets it as on any seat (:4012-4022)
    if isServer() and (p.held and v:getNetPlayerId() == p.held or p.orphan) then
        v:authorizationChanged(nil)
        local d = v:getDriver()
        if d and instanceof(d, "IsoPlayer") then v:authorizationServerOnSeat(d, true) end
    end
    if p.eng and not v:getDriver() and v:isEngineRunning() then v:engineDoShuttingDown() end
end

-- one-shot timer while an action has a due check (as the horn's, Remote.lua); removed when none is left
local ticking = false
local function tick()
    local now, due = getTimestampMs(), nil
    for vid, p in pairs(pending) do
        if p.due and now >= p.due then
            due = due or {}
            due[#due + 1] = vid
        end
    end
    if due then
        for _, vid in ipairs(due) do
            local p = pending[vid]
            if p then
                p.due = nil
                local v = getVehicleById(vid)
                if v then p.on(v, p) else pending[vid] = nil end -- unloaded: its busy flag is stale (see pending)
            end
        end
    end
    for _, p in pairs(pending) do if p.due then return end end
    Events.OnTick.Remove(tick)
    ticking = false
end

local function schedule(p, ms, on)
    p.due, p.on = getTimestampMs() + ms, on
    if not ticking then
        ticking = true
        Events.OnTick.Add(tick)
    end
end

local function nearest(v, skip)
    local best, bd = nil, H.HELP_RANGE
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do
        local q = list:get(i)
        if q ~= skip and not q:isDead() then
            local d = q:DistTo(v)
            if d < bd then best, bd = q, d end
        end
    end
    return best
end

local function airborne(v, p) return not p.h0 or v:getDebugZ() > p.h0 + LIFTED end

-- D3: the helper had its time; over, billed (it flew)
local function d3(v, p)
    finish(v, p, true)
    T.log("thrust " .. p.act .. " ended by the server vid=" .. v:getId())
end

-- q's machine takes the car's physics and lands it (client Thruster.lua thrustLand: the land controller, no driver)
local function handOver(v, p, q)
    p.helper, p.orphan, p.held = q, nil, q:getOnlineID()
    v:authorizationChanged(q)
    T.send(q, "thrustLand", { vid = v:getId() })
    schedule(p, HELP_MS, d3)
    T.log("thrust " .. p.act .. " handed to " .. tostring(q:getUsername()) .. " vid=" .. v:getId())
end

-- D2: the holder's machine never ended it (crash, disconnect: the server sees that only ~11 s later, poc/APP.md, so
-- online or not). Up in the air: the nearest other player within H.HELP_RANGE lands it; nobody: the server holds it
-- (it hangs where it is) and the busy flag says so until someone comes near (H.onUpdate, H.adopt).
local function d2(v, p)
    if not isServer() or not airborne(v, p) then return d3(v, p) end -- SP: this machine is the holder
    local q = nearest(v, p.helper or p.player)
    if q then return handOver(v, p, q) end
    v:authorizationChanged(nil)
    p.orphan, p.held = true, nil
    local part = B.part(v)
    local thr = part and part:getModData().thr
    if type(thr) == "table" and thr.busy then
        thr.busy.orphan = true
        v:transmitPartModData(part)
    end
    T.log("thrust " .. p.act .. " left in the air, nobody near vid=" .. v:getId())
end

-- an orphan (d2) goes to the first player who comes within H.HELP_RANGE: on each request and each parts update
function H.adopt()
    for vid, p in pairs(pending) do
        local v = p.orphan and getVehicleById(vid)
        local q = v and nearest(v)
        if q then handOver(v, p, q) end
    end
end

local function d2Due(act, sec, mapproach)
    if act == "fly" then return sec and mapproach + sec * 1000 + FLY_LAND_MS + SLACK_MS end -- nil: FreeFlight
    return mapproach + PROF_MS[act] + SLACK_MS
end

-- D1 (the show): off the ground by now, or the air back
local function d1(v, p)
    if not airborne(v, p) then
        finish(v, p, false)
        return appTell(p, "THRUST_NO_LIFT")
    end
    schedule(p, d2Due(p.act, nil, APPROACH_MS) - APPROACH_MS - LIFT_MS, d2)
end

-- the show's motor runs: the caller's machine takes the physics (only from -1, not towing: BaseVehicle.java:4012-4022)
local function go(v, p)
    if v:getDriver() or (isServer() and v:getNetPlayerId() ~= -1) then -- got in or taken meanwhile
        finish(v, p, false)
        return appTell(p, "THRUST_BUSY")
    end
    if isServer() then
        v:authorizationServerOnSeat(p.player, true)
        if v:getNetPlayerId() ~= p.player:getOnlineID() then
            finish(v, p, false)
            return appTell(p, "THRUST_BUSY")
        end
        p.held = p.player:getOnlineID()
    end
    schedule(p, APPROACH_MS + LIFT_MS, d1)
    noise(v)
    fx(v, FX[p.act])
    T.send(p.player, "thrustOk", { vid = v:getId(), act = p.act, app = true })
end

local function started(v, p)
    if v:isEngineRunning() then return go(v, p) end
    if p.tries < START_TRIES then
        p.tries = p.tries + 1
        v:tryStartEngine(true)
        return schedule(p, START_MS, started)
    end
    finish(v, p, false)
    appTell(p, "CANT_START")
end

-- the part brought up to now; a busy flag nobody holds (see pending) cleared, and the motor the server started off
local function prepare(v)
    local part = B.part(v)
    if not part or not part:getInventoryItem() then return part end
    local md = part:getModData()
    if type(md.thr) == "table" and md.thr.busy and not pending[v:getId()] then
        if md.thr.busy.eng and not v:getDriver() and v:isEngineRunning() then v:engineDoShuttingDown() end
        md.thr.busy = nil
    end
    H.settle(v, part)
    return part
end

local function bill(player, v, part, act, app, eng)
    local thr = part:getModData().thr
    local cost = math.min(thr.gas, H.COST[act] or 0) -- flying is billed at the end
    thr.gas = thr.gas - cost
    thr.busy = { act = act, by = T.account(player) or player:getUsername(), t = T.hours(), app = app, eng = eng }
    v:transmitPartModData(part)
    T.log(string.format("thrust %s vid=%d by=%s gas=%.2f%s", act, v:getId(), tostring(thr.busy.by), thr.gas,
        app and " (app)" or ""))
    return thr, cost
end

cmds.thrust = function(player, args)
    local v = T.commandVehicle(player, args)
    if not v then return end
    H.adopt()
    local vid, act = v:getId(), args.act
    if type(act) ~= "string" or not H.ACTS[act] then return T.deny(player, "BAD_VALUE", vid) end
    local part = prepare(v)
    local ok, why = H.can(player, v, act)
    if not ok then return T.deny(player, why, vid) end
    local thr, cost = bill(player, v, part, act)
    local sec = nil -- flying: the seconds of air there are (nil: FreeFlight, until the driver lands)
    if act == "fly" and not H.freeFlight() then sec = thr.gas * H.flightSeconds() end
    local p = { act = act, player = player, ms = getTimestampMs(), cost = cost,
        h0 = act ~= "land" and v:getDebugZ() or nil }
    pending[vid] = p
    local due = d2Due(act, sec, ROLL_MS)
    if due then schedule(p, due, d2) end
    noise(v)
    fx(v, FX[act])
    T.send(player, "thrustOk", { vid = vid, act = act, sec = sec })
end

-- The phone app's show (Remote.lua ACT.kickflip / backflip, after its key, reach and VM checks): bill, start the motor
-- if off (checked every 2 s, 3 tries), then the caller's machine flies the empty car. key: the phone key the app sent
-- (its later appDone goes to that car's page). Returns a deny reason or nil.
function H.appShow(player, v, act, key)
    H.adopt()
    local part = prepare(v)
    local ok, why = H.can(player, v, act, true)
    if not ok then return why end
    local api = T.Remote and T.Remote.summonApi and T.Remote.summonApi()
    if api and api.summonInfo and api.summonInfo(v) then return "THRUST_BUSY" end -- AutoDrive drives it
    local eng = not v:isEngineRunning()
    local _, cost = bill(player, v, part, act, true, eng or nil)
    local p = { act = act, player = player, ms = getTimestampMs(), cost = cost, h0 = v:getDebugZ(), app = true,
        eng = eng, key = key, tries = 1 }
    pending[v:getId()] = p
    if eng then
        v:tryStartEngine(true)
        schedule(p, START_MS, started)
    else
        go(v, p)
    end
end

-- the holder's machine (the driver, the show's caller, or the helper landing it): the action is over. done: it took
-- off (boost: it sped up); false = the air back. sec: seconds flown (flying only; the helper's say nothing).
cmds.thrustEnd = function(player, args)
    local v = T.commandVehicle(player, args, H.HELP_RANGE + 30, true) -- a show's caller stands up to 30 tiles away
    if not v then return end
    H.adopt()
    local p = pending[v:getId()]
    if not p or player ~= (p.helper or p.player) then return end -- only who flies it now ends it
    local done = args.done == true
    finish(v, p, done, not p.helper and tonumber(args.sec) or nil)
    if p.app and not done then appTell(p, "THRUST_NO_LIFT") end
end

-- Battery.lua T.Update.Battery, each game minute while the car's parts update: the refill's kWh as it goes, the
-- flight's noise, a FreeFlight (no D2) whose driver is gone, an orphan with someone now near, a stale busy flag.
function H.onUpdate(v, part)
    local thr = part:getModData().thr
    if type(thr) ~= "table" then return end
    local p = pending[v:getId()]
    if p then
        if p.act == "fly" then noise(v) end
        if p.orphan then
            local q = nearest(v)
            if q then handOver(v, p, q) end
        elseif not p.due and not p.app and not p.helper and v:getDriver() ~= p.player then
            d2(v, p)
        end
        return -- billing waits for the action's end
    end
    if thr.busy then -- nobody holds it (see pending): cleared, the motor the server started off
        prepare(v)
        v:transmitPartModData(part)
        return
    end
    if type(thr.gas) == "number" and thr.gas < 1 then
        local _, cut = H.settle(v, part)
        if cut then v:transmitPartModData(part) end
    end
end
