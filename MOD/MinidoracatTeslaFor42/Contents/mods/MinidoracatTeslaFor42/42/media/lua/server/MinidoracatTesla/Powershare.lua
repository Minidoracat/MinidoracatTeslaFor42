-- Cybertruck Powershare Home Backup and the bed outlet (design temp/plan-cybertruck-1030 item 4; research powershare.md).
-- Powershare (owner's manual p.204-206): switched on and plugged into a Wall Connector, the truck backs up the house
-- once it has no power (the sandbox shut-off, no other running generator). The engine powers a square from the grid or
-- from a generator's position only (IsoGridSquare.java:9696-9700, 11799-11805), so the server puts a vanilla
-- IsoGenerator by the truck: our invisible tile and hidden item (Chargers.lua T.PS_SPRITE / T.PS_ITEM; silent, no
-- wear). Its fuel = the kWh above the discharge limit at vanilla's rate (T.GEN_FUEL_PER_KWH x GeneratorFuelConsumption,
-- no ChargeFuelMultiplier: Powershare burns nothing); each settle books the fuel the house burnt since as kWh off the
-- pack and fills it again. Appliances, sync, saving and the catch-up after an unload are vanilla's.
-- Other Teslas charging from it, or from the bed outlet, take their kWh straight off this pack (Charging.lua C.takeFrom).
-- No polling: everything runs from the truck's own charger settles (plugging in, the shut-off hour, at least hourly while
-- plugged in), unplugging, the switches, and the tailgate.
-- State: battery part modData `ps` = { on, floor, by, gx, gy, gz, fuelSet, stop, kw } and `outlet` = true
-- (architecture.md section 4).
if isClient() then return end
require "MinidoracatTesla/Chargers"
require "MinidoracatTesla/Battery"
require "MinidoracatTesla/Charging"
require "MinidoracatTesla/Inbox"
require "MinidoracatTesla/Liftgate"

local T = MinidoracatTesla
local B, C = T.Battery, T.Charge
local PS = {}
T.Powershare = PS

-- Removing the mod leaves a running one as a plain vanilla generator (unknown sprite, IsoObject.java:1073-1083:
-- Base.Generator, engine sound, zombies, wear). Its fuel never holds more than CAP_HOURS of a generator's least draw
-- (its own BASE_DRAW with nothing plugged in, IsoGenerator.java:58,276; the house's load can drop that far once the
-- mod is gone: E2E powershare-removed-sp read 0.02 after the reload), so it runs dry before wear can make it backfire
-- or burn (IsoGenerator.java:199-254; ~1,200 h to condition 40 at 1 in 30). 1.44 L at GFC 0.1: 46 h of a house
-- drawing 0.31 (fridge, lights); the truck refills it at every settle (at least hourly while plugged in).
-- ponytail: a house drawing over 14.4 (1.44 L an hour, ~100 fridges) goes dark before the next hourly settle.
PS.CAP_HOURS = 720
PS.BASE_DRAW = 0.02
PS.MIN_KWH = 0.01   -- less above the limit than this: stopped
PS.PICK_TILES = 8   -- a car in a garage: the nearest outdoor square this near
PS.OUTLET_TILES = 10 -- the bed outlet's chargers to settle around the truck after a change

local function r0() return T.GEN_FUEL_PER_KWH * (SandboxVars.GeneratorFuelConsumption or 0.1) end
local function key(x, y, z) return x .. "," .. y .. "," .. z end

-- kWh above the discharge limit
function PS.avail(v, part)
    part = part or B.part(v)
    if not (part and part:getInventoryItem()) then return 0 end
    return math.max(0, B.kwh(part) - B.capacity(part) * T.psFloor(part) / 100)
end

-- ---------------------------------------------------------------- the generator
local byGen = {} -- "x,y,z" -> vehicle id of the truck whose generator it is (rebuilt as trucks settle or load)

-- the generator square of record ps: the generator (nil when gone) and whether the square is loaded at all
local function genOf(ps)
    local sq = getCell():getGridSquare(ps.gx, ps.gy, ps.gz)
    if not sq then return nil, false end
    local objs = sq:getSpecialObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoGenerator") and T.isPowershare(o) then return o, true end
    end
    return nil, true
end

-- The truck whose running Powershare generator g is (loaded, its record still on that square), else nil.
function PS.carOf(g)
    local sq = g:getSquare()
    if not sq then return nil end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local v = getVehicleById(byGen[key(x, y, z)] or -1)
    local part = v and B.part(v)
    local ps = part and part:getModData().ps
    if ps and ps.gx == x and ps.gy == y and ps.gz == z then return v end
    return nil
end

-- The car's square unless it is inside a building: a running generator there makes the whole building toxic
-- (IsoGenerator.java:191-194, 525-528). Then the nearest square within PICK_TILES on the same floor that is outdoors or
-- no building's. Never a square with a generator already (getGenerator answers the first, IsoGridSquare.java:9713).
local function free(sq) return sq ~= nil and (sq:isOutside() or not sq:getBuilding()) and not sq:getGenerator() end
function PS.pickSquare(v)
    local sq = v:getSquare()
    if not sq then return nil end
    if free(sq) then return sq end
    local cell, x, y, z = getCell(), sq:getX(), sq:getY(), sq:getZ()
    for d = 1, PS.PICK_TILES do
        for dx = -d, d do
            for dy = -d, d do
                if math.max(math.abs(dx), math.abs(dy)) == d then
                    local s = cell:getGridSquare(x + dx, y + dy, z)
                    if free(s) then return s end
                end
            end
        end
    end
    return nil
end

local function place(v, ps)
    local sq = PS.pickSquare(v)
    if not sq then return nil end
    local item = instanceItem(T.PS_ITEM)
    if not item then
        T.log("powershare: no item " .. T.PS_ITEM)
        return nil
    end
    item:getModData().fuel = 0
    -- IsoGenerator(item, cell, sq) adds it to the square and, on a server, sends it to the clients (IsoGenerator.java:96-108)
    local g = IsoGenerator.new(item, getWorld():getCell(), sq)
    g:setConnected(true)
    ps.gx, ps.gy, ps.gz, ps.fuelSet = sq:getX(), sq:getY(), sq:getZ(), 0
    T.log("powershare on vid=" .. v:getId() .. " generator at " .. key(ps.gx, ps.gy, ps.gz))
    return g
end

-- Book what the house burnt since the last fill as kWh off the pack (the cars it charged were booked as they settled).
-- ponytail: a generator gone (burnt down, smashed) counts as having burnt all it had
local function book(v, part, ps, g)
    local r = r0()
    local left = g and g:getFuel() or 0
    if r > 0 and ps.fuelSet then
        local used = math.max(0, ps.fuelSet - left) / r
        if used > 0 then B.set(v, part, B.kwh(part) - used) end
    end
    ps.fuelSet = left
end

-- Fuel = kWh above the limit, at most a full tank and CAP_HOURS of the house's load; condition kept new. GFC 0: vanilla's
-- free generators, a full tank and no charge taken (CHANGELOG).
local function fill(v, part, ps, g)
    if not g:isActivated() then
        g:setFuel(10)
        g:setActivated(true) -- works out the house's load (setSurroundingElectricity, IsoGenerator.java:545)
    end
    local r = r0()
    local fuel = 10
    if r > 0 then
        fuel = math.min(10, PS.avail(v, part) * r, PS.BASE_DRAW * (SandboxVars.GeneratorFuelConsumption or 0.1) * PS.CAP_HOURS)
    end
    if math.abs(g:getFuel() - fuel) > 1e-4 then g:setFuel(fuel) end -- syncs (IsoGenerator.java:509-518)
    if g:getCondition() < 100 then g:setCondition(100) end
    ps.fuelSet = fuel
    -- shown in the app: the house (litres an hour / litres a kWh) plus the cars it charges
    ps.kw = (r > 0 and g:getTotalPowerUsing() / r or 0) + C.drawnKw(v)
    byGen[key(ps.gx, ps.gy, ps.gz)] = v:getId()
end

-- off, then gone: removeFromWorld leaves the chunks' generator positions (IsoGenerator.java:468-479), setActivated(false)
-- clears them and syncs; the removal packet is the server's (environment.md, 42.21). The cars it charged settle before
-- (they book up to now with it) and after (they see it gone).
local function unsupply(v, ps, g)
    C.settleSupplied(v)
    if g then
        g:setActivated(false)
        g:getSquare():transmitRemoveItemFromSquare(g)
    end
    byGen[key(ps.gx, ps.gy, ps.gz)] = nil
    T.log("powershare generator removed at " .. key(ps.gx, ps.gy, ps.gz))
    ps.gx, ps.gy, ps.gz, ps.fuelSet, ps.kw = nil, nil, nil, nil, nil
    C.settleSupplied(v)
end

-- the house burnt some since the last settle and another car took some: book it, fill again (C.takeFrom)
local busy = {}
function PS.touch(v)
    if busy[v] then return end
    local part = B.part(v)
    local ps = part and part:getModData().ps
    if not (ps and ps.gx) then return end
    local g, here = genOf(ps)
    if not (g and here) then return end
    book(v, part, ps, g)
    fill(v, part, ps, g)
end

-- ---------------------------------------------------------------- the decision
-- Called at the end of every settle of the truck's own charger (Charging.lua C.settle; o = that charger, other = it has
-- power without this truck: the grid, another generator, another truck), and with o = nil once unplugged.
-- Supplies when on, plugged into a Wall Connector, no other power, above the limit (plan 4's state machine).
local function update(v, part, ps, o, other)
    local g, here = nil, true
    if ps.gx then
        g, here = genOf(ps)
        if not here then return end -- its square is not loaded: next settle
    end
    local was = T.psState(part)
    local want = ps.on and T.spec(v).powershare and o ~= nil and o.kind == "WallConnector" and not other
        and part:getInventoryItem() ~= nil
    if ps.gx then
        book(v, part, ps, g)
        if not g then unsupply(v, ps, nil) end -- gone from its square: a new one below if still wanted
    end
    local placed = false
    if want and PS.avail(v, part) > PS.MIN_KWH then
        ps.stop = nil
        if not g then
            g = place(v, ps)
            placed = g ~= nil
            if not g then T.log("powershare vid=" .. v:getId() .. ": no outdoor square near for the generator") end
        end
        if g then fill(v, part, ps, g) end
    else
        ps.stop = want or nil -- the house is out of power and the pack at its limit
        if ps.gx then unsupply(v, ps, g) end
    end
    local now = T.psState(part)
    v:transmitPartModData(part)
    if was ~= now then T.log("powershare vid=" .. v:getId() .. " " .. was .. " -> " .. now) end
    if was == "backup" and now == "stopped" then
        local e = T.Inbox.entry(v, "lowBattery", "powershare")
        e.pct = T.psFloor(part)
        T.Inbox.notify(ps.by, e)
    end
    if placed then -- the chargers in its range take it from now on (IsoGenerator.isPoweringSquare: the sandbox range)
        C.settleAround(ps.gx, ps.gy, ps.gz, SandboxVars.GeneratorTileRange or 20, SandboxVars.GeneratorVerticalPowerRange or 3, v)
    end
end
function PS.update(v, part, o, other)
    local ps = part:getModData().ps
    if not ps or busy[v] then return end
    busy[v] = true
    local ok, err = pcall(update, v, part, ps, o, other)
    busy[v] = nil
    if not ok then T.log("powershare update failed: " .. tostring(err)) end
end

-- the cable came out (Charging.lua clearChg): Powershare stops; a bed outlet that AC charging held off supplies again
function PS.unplugged(v, part)
    if part:getModData().ps then PS.update(v, part, nil, false) end
    if part:getModData().outlet then PS.outletChanged(v) end
end

-- ---------------------------------------------------------------- the bed outlet
local function register(v)
    local key0 = v:getKeyId()
    for id, k in pairs(T.OutletCars) do
        if k == key0 and id ~= v:getId() then T.OutletCars[id] = nil end -- this truck under an older id
    end
    T.OutletCars[v:getId()] = key0
end
-- the chargers it feeds book up to now (call before the change), the ones near take the new state (after)
function PS.outletChanged(v)
    C.settleAround(math.floor(v:getX()), math.floor(v:getY()), math.floor(v:getZ()), PS.OUTLET_TILES, 0, v)
end

-- ---------------------------------------------------------------- switches (radial menu, phone app)
-- what: "ps" | "outlet" | "floor". The cable rule decides who (T.mayUseCable: VehicleManager's FUEL, else a key or an
-- unlocked car), as for the charge card. Returns nil, or a deny reason.
function PS.set(player, v, what, on, pct)
    local s = T.spec(v)
    local part = B.part(v)
    if not (s and part) then return "NO_VEHICLE" end
    if what == "outlet" then
        if not s.bedOutlet then return "NO_OUTLET" end
    elseif not s.powershare then
        return "NO_POWERSHARE"
    end
    local ok, deny = T.mayUseCable(player, v)
    if not ok then return deny end
    local md = part:getModData()
    if what == "outlet" then
        if (md.outlet == true) == on then return nil end
        C.settleSupplied(v)
        md.outlet = on or nil
        if on then register(v) else T.OutletCars[v:getId()] = nil end
        v:transmitPartModData(part)
        PS.outletChanged(v)
        T.log("bed outlet " .. (on and "on" or "off") .. " vid=" .. v:getId() .. " by " .. player:getUsername())
        return nil
    end
    local ps = md.ps or {}
    md.ps = ps
    if what == "floor" then
        if type(pct) ~= "number" or pct ~= pct then return "BAD_VALUE" end
        ps.floor = math.max(T.PS_FLOOR_MIN, math.min(T.PS_FLOOR_MAX, math.floor(pct + 0.5)))
        if md.outlet then C.settleSupplied(v) end
    else
        if ps.on == on then return nil end
        ps.on = on
        if on then ps.by = T.account(player) end -- the owner told when it stops (nil: a split-screen guest)
        T.log("powershare " .. (on and "on" or "off") .. " vid=" .. v:getId() .. " by " .. player:getUsername())
    end
    -- decide now: plugged in, its charger's settle does (C.settle -> PS.update); else nothing is on the cable
    if not C.settleCar(v) then PS.update(v, part, nil, false) end
    if md.outlet then PS.outletChanged(v) end
    return nil
end

T.ServerCommands = T.ServerCommands or {}
local function command(what, on)
    return function(player, args)
        local v = T.commandVehicle(player, args) -- in it, or within T.NEAR (Commands.lua)
        if not v then return end
        local why = PS.set(player, v, what, on)
        if why then T.deny(player, why, v:getId()) end
    end
end
T.ServerCommands.psOn = command("ps", true)
T.ServerCommands.psOff = command("ps", false)
T.ServerCommands.outletOn = command("outlet", true)
T.ServerCommands.outletOff = command("outlet", false)

-- ---------------------------------------------------------------- the tailgate (the outlet works with it down, p.200)
-- before it moves the chargers the outlet feeds book with it as it was; after, the ones near take the new state
local function aroundTailgate(v, part, fn)
    local watch = v and part and part:getId() == "TrunkDoor" and T.OutletCars[v:getId()] ~= nil
    if watch then pcall(C.settleSupplied, v) end
    local r = fn()
    if watch then
        local ok, err = pcall(PS.outletChanged, v)
        if not ok then T.log("bed outlet after the tailgate failed: " .. tostring(err)) end
    end
    return r
end
local swing = T.Liftgate.swing -- the dashboard and the app (Liftgate.lua, Remote.lua)
T.Liftgate.swing = function(v, part, open, who)
    return aroundTailgate(v, part, function() return swing(v, part, open, who) end)
end
for _, cls in ipairs({ ISOpenVehicleDoor, ISCloseVehicleDoor }) do -- by hand (server / SP, LuaTimedActionNew.java:166-168)
    local orig = cls.complete
    cls.complete = function(self)
        return aroundTailgate(self.vehicle, self.part, function() return orig(self) end)
    end
end

-- ---------------------------------------------------------------- load
-- every load (BaseVehicle.java:904): the outlet list, and the generator's owner
Events.OnSpawnVehicleEnd.Add(function(v)
    local part = B.part(v)
    local md = part and part:getModData()
    if not md then return end
    if md.outlet then register(v) end
    local ps = md.ps
    if ps and ps.gx then byGen[key(ps.gx, ps.gy, ps.gz)] = v:getId() end
end)

-- vanilla's generator menu (info, switch, plug, fuel, fix, take) never shows for ours: the client drops it from what
-- the right click fetched (client/MinidoracatTesla/PowershareUI.lua)

return PS
