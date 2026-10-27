-- Key card and phone key (user 2026-10-26: "like the real car"; owner's manual, Keys).
-- Both are vanilla Key items (ItemType base:key) carrying the car's keyId, so vanilla unlock, start and ignition accept
-- them (ItemContainer.haveThisKeyId, ItemContainer.java:3242-3256). Rules here are shared by the server handlers
-- (server/MinidoracatTesla/KeyActions.lua) and the client menus (client/MinidoracatTesla/KeysUI.lua).
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
T.Keys = T.Keys or {}
local K = T.Keys

K.CARD = "Base.MinidoracatTesla_KeyCard"
K.PHONE = "Base.MinidoracatTesla_Phone"         -- not paired: a plain item
K.PHONE_KEY = "Base.MinidoracatTesla_PhoneKey"  -- paired: a Key with the car's keyId
K.TAP_RANGE = 1.5   -- key card reader (driver-side B-pillar): tiles from the driver door's area centre
-- Walk-away lock: tiles from the car centre. The car is ~4 tiles long, so walking round to the trunk (~2.5) never
-- locks it; 6 tiles (1 tile = 1 m, Core.lua) is a few metres past the body, like leaving Bluetooth range.
K.LOCK_DIST = 6
K.LOCK_SLACK = 1    -- the server sees the player up to a step behind the client that asked
K.WATCH_MS = 500    -- client distance check while a phone key holder walks away
K.LOCK_TRIES = 6    -- client asks at most this many times (once per WATCH_MS) once it is LOCK_DIST away
-- Lock confirmation (user 2026-10-26: candidate A): the vanilla standard horn on the car's own emitter, stopped after
-- CHIRP_MS, played by each client within CHIRP_TILES. Emitter only, no world sound: zombies do not hear it.
K.CHIRP = "VehicleHornStandard" -- sounds_vehicle_standard.txt (event Vehicle/Standard/Horn)
K.CHIRP_MS = 150
K.CHIRP_TILES = 40
-- Tesla app on the phone key (user 2026-10-27: like the real car). Owner's manual, Mobile App: phone and car talk over
-- the cellular network, or over Bluetooth when the phone key is close. Grid up = phone network up: any distance, as
-- long as the server has the car loaded. Grid down: Bluetooth only, BT_RANGE tiles (1 tile = 1 m).
K.BT_RANGE = 30

local function sameKey(item, keyId) return item:getKeyId() == keyId end

-- This car's card / phone key anywhere on the player: wallet, keyring, bags (ItemContainer.java:1576).
function K.card(player, vehicle)
    return player:getInventory():getFirstTypeEvalArgRecurse(K.CARD, sameKey, vehicle:getKeyId())
end
-- the phone key for car `keyId` anywhere on the player (the app names its car by keyId: server/MinidoracatTesla/Remote.lua)
function K.phoneKeyFor(player, keyId)
    return player:getInventory():getFirstTypeEvalArgRecurse(K.PHONE_KEY, sameKey, keyId)
end
function K.phoneKey(player, vehicle) return K.phoneKeyFor(player, vehicle:getKeyId()) end

-- How the app reaches a loaded car right now: "net", "bt", or nil (no link: the app shows the last record only).
-- The server asks again before every command; the grid state is IsoWorld.hydroPowerOn (IsoWorld.java:3314), which
-- AmbientSoundManager switches off at the sandbox shut-off (AmbientSoundManager.java:228-243).
function K.appReach(player, vehicle)
    if not vehicle then return nil end
    if getWorld():isHydroPowerOn() then return "net" end
    if player:DistTo(vehicle) <= K.BT_RANGE then return "bt" end
    return nil
end

-- The phone app (PhoneApp.lua): where the car is from the player: compass words (north = -y) and the screen angle of the arrow. The iso screen
-- shows a world step (dx, dy) as (dx - dy, (dx + dy) / 2), so north points up-right as the player sees it.
-- Returns distance, compass index 1..8, clockwise degrees from screen-up (DrawTextureAngle, UIElement.java:243-262).
-- Kahlua's % keeps the dividend's sign (-119 % 360 = -119 in game, tesla-app-1027a), so wrap with floor instead.
local function wrap360(d) return d - math.floor(d / 360) * 360 end
function K.bearing(px, py, cx, cy)
    local dx, dy = cx - px, cy - py
    local dist = math.sqrt(dx * dx + dy * dy)
    local compass = wrap360(math.deg(math.atan2(dx, -dy)))
    local sx, sy = dx - dy, (dx + dy) / 2
    local ci = math.floor((compass + 22.5) / 45)
    return dist, ci - math.floor(ci / 8) * 8 + 1, wrap360(math.deg(math.atan2(sx, -sy)))
end

-- the card lying on the console reader = this car's card in the ignition (BaseVehicle.java:9673)
local function cardInIgnition(vehicle)
    local k = vehicle:getCurrentKey()
    return k ~= nil and k:getFullType() == K.CARD and k:getKeyId() == vehicle:getKeyId()
end

-- Card reader: the driver door's area (BaseVehicle.java:8363, VehiclePart.java:127).
function K.readerDist(player, vehicle)
    local door = vehicle:getPassengerDoor(0)
    local c = door and door:getArea() and vehicle:getAreaCenter(door:getArea())
    if not c then return math.huge end
    local dx, dy = player:getX() - c:getX(), player:getY() - c:getY()
    return math.sqrt(dx * dx + dy * dy)
end

-- Tap the card on the reader: outside, this car's card on you, at the driver's door.
function K.canTap(player, vehicle)
    if not vehicle or not T.isTesla(vehicle) then return false, "NO_VEHICLE" end
    if player:getVehicle() then return false, "NOT_OUTSIDE" end
    if not K.card(player, vehicle) then return false, "NO_KEY_CARD" end
    if K.readerDist(player, vehicle) > K.TAP_RANGE then return false, "TOO_FAR" end
    return true
end

-- Make a phone this car's phone key: seated in the car with its card handy (on you or on the console reader).
function K.canPair(player, vehicle, phone)
    local ft = phone and phone:getFullType()
    if ft ~= K.PHONE and ft ~= K.PHONE_KEY then return false, "NO_PHONE" end
    if not vehicle or not T.isTesla(vehicle) or player:getVehicle() ~= vehicle then return false, "NOT_INSIDE" end
    if not K.card(player, vehicle) and not cardInIgnition(vehicle) then return false, "NO_KEY_CARD" end
    if ft == K.PHONE_KEY and phone:getKeyId() == vehicle:getKeyId() then return false, "ALREADY_PAIRED" end
    return true
end

local function anyDoorOpen(vehicle)
    for i = 0, vehicle:getPartCount() - 1 do
        local door = vehicle:getPartByIndex(i):getDoor()
        if door and door:isOpen() then return true end
    end
    return false
end

-- Walk-Away Door Lock. Real car: no lock while a key is inside, a door or trunk is open, or Camp Mode is on
-- (manual: Doors > Walk-Away Door Lock; Climate Controls > Camp Mode "Walk-Away Door Lock is inactive").
-- Camp only counts with someone inside: an empty car's camp stops at the next engine update (Camp.lua "left"), so
-- blocking on it would race that stop and leave the car unlocked (tesla-keys-1026w).
-- false without a reason = nothing to say (no phone key, not away yet, already locked).
function K.canAutoLock(player, vehicle)
    if not vehicle or not T.isTesla(vehicle) or player:getVehicle() then return false end
    if not K.phoneKey(player, vehicle) then return false end
    if player:DistTo(vehicle) < K.LOCK_DIST - K.LOCK_SLACK then return false end
    if vehicle:areAllDoorsLocked() then return false end
    if vehicle:hasPassenger() then
        local part = T.Battery.part(vehicle)
        return false, (part and part:getModData().camp) and "AUTOLOCK_CAMP" or "AUTOLOCK_OCCUPIED"
    end
    if anyDoorOpen(vehicle) then return false, "AUTOLOCK_DOOR_OPEN" end
    return true
end

-- Phone key in a bag or belt bag: pulling a locked door's handle unlocks it, as the real car does with the phone in a
-- pocket or bag. Vanilla canUnlockDoor only sees loose keys and keyrings (BaseVehicle.java:1274-1301 ->
-- ItemContainer.java:3242-3256), so the vanilla unlock action (queued by ISVehicleMenu.onOpenDoor / onEnter) would fail.
-- Runs right before that action toggles the lock: in start() in SP (ISUnlockVehicleDoor.lua:22-36), in complete() on
-- the server (:55-76); never on an MP client. The key card keeps vanilla rules (loose: auto; in the wallet: tap the reader).
function K.phoneUnlock(vehicle, part, chr)
    local door = part and part:getDoor()
    if not door or not door:isLocked() or door:isLockBroken() or not chr or not T.isTesla(vehicle) then return false end
    if chr:getInventory():haveThisKeyId(vehicle:getKeyId()) or not K.phoneKey(chr, vehicle) then return false end
    door:setLocked(false)
    vehicle:transmitPartDoor(part) -- no-op off the server
    return true
end

require "Vehicles/TimedActions/ISUnlockVehicleDoor"
local unlockStart, unlockComplete = ISUnlockVehicleDoor.start, ISUnlockVehicleDoor.complete
function ISUnlockVehicleDoor:start(...)
    if not isClient() and not isServer() then K.phoneUnlock(self.vehicle, self.part, self.character) end
    return unlockStart(self, ...)
end
function ISUnlockVehicleDoor:complete(...)
    if isServer() then K.phoneUnlock(self.vehicle, self.part, self.character) end
    return unlockComplete(self, ...)
end

-- The frunk lid locks with the car (Liftgate.lockLids). Vanilla's other hood entries queue the unlock only when the
-- key is NOT found (the interact key's Vehicles.Use.EngineDoor, Vehicles.lua:849-852; the Mechanics radial,
-- ISVehicleMenu.lua:990-993; DriveUnitMenu.lua), so the owner's open would fail on the lock (ISOpenVehicleDoor.lua:61-64).
-- Whoever may unlock it (vanilla canUnlockDoor: seated, or the key in hand, BaseVehicle.java:1275-1301; or the phone
-- key in a bag, as at a door handle) has it unlocked right before vanilla complete() looks; a stranger finds it locked.
-- complete() runs on the server in MP and locally in SP.
function K.lidUnlock(vehicle, part, chr)
    if not part or part:getId() ~= "EngineDoor" or not chr or not T.isTesla(vehicle) then return false end
    local door = part:getDoor()
    if not door or not door:isLocked() or door:isLockBroken() then return false end
    if not vehicle:canUnlockDoor(part, chr) and not K.phoneKey(chr, vehicle) then return false end
    door:setLocked(false)
    vehicle:transmitPartDoor(part) -- no-op off the server
    return true
end

require "Vehicles/TimedActions/ISOpenVehicleDoor"
local openComplete = ISOpenVehicleDoor.complete
function ISOpenVehicleDoor:complete(...)
    if not isClient() then K.lidUnlock(self.vehicle, self.part, self.character) end
    return openComplete(self, ...)
end

-- Phone key in a bag also starts the car (the real one drives with the phone in a pocket or bag). Vanilla complete()
-- passes haveKey from haveThisKeyId only (ISStartVehicleEngine.lua:29); here tryStartEngine(true) instead. complete()
-- runs on the server in MP, locally in SP. No key goes into the ignition: the Starting state's setKeysInIgnition looks
-- with haveThisKeyId too (BaseVehicle.java:7484,7503 -> :8647-8675), finds nothing and sends no putKeyInIgnition, so
-- no extra "container already has id" (pitfalls.md). Key card: vanilla (loose -> onto the reader; wallet -> refused).
function K.bagPhoneStarts(chr, vehicle)
    return T.isTesla(vehicle) and not vehicle:isKeysInIgnition() and not vehicle:isHotwired()
        and not chr:getInventory():haveThisKeyId(vehicle:getKeyId()) and K.phoneKey(chr, vehicle) ~= nil
end

require "Vehicles/TimedActions/ISStartVehicleEngine"
local startComplete = ISStartVehicleEngine.complete
function ISStartVehicleEngine:complete(...)
    local vehicle = self.character:getVehicle()
    if vehicle and vehicle:isDriver(self.character) and K.bagPhoneStarts(self.character, vehicle) then
        vehicle:tryStartEngine(true)
        return true
    end
    return startComplete(self, ...)
end

return K
