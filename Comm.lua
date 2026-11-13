-- Summon Circle: addon-to-addon messaging over RAID/PARTY.
-- Messages are Lua tables -> CBOR -> compressed -> base64, split into chunks.
local ADDON, ns = ...

local E = C_EncodingUtil
local CHUNK = 220
local msgId = 0
local outq = {}
local buffers = {}

local THROTTLED = Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle

local function encode(tbl)
  return E.EncodeBase64(E.CompressString(E.SerializeCBOR(tbl)))
end

local function decode(s)
  local ok, res = pcall(function()
    return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(s)))
  end)
  if ok then return res end
end

local function channel()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end

-- ns:Send(tbl)        -> everyone in the group running the addon
-- ns:Send(tbl, names) -> privately (addon whisper) to just those players
function ns:Send(tbl, to)
  if not channel() then return end
  if to and #to == 0 then return end
  tbl.v = 1
  local data = encode(tbl)
  msgId = (msgId % 9999) + 1
  local n = math.ceil(#data / CHUNK)
  for _, target in ipairs(to or { false }) do
    for i = 1, n do
      local part = data:sub((i - 1) * CHUNK + 1, i * CHUNK)
      outq[#outq + 1] = { text = msgId .. ":" .. i .. ":" .. n .. ":" .. part, target = target or nil }
    end
  end
end

-- Drain the queue, backing off when Blizzard throttles the prefix.
local function pump()
  while outq[1] do
    local ch = channel()
    if not ch then wipe(outq) return end
    local m = outq[1]
    local res = C_ChatInfo.SendAddonMessage(ns.PREFIX, m.text, m.target and "WHISPER" or ch, m.target)
    if THROTTLED and res == THROTTLED then return end
    table.remove(outq, 1)
  end
end
C_Timer.NewTicker(0.2, ns.Safe(pump))

-- Drop half-received messages after 30s.
C_Timer.NewTicker(15, ns.Safe(function()
  local now = GetTime()
  for k, b in pairs(buffers) do
    if now - b.t > 30 then buffers[k] = nil end
  end
end))

ns:On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
  if prefix ~= ns.PREFIX or ns.IsSecret(text) or ns.IsSecret(sender) then return end
  sender = ns.Full(sender)
  if sender == ns.Me() then return end
  local id, i, n, part = text:match("^(%d+):(%d+):(%d+):(.*)$")
  if not id then return end
  i, n = tonumber(i), tonumber(n)
  local key = sender .. "#" .. id
  local b = buffers[key]
  if not b then
    b = { n = n, got = 0, parts = {}, t = GetTime() }
    buffers[key] = b
  end
  if not b.parts[i] then
    b.parts[i] = part
    b.got = b.got + 1
  end
  if b.got >= b.n then
    buffers[key] = nil
    local msg = decode(table.concat(b.parts))
    if type(msg) == "table" and msg.t then ns:OnMessage(sender, msg) end
  end
end)
