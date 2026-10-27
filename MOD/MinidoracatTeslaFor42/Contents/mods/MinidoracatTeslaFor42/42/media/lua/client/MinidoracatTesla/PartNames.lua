-- EV names for the part ids a Tesla reuses (GasTank = high voltage battery, Engine = drive unit, ...), Tesla only.
-- Vanilla builds every part name as getText("IGUI_VehiclePart" .. id) (ISVehicleMechanics.lua:64, :1076) and the
-- vehicle script has no per-car display name (VehicleScript.java:924-949), so while the methods below run for a
-- Tesla, getText maps the vanilla keys to ours; the inventory window's container buttons are renamed at the end.
-- Other cars and every other caller see vanilla getText.
-- The new Frunk part needs no mapping: IGUI_VehiclePartFrunk is our own key (no vanilla part has that id).
require "Vehicles/ISUI/ISVehicleMechanics"
require "Vehicles/ISUI/ISVehicleMenu"
require "ISUI/ISInventoryPage"
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local unpack = unpack or table.unpack

-- vanilla key -> Tesla key
T.PartNames = {
    IGUI_VehiclePartGasTank = "IGUI_MinidoracatTesla_Part_GasTank",
    IGUI_VehiclePartEngine = "IGUI_MinidoracatTesla_Part_Engine",
    IGUI_VehiclePartBattery = "IGUI_MinidoracatTesla_Part_Battery",
    IGUI_VehiclePartHeater = "IGUI_MinidoracatTesla_Part_Heater",
    IGUI_VehiclePartEngineDoor = "IGUI_MinidoracatTesla_Part_EngineDoor",
    IGUI_VehiclePartTruckBed = "IGUI_MinidoracatTesla_Part_TruckBed",
    IGUI_VehiclePartTrunkDoor = "IGUI_MinidoracatTesla_Part_TrunkDoor",
    IGUI_VehiclePartCatengine = "IGUI_MinidoracatTesla_PartCat_engine", -- category header (ISVehicleMechanics.lua:59)
    Tooltip_outoffuel = "IGUI_MinidoracatTesla_OutOfCharge",        -- empty GasTank (:1085, :1265)
    IGUI_EnginePower = "IGUI_MinidoracatTesla_MotorPower",           -- header "Engine Power: N hp" (:1178)
    IGUI_Vehicle_EngineLoudness = "IGUI_MinidoracatTesla_MotorLoudness", -- drive unit detail (:1325-1327)
    IGUI_Vehicle_EngineQuality = "IGUI_MinidoracatTesla_MotorQuality",
    IGUI_OpenHood = "IGUI_MinidoracatTesla_OpenFrunk",               -- outside radial menu (ISVehicleMenu.lua:318-337)
    IGUI_CloseHood = "IGUI_MinidoracatTesla_CloseFrunk",
    IGUI_LockHood = "IGUI_MinidoracatTesla_LockFrunk",
    IGUI_UnlockHood = "IGUI_MinidoracatTesla_UnlockFrunk",
}
-- per car, on top of T.PartNames (vehicle script full name -> vanilla key -> Tesla key)
T.CarPartNames = {
    -- a sedan's trunk lid, not a liftgate (Model 3 owner's manuals; the Model Y keeps Liftgate)
    ["Base.MinidoracatTesla_Model3"] = { IGUI_VehiclePartTrunkDoor = "IGUI_MinidoracatTesla_Part_TrunkLid" },
}
-- the Tesla key for a vanilla key on this car (script full name), or nil
function T.partNameKey(script, key)
    local car = T.CarPartNames[script]
    return car and car[key] or T.PartNames[key]
end

local vanillaGetText -- set only while a wrapped method runs for a Tesla
local script -- that Tesla's script name
local function teslaGetText(key, ...)
    return vanillaGetText(T.partNameKey(script, key) or key, ...)
end

-- Wrap owner[name]; vehicleOf(...) picks the car from the call's arguments.
function T.withPartNames(owner, name, vehicleOf)
    local orig = owner[name]
    owner[name] = function(...)
        local v = vehicleOf(...)
        if vanillaGetText or not T.isTesla(v) then return orig(...) end
        script = v:getScriptName()
        vanillaGetText, getText = getText, teslaGetText
        local r = { pcall(orig, ...) }
        getText, vanillaGetText = vanillaGetText, nil -- restore even when orig errors
        if not r[1] then error(r[2]) end
        return unpack(r, 2)
    end
end

local function windowVehicle(self) return self.vehicle end
T.withPartNames(ISVehicleMechanics, "initParts", windowVehicle)
-- render draws the car overlay tooltips and the selected part's detail (ISVehicleMechanics.lua:1142,1221): one wrap per frame
T.withPartNames(ISVehicleMechanics, "render", windowVehicle)
-- same vehicle pick as the menu itself (ISVehicleMenu.lua:278,294)
T.withPartNames(ISVehicleMenu, "showRadialMenuOutside", function(playerObj)
    return not playerObj:getVehicle() and ISVehicleMenu.getVehicleToInteractWith(playerObj) or nil
end)

-- container buttons of the loot / inventory window: refreshBackpacks names them getText("IGUI_VehiclePart" .. type)
-- before calling addContainerButton (ISInventoryPage.lua:1586,1610,1766), for whatever cars are in reach
local addContainerButton = ISInventoryPage.addContainerButton
function ISInventoryPage:addContainerButton(container, texture, name, tooltip)
    local part = container and container:getVehiclePart() -- ItemContainer.java:3427
    local v = part and part:getVehicle()
    local key = v and T.isTesla(v) and T.partNameKey(v:getScriptName(), "IGUI_VehiclePart" .. part:getId())
    if key then name, tooltip = getText(key), getText(key) end
    return addContainerButton(self, container, texture, name, tooltip)
end
