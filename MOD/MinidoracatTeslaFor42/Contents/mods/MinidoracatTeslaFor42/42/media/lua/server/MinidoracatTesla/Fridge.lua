-- Car fridge (server and SP; references/upgrades.md section 4): part TeslaFridge's state `fridge` (Upgrades.lua) is
-- settled here and nowhere else. The engine's own fridge rule needs a powered sourceGrid, which a vehicle container
-- never has (Food.java:760; VehicleParts.java:309), so each settle puts the age and freezing each food would have had
-- since the last settle: Upgrades.lua F.step from the baseline the last settle wrote (fridge.items), the hours the
-- fridge ran in its mode, then the hours it had no power. The clients copy items for display (FridgeUI.lua).
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

-- switched off: `fridge` goes (the server reads only that as on); `fridgeLast` keeps the last settle's values for the
-- clients that have not applied them (FridgeUI.lua), until it is switched on again, removed (Upgrades.lua), or there
-- was nothing in it. One transmit.
local function off(v, part, at, items)
    local md = part:getModData()
    md.fridge = nil
    local any = false
    for _ in pairs(items or {}) do any = true; break end -- Kahlua has no next()
    md.fridgeLast = at and any and { at = at, items = items } or nil
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
            local b, cold = old[k], false
            if b then -- from its baseline only, never from the item's own (client-writable) flags
                local mid = F.step(b, on, s.mode, cf) -- where the power stopped
                cold = b.ft > 0 or mid.ft > 0 -- its most freezing time this stretch: the unpowered rest only thaws
                b = F.step(mid, dt - on, nil, cf)
                it:setAge(b.age)
                it:setFreezingTime(b.ft)
                it:setFrozen(b.fr)
            else -- new food only gets a baseline; frozen only with freezing time to show for it, on the item too
                local ft = it:getFreezingTime()
                b = { age = it:getAge(), ft = ft, fr = ft > 0 and it:isFrozen() }
                -- a frozen flag with ft 0 neither ages nor thaws (Food.java:757-758, 2193-2198); no later settle may fix
                -- it (this one may switch the fridge off)
                if it:isFrozen() ~= b.fr then it:setFrozen(b.fr) end
                cold = ft > 0
            end
            -- frozen eggs die when freezing begins and stay dead when thawed (Food.java:837-838): an egg that had
            -- freezing time at any point of this stretch, so one long catch-up does what ten-minute settles do
            if cold and it:isFertilized() then it:setFertilized(false) end
            new[k] = b
        end
    end
    if full and not s.full then T.log("fridge full vid=" .. v:getId() .. ": " .. F.MAX_ITEMS .. " foods tracked, the rest at room rate") end
    if dead then
        off(v, part, t, new)
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
        if md.fridge then off(v, part, md.fridge.at, md.fridge.items) end
    elseif md.fridge then
        md.fridge.mode = mode
        v:transmitPartModData(part)
    else
        md.fridge, md.fridgeLast = { mode = mode, at = T.hours(), by = by, items = {} }, nil
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
