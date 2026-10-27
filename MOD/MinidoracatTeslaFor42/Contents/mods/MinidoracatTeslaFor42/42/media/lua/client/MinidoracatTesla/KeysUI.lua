-- Key card and phone key, client side (rules: shared/MinidoracatTesla/Keys.lua; writes: server KeyActions.lua).
--   * Right-click a Tesla outside with its card on you: "Tap key card: unlock/lock" (walk to the driver door, tap).
--   * Right-click a phone while seated with the card: "Set as phone key" (a phone key in another Tesla: "Add this
--     car"); "Remove from phone >" lists its cars.
--   * Getting a Tesla CarKey (transfer, grab, getting out, login) asks the server to swap it for a key card.
--   * Getting out with a phone key starts a 2 Hz distance check that ends once the car locks or you get back in;
--     players without one never run it. Pulling a locked door's handle with the key on you is vanilla already
--     (ISVehicleMenu.onOpenDoor queues unlock + open; canUnlockDoor accepts any Key with the keyId, BaseVehicle.java:1274).
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Keys"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISGrabItemAction"
require "Vehicles/TimedActions/ISExitVehicle"

local T = MinidoracatTesla
local K = T.Keys
T.ClientCommands = T.ClientCommands or {}
local UI = {}
T.KeysUI = UI
UI.stats = { sweeps = 0, watchAdds = 0, watchRemoves = 0, chirps = 0, chirpStops = 0 }

local function denyText(why) return getText("IGUI_MinidoracatTesla_Deny_" .. tostring(why)) end
local function tip(option, text, blocked)
    local tt = ISWorldObjectContextMenu.addToolTip()
    tt.description = text
    option.toolTip = tt
    if blocked then option.notAvailable = true end
end

-- ------------------------------------------------------------------ CarKey -> key card
-- Ask once per CarKey item; the server knows which keyIds are Tesla keys.
local asked = {}
function UI.checkKeys(player)
    if not player or player:getVehicle() then return end -- swapped after getting out (KeyActions.lua K.sweep)
    local inv = player:getInventory()
    if not inv:containsTypeRecurse("Base.CarKey") then return end
    local list, fresh = inv:getAllTypeRecurse("Base.CarKey"), false
    for i = 0, list:size() - 1 do
        local id = list:get(i):getID()
        if not asked[id] then asked[id], fresh = true, true end
    end
    if fresh then
        UI.stats.sweeps = UI.stats.sweeps + 1
        T.request(player, "keySweep")
    end
end

-- Ask a second later, through a one-shot tick: in MP the client puts a transferred item into the inventory when the
-- server's ItemTransactionPacket arrives (ISInventoryTransferAction.lua:854), not inside perform, and after getting out
-- the server must have the player out of the seat too (K.sweep refuses seated players).
local laterP, laterAt
local function laterTick()
    if getTimestampMs() < laterAt then return end
    Events.OnTick.Remove(laterTick)
    laterAt = nil
    UI.checkKeys(laterP)
end
function UI.checkSoon(player)
    if not laterAt then Events.OnTick.Add(laterTick) end
    laterP, laterAt = player, getTimestampMs() + 1000
end

local function after(cls, name, fn)
    local orig = cls and cls[name]
    if not orig then return T.log("keys: missing " .. name) end
    cls[name] = function(self, ...)
        local r = orig(self, ...)
        fn(self)
        return r
    end
end
after(ISInventoryTransferAction, "perform", function(a)
    if a.destContainer and a.destContainer:isInCharacterInventory(a.character) then UI.checkSoon(a.character) end
end)
after(ISGrabItemAction, "perform", function(a) UI.checkSoon(a.character) end)

-- first tick after login (not OnGameStart itself: ParkModesUI.lua pullInbox)
local function loginCheck()
    Events.OnTick.Remove(loginCheck)
    UI.checkKeys(getSpecificPlayer(0))
end
Events.OnGameStart.Add(function() Events.OnTick.Add(loginCheck) end)

-- ------------------------------------------------------------------ walk-away lock
-- Asks again every WATCH_MS until the car shows locked, at most LOCK_TRIES times: the server may still place the
-- player a few steps back (tesla-keys-1026m: a jump of 9 tiles reached the server after the first request).
local watching = {} -- { p, vid, at, tries }
local function watchTick()
    local now = getTimestampMs()
    for i = #watching, 1, -1 do
        local w = watching[i]
        if now >= w.at then
            w.at = now + K.WATCH_MS
            local v = getVehicleById(w.vid)
            if not v or w.p:getVehicle() or w.p:isDead() or v:areAllDoorsLocked() or w.tries >= K.LOCK_TRIES then
                table.remove(watching, i)
            elseif w.p:DistTo(v) >= K.LOCK_DIST then
                w.tries = w.tries + 1
                T.request(w.p, "autoLock", { vid = w.vid })
            end
        end
    end
    if #watching == 0 then
        Events.OnTick.Remove(watchTick)
        UI.stats.watchRemoves = UI.stats.watchRemoves + 1
    end
end

function UI.watch(player, vehicle)
    for _, w in ipairs(watching) do
        if w.p == player then w.vid, w.at, w.tries = vehicle:getId(), 0, 0; return end
    end
    watching[#watching + 1] = { p = player, vid = vehicle:getId(), at = 0, tries = 0 }
    if #watching == 1 then
        Events.OnTick.Add(watchTick)
        UI.stats.watchAdds = UI.stats.watchAdds + 1
    end
end
function UI.watchCount() return #watching end

-- the server said why it will not lock: show it, stop asking (watchTick removes the hook on its next pass)
T.ClientCommands.autoLockSkip = function(args)
    if not args.reason then return end
    for _, w in ipairs(watching) do
        if w.vid == args.vid then w.tries = K.LOCK_TRIES end
    end
    local p = getSpecificPlayer(0)
    if p then HaloTextHelper.addBadText(p, getText("IGUI_MinidoracatTesla_Deny_" .. tostring(args.reason))) end
end

-- the car is gone from getVehicle() once perform has run, so read it first
local exitPerform = ISExitVehicle.perform
function ISExitVehicle:perform(...)
    local p, v = self.character, self.character:getVehicle()
    local r = exitPerform(self, ...)
    if v and T.isTesla(v) then
        -- a spawn-time CarKey comes back from the ignition on shutdown
        if p:getInventory():containsTypeRecurse("Base.CarKey") then UI.checkSoon(p) end
        if K.phoneKey(p, v) then UI.watch(p, v) end
    end
    return r
end

-- ------------------------------------------------------------------ key card tap (client-only action: no
-- complete(), so it is not a NetTimedAction, LuaTimedActionNew.java:78-80; the server checks the keyTap command)
ISMinidoracatTeslaKeyTap = ISBaseTimedAction:derive("ISMinidoracatTeslaKeyTap")

function ISMinidoracatTeslaKeyTap:isValid()
    return not self.character:getVehicle() and K.card(self.character, self.vehicle) ~= nil
end
function ISMinidoracatTeslaKeyTap:start()
    self.character:faceThisObject(self.vehicle)
end
function ISMinidoracatTeslaKeyTap:perform()
    T.request(self.character, "keyTap", { vid = self.vehicle:getId() })
    ISBaseTimedAction.perform(self)
end
function ISMinidoracatTeslaKeyTap:new(character, vehicle)
    local o = ISBaseTimedAction.new(self, character)
    o.vehicle = vehicle
    o.maxTime = character:isTimedActionInstant() and 1 or 20
    return o
end

function UI.tap(player, vehicle)
    local door = vehicle:getPassengerDoor(0)
    local area = door and door:getArea()
    if area and K.readerDist(player, vehicle) > K.TAP_RANGE then
        ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(player, vehicle, area))
    end
    ISTimedActionQueue.add(ISMinidoracatTeslaKeyTap:new(player, vehicle))
end

function UI.vehicleOptions(player, context, vehicle)
    if not K.card(player, vehicle) then return end -- strangers see nothing
    local key = vehicle:areAllDoorsLocked() and "ContextMenu_MinidoracatTesla_TapUnlock" or "ContextMenu_MinidoracatTesla_TapLock"
    local opt = context:addOption(getText(key), player, UI.tap, vehicle)
    tip(opt, getText("Tooltip_MinidoracatTesla_TapCard"))
    return opt
end

function UI.fillMenu(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end
    -- same pick as vanilla ISVehicleMenu.OnFillWorldObjectContextMenu (ISVehicleMenu.lua:49)
    local vehicle = IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
    if vehicle and T.isTesla(vehicle) then UI.vehicleOptions(player, context, vehicle) end
end
Events.OnFillWorldObjectContextMenu.Add(UI.fillMenu)

-- ------------------------------------------------------------------ phone pairing (one phone key, several cars)
local function onPair(player, vehicle, phone)
    T.request(player, "phonePair", { vid = vehicle:getId(), id = phone:getID() })
end

-- first pairing: "Set as phone key"; a phone key seated in a Tesla it does not open yet: "Add this car (N paired)"
function UI.phoneOption(player, context, phone)
    local v = player:getVehicle()
    local label = getText("ContextMenu_MinidoracatTesla_PairPhone")
    if phone:getFullType() == K.PHONE_KEY and v and T.isTesla(v) and not K.pairedWith(phone, v:getKeyId()) then
        label = getText("ContextMenu_MinidoracatTesla_AddCar", tostring(#K.pairedIds(phone)))
    end
    local opt = context:addOption(label, player, onPair, v, phone)
    local ok, why = K.canPair(player, v, phone)
    tip(opt, ok and getText("Tooltip_MinidoracatTesla_PairPhone") or denyText(why), not ok)
    return opt
end

local function onUnpair(player, phone, keyId)
    T.request(player, "phoneUnpair", { id = phone:getID(), key = keyId })
end
-- "Remove from phone >": one entry per car, in pairing order (the car names come from the item's mirror; the paint
-- from the app's last view of it, PhoneApp.carLabel). Greyed in a car: the server refuses there (KeyActions phoneUnpair)
function UI.unpairOption(player, context, phone)
    local ids = K.pairedIds(phone)
    local cars = phone:getModData()[K.PAIRED_CARS]
    local opt = context:addOption(getText("ContextMenu_MinidoracatTesla_Unpair"))
    if player:getVehicle() then
        tip(opt, denyText("NOT_OUTSIDE"), true)
        return opt
    end
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(opt, sub)
    local App = T.PhoneApp
    for i, keyId in ipairs(ids) do
        local car = type(cars) == "table" and cars[i] or nil
        local label = App and App.carLabel(keyId, car) or getText("IGUI_VehicleName" .. tostring(car))
        sub:addOption(label, player, onUnpair, phone, keyId)
    end
    return opt, sub
end

-- "Open Tesla App" right after "Set up as phone key" (plan-phone-app-1027): a paired phone key opens the app on its
-- car (client/MinidoracatTesla/PhoneApp.lua); an unpaired phone shows it greyed with how to pair.
local function onApp(playerNum, phone)
    local App = T.PhoneApp
    if App then App.open(playerNum, { keyId = phone:getKeyId() }) end
end
function UI.appOption(playerNum, context, phone)
    local opt = context:addOption(getText("ContextMenu_MinidoracatTesla_OpenApp"), playerNum, onApp, phone)
    if phone:getFullType() ~= K.PHONE_KEY then tip(opt, getText("Tooltip_MinidoracatTesla_AppNotPaired"), true) end
    return opt
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    for _, entry in ipairs(items) do
        local item = entry
        if type(entry) == "table" then item = entry.items and entry.items[1] end
        local ft = item and item:getFullType()
        if ft == K.PHONE or ft == K.PHONE_KEY then
            local player = getSpecificPlayer(playerNum)
            UI.phoneOption(player, context, item)
            UI.appOption(playerNum, context, item)
            if ft == K.PHONE_KEY then UI.unpairOption(player, context, item) end
            return
        end
    end
end)

-- ------------------------------------------------------------------ server -> client
local function good(key, args)
    local p = getSpecificPlayer(0)
    local text = getText(key, getText("IGUI_VehicleName" .. tostring(args.car)), tostring(args.n))
    T.log("halo " .. key .. " vid=" .. tostring(args.vid))
    if p then HaloTextHelper.addGoodText(p, text) end
end
T.ClientCommands.autoLocked = function(args) good("IGUI_MinidoracatTesla_AutoLocked", args) end
T.ClientCommands.phonePaired = function(args)
    good((args.n or 1) > 1 and "IGUI_MinidoracatTesla_PhoneAdded" or "IGUI_MinidoracatTesla_PhonePaired", args)
end
T.ClientCommands.phoneUnpaired = function(args)
    good("IGUI_MinidoracatTesla_PhoneRemoved", args)
    local App = T.PhoneApp -- the MiniMap drops the removed car's marker now, not at its next 10 s check
    if App then App.seenRev = App.seenRev + 1 end
end

-- Lock confirmation chirp (Keys.lua K.CHIRP): the vanilla horn event on the car's emitter (FMODSoundEmitter, no
-- WorldSoundManager: zombies do not hear it), stopped after K.CHIRP_MS by a one-shot OnTick removed when empty.
local chirps = {}
local function chirpTick()
    local now = getTimestampMs()
    for i = #chirps, 1, -1 do
        local c = chirps[i]
        if now - c.at >= K.CHIRP_MS then
            c.emitter:stopSound(c.id)
            table.remove(chirps, i)
            UI.stats.chirpStops = UI.stats.chirpStops + 1
        end
    end
    if #chirps == 0 then Events.OnTick.Remove(chirpTick) end
end
T.ClientCommands.keyChirp = function(args)
    local v = args and args.vid and getVehicleById(args.vid)
    if not v then return end
    local emitter = v:getEmitter()
    local id = emitter:playSound(K.CHIRP)
    if not id or id == 0 then return end
    if #chirps == 0 then Events.OnTick.Add(chirpTick) end
    chirps[#chirps + 1] = { emitter = emitter, id = id, at = getTimestampMs() }
    UI.stats.chirps = UI.stats.chirps + 1
    T.log("key chirp vid=" .. v:getId())
end
function UI.chirpCount() return #chirps end
