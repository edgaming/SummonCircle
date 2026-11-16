-- Summon Circle: whose turn it is. Round robin from the last caster,
-- skipping summoners who are AFK, out of shards, or not running the addon.
-- Whoever actually casts becomes the last caster, so the turn simply moves
-- on from them if someone summons out of order.
local ADDON, ns = ...
local Rotation = ns:Module("Rotation")
local Roster = ns.Roster

local STALE = 35 -- seconds without a heartbeat before we assume no addon

function Rotation.ShardsOf(name)
  if name == ns.Me() then return ns.GetShards() end
  local p = Roster.peers[name]
  return p and p.shards or 0
end

-- Why a summoner is skipped (nil = available).
function Rotation.SkipReason(name)
  local shards, afk
  if name == ns.Me() then
    shards, afk = ns.GetShards(), ns.IsAFK("player")
  else
    local p = Roster.peers[name]
    if not p or (GetTime() - p.seen) >= STALE then return "needs the addon" end
    shards, afk = p.shards or 0, p.afk
  end
  if afk then return "AFK" end
  if shards <= 0 then return "no shards" end
end

function Rotation.NextUp()
  local list = ns.Session.ActiveSummoners()
  local n = #list
  if n == 0 then return nil end
  local start = 0
  for i, name in ipairs(list) do
    if name == ns.S.lastCaster then start = i end
  end
  for k = 1, n do
    local name = list[(start + k - 1) % n + 1]
    if not Rotation.SkipReason(name) then return name end
  end
end
