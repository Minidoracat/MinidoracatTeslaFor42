-- Tall hats through a Tesla roof (prototype, temp/report-hat-1102): while a player sits in a Tesla seat whose roof the
-- hat they wear leaves (TallHats.lua, from seat_head.py), the server puts the hidden item MinidoracatTesla_HatHide on
-- them. Its body location hides base:hat and base:fullhat models (NPCs/MinidoracatTesla_BodyLocations.lua), on every
-- client: setWornItem on the server sends SyncClothing to everyone (IsoGameCharacter.java:3472-3478).
-- When: the player's own client asks after entering, switching seats or exiting (client SeatPose.lua; the server has
-- no such event, Camp.lua), death takes it off before the corpse copies the worn items (OnCharacterDeath from
-- DoDeath, IsoGameCharacter.java:2024-2025, before becomeCorpse :14640), and every game minute each player is checked
-- again (a lost command, a hat changed in the seat, a login, a seat lost while away).
if isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/TallHats"

local T = MinidoracatTesla
local H = {}
T.HatHide = H
H.TYPE = "Base.MinidoracatTesla_HatHide"
local HATS = { ItemBodyLocation.HAT, ItemBodyLocation.FULL_HAT }

-- does a hat this player wears leave the roof of the Tesla seat they sit in
function H.wanted(player)
    local v = not player:isDead() and player:getVehicle()
    local spec = v and T.spec(v)
    local seat = spec and v:getSeat(player) or -1
    local p = seat >= 0 and v:getScript():getPassenger(seat)
    local tall = p and T.TallHats[spec.model .. "/" .. p:getId()]
    if not tall then return false end
    for _, loc in ipairs(HATS) do
        local hat = player:getWornItem(loc)
        if hat and tall[hat:getClothingItemName()] then return true end
    end
    return false
end

-- off: take it off whatever the seat (death: the character may still read as seated and alive here)
function H.sync(player, off)
    if not player then return end
    local loc, inv = MinidoracatTeslaHatLoc, player:getInventory()
    local cur, want = player:getWornItem(loc), not off and H.wanted(player)
    if want == (cur ~= nil) then return end
    if want then
        local item = inv:AddItem(H.TYPE)
        if isServer() then sendAddItemToContainer(inv, item) end
        player:setWornItem(loc, item)
    else
        player:removeWornItem(cur, false)
        inv:Remove(cur)
        if isServer() then sendRemoveItemFromContainer(inv, cur) end
    end
    T.log("hatHide " .. tostring(player:getUsername()) .. " " .. (want and "on" or "off"))
end

T.ServerCommands = T.ServerCommands or {}
T.ServerCommands.hatHide = function(player) H.sync(player) end

local function each(fn)
    if isServer() then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do fn(list:get(i)) end
    else
        for i = 0, getNumActivePlayers() - 1 do fn(getSpecificPlayer(i)) end
    end
end
Events.EveryOneMinute.Add(function() each(H.sync) end)
Events.OnCharacterDeath.Add(function(chr)
    if instanceof(chr, "IsoPlayer") then H.sync(chr, true) end
end)
