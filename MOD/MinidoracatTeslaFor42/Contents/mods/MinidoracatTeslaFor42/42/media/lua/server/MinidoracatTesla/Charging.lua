-- Charging: plug / unplug, time-difference settlement, grid first then generator fuel, cable length, relink after
-- restart, and the charge commands. No OnTick: EveryOneMinute is one comparison unless a settle is due (a game minute,
-- not ten: a Supercharger books about 4 kWh a minute, so a due settle (target, shut-off, dry generator) is late by at
-- most one minute; main agent 2026-11-09).
-- Link state lives in the battery part modData `chg` (architecture.md section 4); the charger Lua object only holds vid.
if isClient() then return end
require "MinidoracatTesla/Chargers"
require "MinidoracatTesla/Battery"
require "MinidoracatTesla/ChargerSystem"
require "TimedActions/ISActivateGenerator" -- wrapped below (aroundGenerator), as Powershare.lua requires its own

local T = MinidoracatTesla
local B = T.Battery
local C = T.Charge or {} -- client/ChargerMenu.lua adds the queue helpers to the same table in SP
T.Charge = C

C.DEFAULT_TARGET = 90
C.MAX_STEP_H = 1      -- re-settle at least hourly: generator switched off, car towed away, power back
C.RETRY_H = 1 / 6     -- charger square not loaded yet, or the Cybertruck it ran on (C.settle chg.hold): try again then
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
local draws = {} -- draws[luaObject] = { key = supplier keyId, kw = charging share }: cars a Cybertruck feeds (supplyKw)
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
-- a Mobile Connector only indoors, a Supercharger the gas pump rule: any square not isNoPower, ItemContainer.java:2347-2349)
local function gridUntil(kind, sq)
    return T.gridReaches(kind, sq) and C.gridOffHour() or -HUGE
end

-- The generator the charger runs on, cached square first. On the wiring with generator power (T.wiredPower) one scan
-- of the generator range, the circle vanilla powers (IsoGenerator.isPoweringSquare, IsoGenerator.java:713-719), so the
-- fuel comes from a generator that can be powering it; otherwise only one plugged straight in: a running generator
-- within genTiles of a Mobile Connector or a Supercharger (T.directGenerator, decisions.md 2026-10-28; sc-contract).
-- A cached generator outside genTiles only counts while the square is on wired power. skip: the plugged car's own
-- Powershare record (Chargers.lua T.generatorAt).
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

-- A Cybertruck by its keyId (the same across loads; vehicle ids are handed out again every load, BaseVehicle.java:
-- 793-801), loaded right now, or nil. supIds is kept as trucks supply (supplyKw) and load (Powershare.lua).
C.supIds = C.supIds or {}
function C.carByKey(key)
    local v = key and getVehicleById(C.supIds[key] or -1)
    if v and v:getKeyId() == key then return v end
    return nil
end

-- kW Cybertruck sup's supply `src` has left for charger o: Powershare at most T.PS_KW, the bed outlet T.OUTLET_KW (both
-- times the charging speed sandbox like every charger's kw), less what the others it charges hold (draws).
local function shareLeft(o, key, src)
    local used = 0
    for o2, d in pairs(draws) do
        if o2 ~= o and d.key == key then used = used + d.kw end
    end
    return math.max(0, (src == "powershare" and T.PS_KW or T.OUTLET_KW) * T.chargeMul() - used)
end
-- The charging kW charger o gets from sup from now on (0: the others hold it all; the car still runs on sup). A car
-- full or stopped holds 0 (C.settle). ponytail: first come first served; a share another car gave back reaches this
-- one from its next settle on (hourly at most), never for the stretch already run (C.settle wasKw).
local function supplyKw(o, sup, src, kw)
    local key = sup:getKeyId()
    C.supIds[key] = sup:getId()
    local k = math.min(kw, shareLeft(o, key, src))
    draws[o] = { key = key, kw = k }
    return k
end
-- kW Cybertruck sup is charging other cars with now (the app's Powershare page)
function C.drawnKw(sup)
    local key, kw = sup:getKeyId(), 0
    for _, d in pairs(draws) do
        if d.key == key then kw = kw + d.kw end
    end
    return kw
end
-- Take up to kwh from Cybertruck sup's pack, down to its discharge limit, for a car it charges (or runs, chg.fed): what
-- one car gets the other loses, kWh for kWh. Powershare: the house's use up to now is booked first (Powershare.touch),
-- then the generator's fuel follows the pack. Returns the kWh taken.
function C.takeFrom(sup, src, kwh)
    local PS = T.Powershare
    local part = B.part(sup)
    if src == "powershare" then PS.touch(sup) end
    local k = math.min(kwh, PS.avail(sup, part))
    if k <= 0 then return 0 end
    B.set(sup, part, B.kwh(part) - k)
    if src == "powershare" then PS.touch(sup) end
    return k
end

-- Settle the chargers Cybertruck sup feeds (before its supply changes: they book up to now with it), then those
-- within r tiles (Chebyshev) of x, y and vr floors of z (after it changed: they take it from now on; before it, the
-- ones waiting for it after a restart, when draws is empty). Event-time only.
function C.settleSupplied(sup)
    local key, list = sup:getKeyId(), {}
    for o, d in pairs(draws) do
        if d.key == key then list[#list + 1] = o end
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

-- The charger's tile shows whether a cable is in it (decisions.md 2026-11-09: the gun in its holster when idle, out of
-- it when plugged; Chargers.lua `sprites` / `busy`; the Mobile Connector has one tile). Swapped only when it changes:
-- setSpriteFromName (IsoThumpable also takes it as closedSprite, the one it saves, IsoThumpable.java:372-375,616-618),
-- then on a server UpdateItemSprite to the clients (IsoObject.java:4618-4659, as SRainBarrelGlobalObject.lua:100-101;
-- the client sets the sprite and RecalcAllWithNeighbours, GameClient.java:1122-1166). Neither touches the three
-- blocking fields Chargers.lua turns off at placing, and both tiles carry the same flags, so nothing to recalc here.
-- iso: the charger's IsoObject when the caller has it (a chunk loading: its squares may not be in the cell's grid yet,
-- IsoChunk.java:3799-3829, so o:getIsoObject() may not find it)
-- o.removing (C.onChargerRemoved): the charger is leaving its square, keep its tile whatever path asks (the unplug's
-- own settle can stop it again with "pack"). Its UpdateItemSprite is reliable but unordered (PacketTypes.java:517,
-- 628-647) and the client applies it by square index (GameClient.java:1133-1141): arriving after RemoveItemFromSquare
-- (sent first on a sledgehammer, GameServer.java:2990-2998) it would paint whatever object took that index. A
-- picked-up item keeps the plugged tile; it goes down idle (Chargers.lua removeComponentsBeforePlacing).
function C.setBusy(o, busy, iso)
    if o and o.removing then return end
    iso = iso or (o and o:getIsoObject())
    local info = iso and T.chargerInfo(iso)
    local set = info and T.Chargers[info.kind][busy and "busy" or "sprites"]
    local name = set and set[info.facing]
    if not name or iso:getSprite():getName() == name then return end
    iso:setSpriteFromName(name)
    if isServer() then iso:transmitUpdatedSpriteToClients() end
end

function C.unlink(o)
    C.unschedule(o)
    if o.vid then
        -- false, not nil: the update packet only carries keys that have a value, so nil would leave the client's old vid
        -- (CGlobalObjectSystem.java:62-70 rawsets only what arrives)
        o.vid = false
        o:updateOnClient()
    end
    C.setBusy(o, false)
end

-- A charger's tile loads (ChargerSystem.lua; a placed one, IsoThumpable or the Wall Connector's IsoObject, goes down
-- idle already: Chargers.lua removeComponentsBeforePlacing).
-- Its car already relinked (the car's chunk loaded first, or a save from before the plugged tiles, whose Wall
-- Connector shows the idle one): plugged tile. Loaded plugged with no car yet: the car's own load relinks it
-- (C.relink); still none C.RETRY_H later, that settle (o.loadCheck, cleared by any settle that finds the car) shows the
-- idle tile: the car was deleted or blew up with its cable in. Restart or a chunk loading again in the same session
-- alike (vid may still name the gone car).
function C.onChargerLoaded(o, iso)
    if T.chargerCar(o, o.x, o.y, o.z) then return C.setBusy(o, true, iso) end
    local info = T.chargerInfo(iso)
    if not (info and info.busy) then return end
    o.loadCheck = true
    C.schedule(o, T.hours() + C.RETRY_H)
end

-- Sentry standby is booked on events (Sentry.settle) with the power state it ran under (Battery.onCharger), so settle
-- it before that state changes: every charging settle, and before the link goes.
local function settleSentry(vehicle, now, freeUntil)
    local f = T.Sentry and T.Sentry.settle
    if f then f(vehicle, now, freeUntil) end
end

-- The Cybertruck that fed chg (chg.sup) and how its supply stands since the last settle (chg.last): away = not all
-- there (not loaded, or its Powershare generator's square not loaded: the car waits for it, C.settle chg.hold);
-- ended = its supply to some charger may have ended at an hour nobody saw (brokeAt after chg.last: it moved, C.noteMove,
-- or its outlet / tailgate / Powershare / an AC cable cut it, Powershare.lua PS.broke), or it is not where it stood
-- then (more than 0.5 tile: pushed, towed, teleported with no part update). Returns sup or nil, ended, away.
function C.supplyEnded(chg)
    local sup = chg.sup and C.carByKey(chg.sup)
    if not sup then return nil, true, true end
    if chg.power == "powershare" and T.Powershare.genAway(sup) then return sup, true, true end
    local broke = B.part(sup) and B.part(sup):getModData().brokeAt
    if broke and broke > (chg.last or 0) then return sup, true, false end
    if chg.supX and (math.abs(sup:getX() - chg.supX) > 0.5 or math.abs(sup:getY() - chg.supY) > 0.5) then return sup, true, false end
    return sup, false, false
end

-- A supplier truck's parts update (Battery.lua; parts update while someone sits in the driver's seat, the motor runs,
-- camping, an alarm or the mechanics window is open, BaseVehicle.java:3507-3511): it rolls (over 0.5 km/h; an MP
-- server may read 0, Battery.lua B.summonKm) or stands over 0.5 tile from where the last update saw it ->
-- md.brokeAt. Catches driving off and back to the same spot between two settles. A VirtualVehicle (SP, an id handed
-- back to the pool, VirtualVehicle.java:40-42,139-145) is skipped; an id now on another truck (keyId) starts over.
local lastPos = {} -- vehicle id -> { keyId, x, y } at its last update (this session; cleared when a car loads)
function C.noteMove(v, part)
    if not instanceof(v, "BaseVehicle") then return end
    local id, key, x, y = v:getId(), v:getKeyId(), v:getX(), v:getY()
    local p = lastPos[id]
    if p and p[1] == key then
        if math.abs(v:getCurrentSpeedKmHour()) > 0.5 or math.abs(p[2] - x) > 0.5 or math.abs(p[3] - y) > 0.5 then
            part:getModData().brokeAt = T.hours()
        end
        p[2], p[3] = x, y
    elseif p then
        p[1], p[2], p[3] = key, x, y
    else
        lastPos[id] = { key, x, y }
    end
end

-- World hour Sentry's standby on a Cybertruck's supply was free until (C.powerUntil and C.settle): `away` (not all
-- there yet) -> now: it goes into chg.fed and the settle that sees the truck decides who pays (C.payFed); `ended` ->
-- at most C.MAX_STEP_H past the last settle, then the car's own pack; else now.
function C.carFreeUntil(chg, now, ended, away)
    if away or not ended then return now end
    return math.min(now, math.min(chg.last or now, now) + C.MAX_STEP_H)
end

-- World hour the charger power recorded in chg (chg.power, Battery.onCharger) lasted until, as of `now`; nil = none.
-- Grid: the shut-off hour, which an unloaded car can pass between two settles, unless a generator took over then
-- (`generator`: C.settle found one; nil = not looked up, e.g. a sentry event between two settles: after the shut-off
-- the charger has power only from a generator, through the wiring or plugged straight in, Chargers.lua). Generator:
-- up to now. A Cybertruck (powershare / outlet): C.carFreeUntil. Every Sentry booking (settles, events, unplugging)
-- goes through here.
-- A generator counts as running the whole stretch since the last settle: fuel running out while charging is scheduled
-- (C.settle), and switching one on or off by hand settles the chargers around it before and after (the
-- ISActivateGenerator wrap below). ponytail: one that stops without that action (vanilla: out of fuel while nothing
-- charges, condition 0, fire, explosion, IsoGenerator.java:216,222,249,253; picked up; another mod) is not seen until
-- the next settle (at most C.MAX_STEP_H): the charge since the last settle is not booked (src nil then), and Sentry's
-- standby and the car's own loads for that stretch are free (chg.power was "generator": up to now; chg.fed dropped).
function C.powerUntil(chg, now, generator)
    if not chg or not chg.power then return nil end
    if fromCar(chg.power) then
        local _, ended, away = C.supplyEnded(chg)
        return C.carFreeUntil(chg, now, ended, away)
    end
    local off = chg.power == "grid" and C.gridOffHour()
    if not off or now <= off then return now end
    if generator == nil then
        local sq = getCell():getGridSquare(chg.x, chg.y, chg.z)
        generator = sq ~= nil and (T.wiredPower(chg.kind, sq) or T.directGenerator(chg.kind, chg.x, chg.y, chg.z) ~= nil)
    end
    return generator and now or off
end

-- chg.fed: the car's own loads that ran on its charger's power since the last settle (Battery.draw, Sentry.settle).
-- Cybertruck sup (its supply src) pays `share` of it (1; the capped hour's part of the stretch), down to its limit;
-- whatever nobody pays (the limit, a truck still away, the rest past the cap) comes off the car's own pack: they ran,
-- nothing is made up. Generators: C.settle bills their fuel itself.
function C.payFed(v, part, chg, sup, src, share)
    local fed = chg.fed
    if not fed then return end
    chg.fed = nil
    local paid = sup and C.takeFrom(sup, src, fed * share) or 0
    if fed - paid > 1e-9 then B.set(v, part, math.max(0, B.kwh(part) - (fed - paid))) end
end

-- The link goes: the stretch since the last settle is booked without a generator taking over after the grid shut-off
-- (C.powerUntil with generator = false): on load with the charger gone or taken (relink) a powered square no longer
-- says this car had a charger. ponytail: a car pulled out of reach after the shut-off pays that bit itself. Its
-- chg.fed is settled first (C.payFed): a Cybertruck's share as in C.settle, a generator's left to the car itself.
local function clearChg(vehicle, part)
    local now = T.hours()
    -- the record goes whatever the sentry booking does: a stale record holds the car in Park (CheckOperate.Battery)
    local ok, err = pcall(function()
        local chg = part:getModData().chg
        settleSentry(vehicle, now, C.powerUntil(chg, now, false))
        if chg and chg.fed then
            local sup, ended, away
            if fromCar(chg.power) then sup, ended, away = C.supplyEnded(chg) end
            local h = now - math.min(chg.last or now, now)
            local share = ended and h > C.MAX_STEP_H and C.MAX_STEP_H / h or 1
            C.payFed(vehicle, part, chg, not away and sup or nil, chg.power, share)
        end
    end)
    if not ok then T.log("sentry / own loads before unplug failed: " .. tostring(err)) end
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
-- here = true skips the cable check (unplugging: the car is still at the charger). fresh = true: the car just loaded
-- (relink): a stretch it ran on a Cybertruck not loaded now waits for it once more (below).
function C.settle(o, now, here, fresh)
    local v = T.chargerCar(o, o.x, o.y, o.z)
    if not v then
        -- no car on this cable. vid names no loaded car: unloaded, relink resumes it when it loads. vid names a loaded
        -- car whose record is not this charger (its id handed on, VehicleIDMap.java:49-62,91-95, or its cable gone):
        -- forget the id and never touch that car; ours, still holding its record, relinks to a free charger later.
        -- loadCheck: a plugged tile's check after it loaded (C.onChargerLoaded), no car came: idle tile.
        if o.vid and getVehicleById(o.vid) then C.unlink(o) end
        if o.loadCheck then o.loadCheck = nil; C.setBusy(o, false) end
        return C.unschedule(o)
    end
    o.loadCheck = nil
    local part = B.part(v)
    local md = part:getModData()
    local chg = md.chg
    if not part:getInventoryItem() then return C.stop(o, v, "pack") end -- the pack gone some other way than below
    local iso = o:getIsoObject()
    if not iso then return C.schedule(o, now + C.RETRY_H) end
    if not here and not T.cableReaches(o.kind, o.x, o.y, o.z, v) then return C.stop(o, v, "tooFar") end
    -- the charger's own limit for this car (a Supercharger's: the car's DC peak, its curve on top, Core.lua
    -- B.chargeKwAt); the grid and a generator give it whole, a Cybertruck its share (supplyKw)
    local kw = T.chargerKw(o.kind, v)
    chg.peak = T.dcPeak(o.kind, v, kw)
    local own = { kw = kw, peak = chg.peak }
    local sq = iso:getSquare()
    local t0 = math.min(chg.last or now, now)
    local cap = B.capacity(part)
    local limit = cap * chg.target / 100
    local gUntil = gridUntil(o.kind, sq)
    local fuel = T.fuelPerKwh() -- litres per kWh: a full charge costs the same at any charging speed or curve
    -- The stretch since the last settle ran on what chg.power says. Run on a Cybertruck (chg.sup = its keyId, chg.power
    -- powershare / outlet): that truck pays it, at the share it had (draws; after an unload or a restart chg.kw, never
    -- more than its supply has left now); never retroactively for a stretch with no power, the grid or a generator.
    -- That truck not all there (not loaded, or its Powershare generator's square not loaded): cells load and unload
    -- one after the other (the car first on load, the truck first as the player walks off), so wait until chg.hold (a
    -- world hour, set once, again on a fresh load) leaving chg and draws as they are; past it, a truck still away pays
    -- nothing and the car pays its own loads. A truck there books, even at 0 (its outlet off, at its limit, its share
    -- gone); but if its supply may have ended unseen (C.supplyEnded: moved, cut) or this settle finds it no longer
    -- feeding this charger: at most C.MAX_STEP_H is booked (below).
    local wasCar = fromCar(chg.power)
    local wasSrc, supKey = chg.power, wasCar and chg.sup or nil
    local prevSup, ended, gone
    if wasCar then prevSup, ended, gone = C.supplyEnded(chg) end
    local away = gone and (not prevSup and "the Cybertruck it ran on is not loaded" or "its Powershare generator's square is not loaded")
    if away then prevSup = nil end
    if type(chg.hold) ~= "number" then chg.hold = nil end
    if away and now > t0 then
        if fresh or not chg.hold then chg.hold = now + C.RETRY_H end
        if now < chg.hold then
            T.log("charger " .. o.x .. "," .. o.y .. ": " .. tostring(v:getId()) .. " " .. away .. ", settling again at "
                .. string.format("%.3f", chg.hold))
            return C.schedule(o, chg.hold)
        end
    end
    chg.hold = nil
    local wasKw = 0
    if prevSup then
        wasKw = (draws[o] and draws[o].kw) or math.min(chg.kw or 0, shareLeft(o, supKey, wasSrc))
    end
    -- after the grid: a generator, or a Cybertruck (its Powershare, its bed outlet) giving kwS of its supply for
    -- charging (0: the others hold it all, the car still runs on it)
    local function pick()
        local s, g, k = nil, nil, kw
        if now >= gUntil then s, g = C.source(o, sq, v) end
        if fromCar(s) then k = supplyKw(o, g, s, kw) else draws[o] = nil end
        return s, g, k
    end
    local src, gen, kwS = pick()
    -- ponytail: the truck's supply may have ended unseen (driven, moved: C.supplyEnded) or it no longer feeds this
    -- charger: at most one more hour, the error of an hourly settle anyway, for the charge, and for Sentry's standby
    -- (C.powerUntil, from then on the car's own pack)
    local capped = prevSup ~= nil and (ended or not (fromCar(src) and gen:getKeyId() == supKey))
    local kwh0 = B.kwh(part)
    local needK = math.max(0, limit - kwh0)
    local gotK = 0
    if chg.paused ~= "stopped" and needK > 0 and now > t0 then
        local gridH
        gotK, gridH = B.chargeGain(own, cap, kwh0, math.max(0, math.min(now, gUntil) - t0), limit)
        local rest = now - t0 - gridH -- > 0 with need left only past the shut-off, where src was looked up
        if rest > 0 and gotK < needK then
            if wasCar then
                if capped then rest = math.min(rest, C.MAX_STEP_H) end
                if prevSup and wasKw > 0 then
                    local want = B.chargeGain({ kw = wasKw, peak = chg.peak }, cap, kwh0 + gotK, rest, limit)
                    gotK = gotK + C.takeFrom(prevSup, wasSrc, want)
                end
            elseif src == "generator" then
                -- the fuel as the kWh it buys, then charged on the curve; it burns per kWh
                local f = gen:getFuel()
                local to = fuel > 0 and math.min(limit, kwh0 + gotK + f / fuel) or limit
                local k = B.chargeGain(own, cap, kwh0 + gotK, rest, to)
                if fuel > 0 then
                    local burnt = k * fuel
                    gen:setFuel(burnt >= f - 1e-9 and 0 or f - burnt) -- syncs from the server (IsoGenerator.java:509-518)
                end
                gotK = gotK + k
            end
        end
    end
    if gotK > 0 then chg.added = (chg.added or 0) + B.add(v, gotK, chg.target) end
    -- that ran it dry (a generator's fuel, a Cybertruck's limit): whatever else powers it from now on
    if (src == "generator" and gen:getFuel() <= 0) or (fromCar(src) and T.Powershare.avail(gen) <= 0) then
        src, gen, kwS = pick()
    end
    -- state from now on. power: the charger has a source, whether or not it charges (full / stopped / no share); the
    -- car's own loads run on it meanwhile (Battery.onCharger), and off the grid they cost the source (chg.fed, below).
    -- ponytail: they do not slow charging.
    local power = now < gUntil and "grid" or src
    -- Sentry's standby until now was free while the power lasted (one rule with events, C.carFreeUntil); a truck
    -- still away past the wait gave none (t0)
    local freeUntil
    if wasCar then
        freeUntil = not prevSup and t0 or C.carFreeUntil(chg, now, capped, false) -- chg.last is still t0 here
    else
        freeUntil = C.powerUntil(chg, now, src ~= nil)
    end
    chg.last = now
    settleSentry(v, now, freeUntil)
    -- the car's own loads off the grid since the last settle (Battery.lua B.draw, Sentry.lua settle add them up): the
    -- Cybertruck that ran it (C.payFed: capped, its hour's part; the rest, and what it cannot pay, the car itself),
    -- or the generator's fuel. ponytail: a generator gone by now (dry, switched off, taken away) is not billed.
    if chg.fed then
        if wasCar then
            local h = now - t0
            C.payFed(v, part, chg, prevSup, wasSrc, capped and h > C.MAX_STEP_H and C.MAX_STEP_H / h or 1)
        elseif src == "generator" then
            if fuel > 0 then gen:setFuel(gen:getFuel() - chg.fed * fuel) end
            chg.fed = nil
        else
            chg.fed = nil
        end
    end
    chg.power = power
    chg.sup = fromCar(power) and gen:getKeyId() or nil
    chg.supX, chg.supY = chg.sup and gen:getX() or nil, chg.sup and gen:getY() or nil -- where it fed from (capped above)
    local left = math.max(0, limit - B.kwh(part))
    local charging = power
    if chg.paused == "stopped" then
        charging = nil
    elseif left <= T.KWH_EPS then -- the pack is a float (VehiclePart.java:375-387): 90 % of 78.4 reads back 70.5599976
        chg.paused, charging = "full", nil
    elseif not power or (fromCar(power) and kwS <= 0) then
        chg.paused, charging = "nopower", nil -- no source, or a Cybertruck whose share the others hold (power kept)
    else
        chg.paused = nil
    end
    chg.src = charging
    -- from a Cybertruck kw is the charging share: 0 while full, stopped or shut out, given back to the others
    if fromCar(power) then
        chg.kw = charging and kwS or 0
        draws[o].kw = chg.kw
    else
        chg.kw = kw
    end
    md.chg = chg
    v:transmitPartModData(part)
    local k = B.kwh(part)
    local step = C.MAX_STEP_H
    if charging then step = math.min(step, B.chargeHours(chg, cap, k, limit)) end
    -- grid power ends at the shut-off hour, charging or not (full / stopped still power the car's loads)
    if power == "grid" then step = math.min(step, gUntil - now) end
    if charging == "generator" and fuel > 0 then -- its fuel runs out while charging; not charging, the car's own
        -- loads burn it through chg.fed at each settle (hourly), never a step off the charging power
        step = math.min(step, B.chargeHours(chg, cap, k, math.min(limit, k + gen:getFuel() / fuel)))
    end
    if fromCar(power) and chg.kw > 0 then -- its limit
        step = math.min(step, B.chargeHours(chg, cap, k, math.min(limit, k + T.Powershare.avail(gen))))
    end
    C.schedule(o, now + math.max(step, 1 / 60))
    -- a Cybertruck on its own Wall Connector: Powershare decides here, on every settle (plan 4: plugging in, the
    -- shut-off hour, at least hourly while plugged in), whether the house has power without it
    if md.ps and T.Powershare then T.Powershare.update(v, part, o, power ~= nil) end
end

function C.start(o, v)
    local now = T.hours()
    local part = B.part(v)
    -- any charge cable plugged in turns a Cybertruck's bed outlet off (owner's manual p.200 says AC charging; we stop it
    -- for every charger, as the guide tells players): what it fed books up to now (also the cars waiting for it,
    -- Powershare.settleFed), then stops
    local outlet = part:getModData().outlet
    if outlet and T.Powershare then
        T.Powershare.settleFed(v)
        T.Powershare.broke(v) -- a car it fed that is not loaded now books at most an hour more (C.supplyEnded)
    end
    local kw = T.chargerKw(o.kind, v)
    part:getModData().chg = { x = o.x, y = o.y, z = o.z, kind = o.kind, kw = kw, peak = T.dcPeak(o.kind, v, kw),
        last = now, added = 0, src = nil, target = C.DEFAULT_TARGET, paused = nil }
    o.vid = v:getId()
    o:updateOnClient()
    C.setBusy(o, true)
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
    o.removing = true
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
    C.settle(o, T.hours(), nil, true) -- fresh: a Cybertruck that fed it may load a moment later (C.settle)
    -- after settle: one that unplugs it at once (no pack) sends no plugged-then-idle pair of unordered sprite packets
    if o.vid == v:getId() then C.setBusy(o, true) end
    T.log("relinked " .. tostring(v:getId()) .. " to " .. o.kind .. " at " .. o.x .. "," .. o.y .. "," .. o.z)
end

-- vehicle load runs createPhysics, which fires OnSpawnVehicleEnd every time (BaseVehicle.java:7952-7964, :904)
Events.OnSpawnVehicleEnd.Add(function(v)
    lastPos[v:getId()] = nil -- the id may have been another car's (C.noteMove; as Regen.lua does)
    if T.isTesla(v) then C.relink(v) end
end)

Events.EveryOneMinute.Add(function()
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

-- A generator switched on or off (ISActivateGenerator) by hand: the chargers in its reach settle up to now under the
-- old state (its fuel billed), then again from now under the new one (rescheduled). Without this a Supercharger that
-- sat on nopower for 40 minutes would book those 40 minutes on the curve the moment a generator came on (main agent
-- review 2026-11-09). Reach: the sandbox generator range, or a charger plugged straight in (genTiles, fixed 2) when
-- that is wider (GeneratorTileRange may be 1, SandboxOptions.java:253). ISPlugGenerator is not wrapped: connected only
-- sets the field (IsoGenerator.java:581-590); what powers a square (isActivated, isPoweringSquare, haveElectricity)
-- never reads it, and vanilla offers unplugging only while it is off. complete() runs on the server / SP
-- (NetTimedAction.java:132-134); Powershare.lua refuses it on its own generator on top of this. A hook error never
-- breaks the vanilla action.
local function reach()
    local r = SandboxVars.GeneratorTileRange or 20
    for _, c in pairs(T.Chargers) do
        if type(c) == "table" and c.genTiles and c.genTiles > r then r = c.genTiles end
    end
    return r
end
function C.aroundGenerator(cls, name)
    local orig = cls and cls.complete
    if not orig then
        T.log(name .. ".complete missing, generator switches do not settle chargers")
        return
    end
    cls.complete = function(self)
        local function settle()
            local ok, err = pcall(function()
                local g = self.generator
                if activeCount == 0 or not g then return end
                C.settleAround(g:getX(), g:getY(), g:getZ(), reach(), SandboxVars.GeneratorVerticalPowerRange or 3)
            end)
            if not ok then T.log("settle around a generator failed: " .. tostring(err)) end
        end
        settle()
        local r = orig(self)
        settle()
        return r
    end
end
C.aroundGenerator(ISActivateGenerator, "ISActivateGenerator")

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
    if not pct or pct ~= pct then return end -- NaN (0/0 over the wire) would set the target to 100 past the clamp
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
