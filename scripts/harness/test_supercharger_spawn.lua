-- Supercharger spawn at gas stations (server/MinidoracatTesla/SuperchargerSpawn.lua): the placement rules on made-up
-- forecourts (S.plan: a normal row, room for 2 only, no room, doors, roads by street or centre line, walled-in
-- yards, parked cars), the square codes read from fake squares (S.cellAt, a safehouse's squares blocked), the roads
-- read from a streets.xml's lines (S.streetPieces, S.onRoad, S.roads: never the save's zones), and the station
-- record flow through S.build on fake squares (one record a station whichever pump square loads first or again,
-- posts once the chunks and the charger system are up, at most once, none in a safehouse or on a street, a station
-- 0.6.0 left without posts planned once more, the minute hook gone when nothing waits). The real vanilla stations
-- were checked the same way offline: the map's lotpacks as these grids, the real streets.xml through
-- S.streetPieces, S.plan run on all 46.
local check = H.check
H.side(false, true)
local saved = { getCell = getCell, getWorld = getWorld, MapObjects = MapObjects, sys = SMinidoracatTeslaChargerSystem,
    IsoFlagType = IsoFlagType, getTimestampMs = getTimestampMs, SafeHouse = SafeHouse,
    getLotDirectories = getLotDirectories, fileExists = fileExists, getGameFilesInput = getGameFilesInput,
    endFileInput = endFileInput }
MapObjects = { OnLoadWithSprite = function() end }
H.require("MinidoracatTesla/SuperchargerSpawn")
local T = MinidoracatTesla
local S = T.SuperchargerSpawn

-- a forecourt from rows of characters, top-left at 0,0: "=" paved, "g" grass, "P" pump, "D" door, "I" indoors,
-- "o" blocked, "." other floor, " " no square; paved with: "-" / "|" a wall on its north / west edge, "+" both,
-- "Y" a road's yellow centre line, "c" a parked car, "R" a road (Nav zone), "y" a road with a centre line; grass with
-- "~" / "!" a wall on its north / west edge
local CODES = {
    ["-"] = { k = "=", wn = true }, ["|"] = { k = "=", ww = true }, ["+"] = { k = "=", wn = true, ww = true },
    Y = { k = "=", line = true }, c = { k = "=", car = true }, R = { k = "=", nav = true },
    y = { k = "=", nav = true, line = true },
    ["~"] = { k = "g", wn = true }, ["!"] = { k = "g", ww = true },
}
local function forecourt(rows)
    local cells, pumps = {}, {}
    for y, row in ipairs(rows) do
        for x = 1, #row do
            local ch = row:sub(x, x)
            if ch ~= " " then
                local c = {}
                for k, v in pairs(CODES[ch] or { k = ch }) do c[k] = v end
                cells[(x - 1) .. "," .. (y - 1)] = c
                if ch == "P" then pumps[#pumps + 1] = { x - 1, y - 1 } end
            end
        end
    end
    local x0, y0, x1, y1 = 1e9, 1e9, -1e9, -1e9
    for _, p in ipairs(pumps) do
        x0, y0, x1, y1 = math.min(x0, p[1]), math.min(y0, p[2]), math.max(x1, p[1]), math.max(y1, p[2])
    end
    return function(x, y) return cells[x .. "," .. y] end, x0, y0, x1, y1, #pumps
end
local function put(rows, x, y, s) rows[y + 1] = rows[y + 1]:sub(1, x) .. s .. rows[y + 1]:sub(x + #s + 1) end
local function copy(rows) local t = {} for i, r in ipairs(rows) do t[i] = r end return t end

local DIRS = { S = { 0, 1 }, E = { 1, 0 }, N = { 0, -1 }, W = { -1, 0 } }
-- a post's squares: the post, its slot (DEPTH x 2) and the row a car comes in from
local function squaresOf(p)
    local f = DIRS[p.facing]
    local sx, sy = -f[2], f[1]
    local post, slot, entry = { { p.x, p.y } }, {}, {}
    for k = 1, S.DEPTH + 1 do
        for j = 0, 1 do
            local q = { p.x + k * f[1] + j * sx, p.y + k * f[2] + j * sy }
            if k <= S.DEPTH then slot[#slot + 1] = q else entry[#entry + 1] = q end
        end
    end
    return post, slot, entry
end
-- every post / slot square of a plan, checked against the rules that matter on a forecourt
local function audit(grid, posts, label)
    local ok, why = true, nil
    local function fail(s) if ok then ok, why = false, s end end
    local function far(x, y, test, gap) -- no square passing test within gap - 1
        for dx = 1 - gap, gap - 1 do
            for dy = 1 - gap, gap - 1 do
                local c = grid(x + dx, y + dy)
                if c and test(c) then return false end
            end
        end
        return true
    end
    for i, p in ipairs(posts) do
        local f = DIRS[p.facing]
        local sx, sy = -f[2], f[1]
        if i > 1 and (p.x - posts[i - 1].x ~= 3 * sx or p.y - posts[i - 1].y ~= 3 * sy or p.facing ~= posts[1].facing) then
            fail("row spacing / facing")
        end
        local b = grid(p.x - f[1], p.y - f[2])
        if b and b.k == "=" and not (b.wn or b.ww or grid(p.x, p.y).wn or grid(p.x, p.y).ww) then fail("post " .. i .. " back on open pavement") end
        local post, slot, entry = squaresOf(p)
        for _, q in ipairs(post) do slot[#slot + 1] = q end
        for _, q in ipairs(slot) do
            local c = grid(q[1], q[2])
            if not (c and c.k == "=" and not c.car and not c.nav) then fail("post " .. i .. " square " .. q[1] .. "," .. q[2] .. " not free pavement") end
            if not far(q[1], q[2], function(d) return d.k == "P" end, S.PUMP_GAP) then fail("post " .. i .. " near a pump") end
            if not far(q[1], q[2], function(d) return d.k == "D" end, S.DOOR_GAP) then fail("post " .. i .. " near a door") end
            if not far(q[1], q[2], function(d) return d.line end, S.ROAD_GAP) then fail("post " .. i .. " near a centre line") end
            if not far(q[1], q[2], function(d) return d.nav end, S.NAV_GAP) then fail("post " .. i .. " near a road") end
        end
        for _, q in ipairs(entry) do
            local c = grid(q[1], q[2])
            if not (c and c.k == "=" and not c.car and not c.nav) then fail("post " .. i .. " entry " .. q[1] .. "," .. q[2] .. " blocked") end
        end
    end
    check(ok, label .. (why and (" (" .. why .. ")") or ""))
end

H.section("plan: a forecourt with grass all round: a full row of 4 on the edge nearest the pumps")
local lot = {}
lot[1] = string.rep("g", 34)
for y = 2, 24 do lot[y] = "g" .. string.rep("=", 32) .. "g" end
lot[25] = string.rep("g", 34)
put(lot, 13, 14, "PP==PP")
put(lot, 13, 18, "PP==PP")
local grid, x0, y0, x1, y1, n = forecourt(lot)
check(n == 8 and S.want(n) == 4, "8 pump squares (4 pumps): the station wants 4 posts")
local lotPosts = S.plan(grid, x0, y0, x1, y1, S.want(n))
check(#lotPosts == 4, "4 posts (got " .. #lotPosts .. ")")
audit(grid, lotPosts, "every post backs on the edge, slots paved, 4+ from the pumps, a row 3 apart")
check(lotPosts[1] and lotPosts[1].facing == "E" and lotPosts[1].x == 1, "the row stands on the west edge facing east (the edge nearest the pumps)")

H.section("plan: room for 2 only")
local small = {
    "gggggggggggggggggg",
    "g================g",
    "g================g",
    "g================g",
    "g================g",
    "g================g",
    "g================g",
    "g================g",
    "g================g",
    "g=====PP==PP=====g",
    "g================g",
    "gggggggggggggggggg",
}
grid, x0, y0, x1, y1, n = forecourt(small)
local posts = S.plan(grid, x0, y0, x1, y1, S.want(n))
check(#posts == 2, "a narrow lot: 2 posts though the station wants " .. S.want(n) .. " (got " .. #posts .. ")")
audit(grid, posts, "the 2 posts keep every rule")

H.section("plan: no room at all")
local tight = {
    "gggggggggggg",
    "g==========g",
    "g==========g",
    "g==========g",
    "g===PP=PP==g",
    "g==========g",
    "g==========g",
    "g==========g",
    "gggggggggggg",
}
grid, x0, y0, x1, y1, n = forecourt(tight)
check(#S.plan(grid, x0, y0, x1, y1, S.want(n)) == 0, "a forecourt too small for a slot clear of the pumps: no posts")
local lone = {
    "gggggggggggggggggg",
    "g================g",
    "g================g",
    "g================g",
    "g================g",
    "g================g",
    "g=====PP==PP=====g",
    "g================g",
    "g================g",
    "g================g",
    "gggggggggggggggggg",
}
grid, x0, y0, x1, y1, n = forecourt(lone)
check(#S.plan(grid, x0, y0, x1, y1, 4) == 0, "room for one post only: none (one post alone is no station)")
check(#S.plan(function() return nil end, 0, 0, 0, 0, 4) == 0, "nothing loaded: no posts")

H.section("plan: the shop's door stays clear")
local shop = {} -- open pavement all round (no edge to back on), the shop on the north side
shop[1] = string.rep("I", 60)
shop[2] = string.rep("I", 29) .. "DD" .. string.rep("I", 29)
shop[3] = string.rep("-", 60) -- the shop's south wall on these squares' north edge
for y = 4, 40 do shop[y] = string.rep("=", 60) end
put(shop, 27, 11, "PP==PP")
grid, x0, y0, x1, y1, n = forecourt(shop)
posts = S.plan(grid, x0, y0, x1, y1, S.want(n))
check(#posts == 2, "2 posts along the shop wall (got " .. #posts .. ")")
audit(grid, posts, "none within 3 of the door (or the pumps)")
check(posts[1] and posts[1].y == 2 and posts[1].facing == "S", "they back on the shop's wall, facing the forecourt")

H.section("plan: no posts in a road")
-- an open lot running into a road (no curb), grass only beyond the road: the only edge to back on is across it
local function roadLot(row27)
    local r = {}
    for y = 1, 31 do r[y] = string.rep("=", 60) end
    for y = 23, 31 do r[y] = string.rep("R", 60) end -- the road's Nav zone, lanes 22-30
    r[27] = row27
    r[32] = string.rep("g", 60)
    put(r, 28, 19, "PP==PP")
    return r
end
local road = roadLot(string.rep("y", 60)) -- Nav zone and a painted centre line
grid, x0, y0, x1, y1, n = forecourt(road)
check(#S.plan(grid, x0, y0, x1, y1, S.want(n)) == 0, "Nav road with a centre line: no posts across it")
local unpainted = roadLot(string.rep("R", 60))
grid, x0, y0, x1, y1, n = forecourt(unpainted)
check(#S.plan(grid, x0, y0, x1, y1, S.want(n)) == 0, "Nav road without a painted line: no posts across it")
local dashed = roadLot(string.rep("yR", 30)) -- the centre line broken every other square: no run of ROAD_RUN
grid, x0, y0, x1, y1, n = forecourt(dashed)
check(#S.plan(grid, x0, y0, x1, y1, S.want(n)) == 0, "Nav road with a broken centre line: no posts across it")
-- planted: the same lots without the Nav zone. The broken line alone is no road: the posts go across it; only a
-- solid centre line (maps without Nav zones) still keeps them off.
local function noNav(rows) local t = {} for i, r in ipairs(rows) do t[i] = r:gsub("R", "="):gsub("y", "Y") end return t end
grid, x0, y0, x1, y1, n = forecourt(noNav(dashed))
local planted = S.plan(grid, x0, y0, x1, y1, S.want(n))
check(#planted >= 2 and planted[1].y == 30 and planted[1].facing == "N",
    "planted: the broken line without a Nav zone, the posts back on the far grass, their slots in the lanes")
grid, x0, y0, x1, y1, n = forecourt(noNav(road))
check(#S.plan(grid, x0, y0, x1, y1, S.want(n)) == 0, "no Nav zone, a solid centre line (map mods): still no posts across it")

H.section("plan: no slot in a walled-in yard")
-- x 0..12, y 0..6 paved and walled all round; the pumps on a patch south of it, grass between
local yard = {}
for y = 1, 15 do yard[y] = string.rep("g", 20) end
yard[1] = "+" .. string.rep("-", 12) .. "!" .. string.rep("g", 6)
for y = 2, 7 do yard[y] = "|" .. string.rep("=", 12) .. "!" .. string.rep("g", 6) end
yard[8] = string.rep("~", 13) .. string.rep("g", 7)
for y = 9, 13 do put(yard, 3, y - 1, "========") end
put(yard, 6, 10, "PP")
grid, x0, y0, x1, y1, n = forecourt(yard)
check(#S.plan(grid, x0, y0, x1, y1, S.want(n)) == 0, "the only room is a yard no car can get into: no posts")
local gate = copy(yard)
put(gate, 6, 7, "==") -- a two-square gap in the south wall onto the pumps' patch
grid, x0, y0, x1, y1, n = forecourt(gate)
posts = S.plan(grid, x0, y0, x1, y1, S.want(n))
check(#posts == 2, "planted: the same yard with a two-square gate to the pumps gets its 2 posts (the rule is what stopped it)")
local narrow = copy(yard)
put(narrow, 6, 7, "=") -- one square: a person gets through, a car (1.58 squares wide) does not
grid, x0, y0, x1, y1, n = forecourt(narrow)
check(#S.plan(grid, x0, y0, x1, y1, S.want(n)) == 0, "a one-square gap in the wall: no car gets in, no posts")
-- the pumps 3 squares from the yard inside, the wall between: the lane stops at the wall (a square box of PUMP_GAP
-- around the pumps reached into the yard and let it count as reachable)
local hug = copy(yard)
put(hug, 6, 10, "==")
put(hug, 6, 9, "PP")
grid, x0, y0, x1, y1, n = forecourt(hug)
check(n == 2 and #S.plan(grid, x0, y0, x1, y1, S.want(n)) == 0,
    "pumps by the yard's wall, no gate: the yard is no pump lane, no posts")
local hug2 = copy(hug)
put(hug2, 6, 7, "==")
grid, x0, y0, x1, y1, n = forecourt(hug2)
check(#S.plan(grid, x0, y0, x1, y1, S.want(n)) == 2, "planted: the same with a two-square gate by the pumps: 2 posts")

H.section("plan: parked cars are no lot edge, no slot, no way in")
-- the road lot without the road, a world car parked across it: backing on the car would be the only way to get posts
local parked = {}
for y = 1, 31 do parked[y] = string.rep("=", 60) end
parked[32] = string.rep("g", 60)
put(parked, 28, 19, "PP==PP")
put(parked, 20, 6, "cccccccccccccccccccc")
put(parked, 20, 7, "cccccccccccccccccccc")
grid, x0, y0, x1, y1, n = forecourt(parked)
for _, p in ipairs(S.plan(grid, x0, y0, x1, y1, S.want(n))) do
    check(p.y == 31 - 1 or p.y > 7, "a car across the open lot: no post backs on it (" .. p.x .. "," .. p.y .. ")")
end
-- the grass lot with a car in the first slot the plan took, then in the row a car comes in from
local function blocked(rows, label)
    local g = forecourt(rows)
    local _, gx0, gy0, gx1, gy1, gn = forecourt(rows)
    local ps = S.plan(g, gx0, gy0, gx1, gy1, S.want(gn))
    local hit = false
    for _, p in ipairs(ps) do
        local post, slot, entry = squaresOf(p)
        for _, list in ipairs({ post, slot, entry }) do
            for _, q in ipairs(list) do
                local c = g(q[1], q[2])
                if c and c.car then hit = true end
            end
        end
    end
    check(#ps == 4 and not hit, label .. " (" .. #ps .. " posts)")
end
local inSlot = copy(lot)
put(inSlot, 2, 12, "cc")
blocked(inSlot, "a car parked in the first slot: still 4 posts, no post, slot or way in under it")
local _, _, entry = squaresOf(lotPosts[2])
local inEntry = copy(lot)
put(inEntry, entry[1][1], entry[1][2], "c")
blocked(inEntry, "a car in the row the second slot is entered from: the row moves, nothing under the car")

H.section("cellAt: the square codes from real-looking squares")
IsoFlagType = setmetatable({}, { __index = function(_, k) return k end })
local function list(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end
local function sprite(name, props)
    return { getName = function() return name end,
        getProperties = function() return { has = function(_, k) return props and props[k] or false end } end }
end
-- a fake square: floor sprite name, attached floor overlays, other objects { name, props }, flags, room, car
local function fakeSq(o)
    local floor = { getSprite = function() return sprite(o.floor or "blends_street_01_96") end,
        getAttachedAnimSprite = function()
            local t = {}
            for _, a in ipairs(o.attached or {}) do t[#t + 1] = { getParentSprite = function() return sprite(a) end } end
            return o.attached and list(t) or nil
        end }
    local objs = { floor }
    for _, ob in ipairs(o.objs or {}) do
        objs[#objs + 1] = { _class = ob.class, getSprite = function() return sprite(ob[1], ob[2]) end }
    end
    local flags = {}
    for _, f in ipairs(o.flags or {}) do flags[f] = true end
    return { getObjects = function() return list(objs) end, getFloor = function() return floor end,
        has = function(_, f) return flags[f] == true end, getRoom = function() return o.room end,
        isVehicleIntersecting = function() return o.car == true end, getX = function() return o.x end,
        getY = function() return o.y end, getZ = function() return 0 end }
end
local squares = {}
getCell = function() return { getGridSquare = function(_, x, y) return squares[x .. "," .. y] end } end
-- the one safehouse { x, y, x2, y2 } (x2, y2 exclusive, as SafeHouse.java keeps it) or nil; safeAsked: squares asked
local safeRect, safeAsked = nil, 0
SafeHouse = {
    getSafehouseOverlapping = function(x1, y1, x2, y2)
        local r = safeRect
        return r and x1 < r[3] and x2 > r[1] and y1 < r[4] and y2 > r[2] and r or nil
    end,
    getSafeHouse = function(sq)
        safeAsked = safeAsked + 1
        local r, x, y = safeRect, sq:getX(), sq:getY()
        return r and x >= r[1] and x < r[3] and y >= r[2] and y < r[4] and r or nil
    end,
}
local function code(o, nav, safe)
    o.x, o.y = 0, 0
    squares["0,0"] = fakeSq(o)
    return S.cellAt(0, 0, nav, safe)
end
check(S.cellAt(5, 5) == nil, "no square: nil")
local c = code({ objs = { { "location_shop_fossoil_01_12" } } })
check(c.k == "P", "a Fossoil pump: P")
check(code({ objs = { { "location_shop_gas2go_01_15" } }, flags = { "solid" } }).k == "P", "a Gas2Go pump (solid too): P")
check(code({ flags = { "doorW" } }).k == "D" and code({ flags = { "DoorWallN" } }).k == "D", "a door or a door frame: D")
check(code({ room = {} }).k == "I", "a room: I")
check(code({ flags = { "solidtrans" } }).k == "o", "solidtrans: o")
check(code({ objs = { { "furniture_01_1", { IsMoveAble = true } } } }).k == "o", "a moveable on it: o")
check(code({ objs = { { "x", { IsMoveAble = true } } } , flags = {} }).k == "o"
    and code({ objs = { { "item", { IsMoveAble = true } } } }).k == "o", "another charger (moveable): o")
check(code({ objs = { { "item", { IsMoveAble = true }, class = "IsoWorldInventoryObject" } } }).k == "=", "an item dropped on the floor: still =")
check(code({ flags = { "BlocksPlacement", "canBeRemoved" } }).k == "=", "grass you can cut (BlocksPlacement + canBeRemoved): =")
check(code({ floor = "blends_natural_01_16" }).k == "g" and code({ floor = "floors_exterior_tilesandstone_01_5" }).k == ".",
    "grass g, other floors .")
c = code({ flags = { "WallN", "collideW" } })
check(c.k == "=" and c.wn and c.ww, "walls on the edges: wn, ww, the square still =")
c = code({ attached = { "street_trafficlines_01_25" } })
check(c.line == true, "a bright yellow line attached to the floor (FloorOverlay): line")
check(not code({ attached = { "street_trafficlines_01_17" } }).line and not code({ objs = { { "street_trafficlines_01_25" } } }).line,
    "a faded lot line, or the yellow line as a separate object: no line")
check(code({ car = true }).car == true and code({ car = true, floor = "blends_natural_01_1" }).car == nil, "a car on pavement: car (only on =)")
check(code({}, { { x = -100, y = -1, w = 300, h = 3 } }).nav, "in a street's rectangle: nav")
check(not code({}, { { x = 1, y = 1, w = 5, h = 5 } }).nav, "outside every street: no nav")
safeRect = { 0, 0, 1, 1 }
check(code({}, nil, true).k == "o" and code({ objs = { { "location_shop_fossoil_01_12" } } }, nil, true).k == "P"
    and code({ flags = { "doorW" } }, nil, true).k == "D", "in a safehouse: a free square blocked (o); a pump, a door keep their code")
safeAsked = 0
check(code({}).k == "=" and safeAsked == 0, "no safehouse near the station (safe not set): the square not asked, still =")
safeRect = nil

H.section("roads: the world map's streets, read from streets.xml")
-- a streets.xml as vanilla writes it (WorldMapStreetsXML.java:30-55), from { name, width or false, x, y, x, y, ... }
local function xml(streets)
    local t = { '<streets version="1">' }
    for _, s in ipairs(streets) do
        t[#t + 1] = '    <street name="' .. s[1] .. '"' .. (s[2] and ' width="' .. s[2] .. '"' or "") .. ">"
        t[#t + 1] = "        <points>"
        for i = 3, #s, 2 do t[#t + 1] = string.format('            <point x="%.1f" y="%.1f"/>', s[i], s[i + 1]) end
        t[#t + 1] = "        </points>"
        t[#t + 1] = "    </street>"
    end
    t[#t + 1] = "</streets>"
    return t
end
local function pieces(streets, lines)
    local i, out = 0, {}
    lines = lines or xml(streets)
    return out, S.streetPieces(function() i = i + 1; return lines[i] end, out)
end
local function on(p, ...) -- every x, y given is on a piece
    local a = { ... }
    for i = 1, #a, 2 do
        if not S.onRoad(p, a[i], a[i + 1]) then return false end
    end
    return true
end
local function off(p, ...)
    local a = { ... }
    for i = 1, #a, 2 do
        if S.onRoad(p, a[i], a[i + 1]) then return false end
    end
    return true
end
-- vanilla's zone for a piece along x: x1..x2 - 1, the line's y - width / 2 on, width rows (WorldMapStreet.java:1087-1092)
local p = pieces({ { "Main St", 8, 10, 100.5, 50, 100 } })
check(#p == 1 and on(p, 10, 96, 49, 96, 10, 103, 49, 103) and off(p, 9, 100, 50, 100, 10, 95, 10, 104),
    "a street along x, width 8: 4 rows before the line and 4 from it on, the end point's column out")
p = pieces({ { "Oak Ave", 5, 200.9, 10, 200, 30 } })
check(#p == 1 and on(p, 198, 10, 202, 29) and off(p, 197, 10, 203, 10, 200, 9, 200, 30),
    "a street along y, width 5, points cut to whole squares: 2 columns before the line, 3 from it on")
p = pieces({ { "Hill Rd", 6, 0, 0, 20, 20 } })
check(#p == 1 and on(p, 10, 10, 10, 14, 14, 10) and off(p, 10, 15, 15, 10, 22, 1),
    "a diagonal street, width 6: squares whose centre is within 3 of the line, not the rest of its bounding box")
p = pieces({ { "Creek Rd", 5, 0, 0, 20, 10 } })
check(on(p, 10, 3, 10, 7) and off(p, 10, 2, 10, 8),
    "a diagonal street with an odd width: the line half a square on (vanilla's polyline zone, Zone.java:617)")
p = pieces({ { "Bend St", 6, 0, 50, 30, 50, 40, 60, 40, 90 } })
check(#p == 3 and on(p, 0, 50, 35, 55, 40, 89), "a street with a bend: a piece for each stretch")
p = pieces({ { "A St", 4, 0, 0, 10, 0 }, { "B St", 4, 500, 500, 510, 500 } })
check(#p == 2 and off(p, 250, 250, 11, 0), "two streets: the first one's end not joined to the second one's start")
p = pieces({ { "Railroad", 6, 0, 0, 100, 0 }, { "Fort Knox Branch Line", 6, 0, 10, 100, 10 }, { "Rail St", false, 0, 20, 100, 20 } })
check(#p == 1 and off(p, 50, 0, 50, 10) and on(p, 50, 18, 50, 22) and off(p, 50, 17, 50, 23),
    "railroads are no roads (WorldMapStreet.java:1056-1060); a street with no width is 5 wide")
local whole
p, whole = pieces({ { "Main St", 8, 10, 100, 50, 100 } })
check(whole == true and select(2, pieces(nil, { '<streets version="1"/>' })) == true, "read to the closing tag (or a file with no street): whole")
local cut = xml({ { "Main St", 8, 10, 100, 50, 100 }, { "Oak Ave", 5, 200, 10, 200, 30 } })
cut[#cut], cut[#cut - 1], cut[#cut - 2] = nil, nil, nil
p, whole = pieces(nil, cut)
check(whole == false and #p == 2, "the lines stop before the closing tag (a read error reaches Lua as nil): not whole")
p, whole = pieces(nil, { '<streets version="1"><street name="A St" width="4"><points><point x="0.0" y="0.0"/><point x="10.0" y="0.0"/></points></street></streets>' })
check(whole == false, "a file with its tags on one line (not the layout this reads): not whole, so no plan on half its streets")
-- attributes in another order, as an XML parser takes them (WorldMapStreetsXML.java:76-117)
p = pieces(nil, { '<streets version="1">', '<street name="A St" width="4">', '<point x="0.0" y="0.0"/>', '<point x="10.0" y="0.0"/>',
    '</street>', '<street width="8" name="B St">', '<point y="500.0" x="500.0"/>', '<point y="500.0" x="510.0"/>', '</street>', '</streets>' })
check(#p == 2 and on(p, 500, 496, 509, 503) and off(p, 250, 250, 500, 495, 510, 500),
    "width before name, y before x: the same street, not joined to the one before")
p = pieces({ { "West Rd", 4, -10.5, -0.5, -0.5, -0.5 } })
check(on(p, -10, -2, -1, 1) and off(p, -11, 0, 0, 0, -10, -3, -10, 2), "points below zero are cut towards zero, as Java's (int)")
-- S.roads: every lot directory's file, once a session
local files, opened, closed = {}, 0, 0
local lotDirs = { "Town, KY", "No Streets" }
getLotDirectories = function() return list(lotDirs) end
fileExists = function(path) return files[path] ~= nil end
getGameFilesInput = function(path)
    opened = opened + 1
    local lines, i = files[path], 0
    return lines and { readLine = function() i = i + 1; return lines[i] end } or nil
end
endFileInput = function() closed = closed + 1 end
getWorld = function() error("the save's zones asked") end
files["media/maps/Town, KY/streets.xml"] = xml({ { "Main St", 8, 10, 100, 50, 100 }, { "Far Rd", 8, 5000, 5000, 5100, 5000 } })
S.streets = nil
local near = S.roads(40, 90, 60, 96)
check(#near == 1 and near[1].y == 96 and opened == 1 and closed == 1,
    "the streets touching the squares asked for, from the one directory that has a streets.xml, the file closed")
check(#S.roads(0, 0, 9, 200) == 0 and #S.roads(5050, 4990, 5060, 4996) == 1 and opened == 1,
    "asked again, for other squares: the file is not read twice")
-- a streets.xml that is there and does not read to its end: no roads this session (S.streets false), not read again
S.streets, opened, closed = nil, 0, 0
files["media/maps/Town, KY/streets.xml"] = false -- there (fileExists), no stream for it
check(S.roads(0, 0, 10, 10) == nil and S.streets == false and S.roads(0, 0, 10, 10) == nil and opened == 1,
    "a streets.xml with no stream: no roads, asked once this session")
S.streets, opened = nil, 0
files["media/maps/Town, KY/streets.xml"] = cut
check(S.roads(0, 0, 300, 300) == nil and S.streets == false and closed == 2
    and (H.logLines[#H.logLines] or ""):find("did not read to its end", 1, true),
    "a streets.xml that stops before its closing tag: no roads (not the half that was read), the stream closed, logged")
files, opened, lotDirs, S.streets = {}, 0, { "Lot" }, nil

H.section("build: one record a station, posts once everything is loaded, at most once")
-- S.onPump is what MapObjects.OnLoadWithSprite calls for each pump square of a chunk that loads
H.moddata[S.MODDATA] = nil
-- the world: lot (above) at 1000,1000 as fake squares; chunks loaded per flag
local OX, OY = 1000, 1000
squares = {}
for y, row in ipairs(lot) do
    for x = 1, #row do
        local ch = row:sub(x, x)
        local o = { x = OX + x - 1, y = OY + y - 1 }
        if ch == "P" then o.objs = { { "location_shop_fossoil_01_14" } } elseif ch == "g" then o.floor = "blends_natural_01_1" end
        squares[o.x .. "," .. o.y] = fakeSq(o)
    end
end
local loadedAll, placed = false, {}
getCell = function()
    return {
        getChunkForGridSquare = function(_, x, y) return (loadedAll or (x >= OX and x < OX + 32 and y >= OY and y < OY + 32)) and {} or nil end,
        getGridSquare = function(_, x, y) return squares[x .. "," .. y] end,
    }
end
local objects = {}
local fakeSys = { getLuaObjectCount = function() return #objects end, getLuaObjectByIndex = function(_, i) return objects[i] end }
local realPlace, failAt = S.place, nil
S.place = function(sq, facing)
    if failAt and #placed + 1 == failAt then error("placement failed") end
    placed[#placed + 1] = { x = sq:getX(), y = sq:getY(), facing = facing }
    objects[#objects + 1] = { kind = "Supercharger", x = sq:getX(), y = sq:getY() }
    return {}
end
local function pump(x, y)
    return { getSquare = function() return { getX = function() return x end, getY = function() return y end, getZ = function() return 0 end } end }
end
SMinidoracatTeslaChargerSystem = nil
local hooks = H.count("EveryOneMinute") -- other modules' minute handlers
S.onPump(pump(OX + 13, OY + 14))
local st = H.moddata[S.MODDATA].stations
check(#st == 1 and st[1].x == OX + 13 and st[1].done == false, "first pump square: a station record, waiting")
check(H.count("EveryOneMinute") == hooks + 1, "one minute hook while it waits")
S.onPump(pump(OX + 19, OY + 18))
S.onPump(pump(OX + 13 + S.STATION_R, OY + 14))
check(#st == 1, "the station's other pump squares (and one " .. S.STATION_R .. " away): no second record")
H.fire("EveryOneMinute")
check(#placed == 0 and not st[1].done and not st[1].x0, "the charger system not up yet (new SP game): nothing read, still waiting")
SMinidoracatTeslaChargerSystem = { instance = fakeSys }
local scanned = 0
local cellFn = getCell
getCell = function()
    local c = cellFn()
    local g = c.getGridSquare
    c.getGridSquare = function(self, x, y) scanned = scanned + 1; return g(self, x, y) end
    return c
end
H.fire("EveryOneMinute")
H.fire("EveryOneMinute")
check(#placed == 0 and not st[1].done and not st[1].x0 and scanned == 0 and S.streets == nil,
    "only the station's middle loaded: chunk checks only, no square read (" .. scanned .. "), nothing planned")
-- the pumps scanned in an earlier minute (x0 known), the squares around them not loaded yet: no rescan, still waiting
st[1].x0, st[1].y0, st[1].x1, st[1].y1, st[1].pumps = OX + 13, OY + 14, OX + 18, OY + 18, 8
local done, worked = S.build(st[1])
check(done == false and worked == false and scanned == 0 and S.streets == nil and #placed == 0,
    "pumps known, the plan's squares not loaded: no square read (" .. scanned .. "), nothing planned, waiting")
getCell = cellFn
loadedAll = true
failAt = 2
local ok = pcall(H.fire, "EveryOneMinute")
check(not ok and #placed == 1 and st[1].done == true, "an error placing the second post: the record is done anyway")
H.fire("EveryOneMinute")
check(#placed == 1, "the next minute: no second row around the half-placed one")
failAt = nil
-- a station whose posts exist already (a server down after the chunks were saved, before the global ModData was)
st[1].done = false
S.tick() -- the hook is gone once nothing waits; call the minute handler itself
check(#placed == 1 and st[1].done and st[1].n == 1, "posts already there: marked done, none added")
-- a clean build: the plan's posts, the time logged
placed, objects = {}, {}
st[1].done, st[1].n = false, nil
S.tick()
check(#placed == 4 and st[1].done and st[1].n == 4, "all loaded: 4 posts placed through S.place, the record done")
local same = #placed == #lotPosts
for i, p in ipairs(lotPosts) do
    local q = placed[i]
    if not (q and q.x == OX + p.x and q.y == OY + p.y and q.facing == p.facing) then same = false end
end
check(same and safeAsked == 0, "no safehouse near: placed where the plan said, with its facing, no square asked")
local line = H.logLines[#H.logLines] or ""
check(line:find("planned 4 placed 4", 1, true) and line:find("0 centre line squares", 1, true)
    and line:find("in %- %+ %d+ %+ %d+ %+ %d+ = %d+ ms"), "the log says planned / placed, the centre line squares and the time (scan in an earlier minute): " .. line)
check(H.count("EveryOneMinute") == hooks, "nothing waits: the minute hook is gone")
-- MP: a player's safehouse over the row the plan took (the lot's west strip): no post or slot in it
safeRect = { OX, OY, OX + 8, OY + 25 }
placed, objects = {}, {}
st[1].done, st[1].n = false, nil
S.tick()
local inSafe = false
for _, q in ipairs(placed) do
    local post, slot = squaresOf(q)
    slot[#slot + 1] = post[1]
    for _, s in ipairs(slot) do
        if s[1] >= safeRect[1] and s[1] < safeRect[3] and s[2] >= safeRect[2] and s[2] < safeRect[4] then inSafe = true end
    end
end
line = H.logLines[#H.logLines] or ""
check(#placed >= 2 and not inSafe and placed[1].facing ~= lotPosts[1].facing and line:find("a safehouse near", 1, true),
    "a safehouse over that row: " .. #placed .. " posts elsewhere, no post or slot in it, the log says so: " .. line)
safeRect = nil
H.fire("EveryOneMinute")
local had = #placed
S.onPump(pump(OX + 14, OY + 14))
check(#placed == had and #st == 1 and H.count("EveryOneMinute") == hooks,
    "the same station loading again (another chunk, a later session): no record, no posts, no hook")
S.onPump(pump(OX + 200, OY + 14))
check(#st == 2 and H.count("EveryOneMinute") == hooks + 1, "another station far off: its own record and the hook again")
-- both ready in the same minute: one station's work a minute
placed, objects = {}, {}
st[1].done, st[1].n, st[1].x0 = false, nil, nil
H.fire("EveryOneMinute")
line = H.logLines[#H.logLines] or ""
check(st[1].done and not st[2].done and #placed == 4 and H.count("EveryOneMinute") == hooks + 1,
    "two stations ready the same minute: the first built, the second waits for the next minute")
check(line:find("in %d+ %+ %d+ %+ %d+ %+ %d+ = %d+ ms"), "scanned and built in the same minute: the scan's ms in the log: " .. line)
H.fire("EveryOneMinute")
check(st[2].done and H.count("EveryOneMinute") == hooks, "the next minute: the second built, hook gone again")
-- saved while waiting: the hook comes back when global ModData loads
st[2].done = false
H.fire("OnInitGlobalModData")
check(H.count("EveryOneMinute") == hooks + 1, "a station still waiting in the save: hooked again on OnInitGlobalModData")
st[2].done = true
H.fire("EveryOneMinute")
-- a street down the lot's west strip, where the plan's row stood: the posts go elsewhere, off it
files["media/maps/Lot/streets.xml"] = xml({ { "Pump St", 8, OX + 4, OY - 10, OX + 4, OY + 40 } })
S.streets = nil
placed, objects = {}, {}
st[1].done, st[1].n = false, nil
S.tick()
local onStreet = false
for _, q in ipairs(placed) do
    local post, slot = squaresOf(q)
    slot[#slot + 1] = post[1]
    for _, s in ipairs(slot) do
        if S.onRoad(S.streets, s[1], s[2]) then onStreet = true end
    end
end
line = H.logLines[#H.logLines] or ""
check(#placed >= 2 and not onStreet and placed[1].facing ~= lotPosts[1].facing and line:find("1 street pieces", 1, true),
    "a street over that row: " .. #placed .. " posts elsewhere, no post or slot on it, the log counts it: " .. line)
check(st[1].v == S.RULES, "the record keeps the rules' version it was planned with")
-- the streets do not read this session: the station waits, nothing placed, the file asked once; a later session plans it
files["media/maps/Lot/streets.xml"] = false
S.streets, opened = nil, 0
placed, objects = {}, {}
st[1].done, st[1].n, st[1].v = false, nil, nil
S.tick()
S.tick()
check(#placed == 0 and st[1].done == false and st[1].v == nil and opened == 1,
    "the streets did not read: the station still waits (not marked done), no posts, the file not asked again the next minute")
files, S.streets = {}, nil
S.tick()
check(#placed == 4 and st[1].done and st[1].n == 4, "a later session reads the streets: the station is planned then")
-- a station 0.6.0 planned to no posts (the save's old Nav zones over its forecourt): once more when its pumps load
files, S.streets = {}, nil
placed, objects = {}, {}
st[1].done, st[1].n, st[1].v = true, 0, nil
S.onPump(pump(OX + 13, OY + 14))
S.onPump(pump(OX + 14, OY + 14))
check(st[1].done == false and #st == 2 and H.count("EveryOneMinute") == hooks + 1,
    "a station an older version left without posts, loading again: waiting once more, one hook")
H.fire("EveryOneMinute")
check(#placed == 4 and st[1].done and st[1].v == S.RULES and H.count("EveryOneMinute") == hooks,
    "planned again by this version's rules: 4 posts, hook gone")
placed, objects = {}, {}
st[1].n = 0
S.onPump(pump(OX + 13, OY + 14))
st[2].n, st[2].v = 3, nil
S.onPump(pump(OX + 200, OY + 14))
check(st[1].done and st[2].done and #placed == 0 and H.count("EveryOneMinute") == hooks,
    "no posts by this version's rules, or posts from an older version: not planned again")
-- an older version's plan that stopped half way (done, no n recorded): planned again, the posts it did put down counted
objects = { { kind = "Supercharger", x = OX + 1, y = OY + 5 } }
st[1].done, st[1].n, st[1].v = true, nil, nil
S.onPump(pump(OX + 13, OY + 14))
H.fire("EveryOneMinute")
check(st[1].done and st[1].n == 1 and st[1].v == S.RULES and #placed == 0,
    "an older record with no post count: looked at again, the post already there counted, none added")

S.place = realPlace
H.moddata[S.MODDATA] = nil
getCell, getWorld, MapObjects, SMinidoracatTeslaChargerSystem, IsoFlagType, SafeHouse =
    saved.getCell, saved.getWorld, saved.MapObjects, saved.sys, saved.IsoFlagType, saved.SafeHouse
getLotDirectories, fileExists, getGameFilesInput, endFileInput =
    saved.getLotDirectories, saved.fileExists, saved.getGameFilesInput, saved.endFileInput
S.streets = nil
