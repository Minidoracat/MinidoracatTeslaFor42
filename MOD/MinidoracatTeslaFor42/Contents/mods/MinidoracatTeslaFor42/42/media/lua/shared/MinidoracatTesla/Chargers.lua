-- Charging equipment table (by kind) and the geometry both sides need: which sprite is which charger, where the
-- car's charge port is, whether the cable reaches. cableExit is owned by TeslaChargerArt (cable drawing).
require "MinidoracatTesla/Core"

local T = MinidoracatTesla

T.Chargers = {
    -- Tesla Wall Connector Gen 3: 48 A, 11.5 kW (R4); 7.3 m cable -> 6 tiles. Fuel: fridge + freezer (IsoGenerator 0.13/h).
    WallConnector = {
        kind = "WallConnector",
        kw = 11.5,
        cableTiles = 6,
        fuelPerHour = 0.13,
        item = "Base.MinidoracatTesla_WallConnector",
        sprites = { S = "minidoracat_tesla_01_0", E = "minidoracat_tesla_01_1", N = "minidoracat_tesla_01_2", W = "minidoracat_tesla_01_3" },
        -- { x, y, h }: point on the floor under the cable outlet, Facing=S, tiles from the square centre; h in floors
        cableExit = { 0, -0.40, 0.327 },
    },
}

-- sprite name -> { kind, facing }
T.ChargerSprites = {}
for kind, c in pairs(T.Chargers) do
    for facing, sprite in pairs(c.sprites) do T.ChargerSprites[sprite] = { kind = kind, facing = facing } end
end

function T.chargerInfo(isoObject)
    local sprite = isoObject and isoObject:getSprite()
    local name = sprite and sprite:getName()
    return name and T.ChargerSprites[name] or nil
end

-- Charge port world position: attachment "chargeport" (BaseVehicle.java:9955-9958); x, y in tiles.
local tmp = nil
function T.portPos(vehicle)
    tmp = tmp or Vector3f.new()
    local p = vehicle:getAttachmentWorldPos("chargeport", tmp)
    if not p then return vehicle:getX(), vehicle:getY() end
    return p:x(), p:y()
end

-- cable length check from the charger square centre to the port, same floor
function T.cableReaches(kind, cx, cy, cz, vehicle)
    local c = T.Chargers[kind]
    if not c or math.floor(vehicle:getZ()) ~= cz then return false end
    local px, py = T.portPos(vehicle)
    local dx, dy = px - (cx + 0.5), py - (cy + 0.5)
    return dx * dx + dy * dy <= c.cableTiles * c.cableTiles
end

return T
