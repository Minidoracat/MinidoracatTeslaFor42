-- Charging: plug / unplug, time-difference settlement, grid first then generator fuel, cable length, relink after
-- restart, and the charge commands. No OnTick: EveryTenMinutes is one comparison unless a settle is due.
-- Link state lives in the battery part modData `chg` (architecture.md section 4); the charger Lua object only holds vid.
if isClient() then return end
require "MinidoracatTesla/Chargers"
require "MinidoracatTesla/Battery"
require "MinidoracatTesla/ChargerSystem"

local T = MinidoracatTesla
local B = T.Battery
local C = T.Charge or {} -- client/ChargerMenu.lua adds the queue helpers to the same table in SP
T.Charge = C

C.DEFAULT_TARGET = 90
C.MAX_STEP_H = 1      -- re-settle at least hourly: generator switched off, car towed away, power back
C.RETRY_H = 1 / 6     -- charger square not loaded yet: try again next EveryTenMinutes
local HUGE = 1e30
local DIRS = { "N", "S", "W", "E" }

local active, activeCount, nextDueHour = {}, 0, HUGE -- active[luaObject] = due world hour

local function sys() return SMinidoracatTeslaChargerSystem and SMinidoracatTeslaChargerSystem.instance end

-- nextDueHour stays the exact minimum; the O(active) rescan only runs on settles, never in the idle path
local function recompute()
    nextDueHour = HUGE
    for _, d in pairs(active) do
        if d < nextDueHour then nextDueHour = d end
    end
end
function C.schedule(o, due)
    local old = active[o]
    if old == nil then activeCount = activeCount + 1 end
    active[o] = due
    if due <= nextDueHour then nextDueHour = due
    elseif old ~= nil and old <= nextDueHour then recompute() end
end
function C.unschedule(o)
    local old = active[o]
    if old == nil then return end
    active[o] = nil
    activeCount = activeCount - 1
    if old <= nextDueHour then recompute() end
end
function C.activeCount() return activeCount end
function C.nextDue() return nextDueHour end

-- world hour when grid power ends: doesPowerGridExist is worldAgeDays <= ElecShutModifier (SandboxOptions.java:1290-1292),
-- worldAgeDays = hours/24 + (TimeSinceApo-1)*30 (GameTime.java:897-899)
function C.gridOffHour()
    local shut = SandboxVars.ElecShutModifier
    if type(shut) ~= "number" then return HUGE end
    return (shut - (getSandboxOptions():getTimeSinceApo() - 1) * 30) * 24
end

-- fridge rule (ItemContainer.java:2307-2330): grid reaches this square if it is not a no-power zone and it or a
-- neighbour is inside a room. Returns the world hour the grid lasts until (-HUGE = never had it).
local function gridUntil(sq)
    if sq:isNoPower() then return -HUGE end -- IsoGridSquare.java:11617
    local room = sq:getRoom() ~= nil
    for i = 1, #DIRS do
        if room then break end
        local a = sq:getAdjacentSquare(IsoDirections[DIRS[i]])
        room = a ~= nil and a:getRoom() ~= nil
    end
    return room and C.gridOffHour() or -HUGE
end

local function genAt(x, y, z)
    local sq = getCell():getGridSquare(x, y, z)
    local g = sq and sq:getGenerator() -- IsoGridSquare.java:9713
    if g and g:isActivated() and g:getFuel() > 0 then return g end
    return nil
end

-- a running generator powering the charger square: cached square first, else one scan of the generator range.
-- ponytail: square scan (41x41x7 at defaults) only when the cache misses; keep a generator index if it shows up in profiles
function C.findGenerator(o, sq)
    if not sq:haveElectricity() then return nil end -- IsoGridSquare.java:9696-9700
    if o.gx then
        local g = genAt(o.gx, o.gy, o.gz)
        if g then return g end
        o.gx, o.gy, o.gz = nil, nil, nil
    end
    local r = SandboxVars.GeneratorTileRange or 20
    local vr = SandboxVars.GeneratorVerticalPowerRange or 3
    for z = o.z - vr, o.z + vr do
        for x = o.x - r, o.x + r do
            for y = o.y - r, o.y + r do
                local g = genAt(x, y, z)
                if g then o.gx, o.gy, o.gz = x, y, z; return g end
            end
        end
    end
    return nil
end

local function touchVM(vehicle)
    local mvm = MinidoracatVehicleManager
    if mvm and mvm.Parked and mvm.Parked.touch then mvm.Parked.touch(vehicle) end -- ParkedGuard.lua:258-261
end

function C.unlink(o)
    C.unschedule(o)
    if o.vid then
        -- false, not nil: the update packet only carries keys that have a value, so nil would leave the client's old vid
        -- (CGlobalObjectSystem.java:62-70 rawsets only what arrives)
        o.vid = false
        o:updateOnClient()
    end
end

local function clearChg(vehicle, part)
    part:getModData().chg = nil
    vehicle:transmitPartModData(part)
    touchVM(vehicle)
end

-- Book energy from chg.last to now, pick the source for what comes next, schedule the next settle.
-- here = true skips the cable check (unplugging: the car is still at the charger).
function C.settle(o, now, here)
    local v = o.vid and getVehicleById(o.vid)
    if not v then return C.unschedule(o) end -- car unloaded: relink resumes it when it loads
    local part = B.part(v)
    local md = part and part:getModData()
    local chg = md and md.chg
    if not chg or not part:getInventoryItem() then return C.unlink(o) end
    local iso = o:getIsoObject()
    if not iso then return C.schedule(o, now + C.RETRY_H) end
    if not here and not T.cableReaches(o.kind, o.x, o.y, o.z, v) then return C.stop(o, v, "tooFar") end
    local c = T.Chargers[o.kind]
    local kw = c.kw * T.chargeMul()
    local sq = iso:getSquare()
    local t0 = math.min(chg.last or now, now)
    local cap = B.capacity(part)
    local limit = cap * chg.target / 100
    local needH = math.max(0, limit - B.kwh(part)) / kw
    local gUntil = gridUntil(sq)
    local rate = c.fuelPerHour * (SandboxVars.GeneratorFuelConsumption or 0.1)
    local hours = 0
    if chg.paused ~= "stopped" and needH > 0 and now > t0 then
        local gridH = math.min(math.max(0, math.min(now, gUntil) - t0), needH)
        local rest = math.min(now - t0 - gridH, needH - gridH)
        local genH = 0
        if rest > 0 then
            local g = C.findGenerator(o, sq)
            if g then
                genH = rate > 0 and math.min(rest, g:getFuel() / rate) or rest
                if rate > 0 then g:setFuel(g:getFuel() - rate * genH) end -- syncs from the server (IsoGenerator.java:509-518)
            end
        end
        hours = gridH + genH
    end
    if hours > 0 then chg.added = (chg.added or 0) + B.add(v, kw * hours, chg.target) end
    chg.kw, chg.last = kw, now
    -- state from now on
    local src, gen = nil, nil
    if now < gUntil then
        src = "grid"
    else
        gen = C.findGenerator(o, sq)
        if gen then src = "generator" end
    end
    local left = math.max(0, limit - B.kwh(part))
    if chg.paused == "stopped" then
        src = nil
    elseif left <= 1e-6 then
        chg.paused, src = "full", nil
    elseif not src then
        chg.paused = "nopower"
    else
        chg.paused = nil
    end
    chg.src = src
    md.chg = chg
    v:transmitPartModData(part)
    local step = C.MAX_STEP_H
    if src then step = math.min(step, left / kw) end
    if src == "grid" then step = math.min(step, gUntil - now) end
    if gen and rate > 0 then step = math.min(step, gen:getFuel() / rate) end
    C.schedule(o, now + math.max(step, 1 / 60))
end

function C.start(o, v)
    local now = T.hours()
    local f = T.Sentry and T.Sentry.settle
    if f then f(v, now) end
    local part = B.part(v)
    part:getModData().chg = { x = o.x, y = o.y, z = o.z, kind = o.kind, kw = T.Chargers[o.kind].kw * T.chargeMul(),
        last = now, added = 0, src = nil, target = C.DEFAULT_TARGET, paused = nil }
    o.vid = v:getId()
    o:updateOnClient()
    C.settle(o, now)
    touchVM(v)
    T.log("plugged " .. tostring(v:getId()) .. " into " .. o.kind .. " at " .. o.x .. "," .. o.y .. "," .. o.z)
end

-- reason: "unplug" | "tooFar" | "removed"
function C.stop(o, v, reason)
    local part = v and B.part(v)
    if part and part:getModData().chg then
        if reason ~= "tooFar" and o and o:getIsoObject() then
            local ok, err = pcall(C.settle, o, T.hours(), true) -- book the energy up to now
            if not ok then T.log("settle before unplug failed: " .. tostring(err)) end
        end
        clearChg(v, part)
    end
    if o then C.unlink(o) end
    T.log("unplugged " .. tostring(v and v:getId()) .. " (" .. tostring(reason) .. ")")
end

function C.onChargerRemoved(o)
    local v = o.vid and getVehicleById(o.vid)
    if v then C.stop(o, v, "removed") else C.unschedule(o) end
end

-- ---- player actions (timed action complete(), server / SP) ----

function C.plug(player, v, iso)
    local s = sys()
    local o = s and iso and iso:getSquare() and s:getLuaObjectOnSquare(iso:getSquare())
    local vid = v and v:getId()
    if not o then return T.deny(player, "NO_CHARGER", vid) end
    local part = B.part(v)
    if not part then return T.deny(player, "NO_VEHICLE", vid) end
    if not part:getInventoryItem() then return T.deny(player, "NO_PACK", vid) end
    if part:getModData().chg then return T.deny(player, "PLUGGED", vid) end
    if o.vid and getVehicleById(o.vid) then return T.deny(player, "CHARGER_BUSY", vid) end
    if v:isEngineRunning() then return T.deny(player, "ENGINE_ON", vid) end
    if player:DistTo(v) > T.NEAR then return T.deny(player, "TOO_FAR", vid) end
    if not T.cableReaches(o.kind, o.x, o.y, o.z, v) then return T.deny(player, "CABLE_SHORT", vid) end
    local ok, why = T.authorized(player, v, "FUEL")
    if not ok then
        T.log("plug refused for " .. tostring(player:getUsername()) .. ": " .. tostring(why))
        return T.deny(player, "NOT_OWNER", vid)
    end
    C.start(o, v)
end

function C.unplug(player, v)
    local part = B.part(v)
    local chg = part and part:getModData().chg
    local vid = v and v:getId()
    if not chg then return T.deny(player, "NOT_PLUGGED", vid) end
    local ok, why = T.authorized(player, v, "FUEL")
    if not ok then
        T.log("unplug refused for " .. tostring(player:getUsername()) .. ": " .. tostring(why))
        return T.deny(player, "NOT_OWNER", vid)
    end
    local s = sys()
    C.stop(s and s:getLuaObjectAt(chg.x, chg.y, chg.z), v, "unplug")
end

-- every game minute while the car's parts update (someone drove / towed it): cable length
function C.checkCable(vehicle, part, chg)
    if not instanceof(vehicle, "BaseVehicle") then return end -- SP VirtualVehicle has no attachments
    if T.cableReaches(chg.kind, chg.x, chg.y, chg.z, vehicle) then return end
    local s = sys()
    C.stop(s and s:getLuaObjectAt(chg.x, chg.y, chg.z), vehicle, "tooFar")
end

-- ---- relink: vehicles get a new id every load; the battery part remembers the charger square ----
function C.relink(v)
    local part = B.part(v)
    local chg = part and part:getModData().chg
    if not chg then return end
    local s = sys()
    local o = s and s:getLuaObjectAt(chg.x, chg.y, chg.z)
    local other = o and o.vid and o.vid ~= v:getId() and getVehicleById(o.vid)
    if not o or other then
        clearChg(v, part)
        T.log("relink: charger gone or taken, cable cleared on " .. tostring(v:getId()))
        return
    end
    o.vid = v:getId()
    o:updateOnClient()
    local now = T.hours()
    local f = T.Sentry and T.Sentry.settle
    if f then f(v, now) end
    C.settle(o, now)
    T.log("relinked " .. tostring(v:getId()) .. " to " .. o.kind .. " at " .. o.x .. "," .. o.y .. "," .. o.z)
end

-- vehicle load runs createPhysics, which fires OnSpawnVehicleEnd every time (BaseVehicle.java:7952-7964, :904)
Events.OnSpawnVehicleEnd.Add(function(v)
    if T.isTesla(v) then C.relink(v) end
end)

Events.EveryTenMinutes.Add(function()
    if activeCount == 0 then return end
    local now = T.hours()
    if now < nextDueHour then return end
    local due = {}
    for o, d in pairs(active) do
        if d <= now then due[#due + 1] = o end
    end
    for i = 1, #due do
        local ok, err = pcall(C.settle, due[i], now)
        if not ok then
            T.log("settle failed: " .. tostring(err))
            C.schedule(due[i], now + C.MAX_STEP_H)
        end
    end
end)

-- ---- commands ----
T.ServerCommands = T.ServerCommands or {}

local function linked(player, args, perm)
    local v = T.commandVehicle and T.commandVehicle(player, args, 30)
    if not v then return nil end
    local part = B.part(v)
    local chg = part and part:getModData().chg
    if not chg then T.deny(player, "NOT_PLUGGED", v:getId()); return nil end
    if perm then
        local ok = T.authorized(player, v, perm)
        if not ok then T.deny(player, "NOT_OWNER", v:getId()); return nil end
    end
    local s = sys()
    local o = s and s:getLuaObjectAt(chg.x, chg.y, chg.z)
    if not o then clearChg(v, part); T.deny(player, "NO_CHARGER", v:getId()); return nil end
    return v, part, chg, o
end

-- settle now and sync (the client card estimates from kw and last in between)
T.ServerCommands.chargeInfo = function(player, args)
    local v, _, _, o = linked(player, args, nil)
    if v then C.settle(o, T.hours()) end
end

T.ServerCommands.chargeTarget = function(player, args)
    local v, _, chg, o = linked(player, args, "FUEL")
    if not v then return end
    local pct = tonumber(args.pct)
    if not pct then return end
    C.settle(o, T.hours())
    chg.target = math.max(50, math.min(100, math.floor(pct + 0.5)))
    if chg.paused == "stopped" or chg.paused == "full" then chg.paused = nil end
    C.settle(o, T.hours())
end

T.ServerCommands.chargeStop = function(player, args)
    local v, part, chg, o = linked(player, args, "FUEL")
    if not v then return end
    C.settle(o, T.hours())
    chg.paused = "stopped"
    C.settle(o, T.hours())
end
