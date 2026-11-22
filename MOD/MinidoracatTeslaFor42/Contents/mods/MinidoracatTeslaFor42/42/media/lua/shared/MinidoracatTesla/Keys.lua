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
-- CarKey -> key card while seated (KeysUI.lua): a start waits at most SWAP_WAIT_MS for a sweep it may race; a sweep
-- waits START_MS after a start, until the Starting state (and with it the key into the ignition) has reached the client
K.SWAP_WAIT_MS = 3000
K.START_MS = 2000
-- Lock confirmation (user 2026-10-26: candidate A): the vanilla standard horn on the car's own emitter, stopped after
-- CHIRP_MS, played by each client within CHIRP_TILES. Emitter only, no world sound: zombies do not hear it.
K.CHIRP = "VehicleHornStandard" -- sounds_vehicle_standard.txt (event Vehicle/Standard/Horn)
K.CHIRP_MS = 150
K.CHIRP_TILES = 40
-- Tesla app on the phone key (user 2026-10-27: like the real car). Owner's manual, Mobile App: phone and car talk over
-- the cellular network, or over Bluetooth when the phone key is close. Grid up = phone network up: any distance, as
-- long as the server has the car loaded. Grid down: Bluetooth only, within K.btRange() tiles (1 tile = 1 m).
-- Bluetooth range: sandbox BluetoothRange (0-64, default 50, user 2026-10-30); 0 = no link at all once the grid is down.
-- Both sides read it (the server's reach, the client's NO_LINK text and summon ring); unreadable: 50.
function K.btRange()
    local s = SandboxVars and SandboxVars.MinidoracatTesla
    local v = s and s.BluetoothRange
    if type(v) ~= "number" or v ~= v then return 50 end
    return math.max(0, math.min(64, v))
end

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
-- every car this phone key opens, in pairing order (a new table: menus, pairing and the inventory list's names
-- (KeysUI.lua UI.nameOf), never per frame)
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
    local r = K.btRange()
    if r > 0 and player:DistTo(vehicle) <= r then return "bt" end
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
-- Where the phone is, is not checked here: the server takes only one on the player (KeyActions phonePair finds it
-- there), and the menu carries one from the glove box or another container first (KeysUI onPair).
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
        local part = vehicle:getPartByIndex(i)
        local door = part:getDoor()
        if door and door:isOpen() and not T.OPEN_OK[part:getId()] then return true end
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

-- VehicleManager refuses chr this door of a claimed car: no key of ours (loose, phone, card) gets past it, and the lock
-- is left as it is. Its guard wraps complete() outermost once every mod is loaded (its ActionGuards.lua:214-228,349-350):
-- on the server a refusal never reaches ours, and with its VirtualKey on a granted unlock unlocks the door itself without
-- calling ours (:190-198); in SP our unlock runs in start(), before that guard, hence this check. Its own codes: the hood
-- is REPAIR or SALVAGE (its Actions.lua doorAction), any other door PASSENGER (its unlock guard). No VehicleManager or
-- an unclaimed car (canUse true, "UNCLAIMED"): false, the key rules alone.
local function vmRefuses(chr, vehicle, part)
    local api = MinidoracatVehicleManagerAPI
    if not (api and api.canUse) then return false end
    local codes = part:getId() == "EngineDoor" and { "REPAIR", "SALVAGE" } or { "PASSENGER" }
    for _, code in ipairs(codes) do
        if T.authorized(chr, vehicle, code) then return false end
    end
    return true
end

-- Phone key in a bag or belt bag, or one whose item keyId is another car (a phone paired with several, K.pairedWith):
-- pulling a locked door's handle unlocks it, as the real car does with the phone in a pocket or bag. Vanilla
-- canUnlockDoor only sees loose keys and keyrings with this keyId (BaseVehicle.java:1287-1314 ->
-- ItemContainer.java:3290-3304), so the vanilla unlock action (queued by ISVehicleMenu.onOpenDoor / onEnter) would fail.
-- Runs right before that action toggles the lock: in start() in SP (ISUnlockVehicleDoor.lua:22-36), in complete() on
-- the server (:55-76); never on an MP client. The key card keeps vanilla rules (loose: auto; in the wallet: tap the reader).
function K.phoneUnlock(vehicle, part, chr)
    local door = part and part:getDoor()
    if not door or not door:isLocked() or door:isLockBroken() or not chr or not T.isTesla(vehicle) then return false end
    if part:getVehicle() ~= vehicle then return false end -- vehicle and part travel apart (see K.lidKey)
    if part:getId() == "EngineDoor" then return false end -- the lid unlocks only as it opens (below)
    if chr:getInventory():haveThisKeyId(vehicle:getKeyId()) or not K.phoneKey(chr, vehicle) then return false end
    if vmRefuses(chr, vehicle, part) then return false end
    door:setLocked(false)
    vehicle:transmitPartDoor(part) -- no-op off the server
    return true
end

require "Vehicles/TimedActions/ISUnlockVehicleDoor"
local unlockNew, unlockStart, unlockComplete = ISUnlockVehicleDoor.new, ISUnlockVehicleDoor.start, ISUnlockVehicleDoor.complete
-- Vanilla's unlock just failed on a Tesla's lid (still locked, lock not broken): say so. Only the side that ran the
-- unlock calls this: never for a cancel, never after VehicleManager refused (its guard, outside ours, did not call us).
local function lidDenied(a)
    local v, part = a.vehicle, a.part
    local door = part and part:getDoor()
    if door and v and part:getId() == "EngineDoor" and T.isTesla(v) and door:isLocked() and not door:isLockBroken() then
        T.deny(a.character, "LID_LOCKED", v:getId())
    end
end
function ISUnlockVehicleDoor:start(...)
    local sp = not isClient() and not isServer()
    if sp then K.phoneUnlock(self.vehicle, self.part, self.character) end
    local r = unlockStart(self, ...)
    if sp then lidDenied(self) end -- vanilla toggled here and force-stopped if still locked (ISUnlockVehicleDoor.lua:26-31)
    return r
end
function ISUnlockVehicleDoor:complete(...)
    if isServer() then K.phoneUnlock(self.vehicle, self.part, self.character) end
    local ok = unlockComplete(self, ...)
    if isServer() and not ok then lidDenied(self) end -- MP: only the server's complete() unlocks (:55-76)
    return ok
end

-- The frunk lid locks with the car (Liftgate.lockLids) and unlocks only as it opens: in the open's complete() below
-- (the server in MP, locally in SP), for whoever may open it (K.lidKey); vanilla's open acts only on an unlocked lid
-- (ISOpenVehicleDoor.lua:71-74). Vanilla's hood entries queue its unlock before the open when the key is not in hand
-- (Vehicles.Use.EngineDoor, Vehicles.lua:849-852; the Mechanics radial, ISVehicleMenu.lua:997-998; the mechanics
-- window's engine and headlight actions, ISVehicleMechanics.lua:440,484,516; DriveUnitMenu.lua), the radial's Open
-- Hood when it is (ISVehicleMenu.lua:1230-1231); every one runs outside the car. On a Tesla's lid, four kinds of
-- opener (vanilla skips an ignoreAction, ISTimedActionQueue.lua:158,204):
-- - VehicleManager refuses them the hood: left out, whatever key they hold. It wants PASSENGER for every unlock (its
--   Actions.lua) but REPAIR or SALVAGE for the hood's open (its doorAction), so a rider's unlock went through (its
--   virtual key, ActionGuards.lua:190-198) and left the lid unlocked behind a refused open.
-- - the key in hand: vanilla's unlock, which unlocks it (canUnlockDoor, BaseVehicle.java:1287-1314).
-- - a card or phone key in a bag, or VehicleManager's virtual key: left out, the open unlocks it. Queued, vanilla's
--   unlock failed for them (toggleLockedDoor asks canUnlockDoor, :1242-1256) and dropped the whole queue
--   (ISUnlockVehicleDoor.lua:22-36; semimech-repro-e).
-- - no key: vanilla's unlock, which fails and drops the queue, so no mechanics window opens on a locked car;
--   lidDenied above says why.
function ISUnlockVehicleDoor:new(character, part, ...) -- vanilla's parameter names: they are the wire format (NetTimedAction.java:41-50)
    local o = unlockNew(self, character, part, ...)
    local v = part and part:getVehicle()
    if not isServer() and character and v and part:getId() == "EngineDoor" and T.isTesla(v)
        and (vmRefuses(character, v, part)
            or not character:getInventory():haveThisKeyId(v:getKeyId()) and K.lidKey(v, part, character)) then
        o.ignoreAction = true
    end
    return o
end

-- May chr open this Tesla's frunk lid: VehicleManager does not refuse it (vmRefuses; its own guard on the open, outside
-- ours, refuses first), and this car's key in hand (vanilla's haveThisKeyId: loose or on a keyring), its phone key or
-- key card anywhere on them (as they start it, K.bagKeyStarts), or a VehicleManager user it lets work on the hood (its
-- virtual key is no item). Not the seat: vanilla's hood entries all run outside the car, and the dashboard's frunk
-- button goes through the liftgate command, not here.
function K.lidKey(vehicle, part, chr)
    -- the action carries vehicle and part as separate arguments (ISOpenVehicleDoor.lua:142-145): the key must be this car's
    if not part or part:getId() ~= "EngineDoor" or not chr or part:getVehicle() ~= vehicle or not T.isTesla(vehicle) then
        return false
    end
    if vmRefuses(chr, vehicle, part) then return false end
    return chr:getInventory():haveThisKeyId(vehicle:getKeyId()) ~= nil or K.phoneKey(chr, vehicle) ~= nil
        or K.card(chr, vehicle) ~= nil or vmGrants(chr, vehicle, { "REPAIR", "SALVAGE" })
end

require "Vehicles/TimedActions/ISOpenVehicleDoor"
local openNew, openValidStart, openComplete = ISOpenVehicleDoor.new, ISOpenVehicleDoor.isValidStart, ISOpenVehicleDoor.complete
-- Queued by someone our rule lets in, so with no vanilla unlock ahead of it; by its turn the key may be gone (the bag put
-- down on the walk). Asked once as its turn comes (ISTimedActionQueue.lua:82; false drops the queue) and before anything
-- is sent: end as vanilla's failed unlock would have. An open that starts as it is queued (:9-18) has no such gap.
function ISOpenVehicleDoor:new(character, vehicle, part, ...) -- vanilla's parameter names: the wire format
    local o = openNew(self, character, vehicle, part, ...)
    if not isServer() then o.lidKeyed = K.lidKey(vehicle, part, character) end
    return o
end
function ISOpenVehicleDoor:isValidStart(...)
    local v, part, chr = self.vehicle, self.part, self.character
    local door = self.lidKeyed and part:getDoor()
    if door and door:isLocked() and not door:isOpen() and not door:isLockBroken()
        and not vmRefuses(chr, v, part) and not K.lidKey(v, part, chr) then
        HaloTextHelper.addBadText(chr, T.denyText("LID_LOCKED"))
        return false
    end
    return openValidStart(self, ...)
end
function ISOpenVehicleDoor:complete(...)
    local v, part, chr = self.vehicle, self.part, self.character
    local door = not isClient() and K.lidKey(v, part, chr) and part:getDoor()
    if door then
        if door:isLocked() and not door:isLockBroken() then
            door:setLocked(false)
            v:transmitPartDoor(part)
        end
        -- vanilla's alarm spares the key it sees (haveThisKeyId: loose or on a keyring, ISOpenVehicleDoor.lua:83-93);
        -- this car's card or phone key in a bag opening the lid gets the same: the car counts as entered
        if not door:isLocked() and not chr:getInventory():haveThisKeyId(v:getKeyId())
            and (K.phoneKey(chr, v) or K.card(chr, v)) then
            v:setPreviouslyEntered(true)
        end
    end
    return openComplete(self, ...)
end

-- A phone key or key card in a wallet or bag, or a phone key paired with this car but carrying another car's keyId
-- (K.pairedWith), also starts the car: the real one drives with the phone in a pocket or bag, and the card works from a
-- wallet like the phone (user 2026-10-31, after a Workshop comment). Vanilla complete()
-- passes haveKey from haveThisKeyId only (ISStartVehicleEngine.lua:29); here tryStartEngine(true) instead. complete()
-- runs on the server in MP, locally in SP. No key goes into the ignition: the Starting state's setKeysInIgnition looks
-- with haveThisKeyId too (BaseVehicle.java:7525,7544 -> :8690-8724), finds nothing and sends no putKeyInIgnition, so
-- no extra "container already has id" (pitfalls.md). A key loose or on a keyring: vanilla (into the ignition; the card
-- stays there, on the console reader; the phone key comes back to its driver when the start ends, KeysUI.lua phoneBack).
function K.bagKeyStarts(chr, vehicle)
    return T.isTesla(vehicle) and not vehicle:isKeysInIgnition() and not vehicle:isHotwired()
        and not chr:getInventory():haveThisKeyId(vehicle:getKeyId())
        and (K.phoneKey(chr, vehicle) ~= nil or K.card(chr, vehicle) ~= nil)
end

require "Vehicles/TimedActions/ISStartVehicleEngine"
local startComplete = ISStartVehicleEngine.complete
function ISStartVehicleEngine:complete(...)
    local vehicle = self.character:getVehicle()
    if vehicle and vehicle:isDriver(self.character) and K.bagKeyStarts(self.character, vehicle) then
        vehicle:tryStartEngine(true)
        return true
    end
    return startComplete(self, ...)
end

return K
