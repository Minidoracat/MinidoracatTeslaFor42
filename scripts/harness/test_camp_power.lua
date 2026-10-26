-- 露營插座與車內燈：充電條件（車上、露營中、電量門檻、充滿）、扣電量換算（滿充與中斷時按時間）、
-- 原始動作在露營關掉時被伺服器拒、不在身上的物品不充；車內燈隨露營開關、哨兵閃燈不碰它、零件 init 的光參數。
local F = dofile("scripts/harness/park_fakes.lua")
local check = (H and H.check) or function(ok, label) print((ok and "  PASS  " or "  FAIL  ") .. label); if not ok then error(label) end end

local synced = 0
syncItemFields = function() synced = synced + 1 end

require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/Battery"
require "MinidoracatTesla/Inbox"
require "MinidoracatTesla/Sentry"
require "MinidoracatTesla/CampPower"
require "MinidoracatTesla/Camp"
local T = MinidoracatTesla
local C = T.Camp
local A = ISMinidoracatTeslaChargeItem
T.Packs["Base.MinidoracatTesla_TestPack"] = 75
getGameTime().getMinutesPerDay = function() return 90 end

local function item(full, uses)
    return { full = full, uses = uses,
        getFullType = function(s) return s.full end,
        getCurrentUsesFloat = function(s) return s.uses end,
        setUsedDelta = function(s, d) s.uses = d end }
end
local function seated(name, v, items)
    local p = F.player(name, { vehicle = v, keys = { [v.keyId] = true } })
    local inv = p:getInventory()
    local owned = {}
    for _, it in ipairs(items or {}) do owned[it] = true end
    inv.containsRecursive = function(_, it) return owned[it] == true end
    p.getInventory = function() return inv end
    p.isTimedActionInstant = function() return false end
    return p
end
local function kwh(v) return T.Battery.kwh(v.parts.GasTank) end
local function cabinLight(v)
    local l = { on = false }
    function l:getId() return "CabinLight" end
    function l:setLightActive(b) self.on = b end
    function l:createSpotLightColor(...) self.spot = { ... } end
    v.parts.CabinLight = l
    v.lights[#v.lights + 1] = l
    return l
end

local v = F.track(F.vehicle({ pct = 60 }))
local light = cabinLight(v)
local cell, car = item("Base.Battery", 0.4), item("Base.CarBattery2", 0.5)
local p = seated("owner", v, { cell, car })

-- ---- rules ----
check(select(2, C.canChargeItem(F.player("out", {}), v, cell)) == "NOT_INSIDE", "outlet: must be seated in this car")
check(select(2, C.canChargeItem(p, v, cell)) == "NOT_CAMPING", "outlet: camp off -> NOT_CAMPING")
check(C.Chargeable["Base.Battery"] and C.Chargeable["Base.CarBattery1"] and C.Chargeable["Base.CarBattery3"]
    and not C.Chargeable["Base.Lighter_Battery"], "outlet: dry cells and the three car batteries only")
T.ServerCommands.campOn(p, { vid = v:getId() })
check(v.parts.GasTank:getModData().camp ~= nil and light.on == true, "light: camp on -> cabin light on")
check(C.canChargeItem(p, v, cell) == true, "outlet: camping, seated, pack above the limit -> ok")
check(select(2, C.canChargeItem(p, v, item("Base.Battery", 1))) == "FULL", "outlet: full item -> FULL")
T.Battery.set(v, v.parts.GasTank, 75 * (C.minPct() - 0.5) / 100)
check(select(2, C.canChargeItem(p, v, cell)) == "CAMP_LOW_BATTERY", "outlet: pack below the camp limit -> CAMP_LOW_BATTERY")
v.parts.GasTank:getModData().chg = { x = 1, y = 1, z = 0, power = "grid" }
check(C.canChargeItem(p, v, cell) == true, "outlet: pack below the limit but on a powered charger -> ok")
local need, kc = C.itemNeed(cell), kwh(v)
check(H.near(C.chargeItem(p, v, cell, nil), need, 1e-12) and kwh(v) == kc, "outlet on a powered charger: the item fills, the pack pays nothing")
cell.uses = 0.4
v.parts.GasTank:getModData().chg = nil
T.Battery.set(v, v.parts.GasTank, 45)

-- ---- kWh: capacity x missing fraction; duration from the charging power ----
check(H.near(C.itemNeed(cell), 0.6 * 0.003, 1e-12) and H.near(C.itemNeed(car), 0.5 * 0.72, 1e-12),
    "outlet: need = (1 - charge) x capacity (cell 3 Wh, car battery 0.72 kWh)")
local a = A:new(p, v, car)
check(H.near(a.maxTime, 2.5 * 60 * 90 * 2, 1e-6), "outlet: half a car battery = 2.5 h at 0.144 kW (ISReadABook time units)")

-- ---- completed: the whole need moves from the pack ----
local k0, s0 = kwh(v), synced
a:serverStart()
check(a:isValid() == true, "action: valid while camping")
a:complete()
check(H.near(car.uses, 1, 1e-9) and H.near(k0 - kwh(v), 0.36, 1e-9) and synced == s0 + 1,
    "action complete: car battery full, pack -0.36 kWh, item synced")
a:serverStop()
check(H.near(k0 - kwh(v), 0.36, 1e-9), "action: stop after complete moves nothing more")

-- ---- interrupted: charging time so far ----
car.uses = 0.5
local b = A:new(p, v, car)
k0 = kwh(v)
b:serverStart()
F.hours = F.hours + 1
b:serverStop()
check(H.near(car.uses, 0.7, 1e-9) and H.near(k0 - kwh(v), 0.144, 1e-9), "action stopped after 1 h: +0.144 kWh (12 V x 12 A)")
local c = A:new(p, v, cell)
c:serverStart()
F.hours = F.hours + 10
c:serverStop()
check(H.near(cell.uses, 1, 1e-9), "action stopped late: capped at what the cell needs")

-- whole uses: a dry cell keeps multiples of UseDelta 0.007 (DrainableComboItem.java:83-87); the pack pays the gain
local q = item("Base.Battery", 0.5)
q.setUsedDelta = function(s, d) s.uses = math.floor(math.min(1, d) / 0.007 + 0.5) * 0.007 end
q:setUsedDelta(0.5)
local q0, k1 = q.uses, kwh(v)
check(C.chargeItem(p, v, q, 0.005) == 0 and q.uses == q0 and kwh(v) == k1,
    "whole uses: under half a use gained -> nothing paid")
local got = C.chargeItem(p, v, q, 1)
check(got > 0 and H.near(got, (q.uses - q0) * 0.003, 1e-12) and H.near(k1 - kwh(v), got, 1e-12),
    "whole uses: the pack pays what the cell actually gained")

-- ---- refused: camp off, item not on the player ----
local stray = item("Base.CarBattery1", 0.2)
local d = A:new(p, v, stray)
k0 = kwh(v)
d:serverStart()
d:complete()
check(stray.uses == 0.2 and kwh(v) == k0, "action: item not in the player's inventory -> nothing moves")

F.sent = {}
T.ServerCommands.campOff(p, { vid = v:getId() })
check(v.parts.GasTank:getModData().camp == nil and light.on == false, "light: camp off -> cabin light off")
car.uses = 0.5
local e = A:new(p, v, car)
check(e:isValid() == false, "action: invalid once camp is off (client stops it)")
k0 = kwh(v)
e:serverStart()
e:complete()
check(car.uses == 0.5 and kwh(v) == k0 and F.lastSent("deny").args.reason == "NOT_CAMPING",
    "action: raw request with camp off -> server denies NOT_CAMPING, nothing moves")

-- SP: start() / stop() do the server's part (isClient false, isServer false)
local sp = isServer
isServer = function() return false end
T.ServerCommands.campOn(p, { vid = v:getId() })
local f = A:new(p, v, car)
f:start()
F.hours = F.hours + 0.5
f:stop()
check(H.near(car.uses, 0.6, 1e-9) and f.stopped, "SP: stop() after 0.5 h moves 0.072 kWh")
isServer = sp

-- ---- light: other paths, sentry flash, part init ----
v.passengers, p.vehicle = 0, nil
C.onEngineUpdate(v, v.parts.GasTank, 1)
check(light.on == false, "light: camp auto-off (cabin empty) -> light off")
light.on = true
local st = T.Sentry.stats
local saved = { st.flashes, st.tickAdds, st.tickRemoves } -- test_sentry counts from zero
T.Sentry.flash(v, 2)
F.runTicks(50)
st.flashes, st.tickAdds, st.tickRemoves = saved[1], saved[2], saved[3]
check(light.on == true and v.parts.HeadlightLeft.lightActive == false, "sentry flash toggles headlights only, not the cabin light")
T.Init.CabinLight(v, light)
local s = light.spot
check(s[5] == -1 and s[3] == C.LIGHT_DIST and s[4] == C.LIGHT_INTENSITY and s[7] == 1 and s[8] < s[7] and s[9] < s[8],
    "light init: all-round (dot -1), warm white")

F.done()
