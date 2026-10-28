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

-- One phone key, several cars (user 2026-10-27, decisions.md "手機 App 第二版"). The item's vanilla keyId is the car
-- paired last, so vanilla unlock / start / ignition know that one. The others live in a list, in pairing order (the
-- last entry = the item's keyId), read by everything of Tesla's own (this file, T.authorized, T.legit, the app).
-- Item modData is no proof: any client can overwrite a server item's modData (SyncItemModDataPacket.parse loads the
-- client's table straight into it; SyncItemFieldsPacket.processServer wipes and copies it). So the server and SP read
-- the server-only record T.Store "phones" (item id -> keyIds, every phone key paired since app v2; KeyActions.lua);
-- an MP client reads the modData mirror, for menus and the app only. The item's keyId itself is not client-writable.
K.PAIRED, K.PAIRED_CARS = "teslaKeyIds", "teslaCars" -- modData mirror: keyIds, and their car models (menu labels)
local function extraIds(item)
    local ids
    if not isClient() then -- server / SP: the server-only record, never the client-writable mirror
        ids = T.Store and T.Store.get("phones")[tostring(item:getID())]
    else ids = item:hasModData() and item:getModData()[K.PAIRED] or nil end
    -- only this phone's own list: item ids are random, not unique (InventoryItemFactory.java:139), and the last car
    -- paired is always the item's keyId (KeyActions.lua replace); another item on the same id never inherits it
    if type(ids) ~= "table" or ids[#ids] ~= item:getKeyId() then return nil end
    return ids
end
function K.pairedWith(item, keyId)
    if item:getKeyId() == keyId then return true end
    local ids = extraIds(item)
    if type(ids) ~= "table" then return false end
    for i = 1, #ids do if ids[i] == keyId then return true end end
    return false
end
-- every car this phone key opens, in pairing order (a new table: menus and pairing only, never per frame)
function K.pairedIds(item)
    local out, ids = {}, extraIds(item)
    if type(ids) == "table" then for i = 1, #ids do out[i] = ids[i] end end
    if #out == 0 and item:getKeyId() ~= -1 then out[1] = item:getKeyId() end
    return out
end

-- This car's card / phone key anywhere on the player: wallet, keyring, bags (ItemContainer.java:1576).
function K.card(player, vehicle)
    return player:getInventory():getFirstTypeEvalArgRecurse(K.CARD, sameKey, vehicle:getKeyId())
end
-- the phone key for car `keyId` anywhere on the player, paired first or last (the app names its car by keyId:
-- server/MinidoracatTesla/Remote.lua)
function K.phoneKeyFor(player, keyId)
    return player:getInventory():getFirstTypeEvalArgRecurse(K.PHONE_KEY, K.pairedWith, keyId)
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

-- VehicleManager grants one of `codes` on this car to chr, as a virtual key (no item). Not installed, its VirtualKey
-- sandbox option off (vanilla key rules, VehicleManager ActionGuards.lua virtualKey, default on), or an unclaimed car
-- (anyone's: no key from it) -> false. VehicleManager's admin override ("ADMIN") counts: opt-in in its fleet window, and
-- it writes ADMIN_BYPASS with our mod name (its OwnershipSystem.lua O.allowsRecord). MP client: its projection, UX only.
-- Fails closed, unlike Remote.vmAllows (no VehicleManager or UNCLAIMED = yes there): here only a VehicleManager grant counts.
-- (T.authorized's HOTWIRED, like KEY and EASY_USE, only comes without VehicleManager, which already returned false.)
local function vmGrants(chr, vehicle, codes)
    local api = MinidoracatVehicleManagerAPI
    if not (api and api.canUse) then return false end
    local page = SandboxVars and SandboxVars.MinidoracatVehicleManager
    if page and page.VirtualKey == false then return false end
    for _, code in ipairs(codes) do
        local ok, why = T.authorized(chr, vehicle, code) -- VehicleManager's canUse, as Tesla (Core.lua)
        if ok == true and why ~= "UNCLAIMED" then return true end
    end
    return false
end

-- Make a phone this car's phone key, or add this car to a phone key (K.pairedWith): seated in the car with its card
-- handy (on you or on the console reader). Lost card (user 2026-10-28): VehicleManager's owner of the car (MANAGE, never
-- shareable) pairs without it; returns true, "VM" then (the menu's tooltip). A rent-locked owner (and an admin once the
-- override is off) keeps the phone key, but on a claimed car the key itself gets past nothing VehicleManager refuses:
-- doors and start (its ActionGuards), the app (Remote.lua R.vmAllows), sentry and camp (ParkModes T.legit) ask it.
-- Only the walk-away lock (K.canAutoLock) takes the phone key alone; it can only lock.
-- No VehicleManager (user 2026-10-28, decisions.md keyless rules): seated in a hotwired car pairs too, true, "HOTWIRED"
-- (a hotwired car is anyone's who sits in it, T.authorized), so losing both the card and the phone is not the end;
-- refused, the reason says so (NO_KEY_CARD_HOTWIRE). With VehicleManager the card or its MANAGE, as above.
function K.canPair(player, vehicle, phone)
    local ft = phone and phone:getFullType()
    if ft ~= K.PHONE and ft ~= K.PHONE_KEY then return false, "NO_PHONE" end
    if not vehicle or not T.isTesla(vehicle) or player:getVehicle() ~= vehicle then return false, "NOT_INSIDE" end
    if ft == K.PHONE_KEY and K.pairedWith(phone, vehicle:getKeyId()) then return false, "ALREADY_PAIRED" end
    if K.card(player, vehicle) or cardInIgnition(vehicle) then return true end
    local api = MinidoracatVehicleManagerAPI
    if not (api and api.canUse) then
        if vehicle:isHotwired() then return true, "HOTWIRED" end
        return false, "NO_KEY_CARD_HOTWIRE"
    end
    if vmGrants(player, vehicle, { "MANAGE" }) then return true, "VM" end
    return false, "NO_KEY_CARD"
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

-- Phone key in a bag or belt bag, or one whose item keyId is another car (a phone paired with several, K.pairedWith):
-- pulling a locked door's handle unlocks it, as the real car does with the phone in a pocket or bag. Vanilla
-- canUnlockDoor only sees loose keys and keyrings with this keyId (BaseVehicle.java:1274-1301 ->
-- ItemContainer.java:3242-3256), so the vanilla unlock action (queued by ISVehicleMenu.onOpenDoor / onEnter) would fail.
-- Runs right before that action toggles the lock: in start() in SP (ISUnlockVehicleDoor.lua:22-36), in complete() on
-- the server (:55-76); never on an MP client. The key card keeps vanilla rules (loose: auto; in the wallet: tap the reader).
function K.phoneUnlock(vehicle, part, chr)
    local door = part and part:getDoor()
    if not door or not door:isLocked() or door:isLockBroken() or not chr or not T.isTesla(vehicle) then return false end
    if part:getVehicle() ~= vehicle then return false end -- vehicle and part travel apart (see K.lidUnlock)
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
-- Whoever may unlock it (vanilla canUnlockDoor: seated, or the key in hand, BaseVehicle.java:1275-1301; the phone key
-- in a bag, as at a door handle; a VehicleManager user it lets work on the hood, whose virtual key is no item) has it
-- unlocked right before vanilla complete() looks; a stranger finds it locked. The key card in a wallet does not count
-- (tap the reader, as for the doors). complete() runs on the server in MP and locally in SP.
function K.lidUnlock(vehicle, part, chr)
    -- the action carries vehicle and part as separate arguments (ISOpenVehicleDoor.lua:142-145): the key must be this car's
    if not part or part:getId() ~= "EngineDoor" or not chr or part:getVehicle() ~= vehicle or not T.isTesla(vehicle) then
        return false
    end
    local door = part:getDoor()
    if not door or not door:isLocked() or door:isLockBroken() then return false end
    -- VehicleManager's own codes for opening the hood (its Actions.lua EngineDoor; the app's frunk, Remote.lua)
    if not (vehicle:canUnlockDoor(part, chr) or K.phoneKey(chr, vehicle) or vmGrants(chr, vehicle, { "REPAIR", "SALVAGE" })) then
        return false
    end
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

-- Phone key in a bag, or paired with this car but carrying another car's keyId (K.pairedWith), also starts the car
-- (the real one drives with the phone in a pocket or bag). Vanilla complete()
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
