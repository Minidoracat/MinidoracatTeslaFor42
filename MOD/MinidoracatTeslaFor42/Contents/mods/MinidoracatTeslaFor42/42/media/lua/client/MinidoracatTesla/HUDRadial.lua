-- V key / D-pad up vehicle radial menu: adds "Camp Mode" and "Charging status" for Teslas, Powershare, the bed
-- outlet and the light bar for a Cybertruck (Specs powershare / bedOutlet, part RoofLight), and the bed quality under
-- vanilla "Sleep" (an average bed while camping, Camp.bedType).
-- ISVehicleMenu.showRadialMenu is a toggle (ISVehicleMenu.lua:70-76); remember whether the menu was
-- open BEFORE the vanilla call, because isReallyVisible() lies right after addToUIManager (pitfalls.md UI).
require "Vehicles/ISUI/ISVehicleMenu"
require "ISUI/ISWorldObjectContextMenu"
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Chargers"
require "MinidoracatTesla/HUD"

local T = MinidoracatTesla
local TEX = "media/textures/MinidoracatTesla/HUD/"
-- The centre text's lines (UIFont.Medium, RadialMenu.java:106) stay inside the icon ring: ISRadialMenu's radii 100 /
-- 200 (ISPlayerData.lua:146) put the 64-px icons' inner edge 118 px out, about 220 px across at the text's rows.
-- One line past that ran over the icons (E2E tesla-ctlang-1031m-ko: Korean "충전 케이블이 꽂혀 있으면 ...").
local LINE_W = 220
-- a slice's second line, broken to the ring's width (Core.lua T.wrapText)
local function line2(s) return "\n" .. T.wrapText(s, LINE_W, UIFont.Medium) end

local function onCamp(player, vehicle)
    T.HUD.toggleCamp(player, vehicle)
end

local function onChargeStatus(player, vehicle)
    T.ChargeCard.open(player:getPlayerNum(), vehicle)
end

local function onRoofLight(player, vehicle)
    T.request(player, "roofLight", { vid = vehicle:getId() }) -- Truck.lua, server
end

-- Cybertruck switches (server Powershare.lua PS.set): the charge cable's rule (T.mayUseCable), like the charge card.
-- id: "Powershare" / "Outlet" (texts and icons), cmd: the server command prefix, on: switched on now, note: switched on
-- but giving nothing, why (the phone app's line, T.psStopWhy / T.outletWhy)
local function onSwitch(player, vehicle, cmd, on)
    T.request(player, cmd .. (on and "Off" or "On"), { vid = vehicle:getId() })
end
local function addSwitch(menu, player, vehicle, id, cmd, on, note)
    local label = getText("IGUI_MinidoracatTesla_Radial_" .. id .. (on and "Off" or "On"))
    local ok, why = T.mayUseCable(player, vehicle)
    local icon = TEX .. "radial_" .. id:lower()
    if ok then
        local desc = on and (note and line2(note) or "") or line2(getText("IGUI_MinidoracatTesla_HUD_" .. id .. "Sub"))
        menu:addSlice(label .. desc, getTexture(icon .. ".png"), onSwitch, player, vehicle, cmd, on)
    else
        menu:addSlice(label .. line2(T.denyText(why)), getTexture(icon .. "_off.png"), nil)
    end
end

local function addSlices(menu, player, vehicle)
    local part = T.Battery.part(vehicle)
    if not part then return end
    -- phone key or key card in a wallet or bag (Keys.lua bagKeyStarts): the car takes it as a key, but vanilla looks with
    -- haveThisKeyId and offers hotwiring instead of "Start Engine" (ISVehicleMenu.lua:93-120); that slice becomes "Start
    -- Engine" in place (no such slice: one more at the end)
    if vehicle:isDriver(player) and vehicle:isEngineWorking() and not vehicle:isEngineStarted() and not vehicle:isEngineRunning()
        and not SandboxVars.VehicleEasyUse and T.Keys and T.Keys.bagKeyStarts(player, vehicle) then
        local text, tex = getText("ContextMenu_VehicleStartEngine"), getTexture("media/ui/vehicles/vehicle_ignitionON.png")
        local skill, at = getText("ContextMenu_VehicleHotwireSkill"), nil
        for i, s in ipairs(menu.slices) do
            if s.command[1] == ISVehicleMenu.onHotwire or s.text == skill then at = i; break end
        end
        if at then
            menu.slices[at].command = { ISVehicleMenu.onStartEngine, player } -- what a click runs (ISRadialMenu.lua:18-27,71-76)
            menu:setSliceText(at, text)
            menu:setSliceTexture(at, tex)
        else
            menu:addSlice(text, tex, ISVehicleMenu.onStartEngine, player)
        end
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
        local desc = on and "" or line2(getText("IGUI_MinidoracatTesla_HUD_CampSub"))
        menu:addSlice(label .. desc, getTexture(TEX .. "radial_camp.png"), onCamp, player, vehicle)
    else
        -- greyed: no command
        local reason = why and line2(T.denyText(why)) or ""
        menu:addSlice(label .. reason, getTexture(TEX .. "radial_camp_off.png"), nil)
    end
    menu:addSlice(getText("IGUI_MinidoracatTesla_Radial_ChargeStatus") .. line2(getText("IGUI_MinidoracatTesla_Tip_ChargeStatus")),
        getTexture(TEX .. "radial_charge.png"), onChargeStatus, player, vehicle)
    local spec, md = T.spec(vehicle), part:getModData()
    if spec.powershare then
        local stop = T.psStopWhy(part)
        local note = stop == "spot" and getText("IGUI_MinidoracatTesla_App_PsStoppedSpot")
            or stop and getText("IGUI_MinidoracatTesla_App_PsStoppedSub", tostring(T.psFloor(part))) or nil
        addSwitch(menu, player, vehicle, "Powershare", "ps", md.ps ~= nil and md.ps.on == true, note)
    end
    if spec.bedOutlet then
        local why = md.outlet and T.outletWhy(vehicle, part)
        addSwitch(menu, player, vehicle, "Outlet", "outlet", md.outlet == true,
            why and getText("IGUI_MinidoracatTesla_App_OutletWhy_" .. why) or nil)
    end
    -- the light bar, for the driver like the headlights (Truck.lua roofLight)
    if vehicle:getPartById("RoofLight") and vehicle:isDriver(player) then
        local lit = T.Truck and T.Truck.roofLightOn(vehicle)
        menu:addSlice(getText(lit and "IGUI_MinidoracatTesla_Radial_RoofLightOff" or "IGUI_MinidoracatTesla_Radial_RoofLightOn")
            .. line2(getText("IGUI_MinidoracatTesla_Tip_RoofLight")), getTexture(TEX .. "radial_lightbar.png"), onRoofLight, player, vehicle)
    end
    -- vanilla's own "Sleep" slice (ISVehicleMenu.lua:225): second line = vanilla's bed tooltip (Tooltip_BedType)
    for i, s in ipairs(menu.slices) do
        if s.command[1] == ISVehicleMenu.onSleep then
            local bed = ISWorldObjectContextMenu.getBedQuality(player, nil)
            menu:setSliceText(i, s.text .. line2(getText("Tooltip_BedType", getText("Tooltip_BedType_" .. bed)))) -- ISRadialMenu.lua:55
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
