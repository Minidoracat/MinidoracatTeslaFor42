-- Car fridge (server and SP; references/upgrades.md section 4): part TeslaFridge's state `fridge` (Upgrades.lua) is
-- settled here and nowhere else. The engine's own fridge rule needs a powered sourceGrid, which a vehicle container
-- never has (Food.java:760; VehicleParts.java:309), so each settle puts the age and freezing each food would have had
-- since the last settle: Upgrades.lua F.step from the baseline the last settle wrote (fridge.items), the hours the
-- fridge ran in its mode, then the hours it had no power. The clients copy items for display while it is on; off,
-- a client asks for the food's values now (fridgeFoodPull below; FridgeUI.lua).
-- When: every ten game minutes over the cars registered below, on every load (OnSpawnVehicleEnd: catch-up), before a
-- mode change, and with every charging settle (Charging.lua settleSentry), so the power it ran on is booked as sentry's.
if isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/Inbox"
require "MinidoracatTesla/Upgrades"

local T = MinidoracatTesla
local F, B, S = T.Fridge, T.Battery, T.Sentry
T.ServerCommands = T.ServerCommands or {}

-- vehicle id -> true for the loaded cars with the fridge on. Memory only: ids change on every load and an old one goes
-- to another car (BaseVehicle.java:800-806). A car still at id -1 when it loads goes on `late` instead: the next
-- ten-minute tick lists it if it has an id by then and drops it either way (its next load puts it back).
local cars, late = {}, {}
F.cars, F.late = cars, late
function F.track(v)
    local id = v:getId()
    if id == -1 then late[v] = true else cars[id] = true end
end
function F.untrack(v) cars[v:getId()] = nil end

-- switched off: `fridge` goes (the server reads only that as on). One transmit.
local function off(v, part)
    part:getModData().fridge = nil
    F.untrack(v)
    v:transmitPartModData(part)
end

-- Books the fridge from fridge.at to t (default now). freeUntil: as Sentry.settle (world hour a charger powered the
-- car until; nil = Charge.powerUntil); that stretch costs the pack nothing and goes into chg.fed off the grid. The
-- rest runs on the pack down to S.MIN_PCT; short of that the fridge switches off and its `by` hears it once (it stays
-- off until switched on again, as sentry).
function F.settle(v, t, freeUntil)
    local part = v and v:getPartById("TeslaFridge")
    local s = part and part:getModData().fridge
    if not s then return end
    local bp = B.part(v)
    if not (bp and part:getInventoryItem() and part:getItemContainer()) then return off(v, part) end
    t = t or T.hours()
    local at = tonumber(s.at) or t
    local dt = math.max(0, t - at)
    local md = bp:getModData()
    if freeUntil == nil then
        local f = T.Charge and T.Charge.powerUntil
        if f then freeUntil = f(md.chg, t) elseif B.onCharger(bp) then freeUntil = t end
    end
    local free = math.max(0, math.min(dt, (freeUntil or at) - at))
    if free > 0 and md.chg and md.chg.power ~= "grid" then md.chg.fed = (md.chg.fed or 0) + free * F.KW end
    local cur = B.kwh(bp)
    local paid = math.min(dt - free, math.max(0, (cur - B.capacity(bp) * S.MIN_PCT / 100) / F.KW))
    if paid > 0 then B.set(v, bp, cur - paid * F.KW) end
    local on = free + paid -- hours it ran; the rest of dt it had no power
    local dead = on < dt - 1e-9
    -- an egg dies once it is freezing (Food.isFreezing: can freeze, in a powered freezer; Food.java:837-838, 2188-2190)
    -- and stays dead thawed: freeze mode with power in this stretch (dt 0 is a switch-on or switch-to-freeze settle,
    -- powered), or freezing time already. A stretch with no power at all freezes nothing.
    local freezing = s.mode == "freeze" and (on > 0 or dt == 0)
    local old, new, n, full = s.items or {}, {}, 0, false
    local items = part:getItemContainer():getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        -- food that spoils (Food.java:1377-1381); the first F.MAX_ITEMS of it, the rest at room rate
        if instanceof(it, "Food") and it:getOffAgeMax() < 1000000000 then
            if n == F.MAX_ITEMS then full = true; break end
            n = n + 1
            it:updateAge() -- lastAged = now: the engine adds nothing on top of what is set here
            local k, cf = tostring(it:getID()), it:canBeFrozen()
            local b, was = old[k], nil -- was: its freezing time before this stretch
            if b then -- from its baseline only, never from the item's own (client-writable) flags
                was = b.ft
                b = F.step(F.step(b, on, s.mode, cf), dt - on, nil, cf)
                it:setAge(b.age)
                it:setFreezingTime(b.ft)
                it:setFrozen(b.fr)
            else -- new food only gets a baseline; frozen only with freezing time to show for it, on the item too
                was = it:getFreezingTime()
                b = { age = it:getAge(), ft = was, fr = was > 0 and it:isFrozen() }
                -- a frozen flag with ft 0 neither ages nor thaws (Food.java:757-758, 2193-2198); no later settle may fix
                -- it (this one may switch the fridge off)
                if it:isFrozen() ~= b.fr then it:setFrozen(b.fr) end
            end
            if (was > 0 or cf and freezing) and it:isFertilized() then it:setFertilized(false) end
            new[k] = b
        end
    end
    if full and not s.full then T.log("fridge full vid=" .. v:getId() .. ": " .. F.MAX_ITEMS .. " foods tracked, the rest at room rate") end
    if dead then
        off(v, part)
        T.log("fridge off low battery vid=" .. v:getId())
        T.Inbox.notify(s.by, T.Inbox.entry(v, "lowBattery", "fridge"))
        return
    end
    s.at, s.items, s.full = t, new, full or nil
    F.track(v)
    v:transmitPartModData(part)
end

-- mode "cool" / "freeze" / false (off). Settled first, so the hours so far count under the old mode.
function F.setMode(v, mode, by)
    local part = F.part(v)
    if not part then return end
    local md = part:getModData()
    local was = md.fridge ~= nil
    F.settle(v)
    if was and not md.fridge then return end -- that settle just switched it off for low battery (and said so)
    if not mode then
        if md.fridge then off(v, part) end
    elseif md.fridge then
        md.fridge.mode = mode
        F.settle(v) -- dt 0, in place of a bare transmit: switched to freeze, its eggs die now (as a freezer's first update)
    else
        md.fridge = { mode = mode, at = T.hours(), by = by, items = {} }
        F.settle(v) -- the food in it now gets its baseline
    end
    T.log("fridge " .. tostring(mode or "off") .. " vid=" .. v:getId() .. " by " .. tostring(by))
end

-- client -> server: { vid, mode }. In the car or within T.NEAR, a fridge fitted, a mode the menus offer, the right to
-- the cargo (F.canSet), switching on with 20 % or a charger.
T.ServerCommands.fridge = function(player, args)
    local v = T.commandVehicle(player, args) -- Commands.lua
    if not v then return end
    local ok, why = F.canSet(player, v, args.mode)
    if not ok then
        if why then T.deny(player, why, v:getId()) end
        return
    end
    F.setMode(v, args.mode, T.account(player))
end

-- client -> server: { vid, seq } from a page that shows the fridge while it is off (FridgeUI.lua). Answers that
-- player only with `fridgeFood` { vid, seq, items = { ["<item id>"] = { age, ft, fr, fe } } } (fe only when
-- fertilized): its first F.MAX_ITEMS spoiling foods as the engine has them now (updateAge: its own catch-up; false:
-- no ItemStats to the players around, Food.java:735-745). In the car or within T.NEAR (T.commandVehicle), and the
-- container in this player's reach by the test the loot page uses (canAccessContainer runs the part's
-- ContainerAccess function, BaseVehicle.java:8439-8455). No fridge, switched on (the clients read fridge.items),
-- out of reach or nothing spoiling in it: no answer. Stores nothing.
T.ServerCommands.fridgeFoodPull = function(player, args)
    local v = T.commandVehicle(player, args)
    local part = v and F.part(v)
    local c = part and part:getItemContainer()
    if not c or part:getModData().fridge or not v:canAccessContainer(part:getIndex(), player) then return end
    local items, out, n = c:getItems(), {}, 0
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if instanceof(it, "Food") and it:getOffAgeMax() < 1000000000 then
            if n == F.MAX_ITEMS then break end
            n = n + 1
            it:updateAge(false)
            out[tostring(it:getID())] = { age = it:getAge(), ft = it:getFreezingTime(), fr = it:isFrozen(),
                fe = it:isFertilized() or nil }
        end
    end
    if n > 0 then T.send(player, "fridgeFood", { vid = v:getId(), seq = args.seq, items = out }) end
end

local function settleSafe(v, t)
    local ok, err = pcall(F.settle, v, t)
    if not ok then T.log("fridge settle failed vid=" .. tostring(v:getId()) .. ": " .. tostring(err)) end
end

Events.EveryTenMinutes.Add(function()
    local retry = {}
    for v in pairs(late) do retry[#retry + 1] = v end
    for _, v in ipairs(retry) do
        late[v] = nil
        local id = v:getId()
        local p = id ~= -1 and getVehicleById(id) == v and v:getPartById("TeslaFridge")
        if p and p:getModData().fridge then cars[id] = true end
    end
    local ids = {}
    for id in pairs(cars) do ids[#ids + 1] = id end
    local t = T.hours()
    for _, id in ipairs(ids) do
        local v = getVehicleById(id)
        if v and T.isTesla(v) then settleSafe(v, t) else cars[id] = nil end
    end
end)

-- every load runs createPhysics, which fires this before the parts go into the world (BaseVehicle.java:913, 8018):
-- the catch-up for the time away. Charging.lua's relink, on
-- the same event, may have settled it a moment ago through settleSentry: this one then has dt 0 and rewrites the same
-- baseline (food with a baseline always runs from it).
Events.OnSpawnVehicleEnd.Add(function(v)
    cars[v:getId()] = nil -- the id may have been another car's
    local p = v:getPartById("TeslaFridge")
    if p and p:getModData().fridge then settleSafe(v) end
end)
