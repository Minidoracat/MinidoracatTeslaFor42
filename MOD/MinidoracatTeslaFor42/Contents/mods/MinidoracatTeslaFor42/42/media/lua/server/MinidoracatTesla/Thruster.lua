-- Thrusters, server side (and SP): approve an action (`thrust`), bill the air tank, end it (`thrustEnd`) or expire it
-- when the driver's machine never says so. The flying itself runs on the machine with the car's physics (client
-- Thruster.lua). Shared rules: shared Thruster.lua; design: .claude/skills/tesla-dev/references/roadster2.md.
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
-- real ms past approval an action may run before the server ends it itself: the client's roll-up (3 s) + the action +
-- its landing; flying: its seconds of air + 15 s
local SPAN = { kickflip = 15000, backflip = 15000, boost = 8000, land = 15000 }

-- [vid] = { act, player, ms = approved at (getTimestampMs), cost = air taken, deadline = ms or nil (FreeFlight) };
-- server memory only: a busy flag without an entry here (a server restart) is stale
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
        thr.busy = nil
        v:transmitPartModData(part)
    end
    fx(v, done and p.act ~= "boost" and "land" or nil)
end

-- the driver's machine never ended it (crash, disconnect). A driverless car left mid-air stays where the server's
-- physics holds it (flight PoC: about 98 s): the nearest player's machine takes it as after a collision
-- (Authorization.LocalCollide, BaseVehicle.java:3991-4000) and hands it back once it lies still for 1 s
-- (WorldSimulation.java:184-197), so it falls and lands.
local function expire(vid, p)
    local v = getVehicleById(vid)
    if not v then pending[vid] = nil return end -- unloaded: its busy flag is stale (no entry), cleared on the next `thrust`
    finish(v, p, true, nil)
    T.log("thrust " .. p.act .. " expired vid=" .. vid)
    if not isServer() or v:getDriver() then return end
    local best, bd = nil, 40
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do
        local q = list:get(i)
        local d = q:DistTo(v)
        if d < bd and not q:isDead() then best, bd = q, d end
    end
    if best then v:authorizationServerCollide(best:getOnlineID(), true) end
end

-- one-shot timer while an action with a deadline runs (as the horn's, Remote.lua); removed when none is left
local ticking = false
local function tick()
    local now, due, left = getTimestampMs(), nil, false
    for vid, p in pairs(pending) do
        if p.deadline and now >= p.deadline then
            due = due or {}
            due[#due + 1] = vid
        elseif p.deadline then
            left = true
        end
    end
    if due then for _, vid in ipairs(due) do expire(vid, pending[vid]) end end
    if not left then
        Events.OnTick.Remove(tick)
        ticking = false
    end
end

cmds.thrust = function(player, args)
    local v = T.commandVehicle(player, args)
    if not v then return end
    local vid, act = v:getId(), args.act
    if type(act) ~= "string" or not H.ACTS[act] then return T.deny(player, "BAD_VALUE", vid) end
    local part = B.part(v)
    if part and part:getInventoryItem() then
        local md = part:getModData()
        if type(md.thr) == "table" and md.thr.busy and not pending[vid] then md.thr.busy = nil end -- stale (see pending)
        H.settle(v, part)
    end
    local ok, why = H.can(player, v, act)
    if not ok then return T.deny(player, why, vid) end
    local thr = part:getModData().thr
    local cost = math.min(thr.gas, H.COST[act] or 0) -- flying is billed at the end
    thr.gas = thr.gas - cost
    thr.busy = { act = act, by = T.account(player) or player:getUsername(), t = T.hours() }
    v:transmitPartModData(part)
    local sec = nil -- flying: the seconds of air there are (nil: FreeFlight, until the driver lands)
    if act == "fly" and not H.freeFlight() then sec = thr.gas * H.flightSeconds() end
    local now = getTimestampMs()
    local span = act == "fly" and (sec and sec * 1000 + 15000) or SPAN[act]
    pending[vid] = { act = act, player = player, ms = now, cost = cost, deadline = span and now + span or nil }
    if span and not ticking then
        ticking = true
        Events.OnTick.Add(tick)
    end
    noise(v)
    fx(v, FX[act])
    T.send(player, "thrustOk", { vid = vid, act = act, sec = sec })
    T.log(string.format("thrust %s vid=%d by=%s gas=%.2f", act, vid, tostring(thr.busy.by), thr.gas))
end

-- the driver's machine: the action is over. done: it took off (boost: it sped up); false = the air back.
-- sec: seconds flown (flying only).
cmds.thrustEnd = function(player, args)
    local v = T.commandVehicle(player, args, nil, true)
    if not v then return end
    local p = pending[v:getId()]
    if not p or p.player ~= player then return end -- only the driver it was approved for ends it
    finish(v, p, args.done == true, tonumber(args.sec))
end

-- Battery.lua T.Update.Battery, each game minute while the car's parts update: the refill's kWh as it goes, the
-- flight's noise, and a FreeFlight (no deadline) whose driver is gone.
function H.onUpdate(v, part)
    local thr = part:getModData().thr
    if type(thr) ~= "table" then return end
    local p = pending[v:getId()]
    if p then
        if p.act == "fly" then noise(v) end
        if not p.deadline and v:getDriver() ~= p.player then expire(v:getId(), p) end
        return -- billing waits for the action's end
    end
    if type(thr.gas) == "number" and thr.gas < 1 then
        local _, cut = H.settle(v, part)
        if cut then v:transmitPartModData(part) end
    end
end
