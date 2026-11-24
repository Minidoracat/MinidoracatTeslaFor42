-- Roadster Rocket thruster effects (shared/MinidoracatTesla/ThrusterFx.lua): which models each mode shows, a car
-- without the part, who gets thrustFx, the hiss's start / stop / tail and the fog's fade. Looks, sound and the second
-- client are E2E (R2Fx, temp/plan-roadster2-1124/build/R2Fx.md).
local check = H.check
local T = MinidoracatTesla
local SRC = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/shared/MinidoracatTesla/ThrusterFx.lua"
local saved = { getOnlinePlayers = getOnlinePlayers, getCell = getCell, getIsoMarkers = getIsoMarkers, Vector3f = Vector3f }

-- engine fakes: squares (light 0.1: night), markers (IsoMarkers.addIsoMarker(table, sq, r, g, b, a)), a forward vector
local markers = {}
function getCell()
    return { getGridSquare = function(_, x, y, z) return { x = x, y = y, z = z, getLightLevel = function() return 0.1 end } end }
end
function getIsoMarkers()
    return { addIsoMarker = function(_, tex, sq, r, g, b, a)
        local m = { tex = tex[1], sq = sq, r = r, a = a }
        function m:setAlpha(x) self.a = x end
        function m:remove() self.removed = true end
        markers[#markers + 1] = m
        return m
    end }
end
Vector3f = { new = function() return {} end }
local online = {}
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end

local function car(withPart)
    local v = H.vehicle({ script = "Base.MinidoracatTesla_Roadster2" })
    v.shown, v.played, v.stopped = {}, {}, {}
    if withPart then
        v.parts.TeslaThruster = { setModelVisible = function(_, id, on) v.shown[id] = on end }
    end
    local ids = 0
    v.emitter = { playSoundLoopedImpl = function(_, name) ids = ids + 1; v.played[#v.played + 1] = name; return ids end,
        stopSound = function(_, id) v.stopped[#v.stopped + 1] = id end }
    function v:getEmitter() return self.emitter end
    function v:getForwardVector(out) out.x, out.z = function() return 0 end, function() return 1 end return out end -- +y
    return v
end
local function shown(v)
    local t = {}
    for _, id in ipairs({ "Lift", "Side", "Rear" }) do if v.shown[id] then t[#t + 1] = id end end
    return table.concat(t, "+")
end

-- SP: set() shows the models and calls the client handler straight away
H.side(false, false)
dofile(SRC)
local F = T.ThrusterFx
local minute0, tick0 = H.count("EveryOneMinute"), H.count("OnTick") -- other modules' handlers
local function minutes() return H.count("EveryOneMinute") - minute0 end
local function ticks() return H.count("OnTick") - tick0 end
local v = car(true)
F.set(v, "lift")
check(shown(v) == "Lift" and v.played[1] == F.SOUND and #v.played == 1 and minutes() == 1 and #markers == 1
    and markers[1].tex == F.GLOW and markers[1].sq.x == 100 + F.GLOW_AT and markers[1].sq.y == 100 + F.GLOW_AT
    and markers[1].r == 1 and ticks() == 1,
    "SP lift from rest: Lift only, the hiss starts with its game-minute check, the take-off glow in front of the car")
F.set(v, "flip")
check(shown(v) == "Lift+Side" and #v.played == 1 and #markers == 1, "flip: Lift + Side, the same hiss, no glow")
F.set(v, "lift")
check(#markers == 1, "lift again in the air: no glow")
F.set(v, "boost")
local nb, fog = #F.PUFFS.boost, markers[2]
check(shown(v) == "Rear" and #markers == 1 + nb and fog.tex == F.FOG[F.PUFFS.boost[1][3]]
    and fog.sq.x == 100 + F.PUFFS.boost[1][1] and fog.sq.y == 100 - F.FOG_BEHIND + F.PUFFS.boost[1][2] and fog.a == 0
    and fog.r == F.FOG_MIN_LIGHT and ticks() == 1,
    "boost: Rear only, its puffs right behind the tail (facing +y), shaded by a dark square, fading in")
F.set(v, "land")
local nl = #F.PUFFS.land
check(shown(v) == "" and #v.stopped == 1 and v.played[2] == F.SOUND_END and #markers == 1 + nb + nl
    and markers[2 + nb].sq.x == 100 + F.PUFFS.land[1][1] and markers[2 + nb].sq.y == 100 + F.PUFFS.land[1][2]
    and markers[#markers].tex ~= F.GLOW and minutes() == 0 and F.stats.fog == 2,
    "land: all hidden, hiss stopped with its tail, puffs around the car, no glow, minute check off")
F.set(v, nil)
check(shown(v) == "" and #v.played == 2 and #markers == 1 + nb + nl, "nil: all hidden, no tail, no fog")
F.set(v, "warp")
check(shown(v) == "" and #v.played == 2, "an unknown mode: all hidden, nothing played")

-- each marker fades in, then out over its own life; gone at the end, and the tick removes itself
local p1, pl, ql = markers[2 + nb], markers[#markers], F.PUFFS.land[nl]
H.advanceMs(ql[6] / 2)
H.fire("OnTick")
check(ql[6] > 0 and pl.a == 0, "fog: an outer-ring puff still hidden before its delay")
H.advanceMs(1000 - ql[6] / 2)
H.fire("OnTick")
check(markers[1].removed and math.abs(p1.a - F.PUFFS.land[1][4] * (1 - 1000 / F.PUFFS.land[1][5])) < 1e-6
    and math.abs(pl.a - ql[4] * (1 - (1000 - ql[6]) / ql[5])) < 1e-6 and not p1.removed,
    "fog: the glow gone after F.GLOW_MS, an inner puff part way out, the outer one counting from its delay")
H.advanceMs(4000)
H.fire("OnTick")
local all = true
for _, m in ipairs(markers) do all = all and m.removed end
check(all and ticks() == 0, "fog: every puff gone after its life, tick removed")

-- a car without the part: nothing at all
local plain = car(false)
local sent = F.stats.sent
F.set(plain, "lift")
check(next(plain.shown) == nil and #plain.played == 0 and F.stats.sent == sent, "no TeslaThruster: quietly nothing")

-- the hiss stops when the car is gone from this client (game-minute check), or after SOUND_MAX_MS without a command
F.set(v, "lift")
H.removeVehicle(v)
H.fire("EveryOneMinute")
check(#v.stopped == 2 and minutes() == 0, "unloaded car: hiss stopped, minute check off")
H.addVehicle(v)
F.set(v, "lift")
H.advanceMs(F.SOUND_MAX_MS - 1)
H.fire("EveryOneMinute")
check(#v.stopped == 2, "a long hover inside the backstop keeps its hiss")
F.set(v, "lift") -- renewed
H.advanceMs(F.SOUND_MAX_MS - 1)
H.fire("EveryOneMinute")
check(#v.stopped == 2, "a command renews the backstop")
H.advanceMs(2)
H.fire("EveryOneMinute")
check(#v.stopped == 3 and minutes() == 0, "no command for SOUND_MAX_MS: hiss stopped")

-- MP server: models switched there, thrustFx to every client within NEAR_TILES once, nothing played on the server
H.side(false, true)
local near = H.player({ name = "near", x = v.x + 10, y = v.y })
local far = H.player({ name = "far", x = v.x + T.Liftgate.NEAR_TILES + 1, y = v.y })
online = { near, far }
local n, played = #H.sent, #v.played
F.set(v, "flip")
local s = H.sent[n + 1]
check(shown(v) == "Lift+Side" and #H.sent == n + 1 and s.player == near and s.command == "thrustFx"
    and s.args.vid == v.id and s.args.mode == "flip" and s.args.fog == nil and #v.played == played,
    "MP server flip: models on, thrustFx only to the near client, no fog, no sound on the server")
F.set(v, "land")
s = H.sent[#H.sent]
check(shown(v) == "" and s.args.mode == "land" and s.args.fog and s.args.fog.x == v.x and s.args.fog.y == v.y,
    "MP server land: models off, the fog's place goes along")

-- MP client: set() does nothing (the server owns the models); the handler plays and stops the hiss
H.side(true, false)
local shownBefore = shown(v)
F.set(v, "lift")
check(shown(v) == shownBefore and #H.sent == n + 2, "MP client: set() is a no-op")
T.ClientCommands.thrustFx({ vid = v.id, mode = "lift" })
T.ClientCommands.thrustFx({ vid = v.id, mode = "land", fog = { x = v.x, y = v.y, z = 0 } })
check(v.played[#v.played] == F.SOUND_END and #v.stopped == 4, "MP client: lift then land plays, stops, tails")
T.ClientCommands.thrustFx({ vid = 9999, mode = "lift" })
T.ClientCommands.thrustFx("junk")
check(minutes() == 0, "unknown car or junk args: nothing starts")

-- E3: in flight the server sends lift again each game minute (server Thruster.lua H.onUpdate): no glow, no fog; a
-- client that came near since starts its hiss from it, the others' only renewed
H.side(false, true)
F.set(v, "lift")
F.set(v, "lift")
s = H.sent[#H.sent]
check(s.args.mode == "lift" and s.args.glow == nil and s.args.fog == nil, "E3: lift renewed in flight: no glow, no fog")
H.side(true, false)
local p0, m0 = #v.played, #markers
T.ClientCommands.thrustFx(s.args)
check(#v.played == p0 + 1 and v.played[#v.played] == F.SOUND and #markers == m0 and minutes() == 1,
    "E3: a client's first thrustFx mid-flight: its hiss starts, nothing else")
T.ClientCommands.thrustFx(s.args)
check(#v.played == p0 + 1 and #markers == m0, "E3: the next one: the hiss renewed only")
T.ClientCommands.thrustFx({ vid = v.id, mode = "land" })

H.advanceMs(4000)
H.fire("OnTick")
H.side(false, true)
getOnlinePlayers, getCell, getIsoMarkers, Vector3f = saved.getOnlinePlayers, saved.getCell, saved.getIsoMarkers, saved.Vector3f
