-- TowAuth.lua: a joining player (OnCreateLivingCharacter on the server) puts a towing Tesla's trailer that is still on
-- a gone driver's online id back on Server; a pair someone is driving, a towed car whose own driver is online, an
-- animal, a vanilla tractor and single player are left alone. That the client then keeps its hands off the trailer is
-- engine behaviour: E2E semi-sp lk20 params.
local check = H.check
local T = MinidoracatTesla

H.section("tow authority hand-back")
local savedCell, savedById = getCell, getPlayerByOnlineID
local online = { [4] = true, [9] = true } -- ids someone online holds (the server's IDToPlayerMap)
getPlayerByOnlineID = function(id) return online[id] and H.player() or nil end
local cars = {}
getCell = function() return { getVehicles = function() return { iterator = function()
    local i = 0
    return { hasNext = function() return i < #cars end, next = function() i = i + 1; return cars[i] end }
end } end } end

-- a tractor towing a trailer; npid: the online id holding each one's physics (-1 = the server)
local function rig(script, headNpid, trailerNpid)
    local head = H.vehicle({ script = script })
    local trailer = H.vehicle({ script = "Base.MinidoracatTesla_SemiTrailer" })
    head.npid, trailer.npid = headNpid, trailerNpid
    function head:getVehicleTowing() return trailer end
    function trailer:getVehicleTowing() return nil end
    function trailer:authorizationChanged(c) self.npid = c and c:getOnlineID() or -1; self.changes = (self.changes or 0) + 1 end
    cars[#cars + 1] = head
    cars[#cars + 1] = trailer
    return head, trailer
end

-- single player: nothing to hand back, no handler
local before = H.count("OnCreateLivingCharacter")
H.side(false, false)
dofile("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/server/MinidoracatTesla/TowAuth.lua")
check(H.count("OnCreateLivingCharacter") == before, "single player: no join hook")
H.side(false, true)
H.require("MinidoracatTesla/TowAuth")
check(H.count("OnCreateLivingCharacter") == before + 1, "MP server: one join hook")

local _, gone = rig("Base.MinidoracatTesla_Semi", -1, 0)          -- driver disconnected: Semi back, trailer not
local _, driven = rig("Base.MinidoracatTesla_Semi", 4, 4)         -- someone driving the pair
local _, vanilla = rig("Base.PickUpTruck", -1, 8)                 -- not ours
local _, parked = rig("Base.MinidoracatTesla_Cybertruck", -1, -1) -- parked, both on the server
local _, towedDriven = rig("Base.MinidoracatTesla_ModelY", -1, 9) -- towed car driven by someone online, tractor's engine off

local logs = #H.logLines
H.fire("OnCreateLivingCharacter", { _class = "IsoAnimal" }, {})
check(gone.npid == 0 and not gone.changes, "an animal made: nothing scanned")

H.fire("OnCreateLivingCharacter", H.player(), {})
check(gone.npid == -1 and gone.changes == 1, "a player joining: the gone driver's trailer back on the server")
check(driven.npid == 4 and not driven.changes, "a pair being driven (same id on both): left with its driver")
check(vanilla.npid == 8 and not vanilla.changes, "a vanilla tractor's trailer: left to vanilla")
check(not parked.changes, "a parked pair on the server: untouched")
check(towedDriven.npid == 9 and not towedDriven.changes, "a towed car its online driver holds: left with that driver")
local lines = {}
for i = logs + 1, #H.logLines do lines[#lines + 1] = H.logLines[i] end
check(#lines == 1 and lines[1]:find("[MinidoracatTeslaFor42] towauth: Base.MinidoracatTesla_Semi", 1, true) ~= nil
    and lines[1]:find("online id 0", 1, true) ~= nil, "one log line, only for the hand-back")

H.fire("OnCreateLivingCharacter", H.player(), {})
check(gone.changes == 1 and #H.logLines == logs + 1, "the next join: nothing left to do, no log")

getCell, getPlayerByOnlineID = savedCell, savedById
