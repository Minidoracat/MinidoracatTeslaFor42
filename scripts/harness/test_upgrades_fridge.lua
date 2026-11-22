-- Car fridge (server Fridge.lua, Upgrades.lua F.step / F.canSet, client FridgeUI.lua): one food's state over time
-- (F.step: freezing, thawing, ageing; one catch-up == many ten-minute settles), the cool and freeze rates from each
-- food's baseline, new food only getting one, the item flags never read back, the cap on tracked food, frozen eggs,
-- the 20 % cut-off told once and fridgeLast kept, charger hours free, the catch-up on load, the late registration of a
-- car loaded at id -1, every guard of command `fridge`, and the client copy.
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
    function p:getModData() return self.md end
    function p:getInventoryItem() return self.item end
    function p:getItemContainer() local list = self.items; return { getItems = function() return F.list(list) end } end
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
local bad, n = src:gsub("local b = old%[k%]", "local b = old[k] or { age = it:getAge(), ft = it:getFreezingTime(), fr = it:isFrozen() }")
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

H.section("Fridge: fertilized eggs")
local eggCar = F.track(F.vehicle({ pct = 80 }))
local egg, warm = food(601, { fert = true }), food(602, { fert = true })
local eggPart = fit(eggCar, { egg })
FR.setMode(eggCar, "freeze", "owner")
local coolCar = F.track(F.vehicle({ pct = 80 }))
fit(coolCar, { warm })
FR.setMode(coolCar, "cool", "owner")
check(egg.fert, "freeze, first settle (only a baseline, ft 0): still fertilized")
tick(1)
check(not egg.fert and near(egg.ft, 25, 1e-9) and warm.fert, "freezing begun: no longer fertilized (Food.java:837-838); cool: still fertilized")
FR.setMode(eggCar, false); FR.setMode(coolCar, false)
FR.untrack(eggCar); F.vehicles[eggCar:getId()] = nil; F.vehicles[coolCar:getId()] = nil
check(eggPart.md.fridgeLast and eggPart.md.fridgeLast.items["601"], "switched off: fridgeLast kept")

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
check(alerts("lo") == 1, "the one who switched it on hears it (lowBattery, what fridge)")
tick(5); FR.settle(lv)
check(alerts("lo") == 1, "told once: off is off")
B.part(lv):setContainerContentAmount(14.9) -- just under (at exactly 20 % it may go on again, as sentry)
T.ServerCommands.fridge(lo, { vid = lv:getId(), mode = "cool" })
check(lp.md.fridge == nil and denied() == "LOW_BATTERY", "below 20 %: cannot switch it on again")
local sent = #F.sent
T.ServerCommands.fridge(lo, { vid = lv:getId(), mode = false })
check(#F.sent == sent and lp.md.fridge == nil and lp.md.fridgeLast == last, "switching off below 20 %: no deny, nothing changes")
chg(lv).chg = { power = "grid" }
T.ServerCommands.fridge(lo, { vid = lv:getId(), mode = "freeze" })
check(lp.md.fridge and lp.md.fridge.mode == "freeze" and #F.sent == sent and lp.md.fridgeLast == nil,
    "below 20 % on a charger: switches on, fridgeLast cleared")
chg(lv).chg = nil
lp.items = {}
FR.setMode(lv, false)
check(lp.md.fridge == nil and lp.md.fridgeLast == nil, "switched off with nothing in it: no fridgeLast")

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
check(fp.md.fridge == nil and fp.md.fridgeLast == nil and not FR.cars[v:getId()], "state left on a removed fridge: cleared at the next settle")
fp.item = { getFullType = function() return "Base.MinidoracatTesla_Fridge" end }
FR.setMode(v, "cool", "owner")
FR.setMode(v, false)
check(fp.md.fridgeLast ~= nil, "switched off with food: fridgeLast kept")
T.UninstallComplete.Fridge(v, fp)
check(fp.md.fridge == nil and fp.md.fridgeLast == nil and not FR.cars[v:getId()], "uninstall complete: state and fridgeLast dropped, unlisted")

H.section("Fridge: client copy")
FR.setMode(v, "cool", "owner")
tick(1)
local mine = food(101, { age = 0 }) -- this client's copy of the server's food 101
local view = fit({ parts = {}, getId = function() return 7001 end }, { mine })
view.md = fp.md -- the part modData the server sent
local client = isClient
isClient = function() return true end
H.require("MinidoracatTesla/FridgeUI")
isClient = client
local UI = T.FridgeUI
local page = { shown = true, backpacks = { { inventory = { getVehiclePart = function() return view end } } } }
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
local offAt = F.hours
FR.setMode(v, false)
local fl = fp.md.fridgeLast
check(fp.md.fridge == nil and fl and fl.at == offAt and fl.items["101"], "switched off: fridgeLast { at, items } for the clients")
F.hours = F.hours + 5
mine.age = 0
H.fire("EveryOneMinute")
check(near(mine.age, FR.step(fl.items["101"], 5, nil, true).age, 1e-9) and UI.applied[7001] == "last " .. offAt,
    "off 5 h: fridgeLast run on at room rate to now, under a version of its own (not the same `at` as on)")
mine.age = 0
H.fire("EveryOneMinute")
check(mine.age == 0, "same fridgeLast: not applied again")
local eggView = fit({ parts = {}, getId = function() return 7301 end }, { food(701, { fert = true }), food(702, { fert = true }) })
eggView.md.fridge = { mode = "freeze", at = F.hours, items = { ["701"] = { age = 1, ft = 30, fr = false }, ["702"] = { age = 1, ft = 0, fr = false } } }
check(UI.apply(eggView) == 2 and not eggView.items[1].fert and eggView.items[2].fert, "client copy: an egg with freezing time is no longer fertilized")
H.fire("OnRefreshInventoryWindowContainers", { backpacks = {} }, "end")
check(H.count("EveryOneMinute") == m0 + 1, "another page without one: the check stays for the first")
H.fire("OnRefreshInventoryWindowContainers", page, "begin")
page.backpacks = {}
H.fire("OnRefreshInventoryWindowContainers", page, "end")
check(H.count("EveryOneMinute") == m0 and UI.nWatched == 0, "no page lists a fridge: the per-minute check is removed")

T.Charge = realCharge
F.done()
