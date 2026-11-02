-- Another player seated in a Tesla is drawn from its seat, as the local player is (references/seating.md).
-- Why: every update a remote passenger's x, y go to the car centre (IsoPlayer.updateRemotePlayerInVehicle,
-- IsoPlayer.java:6674-6687, from updateRemotePlayer :6739-6741) and the car's update puts them on the seat
-- (BaseVehicle.java:3487-3494). Both run in MovingObjectUpdateScheduler's FULL bucket in IsoCell.objectList order, a
-- HashSet of identity hashes (IsoCell.java:130, MovingObjectUpdateScheduler.java:38-50,
-- MovingObjectUpdateSchedulerUpdateBucket.java:36-52): whichever comes last wins, the same for a player and a car
-- until the set resizes, different for the next car. The model is placed at the seat either way
-- (ModelSlotRenderData.java:314-327), but its depth comes from x, y (:126-128,226-233): at the centre a front seat
-- sinks into its own seat back, a rear one is drawn over the front seats (E2E seat-remote-mp `RENDERPOS`/`ORDER`).
-- Fix: one OnTick puts each watched passenger back on the seat the way BaseVehicle.update does. OnTick fires after
-- the world update and its postupdate (IngameState.java:1536,1654; IsoWorld.java:2949-2961) and before the frame is
-- drawn (GameWindow.java:687-702), and the next update moves them to the centre again first thing, so only the
-- drawing sees it: the network target and forceX come from the car (IsoPlayer.java:6674-6687), the square, collision
-- and light square were set in postupdate before (IsoMovingObject.java:816-1020).
-- Watched: an online id the server relays when that player gets in, switches or gets out (`seat`, SeatPose.lua; now
-- and 1 s later), and every remote player in a Tesla once a game minute (a car or player that just loaded, a lost
-- command). Dropped once out of a Tesla for GRACE_MS (the relay can come before the vehicle packet).
-- AGENTS.md rule 2 exception (pending the user's approval): the OnTick is there only while someone is watched, and
-- removed when nobody is; per watched player one lookup, three getters and three setters.
require "MinidoracatTesla/Core"
require "MinidoracatTesla/SeatPose" -- its `seat` handler first, wrapped below

local T = MinidoracatTesla
local R = { GRACE_MS = 2000, stats = { tickAdds = 0, tickRemoves = 0 } }
T.RemoteSeat = R

local watched, n = {}, 0 -- online id -> keep until (ms) while not in a Tesla
local drop = {}
local pos

local tick
tick = function()
    local now = getTimestampMs()
    for id, keep in pairs(watched) do
        local p = getPlayerByOnlineID(id)
        local v = p and p:getVehicle()
        local seat = v and T.isTesla(v) and v:getSeat(p) or -1
        if seat >= 0 then
            pos = v:getPassengerWorldPos(seat, pos or Vector3f.new()) -- BaseVehicle.java:1913-1916
            p:setX(pos:x())
            p:setY(pos:y())
            p:setZ(pos:z())
        elseif now > keep then
            drop[#drop + 1] = id
        end
    end
    for i = #drop, 1, -1 do
        watched[drop[i]] = nil
        drop[i] = nil
        n = n - 1
    end
    if n == 0 then
        Events.OnTick.Remove(tick)
        R.stats.tickRemoves = R.stats.tickRemoves + 1
    end
end

function R.watch(id)
    if not watched[id] then
        n = n + 1
        if n == 1 then
            Events.OnTick.Add(tick)
            R.stats.tickAdds = R.stats.tickAdds + 1
        end
    end
    watched[id] = getTimestampMs() + R.GRACE_MS
end

function R.count() return n end

T.ClientCommands = T.ClientCommands or {}
local relayed = T.ClientCommands.seat
T.ClientCommands.seat = function(args)
    if relayed then relayed(args) end
    if type(args.id) == "number" then R.watch(args.id) end
end

Events.EveryOneMinute.Add(function()
    if not isClient() then return end
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        local v = p:getVehicle()
        if v and not p:isLocalPlayer() and T.isTesla(v) then R.watch(p:getOnlineID()) end
    end
end)

return R
