-- Summon Circle: the wire format.
--
-- A message is a Lua table { v = version, t = type, ... }. On the wire it is
-- CBOR -> compressed -> base64, split into frames "id:i:n:part" that fit in
-- one addon message. Receivers ignore types they don't know, so newer
-- versions can add messages without breaking older ones.
local ADDON, ns = ...
local Protocol = ns:Module("Protocol")

Protocol.VERSION = 1
Protocol.CHUNK = 220 -- payload bytes per frame (addon messages max out at 255)

local function codec() return C_EncodingUtil end

function Protocol.Encode(msg)
  msg.v = msg.v or Protocol.VERSION
  local E = codec()
  return E.EncodeBase64(E.CompressString(E.SerializeCBOR(msg)))
end

-- Returns the message table, or nil for anything malformed.
function Protocol.Decode(data)
  local ok, res = pcall(function()
    local E = codec()
    return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(data)))
  end)
  if ok and type(res) == "table" and type(res.t) == "string" then return res end
end

-- data -> { "id:1:n:...", "id:2:n:...", ... }
function Protocol.Frames(data, id)
  local n = math.max(1, math.ceil(#data / Protocol.CHUNK))
  local out = {}
  for i = 1, n do
    out[i] = id .. ":" .. i .. ":" .. n .. ":" .. data:sub((i - 1) * Protocol.CHUNK + 1, i * Protocol.CHUNK)
  end
  return out
end

-- Reassembles frames per sender. Feed() returns the complete data string
-- once the last frame of a message arrives, otherwise nil.
local Assembler = {}
Assembler.__index = Assembler

function Protocol.NewAssembler(maxAge)
  return setmetatable({ buffers = {}, maxAge = maxAge or 30 }, Assembler)
end

function Assembler:Feed(sender, frame, now)
  local id, i, n, part = frame:match("^(%d+):(%d+):(%d+):(.*)$")
  if not id then return nil end
  i, n = tonumber(i), tonumber(n)
  if i < 1 or i > n then return nil end
  local key = sender .. "#" .. id
  local b = self.buffers[key]
  if not b or b.n ~= n then
    b = { n = n, got = 0, parts = {}, t = now or 0 }
    self.buffers[key] = b
  end
  if not b.parts[i] then
    b.parts[i] = part
    b.got = b.got + 1
  end
  if b.got >= b.n then
    self.buffers[key] = nil
    return table.concat(b.parts)
  end
end

-- Drop half-received messages older than maxAge seconds.
function Assembler:Prune(now)
  for k, b in pairs(self.buffers) do
    if (now or 0) - b.t > self.maxAge then self.buffers[k] = nil end
  end
end
