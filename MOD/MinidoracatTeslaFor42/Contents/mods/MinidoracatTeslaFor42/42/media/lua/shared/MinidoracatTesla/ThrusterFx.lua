-- Roadster Rocket thruster effects (references/roadster2.md): the jets of part TeslaThruster (models Lift, Side, Rear),
-- their hiss and the white fog on landing and boost. F.set(vehicle, mode) runs on the server and in SP only (the
-- flight code calls it): it shows the mode's models, which the engine syncs to every client that has the car
-- (BaseVehicle.setModelVisible sets PartModels, BaseVehicle.java:1737-1760; VehiclePartModels.java:23-46), and tells
-- the clients near the car (Liftgate.sendNear; SP: the handler directly) to play the sound, drop the fog and flash
-- the take-off glow: thrustFx { vid, mode, fog = { x, y, z } or nil, glow = { x, y, z } or nil }. A car without the
-- part does nothing.
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Liftgate"

local T = MinidoracatTesla
local F = {}
T.ThrusterFx = F
F.PART = "TeslaThruster"
F.IDS = { "Lift", "Side", "Rear" }
-- the models each mode shows; "land", nil and anything else: none
F.MODELS = { lift = { Lift = true }, flip = { Lift = true, Side = true }, boost = { Rear = true } }
F.SOUND, F.SOUND_END = "MinidoracatTesla_RoadsterJet", "MinidoracatTesla_RoadsterJetEnd"
-- Fog: a low ground layer spreading out, as the official landing (f2-kickflip 11m15): banks around the spot,
-- { dx, dy, texture (1 wide, 2 mid, 3 low), peak alpha, life ms, delay ms }. +x +y is toward the camera. The inner ring
-- comes first and goes first, the outer ring 200-300 ms later and lasts longer, so the layer seems to roll outward
-- (a marker cannot grow, IsoMarkers.java:142). Banks behind the car are the low ones: one stands higher on screen
-- the further back it is, and must not tower over the roof.
F.FOG = { "media/textures/MinidoracatTesla/JetFog1.png", "media/textures/MinidoracatTesla/JetFog2.png",
    "media/textures/MinidoracatTesla/JetFog3.png" }
F.PUFFS = {
    land = { { -1, -1, 3, 0.8, 1900, 0 }, { 1, 1, 3, 0.7, 1700, 0 }, { -1, 1, 2, 0.75, 1800, 0 },
        { 1, -1, 2, 0.75, 1800, 0 }, { -2, 2, 1, 0.7, 2700, 200 }, { 2, -2, 1, 0.7, 2600, 250 },
        { 2, 2, 2, 0.6, 2400, 200 }, { -2, -2, 3, 0.4, 2600, 300 }, { -3, -1, 3, 0.4, 2500, 300 },
        { -1, -3, 3, 0.4, 2500, 300 } },
    -- right behind the tail (F.FOG_BEHIND), then spreading
    boost = { { 0, 0, 2, 0.75, 1800, 0 }, { -1, -1, 3, 0.55, 2200, 200 }, { 1, 1, 3, 0.55, 2200, 200 } },
}
F.FOG_IN_MS = 150
F.FOG_MIN_LIGHT = 0.3 -- puffs take their square's light once: a night fog must not shine like a lamp
F.FOG_BEHIND = 2 -- tiles behind the car's centre for the boost's fog: its tail and rear nozzles
-- Ground glow at take-off (lift from no jets): one flat ellipse standing 2 tiles toward the camera so its middle lands
-- under the car; the jets' light, so not shaded. Not on landing: there it tinted the fog's front bank blue (r2fx-sp-6b).
F.GLOW, F.GLOW_AT, F.GLOW_ALPHA, F.GLOW_MS = "media/textures/MinidoracatTesla/JetGlow.png", 2, 0.7, 800
F.last = {} -- server: each car's current jet mode, for the take-off glow
F.SOUND_MAX_MS = 20 * 60000 -- backstop: a hiss no command renewed for this long stops (the car is checked anyway)
F.stats = { set = 0, sent = 0, fog = 0, loops = 0, stops = 0 }

function F.set(vehicle, mode)
    if isClient() or not vehicle then return end
    local part = vehicle:getPartById(F.PART)
    if not part then return end
    F.stats.set = F.stats.set + 1
    local on = F.MODELS[mode] or {}
    for _, id in ipairs(F.IDS) do part:setModelVisible(id, on[id] == true) end
    local args = { vid = vehicle:getId(), mode = mode }
    local x, y = vehicle:getX(), vehicle:getY()
    if mode == "boost" then
        local f = vehicle:getForwardVector(Vector3f.new()) -- physics frame: world y is its z
        x, y = x - f:x() * F.FOG_BEHIND, y - f:z() * F.FOG_BEHIND
    end
    if mode == "land" or mode == "boost" then args.fog = { x = x, y = y, z = vehicle:getZ() } end
    if mode == "lift" and not F.last[args.vid] then
        args.glow = { x = vehicle:getX(), y = vehicle:getY(), z = vehicle:getZ() }
    end
    F.last[args.vid] = F.MODELS[mode] and mode or nil
    F.stats.sent = F.stats.sent + 1
    if not isServer() then return T.ClientCommands.thrustFx(args) end
    T.Liftgate.sendNear(vehicle, "thrustFx", args)
end

if not isServer() then
    -- Fog and glow: IsoMarkers stand-up sprites, each drawn at its texture's own size, bottom centre on its tile's
    -- centre, with that tile's depth (IsoMarkers.java:116-150; IsoSprite.java:1302-1327). A marker has no scale or
    -- sub-tile position setter (setPos takes whole tiles, IsoMarkers.java:299-304; the size is the texture's, :142),
    -- so the cloud is several banks on different tiles, each on its own clock: hidden until its delay, in over
    -- F.FOG_IN_MS, then out linearly. One OnTick, removed when the last one is gone.
    local fogs = {}
    local function fogTick()
        local now = getTimestampMs()
        for i = #fogs, 1, -1 do
            local f = fogs[i]
            local t = now - f.at
            if t >= f.life then
                f.m:remove()
                table.remove(fogs, i)
            else
                f.m:setAlpha(f.peak * math.max(0, math.min(1, t / F.FOG_IN_MS)) * (1 - t / f.life))
            end
        end
        if #fogs == 0 then Events.OnTick.Remove(fogTick) end
    end
    local function add(tex, sq, c, peak, life, delay)
        local m = sq and getIsoMarkers():addIsoMarker({ tex }, sq, c, c, c, 0)
        if not m then return end
        if #fogs == 0 then Events.OnTick.Add(fogTick) end
        fogs[#fogs + 1] = { m = m, at = getTimestampMs() + (delay or 0), peak = peak, life = life }
    end
    local function tile(p)
        if type(p) ~= "table" or not tonumber(p.x) or not tonumber(p.y) then return end
        return math.floor(p.x), math.floor(p.y), math.floor(tonumber(p.z) or 0)
    end
    local function fog(p, mode)
        local x, y, z = tile(p)
        local sq = x and getCell():getGridSquare(x, y, z)
        if not sq then return end
        local c = math.max(F.FOG_MIN_LIGHT, math.min(1, sq:getLightLevel(0)))
        for _, q in ipairs(F.PUFFS[mode] or F.PUFFS.land) do
            add(F.FOG[q[3]], getCell():getGridSquare(x + q[1], y + q[2], z), c, q[4], q[5], q[6])
        end
        F.stats.fog = F.stats.fog + 1
    end
    local function glow(p)
        local x, y, z = tile(p)
        if x then add(F.GLOW, getCell():getGridSquare(x + F.GLOW_AT, y + F.GLOW_AT, z), 1, F.GLOW_ALPHA, F.GLOW_MS) end
    end

    -- Hiss: one looping sound per car on its emitter, played on this client only (playSoundLoopedImpl; playSound on
    -- an MP client also asks the server to relay it and no stop follows, references/api-sources.md). It stops on
    -- "land" (with the tail), on nil, and by the game-minute check when the car is gone from this client (unloaded,
    -- or loaded again as a new object) or no command came for F.SOUND_MAX_MS.
    local loops, n = {}, 0
    local check
    local function stop(vid, tail)
        local s = loops[vid]
        loops[vid] = nil
        n = n - 1
        s.emitter:stopSound(s.id)
        if tail then s.emitter:playSoundLoopedImpl(F.SOUND_END) end
        F.stats.stops = F.stats.stops + 1
        if n == 0 then Events.EveryOneMinute.Remove(check) end
    end
    check = function()
        local now = getTimestampMs()
        for vid, s in pairs(loops) do
            local v = getVehicleById(vid)
            if not v or v:getEmitter() ~= s.emitter or now - s.at > F.SOUND_MAX_MS then stop(vid, false) end
        end
    end
    local function sound(vid, on, tail)
        local s = loops[vid]
        if s and on then s.at = getTimestampMs() return end
        if s then return stop(vid, tail) end
        local v = on and getVehicleById(vid)
        local emitter = v and v:getEmitter()
        local id = emitter and emitter:playSoundLoopedImpl(F.SOUND)
        if not id or id == 0 then return end
        if n == 0 then Events.EveryOneMinute.Add(check) end
        loops[vid], n = { emitter = emitter, id = id, at = getTimestampMs() }, n + 1
        F.stats.loops = F.stats.loops + 1
    end

    T.ClientCommands = T.ClientCommands or {}
    T.ClientCommands.thrustFx = function(args)
        if type(args) ~= "table" or not args.vid then return end
        if args.fog then fog(args.fog, args.mode) end
        if args.glow then glow(args.glow) end
        sound(args.vid, F.MODELS[args.mode] ~= nil, args.mode == "land")
    end
end
