-- Summon Circle: the blacklist. Entries are saved per character and merge
-- by one rule everywhere: the newest timestamp wins, and a removal is an
-- entry marked deleted, so removals spread the same way additions do.
--
-- Two paths (design doc 02):
--   network  every add/remove is broadcast as one BL_ENTRY to everyone on the
--            faction running the addon, grouped or not
--   group    whole lists are swapped between summoners when they group up,
--            which is how anyone who was offline catches up
--
-- Entry = { by, at, reason, del?, via? }   via: nil = mine, "group", "net"
local ADDON, ns = ...
local Blacklist = ns:Module("Blacklist")
local Sync, Transport, Session = ns.Sync, ns.Transport, ns.Session

-- The last blacklisted player who whispered us: { name, entry, at }.
-- The "what to do now" box offers Invite anyway / Ignore for 2 minutes.
Blacklist.hit = nil

-- The live entry for a name, or nil.
function Blacklist.Get(name)
  local e = ns.db.blacklist[name]
  if e and not e.del then return e end
end

Blacklist.NET_LIMIT = 10        -- network entries accepted per sender per hour
Blacklist.FUTURE_SLACK = 3600   -- entries dated further ahead than this are refused

function Blacklist.Set(name, reason, del)
  name = ns.Full(name)
  local e = { by = ns.Me(), at = GetServerTime(), reason = reason, del = del or nil }
  ns.db.blacklist[name] = e
  if IsInGroup() then Transport.Send({ t = "BL", list = { [name] = e } }, Sync.SummonerTargets()) end
  Transport.SendNet({ t = "BL_ENTRY", name = name, at = e.at, reason = reason, del = e.del })
  ns.Update()
end

-- Keep `e` if it's newer than what we have. Returns true if it was kept.
local function offer(name, e)
  local cur = ns.db.blacklist[name]
  if cur and (e.at or 0) <= (cur.at or 0) then return false end
  ns.db.blacklist[name] = e
  return true
end

-- Merge a group member's list into ours (newest wins).
function Blacklist.Merge(list)
  if type(list) ~= "table" then return end
  local now = GetServerTime()
  for name, e in pairs(list) do
    if type(name) == "string" and type(e) == "table" and type(e.at) == "number"
      and e.at <= now + Blacklist.FUTURE_SLACK then
      offer(name, {
        by = e.by, at = e.at, reason = e.reason, del = e.del or nil,
        via = e.via or "group",
      })
    end
  end
end

---------------------------------------------------------------------------
-- Network entries: accepted from anyone on the faction (doc 02), with a
-- rate limit per sender. The sender is recorded as the author, whatever
-- the message claims.
---------------------------------------------------------------------------
local recent = {} -- [sender] = { times accepted in the last hour }

local function allow(sender, now)
  local list, kept = recent[sender] or {}, {}
  for _, t in ipairs(list) do
    if now - t < 3600 then kept[#kept + 1] = t end
  end
  recent[sender] = kept
  if #kept >= Blacklist.NET_LIMIT then return false end
  kept[#kept + 1] = now
  return true
end

function Blacklist.OnNetEntry(sender, msg)
  local now = GetServerTime()
  if type(msg.name) ~= "string" or msg.name == "" or type(msg.at) ~= "number" then return end
  if msg.at > now + Blacklist.FUTURE_SLACK then return end
  if msg.reason ~= nil and type(msg.reason) ~= "string" then return end
  if not allow(sender, now) then return end
  local name = ns.Full(msg.name)
  if offer(name, { by = sender, at = msg.at, reason = msg.reason, del = msg.del and true or nil, via = "net" }) then
    ns.Update()
  end
end

Transport.HandleNet("BL_ENTRY", Blacklist.OnNetEntry)

-- "by Bram Lock" / "by Bram Lock, via the network"
function Blacklist.Source(e)
  local by = "by " .. ns.Short(e.by)
  return e.via == "net" and (by .. ", via the network") or by
end

function Blacklist.Each(fn)
  for name, e in pairs(ns.db.blacklist) do
    if not e.del then fn(name, e) end
  end
end

-- Seen a blacklisted whisper: remember it for the "what to do now" box.
function Blacklist.NoteHit(name, entry)
  Blacklist.hit = { name = name, entry = entry, at = GetTime() }
  ns.Update()
end

function Blacklist.ClearHit()
  Blacklist.hit = nil
  ns.Update()
end

local function sendAll(to)
  Transport.Send({ t = "BL", list = ns.db.blacklist }, to)
end

-- Only summoners can add entries; customers with the addon can't.
Transport.Handle("BL", function(sender, msg)
  if not Session.IsSummoner(sender) then return end
  Blacklist.Merge(msg.list)
  ns.Update()
end)

-- Swap blacklists with anyone who just became a summoner.
ns.Listen("SUMMONERS_CHANGED", function(old, new)
  local was = {}
  for _, n in ipairs(old or {}) do was[n] = true end
  local me = ns.Me()
  local iAmIn = false
  for _, n in ipairs(new) do if n == me then iAmIn = true end end
  if not iAmIn then return end
  if not was[me] then
    sendAll(Sync.SummonerTargets())
    return
  end
  local added = {}
  for _, n in ipairs(new) do
    if not was[n] and n ~= me and ns.Roster.members[n] then added[#added + 1] = n end
  end
  if #added > 0 then sendAll(added) end
end)

-- A summoner reconnected: send them ours privately.
ns.Listen("PEER_SEEN", function(sender, hello)
  if hello and Session.IsSummoner(sender) and Session.IsSummoner(ns.Me()) then sendAll({ sender }) end
end)

ns.Listen("GROUP_LEFT", function() Blacklist.hit = nil end)
