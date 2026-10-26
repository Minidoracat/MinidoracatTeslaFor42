-- Inventory right-click while seated in a Tesla: "Charge from car outlet" on dry cells and car batteries
-- (CampPower.lua). Greyed with the reason when camp is off, the pack is low or the item is full.
require "MinidoracatTesla/CampPower"

local T = MinidoracatTesla
local C = T.Camp

local function onCharge(player, vehicle, items)
    for _, item in ipairs(items) do
        ISInventoryPaneContextMenu.transferIfNeeded(player, item)
        ISTimedActionQueue.add(ISMinidoracatTeslaChargeItem:new(player, vehicle, item))
    end
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    local vehicle = player and player:getVehicle()
    if not T.Battery.part(vehicle) then return end
    local ready, why = {}, nil
    for _, item in ipairs(ISInventoryPane.getActualItems(items)) do
        if C.Chargeable[item:getFullType()] then
            local ok, w = C.canChargeItem(player, vehicle, item)
            if ok then ready[#ready + 1] = item else why = why or w end
        end
    end
    if #ready == 0 and not why then return end
    local opt = context:addOption(getText("ContextMenu_MinidoracatTesla_ChargeItem"), player, onCharge, vehicle, ready)
    if #ready == 0 then
        opt.notAvailable = true
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip.description = T.denyText(why)
        opt.toolTip = tip
    end
end)
