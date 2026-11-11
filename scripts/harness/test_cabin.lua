-- Model Y 3-D cabin and see-through glass (scripts/blender/skf/convert.py + cabin.py, models.md): the body mesh
-- carries the cabin, each door / the tailgate its window, and the Glass model (part CabinGlass, drawn after every other
-- part model) every window: the body's and a closed copy of each door's; MinidoracatTesla_vehicle draws paint,
-- glass and cabin by UV1 class. Doors keep rate 1 (one AnimationPlayer update a frame), every seat shows its passenger.
local check = H.check
local media = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/"

local function read(p)
    local f = io.open(media .. p, "rb")
    if not f then return nil end
    local t = f:read("*a")
    f:close()
    return t
end

H.section("cabin and glass")
local veh = read("scripts/vehicles/MinidoracatTesla_ModelY.txt")
local geo = veh:sub((veh:find("---- geometry", 1, true))) -- the generated part (convert.py)
local tpl = read("scripts/vehicles/MinidoracatTesla_template.txt")
local models = read("scripts/models/MinidoracatTesla_vehicles.txt")

-- every Tesla model but the wheel and the Viewpoint detail on the merged shader; the cabin glass model, no cabin /
-- window models
for _, car in ipairs({ "MinidoracatTesla_ModelY", "MinidoracatTesla_Model3", "MinidoracatTesla_ModelS", "MinidoracatTesla_ModelX",
    "MinidoracatTesla_ModelYL" }) do
    local shaders, names = {}, {}
    for name, block in models:gmatch("model ([%w_]+)%s*(%b{})") do
        -- the car itself or car_<part> only: "MinidoracatTesla_ModelY" must not take the Model Y L's models
        if name == car or name:sub(1, #car + 1) == car .. "_" then
            names[#names + 1] = name
            if name ~= car .. "_Wheel" and name ~= car .. "_Detail" then
                shaders[#shaders + 1] = name .. "=" .. tostring(block:match("shader = ([%w_]+),"))
            end
        end
    end
    local wrong = {}
    for _, s in ipairs(shaders) do
        if not s:find("=MinidoracatTesla_vehicle$") then wrong[#wrong + 1] = s end
    end
    check(#shaders == 8 and #wrong == 0, car .. ": body, glass, 4 doors, rear lid, frunk lid on MinidoracatTesla_vehicle (off: "
        .. table.concat(wrong, ",") .. ")")
    check(#names == 10, car .. ": 10 models, the cabin glass and the Viewpoint detail but no cabin / window models ("
        .. table.concat(names, ",") .. ")")
    check(read("models_X/vehicles/" .. car .. "_Cabin.fbx") == nil and read("models_X/vehicles/" .. car .. "_Glass.fbx") ~= nil
        and read("textures/Vehicles/" .. car .. "_cabin.png") == nil, car .. ": the glass FBX, no cabin FBX or cabin palette")
    local block = models:match("model " .. car .. "_Glass%s*(%b{})") or ""
    check(block:find("static = true,", 1, true) and block:find("mesh = vehicles/" .. car .. "_Glass,", 1, true) ~= nil,
        car .. ": the glass model is static, its own FBX")
end
-- the Cybertruck's model list is its own (test_truck); its cabin glass is the same kind
local ctGlass = models:match("model MinidoracatTesla_Cybertruck_Glass%s*(%b{})") or ""
check(ctGlass:find("static = true,", 1, true) and ctGlass:find("mesh = vehicles/MinidoracatTesla_Cybertruck_Glass,", 1, true)
    and read("models_X/vehicles/MinidoracatTesla_Cybertruck_Glass.fbx") ~= nil, "Cybertruck: the glass model is static, its own FBX")
local m3 = read("scripts/vehicles/MinidoracatTesla_Model3.txt")
local ms = read("scripts/vehicles/MinidoracatTesla_ModelS.txt")
local mx = read("scripts/vehicles/MinidoracatTesla_ModelX.txt")
local ct = read("scripts/vehicles/MinidoracatTesla_Cybertruck.txt")
local yl = read("scripts/vehicles/MinidoracatTesla_ModelYL.txt")
local geos = { ModelY = geo, Model3 = m3:sub((m3:find("---- geometry", 1, true))),
    ModelS = ms:sub((ms:find("---- geometry", 1, true))),
    ModelX = mx:sub((mx:find("---- geometry", 1, true))),
    Cybertruck = ct:sub((ct:find("---- geometry", 1, true))),
    ModelYL = yl:sub((yl:find("---- geometry (TeslaModelYL)", 1, true))) }
for car, g in pairs(geos) do
    check(g:find("part GloveBox", 1, true) == nil and g:find("part Window", 1, true) == nil
        and g:find("part WindshieldRear", 1, true) == nil, car .. ": no models on GloveBox, Window* or WindshieldRear")
    local cg = g:match("part CabinGlass%s*(%b{})") or ""
    check(cg:find("model Glass", 1, true) and cg:find("file = MinidoracatTesla_" .. car .. "_Glass,", 1, true) ~= nil,
        car .. ": part CabinGlass shows the car's glass model")
    -- the cabin detail under Viewpoint (ViewpointCabin.lua): Viewpoint draws it with its texture (a part model whose
    -- shader is not a vehicle shader), the game's shader draws nothing, so the isometric view does not change
    local cd = g:match("part CabinDetail%s*(%b{})") or ""
    local m = models:match("model MinidoracatTesla_" .. car .. "_Detail%s*(%b{})") or ""
    check(cd:find("model Detail", 1, true) and cd:find("file = MinidoracatTesla_" .. car .. "_Detail,", 1, true)
        and m:find("shader = MinidoracatTesla_viewpoint,", 1, true) and m:find("static = true,", 1, true)
        and m:find("texture = Vehicles/MinidoracatTesla_Detail,", 1, true)
        and m:find("mesh = vehicles/MinidoracatTesla_" .. car .. "_Detail,", 1, true)
        and read("models_X/vehicles/MinidoracatTesla_" .. car .. "_Detail.fbx") ~= nil,
        car .. ": part CabinDetail shows its own static FBX on MinidoracatTesla_viewpoint with the detail texture")
end
check(read("textures/Vehicles/MinidoracatTesla_Detail.png") ~= nil, "the detail texture is there")
-- the cabin glass part: no item, so the engine must not tie its model to one (setAllModelsVisible, VehiclePart.java:
-- 148-155); its init shows the model once every part has its item (Liftgate.lua). The detail part: the same, shown by
-- ViewpointCabin.lua alone
local cgt = tpl:match("part CabinGlass%s*(%b{})") or ""
check(cgt:find("setAllModelsVisible = false,", 1, true) and cgt:find("category = nodisplay,", 1, true)
    and cgt:find("init = MinidoracatTesla.Init.CabinGlass,", 1, true) ~= nil,
    "template part CabinGlass: nodisplay, setAllModelsVisible false, init MinidoracatTesla.Init.CabinGlass")
local cdt = tpl:match("part CabinDetail%s*(%b{})") or ""
check(cdt:find("setAllModelsVisible = false,", 1, true) and cdt:find("category = nodisplay,", 1, true)
    and not cdt:find("init", 1, true), "template part CabinDetail: nodisplay, setAllModelsVisible false, no init")

-- rear lid rules: the hatchback's rear glass rides in its liftgate, the sedan's in the body. Per car script (TeslaLogic,
-- above the geometry mark); part tables merge with the template's (VehicleScript.java:973-981).
local function rules(text, part)
    local s = ""
    for block in text:sub(1, (text:find("---- geometry", 1, true))):gmatch("part " .. part .. "%s*(%b{})") do s = s .. block end
    return s
end
check(rules(veh, "TrunkDoor"):find("requireUninstalled = WindshieldRear,", 1, true) ~= nil,
    "Model Y: liftgate comes off only without its rear glass (in the liftgate's mesh)")
check(rules(veh, "WindshieldRear"):find("requireInstalled = TrunkDoor,", 1, true) ~= nil,
    "Model Y: rear glass goes on only with the liftgate")
check(rules(ms, "TrunkDoor"):find("requireUninstalled = WindshieldRear,", 1, true) ~= nil
    and rules(ms, "WindshieldRear"):find("requireInstalled = TrunkDoor,", 1, true) ~= nil,
    "Model S: a liftback like the Model Y: the rear glass rides in the liftgate (off first, on only with it)")
check(rules(mx, "TrunkDoor"):find("requireUninstalled = WindshieldRear,", 1, true) ~= nil
    and rules(mx, "WindshieldRear"):find("requireInstalled = TrunkDoor,", 1, true) ~= nil,
    "Model X: the liftgate carries its rear glass like the Model Y's")
check(rules(yl, "TrunkDoor"):find("requireUninstalled = WindshieldRear,", 1, true) ~= nil
    and rules(yl, "WindshieldRear"):find("requireInstalled = TrunkDoor,", 1, true) ~= nil,
    "Model Y L: the liftgate carries its rear glass like the Model Y's")
check(not (tpl .. m3):find("requireUninstalled = WindshieldRear", 1, true) and not (tpl .. m3):find("requireInstalled = TrunkDoor", 1, true),
    "Model 3 (and the shared template): trunk lid and rear glass come off and go on independently (glass in the body)")

-- door anim rate: one model per door, one player update a frame
for car, g in pairs(geos) do
    local rates, bad = 0, {}
    for door in pairs({ DoorFrontLeft = 1, DoorFrontRight = 1, DoorRearLeft = 1, DoorRearRight = 1, TrunkDoor = 1,
        EngineDoor = 1 }) do
        local p = g:match("part " .. door .. "%s*(%b{})") or ""
        for r in p:gmatch("rate = ([%d%.]+),") do
            rates = rates + 1
            if r ~= "1.0" then bad[#bad + 1] = door .. "=" .. r end
        end
    end
    check(rates == 12 and #bad == 0, car .. ": door Open / Close rate 1.0 (" .. rates .. " rates, off: "
        .. table.concat(bad, ",") .. ")")
end

local frag = read("shaders/MinidoracatTesla_vehicle.frag") or ""
check(frag:find("texture2D%(TextureRust") ~= nil, "shader samples TextureRust (vehicle path, Shader.java:719-721)")
check(frag:find("discard") ~= nil and frag:find("TextureUninstall1") ~= nil, "glass discards removed / open / smashed panes")
check(frag:find("noDamage = 1.0 - texen2[2][0]", 1, true) ~= nil, "roof glass (LightBar L) takes no damage shell")
check(frag:find("reflectionsOn*ref_en", 1, true) ~= nil and frag:find("reflectionsOn*(1.0-ref_en)", 1, true) ~= nil,
    "both reflection terms scale by reflectionsOn (0 = vehicle_multiuv_noreflect)")
local cells = 0
for _ in (frag:match("const vec3 CABIN%[%d+%] = vec3%[%d+%]%((.-)%);") or ""):gmatch("vec3%(") do cells = cells + 1 end
check(cells == 10, "cabin palette has pzveh.py's 10 CABIN_CELLS (" .. cells .. ")")
for _, v in ipairs({ "MinidoracatTesla_vehicle_static.vert", "MinidoracatTesla_vehicle.vert" }) do
    local src = read("shaders/" .. v) or ""
    check(src:find("textureSize(TextureReflectionA, 0).x > 1", 1, true) ~= nil and src:find("#if __VERSION__ >= 130", 1, true) ~= nil,
        v .. " reports reflectionsOn, guarded for GL 2.1's #version 120")
end
check((read("shaders/MinidoracatTesla_vehicle.vert") or ""):find("MatrixPalette", 1, true) ~= nil, "skinned vertex shader skins")
check(read("shaders/vehicle_multiuv.vert") == nil, "no vehicle_multiuv.vert override left")

local shown, seats = {}, 0
for id, block in geo:gmatch("passenger (%w+)%s*(%b{})") do
    seats = seats + 1
    if block:find("showPassenger = true", 1, true) then shown[#shown + 1] = id end
end
check(seats == 4 and #shown == 4, "all four seats show their passenger (" .. table.concat(shown, ",") .. ")")

-- Six seats (template PassengerSeat6): the Model X and the Model Y L. The 2nd row (Middle*) gets in through the rear
-- doors (DoorRear*: the Model X's falcon wings, the Model Y L's ordinary doors); the 3rd row (Rear*) has its own way in
-- at the 2nd row's spot through the same doors, so a full 2nd row never blocks it (plan-sx-1031 engine-feasibility
-- 2.2 B; plan-yl-1111 engine-feasibility 1.2).
for _, pair in ipairs({ { "ModelX", mx }, { "ModelYL", yl } }) do
    local car, text = pair[1], pair[2]
    H.section(car .. " six seats")
    local gx = geos[car]
    check(text:find("\n        seats = 6,", 1, true) ~= nil and gx:find("template = PassengerSeat6,", 1, true) ~= nil
        and text:find("template = Seat/part/SeatMiddleLeft,", 1, true) ~= nil
        and text:find("template = Seat/part/SeatMiddleRight,", 1, true) ~= nil, "seats = 6, PassengerSeat6, SeatMiddleLeft / Right parts")
    local pas, n6 = {}, 0
    for nm, block in gx:gmatch("passenger (%w+)%s*(%b{})") do
        pas[nm], n6 = block, n6 + 1
    end
    check(n6 == 6, "six passengers in the geometry block (" .. n6 .. ")")
    local function outside(nm) return (pas[nm] or ""):match("position outside%s*(%b{})") or "" end
    for _, s in ipairs({ "Left", "Right" }) do
        local mid, rear = outside("Middle" .. s), outside("Rear" .. s)
        check((pas["Middle" .. s] or ""):find("door = DoorRear" .. s .. ",", 1, true) ~= nil
            and mid:match("area = (%w+),") == "SeatMiddle" .. s, "2nd row " .. s .. ": through DoorRear" .. s .. ", outside at SeatMiddle" .. s)
        check(rear:match("area = (%w+),") == "SeatMiddle" .. s and rear:match("offset = ([^,]+),") ~= nil
            and rear:match("offset = ([^,]+),") == mid:match("offset = ([^,]+),"),
            "3rd row " .. s .. ": its own way in, at the 2nd row's spot (" .. tostring(rear:match("offset = ([^,]+),")) .. ")")
        check(gx:find("area SeatMiddle" .. s, 1, true) ~= nil and gx:find("area SeatRear" .. s, 1, true) ~= nil,
            "areas SeatMiddle" .. s .. " / SeatRear" .. s)
    end
end
-- falcon wing doors whine like vanilla's power window (sounds on the car script's anims, the anims in the geometry)
local falcon = rules(mx, "DoorRear%*")
check(falcon:find("sound = MinidoracatTesla_FalconOpen,", 1, true) ~= nil
    and falcon:find("sound = MinidoracatTesla_FalconClose,", 1, true) ~= nil, "falcon wing doors: power window sounds (raised: MinidoracatTesla_Falcon*)")
check(not yl:find("MinidoracatTesla_Falcon", 1, true), "Model Y L: ordinary rear doors, vanilla door sounds (no falcon wing sound)")
check(geo:find("template = PassengerSeat4,", 1, true) ~= nil and geos.Model3:find("template = PassengerSeat4,", 1, true) ~= nil,
    "Model Y / Model 3 keep PassengerSeat4")
-- the clip lengths the shell and the climb wait on (Core.lua Specs doorClip) are the build's (cars/model_x.py DOORS)
local cfg = assert(io.open("scripts/blender/skf/cars/model_x.py", "r")):read("*a")
local function clip(part) return tonumber((cfg:match('"' .. part .. '": (%b())') or ""):match("([%d.]+)%)$")) end
local SX = MinidoracatTesla.Specs["Base.MinidoracatTesla_ModelX"]
check(SX.doorClip.TrunkDoor == clip("TrunkDoor") and SX.doorClip.DoorRearLeft == clip("DoorRearLeft")
    and SX.doorClip.DoorRearRight == clip("DoorRearRight") and SX.doorWait.DoorRearLeft < SX.doorClip.DoorRearLeft,
    "Model X Specs doorClip = the build's clips (" .. tostring(clip("TrunkDoor")) .. ", " .. tostring(clip("DoorRearLeft"))
    .. "), the climb waits less than the wing's clip")
