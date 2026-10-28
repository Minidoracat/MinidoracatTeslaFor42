-- EV names for the part ids a Tesla reuses (GasTank = high voltage battery, Engine = drive unit, ...), Tesla only.
-- Vanilla builds every part name as getText("IGUI_VehiclePart" .. id) (ISVehicleMechanics.lua:64, :1076) and the
-- vehicle script has no per-car display name (VehicleScript.java:924-949), so while the methods below run for a
-- Tesla, getText maps the vanilla keys to ours (T.partNameKey, the tables in shared Core.lua); the inventory window's
-- container buttons are renamed at the end.
-- Other cars and every other caller see vanilla getText.
-- The new Frunk part needs no mapping: IGUI_VehiclePartFrunk is our own key (no vanilla part has that id).
require "Vehicles/ISUI/ISVehicleMechanics"
require "Vehicles/ISUI/ISVehicleMenu"
require "ISUI/ISInventoryPage"
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local unpack = unpack or table.unpack

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
