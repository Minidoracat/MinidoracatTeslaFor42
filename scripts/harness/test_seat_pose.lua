-- The seated pose in a Tesla (client/MinidoracatTesla/SeatPose.lua): MinidoracatTeslaSeated is set while a player
-- sits in any Tesla seat, MinidoracatTeslaRecline only in the two front seats; both cleared in any other car and after
-- getting out. The anim nodes they gate (AnimSets/player-vehicle/idle/MinidoracatTesla_idle_recline.xml,
-- aim/MinidoracatTesla_aim_seated.xml, aim/MinidoracatTesla_aim_recline.xml) are engine behaviour: E2E seat-head-sp
-- and aim-seat-sp.
local check = H.check

H.section("seat pose variables")
H.stub("Vehicles/ISUI/ISVehicleDashboard")
H.require("MinidoracatTesla/SeatPose")
check(H.count("OnEnterVehicle") >= 1 and H.count("OnExitVehicle") >= 1 and H.count("OnSwitchVehicleSeat") >= 1,
    "listens to enter, exit and seat switches")

local function varPlayer(name)
    local o = H.player({ name = name })
    o.vars = {}
    function o:setVariable(k, v) self.vars[k] = v end
    function o:clearVariable(k) self.vars[k] = nil end
    return o
end
local function car(script)
    local v = H.vehicle({ script = script })
    v.seats = {}
    function v:getSeat(p) return self.seats[p] or -1 end
    return v
end
local p = varPlayer("sitter")
local tesla, van = car("Base.MinidoracatTesla_Model3"), car("Base.CarNormal")
local function sit(v, seat)
    p.vehicle = v
    if v then v.seats[p] = seat end
end

sit(tesla, 0)
H.fire("OnEnterVehicle", p)
check(p.vars.MinidoracatTeslaSeated == true and p.vars.MinidoracatTeslaRecline == true, "driver of a Tesla: seated, reclined")

sit(tesla, 2)
H.fire("OnSwitchVehicleSeat", p)
check(p.vars.MinidoracatTeslaSeated == true and p.vars.MinidoracatTeslaRecline == nil,
    "switched to a rear seat: still seated, upright")

sit(tesla, 1)
H.fire("OnSwitchVehicleSeat", p)
check(p.vars.MinidoracatTeslaRecline == true, "switched to the front passenger seat: reclined again")

sit(van, 0)
H.fire("OnEnterVehicle", p)
check(p.vars.MinidoracatTeslaSeated == nil and p.vars.MinidoracatTeslaRecline == nil, "cleared on getting into a vanilla car")

sit(tesla, 0)
H.fire("OnEnterVehicle", p)
sit(nil)
H.fire("OnExitVehicle", p)
check(p.vars.MinidoracatTeslaSeated == nil and p.vars.MinidoracatTeslaRecline == nil, "cleared after getting out of a Tesla")

H.fire("OnExitVehicle", nil)
check(true, "an event without a player is ignored")

-- other players (MP client): synced once a game minute; nothing to do on a server or in SP
local front, rear, inVan, onFoot = varPlayer("a"), varPlayer("b"), varPlayer("c"), varPlayer("d")
front.vehicle, rear.vehicle, inVan.vehicle = tesla, tesla, van
tesla.seats[front], tesla.seats[rear] = 1, 3
for _, o in ipairs({ inVan, onFoot }) do -- left over from a Tesla
    o.vars.MinidoracatTeslaSeated, o.vars.MinidoracatTeslaRecline = true, true
end
local online = { front, rear, inVan, onFoot }
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
H.fire("EveryOneMinute")
check(front.vars.MinidoracatTeslaSeated == nil, "every minute: nothing on a server")
H.side(true, false)
H.fire("EveryOneMinute")
H.side(false, true)
check(front.vars.MinidoracatTeslaSeated == true and front.vars.MinidoracatTeslaRecline == true,
    "every minute (MP client): another player in a Tesla front seat is seated and reclined")
check(rear.vars.MinidoracatTeslaSeated == true and rear.vars.MinidoracatTeslaRecline == nil,
    "every minute (MP client): another player in a Tesla rear seat is seated, upright")
check(inVan.vars.MinidoracatTeslaSeated == nil and onFoot.vars.MinidoracatTeslaRecline == nil,
    "every minute (MP client): cleared on players in another car or on foot")
getOnlinePlayers = nil
