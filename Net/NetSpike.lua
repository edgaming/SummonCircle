-- Summon Circle: network spike (/sc net). A throwaway experiment, not a feature.
--
-- Answers the questions the network features (design docs 02-04) depend on:
--   1. Can the addon join a custom chat channel without the player seeing it?
--   2. Do addon messages flow through that channel to people outside your group?
--   3. Do addon whispers reach players outside your group?
--   4. How hard does the game throttle us?
--   5. Do long (multi-part) messages survive the trip?
--   6. Is the channel shared between Horde and Alliance?
--
-- Nothing happens until someone types /sc net. Uses its own message prefix,
-- so it can't interfere with the circle's group traffic.
local ADDON, ns = ...
local Spike = ns:Module("NetSpike")
local Protocol = ns.Protocol

Spike.PREFIX = "SUMMONCIRCLENET"  -- max 16 characters
Spike.CHANNEL = "SummonCircleTest" -- one channel for both factions, to test question 6

local THROTTLED = Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle
local on = false
local assembler = Protocol.NewAssembler(30)
local msgId = 0
local R -- results, for /sc net report

local function reset()
  R = {
    joined = false, hidden = false, index = nil,
    sent = 0, sendErrors = {},  -- [result code] = count
    pings = {},                 -- [name] = { faction, at }
    pongs = {},                 -- [name] = { route, ms }
    bursts = {},                -- [name] = { got, of }
    burstSent = nil,            -- { ok, throttled, other, of }
    big = {},                   -- [name] = bytes received intact
  }
end
reset()

local function say(...) print("|cff9482c9[net]|r", ...) end
local function faction() return (UnitFactionGroup("player")) or "?" end

---------------------------------------------------------------------------
-- Channel
---------------------------------------------------------------------------
function Spike.Index()
  local id = GetChannelName(Spike.CHANNEL)
  if type(id) == "number" and id > 0 then return id end
end

-- Remove the channel from every chat window so the player never sees it.
local function hide()
  local remove = ChatFrame_RemoveChannel or (ChatFrameUtil and ChatFrameUtil.RemoveChannel)
  if not remove then return false end
  local ok = true
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf and not pcall(remove, cf, Spike.CHANNEL) then ok = false end
  end
  return ok
end

local function afterJoin()
  R.index = Spike.Index()
  R.joined = R.index ~= nil
  if not R.joined then
    say("|cffff4040Couldn't join the channel.|r Are all 10 channel slots in use? (/chatlist)")
    return
  end
  R.hidden = hide()
  say(("Joined '%s' as channel %d, %s. Hidden from chat: %s."):format(
    Spike.CHANNEL, R.index, faction(), R.hidden and "yes" or "|cffff4040no|r"))
  say("Now type /sc net ping. Anyone else who ran /sc net should answer.")
end

function Spike.Join()
  on = true
  if Spike.Index() then return afterJoin() end
  JoinTemporaryChannel(Spike.CHANNEL)
  say("Joining...")
  C_Timer.After(2, ns.Safe(afterJoin))
end

function Spike.Leave()
  on = false
  LeaveChannelByName(Spike.CHANNEL)
  say("Left the test channel.")
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
-- Returns the game's result for each frame sent.
local function send(msg, route, target)
  msg.faction = faction()
  local data = Protocol.Encode(msg)
  msgId = (msgId % 9999) + 1
  local results = {}
  for _, frame in ipairs(Protocol.Frames(data, msgId)) do
    local res = C_ChatInfo.SendAddonMessage(Spike.PREFIX, frame, route, target)
    R.sent = R.sent + 1
    if res ~= nil and res ~= 0 and res ~= true then R.sendErrors[res] = (R.sendErrors[res] or 0) + 1 end
    results[#results + 1] = res
  end
  return results
end

local function viaChannel(msg)
  local idx = Spike.Index()
  if not idx then say("Not in the test channel. Type /sc net first.") return end
  return send(msg, "CHANNEL", idx)
end

function Spike.Ping()
  if viaChannel({ t = "PING", at = GetTime() }) then say("Ping sent to the channel.") end
end

-- Addon whisper to someone, grouped or not.
function Spike.Whisper(name)
  send({ t = "PING", at = GetTime(), direct = true }, "WHISPER", name)
  say("Ping whispered to " .. name .. ".")
end

-- Many messages at once, to see where the game starts throttling.
function Spike.Burst(n)
  n = math.max(1, math.min(tonumber(n) or 20, 100))
  local count = { ok = 0, throttled = 0, other = 0, of = n }
  local idx = Spike.Index()
  if not idx then say("Not in the test channel. Type /sc net first.") return end
  for i = 1, n do
    local res = send({ t = "BURST", i = i, n = n }, "CHANNEL", idx)[1]
    if res == 0 or res == true or res == nil then count.ok = count.ok + 1
    elseif THROTTLED and res == THROTTLED then count.throttled = count.throttled + 1
    else count.other = count.other + 1 end
  end
  R.burstSent = count
  say(("Burst of %d: %d accepted, %d throttled, %d other errors."):format(n, count.ok, count.throttled, count.other))
end

-- A long message that has to be split into several parts.
function Spike.Big()
  local filler = {}
  for i = 1, 120 do filler[i] = ("Ash Lock %03d"):format(i) end
  local text = table.concat(filler, ",")
  if viaChannel({ t = "BIG", text = text, len = #text }) then
    say(("Sent a %d-character message in parts."):format(#text))
  end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local handlers = {}

function handlers.PING(sender, msg, route)
  R.pings[sender] = { faction = msg.faction, at = GetTime() }
  local cross = msg.faction ~= faction()
  say(("Ping from %s (%s) via %s.%s"):format(sender, tostring(msg.faction), route,
    cross and " |cffffd100Other faction: the channel is shared!|r" or ""))
  send({ t = "PONG", echo = msg.at, route = route }, "WHISPER", sender)
end

function handlers.PONG(sender, msg)
  local ms = msg.echo and math.floor((GetTime() - msg.echo) * 1000) or nil
  R.pongs[sender] = { route = msg.route, ms = ms, faction = msg.faction }
  say(("%s answered (%s), round trip %s ms."):format(sender, tostring(msg.faction), tostring(ms)))
end

function handlers.BURST(sender, msg)
  local b = R.bursts[sender]
  if not b or msg.i == 1 then b = { got = 0, of = msg.n } R.bursts[sender] = b end
  b.got = b.got + 1
  if b.got == 1 then
    C_Timer.After(5, function()
      say(("Burst from %s: received %d of %d."):format(sender, b.got, b.of))
    end)
  end
end

function handlers.BIG(sender, msg)
  local intact = type(msg.text) == "string" and #msg.text == msg.len
  R.big[sender] = intact and msg.len or 0
  say(("Long message from %s: %s."):format(sender, intact and ("all " .. msg.len .. " characters arrived") or "|cffff4040damaged|r"))
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, route, sender)
  if prefix ~= Spike.PREFIX or not on then return end
  if ns.IsSecret(text) or ns.IsSecret(sender) then
    say("|cffff4040A message arrived but the game hid its contents (secret value).|r")
    return
  end
  sender = ns.Full(sender)
  if sender == ns.Me() then return end
  local data = assembler:Feed(sender, text, GetTime())
  if not data then return end
  local msg = Protocol.Decode(data)
  if msg and handlers[msg.t] then handlers[msg.t](sender, msg, route) end
end)

ns.On("ADDON_LOADED", function(name)
  if name == ADDON then C_ChatInfo.RegisterAddonMessagePrefix(Spike.PREFIX) end
end)

---------------------------------------------------------------------------
-- Report: one block to screenshot
---------------------------------------------------------------------------
local function list(t, fmt)
  local out = {}
  for name, v in pairs(t) do out[#out + 1] = fmt(name, v) end
  table.sort(out)
  return #out > 0 and table.concat(out, ", ") or "none"
end

function Spike.Report()
  say(("Me: %s, %s. Channel: %s, hidden: %s."):format(ns.Me(), faction(),
    R.joined and ("#" .. tostring(R.index)) or "not joined", R.hidden and "yes" or "no"))
  say("Pings heard from: " .. list(R.pings, function(n, v) return n .. " (" .. tostring(v.faction) .. ")" end))
  say("Answers to my pings: " .. list(R.pongs, function(n, v)
    return ("%s (%s, %s ms)"):format(n, tostring(v.route), tostring(v.ms)) end))
  if R.burstSent then
    say(("My burst: %d/%d accepted, %d throttled."):format(R.burstSent.ok, R.burstSent.of, R.burstSent.throttled))
  end
  say("Bursts received: " .. list(R.bursts, function(n, v) return ("%s %d/%d"):format(n, v.got, v.of) end))
  say("Long messages received: " .. list(R.big, function(n, v) return n .. (v > 0 and " ok" or " damaged") end))
  say(("Frames sent: %d. Send errors: %s."):format(R.sent, list(R.sendErrors, function(code, n)
    return ("code %s x%d"):format(tostring(code), n) end)))
end

local HELP = {
  "/sc net - join the hidden test channel (everyone testing runs this first)",
  "/sc net ping - ping everyone in the channel; they answer by addon whisper",
  "/sc net whisper First Last - ping one player directly (works outside groups?)",
  "/sc net burst [n] - send n messages at once (default 20) to find the throttle",
  "/sc net big - send a long multi-part message",
  "/sc net report - summary to screenshot",
  "/sc net leave - leave the test channel",
}

function Spike.Command(rest)
  local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
  sub = sub:lower()
  if sub == "" or sub == "join" then Spike.Join()
  elseif sub == "ping" then Spike.Ping()
  elseif sub == "whisper" and arg ~= "" then Spike.Whisper(arg)
  elseif sub == "burst" then Spike.Burst(arg)
  elseif sub == "big" then Spike.Big()
  elseif sub == "report" then Spike.Report()
  elseif sub == "leave" then Spike.Leave()
  else for _, l in ipairs(HELP) do say(l) end end
end

-- For tests.
function Spike.Results() return R end
