-- The cabin's detail under Project Viewpoint (Workshop 3809306528; references/models.md 8 "Viewpoint"). Viewpoint draws
-- the world in 3-D from the player's eye when ZombieBuddy loads its Java, and then the global Viewpoint exists. It
-- draws every vehicle face with the skin at its UV0 (viewpoint/shaders/lib/vehicle.glsl), so our cabin, which our
-- shader colours from UV1, is there the skin corner's grey (scripts/blender/common/pzveh.py CABIN_UV0_RGB). The detail
-- model (part CabinDetail, model Detail: the furniture a little larger and finer, coloured from its own texture) shows
-- only on a client with Viewpoint, only in the car a local player sits in (user 2026-11-08). Viewpoint draws a part
-- model whose shader is not a vehicle shader with the model's texture (viewpoint/models/VehicleCapture); the game's own
-- draw of it (MinidoracatTesla_viewpoint) puts every vertex past the far plane, so the isometric view stays as it was.
-- The model list is this client's own: setModelVisible on a client sets update flags only a server sends
-- (VehicleManager.java:127-153). A vehicle update with the server's part models (a part fitted or taken off, the
-- cabin glass reordered: Liftgate.lua) hides it here again (VehiclePartModels.java:23-46), so sync runs on every game
-- minute too (2.5 s at the default 1-hour day); a model already shown is found and left as it is
-- (BaseVehicle.java:1707-1714).
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local D = {}
T.ViewpointCabin = D

local shown -- the car showing it here

-- the Tesla a local player sits in, with Viewpoint loaded
local function wanted()
    if not (Viewpoint and Viewpoint.View) then return nil end
    for pn = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(pn)
        local v = p and p:getVehicle()
        if v and T.isTesla(v) and v:getPartById("CabinDetail") then return v end
    end
end

function D.sync()
    local v = wanted()
    if shown and shown ~= v then
        local part = shown:getPartById("CabinDetail")
        if part then part:setModelVisible("Detail", false) end
    end
    if v then v:getPartById("CabinDetail"):setModelVisible("Detail", true) end
    shown = v
end

function D.shown() return shown end

Events.OnEnterVehicle.Add(D.sync)
Events.OnExitVehicle.Add(D.sync)
Events.EveryOneMinute.Add(D.sync)

return D
