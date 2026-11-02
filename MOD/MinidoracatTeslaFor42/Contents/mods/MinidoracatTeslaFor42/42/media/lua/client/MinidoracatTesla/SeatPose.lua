-- The seated pose in a Tesla (references/seating.md). Three anim variables pick this MOD's player-vehicle nodes:
-- - MinidoracatTeslaSeated (every Tesla seat): idle plays the car's MinidoracatTesla_IdleDrivingRear_<model>, vanilla's
--   Bob_IdleDriving with the thighs raised 30 deg and the knees bent 40 deg more (scripts/seat_anim.py), so rear-row
--   feet reach the floor of the lower seats without reaching into the front seats; aiming keeps it too. In a car the
--   "aim" variable follows the aim key even with the window shut (IsoPlayer.java:4412-4446, IsoGameCharacter.java:976)
--   and vanilla's aim nodes play standing clips: through the glass the character stood up through the roof.
-- - MinidoracatTeslaRecline (the two front seats): idle and aim play MinidoracatTesla_IdleDrivingRecline_<model>,
--   Bob_IdleDriving leaned back 25 deg with the thighs lowered 10 deg, so the head clears the low roof.
-- - MinidoracatTeslaCar (every Tesla seat): the car's model (Core.lua Specs), the node's other condition. Each car's
--   clips lift the body by how much its script lowers the seat points to the depth reference (seat_anim.py DROP).
--   AnimSets/player-vehicle/idle/MinidoracatTesla_idle_recline_<model>.xml (priority 2) and _idle_rear_<model>.xml
--   (1), aim/MinidoracatTesla_aim_recline_<model>.xml (2) and _aim_seated_<model>.xml (1): the first match wins.
-- Anim variables live on each client's copy of a character, so every client sets them:
-- - the local player at once on every enter (ISEnterVehicle:perform, a saved seat on load IsoCell.java:4524-4525, MP
--   seat sync BaseVehicle.java:2527-2530), seat switch (ISSwitchVehicleSeat:perform, ISSwitchVehicleSeat.lua:57) and
--   exit (ISExitVehicle:perform, teleport IsoGameCharacter.java:16722-16727, TeleportPacket.java:63-66). A respawned
--   character is a new IsoPlayer.
-- - other players once a game minute (MP client): no Lua event fires here when they get in, switch or get out
--   (enterRSync triggers OnEnterVehicle for local players only, BaseVehicle.java:2527).
--   ponytail: another player shows the vanilla upright pose (head through a low roof) for up to one game minute after
--   getting in or switching: a game day's real length / 1440, 2.5 s at the default 1-hour day (sandbox Day Length;
--   10 s at 4 hours); an event from the server when someone gets in, switches or gets out if that ever shows.
require "MinidoracatTesla/Core"
require "Vehicles/ISUI/ISVehicleDashboard" -- registers OnExitVehicle and OnSwitchVehicleSeat (ISVehicleDashboard.lua:715-716)

local T = MinidoracatTesla
local SEATED, RECLINE, CAR = "MinidoracatTeslaSeated", "MinidoracatTeslaRecline", "MinidoracatTeslaCar"

local function set(player, name, on)
    if on then player:setVariable(name, true) else player:clearVariable(name) end
end

local function sync(player)
    if not player then return end
    local v = player:getVehicle()
    local tesla = v and T.isTesla(v)
    set(player, SEATED, tesla)
    set(player, RECLINE, tesla and v:getSeat(player) <= 1)
    if tesla then player:setVariable(CAR, T.spec(v).model) else player:clearVariable(CAR) end
end

-- the local player's own enter / switch / exit also asks the server to put on or take off the hat hider (HatHide.lua):
-- in a Tesla, out of one (the hider's SyncClothing may not have reached this client yet: review 2026-11-02), or
-- wearing it; a vanilla car sends nothing. inTesla: per split-screen player, set at each enter / switch / exit.
local inTesla = {}
local function seat(player)
    sync(player)
    if not (player and player:isLocalPlayer()) then return end
    local v, n = player:getVehicle(), player:getPlayerNum()
    local tesla = v and T.isTesla(v) or false
    if tesla or inTesla[n] or player:getWornItem(MinidoracatTeslaHatLoc) then
        sendClientCommand(player, T.MODULE, "hatHide", {})
    end
    inTesla[n] = tesla
end
Events.OnEnterVehicle.Add(seat)
Events.OnExitVehicle.Add(seat)
Events.OnSwitchVehicleSeat.Add(seat)
Events.EveryOneMinute.Add(function()
    if not isClient() then return end
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do sync(list:get(i)) end
end)
