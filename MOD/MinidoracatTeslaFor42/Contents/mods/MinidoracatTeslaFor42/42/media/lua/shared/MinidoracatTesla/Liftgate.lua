-- Power liftgate and the other doors, opened or closed by the driver with a click on the dashboard's car picture
-- (like the touchscreen in the real car). Rule shared by the dashboard (client pre-check) and the
-- server command `liftgate` { vid, part }, which unlocks a locked door first, toggles it, syncs it and tells the
-- clients near the car to animate it (architecture.md §7).
-- Also syncs the part anim of vanilla door open/close on Teslas in MP: vanilla plays it only on the client that
-- opened the door (ISOpenVehicleDoor.lua:28-31 "TODO: sync part animation"), so everyone else saw no motion.
-- And E at a Tesla's open hood shuts it (vanilla opens the mechanics window again instead).
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local L = {}
T.Liftgate = L
-- doors the driver may open or close from the dashboard (the HUD car picture; nothing else is accepted); the
-- Cybertruck's tonneau cover too (owner's manual p.60: the touchscreen and the app open it)
L.PARTS = { DoorFrontLeft = true, DoorFrontRight = true, DoorRearLeft = true, DoorRearRight = true, TrunkDoor = true,
    EngineDoor = true, TrunkTonneau = true }

-- Returns the installed door part `id` (one of L.PARTS), or nil and an IGUI_MinidoracatTesla_Deny_<reason> suffix.
function L.check(player, vehicle, id)
    if not vehicle or not player or vehicle:getDriver() ~= player then return nil, "NOT_DRIVER" end
    local part = type(id) == "string" and L.PARTS[id] and vehicle:getPartById(id)
    if not part or not part:getInventoryItem() or not part:getDoor() then return nil, "NO_DOOR" end
    if not T.stopped(vehicle) then return nil, "MOVING" end
    return part
end

-- MP: the clients that can have car v loaded, i.e. every client with an online player within NEAR_TILES of it on both
-- axes, but `except`'s: `cmd` with `args`, once per client. The server sends a car's updates to a connection with a
-- player within relevantRange * 8 tiles on both axes (VehicleManager.java:164, UdpConnection.java:224-226),
-- relevantRange = clamp(the client's chunk grid, 12, 20) / 2 + 2 <= 12 chunks (GameServer.java:2808-2809), and a
-- client keeps a car only inside its chunk map, at most 19 chunks wide (IsoChunkMap.java:114-119). Whoever comes nearer
-- later loads the car with its doors and hue (VehicleFullUpdatePacket.java:122-126 = BaseVehicle.save) and the engine
-- poses a door from isOpen whenever no anim plays (BaseVehicle.java:3926-3930), so nothing is lost by not telling them.
-- Once per client, none to `except`'s (it played the anim in :start; its split-screen players share it): T.sendClients
-- (server/MinidoracatTesla/Commands.lua).
L.NEAR_TILES = 96
local function sendNear(v, cmd, args, except)
    local x, y, r = v:getX(), v:getY(), L.NEAR_TILES
    T.sendClients(function(p) return math.abs(p:getX() - x) <= r and math.abs(p:getY() - y) <= r end, cmd, args, except)
end

-- Doors open or swinging ride in the colour hue's integer part (bit k-1 for SHELL_DOORS[k]): the shader draws a door's
-- window from the door model while its bit is set and from its closed copy in the cabin glass model (drawn last,
-- CabinGlass below) while it is clear, and drops the cabin shell's wall behind a door whose bit is set. Hue is the
-- only per-car shader value Lua sets that vanilla leaves alone (BaseVehicle.updateLights -> painColor, every render,
-- BaseVehicle.java:5817), it is saved (:2663) and goes out with the car (VehicleFullUpdatePacket.java:126) and every
-- VehicleProperties (VehicleProperties.java:42); every reader drops the integer part (vehicle_common.frag.glsl:12
-- mod 1, the paint shader's mod 1, Color.HSBtoRGB).
L.SHELL_DOORS = { "DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight", "TrunkDoor" }
local SHELL_K = {}
for k, id in ipairs(L.SHELL_DOORS) do SHELL_K[id] = k end
-- When a bit flips, as fractions of the door's clip: as the opening swing starts and as the closing one ends. The
-- glass draws after every door, so a far door shows through the glass for its whole swing; the closed copy hands over
-- to the door's own window only where the two are the same (the clip's first / last frame). The vanilla door actions
-- take no time (getDuration 0, ISCloseVehicleDoor.lua:92-94), so the clear waits out the closing clip on the door's
-- own clock, T.clipStep (Core.lua): fast forward ends the swing sooner, a pause holds it. Clips are 0.8 s, else Specs
-- doorClip[part]. Read by E2E doors-audit-sp.
L.FLIP = { open = 0, close = 1 }
-- [vid] = { [k] = clip seconds bit k-1 is held for }; the OnTick runs while any is pending. When one runs out, the
-- server (and SP) sets the bit to its door's state (L.syncShell); an MP client that played the swing itself
-- (L.localSwing) sets it to the door's state that reached it, so an open the server never made (the action cancelled,
-- the door locked meanwhile) drops it again. Until then such a client sets it again every tick: the server's hue also
-- comes in every VehicleProperties (blood, keys, alarm: VehicleProperties.java:42), maybe cleared ahead of this swing
local pending, ticking = {}, false
local function empty(t)
    for _ in pairs(t) do return false end
    return true
end
local function flipClip(vehicle, id)
    local c = T.spec(vehicle) and T.spec(vehicle).doorClip
    return (c and c[id] or 0.8) * L.FLIP.close
end
local function setBit(vehicle, k, on)
    local h, b = vehicle:getColorHue(), 2 ^ (k - 1)
    if (math.floor(math.floor(h) / b) % 2 == 1) == on then return end
    vehicle:setColorHSV(h + (on and b or -b), vehicle:getColorSaturation(), vehicle:getColorValue())
end
local shellTick
-- add / remove only on a change: Event.trigger walks the list by index (Event.java:52-62), so taking the tick out and
-- back in from inside it would skip the next mod's OnTick once
local function retick()
    local left = not empty(pending)
    if left == ticking then return end
    ticking = left
    if left then Events.OnTick.Add(shellTick) else Events.OnTick.Remove(shellTick) end
end
shellTick = function()
    local step, due = T.clipStep(), {}
    for vid, ks in pairs(pending) do
        local v = getVehicleById(vid)
        -- unloaded, or the id now another car's: drop it (OnSpawnVehicleEnd sets a car's bits when it loads)
        if not (v and T.isTesla(v)) then
            pending[vid] = nil
        else
            for k, left in pairs(ks) do
                ks[k] = left - step
                if ks[k] <= 1e-6 then due[vid] = v elseif isClient() then setBit(v, k, true) end
            end
        end
    end
    for vid, v in pairs(due) do
        if isClient() then
            local ks = pending[vid]
            for k, left in pairs(ks) do
                if left <= 1e-6 then
                    local part = v:getPartById(L.SHELL_DOORS[k])
                    local door = part and part:getDoor()
                    ks[k] = nil
                    setBit(v, k, door ~= nil and door:isOpen())
                end
            end
            if empty(ks) then pending[vid] = nil end
        else
            L.syncShell(v)
        end
    end
    retick()
end
-- The server (and SP) sets the bits from the doors: an open door's at once, a shut door's after its closing clip;
-- now: all at once (a car just loaded: its doors stand where they were saved)
function L.syncShell(vehicle, now)
    local h = vehicle:getColorHue()
    local was, bits, vid = math.floor(h), 0, vehicle:getId()
    local ks = not now and pending[vid] or {}
    for k, id in ipairs(L.SHELL_DOORS) do
        local part = vehicle:getPartById(id)
        local door = part and part:getDoor()
        local bit = 2 ^ (k - 1)
        local want, have = door and door:isOpen() or false, math.floor(was / bit) % 2 == 1
        if now or not door or want or want == have then
            have, ks[k] = want, nil
        else
            ks[k] = ks[k] or flipClip(vehicle, id)
            if ks[k] <= 1e-6 then have, ks[k] = false, nil end
        end
        if have then bits = bits + bit end
    end
    pending[vid] = not empty(ks) and ks or nil
    retick()
    local hue = h - was + bits
    if hue == h then return end
    vehicle:setColorHSV(hue, vehicle:getColorSaturation(), vehicle:getColorValue())
    if not isServer() then return end
    -- MP: a command to the clients near, not transmitColorHSV: each VehicleProperties re-adds a key that is in the
    -- ignition on every client, which logs "ItemContainer.AddItem > Error, container already has id"
    -- (VehicleProperties.java:27-33).
    -- ponytail: no sequence number; a resent command overtaking a newer one (RELIABLE, unordered: PacketTypes.java:510)
    -- leaves the older hue until the next door change or VehicleProperties. Add a per-car counter if it shows up.
    sendNear(vehicle, "shell", { vid = vehicle:getId(), hue = hue })
end
-- Every client that plays a door's swing (and SP) sets that door's bit in the same frame, so its window never shows
-- twice or not at all while the server's hue travels: the opener in the vanilla action's start (below), everyone
-- else on partAnim. It holds the bit for the clip, then follows the door (shellTick): closing, always; opening, while
-- the door here is not open yet (the server's door state on its way, or an open it never makes). The server's hue
-- stays the saved truth.
function L.localSwing(vehicle, part, open)
    local k = SHELL_K[part:getId()]
    if isServer() or not k or not T.isTesla(vehicle) then return end
    local vid = vehicle:getId()
    local ks = pending[vid] or {}
    ks[k] = not (open and part:getDoor():isOpen()) and flipClip(vehicle, part:getId()) or nil
    pending[vid] = not empty(ks) and ks or nil
    setBit(vehicle, k, true)
    retick()
end

-- client: the dashboard's car picture
function L.toggle(player, vehicle, id)
    local part, why = L.check(player, vehicle, id)
    if not part then
        HaloTextHelper.addBadText(player, getText("IGUI_MinidoracatTesla_Deny_" .. why)) -- HaloTextHelper.lua
        return false
    end
    T.request(player, "liftgate", { vid = vehicle:getId(), part = id })
    return true
end

-- Cabin glass (part CabinGlass, model Glass: every window of the car, convert.py pieces) draws after every other part
-- model, so it blends over a far door instead of hiding it by depth. A car draws its part models in the order they
-- became visible (BaseVehicle.models: setModelVisible appends, BaseVehicle.java:1707-1754; ModelSlotRenderData.java:
-- 139-144,210-218). Its init shows it after every part got its item (createPhysics: createParts then initParts,
-- BaseVehicle.java:868-869), on the server and on each client that loads the car (VehicleFullUpdatePacket.java:86-90).
-- A part model shown later (a door, liftgate, hood, tonneau or tire fitted again) lands after it, so the glass is
-- hidden and shown again to go back to the end. An MP client adds the fitted part's model when the part's item reaches
-- it (VehiclePartItem.java:28) and never reorders the models it has to the server's list (VehiclePartModels.java:
-- 22-46), so each client does the same once that item is there.
T.Init = T.Init or {}
function T.Init.CabinGlass(vehicle, part) part:setModelVisible("Glass", true) end
function L.glassLast(vehicle)
    local p = vehicle:getPartById("CabinGlass")
    if not p then return end
    p:setModelVisible("Glass", false)
    p:setModelVisible("Glass", true)
end

-- every client that has the car loaded: part anim (no-op until the part has a model anim,
-- BaseVehicle.java:2012-2048) and, with `sound`, the anim's sound from the vehicle script (template TrunkDoor:
-- VehicleTrunkOpenStandard / VehicleTrunkCloseStandard; BaseVehicle.java:2090-2097)
if not isServer() then
    T.ClientCommands = T.ClientCommands or {}
    T.ClientCommands.partAnim = function(args)
        local v = type(args.part) == "string" and getVehicleById(args.vid)
        local part = v and v:getPartById(args.part)
        if not part or not part:getDoor() then return end
        local anim = args.open and "Open" or "Close"
        v:playPartAnim(part, anim)
        L.localSwing(v, part, args.open == true)
        if args.sound then v:playPartSound(part, getPlayer(), anim) end
    end
    -- L.syncShell's hue from the server. A swing this client still plays keeps its bit (shellTick too): the server
    -- times its clear on its own OnTick clock, which runs ahead of the clients' (E2E tesla-glass-1102-mp-y-e: cleared on
    -- B 0.4-0.6 clip s into the 0.8 s swing; not proven why, likely the dedicated server's fpsMultiplier, a running
    -- average of its frame rate that drops at once and rises by 1 a frame, GameServer.java:1112-1118)
    T.ClientCommands.shell = function(args)
        local v = getVehicleById(args.vid)
        if not (v and args.hue) then return end
        v:setColorHSV(args.hue, v:getColorSaturation(), v:getColorValue())
        for k in pairs(pending[args.vid] or {}) do setBit(v, k, true) end
    end
    -- L.glassAfter from the server: the glass back to the end once these parts' items are here (they come in a vehicle
    -- update, often after this command). [vid] = { parts = { [part id] = item id }, till }: the item that was fitted, not
    -- one still here from before (InventoryItem.java:1947 keeps the server's id); a later command for the same car adds
    -- its parts (RELIABLE, unordered: PacketTypes.java:510). Given up after 10 s: the glass to the end anyway.
    local waiting, wticking = {}, false
    local function glassTick()
        local now = getTimestampMs()
        for vid, w in pairs(waiting) do
            local v, ready = getVehicleById(vid), true
            for id, item in pairs(w.parts) do
                local p = v and v:getPartById(id)
                local have = p and p:getInventoryItem()
                if p and not (have and have:getID() == item) then ready = false end
            end
            if not v or ready or now > w.till then
                if v and T.isTesla(v) then L.glassLast(v) end
                waiting[vid] = nil
            end
        end
        if empty(waiting) then
            wticking = false
            Events.OnTick.Remove(glassTick)
        end
    end
    T.ClientCommands.glassLast = function(args)
        if type(args.parts) ~= "table" then return end
        local w = waiting[args.vid] or { parts = {} }
        for id, item in pairs(args.parts) do
            if type(id) == "string" then w.parts[id] = item end
        end
        w.till = getTimestampMs() + 10000
        waiting[args.vid] = w
        if not wticking then
            wticking = true
            Events.OnTick.Add(glassTick)
        end
    end
    -- the opener's own swing (and SP): its bit in the frame the vanilla action plays the anim (:start)
    require "Vehicles/TimedActions/ISOpenVehicleDoor"
    require "Vehicles/TimedActions/ISCloseVehicleDoor"
    for cls, open in pairs({ [ISOpenVehicleDoor] = true, [ISCloseVehicleDoor] = false }) do
        local start = cls.start
        cls.start = function(self)
            start(self)
            if self.vehicle and self.part and self.part:getVehicle() == self.vehicle then
                L.localSwing(self.vehicle, self.part, open)
            end
        end
    end
end

-- E at a Tesla's open hood shuts it, like E at a trunk (Vehicles.Use.TrunkDoorOpen) and the gamepad's Close Hood
-- prompt (ISButtonPrompt.lua:590-594). Vanilla E at an open hood (Vehicles.Use.EngineDoor, Vehicles.lua:838-847)
-- shuts it only by closing the mechanics window opened from that hood while the player stands at the hood
-- (ISVehicleMechanics.lua:1408-1413). A window gone some other way (it closes itself 6 tiles from the car,
-- ISVehicleMechanics.lua:20-22) left the lid up, and E there only opened the window again (user 2026-10-31, after a
-- Workshop comment; E2E tesla-hoode-1031-walk). That window still open: vanilla, which shuts both. Its window still on
-- the way (E again during this car's ISOpenMechanicsUIAction): that action stops first, or its perform would open the
-- lid again (ISVehicleMechanics.lua:1414-1417). Vehicles.lua is a server-folder file, loaded after this one:
-- L.wrapHoodUse runs once the game starts, and wraps once.
if not isServer() then
    local function stopWindow(chr, vehicle)
        local q = ISTimedActionQueue.getTimedActionQueue(chr)
        for i, a in ipairs(q.queue) do
            if a.Type == "ISOpenMechanicsUIAction" and a.vehicle == vehicle then
                -- the running one: stopping it resets the queue anyway (ISBaseTimedAction.lua:63-64)
                if i == 1 then ISTimedActionQueue.clear(chr) else a:forceCancel(); q:removeFromQueue(a) end
                return
            end
        end
    end
    function L.wrapHoodUse()
        if L.hoodUse then return end
        local use = Vehicles.Use.EngineDoor
        L.hoodUse = use
        Vehicles.Use.EngineDoor = function(vehicle, part, chr)
            local door = part:getDoor()
            if door and door:isOpen() and part:getInventoryItem() and T.isTesla(vehicle) then
                local ui = getPlayerMechanicsUI(chr:getPlayerNum())
                local shown = ui ~= nil and ui:isReallyVisible()
                if not (shown and ui.usedHood == part) then
                    -- a window not from this hood: another car's (it closes itself only 6 tiles from that car), an
                    -- admin's or the debug cheat's (ISVehicleMenu.lua:968-971), or one opened while no hood was fitted
                    if shown then ui:close() end
                    stopWindow(chr, vehicle)
                    ISTimedActionQueue.add(ISCloseVehicleDoor:new(chr, vehicle, part))
                    return
                end
            end
            return use(vehicle, part, chr)
        end
    end
    Events.OnGameStart.Add(L.wrapHoodUse)
end

if not isClient() then
    -- to the clients near but `except` (MP), or straight to the handler (SP)
    local function broadcast(v, out, except)
        if not isServer() then return T.ClientCommands.partAnim(out) end
        sendNear(v, "partAnim", out, except)
    end

    -- A Tesla locks as a whole: the liftgate, the frunk lid and the Cybertruck's tonneau cover lock and unlock with the
    -- car ("once the vehicle is locked, the tonneau cover is locked in its current position", Cybertruck owner's manual
    -- p.32: an open one stays open, ContainerAccess.Vault reads only open or shut). Vanilla never locks the
    -- hood (Vehicles.Create.Default; ISLockDoors only the cabin doors), and an unlocked lid opens for anyone
    -- (ISOpenVehicleDoor.lua:61-64) while the frunk only asks whether the lid is open (Core.lua ContainerAccess.Frunk).
    -- A broken lock is never locked (it could never open again), but a lid jammed locked does unlock with the car (the
    -- liftgate always did, through setTrunkLocked, BaseVehicle.java:9533-9545).
    L.LIDS = { TrunkDoor = true, EngineDoor = true, TrunkTonneau = true }
    function L.lockLids(v, locked)
        for id in pairs(L.LIDS) do
            local part = v:getPartById(id)
            local door = part and part:getInventoryItem() and part:getDoor()
            if door and door:isLocked() ~= locked and not (locked and door:isLockBroken()) then
                door:setLocked(locked)
                v:transmitPartDoor(part) -- BaseVehicle.java:8247-8256
            end
        end
    end

    -- A lid that shuts on a locked car locks again, however it was opened or shut (the app, the dashboard, by hand,
    -- the owner's "unlock hood"): areAllDoorsLocked only sees the cabin doors (BaseVehicle.java:9332-9335), so it
    -- would otherwise stay unlocked behind "locked".
    -- Model X (Specs falcon): a falcon wing door shut while both front doors are locked locks again too, however it
    -- was shut (the app's falcon button, the dashboard, by hand)
    local WINGS, FRONTS = { DoorRearLeft = true, DoorRearRight = true }, { "DoorFrontLeft", "DoorFrontRight" }
    local function frontsLocked(v)
        for _, id in ipairs(FRONTS) do
            local p = v:getPartById(id)
            local d = p and p:getDoor()
            if not (d and d:isLocked()) then return false end
        end
        return true
    end
    function L.relock(v, part)
        local door, id = part:getDoor(), part:getId()
        if not part:getInventoryItem() or door:isOpen() or door:isLocked() or door:isLockBroken() then return false end
        if L.LIDS[id] then
            if not v:areAllDoorsLocked() then return false end
        elseif not (WINGS[id] and T.spec(v) and T.spec(v).falcon and frontsLocked(v)) then
            return false
        end
        door:setLocked(true)
        -- a wing that was the last unlocked cabin door: a lid shut while it stood unlocked stayed unlocked
        -- (areAllDoorsLocked false above), so lock the lids now, as the vanilla per-door lock does (ISLockVehicleDoor below)
        if WINGS[id] and v:areAllDoorsLocked() then L.lockLids(v, true) end
        return true
    end

    function L.swing(v, part, open, who)
        part:getDoor():setOpen(open)
        if not open then L.relock(v, part) end
        v:transmitPartDoor(part) -- BaseVehicle.java:8247-8256
        L.syncShell(v)
        local f = T.Truck and T.Truck.bedLight
        if f then f(v) end
        broadcast(v, { vid = v:getId(), part = part:getId(), open = open, sound = true })
        T.log("liftgate " .. part:getId() .. " " .. (open and "open" or "close") .. " vid=" .. tostring(v:getId()) .. " by=" .. tostring(who))
    end

    T.ServerCommands = T.ServerCommands or {}
    T.ServerCommands.liftgate = function(player, args)
        local v = T.commandVehicle(player, args) -- server/MinidoracatTesla/Commands.lua
        if not v then return end
        local vid = v:getId()
        local part, why = L.check(player, v, args.part)
        if not part then return T.deny(player, why, vid) end
        local door = part:getDoor()
        if door:isLocked() then
            v:toggleLockedDoor(part, player, false) -- anyone seated may unlock (BaseVehicle.java:1275-1289)
            if door:isLocked() then return T.deny(player, "LOCK_BROKEN", vid) end
        end
        L.swing(v, part, not door:isOpen(), player:getUsername())
    end

    -- vanilla door actions complete here, SP or MP server (LuaTimedActionNew.java:166-168, not on a client): the shell
    -- bits; MP: the part anim to everyone but the opener (it played the anim and sound in :start, a second Open would
    -- restart it)
    require "Vehicles/TimedActions/ISOpenVehicleDoor"
    require "Vehicles/TimedActions/ISCloseVehicleDoor"
    local function wrap(cls, open)
        local orig = cls.complete
        cls.complete = function(self)
            local ok = orig(self)
            local v, part = self.vehicle, self.part -- two arguments: only a part of this car (Keys.lua K.lidUnlock)
            if ok and v and part and T.isTesla(v) and part:getDoor() and part:getVehicle() == v
                and part:getDoor():isOpen() == open then
                if not open and L.relock(v, part) then v:transmitPartDoor(part) end
                L.syncShell(v)
                local f = T.Truck and T.Truck.bedLight
                if f then f(v) end
                if isServer() then broadcast(v, { vid = v:getId(), part = part:getId(), open = open }, self.character) end
            end
            return ok
        end
    end
    wrap(ISOpenVehicleDoor, true)
    wrap(ISCloseVehicleDoor, false)

    -- vanilla locks (same place): "Lock / Unlock Doors" inside the car (ISLockDoors) takes the lids along; a single
    -- door locked with the key (ISLockVehicleDoor) that leaves every cabin door locked locks the lids too. A single
    -- door unlocked (the handle, ISUnlockVehicleDoor) leaves them, as it leaves the other doors.
    require "Vehicles/TimedActions/ISLockDoors"
    require "Vehicles/TimedActions/ISLockVehicleDoor"
    local lockDoors = ISLockDoors.complete
    ISLockDoors.complete = function(self)
        local ok = lockDoors(self)
        if ok and self.vehicle and T.isTesla(self.vehicle) then L.lockLids(self.vehicle, self.locked == true) end
        return ok
    end
    local lockDoor = ISLockVehicleDoor.complete
    ISLockVehicleDoor.complete = function(self)
        local ok = lockDoor(self)
        local v = self.vehicle
        if ok and v and T.isTesla(v) and v:areAllDoorsLocked() then L.lockLids(v, true) end
        return ok
    end

    -- a part model shown again (the CabinGlass note above): the glass back to the end here, and on the clients near once
    -- those parts' items reach them (parts: VehiclePart list, each with its item)
    function L.glassAfter(v, parts)
        L.glassLast(v)
        if not isServer() then return end
        local items = {}
        for _, part in ipairs(parts) do items[part:getId()] = part:getInventoryItem():getID() end
        sendNear(v, "glassLast", { vid = v:getId(), parts = items })
    end
    local function modelled(part)
        return part:getInventoryItem() and part:getId() ~= "CabinGlass" and part:getScriptPart():getModelCount() > 0
    end
    -- fitting a part (SP or MP server, like the door actions above)
    require "Vehicles/TimedActions/ISInstallVehiclePart"
    local install = ISInstallVehiclePart.complete
    ISInstallVehiclePart.complete = function(self)
        local ok = install(self)
        local v, part = self.vehicle, self.part
        if v and part and T.isTesla(v) and modelled(part) then
            L.glassAfter(v, { part })
        end
        return ok
    end
    -- the admin / debug repair (vanilla vehicle commands repair, repairPart: VehicleCommands.lua:330-370) refits every
    -- missing part. Listens from server/MinidoracatTesla/Commands.lua, after vanilla's handler has refitted them (a
    -- shared file's listener would run first: ParkModes.lua S.beforeVehicleCommand). Named so harness test_liftgate runs
    -- it alone.
    function L.onVehicleCommand(module, command, player, args)
        if module ~= "vehicle" or (command ~= "repair" and command ~= "repairPart") then return end
        local v = type(args) == "table" and getVehicleById(args.vehicle)
        if not (v and T.isTesla(v)) or isServer() and not checkPermissions(player, Capability.UseMechanicsCheat) then return end
        local parts = {}
        for i = 0, v:getPartCount() - 1 do
            local part = v:getPartByIndex(i)
            if modelled(part) then parts[#parts + 1] = part end
        end
        L.glassAfter(v, parts)
    end

    -- every load (BaseVehicle.java:904): a locked car from an older save or the world spawn (cabin doors locked by
    -- Vehicles.Create.Door, the hood never) gets its shut lids locked; the shell bits are set to the saved doors at once
    -- (they stand still; a save inside a swing kept the old bit, an older save's open door had none), dropping whatever
    -- was still pending under this id. Named so harness test_liftgate runs this handler alone.
    function L.onLoad(v)
        if not T.isTesla(v) then return end
        for id in pairs(L.LIDS) do
            local part = v:getPartById(id)
            if part and part:getInventoryItem() and part:getDoor() and L.relock(v, part) then v:transmitPartDoor(part) end
        end
        L.syncShell(v, true)
    end
    Events.OnSpawnVehicleEnd.Add(L.onLoad)
end

return L
