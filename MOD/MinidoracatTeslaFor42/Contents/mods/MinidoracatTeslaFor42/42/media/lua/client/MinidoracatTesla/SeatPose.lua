-- The seated pose in a Tesla (references/seating.md). Two anim variables pick this MOD's player-vehicle nodes:
-- - MinidoracatTeslaSeated (every Tesla seat): idle plays MinidoracatTesla_IdleDrivingRear, vanilla's Bob_IdleDriving
--   with the thighs raised 30 deg and the knees bent 40 deg more (scripts/seat_anim.py), so rear-row feet reach the
--   floor of the lower seats without reaching into the front seats; aiming keeps it too. In a car the "aim" variable
--   follows the aim key even with the window shut (IsoPlayer.java:4412-4446, IsoGameCharacter.java:976) and vanilla's
--   aim nodes play standing clips: through the glass the character stood up through the roof.
-- - MinidoracatTeslaRecline (the two front seats): idle and aim play MinidoracatTesla_IdleDrivingRecline, Bob_IdleDriving
--   leaned back 25 deg with the thighs lowered 10 deg, so the head clears the low roof over the front seats.
--   AnimSets/player-vehicle/idle/MinidoracatTesla_idle_recline.xml (priority 2) and _idle_rear.xml (1),
--   aim/MinidoracatTesla_aim_recline.xml (2) and _aim_seated.xml (1): the first matching node wins.
-- Anim variables live on each client's copy of a character, so every client sets them:
-- - the local player at once on every enter (ISEnterVehicle:perform, a saved seat on load IsoCell.java:4524-4525, MP
--   seat sync BaseVehicle.java:2527-2530), seat switch (ISSwitchVehicleSeat:perform, ISSwitchVehicleSeat.lua:57) and
--   exit (ISExitVehicle:perform, teleport IsoGameCharacter.java:16722-16727, TeleportPacket.java:63-66). A respawned
--   character is a new IsoPlayer.
-- - other players (MP client): no Lua event fires here when they get in, switch or get out (enterRSync triggers
--   OnEnterVehicle for local players only, BaseVehicle.java:2527). Their own client sends `seat` (below); the server
--   relays their online id to the clients near, now and HatHide.AGAIN_MS later (server HatHide.lua), and this client
--   syncs that player on each (ClientCommands.seat). The game minute covers the rest: a car or player that just loaded
--   here (sent to a client 64-96 tiles away on both axes, GameServer.java:2808-2809, UdpConnection.java:224-226: before
--   it is on screen; its passengers come after OnSpawnVehicleEnd,
--   VehicleFullUpdatePacket.java:114, or a vehicle update later for a player not known here yet,
--   VehiclePassengers.java:36-38), a login in a seat (its enter can fire while loading, when sendClientCommand does
--   not reach the server, LuaManager.java:8940-8947), a lost command: a game day's real length / 1440, 2.5 s at
--   the default 1-hour day (10 s at 4 hours).
require "MinidoracatTesla/Core"
require "Vehicles/ISUI/ISVehicleDashboard" -- registers OnExitVehicle and OnSwitchVehicleSeat (ISVehicleDashboard.lua:715-716)

local T = MinidoracatTesla
local SEATED, RECLINE = "MinidoracatTeslaSeated", "MinidoracatTeslaRecline"

local function set(player, name, on)
    if on then player:setVariable(name, true) else player:clearVariable(name) end
end

local function sync(player)
    if not player then return end
    local v = player:getVehicle()
    local tesla = v and T.isTesla(v)
    set(player, SEATED, tesla)
    set(player, RECLINE, tesla and v:getSeat(player) <= 1)
end

-- the local player's own enter / switch / exit sends `seat`: the server puts on or takes off the hat hider and tells
-- the clients near to sync this player (server HatHide.lua). Sent in a Tesla, out of one (the hider's SyncClothing may
-- not have reached this client yet: review 2026-11-02), or wearing the hider; a vanilla car sends nothing. inTesla:
-- per split-screen player, set at each enter / switch / exit.
local inTesla = {}
local function seat(player)
    sync(player)
    if not (player and player:isLocalPlayer()) then return end
    local v, n = player:getVehicle(), player:getPlayerNum()
    local tesla = v and T.isTesla(v) or false
    if tesla or inTesla[n] or player:getWornItem(MinidoracatTeslaHatLoc) then
        sendClientCommand(player, T.MODULE, "seat", {})
    end
    inTesla[n] = tesla
end
Events.OnEnterVehicle.Add(seat)
Events.OnExitVehicle.Add(seat)
Events.OnSwitchVehicleSeat.Add(seat)
-- the server's relay of another player's `seat` (only that sender's online id, HatHide.lua)
T.ClientCommands = T.ClientCommands or {}
T.ClientCommands.seat = function(args)
    if type(args.id) == "number" then sync(getPlayerByOnlineID(args.id)) end
end
Events.EveryOneMinute.Add(function()
    if not isClient() then return end
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do sync(list:get(i)) end
end)
