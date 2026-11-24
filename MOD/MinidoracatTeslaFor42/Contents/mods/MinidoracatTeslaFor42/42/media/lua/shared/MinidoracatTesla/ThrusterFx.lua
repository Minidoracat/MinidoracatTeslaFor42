-- Roadster Rocket thruster effects (references/roadster2.md): the jets of part TeslaThruster (models Lift, Side, Rear),
-- their hiss and the white fog on landing and boost. F.set(vehicle, mode) runs on the server and in SP only (the
-- flight code calls it): it shows the mode's models, which the engine syncs to every client that has the car
-- (BaseVehicle.setModelVisible sets PartModels, BaseVehicle.java:1737-1760; VehiclePartModels.java:23-46), and tells
-- the clients near the car (Liftgate.sendNear; SP: the handler directly) to play the sound and drop the fog: thrustFx
-- { vid, mode, fog = { x, y, z } or nil }. A car without the part does nothing.
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
F.FOG = "media/textures/MinidoracatTesla/JetFog.png"
F.FOG_MS, F.FOG_ALPHA = 3000, 0.9
F.FOG_BEHIND = 3 -- tiles behind the car's centre for the boost's fog: the rear jets end about 2 past its tail
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
    F.stats.sent = F.stats.sent + 1
    if not isServer() then return T.ClientCommands.thrustFx(args) end
    T.Liftgate.sendNear(vehicle, "thrustFx", args)
end

if not isServer() then
    -- Fog: an IsoMarkers stand-up sprite at its own size, its bottom centre on the tile's centre (IsoMarkers.java:299;
    -- IsoSprite.java:1302-1327), faded out over F.FOG_MS by a one-shot OnTick removed when the last one is gone.
    local fogs = {}
    local function fogTick()
        local now = getTimestampMs()
        for i = #fogs, 1, -1 do
            local f = fogs[i]
            local k = (now - f.at) / F.FOG_MS
            if k >= 1 then
                f.m:remove()
                table.remove(fogs, i)
            else
                f.m:setAlpha(F.FOG_ALPHA * (1 - k)) -- linear: a 1.5 power left it near gone by 1.5 s (E2E r2fx-sp-1)
            end
        end
        if #fogs == 0 then Events.OnTick.Remove(fogTick) end
    end
    local function fog(p)
        local sq = type(p) == "table" and tonumber(p.x) and getCell():getGridSquare(math.floor(p.x), math.floor(p.y),
            math.floor(tonumber(p.z) or 0))
        local m = sq and getIsoMarkers():addIsoMarker({ F.FOG }, sq, 1, 1, 1, F.FOG_ALPHA)
        if not m then return end
        if #fogs == 0 then Events.OnTick.Add(fogTick) end
        fogs[#fogs + 1] = { m = m, at = getTimestampMs() }
        F.stats.fog = F.stats.fog + 1
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
        if args.fog then fog(args.fog) end
        sound(args.vid, F.MODELS[args.mode] ~= nil, args.mode == "land")
    end
end
