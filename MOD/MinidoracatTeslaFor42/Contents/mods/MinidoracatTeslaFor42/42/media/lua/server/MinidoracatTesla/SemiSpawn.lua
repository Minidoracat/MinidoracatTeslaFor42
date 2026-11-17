-- The Semi and its 53 ft trailer in the world (plan-semi-1117, user ruling 2026-11-18: our own spawn, option c), each on
-- its own, never hitched. Not through VehicleZoneDistribution: vanilla puts a car's centre in a 3 x 5 stall and never
-- looks at its tail or at walls (IsoChunk.AddVehicles_OnZone :940-1117, doSpawnedVehiclesInInvalidPosition :1239-1267),
-- so of the 16,417 parkingstall stalls on the vanilla map only 39 hold a 6.5-square Semi and 32 the 13.3-square trailer
-- inside their zone (Muldraugh, KY/objects.lua, the one zone file of the vanilla map; it has no "delivery" zone at all).
-- Instead, on the server only:
-- - map load: vanilla doMapZones registers each parking zone (metazoneHandler.lua:120,143); a wrap of
--   registerVehiclesZone keeps the parkingstall ones long enough for each car (the same wrap VehicleSpawnControl uses,
--   MVSC_Respawn.lua:55-73): 1,563 lots for the Semi and 1,293 for the trailer on the vanilla map.
-- - each lot's roll is a hash of the lot and a per-world seed: the same lot gets the same roll in every session, so a
--   lot is rolled once and the misses need no record. Sandbox SemiSpawnChance (% of the lots, default 1.5, 0 = none):
--   a simulated estimate of about 23 Semis and 19 trailers on the whole vanilla map, before the lots with no room.
-- - LoadChunk (new chunks and the save's, so explored worlds get them too, like SuperchargerSpawn.lua): one table
--   lookup; a lot that rolled a hit and is not done yet is queued.
-- - EveryOneMinute, only while the queue has something: on a dedicated server SETTLE after its chunk loaded (it reads
--   the chunk's saved cars after LoadChunk, ServerMap.java:827-838, VehiclesDB2.java:346-351,494-525: the wait
--   VehicleSpawnControl measured, MVSC_Respawn.lua:5-7,565, and waits on a dedicated server only); in single player
--   the next game minute (a driver is there within 15 s and would see it appear). Once every square the check reads
--   is loaded, it looks for a free stretch along the lot's long axis, middle first, and puts the car there
--   (addVehicleDebug, as VehicleSpawnControl does). Placed or no room, the lot is done for good: ModData keeps only
--   the lots that rolled a hit (at most every candidate lot, ~2,900 on the vanilla map, so it cannot keep growing).
if isClient() then return end
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local S = {}
T.SemiSpawn = S

S.MODDATA = "MinidoracatTeslaSemiSpawn"
S.RULES = 1           -- the rules' version, kept with every done lot
S.SETTLE_MS = 15000   -- after the chunk loads, dedicated server only (VehicleSpawnControl's SETTLE_MP)
S.TTL_MS = 300000     -- a lot whose squares do not all load in this long leaves the queue; its next load queues it again
S.RECENT_MS = 60000   -- a car just placed is not in its chunk's vehicle list for a few frames (MVSC_Respawn.lua:24)
S.CARS = {
    { key = "semi", script = "Base.MinidoracatTesla_Semi" },
    { key = "trailer", script = "Base.MinidoracatTesla_SemiTrailer" },
}
S.zones = {}   -- { x, y, w, h } parkingstall zones at z 0, as registered
S.byChunk = {} -- [chunk key] = { zone index, car index, ... } candidate lots touching that chunk
S.queue = {}   -- [lot key] = { zi, ci, at (ms) }
S.known = {}   -- [lot key] = true: done in the save, seen this session (LoadChunk skips it without ModData)
S.recent = {}  -- { x0, y0, x1, y1, ms } footprints placed lately
local ORIG_KEY = "MinidoracatTesla_SemiSpawn_registerVehiclesZone"
local seenRect = {}

local function chunkKey(wx, wy) return wx * 100000 + wy end
function S.lotKey(z, car) return z.x .. "," .. z.y .. "," .. z.w .. "," .. z.h .. "," .. car.key end

local function md()
    local t = ModData.getOrCreate(S.MODDATA)
    t.done = t.done or {}
    if not t.seed then t.seed = ZombRand(1000000000) + 1 end
    t.v = S.RULES
    return t
end

-- ---- the lots ----
-- the parkingstall zones (name "" takes the type, IsoChunk.java:1747-1750; the engine lowercases it, VehicleType.java:173)
function S.indexZone(name, kind, x, y, z, w, h)
    if z ~= 0 then return end
    local n = (name ~= nil and name ~= "") and name or kind
    if n == nil or string.lower(n) ~= "parkingstall" then return end
    local rect = x .. "," .. y .. "," .. w .. "," .. h
    if seenRect[rect] then return end -- checkVehiclesZones drops a zone the same as another (IsoMetaGrid.java:880-921)
    seenRect[rect] = true
    S.zones[#S.zones + 1] = { x = x, y = y, w = w, h = h }
end

-- the wrap (the method table is __classmetatables[class].__index; ORIG_KEY: a Lua reload does not wrap it twice)
function S.installZoneIndex()
    local cls = IsoWorld and IsoWorld.class
    local mt = cls and __classmetatables and __classmetatables[cls]
    local methods = mt and mt.__index
    local orig = methods and (rawget(methods, ORIG_KEY) or methods.registerVehiclesZone)
    if orig == nil then return false end
    rawset(methods, ORIG_KEY, orig)
    methods.registerVehiclesZone = function(world, name, kind, x, y, z, w, h, props)
        local zone = orig(world, name, kind, x, y, z, w, h, props)
        if zone then
            local ok, err = pcall(S.indexZone, name, kind, x, y, z, w, h)
            if not ok then S.indexError = tostring(err) end
        end
        return zone
    end
    return true
end

-- each car's body as the engine boxes it: the extents centred on the centre of mass offset (VehiclePoly.java:52-88),
-- the offset added on both sides (VehicleSpawnControl's MVSC_Respawn.lua:377-379). A lot fits a car when its long
-- side holds the body and it is 3 or more wide (a stall's width).
function S.buildIndex()
    S.byChunk = {}
    local lots = {}
    for ci, car in ipairs(S.CARS) do
        local vs = ScriptManager.instance:getVehicle(car.script)
        if vs then
            local ext, com = vs:getExtents(), vs:getCenterOfMassOffset()
            car.len, car.wid = ext:z() + 2 * math.abs(com:z()), ext:x() + 2 * math.abs(com:x())
            car.half = math.ceil(car.len / 2)
        end
        lots[ci] = 0
        for zi, z in ipairs(S.zones) do
            if car.half and math.max(z.w, z.h) >= 2 * car.half and math.min(z.w, z.h) >= 3 then
                lots[ci] = lots[ci] + 1
                for wx = math.floor(z.x / 8), math.floor((z.x + z.w - 1) / 8) do
                    for wy = math.floor(z.y / 8), math.floor((z.y + z.h - 1) / 8) do
                        local k = chunkKey(wx, wy)
                        local list = S.byChunk[k] or {}
                        list[#list + 1] = zi
                        list[#list + 1] = ci
                        S.byChunk[k] = list
                    end
                end
            end
        end
    end
    T.log("semi spawn: " .. #S.zones .. " parking zones, lots for the Semi " .. lots[1] .. ", for the trailer " .. lots[2]
        .. (S.installed and "" or " (zone wrap NOT installed: " .. tostring(S.indexError or "IsoWorld method table not found") .. ")"))
end

-- the lot's roll in [0, 1): Park-Miller over the lot and the world's seed (all within 2^53, exact in a double)
function S.roll(z, ci, seed)
    local h = (z.x * 92821 + z.y * 68917 + z.w * 331 + z.h * 337 + ci * 7919 + seed) % 2147483647
    for _ = 1, 3 do h = (h * 48271) % 2147483647 end
    return h / 2147483647
end

-- ---- the squares ----
-- free for a parked truck: outdoor solid floor with nothing on it but the floor (no wall, fence, door, tree, sign,
-- litter, furniture or anything a player built or dropped), no car (isVehicleIntersecting, IsoGridSquare.java:9853-9874),
-- nobody but zombies (as vanilla, a car may spawn on one), no body, not water and in no safehouse (SafeHouse.getSafeHouse:
-- the one holding the square, whoever the player, SafeHouse.java:157-159)
function S.free(sq)
    if not sq or not sq:isSolidFloor() or not sq:isOutside() or sq:isWaterSquare() then return false end
    local objs = sq:getObjects()
    if objs:size() ~= 1 or objs:get(0) ~= sq:getFloor() then return false end
    if sq:isVehicleIntersecting() or sq:getDeadBody() ~= nil then return false end
    local mov = sq:getMovingObjects()
    for i = 0, mov:size() - 1 do
        if not instanceof(mov:get(i), "IsoZombie") then return false end
    end
    return SafeHouse.getSafeHouse(sq) == nil
end

-- addVehicleDebug puts the car's centre on the square's north-west corner and turns it up to 0.2 rad off its heading
-- (LuaManager.java addVehicleDebug): the body's box widened by that turn and 0.3 (MVSC_Respawn.lua:200-208)
function S.footprint(cx, cy, dir, len, wid)
    local hx, hy = wid / 2, len / 2
    if dir == "W" or dir == "E" then hx, hy = len / 2, wid / 2 end
    local ex, ey = hx + 0.2 * hy + 0.3, hy + 0.2 * hx + 0.3
    return math.floor(cx - ex), math.floor(cy - ey), math.floor(cx + ex), math.floor(cy + ey)
end

-- every chunk under x0..x1, y0..y1 loaded (SuperchargerSpawn.lua's loaded)
local function loaded(x0, y0, x1, y1)
    local cell = getCell()
    for cx = math.floor(x0 / 8), math.floor(x1 / 8) do
        for cy = math.floor(y0 / 8), math.floor(y1 / 8) do
            if not cell:getChunkForGridSquare(cx * 8, cy * 8, 0) then return false end
        end
    end
    return true
end

local function recentOverlap(x0, y0, x1, y1, now)
    for i = #S.recent, 1, -1 do
        local r = S.recent[i]
        if now - r[5] >= S.RECENT_MS then table.remove(S.recent, i)
        elseif x0 <= r[3] and r[1] <= x1 and y0 <= r[4] and r[2] <= y1 then return true end
    end
    return false
end

-- ---- the car ----
-- addVehicleDebug makes it as good as new (parts setGeneralPartCondition(1.3, 10), rust 0). As VehicleSpawnControl's
-- R.naturalize (MVSC_Respawn.lua:258-280): the parkingstall zone and type, each part's setRandomCondition by them
-- (VehiclePart.java setRandomCondition), rust by the zone's baseVehicleQuality, the alarm by sandbox CarAlarm as
-- AddVehicles_OnZone (:1008-1031; a trailer has no engine to sound it). Not its re-run of the part creates: ours ran in
-- addToWorld already (the charge, the paint, the Mobile Connector and phone, Battery.lua) and would add the gifts twice.
-- The key: the engine rolls it in addToWorld (MVSC_Respawn.lua:262). Tyres full (user 2026-11-18): the vanilla tyre
-- create leaves them at 67-100% (Vehicles.lua Create.Tire).
function S.naturalize(v)
    v:setZone("parkingstall")
    v:setVehicleType("parkingstall")
    local def = VehicleZoneDistribution and VehicleZoneDistribution.parkingstall
    local q = def and tonumber(def.baseVehicleQuality) or 0.7
    if v:getPartById("Engine") then
        local alarm = ({ -1, 3, 8, 15, 25, 50 })[SandboxVars.CarAlarm or 4] or 15
        if ZombRand(100) < alarm then v:setAlarmed(true) end
    end
    for i = 0, v:getPartCount() - 1 do
        local part = v:getPartByIndex(i)
        part:setRandomCondition(part:getInventoryItem())
        if part:getWheelIndex() ~= -1 and part:getContainerCapacity() > 0 then
            part:setContainerContentAmount(part:getContainerCapacity(), false, true)
        end
    end
    v:setRust(ZombRand(100) < 100 - math.min(q * 120, 100) and 1 or 0)
end

-- one lot: "placed", "noroom", or "wait" (squares not loaded yet)
function S.place(z, car, now)
    local alongX = z.w >= z.h
    local lo = (alongX and z.x or z.y) + car.half
    local hi = (alongX and z.x + z.w or z.y + z.h) - car.half
    local mid = alongX and z.y + math.floor(z.h / 2) or z.x + math.floor(z.w / 2)
    -- isVehicleIntersecting looks 4 squares past the square (IsoGridSquare.java:9853-9874)
    local reach = math.ceil(car.len * 0.6 + 0.3) + 4
    if alongX then
        if not loaded(lo - reach, mid - reach, hi + reach, mid + reach) then return "wait" end
    elseif not loaded(mid - reach, lo - reach, mid + reach, hi + reach) then return "wait" end
    local dir = alongX and (ZombRand(2) == 0 and "E" or "W") or (ZombRand(2) == 0 and "S" or "N")
    local cell, seen = getCell(), {}
    local function fits(x0, y0, x1, y1)
        for x = x0, x1 do
            for y = y0, y1 do
                local k = x * 100000 + y
                if seen[k] == nil then seen[k] = S.free(cell:getGridSquare(x, y, 0)) end
                if not seen[k] then return false end
            end
        end
        return not recentOverlap(x0, y0, x1, y1, now)
    end
    local c = math.floor((lo + hi) / 2)
    for d = 0, hi - lo do
        for _, p in ipairs(d == 0 and { c } or { c + d, c - d }) do
            if p >= lo and p <= hi then
                local cx, cy = p, mid
                if not alongX then cx, cy = mid, p end
                local x0, y0, x1, y1 = S.footprint(cx, cy, dir, car.len, car.wid)
                if fits(x0, y0, x1, y1) then
                    local v = addVehicleDebug(car.script, IsoDirections[dir], nil, cell:getGridSquare(cx, cy, 0))
                    -- a car it could not put down still comes back, never in the world: sqlId -1 (MVSC_Respawn.lua:316)
                    if not v or v:getSqlId() == -1 then return "noroom" end
                    S.naturalize(v)
                    S.recent[#S.recent + 1] = { x0, y0, x1, y1, now }
                    T.log("semi spawn: " .. car.key .. " at " .. cx .. "," .. cy .. " facing " .. dir .. " in the lot "
                        .. S.lotKey(z, car))
                    return "placed"
                end
            end
        end
    end
    T.log("semi spawn: no room for the " .. car.key .. " in the lot " .. S.lotKey(z, car))
    return "noroom"
end

-- ---- the queue ----
-- each game minute while a lot waits (no tick: AGENTS.md rule 2), one lot at most; unhooks itself when none is left
local hooked = false
local function tick()
    local t, now = md(), getTimestampMs()
    local drop, due = {}, nil
    for k, q in pairs(S.queue) do
        if t.done[k] then drop[#drop + 1] = k; S.known[k] = true
        elseif now - q.at > S.TTL_MS then drop[#drop + 1] = k
        elseif not due and now - q.at >= (isServer() and S.SETTLE_MS or 0) then due = k end
    end
    for _, k in ipairs(drop) do S.queue[k] = nil end
    if due then
        local q = S.queue[due]
        local ok, res = pcall(S.place, S.zones[q.zi], S.CARS[q.ci], now)
        if not ok then T.log("semi spawn: error " .. tostring(res)); res = "error" end
        -- done before anything else: an error half way does not put a second car down later
        if res ~= "wait" then
            t.done[due] = S.RULES
            S.known[due] = true
            S.queue[due] = nil
        end
    end
    for _ in pairs(S.queue) do return end
    Events.EveryOneMinute.Remove(tick)
    hooked = false
end
S.tick = tick

-- IsoChunk has no wx / wy Lua can read: its first square's position (MVSC_Respawn.lua:517-524)
local function chunkOrigin(chunk)
    for x = 0, 7 do
        for y = 0, 7 do
            local sq = chunk:getGridSquare(x, y, 0)
            if sq then return sq:getX() - x, sq:getY() - y end
        end
    end
end

-- LoadChunk (IsoChunk.java:3968; a chunk of the save or a new one): the lots here that rolled a hit
function S.onLoadChunk(chunk)
    local ox, oy = chunkOrigin(chunk)
    if not ox then return end
    local list = S.byChunk[chunkKey(math.floor(ox / 8), math.floor(oy / 8))]
    if not list then return end
    local pct = T.semiSpawnPct()
    if pct <= 0 then return end
    local seed = md().seed
    for i = 1, #list, 2 do
        local zi, ci = list[i], list[i + 1]
        local z, car = S.zones[zi], S.CARS[ci]
        local k = S.lotKey(z, car)
        if not S.known[k] and not S.queue[k] and S.roll(z, ci, seed) * 100 < pct then
            S.queue[k] = { zi = zi, ci = ci, at = getTimestampMs() }
            if not hooked then
                hooked = true
                Events.EveryOneMinute.Add(tick)
            end
        end
    end
end

S.installed = S.installZoneIndex()
Events.OnLoadedMapZones.Add(S.buildIndex)
Events.LoadChunk.Add(S.onLoadChunk)
