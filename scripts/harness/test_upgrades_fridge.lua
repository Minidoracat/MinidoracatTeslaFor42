-- Car fridge (server Fridge.lua, Upgrades.lua F.step / F.canSet, client FridgeUI.lua): one food's state over time
-- (F.step: freezing, thawing, ageing; one catch-up == many ten-minute settles), the cool and freeze rates from each
-- food's baseline, new food only getting one, the item flags never read back (nor left frozen with no freezing time),
-- the cap on tracked food, frozen eggs (also when one catch-up froze and thawed them), the 20 % cut-off told once,
-- charger hours free, the catch-up on load, the late registration of a car loaded at id -1, every guard of command
-- `fridge`, the off answer (`fridgeFoodPull` -> `fridgeFood`: who gets one, what is in it) and the client copy (only
-- on a page that can be seen; on: once per food instance per settle; off: when it asks, which answer it takes).
local F = dofile("scripts/harness/park_fakes.lua")
local check, near = H.check, H.near
H.stub("Definitions/ContainerButtonIcons")
H.require("MinidoracatTesla/Inbox")
H.require("MinidoracatTesla/Fridge")
local T = MinidoracatTesla
local FR, B = T.Fridge, T.Battery
T.Packs["Base.MinidoracatTesla_TestPack"] = 75
local realCharge = T.Charge
T.Charge = { powerUntil = function(chg, t) return chg and chg.power and t or nil end } -- plugged = powered now
local ROOM, COOL = 1 / 24, 0.2 / 24 -- per hour at the default sandbox (FoodRotSpeed 3 = 1.0, FridgeFactor 3 = 0.2)

local Food = { _class = "Food" }
Food.__index = Food
function Food:getID() return self.id end
function Food:getAge() return self.age end
function Food:setAge(a) self.age = a end
function Food:getFreezingTime() return self.ft end
function Food:setFreezingTime(x) self.ft = x end
function Food:isFrozen() return self.fr end
function Food:setFrozen(b) self.fr = b end
function Food:canBeFrozen() return self.freezable end
function Food:getOffAgeMax() return self.offMax end
function Food:isFertilized() return self.fert end
function Food:setFertilized(b) self.fert = b end
-- the engine's own pass in a vehicle container: room rate since the last, nothing while frozen (Food.java:739-776)
function Food:updateAge()
    if not self.fr then self.age = self.age + (F.hours - self.last) * ROOM end
    self.last = F.hours
end
local function food(id, o)
    o = o or {}
    return setmetatable({ id = id, age = o.age or 0, ft = o.ft or 0, fr = o.fr or false, freezable = o.freezable ~= false,
        offMax = o.offMax or 5, fert = o.fert or false, last = F.hours }, Food)
end
local function fit(v, items)
    local p = { md = {}, items = items or {}, item = { getFullType = function() return "Base.MinidoracatTesla_Fridge" end } }
    function p:getId() return "TeslaFridge" end
    function p:getIndex() return 8 end
    function p:getModData() return self.md end
    function p:getInventoryItem() return self.item end
    function p:getItemContainer()
        local list = self.items
        return { getItems = function() return F.list(list) end,
            contains = function(_, it) for _, x in ipairs(list) do if x == it then return true end end return false end }
    end
    -- the part's ContainerAccess test (BaseVehicle.canAccessContainer): true unless a test blocks that player
    v.canAccessContainer = v.canAccessContainer
        or function(self, i, chr) self.access = i; return not (self.blocked and self.blocked[chr]) end
    function p:getVehicle() return v end
    v.parts.TeslaFridge = p
    return p
end
local function remove(list, it) for i = #list, 1, -1 do if list[i] == it then table.remove(list, i) end end end
local function kwh(v) return B.kwh(B.part(v)) end
local function chg(v) return B.part(v):getModData() end
local function tick(h) F.hours = F.hours + h; H.fire("EveryTenMinutes") end
local function denied() local s = F.lastSent("deny"); return s and s.args.reason end
local function alerts(who)
    local n = 0
    for _, s in ipairs(F.sent) do
        if s.cmd == "alert" and s.to == who and s.args.kind == "lowBattery" and s.args.what == "fridge" then n = n + 1 end
    end
    return n
end
-- a load after time away: unlisted and not loaded meanwhile (no ticks, no engine passes), back under a new id
local function unload(car) F.vehicles[car:getId()] = nil; FR.cars[car:getId()] = nil end
local function reload(car, id) car.id = id; F.track(car); H.fire("OnSpawnVehicleEnd", car) end

H.section("Fridge: one food over time (F.step)")
local function same(x, y) return near(x.age, y.age, 1e-9) and near(x.ft, y.ft, 1e-6) and x.fr == y.fr end
local function chain(b, legs)
    for _, l in ipairs(legs) do for _ = 1, l[2] * 6 do b = FR.step(b, 1 / 6, l[1], true) end end
    return b
end
for _, c in ipairs({
    { "cool, unfrozen", { age = 1, ft = 0, fr = false }, "cool" },
    { "freeze, unfrozen", { age = 1, ft = 0, fr = false }, "freeze" },
    { "freeze, half frozen", { age = 1, ft = 50, fr = false }, "freeze" },
    { "freeze, frozen", { age = 1, ft = 100, fr = true }, "freeze" },
    { "cool, frozen", { age = 1, ft = 100, fr = true }, "cool" },
    { "cool, half thawed", { age = 1, ft = 50, fr = true }, "cool" },
    { "no power, frozen", { age = 1, ft = 100, fr = true }, nil },
}) do
    check(same(FR.step(c[2], 30, c[3], true), chain(c[2], { { c[3], 30 } })), "30 h at once == 180 ten-minute steps: " .. c[1])
end
local u = { age = 1, ft = 0, fr = false }
check(same(FR.step(FR.step(u, 12.5, "freeze", true), 17.5, nil, true), chain(u, { { "freeze", 12.5 }, { nil, 17.5 } })),
    "30 h at once == 180 ten-minute steps: freeze, power out after 12.5 h")
local r = FR.step(u, 30, "freeze", true)
check(near(r.age, 1 + 4 * COOL, 1e-12) and r.ft == 100 and r.fr, "unfrozen, 30 h freeze: 4 h at the fridge rate while freezing, then frozen, no ageing")
r = FR.step({ age = 1, ft = 100, fr = true }, 30, "cool", true)
check(near(r.age, 1 + 27 * COOL, 1e-12) and r.ft == 0 and not r.fr, "frozen, 30 h cool: thawed in 3 h (Food.java:843-846) without ageing, then the fridge rate")
r = FR.step({ age = 1, ft = 100, fr = true }, 30, nil, true)
check(near(r.age, 1 + 28.5 * ROOM, 1e-12) and r.ft == 0 and not r.fr, "frozen, 30 h no power: thawed in 1.5 h, then room rate")
r = FR.step({ age = 1, ft = 50, fr = false }, 1, "cool", true)
check(near(r.age, 1 + COOL, 1e-12) and near(r.ft, 50 - 100 / 3, 1e-9) and not r.fr, "half frozen (never frozen), 1 h cool: thawing and ageing at once")
r = FR.step({ age = 1, ft = 0, fr = false }, 30, "freeze", false)
check(near(r.age, 1 + 30 * COOL, 1e-12) and r.ft == 0 and not r.fr, "cannot freeze, 30 h freeze: the fridge rate, ft untouched")

H.section("Fridge: cool")
local v = F.track(F.vehicle({ pct = 80 }))
local owner, other = F.player("owner", { keys = { [v.keyId] = true } }), F.player("other", { keys = { [v.keyId] = true } })
F.online = { owner, other }
local a, b, shelf = food(101, { age = 1 }), food(102, { age = 1, freezable = false }), food(199, { age = 1 })
local fp = fit(v, { a, b })
T.ServerCommands.fridge(owner, { vid = v:getId(), mode = "cool" })
local s = fp.md.fridge
check(s and s.mode == "cool" and s.by == "owner" and s.at == F.hours and s.items["101"] and s.items["102"]
    and FR.cars[v:getId()], "owner switches on: state by owner, every food has a baseline (keyed by item id), car listed")
local k0 = kwh(v)
for i = 1, 10 do
    F.hours = F.hours + 0.5
    a:updateAge(); shelf:updateAge() -- the engine ages it at room rate between settles
    tick(0.5)
end
shelf:updateAge()
check(near(a.age - 1, 10 * COOL, 1e-9) and near((a.age - 1) / (shelf.age - 1), 0.2, 1e-9),
    "10 h cool: age from the baseline at the fridge factor (0.2 of the shelf's), the engine's room-rate passes undone")
check(near(k0 - kwh(v), 10 * FR.KW, 1e-9), "10 h on: 0.6 kWh off the pack (60 W)")
local before = a.age
FR.settle(v)
check(a.age == before and s.items["101"].age == before, "settled twice at the same hour: nothing moves (dt 0 keeps the baseline)")
a.fr, a.ft = true, 100 -- a client's word on the item (isFrozen rides in ItemStatsPacket)
tick(1)
check(not a.fr and a.ft == 0 and near(a.age, before + COOL, 1e-9) and not s.items["101"].fr,
    "food with a baseline: the item's frozen flag is not read back (it ages on at the fridge rate)")

H.section("Fridge: freeze")
T.ServerCommands.fridge(other, { vid = v:getId(), mode = "freeze" })
check(s.mode == "freeze" and s.by == "owner", "another key holder switches to freeze: mode changes, the low-battery note still goes to owner")
local a0, b0 = a.age, b.age
tick(2)
check(near(a.ft, 50, 1e-9) and not a.fr and near(a.age - a0, 2 * COOL, 1e-9), "2 h freeze: half frozen, still ageing at the fridge rate")
tick(2)
check(near(a.ft, 100, 1e-9) and a.fr, "4 h: frozen (FREEZE_HOURS)")
local frozenAge = a.age
a.fr = false; a.ft = 60 -- the engine thaws it in a vehicle container between settles
tick(5)
check(a.age == frozenAge and a.fr and a.ft == 100, "frozen and powered: no ageing, kept frozen against the engine's thaw")
check(b.ft == 0 and not b.fr and near(b.age - b0, 9 * COOL, 1e-9), "food that cannot freeze: the fridge rate, never frozen")
T.ServerCommands.fridge(owner, { vid = v:getId(), mode = "cool" })
tick(1.5)
check(a.age == frozenAge and a.fr and near(a.ft, 50, 1e-9), "cool with frozen food: half thawed after 1.5 h, no ageing while frozen")
tick(2.5)
check(not a.fr and a.ft == 0 and near(a.age, frozenAge + COOL, 1e-9), "thawed at 3 h: then the fridge rate (1 h of the 4)")

H.section("Fridge: new and moved food")
local c = food(103, { age = 2 })
fp.items[#fp.items + 1] = c
F.hours = F.hours + 1
c:updateAge()
tick(0) -- the settle after it went in
check(near(c.age, 2 + ROOM, 1e-9) and near(s.items["103"].age, c.age, 1e-9), "new food: only a baseline (the engine's room rate stands)")
tick(2)
check(near(c.age, 2 + ROOM + 2 * COOL, 1e-9), "from its baseline on: the fridge rate")
-- planted: a settle that books every food, baseline or not, would back-date it: the check above goes red on it
local src = io.open("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/server/MinidoracatTesla/Fridge.lua"):read("a")
local bad, n = src:gsub("local b, was = old%[k%], nil", "local b, was = old[k] or { age = it:getAge(), ft = it:getFreezingTime(), fr = it:isFrozen() }, nil")
local real = { settle = FR.settle, setMode = FR.setMode, track = FR.track, untrack = FR.untrack, cars = FR.cars,
    late = FR.late, cmd = T.ServerCommands.fridge }
local noEvents = setmetatable({}, { __index = function() return { Add = function() end, Remove = function() end } end })
load(bad, "@planted", "t", setmetatable({ Events = noEvents }, { __index = _G }))()
local mutant = FR.settle
for key, fn in pairs(real) do if key == "cmd" then T.ServerCommands.fridge = fn else FR[key] = fn end end
local d = food(104, { age = 2 })
fp.items[#fp.items + 1] = d
F.hours = F.hours + 1
d:updateAge()
mutant(v)
check(n == 1 and not near(d.age, 2 + ROOM, 1e-9), "planted: without the baseline check the new food is back-dated (the check above catches it)")
remove(fp.items, d)
FR.settle(v)
check(s.items["104"] == nil, "food taken out: its baseline goes")
remove(fp.items, c)
tick(1)
c.last = F.hours - 3; c:updateAge() -- three hours on the shelf
local outside = c.age
fp.items[#fp.items + 1] = c
tick(0)
check(s.items["103"] and c.age == outside, "back in the fridge: a fresh baseline, never rolled back to the old one")
local claimed, real100 = food(106, { age = 1, fr = true }), food(107, { age = 1, ft = 100, fr = true })
fp.items[#fp.items + 1] = claimed
fp.items[#fp.items + 1] = real100
tick(0)
check(s.items["106"].fr == false and s.items["107"].fr == true,
    "new food: frozen in its baseline only with freezing time to show for it (a bare isFrozen is not taken)")
remove(fp.items, claimed); remove(fp.items, real100)
tick(0)

H.section("Fridge: fertilized eggs (dead once freezing, Food.isFreezing: can freeze, in a powered freezer; Food.java:837-838, 2188-2190)")
local eggCar = F.track(F.vehicle({ pct = 80 }))
local egg, hard = food(601, { fert = true }), food(603, { fert = true, freezable = false })
local eggPart = fit(eggCar, { egg, hard })
FR.setMode(eggCar, "freeze", "owner")
check(not egg.fert and egg.ft == 0 and hard.fert,
    "switched on in freeze (the first settle: only a baseline, ft 0): dead at once; one that cannot freeze: not")
remove(eggPart.items, egg)
check(not egg.fert, "taken out within the first ten minutes: dead all the same")
local late = food(604, { fert = true })
eggPart.items[#eggPart.items + 1] = late
tick(1 / 6)
check(not late.fert and late.ft == 0, "put in a running freezer: dead at the first settle that sees it (its baseline only, ft 0)")
local coolCar = F.track(F.vehicle({ pct = 80 }))
local warm = food(602, { fert = true })
fit(coolCar, { warm })
FR.setMode(coolCar, "cool", "owner")
tick(1)
check(warm.fert and warm.ft == 0, "cool an hour: still fertilized")
local tx0 = coolCar.transmits
FR.setMode(coolCar, "freeze", "owner")
check(not warm.fert and warm.ft == 0 and coolCar.transmits == tx0 + 2,
    "cool -> freeze: dead at the switch, before any freezing time (one transmit for the old mode's settle, one for the switch)")
FR.setMode(eggCar, false); FR.setMode(coolCar, false)
check(eggPart.md.fridge == nil and eggPart.md.fridgeLast == nil, "switched off: the state goes, nothing kept")
local deadCar = F.track(F.vehicle({ pct = 20 })) -- at the floor: may switch on, pays for nothing
local deadPart = fit(deadCar, {})
FR.setMode(deadCar, "freeze", "owner")
local cold = food(606, { fert = true })
deadPart.items[1] = cold
tick(1)
check(deadPart.md.fridge == nil and cold.fert,
    "freeze mode but no power the whole stretch (off for low battery in the settle that first sees it): still fertilized")
FR.untrack(eggCar)
for _, c in ipairs({ eggCar, coolCar, deadCar }) do F.vehicles[c:getId()] = nil end

H.section("Fridge: at most F.MAX_ITEMS foods")
check(FR.MAX_ITEMS == 400, "F.MAX_ITEMS is 400")
local big = F.track(F.vehicle({ pct = 80 }))
local list = {}
for i = 1, 2400 do list[i] = food(10000 + i, { offMax = 1000000000 }) end -- feathers: never spoil (Food.java:1140-1141)
for i = 1, 500 do list[2400 + i] = food(20000 + i, { age = 1 }) end
local bigPart = fit(big, list)
local fullLogs, realPrint = 0, print
print = function(m) if tostring(m):find("fridge full", 1, true) then fullLogs = fullLogs + 1 end end
local function tracked()
    local k, spoils = 0, true
    for id in pairs(bigPart.md.fridge.items) do k = k + 1; if tonumber(id) < 20000 then spoils = false end end
    return k, spoils
end
FR.setMode(big, "cool", "owner")
tick(1)
local k, spoils = tracked()
local items = bigPart.md.fridge.items
check(k == 400 and spoils and items["20001"] and items["20400"] and not items["20401"],
    "2,400 feathers + 500 foods: the first 400 that spoil tracked, no feather")
check(near(list[2401].age, 1 + COOL, 1e-9) and list[2900].age == 1, "tracked food at the fridge rate; the 500th left to the engine")
check(fullLogs == 1, "full: one log line over two settles")
local keep = {}
for i, it in ipairs(list) do if i <= 2400 or i > 2450 then keep[#keep + 1] = it end end -- 50 tracked taken out
bigPart.items = keep
tick(1)
k, spoils = tracked()
items = bigPart.md.fridge.items
check(k == 400 and spoils and not items["20001"] and items["20450"] and not items["20451"],
    "50 taken out: 400 again, the next 50 in container order get baselines")
check(fullLogs == 1, "still full: no second log")
keep = {}
for i, it in ipairs(bigPart.items) do if i <= 2400 + 350 then keep[#keep + 1] = it end end
bigPart.items = keep
tick(1)
k = tracked()
check(k == 350 and bigPart.md.fridge.full == nil, "350 foods: all tracked, not full")
for i = 1, 60 do keep[#keep + 1] = food(30000 + i, { age = 1 }) end
tick(1)
check(tracked() == 400 and fullLogs == 2, "full again: logged again")
print = realPrint
FR.setMode(big, false)
F.vehicles[big:getId()] = nil

H.section("Fridge: charger")
local cs = chg(v)
cs.chg = { power = "grid" }
k0 = kwh(v)
tick(2)
check(kwh(v) == k0 and cs.chg.fed == nil, "plugged on the grid: no kWh off the pack, nothing booked to fed")
cs.chg.power = "generator"
tick(2)
check(kwh(v) == k0 and near(cs.chg.fed, 2 * FR.KW, 1e-9), "plugged on a generator: free for the car, 0.12 kWh into chg.fed")
F.hours = F.hours + 2
FR.settle(v, F.hours, F.hours - 1) -- Charging.lua settleSentry: the charger powered it only the first hour
check(near(k0 - kwh(v), FR.KW, 1e-9) and near(cs.chg.fed, 3 * FR.KW, 1e-9), "explicit freeUntil: the free hour fed, the other paid")
cs.chg = nil
T.Charge = nil
cs.chg = { power = "grid" }
k0 = kwh(v)
tick(1)
check(kwh(v) == k0, "no Charging module: onCharger decides")
cs.chg = nil
T.Charge = { powerUntil = function(ch, t) return ch and ch.power and t or nil end }

H.section("Fridge: low battery")
local lv = F.track(F.vehicle({ pct = 21 })) -- 15.75 kWh of 75; the floor 15 = 12.5 h at 60 W
local lo = F.player("lo", { keys = { [lv.keyId] = true } })
F.online = { owner, other, lo }
local e = food(105, { age = 1 })
local lp = fit(lv, { e })
T.ServerCommands.fridge(lo, { vid = lv:getId(), mode = "cool" })
local tx = 0
function lv:transmitPartModData(p) if p == lp then tx = tx + 1 end end
tick(20)
check(near(kwh(lv), 15, 1e-9) and lp.md.fridge == nil and not FR.cars[lv:getId()],
    "battery reaches 20 %: stops at the floor, switched off, unlisted")
check(near(e.age, 1 + (7.5 + 12.5 * 0.2) / 24, 1e-9), "food: 12.5 h at the fridge rate, the 7.5 h without power at room rate")
check(lp.md.fridgeLast == nil and tx == 1, "switched off in the one transmit; nothing kept for the clients (they ask)")
check(alerts("lo") == 1, "the one who switched it on hears it (lowBattery, what fridge)")
tick(5); FR.settle(lv)
check(alerts("lo") == 1, "told once: off is off")
B.part(lv):setContainerContentAmount(14.9) -- just under (at exactly 20 % it may go on again, as sentry)
T.ServerCommands.fridge(lo, { vid = lv:getId(), mode = "cool" })
check(lp.md.fridge == nil and denied() == "LOW_BATTERY", "below 20 %: cannot switch it on again")
local sent = #F.sent
T.ServerCommands.fridge(lo, { vid = lv:getId(), mode = false })
check(#F.sent == sent and lp.md.fridge == nil, "switching off below 20 %: no deny, nothing changes")
chg(lv).chg = { power = "grid" }
T.ServerCommands.fridge(lo, { vid = lv:getId(), mode = "freeze" })
check(lp.md.fridge and lp.md.fridge.mode == "freeze" and #F.sent == sent, "below 20 % on a charger: switches on")
chg(lv).chg = nil
lp.items = {}
FR.setMode(lv, false)
local gv = F.track(F.vehicle({ pct = 21 }))
local gp = fit(gv, {})
FR.setMode(gv, "cool", "owner")
local liar = food(108, { age = 1, fr = true }) -- frozen flag, no freezing time (a client's word, or a stale item)
gp.items[1] = liar
F.hours = F.hours + 20
FR.settle(gv)
check(gp.md.fridge == nil and not liar.fr,
    "new food first seen by the settle that switches it off (low battery): frozen with ft 0 cleared in the baseline and on the item")
F.vehicles[gv:getId()] = nil

H.section("Fridge: catch-up on load")
local fz, cl = F.track(F.vehicle({ pct = 80 })), F.track(F.vehicle({ pct = 80 }))
local x, y = food(301, { age = 1 }), food(302, { age = 1 })
fit(fz, { x }); local clp = fit(cl, { y })
FR.setMode(cl, "freeze", "owner")
tick(4)
check(y.fr and near(y.age, 1 + 4 * COOL, 1e-9), "setup: frozen after 4 h freeze")
FR.setMode(cl, "cool", "owner")
FR.setMode(fz, "freeze", "owner")
local x0, y0 = x.age, y.age -- x: its baseline now (the engine aged it on the shelf meanwhile)
unload(fz); unload(cl)
F.hours = F.hours + 30
reload(fz, 7101); reload(cl, 7102)
check(near(x.age, x0 + 4 * COOL, 1e-9) and x.ft == 100 and x.fr and FR.cars[7101],
    "unfrozen food, freeze, 30 h away: 4 h at the fridge rate while freezing, frozen since (listed under its new id)")
check(near(y.age, y0 + 27 * COOL, 1e-9) and y.ft == 0 and not y.fr and clp.md.fridge.at == F.hours,
    "frozen food, cool, 30 h away: thawed in 3 h, then the fridge rate")
FR.setMode(fz, false); FR.setMode(cl, false)
unload(fz); unload(cl)

H.section("Fridge: one catch-up == ten-minute settles (power out midway)")
local P, Q = F.track(F.vehicle({ pct = 21 })), F.track(F.vehicle({ pct = 21 }))
local pf, qf = food(401, { age = 1 }), food(402, { age = 1 })
local pp, qp = fit(P, { pf }), fit(Q, { qf })
FR.setMode(P, "cool", "owner"); FR.setMode(Q, "cool", "owner")
local t0 = F.hours
unload(P)
for _ = 1, 180 do tick(1 / 6) end
qf:updateAge()
F.hours = t0 + 30
reload(P, 7201)
check(near(pf.age, qf.age, 1e-9) and near(pf.age, 1 + (12.5 * 0.2 + 17.5) / 24, 1e-9) and near(kwh(P), kwh(Q), 1e-9)
    and pp.md.fridge == nil and qp.md.fridge == nil, "30 h at once == 180 settles: 12.5 h cool, then off, the same age and pack")
unload(P); unload(Q)

H.section("Fridge: a car loaded at id -1")
local lateCar, stuck = F.vehicle({ pct = 80 }), F.vehicle({ pct = 80 })
fit(lateCar, {}).md.fridge = { mode = "cool", at = F.hours, items = {} }
fit(stuck, {}).md.fridge = { mode = "cool", at = F.hours, items = {} }
lateCar.id, stuck.id = -1, -1
H.fire("OnSpawnVehicleEnd", lateCar)
H.fire("OnSpawnVehicleEnd", stuck)
check(FR.cars[-1] == nil and FR.late[lateCar] and FR.late[stuck], "loaded at id -1: not listed, on the late list")
lateCar.id = 7002
F.track(lateCar)
local cell = getCell
getCell = function() error("the whole cell swept") end
tick(1)
getCell = cell
check(FR.cars[7002] and FR.cars[-1] == nil and next(FR.late) == nil,
    "the next tick: the one with an id now listed, the one still at -1 dropped, the late list empty, no cell sweep")
F.vehicles[7002] = nil
tick(1)
check(FR.cars[7002] == nil, "a listed car no longer loaded: dropped from the list")

H.section("Fridge: command guards")
local function try(p, args) F.sent = {}; T.ServerCommands.fridge(p, args); return denied() end
check(try(owner, { vid = 99999, mode = "cool" }) == "NO_VEHICLE", "no such car: NO_VEHICLE")
check(try(owner, { vid = 1.5, mode = "cool" }) == "NO_VEHICLE", "fractional id: NO_VEHICLE")
local far = F.player("far", { keys = { [v.keyId] = true }, dist = 11 })
check(try(far, { vid = v:getId(), mode = false }) == "TOO_FAR", "11 tiles away: TOO_FAR")
far.vehicle = v
check(try(far, { vid = v:getId(), mode = false }) == nil and fp.md.fridge == nil, "seated in it (a Semi cab, any distance): allowed")
local plain = F.track(F.vehicle({ pct = 80 }))
check(try(F.player("o2", { keys = { [plain.keyId] = true } }), { vid = plain:getId(), mode = "cool" }) == "NO_FRIDGE", "no fridge fitted: NO_FRIDGE")
for _, bad in ipairs({ "boil", 1, true, {} }) do
    check(try(owner, { vid = v:getId(), mode = bad }) == nil and fp.md.fridge == nil, "mode " .. tostring(bad) .. ": ignored, no reply")
end
check(try(owner, { vid = v:getId() }) == nil and fp.md.fridge == nil, "mode missing: ignored")
local stranger = F.player("stranger")
check(try(stranger, { vid = v:getId(), mode = "cool" }) == "CAR_LOCKED" and fp.md.fridge == nil, "no key, doors locked: CAR_LOCKED")
v.locked = false
check(try(stranger, { vid = v:getId(), mode = "cool" }) == nil and fp.md.fridge, "no key, unlocked: allowed (the charge cable's rule)")
FR.setMode(v, false)
v.locked = true
MinidoracatVehicleManagerAPI = { canUse = function(_, _, perm) return false, perm == "CARGO" and "NOPE" or "?" end }
check(try(owner, { vid = v:getId(), mode = "cool" }) == "NOT_OWNER", "VehicleManager refuses CARGO: NOT_OWNER")
MinidoracatVehicleManagerAPI.canUse = function() return false, "RENT_LOCKED" end
check(try(owner, { vid = v:getId(), mode = "cool" }) == "RENT_LOCKED", "VehicleManager's own reason kept: RENT_LOCKED")
MinidoracatVehicleManagerAPI.canUse = function(p) return p == stranger, "OK" end
check(try(stranger, { vid = v:getId(), mode = "cool" }) == nil and fp.md.fridge, "VehicleManager allows: allowed without a key")
FR.setMode(v, false)
-- VehicleManager has no owner for the car (true, "UNCLAIMED", its OwnershipSystem.lua:875-877): this MOD's own rule
MinidoracatVehicleManagerAPI.canUse = function() return true, "UNCLAIMED" end
check(try(stranger, { vid = v:getId(), mode = "cool" }) == "CAR_LOCKED" and fp.md.fridge == nil,
    "unclaimed car, locked, no key: CAR_LOCKED (as without VehicleManager)")
local bagged = F.player("bagged")
local realKeys = T.Keys
T.Keys = { card = function(p) return p == bagged and {} or nil end, phoneKey = function() return nil end }
check(try(bagged, { vid = v:getId(), mode = "cool" }) == nil and fp.md.fridge, "unclaimed car, locked, key card in a bag: allowed")
T.Keys = realKeys
FR.setMode(v, false)
v.locked = false
check(try(stranger, { vid = v:getId(), mode = "cool" }) == nil and fp.md.fridge, "unclaimed car, unlocked, no key: allowed")
FR.setMode(v, false)
v.locked, v.hotwired = true, true
check(try(stranger, { vid = v:getId(), mode = "cool" }) == nil and fp.md.fridge, "unclaimed car, locked but hotwired: allowed")
FR.setMode(v, false)
v.hotwired = nil
MinidoracatVehicleManagerAPI.canUse = function() return false, "QUARANTINED" end
check(try(owner, { vid = v:getId(), mode = "cool" }) == "QUARANTINED", "claimed car, VehicleManager refuses: its reason, the key does not override it")
MinidoracatVehicleManagerAPI = nil
FR.setMode(v, false)

H.section("Fridge: removal")
FR.setMode(v, "cool", "owner")
fp.item = nil
FR.settle(v)
check(fp.md.fridge == nil and not FR.cars[v:getId()], "state left on a removed fridge: cleared at the next settle")
fp.item = { getFullType = function() return "Base.MinidoracatTesla_Fridge" end }
FR.setMode(v, "cool", "owner")
FR.setMode(v, false)
T.UninstallComplete.Fridge(v, fp)
check(fp.md.fridge == nil and not FR.cars[v:getId()], "uninstall complete: state dropped, unlisted")

H.section("Fridge: off, the food's values on request (fridgeFoodPull -> fridgeFood)")
-- the server's answer to p (the `fridgeFood` it sent), who it went to and how many commands went out; nil: none
local function pull(p, args)
    local h, n = T.ServerCommands.fridgeFoodPull, #F.sent
    if not h then return nil end
    h(p, args)
    for i = n + 1, #F.sent do
        if F.sent[i].cmd == "fridgeFood" then return F.sent[i].args, F.sent[i].to, #F.sent - n end
    end
end
-- the page asks by itself: a request that gets no answer sends nothing at all (no deny, no red text over the player)
local function quiet(p, args)
    local n = #F.sent
    T.ServerCommands.fridgeFoodPull(p, args)
    return #F.sent == n
end
local pv = F.track(F.vehicle({ pct = 80 }))
local p1, p2, p3 = food(901, { age = 1 }), food(902, { age = 1, fert = true }), food(903, { age = 1, offMax = 1000000000 })
local pp = fit(pv, { p1, p2, p3 })
local asker = F.player("asker") -- no key: seeing what the loot page shows needs none
FR.setMode(pv, "cool", "owner")
tick(1)
check(quiet(asker, { vid = pv:getId(), seq = 1 }), "switched on: no answer, no deny (the clients read fridge.items)")
FR.setMode(pv, false)
local offAge, ptx = p1.age, pv.transmits
F.hours = F.hours + 5
local pr, pto, nSent = pull(asker, { vid = pv:getId(), seq = 7 })
check(pr and pr.vid == pv:getId() and pr.seq == 7 and pto == "asker" and nSent == 1,
    "off: one answer, to the asker only, its seq as sent")
check(pr and near(pr.items["901"].age, offAge + 5 * ROOM, 1e-12) and pr.items["901"].ft == p1.ft and pr.items["901"].fr == false,
    "the food as the engine has it now (its own room-rate catch-up over the 5 h off)")
check(pr and pr.items["902"].fe == true and pr.items["901"].fe == nil and pr.items["903"] == nil,
    "fe only on the fertilized one; food that never spoils not sent")
check(pp.md.fridge == nil and pv.transmits == ptx, "nothing stored, nothing transmitted")
check(pv.access == pp:getIndex(), "reach asked for the fridge's own part index (canAccessContainer)")
-- `seq` goes back in the answer as sent: only a whole number 1 .. 2^31 - 1, checked before any food is touched
local ages, realAge = 0, Food.updateAge
Food.updateAge = function(self, ...) ages = ages + 1; return realAge(self, ...) end
for _, bad in ipairs({ { "a string", "7" }, { "a table", { 1, { 2 } } }, { "a fraction", 7.5 }, { "negative", -3 },
    { "zero", 0 }, { "2^31", 2147483648 }, { "NaN", 0 / 0 }, { "infinite", math.huge } }) do
    check(quiet(asker, { vid = pv:getId(), seq = bad[2] }) and ages == 0, "seq " .. bad[1] .. ": no answer, no deny, no food touched")
end
check(quiet(asker, { vid = pv:getId() }) and ages == 0, "seq nil: no answer, no deny, no food touched")
Food.updateAge = realAge
pr = pull(asker, { vid = pv:getId(), seq = 2147483647 })
check(pr and pr.seq == 2147483647, "seq 2^31 - 1: answered")
pv.blocked = { [asker] = true }
check(quiet(asker, { vid = pv:getId(), seq = 8 }), "the container out of this player's reach (canAccessContainer false): no answer, no deny")
pv.blocked = nil
asker.dist = 11
check(quiet(asker, { vid = pv:getId(), seq = 9 }), "11 tiles away: no answer, no deny (no TOO_FAR)")
asker.vehicle = pv
check(pull(asker, { vid = pv:getId(), seq = 10 }) ~= nil, "seated in it (a Semi cab, any distance): answered")
asker.vehicle, asker.dist = nil, 2
check(quiet(asker, { vid = 99999, seq = 11 }), "no such car: no answer, no deny (no NO_VEHICLE)")
check(quiet(asker, { vid = pv:getId() + 0.5, seq = 11 }), "fractional id: no answer, no deny")
local notTesla = F.track(F.vehicle({ pct = 80, script = "Base.CarNormal" }))
fit(notTesla, { food(904, { age = 1 }) })
check(quiet(asker, { vid = notTesla:getId(), seq = 12 }), "not a Tesla: no answer, no deny")
local pItem = pp.item
pp.item = nil
check(quiet(asker, { vid = pv:getId(), seq = 13 }), "no fridge fitted: no answer, no deny")
pp.item = pItem
pp.items = { p3 }
check(quiet(asker, { vid = pv:getId(), seq = 14 }), "nothing in it that spoils: no answer, no deny")
local many = {}
for i = 1, 405 do many[i] = food(30000 + i, { age = 1 }) end
pp.items = many
pr = pull(asker, { vid = pv:getId(), seq = 15 })
local nKeys = 0
for _ in pairs(pr and pr.items or {}) do nKeys = nKeys + 1 end
check(nKeys == FR.MAX_ITEMS and pr.items["30400"] and pr.items["30401"] == nil, "405 foods: the first F.MAX_ITEMS in container order")
F.vehicles[pv:getId()], F.vehicles[notTesla:getId()] = nil, nil

H.section("Fridge: client copy, switched on (fridge.items)")
FR.setMode(v, "cool", "owner")
tick(1)
local mine = food(101, { age = 0 }) -- this client's copy of the server's food 101
-- a client's car: getVehicleById finds it under its own id
local function clientCar(id) return F.track({ parts = {}, getId = function() return id end,
    getPartById = function(self, k) return self.parts[k] end }) end
local view = fit(clientCar(7001), { mine })
view.md = fp.md -- the part modData the server sent
local client = isClient
isClient = function() return true end
H.require("MinidoracatTesla/FridgeUI")
isClient = client
local UI = T.FridgeUI
local asks, realSend, realPlayer = {}, sendClientCommand, getSpecificPlayer
sendClientCommand = function(p, module, cmd, args) asks[#asks + 1] = { p = p, module = module, cmd = cmd, args = args } end
getSpecificPlayer = function() return owner end
-- the server's answer to ask i (default the last) about server car `srv`, under the client car's id (as a client and
-- the server both know the car); deliver: this client takes it, returns how many foods did
local function answerTo(srv, i)
    local q = asks[i or #asks]
    if not q then return nil end
    local r = pull(q.p, { vid = srv:getId(), seq = q.args.seq })
    return r and { vid = q.args.vid, seq = r.seq, items = r.items }
end
local function deliver(r) local h = T.ClientCommands.fridgeFood; return r and h and h(r) or 0 end
local page = { shown = true, player = 0, backpacks = { { inventory = { getVehiclePart = function() return view end } } } }
function page:getIsVisible() return self.shown end
local m0 = H.count("EveryOneMinute")
H.fire("OnRefreshInventoryWindowContainers", page, "end")
check(near(mine.age, fp.md.fridge.items["101"].age, 1e-9) and mine.fr == fp.md.fridge.items["101"].fr,
    "page with the fridge: food takes the server's age and frozen state")
check(H.count("EveryOneMinute") == m0 + 1, "while listed: one per-minute check")
mine.age = 0
H.fire("EveryOneMinute")
check(mine.age == 0, "same fridge.at: not applied again")
tick(1)
H.fire("EveryOneMinute")
check(near(mine.age, fp.md.fridge.items["101"].age, 1e-9), "the server settled (new fridge.at): applied again within the minute")
page.shown = false
mine.age = 0
tick(1)
H.fire("EveryOneMinute")
check(mine.age == 0 and H.count("EveryOneMinute") == m0 + 1, "page hidden: nothing applied, still watched")
page.shown = true
H.fire("EveryOneMinute")
check(near(mine.age, fp.md.fridge.items["101"].age, 1e-9), "shown again: applied at the next minute")
page.isCollapsed = true -- ISInventoryPage:collapseNow: still shown, only the title bar
mine.age = 0
tick(1)
H.fire("EveryOneMinute")
check(mine.age == 0 and UI.watched[page], "page collapsed (shown, isCollapsed): nothing applied, still watched")
page.isCollapsed = false
H.fire("EveryOneMinute")
check(near(mine.age, fp.md.fridge.items["101"].age, 1e-9), "uncollapsed: applied at the next minute")
page.shown = false
mine.age = 0
tick(1)
H.fire("OnRefreshInventoryWindowContainers", page, "end")
check(mine.age == 0 and UI.watched[page], "page rebuilt while hidden: nothing applied, still watched")
page.shown = true
H.fire("EveryOneMinute")
check(near(mine.age, fp.md.fridge.items["101"].age, 1e-9), "shown again after that: applied at the next minute")
local mineB = food(102, { age = 0, freezable = false }) -- reaches this client after the page took this settle
view.items[#view.items + 1] = mineB
H.fire("EveryOneMinute")
check(near(mineB.age, fp.md.fridge.items["102"].age, 1e-9),
    "a food instance that arrives after the page took the settle: applied at the next minute, no new settle needed")
local mine2 = food(101, { age = 0 }) -- the same food sent again (moved out and back by someone else): same id, new instance
view.items[1] = mine2
mine.age = 0
H.fire("EveryOneMinute")
check(near(mine2.age, fp.md.fridge.items["101"].age, 1e-9) and mine.age == 0, "same id, another instance: applied at the next minute")

H.section("Fridge: client copy, switched off (asks the server: fridgeFoodPull -> fridgeFood)")
FR.setMode(v, false)
check(fp.md.fridge == nil and fp.md.fridgeLast == nil, "switched off: no fridge table, nothing left in modData for the clients")
local aOff = a.age
F.hours = F.hours + 5
mine2.age, mineB.age = 0, 0
local n0 = #asks
H.fire("EveryOneMinute")
local q = asks[#asks]
check(#asks == n0 + 1 and q.cmd == "fridgeFoodPull" and q.module == T.MODULE and q.p == owner and q.args.vid == 7001
    and mine2.age == 0, "off: the page's player asks once (fridgeFoodPull), nothing applied before the answer")
check(deliver(answerTo(v)) == 2 and near(mine2.age, aOff + 5 * ROOM, 1e-12) and near(mine2.age, a.age, 1e-12)
    and near(mineB.age, b.age, 1e-12) and mine2.ft == a.ft and mine2.fr == a.fr,
    "the answer: each food = the server's now (off 5 h: the engine's own room rate)")
n0 = #asks
H.fire("EveryOneMinute")
check(#asks == n0, "the same ten minutes, the same instances: no second ask")
F.hours = F.hours + 1 / 6
H.fire("EveryOneMinute")
check(#asks == n0 + 1 and deliver(answerTo(v)) == 2 and near(mine2.age, a.age, 1e-12),
    "the ten-minute bucket moved on: asks again and takes it (a page left open follows the server)")
local mine3 = food(101, { age = 0 })
view.items[1] = mine3
n0 = #asks
H.fire("EveryOneMinute")
check(#asks == n0 + 1 and deliver(answerTo(v)) == 2 and near(mine3.age, a.age, 1e-12),
    "same ten minutes, same count and ids, one food another instance: asks again, the new instance takes it")
F.hours = F.hours + 1 / 6
H.fire("EveryOneMinute")
local first = #asks
F.hours = F.hours + 1 / 6
H.fire("EveryOneMinute")
local older, newer = answerTo(v, first), answerTo(v)
check(#asks == first + 1 and deliver(newer) == 2 and near(mine3.age, a.age, 1e-12), "the last ask's answer: taken")
mine3.age = -1
check(deliver(older) == 0 and mine3.age == -1, "an older ask's answer arriving after it (RELIABLE, not ordered): dropped")
F.hours = F.hours + 1 / 6
H.fire("EveryOneMinute")
local r1 = answerTo(v)
local mine4 = food(101, { age = 0 })
view.items[1] = mine4
check(deliver(r1) == 1 and mine4.age == 0 and near(mineB.age, b.age, 1e-12),
    "a food swapped for another instance between ask and answer: not written, the rest is")
H.fire("EveryOneMinute")
check(deliver(answerTo(v)) == 2 and near(mine4.age, a.age, 1e-12), "the next minute asks for it, and it takes that answer")
F.hours = F.hours + 1 / 6
H.fire("EveryOneMinute")
local r2 = answerTo(v)
FR.setMode(v, "cool", "owner")
mine4.age = -1
check(r2 and deliver(r2) == 0 and mine4.age == -1, "switched on before the answer came: dropped")
FR.setMode(v, false)
F.hours = F.hours + 1 / 6
H.fire("EveryOneMinute")
local r3 = answerTo(v)
local fItem = view.item
view.item = nil
check(r3 and deliver(r3) == 0 and mine4.age == -1, "the fridge removed before the answer came: dropped")
view.item = fItem
page.shown = false
F.hours = F.hours + 1 / 6
n0 = #asks
H.fire("EveryOneMinute")
check(#asks == n0, "page hidden: no ask")
check(UI.cars[7001] == nil and UI.watched[page], "page hidden a minute: still watched, the car's state (food instances) let go")
page.shown = true
H.fire("EveryOneMinute")
check(#asks == n0 + 1 and deliver(answerTo(v)) == 2 and near(mine4.age, a.age, 1e-12), "shown again: asks at the next minute")
-- an answer on its way when the page stops showing the fridge: dropped with the car's state; shown again, asks anew
F.hours = F.hours + 1 / 6
H.fire("EveryOneMinute")
local late = answerTo(v)
page.isCollapsed = true
mine4.age = -1
check(late and deliver(late) == 0 and mine4.age == -1 and UI.cars[7001] == nil,
    "collapsed before the answer came: not written, the car's state gone")
page.isCollapsed = false
n0 = #asks
H.fire("EveryOneMinute")
check(#asks == n0 + 1 and deliver(answerTo(v)) == 2 and near(mine4.age, a.age, 1e-12),
    "uncollapsed: asks again at the next minute and takes that answer")
local packs = page.backpacks
F.hours = F.hours + 1 / 6
H.fire("EveryOneMinute")
late = answerTo(v)
page.backpacks = {}
H.fire("OnRefreshInventoryWindowContainers", page, "end")
mine4.age = -1
check(UI.cars[7001] == nil and not UI.watched[page], "the last page no longer lists the fridge: the car's state gone")
check(late and deliver(late) == 0 and mine4.age == -1, "an answer arriving after that: not written")
page.backpacks = packs
n0 = #asks
H.fire("OnRefreshInventoryWindowContainers", page, "end")
check(#asks == n0 + 1 and deliver(answerTo(v)) == 2 and near(mine4.age, a.age, 1e-12), "listed again: asks at once, takes it")
-- split screen: another page lists the same car; one of them stops listing it, the other still shows it
local page2 = { shown = true, player = 0, backpacks = packs }
page2.getIsVisible = page.getIsVisible
H.fire("OnRefreshInventoryWindowContainers", page2, "end")
page2.backpacks = {}
H.fire("OnRefreshInventoryWindowContainers", page2, "end")
H.fire("EveryOneMinute")
check(UI.cars[7001] ~= nil and UI.watched[page], "two pages list the car, one stops: the state stays (the other still shows it)")
page2.backpacks = packs
H.fire("OnRefreshInventoryWindowContainers", page2, "end")
page.shown = false
H.fire("EveryOneMinute")
check(UI.cars[7001] ~= nil, "two pages list the car, one hidden: the state stays")
page.shown = true
page2.backpacks = {}
H.fire("OnRefreshInventoryWindowContainers", page2, "end")
-- (c) food put in after it went off, a fertilized egg the server has as fertilized and this copy not
local srvEgg, cliEgg = food(905, { age = 1, fert = true }), food(905, { age = 0, fert = false })
fp.items[#fp.items + 1] = srvEgg
view.items[#view.items + 1] = cliEgg
H.fire("EveryOneMinute")
check(deliver(answerTo(v)) == 3 and cliEgg.fert == true and near(cliEgg.age, srvEgg.age, 1e-12),
    "food put in after it went off: the server's values too, its fertilized flag taken (server true, copy false)")
remove(fp.items, srvEgg); remove(view.items, cliEgg)
-- (a) this client takes a food out and puts it back while off; meanwhile the server's value moved on (in another
-- fridge, say): the copy shows the server's value, not one guessed from the switch-off
remove(view.items, mine4); remove(fp.items, a)
F.hours = F.hours + 3
a.age, a.last = a.age + 3 * COOL, F.hours
table.insert(fp.items, 1, a)
table.insert(view.items, 1, mine4)
mine4.age = 0
F.hours = F.hours + 1 / 6
H.fire("EveryOneMinute")
check(deliver(answerTo(v)) == 2 and near(mine4.age, a.age, 1e-12), "(a) out and back in while off: the server's value")
-- (b) the answer first, a food after it (the item and the answer ride different channels)
remove(view.items, mineB)
F.hours = F.hours + 1 / 6
H.fire("EveryOneMinute")
local early = answerTo(v)
local mineB2 = food(102, { age = 0, freezable = false })
view.items[#view.items + 1] = mineB2
check(deliver(early) == 1 and mineB2.age == 0, "(b) an answer from before the food arrived: not written to it")
H.fire("EveryOneMinute")
check(deliver(answerTo(v)) == 2 and near(mineB2.age, b.age, 1e-12), "(b) the next minute (same ten minutes) asks for it: the server's value")
local nEmpty = #asks
local ev = F.track(F.vehicle({ pct = 80 }))
local evFood = food(906, { age = 2 })
local evp = fit(ev, { evFood })
local evCopy = food(906, { age = 0 })
local eview = fit(clientCar(7003), {})
local epage = { shown = true, player = 0, backpacks = { { inventory = { getVehiclePart = function() return eview end } } } }
epage.getIsVisible = page.getIsVisible
H.fire("OnRefreshInventoryWindowContainers", epage, "end")
check(#asks == nEmpty, "an empty fridge: no ask")
eview.items[1] = evCopy
H.fire("EveryOneMinute")
check(#asks == nEmpty + 1 and deliver(answerTo(ev)) == 1 and near(evCopy.age, evFood.age, 1e-12),
    "scanned empty, the food arriving later in the same ten minutes: asks at once, takes it")
H.fire("OnRefreshInventoryWindowContainers", epage, "begin")
epage.backpacks = {}
H.fire("OnRefreshInventoryWindowContainers", epage, "end")
F.vehicles[ev:getId()] = nil
FR.setMode(v, "cool", "owner")
local eggView = fit({ parts = {}, getId = function() return 7301 end },
    { food(701, { fert = true }), food(702, { fert = true }), food(703, { fert = true, freezable = false }) })
eggView.md.fridge = { mode = "freeze", at = F.hours, items = { ["701"] = { age = 1, ft = 30, fr = false },
    ["702"] = { age = 1, ft = 0, fr = false }, ["703"] = { age = 1, ft = 0, fr = false } } }
check(UI.apply(eggView) == 3 and not eggView.items[1].fert and not eggView.items[2].fert and eggView.items[3].fert,
    "client copy, freezer running: eggs that can freeze are dead, ft 0 too (Food.isFreezing); one that cannot: not")
local coolView = fit({ parts = {}, getId = function() return 7302 end }, { food(704, { fert = true }), food(705, { fert = true }) })
coolView.md.fridge = { mode = "cool", at = F.hours, items = { ["704"] = { age = 1, ft = 0, fr = false }, ["705"] = { age = 1, ft = 20, fr = false } } }
check(UI.apply(coolView) == 2 and coolView.items[1].fert and not coolView.items[2].fert,
    "client copy, cool: an egg with no freezing time still fertilized, one with some not")
H.fire("OnRefreshInventoryWindowContainers", { backpacks = {} }, "end")
check(H.count("EveryOneMinute") == m0 + 1, "another page without one: the check stays for the first")
H.fire("OnRefreshInventoryWindowContainers", page, "begin")
page.backpacks = {}
H.fire("OnRefreshInventoryWindowContainers", page, "end")
check(H.count("EveryOneMinute") == m0 and UI.nWatched == 0, "no page lists a fridge: the per-minute check is removed")

H.section("Fridge: a fertilized egg frozen, then thawed (one catch-up == ten-minute settles == a late client)")
local LC, SC = F.track(F.vehicle({ pct = 21 })), F.track(F.vehicle({ pct = 21 }))
local le, se = food(801, { age = 1, fert = true }), food(802, { age = 1, fert = true })
local lcp = fit(LC, { le })
local scp = fit(SC, { se })
FR.setMode(LC, "freeze", "owner"); FR.setMode(SC, "freeze", "owner")
local le2 = food(803, { age = 1, fert = true }) -- put in after the switch-on settle: first seen by the catch-up
lcp.items[#lcp.items + 1] = le2
local t1 = F.hours
unload(LC)
for _ = 1, 87 do tick(1 / 6) end -- 14.5 h: 12.5 h freezing on the pack down to 20 %, then 2 h without power
F.hours = t1 + 14.5
reload(LC, 7501)
check(le.ft == 0 and not le.fr and not le.fert and near(le.age, 1 + 4 * COOL + 0.5 * ROOM, 1e-9),
    "one catch-up: frozen, then thawed by its end (ft 0); the egg dead")
check(not le2.fert and le2.ft == 0,
    "first seen by a catch-up that had power in freeze mode (12.5 h of 14.5): dead, though only a baseline (ft 0)")
check(not se.fert and scp.md.fridge == nil, "ten-minute settles: the same egg, dead since the first settle; off at 20 %")
local copy = food(802, { age = 0, fert = true }) -- a client that never looked until now (its copy still fertilized)
local cview = fit(clientCar(7502), { copy })
cview.md = scp.md
local cpage = { shown = true, player = 0, backpacks = { { inventory = { getVehiclePart = function() return cview end } } } }
cpage.getIsVisible = page.getIsVisible
local na = #asks
H.fire("OnRefreshInventoryWindowContainers", cpage, "end")
check(#asks == na + 1 and asks[#asks].args.vid == 7502, "a client looking after it went off: its page asks")
check(deliver(answerTo(SC)) == 1 and not copy.fert and copy.ft == se.ft and near(copy.age, se.age, 1e-12),
    "the answer: dead (no fe), the server's age and freezing time")
sendClientCommand, getSpecificPlayer = realSend, realPlayer
unload(LC); F.vehicles[SC:getId()] = nil

T.Charge = realCharge
F.done()
