-- A hitch a client missed (client/MinidoracatTesla/TowLink.lua, towAsk in server/MinidoracatTesla/TowAuth.lua): each
-- Tesla or trailer the client builds asks the server once what it is hitched to, cars built during the loading screen
-- one a tick from the first; the server answers for a pair with a Tesla in it, asked about either end; the client
-- hooks the two only when it has both and neither end is taken. That the engine then keeps the pair together is E2E
-- join-race-mp (X5, X7).
local check = H.check
local T = MinidoracatTesla
local MEDIA_LUA = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua"
local SEMI, TRAILER = "Base.MinidoracatTesla_Semi", "Base.MinidoracatTesla_SemiTrailer"

H.section("tow link: the server's answer")
H.side(false, true)
H.require("MinidoracatTesla/TowAuth")
local function car(script)
    local v = H.vehicle({ script = script })
    function v:getVehicleTowing() return self.towing end
    return v
end
-- `head` tows `tail` on the server
local function hitch(head, tail, attA, attB)
    head.towing, tail.towedBy = tail, head
    function head:getTowAttachmentSelf() return attA end
    function head:getTowAttachmentOther() return attB end
    return head, tail
end
local asker = H.player({ name = "asker" })
local function answer(vid, a)
    local from = #H.sent
    H.fire("OnClientCommand", T.MODULE, "towAsk", asker, { vid = vid, a = a })
    return #H.sent - from, H.sent[#H.sent]
end

local semi, trailer = hitch(car(SEMI), car(TRAILER), "mtsemi_fifthwheel", "mtsemi_kingpin")
local function isSemiPair(n, m)
    return n == 1 and m.player == asker and m.module == T.MODULE and m.command == "towLink" and m.args.a == semi:getId()
        and m.args.b == trailer:getId() and m.args.attA == "mtsemi_fifthwheel" and m.args.attB == "mtsemi_kingpin"
end
check(isSemiPair(answer(trailer:getId())), "a hitched Semi trailer: its tractor and the hitch's two attachments, to the one who asked")
check(isSemiPair(answer(semi:getId())), "asked about the tractor (it was the late one): the same answer")
local _, cart = hitch(car("Base.MinidoracatTesla_Cybertruck"), car("Base.Trailer"), "trailer", "trailer")
local _, roped = hitch(car("Base.PickUpTruck"), car("Base.MinidoracatTesla_ModelY"), "trailer", "trailerfront")
check(answer(cart:getId()) == 1 and answer(roped:getId()) == 1, "a vanilla trailer behind a Tesla, a Tesla behind a vanilla truck: answered")
local pickup, vanilla = hitch(car("Base.PickUpTruck"), car("Base.Trailer"), "trailer", "trailer")
check(answer(vanilla:getId()) == 0 and answer(pickup:getId()) == 0, "a pair with no Tesla in it, either end: no answer, left to vanilla")
check(answer(car(SEMI):getId()) == 0 and answer(car(TRAILER):getId()) == 0, "a tractor or a trailer on its own: no answer")
local logs = #H.logLines
check(answer(987654) == 0 and answer("7") == 0 and answer(nil) == 0 and answer(trailer:getId() + 0.5) == 0
    and #H.logLines == logs, "an id no car has, a string, none at all, a fraction: no answer, no error")
-- the check a client sends after hooking on an answer: told only when that answer has gone stale
local loose = car(TRAILER)
local n, m = answer(loose:getId(), semi:getId())
check(answer(trailer:getId(), semi:getId()) == 0 and answer(987654, semi:getId()) == 0,
    "a check on a pair still hitched, or on a car that is gone: no word")
check(n == 1 and m.player == asker and m.command == "towLink" and m.args.apart == true and m.args.a == semi:getId()
    and m.args.b == loose:getId(), "a check on a trailer that is loose now: told they are apart")
n, m = answer(trailer:getId(), pickup:getId())
check(n == 1 and m.args.apart == true, "a check naming another tractor than the one towing it: apart")

H.section("tow link: the client asking")
local savedPlayer = getSpecificPlayer
local me = H.player({ name = "me" })
local alive = true
getSpecificPlayer = function(i) return i == 0 and alive and me or nil end
local function asks(from)
    local ids = {}
    for i = from + 1, #H.clientSent do
        local c = H.clientSent[i]
        if c.module == T.MODULE and c.command == "towAsk" and c.player == me then ids[#ids + 1] = c.args.vid end
    end
    return ids
end

-- OnGameStart and OnTick are caught here, and the spawn handler is called by name: other modules hook those events too
local hook, realEvents = {}, {}
for _, name in ipairs({ "OnGameStart", "OnTick" }) do
    realEvents[name] = rawget(Events, name)
    rawset(Events, name, { Add = function(fn) hook[name] = fn end, Remove = function(fn) if hook[name] == fn then hook[name] = nil end end })
end
local spawnHooks = H.count("OnSpawnVehicleEnd")
H.side(false, false)
dofile(MEDIA_LUA .. "/client/MinidoracatTesla/TowLink.lua")
H.side(false, true)
dofile(MEDIA_LUA .. "/client/MinidoracatTesla/TowLink.lua")
check(H.count("OnSpawnVehicleEnd") == spawnHooks and not T.TowLink and not hook.OnGameStart,
    "single player and the server: nothing hooked")
H.side(true, false)
H.require("MinidoracatTesla/TowLink")
local built = T.TowLink.onSpawn
check(H.count("OnSpawnVehicleEnd") == spawnHooks + 1 and hook.OnGameStart ~= nil, "MP client: one hook on cars being built, one on login")

local from = #H.clientSent
local early1, early2 = car(TRAILER), car("Base.MinidoracatTesla_ModelY")
built(early1)
built(early2)
built(car("Base.CarNormal"))
check(#asks(from) == 0, "cars built during the loading screen: nothing sent yet (it would not reach the server)")
hook.OnGameStart()
check(#asks(from) == 0 and hook.OnTick ~= nil, "login: still nothing, waiting for the first tick")
hook.OnTick(0)
check(#asks(from) == 1 and hook.OnTick ~= nil, "the first tick after login: one question, the rest wait their tick")
hook.OnTick(0)
local got = asks(from)
table.sort(got)
check(#got == 2 and got[1] == math.min(early1:getId(), early2:getId()) and got[2] == math.max(early1:getId(), early2:getId()),
    "a tick each: one question for each Tesla or trailer built by then, none for a vanilla car")
hook.OnTick(0)
check(#asks(from) == 2 and hook.OnTick == nil, "all asked: the tick hook took itself off")

from = #H.clientSent
local late = car("Base.Trailer")
built(late)
built(car("Base.PickUpTruck"))
got = asks(from)
check(#got == 1 and got[1] == late:getId(), "after that: a trailer asks as it is built, a vanilla car never")
alive = false
built(car(SEMI))
check(#asks(from) == 1, "no local player (dead): not sent")
alive = true

-- a busy moment after login: 40 Teslas and trailers built in one go, each asked as it is built; a pair hooked on an
-- answer checks once more, so at most half as many again
from = #H.clientSent
for _ = 1, 40 do built(car(TRAILER)) end
local served = H.serve(from)
local row = T.CommandRate.LIMITS.towAsk
check(served.towAsk == 40 and row.max >= 1.5 * 60, "40 cars built at once all reach the server's handler; the budget ("
    .. row.max .. ") is at least 1.5 times those and their 20 checks")

H.section("tow link: the client hooking up")
local function linkable(script)
    local v = car(script)
    function v:addPointConstraint(p, other, attA, attB)
        self.hooks = (self.hooks or 0) + 1
        self.hook = { p = p, other = other, attA = attA, attB = attB }
        if not other.unbuilt then self.towing, other.towedBy = other, self end
    end
    function v:breakConstraint(forget, remote)
        self.breaks = { forget = forget, remote = remote }
        self.towing.towedBy, self.towing = nil, nil
    end
    return v
end
local link = T.ClientCommands.towLink
-- the towAsk commands this client sent since `from`
local function sentAsks(from)
    local list = {}
    for i = from + 1, #H.clientSent do
        if H.clientSent[i].command == "towAsk" then list[#list + 1] = H.clientSent[i].args end
    end
    return list
end
local a, b = linkable(SEMI), linkable(TRAILER)
logs = #H.logLines
from = #H.clientSent
link({ a = a:getId(), b = b:getId(), attA = "mtsemi_fifthwheel", attB = "mtsemi_kingpin" })
check(a.hooks == 1 and a.hook.p == nil and a.hook.other == b and a.hook.attA == "mtsemi_fifthwheel"
    and a.hook.attB == "mtsemi_kingpin" and not b.hooks, "both built, neither hooked: the tractor hooks the trailer, as the packet would")
check(#H.logLines == logs + 1 and H.logLines[#H.logLines]:find("towlink:", 1, true) ~= nil, "one log line for the catch-up")
local sent = sentAsks(from)
check(#sent == 1 and sent[1].vid == b:getId() and sent[1].a == a:getId(), "and one check back to the server: this trailer behind this tractor")
link({ a = a:getId(), b = b:getId(), attA = "mtsemi_fifthwheel", attB = "mtsemi_kingpin" })
check(a.hooks == 1 and #H.logLines == logs + 1 and #sentAsks(from) == 1,
    "already hooked (the packet or the engine's retry got there): left alone, no check")
-- the answer had crossed an unhitch: the server says apart
link({ a = a:getId(), b = b:getId(), apart = true })
sent = sentAsks(from)
check(a.breaks and a.breaks.forget == true and a.breaks.remote == true and not a.towing and not b.towedBy,
    "apart: this client lets go, as the unhitch packet does")
check(#H.logLines == logs + 2 and #sent == 2 and sent[2].vid == b:getId() and sent[2].a == nil,
    "one log line, and the trailer asks afresh (that word may have been the late one)")
a.breaks = nil
link({ a = a:getId(), b = b:getId(), apart = true })
check(not a.breaks and #sentAsks(from) == 2 and #H.logLines == logs + 2, "apart for a pair not hooked here: nothing to do")
local c, d, e = linkable(SEMI), linkable(TRAILER), linkable(TRAILER)
c.towing, e.towedBy = e, c
link({ a = c:getId(), b = d:getId(), attA = "x", attB = "y" })
check(not c.hooks, "the tractor tows another car here: left alone")
local f, g = linkable(SEMI), linkable(TRAILER)
g.towedBy = c
link({ a = f:getId(), b = g:getId(), attA = "x", attB = "y" })
check(not f.hooks, "the trailer is behind another car here: left alone")
local gone = linkable(TRAILER)
H.removeVehicle(gone)
link({ a = f:getId(), b = gone:getId(), attA = "x", attB = "y" })
link({ a = gone:getId(), b = d:getId(), attA = "x", attB = "y" })
link({ a = f:getId(), b = f:getId(), attA = "x", attB = "y" })
check(not f.hooks and not gone.hooks, "either one not built here, or one car named twice: nothing hooked")
-- a car known by id whose chunk is not loaded: the engine's hook does nothing (no script yet)
local known = linkable(TRAILER)
known.unbuilt = true
logs = #H.logLines
link({ a = f:getId(), b = known:getId(), attA = "x", attB = "y" })
check(f.hooks == 1 and not f.towing and #H.logLines == logs, "the engine did not hook them (one is not built yet): no catch-up logged")

Events.OnSpawnVehicleEnd.Remove(T.TowLink.onSpawn)
for name, real in pairs(realEvents) do rawset(Events, name, real) end
for _, name in ipairs({ "OnGameStart", "OnTick" }) do if not realEvents[name] then rawset(Events, name, nil) end end
getSpecificPlayer = savedPlayer
H.side(false, true)
