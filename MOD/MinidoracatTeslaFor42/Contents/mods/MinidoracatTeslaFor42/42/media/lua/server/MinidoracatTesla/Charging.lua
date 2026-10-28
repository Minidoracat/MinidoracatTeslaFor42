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

-- world hour the grid powers this charger until (-HUGE = never had it): T.gridReaches (Chargers.lua: the fridge rule,
-- and a Mobile Connector only indoors)
local function gridUntil(kind, sq)
    return T.gridReaches(kind, sq) and C.gridOffHour() or -HUGE
end

-- The generator the charger runs on, cached square first. On the wiring with generator power (T.wiredPower) one scan
-- of the generator range, the circle vanilla powers (IsoGenerator.isPoweringSquare, IsoGenerator.java:713-719), so the
-- fuel comes from a generator that can be powering it; otherwise only one a Mobile Connector is plugged straight into
-- (T.directGenerator, decisions.md 2026-10-28). A cached generator outside genTiles only counts while the square is on
-- wired power.
-- ponytail: square scan (41x41x7 at defaults) only when the cache misses; keep a generator index if it shows up in profiles
function C.findGenerator(o, sq)
    local wired = T.wiredPower(o.kind, sq)
    if o.gx then
        local r = T.Chargers[o.kind].genTiles
        local direct = r and o.gz == o.z and math.abs(o.gx - o.x) <= r and math.abs(o.gy - o.y) <= r
        local g = (wired or direct) and T.generatorAt(o.gx, o.gy, o.gz)
        if g then return g end
        o.gx, o.gy, o.gz = nil, nil, nil
    end
    if wired then
        local r = SandboxVars.GeneratorTileRange or 20
        local vr = SandboxVars.GeneratorVerticalPowerRange or 3
        for z = o.z - vr, o.z + vr do
            for x = o.x - r, o.x + r do
                for y = o.y - r, o.y + r do
                    local dx, dy = x - o.x, y - o.y
                    local g = dx * dx + dy * dy <= r * r and T.generatorAt(x, y, z)
                    if g then o.gx, o.gy, o.gz = x, y, z; return g end
                end
            end
        end
    end
    local g, x, y = T.directGenerator(o.kind, o.x, o.y, o.z)
    if g then o.gx, o.gy, o.gz = x, y, o.z end
    return g
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

-- Sentry standby is booked on events (Sentry.settle) with the power state it ran under (Battery.onCharger), so settle
-- it before that state changes: every charging settle, and before the link goes.
local function settleSentry(vehicle, now, freeUntil)
    local f = T.Sentry and T.Sentry.settle
    if f then f(vehicle, now, freeUntil) end
end

-- World hour the charger power recorded in chg (chg.power, Battery.onCharger) lasted until, as of `now`; nil = none.
-- Grid: the shut-off hour, which an unloaded car can pass between two settles, unless a generator took over then
-- (`generator`: C.settle found one; nil = not looked up, e.g. a sentry event between two settles: after the shut-off
-- the charger has power only from a generator, through the wiring or plugged straight in, Chargers.lua). Generator:
-- up to now.
-- ponytail: a generator counts as running the whole stretch (its fuel is only metered for charging)
function C.powerUntil(chg, now, generator)
    if not chg or not chg.power then return nil end
    local off = chg.power == "grid" and C.gridOffHour()
    if not off or now <= off then return now end
    if generator == nil then
        local sq = getCell():getGridSquare(chg.x, chg.y, chg.z)
        generator = sq ~= nil and (T.wiredPower(chg.kind, sq) or T.directGenerator(chg.kind, chg.x, chg.y, chg.z) ~= nil)
    end
    return generator and now or off
end

-- The link goes: the stretch since the last settle is booked without a generator taking over after the grid shut-off
-- (C.powerUntil with generator = false): on load with the charger gone or taken (relink) a powered square no longer
-- says this car had a charger. ponytail: a car pulled out of reach after the shut-off pays that bit itself.
local function clearChg(vehicle, part)
    local now = T.hours()
    -- the record goes whatever the sentry booking does: a stale record holds the car in Park (CheckOperate.Battery)
    local ok, err = pcall(function() settleSentry(vehicle, now, C.powerUntil(part:getModData().chg, now, false)) end)
    if not ok then T.log("sentry settle before unplug failed: " .. tostring(err)) end
    part:getModData().chg = nil
    vehicle:transmitPartModData(part)
    touchVM(vehicle)
end

-- Book energy from chg.last to now, pick the source for what comes next, schedule the next settle.
-- here = true skips the cable check (unplugging: the car is still at the charger).
function C.settle(o, now, here)
    local v = T.chargerCar(o, o.x, o.y, o.z)
    if not v then
        -- no car on this cable. vid names no loaded car: unloaded, relink resumes it when it loads. vid names a loaded
        -- car whose record is not this charger (its id handed on, VehicleIDMap.java:49-62,91-95, or its cable gone):
        -- forget the id and never touch that car; ours, still holding its record, relinks to a free charger later.
        if o.vid and getVehicleById(o.vid) then return C.unlink(o) end
        return C.unschedule(o)
    end
    local part = B.part(v)
    local md = part:getModData()
    local chg = md.chg
    if not part:getInventoryItem() then return C.stop(o, v, "pack") end -- the pack gone some other way than below
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
    local gUntil = gridUntil(o.kind, sq)
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
    -- state from now on. power: the charger has a source, whether or not it charges (full / stopped); the car's own
    -- loads run on it meanwhile (Battery.onCharger).
    -- ponytail: those loads burn no generator fuel and do not slow charging; meter them if a generator lasting longer
    -- than its charging hours shows up in play.
    local src, gen = nil, nil
    if now < gUntil then
        src = "grid"
    else
        gen = C.findGenerator(o, sq)
        if gen then src = "generator" end
    end
    settleSentry(v, now, C.powerUntil(chg, now, gen ~= nil)) -- with the power it ran on until now
    chg.power = src
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
    -- grid power ends at the shut-off hour, charging or not (full / stopped still power the car's loads)
    if chg.power == "grid" then step = math.min(step, gUntil - now) end
    if gen and rate > 0 then step = math.min(step, gen:getFuel() / rate) end
    C.schedule(o, now + math.max(step, 1 / 60))
end

function C.start(o, v)
    local now = T.hours()
    local part = B.part(v)
    part:getModData().chg = { x = o.x, y = o.y, z = o.z, kind = o.kind, kw = T.Chargers[o.kind].kw * T.chargeMul(),
        last = now, added = 0, src = nil, target = C.DEFAULT_TARGET, paused = nil }
    o.vid = v:getId()
    o:updateOnClient()
    C.settle(o, now)
    touchVM(v)
    T.log("plugged " .. tostring(v:getId()) .. " into " .. o.kind .. " at " .. o.x .. "," .. o.y .. "," .. o.z)
end

-- reason: "unplug" | "tooFar" | "removed" | "pack"
function C.stop(o, v, reason)
    local part = v and B.part(v)
    if part and part:getModData().chg then
        -- tooFar: the car left the cable; pack: no pack to book into (settle would come back here)
        if reason ~= "tooFar" and reason ~= "pack" and o and o:getIsoObject() then
            local ok, err = pcall(C.settle, o, T.hours(), true) -- book the energy up to now
            if not ok then T.log("settle before unplug failed: " .. tostring(err)) end
        end
        if part:getModData().chg then -- that settle may have unplugged it already (no pack)
            local ok, err = pcall(clearChg, v, part) -- the charger is told below whatever this does
            if not ok then T.log("clearing the cable record failed: " .. tostring(err)) end
        end
    end
    if o then C.unlink(o) end
    T.log("unplugged " .. tostring(v and v:getId()) .. " (" .. tostring(reason) .. ")")
end

-- only the car on this charger's cable: an id handed to another car (maybe plugged in elsewhere) is not unplugged
function C.onChargerRemoved(o)
    local v = T.chargerCar(o, o.x, o.y, o.z)
    if v then C.stop(o, v, "removed") else C.unschedule(o) end
end

-- Taking the pack out while plugged in (vanilla ISUninstallVehiclePart:complete, server / SP): book the energy into
-- the part first (the pack item takes the part's content, ISUninstallVehiclePart.lua:63-64), then unplug once it is
-- out. Left alone, the next settle only made the charger forget the car: the car kept its cable record (held in Park
-- while the pedal was down, Core.lua CheckOperate.Battery) and the charger showed no Unplug row for it.
-- A hook error must never break the vanilla action (Sentry.lua hook): both halves under pcall.
local function packLink(v, part) -- a plugged-in Tesla's pack: its cable record, and its charger if still its own
    local chg = v and part and part == B.part(v) and part:getModData().chg
    if not chg then return nil end
    local s = sys()
    local o = s and s:getLuaObjectAt(chg.x, chg.y, chg.z)
    return chg, o and T.chargerCar(o, o.x, o.y, o.z) == v and o or nil -- another car's charger now: leave it be
end
local uninstall = ISUninstallVehiclePart and ISUninstallVehiclePart.complete
if uninstall then
    function ISUninstallVehiclePart:complete()
        local v, part = self.vehicle, self.part
        local ok, chg, o = pcall(packLink, v, part)
        if not ok then T.log("pack uninstall hook failed: " .. tostring(chg)); chg, o = nil, nil end
        if o and o:getIsoObject() then
            local fine, err = pcall(C.settle, o, T.hours(), true)
            if not fine then T.log("settle before the pack came out failed: " .. tostring(err)) end
        end
        local r = uninstall(self)
        if chg and not part:getInventoryItem() then
            local fine, err = pcall(C.stop, o, v, "pack")
            if not fine then T.log("unplug after the pack came out failed: " .. tostring(err)) end
        end
        return r
    end
end

-- ---- player actions (timed action complete(), server / SP) ----

-- the cable rule (Chargers.lua T.mayUseCable; T.mayUnplug for unplug and stop, which the charger's owner may too) for
-- plug, unplug and the charge card; refused: log, deny with the reason it gives, false
local function mayCable(player, v, what, rule)
    local ok, deny, why = (rule or T.mayUseCable)(player, v)
    if ok then return true end
    T.log(what .. " refused for " .. tostring(player:getUsername()) .. ": " .. tostring(why or deny))
    T.deny(player, deny, v:getId())
    return false
end

-- plug / unplug are not remotes: near the car, or near the charger on its floor (queuePlug / queueUnplug walk to the
-- charger, ChargerMenu.lua; DistTo is the Manhattan distance, IsoMovingObject.java:601-607, and DistTo(x, y) has no
-- floor, so a car parked aslant at the cable's end can be > T.NEAR from someone at the charger)
local function near(player, v, x, y, z)
    if player:DistTo(v) <= T.NEAR then return true end
    return math.floor(player:getZ()) == z and player:DistTo(x, y) <= T.NEAR
end

function C.plug(player, v, iso)
    local s = sys()
    local o = s and iso and iso:getSquare() and s:getLuaObjectOnSquare(iso:getSquare())
    local vid = v and v:getId()
    if not o then return T.deny(player, "NO_CHARGER", vid) end
    local part = B.part(v)
    if not part then return T.deny(player, "NO_VEHICLE", vid) end
    if not part:getInventoryItem() then return T.deny(player, "NO_PACK", vid) end
    if part:getModData().chg then return T.deny(player, "PLUGGED", vid) end
    if T.chargerCar(o, o.x, o.y, o.z) then return T.deny(player, "CHARGER_BUSY", vid) end -- a reused id is no car here
    if not T.stopped(v) then return T.deny(player, "MOVING", vid) end -- the motor may run: plugging in shifts to Park (owner's manual, Shifting)
    if not near(player, v, o.x, o.y, o.z) then return T.deny(player, "TOO_FAR", vid) end
    if not T.cableReaches(o.kind, o.x, o.y, o.z, v) then return T.deny(player, "CABLE_SHORT", vid) end
    if not mayCable(player, v, "plug") then return end
    C.start(o, v)
end

function C.unplug(player, v)
    local part = B.part(v)
    local chg = part and part:getModData().chg
    local vid = v and v:getId()
    if not chg then return T.deny(player, "NOT_PLUGGED", vid) end
    if not near(player, v, chg.x, chg.y, chg.z) then return T.deny(player, "TOO_FAR", vid) end
    if not mayCable(player, v, "unplug", T.mayUnplug) then return end
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
    local other = o and o.vid and o.vid ~= v:getId() and T.chargerCar(o, o.x, o.y, o.z) -- not a car that took the id
    if not o or other then
        clearChg(v, part)
        T.log("relink: charger gone or taken, cable cleared on " .. tostring(v:getId()))
        return
    end
    o.vid = v:getId()
    o:updateOnClient()
    C.settle(o, T.hours())
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

-- the battery part, its link and the charger it is plugged into; nil and a deny reason when there is none
local function chargerOf(v)
    local part = B.part(v)
    local chg = part and part:getModData().chg
    if not chg then return nil, "NOT_PLUGGED" end
    local s = sys()
    local o = s and s:getLuaObjectAt(chg.x, chg.y, chg.z)
    if not o then clearChg(v, part); return nil, "NO_CHARGER" end
    return part, chg, o
end

-- rule: the charge card's buttons take the cable rule (T.mayUseCable; stop T.mayUnplug), like plug / unplug and the
-- card's own pre-check (HUDChargeCard.lua); nil = no rule (chargeInfo)
local function linked(player, args, rule)
    local v = T.commandVehicle and T.commandVehicle(player, args, 30)
    if not v then return nil end
    local part, chg, o = chargerOf(v)
    if not part then T.deny(player, chg, v:getId()); return nil end
    if rule and not mayCable(player, v, "charge card", rule) then return nil end
    return v, part, chg, o
end

-- Stop or resume (stopped -> charging) from the phone app (Remote.lua, which checked reach and rights). Same as the
-- card's chargeStop / chargeTarget without the distance. Returns true, or false and a deny reason.
function C.setStopped(v, stop)
    local part, chg, o = chargerOf(v)
    if not part then return false, chg end
    C.settle(o, T.hours())
    if stop then chg.paused = "stopped" elseif chg.paused == "stopped" then chg.paused = nil end
    C.settle(o, T.hours())
    return true
end

-- settle now and sync (the client card estimates from kw and last in between)
T.ServerCommands.chargeInfo = function(player, args)
    local v, _, _, o = linked(player, args, nil)
    if v then C.settle(o, T.hours()) end
end

T.ServerCommands.chargeTarget = function(player, args)
    local v, _, chg, o = linked(player, args, T.mayUseCable)
    if not v then return end
    local pct = tonumber(args.pct)
    if not pct then return end
    C.settle(o, T.hours())
    chg.target = math.max(50, math.min(100, math.floor(pct + 0.5)))
    if chg.paused == "stopped" or chg.paused == "full" then chg.paused = nil end
    C.settle(o, T.hours())
end

T.ServerCommands.chargeStop = function(player, args)
    local v, part, chg, o = linked(player, args, T.mayUnplug)
    if not v then return end
    C.settle(o, T.hours())
    chg.paused = "stopped"
    C.settle(o, T.hours())
end

-- ---- loot: the Mobile Connector sits in every procedural list that has vanilla's car battery charger, at half its
-- weight (decisions.md 2026-10-28; ProceduralDistributions.lua: CarSupplyBatteries 10, GasStoreEmergency 6, ...).
-- Our pairs go first so a reload does not stack them (KeyActions.lua phone loot).
C.LOOT_ITEM = "Base.MinidoracatTesla_MobileConnector"
C.LOOT_SHARE = 0.5
local function addLoot(items)
    for i = #items - 1, 1, -2 do
        if items[i] == C.LOOT_ITEM then table.remove(items, i + 1); table.remove(items, i) end
    end
    local w = 0
    for i = 1, #items - 1, 2 do
        if items[i] == "CarBatteryCharger" or items[i] == "Base.CarBatteryCharger" then w = w + (tonumber(items[i + 1]) or 0) end
    end
    if w > 0 then
        table.insert(items, C.LOOT_ITEM)
        table.insert(items, w * C.LOOT_SHARE)
    end
end
function C.injectLoot()
    local lists = ProceduralDistributions and ProceduralDistributions.list
    if not lists then return end
    for _, l in pairs(lists) do
        if type(l) == "table" then
            if type(l.items) == "table" then addLoot(l.items) end
            if type(l.junk) == "table" and type(l.junk.items) == "table" then addLoot(l.junk.items) end
        end
    end
end
Events.OnPostDistributionMerge.Add(C.injectLoot)
