-- What the server keeps for itself, in a server-only GOS system (gos_MinidoracatTeslaApp.bin), never Global ModData:
-- any logged-in client can fetch a whole Global ModData table by name (GlobalModDataRequestPacket.java:15,32 ->
-- GlobalModData.java:171; family conventions.md). T.Store.get(name):
--   seen: tostring(keyId) -> the app's last record; alerts: tostring(keyId) -> alerts, oldest first (Remote.lua)
--   inbox: account -> offline alerts (Inbox.lua); keyIds: tostring(keyId) -> car model (KeyActions.lua)
if isClient() then return end
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local St = {}
T.Store = St
St.SYSTEM = "MinidoracatTeslaApp" -- named after its first user, the phone app; the file name is in saves now
St.KEYS = { "seen", "alerts", "inbox", "keyIds" }
-- Global ModData tables of older saves: moved in once, then removed so they are neither saved nor served again
St.LEGACY = { inbox = "MinidoracatTesla_Inbox", keyIds = "MinidoracatTesla_KeyIds" }
-- ponytail: the whole system is serialized into SliceY's fixed 10 MiB buffer (SliceY.java:10). save() truncates the
-- file before it serializes and only logs the overflow (SGlobalObjectSystem.java:279-295), so a save past 10 MiB empties
-- the file and the next start finds the whole store gone. Every list is capped (20 inbox alerts an account, 10 app
-- alerts a car), so it grows only with accounts and cars: ~1600 owners each with a full inbox and a car full of alerts
-- (review verify 2026-10-27). Prune inboxes of long-gone accounts or split the keys into systems (one buffer each,
-- SGlobalObjects.java:151-156) if a server ever gets near it.

local db
function St.get(name)
    if not db then
        local sys = SGlobalObjects.registerSystem(St.SYSTEM) -- loads the file the first time (SGlobalObjects.java:31-39)
        local saved = { "moved" } -- only these are saved (:210-230)
        for _, key in ipairs(St.KEYS) do saved[#saved + 1] = key end
        sys:setModDataKeys(saved)
        sys:setObjectModDataKeys({})
        sys:setObjectSyncKeys({})
        db = sys:getModData()
        -- GOS calls these by rawget on this table (SGlobalObjectSystem.java:95-162): nothing goes to clients
        db.getInitialStateForClient = function() return nil end
        db.OnClientCommand = function() end
        db.isValidIsoObject = function() return false end
        db.OnChunkLoaded = function() end
        for _, key in ipairs(St.KEYS) do
            if type(db[key]) ~= "table" then db[key] = {} end
        end
        -- The GOS file is saved before global_mod_data.bin (ServerMap.java:391,409; GameWindow.java:1073,1080). A crash
        -- in between keeps the old tables on disk next to a store that already has them (`moved`, saved with it): they
        -- are then only removed, so an inbox pulled since is not delivered twice. Never neither.
        for key, legacy in pairs(St.LEGACY) do
            local old = ModData.remove(legacy) -- GlobalModData.java:104-106
            if old and not db.moved then
                local n = 0
                for k, val in pairs(old) do
                    if db[key][k] == nil then db[key][k] = val end
                    n = n + 1
                end
                T.log("moved Global ModData " .. legacy .. " (" .. n .. ") into " .. St.SYSTEM .. "." .. key)
            end
        end
        db.moved = true
    end
    return db[name]
end

-- where vanilla opens its systems (SGlobalObjects.initSystems: GameServer.java:816, SP GameLoadingState.java:313), before
-- any client connects or the world is saved: the old tables are gone before anyone can ask for them, even if no Tesla
-- loads and no inbox is touched this session. NOT at OnInitGlobalModData: that fires (IsoWorld.java:2009) before
-- GlobalObjectLookup.init (:2179), and a system registered then keeps a null cell table -> every chunk load throws in
-- SGlobalObjectSystem.chunkLoaded and no client gets past "loading map" (tesla-fix-1027m/o). A Tesla's chunk loading
-- first (SP) opens it earlier through St.get, after the lookup is set up, as the app always did.
Events.OnSGlobalObjectSystemInit.Add(function() St.get("inbox") end)
