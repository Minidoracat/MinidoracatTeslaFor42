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
    for _, id in ipairs({ "TrunkDoor", "DoorFrontLeft" }) do
        local door = { open = false, locked = id == "TrunkDoor", broken = false }
        function door:isOpen() return self.open end
        function door:setOpen(b) self.open = b end
        function door:isLocked() return self.locked end
        v.parts[id] = { id = id, door = door, item = {}, getId = function(self) return self.id end,
            getDoor = function(self) return self.door end, getInventoryItem = function(self) return self.item end }
    end
    function v:toggleLockedDoor(part, chr, locked) -- BaseVehicle.java:1230-1244 (seated player may unlock)
        if not locked and not part.door.broken and part.door.locked then part.door.locked = false end
    end
    function v:transmitPartDoor() self.doorTx = self.doorTx + 1 end
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
cmd(driver, { vid = v:getId() })
local d = v.parts.TrunkDoor.door
check(d.open and not d.locked and v.doorTx == 1, "driver, parked, locked: unlocked, opened, door synced")
check(v.anims[1] == "TrunkDoor:Open" and v.sound == "Open", "SP: client handler played the Open anim and its sound")
check(math.floor(v:getColorHue()) == 16 and H.near(v:getColorHue() - 16, 0.69, 1e-6) and v.colorTx == 1,
    "shell bits: tailgate open = hue integer 16, the paint hue kept, transmitted")
cmd(driver, { vid = v:getId() })
check(not d.open and v.anims[2] == "TrunkDoor:Close", "second press closes")
check(H.near(v:getColorHue(), 0.69, 1e-6), "shell bits cleared on close")
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
cmd(passenger, { vid = v:getId() })
check(denied("NOT_DRIVER") and not d.open and v.doorTx == 2, "passenger: NOT_DRIVER, nothing changed")
v.speed = 12
cmd(driver, { vid = v:getId() })
check(denied("MOVING") and not d.open and v.doorTx == 2, "driving: MOVING, nothing changed")
v.speed = 0.4
d.locked, d.broken = true, true
cmd(driver, { vid = v:getId() })
check(denied("LIFTGATE_LOCKED") and d.locked and not d.open and v.doorTx == 2, "broken lock: LIFTGATE_LOCKED, still locked and shut")
d.broken = false
v.parts.TrunkDoor.item = nil
cmd(driver, { vid = v:getId() })
check(denied("NO_LIFTGATE") and not d.open, "liftgate part uninstalled: NO_LIFTGATE")
v.parts.TrunkDoor.item = {}
local n = #H.sent
cmd(driver, { vid = v:getId() })
local a, b = H.sent[n + 1], H.sent[n + 2]
check(d.open and #H.sent == n + 2 and a.player == driver and b.player == passenger and a.command == "partAnim"
    and a.args.part == "TrunkDoor" and a.args.open == true and a.args.sound == true,
    "MP: opened, partAnim { TrunkDoor, open, sound } to every online player")

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
b = H.sent[n + 1]
check(#H.sent == n + 1 and b.player == passenger and b.args.part == "DoorFrontLeft" and b.args.open == true and not b.args.sound,
    "door opened by the driver: anim to the others only (the opener played it in :start)")
n = #H.sent
ISCloseVehicleDoor.complete({ vehicle = v, part = fl, character = passenger })
check(#H.sent == n + 1 and H.sent[n + 1].player == driver and H.sent[n + 1].args.open == false, "closed by the passenger: anim to the driver")
local gas = car({ script = "Base.CarNormal" })
n = #H.sent
ISOpenVehicleDoor.complete({ vehicle = gas, part = gas.parts.DoorFrontLeft, character = driver })
check(#H.sent == n, "not a Tesla: nothing sent")

H.section("liftgate: client")
H.side(true, false)
v.speed = 30
H.clientSent = {}
check(L.toggle(driver, v) == false and #H.clientSent == 0 and halo[#halo] == "IGUI_MinidoracatTesla_Deny_MOVING",
    "key while driving: refused on the client with a halo, nothing sent")
v.speed = 0
check(L.toggle(driver, v) and H.clientSent[1].command == "liftgate", "key while parked: liftgate sent")
local na = #v.anims
T.ClientCommands.partAnim({ vid = 424242, part = "TrunkDoor", open = true })
T.ClientCommands.partAnim({ vid = v:getId(), part = 7, open = true })
check(#v.anims == na, "client without the car, or a bad part id: ignored")
getOnlinePlayers, ISOpenVehicleDoor, ISCloseVehicleDoor = saved.getOnlinePlayers, saved.ISOpenVehicleDoor, saved.ISCloseVehicleDoor
HaloTextHelper, getPlayer = saved.HaloTextHelper, saved.getPlayer
H.side(false, true)
