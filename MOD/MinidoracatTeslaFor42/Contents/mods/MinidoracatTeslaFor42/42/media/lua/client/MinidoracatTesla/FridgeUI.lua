-- Car fridge, client side (references/upgrades.md section 4): its container button wears vanilla's fridge icon, and an
-- MP client shows the server's food values. The server settles the fridge (server Fridge.lua) but a food's age and
-- freezing time are not in ItemStatsPacket (ItemStatsPacket.java:172-199, only isFrozen), and this client's copy of the
-- food does not age on its own (Food.update ages on the server only, Food.java:378-380): it only jumps at room rate
-- when this client puts it in or takes it out (:2476-2483). While an inventory page lists a TeslaFridge container, its
-- food takes the values in fridge.items (or, the fridge off, fridgeLast.items run on at room rate to now): when the
-- page is built, then once a game minute while it stays listed, each time only while its contents can be seen (shown
-- and not collapsed). A version says what was applied, one already applied is skipped: on, `fridge.at` (the server
-- settles every ten minutes); off, `fridgeLast.at` and the ten game minutes now falls in, as the value it runs on to
-- moves with the clock. No page lists one: nothing runs. The switches are in ParkModesUI.lua (right-click) and
-- HUDRadial.lua.
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
    local s, now = md.fridge, T.hours()
    local ver = s and "on " .. tostring(s.at)
    if not s then
        s = md.fridgeLast
        ver = s and "last " .. tostring(s.at) .. " " .. math.floor(now * 6) -- the ten-minute bucket
    end
    if not (s and s.items and s.at) then return 0 end
    local vid = part:getVehicle():getId()
    if UI.applied[vid] == ver then return 0 end
    UI.applied[vid] = ver
    local off = not md.fridge and math.max(0, now - s.at) or 0 -- hours since it went off: room rate, as the server
    local freezing = md.fridge and md.fridge.mode == "freeze"
    local n, items = 0, part:getItemContainer():getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local b = instanceof(it, "Food") and s.items[tostring(it:getID())]
        if b then
            -- an egg in a running freezer, or with freezing time before the run-on (room rate only thaws), is dead
            -- (as the server, Fridge.lua; Food.isFreezing)
            if (b.ft > 0 or freezing and it:canBeFrozen()) and it:isFertilized() then it:setFertilized(false) end
            if off > 0 then b = T.Fridge.step(b, off, nil, it:canBeFrozen()) end -- shared Upgrades.lua
            it:updateAge() -- lastAged = now, so the room-rate gap is not added again
            it:setAge(b.age)
            it:setFreezingTime(b.ft)
            it:setFrozen(b.fr == true)
            n = n + 1
        end
    end
    return n
end

-- can this page's contents be seen? Hidden (inventory toggled off) or collapsed to its title bar (ISInventoryPage
-- collapseNow sets only isCollapsed, ISInventoryPage.lua:1276-1280): nothing to show, so nothing applied
local function seen(page)
    return page:getIsVisible() and not page.isCollapsed
end

-- applies every fridge the page lists while its contents can be seen; true when it lists one
local function scan(page)
    local found, show = false, nil
    for _, b in ipairs(page.backpacks or {}) do
        local part = b.inventory and b.inventory:getVehiclePart()
        if part and part:getId() == "TeslaFridge" then
            found = true
            if show == nil then show = seen(page) end
            if show then UI.apply(part) end
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
-- a page whose contents cannot be seen stays watched but applies nothing: showing it again does not rebuild it
-- (ISInventoryPage.onKeyPressed / toggleInventory only setVisible; uncollapsing clears isCollapsed), so the next
-- minute after that applies
everyMinute = function()
    local pages = {}
    for page in pairs(UI.watched) do pages[#pages + 1] = page end
    for _, page in ipairs(pages) do watch(page, scan(page)) end
end

Events.OnRefreshInventoryWindowContainers.Add(function(page, step)
    if step == "end" then watch(page, scan(page)) end
end)
