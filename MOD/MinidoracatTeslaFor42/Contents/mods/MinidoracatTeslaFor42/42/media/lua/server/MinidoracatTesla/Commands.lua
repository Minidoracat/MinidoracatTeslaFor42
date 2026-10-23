-- Server side of module "MinidoracatTesla": one OnClientCommand dispatch into MinidoracatTesla.ServerCommands.
-- SP routes sendClientCommand here too (SinglePlayerClient.java:101-123 -> OnClientCommand).
if isClient() then return end
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
T.ServerCommands = T.ServerCommands or {}
T.NEAR = 10 -- tiles between player and car for commands sent from outside

local function isInt(n) return type(n) == "number" and n == n and math.floor(n) == n end

-- Shared validation for handlers: player, Tesla by args.vid, distance. Denies and returns nil on failure.
function T.commandVehicle(player, args, maxDist)
    if not player then return nil end
    local vid = args and args.vid
    local v = isInt(vid) and getVehicleById(vid) or nil -- whole numbers only: fractions truncate to another id
    if not v or not T.isTesla(v) then
        T.deny(player, "NO_VEHICLE", isInt(vid) and vid or nil)
        return nil
    end
    if player:getVehicle() ~= v and player:DistTo(v) > (maxDist or T.NEAR) then
        T.deny(player, "TOO_FAR", vid)
        return nil
    end
    return v
end

if not T.serverDispatch then
    T.serverDispatch = true
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= T.MODULE then return end
        local fn = T.ServerCommands[command]
        if not fn then return end
        local ok, err = pcall(fn, player, type(args) == "table" and args or {})
        if not ok then T.log("command " .. tostring(command) .. " failed: " .. tostring(err)) end
    end)
end
