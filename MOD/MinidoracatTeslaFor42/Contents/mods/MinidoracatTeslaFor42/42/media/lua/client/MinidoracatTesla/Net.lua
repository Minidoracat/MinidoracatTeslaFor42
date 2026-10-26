-- Client side of module "MinidoracatTesla": one OnServerCommand dispatch into MinidoracatTesla.ClientCommands.
-- SP never gets here (MinidoracatTesla.send calls the handler directly).
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
T.ClientCommands = T.ClientCommands or {}

-- default deny handler: red halo text over the local player (HaloTextHelper.java; vanilla ISWorldObjectContextMenu.lua:1038)
T.ClientCommands.deny = T.ClientCommands.deny or function(args)
    local p = getSpecificPlayer(0)
    local reason = type(args) == "table" and tostring(args.reason) or "?"
    if p then HaloTextHelper.addBadText(p, T.denyText(reason)) end
end

if not T.clientDispatch then
    T.clientDispatch = true
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= T.MODULE then return end
        local fn = T.ClientCommands[command]
        if fn then fn(type(args) == "table" and args or {}) end
    end)
end
