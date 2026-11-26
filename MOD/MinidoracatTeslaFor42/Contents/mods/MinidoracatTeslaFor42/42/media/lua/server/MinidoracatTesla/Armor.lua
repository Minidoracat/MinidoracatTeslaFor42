-- Protection kits, server side (references/upgrades.md section 4; the part and k are shared/Upgrades.lua T.Armor).
-- The damage lands in Java with no Lua hook before it (crash, zombies, weapons), so a kit gives part of it back
-- afterwards. Per loaded car with a kit, in memory only (no save, no modData): snap[partId] = { c = condition,
-- id = item ID or -1 } for the parts A.covers. Settling: same item and lower condition -> back to
-- c + loss * (1 - k), randomly rounded, never above the snapshot; higher -> new snapshot only; item changed or gone ->
-- new snapshot only (a pane or a light knocked out stays out: refitting the old item would copy it).
-- When: every game minute after the sentry scan (required first, so it still sees the loss) and at once on a crash
-- (OnPlayerGetDamage CARCRASHDAMAGE: only for a car with someone in it, BaseVehicle.java:9494-9505). Around anything
-- that changes conditions on purpose (part install / uninstall, drive unit repair / salvage, vanilla engine actions,
-- an Armor Glass smash): settle first, then a new snapshot (A.around), so what was owed is given back and the change
-- itself is kept. After an admin's vanilla vehicle commands setPartCondition / repair / repairPart: new snapshot only.
-- Also the server's half of mechanicRequireKey for both upgrade parts (A.mayRemove) and of the install checks.
if isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Sentry"
require "MinidoracatTesla/Upgrades"
require "Vehicles/TimedActions/ISInstallVehiclePart"
require "Vehicles/TimedActions/ISUninstallVehiclePart"

local T = MinidoracatTesla
local A = T.Armor

-- vehicle id -> { v = the car, snap = { [partId] = { c, id } } }. Ids are given again to other cars
-- (VehicleIDMap.java:49-62), so an entry counts only for the car it was taken from.
A.cars = {}

local function itemId(part)
    local it = part:getInventoryItem()
    return it and it:getID() or -1
end

local function entry(v)
    local e = A.cars[v:getId()]
    return e and e.v == v and e or nil
end

-- n * k as a whole number, rounded up with the chance of its fraction: on average exactly n * k
local function share(n, k)
    local x = n * k
    local f = math.floor(x)
    if ZombRandFloat(0, 1) < x - f then f = f + 1 end
    return f
end

-- One pass over the parts: give back what the covered ones lost since the snapshot (settle = true), then take the
-- new snapshot. Returns how many parts were given condition back.
local function pass(v, e, k, settle)
    local snap, n = e.snap, 0
    for i = 0, v:getPartCount() - 1 do
        local p = v:getPartByIndex(i)
        if A.covers(p) then
            local pid, c, iid = p:getId(), p:getCondition(), itemId(p)
            local s = snap[pid]
            if settle and s and s.id == iid and c < s.c then
                local set = s.c - share(s.c - c, k) -- the car keeps loss * k: never above the snapshot
                if set > c then
                    p:setCondition(set)
                    if p:getWindow() then v:transmitPartWindow(p) end
                    v:transmitPartCondition(p)
                    c, n = set, n + 1
                end
            end
            if s then s.c, s.id = c, iid else snap[pid] = { c = c, id = iid } end
        end
    end
    return n
end

-- Upgrades.lua calls these on a kit's init, install and uninstall. A car still without an id (a part init on load
-- runs before createPhysics gives one, BaseVehicle.java:799-806) is tracked by OnSpawnVehicleEnd below.
function A.track(v)
    local id = v:getId()
    if id < 0 then return end
    local e = { v = v, snap = {} }
    pass(v, e, nil, false)
    A.cars[id] = e
end

function A.untrack(v)
    if entry(v) then A.cars[v:getId()] = nil end
end

-- new snapshot, no settling
function A.resnap(v)
    local e = entry(v)
    if e then pass(v, e, nil, false) end
end

function A.settle(v)
    local e, k = entry(v), A.k(v)
    if not (e and k) then return 0 end
    return pass(v, e, k, true)
end

-- a car gone, given its id to another car, or without its kit leaves the list
function A.minute()
    local gone
    for id, e in pairs(A.cars) do
        local v = getVehicleById(id)
        if v and v == e.v and A.k(v) then
            A.settle(v)
        else
            gone = gone or {}
            gone[#gone + 1] = id
        end
    end
    if gone then for _, id in ipairs(gone) do A.cars[id] = nil end end
end
Events.EveryOneMinute.Add(A.minute) -- after Sentry's scan (required above): it must see the loss first

function A.onDamage(chr, kind)
    if kind ~= "CARCRASHDAMAGE" then return end
    local v = chr and chr:getVehicle()
    if v then A.settle(v) end
end
Events.OnPlayerGetDamage.Add(A.onDamage)

-- every load, the id given by now (BaseVehicle.java:799-806,913); an untracked id drops what another car left under it
function A.onLoad(v)
    if A.k(v) then A.track(v) else A.cars[v:getId()] = nil end
end
Events.OnSpawnVehicleEnd.Add(A.onLoad)

-- vanilla vehicle commands that set conditions; Commands.lua calls this after vanilla's handler ran. Vanilla runs them
-- for UseMechanicsCheat only (VehicleCommands.lua:28-30,261-263,289-291): anyone else's would drop what is owed.
local RESNAP = { setPartCondition = true, repair = true, repairPart = true }
function A.onVehicleCommand(module, command, player, args)
    if module ~= "vehicle" or not RESNAP[command] or type(args) ~= "table" then return end
    if isServer() and not checkPermissions(player, Capability.UseMechanicsCheat) then return end
    local v = getVehicleById(tonumber(args.vehicle) or -1)
    if v then A.resnap(v) end
end

-- ---------------------------------------------------------------- who may take an upgrade off
-- mechanicRequireKey is checked on the client only (VehicleUtils.RequiredKeyNotFound, Vehicles.lua:1380-1389): the
-- server's NetTimedAction.isValid never calls Lua (NetTimedAction.java:118-120) and vanilla's complete only rolls the
-- skill, so a modified client took a kit off a locked car (upgrades.md section 3). The same rule here, server only
-- (SP runs vanilla's own test): an admin's mechanics cheat, or VehicleEasyUse, an unlocked door or open window
-- (VehicleUtils.CheckForUnlockedDoorsWindows), or this car's key on the player (a loose key or this mod's key card /
-- phone key, as T.authorized counts them); then VehicleManager's SALVAGE right when it is there (T.mayUseCable's
-- shape; its own action guard asks the same). requireEmpty is the client's test too (Vehicles.lua:948-949).
-- Not RequiredKeyNotFound itself, nor canUninstallPart: both read ISVehicleMechanics.cheat, which a server lacks.
A.GUARDED = { TeslaArmor = true, TeslaFridge = true }

local function holdsKey(player, v)
    local K = T.Keys
    return player:getInventory():haveThisKeyId(v:getKeyId()) ~= nil or K.card(player, v) ~= nil or K.phoneKey(player, v) ~= nil
end

-- true, or false and a deny reason (nil: no message, only a modified client gets here)
function A.mayRemove(player, v, part)
    if checkPermissions(player, Capability.UseMechanicsCheat) then return true end
    local tbl = part:getTable("uninstall")
    local box = part:getItemContainer()
    if tbl and tbl.requireEmpty and (part:getContainerContentAmount() >= 0.0005 or box and not box:isEmpty()) then
        return false, nil
    end
    if not (SandboxVars.VehicleEasyUse or VehicleUtils.CheckForUnlockedDoorsWindows(v) or holdsKey(player, v)) then
        return false, "CAR_LOCKED"
    end
    local api = MinidoracatVehicleManagerAPI
    if api and api.canUse then
        local ok, why = api.canUse(player, v, "SALVAGE", { mod = T.MODULE })
        if not ok then return false, T.VM_REASONS[why] and why or "NOT_OWNER" end
    end
    return true
end

-- install / uninstall complete run on the server in MP (NetTimedAction.java:132-134) and locally in SP. Refused: the
-- part and the item stay as they are; complete returns false (the client gets the action rejected, ActionManager.java:
-- 74-97), its mechanics window flashes red, and the part is sent again. A snapshot error never breaks the action.
local function safely(fn, v)
    local ok, err = pcall(fn, v)
    if not ok then T.log("armor snapshot error " .. tostring(err)) end
end

-- fn changes conditions on purpose: what the kit owes is given back first, fn's own change is kept (new snapshot)
function A.around(v, fn)
    if not v then return fn() end
    safely(A.settle, v)
    local r = fn()
    safely(A.resnap, v)
    return r
end

-- why: logged; deny: the reason the player is told (nil: none, the mechanics window still flashes red)
local function refuse(v, part, chr, what, why, ...)
    local deny = ...
    T.log("upgrade " .. what .. " refused vid=" .. v:getId() .. " part=" .. part:getId() .. " by "
        .. tostring(chr:getUsername()) .. " why=" .. tostring(why))
    v:transmitPartItem(part)
    chr:sendObjectChange(IsoObjectChange.MECHANIC_ACTION_DONE, { success = false })
    if deny then T.deny(chr, deny, v:getId()) end
    return false
end

-- vanilla's complete fits self.item over whatever is there and takes it from the main inventory without asking
-- (ISInstallVehiclePart.lua:61-99): two players fitting the same empty slot, the second one's kit replaced the first.
-- So on the server: the slot still empty, the item in the player's main inventory (where vanilla removes it from)
-- and one this part takes. No deny message (no reason key for it): the mechanics window flashes red.
local function installRefusal(self)
    local part, it, chr = self.part, self.item, self.character
    if part:getInventoryItem() then return "taken" end
    if not (it and chr:getInventory():contains(it)) then return "item" end
    local types = part:getItemType()
    if not (types and types:contains(it:getFullType())) then return "type" end
end

local install = ISInstallVehiclePart.complete
ISInstallVehiclePart.complete = function(self)
    local v, part, chr = self.vehicle, self.part, self.character
    if isServer() and v and part and chr and A.GUARDED[part:getId()] then
        local bad = installRefusal(self)
        if bad then return refuse(v, part, chr, "install", bad) end
    end
    return A.around(v, function() return install(self) end)
end

local uninstall = ISUninstallVehiclePart.complete
ISUninstallVehiclePart.complete = function(self)
    local v, part, chr = self.vehicle, self.part, self.character
    if isServer() and v and part and chr and A.GUARDED[part:getId()] and part:getInventoryItem() then
        local ok, why = A.mayRemove(chr, v, part)
        if not ok then return refuse(v, part, chr, "uninstall", why, why) end
    end
    return A.around(v, function() return uninstall(self) end)
end
