-- Cybertruck (plan-cybertruck-1030 items 2 and 5): the bed's Vault rule (Core.lua ContainerAccess.Vault), the tonneau
-- cover on the dashboard and in the car's lock (Liftgate.lua), bed lights on Auto, the roof light bar command and
-- Armor Glass (Truck.lua). The real light, anim and the second client are E2E.
local check = H.check
local T = MinidoracatTesla
local MEDIA = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/shared/MinidoracatTesla/"

local saved = { ISSmashWindow = ISSmashWindow, instanceof = instanceof, getOnlinePlayers = getOnlinePlayers,
    sendDamage = sendDamage, getPlayer = getPlayer }
function getPlayer() return nil end -- SP partAnim's sound (Liftgate.lua client handler)
-- vanilla ISSmashWindow (shared/TimedActions/ISSmashWindow.lua:23-60): start hands SP to Java, complete hits on the
-- MP server only
ISSmashWindow = {
    start = function(self) self.character.javaSmash = (self.character.javaSmash or 0) + 1 end,
    complete = function(self)
        if isServer() and not self.window:isDestroyed() then self.window:hit(self.character) end
        return true
    end,
    setActionAnim = function(self, anim) self.anim = anim end,
}
function instanceof(o, cls) return type(o) == "table" and o._class == cls end
local damaged = {}
function sendDamage(p) damaged[#damaged + 1] = p end
H.stub("TimedActions/ISSmashWindow")
H.side(false, false)
dofile(MEDIA .. "Truck.lua")
local R = T.Truck

-- ------------------------------------------------------------------ fakes
local function door(v, id, item)
    local d = { open = false, locked = false, broken = false }
    function d:isOpen() return self.open end
    function d:setOpen(b) self.open = b end
    function d:isLocked() return self.locked end
    function d:setLocked(b) self.locked = b end
    function d:isLockBroken() return self.broken end
    v.parts[id] = { id = id, door = d, item = item ~= false and {} or nil, getId = function(self) return self.id end,
        getDoor = function(self) return self.door end, getInventoryItem = function(self) return self.item end,
        getVehicle = function() return v end }
    return d
end
local function light(v, id)
    local l = { active = false, tx = 0 }
    function l:getActive() return self.active end
    v.parts[id] = { id = id, light = l, getId = function(self) return self.id end, getLight = function(self) return self.light end,
        setLightActive = function(self, b) if self.light.active ~= b then self.light.active = b; self.light.tx = self.light.tx + 1 end end }
    return l
end
local function truck(o)
    o = o or {}
    o.script = o.script or "Base.MinidoracatTesla_Cybertruck"
    local v = H.vehicle(o)
    v.area = {} -- areas the test stands the player in
    function v:isInArea(id, chr) return chr.areas and chr.areas[id] == true end
    function v:transmitPartDoor() self.doorTx = (self.doorTx or 0) + 1 end
    function v:areAllDoorsLocked() return self.cabinLocked == true end
    function v:toggleLockedDoor(part) if not part.door.broken then part.door.locked = false end end
    function v:playPartAnim() end
    function v:playPartSound() end
    v.gate, v.cover = door(v, "TrunkDoor"), door(v, "TrunkTonneau")
    door(v, "EngineDoor")
    v.bed = { getArea = function() return "TruckBed" end, getId = function() return "TruckBed" end }
    v.parts.TruckBed = v.bed
    return v
end
local function at(...)
    local p = H.player({})
    p.areas = {}
    for _, a in ipairs({ ... }) do p.areas[a] = true end
    return p
end

-- ------------------------------------------------------------------ Vault
H.section("Cybertruck bed: the Vault rule")
local v = truck()
local vault = T.ContainerAccess.Vault
local rear, side, nowhere = at("TruckBed"), at("BedSide"), at()
local function reach(p) return vault(v, v.bed, p) end
check(not reach(rear) and not reach(side) and not reach(nowhere), "both shut: not from the rear, not from the side")
v.gate.open = true
check(reach(rear) and not reach(side), "tailgate down: from the rear only")
v.gate.open, v.cover.open = false, true
check(reach(rear) and reach(side) and not reach(nowhere), "tonneau open: from the rear and the sides")
v.gate.open = true
check(reach(rear) and reach(side), "both open: rear and sides")
local inside = at("TruckBed")
inside.vehicle = v
check(not vault(v, v.bed, inside), "sitting in the truck: never (vanilla TruckBed rule)")
v.gate.open, v.cover.open = false, false
v.parts.TrunkTonneau.item = nil
check(reach(rear) and reach(side), "tonneau removed: open from the rear and the sides")
v.parts.TrunkTonneau.item = {}
v.parts.TrunkDoor.item = nil
check(reach(rear) and not reach(side), "tailgate removed, tonneau shut: the rear only")
v.parts.TrunkDoor.item = {}
v.gate.locked, v.cover.locked = true, true
v.cover.open = true
check(reach(side), "locked car, tonneau left open: still reached (the lock holds it where it is, manual p.32)")
v.cover.open, v.gate.locked, v.cover.locked = false, false, false
check(T.ContainerAccess.Frunk ~= nil and T.lidOpen(v, "Nothing") == true, "a lid the car lacks counts as open (T.lidOpen)")

-- ------------------------------------------------------------------ tonneau on the dashboard, lock, bed lights
H.section("Cybertruck: tonneau cover on the dashboard, in the car's lock; bed lights on Auto")
-- SP load of Liftgate.lua over plain vanilla door actions (ISOpenVehicleDoor.lua:61-97): it wraps their complete
saved.ISOpenVehicleDoor, saved.ISCloseVehicleDoor = ISOpenVehicleDoor, ISCloseVehicleDoor
ISOpenVehicleDoor = { complete = function(self) self.part:getDoor():setOpen(true); return true end }
ISCloseVehicleDoor = { complete = function(self) self.part:getDoor():setOpen(false); return true end }
dofile(MEDIA .. "Liftgate.lua")
local L = T.Liftgate
check(L.PARTS.TrunkTonneau and L.LIDS.TrunkTonneau, "tonneau is a dashboard door and a lid that locks with the car")
local bl = light(v, "BedLight")
local driver = H.player({})
driver.vehicle, v.driver = v, driver
v.cover.locked = true
T.ServerCommands.liftgate(driver, { vid = v:getId(), part = "TrunkTonneau" })
check(v.cover.open and not v.cover.locked and bl.active and bl.tx == 1, "driver opens the locked tonneau: unlocked, open, bed lights on")
T.ServerCommands.liftgate(driver, { vid = v:getId(), part = "TrunkDoor" })
check(v.gate.open and bl.active and bl.tx == 1, "tailgate down too: lights stay on, nothing resent")
T.ServerCommands.liftgate(driver, { vid = v:getId(), part = "TrunkTonneau" })
check(not v.cover.open and bl.active, "tonneau shut, tailgate still down: lights on")
T.ServerCommands.liftgate(driver, { vid = v:getId(), part = "TrunkDoor" })
check(not v.gate.open and not bl.active and bl.tx == 2, "both shut: lights off")
-- vanilla open / close actions (Liftgate.lua wraps their complete)
ISOpenVehicleDoor.complete({ vehicle = v, part = v.parts.TrunkDoor, character = driver })
check(v.gate.open and bl.active, "tailgate opened by hand (vanilla action): lights on")
ISCloseVehicleDoor.complete({ vehicle = v, part = v.parts.TrunkDoor, character = driver })
check(not v.gate.open and not bl.active, "...and shut by hand: off")
v.parts.TrunkTonneau.item = nil
v.cover.open = true
R.bedLight(v)
check(not bl.active, "a removed tonneau is no lid to sense: lights stay off")
v.parts.TrunkTonneau.item, v.cover.open = {}, false
L.lockLids(v, true)
check(v.cover.locked and v.gate.locked, "car locked: the tonneau locks with the tailgate")
L.lockLids(v, false)
check(not v.cover.locked, "unlocked with the car")
v.cabinLocked = true
v.cover.open = true
check(L.relock(v, v.parts.TrunkTonneau) == false, "open tonneau on a locked car: not relocked while open")
v.cover.open = false
check(L.relock(v, v.parts.TrunkTonneau) == true and v.cover.locked, "shut on a locked car: locked again")
v.cabinLocked, v.cover.locked = false, false
local my = H.vehicle({ script = "Base.MinidoracatTesla_ModelY" })
check(pcall(R.bedLight, my), "a car with no bed lights: nothing to do, no error")

-- ------------------------------------------------------------------ roof light bar
H.section("Cybertruck: roof light bar (roofLight command)")
local rl = light(v, "RoofLight")
local cmd = T.ServerCommands.roofLight
local function denied(reason) local s = H.sent[#H.sent]; return s and s.command == "deny" and s.args.reason == reason end
cmd(driver, { vid = v:getId() })
check(rl.active and rl.tx == 1 and R.roofLightOn(v), "driver: on, sent once (setLightActive)")
cmd(driver, { vid = v:getId() })
check(not rl.active and rl.tx == 2, "again: off")
H.side(false, true)
local passenger = H.player({ name = "bob", x = v.x, y = v.y })
passenger.vehicle = v
cmd(passenger, { vid = v:getId() })
check(denied("NOT_DRIVER") and not rl.active and rl.tx == 2, "passenger: NOT_DRIVER, unchanged")
local far = H.player({ name = "far", x = v.x + 40, y = v.y })
cmd(far, { vid = v:getId() })
check(denied("TOO_FAR") and not rl.active, "40 tiles away: TOO_FAR")
cmd(driver, { vid = 9.5 })
check(denied("NO_VEHICLE") and not rl.active, "a fractional vid: NO_VEHICLE")
my.driver = driver
driver.vehicle = my
cmd(driver, { vid = my:getId() })
check(not denied("NOT_DRIVER"), "a car without a light bar: nothing, no deny")
driver.vehicle = v
H.side(false, false)

-- ------------------------------------------------------------------ Armor Glass
H.section("Cybertruck: Armor Glass takes 3 smashes (ISSmashWindow)")
local function glass(car)
    local w = { _class = "VehicleWindow", hp = 100, hits = 0 }
    local part = { getVehicle = function() return car end, getId = function() return "WindowFrontLeft" end }
    function w:getPart() return part end
    function w:getHealth() return self.hp end
    function w:isDestroyed() return self.hp <= 0 end
    function w:damage(n) self.hits = self.hits + 1; self.hp = math.max(0, self.hp - n) end
    function w:hit() self.hits = self.hits + 1; self.hp = 0 end
    return w
end
local function hands(p, weapon)
    function p:getPrimaryHandItem() return weapon and { _class = "HandWeapon" } or nil end
    function p:getSecondaryHandItem() return nil end
    p.cuts = 0
    function p:getBodyDamage() return { setScratchedWindow = function() p.cuts = p.cuts + 1 end } end
    return p
end
local thief = hands(H.player({ name = "thief" }), true)
local w = glass(v)
local a = setmetatable({ character = thief, window = w, vehiclePart = {} }, { __index = ISSmashWindow })
a:start()
check(a.anim == "Destroy" and not thief.javaSmash, "SP start: a heavy swing, not vanilla's one-hit Java smash")
a:complete()
check(not w:isDestroyed() and w.hp == 66, "SP first smash: cracked, 66 left")
a:complete()
check(not w:isDestroyed() and w.hp == 32, "second: 32 left")
a:complete()
check(w:isDestroyed() and w.hits == 3, "third: broken")
check(a:complete() == true and w.hits == 3, "a broken window: nothing more")
H.side(true, false)
local w2 = glass(v)
a = setmetatable({ character = thief, window = w2 }, { __index = ISSmashWindow })
a:complete()
check(w2.hp == 100, "MP client: complete hits nothing (the server counts)")
H.side(false, true)
a:complete()
check(w2.hp == 66 and thief.cuts == 0 and #damaged == 0, "MP server: counts the smash; a weapon in hand cuts nobody")
local bare = hands(H.player({ name = "fist" }), false)
a = setmetatable({ character = bare, window = w2 }, { __index = ISSmashWindow })
a:complete()
check(w2.hp == 32 and bare.cuts == 1 and damaged[1] == bare, "bare hands: a cut, sent to the client (sendDamage)")
H.side(false, false)
local mw = glass(my)
a = setmetatable({ character = thief, window = mw }, { __index = ISSmashWindow })
a:start()
a:complete()
check(thief.javaSmash == 1 and not a.anim and mw.hp == 100, "Model Y SP: vanilla start (Java smash), vanilla complete")
H.side(false, true)
a:complete()
check(mw:isDestroyed() and mw.hits == 1, "Model Y MP server: one hit breaks it, as vanilla")
local house = { _class = "IsoWindow", isDestroyed = function() return false end, hit = function(self) self.hitIt = true end }
a = setmetatable({ character = thief, window = house }, { __index = ISSmashWindow })
a:complete()
check(house.hitIt, "a house window: vanilla")

ISSmashWindow, instanceof, getOnlinePlayers, sendDamage = saved.ISSmashWindow, saved.instanceof, saved.getOnlinePlayers, saved.sendDamage
getPlayer, ISOpenVehicleDoor, ISCloseVehicleDoor = saved.getPlayer, saved.ISOpenVehicleDoor, saved.ISCloseVehicleDoor
H.side(false, true)
