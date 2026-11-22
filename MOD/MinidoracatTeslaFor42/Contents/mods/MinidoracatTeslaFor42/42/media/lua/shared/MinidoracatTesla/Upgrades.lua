-- Upgrades (references/upgrades.md): part TeslaArmor (protection kits) and part TeslaFridge (car fridge), both in
-- template MinidoracatTeslaCab. Shared, so both sides have the data and the part inits; the install / uninstall
-- completes run where the timed action completes (the server, or SP). The server sides (server/MinidoracatTesla/
-- Armor.lua, Fridge.lua) hook in through T.Armor.track / untrack and T.Fridge.track / untrack, called here only
-- when they exist (never on a client).
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Liftgate"
require "MinidoracatTesla/ParkModes"

local T = MinidoracatTesla
T.Init = T.Init or {}
T.InstallComplete = T.InstallComplete or {}
T.UninstallComplete = T.UninstallComplete or {}

-- ---------------------------------------------------------------- Armor
local A = {}
T.Armor = A

-- the share of impact damage the car keeps with each kit fitted (no kit: full damage)
A.K = {
    ["Base.MinidoracatTesla_ArmorInner"] = 0.5,
    ["Base.MinidoracatTesla_ArmorOuter"] = 0.25,
}

-- the parts a kit shields, picked the way the engine picks what zombies and melee hit (door / bodywork,
-- BaseVehicle.java:9596-9599) plus windows, lights, the drive unit and the battery: a new car is covered as is.
-- Not tyres, brakes, suspension or seats (tyres wear every minute; covering them would double their life).
function A.covers(part)
    local id, c = part:getId(), part:getCategory()
    if id == "TeslaArmor" then return false end
    return c == "door" or c == "bodywork" or part:getWindow() ~= nil or part:getLight() ~= nil
        or id == "Engine" or id == "GasTank"
end

-- the fitted kit's k, or nil with none
function A.k(vehicle)
    local p = vehicle and vehicle:getPartById("TeslaArmor")
    local it = p and p:getInventoryItem()
    return it and A.K[it:getFullType()] or nil
end

-- the bull bar (model Armor, in each car's script) shows with the Outer kit only. The part is not
-- setAllModelsVisible, so the engine never toggles it (VehiclePart.java:148-162); a car without model Armor ignores
-- the call (:467-472). On the server it reaches every client (PartModels, VehiclePartModels.java:23-60).
function A.sync(vehicle, part)
    local it = part:getInventoryItem()
    local show = it ~= nil and it:getFullType() == "Base.MinidoracatTesla_ArmorOuter"
    part:setModelVisible("Armor", show)
    return show
end

-- every load (both sides) and an admin repair (VehiclePart.java:955-972). CabinGlass inits earlier in the part order
-- and the window glass must draw last (Liftgate.lua Init.CabinGlass), so it goes behind the bar again.
function T.Init.Armor(vehicle, part)
    if A.sync(vehicle, part) then T.Liftgate.glassLast(vehicle) end
    if part:getInventoryItem() and A.track then A.track(vehicle) end
end

-- fitted: Liftgate.lua's install wrapper moves the glass behind the bar after this (glassAfter)
function T.InstallComplete.Armor(vehicle, part)
    A.sync(vehicle, part)
    if A.track then A.track(vehicle) end
end

-- removed: the part has no item any more (ISUninstallVehiclePart.complete takes it before calling this)
function T.UninstallComplete.Armor(vehicle, part)
    A.sync(vehicle, part)
    if A.untrack then A.untrack(vehicle) end
end

-- ---------------------------------------------------------------- Fridge
-- part modData `fridge` = { mode = "cool" | "freeze", at, by, full, items = { ["<item id>"] = { age, ft, fr } } }
-- (server only writes it; items is keyed by tostring(getID()), which survives reloads and restarts,
-- references/upgrades.md); command `fridge` { vid, mode = "cool" | "freeze" | false }. Off = no `fridge` table; a
-- client showing it then asks the server for the food's values (`fridgeFoodPull` -> `fridgeFood`, Fridge.lua).
local F = {}
T.Fridge = F

F.KW = 0.06            -- draw while on: 60 W
-- food tracked per fridge, in container order: fridge.items rides in the part's modData (length unsigned 16-bit,
-- VehiclePartModData.java:23-29) inside the car's update packet (total a signed short, 32,767,
-- VehicleUpdatePacket.java:82); ~54 bytes an entry. The off answer (fridgeFood) sends as many.
F.MAX_ITEMS = 400
F.FREEZE_HOURS = 4     -- freezing time 0 -> 100 in a powered freezer (Food.java:835,839)
F.THAW_HOURS = 1.5     -- 100 -> 0 anywhere else; twice that in a powered fridge (Food.java:836,843-846)
-- vanilla's fridge slow-down and rot speed by the sandbox values; any other value is the default 3 (Food.java:713-732)
F.FRIDGE_FACTOR = { 0.4, 0.3, 0.2, 0.1, 0.03, 0 }
F.ROT_SPEED = { 1.7, 1.4, 1.0, 0.7, 0.4 }
function F.fridgeFactor() return F.FRIDGE_FACTOR[SandboxVars.FridgeFactor] or F.FRIDGE_FACTOR[3] end
function F.rotSpeed() return F.ROT_SPEED[SandboxVars.FoodRotSpeed] or F.ROT_SPEED[3] end

-- one food's { age, ft, fr } after h hours with the fridge powered in `mode` ("cool" / "freeze"), or with no power
-- (mode nil: room rate). Vanilla's freezer and fridge rules in exact pieces, so step(step(b, x), y) == step(b, x + y):
-- frozen food does not age (Food.java:757-758) and stays frozen until thawed to 0 (setFreezingTime, :2156-2163);
-- a powered freezer raises ft 100 per 4 h (:837-839), unfrozen food ageing at the fridge factor meanwhile
-- (:759-761); anywhere else ft falls 100 per 1.5 h, 3 h in a powered fridge (:842-852; its /6 is for a container
-- above 1.0, a stove: a powered fridge reads 0.2, a car's 1.0, ItemContainer.java:2442-2462). A food that cannot
-- freeze keeps its ft (:2189-2199).
function F.step(b, h, mode, canFreeze)
    local ft, fr = b.ft, b.fr
    local still = fr and h or 0 -- the hours of h spent frozen
    if canFreeze and mode == "freeze" then
        if not fr then still = math.max(0, h - (100 - ft) / 100 * F.FREEZE_HOURS) end
        ft = math.min(100, ft + h * 100 / F.FREEZE_HOURS)
        fr = fr or ft >= 100
    elseif canFreeze and ft > 0 then
        local th = mode == "cool" and 2 * F.THAW_HOURS or F.THAW_HOURS
        if fr then still = math.min(h, ft / 100 * th) end
        ft = math.max(0, ft - h * 100 / th)
        fr = fr and ft > 0
    end
    local rate = (mode and F.fridgeFactor() or 1) * F.rotSpeed() / 24 -- age is in days (Food.java:773)
    return { age = b.age + (h - still) * rate, ft = ft, fr = fr }
end

-- the fitted fridge part, or nil
function F.part(vehicle)
    local p = vehicle and vehicle:getPartById("TeslaFridge")
    return p and p:getInventoryItem() and p or nil
end

-- may player switch the fridge to `mode`? The server's `fridge` command and the menus' greying. VehicleManager's
-- CARGO decides a car it has an owner for; otherwise (none installed, or the car "UNCLAIMED") this MOD's own rule
-- (Core.lua T.ownRule: a key, the card or phone key, hotwired, VehicleEasyUse) or an unlocked car, as the guide says
-- (STEAM_GUIDE.md "車沒綁定"). Switching on needs sentry's 20 % or a charger.
-- Returns true, or false and the deny reason (nil for a mode no client sends).
F.MODES = { cool = true, freeze = true }
function F.canSet(player, vehicle, mode)
    if mode ~= false and not F.MODES[mode] then return false end
    if not F.part(vehicle) then return false, "NO_FRIDGE" end
    local ok, why = T.authorized(player, vehicle, "CARGO")
    local api = MinidoracatVehicleManagerAPI
    local vm = api and api.canUse and why ~= "UNCLAIMED"
    if why == "UNCLAIMED" then ok = T.ownRule(player, vehicle) end
    if not ok then
        if vm then return false, T.VM_REASONS[why] and why or "NOT_OWNER" end
        if vehicle:isAnyDoorLocked() then return false, "CAR_LOCKED" end
    end
    if mode then
        local bp = T.Battery.part(vehicle)
        if not bp or T.Battery.pct(bp) < T.Sentry.MIN_PCT and not T.Battery.onCharger(bp) then return false, "LOW_BATTERY" end
    end
    return true
end

-- every load (both sides) and an admin repair. repair() fills the item's capacity (VehiclePart.java:964-966) and a
-- fitted item copies it into the part's content amount (:185-193), which requireEmpty reads (Vehicles.lua:948-949):
-- an empty fridge would never come off. Zero both.
function T.Init.Fridge(vehicle, part)
    part:setContainerContentAmount(0)
    local it = part:getInventoryItem()
    if it then it:setItemCapacity(0) end
end

-- removed (empty, requireEmpty): forget its state; transmitPartModData reaches the clients from the server only
-- (BaseVehicle.java:8274-8281)
function T.UninstallComplete.Fridge(vehicle, part)
    part:getModData().fridge = nil
    vehicle:transmitPartModData(part)
    if F.untrack then F.untrack(vehicle) end
end
