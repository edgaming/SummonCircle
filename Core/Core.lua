-- Summon Circle: namespace, saved settings, WoW event dispatch and the
-- internal event bus.
--
-- Two kinds of events:
--   ns.On(event, fn)      WoW events (GROUP_ROSTER_UPDATE, CHAT_MSG_WHISPER, ...)
--   ns.Listen(name, fn)   our own events, raised with ns.Emit(name, ...)
-- Domain modules never call the UI directly; they ns.Update() and the
-- window refreshes itself.
local ADDON, ns = ...
SummonCircle = ns -- global handle for /dump debugging

ns.ADDON = ADDON

-- Modules live on the namespace: ns:Module("Queue") returns ns.Queue.
function ns:Module(name)
  local m = rawget(self, name)
  if not m then
    m = {}
    self[name] = m
  end
  return m
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
local DEFAULTS = {
  price = 3000,                          -- copper (30s)
  keywords = { "inv", "invite", "summon", "+" }, -- whisper triggers (whole message, case-insensitive)
  channels = false,                      -- [channel name] = true; false = auto (Trade)
  adText = "WTS summons to {city} - {price} - whisper 'inv' for instant invite{queue}",
  adCooldown = 60,                       -- seconds between ads
  thanks = "Thanks",
  summonTimeout = 120,                   -- seconds before an unaccepted summon resets
  unpaidTimeout = 180,                   -- seconds after arrival before the row turns red
  blacklist = {},                        -- ["First Last"] = { by, at, reason, del }
  lifetime = { copper = 0, summons = 0 },
  ui = { shown = true },
}

local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = deepcopy(x) end
  return t
end

---------------------------------------------------------------------------
-- Output and error reporting
---------------------------------------------------------------------------
function ns.Print(...)
  print("|cff9482c9Summon Circle|r:", ...)
end

-- WoW hides Lua errors by default, so also print each distinct error once.
local reported = {}
function ns.ReportError(err)
  err = tostring(err)
  geterrorhandler()(err)
  if not reported[err] then
    reported[err] = true
    print("|cff9482c9Summon Circle|r |cffff4040error (please screenshot):|r " .. err)
  end
end

-- Wrap a callback so its errors get reported instead of silently swallowed.
function ns.Safe(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.ReportError(err) end
  end
end

---------------------------------------------------------------------------
-- WoW event dispatch: handlers run in registration order (= file load order).
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local wowHandlers = {}

function ns.On(event, fn)
  if not wowHandlers[event] then
    wowHandlers[event] = {}
    frame:RegisterEvent(event)
  end
  table.insert(wowHandlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(wowHandlers[event]) do
    local ok, err = pcall(fn, ...)
    if not ok then ns.ReportError(event .. ": " .. tostring(err)) end
  end
end)

---------------------------------------------------------------------------
-- Internal event bus
---------------------------------------------------------------------------
local listeners = {}

function ns.Listen(name, fn)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], fn)
end

function ns.Emit(name, ...)
  for _, fn in ipairs(listeners[name] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then ns.ReportError(name .. ": " .. tostring(err)) end
  end
end

-- "Something the window shows has changed."
function ns.Update()
  ns.Emit("UPDATE")
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  SummonCircleDB = SummonCircleDB or {}
  for k, v in pairs(DEFAULTS) do
    if SummonCircleDB[k] == nil then SummonCircleDB[k] = deepcopy(v) end
  end
  ns.db = SummonCircleDB
end)

-- Small things the window shows that can change without any of our events.
ns.On("BAG_UPDATE_DELAYED", function() ns.Update() end)   -- shard count
ns.On("CHANNEL_UI_UPDATE", function() ns.Update() end)    -- joined channels
