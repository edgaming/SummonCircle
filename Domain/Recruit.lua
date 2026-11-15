-- Summon Circle: finding summoners (design doc 03).
--
-- Leader: ticks "Looking for summoners". The circle's listing says so, and
-- warlocks who click Ask to join show up under Summoners with an Invite
-- button. An invited applicant who joins becomes a summoner automatically
-- (the leader's click already said yes). Once the circle has 3 summoners,
-- recruiting turns itself off and remaining applicants are told it's full.
--
-- Seeker: Ask to join whispers the leader a friendly sentence and sends a
-- hidden JOIN_REQ with where they are and how many shards they have.
--
-- Shared state (synced to the summoners like the queue):
--   S.recruiting = true|nil
--   S.applicants = { ["First Last"] = { name, zone, shards, at, invited } }
local ADDON, ns = ...
local Recruit = ns:Module("Recruit")
local Sync, Roster, Session, Transport = ns.Sync, ns.Roster, ns.Session, ns.Transport

Recruit.ASKED_FOR = 120     -- seconds a seeker's row shows "Asked"
Recruit.CLOSED_FOR = 600    -- seconds it shows "Circle filled"
Recruit.APPLY_EXPIRE = 600  -- uninvited applications fade after 10 minutes

Recruit.asked = {}   -- seeker: [leader] = GetTime() we asked
Recruit.closed = {}  -- seeker: [leader] = GetTime() they said they're full

local function applicants()
  ns.S.applicants = ns.S.applicants or {}
  return ns.S.applicants
end

function Recruit.IsRecruiting()
  return ns.S ~= nil and ns.S.recruiting == true
end

-- Applicants newest first.
function Recruit.Applicants()
  local out = {}
  for _, a in pairs(applicants()) do out[#out + 1] = a end
  table.sort(out, function(a, b)
    if a.at ~= b.at then return a.at > b.at end
    return a.name < b.name
  end)
  return out
end

---------------------------------------------------------------------------
-- Ops
---------------------------------------------------------------------------
Sync.RegisterOp("RECRUIT", function(m)
  ns.S.recruiting = m.on and true or nil
  if not m.on then ns.S.applicants = {} end
end)

Sync.RegisterOp("APPLY", function(m)
  local a = m.a
  local cur = applicants()[a.name]
  a.invited = cur and cur.invited or nil
  applicants()[a.name] = a
end)

Sync.RegisterOp("APPLICANT_INVITED", function(m)
  local a = applicants()[m.name]
  if a then a.invited = true end
end)

Sync.RegisterOp("APPLICANT_DEL", function(m) applicants()[m.name] = nil end)

---------------------------------------------------------------------------
-- Leader
---------------------------------------------------------------------------
-- Tell applicants still outside the group that the circle is full.
local function closeApplicants()
  for name in pairs(applicants()) do
    if not Roster.members[name] then Transport.SendDirect({ t = "JOIN_CLOSED" }, name) end
  end
end

function Recruit.SetRecruiting(on)
  if not Roster.IsLeader() then return end
  if not on then closeApplicants() end
  Sync.Do("RECRUIT", { on = on and true or false })
end

function Recruit.Invite(name)
  local a = applicants()[name]
  if not Roster.IsLeader() or not a then return end
  if a.demo then a.invited = true; return ns.Update() end -- made-up applicant (/sc demo)
  ns.API.Invite(name)
  Sync.Do("APPLICANT_INVITED", { name = name })
end

function Recruit.Dismiss(name)
  if not Roster.IsLeader() or not applicants()[name] then return end
  Sync.Do("APPLICANT_DEL", { name = name })
end

-- Someone asked to join.
Transport.Handle("JOIN_REQ", function(sender, msg)
  if not Roster.IsLeader() or not Recruit.IsRecruiting() then
    Transport.SendDirect({ t = "JOIN_CLOSED" }, sender)
    return
  end
  if Session.IsSummoner(sender) then return end
  local cur = applicants()[sender]
  if cur and GetServerTime() - cur.at < 60 then return end -- asked twice in a row
  local zone = type(msg.zone) == "string" and msg.zone:sub(1, 40) or "?"
  local shards = type(msg.shards) == "number" and math.max(0, math.floor(msg.shards)) or 0
  Sync.Do("APPLY", { a = { name = sender, zone = zone, shards = shards, at = GetServerTime() } })
end)

-- Every second, for the leader: invited applicants who joined become
-- summoners; a full circle stops recruiting; stale applications fade.
function Recruit.Tick(now)
  if not ns.S or not Roster.IsLeader() then return end
  now = now or GetServerTime()
  for name, a in pairs(applicants()) do
    if a.invited and Roster.members[name] then
      if not Session.IsSummoner(name) then
        local list = {}
        for _, n in ipairs(ns.S.summoners) do list[#list + 1] = n end
        if #list == 0 then list[1] = ns.Me() end
        list[#list + 1] = name
        Sync.Do("SUMMONERS", { list = list })
      end
      Sync.Do("APPLICANT_DEL", { name = name })
    elseif not a.invited and now - a.at >= Recruit.APPLY_EXPIRE then
      Sync.Do("APPLICANT_DEL", { name = name })
    end
  end
  if Recruit.IsRecruiting() and #Session.ActiveSummoners() >= ns.Listings.WANTED then
    Recruit.SetRecruiting(false)
  end
end

-- Leaving or joining someone else's group: recruiting was theirs, not ours.
local function forget()
  if ns.S then ns.S.recruiting, ns.S.applicants = nil, {} end
end
ns.Listen("GROUP_LEFT", forget)
ns.Listen("GROUP_JOINED", function()
  if not ns.IsGroupLeader("player") then forget() end
end)

---------------------------------------------------------------------------
-- Seeker
---------------------------------------------------------------------------
function Recruit.Ask(leader)
  local l = ns.Listings.all[leader]
  if not l or Recruit.RowState(leader) ~= "ask" then return end
  if l.demo then -- made-up circle (/sc demo): just show the button change
    Recruit.asked[leader] = GetTime()
    return ns.Update()
  end
  local zone, shards = GetRealZoneText() or "?", ns.GetShards()
  ns.Whisper(("Hi, I'm looking to join your summoning circle in %s. I'm in %s with %d soul shards.")
    :format(l.spot, zone, shards), leader)
  Transport.SendDirect({ t = "JOIN_REQ", zone = zone, shards = shards, spot = l.spot }, leader)
  Recruit.asked[leader] = GetTime()
  ns.Update()
end

-- "ask" | "asked" | "closed"
function Recruit.RowState(leader, now)
  now = now or GetTime()
  if Recruit.closed[leader] and now - Recruit.closed[leader] < Recruit.CLOSED_FOR then return "closed" end
  if Recruit.asked[leader] and now - Recruit.asked[leader] < Recruit.ASKED_FOR then return "asked" end
  return "ask"
end

Transport.Handle("JOIN_CLOSED", function(sender)
  Recruit.closed[sender] = GetTime()
  ns.Update()
end)

-- Find a Circle isn't for you while you're summoning in a circle.
function Recruit.InACircle()
  return IsInGroup() and Session.IsSummoner(ns.Me())
end

ns.On("PLAYER_LOGIN", function()
  C_Timer.NewTicker(1, ns.Safe(function() Recruit.Tick() end))
end)
