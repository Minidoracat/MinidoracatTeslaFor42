-- Client: CGlobalObjectSystem mirror of the chargers, charger right-click menu, plug / unplug queue helpers.
-- MinidoracatTesla.onChargerChanged(luaObject, removed) is defined by Cable.lua (TeslaChargerArt); we only call it.
require "Map/CGlobalObjectSystem"
require "Map/CGlobalObject"
require "MinidoracatTesla/Chargers"
require "MinidoracatTesla/ISMinidoracatTeslaPlug"

local T = MinidoracatTesla
T.Charge = T.Charge or {} -- shared with server/Charging.lua in SP
local C = T.Charge

local function changed(o, removed)
    local f = T.onChargerChanged
    if f and o then f(o, removed) end
end

CMinidoracatTeslaCharger = CGlobalObject:derive("CMinidoracatTeslaCharger")
function CMinidoracatTeslaCharger:new(luaSystem, globalObject)
    return CGlobalObject.new(self, luaSystem, globalObject)
end

CMinidoracatTeslaChargerSystem = CGlobalObjectSystem:derive("CMinidoracatTeslaChargerSystem")

function CMinidoracatTeslaChargerSystem:new()
    return CGlobalObjectSystem.new(self, "MinidoracatTeslaCharger")
end

function CMinidoracatTeslaChargerSystem:isValidIsoObject(isoObject)
    return T.chargerInfo(isoObject) ~= nil
end

function CMinidoracatTeslaChargerSystem:newLuaObject(globalObject)
    return CMinidoracatTeslaCharger:new(self, globalObject)
end

function CMinidoracatTeslaChargerSystem:initLuaObjects()
    CGlobalObjectSystem.initLuaObjects(self)
    for i = 1, self:getLuaObjectCount() do changed(self:getLuaObjectByIndex(i)) end
end

-- Java writes the synced fields, then calls this (CGlobalObjectSystem.java:62-77)
function CMinidoracatTeslaChargerSystem:OnLuaObjectUpdated(luaObject)
    changed(luaObject)
end

function CMinidoracatTeslaChargerSystem:removeLuaObjectAt(x, y, z)
    local g = self.system:getObjectAt(x, y, z)
    if g then changed(g:getModData(), true) end
    CGlobalObjectSystem.removeLuaObjectAt(self, x, y, z)
end

CGlobalObjectSystem.RegisterSystemClass(CMinidoracatTeslaChargerSystem)

-- synced Lua object on a square, without vanilla getLuaObjectAt's copy of the IsoObject modData (CGlobalObjectSystem.lua:84-91)
function C.chargerAt(x, y, z)
    local s = CMinidoracatTeslaChargerSystem.instance
    local g = s and s.system:getObjectAt(x, y, z)
    return g and g:getModData() or nil
end

function C.queuePlug(player, vehicle, charger)
    if luautils.walkAdjObject(player, charger) then -- luautils.lua:363-382
        ISTimedActionQueue.add(ISMinidoracatTeslaPlug:new(player, vehicle, charger))
    end
end

function C.queueUnplug(player, vehicle)
    local part = T.Battery.part(vehicle)
    local chg = part and part:getModData().chg
    local sq = chg and getCell():getGridSquare(chg.x, chg.y, chg.z)
    local charger = sq and CMinidoracatTeslaChargerSystem.instance:getIsoObjectOnSquare(sq)
    if charger and not luautils.walkAdjObject(player, charger) then return end
    ISTimedActionQueue.add(ISMinidoracatTeslaUnplug:new(player, vehicle))
end

-- charge card (TeslaDashboard, HUDChargeCard.lua) sends chargeInfo itself; without it, just ask the server to settle
function C.showStatus(player, vehicle)
    local card = T.ChargeCard
    if card and card.open then return card.open(player:getPlayerNum(), vehicle) end
    T.request(player, "chargeInfo", { vid = vehicle:getId() })
end

local function teslasNear(sq, r)
    local out, seen = {}, {}
    local cell = getCell()
    for dx = -r, r do
        for dy = -r, r do
            local s = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            local v = s and s:getVehicleContainer()
            if v and not seen[v] and T.isTesla(v) then
                seen[v] = true
                out[#out + 1] = v
            end
        end
    end
    return out
end

local function disable(option, textKey)
    option.notAvailable = true
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip.description = getText(textKey)
    option.toolTip = tip
end
-- grey a plug / unplug row the way the server would refuse it, with its reason: the shared cable rule (T.mayUseCable,
-- Chargers.lua, which lists the reasons; unplug: T.mayUnplug, the charger's owner too)
local function notOwner(option, player, vehicle, rule)
    local ok, deny = (rule or T.mayUseCable)(player, vehicle)
    if ok then return false end
    disable(option, "IGUI_MinidoracatTesla_Deny_" .. deny)
    return true
end

local function onFill(playerNum, context, worldObjects, test)
    if test then return end
    local charger, info = nil, nil
    for i = 1, #worldObjects do
        info = T.chargerInfo(worldObjects[i])
        if info then charger = worldObjects[i] break end
    end
    if not charger then return end
    local player = getSpecificPlayer(playerNum)
    local sq = charger:getSquare()
    local plugged = T.pluggedCarOn(sq) -- a reused id is no car here: the plug rows show, plugging in takes the charger over
    local c = T.Chargers[info.kind]
    -- a Mobile Connector without power still takes the cable and charges once power comes; plugged or not, say where it works
    if c.genTiles and not T.chargerPowered(info.kind, sq) then
        context:addOption(getText("ContextMenu_MinidoracatTesla_MobileNoPower"), nil, nil).notAvailable = true
    end
    if plugged then
        notOwner(context:addOption(getText("ContextMenu_MinidoracatTesla_Unplug"), player, C.queueUnplug, plugged), player, plugged, T.mayUnplug)
        context:addOption(getText("ContextMenu_MinidoracatTesla_ChargeStatus"), player, C.showStatus, plugged)
        return
    end
    local cars = teslasNear(sq, math.ceil(c.cableTiles) + 2)
    local any = false
    for _, v in ipairs(cars) do
        local part = T.Battery.part(v)
        if part and not part:getModData().chg then
            any = true
            local name = getText("IGUI_VehicleName" .. v:getScript():getName())
            local opt = context:addOption(getText("ContextMenu_MinidoracatTesla_PlugInto", name), player, C.queuePlug, v, charger)
            if not notOwner(opt, player, v) then
                if not part:getInventoryItem() then
                    disable(opt, "IGUI_MinidoracatTesla_Deny_NO_PACK")
                elseif not T.stopped(v) then
                    disable(opt, "IGUI_MinidoracatTesla_Deny_MOVING")
                elseif not T.cableReaches(info.kind, sq:getX(), sq:getY(), sq:getZ(), v) then
                    disable(opt, "IGUI_MinidoracatTesla_Deny_CABLE_SHORT")
                end
            end
        end
    end
    if not any then
        disable(context:addOption(getText("ContextMenu_MinidoracatTesla_Plug"), nil, nil), "Tooltip_MinidoracatTesla_NoCarInReach")
    end
end
Events.OnFillWorldObjectContextMenu.Add(onFill)

-- Move cursor: picking up or rotating a charger with a car plugged in is refused the way the server's
-- ISMoveablesAction:complete refuses it (Chargers.lua T.mayMoveCharger), the reason in the cursor panel (Chargers.lua,
-- getInfoPanelDescription). Wrapped here, not in ISMoveableSpriteProps: its canRotateMoveable gets no character
-- (ISMoveableCursor.lua:628,640). ISMoveableCursor is a server/ file (server/BuildingObjects/), loaded after client/,
-- so the wrap waits for OnGameStart. Pick up keeps vanilla's normal tint when refused (:539), rotate turns red (:629).
function C.guardMoveCursor()
    local Cur = ISMoveableCursor
    if not (Cur and Cur.isValid) then return T.log("charger move guard: ISMoveableCursor.isValid missing") end
    if Cur.teslaGuard then return end
    Cur.teslaGuard = true
    local isValid = Cur.isValid
    function Cur:isValid(square)
        local r = isValid(self, square)
        local mode = ISMoveableCursor.mode[self.player]
        local refused = (self.canCreate and (mode == "pickup" or mode == "rotate") and self.origMoveProps
            and not T.mayMoveCharger(self.character, square, self.origMoveProps.spriteName)) == true
        local was = self.teslaRefused == true
        self.teslaRefused = refused
        if refused then
            self.canCreate = false
            if mode == "rotate" then self.colorMod = ISMoveableCursor.invalidColor end
        end
        if refused or was then
            -- the panel's text is cached per square and object (:270): redo it when the answer changes under a still
            -- cursor (the car locked or unlocked meanwhile); the picture as refused or not (:275)
            if refused ~= was then self.cacheSquare = nil end
            self:setInfoPanel(square, self.cacheObject, self.currentMoveProps)
        end
        return r
    end
end
Events.OnGameStart.Add(C.guardMoveCursor)

-- Plugged-in car (Core.lua CheckOperate.Battery, every frame for the local driver while plugged in; true = hold this
-- frame's input back). While the driver holds the accelerator or reverse, read the way CarController.updateControls
-- reads them (keyboard only for player 0, the joypad triggers, CarController.java:936-971), the vanilla forced brake
-- (BaseVehicle.setForceBrake, as ISStopVehicle.lua does) keeps the car still: in updateControls it sets brake for 1 s
-- after the call (CarController.java:974-980), and brake beats the accelerator (:174-178). It does not count in the
-- millisecond of the call, so it is renewed every BRAKE_MS and that frame's input is held back, never two calls in a
-- row: the one after a renewal updates under that brake, so the controls refresh at least every other frame whatever
-- the frame time (< 1 s), and a pedal held since before the plug is braked too and clears on release.
-- Says why at most every HINT_MS.
C.HINT_MS = 3000
C.BRAKE_MS = 500
local hintAt = 0
local brakeAt, renewed = {}, {} -- vehicle -> ms of the last setForceBrake / the last call renewed it
function T.onPluggedDrive(vehicle)
    local p = vehicle:getDriver()
    if not p or not p:isLocalPlayer() then return false end
    local pad = p:getJoypadBind()
    local pedal = (p:getPlayerNum() == 0 and (isKeyDown(KeybindId.FORWARD) or isKeyDown(KeybindId.BACKWARD)))
        or (pad ~= -1 and (isJoypadRTPressed(pad) or isJoypadLTPressed(pad)))
    if not pedal then renewed[vehicle] = nil; return false end
    local now = getTimestampMs() -- System.currentTimeMillis, the clock forceBrake uses (LuaManager.java:9295-9297)
    if now >= hintAt then
        hintAt = now + C.HINT_MS
        HaloTextHelper.addBadText(p, getText("IGUI_MinidoracatTesla_Deny_CABLE_PLUGGED"))
    end
    if renewed[vehicle] or now - (brakeAt[vehicle] or 0) < C.BRAKE_MS then renewed[vehicle] = nil; return false end
    brakeAt[vehicle], renewed[vehicle] = now, true
    vehicle:setForceBrake()
    return true
end
