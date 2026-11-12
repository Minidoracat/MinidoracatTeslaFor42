-- Getting in through a door that has swung open (client/MinidoracatTesla/EnterDoor.lua): the climb after the open
-- action waits E.WAIT of door-anim time, or the car's own per-door time (Model X falcon wing doors: Specs doorWait);
-- six-seat cars: the rear doors' row order, and the seat panel's icons kept apart (ISVehicleSeatUI).
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
for _, m in ipairs({ "TimedActions/ISTimedActionQueue", "Vehicles/TimedActions/ISEnterVehicle", "Vehicles/TimedActions/ISExitVehicle",
    "Vehicles/ISUI/ISVehicleSeatUI" }) do
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
local X, Y, YL = "Base.MinidoracatTesla_ModelX", "Base.MinidoracatTesla_ModelY", "Base.MinidoracatTesla_ModelYL"
check(waitAfter(X, "DoorRearLeft") == T.Specs[X].doorWait.DoorRearLeft and waitAfter(X, "DoorRearRight") == T.Specs[X].doorWait.DoorRearRight,
    "Model X falcon wing door: the climb waits its own " .. tostring(T.Specs[X].doorWait.DoorRearLeft) .. " s")
check(waitAfter(X, "DoorRearLeft", ISExitVehicle) == T.Specs[X].doorWait.DoorRearLeft, "getting out through it waits the same")
check(waitAfter(X, "DoorFrontLeft") == E.WAIT, "Model X front door: E.WAIT (" .. E.WAIT .. " s)")
check(waitAfter(Y, "DoorRearLeft") == E.WAIT and T.Specs[Y].doorWait == nil, "Model Y rear door (no doorWait): E.WAIT")
check(waitAfter(YL, "DoorRearLeft") == E.WAIT and T.Specs[YL].doorWait == nil, "Model Y L rear door (ordinary, no doorWait): E.WAIT")

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

H.section("six-seat rear door E: 2nd row first, then the 3rd")
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
    local seats = script == Y and 4 or 6 -- Model Y: PassengerSeat4
    return { getMaxPassengers = function() return seats end, getScriptName = function() return script end,
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
check(e == nil and van == true, "Model Y rear door (four seats): vanilla")
check(useAt(car(YL, {}), "DoorRearLeft") == 4, "Model Y L rear door, all free: the 2nd row (MiddleLeft, seat 4)")
check(useAt(car(YL, { [4] = true }), "DoorRearLeft") == 2, "Model Y L rear door, 2nd row taken: the 3rd row (seat 2)")
check(useAt(car(YL, {}), "DoorRearRight") == 5, "Model Y L right rear door: MiddleRight (seat 5)")
e, van = useAt(car(YL, { [5] = true, [3] = true }), "DoorRearRight")
check(e == nil and van == true, "Model Y L right rear door, both rows taken: vanilla")
e, van = useAt(car(YL, {}), "DoorFrontLeft")
check(e == nil and van == true, "Model Y L front door: vanilla")
e, van = useAt(car("Base.CarNormal", {}), "DoorRearLeft")
check(e == nil and van == true, "a six-seat vanilla car: vanilla")

H.section("six-seat rear door gamepad Interact: the same seat as E")
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
check(prompt(car(Y, {}, "DoorRearLeft"), 2) == 2, "Model Y rear door (four seats): vanilla's seat")
check(prompt(car(YL, {}, "DoorRearLeft"), 2) == 4, "Model Y L rear door, all free: the 2nd row (seat 4)")
check(prompt(car(YL, { [4] = true }, "DoorRearLeft"), 2) == 2, "Model Y L rear door, 2nd row taken: the 3rd row (seat 2)")
check(prompt(car(YL, {}, "DoorRearRight"), 3) == 5, "Model Y L right rear door: MiddleRight (seat 5)")
Vehicles, ISVehicleMenu, ISButtonPrompt, getSpecificPlayer = savedV, savedMenu, savedPrompt, savedGSP

H.section("six-seat seat panel: no two seat icons overlap (ISVehicleSeatUI)")
-- the real script's extents z and each passenger's inside offset, in seat order (PassengerSeat6: Front*, Rear*, Middle*)
local function readSeats(file)
    local f = assert(io.open("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/scripts/vehicles/" .. file, "r"))
    local s = f:read("*a")
    f:close()
    local seats = {}
    for _, name in ipairs({ "FrontLeft", "FrontRight", "RearLeft", "RearRight", "MiddleLeft", "MiddleRight" }) do
        local at = s:find("passenger " .. name .. "%s")
        if at then
            local x, y, z = s:match("position inside%s*{%s*offset%s*=%s*(%S+)%s+(%S+)%s+([^,%s]+)", at)
            seats[#seats + 1] = { tonumber(x), tonumber(y), tonumber(z) }
        end
    end
    return tonumber(s:match("\n%s*extents%s*=%s*%S+%s+%S+%s+([^,%s]+)")), seats
end
local function seatCar(script, extZ, seats)
    local sc = { getExtents = function() return { z = function() return extZ end } end,
        getPassengerCount = function() return #seats end,
        getPassenger = function(_, i)
            local o = seats[i + 1]
            return { getPositionById = function(_, id)
                return id == "inside" and { getOffset = function() return { get = function(_, k) return o[k + 1] end } end } or nil
            end }
        end }
    return { getScriptName = function() return script end, getScript = function() return sc end,
        getMaxPassengers = function() return #seats end }
end
-- vanilla's icon corners (ISVehicleSeatUI.lua:206-246; the per-script SeatOffsetX/Y shift every icon alike, left out)
local function icons(ui, v)
    local sc, r = v:getScript(), {}
    local scale = ui.height * 0.7 / sc:getExtents():z()
    for s = 1, v:getMaxPassengers() do
        local o = sc:getPassenger(s - 1):getPositionById("inside"):getOffset()
        r[s] = { x = ui.width / 2 - o:get(0) * scale - 41 / 2, y = ui.height / 2 - o:get(2) * scale - 59 / 2 }
    end
    return r
end
-- the deepest overlap of any two icons, px (> 0: they overlap; the E2E modelx-sp SEATUI measure)
local function worst(r)
    local w = -math.huge
    for i = 1, #r do
        for j = i + 1, #r do w = math.max(w, math.min(41 - math.abs(r[i].x - r[j].x), 59 - math.abs(r[i].y - r[j].y))) end
    end
    return w
end
local function sign(d) return d > 1e-9 and 1 or d < -1e-9 and -1 or 0 end
-- every pair keeps its left/right and front/back
local function sameOrder(a, b)
    for i = 1, #a do
        for j = 1, #a do
            if sign(a[i].x - a[j].x) ~= sign(b[i].x - b[j].x) or sign(a[i].y - a[j].y) ~= sign(b[i].y - b[j].y) then return false end
        end
    end
    return true
end
local function samePlaces(a, b)
    for i = 1, #a do if not (H.near(a[i].x, b[i].x) and H.near(a[i].y, b[i].y)) then return false end end
    return #a == #b
end
local savedSeatUI = ISVehicleSeatUI
-- vanilla's (ISVehicleSeatUI.lua:497-511,529-538): 263 x 500, the gamepad moves two seats at a time
ISVehicleSeatUI = {
    setVehicle = function(self, v) self.vehicle, self.joypadSeat = v, 1 end,
    onJoypadDirUp = function(self) if self.joypadSeat > 2 then self.joypadSeat = self.joypadSeat - 2 end end,
    onJoypadDirDown = function(self)
        if self.joypadSeat <= self.vehicle:getScript():getPassengerCount() - 2 then self.joypadSeat = self.joypadSeat + 2 end
    end,
}
local function panel()
    return setmetatable({ width = 263, height = 500, setHeight = function(self, h) self.height = h end }, { __index = ISVehicleSeatUI })
end
local savedScreenH, screenH = getPlayerScreenHeight, 1080
function getPlayerScreenHeight() return screenH end
E.seatSetVehicle = nil
if E.wrapSeatUI then E.wrapSeatUI() end

local XZ, XS = readSeats("MinidoracatTesla_ModelX.txt")
check(#XS == 6 and XZ > 2, "Model X script: six inside offsets and extents z " .. tostring(XZ))
local function fixed(v)
    local ui = panel()
    local before = icons(ui, v)
    ui:setVehicle(v)
    return before, icons(ui, v), ui
end
local before, after, ui = fixed(seatCar(X, XZ, XS))
-- 5.9 since the 2026-11-12 round 2 body (SEAT third back 0.09; 6.7 at 0.08, E2E SEATUI measured 5.1 before the round 1 body);
-- 5.8 since round 9 (2026-11-13: the body 1.3 mm shorter, extents z 2.2955 -> 2.2949)
check(H.near(worst(before), 5.8, 0.1), string.format("Model X at vanilla's 500 px: the 2nd and 3rd rows overlap %.1f px (offline 5.8)", worst(before)))
check(worst(after) <= 0, string.format("Model X: no two icons overlap (worst %.2f px; panel %d px)", worst(after), ui.height))
check(sameOrder(before, after), "Model X: every icon keeps its left/right and front/back")
local gap = after[3].y - after[5].y -- 3rd row (RearLeft, seat 3) below the 2nd (MiddleLeft, seat 5)
check(gap >= 59 and gap < 60, string.format("Model X: the 2nd and 3rd rows just apart (%.2f px, icon 59)", gap))
check(ui.width == 263, "the panel keeps vanilla's width")
local inside = true
for _, r in ipairs(after) do inside = inside and r.x >= 0 and r.x + 41 <= ui.width and r.y >= 0 and r.y + 59 <= ui.height end
check(inside, "Model X: every icon inside the panel")

local YZ, YS = readSeats("MinidoracatTesla_ModelY.txt")
before, after, ui = fixed(seatCar(Y, YZ, YS))
check(#YS == 4 and ui.height == 500 and samePlaces(before, after), "Model Y (four seats): vanilla's panel and icon places")
before, after, ui = fixed(seatCar("Base.VanSeats", XZ, XS))
check(ui.height == 500 and samePlaces(before, after), "a vanilla six-seat car (Model X's seats): vanilla's panel and places")
ui = panel()
ui:setVehicle(seatCar(X, XZ, XS))
ui:setVehicle(seatCar(Y, YZ, YS))
check(ui.height == 500, "the player's one panel, a Model X then a Model Y: back to vanilla's 500 px")
screenH = 512
ui = panel()
ui:setVehicle(seatCar(X, XZ, XS))
check(ui.height == 512, "a 512 px split screen: the panel stops at the player's screen height")
screenH = 400
ui = panel()
ui:setVehicle(seatCar(X, XZ, XS))
check(ui.height == 500, "a screen shorter than vanilla's panel: vanilla's 500 px, never less")
screenH = 1080

local YLZ, YLS = readSeats("MinidoracatTesla_ModelYL.txt")
before, after, ui = fixed(seatCar(YL, YLZ, YLS))
check(#YLS == 6 and worst(after) <= 0 and sameOrder(before, after),
    string.format("Model Y L (its script now): %.1f px overlap at 500, none at %d (worst %.2f)", worst(before), ui.height, worst(after)))
-- rows closer than a Model X's: the 3rd row 0.47 tiles behind the 2nd (0.258 script units at the cars' model scale 1.82)
local close = {}
for i, o in ipairs(XS) do close[i] = { o[1], o[2], o[3] } end
close[3][3], close[4][3] = XS[5][3] - 0.47 / 1.82, XS[6][3] - 0.47 / 1.82
before, after, ui = fixed(seatCar(X, XZ, close))
check(worst(before) > 19 and worst(after) <= 0 and sameOrder(before, after),
    string.format("rows 0.47 tiles apart: %.1f px overlap at 500, none at %d (worst %.2f)", worst(before), ui.height, worst(after)))

-- gamepad up/down: the next row on screen on the same side; vanilla's two-at-a-time went front -> 3rd row -> 2nd row
local function pad(v, from, ...)
    local p = panel()
    p:setVehicle(v)
    p.joypadSeat = from
    for _, d in ipairs({ ... }) do if d == "down" then p:onJoypadDirDown() else p:onJoypadDirUp() end end
    return p.joypadSeat
end
local mx = seatCar(X, XZ, XS)
check(pad(mx, 1, "down") == 5 and pad(mx, 1, "down", "down") == 3 and pad(mx, 1, "down", "down", "down") == 3,
    "Model X pad down from seat 1: 5 (2nd row), 3 (3rd row), then stays")
check(pad(mx, 3, "up") == 5 and pad(mx, 3, "up", "up") == 1 and pad(mx, 3, "up", "up", "up") == 1,
    "Model X pad up from seat 3: 5, 1, then stays")
check(pad(mx, 2, "down") == 6 and pad(mx, 2, "down", "down") == 4 and pad(mx, 4, "up") == 6, "right side: 2 -> 6 -> 4 and back")
check(pad(seatCar(Y, YZ, YS), 1, "down") == 3, "Model Y (four seats): vanilla's 1 -> 3")
check(pad(seatCar("Base.VanSeats", XZ, XS), 1, "down") == 3, "a vanilla six-seat car: vanilla's 1 -> 3")
ISVehicleSeatUI = savedSeatUI
getPlayerScreenHeight = savedScreenH
