-- Owner notifications for sentry and camp. Online owner: immediate "alert". Offline owner: kept in the server-only
-- store (Store.lua "inbox"; never Global ModData, which any client can fetch), at most MAX entries per
-- account, delivered and cleared when the client sends "inboxPull" after login (first OnTick after OnGameStart).
-- Accounts are T.account names: a split-screen guest has none, so it neither gets nor pulls anyone's alerts.
if isClient() then return end
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Store"

local T = MinidoracatTesla
T.Inbox = T.Inbox or {}
T.ServerCommands = T.ServerCommands or {}
local I = T.Inbox

I.MAX = 20

-- Online player by account name. getOnlinePlayers is empty in SP (LuaManager.java:4457-4463).
function I.online(username)
    if not username then return nil end
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        if T.account(p) == username then return p end
    end
    if not isServer() then
        local p = getSpecificPlayer(0)
        if p and p:getUsername() == username then return p end
    end
    return nil
end

-- One event record; plain strings and numbers only (sent as-is, stored as-is). `key` = the car's keyId: the phone
-- app's alert list (Remote.lua) is per car.
function I.entry(vehicle, kind, what, actor, partId)
    local gt = getGameTime()
    local script = vehicle:getScript()
    return {
        at = gt:getWorldAgeHours(), hh = gt:getHour(), mm = gt:getMinutes(),
        car = script and (script:getCarModelName() or script:getName()) or "",
        kind = kind, what = what, part = partId,
        by = actor and actor:getUsername() or nil,
        x = math.floor(vehicle:getX()), y = math.floor(vehicle:getY()), key = vehicle:getKeyId(),
    }
end

function I.store(username, e)
    local data = T.Store.get("inbox")
    local list = data[username]
    if not list then
        list = {}
        data[username] = list
    end
    list[#list + 1] = e
    while #list > I.MAX do table.remove(list, 1) end
end

-- username nil (sentry armed by a split-screen guest, T.account): nobody to tell, but the car's own alert list
-- (the phone app's, Remote.logAlert) still gets it
function I.notify(username, e)
    local log = T.Remote and T.Remote.logAlert
    if log then log(e) end
    if not username then return end
    local p = I.online(username)
    if p then
        T.send(p, "alert", e)
    else
        I.store(username, e)
    end
    T.log("notify " .. tostring(username) .. " " .. tostring(e.kind) .. " " .. tostring(e.what)
        .. (p and " online" or " stored"))
end

T.ServerCommands.inboxPull = function(player, args)
    local name = T.account(player)
    if not name then return end
    local data = T.Store.get("inbox")
    local list = data[name]
    if not list or #list == 0 then return end
    data[name] = nil
    T.send(player, "inbox", { list = list })
    T.log("inbox delivered " .. #list .. " to " .. tostring(name))
end
