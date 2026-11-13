-- Summon Circle: core helpers, saved variables, event dispatch.
local ADDON, ns = ...
SummonCircle = ns -- global handle for /dump debugging

ns.PREFIX = "SUMMONCIRCLE"
ns.SHARD_ITEM = 6265   -- Soul Shard item
ns.SUMMON_SPELL = 698  -- Ritual of Summoning

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

-- Prefer namespaced APIs where Midnight moved them; fall back to globals.
ns.API = {
  SendChat   = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage,
  Invite     = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit,
  Uninvite   = (C_PartyInfo and C_PartyInfo.UninviteUnit) or UninviteUnit,
  ConvertToRaid = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid,
  ItemCount  = (C_Item and C_Item.GetItemCount) or GetItemCount,
  SpellName  = function(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
  end,
}

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
function ns.Print(...)
  print("|cff9482c9Summon Circle|r:", ...)
end

-- Midnight "secret values": anything we can't inspect, we ignore.
function ns.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

-- WoW Forever has no realms: names are unique "First Last". Strip any
-- "-Realm" suffix the game attaches so every name is a plain "First Last".
function ns.Full(name)
  if not name or name == "" then return nil end
  return (name:gsub("%-.*$", ""))
end

-- Leader/assist checks that also cover dungeon-finder ("instance") groups.
local INSTANCE = LE_PARTY_CATEGORY_INSTANCE
function ns.IsGroupLeader(unit)
  if UnitIsGroupLeader(unit) then return true end
  return INSTANCE ~= nil and UnitIsGroupLeader(unit, INSTANCE) == true
end
function ns.IsGroupAssistant(unit)
  if UnitIsGroupAssistant(unit) then return true end
  return INSTANCE ~= nil and UnitIsGroupAssistant(unit, INSTANCE) == true
end

function ns.Short(name)
  return name and ns.Full(name) or "?"
end

-- One way to turn any unit into a name key, used for me AND everyone in
-- the group, so two-word names ("Ash Lock") always match up.
function ns.UnitKey(unit)
  local n = GetUnitName(unit, true)
  if not n or ns.IsSecret(n) or n == "" or n == UNKNOWNOBJECT then return nil end
  return ns.Full(n)
end

function ns.Me()
  if not ns.me then ns.me = ns.UnitKey("player") end
  return ns.me or ns.Full(UnitName("player"))
end

function ns.Money(c)
  c = math.floor(c or 0)
  local g, s, cc = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t = {}
  if g > 0 then t[#t + 1] = g .. "g" end
  if s > 0 then t[#t + 1] = s .. "s" end
  if cc > 0 or #t == 0 then t[#t + 1] = cc .. "c" end
  return table.concat(t)
end

-- "30s", "1g20s", "50" (plain number = silver)
function ns.ParseMoney(str)
  if not str then return nil end
  str = str:lower():gsub("%s", "")
  if str:match("^%d+$") then return tonumber(str) * 100 end
  local total, matched = 0, false
  for n, u in str:gmatch("(%d+)([gsc])") do
    total = total + tonumber(n) * (u == "g" and 10000 or u == "s" and 100 or 1)
    matched = true
  end
  return matched and total or nil
end

function ns.Clock(sec)
  sec = math.max(0, math.floor(sec or 0))
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

function ns.SummonName()
  return ns.API.SpellName(ns.SUMMON_SPELL) or "Ritual of Summoning"
end

function ns.IsSummonSpell(id)
  if not id or ns.IsSecret(id) then return false end
  if id == ns.SUMMON_SPELL then return true end
  return ns.API.SpellName(id) == ns.SummonName()
end

function ns.GetShards()
  local n = ns.API.ItemCount(ns.SHARD_ITEM) or 0
  if n == 0 and Enum.PowerType and Enum.PowerType.SoulShards then
    local ok, p = pcall(UnitPower, "player", Enum.PowerType.SoulShards)
    if ok and type(p) == "number" and not ns.IsSecret(p) and p > 0 then n = p end
  end
  return n
end

---------------------------------------------------------------------------
-- Event dispatch: ns:On(event, fn) — handlers run in registration order.
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    frame:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
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

frame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event]) do
    local ok, err = pcall(fn, ...)
    if not ok then ns.ReportError(event .. ": " .. tostring(err)) end
  end
end)

ns:On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  SummonCircleDB = SummonCircleDB or {}
  for k, v in pairs(DEFAULTS) do
    if SummonCircleDB[k] == nil then SummonCircleDB[k] = deepcopy(v) end
  end
  ns.db = SummonCircleDB
  C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
end)
