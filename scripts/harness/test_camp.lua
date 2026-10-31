-- 露營：開啟條件（行駛中拒絕、馬達運轉中停著一次開好）、熄火加熱並扣主電池、12V 補電、下車／低電量／發動自動關閉、重載後重設 needPartsUpdate、與哨兵互斥；HEPA／生化防禦（空調開著、生化防禦、都關著、Model 3 沒有）。
local F = dofile("scripts/harness/park_fakes.lua")
local check = (H and H.check) or function(ok, label) print((ok and "  PASS  " or "  FAIL  ") .. label); if not ok then error(label) end end

require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/Battery"
require "MinidoracatTesla/Inbox"
require "MinidoracatTesla/Sentry"
require "MinidoracatTesla/Camp"
-- bdm asks Remote.vmAllows (test_phone_app loads the real Remote.lua with its fakes); its rule here: no VehicleManager
-- = yes, else canUse's answer (NOT_OWNER on refusal). Restored at the end of the HEPA block.
local savedRemote = MinidoracatTesla.Remote
MinidoracatTesla.Remote = { vmAllows = function(p, v, codes)
    local api = MinidoracatVehicleManagerAPI
    if not (api and api.canUse) then return true end
    if api.canUse(p, v, codes[1]) then return true end
    return false, "NOT_OWNER"
end }
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
v.kmh = T.STOP_KMH + 0.5
check(select(2, C.canEnable(owner, v)) == "MOVING", "camp: rolling just above STOP_KMH is still moving")
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
check(driven.parts.Heater:getModData().active == true and driven.parts.Heater:getModData().temperature == 15,
    "camp: heater back on after the shut-off switched it off (auto climate: 10 C outside -> +15)")
md(driven).camp = nil
MinidoracatVehicleManagerAPI = { canUse = function() return false, "NO_RIGHTS" end }
cmds.campOn(driver, { vid = driven:getId() })
check(md(driven).camp == nil and F.lastSent("deny").args.reason == "NOT_OWNER",
    "camp: VehicleManager refusal wins over a key in the ignition")
MinidoracatVehicleManagerAPI = nil
cmds.campOn(driver, { vid = driven:getId() })
check(md(driven).camp ~= nil and driven.shutOffs == 1,
    "camp: key left in the ignition after shutdown -> the seated player enables (no second shut-off)")
check(md(driven).camp.by == "driver", "camp: the account that turned it on is kept (notifications)")
md(driven).camp = nil
local guest = F.player("owner", { vehicle = driven, num = 1 }) -- split-screen guest named like an account
driven.driver = guest
cmds.campOn(guest, { vid = driven:getId() })
check(md(driven).camp ~= nil and md(driven).camp.by == nil,
    "camp by a split-screen guest: on, but no account to notify (its name is the client's own pick)")
md(driven).camp, driven.driver = nil, driver

-- ---- exclusive with sentry ----
md(v).sentry = { by = "owner", at = F.hours, kwh = kwh(v), since = F.hours }
cmds.campOn(owner, { vid = v:getId() })
local heater = v.parts.Heater:getModData()
check(md(v).camp ~= nil and md(v).sentry == nil, "camp: on, sentry cleared")
check(heater.active == true and heater.temperature == 15 and heater.auto == 15 and v.needParts == true,
    "camp: heater on with auto climate (10 C outside -> knob stop +15), parts update on")

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
-- plugged into a powered charger (Battery.onCharger): the heater runs on the charger
md(v).chg = { x = 1, y = 1, z = 0, power = "grid" }
local c0, t0 = kwh(v), pc.temperature
for _ = 1, 5 do T.Update.Heater(v, v.parts.Heater, 1) end
check(kwh(v) == c0 and pc.temperature == t0 + 5, "heater on a powered charger: still heats, takes nothing from the pack")
md(v).chg.power = nil
T.Update.Heater(v, v.parts.Heater, 1)
check(math.abs((c0 - kwh(v)) - C.HEATER_KW / 60) < 1e-6, "heater on an unpowered charger: the pack pays")
md(v).chg = nil

-- ---- HEPA / Bioweapon Defense Mode: more than 5 corpses outside (Java left a corpse rate), someone inside ----
local units = 48 * 1 * 90 * 60 / 1440 -- one game minute at 90 min/day
local hy = F.track(F.vehicle({ pct = 60, running = true })) -- Model Y: Specs hepa
local rider0 = F.player("rider0", { vehicle = hy, sick = 10, sickRate = 0.001 })
hy.seats[0], hy.passengers = rider0, 1
local hyh = hy.parts.Heater:getModData()
hyh.active, hyh.temperature = true, 15
T.Update.Heater(hy, hy.parts.Heater, 1)
check(H.near(10 - rider0.sick, 0.001 * units, 1e-9), "HEPA: climate running -> this minute's corpse sickness taken back")
hyh.active = false
local s0, e0 = rider0.sick, kwh(hy)
T.Update.Heater(hy, hy.parts.Heater, 1)
check(rider0.sick == s0 and kwh(hy) == e0, "HEPA: climate off, BDM off -> sickness stays (as now), nothing drawn")
md(hy).bdm = true
T.Update.Heater(hy, hy.parts.Heater, 1)
check(H.near(s0 - rider0.sick, 0.001 * units, 1e-9) and H.near(e0 - kwh(hy), C.HEATER_KW / 60, 1e-9),
    "BDM on, climate off: the fan filters anyway and draws the climate's 1.5 kW")
hyh.active, hyh.temperature = true, 0
local s1, e1 = rider0.sick, kwh(hy)
T.Update.Heater(hy, hy.parts.Heater, 1)
check(H.near(s1 - rider0.sick, 0.001 * units, 1e-9) and H.near(e1 - kwh(hy), C.HEATER_KW / 60, 1e-9),
    "BDM on, knob at 0: filters, one 1.5 kW draw (not two)")
hyh.temperature = 15
local e2 = kwh(hy)
T.Update.Heater(hy, hy.parts.Heater, 1)
check(H.near(e2 - kwh(hy), C.HEATER_KW / 60, 1e-9), "BDM on with the climate running: still one 1.5 kW draw")
hy.running = false -- parked, no camp: no power for the fan
local s2 = rider0.sick
T.Update.Heater(hy, hy.parts.Heater, 1)
check(rider0.sick == s2, "BDM on, motor off and no camp: nothing filtered")
hy.running = true
rider0.sickRate = 0 -- 5 corpses or fewer: Java's own recovery runs, nothing to take back
T.Update.Heater(hy, hy.parts.Heater, 1)
check(rider0.sick == s2, "HEPA: no corpse rate -> nothing removed")
rider0.sickRate = 0.001
-- the first update after the parts stopped updating hands in the whole stopped time (VehicleParts.java:381-386):
-- filter and draw for T.MAX_ELAPSED minutes at most, like Update.Battery
local s3, e3 = rider0.sick, kwh(hy)
T.Update.Heater(hy, hy.parts.Heater, 600)
check(H.near(s3 - rider0.sick, 0.001 * units * T.MAX_ELAPSED, 1e-9) and H.near(e3 - kwh(hy), C.HEATER_KW * T.MAX_ELAPSED / 60, 1e-9),
    "an update handing in 600 minutes: filters and draws for T.MAX_ELAPSED (10) minutes only")
local m3 = F.track(F.vehicle({ pct = 60, running = true, script = "Base.MinidoracatTesla_Model3" }))
local rider3 = F.player("rider3", { vehicle = m3, sick = 10, sickRate = 0.001 })
m3.seats[0], m3.passengers = rider3, 1
m3.parts.Heater:getModData().active, m3.parts.Heater:getModData().temperature = true, 15
md(m3).bdm = true -- even if a modified client had set it
T.Update.Heater(m3, m3.parts.Heater, 1)
check(rider3.sick == 10, "Model 3 (no HEPA in its manuals): climate running and bdm set -> no filtering")
-- the `bdm` command: anyone inside a car with HEPA, toggles md.bdm
md(m3).bdm = nil
cmds.bdm(rider3, { vid = m3:getId() })
check(md(m3).bdm == nil, "bdm on a Model 3: ignored")
md(hy).bdm = nil
local outside = F.player("outside")
F.sent = {}
cmds.bdm(outside, { vid = hy:getId() })
check(md(hy).bdm == nil and F.lastSent("deny").args.reason == "NOT_INSIDE", "bdm from outside the car: NOT_INSIDE")
MinidoracatVehicleManagerAPI = { canUse = function() return false, "NOT_SHARED" end }
cmds.bdm(rider0, { vid = hy:getId() })
check(md(hy).bdm == nil and F.lastSent("deny").args.reason == "NOT_OWNER", "bdm with VehicleManager refusing PASSENGER: NOT_OWNER")
MinidoracatVehicleManagerAPI = { canUse = function() return true, "UNCLAIMED" end }
local tx0 = hy.transmits
cmds.bdm(rider0, { vid = hy:getId() })
check(md(hy).bdm == true and hy.transmits == tx0 + 1, "bdm by a passenger: on, synced (an unclaimed car passes VehicleManager)")
MinidoracatVehicleManagerAPI = nil
cmds.bdm(rider0, { vid = hy:getId() })
check(md(hy).bdm == nil, "bdm again: off (no field)")
T.Remote = savedRemote

-- ---- auto climate: cool in summer, follow the outside air, the player's knob wins ----
local hot = F.track(F.vehicle({ pct = 60 }))
local hp = F.player("hp", { keys = { [hot.keyId] = true }, vehicle = hot })
hot.passengers, hot.seats[0], hot.driver = 1, hp, hp
F.air = 35
cmds.campOn(hp, { vid = hot:getId() })
local hh, hpc = hot.parts.Heater:getModData(), hot.parts.PassengerCompartment:getModData()
check(md(hot).camp ~= nil and hh.temperature == -15 and hh.auto == -15,
    "auto climate: 35 C outside -> cool, knob stop -15 (cabin about 20 C, not +15 on top of 35)")
local h0 = kwh(hot)
for _ = 1, 5 do T.Update.Heater(hot, hot.parts.Heater, 1) end
check(hpc.temperature == -5 and kwh(hot) < h0, "auto climate: cabin cools 1 per game minute, pack pays")
F.air = 29
local tx = hot.transmits
T.Update.Heater(hot, hot.parts.Heater, 1)
check(hh.temperature == -8 and hh.auto == -8 and hot.transmits > tx, "auto climate: evening 29 C -> -8, heater synced")
hh.temperature = 8 -- the player turns the knob (vanilla toggleHeater, VehicleCommands.lua:91-99)
F.air = 35
T.Update.Heater(hot, hot.parts.Heater, 1)
check(hh.temperature == 8 and hh.auto == nil, "auto climate: a knob turn is the player's, auto stops")
cmds.campOff(hp, { vid = hot:getId() })
cmds.campOn(hp, { vid = hot:getId() })
check(hh.temperature == 8 and hh.auto == nil, "auto climate: next camp keeps the player's knob")
cmds.campOff(hp, { vid = hot:getId() })
hh.temperature, F.air = 0, 22
cmds.campOn(hp, { vid = hot:getId() })
local z0 = kwh(hot)
T.Update.Heater(hot, hot.parts.Heater, 1)
check(hh.temperature == 0 and hh.auto == 0 and kwh(hot) == z0, "auto climate: 22 C outside -> knob 0, no draw")
F.air = 10

-- ---- screen: boredom eases for everyone awake inside ----
hp.boredom = 50
local rider = F.player("rider2", { vehicle = hot, boredom = 50 })
rider.asleep, hot.seats[1] = true, rider
C.onEngineUpdate(hot, hot.parts.GasTank, 1)
local per = C.BOREDOM_RATE * 48 * 90 * 60 / 1440 -- one game minute at 90 min/day = 180 multiplier units
check(math.abs((50 - hp.boredom) - per) < 1e-9 and rider.boredom == 50,
    "screen: awake occupant loses BOREDOM_RATE x 180 units per game minute, sleeper unchanged")

-- ---- sleeping while camping: average bed on both ends ----
check(C.bedType(hp, hot) == "averageBed", "bed: camping -> average bed")
hot.seatTags = { [0] = { PILLOW = true } }
check(C.bedType(hp, hot) == "averageBedPillow", "bed: pillow on the seat -> average bed with pillow")
F.fire("OnClientCommand", "player", "onVehicleSleep", hp, { id = 1, isAsleep = true })
check(hp.bedType == "averageBedPillow", "bed: server copy set on player/onVehicleSleep")
cmds.campOff(hp, { vid = hot:getId() })
check(C.bedType(hp, hot) == nil, "bed: no camp -> vanilla decides")
F.fire("OnClientCommand", "player", "onVehicleSleep", hp, { id = 1, isAsleep = true })
check(hp.bedType == "averageBed", "bed: car sleep without camp -> server default back")

-- ---- sandbox low-battery limit (10-20 %) ----
check(C.minPct() == 20, "limit: default 20")
T.Battery.set(hot, hot.parts.GasTank, 75 * 0.15)
check(select(2, C.canEnable(hp, hot)) == "CAMP_LOW_BATTERY", "limit: 15% < 20 -> CAMP_LOW_BATTERY")
SandboxVars.MinidoracatTesla = { CampMinBattery = 10 }
check(C.minPct() == 10 and C.canEnable(hp, hot) == true, "limit: sandbox 10 -> 15% may camp")
SandboxVars.MinidoracatTesla.CampMinBattery = 5
check(C.minPct() == 10, "limit: clamped to 10")
SandboxVars.MinidoracatTesla.CampMinBattery = 10
cmds.campOn(hp, { vid = hot:getId() })
F.sent, F.online = {}, { owner, hp }
T.Battery.set(hot, hot.parts.GasTank, 75 * 0.099)
C.onEngineUpdate(hot, hot.parts.GasTank, 1)
check(md(hot).camp == nil and F.lastSent("alert") and F.lastSent("alert").args.pct == 10,
    "limit: below the sandbox 10% turns camp off, alert carries 10")
-- on a powered charger the pack does not drain: camp may start and stays on below the limit
T.Battery.set(hot, hot.parts.GasTank, 75 * 0.05)
md(hot).chg = { x = 1, y = 1, z = 0, power = "generator" }
check(C.canEnable(hp, hot) == true, "limit: 5% pack on a powered charger may camp")
cmds.campOn(hp, { vid = hot:getId() })
C.onEngineUpdate(hot, hot.parts.GasTank, 1)
check(md(hot).camp ~= nil, "limit: 5% pack on a powered charger keeps camping")
md(hot).chg.power = nil
C.onEngineUpdate(hot, hot.parts.GasTank, 1)
check(md(hot).camp == nil, "limit: charger loses power -> the camp limit applies again")
md(hot).chg = nil
SandboxVars.MinidoracatTesla = nil

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
check(idle.parts.Battery.item.uses >= 0.99 and math.abs((five0 - kwh(idle)) - 0.5 * T.Specs["Base.MinidoracatTesla_ModelY"].v12Kwh) < 1e-9,
    "12V: DC-DC at 5% pack, camp off: refilled, pack pays 0.5 x the 12V kWh")
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
check(F.lastSent("alert") ~= nil and F.lastSent("alert").args.kind == "lowBattery" and F.lastSent("alert").args.what == "camp"
    and F.lastSent("alert").args.pct == 20, "camp: owner alerted on low battery (pct 20 for the card)")

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
