-- Armor.lua (references/upgrades.md section 4): the kits give back loss * (1 - k) after the fact, never above the
-- snapshot and never twice; a changed or missing item is only re-recorded (no refit); what is covered; tracking by
-- the car, not its reused id; the crash event only; new snapshots after part actions and vanilla vehicle commands;
-- the sentry scan registered first; the server's key / empty / VehicleManager check on taking TeslaArmor or
-- TeslaFridge off.
local check = H.check
local T = MinidoracatTesla
local MEDIA = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua"

-- Upgrades.lua and Armor.lua run here without being marked loaded and without Liftgate / Sentry: test_liftgate and
-- test_sentry load those themselves later (they wrap the vanilla actions they set up first). The order Armor.lua
-- requires the sentry and adds its minute handler is recorded instead.
local saved = { require = require, ISInstallVehiclePart = ISInstallVehiclePart,
    ISUninstallVehiclePart = ISUninstallVehiclePart, Liftgate = T.Liftgate, Keys = T.Keys,
    VehicleUtils = VehicleUtils, IsoObjectChange = IsoObjectChange, Capability = Capability }
local order, minuteAdd = {}, Events.EveryOneMinute.Add
require = function(name)
    if name == "MinidoracatTesla/Sentry" then order[#order + 1] = "sentry"; return true end
    if name == "MinidoracatTesla/Liftgate" or name == "MinidoracatTesla/Upgrades" then return true end
    return saved.require(name)
end
Events.EveryOneMinute.Add = function(fn) order[#order + 1] = "minute"; return minuteAdd(fn) end
T.Liftgate = { glassLast = function() end }
-- vanilla uninstall on success (ISUninstallVehiclePart.lua:62-69): the item leaves the part
local vanilla = { install = 0, uninstall = 0 }
ISInstallVehiclePart = { complete = function() vanilla.install = vanilla.install + 1; return true end }
ISUninstallVehiclePart = { complete = function(self)
    vanilla.uninstall = vanilla.uninstall + 1
    self.part.item = nil
    return true
end }
dofile(MEDIA .. "/shared/MinidoracatTesla/Upgrades.lua")
dofile(MEDIA .. "/server/MinidoracatTesla/Armor.lua")
require, Events.EveryOneMinute.Add = saved.require, minuteAdd
local A = T.Armor

-- ---------------------------------------------------------------- fakes
local itemIds = 100
local function item(full)
    itemIds = itemIds + 1
    local it = { full = full or "Base.Part", id = itemIds }
    function it:getFullType() return self.full end
    function it:getID() return self.id end
    return it
end
local function part(id, o)
    o = o or {}
    local p = { id = id, cat = o.cat, item = o.item, window = o.window, light = o.light, cond = o.cond or 100,
        sets = 0, refits = 0, tbl = o.tbl, box = o.box, content = 0 }
    function p:getId() return self.id end
    function p:getCategory() return self.cat end
    function p:getWindow() return self.window end
    function p:getLight() return self.light end
    function p:getInventoryItem() return self.item end
    function p:setInventoryItem(it) self.refits = self.refits + 1; self.item = it end
    function p:getCondition() return self.cond end
    function p:setCondition(c) self.sets = self.sets + 1; self.cond = c end
    function p:setModelVisible() end
    function p:getTable(name) return self.tbl and self.tbl[name] end
    function p:getItemContainer() return self.box end
    function p:getContainerContentAmount() return self.content end
    return p
end
local nextId = 9000
-- a Model Y's shielded parts and some it leaves alone; kit = "Inner" / "Outer" / nil
local function car(kit, id)
    nextId = nextId + 1
    local v = { id = id or nextId, list = {}, parts = {}, condTx = 0, winTx = 0, itemTx = 0, keyId = 4242 }
    local function add(p) v.list[#v.list + 1] = p; v.parts[p.id] = p end
    add(part("DoorFrontLeft", { cat = "door", item = item() }))
    add(part("EngineDoor", { cat = "bodywork", item = item() }))
    add(part("WindowFrontLeft", { item = item(), window = {} }))
    add(part("HeadlightLeft", { item = item(), light = {} }))
    add(part("Engine"))
    add(part("GasTank", { item = item() }))
    add(part("TireFrontLeft", { cat = "tire", item = item() }))
    add(part("Battery", { item = item() }))
    add(part("TeslaArmor", { cat = "upgrade", item = kit and item("Base.MinidoracatTesla_Armor" .. kit) or nil }))
    add(part("TeslaFridge", { cat = "upgrade", item = item("Base.MinidoracatTesla_Fridge"),
        tbl = { uninstall = { requireEmpty = "true" } }, box = { n = 0, isEmpty = function(b) return b.n == 0 end } }))
    function v:getId() return self.id end
    function v:getPartCount() return #self.list end
    function v:getPartByIndex(i) return self.list[i + 1] end
    function v:getPartById(pid) return self.parts[pid] end
    function v:transmitPartCondition() self.condTx = self.condTx + 1 end
    function v:transmitPartWindow() self.winTx = self.winTx + 1 end
    function v:transmitPartItem() self.itemTx = self.itemTx + 1 end
    function v:getKeyId() return self.keyId end
    H.addVehicle(v)
    return v
end
local function cond(v, pid) return v.parts[pid].cond end
local function hit(v, pid, c) v.parts[pid].cond = c end

H.section("Armor: order and settling")
check(order[1] == "sentry" and order[2] == "minute" and #order == 2,
    "Armor.lua requires the sentry before adding its minute handler (sentry scans the loss first)")

local v = car("Inner")
T.Init.Armor(v, v.parts.TeslaArmor) -- load: the part init tracks it
check(A.cars[v.id] and A.cars[v.id].v == v, "init with a kit and an id: tracked")
hit(v, "DoorFrontLeft", 60); hit(v, "WindowFrontLeft", 60); hit(v, "Engine", 40)
H.fire("EveryOneMinute")
check(cond(v, "DoorFrontLeft") == 80 and cond(v, "WindowFrontLeft") == 80 and cond(v, "Engine") == 70,
    "Inner (k 0.5): door and window 100 -> 60 back to 80; Engine (no item) 100 -> 40 back to 70")
check(v.winTx == 1 and v.condTx == 3, "conditions sent, the window's state too")
H.fire("EveryOneMinute")
check(cond(v, "DoorFrontLeft") == 80 and v.condTx == 3, "next minute with no new loss: nothing given back again")
hit(v, "DoorFrontLeft", 50)
H.fire("EveryOneMinute")
check(cond(v, "DoorFrontLeft") == 65, "a second hit counts from the last snapshot: 80 -> 50 back to 65")

local o = car("Outer")
A.onLoad(o) -- OnSpawnVehicleEnd
hit(o, "EngineDoor", 60); hit(o, "HeadlightLeft", 20); hit(o, "GasTank", 92)
A.settle(o)
check(cond(o, "EngineDoor") == 90 and cond(o, "HeadlightLeft") == 80 and cond(o, "GasTank") == 98,
    "Outer (k 0.25): hood 60 -> 90, light 20 -> 80, battery 92 -> 98")

-- random rounding: whatever the roll, the car keeps floor or ceil of loss * k and never more than the snapshot
local okRound, okCap = true, true
for loss = 1, 100, 7 do
    for _, r in ipairs({ 0, 0.3, 0.7, 0.999 }) do
        H.setRand(r)
        for _, kit in ipairs({ "Inner", "Outer" }) do
            local c = car(kit)
            A.track(c)
            hit(c, "DoorFrontLeft", 100 - loss)
            A.settle(c)
            local kept = 100 - cond(c, "DoorFrontLeft")
            local x = loss * A.K["Base.MinidoracatTesla_Armor" .. kit]
            okRound = okRound and (kept == math.floor(x) or kept == math.ceil(x))
            okCap = okCap and cond(c, "DoorFrontLeft") <= 100
            H.removeVehicle(c); A.cars[c.id] = nil
        end
    end
end
H.setRand(0.5)
check(okRound, "kept = loss * k rounded down or up at random (k 0.5 and 0.25, losses 1-99)")
check(okCap, "never given back above the snapshot")

H.section("Armor: what is left alone")
v = car("Inner")
A.track(v)
local pane = v.parts.WindowFrontLeft
pane.item, pane.cond = item(), 50 -- another pane, worse
hit(v, "DoorFrontLeft", 70)
v.parts.DoorFrontLeft.item = item() -- a door swapped
A.settle(v)
check(pane.cond == 50 and cond(v, "DoorFrontLeft") == 70, "item changed: nothing given back")
A.settle(v)
check(pane.cond == 50, "item changed: the new one is the snapshot from then on")
v = car("Inner")
A.track(v)
pane = v.parts.WindowFrontLeft
pane.item, pane.cond = nil, 0 -- knocked out (VehicleWindow.damage at 0)
v.parts.HeadlightLeft.item, v.parts.HeadlightLeft.cond = nil, 0
A.settle(v)
check(pane.refits == 0 and pane.item == nil and pane.cond == 0 and v.parts.HeadlightLeft.refits == 0,
    "a pane or light knocked out stays out: no setInventoryItem, no condition")
hit(v, "TireFrontLeft", 50); hit(v, "TeslaArmor", 50); hit(v, "Battery", 50)
A.settle(v)
check(cond(v, "TireFrontLeft") == 50 and cond(v, "TeslaArmor") == 50 and cond(v, "Battery") == 50,
    "tyres, the 12 V battery and the kit itself are not covered")
hit(v, "DoorFrontLeft", 70)
A.settle(v)
local sets = v.parts.DoorFrontLeft.sets
v.parts.DoorFrontLeft.cond = 95 -- repaired past the snapshot (85)
A.settle(v)
check(cond(v, "DoorFrontLeft") == 95 and v.parts.DoorFrontLeft.sets == sets, "condition up: snapshot only")
hit(v, "DoorFrontLeft", 75)
A.settle(v)
check(cond(v, "DoorFrontLeft") == 85, "...and the next loss counts from it: 95 -> 75 back to 85")

H.section("Armor: tracking")
v = car("Inner", -1)
A.track(v)
check(A.cars[-1] == nil, "an id not given yet (-1): not tracked")
v.id = 9500; H.addVehicle(v)
A.onLoad(v) -- OnSpawnVehicleEnd: the id is there now
check(A.cars[9500] and A.cars[9500].v == v, "OnSpawnVehicleEnd tracks it once it has an id")
v.parts.TeslaArmor.item = nil
T.UninstallComplete.Armor(v, v.parts.TeslaArmor)
check(A.cars[9500] == nil, "kit taken off: untracked")
v.parts.TeslaArmor.item = item("Base.MinidoracatTesla_ArmorInner")
T.InstallComplete.Armor(v, v.parts.TeslaArmor)
check(A.cars[9500] and A.cars[9500].v == v, "kit fitted: tracked")
-- unloaded; another car gets the id
H.removeVehicle(v)
local other = car(nil, 9500)
hit(other, "DoorFrontLeft", 10)
check(A.settle(other) == 0 and cond(other, "DoorFrontLeft") == 10, "id reused by a car without a kit: the old snapshot does nothing")
H.fire("EveryOneMinute")
check(A.cars[9500] == nil, "minute: the entry of a car no longer under its id leaves")
local reuse = car("Inner", 9500)
A.track(reuse)
H.removeVehicle(reuse)
local reuse2 = car("Outer", 9500)
hit(reuse2, "Engine", 10) -- no item on either car: only the car itself tells them apart
check(A.settle(reuse2) == 0 and cond(reuse2, "Engine") == 10,
    "id reused by another car with a kit: not settled with the old car's snapshot")
A.onLoad(reuse2)
hit(reuse2, "Engine", 0)
A.settle(reuse2)
check(cond(reuse2, "Engine") == 8, "...its own snapshot from load on: 10 -> 0 back to 8 (keeps 2.5, rounded down at roll 0.5)")
local bare = car(nil)
A.cars[bare.id] = { v = bare, snap = {} }
H.fire("EveryOneMinute")
check(A.cars[bare.id] == nil, "minute: a car without a kit leaves")

H.section("Armor: when")
v = car("Inner")
A.track(v)
local driver = H.player({ name = "drv" })
driver.vehicle = v
hit(v, "DoorFrontLeft", 60)
H.fire("OnPlayerGetDamage", driver, "WEAPONHIT", 5)
H.fire("OnPlayerGetDamage", driver, "FALLDOWN", 5)
check(cond(v, "DoorFrontLeft") == 60, "other damage kinds: no settling")
H.fire("OnPlayerGetDamage", driver, "CARCRASHDAMAGE", 5)
check(cond(v, "DoorFrontLeft") == 80, "CARCRASHDAMAGE: the car settles at once")
local walker = H.player({ name = "walk" })
H.fire("OnPlayerGetDamage", walker, "CARCRASHDAMAGE", 5)
check(true, "CARCRASHDAMAGE on someone not in a car: nothing")

local admin = H.player({ name = "adm", admin = true })
hit(v, "DoorFrontLeft", 50) -- an admin sets the condition (vanilla VehicleCommands setPartCondition)
H.fire("OnClientCommand", "vehicle", "setPartCondition", admin, { vehicle = v.id, part = "DoorFrontLeft", condition = 50 })
A.settle(v)
check(cond(v, "DoorFrontLeft") == 50, "after vanilla setPartCondition: new snapshot, not given back")
hit(v, "EngineDoor", 40)
H.fire("OnClientCommand", "vehicle", "repairPart", admin, { vehicle = v.id })
A.settle(v)
check(cond(v, "EngineDoor") == 40, "after vanilla repairPart: new snapshot")
hit(v, "EngineDoor", 30)
H.fire("OnClientCommand", "vehicle", "crash", admin, { vehicle = v.id })
A.settle(v)
check(cond(v, "EngineDoor") == 35, "other vanilla commands leave the snapshot")
hit(v, "WindowFrontLeft", 70)
ISInstallVehiclePart.complete({ vehicle = v, part = v.parts.Battery, character = admin })
A.settle(v)
check(cond(v, "WindowFrontLeft") == 70 and vanilla.install == 1, "after any part install complete: new snapshot")
hit(v, "WindowFrontLeft", 60)
H.side(false, false)
ISUninstallVehiclePart.complete({ vehicle = v, part = v.parts.Battery, character = admin })
H.side(false, true)
A.settle(v)
check(cond(v, "WindowFrontLeft") == 60 and vanilla.uninstall == 1, "after any part uninstall complete: new snapshot")

H.section("Armor: taking an upgrade off (server)")
T.Keys = { card = function(p) return p.card end, phoneKey = function() return nil end }
VehicleUtils = setmetatable({ CheckForUnlockedDoorsWindows = function(car) return car.open == true end },
    { __index = saved.VehicleUtils })
IsoObjectChange = { MECHANIC_ACTION_DONE = "mechanicActionDone" }
Capability = setmetatable({ UseMechanicsCheat = "UseMechanicsCheat" }, { __index = saved.Capability })
local function player(name, o)
    local p = H.player(o or {})
    p.name, p.changes = name, {}
    function p:sendObjectChange(what, args) self.changes[#self.changes + 1] = { what = what, success = args.success } end
    return p
end
local function lastDeny()
    local m = H.sent[#H.sent]
    return m and m.command == "deny" and m.args.reason or nil
end
local function takeOff(chr, car_, pid)
    H.sent = {}
    local before = vanilla.uninstall
    local r = ISUninstallVehiclePart.complete({ vehicle = car_, part = car_.parts[pid], character = chr })
    return r, vanilla.uninstall > before
end
v = car("Inner")
local kit = v.parts.TeslaArmor.item
local thief = player("thief")
local r, ran = takeOff(thief, v, "TeslaArmor")
check(r == false and not ran and v.parts.TeslaArmor.item == kit, "no key, locked car: refused, kit stays, vanilla complete not run")
check(lastDeny() == "CAR_LOCKED" and v.itemTx == 1 and thief.changes[1] and thief.changes[1].success == false,
    "refused: told why (CAR_LOCKED), part sent again, mechanics window flashes red")
r, ran = takeOff(thief, v, "TeslaFridge")
check(r == false and not ran and v.parts.TeslaFridge.item ~= nil, "no key: the fridge stays too")
r, ran = takeOff(thief, v, "Battery")
check(r == true and ran, "any other part: vanilla as is (its own client test)")
v.open = true
r, ran = takeOff(thief, v, "TeslaArmor")
check(r == true and ran and v.parts.TeslaArmor.item == nil, "a door unlocked or open (vanilla's rule): anyone may")
v = car("Inner")
v.parts.TeslaArmor.cond = 100
local owner = player("owner", { keys = { [v.keyId] = true } })
r, ran = takeOff(owner, v, "TeslaArmor")
check(r == true and ran, "this car's key on the player: allowed")
v = car("Outer")
local carded = player("carded")
carded.card = {}
r, ran = takeOff(carded, v, "TeslaArmor")
check(r == true and ran, "this car's key card (this mod's key): allowed")
v = car("Inner")
SandboxVars.VehicleEasyUse = true
r, ran = takeOff(thief, v, "TeslaArmor")
SandboxVars.VehicleEasyUse = false
check(r == true and ran, "VehicleEasyUse: allowed")
v = car("Inner")
r, ran = takeOff(player("adm", { admin = true }), v, "TeslaArmor")
check(r == true and ran, "an admin's mechanics cheat: allowed")

v = car("Inner")
owner = player("owner", { keys = { [v.keyId] = true } })
v.parts.TeslaFridge.box.n = 2
r, ran = takeOff(owner, v, "TeslaFridge")
check(r == false and not ran and v.parts.TeslaFridge.item ~= nil and lastDeny() == nil,
    "fridge with food in it: refused even with the key (requireEmpty), no message")
v.parts.TeslaFridge.box.n = 0
v.parts.TeslaFridge.content = 1
r, ran = takeOff(owner, v, "TeslaFridge")
check(r == false and not ran, "fridge with a content amount: refused")
v.parts.TeslaFridge.content = 0
r, ran = takeOff(owner, v, "TeslaFridge")
check(r == true and ran, "empty fridge, key: allowed")

v = car("Inner")
owner = player("owner", { keys = { [v.keyId] = true } })
local asked
MinidoracatVehicleManagerAPI = { canUse = function(p, car_, code) asked = code; return p == owner, "NOT_SHARED" end }
r, ran = takeOff(player("member", { keys = { [v.keyId] = true } }), v, "TeslaArmor")
check(r == false and not ran and asked == "SALVAGE" and lastDeny() == "NOT_OWNER",
    "VehicleManager says no (SALVAGE): refused even with the key, NOT_OWNER")
MinidoracatVehicleManagerAPI = { canUse = function() return false, "RENT_LOCKED" end }
r = takeOff(owner, v, "TeslaArmor")
check(r == false and lastDeny() == "RENT_LOCKED", "VehicleManager's own reasons are kept")
MinidoracatVehicleManagerAPI = { canUse = function() return true, "UNCLAIMED" end }
r, ran = takeOff(thief, v, "TeslaArmor")
check(r == false and not ran, "VehicleManager says yes (an unclaimed car) but no key on a locked car: refused")
r, ran = takeOff(owner, v, "TeslaArmor")
check(r == true and ran, "VehicleManager yes and the key: allowed")
MinidoracatVehicleManagerAPI = nil

v = car("Inner")
H.side(false, false)
r, ran = takeOff(thief, v, "TeslaArmor")
H.side(false, true)
check(r == true and ran, "SP: no server check (vanilla's own test on this machine)")

-- leave the shared world as it was
A.cars = {}
H.sent = {}
require, ISInstallVehiclePart, ISUninstallVehiclePart = saved.require, saved.ISInstallVehiclePart, saved.ISUninstallVehiclePart
T.Liftgate, T.Keys, VehicleUtils, IsoObjectChange, Capability = saved.Liftgate, saved.Keys, saved.VehicleUtils,
    saved.IsoObjectChange, saved.Capability
