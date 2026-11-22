-- Car fridge (server Fridge.lua, Upgrades.lua F.canSet, client FridgeUI.lua): the cool and freeze rates from each
-- food's baseline, new food only getting one, the 20 % cut-off told once, charger hours free, the catch-up on load,
-- the late registration of a car loaded at id -1, every guard of command `fridge`, and the client copy.
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

local function food(id, o)
    o = o or {}
    local f = { _class = "Food", id = id, age = o.age or 0, ft = 0, fr = false, freezable = o.freezable ~= false, last = F.hours }
    function f:getID() return self.id end
    function f:getAge() return self.age end
    function f:setAge(a) self.age = a end
    function f:getFreezingTime() return self.ft end
    function f:setFreezingTime(x) self.ft = x end
    function f:isFrozen() return self.fr end
    function f:setFrozen(b) self.fr = b end
    function f:canBeFrozen() return self.freezable end
    -- the engine's own pass in a vehicle container: room rate since the last, nothing while frozen (Food.java:739-776)
    function f:updateAge()
        if not self.fr then self.age = self.age + (F.hours - self.last) * ROOM end
        self.last = F.hours
    end
    return f
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
tick(3)
check(a.age == frozenAge, "cool with frozen food: still no ageing from its frozen baseline")

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
    cmd = T.ServerCommands.fridge }
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
T.ServerCommands.fridge(lo, { vid = lv:getId(), mode = false })
check(denied() == "LOW_BATTERY" and #F.sent > 0, "switching off below 20 % is fine (no new deny)")
chg(lv).chg = { power = "grid" }
local sent = #F.sent
T.ServerCommands.fridge(lo, { vid = lv:getId(), mode = "freeze" })
check(lp.md.fridge and lp.md.fridge.mode == "freeze" and #F.sent == sent, "below 20 % on a charger: switches on")
chg(lv).chg = nil
FR.setMode(lv, false)

H.section("Fridge: load")
local h0, a1 = F.hours, a.age
s = fp.md.fridge
s.mode = "cool"
F.vehicles[v:getId()] = nil -- unloaded for 30 h: no ticks, no engine passes
FR.cars[v:getId()] = nil
F.hours = F.hours + 30
v.id = 7001
F.track(v)
H.fire("OnSpawnVehicleEnd", v)
check(a.age == a1 and s.at == F.hours and FR.cars[7001], "load: frozen food caught up (no ageing), the car listed under its new id")
check(near(c.age, s.items["103"].age, 1e-9) and s.items["103"].age > outside, "load: unfrozen food caught up 30 h at the fridge rate")
local lateCar = F.vehicle({ pct = 80 })
fit(lateCar, {}).md.fridge = { mode = "cool", at = F.hours, items = {} }
lateCar.id = -1
H.fire("OnSpawnVehicleEnd", lateCar)
check(FR.cars[-1] == nil, "loaded at id -1: not listed")
lateCar.id = 7002
F.track(lateCar)
local cell = getCell
getCell = function()
    return { getVehicles = function()
        local i, list = 0, { v, lateCar }
        return { iterator = function() return { hasNext = function() return i < #list end,
            next = function() i = i + 1; return list[i] end } end }
    end }
end
tick(1)
getCell = cell
check(FR.cars[7002] and FR.cars[7001], "the next ten-minute tick finds it in the cell")
local swept = 0
getCell = function() swept = swept + 1; return cell() end
tick(1)
getCell = cell
check(swept == 0, "then no more sweeps")
F.vehicles[7002] = nil
tick(1)
check(FR.cars[7002] == nil, "a listed car no longer loaded: dropped from the list")
F.hours = h0 + 30

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
MinidoracatVehicleManagerAPI = nil
FR.setMode(v, false)

H.section("Fridge: removal")
FR.setMode(v, "cool", "owner")
fp.item = nil
FR.settle(v)
check(fp.md.fridge == nil and not FR.cars[v:getId()], "state left on a removed fridge: cleared at the next settle")
fp.item = { getFullType = function() return "Base.MinidoracatTesla_Fridge" end }
FR.setMode(v, "cool", "owner")
T.UninstallComplete.Fridge(v, fp)
check(fp.md.fridge == nil and not FR.cars[v:getId()], "uninstall complete: state dropped, unlisted")

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
local page = { backpacks = { { inventory = { getVehiclePart = function() return view end } } } }
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
H.fire("OnRefreshInventoryWindowContainers", { backpacks = {} }, "end")
check(H.count("EveryOneMinute") == m0 + 1, "another page without one: the check stays for the first")
H.fire("OnRefreshInventoryWindowContainers", page, "begin")
page.backpacks = {}
H.fire("OnRefreshInventoryWindowContainers", page, "end")
check(H.count("EveryOneMinute") == m0 and UI.nWatched == 0, "no page lists a fridge: the per-minute check is removed")
FR.setMode(v, false)

T.Charge = realCharge
F.done()
