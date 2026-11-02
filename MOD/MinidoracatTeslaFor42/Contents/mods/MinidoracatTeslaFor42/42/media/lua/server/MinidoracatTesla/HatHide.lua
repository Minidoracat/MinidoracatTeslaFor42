-- Tall hats through a Tesla roof (user 2026-11-02: hide them while seated, over 10 mm out; bald under the Spiffo head
-- and the spiked full crash helmets accepted).
-- While a player sits in a Tesla seat whose roof the hat they wear leaves (TallHats.lua, from seat_head.py
-- --tall-lua), the server puts the hidden item MinidoracatTesla_HatHide on them. Its body location hides base:hat and
-- base:fullhat models (NPCs/MinidoracatTesla_BodyLocations.lua), on every client: setWornItem on the server sends
-- SyncClothing to everyone (IsoGameCharacter.java:3472-3478). The hat stays worn, so the hair and beard still follow
-- it: the hair style is the hat's alternate (PopTemplateManager.java:124-143, HairStyles.java:164-171), none under
-- the Spiffo head (hatCategory nohair) or the spiked full crash helmets (nohairnobeard: no beard either, :145-152).
-- When: the player's own client sends `seat` after entering, switching seats or exiting (client SeatPose.lua; the
-- server has no such event, Camp.lua), and on a server it looks again AGAIN_MS later: the command is RELIABLE, the exit
-- and seat switch RELIABLE_ORDERED (PacketTypes.java:510; VehicleExitPacket.java:17-23), so the command can be handled
-- while the seat is still the old one. Each time (MP) the clients near get the sender's online id, `seat` { id }, to
-- set that player's seated pose there and draw them from the seat (SeatPose.lua, RemoteSeat.lua; anim variables are
-- per client, no Lua event fires there either):
-- only the sender's own id, the command's arguments are never read; again AGAIN_MS later, for a client the relay
-- reached ahead of that player's vehicle packet. Death takes it off before the corpse copies the worn items
-- (OnCharacterDeath from DoDeath, IsoGameCharacter.java:2024-2025, before becomeCorpse :14640); and the EveryOneMinute
-- event checks every player again (a hat changed in the seat, a lost command, a login, a seat lost while away): the
-- online players on a server, the local ones in SP. AGENTS.md rule 2: events, a one-shot OnTick while a look-again is
-- due; per player a few getters, two table lookups and one inventory scan (getAllType), an item only when the state
-- flips (E2E seat-hat-sp / hat-mp `RECONCILE`).
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

-- off: take it off whatever the seat (death: the character may still read as seated and alive here). Leaves one
-- hider, worn, or none: an unworn copy goes too. A client's own SyncClothing sent before the hider reached it drops
-- the hider from the server's worn list and leaves it in the inventory (SyncClothingPacket.java:176-190, processServer
-- :230-231); the next sync wears that one again instead of adding another (review 2026-11-02).
function H.sync(player, off)
    if not player then return end
    local loc, inv = MinidoracatTeslaHatLoc, player:getInventory()
    local want = not off and H.wanted(player)
    local cur, all = player:getWornItem(loc), inv:getAllType(H.TYPE)
    local keep = want and (cur or (all:size() > 0 and all:get(0))) or nil
    local changed = false
    if cur and cur ~= keep then
        player:removeWornItem(cur, false)
        changed = true
    end
    for i = all:size() - 1, 0, -1 do
        local it = all:get(i)
        if it ~= keep then
            inv:Remove(it)
            if isServer() then sendRemoveItemFromContainer(inv, it) end
            changed = true
        end
    end
    if want and not keep then
        keep = inv:AddItem(H.TYPE)
        if isServer() then sendAddItemToContainer(inv, keep) end
    end
    if keep and keep ~= cur then
        player:setWornItem(loc, keep)
        changed = true
    end
    if changed then T.log("hatHide " .. tostring(player:getUsername()) .. " " .. (want and "on" or "off")) end
end

-- MP: the clients that can have this player's car loaded (Liftgate.sendNear: 96 tiles on both axes of the player, who
-- sits in or stands by it), but the sender's (it set its own pose): this player's online id, nothing from the client.
-- Liftgate is a shared file, loaded before any server one; looked up per call (the harness loads it later).
local function relay(player)
    T.Liftgate.sendNear(player, "seat", { id = player:getOnlineID() }, player)
end

-- look again AGAIN_MS after a command on a server (see the top): onlineID -> due ms, so a player gone by then is
-- skipped (getPlayerByOnlineID -> nil). The OnTick goes once none is due, as the horn's (Remote.lua).
H.AGAIN_MS = 1000
local again, pending = {}, 0 -- pending: how many ids `again` holds (next is not a Kahlua global, verify_mod)
local function againTick()
    local now, due = getTimestampMs(), {}
    for id, at in pairs(again) do
        if now >= at or at - now > H.AGAIN_MS then due[#due + 1] = id end -- the clock set back: now
    end
    for _, id in ipairs(due) do
        again[id] = nil
        pending = pending - 1
        local p = getPlayerByOnlineID(id)
        if p then relay(p) end
        H.sync(p, false)
    end
    if pending == 0 then Events.OnTick.Remove(againTick) end
end

T.ServerCommands = T.ServerCommands or {}
T.ServerCommands.seat = function(player)
    if isServer() then
        local id = player:getOnlineID()
        if not again[id] then
            if pending == 0 then Events.OnTick.Add(againTick) end
            pending = pending + 1
        end
        again[id] = getTimestampMs() + H.AGAIN_MS
        relay(player)
    end
    H.sync(player, false)
end

function H.minute()
    if isServer() then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do H.sync(list:get(i), false) end
    else
        for i = 0, getNumActivePlayers() - 1 do H.sync(getSpecificPlayer(i), false) end
    end
end
function H.onDeath(chr)
    if instanceof(chr, "IsoPlayer") then H.sync(chr, true) end
end
Events.EveryOneMinute.Add(H.minute)
Events.OnCharacterDeath.Add(H.onDeath)
