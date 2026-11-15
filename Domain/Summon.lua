-- Summon Circle: getting a summon from an open circle (design doc 04).
--
-- "Get summoned" whispers the circle's keyword (normally "inv") to its
-- first contact: the leader, or another summoner who can invite if the
-- leader is AFK. From there the circle's normal flow takes over: invite,
-- "you're #3 in queue", summon, trade. Nothing new goes over the network.
local ADDON, ns = ...
local Summon = ns:Module("Summon")
local Roster = ns.Roster

Summon.REQUESTED_FOR = 120 -- seconds the button stays "Requested"
Summon.requested = {}      -- [leader] = GetTime() we asked

-- The circle we're grouped with, if any (its leader or a contact is here).
function Summon.CurrentCircle()
  if not IsInGroup() then return nil end
  for leader, l in pairs(ns.Listings.all) do
    if Roster.members[leader] then return l end
    for _, n in ipairs(l.contacts or {}) do
      if Roster.members[n] then return l end
    end
  end
end

-- "get" | "requested" | "in group"
function Summon.State(leader, now)
  if IsInGroup() then return "in group" end
  local t = Summon.requested[leader]
  if t and (now or GetTime()) - t < Summon.REQUESTED_FOR then return "requested" end
  return "get"
end

function Summon.Request(leader)
  local l = ns.Listings.all[leader]
  if not l or Summon.State(leader) ~= "get" then return end
  Summon.requested[leader] = GetTime()
  if not l.demo then -- made-up circles (/sc demo) get nothing sent
    local to = (l.contacts and l.contacts[1]) or l.leader
    ns.Whisper(l.keyword or "inv", to)
  end
  ns.Update()
end
