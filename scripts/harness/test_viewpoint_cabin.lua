-- The cabin detail under Project Viewpoint (client/MinidoracatTesla/ViewpointCabin.lua): with Viewpoint loaded (its
-- global), the Tesla a local player sits in shows part CabinDetail's model Detail, hidden again once out of it or in
-- another car; every sync while seated shows it again (a server vehicle update hides it, VehiclePartModels.java:23-46);
-- without Viewpoint nothing is shown. What Viewpoint draws, and that vanilla draws nothing, is E2E.
local check = H.check

H.section("Viewpoint cabin detail")
local savedNum, savedSpecific, savedVP = getNumActivePlayers, getSpecificPlayer, Viewpoint
local p = H.player({ name = "vp" })
function getNumActivePlayers() return 1 end
function getSpecificPlayer(n) return n == 0 and p or nil end
H.require("MinidoracatTesla/ViewpointCabin")
local D = MinidoracatTesla.ViewpointCabin

local function car(script)
    local v = H.vehicle({ script = script })
    local part = { log = {} }
    function part:setModelVisible(id, on) self.log[#self.log + 1] = id .. "=" .. tostring(on) end
    v.parts.CabinDetail = part
    return v, part.log
end
local a, la = car("Base.MinidoracatTesla_Model3")
local b, lb = car("Base.MinidoracatTesla_Cybertruck")
local van, lv = car("Base.CarNormal")

Viewpoint = nil
p.vehicle = a
D.sync()
check(#la == 0 and D.shown() == nil, "without Viewpoint: nothing shown in the Tesla sat in")

Viewpoint = { View = {} }
D.sync()
check(la[#la] == "Detail=true" and D.shown() == a, "Viewpoint loaded, seated in a Tesla: its detail shown")
local n = #la
D.sync()
check(#la == n + 1 and la[#la] == "Detail=true", "still seated: each sync shows it again (after the server's part models)")

p.vehicle = van
D.sync()
check(la[#la] == "Detail=false" and #lv == 0 and D.shown() == nil, "in a vanilla car: the Tesla's hidden, nothing on the van")

p.vehicle = a
D.sync()
p.vehicle = b
D.sync()
check(la[#la] == "Detail=false" and lb[#lb] == "Detail=true" and D.shown() == b,
    "from one Tesla into another: the first hidden, the second shown")

p.vehicle = nil
D.sync()
check(lb[#lb] == "Detail=false" and D.shown() == nil, "out of the car: hidden")

getNumActivePlayers, getSpecificPlayer, Viewpoint = savedNum, savedSpecific, savedVP
