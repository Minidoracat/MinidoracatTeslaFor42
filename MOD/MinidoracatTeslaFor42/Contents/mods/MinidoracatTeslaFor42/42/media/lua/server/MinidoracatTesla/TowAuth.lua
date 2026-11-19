-- MP server: a towing Tesla's trailer left on a gone driver's physics authority goes back to the server before anyone
-- gets that online id again. The engine's disconnect hands back the driver's own car only (GameServer.java:2642-2652);
-- stepping out hands back the trailer too (BaseVehicle.java:4027-4034). The next player given that id (slot x 4,
-- GameServer.java:2706-2727; the one reconnecting, usually) gets the trailer as Local before the two hook up again and
-- runs its physics (BaseVehicle.java:629-637 over :845-850): a Semi folded to -76 degrees knocks it loose
-- (detachTrailerSpontaneous, :10261-10318) and the server unhitches it (VehicleCommands.lua:353-360). semi-sp lk01..20:
-- 9/20 lost the trailer; the same hand-back from a scenario, lkF1..8: 8/8 kept it.
-- When: the server has no disconnect or login event for Lua. It loads every joining player into a new IsoPlayer, whose
-- constructor fires OnCreateLivingCharacter (receivePlayerConnect -> serverLoadNetworkCharacter, GameServer.java:2838-
-- 2843, ServerPlayerDB.java:255, IsoPlayer.java:514-515,637), before the connection is fully connected (:2878) and
-- vehicles go to fully connected ones only (VehicleManager.java:160-161): an id comes back only through here, however
-- fast the reconnect or long the game minute. Animals are IsoPlayers too (IsoPlayer.java:518-559): skipped. Normal
-- driving never matches: the engine sets the pair together everywhere (BaseVehicle.java:3991-4034, :10156-10163). A
-- car loaded again (chunk, server restart) starts on Server (:294-295; load does not read it).
if not isServer() then return end
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local TA = {}
T.TowAuth = TA

-- every loaded towing Tesla on Server whose trailer is still someone's: trailer back to Server (authorizationChanged
-- nil = Server, -1, BaseVehicle.java:10175-10180). IsoCell.vehicles is a HashSet: iterator() (SemiHitch.lua has why).
function TA.handBack()
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        local t = v:getVehicleTowing()
        if t and v:getNetPlayerId() == -1 and t:getNetPlayerId() ~= -1 and T.isTesla(v) then
            T.log("towauth: " .. v:getScriptName() .. " #" .. v:getId() .. " trailer #" .. t:getId() .. " still on online id "
                .. t:getNetPlayerId() .. ", handed back to the server")
            t:authorizationChanged(nil)
        end
    end
end

Events.OnCreateLivingCharacter.Add(function(character)
    if not instanceof(character, "IsoAnimal") then TA.handBack() end
end)
