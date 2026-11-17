-- Tesla Semi and its 53 ft trailer: the hitch slice in the vehicle radial menu.
-- Vanilla's towing slices (ISVehicleMenu.lua:564-592, only called from the outside radial, :356) look for the other
-- vehicle within 6 squares of this one's square (ISVehicleTrailerUtils.lua:3-19); the trailer's centre sits 7.97-8.03
-- squares from the Semi's (proto RESULTS.md:49), so vanilla never offers the pair. Here: the other half from the cell's
-- vehicles, the engine's own test (canAttachTrailer: the two points within 1 m, BaseVehicle.java:10354-10391), then
-- vanilla's walk, timed action and "attachTrailer" command (VehicleCommands.lua:330-341). No command of our own.
-- Unhitching stays vanilla's: the first two branches of doTowingMenu take any towing pair.
-- Wrapped, not replaced: every other vehicle (another MOD's trailers too) gets exactly vanilla's slices.
require "Vehicles/ISUI/ISVehicleMenu"
require "Vehicles/ISVehicleTrailerUtils"
require "Vehicles/TimedActions/ISAttachTrailerToVehicle"
require "Vehicles/TimedActions/ISDetachTrailerFromVehicle"
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local SH = {}
T.SemiHitch = SH
SH.TRACTOR, SH.TRAILER = "Base.MinidoracatTesla_Semi", "Base.MinidoracatTesla_SemiTrailer"
SH.FIFTH_WHEEL, SH.KINGPIN = "mtsemi_fifthwheel", "mtsemi_kingpin"
-- the driver's radial (inside the cab): off until MP play shows both cars' authority right after the hitch
-- (BaseVehicle.java:10180-10195 constraintChanged, read only; impl-rulings.md 5)
SH.IN_CAR = false

-- as vanilla (ISVehicleMenu.lua:580-581): the server option only exists in MP
function SH.disabled()
    return isClient() and getServerOptions():getBoolean("DisableTrailerTowing")
end

-- the Semi and the trailer ready to hitch, from either one; nil when this is neither or no other half is in place.
-- IsoCell.vehicles is a HashSet (IsoCell.java:159,2732): no get(i), walk it with iterator() (HashSet and Iterator are
-- exposed, LuaManager.java:1709,1715). Runs once per menu opening.
function SH.pair(vehicle)
    local name = vehicle:getScriptName()
    local want = (name == SH.TRACTOR and SH.TRAILER) or (name == SH.TRAILER and SH.TRACTOR) or nil
    if not want then return nil end
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local o = it:next()
        if o ~= vehicle and o:getScriptName() == want then
            local a, b = vehicle, o
            if want == SH.TRACTOR then a, b = o, vehicle end
            if a:canAttachTrailer(b, SH.FIFTH_WHEEL, SH.KINGPIN) then return a, b end
        end
    end
end

-- Vanilla's action looks for the trailer again within 6 squares when it starts (ISAttachTrailerToVehicle.lua:42-48);
-- this one asks the engine about its own trailer
SH.Attach = ISAttachTrailerToVehicle:derive("MinidoracatTeslaSemiAttach")
function SH.Attach:attachTrailer()
    if self.vehicleA:canAttachTrailer(self.vehicleB, self.attachmentA, self.attachmentB) then
        sendClientCommand(self.character, "vehicle", "attachTrailer", { vehicleA = self.vehicleA:getId(),
            vehicleB = self.vehicleB:getId(), attachmentA = self.attachmentA, attachmentB = self.attachmentB })
    end
end

local function onAttach(player, a, b, seated)
    local action = SH.Attach:new(player, a, b, SH.FIFTH_WHEEL, SH.KINGPIN)
    if seated then ISTimedActionQueue.add(action) else ISVehicleTrailerUtils.walkToTrailer(player, a, SH.FIFTH_WHEEL, action) end
end

local function onDetach(player, a)
    ISTimedActionQueue.add(ISDetachTrailerFromVehicle:new(player, a, SH.FIFTH_WHEEL))
end

-- vanilla's slice text and icon (ISVehicleMenu.lua:557-561)
local function addAttach(player, vehicle, menu, seated)
    if SH.disabled() then return end
    local a, b = SH.pair(vehicle)
    if not a then return end
    menu:addSlice(getText("ContextMenu_Vehicle_AttachTrailer", ISVehicleMenu.getVehicleDisplayName(b),
        ISVehicleMenu.getVehicleDisplayName(a)), getTexture("media/ui/ZoomIn.png"), onAttach, player, a, b, seated)
end

local origTowing = ISVehicleMenu.doTowingMenu
function ISVehicleMenu.doTowingMenu(playerObj, vehicle, menu)
    origTowing(playerObj, vehicle, menu)
    if not vehicle:getVehicleTowing() and not vehicle:getVehicleTowedBy() then addAttach(playerObj, vehicle, menu, false) end
end

-- the driver's radial: vanilla has no towing slices there; the toggle and paused-game returns as HUDRadial.lua
local origRadial = ISVehicleMenu.showRadialMenu
function ISVehicleMenu.showRadialMenu(playerObj)
    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
    local wasOpen = menu:isReallyVisible()
    origRadial(playerObj)
    if not SH.IN_CAR or wasOpen then return end
    local sc = UIManager.getSpeedControls()
    if sc and sc:getCurrentGameSpeed() == 0 then return end
    local v = playerObj:getVehicle()
    if not v or v:getScriptName() ~= SH.TRACTOR or not v:isDriver(playerObj) then return end
    local towed = v:getVehicleTowing()
    if towed then
        menu:addSlice(getText("ContextMenu_Vehicle_DetachTrailer", ISVehicleMenu.getVehicleDisplayName(towed)),
            getTexture("media/ui/ZoomOut.png"), onDetach, playerObj, v)
    else
        addAttach(playerObj, v, menu, true)
    end
end
