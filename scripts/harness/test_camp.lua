-- 露營：開啟條件（行駛中拒絕、馬達運轉中停著一次開好）、熄火加熱並扣主電池、12V 補電、下車／低電量／發動自動關閉、重載後重設 needPartsUpdate、與哨兵互斥。
local F = dofile("scripts/harness/park_fakes.lua")
local check = (H and H.check) or function(ok, label) print((ok and "  PASS  " or "  FAIL  ") .. label); if not ok then error(label) end end

require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/Battery"
require "MinidoracatTesla/Inbox"
require "MinidoracatTesla/Sentry"
require "MinidoracatTesla/Camp"
local T = MinidoracatTesla
local C = T.Camp
T.Packs["Base.MinidoracatTesla_TestPack"] = 75

local cmds = T.ServerCommands
local function md(v) return v:getPartById("GasTank"):getModData() end
local function kwh(v) return T.Battery.kwh(v.parts.GasTank) end

local v = F.track(F.vehicle({ pct = 50 }))
local owner = F.player("owner", { keys = { [v.keyId] = true } })
F.online = { owner }

-- ---- rules ----
cmds.campOn(owner, { vid = v:getId() })
check(md(v).camp == nil and F.lastSent("deny").args.reason == "NOT_INSIDE", "camp: must be seated inside")
owner.vehicle, v.passengers, v.running, v.kmh = v, 1, true, 30
cmds.campOn(owner, { vid = v:getId() })
check(md(v).camp == nil and F.lastSent("deny").args.reason == "MOVING" and v.running and not v.shutOffs,
    "camp: moving car -> MOVING, motor keeps running")
v.kmh = C.MAX_KMH + 0.5
check(select(2, C.canEnable(owner, v)) == "MOVING", "camp: rolling just above MAX_KMH is still moving")
v.kmh, v.running = 0, false
local stranger = F.player("stranger", { vehicle = v })
cmds.campOn(stranger, { vid = v:getId() })
check(md(v).camp == nil and F.lastSent("deny").args.reason == "NOT_OWNER", "camp: stranger in the seat cannot enable")

-- starting the motor moves the driver's key into the ignition (BaseVehicle.java:8647-8675): no key in hand
local driven = F.track(F.vehicle({ pct = 50 }))
driven.ignition, driven.running, driven.passengers = true, true, 2
local driver = F.player("driver", { vehicle = driven })
driven.driver = driver
cmds.campOn(F.player("rider", { vehicle = driven }), { vid = driven:getId() })
check(md(driven).camp == nil and F.lastSent("deny").args.reason == "NOT_DRIVER" and driven.running,
    "camp: a passenger cannot shut the driver's motor off (vanilla shut-off is driver-only)")
cmds.campOn(driver, { vid = driven:getId() })
check(md(driven).camp ~= nil and not driven.running and driven.shutOffs == 1,
    "camp: motor on, parked, key in the ignition -> camp on and motor shut off in one tap (not NOT_OWNER)")
check(driven.parts.Heater:getModData().active == true and driven.parts.Heater:getModData().temperature == C.DEFAULT_TEMP,
    "camp: heater back on after the shut-off switched it off")
md(driven).camp = nil
MinidoracatVehicleManagerAPI = { canUse = function() return false, "NO_RIGHTS" end }
cmds.campOn(driver, { vid = driven:getId() })
check(md(driven).camp == nil and F.lastSent("deny").args.reason == "NOT_OWNER",
    "camp: VehicleManager refusal wins over a key in the ignition")
MinidoracatVehicleManagerAPI = nil
cmds.campOn(driver, { vid = driven:getId() })
check(md(driven).camp ~= nil and driven.shutOffs == 1,
    "camp: key left in the ignition after shutdown -> the seated player enables (no second shut-off)")

-- ---- exclusive with sentry ----
md(v).sentry = { by = "owner", at = F.hours, kwh = kwh(v), since = F.hours }
cmds.campOn(owner, { vid = v:getId() })
local heater = v.parts.Heater:getModData()
check(md(v).camp ~= nil and md(v).sentry == nil, "camp: on, sentry cleared")
check(heater.active == true and heater.temperature == C.DEFAULT_TEMP and v.needParts == true,
    "camp: heater forced on at default knob value, parts update on")

-- ---- off: hook is a single field check ----
local plain = F.track(F.vehicle({ pct = 50 }))
plain.needParts = false
C.onEngineUpdate(plain, plain.parts.GasTank, 1)
check(plain.needParts == false and plain.transmits == 0, "camp off: engine hook changes nothing")

-- ---- heater warms with the motor off, draws the main pack ----
local pc = v.parts.PassengerCompartment:getModData()
local k0 = kwh(v)
for _ = 1, 10 do T.Update.Heater(v, v.parts.Heater, 1) end
check(pc.temperature == 10, "heater: +1 per game minute while camping (motor off)")
check(math.abs((k0 - kwh(v)) - C.HEATER_KW * 10 / 60) < 1e-6, "heater: 1.5 kW drawn from the main pack")
local idle = F.track(F.vehicle({ pct = 50 }))
idle.parts.Heater:getModData().active, idle.parts.Heater:getModData().temperature = true, 15
local i0 = kwh(idle)
T.Update.Heater(idle, idle.parts.Heater, 5)
check(kwh(idle) == i0 and (idle.parts.PassengerCompartment:getModData().temperature or 0) == 0,
    "heater: no camp and motor off -> no heat, no draw (vanilla behaviour)")

-- ---- 12V: DC-DC top-up whenever the pack holds >= 5% (camp or not) ----
v.parts.Battery.item.uses = 0.5
T.Update.Battery12V(v, v.parts.Battery, 1)
check(v.parts.Battery.item.uses >= 0.99, "12V: topped up while camping")
T.Battery.set(idle, idle.parts.GasTank, 75 * 0.0499)
idle.parts.Battery.item.uses = 0.5
local low0 = kwh(idle)
T.Update.Battery12V(idle, idle.parts.Battery, 1)
check(idle.parts.Battery.item.uses == 0.5 and kwh(idle) == low0, "12V: no DC-DC top-up below 5% pack")
T.Battery.set(idle, idle.parts.GasTank, 75 * 0.05)
local five0 = kwh(idle)
T.Update.Battery12V(idle, idle.parts.Battery, 1)
check(idle.parts.Battery.item.uses >= 0.99 and math.abs((five0 - kwh(idle)) - 0.5 * T.V12_KWH) < 1e-9,
    "12V: DC-DC at 5% pack, camp off: refilled, pack pays 0.5 x V12_KWH")
idle.parts.Battery.item.uses = 0.96
local hi0 = kwh(idle)
T.Update.Battery12V(idle, idle.parts.Battery, 1)
check(idle.parts.Battery.item.uses == 0.96 and kwh(idle) == hi0, "12V: no top-up at 95% or more")

-- ---- engine hook keeps parts updating; reload resets the unsaved flag ----
v.needParts = false
C.onEngineUpdate(v, v.parts.GasTank, 1)
check(v.needParts == true and md(v).camp ~= nil, "camp: engine hook re-enables needPartsUpdate")
v.needParts = false
F.fire("OnSpawnVehicleEnd", v)
check(v.needParts == true, "camp: OnSpawnVehicleEnd re-enables needPartsUpdate after reload")

-- ---- auto-off: low battery (with alert), empty cabin, motor started ----
F.sent = {}
T.Battery.set(v, v.parts.GasTank, 75 * 0.199)
C.onEngineUpdate(v, v.parts.GasTank, 1)
check(md(v).camp == nil and heater.active == false, "camp: below 20% turns off, heater off")
check(F.lastSent("alert") ~= nil and F.lastSent("alert").args.kind == "lowBattery" and F.lastSent("alert").args.what == "camp",
    "camp: owner alerted on low battery")

T.Battery.set(v, v.parts.GasTank, 60)
cmds.campOn(owner, { vid = v:getId() })
v.passengers, owner.vehicle = 0, nil
C.onEngineUpdate(v, v.parts.GasTank, 1)
check(md(v).camp == nil, "camp: empty cabin turns it off")

owner.vehicle, v.passengers = v, 1
cmds.campOn(owner, { vid = v:getId() })
v.running = true
C.onEngineUpdate(v, v.parts.GasTank, 1)
check(md(v).camp == nil, "camp: starting the motor turns it off")

-- VirtualVehicle (SP unloaded car) has no hasPassenger: treated as empty
v.running = false
cmds.campOn(owner, { vid = v:getId() })
v.hasPassenger = nil
C.onEngineUpdate(v, v.parts.GasTank, 1)
check(md(v).camp == nil, "camp: VirtualVehicle without hasPassenger turns it off")

-- arming sentry clears a stale camp
local w = F.track(F.vehicle({ pct = 60 }))
local wo = F.player("wo", { keys = { [w.keyId] = true } })
md(w).camp = { by = "wo", at = F.hours }
cmds.sentryArm(wo, { vid = w:getId() })
check(md(w).sentry ~= nil and md(w).camp == nil, "sentry: arming clears camp")

F.done()
