-- Getting in and out of a Tesla: climb through the door once it has swung open.
-- Vanilla queues walk to the seat -> ISOpenVehicleDoor -> ISEnterVehicle -> ISCloseVehicleDoor (getting out:
-- ISOpenVehicleDoor -> ISExitVehicle -> ISCloseVehicleDoor; ISVehicleMenu.lua:1454-1481,1591-1606). The open action
-- starts the door's Open anim and ends about 5 ticks later (setTime(5), ISOpenVehicleDoor.lua:28-42), so the climb
-- starts right away. Vanilla doors open in about 0.3 s (SportsCar: rate 2.0); a Tesla door swings for about 1 s
-- (models.md 9; every car's side doors are 0.8 s clips, scripts/blender/skf/cars/<car>.py DOORS), so the character
-- went through a door barely ajar (E2E enter-sp).
-- Here: when the open action is followed by the climb, the climb waits (its waitToStart, vanilla's own hook, called only
-- while that action waits in the queue) until the door is most of the way open. The rest of the queue is unchanged.
require "TimedActions/ISTimedActionQueue"
require "Vehicles/TimedActions/ISEnterVehicle"
require "Vehicles/TimedActions/ISExitVehicle"
require "Vehicles/TimedActions/ISOpenVehicleDoor"

local T = MinidoracatTesla
local E = {}
T.EnterDoor = E

-- seconds of door-anim time the climb waits after the open action: with its ~5 ticks the door has run ~0.63 s of
-- its ~1 s swing, about 70% of the angle (eased clip)
E.WAIT = 0.55
local CLIMB = { ISEnterVehicle = true, ISExitVehicle = true }

-- looked up when the open action ends, not when it starts: getting out queues the open action into an empty queue,
-- which starts it at once (ISTimedActionQueue:addToQueue), before onExitAux has queued the climb
local perform = ISOpenVehicleDoor.perform
function ISOpenVehicleDoor:perform(...)
    if self.vehicle and T.isTesla(self.vehicle) then
        local queue = ISTimedActionQueue.getTimedActionQueue(self.character)
        local i = queue:indexOf(self)
        local nxt = i > 0 and queue.queue[i + 1]
        if nxt and CLIMB[nxt.Type] then nxt.teslaDoorWait = E.WAIT end
    end
    return perform(self, ...)
end

-- true while the door is still swinging; time as the part anims count it (BaseVehicle.java:3898-3903)
local function swinging(self)
    local left = self.teslaDoorWait
    if not left then return false end
    left = left - getGameTime():getUnmoddedMultiplier() / 60
    if left > 0 then
        self.teslaDoorWait = left
        return true
    end
    self.teslaDoorWait = nil
    return false
end

for _, cls in ipairs({ ISEnterVehicle, ISExitVehicle }) do
    local orig = cls.waitToStart -- ISEnterVehicle's own; ISExitVehicle inherits ISBaseTimedAction's (false)
    cls.waitToStart = function(self)
        if swinging(self) then return true end
        return orig(self)
    end
end

return E
