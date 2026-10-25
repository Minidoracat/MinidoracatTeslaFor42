-- Model Y 3-D cabin and see-through glass (scripts/blender/skf/convert.py + cabin.py, models.md): no extra models. The body mesh
-- carries the cabin and the body's glass, each door / the tailgate its window; MinidoracatTesla_vehicle draws paint,
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
local tpl = read("scripts/vehicles/MinidoracatTesla_template.txt")
local models = read("scripts/models/MinidoracatTesla_vehicles.txt")

-- every Tesla model but the wheel on the merged shader; no cabin / glass / window models left
local shaders, names = {}, {}
for name, block in models:gmatch("model (MinidoracatTesla_ModelY[%w_]*)%s*(%b{})") do
    names[#names + 1] = name
    if name ~= "MinidoracatTesla_ModelY_Wheel" then
        shaders[#shaders + 1] = name .. "=" .. tostring(block:match("shader = ([%w_]+),"))
    end
end
local wrong = {}
for _, s in ipairs(shaders) do
    if not s:find("=MinidoracatTesla_vehicle$") then wrong[#wrong + 1] = s end
end
check(#shaders == 7 and #wrong == 0, "body, 4 doors, tailgate, frunk lid on MinidoracatTesla_vehicle (off: "
    .. table.concat(wrong, ",") .. ")")
check(#names == 8, "8 Model Y models, no cabin / glass / window models (" .. table.concat(names, ",") .. ")")
check(read("models_X/vehicles/MinidoracatTesla_ModelY_Cabin.fbx") == nil
    and read("models_X/vehicles/MinidoracatTesla_ModelY_Glass.fbx") == nil
    and read("textures/Vehicles/MinidoracatTesla_ModelY_cabin.png") == nil, "no cabin / glass FBX or cabin palette left")
check(veh:find("part GloveBox", 1, true) == nil and veh:find("part Window", 1, true) == nil
    and veh:find("part WindshieldRear", 1, true) == nil, "no models on GloveBox, Window* or WindshieldRear")
check((tpl:match("part TrunkDoor%s*(%b{})") or ""):find("requireUninstalled = WindshieldRear,", 1, true) ~= nil,
    "tailgate comes off only without its rear glass (in the tailgate's mesh)")
check((tpl:match("part WindshieldRear%s*(%b{})") or ""):find("requireInstalled = TrunkDoor,", 1, true) ~= nil,
    "rear glass goes on only with the tailgate")

-- door anim rate: one model per door, one player update a frame
local rates, bad = 0, {}
for door in pairs({ DoorFrontLeft = 1, DoorFrontRight = 1, DoorRearLeft = 1, DoorRearRight = 1, TrunkDoor = 1,
    EngineDoor = 1 }) do
    local p = veh:match("part " .. door .. "%s*(%b{})") or ""
    for r in p:gmatch("rate = ([%d%.]+),") do
        rates = rates + 1
        if r ~= "1.0" then bad[#bad + 1] = door .. "=" .. r end
    end
end
check(rates == 12 and #bad == 0, "door Open / Close rate 1.0 (" .. rates .. " rates, off: " .. table.concat(bad, ",") .. ")")

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
for id, block in veh:gmatch("passenger (%w+)%s*(%b{})") do
    seats = seats + 1
    if block:find("showPassenger = true", 1, true) then shown[#shown + 1] = id end
end
check(seats == 4 and #shown == 4, "all four seats show their passenger (" .. table.concat(shown, ",") .. ")")
