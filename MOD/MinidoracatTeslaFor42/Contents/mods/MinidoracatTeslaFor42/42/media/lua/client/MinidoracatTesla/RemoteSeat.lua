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
-- drawn (GameWindow.java:687-702); their next update puts them on the centre again (IsoPlayer.java:6674-6687, the
-- network target and forceX from the car). Until then whatever reads their x, y sees the seat, as when the car
-- updates last: the next frame's CombatManager.update before the world update (GameWindow.java:360-363), VoiceManager
-- after it (:375), their sound emitter (IsoGameCharacter.java:1546-1556) and the objects updated before them. Left as
-- postupdate set them: the square, its moving objects and collision (IsoMovingObject.java:1004-1019), so the model is
-- lit from the centre's square as before this fix (ModelInstance.java:606-624); setting the square too would move
-- them between two squares every frame (postupdate starts with last = current, IsoMovingObject.java:848).
-- Watched: SeatPose.lua calls R.watch for the online id the server relays when that player gets in, switches or gets
-- out (`seat`, now and 1 s later) and for every remote player in a Tesla once a game minute (a car or player that just
-- loaded, a lost command). Dropped once out of a Tesla and GRACE_MS past the last of those (the relay can come before
-- the vehicle packet), or at once when the clock was set back past it.
-- AGENTS.md rule 2 exception (approved by the user 2026-11-02): the OnTick is there only while someone is watched, and
-- removed when nobody is. Per watched player and frame: an id lookup, the vehicle, isTesla, getSeat,
-- getPassengerWorldPos and three setters (E2E seat-remote-mp prof=1: 0.026 ms a frame).
require "MinidoracatTesla/Core"

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
        elseif now > keep or keep - now > R.GRACE_MS then -- the clock set back: now (as HatHide.lua's againTick)
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

return R
