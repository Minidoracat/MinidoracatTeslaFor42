-- Public, versioned API for other mods. Read-only; works on server and client.
-- hudRect(playerNum) is added by client/MinidoracatTesla/HUD.lua (TeslaDashboard).
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
MinidoracatTeslaAPI = MinidoracatTeslaAPI or {}
local API = MinidoracatTeslaAPI
API.apiVersion = 1

function API.isTesla(vehicle) return T.isTesla(vehicle) end

-- pct 0-100, kwh, capacity kWh; nil when the car is not a Tesla or the pack is removed
function API.battery(vehicle)
    local part = T.Battery.part(vehicle)
    if not part or not part:getInventoryItem() then return nil end
    return T.Battery.pct(part), T.Battery.kwh(part), T.Battery.capacity(part)
end

function API.rangeKm(vehicle) return T.rangeKm(vehicle) end

-- true while a charge cable is plugged in (charging, paused or full)
function API.isPluggedIn(vehicle)
    local part = T.Battery.part(vehicle)
    return part ~= nil and part:getModData().chg ~= nil
end

return API
