-- Tall hats hidden while seated (server/MinidoracatTesla/HatHide.lua): the hider goes on only for a hat TallHats lists
-- for that seat, comes off (and out of the inventory) on getting out, a cap, another car or death; the game-minute
-- reconcile covers every online player (MP) or the local ones (SP). What the hider hides is engine behaviour (body
-- location hideModel): E2E seat-hat-sp and hat-mp.
local check = H.check

H.section("hat hider")
local HAT, FULL, LOC = "base:hat", "base:fullhat", "MinidoracatTesla:HatHide"
ItemBodyLocation = ItemBodyLocation or {}
ItemBodyLocation.HAT, ItemBodyLocation.FULL_HAT = HAT, FULL
MinidoracatTeslaHatLoc = LOC
local savedSend = { add = sendAddItemToContainer, rem = sendRemoveItemFromContainer }
local sent = { add = 0, rem = 0 }
function sendAddItemToContainer() sent.add = sent.add + 1 end
function sendRemoveItemFromContainer() sent.rem = sent.rem + 1 end

H.side(false, true)
H.require("MinidoracatTesla/HatHide")
local Hd = MinidoracatTesla.HatHide
check(MinidoracatTesla.TallHats["Model3/FrontLeft"].Hat_Stovepipe and not MinidoracatTesla.TallHats["ModelX/FrontLeft"].Hat_Stovepipe,
    "TallHats: a top hat leaves the Model 3 roof, not the Model X front one (seat_head.py --tall-lua)")

local function hatItem(ci) return { ci = ci, getClothingItemName = function(self) return self.ci end } end
local function wearer(name)
    local p = H.player({ name = name })
    p.worn, p.items = {}, {}
    function p:getWornItem(loc) return self.worn[loc] end
    function p:setWornItem(loc, it) self.worn[loc] = it end
    function p:removeWornItem(it) for k, v in pairs(self.worn) do if v == it then self.worn[k] = nil end end end
    function p:getInventory()
        local items = self.items
        return {
            AddItem = function(_, t) local it = { type = t }; items[#items + 1] = it; return it end,
            Remove = function(_, it) for i = #items, 1, -1 do if items[i] == it then table.remove(items, i) end end end,
            getAllType = function(_, t)
                local l = {}
                for _, it in ipairs(items) do if it.type == t then l[#l + 1] = it end end
                return { size = function() return #l end, get = function(_, i) return l[i + 1] end }
            end,
        }
    end
    return p
end
local function car(model, seats)
    local v = H.vehicle({ script = "Base.MinidoracatTesla_" .. model })
    v.seats = {}
    function v:getSeat(p) return self.seats[p] or -1 end
    function v:getScript() return { getPassenger = function(_, i) return { getId = function() return seats[i + 1] end } end } end
    return v
end
local m3, mx = car("Model3", { "FrontLeft", "FrontRight", "RearLeft", "RearRight" }), car("ModelX", { "FrontLeft" })
local van = H.vehicle({ script = "Base.CarNormal" })
local p = wearer("hatter")
local function sit(v, s) p.vehicle = v; if v and v.seats then v.seats[p] = s end end
local function on() return p.worn[LOC] ~= nil end

-- SP (no server, no sends): the local players get the minute check
H.side(false, false)
local savedNum, savedSpecific = getNumActivePlayers, getSpecificPlayer
function getNumActivePlayers() return 1 end
function getSpecificPlayer(i) return i == 0 and p or nil end
p.worn[HAT] = hatItem("Hat_Stovepipe")
sit(m3, 0)
local ticks = H.count("OnTick")
MinidoracatTesla.ServerCommands.seat(p, {})
check(on() and #p.items == 1 and p.worn[LOC] == p.items[1] and p.items[1].type == Hd.TYPE,
    "top hat in the Model 3 driver's seat (seat command): the hider is added and worn")
check(H.count("OnTick") == ticks, "SP: no look-again (the seat is already the new one)")
Hd.sync(p, false)
check(#p.items == 1, "asked again: nothing changes")
local stray = { type = Hd.TYPE }
p.items[#p.items + 1] = stray
Hd.sync(p, false)
check(#p.items == 1 and p.items[1] == p.worn[LOC] and p.worn[LOC] ~= stray,
    "an unworn copy (item add and worn sync crossed) goes, the worn one stays")
p.worn[LOC] = nil
Hd.sync(p, false)
check(#p.items == 1 and p.worn[LOC] == p.items[1],
    "the worn list lost it (a client's clothing sync), the copy in the inventory is worn again, no second one")
p.worn[HAT] = hatItem("Hat_BaseballCap")
H.fire("EveryOneMinute")
check(not on() and #p.items == 0, "SP: the game-minute check takes it off for a cap and out of the inventory")
p.worn[HAT] = hatItem("Hat_Stovepipe")
sit(mx, 0)
Hd.sync(p)
check(not on(), "Model X front seat: the top hat fits, no hider")
p.worn[HAT], p.worn[FULL] = nil, hatItem("Hat_Spiffo")
sit(m3, 2)
Hd.sync(p)
check(on(), "a Spiffo head (base:fullhat) in the Model 3 rear: hider on")
sit(van, 0)
Hd.sync(p)
check(not on() and #p.items == 0, "in a vanilla car: off")
sit(m3, 2)
Hd.sync(p)
sit(nil)
Hd.sync(p)
check(not on(), "got out: off")
sit(m3, 2)
Hd.sync(p)
p._class = "IsoPlayer"
H.fire("OnCharacterDeath", p)
check(not on() and #p.items == 0, "death takes it off however the character still reads as seated")

-- MP server: sends to the owner, and the minute check covers every online player
getNumActivePlayers, getSpecificPlayer = savedNum, savedSpecific
local q = wearer("other")
q.worn[HAT], q.vehicle = hatItem("Hat_Stovepipe"), m3
m3.seats[q] = 1
function getOnlinePlayers() return { size = function() return 1 end, get = function() return q end } end
H.side(false, true)
H.fire("EveryOneMinute")
check(q.worn[LOC] ~= nil and sent.add == 1,
    "MP server: the game-minute check puts it on an online player who sat without a command, and sends the item")
q.vehicle = nil
H.fire("EveryOneMinute")
check(q.worn[LOC] == nil and sent.rem == 1, "MP server: off after the exit, the removal sent")

-- MP server: the exit's command handled before the exit packet (RELIABLE vs RELIABLE_ORDERED): AGAIN_MS later.
-- The relay to the clients near (Liftgate.sendNear, not loaded yet here) is test_seat_pose's.
local savedById, savedLiftgate = getPlayerByOnlineID, MinidoracatTesla.Liftgate
MinidoracatTesla.Liftgate = savedLiftgate or { sendNear = function() end }
local gone = false
function getPlayerByOnlineID(id) return not gone and id == q:getOnlineID() and q or nil end
q.vehicle = m3
H.fire("EveryOneMinute")
ticks = H.count("OnTick")
MinidoracatTesla.ServerCommands.seat(q, {})
check(q.worn[LOC] ~= nil and H.count("OnTick") == ticks + 1,
    "MP server: a command while the server still has them seated keeps the hider, a look-again OnTick is added")
MinidoracatTesla.ServerCommands.seat(q, {})
check(H.count("OnTick") == ticks + 1, "a second command: still one OnTick")
q.vehicle = nil
H.fire("OnTick")
check(q.worn[LOC] ~= nil, "before AGAIN_MS: not looked at yet")
H.advanceMs(Hd.AGAIN_MS)
H.fire("OnTick")
check(q.worn[LOC] == nil and H.count("OnTick") == ticks, "AGAIN_MS later the exit has applied: off, the OnTick removed")
MinidoracatTesla.ServerCommands.seat(q, {})
q.vehicle = m3 -- seated again with the top hat: a kept IsoPlayer reference would put the hider on
gone = true
H.advanceMs(Hd.AGAIN_MS)
H.fire("OnTick")
check(q.worn[LOC] == nil and H.count("OnTick") == ticks,
    "a player gone by then is skipped (looked up by id, no kept reference), the OnTick removed")
gone = false
MinidoracatTesla.ServerCommands.seat(q, {})
check(q.worn[LOC] ~= nil, "seated with the top hat: the command puts it on")
q.vehicle = nil
H.advanceMs(-2 * Hd.AGAIN_MS)
H.fire("OnTick")
check(q.worn[LOC] == nil and H.count("OnTick") == ticks,
    "the clock set back: looked at on the next tick instead of waiting, the OnTick removed")
H.advanceMs(2 * Hd.AGAIN_MS)

getPlayerByOnlineID = savedById
MinidoracatTesla.Liftgate = savedLiftgate
getOnlinePlayers = nil
sendAddItemToContainer, sendRemoveItemFromContainer = savedSend.add, savedSend.rem
-- the other tests' fake players wear nothing: unhook this module's minute and death handlers
Events.EveryOneMinute.Remove(Hd.minute)
Events.OnCharacterDeath.Remove(Hd.onDeath)
