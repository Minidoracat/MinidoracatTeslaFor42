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
-- ponytail: the whole system is serialized into SliceY's fixed 10 MiB buffer (SliceY.java:10,
-- SGlobalObjectSystem.java:273-295; an overflow is logged and that save of the file is lost). An offline inbox is at
-- most 20 alerts of ~0.3 KB, so that is ~1700 accounts each holding a full inbox; prune inboxes of long-gone accounts or
-- split the keys into systems if a server ever gets near it.

local db
function St.get(name)
    if not db then
        local sys = SGlobalObjects.registerSystem(St.SYSTEM) -- loads the file the first time (SGlobalObjects.java:31-39)
        sys:setModDataKeys({ "seen", "alerts", "inbox", "keyIds", "moved" }) -- only these are saved (:210-230)
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

-- right after global_mod_data.bin loads (IsoWorld.java:2009, before any chunk or client): the old tables are gone
-- before anyone can ask for them, even if no Tesla loads and no inbox is touched this session
Events.OnInitGlobalModData.Add(function() St.get("inbox") end)
