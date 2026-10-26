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
K.REG = "MinidoracatTesla_KeyIds"               -- server Global ModData: tostring(keyId) -> car model name
K.TAP_RANGE = 1.5   -- key card reader (driver-side B-pillar): tiles from the driver door's area centre
-- Walk-away lock: tiles from the car centre. The car is ~4 tiles long, so walking round to the trunk (~2.5) never
-- locks it; 6 tiles (1 tile = 1 m, Core.lua) is a few metres past the body, like leaving Bluetooth range.
K.LOCK_DIST = 6
K.LOCK_SLACK = 1    -- the server sees the player up to a step behind the client that asked
K.WATCH_MS = 500    -- client distance check while a phone key holder walks away
K.LOCK_TRIES = 6    -- client asks at most this many times (once per WATCH_MS) once it is LOCK_DIST away

local function sameKey(item, keyId) return item:getKeyId() == keyId end

-- This car's card / phone key anywhere on the player: wallet, keyring, bags (ItemContainer.java:1576).
function K.card(player, vehicle)
    return player:getInventory():getFirstTypeEvalArgRecurse(K.CARD, sameKey, vehicle:getKeyId())
end
function K.phoneKey(player, vehicle)
    return player:getInventory():getFirstTypeEvalArgRecurse(K.PHONE_KEY, sameKey, vehicle:getKeyId())
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
-- false without a reason = nothing to say (no phone key, not away yet, already locked).
function K.canAutoLock(player, vehicle)
    if not vehicle or not T.isTesla(vehicle) or player:getVehicle() then return false end
    if not K.phoneKey(player, vehicle) then return false end
    if player:DistTo(vehicle) < K.LOCK_DIST - K.LOCK_SLACK then return false end
    if vehicle:areAllDoorsLocked() then return false end
    local part = T.Battery.part(vehicle)
    if part and part:getModData().camp then return false, "AUTOLOCK_CAMP" end
    if vehicle:hasPassenger() then return false, "AUTOLOCK_OCCUPIED" end
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

return K
