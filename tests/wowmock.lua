-- Minimal fake WoW API, enough to load and drive the addon.
ERRORS = {}
SENT = {}
CHAT = {}
local timers = {}
EVENTS = {}

local function noop() end
local FrameMT = {}
FrameMT.__index = function(t, k)
  local v = rawget(FrameMT, k)
  if v then return v end
  return noop
end
local function newFrame(name)
  local f = setmetatable({ _shown = true, _scripts = {}, _attrs = {}, _text = "", _events = {} }, FrameMT)
  if name then _G[name] = f end
  return f
end
function FrameMT.Show(f) f._shown = true end
function FrameMT.Hide(f) f._shown = false end
function FrameMT.SetShown(f, v) f._shown = not not v end
function FrameMT.IsShown(f) return f._shown end
function FrameMT.SetText(f, t) f._text = t end
function FrameMT.GetText(f) return f._text end
function FrameMT.SetScript(f, k, fn) f._scripts[k] = fn end
function FrameMT.GetScript(f, k) return f._scripts[k] end
function FrameMT.SetAttribute(f, k, v) f._attrs[k] = v end
function FrameMT.GetAttribute(f, k) return f._attrs[k] end
function FrameMT.RegisterEvent(f, e) f._events[e] = true; EVENTS[e] = EVENTS[e] or {}; table.insert(EVENTS[e], f) end
function FrameMT.CreateFontString(f) return newFrame() end
function FrameMT.CreateTexture(f) return newFrame() end
function FrameMT.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function FrameMT.HasFocus() return false end
function FrameMT.GetChecked(f) return f._checked end
function FrameMT.SetChecked(f, v) f._checked = v end
function FrameMT.IsEnabled(f) return f._enabled ~= false end
function FrameMT.Enable(f) f._enabled = true end
function FrameMT.Disable(f) f._enabled = false end
function FrameMT.SetEnabled(f, v) f._enabled = v end
function FrameMT.StartMoving() end

function CreateFrame(kind, name, parent, template) return newFrame(name) end
UIParent = newFrame("UIParent")
RaidWarningFrame = newFrame()

function FireEvent(e, ...)
  for _, f in ipairs(EVENTS[e] or {}) do
    local h = f._scripts.OnEvent
    if h then h(f, e, ...) end
  end
end

C_Timer = {
  NewTicker = function(sec, fn) table.insert(timers, fn); return {} end,
  After = function(sec, fn) table.insert(timers, fn) end,
}
function RunTimers(n)
  for _ = 1, (n or 1) do
    local list = {}
    for i, fn in ipairs(timers) do list[i] = fn end
    for _, fn in ipairs(list) do
      local ok, err = pcall(fn)
      if not ok then table.insert(ERRORS, "timer: " .. tostring(err)) end
    end
  end
end

-- Group model
ME_NAME = "Ash Lock"
GROUP = {}         -- list of { name=, leader=bool, assist=bool }
RAID = false
local function unitName(unit)
  if unit == "player" then return ME_NAME end
  local i = tonumber((unit or ""):match("^party(%d)$"))
  if i then
    local others = {}
    for _, m in ipairs(GROUP) do if m.name ~= ME_NAME then others[#others+1] = m end end
    return others[i] and others[i].name
  end
  i = tonumber((unit or ""):match("^raid(%d+)$"))
  if i then return GROUP[i] and GROUP[i].name end
  return nil
end
local function member(unit)
  local n = unitName(unit)
  for _, m in ipairs(GROUP) do if m.name == n then return m end end
end
function IsInGroup() return #GROUP > 0 end
function IsInRaid() return RAID and #GROUP > 0 end
function GetNumGroupMembers() return #GROUP end
function UnitExists(u) return unitName(u) ~= nil end
function UnitIsConnected() return true end
function UnitName(u) return unitName(u) end
function GetUnitName(u, full) return unitName(u) end
function UnitFullName(u) return unitName(u), "Realm" end
function UnitIsGroupLeader(u, cat) if cat then return false end local m = member(u); return m and m.leader or false end
function UnitIsGroupAssistant(u, cat) if cat then return false end local m = member(u); return m and m.assist or false end
function GetRaidRosterInfo(i)
  local m = GROUP[i]; if not m then return end
  local class = m.class or "WARLOCK"
  return m.name, m.leader and 2 or (m.assist and 1 or 0), 1, 60, class, class, m.zone or "Undercity", true
end
function UnitIsAFK() return false end
function UnitPower() return 0 end
function GetNormalizedRealmName() return "CAMWOWUS2Realm8PvP" end
function Ambiguate(name, mode) return (name:gsub("%-[^%-]+$", "")) end
function GetRealZoneText() return "Undercity" end
function GetServerTime() return os.time() end
local t0 = os.clock()
function GetTime() return 1000 + (os.clock() - t0) end
function InCombatLockdown() return false end
function GetCVarBool() return true end
function GetChannelList() return 1, "General - Undercity", false, 2, "Trade - City", false end
function IsInGroupCat() end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function geterrorhandler() return function(e) table.insert(ERRORS, tostring(e)) end end
function print(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end CHAT[#CHAT+1] = table.concat(t, " ") end
function PlaySound() end
function RaidNotice_AddMessage(_, text) CHAT[#CHAT+1] = "[RW] " .. text end
function InitiateTrade() end
function PromoteToAssistant(u) local m = member(u); if m then m.assist = true end end
function UninviteUnit() end
function ConvertToRaid() RAID = true end
function SendChatMessage(text, kind, _, target) SENT[#SENT+1] = { kind = kind, text = text, target = target } end
function GetTargetTradeMoney() return 0 end
ChatTypeInfo = { RAID_WARNING = {} }
SOUNDKIT = { RAID_WARNING = 1 }
LE_PARTY_CATEGORY_INSTANCE = 2
UNKNOWNOBJECT = "Unknown"
ERR_TRADE_COMPLETE = "Trade complete."
SlashCmdList = {}
Enum = { PowerType = { SoulShards = 7 }, SendAddonMessageResult = { AddonMessageThrottle = 3 } }
C_AddOns = { GetAddOnMetadata = function() return "test" end }
C_Item = { GetItemCount = function() return 22 end }
C_Spell = { GetSpellName = function(id) return id == 698 and "Ritual of Summoning" or "Other" end }
C_PartyInfo = { InviteUnit = function(n) SENT[#SENT+1] = { kind = "INVITE", target = n } end, ConvertToRaid = function() RAID = true end }
local reg, regN = {}, 0
C_EncodingUtil = {
  SerializeCBOR = function(t) regN = regN + 1; reg[tostring(regN)] = t; return tostring(regN) end,
  DeserializeCBOR = function(s) return reg[s] end,
  CompressString = function(s) return s end, DecompressString = function(s) return s end,
  EncodeBase64 = function(s) return s end, DecodeBase64 = function(s) return s end,
}
ADDON_MSGS = {}
C_ChatInfo = {
  RegisterAddonMessagePrefix = noop,
  SendAddonMessage = function(prefix, text, chatType, target) ADDON_MSGS[#ADDON_MSGS+1] = { text = text, chatType = chatType, target = target } return 0 end,
}
PLAYER_CLASS = "WARLOCK"
function UnitClass(u)
  if u == nil or u == "player" then return "Warlock", PLAYER_CLASS end
  local m = member(u)
  local class = m and m.class or "WARLOCK"
  return class, class
end
