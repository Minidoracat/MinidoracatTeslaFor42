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
MinidoracatTesla.ServerCommands.hatHide(p, {})
check(on() and #p.items == 1 and p.worn[LOC] == p.items[1] and p.items[1].type == Hd.TYPE,
    "top hat in the Model 3 driver's seat (hatHide command): the hider is added and worn")
Hd.sync(p)
check(#p.items == 1, "asked again: nothing changes")
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
getOnlinePlayers = nil
sendAddItemToContainer, sendRemoveItemFromContainer = savedSend.add, savedSend.rem
-- the other tests' fake players wear nothing: unhook this module's minute and death handlers
Events.EveryOneMinute.Remove(Hd.minute)
Events.OnCharacterDeath.Remove(Hd.onDeath)
