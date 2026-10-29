-- Aiming from a Tesla seat stays seated (client/MinidoracatTesla/SeatAim.lua): MinidoracatTeslaSeated is set while the
-- local player sits in a Tesla, cleared in any other car and after getting out. The anim node it gates
-- (AnimSets/player-vehicle/aim/MinidoracatTesla_aim_seated.xml) is engine behaviour: E2E aim-seat-sp.
local check = H.check

H.section("seat aim variable")
H.stub("Vehicles/ISUI/ISVehicleDashboard")
H.require("MinidoracatTesla/SeatAim")
check(H.count("OnEnterVehicle") >= 1 and H.count("OnExitVehicle") >= 1, "listens to enter and exit")

local p = H.player({ name = "aimer" })
p.vars = {}
function p:setVariable(k, v) self.vars[k] = v end
function p:clearVariable(k) self.vars[k] = nil end

local tesla = H.vehicle({ script = "Base.MinidoracatTesla_Model3" })
local van = H.vehicle({ script = "Base.CarNormal" })

p.vehicle = tesla
H.fire("OnEnterVehicle", p)
check(p.vars.MinidoracatTeslaSeated == true, "set on getting into a Tesla")

p.vehicle = van
H.fire("OnEnterVehicle", p)
check(p.vars.MinidoracatTeslaSeated == nil, "cleared on getting into a vanilla car")

p.vehicle = tesla
H.fire("OnEnterVehicle", p)
p.vehicle = nil
H.fire("OnExitVehicle", p)
check(p.vars.MinidoracatTeslaSeated == nil, "cleared after getting out of a Tesla")

H.fire("OnExitVehicle", nil)
check(true, "an event without a player is ignored")

-- other players (MP client): synced once a game minute; nothing to do on a server or in SP
local function varPlayer(name)
    local o = H.player({ name = name })
    o.vars = {}
    o.setVariable, o.clearVariable = p.setVariable, p.clearVariable
    return o
end
local inTesla, inVan, onFoot = varPlayer("a"), varPlayer("b"), varPlayer("c")
inTesla.vehicle, inVan.vehicle = tesla, van
inVan.vars.MinidoracatTeslaSeated, onFoot.vars.MinidoracatTeslaSeated = true, true -- left over from a Tesla
local online = { inTesla, inVan, onFoot }
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
H.fire("EveryOneMinute")
check(inTesla.vars.MinidoracatTeslaSeated == nil, "every minute: nothing on a server")
H.side(true, false)
H.fire("EveryOneMinute")
H.side(false, true)
check(inTesla.vars.MinidoracatTeslaSeated == true, "every minute (MP client): set on another player seated in a Tesla")
check(inVan.vars.MinidoracatTeslaSeated == nil and onFoot.vars.MinidoracatTeslaSeated == nil,
    "every minute (MP client): cleared on players in another car or on foot")
getOnlinePlayers = nil
