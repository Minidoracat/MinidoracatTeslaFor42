-- Tesla app on the phone key (design: plan-phone-app-1027, user answers 2026-10-27; looks after the real Tesla app,
-- decisions.md "手機 App 第一版", mock temp/app-style/restyle.html). Opened from the phone key's right-click menu
-- (KeysUI.lua). While open it asks the server for its car every POLL_MS; the server (server/MinidoracatTesla/Remote.lua)
-- answers holders of that phone key only and checks every command again. Players without the app open cost nothing.
-- The car is named by keyId (self.key) in every request.
-- Pages: "home" (name, battery, the car in its paint, four quick icons, a list into the sub pages), "controls" (flash,
-- horn, frunk, liftgate), "location" (arrow, distance, "Show on map"), "security" (Sentry Mode, alerts), "charging".
-- "Show on map" opens the world map on the car and draws a marker after vanilla's map: never saved, gone when the map
-- closes (the app comes back on the location page).
-- Drawing: the dashboard atlas (2x; HUD.spr / HUD.rrect), S scale, HUD.drawTip. Buttons are bare hit areas; the app
-- draws everything. Joypad: the D-pad moves along the page's rows (NAV), A presses, B goes back (home: closes).
-- A page taller than this player's screen scrolls below its header (mouse wheel; joypad focus scrolls itself in).
require "ISUI/ISPanelJoypad"
require "ISUI/ISButton"
require "ISUI/Maps/ISWorldMap"
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Keys"
require "MinidoracatTesla/HUD"

local T = MinidoracatTesla
local K = T.Keys
local HUD = T.HUD
local App = ISPanelJoypad:derive("MinidoracatTeslaPhoneApp")
T.PhoneApp = App
T.ClientCommands = T.ClientCommands or {}
App.POLL_MS = 2000
App.TOAST_MS = 4000
App.stats = { polls = 0, states = 0, sent = 0 }
local apps = {} -- [playerNum]

local W, PAD = 340, 20
local P = "IGUI_MinidoracatTesla_App_"
local TIP = "IGUI_MinidoracatTesla_Tip_App"
local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function rgb(hex)
    return { tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255 }
end
-- the real Tesla app's colours (decisions.md): blue only for main actions, no card fills, a 1 px frame on the control
-- tiles. build_atlas.py PAL app* holds the same hex values and asserts their contrast: change both.
local C = { bg = rgb("#161718"), text = rgb("#F3F3F3"), text2 = rgb("#8A8B8B"), weak = rgb("#454546"),
    line = rgb("#2E2F30"), blue = rgb("#3268FE"), ok = HUD.C.ok, warn = HUD.C.warn, white = HUD.C.white }

-- hit areas: id -> { page, server action }; the list rows open the page of their own name
local BTN = {
    close = { "home" }, lock = { "home", "lock" }, qcharge = { "home", "charge" }, qfrunk = { "home", "frunk" },
    qtrunk = { "home", "trunk" }, controls = { "home" }, location = { "home" }, security = { "home" }, charging = { "home" },
    back = {}, flash = { "controls", "flash" }, horn = { "controls", "horn" }, frunk = { "controls", "frunk" },
    trunk = { "controls", "trunk" }, map = { "location" }, sentry = { "security", "sentry" }, charge = { "charging", "charge" },
}
local BTN_ORDER = { "close", "lock", "qcharge", "qfrunk", "qtrunk", "controls", "location", "security", "charging", "back",
    "flash", "horn", "frunk", "trunk", "map", "sentry", "charge" }
-- the joypad's rows per page, top to bottom (buttons not shown are skipped)
local NAV = {
    home = { { "close" }, { "lock", "qcharge", "qfrunk", "qtrunk" }, { "controls" }, { "location" }, { "security" }, { "charging" } },
    controls = { { "back" }, { "flash", "horn" }, { "frunk", "trunk" } },
    location = { { "back" }, { "map" } },
    security = { { "back" }, { "sentry" } },
    charging = { { "back" }, { "charge" } },
}
local QUICK = { "lock", "qcharge", "qfrunk", "qtrunk" }
local LIST = { "controls", "location", "security", "charging" }
local LIST_ICON = { controls = "i_carfront", location = "i_nav", security = "i_shield", charging = "i_bolt" }
local TITLE = { controls = "Controls", location = "Location", security = "Security", charging = "ChargingTitle" }
local GRID = { "flash", "horn", "frunk", "trunk" }
local GRID_ICON = { flash = "i_headlight", horn = "i_horn", frunk = "i_frunk", trunk = "i_trunk" }
local LIDS = { "frunk", "trunk" }
local HEAD = { "close", "back" } -- header buttons (never scroll)
local MAIN = { "map", "charge" } -- the blue main actions

local function txt(key, ...) return getText(P .. key, ...) end

-- the longest head of `s` that fits `maxW` in `font`, with "..." when cut. Kahlua strings index UTF-16 units, so sub
-- never splits a CJK character in game.
local function fitText(s, maxW, font)
    font = font or UIFont.Small
    local tm = getTextManager()
    if tm:MeasureStringX(font, s) <= maxW then return s end
    local n = #s
    while n > 1 and tm:MeasureStringX(font, s:sub(1, n) .. "...") > maxW do n = n - 1 end
    return s:sub(1, n) .. "..."
end
-- a toast's text in up to two lines: cut at the last space that fits (CJK: at the last character that fits)
local function wrap2(s, maxW)
    local tm = getTextManager()
    if tm:MeasureStringX(UIFont.Small, s) <= maxW then return s, nil end
    local n = #s
    while n > 1 and tm:MeasureStringX(UIFont.Small, s:sub(1, n)) > maxW do n = n - 1 end
    local sp = n
    while sp > n / 2 and s:sub(sp, sp) ~= " " do sp = sp - 1 end
    if s:sub(sp, sp) == " " then n = sp end
    return s:sub(1, n), fitText(s:sub(n + 1):gsub("^%s+", ""), maxW)
end

-- the car picture in its paint: scripts/blender/skf/convert.py appcar (480x240, references/models.md)
local carTex = {}
local function carTexture(name)
    local t = carTex[name]
    if not t then
        t = getTexture("media/textures/MinidoracatTesla/HUD/app_car_" .. name .. ".png")
        carTex[name] = t
    end
    return t
end
-- colors[skin + 1] of the car's spec (Core.lua: entry i = script skin i-1); no skin yet (a record from before the
-- field) or an unknown index: the first paint
function App.paint(car, skin)
    local spec = car and T.Specs["Base." .. car] or T.Specs["Base.MinidoracatTesla_ModelY"]
    local colors = spec.colors
    return (type(skin) == "number" and colors[skin + 1]) or colors[1], spec.model
end

function App:new(playerNum)
    local o = ISPanelJoypad.new(self, 0, 0, W, 400)
    o.playerNum = playerNum
    o.background = false
    o.anchorLeft, o.anchorTop = false, false
    o.page = "home"
    o.scroll, o.scrollMax, o.dy = 0, 0, 0
    o.L, o.n = {}, 0
    o.rowEm, o.rowSub = {}, {}
    return o
end

function App:createChildren()
    self.b, self.buttons = {}, {}
    for _, id in ipairs(BTN_ORDER) do
        local b = ISButton:new(0, 0, 40, 40, "", self, App.onButton)
        b:initialise()
        b:instantiate()
        -- a bare hit area: the app draws every button (ISButton's own disabled look is an opaque box, ISButton.lua:416-438)
        b.displayBackground = false
        b.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        b.backgroundColorMouseOver = { r = 1, g = 1, b = 1, a = 0 }
        b.borderColor = { r = 1, g = 1, b = 1, a = 0 }
        b.id, b.act, b.enable = id, BTN[id][2], true
        self:addChild(b)
        self.b[id] = b
        self.buttons[#self.buttons + 1] = b
    end
end

-- ---------------------------------------------------------------- open / close
function App.open(playerNum, keyId, page)
    local p = getSpecificPlayer(playerNum)
    if not p or type(keyId) ~= "number" then return nil end
    local a = apps[playerNum]
    if not a then
        a = App:new(playerNum)
        a:initialise()
        a:instantiate()
        apps[playerNum] = a
    end
    if a.key ~= keyId then a.st, a.alerts, a.alertsWhy = nil, nil, nil end -- another car: forget the old one's state
    a.key, a.player, a.page, a.toast, a.nextPoll, a.scroll = keyId, p, page or "home", nil, 0, 0
    a.sig = nil
    a:send("appAlerts", {}) -- the home list's alert count; the security page asks again
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
    local jf = self.joyfocus
    if jf then
        if JoypadState.players[self.playerNum + 1] then setJoypadFocus(self.playerNum, nil) end
        if self.joyfocus then self:onLoseJoypadFocus(jf) end -- focus off even without a pad in the slot
    end
    self.joyfocus = nil
    self:setFocus(nil)
    if self.inUI then self:removeFromUIManager(); self.inUI = false end
    self.key = nil
end

function App:setPage(page)
    local from = self.page
    self.page, self.scroll, self.sig = page, 0, nil
    if page == "security" then self:send("appAlerts", {}) end
    self:read()
    self:layout()
    -- joypad: back home lands on the row it came from, a sub page starts on its first control
    if self.joyfocus then self:focusFirst(page == "home" and from or nil) end
end

-- ---------------------------------------------------------------- joypad: own rows (NAV), not ISPanelJoypad's grid
-- the focused control stays in view (layout scrolls to it) until the player scrolls the page by hand
function App:setFocus(b)
    if self.focusB then self.focusB.joypadFocused = false end
    self.focusB, self.freeScroll = b, false
    if not b then return end
    b.joypadFocused = true
    if b.cy >= self.yBody and self.scrollMax > 0 then self:layout() end
end
function App:focusAt(row, col)
    self.fRow, self.fCol = row, col
    self:setFocus(self.b[NAV[self.page][row][col]])
end
function App:focusFirst(id)
    local rows = NAV[self.page]
    for r, row in ipairs(rows) do
        for c, bid in ipairs(row) do
            if bid == id and self.b[bid].shown then return self:focusAt(r, c) end
        end
    end
    for i = 2, #rows + 1 do -- the first control under the header, else the header's close / back
        local r = i <= #rows and i or 1
        for c, bid in ipairs(rows[r]) do
            if self.b[bid].shown then return self:focusAt(r, c) end
        end
    end
end
-- up / down: the nearest shown button (by centre x) on the next row that has one; past the last one the page scrolls
-- (the Security page's alerts have no buttons). Left / right: along the row.
function App:move(dr, dc)
    local rows, r, c = NAV[self.page], self.fRow or 1, self.fCol or 1
    if not self.focusB then return self:focusFirst() end
    if dr ~= 0 then
        local cx = self.focusB.cx + self.focusB.cw / 2
        local i = r + dr
        while rows[i] do
            local best, bd
            for j, bid in ipairs(rows[i]) do
                local b = self.b[bid]
                local d = b.shown and math.abs(b.cx + b.cw / 2 - cx)
                if d and (not bd or d < bd) then best, bd = j, d end
            end
            if best then return self:focusAt(i, best) end
            i = i + dr
        end
        if self.scrollMax > 0 then self:onMouseWheel(dr) end
        return
    end
    local row, j = rows[r], c + dc
    while row and row[j] do
        if self.b[row[j]].shown then return self:focusAt(r, j) end
        j = j + dc
    end
end
function App:onGainJoypadFocus(joypadData)
    ISPanelJoypad.onGainJoypadFocus(self, joypadData)
    self:focusFirst()
end
function App:onLoseJoypadFocus(joypadData)
    ISPanelJoypad.onLoseJoypadFocus(self, joypadData)
    self:setFocus(nil)
end
function App:onJoypadDirUp() self:move(-1, 0) end
function App:onJoypadDirDown() self:move(1, 0) end
function App:onJoypadDirLeft() self:move(0, -1) end
function App:onJoypadDirRight() self:move(0, 1) end
function App:onJoypadDown(button)
    if button == Joypad.AButton then
        local b = self.focusB
        if b and b.shown then b:forceClick() end -- the click sound; nothing when disabled (ISButton.lua forceClick)
    elseif button == Joypad.BButton then
        if self.page == "home" then self:close() else self:setPage("home") end
    end
end

function App:onMouseWheel(del)
    if self.scrollMax <= 0 then return false end
    self.scroll = self.scroll + del * math.floor(40 * self.S)
    self.freeScroll = true
    self:layout()
    return true
end

-- ---------------------------------------------------------------- actions (the server checks everything)
function App:send(cmd, args)
    args.key = self.key
    T.request(self.player, cmd, args)
end

function App:onButton(b)
    local id = b.id
    if id == "close" then return self:close() end
    if id == "back" then return self:setPage("home") end
    if TITLE[id] then return self:setPage(id) end
    if id == "map" then return self:onMap() end
    local st, act, on = self.st or {}, b.act, nil
    if act == "lock" then act = st.locked and "unlock" or "lock"
    elseif act == "sentry" then on = not st.sentry
    elseif act == "frunk" or act == "trunk" then on = not st[act]
    elseif act == "charge" then on = st.chg == "stopped" end
    App.stats.sent = App.stats.sent + 1
    self:send("appAction", { act = act, on = on })
end

-- "Show on map": vanilla world map centred on the car (ISWorldMap.lua:1500), marker drawn by App.drawMapCar
function App:onMap()
    local st = self.st
    if not (st and st.x) or not ISWorldMap.IsAllowed() then return end
    App.mapCar = { x = st.x + 0.5, y = st.y + 0.5, name = self.sName, dist = self.sDist, pn = self.playerNum, key = self.key }
    self:close()
    ISWorldMap.ShowWorldMap(App.mapCar.pn, App.mapCar.x, App.mapCar.y, 18)
end

function App:showToast(text, ok)
    local S = self.S or 1
    local l1, l2 = wrap2(text, self.width - 2 * math.floor(PAD * S) - math.floor(26 * S))
    self.toast = { text = text, l1 = l1, l2 = l2, ok = ok, untilMs = getTimestampMs() + App.TOAST_MS }
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
        if not args.why and args.on ~= nil then -- what the server did (a lid toggles what is there now)
            text = getText("IGUI_MinidoracatTesla_App_Done_" .. args.act .. (args.on and "_on" or "_off"))
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
        a.alertsWhy = args.deny and T.denyText(args.deny) -- VehicleManager said no: say why instead of "no alerts"
        a.sig = nil
        if a.S then a:read(); a:layout() end -- render reads each row's place: lay them out before the next frame
    end)
end

-- ---------------------------------------------------------------- reading
local function ageText(hours)
    local mins = math.floor(math.max(0, hours) * 60)
    if mins < 2 then return txt("AgeNow") end
    if mins < 60 then return txt("MinsAgo", tostring(mins)) end
    if mins < 48 * 60 then return txt("HoursAgo", tostring(math.floor(mins / 60))) end
    return txt("DaysAgo", tostring(math.floor(mins / 1440)))
end

local function distText(d)
    if d < 1000 then return txt("Meters", tostring(math.floor(d + 0.5))) end
    local t = math.floor(d / 100 + 0.5)
    return txt("Km", tostring(math.floor(t / 10)) .. "." .. tostring(t % 10))
end

local function enable(b, on, isOn, icon, tip)
    b:setEnable(on == true)
    b.borderColor.a = 0
    b.on, b.icon, b.tipKey = isOn == true, icon, tip
end

-- strings and button states only when something shown changes (10 Hz update; no allocation otherwise)
function App:read()
    local st, p = self.st, self.player
    local gt = getGameTime()
    local hh, mm = gt:getHour(), gt:getMinutes()
    local now = getTimestampMs()
    if self.toast and now >= self.toast.untilMs then self.toast, self.sig = nil, nil end
    -- position: every update (the player walks); a new tile or direction redoes the strings that show it
    if st and st.x and p then
        local d, ci, ang = K.bearing(p:getX(), p:getY(), st.x + 0.5, st.y + 0.5)
        self.arrowAngle = ang
        local dk = math.floor(d + 0.5) * 8 + ci
        if dk ~= self.distKey then
            self.distKey = dk
            if self.page == "home" or self.page == "location" then self.sig = nil end -- the pages that show it
            self.sDist = distText(d)
            self.sDir = d < 3 and txt("Here") or txt("Dir_" .. DIRS[ci])
            self.sDirDist = d < 3 and self.sDir or txt("DirDist", self.sDir, self.sDist)
        end
    end
    local alertsN = self.alerts and #self.alerts or -1
    local sig = self.page .. hh .. ":" .. mm .. "/" .. tostring(self.toast and self.toast.text) .. "/" .. alertsN .. "/"
        .. tostring(self.stAt) .. "/" .. tostring(self.alertsWhy)
    if sig == self.sig then return false end
    self.sig = sig
    self.sTime = string.format("%02d:%02d", hh, mm)
    local link = st and st.link
    -- status bar: the phone's network (grid up), else Bluetooth while it reaches the car, else no service
    self.grid = st ~= nil and st.grid == true
    self.sNet = self.grid and txt("Net") or (link == "bt" and txt("Bt") or txt("NoService"))
    local rec = st and st.pct ~= nil and not st.deny
    self.rec = rec
    self.sName = st and st.car and getText("IGUI_VehicleName" .. st.car) or txt("Title")
    local paint, model = App.paint(st and st.car, st and st.skin)
    self.paintName, self.model = paint.name, model
    self.carTex = carTexture(paint.name)
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
        self.sSub = txt("LastSeen", ageText(T.hours() - (st.h or 0)))
    end
    self.sSub2 = rec and not link and txt("FootOff") or nil -- why the controls are grey
    self.sBat = rec and (txt("Km", tostring(st.km)) .. sep .. tostring(st.pct) .. "%") or ""
    self.pct = rec and st.pct or 0
    self.sWhen = rec and (link and txt("JustNow") or ageText(T.hours() - (st.h or 0))) or ""
    self.sTitle = TITLE[self.page] and txt(TITLE[self.page]) or ""
    -- the home list: a grey line under each title, the state that is on in white first (the mock's <em>)
    local em, sub = self.rowEm, self.rowSub
    sub.controls = txt("ControlsSub")
    em.location, sub.location = nil, rec and self.sDirDist and (self.sDirDist .. sep .. self.sWhen) or ""
    local alerts = self.alertsWhy or (self.alerts and (#self.alerts > 0 and txt("AlertCount", tostring(#self.alerts)) or txt("NoAlerts")))
    if rec and st.sentry then em.security, sub.security = txt("Done_sentry_on"), alerts and (sep .. alerts) or ""
    elseif rec then em.security, sub.security = nil, txt("Done_sentry_off") .. (alerts and (sep .. alerts) or "")
    else em.security, sub.security = nil, alerts or "" end
    local chg = rec and st.chg
    self.chg = chg
    local state = chg == "charging" and txt("ChargingNow") or chg == "full" and txt("ChargeFull", tostring(st.target or 90))
        or chg == "nopower" and txt("ChargeNoPower") or chg == "stopped" and txt("ChargeStopped") or (rec and txt("NotPlugged"))
    self.sKw = chg == "charging" and st.kw and txt("Kw", tostring(st.kw)) or nil -- stopped / full: no power flows
    self.sEta = chg == "charging" and st.mins and txt("ToTarget", tostring(st.target or 90), tostring(st.mins)) or nil
    self.sChgState = state or self.sSub
    if chg == "charging" then
        em.charging, sub.charging = state, sep .. txt("Kw", tostring(st.kw or 0)) .. (self.sEta and (sep .. self.sEta) or "")
    else
        em.charging, sub.charging = nil, state or ""
    end
    -- buttons
    local b = self.b
    local live = rec and link ~= nil
    local locked = rec and st.locked == true
    enable(b.lock, live, locked, locked and "i_lockfill" or "i_unlock", TIP .. (locked and "Unlock" or "Lock"))
    local plugged = chg == "charging" or chg == "stopped"
    local chgTip = chg == "charging" and (TIP .. "ChargeStop") or chg and (TIP .. "ChargeStart") or (P .. "NotPlugged")
    enable(b.qcharge, live and plugged, chg == "charging", "i_bolt", chgTip)
    enable(b.charge, live, chg == "charging", nil, chgTip)
    self.sChargeBtn = chg == "charging" and txt("ChargeStop") or txt("ChargeStart")
    for _, id in ipairs(LIDS) do
        local open = rec and st[id] == true
        local tip = TIP .. id:sub(1, 1):upper() .. id:sub(2)
        enable(b["q" .. id], live, open, GRID_ICON[id], tip)
        enable(b[id], live, open, GRID_ICON[id], tip)
        b[id].sub = open and txt("Opened") or txt("TapOpen")
    end
    enable(b.flash, live, false, GRID_ICON.flash, TIP .. "Flash")
    b.flash.sub = txt("FlashSub")
    enable(b.horn, live, false, GRID_ICON.horn, TIP .. "Horn")
    b.horn.sub = txt("HornSub")
    local sentry = rec and st.sentry == true
    enable(b.sentry, live, sentry, nil, TIP .. (sentry and "SentryOff" or "SentryOn"))
    enable(b.map, rec, false, nil, TIP .. "Map")
    enable(b.close, true, false, "i_close", TIP .. "Close")
    enable(b.back, true, false, "i_back", TIP .. "Back")
    for _, id in ipairs(LIST) do enable(b[id], true, false, LIST_ICON[id], nil) end
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

-- ---------------------------------------------------------------- layout (design units x S; y below the header
-- is in page coordinates, drawn and placed minus self.dy)
function App:layout()
    local tm = getTextManager()
    self.tipKey = nil
    local pn = self.playerNum
    local S = math.min(tm:getFontHeight(UIFont.Small) / 19, (getPlayerScreenWidth(pn) - 8) / W)
    self.S = S
    local FH, FHM, FHL = tm:getFontHeight(UIFont.Small), tm:getFontHeight(UIFont.Medium), tm:getFontHeight(UIFont.Large)
    self.FH, self.FHM, self.FHL = FH, FHM, FHL
    self.A = T.HUDAtlas[2] -- 2x at every S: the 24-unit icons and the wordmark stay sharp at S = 1
    self.tex = getTexture(self.A.tex)
    self.f = S / 2
    self.arrowTex = getTexture("media/textures/MinidoracatTesla/HUD/app_arrow" .. (S >= 1.5 and 2 or 1) .. "x.png")
    local function u(n) return math.floor(n * S + 0.5) end
    local sw, sh = getPlayerScreenWidth(pn), getPlayerScreenHeight(pn)
    local w = math.min(math.floor(W * S), sw - 8)
    local pad = math.floor(PAD * S)
    self.pad = pad
    for _, b in ipairs(self.buttons) do b.shown = false end
    local function place(id, x, y, bw, bh)
        local b = self.b[id]
        b.shown, b.cx, b.cy, b.cw, b.ch = true, math.floor(x), math.floor(y), math.floor(bw), math.floor(bh)
        return b
    end
    local page = self.page
    local y = u(12)
    self.yBar = y
    y = y + FH + u(14)
    if page == "home" then
        local cs = u(28)
        self.yName = y
        place("close", w - pad - cs + u(6), y + math.floor((FHL - cs) / 2), cs, cs)
        self.sHead = fitText(self.sName, w - 2 * pad - cs, UIFont.Large)
        y = y + FHL + u(4)
    else
        local bs = u(32)
        place("back", pad - u(8), y, bs, bs)
        self.xTitle = pad - u(8) + bs + u(4)
        self.yName = y + math.floor((bs - FHM) / 2)
        self.sHead = fitText(self.sTitle, w - pad - self.xTitle, UIFont.Medium)
        y = y + bs + u(12)
    end
    self.yBody = y
    local cw -- the car picture's width
    local tw = w - 2 * pad
    if page == "home" then
        self.yBat = y
        self.sBatFit = fitText(self.sBat, tw - u(30))
        y = y + FH + u(2)
        self.ySub, self.sSubFit = y, fitText(self.sSub, tw)
        y = y + FH
        self.sSub2Fit = self.sSub2 and fitText(self.sSub2, tw)
        if self.sSub2 then self.ySub2 = y; y = y + FH end
        cw = math.floor(w * 0.68)
        y = y + u(12)
        self.yCar = y
        y = y + math.floor(cw / 2) + u(8)
        local slot, qw, qh = tw / 4, u(48), u(40)
        for i, id in ipairs(QUICK) do place(id, pad + (i - 0.5) * slot - qw / 2, y, qw, qh) end
        y = y + qh + u(10)
        local rh = math.max(FHM + u(2) + FH, u(36)) + u(20)
        local rx = pad + u(40)
        local rw = w - rx - pad - u(22)
        for _, id in ipairs(LIST) do
            local b = place(id, pad / 2, y, w - pad, rh) -- inset: the focus ring stays inside the phone
            b.sTitle = fitText(txt(TITLE[id]), rw, UIFont.Medium)
            local e = self.rowEm[id]
            b.sEm = e and fitText(e, rw) or nil
            b.emW = b.sEm and tm:MeasureStringX(UIFont.Small, b.sEm) or 0
            b.sSub = fitText(self.rowSub[id] or "", rw - b.emW)
            y = y + rh
        end
        y = y + u(8)
        self.yLine = y
        y = y + 1 + u(16)
        local A = self.A
        local wm, trim = A["wm_" .. self.model], A["trim_" .. self.model]
        self.yWm = y
        y = y + (wm and math.floor(wm[4] * self.f) or 0) + u(8)
        self.yTrim = y
        y = y + (trim and math.floor(trim[4] * self.f) or 0) + u(6)
    elseif page == "controls" then
        cw = math.floor(w * 0.56)
        y = y + u(4)
        self.yCar = y
        y = y + math.floor(cw / 2) + u(16)
        local gap = u(12)
        local cellW = math.floor((tw - gap) / 2)
        local cellH = u(14) + u(22) + u(8) + FH + u(2) + FH + u(12)
        for i, id in ipairs(GRID) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local b = place(id, pad + col * (cellW + gap), y + row * (cellH + gap), cellW, cellH)
            b.sTitle = fitText(txt(id:sub(1, 1):upper() .. id:sub(2)), cellW - u(28))
            b.sSubFit = fitText(b.sub, cellW - u(28))
        end
        y = y + 2 * cellH + gap + u(16)
    elseif page == "location" then
        if self.rec and self.sDist then
            self.yArrow = y + u(28)
            y = y + u(56) + u(14)
            self.yDist, self.sDistFit = y, fitText(self.sDist, tw, UIFont.Large)
            y = y + FHL + u(2)
            self.yDir, self.sDirFit = y, fitText(self.sDir, tw)
            y = y + FH + u(2)
            self.yWhen, self.sWhenFit = y, fitText(txt("Location") .. getText("IGUI_MinidoracatTesla_Sep") .. self.sWhen, tw)
            y = y + FH + u(18)
        else
            self.yArrow = nil
            self.yMsg, self.sMsg = y, fitText(self.sSub, tw)
            y = y + FH + u(18)
        end
        if ISWorldMap.IsAllowed() then
            local b = place("map", pad, y, tw, u(40))
            b.sTitle = fitText(txt("Map"), tw - u(16))
            y = y + u(40) + u(14)
        end
    elseif page == "security" then
        local rh = math.max(FHM + u(2) + FH, u(36)) + u(20)
        local b = place("sentry", pad / 2, y, w - pad, rh)
        local rw = tw - u(52)
        b.sTitle = fitText(txt("SentryMode"), rw, UIFont.Medium)
        b.sSub = fitText(self.rec and txt(self.b.sentry.on and "Done_sentry_on" or "Done_sentry_off") or self.sSub, rw)
        y = y + rh + u(10)
        self.yAlertsHead, self.sAlertsHead = y, fitText(txt("AlertsTitle"), tw)
        y = y + FH + u(10)
        local rows = self.alerts
        local ah = 2 * FH + u(14)
        if rows and #rows > 0 then
            local ax = u(28)
            for _, r in ipairs(rows) do
                r.y = y
                r.sTime = r.time
                r.sTitle = fitText(r.title, tw - ax - tm:MeasureStringX(UIFont.Small, r.time) - u(8))
                r.sDetail = fitText(r.detail, tw - ax)
                y = y + ah
            end
        else
            self.yAlertsMsg = y
            self.sAlertsMsg = fitText(self.alertsWhy or (rows and txt("NoAlerts") or txt("Loading")), tw)
            y = y + FH + u(10)
        end
        y = y + u(6)
    elseif page == "charging" then
        self.yState, self.sStateFit = y, fitText(self.sChgState, tw, UIFont.Large)
        y = y + FHL + u(6)
        self.yBat, self.sBatFit = y, fitText(self.sBat, tw - u(30))
        y = y + FH + u(12)
        self.yKw, self.sKwFit = self.sKw and y, self.sKw and fitText(self.sKw, tw)
        if self.sKw then y = y + FH + u(4) end
        self.yEta, self.sEtaFit = self.sEta and y, self.sEta and fitText(self.sEta, tw)
        if self.sEta then y = y + FH + u(4) end
        y = y + u(14)
        if self.chg == "charging" or self.chg == "stopped" then
            local b = place("charge", pad, y, tw, u(40))
            b.sTitle = fitText(self.sChargeBtn, tw - u(16))
            y = y + u(40) + u(14)
        end
    end
    if cw then self.carX, self.carW, self.carH = math.floor((w - cw) / 2), cw, math.floor(cw / 2) end
    -- the toast sits at the bottom, outside the scrolled part
    local toastH = self.toast and (FH * (self.toast.l2 and 2 or 1) + u(16)) or 0
    local bottom = u(12)
    local h = math.min(y + toastH + bottom, sh - 8)
    self.yBodyEnd = h - toastH - bottom
    self.yToast = self.toast and (self.yBodyEnd + u(8)) or nil
    self.scrollMax = math.max(0, y - self.yBodyEnd)
    local fb = self.focusB -- the focused control in view (a toast shortens the body, a page grows)
    if fb and fb.shown and fb.cy >= self.yBody and not self.freeScroll then
        if fb.cy - self.scroll < self.yBody then self.scroll = fb.cy - self.yBody end
        if fb.cy + fb.ch - self.scroll > self.yBodyEnd then self.scroll = fb.cy + fb.ch - self.yBodyEnd end
    end
    self.scroll = math.max(0, math.min(self.scroll, self.scrollMax))
    self.dy = self.scroll
    for _, b in ipairs(self.buttons) do
        local show = b.shown
        if show then
            local by = b.cy >= self.yBody and b.cy - self.dy or b.cy
            b:setX(b.cx); b:setY(by); b:setWidth(b.cw); b:setHeight(b.ch)
            -- only when wholly inside the visible body: the stencil clips drawing, not clicks (UIElement.java:1875-1889)
            show = b.cy < self.yBody or (by >= self.yBody and by + b.ch <= self.yBodyEnd)
        end
        b:setVisible(show)
    end
    self:setWidth(w)
    self:setHeight(h)
    -- right half of this player's screen, centred vertically, like a phone held up
    self:setX(getPlayerScreenLeft(pn) + math.max(4, sw - w - u(40)))
    self:setY(getPlayerScreenTop(pn) + math.max(4, math.floor((sh - h) / 2)))
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

-- a t-px rounded frame (no card fill: the inside is the phone's background again)
local function frame(self, x, y, w, h, r, t, c, a)
    HUD.rrect(self, x, y, w, h, r, c, a)
    HUD.rrect(self, x + t, y + t, w - 2 * t, h - 2 * t, math.max(0, r - t), C.bg, 1)
end
local function focusRing(self, b)
    local S = self.S
    local g = math.floor(3 * S)
    frame(self, b.x - g, b.y - g, b.width + 2 * g, b.height + 2 * g, 8 * S, math.max(1, math.floor(2 * S)), C.text, 1)
end
-- an 18-unit atlas icon scaled to `size` units, centred on (cx, cy)
local function icon(self, name, cx, cy, size, c, a)
    local S = self.S
    HUD.spr(self, self.A[name], cx - size * S / 2, cy - size * S / 2, c, a, size / 18)
end
local function batteryBar(self, x, y)
    local S = self.S
    local bw, bh = math.floor(22 * S), math.max(2, math.floor(9 * S))
    local by = y + math.floor((self.FH - bh) / 2)
    HUD.rrect(self, x, by, bw, bh, 2 * S, C.weak, 1)
    HUD.rrect(self, x, by, math.max(2 * S, bw * self.pct / 100), bh, 2 * S, self.pct < 20 and C.warn or C.text2, 1)
end

function App:prerender()
    if not self.S then return end
    self.n = 0
    local S, w, A, o, pad = self.S, self.width, self.A, self.dy, self.pad
    HUD.rrect(self, 0, 0, w, self.height, 24 * S, C.bg, 0.98)
    if self.grid then -- signal bars
        local bx = w - pad - math.floor(16 * S)
        local by = self.yBar + (self.FH - 12 * S) / 2
        for i = 0, 3 do
            local hh = (4 + i * 2.7) * S
            HUD.rect(self, bx + i * 4.3 * S, by + 12 * S - hh, 3 * S, hh, C.text, 1)
        end
    end
    for _, id in ipairs(HEAD) do
        local b = self.b[id]
        if b:isVisible() then
            if b.joypadFocused then focusRing(self, b) end
            icon(self, b.icon, b.x + b.width / 2, b.y + b.height / 2, 20, id == "close" and C.text2 or C.text, 1)
        end
    end
    flush(self)
    local clip = self.scrollMax > 0
    if clip then self:setStencilRect(0, self.yBody, w, self.yBodyEnd - self.yBody) end
    local page = self.page
    for _, b in ipairs(self.buttons) do
        if b.joypadFocused and b:isVisible() and b.cy >= self.yBody then focusRing(self, b) end
    end
    if page == "home" then
        if self.rec then batteryBar(self, pad, self.yBat - o) end
        for _, id in ipairs(QUICK) do
            local b = self.b[id]
            local c = not b.enable and C.weak or (b.on and C.text or C.text2)
            icon(self, b.icon, b.x + b.width / 2, b.y + b.height / 2, 24, c, 1)
        end
        for _, id in ipairs(LIST) do
            local b = self.b[id]
            local cy = b.cy - o + b.ch / 2
            icon(self, b.icon, pad + 10 * S, cy, 20, C.text2, 1)
            icon(self, "i_chev", w - pad - 8 * S, cy, 16, C.weak, 1)
        end
        HUD.rect(self, pad, self.yLine - o, w - 2 * pad, 1, C.line, 1)
        local wm, trim = A["wm_" .. self.model], A["trim_" .. self.model]
        if wm then HUD.spr(self, wm, pad, self.yWm - o, C.text, 1) end
        if trim then HUD.spr(self, trim, pad, self.yTrim - o, C.text2, 1) end
    elseif page == "controls" then
        for _, id in ipairs(GRID) do
            local b = self.b[id]
            local by = b.cy - o
            frame(self, b.cx, by, b.cw, b.ch, 6 * S, 1, b.on and b.enable and C.text or C.line, 1)
            icon(self, b.icon, b.cx + 14 * S + 11 * S, by + 14 * S + 11 * S, 22, b.enable and C.text or C.weak, 1)
        end
    elseif page == "security" then
        local b = self.b.sentry
        local tw, th = math.floor(40 * S), math.floor(22 * S)
        local tx, ty = w - pad - tw, b.cy - o + math.floor((b.ch - th) / 2)
        local a = b.enable and 1 or 0.4
        HUD.rrect(self, tx, ty, tw, th, th / 2, b.on and C.blue or C.weak, a)
        local k = th - math.floor(4 * S)
        HUD.rrect(self, b.on and (tx + tw - k - 2 * S) or (tx + 2 * S), ty + 2 * S, k, k, k / 2, b.on and C.white or C.text2, a)
    elseif page == "charging" then
        if self.rec then batteryBar(self, pad, self.yBat - o) end
    end
    for _, id in ipairs(MAIN) do -- the main actions: blue
        local b = self.b[id]
        if b.shown and BTN[id][1] == page then HUD.rrect(self, b.cx, b.cy - o, b.cw, b.ch, 6 * S, C.blue, b.enable and 1 or 0.4) end
    end
    flush(self)
    if self.carW and (page == "home" or page == "controls") and self.carTex then
        self.javaObject:DrawTextureScaled(self.carTex, self.carX, self.yCar - o, self.carW, self.carH, self.rec and 1 or 0.5)
    end
    if clip then self:clearStencilRect() end
    if self.yToast then
        local t = self.toast
        icon(self, t.ok and "i_check" or "i_warn", pad + 9 * S, self.yToast + (t.l2 and self.FH or self.FH / 2), 18, t.ok and C.ok or C.warn, 1)
        flush(self)
    end
end

function App:render()
    if not self.S then return end
    local S, w, o, pad = self.S, self.width, self.dy, self.pad
    local jo, c, c2, cw = self.javaObject, C.text, C.text2, C.weak
    local Sm = UIFont.Small
    jo:DrawText(Sm, self.sTime, pad, self.yBar, c[1], c[2], c[3], 1)
    self:drawTextRight(self.sNet, w - pad - (self.grid and math.floor(22 * S) or 0), self.yBar, c[1], c[2], c[3], 1, Sm)
    local page = self.page
    if page == "home" then
        jo:DrawText(UIFont.Large, self.sHead, pad, self.yName, c[1], c[2], c[3], 1)
    else
        jo:DrawText(UIFont.Medium, self.sHead, self.xTitle, self.yName, c[1], c[2], c[3], 1)
    end
    local clip = self.scrollMax > 0
    if clip then self:setStencilRect(0, self.yBody, w, self.yBodyEnd - self.yBody) end
    if page == "home" then
        jo:DrawText(Sm, self.sBatFit, pad + math.floor(30 * S), self.yBat - o, c2[1], c2[2], c2[3], 1)
        jo:DrawText(Sm, self.sSubFit, pad, self.ySub - o, c2[1], c2[2], c2[3], 1)
        if self.sSub2Fit then jo:DrawText(Sm, self.sSub2Fit, pad, self.ySub2 - o, c2[1], c2[2], c2[3], 1) end
        local rx = pad + math.floor(40 * S)
        for _, id in ipairs(LIST) do
            local b = self.b[id]
            local ty = b.cy - o + math.floor((b.ch - self.FHM - math.floor(2 * S) - self.FH) / 2)
            jo:DrawText(UIFont.Medium, b.sTitle, rx, ty, c[1], c[2], c[3], 1)
            local sy = ty + self.FHM + math.floor(2 * S)
            if b.sEm then jo:DrawText(Sm, b.sEm, rx, sy, c[1], c[2], c[3], 1) end
            jo:DrawText(Sm, b.sSub, rx + b.emW, sy, c2[1], c2[2], c2[3], 1)
        end
    elseif page == "controls" then
        for _, id in ipairs(GRID) do
            local b = self.b[id]
            local tx, ty = b.cx + math.floor(14 * S), b.cy - o + math.floor(44 * S)
            local tc = b.enable and c or cw
            jo:DrawText(Sm, b.sTitle, tx, ty, tc[1], tc[2], tc[3], 1)
            local sc = b.enable and c2 or cw
            jo:DrawText(Sm, b.sSubFit, tx, ty + self.FH + math.floor(2 * S), sc[1], sc[2], sc[3], 1)
        end
    elseif page == "location" then
        if self.yArrow then
            jo:DrawTextureAngle(self.arrowTex, w / 2, self.yArrow - o, self.arrowAngle or 0, c[1], c[2], c[3], 1)
            self:drawTextCentre(self.sDistFit, w / 2, self.yDist - o, c[1], c[2], c[3], 1, UIFont.Large)
            self:drawTextCentre(self.sDirFit, w / 2, self.yDir - o, c2[1], c2[2], c2[3], 1, Sm)
            self:drawTextCentre(self.sWhenFit, w / 2, self.yWhen - o, c2[1], c2[2], c2[3], 1, Sm)
        else
            self:drawTextCentre(self.sMsg, w / 2, self.yMsg - o, c2[1], c2[2], c2[3], 1, Sm)
        end
    elseif page == "security" then
        local b = self.b.sentry
        local ty = b.cy - o + math.floor((b.ch - self.FHM - math.floor(2 * S) - self.FH) / 2)
        jo:DrawText(UIFont.Medium, b.sTitle, pad, ty, c[1], c[2], c[3], 1)
        jo:DrawText(Sm, b.sSub, pad, ty + self.FHM + math.floor(2 * S), c2[1], c2[2], c2[3], 1)
        jo:DrawText(Sm, self.sAlertsHead, pad, self.yAlertsHead - o, c2[1], c2[2], c2[3], 1)
        local rows = self.alerts
        if rows and #rows > 0 then
            local ax = pad + math.floor(28 * S)
            for _, r in ipairs(rows) do
                local ry = r.y - o + math.floor(7 * S)
                if r.icon then self:drawTextureScaled(r.icon, pad, ry, 18 * S, 18 * S, 1, 1, 1, 1) end
                jo:DrawText(Sm, r.sTitle, ax, ry, c[1], c[2], c[3], 1)
                self:drawTextRight(r.sTime, w - pad, ry, c2[1], c2[2], c2[3], 1, Sm)
                jo:DrawText(Sm, r.sDetail, ax, ry + self.FH, c2[1], c2[2], c2[3], 1)
            end
        else
            jo:DrawText(Sm, self.sAlertsMsg, pad, self.yAlertsMsg - o, c2[1], c2[2], c2[3], 1)
        end
    elseif page == "charging" then
        jo:DrawText(UIFont.Large, self.sStateFit, pad, self.yState - o, c[1], c[2], c[3], 1)
        jo:DrawText(Sm, self.sBatFit, pad + math.floor(30 * S), self.yBat - o, c2[1], c2[2], c2[3], 1)
        if self.sKwFit then jo:DrawText(Sm, self.sKwFit, pad, self.yKw - o, c[1], c[2], c[3], 1) end
        if self.sEtaFit then jo:DrawText(Sm, self.sEtaFit, pad, self.yEta - o, c2[1], c2[2], c2[3], 1) end
    end
    for _, id in ipairs(MAIN) do
        local b = self.b[id]
        if b.shown and BTN[id][1] == page then
            self:drawTextCentre(b.sTitle, b.cx + b.cw / 2, b.cy - o + (b.ch - self.FH) / 2, 1, 1, 1, b.enable and 1 or 0.5, Sm)
        end
    end
    if clip then self:clearStencilRect() end
    if self.yToast then
        local t = self.toast
        local tc = t.ok and c or C.warn
        local tx = pad + math.floor(26 * S)
        jo:DrawText(Sm, t.l1, tx, self.yToast, tc[1], tc[2], tc[3], 1)
        if t.l2 then jo:DrawText(Sm, t.l2, tx, self.yToast + self.FH, tc[1], tc[2], tc[3], 1) end
    end
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
    local b = C.blue
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
    if m then App.open(m.pn, m.key, "location") end -- back to the page that opened the map
    return r
end

return App
