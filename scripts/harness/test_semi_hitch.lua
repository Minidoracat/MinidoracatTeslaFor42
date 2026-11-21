-- client/SemiHitch.lua: the Semi <-> 53 ft trailer slice in the outside radial (vanilla's doTowingMenu wrapped), the
-- server option DisableTrailerTowing, vanilla's command on the hitch, and the driver's radial inside the cab.
local H = H
local check = H.check

for _, m in ipairs({ "Vehicles/ISUI/ISVehicleMenu", "Vehicles/ISVehicleTrailerUtils", "Vehicles/TimedActions/ISAttachTrailerToVehicle",
    "Vehicles/TimedActions/ISDetachTrailerFromVehicle", "Vehicles/TimedActions/ISPathFindAction", "Definitions/ContainerButtonIcons" }) do
    H.stub(m)
end
local saved = { ISVehicleMenu, ISVehicleTrailerUtils, ISAttachTrailerToVehicle, ISDetachTrailerFromVehicle, ISTimedActionQueue,
    getCell, getServerOptions, getPlayerRadialMenu, UIManager, getTexture, ISVehicleMechanics, ISPathFindAction, Vector3f,
    ISBaseTimedAction }

-- vanilla fakes: doTowingMenu adds one "vanilla" slice (its own branches are vanilla's business), the radial a toggle
ISVehicleMenu = {}
function ISVehicleMenu.doTowingMenu(_, _, menu) menu:addSlice("vanilla") end
local radial = { slices = {}, open = false }
function radial:isReallyVisible() return self.open end
function radial:addSlice(text, tex, fn, ...) self.slices[#self.slices + 1] = { text = text, fn = fn, args = { ... } } end
function ISVehicleMenu.showRadialMenu()
    if radial.open then radial.open = false; return end
    radial.slices = {}; radial.open = true
end
function ISVehicleMenu.getVehicleDisplayName(v) return v.script end
local vanillaPick -- what vanilla's own pick finds; nil: no car in its reach
function ISVehicleMenu.getVehicleToInteractWith() return vanillaPick end
function getPlayerRadialMenu() return radial end
function getTexture(p) return { path = p } end
UIManager = { getSpeedControls = function() return { getCurrentGameSpeed = function() return 1 end } end }
local queue = {}
ISTimedActionQueue = { add = function(a) queue[#queue + 1] = a end }
-- vanilla's walk as it goes for the fifth wheel (semiA-hitch-2): its spot behind the hitch is inside the trailer,
-- getPlayerTrailerWorldPos is nil on both sides, so it says "no way to the trailer" and queues nothing; a car with
-- `vanillaClear` gets its walk and the next action (another car's hitch, the cheat)
local walked, fails = nil, 0
ISVehicleMechanics = { cheat = false }
ISVehicleTrailerUtils = {}
function ISVehicleTrailerUtils.onTrailerPathFail() fails = fails + 1 end
function ISVehicleTrailerUtils.walkToTrailer(p, v, att, next)
    walked = { p = p, v = v, att = att, vanilla = true }
    if not (v.vanillaClear or ISVehicleMechanics.cheat) then ISVehicleTrailerUtils.onTrailerPathFail(p); return false end
    queue[#queue + 1] = next
    return true
end
ISPathFindAction = { Type = "ISPathFindAction" }
function ISPathFindAction:pathToNearest(character, locations)
    return { Type = "ISPathFindAction", character = character, locations = locations,
        setOnFail = function(self, fn, arg) self.onFail, self.failArg = fn, arg end }
end
-- vanilla's walk for a vehicle with no hood (ISVehicleMenu.onMechanic, :1002-1005)
function ISPathFindAction:pathToVehicleAdjacent(character, vehicle) return { vanillaAdjacent = vehicle } end
Vector3f = { new = function()
    local v = { _x = 0, _y = 0, _z = 0 }
    function v:x() return self._x end
    function v:y() return self._y end
    function v:z() return self._z end
    return v
end }
local function action(name)
    local cls = { Type = name }
    cls.__index = cls
    function cls:derive(n) local c = setmetatable({ Type = n }, { __index = self }); c.__index = c; return c end
    return cls
end
ISAttachTrailerToVehicle = action("ISAttachTrailerToVehicle")
function ISAttachTrailerToVehicle:new(character, a, b, attA, attB)
    return setmetatable({ character = character, vehicleA = a, vehicleB = b, attachmentA = attA, attachmentB = attB }, self)
end
-- vanilla's fields (ISDetachTrailerFromVehicle.lua:51-61); its perform only counted here: the wrap must leave other
-- hitches to it
ISDetachTrailerFromVehicle = action("ISDetachTrailerFromVehicle")
function ISDetachTrailerFromVehicle:new(character, v, att)
    return setmetatable({ character = character, vehicle = v, attachment = att, hitchPos = Vector3f.new() }, self)
end
local vanillaDetached, baseDone = 0, 0
function ISDetachTrailerFromVehicle:perform() vanillaDetached = vanillaDetached + 1 end
function ISDetachTrailerFromVehicle:stopSound() end
ISBaseTimedAction = { perform = function() baseDone = baseDone + 1 end }
local option = false
function getServerOptions() return { getBoolean = function(_, k) return k == "DisableTrailerTowing" and option end } end

-- vehicles: canAttachTrailer as the engine for the pair it was told is in place (`hitchable`), names checked; a
-- position (x, y, level z) and heading `yaw` with the engine's local frame (x across, z along) for the stand spots;
-- each car's runtime box (extents and centre of mass x 1.82, the scripts) and the fifth wheel / kingpin
local cars = {}
local hitchable = true
local nextId = 900
local BOX = { ["Base.MinidoracatTesla_Semi"] = { 2.079, 6.492, -0.601 },
    ["Base.MinidoracatTesla_SemiTrailer"] = { 2.148, 13.343, 2.937 } }
local function car(script)
    nextId = nextId + 1
    local v = { script = script, id = nextId, x = 0, y = 0, z = 0, yaw = 0 }
    function v:getScriptName() return self.script end
    function v:getId() return self.id end
    function v:getZ() return self.z end
    function v:getVehicleTowing() return self.towing end
    function v:getVehicleTowedBy() return self.towedBy end
    function v:isDriver(p) return self.driver == p end
    function v:getCurrentSpeedKmHour() return self.kmh or 0 end
    function v:canAttachTrailer(b, attA, attB)
        return hitchable and self.script == "Base.MinidoracatTesla_Semi" and b.script == "Base.MinidoracatTesla_SemiTrailer"
            and attA == "mtsemi_fifthwheel" and attB == "mtsemi_kingpin"
    end
    local b = BOX[script] or { 1.8, 4.5, 0 }
    local ext, com = Vector3f.new(), Vector3f.new()
    ext._x, ext._y, ext._z, com._z = b[1], 1.5, b[2], b[3]
    function v:getScript() return { getExtents = function() return ext end, getCenterOfMassOffset = function() return com end } end
    function v:getWorldPos(lx, _, lz, w)
        local c, s = math.cos(self.yaw), math.sin(self.yaw)
        w._x, w._y, w._z = self.x + lx * c - lz * s, self.y + lx * s + lz * c, self.z
        return w
    end
    function v:getLocalPos(wx, wy, _, l)
        local c, s, dx, dy = math.cos(self.yaw), math.sin(self.yaw), wx - self.x, wy - self.y
        l._x, l._y, l._z = dx * c + dy * s, 0, -dx * s + dy * c
        return l
    end
    function v:getTowingLocalPos(att, l)
        if att ~= "mtsemi_fifthwheel" or self.script ~= "Base.MinidoracatTesla_Semi" then return nil end
        l._x, l._y, l._z = 0, 0, -2.4
        return l
    end
    cars[#cars + 1] = v
    return v
end
function getCell()
    return { getVehicles = function()
        return { iterator = function()
            local i = 0
            return { hasNext = function() return i < #cars end, next = function() i = i + 1; return cars[i] end }
        end }
    end }
end

H.require("MinidoracatTesla/SemiHitch")
local SH = MinidoracatTesla.SemiHitch
local p = H.player({})
local semi, trailer, my = car("Base.MinidoracatTesla_Semi"), car("Base.MinidoracatTesla_SemiTrailer"), car("Base.MinidoracatTesla_ModelY")
local van = car("Base.Van")
-- in place: the Semi at 100,100 heading 0.6 rad, the trailer behind it, its kingpin (0.76 m inside its nose: local z
-- 2.937 + 13.343 / 2 - 0.76 = 8.85) on the fifth wheel (the Semi's local z -2.4)
semi.x, semi.y, semi.yaw, trailer.yaw = 100, 100, 0.6, 0.6
do local w = semi:getWorldPos(0, 0, -2.4 - 8.85, Vector3f.new()); trailer.x, trailer.y = w._x, w._y end

local function outside(v)
    local m = { slices = {} }
    m.addSlice = radial.addSlice
    ISVehicleMenu.doTowingMenu(p, v, m)
    return m.slices
end

H.section("Semi hitch: the outside radial (vanilla's slices kept, one more for the pair)")
local s = outside(semi)
check(#s == 2 and s[1].text == "vanilla" and s[2].text == "ContextMenu_Vehicle_AttachTrailer" and s[2].args[2] == semi
    and s[2].args[3] == trailer, "at the Semi, hitched in place: vanilla's slices, then attach (Semi tows the trailer)")
s = outside(trailer)
check(#s == 2 and s[2].args[2] == semi and s[2].args[3] == trailer, "at the trailer: the same slice, the Semi still tows")
s = outside(my)
check(#s == 1 and s[1].text == "vanilla", "a Model Y: vanilla's slices only")
s = outside(van)
check(#s == 1, "a vanilla van: vanilla's slices only")
hitchable = false
check(#outside(semi) == 1, "the fifth wheel not under the kingpin (canAttachTrailer false): no slice")
hitchable = true
semi.towing = trailer
check(#outside(semi) == 1, "already towing: vanilla's own detach branch, no attach slice")
semi.towing = nil
trailer.towedBy = semi
check(#outside(trailer) == 1, "the trailer already towed: no attach slice")
trailer.towedBy = nil
-- the same place one floor apart (a parking deck): canAttachTrailer compares x and y only
trailer.z = 1
check(#outside(semi) == 1 and #outside(trailer) == 1, "the trailer on the floor above, right over the fifth wheel: no slice")
local n1 = #H.clientSent
SH.Attach:new(p, semi, trailer, "mtsemi_fifthwheel", "mtsemi_kingpin"):attachTrailer()
check(#H.clientSent == n1, "floors apart when the action starts: nothing sent")
trailer.z = 0

H.section("Semi hitch: server option DisableTrailerTowing (as vanilla, MP only)")
H.side(true, false)
option = true
check(#outside(semi) == 1 and #outside(trailer) == 1, "MP client, DisableTrailerTowing on: no hitch slice at either")
option = false
check(#outside(semi) == 2, "MP client, the option off: the slice")
H.side(false, false)
option = true
check(#outside(semi) == 2, "SP: no server options, the slice")
option = false
H.side(false, true)

H.section("Semi hitch: choosing the slice walks beside the fifth wheel, then vanilla's attachTrailer command")
s = outside(semi)[2]
queue, walked, fails = {}, nil, 0
s.fn(table.unpack(s.args))
local walk, act = queue[1], queue[2]
check(walked == nil and fails == 0 and walk and walk.Type == "ISPathFindAction" and walk.character == p
    and walk.onFail == ISVehicleTrailerUtils.onTrailerPathFail and walk.failArg == p,
    "vanilla's walk would find no way (its spot is inside the trailer): ours walks, 'no way' if the path fails")
check(act and getmetatable(act) == SH.Attach and act.vehicleB == trailer and act.attachmentB == "mtsemi_kingpin", "then our attach action")
-- each spot: on the Semi's level, clear of both boxes by 0.35, within 3.5 of the fifth wheel, one each side
local function spotsOk(locs, tr)
    local hitch = semi:getWorldPos(0, 0, -2.4, Vector3f.new())
    local ok, sides = #locs == 6, 0
    for i = 1, #locs, 3 do
        local x, y = locs[i], locs[i + 1]
        for _, v in ipairs({ semi, tr }) do
            local l, b = v:getLocalPos(x, y, 0, Vector3f.new()), BOX[v.script]
            ok = ok and (math.abs(l._x) > b[1] / 2 + 0.35 or math.abs(l._z - b[3]) > b[2] / 2 + 0.35)
        end
        local l = semi:getLocalPos(x, y, 0, Vector3f.new())
        sides = sides + (l._x > 0 and 1 or 2)
        ok = ok and locs[i + 2] == semi.z and math.sqrt((x - hitch._x) ^ 2 + (y - hitch._y) ^ 2) <= 3.5
            and math.abs(l._z + 2.4) < 1e-9
    end
    return ok and sides == 3
end
check(spotsOk(walk.locations, trailer), "two spots, either side of the fifth wheel: clear of the Semi and the trailer, within reach")
local n0 = #H.clientSent
act:attachTrailer()
local m = H.clientSent[#H.clientSent]
check(#H.clientSent == n0 + 1 and m.module == "vehicle" and m.command == "attachTrailer" and m.args.vehicleA == semi.id
    and m.args.vehicleB == trailer.id and m.args.attachmentA == "mtsemi_fifthwheel" and m.args.attachmentB == "mtsemi_kingpin",
    "attach: vanilla's command with the pair and both points (VehicleCommands.lua:330-341)")
hitchable = false
act:attachTrailer()
check(#H.clientSent == n0 + 1, "moved apart before the action starts: nothing sent")
hitchable = true

H.section("Semi hitch: unhitching from outside (vanilla's onDetachTrailer -> walkToTrailer)")
semi.towing, trailer.towedBy = trailer, semi
trailer.yaw = 0.6 + 0.35 -- swung 20 degrees about the kingpin
do
    local k = semi:getWorldPos(0, 0, -2.4, Vector3f.new())
    trailer.x, trailer.y = k._x + 8.85 * math.sin(trailer.yaw), k._y - 8.85 * math.cos(trailer.yaw)
end
queue, walked, fails = {}, nil, 0
local det = ISDetachTrailerFromVehicle:new(p, semi, "mtsemi_fifthwheel")
local okWalk = ISVehicleTrailerUtils.walkToTrailer(p, semi, "mtsemi_fifthwheel", det)
check(okWalk == true and walked == nil and fails == 0 and queue[1].Type == "ISPathFindAction" and queue[2] == det
    and spotsOk(queue[1].locations, trailer), "the trailer swung 20 degrees: walks to a clear spot beside the fifth wheel, then detaches")
trailer.yaw = 0.6
do local w = semi:getWorldPos(0, 0, -2.4 - 8.85, Vector3f.new()); trailer.x, trailer.y = w._x, w._y end

H.section("Semi hitch: every other walk stays vanilla's")
queue, walked, fails = {}, nil, 0
my.vanillaClear = true
ISVehicleTrailerUtils.walkToTrailer(p, my, "trailer", "next")
check(walked and walked.vanilla and walked.v == my and queue[1] == "next", "another car's hitch: vanilla's walk")
queue, walked = {}, nil
ISVehicleTrailerUtils.walkToTrailer(p, semi, "trailer", "next")
check(walked and walked.v == semi and fails == 1 and #queue == 0, "the Semi's rear hitch (not the fifth wheel): vanilla's walk")
queue, walked, fails = {}, nil, 0
ISVehicleMechanics.cheat = true
ISVehicleTrailerUtils.walkToTrailer(p, semi, "mtsemi_fifthwheel", "next")
check(walked and walked.vanilla and queue[1] == "next" and fails == 0, "ISVehicleMechanics.cheat: vanilla's (no walk at all)")
ISVehicleMechanics.cheat = false
-- nowhere clear within reach (a trailer three times as wide): 'no way to the trailer', nothing queued
queue, walked, fails = {}, nil, 0
local trailerScript = trailer.getScript
BOX["Base.MinidoracatTesla_SemiTrailer"][1] = 8
trailer.getScript = car("Base.MinidoracatTesla_SemiTrailer").getScript
cars[#cars] = nil
check(ISVehicleTrailerUtils.walkToTrailer(p, semi, "mtsemi_fifthwheel", det) == false and fails == 1 and #queue == 0
    and walked == nil, "no clear spot within 3.5 of the fifth wheel: 'no way to the trailer', nothing queued")
BOX["Base.MinidoracatTesla_SemiTrailer"][1], trailer.getScript = 2.148, trailerScript
semi.towing, trailer.towedBy = nil, nil

H.section("Semi hitch: the driver's radial")
p.vehicle = semi
semi.driver = p
radial.open = false
ISVehicleMenu.showRadialMenu(p)
check(#radial.slices == 1 and radial.slices[1].args[4] == true, "the driver gets the attach slice")
queue, walked = {}, nil
radial.slices[1].fn(table.unpack(radial.slices[1].args))
check(walked == nil and getmetatable(queue[1]) == SH.Attach, "seated: the action straight away, no walk")
semi.towing = trailer
radial.open = false
ISVehicleMenu.showRadialMenu(p)
check(#radial.slices == 1 and radial.slices[1].text == "ContextMenu_Vehicle_DetachTrailer", "towing: the detach slice")
queue = {}
radial.slices[1].fn(table.unpack(radial.slices[1].args))
local d = queue[1]
check(getmetatable(d) == ISDetachTrailerFromVehicle and d.attachment == "mtsemi_fifthwheel", "detach: vanilla's action")
-- vanilla's own check reads Manhattan distance on truncated coordinates and then does nothing (semiE-incar-3)
d.hitchPos._x, d.hitchPos._y = 100.9, 100.9
p.x, p.y = 103.35, 103.35 -- 3.47 straight; vanilla reads |100 - 103.35| * 2 = 6.7
local n2 = #H.clientSent
d:perform()
local m2 = H.clientSent[#H.clientSent]
check(#H.clientSent == n2 + 1 and m2.module == "vehicle" and m2.command == "detachTrailer" and m2.args.vehicle == semi.id
    and baseDone == 1 and vanillaDetached == 0, "seated, the Semi on a diagonal: detachTrailer sent, the action ends")
p.vehicle = nil
d:perform()
check(#H.clientSent == n2 + 2, "on foot 3.47 straight from the fifth wheel: sent")
p.x, p.y = 103.8, 103.8 -- 4.1 straight
d:perform()
check(#H.clientSent == n2 + 2 and baseDone == 3, "on foot past 4 straight: nothing sent, the action still ends")
p.vehicle = semi
d:perform()
check(#H.clientSent == n2 + 3, "back in the cab at the same spot: sent")
semi.kmh = -30
d:perform()
check(#H.clientSent == n2 + 3 and baseDone == 5, "seated, the Semi moving by the time the action ends: nothing sent")
ISDetachTrailerFromVehicle:new(p, my, "trailer"):perform()
ISDetachTrailerFromVehicle:new(p, semi, "trailer"):perform()
check(vanillaDetached == 2 and #H.clientSent == n2 + 3 and baseDone == 5, "another car's hitch, the Semi's rear hitch: vanilla's perform")
semi.driver = p
radial.open = false
ISVehicleMenu.showRadialMenu(p)
check(#radial.slices == 0, "the driver while moving: no hitch slices")
semi.kmh = -0.2 -- what the Semi reads standing (semiA-hitch-6)
radial.open = false
ISVehicleMenu.showRadialMenu(p)
check(#radial.slices == 1, "standing (-0.2 km/h): the detach slice")
semi.kmh = nil
semi.towing, semi.driver = nil, nil
p.vehicle = trailer
radial.open = false
ISVehicleMenu.showRadialMenu(p)
check(#radial.slices == 0, "not the Semi's driver: nothing")

H.section("Semi hitch: V on a stand spot (vanilla finds no car past the trailer's nose)")
p.vehicle, p.z = nil, 0
semi.towing, trailer.towedBy = trailer, semi
local spots = SH.standPoints(semi, trailer)
p.x, p.y = spots[1], spots[2]
vanillaPick = my
check(ISVehicleMenu.getVehicleToInteractWith(p) == my, "vanilla picked a car: that one")
vanillaPick = nil
check(ISVehicleMenu.getVehicleToInteractWith(p) == semi, "vanilla none, on a stand spot, the trailer hitched: the Semi")
semi.towing, trailer.towedBy = nil, nil
check(ISVehicleMenu.getVehicleToInteractWith(p) == semi, "unhitched, the kingpin still over the fifth wheel: the Semi")
hitchable = false
check(ISVehicleMenu.getVehicleToInteractWith(p) == nil, "no trailer at the fifth wheel (vanilla's line is clear there): vanilla's nil")
hitchable = true
p.z = 1
check(ISVehicleMenu.getVehicleToInteractWith(p) == nil, "on the floor above: nil")
p.z = 0
do local w = semi:getWorldPos(3.6, 0, -2.4, Vector3f.new()); p.x, p.y = w._x, w._y end
check(ISVehicleMenu.getVehicleToInteractWith(p) == nil, "3.6 from the fifth wheel (past the spots' reach): nil")
local semi2 = car("Base.MinidoracatTesla_Semi")
semi2.x, semi2.y, semi2.yaw, semi2.towing = semi.x + 3, semi.y, 0.6, trailer
do local w = semi2:getWorldPos(-1, 0, -2.4, Vector3f.new()); p.x, p.y = w._x, w._y end
check(ISVehicleMenu.getVehicleToInteractWith(p) == semi2, "two Semis in reach (2.2 and 1.0 from their fifth wheels): the nearer one")
cars[#cars] = nil

H.section("Semi hitch: Vehicle Mechanics on the trailer walks beside its origin (the window's reach)")
-- the window closes past 6 of the vehicle, Manhattan on the truncated origin (ISVehicleMechanics.lua:20-22,
-- IsoMovingObject.java:601-603): every spot inside that at any heading, 0.35 off either side of the box, on its floor
local function inReach(v)
    local locs = ISPathFindAction:pathToVehicleAdjacent(p, v).locations
    local ok, fx, fy = locs and #locs == 18, math.floor(v.x), math.floor(v.y)
    for i = 1, ok and #locs or 0, 3 do
        local x, y = locs[i], locs[i + 1]
        local l = v:getLocalPos(x, y, 0, Vector3f.new())
        ok = ok and locs[i + 2] == v.z and math.abs(math.abs(l._x) - (2.148 / 2 + 0.35)) < 1e-9
            and math.abs(x - fx) + math.abs(y - fy) < 6
    end
    return ok
end
local tx, ty, tyaw = trailer.x, trailer.y, trailer.yaw
local allIn = true
for _, yaw in ipairs({ 0, 0.6, math.pi / 4, 2.4, 3 * math.pi / 4 }) do
    for _, off in ipairs({ 0.01, 0.99 }) do
        trailer.x, trailer.y, trailer.yaw = 200 + off, 300 + off, yaw
        allIn = allIn and inReach(trailer)
    end
end
trailer.x, trailer.y, trailer.yaw = tx, ty, tyaw
check(allIn, "the trailer, five headings: six spots beside it, all within the window's reach")
check(ISPathFindAction:pathToVehicleAdjacent(p, my).vanillaAdjacent == my
    and ISPathFindAction:pathToVehicleAdjacent(p, semi).vanillaAdjacent == semi, "a Model Y, the Semi: vanilla's walk")

ISVehicleMenu, ISVehicleTrailerUtils, ISAttachTrailerToVehicle, ISDetachTrailerFromVehicle, ISTimedActionQueue,
    getCell, getServerOptions, getPlayerRadialMenu, UIManager, getTexture, ISVehicleMechanics, ISPathFindAction, Vector3f,
    ISBaseTimedAction = table.unpack(saved, 1, 14)
