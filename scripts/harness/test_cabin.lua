-- Model Y 3-D cabin and see-through glass (build.py stage cabin, models.md section 8): GloveBox draws Cabin then the
-- body's Glass, the door windows / rear glass are skinned models on the doors' child parts, part order puts every
-- glass model after the cabin and the doors, every seat shows its passenger.
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

local glove = veh:match("part GloveBox%s*(%b{})") or ""
local files = {}
for id, file in glove:gmatch("model (%w+)%s*{%s*file%s*=%s*([%w_]+)") do files[#files + 1] = id .. "=" .. file end
check(table.concat(files, ",") == "Cabin=MinidoracatTesla_ModelY_Cabin,Glass=MinidoracatTesla_ModelY_Glass",
    "GloveBox models in draw order cabin, glass (" .. table.concat(files, ",") .. ")")

local function model(name)
    return models:match("model MinidoracatTesla_ModelY_" .. name .. "%s*(%b{})") or ""
end
local cabin = model("Cabin")
check(cabin:find("shader = MinidoracatTesla_cabin,", 1, true) and cabin:find("static = true,", 1, true),
    "Cabin model: own shader, static (non-vehicle path gets the transform only when static, Model.java:591-597)")
local glass = model("Glass")
check(glass:find("shader = MinidoracatTesla_glass,", 1, true) and glass:find("static = true,", 1, true),
    "Glass model: glass shader, static")
for _, f in ipairs({ "MinidoracatTesla_ModelY_Cabin", "MinidoracatTesla_ModelY_Glass" }) do
    check(read("models_X/vehicles/" .. f .. ".fbx") ~= nil, f .. " FBX exists")
end
check(read("textures/Vehicles/MinidoracatTesla_ModelY_cabin.png") ~= nil, "cabin texture exists")

-- door glass: skinned meshes in the doors FBX, one model per Window / WindshieldRear part
local doorsFbx = read("models_X/vehicles/MinidoracatTesla_ModelY_Doors.fbx") or ""
local glassParts = { WindowFrontLeft = "DoorFrontLeft", WindowFrontRight = "DoorFrontRight",
    WindowRearLeft = "DoorRearLeft", WindowRearRight = "DoorRearRight", WindshieldRear = "TrunkDoor" }
for part, door in pairs(glassParts) do
    local m = model(part)
    check(m:find("mesh = vehicles/MinidoracatTesla_ModelY_Doors|" .. part .. ",", 1, true)
        and m:find("shader = MinidoracatTesla_glass,", 1, true) and m:find("static = false,", 1, true),
        part .. " model: doors FBX mesh, glass shader, skinned")
    check(doorsFbx:find(part, 1, true) ~= nil, part .. " mesh is in the doors FBX")
    local p = veh:match("part " .. part .. "%s*(%b{})") or ""
    check(p:find("file = MinidoracatTesla_ModelY_" .. part .. ",", 1, true) ~= nil, part .. " part shows its glass model")
    -- the window parts get their door parent from vanilla template Window; only the rear glass sets its own
    local parent = p:match("parent = (%w+),")
    if part == "WindshieldRear" then
        check(parent == door, "WindshieldRear is the tailgate's child (" .. tostring(parent) .. ")")
    else
        check(parent == nil, part .. " keeps vanilla's parent (no override)")
    end
end
check((tpl:match("part TrunkDoor%s*(%b{})") or ""):find("requireUninstalled = WindshieldRear,", 1, true) ~= nil,
    "tailgate comes off only without its rear glass")
check((tpl:match("part WindshieldRear%s*(%b{})") or ""):find("requireInstalled = TrunkDoor,", 1, true) ~= nil,
    "rear glass goes on only with the tailgate")

-- draw order: doors, then GloveBox, then every glass part
local order = {}
for name in tpl:gmatch("template = ([%w/]+),") do order[#order + 1] = name:match("([%w]+)$") end
local function at(name)
    for i, n in ipairs(order) do if n == name then return i end end
    return 0
end
check(at("DoorRearRight") > 0 and at("DoorRearRight") < at("GloveBox") and at("TrunkDoor") < at("GloveBox"),
    "doors and tailgate come before GloveBox")
for _, n in ipairs({ "WindshieldRear", "WindowFrontLeft", "WindowFrontRight", "WindowRearLeft", "WindowRearRight" }) do
    check(at(n) > at("GloveBox"), n .. " comes after GloveBox (glass over the cabin)")
end

-- door anim rate: the window model advances the door's player a second time each frame
local rates, bad = 0, {}
for door in pairs({ DoorFrontLeft = 1, DoorFrontRight = 1, DoorRearLeft = 1, DoorRearRight = 1, TrunkDoor = 1 }) do
    local p = veh:match("part " .. door .. "%s*(%b{})") or ""
    for r in p:gmatch("rate = ([%d%.]+),") do
        rates = rates + 1
        if r ~= "0.5" then bad[#bad + 1] = door .. "=" .. r end
    end
end
check(rates == 10 and #bad == 0, "door Open / Close rate 0.5 (" .. rates .. " rates, off: " .. table.concat(bad, ",") .. ")")

local frag = read("shaders/MinidoracatTesla_glass.frag") or ""
check(frag:find("texture2D%(TextureRust") ~= nil, "glass shader samples TextureRust (vehicle path, Shader.java:719-721)")
check(frag:find("discard") ~= nil and frag:find("TextureUninstall1") ~= nil, "glass shader discards removed / open panes")
check(frag:find("TextureReflection") == nil, "glass shader never samples the reflection maps (unbound without reflections)")
check(read("shaders/MinidoracatTesla_glass_static.vert") ~= nil, "static glass vertex shader exists (ShaderProgram.java:278-282)")
local skinned = read("shaders/MinidoracatTesla_glass.vert") or ""
check(skinned:find("MatrixPalette", 1, true) ~= nil, "skinned glass vertex shader exists and skins (door windows)")
local cfrag = read("shaders/MinidoracatTesla_cabin.frag") or ""
check(read("shaders/MinidoracatTesla_cabin_static.vert") ~= nil, "cabin static vertex shader exists")
check(cfrag ~= "" and cfrag:find("uniform%s+sampler2D%s+TextureRust") == nil,
    "cabin shader stays off the vehicle path (no TextureRust uniform)")

local shown, seats = {}, 0
for id, block in veh:gmatch("passenger (%w+)%s*(%b{})") do
    seats = seats + 1
    if block:find("showPassenger = true", 1, true) then shown[#shown + 1] = id end
end
check(seats == 4 and #shown == 4, "all four seats show their passenger (" .. table.concat(shown, ",") .. ")")
