-- Cybertruck Powershare (plan 4: hidden vanilla generator) and the bed outlet (4.4): the state machine, fuel <-> kWh
-- booking, conservation when another Tesla charges, the 11.5 / 9.6 kW caps, the discharge limit, the 30-day fuel cap,
-- unplugging, another generator, GFC 0, the switches' rules, the tailgate.
local check, near = H.check, H.near
H.side(false, true)

local saved = { getCell = getCell, getWorld = getWorld, instanceItem = instanceItem, IsoGenerator = IsoGenerator,
    getOnlinePlayers = getOnlinePlayers, getSpecificPlayer = getSpecificPlayer, getSandboxOptions = getSandboxOptions }

local T, B, C -- set once Powershare is loaded (the fakes below read the clock)

-- ---- world fakes: squares (room = indoors), generators (vanilla IsoGenerator's surface), the cell ----
local squares, removed = {}, {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function list(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end
local gens = {} -- every running generator (haveElectricity: in one's range)
local function square(x, y, z, o)
    o = o or {}
    local sq = { x = x, y = y, z = z or 0, room = o.room, special = {}, building = o.room and {} or nil }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getRoom() return self.room end
    function sq:getBuilding() return self.building end
    function sq:isOutside() return self.room == nil end
    function sq:isNoPower() return false end
    function sq:hasGridPower() return T.hours() < C.gridOffHour() end
    function sq:haveElectricity()
        for _, g in ipairs(gens) do
            local dx, dy = g.sq.x - self.x, g.sq.y - self.y
            if g.on and dx * dx + dy * dy <= 400 then return true end
        end
        return false
    end
    function sq:getGenerator() return self.special[1] end
    function sq:getSpecialObjects() return list(self.special) end
    function sq:getAdjacentSquare() return nil end
    function sq:getVehicleContainer() return nil end
    function sq:transmitRemoveItemFromSquare(obj)
        for i = #self.special, 1, -1 do if self.special[i] == obj then table.remove(self.special, i) end end
        for i = #gens, 1, -1 do if gens[i] == obj then table.remove(gens, i) end end
        removed[#removed + 1] = obj
    end
    squares[key(x, y, z or 0)] = sq
    return sq
end
local function sqAt(x, y, z) return squares[key(x, y, z)] end
local cell = { getGridSquare = function(_, x, y, z) return sqAt(x, y, z) end }
getCell = function() return cell end
getWorld = function() return { getCell = function() return cell end } end
getSandboxOptions = function() return { getTimeSinceApo = function() return 1 end } end
local LOAD = 0.02 -- the house's vanilla load units (IsoGenerator base 0.02; tests raise it)
local function newGen(sq, sprite)
    local g = { sq = sq, fuel = 0, on = false, cond = 100, sprite = sprite, _class = "IsoGenerator", syncs = 0 }
    function g:getSquare() return self.sq end
    function g:getSprite() local n = self.sprite; return { getName = function() return n end } end
    function g:isActivated() return self.on end
    function g:setActivated(b) self.on = b end
    function g:getFuel() return self.fuel end
    function g:setFuel(f) self.fuel = math.max(0, math.min(f, 10)); self.syncs = self.syncs + 1 end
    function g:getTotalPowerUsing() return LOAD * (SandboxVars.GeneratorFuelConsumption or 0.1) end -- L/h (:732-734)
    function g:getCondition() return self.cond end
    function g:setCondition(c) self.cond = c end
    function g:setConnected(b) self.connected = b end
    function g:isConnected() return self.connected == true end
    sq.special[#sq.special + 1] = g
    gens[#gens + 1] = g
    return g
end
IsoGenerator = { new = function(item, _, sq) return newGen(sq, item.sprite) end }
instanceItem = function(t)
    if t ~= "Base.MinidoracatTesla_Powershare" then return nil end
    local md = {}
    return { sprite = "minidoracat_tesla_01_12", getModData = function() return md end }
end
local online = {}
getOnlinePlayers = function() return list(online) end
getSpecificPlayer = function() return nil end

local ticks0, mins0 = H.count("OnTick"), H.count("EveryOneMinute")
require "MinidoracatTesla/Powershare"
T, B, C = MinidoracatTesla, MinidoracatTesla.Battery, MinidoracatTesla.Charge
local PS = T.Powershare
local SYS = SMinidoracatTeslaChargerSystem.instance
for _, o in pairs(SYS.objs) do C.unschedule(o) end -- test_charging's chargers: not in this world
SYS.objs = {}
SandboxVars.ElecShutModifier = 14 -- the grid ends at world hour 336 (Charging.lua C.gridOffHour)
SandboxVars.GeneratorFuelConsumption = 0.1
local r0 = T.GEN_FUEL_PER_KWH * 0.1

local function charger(x, y, sprite, o)
    local sq = sqAt(x, y, 0) or square(x, y, 0, o)
    local iso = { sq = sq, sprite = sprite }
    function iso:getSquare() return self.sq end
    function iso:getSprite() local n = self.sprite; return { getName = function() return n end } end
    local lo = SMinidoracatTeslaCharger:new(SYS, { gx_ = x, gy_ = y, gz_ = 0 })
    lo:stateFromIsoObject(iso)
    lo.iso = iso
    SYS.objs[key(x, y, 0)] = lo
    return lo, iso
end
local WALL, MOBILE = "minidoracat_tesla_01_0", "minidoracat_tesla_01_8"

-- a car at (x, y) (charge port there too); Cybertruck: the 123 kWh pack, a tailgate, the bed area 2 tiles behind
local nextKey = 500
local function car(script, kwh, x, y)
    local ct = script == "Base.MinidoracatTesla_Cybertruck"
    nextKey = nextKey + 1
    local v = H.vehicle({ script = script, x = x, y = y, pack = ct and "Base.MinidoracatTesla_CybertruckBattery" or nil })
    v._class = "BaseVehicle"
    v.keyId = nextKey
    local part = v.parts.GasTank
    if ct then part.item.maxCap = 123 end
    part:setContainerContentAmount(kwh)
    function v:getAttachmentWorldPos(_, out) out._x, out._y = self.x, self.y; return out end
    function v:getSquare() return sqAt(math.floor(self.x), math.floor(self.y), 0) or square(math.floor(self.x), math.floor(self.y), 0) end
    function v:getAreaCenter(area)
        if area ~= "TruckBed" then return nil end
        local cx, cy = self.x, self.y + 3
        return { getX = function() return cx end, getY = function() return cy end }
    end
    function v:getScript() return { getCarModelName = function() return script:sub(6) end, getName = function() return script:sub(6) end } end
    function v:areAllDoorsLocked() return false end
    function v:transmitPartDoor() end
    v.gateOpen = false
    local gate = { id = "TrunkDoor", item = {}, md = {} }
    function gate:getId() return self.id end
    function gate:getInventoryItem() return self.item end
    function gate:getVehicle() return v end
    function gate:getDoor()
        return { isOpen = function() return v.gateOpen end, setOpen = function(_, b) v.gateOpen = b end,
            isLocked = function() return false end, isLockBroken = function() return false end }
    end
    v.parts.TrunkDoor = gate
    return v
end
local CT, MY = "Base.MinidoracatTesla_Cybertruck", "Base.MinidoracatTesla_ModelY"
local owner = H.player({ name = "own", x = 300, y = 300 })
local function keyFor(v) owner.keys[v:getKeyId()] = true end
local function plug(v, lo) owner.x, owner.y = lo.x, lo.y; C.plug(owner, v, lo.iso) end -- standing at the charger
local function unplug(v) owner.x, owner.y = v.x, v.y; C.unplug(owner, v) end
local function md(v) return B.part(v):getModData() end
local function gen(v) local ps = md(v).ps; return ps and ps.gx and sqAt(ps.gx, ps.gy, ps.gz):getGenerator() end
local floorKwh = 123 * 0.2

H.section("Powershare: off -> armed on the grid -> backup at the shut-off (plan 4 state machine)")
H.setHours(335)
local wo = charger(300, 300, WALL, { room = {} })
local ct = car(CT, 50, 302.5, 302.5)
keyFor(ct)
plug(ct, wo)
check(T.psState(B.part(ct)) == "off" and md(ct).chg.power == "grid", "plugged on the grid, Powershare off")
check(PS.set(owner, ct, "ps", true) == nil and T.psState(B.part(ct)) == "armed" and md(ct).ps.by == "own",
    "switched on: armed (the grid is up), the owner recorded")
check(#gens == 0, "armed: no generator in the world")
local ctBefore = B.kwh(B.part(ct))
H.setHours(336.5)
C.settle(wo, H.hours())
local g = gen(ct)
check(T.psState(B.part(ct)) == "backup" and g ~= nil and g.on and g.connected, "past the shut-off: backup, a running generator")
check(g and g.sq.x == 302 and g.sq.y == 302 and T.isPowershare(g), "on the car's (outdoor) square, our sprite")
check(md(ct).chg.paused == "nopower" and md(ct).chg.power == nil, "its own charging pauses: it never charges itself")
local avail = B.kwh(B.part(ct)) - floorKwh
check(near(g.fuel, math.min(10, avail * r0, 0.02 * 0.1 * 720), 1e-6) and near(md(ct).ps.fuelSet, g.fuel, 1e-9),
    "fuel = min(10 L, kWh above the limit x r0, 720 h of the load): " .. string.format("%.3f", g.fuel))
check(near(B.kwh(B.part(ct)), ctBefore + 11.5, 1e-6), "the grid hour before the shut-off charged it (11.5), the half hour after nothing")

H.section("Powershare: the house's use is booked by the server's clock x load, never the generator's fuel")
local HOUSE = 0.02 * 0.1 / r0 -- kWh an hour at the base load (0.0157)
local k0 = B.kwh(B.part(ct))
g.fuel = 0 -- a client wrote it (SyncIsoObject: GameServer.java:2969-2980, IsoGenerator.java:607-614)
H.setHours(337)
C.settle(wo, H.hours())
check(near(k0 - B.kwh(B.part(ct)), 0.5 * HOUSE, 1e-6),
    string.format("a client set the fuel to 0: 0.5 h x load booked (%.4f kWh), not the 1.44 L it was given", 0.5 * HOUSE))
check(near(g.fuel, md(ct).ps.fuelSet, 1e-9) and g.fuel > 0, "filled again")
k0 = B.kwh(B.part(ct))
g.fuel, g.connected, g.cond, g.on = 10, false, 5, false -- a client: full tank, unplugged, worn, off
H.setHours(337.5)
C.settle(wo, H.hours())
check(near(k0 - B.kwh(B.part(ct)), 0.5 * HOUSE, 1e-6), "a client set it to 10 L: still 0.5 h x load, nothing given back")
check(g.connected and g.on and g.cond == 100 and near(g.fuel, md(ct).ps.fuelSet, 1e-9),
    "the settle puts back connected, activated, condition and its own fuel")
H.section("Powershare: vanilla's take / plug / smash on ours are refused on the server")
local thief = H.player({ name = "mal2", x = 302, y = 302 })
local function act(cls, field, obj) local a = setmetatable({ character = thief, [field] = obj }, { __index = cls }); return a:complete(), a.done end
local r, done = act(ISTakeGenerator, "generator", g)
check(r == false and not done, "ISTakeGenerator on ours: refused, no hidden item handed out")
r, done = act(ISPlugGenerator, "generator", g)
check(r == false and not done, "ISPlugGenerator (unplug) on ours: refused")
r, done = act(ISDestroyStuffAction, "item", g)
check(r == false and not done and gen(ct) == g, "ISDestroyStuffAction (sledgehammer) on ours: refused, still there")
local plain = newGen(square(290, 290, 0), "appliances_misc_01_0")
r, done = act(ISTakeGenerator, "generator", plain)
check(r == true and done, "a vanilla generator: vanilla's action as usual")
for i = #gens, 1, -1 do if gens[i] == plain then table.remove(gens, i) end end
k0 = B.kwh(B.part(ct))
g.sq:transmitRemoveItemFromSquare(g) -- gone some other way (burnt down)
H.setHours(338)
C.settle(wo, H.hours())
check(near(B.kwh(B.part(ct)), k0, 1e-9), "its generator gone: nothing more booked for it")
g = gen(ct)
check(g ~= nil and T.psState(B.part(ct)) == "backup", "a new one in its place")

H.section("Powershare: another Tesla charges from it, kWh for kWh, 11.5 kW at most together")
local w2 = charger(310, 300, WALL, { room = {} })
local my = car(MY, 20, 311.5, 302.5)
keyFor(my)
H.sent = {}
plug(my, w2)
check(md(my).chg.src == "powershare" and near(md(my).chg.kw, 11.5, 1e-9), "Model Y on a Wall Connector in range: powershare, 11.5 kW")
local ctK, myK = B.kwh(B.part(ct)), B.kwh(B.part(my))
H.setHours(339)
C.settle(w2, H.hours())
local gotMy, lostCt = B.kwh(B.part(my)) - myK, ctK - B.kwh(B.part(ct))
check(near(gotMy, 11.5, 1e-6) and near(lostCt, 11.5 + HOUSE, 1e-6),
    string.format("1 h: Model Y +%.3f, Cybertruck -%.3f (and the house's hour)", gotMy, lostCt))
local m3 = car("Base.MinidoracatTesla_Model3", 20, 321.5, 302.5)
keyFor(m3)
local w3 = charger(320, 300, MOBILE, { room = {} })
plug(m3, w3)
check(md(m3).chg.paused == "nopower" and md(m3).chg.power == nil, "a second car while the first takes all 11.5 kW: nothing left")
unplug(m3)

H.section("Powershare: the discharge limit stops it and tells the owner")
B.set(ct, B.part(ct), floorKwh + 2)
PS.touch(ct) -- the pack moved: refill caps the fuel
myK = B.kwh(B.part(my))
H.setHours(340)
C.settle(w2, H.hours())
check(near(B.kwh(B.part(my)) - myK, 2, 1e-6) and near(B.kwh(B.part(ct)), floorKwh - HOUSE, 1e-6),
    "Model Y got the last 2 kWh above the limit, the Cybertruck sits on it (less the house's last hour)")
C.settle(wo, H.hours())
check(T.psState(B.part(ct)) == "stopped" and gen(ct) == nil and #gens == 0, "stopped: the generator is gone")
check(removed[#removed] == g and not g.on, "switched off before the removal packet (chunk positions cleared)")
local inbox = T.Store.get("inbox").own
check(inbox and inbox[#inbox].what == "powershare" and inbox[#inbox].pct == 20, "offline owner: the stop waits in the inbox (20%)")
check(md(my).chg.paused == "nopower", "the Model Y sees no power after the stop")

H.section("Powershare: lower the limit -> backup again; another generator -> standby, charging as usual")
check(PS.set(owner, ct, "floor", nil, 3) == nil and md(ct).ps.floor == 5, "limit clamps to 5 %")
check(T.psState(B.part(ct)) == "backup" and gen(ct) ~= nil, "5 %: above it again, backup")
check(PS.set(owner, ct, "floor", nil, 95) == nil and md(ct).ps.floor == 90 and T.psState(B.part(ct)) == "stopped",
    "90 %: clamped, below it, stopped")
PS.set(owner, ct, "floor", nil, 20)
B.set(ct, B.part(ct), 100)
C.settle(wo, H.hours())
check(T.psState(B.part(ct)) == "backup", "charged back above: backup")
local other = newGen(square(305, 310, 0), "appliances_misc_01_0")
other.on, other.fuel = true, 10
C.settle(wo, H.hours())
check(T.psState(B.part(ct)) == "armed" and gen(ct) == nil, "another running generator: standby, ours removed")
check(md(ct).chg.src == "generator" and md(ct).chg.paused == nil, "and the Cybertruck charges from it as usual")
check(md(my).chg.src == "generator", "the Model Y moved to that generator too")
other.on = false
for i = #gens, 1, -1 do if gens[i] == other then table.remove(gens, i) end end
C.settle(wo, H.hours())
check(T.psState(B.part(ct)) == "backup", "that generator off: backup again")

H.section("Powershare: unplugging stops it; off stays off")
unplug(ct)
check(T.psState(B.part(ct)) == "armed" and gen(ct) == nil and #gens == 0, "unplugged: armed, the generator gone")
check(PS.set(owner, ct, "ps", false) == nil and T.psState(B.part(ct)) == "off", "switched off")
plug(ct, wo)
check(T.psState(B.part(ct)) == "off" and #gens == 0, "plugged in again while off: nothing")

H.section("Powershare: the 30-day fuel cap and GFC 0")
PS.set(owner, ct, "ps", true)
g = gen(ct)
B.set(ct, B.part(ct), 123) -- full: the kWh above the limit are no cap here
LOAD = 0.15 -- a fridge + freezer
PS.touch(ct)
check(near(g.fuel, 0.02 * 0.1 * 720, 1e-6), "load 0.15: the cap is 720 h of the generator's own 0.02 (1.44 L), not of the house")
LOAD = 0.05
PS.touch(ct)
check(near(g.fuel, 1.44, 1e-6), "load 0.05: still 1.44 L (the house's load may drop to 0.02 once the mod is gone)")
LOAD = 0.02
SandboxVars.GeneratorFuelConsumption = 0
k0 = B.kwh(B.part(ct))
g.fuel = 4
PS.touch(ct)
check(g.fuel == 10 and B.kwh(B.part(ct)) == k0, "GFC 0: a full tank, nothing booked (vanilla's free generators)")
SandboxVars.GeneratorFuelConsumption = 0.1
PS.touch(ct)
unplug(my)

H.section("Powershare / outlet: who may (the cable rule), which car")
local stranger = H.player({ name = "mal", x = 300, y = 300 })
stranger.getInventory = function() -- no key, card or phone key (Keys.lua K.card)
    return { haveThisKeyId = function() return nil end, getFirstTypeEvalArgRecurse = function() return nil end }
end
ct.locked = true
check(PS.set(stranger, ct, "ps", false) == "CAR_LOCKED" and T.psState(B.part(ct)) == "backup", "a stranger, locked car: CAR_LOCKED, unchanged")
check(PS.set(stranger, ct, "floor", nil, 50) == "CAR_LOCKED" and md(ct).ps.floor == 20, "nor the limit")
check(PS.set(stranger, ct, "outlet", true) == "CAR_LOCKED" and md(ct).outlet == nil, "nor the outlet")
ct.locked = false
check(PS.set(owner, my, "ps", true) == "NO_POWERSHARE" and md(my).ps == nil, "a Model Y: NO_POWERSHARE")
check(PS.set(owner, my, "outlet", true) == "NO_OUTLET" and md(my).outlet == nil, "a Model Y: NO_OUTLET")
check(PS.set(owner, ct, "floor", nil, "x") == "BAD_VALUE" and PS.set(owner, ct, "floor", nil, 0 / 0) == "BAD_VALUE", "a bad limit: BAD_VALUE")
H.sent = {}
ct.locked = true
stranger.x, stranger.y = 303, 303
H.fire("OnClientCommand", "MinidoracatTesla", "psOff", stranger, { vid = ct:getId() })
check(T.psState(B.part(ct)) == "backup" and H.sent[1] and H.sent[1].args.reason == "CAR_LOCKED",
    "psOff command from a stranger next to the locked car: deny CAR_LOCKED")
H.fire("OnClientCommand", "MinidoracatTesla", "psOff", owner, { vid = ct:getId() })
check(T.psState(B.part(ct)) == "off", "psOff command from the key holder: off")
H.fire("OnClientCommand", "MinidoracatTesla", "psOn", owner, { vid = ct:getId() })
check(T.psState(B.part(ct)) == "backup", "psOn command: backup again")
ct.locked = false

H.section("bed outlet: a Mobile Connector by the bed charges another Tesla from the pack")
unplug(ct)
PS.set(owner, ct, "ps", false)
ct.x, ct.y = 400.5, 400.5 -- bed area centre (400.5, 403.5)
local bedMc = charger(401, 404, MOBILE) -- outdoors, no generator
local y2 = car(MY, 30, 402.5, 405.5)
keyFor(y2)
plug(y2, bedMc)
check(md(y2).chg.paused == "nopower", "outlet off: no power")
check(PS.set(owner, ct, "outlet", true) == nil and md(ct).outlet == true and T.OutletCars[ct:getId()] == ct:getKeyId(),
    "outlet on: the server lists the car")
check(md(y2).chg.paused == "nopower", "tailgate up: still none")
ISOpenVehicleDoor.complete({ vehicle = ct, part = ct.parts.TrunkDoor })
check(ct.gateOpen and md(y2).chg.src == "outlet" and near(md(y2).chg.kw, 7.6, 1e-9),
    "tailgate down (by hand): the Mobile Connector has power at once, 7.6 kW")
ctK, myK = B.kwh(B.part(ct)), B.kwh(B.part(y2))
H.setHours(341)
C.settle(bedMc, H.hours())
gotMy, lostCt = B.kwh(B.part(y2)) - myK, ctK - B.kwh(B.part(ct))
check(near(gotMy, 7.6, 1e-6) and near(lostCt, 7.6, 1e-6), string.format("1 h: Model Y +%.3f, Cybertruck -%.3f", gotMy, lostCt))
local y3 = car(MY, 30, 399.5, 405.5)
keyFor(y3)
local bedMc2 = charger(399, 403, MOBILE)
plug(y3, bedMc2)
check(near(md(y3).chg.kw, 9.6 - 7.6, 1e-9), "a second Mobile Connector: what is left of 9.6 kW (2.0)")
unplug(y3)
local farMc = charger(404, 407, MOBILE) -- 3.5 tiles from the bed centre
check(T.bedOutlet("MobileConnector", 404, 407, 0) == nil and T.bedOutlet("MobileConnector", 402, 405, 0) == ct,
    "Chebyshev 2 tiles from the bed area: in; 3 out")
check(T.bedOutlet("WallConnector", 401, 404, 0) == nil, "a Wall Connector never plugs into the outlet")
check(T.bedOutlet("MobileConnector", 401, 404, 0, ct) == nil, "never the truck's own outlet")
myK, ctK = B.kwh(B.part(y2)), B.kwh(B.part(ct))
H.setHours(341.5)
T.Liftgate.swing(ct, ct.parts.TrunkDoor, false, "own") -- the dashboard / app close
check(near(B.kwh(B.part(y2)) - myK, 3.8, 1e-6) and near(ctK - B.kwh(B.part(ct)), 3.8, 1e-6),
    "tailgate up (dashboard): the half hour before it is booked first (3.8 each way)")
check(md(y2).chg.paused == "nopower", "and the Mobile Connector has no power after it")
T.Liftgate.swing(ct, ct.parts.TrunkDoor, true, "own")
check(md(y2).chg.src == "outlet", "down again: power")
H.setHours(342)
myK = B.kwh(B.part(y2))
check(PS.set(owner, ct, "outlet", false) == nil and md(ct).outlet == nil and T.OutletCars[ct:getId()] == nil,
    "outlet off: off the list")
check(near(B.kwh(B.part(y2)) - myK, 3.8, 1e-6) and md(y2).chg.paused == "nopower", "booked up to the switch, then none")
PS.set(owner, ct, "outlet", true)
local wct = charger(398, 398, WALL, { room = {} })
myK = B.kwh(B.part(y2))
H.setHours(342.5)
plug(ct, wct)
check(near(B.kwh(B.part(y2)) - myK, 3.8, 1e-6) and md(y2).chg.paused == "nopower", "the truck plugged in: the outlet stops (p.200)")
unplug(ct)
check(md(y2).chg.src == "outlet", "unplugged: it supplies again")
B.set(ct, B.part(ct), floorKwh + 1)
H.setHours(343)
C.settle(bedMc, H.hours())
check(near(B.kwh(B.part(ct)), floorKwh, 1e-6) and md(y2).chg.paused == "nopower", "down to the 20 % limit, then none")

H.section("bed outlet: no retroactive stretch, shares given back, the limit, a truck loading late")
B.set(ct, B.part(ct), 100) -- above the limit again; nothing settles the Model Y now
myK = B.kwh(B.part(y2))
H.setHours(343.5)
C.settle(bedMc, H.hours())
check(near(B.kwh(B.part(y2)), myK, 1e-9) and md(y2).chg.src == "outlet",
    "power came back unseen: the half hour it had none books nothing, the outlet from now on")
plug(y3, bedMc2)
check(near(md(y3).chg.kw, 2.0, 1e-9), "second car: 2.0 kW left")
local lim = 78.4 * 0.9
B.set(y2, B.part(y2), lim - 1)
local y3K = B.kwh(B.part(y3))
H.setHours(344)
C.settle(bedMc, H.hours())
check(md(y2).chg.paused == "full" and near(T.Charge.drawnKw(ct), 2.0, 1e-9), "first car full: it holds 0 kW (drawnKw 2.0)")
C.settle(bedMc2, H.hours())
check(near(B.kwh(B.part(y3)) - y3K, 1.0, 1e-6) and near(md(y3).chg.kw, 7.6, 1e-9),
    "second car: the half hour run at its 2.0 kW share (1.0 kWh), the freed share (7.6) from now on")
y3K = B.kwh(B.part(y3))
H.setHours(344.5)
C.settle(bedMc2, H.hours())
check(near(B.kwh(B.part(y3)) - y3K, 3.8, 1e-6), "next half hour at 7.6 kW")
B.set(ct, B.part(ct), floorKwh + 1)
y3K = B.kwh(B.part(y3))
H.setHours(345)
check(PS.set(owner, ct, "floor", nil, 10) == nil, "limit lowered to 10 %")
check(near(B.kwh(B.part(y3)) - y3K, 1.0, 1e-6), "the stretch before it booked at the old 20 % limit (1 kWh above it)")
B.set(ct, B.part(ct), 100)
C.settle(bedMc2, H.hours())
y3K = B.kwh(B.part(y3))
local last0 = md(y3).chg.last
local listed = T.OutletCars[ct:getId()]
T.OutletCars[ct:getId()] = nil -- the truck's cell not loaded yet
H.setHours(346)
C.relink(y3)
check(near(B.kwh(B.part(y3)), y3K, 1e-9) and md(y3).chg.last == last0 and md(y3).chg.power == "outlet",
    "the car loads before the truck that fed it: nothing booked, the record kept, settled again shortly")
T.OutletCars[ct:getId()] = listed
H.setHours(346 + 1 / 6)
C.settle(bedMc2, H.hours())
check(near(B.kwh(B.part(y3)) - y3K, 7.6 * (1 + 1 / 6), 1e-6), "the truck back: the whole stretch away booked")
y3K = B.kwh(B.part(y3))
T.OutletCars[ct:getId()] = nil
H.setHours(347)
C.relink(y3)
H.setHours(347 + 1 / 6)
C.settle(bedMc2, H.hours())
check(near(B.kwh(B.part(y3)), y3K, 1e-9) and md(y3).chg.paused == "nopower", "the truck still away on the retry: nothing, as usual")
T.OutletCars[ct:getId()] = listed
C.settle(bedMc2, H.hours()) -- on the outlet again
y3K, last0 = B.kwh(B.part(y3)), md(y3).chg.last
T.OutletCars[ct:getId()] = nil -- the player walks off: the truck's cell unloads first
H.setHours(348)
C.settle(bedMc2, H.hours())
check(near(B.kwh(B.part(y3)), y3K, 1e-9) and md(y3).chg.last == last0 and md(y3).chg.power == "outlet",
    "the truck unloaded first, the car's own settle meanwhile: it waits too (nothing booked, record kept)")
T.OutletCars[ct:getId()] = listed
H.setHours(350)
C.relink(y3)
check(near(B.kwh(B.part(y3)) - y3K, 7.6 * (350 - last0), 1e-6), "both back: the whole stretch away booked")
unplug(y3)

H.section("Powershare: nowhere to put the generator -> stopped (spot), the owner told, retried each settle")
local gw = charger(500, 500, WALL, { room = {} })
local ct2 = car(CT, 80, 500.5, 495.5)
for x = 492, 508 do for y = 487, 503 do square(x, y, 0, { room = {} }) end end -- indoors all round: no spot
keyFor(ct2)
plug(ct2, gw)
local function lastNote() local b = T.Store.get("inbox").own or {}; return b[#b] end
local before = lastNote()
PS.set(owner, ct2, "ps", true) -- plugged in, the grid long gone: decides now
check(T.psState(B.part(ct2)) == "stopped" and T.psStopWhy(B.part(ct2)) == "spot" and gen(ct2) == nil,
    "no outdoor square near: stopped, why spot, no generator")
local note = lastNote()
check(note ~= before and note.what == "powershareSpot" and note.kind == "lowBattery",
    "the owner is told (lowBattery / powershareSpot)")
C.settle(gw, H.hours())
check(lastNote() == note, "still no spot on the next settle: not told again")
square(500, 494, 0) -- an outdoor square opens up
C.settle(gw, H.hours())
check(T.psState(B.part(ct2)) == "backup" and gen(ct2) ~= nil, "a spot near now: backup")
unplug(ct2)

H.section("no polling")
check(H.count("OnTick") == ticks0 and H.count("EveryOneMinute") == mins0, "Powershare adds no OnTick / EveryOneMinute")

for k, v in pairs(saved) do _G[k] = v end
