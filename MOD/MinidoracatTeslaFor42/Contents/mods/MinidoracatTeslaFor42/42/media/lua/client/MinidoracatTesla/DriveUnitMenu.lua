-- Mechanics window, Tesla drive unit: vanilla's "Take Engine Parts" / "Repair Engine" (ISVehicleMechanics.lua:324-341,
-- hardcoded to Base.EngineParts) become "Take Drive Unit Parts" / "Repair Drive Unit" with our item. The two options are
-- rewritten in place after vanilla builds the menu, so the order stays. Requirements, tooltip layout (:641-686) and the
-- queued actions (:418-493) follow vanilla.
require "Vehicles/ISUI/ISVehicleMechanics"
require "MinidoracatTesla/DriveUnit"

local T, DU = MinidoracatTesla, MinidoracatTesla.DriveUnit

-- ISVehicleMechanics.onRepairEngine / onTakeEngineParts (:418-449, :463-493)
local function queue(playerObj, part, cls, withParts)
    if playerObj:getVehicle() then ISVehicleMenu.onExit(playerObj) end
    local _, tagToItem = VehicleUtils.getItems(playerObj:getPlayerNum())
    local wrench = tagToItem[ItemTag.WRENCH][1]
    ISVehiclePartMenu.toPlayerInventory(playerObj, wrench)
    if withParts then ISVehiclePartMenu.toPlayerInventory(playerObj, playerObj:getInventory():getFirstTypeRecurse(DU.ITEM)) end
    local vehicle = part:getVehicle()
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, part:getArea()))
    local door = vehicle:getPartById("EngineDoor")
    local lid = door and door:getDoor() and door:getInventoryItem() and not door:getDoor():isOpen() and door or nil
    if lid then
        if lid:getDoor():isLocked() and VehicleUtils.RequiredKeyNotFound(lid, playerObj) then
            ISTimedActionQueue.add(ISUnlockVehicleDoor:new(playerObj, lid))
        end
        ISTimedActionQueue.add(ISOpenVehicleDoor:new(playerObj, vehicle, lid))
    end
    ISTimedActionQueue.add(cls:new(playerObj, part, wrench, 300))
    if lid then ISTimedActionQueue.add(ISCloseVehicleDoor:new(playerObj, vehicle, lid)) end
end

function DU.onRepair(playerObj, part) queue(playerObj, part, ISMinidoracatTeslaRepairDriveUnit, true) end
function DU.onTake(playerObj, part) queue(playerObj, part, ISMinidoracatTeslaTakeDriveUnitParts, false) end

-- ISVehicleMechanics:doMenuTooltip "takeengineparts" / "repairengine" (:628-686) with our item and texts
local function tooltip(chr, part, option, wrench, repair)
    local g, b = ISVehicleMechanics.ghs, ISVehicleMechanics.bhs
    local cond, perk = part:getCondition(), chr:getPerkLevel(Perks.Mechanics)
    local level = part:getVehicle():getScript():getEngineRepairLevel()
    local d = getText("Tooltip_craft_Needs") .. " : <LINE>"
    if repair and cond >= 100 then
        d = d .. " " .. b .. " " .. getText("Tooltip_MinidoracatTesla_DriveUnitCondition", cond) .. " <LINE>"
    elseif not repair and cond < 10 then
        d = d .. " " .. b .. " " .. getText("Tooltip_MinidoracatTesla_DriveUnitCondition", cond .. "/10") .. " <LINE>"
    end
    d = d .. " " .. (perk < level and b or g) .. getText("IGUI_perks_Mechanics") .. " " .. perk .. "/" .. level .. " <LINE>"
    d = d .. " " .. (wrench and g .. getItemDisplayName("Base.Wrench") .. " 1/1 <LINE>" or b .. getItemDisplayName("Base.Wrench") .. " 0/1 <LINE>")
    if repair then
        local name = getItemDisplayName(DU.ITEM)
        d = d .. " " .. (DU.count(chr) > 0 and g .. name .. " <LINE>" or b .. name .. " 0/1 <LINE>")
    else
        d = d .. " " .. b .. " " .. getText("Tooltip_MinidoracatTesla_TakeDriveUnitPartsWarning")
    end
    local tip = ISToolTip:new()
    tip:initialise()
    tip:setVisible(false)
    tip.description = d
    option.toolTip = tip
end

local doPartContextMenu = ISVehicleMechanics.doPartContextMenu
function ISVehicleMechanics:doPartContextMenu(part, x, y)
    doPartContextMenu(self, part, x, y)
    if part:getId() ~= "Engine" or not self.context or not T.isTesla(part:getVehicle()) then return end
    local take, repair = getText("IGUI_TakeEngineParts"), getText("IGUI_RepairEngine")
    local playerObj = getSpecificPlayer(self.playerNum)
    local wrench = ISVehicleMechanics:getWrench(self.chr)
    for _, opt in ipairs(self.context.options) do
        local isRepair = opt.name == repair
        if isRepair or opt.name == take then
            local ok = isRepair and DU.canRepair(self.chr, part, wrench) or not isRepair and DU.canTake(self.chr, part, wrench)
            opt.name = getText(isRepair and "IGUI_MinidoracatTesla_RepairDriveUnit" or "IGUI_MinidoracatTesla_TakeDriveUnitParts")
            opt.target, opt.onSelect, opt.param1 = playerObj, isRepair and DU.onRepair or DU.onTake, part
            opt.notAvailable = not ok
            tooltip(self.chr, part, opt, wrench, isRepair)
        end
    end
    self.context:setWidth(self.context:calcWidth())
end
