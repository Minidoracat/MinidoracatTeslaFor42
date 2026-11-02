-- Power liftgate and door-anim sync (shared/MinidoracatTesla/Liftgate.lua): server rules, unlock-then-toggle,
-- sync, client anim. Real animation, sound and the second client are E2E hud-sp / liftgate-mp.
local check = H.check
local T = MinidoracatTesla
local SRC = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/shared/MinidoracatTesla/Liftgate.lua"

-- SP load: both the server and the client handler register (the module branches on isClient/isServer at load)
-- globals other tests set up (park_fakes.lua): put them back at the end
local saved = { getOnlinePlayers = getOnlinePlayers, ISOpenVehicleDoor = ISOpenVehicleDoor,
    ISCloseVehicleDoor = ISCloseVehicleDoor, ISInstallVehiclePart = ISInstallVehiclePart, HaloTextHelper = HaloTextHelper,
    getPlayer = getPlayer }
H.side(false, false)
-- vanilla door actions: start() plays the anim, complete() opens/closes and returns true (ISOpenVehicleDoor.lua:26-97);
-- SP wraps both; vanilla install: complete() fits the item (ISInstallVehiclePart.lua:93-95)
ISOpenVehicleDoor = { start = function(self) self.vehicle:playPartAnim(self.part, "Open") end,
    complete = function(self) self.part:getDoor():setOpen(true); return true end }
ISCloseVehicleDoor = { start = function(self) self.vehicle:playPartAnim(self.part, "Close") end,
    complete = function(self) self.part:getDoor():setOpen(false); return true end }
ISInstallVehiclePart = { complete = function(self) self.part.item = self.item; return true end }
H.stub("Vehicles/TimedActions/ISOpenVehicleDoor")
H.stub("Vehicles/TimedActions/ISCloseVehicleDoor")
H.stub("Vehicles/TimedActions/ISInstallVehiclePart")
dofile(SRC)
local L = T.Liftgate
local halo = {}
HaloTextHelper = { addBadText = function(_, text) halo[#halo + 1] = text end }
function getPlayer() return nil end

local function car(o)
    local v = H.vehicle(o)
    v.anims, v.doorTx, v.order = {}, 0, {}
    local models = { getModelCount = function() return 1 end }
    for _, id in ipairs({ "TrunkDoor", "DoorFrontLeft", "DoorRearLeft", "EngineDoor" }) do
        local door = { open = false, locked = id == "TrunkDoor", broken = false }
        function door:isOpen() return self.open end
        function door:setOpen(b) self.open = b end
        function door:isLocked() return self.locked end
        function door:setLocked(b) self.locked = b end
        function door:isLockBroken() return self.broken end
        v.parts[id] = { id = id, door = door, item = {}, getId = function(self) return self.id end,
            getDoor = function(self) return self.door end, getInventoryItem = function(self) return self.item end,
            getVehicle = function() return v end, getScriptPart = function() return models end }
        v.order[#v.order + 1] = v.parts[id]
    end
    -- the cabin glass part: no item, one model; setModelVisible logged ("Glass+" shown, "Glass-" hidden)
    v.glass = {}
    v.parts.CabinGlass = { id = "CabinGlass", getId = function(self) return self.id end, getInventoryItem = function() end,
        getScriptPart = function() return models end,
        setModelVisible = function(_, m, on) v.glass[#v.glass + 1] = m .. (on and "+" or "-") end }
    v.order[#v.order + 1] = v.parts.CabinGlass
    function v:getPartCount() return #self.order end
    function v:getPartByIndex(i) return self.order[i + 1] end
    function v:toggleLockedDoor(part, chr, locked) -- BaseVehicle.java:1230-1244 (seated player may unlock)
        if not locked and not part.door.broken and part.door.locked then part.door.locked = false end
    end
    function v:transmitPartDoor() self.doorTx = self.doorTx + 1 end
    v.cabinLocked = false -- areAllDoorsLocked: the cabin doors only (BaseVehicle.java:9332-9335)
    function v:areAllDoorsLocked() return self.cabinLocked end
    function v:playPartAnim(part, anim) self.anims[#self.anims + 1] = part.id .. ":" .. anim end
    function v:playPartSound(part, p, anim) self.sound = anim end
    return v
end

local v = car({})
local driver = H.player({})
driver.vehicle, v.driver = v, driver
local cmd = T.ServerCommands.liftgate
local function denied(reason)
    local last = H.sent[#H.sent]
    return last and last.command == "deny" and last.args.reason == reason
end

H.section("liftgate: server rules")
-- the shell bits follow the door's clip clock: 1/60 x 0.8 x the unmodded multiplier a tick (Liftgate.syncShell): set as
-- the opening swing starts, cleared as the closing one ends (L.FLIP; the glass draws last, models.md 8)
local function tick(n) for _ = 1, n do H.fire("OnTick") end end
local function settle() H.setMultiplier(40); tick(70); H.setMultiplier(1) end -- every swing over (3.6 clip s at 40x)
local ticks = H.count("OnTick")
check(L.FLIP.open == 0 and L.FLIP.close == 1, "a bit flips as the opening swing starts and as the closing one ends")
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
local d = v.parts.TrunkDoor.door
check(d.open and not d.locked and v.doorTx == 1, "driver, parked, locked: unlocked, opened, door synced")
check(v.anims[1] == "TrunkDoor:Open" and v.sound == "Open", "SP: client handler played the Open anim and its sound")
check(math.floor(v:getColorHue()) == 16 and H.near(v:getColorHue() - 16, 0.69, 1e-6) and not v.colorTx
    and H.count("OnTick") == ticks,
    "opened: tailgate bit 16 at once (its window from the tailgate as it swings), paint hue kept, no transmitColorHSV, no OnTick")
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(not d.open and v.anims[2] == "TrunkDoor:Close", "second press closes")
-- Model Y doorClip TrunkDoor 3.6 clip s: 270 ticks at 1x
tick(269)
check(math.floor(v:getColorHue()) == 16, "closed: the bit stays while the tailgate swings shut (269 ticks)")
tick(1)
check(H.near(v:getColorHue(), 0.69, 1e-6) and H.count("OnTick") == ticks, "...cleared at 270 ticks (3.6 clip s), OnTick removed")
check(not d.locked, "car unlocked: the closed liftgate stays unlocked")
v.cabinLocked = true -- locked car: the liftgate locks again when it shuts
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(not d.open and d.locked, "locked car: liftgate shut from the dashboard -> locked again")
settle()
check(H.near(v:getColorHue(), 0.69, 1e-6) and H.count("OnTick") == ticks, "...its swing over: bit clear, nothing pending")
local lidE = v.parts.EngineDoor.door
cmd(driver, { vid = v:getId(), part = "EngineDoor" })
cmd(driver, { vid = v:getId(), part = "EngineDoor" })
check(not lidE.open and lidE.locked, "frunk lid shut on a locked car: locked again, like the liftgate (the car locks as a whole)")
check(H.near(v:getColorHue(), 0.69, 1e-6), "...the frunk lid has no shell bit")
d.locked, d.broken = false, true
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(not d.locked, "broken lock: shut but not locked (it could never open again)")
d.broken, v.cabinLocked = false, false
settle()
local sp = car({})
local fl0 = sp.parts.DoorFrontLeft
local function act() return { vehicle = sp, part = fl0, character = driver } end
local function open(o) (o and ISOpenVehicleDoor or ISCloseVehicleDoor).complete(act(o)) end
local function bit() return math.floor(sp:getColorHue()) end
open(true)
check(bit() == 1 and #sp.anims == 0 and H.count("OnTick") == ticks,
    "SP door action complete: shell bit 1 for DoorFrontLeft at once, no anim broadcast, no OnTick")
open(false)
tick(59)
check(bit() == 1, "SP door closed: the bit stays 59 ticks in (0.8 clip s door: 60 ticks at 1x)")
open(true)
check(bit() == 1 and H.count("OnTick") == ticks, "...opened again inside the closing swing: set, the pending clear dropped")
open(false)
tick(59)
check(bit() == 1, "...closed again: still set at 59 ticks")
tick(1)
check(bit() == 0 and H.count("OnTick") == ticks, "...cleared at 60 ticks, OnTick removed")
-- the opener's start (SP runs the client wrap too): the bit with the anim, before complete
ISOpenVehicleDoor.start(act(true))
check(sp.anims[#sp.anims] == "DoorFrontLeft:Open" and bit() == 1, "SP Open start: the anim and the bit in the same call")
open(true)
ISCloseVehicleDoor.start(act(false))
check(sp.anims[#sp.anims] == "DoorFrontLeft:Close" and bit() == 1 and H.count("OnTick") == ticks + 1,
    "SP Close start: the anim, the bit kept for the swing, one OnTick")
tick(30)
open(false) -- complete half a swing later (a slow action): the start's clock stands
tick(29)
check(bit() == 1, "...complete keeps the start's clear: still set 59 ticks after the start")
tick(1)
check(bit() == 0 and H.count("OnTick") == ticks, "...cleared 60 ticks after the start")
for _, m in ipairs({ { 5, 12 }, { 20, 3 }, { 40, 2 } }) do -- multiplier, ticks to close
    H.setMultiplier(m[1])
    open(true)
    local opened = bit()
    open(false)
    tick(m[2] - 1)
    local late = bit()
    tick(1)
    check(opened == 1 and late == 1 and bit() == 0,
        "game speed x" .. m[1] .. ": the bit set at the opening, cleared " .. m[2] .. " ticks into the closing")
end
H.setMultiplier(1)
open(true)
open(false)
tick(30) -- 0.4 of the 0.8 clip s
H.setMultiplier(0) -- paused: the door stands still, so does the shell
tick(100)
check(bit() == 1, "paused mid-swing: the bit holds")
H.setMultiplier(5) -- 0.4 clip s left at 0.0667 a tick: 6 ticks
tick(5)
check(bit() == 1, "speed changed mid-swing (1x, pause, 5x): still set 5 ticks after")
tick(1)
check(bit() == 0, "...cleared on the 6th, as the clip got there")
H.setMultiplier(1)
open(true)
open(false)
tick(5)
H.removeVehicle(sp) -- unloaded mid-swing; its id goes to another make (the engine reuses ids)
local gas0 = car({ id = sp:getId(), script = "Base.CarNormal" })
settle()
check(H.near(gas0:getColorHue(), 0.69, 1e-6) and H.count("OnTick") == ticks,
    "a pending swing whose id is now another make's: dropped, that car's hue untouched, OnTick removed")
-- a load: Liftgate's own OnSpawnVehicleEnd handler (the other mods' handlers need a fuller car)
local function loaded() L.onLoad(sp) end
H.addVehicle(sp) -- back (fl0 shut, bit still 1: unloaded inside the swing)
loaded()
check(bit() == 0 and H.count("OnTick") == ticks, "loaded with the door shut but its bit set: cleared at once, no OnTick")
fl0.door.open = true -- saved open with no bit (an older save)
loaded()
check(bit() == 1 and H.count("OnTick") == ticks, "loaded with a door open: its bit at once")
open(false)
tick(3)
loaded() -- reloaded mid-swing (closed just before): the doors stand, the pending clear goes with it
check(bit() == 0 and H.count("OnTick") == ticks, "reloaded mid-swing: set to the door at once, the pending clear dropped")
open(false)
settle() -- the liftgate's opens and closes above

local passenger = H.player({ name = "bob" })
passenger.vehicle = v
local online = { driver, passenger }
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
H.side(false, true) -- MP server: deny goes out as a server command
local tx0 = v.doorTx
cmd(passenger, { vid = v:getId(), part = "TrunkDoor" })
check(denied("NOT_DRIVER") and not d.open and v.doorTx == tx0, "passenger: NOT_DRIVER, nothing changed")
v.speed = 12
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(denied("MOVING") and not d.open and v.doorTx == tx0, "driving: MOVING, nothing changed")
v.speed = 0.4
d.locked, d.broken = true, true
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(denied("LOCK_BROKEN") and d.locked and not d.open and v.doorTx == tx0, "broken lock: LOCK_BROKEN, still locked and shut")
d.broken = false
v.parts.TrunkDoor.item = nil
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(denied("NO_DOOR") and not d.open, "liftgate part uninstalled: NO_DOOR")
v.parts.TrunkDoor.item = {}
local n = #H.sent
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
local s1, s2, a, b = H.sent[n + 1], H.sent[n + 2], H.sent[n + 3], H.sent[n + 4]
check(d.open and #H.sent == n + 4 and s1.player == driver and s2.player == passenger and s1.command == "shell"
    and s2.command == "shell" and s1.args.vid == v:getId() and s1.args.hue == v:getColorHue()
    and math.floor(s1.args.hue) == 16 and not v.colorTx,
    "MP: opened, the shell hue (16 + paint) at once to every player near as a command, no transmitColorHSV (VehicleProperties)")
check(a.player == driver and b.player == passenger and a.command == "partAnim"
    and a.args.part == "TrunkDoor" and a.args.open == true and a.args.sound == true,
    "...then partAnim { TrunkDoor, open, sound } to every player near")
settle()
check(#H.sent == n + 4, "...nothing more once the swing is over")

H.section("liftgate: only the players who can have the car loaded (Liftgate.NEAR_TILES)")
-- the server sends a car to a connection within relevantRange * 8 tiles on both axes, at most 96
-- (UdpConnection.java:224-226, GameServer.java:2808-2809): a square, not a circle. The engine's number, not the MOD's.
local REACH = 96
check(L.NEAR_TILES == REACH, "NEAR_TILES is the engine's farthest vehicle relevance (96 tiles)")
local far = H.player({ name = "far", x = v.x + REACH + 0.5, y = v.y })
local corner = H.player({ name = "corner", x = v.x - REACH, y = v.y + REACH })
online = { driver, passenger, far, corner }
local function got(p, from, command)
    local c = 0
    for i = from + 1, #H.sent do
        if H.sent[i].player == p and (command == nil or H.sent[i].command == command) then c = c + 1 end
    end
    return c
end
n = #H.sent
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(not d.open and got(far, n) == 0, "dashboard close: nothing to a player 96.5 tiles away on one axis")
check(got(corner, n, "shell") == 0 and got(corner, n, "partAnim") == 1 and got(driver, n) == 1 and got(passenger, n) == 1,
    "...partAnim once each to the driver, the passenger and a player 96 tiles away on both axes; the shell bit waits")
settle()
check(got(corner, n, "shell") == 1 and got(driver, n, "shell") == 1 and got(passenger, n, "shell") == 1 and got(far, n) == 0,
    "...the swing over: the cleared shell hue once each, none far")
n = #H.sent
ISOpenVehicleDoor.complete({ vehicle = v, part = v.parts.DoorFrontLeft, character = passenger })
check(got(far, n) == 0 and got(corner, n, "partAnim") == 1 and got(driver, n, "partAnim") == 1 and got(passenger, n, "partAnim") == 0,
    "vanilla door action: anim to the players near but the opener, none far")
ISCloseVehicleDoor.complete({ vehicle = v, part = v.parts.DoorFrontLeft, character = passenger })
settle()
far.x = v.x + 10 -- walked up: the car (doors, hue) comes with the engine's full update; later changes reach it
n = #H.sent
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
settle()
check(d.open and got(far, n, "shell") == 1 and got(far, n, "partAnim") == 1, "the far player walked up: the next open reaches it")

H.section("liftgate: once per client connection (split-screen)")
-- sendServerCommand(player, ...) goes to the player's connection (GameServer.java:3562-3569) and the client fires
-- OnServerCommand once per packet, no player in it (GameClient.java:1055-1071): two players of one client near the car
-- must not get two partAnim (the anim restarts, the sound plays twice). Online id = slot * 4 + split-screen index.
local guest = H.player({ name = "guest", num = 1, x = v.x + 3, y = v.y })
guest.oid = driver.oid + 1
local away = H.player({ name = "away", x = v.x + REACH + 50, y = v.y })
local awayGuest = H.player({ name = "awayGuest", num = 1, x = v.x + 5, y = v.y })
awayGuest.oid = away.oid + 1
online = { driver, guest, passenger, away, awayGuest }
local function conn(p, from, command) -- commands sent to p's connection
    local c = 0
    for i = from + 1, #H.sent do
        local s = H.sent[i]
        if s.player and s.command == command and math.floor(s.player:getOnlineID() / 4) == math.floor(p:getOnlineID() / 4) then
            c = c + 1
        end
    end
    return c
end
n = #H.sent
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
settle()
check(not d.open and conn(driver, n, "shell") == 1 and conn(driver, n, "partAnim") == 1 and conn(passenger, n, "partAnim") == 1,
    "the driver and its split-screen guest share one client: one shell, one partAnim to it")
check(conn(away, n, "shell") == 1 and conn(away, n, "partAnim") == 1, "...a client with only its guest near: one each")
n = #H.sent
ISOpenVehicleDoor.complete({ vehicle = v, part = v.parts.DoorFrontLeft, character = guest })
check(conn(driver, n, "partAnim") == 0 and conn(passenger, n, "partAnim") == 1 and conn(away, n, "partAnim") == 1,
    "vanilla door opened by the guest: no anim back to its own client (it played it in :start), one to every other")
ISCloseVehicleDoor.complete({ vehicle = v, part = v.parts.DoorFrontLeft, character = guest })
settle()
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(d.open, "liftgate open again for the next section")
settle()
online = { driver, passenger }

H.section("dashboard doors: any door part (HUD car picture)")
local rl, lid = v.parts.DoorRearLeft.door, v.parts.EngineDoor.door
rl.locked = true
n = #H.sent
cmd(driver, { vid = v:getId(), part = "DoorRearLeft" })
a = H.sent[#H.sent]
check(rl.open and not rl.locked and a.command == "partAnim" and a.args.part == "DoorRearLeft" and a.args.sound == true,
    "locked rear left door: unlocked, opened, partAnim { DoorRearLeft, sound }")
check(math.floor(v:getColorHue()) == 16 + 4 and H.sent[n + 1].command == "shell",
    "shell bits at once, sent before the anim: liftgate (16) + rear left door (4)")
settle()
cmd(driver, { vid = v:getId(), part = "EngineDoor" })
check(lid.open and H.sent[#H.sent].args.part == "EngineDoor", "frunk lid: lifted, partAnim EngineDoor")
local tx = v.doorTx
for _, bad in ipairs({ "GasTank", "WindowFrontLeft", 7, false }) do
    cmd(driver, { vid = v:getId(), part = bad })
    check(denied("NO_DOOR") and v.doorTx == tx, "part id " .. tostring(bad) .. ": NO_DOOR, nothing changed")
end
cmd(driver, { vid = v:getId() })
check(denied("NO_DOOR") and v.doorTx == tx, "no part id: NO_DOOR")
cmd(passenger, { vid = v:getId(), part = "EngineDoor" })
check(denied("NOT_DRIVER") and lid.open and v.doorTx == tx, "passenger, frunk lid: NOT_DRIVER, nothing changed")
v.speed = 12
cmd(driver, { vid = v:getId(), part = "DoorRearLeft" })
check(denied("MOVING") and rl.open and v.doorTx == tx, "driving, rear door: MOVING, stays open")
v.speed = 0
cmd(driver, { vid = v:getId(), part = "EngineDoor" })
cmd(driver, { vid = v:getId(), part = "DoorRearLeft" })
settle()
check(not lid.open and not rl.open and math.floor(v:getColorHue()) == 16, "second clicks close the lid and the door")

H.section("door anim sync (MP server)")
-- vanilla door actions: complete() opens/closes and returns true (ISOpenVehicleDoor.lua:61-97)
ISOpenVehicleDoor = { complete = function(self) self.part:getDoor():setOpen(true); return true end }
ISCloseVehicleDoor = { complete = function(self) self.part:getDoor():setOpen(false); return true end }
ISInstallVehiclePart = { complete = function(self) self.part.item = self.item; return true end }
H.stub("Vehicles/TimedActions/ISOpenVehicleDoor")
H.stub("Vehicles/TimedActions/ISCloseVehicleDoor")
dofile(SRC) -- MP server load: wraps the two actions
local fl = v.parts.DoorFrontLeft
n = #H.sent
check(ISOpenVehicleDoor.complete({ vehicle = v, part = fl, character = driver }) == true, "wrapped complete keeps the vanilla result")
local sh = H.sent[n + 1]
b = H.sent[n + 3]
check(#H.sent == n + 3 and sh.command == "shell" and math.floor(sh.args.hue) == 17 and H.sent[n + 2].command == "shell"
    and b.player == passenger and b.args.part == "DoorFrontLeft" and b.args.open == true and not b.args.sound,
    "door opened by the driver: the shell hue to everyone at once, the anim to the others only (the opener played it in :start)")
settle()
check(#H.sent == n + 3, "...nothing more once the swing is over")
n = #H.sent
ISCloseVehicleDoor.complete({ vehicle = v, part = fl, character = passenger })
check(#H.sent == n + 1 and H.sent[n + 1].player == driver and H.sent[n + 1].args.open == false,
    "closed by the passenger: anim to the driver at once")
settle()
check(#H.sent == n + 3 and H.sent[n + 2].command == "shell" and math.floor(H.sent[n + 2].args.hue) == 16,
    "...the shell bit cleared to everyone once the swing is over")
local tg = v.parts.TrunkDoor
tg.door.open, tg.door.locked, v.cabinLocked = true, false, true -- opened on a locked car (the app, the dashboard)
local tx2 = v.doorTx
ISCloseVehicleDoor.complete({ vehicle = v, part = tg, character = passenger })
check(tg.door.locked and v.doorTx == tx2 + 1, "locked car: liftgate shut by hand (vanilla close) -> locked again and synced")
settle()
v.cabinLocked = false
-- review round 2 (R2-3), by hand: Model X, the car locked, the app opened both wings (unlocked); the liftgate opened and
-- shut by hand stays unlocked (cabin not all locked), the wings shut by hand lock; the last one locks the lids too
do
    local x = car({ script = "Base.MinidoracatTesla_ModelX" })
    for _, id in ipairs({ "DoorFrontRight", "DoorRearRight" }) do
        local d0 = x.parts.DoorFrontLeft
        local door = setmetatable({ open = false, locked = false, broken = false }, { __index = d0.door })
        x.parts[id] = setmetatable({ id = id, door = door, item = {} }, { __index = d0 })
    end
    local CABIN = { "DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight" }
    function x:areAllDoorsLocked()
        for _, id in ipairs(CABIN) do if not self.parts[id].door.locked then return false end end
        return true
    end
    for _, id in ipairs(CABIN) do x.parts[id].door.locked = true end
    local wl, wr, gate = x.parts.DoorRearLeft.door, x.parts.DoorRearRight.door, x.parts.TrunkDoor.door
    wl.open, wl.locked, wr.open, wr.locked = true, false, true, false -- the app opened both wings
    gate.open, gate.locked = true, false
    ISCloseVehicleDoor.complete({ vehicle = x, part = x.parts.TrunkDoor, character = passenger })
    check(not gate.open and not gate.locked, "by hand: liftgate shut while the wings stand unlocked: not locked yet")
    ISCloseVehicleDoor.complete({ vehicle = x, part = x.parts.DoorRearLeft, character = passenger })
    check(wl.locked and not gate.locked, "by hand: the left wing shut locks, the right still open: liftgate waits")
    ISCloseVehicleDoor.complete({ vehicle = x, part = x.parts.DoorRearRight, character = passenger })
    check(wr.locked and gate.locked and x.parts.EngineDoor.door.locked,
        "by hand: wings open -> liftgate open, shut -> wings shut: wings and liftgate locked")
end
local gas = car({ script = "Base.CarNormal" })
n = #H.sent
ISOpenVehicleDoor.complete({ vehicle = gas, part = gas.parts.DoorFrontLeft, character = driver })
check(#H.sent == n, "not a Tesla: nothing sent")
-- a shell door's bit clears when its Close clip is over: Specs doorClip (else 0.8) must be the clip the build animates
-- (scripts/blender/skf/cars/<car>.py DOORS, 4th value)
for name, s in pairs(T.Specs) do
    local f = io.open("scripts/blender/skf/cars/" .. s.model:gsub("^Model", "model_"):lower() .. ".py", "r")
    local src = f and f:read("*a") or ""
    if f then f:close() end
    for _, id in ipairs(L.SHELL_DOORS) do
        local clip = tonumber((src:match('"' .. id .. '":%s*(%b())') or ""):match(",%s*([%d.]+)%)$")) -- the falcon axis is a string
        local want = s.doorClip and s.doorClip[id] or 0.8
        check(clip ~= nil and want == clip, name .. " " .. id .. ": clip " .. tostring(want) .. " = its build's " .. tostring(clip))
    end
end

H.section("cabin glass: drawn after every other part model (MP server)")
local LG = T.Liftgate -- the MP server load's module (its install wrap and repair handler)
T.Init.CabinGlass(v, v.parts.CabinGlass)
check(v.glass[#v.glass] == "Glass+", "init (every load, once each part has its item): the glass model shown")
v.glass, n, fl.item = {}, #H.sent, nil
check(ISInstallVehiclePart.complete({ vehicle = v, part = fl, item = {} }) == true, "wrapped install keeps the vanilla result")
local gl = H.sent[n + 1]
check(table.concat(v.glass, ",") == "Glass-,Glass+" and #H.sent == n + 2 and gl.command == "glassLast"
    and gl.args.vid == v:getId() and #gl.args.parts == 1 and gl.args.parts[1] == "DoorFrontLeft",
    "door fitted: the glass hidden and shown again (to the end of the model list), glassLast { the door } to every player near")
v.glass, n = {}, #H.sent
ISInstallVehiclePart.complete({ vehicle = v, part = fl, item = nil })
check(#v.glass == 0 and #H.sent == n, "install that left no item (failed): nothing")
fl.item = {}
local bare = { id = "Battery", getId = function(self) return self.id end, getInventoryItem = function() return {} end,
    getVehicle = function() return v end, getScriptPart = function() return { getModelCount = function() return 0 end } end }
ISInstallVehiclePart.complete({ vehicle = v, part = bare, item = {} })
local gasFl = gas.parts.DoorFrontLeft
ISInstallVehiclePart.complete({ vehicle = gas, part = gasFl, item = {} })
check(#v.glass == 0 and #gas.glass == 0 and #H.sent == n, "a part with no model, another make's door: nothing")
LG.onVehicleCommand("vehicle", "repair", driver, { vehicle = v:getId() })
check(#v.glass == 0 and #H.sent == n, "vanilla repair command from a player without the mechanics cheat: nothing")
driver._admin = true
LG.onVehicleCommand("vehicle", "repair", driver, { vehicle = v:getId() })
gl = H.sent[n + 1]
check(table.concat(v.glass, ",") == "Glass-,Glass+" and gl.command == "glassLast" and #gl.args.parts == 4,
    "admin repair: glass to the end, glassLast with every fitted part that has a model (4: not CabinGlass)")
v.glass, n = {}, #H.sent
LG.onVehicleCommand("vehicle", "remove", driver, { vehicle = v:getId() })
LG.onVehicleCommand("vehicle", "repairPart", driver, { vehicle = gas:getId() })
check(#v.glass == 0 and #H.sent == n, "another vehicle command, another make's repair: nothing")
driver._admin = nil

H.section("liftgate: client")
H.side(true, false)
v.speed = 30
H.clientSent = {}
check(L.toggle(driver, v, "TrunkDoor") == false and #H.clientSent == 0 and halo[#halo] == "IGUI_MinidoracatTesla_Deny_MOVING",
    "car picture while driving: refused on the client with a halo, nothing sent")
v.speed = 0
check(L.toggle(driver, v, "TrunkDoor") and H.clientSent[1].command == "liftgate" and H.clientSent[1].args.part == "TrunkDoor",
    "car picture tail, parked: liftgate { part = TrunkDoor } sent")
check(L.toggle(driver, v, "EngineDoor") and H.clientSent[2].args.part == "EngineDoor", "car picture: frunk lid sent")
check(L.toggle(driver, v, "Muffler") == false and #H.clientSent == 2 and halo[#halo] == "IGUI_MinidoracatTesla_Deny_NO_DOOR",
    "not a dashboard door: refused on the client, nothing sent")
check(L.toggle(passenger, v, "DoorFrontLeft") == false and #H.clientSent == 2, "passenger: refused on the client")
local na = #v.anims
T.ClientCommands.partAnim({ vid = 424242, part = "TrunkDoor", open = true })
T.ClientCommands.partAnim({ vid = v:getId(), part = 7, open = true })
check(#v.anims == na, "client without the car, or a bad part id: ignored")
local hb = v:getColorHue()
T.ClientCommands.shell({ vid = v:getId(), hue = 1.69 })
check(H.near(v:getColorHue(), 1.69, 1e-6), "client: shell sets the server's hue on the loaded car")
T.ClientCommands.shell({ vid = 424242, hue = 3 })
check(H.near(v:getColorHue(), 1.69, 1e-6), "client: shell for a car not loaded is ignored")
v:setColorHSV(hb, v:getColorSaturation(), v:getColorValue())
-- partAnim plays a swing here: its door's bit in the same frame (Liftgate.localSwing), cleared as the closing clip ends
H.side(false, true)
settle() -- the server's swings above (Model X wings) over first
H.side(true, false)
local cv = car({})
local function cbit() return math.floor(cv:getColorHue()) end
T.ClientCommands.partAnim({ vid = cv:getId(), part = "DoorFrontLeft", open = true })
check(cbit() == 1 and H.count("OnTick") == ticks, "client partAnim Open: the door's bit at once (the server's hue on its way)")
T.ClientCommands.partAnim({ vid = cv:getId(), part = "DoorFrontLeft", open = false })
tick(30)
T.ClientCommands.shell({ vid = cv:getId(), hue = cv:getColorHue() - 1 }) -- the server's clear, ahead of this swing
check(cbit() == 1, "...the server's hue clearing it mid-swing: this client's bit stays (its swing still plays)")
tick(29)
check(cbit() == 1, "...Close: still set 59 ticks into the swing")
tick(1)
check(cbit() == 0 and H.count("OnTick") == ticks, "...cleared as the 0.8 clip s end, OnTick removed")
T.ClientCommands.partAnim({ vid = cv:getId(), part = "EngineDoor", open = true })
check(cbit() == 0 and H.count("OnTick") == ticks, "frunk lid: no shell bit")
-- glassLast from the server: once the fitted part's item is here (a vehicle update, maybe after the command)
cv.parts.DoorRearLeft.item = nil
T.ClientCommands.glassLast({ vid = cv:getId(), parts = { "DoorRearLeft" } })
tick(3)
check(#cv.glass == 0 and H.count("OnTick") == ticks + 1, "client glassLast before the part's item came: waits, one OnTick")
cv.parts.DoorRearLeft.item = {}
tick(1)
check(table.concat(cv.glass, ",") == "Glass-,Glass+" and H.count("OnTick") == ticks,
    "...the item here: glass to the end of the model list, OnTick removed")
cv.glass, cv.parts.DoorRearLeft.item = {}, nil
T.ClientCommands.glassLast({ vid = cv:getId(), parts = { "DoorRearLeft" } })
H.advanceMs(10001)
tick(1)
check(table.concat(cv.glass, ",") == "Glass-,Glass+" and H.count("OnTick") == ticks,
    "...an item that never comes: given up after 10 s, the glass to the end anyway")
cv.glass, cv.parts.DoorRearLeft.item = {}, {}
T.ClientCommands.glassLast({ vid = 424242, parts = { "DoorRearLeft" } })
tick(1)
T.ClientCommands.glassLast({ vid = cv:getId() })
check(#cv.glass == 0 and H.count("OnTick") == ticks, "glassLast for a car not loaded, or without parts: nothing left")
-- the driver clicking the car picture twice a second for a minute (the fake's four doors, round and round), each
-- request through the server's dispatch (Commands.lua CommandRate): none dropped, the busiest 10 s keeps half its
-- budget again to spare
local CR, ids = T.CommandRate, { "DoorFrontLeft", "DoorRearLeft", "TrunkDoor", "EngineDoor" }
local dropped, from, reached, times = CR.dropped.liftgate or 0, #H.clientSent, 0, {}
for i = 0, 119 do
    H.side(true, false)
    L.toggle(driver, v, ids[i % #ids + 1])
    for _ = from + 1, #H.clientSent do times[#times + 1] = i * 500 end
    local got
    got, from = H.serve(from)
    reached = reached + (got.liftgate or 0)
    H.advanceMs(500)
end
local busiest = H.busiest(times, CR.LIMITS.liftgate.ms)
check(reached == 120 and #times == 120 and (CR.dropped.liftgate or 0) == dropped and busiest * 1.5 <= CR.LIMITS.liftgate.max,
    "a minute of clicks on the car picture, 2 a second (" .. busiest .. " in the busiest 10 s): all " .. reached
    .. " reach the server's handler")

H.section("hood: E at an open Tesla hood shuts it (Vehicles.Use.EngineDoor)")
-- vanilla E at the hood (Vehicles.lua:829-857) and the mechanics window (ISVehicleMechanics), faked; the module's
-- OnGameStart handler called straight
local vanillaUse, queued, pending, cleared, win = 0, {}, {}, 0, { shown = false }
local before = { use = Vehicles.Use, mech = getPlayerMechanicsUI, queue = ISTimedActionQueue, new = ISCloseVehicleDoor.new }
local function vanillaE() vanillaUse = vanillaUse + 1 end
Vehicles.Use = { EngineDoor = vanillaE }
function win:isReallyVisible() return self.shown end
function win:close() self.shown = false end
getPlayerMechanicsUI = function() return win end
-- the player's queue (ISTimedActionQueue.lua): `pending` is what it holds, the running action first; `queued` what the
-- wrapper adds; clear() stops the running action and empties it (:236-243)
local playerQ = { queue = pending }
function playerQ:removeFromQueue(a)
    for i, x in ipairs(self.queue) do if x == a then table.remove(self.queue, i); return end end
end
ISTimedActionQueue = { add = function(a) queued[#queued + 1] = a end, getTimedActionQueue = function() return playerQ end,
    clear = function() cleared = cleared + 1; for i = #pending, 1, -1 do pending[i] = nil end end }
ISCloseVehicleDoor.new = function(_, chr, veh, part) return { shut = part.id, vehicle = veh, chr = chr } end
L.wrapHoodUse()
local wrapped = Vehicles.Use.EngineDoor
L.wrapHoodUse()
check(wrapped ~= vanillaE and Vehicles.Use.EngineDoor == wrapped and L.hoodUse == vanillaE, "a second game start does not wrap again")
local hood = v.parts.EngineDoor
local function e(car)
    vanillaUse, queued = 0, {}
    Vehicles.Use.EngineDoor(car, car.parts.EngineDoor, driver)
end
hood.door.open = true
e(v)
check(#queued == 1 and queued[1].shut == "EngineDoor" and queued[1].vehicle == v and queued[1].chr == driver and vanillaUse == 0,
    "open hood, no mechanics window (it closed itself 6 tiles away): E shuts the hood, vanilla not asked")
win.shown, win.usedHood = true, hood
e(v)
check(#queued == 0 and vanillaUse == 1, "open hood with its own mechanics window: vanilla (closing that window shuts the hood)")
win.shown, win.usedHood = true, nil
e(v)
check(not win.shown and #queued == 1 and queued[1].shut == "EngineDoor" and vanillaUse == 0,
    "open hood, a window not from this hood (an admin's): the window closes and the hood shuts")
local function examine(car) -- ISOpenMechanicsUIAction:new keeps the car (ISOpenMechanicsUIAction.lua:39-45)
    return { Type = "ISOpenMechanicsUIAction", vehicle = car, forceCancel = function(self) self.cancelled = true end }
end
pending[1] = examine(v)
e(v)
check(cleared == 1 and #pending == 0 and #queued == 1 and queued[1].shut == "EngineDoor" and vanillaUse == 0,
    "open hood, this car's window still on the way (E again while examining): the examining stops, the hood shuts")
local walkTo, later = { Type = "ISPathFindAction" }, examine(v)
pending[1], pending[2], cleared = walkTo, later, 0
e(v)
check(cleared == 0 and later.cancelled and #pending == 1 and pending[1] == walkTo and #queued == 1 and vanillaUse == 0,
    "this car's window queued behind another action: only that one is dropped, the hood shuts")
local elsewhere = examine({})
pending[1] = elsewhere
e(v)
check(cleared == 0 and not elsewhere.cancelled and pending[1] == elsewhere and #queued == 1 and queued[1].shut == "EngineDoor",
    "another car's mechanics window on the way: left alone, this hood shuts")
pending[1] = nil
hood.item = nil
e(v)
check(#queued == 0 and vanillaUse == 1, "no hood fitted: vanilla (the mechanics window)")
hood.item, hood.door.open = {}, false
e(v)
check(#queued == 0 and vanillaUse == 1, "closed hood: vanilla (open it and the mechanics window)")
local other = car({ script = "Base.CarNormal" })
other.parts.EngineDoor.door.open = true
e(other)
check(#queued == 0 and vanillaUse == 1, "another make's open hood: vanilla")
Vehicles.Use, getPlayerMechanicsUI, ISTimedActionQueue, ISCloseVehicleDoor.new = before.use, before.mech, before.queue, before.new
H.side(true, false)
getOnlinePlayers, ISOpenVehicleDoor, ISCloseVehicleDoor = saved.getOnlinePlayers, saved.ISOpenVehicleDoor, saved.ISCloseVehicleDoor
HaloTextHelper, getPlayer, ISInstallVehiclePart = saved.HaloTextHelper, saved.getPlayer, saved.ISInstallVehiclePart
H.side(false, true)
settle()
check(H.count("OnTick") == ticks, "every shell swing settled: no OnTick left (" .. H.count("OnTick") .. " of " .. ticks .. ")")
