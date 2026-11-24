-- Thrusters, server side (and SP): approve an action (`thrust`, the driver; H.appShow, the phone app's show of the
-- empty car), bill the air tank, end it (`thrustEnd`) or, when the holder's machine never says so, have someone near
-- land it. The flying itself runs on the machine with the car's physics (client Thruster.lua). Shared rules: shared
-- Thruster.lua; design: .claude/skills/tesla-dev/references/roadster2.md. No watchdog: each action has due times
-- (the lift-off look every 500 ms until seen, D2 end, D3 the helper's landing), checked by a one-shot OnTick that
-- compares times only and is gone when none is left.
-- Each action carries `n`, the asking machine's own number for it (client Thruster.lua nextN): a client command is
-- reliable, not ordered (PacketTypes.java:508 ClientCommand reliability 2 = RELIABLE, RakNetPeerInterface.java:43-44),
-- so a late thrustEnd of the last action must not end this one.
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
-- D2, real ms past approval (the show: past its motor running): the approach (the driver's roll-up and the show's
-- both give up at 3 s, client Thruster.lua ROLL_S) + the action's profile (client PROF; boost 1.5 s) + off its
-- profile up to 4 s more (client `t > P.T + 4`) + the landing's cap (client LAND_S 12 s) + slack. Flying: its
-- seconds of air instead of the profile, and 5 s of slack (120 s of flight and a 12 s landing on a slow link). Long,
-- but D2 only matters when the holder's machine is gone.
local ROLL_MS, SLACK_MS, FLY_SLACK_MS, LAND_MS, OFF_MS = 3000, 2000, 5000, 12000, 4000
local PROF_MS = { kickflip = 3800, backflip = 2800 }
-- the lift-off look: every LOOK_MS from approval (the show: from its motor running) until seen, at most WINDOW_MS
-- (the approach's budget + 1.5 s: 9 looks); never seen by then, D2 on its time (the show: over now, the air back)
local LOOK_MS, WINDOW_MS = 500, ROLL_MS + 1500
-- D3: the helper's wait for the physics (client 2 s) + its landing's cap (LAND_MS) + 1 s; then, still up, the next one
local HELP_MS = 2000 + LAND_MS + 1000
local START_MS, START_TRIES = 2000, 3 -- tryStartEngine takes 1.7 s; 15 of 16 start first time (poc/APP.md)
local ABORT_MS = 500   -- an end said in the air: look again this much later (the server's copy lags ~0.1 s)
-- MP flying is billed by the server's own clock: from the look that saw it up to the end said on the ground, less
-- LAND_FLAT_S. r2fix-mp-a (FlightSeconds 20, flown 10 s and 20 s at 3 m): that span came out flown + 0.26 s both
-- times (the look sees the lift-off 0-0.5 s late, which eats most of the ~1.4 s landing from 3 m); 0.25 bills
-- what was flown to within a look. A landing from higher or lower than 3 m takes longer or shorter
-- shortcut: one flat landing time for every height (measured from 3 m only), when billing must be within a look
-- from any height: take the landing's own time from the holder's height at the end
H.LAND_FLAT_S = 0.25
local LAND_FLAT_S = H.LAND_FLAT_S

-- [vid] = { v = the car approved (ids are reused, VehicleIDMap.java:49-61), act, player, n = the asker's action
-- number, ms = approved at (nowMs), w0 = the lift-off looks' start (the show: its motor running), cost = air taken,
-- busy = the busy flag bill wrote, due = nowMs of the next check or nil, on = what that check runs, k0 = km/h then,
-- up / upMs = a look saw it off the ground (boost: sped up) and when, downMs = when the server saw the end on the
-- ground, avail = the seconds of air approved (flying), sec = seconds flown as the holder said (SP), app = the phone
-- show, eng = the server started the motor, held = the online id this file gave the car's physics to, helper = who
-- lands it, tried = { [player] = true } who had it and did not bring it down, orphan = up with nobody near }.
-- Server memory only: a busy flag without an entry here (a restart, an unload, SP reload) is stale.
local pending = {}
H.pending = pending

-- v's entry, if it is for this very car (another car may have its id now: that entry is dropped)
local function entry(v)
    local id = v:getId()
    local p = pending[id]
    if p and p.v ~= v then
        pending[id], p = nil, nil
    end
    return p
end

-- vid's car if it is still p's and in the world. The ground's square, not the car's own (BaseVehicle.getSquare is
-- the square at the car's height): up in the open air that level may have none
local function here(vid, p)
    local v = getVehicleById(vid)
    if v ~= p.v then return nil end
    return getCell():getGridSquare(math.floor(v:getX()), math.floor(v:getY()), 0) and v or nil
end

local function fx(v, mode)
    local f = T.ThrusterFx and T.ThrusterFx.set
    if f then f(v, mode) end
end

-- the motor this file started, off, also while it is still starting: Starting / RetryingStarting / StartingSuccess
-- run on into Running by themselves (VehicleEngine.java:202-212) while isEngineRunning is Running only (:355-357);
-- engineDoShuttingDown from any state is ShuttingDown, Idle 2 s later (:222-224, :416-422)
local function motorOff(v)
    if not v:getDriver() and (v:isEngineRunning() or v:isEngineStarted()) then v:engineDoShuttingDown() end
end

local function noise(v)
    addSound(v, math.floor(v:getX()), math.floor(v:getY()), math.floor(v:getZ()), SOUND_R, SOUND_V)
end

local function isN(n) return type(n) == "number" and n == n end
-- a refusal of the action numbered n (client Thruster.lua: its ask answered, a soft landing it started stopped); as
-- T.deny otherwise
local function deny(player, why, vid, n)
    T.send(player, "deny", { reason = why, vid = vid, pn = player:getPlayerNum(), n = isN(n) and n or nil })
end

-- What bringing the tank up to now would do, nothing written (a refusal changes nothing): { thr (nil: none yet, a
-- full one is made), gas = the air after, pack = kWh off the pack, cut = the pack's floor cut the refill }. The pack
-- pays all of it, plugged in or not (a charger's source pays back through the charge it adds: Charging.lua C.settle
-- settles the air first), never under the 12V floor for it (T.DCDC_MIN_PCT): what it can't pay is not refilled.
-- While an action runs nothing refills (its end sets `at`). nil: no thrusters.
function H.refill(v, part)
    if not H.conf(v) then return nil end
    local thr, now = part:getModData().thr, T.hours()
    if type(thr) ~= "table" or type(thr.gas) ~= "number" then return { gas = 1, now = now } end
    local r = { thr = thr, gas = thr.gas, now = now, pack = 0, cut = false }
    if entry(v) then r.running = true return r end
    local mid = H.gasNow(thr, type(thr.at) == "number" and thr.at or now)
    local add = H.gasNow(thr, now) - mid
    local kwh = add * H.refillKwh()
    if kwh > 0 then
        local spare = H.packSpare(part)
        if spare < kwh then add, kwh, r.cut = add * spare / kwh, spare, true end
    end
    r.pack = math.max(0, kwh)
    r.gas = math.max(0, math.min(1, mid + add))
    return r
end

-- r (H.refill) written: the tank and the kWh paid. Returns thr and whether the client's copy (gas + the same refill
-- estimate) is now wrong. The clock always moves on: a stretch the pack could not pay (at its floor) is not refilled
function H.applyRefill(v, part, r)
    if not r.thr then
        local thr = { gas = 1, at = r.now }
        part:getModData().thr = thr
        return thr, true
    end
    if r.running then return r.thr, false end
    if r.pack > 0 then B.set(v, part, B.kwh(part) - r.pack) end
    r.thr.gas, r.thr.at = r.gas, r.now
    return r.thr, r.cut
end

-- the tank brought up to now (H.refill, then written); thr and whether the client's copy is wrong. nil: no thrusters
function H.settle(v, part)
    local r = H.refill(v, part)
    if not r then return nil, false end
    return H.applyRefill(v, part, r)
end

-- the show's caller: how it went (PhoneApp.lua appDone shows the reason)
local function appTell(p, why)
    T.send(p.player, "appDone", { key = p.key, act = p.act, why = why })
end

-- off the ground: over GROUND floors above the highest floor under it (H.groundZ: a flat roof counts, as on the
-- flying machine). A car at rest sits 0.075-0.152 into its floor (poc/APP.md).
-- shortcut: a car falling past a floor's line reads as down for that look; a due check then ends it early (rare)
local GROUND = 0.25
local function airborne(v) return v:getDebugZ() - H.groundZ(v) > GROUND end

-- a car said at rest off the ground (cmds.thrustEnd rest: on its side, an eave, a fence, another car) still where it
-- was ABORT_MS later, its sayer still online: down for good. The sayer's machine holds the physics with its controller
-- off, so a car really in the air would have dropped ~1.25 m by then (~0.8 m in the server's copy, ~0.1 s behind); one
-- that went quiet (a crash) never says rest. REST_DM: the server's copy still settles after its holder's (r2rest-mp-near2:
-- 0.148 m in ABORT_MS; the same car rests 1.13 m up on its holder, 1.27-1.31 m on the others), so twice that
local REST_DXY, REST_DM = 0.15, 0.3 -- tiles, metres
local function stillAt(v, r)
    return getPlayerByOnlineID(r.by:getOnlineID()) == r.by and math.abs(v:getX() - r.x) < REST_DXY
        and math.abs(v:getY() - r.y) < REST_DXY and math.abs(v:getDebugZ() - r.z) * H.FLOOR < REST_DM
end
-- moved, but only as a car settles once its thrusters let go (r2scan-mp-r2 boostnearhold: leaning on a roof's wall,
-- 0.20-0.27 tiles on and 0.26-0.30 m lower each look, three hand-backs to its own driver): looked at again from where
-- it is now, up to SETTLE_N times; a car really in the air drops ~0.8 m in the server's copy by a look
local SETTLE_DXY, SETTLE_DM, SETTLE_N = 0.4, 0.4, 4
local function settling(v, r)
    return (r.looks or 0) < SETTLE_N and getPlayerByOnlineID(r.by:getOnlineID()) == r.by and math.abs(v:getX() - r.x) < SETTLE_DXY
        and math.abs(v:getY() - r.y) < SETTLE_DXY and math.abs(v:getDebugZ() - r.z) * H.FLOOR < SETTLE_DM
end

-- the clock every time here is on (ms): real time while the timer below runs, at most 250 ms a frame, never back.
-- The wall clock (getTimestampMs, System.currentTimeMillis) set back or forward moves it one frame's worth at most,
-- so a due check never runs early nor waits for the wall clock to catch up; a hitch only makes them later. SP: it
-- stops while the game is paused (the client's flight does too). It stands still while no check is due: an orphan
-- (d2, nobody near) has none, so its hanging time is not flown time (billed within the approved seconds anyway)
local ticking = false
local clock, last = 0, nil
local function nowMs() return clock end

-- the server's own look, never the client's word: off the ground (boost: sped up 7 km/h, client: 2 m/s)
local function look(v, p)
    if p.up then return true end
    local up
    if p.act == "boost" then up = math.abs(v:getCurrentSpeedKmHour()) >= p.k0 + 7 else up = airborne(v) end
    if up then p.up, p.upMs = true, nowMs() end
    return up
end

-- done: it flew (a look saw it; SP: the holder's word); false: the air back. MP flying is billed by the server's
-- clock (LAND_FLAT_S), never over the seconds approved; SP by p.sec, the seconds the holder's machine says it flew
-- (its own clock, a pause not counted), never over the time since approval
local function finish(v, p, done)
    pending[v:getId()] = nil
    local part = B.part(v)
    local thr = part and part:getModData().thr
    if type(thr) == "table" then
        local gas = type(thr.gas) == "number" and thr.gas or 0
        if not done then
            gas = gas + p.cost -- never left the ground: the air back
        elseif p.act == "fly" and not H.freeFlight() then
            local s
            if isServer() then
                local air = p.upMs and math.max(0, (p.downMs or nowMs()) - p.upMs) / 1000 or 0
                s = math.min(math.max(0, air - LAND_FLAT_S), p.avail or 0)
            else
                local real = math.max(0, nowMs() - p.ms) / 1000
                s = isN(p.sec) and p.sec or real
                s = math.min(math.max(0, s), real)
            end
            gas = gas - s / H.flightSeconds()
        end
        thr.gas = math.max(0, math.min(1, gas))
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
    if p.eng then motorOff(v) end
end

-- one-shot timer while an action has a due check (as the horn's, Remote.lua); removed when none is left. It reads
-- no car: only the check that is due does
local function tick()
    local t = getTimestampMs()
    if isServer() or not isGamePaused() then clock = clock + math.min(250, math.max(0, t - (last or t))) end
    last = t
    local now, due = nowMs(), nil
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
                -- the car approved, still in the world; else its busy flag is stale (see pending, H.onLoad)
                local v = here(vid, p)
                if v then p.on(v, p) else pending[vid] = nil end
            end
        end
    end
    for _, p in pairs(pending) do if p.due then return end end
    Events.OnTick.Remove(tick)
    ticking = false
end

local function schedule(p, ms, on)
    if not ticking then
        ticking, last = true, getTimestampMs()
        Events.OnTick.Add(tick)
    end
    p.due, p.on = nowMs() + ms, on
end

-- a machine's slot: its online ids are slot * 4 + its split-screen index (Commands.lua T.sendClients)
local function slot(q) return math.floor(q:getOnlineID() / 4) end

-- someone on q's machine holding another action now (its driver, or the one landing it): the flying controller is
-- the machine's own (client Thruster.lua F), so it refuses the hand-over, also for its other split-screen player,
-- and the car falls while it holds the physics before saying so (r2fix-mp-c: handed 5 times in 15 s, 6.79 m down in
-- steps). An orphan's own driver is not busy with it: back near, it is theirs to land. Only one still online counts:
-- a disconnected player's object keeps its online id, whose slot goes to the next connection (GameServer.java:2696-2726)
local function holding(q, p)
    local c = slot(q)
    for _, p2 in pairs(pending) do
        local h = p2.helper or p2.player
        if p2 ~= p and not p2.orphan and getPlayerByOnlineID(h:getOnlineID()) == h and slot(h) == c then return true end
    end
    return false
end

-- the nearest player within H.HELP_RANGE who has not had it (the caller, the driver, a helper who could not) and
-- whose machine is not holding another action
local function nearest(v, p)
    local best, bd = nil, H.HELP_RANGE
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do
        local q = list:get(i)
        if not p.tried[q] and not q:isDead() and not holding(q, p) then
            local d = q:DistTo(v)
            if d < bd then best, bd = q, d end
        end
    end
    return best
end

local d2

-- D3: the helper had its time. Down: over, billed (it flew); still up: it could not, the next one (d2)
local function d3(v, p)
    if isServer() and airborne(v) then return d2(v, p) end
    finish(v, p, true)
    T.log("thrust " .. p.act .. " ended by the server vid=" .. v:getId())
end

-- q's machine takes the car's physics and lands it (client Thruster.lua thrustLand: the land controller, no driver;
-- it says thrustEnd with this action's n and this hand-over's term when down, or at once when it can't). term: one
-- more each hand-over, as the same player may have it twice (tried forgotten, d2) and a late end of the first must
-- not end the second (commands are reliable, not ordered)
local function handOver(v, p, q)
    p.helper, p.orphan, p.held, p.term, p.rest = q, nil, q:getOnlineID(), (p.term or 0) + 1, nil
    v:authorizationChanged(q)
    T.send(q, "thrustLand", { vid = v:getId(), pn = q:getPlayerNum(), n = p.n, term = p.term })
    schedule(p, HELP_MS, d3)
    T.log("thrust " .. p.act .. " handed to " .. tostring(q:getUsername()) .. " vid=" .. v:getId())
end

-- D2: whoever holds it (the holder's machine, or a helper) never brought it down: crash, disconnect (the server sees
-- that only ~11 s later, poc/APP.md, so online or not), an end said in the air (thrustEnd). Down: over (the air back
-- if no look saw it go). Up: the nearest player who has not had it lands it; nobody: the server holds it (it hangs
-- where it is) and the busy flag says so until someone comes near (H.onUpdate, H.adopt), whoever that is: who could
-- not before may now
d2 = function(v, p)
    local r = p.rest
    p.rest = nil
    if isServer() and r and airborne(v) then
        if stillAt(v, r) then
            p.downMs = r.ms
            finish(v, p, p.up == true)
            return T.log("thrust " .. p.act .. " ended at rest off the ground vid=" .. v:getId())
        end
        T.log(string.format("thrust %s said at rest but moved vid=%d dx=%.3f dy=%.3f dm=%.3f online=%s look=%d", p.act, v:getId(),
            v:getX() - r.x, v:getY() - r.y, (v:getDebugZ() - r.z) * H.FLOOR, tostring(getPlayerByOnlineID(r.by:getOnlineID()) == r.by), r.looks or 0))
        if settling(v, r) then
            p.rest = { x = v:getX(), y = v:getY(), z = v:getDebugZ(), by = r.by, ms = r.ms, looks = (r.looks or 0) + 1 }
            return schedule(p, ABORT_MS, d2)
        end
    end
    if not isServer() or not airborne(v) then -- SP: this machine is the holder
        local done = p.up == true
        finish(v, p, done)
        if p.app and not done then appTell(p, "THRUST_NO_LIFT") end
        return T.log("thrust " .. p.act .. " ended by the server vid=" .. v:getId())
    end
    if not p.up then p.up, p.upMs = true, nowMs() end -- up now: it went
    p.tried[p.helper or p.player] = true
    local q = nearest(v, p)
    if q then return handOver(v, p, q) end
    v:authorizationChanged(nil)
    p.orphan, p.held, p.helper, p.tried = true, nil, nil, {}
    local part = B.part(v)
    local thr = part and part:getModData().thr
    if type(thr) == "table" and thr.busy then
        thr.busy.orphan = true
        v:transmitPartModData(part)
    end
    T.log("thrust " .. p.act .. " left in the air, nobody near vid=" .. v:getId())
end

-- an orphan (d2) goes to the first player who comes within H.HELP_RANGE: on each request and each parts update.
-- An entry whose car is gone (unloaded, its id another car's) is dropped (its busy flag is stale: H.onLoad)
function H.adopt()
    for vid, p in pairs(pending) do
        local v = here(vid, p)
        if not v then
            pending[vid] = nil
        elseif p.orphan then
            local q = nearest(v, p)
            if q then handOver(v, p, q) end
        end
    end
end

-- ms from the looks' start to D2 (see ROLL_MS); nil: FreeFlight, no D2
local function d2Due(act, sec)
    if act == "fly" then return sec and ROLL_MS + sec * 1000 + LAND_MS + FLY_SLACK_MS end
    if act == "boost" then return ROLL_MS + 1500 + SLACK_MS end
    if act == "land" then return LAND_MS + SLACK_MS end
    return ROLL_MS + PROF_MS[act] + OFF_MS + LAND_MS + SLACK_MS
end

-- the looks are over: D2 on its time (FreeFlight: none; the end or the next parts update ends it)
local function toD2(p)
    local ms = d2Due(p.act, p.avail)
    if ms then schedule(p, math.max(0, p.w0 + ms - nowMs()), d2) end
end

-- the lift-off look (see LOOK_MS) on the looks' grid, w0 + k * LOOK_MS, the last at w0 + WINDOW_MS (a late frame
-- moves no later look; looks missed are not made up): seen, D2 on its time; the window over unseen: D2 on its time
-- (the show: over now, the air back: it never left the ground)
local function witness(v, p)
    if look(v, p) then return toD2(p) end
    local t = nowMs() - p.w0
    if t >= WINDOW_MS then
        if p.app then return d2(v, p) end
        return toD2(p)
    end
    schedule(p, math.min(WINDOW_MS, (math.floor(t / LOOK_MS) + 1) * LOOK_MS) - t, witness)
end

-- the show still allowed as when it was approved: its caller online, near, with DRIVE, still holding the phone key
-- with the car in the phone's reach (Remote.lua R.appLink: NO_PHONE_KEY, NO_LINK); the car free, no cable in, its
-- busy flag still this show's (H.can with it and the air it took aside). false and the reason (nil: the caller is
-- gone, nobody to tell)
local function stillOk(v, p)
    if isServer() then
        local list, on = getOnlinePlayers(), false
        for i = 0, list:size() - 1 do
            if list:get(i) == p.player then on = true break end
        end
        if not on then return false, nil end
    end
    local ok, why = H.can(p.player, v, p.act, true, nil, p.busy)
    if not ok then return false, why end
    local part = B.part(v)
    local thr = part and part:getModData().thr
    if type(thr) ~= "table" or thr.busy ~= p.busy then return false, "THRUST_BUSY" end
    why = T.Remote.appLink(p.player, v, p.key)
    if why then return false, why end
    return true
end
local function refuse(v, p, why)
    finish(v, p, false)
    if why then appTell(p, why) end
end

-- the show's motor runs: the caller's machine takes the physics (only from -1, not towing: BaseVehicle.java:4012-4022)
local function go(v, p)
    local ok, why = stillOk(v, p)
    if not ok then return refuse(v, p, why) end
    if isServer() then
        v:authorizationServerOnSeat(p.player, true)
        if v:getNetPlayerId() ~= p.player:getOnlineID() then return refuse(v, p, "THRUST_BUSY") end
        p.held = p.player:getOnlineID()
    end
    p.w0 = nowMs()
    schedule(p, LOOK_MS, witness)
    noise(v)
    fx(v, FX[p.act])
    T.send(p.player, "thrustOk", { vid = v:getId(), act = p.act, app = true, pn = p.player:getPlayerNum(), n = p.n })
end

local function started(v, p)
    if v:isEngineRunning() then return go(v, p) end
    if p.tries < START_TRIES then
        local ok, why = stillOk(v, p)
        if not ok then return refuse(v, p, why) end
        p.tries = p.tries + 1
        v:tryStartEngine(true)
        return schedule(p, START_MS, started)
    end
    refuse(v, p, "CANT_START")
end

-- a busy flag nobody holds (see pending) cleared, and the motor the server started for it off; returns the battery
-- part. Only a tank there already is touched
local function clearStale(v)
    local part = B.part(v)
    if not part or not part:getInventoryItem() then return part end
    local thr = part:getModData().thr
    if type(thr) == "table" and thr.busy and not entry(v) then
        if thr.busy.eng then motorOff(v) end
        thr.busy = nil
        v:transmitPartModData(part)
    end
    return part
end

-- after H.can: the air there really is once the refill is paid (H.refill); enough: written, thr returned; not: nil
-- and THRUST_NO_AIR, nothing written (the pack's floor cut the refill the clients' estimate counts on)
local function settleFor(v, part, act)
    local r = H.refill(v, part)
    if r.gas + 1e-9 < H.need(act) then return nil, "THRUST_NO_AIR" end
    return (H.applyRefill(v, part, r))
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

-- args { vid, act, n, over }: n the asker's number for this action (BAD_VALUE without one). A refusal changes nothing
-- kept (a stale busy flag aside); approved: thrustOk { vid, act, sec (flying: the seconds of air; nil: FreeFlight), n,
-- pn }. A soft landing asked by the driver whose own action still runs here names it (over = its n): a stunt asked on
-- a roof's edge, the car fallen off before its answer, or a boost the driver's machine ended off an edge (its
-- thrustEnd, sent the same frame, may arrive after: RELIABLE, unordered, PacketTypes.java:508). Checked with that one's
-- busy flag as its own, it ends that one first (billed if a look saw it go, a boost's speed read now; else the air
-- back); that one's late thrustEnd then names no action here. Refused (the motor off meanwhile, ...): that one stays as
-- it was. Anyone else's action, a show, a landing, an
-- ask it does not name: THRUST_BUSY as ever. The car not found is refused here, with n (T.commandVehicle's own
-- refusal has none: on the client it would answer no ask, and a soft landing begun before the answer would run on
-- unbilled)
cmds.thrust = function(player, args)
    local v = T.commandVehicle(player, args, nil, true)
    if not v then
        if not player or type(args) ~= "table" then return end
        return deny(player, "NO_VEHICLE", isN(args.vid) and args.vid or nil, args.n)
    end
    local vid, act, n = v:getId(), args.act, args.n
    if type(act) ~= "string" or not H.ACTS[act] or not isN(n) then return deny(player, "BAD_VALUE", vid, n) end
    H.adopt()
    local own = act == "land" and entry(v)
    if not (own and own.player == player and not own.app and own.act ~= "land" and not own.helper and not own.orphan
        and v:isDriver(player) and isN(args.over) and own.n == args.over) then own = nil end
    local part = clearStale(v)
    local ok, why = H.can(player, v, act, nil, nil, own and own.busy or nil)
    if not ok then return deny(player, why, vid, n) end
    if own then
        if own.act == "boost" then look(v, own) end -- pushed out over the edge: its speed shows it went
        finish(v, own, own.up == true)
        T.log("thrust " .. own.act .. " ended by its driver's soft landing vid=" .. vid)
    end
    local thr
    thr, why = settleFor(v, part, act)
    if not thr then return deny(player, why, vid, n) end
    local _, cost = bill(player, v, part, act, nil, nil) -- all six given: Kahlua does not fill left-out fixed parameters
    local sec = nil -- flying: the seconds of air there are (nil: FreeFlight, until the driver lands)
    if act == "fly" and not H.freeFlight() then sec = thr.gas * H.flightSeconds() end
    local now = nowMs()
    local p = { v = v, act = act, player = player, n = n, ms = now, w0 = now, cost = cost, busy = thr.busy, tried = {},
        k0 = math.abs(v:getCurrentSpeedKmHour()), avail = sec }
    pending[vid] = p
    -- the soft landing: a falling car is up already (one look now)
    if act == "land" and look(v, p) then toD2(p) else schedule(p, LOOK_MS, witness) end
    noise(v)
    fx(v, FX[act])
    T.send(player, "thrustOk", { vid = vid, act = act, sec = sec, n = n, pn = player:getPlayerNum() })
end

-- The phone app's show (Remote.lua ACT.kickflip / backflip, after its key, reach and VM checks): bill, start the motor
-- if off (checked every 2 s, 3 tries), then the caller's machine flies the empty car; the show's checks run again
-- before each try and before the physics goes (stillOk). key: the phone key the app sent (its later appDone goes to
-- that car's page); n: the caller's number for this action. Returns a deny reason or nil.
function H.appShow(player, v, act, key, n)
    if not isN(n) then return "BAD_VALUE" end
    H.adopt()
    local part = clearStale(v)
    local ok, why = H.can(player, v, act, true)
    if not ok then return why end
    local thr
    thr, why = settleFor(v, part, act)
    if not thr then return why end
    local eng = not v:isEngineRunning()
    local _, cost = bill(player, v, part, act, true, eng or nil)
    local p = { v = v, act = act, player = player, n = n, ms = nowMs(), cost = cost, busy = thr.busy, k0 = 0,
        app = true, eng = eng, key = key, tries = 1, tried = {} }
    pending[v:getId()] = p
    if eng then
        v:tryStartEngine(true)
        schedule(p, START_MS, started)
    else
        go(v, p)
    end
end

-- args { vid, act, done, sec, abort, n, term, rest }, from the holder's machine (the driver, the show's caller, or the
-- helper landing it) with this action's n (any other: ignored); a helper's also with its hand-over's term (handOver).
-- The action is over, or it can't go on (the physics left, someone sat in). MP: the server judges it, never the
-- client's word: still up, it looks again ABORT_MS later and hands it on (d2); down, over now (the air back only if
-- no look saw it go). rest (true: a soft landing at rest off the ground): still up, and still where it was ABORT_MS
-- later with its sayer online, it is over there (d2, stillAt).
-- A boost its driver ends, still in the seat, is over at its end, up or not: it has no landing of
-- its own and was billed on approval; a car falling off a roof after it is the driver's soft landing (client H.watch),
-- which a busy flag would refuse. Handed on (a helper's end) or its driver gone, the air path as any action's.
-- SP: done (false = the air back) and sec (seconds flown, flying) are this machine's own.
cmds.thrustEnd = function(player, args)
    local v = T.commandVehicle(player, args, H.HELP_RANGE + 30, true) -- a show's caller stands up to 30 tiles away
    if not v then return end
    H.adopt()
    local p = entry(v)
    if not p or player ~= (p.helper or p.player) or args.n ~= p.n then return end -- only who flies it now ends it
    if p.helper and args.term ~= p.term then return end -- a helper's end of an earlier hand-over
    if isServer() then
        look(v, p) -- a boost: its speed now
        if p.act == "boost" and not p.helper and v:getDriver() == player then
            finish(v, p, p.up == true)
            return T.log("thrust boost ended vid=" .. v:getId())
        end
        if airborne(v) then
            -- at rest off the ground (client: still REST_S in its soft landing): where it is now, to end it there if
            -- it has not moved ABORT_MS later (d2). Only this end's spot counts: any other end, a hand-over drop it
            p.rest = args.rest == true and { x = v:getX(), y = v:getY(), z = v:getDebugZ(), by = player, ms = nowMs() } or nil
            T.log(string.format("thrust %s end said in the air vid=%d rest=%s abort=%s by=%s", p.act, v:getId(), tostring(args.rest == true),
                tostring(args.abort), tostring(player:getUsername())))
            return schedule(p, ABORT_MS, d2)
        end
        p.downMs = nowMs()
        return d2(v, p)
    end
    if not p.helper then p.sec = tonumber(args.sec) end
    local done = args.done == true
    finish(v, p, done)
    if p.app and not done then appTell(p, "THRUST_NO_LIFT") end
end

-- Battery.lua T.Update.Battery, each game minute while the car's parts update: the refill's kWh as it goes, the
-- flight's noise and jets (a client that came near since hears and sees them; ThrusterFx.lua renews its hiss without
-- the take-off glow), a FreeFlight (no D2) whose driver is gone, an orphan with someone now near (H.adopt), a stale
-- busy flag.
function H.onUpdate(v, part)
    H.adopt()
    local thr = part:getModData().thr
    if type(thr) ~= "table" then return end
    local p = entry(v)
    if p then
        if p.act == "fly" then
            noise(v)
            fx(v, "lift")
        end
        if not p.orphan and not p.due and not p.app and not p.helper and v:getDriver() ~= p.player then
            d2(v, p)
        end
        return -- billing waits for the action's end
    end
    if thr.busy then clearStale(v) end -- nobody holds it (see pending): cleared, the motor the server started off
    if type(thr.gas) == "number" and thr.gas < 1 then
        local _, cut = H.settle(v, part)
        if cut then v:transmitPartModData(part) end
    end
end

-- a car loaded (every load, BaseVehicle.java:904): a busy flag nobody holds (a restart, an unload) is cleared, and the
-- motor the server started for it off (clearStale)
function H.onLoad(v)
    local part = B.part(v)
    local thr = part and part:getModData().thr
    if type(thr) == "table" and thr.busy and not entry(v) then clearStale(v) end
end
Events.OnSpawnVehicleEnd.Add(H.onLoad)
