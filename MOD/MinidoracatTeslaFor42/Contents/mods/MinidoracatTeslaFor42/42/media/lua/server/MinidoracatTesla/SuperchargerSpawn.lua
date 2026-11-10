-- V4 Superchargers at gas stations (decisions.md "超級充電座", user 2026-11-09): 2-4 posts a station, put down once,
-- the way a player places one (vanilla placeMoveableInternal), on the server only.
-- Trigger: MapObjects.OnLoadWithSprite on the gas pump sprites (every tiledef tile with fuelAmount: Fossoil and Gas2Go
-- 12-15, newtiledefinitions.tiles). MapObjects.loadGridSquare runs for each square of every chunk that loads, from the
-- save too (IsoChunk.java:3825-3829; newGridSquare only for a brand-new one), and for a tile object added through
-- IsoGridSquare.addTileObject / IsoCell / RandomizedWorldBase (IsoGridSquare.java:10660-10662, IsoCell.java:4234-4236,
-- RandomizedWorldBase.java:1239-1240,1264-1265): a station explored before the MOD was added gets its posts the next
-- time its chunks load (user 2026-11-09), and every later load finds its record and does nothing.
-- Neighbour chunks may not be loaded yet then (SP: one chunk at a time, IsoChunkMap.java:182-207; MP: a 64x64 server
-- cell, ServerMap.java:927-956), and the charger system does not exist yet for the first chunks of a new SP game
-- (IsoWorld init loads them before GameLoadingState.java:313 initSystems). So the callback only records the station
-- in global ModData (server save) and the posts go down on a later EveryOneMinute, once the chunks around it are
-- loaded and the charger system is up. The record also dedupes: pumps within STATION_R of a known station are the
-- same station, whichever chunk or session they load in; a done station stays done (posts picked up are not put
-- back). On a server no post or slot goes in a safehouse (S.cellAt's safe).
if isClient() then return end
require "MinidoracatTesla/Chargers"
require "Moveables/ISMoveableSpriteProps"

local T = MinidoracatTesla
local S = {}
T.SuperchargerSpawn = S

S.PUMPS = {}
for _, brand in ipairs({ "fossoil", "gas2go" }) do
    for i = 12, 15 do S.PUMPS["location_shop_" .. brand .. "_01_" .. i] = true end
end
-- { stations = { { x, y, done, n, v, x0, y0, x1, y1, pumps } } }: x, y = the first pump seen; x0..y1 its pumps'
-- extent; n posts; v = S.RULES when it was planned (nil: 0.6.0)
S.MODDATA = "MinidoracatTeslaSupercharger"
-- the rules' version. A station an older version planned to no posts is planned once more the next time its pumps
-- load (S.onPump). 2: roads are the world map's streets whatever zones the save has (S.roads); 0.6.0 asked the
-- save's Nav zones and found no room at 14 of the production server's 39 stations.
S.RULES = 2
S.STATION_R = 32  -- pumps this close (Chebyshev) are one station: the longest vanilla station spans 27 tiles (Rosewood)
S.MARGIN = 12     -- posts stand this far from the station's pumps at most
S.DEPTH = 5       -- the parking slot in front of a post: 5 deep x 2 wide (a Tesla is about 4 x 1.6 tiles)
S.SPACING = 3     -- post to post along a row: a 2-wide slot and a 1-tile gap
S.PUMP_GAP = 4    -- post and slot squares at least this far (Chebyshev) from a pump: a lane stays beside each island
S.DOOR_GAP = 3    -- and from a door: the shop's entrance stays open
-- and from a road (a street, S.roads) by 2: a street's rectangle is its width attribute wide and leaves out the
-- asphalt row with the curb on each side (streets.xml width, WorldMapStreet.java:1087-1092; measured near the 46
-- vanilla stations: that row is street floor all along the edge). Same plans as 1 at all 46 stations.
S.NAV_GAP = 2
-- maps without streets.xml (map mods): a road's centre line, a straight run of ROAD_RUN bright yellow line squares
-- (street_trafficlines_01_24-31, FloorOverlay tiles the cell loader puts on the floor's attached sprites; lots paint
-- the faded 16-23 and yellow curbs). Muldraugh's 4-lane highway at 10585-10598,9745 is 5-6 squares from its centre
-- line to either edge.
S.ROAD_GAP = 7
S.ROAD_RUN = 8
S.CENTRE_LINES = {}
for i = 24, 31 do S.CENTRE_LINES["street_trafficlines_01_" .. i] = true end
-- how far past the pumps the plan reads squares: the farthest slot square (side column, the row a car comes in
-- from) and a pump, door or road the gap away from it
S.REACH = S.MARGIN + S.DEPTH + 2 + math.max(S.PUMP_GAP, S.DOOR_GAP, S.NAV_GAP, S.ROAD_GAP)

local DIRS = { S = { 0, 1 }, E = { 1, 0 }, N = { 0, -1 }, W = { -1, 0 } }
local FACINGS = { "S", "E", "N", "W" }

-- ---- the plan: pure, over a grid of square codes (harness: scripts/harness/test_supercharger_spawn.lua) ----
-- grid(x, y) -> nil (no square) or { k, wn, ww, nav, line, car }: k "=" paved and free (street floor, nothing in the
-- way), "P" pump, "D" door, "I" indoors, "o" blocked, "g" grass, "." other floor, " " nothing; wn / ww: a wall, fence,
-- door or window on the square's north / west edge; nav: on a road (a street, S.roads); line: a bright yellow
-- traffic line on it; car: a car stands on it (still "=": a parked car is no lot edge to back a post on, but nothing
-- goes under it).
-- A post faces f with its slot in front: S.DEPTH rows of 2 squares, the post's column and the one on the car's
-- right (backed in, its rear-left charge port by the post). Rules:
-- - post and slot squares paved, free, outdoors, no car, no road; PUMP_GAP / DOOR_GAP / NAV_GAP / ROAD_GAP clear;
-- - no edge wall inside the slot or between post and slot; the squares a car drives in from (row DEPTH + 1) paved,
--   edge-free, no car, no road;
-- - a car fits from there to a road or a pump's lane: 2 x 2 blocks of paved squares with no wall inside, each next to
--   the last (a Model Y is 1.58 squares wide, VehicleScript.java:436-438,463-473), from the block of the slot's last
--   row and the row a car comes in from to a block with a road square or a lane square (paved, PUMP_GAP - 1 steps or
--   fewer from a pump without crossing a wall: a car that gets to the pumps gets out to the road). No slot in a
--   walled-in yard, behind a one-square gap, or by a pump on the far side of the yard's wall;
-- - the post's back on the lot's edge (behind it: not open pavement, or a wall between), so no post stands in the
--   middle of the forecourt.
-- Posts go in a row SPACING apart. Picks the longest row (up to want), then the one nearest the pumps. No row of 2:
-- no posts.
local function side(f) return -f[2], f[1] end

-- posts: { { x, y, facing } } for the station whose pumps lie in x0..x1, y0..y1 (grid covers S.REACH around it)
function S.plan(grid, x0, y0, x1, y1, want)
    local R = S.REACH
    local BX, BY = x0 - R, y0 - R
    local W, H = x1 - x0 + 2 * R + 1, y1 - y0 + 2 * R + 1
    local C, near = {}, {}
    local function id(x, y)
        if x < BX or y < BY or x >= BX + W or y >= BY + H then return nil end
        return (y - BY) * W + (x - BX) + 1
    end
    for y = BY, BY + H - 1 do
        for x = BX, BX + W - 1 do C[id(x, y)] = grid(x, y) or false end
    end
    local function at(x, y)
        local i = id(x, y)
        return i and C[i] or nil
    end
    local function mark(set, x, y, r)
        for dx = 1 - r, r - 1 do
            for dy = 1 - r, r - 1 do
                local i = id(x + dx, y + dy)
                if i then set[i] = true end
            end
        end
    end
    local function run(x, y, dx, dy) -- line squares from x, y on, up to ROAD_RUN
        local n = 0
        while n < S.ROAD_RUN do
            local c = at(x + n * dx, y + n * dy)
            if not (c and c.line) then break end
            n = n + 1
        end
        return n
    end
    local px, py, np, pumps = 0, 0, 0, {}
    for y = BY, BY + H - 1 do
        for x = BX, BX + W - 1 do
            local c = at(x, y)
            if c then
                if c.k == "P" then
                    mark(near, x, y, S.PUMP_GAP)
                    px, py, np = px + x, py + y, np + 1
                    pumps[np] = id(x, y)
                elseif c.k == "D" then mark(near, x, y, S.DOOR_GAP) end
                if c.nav then mark(near, x, y, S.NAV_GAP) end
                if c.line and (run(x, y, 1, 0) + run(x, y, -1, 0) > S.ROAD_RUN
                    or run(x, y, 0, 1) + run(x, y, 0, -1) > S.ROAD_RUN) then
                    mark(near, x, y, S.ROAD_GAP)
                end
            end
        end
    end
    if np == 0 then return {} end
    px, py = px / np, py / np

    -- a wall between neighbours: i and i + 1 (on the west edge of i + 1), i and i + W (on the north edge of i + W)
    local function wallE(i) local e = C[i + 1]; return not e or e.ww end
    local function wallS(i) local d = C[i + W]; return not d or d.wn end
    local LAST = W * H
    -- the pumps' lanes: squares up to PUMP_GAP - 1 steps from a pump square, never across a wall nor over a blocked
    -- square (a canopy over the pumps is a room: indoors squares count, the building's walls stop the walk)
    local lane, step, q, head = {}, {}, {}, 1
    for k, i in ipairs(pumps) do q[k] = i; step[i] = 0 end
    local function walk(i, j, wall)
        if step[j] or wall then return end
        local d = C[j]
        if not d or d.k == "o" or d.k == " " then return end
        step[j] = step[i] + 1
        lane[j] = true
        if step[j] < S.PUMP_GAP - 1 then q[#q + 1] = j end
    end
    while q[head] do
        local i = q[head]
        head = head + 1
        local col = (i - 1) % W
        if i > W then walk(i, i - W, wallS(i - W)) end
        if i + W <= LAST then walk(i, i + W, wallS(i)) end
        if col > 0 then walk(i, i - 1, wallE(i - 1)) end
        if col < W - 1 then walk(i, i + 1, wallE(i)) end
    end

    -- where a car fits: 2 x 2 blocks (by their top-left square) of paved squares with no wall inside; two blocks one
    -- square apart overlap, so a car moves from one to the next. Blocks grouped by that; does the group hold a road
    -- or lane square. One flood per group, numeric ids (no string keys: Kahlua).
    local function paved(c) return c and (c.k == "=" or c.nav) end
    local blk = {}
    local function block(i)
        local b = blk[i]
        if b == nil then
            local c, e, d, de = C[i], C[i + 1], C[i + W], C[i + W + 1]
            b = (i - 1) % W < W - 1 and i + W <= LAST and paved(c) and paved(e) and paved(d) and paved(de)
                and not e.ww and not de.ww and not d.wn and not de.wn or false
            blk[i] = b
        end
        return b
    end
    local function exit(i)
        local c, e, d, de = C[i], C[i + 1], C[i + W], C[i + W + 1]
        return c.nav or e.nav or d.nav or de.nav or lane[i] or lane[i + 1] or lane[i + W] or lane[i + W + 1]
    end
    local group, out = {}, {}
    local function connected(i0)
        if group[i0] then return out[group[i0]] end
        if not block(i0) then return false end
        local g, ok = #out + 1, false
        group[i0] = g
        local qb, hb = { i0 }, 1
        local function go(j)
            if j >= 1 and j <= LAST and not group[j] and block(j) then
                group[j] = g
                qb[#qb + 1] = j
            end
        end
        while qb[hb] do
            local i = qb[hb]
            hb = hb + 1
            if not ok and exit(i) then ok = true end
            local col = (i - 1) % W
            go(i - W)
            go(i + W)
            if col > 0 then go(i - 1) end
            go(i + 1) -- block() turns down the last column
        end
        out[g] = ok
        return ok
    end

    -- a post or slot square: paved, free, no car, no road, no gap
    local open = {}
    for i = 1, W * H do
        local c = C[i]
        open[i] = c and c.k == "=" and not c.car and not c.nav and not near[i] or false
    end
    -- posts stand within MARGIN of the pumps: the slot, the row the car comes from and the back are all inside the
    -- grid (REACH > MARGIN + DEPTH + 2), so their ids are plain offsets (Kahlua: no per-square bounds or closures)
    local DEPTH = S.DEPTH
    local function postOK(x, y, f)
        if x < x0 - S.MARGIN or x > x1 + S.MARGIN or y < y0 - S.MARGIN or y > y1 + S.MARGIN then return false end
        local i = id(x, y)
        if not open[i] then return false end
        local fx, fy = f[1], f[2]
        local sx, sy = side(f)
        local df, ds = fy * W + fx, sy * W + sx
        local c = C[i]
        if (fy < 0 and c.wn) or (fx < 0 and c.ww) then return false end -- the edge between post and slot
        for k = 1, DEPTH do
            local a = i + k * df
            if not (open[a] and open[a + ds]) then return false end
        end
        for k = 1, DEPTH + 1 do
            local a = i + k * df
            for j = 0, ds, ds do
                local q = C[a + j]
                if not q or q.wn or q.ww then return false end
                if k > DEPTH and (q.k ~= "=" or q.car or q.nav) then return false end -- where the car comes in from
            end
        end
        -- the back: off the pavement, or a wall between
        local b = C[i - df]
        if b and b.k == "=" then
            if fy > 0 then if not c.wn then return false end
            elseif fy < 0 then if not b.wn then return false end
            elseif fx > 0 then if not c.ww then return false end
            elseif not b.ww then return false end
        end
        -- the 2 x 2 block of the slot's last row and the row a car comes in from: its top-left is the smallest id
        local a = i + DEPTH * df
        return connected(math.min(a, a + df, a + ds, a + df + ds))
    end
    local best, bestN, bestD = nil, 0, math.huge
    for x = x0 - S.MARGIN, x1 + S.MARGIN do
        for y = y0 - S.MARGIN, y1 + S.MARGIN do
            for _, name in ipairs(FACINGS) do
                local f = DIRS[name]
                local sx, sy = side(f)
                local n = 0
                while n < want and postOK(x + n * S.SPACING * sx, y + n * S.SPACING * sy, f) do n = n + 1 end
                if n > 0 then
                    -- nearest to the pumps: the row's middle, half a car in front of it
                    local mx = x + (n - 1) * S.SPACING * sx / 2 + f[1] * 2.5
                    local my = y + (n - 1) * S.SPACING * sy / 2 + f[2] * 2.5
                    local d = (mx - px) ^ 2 + (my - py) ^ 2
                    if n > bestN or (n == bestN and d < bestD) then
                        best, bestN, bestD = { x = x, y = y, f = name }, n, d
                    end
                end
            end
        end
    end
    local posts = {}
    if bestN < 2 then return posts end -- one post alone is no Supercharger station
    local sx, sy = side(DIRS[best.f])
    for i = 0, bestN - 1 do
        posts[#posts + 1] = { x = best.x + i * S.SPACING * sx, y = best.y + i * S.SPACING * sy, facing = best.f }
    end
    return posts
end

-- posts a station gets by its pump squares (2 a pump): 2-4
function S.want(pumpSquares) return math.max(2, math.min(4, math.floor(pumpSquares / 2))) end

-- the station record pump (x, y) belongs to, or nil
function S.stationOf(stations, x, y)
    for _, s in ipairs(stations) do
        if math.abs(s.x - x) <= S.STATION_R and math.abs(s.y - y) <= S.STATION_R then return s end
    end
    return nil
end

-- ---- the world ----
local function md()
    local t = ModData.getOrCreate(S.MODDATA)
    t.stations = t.stations or {}
    return t
end

local EDGE_N = { "collideN", "WallN", "WallNW", "WallNTrans", "doorN", "DoorWallN", "windowN", "WindowN", "HoppableN" }
local EDGE_W = { "collideW", "WallW", "WallNW", "WallWTrans", "doorW", "DoorWallW", "windowW", "WindowW", "HoppableW" }
local DOORS = { "doorN", "doorW", "DoorWallN", "DoorWallW" }
-- the IsoFlagType values, looked up once (a field of a Java enum per square per flag adds up over ~4000 squares)
local F
local function flags()
    F = {}
    for _, list in ipairs({ EDGE_N, EDGE_W, DOORS, { "solid", "solidtrans", "canBeCut", "canBeRemoved" } }) do
        for _, n in ipairs(list) do F[n] = IsoFlagType[n] end
    end
    for _, t in ipairs({ EDGE_N, EDGE_W, DOORS }) do
        for i, n in ipairs(t) do t[i] = F[n] end
    end
end
local function anyFlag(sq, list)
    for _, f in ipairs(list) do
        if sq:has(f) then return true end
    end
    return false
end

-- ---- roads: the world map's streets ----
-- Vanilla turns each lot directory's streets.xml into Nav zones when a world loads (IsoWorld.registerNavZones,
-- IsoWorld.java:446-457, from metazoneHandler.lua:178-184; objects.lua's own Nav entries are skipped, :93), but a
-- save keeps the zones it was made with: IsoMetaGrid.load swaps every zone for map_zone.bin's right after
-- (IsoWorld.java:2063-2067, IsoMetaGrid.java:1793-1840). A world older than the streets still has objects.lua's Nav,
-- painted over whole forecourts. So the streets are read here, the way WorldMapStreet.registerNavZones makes zones
-- of them (WorldMapStreet.java:1055-1111): points cut to whole squares; a piece along x or y is a rectangle the
-- street's width wide (width / 2 squares before the line, the rest after); a diagonal piece is every square whose
-- centre is within width / 2 of it (vanilla: a polyline zone, the line moved half a square when the width is odd and
-- offset by width / 2 with mitred joins and butt ends, Zone.java:604-643; round here: the same squares but for a
-- corner square at a bend or a dead end); a railroad is no road.
-- nextLine() -> the next line of a streets.xml or nil (as vanilla writes the file, WorldMapStreetsXML.java:30-55: a
-- tag a line, name before width, x before y). Adds every piece to out: { x, y, w, h } the bounding box of its
-- squares, and for a diagonal one ax, ay (where it starts), dx, dy, len2, r2 (width / 2 squared).
function S.streetPieces(nextLine, out)
    local width, px, py -- width nil: a railroad, or no street yet
    for line in nextLine do
        local a, b = line:match('<point x="([^"]+)" y="([^"]+)"')
        if a then
            local x, y = math.floor(tonumber(a) or 0), math.floor(tonumber(b) or 0)
            if px and width then
                if px == x or py == y then
                    local half = math.floor(width / 2)
                    out[#out + 1] = { x = px == x and x - half or math.min(px, x), y = py == y and y - half or math.min(py, y),
                        w = py == y and math.abs(x - px) or width, h = px == x and math.abs(y - py) or width }
                else
                    local d, r = width % 2 == 0 and 0 or 0.5, width / 2
                    local bx, by = math.floor(math.min(px, x) + d - r), math.floor(math.min(py, y) + d - r)
                    out[#out + 1] = { x = bx, y = by, w = math.ceil(math.max(px, x) + d + r) - bx,
                        h = math.ceil(math.max(py, y) + d + r) - by, ax = px + d, ay = py + d, dx = x - px, dy = y - py,
                        len2 = (x - px) ^ 2 + (y - py) ^ 2, r2 = r * r }
                end
            end
            px, py = x, y
        else
            local name = line:match('<street name="([^"]*)"')
            if name then
                name = name:lower()
                width = not name:find("railroad", 1, true) and not name:find("branch line", 1, true)
                    and (tonumber(line:match('width="(%d+)"')) or 5) or nil
                px = nil
            end
        end
    end
    return out
end

-- is square x, y on one of the pieces
function S.onRoad(pieces, x, y)
    for _, p in ipairs(pieces) do
        if x >= p.x and y >= p.y and x < p.x + p.w and y < p.y + p.h then
            if not p.dx then return true end
            local qx, qy = x + 0.5 - p.ax, y + 0.5 - p.ay
            local t = (qx * p.dx + qy * p.dy) / p.len2
            t = t < 0 and 0 or t > 1 and 1 or t
            qx, qy = qx - t * p.dx, qy - t * p.dy
            if qx * qx + qy * qy <= p.r2 then return true end
        end
    end
    return false
end

-- the pieces touching x0..x1, y0..y1. The streets are read once a session, the first time a station is planned:
-- getGameFilesInput gives a DataInputStream on a game or mod file (LuaManager.java:6819-6842), no buffer, so
-- readLine takes the file a byte a call (about 0.3 s for vanilla's 300 KB). A streets.xml that is there and cannot
-- be read is an error: no plan without the roads.
function S.roads(x0, y0, x1, y1)
    if not S.streets then
        local t0, list, files = getTimestampMs(), {}, 0
        local dirs = getLotDirectories()
        for i = 0, dirs:size() - 1 do
            local path = "media/maps/" .. dirs:get(i) .. "/streets.xml"
            if fileExists(path) then
                local input = getGameFilesInput(path)
                if not input then error("supercharger spawn: cannot read " .. path) end
                S.streetPieces(function() return input:readLine() end, list)
                endFileInput()
                files = files + 1
            end
        end
        S.streets = list
        T.log("supercharger spawn: " .. #list .. " street pieces from " .. files .. " streets.xml in "
            .. (getTimestampMs() - t0) .. " ms")
    end
    local out = {}
    for _, p in ipairs(S.streets) do
        if p.x <= x1 and p.x + p.w > x0 and p.y <= y1 and p.y + p.h > y0 then out[#out + 1] = p end
    end
    return out
end

local function pumpOn(sq)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local spr = objs:get(i):getSprite()
        local name = spr and spr:getName()
        if name and S.PUMPS[name] then return true end
    end
    return false
end

-- the code S.plan reads for square x, y, 0 (nav: S.roads); nil when it is not loaded. safe: a safehouse overlaps
-- the plan's squares (SafeHouse.java:181-189), so ask each free square (getSafeHouse: the one holding it, whoever the
-- player, :157-159,201-222) and block it: the claimed lot is the player's
function S.cellAt(x, y, nav, safe)
    local sq = getCell():getGridSquare(x, y, 0)
    if not sq then return nil end
    if not F then flags() end
    local c = { k = " ", wn = anyFlag(sq, EDGE_N), ww = anyFlag(sq, EDGE_W) }
    if nav and S.onRoad(nav, x, y) then c.nav = true end
    local objs, floor, moveable = sq:getObjects(), sq:getFloor(), false
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local spr = o:getSprite()
        if spr and o ~= floor then
            if S.PUMPS[spr:getName()] then c.k = "P"; return c end
            if not moveable and not instanceof(o, "IsoWorldInventoryObject") and spr:getProperties():has("IsMoveAble") then
                moveable = true -- furniture, a sign, another charger
            end
        end
    end
    -- road paint is a FloorOverlay: the cell loader attaches it to the floor (CellLoader.java:256-264), the way
    -- vanilla reads it back in ISNaturalFloor.lua:121-124
    local att = floor and floor:getAttachedAnimSprite()
    for i = 0, att and att:size() - 1 or -1 do
        local p = att:get(i):getParentSprite()
        if p and S.CENTRE_LINES[p:getName()] then c.line = true end
    end
    if anyFlag(sq, DOORS) then
        c.k = "D"
    elseif sq:getRoom() then
        c.k = "I"
    elseif moveable or sq:has(F.solid) or sq:has(F.solidtrans) or sq:has(F.canBeCut)
        or (sq:has("BlocksPlacement") and not sq:has(F.canBeRemoved)) or sq:has("tree") then
        c.k = "o" -- vanilla isFreeTile (ISMoveableSpriteProps.lua:1074-1083) and solid things
    else
        local n = floor and floor:getSprite() and floor:getSprite():getName() or ""
        if n:find("^blends_street") or n:find("^floors_exterior_street") then c.k = "="
        elseif n:find("^blends_natural") then c.k = "g"
        elseif n ~= "" then c.k = "." end
    end
    if safe and c.k == "=" and SafeHouse.getSafeHouse(sq) then c.k = "o" end
    c.car = c.k == "=" and sq:isVehicleIntersecting() or nil -- IsoGridSquare.java:9895
    return c
end

-- every chunk under x0..x1, y0..y1 (z 0) loaded and done: SP adds a chunk to the map right before its
-- doLoadGridsquare (IsoChunkMap.java:187-207), the server loads a whole server cell in one call (ServerMap.java:839-969)
local function loaded(x0, y0, x1, y1)
    local cell = getCell()
    for cx = math.floor(x0 / 8), math.floor(x1 / 8) do
        for cy = math.floor(y0 / 8), math.floor(y1 / 8) do
            if not cell:getChunkForGridSquare(cx * 8, cy * 8, 0) then return false end
        end
    end
    return true
end

-- the vanilla placement, as a player putting the item down (ISMoveableSpriteProps.lua:2075-2570: the same
-- IsoThumpable and settings, Chargers.lua's wrap of it, transmitCompleteItemToClients on the server :2537-2539, and
-- OnObjectAdded :2541 that registers it with the charger system, ChargerSystem.lua). No owner: a public charger.
function S.place(sq, facing)
    local c = T.Chargers.Supercharger
    local name = c.sprites[facing]
    local props = ISMoveableSpriteProps.new(getSprite(name))
    return props:placeMoveableInternal(nil, sq, instanceItem(c.item), name)
end

-- Superchargers the charger system has in x0..x1, y0..y1
local function existing(sys, x0, y0, x1, y1)
    local n = 0
    for i = 1, sys:getLuaObjectCount() do
        local o = sys:getLuaObjectByIndex(i)
        if o.kind == "Supercharger" and o.x >= x0 and o.x <= x1 and o.y >= y0 and o.y <= y1 then n = n + 1 end
    end
    return n
end

-- station record s: done (true when done, false while waiting for the charger system or chunks), worked (true when
-- it scanned the pumps or planned: the minute's heavy part)
function S.build(s)
    local sys = SMinidoracatTeslaChargerSystem and SMinidoracatTeslaChargerSystem.instance
    if not sys then return false, false end
    local t0 = getTimestampMs()
    local scan -- ms, when the pumps were scanned in this call
    -- the pumps' extent once every square within STATION_R is loaded (kept: no rescan while the rest loads)
    if not s.x0 then
        local R = S.STATION_R
        if not loaded(s.x - R, s.y - R, s.x + R, s.y + R) then return false, false end
        local cell, pumps = getCell(), 0
        local x0, y0, x1, y1 = s.x, s.y, s.x, s.y
        for x = s.x - R, s.x + R do
            for y = s.y - R, s.y + R do
                local sq = cell:getGridSquare(x, y, 0)
                if sq and pumpOn(sq) then
                    pumps = pumps + 1
                    x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
                end
            end
        end
        s.x0, s.y0, s.x1, s.y1, s.pumps = x0, y0, x1, y1, pumps
        scan = getTimestampMs() - t0
    end
    local R = S.REACH
    local bx0, by0, bx1, by1 = s.x0 - R, s.y0 - R, s.x1 + R, s.y1 + R
    if not loaded(bx0, by0, bx1, by1) then
        if scan then
            T.log("supercharger spawn: station " .. s.x .. "," .. s.y .. " scanned " .. s.pumps .. " pump squares in "
                .. scan .. " ms, waiting for the squares around it")
        end
        return false, scan ~= nil
    end
    -- at most once: done before anything is placed (an error half way, or a server down after the chunks were saved
    -- and before the global ModData was, must not put down a second row)
    s.done = true
    s.v = S.RULES
    local had = existing(sys, bx0, by0, bx1, by1)
    if had > 0 then
        s.n = had
        T.log("supercharger spawn: station " .. s.x .. "," .. s.y .. " already has " .. had .. " posts")
        return true, scan ~= nil
    end
    local ta = getTimestampMs()
    local nav = S.roads(bx0, by0, bx1, by1)
    local safe = SafeHouse.getSafehouseOverlapping(bx0, by0, bx1 + 1, by1 + 1) ~= nil -- x2, y2 exclusive
    local W, cells, lines = bx1 - bx0 + 1, {}, 0
    for y = by0, by1 do
        for x = bx0, bx1 do
            local c = S.cellAt(x, y, nav, safe) or false
            cells[(y - by0) * W + (x - bx0) + 1] = c
            if c and c.line then lines = lines + 1 end
        end
    end
    local tr = getTimestampMs()
    local posts = S.plan(function(x, y) return cells[(y - by0) * W + (x - bx0) + 1] or nil end, s.x0, s.y0, s.x1, s.y1,
        S.want(s.pumps))
    local t1 = getTimestampMs()
    local n = 0
    for _, p in ipairs(posts) do
        local sq = getCell():getGridSquare(p.x, p.y, 0)
        if sq and S.place(sq, p.facing) then n = n + 1 end
    end
    s.n = n
    local t2 = getTimestampMs()
    T.log("supercharger spawn: station " .. s.x .. "," .. s.y .. " (" .. s.pumps .. " pump squares, " .. #nav
        .. " street pieces, " .. lines .. " centre line squares" .. (safe and ", a safehouse near" or "") .. ") planned "
        .. #posts .. " placed " .. n
        .. (posts[1] and (" facing " .. posts[1].facing .. " from " .. posts[1].x .. "," .. posts[1].y) or "")
        .. " in " .. (scan and tostring(scan) or "-") .. " + " .. (tr - ta) .. " + " .. (t1 - tr) .. " + " .. (t2 - t1)
        .. " = " .. (t2 - t0) .. " ms (scan + read + plan + place; scan - = an earlier minute)")
    return true, true
end

-- each game minute while a station waits (no tick: AGENTS.md rule 2), the heavy part of one station at most (two
-- stations ready in the same minute do not add up); unhooks itself when none is left
local hooked = false
local function tick()
    local left, worked = false, false
    for _, s in ipairs(md().stations) do
        if not s.done then
            if worked then
                left = true
            else
                local done, w = S.build(s)
                worked = w
                if not done then left = true end
            end
        end
    end
    if not left then
        Events.EveryOneMinute.Remove(tick)
        hooked = false
    end
end
S.tick = tick
local function hook()
    if hooked then return end
    hooked = true
    Events.EveryOneMinute.Add(tick)
end

-- MapObjects callback: a pump square in a chunk that loads (new or from the save), or a pump put down
function S.onPump(isoObject)
    local sq = isoObject:getSquare()
    if not sq or sq:getZ() ~= 0 then return end
    local x, y = sq:getX(), sq:getY()
    local t = md()
    local s = S.stationOf(t.stations, x, y)
    if s then
        if s.done and (s.n or 0) == 0 and (s.v or 1) < S.RULES then
            s.done = false
            T.log("supercharger spawn: station " .. s.x .. "," .. s.y .. " got no posts under older rules, planning it again")
            hook()
        end
        return
    end
    t.stations[#t.stations + 1] = { x = x, y = y, done = false }
    T.log("supercharger spawn: new station at " .. x .. "," .. y)
    hook()
end

local list = {}
for name in pairs(S.PUMPS) do list[#list + 1] = name end
-- priority 41, not vanilla's 5 (every MapObjects/MO*.lua uses 5): a second callback on the same sprite with the same
-- priority replaces the first (MapObjects.java:148-152), so another MOD's pump hook copying 5 would silently drop one
-- of the two. Higher runs first: the station is recorded before anything else touches the pump.
MapObjects.OnLoadWithSprite(list, S.onPump, 41)
-- a station still waiting when the game was saved (GlobalModData.init, IsoWorld.java:2009)
Events.OnInitGlobalModData.Add(function()
    for _, s in ipairs(md().stations) do
        if not s.done then hook(); return end
    end
end)
