-- Upgrades (references/upgrades.md): part TeslaArmor (protection kits) and part TeslaFridge (car fridge), both in
-- template MinidoracatTeslaCab. Shared, so both sides have the data and the part inits; the install / uninstall
-- completes run where the timed action completes (the server, or SP). The server sides (server/MinidoracatTesla/
-- Armor.lua, Fridge.lua) hook in through T.Armor.track / untrack and T.Fridge.track / untrack, called here only
-- when they exist (never on a client).
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Liftgate"

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
-- part modData `fridge` = { mode = "cool" | "freeze", at, by, items = { [full type] = { age, ft, fr } } } (server only
-- writes it); command `fridge` { vid, mode }. Off = no `fridge` table.
local F = {}
T.Fridge = F

F.KW = 0.06            -- draw while on: 60 W
F.FREEZE_HOURS = 4     -- unfrozen food freezes fully in 4 h, as in a freezer (Food.java:839)
-- vanilla's fridge slow-down and rot speed by the sandbox values; any other value is the default 3 (Food.java:713-732)
F.FRIDGE_FACTOR = { 0.4, 0.3, 0.2, 0.1, 0.03, 0 }
F.ROT_SPEED = { 1.7, 1.4, 1.0, 0.7, 0.4 }
function F.fridgeFactor() return F.FRIDGE_FACTOR[SandboxVars.FridgeFactor] or F.FRIDGE_FACTOR[3] end
function F.rotSpeed() return F.ROT_SPEED[SandboxVars.FoodRotSpeed] or F.ROT_SPEED[3] end

-- the fitted fridge part, or nil
function F.part(vehicle)
    local p = vehicle and vehicle:getPartById("TeslaFridge")
    return p and p:getInventoryItem() and p or nil
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
