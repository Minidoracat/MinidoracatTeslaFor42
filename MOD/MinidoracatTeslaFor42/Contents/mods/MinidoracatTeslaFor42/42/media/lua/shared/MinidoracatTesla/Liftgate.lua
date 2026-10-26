-- Power liftgate and the other doors, opened or closed by the driver from the dashboard (liftgate key, or a click
-- on the car picture: like the touchscreen in the real car). Rule shared by the dashboard (client pre-check) and the
-- server command `liftgate` { vid, part }, which unlocks a locked door first, toggles it, syncs it and tells every
-- client to animate it (architecture.md §7).
-- Also syncs the part anim of vanilla door open/close on Teslas in MP: vanilla plays it only on the client that
-- opened the door (ISOpenVehicleDoor.lua:28-31 "TODO: sync part animation"), so everyone else saw no motion.
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local L = {}
T.Liftgate = L
L.PART = "TrunkDoor" -- the liftgate key
-- doors the driver may open or close from the dashboard (the HUD car picture; nothing else is accepted)
L.PARTS = { DoorFrontLeft = true, DoorFrontRight = true, DoorRearLeft = true, DoorRearRight = true, TrunkDoor = true,
    EngineDoor = true }
L.MAX_KMH = 1 -- "parked"; the HUD shows N below 1 km/h too

-- Returns the installed door part `id` (one of L.PARTS), or nil and an IGUI_MinidoracatTesla_Deny_<reason> suffix.
function L.check(player, vehicle, id)
    if not vehicle or not player or vehicle:getDriver() ~= player then return nil, "NOT_DRIVER" end
    local part = type(id) == "string" and L.PARTS[id] and vehicle:getPartById(id)
    if not part or not part:getInventoryItem() or not part:getDoor() then return nil, "NO_DOOR" end
    if math.abs(vehicle:getCurrentSpeedKmHour()) > L.MAX_KMH then return nil, "MOVING" end
    return part
end

-- Open doors ride in the colour hue's integer part (bit k-1 for SHELL_DOORS[k]): the shader hides the cabin shell's
-- wall behind an open door (else the far wall showed through the roof glass where the door opening is). Hue is the
-- only per-car shader value Lua sets that vanilla leaves alone (BaseVehicle.updateLights -> painColor, every render,
-- BaseVehicle.java:5817), it is saved (:2663) and synced with the skin (VehicleProperties.java:42); every reader
-- drops the integer part (vehicle_common.frag.glsl:12 mod 1, the paint shader's mod 1, Color.HSBtoRGB).
L.SHELL_DOORS = { "DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight", "TrunkDoor" }
function L.syncShell(vehicle)
    local bits = 0
    for k, id in ipairs(L.SHELL_DOORS) do
        local part = vehicle:getPartById(id)
        local door = part and part:getDoor()
        if door and door:isOpen() then bits = bits + 2 ^ (k - 1) end
    end
    local h = vehicle:getColorHue()
    local hue = h - math.floor(h) + bits
    if hue == h then return end
    vehicle:setColorHSV(hue, vehicle:getColorSaturation(), vehicle:getColorValue())
    vehicle:transmitColorHSV() -- MP server: flag 4096, VehicleProperties to every client (BaseVehicle.java:9209-9212)
end

-- client: the dashboard (liftgate key, car picture)
function L.toggle(player, vehicle, id)
    local part, why = L.check(player, vehicle, id)
    if not part then
        HaloTextHelper.addBadText(player, getText("IGUI_MinidoracatTesla_Deny_" .. why)) -- HaloTextHelper.lua
        return false
    end
    T.request(player, "liftgate", { vid = vehicle:getId(), part = id })
    return true
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
        if args.sound then v:playPartSound(part, getPlayer(), anim) end
    end
end

if not isClient() then
    -- to every online player but `except` (MP), or straight to the handler (SP)
    local function broadcast(out, except)
        if not isServer() then return T.ClientCommands.partAnim(out) end
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p ~= except then sendServerCommand(p, T.MODULE, "partAnim", out) end -- far clients ignore it
        end
    end

    T.ServerCommands = T.ServerCommands or {}
    T.ServerCommands.liftgate = function(player, args)
        local v = T.commandVehicle(player, args) -- server/MinidoracatTesla/Commands.lua
        if not v then return end
        local vid = v:getId()
        local id = args.part
        local part, why = L.check(player, v, id)
        if not part then return T.deny(player, why, vid) end
        local door = part:getDoor()
        if door:isLocked() then
            v:toggleLockedDoor(part, player, false) -- anyone seated may unlock (BaseVehicle.java:1275-1289)
            if door:isLocked() then return T.deny(player, "LOCK_BROKEN", vid) end
        end
        local open = not door:isOpen()
        door:setOpen(open)
        v:transmitPartDoor(part) -- BaseVehicle.java:8247-8256
        L.syncShell(v)
        broadcast({ vid = vid, part = id, open = open, sound = true })
        T.log("liftgate " .. id .. " " .. (open and "open" or "close") .. " vid=" .. tostring(vid) .. " by=" .. tostring(player:getUsername()))
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
            local v, part = self.vehicle, self.part
            if ok and v and part and T.isTesla(v) and part:getDoor() and part:getDoor():isOpen() == open then
                L.syncShell(v)
                if isServer() then broadcast({ vid = v:getId(), part = part:getId(), open = open }, self.character) end
            end
            return ok
        end
    end
    wrap(ISOpenVehicleDoor, true)
    wrap(ISCloseVehicleDoor, false)
end

return L
