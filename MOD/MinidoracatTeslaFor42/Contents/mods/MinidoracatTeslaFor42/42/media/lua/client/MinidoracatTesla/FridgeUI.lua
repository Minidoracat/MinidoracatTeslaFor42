-- Car fridge, client side (references/upgrades.md section 4): its container button wears vanilla's fridge icon, and an
-- MP client shows the server's food values. The server settles the fridge (server Fridge.lua) but a food's age and
-- freezing time are not in ItemStatsPacket (ItemStatsPacket.java:172-199, only isFrozen), so this client's copy of the
-- food ages at room rate. While an inventory page
-- lists a TeslaFridge container, its food takes the values in fridge.items: when the page is built, then once a game
-- minute while it stays listed (the server settles every ten); fridge.at is the version, one already applied is
-- skipped. No page lists one: nothing runs. The switches are in ParkModesUI.lua (right-click) and HUDRadial.lua.
require "Definitions/ContainerButtonIcons"
require "MinidoracatTesla/Core"
ContainerButtonIcons.TeslaFridge = ContainerButtonIcons.fridge
if not isClient() then return end

local T = MinidoracatTesla
local UI = { applied = {}, watched = {}, nWatched = 0, hooked = false }
T.FridgeUI = UI

-- this fridge's food to the server's values, once per fridge.at; returns how many took them
function UI.apply(part)
    local s = part:getModData().fridge
    if not (s and s.items and s.at) then return 0 end
    local vid = part:getVehicle():getId()
    if UI.applied[vid] == s.at then return 0 end
    UI.applied[vid] = s.at
    local n, items = 0, part:getItemContainer():getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local b = instanceof(it, "Food") and s.items[tostring(it:getID())]
        if b then
            it:updateAge() -- lastAged = now, so the room-rate gap is not added again
            it:setAge(b.age)
            it:setFreezingTime(b.ft)
            it:setFrozen(b.fr == true)
            n = n + 1
        end
    end
    return n
end

-- applies every fridge the page lists; true when it lists one
local function scan(page)
    local found = false
    for _, b in ipairs(page.backpacks or {}) do
        local part = b.inventory and b.inventory:getVehiclePart()
        if part and part:getId() == "TeslaFridge" then
            UI.apply(part)
            found = true
        end
    end
    return found
end

local everyMinute
local function watch(page, on)
    if on and not UI.watched[page] then UI.nWatched = UI.nWatched + 1 end
    if not on and UI.watched[page] then UI.nWatched = UI.nWatched - 1 end
    UI.watched[page] = on or nil
    if UI.nWatched > 0 and not UI.hooked then
        Events.EveryOneMinute.Add(everyMinute)
    elseif UI.nWatched == 0 and UI.hooked then
        Events.EveryOneMinute.Remove(everyMinute)
    end
    UI.hooked = UI.nWatched > 0
end
everyMinute = function()
    local pages = {}
    for page in pairs(UI.watched) do pages[#pages + 1] = page end
    for _, page in ipairs(pages) do watch(page, scan(page)) end
end

Events.OnRefreshInventoryWindowContainers.Add(function(page, step)
    if step == "end" then watch(page, scan(page)) end
end)
