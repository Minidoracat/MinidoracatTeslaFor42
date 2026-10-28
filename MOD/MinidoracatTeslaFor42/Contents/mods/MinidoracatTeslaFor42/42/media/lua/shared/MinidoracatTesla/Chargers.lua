-- Charging equipment table (by kind) and the geometry both sides need: which sprite is which charger, where the
-- car's charge port is, whether the cable reaches. cableExit is owned by TeslaChargerArt (cable drawing).
require "MinidoracatTesla/Core"
require "Moveables/ISMoveableSpriteProps"

local T = MinidoracatTesla

-- Generator fuel (litres, IsoGenerator's 10 L tank) per kWh charged, x GeneratorFuelConsumption (Charging.lua settle);
-- every charger burns kw x this per hour. The one number to tune. User 2026-10-28: at the vanilla default
-- GeneratorFuelConsumption 0.1 (SandboxOptions.java:146) a Model Y from 0 to 100 % (78.4 kWh) takes about one full tank.
T.GEN_FUEL_PER_KWH = 100 / 78.4

-- Cable tiles: official metres x 6 / 7.3 (the Wall Connector's 7.3 m plays as 6 tiles), rounded.
T.Chargers = {
    -- Tesla Wall Connector Gen 3: 48 A, 11.5 kW (R4); 7.3 m cable -> 6 tiles.
    WallConnector = {
        kind = "WallConnector",
        kw = 11.5,
        cableTiles = 6,
        item = "Base.MinidoracatTesla_WallConnector",
        sprites = { S = "minidoracat_tesla_01_0", E = "minidoracat_tesla_01_1", N = "minidoracat_tesla_01_2", W = "minidoracat_tesla_01_3" },
        -- { x, y, h }: point on the floor under the cable outlet, Facing=S, tiles from the square centre; h in floors
        -- (0 = the cable leaves at floor level: no hang segment, Cable.lua)
        cableExit = { 0, -0.40, 0.327 },
    },
    -- Tesla Gen 3 Mobile Connector (North America): 32 A at 240 V (NEMA 14-50), 7.6 kW; 6 m (20 ft) cable -> 5 tiles
    -- (official.md 1.2). Sits on the floor (the tile's default MoveType Object).
    MobileConnector = {
        kind = "MobileConnector",
        kw = 7.6,
        cableTiles = 5,
        item = "Base.MinidoracatTesla_MobileConnector",
        sprites = { S = "minidoracat_tesla_01_8", E = "minidoracat_tesla_01_9", N = "minidoracat_tesla_01_10", W = "minidoracat_tesla_01_11" },
        cableExit = { 0, 0.20, 0 },
    },
}

-- sprite name -> { kind, facing }; fuelPerHour = kw x GEN_FUEL_PER_KWH
T.ChargerSprites = {}
for kind, c in pairs(T.Chargers) do
    c.fuelPerHour = c.kw * T.GEN_FUEL_PER_KWH
    for facing, sprite in pairs(c.sprites) do T.ChargerSprites[sprite] = { kind = kind, facing = facing } end
end

function T.chargerInfo(isoObject)
    local sprite = isoObject and isoObject:getSprite()
    local name = sprite and sprite:getName()
    return name and T.ChargerSprites[name] or nil
end

-- One charger a square: the charger system keys its objects by square (ChargerSystem.lua), but vanilla lets a floor
-- object share a square with a wall object or another floor object (isFreeTile only looks at BlocksPlacement and
-- trees, ISMoveableSpriteProps.lua:1074-1083,1747-1772), and two wall objects on different walls of one square (it
-- only refuses the same Facing, :1800-1801). Both the cursor and the server's ISMoveablesAction:complete
-- (placeMoveable, :2050) ask canPlaceMoveableInternal, so the check sits there; rotating passes _forceAllow
-- (:2900 -> :2050), so this never blocks a rotation.
function T.chargerOnSquare(sq)
    local objs = sq and sq:getObjects()
    if not objs then return false end
    for i = 0, objs:size() - 1 do
        if T.chargerInfo(objs:get(i)) then return true end
    end
    return false
end
local canPlace = ISMoveableSpriteProps and ISMoveableSpriteProps.canPlaceMoveableInternal
if canPlace then
    function ISMoveableSpriteProps:canPlaceMoveableInternal(character, square, item, forceTypeObject)
        if T.ChargerSprites[self.spriteName] and T.chargerOnSquare(square) then return false end
        return canPlace(self, character, square, item, forceTypeObject)
    end
else
    T.log("charger placement guard: ISMoveableSpriteProps.canPlaceMoveableInternal missing")
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
