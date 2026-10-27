-- Tesla app on the phone key (design: plan-phone-app-1027, user answers 2026-10-27). Opened from the phone key's
-- right-click menu (KeysUI.lua). While open it asks the server for its car every POLL_MS; the server
-- (server/MinidoracatTesla/Remote.lua) answers holders of that phone key only and checks every command again.
-- Players without the app open cost nothing. The car is named by keyId (self.key) in every request.
-- Pages: "home" (status, remote buttons, location, charging) and "alerts". "Show on map" opens the world map on the
-- car and draws a marker after vanilla's map: never saved, gone when the map closes.
-- Drawing follows the charge card (HUDChargeCard.lua): dashboard atlas, palette, S scale, joypad rows, HUD.drawTip.
require "ISUI/ISPanelJoypad"
require "ISUI/ISButton"
require "ISUI/Maps/ISWorldMap"
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Keys"
require "MinidoracatTesla/HUD"

local T = MinidoracatTesla
local K = T.Keys
local HUD = T.HUD
local C = HUD.C
local App = ISPanelJoypad:derive("MinidoracatTeslaPhoneApp")
T.PhoneApp = App
T.ClientCommands = T.ClientCommands or {}
App.POLL_MS = 2000
App.TOAST_MS = 4000
App.stats = { polls = 0, states = 0, sent = 0 }
local apps = {} -- [playerNum]

local W, PAD, GAP, BTN = 340, 14, 8, 42
local P = "IGUI_MinidoracatTesla_App_"
local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
-- round remote buttons: two rows (mock: lock, flash, horn, sentry; then the three extra features)
local ACTS = { "lock", "flash", "horn", "sentry", "frunk", "trunk", "alerts" }

local function txt(key, ...) return getText(P .. key, ...) end

function App:new(playerNum)
    local o = ISPanelJoypad.new(self, 0, 0, W, 400)
    o.playerNum = playerNum
    o.background = false
    o.anchorLeft, o.anchorTop = false, false
    o.page = "home"
    o.L, o.n = {}, 0
    return o
end

local function styleButton(b, text)
    b.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    b.backgroundColorMouseOver = { r = 1, g = 1, b = 1, a = 0 }
    b.borderColor = { r = 1, g = 1, b = 1, a = 0 }
    local c = text or C.text
    b.textColor = { r = c[1], g = c[2], b = c[3], a = 1 }
end

function App:createChildren()
    local function mk(title, fn, tip, color)
        local b = ISButton:new(0, 0, 40, 40, title, self, fn)
        b:initialise()
        b:instantiate()
        styleButton(b, color)
        b.tipKey = tip
        self:addChild(b)
        return b
    end
    self.acts = {}
    for i, id in ipairs(ACTS) do
        local b = mk("", App.onAct, nil)
        b.actId = id
        self.acts[i] = b
    end
    self.btnClose = mk("\195\151", App.close, "IGUI_MinidoracatTesla_Tip_AppClose", C.text3) -- U+00D7
    self.btnMap = mk(txt("Map"), App.onMap, "IGUI_MinidoracatTesla_Tip_AppMap", C.white)
    self.btnCharge = mk("", App.onCharge, nil, C.white)
    self.btnBack = mk(txt("Back"), App.onBack, "IGUI_MinidoracatTesla_Tip_AppBack", C.white)
    local a = self.acts
    self:insertNewLineOfButtons(a[1], a[2], a[3], a[4])
    self:insertNewLineOfButtons(a[5], a[6], a[7])
    self:insertNewLineOfButtons(self.btnMap)
    self:insertNewLineOfButtons(self.btnCharge)
    self:insertNewLineOfButtons(self.btnBack)
    self:insertNewLineOfButtons(self.btnClose)
    self.buttons = { a[1], a[2], a[3], a[4], a[5], a[6], a[7], self.btnMap, self.btnCharge, self.btnBack, self.btnClose }
end

-- ---------------------------------------------------------------- open / close
function App.open(playerNum, keyId)
    local p = getSpecificPlayer(playerNum)
    if not p or type(keyId) ~= "number" then return nil end
    local a = apps[playerNum]
    if not a then
        a = App:new(playerNum)
        a:initialise()
        a:instantiate()
        apps[playerNum] = a
    end
    if a.key ~= keyId then a.st, a.alerts = nil, nil end -- another car: forget the old one's state
    a.key, a.player, a.page, a.toast, a.nextPoll = keyId, p, "home", nil, 0
    a.sig = nil
    a:read()
    a:layout()
    if not a.inUI then a:addToUIManager(); a.inUI = true end
    a:setVisible(true)
    a:bringToTop()
    if JoypadState.players[playerNum + 1] then setJoypadFocus(playerNum, a) end -- JoyPadSetup.lua:546
    T.log("app open key=" .. tostring(keyId))
    return a
end
function App.get(playerNum) return apps[playerNum or 0] end

function App:close()
    if self.joyfocus and JoypadState.players[self.playerNum + 1] then setJoypadFocus(self.playerNum, nil) end
    self.joyfocus = nil
    if self.inUI then self:removeFromUIManager(); self.inUI = false end
    self.key = nil
end

function App:onGainJoypadFocus(joypadData)
    ISPanelJoypad.onGainJoypadFocus(self, joypadData)
    self:setISButtonForB(self.page == "alerts" and self.btnBack or self.btnClose)
    self:setJoypadFocusTopLeft(joypadData)
end

function App:onLoseJoypadFocus(joypadData)
    ISPanelJoypad.onLoseJoypadFocus(self, joypadData)
    self:clearJoypadFocus(joypadData)
    self:clearISButtonB()
end

function App:setPage(page)
    self.page = page
    self.sig = nil
    self:read()
    self:layout()
    if self.joyfocus then
        self:setISButtonForB(page == "alerts" and self.btnBack or self.btnClose)
        self:setJoypadFocusTopLeft(self.joyfocus)
    end
end

-- ---------------------------------------------------------------- actions (the server checks everything)
function App:send(cmd, args)
    args.key = self.key
    T.request(self.player, cmd, args)
end

function App:onAct(b)
    local id, st = b.actId, self.st or {}
    if id == "alerts" then
        self:send("appAlerts", {})
        return self:setPage("alerts")
    end
    local act, on = id, nil
    if id == "lock" then act = st.locked and "unlock" or "lock"
    elseif id == "sentry" then on = not st.sentry
    elseif id == "frunk" then on = not st.frunk
    elseif id == "trunk" then on = not st.trunk end
    self.sent = { act = act, on = on }
    App.stats.sent = App.stats.sent + 1
    self:send("appAction", { act = act, on = on })
end

function App:onCharge()
    local on = (self.st and self.st.chg) == "stopped"
    self.sent = { act = "charge", on = on }
    App.stats.sent = App.stats.sent + 1
    self:send("appAction", { act = "charge", on = on })
end

function App:onBack() self:setPage("home") end

-- "Show on map": vanilla world map centred on the car (ISWorldMap.lua:1500), marker drawn by App.drawMapCar
function App:onMap()
    local st = self.st
    if not (st and st.x) or not ISWorldMap.IsAllowed() then return end
    App.mapCar = { x = st.x + 0.5, y = st.y + 0.5, name = self.sName, dist = self.sDist, pn = self.playerNum, key = self.key }
    self:close()
    ISWorldMap.ShowWorldMap(App.mapCar.pn, App.mapCar.x, App.mapCar.y, 18)
end

function App:showToast(text, ok)
    self.toast = { text = text, ok = ok, untilMs = getTimestampMs() + App.TOAST_MS }
    self.sig = nil
end

-- ---------------------------------------------------------------- server -> client
local function each(key, fn)
    local hit = false
    for _, a in pairs(apps) do
        if a.key ~= nil and a.key == key then fn(a); hit = true end
    end
    return hit
end

T.ClientCommands.appState = function(args)
    each(args.key, function(a)
        App.stats.states = App.stats.states + 1
        a.st = args
        a.stAt = getTimestampMs()
    end)
end

T.ClientCommands.appDone = function(args)
    local text
    if args.why then
        text = T.denyText(args.why)
    else
        text = getText("IGUI_MinidoracatTesla_App_Done_" .. tostring(args.act))
    end
    local shown = args.key ~= nil and each(args.key, function(a)
        if not args.why and a.sent and a.sent.act == args.act and a.sent.on ~= nil then
            text = getText("IGUI_MinidoracatTesla_App_Done_" .. args.act .. (a.sent.on and "_on" or "_off"))
        end
        a:showToast(text, args.why == nil)
    end)
    App.lastDone = args
    T.log("app done " .. tostring(args.act) .. " " .. tostring(args.why or "ok"))
    if not shown then -- no app open (or not a holder): say it over the player's head
        local p = getSpecificPlayer(0)
        if p then
            if args.why then HaloTextHelper.addBadText(p, text) else HaloTextHelper.addGoodText(p, text) end
        end
    end
end

T.ClientCommands.appAlerts = function(args)
    each(args.key, function(a)
        local rows = {}
        local list = type(args.list) == "table" and args.list or {}
        local card = T.ParkUI and T.ParkUI.card
        for i = #list, 1, -1 do -- newest first
            local c = card and card(list[i])
            if c then rows[#rows + 1] = { title = c.title, detail = c.detail or "", time = c.time or "", icon = c.icon } end
        end
        a.alerts = rows
        a.sig = nil
    end)
end

-- ---------------------------------------------------------------- reading
local function ageText(hours)
    local mins = math.floor(math.max(0, hours) * 60)
    if mins < 2 then return txt("JustNow") end
    if mins < 60 then return txt("MinsAgo", tostring(mins)) end
    if mins < 48 * 60 then return txt("HoursAgo", tostring(math.floor(mins / 60))) end
    return txt("DaysAgo", tostring(math.floor(mins / 1440)))
end

local function distText(d)
    if d < 1000 then return txt("Meters", tostring(math.floor(d + 0.5))) end
    local t = math.floor(d / 100 + 0.5)
    return txt("Km", tostring(math.floor(t / 10)) .. "." .. tostring(t % 10))
end

-- Where the car is from the player: compass words (north = -y) and the screen angle of the arrow. The iso screen
-- shows a world step (dx, dy) as (dx - dy, (dx + dy) / 2), so north points up-right as the player sees it.
-- Returns distance, compass index 1..8, clockwise degrees from screen-up (DrawTextureAngle, UIElement.java:243-262).
-- Kahlua's % keeps the dividend's sign (-119 % 360 = -119 in game, tesla-app-1027a), so wrap with floor instead.
local function wrap360(d) return d - math.floor(d / 360) * 360 end
function App.bearing(px, py, cx, cy)
    local dx, dy = cx - px, cy - py
    local dist = math.sqrt(dx * dx + dy * dy)
    local compass = wrap360(math.deg(math.atan2(dx, -dy)))
    local sx, sy = dx - dy, (dx + dy) / 2
    local ci = math.floor((compass + 22.5) / 45)
    return dist, ci - math.floor(ci / 8) * 8 + 1, wrap360(math.deg(math.atan2(sx, -sy)))
end

-- strings and button states only when something shown changes (10 Hz update; no allocation otherwise)
function App:read()
    local st, p = self.st, self.player
    local gt = getGameTime()
    local hh, mm = gt:getHour(), gt:getMinutes()
    local now = getTimestampMs()
    if self.toast and now >= self.toast.untilMs then self.toast, self.sig = nil, nil end
    -- position: every update (the player walks), no relayout
    if st and st.x and p then
        local d, ci, ang = App.bearing(p:getX(), p:getY(), st.x + 0.5, st.y + 0.5)
        self.arrowAngle = ang
        local dk = math.floor(d + 0.5) .. ci
        if dk ~= self.distKey then
            self.distKey = dk
            self.sDist = distText(d)
            self.sDir = d < 3 and txt("Here") or txt("Dir_" .. DIRS[ci])
        end
    end
    local alertsN = self.alerts and #self.alerts or -1
    local sig = self.page .. hh .. ":" .. mm .. "/" .. tostring(self.toast and self.toast.text) .. "/" .. alertsN .. "/"
        .. tostring(self.stAt)
    if sig == self.sig then return false end
    self.sig = sig
    self.sTime = string.format("%02d:%02d", hh, mm)
    local link = st and st.link
    self.link = link
    -- status bar: the phone's network (grid up), else Bluetooth while it reaches the car, else no service
    self.grid = st ~= nil and st.grid == true
    self.sNet = self.grid and txt("Net") or (link == "bt" and txt("Bt") or txt("NoService"))
    local rec = st and st.pct ~= nil and not st.deny
    self.rec = rec
    self.sName = st and st.car and getText("IGUI_VehicleName" .. st.car) or txt("Title")
    local sep = getText("IGUI_MinidoracatTesla_Sep")
    if not st then
        self.sSub = txt("Connecting")
    elseif st.deny then
        self.sSub = T.denyText(st.deny)
    elseif not rec then
        self.sSub = txt("NoRecord")
    elseif link then
        self.sSub = (st.drive and txt("Driving") or txt("Parked")) .. sep .. (st.locked and txt("Locked") or txt("Unlocked"))
    else
        self.sSub = txt("LastSeen", ageText(T.hours() - (st.h or 0))) .. sep .. tostring(st.pct) .. "%" .. sep .. tostring(st.km) .. " km"
    end
    self.sHead, self.sHeadSub = self.sName, self.sSub
    if self.page == "alerts" then self.sHead, self.sHeadSub = txt("AlertsTitle"), self.sName end
    self.sPct = rec and (tostring(st.pct) .. "%") or ""
    self.pct = rec and st.pct or 0
    self.sKm = rec and (tostring(st.km) .. " km") or ""
    self.sWhen = rec and (txt("Location") .. sep .. (link and txt("JustNow") or ageText(T.hours() - (st.h or 0)))) or ""
    self.sFoot = (st and not st.deny and (link == "net" and txt("FootNet") or (link == "bt" and txt("FootBt") or txt("FootOff")))) or ""
    -- remote buttons
    local live = rec and link ~= nil
    for _, b in ipairs(self.acts) do
        local id = b.actId
        local icon, label, tip, on = "i_" .. id, txt(id == "alerts" and "Alerts" or id:sub(1, 1):upper() .. id:sub(2)), "IGUI_MinidoracatTesla_Tip_App" .. id:sub(1, 1):upper() .. id:sub(2), false
        if id == "lock" then
            on = rec and st.locked == true
            icon, label = on and "i_unlock" or "i_lock", on and txt("Unlock") or txt("Lock")
            tip = on and "IGUI_MinidoracatTesla_Tip_AppUnlock" or "IGUI_MinidoracatTesla_Tip_AppLock"
        elseif id == "flash" then icon = "i_headlight"
        elseif id == "sentry" then
            on = rec and st.sentry == true
            icon = "i_ring"
            tip = on and "IGUI_MinidoracatTesla_Tip_AppSentryOff" or "IGUI_MinidoracatTesla_Tip_AppSentryOn"
        elseif id == "frunk" or id == "trunk" then on = rec and st[id] == true
        elseif id == "alerts" then icon = "i_list" end
        b.icon, b.label, b.tipKey, b.on = icon, label, tip, on
        b:setEnable((id == "alerts" and not (st and st.deny)) or live == true)
    end
    -- charging card
    local chg = rec and st.chg
    self.chg = chg
    if chg then
        if chg == "charging" then self.sChg = txt("Charging", tostring(st.kw or 0))
        elseif chg == "full" then self.sChg = txt("ChargeFull", tostring(st.target or 90))
        elseif chg == "nopower" then self.sChg = txt("ChargeNoPower")
        else self.sChg = txt("ChargeStopped") end
        self.sChgDetail = (chg == "charging" and st.mins) and txt("ToTarget", tostring(st.target or 90), tostring(st.mins)) or ""
        self.btnCharge:setTitle(chg == "charging" and txt("ChargeStop") or txt("ChargeStart"))
        self.btnCharge.tipKey = chg == "charging" and "IGUI_MinidoracatTesla_Tip_AppChargeStop" or "IGUI_MinidoracatTesla_Tip_AppChargeStart"
        self.btnCharge:setEnable(live)
    end
    self.btnMap:setEnable(rec == true)
    return true
end

function App:update()
    ISPanelJoypad.update(self)
    if not self.key then return end
    local p = self.player
    local now = getTimestampMs()
    if now >= self.nextPoll then
        self.nextPoll = now + App.POLL_MS
        -- the phone left the inventory, or the player is gone: close (nothing to poll for)
        if not p or p:isDead() or not K.phoneKeyFor(p, self.key) then return self:close() end
        App.stats.polls = App.stats.polls + 1
        self:send("appStatus", {})
    end
    if self:read() then self:layout() end
end

-- ---------------------------------------------------------------- layout
function App:layout()
    local tm = getTextManager()
    self.tipKey = nil
    local pn = self.playerNum
    local S = tm:getFontHeight(UIFont.Small) / 19
    S = math.min(S, (getPlayerScreenWidth(pn) - 8) / W)
    self.S = S
    self.FH, self.FHM, self.FHL = tm:getFontHeight(UIFont.Small), tm:getFontHeight(UIFont.Medium), tm:getFontHeight(UIFont.Large)
    local k = S >= 1.5 and 2 or 1
    self.A = T.HUDAtlas[k]
    self.tex = getTexture(self.A.tex)
    self.arrowTex = getTexture("media/textures/MinidoracatTesla/HUD/app_arrow" .. k .. "x.png")
    self.f = S / k
    local w = math.min(math.floor(W * S), getPlayerScreenWidth(pn) - 8)
    local pad, gap = math.floor(PAD * S), math.floor(GAP * S)
    local home = self.page == "home"
    for _, b in ipairs(self.buttons) do b:setVisible(false) end
    local y = pad
    self.yBar = y
    y = y + self.FH + gap
    -- header: name, status line, close
    self.yName = y
    local cs = math.floor(28 * S)
    self.btnClose:setVisible(true)
    self.btnClose:setX(w - pad - cs); self.btnClose:setY(y); self.btnClose:setWidth(cs); self.btnClose:setHeight(cs)
    y = y + self.FHM
    self.ySub = y
    y = y + self.FH + gap
    if home then
        self.yCar = y
        y = y + math.floor(85 * S) + math.floor(4 * S)
        self.yBat = y
        y = y + self.FHL + gap
        -- remote buttons: 4 columns, 2 rows, label under each
        local colW = (w - 2 * pad) / 4
        local bs = math.floor(BTN * S)
        self.btnSize = bs
        local rowH = bs + math.floor(5 * S) + self.FH
        for i, b in ipairs(self.acts) do
            local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
            b:setVisible(true)
            b:setX(math.floor(pad + col * colW + (colW - bs) / 2)); b:setY(y + row * (rowH + gap))
            b:setWidth(bs); b:setHeight(bs)
        end
        y = y + 2 * rowH + gap + math.floor(4 * S)
        -- location card
        local ip = math.floor(10 * S)
        local bh = math.max(self.FH + math.floor(10 * S), math.floor(30 * S))
        local function fit(b) return tm:MeasureStringX(UIFont.Small, b.title) + math.floor(20 * S) end
        self.yLoc = y
        local row1 = math.max(bh, self.FHM + self.FH)
        self.locH = ip + row1 + math.floor(4 * S) + self.FH + ip
        self.btnMap:setVisible(ISWorldMap.IsAllowed())
        local mw = fit(self.btnMap)
        self.btnMap:setX(w - pad - ip - mw); self.btnMap:setY(y + ip + math.floor((row1 - bh) / 2))
        self.btnMap:setWidth(mw); self.btnMap:setHeight(bh)
        self.locRow1 = row1
        y = y + self.locH + gap
        -- charging card (plugged in only)
        self.yChg = nil
        if self.chg then
            self.yChg = y
            local cw = fit(self.btnCharge)
            local showBtn = self.chg == "charging" or self.chg == "stopped"
            self.btnCharge:setVisible(showBtn)
            self.btnCharge:setX(w - pad - ip - cw); self.btnCharge:setY(y + ip)
            self.btnCharge:setWidth(cw); self.btnCharge:setHeight(bh)
            self.chgH = ip + math.max(bh, self.FH) + math.floor(4 * S) + self.FH + ip
            y = y + self.chgH + gap
        end
    else
        -- alerts page: newest first, one card per alert
        self.yRows = y
        local rh = 2 * self.FH + math.floor(14 * S)
        self.rowH = rh
        local n = self.alerts and #self.alerts or 0
        y = y + math.max(1, n) * (rh + math.floor(6 * S))
        local bh = math.max(self.FH + math.floor(10 * S), math.floor(32 * S))
        self.btnBack:setVisible(true)
        self.btnBack:setX(pad); self.btnBack:setY(y); self.btnBack:setWidth(w - 2 * pad); self.btnBack:setHeight(bh)
        y = y + bh + gap
    end
    self.yToast = nil
    if self.toast then
        self.yToast = y
        y = y + self.FH + math.floor(16 * S) + gap
    end
    self.yFoot = y
    y = y + self.FH + pad
    self:setWidth(w)
    self:setHeight(y)
    -- right half of this player's screen, centred vertically, like a phone held up
    local sw, sh = getPlayerScreenWidth(pn), getPlayerScreenHeight(pn)
    self:setX(getPlayerScreenLeft(pn) + math.max(4, sw - w - math.floor(40 * S)))
    self:setY(getPlayerScreenTop(pn) + math.max(4, math.floor((sh - y) / 2)))
end

Events.OnResolutionChange.Add(function()
    for _, a in pairs(apps) do
        if a.key then a:layout() end
    end
end)

-- ---------------------------------------------------------------- drawing
local function flush(self)
    local jo, tex, L = self.javaObject, self.tex, self.L
    for i = 1, self.n, 12 do
        jo:DrawSubTextureRGBA(tex, L[i], L[i + 1], L[i + 2], L[i + 3], L[i + 4], L[i + 5], L[i + 6], L[i + 7],
            L[i + 8], L[i + 9], L[i + 10], L[i + 11])
    end
    self.n = 0
end

local function focusRing(self, b, S)
    HUD.rrect(self, b.x - 4 * S, b.y - 4 * S, b.width + 8 * S, b.height + 8 * S, math.min(b.width, b.height) / 2 + 4 * S, C.text, 1)
    HUD.rrect(self, b.x - 2 * S, b.y - 2 * S, b.width + 4 * S, b.height + 4 * S, math.min(b.width, b.height) / 2 + 2 * S, C.bg, 1)
end

function App:prerender()
    if not self.S then return end
    self.n = 0
    local S, w, A = self.S, self.width, self.A
    local pad = math.floor(PAD * S)
    HUD.rrect(self, 0, 0, w, self.height, 24 * S, C.bg, 0.97)
    -- signal bars (grid up)
    if self.grid then
        local bx = w - pad - math.floor(16 * S)
        local by = self.yBar + (self.FH - 12 * S) / 2
        for i = 0, 3 do
            local hh = (4 + i * 2.7) * S
            HUD.rect(self, bx + i * 4.3 * S, by + 12 * S - hh, 3 * S, hh, C.text2, 1)
        end
    end
    if self.page == "home" then
        HUD.spr(self, A.car, math.floor((w - 150 * S) / 2), self.yCar, C.white, self.rec and 1 or 0.5)
        if self.rec then -- battery cell after the percentage (centred row)
            self.cellX = math.floor(w / 2 - 12 * S)
            local cy = self.yBat + (self.FHL - 12 * S) / 2
            HUD.spr(self, A.cell, self.cellX, cy, C.text, 1)
            HUD.rect(self, self.cellX + 2.4 * S, cy + 2.4 * S, math.max(1, 13.4 * S * self.pct / 100), 7.2 * S, self.pct < 20 and C.warn or C.text, 1)
        end
        for _, b in ipairs(self.acts) do
            local a = b.enable and 1 or 0.35
            if b.joypadFocused then focusRing(self, b, S) end
            HUD.rrect(self, b.x, b.y, b.width, b.height, b.width / 2, b.on and C.accentFill or C.surface, a)
            local ix, iy = b.x + (b.width - 18 * S) / 2, b.y + (b.height - 18 * S) / 2
            HUD.spr(self, A[b.icon], ix, iy, C.text, a)
            if b.actId == "sentry" then HUD.spr(self, A.i_dot, ix, iy, C.red, a) end
        end
        HUD.rrect(self, pad, self.yLoc, w - 2 * pad, self.locH, 12 * S, C.surface, 1)
        if self.yChg then
            HUD.rrect(self, pad, self.yChg, w - 2 * pad, self.chgH, 12 * S, C.surface, 1)
            HUD.spr(self, A.i_bolt, pad + 10 * S, self.yChg + 10 * S + (math.max(self.btnCharge.height, self.FH) - 18 * S) / 2,
                self.chg == "charging" and C.ok or C.text2, 1)
        end
    else
        local rows = self.alerts or {}
        local rh = self.rowH
        for i = 1, math.max(1, #rows) do
            HUD.rrect(self, pad, self.yRows + (i - 1) * (rh + 6 * S), w - 2 * pad, rh, 10 * S, C.surface, 1)
        end
    end
    for _, b in ipairs({ self.btnMap, self.btnCharge, self.btnBack }) do
        if b:isVisible() then
            if b.joypadFocused then focusRing(self, b, S) end
            HUD.rrect(self, b.x, b.y, b.width, b.height, 8 * S, C.accentFill, b.enable and 1 or 0.4)
        end
    end
    if self.btnClose.joypadFocused then focusRing(self, self.btnClose, S) end
    if self.yToast then
        HUD.rrect(self, pad, self.yToast, w - 2 * pad, self.FH + 16 * S, 10 * S, C.track, 1)
        HUD.spr(self, self.toast.ok and A.i_check or A.i_warn, pad + 8 * S, self.yToast + (self.FH + 16 * S - 18 * S) / 2,
            self.toast.ok and C.ok or C.warn, 1)
    end
    flush(self)
end

function App:render()
    if not self.S then return end
    local S, w = self.S, self.width
    local pad = math.floor(PAD * S)
    local jo, c, c2, c3 = self.javaObject, C.text, C.text2, C.text3
    jo:DrawText(UIFont.Small, self.sTime, pad, self.yBar, c2[1], c2[2], c2[3], 1)
    local netC = self.link == "bt" and C.accent or c2
    self:drawTextRight(self.sNet, w - pad - (self.grid and math.floor(22 * S) or 0), self.yBar, netC[1], netC[2], netC[3], 1, UIFont.Small)
    jo:DrawText(UIFont.Medium, self.sHead, pad, self.yName, c[1], c[2], c[3], 1)
    jo:DrawText(UIFont.Small, self.sHeadSub, pad, self.ySub, c2[1], c2[2], c2[3], 1)
    if self.page == "home" then
        if self.rec then
            self:drawTextRight(self.sPct, self.cellX - math.floor(8 * S), self.yBat, c[1], c[2], c[3], 1, UIFont.Large)
            jo:DrawText(UIFont.Small, self.sKm, self.cellX + math.floor(32 * S), self.yBat + (self.FHL - self.FH) / 2, c2[1], c2[2], c2[3], 1)
        end
        for _, b in ipairs(self.acts) do
            self:drawTextCentre(b.label, b.x + b.width / 2, b.y + b.height + math.floor(5 * S), c2[1], c2[2], c2[3], b.enable and 1 or 0.35, UIFont.Small)
        end
        local ip = math.floor(10 * S)
        if self.rec and self.sDist then
            local ay = self.yLoc + ip + self.locRow1 / 2
            jo:DrawTextureAngle(self.arrowTex, pad + ip + 12 * S, ay, self.arrowAngle or 0, 1, 1, 1, 1)
            local tx = pad + ip + math.floor(30 * S)
            jo:DrawText(UIFont.Medium, self.sDist, tx, self.yLoc + ip + (self.locRow1 - self.FHM - self.FH) / 2, c[1], c[2], c[3], 1)
            jo:DrawText(UIFont.Small, self.sDir, tx, self.yLoc + ip + (self.locRow1 - self.FHM - self.FH) / 2 + self.FHM, c2[1], c2[2], c2[3], 1)
        end
        jo:DrawText(UIFont.Small, self.sWhen, pad + ip, self.yLoc + ip + self.locRow1 + math.floor(4 * S), c3[1], c3[2], c3[3], 1)
        if self.yChg then
            local row1 = math.max(self.btnCharge.height, self.FH)
            jo:DrawText(UIFont.Small, self.sChg, pad + ip + math.floor(24 * S), self.yChg + ip + (row1 - self.FH) / 2, c[1], c[2], c[3], 1)
            jo:DrawText(UIFont.Small, self.sChgDetail, pad + ip, self.yChg + ip + row1 + math.floor(4 * S), c3[1], c3[2], c3[3], 1)
        end
    else
        local rows = self.alerts
        local rh = self.rowH
        if not rows then
            jo:DrawText(UIFont.Small, txt("Loading"), pad + math.floor(10 * S), self.yRows + (rh - self.FH) / 2, c2[1], c2[2], c2[3], 1)
        elseif #rows == 0 then
            jo:DrawText(UIFont.Small, txt("NoAlerts"), pad + math.floor(10 * S), self.yRows + (rh - self.FH) / 2, c2[1], c2[2], c2[3], 1)
        else
            for i, r in ipairs(rows) do
                local ry = self.yRows + (i - 1) * (rh + 6 * S) + math.floor(7 * S)
                if r.icon then self:drawTextureScaled(r.icon, pad + 10 * S, ry, 18 * S, 18 * S, 1, 1, 1, 1) end
                jo:DrawText(UIFont.Small, r.title, pad + math.floor(36 * S), ry, c[1], c[2], c[3], 1)
                self:drawTextRight(r.time, w - pad - math.floor(10 * S), ry, c3[1], c3[2], c3[3], 1, UIFont.Small)
                jo:DrawText(UIFont.Small, r.detail, pad + math.floor(36 * S), ry + self.FH, c3[1], c3[2], c3[3], 1)
            end
        end
    end
    if self.yToast then
        local tc = self.toast.ok and c or C.warn
        jo:DrawText(UIFont.Small, self.toast.text, pad + math.floor(32 * S), self.yToast + math.floor(8 * S), tc[1], tc[2], tc[3], 1)
    end
    self:drawTextCentre(self.sFoot, w / 2, self.yFoot, c3[1], c3[2], c3[3], 1, UIFont.Small)
    -- hover help: the button under the mouse, or the joypad-focused one
    for _, b in ipairs(self.buttons) do
        if b:isVisible() and b.tipKey and (b.joypadFocused or b:isMouseOver()) then
            HUD.drawTip(self, b.tipKey, b.x, b.y, b.width, b.height)
            break
        end
    end
end

-- ---------------------------------------------------------------- world map marker (temporary, never saved)
-- Drawn after vanilla's map (ISWorldMap.lua:384) with the dashboard atlas; worldToUIX/Y as vanilla's print media
-- markers (:478-479). Cleared when the map closes; the app comes back then.
function App.drawMapCar(map, m)
    local api = map.mapAPI
    if not api then return end
    local x, y = api:worldToUIX(m.x, m.y), api:worldToUIY(m.x, m.y)
    local A = T.HUDAtlas[1]
    local tex = getTexture(A.tex)
    local e = A.round
    local jo = map.javaObject
    jo:DrawSubTextureRGBA(tex, e[1], e[2], e[3], e[4], x - 15, y - 15, 30, 30, 1, 1, 1, 1)
    local b = C.accentFill
    jo:DrawSubTextureRGBA(tex, e[1], e[2], e[3], e[4], x - 13, y - 13, 26, 26, b[1], b[2], b[3], 1)
    local car = A.car -- the dashboard's top view, small, as the car glyph
    jo:DrawSubTextureRGBA(tex, car[1], car[2], car[3], car[4], x - 10, y - 6, 20, 11, 1, 1, 1, 1)
    local tm = getTextManager()
    local tw = math.max(tm:MeasureStringX(UIFont.Medium, m.name or ""), tm:MeasureStringX(UIFont.Small, m.dist or ""))
    local fm, fs = tm:getFontHeight(UIFont.Medium), tm:getFontHeight(UIFont.Small)
    map:drawRect(x + 18, y - fm, tw + 12, fm + fs + 4, 0.85, 1, 1, 1)
    map:drawText(m.name or "", x + 24, y - fm + 1, 0.12, 0.13, 0.15, 1, UIFont.Medium)
    map:drawText(m.dist or "", x + 24, y + 2, 0.29, 0.32, 0.36, 1, UIFont.Small)
    App.mapDrawn = (App.mapDrawn or 0) + 1
end

local mapRender, mapClose = ISWorldMap.render, ISWorldMap.close
function ISWorldMap:render(...)
    local r = mapRender(self, ...)
    local m = App.mapCar
    if m then App.drawMapCar(self, m) end
    return r
end
function ISWorldMap:close(...)
    local m = App.mapCar
    App.mapCar = nil
    local r = mapClose(self, ...)
    if m then App.open(m.pn, m.key) end -- back to the app
    return r
end

return App
