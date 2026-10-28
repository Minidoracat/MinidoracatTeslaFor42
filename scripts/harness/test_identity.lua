-- Account identity (Core.lua T.account; Store.lua St.onNewGame / St.verify; family conventions.md, player identity):
-- a slot-0 player renamed on respawn to an offline owner (ConnectCoopPacket.java:65-109, GameServer.java:2848) must
-- not speak for that owner on a Steam server. The engine fact (the server really shows slot 0 under the new name) and
-- the real login flow are E2E identity-mp.
local check = H.check
local T = MinidoracatTesla
H.require("MinidoracatTesla/Store")
H.require("MinidoracatTesla/Inbox")
H.side(false, true)
local St = T.Store
local ids, inbox = St.get("ids"), St.get("inbox")
local SID_OWNER, SID_THIEF, SID_OLD = 76561198000000016, 76561198012345680, 76561198000000032
local savedOnline = getOnlinePlayers
local online = {}
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
local function sentSince(n, cmd)
    for i = n + 1, #H.sent do if H.sent[i].command == cmd then return H.sent[i] end end
end

H.section("identity: no-steam server, split-screen guests")
H.steam = false
local owner = H.player({ name = "owner" })
check(T.account(owner) == "owner" and next(ids) == nil, "no-steam: the name; nothing bound (no SteamID to check it against)")
check(T.account(H.player({ name = "owner", num = 1 })) == nil, "split-screen guest (slot 1): no account")
H.side(false, false)
check(T.account(H.player({ name = "Bob Smith", num = 1 })) == "Bob Smith", "SP: the username")
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
-- the thief dies and respawns: CreatePlayer with its own login name, then ConnectCoop names slot 0 "owner"
H.advanceMs(10 * 60000)
H.fire("OnNewGame", H.player({ name = "thief", sid = SID_THIEF }), nil)
local renamed = H.player({ name = "owner", sid = SID_THIEF })
check(T.account(renamed) == nil, "respawn renamed to the offline owner (the thief's SteamID): no account")
local n = #H.sent
T.ServerCommands.inboxPull(renamed, {})
local deny = sentSince(n, "deny")
check(#inbox.owner == 2 and sentSince(n, "inbox") == nil, "...inboxPull: the owner's inbox is neither sent nor cleared")
check(deny and deny.player == renamed and deny.args.reason == "IDENTITY_UNVERIFIED", "...and it is told IDENTITY_UNVERIFIED")
online = { renamed }
n = #H.sent
T.Inbox.notify("owner", { kind = "touch", what = "door" })
check(sentSince(n, "alert") == nil and #inbox.owner == 3, "...a live alert for the owner goes to the inbox, not to it")
check(T.legit(renamed, H.vehicle({}), "owner") == false, "...the sentry owner's name does not make it legit")
n = #H.sent
T.ServerCommands.inboxPull(H.player({ name = "thief", sid = SID_THIEF }), {})
check(sentSince(n, "deny") == nil, "the thief under its own name: verified, nothing to deliver, no deny")

H.section("identity: first seen (characters from before the binding)")
local carol = H.player({ name = "carol", sid = SID_THIEF })
check(T.account(carol) == nil and ids.carol == nil,
    "a name never seen, right after OnNewGame made another name for this SteamID (a renamed respawn): not bound")
H.advanceMs(St.RENAME_MS + 1)
check(T.account(carol) == "carol" and ids.carol.src == "LOGIN", "the same name after the respawn window: bound on first sight")
local vet = H.player({ name = "veteran", sid = SID_OLD })
check(T.account(vet) == "veteran" and ids.veteran.sid == SID_OLD and ids.veteran.src == "LOGIN",
    "a character from before the MOD (no OnNewGame), alive: bound on first sight")
local ghost = H.player({ name = "ghost", sid = SID_OLD })
ghost.dead = true
check(T.account(ghost) == nil and ids.ghost == nil, "dead: not bound")
check(T.account(H.player({ name = "nosid", sid = 0 })) == nil and ids.nosid == nil, "no SteamID: not bound")
check(T.account(H.player({ name = "", sid = SID_OLD })) == nil and ids[""] == nil, "empty name: none")

H.section("identity: OnNewGame never moves a binding")
local logs = #H.logLines
H.fire("OnNewGame", H.player({ name = "owner", sid = SID_THIEF }), nil)
local conflict = false
for i = logs + 1, #H.logLines do if H.logLines[i]:find("BIND_CONFLICT", 1, true) then conflict = true end end
check(ids.owner.sid == SID_OWNER and conflict, "a new character under a bound name with another SteamID: kept, BIND_CONFLICT logged")
n = #H.sent
T.ServerCommands.inboxPull(owner, {})
local got = sentSince(n, "inbox")
check(got and got.player == owner and #got.args.list == 3 and inbox.owner == nil, "the owner logs in: gets its 3 alerts, inbox cleared")
local savedKeys = {}
for _, k in ipairs(H.gos[St.SYSTEM].keys) do savedKeys[k] = true end
check(savedKeys.ids, "bindings are saved with the store (setModDataKeys)")

H.steam = false
getOnlinePlayers = savedOnline
