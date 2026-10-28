-- Power liftgate and door-anim sync (shared/MinidoracatTesla/Liftgate.lua): server rules, unlock-then-toggle,
-- sync, client anim. Real animation, sound and the second client are E2E hud-sp / liftgate-mp.
local check = H.check
local T = MinidoracatTesla
local SRC = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/shared/MinidoracatTesla/Liftgate.lua"

-- SP load: both the server and the client handler register (the module branches on isClient/isServer at load)
-- globals other tests set up (park_fakes.lua): put them back at the end
local saved = { getOnlinePlayers = getOnlinePlayers, ISOpenVehicleDoor = ISOpenVehicleDoor,
    ISCloseVehicleDoor = ISCloseVehicleDoor, HaloTextHelper = HaloTextHelper, getPlayer = getPlayer }
H.side(false, false)
-- vanilla door actions: complete() opens/closes and returns true (ISOpenVehicleDoor.lua:61-97); SP wraps them too
ISOpenVehicleDoor = { complete = function(self) self.part:getDoor():setOpen(true); return true end }
ISCloseVehicleDoor = { complete = function(self) self.part:getDoor():setOpen(false); return true end }
H.stub("Vehicles/TimedActions/ISOpenVehicleDoor")
H.stub("Vehicles/TimedActions/ISCloseVehicleDoor")
dofile(SRC)
local L = T.Liftgate
local halo = {}
HaloTextHelper = { addBadText = function(_, text) halo[#halo + 1] = text end }
function getPlayer() return nil end

local function car(o)
    local v = H.vehicle(o)
    v.anims, v.doorTx = {}, 0
    for _, id in ipairs({ "TrunkDoor", "DoorFrontLeft", "DoorRearLeft", "EngineDoor" }) do
        local door = { open = false, locked = id == "TrunkDoor", broken = false }
        function door:isOpen() return self.open end
        function door:setOpen(b) self.open = b end
        function door:isLocked() return self.locked end
        function door:setLocked(b) self.locked = b end
        function door:isLockBroken() return self.broken end
        v.parts[id] = { id = id, door = door, item = {}, getId = function(self) return self.id end,
            getDoor = function(self) return self.door end, getInventoryItem = function(self) return self.item end,
            getVehicle = function() return v end }
    end
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
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
local d = v.parts.TrunkDoor.door
check(d.open and not d.locked and v.doorTx == 1, "driver, parked, locked: unlocked, opened, door synced")
check(v.anims[1] == "TrunkDoor:Open" and v.sound == "Open", "SP: client handler played the Open anim and its sound")
check(math.floor(v:getColorHue()) == 16 and H.near(v:getColorHue() - 16, 0.69, 1e-6) and not v.colorTx,
    "shell bits: tailgate open = hue integer 16, the paint hue kept, no transmitColorHSV")
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(not d.open and v.anims[2] == "TrunkDoor:Close", "second press closes")
check(H.near(v:getColorHue(), 0.69, 1e-6), "shell bits cleared on close")
check(not d.locked, "car unlocked: the closed liftgate stays unlocked")
v.cabinLocked = true -- locked car: the liftgate locks again when it shuts
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(not d.open and d.locked, "locked car: liftgate shut from the dashboard -> locked again")
local lidE = v.parts.EngineDoor.door
cmd(driver, { vid = v:getId(), part = "EngineDoor" })
cmd(driver, { vid = v:getId(), part = "EngineDoor" })
check(not lidE.open and lidE.locked, "frunk lid shut on a locked car: locked again, like the liftgate (the car locks as a whole)")
d.locked, d.broken = false, true
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(not d.locked, "broken lock: shut but not locked (it could never open again)")
d.broken, v.cabinLocked = false, false
local sp = car({})
ISOpenVehicleDoor.complete({ vehicle = sp, part = sp.parts.DoorFrontLeft, character = driver })
check(math.floor(sp:getColorHue()) == 1 and #sp.anims == 0, "SP door action: shell bit 1 for DoorFrontLeft, no anim broadcast")
ISCloseVehicleDoor.complete({ vehicle = sp, part = sp.parts.DoorFrontLeft, character = driver })
check(math.floor(sp:getColorHue()) == 0, "SP door closed: bit cleared")

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
    "MP: shell hue (16 + paint) to every player near as a command, no transmitColorHSV (VehicleProperties)")
check(a.player == driver and b.player == passenger and a.command == "partAnim"
    and a.args.part == "TrunkDoor" and a.args.open == true and a.args.sound == true,
    "MP: opened, partAnim { TrunkDoor, open, sound } to every player near")

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
check(got(corner, n, "shell") == 1 and got(corner, n, "partAnim") == 1 and got(driver, n) == 2 and got(passenger, n) == 2,
    "...shell and partAnim once each to the driver, the passenger and a player 96 tiles away on both axes")
n = #H.sent
ISOpenVehicleDoor.complete({ vehicle = v, part = v.parts.DoorFrontLeft, character = passenger })
check(got(far, n) == 0 and got(corner, n, "partAnim") == 1 and got(driver, n, "partAnim") == 1 and got(passenger, n, "partAnim") == 0,
    "vanilla door action: anim to the players near but the opener, none far")
ISCloseVehicleDoor.complete({ vehicle = v, part = v.parts.DoorFrontLeft, character = passenger })
far.x = v.x + 10 -- walked up: the car (doors, hue) comes with the engine's full update; later changes reach it
n = #H.sent
cmd(driver, { vid = v:getId(), part = "TrunkDoor" })
check(d.open and got(far, n, "shell") == 1 and got(far, n, "partAnim") == 1, "the far player walked up: the next open reaches it")
online = { driver, passenger }

H.section("dashboard doors: any door part (HUD car picture)")
local rl, lid = v.parts.DoorRearLeft.door, v.parts.EngineDoor.door
rl.locked = true
n = #H.sent
cmd(driver, { vid = v:getId(), part = "DoorRearLeft" })
a = H.sent[n + 3] -- after the two `shell` commands (driver, passenger)
check(rl.open and not rl.locked and a.command == "partAnim" and a.args.part == "DoorRearLeft" and a.args.sound == true,
    "locked rear left door: unlocked, opened, partAnim { DoorRearLeft, sound }")
check(math.floor(v:getColorHue()) == 16 + 4, "shell bits: liftgate (16) + rear left door (4)")
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
check(not lid.open and not rl.open and math.floor(v:getColorHue()) == 16, "second clicks close the lid and the door")

H.section("door anim sync (MP server)")
-- vanilla door actions: complete() opens/closes and returns true (ISOpenVehicleDoor.lua:61-97)
ISOpenVehicleDoor = { complete = function(self) self.part:getDoor():setOpen(true); return true end }
ISCloseVehicleDoor = { complete = function(self) self.part:getDoor():setOpen(false); return true end }
H.stub("Vehicles/TimedActions/ISOpenVehicleDoor")
H.stub("Vehicles/TimedActions/ISCloseVehicleDoor")
dofile(SRC) -- MP server load: wraps the two actions
local fl = v.parts.DoorFrontLeft
n = #H.sent
check(ISOpenVehicleDoor.complete({ vehicle = v, part = fl, character = driver }) == true, "wrapped complete keeps the vanilla result")
b = H.sent[n + 3]
check(#H.sent == n + 3 and H.sent[n + 1].command == "shell" and math.floor(H.sent[n + 1].args.hue) == 17
    and b.player == passenger and b.args.part == "DoorFrontLeft" and b.args.open == true and not b.args.sound,
    "door opened by the driver: shell hue to everyone, anim to the others only (the opener played it in :start)")
n = #H.sent
ISCloseVehicleDoor.complete({ vehicle = v, part = fl, character = passenger })
check(#H.sent == n + 3 and H.sent[n + 3].player == driver and H.sent[n + 3].args.open == false
    and math.floor(H.sent[n + 1].args.hue) == 16, "closed by the passenger: shell bit cleared, anim to the driver")
local tg = v.parts.TrunkDoor
tg.door.open, tg.door.locked, v.cabinLocked = true, false, true -- opened on a locked car (the app, the dashboard)
local tx2 = v.doorTx
ISCloseVehicleDoor.complete({ vehicle = v, part = tg, character = passenger })
check(tg.door.locked and v.doorTx == tx2 + 1, "locked car: liftgate shut by hand (vanilla close) -> locked again and synced")
v.cabinLocked = false
local gas = car({ script = "Base.CarNormal" })
n = #H.sent
ISOpenVehicleDoor.complete({ vehicle = gas, part = gas.parts.DoorFrontLeft, character = driver })
check(#H.sent == n, "not a Tesla: nothing sent")

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
H.side(true, false)
getOnlinePlayers, ISOpenVehicleDoor, ISCloseVehicleDoor = saved.getOnlinePlayers, saved.ISOpenVehicleDoor, saved.ISCloseVehicleDoor
HaloTextHelper, getPlayer = saved.HaloTextHelper, saved.getPlayer
H.side(false, true)
