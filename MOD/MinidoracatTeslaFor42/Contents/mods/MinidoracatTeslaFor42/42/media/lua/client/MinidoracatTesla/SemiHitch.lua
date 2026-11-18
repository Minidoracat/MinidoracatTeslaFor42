-- Tesla Semi and its 53 ft trailer: the hitch slice in the vehicle radial menu.
-- Vanilla's towing slices (ISVehicleMenu.lua:564-592, only called from the outside radial, :356) look for the other
-- vehicle within 6 squares of this one's square (ISVehicleTrailerUtils.lua:3-19); the trailer's centre sits 7.97-8.03
-- squares from the Semi's (proto RESULTS.md:49), so vanilla never offers the pair. Here: the other half from the cell's
-- vehicles, the engine's own test (canAttachTrailer: the two points within 1 m, BaseVehicle.java:10354-10391), then
-- vanilla's walk, timed action and "attachTrailer" command (VehicleCommands.lua:330-341). No command of our own.
-- Unhitching stays vanilla's: the first two branches of doTowingMenu take any towing pair. Both walk through
-- ISVehicleTrailerUtils.walkToTrailer (onDetachTrailer too, ISVehicleMenu.lua:1738-1741), wrapped below for the fifth
-- wheel only: vanilla's spot behind it is inside the trailer. So is the detach action's distance check (SH.NEAR).
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
-- as vanilla (ISVehicleMenu.lua:580-581): the server option only exists in MP
function SH.disabled()
    return isClient() and getServerOptions():getBoolean("DisableTrailerTowing")
end

-- the Semi and the trailer ready to hitch, from either one; nil when this is neither or no other half is in place.
-- IsoCell.vehicles is a HashSet (IsoCell.java:159,2732): no get(i), walk it with iterator() (HashSet and Iterator are
-- exposed, LuaManager.java:1709,1715). Runs once per menu opening. Same floor only: canAttachTrailer compares x and y
-- alone (BaseVehicle.java:10354-10391); vanilla looks on the vehicle's own level (ISVehicleTrailerUtils.lua:3-10).
local function level(v) return math.floor(v:getZ()) end
function SH.pair(vehicle)
    local name = vehicle:getScriptName()
    local want = (name == SH.TRACTOR and SH.TRAILER) or (name == SH.TRAILER and SH.TRACTOR) or nil
    if not want then return nil end
    local z = level(vehicle)
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local o = it:next()
        if o ~= vehicle and o:getScriptName() == want and level(o) == z then
            local a, b = vehicle, o
            if want == SH.TRACTOR then a, b = o, vehicle end
            if a:canAttachTrailer(b, SH.FIFTH_WHEEL, SH.KINGPIN) then return a, b end
        end
    end
end

-- Where the player stands to work the fifth wheel. Vanilla's spot is 0.35 past the towing car's box behind its hitch
-- (getPlayerTrailerLocalPos, BaseVehicle.java:10031-10045), and walkToTrailer drops it when that spot is not clear
-- (getPlayerTrailerWorldPos :10047-10058: lineClearCollide, whose end must not be in another car's polyPlusRadius,
-- LineClearCollideMain.java:213-219). The fifth wheel is under the trailer's nose: that spot is inside the trailer, so
-- vanilla finds no way to it, hitching or unhitching (semiA-hitch-2). Here: beside the fifth wheel, across the Semi,
-- each side stepping out until clear of the trailer's box by the same 0.35 (its polyPlusRadius is the box plus 0.15,
-- VehiclePoly.java:52-66, BaseVehicle.java:4224), within SH.REACH of the hitch (the detach action does nothing past
-- 4, ISDetachTrailerFromVehicle.lua:34). A flat list x, y, z per spot for ISPathFindAction:pathToNearest; nil: none.
SH.CLEAR, SH.STEP, SH.REACH = 0.35, 0.25, 3.5
local function clearOf(v, x, y)
    local l = v:getLocalPos(x, y, 0, Vector3f.new())
    local s = v:getScript()
    local e, c = s:getExtents(), s:getCenterOfMassOffset()
    return math.abs(l:x() - c:x()) > e:x() / 2 + SH.CLEAR or math.abs(l:z() - c:z()) > e:z() / 2 + SH.CLEAR
end
function SH.standPoints(semi, trailer)
    local hitch = semi:getTowingLocalPos(SH.FIFTH_WHEEL, Vector3f.new())
    if not hitch then return nil end
    local s = semi:getScript()
    local half = s:getExtents():x() / 2 + SH.CLEAR
    local cx, z = s:getCenterOfMassOffset():x(), level(semi)
    local out, w = {}, Vector3f.new()
    for side = 1, -1, -2 do -- local +x first: vanilla's "left"
        local x = cx + side * half
        while math.abs(x - hitch:x()) <= SH.REACH do
            semi:getWorldPos(x, 0, hitch:z(), w)
            if not trailer or clearOf(trailer, w:x(), w:y()) then
                out[#out + 1] = w:x(); out[#out + 1] = w:y(); out[#out + 1] = z
                break
            end
            x = x + side * SH.STEP
        end
    end
    if #out > 0 then return out end
end

-- vanilla's walk (ISVehicleTrailerUtils.lua:27-61) for every other car and hitch and for ISVehicleMechanics.cheat; for
-- the fifth wheel its own steps with our spots (and the fail callback vanilla meant: it names
-- ISVehicleMenu.onTrailerPathFail, which does not exist)
local origWalk = ISVehicleTrailerUtils.walkToTrailer
function ISVehicleTrailerUtils.walkToTrailer(playerObj, vehicle, attachment, nextAction)
    if ISVehicleMechanics.cheat or attachment ~= SH.FIFTH_WHEEL or vehicle:getScriptName() ~= SH.TRACTOR then
        return origWalk(playerObj, vehicle, attachment, nextAction)
    end
    local spots = SH.standPoints(vehicle, vehicle:getVehicleTowing() or nextAction and nextAction.vehicleB)
    if not spots then
        ISVehicleTrailerUtils.onTrailerPathFail(playerObj)
        return false
    end
    local action = ISPathFindAction:pathToNearest(playerObj, spots)
    action:setOnFail(ISVehicleTrailerUtils.onTrailerPathFail, playerObj)
    ISTimedActionQueue.add(action)
    if nextAction then ISTimedActionQueue.add(nextAction) end
    return true
end

-- Vanilla's action looks for the trailer again within 6 squares when it starts (ISAttachTrailerToVehicle.lua:42-48);
-- this one asks the engine about its own trailer, on the same floor (SH.pair)
SH.Attach = ISAttachTrailerToVehicle:derive("MinidoracatTeslaSemiAttach")
function SH.Attach:attachTrailer()
    local a, b = self.vehicleA, self.vehicleB
    if level(a) == level(b) and a:canAttachTrailer(b, self.attachmentA, self.attachmentB) then
        sendClientCommand(self.character, "vehicle", "attachTrailer", { vehicleA = a:getId(),
            vehicleB = b:getId(), attachmentA = self.attachmentA, attachmentB = self.attachmentB })
    end
end

-- Vanilla's detach gives up, silently, past 4 of the hitch, measured with DistTo(x, y): the int overload, Manhattan
-- on truncated coordinates (ISDetachTrailerFromVehicle.lua:34, IsoMovingObject.java:601-603). With the Semi on a
-- diagonal the driver's seat (3.47 straight) reads about 5 (semiE-incar-3), and a stand spot SH.REACH out can too.
-- For the fifth wheel: anyone in this Semi's cab once it stands (T.stopped: the slice may have been picked before it
-- moved off, and nothing stops a seated action), or the same 4 measured straight. Every other hitch: vanilla's.
SH.NEAR = 4
local origDetach = ISDetachTrailerFromVehicle.perform
function ISDetachTrailerFromVehicle:perform()
    local v, c, h = self.vehicle, self.character, self.hitchPos
    if self.attachment ~= SH.FIFTH_WHEEL or v:getScriptName() ~= SH.TRACTOR then return origDetach(self) end
    self:stopSound()
    local dx, dy = c:getX() - h:x(), c:getY() - h:y()
    local seated = c:getVehicle() == v
    if seated and T.stopped(v) or not seated and dx * dx + dy * dy <= SH.NEAR * SH.NEAR then
        sendClientCommand(c, "vehicle", "detachTrailer", { vehicle = v:getId() })
    end
    ISBaseTimedAction.perform(self)
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

-- On a stand spot with the trailer on (or still over the fifth wheel), V finds no car and toggles the UI instead
-- (ISUIHandler.lua:43-53): getNearVehicle wants a clear line from the player to where he faces the Semi, and the
-- trailer's nose (its box plus 0.15) lies across it (IsoPlayer.java:4302-4330; semiB-ssp-EN, semiF-ssp1
-- `vehicle=nil`). Vanilla's pick first; with none, the nearest Semi on this floor with a trailer at its fifth wheel
-- and the player within the spots' reach of it. One pass over the cell's cars per key released on foot away from
-- any car vanilla can pick (ISVehicleMenu.lua:1652).
local origPick = ISVehicleMenu.getVehicleToInteractWith
local hitchW
function ISVehicleMenu.getVehicleToInteractWith(playerObj)
    local v = origPick(playerObj)
    if v then return v end
    local px, py, z = playerObj:getX(), playerObj:getY(), math.floor(playerObj:getZ())
    local best = SH.REACH * SH.REACH
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local o = it:next()
        if o:getScriptName() == SH.TRACTOR and level(o) == z then
            hitchW = hitchW or Vector3f.new()
            local h = o:getTowingLocalPos(SH.FIFTH_WHEEL, hitchW)
            if h then
                o:getWorldPos(h:x(), 0, h:z(), h)
                local dx, dy = h:x() - px, h:y() - py
                local d = dx * dx + dy * dy
                if d <= best and (o:getVehicleTowing() or SH.pair(o)) then v, best = o, d end
            end
        end
    end
    return v
end

-- the driver's radial: vanilla has no towing slices there; the toggle and paused-game returns as HUDRadial.lua.
-- Seated works: MP play gave the driver both cars' authority after the hitch (semiE-incar-1); the detach from the
-- seat goes through the wrapped perform above. Standing still only, like every Park-only action (T.stopped): vanilla
-- unhitches from outside, and a 53 ft trailer let go at speed is a weapon.
local origRadial = ISVehicleMenu.showRadialMenu
function ISVehicleMenu.showRadialMenu(playerObj)
    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
    local wasOpen = menu:isReallyVisible()
    origRadial(playerObj)
    if wasOpen then return end
    local sc = UIManager.getSpeedControls()
    if sc and sc:getCurrentGameSpeed() == 0 then return end
    local v = playerObj:getVehicle()
    if not v or v:getScriptName() ~= SH.TRACTOR or not v:isDriver(playerObj) or not T.stopped(v) then return end
    local towed = v:getVehicleTowing()
    if towed then
        menu:addSlice(getText("ContextMenu_Vehicle_DetachTrailer", ISVehicleMenu.getVehicleDisplayName(towed)),
            getTexture("media/ui/ZoomOut.png"), onDetach, playerObj, v)
    else
        addAttach(playerObj, v, menu, true)
    end
end
