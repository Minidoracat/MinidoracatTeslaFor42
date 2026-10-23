-- V key / D-pad up vehicle radial menu: adds "Camp Mode" and "Charging status" for Teslas.
-- ISVehicleMenu.showRadialMenu is a toggle (ISVehicleMenu.lua:70-76); remember whether the menu was
-- open BEFORE the vanilla call, because isReallyVisible() lies right after addToUIManager (pitfalls.md UI).
require "Vehicles/ISUI/ISVehicleMenu"
require "MinidoracatTesla/Core"
require "MinidoracatTesla/HUD"

local T = MinidoracatTesla
local TEX = "media/textures/MinidoracatTesla/HUD/"

local function onCamp(player, vehicle)
    T.HUD.toggleCamp(player, vehicle)
end

local function onChargeStatus(player, vehicle)
    T.ChargeCard.open(player:getPlayerNum(), vehicle)
end

local function addSlices(menu, player, vehicle)
    local part = T.Battery.part(vehicle)
    if not part then return end
    local on = part:getModData().camp ~= nil
    local label = getText(on and "IGUI_MinidoracatTesla_Radial_CampOff" or "IGUI_MinidoracatTesla_Radial_CampOn")
    local ok, why = true, nil
    local Camp = T.Camp
    if Camp and Camp.canEnable then
        if on then ok, why = Camp.canDisable(player, vehicle) else ok, why = Camp.canEnable(player, vehicle) end
    end
    if ok then
        menu:addSlice(label, getTexture(TEX .. "radial_camp.png"), onCamp, player, vehicle)
    else
        -- greyed: no command, reason on a second line (RadialMenu.java:166-190 splits on \n)
        local reason = why and ("\n" .. getText("IGUI_MinidoracatTesla_Deny_" .. why)) or ""
        menu:addSlice(label .. reason, getTexture(TEX .. "radial_camp_off.png"), nil)
    end
    menu:addSlice(getText("IGUI_MinidoracatTesla_Radial_ChargeStatus"), getTexture(TEX .. "radial_charge.png"),
        onChargeStatus, player, vehicle)
end

local orig = ISVehicleMenu.showRadialMenu
function ISVehicleMenu.showRadialMenu(playerObj)
    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
    local wasOpen = menu:isReallyVisible()
    orig(playerObj)
    if wasOpen then return end
    local sc = UIManager.getSpeedControls()
    if sc and sc:getCurrentGameSpeed() == 0 then return end -- vanilla returned early (:58-59)
    local vehicle = playerObj:getVehicle()
    if vehicle and T.isTesla(vehicle) then addSlices(menu, playerObj, vehicle) end
end
