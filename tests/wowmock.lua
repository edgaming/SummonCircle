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
function FrameMT.SetAlpha(f, a) f._alpha = a end
function FrameMT.GetAlpha(f) return rawget(f, "_alpha") or 1 end
-- Animations: groups record whether they're playing.
function FrameMT.CreateAnimationGroup(f) local g = newFrame(); g._playing = false; return g end
function FrameMT.CreateAnimation(g) return newFrame() end
function FrameMT.Play(g) g._playing = true end
function FrameMT.Stop(g) g._playing = false end
function FrameMT.IsPlaying(g) return rawget(g, "_playing") == true end
function FrameMT.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function FrameMT.HasFocus() return false end
function FrameMT.GetChecked(f) return f._checked end
function FrameMT.SetChecked(f, v) f._checked = v end
function FrameMT.IsEnabled(f) return f._enabled ~= false end
function FrameMT.Enable(f) f._enabled = true end
function FrameMT.Disable(f) f._enabled = false end
function FrameMT.SetEnabled(f, v) f._enabled = v end
function FrameMT.StartMoving() end
function FrameMT.GetFrameLevel(f) return rawget(f, "_level") or 1 end
function FrameMT.SetFrameLevel(f, l) f._level = l end
function FrameMT.GetFrameStrata(f) return rawget(f, "_strata") or "MEDIUM" end
function FrameMT.SetFrameStrata(f, s) f._strata = s end

function CreateFrame(kind, name, parent, template) return newFrame(name) end
UIParent = newFrame("UIParent")
RaidWarningFrame = newFrame()

function FireEvent(e, ...)
  for _, f in ipairs(EVENTS[e] or {}) do
    local h = f._scripts.OnEvent
    if h then h(f, e, ...) end
  end
end

-- Timers: RunTimers(n) runs every ticker n times; C_Timer.After callbacks
-- run once, on the next RunTimers.
local afters = {}
C_Timer = {
  NewTicker = function(sec, fn) table.insert(timers, fn); return {} end,
  After = function(sec, fn) table.insert(afters, fn) end,
}
local function call(fn)
  local ok, err = pcall(fn)
  if not ok then table.insert(ERRORS, "timer: " .. tostring(err)) end
end
function RunTimers(n)
  for _ = 1, (n or 1) do
    local list = {}
    for i, fn in ipairs(timers) do list[i] = fn end
    for _, fn in ipairs(list) do call(fn) end
    local once = afters
    afters = {}
    for _, fn in ipairs(once) do call(fn) end
  end
end

-- Clock: Advance(sec) moves both game clocks forward.
CLOCK_OFFSET = 0
function Advance(sec) CLOCK_OFFSET = CLOCK_OFFSET + sec end

-- Group model
ME_NAME = "Ash Lock"
GROUP = {}         -- list of { name=, leader=bool, assist=bool }
RAID = false
TRADE_PARTNER = nil -- who's on the other side of the trade window
TRADE_MONEY = 0
ZONE = "Undercity"  -- where I am
local function unitName(unit)
  if unit == "player" then return ME_NAME end
  if unit == "NPC" then return TRADE_PARTNER end
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
AFK = false -- is this player AFK?
function UnitIsAFK(unit) return unit == "player" and AFK or false end
function UnitPower() return 0 end
function GetNormalizedRealmName() return "CAMWOWUS2Realm8PvP" end
function Ambiguate(name, mode) return (name:gsub("%-[^%-]+$", "")) end
function GetRealZoneText() return ZONE end
function GetServerTime() return os.time() + CLOCK_OFFSET end
local t0 = os.clock()
function GetTime() return 1000 + (os.clock() - t0) + CLOCK_OFFSET end
COMBAT = false
function InCombatLockdown() return COMBAT end
function GetCVarBool() return true end
-- Chat channels: General and Trade, plus any custom channels joined.
JOINED = {}            -- [index] = name of custom channels
HIDDEN_CHANNELS = {}   -- [name] = true once removed from a chat window
CHANNEL_JOIN_OK = true -- set false to simulate a failed join
function GetChannelList()
  local t = { 1, "General - Undercity", false, 2, "Trade - City", false }
  for i = 3, 10 do
    if JOINED[i] then t[#t + 1] = i; t[#t + 1] = JOINED[i]; t[#t + 1] = false end
  end
  return unpack(t)
end
function GetChannelName(name)
  for i, n in pairs(JOINED) do
    if n == name or i == name then return i, n end
  end
  return 0
end
function JoinTemporaryChannel(name)
  if not CHANNEL_JOIN_OK then return end
  for _, n in pairs(JOINED) do if n == name then return end end
  for i = 3, 10 do
    if not JOINED[i] then JOINED[i] = name; return end
  end
end
function LeaveChannelByName(name)
  for i, n in pairs(JOINED) do if n == name then JOINED[i] = nil end end
end
NUM_CHAT_WINDOWS = 1
function ChatFrame_RemoveChannel(frame, name) HIDDEN_CHANNELS[name] = true end
PLAYER_FACTION = "Horde"
function UnitFactionGroup(unit) return PLAYER_FACTION, PLAYER_FACTION end
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
function GetTargetTradeMoney() return TRADE_MONEY end
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
-- "CBOR" here is a Lua literal, so messages survive the trip between
-- separate players (separate Lua runtimes) in the multi-player tests.
local function ser(v)
  local t = type(v)
  if t == "string" then return ("%q"):format(v) end
  if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  if t == "table" then
    local out = {}
    for k, x in pairs(v) do out[#out + 1] = "[" .. ser(k) .. "]=" .. ser(x) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  error("can't serialize " .. t)
end
C_EncodingUtil = {
  SerializeCBOR = ser,
  DeserializeCBOR = function(s)
    local f = loadstring("return " .. s)
    if not f then error("bad CBOR") end
    setfenv(f, {})
    return f()
  end,
  CompressString = function(s) return s end, DecompressString = function(s) return s end,
  EncodeBase64 = function(s) return s end, DecodeBase64 = function(s) return s end,
}
ADDON_MSGS = {}
C_ChatInfo = {
  RegisterAddonMessagePrefix = noop,
  SendAddonMessage = function(prefix, text, chatType, target)
    if chatType == "CHANNEL" and not JOINED[target] then return 5 end -- not in that channel
    ADDON_MSGS[#ADDON_MSGS+1] = { prefix = prefix, text = text, chatType = chatType, target = target }
    return 0
  end,
}
PLAYER_CLASS = "WARLOCK"
function UnitClass(u)
  if u == nil or u == "player" then return "Warlock", PLAYER_CLASS end
  local m = member(u)
  local class = m and m.class or "WARLOCK"
  return class, class
end

-- Assertions shared by every test.
function check(label, cond) print((cond and "PASS " or "FAIL ") .. label) end
function eq(label, got, want)
  if got == want then print("PASS " .. label)
  else print(("FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want))) end
end

-- Load the addon the way the game does at login.
function Boot()
  LoadAddon(ADDON_DIR)
  FireEvent("ADDON_LOADED", "SummonCircle")
  FireEvent("PLAYER_LOGIN")
end
ChatFrame1 = CreateFrame("Frame")

-- Tooltip: records its lines.
GameTooltip = CreateFrame("Frame")
TOOLTIP = {}
function GameTooltip:SetOwner() TOOLTIP = {} end
function GameTooltip:AddLine(text) TOOLTIP[#TOOLTIP + 1] = tostring(text) end
function GameTooltip:AddDoubleLine(a, b) TOOLTIP[#TOOLTIP + 1] = tostring(a) .. " | " .. tostring(b) end
