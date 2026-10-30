-- Powershare's hidden generator (server/MinidoracatTesla/Powershare.lua) is a vanilla IsoGenerator: the right-click
-- fetch (ISWorldObjectContextMenuLogic.java:326-327) takes it as fetch.generator, and vanilla's generator menu
-- (info, switch, plug, fuel, fix, take; :2088-2226) would offer it on the floor next to the truck. The event fires
-- after the fetch and before the menu is built (ISWorldObjectContextMenu.lua:183-190): drop ours by its sprite (never
-- its modData, which any client can write, AGENTS.md rule 3).
require "ISUI/ISWorldObjectContextMenu"
require "MinidoracatTesla/Chargers"

local T = MinidoracatTesla

Events.OnPreFillWorldObjectContextMenu.Add(function()
    local fetch = ISWorldObjectContextMenu.fetchVars
    if fetch and fetch.generator and T.isPowershare(fetch.generator) then fetch.generator = nil end
end)
