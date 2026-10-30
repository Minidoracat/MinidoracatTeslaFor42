-- Powershare's hidden generator (server/MinidoracatTesla/Powershare.lua) is a vanilla IsoGenerator: the right-click
-- fetch (ISWorldObjectContextMenuLogic.java:326-327) takes it as fetch.generator, and vanilla's generator menu
-- (info, switch, plug, fuel, fix, take; :2088-2226) would offer it on the floor next to the truck. The event fires
-- after the fetch and before the menu is built (ISWorldObjectContextMenu.lua:183-190): drop ours by its sprite (never
-- its modData, which any client can write, AGENTS.md rule 3). The sledgehammer cursor would offer it too
-- (ISDestroyCursor:canDestroy, server/BuildingObjects/ISDestroyCursor.lua:293-362). The server refuses all of these
-- anyway (Powershare.lua guard); this only keeps them off the screen.
require "ISUI/ISWorldObjectContextMenu"
require "MinidoracatTesla/Chargers"

local T = MinidoracatTesla

Events.OnPreFillWorldObjectContextMenu.Add(function()
    local fetch = ISWorldObjectContextMenu.fetchVars
    if fetch and fetch.generator and T.isPowershare(fetch.generator) then fetch.generator = nil end
end)

-- ISDestroyCursor lives in the server folder, loaded after this one: wrap it once the game runs
local wrapped = false
Events.OnGameStart.Add(function()
    if wrapped or not (ISDestroyCursor and ISDestroyCursor.canDestroy) then return end
    wrapped = true
    local canDestroy = ISDestroyCursor.canDestroy
    function ISDestroyCursor:canDestroy(object)
        if object and instanceof(object, "IsoGenerator") and T.isPowershare(object) then return false end
        return canDestroy(self, object)
    end
end)
