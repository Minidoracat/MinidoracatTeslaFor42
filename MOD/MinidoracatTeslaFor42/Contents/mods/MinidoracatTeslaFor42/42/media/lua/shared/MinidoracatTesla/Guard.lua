-- Command guard: vanilla vehicle/setContainerContentAmount has no permission check (VehicleCommands.lua:76-88),
-- so any client could set a Tesla's charge. Registered from shared so it runs before every server/ handler
-- (dedicated server loads all shared before server, GameServer.java:1469-1471; Event.trigger keeps Add order and
-- hands the same args table to every callback, Event.java:52-63). Same approach as VehicleManager
-- shared/MinidoracatVehicleManager_CommandGate.lua:266-279,331-335. Admins pass.
require "MinidoracatTesla/Core"

local T = MinidoracatTesla

local function neutralize(args)
    local keys = {}
    for k in pairs(args) do keys[#keys + 1] = k end
    for _, k in ipairs(keys) do args[k] = nil end
    args.vehicle = -1 -- VehicleIDMap.get(-1) is null, the vanilla handler then just logs (VehicleIDMap.java:65-67)
end

function T.guardCommand(module, command, player, args)
    if module ~= "vehicle" or command ~= "setContainerContentAmount" or type(args) ~= "table" then return false end
    if args.part ~= T.BATTERY_PART or type(args.vehicle) ~= "number" then return false end
    local v = getVehicleById(args.vehicle)
    if not v or not T.isTesla(v) or T.isAdmin(player) then return false end
    local id = v:getId()
    neutralize(args)
    T.log("blocked setContainerContentAmount on Tesla " .. tostring(id) .. " from " .. tostring(player and player:getUsername()))
    return true
end

if isServer() and not T.guardRegistered then
    T.guardRegistered = true
    Events.OnClientCommand.Add(function(module, command, player, args) T.guardCommand(module, command, player, args) end)
end
