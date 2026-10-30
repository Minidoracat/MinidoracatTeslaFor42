-- Cybertruck features (plan-cybertruck-1030 item 5): bed lights, roof light bar.
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local R = {}
T.Truck = R
T.Init = T.Init or {}

-- Light part inits (both sides, every load: VehicleLight saves only active/offset/intensity/dist, VehicleLight.java:85-102;
-- the colour and dot are set again here, like CampPower.lua Init.CabinLight). The spot offset comes from the vehicle
-- script's `table light { xOffset, yOffset }` (geometry, like vanilla's `table headlight`, Vehicles.lua:1512-1520), in
-- half body extents; y < 0 = rear.
local function spot(part, dist, intensity, dot, r, g, b)
    local t = part:getTable("light")
    local x = t and tonumber(t.xOffset) or 0
    local y = t and tonumber(t.yOffset) or 0
    part:createSpotLightColor(x, y, dist, intensity, dot, 0, r, g, b)
end
-- bed lights: all round (dot -1) over the bed, cool white LED
function T.Init.BedLight(vehicle, part)
    spot(part, 4, 0.45, -1, 1.0, 0.96, 0.9)
end
-- roof light bar: forward, vanilla headlight cone (dot 0.75) and brightness, farther (36 -> 48; Vehicles.lua:1505-1509)
function T.Init.RoofLight(vehicle, part)
    spot(part, 48, 0.75, 0.75, 1.0, 1.0, 1.0)
end

return R
