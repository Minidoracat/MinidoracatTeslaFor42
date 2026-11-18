-- SemiSpawn.lua: the Semi and the trailer put down by the server in long parking lots (no zone table), each lot rolled
-- once, only on clear ground, the minute hook only while a lot waits
local check = H.check
local T = MinidoracatTesla
local saved = { getCell = getCell, SafeHouse = SafeHouse, ScriptManager = ScriptManager, addVehicleDebug = addVehicleDebug,
    IsoDirections = IsoDirections, cm = __classmetatables, IsoWorld = IsoWorld, WorldGenParams = WorldGenParams,
    IsoFlagType = IsoFlagType, IsoPropertyType = IsoPropertyType, pct = SandboxVars.MinidoracatTesla.SemiSpawnChance }
-- the world generation seed string (single player: the new game screen's; a server: its ini's Seed)
local seedString = "Kentucky1993"
WorldGenParams = { INSTANCE = { getSeedString = function() return seedString end } }

local function list(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end

-- the IsoWorld method table the module wraps (vanilla doMapZones calls it, metazoneHandler.lua:120,143)
local registered = {}
local methods = { registerVehiclesZone = function(_, name, kind, x, y, z, w, h)
    registered[#registered + 1] = name
    return { name = name }
end }
IsoWorld = { class = "IsoWorld.class" }
__classmetatables = { [IsoWorld.class] = { __index = methods } }

-- the cars' boxes as the scripts give them (runtime: extents and centre of mass x 1.82): Semi 2.079 x 6.492 with the
-- centre of mass 0.601 behind, trailer 2.148 x 13.343 with it 2.937 ahead
local function vec(x, y, z) return { x = function() return x end, y = function() return y end, z = function() return z end } end
local DIMS = { ["Base.MinidoracatTesla_Semi"] = { 2.079, 6.492, -0.601 }, ["Base.MinidoracatTesla_SemiTrailer"] = { 2.148, 13.343, 2.937 } }
ScriptManager = { instance = { getVehicle = function(_, name)
    local d = DIMS[name]
    return d and { getExtents = function() return vec(d[1], 2, d[2]) end,
        getCenterOfMassOffset = function() return vec(0, 0, d[3]) end }
end } }
-- IsoDirections.java:9-29: the angle is ordinal x 2 pi / 8 (N 0, W 2, S 4, E 6)
local function isoDir(name, ordinal) return { name = name, toAngle = function() return ordinal * math.pi / 4 end } end
IsoDirections = { N = isoDir("N", 0), W = isoDir("W", 2), S = isoDir("S", 4), E = isoDir("E", 6) }
IsoFlagType = setmetatable({}, { __index = function(_, k) return k end })
IsoPropertyType = { GARAGE_DOOR = "GarageDoor" }

-- the world: every square clear outdoor floor unless `mods` says otherwise ({ solid = true }, { trans = true } a fence,
-- { tree = true }, { stairs = true }, { flag = "WallN" } that flag or property, { thump = true } a player's build,
-- { item = true } something dropped on it, { paint = true } / { grass = true } an object with no collision, { safe =
-- true } in a safehouse, { car = true } a car over it, { zombie = true } / { player = true } someone on it);
-- `unloaded` true: no chunk loaded, { x0, x1 }: none whose squares x0..x1; `others`: the cars in the cell
local mods, squares, unloaded, others = {}, {}, false, {}
local function square(x, y)
    local k = x .. "," .. y
    if squares[k] then return squares[k] end
    local o, floor = mods[k] or {}, { floor = true }
    local objs = { floor }
    if o.paint then objs[#objs + 1] = { sprite = "street_decoration_01_40" } end
    if o.grass then objs[#objs + 1] = { sprite = "e_newgrass_1_0" } end
    if o.thump then objs[#objs + 1] = { _class = "IsoThumpable" } end
    local mov = (o.zombie and { { _class = "IsoZombie" } }) or (o.player and { { _class = "IsoPlayer" } }) or {}
    local items = o.item and { { _class = "IsoWorldInventoryObject" } } or {}
    local sq = { _safe = o.safe,
        getX = function() return x end, getY = function() return y end,
        isSolidFloor = function() return true end, isOutside = function() return not o.inside end,
        isSolid = function() return o.solid == true end, isSolidTrans = function() return o.trans == true end,
        HasTree = function() return o.tree == true end, HasStairs = function() return o.stairs == true end,
        has = function(_, f) return f ~= nil and o.flag == f end,
        isWaterSquare = function() return false end, getObjects = function() return list(objs) end,
        getWorldObjects = function() return { isEmpty = function() return #items == 0 end } end,
        getFloor = function() return floor end, isVehicleIntersecting = function() return o.car == true end,
        getDeadBody = function() return nil end, getMovingObjects = function() return list(mov) end }
    squares[k] = sq
    return sq
end
local function setMods(m) mods, squares = m, {} end
getCell = function() return {
    getGridSquare = function(_, x, y, z) return z == 0 and square(x, y) or nil end,
    getChunkForGridSquare = function(_, x)
        if unloaded == true or (type(unloaded) == "table" and x >= unloaded[1] and x <= unloaded[2]) then return nil end
        return true
    end,
    -- IsoCell.vehicles, a HashSet: iterator() only
    getVehicles = function() return { iterator = function()
        local i = 0
        return { hasNext = function() return i < #others end, next = function() i = i + 1; return others[i] end }
    end } end,
} end
-- a car standing at x, y whose body covers the squares x0..x1, y0..y1 (isIntersectingSquare, z 0); `asked` counts
local function otherCar(x, y, x0, y0, x1, y1, script)
    return { asked = 0, getX = function() return x end, getY = function() return y end,
        getScriptName = function() return script or "Base.CarNormal" end,
        isIntersectingSquare = function(self, sx, sy, sz)
            self.asked = self.asked + 1
            return sz == 0 and sx >= x0 and sx <= x1 and sy >= y0 and sy <= y1
        end }
end
SafeHouse = { getSafeHouse = function(sq) return sq._safe and {} or nil end }

-- addVehicleDebug: placed[i] = { script, dir, x, y, v }; rejectNext: the engine refuses the next one (sqlId -1)
local placed, rejectNext = {}, false
local function part(wheel)
    return { cond = nil, amount = 20, getInventoryItem = function() return {} end,
        setRandomCondition = function(self) self.cond = "random" end,
        getWheelIndex = function() return wheel end, getContainerCapacity = function() return wheel ~= -1 and 35 or 0 end,
        setContainerContentAmount = function(self, a) self.amount = a end }
end
addVehicleDebug = function(script, dir, skin, sq)
    local parts = { part(-1), part(0), part(1) }
    local v = { script = script, sqlId = rejectNext and -1 or 1, parts = parts,
        getSqlId = function(self) return self.sqlId end,
        setZone = function(self, z) self.zone = z end, setVehicleType = function(self, t) self.type = t end,
        getPartById = function(self, id) return id == "Engine" and script == "Base.MinidoracatTesla_Semi" and parts[1] or nil end,
        setAlarmed = function(self, a) self.alarmed = a end,
        getPartCount = function() return #parts end, getPartByIndex = function(_, i) return parts[i + 1] end,
        setRust = function(self, r) self.rust = r end,
        setAngles = function(self, x, y, z) self.angles = { x, y, z } end }
    rejectNext = false
    placed[#placed + 1] = { script = script, dir = dir.name, x = sq:getX(), y = sq:getY(), v = v }
    return v
end

H.setRand(0.5) -- ZombRand: E / W and N / S pick the second, no alarm, no rust
H.side(false, true) -- a dedicated server until the single player section
H.require("MinidoracatTesla/SemiSpawn")
local S = T.SemiSpawn
local SEMI, TRAILER = S.CARS[1], S.CARS[2]

H.section("semi spawn: the lots")
check(S.installed, "the registerVehiclesZone wrap is in")
local function zone(name, kind, x, y, z, w, h) return methods.registerVehiclesZone({}, name, kind, x, y, z, w, h, {}) end
local z1 = zone("", "ParkingStall", 100, 100, 0, 60, 5) -- both fit, one after the other (the footprints 8 and 15 long)
check(z1 and z1.name == "" and registered[1] == "", "the wrap runs vanilla's register and returns its zone")
zone("parkingstall", "ParkingStall", 200, 100, 0, 5, 10)  -- Semi only, north-south: the wall lot
zone("", "ParkingStall", 300, 100, 0, 10, 5)              -- Semi only: the safehouse lot
zone("", "ParkingStall", 400, 100, 0, 10, 5)              -- Semi only: the free lot
zone("", "ParkingStall", 500, 100, 0, 10, 5)              -- Semi only: the lot the engine refuses
zone("", "ParkingStall", 600, 100, 0, 10, 5)              -- Semi only: chance 0
zone("", "ParkingStall", 100, 100, 0, 60, 5)              -- the same rect again: dropped like checkVehiclesZones
zone("", "ParkingStall", 700, 100, 1, 30, 5)              -- upstairs: not a lot
zone("", "TrafficJam", 800, 100, 0, 30, 5)                -- another kind
zone("", "ParkingStall", 900, 100, 0, 7, 5)               -- too short for the Semi
zone("", "ParkingStall", 1000, 100, 0, 30, 2)             -- too narrow
zone("", "ParkingStall", 1100, 100, 0, 10, 5)             -- Semi only: a long car's body over it
zone("", "ParkingStall", 1200, 100, 0, 10, 5)             -- Semi only: placed while another waits
zone("", "ParkingStall", 1300, 100, 0, 10, 5)             -- Semi only: the settle
zone("", "ParkingStall", 1400, 100, 0, 10, 5)             -- Semi only: the chance turned down
zone("", "ParkingStall", 1500, 100, 0, 14, 5)             -- 14 long: the Semi, not the trailer (15)
zone("", "ParkingStall", 1600, 100, 0, 15, 5)             -- 15 long: both
check(#S.zones == 14, "parkingstall zones at z 0, no duplicate rect: " .. #S.zones)
H.fire("OnLoadedMapZones")
local function near(a, b) return math.abs(a - b) < 0.006 end
check(near(SEMI.a, 2.64) and near(SEMI.b, 3.85) and near(TRAILER.a, 9.61) and near(TRAILER.b, 3.73)
    and near(SEMI.wid, 2.079) and near(TRAILER.wid, 2.148),
    "the bodies from the script's extents and centre of mass = the measured ones (semiA-bcd-1): Semi a " .. SEMI.a
    .. " b " .. SEMI.b .. ", trailer a " .. TRAILER.a .. " b " .. TRAILER.b)
-- isIntersectingSquare round the car put down squared, relative to its square (RESULTS-A.md, SP and a dedicated
-- server's client the same): x0, y0, x1, y1
local MEASURED = {
    semi = { N = { -2, -3, 1, 3 }, E = { -4, -2, 2, 1 }, S = { -2, -4, 1, 2 }, W = { -3, -2, 3, 1 } },
    trailer = { N = { -2, -10, 1, 3 }, E = { -4, -2, 9, 1 }, S = { -2, -4, 1, 9 }, W = { -10, -2, 3, 1 } },
}
for _, car in ipairs({ SEMI, TRAILER }) do
    for dir, m in pairs(MEASURED[car.key]) do
        local x0, y0, x1, y1 = S.box(car, dir)
        local got = { math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1) }
        local f = { S.footprint(0, 0, dir, car) }
        check(got[1] == m[1] and got[2] == m[2] and got[3] == m[3] and got[4] == m[4]
            and f[1] <= m[1] and f[2] <= m[2] and f[3] >= m[3] and f[4] >= m[4],
            car.key .. " facing " .. dir .. ": the squares under the box = the measured " .. table.concat(m, ",")
            .. " (got " .. table.concat(got, ",") .. "), the footprint with the margin round them (" .. table.concat(f, ",") .. ")")
    end
end
check(SEMI.need == 8 and TRAILER.need == 15, "a lot's long side needs the footprint: Semi " .. tostring(SEMI.need)
    .. ", trailer " .. tostring(TRAILER.need) .. " (vanilla map: 1,563 and 1,293 lots)")
local function lotsIn(wx, wy)
    local t, l = {}, S.byChunk[wx * 100000 + wy] or {}
    for i = 1, #l, 2 do t[#t + 1] = S.CARS[l[i + 1]].key .. "@" .. S.zones[l[i]].x end
    return table.concat(t, " ")
end
check(lotsIn(12, 12) == "semi@100 trailer@100" and lotsIn(19, 13) == "semi@100 trailer@100",
    "the 60 x 5 lot: both cars, in every chunk it touches (" .. lotsIn(12, 12) .. ")")
check(lotsIn(112, 12) == "" and lotsIn(125, 12) == "", "too short (7) or too narrow: no lot")
check(lotsIn(37, 12) == "semi@300", "a 10 x 5 lot: the Semi only")
check(lotsIn(187, 12) == "semi@1500" and lotsIn(200, 12) == "semi@1600 trailer@1600",
    "14 long: the Semi only; 15 long: the trailer too")

H.section("semi spawn: the roll")
local seed = 12345
local same = S.roll(S.zones[1], 1, seed) == S.roll(S.zones[1], 1, seed)
local hits, n = 0, 0
for x = 0, 99 do
    for y = 0, 99 do
        n = n + 1
        if S.roll({ x = 3000 + x * 37, y = 9000 + y * 41, w = 10, h = 5 }, 1, seed) * 100 < 1.5 then hits = hits + 1 end
    end
end
check(same and hits > 100 and hits < 200, "the same lot rolls the same; 1.5% of 10000 lots hit: " .. hits)
local s1 = S.seed()
seedString = "Kentucky1994"
local s2 = S.seed()
seedString = ""
local s0 = S.seed()
seedString = "Kentucky1993"
check(s1 == S.seed() and s1 ~= s2 and s0 == 0 and s1 > 0 and s1 < 2147483647,
    "the seed from the world generation seed string: the same string the same seed, another one another (" .. s1 .. ")")

local function chunkAt(ox, oy)
    return { getGridSquare = function(_, x, y, z) return square(ox + x, oy + y) end }
end
local hooks = H.count("EveryOneMinute")
local function queued() local c = 0 for _ in pairs(S.queue) do c = c + 1 end return c end
local done = function() return ModData.getOrCreate(S.MODDATA).done end

H.section("semi spawn: placed")
SandboxVars.MinidoracatTesla.SemiSpawnChance = 100
-- the 60 x 5 lot painted and grown over: road paint along its middle row, grass along the row past it (no collision:
-- they block nothing, semiA-lots-2)
local painted = {}
for x = 96, 163 do painted[x .. ",102"] = { paint = true }; painted[x .. ",103"] = { grass = true } end
setMods(painted)
H.fire("LoadChunk", chunkAt(96, 96))
H.fire("LoadChunk", chunkAt(104, 96)) -- the same lot from its next chunk: queued once
check(queued() == 2 and H.count("EveryOneMinute") == hooks + 1, "a hit lot's chunk loads: both cars queued, one minute hook")
H.fire("EveryOneMinute")
check(#placed == 0, "nothing before the chunk settles")
H.advanceMs(S.SETTLE_MS)
H.fire("EveryOneMinute")
check(#placed == 1, "settled: one lot a minute")
H.fire("EveryOneMinute")
check(#placed == 2 and queued() == 0 and H.count("EveryOneMinute") == hooks, "both put down, the queue empty, hook removed")
local function box(p)
    local car = p.script == SEMI.script and SEMI or TRAILER
    return { S.footprint(p.x, p.y, p.dir, car) }
end
local a, b = box(placed[1]), box(placed[2])
local inLot = true
for _, f in ipairs({ a, b }) do
    -- the footprint with the margin inside the lot's long side
    if f[1] < 100 or f[3] > 159 then inLot = false end
end
check(inLot and placed[1].y == 102 and placed[2].y == 102 and placed[1].dir == "W" and placed[2].dir == "W",
    "along the lot's long side, on its middle row, over the paint and the grass")
check(a[3] < b[1] or b[3] < a[1], "the second car not on the first (" .. a[1] .. "-" .. a[3] .. ", " .. b[1] .. "-" .. b[3] .. ")")
local ang1, ang2 = placed[1].v.angles, placed[2].v.angles
check(ang1 and ang2 and ang1[1] == 0 and math.abs(ang1[2] - 270) < 1e-9 and ang1[3] == 0 and math.abs(ang2[2] - 270) < 1e-9,
    "squared to its heading when put down: setAngles(0, deg(W's angle + pi) = 270, 0)")
local v = placed[1].v
check(v.zone == "parkingstall" and v.type == "parkingstall" and v.parts[1].cond == "random" and v.parts[2].cond == "random",
    "a parked car's condition: parkingstall zone and type, each part's random condition")
check(v.parts[2].amount == 35 and v.parts[3].amount == 35 and v.parts[1].amount == 20 and v.rust == 0,
    "tyres full, other parts untouched, rust by the zone quality")
local k1 = S.lotKey(S.zones[1], SEMI)
check(done()[k1] == S.RULES and done()[S.lotKey(S.zones[1], TRAILER)] == S.RULES, "both lots done with the rules' version")

H.section("semi spawn: rolled once")
H.fire("LoadChunk", chunkAt(96, 96))
check(queued() == 0 and H.count("EveryOneMinute") == hooks, "the lot loads again (this session or the next): done in ModData, nothing queued")

H.section("semi spawn: no room")
-- a dedicated server: the first minute sees the lot's chunks loaded, SETTLE later it is put down
local function settleTick()
    H.fire("EveryOneMinute")
    H.advanceMs(S.SETTLE_MS)
    H.fire("EveryOneMinute")
end
-- the north-south lot 200,100 5 x 10: a fence on its middle row under every place the Semi could take
setMods({ ["201,105"] = { trans = true }, ["202,105"] = { trans = true }, ["203,105"] = { trans = true } })
H.fire("LoadChunk", chunkAt(200, 104))
settleTick()
check(#placed == 2 and done()[S.lotKey(S.zones[2], SEMI)] == S.RULES and H.count("EveryOneMinute") == hooks,
    "a fence in the way: no car, the lot done")
setMods({ ["305,102"] = { safe = true } }) -- one square of the lot in a safehouse
H.fire("LoadChunk", chunkAt(296, 96))
settleTick()
check(#placed == 2 and done()[S.lotKey(S.zones[3], SEMI)] == S.RULES, "one square under the body in a safehouse: no car")

setMods({ ["1,1"] = { solid = true }, ["2,1"] = { car = true }, ["3,1"] = { player = true }, ["4,1"] = { inside = true },
    ["5,1"] = { safe = true }, ["6,1"] = { zombie = true }, ["7,1"] = { paint = true }, ["8,1"] = { grass = true },
    ["9,1"] = { trans = true }, ["10,1"] = { tree = true }, ["11,1"] = { stairs = true }, ["12,1"] = { thump = true },
    ["13,1"] = { item = true }, ["14,1"] = { flag = "WallN" }, ["15,1"] = { flag = "HoppableW" },
    ["16,1"] = { flag = "GarageDoor" } })
local function sqFree(x) return S.free(square(x, 1)) end
check(sqFree(0) and sqFree(6) and sqFree(7) and sqFree(8) and not S.free(nil),
    "a square: clear floor, a zombie, road paint, grass yes")
local blocked = {}
for x = 1, 16 do
    if x < 6 or x > 8 then blocked[#blocked + 1] = sqFree(x) and x or nil end
end
check(#blocked == 0, "a square: solid, a car, a player, indoors, a safehouse, a fence, a tree, stairs, a player's build, "
    .. "an item on it, a wall edge, a hoppable edge, a garage door no (free: " .. table.concat(blocked, ",") .. ")")

H.section("semi spawn: waits for its squares")
setMods({ ["405,102"] = { zombie = true } })
unloaded = true
H.fire("LoadChunk", chunkAt(400, 96))
H.advanceMs(S.SETTLE_MS)
H.fire("EveryOneMinute")
check(#placed == 2 and queued() == 1 and H.count("EveryOneMinute") == hooks + 1, "squares around it not loaded: it waits")
H.advanceMs(S.TTL_MS)
H.fire("EveryOneMinute")
check(queued() == 0 and done()[S.lotKey(S.zones[4], SEMI)] == nil and H.count("EveryOneMinute") == hooks,
    "never loaded: dropped from the queue, not done")
unloaded = false
H.fire("LoadChunk", chunkAt(400, 96))
settleTick()
check(#placed == 3 and placed[3].x == 404, "loaded next time: put down over the zombie at 405 (it does not block, as vanilla)")

H.section("semi spawn: refused")
rejectNext = true
H.fire("LoadChunk", chunkAt(496, 96))
settleTick()
check(#placed == 4 and placed[4].v.zone == nil and done()[S.lotKey(S.zones[5], SEMI)] == S.RULES,
    "the engine refuses it (sqlId -1): left alone, the lot done")

H.section("semi spawn: a long car standing off the lot")
-- the lot 1100,100 10 x 5: a car standing 8 squares north of its middle row (further than isVehicleIntersecting's
-- 4, the squares say free) with its body over the whole lot; another one far off is not even asked
local over, far = otherCar(1105, 94, 1095, 95, 1115, 106), otherCar(5000, 5000, 4990, 4990, 5010, 5010)
others = { over, far }
H.fire("LoadChunk", chunkAt(1096, 96))
settleTick()
check(#placed == 4 and done()[S.lotKey(S.zones[9], SEMI)] == S.RULES and over.asked > 0 and far.asked == 0,
    "every car in the cell near the lot asked (isIntersectingSquare): its body over the lot, no room")
others = {}

H.section("semi spawn: a lot waiting does not hold the others up")
-- the lot at 1300 queued first, its chunks not loaded; the one at 1200 a moment later
unloaded = { 1280, 1340 }
H.fire("LoadChunk", chunkAt(1296, 96))
H.advanceMs(1)
H.fire("LoadChunk", chunkAt(1200, 96))
settleTick()
local kA = S.lotKey(S.zones[11], SEMI)
check(#placed == 5 and placed[5].x >= 1200 and placed[5].x < 1210 and queued() == 1 and S.queue[kA] and not S.queue[kA].ready
    and done()[kA] == nil, "the older lot still not loaded: the newer one put down past it, the older waits")

H.section("semi spawn: SETTLE from its chunks all loaded")
-- the lot at 1300 has been queued SETTLE and more: loaded now, it still waits SETTLE from this minute
unloaded = false
H.fire("EveryOneMinute")
H.advanceMs(S.SETTLE_MS - 1)
H.fire("EveryOneMinute")
check(#placed == 5 and S.queue[kA], "loaded a minute ago, queued long before: not before SETTLE from the load")
unloaded = { 1280, 1340 } -- one chunk gone again: the settle starts over
H.fire("EveryOneMinute")
unloaded = false
H.fire("EveryOneMinute")
H.advanceMs(S.SETTLE_MS - 1)
H.fire("EveryOneMinute")
check(#placed == 5 and S.queue[kA], "a chunk unloaded in between: SETTLE again from the reload")
H.advanceMs(1)
H.fire("EveryOneMinute")
check(#placed == 6 and placed[6].x >= 1300 and done()[kA] == S.RULES and H.count("EveryOneMinute") == hooks,
    "SETTLE after the reload: put down")

H.section("semi spawn: the chance turned down with lots queued")
H.fire("LoadChunk", chunkAt(1400, 96))
local kC = S.lotKey(S.zones[12], SEMI)
SandboxVars.MinidoracatTesla.SemiSpawnChance = 0
H.fire("EveryOneMinute")
check(#placed == 6 and queued() == 0 and done()[kC] == nil and H.count("EveryOneMinute") == hooks,
    "chance 0 before it settles: off the queue, not done, hook removed")
SandboxVars.MinidoracatTesla.SemiSpawnChance = 100
H.fire("LoadChunk", chunkAt(1400, 96))
settleTick()
check(#placed == 7 and placed[7].x >= 1400 and done()[kC] == S.RULES, "turned back up: its next load puts it down")

H.section("semi spawn: its car already in the lot (G1)")
-- the Semi's lot 1500,100 14 x 5: a Semi standing just north of it (not in the lot, not over it) is no record
local k15 = S.lotKey(S.zones[13], SEMI)
others = { otherCar(1509, 94, 1509, 94, 1509, 94, SEMI.script) }
H.fire("LoadChunk", chunkAt(1496, 96))
settleTick()
check(#placed == 8 and placed[8].x >= 1500 and placed[8].x < 1520 and done()[k15] == S.RULES,
    "a Semi parked off the lot: the lot gets its own")
-- a crash after vehicles.db took the car, before the world save took the done mark: the next session sees the lot
-- again, with the car we put down standing in it
done()[k15] = nil
local p = placed[8]
others[#others + 1] = otherCar(p.x, p.y, p.x - 1, p.y - 1, p.x + 1, p.y + 1, SEMI.script)
H.fire("LoadChunk", chunkAt(1496, 96))
settleTick()
check(#placed == 8 and done()[k15] == S.RULES and queued() == 0 and H.count("EveryOneMinute") == hooks,
    "the done mark lost, its Semi in the lot: nothing put down again, the lot done")
check(ModData.getOrCreate(S.MODDATA).seed == nil, "no seed kept in ModData: the world's seed string is the record")
others = {}

H.section("semi spawn: chance 0")
SandboxVars.MinidoracatTesla.SemiSpawnChance = 0
H.fire("LoadChunk", chunkAt(600, 96))
check(queued() == 0 and H.count("EveryOneMinute") == hooks, "chance 0: nothing queued, no hook")

H.section("semi spawn: single player")
SandboxVars.MinidoracatTesla.SemiSpawnChance = 100
H.side(false, false)
H.fire("LoadChunk", chunkAt(600, 96))
H.fire("EveryOneMinute")
check(#placed == 9 and placed[9].x >= 600 and queued() == 0 and H.count("EveryOneMinute") == hooks,
    "single player: put down the next game minute, no settle wait")
H.side(false, true)
SandboxVars.MinidoracatTesla.SemiSpawnChance = nil
check(T.semiSpawnPct() == 1.5, "unset: 1.5%")

setMods({})
getCell, SafeHouse, ScriptManager, addVehicleDebug, IsoDirections, __classmetatables, IsoWorld, WorldGenParams =
    saved.getCell, saved.SafeHouse, saved.ScriptManager, saved.addVehicleDebug, saved.IsoDirections, saved.cm, saved.IsoWorld,
    saved.WorldGenParams
IsoFlagType, IsoPropertyType = saved.IsoFlagType, saved.IsoPropertyType
SandboxVars.MinidoracatTesla.SemiSpawnChance = saved.pct
