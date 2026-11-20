-- MP client: a hitch this client was never told of. The server tells every client once that two cars hooked up, and a
-- client hooks them only if it has both built right then (VehicleTowingAttachPacket.java:71-76). A car built later
-- comes with no word of it (VehicleFullUpdatePacket.java:55-104), and the engine's own retry runs from a tractor that
-- was built already hooked up (BaseVehicle.java:3341-3343, :10407-10418). So with the tractor built and the trailer not
-- yet, the pair stays apart on this client until both unload or its player takes the wheel: someone walking up from
-- the tractor's end while another player hitches. The Semi and its trailer always sit in two chunks (11 squares
-- between their centres). E2E join-race-mp: X7 walking up 8/8 missed, X5 9/9 when the server hitched 100 ms or more
-- before the trailer was built here; vanilla's pickup and trailer the same across a chunk edge (8/8), the engine's own.
-- Here: each Tesla or trailer this client builds asks the server once who tows it (towAsk, server TowAuth.lua); the
-- answer (towLink) hooks the two as the missed packet would have. No tick: OnSpawnVehicleEnd fires once per car built
-- (BaseVehicle.java:913). A pair with no Tesla in it is left to vanilla (the server does not answer). So is a Tesla
-- towing a vanilla car on a rope: asking about every car a client builds would cost more than that case is worth.
if not isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Net"

local T = MinidoracatTesla
local TL = {}
T.TowLink = TL

local function ask(id)
    local p = getSpecificPlayer(0)
    if p then T.request(p, "towAsk", { vid = id }) end
end

-- Cars built during the loading screen wait for the first tick: a command sent before it never reaches the server
-- (ParkModesUI.lua pullInbox has why). `early` = their ids, nil once that tick has asked.
-- "Trailer" in the script name is the engine's own test for one (BaseVehicle.java:10117, :10387).
local early = {}
function TL.onSpawn(v)
    if not T.isTesla(v) and not v:getScriptName():find("Trailer", 1, true) then return end
    if early then early[#early + 1] = v:getId() else ask(v:getId()) end
end
Events.OnSpawnVehicleEnd.Add(TL.onSpawn)

local function login()
    Events.OnTick.Remove(login)
    local ids = early or {}
    early = nil
    for _, id in ipairs(ids) do ask(id) end
end
Events.OnGameStart.Add(function() Events.OnTick.Add(login) end)

-- the server's answer: car `a` tows car `b` there. Hooked only when this client has both and neither end is taken
-- (the packet came after all, or the engine's retry got there first); addPointConstraint is what the packet runs (:74).
T.ClientCommands.towLink = function(args)
    local a, b = getVehicleById(args.a), getVehicleById(args.b)
    if not a or not b or a == b or a:getVehicleTowing() or b:getVehicleTowedBy() then return end
    a:addPointConstraint(nil, b, args.attA, args.attB)
    T.log("towlink: " .. a:getScriptName() .. " #" .. a:getId() .. " hooked to #" .. b:getId() .. ", the hitch was missed here")
end
