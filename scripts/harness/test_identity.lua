-- Account identity (Core.lua T.account; Store.lua St.onNewGame / St.seat / St.verify / St.scan; family conventions.md,
-- player identity): a slot-0 player renamed on respawn to an offline owner (ConnectCoopPacket.java:65-109,
-- GameServer.java:2848) must not speak for that owner on a Steam server. The engine fact (the server really shows
-- slot 0 under the new name) and the real login flow are E2E identity-mp.
local check = H.check
local T = MinidoracatTesla
H.require("MinidoracatTesla/Store")
H.require("MinidoracatTesla/Inbox")
H.side(false, true)
local St = T.Store
local ids, inbox = St.get("ids"), St.get("inbox")
local SID_OWNER, SID_THIEF, SID_OLD, SID_NEW = 76561198000000016, 76561198012345680, 76561198000000032, 76561198000000048
local savedOnline = getOnlinePlayers
local online = {}
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
local function sentSince(n, cmd)
    for i = n + 1, #H.sent do if H.sent[i].command == cmd then return H.sent[i] end end
end
-- the engine's respawn: ConnectCoop replaces the dead slot-0 player, the newcomer keeps its onlineID
-- (ConnectCoopPacket.java:69,93,100) and names itself
local function respawn(dead, name)
    dead.dead = true
    local p = H.player({ name = name, sid = dead.sid })
    p.oid = dead.oid
    return p
end
local function logged(from, text)
    local n = 0
    for i = from + 1, #H.logLines do if H.logLines[i]:find(text, 1, true) then n = n + 1 end end
    return n
end
-- a car for Inbox.entry: the intruder an alert names (`by`) is its account, false when it has none, never the name
-- its client sent
local scene = { getScript = function() return nil end, getX = function() return 1 end, getY = function() return 2 end,
    getKeyId = function() return 7 end }

H.section("identity: no-steam server, split-screen guests")
H.steam = false
local owner = H.player({ name = "owner" })
check(T.account(owner) == "owner" and next(ids) == nil, "no-steam: the name; nothing bound (no SteamID to check it against)")
local guest = H.player({ name = "owner", num = 1 })
check(T.account(guest) == nil, "split-screen guest (slot 1): no account")
check(T.Inbox.entry(scene, "touch", "door", owner).by == "owner" and T.Inbox.entry(scene, "touch", "door", guest).by == false,
    "no-steam: an alert names the intruder's name; a guest named like the owner: unverified")
H.side(false, false)
check(T.account(H.player({ name = "Bob Smith", num = 1 })) == "Bob Smith", "SP: the username")
H.side(true, false)
check(T.account(H.player({ name = "owner" })) == "owner" and T.account(H.player({ name = "owner", num = 1 })) == nil,
    "MP client: slot 0 its username, a split-screen guest none (as the server answers; UI hints only)")
H.side(false, true)

H.section("identity: Steam server")
H.steam = true
-- the owner's character is made on this server: OnNewGame from CreatePlayerPacket carries the login name and the
-- connection's SteamID (CreatePlayerPacket.java:296-301)
H.fire("OnNewGame", H.player({ name = "owner", sid = SID_OWNER }), nil)
check(ids.owner and ids.owner.sid == SID_OWNER and ids.owner.src == "NEWGAME", "new character: the name is bound to its SteamID")
owner.sid = SID_OWNER
check(T.account(owner) == "owner", "the owner with its SteamID: its account")
inbox.owner = { { kind = "touch", what = "door" }, { kind = "break", what = "window" } }
-- the thief plays under its own name (the server's scan sees its slot), dies and respawns: CreatePlayer with its own
-- login name, then ConnectCoop names slot 0 "owner"
local thief = H.player({ name = "thief", sid = SID_THIEF })
online = { thief }
St.scan()
check(ids.thief and ids.thief.src == "LOGIN", "the scan binds a player at login without any command from it")
H.advanceMs(10 * 60000)
H.fire("OnNewGame", H.player({ name = "thief", sid = SID_THIEF }), nil)
local renamed = respawn(thief, "owner")
check(T.account(renamed) == nil, "respawn renamed to the offline owner (the thief's SteamID): no account")
local n = #H.sent
T.ServerCommands.inboxPull(renamed, {})
local deny = sentSince(n, "deny")
check(#inbox.owner == 2 and sentSince(n, "inbox") == nil, "...inboxPull: the owner's inbox is neither sent nor cleared")
check(deny and deny.player == renamed and deny.args.reason == "IDENTITY_UNVERIFIED", "...and it is told IDENTITY_UNVERIFIED")
local logs = #H.logLines
for _ = 1, 5 do T.ServerCommands.inboxPull(renamed, {}) end
check(logged(logs, "not verified") == 0, "...more pulls within the hour: denied, not logged again (aggregated)")
H.advanceMs(3600000)
T.ServerCommands.inboxPull(renamed, {})
check(logged(logs, "IDENTITY_UNVERIFIED x6") == 1, "...an hour later one line with the count")
local other = H.player({ name = "someone", sid = SID_THIEF })
other.oid, ids.someone = renamed.oid, { sid = SID_OWNER, src = "E2E", at = 0 } -- bound to another Steam account
T.ServerCommands.inboxPull(other, {})
check(logged(logs, "account someone not verified") == 1, "...another name on that slot within the hour: its own line")
online = { renamed }
n = #H.sent
T.Inbox.notify("owner", { kind = "touch", what = "door" })
check(sentSince(n, "alert") == nil and #inbox.owner == 3, "...a live alert for the owner goes to the inbox, not to it")
check(T.legit(renamed, H.vehicle({}), "owner") == false, "...the sentry owner's name does not make it legit")
check(T.Inbox.entry(scene, "touch", "door", renamed).by == false,
    "...an alert it sets off names it unverified, not the owner it calls itself")
check(T.Inbox.entry(scene, "lowBattery", "sentry").by == nil, "an alert with no intruder names nobody")
local back = respawn(renamed, "thief")
n = #H.sent
T.ServerCommands.inboxPull(back, {})
check(T.account(back) == "thief" and sentSince(n, "deny") == nil, "respawned under its own login name again: its account")
check(T.Inbox.entry(scene, "touch", "door", back).by == "thief", "...and an alert it sets off names it")

H.section("identity: first seen (a name never bound)")
-- OnNewGame alone: a new connection (no slot on record) whose SteamID just made another character name
H.fire("OnNewGame", H.player({ name = "erin", sid = SID_NEW }), nil)
local dave = H.player({ name = "dave", sid = SID_NEW })
check(T.account(dave) == nil and ids.dave == nil,
    "OnNewGame made erin for this SteamID within 2 minutes, slot 0 calls itself dave: not bound")
-- the slot alone: the thief's slot logged in as thief; its respawns keep that login however long they wait
local carol = respawn(back, "carol")
H.advanceMs(St.RENAME_MS + 1)
check(T.account(carol) == nil and ids.carol == nil,
    "renamed respawn to a name never bound, past the 2-minute window: not bound (the slot logged in as thief)")
local carol2 = respawn(carol, "carol")
check(T.account(carol2) == nil and ids.carol == nil, "...nor after dying and respawning as carol again (login carried)")
check(T.account(dave) == "dave" and ids.dave.src == "LOGIN", "dave after the window, on its own connection: bound")
local vet = H.player({ name = "veteran", sid = SID_OLD })
check(T.account(vet) == "veteran" and ids.veteran.sid == SID_OLD and ids.veteran.src == "LOGIN",
    "a character from before the MOD (no OnNewGame), new connection, alive: bound on first sight")
check(T.account(H.player({ name = "veteran", sid = SID_THIEF })) == nil, "then the name is that SteamID's only")
local ghost = H.player({ name = "ghost", sid = SID_OLD })
ghost.dead = true
check(T.account(ghost) == nil and ids.ghost == nil, "dead: not bound")
check(T.account(H.player({ name = "nosid", sid = 0 })) == nil and ids.nosid == nil, "no SteamID: not bound")
check(T.account(H.player({ name = "", sid = SID_OLD })) == nil and ids[""] == nil, "empty name: none")
local long = string.rep("x", 33)
check(T.account(H.player({ name = long, sid = SID_NEW })) == nil and ids[long] == nil,
    "a name longer than any account name (getMaxUsernameLength 32): not bound")
-- alerts kept under a name before any binding (an older world): only a new character (OnNewGame) may claim them
inbox.legacy = { { kind = "touch", what = "door" } }
local legacy = H.player({ name = "legacy", sid = SID_NEW })
check(T.account(legacy) == nil and ids.legacy == nil and #inbox.legacy == 1, "a name with an older inbox: not bound on first sight")
H.fire("OnNewGame", H.player({ name = "legacy", sid = SID_NEW }), nil)
n = #H.sent
T.ServerCommands.inboxPull(legacy, {})
check(ids.legacy and ids.legacy.src == "NEWGAME" and sentSince(n, "inbox") and inbox.legacy == nil,
    "...its new character binds it (OnNewGame) and the inbox is delivered")
inbox.emptied = {}
check(T.account(H.player({ name = "emptied", sid = SID_NEW + 16 })) == "emptied" and ids.emptied.src == "LOGIN",
    "an empty older inbox table does not block the binding")
online = { H.player({ name = "guest", sid = SID_NEW, num = 1 }) }
St.scan()
check(ids.guest == nil, "the scan leaves split-screen guests alone")

H.section("identity: OnNewGame never moves a binding")
logs = #H.logLines
H.fire("OnNewGame", H.player({ name = "owner", sid = SID_THIEF }), nil)
check(ids.owner.sid == SID_OWNER and logged(logs, "BIND_CONFLICT") == 1, "a new character under a bound name with another SteamID: kept, BIND_CONFLICT logged")
n = #H.sent
T.ServerCommands.inboxPull(owner, {})
local got = sentSince(n, "inbox")
check(got and got.player == owner and #got.args.list == 3 and inbox.owner == nil, "the owner logs in: gets its 3 alerts, inbox cleared")
local savedKeys = {}
for _, k in ipairs(H.gos[St.SYSTEM].keys) do savedKeys[k] = true end
check(savedKeys.ids, "bindings are saved with the store (setModDataKeys)")
H.steam = false
online = { H.player({ name = "nosteam", sid = SID_NEW }) }
St.scan()
check(ids.nosteam == nil, "no-steam: the scan binds nothing")
getOnlinePlayers = savedOnline
