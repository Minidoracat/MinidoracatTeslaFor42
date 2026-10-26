-- Charging: settle arithmetic (grid, generator fuel, target), cable length, scheduler cost, relink, plug guards, commands.
local check, near = H.check, H.near
H.side(false, true)

-- ---- fakes: world squares, generator, vanilla GOS classes ----
IsoDirections = { N = "N", S = "S", W = "W", E = "E" }
local squares = {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function square(x, y, z, o)
    o = o or {}
    local sq = { x = x, y = y, z = z, room = o.room, noPower = o.noPower or false, elec = o.elec or false, gen = nil, special = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getRoom() return self.room end
    function sq:isNoPower() return self.noPower end
    function sq:haveElectricity() return self.elec end
    function sq:getGenerator() return self.gen end
    function sq:getVehicleContainer() return self.vehicle end
    function sq:getAdjacentSquare(d)
        local dx, dy = 0, 0
        if d == "N" then dy = -1 elseif d == "S" then dy = 1 elseif d == "W" then dx = -1 else dx = 1 end
        return squares[key(self.x + dx, self.y + dy, self.z)]
    end
    squares[key(x, y, z)] = sq
    return sq
end
function getCell() return { getGridSquare = function(_, x, y, z) return squares[key(x, y, z)] end } end
local apo = 1
function getSandboxOptions() return { getTimeSinceApo = function() return apo end } end
Vector3f = { new = function() local v = { _x = 0, _y = 0 }; function v:x() return self._x end; function v:y() return self._y end; return v end }

local function generator(fuel, on)
    local g = { fuel = fuel, on = on }
    function g:isActivated() return self.on end
    function g:getFuel() return self.fuel end
    function g:setFuel(f) self.fuel = math.max(0, math.min(f, 10)) end
    return g
end

H.stub("Map/SGlobalObjectSystem")
H.stub("Map/SGlobalObject")
local function derive(base, name)
    local c = setmetatable({ Type = name }, { __index = base })
    c.__index = c
    return c
end
SGlobalObject = { derive = derive }
SGlobalObject.__index = SGlobalObject
function SGlobalObject.new(cls, sys, g)
    local o = setmetatable(g, cls)
    o.luaSystem, o.x, o.y, o.z = sys, g.gx_, g.gy_, g.gz_
    return o
end
function SGlobalObject:getIsoObject() return self.iso end
function SGlobalObject:updateOnClient() self.updates = (self.updates or 0) + 1 end
SGlobalObjectSystem = { derive = derive }
SGlobalObjectSystem.__index = SGlobalObjectSystem
function SGlobalObjectSystem.new(cls, name)
    local o = setmetatable({ objs = {}, systemName = name }, cls)
    o.system = { setModDataKeys = function() end, setObjectModDataKeys = function(_, k) o.saved = k end,
        setObjectSyncKeys = function(_, k) o.synced = k end }
    o:initSystem()
    o:initLuaObjects()
    return o
end
function SGlobalObjectSystem:initSystem() end
function SGlobalObjectSystem:initLuaObjects() end
function SGlobalObjectSystem:getLuaObjectCount() return 0 end
function SGlobalObjectSystem:getLuaObjectAt(x, y, z) return self.objs[key(x, y, z)] end
function SGlobalObjectSystem:getLuaObjectOnSquare(sq) return sq and self:getLuaObjectAt(sq:getX(), sq:getY(), sq:getZ()) end
function SGlobalObjectSystem:loadIsoObject(iso) end
function SGlobalObjectSystem.RegisterSystemClass(cls) cls.instance = cls:new() end
MapObjects = { OnLoadWithSprite = function(list, fn) H.onLoadSprites = list end }

require "MinidoracatTesla/Charging"
local T, B, C = MinidoracatTesla, MinidoracatTesla.Battery, MinidoracatTesla.Charge
local SYS = SMinidoracatTeslaChargerSystem.instance
check(SYS ~= nil and SYS.systemName == "MinidoracatTeslaCharger", "charger system registered under its contract name")
check(SYS.saved[1] == "kind" and SYS.synced[3] == "vid", "saves kind/facing, syncs kind/facing/vid")
check(#H.onLoadSprites == 4, "chunk load hook covers the 4 Wall Connector sprites")

-- a placed charger at (200,200,0) facing S, inside a room
local function charger(x, y, o)
    local sq = square(x, y, 0, o)
    local iso = { sq = sq, sprite = "minidoracat_tesla_01_0" }
    function iso:getSquare() return self.sq end
    function iso:getSprite() local n = self.sprite; return { getName = function() return n end } end
    local lo = SMinidoracatTeslaCharger:new(SYS, { gx_ = x, gy_ = y, gz_ = 0 })
    lo:stateFromIsoObject(iso)
    lo.iso = iso
    SYS.objs[key(x, y, 0)] = lo
    return lo, iso, sq
end
-- a Model Y whose charge port is at (px, py)
local function car(kwh, px, py)
    local v = H.vehicle({ kwh = kwh, x = px, y = py })
    v._class = "BaseVehicle"
    function v:getAttachmentWorldPos(_, out) out._x, out._y = self.x, self.y; return out end
    return v
end
local owner = H.player({ name = "own", keys = { [77] = true }, x = 201, y = 202 })
SandboxVars.ElecShutModifier = 14
SandboxVars.GeneratorFuelConsumption = 0.1
local WC = T.Chargers.WallConnector

H.section("plug and grid settle")
local lo, iso, sq = charger(200, 200, { room = {} })
check(lo.kind == "WallConnector" and lo.facing == "S", "sprite 0 is a south-facing Wall Connector")
local v = car(10, 202.5, 203.5)
H.setHours(100)
C.plug(owner, v, iso)
local chg = B.part(v):getModData().chg
check(chg ~= nil and chg.x == 200 and chg.target == 90 and chg.src == "grid" and chg.paused == nil, "plug links the pack: grid, target 90")
check(lo.vid == v:getId() and lo.updates >= 1, "charger knows the car and syncs vid")
check(C.activeCount() == 1, "one active charger")
H.setHours(102)
C.settle(lo, H.hours())
check(near(B.kwh(B.part(v)), 10 + 2 * 11.5, 1e-6) and near(chg.added, 23, 1e-6), "2 h on grid adds 23 kWh")
H.setHours(110)
C.settle(lo, H.hours())
check(near(B.pct(B.part(v)), 90, 1e-6) and chg.paused == "full" and chg.src == nil, "stops at the 90% target, paused=full")
check(C.nextDue() > H.hours() and C.nextDue() <= H.hours() + C.MAX_STEP_H + 1e-9, "full still re-checks within an hour")

H.section("scheduler cost")
local settles = 0
local realSettle = C.settle
C.settle = function(...) settles = settles + 1; return realSettle(...) end
H.setHours(C.nextDue() - 0.05)
H.fire("EveryTenMinutes")
check(settles == 0, "EveryTenMinutes before the due hour settles nothing")
H.setHours(C.nextDue() + 0.01)
H.fire("EveryTenMinutes")
check(settles == 1, "due hour reached: exactly the due charger settles")
C.settle = realSettle

H.section("chargeTarget / chargeStop")
owner.x, owner.y = 201, 202
H.fire("OnClientCommand", "MinidoracatTesla", "chargeTarget", owner, { vid = v:getId(), pct = 100 })
check(chg.target == 100 and chg.paused == nil and chg.src == "grid", "raising the target resumes charging")
H.fire("OnClientCommand", "MinidoracatTesla", "chargeStop", owner, { vid = v:getId() })
check(chg.paused == "stopped", "chargeStop pauses")
local k = B.kwh(B.part(v))
H.setHours(H.hours() + 1)
C.settle(lo, H.hours())
check(B.kwh(B.part(v)) == k, "no energy while stopped")
local stranger = H.player({ name = "mal", x = 201, y = 202 })
H.sent = {}
H.fire("OnClientCommand", "MinidoracatTesla", "chargeTarget", stranger, { vid = v:getId(), pct = 50 })
check(chg.target == 100 and H.sent[1] and H.sent[1].args.reason == "NOT_OWNER", "strangers cannot change the target")

H.section("unplug")
H.fire("OnClientCommand", "MinidoracatTesla", "chargeTarget", owner, { vid = v:getId(), pct = 100 })
B.set(v, B.part(v), 30)
H.setHours(H.hours() + 0.5)
C.unplug(owner, v)
check(near(B.kwh(B.part(v)), 30 + 0.5 * 11.5, 1e-6), "unplug books the energy up to now")
check(B.part(v):getModData().chg == nil and lo.vid == false and C.activeCount() == 0, "unplug clears the link (vid=false so it syncs) and the schedule")
check(T.CheckEngine.Battery(v, B.part(v)) == true, "unplugged car can start again")

H.section("grid shut-off and generator")
-- grid ends at world hour (14 - 0) * 24 = 336 with TimeSinceApo 1
-- stopped (or full) on the grid: still settles at the shut-off hour, the grid runs the car's own loads until then
local loF, isoF = charger(320, 300, { room = {}, elec = true })
local vF = car(5, 322.5, 303.5)
local pF = H.player({ name = "own", keys = { [77] = true }, x = 321, y = 302 })
H.setHours(335.5)
C.plug(pF, vF, isoF)
B.part(vF):getModData().chg.paused = "stopped"
C.settle(loF, H.hours())
check(B.part(vF):getModData().chg.power == "grid" and near(C.nextDue(), 336, 1e-9),
    "stopped on the grid at 335.5: next settle at the 336 shut-off, not an hour later")
C.unplug(pF, vF)
local lo2, iso2, sq2 = charger(300, 300, { room = {}, elec = true })
local genSq = square(305, 300, 0)
genSq.gen = generator(10, true)
local v2 = car(0, 302.5, 303.5)
H.setHours(335)
C.plug(owner2 or H.player({ name = "own", keys = { [77] = true }, x = 301, y = 302 }), v2, iso2)
local chg2 = B.part(v2):getModData().chg
check(chg2 and chg2.src == "grid", "grid while it lasts")
check(C.nextDue() <= 336 + 1e-9, "next settle at the grid shut-off hour")
H.setHours(338)
T.Sentry = T.Sentry or {}
local realSentry0, sentryArgs = T.Sentry.settle, nil
T.Sentry.settle = function(_, t, freeUntil) sentryArgs = { t = t, free = freeUntil } end
check(chg2.power == "grid", "plugged on the grid: power = grid")
C.settle(lo2, H.hours())
T.Sentry.settle = realSentry0
check(sentryArgs and sentryArgs.t == 338 and sentryArgs.free == 338,
    "settle past the grid shut-off with a generator there: it took over, sentry standby free up to now")
local dark, lit = { power = "grid", x = 900, y = 900, z = 0 }, { power = "grid", x = 300, y = 300, z = 0 } -- lit: elec
check(C.powerUntil(dark, 338) == 336 and C.powerUntil(dark, 335) == 335 and C.powerUntil(lit, 338, false) == 336
    and C.powerUntil({ power = "generator" }, 338) == 338 and C.powerUntil({ power = nil }, 338) == nil
    and C.powerUntil(nil, 338) == nil, "powerUntil: grid to the 336 shut-off unless a generator took over, generator to now")
check(C.powerUntil(lit, 338) == 338,
    "powerUntil not told (sentry event between settles): the charger square still has power -> a generator, free to now")
check(chg2.power == "generator", "after the shut-off: power = generator")
local rate = WC.fuelPerHour * 0.1
check(near(B.kwh(B.part(v2)), 3 * 11.5, 1e-6), "1 h grid + 2 h generator = 3 h of charge")
check(near(genSq.gen.fuel, 10 - 2 * rate, 1e-6), "generator burned 0.13 x GeneratorFuelConsumption per hour for 2 h")
check(chg2.src == "generator" and chg2.paused == nil, "source switched to generator")
genSq.gen.fuel = rate * 0.5 -- half an hour of fuel left
local k2 = B.kwh(B.part(v2))
H.setHours(340)
C.settle(lo2, H.hours())
check(near(B.kwh(B.part(v2)) - k2, 0.5 * 11.5, 1e-6) and genSq.gen.fuel == 0, "charging stops when the generator runs dry")
check(chg2.paused == "nopower" and chg2.src == nil, "no grid, no fuel: paused=nopower")
genSq.gen.fuel = 5
H.setHours(341)
C.settle(lo2, H.hours())
check(chg2.paused == nil and chg2.src == "generator", "refuelled generator resumes on the next settle")

H.section("no power at all")
local lo3, iso3 = charger(400, 400, {}) -- outdoors: fridge rule gives no grid; no generator
local v3 = car(5, 402.5, 403.5)
H.setHours(120)
C.plug(H.player({ name = "own", keys = { [77] = true }, x = 401, y = 402 }), v3, iso3)
local chg3 = B.part(v3):getModData().chg
H.setHours(125)
C.settle(lo3, H.hours())
check(chg3.paused == "nopower" and B.kwh(B.part(v3)) == 5, "outdoor wall connector without generator does not charge")

H.section("cable length")
v3.x, v3.y = 400.5 + 7, 400.5
H.setHours(126)
C.settle(lo3, H.hours())
check(B.part(v3):getModData().chg == nil and lo3.vid == false, "towed beyond 6 tiles: auto-unplugged")
local lo4, iso4 = charger(500, 500, { room = {} })
local v4 = car(5, 500.5, 500.5)
C.plug(H.player({ name = "own", keys = { [77] = true }, x = 501, y = 501 }), v4, iso4)
T.Sentry = T.Sentry or {}
local realSentry1, sentryPower = T.Sentry.settle, nil
T.Sentry.settle = function(veh) local c = B.part(veh):getModData().chg; sentryPower = c and c.power or "unplugged" end
v4.x = 500.5 + 6.5
T.Update.Battery(v4, B.part(v4), 1)
T.Sentry.settle = realSentry1
check(B.part(v4):getModData().chg == nil, "battery part update also unplugs when the cable no longer reaches")
check(sentryPower == "grid", "auto-unplug books sentry standby first, while the charger still powers it")

H.section("plug guards")
local lo5, iso5 = charger(600, 600, { room = {} })
local v5 = car(5, 600.5 + 8, 600.5)
local p5 = H.player({ name = "own", keys = { [77] = true }, x = 601, y = 601 })
H.sent = {}
C.plug(p5, v5, iso5)
check(H.sent[#H.sent].args.reason == "CABLE_SHORT" and B.part(v5):getModData().chg == nil, "too far for the cable: refused")
v5.x = 602.5
v5.running, v5.speed = true, 5
C.plug(p5, v5, iso5)
check(H.sent[#H.sent].args.reason == "MOVING" and B.part(v5):getModData().chg == nil, "rolling at 5 km/h: refused MOVING")
v5.speed = 0.5
C.plug(p5, v5, iso5)
local chg5 = B.part(v5):getModData().chg
check(chg5 ~= nil and chg5.src == "grid" and chg5.power == "grid", "stopped with the motor running: plugged in and charging (owner's manual, Shifting)")
check(T.CheckEngine.Battery(v5, B.part(v5)) == true, "plugged in: the car can still be started")
local k5 = B.kwh(B.part(v5))
T.Update.Battery(v5, B.part(v5), 10)
check(B.kwh(B.part(v5)) == k5, "plugged into a powered charger: the running motor's standby leaves the pack alone")
C.unplug(p5, v5)
v5.running, v5.speed = false, 0
H.sent = {}
C.plug(H.player({ name = "mal", x = 601, y = 601 }), v5, iso5)
check(H.sent[#H.sent].args.reason == "NOT_OWNER", "no key, no VehicleManager right: refused")
C.plug(p5, v5, iso5)
local v6 = car(5, 601.5, 602.5)
C.plug(p5, v6, iso5)
check(H.sent[#H.sent].args.reason == "CHARGER_BUSY" and B.part(v6):getModData().chg == nil, "second car on a busy charger: refused")
local touched = 0
MinidoracatVehicleManager = { Parked = { touch = function() touched = touched + 1 end } }
MinidoracatVehicleManagerAPI = { canUse = function(p, veh, perm) return perm == "FUEL" and p == p5, "OK" end }
C.unplug(p5, v5)
C.plug(p5, v6, iso5)
check(B.part(v6):getModData().chg ~= nil and touched >= 2, "VehicleManager: FUEL right checked, Parked.touch after changes")
MinidoracatVehicleManager, MinidoracatVehicleManagerAPI = nil, nil

H.section("relink after restart")
local sentrySettled = 0
T.Sentry = T.Sentry or {}
local realSentry = T.Sentry.settle
T.Sentry.settle = function() sentrySettled = sentrySettled + 1 end
local md6 = B.part(v6):getModData()
-- restart: vehicle ids are reallocated, the charger loses vid, the schedule is empty
H.removeVehicle(v6)
lo5.vid = nil
C.unschedule(lo5)
v6.id = 9001
local reg = H.vehicle({ id = 9001 })
reg.parts, reg.x, reg.y, reg._class = v6.parts, v6.x, v6.y, "BaseVehicle"
reg.getAttachmentWorldPos = v6.getAttachmentWorldPos
H.setHours(H.hours() + 1)
local before = B.kwh(B.part(reg))
H.fire("OnSpawnVehicleEnd", reg)
check(lo5.vid == 9001 and C.activeCount() >= 1, "vehicle load relinks the charger to the new id")
check(B.kwh(B.part(reg)) > before and sentrySettled == 1, "relink settles the offline hour and calls Sentry.settle")
local gone = car(5, 700.5, 700.5)
B.part(gone):getModData().chg = { x = 700, y = 700, z = 0, kind = "WallConnector", last = 1, target = 90 }
H.fire("OnSpawnVehicleEnd", gone)
check(B.part(gone):getModData().chg == nil, "charger gone while offline: the link is cleared on load")
T.Sentry.settle = realSentry

H.section("charger removed")
lo5:aboutToRemoveFromSystem()
check(B.part(reg):getModData().chg == nil and not lo5.vid, "picking up the charger unplugs the car")
