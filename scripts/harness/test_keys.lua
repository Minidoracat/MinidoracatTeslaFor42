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
    local d = p.d
    p.doorObj = {
        isLocked = function() return d.locked end, setLocked = function(_, b) d.locked = b end,
        isOpen = function() return d.open end, isLockBroken = function() return d.broken end,
    }
    return p
end
local function tesla(o)
    local v = F.track(F.vehicle(o))
    v.doors = { door("DoorFrontLeft"), door("DoorFrontRight"), door("DoorRearLeft"), door("DoorRearRight") }
    v.doors[1].area = "SeatFrontLeft"
    v.trunk = door("TrunkDoor")
    v.doorTx = 0
    local all = {}
    for _, p in pairs(v.parts) do all[#all + 1] = p end
    for _, d in ipairs(v.doors) do all[#all + 1] = d end
    all[#all + 1] = v.trunk
    function v:getPassengerDoor(seat) return self.doors[seat + 1] end
    function v:getMaxPassengers() return 4 end
    function v:getPartCount() return #all end
    function v:getPartByIndex(i) local p = all[i + 1]; p.getDoor = p.getDoor or function() return nil end; return p end
    function v:areAllDoorsLocked()
        for _, d in ipairs(self.doors) do if not d.d.locked then return false end end
        return true
    end
    function v:setTrunkLocked(b) self.trunk.d.locked = b end
    function v:transmitPartDoor() self.doorTx = self.doorTx + 1 end
    function v:getAreaCenter(area)
        if area ~= "SeatFrontLeft" then return nil end
        return { getX = function() return self.x - 1 end, getY = function() return self.y end }
    end
    function v:getCurrentKey() return self.ignitionKey end
    function v:getSquare() return {} end
    return v
end

local function player(name, inv, x, y)
    local p = { name = name, inv = inv, x = x, y = y }
    function p:getUsername() return self.name end
    function p:getVehicle() return self.vehicle end
    function p:getInventory() return self.inv end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:DistTo(v) local dx, dy = self.x - v:getX(), self.y - v:getY(); return math.sqrt(dx * dx + dy * dy) end
    return p
end

require "MinidoracatTesla/Keys"
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
local reg = ModData.getOrCreate(K.REG)
check(reg[tostring(v.keyId)] == "MinidoracatTesla_ModelY", "registry: a loaded Tesla's keyId is recorded with its model name")
check(reg[tostring(other.keyId)] == nil, "registry: other cars are not recorded")

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
cmds.keyTap(owner, { vid = v:getId() })
local lockedAll = v.doors[1].d.locked and v.doors[2].d.locked and v.doors[4].d.locked and v.trunk.d.locked
check(lockedAll and not v.doors[3].d.locked, "keyTap: locks every door and the trunk, skips a broken lock")
check(S.stats.flashes == flashes0 + 1 and sounds[#sounds] == K.SOUND, "keyTap: flash + beep (playServerSound on the server)")
v.headlights = false
v.toggles = 0
F.runTicks(50, 450)
check(v.toggles == 2 and v.headlights == false and F.handlers("OnTick") == 0, "keyTap lock: one flash (2 toggles), lights restored, OnTick removed")
v.doors[3].d.broken = false
v.doors[3].d.locked = true
v.parts.GasTank:getModData().sentry = { by = "owner", at = F.hours, kwh = 50, since = F.hours }
cmds.keyTap(owner, { vid = v:getId() })
check(not v.doors[1].d.locked and not v.trunk.d.locked, "keyTap again: unlocks")
v.toggles = 0
F.runTicks(50, 450)
check(v.toggles == 4, "keyTap unlock: two flashes (4 toggles)")
check(v.parts.GasTank:getModData().sentry == nil, "keyTap unlock: the owner's card disarms sentry")

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
check(select(2, autoLockReason()) == "AUTOLOCK_CAMP", "auto-lock: camp on -> AUTOLOCK_CAMP")
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
cmds.autoLock(owner, { vid = v:getId() })
local skip = F.lastSent("autoLockSkip")
check(skip and skip.args.reason == "AUTOLOCK_CAMP" and F.lastSent("deny") == nil and not v:areAllDoorsLocked(),
    "autoLock command, camp on: autoLockSkip with the reason (client says it, stops asking), nothing locked")
v.parts.GasTank:getModData().camp = nil
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

-- ------------------------------------------------------------------ phone loot
ProceduralDistributions = { list = { ElectronicStorePhones = { items = { "CordlessPhone", 50 } } } }
F.fire("OnPostDistributionMerge")
F.fire("OnPostDistributionMerge")
local items = ProceduralDistributions.list.ElectronicStorePhones.items
check(#items == 4 and items[3] == K.PHONE and items[4] == K.LOOT.ElectronicStorePhones, "loot: phone added once even when the merge runs twice")

for k, n in pairs(statsBefore) do S.stats[k] = n end -- test_sentry counts flashes from zero
instanceItem, playServerSound, sendAddItemToContainer, sendRemoveItemFromContainer, ProceduralDistributions, getItemNameFromFullType = nil, nil, nil, nil, nil, nil
F.done()
