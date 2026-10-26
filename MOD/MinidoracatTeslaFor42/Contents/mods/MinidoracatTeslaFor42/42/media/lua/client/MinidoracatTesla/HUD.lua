-- Tesla-style dashboard strip. Replaces the vanilla ISVehicleDashboard while the local driver sits in a Tesla.
-- Design and sources: .claude/skills/tesla-dev/references/hud.md
--   update()    10 Hz (UIManager.java:515-520): reads the car into self.st, rebuilds the quad list only on change.
--   prerender() no game reads, no allocation: one atlas texture, one DrawSubTextureRGBA per quad, then <=2 texts.
--   render()    only while the mouse is over a quick key, the power key or a door on the car picture: highlight + help.
require "ISUI/ISUIElement"
require "Vehicles/ISUI/ISVehicleDashboard"
require "MinidoracatTesla/Core"
require "MinidoracatTesla/HUDAtlas"
require "MinidoracatTesla/Liftgate"

local T = MinidoracatTesla
local HUD = ISUIElement:derive("MinidoracatTeslaHUD")
T.HUD = HUD
local huds = {} -- [playerNum] = HUD

-- design units at S = 1 (font size 1x: Small = 19 px). Four quick keys right-aligned at R_EDGE; their left edge (312)
-- is where the car picture's clickable zones end, so the strip is exactly as wide as that needs (2026-10-26: the
-- liftgate key went, the car picture's tail opens the liftgate; 552 -> 506).
local W, PADX, R_EDGE = 506, 16, 490
local GEAR_X, GEAR_Y, SPD_Y = 33, 12, 36
local PM_X, PM_W, PM_H = 18, 4, 62
local CAR_X, CAR_Y = 172, 14
-- power key (2026-10-27): after the gear row, 8 left of the car picture, centred on the gear row; above the speed
-- digits (y >= 36), so the strip keeps its 506 width (AutoDrive's FSD card lines up with it)
local PWR_X, PWR_Y, PWR = 136, 5, 28
local KEY, KEY_GAP = 40, 6
local KEYS_Y = 60
local MSG_Y, MSG_H, MSG_MINW, MSG_MAXW = 108, 30, 312, 474
local H_NOMSG = 112
local LOW_PCT = 20
local DOORS = { "DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight", "TrunkDoor", "DoorRear", "EngineDoor" }
local DOOR_SPR = { "door_FL", "door_FR", "door_RL", "door_RR", "door_TR", "door_TR", "door_HD" }
local POW2 = { 1, 2, 4, 8, 16, 32, 64 }
-- clickable car picture: { DOORS index, x0, y0, x1, y1 } in design units from the car sprite's top-left (150x85, nose
-- right, left side up; build_atlas.py car_body at 150/170 px per viewBox unit). Rear doors end at the B-pillar seam
-- (x 69), the front doors and the frunk lid split the windscreen; x 140 is where the quick keys start.
local ZONES = {
    { 5, 0, 0, 45, 85 }, { 3, 45, 0, 69, 42.5 }, { 4, 45, 42.5, 69, 85 },
    { 1, 69, 0, 97, 42.5 }, { 2, 69, 42.5, 97, 85 }, { 7, 97, 0, 140, 85 },
}
local PART_KEY = {} -- vanilla part-name keys; the tip maps them through T.PartNames (Tesla names)
for i = 1, #DOORS do PART_KEY[i] = "IGUI_VehiclePart" .. DOORS[i] end

local function rgb(hex)
    return { tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255 }
end
local C = {
    bg = rgb("#121417"), surface = rgb("#1E2227"), track = rgb("#2E343B"), text = rgb("#F3F5F7"),
    text2 = rgb("#AEB6BF"), text3 = rgb("#8E98A3"), accent = rgb("#5B8CFF"), accentFill = rgb("#3E6AE1"),
    ok = rgb("#3DD68C"), warn = rgb("#F5B544"), danger = rgb("#FF6B6B"), red = rgb("#EC1C24"), white = { 1, 1, 1 },
}
HUD.C = C
-- digit sets as 0-based arrays (built once at load; the generated file stores flat names)
for _, A in pairs(T.HUDAtlas) do
    for _, set in ipairs({ "big", "mid", "sm" }) do
        local t = {}
        for d = 0, 9 do t[d] = A[set .. "_" .. d] end
        A[set] = t
    end
end
local GEARS = { "P", "R", "N", "D" }
local KEYS = { "headlight", "heater", "radio", "tent" }
local NKEYS = #KEYS
-- hover help per quick key (translation keys); camp depends on its state
local TIPS = { "IGUI_MinidoracatTesla_Tip_Headlight", "IGUI_MinidoracatTesla_Tip_Heater", "IGUI_MinidoracatTesla_Tip_Radio" }
local TIP_OPEN, TIP_CLOSE = "IGUI_MinidoracatTesla_Tip_DoorOpen", "IGUI_MinidoracatTesla_Tip_DoorClose" -- %1 = part name
local TIP_ON, TIP_OFF = "IGUI_MinidoracatTesla_Tip_PowerOn", "IGUI_MinidoracatTesla_Tip_PowerOff"

-- ---------------------------------------------------------------- quad list helpers
local function quad(self, sx, sy, sw, sh, x, y, w, h, c, a)
    local L, n = self.L, self.n
    L[n + 1] = sx; L[n + 2] = sy; L[n + 3] = sw; L[n + 4] = sh
    L[n + 5] = math.floor(x + 0.5); L[n + 6] = math.floor(y + 0.5); L[n + 7] = w; L[n + 8] = h
    L[n + 9] = c[1]; L[n + 10] = c[2]; L[n + 11] = c[3]; L[n + 12] = a
    self.n = n + 12
    return n + 12 -- index of the alpha slot (for pulses)
end
local function spr(self, e, x, y, c, a, scale)
    local f = self.f * (scale or 1)
    return quad(self, e[1], e[2], e[3], e[4], x + e[5] * f, y + e[6] * f, e[3] * f, e[4] * f, c, a or 1)
end
local function rect(self, x, y, w, h, c, a)
    local e = self.A.solid
    quad(self, e[1], e[2], e[3], e[4], x, y, w, h, c, a or 1)
end
local function rrect(self, x, y, w, h, r, c, a)
    local e = self.A.round
    local hx = e[3] / 2
    r = math.floor(r + 0.5); x = math.floor(x + 0.5); y = math.floor(y + 0.5)
    w = math.floor(w + 0.5); h = math.floor(h + 0.5)
    quad(self, e[1], e[2], hx, hx, x, y, r, r, c, a)
    quad(self, e[1] + hx, e[2], hx, hx, x + w - r, y, r, r, c, a)
    quad(self, e[1], e[2] + hx, hx, hx, x, y + h - r, r, r, c, a)
    quad(self, e[1] + hx, e[2] + hx, hx, hx, x + w - r, y + h - r, r, r, c, a)
    rect(self, x + r, y, w - 2 * r, r, c, a)
    rect(self, x, y + r, w, h - 2 * r, c, a)
    rect(self, x + r, y + h - r, w - 2 * r, r, c, a)
end
local function pill(self, x, y, w, h, c, a)
    local e = self.A.round
    local hx = e[3] / 2
    local r = math.floor(h / 2 + 0.5)
    quad(self, e[1], e[2], hx, e[4], x, y, r, h, c, a)
    rect(self, x + r, y, w - 2 * r, h, c, a)
    quad(self, e[1] + hx, e[2], hx, e[4], x + w - r, y, r, h, c, a)
end
-- digits of a non-negative integer, left to right from x; returns the end x
local function digits(self, set, value, x, y, c, a)
    local f = self.f
    local adv = set[0][7] * f
    local div = 1
    while div * 10 <= value do div = div * 10 end
    while div >= 1 do
        local d = math.floor(value / div) % 10
        spr(self, set[d], x, y, c, a)
        x = x + adv
        div = div / 10
    end
    return x
end
local function digitsWidth(self, set, value)
    local n = 1
    while value >= 10 do value = math.floor(value / 10); n = n + 1 end
    return n * set[0][7] * self.f
end
HUD.quad, HUD.spr, HUD.rect, HUD.rrect, HUD.pill = quad, spr, rect, rrect, pill

-- ---------------------------------------------------------------- hover help (HUD keys, charge card buttons)
-- One line in the dashboard style (UIFont.Small, scale S), centred above the anchor rect (element-local) and kept
-- inside this player's screen; below the anchor when there is no room above, so it never covers the anchor.
-- Wider than the player's screen (split view + big font): two lines, broken at the space nearest the middle.
-- The string is fetched and measured only when the key (or `arg`, a translation key for %1) changes (layout resets
-- el.tipKey); drawing allocates nothing.
-- `el` needs S, FH, A, f, tex, playerNum (the HUD and the card both have them).
local tipQ = { L = {}, n = 0 }
local function drawQ(el, q)
    local jo, tex, L = el.javaObject, el.tex, q.L
    for i = 1, q.n, 12 do
        jo:DrawSubTextureRGBA(tex, L[i], L[i + 1], L[i + 2], L[i + 3], L[i + 4], L[i + 5], L[i + 6], L[i + 7],
            L[i + 8], L[i + 9], L[i + 10], L[i + 11])
    end
end
function HUD.drawTip(el, key, ax, ay, aw, ah, arg)
    local S, pn = el.S, el.playerNum
    local padX, padY, gap = math.floor(10 * S), math.floor(5 * S), math.floor(6 * S)
    if key ~= el.tipKey or arg ~= el.tipArg then
        el.tipKey, el.tipArg = key, arg
        local tm, s = getTextManager(), arg and getText(key, getText(arg)) or getText(key)
        local tw = tm:MeasureStringX(UIFont.Small, s)
        el.tipText, el.tipText2 = s, nil
        if tw > getPlayerScreenWidth(pn) - 8 - 2 * padX then
            local mid, cut = #s / 2, nil
            local i = s:find(" ", 1, true)
            while i do
                if not cut or math.abs(i - mid) < math.abs(cut - mid) then cut = i end
                i = s:find(" ", i + 1, true)
            end
            if cut then
                el.tipText, el.tipText2 = s:sub(1, cut - 1), s:sub(cut + 1)
            else -- no spaces (CJK): split in the middle (Kahlua indexes UTF-16 chars; the byte step is for plain Lua)
                local j = math.max(2, math.floor(mid))
                while j > 2 and s:byte(j) >= 128 and s:byte(j) < 192 do j = j - 1 end
                el.tipText, el.tipText2 = s:sub(1, j - 1), s:sub(j)
            end
            tw = math.max(tm:MeasureStringX(UIFont.Small, el.tipText), tm:MeasureStringX(UIFont.Small, el.tipText2))
        end
        el.tipW = tw
    end
    local w, h = el.tipW + 2 * padX, (el.tipText2 and 2 or 1) * el.FH + 2 * padY
    local left = getPlayerScreenLeft(pn) - el:getAbsoluteX()
    local top = getPlayerScreenTop(pn) - el:getAbsoluteY()
    local x = math.max(left + 4, math.min(math.floor(ax + (aw - w) / 2), left + getPlayerScreenWidth(pn) - 4 - w))
    local y = ay - gap - h
    if y < top + 4 then y = ay + ah + gap end
    tipQ.A, tipQ.f, tipQ.n = el.A, el.f, 0
    rrect(tipQ, x, y, w, h, 8 * S, C.track, 0.97)
    drawQ(el, tipQ)
    local jo = el.javaObject
    local c = C.text
    jo:DrawText(UIFont.Small, el.tipText, x + padX, y + padY, c[1], c[2], c[3], 1)
    if el.tipText2 then jo:DrawText(UIFont.Small, el.tipText2, x + padX, y + padY + el.FH, c[1], c[2], c[3], 1) end
    el.tipRect = el.tipRect or {}
    el.tipRect.x, el.tipRect.y, el.tipRect.w, el.tipRect.h = x, y, w, h -- E2E and tests read where it went
end

-- ---------------------------------------------------------------- charge estimate (shared with the card)
-- Client-side projection between server settlements: kw * (now - last), capped at the target (architecture §4).
function HUD.chargeEstimate(part, chg, now)
    local cap = T.Battery.capacity(part)
    local kwh = T.Battery.kwh(part)
    local target = (chg.target or 100) * cap / 100
    local added = chg.added or 0
    if not chg.paused and chg.kw and chg.last and now > chg.last then
        local gain = math.min(chg.kw * (now - chg.last), math.max(0, target - kwh))
        kwh = kwh + gain
        added = added + gain
    end
    local hoursLeft = (chg.kw and chg.kw > 0) and math.max(0, target - kwh) / chg.kw or 0
    return kwh, added, hoursLeft, cap
end

-- ---------------------------------------------------------------- life cycle
function HUD:new(playerNum)
    local o = ISUIElement:new(0, 0, W, H_NOMSG)
    setmetatable(o, self)
    self.__index = self
    o.playerNum = playerNum
    o.anchorLeft, o.anchorTop = false, false
    o.L, o.n = {}, 0
    o.st = {}
    o.tick = 0
    o.msgH = 0
    return o
end

function HUD:attach(vehicle)
    self.vehicle = vehicle
    self.character = getSpecificPlayer(self.playerNum)
    self.battery = T.Battery.part(vehicle)
    self.heaterPart = vehicle:getPartById("Heater")
    self.radioPart = vehicle:getPartById("Radio")
    self.doors = {}
    for i = 1, #DOORS do
        local p = vehicle:getPartById(DOORS[i])
        if p and p:getDoor() then self.doors[#self.doors + 1] = { part = p, bit = POW2[i], spr = DOOR_SPR[i], name = DOORS[i] } end
    end
    self.fake = BaseVehicle.getFakeSpeedModifier() -- BaseVehicle.java:666; vanilla :256 multiplies the gauge too
    self.kmPerKwh = T.kmPerKwh(vehicle)
    local st = self.st
    for k in pairs(st) do st[k] = nil end
    self.tick = 0
    self.prevKmh = nil
    self:scale()
    self:readFast()
    self:readSlow()
    self:place()
    -- prerender can run before the first update(): the quad list and text positions must exist now
    self:build()
end

function HUD:show(vehicle)
    self:attach(vehicle)
    if not self.inUI then
        self:addToUIManager()
        self.inUI = true
    end
    self:setVisible(true)
end

function HUD:hide()
    self.vehicle = nil
    if self.inUI then
        self:removeFromUIManager()
        self.inUI = false
    end
end

function HUD.get(playerNum)
    local h = huds[playerNum]
    if not h then
        h = HUD:new(playerNum)
        h:initialise()
        h:instantiate()
        h:setVisible(false)
        huds[playerNum] = h
    end
    return h
end

-- ---------------------------------------------------------------- reading the car
function HUD:readFast()
    local v, st = self.vehicle, self.st
    local running = v:isEngineRunning()
    st.on = running
    local raw = math.abs(v:getCurrentSpeedKmHour()) * self.fake
    st.kmh = math.floor(raw + 0.5)
    local gear = 1
    if running and (st.chg or 0) == 0 then -- plugged in = Park (owner's manual, Shifting)
        -- -1 R, 0 N, >=1 D (TransmissionNumber.java). PZ drops to N while coasting; a Tesla stays in D.
        local t = v:getTransmissionNumber()
        gear = t < 0 and 2 or ((t == 0 and raw < 1) and 3 or 4)
    end
    st.gear = gear
    -- power meter, 0..10 each way: throttle (CarController.java:226-248) up, measured deceleration down
    local use, regen = 0, 0
    if running then
        local thr = v:getThrottle() -- BaseVehicle.java:11587
        local drop = (self.prevKmh or raw) - raw
        if thr > 0.02 then
            use = math.min(10, math.floor(thr * 10 + 0.5))
        elseif drop > 0.05 and raw > 3 then -- >= 0.5 km/h per second of slowing down
            regen = math.max(1, math.min(10, math.floor(drop * 10 + 0.5)))
        end
    end
    self.prevKmh = raw
    st.use, st.regen = use, regen
    st.lights = v:getHeadlightsOn()
    -- vanilla plays the ignition-key sounds from its prerender (ISVehicleDashboard.lua:313-327); keep them
    local keyOn = (v:isKeysInIgnition() or running or v:isStarting()) and not v:isHotwired()
    if keyOn ~= (self.wasKey or false) then
        self.wasKey = keyOn
        if self.character then self.character:playSound(keyOn and "VehicleInsertIgnitionKey" or "VehicleRemoveIgnitionKey") end
    end
end

function HUD:readSlow()
    local v, st, part = self.vehicle, self.st, self.battery
    local kwh = part and T.Battery.kwh(part) or 0
    st.pct = part and math.floor(T.Battery.pct(part) + 0.5) or 0
    st.range = math.floor(kwh * self.kmPerKwh + 0.5)
    st.locked = v:areAllDoorsLocked()
    local bits, avail = 0, 0 -- open doors; installed doors (a car-picture zone dims without one)
    for i = 1, #self.doors do
        local d = self.doors[i]
        if d.part:getDoor():isOpen() then bits = bits + d.bit end
        if d.part:getInventoryItem() then avail = avail + d.bit end
    end
    st.avail = avail
    st.doors = bits
    local hp = self.heaterPart
    st.heater = hp ~= nil and hp:getModData().active == true
    local rp = self.radioPart
    local dd = rp and rp:getDeviceData()
    st.radio = dd ~= nil and dd:getIsTurnedOn()
    local md = part and part:getModData()
    st.camp = md ~= nil and md.camp ~= nil
    st.sentry = md ~= nil and md.sentry ~= nil
    local chg = md and md.chg
    local cs, added, mins = 0, 0, 0
    if chg then
        if chg.paused == "full" then cs = 2
        elseif chg.paused then cs = 3
        else
            cs = 1
            local k2, add, hrs = HUD.chargeEstimate(part, chg, T.hours())
            st.pct = math.min(100, math.floor(T.Battery.pct(part) + (k2 - kwh) * 100 / math.max(1, T.Battery.capacity(part)) + 0.5))
            st.range = math.floor(k2 * self.kmPerKwh + 0.5)
            added = math.floor(add * self.kmPerKwh + 0.5)
            mins = math.floor(hrs * 60 + 0.5)
        end
        st.target = chg.target or 100
    end
    st.chg = cs
    -- message: priority door > no power > low battery > charging > charged > camp > sentry
    local id, a1, a2 = 0, 0, 0
    if bits > 0 then id, a1 = 1, bits
    elseif cs == 3 then id = 2
    elseif st.pct < LOW_PCT and cs == 0 then id, a1 = 3, st.range
    elseif cs == 1 then id, a1, a2 = 4, added, mins
    elseif cs == 2 then id, a1 = 5, st.target
    elseif st.camp then id = 6
    elseif st.sentry then id = 7
    end
    if id ~= self.msgId or a1 ~= self.msgA1 or a2 ~= self.msgA2 then
        self.msgId, self.msgA1, self.msgA2 = id, a1, a2
        self:setMessage()
    end
end

local function hmm(mins)
    local m = mins % 60
    return tostring(math.floor(mins / 60)) .. (m < 10 and ":0" or ":") .. tostring(m)
end

-- Only runs when the message or its numbers change: builds the strings, measures them, re-lays out.
function HUD:setMessage()
    local id, a1, a2 = self.msgId, self.msgA1, self.msgA2
    local title, sub, icon, color
    if id == 1 then
        local n, first = 0, nil
        for i = 1, #self.doors do
            local d = self.doors[i]
            if math.floor(a1 / d.bit) % 2 == 1 then n = n + 1; first = first or d.name end
        end
        local pk = "IGUI_VehiclePart" .. tostring(first)
        pk = (T.PartNames and T.PartNames[pk]) or pk -- Tesla part names (client/MinidoracatTesla/PartNames.lua): EngineDoor = frunk lid
        title = n == 1 and getText("IGUI_MinidoracatTesla_HUD_DoorOpen", getText(pk))
            or getText("IGUI_MinidoracatTesla_HUD_DoorsOpen", tostring(n))
        sub, icon, color = getText("IGUI_MinidoracatTesla_HUD_DoorOpenSub"), "i_warn", C.warn
    elseif id == 2 then
        title, sub, icon, color = getText("IGUI_MinidoracatTesla_HUD_NoPower"), getText("IGUI_MinidoracatTesla_HUD_NoPowerSub"), "i_warn", C.warn
    elseif id == 3 then
        title, sub, icon, color = getText("IGUI_MinidoracatTesla_HUD_LowBattery"),
            getText("IGUI_MinidoracatTesla_HUD_LowBatterySub", tostring(a1)), "i_warn", C.warn
    elseif id == 4 then
        title, sub, icon, color = getText("IGUI_MinidoracatTesla_HUD_Charging"),
            getText("IGUI_MinidoracatTesla_HUD_ChargingSub", tostring(a1), hmm(a2), tostring(self.st.target or 100)), "i_bolt", C.ok
    elseif id == 5 then
        title, sub, icon, color = getText("IGUI_MinidoracatTesla_HUD_Charged", tostring(a1)),
            getText("IGUI_MinidoracatTesla_HUD_ChargedSub"), "i_check", C.ok
    elseif id == 6 then
        title, sub, icon, color = getText("IGUI_MinidoracatTesla_HUD_Camp"), getText("IGUI_MinidoracatTesla_HUD_CampSub"), "i_tent", C.text2
    elseif id == 7 then
        title, sub, icon, color = getText("IGUI_MinidoracatTesla_HUD_Sentry"), getText("IGUI_MinidoracatTesla_HUD_SentrySub"), "i_ring", C.text2
    end
    self.msgTitle, self.msgSub, self.msgIcon, self.msgColor = title, sub, icon, color
    self:measureMessage()
end

function HUD:measureMessage()
    local oldH = self.msgH
    if not self.msgTitle then
        self.msgH = 0
    else
        local S, tm = self.S, getTextManager()
        local tw = tm:MeasureStringX(UIFont.Small, self.msgTitle)
        local sw = self.msgSub and tm:MeasureStringX(UIFont.Small, self.msgSub) or 0
        local lead = math.floor(14 * S + 18 * S + 8 * S) -- left pad + icon + gap
        local gap = math.floor(10 * S)
        local one = lead + tw + gap + sw + math.floor(16 * S)
        local maxW = math.min(math.floor(MSG_MAXW * S), self.width - math.floor(2 * PADX * S))
        local h1 = math.max(math.floor(MSG_H * S), self.FH + math.floor(10 * S))
        if one <= maxW then
            self.msgW, self.msgH, self.msgTwo = math.max(math.floor(MSG_MINW * S), one), h1, false
        else
            self.msgW = math.min(maxW, lead + math.max(tw, sw) + math.floor(16 * S))
            self.msgH, self.msgTwo = h1 + self.FH, true
        end
        self.msgTX = math.floor(PADX * S) + lead
        self.msgTX2 = self.msgTwo and self.msgTX or (self.msgTX + tw + gap)
    end
    if self.msgH ~= oldH then self:place() end
    self.dirty = true
end

-- ---------------------------------------------------------------- layout
function HUD:scale()
    self.FH = getTextManager():getFontHeight(UIFont.Small)
    local pn = self.playerNum
    -- vanilla new-UI scale (ISWidgetCraftLogicControl.lua:5); shrink to fit narrow split-screen views
    local S = math.min(self.FH / 19, (getPlayerScreenWidth(pn) - 8) / W)
    self.S = S
    local k = S >= 1.5 and 2 or 1
    self.A = T.HUDAtlas[k]
    self.tex = getTexture(self.A.tex)
    self.f = S / k
    self:setWidth(math.floor(W * S))
    self.tipKey = nil -- re-measure the hover help at the new scale
end

function HUD:layout()
    self:scale()
    self:measureMessage()
    self:place()
    self:build()
end

function HUD:place()
    local S, pn = self.S, self.playerNum
    local h = self.msgH > 0 and (math.floor(MSG_Y * S) + self.msgH + math.floor(12 * S)) or math.floor(H_NOMSG * S)
    self:setHeight(h)
    -- bottom centre of this player's screen, like vanilla (ISVehicleDashboard.lua:422-433)
    self:setX(getPlayerScreenLeft(pn) + math.floor((getPlayerScreenWidth(pn) - self.width) / 2))
    self:setY(getPlayerScreenTop(pn) + getPlayerScreenHeight(pn) - h)
    self.dirty = true
end

-- ---------------------------------------------------------------- build the quad list (state changes only)
function HUD:build()
    local S, A, st = self.S, self.A, self.st
    self.n = 0
    self.pulseIdx = nil
    local w, h = self.width, self.height
    rrect(self, 0, 0, w, h, 16 * S, C.bg, 0.94)

    -- gear row: current gear bold white, others regular grey
    local x = GEAR_X * S
    local gy = GEAR_Y * S
    for i = 1, 4 do
        local g = GEARS[i]
        local cur = st.gear == i
        local e = cur and A["smb_" .. g] or A["sm_" .. g]
        spr(self, e, x, gy, cur and C.text or C.text3, 1)
        x = x + A["sm_" .. g][7] * self.f + 9 * S
    end

    -- power meter: track, zero tick, white use up / green regen down
    local py, ph = SPD_Y * S, PM_H * S
    local mid = py + ph / 2
    local pw = math.max(2, PM_W * S)
    rrect(self, PM_X * S, py, pw, ph, pw / 2, C.track, 1)
    if st.use > 0 then rect(self, PM_X * S, mid - ph / 2 * st.use / 10, pw, ph / 2 * st.use / 10, C.text, 1) end
    if st.regen > 0 then rect(self, PM_X * S, mid, pw, ph / 2 * st.regen / 10, C.ok, 1) end
    rect(self, PM_X * S - 3 * S, mid, pw + 6 * S, math.max(1, S), C.text3, 1)

    -- speed + unit
    digits(self, A.big, st.kmh, GEAR_X * S - 2 * S, py + 2 * S, C.text, 1)
    spr(self, A.kmh, GEAR_X * S, py + 48 * S, C.text2, 1)

    -- car, open doors, charge indicator
    local cx, cy = CAR_X * S, CAR_Y * S
    spr(self, A.car, cx, cy, C.white, 1)
    for i = 1, #self.doors do
        local d = self.doors[i]
        if math.floor(st.doors / d.bit) % 2 == 1 then spr(self, A[d.spr], cx, cy, C.warn, 1) end
    end
    for i = 1, #ZONES do -- door removed: its zone darkened, not clickable
        local z = ZONES[i]
        if math.floor(st.avail / POW2[z[1]]) % 2 == 0 then
            rect(self, cx + z[2] * S, cy + z[3] * S, (z[4] - z[2]) * S, (z[5] - z[3]) * S, C.bg, 0.6)
        end
    end
    if st.chg > 0 then
        local col = st.chg == 3 and C.accent or C.ok
        local idx = spr(self, A.i_bolt, cx + 2 * S, cy - 4 * S, col, 1)
        if st.chg == 1 then self.pulseIdx = idx end
    end

    -- right column: lock / tent / sentry / pct / cell
    local R = R_EDGE * S
    local ry = GEAR_Y * S
    local cell = A.cell
    local cw = cell[3] * self.f
    local cellX = R - cw
    spr(self, cell, cellX, ry + 4 * S, C.text2, 1)
    local fillW = 17.2 * S * st.pct / 100
    if fillW > 0 then rect(self, cellX + 2.4 * S, ry + 4 * S + 2.4 * S, fillW, 7.2 * S, st.chg == 1 and C.ok or C.text, 1) end
    local pctW = digitsWidth(self, A.mid, st.pct) + A.mid_pct[7] * self.f
    x = cellX - 6 * S - pctW
    x = digits(self, A.mid, st.pct, x, ry + 2 * S, C.text, 1)
    spr(self, A.mid_pct, x, ry + 2 * S, C.text, 1)
    x = cellX - 6 * S - pctW - 10 * S
    local icon = 18 * S
    if st.sentry then
        x = x - icon
        spr(self, A.i_ring, x, ry + 1 * S, C.text2, 1)
        spr(self, A.i_dot, x, ry + 1 * S, C.red, 1)
        x = x - 8 * S
    end
    if st.camp then
        x = x - icon
        spr(self, A.i_tent, x, ry + 1 * S, C.accent, 1)
        x = x - 8 * S
    end
    x = x - icon
    if st.locked then spr(self, A.i_lock, x, ry + 1 * S, C.text2, 1) else spr(self, A.i_unlock, x, ry + 1 * S, C.text3, 1) end

    -- range
    local kmW = A.km[3] * self.f
    local rx = R - kmW - digitsWidth(self, A.sm, st.range) - 4 * S
    digits(self, A.sm, st.range, rx, SPD_Y * S, C.text2, 1)
    spr(self, A.km, R - kmW, SPD_Y * S, C.text2, 1)

    -- power key: same look as the quick keys, smaller (icon blue + underline while on)
    local ps = PWR * S
    local pwx, pwy = PWR_X * S, PWR_Y * S
    self.pwrX, self.pwrY, self.pwrS = pwx, pwy, ps
    rrect(self, pwx, pwy, ps, ps, 7 * S, C.surface, 1)
    spr(self, A.i_power, pwx + 5 * S, pwy + 4 * S, st.on and C.accent or C.text2, 1)
    if st.on then rect(self, pwx + 8 * S, pwy + 24 * S, 12 * S, math.max(1, 2 * S), C.accent, 1) end

    -- quick keys: icon turns blue and gets an underline when on
    local ks = KEY * S
    local kx = R - (NKEYS * KEY + (NKEYS - 1) * KEY_GAP) * S
    local ky = KEYS_Y * S
    self.keyX, self.keyY, self.keyStep, self.keyS = kx, ky, (KEY + KEY_GAP) * S, ks
    for i = 1, NKEYS do
        local on = self:keyOn(i)
        spr(self, A.keybg, kx, ky, C.surface, 1)
        spr(self, A["i_" .. KEYS[i]], kx + 11 * S, ky + 10 * S, on and C.accent or C.text2, 1)
        if on then rect(self, kx + 12 * S, ky + 33 * S, 16 * S, math.max(1, 2 * S), C.accent, 1) end
        kx = kx + (KEY + KEY_GAP) * S
    end

    -- alert pill
    if self.msgTitle then
        local my = MSG_Y * S
        pill(self, PADX * S, my, self.msgW, self.msgH, C.surface, 1)
        local iy = self.msgTwo and (my + 6 * S) or (my + (self.msgH - 18 * S) / 2)
        spr(self, A[self.msgIcon], PADX * S + 14 * S, iy, self.msgColor, 1)
        self.msgTY = math.floor(self.msgTwo and (my + 5 * S) or (my + (self.msgH - self.FH) / 2))
        self.msgTY2 = self.msgTwo and (self.msgTY + self.FH) or self.msgTY
    end
    self.dirty = false
end

-- ---------------------------------------------------------------- UI callbacks
function HUD:update()
    local v = self.vehicle
    if not v then return end
    local st = self.st
    local kmh, gear, use, regen, lights, on = st.kmh, st.gear, st.use, st.regen, st.lights, st.on
    self:readFast()
    local changed = kmh ~= st.kmh or gear ~= st.gear or use ~= st.use or regen ~= st.regen or lights ~= st.lights
        or on ~= st.on
    self.tick = self.tick + 1
    if self.tick % 3 == 0 then
        local pct, range, locked, doors, avail, heater, radio, camp, sentry, chg =
            st.pct, st.range, st.locked, st.doors, st.avail, st.heater, st.radio, st.camp, st.sentry, st.chg
        self:readSlow()
        changed = changed or pct ~= st.pct or range ~= st.range or locked ~= st.locked or doors ~= st.doors
            or avail ~= st.avail or heater ~= st.heater or radio ~= st.radio or camp ~= st.camp or sentry ~= st.sentry
            or chg ~= st.chg
    end
    if changed or self.dirty then self:build() end
    if self.pulseIdx then -- charging: slow green pulse (owner's manual charge-port light), 10 Hz steps
        self.L[self.pulseIdx] = 0.55 + 0.45 * math.abs(math.sin(getTimestampMs() / 600))
    end
end

function HUD:prerender()
    local jo, tex, L = self.javaObject, self.tex, self.L
    for i = 1, self.n, 12 do
        jo:DrawSubTextureRGBA(tex, L[i], L[i + 1], L[i + 2], L[i + 3], L[i + 4], L[i + 5], L[i + 6], L[i + 7],
            L[i + 8], L[i + 9], L[i + 10], L[i + 11])
    end
    local t = self.msgTitle
    if t then
        local c, c2 = C.text, C.text2
        jo:DrawText(UIFont.Small, t, self.msgTX, self.msgTY, c[1], c[2], c[3], 1)
        if self.msgSub then jo:DrawText(UIFont.Small, self.msgSub, self.msgTX2, self.msgTY2, c2[1], c2[2], c2[3], 1) end
    end
end

-- hover help over a quick key or a door zone of the car picture (render runs every UI redraw; the hit tests are a few
-- comparisons); a door zone is also highlighted: tinted, its door drawn swung out in accent
function HUD:render()
    if not self.keyX or not self:isMouseOver() then return end
    local mx, my = self:getMouseX(), self:getMouseY()
    local i = self:keyAt(mx, my)
    if i then
        local key = TIPS[i]
        if i == 4 then key = self.st.camp and "IGUI_MinidoracatTesla_Radial_CampOff" or "IGUI_MinidoracatTesla_Tip_Camp" end
        return HUD.drawTip(self, key, self.keyX + (i - 1) * self.keyStep, self.keyY, self.keyS, self.keyS)
    end
    if self:powerAt(mx, my) then
        return HUD.drawTip(self, self.st.on and TIP_OFF or TIP_ON, self.pwrX, self.pwrY, self.pwrS, self.pwrS)
    end
    local z = self:zoneAt(mx, my)
    if not z then return end
    local S = self.S
    local cx, cy = CAR_X * S, CAR_Y * S
    local zx, zy, zw, zh = cx + z[2] * S, cy + z[3] * S, (z[4] - z[2]) * S, (z[5] - z[3]) * S
    tipQ.A, tipQ.f, tipQ.n = self.A, self.f, 0
    rrect(tipQ, zx, zy, zw, zh, 6 * S, C.accent, 0.18)
    spr(tipQ, self.A[DOOR_SPR[z[1]]], cx, cy, C.accent, 1)
    drawQ(self, tipQ)
    self:doorTip(z[1], zx, zy, zw, zh)
end

-- "Open / Close <Tesla part name>" for DOORS[k]
function HUD:doorTip(k, ax, ay, aw, ah)
    local open = math.floor(self.st.doors / POW2[k]) % 2 == 1
    local name = PART_KEY[k]
    HUD.drawTip(self, open and TIP_CLOSE or TIP_OPEN, ax, ay, aw, ah, T.PartNames and T.PartNames[name] or name)
end

function HUD:keyOn(i)
    local st = self.st
    if i == 1 then return st.lights end
    if i == 2 then return st.heater end
    if i == 3 then return st.radio end
    return st.camp
end

-- quick keys are clickable like the vanilla dashboard icons; everything else lets clicks through
function HUD:keyAt(x, y)
    if not self.keyX or y < self.keyY or y > self.keyY + self.keyS then return nil end
    local i = math.floor((x - self.keyX) / self.keyStep) + 1
    if i < 1 or i > NKEYS or x > self.keyX + (i - 1) * self.keyStep + self.keyS then return nil end
    return i
end

-- car picture: the ZONES entry under (x, y), nil when that door is not installed (the click goes through)
function HUD:zoneAt(x, y)
    if not self.keyX then return nil end
    local lx, ly = x / self.S - CAR_X, y / self.S - CAR_Y
    for i = 1, #ZONES do
        local z = ZONES[i]
        if lx >= z[2] and lx < z[4] and ly >= z[3] and ly < z[5] then
            return math.floor(self.st.avail / POW2[z[1]]) % 2 == 1 and z or nil
        end
    end
    return nil
end

function HUD:powerAt(x, y)
    return self.pwrX ~= nil and x >= self.pwrX and x <= self.pwrX + self.pwrS and y >= self.pwrY and y <= self.pwrY + self.pwrS
end

function HUD:onMouseDown(x, y)
    return self:keyAt(x, y) ~= nil or self:powerAt(x, y) or self:zoneAt(x, y) ~= nil
end

function HUD:onMouseUp(x, y)
    local p, v = self.character, self.vehicle
    if not p or not v then return false end
    local i = self:keyAt(x, y)
    if not i then
        if self:powerAt(x, y) then
            HUD.togglePower(p, v)
            return true
        end
        local z = self:zoneAt(x, y)
        if not z then return false end
        T.Liftgate.toggle(p, v, DOORS[z[1]])
        return true
    end
    if i == 1 then ISVehicleMenu.onToggleHeadlights(p)          -- ISVehicleMenu.lua:1114
    elseif i == 2 then ISVehicleMenu.onToggleHeater(p)          -- ISVehicleMenu.lua:1133
    elseif i == 3 then
        local rp = self.radioPart
        if rp and rp:getDeviceData() and rp:getInventoryItem() then ISVehicleMenu.onSignalDevice(p, rp) end -- :151-157
    else T.HUD.toggleCamp(p, v)
    end
    return true
end

-- camp toggle shared by the quick key and the radial menu (rules: shared/MinidoracatTesla/ParkModes.lua)
function HUD.toggleCamp(player, vehicle)
    local Camp = T.Camp
    local part = T.Battery.part(vehicle)
    local on = part and part:getModData().camp ~= nil
    local ok, why
    if Camp and Camp.canEnable then
        if on then ok, why = Camp.canDisable(player, vehicle) else ok, why = Camp.canEnable(player, vehicle) end
    else
        ok = true
    end
    if not ok then
        if why then HaloTextHelper.addBadText(player, T.denyText(why)) end -- HaloTextHelper.lua
        return
    end
    T.request(player, on and "campOff" or "campOn", { vid = vehicle:getId() })
end

-- power key (user 2026-10-27: the dashboard needs an on/off switch, else only Camp Mode turns the motor off).
-- On: the vanilla start action, same as the start-engine key (ISVehicleMenu.lua:1660-1664), so the key card, a bag
-- phone key (Keys.lua), the ignition key and hotwiring all work as before. Off: only stopped, like the real car
-- powering off in Park (owner's manual, Controls > Safety > Power Off); then the vanilla shut-off action.
function HUD.togglePower(player, vehicle)
    if not vehicle:isDriver(player) then return end
    if not vehicle:isEngineRunning() then return ISVehicleMenu.onStartEngine(player) end -- ISVehicleMenu.lua:1164
    if not T.stopped(vehicle) then
        HaloTextHelper.addBadText(player, T.denyText("MOVING"))
        return
    end
    ISVehicleMenu.onShutOff(player) -- ISVehicleMenu.lua:1176
end

-- ---------------------------------------------------------------- vanilla dashboard hooks
-- Tesla: the vanilla dashboard stays in UIManager but invisible, so its whole tree stops rendering
-- (UIElement.java:1605) while every other mod's wrappers on it keep working.
local origSetVehicle = ISVehicleDashboard.setVehicle
function ISVehicleDashboard:setVehicle(vehicle)
    self.mtTesla = vehicle ~= nil and T.isTesla(vehicle)
    origSetVehicle(self, vehicle) -- calls add/removeFromUIManager below (ISVehicleDashboard.lua:180-229)
end

local origAdd = ISVehicleDashboard.addToUIManager
function ISVehicleDashboard:addToUIManager()
    origAdd(self)
    if self.mtTesla and self.vehicle then
        self:setVisible(false)
        HUD.get(self.playerNum):show(self.vehicle)
    else
        local h = huds[self.playerNum]
        if h and h.vehicle then h:hide() end
    end
end

-- also fires every tick for walking player 0 (damageChecker, ISVehicleDashboard.lua:659-664): keep it O(1)
local origRemove = ISVehicleDashboard.removeFromUIManager
function ISVehicleDashboard:removeFromUIManager()
    origRemove(self)
    local h = huds[self.playerNum]
    if h and h.vehicle then h:hide() end
end

Events.OnResolutionChange.Add(function()
    for _, h in pairs(huds) do
        if h.vehicle then h:layout() end
    end
end)

-- ---------------------------------------------------------------- public API for other mods (AutoDrive)
-- Contract: references/hud.md "hudRect". Absolute screen pixels, top-left origin.
MinidoracatTeslaAPI = MinidoracatTeslaAPI or {}
function MinidoracatTeslaAPI.hudRect(playerNum)
    local h = huds[playerNum or 0]
    if not h or not h.vehicle or not h.inUI then return 0, 0, 0, 0, false end
    return h.x, h.y, h.width, h.height, h:isVisible()
end

return HUD
