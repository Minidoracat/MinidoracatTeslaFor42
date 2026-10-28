-- SGlobalObjectSystem "MinidoracatTeslaCharger": one Lua object per placed charger, saved in gos_MinidoracatTeslaCharger.bin.
-- Found without scanning: moveable placement fires OnObjectAdded on the server (ISMoveableSpriteProps.lua:2541),
-- chunk load goes through MapObjects.OnLoadWithSprite (MapObjects.java:184-221), pick-up / destroy fire
-- OnObjectAboutToBeRemoved; RegisterSystemClass hooks all three (SGlobalObjectSystem.lua RegisterSystemClass).
-- Saved: kind, facing, owner (T.account of who placed it, Chargers.lua move guard; nil on chargers placed before it).
-- Synced to clients: kind, facing, owner, vid (charging car's getId(); session-scoped, cleared on load, set again by
-- relink in Charging.lua).
if isClient() then return end
require "Map/SGlobalObjectSystem"
require "Map/SGlobalObject"
require "MinidoracatTesla/Chargers"

local T = MinidoracatTesla

SMinidoracatTeslaCharger = SGlobalObject:derive("SMinidoracatTeslaCharger")

function SMinidoracatTeslaCharger:new(luaSystem, globalObject)
    return SGlobalObject.new(self, luaSystem, globalObject)
end

function SMinidoracatTeslaCharger:initNew()
    self.vid = nil
end

function SMinidoracatTeslaCharger:stateFromIsoObject(isoObject)
    local info = T.chargerInfo(isoObject)
    self.kind = info and info.kind or "WallConnector"
    self.facing = info and info.facing or "S"
    self.vid = nil
end

function SMinidoracatTeslaCharger:stateToIsoObject(isoObject)
    local info = T.chargerInfo(isoObject)
    if info and (info.kind ~= self.kind or info.facing ~= self.facing) then
        self.kind, self.facing = info.kind, info.facing
        self:updateOnClient()
    end
end

-- picked up, destroyed or orphaned: the cable comes out first
function SMinidoracatTeslaCharger:aboutToRemoveFromSystem()
    local f = T.Charge and T.Charge.onChargerRemoved
    if f then f(self) end
end

SMinidoracatTeslaChargerSystem = SGlobalObjectSystem:derive("SMinidoracatTeslaChargerSystem")

function SMinidoracatTeslaChargerSystem:new()
    return SGlobalObjectSystem.new(self, "MinidoracatTeslaCharger")
end

function SMinidoracatTeslaChargerSystem:initSystem()
    SGlobalObjectSystem.initSystem(self)
    self.system:setModDataKeys({})
    self.system:setObjectModDataKeys({ "kind", "facing", "owner" })  -- SFeedingTroughSystem.lua:15-22
    self.system:setObjectSyncKeys({ "kind", "facing", "owner", "vid" })
end

function SMinidoracatTeslaChargerSystem:initLuaObjects()
    SGlobalObjectSystem.initLuaObjects(self)
    for i = 1, self:getLuaObjectCount() do self:getLuaObjectByIndex(i).vid = nil end
end

function SMinidoracatTeslaChargerSystem:newLuaObject(globalObject)
    return SMinidoracatTeslaCharger:new(self, globalObject)
end

function SMinidoracatTeslaChargerSystem:isValidIsoObject(isoObject)
    return T.chargerInfo(isoObject) ~= nil
end

-- vanilla sends the add packet before stateFromIsoObject has run for new objects in some paths; push the fields
function SMinidoracatTeslaChargerSystem:OnObjectAdded(isoObject)
    if not self:isValidIsoObject(isoObject) then return end
    self:loadIsoObject(isoObject)
    local o = self:getLuaObjectOnSquare(isoObject:getSquare())
    if o then
        T.log("charger placed " .. o.kind .. " " .. o.facing .. " at " .. o.x .. "," .. o.y .. "," .. o.z)
        o:updateOnClient()
    end
end

SGlobalObjectSystem.RegisterSystemClass(SMinidoracatTeslaChargerSystem)

-- chunk load: one Java hash lookup per object, Lua only on our sprites
local function onLoad(isoObject)
    local sys = SMinidoracatTeslaChargerSystem.instance
    if sys then sys:loadIsoObject(isoObject) end
end
local sprites = {}
for name in pairs(T.ChargerSprites) do sprites[#sprites + 1] = name end
MapObjects.OnLoadWithSprite(sprites, onLoad, 5) -- MOCampfire.lua / MOFeedingTrough.lua pattern
