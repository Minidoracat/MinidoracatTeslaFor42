-- Drive unit (Engine part) repair and salvage on a Tesla use Drive Unit Parts instead of vanilla Base.EngineParts.
-- Vanilla ISRepairEngine / ISTakeEngineParts hardcode "EngineParts" in complete() (shared/Vehicles/TimedActions/), so
-- the two actions below copy their complete() with our item and the same formulas. Vanilla's two actions refuse a
-- Tesla: isValid stops the client queue; the server only runs complete() (NetTimedAction.java:118-135, rejected when
-- it returns false, ActionManager.java:69-88). complete() runs on the server or in SP (LuaTimedActionNew.java:164-170);
-- the server rebuilds an action from new()'s parameter names (NetTimedAction.java:41-50,142-170).
require "Vehicles/TimedActions/ISRepairEngine"
require "Vehicles/TimedActions/ISTakeEngineParts"
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local DU = {}
T.DriveUnit = DU
DU.ITEM = "Base.MinidoracatTesla_DriveUnitParts"

-- levels over the script's engine repair level (Tesla 6); the menu wants >= 0 (ISVehicleMechanics.lua:325,333)
function DU.skillOver(chr, vehicle)
    return chr:getPerkLevel(Perks.Mechanics) - vehicle:getScript():getEngineRepairLevel()
end

function DU.count(chr) return chr:getInventory():getNumberOfItem(DU.ITEM, false, true) end -- bags included, as vanilla

function DU.canTake(chr, part, wrench) -- ISVehicleMechanics.lua:325
    return part:getCondition() > 10 and DU.skillOver(chr, part:getVehicle()) >= 0 and wrench ~= nil
end

function DU.canRepair(chr, part, wrench) -- ISVehicleMechanics.lua:333
    return part:getCondition() < 100 and DU.count(chr) > 0 and DU.skillOver(chr, part:getVehicle()) >= 0 and wrench ~= nil
end

-- ISRepairEngine.lua:47-58: each part adds 1 + skill/2 (max 5) until 100; returns the parts used
function DU.repair(part, n, skill)
    local per, done = math.min(1 + skill / 2, 5), 0
    for _ = 1, n do
        part:setCondition(part:getCondition() + per)
        done = done + 1
        if part:getCondition() >= 100 then
            part:setCondition(100)
            break
        end
    end
    return done
end

-- ISTakeEngineParts.lua:43-46: one part per random(c/3, c) condition points, c = max(20 - skill, 5)
function DU.salvage(cond, skill)
    local c = math.max(20 - skill, 5)
    c = ZombRand(c / 3, c)
    return math.floor(cond / c), c
end

-- ---- vanilla actions refuse a Tesla
for _, cls in ipairs({ ISRepairEngine, ISTakeEngineParts }) do
    local isValid, complete = cls.isValid, cls.complete
    function cls:isValid() return not T.isTesla(self.vehicle) and isValid(self) end
    function cls:complete()
        if T.isTesla(self.vehicle) then return false end
        return complete(self)
    end
end

-- ---- repair: ISRepairEngine with Drive Unit Parts
ISMinidoracatTeslaRepairDriveUnit = ISRepairEngine:derive("ISMinidoracatTeslaRepairDriveUnit")

function ISMinidoracatTeslaRepairDriveUnit:isValid() return T.isTesla(self.vehicle) end

function ISMinidoracatTeslaRepairDriveUnit:start()
    self.item:setJobType(getText("IGUI_MinidoracatTesla_RepairDriveUnit"))
    self:setActionAnim("VehicleWorkOnMid")
end

-- ISRepairEngine.lua:37-89; also refuses a non-Tesla and a mechanic under the repair level (vanilla trusts the menu)
function ISMinidoracatTeslaRepairDriveUnit:complete()
    local v, part, chr = self.vehicle, self.part, self.character
    if not part or not self.item or not T.isTesla(v) then return false end
    local skill = DU.skillOver(chr, v)
    if skill < 0 then return false end
    local giveXP = chr:getMechanicsItem(v:getMechanicalID() .. "2") == nil
    local done = DU.repair(part, DU.count(chr), skill)
    if done > 0 then
        if giveXP then addXp(chr, Perks.Mechanics, done) end
        local used = chr:getInventory():getSomeTypeRecurse(DU.ITEM, done)
        for i = 0, used:size() - 1 do
            local item = used:get(i)
            local container = item:getContainer()
            if container then
                container:DoRemoveItem(item)
                sendRemoveItemFromContainer(container, item)
            end
        end
        v:transmitPartCondition(part)
    else
        addXp(chr, Perks.Mechanics, 1)
    end
    chr:sendObjectChange(IsoObjectChange.MECHANIC_ACTION_DONE, { success = (done > 0) })
    if done > 0 then
        chr:addMechanicsItem(self.item:getID() .. v:getMechanicalID() .. "1", part, getGameTime():getCalender():getTimeInMillis())
    else
        addXp(chr, Perks.Mechanics, 1)
    end
    chr:addMechanicsItem(v:getMechanicalID() .. "2", part, getGameTime():getCalender():getTimeInMillis())
    return true
end

function ISMinidoracatTeslaRepairDriveUnit:new(character, part, item, maxTimeInit)
    local o = ISRepairEngine.new(self, character, part, item, maxTimeInit)
    o.jobType = getText("IGUI_MinidoracatTesla_RepairDriveUnit")
    return o
end

-- ---- salvage: ISTakeEngineParts giving Drive Unit Parts
ISMinidoracatTeslaTakeDriveUnitParts = ISTakeEngineParts:derive("ISMinidoracatTeslaTakeDriveUnitParts")

function ISMinidoracatTeslaTakeDriveUnitParts:isValid() return T.isTesla(self.vehicle) end

function ISMinidoracatTeslaTakeDriveUnitParts:start()
    self.item:setJobType(getText("IGUI_MinidoracatTesla_TakeDriveUnitParts"))
end

-- ISTakeEngineParts.lua:31-71; same extra refusals as the repair
function ISMinidoracatTeslaTakeDriveUnitParts:complete()
    local v, part, chr = self.vehicle, self.part, self.character
    if not part or not self.item or not T.isTesla(v) then return false end
    local skill = DU.skillOver(chr, v)
    if skill < 0 then return false end
    local cond = part:getCondition()
    local numParts, condForPart = DU.salvage(cond, skill)
    if numParts > 0 then
        local items = chr:getInventory():AddItems(DU.ITEM, numParts)
        sendAddItemsToContainer(chr:getInventory(), items)
    else
        addXp(chr, Perks.Mechanics, 1)
    end
    part:setCondition(0)
    v:transmitPartCondition(part)
    chr:sendObjectChange(IsoObjectChange.MECHANIC_ACTION_DONE, { success = (numParts > 0) })
    if numParts > 0 then
        chr:addMechanicsItem(self.item:getID() .. v:getMechanicalID() .. "1", part, getGameTime():getCalender():getTimeInMillis())
    else
        addXp(chr, Perks.Mechanics, 1)
    end
    if not chr:getMechanicsItem(v:getMechanicalID() .. "3") then
        addXp(chr, Perks.Mechanics, numParts / 2)
    end
    chr:addMechanicsItem(v:getMechanicalID() .. "3", part, getGameTime():getCalender():getTimeInMillis())
    return true
end

function ISMinidoracatTeslaTakeDriveUnitParts:new(character, part, item, maxTimeInit)
    local o = ISTakeEngineParts.new(self, character, part, item, maxTimeInit)
    o.jobType = getText("IGUI_MinidoracatTesla_TakeDriveUnitParts")
    return o
end
