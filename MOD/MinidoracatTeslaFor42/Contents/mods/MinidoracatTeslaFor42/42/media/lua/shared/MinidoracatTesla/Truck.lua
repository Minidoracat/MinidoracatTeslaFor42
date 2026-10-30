-- Cybertruck features (plan-cybertruck-1030 item 5): bed lights (Auto), roof light bar, Armor Glass.
require "MinidoracatTesla/Core"
require "TimedActions/ISSmashWindow"

local T = MinidoracatTesla
local R = {}
T.Truck = R
T.Init = T.Init or {}

-- Light part inits (both sides, every load: VehicleLight saves only active/offset/intensity/dist, VehicleLight.java:85-102;
-- the colour and dot are set again here, like CampPower.lua Init.CabinLight). The spot offset comes from the vehicle
-- script's `table light { xOffset, yOffset }` (geometry, like vanilla's `table headlight`, Vehicles.lua:1512-1520), in
-- half body extents; y < 0 = rear.
local function spot(part, dist, intensity, dot, r, g, b)
    local t = part:getTable("light")
    local x = t and tonumber(t.xOffset) or 0
    local y = t and tonumber(t.yOffset) or 0
    part:createSpotLightColor(x, y, dist, intensity, dot, 0, r, g, b)
end
-- bed lights: all round (dot -1) over the bed, cool white LED
function T.Init.BedLight(vehicle, part)
    spot(part, 4, 0.45, -1, 1.0, 0.96, 0.9)
end
-- roof light bar: forward, vanilla headlight cone (dot 0.75) and brightness, farther (36 -> 48; Vehicles.lua:1505-1509)
function T.Init.RoofLight(vehicle, part)
    spot(part, 48, 0.75, 0.75, 1.0, 1.0, 1.0)
end

local function isOpen(v, id)
    local p = v:getPartById(id)
    local d = p and p:getInventoryItem() and p:getDoor()
    return d ~= nil and d:isOpen()
end

-- Server (or SP): bed lights on Auto, on while the tailgate or the tonneau is open (owner's manual p.83). Called where
-- a lid changes (Liftgate.lua: L.swing, vanilla open / close completes), never polled; setLightActive sends the part
-- light only on a change (VehiclePart.java:725-729) and the light's state is saved (VehicleLight.java:85-102).
function R.bedLight(v)
    local p = v:getPartById("BedLight")
    if p then p:setLightActive(isOpen(v, "TrunkDoor") or isOpen(v, "TrunkTonneau")) end
end

-- client: the V radial menu's light bar slice (HUDRadial.lua)
function R.roofLightOn(v)
    local p = v and v:getPartById("RoofLight")
    local light = p and p:getLight()
    return light ~= nil and light:getActive()
end

-- ------------------------------------------------------------------ Armor Glass
-- A Cybertruck window takes 3 smashes (Specs armorGlass; tesla.com: "Armor Glass can resist the impact of a baseball
-- at 70 mph"). Vanilla's one right-click action, ISSmashWindow (ISVehiclePartMenu.lua:367-378), breaks it in one go:
-- SP in Java from start's smashCarWindow (SmashWindowState.java:120-125, local player, not a client), MP on the server
-- in complete (ISSmashWindow.lua:46-60). On an armoured car start plays a heavy swing instead and complete, on the
-- server or in SP, takes a third of the glass each time (VehicleWindow.damage: the alarm, the smash sound and the
-- broken glass at 0 as vanilla, VehicleWindow.java:76-107); the condition is the count, so a new window starts over.
-- Bare hands cut like vanilla. Loaded from shared, before VehicleManager's server wrap of the same complete
-- (MinidoracatVehicleManager_ActionGuards.lua, SALVAGE): its refusal comes first and counts no hit.
local function armour(a)
    local w = a.window
    if not w or not instanceof(w, "VehicleWindow") then return nil end -- a house window is not a car's
    local part = w:getPart() -- the window's own car, not the action's vehiclePart field
    local s = T.spec(part and part:getVehicle())
    return s and s.armorGlass
end

local start, complete = ISSmashWindow.start, ISSmashWindow.complete
function ISSmashWindow:start()
    if not armour(self) then return start(self) end
    self:setActionAnim("Destroy") -- AnimSets/player/actions/Destroy.xml: a two-handed heavy hit
end

function ISSmashWindow:complete()
    local hits = armour(self)
    if not hits then return complete(self) end
    if not isClient() and not self.window:isDestroyed() then
        self.window:damage(math.ceil(100 / hits))
        local c = self.character
        if not instanceof(c:getPrimaryHandItem(), "HandWeapon") and not instanceof(c:getSecondaryHandItem(), "HandWeapon") then
            c:getBodyDamage():setScratchedWindow()
            if isServer() then sendDamage(c) end
        end
        T.log("armor glass vid=" .. tostring(self.window:getPart():getVehicle():getId()) .. " "
            .. self.window:getPart():getId() .. " hp=" .. tostring(self.window:getHealth()) .. " by=" .. c:getUsername())
    end
    return true
end

-- ------------------------------------------------------------------ roof light bar (server)
-- `roofLight` { vid }: the driver switches the light bar; setLightActive sends it to everyone (VehiclePart.java:725-729).
if not isClient() then
    T.ServerCommands = T.ServerCommands or {}
    T.ServerCommands.roofLight = function(player, args)
        local v = T.commandVehicle(player, args) -- server/MinidoracatTesla/Commands.lua
        if not v then return end
        if v:getDriver() ~= player then return T.deny(player, "NOT_DRIVER", v:getId()) end
        local p = v:getPartById("RoofLight")
        local light = p and p:getLight()
        if not light then return end
        p:setLightActive(not light:getActive())
        T.log("roof light " .. (light:getActive() and "on" or "off") .. " vid=" .. tostring(v:getId()) .. " by=" .. player:getUsername())
    end
end

return R
