-- Summon Circle: the blacklist. Entries are saved per character and merge
-- between summoners: the newest timestamp wins, and a removal is an entry
-- marked deleted, so removals spread the same way additions do.
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

function Blacklist.Set(name, reason, del)
  name = ns.Full(name)
  local e = { by = ns.Me(), at = GetServerTime(), reason = reason, del = del or nil }
  ns.db.blacklist[name] = e
  if IsInGroup() then Transport.Send({ t = "BL", list = { [name] = e } }, Sync.SummonerTargets()) end
  ns.Update()
end

-- Merge someone else's entries into ours (newest wins).
function Blacklist.Merge(list)
  if type(list) ~= "table" then return end
  for name, e in pairs(list) do
    if type(name) == "string" and type(e) == "table" then
      local cur = ns.db.blacklist[name]
      if not cur or (e.at or 0) > (cur.at or 0) then
        ns.db.blacklist[name] = e
      end
    end
  end
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
