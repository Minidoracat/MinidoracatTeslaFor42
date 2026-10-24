-- Power liftgate, opened or closed by the driver from the dashboard key (like the touchscreen in the real car).
-- Rule shared by the key (client pre-check) and the server command `liftgate` { vid }, which unlocks a locked
-- liftgate first, toggles it, syncs the door and tells every client to animate it (architecture.md §7).
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local L = {}
T.Liftgate = L
L.PART = "TrunkDoor"
L.MAX_KMH = 1 -- "parked"; the HUD shows N below 1 km/h too

-- Returns the installed liftgate part, or nil and an IGUI_MinidoracatTesla_Deny_<reason> suffix.
function L.check(player, vehicle)
    if not vehicle or not player or vehicle:getDriver() ~= player then return nil, "NOT_DRIVER" end
    local part = vehicle:getPartById(L.PART)
    if not part or not part:getInventoryItem() or not part:getDoor() then return nil, "NO_LIFTGATE" end
    if math.abs(vehicle:getCurrentSpeedKmHour()) > L.MAX_KMH then return nil, "MOVING" end
    return part
end

-- client: the dashboard key
function L.toggle(player, vehicle)
    local part, why = L.check(player, vehicle)
    if not part then
        HaloTextHelper.addBadText(player, getText("IGUI_MinidoracatTesla_Deny_" .. why)) -- HaloTextHelper.lua
        return false
    end
    T.request(player, "liftgate", { vid = vehicle:getId() })
    return true
end

-- every client that has the car loaded: part anim (no-op until the part has a model anim,
-- BaseVehicle.java:2012-2048) and the anim's sound from the vehicle script (template TrunkDoor:
-- VehicleTrunkOpenStandard / VehicleTrunkCloseStandard; BaseVehicle.java:2090-2097)
if not isServer() then
    T.ClientCommands = T.ClientCommands or {}
    T.ClientCommands.liftgate = function(args)
        local v = getVehicleById(args.vid)
        local part = v and v:getPartById(L.PART)
        if not part then return end
        local anim = args.open and "Open" or "Close"
        v:playPartAnim(part, anim)
        v:playPartSound(part, getPlayer(), anim)
    end
end

if not isClient() then
    T.ServerCommands = T.ServerCommands or {}
    T.ServerCommands.liftgate = function(player, args)
        local v = T.commandVehicle(player, args) -- server/MinidoracatTesla/Commands.lua
        if not v then return end
        local vid = v:getId()
        local part, why = L.check(player, v)
        if not part then return T.deny(player, why, vid) end
        local door = part:getDoor()
        if door:isLocked() then
            v:toggleLockedDoor(part, player, false) -- anyone seated may unlock (BaseVehicle.java:1275-1289)
            if door:isLocked() then return T.deny(player, "LIFTGATE_LOCKED", vid) end -- lock broken
        end
        local open = not door:isOpen()
        door:setOpen(open)
        v:transmitPartDoor(part) -- BaseVehicle.java:8247-8256
        local out = { vid = vid, open = open }
        if isServer() then
            sendServerCommand(T.MODULE, "liftgate", out) -- all clients; those without the car ignore it
        else
            T.ClientCommands.liftgate(out) -- SP
        end
        T.log("liftgate " .. (open and "open" or "close") .. " vid=" .. tostring(vid) .. " by=" .. tostring(player:getUsername()))
    end
end

return L
