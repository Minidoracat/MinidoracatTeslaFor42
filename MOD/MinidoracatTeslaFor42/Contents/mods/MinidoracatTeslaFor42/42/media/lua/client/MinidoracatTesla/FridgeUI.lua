-- Car fridge, client side (references/upgrades.md section 4): its container button wears vanilla's fridge icon, and an
-- MP client shows the server's food values. The server settles the fridge (server Fridge.lua) but a food's age and
-- freezing time are not in ItemStatsPacket (ItemStatsPacket.java:172-199, only isFrozen), and this client's copy of the
-- food does not age on its own (Food.update ages on the server only, Food.java:378-380): it only jumps at room rate
-- when this client puts it in or takes it out (:2476-2483). While an inventory page lists a TeslaFridge container and
-- its contents can be seen (shown and not collapsed): when the page is built, then once a game minute,
--   on:  each food takes its values in fridge.items, once per food instance per settle (`fridge.at`);
--   off: the page's player asks the server for the values now (`fridgeFoodPull`, answer `fridgeFood` below), again
--        every ten game minutes, and at once when a food instance shows up that the last ask did not see.
-- One state per car: UI.cars[vid] = { ver, items = { [id] = the instance applied (on) / asked about (off) }, seq,
-- bucket }. No page lists one: nothing runs. The switches are in ParkModesUI.lua (right-click) and HUDRadial.lua.
require "Definitions/ContainerButtonIcons"
require "MinidoracatTesla/Core"
ContainerButtonIcons.TeslaFridge = ContainerButtonIcons.fridge
if not isClient() then return end

local T = MinidoracatTesla
T.ClientCommands = T.ClientCommands or {}
local UI = { cars = {}, seq = 0, watched = {}, nWatched = 0, hooked = false }
T.FridgeUI = UI

local function spoils(it) return instanceof(it, "Food") and it:getOffAgeMax() < 1000000000 end -- the server's test

-- car vid's state, a fresh one when the version changed (switched on or off, or a new settle)
local function state(vid, ver)
    local st = UI.cars[vid]
    if not (st and st.ver == ver) then
        st = { ver = ver, items = {} }
        UI.cars[vid] = st
    end
    return st
end

-- this fridge's food to the server's values. On: each food instance not yet given this settle's values gets them;
-- returns how many. Off: asks through `player` (the page's) when the ten-minute bucket moved on or a food instance is
-- new since the last ask; returns how many foods it asked about (0: no ask)
function UI.apply(part, player)
    local md = part:getModData()
    local vid, s = part:getVehicle():getId(), md.fridge
    local items, n = part:getItemContainer():getItems(), 0
    if s then
        if not (s.items and s.at) then return 0 end
        local st = state(vid, "on " .. tostring(s.at)) -- also drops an off state, so an answer still due is dropped
        local freezing = s.mode == "freeze"
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local id = instanceof(it, "Food") and tostring(it:getID())
            local b = id and s.items[id]
            if b and st.items[id] ~= it then
                st.items[id] = it
                -- an egg in a running freezer, or with freezing time, is dead (as the server, Fridge.lua; Food.isFreezing)
                if (b.ft > 0 or freezing and it:canBeFrozen()) and it:isFertilized() then it:setFertilized(false) end
                it:updateAge() -- lastAged = now, so the room-rate gap is not added again
                it:setAge(b.age)
                it:setFreezingTime(b.ft)
                it:setFrozen(b.fr == true)
                n = n + 1
            end
        end
        return n
    end
    local st, bucket = state(vid, "off"), math.floor(T.hours() * 6) -- ten game minutes
    local due, now = st.bucket ~= bucket, {}
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if spoils(it) then
            local id = tostring(it:getID())
            now[id] = it
            n = n + 1
            if st.items[id] ~= it then due = true end
        end
    end
    if n == 0 or not due or not player then return 0 end
    UI.seq = UI.seq + 1
    st.items, st.bucket, st.seq = now, bucket, UI.seq
    T.request(player, "fridgeFoodPull", { vid = vid, seq = UI.seq })
    return n
end

-- server -> this client: { vid, seq, items = { [id] = { age, ft, fr, fe } } }, the answer to an ask. Only the last
-- ask's answer counts (answers may arrive out of order: sendServerCommand is RELIABLE, not ordered, GameServer.java:
-- 3507-3528, PacketTypes.java:508,722-724); dropped when the fridge was switched on or removed meanwhile. Written only
-- to a food that is still the instance the ask saw (another player's food, or one moved out and back, is a new
-- instance: the next scan asks again). Returns how many foods took it.
T.ClientCommands.fridgeFood = function(args)
    local st = UI.cars[args.vid]
    if not (st and st.ver == "off" and st.seq == args.seq and type(args.items) == "table") then return 0 end
    local v = getVehicleById(args.vid)
    local part = v and T.Fridge and T.Fridge.part(v)
    if not part or part:getModData().fridge then return 0 end
    local c, n = part:getItemContainer(), 0
    for id, b in pairs(args.items) do
        local it = st.items[id]
        if it and c:contains(it) then
            it:updateAge() -- lastAged = now, so the room-rate gap is not added again
            it:setAge(b.age)
            it:setFreezingTime(b.ft)
            it:setFrozen(b.fr == true)
            if it:isFertilized() ~= (b.fe == true) then it:setFertilized(b.fe == true) end
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

-- applies (or asks about) every fridge the page lists while its contents can be seen; true when it lists one
local function scan(page)
    local found, show = false, nil
    for _, b in ipairs(page.backpacks or {}) do
        local part = b.inventory and b.inventory:getVehiclePart()
        if part and part:getId() == "TeslaFridge" then
            found = true
            if show == nil then show = seen(page) end
            if show then UI.apply(part, getSpecificPlayer(page.player or 0)) end
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
