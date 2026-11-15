-- Summon Circle: sending and receiving addon messages.
--
--   Transport.Send(msg)          everyone in the group running the addon
--   Transport.Send(msg, names)   privately (addon whisper) to just those players
--   Transport.Handle(t, fn)      fn(sender, msg) for every incoming message of type t
--
-- Features never call WoW's messaging API directly. Outgoing frames go
-- through one queue that backs off when WoW throttles us.
local ADDON, ns = ...
local Transport = ns:Module("Transport")
local Protocol = ns.Protocol

ns.PREFIX = "SUMMONCIRCLE"

local THROTTLED = Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle
local outq = {}
local msgId = 0
local handlers = {}
local assembler = Protocol.NewAssembler(30)

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

-- Hand a decoded message to its handler. Unknown types are ignored.
function Transport.Dispatch(sender, msg)
  local fn = handlers[msg.t]
  if fn then fn(sender, msg) end
end

-- Drain the queue, backing off when Blizzard throttles the prefix.
local function pump()
  while outq[1] do
    local ch = groupChannel()
    if not ch then wipe(outq) return end
    local m = outq[1]
    local res = C_ChatInfo.SendAddonMessage(ns.PREFIX, m.text, m.target and "WHISPER" or ch, m.target)
    if THROTTLED and res == THROTTLED then return end
    table.remove(outq, 1)
  end
end
C_Timer.NewTicker(0.2, ns.Safe(pump))
C_Timer.NewTicker(15, ns.Safe(function() assembler:Prune(GetTime()) end))

ns.On("ADDON_LOADED", function(name)
  if name == ADDON then C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX) end
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
  if msg then Transport.Dispatch(sender, msg) end
end)
