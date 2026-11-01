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

-- the wait counts on the door's clip clock (T.clipStep): updates until the climb may start at multiplier m
local function climbUpdates(script, door, m)
    local nxt = setmetatable({}, { __index = ISEnterVehicle })
    local v = H.vehicle({ script = script })
    q.queue = { setmetatable({ vehicle = v, part = { getId = function() return door end } }, { __index = ISOpenVehicleDoor }), nxt }
    q.queue[1]:perform()
    H.removeVehicle(v)
    H.setMultiplier(m)
    local n = 0
    repeat n = n + 1 until not nxt:waitToStart() or n > 1000
    H.setMultiplier(1)
    return n
end
-- before 2026-11-01 the wait was 0.55 (E.WAIT) or 2.3 (falcon) less m/60 an update. The multiplier is frame time x 60
-- x the game speed (GameTime.java:1018-1022), never a round 1 in play (at exactly 1 both counts end on a float crumb)
local function oldUpdates(w, m) local n = 0; repeat n = n + 1; w = w - m / 60 until w <= 0; return n end
for _, m in ipairs({ 0.97, 1.03, 2.01, 5.02, 40.1 }) do
    check(climbUpdates(X, "DoorFrontLeft", m) == oldUpdates(0.55, m) and climbUpdates(X, "DoorRearLeft", m) == oldUpdates(2.3, m),
        string.format("multiplier %.2f: the climb starts on the same update as the old count (front %d, falcon %d)",
            m, climbUpdates(X, "DoorFrontLeft", m), climbUpdates(X, "DoorRearLeft", m)))
end
-- fast forward: the climb starts the update the clip passes the wait
local step40 = 0.8 / 60 * 40
local n40 = climbUpdates(X, "DoorRearLeft", 40)
check((n40 - 1) * step40 < T.Specs[X].doorWait.DoorRearLeft and n40 * step40 >= T.Specs[X].doorWait.DoorRearLeft,
    string.format("multiplier 40: the falcon climb starts at clip %.2f s, the update it passes %.2f", n40 * step40,
        T.Specs[X].doorWait.DoorRearLeft))
check(climbUpdates(X, "DoorFrontLeft", 0) > 1000, "paused (multiplier 0): the climb keeps waiting")

ISOpenVehicleDoor.perform, ISTimedActionQueue, ISEnterVehicle, ISExitVehicle = saved.perform, saved.queue, saved.enter, saved.exit

H.section("falcon wing E: 2nd row first, then the 3rd")
local savedV, savedMenu, savedPrompt, savedGSP = Vehicles, ISVehicleMenu, ISButtonPrompt, getSpecificPlayer
local entered, vanilla, prompted
Vehicles = { Use = { Door = function() vanilla = true end } }
ISVehicleMenu = { onEnter = function(_, _, seat) entered = seat end }
ISButtonPrompt = { cmdEnterVehicle = function(_, _, seat) prompted = seat end }
E.doorUse = nil
E.wrapDoorUse()
local NAMES = { [0] = "FrontLeft", "FrontRight", "RearLeft", "RearRight", "MiddleLeft", "MiddleRight" } -- PassengerSeat6 order
-- taken[i]: true = someone (or a load) in seat i, "gone" = the seat part removed (isSeatInstalled false)
local function car(script, taken, useable)
    return { getMaxPassengers = function() return 6 end, getScriptName = function() return script end,
        getScript = function() return { getPassenger = function(_, i) return { getId = function() return NAMES[i] end } end } end,
        isSeatOccupied = function(_, i) return taken[i] == true end,
        isSeatInstalled = function(_, i) return taken[i] ~= "gone" end,
        getUseablePart = function() return useable and { getId = function() return useable end } end }
end
local function useAt(v, door)
    entered, vanilla = nil, nil
    Vehicles.Use.Door(v, { getId = function() return door end }, {})
    return entered, vanilla
end
check(useAt(car(X, {}), "DoorRearLeft") == 4, "left wing, all free: the 2nd row (MiddleLeft, seat 4)")
check(useAt(car(X, { [4] = true }), "DoorRearLeft") == 2, "left wing, 2nd row taken: the 3rd row (RearLeft, seat 2)")
check(useAt(car(X, {}), "DoorRearRight") == 5, "right wing: MiddleRight (seat 5)")
check(useAt(car(X, { [4] = "gone" }), "DoorRearLeft") == 2, "left wing, 2nd-row seat removed: the 3rd row (seat 2)")
local e, van = useAt(car(X, { [5] = true, [3] = true }), "DoorRearRight")
check(e == nil and van == true, "right wing, both rows taken: vanilla (it says the seat is taken)")
e, van = useAt(car(X, {}), "DoorFrontLeft")
check(e == nil and van == true, "Model X front door: vanilla")
e, van = useAt(car(Y, {}), "DoorRearLeft")
check(e == nil and van == true, "Model Y rear door: vanilla")

H.section("falcon wing gamepad Interact: the same seat as E")
-- ISButtonPrompt binds self.cmdEnterVehicle(vehicle, seat) with the first seat the door serves (Rear* at a falcon wing:
-- seat 2 left, 3 right), or getBestSeat when no door part is useable
getSpecificPlayer = function() return {} end
local function prompt(v, seat)
    prompted = nil
    ISButtonPrompt.cmdEnterVehicle({ player = 0 }, v, seat)
    return prompted
end
check(prompt(car(X, {}, "DoorRearLeft"), 2) == 4, "left wing, all free: the 2nd row (seat 4), not vanilla's 3rd row")
check(prompt(car(X, { [4] = true }, "DoorRearLeft"), 2) == 2, "left wing, 2nd row taken: the 3rd row (seat 2)")
check(prompt(car(X, {}, "DoorRearRight"), 3) == 5, "right wing: MiddleRight (seat 5)")
check(prompt(car(X, { [5] = true, [3] = true }, "DoorRearRight"), 3) == 3, "right wing, both rows taken: vanilla's seat")
check(prompt(car(X, { [5] = "gone" }, "DoorRearRight"), 3) == 3, "right wing, 2nd-row seat removed: the 3rd row (seat 3)")
check(prompt(car(X, { [4] = "gone", [2] = "gone" }, "DoorRearLeft"), 2) == 2, "left wing, both seats removed: vanilla's seat")
check(prompt(car(X, {}, "DoorFrontLeft"), 0) == 0, "Model X front door: vanilla's seat")
check(prompt(car(X, {}, nil), 2) == 2, "no useable door (getBestSeat branch): vanilla's seat")
check(prompt(car(Y, {}, "DoorRearLeft"), 2) == 2, "Model Y rear door: vanilla's seat")
Vehicles, ISVehicleMenu, ISButtonPrompt, getSpecificPlayer = savedV, savedMenu, savedPrompt, savedGSP

