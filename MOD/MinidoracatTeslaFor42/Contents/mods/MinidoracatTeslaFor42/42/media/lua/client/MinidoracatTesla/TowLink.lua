-- MP client: a hitch this client was never told of. The server tells every client once that two cars hooked up, and a
-- client hooks them only if it has both built right then (VehicleTowingAttachPacket.java:71-76). A car's own data says
-- what it was hitched to when the server sent it (BaseVehicle.java:2830-2838), but the engine's retry runs only from a
-- tractor whose data says it tows something (:3341-3343, :10407-10418). So with the tractor sent before the hitch and
-- the trailer built after it, the pair stays apart on this client until both unload or its player takes the wheel:
-- someone walking up from the tractor's end while another player hitches. The Semi and its trailer always sit in two
-- chunks (11 squares between their centres). E2E join-race-mp: X7 walking up 8/8 missed, X5 9/9 when the server
-- hitched 100 ms or more before the trailer was built here; vanilla's pickup and trailer the same across a chunk edge
-- (8/8), the engine's own. The tractor can be the late one too: a car whose chunk is not loaded yet is known by id but
-- not built (VehicleFullUpdatePacket.java:85-93), and hooking it does nothing (no script yet, :810-812, :10113).
-- Here: each Tesla or trailer this client builds asks the server once what it is hitched to (towAsk, server
-- TowAuth.lua); the answer (towLink) hooks the two as the missed packet would have. No tick: OnSpawnVehicleEnd fires
-- once per car built (BaseVehicle.java:913). A pair with no Tesla in it is left to vanilla (the server does not
-- answer). So is a Tesla towing a vanilla car on a rope when the vanilla car is the late one: asking about every car
-- a client builds would cost more than that case is worth.
if not isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Net"

local T = MinidoracatTesla
local TL = {}
T.TowLink = TL

-- `a` = the tractor this client just hooked car `id` to on an answer: a check, see towLink
local function ask(id, a)
    local p = getSpecificPlayer(0)
    if p then T.request(p, "towAsk", { vid = id, a = a }) end
end

-- Cars built during the loading screen wait for the first tick: a command sent before it never reaches the server
-- (ParkModesUI.lua pullInbox has why). `early` = their ids, nil once asked: one a tick, the engine drops every mod's
-- commands once a client sends more than MaxPacketsPerSecond of them in a second (PacketsCache.java:76-100).
-- "Trailer" in the script name is the engine's own test for one (BaseVehicle.java:10117, :10387).
local early = {}
function TL.onSpawn(v)
    if not T.isTesla(v) and not v:getScriptName():find("Trailer", 1, true) then return end
    if early then early[#early + 1] = v:getId() else ask(v:getId()) end
end
Events.OnSpawnVehicleEnd.Add(TL.onSpawn)

local function login()
    local id = table.remove(early)
    if id then return ask(id) end
    early = nil
    Events.OnTick.Remove(login)
end
Events.OnGameStart.Add(function() Events.OnTick.Add(login) end)

-- the server's answer: car `a` tows car `b` there. Hooked only when this client has both and neither end is taken
-- (the packet came after all, or the engine's retry got there first); addPointConstraint is what the packet runs (:74).
-- A car known here but not built yet takes no hook; a Tesla or a trailer asks again when it is built.
-- An answer can arrive after an unhitch that left the server later: commands are reliable but not ordered, the towing
-- packets are (PacketTypes.java:508, VehicleTowingDetachPacket.java:15-20), and nothing from the engine would undo
-- that hook. So each hook made here is checked once: the server says `apart` if it no longer has the pair, and this
-- client lets go as the unhitch packet does (VehicleTowingDetachPacket.java:66) and asks afresh, in case that word was
-- the late one.
T.ClientCommands.towLink = function(args)
    local a, b = getVehicleById(args.a), getVehicleById(args.b)
    if not a or not b or a == b then return end
    if args.apart then
        if a:getVehicleTowing() ~= b then return end
        a:breakConstraint(true, true)
        T.log("towlink: " .. a:getScriptName() .. " #" .. a:getId() .. " let go of #" .. b:getId() .. ", the server has them apart")
        return ask(b:getId())
    end
    if a:getVehicleTowing() or b:getVehicleTowedBy() then return end
    a:addPointConstraint(nil, b, args.attA, args.attB)
    if a:getVehicleTowing() ~= b then return end
    T.log("towlink: " .. a:getScriptName() .. " #" .. a:getId() .. " hooked to #" .. b:getId() .. ", the hitch was missed here")
    ask(b:getId(), a:getId())
end
