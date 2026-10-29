-- Aiming from a Tesla seat stays seated (models.md section 8). In a car the "aim" anim variable follows the aim key
-- even with the window shut (IsoPlayer.java:4412-4446, IsoGameCharacter.java:976), and vanilla's player-vehicle aim
-- nodes play standing clips: through the glass the character stood up through the roof.
-- AnimSets/player-vehicle/aim/MinidoracatTesla_aim_seated.xml plays the seated idle instead while the character's
-- MinidoracatTeslaSeated is true. Anim variables live on each client's copy of a character, so every client sets it:
-- - the local player at once on every enter (ISEnterVehicle:perform, a saved seat on load IsoCell.java:4524-4525, MP
--   seat sync BaseVehicle.java:2527-2530) and exit (ISExitVehicle:perform, teleport IsoGameCharacter.java:16722-16727,
--   TeleportPacket.java:63-66). Switching seats stays in the same car; a respawned character is a new IsoPlayer.
-- - other players once a game minute (MP client): their aim reaches this client through the synced PlayerAimState
--   (IsoPlayer.java:1190-1191, PlayerAimState.java:41-74), but no Lua event fires when they get in or out here
--   (enterRSync triggers OnEnterVehicle for local players only, BaseVehicle.java:2527).
--   ponytail: up to one game minute (2.5 s at 1-hour days) before another player shows seated; an event from the
--   server when someone gets in or out of a Tesla if that ever shows.
require "MinidoracatTesla/Core"
require "Vehicles/ISUI/ISVehicleDashboard" -- registers OnExitVehicle (ISVehicleDashboard.lua:715); OnEnterVehicle is Java's

local T = MinidoracatTesla
local VAR = "MinidoracatTeslaSeated"

local function sync(player)
    if not player then return end
    local v = player:getVehicle()
    if v and T.isTesla(v) then
        player:setVariable(VAR, true)
    else
        player:clearVariable(VAR)
    end
end

Events.OnEnterVehicle.Add(sync)
Events.OnExitVehicle.Add(sync)
Events.EveryOneMinute.Add(function()
    if not isClient() then return end
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do sync(list:get(i)) end
end)
