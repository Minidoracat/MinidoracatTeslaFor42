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
local draws = {} -- draws[luaObject] = { id = supplier vehicle id, kw }: cars a Cybertruck charges (supplyKw)
function C.unschedule(o)
    draws[o] = nil
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
-- wired power. skip: the plugged car's own Powershare record (Chargers.lua T.generatorAt).
-- ponytail: square scan (41x41x7 at defaults) only when the cache misses; keep a generator index if it shows up in profiles
function C.findGenerator(o, sq, skip)
    local wired = T.wiredPower(o.kind, sq)
    if o.gx then
        local r = T.Chargers[o.kind].genTiles
        local direct = r and o.gz == o.z and math.abs(o.gx - o.x) <= r and math.abs(o.gy - o.y) <= r
        local g = (wired or direct) and T.generatorAt(o.gx, o.gy, o.gz, skip)
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
                    local g = dx * dx + dy * dy <= r * r and T.generatorAt(x, y, z, skip)
                    if g then o.gx, o.gy, o.gz = x, y, z; return g end
                end
            end
        end
    end
    local g, x, y = T.directGenerator(o.kind, o.x, o.y, o.z, skip)
    if g then o.gx, o.gy, o.gz = x, y, o.z end
    return g
end

-- What powers charger o for car v once the grid is off, or nil: "generator", g; "powershare", the Cybertruck whose
-- hidden generator powers the house (Powershare.lua; user 2026-10-30 "幫別台特斯拉充電"); "outlet", the Cybertruck
-- whose bed outlet it sits by (Chargers.lua T.bedOutlet). v's own Powershare never counts (plan 4.1: it never charges
-- itself), nor one whose car is not loaded or is at its discharge limit (nobody pays).
function C.source(o, sq, v)
    local part = B.part(v)
    local ps = part and part:getModData().ps
    local g = C.findGenerator(o, sq, ps and ps.gx and ps or nil)
    local PS = T.Powershare
    if g then
        if not T.isPowershare(g) then return "generator", g end
        local sup = PS and PS.carOf(g)
        if sup and PS.avail(sup) > 0 then return "powershare", sup end
    end
    local sup = T.bedOutlet(o.kind, o.x, o.y, o.z, v)
    if sup then return "outlet", sup end
    return nil
end
local function fromCar(src) return src == "powershare" or src == "outlet" end

-- kW a Cybertruck gives charger o, shared by all it charges: Powershare at most T.PS_KW, the bed outlet T.OUTLET_KW,
-- both times the charging speed sandbox like every charger's kw.
-- ponytail: first come first served between settles; the share evens out as each settles again (hourly at most)
local function supplyKw(o, sup, src, kw)
    local cap = (src == "powershare" and T.PS_KW or T.OUTLET_KW) * T.chargeMul()
    local id, used = sup:getId(), 0
    for o2, d in pairs(draws) do
        if o2 ~= o and d.id == id then used = used + d.kw end
    end
    local k = math.max(0, math.min(kw, cap - used))
    draws[o] = { id = id, kw = k }
    return k
end
-- kW Cybertruck sup is giving the cars it charges now (the app's Powershare page)
function C.drawnKw(sup)
    local id, kw = sup:getId(), 0
    for _, d in pairs(draws) do
        if d.id == id then kw = kw + d.kw end
    end
    return kw
end
-- Take up to kwh from Cybertruck sup's pack, down to its discharge limit, for a car it charges (or runs, chg.fed): what
-- one car gets the other loses, kWh for kWh. Powershare's generator fuel follows the pack (Powershare.touch). Returns
-- the kWh taken.
function C.takeFrom(sup, src, kwh)
    local PS = T.Powershare
    local part = B.part(sup)
    local k = math.min(kwh, PS.avail(sup, part))
    if k <= 0 then return 0 end
    B.set(sup, part, B.kwh(part) - k)
    if src == "powershare" then PS.touch(sup) end
    return k
end

-- Settle the chargers Cybertruck sup is charging (before its supply changes: they book up to now with it), then those
-- within r tiles (Chebyshev) of x, y and vr floors of z (after it changed: they take it from now on). Event-time only.
function C.settleSupplied(sup)
    local id, list = sup:getId(), {}
    for o, d in pairs(draws) do
        if d.id == id then list[#list + 1] = o end
    end
    local now = T.hours()
    for i = 1, #list do
        local ok, err = pcall(C.settle, list[i], now)
        if not ok then T.log("settle for a supply change failed: " .. tostring(err)) end
    end
end
function C.settleAround(x, y, z, r, vr, except)
    local list = {}
    for o in pairs(active) do
        if math.abs(o.x - x) <= r and math.abs(o.y - y) <= r and math.abs(o.z - z) <= vr then list[#list + 1] = o end
    end
    local now = T.hours()
    for i = 1, #list do
        if T.chargerCar(list[i], list[i].x, list[i].y, list[i].z) ~= except then
            local ok, err = pcall(C.settle, list[i], now)
            if not ok then T.log("settle for a supply change failed: " .. tostring(err)) end
        end
    end
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
-- ponytail: a generator counts as running the whole stretch (its fuel is billed at each settle, C.settle)
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
    -- unplugged: a Cybertruck's Powershare stops (plan 4: "拔線"), its bed outlet may supply again
    local PS = T.Powershare
    if PS then
        ok, err = pcall(PS.unplugged, vehicle, part)
        if not ok then T.log("powershare after unplug failed: " .. tostring(err)) end
    end
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
    local gUntil = gridUntil(o.kind, sq)
    local fuel = T.fuelPerKwh()
    local rate = kw * fuel -- litres per hour of charging (per kWh: a full charge costs the same at any charging speed)
    -- after the grid: a generator, or a Cybertruck (its Powershare, its bed outlet) giving kwS of its supply
    local function pick()
        local s, g, k = nil, nil, kw
        if now >= gUntil then s, g = C.source(o, sq, v) end
        if fromCar(s) then
            k = supplyKw(o, g, s, kw)
            if k <= 0 then s, g, k = nil, nil, kw end -- the others take all it gives
        end
        if not fromCar(s) then draws[o] = nil end
        return s, g, k
    end
    local src, gen, kwS = pick()
    local needK = math.max(0, limit - B.kwh(part))
    local gotK = 0
    if chg.paused ~= "stopped" and needK > 0 and now > t0 then
        local gridH = math.min(math.max(0, math.min(now, gUntil) - t0), needK / kw)
        gotK = kw * gridH
        local rest = now - t0 - gridH -- > 0 with need left only past the shut-off, where src was looked up
        if rest > 0 and gotK < needK then
            if src == "generator" then
                local h = math.min(rest, (needK - gotK) / kw)
                if rate > 0 then
                    h = math.min(h, gen:getFuel() / rate)
                    gen:setFuel(gen:getFuel() - rate * h) -- syncs from the server (IsoGenerator.java:509-518)
                end
                gotK = gotK + kw * h
            elseif src then
                gotK = gotK + C.takeFrom(gen, src, math.min(rest * kwS, needK - gotK))
            end
        end
    end
    if gotK > 0 then chg.added = (chg.added or 0) + B.add(v, gotK, chg.target) end
    -- that ran it dry (a generator's fuel, a Cybertruck's limit): whatever else powers it from now on
    if (src == "generator" and gen:getFuel() <= 0) or (fromCar(src) and T.Powershare.avail(gen) <= 0) then
        src, gen, kwS = pick()
    end
    -- state from now on. power: the charger has a source, whether or not it charges (full / stopped); the car's own
    -- loads run on it meanwhile (Battery.onCharger), and off the grid they cost the source (chg.fed, below).
    -- ponytail: they do not slow charging.
    local power = now < gUntil and "grid" or src
    chg.kw, chg.last = power == "grid" and kw or kwS, now
    settleSentry(v, now, C.powerUntil(chg, now, src ~= nil)) -- with the power it ran on until now
    -- the car's own loads off the grid since the last settle (Battery.lua B.draw, Sentry.lua settle add them up): the
    -- generator's fuel, or the Cybertruck's pack. ponytail: a source gone by now (dry, switched off, taken away) is
    -- not billed for them.
    if chg.fed then
        if src == "generator" then
            if fuel > 0 then gen:setFuel(gen:getFuel() - chg.fed * fuel) end
        elseif src then
            C.takeFrom(gen, src, chg.fed)
        end
        chg.fed = nil
    end
    chg.power = power
    local left = math.max(0, limit - B.kwh(part))
    local charging = power
    if chg.paused == "stopped" then
        charging = nil
    elseif left <= 1e-6 then
        chg.paused, charging = "full", nil
    elseif not power then
        chg.paused = "nopower"
    else
        chg.paused = nil
    end
    chg.src = charging
    md.chg = chg
    v:transmitPartModData(part)
    local step = C.MAX_STEP_H
    if charging then step = math.min(step, left / chg.kw) end
    -- grid power ends at the shut-off hour, charging or not (full / stopped still power the car's loads)
    if power == "grid" then step = math.min(step, gUntil - now) end
    if power == "generator" and rate > 0 then step = math.min(step, gen:getFuel() / rate) end
    if fromCar(power) then step = math.min(step, T.Powershare.avail(gen) / kwS) end -- its discharge limit
    C.schedule(o, now + math.max(step, 1 / 60))
    -- a Cybertruck on its own Wall Connector: Powershare decides here, on every settle (plan 4: plugging in, the
    -- shut-off hour, at least hourly while plugged in), whether the house has power without it
    if md.ps and T.Powershare then T.Powershare.update(v, part, o, power ~= nil) end
end

function C.start(o, v)
    local now = T.hours()
    local part = B.part(v)
    -- AC charging turns a Cybertruck's bed outlet off (owner's manual p.200): what it fed books up to now, then stops
    local outlet = part:getModData().outlet
    if outlet then C.settleSupplied(v) end
    part:getModData().chg = { x = o.x, y = o.y, z = o.z, kind = o.kind, kw = T.Chargers[o.kind].kw * T.chargeMul(),
        last = now, added = 0, src = nil, target = C.DEFAULT_TARGET, paused = nil }
    o.vid = v:getId()
    o:updateOnClient()
    C.settle(o, now)
    if outlet then C.settleSupplied(v) end
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
-- Settle v's charger now (Powershare.lua: a switch or the discharge limit changed). False when v is not plugged in.
function C.settleCar(v)
    local part, _, o = chargerOf(v)
    if not part then return false end
    C.settle(o, T.hours())
    return true
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
