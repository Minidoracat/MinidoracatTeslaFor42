-- Drive battery: readers, drain and transmit throttle, regen, start check, command guard, spawns.
local T, B = MinidoracatTesla, MinidoracatTesla.Battery
local check, near = H.check, H.near
H.side(false, true)

H.section("readers")
local v = H.vehicle({ kwh = 31.25 })
local part = B.part(v)
check(T.isTesla(v) and part ~= nil, "Model Y is a Tesla with a battery part")
check(B.capacity(part) == 62.5, "SR pack capacity is the exact 62.5 kWh, not the int MaxCapacity 63")
check(near(B.pct(part), 50), "pct = kwh / exact capacity")
local lr = H.vehicle({ pack = "Base.MinidoracatTesla_ModelYBatteryLR", kwh = 82.1 })
check(B.capacity(B.part(lr)) == 82.1 and near(B.pct(B.part(lr)), 100), "LR pack 82.1 kWh")
local other = H.vehicle({ script = "Base.CarNormal" })
check(not T.isTesla(other) and B.part(other) == nil, "vanilla car is not a Tesla")
check(T.kmPerKwh(v) > 0 and near(T.rangeKm(v), 31.25 * T.kmPerKwh(v)), "range = kwh * km/kWh")
SandboxVars.MinidoracatTesla.RangeMultiplier = 2
local k2 = T.kmPerKwh(v)
SandboxVars.MinidoracatTesla.RangeMultiplier = 1
check(near(k2, 2 * T.kmPerKwh(v)), "RangeMultiplier 2 doubles km/kWh")

H.section("drain")
local s = T.spec(v)
v.running, v.speed = true, 60
local before = B.kwh(part)
T.Update.Battery(v, part, 1)
local used = (s.idleKw + s.kwPerKmh * 60) / 60
check(near(before - B.kwh(part), used, 1e-5), "one game minute at 60 km/h drains (idle + k*60)/60 kWh")
check(v.transmits == 1, "first write transmits (no sentKwh yet)")
local tx = v.transmits
T.Update.Battery(v, part, 1)
check(v.transmits == tx, "a drain below 1% of capacity does not transmit")
for _ = 1, math.ceil(B.capacity(part) / 100 / used) do T.Update.Battery(v, part, 1) end -- just past 1%
check(v.transmits == tx + 1, "transmits once the change since the last send reaches 1%")
local k0 = B.kwh(part)
T.Update.Battery(v, part, 600)
check(near(k0 - B.kwh(part), used * T.MAX_ELAPSED, 1e-5), "elapsedMinutes is capped at 10")
v.running = false
k0 = B.kwh(part)
T.Update.Battery(v, part, 5)
check(B.kwh(part) == k0, "no drain with the motor off")
SandboxVars.MinidoracatTesla.RangeMultiplier = 2
v.running = true
k0 = B.kwh(part)
T.Update.Battery(v, part, 1)
check(near(k0 - B.kwh(part), used / 2, 1e-5), "RangeMultiplier 2 halves the drain")
SandboxVars.MinidoracatTesla.RangeMultiplier = 1
local empty = H.vehicle({ kwh = 0.01, running = true, speed = 80 })
T.Update.Battery(empty, B.part(empty), 10)
check(B.kwh(B.part(empty)) == 0 and empty.transmits == 1, "drain clamps at 0 and transmits the empty state")

H.section("regen")
local R = T.Regen
local rv = H.vehicle({ kwh = 30, running = true, speed = 60 })
local rp = B.part(rv)
check(near(R.kwh(s, 60, 0), 0.6 * 0.5 * 1980 * (60 / 3.6) ^ 2 / 3600000), "regen kWh = eff * 1/2 m (v1^2 - v2^2)")
check(R.kwh(s, 20, 40) == 0, "no regen when speeding up")
-- MP: drive 5 minutes to build budget, then brake 60 -> 0
for _ = 1, 5 do T.Update.Battery(rv, rp, 1) end
local driver = H.player({ name = "drv" })
driver.vehicle, rv.driver = rv, driver
H.fire("OnClientCommand", "vehicle", "setStoplightsOn", driver, { on = true })
rv.speed = 0
H.fire("OnClientCommand", "vehicle", "setStoplightsOn", driver, { on = false })
rv.running = false -- coasting stopped: next update only credits regen
local k1 = B.kwh(rp)
T.Update.Battery(rv, rp, 1)
local gained = B.kwh(rp) - k1
check(gained > 0, "MP brake edge credits regen at the next battery update")
check(gained <= math.min(R.kwh(s, 60, 0), R.BUDGET_MAX) + 1e-9, "credit never exceeds the kinetic energy or the budget")
-- accelerate/brake loop: net energy must still go down
rv.running = true
local loopStart = B.kwh(rp)
for _ = 1, 30 do
    rv.speed = 60
    T.Update.Battery(rv, rp, 1)
    H.fire("OnClientCommand", "vehicle", "setStoplightsOn", driver, { on = true })
    rv.speed = 0
    H.fire("OnClientCommand", "vehicle", "setStoplightsOn", driver, { on = false })
end
T.Update.Battery(rv, rp, 1)
check(B.kwh(rp) < loopStart, "accelerate/brake loops cannot create energy (budget cap)")
-- a passenger's or other car's stoplight command does nothing
local p2 = H.player({ name = "pax" })
p2.vehicle = rv
rv.speed = 60
H.fire("OnClientCommand", "vehicle", "setStoplightsOn", p2, { on = true })
rv.speed = 0
H.fire("OnClientCommand", "vehicle", "setStoplightsOn", p2, { on = false })
rv.running = false
k1 = B.kwh(rp)
T.Update.Battery(rv, rp, 1)
check(B.kwh(rp) == k1, "stoplight edges from a non-driver are ignored")
-- SP: engine-recorded brake start speed
H.side(false, false)
local sv = H.vehicle({ kwh = 30, running = true, speed = 60 })
local sp = B.part(sv)
for _ = 1, 5 do T.Update.Battery(sv, sp, 1) end
sv.running, sv.speed, sv.brakeSpeed = false, 0, 60
k1 = B.kwh(sp)
T.Update.Battery(sv, sp, 1)
check(B.kwh(sp) > k1, "SP: getBrakeSpeedBetweenUpdate drives regen")
H.side(false, true)

H.section("start check")
local cv = H.vehicle({ kwh = 10 })
local cp = B.part(cv)
check(T.CheckEngine.Battery(cv, cp) == true, "can start with charge and no cable")
cp:getModData().chg = { x = 1, y = 1, z = 0 }
check(T.CheckEngine.Battery(cv, cp) == false, "cannot start while a charge cable is plugged in")
cp:getModData().chg = nil
cp:setContainerContentAmount(0)
check(T.CheckEngine.Battery(cv, cp) == false, "cannot start with an empty pack")
local nopack = H.vehicle({ noPack = true })
check(T.CheckEngine.Battery(nopack, B.part(nopack)) == false, "cannot start without a pack")

H.section("writers")
local wv = H.vehicle({ kwh = 10 })
local wp = B.part(wv)
local added = B.add(wv, 100, 50)
check(near(B.kwh(wp), 31.25) and near(added, 21.25), "add stops at the target percent and returns what was added")
check(B.add(wv, 5, 50) == 0, "add at target adds nothing")
wv:getBattery():getInventoryItem():setUsedDelta(0.5)
local took = B.topUp12V(wv)
check(near(took, 0.5 * T.V12_KWH) and near(wv:getBattery():getInventoryItem():getCurrentUsesFloat(), 1), "topUp12V fills 12V from the pack")
check(B.topUp12V(wv) == 0, "topUp12V on a full 12V does nothing")
check(B.set(wv, wp, 0 / 0) == 0, "set turns NaN into 0")

H.section("create")
H.setRand(0.5)
local nv = H.vehicle({})
T.Create.Battery(nv, B.part(nv))
check(near(B.pct(B.part(nv)), (0.05 + 0.55 * 0.5) * 100), "create: normal car starts at 5-60%")
nv.good = true
T.Create.Battery(nv, B.part(nv))
check(near(B.pct(B.part(nv)), 80), "create: good car starts at 60-100%")
T.Create.Motor(nv, nv:getPartById("Engine"))
check(nv.feature and nv.feature[1] == 100 and nv.feature[2] == 20 and nv.feature[3] == 5000, "motor: quality 100, script loudness and force")
local pal = T.spec(nv).colors[5] -- ZombRand(8) with rand 0.5 = 4 -> colors[5], skin 4
check(nv.skin == 4 and nv.hsv and nv.hsv[1] == pal.h and nv.hsv[2] == pal.s and nv.hsv[3] == pal.v
    and nv.colorTx == 1 and nv.skinTx == 1, "new car gets a factory paint (skin + damage tint) and transmits it")
T.Update.Engine(nv, nv:getPartById("Engine"), 1)
check(nv.vanillaEngine == 1, "Update.Engine runs the vanilla engine update")

H.section("command guard")
local gv = H.vehicle({ kwh = 5 })
local cheat = H.player({ name = "mallory" })
local args = { vehicle = gv:getId(), part = "GasTank", amount = 62 }
H.fire("OnClientCommand", "vehicle", "setContainerContentAmount", cheat, args)
check(args.vehicle == -1 and args.amount == nil and args.part == nil, "non-admin setContainerContentAmount on a Tesla pack is neutralized")
local admin = H.player({ name = "root", admin = true })
args = { vehicle = gv:getId(), part = "GasTank", amount = 62 }
H.fire("OnClientCommand", "vehicle", "setContainerContentAmount", admin, args)
check(args.vehicle == gv:getId() and args.amount == 62, "admin passes")
args = { vehicle = other:getId(), part = "GasTank", amount = 10 }
H.fire("OnClientCommand", "vehicle", "setContainerContentAmount", cheat, args)
check(args.vehicle == other:getId(), "vanilla cars are untouched")
args = { vehicle = gv:getId(), part = "TireFrontLeft", amount = 10 }
H.fire("OnClientCommand", "vehicle", "setContainerContentAmount", cheat, args)
check(args.part == "TireFrontLeft", "other Tesla parts (tire air) are untouched")

H.section("authorized and spawns")
local owner = H.player({ name = "own", keys = { [77] = true } })
check(T.authorized(owner, gv) == true and T.authorized(cheat, gv) == false, "no VehicleManager: key decides")
MinidoracatVehicleManagerAPI = { canUse = function(p, veh, perm) return p == cheat, "VM" end }
check(T.authorized(cheat, gv, "FUEL") == true and T.authorized(owner, gv, "FUEL") == false, "VehicleManager present: canUse decides")
MinidoracatVehicleManagerAPI = nil
local Z = VehicleZoneDistribution
check(Z.parkingstall.vehicles["Base.MinidoracatTesla_ModelY"].spawnChance == 3
    and Z.good.vehicles["Base.MinidoracatTesla_ModelY"].spawnChance == 4, "spawn table: parkingstall 3, good 4")

H.section("dispatch")
local hits = 0
T.ServerCommands.harnessPing = function(p, a) hits = hits + 1; error("boom") end
H.fire("OnClientCommand", "MinidoracatTesla", "harnessPing", cheat, nil)
check(hits == 1, "server dispatch calls the handler and survives its error")
T.ServerCommands.harnessPing = nil
H.sent = {}
local far = H.player({ x = 500, y = 500 })
check(T.commandVehicle(far, { vid = gv:getId() }) == nil and H.sent[1] and H.sent[1].args.reason == "TOO_FAR", "commandVehicle denies far players")
check(T.commandVehicle(cheat, { vid = gv:getId() + 0.5 }) == nil, "commandVehicle rejects fractional ids")
check(T.commandVehicle(cheat, { vid = gv:getId() }) == gv, "commandVehicle returns the car for a near player")
