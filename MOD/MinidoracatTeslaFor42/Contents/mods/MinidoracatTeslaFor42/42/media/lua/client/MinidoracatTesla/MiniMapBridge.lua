-- The player's Teslas on the MiniMap (MinidoracatMiniMapFor42, optional; user 2026-10-27, decisions.md "手機 App
-- 第二版"): its minimap and its world map draw the cars the phone app last saw (PhoneApp.lua App.seen: the selected
-- car every 2 s while the app is open, the others when its car list opens). A car VehicleManager already draws (its
-- own MiniMap bridge, MinidoracatVehicleManager_MiniMapBridge.lua) is left to it. Older than App.FRESH_MS (10 min):
-- drawn faded. Clicking one does nothing. Registered at OnGameStart only when the MiniMap has
-- registerMarkerProvider (MinidoracatMiniMap_Markers.lua:27; same hook-up as VehicleManager's bridge); without it the
-- app's temporary world map marker stays (PhoneApp.lua drawMapCar).
require "MinidoracatTesla/Core"
require "MinidoracatTesla/PhoneApp"

local T = MinidoracatTesla
local App = T.PhoneApp
local B = {}
T.MiniMapBridge = B
B.OWNER = T.MOD_ID
B.CHECK_MS = 10000 -- how often a marker may turn faded (the table is otherwise rebuilt only when App.seen changes)
B.stats = { builds = 0 }

local HUD_TEX = "media/textures/MinidoracatTesla/HUD/"
local WHITE = { r = 1, g = 1, b = 1 }
local BLUE = { r = 0x32 / 255, g = 0x68 / 255, b = 0xFE / 255 } -- the app's blue (PhoneApp.lua C.blue), as the app's map marker

-- keyIds VehicleManager's bridge draws for this player (its fleet rows with a keyId), only when that bridge is on
local function vmDrawn()
    local mvm = MinidoracatVehicleManager
    local vb = mvm and mvm.MiniMapBridge
    if not (vb and vb.registered) then return nil end
    local VML = T.VMLink
    local rows = VML and VML.cars and VML.cars(0) or {}
    local out = {}
    for _, r in ipairs(rows) do if r.keyId then out[r.keyId] = true end end
    return out
end

-- the cars player 0's phone keys open now: App.seen keeps cars removed from the phone or handed over with it
-- (review 2026-10-27); read only when the table is rebuilt (App.seen moved, or every CHECK_MS)
local function onPhone()
    local p = getSpecificPlayer(0)
    local out = {}
    if not p then return out end
    local list = p:getInventory():getAllTypeRecurse(T.Keys.PHONE_KEY)
    for i = 0, list:size() - 1 do
        for _, k in ipairs(T.Keys.pairedIds(list:get(i))) do out[k] = true end
    end
    return out
end

function B.build(now)
    B.stats.builds = B.stats.builds + 1
    local api = MinidoracatMiniMapAPI
    local v2 = api and type(api.markerApiVersion) == "number" and api.markerApiVersion >= 2
    local skip, mine = vmDrawn() or {}, onPhone()
    local markers, stale, keys = {}, 0, {}
    B.vmSkip = skip -- (for drawsWorld, every world map frame: no list built there)
    for key, st in pairs(App.seen) do
        if st.x and st.y and not st.deny and not skip[key] and mine[key] then
            local fresh = st.seenAt and now - st.seenAt <= App.FRESH_MS
            if not fresh then stale = stale + 1 end
            local m = { id = "tesla:" .. tostring(key), x = st.x + 0.5, y = st.y + 0.5, texture = B.tex.car,
                r = WHITE.r, g = WHITE.g, b = WHITE.b, state = fresh and "live" or "old",
                label = st.car and getText("IGUI_VehicleName" .. st.car) or nil }
            if v2 and B.tex.round then
                m.scale = 1.5
                m.badge = { texture = B.tex.round, r = BLUE.r, g = BLUE.g, b = BLUE.b, a = 1 }
                m.ring = { r = 1, g = 1, b = 1, a = 1 }
            end
            markers[#markers + 1] = m
            keys[key] = true
        end
    end
    B.drawnKeys = keys
    return markers, stale
end

-- per frame, per surface: the cached table; rebuilt when App.seen moved, or every CHECK_MS a marker may have faded
-- (or VehicleManager's bridge took one over): a new table only when something shown changed
local cache = { out = { revision = 0, markers = {} } }
function B.provider(playerNum, surface)
    if playerNum ~= 0 then return nil end -- ponytail: App.seen is one table (PhoneApp.lua); split-screen guests get none
    local now = getTimestampMs()
    if surface == "world" then B.worldAt = now end -- the MiniMap is drawing our markers on the world map right now
    if cache.rev == App.seenRev and now < (cache.checkAt or 0) then return cache.out end
    cache.checkAt = now + B.CHECK_MS
    local markers, stale = B.build(now)
    if cache.rev ~= App.seenRev or stale ~= cache.stale or #markers ~= #cache.out.markers then
        cache.rev, cache.stale = App.seenRev, stale
        cache.out = { revision = cache.out.revision + 1, markers = markers }
    end
    return cache.out
end

-- the app's temporary world map marker steps aside only while the MiniMap really draws that car there: player 0 only,
-- not when its world map layers (WMLayers) are off (then it never asks this provider for "world"), and only for a car
-- one of the two bridges has a marker for (ours from the last build, or VehicleManager's: its fleet, VM-only cars too)
function B.drawsWorld(playerNum, key)
    if not (B.registered == true and playerNum == 0 and B.worldAt ~= nil and getTimestampMs() - B.worldAt < 1000) then
        return false
    end
    if key ~= nil and B.drawnKeys and B.drawnKeys[key] then return true end
    local mvm = MinidoracatVehicleManager
    local vmOn = mvm and mvm.MiniMapBridge and mvm.MiniMapBridge.registered
    return vmOn and (key == nil or (B.vmSkip ~= nil and B.vmSkip[key] == true)) or false
end

function B.register()
    if B.registered then return end
    local api = MinidoracatMiniMapAPI
    if not (api and type(api.registerMarkerProvider) == "function") then return end
    B.tex = { car = getTexture(HUD_TEX .. "map_car.png"), round = getTexture(HUD_TEX .. "map_round.png") }
    api.registerMarkerProvider(B.OWNER, B.provider)
    B.registered = true
    T.log("MiniMap marker provider registered")
end

-- the MiniMap is not required by this MOD: load order is not guaranteed, so detect once every client file has loaded
Events.OnGameStart.Add(B.register)

return B
