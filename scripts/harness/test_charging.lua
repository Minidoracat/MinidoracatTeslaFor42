-- Charging: settle arithmetic (grid, generator fuel, target), cable length, scheduler cost, relink, plug guards, commands.
local check, near = H.check, H.near
H.side(false, true)

-- ---- fakes: world squares, generator, vanilla GOS classes ----
IsoDirections = { N = "N", S = "S", W = "W", E = "E" }
local squares = {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function square(x, y, z, o)
    o = o or {}
    local outside = o.outside
    if outside == nil then outside = o.room == nil end -- the fake's default: a room is indoors, anything else outdoors
    local sq = { x = x, y = y, z = z, room = o.room, noPower = o.noPower or false, elec = o.elec or false, gen = nil,
        special = {}, outside = outside }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getRoom() return self.room end
    function sq:isNoPower() return self.noPower end
    function sq:haveElectricity() return self.elec end
    function sq:isOutside() return self.outside end
    function sq:hasGridPower() return not self.noPower end
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
-- vanilla ISUninstallVehiclePart:complete on success (ISUninstallVehiclePart.lua:62-69): the pack takes the part's
-- content, the part's item goes; fail = nothing happens
local uninstallBefore = ISUninstallVehiclePart -- other files' (park_fakes.lua): restored at the end
ISUninstallVehiclePart = { complete = function(self)
    if self.fail then return true end
    self.taken, self.content = self.part:getInventoryItem(), self.part:getContainerContentAmount() -- :63 setItemCapacity
    self.part.item = nil
    return true
end }

require "MinidoracatTesla/Charging"
local T, B, C = MinidoracatTesla, MinidoracatTesla.Battery, MinidoracatTesla.Charge
local SYS = SMinidoracatTeslaChargerSystem.instance
check(SYS ~= nil and SYS.systemName == "MinidoracatTeslaCharger", "charger system registered under its contract name")
check(SYS.saved[1] == "kind" and SYS.saved[3] == "owner" and SYS.synced[3] == "owner" and SYS.synced[4] == "vid",
    "saves kind/facing/owner, syncs kind/facing/owner/vid")
check(#H.onLoadSprites == 8, "chunk load hook covers the 4 Wall Connector + 4 Mobile Connector sprites")

-- a placed charger at (200,200,0) facing S, inside a room
local function charger(x, y, o, sprite)
    local sq = square(x, y, 0, o)
    local iso = { sq = sq, sprite = sprite or "minidoracat_tesla_01_0" }
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
v.locked = true
H.fire("OnClientCommand", "MinidoracatTesla", "chargeTarget", stranger, { vid = v:getId(), pct = 50 })
check(chg.target == 100 and H.sent[1] and H.sent[1].args.reason == "CAR_LOCKED", "strangers cannot change a locked car's target (CAR_LOCKED)")
v.locked = false
-- phone app (Remote.lua): no distance here, the caller checked reach and rights
check(C.setStopped(v, false) == true and chg.paused == nil and chg.src == "grid", "setStopped(false): the app resumes a stopped charge")
check(C.setStopped(v, true) == true and chg.paused == "stopped", "setStopped(true): the app stops it")
C.setStopped(v, false)
local plainCar = H.vehicle({ x = 300, y = 300 })
local ok2, why2 = C.setStopped(plainCar, true)
check(ok2 == false and why2 == "NOT_PLUGGED", "setStopped on a car without a cable: NOT_PLUGGED")

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
local rate = 11.5 * T.fuelPerKwh()
check(near(B.kwh(B.part(v2)), 3 * 11.5, 1e-6), "1 h grid + 2 h generator = 3 h of charge")
check(near(genSq.gen.fuel, 10 - 2 * rate, 1e-6) and near(rate, 11.5 * 100 / 78.4 * 0.1, 1e-9),
    "generator burned 11.5 kW x GEN_FUEL_PER_KWH x GeneratorFuelConsumption per hour for 2 h")
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
v5.locked = true
C.plug(H.player({ name = "mal", x = 601, y = 601 }), v5, iso5)
check(H.sent[#H.sent].args.reason == "CAR_LOCKED", "no key, car locked, no VehicleManager: refused CAR_LOCKED")
v5.locked = false
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
square(700, 700, 0, { elec = true }) -- a generator powers the square, but the charger is gone
B.part(gone):getModData().chg = { x = 700, y = 700, z = 0, kind = "WallConnector", last = 1, target = 90, power = "grid" }
local goneFree, h0 = nil, H.hours()
T.Sentry.settle = function(_, _, freeUntil) goneFree = freeUntil end
H.setHours(400) -- loaded again after the 336 grid shut-off
H.fire("OnSpawnVehicleEnd", gone)
H.setHours(h0)
check(B.part(gone):getModData().chg == nil, "charger gone while offline: the link is cleared on load")
check(goneFree == 336, "charger gone, square still powered: sentry standby free only to the grid shut-off (no generator takeover)")
T.Sentry.settle = realSentry

H.section("charger removed")
lo5:aboutToRemoveFromSystem()
check(B.part(reg):getModData().chg == nil and not lo5.vid, "picking up the charger unplugs the car")

H.section("mobile connector")
local MC = T.Chargers.MobileConnector
check(MC.kw == 7.6 and MC.cableTiles == 5 and MC.item == "Base.MinidoracatTesla_MobileConnector",
    "Mobile Connector: 7.6 kW, 5-tile cable (official 32 A / 240 V, 6 m)")
check(near(T.fuelPerKwh(), T.GEN_FUEL_PER_KWH * 0.1, 1e-15) and near(T.GEN_FUEL_PER_KWH * 78.4 * 0.1, 10, 1e-9),
    "user 2026-10-28: at the default GeneratorFuelConsumption 0.1, a Model Y 0 -> 100 % (78.4 kWh) burns one 10 L tank")
local mo, miso = charger(800, 800, { room = {} }, "minidoracat_tesla_01_10")
check(mo.kind == "MobileConnector" and mo.facing == "N", "sprite 10 is a north-facing Mobile Connector")
local mp = H.player({ name = "own", keys = { [77] = true }, x = 801, y = 801 })
local mv = car(10, 800.5 + 5.2, 800.5)
H.sent = {}
C.plug(mp, mv, miso)
check(H.sent[#H.sent].args.reason == "CABLE_SHORT" and B.part(mv):getModData().chg == nil, "5.2 tiles: beyond the 5-tile cable, refused")
mv.x = 800.5 + 4.8
H.sent = {}
mv.locked = true
C.plug(H.player({ name = "mal", x = 801, y = 801 }), mv, miso)
check(H.sent[#H.sent].args.reason == "CAR_LOCKED" and B.part(mv):getModData().chg == nil, "in reach, no key, car locked: refused CAR_LOCKED, nothing changes")
mv.locked = false
H.setHours(150)
C.plug(mp, mv, miso)
local mchg = B.part(mv):getModData().chg
check(mchg ~= nil and mchg.kind == "MobileConnector" and near(mchg.kw, 7.6, 1e-9) and mchg.src == "grid",
    "4.8 tiles indoors on the grid: plugged, chg.kw 7.6 (the card and the app read it)")
H.setHours(152)
C.settle(mo, H.hours())
check(near(B.kwh(B.part(mv)), 10 + 2 * 7.6, 1e-6), "2 h on the grid adds 15.2 kWh")
C.unplug(mp, mv)
-- outdoors, no generator: no power, no charge
local mo2, miso2 = charger(820, 800, {}, "minidoracat_tesla_01_8")
local mv2 = car(5, 822.5, 800.5)
H.setHours(160)
C.plug(H.player({ name = "own", keys = { [77] = true }, x = 821, y = 801 }), mv2, miso2)
H.setHours(165)
C.settle(mo2, H.hours())
local mchg2 = B.part(mv2):getModData().chg
check(mchg2.paused == "nopower" and mchg2.power == nil and B.kwh(B.part(mv2)) == 5, "outdoors without a generator: paused=nopower, no energy")
-- Mobile Connector power (decisions.md 2026-10-28): indoors on the building wiring like the Wall Connector; anywhere
-- else only a running generator up to genTiles (2, same floor, Chebyshev) away, plugged straight in
check(MC.genTiles == 2 and WC.genTiles == nil, "Mobile Connector plugs straight into a generator up to 2 tiles away; the Wall Connector never does")
local MRATE = 7.6 * T.fuelPerKwh()
local function mplug(x, y, o, h)
    local lo_, iso_, sq_ = charger(x, y, o, "minidoracat_tesla_01_9")
    local v_ = car(5, x + 2.5, y + 0.5)
    H.setHours(h)
    C.plug(H.player({ name = "own", keys = { [77] = true }, x = x + 1, y = y + 1 }), v_, iso_)
    return lo_, v_, sq_, B.part(v_):getModData().chg
end
-- outdoors inside a generator's power range (the square has electricity), generator 5 tiles away: no power
local mo3, mv3, msq3, mchg3 = mplug(840, 800, { elec = true }, 170)
local mgen = square(845, 800, 0)
mgen.gen = generator(10, true)
H.setHours(173)
C.settle(mo3, H.hours())
check(mchg3.paused == "nopower" and mchg3.power == nil and B.kwh(B.part(mv3)) == 5 and mgen.gen.fuel == 10,
    "outdoors in a generator's range but 5 tiles from it: no power, no charge, its fuel untouched")
check(not T.chargerPowered("MobileConnector", msq3) and T.chargerPowered("WallConnector", msq3),
    "the menu's power check agrees; a Wall Connector on that square would take the generator's range")
-- the generator moves next to it (Chebyshev 2, diagonal): plugged straight in, burns that generator's fuel
mgen.gen = nil
local mgen2 = square(842, 802, 0)
mgen2.gen = generator(10, true)
H.setHours(174)
C.settle(mo3, H.hours())
check(mchg3.src == "generator" and mchg3.power == "generator" and near(B.kwh(B.part(mv3)), 5 + 7.6, 1e-6),
    "generator 2 tiles away (diagonal): 1 h at 7.6 kW")
check(near(mgen2.gen.fuel, 10 - MRATE, 1e-9) and near(MRATE, 7.6 * T.GEN_FUEL_PER_KWH * 0.1, 1e-12),
    "that generator burned 7.6 x GEN_FUEL_PER_KWH x GeneratorFuelConsumption for the hour")
check(T.chargerPowered("MobileConnector", msq3), "the menu's power check sees the generator next to it")
mgen2.gen.on = false
local k3 = B.kwh(B.part(mv3))
H.setHours(175)
C.settle(mo3, H.hours())
check(B.kwh(B.part(mv3)) == k3 and mchg3.paused == "nopower" and mchg3.power == nil, "generator switched off: no charge, paused=nopower")
mgen2.gen.on, mgen2.gen.fuel = true, 0
H.setHours(176)
C.settle(mo3, H.hours())
check(B.kwh(B.part(mv3)) == k3 and mchg3.paused == "nopower", "generator out of fuel: no charge, paused=nopower")
mgen2.gen.fuel = 10
H.setHours(177)
C.settle(mo3, H.hours())
check(mchg3.src == "generator" and near(B.kwh(B.part(mv3)) - k3, 7.6, 1e-6), "refuelled: charges again on the next settle")
-- car unloaded for 4 h (nothing settles), loaded again: relink books the whole stretch on that generator
C.unschedule(mo3)
local f3, k3b = mgen2.gen.fuel, B.kwh(B.part(mv3))
H.setHours(181)
H.fire("OnSpawnVehicleEnd", mv3)
check(near(B.kwh(B.part(mv3)) - k3b, 4 * 7.6, 1e-6) and near(f3 - mgen2.gen.fuel, 4 * MRATE, 1e-9),
    "car loaded again after 4 h: 4 h of charge and 4 h of that generator's fuel")
-- 3 tiles away or another floor: not plugged in; the scan is a 5x5 on the charger's floor
local g3 = square(1003, 1000, 0)
g3.gen = generator(10, true)
local gUp = square(1001, 1000, 1)
gUp.gen = generator(10, true)
check(T.directGenerator("MobileConnector", 1000, 1000, 0) == nil, "3 tiles away or one floor up: not plugged in")
check(T.directGenerator("MobileConnector", 1001, 1000, 0) == g3.gen and T.directGenerator("WallConnector", 1001, 1000, 0) == nil,
    "2 tiles away: plugged in (Mobile Connector only)")
-- sandbox AllowExteriorGenerator off: vanilla's haveElectricity is false outdoors (IsoGridSquare.java:9697); a generator
-- right next to it still powers it
SandboxVars.AllowExteriorGenerator = false
local mo4, mv4, _, mchg4 = mplug(1100, 1000, { elec = false }, 200)
local g4 = square(1101, 1001, 0)
g4.gen = generator(10, true)
H.setHours(202)
C.settle(mo4, H.hours())
check(mchg4.src == "generator" and near(B.kwh(B.part(mv4)), 5 + 2 * 7.6, 1e-6) and near(g4.gen.fuel, 10 - 2 * MRATE, 1e-9),
    "AllowExteriorGenerator off, generator next to it outdoors: plugged straight in, charges and burns its fuel")
SandboxVars.AllowExteriorGenerator = nil
-- indoors without a room (a roofed player-built base): a generator's range powers it through the wiring, 10 tiles away
local mo5, mv5, _, mchg5 = mplug(1200, 1000, { outside = false, elec = true }, 210)
local g5 = square(1210, 1000, 0)
g5.gen = generator(10, true)
H.setHours(212)
C.settle(mo5, H.hours())
check(mchg5.src == "generator" and near(B.kwh(B.part(mv5)), 5 + 2 * 7.6, 1e-6) and near(g5.gen.fuel, 10 - 2 * MRATE, 1e-9),
    "indoors with generator power (no room, roof overhead): the generator 10 tiles away powers it, its fuel burns")
-- the roof comes off (outdoors now): the cached generator 10 tiles away no longer counts, its fuel stays
local sq5 = getCell():getGridSquare(1200, 1000, 0)
sq5.outside = true
local f5 = g5.gen.fuel
H.setHours(213)
C.settle(mo5, H.hours())
check(mchg5.paused == "nopower" and mchg5.power == nil and g5.gen.fuel == f5,
    "roof gone: the cached generator 10 tiles away no longer powers it, its fuel stays")
-- roofed without a room, grid up, no generator: no grid (vanilla's fridge rule needs a room; a player-built room is a
-- NoPower square, IsoGridSquare.java:11617-11633)
sq5.outside, sq5.elec = false, false
check(not T.gridReaches("MobileConnector", sq5) and not T.chargerPowered("MobileConnector", sq5),
    "roofed, no room, no generator: no grid and no power, as for a vanilla fridge")
-- just outside a house (fridge rule: a neighbour in a room): grid for the Wall Connector, not for the Mobile Connector
local edge = square(1300, 1000, 0)
square(1300, 999, 0, { room = {} })
check(T.gridReaches("WallConnector", edge) and not T.gridReaches("MobileConnector", edge),
    "outdoor square next to a room: the grid reaches a Wall Connector there, a Mobile Connector has to be inside")
-- on the wiring the fuel comes from a generator inside vanilla's circular range (IsoGenerator.isPoweringSquare), not
-- from one in the scan box's corner
local mo7, _, _, mchg7 = mplug(1500, 1000, { outside = false, elec = true }, 220)
local corner = square(1480, 980, 0) -- 20, 20: inside the 41 x 41 box, 28 tiles away
corner.gen = generator(10, true)
local g7 = square(1505, 1000, 0)
g7.gen = generator(10, true)
H.setHours(221)
C.settle(mo7, H.hours())
check(mchg7.src == "generator" and corner.gen.fuel == 10 and near(g7.gen.fuel, 10 - MRATE, 1e-9),
    "wired: the generator 5 tiles away pays, not the one in the box corner 28 tiles away")
-- indoors on the grid with a generator 2 tiles away: the grid first, the generator's fuel untouched
local mo8, mv8, _, mchg8 = mplug(1600, 1000, { room = {}, elec = true }, 230)
local g8 = square(1602, 1000, 0)
g8.gen = generator(10, true)
H.setHours(232)
C.settle(mo8, H.hours())
check(mchg8.src == "grid" and near(B.kwh(B.part(mv8)), 5 + 2 * 7.6, 1e-6) and g8.gen.fuel == 10,
    "indoors on the grid with a generator next to it: 2 h on the grid, no fuel burned")
-- indoors on the grid when the shut-off falls between two settles: grid to 336, then the wired generator
local mo6, mv6, _, mchg6 = mplug(1400, 1000, { room = {}, elec = true }, 335)
local g6 = square(1410, 1000, 0)
g6.gen = generator(10, true)
check(mchg6.src == "grid", "indoors on the grid before the shut-off")
H.setHours(338)
C.settle(mo6, H.hours())
check(near(B.kwh(B.part(mv6)), 5 + 3 * 7.6, 1e-6) and near(g6.gen.fuel, 10 - 2 * MRATE, 1e-9) and mchg6.power == "generator",
    "shut-off between settles: 1 h on the grid + 2 h on the wired generator, which pays only its 2 h")
-- sentry event between settles (powerUntil not told): after the shut-off only a generator it can use counts
local outGrid = { power = "grid", kind = "MobileConnector", x = 840, y = 800, z = 0 } -- outdoors, in range, generator 2 away
mgen2.gen.fuel = 10
check(C.powerUntil(outGrid, 338) == 338, "powerUntil, Mobile Connector with a generator 2 tiles away: free to now")
mgen2.gen.on = false
check(C.powerUntil(outGrid, 338) == 336, "powerUntil, Mobile Connector outdoors in a generator's range only: free to the 336 shut-off")

H.section("generator fuel (user 2026-10-29): sandbox multiplier, charging speed, the car's own loads")
-- every kWh a generator gives a Tesla burns GEN_FUEL_PER_KWH x GeneratorFuelConsumption x ChargeFuelMultiplier
SandboxVars.MinidoracatTesla = SandboxVars.MinidoracatTesla or {}
local TS = SandboxVars.MinidoracatTesla
local savedFuelMul, savedSpeedMul = TS.ChargeFuelMultiplier, TS.ChargeSpeedMultiplier
TS.ChargeFuelMultiplier = nil
check(T.chargeFuelMul() == 1 and near(T.fuelPerKwh() * 78.4, 10, 1e-9), "multiplier unset: 1, a full Model Y burns one 10 L tank")
TS.ChargeFuelMultiplier = 0.5
check(near(T.fuelPerKwh() * 78.4, 5, 1e-9), "ChargeFuelMultiplier 0.5: half a tank")
TS.ChargeFuelMultiplier = -1
local mulLow = T.chargeFuelMul()
TS.ChargeFuelMultiplier = 99
check(mulLow == 0 and T.chargeFuelMul() == 10, "the multiplier stays within the sandbox range 0-10")
-- twice as fast at half the fuel: the fuel follows the kWh, not the hours
TS.ChargeFuelMultiplier, TS.ChargeSpeedMultiplier = 0.5, 2
local fo, fv, _, fchg = mplug(1700, 1000, {}, 240)
local fg = square(1701, 1000, 0)
fg.gen = generator(10, true)
H.setHours(241)
C.settle(fo, H.hours())
local fk = B.kwh(B.part(fv)) - 5
check(fchg.src == "generator" and near(fk, 15.2, 1e-6) and near(10 - fg.gen.fuel, fk * T.GEN_FUEL_PER_KWH * 0.1 * 0.5, 1e-9),
    "speed x2, fuel x0.5: 1 h adds 15.2 kWh and burns 15.2 x GEN_FUEL_PER_KWH x GeneratorFuelConsumption x 0.5")
-- stopped (full is the same): no charge, but the car's own loads still run on the generator and cost its fuel
fchg.paused = "stopped"
local fpart = B.part(fv)
local fk0, ff0 = B.kwh(fpart), fg.gen.fuel
check(B.draw(fv, fpart, 1.5) == 0 and near(fchg.fed, 1.5, 1e-12) and B.kwh(fpart) == fk0,
    "a load on the generator-powered charger: nothing from the pack, 1.5 kWh waits in chg.fed")
fv.running = true
T.Update.Battery(fv, fpart, 10)
fv.running = false
local idle = T.spec(fv).idleKw * 10 / 60 * T.driveMul()
check(B.kwh(fpart) == fk0 and near(fchg.fed, 1.5 + idle, 1e-12), "motor standby in Park adds to chg.fed, not to the pack")
-- the standby is drive draw: it follows vanilla Gas Consumption (Core.lua T.driveMul), the loads above do not
local idle1, fed0 = T.spec(fv).idleKw * 10 / 60 / T.rangeMul(), fchg.fed
fv.running = true
SandboxVars.CarGasConsumption = 2
T.Update.Battery(fv, fpart, 10)
local fed2 = fchg.fed
SandboxVars.CarGasConsumption = 0
T.Update.Battery(fv, fpart, 10)
SandboxVars.CarGasConsumption = nil
fv.running = false
check(B.kwh(fpart) == fk0 and near(fed2 - fed0, 2 * idle1, 1e-12) and fchg.fed == fed2,
    "motor standby on the charger: x2 at Gas Consumption 2, nothing at 0")
local billed = fchg.fed
H.setHours(242)
C.settle(fo, H.hours())
check(B.kwh(fpart) == fk0 and fchg.fed == nil and near(ff0 - fg.gen.fuel, billed * T.fuelPerKwh(), 1e-12),
    "next settle: no charge (stopped); the loads burn their kWh x fuel per kWh and chg.fed is cleared")
-- motor standby at the defaults (Gas Consumption 1, ChargeFuelMultiplier 1, GeneratorFuelConsumption 0.1): an hour of
-- the recalibrated idleKw (0.376 kW, Core.lua DRIVE_SCALE) burns 0.048 L, a heater 0.19, Wall Connector charging 1.47
-- (charging.md "插著線時")
TS.ChargeFuelMultiplier = nil
local sf0 = fg.gen.fuel
fv.running = true
for _ = 1, 6 do T.Update.Battery(fv, fpart, 10) end
fv.running = false
H.setHours(242.25)
C.settle(fo, H.hours())
check(B.kwh(fpart) == fk0 and near(sf0 - fg.gen.fuel, 0.376 * T.GEN_FUEL_PER_KWH * 0.1, 1e-9)
    and near(sf0 - fg.gen.fuel, 0.048, 0.0005), string.format("an hour of motor standby on a generator: %.4f L at the defaults", sf0 - fg.gen.fuel))
TS.ChargeFuelMultiplier = 0.5
-- the generator gone by the next settle: the loads it ran are not billed to anyone
fg.gen.on = false
B.draw(fv, fpart, 1.5)
local ff1 = fg.gen.fuel
H.setHours(242.5)
C.settle(fo, H.hours())
check(fchg.fed == nil and fg.gen.fuel == ff1 and fchg.power == nil and B.kwh(fpart) == fk0,
    "generator off by the next settle: its loads go unbilled, chg.fed cleared, the charger has no power now")
fg.gen.on = true
-- on the grid the same loads are free
local _, gv, _, gchg = mplug(1720, 1000, { room = {} }, 243)
B.draw(gv, B.part(gv), 1.5)
check(gchg.power == "grid" and gchg.fed == nil, "a load on grid power: nothing to bill")
-- multiplier 0: the generator charges and runs the loads without burning fuel
TS.ChargeFuelMultiplier = 0
fchg.paused = nil
H.setHours(243)
C.settle(fo, H.hours()) -- the generator is back on: power again
local fk2, ff2 = B.kwh(fpart), fg.gen.fuel
B.draw(fv, fpart, 1.5)
H.setHours(244)
C.settle(fo, H.hours())
check(near(B.kwh(fpart) - fk2, 15.2, 1e-6) and fg.gen.fuel == ff2 and fchg.fed == nil,
    "ChargeFuelMultiplier 0: 1 h of charge and a load, the generator's fuel untouched")
TS.ChargeFuelMultiplier, TS.ChargeSpeedMultiplier = savedFuelMul, savedSpeedMul

H.section("one charger a square")
local function placeSq(...)
    local list = {}
    for _, n in ipairs({ ... }) do
        list[#list + 1] = { getSprite = function() return { getName = function() return n end } end }
    end
    return { getObjects = function() return { size = function() return #list end, get = function(_, i) return list[i + 1] end } end }
end
local function props(sprite, free) return setmetatable({ spriteName = sprite, free = free }, { __index = ISMoveableSpriteProps }) end
local mcS, wcS = "minidoracat_tesla_01_8", "minidoracat_tesla_01_0"
check(props(mcS):canPlaceMoveableInternal(nil, placeSq("floors_01_0")) == true, "Mobile Connector on a free floor: vanilla decides (true)")
check(props(mcS, false):canPlaceMoveableInternal(nil, placeSq()) == false, "vanilla says no: still no")
check(props(mcS):canPlaceMoveableInternal(nil, placeSq("floors_01_0", mcS)) == false, "second Mobile Connector on the same square: refused")
check(props(mcS):canPlaceMoveableInternal(nil, placeSq(wcS)) == false
    and props(wcS):canPlaceMoveableInternal(nil, placeSq("minidoracat_tesla_01_11")) == false,
    "Wall Connector and Mobile Connector never share a square, either order")
check(props("furniture_seating_01_0"):canPlaceMoveableInternal(nil, placeSq(mcS)) == true, "other furniture next to a charger: untouched")

H.section("mobile connector loot")
ProceduralDistributions = { list = {
    CarSupplyBatteries = { items = { "CarBattery3", 6, "CarBatteryCharger", 10 } },
    GasStoreEmergency = { items = { "CarBatteryCharger", 6 }, junk = { items = { "CarBatteryCharger", 1 } } },
    KitchenCutlery = { items = { "Fork", 10 } },
} }
H.fire("OnPostDistributionMerge")
H.fire("OnPostDistributionMerge") -- a reload must not stack our pairs
local L = ProceduralDistributions.list
local function weightOf(items)
    local n, w = 0, nil
    for i = 1, #items - 1, 2 do if items[i] == MC.item then n, w = n + 1, items[i + 1] end end
    return n, w
end
local n1, w1 = weightOf(L.CarSupplyBatteries.items)
local n2, w2 = weightOf(L.GasStoreEmergency.items)
local n3, w3 = weightOf(L.GasStoreEmergency.junk.items)
check(n1 == 1 and w1 == 5 and n2 == 1 and w2 == 3 and n3 == 1 and w3 == 0.5,
    "every list with the car battery charger gets one Mobile Connector at half its weight, also after a reload")
check(weightOf(L.KitchenCutlery.items) == 0, "lists without the car battery charger stay as they are")
ProceduralDistributions = nil

H.section("mobile connector in a new car's trunk")
local function withTrunk(v)
    local box = { items = {} }
    function box:AddItem(t) self.items[#self.items + 1] = t end
    v.parts.TruckBed = { getItemContainer = function() return box end }
    return box
end
local pct0 = T.MOBILE_IN_TRUNK_PCT
check(pct0 == 25, "default chance: 25 % of new cars")
for _, script in ipairs({ "Base.MinidoracatTesla_ModelY", "Base.MinidoracatTesla_Model3" }) do
    T.MOBILE_IN_TRUNK_PCT = 100
    local nv = H.vehicle({ script = script })
    local box = withTrunk(nv)
    T.Create.Motor(nv, nv:getPartById("Engine"))
    check(#box.items == 1 and box.items[1] == MC.item, script .. ": new car at 100 %: one Mobile Connector in the trunk")
    nv._class = "BaseVehicle"
    H.fire("OnSpawnVehicleEnd", nv) -- every later load fires this, never the part create
    check(#box.items == 1, script .. ": loading the car again adds nothing")
    T.MOBILE_IN_TRUNK_PCT = 0
    local nv0 = H.vehicle({ script = script })
    local box0 = withTrunk(nv0)
    T.Create.Motor(nv0, nv0:getPartById("Engine"))
    check(#box0.items == 0, script .. ": at 0 %: an empty trunk")
end
T.MOBILE_IN_TRUNK_PCT = pct0

H.section("keyless rules (user 2026-10-28): plug, unplug, charge card, pick up and rotate the charger")
-- No VehicleManager: a key, a hotwired car (both on a locked car) or an unlocked car -> allowed; a locked car without a
-- key -> CAR_LOCKED everywhere. VehicleManager present: only its FUEL right, locked or not.
local MCS = "minidoracat_tesla_01_8"
local klo, kiso, ksq = charger(900, 900, { room = {} }, MCS)
local kv = car(20, 900.5 + 2, 900.5)
local kOwner = H.player({ name = "own", keys = { [77] = true }, x = 901, y = 901 })
local mal = H.player({ name = "mal", x = 901, y = 901 })
local function kchg() return B.part(kv):getModData().chg end
local function lastDeny() for i = #H.sent, 1, -1 do if H.sent[i].command == "deny" then return H.sent[i].args.reason end end end
-- vanilla's ISMoveablesAction on the charger square through Chargers.lua's wrap; done = vanilla moved it
local function move(mode, sprite)
    local a = setmetatable({ mode = mode, character = mal, square = ksq, origSpriteName = sprite,
        moveProps = { spriteName = sprite } }, { __index = ISMoveablesAction })
    return a:complete(), a.done == 1
end
local function matrix(label, allowed, deny)
    if not kchg() then C.plug(kOwner, kv, kiso) end
    H.sent = {}
    H.fire("OnClientCommand", "MinidoracatTesla", "chargeTarget", mal, { vid = kv:getId(), pct = 60 })
    check((kchg().target == 60) == allowed and (allowed or lastDeny() == deny), label .. ": charge card target %")
    kchg().target = 90
    H.sent = {}
    H.fire("OnClientCommand", "MinidoracatTesla", "chargeStop", mal, { vid = kv:getId() })
    check((kchg().paused == "stopped") == allowed and (allowed or lastDeny() == deny), label .. ": charge card stop")
    kchg().paused = nil
    for _, mode in ipairs({ "pickup", "rotate" }) do
        H.sent = {}
        local r, done = move(mode, MCS)
        check(r == allowed and done == allowed and (allowed or lastDeny() == deny), label .. ": " .. mode .. " the plugged Mobile Connector")
    end
    H.sent = {}
    C.unplug(mal, kv)
    check((kchg() == nil) == allowed and (allowed or lastDeny() == deny), label .. ": unplug")
    if not kchg() then
        C.plug(mal, kv, kiso)
        check(kchg() ~= nil, label .. ": plug back in")
    else
        C.unplug(kOwner, kv)
        H.sent = {}
        C.plug(mal, kv, kiso)
        check(kchg() == nil and lastDeny() == deny, label .. ": plug")
    end
end
kv.locked = true
mal.keys[77] = true
matrix("no VehicleManager, the key, car locked", true)
mal.keys[77] = nil
kv.hotwired = true
check(select(2, T.mayUseCable(mal, kv)) == "HOTWIRED", "no VehicleManager: a hotwired car counts as the key in the ignition (HOTWIRED)")
matrix("no VehicleManager, hotwired, car locked", true)
kv.hotwired, kv.locked = false, false
matrix("no VehicleManager, no key, car unlocked", true)
kv.locked = true
matrix("no VehicleManager, no key, car locked", false, "CAR_LOCKED")
check(move("pickup", "some_other_tile") == true, "a locked car's charger square: other moveables are not this rule's business")
C.unplug(kOwner, kv)
check(move("pickup", MCS) == true, "nothing plugged in: anyone picks the Mobile Connector up (vanilla)")
-- the charger names a car that is not here (unloaded, or its id handed to another car): the server refuses the move
-- (NOT_LOADED); a reused id neither counts as the charger taken (relink) nor busy (plug)
C.plug(kOwner, kv, kiso)
local kvid = klo.vid
klo.vid = 424242 -- the plugged car unloaded: settle keeps vid until relink
H.sent = {}
check(move("pickup", MCS) == false and lastDeny() == "NOT_LOADED", "plugged car not loaded: pick up refused on the server (NOT_LOADED)")
local reuse = car(20, 950.5, 950.5)
klo.vid = reuse:getId()
H.sent = {}
check(move("rotate", MCS) == false and lastDeny() == "NOT_LOADED", "the id now names another car (no cable here): still refused")
C.relink(kv)
check(klo.vid == kvid and kchg() ~= nil, "the real car loads again: relinked, the car holding the old id does not count as taken")
C.unplug(kOwner, kv)
klo.vid = reuse:getId()
C.plug(kOwner, kv, kiso)
check(kchg() ~= nil and klo.vid == kvid, "a reused id on the charger: not busy, plugging in takes it over")
C.unplug(kOwner, kv)
-- settle and charger removal with the id handed to a Tesla plugged in elsewhere: that car is left alone
local ylo = charger(950, 950, { room = {} }, MCS)
C.start(ylo, reuse)
local function rchg() return B.part(reuse):getModData().chg end
klo.vid = reuse:getId() -- our car unloaded, its id now the other Tesla's
C.settle(klo, T.hours())
check(rchg() ~= nil and rchg().x == 950 and not klo.vid, "settle: the id names a car plugged in elsewhere -> forgotten, that car stays plugged")
klo.vid = reuse:getId()
C.onChargerRemoved(klo)
check(rchg() ~= nil and rchg().x == 950, "charger removed: the car holding its old id (plugged in elsewhere) stays plugged")
klo.vid = false
C.stop(ylo, reuse, "unplug")
-- the charger's owner (main agent 2026-10-28): its placer, or the owner / a member of the safehouse its square is in,
-- may unplug, stop on the card, pick up and rotate whatever is plugged in, locked or not; not plug in, not the target
local function act(mode, who, onDone)
    local a = setmetatable({ mode = mode, character = who, square = ksq, origSpriteName = MCS,
        moveProps = { spriteName = MCS }, onComplete = onDone }, { __index = ISMoveablesAction })
    return a:complete()
end
SYS.objs[key(900, 900, 0)] = nil
act("place", mal, function() SYS.objs[key(900, 900, 0)] = klo end) -- vanilla's place: OnObjectAdded makes the object
check(klo.owner == "mal", "placing a charger records its placer (T.account)")
kv.locked = true
C.plug(kOwner, kv, kiso)
check(not T.mayUseCable(mal, kv) and select(2, T.mayUnplug(mal, kv)) == "CHARGER_OWNER",
    "the charger's owner, someone else's locked car: not the cable rule, but T.mayUnplug says CHARGER_OWNER")
H.sent = {}
H.fire("OnClientCommand", "MinidoracatTesla", "chargeTarget", mal, { vid = kv:getId(), pct = 60 })
check(kchg().target ~= 60 and lastDeny() == "CAR_LOCKED", "the charger's owner: the target % stays the cable rule (CAR_LOCKED)")
H.fire("OnClientCommand", "MinidoracatTesla", "chargeStop", mal, { vid = kv:getId() })
check(kchg().paused == "stopped", "the charger's owner stops someone else's locked car on the card")
check(move("pickup", MCS) == true and move("rotate", MCS) == true, "the charger's owner may pick up and rotate it with that car plugged in")
local fresh
act("rotate", mal, function()
    fresh = SMinidoracatTeslaCharger:new(SYS, { gx_ = 900, gy_ = 900, gz_ = 0 })
    fresh:stateFromIsoObject(kiso)
    SYS.objs[key(900, 900, 0)] = fresh
end)
check(fresh and fresh.owner == "mal", "rotating (pick up + place: a new charger object) keeps the owner")
SYS.objs[key(900, 900, 0)] = klo
local function rotateBy(who)
    local n = SMinidoracatTeslaCharger:new(SYS, { gx_ = 900, gy_ = 900, gz_ = 0 })
    n:stateFromIsoObject(kiso)
    act("rotate", who, function() SYS.objs[key(900, 900, 0)] = n end)
    SYS.objs[key(900, 900, 0)] = klo
    return n
end
check(rotateBy(kOwner).owner == "mal", "someone else turning the charger (the car's key holder): the owner stays mal, not him")
klo.owner = nil
check(rotateBy(kOwner).owner == nil, "turning a charger with no owner on record does not make the turner its owner")
klo.owner = "mal"
act("place", kOwner, function() end) -- vanilla placed nothing new on this square (the one-charger-a-square guard)
check(klo.owner == "mal", "a place on a square whose charger object stays the same leaves its owner alone")
C.unplug(mal, kv)
check(kchg() == nil, "the charger's owner unplugs someone else's locked car")
H.sent = {}
C.plug(mal, kv, kiso)
check(kchg() == nil and lastDeny() == "CAR_LOCKED", "the charger's owner may not plug in a car he has no right to")
C.plug(kOwner, kv, kiso)
local guest = H.player({ name = "guest", x = 901, y = 901 })
SafeHouse = { getSafeHouse = function(sq) return sq == ksq and { playerAllowed = function(_, n) return n == "guest" end } or nil end }
check(select(2, T.mayUnplug(guest, kv)) == "CHARGER_OWNER", "a member of the safehouse the charger stands in counts as its owner")
SafeHouse = nil
check(T.mayUnplug(guest, kv) == false, "no safehouse there: a stranger does not")
klo.owner = nil
check(T.mayUnplug(mal, kv) == false and move("pickup", MCS) == false, "a charger placed before the owner record: the cable rule alone")
klo.owner = "mal"
MinidoracatVehicleManagerAPI = { canUse = function() return false, "NOT_AUTHORIZED" end }
check(select(2, T.mayUnplug(mal, kv)) == "CHARGER_OWNER", "VehicleManager says no: the charger's owner still unplugs")
MinidoracatVehicleManagerAPI = nil
klo.owner = nil
-- unplug is not a remote: near the car or near the charger (queueUnplug walks to the charger); DistTo is Manhattan
local far = H.player({ name = "far", keys = { [77] = true }, x = 930, y = 930 })
H.sent = {}
C.unplug(far, kv)
check(kchg() ~= nil and lastDeny() == "TOO_FAR", "unplug far from both the car and the charger: TOO_FAR")
local kx = kv.x
kv.x = 912 -- the car's centre past T.NEAR (Manhattan) from someone standing at the charger
H.sent = {}
C.unplug(H.player({ name = "upstairs", keys = { [77] = true }, x = 899, y = 899, z = 1 }), kv)
check(kchg() ~= nil and lastDeny() == "TOO_FAR", "unplug from the floor above the charger, the car past T.NEAR: TOO_FAR")
C.unplug(H.player({ name = "side", keys = { [77] = true }, x = 899, y = 899 }), kv)
check(kchg() == nil, "unplug standing at the charger, the car's centre past T.NEAR: allowed")
-- plug the same way (queuePlug walks to the charger): the car aslant at the cable's end, the player on the far side
local ky = kv.y
kv.x, kv.y = 904, 904 -- port 4.95 from the charger's centre (cable 5), 16 (Manhattan) from the player below
check(T.cableReaches(klo.kind, 900, 900, 0, kv), "(the aslant car is in the cable's reach)")
H.sent = {}
C.plug(H.player({ name = "far", keys = { [77] = true }, x = 930, y = 930 }), kv, kiso)
check(kchg() == nil and lastDeny() == "TOO_FAR", "plug far from both the car and the charger: TOO_FAR")
H.sent = {}
C.plug(H.player({ name = "upstairs", keys = { [77] = true }, x = 896, y = 896, z = 1 }), kv, kiso)
check(kchg() == nil and lastDeny() == "TOO_FAR", "plug from the floor above the charger, the car past T.NEAR: TOO_FAR")
C.plug(H.player({ name = "side", keys = { [77] = true }, x = 896, y = 896 }), kv, kiso)
check(kchg() ~= nil, "plug standing at the charger's far side, the aslant car's centre past T.NEAR: allowed")
C.unplug(kOwner, kv)
kv.x, kv.y = kx, ky
MinidoracatVehicleManagerAPI = { canUse = function(p, veh, perm) return perm == "FUEL" and p == kOwner, p == kOwner and "OWNER" or "NOT_AUTHORIZED" end }
for _, locked in ipairs({ true, false }) do
    kv.locked, mal.keys[77], kv.hotwired = locked, true, true
    matrix("VehicleManager says no (key and hotwired too), car " .. (locked and "locked" or "unlocked"), false, "NOT_OWNER")
end
for _, r in ipairs({ "RENT_LOCKED", "FACTION_PAUSED", "QUARANTINED" }) do
    MinidoracatVehicleManagerAPI.canUse = function() return false, r end
    check(select(2, T.mayUseCable(kOwner, kv)) == r, "VehicleManager's " .. r .. " keeps its own reason (T.VM_REASONS)")
end
MinidoracatVehicleManagerAPI.canUse = function(p, veh, perm) return perm == "FUEL" and p == kOwner, p == kOwner and "OWNER" or "NOT_AUTHORIZED" end
mal.keys[77], kv.hotwired, kv.locked = nil, false, false
C.unplug(kOwner, kv)
check(kchg() == nil, "VehicleManager: the car's FUEL holder unplugs")
MinidoracatVehicleManagerAPI = nil

H.section("taking the pack out while plugged in")
local plo, piso = charger(960, 960, { room = {} })
local pv = car(20, 960.5 + 2, 960.5)
local pp = H.player({ name = "mech", keys = { [77] = true }, x = 961, y = 961 })
local function pchg() return B.part(pv):getModData().chg end
local function pull(fail)
    local a = { vehicle = pv, part = B.part(pv), character = pp, fail = fail }
    ISUninstallVehiclePart.complete(a)
    return a
end
H.setHours(100) -- grid power (the first section's clock)
C.plug(pp, pv, piso)
check(pchg() ~= nil and plo.vid == pv:getId(), "(plugged in)")
H.setHours(H.hours() + 1)
pull(true)
check(pchg() ~= nil and plo.vid == pv:getId(), "the pack stays in (failed uninstall): still plugged in")
local c0 = B.kwh(B.part(pv))
H.setHours(H.hours() + 1)
local a = pull()
check(a.taken ~= nil and pchg() == nil and plo.vid == false, "the pack out: the car's cable record cleared, the charger told (vid false)")
check(near(a.content, c0 + 11.5, 1e-6), "the hour up to then (11.5 kWh) is booked before the pack takes the part's content")
B.part(pv).item = a.taken -- installed again
-- (the Park hold, Core.lua CheckOperate.Battery, is `chg ~= nil`: cleared above. Its client half T.onPluggedDrive is
-- not loaded here, so it is not asked)
C.plug(pp, pv, piso)
check(pchg() ~= nil and plo.vid == pv:getId(), "the pack back in: it plugs into the same charger again")
local other = { item = {}, md = {} } -- another part of the same car (a door, the 12V)
function other:getInventoryItem() return self.item end
function other:getContainerContentAmount() return 0 end
function other:getModData() return self.md end
ISUninstallVehiclePart.complete({ vehicle = pv, part = other, character = pp })
check(other.item == nil and pchg() ~= nil and plo.vid == pv:getId(), "another part taken off: the cable stays as it was")
-- pv's record is stale: its id went to qv, really plugged into plo (VehicleIDMap reuse); taking pv's pack out must not
-- touch qv or plo
local qv = car(30, 960.5 + 2, 960.5)
B.part(qv):getModData().chg = { x = 960, y = 960, z = 0, kind = plo.kind, last = H.hours(), added = 0, target = 90 }
plo.vid = qv:getId()
local q = pull()
check(q.taken ~= nil and pchg() == nil and plo.vid == qv:getId() and B.part(qv):getModData().chg ~= nil,
    "the pack out of a car whose charger now holds another car: only its own record cleared, the other car stays plugged")
B.part(pv).item = q.taken
B.part(qv):getModData().chg = nil
C.plug(pp, pv, piso)
check(pchg() ~= nil and plo.vid == pv:getId(), "(plugged in again)")
local sentryBefore = T.Sentry
T.Sentry = { settle = function() error("sentry boom") end } -- the sentry booking throws while unplugging
local e = pull()
check(e.taken ~= nil and pchg() == nil and plo.vid == false, "the sentry booking throws: the record and the charger's vid still go")
T.Sentry = sentryBefore
B.part(pv).item = e.taken
C.plug(pp, pv, piso)
check(pchg() ~= nil and plo.vid == pv:getId(), "(plugged in again)")
local tx = pv.transmitPartModData
pv.transmitPartModData = function() error("transmit boom") end -- the part sync throws after the record is cleared
local f = pull()
pv.transmitPartModData = tx
check(f.taken ~= nil and pchg() == nil and plo.vid == false, "the part sync throws: the record is gone and the charger is still told")
B.part(pv).item = f.taken
C.plug(pp, pv, piso)
check(pchg() ~= nil and plo.vid == pv:getId(), "(plugged in again)")
B.part(pv).item = nil -- gone some other way (another mod, debug): the next settle unplugs it
C.settle(plo, H.hours())
check(pchg() == nil and plo.vid == false, "settle with the pack gone: the car's record cleared, the charger forgets it")
B.part(pv).item = a.taken
ISUninstallVehiclePart = uninstallBefore
