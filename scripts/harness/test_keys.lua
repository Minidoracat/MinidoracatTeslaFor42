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
    function it:getDisplayName() return self.name or self.ft end -- unnamed on a dedicated server: the full type (tesla-keys-1026e)
    function it:setName(n) self.name = n end
    function it:isCustomName() return self.custom == true end
    function it:getContainer() return self.cont end
    function it:hasModData() return self.md ~= nil end
    function it:getModData() self.md = self.md or {}; return self.md end
    function it:hasTag() return false end
    function it:getInventory() return self.inv end
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
    function c:getItemWithID(id) for _, it in ipairs(self.items) do if it.id == id then return it end end end
    function c:getItems() return jlist(self.items) end
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

ItemTag = ItemTag or { KEY_RING = "KeyRing" }
local sentPackets = { add = 0, remove = 0 }
getItemNameFromFullType = function(ft) return "ItemName_" .. ft end
instanceItem = function(ft) return key(ft) end
sendAddItemToContainer = function() sentPackets.add = sentPackets.add + 1 end
sendRemoveItemFromContainer = function(c, it) sentPackets.remove = sentPackets.remove + 1; sentPackets.lastRemove = { c, it } end
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
    function v:isEngineStarted() return self.starting == true end -- Starting..StartingSuccess (VehicleEngine.java:365-370)
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
    function p:DistTo(v) return math.abs(self.x - v:getX()) + math.abs(self.y - v:getY()) end -- the engine's: Manhattan (IsoMovingObject.java:605-607)
    return p
end

H.stub("Vehicles/TimedActions/ISUnlockVehicleDoor") -- park_fakes made the class; Keys.lua wraps start() and complete()
ISUnlockVehicleDoor.start = ISUnlockVehicleDoor.start or function() return true end
local unlockBefore = { start = ISUnlockVehicleDoor.start, complete = ISUnlockVehicleDoor.complete } -- restored at the end
-- vanilla ISStartVehicleEngine:complete (ISStartVehicleEngine.lua:26-44): haveKey from haveThisKeyId only
H.stub("Vehicles/TimedActions/ISStartVehicleEngine")
ISStartVehicleEngine = { waitToStart = function() return false end, complete = function(self) -- (ISBaseTimedAction's)
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

local served = {} -- items the server made, named by the client further down (KeysUI UI.nameOf)
local teslaKey, plainKey = key("Base.CarKey", v.keyId), key("Base.CarKey", other.keyId)
local wallet = bag("Base.Wallet", teslaKey)
local ownerInv = container(wallet, plainKey)
local owner = player("owner", ownerInv, v.x - 1, v.y)
-- seated, driving: the inventory's key swaps, except this car's while its motor starts with the ignition empty (the
-- client moves its own copy in when the Starting state arrives, KeyActions K.sweep)
owner.vehicle, v.driver, v.starting = v, owner, true
cmds.keySweep(owner, {})
check(teslaKey.cont == wallet.inv, "sweep: the driver's key waits while the motor starts with the ignition empty")
v.starting = false
cmds.keySweep(owner, {})
local card = wallet.inv.items[1]
check(card and card.ft == K.CARD and card.keyId == v.keyId, "sweep: seated, motor off: the Tesla key became a key card with the same keyId")
check(card and card.cont == wallet.inv and teslaKey.cont == nil, "sweep: swapped in place (still in the wallet)")
check(card and card.name == nil and card.md[K.PAIRED_CARS][1] == "MinidoracatTesla_ModelY",
    "sweep: left unnamed (the client names it in its language), the car model in teslaCars")
served.card = card
check(plainKey.cont == ownerInv and plainKey.ft == "Base.CarKey", "sweep: other cars' keys untouched")
check(sentPackets.add == 1 and sentPackets.remove == 1, "sweep: one remove and one add packet")
cmds.keySweep(owner, {})
check(sentPackets.add == 1, "sweep: nothing left to swap the second time")
owner.vehicle, v.driver = nil, nil
-- what the wait leaves alone: another Tesla's key, and this car's once its key cannot go in
do
    local v2 = tesla({ pct = 50 })
    F.fire("OnSpawnVehicleEnd", v2)
    local theirs = key("Base.CarKey", v2.keyId)
    local inv = container(theirs)
    local p = player("driver2", inv, v.x, v.y)
    p.vehicle, v.driver, v.starting = v, p, true
    local mine = inv:AddItem(key("Base.CarKey", v.keyId))
    cmds.keySweep(p, {})
    check(mine.cont == inv and theirs.cont == nil, "sweep wait: only this car's key waits, another Tesla's becomes a card")
    inv:Remove(mine)
    local cases = {
        { "the ignition already holds a key", function() v.ignition = true end },
        { "a hotwired car (no key goes in)", function() v.hotwired = true end },
        { "a passenger", function() v.driver = nil end },
        { "the motor running", function() v.starting, v.running = false, true end },
    }
    for _, c in ipairs(cases) do
        v.driver, v.starting, v.ignition, v.hotwired, v.running = p, true, false, false, false
        c[2]()
        local k = inv:AddItem(key("Base.CarKey", v.keyId))
        cmds.keySweep(p, {})
        check(k.cont == nil, "sweep wait: " .. c[1] .. " -> swapped")
    end
    v.driver, v.starting, v.ignition, v.hotwired, v.running = nil, false, false, false, false
end

-- vanilla "vehicle" commands, looked at a tick later (after vanilla's own handler)
do
    local inv = container()
    local p = player("admin", inv, v.x, v.y)
    inv:AddItem(key("Base.CarKey", v.keyId)) -- what vanilla getKey adds (VehicleCommands.lua:317-327)
    H.fire("OnClientCommand", "vehicle", "getKey", p, { vehicle = v:getId() })
    H.fire("OnTick")
    check(inv.items[1].ft == "Base.CarKey", "admin Get Key without the cheat right: no sweep (vanilla gave nothing)")
    p._admin = true
    H.fire("OnClientCommand", "vehicle", "getKey", p, { vehicle = v:getId() })
    check(inv.items[1].ft == "Base.CarKey", "admin Get Key: nothing inside vanilla's dispatch")
    H.fire("OnTick")
    check(inv.items[1].ft == K.CARD, "admin Get Key: swapped a tick later (no client action asks)")
    -- ghost guard: the client's start beat the swap; vanilla putKeyInIgnition took the first key with the keyId out
    -- of the inventory (haveThisKeyId: loose keys, then key rings) and put the client's old CarKey in
    -- (BaseVehicle.java:8726-8727); the client still holds the key vanilla took
    local function vanillaPut(sender, old)
        local taken = sender:getInventory():haveThisKeyId(old.keyId)
        taken.cont:Remove(taken)
        H.fire("OnClientCommand", "vehicle", "putKeyInIgnition", sender, { key = old, container = -1 })
        H.fire("OnTick")
        return taken
    end
    local getKeyCard = inv.items[1]
    inv:Remove(getKeyCard) -- (one key of the car first: vanilla takes our new card)
    local old = inv:AddItem(key("Base.CarKey", v.keyId))
    old._class = "Key"
    cmds.keySweep(p, {})
    local card = inv.items[#inv.items]
    local removes, ghosts = sentPackets.remove, K.stats.ghosts
    local other = player("other", container(), v.x, v.y)
    H.fire("OnClientCommand", "vehicle", "putKeyInIgnition", other, { key = old, container = -1 })
    H.fire("OnTick")
    check(sentPackets.remove == removes, "ghost guard: another player naming my old key's id -> nothing")
    local taken = vanillaPut(p, old)
    local last = sentPackets.lastRemove
    check(taken == card and sentPackets.remove == removes + 1 and K.stats.ghosts == ghosts + 1 and last[1] == inv
        and last[2] == card, "ghost guard: the card vanilla took out is removed on the client too (that card, its container)")
    H.fire("OnClientCommand", "vehicle", "putKeyInIgnition", p, { key = old, container = -1 })
    H.fire("OnTick")
    check(sentPackets.remove == removes + 1, "ghost guard: once per swap")
    -- two keys of the car (order: card, CarKey): the new card goes last, vanilla takes the other one
    inv:AddItem(getKeyCard)
    local old2 = inv:AddItem(key("Base.CarKey", v.keyId))
    old2._class = "Key"
    cmds.keySweep(p, {})
    local card2 = inv.items[#inv.items]
    removes = sentPackets.remove
    taken = vanillaPut(p, old2)
    last = sentPackets.lastRemove
    check(taken == getKeyCard and sentPackets.remove == removes + 1 and last[2] == getKeyCard and card2.cont == inv,
        "ghost guard: vanilla took the car's other card -> that one is removed on the client, the new card stays")
    -- in a key ring: vanilla takes it from the ring, the remove names the ring
    inv:Remove(card2)
    local ring = bag("Base.KeyRing", key("Base.CarKey", v.keyId))
    local old3 = ring.inv.items[1]
    old3._class = "Key"
    inv:AddItem(ring)
    cmds.keySweep(p, {})
    local card3 = ring.inv.items[1]
    removes = sentPackets.remove
    taken = vanillaPut(p, old3)
    last = sentPackets.lastRemove
    check(taken == card3 and sentPackets.remove == removes + 1 and last[1] == ring.inv and last[2] == card3,
        "ghost guard: a card in a key ring -> removed from that ring on the client")
    -- any Key with the keyId (a vanilla Base.Key1 here), first in the order: vanilla takes it
    ring.inv:Remove(card3)
    inv:Remove(ring)
    local house = key("Base.Key1", v.keyId)
    inv:AddItem(house)
    local old4 = inv:AddItem(key("Base.CarKey", v.keyId))
    old4._class = "Key"
    cmds.keySweep(p, {})
    removes = sentPackets.remove
    taken = vanillaPut(p, old4)
    last = sentPackets.lastRemove
    check(taken == house and sentPackets.remove == removes + 1 and last[2] == house,
        "ghost guard: vanilla took another Key type with the keyId -> removed on the client too")
    local plain = key("Base.CarKey", v.keyId)
    plain._class = "Key"
    removes = sentPackets.remove
    H.fire("OnClientCommand", "vehicle", "putKeyInIgnition", p, { key = plain, container = -1 })
    H.fire("OnTick")
    check(sentPackets.remove == removes, "ghost guard: a key we never swapped -> nothing")
end

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
-- the owner's split-screen guest beside it: the same client (online id slot * 4 + 1), which plays a chirp per packet
local guest = player("guest", container(), v.x - 1, v.y + 1, 1)
guest.oid = owner.oid + 1
F.online = { owner, guest, farAway }
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
    and #sounds == beeps0, "keyTap lock: flash + horn chirp once per client within CHIRP_TILES (not again for the "
    .. "split-screen guest on the owner's client), no playServerSound")
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

-- VehicleManager present: the tap also needs its PASSENGER right, like the app's lock / unlock (Remote.lua VM_CODES):
-- a card picked up off the floor does not open a car claimed by someone else, nor disarm its sentry
local asked = {}
MinidoracatVehicleManagerAPI = { canUse = function(p, _, code, ctx)
    asked[#asked + 1] = code .. "/" .. tostring(ctx and ctx.mod)
    if p == owner and code == "PASSENGER" then return true, "OWNER" end
    return false, "NOT_SHARED"
end }
cmds.keyTap(owner, { vid = v:getId() }) -- lock it again, the owner's right
check(v.doors[1].d.locked and asked[1] == "PASSENGER/" .. T.MODULE, "VehicleManager: the owner's tap asks PASSENGER and locks")
v.parts.GasTank:getModData().sentry = { by = "owner", at = F.hours, kwh = 50, since = F.hours }
local finder = player("finder", container(item(K.CARD, v.keyId)), v.x - 1, v.y)
local f0 = S.stats.flashes
F.sent = {}
cmds.keyTap(finder, { vid = v:getId() })
check(lastDeny() == "NOT_OWNER" and v.doors[1].d.locked and v.trunk.d.locked and v.frunk.d.locked
    and S.stats.flashes == f0 and v.parts.GasTank:getModData().sentry ~= nil,
    "VehicleManager: a found card on a car claimed by someone else -> NOT_OWNER, still locked, no flash, sentry kept")
MinidoracatVehicleManagerAPI.canUse = function() return false, "RENT_LOCKED" end
cmds.keyTap(finder, { vid = v:getId() })
check(lastDeny() == "RENT_LOCKED" and v.doors[1].d.locked, "VehicleManager: its own reason (rent locked) passes through")
MinidoracatVehicleManagerAPI.canUse = function() return true, "UNCLAIMED" end
cmds.keyTap(finder, { vid = v:getId() })
check(not v.doors[1].d.locked, "VehicleManager: an unclaimed car -> the card is enough, as without VehicleManager")
MinidoracatVehicleManagerAPI = nil
v.parts.GasTank:getModData().sentry = nil
F.runTicks(50, 450)

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
check(not ok and why == "NO_KEY_CARD_HOTWIRE", "pair: seated without the card, no VehicleManager -> NO_KEY_CARD_HOTWIRE (says hotwiring works)")
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
check(lastDeny() == "NO_KEY_CARD_HOTWIRE" and noCard.inv.items[1].ft == K.PHONE, "phonePair raw command without the card: denied, phone unchanged")
-- Lost card (user 2026-10-28): VehicleManager's owner of this car (MANAGE, never shareable) pairs without it. Fake VM:
-- the owner gets every code (VM O.allowsRecord "OWNER"), a DRIVE share gets DRIVE/PASSENGER only.
local vmOwner = player("vmowner", container(item(K.PHONE)), v.x, v.y)
local vmDriver = player("vmdriver", container(item(K.PHONE)), v.x, v.y)
vmOwner.vehicle, vmDriver.vehicle = v, v
local vmAsked = {}
local function fakeVM(adminFor)
    return { canUse = function(p, car, code, ctx)
        vmAsked[#vmAsked + 1] = { code = code, mod = ctx and ctx.mod, silent = ctx and ctx.silent }
        if car ~= v then return false, "NOT_AUTHORIZED" end
        if p == vmOwner then return true, "OWNER" end
        if p == vmDriver and (code == "DRIVE" or code == "PASSENGER") then return true, "MEMBER" end
        if p == adminFor then return true, "ADMIN" end
        return false, "NOT_AUTHORIZED"
    end }
end
MinidoracatVehicleManagerAPI = fakeVM()
ok, why = K.canPair(vmOwner, v, vmOwner.inv.items[1])
check(ok == true and why == "VM", "pair: VehicleManager owner without the card -> allowed (tooltip says why)")
check(vmAsked[#vmAsked].code == "MANAGE" and vmAsked[#vmAsked].mod == T.MODULE and vmAsked[#vmAsked].silent == nil,
    "pair: asks VehicleManager MANAGE, as Tesla, not silent (an admin's override is audited)")
local asked0 = #vmAsked
check(K.canPair(owner, v, item(K.PHONE)) == true and #vmAsked == asked0, "pair: the card on you -> VehicleManager not asked")
ok, why = K.canPair(vmDriver, v, vmDriver.inv.items[1])
check(not ok and why == "NO_KEY_CARD", "pair: a DRIVE share without the card -> NO_KEY_CARD")
ok, why = K.canPair(noCard, v, noCard.inv.items[1])
check(not ok and why == "NO_KEY_CARD", "pair: VehicleManager says no -> NO_KEY_CARD")
MinidoracatVehicleManagerAPI = fakeVM(noCard)
ok, why = K.canPair(noCard, v, noCard.inv.items[1])
check(ok == true and why == "VM", "pair: an admin with VehicleManager's override on -> allowed (VM audits it)")
MinidoracatVehicleManagerAPI = { canUse = function() return true, "UNCLAIMED" end }
ok, why = K.canPair(noCard, v, noCard.inv.items[1])
check(not ok and why == "NO_KEY_CARD", "pair: an unclaimed car is nobody's -> NO_KEY_CARD")
MinidoracatVehicleManagerAPI = fakeVM()
SandboxVars.MinidoracatVehicleManager = { VirtualKey = false } -- the server wants vanilla key rules
ok, why = K.canPair(vmOwner, v, vmOwner.inv.items[1])
check(not ok and why == "NO_KEY_CARD", "pair: VehicleManager VirtualKey off -> the owner needs the card too")
SandboxVars.MinidoracatVehicleManager = nil
F.sent = {}
cmds.phonePair(vmDriver, { vid = v:getId(), id = vmDriver.inv.items[1]:getID() })
check(lastDeny() == "NO_KEY_CARD" and vmDriver.inv.items[1].ft == K.PHONE, "phonePair: a DRIVE share without the card -> denied")
F.sent = {}
cmds.phonePair(vmOwner, { vid = v:getId(), id = vmOwner.inv.items[1]:getID() })
local ownerPk = vmOwner.inv.items[#vmOwner.inv.items]
check(ownerPk.ft == K.PHONE_KEY and ownerPk.keyId == v.keyId and F.lastSent("phonePaired") ~= nil,
    "phonePair: the VehicleManager owner without the card -> a phone key for this car")
MinidoracatVehicleManagerAPI = nil
ok, why = K.canPair(vmOwner, v, item(K.PHONE))
check(not ok and why == "NO_KEY_CARD_HOTWIRE", "pair: no VehicleManager, not hotwired -> the card")
SandboxVars.VehicleEasyUse = true -- T.authorized says yes to everyone then; vmGrants must still need VehicleManager
ok, why = K.canPair(vmOwner, v, item(K.PHONE))
check(not ok and why == "NO_KEY_CARD_HOTWIRE", "pair: no VehicleManager, VehicleEasyUse on -> still the card")
SandboxVars.VehicleEasyUse = nil
-- hotwired (user 2026-10-28, decisions.md keyless rules): without VehicleManager, seated in a hotwired car pairs
v.hotwired = true
ok, why = K.canPair(noCard, v, noCard.inv.items[1])
check(ok == true and why == "HOTWIRED", "pair: no VehicleManager, seated in a hotwired car -> allowed (HOTWIRED, tooltip says why)")
MinidoracatVehicleManagerAPI = fakeVM()
ok, why = K.canPair(noCard, v, noCard.inv.items[1])
check(not ok and why == "NO_KEY_CARD", "pair: VehicleManager installed, hotwired car -> still the card or its MANAGE")
MinidoracatVehicleManagerAPI = nil
F.sent = {}
cmds.phonePair(noCard, { vid = v:getId(), id = noCard.inv.items[1]:getID() })
local hotPk = noCard.inv.items[#noCard.inv.items]
check(hotPk.ft == K.PHONE_KEY and hotPk.keyId == v.keyId and F.lastSent("phonePaired") ~= nil,
    "phonePair in a hotwired car without the card -> a phone key for it")
v.hotwired = nil

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

-- ------------------------------------------------------------------ starting with the phone key or key card in a bag
local starts = {}
function v:tryStartEngine(haveKey) starts[#starts + 1] = haveKey end
function v:isDriver(p) return p.vehicle == self end
function v:isHotwired() return self.hotwired == true end
local function start(p) starts = {}; ISStartVehicleEngine.complete({ character = p }); return starts[1] end
local otherCard = player("othercard", container(bag("Base.Wallet", item(K.CARD, v.keyId + 1))), v.x, v.y)
-- each start with one key only (the owner carries both: the card in the wallet would hide a broken phone-key branch)
local phoneOnly = player("phoneonly", container(bag("Base.Bag_Schoolbag", key(K.PHONE_KEY, v.keyId))), v.x, v.y)
walletOnly.vehicle, stranger.vehicle, otherCard.vehicle, phoneOnly.vehicle = v, v, v, v
check(start(phoneOnly) == true, "start: phone key in a bag (no card) -> tryStartEngine(true) (vanilla would pass false)")
check(start(walletOnly) == true, "start: key card in the wallet -> tryStartEngine(true) (vanilla would pass false)")
check(start(stranger) == false, "start: no key -> vanilla haveKey false")
check(start(otherCard) == false, "start: another car's key card in the wallet -> vanilla haveKey false")
local cardLoose = player("cardloose", container(key(K.CARD, v.keyId)), v.x, v.y)
cardLoose.vehicle = v
check(start(cardLoose) == true and K.bagKeyStarts(cardLoose, v) == false, "start: loose key card -> vanilla path (goes into the ignition)")
v.hotwired = true
check(K.bagKeyStarts(phoneOnly, v) == false and K.bagKeyStarts(walletOnly, v) == false, "start: hotwired -> vanilla path")
v.hotwired, walletOnly.vehicle, stranger.vehicle, otherCard.vehicle, phoneOnly.vehicle = nil, nil, nil, nil, nil

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
check(ph.name == nil and ph.md[K.PAIRED_CARS][1] == "MinidoracatTesla_ModelY", "one car: unnamed, its model in the mirror")
served.one = ph
multi.vehicle = carB
check(K.canPair(multi, carB, ph) == true, "a phone key for A, seated in B with B's card: may add B")
local oldId = ph.id
F.sent = {}
cmds.phonePair(multi, { vid = carB:getId(), id = ph.id })
ph = phoneOf(mInv)
local rec = phones[tostring(ph.id)]
check(ph.keyId == carB.keyId and rec and rec[1] == carA.keyId and rec[2] == carB.keyId and phones[tostring(oldId)] == nil,
    "add B: the item's keyId = B (paired last), the server record { A, B } follows the new item id")
check(ph.name == nil and #ph.md[K.PAIRED_CARS] == 2, "two cars: unnamed, both models in the mirror")
served.two = ph
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
check(carB.startArg == false and not K.bagKeyStarts(onlyA, carB), "a phone key for A only: B does not start")
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
check(ph.keyId == carA.keyId and r2 and #r2 == 1 and ph.name == nil and ph.md[K.PAIRED_CARS][1] == "MinidoracatTesla_ModelY"
    and F.lastSent("phoneUnpaired").args.n == 1, "remove B (the item's keyId): keyId back to A, record { A }, A's model again")
served.back = ph
check(K.phoneKey(multi, carB) == nil, "removed: B no longer opens")
multi.vehicle = carB
cmds.phonePair(multi, { vid = carB:getId(), id = ph.id })
check(lastDeny() == "NO_KEY_CARD_HOTWIRE" and phoneOf(mInv).keyId == carA.keyId, "adding B again needs B's card: NO_KEY_CARD_HOTWIRE, still one car")
multi.vehicle = nil -- (removing is done outside a car)
cmds.phoneUnpair(multi, { id = ph.id, key = carA.keyId })
local plainPhone = mInv.items[#mInv.items]
check(phoneOf(mInv) == nil and plainPhone.ft == K.PHONE and plainPhone.keyId == -1 and not plainPhone.md
    and plainPhone.name == nil, "remove the last car: a plain phone again (no keyId, no mirror, unnamed)")
served.plain = plainPhone
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
-- a Model 3 joins a phone whose car B dropped out of the keyId registry (a store from before it): every car keeps its
-- own model or none, never the Model Y's (KeyActions carsOf; the menus and the halo name an unknown one "Tesla")
local carC = tesla({ pct = 50, script = "Base.MinidoracatTesla_Model3" })
carC.x, carC.y = carB.x, carB.y
local reg = T.Store.get("keyIds")
reg[tostring(carB.keyId)] = nil
mInv:AddItem(key(K.CARD, carC.keyId))
multi.vehicle = carC
cmds.phonePair(multi, { vid = carC:getId(), id = ph.id })
ph = phoneOf(mInv)
local cars = ph.md[K.PAIRED_CARS]
check(reg[tostring(carC.keyId)] == "MinidoracatTesla_Model3" and cars[1] == nil and cars[2] == "MinidoracatTesla_Model3",
    "Model 3 added: registered on pairing, its model in the mirror; the unregistered car stays nil, not the Model Y")
multi.vehicle = nil
F.sent = {}
cmds.phoneUnpair(multi, { id = ph.id, key = carB.keyId })
ph = phoneOf(mInv)
check(F.lastSent("phoneUnpaired").args.car == nil and ph.name == nil and #ph.md[K.PAIRED_CARS] == 1
    and ph.md[K.PAIRED_CARS][1] == "MinidoracatTesla_Model3",
    "removing the unregistered car: told with no model (client says 'Tesla'); the Model 3 left is the mirror's one car")
served.m3 = ph
reg[tostring(carB.keyId)] = "MinidoracatTesla_ModelY"
cmds.phoneUnpair(multi, { id = ph.id, key = carC.keyId })
ph = mInv.items[#mInv.items]
check(ph.ft == K.PHONE, "remove the Model 3: a plain phone again")

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
local ticks, hooks = {}, {}
local sink = setmetatable({}, { __index = function(t, name) -- KeysUI's events stay out of later tests
    local e = { Add = function(fn)
            if name == "OnTick" then ticks[fn] = true else hooks[name] = hooks[name] or {}; table.insert(hooks[name], fn) end
        end,
        Remove = function(fn) if name == "OnTick" then ticks[fn] = nil end end }
    rawset(t, name, e)
    return e
end })
local realEvents = Events
local stubs = { "TimedActions/ISBaseTimedAction", "TimedActions/ISTimedActionQueue", "TimedActions/ISInventoryTransferAction",
    "TimedActions/ISGrabItemAction", "Vehicles/TimedActions/ISExitVehicle", "ISUI/ISInventoryPane" }
for _, m in ipairs(stubs) do H.stub(m) end
local GLOBALS = { "ISBaseTimedAction", "ISTimedActionQueue", "ISInventoryTransferAction", "ISGrabItemAction", "ISExitVehicle",
    "ISWorldObjectContextMenu", "ISMinidoracatTeslaKeyTap", "ISInventoryPane", "getSpecificPlayer" }
local before = {}
for _, g in ipairs(GLOBALS) do before[g] = _G[g] end
ISBaseTimedAction = { perform = function() end }
function ISBaseTimedAction:derive(name) local c = setmetatable({ Type = name }, { __index = self }); c.__index = c; return c end
function ISBaseTimedAction:new(ch) return setmetatable({ character = ch }, self) end
ISTimedActionQueue = { add = function() end }
ISInventoryTransferAction = { perform = function() end }
ISGrabItemAction = { start = function() end, perform = function(self) table.remove(self.queueList, 1) end }
ISExitVehicle = { perform = function(self) self.character.vehicle = nil end }
ISWorldObjectContextMenu = { addToolTip = function() return {} end }
ISInventoryPane = { refreshContainer = function(self) self.refreshed = (self.refreshed or 0) + 1 end } -- vanilla lists
local function pane(inv, onCharacter) -- an inventory window's list: the player's own, or loot (floor, glove box)
    return setmetatable({ inventory = inv, player = 0, parent = { onCharacter = onCharacter } }, { __index = ISInventoryPane })
end
Events = sink
H.side(true, false)
require "MinidoracatTesla/KeysUI"
local UI = T.KeysUI
do -- the pairing menu tells a VehicleManager owner without the card why it is allowed (KeysUI.phoneOption)
    local tipMenu = { addOption = function() return {} end }
    local lost = player("lostcard", container(item(K.PHONE)), v.x, v.y)
    lost.vehicle = v
    MinidoracatVehicleManagerAPI = { canUse = function(p) return p == lost, p == lost and "OWNER" or "NOT_AUTHORIZED" end }
    local opt = UI.phoneOption(lost, tipMenu, lost.inv.items[1])
    check(not opt.notAvailable and opt.toolTip.description == "Tooltip_MinidoracatTesla_PairPhoneOwner",
        "pair menu: VehicleManager owner without the card -> enabled, owner tooltip")
    lost.inv:AddItem(item(K.CARD, v.keyId))
    opt = UI.phoneOption(lost, tipMenu, lost.inv.items[1])
    check(not opt.notAvailable and opt.toolTip.description == "Tooltip_MinidoracatTesla_PairPhone",
        "pair menu: the same owner with the card -> the card tooltip")
    lost.vehicle = nil
    MinidoracatVehicleManagerAPI = nil
end

-- Names in the player's language (KeysUI UI.nameOf / nameAll): the server leaves these items unnamed (KeyActions
-- replace); the client adds the car from teslaCars, reads it back from a name fixed in the server's language before,
-- and keeps a name the player gave.
H.section("keys: item names in the player's language (client)")
do
    local realGT, realGTN, realName, realCli = getText, getTextOrNull, getItemName, isClient
    isClient = function() return true end -- an MP client: phone keys read the modData mirror (Keys.lua extraIds)
    local function speak(items, cars, many) -- this client's language
        getItemName = function(ft) return items[ft] or ft end
        getTextOrNull = function(k) return cars[k] end
        getText = function(k, a) if k == "IGUI_MinidoracatTesla_PhoneCars" then return many(a) end return cars[k] or k end
    end
    speak({ [K.CARD] = "卡片鑰匙", [K.PHONE] = "智慧型手機", [K.PHONE_KEY] = "手機鑰匙" },
        { IGUI_VehicleNameMinidoracatTesla_ModelY = "特斯拉 Model Y", IGUI_VehicleNameMinidoracatTesla_Model3 = "特斯拉 Model 3" },
        function(n) return n .. " 台特斯拉" end)
    check(UI.nameOf(served.card) == "卡片鑰匙 - 特斯拉 Model Y", "name: the swapped key card, in the client's language")
    check(UI.nameOf(served.one) == "手機鑰匙 - 特斯拉 Model Y", "name: a phone key for one car")
    check(UI.nameOf(served.two) == "手機鑰匙 - 2 台特斯拉", "name: a phone key for two cars")
    check(UI.nameOf(served.back) == "手機鑰匙 - 特斯拉 Model Y", "name: back to one car after removing the other")
    check(UI.nameOf(served.m3) == "手機鑰匙 - 特斯拉 Model 3", "name: the Model 3 left on the phone")
    check(UI.nameOf(served.plain) == "智慧型手機", "name: unpaired, a plain smartphone")
    local function fixed(ft, name) local it = key(ft); it.name = name; return it end -- named by the server before
    local oldCard, oldM3 = fixed(K.CARD, "Key Card - Tesla Model Y"), fixed(K.CARD, "Key Card - Tesla Model3")
    local oldPk, oldPhone = fixed(K.PHONE_KEY, "Phone Key - Tesla ModelY"), fixed(K.PHONE, "Smartphone")
    local custom = fixed(K.CARD, "Bob's car")
    custom.custom = true -- vanilla rename (ISInventoryPaneContextMenu: setName + setCustomName(true))
    local bogus = key(K.CARD)
    bogus.md = { [K.PAIRED_CARS] = { "Bogus" } } -- a mirror the client rewrote: no such car
    local carKey = key("Base.CarKey", 77)
    carKey.name = "Vehicle Key - Dash Elite"
    local inv = container(oldCard, bag("Base.Bag_Schoolbag", oldPk, oldPhone), oldM3, custom, bogus, carKey)
    UI.nameAll(inv)
    check(oldCard.name == "卡片鑰匙 - 特斯拉 Model Y" and oldM3.name == "卡片鑰匙 - 特斯拉 Model 3",
        "old names fixed in the server's language: the model read back ('Model Y', 'Model3')")
    check(oldPk.name == "手機鑰匙 - 特斯拉 Model Y" and oldPhone.name == "智慧型手機",
        "old names inside a bag: the phone key, and the unpaired 'Smartphone' too")
    check(custom.name == "Bob's car", "a name the player gave stays")
    check(bogus.name == "卡片鑰匙", "an unknown model in the mirror: the plain item name, never a raw key")
    check(carKey.name == "Vehicle Key - Dash Elite", "other items untouched (vanilla CarKey)")
    local n = UI.stats.names
    UI.nameAll(inv)
    check(UI.stats.names == n, "a second pass renames nothing")
    local loot = pane(container(fixed(K.CARD, "Key Card - Tesla Model Y")), false)
    loot:refreshContainer()
    check(loot.inventory.items[1].name == "卡片鑰匙 - 特斯拉 Model Y" and loot.refreshed == 1,
        "a loot list refresh (floor, glove box) names what it lists, then vanilla's refresh runs")
    speak({ [K.CARD] = "Key Card", [K.PHONE] = "Smartphone", [K.PHONE_KEY] = "Phone Key" },
        { IGUI_VehicleNameMinidoracatTesla_ModelY = "Tesla Model Y", IGUI_VehicleNameMinidoracatTesla_Model3 = "Tesla Model 3" },
        function(n) return n .. " Teslas" end)
    UI.nameAll(inv)
    check(UI.nameOf(served.two) == "Phone Key - 2 Teslas" and oldCard.name == "Key Card - Tesla Model Y"
        and oldPhone.name == "Smartphone", "an English client: the same items in English")
    getText, getTextOrNull, getItemName, isClient = realGT, realGTN, realName, realCli
end
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

-- Seated in a Tesla: CarKeys on the player swap too; a start waits for a sweep that may still swap this car's key, and
-- a sweep waits for a start whose Starting state may still move the key into the ignition (KeysUI.lua, K.sweep).
H.section("keys: CarKey -> key card while seated (client)")
do
    local function tickFor(ms)
        for _ = 0, ms / 100 do
            for fn in pairs(ticks) do fn() end
            H.advanceMs(100)
        end
    end
    local function sweeps(from)
        local n = 0
        for i = from + 1, #H.clientSent do if H.clientSent[i].command == "keySweep" then n = n + 1 end end
        return n
    end
    local sc = tesla({ pct = 60 })
    local sInv = container()
    local sp = player("seated", sInv, sc.x, sc.y)
    sp.vehicle, sc.driver = sc, sp
    local k1 = sInv:AddItem(key("Base.CarKey", sc.keyId))
    local from = #H.clientSent
    for _, fn in ipairs(hooks.OnEnterVehicle or {}) do fn(sp) end
    tickFor(1000)
    check(sweeps(from) == 1, "seated: getting in with a CarKey asks for the swap a second later, still in the seat")
    local start = setmetatable({ character = sp }, { __index = ISStartVehicleEngine })
    check(start:waitToStart() == true, "start waits while the sweep may still swap this car's key")
    sInv:Remove(k1)
    sInv:AddItem(key(K.CARD, sc.keyId)) -- the swap arrives
    check(start:waitToStart() == false, "start goes once this car's CarKey is gone")
    from = #H.clientSent
    sInv:AddItem(key("Base.CarKey", sc.keyId))
    UI.checkKeys(sp)
    check(sweeps(from) == 0, "a CarKey right after a start: not asked yet (the Starting state may still move it in)")
    tickFor(K.START_MS + 1000)
    check(sweeps(from) == 1, "... asked once the start has settled")
    check(start:waitToStart() == true, "start waits for that sweep too")
    H.advanceMs(K.SWAP_WAIT_MS)
    check(start:waitToStart() == false, "no swap within SWAP_WAIT_MS (dropped, lost): the start goes with the CarKey")
    from = #H.clientSent
    ISExitVehicle.perform(setmetatable({ character = sp }, { __index = ISExitVehicle }))
    tickFor(1000)
    check(sweeps(from) == 1, "getting out asks again for a CarKey asked before (the seated ask may have been refused)")
    sc.driver = nil
end

-- A CarKey later than the grab's perform (a busy MP client: seconds; keys-mp latekey) or with no client action at all
-- (/additem, other mods): the inventory list refresh that shows it asks, or with the window closed the next game minute.
-- No polling in between (KeysUI.lua refreshContainer, EveryOneMinute).
H.section("keys: a CarKey that shows up late or on its own (client)")
do
    local function tickFor(ms)
        for _ = 1, ms / 100 do
            for fn in pairs(ticks) do fn() end
            H.advanceMs(100)
        end
    end
    local function sweeps(from)
        local n = 0
        for i = from + 1, #H.clientSent do if H.clientSent[i].command == "keySweep" then n = n + 1 end end
        return n
    end
    local function nTicks() local n = 0; for _ in pairs(ticks) do n = n + 1 end; return n end
    local gInv = container()
    local gp = player("grabber", gInv, car.x + 3, car.y)
    getSpecificPlayer = function(n) return n == 0 and gp or nil end
    local mine = pane(gInv, true)
    local base, from = nTicks(), #H.clientSent
    local a = setmetatable({ character = gp, queueList = { { type = "Base.CarKey", items = {} } } }, { __index = ISGrabItemAction })
    a:start()
    tickFor(1000)
    a:perform() -- the server's Done: no CarKey here yet
    tickFor(12000)
    check(sweeps(from) == 0 and nTicks() == base, "late grab: nothing asked while the CarKey is not here, no tick hook left")
    gInv:AddItem(key("Base.CarKey", car.keyId)) -- 13 s after the grab began (the old retry gave up after 10)
    mine:refreshContainer() -- drawDirty after the item packet
    check(sweeps(from) == 1, "a CarKey 13 s late: the inventory list refresh that shows it asks at once")
    mine:refreshContainer()
    check(sweeps(from) == 1 and mine.refreshed == 2, "... once: refreshes with only asked CarKeys send nothing")
    from = #H.clientSent
    gInv:AddItem(key("Base.CarKey", car.keyId)) -- the server added it (/additem), the window is closed: no refresh
    for _, fn in ipairs(hooks.EveryOneMinute or {}) do fn() end
    check(sweeps(from) == 1, "a CarKey with no client action and no list drawn: asked at the next game minute")
    for _, fn in ipairs(hooks.EveryOneMinute or {}) do fn() end
    check(sweeps(from) == 1, "... and not again the minute after")
    from = #H.clientSent
    pane(container(key("Base.CarKey", car.keyId)), false):refreshContainer()
    check(sweeps(from) == 0, "a CarKey in a loot list (floor, glove box) is not asked about")
    -- Login: the window's first refresh (OnCreatePlayer) runs before GameClient.ingame, so its keySweep never reaches
    -- the server (LuaManager.java:8940-8947); the first tick after OnGameStart asks again for the same CarKey.
    gInv = container(key("Base.CarKey", car.keyId)) -- a CarKey never swapped (0.1.0's late pickup), there at login
    gp = player("relogin", gInv, car.x + 3, car.y)
    mine = pane(gInv, true)
    from = #H.clientSent
    mine:refreshContainer() -- OnCreatePlayer: asked, and lost
    for _, fn in ipairs(hooks.OnGameStart or {}) do fn() end
    tickFor(100)
    check(sweeps(from) == 2, "login: the first tick asks again for a CarKey the pre-ingame list refresh already asked about")
end
Events = realEvents
H.side(false, true)
for _, g in ipairs(GLOBALS) do _G[g] = before[g] end
T.KeysUI = nil -- its hooks went to the sink; the HUD's key-out call (HUD.lua readFast) must not reach it in later tests
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
