-- Key card and phone key, server side (rules: shared/MinidoracatTesla/Keys.lua).
--   * A Tesla's vanilla CarKey becomes a key card when a player has it (createVehicleKey hard-codes CarKey,
--     BaseVehicle.java:1145-1157, from ~20 call sites, so the swap happens on the player, not at creation).
--     Which keys are Tesla keys: a keyId registry filled when a Tesla loads, not the translated item name.
--   * keyTap: lock / unlock every door with the card, flash + beep. autoLock: walk-away lock for phone keys.
--   * phonePair: a phone becomes this car's phone key, or a phone key adds this car (one phone, several cars).
--     phoneUnpair: a car leaves the phone key (the last one out: a plain phone again).
--   * Phone loot.
if isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Keys"
require "MinidoracatTesla/Sentry"
require "MinidoracatTesla/Store"
require "MinidoracatTesla/Liftgate"

local T = MinidoracatTesla
local K = T.Keys
local S = T.Sentry
T.ServerCommands = T.ServerCommands or {}

K.SOUND = "MinidoracatTesla_KeyAlert" -- 0.4 s chime (sound.md): the unlock beep; lock = the horn chirp (K.CHIRP)
K.stats = { swaps = 0, taps = 0, pairs = 0, autoLocks = 0, chirps = 0 }

-- ------------------------------------------------------------------ Tesla keyId registry
-- server-only (Store.lua): which keyIds are Teslas is nobody else's business
local function registry() return T.Store.get("keyIds") end

-- same name vanilla gives the CarKey (keyNamerVehicle, BaseVehicle.java:10739-10753)
local function carName(vehicle)
    local s = vehicle:getScript()
    return s:getCarModelName() or s:getName()
end

-- OnSpawnVehicleEnd fires on every load, new or from the save (BaseVehicle.java:904, 7952-7964)
function K.register(vehicle)
    if not T.isTesla(vehicle) then return end
    local reg, id = registry(), tostring(vehicle:getKeyId())
    if not reg[id] then reg[id] = carName(vehicle) end
end
Events.OnSpawnVehicleEnd.Add(K.register)

-- Same container, new item: server Remove/AddItem first, then the packets (pitfalls.md: send only sends). `ids` (phone
-- keys): every paired car in pairing order, written to the server-only record (the authority, Keys.pairedWith) and to
-- the modData mirror the client reads; the new item has a new id, so the old id's record goes.
local function replace(old, fullType, keyId, name, ids, cars)
    local cont = old:getContainer()
    if not cont then return nil end
    local item = instanceItem(fullType)
    local phones = ids and T.Store.get("phones")
    -- item ids are random ints, not unique (InventoryItemFactory.java:139): a phone never takes an id another phone's
    -- record already has (review 2026-10-27: it would inherit that phone's cars)
    for _ = 1, 8 do
        if not (phones and phones[tostring(item:getID())]) then break end
        item = instanceItem(fullType)
    end
    item:setKeyId(keyId)
    item:setName(name)
    if ids then -- a phone (key): its record follows the new item id
        phones[tostring(old:getID())] = nil
        if #ids > 1 then -- its own copy: a client's SyncItemModData replaces the item's modData, never the store's
            local copy = {}
            for i = 1, #ids do copy[i] = ids[i] end
            phones[tostring(item:getID())] = copy
        end
        if #ids > 0 then
            local md = item:getModData()
            md[K.PAIRED], md[K.PAIRED_CARS] = ids, cars
        end
    end
    cont:Remove(old)
    sendRemoveItemFromContainer(cont, old)
    cont:AddItem(item)
    sendAddItemToContainer(cont, item)
    return item
end
-- not item:getDisplayName(): on a dedicated server that is the script's full type (tesla-keys-1026e)
local function keyName(fullType, car) return getItemNameFromFullType(fullType) .. " - " .. getText("IGUI_VehicleName" .. car) end

-- a phone key's name: "Phone Key - Model Y" for one car, "Phone Key - 2 Teslas" for more
local function phoneName(ids, cars)
    if #ids == 1 then return keyName(K.PHONE_KEY, cars[1]) end
    return getItemNameFromFullType(K.PHONE_KEY) .. " - " .. getText("IGUI_MinidoracatTesla_PhoneCars", tostring(#ids))
end
-- the car models of `ids` (menu labels on the client), from the registry every loaded Tesla is in
local function carsOf(ids)
    local reg, out = registry(), {}
    for i, id in ipairs(ids) do out[i] = reg[tostring(id)] or "MinidoracatTesla_ModelY" end
    return out
end
-- Every Tesla CarKey on the player becomes a key card. Not while seated: the key may be on its way into or out of the
-- ignition, and the client's copy would keep the old item id (IgnitionDup 2026-10-26: VehicleProperties.java:27-33).
function K.sweep(player)
    if not player or player:getVehicle() then return 0 end
    local inv = player:getInventory()
    if not inv:containsTypeRecurse("Base.CarKey") then return 0 end
    local reg, n = registry(), 0
    local list = inv:getAllTypeRecurse("Base.CarKey")
    for i = 0, list:size() - 1 do
        local key = list:get(i)
        local car = reg[tostring(key:getKeyId())]
        if car and replace(key, K.CARD, key:getKeyId(), keyName(K.CARD, car)) then n = n + 1 end
    end
    if n > 0 then
        K.stats.swaps = K.stats.swaps + n
        T.log("key card: swapped " .. n .. " car key(s) for " .. player:getUsername())
    end
    return n
end

-- ------------------------------------------------------------------ lock, flash, beep
-- every passenger door like vanilla ISLockDoors:complete (ISLockDoors.lua), then the liftgate and the frunk lid
-- (Liftgate.lockLids): a Tesla locks as a whole
function K.setLocked(vehicle, locked)
    for seat = 0, vehicle:getMaxPassengers() - 1 do
        local part = vehicle:getPassengerDoor(seat)
        local door = part and part:getDoor()
        if door and not door:isLockBroken() then
            door:setLocked(locked)
            vehicle:transmitPartDoor(part)
        end
    end
    T.Liftgate.lockLids(vehicle, locked)
    local remember = T.Remote and T.Remote.remember -- the phone app's last record (Remote.lua)
    if remember then remember(vehicle) end
end

-- one flash to lock, two to unlock (Sentry's flash: headlights + light parts, synced to every client).
-- Lock: horn chirp, each client within CHIRP_TILES plays and stops it itself (KeysUI keyChirp); playServerSound cannot
-- stop a sound. Neither path adds a world sound (zombies). Unlock: the KeyAlert beep.
function K.signal(vehicle, locked)
    S.flash(vehicle, locked and 2 or 4)
    if locked then
        local out = { vid = vehicle:getId() }
        if not isServer() then
            local fn = T.ClientCommands and T.ClientCommands.keyChirp -- SP: the client handler directly
            if fn then fn(out); K.stats.chirps = K.stats.chirps + 1 end
            return
        end
        local x, y, r2 = vehicle:getX(), vehicle:getY(), K.CHIRP_TILES * K.CHIRP_TILES
        local list = getOnlinePlayers() -- LuaManager.java:4457
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            local dx, dy = p:getX() - x, p:getY() - y
            if dx * dx + dy * dy <= r2 then
                sendServerCommand(p, T.MODULE, "keyChirp", out)
                K.stats.chirps = K.stats.chirps + 1
            end
        end
    elseif isServer() then
        playServerSound(K.SOUND, vehicle:getSquare()) -- players within 10 tiles (GameServer.java:2136-2156)
    else
        vehicle:getEmitter():playSound(K.SOUND)
    end
end

-- ------------------------------------------------------------------ commands
T.ServerCommands.keySweep = function(player)
    K.sweep(player)
end

T.ServerCommands.keyTap = function(player, args)
    local v = T.commandVehicle(player, args)
    if not v then return end
    local ok, why = K.canTap(player, v)
    if not ok then return T.deny(player, why, v:getId()) end
    local lock = not v:areAllDoorsLocked()
    K.setLocked(v, lock)
    K.signal(v, lock)
    -- an authenticated unlock is the owner coming back, not a stranger at the door
    local part = not lock and T.Battery.part(v)
    if part and part:getModData().sentry then S.disarm(v, player:getUsername()) end
    K.stats.taps = K.stats.taps + 1
    T.log("key card " .. (lock and "lock" or "unlock") .. " vid=" .. v:getId() .. " by " .. player:getUsername())
end

T.ServerCommands.phonePair = function(player, args)
    local v = T.commandVehicle(player, args)
    if not v then return end
    local id = tonumber(args.id)
    local phone = id and player:getInventory():getItemWithIDRecursiv(id) or nil
    local ok, why = K.canPair(player, v, phone)
    if not ok then return T.deny(player, why, v:getId()) end
    -- a phone key keeps its cars and adds this one last: the item's keyId (vanilla's) becomes this car
    local ids = phone:getFullType() == K.PHONE_KEY and K.pairedIds(phone) or {}
    ids[#ids + 1] = v:getKeyId()
    local cars = carsOf(ids)
    if not replace(phone, K.PHONE_KEY, v:getKeyId(), phoneName(ids, cars), ids, cars) then return end
    K.stats.pairs = K.stats.pairs + 1
    T.log("phone key paired vid=" .. v:getId() .. " cars=" .. #ids .. " by " .. player:getUsername())
    T.send(player, "phonePaired", { vid = v:getId(), car = carName(v), n = #ids })
end

-- "Remove from phone > car": anywhere outside a car, the phone key on you. The item's keyId moves to the car paired
-- last of those left; the last car out leaves a plain phone (no keyId, no record). Not in a car: the phone key may be
-- on its way into the ignition, and swapping such a key doubles it there (keys.md "IgnitionDup", as K.sweep).
T.ServerCommands.phoneUnpair = function(player, args)
    local id, key = args.id, args.key
    if not player or type(id) ~= "number" or type(key) ~= "number" then return end
    if player:getVehicle() then return T.deny(player, "NOT_OUTSIDE") end
    local phone = player:getInventory():getItemWithIDRecursiv(id)
    if not phone or phone:getFullType() ~= K.PHONE_KEY or not K.pairedWith(phone, key) then
        return T.deny(player, "NO_PHONE_KEY")
    end
    local ids, left = K.pairedIds(phone), {}
    for _, k in ipairs(ids) do if k ~= key then left[#left + 1] = k end end
    local car = registry()[tostring(key)] or "MinidoracatTesla_ModelY"
    local done
    if #left == 0 then
        done = replace(phone, K.PHONE, -1, getItemNameFromFullType(K.PHONE), left)
    else
        local cars = carsOf(left)
        done = replace(phone, K.PHONE_KEY, left[#left], phoneName(left, cars), left, cars)
    end
    if not done then return end
    T.log("phone key unpaired key=" .. tostring(key) .. " left=" .. #left .. " by " .. player:getUsername())
    T.send(player, "phoneUnpaired", { car = car, n = #left })
end

T.ServerCommands.autoLock = function(player, args)
    local v = T.commandVehicle(player, args, K.LOCK_DIST * 5)
    if not v then return end
    local ok, why = K.canAutoLock(player, v)
    if not ok then
        T.log("walk-away lock skipped vid=" .. v:getId() .. " " .. tostring(why))
        -- with a reason the client says why and stops asking; without one (not away yet as the server sees it,
        -- already locked) it may ask again (KeysUI watchTick)
        T.send(player, "autoLockSkip", { vid = v:getId(), reason = why })
        return
    end
    K.setLocked(v, true)
    K.signal(v, true)
    K.stats.autoLocks = K.stats.autoLocks + 1
    T.log("walk-away lock vid=" .. v:getId() .. " by " .. player:getUsername())
    T.send(player, "autoLocked", { vid = v:getId(), car = carName(v) })
end

-- ------------------------------------------------------------------ phone loot
-- A smartphone is rare in 1993 Kentucky: phone shops carry it, homes and offices seldom. Weights sit below the
-- cordless handset's in the same lists (ProceduralDistributions.lua: ElectronicStorePhones 50/20/20/10,
-- StoreShelfElectronics 8, GigamartHouseElectronics 20/10, OfficeDeskHome 8, BedroomSidetableClassy 10).
-- Same pattern as AutoDrive's MDAD_Distributions.lua: remove our pairs first so a reload does not stack them.
K.LOOT = {
    ElectronicStorePhones = 10,
    StoreShelfElectronics = 2,
    GigamartHouseElectronics = 4,
    OfficeDeskHome = 1,
    OfficeDeskHomeClassy = 2,
    BedroomSidetableClassy = 1,
    BedroomSidetable = 0.3,
}
local function injectLoot()
    local lists = ProceduralDistributions and ProceduralDistributions.list
    if not lists then return end
    for name, weight in pairs(K.LOOT) do
        local items = lists[name] and lists[name].items
        if items then
            for i = #items - 1, 1, -2 do
                if items[i] == K.PHONE then table.remove(items, i + 1); table.remove(items, i) end
            end
            table.insert(items, K.PHONE)
            table.insert(items, weight)
        end
    end
end
Events.OnPostDistributionMerge.Add(injectLoot)
