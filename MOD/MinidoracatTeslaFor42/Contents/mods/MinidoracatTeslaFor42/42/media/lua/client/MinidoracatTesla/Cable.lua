-- Charge cable between a charger and the car's charge port (client only; nothing is synced or saved here).
-- Data: the CMinidoracatTeslaChargerSystem lua objects; TeslaLogic calls MinidoracatTesla.onChargerChanged(o, removed)
-- after initLuaObjects, on every OnLuaObjectUpdated and before removeLuaObjectAt. o.vid = plugged car id or nil.
-- 3D: render-only items (scripts/items/MinidoracatTesla_cable.txt: hang, floor, one plug per car) drawn with Render3DItem in
-- RenderOpaqueObjectsInWorld, like vanilla Fishing/Bobber.lua:32-38 (LuaManager.java:11932-11963; the event fires per
-- local player per frame, FBORenderCell.java:1126,3634-3656). With 3D ground items off (Core.java:4477) Render3DItem
-- would draw item icons, so a 2D polyline is drawn in OnPostRender instead (renderIsoLine, LuaManager.java:10173-10186).
-- Both handlers are hooked only while at least one cable is plugged in: 0 draws per frame otherwise.
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local C = {}
T.Cable = C

-- Mesh geometry (scripts/blender/props/props_blender.py): tiles; heights in levels (1 level = 2.44949 units).
-- The plug segment (item and handle height) is per car: T.Specs[script].plug (Core.lua).
C.HANG_REACH = 0.40          -- hang segment: exit floor point -> where it lies on the floor, along the facing
C.PLUG_REACH = 0.36          -- plug segment: its floor point -> handle tip at the port, horizontal
C.DRAW_RANGE = 45            -- 3D: skip chargers farther than this from the local player (tiles)
-- ponytail: floor runs longer than this are not drawn (car dragged away before the server unplugged it)
C.MAX_FLOOR = 16
C.WIDTH_2D = 3
-- facing -> forward dx, dy (PZ: +x east, +y south) and the Render3DItem angle of that direction:
-- model +X points along atan2(dy, dx) degrees (ItemModelRenderer.java:260-268,908-921; Core.java:2578-2587)
local FACE = { S = { 0, 1, 90 }, E = { 1, 0, 0 }, N = { 0, -1, 270 }, W = { -1, 0, 180 } }

local lines, byKey, count = {}, {}, 0
local hooked = false
local hangItem, floorItem, vLocal, vWorld
local plugItems = {}         -- plug item type -> its render instance, one per car model, reused every frame
local g = {}                 -- one solve result, reused every line and frame

local function angle(dx, dy)
    local a = math.deg(math.atan2(dy, dx))
    if a < 0 then a = a + 360 end
    return a                 -- >= 0: Render3DItem only takes the forced rotation when >= 0 (ItemModelRenderer.java:260)
end

local function squareAt(cell, x, y, z)
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
end

local function groundZ(sq, x, y)
    return sq:getApparentZ(x - math.floor(x), y - math.floor(y))
end

-- Endpoints of one plugged cable into g (returned; the same table every call, read it before the next solve).
-- false when the car or the charger definition is not available here.
-- g.ex,ey: floor point under the charger's exit (hang origin); g.ax,ay: where the hang lies on the floor;
-- g.bx,by,bz: plug segment origin on the floor; g.px,py: charge port; g.len: floor run a -> b;
-- g.plug: the car's T.Specs plug ({ item, z }).
function C.solve(e)
    local vehicle = getVehicleById(e.vid)                    -- LuaManager.java:10276-10281
    local def = vehicle and T.Chargers and T.Chargers[e.kind]
    local spec = def and T.spec(vehicle)
    g.plug = spec and spec.plug
    if not g.plug then return false end
    local exit = def.cableExit
    if not exit then return false end
    local lp = vehicle:getAttachmentLocalPos("chargeport", vLocal)   -- BaseVehicle.java:9940-9952
    if not lp then return false end
    local f = FACE[e.facing] or FACE.S
    local fx, fy = f[1], f[2]
    -- cableExit is given for Facing S (forward +y); turn it: right = (fy, -fx), forward = (fx, fy)
    local ox, oy = exit[1], exit[2]
    g.ex = e.x + 0.5 + ox * fy + oy * fx
    g.ey = e.y + 0.5 - ox * fx + oy * fy
    g.eh = exit[3]
    g.hangAngle = f[3]
    g.ax = g.ex + fx * C.HANG_REACH
    g.ay = g.ey + fy * C.HANG_REACH
    -- plug sits outside the car flank the port is on: local x pushed outward by PLUG_REACH
    local lx, ly, lz = lp:x(), lp:y(), lp:z()
    local side = lx >= 0 and C.PLUG_REACH or -C.PLUG_REACH
    local w = vehicle:getWorldPos(lx, ly, lz, vWorld)         -- BaseVehicle.java:1891-1893 (x,y world; z see below)
    g.px, g.py = w:x(), w:y()
    w = vehicle:getWorldPos(lx + side, ly, lz, vWorld)
    g.bx, g.by = w:x(), w:y()
    -- ground under the plug: the car's floor level (BaseVehicle.java:3371-3377) plus the ramp height there
    -- (IsoGridSquare.getApparentZ, :10177-10196; vanilla ramps_01 tiles); the handle height is built into each car's mesh
    g.bsq = squareAt(getCell(), g.bx, g.by, vehicle:getZ())
    g.bz = g.bsq and groundZ(g.bsq, g.bx, g.by) or vehicle:getZ()
    g.plugAngle = angle(g.px - g.bx, g.py - g.by)
    local dx, dy = g.bx - g.ax, g.by - g.ay
    g.len = math.sqrt(dx * dx + dy * dy)
    g.ux, g.uy = 0, 0
    if g.len > 0 then g.ux, g.uy = dx / g.len, dy / g.len end
    g.floorAngle = angle(dx, dy)
    return g
end

-- 3D: 1 hang + ceil(len) floor + 1 plug Render3DItem per cable. Floor pieces are 1 tile long (origin = midpoint):
-- laid from a, the last one ends exactly at b (overlapping its neighbour); a run under 1 tile is one scaled piece.
local function draw3D(cell, e)
    local z = e.z
    local sq = squareAt(cell, g.ex, g.ey, z)
    if not sq then return end
    Render3DItem(hangItem, sq, g.ex, g.ey, z, g.hangAngle)
    local len = g.len
    if len > C.MAX_FLOOR then return end
    if len > 0.05 then
        local ux, uy, a = g.ux, g.uy, g.floorAngle
        if len < 1 then
            local mx, my = g.ax + ux * len * 0.5, g.ay + uy * len * 0.5
            sq = squareAt(cell, mx, my, z)
            if sq then
                floorItem:setWorldScale(len)                  -- InventoryItem.java:4248, ItemModelRenderer.java:255-257
                Render3DItem(floorItem, sq, mx, my, z, a)
                floorItem:setWorldScale(1)
            end
        else
            local n = math.ceil(len)
            for k = 0, n - 1 do
                local t = (k < n - 1) and (k + 0.5) or (len - 0.5)
                local mx, my = g.ax + ux * t, g.ay + uy * t
                sq = squareAt(cell, mx, my, z)
                if sq then Render3DItem(floorItem, sq, mx, my, groundZ(sq, mx, my), a) end
            end
        end
    end
    local plug = g.bsq and plugItems[g.plug.item]
    if plug then Render3DItem(plug, g.bsq, g.bx, g.by, g.bz, g.plugAngle) end
end

local function render3D(playerIndex)
    if not getCore():isOption3DGroundItem() then return end
    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    local px, py, r2 = player:getX(), player:getY(), C.DRAW_RANGE * C.DRAW_RANGE
    local cell = getCell()
    for i = 1, count do
        local e = lines[i]
        local dx, dy = e.x - px, e.y - py
        if dx * dx + dy * dy <= r2 and C.solve(e) then draw3D(cell, e) end
    end
end

-- 2D fallback: exit -> floor -> plug floor point -> port. Always on top of walls and cars (no depth), R8.
local function render2D()
    if getCore():isOption3DGroundItem() then return end
    local wdt = C.WIDTH_2D
    for i = 1, count do
        local e = lines[i]
        if C.solve(e) and g.len <= C.MAX_FLOOR then
            local z = e.z
            renderIsoLine(g.ex, g.ey, z + g.eh, g.ax, g.ay, z, wdt, 0.1, 0.1, 0.11, 1)
            renderIsoLine(g.ax, g.ay, z, g.bx, g.by, g.bz, wdt, 0.1, 0.1, 0.11, 1)
            renderIsoLine(g.bx, g.by, g.bz, g.px, g.py, g.bz + g.plug.z / 2.44949, wdt, 0.1, 0.1, 0.11, 1)
        end
    end
end

local function sync()
    local want = count > 0
    if want == hooked then return end
    hooked = want
    if want then
        if not hangItem then                                  -- once per client, reused every frame
            hangItem = instanceItem("Base.MinidoracatTesla_CableHang")
            floorItem = instanceItem("Base.MinidoracatTesla_CableFloor")
            for _, s in pairs(T.Specs) do plugItems[s.plug.item] = instanceItem(s.plug.item) end -- one per car
            vLocal, vWorld = Vector3f.new(), Vector3f.new()
        end
        Events.RenderOpaqueObjectsInWorld.Add(render3D)
        Events.OnPostRender.Add(render2D)
    else
        Events.RenderOpaqueObjectsInWorld.Remove(render3D)
        Events.OnPostRender.Remove(render2D)
    end
end

-- Keep the plugged list in step with one charger lua object.
function C.update(o, removed)
    local key = o.x .. "," .. o.y .. "," .. o.z
    local e = byKey[key]
    if removed or not o.vid then          -- unplugged syncs vid = false (GOS packets only carry set keys)
        if e then
            for i = 1, count do
                if lines[i] == e then
                    lines[i] = lines[count]
                    lines[count] = nil
                    count = count - 1
                    break
                end
            end
            byKey[key] = nil
        end
    else
        if not e then
            e = {}
            count = count + 1
            lines[count] = e
            byKey[key] = e
        end
        e.x, e.y, e.z, e.kind, e.facing, e.vid = o.x, o.y, o.z, o.kind, o.facing, o.vid
    end
    sync()
end

function C.count() return count end
function C.hooked() return hooked end

local prev = T.onChargerChanged
function T.onChargerChanged(o, removed)
    if prev then prev(o, removed) end
    C.update(o, removed)
end
