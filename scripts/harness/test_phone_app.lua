-- Phone app server side (server/MinidoracatTesla/Remote.lua): reach (grid up: any distance; grid down: Bluetooth 30),
-- only phone key holders get answers or may act, VehicleManager rights on top of the key, the last record for an
-- unloaded car, the horn's one-shot OnTick, alerts per car, and the bearing the client draws (PhoneApp.bearing).
-- Runs after test_keys / test_liftgate / test_charging (name order): Keys, Liftgate and Charging are loaded by then.
local F = dofile("scripts/harness/park_fakes.lua")
local check = (H and H.check) or function(ok, label) print((ok and "  PASS  " or "  FAIL  ") .. label); if not ok then error(label) end end

require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/Battery"
require "MinidoracatTesla/Inbox"
require "MinidoracatTesla/Sentry"
require "MinidoracatTesla/Keys"
require "MinidoracatTesla/KeyActions"
require "MinidoracatTesla/Liftgate"
local T = MinidoracatTesla
local K, S = T.Keys, T.Sentry
local statsBefore = { flashes = S.stats.flashes, tickAdds = S.stats.tickAdds, tickRemoves = S.stats.tickRemoves }

local grid = true
local savedWorld = getWorld
getWorld = function() return { isHydroPowerOn = function() return grid end } end
local savedSound = playServerSound
playServerSound = function() end
require "MinidoracatTesla/Remote"
local R = T.Remote
local cmds = T.ServerCommands

-- ------------------------------------------------------------------ fakes: doors, horn, phone key inventory
local function door(id)
    local d = { locked = false, open = false, broken = false }
    local p = { id = id, d = d }
    function p:getId() return self.id end
    function p:getInventoryItem() return {} end
    p.doorObj = {
        isLocked = function() return d.locked end, setLocked = function(_, b) d.locked = b end,
        isOpen = function() return d.open end, setOpen = function(_, b) d.open = b end,
        isLockBroken = function() return d.broken end,
    }
    function p:getDoor() return self.doorObj end
    return p
end
local function tesla(keyId)
    local v = F.track(F.vehicle({ keyId = keyId, pct = 80 }))
    v.z = 0
    v.doors = { door("DoorFrontLeft"), door("DoorFrontRight"), door("DoorRearLeft"), door("DoorRearRight") }
    v.parts.TrunkDoor, v.parts.EngineDoor = door("TrunkDoor"), door("EngineDoor")
    for _, d in ipairs(v.doors) do v.parts[d.id] = d end
    v.hue = 0.6
    function v:getZ() return self.z end
    function v:getPassengerDoor(seat) return self.doors[seat + 1] end
    function v:areAllDoorsLocked()
        for _, d in ipairs(self.doors) do if not d.d.locked then return false end end
        return true
    end
    function v:setTrunkLocked(b) self.parts.TrunkDoor.d.locked = b end
    function v:transmitPartDoor() self.doorTx = (self.doorTx or 0) + 1 end
    function v:getColorHue() return self.hue end
    function v:getColorSaturation() return 0.5 end
    function v:getColorValue() return 0.5 end
    function v:setColorHSV(h) self.hue = h end
    function v:onHornStart() self.horn = true; self.hornStarts = (self.hornStarts or 0) + 1 end
    function v:onHornStop() self.horn = false end
    return v
end

local function container(...)
    local c = { items = { ... } }
    function c:getFirstTypeEvalArgRecurse(t, fn, arg)
        for _, it in ipairs(self.items) do if it.ft == t and fn(it, arg) then return it end end
    end
    function c:haveThisKeyId() return nil end
    return c
end
local function phoneKey(keyId)
    return { ft = K.PHONE_KEY, keyId = keyId, getKeyId = function(self) return self.keyId end }
end
local function player(name, inv, x, y)
    local p = { name = name, inv = inv, x = x, y = y }
    function p:getUsername() return self.name end
    function p:getVehicle() return self.vehicle end
    function p:getInventory() return self.inv end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:DistTo(v) local dx, dy = self.x - v:getX(), self.y - v:getY(); return math.sqrt(dx * dx + dy * dy) end
    return p
end
local function last(cmd) local m = F.lastSent(cmd); return m and m.args end
local function act(p, a, on) F.sent = {}; cmds.appAction(p, { key = p.key, act = a, on = on }); return last("appDone") end

local v = tesla(9001)
F.fire("OnSpawnVehicleEnd", v)
local owner = player("owner", container(phoneKey(9001)), v.x + 500, v.y)
owner.key = 9001
local stranger = player("stranger", container(), v.x + 1, v.y)
stranger.key = 9001
F.online = { owner, stranger }

-- ------------------------------------------------------------------ reach
H.section("phone app: reach")
check(K.appReach(owner, v) == "net", "grid up: 500 tiles away -> net (any distance while the server has the car)")
grid = false
check(K.appReach(owner, v) == nil, "grid down: 500 tiles -> no link")
owner.x = v.x + 30
check(K.appReach(owner, v) == "bt", "grid down: 30 tiles -> Bluetooth")
owner.x = v.x + 30.5
check(K.appReach(owner, v) == nil, "grid down: 30.5 tiles -> no link")
check(K.appReach(owner, nil) == nil, "car not loaded -> no link")
grid = true
owner.x = v.x + 500

-- ------------------------------------------------------------------ holders only
H.section("phone app: holders only")
F.sent = {}
cmds.appStatus(stranger, { key = 9001 })
check(last("appState") == nil, "appStatus without the phone key: no answer about the car")
local d = act(stranger, "unlock")
check(d and d.why == "NO_PHONE_KEY" and d.key == nil, "appAction without the phone key: NO_PHONE_KEY")
v.doors[1].d.locked = true
d = act(stranger, "unlock")
check(v.doors[1].d.locked, "stranger's unlock changed nothing")
v.doors[1].d.locked = false
F.sent = {}
cmds.appAction(owner, { key = 9001.5, act = "lock" })
check(last("appDone").why == "NO_PHONE_KEY" and not v.doors[1].d.locked, "fractional key -> refused")
F.sent = {}
cmds.appAction(owner, { key = 9001, act = "selfDestruct" })
check(#F.sent == 0, "unknown action: ignored")

-- ------------------------------------------------------------------ actions over the network
H.section("phone app: actions")
d = act(owner, "lock")
check(d and d.why == nil and v:areAllDoorsLocked() and v.parts.TrunkDoor.d.locked, "net, 500 tiles: lock -> every door and the trunk locked")
check(last("appState") and last("appState").locked == true and last("appState").link == "net", "after an action: fresh appState (locked, net)")
F.runTicks(50, 450)
v.parts.GasTank:getModData().sentry = { by = "owner", at = F.hours, kwh = 50, since = F.hours }
d = act(owner, "unlock")
check(d.why == nil and not v.doors[1].d.locked and v.parts.GasTank:getModData().sentry == nil, "unlock: doors open, sentry disarmed (like the card)")
F.runTicks(50, 450)
local fl = S.stats.flashes
d = act(owner, "flash")
check(d.why == nil and S.stats.flashes == fl + 1, "flash: the sentry flash")
F.runTicks(50, 450)

-- horn: vanilla onHornStart, stopped by a one-shot OnTick after a second
local ticks = F.handlers("OnTick")
d = act(owner, "horn")
check(d.why == nil and v.horn == true and F.handlers("OnTick") == ticks + 1, "horn: vanilla horn on, one OnTick")
act(owner, "horn")
check(v.hornStarts == 1, "horn again while sounding: not restarted")
F.advance(900); F.fire("OnTick")
check(v.horn == true, "horn: still on at 0.9 s")
F.advance(200); F.fire("OnTick")
check(v.horn == false and F.handlers("OnTick") == ticks and R.hornCount() == 0, "horn: off after 1 s, OnTick removed")

-- sentry from far away: the usual rules but not the 10 tiles
d = act(owner, "sentry", true)
check(d.why == "UNLOCKED", "sentry on with doors unlocked -> UNLOCKED (original rule)")
act(owner, "lock")
F.runTicks(50, 450)
d = act(owner, "sentry", true)
check(d.why == nil and v.parts.GasTank:getModData().sentry ~= nil, "sentry on from 500 tiles (app reach instead of 10 tiles)")
d = act(owner, "sentry", false)
check(d.why == nil and v.parts.GasTank:getModData().sentry == nil, "sentry off remotely")
d = act(owner, "sentry", false)
check(d.why == "SENTRY_OFF", "sentry off when already off -> SENTRY_OFF")

-- frunk / liftgate: unlock first, open, animate
d = act(owner, "trunk")
check(d.why == nil and v.parts.TrunkDoor.d.open and not v.parts.TrunkDoor.d.locked, "liftgate: was locked -> unlocked and opened")
check(last("partAnim") and last("partAnim").part == "TrunkDoor" and last("partAnim").sound == true, "liftgate: partAnim with sound to clients")
act(owner, "trunk")
check(not v.parts.TrunkDoor.d.open, "liftgate again: closed")
v.kmh = 20
d = act(owner, "frunk")
check(d.why == "MOVING" and not v.parts.EngineDoor.d.open, "frunk while moving -> MOVING")
v.kmh = 0
d = act(owner, "frunk")
check(d.why == nil and v.parts.EngineDoor.d.open, "frunk opens")
act(owner, "frunk")

-- charging: no cable -> NOT_PLUGGED; with a cable the call goes to Charge.setStopped
d = act(owner, "charge", false)
check(d.why == "NOT_PLUGGED", "charge with no cable -> NOT_PLUGGED")
local realStop = T.Charge and T.Charge.setStopped
T.Charge = T.Charge or {}
local stopArg
T.Charge.setStopped = function(car, stop) stopArg = { car, stop }; return true end
d = act(owner, "charge", false)
check(d.why == nil and stopArg[1] == v and stopArg[2] == true, "charge off -> Charge.setStopped(v, true)")
act(owner, "charge", true)
check(stopArg[2] == false, "charge on -> Charge.setStopped(v, false)")
T.Charge.setStopped = realStop

-- ------------------------------------------------------------------ power out: Bluetooth only
H.section("phone app: power out")
grid = false
owner.x = v.x + 31
d = act(owner, "unlock")
check(d.why == "NO_LINK" and v:areAllDoorsLocked(), "grid down, 31 tiles: NO_LINK, still locked")
owner.x = v.x + 29
d = act(owner, "unlock")
check(d.why == nil and not v:areAllDoorsLocked(), "grid down, 29 tiles: Bluetooth, unlocked")
F.runTicks(50, 450)
F.sent = {}
owner.x = v.x + 31
cmds.appStatus(owner, { key = 9001 })
local st = last("appState")
check(st and st.link == nil and st.pct ~= nil and st.locked == false, "grid down, 31 tiles: status = last record, no link")
grid = true

-- ------------------------------------------------------------------ last record for an unloaded car
H.section("phone app: last record")
act(owner, "lock")
F.runTicks(50, 450)
local hours = F.hours
F.vehicles[v:getId()] = nil -- the car unloads
F.sent = {}
cmds.appStatus(owner, { key = 9001 })
st = last("appState")
check(st and st.link == nil and st.x == math.floor(v.x) and st.locked == true and st.pct == 80 and st.car == "MinidoracatTesla_ModelY",
    "unloaded: the server's last record (position, locked, battery)")
check(st and st.h ~= nil, "last record carries its game hour")
d = act(owner, "unlock")
check(d.why == "NO_LINK", "unloaded: actions refused (NO_LINK) even with the grid up")
local other = tesla(4242) -- the id is reused by another car: never mistaken for ours
other.id = v:getId()
F.vehicles[other.id] = other
check(R.loadedCar(9001) == nil, "vehicle id reused by another car: not this keyId's car")
F.vehicles[other.id] = v

-- ------------------------------------------------------------------ VehicleManager rights on top of the key
H.section("phone app: VehicleManager")
local asked = {}
local answer = { ok = false, why = "NOT_AUTHORIZED" }
MinidoracatVehicleManagerAPI = { canUse = function(p, car, code, ctx)
    asked[#asked + 1] = { code = code, silent = ctx and ctx.silent, mod = ctx and ctx.mod }
    return answer.ok, answer.why
end }
d = act(owner, "unlock")
check(d.why == "NOT_OWNER" and v:areAllDoorsLocked(), "car bound to someone else: phone key holder refused (NOT_OWNER), still locked")
check(asked[#asked].code == "PASSENGER" and asked[#asked].silent == true and asked[#asked].mod == T.MODULE, "VM asked PASSENGER, silent")
answer.why = "RENT_LOCKED"
d = act(owner, "flash")
check(d.why == "RENT_LOCKED", "VM rental lock -> RENT_LOCKED")
answer.why = "FACTION_PAUSED"
check(act(owner, "horn").why == "FACTION_PAUSED", "VM faction paused -> FACTION_PAUSED")
asked = {}
act(owner, "frunk")
check(#asked == 2 and asked[1].code == "REPAIR" and asked[2].code == "SALVAGE", "frunk: VM REPAIR or SALVAGE (the hood adapter)")
asked = {}
act(owner, "trunk")
check(asked[1].code == "CARGO", "liftgate: VM CARGO")
asked = {}
act(owner, "charge", true)
check(asked[1].code == "FUEL", "charging: VM FUEL")
answer.why = "NOT_AUTHORIZED"
F.sent = {}
asked = {}
cmds.appStatus(owner, { key = 9001 })
st = last("appState")
check(st and st.deny == "NOT_OWNER" and st.x == nil and asked[1].code == "TRACK" and asked[1].silent == true,
    "status: VM TRACK (silent), refused -> no position")
answer.ok, answer.why = true, "UNCLAIMED"
d = act(owner, "unlock")
check(d.why == nil and not v:areAllDoorsLocked(), "unclaimed car (VM UNCLAIMED): the phone key is enough")
F.runTicks(50, 450)
d = act(stranger, "unlock")
check(d.why == "NO_PHONE_KEY", "unclaimed car: no phone key still refused (VM UNCLAIMED is not enough)")
MinidoracatVehicleManagerAPI = nil

-- ------------------------------------------------------------------ alerts per car
H.section("phone app: alerts")
for i = 1, 12 do T.Inbox.notify("owner", { kind = "touch", what = "door", key = 9001, i = i }) end
T.Inbox.notify("owner", { kind = "touch", what = "door", key = 5555 })
F.sent = {}
cmds.appAlerts(owner, { key = 9001 })
local al = last("appAlerts")
check(al and #al.list == R.MAX_ALERTS and al.list[R.MAX_ALERTS].i == 12, "alerts: this car's newest 10")
F.sent = {}
cmds.appAlerts(stranger, { key = 9001 })
check(last("appAlerts") == nil, "alerts: nothing for a player without the phone key")

-- ------------------------------------------------------------------ client bearing (pure math in PhoneApp.lua)
H.section("phone app: bearing")
local function bearing(px, py, cx, cy)
    local dx, dy = cx - px, cy - py
    local compass = math.deg(math.atan2(dx, -dy)) % 360
    local sx, sy = dx - dy, (dx + dy) / 2
    return math.floor((compass + 22.5) / 45) % 8 + 1, math.deg(math.atan2(sx, -sy)) % 360
end
local ci, ang = bearing(0, 0, 0, -100)
check(ci == 1 and ang > 0 and ang < 90, "car due north (-y): compass N, arrow up-right on the iso screen")
ci, ang = bearing(0, 0, 100, 100)
check(ci == 4 and math.abs(ang - 180) < 1e-6, "car south-east (+x+y): compass SE, arrow straight down")
local src = io.open("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/client/MinidoracatTesla/PhoneApp.lua"):read("*a")
check(src:find("local sx, sy = dx %- dy, %(dx %+ dy%) / 2", 1) ~= nil, "PhoneApp.bearing uses the same iso projection")

-- ------------------------------------------------------------------ restore (later tests use their own fakes)
Events.OnSpawnVehicleEnd.Remove(R.onLoad)
T.Remote = nil
getWorld, playServerSound = savedWorld, savedSound
for k, n in pairs(statsBefore) do S.stats[k] = n end
F.done()
