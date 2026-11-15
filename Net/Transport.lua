-- Summon Circle: sending and receiving addon messages.
--
--   Transport.Send(msg)          everyone in the group running the addon
--   Transport.Send(msg, names)   privately (addon whisper) to just those players
--   Transport.Handle(t, fn)      fn(sender, msg) for every incoming message of type t
--
--   Transport.SendNet(msg)       everyone on our faction running the addon (Net.lua)
--   Transport.HandleNet(t, fn)   fn(sender, msg) for network messages of type t
--
-- Features never call WoW's messaging API directly. Outgoing frames go
-- through queues that back off when WoW throttles us. Network traffic has
-- its own prefix (so its own throttle budget) and only goes out once the
-- group queue is empty, so it can never delay the circle.
local ADDON, ns = ...
local Transport = ns:Module("Transport")
local Protocol = ns.Protocol

ns.PREFIX = "SUMMONCIRCLE"
ns.NET_PREFIX = "SUMMONCIRCLENET"

local THROTTLED = Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle
local outq = {}
local msgId = 0
local handlers = {}
local assembler = Protocol.NewAssembler(30)
local netq, netHandlers = {}, {}
local netAssembler = Protocol.NewAssembler(30)

-- Someone runs a newer version: say so once.
local hinted = false
local function versionHint(msg)
  if not hinted and type(msg.v) == "number" and msg.v > Protocol.VERSION then
    hinted = true
    ns.Print("A newer version of Summon Circle is out. Update it in WowUp.")
  end
end

local function groupChannel()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end

function Transport.Handle(t, fn)
  assert(not handlers[t], "two handlers for message type " .. tostring(t))
  handlers[t] = fn
end

function Transport.Send(msg, to)
  if not groupChannel() then return end
  if to and #to == 0 then return end
  local data = Protocol.Encode(msg)
  msgId = (msgId % 9999) + 1
  local frames = Protocol.Frames(data, msgId)
  for _, target in ipairs(to or { false }) do
    for _, text in ipairs(frames) do
      outq[#outq + 1] = { text = text, target = target or nil }
    end
  end
end

function Transport.HandleNet(t, fn)
  assert(not netHandlers[t], "two network handlers for message type " .. tostring(t))
  netHandlers[t] = fn
end

-- Returns false when the network isn't available.
function Transport.SendNet(msg)
  if not ns.Net.Available() then return false end
  msg.faction = ns.Net.Faction()
  msgId = (msgId % 9999) + 1
  for _, text in ipairs(Protocol.Frames(Protocol.Encode(msg), msgId)) do
    netq[#netq + 1] = text
  end
  return true
end

function Transport.DispatchNet(sender, msg)
  local fn = netHandlers[msg.t]
  if fn then fn(sender, msg) end
end

-- Hand a decoded message to its handler. Unknown types are ignored.
function Transport.Dispatch(sender, msg)
  local fn = handlers[msg.t]
  if fn then fn(sender, msg) end
end

-- Drain the queues, backing off when Blizzard throttles a prefix.
-- Group first; the network only once the group queue is empty.
local function pump()
  while outq[1] do
    local ch = groupChannel()
    if not ch then wipe(outq) break end
    local m = outq[1]
    local res = C_ChatInfo.SendAddonMessage(ns.PREFIX, m.text, m.target and "WHISPER" or ch, m.target)
    if THROTTLED and res == THROTTLED then return end
    table.remove(outq, 1)
  end
  while netq[1] do
    local idx = ns.Net.Available() and ns.Net.Index()
    if not idx then wipe(netq) return end
    local res = C_ChatInfo.SendAddonMessage(ns.NET_PREFIX, netq[1], "CHANNEL", idx)
    if THROTTLED and res == THROTTLED then return end
    table.remove(netq, 1)
  end
end
C_Timer.NewTicker(0.2, ns.Safe(pump))
C_Timer.NewTicker(15, ns.Safe(function()
  assembler:Prune(GetTime())
  netAssembler:Prune(GetTime())
end))

ns.On("ADDON_LOADED", function(name)
  if name == ADDON then
    C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(ns.NET_PREFIX)
  end
end)

-- Group traffic only arrives through the group or an addon whisper. Anything
-- on our prefix from a public channel is someone else's, and is dropped.
local ROUTES = { PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }

ns.On("CHAT_MSG_ADDON", function(prefix, text, route, sender)
  if prefix ~= ns.PREFIX or not ROUTES[route] or ns.IsSecret(text) or ns.IsSecret(sender) then return end
  sender = ns.Full(sender)
  if sender == ns.Me() then return end
  local data = assembler:Feed(sender, text, GetTime())
  if not data then return end
  local msg = Protocol.Decode(data)
  if msg then versionHint(msg); Transport.Dispatch(sender, msg) end
end)

-- Network traffic: only through our faction's channel, only our faction.
ns.On("CHAT_MSG_ADDON", function(prefix, text, route, sender)
  if prefix ~= ns.NET_PREFIX or route ~= "CHANNEL" or not ns.Net.Available() then return end
  if ns.IsSecret(text) or ns.IsSecret(sender) then return end
  sender = ns.Full(sender)
  if not sender or sender == ns.Me() then return end
  local data = netAssembler:Feed(sender, text, GetTime())
  if not data then return end
  local msg = Protocol.Decode(data)
  if not msg or msg.faction ~= ns.Net.Faction() then return end
  versionHint(msg)
  ns.Net.received = ns.Net.received + 1
  Transport.DispatchNet(sender, msg)
end)
