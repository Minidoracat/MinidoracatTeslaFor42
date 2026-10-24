-- Power liftgate (shared/MinidoracatTesla/Liftgate.lua): server rules, unlock-then-toggle, sync, client anim.
-- Real animation, sound and the second client are E2E hud-sp / liftgate-mp.
local check = H.check
local T = MinidoracatTesla

-- SP load: both the server and the client handler register (the module branches on isClient/isServer at load)
H.side(false, false)
dofile("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/shared/MinidoracatTesla/Liftgate.lua")
local L = T.Liftgate
local halo = {}
HaloTextHelper = { addBadText = function(_, text) halo[#halo + 1] = text end }
function getPlayer() return nil end

local function car(o)
    local v = H.vehicle(o)
    local door = { open = false, locked = true, broken = false }
    function door:isOpen() return self.open end
    function door:setOpen(b) self.open = b end
    function door:isLocked() return self.locked end
    v.parts.TrunkDoor = { door = door, item = {}, getDoor = function(self) return self.door end,
        getInventoryItem = function(self) return self.item end }
    v.anims, v.doorTx = {}, 0
    function v:toggleLockedDoor(part, chr, locked) -- BaseVehicle.java:1230-1244 (seated player may unlock)
        if not locked and not part.door.broken and part.door.locked then part.door.locked = false end
    end
    function v:transmitPartDoor() self.doorTx = self.doorTx + 1 end
    function v:playPartAnim(part, anim) self.anims[#self.anims + 1] = anim end
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
check(v.anims[1] == "Open" and v.sound == "Open", "SP: client handler played the Open anim and its sound")
cmd(driver, { vid = v:getId() })
check(not d.open and v.anims[2] == "Close", "second press closes")

local passenger = H.player({ name = "bob" })
passenger.vehicle = v
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
local b = H.sent[n + 1]
check(d.open and b and b.player == nil and b.command == "liftgate" and b.args.open == true and b.args.vid == v:getId(),
    "MP: opened, then one broadcast { vid, open } to every client")

H.section("liftgate: client")
H.side(true, false)
v.speed = 30
H.clientSent = {}
check(L.toggle(driver, v) == false and #H.clientSent == 0 and halo[#halo] == "IGUI_MinidoracatTesla_Deny_MOVING",
    "key while driving: refused on the client with a halo, nothing sent")
v.speed = 0
check(L.toggle(driver, v) and H.clientSent[1].command == "liftgate", "key while parked: liftgate sent")
local na = #v.anims
T.ClientCommands.liftgate({ vid = 424242, open = true })
check(#v.anims == na, "client without the car: ignored")
H.side(false, true)
