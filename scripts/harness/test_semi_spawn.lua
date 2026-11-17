-- SemiSpawn.lua: the Semi and the trailer put down by the server in long parking lots (no zone table), each lot rolled
-- once, only on clear ground, the minute hook only while a lot waits
local check = H.check
local T = MinidoracatTesla
local saved = { getCell = getCell, SafeHouse = SafeHouse, ScriptManager = ScriptManager, addVehicleDebug = addVehicleDebug,
    IsoDirections = IsoDirections, cm = __classmetatables, IsoWorld = IsoWorld,
    pct = SandboxVars.MinidoracatTesla.SemiSpawnChance }

local function list(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end

-- the IsoWorld method table the module wraps (vanilla doMapZones calls it, metazoneHandler.lua:120,143)
local registered = {}
local methods = { registerVehiclesZone = function(_, name, kind, x, y, z, w, h)
    registered[#registered + 1] = name
    return { name = name }
end }
IsoWorld = { class = "IsoWorld.class" }
__classmetatables = { [IsoWorld.class] = { __index = methods } }

-- the cars' boxes (runtime extents x 1.82 scale: Semi about 6.49 x 2.08, trailer 13.3 x 2.6)
local function vec(x, y, z) return { x = function() return x end, y = function() return y end, z = function() return z end } end
local DIMS = { ["Base.MinidoracatTesla_Semi"] = { 2.08, 6.29, 0.1 }, ["Base.MinidoracatTesla_SemiTrailer"] = { 2.6, 13.3, 0 } }
ScriptManager = { instance = { getVehicle = function(_, name)
    local d = DIMS[name]
    return d and { getExtents = function() return vec(d[1], 2, d[2]) end,
        getCenterOfMassOffset = function() return vec(0, 0, d[3]) end }
end } }
IsoDirections = { N = "N", S = "S", E = "E", W = "W" }

-- the world: every square clear outdoor floor unless `mods` says otherwise ({ wall = true } an object on it,
-- { safe = true } in a safehouse, { car = true } a car over it, { zombie = true } / { player = true } someone on it)
local mods, squares, unloaded = {}, {}, false
local function square(x, y)
    local k = x .. "," .. y
    if squares[k] then return squares[k] end
    local o, floor = mods[k] or {}, { floor = true }
    local objs = o.wall and { floor, { wall = true } } or { floor }
    local mov = (o.zombie and { { _class = "IsoZombie" } }) or (o.player and { { _class = "IsoPlayer" } }) or {}
    local sq = { _safe = o.safe,
        getX = function() return x end, getY = function() return y end,
        isSolidFloor = function() return true end, isOutside = function() return not o.inside end,
        isWaterSquare = function() return false end, getObjects = function() return list(objs) end,
        getFloor = function() return floor end, isVehicleIntersecting = function() return o.car == true end,
        getDeadBody = function() return nil end, getMovingObjects = function() return list(mov) end }
    squares[k] = sq
    return sq
end
local function setMods(m) mods, squares = m, {} end
getCell = function() return {
    getGridSquare = function(_, x, y, z) return z == 0 and square(x, y) or nil end,
    getChunkForGridSquare = function() return not unloaded or nil end,
} end
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
        setRust = function(self, r) self.rust = r end }
    rejectNext = false
    placed[#placed + 1] = { script = script, dir = dir, x = sq:getX(), y = sq:getY(), v = v }
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
local z1 = zone("", "ParkingStall", 100, 100, 0, 40, 5) -- both fit, one after the other (40 >= 8 + 15 + margins)
check(z1 and z1.name == "" and registered[1] == "", "the wrap runs vanilla's register and returns its zone")
zone("parkingstall", "ParkingStall", 200, 100, 0, 5, 10)  -- Semi only, north-south: the wall lot
zone("", "ParkingStall", 300, 100, 0, 10, 5)              -- Semi only: the safehouse lot
zone("", "ParkingStall", 400, 100, 0, 10, 5)              -- Semi only: the free lot
zone("", "ParkingStall", 500, 100, 0, 10, 5)              -- Semi only: the lot the engine refuses
zone("", "ParkingStall", 600, 100, 0, 10, 5)              -- Semi only: chance 0
zone("", "ParkingStall", 100, 100, 0, 40, 5)              -- the same rect again: dropped like checkVehiclesZones
zone("", "ParkingStall", 700, 100, 1, 30, 5)              -- upstairs: not a lot
zone("", "TrafficJam", 800, 100, 0, 30, 5)                -- another kind
zone("", "ParkingStall", 900, 100, 0, 7, 5)               -- too short for the Semi
zone("", "ParkingStall", 1000, 100, 0, 30, 2)             -- too narrow
check(#S.zones == 8, "parkingstall zones at z 0, no duplicate rect: " .. #S.zones)
H.fire("OnLoadedMapZones")
check(SEMI.half == 4 and TRAILER.half == 7, "the bodies by the script's box: Semi half " .. tostring(SEMI.half)
    .. ", trailer half " .. tostring(TRAILER.half))
local function lotsIn(wx, wy)
    local t, l = {}, S.byChunk[wx * 100000 + wy] or {}
    for i = 1, #l, 2 do t[#t + 1] = S.CARS[l[i + 1]].key .. "@" .. S.zones[l[i]].x end
    return table.concat(t, " ")
end
check(lotsIn(12, 12) == "semi@100 trailer@100" and lotsIn(14, 13) == "semi@100 trailer@100",
    "the 40 x 5 lot: both cars, in every chunk it touches (" .. lotsIn(12, 12) .. ")")
check(lotsIn(112, 12) == "" and lotsIn(125, 12) == "", "too short or too narrow: no lot")
check(lotsIn(37, 12) == "semi@300", "a 10 x 5 lot: the Semi only")

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

local function chunkAt(ox, oy)
    return { getGridSquare = function(_, x, y, z) return square(ox + x, oy + y) end }
end
local hooks = H.count("EveryOneMinute")
local function queued() local c = 0 for _ in pairs(S.queue) do c = c + 1 end return c end
local done = function() return ModData.getOrCreate(S.MODDATA).done end

H.section("semi spawn: placed")
SandboxVars.MinidoracatTesla.SemiSpawnChance = 100
setMods({})
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
    return { S.footprint(p.x, p.y, p.dir, car.len, car.wid) }
end
local a, b = box(placed[1]), box(placed[2])
local inLot = true
for _, f in ipairs({ a, b }) do
    -- the box with the turn margin inside the lot's long side
    if f[1] < 100 or f[3] > 139 then inLot = false end
end
check(inLot and placed[1].y == 102 and placed[2].y == 102 and (placed[1].dir == "E" or placed[1].dir == "W"),
    "along the lot's long side, on its middle row")
check(a[3] < b[1] or b[3] < a[1], "the second car not on the first (" .. a[1] .. "-" .. a[3] .. ", " .. b[1] .. "-" .. b[3] .. ")")
local v = placed[1].v
check(v.zone == "parkingstall" and v.type == "parkingstall" and v.parts[1].cond == "random" and v.parts[2].cond == "random",
    "a parked car's condition: parkingstall zone and type, each part's random condition")
check(v.parts[2].amount == 35 and v.parts[3].amount == 35 and v.parts[1].amount == 20 and v.rust == 0,
    "tyres full, other parts untouched, rust by the zone quality")
local k1 = S.lotKey(S.zones[1], SEMI)
check(done()[k1] == S.RULES and done()[S.lotKey(S.zones[1], TRAILER)] == S.RULES, "both lots done with the rules' version")

H.section("semi spawn: rolled once")
H.fire("LoadChunk", chunkAt(96, 96))
check(queued() == 0 and H.count("EveryOneMinute") == hooks, "the lot loads again this session: nothing queued")
S.known = {} -- the next session: only ModData remembers
H.fire("LoadChunk", chunkAt(96, 96))
H.advanceMs(S.SETTLE_MS)
H.fire("EveryOneMinute")
check(#placed == 2 and queued() == 0 and H.count("EveryOneMinute") == hooks, "the next session: done in ModData, not again")

H.section("semi spawn: no room")
-- the north-south lot 200,100 5 x 10: a wall on its middle row under every place the Semi could take
setMods({ ["201,105"] = { wall = true }, ["202,105"] = { wall = true }, ["203,105"] = { wall = true } })
H.fire("LoadChunk", chunkAt(200, 104))
H.advanceMs(S.SETTLE_MS)
H.fire("EveryOneMinute")
check(#placed == 2 and done()[S.lotKey(S.zones[2], SEMI)] == S.RULES and H.count("EveryOneMinute") == hooks,
    "a wall in the way: no car, the lot done")
setMods({ ["305,102"] = { safe = true } }) -- one square of the lot in a safehouse
H.fire("LoadChunk", chunkAt(296, 96))
H.advanceMs(S.SETTLE_MS)
H.fire("EveryOneMinute")
check(#placed == 2 and done()[S.lotKey(S.zones[3], SEMI)] == S.RULES, "one square under the body in a safehouse: no car")

setMods({ ["1,1"] = { wall = true }, ["2,1"] = { car = true }, ["3,1"] = { player = true }, ["4,1"] = { inside = true },
    ["5,1"] = { safe = true }, ["6,1"] = { zombie = true } })
check(S.free(square(0, 1)) and not S.free(square(1, 1)) and not S.free(square(2, 1)) and not S.free(square(3, 1))
    and not S.free(square(4, 1)) and not S.free(square(5, 1)) and S.free(square(6, 1)) and not S.free(nil),
    "a square: clear floor yes; an object, a car, a player, indoors, a safehouse no; a zombie yes")

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
H.advanceMs(S.SETTLE_MS)
H.fire("EveryOneMinute")
check(#placed == 3 and placed[3].x == 405, "loaded next time: put down (a zombie does not block, as vanilla)")

H.section("semi spawn: refused")
rejectNext = true
H.fire("LoadChunk", chunkAt(496, 96))
H.advanceMs(S.SETTLE_MS)
H.fire("EveryOneMinute")
check(#placed == 4 and placed[4].v.zone == nil and done()[S.lotKey(S.zones[5], SEMI)] == S.RULES,
    "the engine refuses it (sqlId -1): left alone, the lot done")

H.section("semi spawn: chance 0")
SandboxVars.MinidoracatTesla.SemiSpawnChance = 0
H.fire("LoadChunk", chunkAt(600, 96))
check(queued() == 0 and H.count("EveryOneMinute") == hooks, "chance 0: nothing queued, no hook")

H.section("semi spawn: single player")
SandboxVars.MinidoracatTesla.SemiSpawnChance = 100
H.side(false, false)
H.fire("LoadChunk", chunkAt(600, 96))
H.fire("EveryOneMinute")
check(#placed == 5 and placed[5].x >= 600 and queued() == 0 and H.count("EveryOneMinute") == hooks,
    "single player: put down the next game minute, no settle wait")
H.side(false, true)
SandboxVars.MinidoracatTesla.SemiSpawnChance = nil
check(T.semiSpawnPct() == 1.5, "unset: 1.5%")

setMods({})
getCell, SafeHouse, ScriptManager, addVehicleDebug, IsoDirections, __classmetatables, IsoWorld =
    saved.getCell, saved.SafeHouse, saved.ScriptManager, saved.addVehicleDebug, saved.IsoDirections, saved.cm, saved.IsoWorld
SandboxVars.MinidoracatTesla.SemiSpawnChance = saved.pct
