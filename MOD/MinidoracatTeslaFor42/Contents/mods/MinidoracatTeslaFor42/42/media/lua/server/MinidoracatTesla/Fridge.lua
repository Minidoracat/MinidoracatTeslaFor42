-- Car fridge (server and SP; references/upgrades.md section 4): part TeslaFridge's state `fridge` (Upgrades.lua) is
-- settled here and nowhere else. The engine's own fridge rule needs a powered sourceGrid, which a vehicle container
-- never has (Food.java:760; VehicleParts.java:309), so each settle puts the age (and the freezing) the food
-- would have had: since the last settle, the hours the fridge ran at the fridge factor, the rest at room rate,
-- counted from the baseline the last settle wrote (fridge.items). The clients copy items for display (FridgeUI.lua).
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
-- to another car (BaseVehicle.java:800-806). A car still at id -1 when it loads is not listed; `late` makes the next
-- ten-minute tick look for it in the cell.
local cars, late = {}, false
F.cars = cars
function F.track(v)
    local id = v:getId()
    if id == -1 then late = true else cars[id] = true end
end
function F.untrack(v) cars[v:getId()] = nil end

local function off(v, part)
    part:getModData().fridge = nil
    F.untrack(v)
    v:transmitPartModData(part)
end

-- Books the fridge from fridge.at to t (default now). freeUntil: as Sentry.settle (world hour a charger powered the
-- car until; nil = Charge.powerUntil); that stretch costs the pack nothing and goes into chg.fed off the grid. The
-- rest runs on the pack down to S.MIN_PCT; short of that the fridge switches off and its `by` hears it once (off
-- clears the state: it stays off until switched on again, as sentry).
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
    local factor, perHour = F.fridgeFactor(), F.rotSpeed() / 24 -- age is in days (Food.java:773)
    local freeze = s.mode == "freeze"
    local old, new = s.items or {}, {}
    local items = part:getItemContainer():getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if instanceof(it, "Food") then
            it:updateAge() -- lastAged = now: the engine adds nothing on top of what is set here
            local k = tostring(it:getID())
            local b = old[k]
            -- only food that was here at the last settle runs from its baseline; new food only gets one
            if b then
                it:setAge(b.age + ((dt - on) + on * (b.fr and 0 or factor)) * perHour)
                if freeze and it:canBeFrozen() then
                    if not b.fr then
                        it:setFreezingTime(math.min(100, b.ft + on / F.FREEZE_HOURS * 100))
                        if it:getFreezingTime() >= 100 then it:setFrozen(true) end
                    elseif not dead then
                        it:setFreezingTime(100)
                        it:setFrozen(true)
                    end
                end
            end
            new[k] = { age = it:getAge(), ft = it:getFreezingTime(), fr = it:isFrozen() }
        end
    end
    if dead then
        off(v, part)
        T.log("fridge off low battery vid=" .. v:getId())
        T.Inbox.notify(s.by, T.Inbox.entry(v, "lowBattery", "fridge"))
        return
    end
    s.at, s.items = t, new
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
        v:transmitPartModData(part)
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

local function settleSafe(v, t)
    local ok, err = pcall(F.settle, v, t)
    if not ok then T.log("fridge settle failed vid=" .. tostring(v:getId()) .. ": " .. tostring(err)) end
end

-- the cars that loaded at id -1 (IsoCell.getVehicles is a HashSet: iterator)
local function sweep()
    late = false
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        local p = v:getPartById("TeslaFridge")
        if p and p:getModData().fridge then F.track(v) end
    end
end

Events.EveryTenMinutes.Add(function()
    if late then sweep() end
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
