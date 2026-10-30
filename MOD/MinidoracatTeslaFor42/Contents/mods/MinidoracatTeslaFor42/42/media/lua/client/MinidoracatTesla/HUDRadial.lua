-- V key / D-pad up vehicle radial menu: adds "Camp Mode", "Charging status" and the Cybertruck's light bar for
-- Teslas, and the bed quality under vanilla "Sleep" (an average bed while camping, Camp.bedType).
-- ISVehicleMenu.showRadialMenu is a toggle (ISVehicleMenu.lua:70-76); remember whether the menu was
-- open BEFORE the vanilla call, because isReallyVisible() lies right after addToUIManager (pitfalls.md UI).
require "Vehicles/ISUI/ISVehicleMenu"
require "ISUI/ISWorldObjectContextMenu"
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

local function onRoofLight(player, vehicle)
    T.request(player, "roofLight", { vid = vehicle:getId() }) -- Truck.lua, server
end

local function addSlices(menu, player, vehicle)
    local part = T.Battery.part(vehicle)
    if not part then return end
    -- phone key in a bag (Keys.lua): vanilla offers "Start Engine" only when haveThisKeyId finds a key (ISVehicleMenu.lua:93-101)
    if vehicle:isDriver(player) and vehicle:isEngineWorking() and not vehicle:isEngineStarted() and not vehicle:isEngineRunning()
        and not SandboxVars.VehicleEasyUse and T.Keys and T.Keys.bagPhoneStarts(player, vehicle) then
        menu:addSlice(getText("ContextMenu_VehicleStartEngine"), getTexture("media/ui/vehicles/vehicle_ignitionON.png"),
            ISVehicleMenu.onStartEngine, player)
    end
    local on = part:getModData().camp ~= nil
    local label = getText(on and "IGUI_MinidoracatTesla_Radial_CampOff" or "IGUI_MinidoracatTesla_Radial_CampOn")
    local ok, why = true, nil
    local Camp = T.Camp
    if Camp and Camp.canEnable then
        if on then ok, why = Camp.canDisable(player, vehicle) else ok, why = Camp.canEnable(player, vehicle) end
    end
    -- the menu shows the hovered slice's text in its centre, one line per \n (RadialMenu.java:157-198):
    -- second line = what turning it on does, or why it is greyed
    if ok then
        local desc = on and "" or ("\n" .. getText("IGUI_MinidoracatTesla_HUD_CampSub"))
        menu:addSlice(label .. desc, getTexture(TEX .. "radial_camp.png"), onCamp, player, vehicle)
    else
        -- greyed: no command
        local reason = why and ("\n" .. T.denyText(why)) or ""
        menu:addSlice(label .. reason, getTexture(TEX .. "radial_camp_off.png"), nil)
    end
    menu:addSlice(getText("IGUI_MinidoracatTesla_Radial_ChargeStatus") .. "\n" .. getText("IGUI_MinidoracatTesla_Tip_ChargeStatus"),
        getTexture(TEX .. "radial_charge.png"), onChargeStatus, player, vehicle)
    -- the light bar, for the driver like the headlights (Truck.lua roofLight)
    if vehicle:getPartById("RoofLight") and vehicle:isDriver(player) then
        local lit = T.Truck and T.Truck.roofLightOn(vehicle)
        menu:addSlice(getText(lit and "IGUI_MinidoracatTesla_Radial_RoofLightOff" or "IGUI_MinidoracatTesla_Radial_RoofLightOn")
            .. "\n" .. getText("IGUI_MinidoracatTesla_Tip_RoofLight"), getTexture(TEX .. "radial_lightbar.png"), onRoofLight, player, vehicle)
    end
    -- vanilla's own "Sleep" slice (ISVehicleMenu.lua:225): second line = vanilla's bed tooltip (Tooltip_BedType)
    for i, s in ipairs(menu.slices) do
        if s.command[1] == ISVehicleMenu.onSleep then
            local bed = ISWorldObjectContextMenu.getBedQuality(player, nil)
            menu:setSliceText(i, s.text .. "\n" .. getText("Tooltip_BedType", getText("Tooltip_BedType_" .. bed))) -- ISRadialMenu.lua:55
        end
    end
end

-- Sleeping while camping counts as an average bed; the server copy gets the same value (server Camp.lua)
local origBed = ISWorldObjectContextMenu.getBedQuality
function ISWorldObjectContextMenu.getBedQuality(playerObj, bed)
    local v = playerObj:getVehicle()
    return (v and T.Camp.bedType and T.Camp.bedType(playerObj, v)) or origBed(playerObj, bed)
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
