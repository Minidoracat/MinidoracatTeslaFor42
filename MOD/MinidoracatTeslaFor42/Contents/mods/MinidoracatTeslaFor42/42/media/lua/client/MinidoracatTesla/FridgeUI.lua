-- Car fridge, client side (references/upgrades.md section 4): its container button wears vanilla's fridge icon, and an
-- MP client shows the server's food values. The server settles the fridge (server Fridge.lua) but a food's age and
-- freezing time are not in ItemStatsPacket (ItemStatsPacket.java:172-199, only isFrozen), so this client's copy of the
-- food ages at room rate. While an inventory page lists a TeslaFridge container, its food takes the values in
-- fridge.items (or, the fridge off, fridgeLast.items run on at room rate to now): when the page is built, then once a
-- game minute while it stays listed and shown (the server settles every ten); the table and its `at` are the version,
-- one already applied is skipped. No page lists one: nothing runs. The switches are in ParkModesUI.lua (right-click)
-- and HUDRadial.lua.
require "Definitions/ContainerButtonIcons"
require "MinidoracatTesla/Core"
ContainerButtonIcons.TeslaFridge = ContainerButtonIcons.fridge
if not isClient() then return end

local T = MinidoracatTesla
local UI = { applied = {}, watched = {}, nWatched = 0, hooked = false }
T.FridgeUI = UI

-- this fridge's food to the server's values, once per version; returns how many took them
function UI.apply(part)
    local md = part:getModData()
    local s, ver = md.fridge, "on "
    if not s then s, ver = md.fridgeLast, "last " end
    if not (s and s.items and s.at) then return 0 end
    local vid = part:getVehicle():getId()
    ver = ver .. s.at
    if UI.applied[vid] == ver then return 0 end
    UI.applied[vid] = ver
    local off = not md.fridge and math.max(0, T.hours() - s.at) or 0 -- hours since it went off: room rate, as the server
    local n, items = 0, part:getItemContainer():getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local b = instanceof(it, "Food") and s.items[tostring(it:getID())]
        if b then
            if off > 0 then b = T.Fridge.step(b, off, nil, it:canBeFrozen()) end -- shared Upgrades.lua
            it:updateAge() -- lastAged = now, so the room-rate gap is not added again
            it:setAge(b.age)
            it:setFreezingTime(b.ft)
            it:setFrozen(b.fr == true)
            if b.ft > 0 and it:isFertilized() then it:setFertilized(false) end -- as the server (Fridge.lua)
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
-- a hidden page (the inventory toggled off) stays watched but applies nothing: showing it again does not rebuild it
-- (ISInventoryPage.onKeyPressed / toggleInventory only setVisible), so the next minute after that applies
everyMinute = function()
    local pages = {}
    for page in pairs(UI.watched) do pages[#pages + 1] = page end
    for _, page in ipairs(pages) do
        if page:getIsVisible() then watch(page, scan(page)) end
    end
end

Events.OnRefreshInventoryWindowContainers.Add(function(page, step)
    if step == "end" then watch(page, scan(page)) end
end)
