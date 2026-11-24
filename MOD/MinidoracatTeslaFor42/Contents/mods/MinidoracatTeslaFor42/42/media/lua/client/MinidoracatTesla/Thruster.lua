-- Thrusters, the driver's side (Roadster Rocket, Specs `thruster`): the radial ring, the key binds, asking the server
-- (`thrust`), and flying the approved action on this machine, which has the car's physics: one OnTick for the action's
-- length that reads the car and gives it one addImpulse a frame (AGENTS.md rule 2 exception, roadster2.md), removed on
-- landing or abort. The server bills and ends it (server Thruster.lua). Controller, gains and profiles: the flight PoC
-- (temp/plan-roadster2-1124/poc/RESULTS.md, scenario flight-poc-sp); physics coordinates x = world x, y = up,
-- z = world y.
if isServer() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Units" -- the mod's options page (PZAPI.ModOptions) the key binds go on
require "MinidoracatTesla/Net" -- its deny handler, wrapped at the end of this file
require "Vehicles/ISUI/ISVehicleMenu"

local T = MinidoracatTesla
local H = T.Thruster
local FLOOR = H.FLOOR
local TEX = "media/textures/MinidoracatTesla/HUD/"
T.ClientCommands = T.ClientCommands or {}

local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
local function cross(ax, ay, az, bx, by, bz) return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx end
local function dot(ax, ay, az, bx, by, bz) return ax * bx + ay * by + az * bz end
local function rot(vx, vy, vz, ax, ay, az, th) -- v about the unit axis a by th
    local c, s = math.cos(th), math.sin(th)
    local cx, cy, cz = cross(ax, ay, az, vx, vy, vz)
    local d = dot(ax, ay, az, vx, vy, vz) * (1 - c)
    return vx * c + cx * s + ax * d, vy * c + cy * s + ay * d, vz * c + cz * s + az * d
end

-- ---- controller constants (flight PoC) ----
local G = 10
local KP_H, KD_H, KI_H = 4, 4, 1 -- hover height PID
-- the hover's reference height moves to its goal (flyH at take-off, PageUp/PageDown) at most HOVER_V m/s, speeding
-- up and slowing down at HOVER_A m/s^2 (its speed and acceleration fed forward); the integral only within IE_BAND m
-- of it. A step to flyH wound the integral up on the climb: 3.49 m three seconds after a take-off for 3
-- (r2int-sp-t0, the real body); a 2.5 m/s ramp alone still overshot 0.39 m (harness "hover:")
local HOVER_V, HOVER_A, IE_BAND = 3, 4, 0.5
local KP_R, KD_R = 25, 10        -- profile height tracking
local KV, AMAX = 2, 10           -- horizontal speed P, its acceleration cap (m/s^2)
local GAIN = { lo = { 9, 6 }, hi = { 36, 12 } } -- attitude PD
local LPAR = 0.02                -- torque of the force along it, kept until it is worth a torque-only frame
local DT_MAX = 0.083             -- the physics step's own cap
local ROLL_S, LAND_S = 3, 12     -- roll-up and soft landing give up after these seconds (server Thruster.lua D2/D3)
-- the soft landing at rest off the ground (on its side, an eave, a fence, another car: r2int-mp-prof fix 1, up 0.141
-- at 0.817 m, ran its 12 s): this long under REST_V m/s within REST_DH m of one height is over. A landing never sinks
-- slower than 0.7 m/s (landVy), so a car still coming down never reads as at rest; a car pressed down on what holds it
-- sinks 0.05-0.1 m/s (r2f3-mp-c boostnearhold: 1.6 s on a fence top, never 0.7 s within 0.03 m)
local REST_S, REST_V, REST_DH = 0.7, 0.2, 0.1
-- at rest REST_S, then a probe with no push: a car held on a roof's edge by the landing's own push read as at rest,
-- ended there and tipped over (r2fin-sp-full roof 1 #1: up 0.033, hit -4.22 m/s). Sampled at PROBE_A s (the springs
-- settle first) and PROBE_B s: faster than REST_V, PROBE_DH m lower or turned over 2 degrees is moving (r2f3-sp-probe2:
-- a car read at rest at 3.76 fell after; hung cars 8.6-30. Read moving wrongly, it is only carried 3 m)
local PROBE_A, PROBE_B, PROBE_DH, PROBE_DOT = 0.2, 0.4, 0.05, 0.99939
-- found moving, it is lifted LIFT_DH m and carried the way it leans (its up vector's level part: the side hanging free)
-- at SLIDE_V, until SLIDE_D m off or SLIDE_S s; then down again, probed again if it stops. Held on an edge the landing
-- pushes down at -G and its attitude PD levels it about the edge (r2f3-sp-probe3: slid level 3 s, rose 0.1-0.25 m,
-- never got off, 8 of 8 one floor up); landing on in place, it hung there LAND_S (r2f3-sp-probe: 6 of 30)
local SLIDE_V, LIFT_DH, SLIDE_D, SLIDE_S = 2, 0.8, 3, 4
-- a flight's landing stops at its height first (r2scan-sp-obst2 fenceland: down at its flying speed onto a fence,
-- turned over): GLIDE_V m/s ahead while anything under it would catch it (landClear), down after GLIDE_S s at most
local GLIDE_V, GLIDE_S = 3, 4
-- a flight's motor off above OFF_H m (its wheels clear), started START_MS ms after it was seen off at the earliest
local OFF_H, START_MS = 0.6, 2200
local WAKE_KMH = 3               -- the motor's creep that wakes a parked car before it flies (go)
-- the real seconds one frame may count toward the flight's limit: a pause (no OnTick) is not flown time
local REAL_MAX = 0.25
-- the soft landing's sink speed (m/s, negative) at hm m: v^2 = 0.49 + 12 (hm - 0.3), a steady 6 m/s^2 braking,
-- 0.7-8 m/s. A stunt past its turn coming down faster than this is taken over by it
local function landVy(hm) return -math.max(0.7, math.min(8, math.sqrt(0.49 + 12 * math.max(0, hm - 0.3)))) end
local V3 = { u = Vector3f.new(), f = Vector3f.new(), lv = Vector3f.new(), imp = Vector3f.new(), rel = Vector3f.new() }

-- kickflip: height (m at apex 8) through these points (s, m), one roll about the nose axis between 0.8 and 1.8 s;
-- backflip: h = apex sin^2(pi t / 2.8), one pitch nose-up between 0.75 and 2.0 s
local KICK = { { 0, 0 }, { 0.4, 1.68 }, { 0.8, 4.48 }, { 1.3, 7.28 }, { 1.8, 7.99 }, { 2.3, 6.04 }, { 2.8, 3.17 }, { 3.3, 1.04 }, { 3.8, 0.18 } }
local function slope(i)
    local n = #KICK
    if i == 1 then return 0 end
    if i == n then return (KICK[n][2] - KICK[n - 1][2]) / (KICK[n][1] - KICK[n - 1][1]) end
    return (KICK[i + 1][2] - KICK[i - 1][2]) / (KICK[i + 1][1] - KICK[i - 1][1])
end
local function hermite(t)
    local n = #KICK
    if t <= 0 then return 0, 0, 0 end
    if t >= KICK[n][1] then return KICK[n][2], slope(n), 0 end
    local i = 1
    while KICK[i + 1][1] < t do i = i + 1 end
    local g = KICK[i + 1][1] - KICK[i][1]
    local s = (t - KICK[i][1]) / g
    local y0, y1, m0, m1 = KICK[i][2], KICK[i + 1][2], slope(i) * g, slope(i + 1) * g
    local s2, s3 = s * s, s * s * s
    return (2 * s3 - 3 * s2 + 1) * y0 + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * y1 + (s3 - s2) * m1,
        ((6 * s2 - 6 * s) * y0 + (3 * s2 - 4 * s + 1) * m0 + (-6 * s2 + 6 * s) * y1 + (3 * s2 - 2 * s) * m1) / g,
        ((12 * s - 6) * y0 + (6 * s - 4) * m0 + (-12 * s + 6) * y1 + (6 * s - 2) * m1) / (g * g)
end
local BF_T = 2.8
local PROF = {
    kickflip = { T = 3.8, t1 = 0.8, t2 = 1.8, axis = "f", H = function(t, apex)
        local h, d, dd = hermite(t)
        local k = apex / 7.99
        return h * k, d * k, dd * k
    end },
    backflip = { T = BF_T, t1 = 0.75, t2 = 2.0, axis = "r", H = function(t, apex)
        local w = math.pi / BF_T
        return apex * math.sin(w * t) ^ 2, apex * w * math.sin(2 * w * t), 2 * apex * w * w * math.cos(2 * w * t)
    end },
}
local function quintic(t, t1, t2)
    if t <= t1 then return 0, 0, 0 end
    if t >= t2 then return 1, 0, 0 end
    local d = t2 - t1
    local x = (t - t1) / d
    return x * x * x * (10 - 15 * x + 6 * x * x), 30 * x * x * (1 - x) ^ 2 / d, (60 * x - 180 * x * x + 120 * x * x * x) / (d * d)
end

-- ---- where the ground is: shared Thruster.lua (the server judges "off the ground" by the same) ----
local function groundZ(v) return H.groundZ(v, true) end -- cached: H.groundReset at each action's start
-- floors between the ground and the car's physics origin at rest, per car, measured when it stands on the ground
local RESTS = {}
-- [vid] = true: its soft landing ended at rest off the ground (REST_S); the watch's tilt branch skips it until it
-- stands on the ground again or starts a boost or stunt (a car teetering on an eave would start a landing each time
-- it slips, a third each)
local RESTED = {}
local function heightOf(v, rest) return (v:getDebugZ() - groundZ(v) - rest) * FLOOR end

-- kickflip / backflip: what lies on the car's way, read once before take-off. Two kinds:
-- * slowed or stopped at any height: an object with CarSlowFactor or HitByCar (a tree, a fence, a hedge, a pole). The
--   engine reads the objects on the car's own level (breakingObjects, BaseVehicle.java:2965-3003), and that level
--   stays 0 over open ground however high the car is (BaseVehicle.java:3404-3410: z is the origin's floor only where
--   that square exists with a floor on it or under it); once listed only the 2D distance counts (:3045-3080). So the
--   whole way (r15 KshotA: stopped 2.70 m up)
-- * a static body (IsoChunk.java:1949-2107): a solid, solidtrans or blocksight square, stairs, a tree, a moveable, a
--   PhysicsShape / PhysicsMesh tile, a player's whole-square wall, on level 0 an outdoor lamp post or a hoop; a wall,
--   window (open or shut) or shut door on the square's own N / W edge. Built per level (updatePhysicsForLevel; their
--   height is in the native code, unread): taken as one floor high at most, so only where the car is under one floor
-- All the way, a floor up to the apex (a roof, a bridge). shortcut: tiles only, not the car's exact outline
local function slows(sq)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local p = objs:get(i):getProperties()
        if p and (p:has("CarSlowFactor") or p:has("HitByCar")) then return true end
    end
    return false
end
local HOOPS = { recreational_sports_01_19 = true, recreational_sports_01_21 = true, recreational_sports_01_32 = true }
local function body(sq, ground) -- ground: level 0, where lamp posts and hoops get one (IsoChunk.java:1992-2013)
    if sq:isSolid() or sq:isSolidTrans() or sq:HasStairs() then return true end
    local f = sq:getProperties()
    if f and (f:has(IsoFlagType.blocksight) or f:has(IsoFlagType.collideN) or f:has(IsoFlagType.collideW)
        or f:has(IsoFlagType.windowN) or f:has(IsoFlagType.windowW)
        or (f:has(IsoFlagType.doorN) or f:has(IsoFlagType.doorW)) and not f:has(IsoFlagType.open)) then return true end
    if sq:has(IsoObjectType.tree) or sq:has(IsoObjectType.isMoveAbleObject) then return true end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local p = o:getProperties()
        if p and (p:has("PhysicsShape") or p:has("PhysicsMesh")) then return true end
        if instanceof(o, "IsoThumpable") and o:isBlockAllTheSquare() then return true end
        if ground then
            local s = o:getSprite()
            local n = s and s:getName()
            if n and (n:find("lighting_outdoor_", 1, true) or HOOPS[n]) then return true end
        end
    end
    return false
end
local function roofOver(cell, x, y, z0, levels)
    for lv = z0 + 1, z0 + levels do
        local up = cell:getGridSquare(x, y, lv)
        if up and (up:getFloor() or up:isSolid()) then return true end
    end
    return false
end
local function clearPath(v, conf, act)
    local fw = v:getForwardVector(V3.f)
    local l = math.max(1e-6, math.sqrt(fw:x() ^ 2 + fw:z() ^ 2))
    local fx, fy = fw:x() / l, fw:z() / l
    local P = PROF[act]
    local mps = math.max(conf.rollKmh, v:getCurrentSpeedKmHour()) / 3.6
    local len = mps * (P.T + 0.7) + 2.5
    -- below one floor: kickflip the first 0.55 s and from 2.9 s (its height curve), backflip all of it
    local low1, low2 = act == "kickflip" and mps * 0.55 + 2.5 or len, act == "kickflip" and mps * 2.9 - 2.5 or len
    local levels = math.ceil((conf.apex + 1.5) / FLOOR)
    local cell, z0 = getCell(), groundZ(v)
    local x0, y0 = v:getX(), v:getY()
    local seen, prev = {}, {}
    for d = 0, len, 0.5 do
        local low = d <= low1 or d >= low2
        for o = -1, 1 do
            local x, y = math.floor(x0 + fx * d - fy * o), math.floor(y0 + fy * d + fx * o)
            local k = x * 100000 + y
            if not seen[k] then
                seen[k] = true
                local sq = cell:getGridSquare(x, y, z0)
                if not sq then return false end -- not loaded: can't tell
                if slows(sq) or low and body(sq, z0 == 0) then return false end
                local pv = prev[o]
                if low and pv and pv:isBlockedTo(sq) then return false end
                if roofOver(cell, x, y, z0, levels) then return false end
                prev[o] = sq
            end
        end
    end
    return true
end
-- flying: nothing overhead where it takes off
local function clearAbove(v, conf)
    local cell, z0 = getCell(), groundZ(v)
    local levels = math.ceil((conf.flyMaxH + 1.5) / FLOOR)
    local x0, y0 = math.floor(v:getX()), math.floor(v:getY())
    for x = x0 - 1, x0 + 1 do
        for y = y0 - 1, y0 + 1 do
            if roofOver(cell, x, y, z0, levels) then return false end
        end
    end
    return true
end

-- where a flight's landing comes down: nothing under the car's outline (-2.5 to +4 m along it, a tile either side)
-- that slows or stops a car on the level it lands on (slows / body above)
local function landClear(v)
    local fw = v:getForwardVector(V3.f)
    local l = math.max(1e-6, math.sqrt(fw:x() ^ 2 + fw:z() ^ 2))
    local fx, fy = fw:x() / l, fw:z() / l
    local cell, z0 = getCell(), groundZ(v)
    local x0, y0 = v:getX(), v:getY()
    for d = -2.5, 4, 0.5 do
        for o = -1, 1 do
            local sq = cell:getGridSquare(math.floor(x0 + fx * d - fy * o), math.floor(y0 + fy * d + fx * o), z0)
            if sq and (slows(sq) or body(sq, z0 == 0)) then return false end
        end
    end
    return true
end

-- ---- the action this machine flies (one at a time) ----
local F = nil
-- the motor asked off in flight (offAsked): Core.lua CheckOperate.Battery holds the driver's input back until the
-- landing comes down (sink), or vanilla starts it again on W once it idles (CarController.java:329-341). The brake
-- forced once and read once: the controls kept from then on are braking or park()'s all-false (:983-990), no gas
function H.offHold(v)
    local f = F
    if not f or f.v ~= v or not f.offAsked or f.sink then return false end
    if v:isRegulator() then v:setRegulator(false) end -- cruise is gas too (CarController.java:243-247)
    if not f.snap then f.snap = 1; v:setForceBrake(); return true end -- counts from the next ms (:974-975)
    if f.snap == 1 then f.snap = 2; return false end -- one read with the brake forced on
    return true
end
function H.active() return F end
-- { vid, n, t }: the boost this machine ended off an edge (n: its number, t: its busy flag's time). Its busy flag stays
-- in this machine's copy until the server's clear arrives, so it is no bar to that fall's landing, and the landing
-- names it (over = n): its thrustEnd, sent the same frame, may reach the server after the landing (RELIABLE,
-- unordered: PacketTypes.java:508). Used once (H.ask)
local OFF_EDGE = nil
local function busyOf(v)
    local part = T.Battery.part(v)
    local thr = part and part:getModData().thr
    return type(thr) == "table" and thr.busy or nil
end

local function authority(v) return not isClient() or v:isLocalPhysicSim() end -- BaseVehicle.java:682-686

-- angular velocity from how u and f moved, over the physics seconds since they last changed rounded to the 0.01 s
-- substep (WorldSimulation.java:83-90)
local function bodyFix(sx, sy, sz, ux, uy, uz, fx, fy, fz)
    local rx, ry, rz = cross(ux, uy, uz, fx, fy, fz)
    local su, sf, sr = dot(sx, sy, sz, ux, uy, uz), dot(sx, sy, sz, fx, fy, fz), dot(sx, sy, sz, rx, ry, rz) / 2
    return su * ux + sf * fx + sr * rx, su * uy + sf * fy + sr * ry, su * uz + sf * fz + sr * rz
end
local function updOmega(st, ux, uy, uz, fx, fy, fz, dt)
    st.acc = st.acc + dt
    if not st.ux then
        st.ux, st.uy, st.uz, st.fx, st.fy, st.fz, st.acc = ux, uy, uz, fx, fy, fz, 0
        return
    end
    if ux == st.ux and uy == st.uy and uz == st.uz and fx == st.fx and fy == st.fy and fz == st.fz then
        if st.acc > 0.05 then st.wx, st.wy, st.wz = 0, 0, 0 end
        return
    end
    local per = math.max(1, math.floor(st.acc / 0.01 + 0.5)) * 0.01
    local ax, ay, az = cross(ux, uy, uz, (ux - st.ux) / per, (uy - st.uy) / per, (uz - st.uz) / per)
    local bx, by, bz = cross(fx, fy, fz, (fx - st.fx) / per, (fy - st.fy) / per, (fz - st.fz) / per)
    local wx, wy, wz = bodyFix(ax + bx, ay + by, az + bz, ux, uy, uz, fx, fy, fz)
    st.wx, st.wy, st.wz = 0.5 * (wx + st.wx), 0.5 * (wy + st.wy), 0.5 * (wz + st.wz)
    st.ux, st.uy, st.uz, st.fx, st.fy, st.fz, st.acc = ux, uy, uz, fx, fy, fz, 0
end

-- one impulse a frame (addImpulse keeps one per tick, BaseVehicle.java:688-699): the frame's force at the arm that
-- gives its torque; the torque along the force can't come from an arm, so it waits until it is worth one frame of
-- torque alone (a tiny force on a long arm)
local function sendAI(v, jx, jy, jz, rx, ry, rz)
    V3.imp:set(jx * 100, jy * 100, jz * 100) -- an impulse acts for one 0.01 s substep
    V3.rel:set(rx, ry, rz)
    v:addImpulse(V3.imp, V3.rel)
end
local function torqueOnly(v, lx, ly, lz, m)
    local dx, dy, dz = cross(lx, ly, lz, 0, 1, 0)
    if dx * dx + dy * dy + dz * dz < 1e-8 * (lx * lx + ly * ly + lz * lz) then dx, dy, dz = cross(lx, ly, lz, 1, 0, 0) end
    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
    local e = 1e-4 * m
    dx, dy, dz = dx / l * e, dy / l * e, dz / l * e
    local rx, ry, rz = cross(dx, dy, dz, lx, ly, lz)
    sendAI(v, dx, dy, dz, rx / (e * e), ry / (e * e), rz / (e * e))
end
local function flush(v, b, m, iu)
    local J2 = b.jx * b.jx + b.jy * b.jy + b.jz * b.jz
    if J2 < (1e-4 * m) ^ 2 then
        if b.lx ~= 0 or b.ly ~= 0 or b.lz ~= 0 then torqueOnly(v, b.lx, b.ly, b.lz, m); b.lx, b.ly, b.lz = 0, 0, 0 end
        return
    end
    local d = dot(b.lx, b.ly, b.lz, b.jx, b.jy, b.jz) / J2
    local qx, qy, qz = d * b.jx, d * b.jy, d * b.jz
    if math.sqrt(qx * qx + qy * qy + qz * qz) > LPAR * iu * m and not b.lastTq then
        torqueOnly(v, b.lx, b.ly, b.lz, m)
        b.lx, b.ly, b.lz, b.lastTq = 0, 0, 0, true
        return
    end
    local rx, ry, rz = cross(b.jx, b.jy, b.jz, b.lx - qx, b.ly - qy, b.lz - qz)
    sendAI(v, b.jx, b.jy, b.jz, rx / J2, ry / J2, rz / J2)
    b.jx, b.jy, b.jz, b.lx, b.ly, b.lz, b.lastTq = 0, 0, 0, qx, qy, qz, false
end

-- the frame's push: height (profile ref, or hover hT), horizontal speed (vT) or boost, attitude (ud/fd or psiT)
local function drive(f, v, dt, hm)
    local st = f.st
    local u, fw, lv = v:getUpVector(V3.u), v:getForwardVector(V3.f), v:getLinearVelocity(V3.lv)
    local ux, uy, uz, fx, fy, fz, vx, vy, vz = u:x(), u:y(), u:z(), fw:x(), fw:y(), fw:z(), lv:x(), lv:y(), lv:z()
    updOmega(st, ux, uy, uz, fx, fy, fz, dt)
    local ax, ay, az = 0, 0, 0
    if st.rh then
        ay = clamp(G + st.ray + KP_R * (st.rh - hm) + KD_R * (st.rvy - vy), -G, 5 * G)
    elseif st.hT then
        local e = st.hT - hm
        if math.abs(e) < IE_BAND then st.ie = clamp(st.ie + e * dt, -3 / KI_H, 3 / KI_H) end
        ay = clamp(G + st.ha + KP_H * e + KD_H * (st.hv - vy) + KI_H * st.ie, 0, 4 * G)
    end
    if st.vTx then
        ax, az = KV * (st.vTx - vx), KV * (st.vTz - vz)
        local a = math.sqrt(ax * ax + az * az)
        if a > AMAX then ax, az = ax * AMAX / a, az * AMAX / a end
    end
    if st.pushA then
        if math.sqrt(vx * vx + vz * vz) < st.pushV then ax, az = st.pushA * st.pdx, st.pushA * st.pdz else ax, az = 0, 0 end
    end
    local alx, aly, alz = 0, 0, 0
    if st.att then
        local udx, udy, udz, fdx, fdy, fdz, free = 0, 1, 0, 0, 0, 0, false
        if st.udx then udx, udy, udz = st.udx, st.udy, st.udz end
        if st.fdx then
            fdx, fdy, fdz = st.fdx, st.fdy, st.fdz
        elseif st.psiT then
            fdx, fdz = math.cos(st.psiT), math.sin(st.psiT)
        else
            local l = math.max(1e-6, math.sqrt(fx * fx + fz * fz))
            fdx, fdz, free = fx / l, fz / l, true
        end
        local e1x, e1y, e1z = cross(ux, uy, uz, udx, udy, udz)
        local e2x, e2y, e2z = cross(fx, fy, fz, fdx, fdy, fdz)
        local ex, ey, ez = bodyFix(e1x + e2x, e1y + e2y, e1z + e2z, ux, uy, uz, fx, fy, fz)
        local g = GAIN[st.gain]
        alx = st.affx + g[1] * ex + g[2] * (st.wdx - st.wx)
        aly = st.affy + g[1] * ey + g[2] * (st.wdy - st.wy)
        alz = st.affz + g[1] * ez + g[2] * (st.wdz - st.wz)
        if free then -- yaw left alone
            local d = dot(alx, aly, alz, ux, uy, uz)
            alx, aly, alz = alx - d * ux, aly - d * uy, alz - d * uz
        end
    end
    -- torque = I alpha about the body axes
    local m, I = v:getMass(), f.conf.inertia
    local rx, ry, rz = cross(ux, uy, uz, fx, fy, fz)
    local ta = I.f * m * dot(alx, aly, alz, fx, fy, fz)
    local tb = I.r * m * dot(alx, aly, alz, rx, ry, rz)
    local tc = I.u * m * dot(alx, aly, alz, ux, uy, uz)
    local b = f.bank
    b.jx, b.jy, b.jz = b.jx + ax * m * dt, b.jy + ay * m * dt, b.jz + az * m * dt
    b.lx = b.lx + (ta * fx + tb * rx + tc * ux) * dt
    b.ly = b.ly + (ta * fy + tb * ry + tc * uy) * dt
    b.lz = b.lz + (ta * fz + tb * rz + tc * uz) * dt
    flush(v, b, m, I.u)
end

local function newState(gain)
    return { acc = 0, wx = 0, wy = 0, wz = 0, ie = 0, gain = gain or "lo", wdx = 0, wdy = 0, wdz = 0, affx = 0, affy = 0, affz = 0 }
end
local function levelHeading(v)
    local fw = v:getForwardVector(V3.f)
    local l = math.max(1e-6, math.sqrt(fw:x() ^ 2 + fw:z() ^ 2))
    return fw:x() / l, fw:z() / l
end

-- camera: the culling height grows with zoom and screen height (flight PoC r3/r18, 1080p: about 1.6 + 6.7 x zoom m);
-- zoom out by whole steps (0.25 each, MultiTextureFBO2.java:26) until `top` m stays on screen, and back after
local function zoomOut(f, top)
    local pn = f.player:getPlayerNum()
    local core = getCore()
    local z = core:getZoom(pn)
    local need = ((top + 1.5) * 1080 / math.max(1, getPlayerScreenHeight(pn)) - 1.6) / 6.7
    local n = math.ceil((need - z) / 0.25 - 1e-6)
    n = clamp(math.min(n, math.floor((core:getMaxZoom() - z) / 0.25 + 1e-6)), 0, 6)
    for _ = 1, n do core:doZoomScroll(pn, 1) end
    f.zoom = (f.zoom or 0) + n
end

-- the motor's cruise back as it was (the driver's roll-up, go)
local function regBack(f)
    if f.reg0 == nil then return end
    f.v:setRegulator(f.reg0 == true)
    f.v:setRegulatorSpeed(f.regSpd0)
    f.reg0 = nil
end

-- the action over on this machine, nothing said: its controller off, the camera and the motor's cruise back
local function halt()
    local f = F
    F = nil
    Events.OnTick.Remove(H.tick)
    if not f then return end
    regBack(f)
    for _ = 1, f.zoom or 0 do getCore():doZoomScroll(f.player:getPlayerNum(), -1) end
    return f
end

-- abort: it can't go on here (the physics left, someone sat in); the server judges what happened (server thrustEnd).
-- rest: a soft landing still off the ground but at rest (REST_S): the server ends it where it is.
-- why, abort and rest optional (`...`: most callers leave them out, and Kahlua does not fill left-out fixed parameters)
local function stop(done, ...)
    local why, abort, rest = ...
    local f = halt()
    if not f then return end
    if rest then RESTED[f.vid] = true end
    T.request(f.player, "thrustEnd", { vid = f.vid, act = f.act, done = done == true, sec = f.flown, abort = abort,
        n = f.n, term = f.term, rest = rest })
    if why then HaloTextHelper.addBadText(f.player, T.denyText(why)) end
end

-- hand over to the soft landing: track the height it is at, sink at a speed that shrinks near the ground, level out
local function setLand(f, hm)
    local st = newState("hi")
    st.att, st.rh, st.rvy, st.ray = true, hm, 0, 0
    f.st, f.phase, f.t = st, "land", 0
    f.bank.lastTq = false
end

local function beginRun(f)
    local v, c = f.v, f.conf
    local st = newState("lo")
    f.st, f.t = st, 0
    local lx, lz = levelHeading(v)
    if f.act == "kickflip" or f.act == "backflip" then
        local P = PROF[f.act]
        local lv = v:getLinearVelocity(V3.lv)
        st.att, st.gain, st.vTx, st.vTz = true, "hi", lv:x(), lv:z()
        st.rh, st.rvy, st.ray = 0, 0, 0
        st.fdx, st.fdy, st.fdz, st.udx, st.udy, st.udz = lx, 0, lz, 0, 1, 0
        f.P, f.f0x, f.f0z = P, lx, lz
        if P.axis == "f" then f.ax, f.az = lx, lz else f.ax, f.az = -lz, lx end -- right axis: nose up first
        f.hEnd = P.H(P.T, c.apex)
        f.phase = "stunt"
        zoomOut(f, c.apex)
    elseif f.act == "boost" then
        local lv = v:getLinearVelocity(V3.lv)
        st.pushA, st.pushV, st.pdx, st.pdz = c.boostA, c.boostV, lx, lz
        f.v0 = math.sqrt(lv:x() ^ 2 + lv:z() ^ 2)
        f.phase = "boost"
    elseif f.act == "fly" then
        st.att, st.hT, st.hG, st.hv, st.ha, st.psiT = true, heightOf(v, f.rest), c.flyH, 0, 0, math.atan2(lz, lx)
        local lv = v:getLinearVelocity(V3.lv)
        st.vTx, st.vTz = lv:x(), lv:z()
        f.spd, f.phase = lv:x() * lx + lv:z() * lz, "fly"
        zoomOut(f, c.flyMaxH)
    else
        setLand(f, heightOf(v, f.rest))
    end
end

-- a parked car may ignore addImpulse until it moves (flight PoC r18: 19 % of new cars). Lifted off its wheels by
-- 0.04 floor first, it takes it: 8/8 (poc/APP.md). setDebugZ is a teleport within the car's floor, its argument that
-- floor's fraction clamped to 0-0.99 (BaseVehicle.java:4161-4168): the fraction, never the absolute height
local function preLift(v)
    local h = v:getDebugZ()
    v:setDebugZ(h - math.floor(h) + 0.04)
end
-- the show (the car empty) rolls up to conf.rollKmh pushed by the thrusters (poc/APP.md: a = 14.4 + 3.6 e +
-- 2 integral e, 0-36 m/s2; an empty car's park brake holds it each update, BaseVehicle.java:3398-3400)
local function beginRoll(f)
    local v, st = f.v, newState("lo")
    st.pdx, st.pdz = levelHeading(v)
    st.pushA, st.pushV = 0, math.huge
    f.st, f.phase, f.t = st, "roll", 0
    preLift(v)
end
-- a parked car may take no impulse even lifted: its physics won't switch on (r2fe-sp-g: 0 of 3 flew), or it reads on
-- and still stays put (r2fe-sp-i: 2 of 2). The motor's creep wakes it (r2fe-sp-g: 3 of 3 flew after it; the stunts'
-- roll-up never stuck): from "wake" it flies once it moves. Once only, its flown time not counted
local function wake(f)
    local v = f.v
    f.woke, f.flown = true, 0
    f.phase, f.t, f.reg0, f.regSpd0 = "wake", 0, v:isRegulator(), v:getRegulatorSpeed()
    v:setRegulatorSpeed(WAKE_KMH)
    v:setRegulator(true)
end
-- the driver's stunt from under conf.rollKmh: the motor's cruise takes it there (flight PoC: 17/17 from 6 km/h; the
-- thrusters' push left 3 of 13 parked cars stuck, r2f-sp-1124c). Flying from a standstill: lifted, then straight up
local function go(f)
    local v, c = f.v, f.conf
    if f.act == "land" or v:getCurrentSpeedKmHour() >= c.rollKmh then return beginRun(f) end
    if f.act == "fly" then
        if not v:isPhysicsActive() then v:setPhysicsActive(true) end
        if not v:isPhysicsActive() then return wake(f) end
        preLift(v)
        return beginRun(f)
    end
    if f.app then return beginRoll(f) end
    f.phase, f.t, f.reg0, f.regSpd0 = "drive", 0, v:isRegulator(), v:getRegulatorSpeed()
    v:setRegulatorSpeed(c.rollKmh + 2)
    v:setRegulator(true)
end

-- app: "show" = the phone app's show (the caller outside, the car empty), "help" = landing a car the server handed to
-- this machine (server Thruster.lua handOver); both wait for the car's physics to arrive here first. n: the server's
-- number for this action (its thrustEnd carries it). ok: approved (the soft landing starts before its answer). Optional
-- term (`...`: a helper's hand-over term; callers leave it out, and Kahlua does not fill left-out fixed parameters)
local function start(player, v, act, sec, app, n, ...)
    local term = ...
    H.groundReset() -- floors built or torn down since the last action count
    local c = H.conf(v)
    local vid = v:getId()
    local f = { player = player, v = v, vid = vid, act = act, conf = c, sec = sec, t = 0, flown = 0, app = app,
        n = n, term = term, ok = app ~= nil,
        bank = { jx = 0, jy = 0, jz = 0, lx = 0, ly = 0, lz = 0, lastTq = false } }
    if act == "land" then
        f.rest, f.lifted = RESTS[vid] or c.rest, true
    else -- a boost or stunt leaves where it rested behind (r2rest-mp-r2 boostnearhold: still RESTED, it went over a
        -- roof's edge nose-first and the tilt branch let it fall at -5.9 m/s)
        f.rest = clamp(v:getDebugZ() - groundZ(v), 0.02, 0.25)
        RESTS[vid], RESTED[vid] = f.rest, nil
    end
    F = f
    if app and not authority(v) then f.phase, f.ms0 = "wait", getTimestampMs() else go(f) end
    Events.OnTick.Add(H.tick)
end

local function keyDown(o) local k = o and o:getValue() or 0 return k ~= 0 and isKeyDown(k) end
local KEYS = {}
-- a controller's stick: nothing inside PAD_DEAD (past the engine's own, JoypadManager.java:298-300: a worn stick resting
-- a little off holds course), then 0-1 again to full
local PAD_DEAD = 0.2
local function padAxis(a)
    local m = math.abs(a)
    if m <= PAD_DEAD then return 0 end
    return (a < 0 and -1 or 1) * (m - PAD_DEAD) / (1 - PAD_DEAD)
end

-- a boost over by this machine: its landing may pass that boost's busy flag until the server's clear comes (OFF_EDGE).
-- Also one at its speed on an edge's lip: it rolls off a moment later (r2f3-mp-d2 boostnearhold: its thrustEnd 300 ms
-- late, the landing refused here meanwhile, asked at up 0.3 and down at 0.83)
local function boostOver(f, v)
    local busy = busyOf(v)
    OFF_EDGE = { vid = f.vid, n = f.n, t = type(busy) == "table" and busy.t or nil }
    stop(f.lifted)
end

-- a flight's motor, shut off at OFF_H m (fly), started again as its landing comes down: once, by the vanilla start
-- (ISVehicleMenu.onStartEngine, the HUD's power key's way: every kind of key), START_MS after it was seen off
-- (ShuttingDown lasts 2 s, tryStartEngine acts only from Idle: BaseVehicle.java:7611-7653). Not tried again (each
-- try costs the 12V 0.025); the heater back on if it was (vanilla toggleHeater, VehicleCommands.lua:59-71)
local function startBack(f, v, now)
    if not f.offAsked or f.started or not f.offSeen or now - f.offSeen < START_MS or v:isEngineRunning() then return end
    f.started = true
    ISVehicleMenu.onStartEngine(f.player)
    if f.heat then sendClientCommand(f.player, "vehicle", "toggleHeater", { on = true, temp = f.heat }) end
end

-- each frame while an action runs
function H.tick()
    local f = F
    if not f then return Events.OnTick.Remove(H.tick) end
    local v = f.v
    if f.phase == "wait" then -- the server handed the physics over: here within about 0.1 s (poc/APP.md)
        local now = getTimestampMs()
        if now < f.ms0 then f.ms0 = now end -- the wall clock set back: no time passed, the wait goes on from now
        if authority(v) then go(f)
        elseif now - f.ms0 > 2000 then return stop(false) end
        return
    end
    -- someone took the driver's seat (the show: anyone; the helper lands it whoever sits there), or the physics left
    if (f.app == "show" and v:getDriver() ~= nil) or (not f.app and v:getDriver() ~= f.player) or not authority(v) then
        return stop(f.lifted, nil, true)
    end
    -- the flight's limit counts real time, as the server's D2 does (a slow frame's physics step is capped at DT_MAX;
    -- the wall clock set back or forward counts as no time or REAL_MAX)
    local now = getTimestampMs()
    local real = math.min(REAL_MAX, math.max(0, (now - (f.ms or now)) / 1000))
    f.ms = now
    if f.offAsked and not f.offSeen and not v:isEngineRunning() then f.offSeen = now end -- ShuttingDown from here
    local dt = math.min(DT_MAX, math.max(0, getGameTime():getPhysicsSecondsSinceLastUpdate()))
    if dt <= 0 then return end -- paused
    if not v:isPhysicsActive() then v:setPhysicsActive(true) end -- a sleeping body takes no impulse (PoC r2)
    f.t = f.t + dt
    local c = f.conf
    local hm = heightOf(v, f.rest)
    local vy = v:getLinearVelocity(V3.lv):y()
    if hm > 0.3 then f.lifted = true end
    local st, ph, t = f.st, f.phase, f.t
    if ph == "wake" then -- moving under its own motor: awake (r2fe-sp-g, 3 km/h for 0.3 s)
        if v:isPhysicsActive() and v:getCurrentSpeedKmHour() > 1 then
            regBack(f)
            preLift(v)
            return beginRun(f)
        end
        if t > ROLL_S then return stop(false, "THRUST_NO_LIFT") end
        -- the brake (Space, the default up key, held as it was asked: r2f3-key-a) drops the cruise every frame
        -- (CarController.java:460-462): set it again, so the creep goes on once it is let go, within ROLL_S
        if not v:isRegulator() then
            v:setRegulatorSpeed(WAKE_KMH)
            v:setRegulator(true)
        end
        return
    elseif ph == "drive" then
        if v:getCurrentSpeedKmHour() >= c.rollKmh then
            regBack(f)
            return beginRun(f)
        end
        if t > ROLL_S then return stop(false, "THRUST_NO_LIFT") end
        return -- the motor drives it
    elseif ph == "roll" then
        local lv = v:getLinearVelocity(V3.lv)
        local along = lv:x() * st.pdx + lv:z() * st.pdz
        if along * 3.6 >= c.rollKmh then return beginRun(f) end
        if t > ROLL_S then return stop(false, "THRUST_NO_LIFT") end
        local e = c.rollKmh / 3.6 - along
        st.ie = st.ie + e * dt
        st.pushA = clamp(14.4 + 3.6 * e + 2 * st.ie, 0, 36)
    elseif ph == "stunt" then
        local P = f.P
        local h, hd, hdd
        if t <= P.T then h, hd, hdd = P.H(t, c.apex) else h, hd, hdd = f.hEnd - (t - P.T), -1, 0 end
        st.rh, st.rvy, st.ray = h, hd, hdd
        local s, sd, sdd = quintic(t, P.t1, P.t2)
        local th, ax, az = 2 * math.pi * s, f.ax, f.az
        st.udx, st.udy, st.udz = rot(0, 1, 0, ax, 0, az, th)
        st.fdx, st.fdy, st.fdz = rot(f.f0x, 0, f.f0z, ax, 0, az, th)
        local wd, ad = 2 * math.pi * sd, 2 * math.pi * sdd
        st.wdx, st.wdy, st.wdz, st.affx, st.affy, st.affz = ax * wd, 0, az * wd, ax * ad, 0, az * ad
        if t > 0.8 and not f.lifted then return stop(false, "THRUST_NO_LIFT") end
        if t > P.T * 0.6 and (hm < 0.05 or (hm < 0.4 and vy > -0.25)) then return stop(true) end
        if t > 1 and (math.abs(h - hm) > 3 or t > P.T + 4) then setLand(f, hm) -- off its profile: land it
        elseif t > P.t2 and vy < landVy(hm) then setLand(f, hm) end -- upright, coming down too hard: soften it
    elseif ph == "boost" then
        local lv = v:getLinearVelocity(V3.lv)
        local gain = math.sqrt(lv:x() ^ 2 + lv:z() ^ 2) - f.v0
        if hm > 1.5 and vy < -2 then -- off an edge: over now, the driver's soft landing takes the fall (H.watch)
            local pl = f.player
            boostOver(f, v)
            return H.watch(pl, v)
        end
        if gain > 2 then f.lifted = true end
        -- stopped short once up to speed (r2f3-mp-d3 boostnearhold: into the support east of roof 1, asked to land at up
        -- -0.66 on its busy flag): over like any other boost, not "no lift"
        if t > 0.4 and gain < 1 then
            if f.lifted then return boostOver(f, v) end
            return stop(false, "THRUST_NO_LIFT")
        end
        if gain + f.v0 >= c.boostV or t > 1.5 then return boostOver(f, v) end
    elseif ph == "fly" then
        if f.wantLand or (f.sec and f.flown >= f.sec) then
            -- stop at its height first, gliding on at GLIDE_V over anything that would catch it (landClear)
            local psi = st.psiT
            setLand(f, hm)
            f.brake, f.brakeH, f.gdx, f.gdz, f.cx, f.cy, f.clear = true, hm, math.cos(psi), math.sin(psi), nil, nil, nil
        else
            f.flown = f.flown + real
            -- the motor off once the wheels are clear (oracle-flight2 Q1): a running motor's car hits what it flies
            -- through (r2scan: zombies lying under it held it 21.6 s); started again as it comes down (startBack)
            if not f.offAsked and hm > OFF_H and v:isEngineRunning() then
                local h = v:getPartById("Heater")
                local hd = h and h:getModData()
                f.offAsked, f.heat = true, hd and hd.active and tonumber(hd.temperature) or nil
                ISVehicleMenu.onShutOff(f.player) -- vanilla's 0 s action: vehicle:shutOff() on the server
            end
            -- a controller's player (BaseVehicle.java:4661-4668): as vanilla drives (CarController.java:958-967), the
            -- right stick for the height (pushed up: negative, PlayerCamera.java:148); with RB held it looks around
            -- instead (PlayerCamera.java:144-146)
            local pad = f.player:getJoypadBind()
            if pad ~= -1 then
                if not isJoypadRBPressed(pad) then
                    st.hG = clamp(st.hG - padAxis(getJoypadAimingAxisY(pad)) * c.flyClimb * dt, c.flyMinH, c.flyMaxH)
                end
            else
                if keyDown(KEYS.up) then st.hG = math.min(c.flyMaxH, st.hG + c.flyClimb * dt) end
                if keyDown(KEYS.down) then st.hG = math.max(c.flyMinH, st.hG - c.flyClimb * dt) end
            end
            local d = st.hG - st.hT
            local vRef = (d < 0 and -1 or 1) * math.min(HOVER_V, math.sqrt(2 * HOVER_A * math.abs(d)))
            st.ha = clamp(vRef - st.hv, -HOVER_A * dt, HOVER_A * dt) / dt
            st.hv = st.hv + st.ha * dt
            st.hT = st.hT + st.hv * dt
            if (st.hG - st.hT) * d < 0 then st.hT, st.hv, st.ha = st.hG, 0, 0 end -- not past the goal
            -- psi = atan2(world y, world x): turning right (clockwise on the map) raises it
            local yaw = math.rad(c.flyYaw) * dt
            local want
            if pad ~= -1 then -- RT ahead, LT back, the left stick steers
                want = isJoypadRTPressed(pad) and c.flyVmax or (isJoypadLTPressed(pad) and -c.flyVmax / 3 or 0)
                st.psiT = st.psiT + padAxis(getJoypadMovementAxisX(pad)) * yaw
            else
                local core = getCore()
                want = isKeyDown(core:getKey("Forward")) and c.flyVmax or (isKeyDown(core:getKey("Backward")) and -c.flyVmax / 3 or 0)
                if isKeyDown(core:getKey("Left")) then st.psiT = st.psiT - yaw end
                if isKeyDown(core:getKey("Right")) then st.psiT = st.psiT + yaw end
            end
            local step = c.flyAcc * dt
            f.spd = f.spd + clamp(want - f.spd, -step, step)
            st.vTx, st.vTz = math.cos(st.psiT) * f.spd, math.sin(st.psiT) * f.spd
            if t > 0.5 and not f.woke and not f.lifted and hm < 0.15 and v:getCurrentSpeedKmHour() < c.rollKmh then
                return wake(f) -- a working takeoff is up 0.4 m by now (r2fe-sp-g)
            end
            if t > 1 and not f.lifted then return stop(false, "THRUST_NO_LIFT") end
        end
    end
    if f.phase == "land" then
        st = f.st
        local u, fw = v:getUpVector(V3.u), v:getForwardVector(V3.f)
        local ux, uy, uz, fx, fz = u:x(), u:y(), u:z(), fw:x(), fw:z()
        local l = math.max(1e-6, math.sqrt(fx * fx + fz * fz))
        st.fdx, st.fdy, st.fdz = fx / l, 0, fz / l
        if uy < 0.1 then -- upside down: aim at a side first (straight up is no error direction from there)
            local rx, ry, rz = cross(ux, uy, uz, fx, fw:y(), fz)
            if ry < 0 then rx, ry, rz = -rx, -ry, -rz end
            st.udx, st.udy, st.udz = rx, ry, rz
        else
            st.udx, st.udy, st.udz = 0, 1, 0
        end
        st.rh = hm
        st.rvy = landVy(hm)
        -- the curve's own braking fed forward (d rvy/dt = 6 vy / rvy on it): the PD alone trailed it by 0.7-1.2 m/s
        -- and touched down at -2.7 (kickflip) / -3.2 (backflip) m/s (r2fe-sp-a, switching at 1.5 m)
        st.ray = (st.rvy > -8 and st.rvy < -0.7) and math.max(0, 6 * vy / st.rvy) or 0
        if hm < 0.05 or (hm < 0.4 and vy > -0.25) then return stop(f.lifted) end
        -- still up after LAND_S: over where it is, as at rest (RESTED: the watch's tilt branch asks no more; on its
        -- own, SP's busy cleared at once, it asked again and billed the tank twice: r2f3-sp-probe 6 of 30)
        if f.t > LAND_S then return stop(f.lifted, nil, nil, true) end
        local lv = v:getLinearVelocity(V3.lv)
        if f.brake then -- a flight's landing: held at its height, slowed to GLIDE_V; down once clear or after GLIDE_S
            if lv:x() ^ 2 + lv:z() ^ 2 <= (GLIDE_V * 1.1) ^ 2 then
                local cx, cy = math.floor(v:getX()), math.floor(v:getY())
                if cx ~= f.cx or cy ~= f.cy then f.cx, f.cy, f.clear = cx, cy, landClear(v) end -- a new square: look once
            end
            if not f.clear and f.t <= GLIDE_S then
                st.rh, st.rvy, st.ray = f.brakeH, 0, 0
                st.vTx, st.vTz = f.gdx * GLIDE_V, f.gdz * GLIDE_V
                return drive(f, v, dt, hm)
            end
            f.brake, f.sink, st.vTx, st.vTz = nil, true, 0, 0 -- coming down now, stopping where it is
            startBack(f, v, now)
        end
        local s = f.slide
        if s then -- lifted clear of what held it and carried the way it leans; then down again
            s.t = s.t + dt
            local dx, dy = v:getX() - s.x, v:getY() - s.y
            if dx * dx + dy * dy >= SLIDE_D * SLIDE_D or s.t > SLIDE_S then
                T.log(string.format("thrust carry vid=%d d=%.2f t=%.1f h=%.2f", f.vid, math.sqrt(dx * dx + dy * dy), s.t, hm))
                f.slide, f.restH, st.vTx, st.vTz = nil, nil, 0, 0
            else
                -- an absolute height: the floor under it (hm's) may change on the way
                st.rh, st.rvy, st.ray = hm + (s.z - v:getDebugZ()) * FLOOR, 0, 0
                st.vTx, st.vTz = s.dx * SLIDE_V, s.dz * SLIDE_V
                return drive(f, v, dt, hm)
            end
        end
        local p = f.probe
        if p then -- no push: does it stay put on its own? (the first PROBE_A s is the springs settling)
            p.t = p.t + dt
            if not p.h then
                if p.t >= PROBE_A - 1e-6 then p.h, p.ux, p.uy, p.uz = hm, ux, uy, uz end
            elseif p.t >= PROBE_B - 1e-6 then
                local dv = math.sqrt(lv:x() ^ 2 + vy * vy + lv:z() ^ 2)
                local dot = (ux * p.ux + uy * p.uy + uz * p.uz)
                    / math.max(1e-9, math.sqrt((ux * ux + uy * uy + uz * uz) * (p.ux ^ 2 + p.uy ^ 2 + p.uz ^ 2)))
                local moving = dv > REST_V or p.h - hm > PROBE_DH or dot < PROBE_DOT
                local sx, sz = ux, uz
                if sx * sx + sz * sz < 0.05 ^ 2 then sx, sz = lv:x(), lv:z() end
                local l = math.sqrt(sx * sx + sz * sz)
                T.log(string.format("thrust probe vid=%d dv=%.3f dh=%.3f dAng=%.2f h=%.2f dir=%.0f %s", f.vid, dv, p.h - hm,
                    math.deg(math.acos(math.min(1, dot))), hm, math.deg(math.atan2(sz, sx)), moving and "moving" or "at rest"))
                if not moving then return stop(f.lifted, nil, nil, true) end
                -- held up by its own push (a roof's edge): lifted off it and carried away, then down and probed again
                local t0 = f.t
                setLand(f, hm)
                f.t, f.probe = t0, nil
                if l > 1e-3 then
                    f.slide = { dx = sx / l, dz = sz / l, x = v:getX(), y = v:getY(), z = v:getDebugZ() + LIFT_DH / FLOOR, t = 0 }
                else f.noRest = true end -- no way to go: land on in place
            end
            return
        end
        if f.noRest or lv:x() ^ 2 + vy * vy + lv:z() ^ 2 > REST_V * REST_V or not f.restH or math.abs(hm - f.restH) > REST_DH then
            f.restH, f.restT = hm, 0
        else
            f.restT = f.restT + dt
            if f.restT >= REST_S then f.probe = { t = 0 } return end
        end
    end
    drive(f, v, dt, hm)
end

-- ---- asking ----
-- [pn] = { vid, act, n, ms }: what each local player asked and has no answer for yet (thrustOk, deny); after
-- ASK_MS it is as good as unanswered (thrustOk then gives the air back). The wall clock set back counts no time
local asked, ASK_MS = {}, 3000
local function pendingAsk(pn)
    local a = asked[pn]
    if not a then return nil end
    local now = getTimestampMs()
    if now < a.ms then a.ms = now end -- the wall clock set back: no time passed, the wait goes on from now
    if now - a.ms > ASK_MS then
        asked[pn] = nil
        return nil
    end
    return a
end
-- the number for this machine's next action: rising, also past a restart of the game (the wall clock)
local seq = 0
function H.nextN()
    seq = math.max(seq + 1, getTimestampMs())
    return seq
end

-- the client's side of the rules: H.can plus what only this machine sees. Optional app (`...`, as H.can): the phone
-- app's show (PhoneApp.lua asks before sending; the server gives this machine the physics only once it approves). An
-- action asked and not answered yet refuses another with no reason (nothing to say: the answer is on its way; the
-- soft landing aside: a fall can't wait)
local SPEED_MAX = { kickflip = "kickMaxKmh", backflip = "flipMaxKmh", boost = "boostMaxKmh" }
function H.check(player, v, act, ...)
    local app = ...
    H.groundReset() -- the floors read afresh: one built under the car since the last action counts
    if F then return false, "THRUST_BUSY" end
    if act ~= "land" and not app and pendingAsk(player:getPlayerNum()) then return false end
    local o, b = OFF_EDGE, act == "land" and busyOf(v)
    local mine = o and o.vid == v:getId() and type(b) == "table" and b.act == "boost" and b.t == o.t and b or nil
    local ok, why = H.can(player, v, act, app, true, mine)
    if not ok then return false, why end
    if not app and not authority(v) then return false, "THRUST_AUTHORITY" end
    local c = H.conf(v)
    if act ~= "land" then
        if heightOf(v, RESTS[v:getId()] or c.rest) > 0.4 then return false, "THRUST_AIRBORNE" end
        local kmh = v:getCurrentSpeedKmHour()
        if kmh < -1 then return false, "THRUST_REVERSE" end
        local max = SPEED_MAX[act]
        if max and kmh > c[max] then return false, "THRUST_FAST" end
    end
    if PROF[act] and not clearPath(v, c, act) then return false, "THRUST_ROOM" end
    if act == "fly" and not clearAbove(v, c) then return false, "THRUST_ROOM" end
    return true
end
-- the tank as this machine sees it, 0-1 (flying: what is left of the approved seconds); nil: no thrusters or off
function H.air(v)
    if not H.conf(v) or not H.enabled() then return nil end
    local f = F
    if f and f.v == v and f.act == "fly" and f.sec then return clamp((f.sec - f.flown) / H.flightSeconds(), 0, 1) end
    local part = T.Battery.part(v)
    return H.gasNow(part and part:getModData().thr, T.hours())
end
-- why refused, in words; THRUST_NO_AIR adds when this car's tank is full again (v may be nil: a car not loaded here)
function H.whyText(v, why)
    local s = T.denyText(why)
    local a = why == "THRUST_NO_AIR" and v and H.air(v)
    if a and a < 1 then s = s .. " " .. getText("IGUI_MinidoracatTesla_Thrust_Refill", tostring(H.minutesToFull(a))) end
    return s
end

function H.ask(player, v, act)
    local f = F
    if act == "fly" and f and f.v == v and f.act == "fly" then f.wantLand = true return true end -- the second press lands
    local ok, why = H.check(player, v, act)
    if not ok then
        if why then HaloTextHelper.addBadText(player, H.whyText(v, why)) end
        return false
    end
    local n = H.nextN()
    local pn = player:getPlayerNum()
    -- a soft landing names the unanswered ask of this car it takes over, or the boost this machine just ended off an
    -- edge (server Thruster.lua cmds.thrust ends only that one)
    local prev, o = act == "land" and pendingAsk(pn), OFF_EDGE
    OFF_EDGE = nil
    local over = prev and prev.vid == v:getId() and prev.n or nil
    if act == "land" and not over and o and o.vid == v:getId() then over = o.n end
    -- falling: no time to wait for the server (it bills after; a refusal stops it, the deny below)
    if act == "land" then start(player, v, act, nil, nil, n) end
    asked[pn] = { vid = v:getId(), act = act, n = n, ms = getTimestampMs() }
    T.request(player, "thrust", { vid = v:getId(), act = act, n = n, over = over })
    return true
end

-- args { vid, act, sec, n, pn, app }: approved for the local player pn. app: the phone app's show this machine's
-- player called (server Thruster.lua go: the physics is on its way)
T.ClientCommands.thrustOk = function(args)
    local pn = args.pn or 0
    local player = getSpecificPlayer(pn) or getSpecificPlayer(0)
    local a = pendingAsk(pn)
    if a and a.n == args.n then asked[pn] = nil else a = nil end
    local f = F
    local v = getVehicleById(args.vid)
    local function back() -- too late or no longer possible here: the air back
        T.request(player, "thrustEnd", { vid = args.vid, act = args.act, done = false, sec = 0, n = args.n })
    end
    if args.app then
        if f or not v or v:getDriver() then return back() end
        return start(player, v, args.act, nil, "show", args.n)
    end
    if f and f.n == args.n then -- the soft landing, already under way
        f.ok = true
        return
    end
    -- the driver's own action approved while the soft landing it fell into is not yet: the server ends that one
    -- itself when the landing reaches it (server Thruster.lua cmds.thrust); a thrustEnd now would hand the car on
    if f and f.act == "land" and not f.ok and f.vid == args.vid then return end
    if not a or f or not v or not v:isDriver(player) or not authority(v) then return back() end
    start(player, v, args.act, args.sec, nil, args.n)
    F.ok = true
end

-- args { vid, pn, n, term }: the server handed this player's machine a car left in the air (its holder's game went
-- quiet, or it said it could not go on): land it, driver or not. Can't here: say so at once, the server hands it to
-- the next one. Its thrustEnd carries term: the server tells this hand-over's end from an earlier one's
T.ClientCommands.thrustLand = function(args)
    local player = getSpecificPlayer(args.pn or 0) or getSpecificPlayer(0)
    local v = getVehicleById(args.vid)
    if F or not v or not H.conf(v) then
        return T.request(player, "thrustEnd", { vid = args.vid, act = "land", done = false, abort = true, n = args.n,
            term = args.term })
    end
    start(player, v, "land", nil, "help", args.n, args.term)
end

-- a refusal of this machine's action n (server Thruster.lua deny): its ask is answered, and a soft landing started
-- before the answer stops here, nothing more said (the server kept nothing of it). Then why, as the ring says it
-- (H.whyText). A refusal without n is some other command's about the car (T.deny): no answer to an ask here, the
-- usual message (Net.lua)
local baseDeny = T.ClientCommands.deny
T.ClientCommands.deny = function(args)
    if type(args) == "table" and type(args.n) == "number" then
        local pn = args.pn or 0
        local a = asked[pn]
        if a and a.n == args.n then asked[pn] = nil end
        local f = F
        if f and f.n == args.n and not f.ok then
            halt()
            -- a landing refused: the watch's tilt branch (no vy past 53 degrees) asks no more for this car at rest
            if f.act == "land" then RESTED[f.vid] = true end
        end
        local p = getSpecificPlayer(pn) or getSpecificPlayer(0)
        if p then HaloTextHelper.addBadText(p, H.whyText(args.vid and getVehicleById(args.vid), tostring(args.reason))) end
        return
    end
    return baseDeny(args)
end

-- HUD.lua, each dashboard update (10 Hz) of a car with thrusters: notes where it rests on the ground, and catches a
-- fall (off a roof, a stunt gone wrong) to land it softly when there is air for it. A car tipping nose-first over an
-- edge slides down the wall under it slower than a fall (r2int-sp-full roof 1 #1: -1.9 m/s at most, on its nose
-- after): tilted past 37 degrees and coming down over the drop counts too, past 53 at any speed (r2f3-mp-c boostnear:
-- rolling over on a fence top at -0.1 m/s, asked only at up 0)
function H.watch(player, v)
    if F or not v:isDriver(player) then return end
    local c = H.conf(v)
    if not c then return end
    local vid = v:getId()
    local vy = v:getLinearVelocity(V3.lv):y()
    local hm = heightOf(v, RESTS[vid] or c.rest)
    if hm < 0.2 and math.abs(vy) < 0.05 then
        RESTS[vid] = clamp(v:getDebugZ() - groundZ(v), 0.02, 0.25)
        RESTED[vid] = nil
    elseif ((hm > 1.5 and vy < -2) or (hm > 1 and not RESTED[vid] and v:getUpVector(V3.u):y() < (vy < -0.5 and 0.8 or 0.6)))
        and (H.air(v) or 0) >= H.COST.land and H.check(player, v, "land") then
        H.ask(player, v, "land")
    end
end

-- ---- the radial ring (HUDRadial.lua adds the entry slice) ----
local ACTS = { "kickflip", "backflip", "boost", "fly" }
local NAME = { kickflip = "Kickflip", backflip = "Backflip", boost = "Boost", fly = "Fly" }
local function line2(s) return "\n" .. T.wrapText(s, 220, UIFont.Medium) end -- the ring's width (HUDRadial.lua LINE_W)
local function onAct(player, v, act) H.ask(player, v, act) end
-- how to fly, with the keys bound now (the up / down binds; vanilla's exit, the Interact key: getting out lands it,
-- ISVehicleMenu.onExit below); a controller's player: the controller's way
function H.flyTip(player)
    if player:getJoypadBind() ~= -1 then return getText("IGUI_MinidoracatTesla_Tip_ThrustFlyPad") end
    local up, down = KEYS.up, KEYS.down
    return getText("IGUI_MinidoracatTesla_Tip_ThrustFly", getKeyName(up and up:getValue() or 0),
        getKeyName(down and down:getValue() or 0), getKeyName(getCore():getKey("Interact")))
end

function H.openRing(player, v)
    local pn = player:getPlayerNum()
    local menu = getPlayerRadialMenu(pn)
    menu:clear()
    local f = F
    for _, act in ipairs(ACTS) do
        local id = NAME[act]
        local title = getText("IGUI_MinidoracatTesla_Radial_Thrust" .. id)
        if act == "fly" and f and f.v == v and f.act == "fly" then
            menu:addSlice(getText("IGUI_MinidoracatTesla_Radial_ThrustLand"), getTexture(TEX .. "radial_thrust_land.png"), onAct, player, v, act)
        else
            local ok, why = H.check(player, v, act)
            if ok then
                menu:addSlice(title .. line2(act == "fly" and H.flyTip(player) or getText("IGUI_MinidoracatTesla_Tip_Thrust" .. id)),
                    getTexture(TEX .. "radial_thrust_" .. act .. ".png"), onAct, player, v, act)
            else -- no reason: an ask waits for its answer (H.check)
                menu:addSlice(why and title .. line2(H.whyText(v, why)) or title, getTexture(TEX .. "radial_thrust_" .. act .. "_off.png"), nil)
            end
        end
    end
    -- placed and shown like vanilla's own (ISVehicleMenu.lua:78-79,232-241)
    menu:setX(getPlayerScreenLeft(pn) + getPlayerScreenWidth(pn) / 2 - menu:getWidth() / 2)
    menu:setY(getPlayerScreenTop(pn) + getPlayerScreenHeight(pn) / 2 - menu:getHeight() / 2)
    menu:addToUIManager()
    if JoypadState.players[pn + 1] then
        setJoypadFocus(pn, menu)
        player:setJoypadIgnoreAimUntilCentered(true)
    end
end

function H.radialSlice(menu, player, v)
    if not H.conf(v) or not v:isDriver(player) then return end
    local f = F
    if f and f.v == v and f.act == "fly" then -- flying: the quickest way down (the second fly press lands it, H.ask)
        return menu:addSlice(getText("IGUI_MinidoracatTesla_Radial_ThrustLand"), getTexture(TEX .. "radial_thrust_land.png"),
            onAct, player, v, "fly")
    end
    local a = H.air(v)
    local sub = a and getText("IGUI_MinidoracatTesla_Tip_ThrustAir", tostring(math.floor(a * 100))) or T.denyText("THRUST_OFF")
    menu:addSlice(getText("IGUI_MinidoracatTesla_Radial_Thrusters") .. line2(sub), getTexture(TEX .. "radial_thrust.png"),
        H.openRing, player, v)
end

-- ---- key binds (keyboard; the mod's options page; ids are in players' ModOptions.ini: never rename them) ----
if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.getOptions then
    local o = PZAPI.ModOptions:getOptions(T.MODULE)
    if o then
        o:addTitle("IGUI_MinidoracatTesla_Radial_Thrusters")
        KEYS.kickflip = o:addKeyBind("ThrustKickflip", "IGUI_MinidoracatTesla_Radial_ThrustKickflip", Keyboard.KEY_NONE)
        KEYS.backflip = o:addKeyBind("ThrustBackflip", "IGUI_MinidoracatTesla_Radial_ThrustBackflip", Keyboard.KEY_NONE)
        KEYS.boost = o:addKeyBind("ThrustBoost", "IGUI_MinidoracatTesla_Radial_ThrustBoost", Keyboard.KEY_NONE)
        KEYS.fly = o:addKeyBind("ThrustFly", "IGUI_MinidoracatTesla_Key_ThrustFly", Keyboard.KEY_NONE)
        KEYS.up = o:addKeyBind("ThrustUp", "IGUI_MinidoracatTesla_Key_ThrustUp", Keyboard.KEY_PRIOR)
        KEYS.down = o:addKeyBind("ThrustDown", "IGUI_MinidoracatTesla_Key_ThrustDown", Keyboard.KEY_NEXT)
    end
end
H.KEYS = KEYS

Events.OnKeyPressed.Add(function(key)
    if key == 0 then return end
    local act
    for _, a in ipairs(ACTS) do
        local o = KEYS[a]
        if o and o:getValue() == key then act = a break end
    end
    if not act then return end
    local p -- the keyboard's player: the one split-screen player without a controller
    for pn = 0, getNumActivePlayers() - 1 do
        local q = getSpecificPlayer(pn)
        if q and not JoypadState.players[pn + 1] then p = q break end
    end
    local v = p and p:getVehicle()
    if v and H.conf(v) then H.ask(p, v, act) end
end)

-- no getting out mid-air: the car is this machine's to fly until it lands. Flying, getting out (vanilla's exit: a
-- controller's A, ISButtonPrompt.lua:444; the Interact key, Vehicles.lua OnUseVehicle) lands it instead.
-- At rest off the ground after (another car's roof, an eave), vanilla's way out from the seat runs into what holds it
-- up (isExitBlocked, BaseVehicle.java:6669-6699: lineClearCollide on the car's floor; r2rest-mp-near2: both seats, no
-- seat to switch to) and nothing else may move it (THRUST_AIRBORNE): out as vanilla's onExitAux, without that check
-- (ISExitVehicle puts the player at the seat's outside spot on the car's floor, setCharacterPosition)
local function exitUp(p, v, seat)
    local part = v:getPassengerDoor(seat)
    local door = part and part:getInventoryItem() and part:getDoor()
    if door and door:isLocked() then ISTimedActionQueue.add(ISUnlockVehicleDoor:new(p, part)) end
    if door and not door:isOpen() then ISTimedActionQueue.add(ISOpenVehicleDoor:new(p, v, part)) end
    ISTimedActionQueue.add(ISExitVehicle:new(p))
    if door then ISTimedActionQueue.add(ISCloseVehicleDoor:new(p, v, part)) end
end
local origExit = ISVehicleMenu.onExit
function ISVehicleMenu.onExit(playerObj, seatFrom)
    local f = F
    if f and f.player == playerObj then
        if f.act == "fly" and f.phase ~= "land" then
            f.wantLand = true
            return
        end
        HaloTextHelper.addBadText(playerObj, T.denyText("THRUST_IN_AIR"))
        return
    end
    local v = playerObj:getVehicle()
    local c = v and H.conf(v)
    if c and heightOf(v, RESTS[v:getId()] or c.rest) > 0.4 and v:isStopped() then
        local seat = seatFrom or v:getSeat(playerObj)
        if v:isExitBlocked(playerObj, seat) and not ISVehicleMenu.getBestSwitchSeatExit(playerObj, v, seat) then
            return exitUp(playerObj, v, seat)
        end
    end
    return origExit(playerObj, seatFrom)
end
