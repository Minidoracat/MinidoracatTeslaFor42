-- MP server: a towing Tesla's trailer left on a gone driver's physics authority goes back to the server before anyone
-- gets that online id again. The engine's disconnect hands back the driver's own car only (GameServer.java:2642-2652);
-- stepping out hands back the trailer too (BaseVehicle.java:4027-4034). The next player given that id (slot x 4 + the
-- split-screen index, GameServer.java:2706-2727, ConnectCoopPacket.java:125; the one reconnecting, usually) gets the
-- trailer as Local before the two hook up again and runs its physics (BaseVehicle.java:629-637 over :845-850): a Semi
-- folded to -76 degrees knocks it loose
-- (detachTrailerSpontaneous, :10261-10318) and the server unhitches it (VehicleCommands.lua:353-360). semi-sp lk01..20:
-- 9/20 lost the trailer; the same hand-back from a scenario, lkF1..8: 8/8 kept it.
-- When: the server has no disconnect or login event for Lua. It loads every joining player into a new IsoPlayer, whose
-- constructor fires OnCreateLivingCharacter (receivePlayerConnect -> serverLoadNetworkCharacter, GameServer.java:2838-
-- 2843, ServerPlayerDB.java:255, IsoPlayer.java:514-515,637), before the connection is fully connected (:2878) and
-- vehicles go to fully connected ones only (VehicleManager.java:160-161): an id comes back only through here, however
-- fast the reconnect or long the game minute. Animals are IsoPlayers too (IsoPlayer.java:518-559): skipped. The pair
-- is not always set together: a towed car with its own driver gets its own authority while the tractor's driver sits
-- with the engine off (BaseVehicle.java:4019-4021 over :7506-7507; entering gives none with the engine off,
-- VehicleEnterPacket.java:123-129), so each car is judged alone, by whether its holder is online: disconnect drops the
-- id from the server's map (GameServer.java:2668) and a joining player is put in it after this event (:2864). A car
-- loaded again (chunk, server restart) starts on Server (BaseVehicle.java:294-295; load does not read it).
-- The tractor itself can be left behind too: hitching on foot puts both on the player as LocalCollide
-- (:10157-10164), only his client gives them back, seconds later (WorldSimulation.java:184-197), and the server never
-- times it out (netPlayerTimeout is written at :633 and read nowhere). Dropping inside those seconds leaves both on
-- his id, and no one else can then drive the pair: a driver is granted a car on Server only (:7505-7508,
-- VehicleEnterPacket.java:123-129). The Engine update (Battery.lua) frees such a car for the one driving it now.
if not isServer() then return end
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local TA = {}
T.TowAuth = TA

-- one car still held by an id no one online has: back to Server (authorizationChanged nil = Server, -1,
-- BaseVehicle.java:10175-10180)
local function back(v, head, what)
    local id = v:getNetPlayerId()
    if id == -1 or getPlayerByOnlineID(id) then return end
    T.log("towauth: " .. head:getScriptName() .. " #" .. head:getId() .. what .. " still on online id " .. id
        .. ", handed back to the server")
    v:authorizationChanged(nil)
end

-- a Tesla and what it tows
function TA.free(v)
    local t = v:getVehicleTowing()
    back(v, v, "")
    if t then back(t, v, " trailer #" .. t:getId()) end
end

-- every loaded Tesla. IsoCell.vehicles is a HashSet: iterator() (SemiHitch.lua has why).
function TA.handBack()
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        if T.isTesla(v) then TA.free(v) end
    end
end

Events.OnCreateLivingCharacter.Add(function(character)
    if not instanceof(character, "IsoAnimal") then TA.handBack() end
end)
