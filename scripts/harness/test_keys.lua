-- Key card and phone key: CarKey -> key card swap, tap rules and the raw keyTap command, phone pairing, walk-away lock
-- conditions, phone loot injection.
local F = dofile("scripts/harness/park_fakes.lua")
local check = (H and H.check) or function(ok, label) print((ok and "  PASS  " or "  FAIL  ") .. label); if not ok then error(label) end end

require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/Battery"
require "MinidoracatTesla/Inbox"
require "MinidoracatTesla/Sentry"
local T = MinidoracatTesla
local S = T.Sentry
local statsBefore = { flashes = S.stats.flashes, tickAdds = S.stats.tickAdds, tickRemoves = S.stats.tickRemoves }

-- ------------------------------------------------------------------ items and containers (vanilla semantics)
local nextItem = 1000
local function item(ft, keyId)
    local it = { ft = ft, keyId = keyId or -1, id = nextItem }
    nextItem = nextItem + 1
    function it:getFullType() return self.ft end
    function it:getType() return (self.ft:gsub("^Base%.", "")) end
    function it:getKeyId() return self.keyId end
    function it:setKeyId(k) self.keyId = k end
    function it:getID() return self.id end
    function it:getDisplayName() return self.ft end -- what a dedicated server returns (tesla-keys-1026e)
    function it:setName(n) self.name = n end
    function it:getContainer() return self.cont end
    function it:hasModData() return self.md ~= nil end
    function it:getModData() self.md = self.md or {}; return self.md end
    return it
end
local function typeIs(it, t) return it.ft == t or it:getType() == t end
local function jlist(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end

local container
local function walk(c, fn)
    for _, it in ipairs(c.items) do
        if fn(it) then return it end
        if it.inv then local r = walk(it.inv, fn); if r then return r end end
    end
end
container = function(...)
    local c = { items = {} }
    function c:AddItem(it) it.cont = self; self.items[#self.items + 1] = it; return it end
    function c:Remove(it)
        for i, x in ipairs(self.items) do if x == it then table.remove(self.items, i); it.cont = nil; return end end
    end
    function c:getFirstTypeEvalArgRecurse(t, fn, arg) return walk(self, function(it) return typeIs(it, t) and fn(it, arg) end) end
    function c:containsTypeRecurse(t) return walk(self, function(it) return typeIs(it, t) end) ~= nil end
    function c:getAllTypeRecurse(t)
        local out = {}
        walk(self, function(it) if typeIs(it, t) then out[#out + 1] = it end end)
        return jlist(out)
    end
    function c:getItemWithIDRecursiv(id) return walk(self, function(it) return it.id == id end) end
    -- ItemContainer.java:3242-3256: loose keys and keyrings only, not wallets or bags
    function c:haveThisKeyId(id)
        for _, it in ipairs(self.items) do
            if it.keyId == id and it.isKey then return it end
            if it.ft == "Base.KeyRing" and it.inv then local r = it.inv:haveThisKeyId(id); if r then return r end end
        end
    end
    for _, it in ipairs({ ... }) do c:AddItem(it) end
    return c
end
local function bag(ft, ...)
    local b = item(ft)
    b.inv = container(...)
    return b
end
local function key(ft, keyId) local k = item(ft, keyId); k.isKey = true; return k end

local sentPackets = { add = 0, remove = 0 }
getItemNameFromFullType = function(ft) return "ItemName_" .. ft end
instanceItem = function(ft) return key(ft) end
sendAddItemToContainer = function() sentPackets.add = sentPackets.add + 1 end
sendRemoveItemFromContainer = function() sentPackets.remove = sentPackets.remove + 1 end
local sounds = {}
playServerSound = function(name) sounds[#sounds + 1] = name end

-- ------------------------------------------------------------------ vehicle with doors, players with positions
local function door(id)
    local p = { id = id, d = { locked = false, open = false, broken = false } }
    function p:getId() return self.id end
    function p:getArea() return self.area end
    function p:getDoor() return self.doorObj end
    function p:getInventoryItem() return {} end
    local d = p.d
    p.doorObj = {
        isLocked = function() return d.locked end, setLocked = function(_, b) d.locked = b end,
        isOpen = function() return d.open end, setOpen = function(_, b) d.open = b end,
        isLockBroken = function() return d.broken end,
    }
    return p
end
local function tesla(o)
    local v = F.track(F.vehicle(o))
    v.doors = { door("DoorFrontLeft"), door("DoorFrontRight"), door("DoorRearLeft"), door("DoorRearRight") }
    v.doors[1].area = "SeatFrontLeft"
    v.trunk, v.frunk = door("TrunkDoor"), door("EngineDoor")
    v.parts.TrunkDoor, v.parts.EngineDoor = v.trunk, v.frunk
    v.doorTx = 0
    local all = {}
    for _, p in pairs(v.parts) do all[#all + 1] = p end
    for _, d in ipairs(v.doors) do all[#all + 1] = d end
    for _, p in ipairs(all) do p.getVehicle = p.getVehicle or function() return v end end
    function v:getPassengerDoor(seat) return self.doors[seat + 1] end
    function v:getMaxPassengers() return 4 end
    function v:getPartCount() return #all end
    function v:getPartByIndex(i) local p = all[i + 1]; p.getDoor = p.getDoor or function() return nil end; return p end
    function v:areAllDoorsLocked()
        for _, d in ipairs(self.doors) do if not d.d.locked then return false end end
        return true
    end
    function v:transmitPartDoor() self.doorTx = self.doorTx + 1 end
    function v:canUnlockDoor(part, chr) -- BaseVehicle.java:1275-1301 (seat and child window left out)
        return part.d.locked and not part.d.broken and chr:getInventory():haveThisKeyId(self.keyId) ~= nil
    end
    function v:getColorHue() return 0.6 end -- Liftgate's shell bits: no door open in these checks
    function v:getAreaCenter(area)
        if area ~= "SeatFrontLeft" then return nil end
        return { getX = function() return self.x - 1 end, getY = function() return self.y end }
    end
    function v:getCurrentKey() return self.ignitionKey end
    function v:getSquare() return {} end
    return v
end

local oids = 0
local function player(name, inv, x, y, num)
    oids = oids + 1
    local p = { name = name, inv = inv, x = x, y = y, num = num or 0, oid = oids * 4 + (num or 0) }
    function p:getOnlineID() return self.oid end -- slot * 4 + split-screen index, like H.player
    function p:getSteamID() return 0 end
    function p:getUsername() return self.name end
    function p:getPlayerNum() return self.num end
    function p:getVehicle() return self.vehicle end
    function p:getInventory() return self.inv end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:DistTo(v) local dx, dy = self.x - v:getX(), self.y - v:getY(); return math.sqrt(dx * dx + dy * dy) end
    return p
end

H.stub("Vehicles/TimedActions/ISUnlockVehicleDoor") -- park_fakes made the class; Keys.lua wraps start() and complete()
ISUnlockVehicleDoor.start = ISUnlockVehicleDoor.start or function() return true end
local unlockBefore = { start = ISUnlockVehicleDoor.start, complete = ISUnlockVehicleDoor.complete } -- restored at the end
-- vanilla ISStartVehicleEngine:complete (ISStartVehicleEngine.lua:26-44): haveKey from haveThisKeyId only
H.stub("Vehicles/TimedActions/ISStartVehicleEngine")
ISStartVehicleEngine = { complete = function(self)
    local veh = self.character:getVehicle()
    veh:tryStartEngine(self.character:getInventory():haveThisKeyId(veh:getKeyId()) ~= nil)
    return true
end }
require "MinidoracatTesla/Keys"
-- server side of Liftgate.lua (lockLids, relock, the vanilla lock wraps): an earlier test may have loaded it as a client.
-- It wraps the harness's vanilla actions; the plain ones go back at the end for the tests after this one.
local ACTIONS = { "ISOpenVehicleDoor", "ISCloseVehicleDoor", "ISLockDoors", "ISLockVehicleDoor" }
local plain = {}
for _, n in ipairs(ACTIONS) do plain[n] = _G[n].complete end
dofile("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/shared/MinidoracatTesla/Liftgate.lua")
require "MinidoracatTesla/KeyActions"
local K = T.Keys
local cmds = T.ServerCommands
local function lastDeny() local m = F.lastSent("deny"); return m and m.args.reason end

-- ------------------------------------------------------------------ registry and the CarKey swap
local v = tesla({ pct = 80 })
local other = F.track(F.vehicle({}))
function other:getScriptName() return "Base.CarNormal" end
F.fire("OnSpawnVehicleEnd", v)
F.fire("OnSpawnVehicleEnd", other)
local reg = T.Store.get("keyIds")
check(reg[tostring(v.keyId)] == "MinidoracatTesla_ModelY", "registry: a loaded Tesla's keyId is recorded with its model name")
check(reg[tostring(other.keyId)] == nil, "registry: other cars are not recorded")
check(H.moddata.MinidoracatTesla_KeyIds == nil and H.gos[T.Store.SYSTEM].md.keyIds == reg,
    "registry: in the server-only store, no Global ModData table a client could request")

local teslaKey, plainKey = key("Base.CarKey", v.keyId), key("Base.CarKey", other.keyId)
local wallet = bag("Base.Wallet", teslaKey)
local ownerInv = container(wallet, plainKey)
local owner = player("owner", ownerInv, v.x - 1, v.y)
owner.vehicle = v
cmds.keySweep(owner, {})
check(teslaKey.cont == wallet.inv, "sweep: refused while seated (key may be going in or out of the ignition)")
owner.vehicle = nil
cmds.keySweep(owner, {})
local card = wallet.inv.items[1]
check(card and card.ft == K.CARD and card.keyId == v.keyId, "sweep: the Tesla key became a key card with the same keyId")
check(card and card.cont == wallet.inv and teslaKey.cont == nil, "sweep: swapped in place (still in the wallet)")
check(card and card.name == "ItemName_" .. K.CARD .. " - IGUI_VehicleNameMinidoracatTesla_ModelY", "sweep: named like the vanilla key (item - car)")
check(plainKey.cont == ownerInv and plainKey.ft == "Base.CarKey", "sweep: other cars' keys untouched")
check(sentPackets.add == 1 and sentPackets.remove == 1, "sweep: one remove and one add packet")
cmds.keySweep(owner, {})
check(sentPackets.add == 1, "sweep: nothing left to swap the second time")

-- ------------------------------------------------------------------ tap rules (card in the wallet counts)
local ok, why = K.canTap(owner, v)
check(ok == true, "tap: card in the wallet, at the driver door -> ok (" .. tostring(why) .. ")")
owner.x = v.x - 4
ok, why = K.canTap(owner, v)
check(not ok and why == "TOO_FAR", "tap: 3 tiles from the reader -> TOO_FAR")
owner.x = v.x - 1
owner.vehicle = v
ok, why = K.canTap(owner, v)
check(not ok and why == "NOT_OUTSIDE", "tap: from the seat -> NOT_OUTSIDE")
owner.vehicle = nil
local thief = player("thief", container(key("Base.CarKey", v.keyId)), v.x - 1, v.y)
ok, why = K.canTap(thief, v)
check(not ok and why == "NO_KEY_CARD", "tap: a plain CarKey is not a card -> NO_KEY_CARD")

-- raw keyTap from a player without the card: denied, doors unchanged, no flash
F.sent = {}
local flashes0 = S.stats.flashes
cmds.keyTap(player("stranger", container(), v.x - 1, v.y), { vid = v:getId() })
check(lastDeny() == "NO_KEY_CARD" and not v.doors[1].d.locked and S.stats.flashes == flashes0,
    "keyTap raw command without a card: denied, nothing locked, no flash")
cmds.keyTap(owner, { vid = v:getId() + 0.5 })
check(lastDeny() == "NO_VEHICLE", "keyTap: fractional vid -> NO_VEHICLE")

-- owner taps: lock all four doors and the trunk, one flash (2 toggles), beep; tap again: unlock, two flashes
v.doors[3].d.broken = true
local onlineBefore = F.online
local farAway = player("faraway", container(), v.x + K.CHIRP_TILES + 1, v.y)
F.online = { owner, farAway }
F.sent = {}
local beeps0 = #sounds
cmds.keyTap(owner, { vid = v:getId() })
local lockedAll = v.doors[1].d.locked and v.doors[2].d.locked and v.doors[4].d.locked and v.trunk.d.locked
check(lockedAll and not v.doors[3].d.locked, "keyTap: locks every door and the trunk, skips a broken lock")
check(v.frunk.d.locked, "keyTap: the frunk lid locks with the car (a stranger's vanilla Open Hood stays shut)")
local chirp = F.lastSent("keyChirp")
local chirpsTo = 0
for _, m in ipairs(F.sent) do if m.cmd == "keyChirp" then chirpsTo = chirpsTo + 1 end end
check(S.stats.flashes == flashes0 + 1 and chirp and chirp.to == "owner" and chirp.args.vid == v:getId() and chirpsTo == 1
    and #sounds == beeps0, "keyTap lock: flash + horn chirp sent to players within CHIRP_TILES only, no playServerSound")
v.headlights = false
v.toggles = 0
F.runTicks(50, 450)
check(v.toggles == 2 and v.headlights == false and F.handlers("OnTick") == 0, "keyTap lock: one flash (2 toggles), lights restored, OnTick removed")
v.doors[3].d.broken = false
v.doors[3].d.locked = true
v.parts.GasTank:getModData().sentry = { by = "owner", at = F.hours, kwh = 50, since = F.hours }
cmds.keyTap(owner, { vid = v:getId() })
check(not v.doors[1].d.locked and not v.trunk.d.locked and not v.frunk.d.locked, "keyTap again: unlocks, the frunk lid too")
check(sounds[#sounds] == K.SOUND and #sounds == beeps0 + 1, "keyTap unlock: KeyAlert beep (playServerSound), no chirp")
F.online = onlineBefore
v.toggles = 0
F.runTicks(50, 450)
check(v.toggles == 4, "keyTap unlock: two flashes (4 toggles)")
check(v.parts.GasTank:getModData().sentry == nil, "keyTap unlock: the owner's card disarms sentry")

-- ------------------------------------------------------------------ the lids lock with the car, every way it locks
H.section("frunk lid and liftgate follow the car lock")
local function allDoors(b) for _, d in ipairs(v.doors) do d.d.locked = b end end
v.frunk.d.broken = true
K.setLocked(v, true)
check(not v.frunk.d.locked and v.trunk.d.locked, "a broken frunk lock is never locked (it could not open again)")
v.frunk.d.broken = false
K.setLocked(v, false)
v.trunk.d.locked, v.trunk.d.broken = true, true -- a world-spawn liftgate jammed locked (Vehicles.Create.TrunkDoor)
K.setLocked(v, false)
check(not v.trunk.d.locked, "a liftgate jammed locked still unlocks with the car (as setTrunkLocked did)")
v.trunk.d.broken = false
ISLockDoors.complete({ vehicle = v, locked = true, character = owner }) -- inside: vanilla "Lock Doors"
check(v:areAllDoorsLocked() and v.frunk.d.locked and v.trunk.d.locked, "vanilla Lock Doors inside: the lids lock too")
ISLockDoors.complete({ vehicle = v, locked = false, character = owner })
check(not v.frunk.d.locked and not v.trunk.d.locked, "vanilla Unlock Doors inside: the lids unlock too")
allDoors(true)
v.doors[2].d.locked = false
ISLockVehicleDoor.complete({ vehicle = v, part = v.doors[1], character = owner })
check(not v.frunk.d.locked, "one door locked with the key, another still open: lids stay unlocked")
ISLockVehicleDoor.complete({ vehicle = v, part = v.doors[2], character = owner })
check(v.frunk.d.locked and v.trunk.d.locked, "the last door locked with the key: the car is locked, lids too")
K.setLocked(v, false)
allDoors(true) -- an older save or a world spawn: cabin locked, lids not (vanilla never locks the hood)
local tx0 = v.doorTx
F.fire("OnSpawnVehicleEnd", v)
check(v.frunk.d.locked and v.trunk.d.locked and v.doorTx == tx0 + 2, "loaded locked: the shut lids lock and sync")
allDoors(false)
v.frunk.d.locked, v.trunk.d.locked = false, false
v.frunk.d.open = true
allDoors(true)
F.fire("OnSpawnVehicleEnd", v)
check(not v.frunk.d.locked, "loaded locked with the lid up: left open and unlocked (locks when it shuts)")
ISCloseVehicleDoor.complete({ vehicle = v, part = v.frunk, character = owner })
check(not v.frunk.d.open and v.frunk.d.locked, "lid shut by hand on a locked car: locked again")
K.setLocked(v, false)

-- ------------------------------------------------------------------ phone pairing
local phone = item(K.PHONE)
ownerInv:AddItem(phone)
ok, why = K.canPair(owner, v, phone)
check(not ok and why == "NOT_INSIDE", "pair: outside -> NOT_INSIDE")
owner.vehicle = v
local noCard = player("nocard", container(item(K.PHONE)), v.x, v.y)
noCard.vehicle = v
ok, why = K.canPair(noCard, v, noCard.inv.items[1])
check(not ok and why == "NO_KEY_CARD", "pair: seated without the card -> NO_KEY_CARD")
v.ignitionKey = item(K.CARD, v.keyId)
ok = K.canPair(noCard, v, noCard.inv.items[1])
check(ok == true, "pair: the card on the console reader (in the ignition) counts")
v.ignitionKey = nil
check(K.canPair(owner, v, item("Base.Pager")) == false, "pair: not a phone -> refused")
F.sent = {}
cmds.phonePair(owner, { vid = v:getId(), id = phone:getID() })
local pk = ownerInv.items[#ownerInv.items]
check(pk.ft == K.PHONE_KEY and pk.keyId == v.keyId and phone.cont == nil, "pair: the phone became this car's phone key")
check(F.lastSent("phonePaired") ~= nil, "pair: client told (halo)")
cmds.phonePair(owner, { vid = v:getId(), id = pk:getID() })
check(lastDeny() == "ALREADY_PAIRED", "pair: same car again -> ALREADY_PAIRED")
cmds.phonePair(noCard, { vid = v:getId(), id = noCard.inv.items[1]:getID() })
check(lastDeny() == "NO_KEY_CARD" and noCard.inv.items[1].ft == K.PHONE, "phonePair raw command without the card: denied, phone unchanged")

-- ------------------------------------------------------------------ walk-away lock
owner.vehicle = nil
owner.x = v.x - 3
ok, why = K.canAutoLock(owner, v)
check(not ok and why == nil, "auto-lock: 3 tiles away -> not yet, nothing said")
owner.x = v.x - K.LOCK_DIST
local function autoLockReason() local a, b = K.canAutoLock(owner, v); return a, b end
v.parts.GasTank:getModData().camp = { by = "owner", at = F.hours }
v.passengers = 1
check(select(2, autoLockReason()) == "AUTOLOCK_CAMP", "auto-lock: camp on, someone inside -> AUTOLOCK_CAMP")
v.passengers = 0
check(autoLockReason() == true, "auto-lock: camp on but nobody inside -> lock (camp stops itself, Camp.lua 'left')")
v.parts.GasTank:getModData().camp = nil
v.passengers = 1
check(select(2, autoLockReason()) == "AUTOLOCK_OCCUPIED", "auto-lock: someone inside -> AUTOLOCK_OCCUPIED")
v.passengers = 0
v.trunk.d.open = true
check(select(2, autoLockReason()) == "AUTOLOCK_DOOR_OPEN", "auto-lock: trunk open -> AUTOLOCK_DOOR_OPEN")
v.trunk.d.open = false
check(autoLockReason() == true, "auto-lock: away, empty, closed -> lock")
check(K.canAutoLock(player("cardonly", container(item(K.CARD, v.keyId)), owner.x, owner.y), v) == false,
    "auto-lock: a key card alone never auto-locks (manual: key card has no walk-away lock)")
F.sent = {}
v.parts.GasTank:getModData().camp = { by = "owner", at = F.hours }
v.passengers = 1
cmds.autoLock(owner, { vid = v:getId() })
local skip = F.lastSent("autoLockSkip")
check(skip and skip.args.reason == "AUTOLOCK_CAMP" and F.lastSent("deny") == nil and not v:areAllDoorsLocked(),
    "autoLock command, camp on with someone inside: autoLockSkip with the reason (client says it, stops asking), nothing locked")
v.parts.GasTank:getModData().camp, v.passengers = nil, 0
owner.x = v.x - 4
F.sent = {}
cmds.autoLock(owner, { vid = v:getId() })
skip = F.lastSent("autoLockSkip")
check(skip and skip.args.reason == nil and not v:areAllDoorsLocked(), "autoLock command, server sees 4 tiles: skip without a reason (client asks again)")
owner.x = v.x - K.LOCK_DIST
F.sent = {}
cmds.autoLock(owner, { vid = v:getId() })
check(v:areAllDoorsLocked() and v.trunk.d.locked and F.lastSent("autoLocked") ~= nil, "autoLock command: locked, client told")
F.runTicks(50, 450)
F.sent = {}
cmds.autoLock(owner, { vid = v:getId() })
check(F.lastSent("autoLocked") == nil and F.lastSent("autoLockSkip").args.reason == nil, "autoLock again: already locked, silent skip")

-- ------------------------------------------------------------------ pulling the handle with the phone key in a bag
ownerInv:Remove(pk)
local backpack = bag("Base.Bag_Schoolbag", pk)
ownerInv:AddItem(backpack)
check(ownerInv:haveThisKeyId(v.keyId) == nil and K.phoneKey(owner, v) == pk, "handle: phone key in a bag, vanilla key lookup misses it")
owner.x = v.x - 1
v.parts.GasTank:getModData().sentry = { by = "someoneElse", at = F.hours, kwh = 50, since = F.hours }
local tx, fl = v.doorTx, S.stats.flashes
local unlock = { vehicle = v, part = v.doors[1], character = owner }
ISUnlockVehicleDoor.complete(unlock)
check(not v.doors[1].d.locked and v.doors[2].d.locked and v.doorTx == tx + 1, "handle (server complete): that door unlocked and synced, the others stay locked")
check(v.parts.GasTank:getModData().sentry == nil and S.stats.flashes == fl, "handle: phone key in a bag counts as the owner -> sentry disarmed, no flash")
v.doors[1].d.locked = true
local stranger = player("stranger", container(), v.x - 1, v.y)
ISUnlockVehicleDoor.complete({ vehicle = v, part = v.doors[1], character = stranger })
check(v.doors[1].d.locked, "handle: no key -> stays locked")
-- the frunk lid locks with the car; vanilla's hood entries (Use.EngineDoor, the Mechanics radial) queue no unlock for
-- a key holder, so opening it has to unlock it for whoever may (Keys.lua K.lidUnlock)
check(v:areAllDoorsLocked() and v.frunk.d.locked, "frunk: locked with the car (walk-away lock above)")
ISOpenVehicleDoor.complete({ vehicle = v, part = v.frunk, character = stranger })
check(v.frunk.d.locked and not v.frunk.d.open, "frunk: a stranger's open leaves it shut and locked")
ISOpenVehicleDoor.complete({ vehicle = v, part = v.frunk, character = owner })
check(not v.frunk.d.locked and v.frunk.d.open, "frunk: the owner (phone key in a bag) opens it straight away, no unlock step")
ISCloseVehicleDoor.complete({ vehicle = v, part = v.frunk, character = owner })
check(not v.frunk.d.open and v.frunk.d.locked, "frunk: shut again on the locked car -> locked")
local loose = player("loosekey", container(key("Base.CarKey", v.keyId)), v.x - 1, v.y)
ISOpenVehicleDoor.complete({ vehicle = v, part = v.frunk, character = loose })
check(v.frunk.d.open, "frunk: a key in hand opens it too (vanilla canUnlockDoor)")
ISCloseVehicleDoor.complete({ vehicle = v, part = v.frunk, character = owner })
check(T.authorized(owner, v, "PASSENGER") == true and T.authorized(stranger, v, "PASSENGER") == false,
    "authorized (camp, charging): phone key in a bag counts, no key does not")
local walletOnly = player("walletonly", container(bag("Base.Wallet", item(K.CARD, v.keyId))), v.x - 1, v.y)
ISUnlockVehicleDoor.complete({ vehicle = v, part = v.doors[1], character = walletOnly })
check(v.doors[1].d.locked, "handle: key card in the wallet -> stays locked (tap the reader)")
ISOpenVehicleDoor.complete({ vehicle = v, part = v.frunk, character = walletOnly })
check(v.frunk.d.locked and not v.frunk.d.open, "frunk: the key card in a wallet does not open it (tap the reader)")
MinidoracatVehicleManagerAPI = { canUse = function(p, _, code) return code == "PASSENGER" and p == stranger, "SHARED" end }
ISOpenVehicleDoor.complete({ vehicle = v, part = v.frunk, character = stranger })
check(v.frunk.d.locked and not v.frunk.d.open, "frunk: a VehicleManager rider only (PASSENGER) is not the hood's right")
MinidoracatVehicleManagerAPI = { canUse = function(p, _, code) return code == "REPAIR" and p == stranger, "SHARED" end }
ISOpenVehicleDoor.complete({ vehicle = v, part = v.frunk, character = stranger })
check(v.frunk.d.open, "frunk: a VehicleManager mechanic (REPAIR shared, virtual key, no item) opens it")
ISCloseVehicleDoor.complete({ vehicle = v, part = v.frunk, character = stranger })
MinidoracatVehicleManagerAPI = { canUse = function(p, _, code) return code == "SALVAGE" and p == stranger, "SHARED" end }
ISOpenVehicleDoor.complete({ vehicle = v, part = v.frunk, character = stranger })
check(v.frunk.d.open, "frunk: a VehicleManager salvager (SALVAGE shared) opens it too (VM's own hood rule)")
ISCloseVehicleDoor.complete({ vehicle = v, part = v.frunk, character = stranger })
SandboxVars.MinidoracatVehicleManager = { VirtualKey = false } -- its "Off keeps the vanilla key rules"
ISOpenVehicleDoor.complete({ vehicle = v, part = v.frunk, character = stranger })
check(v.frunk.d.locked and not v.frunk.d.open, "frunk: VehicleManager VirtualKey off -> a rider without a key stays out")
SandboxVars.MinidoracatVehicleManager = nil
MinidoracatVehicleManagerAPI = { canUse = function() return true, "UNCLAIMED" end }
ISOpenVehicleDoor.complete({ vehicle = v, part = v.frunk, character = stranger })
check(v.frunk.d.locked and not v.frunk.d.open, "frunk: VehicleManager UNCLAIMED is nobody's key")
MinidoracatVehicleManagerAPI = nil
-- the action's vehicle and part are separate arguments: this car's key must not unlock another car's lid or door
local otherLid, otherDoor = door("EngineDoor"), door("DoorFrontLeft")
otherLid.d.locked, otherDoor.d.locked = true, true
otherLid.getVehicle = function() return {} end
otherDoor.getVehicle = otherLid.getVehicle
ISOpenVehicleDoor.complete({ vehicle = v, part = otherLid, character = loose })
check(otherLid.d.locked and not otherLid.d.open, "frunk: a key for car A does not unlock car B's lid (vehicle/part mismatch)")
check(not K.phoneUnlock(v, otherDoor, owner) and otherDoor.d.locked, "handle: phone key for car A leaves car B's door locked")
otherLid.d.locked, otherLid.d.open = false, true -- car B's lid, unlocked and open
ISCloseVehicleDoor.complete({ vehicle = v, part = otherLid, character = loose })
check(v:areAllDoorsLocked() and not otherLid.d.open and not otherLid.d.locked,
    "frunk: shutting car B's lid in an action naming locked car A does not lock B's lid")
v.doors[1].d.broken = true
ISUnlockVehicleDoor.complete(unlock)
check(v.doors[1].d.locked, "handle: broken lock -> stays locked")
v.doors[1].d.broken = false
local srv = isServer
isServer = function() return false end
ISUnlockVehicleDoor.complete(unlock)
check(v.doors[1].d.locked, "handle: complete() off the server (SP runs it in start) -> no unlock there")
ISUnlockVehicleDoor.start(unlock)
check(not v.doors[1].d.locked, "handle (SP start): phone key in a bag unlocks before the vanilla lock check")
isServer = srv
v.doors[1].d.locked = true
local cli = isClient
isClient = function() return true end
isServer = function() return false end
ISUnlockVehicleDoor.start(unlock)
check(v.doors[1].d.locked, "handle (MP client start): never unlocks locally")
isClient, isServer = cli, srv
ISUnlockVehicleDoor.start, ISUnlockVehicleDoor.complete = unlockBefore.start, unlockBefore.complete -- other tests' fake parts have no getDoor

-- ------------------------------------------------------------------ starting with the phone key in a bag
local starts = {}
function v:tryStartEngine(haveKey) starts[#starts + 1] = haveKey end
function v:isDriver(p) return p.vehicle == self end
function v:isHotwired() return self.hotwired == true end
local function start(p) starts = {}; ISStartVehicleEngine.complete({ character = p }); return starts[1] end
owner.vehicle, walletOnly.vehicle, stranger.vehicle = v, v, v
check(start(owner) == true, "start: phone key in a bag -> tryStartEngine(true) (vanilla would pass false)")
check(start(walletOnly) == false, "start: key card only in the wallet -> vanilla haveKey false (tap = put it on the reader)")
check(start(stranger) == false, "start: no key -> vanilla haveKey false")
local cardLoose = player("cardloose", container(key(K.CARD, v.keyId)), v.x, v.y)
cardLoose.vehicle = v
check(start(cardLoose) == true and K.bagPhoneStarts(cardLoose, v) == false, "start: loose key card -> vanilla path (goes into the ignition)")
v.hotwired = true
check(K.bagPhoneStarts(owner, v) == false, "start: hotwired -> vanilla path")
v.hotwired, owner.vehicle, walletOnly.vehicle, stranger.vehicle = nil, nil, nil, nil

-- ------------------------------------------------------------------ one phone key, several cars (app v2)
H.section("one phone key, several cars")
local carA, carB = tesla({ pct = 70 }), tesla({ pct = 60 })
carB.x, carB.y = carA.x + 40, carA.y
F.fire("OnSpawnVehicleEnd", carA)
F.fire("OnSpawnVehicleEnd", carB)
local phones = T.Store.get("phones")
local mInv = container(key(K.CARD, carA.keyId), key(K.CARD, carB.keyId), item(K.PHONE))
local multi = player("multi", mInv, carA.x, carA.y)
local function phoneOf(inv) return inv:getFirstTypeEvalArgRecurse(K.PHONE_KEY, function() return true end) end
multi.vehicle = carA
cmds.phonePair(multi, { vid = carA:getId(), id = mInv.items[3]:getID() })
local ph = phoneOf(mInv)
local r1 = phones[tostring(ph.id)]
check(ph and ph.keyId == carA.keyId and r1 and #r1 == 1 and r1[1] == carA.keyId and ph.md[K.PAIRED][1] == carA.keyId,
    "first pairing: keyId = car A, recorded { A } (every phone key: no two share an item id), modData mirror { A }")
-- an unrelated plain phone on the same item id (ids are random) pairs: that phone key's record stays
local stray = item(K.PHONE)
stray.id = ph.id
local strayInv = container(key(K.CARD, carB.keyId), stray)
local strayP = player("stray", strayInv, carB.x, carB.y)
strayP.vehicle = carB
cmds.phonePair(strayP, { vid = carB:getId(), id = stray.id })
local strayKey = phoneOf(strayInv)
check(strayKey and strayKey.id ~= ph.id and phones[tostring(ph.id)] == r1 and not K.pairedWith(ph, carB.keyId),
    "a plain phone sharing the item id pairs elsewhere: a new id, the first phone's record untouched")
phones[tostring(strayKey.id)] = nil
check(ph.name == "ItemName_" .. K.PHONE_KEY .. " - IGUI_VehicleNameMinidoracatTesla_ModelY", "one car: named like before (item - car)")
multi.vehicle = carB
check(K.canPair(multi, carB, ph) == true, "a phone key for A, seated in B with B's card: may add B")
local oldId = ph.id
F.sent = {}
cmds.phonePair(multi, { vid = carB:getId(), id = ph.id })
ph = phoneOf(mInv)
local rec = phones[tostring(ph.id)]
check(ph.keyId == carB.keyId and rec and rec[1] == carA.keyId and rec[2] == carB.keyId and phones[tostring(oldId)] == nil,
    "add B: the item's keyId = B (paired last), the server record { A, B } follows the new item id")
check(ph.name == "ItemName_" .. K.PHONE_KEY .. " - IGUI_MinidoracatTesla_PhoneCars", "two cars: 'Phone Key - N Teslas'")
check(F.lastSent("phonePaired").args.n == 2, "client told: now 2 cars")
cmds.phonePair(multi, { vid = carB:getId(), id = ph.id })
check(lastDeny() == "ALREADY_PAIRED", "B again -> ALREADY_PAIRED")
multi.vehicle = carA
check(select(2, K.canPair(multi, carA, ph)) == "ALREADY_PAIRED", "A (paired first, not the item's keyId) -> ALREADY_PAIRED too")
-- car A, the one vanilla no longer knows (the item carries B's keyId): handle, start, walk-away lock, T.authorized
mInv:Remove(mInv.items[1]); mInv:Remove(mInv.items[1]) -- the cards go: only the phone key counts from here
multi.vehicle = nil
multi.x = carA.x - 1
check(mInv:haveThisKeyId(carA.keyId) == nil and K.phoneKey(multi, carA) == ph and K.phoneKey(multi, carB) == ph,
    "loose phone key: vanilla lookup misses A, Keys.phoneKey finds it for A and B")
carA.doors[1].d.locked = true
check(K.phoneUnlock(carA, carA.doors[1], multi) and not carA.doors[1].d.locked, "handle on A with the loose two-car phone: unlocked")
carB.doors[1].d.locked = true
check(not K.phoneUnlock(carB, carB.doors[1], multi) and carB.doors[1].d.locked,
    "handle on B: vanilla's own (the item's keyId is B), Tesla's does not double up")
carB.doors[1].d.locked = false
local startsA = {}
function carA:tryStartEngine(h) startsA[#startsA + 1] = h end
function carA:isDriver(p) return p.vehicle == self end
function carA:isHotwired() return false end
multi.vehicle = carA
ISStartVehicleEngine.complete({ character = multi })
check(startsA[1] == true, "start A with the loose phone key carrying B's keyId: tryStartEngine(true)")
multi.vehicle = nil
multi.x = carA.x - K.LOCK_DIST
check(K.canAutoLock(multi, carA) == true, "walk away from A: auto-lock")
check(T.authorized(multi, carA, "PASSENGER") == true and T.legit(multi, carA) == true, "A: authorized and legit (sentry)")
-- a phone paired with A only does nothing at B
local onlyA = player("onlyA", container(key(K.PHONE_KEY, carA.keyId)), carB.x - 1, carB.y)
carB.doors[1].d.locked = true
check(K.phoneKey(onlyA, carB) == nil and not K.phoneUnlock(carB, carB.doors[1], onlyA) and carB.doors[1].d.locked,
    "a phone key for A only: B's handle stays locked")
function carB:tryStartEngine(h) self.startArg = h end
function carB:isDriver(p) return p.vehicle == self end
function carB:isHotwired() return false end
onlyA.vehicle = carB
ISStartVehicleEngine.complete({ character = onlyA })
check(carB.startArg == false and not K.bagPhoneStarts(onlyA, carB), "a phone key for A only: B does not start")
onlyA.vehicle, onlyA.x = nil, carB.x - K.LOCK_DIST
check(K.canAutoLock(onlyA, carB) == false and T.authorized(onlyA, carB, "PASSENGER") == false and not T.legit(onlyA, carB),
    "a phone key for A only: no walk-away lock, not authorized, not legit at B")
-- a client cannot pair itself by writing the modData mirror (SyncItemModDataPacket): the server reads its own record
local forged = onlyA.inv.items[1]
forged:getModData()[K.PAIRED] = { carB.keyId, carA.keyId } -- (the item's keyId last, as a real mirror)
check(not K.pairedWith(forged, carB.keyId) and K.phoneKey(onlyA, carB) == nil, "forged modData list: the server still says no for B")
local cliSide, srvSide = isClient, isServer
isClient, isServer = function() return true end, function() return false end
check(K.pairedWith(forged, carB.keyId) == true, "(an MP client reads the mirror: menus only, the server checks again)")
isClient, isServer = cliSide, srvSide
-- item ids are random, not unique (InventoryItemFactory.java:139): another phone key on a recorded id inherits nothing
local twin = key(K.PHONE_KEY, carA.keyId)
twin.id = ph.id -- ph: { A, B } on the server, keyId B
check(phones[tostring(ph.id)] ~= nil and not K.pairedWith(twin, carB.keyId) and K.pairedWith(ph, carA.keyId),
    "a phone key on the same item id with another keyId: not paired with B (the record is only its own phone's)")
-- handed over (trade, dropped and picked up): the same item, the same id, so its cars go with it, like a vanilla key
local taker = player("taker", container(), carA.x - 1, carA.y)
mInv:Remove(ph); taker.inv:AddItem(ph)
check(K.phoneKey(taker, carA) == ph and K.phoneKey(taker, carB) == ph and K.phoneKey(multi, carA) == nil
    and K.phoneKey(multi, carB) == nil, "the phone key handed over: the new holder opens A and B, the old one neither")
taker.inv:Remove(ph); mInv:AddItem(ph)
-- remove from phone
F.sent = {}
multi.vehicle = carA
cmds.phoneUnpair(multi, { id = ph.id, key = carB.keyId })
check(lastDeny() == "NOT_OUTSIDE" and phoneOf(mInv) == ph, "remove from phone while in a car: NOT_OUTSIDE (no swap near the ignition)")
multi.vehicle = nil
cmds.phoneUnpair(onlyA, { id = ph.id, key = carA.keyId })
check(lastDeny() == "NO_PHONE_KEY" and phoneOf(mInv) == ph, "unpair someone else's phone: NO_PHONE_KEY, unchanged")
cmds.phoneUnpair(multi, { id = ph.id, key = carB.keyId })
ph = phoneOf(mInv)
local r2 = phones[tostring(ph.id)]
check(ph.keyId == carA.keyId and r2 and #r2 == 1 and ph.name:find("VehicleName", 1, true)
    and F.lastSent("phoneUnpaired").args.n == 1, "remove B (the item's keyId): keyId back to A, record { A }, car name again")
check(K.phoneKey(multi, carB) == nil, "removed: B no longer opens")
multi.vehicle = carB
cmds.phonePair(multi, { vid = carB:getId(), id = ph.id })
check(lastDeny() == "NO_KEY_CARD" and phoneOf(mInv).keyId == carA.keyId, "adding B again needs B's card: NO_KEY_CARD, still one car")
multi.vehicle = nil -- (removing is done outside a car)
cmds.phoneUnpair(multi, { id = ph.id, key = carA.keyId })
local plainPhone = mInv.items[#mInv.items]
check(phoneOf(mInv) == nil and plainPhone.ft == K.PHONE and plainPhone.keyId == -1 and not plainPhone.md,
    "remove the last car: a plain phone again (no keyId, no mirror)")
-- removing a car that is not the item's keyId leaves the keyId alone
mInv:AddItem(key(K.CARD, carA.keyId)); mInv:AddItem(key(K.CARD, carB.keyId))
multi.vehicle = carA
cmds.phonePair(multi, { vid = carA:getId(), id = plainPhone.id })
multi.vehicle = carB
local planted, plantedId = { 4242, 4343 }, tostring(nextItem) -- another phone's record already on the next item id
phones[plantedId] = planted
cmds.phonePair(multi, { vid = carB:getId(), id = phoneOf(mInv).id })
check(tostring(phoneOf(mInv).id) ~= plantedId and phones[plantedId] == planted and #K.pairedIds(phoneOf(mInv)) == 2,
    "pairing never takes an item id another phone's record has (new instance), that record untouched")
phones[plantedId] = nil
multi.vehicle = nil
cmds.phoneUnpair(multi, { id = phoneOf(mInv).id, key = carA.keyId })
ph = phoneOf(mInv)
check(ph.keyId == carB.keyId and not K.pairedWith(ph, carA.keyId) and #K.pairedIds(ph) == 1,
    "remove A (paired first): keyId stays B, one car left")
multi.vehicle = nil

-- ------------------------------------------------------------------ phone loot
ProceduralDistributions = { list = { ElectronicStorePhones = { items = { "CordlessPhone", 50 } } } }
F.fire("OnPostDistributionMerge")
F.fire("OnPostDistributionMerge")
local items = ProceduralDistributions.list.ElectronicStorePhones.items
check(#items == 4 and items[3] == K.PHONE and items[4] == K.LOOT.ElectronicStorePhones, "loot: phone added once even when the merge runs twice")

-- ------------------------------------------------------------------ a busy minute against the server's budget
-- The real client (KeysUI.lua) for a minute, a cycle every 10 s (as fast as getting out, walking off and back can go):
-- out of the car with a phone key (the walk-away lock asks 6 times, 2 a second) and a CarKey back from the ignition
-- (keySweep a second later), two key card taps, "Add this car" on the phone, back in. Every request through the
-- server's dispatch (Commands.lua CommandRate, the `default` budget): none dropped.
H.section("keys: a busy minute within the server's budget")
local ticks = {}
local sink = setmetatable({}, { __index = function(t, name) -- KeysUI's events stay out of later tests
    local e = { Add = function(fn) if name == "OnTick" then ticks[fn] = true end end,
        Remove = function(fn) if name == "OnTick" then ticks[fn] = nil end end }
    rawset(t, name, e)
    return e
end })
local realEvents = Events
local stubs = { "TimedActions/ISBaseTimedAction", "TimedActions/ISTimedActionQueue", "TimedActions/ISInventoryTransferAction",
    "TimedActions/ISGrabItemAction", "Vehicles/TimedActions/ISExitVehicle" }
for _, m in ipairs(stubs) do H.stub(m) end
local GLOBALS = { "ISBaseTimedAction", "ISTimedActionQueue", "ISInventoryTransferAction", "ISGrabItemAction", "ISExitVehicle",
    "ISWorldObjectContextMenu", "ISMinidoracatTeslaKeyTap" }
local before = {}
for _, g in ipairs(GLOBALS) do before[g] = _G[g] end
ISBaseTimedAction = { perform = function() end }
function ISBaseTimedAction:derive(name) local c = setmetatable({ Type = name }, { __index = self }); c.__index = c; return c end
function ISBaseTimedAction:new(ch) return setmetatable({ character = ch }, self) end
ISTimedActionQueue = { add = function() end }
ISInventoryTransferAction, ISGrabItemAction = { perform = function() end }, { perform = function() end }
ISExitVehicle = { perform = function(self) self.character.vehicle = nil end }
ISWorldObjectContextMenu = { addToolTip = function() return {} end }
Events = sink
H.side(true, false)
require "MinidoracatTesla/KeysUI"
local UI = T.KeysUI
local car = tesla({ pct = 80 })
local wInv = container(key(K.CARD, car.keyId), key(K.PHONE_KEY, car.keyId), item(K.PHONE))
local walker = player("walker", wInv, car.x - 1, car.y)
function walker:getOnlineID() return 9200 end
function walker:isDead() return false end
function walker:isTimedActionInstant() return false end
local menu = { addOption = function(self, _, target, fn, a1, a2)
    self.last = { target = target, fn = fn, a1 = a1, a2 = a2 }
    return self.last
end }
local dropped0, from, sentN, gotN, times = T.CommandRate.dropped.default or 0, #H.clientSent, {}, {}, {}
for tick = 0, 599 do
    H.side(true, false)
    local s = tick % 100 -- 100 ms ticks, a 10 s cycle
    if s == 0 then
        walker.vehicle = car
        wInv:AddItem(key("Base.CarKey", car.keyId)) -- the spawn-time key, back from the ignition
        ISExitVehicle.perform(setmetatable({ character = walker }, { __index = ISExitVehicle }))
        walker.x = car.x - (K.LOCK_DIST + 2)
    elseif s == 40 or s == 50 then
        walker.x = car.x - 1
        ISMinidoracatTeslaKeyTap:new(walker, car):perform()
    elseif s == 70 then
        walker.vehicle = car
        UI.phoneOption(walker, menu, wInv.items[3])
        menu.last.fn(menu.last.target, menu.last.a1, menu.last.a2)
    end
    for fn in pairs(ticks) do fn() end
    for i = from + 1, #H.clientSent do
        local c = H.clientSent[i].command
        sentN[c] = (sentN[c] or 0) + 1
        times[#times + 1] = tick * 100 -- all four share `default`
    end
    local got
    got, from = H.serve(from)
    for c, n in pairs(got) do gotN[c] = (gotN[c] or 0) + n end
    H.advanceMs(100)
end
Events = realEvents
H.side(false, true)
for _, g in ipairs(GLOBALS) do _G[g] = before[g] end
local same, line = true, {}
for c, n in pairs(sentN) do
    if gotN[c] ~= n then same = false end
    line[#line + 1] = c .. " " .. n
end
table.sort(line)
local busiest = H.busiest(times, T.CommandRate.LIMITS.default.ms)
check(same and sentN.autoLock == 36 and sentN.keySweep == 6 and sentN.keyTap == 12 and sentN.phonePair == 6
    and (T.CommandRate.dropped.default or 0) == dropped0 and busiest * 1.5 <= T.CommandRate.LIMITS.default.max,
    "every request reached its handler (" .. busiest .. " in the busiest 10 s): " .. table.concat(line, ", "))

for k, n in pairs(statsBefore) do S.stats[k] = n end -- test_sentry counts flashes from zero
instanceItem, playServerSound, sendAddItemToContainer, sendRemoveItemFromContainer, ProceduralDistributions, getItemNameFromFullType = nil, nil, nil, nil, nil, nil
ISStartVehicleEngine = nil
for _, n in ipairs(ACTIONS) do _G[n].complete = plain[n] end
F.done()
