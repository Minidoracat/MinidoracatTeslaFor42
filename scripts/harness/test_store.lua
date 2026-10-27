-- Server-only store (server/MinidoracatTesla/Store.lua): an older save's Global ModData tables (offline inbox, Tesla
-- keyId registry) move into the GOS system once and disappear from Global ModData, which any client may request by
-- name (GlobalModDataRequestPacket.java). Real save files and the client request: E2E fix1027-mp.
local check = H.check
local T = MinidoracatTesla
local SRC = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/server/MinidoracatTesla/Store.lua"

H.section("store: an older save's Global ModData moves in")
local entry = { kind = "touch", what = "door", by = "thief", x = 1, y = 2, key = 424242 }
H.moddata.MinidoracatTesla_Inbox = { ghost = { entry } }
H.moddata.MinidoracatTesla_KeyIds = { ["424242"] = "MinidoracatTesla_ModelY", ["77"] = "old name" }
local sys = H.gos[T.Store.SYSTEM]
sys.md.keyIds["77"] = "MinidoracatTesla_ModelY" -- already in the store: kept
sys.md.moved = nil -- a store saved by the version before (the app's records only)
local logs0 = #H.logLines
dofile(SRC) -- a fresh server start: the store is opened again
H.fire("OnInitGlobalModData", false) -- IsoWorld.java:2009: GlobalObjectLookup is not set up yet (:2179)
check(H.moddata.MinidoracatTesla_Inbox ~= nil,
    "nothing opens the GOS system at the global data load (a system registered then breaks every chunk load)")
H.fire("OnSGlobalObjectSystemInit") -- SGlobalObjects.initSystems: before any client connects or the world saves
check(H.moddata.MinidoracatTesla_Inbox == nil and H.moddata.MinidoracatTesla_KeyIds == nil,
    "the systems' start moves them, before anything else asks the store")
local St = T.Store
check(St.get("inbox").ghost and St.get("inbox").ghost[1] == entry, "offline inbox moved into the store")
check(St.get("keyIds")["424242"] == "MinidoracatTesla_ModelY", "keyId registry moved into the store")
check(St.get("keyIds")["77"] == "MinidoracatTesla_ModelY", "an entry the store already has wins over the old table")
check(H.moddata.MinidoracatTesla_Inbox == nil and H.moddata.MinidoracatTesla_KeyIds == nil,
    "old Global ModData tables removed: no longer saved, nothing for a client to request")
local moved = 0
for i = logs0 + 1, #H.logLines do if H.logLines[i]:find("moved Global ModData", 1, true) then moved = moved + 1 end end
check(moved == 2, "one log line per moved table")
check(sys.md.getInitialStateForClient() == nil, "the GOS system sends clients nothing")
dofile(SRC) -- next start: nothing left to move
H.fire("OnSGlobalObjectSystemInit")
check(T.Store.get("inbox").ghost[1] == entry and H.moddata.MinidoracatTesla_Inbox == nil, "second start: data kept, nothing recreated")
local savedKeys = {}
for _, k in ipairs(sys.keys) do savedKeys[k] = true end
check(sys.md.moved == true and savedKeys.moved and savedKeys.inbox and savedKeys.keyIds and savedKeys.seen
    and savedKeys.alerts, "the store remembers it has moved them, and saves every key (setModDataKeys)")
-- crash after the store was saved but before global_mod_data.bin: the old tables are on disk again, while the inbox
-- was pulled (and that saved) since
T.Store.get("inbox").ghost = nil
H.moddata.MinidoracatTesla_Inbox = { ghost = { entry } }
dofile(SRC)
H.fire("OnSGlobalObjectSystemInit")
check(T.Store.get("inbox").ghost == nil and H.moddata.MinidoracatTesla_Inbox == nil,
    "old table left by a crash between the two saves: removed, a pulled inbox is not delivered again")
