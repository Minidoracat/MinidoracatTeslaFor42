-- The Semi and its 53 ft trailer in the world (plan-semi-1117, user ruling 2026-11-18: our own spawn, option c), each on
-- its own, never hitched. Not through VehicleZoneDistribution: vanilla puts a car's centre in a 3 x 5 stall and never
-- looks at its tail or at walls (IsoChunk.AddVehicles_OnZone :940-1117, doSpawnedVehiclesInInvalidPosition :1239-1267),
-- so of the 16,417 parkingstall stalls on the vanilla map only 39 hold a 6.5-square Semi and 32 the 13.3-square trailer
-- inside their zone (Muldraugh, KY/objects.lua, the one zone file of the vanilla map; it has no "delivery" zone at all).
-- Instead, on the server only:
-- - map load: vanilla doMapZones registers each parking zone (metazoneHandler.lua:120,143); a wrap of
--   registerVehiclesZone keeps the parkingstall ones long enough for each car (the same wrap VehicleSpawnControl uses,
--   MVSC_Respawn.lua:55-73): 1,563 lots for the Semi (8 squares or longer) and 1,293 for the trailer (15 or longer:
--   the squares its body covers with the margin, S.box) on the vanilla map (7,668 parkingstall zones at z 0 once
--   duplicates are dropped).
-- - each lot's roll is a hash of the lot and the world generation seed (S.seed): the same lot gets the same roll in
--   every session, so a lot is rolled once and the misses need no record. Sandbox SemiSpawnChance (% of the lots,
--   default 1.5, 0 = none; the trailer's lots at twice it, S.CARS mul): about 23 Semis and 39 trailers on the whole
--   vanilla map (the lots x the chance), before the lots with no room.
-- - LoadChunk (new chunks and the save's, so explored worlds get them too, like SuperchargerSpawn.lua): one table
--   lookup; a lot that rolled a hit and is not done yet is queued.
-- - EveryOneMinute, only while the queue has something: the lot's roll again at today's chance (turned down, the
--   queued ones go too), then the lots whose squares are all loaded, oldest first, until one is placed or has no room.
--   On a dedicated server a lot waits SETTLE from the first minute all its chunks are seen loaded, again if one
--   unloads (the server reads a chunk's saved cars after LoadChunk, ServerMap.java:827-838, VehiclesDB2.java:346-351,
--   494-525: the wait VehicleSpawnControl measured, MVSC_Respawn.lua:5-7,565); in single player none (a driver is
--   there within 15 s and would see it appear). It looks for a free stretch along the lot's long axis, middle first,
--   facing a random way along it, and puts the car there (addVehicleDebug, as VehicleSpawnControl does), turned
--   square to the lot. Placed, no room, or the same car already
--   standing in the lot, the lot is done for good: ModData keeps only the lots that rolled a hit (at most every
--   candidate lot, ~2,900 on the vanilla map).
-- shortcut: the done mark is in global ModData and the car in vehicles.db, saved apart; after a crash between the two
-- saves the car found in its lot stands for the lost mark, but one driven out of the lot before the crash is not seen,
-- and the lot gets a second car next session.
if isClient() then return end
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local S = {}
T.SemiSpawn = S

S.MODDATA = "MinidoracatTeslaSemiSpawn"
S.RULES = 1           -- the rules' version, kept with every done lot
S.SETTLE_MS = 15000   -- after all the lot's chunks are seen loaded, dedicated server only (VehicleSpawnControl's SETTLE_MP)
S.TTL_MS = 300000     -- a lot whose squares do not all load in this long leaves the queue; its next load queues it again
S.RECENT_MS = 60000   -- a car just placed is not in its chunk's vehicle list for a few frames (MVSC_Respawn.lua:24)
S.NEAR = 10           -- how far a parked car's body reaches from its position: our trailer's 9.61 (S.box, measured)
S.MARGIN = 0.3        -- round the body's box (VehicleSpawnControl's footprint, MVSC_Respawn.lua:200-208)
S.CARS = {
    { key = "semi", script = "Base.MinidoracatTesla_Semi" },
    -- mul 2 (user 2026-11-18): at the same chance about half as many trailers as Semis were left once the lots with
    -- no room were out (23 to 11, the vanilla map at 1.5%)
    { key = "trailer", script = "Base.MinidoracatTesla_SemiTrailer", mul = 2 },
}
S.zones = {}   -- { x, y, w, h } parkingstall zones at z 0, as registered
S.byChunk = {} -- [chunk key] = { zone index, car index, ... } candidate lots touching that chunk
S.queue = {}   -- [lot key] = { zi, ci, at (ms queued), ready (ms its chunks were first seen all loaded) }
S.recent = {}  -- { x0, y0, x1, y1, ms } footprints placed lately
local ORIG_KEY = "MinidoracatTesla_SemiSpawn_registerVehiclesZone"
local seenRect = {}

local function chunkKey(wx, wy) return wx * 100000 + wy end
function S.lotKey(z, car) return z.x .. "," .. z.y .. "," .. z.w .. "," .. z.h .. "," .. car.key end

local function md()
    local t = ModData.getOrCreate(S.MODDATA)
    t.done = t.done or {}
    t.v = S.RULES
    return t
end

-- the world's seed, the same from its first boot, never through our unsaved ModData: the world generation seed string
-- (WorldGenParams, exposed LuaManager.java:2226; vanilla Lua reads it, MainScreen.lua:672). Single player: the new
-- game screen always fills it (MapSpawnSelect.lua:900-913) and the loading state saves map_worldgen.bin at once
-- (GameLoadingState.java:326-336, GameWindow.java:1030). Dedicated server: a new world takes the ini's Seed or a
-- generated one and writes it into the ini right away (IsoWorld.java:1880-1888, ServerOptions.java:363-370), which the
-- next boot reads back if map_worldgen.bin was never saved. Folded into an int below 2^31 (an empty one gives 0).
function S.seed()
    local s, h = WorldGenParams.INSTANCE:getSeedString() or "", 0
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 2147483647 end
    return h
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

-- each car's body round its position, put down square to its heading (S.place): a squares out on the side it faces
-- (N: -y, E: +x), b on the other, wid / 2 across. The engine boxes the body as the extents centred on the centre of
-- mass offset (VehiclePoly.java:52-88), so a = len / 2 + com z and b = len / 2 - com z: Semi 2.64 / 3.85, trailer
-- 9.61 / 3.73, as measured round the placed cars (semiA-bcd-1, temp/plan-semi-1117/e2e/RESULTS-A.md "生成放下率與擺正").
-- Offsets of the box from the position, without the margin.
function S.box(car, dir)
    local a, b, w = car.a, car.b, car.wid / 2
    if dir == "N" then return -w, -a, w, b end
    if dir == "S" then return -w, -b, w, a end
    if dir == "W" then return -a, -w, b, w end
    return -b, -w, a, w
end

-- the squares the body covers at cx, cy (a square's north-west corner, where addVehicleDebug puts the position), with
-- S.MARGIN round it
function S.footprint(cx, cy, dir, car)
    local x0, y0, x1, y1 = S.box(car, dir)
    local m = S.MARGIN
    return math.floor(cx + x0 - m), math.floor(cy + y0 - m), math.floor(cx + x1 + m), math.floor(cy + y1 + m)
end

-- A lot fits a car when its long side holds the footprint facing one way or the other along it and it is 3 or more
-- wide (a stall's width); the footprint reaches past the lot's sides, S.free checks those squares too.
function S.buildIndex()
    S.byChunk = {}
    local lots = {}
    for ci, car in ipairs(S.CARS) do
        local vs = ScriptManager.instance:getVehicle(car.script)
        if vs then
            local ext, com = vs:getExtents(), vs:getCenterOfMassOffset()
            car.a, car.b, car.wid = ext:z() / 2 + com:z(), ext:z() / 2 - com:z(), ext:x()
            local _, n0, _, n1 = S.footprint(0, 0, "N", car)
            local _, s0, _, s1 = S.footprint(0, 0, "S", car)
            car.need = math.min(n1 - n0, s1 - s0) + 1
        end
        lots[ci] = 0
        for zi, z in ipairs(S.zones) do
            if car.need and math.max(z.w, z.h) >= car.need and math.min(z.w, z.h) >= 3 then
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
-- the lot rolled a hit at this chance (%), the car's own multiple of it (S.CARS mul)
function S.hit(z, ci, seed, pct) return S.roll(z, ci, seed) * 100 < pct * (S.CARS[ci].mul or 1) end

-- ---- the squares ----
-- free for a parked truck: VehicleSpawnControl's open ground, its conditions copied (no call across mods: openGround
-- and R.squareFree, MVSC_Respawn.lua:211-220,332-352): solid floor; nothing solid, see-through solid (a fence) or a
-- tree; not water; nothing dropped on it (getWorldObjects) and nothing a player built (IsoThumpable); outdoors; no
-- stairs, garage door or wall, window, door or hoppable edge. What has no collision stays allowed: road paint
-- (street_decoration_01_40..45), grass, litter, as measured blocking the trailer before (semiA-lots-2). Ours kept: no
-- car (isVehicleIntersecting, IsoGridSquare.java:9853-9874), nobody but zombies (as vanilla, a car may spawn on one),
-- no body, in no safehouse (SafeHouse.getSafeHouse: the one holding the square, whoever the player,
-- SafeHouse.java:157-159).
local EDGES = { "collideN", "collideW", "WallN", "WallW", "WallNW", "WallSE", "WindowN", "WindowW", "DoorWallN",
    "DoorWallW", "doorN", "doorW", "HoppableN", "HoppableW" }
function S.free(sq)
    if not sq or not sq:isSolidFloor() or sq:isSolid() or sq:isSolidTrans() or sq:HasTree() or sq:isWaterSquare() then
        return false
    end
    if not sq:getWorldObjects():isEmpty() then return false end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        if instanceof(objs:get(i), "IsoThumpable") then return false end
    end
    if not sq:isOutside() or sq:HasStairs() or sq:has(IsoPropertyType.GARAGE_DOOR) then return false end
    for _, flag in ipairs(EDGES) do
        if sq:has(IsoFlagType[flag]) then return false end
    end
    if sq:isVehicleIntersecting() or sq:getDeadBody() ~= nil then return false end
    local mov = sq:getMovingObjects()
    for i = 0, mov:size() - 1 do
        if not instanceof(mov:get(i), "IsoZombie") then return false end
    end
    return SafeHouse.getSafeHouse(sq) == nil
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

-- the middle row across the lot, where the position goes
local function midRow(z)
    if z.w >= z.h then return z.y + math.floor(z.h / 2) end
    return z.x + math.floor(z.w / 2)
end
-- the stretch along the lot the position may take facing dir (lo..hi; none when lo > hi), its footprint in the lot
-- end to end (floor(p + offset) = p + floor(offset) for a whole p)
local function span(z, car, dir)
    local x0, y0, x1, y1 = S.footprint(0, 0, dir, car)
    if z.w >= z.h then return z.x - x0, z.x + z.w - 1 - x1 end
    return z.y - y0, z.y + z.h - 1 - y1
end
-- every square a footprint in the lot may cover: the lot's length by the footprint's width on the middle row
local function lotBox(z, car)
    local m, w = midRow(z), car.wid / 2 + S.MARGIN
    if z.w >= z.h then return z.x, m + math.floor(-w), z.x + z.w - 1, m + math.floor(w) end
    return m + math.floor(-w), z.y, m + math.floor(w), z.y + z.h - 1
end

-- every chunk the check reads loaded: the footprints, and S.NEAR past them for the cars standing there (a car in a
-- chunk not loaded is in no list; isVehicleIntersecting itself looks 4 past, IsoGridSquare.java:9853-9874)
function S.ready(z, car)
    local x0, y0, x1, y1 = lotBox(z, car)
    return loaded(x0 - S.NEAR, y0 - S.NEAR, x1 + S.NEAR, y1 + S.NEAR)
end

-- the cars whose body may reach the footprints. isVehicleIntersecting finds a car by the chunks 4 squares round the
-- square, so a long one standing further off is missed; every car in the world is asked here instead. IsoCell.vehicles
-- holds them on a dedicated server too: createPhysics adds the car to the cell's addVehicles (BaseVehicle.java:895-898),
-- the cell's update moves those in (IsoCell.java:2164-2169,4059), which the server runs every frame (GameServer.java:1060
-- IngameState.update -> IngameState.java:1535 -> IsoWorld.java:2962), removeFromWorld takes it out (BaseVehicle.java:
-- 8119-8120). A HashSet: walked with iterator(), as SemiHitch.lua does. Also the one walk that sees this lot's own car
-- standing in it already: put down before a crash that lost the done mark (VehiclesDB2 commits the car itself,
-- VehiclesDB2.java:805-821,841-855; global ModData waits for the world save). Standing, on the ground, inside the lot
-- (half-open, like span): "there" marks the lot done for good, so one driving through, on a deck above or on the next
-- lot's first square must not count.
local function carsNear(z, car, x0, y0, x1, y1)
    local out, it = {}, getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        local x, y = v:getX(), v:getY()
        if x >= z.x and x < z.x + z.w and y >= z.y and y < z.y + z.h and math.floor(v:getZ()) == 0
            and v:getScriptName() == car.script and T.stopped(v) then
            return nil
        end
        if x >= x0 - S.NEAR and x <= x1 + 1 + S.NEAR and y >= y0 - S.NEAR and y <= y1 + 1 + S.NEAR then out[#out + 1] = v end
    end
    return out
end

-- one lot whose squares are loaded: "placed", "there" (its car stands in it already) or "noroom". Facing a random way
-- along the lot; the other way would add no room: its footprints are the same windows of the lot, shifted (S.footprint,
-- the same length both ways for both cars). Nothing here asks the car just put down: isIntersectingSquare is false for
-- all its squares within the call that made it (semiA-bcd-1); S.recent keeps its footprint for the next ones.
function S.place(z, car, now)
    local cars = carsNear(z, car, lotBox(z, car))
    if not cars then
        T.log("semi spawn: the " .. car.key .. " is in the lot " .. S.lotKey(z, car) .. " already")
        return "there"
    end
    local alongX = z.w >= z.h
    local dir = alongX and (ZombRand(2) == 0 and "E" or "W") or (ZombRand(2) == 0 and "S" or "N")
    local cell, seen = getCell(), {}
    local function free(x, y)
        if not S.free(cell:getGridSquare(x, y, 0)) then return false end
        for i = 1, #cars do
            if cars[i]:isIntersectingSquare(x, y, 0) then return false end -- BaseVehicle.java:5785-5797
        end
        return true
    end
    local function fits(x0, y0, x1, y1)
        for x = x0, x1 do
            for y = y0, y1 do
                local k = x * 100000 + y
                if seen[k] == nil then seen[k] = free(x, y) end
                if not seen[k] then return false end
            end
        end
        return not recentOverlap(x0, y0, x1, y1, now)
    end
    local lo, hi = span(z, car, dir)
    local c, mid = math.floor((lo + hi) / 2), midRow(z)
    for d = 0, hi - lo do
        for _, p in ipairs(d == 0 and { c } or { c + d, c - d }) do
            if p >= lo and p <= hi then
                local cx, cy = p, mid
                if not alongX then cx, cy = mid, p end
                local x0, y0, x1, y1 = S.footprint(cx, cy, dir, car)
                if fits(x0, y0, x1, y1) then
                    local v = addVehicleDebug(car.script, IsoDirections[dir], nil, cell:getGridSquare(cx, cy, 0))
                    -- a car it could not put down still comes back, never in the world: sqlId -1 (MVSC_Respawn.lua:316)
                    if not v or v:getSqlId() == -1 then return "noroom" end
                    -- addVehicleDebug turns it up to 0.2 rad off the heading (LuaManager.java addVehicleDebug): squared
                    -- here, in the same call (setAngles -> setWorldTransform, BaseVehicle.java:4083-4129; the save
                    -- keeps that transform, :2637-2645). Measured -10.7..+7.7 degrees off -> 0.00, held 6 s and after a
                    -- reload, read the same by a dedicated server's client (semiA-bcd-1, semiA-smp-1, semiA-sload-1).
                    -- It does nothing when the whole degrees already match (:4115).
                    v:setAngles(0, math.deg(IsoDirections[dir]:toAngle() + math.pi), 0)
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
-- each game minute while a lot waits (no tick: AGENTS.md rule 2). Rolled again at today's chance (a miss leaves the
-- queue, not done: the chance turned back up queues it on its next load). A lot whose chunks are not all loaded waits
-- (its settle starts over) without holding the others up; of the settled ones the oldest (queued first, then by key)
-- is put down or has no room, the one square scan of the minute. No table.sort (verify_mod): one pass keeps the
-- oldest. Unhooks itself when none is left.
local hooked = false
local function tick()
    local t, now = md(), getTimestampMs()
    local pct, settle, seed = T.semiSpawnPct(), isServer() and S.SETTLE_MS or 0, S.seed()
    local pick, pq
    for k, q in pairs(S.queue) do
        if not q.ready and now - q.at > S.TTL_MS then S.queue[k] = nil -- never all loaded: its next load queues it again
        elseif not S.hit(S.zones[q.zi], q.ci, seed, pct) then S.queue[k] = nil
        elseif not S.ready(S.zones[q.zi], S.CARS[q.ci]) then q.ready = nil
        else
            q.ready = q.ready or now
            if now - q.ready >= settle and (not pq or q.at < pq.at or (q.at == pq.at and k < pick)) then pick, pq = k, q end
        end
    end
    if pick then
        -- done before anything else: an error half way does not put a second car down later
        t.done[pick] = S.RULES
        S.queue[pick] = nil
        local ok, res = pcall(S.place, S.zones[pq.zi], S.CARS[pq.ci], now)
        if not ok then T.log("semi spawn: error " .. tostring(res)) end
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
    local t, seed = md(), S.seed()
    for i = 1, #list, 2 do
        local zi, ci = list[i], list[i + 1]
        local z, car = S.zones[zi], S.CARS[ci]
        local k = S.lotKey(z, car)
        if not t.done[k] and not S.queue[k] and S.hit(z, ci, seed, pct) then
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
