-- Drive battery: readers, drain and transmit throttle, regen, start check, command guard, spawns.
local T, B = MinidoracatTesla, MinidoracatTesla.Battery
local check, near = H.check, H.near
H.side(false, true)

H.section("readers")
local v = H.vehicle({ kwh = 39.2 })
local part = B.part(v)
check(T.isTesla(v) and part ~= nil, "Model Y is a Tesla with a battery part")
check(B.capacity(part) == 78.4, "Performance pack capacity is the exact 78.4 kWh, not the int MaxCapacity 79")
check(near(B.pct(part), 50), "pct = kwh / exact capacity")
check(math.ceil(T.Packs["Base.MinidoracatTesla_ModelYBattery"]) == H.scriptValue("items/MinidoracatTesla_items.txt",
    "MaxCapacity", "item MinidoracatTesla_ModelYBattery"), "pack item MaxCapacity is the exact kWh rounded up")
check(math.ceil(T.Packs["Base.MinidoracatTesla_Model3Battery"]) == H.scriptValue("items/MinidoracatTesla_items.txt",
    "MaxCapacity", "item MinidoracatTesla_Model3Battery"), "Model 3 pack item MaxCapacity is the exact kWh rounded up")
local m3 = H.vehicle({ script = "Base.MinidoracatTesla_Model3", kwh = 39.2 })
check(T.isTesla(m3) and B.part(m3):getInventoryItem():getFullType() == "Base.MinidoracatTesla_Model3Battery"
    and B.capacity(B.part(m3)) == 78.4, "Model 3 is a Tesla with its own pack, exact 78.4 kWh (MIIT TSL7000BEVBA5)")
check(near(78.4 * T.kmPerKwh(m3), 75.7, 0.1), "Model 3: a full pack at 50 km/h = one vanilla CarNormal tank too (75.7 km, Gas Consumption 1)")
check(T.spec(m3).massKg == 1851, "Model 3 regen mass = Performance curb mass 1851 kg")
H.removeVehicle(m3)
local full = H.vehicle({ kwh = 78.4 })
-- vanilla repair() fills the tank to the item's int MaxCapacity (VehiclePart.java:989-992): 79 for the 78.4 kWh pack
B.part(full):setContainerContentAmount(79)
check(B.kwh(B.part(full)) == 78.4 and near(B.pct(B.part(full)), 100), "after repair() (tank 79): reads the exact 78.4 kWh")
full.running, full.speed = true, 0
T.Update.Battery(full, B.part(full), 1)
check(near(78.4 - B.kwh(B.part(full)), T.spec(full).idleKw / 60, 1e-6),
    "after repair(): the first drain takes only its own use, not the 0.6 kWh above the pack size")
full.running = false
local other = H.vehicle({ script = "Base.CarNormal" })
check(not T.isTesla(other) and B.part(other) == nil, "vanilla car is not a Tesla")
check(T.kmPerKwh(v) > 0 and near(T.rangeKm(v), 39.2 * T.kmPerKwh(v)), "range = kwh * km/kWh")
-- 2026-10-29 recalibration (Core.lua DRIVE_SCALE): vanilla CarNormal's 49 L at 50 km/h is about 75.7 km at the default
-- Gas Consumption 1 (tesla-rangegas-1029-calib-g1) and 757 km at the E2E server template's 0.1 (tesla-calib-normal-1023a)
check(T.DRIVE_SCALE == 10 and near(T.spec(v).idleKw, 0.376, 1e-12) and near(T.spec(v).kwPerKmh, 0.0572, 1e-12),
    "coefficients: 10 x the 10-23 fit (idleKw 0.376, kwPerKmh 0.0572)")
check(near(78.4 * T.kmPerKwh(v), 75.7, 0.1), "a full pack at 50 km/h = one vanilla CarNormal tank (75.7 km at Gas Consumption 1, 90-minute day)")
SandboxVars.CarGasConsumption = 0.1
check(near(78.4 * T.kmPerKwh(v), 757, 1), "Gas Consumption 0.1 (E2E MP template): the 757 km of the 10-23 calibration")
SandboxVars.CarGasConsumption = nil
SandboxVars.MinidoracatTesla.RangeMultiplier = 2
local k2 = T.kmPerKwh(v)
SandboxVars.MinidoracatTesla.RangeMultiplier = 10
local k10 = T.kmPerKwh(v)
SandboxVars.MinidoracatTesla.RangeMultiplier = 11
local k11 = T.kmPerKwh(v)
SandboxVars.MinidoracatTesla.RangeMultiplier = 0.1
local kLow = T.kmPerKwh(v)
SandboxVars.MinidoracatTesla.RangeMultiplier = 1
check(near(k2, 2 * T.kmPerKwh(v)), "RangeMultiplier 2 doubles km/kWh")
check(near(k10, 10 * T.kmPerKwh(v)) and k11 == k10 and near(78.4 * k10, 757, 1),
    "RangeMultiplier 10 (the sandbox max): 10 x, 757 km at Gas Consumption 1; 11 is clamped to 10")
check(near(kLow, 0.25 * T.kmPerKwh(v)), "RangeMultiplier below 0.25 is clamped to 0.25")
local sbf = assert(io.open("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/sandbox-options.txt", "r"))
local sbText = sbf:read("*a")
sbf:close()
local rangeOpt = sbText:sub((assert(sbText:find("option MinidoracatTesla.RangeMultiplier", 1, true))))
check(tonumber(rangeOpt:match("min%s*=%s*([%d%.]+)")) == 0.25 and tonumber(rangeOpt:match("max%s*=%s*([%d%.]+)")) == 10,
    "sandbox-options.txt RangeMultiplier 0.25-10 (= T.rangeMul's clamp)")
-- vanilla sandbox Gas Consumption (CarGasConsumption, 0-100) scales the drive draw like petrol (user 2026-10-29)
local k1 = T.kmPerKwh(v)
SandboxVars.CarGasConsumption = 1
check(T.kmPerKwh(v) == k1, "Gas Consumption 1 (vanilla default) = unset: the calibration km/kWh")
SandboxVars.CarGasConsumption = 2
check(near(T.kmPerKwh(v), k1 / 2), "Gas Consumption 2 halves km/kWh")
SandboxVars.CarGasConsumption = 0
check(T.kmPerKwh(v) == nil and T.rangeKm(v) == math.huge, "Gas Consumption 0: no range limit (km/kWh nil, range math.huge)")
SandboxVars.CarGasConsumption = "x"
check(T.kmPerKwh(v) == k1, "Gas Consumption unreadable: 1")
SandboxVars.CarGasConsumption = nil

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
SandboxVars.CarGasConsumption = 2
k0 = B.kwh(part)
T.Update.Battery(v, part, 1)
check(near(k0 - B.kwh(part), used * 2, 1e-5), "Gas Consumption 2 doubles the drain (idle included)")
SandboxVars.CarGasConsumption = 0
k0 = B.kwh(part)
T.Update.Battery(v, part, 1)
check(B.kwh(part) == k0, "Gas Consumption 0: driving takes no charge")
SandboxVars.CarGasConsumption = 1
k0 = B.kwh(part)
T.Update.Battery(v, part, 1)
check(near(k0 - B.kwh(part), used, 1e-5), "Gas Consumption 1: the calibration drain")
-- the car's own loads (climate, camp socket, 12V, sentry: B.draw) keep their kWh whatever the Gas Consumption
local drew = {}
for _, g in ipairs({ 0, 2 }) do
    SandboxVars.CarGasConsumption = g
    drew[#drew + 1] = B.draw(v, part, 0.5)
end
check(drew[1] == 0.5 and drew[2] == 0.5, "Gas Consumption 0 and 2: B.draw (climate, camp, sentry) takes the same 0.5 kWh")
SandboxVars.CarGasConsumption = nil
local empty = H.vehicle({ kwh = 0.01, running = true, speed = 80 })
T.Update.Battery(empty, B.part(empty), 10)
check(B.kwh(B.part(empty)) == 0 and empty.transmits == 1, "drain clamps at 0 and transmits the empty state")

H.section("summon: drain by distance")
-- AutoDrive's summon (Remote.lua ACT.summon): the server reads 0 km/h for an unmanned car, so the drive term comes from
-- the distance moved. Same energy as the speed formula for the same path, whatever speed the server reads.
local sv = H.vehicle({ kwh = 50, running = true, speed = 0 })
sv._class = "BaseVehicle"
local spart = B.part(sv)
local summoned = {}
local realRemote = T.Remote
T.Remote = { summonApi = function() return { summonInfo = function(car) return summoned[car] end } end }
summoned[sv] = { by = "own", phase = "driving" }
local k0 = B.kwh(spart)
T.Update.Battery(sv, spart, 1) -- the summon's first update: where it starts, idle only
check(near(k0 - B.kwh(spart), s.idleKw / 60, 1e-9), "summon, first update: idle only (no earlier position)")
local secPerMin = T.secPerGameMin()
local function step(dx, readKmh)
    sv.x, sv.speed = sv.x + dx, readKmh
    local before = B.kwh(spart)
    T.Update.Battery(sv, spart, 1)
    return before - B.kwh(spart)
end
local got = step(50, 0) -- 50 tiles in one game minute (3.75 s): 48 km/h
local kmh = 0.05 / (secPerMin / 3600)
check(near(got, (s.idleKw + s.kwPerKmh * kmh) / 60, 1e-9), "50 tiles in a game minute, server reads 0 km/h: = the speed formula at 48 km/h")
check(near(step(50, 60), got, 1e-12), "the same path with the server reading 60 km/h: the same energy")
check(near(step(0, 30), s.idleKw / 60, 1e-12), "summoned but standing: idle only, whatever the speed read")
summoned[sv] = nil
check(near(step(50, 60), (s.idleKw + s.kwPerKmh * 60) / 60, 1e-9), "summon over: back to the speed read")
summoned[sv] = { by = "own", phase = "driving", startedMs = 1000 }
check(near(step(500, 0), s.idleKw / 60, 1e-12), "a new summon starts from where the car is (not from the last one's end)")
summoned[sv] = { by = "own", phase = "driving", startedMs = 2000 } -- ended and summoned again between two updates
check(near(step(500, 0), s.idleKw / 60, 1e-12), "back to back, no update between: the second summon starts fresh too")
check(near(step(50, 0), got, 1e-9), "...then counts its own path")
summoned[sv] = nil
step(0, 0)
-- recorded at the start (Remote.lua ACT.summon), charged at the end (R.summonEnded): a summon shorter than one
-- game minute (most of them) is over before the pack's first update
local drive = got - s.idleKw / 60 -- 50 tiles' drive term
B.summonStart(sv, 3000)
summoned[sv] = { by = "own", phase = "driving", startedMs = 3000 }
sv.x = sv.x + 50
summoned[sv] = nil
local before = B.kwh(spart)
B.summonEnd(sv)
check(near(before - B.kwh(spart), drive, 1e-9), "start and end with no update between: the whole path charged at the end")
B.summonStart(sv, 4000)
summoned[sv] = { by = "own", phase = "driving", startedMs = 4000 }
check(near(step(50, 0), got, 1e-9), "an update during it: the path from the start (not 0)")
sv.x = sv.x + 50
summoned[sv] = nil
before = B.kwh(spart)
B.summonEnd(sv)
check(near(before - B.kwh(spart), drive, 1e-9), "...and the end charges only the leg after that update")
before = B.kwh(spart)
B.summonEnd(sv)
check(B.kwh(spart) == before, "an end with nothing kept: no charge")
SandboxVars.CarGasConsumption = 2
B.summonStart(sv, 5000)
summoned[sv] = { by = "own", phase = "driving", startedMs = 5000 }
sv.x = sv.x + 50
summoned[sv] = nil
before = B.kwh(spart)
B.summonEnd(sv)
check(near(before - B.kwh(spart), 2 * drive, 1e-9), "Gas Consumption 2: a summon's path takes twice the charge")
SandboxVars.CarGasConsumption = 0
B.summonStart(sv, 6000)
summoned[sv] = { by = "own", phase = "driving", startedMs = 6000 }
sv.x = sv.x + 50
summoned[sv] = nil
before = B.kwh(spart)
B.summonEnd(sv)
check(B.kwh(spart) == before, "Gas Consumption 0: a summon takes no charge")
SandboxVars.CarGasConsumption = nil
T.Remote = realRemote

H.section("regen")
local R = T.Regen
local rv = H.vehicle({ kwh = 30, running = true, speed = 60 })
local rp = B.part(rv)
local ke60 = 0.6 * 0.5 * 2033 * (60 / 3.6) ^ 2 / 3600000 -- the physical kinetic energy, kWh
check(near(R.kwh(s, 60, 0), ke60 * T.DRIVE_SCALE), "regen kWh = eff * 1/2 m (v1^2 - v2^2) x DRIVE_SCALE (the drive draw's calibration)")
check(R.kwh(s, 20, 40) == 0, "no regen when speeding up")
SandboxVars.CarGasConsumption = 2
local ke2 = R.kwh(s, 60, 0)
SandboxVars.CarGasConsumption = 0.1
local ke01 = R.kwh(s, 60, 0)
SandboxVars.CarGasConsumption = nil
check(near(ke2, 2 * ke60 * T.DRIVE_SCALE) and near(ke01, ke60), "regen follows T.driveMul: x2 at Gas Consumption 2; at 0.1 the 10-23 value")
-- the share of the drive draw braking gives back is the same at any Gas Consumption (2026-10-29 recalibration: the
-- drive draw went x10; unscaled, regen would have fallen to a tenth of its share). SP path, 5 min at 60 then 20 -> 0
-- (small enough to stay under the 30% budget).
H.side(false, false)
local function regenShare(gas)
    SandboxVars.CarGasConsumption = gas
    local car = H.vehicle({ kwh = 50, running = true, speed = 60 })
    local cp = B.part(car)
    local k0 = B.kwh(cp)
    for _ = 1, 5 do T.Update.Battery(car, cp, 1) end
    local used = k0 - B.kwh(cp)
    car.running, car.speed, car.brakeSpeed = false, 0, 20
    local k1 = B.kwh(cp)
    T.Update.Battery(car, cp, 1)
    SandboxVars.CarGasConsumption = nil
    H.removeVehicle(car)
    return (B.kwh(cp) - k1) / used
end
local sh1, sh01, sh2 = regenShare(1), regenShare(0.1), regenShare(2)
check(sh1 > 0.1 and sh1 < R.SHARE and near(sh01, sh1, 1e-9) and near(sh2, sh1, 1e-9),
    string.format("regen share of the drive draw: %.4f at Gas Consumption 1, the same at 0.1 and 2", sh1))
-- the unspent budget's cap scales too (R.BUDGET_MAX x R.scale(), 5 kWh at Gas Consumption 1): an hour at 60 km/h
-- banks 6 x 0.3 x (0.376 + 0.0572 x 60) x 10/60 = 1.142 kWh, and a stop from 120 km/h (1.88 kWh) takes all of it
local bc = H.vehicle({ kwh = 50, running = true, speed = 60 })
local bp = B.part(bc)
for _ = 1, 6 do T.Update.Battery(bc, bp, 10) end
bc.running, bc.speed, bc.brakeSpeed = false, 0, 120
local bk = B.kwh(bp)
T.Update.Battery(bc, bp, 1)
local banked = 6 * R.SHARE * (s.idleKw + s.kwPerKmh * 60) * 10 / 60
check(near(B.kwh(bp) - bk, banked, 1e-9) and banked > 1.1,
    string.format("budget cap scales with the drive draw: an hour's budget %.3f kWh is credited, not capped at 0.5", banked))
H.removeVehicle(bc)
H.side(false, true)
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
check(gained <= math.min(R.kwh(s, 60, 0), R.BUDGET_MAX * R.scale()) + 1e-9, "credit never exceeds the kinetic energy or the budget")
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
-- vehicle ids go to other cars (BaseVehicle.java:793-801): a car that gets a gone car's id gets none of its regen
local function idCar(id, keyId)
    local c = H.vehicle({ id = id, kwh = 30, running = true, speed = 60 })
    c._class, c.keyId = "BaseVehicle", keyId
    local d = H.player({ name = "drv" .. keyId })
    d.vehicle, c.driver = c, d
    return c, B.part(c), d
end
local function brake(c, d)
    H.fire("OnClientCommand", "vehicle", "setStoplightsOn", d, { on = true })
    c.speed = 0
    H.fire("OnClientCommand", "vehicle", "setStoplightsOn", d, { on = false })
    c.running = false
end
local ida, iap, iad = idCar(900, 501)
for _ = 1, 5 do T.Update.Battery(ida, iap, 1) end -- budget
brake(ida, iad) -- pending, not yet credited
H.removeVehicle(ida)
local idb, ibp = idCar(900, 502)
idb.running, idb.speed = false, 0
local ib0 = B.kwh(ibp)
T.Update.Battery(idb, ibp, 1)
check(B.kwh(ibp) == ib0, "id reused by another car (keyId differs): the gone car's pending regen and budget are not credited")
H.removeVehicle(idb)
local idc, icp = idCar(901, 503)
for _ = 1, 5 do T.Update.Battery(idc, icp, 1) end -- budget only
H.removeVehicle(idc)
local idd, idp, idd2 = idCar(901, 504)
brake(idd, idd2) -- its own brake from 60, no budget of its own
local id0 = B.kwh(idp)
T.Update.Battery(idd, idp, 1)
check(B.kwh(idp) == id0, "id reused: the new car's own brake gets no budget from the gone car")
idd.running, idd.speed = true, 60
for _ = 1, 5 do T.Update.Battery(idd, idp, 1) end
brake(idd, idd2)
id0 = B.kwh(idp)
T.Update.Battery(idd, idp, 1)
check(B.kwh(idp) > id0, "...and once it has driven, its own budget pays its regen")
H.removeVehicle(idd)
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

H.section("start check and plugged-in driving")
local cv = H.vehicle({ kwh = 10 })
function cv:isRegulator() return self.cruise == true end
function cv:setRegulator(on) self.cruise = on end
local cp = B.part(cv)
check(T.CheckEngine.Battery(cv, cp) == true, "can start with charge and no cable")
cv.cruise = true
check(T.CheckOperate.Battery(cv, cp) == true and cv.cruise == true, "no cable: the driver's input reaches the car, cruise untouched")
cp:getModData().chg = { x = 1, y = 1, z = 0 }
check(T.CheckEngine.Battery(cv, cp) == true, "plugged in: the car still powers on (Park, owner's manual Shifting)")
local pedal, asked = false, 0
T.onPluggedDrive = function(veh) if veh == cv then asked = asked + 1 end return pedal end
check(T.CheckOperate.Battery(cv, cp) == true and asked == 1 and cv.cruise == false,
    "plugged in, no pedal: controls refresh (a held pedal clears on release), cruise control switched off")
pedal = true
check(T.CheckOperate.Battery(cv, cp) == false, "plugged in, accelerator down: the input is held back")
T.onPluggedDrive = nil
check(T.CheckOperate.Battery(cv, cp) == true, "dedicated server (no client hint): controls are not read there anyway")
cp:getModData().chg = nil
cp:setContainerContentAmount(0)
check(T.CheckEngine.Battery(cv, cp) == false, "cannot start with an empty pack")
local nopack = H.vehicle({ noPack = true })
check(B.part(nopack):getInventoryItem() == nil, "noPack fixture: the GasTank slot is empty")
-- charge left in the part's mod data still reads back with no item (VehiclePart.java:375-381), so only the
-- missing pack can refuse the start here
B.part(nopack):getModData().contentAmount = 50
check(nopack:hasEnoughGasToRun() and T.CheckEngine.Battery(nopack, B.part(nopack)) == false, "cannot start without a pack")
local tf = assert(io.open("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/scripts/vehicles/MinidoracatTesla_template.txt"))
local tpl = tf:read("*a")
tf:close()
local gasTank = tpl:sub((tpl:find("part GasTank", 1, true)))
gasTank = gasTank:sub(1, (gasTank:find("table install", 1, true)))
check(gasTank:find("checkOperate = MinidoracatTesla.CheckOperate.Battery,", 1, true) ~= nil,
    "vehicle template: GasTank lua block wires checkOperate")
v.speed = 1
check(T.stopped(v) == true, "1 km/h counts as stopped")
v.speed = -1.5
check(T.stopped(v) == false, "1.5 km/h in reverse is moving")
v.speed = 0

H.section("writers")
local wv = H.vehicle({ kwh = 10 })
local wp = B.part(wv)
local added = B.add(wv, 100, 50)
check(near(B.kwh(wp), 39.2) and near(added, 29.2), "add stops at the target percent and returns what was added")
check(B.add(wv, 5, 50) == 0, "add at target adds nothing")
wv:getBattery():getInventoryItem():setUsedDelta(0.5)
local took = B.topUp12V(wv)
check(near(took, 0.5 * T.Specs["Base.MinidoracatTesla_ModelY"].v12Kwh) and near(wv:getBattery():getInventoryItem():getCurrentUsesFloat(), 1), "topUp12V fills 12V from the pack")
check(B.topUp12V(wv) == 0, "topUp12V on a full 12V does nothing")
check(B.set(wv, wp, 0 / 0) == 0, "set turns NaN into 0")

H.section("on a powered charger: the car's own loads skip the pack")
local ov = H.vehicle({ kwh = 30, running = true, speed = 0 })
local op = B.part(ov)
op:getModData().chg = { x = 1, y = 1, z = 0, power = nil }
check(B.onCharger(op) == false, "plugged in, charger without power: loads stay on the pack")
local o0 = B.kwh(op)
T.Update.Battery(ov, op, 10)
check(near(o0 - B.kwh(op), T.spec(ov).idleKw * 10 / 60, 1e-6), "unpowered charger: running motor drains the pack as before")
op:getModData().chg.power = "grid"
check(B.onCharger(op) == true, "plugged in with grid: on the charger")
o0 = B.kwh(op)
T.Update.Battery(ov, op, 10)
check(B.kwh(op) == o0, "powered charger: the running motor's standby takes nothing from the pack")
check(B.draw(ov, op, 1.5) == 0 and B.kwh(op) == o0, "powered charger: B.draw takes nothing")
ov:getBattery():getInventoryItem():setUsedDelta(0.2)
check(B.topUp12V(ov) == 0 and near(ov:getBattery():getInventoryItem():getCurrentUsesFloat(), 1) and B.kwh(op) == o0,
    "powered charger: the 12V is topped up without touching the pack")
B.set(ov, op, B.capacity(op) * 0.02)
ov:getBattery():getInventoryItem():setUsedDelta(0.5)
B.dcdc(ov)
check(near(ov:getBattery():getInventoryItem():getCurrentUsesFloat(), 1), "powered charger: DC-DC works below its 5% pack floor")
op:getModData().chg.power = "generator"
check(B.onCharger(op) == true, "generator power counts too")
op:getModData().chg = nil
o0 = B.kwh(op)
check(near(B.draw(ov, op, 0.5), 0.5) and near(o0 - B.kwh(op), 0.5), "unplugged: B.draw takes from the pack")
check(near(B.draw(ov, op, 99), o0 - 0.5) and B.kwh(op) == 0, "B.draw stops at empty and returns what it took")

H.section("create")
H.setRand(0.5)
local nv = H.vehicle({})
T.Create.Battery(nv, B.part(nv))
check(near(B.pct(B.part(nv)), (0.05 + 0.55 * 0.5) * 100), "create: normal car starts at 5-60%")
nv.good = true
T.Create.Battery(nv, B.part(nv))
check(near(B.pct(B.part(nv)), 80), "create: good car starts at 60-100%")
T.Create.Motor(nv, nv:getPartById("Engine"))
check(nv.feature and nv.feature[1] == 100 and nv.feature[2] == 20 and nv.feature[3] == 6260,
    "motor: quality 100, script loudness, script engineForce 6260 (626 hp, Performance)")
local nm3 = H.vehicle({ script = "Base.MinidoracatTesla_Model3" })
T.Create.Motor(nm3, nm3:getPartById("Engine"))
check(nm3.feature and nm3.feature[3] == 6180, "Model 3 motor: its own script engineForce 6180 (461 kW = 618 hp)")
H.removeVehicle(nm3)
H.setRand(0.5)
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
    and Z.good.vehicles["Base.MinidoracatTesla_ModelY"].spawnChance == 4, "spawn table Model Y: parkingstall 3, good 4")
check(Z.parkingstall.vehicles["Base.MinidoracatTesla_Model3"].spawnChance == 3
    and Z.good.vehicles["Base.MinidoracatTesla_Model3"] == nil, "spawn table Model 3: parkingstall 3, not in good")

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
