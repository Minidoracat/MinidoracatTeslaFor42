-- client/SemiHitch.lua: the Semi <-> 53 ft trailer slice in the outside radial (vanilla's doTowingMenu wrapped), the
-- server option DisableTrailerTowing, vanilla's command on the hitch, and the driver's radial behind SH.IN_CAR.
local H = H
local check = H.check

for _, m in ipairs({ "Vehicles/ISUI/ISVehicleMenu", "Vehicles/ISVehicleTrailerUtils", "Vehicles/TimedActions/ISAttachTrailerToVehicle",
    "Vehicles/TimedActions/ISDetachTrailerFromVehicle" }) do H.stub(m) end
local saved = { ISVehicleMenu, ISVehicleTrailerUtils, ISAttachTrailerToVehicle, ISDetachTrailerFromVehicle, ISTimedActionQueue,
    getCell, getServerOptions, getPlayerRadialMenu, UIManager, getTexture }

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
function getPlayerRadialMenu() return radial end
function getTexture(p) return { path = p } end
UIManager = { getSpeedControls = function() return { getCurrentGameSpeed = function() return 1 end } end }
local queue = {}
ISTimedActionQueue = { add = function(a) queue[#queue + 1] = a end }
local walked
ISVehicleTrailerUtils = { walkToTrailer = function(p, v, att, next) walked = { p = p, v = v, att = att }; queue[#queue + 1] = next; return true end }
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
ISDetachTrailerFromVehicle = action("ISDetachTrailerFromVehicle")
function ISDetachTrailerFromVehicle:new(character, v, att) return setmetatable({ character = character, vehicleA = v, attachmentA = att }, self) end
local option = false
function getServerOptions() return { getBoolean = function(_, k) return k == "DisableTrailerTowing" and option end } end

-- vehicles: canAttachTrailer as the engine for the pair it was told is in place (`hitchable`), names checked
local cars = {}
local hitchable = true
local nextId = 900
local function car(script)
    nextId = nextId + 1
    local v = { script = script, id = nextId }
    function v:getScriptName() return self.script end
    function v:getId() return self.id end
    function v:getVehicleTowing() return self.towing end
    function v:getVehicleTowedBy() return self.towedBy end
    function v:isDriver(p) return self.driver == p end
    function v:canAttachTrailer(b, attA, attB)
        return hitchable and self.script == "Base.MinidoracatTesla_Semi" and b.script == "Base.MinidoracatTesla_SemiTrailer"
            and attA == "mtsemi_fifthwheel" and attB == "mtsemi_kingpin"
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

H.section("Semi hitch: choosing the slice walks to the fifth wheel, then vanilla's attachTrailer command")
s = outside(semi)[2]
queue, walked = {}, nil
s.fn(table.unpack(s.args))
local act = queue[1]
check(walked and walked.v == semi and walked.att == "mtsemi_fifthwheel", "walks to the Semi's fifth wheel (vanilla walkToTrailer)")
check(act and getmetatable(act) == SH.Attach and act.vehicleB == trailer and act.attachmentB == "mtsemi_kingpin", "then our attach action")
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

H.section("Semi hitch: the driver's radial stays off (SH.IN_CAR)")
p.vehicle = semi
semi.driver = p
radial.open = false
ISVehicleMenu.showRadialMenu(p)
check(SH.IN_CAR == false and #radial.slices == 0, "default: no hitch slice inside the cab")
SH.IN_CAR = true
radial.open = false
ISVehicleMenu.showRadialMenu(p)
check(#radial.slices == 1 and radial.slices[1].args[4] == true, "switched on: the driver gets the attach slice")
queue, walked = {}, nil
radial.slices[1].fn(table.unpack(radial.slices[1].args))
check(walked == nil and getmetatable(queue[1]) == SH.Attach, "seated: the action straight away, no walk")
semi.towing = trailer
radial.open = false
ISVehicleMenu.showRadialMenu(p)
check(#radial.slices == 1 and radial.slices[1].text == "ContextMenu_Vehicle_DetachTrailer", "towing: the detach slice")
queue = {}
radial.slices[1].fn(table.unpack(radial.slices[1].args))
check(getmetatable(queue[1]) == ISDetachTrailerFromVehicle and queue[1].attachmentA == "mtsemi_fifthwheel", "detach: vanilla's action")
semi.towing, semi.driver = nil, nil
p.vehicle = trailer
radial.open = false
ISVehicleMenu.showRadialMenu(p)
check(#radial.slices == 0, "not the Semi's driver: nothing")
SH.IN_CAR = false

ISVehicleMenu, ISVehicleTrailerUtils, ISAttachTrailerToVehicle, ISDetachTrailerFromVehicle, ISTimedActionQueue,
    getCell, getServerOptions, getPlayerRadialMenu, UIManager, getTexture = table.unpack(saved, 1, 10)
