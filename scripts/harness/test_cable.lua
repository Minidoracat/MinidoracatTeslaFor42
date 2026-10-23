-- Charge cable (client/MinidoracatTesla/Cable.lua): hooks only while plugged, endpoints line up, 2D fallback.
local check = H.check
local saved = {}
for _, k in ipairs({ "Render3DItem", "renderIsoLine", "instanceItem", "Vector3f", "getCore", "getSpecificPlayer", "getCell" }) do
    saved[k] = _G[k] or false
end

-- ---- fakes: render calls, items, vectors, core option, cell, player ----
local draws, lines2d = {}, {}
function Render3DItem(item, sq, x, y, z, a) draws[#draws + 1] = { item = item, x = x, y = y, z = z, a = a, s = item.scale } end
function renderIsoLine(x, y, z, tx, ty, tz) lines2d[#lines2d + 1] = { x, y, z, tx, ty, tz } end
function instanceItem(t) return { type = t, scale = 1, setWorldScale = function(self, s) self.scale = s end } end
Vector3f = { new = function()
    local v = { 0, 0, 0 }
    function v:set(a, b, c) self[1], self[2], self[3] = a, b, c; return self end
    function v:x() return self[1] end
    function v:y() return self[2] end
    function v:z() return self[3] end
    return v
end }
local opt3d = true
function getCore() return { isOption3DGroundItem = function() return opt3d end } end
local player = H.player({ x = 10, y = 22 })
function getSpecificPlayer(i) return i == 0 and player or nil end
local ramp = {}             -- "x,y" -> apparent height above the level (vanilla ramps_01 squares)
local function sqFake(x, y, z)
    return { x = x, y = y, z = z, getApparentZ = function(self) return self.z + (ramp[self.x .. "," .. self.y] or 0) end }
end
function getCell() return { getGridSquare = function(_, x, y, z) return sqFake(x, y, z) end } end

local ok = pcall(H.require, "MinidoracatTesla/Chargers")
local T = MinidoracatTesla
if ok and T.Chargers and T.Chargers.WallConnector then
    local ex = T.Chargers.WallConnector.cableExit
    check(ex and ex[1] == 0 and H.near(ex[2], -0.40) and H.near(ex[3], 0.327),
        "cable: Chargers.WallConnector.cableExit = { 0, -0.40, 0.327 } (matches props_blender.py EXIT_Y / EXIT_Z)")
else
    T.Chargers = T.Chargers or {}
    T.Chargers.WallConnector = { cableExit = { 0, -0.40, 0.327 } }   -- Chargers.lua not written yet (TeslaLogic)
end
H.require("MinidoracatTesla/Cable")
local C = T.Cable

-- car: yaw only; local x = right flank (+x), local z = forward. chargeport local (0.4615, 0, -0.6264) like Model Y
local function car(x, y, yaw)
    local v = H.vehicle({ x = x, y = y })
    local c, s = math.cos(yaw), math.sin(yaw)
    function v:getAttachmentLocalPos(name, out) if name ~= "chargeport" then return nil end return out:set(0.4615, 0.0, -0.6264) end
    function v:getWorldPos(lx, ly, lz, out) return out:set(self.x + lx * c - lz * s, self.y + lx * s + lz * c, self.z + ly) end
    return v
end

local function frame()
    draws, lines2d = {}, {}
    H.fire("RenderOpaqueObjectsInWorld", 0, 0, 0, 0, nil)
    H.fire("OnPostRender")
end

-- ---- idle: nothing hooked, nothing drawn ----
check(C.count() == 0 and H.count("RenderOpaqueObjectsInWorld") == 0 and H.count("OnPostRender") == 0,
    "cable: no plugged charger -> no render handlers")
local o = { x = 10, y = 20, z = 0, kind = "WallConnector", facing = "S", vid = nil }
T.onChargerChanged(o)
frame()
check(C.count() == 0 and #draws == 0 and H.count("RenderOpaqueObjectsInWorld") == 0, "cable: charger without vid stays unhooked")

-- ---- plugged: Facing S charger at (10,20), car parked south of it ----
local v = car(11.2, 24.0, 0.3)
o.vid = v:getId()
T.onChargerChanged(o)
check(H.count("RenderOpaqueObjectsInWorld") == 1 and H.count("OnPostRender") == 1, "cable: plugging hooks both handlers once")
T.onChargerChanged(o)
check(H.count("RenderOpaqueObjectsInWorld") == 1 and C.count() == 1, "cable: repeated update does not double-hook")
frame()
local hang, plug = draws[1], draws[#draws]
check(hang.item.type == "Base.MinidoracatTesla_CableHang" and H.near(hang.x, 10.5) and H.near(hang.y, 20.1) and hang.a == 90,
    "cable: hang origin under the exit (10.5, 20.1), angle 90 (facing S = +y)")
-- port and plug tip
local lp = Vector3f.new():set(0.4615, 0, -0.6264)
local port = v:getWorldPos(lp:x(), lp:y(), lp:z(), Vector3f.new())
local tipx = plug.x + C.PLUG_REACH * math.cos(math.rad(plug.a))
local tipy = plug.y + C.PLUG_REACH * math.sin(math.rad(plug.a))
check(plug.item.type == "Base.MinidoracatTesla_CablePlug" and H.near(tipx, port:x(), 1e-4) and H.near(tipy, port:y(), 1e-4),
    "cable: plug tip (origin + PLUG_REACH along its angle) lands on the charge port")
local ax, ay = 10.5, 20.5
local len = math.sqrt((plug.x - ax) ^ 2 + (plug.y - ay) ^ 2)
check(#draws == 2 + math.ceil(len), "cable: draws = 1 hang + ceil(floor run) + 1 plug (" .. #draws .. ")")
local first, last = draws[2], draws[#draws - 1]
local fa = math.rad(first.a)
check(H.near(first.x - 0.5 * math.cos(fa), ax, 1e-6) and H.near(first.y - 0.5 * math.sin(fa), ay, 1e-6),
    "cable: first floor piece starts where the hang lies down")
check(H.near(last.x + 0.5 * math.cos(fa), plug.x, 1e-6) and H.near(last.y + 0.5 * math.sin(fa), plug.y, 1e-6),
    "cable: last floor piece ends at the plug origin")
check(#lines2d == 0, "cable: 3D on -> no 2D lines")

-- ---- plug on a ramp square: lifted by the apparent height ----
ramp[math.floor(plug.x) .. "," .. math.floor(plug.y)] = 0.25
frame()
check(H.near(draws[#draws].z, 0.25) and draws[1].z == 0, "cable: plug on a ramp square sits at getApparentZ (0.25)")
ramp = {}

-- ---- car moves: endpoints follow ----
v.x, v.y = 13.0, 25.5
frame()
local plug2 = draws[#draws]
check(not H.near(plug2.x, plug.x) and H.near(plug2.x + C.PLUG_REACH * math.cos(math.rad(plug2.a)),
    v:getWorldPos(0.4615, 0, -0.6264, Vector3f.new()):x(), 1e-4), "cable: plug follows the car")

-- ---- player far away: culled ----
player.x = 10 + C.DRAW_RANGE + 5
frame()
check(#draws == 0, "cable: charger beyond DRAW_RANGE -> 0 draws")
player.x = 10

-- ---- short run: one scaled floor piece, scale restored ----
v.x, v.y = 10.0, 21.6
frame()
local n = #draws
check(n == 3 and draws[2].s < 1 and draws[2].item.scale == 1, "cable: floor run < 1 tile -> one scaled piece, scale reset")

-- ---- facings rotate the exit ----
o.facing = "E"
T.onChargerChanged(o)
frame()
check(H.near(draws[1].x, 10.1) and H.near(draws[1].y, 20.5) and draws[1].a == 0, "cable: facing E exit (10.1, 20.5), angle 0")
o.facing = "N"
T.onChargerChanged(o)
frame()
check(H.near(draws[1].x, 10.5) and H.near(draws[1].y, 20.9) and draws[1].a == 270, "cable: facing N exit (10.5, 20.9), angle 270")
o.facing = "W"
T.onChargerChanged(o)
frame()
check(H.near(draws[1].x, 10.9) and H.near(draws[1].y, 20.5) and draws[1].a == 180, "cable: facing W exit (10.9, 20.5), angle 180")

-- ---- 3D ground items off: 2D polyline only ----
opt3d = false
frame()
check(#draws == 0 and #lines2d == 3, "cable: 3D ground items off -> 0 Render3DItem, 3 iso lines")
check(H.near(lines2d[1][3], 0.327) and H.near(lines2d[1][1], 10.9), "cable: 2D line starts at the exit height")
opt3d = true

-- ---- car not loaded on this client / dragged too far ----
H.removeVehicle(v)
frame()
check(#draws == 0 and #lines2d == 0, "cable: unknown vid -> 0 draws")
local far = car(40, 20, 0)
o.vid = far:getId()
T.onChargerChanged(o)
frame()
check(#draws == 1 and draws[1].item.type == "Base.MinidoracatTesla_CableHang", "cable: floor run > MAX_FLOOR -> only the hang")

-- ---- second charger, then unplug both: handlers removed ----
local o2 = { x = 30, y = 20, z = 0, kind = "WallConnector", facing = "S", vid = car(31, 23, 0):getId() }
T.onChargerChanged(o2)
check(C.count() == 2 and H.count("RenderOpaqueObjectsInWorld") == 1, "cable: two cables, one handler")
o.vid = false               -- what the server syncs after unplugging (TeslaLogic, GOS only sends set keys)
T.onChargerChanged(o)
T.onChargerChanged(o2, true)
frame()
check(C.count() == 0 and H.count("RenderOpaqueObjectsInWorld") == 0 and H.count("OnPostRender") == 0 and #draws == 0,
    "cable: unplug + remove -> handlers removed, 0 draws per frame")

for k, v in pairs(saved) do _G[k] = v or nil end   -- later test files bring their own fakes
