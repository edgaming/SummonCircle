-- Sending and receiving through the real addon-message path.
GROUP = { { name = "Ash Lock", leader = true }, { name = "Bram Lock" } }
Boot()
local T, P = ns.Transport, ns.Protocol

local got = {}
T.Handle("TEST", function(sender, msg) got[#got + 1] = { sender = sender, msg = msg } end)
local function deliver(msg, sender)
  local frames = P.Frames(P.Encode(msg), 42)
  for _, fr in ipairs(frames) do FireEvent("CHAT_MSG_ADDON", ns.PREFIX, fr, "PARTY", sender) end
end

deliver({ t = "TEST", n = 1 }, "Bram Lock-CAMWOWUS2Realm8PvP")
eq("receive: delivered", #got, 1)
eq("receive: sender has no realm", got[1] and got[1].sender, "Bram Lock")
deliver({ t = "TEST", big = ("y"):rep(600) }, "Bram Lock")
eq("receive: multi-frame message", got[2] and #got[2].msg.big, 600)
deliver({ t = "TEST" }, "Ash Lock")
eq("receive: my own messages ignored", #got, 2)
deliver({ t = "SOMETHING_NEW" }, "Bram Lock")
check("receive: unknown types ignored", #ERRORS == 0)
FireEvent("CHAT_MSG_ADDON", "OTHERADDON", "1:1:1:{}", "PARTY", "Bram Lock")
eq("receive: other prefixes ignored", #got, 2)

local ok = pcall(T.Handle, "TEST", function() end)
check("handle: one handler per type", not ok)

-- Sending. Only look at our TEST messages (heartbeats go out too).
local function sent()
  local out = {}
  for _, m in ipairs(ADDON_MSGS) do
    local msg = P.Decode(m.text:match("^%d+:%d+:%d+:(.*)$") or "")
    if msg and msg.t == "TEST" then out[#out + 1] = { chatType = m.chatType, target = m.target, msg = msg } end
  end
  return out
end
ADDON_MSGS = {}
T.Send({ t = "TEST" })
RunTimers(1)
eq("send: group channel", sent()[1] and sent()[1].chatType, "PARTY")
ADDON_MSGS = {}
T.Send({ t = "TEST" }, { "Bram Lock" })
RunTimers(1)
eq("send: private", sent()[1] and sent()[1].chatType, "WHISPER")
eq("send: private target", sent()[1] and sent()[1].target, "Bram Lock")
ADDON_MSGS = {}
T.Send({ t = "TEST" }, {})
RunTimers(1)
eq("send: empty target list sends nothing", #sent(), 0)

-- Throttled: hold the queue and retry later, in order.
local real = C_ChatInfo.SendAddonMessage
local throttled = true
C_ChatInfo.SendAddonMessage = function(...)
  if throttled then return Enum.SendAddonMessageResult.AddonMessageThrottle end
  return real(...)
end
ADDON_MSGS = {}
T.Send({ t = "TEST", n = 1 }); T.Send({ t = "TEST", n = 2 })
RunTimers(1)
eq("throttle: nothing sent yet", #ADDON_MSGS, 0)
throttled = false
RunTimers(1)
eq("throttle: both sent after", #sent(), 2)
eq("throttle: order kept", sent()[1] and sent()[1].msg.n, 1)
C_ChatInfo.SendAddonMessage = real

-- Solo: nothing to send to.
GROUP = {}
ADDON_MSGS = {}
T.Send({ t = "TEST" })
RunTimers(1)
eq("solo: nothing sent", #ADDON_MSGS, 0)
