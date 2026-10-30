-- Phone app (server/MinidoracatTesla/Remote.lua): reach (grid up: any distance; grid down: Bluetooth, sandbox
-- BluetoothRange, default 50), only phone
-- key holders get answers or may act, VehicleManager rights on top of the key, the last record for an unloaded car
-- (with the paint), the horn's one-shot OnTick, alerts per car, the bearing the client draws (Keys.bearing); the
-- client (client/MinidoracatTesla/PhoneApp.lua): pages, back, joypad rows, paint picture, scrolling, text fit.
-- Runs after test_hud / test_keys / test_liftgate / test_charging (name order): HUD, Keys, Liftgate and Charging are
-- loaded by then.
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
-- the server-only GOS store (smoke_harness.lua H.gos; never Global ModData, which any client may fetch by name)
local gos = H.gos
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
    function v:transmitPartDoor() self.doorTx = (self.doorTx or 0) + 1 end
    function v:getColorHue() return self.hue end
    v.charge12 = 1
    function v:getBatteryCharge() return self.charge12 end
    function v:getColorSaturation() return 0.5 end
    function v:getColorValue() return 0.5 end
    function v:setColorHSV(h) self.hue = h end
    function v:onHornStart() self.horn = true; self.hornStarts = (self.hornStarts or 0) + 1 end
    function v:onHornStop() self.horn = false end
    v.skinIndex = 4 -- UltraRed (Core.lua colors[5])
    function v:getSkinIndex() return self.skinIndex end
    return v
end

local function container(...)
    local c = { items = { ... } }
    function c:getFirstTypeEvalArgRecurse(t, fn, arg)
        for _, it in ipairs(self.items) do if it.ft == t and fn(it, arg) then return it end end
    end
    function c:getAllTypeRecurse(t)
        local out = {}
        for _, it in ipairs(self.items) do if it.ft == t then out[#out + 1] = it end end
        return { size = function() return #out end, get = function(_, i) return out[i + 1] end }
    end
    function c:containsTypeRecurse(t) return self:getAllTypeRecurse(t):size() > 0 end
    function c:haveThisKeyId() return nil end
    return c
end
local nextPhone = 70000
local function phoneKey(keyId)
    nextPhone = nextPhone + 1
    local it = { ft = K.PHONE_KEY, keyId = keyId, id = nextPhone }
    function it:getKeyId() return self.keyId end
    function it:getID() return self.id end
    function it:hasModData() return self.md ~= nil end
    function it:getModData() self.md = self.md or {}; return self.md end
    return it
end
-- a phone key paired with several cars, as KeyActions.phonePair leaves it (server record + client mirror)
local function multiPhone(ids)
    local it = phoneKey(ids[#ids])
    T.Store.get("phones")[tostring(it.id)] = ids
    local cars = {}
    for i = 1, #ids do cars[i] = "MinidoracatTesla_ModelY" end
    it:getModData()[K.PAIRED], it.md[K.PAIRED_CARS] = ids, cars
    return it
end
local oids = 0
local function player(name, inv, x, y)
    oids = oids + 1
    local p = { name = name, inv = inv, x = x, y = y, oid = oids * 4 }
    function p:getOnlineID() return self.oid end -- slot * 4, like H.player
    function p:getSteamID() return 0 end
    function p:getUsername() return self.name end
    function p:getPlayerNum() return 0 end
    function p:getVehicle() return self.vehicle end
    function p:getInventory() return self.inv end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:DistTo(v) return math.abs(self.x - v:getX()) + math.abs(self.y - v:getY()) end -- the engine's: Manhattan (IsoMovingObject.java:605-607)
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
SandboxVars.MinidoracatTesla = SandboxVars.MinidoracatTesla or {}
local TSB = SandboxVars.MinidoracatTesla
TSB.BluetoothRange = nil
check(K.btRange() == 50, "Bluetooth range: sandbox unset -> 50")
check(K.appReach(owner, v) == "net", "grid up: 500 tiles away -> net (any distance while the server has the car)")
TSB.BluetoothRange = 0
check(K.appReach(owner, v) == "net", "grid up, Bluetooth range 0: still net (the range is for a power cut only)")
TSB.BluetoothRange = nil
grid = false
check(K.appReach(owner, v) == nil, "grid down: 500 tiles -> no link")
owner.x = v.x + 50
check(K.appReach(owner, v) == "bt", "grid down, default range: 50 tiles -> Bluetooth")
owner.x = v.x + 50.5
check(K.appReach(owner, v) == nil, "grid down, default range: 50.5 tiles -> no link")
check(K.appReach(owner, nil) == nil, "car not loaded -> no link")
TSB.BluetoothRange = 0
owner.x = v.x
check(K.btRange() == 0 and K.appReach(owner, v) == nil, "grid down, range 0: no link even beside the car")
TSB.BluetoothRange = 100
owner.x = v.x + 64
check(K.btRange() == 64 and K.appReach(owner, v) == "bt", "range 100: clamped to 64 (64 tiles -> Bluetooth)")
owner.x = v.x + 64.5
check(K.appReach(owner, v) == nil, "...64.5 tiles -> no link")
TSB.BluetoothRange = -5
check(K.btRange() == 0, "range -5: clamped to 0")
TSB.BluetoothRange = "x"
check(K.btRange() == 50, "range unreadable (a string): 50")
TSB.BluetoothRange = 0 / 0
check(K.btRange() == 50, "range NaN: 50")
TSB.BluetoothRange = 12
owner.x = v.x + 12
check(K.appReach(owner, v) == "bt", "range 12: 12 tiles -> Bluetooth")
owner.x = v.x + 13
check(K.appReach(owner, v) == nil, "range 12: 13 tiles -> no link")
local gtNL = getText
getText = function(k, a) return a and (k .. "|" .. a) or k end
check(T.denyText("NO_LINK") == "IGUI_MinidoracatTesla_Deny_NO_LINK|12", "NO_LINK text carries the range set (12)")
TSB.BluetoothRange = nil
check(T.denyText("NO_LINK") == "IGUI_MinidoracatTesla_Deny_NO_LINK|50", "...and the default when unset (50)")
getText = gtNL
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
v.charge12 = 0
d = act(owner, "horn")
check(d.why == "NO_12V" and not v.horn and F.handlers("OnTick") == ticks, "horn with a flat 12 V battery -> NO_12V, no OnTick (vanilla needs power)")
v.charge12 = 1
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
local s0, a0 = v.parts.GasTank:getModData().sentry, R.stats.actions
d = act(owner, "sentry", true)
check(d.why == nil and d.on == true and v.parts.GasTank:getModData().sentry == s0 and R.stats.actions == a0,
    "sentry on again (a 2 s old view, a double tap): nothing changes, not counted as an action")
d = act(owner, "sentry", false)
check(d.why == nil and v.parts.GasTank:getModData().sentry == nil, "sentry off remotely")
d = act(owner, "sentry", false)
check(d.why == "SENTRY_OFF", "sentry off when already off -> SENTRY_OFF")

-- frunk / liftgate: unlock first, open, animate; closing on a locked car locks the lid again
check(v:areAllDoorsLocked(), "car locked before the liftgate")
d = act(owner, "trunk", true)
check(d.why == nil and v.parts.TrunkDoor.d.open and not v.parts.TrunkDoor.d.locked, "liftgate: was locked -> unlocked and opened")
check(last("partAnim") and last("partAnim").part == "TrunkDoor" and last("partAnim").sound == true, "liftgate: partAnim with sound to clients")
d = act(owner, "trunk", false)
check(d.on == false and not v.parts.TrunkDoor.d.open and v.parts.TrunkDoor.d.locked, "liftgate closed on a locked car: locked again")
v.parts.TrunkDoor.d.locked, v.parts.TrunkDoor.d.broken = false, true -- unlocked with a broken lock (vanilla spawns these)
act(owner, "trunk", true)
d = act(owner, "trunk", false)
check(d.on == false and not v.parts.TrunkDoor.d.locked, "broken lock: closing doesn't lock it (it could never open again)")
check(act(owner, "trunk", true).why == nil, "broken lock: opens again from the app")
act(owner, "trunk", false)
v.parts.TrunkDoor.d.broken = false
v.kmh = 20
d = act(owner, "frunk", true)
check(d.why == "MOVING" and not v.parts.EngineDoor.d.open, "frunk while moving -> MOVING")
v.kmh = 0
d = act(owner, "frunk", true)
check(d.why == nil and v.parts.EngineDoor.d.open and d.on == true, "frunk opens (appDone on = true)")
d = act(owner, "frunk", false)
check(d.why == nil and not v.parts.EngineDoor.d.open and d.on == false, "frunk closes (appDone on = false)")
check(v.parts.EngineDoor.d.locked, "frunk lid closed on a locked car: locked again, same rule as the liftgate")
v.parts.TrunkDoor.d.open = true -- someone opened the liftgate by hand since the app's last poll
local tx = v.doorTx or 0
d = act(owner, "trunk", true)
check(d.why == nil and v.parts.TrunkDoor.d.open and d.on == true and (v.doorTx or 0) == tx, "liftgate already open, app asks open: nothing moves")
d = act(owner, "trunk", false)
check(d.why == nil and not v.parts.TrunkDoor.d.open and d.on == false, "liftgate: app asks closed -> closed")
-- the Cybertruck's tonneau cover: the same swing as the liftgate (unlock, open, close locks again on a locked car);
-- a car without one says NO_DOOR and moves nothing
d = act(owner, "tonneau", true)
check(d.why == "NO_DOOR", "tonneau on a car without one -> NO_DOOR")
v.parts.TrunkTonneau = door("TrunkTonneau")
v.parts.TrunkTonneau.d.locked = true
d = act(owner, "tonneau", true)
check(d.why == nil and d.on == true and v.parts.TrunkTonneau.d.open and not v.parts.TrunkTonneau.d.locked
    and last("partAnim") and last("partAnim").part == "TrunkTonneau", "tonneau: was locked -> unlocked, opened, partAnim")
check(last("appState") and last("appState").tonneau == true, "tonneau: the record says open")
d = act(owner, "tonneau", false)
check(d.why == nil and not v.parts.TrunkTonneau.d.open and v.parts.TrunkTonneau.d.locked, "tonneau closed on a locked car: locked again")
v.parts.TrunkTonneau = nil

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
owner.x = v.x + 51
d = act(owner, "unlock")
check(d.why == "NO_LINK" and v:areAllDoorsLocked(), "grid down, 51 tiles: NO_LINK, still locked")
owner.x = v.x + 49
d = act(owner, "unlock")
check(d.why == nil and not v:areAllDoorsLocked(), "grid down, 49 tiles: Bluetooth, unlocked")
F.runTicks(50, 450)
F.sent = {}
owner.x = v.x + 51
cmds.appStatus(owner, { key = 9001 })
local st = last("appState")
check(st and st.link == nil and st.pct ~= nil and st.locked == false, "grid down, 51 tiles: status = last record, no link")
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
check(st and st.skin == 4, "last record carries the paint (skin index) for the app's car picture")
local db = gos[T.Store.SYSTEM]
local saved = {}
for _, k in ipairs(db.keys) do saved[k] = true end
check(db and db.registers == 1 and db.md.seen["9001"] ~= nil and saved.seen and saved.alerts and saved.inbox and saved.keyIds,
    "records in the server-only GOS store (saved keys seen, alerts, inbox, keyIds; registered once)")
check(db.md.getInitialStateForClient() == nil, "GOS system sends nothing to clients")
local wild = tesla(7777) -- a Tesla the world spawned, never seen by an app
R.onLoad(wild)
R.remember(wild)
check(db.md.seen["7777"] == nil, "a loaded car the app never asked about gets no record")
F.vehicles[wild:getId()] = nil
d = act(owner, "unlock")
check(d.why == "NOT_LOADED", "unloaded: actions refused (NOT_LOADED) even with the grid up")
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
check(asked[#asked].code == "PASSENGER" and asked[#asked].silent == false and asked[#asked].mod == T.MODULE,
    "VM asked PASSENGER, not silent (an admin's remote unlock is audited like in person)")
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
asked = {}
v.parts.GasTank:getModData().sentry = nil
d = act(owner, "sentry", true)
check(d.why == "NOT_OWNER" and asked[1].code == "PASSENGER" and v.parts.GasTank:getModData().sentry == nil,
    "sentry: VM PASSENGER like a remote lock; car bound to someone else -> an old phone key can't arm it")
v.parts.GasTank:getModData().sentry = { by = "owner", at = F.hours, kwh = 50, since = F.hours }
d = act(owner, "sentry", false)
check(d.why == "NOT_OWNER" and v.parts.GasTank:getModData().sentry ~= nil, "...nor turn it off from afar")
v.parts.GasTank:getModData().sentry = nil
F.sent = {}
asked = {}
cmds.appStatus(owner, { key = 9001 })
st = last("appState")
check(st and st.deny == "NOT_OWNER" and st.x == nil and asked[1].code == "TRACK" and asked[1].silent == true,
    "status: VM TRACK (silent), refused -> no position")
F.vehicles[v:getId()] = nil -- unloaded: VM can't be asked, so no record and no alerts (a revoked share stays revoked)
F.sent = {}
cmds.appStatus(owner, { key = 9001 })
st = last("appState")
check(st and st.deny == "UNVERIFIED" and st.x == nil and st.pct == nil, "older VehicleManager (no canTrackKeyId), car unloaded: status refused (UNVERIFIED), no record")
cmds.appAlerts(owner, { key = 9001 })
check(last("appAlerts") and last("appAlerts").deny == "UNVERIFIED" and last("appAlerts").list == nil, "older VehicleManager, car unloaded: no alerts, told why")
F.vehicles[v:getId()] = v
answer.ok, answer.why = true, "UNCLAIMED"
d = act(owner, "unlock")
check(d.why == nil and not v:areAllDoorsLocked(), "unclaimed car (VM UNCLAIMED): the phone key is enough")
F.runTicks(50, 450)
d = act(stranger, "unlock")
check(d.why == "NO_PHONE_KEY", "unclaimed car: no phone key still refused (VM UNCLAIMED is not enough)")
MinidoracatVehicleManagerAPI = nil

-- ------------------------------------------------------------------ record while charging: the HUD's projection
H.section("phone app: charging record")
local gas = v.parts.GasTank
gas:getModData().chg = { kw = 10, last = F.hours - 0.5, added = 0, target = 90 }
local before = T.Battery.kwh(gas)
local r = R.remember(v)
local want = T.Battery.chargeEstimate(gas, gas:getModData().chg, F.hours)
check(want > before and r.pct == math.floor(want * 100 / T.Battery.capacity(gas) + 0.5) and r.chg == "charging",
    "charging: record pct = the HUD projection since the last settlement")
check(r.mins and r.mins > 0, "charging: minutes left from the projection")
local wasRunning = v.running
v.running = true
check(R.remember(v).drive == false, "motor on while plugged in: the app says Parked, like the HUD's P")
gas:getModData().chg = nil
check(R.remember(v).drive == true, "motor on, unplugged: Driving")
SandboxVars.CarGasConsumption = 0 -- vanilla Gas Consumption 0: driving takes no charge (Core.lua T.kmPerKwh nil)
local rz = R.remember(v)
check(rz.km == nil and rz.pct ~= nil, "Gas Consumption 0: the record has no km (no range limit), pct as usual")
local gasKwh = T.Battery.kwh(gas)
gas:setContainerContentAmount(0)
check(R.remember(v).km == 0, "Gas Consumption 0, empty pack: the record says 0 km")
gas:setContainerContentAmount(gasKwh)
SandboxVars.CarGasConsumption = nil
check(R.remember(v).km ~= nil, "...a number again once driving takes charge")
v.running = wasRunning
-- the battery update also runs for VirtualVehicle (no getKeyId): no record, the drain goes on
local realRemember, remembered = R.remember, 0
R.remember = function() remembered = remembered + 1 end
local fakePart = { getInventoryItem = function() return {} end, getModData = function() return {} end }
T.Update.Battery({ _class = "VirtualVehicle" }, fakePart, 0)
check(remembered == 0, "battery update with a VirtualVehicle (no getKeyId): no record")
T.Update.Battery({ _class = "BaseVehicle" }, fakePart, 0)
check(remembered == 1, "battery update with a BaseVehicle: record")
R.remember = realRemember

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

-- ------------------------------------------------------------------ one phone key, several cars
H.section("phone app: one phone, several cars")
local v2 = tesla(9002)
v2.skinIndex = 1 -- PearlWhite
F.fire("OnSpawnVehicleEnd", v2)
local two = player("two", container(multiPhone({ 9001, 9002 })), v.x + 500, v.y)
F.sent = {}
cmds.appAction(two, { key = 9001, act = "flash" })
check(last("appDone") and last("appDone").why == nil, "two-car phone (item keyId 9002): flash the car paired first")
F.runTicks(50, 450)
F.sent = {}
cmds.appStatusAll(two, { keys = { 9001, 9002, 4242, 9001.5 } })
local all = last("appStates")
check(all and #all.list == 2 and all.list[1].key == 9001 and all.list[2].key == 9002 and all.list[2].skin == 1,
    "batch (the car list): one state per car the phone holds, the rest left out")
F.sent = {}
cmds.appStatusAll(owner, { keys = { 9001, 9002 } })
all = last("appStates")
check(#all.list == 1 and all.list[1].key == 9001, "batch from a phone for 9001 only: nothing about 9002")
F.sent = {}
cmds.appAction(owner, { key = 9002, act = "unlock" })
check(last("appDone").why == "NO_PHONE_KEY", "a phone for 9001 only: 9002's unlock -> NO_PHONE_KEY")
local big = {}
for i = 1, 100 do big[i] = 9001 end
F.sent = {}
local status0 = R.stats.status
cmds.appStatusAll(two, { keys = big })
check(#last("appStates").list == 1 and R.stats.status == status0 + 1, "batch: a repeated key answered once")
for i = 1, 100 do big[i] = i % 2 == 0 and 9001 or 9002 end
big[17] = 1 -- (past MAX_BATCH: never looked at)
F.sent = {}
cmds.appStatusAll(two, { keys = big })
check(#last("appStates").list == 2, "batch: at most MAX_BATCH keys read, each car once")
F.sent = {}
cmds.appStatusAll(two, { keys = "9001" })
check(#F.sent == 0, "batch: keys not a list -> ignored")

-- ------------------------------------------------------------------ summon (ACT.summon, a fake MinidoracatAutoDriveAPI)
H.section("phone app: summon (server)")
local AD = { summonApiVersion = 1, calls = {}, stops = {}, info = {}, answer = { true } }
function AD.startSummon(p, car, opts)
    AD.calls[#AD.calls + 1] = { p = p, car = car, opts = opts }
    if AD.answer[1] then AD.info[car] = { by = p:getUsername(), phase = "starting", mode = opts.mode, startedMs = 5000 + #AD.calls } end
    return AD.answer[1], AD.answer[2]
end
function AD.stopSummon(car, code) AD.stops[#AD.stops + 1] = { car = car, code = code }; AD.info[car] = nil; return true end
function AD.summonInfo(car) return AD.info[car] end
function v:getVehicleTowing() return self.towing end
function v:getVehicleTowedBy() return nil end
function v:isEngineWorking() return self.working ~= false end
local function summon(p, on, extra)
    F.sent = {}
    local args = { key = p.key, act = "summon", on = on }
    for k, val in pairs(extra or {}) do args[k] = val end
    cmds.appAction(p, args)
    return last("appDone")
end
v.running = false
d = summon(owner, true)
check(d.why == "NO_AUTODRIVE" and #AD.calls == 0 and not v.running, "no AutoDrive summon API: NO_AUTODRIVE, nothing started")
MinidoracatAutoDriveAPI = { summonApiVersion = 0, startSummon = AD.startSummon, stopSummon = AD.stopSummon, summonInfo = AD.summonInfo }
check(summon(owner, true).why == "NO_AUTODRIVE", "summonApiVersion 0: NO_AUTODRIVE")
MinidoracatAutoDriveAPI = AD
F.vehicles[v:getId()] = nil
check(summon(owner, true).why == "NOT_LOADED" and #AD.calls == 0, "car not loaded on the server: NOT_LOADED")
F.vehicles[v:getId()] = v
MinidoracatAutoDriveAPI = AD
check(summon(stranger, true).why == "NO_PHONE_KEY" and #AD.calls == 0, "no phone key: NO_PHONE_KEY")
grid = false
owner.x = v.x + 51
check(summon(owner, true).why == "NO_LINK" and #AD.calls == 0, "grid down, 51 tiles: NO_LINK")
SandboxVars.MinidoracatTesla.BluetoothRange = 10
owner.x = v.x + 20
check(summon(owner, true).why == "NO_LINK" and #AD.calls == 0, "grid down, Bluetooth range 10, 20 tiles: NO_LINK")
SandboxVars.MinidoracatTesla.BluetoothRange = nil
owner.x = v.x + 20
asked = {}
answer.ok, answer.why = false, "NOT_AUTHORIZED"
MinidoracatVehicleManagerAPI = { canUse = function(p, car, code, ctx)
    asked[#asked + 1] = { code = code, silent = ctx and ctx.silent }
    return answer.ok, answer.why
end }
d = summon(owner, true)
check(d.why == "NOT_OWNER" and asked[1].code == "DRIVE" and not asked[1].silent and #AD.calls == 0,
    "VehicleManager asked DRIVE (not silent); only TRACK shared -> NOT_OWNER, AutoDrive never called")
MinidoracatVehicleManagerAPI = nil
owner.vehicle = v
check(summon(owner, true).why == "NOT_OUTSIDE", "summoner in a car: NOT_OUTSIDE")
owner.vehicle = nil
v.passengers = 1
check(summon(owner, true).why == "OCCUPIED", "someone in the car: OCCUPIED")
v.passengers = 0
v.parts.GasTank:getModData().chg = { kw = 7 }
check(summon(owner, true).why == "CABLE_PLUGGED", "plugged in: CABLE_PLUGGED")
v.parts.GasTank:getModData().chg = nil
v.towing = {}
check(summon(owner, true).why == "TOWED", "towing: TOWED")
v.towing = nil
v.charge12 = 0
check(summon(owner, true).why == "NO_12V", "flat 12 V: NO_12V")
v.charge12 = 1
v.working = false
check(summon(owner, true).why == "CANT_START" and #AD.calls == 0, "motor can't run (empty pack): CANT_START")
v.working = nil
check(summon(owner, true, { mode = "fly" }).why == "NO_TARGET", "unknown mode: NO_TARGET")
check(summon(owner, true, { mode = "target", x = 0 / 0, y = 5 }).why == "NO_TARGET", "target with NaN: NO_TARGET")
check(summon(owner, true, { mode = "dumb", dir = 2 }).why == "NO_TARGET" and #AD.calls == 0, "dumb with dir 2: NO_TARGET")
AD.answer = { false, "UI_MinidoracatAutoDrive_NeedModule" }
d = summon(owner, true)
check(d.why == "UI_MinidoracatAutoDrive_NeedModule" and #AD.calls == 1, "AutoDrive refuses: its translation key goes to the app")
check(T.denyText(d.why) == "UI_MinidoracatAutoDrive_NeedModule" and T.denyText("IGUI_MVM_Protected") == "IGUI_MVM_Protected"
    and T.denyText("TOWED") == "IGUI_MinidoracatTesla_Deny_TOWED", "denyText: whole keys as they are, Tesla codes as Deny_<code>")
AD.answer, AD.calls = { true }, {}
v.parts.GasTank:getModData().sentry = { by = "owner", at = F.hours, kwh = 50, since = F.hours }
d = summon(owner, true)
local c1 = AD.calls[1]
check(d.why == nil and d.on == true and #AD.calls == 1 and c1.p == owner and c1.car == v and c1.opts.mode == "come"
    and c1.opts.startEngine == true and type(c1.opts.onEnd) == "function", "come: startSummon once (mode come, startEngine, onEnd)")
check(v.parts.GasTank:getModData().sentry == nil, "sentry switched off once the car is on its way")
F.runTicks(50, 450)
d = summon(owner, true)
check(d.why == nil and d.on == true and #AD.calls == 1, "start again while it runs: done, startSummon not called twice")
F.sent = {}
cmds.appStatus(owner, { key = 9001 })
st = last("appState")
check(st.vid == v:getId() and st.summon and st.summon.mine == true and st.summon.phase == "starting" and st.summon.mode == "come",
    "status over a live link: the vehicle id and the summon (mine, phase, mode)")
local two2 = player("other", container(phoneKey(9001)), v.x + 3, v.y)
two2.key = 9001
check(summon(two2, true).why == "UI_MinidoracatAutoDrive_SummonBusy", "another holder starts while it runs: SummonBusy")
F.sent = {}
cmds.appStatus(two2, { key = 9001 })
check(last("appState").summon.mine == false, "the other holder sees someone else's summon")
-- who counts as the summoner (Remote.isSummoner): the session's username while that name is online once (a dedicated
-- server keeps names unique); online twice (a Steam co-op host checks only the SteamID, LoginPacket.java:78-90): only
-- the main player whose account (SteamID) is that name
local info = AD.info[v]
H.steam = true
local SID_A, SID_B = 76561198000000112, 76561198000000128
local realIds, realOnline = T.Store.get("ids").owner, F.online
T.Store.get("ids").owner = { sid = SID_B, src = "E2E", at = 0 } -- the name is bound to someone else: owner unverified
F.online = { owner, two2 }
check(T.Remote.isSummoner(owner, info), "Steam, the name online once: the summoner even with no verified account")
T.Store.get("ids").owner = { sid = SID_A, src = "E2E", at = 0 }
local pA, pB, pG = H.player({ name = "owner", sid = SID_A }), H.player({ name = "owner", sid = SID_B }), H.player({ name = "owner", num = 1 })
F.online = { pG, two2 }
check(T.Remote.isSummoner(pG, info), "a split-screen guest, the name online once: its own summon")
F.online = { pA, pB, pG }
check(T.Remote.isSummoner(pA, info), "co-op host, the name online three times: the main player with the bound SteamID is the summoner")
check(not T.Remote.isSummoner(pB, info) and not T.Remote.isSummoner(pG, info),
    "...the other login (another SteamID) and a split-screen guest with that name are not")
F.online, T.Store.get("ids").owner, H.steam = realOnline, realIds, false
check(not T.Remote.isSummoner(owner, nil) and not T.Remote.isSummoner(two2, info), "no summon, or another name: no")
grid = false
owner.x, two2.x = v.x + 55, v.x + 55
d = summon(two2, false)
check(d.why == "NO_LINK" and #AD.stops == 0, "grid down, 55 tiles: another holder's stop is refused (NO_LINK)")
asked = {}
answer.ok, answer.why = false, "NOT_AUTHORIZED"
MinidoracatVehicleManagerAPI = { canUse = function(p, car, code) asked[#asked + 1] = code; return false, "NOT_AUTHORIZED" end }
d = summon(owner, false)
local askedDrive = false
for _, c in ipairs(asked) do if c == "DRIVE" then askedDrive = true end end
check(d.why == nil and d.on == false and #AD.stops == 1 and AD.stops[1].code == "CANCELLED" and not askedDrive,
    "grid down, 55 tiles, share taken back: the summoner's own stop still works (no reach, no DRIVE asked)")
MinidoracatVehicleManagerAPI = nil
grid = true
owner.x, two2.x = v.x + 500, v.x + 3
d = summon(owner, false)
check(d.why == nil and d.on == false and #AD.stops == 1, "stop when none runs: done, nothing called")
-- grid down: the picked spot within Bluetooth from the player too (the app's ring), checked again on the server
grid = false
owner.x = v.x + 20
AD.calls = {}
d = summon(owner, true, { mode = "target", x = owner.x + 51, y = owner.y })
check(d.why == "UI_MinidoracatAutoDrive_SummonTooFar" and #AD.calls == 0,
    "grid down: a spot 51 tiles from the player (past Bluetooth 50) -> too far, nothing started")
d = summon(owner, true, { mode = "target", x = owner.x + 50, y = owner.y })
check(d.why == nil and #AD.calls == 1, "grid down: a spot 50 tiles away -> AutoDrive asked")
AD.info[v] = nil
grid = true
owner.x = v.x + 500
AD.calls = {}
summon(owner, true, { mode = "target", x = 1012.5, y = 1990.5 })
c1 = AD.calls[1]
check(c1 and c1.opts.mode == "target" and c1.opts.x == 1012.5 and c1.opts.y == 1990.5, "target: x, y handed over as sent")
AD.info[v] = nil
local batt, realStart, realEnd = {}, T.Battery.summonStart, T.Battery.summonEnd -- the drain's start and last leg
T.Battery.summonStart = function(car, ms) batt.start, batt.ms = car, ms end
T.Battery.summonEnd = function(car) batt.ended = car end
summon(owner, true, { mode = "dumb", dir = -1 })
check(AD.calls[2].opts.mode == "dumb" and AD.calls[2].opts.dir == -1 and AD.calls[2].opts.x == nil, "dumb: dir handed over")
check(batt.start == v and batt.ms == AD.info[v].startedMs and batt.ended == nil,
    "started: the battery marks where this summon (AutoDrive's startedMs) starts")
F.sent = {}
local touched = 0
MinidoracatVehicleManager = { Parked = { touch = function(car) if car == v then touched = touched + 1 end end } }
AD.calls[2].opts.onEnd(v, "ARRIVED", owner) -- AutoDrive's call, through the closure ACT.summon gave it
MinidoracatVehicleManager = nil
d = last("appDone")
check(d and d.act == "summonEnd" and d.why == "ARRIVED" and d.key == 9001 and touched == 1 and batt.ended == v,
    "onEnd: the summoner hears the stop code; VehicleManager's parked guard touched; the battery charges the last leg")
F.sent = {}
T.Battery.summonEnd = function() error("a removed car") end
local okEnd = pcall(AD.calls[2].opts.onEnd, v, "GONE", owner) -- AutoDrive calls onEnd in a pcall
d = last("appDone")
check(not okEnd and d and d.why == "GONE", "an error after it (swallowed by AutoDrive): the summoner heard the end first")
T.Battery.summonStart, T.Battery.summonEnd = realStart, realEnd
F.sent = {}
R.summonEnded(v, "LEFT", nil)
check(#F.sent == 0, "onEnd with the summoner gone: nothing sent, no error")
F.sent = {}
AD.calls[2].opts.onEnd(nil, "GONE", owner) -- the car itself gone: AutoDrive has no vehicle to hand back
d = last("appDone")
check(d and d.act == "summonEnd" and d.why == "GONE" and d.key == 9001, "onEnd GONE (no vehicle): the summoner still hears it")
AD.info[v] = nil
owner.x = v.x + 500
grid = true
MinidoracatAutoDriveAPI = nil

-- ------------------------------------------------------------------ client bearing (pure math in PhoneApp.lua)
H.section("phone app: bearing")
local function bearing(...)
    local _, ci, ang = K.bearing(...)
    return ci, ang
end
local ci, ang = bearing(0, 0, 0, -100)
check(ci == 1 and ang > 0 and ang < 90, "car due north (-y): compass N, arrow up-right on the iso screen")
ci, ang = bearing(0, 0, 100, 100)
check(ci == 4 and math.abs(ang - 180) < 1e-6, "car south-east (+x+y): compass SE, arrow straight down")
ci, ang = bearing(0, 0, 0, 100)
check(ci == 5 and ang > 180 and ang < 270, "car due south: compass S, arrow down-left (no negative angle)")
ci, ang = bearing(0, 0, -100, 0)
check(ci == 7 and ang > 270 and ang < 360, "car due west: compass W (index from a negative atan2), arrow up-left")

-- ------------------------------------------------------------------ client: pages, joypad, paint, fit (PhoneApp.lua)
-- UI fakes of its own (only what PhoneApp / HUD.drawTip touch); DrawText calls are kept to check nothing is drawn
-- outside the phone. getText returns the key, so every string is long: the fitting is exercised everywhere.
H.section("phone app: client")
H.side(true, false)
local SW, SH = 1920, 1009
function getPlayerScreenLeft() return 0 end
function getPlayerScreenTop() return 0 end
function getPlayerScreenWidth() return SW end
function getPlayerScreenHeight() return SH end
UIFont = { Small = "Small", Medium = "Medium", Large = "Large" }
local FONT_H, CHAR_W = { Small = 19, Medium = 22, Large = 30 }, { Small = 8, Medium = 10, Large = 13 }
local tmFake = { getFontHeight = function(_, f) return FONT_H[f] end, MeasureStringX = function(_, f, s) return #s * CHAR_W[f] end }
function getTextManager() return tmFake end
function getTexture(path) return { path = path } end
local gtime = getGameTime()
gtime.getHour, gtime.getMinutes = function() return 14 end, function() return 32 end
local drawn, recording = {}, true
local UI = {}
UI.__index = UI
function UI:derive(name) local t = { Type = name }; setmetatable(t, { __index = self }); t.__index = t; return t end
function UI:new(x, y, w, h) local o = { x = x, y = y, width = w, height = h, visible = true }; setmetatable(o, self); return o end
function UI:initialise() end
function UI:instantiate()
    local me = self
    self.javaObject = {
        DrawSubTextureRGBA = function() end, DrawTextureAngle = function() end, DrawTextureScaled = function() end,
        DrawText = function(_, font, s, x, y) if recording then drawn[#drawn + 1] = { font = font, s = s, x = x, y = y, el = me } end end,
    }
    if self.createChildren then self:createChildren() end
end
function UI:setX(x) self.x = x end
function UI:setY(y) self.y = y end
function UI:setWidth(w) self.width = w end
function UI:setHeight(h) self.height = h end
function UI:setVisible(v) self.visible = v end
function UI:isVisible() return self.visible end
function UI:getIsVisible() return self.visible end
function UI:addToUIManager() end
function UI:removeFromUIManager() end
function UI:bringToTop() end
function UI:addChild() end
function UI:update() end
function UI:getAbsoluteX() return self.x end
function UI:getAbsoluteY() return self.y end
function UI:setStencilRect() end
function UI:clearStencilRect() end
function UI:drawTextureScaled() end
function UI:drawTextRight(s, x, y, r, g, b, a, font) self.javaObject:DrawText(font, s, x - #s * CHAR_W[font], y) end
function UI:drawTextCentre(s, x, y, r, g, b, a, font) self.javaObject:DrawText(font, s, x - #s * CHAR_W[font] / 2, y) end
function UI:onGainJoypadFocus(jd) self.joyfocus = jd end
function UI:onLoseJoypadFocus() self.joyfocus = nil end
ISPanelJoypad = UI:derive("ISPanelJoypad")
ISUIElement = UI:derive("ISUIElement")
-- the pick page's UIWorldMap (PickMap): 2 px a tile around the centre it is given
local mapCalls = { data = 0, style = 0, zoom = nil }
UIWorldMap = { new = function(el)
    local api = { el = el, cx = 0, cy = 0, k = 2 }
    function api:setMapItem() end
    function api:setMaxZoom() end
    function api:addData() mapCalls.data = mapCalls.data + 1 end
    function api:endDirectoryData() end
    function api:addImages() end
    function api:setBoundsFromWorld() end
    function api:setBoolean(n, b) mapCalls[n] = b end
    function api:centerOn(x, y) self.cx, self.cy = x, y end
    function api:setZoom(z) mapCalls.zoom = z end
    function api:worldToUIX(x) return (x - self.cx) * self.k + self.el.width / 2 end
    function api:worldToUIY(_, y) return (y - self.cy) * self.k + self.el.height / 2 end
    function api:uiToWorldX(x) return self.cx + (x - self.el.width / 2) / self.k end
    function api:uiToWorldY(_, y) return self.cy + (y - self.el.height / 2) / self.k end
    local jo = { DrawSubTextureRGBA = function() end, DrawText = function() end }
    function jo:getAPIv3() return api end
    for _, m in ipairs({ "setX", "setY", "setWidth", "setHeight", "setAnchorLeft", "setAnchorTop" }) do jo[m] = function() end end
    return jo
end }
MapItem = { getSingleton = function() return {} end }
function getLotDirectories() return { size = function() return 1 end, get = function() return "Muldraugh, KY" end } end
function fileExists() return true end
MapUtils = { initDefaultStyleV1 = function() mapCalls.style = mapCalls.style + 1 end }
ISButton = UI:derive("ISButton")
function ISButton:new(x, y, w, h, title, target, onclick)
    local o = UI.new(self, x, y, w, h)
    o.title, o.target, o.onclick, o.enable, o.borderColor = title, target, onclick, true, { a = 1 }
    return o
end
function ISButton:setEnable(e) self.enable = e; self.borderColor = { a = 1 } end
function ISButton:isMouseOver() return self.mouseOver == true end
function ISButton:forceClick() if self.visible and self.enable then self.onclick(self.target, self) end end -- ISButton.lua
Joypad = { AButton = 0, BButton = 1 }
JoypadState = { players = {} }
function setJoypadFocus() end
ISWorldMap = { IsAllowed = function() return true end, ShowWorldMap = function() end, render = function() end, close = function() end }
-- the phone's dropped spot (PhoneApp posFile): a file store; vanilla ISPanelJoypad's drag (moveWithMouse) sets moving
local files = {}
function getFileReader(name)
    local s = files[name]
    if not s then return nil end
    return { readLine = function() local l = s; s = nil; return l end, close = function() end }
end
function getFileWriter(name)
    local buf = {}
    return { write = function(_, s) buf[#buf + 1] = s end, close = function() files[name] = table.concat(buf) end }
end
function ISPanelJoypad:onMouseDown() self.moving = true end
function ISPanelJoypad:onMouseUp() self.moving = false end
function ISPanelJoypad:onMouseUpOutside() self.moving = false end
H.stub("ISUI/ISPanelJoypad")
H.stub("ISUI/ISButton")
H.stub("ISUI/Maps/ISWorldMap")
H.stub("ISUI/Maps/ISMapDefinitions")
H.stub("ISUI/ISUIElement")
require "MinidoracatTesla/PhoneApp"
local App = T.PhoneApp
local myInv = container(multiPhone({ 9001, 9002 }))
local me = { getX = function() return 1000 end, getY = function() return 1990 end, isDead = function() return false end,
    getInventory = function() return myInv end, getSteamID = function() return 0 end }
local realSpecific = getSpecificPlayer
getSpecificPlayer = function() return me end
local function sentLast() local m = H.clientSent[#H.clientSent]; return m and m.command, m and m.args end
local a = App.open(0, { keyId = 9001 })
local function state(t)
    local s = { key = 9001, link = "net", grid = true, car = "MinidoracatTesla_ModelY", x = 1000, y = 2000, pct = 80, km = 600,
        locked = true, skin = 4, h = H.hours() }
    for k, val in pairs(t or {}) do s[k] = val end
    for k, val in pairs(t or {}) do if val == false and k ~= "locked" then s[k] = nil end end -- false = not sent
    H.advanceMs(1) -- a new state time: the app's change signature
    T.ClientCommands.appState(s)
    if a:read() then a:layout() end
end
-- every string drawn by a full redraw of the current page sits inside the phone
local function textInside()
    drawn = {}
    a:prerender()
    a:render()
    for _, d in ipairs(drawn) do
        local wid = #d.s * CHAR_W[d.font]
        if d.x < 0 or d.x + wid > a.width + 0.5 then return false, d.s .. " at " .. d.x .. "+" .. wid .. " > " .. a.width end
    end
    return #drawn > 0, #drawn .. " strings"
end
check(a and a.inUI and a.page == "home" and sentLast() == "appAlerts", "open: home page, asks for the alerts once (the list's count)")
state()
local colors = T.Specs["Base.MinidoracatTesla_ModelY"].colors
check(a.carTex.path == "media/textures/MinidoracatTesla/HUD/app_car_UltraRed.png", "skin 4 -> the UltraRed picture")
local missing = {}
for _, c in ipairs(colors) do
    local f = io.open("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/textures/MinidoracatTesla/HUD/app_car_" .. c.name .. ".png", "rb")
    if f then f:close() else missing[#missing + 1] = c.name end
end
check(#missing == 0, "a car picture for each of the 8 paints (" .. table.concat(missing, ",") .. ")")
state({ link = false, skin = false })
check(a.paintName == colors[1].name and a.sSub2 ~= nil and not a.b.lock.enable,
    "a record from before the paint field: first paint; offline: 'can't reach' line, lock greyed")
state({ skin = 99 })
check(a.paintName == colors[1].name, "unknown skin index -> first paint")
local realGTkm = getText
getText = function(k, a) return a and (k .. "|" .. a) or k end
state({ km = false }) -- vanilla Gas Consumption 0: the record has no km (Remote.lua)
check(a.sBat:find("_App_Km|--", 1, true) ~= nil, "no km in the record (Gas Consumption 0): the battery line says -- (" .. a.sBat .. ")")
getText = realGTkm
state()
-- each car its own picture files, paints, wordmark, map glyph and lid words (Specs appCar / colors / model,
-- T.CarPartNames): the Model 3 shares six paint names with the Model Y, so a shared file name would show the other car
check(a.model == "ModelY" and a.b.trunk.tipKey == "IGUI_MinidoracatTesla_Tip_AppTrunk"
    and a.rowSub.controls == "IGUI_MinidoracatTesla_App_ControlsSub", "Model Y: wordmark ModelY, the liftgate's tip and words")
T.ClientCommands.appDone({ key = 9001, act = "trunk", on = true })
check(a.toast.text == "IGUI_MinidoracatTesla_App_Done_trunk_on", "Model Y: 'liftgate opened'")
state({ car = "MinidoracatTesla_Model3", skin = 5 })
local c3 = T.Specs["Base.MinidoracatTesla_Model3"].colors
check(a.carTex.path == "media/textures/MinidoracatTesla/HUD/app_car_model3_DeepBlue.png" and a.paintName == c3[6].name
    and a.model == "Model3" and T.HUDAtlas[2].wm_Model3 ~= nil and T.HUDAtlas[2].car_Model3 ~= nil,
    "Model 3 skin 5 -> app_car_model3_DeepBlue (its own paint table), MODEL 3 wordmark, its own top view")
missing = {}
for _, c in ipairs(c3) do
    local f = io.open("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/textures/MinidoracatTesla/HUD/app_car_model3_" .. c.name .. ".png", "rb")
    if f then f:close() else missing[#missing + 1] = c.name end
end
check(#missing == 0, "Model 3: a car picture for each of its 8 paints (" .. table.concat(missing, ",") .. ")")
check(a.b.trunk.tipKey == "IGUI_MinidoracatTesla_Tip_AppTrunkLid" and a.b.qtrunk.tipKey == "IGUI_MinidoracatTesla_Tip_AppTrunkLid"
    and a.b.lock.tipKey == "IGUI_MinidoracatTesla_Tip_AppUnlockLid"
    and a.rowSub.controls == "IGUI_MinidoracatTesla_App_ControlsSubLid", "Model 3: tips and the controls line say trunk (lid)")
local realGT = getText -- the cell is narrow: short words so fitText keeps them whole
getText = function(k, ...)
    if k == "IGUI_MinidoracatTesla_App_TrunkLid" then return "LID" elseif k == "IGUI_MinidoracatTesla_App_Trunk" then return "GATE" end
    return realGT(k, ...)
end
a.b.controls:forceClick()
local lidTitle = a.b.trunk.sTitle
a.b.back:forceClick()
getText = realGT
check(lidTitle == "LID", "Model 3: the controls page's lid button is titled with the trunk lid key (" .. tostring(lidTitle) .. ")")
T.ClientCommands.appDone({ key = 9001, act = "trunk", on = false })
check(a.toast.text == "IGUI_MinidoracatTesla_App_Done_trunkLid_off", "Model 3: 'trunk closed', not 'liftgate closed'")
-- Cybertruck: a tonneau cell after the tailgate (Specs tonneau), the tailgate's words, the lock tips naming the tonneau;
-- the other cars have no tonneau cell
state({ car = "MinidoracatTesla_Cybertruck", skin = 0, tonneau = true })
a.b.controls:forceClick()
local cells = table.concat(a.cells, ",")
check(cells == "flash,horn,frunk,trunk,tonneau" and a.b.tonneau.shown and a.b.tonneau.on
    and a.b.tonneau.icon == "i_tonneau" and a.b.tonneau.tipKey == "IGUI_MinidoracatTesla_Tip_AppTonneau"
    and a.b.trunk.tipKey == "IGUI_MinidoracatTesla_Tip_AppTailgate", "Cybertruck: cells " .. cells .. ", tonneau open and lit")
check(a.b.lock.tipKey == "IGUI_MinidoracatTesla_Tip_AppUnlockCybertruck"
    and a.rowSub.controls == "IGUI_MinidoracatTesla_App_ControlsSubCybertruck", "Cybertruck: lock tip and controls line name the tonneau")
a.b.tonneau:forceClick()
local tcmd, targs = sentLast()
check(tcmd == "appAction" and targs.act == "tonneau" and targs.on == false, "tonneau cell on an open cover -> appAction tonneau, on = false")
a.b.back:forceClick()
T.ClientCommands.appDone({ key = 9001, act = "trunk", on = true })
check(a.toast.text == "IGUI_MinidoracatTesla_App_Done_tailgate_on", "Cybertruck: 'tailgate opened'")
T.ClientCommands.appDone({ key = 9001, act = "tonneau", on = false })
check(a.toast.text == "IGUI_MinidoracatTesla_App_Done_tonneau_off", "Cybertruck: 'tonneau cover closed'")
state({ car = "MinidoracatTesla_Model3", skin = 5 })
a.b.controls:forceClick()
check(table.concat(a.cells, ",") == "flash,horn,frunk,trunk" and not a.b.tonneau.shown, "Model 3: no tonneau cell")
a.b.back:forceClick()
a:onMap()
check(App.mapCar and App.mapCar.spr == "car_Model3", "Model 3: the world map marker draws the Model 3 top view")
-- no server record with a model yet (paired, never seen live, or VehicleManager said no): the phone key's mirror
-- names the car, so the Model 3 still gets its picture and its lid words, not the Model Y's
local mirror = myInv.items[1].md[K.PAIRED_CARS]
mirror[1] = "MinidoracatTesla_Model3"
a = App.open(0, { keyId = 9001 })
state({ car = false })
check(a.carHint == "MinidoracatTesla_Model3" and a.model == "Model3" and a.carSpr == "car_Model3"
    and a.b.trunk.tipKey == "IGUI_MinidoracatTesla_Tip_AppTrunkLid"
    and a.carTex.path:find("app_car_model3_", 1, true) ~= nil, "no model in the record: the phone key's mirror says Model 3")
mirror[1] = "MinidoracatTesla_ModelY"
-- every car in T.Specs has what the HUD and the app draw for it: zones, top view and wordmark at both scales, a
-- picture per paint, a plug item (a third car added to Specs without them fails here, not in game)
local gaps = {}
for script, s in pairs(T.Specs) do
    local function need(ok, what) if not ok then gaps[#gaps + 1] = script .. " " .. what end end
    need(T.HUD.ZONES[s.model], "HUD.ZONES")
    for k = 1, 2 do
        for _, pre in ipairs({ "car_", "wm_", "trim_" }) do need(T.HUDAtlas[k][pre .. s.model], pre .. s.model .. "@" .. k) end
    end
    for _, c in ipairs(s.colors) do
        local f = io.open("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/textures/MinidoracatTesla/HUD/"
            .. s.appCar .. c.name .. ".png", "rb")
        need(f, s.appCar .. c.name)
        if f then f:close() end
    end
    need(s.plug and s.plug.item and s.plug.z, "plug")
end
check(#gaps == 0, "every Specs car has its zones, atlas sprites, app pictures and plug (" .. table.concat(gaps, ", ") .. ")")
App.mapCar = nil
a = App.open(0, { keyId = 9001 })
state({ car = "SomethingElse" })
check(a.carTex == nil and a.model == nil and a.paintName == nil and a.b.trunk.tipKey == "IGUI_MinidoracatTesla_Tip_AppTrunk",
    "a car that is no Tesla script: no picture, no wordmark, no other car's paint")
state()
check(a.height <= SH - 8 and a.scrollMax == 0, "1920x1009, S=1: the home page fits (" .. a.height .. " px), no scrolling")
local ok, why = textInside()
check(ok, "home: no text outside the phone (" .. why .. ")")
-- pages: list rows open them, back returns
for _, page in ipairs({ "controls", "location", "security", "charging" }) do
    a.b[page]:forceClick()
    local fine = a.page == page and a.b.back:isVisible() and not a.b.close:isVisible()
    ok, why = textInside()
    check(fine and ok and a.height <= SH - 8, page .. ": opened from its row, back shown, text inside (" .. why .. ")")
    a.b.back:forceClick()
    check(a.page == "home" and a.b.controls:isVisible(), page .. ": back -> home")
end
a.b.security:forceClick()
check(sentLast() == "appAlerts", "security page asks for the alerts again")
a.b.back:forceClick()
-- remote actions: lock (locked -> unlock), a lid asks the opposite of what is shown
a.b.lock:forceClick()
local cmd, args = sentLast()
check(cmd == "appAction" and args.act == "unlock" and args.key == 9001, "home lock icon on a locked car -> unlock")
state({ chg = "charging", kw = 11.5, target = 90, mins = 50 })
check(a.b.qcharge.enable and a.b.qcharge.on and a.rowEm.charging ~= nil, "charging: quick bolt lit, list row leads with the state")
a.b.qcharge:forceClick()
cmd, args = sentLast()
check(args.act == "charge" and args.on == false, "quick bolt while charging -> stop charging")
state()
check(not a.b.qcharge.enable and a.b.qcharge.tipKey == "IGUI_MinidoracatTesla_App_NotPlugged", "not plugged: bolt greyed, its tip says why")
state({ chg = "full", target = 90 })
check(not a.b.qcharge.enable and a.b.qcharge.tipKey == "IGUI_MinidoracatTesla_Tip_AppChargeStart", "charged full: bolt greyed, tip is its function (still plugged in)")
state()
-- joypad: rows per page, A presses, B back / close
local jd = {}
a:onGainJoypadFocus(jd)
check(a.b.lock.joypadFocused, "joypad: first control (lock) focused")
a:onJoypadDirRight()
check(a.b.qcharge.joypadFocused and not a.b.lock.joypadFocused, "joypad: right -> charge icon")
a:onJoypadDirUp()
check(a.b.cars.joypadFocused, "joypad: up -> the car name (car list)")
a:onJoypadDirRight()
check(a.b.close.joypadFocused, "joypad: right -> close")
a:onJoypadDirDown(); a:onJoypadDirDown()
check(a.b.controls.joypadFocused, "joypad: down twice -> Controls row")
a:onJoypadDown(Joypad.AButton)
check(a.page == "controls" and a.b.flash.joypadFocused, "joypad: A opens Controls, focus on Flash")
a:onJoypadDirRight(); a:onJoypadDirDown()
check(a.b.trunk.joypadFocused, "joypad: right, down -> Liftgate")
a:onJoypadDown(Joypad.AButton)
cmd, args = sentLast()
check(args.act == "trunk" and args.on == true, "joypad: A on Liftgate -> open it")
a:onJoypadDown(Joypad.BButton)
check(a.page == "home" and a.b.controls.joypadFocused, "joypad: B on a sub page -> home, focus back on its row")
state({ link = false })
a:onJoypadDirUp() -- Controls row -> the quick icon nearest its centre, then left to the end of the row
for _ = 1, 4 do a:onJoypadDirLeft() end
check(a.b.lock.joypadFocused and not a.b.lock.enable, "offline: lock focused but greyed")
local n = #H.clientSent
a:onJoypadDown(Joypad.AButton)
check(#H.clientSent == n, "joypad: A on a greyed control sends nothing")
state()
a:onJoypadDown(Joypad.BButton)
check(not a.inUI and a.key == nil, "joypad: B on home closes the app")
-- split screen: half the height, the page scrolls and the joypad focus scrolls itself into view
SW, SH = 960, 504
a = App.open(0, { keyId = 9001 })
state()
check(a.height <= SH - 8 and a.scrollMax > 0, "split screen (960x504): no taller than the screen (" .. a.height .. "), the page scrolls")
a:onGainJoypadFocus(jd)
for _ = 1, 5 do a:onJoypadDirDown() end
local row = a.b.charging
check(row.joypadFocused and row:isVisible() and a.scroll > 0 and row.y >= a.yBody and row.y + row.height <= a.yBodyEnd,
    "split screen: down to Charging scrolls it into view (scroll " .. a.scroll .. ")")
ok, why = textInside()
check(ok, "split screen: text inside the phone (" .. why .. ")")
a:onMouseWheel(-100)
check(a.scroll == 0 and a.b.lock:isVisible() and not a.b.charging:isVisible(),
    "mouse wheel up: back to the top; the Charging row below the fold is hidden (no clicks over the toast)")
-- Security page with 10 alerts on the half screen: an alerts reply draws at once, joypad down past Sentry Mode
-- scrolls the list, a control only half inside the visible part takes no clicks
check(not a.b.security:isVisible(), "the Security row half below the fold takes no clicks until scrolled in")
a:onMouseWheel(5)
a.b.security:forceClick()
local list, realParkUI = {}, T.ParkUI
for i = 1, 10 do list[i] = { i = i } end
T.ParkUI = { card = function(e) return { title = "alert " .. e.i, detail = "detail", time = "14:0" .. (e.i % 10) } end }
T.ClientCommands.appAlerts({ key = 9001, list = list })
ok, why = pcall(function() a:prerender(); a:render() end)
check(ok and #a.alerts == 10, "alerts arriving between updates: drawn at once (" .. tostring(why) .. ")")
check(a.scrollMax > 0 and a.b.sentry.joypadFocused, "split screen, 10 alerts: the Security page scrolls; joypad on Sentry Mode")
a:onJoypadDirDown(); a:onJoypadDirDown()
check(a.b.sentry.joypadFocused and a.scroll > 0, "joypad down past Sentry Mode scrolls the alerts (" .. a.scroll .. ")")
a:onJoypadDirUp()
check(a.b.back.joypadFocused, "joypad up from the list: back")
a:onJoypadDirDown()
check(a.b.sentry.joypadFocused and a.scroll == 0 and a.b.sentry:isVisible(), "joypad down again: Sentry Mode scrolled back in view")
a:onMouseWheel(1)
local partial = false
for _, b in ipairs(a.buttons) do
    if b:isVisible() and b.cy >= a.yBody and (b.y < a.yBody or b.y + b.height > a.yBodyEnd) then partial = true end
end
check(a.scroll > 0 and not a.b.sentry:isVisible() and not partial, "scrolled: a control not wholly in view takes no clicks")
ok, why = textInside()
check(ok, "Security page with 10 alerts: text inside the phone (" .. why .. ")")
T.ParkUI = realParkUI
a:onJoypadDown(Joypad.BButton)
a:onJoypadDirDown(); a:onJoypadDirDown(); a:onJoypadDirDown() -- Security row -> Charging, the last one
a:showToast(string.rep("word ", 40), false)
a:layout()
ok, why = textInside()
check(ok and a.yToast and a.yToast + 2 * 19 <= a.height, "a long toast: two lines at the bottom, inside (" .. why .. ")")
check(a.b.charging.joypadFocused and a.b.charging:isVisible(), "the toast shortens the page: the focused Charging row scrolls back in view")
-- "Show on map" from the Location page: the app steps aside, closing the map brings it back on Location
a.b.location:forceClick()
a.b.map:forceClick()
check(not a.inUI and App.mapCar ~= nil, "map: the app closes, the marker is set")
ISWorldMap.close({})
check(a.inUI and a.page == "location" and App.mapCar == nil, "map closed: the app back on the Location page, marker gone")
-- ---------------------------------------------------------------- the car list (one phone key, several cars)
H.section("phone app: car list")
SW, SH = 1920, 1009
a:setPage("home")
state()
local function rowsShown()
    local n = 0
    while a.b["pick" .. (n + 1)] and a.b["pick" .. (n + 1)].shown do n = n + 1 end
    return n
end
local sent0 = #H.clientSent
a.b.cars:forceClick()
cmd, args = sentLast()
check(a.page == "cars" and cmd == "appStatusAll" and #args.keys == 1 and args.keys[1] == 9002,
    "car name -> the list; one batch for the other paired car (the selected one is polled anyway)")
check(rowsShown() == 2 and a.b.pick1.cur and not a.b.pick2.cur and a.b.pick2.sSub == "IGUI_MinidoracatTesla_App_Loading",
    "two rows in pairing order, the current car marked, the other loading")
T.ClientCommands.appStates({ list = { { key = 9002, link = nil, grid = true, car = "MinidoracatTesla_ModelY", x = 1200,
    y = 1990, pct = 41, km = 300, skin = 1, h = H.hours() - 2 } } })
check(a:read() and a:layout() == nil, "batch answer: the open list redraws")
local line2 = a:carLine(a.b.pick2.pick) -- (the drawn row is cut to fit: getText returns the long keys here)
check(line2:find("41%", 1, true) == 1 and line2:find("LastSeen", 1, true) and App.carLabel(9002):find("Pearl White", 1, true),
    "batch answer: the other car's line (41% · last seen) and paint")
check(#H.clientSent == sent0 + 1, "the list asked once (no batch per redraw)")
ok, why = textInside()
check(ok, "car list: text inside the phone (" .. why .. ")")
-- joypad: D-pad picks, A selects, B closes the list
a:onGainJoypadFocus(jd)
check(a.b.pick1.joypadFocused, "joypad on the list: the current car focused")
a:onJoypadDirDown()
check(a.b.pick2.joypadFocused, "joypad: down -> the next car")
a:onJoypadDown(Joypad.AButton)
cmd, args = sentLast()
check(a.page == "home" and a.key == 9002 and a.paintName == "PearlWhite" and cmd == "appAlerts" and args.key == 9002,
    "A: switched to the other car (its paint at once from the last view), its alerts asked")
H.advanceMs(App.POLL_MS + 1)
a:update()
cmd, args = sentLast()
check(cmd == "appStatus" and args.key == 9002, "only the selected car is polled")
a:setPage("cars")
a:onJoypadDown(Joypad.BButton)
check(a.page == "home" and a.key == 9002, "B on the list: back home, same car")
-- a refusal in the batch keeps its reason (no place), the row says why instead of loading forever (review 2026-10-27)
T.ClientCommands.appStates({ list = { { key = 9002, deny = "NOT_OWNER" } } })
check(App.seen[9002].deny == "NOT_OWNER" and App.seen[9002].x == nil and a:carLine({ key = 9002 }) == T.denyText("NOT_OWNER"),
    "refused in the batch: the row shows why, no place kept")
state()
-- more paired cars than the server answers per request: the list asks in chunks of App.BATCH, one a LIST_MS
local savedPhones = myInv
local many = {}
for i = 1, 18 do many[i] = 7000 + i end
myInv = container(multiPhone(many))
App.open(0, { keyId = 7018 })
H.advanceMs(App.LIST_MS)
local sentM = #H.clientSent
local function listReqs(asked)
    local reqs = 0
    for i = sentM + 1, #H.clientSent do
        local s = H.clientSent[i]
        if s.command == "appStatusAll" then
            reqs = reqs + 1
            check(#s.args.keys <= R.MAX_BATCH, "chunk " .. reqs .. ": at most the server's MAX_BATCH")
            for _, k in ipairs(s.args.keys) do asked[k] = true end
        end
    end
    return reqs
end
local asked = {}
a.b.cars:forceClick()
a:update()
a.b.back:forceClick()
a.b.cars:forceClick() -- opened again within the second: no second round on top
check(listReqs({}) == 1, "18 cars: the first 16 at once, the rest not in the same second (reopening adds none)")
myInv = container(myInv.items[1], multiPhone({ 8001, 8002 })) -- a second phone picked up while the round goes out
a.b.back:forceClick()
a.b.cars:forceClick()
check(listReqs({}) == 1, "a second phone mid-round: still nothing more this second")
H.advanceMs(App.LIST_MS)
a:update()
H.advanceMs(App.LIST_MS)
a:update()
local all17 = true
local reqs = listReqs(asked)
for i = 1, 17 do if not asked[7000 + i] then all17 = false end end
check(reqs == 2 and all17 and asked[8001] and asked[8002] and App.BATCH == R.MAX_BATCH,
    "a second later the update sends the rest, the new phone's cars with it: two requests cover all 19 others")
myInv = container(multiPhone(many))
a:setPage("cars") -- a new round of 17, held back: the last request went out this same second
sentM = #H.clientSent
H.advanceMs(-60000) -- the player's wall clock jumps back a minute
a:update()
check(listReqs({}) == 1, "client clock set back mid-round: the round goes on, not stuck until the clock catches up")
H.advanceMs(60000)
-- 50 paired cars (4 requests a round), the list opened and closed twice a second for 10 s: through the server's
-- dispatch (Commands.lua CommandRate) every request gets through, at most one a second
for i = 19, 50 do many[i] = 7000 + i end
myInv = container(multiPhone(many))
App.open(0, { keyId = 7050 })
me.getOnlineID, me.getUsername = function() return 9101 end, function() return "me" end
H.advanceMs(App.LIST_MS)
local fromL, times, gotL, dropL = #H.clientSent, {}, 0, T.CommandRate.dropped.appStatusAll or 0
for tick = 0, 99 do
    H.side(true, false)
    if tick % 5 == 0 then (a.page == "cars" and a.b.back or a.b.cars):forceClick() end
    a:update()
    for i = fromL + 1, #H.clientSent do
        if H.clientSent[i].command == "appStatusAll" then times[#times + 1] = tick * 100 end
    end
    local got
    got, fromL = H.serve(fromL)
    gotL = gotL + (got.appStatusAll or 0)
    H.advanceMs(100)
end
check(#times == 10 and gotL == 10 and H.busiest(times, 10000) * 1.5 <= T.CommandRate.LIMITS.appStatusAll.max
    and (T.CommandRate.dropped.appStatusAll or 0) == dropL,
    "50 cars, list opened 10 times in 10 s: " .. #times .. " requests (one a second), all reach the server's handler")
local eighteen = {}
for i = 1, 18 do eighteen[i] = 7000 + i end
myInv = container(multiPhone(eighteen))
App.open(0, { keyId = 7018 })
a:setPage("cars")
H.advanceMs(App.LIST_MS) -- (the next list opens below send at once)
-- the list's joypad rows are this app's own (split screen: another app's list keeps its length)
local other = setmetatable({ page = "cars", navCars = { { "back" }, { "pick1" } } }, { __index = App })
check(#a:navRows() == 19 and #other:navRows() == 2, "car list joypad rows per app, not shared")
myInv = savedPhones
App.open(0, { keyId = 9002 })
T.ClientCommands.appStates({ list = { { key = 9002, link = nil, grid = true, car = "MinidoracatTesla_ModelY", x = 1200,
    y = 1990, pct = 41, km = 300, skin = 1, h = H.hours() - 2 } } }) -- back to its last view before the refusal
state()
-- VehicleManager's cars (MinidoracatTesla.VMLink): a paired one merges into its row, an unpaired one gets its own
T.VMLink = { cars = function() return {
    { oid = "o-1", keyId = 9001, script = "Base.MinidoracatTesla_ModelY", x = 1000, y = 2000, ageMs = 1000 },
    { oid = "o-2", keyId = 5555, script = "Base.MinidoracatTesla_ModelY", x = 1003, y = 1990, ageMs = 300000 } } end }
a:setPage("cars")
check(rowsShown() == 3 and a.b.pick3.pick.oid == "o-2" and a.b.pick1.pick.oid == "o-1"
    and a:carLine(a.b.pick3.pick):find("App_VmTag", 1, true) and a:carLine(a.b.pick3.pick):find("DirDist", 1, true)
    and a:carLine(a.b.pick3.pick):find("MinsAgo", 1, true), "VehicleManager: paired car merged, the unpaired one listed (tag, place, age)")
a.b.pick3:forceClick()
check(a.key == nil and a.oid == "o-2" and a.vmOnly and a.hasPos and a.sSub2 == "IGUI_MinidoracatTesla_App_NotPaired",
    "unpaired VehicleManager car selected: its last position, why the buttons are dim")
check(a.b.lock.enable and not a.b.lock.lit and a.b.lock.hint, "remote buttons dim but pressable")
local n0 = #H.clientSent
a.b.lock:forceClick()
check(#H.clientSent == n0 and a.toast and a.toast.text == "IGUI_MinidoracatTesla_App_JoinHint",
    "pressing one sends nothing, says how to add the car")
H.advanceMs(App.POLL_MS + 1)
a:update()
check(#H.clientSent == n0, "an unpaired car is never polled from the server")
a.b.location:forceClick()
check(a.b.map.shown and a.b.map.enable and not a.b.navcar.shown, "location: map yes; navigate hidden without the MiniMap")
-- Navigate to car: only with MiniMap navApiVersion >= 12 (setNavTarget)
local navArgs
MinidoracatMiniMapAPI = { navApiVersion = 11, setNavTarget = function(...) navArgs = { ... }; return true, "ok" end }
a:setPage("location")
check(not a.b.navcar.shown, "MiniMap navApiVersion 11: no navigate button")
MinidoracatMiniMapAPI.navApiVersion = 12
a:setPage("location")
check(a.b.navcar.shown and a.b.navcar.enable, "MiniMap navApiVersion 12: navigate button")
ok, why = textInside()
check(ok, "location with both buttons: text inside (" .. why .. ")")
a.b.navcar:forceClick()
check(navArgs and navArgs[1] == 0 and navArgs[2] == 1003.5 and navArgs[3] == 1990.5 and navArgs[4] == a.sName
    and a.toast.text == "IGUI_MinidoracatTesla_App_NavSet", "navigate: setNavTarget(player, the car's square centre, name), toast")
MinidoracatMiniMapAPI.setNavTarget = function() return true, "prompted" end
a.b.navcar:forceClick()
check(a.toast.text == "IGUI_MinidoracatTesla_App_NavPrompted", "MiniMap asks first (prompted): told to confirm there")
MinidoracatMiniMapAPI.setNavTarget = function() return false, "nearby" end
a.b.navcar:forceClick()
check(a.toast.text == "IGUI_MinidoracatTesla_App_NavNearby" and not a.toast.ok, "nearby: says so")
MinidoracatMiniMapAPI.setNavTarget = function() return false, "busy" end
a.b.navcar:forceClick()
check(a.toast.text == "IGUI_MinidoracatTesla_App_NavFailed", "other refusals: can't set now")
MinidoracatMiniMapAPI = nil
-- opening on a given car (VehicleManager's menu: opts.keyId / opts.oid)
check(App.open(0, { oid = "o-1" }).key == 9001, "open { oid }: the paired car it maps to")
check(App.open(0, { keyId = 5555 }).oid == "o-2", "open { keyId } of an unpaired VehicleManager car: that car")
check(App.open(0, 9001) ~= nil and a.key == 9001, "open with a non-table: the first car, no error")
local savedInv = myInv
myInv = container()
check(App.open(0, { keyId = 9001 }) == nil, "no phone key on the player: the app does not open")
myInv = savedInv
App.open(0, { keyId = 9001 })
state()
a:setPage("home")

-- ---------------------------------------------------------------- dragging the phone (moveWithMouse, its file)
H.section("phone app: drag")
check(not a.pos and a.x == SW - a.width - 40, "never dragged: the right half of the screen")
a:onMouseDown(5, 5)
a.x, a.y = 300, 200 -- ISPanelJoypad:onMouseMove while the button is held
a:layout() -- a poll's layout mid-drag
check(a.x == 300 and a.y == 200, "a layout during the drag does not snap the phone back")
a:onMouseUp(5, 5)
check(files["MinidoracatTesla_phone0.txt"] == "300 200" and a.x == 300 and a.y == 200 and not a.moving,
    "dropped: it stays there, the spot written to this player's file")
files["MinidoracatTesla_phone0.txt"] = nil
a:onMouseDown(5, 5)
a:onMouseUp(5, 5)
check(files["MinidoracatTesla_phone0.txt"] == nil and a.x == 300, "a click on the background is not a drag: nothing written")
a:setPage("security")
check(a.x == 300 and a.y == math.min(200, SH - a.height - 4), "another page: same spot (moved up only if it would not fit)")
a:setPage("home")
a:onMouseDown(5, 5)
a.x, a.y = 1900, -30
a:onMouseUpOutside(5, 5) -- let go off the game window
check(a.x == SW - a.width - 4 and a.y == 4 and files["MinidoracatTesla_phone0.txt"] == "1900 -30",
    "dropped half off the screen: pulled back inside (the drop is kept as it was)")
a.pos = { x = 300, y = 200 }
a:onMouseDown(5, 5)
a:close() -- closed mid-drag: no mouse-up will come
App.open(0, { keyId = 9001 })
check(not a.moving and a.x == 300, "closed mid-drag: reopened at its spot, not stuck moving")
files["MinidoracatTesla_phone1.txt"] = "120 80"
local b2 = App.open(1, { keyId = 9001 })
check(b2 ~= a and b2.pos and b2.x == 120 and b2.y == 80, "another split-screen player: their own file, read when their app is made")
b2:close()
a.pos = nil
a:layout()

-- ---------------------------------------------------------------- a busy minute against the server's budget
-- The real app for a minute (update every 100 ms: its 2 s polls) under a player clicking twice a second without a
-- break: a tour (car list and picks, security page and Sentry, controls, quick buttons, closing and reopening), then
-- 10 s each of mashing the horn, flipping between the cars (each pick: appAlerts and a poll at once) and in and out of
-- the security page, then the tour again. Every request goes through the server's dispatch (Commands.lua
-- CommandRate): none may be dropped, and each command's busiest 10 s keeps half its budget again to spare.
H.section("phone app: a busy minute within the server's budget")
local CR = T.CommandRate
me.getOnlineID, me.getUsername = function() return 9100 end, function() return "me" end
local tour = { "cars", "pick2", "cars", "pick1", "security", "sentry", "back", "controls", "flash", "horn", "frunk",
    "trunk", "back", "lock", "qtrunk", "qfrunk", "cars", "pick2", "close", "open" }
local script = {}
local function add(ids, n) for i = 1, n do script[#script + 1] = ids[(i - 1) % #ids + 1] end end
add(tour, 20)
add({ "controls" }, 1); add({ "horn" }, 19)
add({ "back" }, 1); add({ "cars", "pick2", "cars", "pick1" }, 19)
add({ "pick1" }, 1); add({ "security", "back" }, 18); add({ "open" }, 1)
add(tour, 40)
local dropped0, from, sentN, gotN, clicks, missed = {}, #H.clientSent, {}, {}, 0, {}
for k, n in pairs(CR.dropped) do dropped0[k] = n end
local perWin, times = {}, {} -- command -> send times (ms), to report the busiest 10 s
for tick = 0, 599 do
    H.side(true, false)
    if tick % 5 == 0 then -- a click every 0.5 s
        clicks = clicks + 1
        local id = script[clicks]
        if id == "open" then App.open(0, { keyId = 9001 })
        elseif a.b[id] and a.b[id].shown and a.b[id].enable then a.b[id]:forceClick()
        else missed[#missed + 1] = id .. "@" .. a.page end
    end
    a:update()
    for i = from + 1, #H.clientSent do
        local c = H.clientSent[i].command
        sentN[c] = (sentN[c] or 0) + 1
        times[c] = times[c] or {}
        times[c][#times[c] + 1] = tick * 100
    end
    local got
    got, from = H.serve(from)
    for c, n in pairs(got) do gotN[c] = (gotN[c] or 0) + n end
    H.advanceMs(100)
end
local same, line = true, {}
for c, n in pairs(sentN) do
    if gotN[c] ~= n then same = false end
    local busiest = H.busiest(times[c], 10000)
    perWin[c] = busiest
    line[#line + 1] = c .. " " .. n .. " (busiest 10 s " .. busiest .. ")"
end
table.sort(line)
local none = true
for k, n in pairs(CR.dropped) do if n ~= (dropped0[k] or 0) then none = false end end
check(#missed == 0, "the click script followed the pages (" .. (#missed == 0 and clicks .. " clicks" or table.concat(missed, ", ")) .. ")")
check(same and none and (sentN.appStatus or 0) >= 30 and (sentN.appAlerts or 0) >= 10 and (sentN.appAction or 0) >= 30
    and (sentN.appStatusAll or 0) >= 6, "every request reached its handler: " .. table.concat(line, ", "))
for c, n in pairs(perWin) do
    local lim = CR.LIMITS[c] or CR.LIMITS.default
    check(n * 1.5 <= lim.max, c .. ": busiest 10 s (" .. n .. ") has half its budget again to spare (" .. lim.max .. ")")
end

-- ---------------------------------------------------------------- summon pages (a fake client MinidoracatAutoDriveAPI)
H.section("phone app: summon (client)")
local P = "IGUI_MinidoracatTesla_App_"
local VID = v:getId() -- v is loaded (getVehicleById), 10 tiles south of the player
local function sread() a.sumNext = 0; a:read(); a:layout() end
local halos, realHalo = {}, HaloTextHelper -- an app closed when its summon ends: the words over the player's head
HaloTextHelper = { addGoodText = function(_, t) halos[#halos + 1] = t end, addBadText = function(_, t) halos[#halos + 1] = t end }
a:setPage("home")
state({ vid = VID })
check(not a.b.summon.shown and #a:navRows() == 7, "no AutoDrive summon API: no Summon row")
local CL = { summonApiVersion = 1, reach = 64, can = { come = { true }, dumb = { true }, target = { true } }, asked = {} }
function CL.canSummon(pn, car, opts)
    CL.asked[#CL.asked + 1] = { car = car, mode = opts.mode, x = opts.x, y = opts.y, dir = opts.dir }
    local r = CL.can[opts.mode]
    return r[1], r[2]
end
function CL.summonState() return CL.st end
function CL.summonReach() return CL.reach end
function CL.summonReasonText(code) return "R_" .. code end
MinidoracatAutoDriveAPI = CL
state({ vid = VID })
sread()
local bs = a.b
check(bs.summon.shown and bs.summon.cy > bs.location.cy and bs.summon.cy < bs.security.cy,
    "with the API: the Summon row between Location and Security")
check(a.rowSub.summon:find(P .. "SummonReady", 1, true) == 1, "Summon row: within range (and how far the car is)")
ok, why = textInside()
check(ok and a.height <= SH - 8, "home with the Summon row: text inside, fits (" .. a.height .. " px)")
a:onGainJoypadFocus(jd)
a:focusFirst("location")
a:onJoypadDirDown()
check(bs.summon.joypadFocused, "joypad: Location row, down -> Summon row")
a:onJoypadDown(Joypad.AButton)
sread()
check(a.page == "summon" and bs.come.shown and bs.come.enable and bs.pick.shown and bs.fwd.enable and bs.rev.enable
    and bs.come.joypadFocused, "A: the summon page, come / pick / forward / back usable, focus on Come to me")
local sawCar, sawDumb = false, false
for _, q in ipairs(CL.asked) do
    if q.car == v and q.mode == "come" then sawCar = true end
    if q.mode == "dumb" then sawDumb = true end
end
check(sawCar and sawDumb, "canSummon asked with the car this game has loaded, for come and for dumb")
check(a.sSumState == P .. "SummonCarAt" and a.sSumSub == P .. "SummonRange" and a.radCarX ~= nil
    and a.radCarY > a.radCY, "ready: where the car is, the range, the car's dot south of the player")
ok, why = textInside()
check(ok, "summon page: text inside (" .. why .. ")")
-- come: starting -> driving -> stop pressed -> CANCELLED
bs.come:forceClick()
cmd, args = sentLast()
check(cmd == "appAction" and args.act == "summon" and args.on == true and args.mode == "come" and args.key == 9001,
    "Come to me -> appAction summon on, mode come")
sread()
check(a.sumPhase == "starting" and bs.come.shown and bs.come.style == "stop" and not bs.fwd.shown and not bs.pick.shown,
    "starting: one button, Come to me now Stop")
T.ClientCommands.appDone({ key = 9001, act = "summon", on = true })
check(a.toast.text == P .. "Done_summon_on" and a.sumPhase == "starting", "server ok: toast, still starting")
CL.st = { vid = VID, phase = "driving", dist = 12, mode = "come" }
sread()
check(a.sumPhase == "driving" and a.sSumState == P .. "SummonComing" and a.rowEm.summon == a.sSumState,
    "AutoDrive driving: the car is coming (the home row says so too)")
bs.come:forceClick()
cmd, args = sentLast()
check(args.act == "summon" and args.on == false and a.sum.stopAsked, "Stop -> appAction summon off")
T.ClientCommands.appDone({ key = 9001, act = "summon", why = "NO_LINK" })
check(a.sumPhase == "driving" or a.sum.phase == "driving", "the stop refused (NO_LINK): still driving")
T.ClientCommands.appDone({ key = 9001, act = "summonEnd", why = "ARRIVED" })
sread()
check(a.sumPhase == "arrived" and a.toast.text == "R_ARRIVED" and a.toast.ok and bs.finish.shown and not bs.come.shown,
    "summonEnd ARRIVED: arrived, AutoDrive's words, Done")
CL.st = { vid = VID, phase = "ended", code = "ARRIVED", dist = 4 }
bs.finish:forceClick()
sread()
check(a.sum == nil and a.sumPhase == "ready" and bs.come.shown, "Done: ready again (an old ended state does not end anything)")
-- refused at the start, then try again; a stop code
bs.rev:forceClick()
cmd, args = sentLast()
check(args.mode == "dumb" and args.dir == -1 and args.x == nil, "Back -> dumb, dir -1")
sread()
check(bs.rev.style == "stop" and not bs.come.shown, "back running: its button is the Stop")
T.ClientCommands.appDone({ key = 9001, act = "summon", why = "TOWED" })
sread()
check(a.sumPhase == "stopped" and a.sSumState == P .. "SummonRefused" and a.sSumNote == "IGUI_MinidoracatTesla_Deny_TOWED"
    and bs.again.shown and bs.finish.shown, "refused (TOWED): why in full, Try again / Done")
bs.again:forceClick()
cmd, args = sentLast()
check(args.mode == "dumb" and args.dir == -1 and a.sumPhase ~= nil, "Try again: the same summon (dumb back)")
CL.st = { vid = VID, phase = "driving", dist = 5, mode = "dumb" }
sread()
CL.st = { vid = VID, phase = "ended", code = "ZOMBIES", dist = 5 }
sread()
check(a.sumPhase == "stopped" and a.sum.code == "ZOMBIES" and a.sSumState == P .. "SummonStopped",
    "AutoDrive ended (ZOMBIES) before the server's word: stopped with its code")
T.ClientCommands.appDone({ key = 9001, act = "summonEnd", why = "CANCELLED" })
sread()
check(a.sum == nil and a.sumPhase == "ready", "summonEnd CANCELLED: back to ready")
CL.st = nil
-- greyed with AutoDrive's reason
CL.can.come = { false, "UI_MinidoracatAutoDrive_NeedModule" }
sread()
check(not bs.come.enable and not bs.pick.enable and bs.fwd.enable and a.sSumNote == "UI_MinidoracatAutoDrive_NeedModule",
    "canSummon come refused: come / pick grey, forward still usable, the reason under the buttons")
local n1 = #H.clientSent
bs.come:forceClick()
check(#H.clientSent == n1, "a grey Come to me sends nothing")
ok, why = textInside()
check(ok, "greyed summon page: text inside (" .. why .. ")")
CL.can.come = { true }
state({ vid = VID, summon = { phase = "driving", mode = "come", mine = false } })
sread()
check(not bs.come.enable and not bs.fwd.enable and a.sSumNote == "UI_MinidoracatAutoDrive_SummonBusy",
    "someone else's summon of this car: everything grey, says so")
state({ vid = VID, summon = { phase = "driving", mode = "target", mine = true } })
sread()
check(a.sumPhase == "starting" and a.sum.mode == "target" and bs.pick.style == "stop",
    "my summon running when the app opens: shown as running, its button the Stop")
a.sum = nil
state({ vid = VID })
sread()
-- reopened: the client's copy of a state with a summon is not trusted; an ended summon goes back to ready
state({ vid = VID, summon = { phase = "driving", mode = "dumb", mine = true } })
sread()
check(a.sumPhase == "starting" and a.sum.dir == -1 and not a.sum.adopted and bs.rev.style == "stop",
    "running when the app opens: its dir from this game's last request (Back), that button the Stop")
a:close()
T.ClientCommands.appDone({ key = 9001, act = "summonEnd", why = "ARRIVED" }) -- the app is closed: over the head
check(halos[#halos] == "R_ARRIVED", "summonEnd with the app closed: AutoDrive's words over the player's head")
App.open(0, { keyId = 9001 })
a:setPage("summon")
sread()
check(a.sumPhase == "ready" and a.sum == nil, "reopened after it ended unheard: ready (the cached state's summon ignored)")
state({ vid = VID })
sread()
check(a.sumPhase == "ready", "...and the server's state without a summon keeps it so")
App.sumReq[9001] = nil
state({ vid = VID, summon = { phase = "driving", mode = "dumb", mine = true } })
CL.st = { vid = VID, phase = "driving", dist = 6, mode = "dumb" }
sread()
check(a.sum.adopted and a.sSumState == P .. "Driving", "running, no request of ours for it: no guessed direction")
T.ClientCommands.appDone({ key = 9001, act = "summonEnd", why = "BLOCKED" })
sread()
check(a.sumPhase == "stopped" and not bs.again.shown and bs.finish.shown and bs.finish.style == "main",
    "it stopped: no Try again (its dir unknown), Done")
bs.finish:forceClick()
CL.st = nil
state({ vid = VID, summon = { phase = "driving", mode = "come", mine = true } })
sread()
state({ vid = VID }) -- the summon ended and its summonEnd was lost: the next state says no summon
sread()
check(a.sumPhase == "ready", "running, then a server state without it: ended unheard, ready")
-- this app's own summon: the server took it (appDone on), then a state without it: ended unheard, ready
bs.come:forceClick()
T.ClientCommands.appDone({ key = 9001, act = "summon", on = true })
state({ vid = VID, summon = { phase = "starting", mode = "come", mine = true } })
sread()
check(a.sumPhase == "starting", "own summon: running while the server's states show it")
state({ vid = VID })
sread()
check(a.sumPhase == "ready" and a.sum == nil, "own summon, then a state without it: ready")
-- the stop refused because the server lost the car (NOT_LOADED): not stuck on a summon nobody runs
bs.come:forceClick()
T.ClientCommands.appDone({ key = 9001, act = "summon", on = true })
state({ vid = VID, summon = { phase = "starting", mode = "come", mine = true } })
sread()
bs.come:forceClick()
T.ClientCommands.appDone({ key = 9001, act = "summon", why = "NOT_LOADED" })
sread()
check(a.sumPhase == "stopped" and a.sSumNote == "IGUI_MinidoracatTesla_Deny_NOT_LOADED" and bs.finish.shown,
    "the stop refused NOT_LOADED: stopped with the reason, Done")
bs.finish:forceClick()
state({ vid = VID })
sread()
-- reopened with no link (grid down, the car past Bluetooth): AutoDrive's own summonState still gives the Stop
App.sumReq[9001] = { mode = "target", x = 1012.5, y = 1990.5 }
a:close()
App.open(0, { keyId = 9001 })
a:setPage("summon")
state({ link = false })
CL.st = { vid = VID, phase = "driving", dist = 40, mode = "target" }
sread()
check(a.sum and a.sum.mode == "target" and a.sum.x == 1012.5 and a.sumPhase == "driving" and bs.pick.style == "stop",
    "no link, AutoDrive says this player's summon of this car drives: shown running, its Stop")
bs.pick:forceClick()
cmd, args = sentLast()
check(cmd == "appAction" and args.act == "summon" and args.on == false, "...and the Stop goes to the server")
T.ClientCommands.appDone({ key = 9001, act = "summon", on = false })
sread() -- AutoDrive's state still says driving for a moment
check(a.sumPhase == "ready" and a.sum == nil, "stopped: ready (AutoDrive's lagging 'driving' does not bring it back)")
-- no link, the summon arrives: where it stopped is the car's live place until Done (the record is from the last link)
a:close()
App.open(0, { keyId = 9001 })
a:setPage("summon")
App.sumReq[9001] = { mode = "target", x = 1012.5, y = 1990.5 }
state({ link = false })
CL.st = { vid = VID, phase = "driving", dist = 40, mode = "target" }
sread()
T.ClientCommands.appDone({ key = 9001, act = "summonEnd", why = "ARRIVED" })
CL.st = { vid = VID, phase = "ended", code = "ARRIVED", mode = "target" }
sread()
check(a.sumPhase == "arrived" and a.sumCarX == v:getX(), "no link, arrived: the car's live place, not the last record")
bs.finish:forceClick()
sread()
-- AutoDrive keeps its last result all session: an ended one gives no live place (the share taken back: no position)
CL.st = { vid = VID, phase = "ended", code = "ARRIVED", mode = "target" }
a:close()
App.open(0, { keyId = 9001 })
a:setPage("summon")
state({ link = false, deny = "NOT_AUTHORIZED", x = false, y = false, pct = false })
sread()
check(a.sum == nil and a.sumPhase == "ready" and a.sumCarX == nil, "no link, AutoDrive's summon over: no live place of the car")
-- no link, this player summons another car (another key): not this one's
v.keyId = 9002
CL.st = { vid = VID, phase = "driving", dist = 9, mode = "come" }
a:close()
App.open(0, { keyId = 9001 })
a:setPage("summon")
state({ link = false })
sread()
check(a.sum == nil and a.sumPhase == "ready", "no link, AutoDrive drives a car with another key: not taken for this one")
v.keyId, CL.st = 9001, nil
-- reopened, and a refusal comes before any state: shown, no Try again
a:close()
App.open(0, { keyId = 9001 })
a:setPage("summon")
T.ClientCommands.appDone({ key = 9001, act = "summon", why = "NO_LINK" })
state({ link = false })
sread()
check(a.sumPhase == "stopped" and not bs.again.shown and bs.finish.shown, "a refusal this app knew nothing of: Done only")
bs.finish:forceClick()
-- a refused start with AutoDrive's old result for this car still there: no live place (the start never ran)
a:close()
App.open(0, { keyId = 9001 })
a:setPage("summon")
state({ link = false, deny = "NOT_AUTHORIZED", x = false, y = false, pct = false })
CL.st = { vid = VID, phase = "ended", code = "ARRIVED", mode = "come" }
T.ClientCommands.appDone({ key = 9001, act = "summon", why = "NOT_AUTHORIZED" })
sread()
check(a.sumPhase == "stopped" and a.sumCarX == nil, "a refused start, AutoDrive's old result: no live place of the car")
bs.finish:forceClick()
CL.st = nil
-- reopened, and the end comes before any state: shown, but no Try again (nothing known of it)
a:close()
App.open(0, { keyId = 9001 })
a:setPage("summon")
T.ClientCommands.appDone({ key = 9001, act = "summonEnd", why = "BLOCKED" })
state({ vid = VID })
sread()
check(a.sumPhase == "stopped" and not bs.again.shown and bs.finish.shown, "an end this app knew nothing of: Done only")
bs.finish:forceClick()
-- reopened on the cached state (link, vid) while this player summons another car that now has that vid (ids reused)
a:close()
v.keyId = 9002
CL.st = { vid = VID, phase = "driving", dist = 9, mode = "come" }
App.open(0, { keyId = 9001 })
a:setPage("summon")
sread()
check(a.sum == nil and a.sumPhase == "ready", "AutoDrive's summon of another car with the cached vid: not taken for this one")
v.keyId, CL.st = 9001, nil
state({ vid = 98765 }) -- the server has the car, this game has not loaded it
sread()
check(not bs.come.enable and not bs.fwd.enable and a.sSumNote == "UI_MinidoracatAutoDrive_SummonTooFar",
    "car not loaded in this game: too far (not 'within range'), all grey")
state({ vid = VID })
sread()
a:onGainJoypadFocus(jd)
a:focusFirst("come")
bs.come:forceClick()
sread()
check(bs.come.joypadFocused and bs.come.style == "stop", "joypad on the running summon's Stop")
T.ClientCommands.appDone({ key = 9001, act = "summonEnd", why = "ARRIVED" })
sread()
check(bs.finish.joypadFocused, "it arrived, its Stop gone: the joypad moves to Done")
bs.finish:forceClick()
sread()
-- the first time this game opens the app (a new app, nothing seen yet) with AutoDrive already there
local seenKeep = App.seen
App.seen = {}
local okOpen, a2 = pcall(App.open, 1, { keyId = 9001 })
check(okOpen and a2 and a2.inUI and a2.sumApi, "first open with the summon API installed: opens (" .. tostring(a2) .. ")")
if okOpen and a2 then a2:close() end
App.seen = seenKeep
-- pick a spot
bs.pick:forceClick()
sread()
local map = bs.spot
check(a.page == "pick" and map and map.shown and map:isVisible() and mapCalls.data == 1 and mapCalls.style == 1
    and mapCalls.HideUnvisited == true and mapCalls.Isometric == false,
    "Pick a spot: the map (vanilla data and style, only what the player has seen, top-down)")
check(map.joypadFocused and not bs.go.enable and a.sPickNote == P .. "SummonPickHint", "no pin yet: Go here grey, the hint")
map:prerender()
check(map.mapAPI.cx == 1000 and map.mapAPI.cy == 1990 and mapCalls.zoom > 17 and mapCalls.zoom < 19,
    "the map on the player, zoomed to the range (" .. tostring(mapCalls.zoom) .. ")")
map:onMouseUp(map.width / 2 + 20, map.height / 2 - 30) -- 10 tiles east, 15 north
sread()
local lastPin = CL.asked[#CL.asked]
check(a.pin.x == 1010.5 and a.pin.y == 1975.5 and lastPin.mode == "target" and lastPin.x == 1010.5 and bs.go.enable
    and a.sPickNote == P .. "SummonSpotAt", "a click drops the pin on that square; canSummon asked for it; Go here usable")
local okDraw = pcall(function() a:prerender(); a:render(); map:render() end)
check(okDraw, "pick page draws (map overlay too)")
ok, why = textInside()
check(ok, "pick page: text inside (" .. why .. ")")
CL.can.target = { false, "UI_MinidoracatAutoDrive_SummonTooFar" }
sread()
check(not bs.go.enable and a.sPickNote == "UI_MinidoracatAutoDrive_SummonTooFar", "pin out of range: Go here grey, why")
CL.can.target = { true }
-- grid down: the ring and the spot no further than Bluetooth (Keys.btRange); AutoDrive's own reach (64) is above it
SandboxVars.MinidoracatTesla.BluetoothRange = 12
state({ vid = VID, grid = false, link = "bt" })
sread()
check(a.sumR == 12 and not bs.go.enable and a.sPickNote == "UI_MinidoracatAutoDrive_SummonTooFar",
    "grid down, Bluetooth 12: the ring 12, the pin 18 tiles away out of reach (" .. tostring(a.sumR) .. ")")
SandboxVars.MinidoracatTesla.BluetoothRange = nil
sread()
check(a.sumR == 50 and bs.go.enable, "grid down, Bluetooth unset: the ring 50, the pin inside it")
state({ vid = VID })
sread()
check(a.sumR == 64 and bs.go.enable, "grid up: the ring is AutoDrive's reach (64)")
a:onJoypadDirRight()
sread()
check(a.pin.x == 1012.5 and map.joypadFocused, "joypad on the map: right moves the pin 2 tiles")
a:onJoypadDown(Joypad.AButton)
check(bs.go.joypadFocused, "A on the map: on to Go here")
a:onJoypadDown(Joypad.AButton)
cmd, args = sentLast()
check(args.act == "summon" and args.mode == "target" and args.x == 1012.5 and args.y == 1975.5 and a.page == "summon",
    "Go here -> appAction target with the pin, back on the summon page")
sread()
check(a.sumPhase == "starting" and bs.pick.style == "stop" and a.radPinX ~= nil, "target running: Pick a spot is the Stop, the pin on the radar")
T.ClientCommands.appDone({ key = 9001, act = "summonEnd", why = "CANCELLED" })
sread()
bs.pick:forceClick()
a:onJoypadDown(Joypad.BButton)
check(a.page == "summon", "B on the pick page: back to the summon page")
a:onJoypadDown(Joypad.BButton)
check(a.page == "home" and bs.summon.joypadFocused, "B on the summon page: home, on the Summon row")
a:setPage("summon")
ISWorldMap.IsAllowed = function() return false end
sread()
check(not bs.pick.shown and bs.come.shown, "world map off on the server: no Pick a spot")
ISWorldMap.IsAllowed = function() return true end
sread()
-- a summonEnd with the app closed: over the player's head
recording = false
collectgarbage("collect"); collectgarbage("stop")
a:prerender(); a:render()
local kb0 = collectgarbage("count")
for _ = 1, 200 do a:prerender(); a:render() end
local grew0 = collectgarbage("count") - kb0
collectgarbage("restart")
recording = true
check(grew0 < 1, "summon page: 200 redraws allocate nothing (" .. string.format("%.2f", grew0) .. " KB)")
MinidoracatAutoDriveAPI = nil
a.sum, a.pin = nil, nil
a:setPage("home")
state()
check(not a.b.summon.shown, "API gone: the Summon row gone")
HaloTextHelper = realHalo
a:onLoseJoypadFocus(jd) -- the redraw check below measures the page without a focused control's help text
a:setPage("location")

-- ---------------------------------------------------------------- MiniMap markers (MiniMapBridge.lua)
H.section("phone app: MiniMap markers")
local provider
MinidoracatMiniMapAPI = { markerApiVersion = 3, registerMarkerProvider = function(owner, fn) provider = { owner, fn } end }
require "MinidoracatTesla/MiniMapBridge"
local B = T.MiniMapBridge
check(not B.registered and provider == nil, "not registered before OnGameStart")
B.register()
check(B.registered and provider[1] == T.MOD_ID, "OnGameStart with the MiniMap: provider registered")
local mk = provider[2](0, "mini")
local ids = {}
for _, m in ipairs(mk.markers) do ids[m.id] = m end
check(ids["tesla:9001"] and ids["tesla:9002"] and not ids["tesla:5555"] and ids["tesla:9001"].state == "live"
    and ids["tesla:9001"].badge and ids["tesla:9001"].x == 1000.5, "markers: the app's cars, live, with the badge")
check(provider[2](0, "world") == mk and provider[2](1, "mini") == nil, "same table every frame; split-screen guests none")
local rev = mk.revision
state() -- the 2 s poll: same place
check(provider[2](0, "mini") == mk, "a poll that changes nothing: same table")
MinidoracatVehicleManager = { MiniMapBridge = { registered = true } }
H.advanceMs(B.CHECK_MS + 1)
mk = provider[2](0, "mini")
ids = {}
for _, m in ipairs(mk.markers) do ids[m.id] = m end
check(mk.revision == rev + 1 and not ids["tesla:9001"] and ids["tesla:9002"], "a car VehicleManager's bridge draws: not twice")
MinidoracatVehicleManager = nil
H.advanceMs(App.FRESH_MS + 1)
mk = provider[2](0, "mini")
local faded = true
for _, m in ipairs(mk.markers) do if m.state == "live" then faded = false end end
check(#mk.markers == 2 and faded, "10 minutes without a look: faded")
state()
mk = provider[2](0, "mini")
ids = {}
for _, m in ipairs(mk.markers) do ids[m.id] = m end
check(ids["tesla:9001"].state == "live" and ids["tesla:9002"].state ~= "live", "a fresh look: that car live again")
-- a car no longer on the phone (removed, or the phone handed over): its marker goes, though App.seen still has it
local keptInv = myInv
myInv = container(phoneKey(9001))
App.seenRev = App.seenRev + 1 -- (KeysUI's phoneUnpaired does this)
mk = provider[2](0, "mini")
ids = {}
for _, m in ipairs(mk.markers) do ids[m.id] = m end
check(ids["tesla:9001"] and not ids["tesla:9002"] and App.seen[9002] ~= nil, "removed from the phone: no marker for it")
-- the phone for 9001 handed over, one for 9002 picked up: as many markers, other cars (no seenRev move: the 10 s check)
myInv = container(phoneKey(9002))
H.advanceMs(B.CHECK_MS + 1)
mk = provider[2](0, "mini")
ids = {}
for _, m in ipairs(mk.markers) do ids[m.id] = m end
check(ids["tesla:9002"] and not ids["tesla:9001"] and B.drawsWorld(0, 9002) == false,
    "a phone swapped for another one: its cars' markers, not the old ones (same count)")
myInv = keptInv
App.seenRev = App.seenRev + 1
provider[2](0, "mini")
App.mapCar = { x = 1, y = 1, pn = 0, key = 9001 }
local realDraw, draws = App.drawMapCar, 0
App.drawMapCar = function() draws = draws + 1 end -- (the real one needs the world map's mapAPI)
provider[2](0, "world") -- the MiniMap draws our markers on the world map this frame
ISWorldMap:render()
check(draws == 0, "with the MiniMap's world map marker: the app's temporary marker is not drawn too")
H.advanceMs(2000) -- its world map layers off (WMLayers): it stops asking for "world"
ISWorldMap:render()
check(draws == 1, "MiniMap world layers off: the app's temporary marker again")
App.mapCar.pn = 1
provider[2](0, "world")
ISWorldMap:render()
check(draws == 2, "split-screen player 1 (no MiniMap markers for it): the temporary marker")
App.drawMapCar, App.mapCar = realDraw, nil
B.registered = false
MinidoracatMiniMapAPI, T.VMLink = nil, nil

-- redraw allocates nothing
recording = false
collectgarbage("collect"); collectgarbage("stop")
a:prerender(); a:render()
local kb = collectgarbage("count")
for _ = 1, 200 do a:prerender(); a:render() end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
check(grew < 1, "200 redraws allocate nothing (" .. string.format("%.2f", grew) .. " KB)")
a:close()
getSpecificPlayer = realSpecific
H.side(false, true)

-- ------------------------------------------------------------------ restore (later tests use their own fakes)
Events.OnSpawnVehicleEnd.Remove(R.onLoad)
T.Remote = nil
getWorld, playServerSound = savedWorld, savedSound
for k, n in pairs(statsBefore) do S.stats[k] = n end
F.done()
