-- Roadster Rocket thruster effects (shared/MinidoracatTesla/ThrusterFx.lua): which models each mode shows, a car
-- without the part, who gets thrustFx, the hiss's start / stop / tail and the fog's fade. Looks, sound and the second
-- client are E2E (R2Fx, temp/plan-roadster2-1124/build/R2Fx.md).
local check = H.check
local T = MinidoracatTesla
local SRC = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/shared/MinidoracatTesla/ThrusterFx.lua"
local saved = { getOnlinePlayers = getOnlinePlayers, getCell = getCell, getIsoMarkers = getIsoMarkers, Vector3f = Vector3f }

-- engine fakes: squares, markers (IsoMarkers.addIsoMarker(table, sq, r, g, b, a)), a forward vector (physics frame)
local markers = {}
function getCell() return { getGridSquare = function(_, x, y, z) return { x = x, y = y, z = z } end } end
function getIsoMarkers()
    return { addIsoMarker = function(_, tex, sq, r, g, b, a)
        local m = { tex = tex[1], sq = sq, a = a }
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
check(shown(v) == "Lift" and v.played[1] == F.SOUND and #v.played == 1 and minutes() == 1,
    "SP lift: Lift only, the hiss starts with its game-minute check")
F.set(v, "flip")
check(shown(v) == "Lift+Side" and #v.played == 1, "flip: Lift + Side, the same hiss keeps playing")
F.set(v, "boost")
local fog = markers[#markers]
check(shown(v) == "Rear" and #markers == 1 and fog.tex == F.FOG and fog.sq.x == 100 and fog.sq.y == 97
    and ticks() == 1, "boost: Rear only, one fog marker 3 tiles behind the car (facing +y), fade tick on")
F.set(v, "land")
check(shown(v) == "" and #v.stopped == 1 and v.played[2] == F.SOUND_END and #markers == 2
    and markers[2].sq.x == 100 and markers[2].sq.y == 100 and minutes() == 0,
    "land: all hidden, hiss stopped with its tail, fog under the car, minute check off")
F.set(v, nil)
check(shown(v) == "" and #v.played == 2 and #markers == 2, "nil: all hidden, no tail, no fog")
F.set(v, "warp")
check(shown(v) == "" and #v.played == 2, "an unknown mode: all hidden, nothing played")

-- fog fades over F.FOG_MS, then the markers go and the tick removes itself
H.advanceMs(F.FOG_MS / 2)
H.fire("OnTick")
check(markers[1].a < F.FOG_ALPHA and markers[1].a > 0 and not markers[1].removed, "fog: half way, fainter")
H.advanceMs(F.FOG_MS)
H.fire("OnTick")
check(markers[1].removed and markers[2].removed and ticks() == 0, "fog: gone after FOG_MS, tick removed")

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

H.advanceMs(F.FOG_MS + 1)
H.fire("OnTick")
H.side(false, true)
getOnlinePlayers, getCell, getIsoMarkers, Vector3f = saved.getOnlinePlayers, saved.getCell, saved.getIsoMarkers, saved.Vector3f
