-- Charging equipment table (by kind) and the geometry both sides need: which sprite is which charger, where the
-- car's charge port is, whether the cable reaches. cableExit is owned by TeslaChargerArt (cable drawing).
require "MinidoracatTesla/Core"
require "Moveables/ISMoveableSpriteProps"
require "Moveables/ISMoveablesAction"

local T = MinidoracatTesla

-- Generator fuel (litres, IsoGenerator's 10 L tank, IsoGenerator.java:505-507) per kWh a generator gives a Tesla: the
-- charge and the car's own loads it runs while plugged in (Charging.lua settle, Battery.lua B.draw). User 2026-10-28:
-- at the vanilla default GeneratorFuelConsumption 0.1 (SandboxOptions.java:146) a Model Y from 0 to 100 % (78.4 kWh)
-- takes about one full tank. User 2026-10-29: any generator power costs it, through the wiring or plugged straight
-- in (only the grid is free), scaled by the sandbox ChargeFuelMultiplier. Per kWh, so the charging speed sandbox does
-- not change what a full charge costs.
T.GEN_FUEL_PER_KWH = 100 / 78.4
function T.fuelPerKwh()
    return T.GEN_FUEL_PER_KWH * (SandboxVars.GeneratorFuelConsumption or 0.1) * T.chargeFuelMul()
end

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
    -- Power (decisions.md 2026-10-28): indoors it plugs into the building's sockets like the Wall Connector; anywhere
    -- else only straight into a running generator up to genTiles away (same floor, Chebyshev; T.directGenerator).
    MobileConnector = {
        kind = "MobileConnector",
        kw = 7.6,
        cableTiles = 5,
        item = "Base.MinidoracatTesla_MobileConnector",
        sprites = { S = "minidoracat_tesla_01_8", E = "minidoracat_tesla_01_9", N = "minidoracat_tesla_01_10", W = "minidoracat_tesla_01_11" },
        cableExit = { 0, 0.20, 0 },
        genTiles = 2,
    },
}

-- sprite name -> { kind, facing }
T.ChargerSprites = {}
for kind, c in pairs(T.Chargers) do
    for facing, sprite in pairs(c.sprites) do T.ChargerSprites[sprite] = { kind = kind, facing = facing } end
end

-- ---- power at a charger square: Charging.lua's settle and the charger menu's no-power hint share these ----

-- a running generator with fuel on that square, else nil. skip: a Cybertruck's `ps` record (gx, gy, gz), whose own
-- Powershare generator never counts for it (it never charges itself, Charging.lua C.source)
function T.generatorAt(x, y, z, skip)
    if skip and skip.gx == x and skip.gy == y and skip.gz == z then return nil end
    local sq = getCell():getGridSquare(x, y, z)
    local g = sq and sq:getGenerator() -- IsoGridSquare.java:9713
    if g and g:isActivated() and g:getFuel() > 0 then return g end -- IsoGenerator.java:497-520
    return nil
end

-- The charger is on the building wiring. A Wall Connector always is (it hangs on a wall); a charger with genTiles
-- (Mobile Connector) only indoors, vanilla's exterior flag off (IsoGridSquare.isOutside, :9431): a room or a roof
-- overhead (:7306-7317; IsoChunk.java:2428-2440 on load, IsoCell.java:4393-4405 when one is built), so a roofed
-- player-built base counts. The same flag the sandbox AllowExteriorGenerator reads in haveElectricity (:9697).
function T.onWiring(kind, sq)
    local c = T.Chargers[kind]
    return not (c and c.genTiles and sq:isOutside())
end

-- the grid reaches the charger while the grid is up: on the wiring, and the fridge rule (ItemContainer.java:2307-2330):
-- not a no-power zone, and the square or a neighbour is inside a room
local DIRS = { "N", "S", "W", "E" }
function T.gridReaches(kind, sq)
    if not T.onWiring(kind, sq) or sq:isNoPower() then return false end -- IsoGridSquare.java:11617
    if sq:getRoom() ~= nil then return true end
    for i = 1, #DIRS do
        local a = sq:getAdjacentSquare(IsoDirections[DIRS[i]])
        if a ~= nil and a:getRoom() ~= nil then return true end
    end
    return false
end

-- a generator powers the charger through the wiring: in a generator's range (haveElectricity, IsoGridSquare.java:9696-9700)
function T.wiredPower(kind, sq)
    return T.onWiring(kind, sq) and sq:haveElectricity()
end

-- plugged straight into a running generator up to genTiles from (x, y), same floor: generator, gx, gy. No sandbox
-- AllowExteriorGenerator limit (decisions.md 2026-10-28).
function T.directGenerator(kind, x, y, z, skip)
    local c = T.Chargers[kind]
    local r = c and c.genTiles
    if not r then return nil end
    for gx = x - r, x + r do
        for gy = y - r, y + r do
            local g = T.generatorAt(gx, gy, z, skip)
            if g then return g, gx, gy end
        end
    end
    return nil
end

-- ---- Cybertruck power: Powershare and the bed outlet (server/MinidoracatTesla/Powershare.lua; plan 4) ----
-- Powershare's hidden vanilla generator: our invisible tile (scripts/blender/props/build.py PS_INDEX: no image, tile
-- property GeneratorSound) placed from a hidden item whose WorldObjectSprite it is; IsoGenerator maps the sprite back
-- to that item for its SoundRadius and ConditionLowerChanceOneIn (getGeneratorItemType, IsoGenerator.java:133-156,170-199).
T.PS_SPRITE = "minidoracat_tesla_01_12"
T.PS_ITEM = "Base.MinidoracatTesla_Powershare"
-- the most the cars a Cybertruck charges get together (owner's manual p.204, p.199-201; tesla.com "up to 9.6 kW");
-- the house's load and a plugged car's own draw are not counted against it (small: a home ~0.3 kW, powershare.md)
T.PS_KW = 11.5     -- Powershare
T.OUTLET_KW = 9.6  -- the bed's 240 V outlet, 40 A
T.PS_FLOOR, T.PS_FLOOR_MIN, T.PS_FLOOR_MAX = 20, 5, 90 -- discharge limit %: Low Power Mode's default (p.199); app 5-90
function T.isPowershare(g)
    local s = g and g:getSprite()
    return s ~= nil and s:getName() == T.PS_SPRITE
end
-- the discharge limit (%) of a Cybertruck's pack (battery part modData ps.floor): Powershare and the bed outlet stop there
function T.psFloor(part)
    local ps = part and part:getModData().ps
    local f = ps and tonumber(ps.floor)
    if not f then return T.PS_FLOOR end
    return math.max(T.PS_FLOOR_MIN, math.min(T.PS_FLOOR_MAX, f))
end
-- plan 4's states: "off", "armed" (on, the house has the grid or another generator, or no Wall Connector cable),
-- "backup" (its generator is out), "stopped" (the house is out of power and it cannot supply: T.psStopWhy)
function T.psState(part)
    local ps = part and part:getModData().ps
    if not (ps and ps.on) then return "off" end
    if ps.gx then return "backup" end
    return ps.stop and "stopped" or "armed"
end
-- why a stopped Powershare gives nothing: "spot" (no outdoor square near the truck for its generator, Powershare.lua
-- PS.pickSquare) or "floor" (the pack at its discharge limit)
function T.psStopWhy(part)
    local ps = part and part:getModData().ps
    if not (ps and ps.on and not ps.gx and ps.stop) then return nil end
    return ps.stop == "spot" and "spot" or "floor"
end

-- Why Cybertruck v's bed outlet (switched on, battery part modData `outlet`) gives nothing right now, or nil when it
-- supplies: "Plugged" (a charge cable in v: AC charging turns the outlets off, owner's manual p.200), "Backup" (Home
-- Backup running, p.205), "Gate" (the tailgate up; a removed tailgate is no lid), "Floor" (at its discharge limit, or
-- no pack). The server's T.outletPowers and the phone app's line (Remote.lua outletWhy) both ask this.
function T.outletWhy(v, part)
    local md = part:getModData()
    if md.chg then return "Plugged" end
    if md.ps and md.ps.gx then return "Backup" end
    if not T.lidOpen(v, "TrunkDoor") then return "Gate" end
    if not part:getInventoryItem() or T.Battery.pct(part) <= T.psFloor(part) then return "Floor" end
    return nil
end

-- Does Cybertruck v's bed outlet power a Mobile Connector at x, y, z (user 2026-10-30: "能，照實車")? The outlet on and
-- nothing holding it off (T.outletWhy), and the charger within Specs bedOutlet.tiles of the bed area's centre
-- (Chebyshev, like genTiles; getAreaCenter, BaseVehicle.java:8363-8373), same floor.
function T.outletPowers(v, x, y, z)
    local s = T.spec(v)
    local bo = s and s.bedOutlet
    local part = bo and T.Battery.part(v)
    if not (part and part:getModData().outlet) or T.outletWhy(v, part) then return false end
    if math.floor(v:getZ()) ~= z then return false end
    local c = v:getAreaCenter(bo.area)
    return c ~= nil and math.abs(x + 0.5 - c:getX()) <= bo.tiles and math.abs(y + 0.5 - c:getY()) <= bo.tiles
end
-- The Cybertruck whose bed outlet powers a charger of `kind` at x, y, z (only a Mobile Connector plugs into one), not
-- `except`; else nil. Server / SP: the cars with the outlet on (T.OutletCars, kept by Powershare.lua), no map scan.
-- MP client (the menu's hint): the cars on the squares around.
T.OutletCars = T.OutletCars or {} -- vehicle id -> keyId (ids are handed out again: the keyId must still match)
function T.bedOutlet(kind, x, y, z, except)
    local c = T.Chargers[kind]
    if not (c and c.genTiles) then return nil end
    if not isClient() then
        for id, key in pairs(T.OutletCars) do
            local v = getVehicleById(id)
            if v and v ~= except and v:getKeyId() == key and T.outletPowers(v, x, y, z) then return v end
        end
        return nil
    end
    local cell, seen = getCell(), {}
    for dx = -5, 5 do
        for dy = -5, 5 do
            local sq = cell:getGridSquare(x + dx, y + dy, z)
            local v = sq and sq:getVehicleContainer() -- IsoGridSquare.java:9872
            if v and not seen[v] then
                seen[v] = true
                if v ~= except and T.outletPowers(v, x, y, z) then return v end
            end
        end
    end
    return nil
end

-- has the charger power right now (the menu's hint; the server books it by the hour in Charging.lua C.settle).
-- hasGridPower = not isNoPower and doesPowerGridExist (IsoGridSquare.java:11799-11801, SandboxOptions.java:1290-1292):
-- the same shut-off hour as the server's C.gridOffHour.
function T.chargerPowered(kind, sq)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    return (sq:hasGridPower() and T.gridReaches(kind, sq)) or T.wiredPower(kind, sq)
        or T.directGenerator(kind, x, y, z) ~= nil or T.bedOutlet(kind, x, y, z) ~= nil
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

-- Who may plug a charge cable into this car, pull it out, work its charge card (target %, stop) or move the charger it
-- is plugged into: the cable rule the server (Charging.lua plug / unplug / chargeTarget / chargeStop, the move guard
-- below) and the client's pre-checks (ChargerMenu.lua, HUDChargeCard.lua) share, so a button is grey exactly when the
-- server would refuse. Plugging in and the target % ask it alone; unplug, stop and moving the charger go through
-- T.mayUnplug / T.mayMoveCharger, which also let the charger's owner. VehicleManager present: its FUEL right decides
-- (T.authorized). Without it (user 2026-10-28,
-- decisions.md keyless rules; the real car's charge port opens while it is unlocked): a key, the key in the ignition,
-- a hotwired car or sandbox VehicleEasyUse (T.authorized); else an unlocked car; a locked one refuses CAR_LOCKED.
-- Locked = vanilla's own lock / unlock toggle test, any cabin door locked (isAnyDoorLocked, BaseVehicle.java:9343-9352;
-- ISVehicleMenu.lua:173, ISVehicleDashboard.lua:522).
-- Returns true, why; or false, the reason to show (IGUI_MinidoracatTesla_Deny_<reason>: VehicleManager's rent /
-- faction / quarantine locks keep theirs, any other of its refusals is NOT_OWNER) and VehicleManager's own reason for
-- the log.
function T.mayUseCable(player, vehicle)
    if not (player and vehicle) then return false, "NO_VEHICLE" end
    local ok, why = T.authorized(player, vehicle, "FUEL")
    if ok then return true, why end
    local api = MinidoracatVehicleManagerAPI
    if api and api.canUse then return false, T.VM_REASONS[why] and why or "NOT_OWNER", why end
    if not vehicle:isAnyDoorLocked() then return true, "UNLOCKED" end
    return false, "CAR_LOCKED"
end

-- The charger object on a square. Server and SP: the charger system's own object (ChargerSystem.lua; `vid` = the car's
-- getId() this session, kept while the car is unloaded and set again by Charging.lua relink; `owner` = who placed it);
-- MP client: its synced mirror (ChargerMenu.lua C.chargerAt), the same fields.
local function chargerObjectAt(x, y, z)
    if isClient() then
        local C = T.Charge
        return C and C.chargerAt and C.chargerAt(x, y, z)
    end
    local s = SMinidoracatTeslaChargerSystem and SMinidoracatTeslaChargerSystem.instance
    return s and s:getLuaObjectAt(x, y, z)
end

-- The car plugged into the charger on this square, as T.chargerCar answers.
function T.pluggedCarOn(sq)
    if not sq then return nil end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    return T.chargerCar(chargerObjectAt(x, y, z), x, y, z)
end

-- The charger's owner (main agent 2026-10-28, closing the hole the move guard opened: someone else's locked car must
-- not hold your charger): whoever placed it (`owner` = T.account at placement, the move guard below) or the owner / a
-- member of the safehouse its square is in (SafeHouse.getSafeHouse -> findSafeHouse, SafeHouse.java:157,201-219;
-- playerAllowed(name) = member or owner, :288-290). A charger placed before the record has no owner: the cable rule
-- alone. A player without an account (a split-screen guest, an unbound name on a Steam server, Core.lua) owns nothing.
function T.chargerOwner(player, x, y, z)
    local o = chargerObjectAt(x, y, z)
    local owner = o and o.owner
    local me = owner and player and T.account(player)
    if not me then return false end
    if me == owner then return true end
    local sq = getCell():getGridSquare(x, y, z)
    local safe = sq and SafeHouse and SafeHouse.getSafeHouse(sq)
    return safe ~= nil and safe:playerAllowed(me) == true
end

-- Unplug, the charge card's stop, picking up or rotating the charger: the cable rule, or the charger's owner, locked
-- car or not, VehicleManager or not. Plugging in and the target % (resume included) stay the cable rule alone.
-- Returns like T.mayUseCable ("CHARGER_OWNER" when only ownership lets it).
function T.mayUnplug(player, vehicle)
    local ok, deny, why = T.mayUseCable(player, vehicle)
    if ok then return true, deny end
    local part = T.Battery.part(vehicle)
    local chg = part and part:getModData().chg
    if chg and T.chargerOwner(player, chg.x, chg.y, chg.z) then return true, "CHARGER_OWNER" end
    return false, deny, why
end

-- The car on the cable of charger object o at x, y, z: its `vid` names a loaded car whose own record (battery part chg)
-- is this square. nil when nothing is plugged in (vid nil / false); nil, "NOT_LOADED" when vid names no such car:
-- unloaded, or the id now belongs to another car (ids are handed out again, VehicleIDMap.java:49-62,91-95).
-- Charging.lua plug (busy), relink (taken), settle and charger removal, and the charger's menu all ask this: a reused
-- id neither blocks plugging in, nor unplugs the car coming back, nor stops the car that now holds the id.
function T.chargerCar(o, x, y, z)
    if not (o and o.vid) then return nil end
    local v = getVehicleById(o.vid)
    local part = v and T.Battery.part(v)
    local chg = part and part:getModData().chg
    if chg and chg.x == x and chg.y == y and chg.z == z then return v end
    return nil, "NOT_LOADED"
end

-- Picking up or rotating a charger a car is plugged into pulls its cable out: both take the IsoObject off the square
-- (pick up: ISMoveablesAction.lua:239-240 -> ISMoveableSpriteProps.lua:1265-1269; rotate = pick up + place,
-- :2881-2900) and removal unplugs (ChargerSystem.lua OnObjectAboutToBeRemoved -> Charging.lua C.onChargerRemoved).
-- Before 2026-10-28 anyone could carry off a locked car's Mobile Connector, i.e. unplug it without the cable rule.
-- spriteName = the sprite the move takes off the square. Returns like T.mayUnplug, the car third. A plugged car that
-- is not loaded refuses (NOT_LOADED) rather than let the charger go without the rule (review 2026-10-28); its owner
-- may move it anyway.
function T.mayMoveCharger(player, sq, spriteName)
    if not T.ChargerSprites[spriteName] then return true end
    local car, missing = T.pluggedCarOn(sq)
    if not (car or missing) then return true end
    if T.chargerOwner(player, sq:getX(), sq:getY(), sq:getZ()) then return true, "CHARGER_OWNER", car end
    if missing then return false, missing end
    local ok, deny = T.mayUseCable(player, car)
    return ok, deny, car
end

-- Server side of the move guard (MP: complete runs only on the server, NetTimedAction.java:132-134, a false return
-- rejects the action, ActionManager.java:69,87-95; SP: locally). What leaves the square: pick up takes
-- moveProps.spriteName (findOnSquare, ISMoveableSpriteProps.lua:1267), rotate takes origSpriteName (:2883,2889,2899). The
-- move cursor greys the same (ChargerMenu.lua C.guardMoveCursor); the cursor panel's reason line is below.
-- The same wrap records the owner: placing makes the placer the owner; rotating (pick up + place: a new charger
-- object) keeps the old one, whoever turns it.
local function chargerObjectOn(square)
    return square and chargerObjectAt(square:getX(), square:getY(), square:getZ())
end
local complete = ISMoveablesAction and ISMoveablesAction.complete
if complete then
    function ISMoveablesAction:complete()
        local name = (self.mode == "pickup" and self.moveProps and self.moveProps.spriteName)
            or (self.mode == "rotate" and self.origSpriteName) or nil
        if name then
            local ok, deny, car = T.mayMoveCharger(self.character, self.square, name)
            if not ok then
                T.log("charger " .. self.mode .. " refused for " .. tostring(self.character:getUsername()) .. ": " .. tostring(deny))
                T.deny(self.character, deny, car and car:getId())
                return false
            end
        end
        local before = (self.mode == "place" or self.mode == "rotate") and chargerObjectOn(self.square)
        local keep = self.mode == "rotate" and before and before.owner
        local r = complete(self)
        local o = (self.mode == "place" or self.mode == "rotate") and chargerObjectOn(self.square)
        if o and o ~= before then
            o.owner = keep or (self.mode == "place" and T.account(self.character)) or nil
            if o.owner then o:updateOnClient() end
        end
        return r
    end
else
    T.log("charger move guard: ISMoveablesAction.complete missing")
end
-- the move cursor's info panel (ISMoveableCursor.lua:271) says why in red, as vanilla's own refusals (:581-584)
local describe = ISMoveableSpriteProps and ISMoveableSpriteProps.getInfoPanelDescription
if describe then
    function ISMoveableSpriteProps:getInfoPanelDescription(square, object, player, mode)
        local t = describe(self, square, object, player, mode)
        if (mode == "pickup" or mode == "rotate") and type(t) == "table" and player then
            local ok, deny = T.mayMoveCharger(player, square, self.spriteName)
            if not ok then
                local c = ISMoveableSpriteProps.bhc
                ISMoveableSpriteProps.addLineToInfoTable(t, T.denyText(deny), c:getR() * 255, c:getG() * 255, c:getB() * 255)
            end
        end
        return t
    end
else
    T.log("charger move guard: ISMoveableSpriteProps.getInfoPanelDescription missing")
end

return T
