-- Per-player command budget at the server dispatch (server/MinidoracatTesla/Commands.lua T.CommandRate): past the
-- budget dropped before the handler, counted, one log line a window; players apart; the window recovers, a clock set
-- back starts over; SP and unknown commands are left alone. The real client's busiest minute through it (H.serve) is
-- in test_sound_remote (motor), test_phone_app (the app), test_liftgate (car picture), test_hud (charge card) and
-- test_keys (walk-away lock, key sweep, key card taps, pairing).
local check = H.check
local T = MinidoracatTesla
local CR = T.CommandRate
local cmds = T.ServerCommands

H.section("command budget: server dispatch")
H.side(false, true)
local hits, saved, names = {}, {}, { "rateA", "rateB", "liftgate" }
for _, c in ipairs(names) do -- rateA / rateB: no row (default); liftgate: its own row
    saved[c] = cmds[c]
    cmds[c] = function() hits[c] = (hits[c] or 0) + 1 end
end
local function send(p, c, n)
    hits[c] = 0
    for _ = 1, n or 1 do H.fire("OnClientCommand", T.MODULE, c, p, {}) end
    return hits[c]
end
local function logs()
    local n = 0
    for _, l in ipairs(H.logLines) do if l:find("rate limit:", 1, true) then n = n + 1 end end
    return n
end
local D, G = CR.LIMITS.default, CR.LIMITS.liftgate
check(D.max >= 2 * 20 and G.max < D.max and CR.LIMITS.motor.max == 10 and CR.LIMITS.motor.ms == 5000,
    "budgets: default twice the busiest client (20 a window), liftgate tighter, motor unchanged (10 per 5 s)")
-- every row names a real command (a typo would quietly fall back to `default`): its handler is assigned somewhere
-- (lists the files like smoke_harness.lua does: `ls` in a POSIX shell, else cmd's `dir`, which prints whole paths)
local MEDIA_LUA = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua"
local handlers, scanned, dir = {}, 0, nil
local lister = io.popen('ls -R "' .. MEDIA_LUA .. '" 2>/dev/null || dir /s /b "' .. MEDIA_LUA:gsub("/", "\\") .. '\\*.lua" 2>nul')
for line in lister:lines() do
    line = line:gsub("\r$", "")
    if line:sub(-1) == ":" then dir = line:sub(1, -2)
    elseif line:sub(-4) == ".lua" then
        local f = io.open(line:find("[/\\]") and line or (dir .. "/" .. line), "r")
        if f then
            scanned = scanned + 1
            for name in f:read("*a"):gmatch("ServerCommands%.([%w_]+)%s*=%s*function") do handlers[name] = true end
            f:close()
        end
    end
end
lister:close()
local typos = {}
for name in pairs(CR.LIMITS) do if name ~= "default" and not handlers[name] then typos[#typos + 1] = name end end
check(scanned > 0 and handlers.motor and handlers.liftgate and #typos == 0, "every budget row is a command with a handler "
    .. "in the MOD (" .. scanned .. " files; " .. (#typos == 0 and "all rows" or "missing: " .. table.concat(typos, ", ")) .. ")")

local p1, p2 = H.player({ name = "p1" }), H.player({ name = "p2" })
local d0, l0, s0 = CR.dropped.default or 0, logs(), #H.sent
check(send(p1, "rateA", D.max - 10) == D.max - 10 and send(p1, "rateB", 10) == 10 and (CR.dropped.default or 0) == d0,
    "commands without a row share one budget: " .. D.max .. " in a window all reach their handler")
check(send(p1, "rateB", 25) == 0 and CR.dropped.default == d0 + 25, "past it: dropped before the handler, each counted")
check(logs() == l0 + 1, "one log line for the window, not one per drop")
check(H.logLines[#H.logLines]:find("default", 1, true) and H.logLines[#H.logLines]:find("p1", 1, true),
    "the line names the bucket and the player")
check(#H.sent == s0, "no reply to the client (a reply per drop would grow with the flood)")
check(send(p1, "liftgate", G.max) == G.max and send(p1, "liftgate", 3) == 0 and (CR.dropped.liftgate or 0) == 3,
    "a command with a row has its own budget (" .. G.max .. "), apart from the spent default")
check(send(p2, "rateA", D.max) == D.max, "another player's budget is their own")
-- the online id goes to someone else (a connection slot reused, GameServer.java:2669-2676) while p2's window runs
check(send(p2, "rateA") == 0, "p2 past its budget: cut")
local again = H.player({ name = "p2" }) -- p2 respawned or back on the same slot: a new IsoPlayer, the same account
again.oid = p2.oid
check(send(again, "rateA") == 0, "the same account on a new character (respawn, reconnect) does not start over")
local p3 = H.player({ name = "p3" })
p3.oid = p2.oid
check(send(p3, "rateA", D.max) == D.max, "a new player on a reused online id starts with a fresh budget")
check(send(p3, "rateA") == 0, "and is cut past it like anyone")
local l1 = logs()
H.advanceMs(D.ms - 1)
check(send(p1, "rateA") == 0 and logs() == l1, "1 ms before the window ends: still dropped (logged once already)")
H.advanceMs(1)
check(send(p1, "rateA", D.max) == D.max and logs() == l1, "next window: the full budget again, nothing logged")
H.advanceMs(-60000) -- the server's wall clock jumps back (getTimestampMs is System.currentTimeMillis)
check(send(p1, "rateA", D.max) == D.max, "clock set back a minute: a fresh window, not one stretched by the jump")
H.advanceMs(60000 + D.ms)
local d1 = CR.dropped.default
for _ = 1, 100 do H.fire("OnClientCommand", T.MODULE, "noSuchCommand", p1, {}) end
check(send(p1, "rateA", D.max) == D.max and CR.dropped.default == d1, "unknown commands use no budget (dropped before it)")
H.side(false, false)
check(send(p1, "rateA", 3 * D.max) == 3 * D.max and CR.dropped.default == d1, "SP: no budget (no other client to defend against)")
H.side(false, true)

for _, c in ipairs(names) do cmds[c] = saved[c] end
H.advanceMs(G.ms) -- later tests start with fresh windows
