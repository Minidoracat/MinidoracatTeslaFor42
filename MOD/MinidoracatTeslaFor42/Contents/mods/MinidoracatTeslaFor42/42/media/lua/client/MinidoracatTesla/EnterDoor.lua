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
require "Vehicles/ISUI/ISVehicleSeatUI"

local T = MinidoracatTesla
local E = {}
T.EnterDoor = E

-- clip seconds into the door's opening swing (T.clipStep's clock) the climb starts at: 0.44 of a 0.8 s clip, the door
-- most of the way open (E2E enter-sp; modelx-sp CLIMB)
E.WAIT = 0.44
local CLIMB = { ISEnterVehicle = true, ISExitVehicle = true }

-- looked up when the open action ends, not when it starts: getting out queues the open action into an empty queue,
-- which starts it at once (ISTimedActionQueue:addToQueue), before onExitAux has queued the climb
local perform = ISOpenVehicleDoor.perform
function ISOpenVehicleDoor:perform(...)
    if self.vehicle and T.isTesla(self.vehicle) then
        local queue = ISTimedActionQueue.getTimedActionQueue(self.character)
        local i = queue:indexOf(self)
        local nxt = i > 0 and queue.queue[i + 1]
        -- a door of its own pace (Model X falcon wing doors: Core.lua Specs doorWait), else E.WAIT
        local waits = T.spec(self.vehicle).doorWait
        if nxt and CLIMB[nxt.Type] then nxt.teslaDoorWait = waits and waits[self.part:getId()] or E.WAIT end
    end
    return perform(self, ...)
end

-- true while the door is still swinging; counted on the part anims' clock (T.clipStep)
local function swinging(self)
    local left = self.teslaDoorWait
    if not left then return false end
    left = left - T.clipStep()
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

-- Six-seat cars (Model X, Model Y L): E on a door takes the first seat that door serves (Vehicles.Use.Door,
-- Vehicles.lua:816-827), and so does the gamepad's Interact prompt (ISButtonPrompt.lua:572-589, cmdEnterVehicle);
-- PassengerSeat6 loads Rear* (3rd row) before Middle* (template_passenger.txt), so both sat in the 3rd row, and did
-- nothing once it was taken. At a rear door (a Model X's falcon wing, a Model Y L's ordinary door): the free 2nd-row
-- seat, then the 3rd row's, else vanilla's. Four-seat cars keep vanilla's. Free = installed and nobody (no load) in
-- it: isSeatOccupied only sees people and items, the seat part may be gone (BaseVehicle.java:2232-2239), and vanilla
-- refuses a missing seat (ISVehicleMenu.lua:1432-1436). The seat panel (ISVehicleSeatUI) calls ISVehicleMenu.onEnter
-- itself: a seat picked there stays as picked.
local ROWS = { DoorRearLeft = { "MiddleLeft", "RearLeft" }, DoorRearRight = { "MiddleRight", "RearRight" } }
function E.rowSeat(vehicle, part)
    local rows = part and ROWS[part:getId()]
    if not (rows and T.isTesla(vehicle) and vehicle:getMaxPassengers() > 4) then return nil end
    local script = vehicle:getScript()
    for _, name in ipairs(rows) do
        for seat = 0, vehicle:getMaxPassengers() - 1 do
            if script:getPassenger(seat):getId() == name and vehicle:isSeatInstalled(seat)
                and not vehicle:isSeatOccupied(seat) then return seat end
        end
    end
end

function E.wrapDoorUse()
    if E.doorUse or not (Vehicles and Vehicles.Use and Vehicles.Use.Door) then return end
    local use = Vehicles.Use.Door
    E.doorUse = use
    Vehicles.Use.Door = function(vehicle, part, chr)
        local seat = E.rowSeat(vehicle, part)
        if seat then return ISVehicleMenu.onEnter(chr, vehicle, seat) end
        return use(vehicle, part, chr)
    end
    -- the prompt is rebuilt every update with self.cmdEnterVehicle (a class method); its other caller, the no-door
    -- getBestSeat branch (ISButtonPrompt.lua:603-605), has no useable part, so it keeps vanilla's seat
    local enter = ISButtonPrompt.cmdEnterVehicle
    ISButtonPrompt.cmdEnterVehicle = function(self, vehicle, seat)
        local part = vehicle:getUseablePart(getSpecificPlayer(self.player))
        return enter(self, vehicle, E.rowSeat(vehicle, part) or seat)
    end
end
Events.OnGameStart.Add(E.wrapDoorUse)

-- Six-seat cars' seat panel (ISVehicleSeatUI): vanilla draws each seat as a 41 x 59 px icon at its inside offset, x from
-- offset x and y from offset z at 0.7 x panel height / extents z px a unit, on a 263 x 500 panel (ISVehicleSeatUI.lua:
-- 206-243,581-584); mouse hits and the gamepad's highlight use the same x, y (:248-250). A Model X's 2nd and 3rd rows
-- are 0.354 apart, 54 px, so their icons overlapped 5 px (E2E modelx-sp SEATUI); vanilla's only per-car knobs,
-- SeatOffsetX/Y (:13-59), move every icon alike. Here: when the panel gets a six-seat Tesla (setVehicle, once a showing,
-- ISVehicleMenu.lua:1634) it is made just tall enough that no two icons overlap; the scale grows with it, so every icon
-- keeps its side and row. Any other car gets the panel's own height back (one panel a player, reused). The panel
-- recentres itself every update (:400-402).
local ICON_W, ICON_H = 41, 59
-- a six-seat Tesla's inside offsets by seat (1-based; nil where vanilla draws no icon) and its seat count, else nil
local function sixSeats(vehicle)
    if not (vehicle and T.isTesla(vehicle) and vehicle:getMaxPassengers() > 4) then return nil end
    local script, offs, n = vehicle:getScript(), {}, vehicle:getMaxPassengers()
    for s = 1, n do
        local pos = script:getPassenger(s - 1):getPositionById("inside")
        offs[s] = pos and pos:getOffset() or nil
    end
    return offs, n
end

function E.seatPanelHeight(vehicle, base)
    local offs, n = sixSeats(vehicle)
    if not offs then return base end
    local need = 0 -- px a unit at which every two icons sit apart, across or along
    for i = 1, n do
        for j = i + 1, n do
            local a, b = offs[i], offs[j]
            if a and b then
                local dx, dz = math.abs(a:get(0) - b:get(0)), math.abs(a:get(2) - b:get(2))
                local s = dz > 0 and ICON_H / dz or nil
                if dx > 0 and (not s or ICON_W / dx < s) then s = ICON_W / dx end
                if s and s > need then need = s end
            end
        end
    end
    -- floor + 1: strictly over, so float rounding never leaves a hair of overlap
    return math.max(base, math.floor(need * vehicle:getScript():getExtents():z() / 0.7) + 1)
end

-- gamepad up/down: vanilla moves two seats at a time (:497-511), which on PassengerSeat6 (Rear* load before Middle*)
-- went front -> 3rd row -> 2nd row. Here: the nearest row up (larger z, higher on the panel) or down, same side;
-- none: stays. nil: not a six-seat Tesla (vanilla's).
function E.padRowSeat(vehicle, from, up)
    local offs, n = sixSeats(vehicle)
    local o = offs and offs[from]
    if not o then return nil end
    local best, bestD
    for s = 1, n do
        local q = offs[s]
        local d = q and (q:get(2) - o:get(2)) * (up and 1 or -1)
        if d and d > 0 and (q:get(0) > 0) == (o:get(0) > 0) and (not best or d < bestD) then best, bestD = s, d end
    end
    return best or from
end

function E.wrapSeatUI()
    if E.seatSetVehicle or not ISVehicleSeatUI then return end
    local set, up, down = ISVehicleSeatUI.setVehicle, ISVehicleSeatUI.onJoypadDirUp, ISVehicleSeatUI.onJoypadDirDown
    E.seatSetVehicle = set
    ISVehicleSeatUI.setVehicle = function(self, vehicle, ...)
        set(self, vehicle, ...)
        self.teslaBaseHeight = self.teslaBaseHeight or self.height
        local h = E.seatPanelHeight(vehicle, self.teslaBaseHeight)
        if h ~= self.height then self:setHeight(h) end
    end
    ISVehicleSeatUI.onJoypadDirUp = function(self, ...)
        local s = E.padRowSeat(self.vehicle, self.joypadSeat, true)
        if not s then return up(self, ...) end
        self.joypadSeat = s
    end
    ISVehicleSeatUI.onJoypadDirDown = function(self, ...)
        local s = E.padRowSeat(self.vehicle, self.joypadSeat, false)
        if not s then return down(self, ...) end
        self.joypadSeat = s
    end
end
E.wrapSeatUI()

return E
