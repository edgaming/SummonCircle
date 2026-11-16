-- Summon Circle: circle listings on the network (design docs 00 and 03).
--
-- A circle's group leader publishes one LISTING while the shop is open or
-- the circle is looking for summoners: on any change (at most every 10 s)
-- and as a heartbeat every 60 s. LISTING_END withdraws it; listeners also
-- drop a listing that hasn't been refreshed in 180 s (crashes, disconnects).
--
-- Nobody asks for listings on login: players just listen, so for the first
-- minute on the network the list says it's still waiting. This keeps the
-- traffic proportional to the number of circles, not the number of players.
--
-- Listing = { t, leader, contacts, spot, short?, open, recruiting,
--             summoners, wanted, shards = { { n, s } ... }, price, queue, at }
local ADDON, ns = ...
local Listings = ns:Module("Listings")
local Transport, Roster = ns.Transport, ns.Roster

Listings.HEARTBEAT = 60
Listings.MIN_GAP = 10   -- seconds between change-triggered sends
Listings.EXPIRE = 180
Listings.WAIT = 60      -- "waiting for existing circles" after joining the network
Listings.WANTED = 3     -- target circle size (fixed in v1)

Listings.all = {}       -- [leader] = listing heard on the network (+ seen = GetTime())
Listings.readyAt = nil  -- GetTime() when the network came up

-- Where the leader is standing: a known city, or the zone the game reports.
function Listings.Spot()
  local loc = ns.Locations.Current()
  if loc then return loc.name, loc.short end
  local zone = ns.ZoneText()
  if zone then return zone, nil end
  return "?", nil
end

---------------------------------------------------------------------------
-- Publishing (group leader only)
---------------------------------------------------------------------------
function Listings.ShouldPublish()
  if not ns.S or not Roster.IsLeader() then return false end
  return ns.Session.IsActive() or ns.S.recruiting == true
end

function Listings.Build()
  local S, me = ns.S, ns.Me()
  local list = ns.Session.ActiveSummoners()
  -- Contacts: who a customer should whisper. Summoners who can invite and
  -- aren't AFK; the leader first, unless the leader is AFK.
  local shards, contacts = {}, {}
  if not ns.IsAFK("player") then contacts[1] = me end
  for _, n in ipairs(list) do
    shards[#shards + 1] = { n = n, s = ns.Rotation.ShardsOf(n) }
    if n ~= me then
      local r, p = Roster.members[n], Roster.peers[n]
      if r and (r.rank or 0) > 0 and not (p and p.afk) then contacts[#contacts + 1] = n end
    end
  end
  if #contacts == 0 then contacts[1] = me end
  local spot, short = Listings.Spot()
  return {
    t = "LISTING", leader = me, contacts = contacts, spot = spot, short = short,
    open = ns.Session.IsActive(), recruiting = S.recruiting == true,
    summoners = #list, wanted = Listings.WANTED, shards = shards,
    price = S.price, queue = #ns.Queue.Waiting(),
    keyword = ns.db.keywords[1] or "inv", -- what a customer whispers to get in line
  }
end

-- What a listing says, minus the timestamp: a change means "send now".
local function signature(l)
  local bits = { l.spot, tostring(l.open), tostring(l.recruiting), l.summoners, l.price, l.queue }
  for _, s in ipairs(l.shards) do bits[#bits + 1] = s.n .. "=" .. s.s end
  for _, c in ipairs(l.contacts) do bits[#bits + 1] = c end
  return table.concat(bits, "|")
end

local live, lastSent, lastSig = false, -math.huge, nil

function Listings.Publish(now)
  now = now or GetTime()
  if Listings.ShouldPublish() and ns.Net.Available() then
    local l = Listings.Build()
    local sig = signature(l)
    if not live or now - lastSent >= Listings.HEARTBEAT
      or (sig ~= lastSig and now - lastSent >= Listings.MIN_GAP) then
      l.at = GetServerTime()
      Transport.SendNet(l)
      live, lastSent, lastSig = true, now, sig
    end
  elseif live then
    Transport.SendNet({ t = "LISTING_END", leader = ns.Me() })
    live, lastSig = false, nil
  end
end

function Listings.IsLive() return live end

---------------------------------------------------------------------------
-- Listening
---------------------------------------------------------------------------
local function valid(l)
  if type(l.spot) ~= "string" or type(l.summoners) ~= "number" or type(l.price) ~= "number" then return false end
  if type(l.shards) ~= "table" then return false end
  for _, s in ipairs(l.shards) do
    if type(s) ~= "table" or type(s.n) ~= "string" or type(s.s) ~= "number" then return false end
  end
  return true
end

Transport.HandleNet("LISTING", function(sender, msg)
  -- Only the leader speaks for a circle.
  if msg.leader ~= sender or not valid(msg) then return end
  msg.seen = GetTime()
  Listings.all[sender] = msg
  ns.Update()
end)

Transport.HandleNet("LISTING_END", function(sender)
  if Listings.all[sender] then
    Listings.all[sender] = nil
    ns.Update()
  end
end)

function Listings.Expire(now)
  now = now or GetTime()
  local changed = false
  for leader, l in pairs(Listings.all) do
    if now - l.seen >= Listings.EXPIRE then Listings.all[leader] = nil; changed = true end
  end
  if changed then ns.Update() end
end

-- Still inside the first minute on the network?
function Listings.Waiting(now)
  return Listings.readyAt ~= nil and (now or GetTime()) - Listings.readyAt < Listings.WAIT
end

-- The circle's total shards: how many summons it can still do.
function Listings.SummonsLeft(l)
  local total = 0
  for _, s in ipairs(l.shards) do total = total + s.s end
  return total
end

-- Open circles, for Find a Summon: shortest wait first, then cheapest.
-- Never your own, one you're grouped with, or one where you already are.
function Listings.Open()
  local here = Listings.Spot()
  local out = {}
  for leader, l in pairs(Listings.all) do
    if l.open and leader ~= ns.Me() and not Roster.members[leader] and l.spot ~= here then
      out[#out + 1] = l
    end
  end
  table.sort(out, function(a, b)
    if (a.queue or 0) ~= (b.queue or 0) then return (a.queue or 0) < (b.queue or 0) end
    if a.price ~= b.price then return a.price < b.price end
    return a.leader < b.leader
  end)
  return out
end

-- Your own circle's listing while it's recruiting (what others see), or nil.
-- The leader builds it; other summoners use the one heard from the leader.
function Listings.MineRecruiting()
  if not ns.S or not ns.S.recruiting then return nil end
  if Roster.IsLeader() then
    local l = Listings.Build()
    l.at = GetServerTime()
    return l
  end
  for leader, l in pairs(Listings.all) do
    if Roster.members[leader] and l.recruiting then return l end
  end
end

-- Circles looking for summoners, for Find a Circle: closest to full first,
-- then newest. Never your own circle or one you're grouped with.
function Listings.Recruiting()
  local out = {}
  for leader, l in pairs(Listings.all) do
    if l.recruiting and leader ~= ns.Me() and not Roster.members[leader] then out[#out + 1] = l end
  end
  table.sort(out, function(a, b)
    local na, nb = (a.wanted or 3) - a.summoners, (b.wanted or 3) - b.summoners
    if na ~= nb then return na < nb end
    if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
    return a.leader < b.leader
  end)
  return out
end

ns.Listen("NET_READY", function() Listings.readyAt = GetTime() end)

-- Logging out: withdraw the listing right away (expiry is the backstop).
ns.On("PLAYER_LOGOUT", function()
  if live then
    Transport.SendNet({ t = "LISTING_END", leader = ns.Me() })
    Transport.Flush()
  end
end)

ns.On("PLAYER_LOGIN", function()
  C_Timer.NewTicker(1, ns.Safe(function()
    Listings.Publish()
    Listings.Expire()
  end))
end)
