-- Plug / unplug timed actions. complete() runs on the server or in SP only (LuaTimedActionNew.java:164-170);
-- the server rebuilds the action from new()'s parameter names (NetTimedAction.java:41-50,142-170), so the fields
-- are named exactly like the parameters. All checks are repeated on the server in MinidoracatTesla.Charge.
require "TimedActions/ISBaseTimedAction"
require "MinidoracatTesla/Core"

ISMinidoracatTeslaPlug = ISBaseTimedAction:derive("ISMinidoracatTeslaPlug")

function ISMinidoracatTeslaPlug:isValid()
    return self.vehicle ~= nil and self.charger ~= nil and self.charger:getSquare() ~= nil
end

function ISMinidoracatTeslaPlug:waitToStart()
    self.character:faceThisObject(self.charger) -- ISActivateCarBatteryChargerAction.lua:11
    return self.character:shouldBeTurning()
end

function ISMinidoracatTeslaPlug:update()
    self.character:faceThisObject(self.charger)
end

function ISMinidoracatTeslaPlug:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
end

function ISMinidoracatTeslaPlug:stop()
    ISBaseTimedAction.stop(self)
end

function ISMinidoracatTeslaPlug:perform()
    ISBaseTimedAction.perform(self)
end

function ISMinidoracatTeslaPlug:complete()
    local C = MinidoracatTesla.Charge
    if C then C.plug(self.character, self.vehicle, self.charger) end
    return true
end

function ISMinidoracatTeslaPlug:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 120
end

function ISMinidoracatTeslaPlug:new(character, vehicle, charger)
    local o = ISBaseTimedAction.new(self, character)
    o.vehicle = vehicle
    o.charger = charger
    o.maxTime = o:getDuration()
    return o
end

ISMinidoracatTeslaUnplug = ISBaseTimedAction:derive("ISMinidoracatTeslaUnplug")

function ISMinidoracatTeslaUnplug:isValid()
    return self.vehicle ~= nil
end

function ISMinidoracatTeslaUnplug:waitToStart()
    self.character:faceThisObject(self.vehicle)
    return self.character:shouldBeTurning()
end

function ISMinidoracatTeslaUnplug:update()
    self.character:faceThisObject(self.vehicle)
end

function ISMinidoracatTeslaUnplug:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
end

function ISMinidoracatTeslaUnplug:stop()
    ISBaseTimedAction.stop(self)
end

function ISMinidoracatTeslaUnplug:perform()
    ISBaseTimedAction.perform(self)
end

function ISMinidoracatTeslaUnplug:complete()
    local C = MinidoracatTesla.Charge
    if C then C.unplug(self.character, self.vehicle) end
    return true
end

function ISMinidoracatTeslaUnplug:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 80
end

function ISMinidoracatTeslaUnplug:new(character, vehicle)
    local o = ISBaseTimedAction.new(self, character)
    o.vehicle = vehicle
    o.maxTime = o:getDuration()
    return o
end
