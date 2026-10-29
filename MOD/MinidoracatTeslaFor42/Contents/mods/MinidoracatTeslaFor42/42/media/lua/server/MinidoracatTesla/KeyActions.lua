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
require "MinidoracatTesla/Remote"

local T = MinidoracatTesla
local K = T.Keys
local S = T.Sentry
T.ServerCommands = T.ServerCommands or {}

K.SOUND = "MinidoracatTesla_KeyAlert" -- 0.4 s chime (sound.md): the unlock beep; lock = the horn chirp (K.CHIRP)
K.stats = { swaps = 0, taps = 0, pairs = 0, autoLocks = 0, chirps = 0, holds = 0, ghosts = 0 }

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
-- the modData mirror the client reads; the new item has a new id, so the old id's record goes. `cars`: the car models
-- (teslaCars: the card's one car, the phone key's cars in pairing order), for the client's item name and menu labels.
-- No setName: a name other than the item's original one is saved and sent to clients as it is (InventoryItem.java:
-- 1711-1714, read back :2038), so a name made here stays in the server's language on every client (production
-- players.db 2026-10-29: an unpaired phone saved as "Smartphone"). Unnamed, the client builds the item from its own
-- script (its language) and KeysUI.lua UI.nameOf adds the car.
-- Item ids are random ints, not unique (InventoryItemFactory.java:139), so every phone key made here is recorded (one
-- car too) and a new one never takes a recorded id: two phone keys never share one (review 2026-10-27, round 1 and 2:
-- a twin would inherit the other's cars). ponytail: phone keys paired before app v2 are not recorded, so a new one can
-- still land on such an id (chance: their count / 2^31 per pairing); they get recorded at their next pairing.
local function replace(old, fullType, keyId, ids, cars)
    local cont = old:getContainer()
    if not cont then return nil end
    local item = instanceItem(fullType)
    local phones = ids and T.Store.get("phones")
    if phones then
        local tries = 1
        while phones[tostring(item:getID())] do
            if tries == 8 then return nil end -- (never in practice: nothing changes rather than a shared id)
            tries = tries + 1
            item = instanceItem(fullType)
        end
    end
    item:setKeyId(keyId)
    if cars then item:getModData()[K.PAIRED_CARS] = cars end
    if ids then -- a phone (key): its record follows the new item id
        local oldId = tostring(old:getID())
        local r = phones[oldId]
        if r and old:getFullType() == K.PHONE_KEY and r[#r] == old:getKeyId() then phones[oldId] = nil end -- its own only
        if #ids > 0 then -- its own copy: a client's SyncItemModData replaces the item's modData, never the store's
            local copy = {}
            for i = 1, #ids do copy[i] = ids[i] end
            phones[tostring(item:getID())] = copy
            item:getModData()[K.PAIRED] = ids
        end
    end
    cont:Remove(old)
    sendRemoveItemFromContainer(cont, old)
    cont:AddItem(item)
    sendAddItemToContainer(cont, item)
    return item
end
-- the car models of `ids` (item name and menu labels on the client), from the registry every loaded Tesla is in; an id
-- it lacks (a store from before the registry) stays nil, never another car's model
local function carsOf(ids)
    local reg, out = registry(), {}
    for i, id in ipairs(ids) do out[i] = reg[tostring(id)] end
    return out
end
-- Every Tesla CarKey in the player's inventory becomes a key card, seated too. The ignition is not the inventory: its
-- key never changes (a swapped ignition key doubles on the client, IgnitionDup 2026-10-26, VehicleProperties.java:
-- 27-36). Racing a start (keys.md "坐著換卡碰上發動"): the client moves its own copy of the key in when the Starting
-- state reaches it and sends that item (BaseVehicle.java:7484,7503 -> :8647-8675); the server then takes out whichever
-- key has that keyId (:8726): the card a swap just made, or another key of the car before it (the card goes last), and
-- the client keeps that key as a ghost. So the car's own key waits while its driver's motor is starting with the
-- ignition empty; the client's start waits for a sweep it sent (KeysUI.lua UI.swapPending); a ghost that still happens
-- is removed on the client (ghost guard below).
local GHOST_MS = 60000 -- a swap is remembered this long for the ghost guard (a race lasts seconds)
-- "username:old CarKey item id" -> { keys = { { item, container }, ... }, at }: every key of that car haveThisKeyId could
-- take right after the swap (the new card, other cards, CarKeys, phone keys, any Key with that keyId). The username,
-- not the IsoPlayer (family pitfalls).
local swapped = {}
local function prune(now)
    local stale = {}
    for k, r in pairs(swapped) do
        if now - r.at > GHOST_MS then stale[#stale + 1] = k end
    end
    for _, k in ipairs(stale) do swapped[k] = nil end
end
-- keyId -> its keys where haveThisKeyId looks (ItemContainer.java:3242-3256): loose in the inventory, or in a key ring
-- (nested rings too); not in bags or wallets, so the scan stays at the inventory's top level, for the keyIds in `olds`
local function keysOf(inv, olds)
    local out = {}
    for kid in pairs(olds) do out[kid] = {} end
    local function scan(c)
        local items = c:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local b = out[it:getKeyId()]
            if b then
                b[#b + 1] = { it, c }
            elseif it:getType() == "KeyRing" or it:hasTag(ItemTag.KEY_RING) then
                scan(it:getInventory())
            end
        end
    end
    scan(inv)
    return out
end

function K.sweep(player)
    if not player then return 0 end
    local now = getTimestampMs()
    prune(now)
    local inv = player:getInventory()
    if not inv:containsTypeRecurse("Base.CarKey") then return 0 end
    local v = player:getVehicle()
    local hold = v and v:getDriver() == player and v:isEngineStarted() and not v:isKeysInIgnition()
        and not v:isHotwired() and v:getKeyId() or nil
    local reg, n, olds = registry(), 0, {}
    local list = inv:getAllTypeRecurse("Base.CarKey")
    for i = 0, list:size() - 1 do
        local key = list:get(i)
        local kid = key:getKeyId()
        local car = reg[tostring(kid)]
        if car and kid == hold then
            K.stats.holds = K.stats.holds + 1
            T.log("key card: the motor is starting, " .. player:getUsername() .. "'s key waits for the ignition")
        elseif car then
            local oldId = key:getID()
            if replace(key, K.CARD, kid, nil, { car }) then
                n = n + 1
                olds[kid] = olds[kid] or {}
                table.insert(olds[kid], oldId)
            end
        end
    end
    if n == 0 then return 0 end
    local name, keys = player:getUsername(), keysOf(inv, olds)
    for kid, ids in pairs(olds) do
        for _, id in ipairs(ids) do swapped[name .. ":" .. id] = { keys = keys[kid], at = now } end
    end
    K.stats.swaps = K.stats.swaps + n
    T.log("key card: swapped " .. n .. " car key(s) for " .. name)
    return n
end

-- Vanilla "vehicle" commands, looked at one tick later (after vanilla's handler, whichever of us registered first;
-- VehicleCommands.lua:470-482). putKeyInIgnition from the player we swapped this CarKey for: the client's start beat
-- the swap, vanilla took a key with that keyId out of the inventory (BaseVehicle.java:8726; our card, or another key
-- of the car first in the server's order) and the client still holds it. Every key of the car that was on the player
-- after the swap and is no longer in its container on the server is removed there on the client too (a no-op where the
-- client moved it as well); both ends keep the CarKey in the ignition, swapped once it comes back. Item ids travel as
-- the client sent them, hence the username in the record. getKey (admin "Get Key" in the vehicle spawner and the
-- mechanics menu, VehicleCommands.lua:317-327): no client action asks for the swap, so sweep here.
local later = {}
local function laterTick()
    Events.OnTick.Remove(laterTick)
    local jobs = later
    later = {}
    for _, fn in ipairs(jobs) do fn() end
end
local function nextTick(fn)
    if #later == 0 then Events.OnTick.Add(laterTick) end
    later[#later + 1] = fn
end
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "vehicle" or not player then return end
    if command == "getKey" then -- vanilla's own check (VehicleCommands.lua:319): no free sweeps past the command budget
        if checkPermissions(player, Capability.UseMechanicsCheat) then nextTick(function() K.sweep(player) end) end
        return
    end
    local key = command == "putKeyInIgnition" and type(args) == "table" and args.key
    if not key or not instanceof(key, "Key") then return end
    prune(getTimestampMs())
    local k = player:getUsername() .. ":" .. key:getID()
    local rec = swapped[k]
    if not rec then return end
    swapped[k] = nil
    nextTick(function()
        local n = 0
        for _, e in ipairs(rec.keys) do
            local item, cont = e[1], e[2]
            if cont and not cont:getItemWithID(item:getID()) then
                sendRemoveItemFromContainer(cont, item)
                n = n + 1
            end
        end
        if n == 0 then return end
        K.stats.ghosts = K.stats.ghosts + n
        T.log("key card: a start beat the swap, removed " .. n .. " key(s) on " .. player:getUsername() .. "'s client")
    end)
end)

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
    T.Remote.remember(vehicle) -- the phone app's last record (Remote.lua)
end

-- one flash to lock, two to unlock (Sentry's flash: headlights + light parts, synced to every client).
-- Lock: horn chirp, each client within CHIRP_TILES plays and stops it itself (KeysUI keyChirp; once per client,
-- T.sendClients); playServerSound cannot stop a sound. Neither path adds a world sound (zombies). Unlock: the KeyAlert
-- beep.
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
        K.stats.chirps = K.stats.chirps + T.sendClients(function(p)
            local dx, dy = p:getX() - x, p:getY() - y
            return dx * dx + dy * dy <= r2
        end, "keyChirp", out)
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
    -- VehicleManager present: its PASSENGER right too, as the app's lock / unlock (Remote.lua VM_CODES); the card
    -- alone is anyone's who picked it up, and the tap unlocks the whole car and disarms sentry without the vanilla
    -- actions VehicleManager guards. Unclaimed cars and no VehicleManager: the card is enough.
    if ok then ok, why = T.Remote.vmAllows(player, v, { "PASSENGER" }) end
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
    K.register(v) -- this car is in the registry before its model is read
    local cars = carsOf(ids)
    if not replace(phone, K.PHONE_KEY, v:getKeyId(), ids, cars) then return end
    K.stats.pairs = K.stats.pairs + 1
    T.log("phone key paired vid=" .. v:getId() .. " cars=" .. #ids .. " by " .. player:getUsername()
        .. (why and " (no card: " .. why .. ")" or ""))
    T.send(player, "phonePaired", { vid = v:getId(), car = carName(v), n = #ids })
end

-- "Remove from phone > car": anywhere outside a car, the phone key on you. The item's keyId moves to the car paired
-- last of those left; the last car out leaves a plain phone (no keyId, no record). Not in a car: the phone key may be
-- on its way into the ignition, and swapping such a key doubles it there (keys.md "IgnitionDup").
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
    local car = registry()[tostring(key)] -- nil: the client names it "Tesla"
    local done
    if #left == 0 then
        done = replace(phone, K.PHONE, -1, left)
    else
        done = replace(phone, K.PHONE_KEY, left[#left], left, carsOf(left))
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
