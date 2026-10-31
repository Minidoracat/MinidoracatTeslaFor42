-- Getting in through a door that has swung open (client/MinidoracatTesla/EnterDoor.lua): the climb after the open
-- action waits E.WAIT of door-anim time, or the car's own per-door time (Model X falcon wing doors: Specs doorWait).
local T = MinidoracatTesla
local check = H.check

H.section("enter door wait")
local saved = { perform = ISOpenVehicleDoor.perform, queue = ISTimedActionQueue, enter = ISEnterVehicle, exit = ISExitVehicle }
ISOpenVehicleDoor.perform = function() end
ISEnterVehicle = { Type = "ISEnterVehicle", waitToStart = function() return false end }
ISExitVehicle = { Type = "ISExitVehicle", waitToStart = function() return false end }
local q = { queue = {} }
function q:indexOf(a) for i, b in ipairs(self.queue) do if b == a then return i end end return -1 end
ISTimedActionQueue = { getTimedActionQueue = function() return q end }
for _, m in ipairs({ "TimedActions/ISTimedActionQueue", "Vehicles/TimedActions/ISEnterVehicle", "Vehicles/TimedActions/ISExitVehicle" }) do
    H.stub(m)
end
local E = assert(loadfile("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/client/MinidoracatTesla/EnterDoor.lua"))()

-- the wait the climb gets after opening `door` on `script`
local function waitAfter(script, door, climb)
    local v = H.vehicle({ script = script })
    local open = setmetatable({ vehicle = v, part = { getId = function() return door end } }, { __index = ISOpenVehicleDoor })
    local nxt = setmetatable({}, { __index = climb or ISEnterVehicle })
    q.queue = { open, nxt }
    open:perform()
    H.removeVehicle(v)
    return nxt.teslaDoorWait
end
local X, Y = "Base.MinidoracatTesla_ModelX", "Base.MinidoracatTesla_ModelY"
check(waitAfter(X, "DoorRearLeft") == T.Specs[X].doorWait.DoorRearLeft and waitAfter(X, "DoorRearRight") == T.Specs[X].doorWait.DoorRearRight,
    "Model X falcon wing door: the climb waits its own " .. tostring(T.Specs[X].doorWait.DoorRearLeft) .. " s")
check(waitAfter(X, "DoorRearLeft", ISExitVehicle) == T.Specs[X].doorWait.DoorRearLeft, "getting out through it waits the same")
check(waitAfter(X, "DoorFrontLeft") == E.WAIT, "Model X front door: E.WAIT (" .. E.WAIT .. " s)")
check(waitAfter(Y, "DoorRearLeft") == E.WAIT and T.Specs[Y].doorWait == nil, "Model Y rear door (no doorWait): E.WAIT")

ISOpenVehicleDoor.perform, ISTimedActionQueue, ISEnterVehicle, ISExitVehicle = saved.perform, saved.queue, saved.enter, saved.exit
