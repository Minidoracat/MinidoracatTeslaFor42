-- Tesla HUD (client): vanilla dashboard hand-over, hudRect contract, zero-allocation redraw, read model, radial menu.
-- Engine-only behaviour (real drawing, focus, screenshots) is covered by E2E hud-sp / hud-mp.
local check = H.check

-- ---------------------------------------------------------------- client fakes (only what HUD*.lua touches)
H.side(true, false)
local SCREEN_W, SCREEN_H = 1920, 1080
function getPlayerScreenLeft() return 0 end
function getPlayerScreenTop() return 0 end
function getPlayerScreenWidth() return SCREEN_W end
function getPlayerScreenHeight() return SCREEN_H end
UIFont = { Small = "Small", Medium = "Medium", Large = "Large" }
local fontH = 19
function getTextManager()
    return { getFontHeight = function() return fontH end, MeasureStringX = function(_, _, s) return #s * 8 end }
end
function getTexture(path) return { path = path } end
BaseVehicle = { getFakeSpeedModifier = function() return 1.0 end }
local sounds = {}
function getSpecificPlayer() return { playSound = function(_, s) sounds[#sounds + 1] = s end } end
HaloTextHelper = { addBadText = function() end }
UIManager = { getSpeedControls = function() return { getCurrentGameSpeed = function() return 1 end } end }

local drawCalls = 0
ISUIElement = {}
ISUIElement.__index = ISUIElement
function ISUIElement:derive(name) local t = { Type = name }; setmetatable(t, { __index = self }); t.__index = t; return t end
function ISUIElement:new(x, y, w, h)
    local o = { x = x, y = y, width = w, height = h, visible = true }
    setmetatable(o, self); self.__index = self
    return o
end
function ISUIElement:initialise() end
function ISUIElement:instantiate()
    self.javaObject = {
        DrawSubTextureRGBA = function() drawCalls = drawCalls + 1 end,
        DrawText = function(_, font, text, x, y)
            drawCalls = drawCalls + 1
            lastText = text
            if type(x) ~= "number" or type(y) ~= "number" then badText = (badText or 0) + 1 end -- Java NPEs on nil
        end,
    }
end
function ISUIElement:setWidth(w) self.width = w end
function ISUIElement:setHeight(h) self.height = h end
function ISUIElement:setX(x) self.x = x end
function ISUIElement:setY(y) self.y = y end
function ISUIElement:setVisible(v) self.visible = v end
function ISUIElement:isVisible() return self.visible end
function ISUIElement:addToUIManager() self.inManager = true end
function ISUIElement:removeFromUIManager() self.inManager = false end

-- vanilla dashboard: setVehicle mirrors ISVehicleDashboard.lua:180-229 (visible + add, or remove)
ISVehicleDashboard = ISUIElement:derive("ISVehicleDashboard")
function ISVehicleDashboard:setVehicle(vehicle)
    self.vehicle = vehicle
    if not vehicle then self:removeFromUIManager(); return end
    self:setVisible(true)
    self:addToUIManager()
end
H.stub("ISUI/ISUIElement")
H.stub("Vehicles/ISUI/ISVehicleDashboard")

-- radial menu: vanilla toggles (ISVehicleMenu.lua:67-76) and adds its own "Sleep" slice (:225)
local menu = { slices = {}, open = false }
function menu:isReallyVisible() return self.open end
function menu:addSlice(text, tex, fn, a1, a2)
    self.slices[#self.slices + 1] = { text = text, fn = fn, a1 = a1, a2 = a2, command = { fn, a1, a2 } }
end
function menu:setSliceText(i, text) self.slices[i].text = text end -- ISRadialMenu.lua:55
function getPlayerRadialMenu() return menu end
ISVehicleMenu = { onSleep = function() end }
ISVehicleMenu.showRadialMenu = function()
    if menu.open then menu.open = false; menu.slices = {}; return end
    menu.slices = {}; menu:addSlice("vanilla"); menu:addSlice("Sleep", nil, ISVehicleMenu.onSleep); menu.open = true
end
H.stub("Vehicles/ISUI/ISVehicleMenu")
ISWorldObjectContextMenu = { getBedQuality = function() return "badBed" end } -- vanilla: any car seat (ISWorldObjectContextMenu.lua:2923-2934)
H.stub("ISUI/ISWorldObjectContextMenu")

require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/HUD"
require "MinidoracatTesla/HUDRadial"
local T = MinidoracatTesla
local HUD = T.HUD

-- vehicle fake on top of H.vehicle (doors, transmission, throttle)
local function car(o)
    local v = H.vehicle(o)
    v.gear, v.throttle, v.lights, v.locked = 0, 0, false, false
    for _, id in ipairs({ "DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight", "TrunkDoor" }) do
        local d = { open = false }
        function d:isOpen() return self.open end
        v.parts[id] = { door = d, getDoor = function(self) return self.door end, getModData = function() return {} end,
            getInventoryItem = function() return {} end }
    end
    function v:getTransmissionNumber() return self.gear end
    function v:getThrottle() return self.throttle end
    function v:getHeadlightsOn() return self.lights end
    function v:areAllDoorsLocked() return self.locked end
    function v:isStarting() return false end
    function v:isHotwired() return false end
    return v
end

-- ---------------------------------------------------------------- hand-over
H.section("dashboard hand-over")
local dash = ISVehicleDashboard:new(0, 0, 552, 121)
dash.playerNum = 0
local _, _, _, _, vis0 = MinidoracatTeslaAPI.hudRect(0)
check(vis0 == false, "hudRect: no HUD yet -> visible=false")

local tesla = car({ kwh = 31.25 })
dash:setVehicle(tesla)
local h = HUD.get(0)
check(dash.inManager == true and dash.visible == false, "tesla: vanilla stays in UIManager but invisible")
check(h.inManager == true and h.vehicle == tesla, "tesla: HUD shown and attached")
local x, y, w, hh, vis = MinidoracatTeslaAPI.hudRect(0)
check(vis == true and w == 552 and y + hh == SCREEN_H and x == (SCREEN_W - 552) / 2,
    "hudRect: 552 wide at S=1, bottom-centre of the player screen")

dash:removeFromUIManager() -- joypad inventory opens (ISInventoryPage.lua:774)
check(h.inManager == false and select(5, MinidoracatTeslaAPI.hudRect(0)) == false, "joypad inventory: HUD hidden, hudRect not visible")
dash:addToUIManager() -- and closes (:759)
check(h.inManager == true and dash.visible == false, "joypad inventory closed: HUD back, vanilla still hidden")

local gas = car({ script = "Base.CarNormal" })
dash:setVehicle(gas)
check(dash.visible == true and h.inManager == false, "normal car: vanilla visible, HUD hidden")
dash:setVehicle(nil)
dash:setVehicle(nil) -- damageChecker calls this every tick on foot
check(h.inManager == false and h.vehicle == nil, "on foot: HUD stays hidden (repeated nil is harmless)")

-- split screen (4 players at 1280x720 = 640 wide) and big fonts: the strip shrinks to fit its quarter
SCREEN_W, fontH = 640, 33
dash:setVehicle(tesla)
local xq, _, wq, _, visq = MinidoracatTeslaAPI.hudRect(0)
check(visq and wq <= 632 and xq >= 0 and xq + wq <= 640, "640 px wide split view at font 4x: fits (" .. wq .. " px)")
SCREEN_W, fontH = 1920, 19
dash:setVehicle(nil)

-- ---------------------------------------------------------------- read model
H.section("read model")
dash:setVehicle(tesla)
check(h.st.gear == 1 and h.st.kmh == 0 and h.st.pct == 50, "parked: P, 0 km/h, 50%")
tesla.running, tesla.gear, tesla.throttle, tesla.speed = true, 1, 0.6, 40
h:update()
check(h.st.gear == 4 and h.st.use == 6 and h.st.kmh == 40, "driving: D, throttle 0.6 -> use 6, 40 km/h")
check(sounds[#sounds] == "VehicleInsertIgnitionKey", "ignition sound kept from vanilla prerender")
tesla.gear, tesla.throttle, tesla.speed = 0, 0, 39.5
h:update()
check(h.st.gear == 4 and h.st.regen == 5 and h.st.use == 0, "coasting in N: still D, 0.5 km/h per 0.1 s -> regen 5")
tesla.speed = 0
h:update()
h:update()
check(h.st.gear == 3, "standing with motor on in N: N")
tesla.parts.DoorFrontLeft.door.open = true
h:update(); h:update(); h:update()
check(h.st.doors == 1 and h.msgId == 1 and h.msgH > 0, "open door: bit set, door pill on")
local _, y2, _, h2 = MinidoracatTeslaAPI.hudRect(0)
check(h2 > hh and y2 + h2 == SCREEN_H, "pill grows the HUD upward; bottom stays at the screen bottom")
-- getting in with an alert already up: the engine can call prerender before the first update()
-- (a fresh HUD: player 1's first seat-in, no earlier build to reuse)
local dash1 = ISVehicleDashboard:new(0, 0, 552, 121)
dash1.playerNum = 1
badText = 0
dash1:setVehicle(tesla)
local h1 = HUD.get(1)
h1:prerender()
check(h1.msgTitle ~= nil and badText == 0 and h1.n > 0, "first prerender after seating: quads built, pill text has a position")
dash1:setVehicle(nil)
tesla.parts.DoorFrontLeft.door.open = false

-- ---------------------------------------------------------------- charge projection
H.section("charge projection")
local part = T.Battery.part(tesla)
local chg = { kw = 10, last = H.hours() - 0.5, added = 1, target = 60 }
local kwh, added, hours = HUD.chargeEstimate(part, chg, H.hours())
check(H.near(kwh, 36.25) and H.near(added, 6) and H.near(hours, (37.5 - 36.25) / 10), "kw * (now - last) added on top of the synced kWh")
chg.last = H.hours() - 5
kwh = HUD.chargeEstimate(part, chg, H.hours())
check(H.near(kwh, 37.5), "projection capped at the target")
chg.paused = "nopower"
kwh = HUD.chargeEstimate(part, chg, H.hours())
check(H.near(kwh, 31.25), "paused: no projection")
part:getModData().chg = { kw = 11.5, last = H.hours(), added = 0, target = 90 }
h:update(); h:update(); h:update()
check(h.st.chg == 1 and h.msgId == 4, "charging state and pill")
part:getModData().chg = nil

-- ---------------------------------------------------------------- redraw cost
H.section("redraw")
h:update(); h:update(); h:update()
local quads = h.n / 12
drawCalls = 0
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 1000 do h:prerender() end
local grew = collectgarbage("count") - before
collectgarbage("restart")
check(grew == 0, "prerender x1000 allocates nothing (" .. grew .. " KB)")
check(drawCalls == 1000 * quads, "prerender: one draw call per cached quad, no text without a pill (" .. quads .. " quads)")
check(quads <= 60, "quad budget <= 60 (" .. quads .. ")")
local n0 = h.n
h:update()
check(h.n == n0, "no state change: list not rebuilt into a different size")

-- ---------------------------------------------------------------- hover help (render)
H.section("hover help")
local mx, my
local function hoverAt(el) -- the E2E trick: instance methods instead of the engine mouse
    el.isMouseOver = function() return mx ~= nil end
    el.getMouseX = function() return mx end
    el.getMouseY = function() return my end
    el.getAbsoluteX = function(self) return self.x end
    el.getAbsoluteY = function(self) return self.y end
end
hoverAt(h)
drawCalls = 0
h:render()
check(drawCalls == 0, "no hover: render draws nothing")
local function tipOk(el, i)
    local ax = el.keyX + (i - 1) * el.keyStep
    mx, my = ax + el.keyS / 2, el.keyY + el.keyS / 2
    el:render()
    local r = el.tipRect
    local over = r.x < ax + el.keyS and r.x + r.w > ax and r.y < el.keyY + el.keyS and r.y + r.h > el.keyY
    return not over and el.x + r.x >= 0 and el.x + r.x + r.w <= SCREEN_W and el.y + r.y >= 0
end
local allOk = true
for i = 1, 5 do allOk = allOk and tipOk(h, i) end
check(allOk, "each of the 5 keys: tip on screen and not over the key")
check(lastText == "IGUI_MinidoracatTesla_Tip_GateOpen", "liftgate closed: tip says open (" .. tostring(lastText) .. ")")
tesla.parts.TrunkDoor.door.open = true
h:update(); h:update(); h:update()
tipOk(h, 5)
check(h:keyOn(5) and lastText == "IGUI_MinidoracatTesla_Tip_GateClose", "liftgate open: key on, tip says close")
tesla.parts.TrunkDoor.door.open = false
h:update(); h:update(); h:update()
mx, my = h.keyX - 5, h.keyY + 2
drawCalls = 0
h:render()
check(drawCalls == 0, "mouse on the HUD but not on a key: no tip")
tipOk(h, 4)
collectgarbage("collect")
collectgarbage("stop")
h:render() -- the collect above frees Lua call frames; let the deeper render->drawTip->quad chain re-grow them first
before = collectgarbage("count")
for _ = 1, 1000 do h:render() end
grew = collectgarbage("count") - before
collectgarbage("restart")
check(grew == 0, "hovered render x1000 allocates nothing (" .. grew .. " KB)")
-- 640 px split view, big font: the last key sits near the right edge; the tip is pushed back inside
SCREEN_W, fontH = 640, 33
h:layout()
check(tipOk(h, 5) and tipOk(h, 1), "640 px split view at font 4x: tips stay inside the screen")
-- a translation wider than that view: two lines, still inside
local realGetText = getText
getText = function(key) return key:find("Tip_", 1, true) and string.rep("wide words ", 9) .. "end" or key end -- 102 chars, 816 px
h:layout()
local twoOk = tipOk(h, 1)
getText = realGetText
check(twoOk and h.tipText2 ~= nil and h.tipRect.w <= 640 - 8, "tip wider than the 640 px view: broken into two lines that fit")
getText = function(key) return key:find("Tip_", 1, true) and string.rep("\233\155\187", 40) or key end -- 40 CJK chars, no spaces
h:layout()
twoOk = tipOk(h, 1)
getText = realGetText
check(twoOk and h.tipText2 ~= nil and #h.tipText % 3 == 0 and #h.tipText2 % 3 == 0, "no spaces: split on a character boundary")
SCREEN_W, fontH = 1920, 19
h:layout()
mx = nil

-- ---------------------------------------------------------------- chargeCardRect (AutoDrive stacks its FSD card on it)
H.section("chargeCardRect")
ISPanelJoypad = ISUIElement:derive("ISPanelJoypad")
function ISPanelJoypad:instantiate() ISUIElement.instantiate(self); if self.createChildren then self:createChildren() end end
function ISPanelJoypad:update() end
function ISPanelJoypad:addChild() end
function ISPanelJoypad:insertNewLineOfButtons() end
function ISPanelJoypad:bringToTop() end
ISButton = ISUIElement:derive("ISButton")
function ISButton:new(x, y, w, hh, title)
    local o = ISUIElement.new(self, x, y, w, hh)
    o.title, o.enable = title, true
    return o
end
function ISButton:setTitle(t) self.title = t end
function ISButton:setEnable(e) self.enable = e end
JoypadState = { players = {} }
H.stub("ISUI/ISPanelJoypad")
H.stub("ISUI/ISButton")
require "MinidoracatTesla/HUDChargeCard"
local cardPlayer = { isDead = function() return false end, getVehicle = function() return tesla end,
    DistTo = function() return 0 end }
local realGetSpecific = getSpecificPlayer
getSpecificPlayer = function() return cardPlayer end
dash:setVehicle(tesla)
local _, _, _, _, cv0 = MinidoracatTeslaAPI.chargeCardRect(0)
check(cv0 == false and select(3, MinidoracatTeslaAPI.chargeCardRect(0)) == 0, "card not open: 0, 0, 0, 0, false")
local card = T.ChargeCard.open(0, tesla)
local function cardAboveHud()
    local cx, cy, cw, ch, cvis = MinidoracatTeslaAPI.chargeCardRect(0)
    local _, hy = MinidoracatTeslaAPI.hudRect(0)
    return cvis == true and cw > 0 and ch > 0 and cy + ch == hy - math.floor(8 * card.S)
        and cx == math.floor((SCREEN_W - cw) / 2), cy + ch
end
local ok1, bottom1 = cardAboveHud()
check(ok1, "card open: rect is the drawn card, centred, bottom 8*S above hudRect")
tesla.parts.DoorFrontLeft.door.open = true -- door pill: the HUD grows upward
h:update(); h:update(); h:update()
card:update()
local ok2, bottom2 = cardAboveHud()
check(ok2 and bottom2 < bottom1, "HUD grew (pill): card and its rect moved up with it (" .. bottom1 .. " -> " .. bottom2 .. ")")
tesla.parts.DoorFrontLeft.door.open = false
h:update(); h:update(); h:update()
card:update()
check((cardAboveHud()), "pill gone: card back down, still 8*S above the HUD")
card:setVisible(false) -- ESC / UI toggled off
local _, _, cw3, _, cv3 = MinidoracatTeslaAPI.chargeCardRect(0)
check(cw3 > 0 and cv3 == false, "UI hidden: rect kept, visible=false (like hudRect)")
card:setVisible(true)
collectgarbage("collect"); collectgarbage("stop")
MinidoracatTeslaAPI.chargeCardRect(0)
local kb = collectgarbage("count")
for _ = 1, 1000 do MinidoracatTeslaAPI.chargeCardRect(0) end
local cgrew = collectgarbage("count") - kb
collectgarbage("restart")
check(cgrew == 0, "chargeCardRect x1000 allocates nothing (" .. cgrew .. " KB)")
card:close()
check(select(5, MinidoracatTeslaAPI.chargeCardRect(0)) == false, "card closed: visible=false")
getSpecificPlayer = realGetSpecific

-- ---------------------------------------------------------------- radial menu
H.section("radial menu")
local p = H.player({ keys = { [tesla.keyId] = true } })
p.vehicle = tesla
p.getPlayerNum = function() return 0 end
tesla.running = false
ISVehicleMenu.showRadialMenu(p)
local camp, status
for _, s in ipairs(menu.slices) do
    if s.text == "IGUI_MinidoracatTesla_Radial_CampOn\nIGUI_MinidoracatTesla_HUD_CampSub" then camp = s end
    if s.text == "IGUI_MinidoracatTesla_Radial_ChargeStatus\nIGUI_MinidoracatTesla_Tip_ChargeStatus" then status = s end
end
check(camp ~= nil and camp.fn ~= nil and status ~= nil, "radial: camp (enabled) and charging status, each with a what-it-does line")
local sleep = menu.slices[2]
check(sleep.text == "Sleep\nTooltip_BedType" and sleep.fn == ISVehicleMenu.onSleep, "radial: vanilla Sleep slice gets the bed quality line")
check(ISWorldObjectContextMenu.getBedQuality(p, nil) == "badBed", "bed: not camping -> vanilla bad bed")
T.Battery.part(tesla):getModData().camp = { by = "x" }
p.getPrimaryHandItem = function() return nil end
p.getSecondaryHandItem = function() return nil end
tesla.getSeat = function() return 0 end
tesla.getPartForSeatContainer = function() return { getItemContainer = function() return { containsTag = function() return false end } end } end
check(ISWorldObjectContextMenu.getBedQuality(p, nil) == "averageBed", "bed: camping -> average bed (wrapped getBedQuality)")
T.Battery.part(tesla):getModData().camp = nil
ISVehicleMenu.showRadialMenu(p)
check(#menu.slices == 0, "radial: second press closes, nothing re-added")
tesla.running, tesla.speed = true, 30
ISVehicleMenu.showRadialMenu(p)
local grey
for _, s in ipairs(menu.slices) do
    if s.text:find("Radial_CampOn", 1, true) then grey = s end
end
check(grey ~= nil and grey.fn == nil and grey.text:find("\nIGUI_MinidoracatTesla_Deny_MOVING", 1, true) ~= nil,
    "radial: camp greyed with the deny reason while driving")
menu.open = false
H.side(false, true)
