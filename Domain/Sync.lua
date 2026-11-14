-- Summon Circle: the circle's shared state and how it stays in sync.
--
-- The "authority" (normally the group leader) holds the official copy and
-- broadcasts snapshots; every summoner keeps a full copy so any of them can
-- take over if leadership changes. Changes are "ops": applied locally right
-- away, sent to the other summoners, and reconciled by the next snapshot.
--
--   Sync.RegisterOp(name, fn)   fn(m, remote) applies op m to ns.S
--   Sync.Do(name, m)            apply locally + send to the summoners
--   Sync.OnTick(order, fn)      authority housekeeping, every second, lowest
--                               order first. fn returns changed[, after]:
--                               `after` runs once the change is published.
local ADDON, ns = ...
local Sync = ns:Module("Sync")
local Transport, Roster = ns.Transport, ns.Roster

local ops = {}
local ticks = {}

function Sync.NewState()
  return {
    epoch = 0, seq = 0, leader = nil,
    price = ns.db.price,
    queue = {},       -- ["First Last"] = { name, added, status, caster, castAt, arrivedAt, paid }
    summoners = {},   -- picked by the leader, in rotation order
    lastCaster = nil,
    ledger = {},      -- [summoner] = { copper, summons, shards, failed }
    sessionStart = GetServerTime(),
  }
end

function Sync.RegisterOp(name, fn)
  assert(not ops[name], "op registered twice: " .. name)
  ops[name] = fn
end

function Sync.OnTick(order, fn)
  ticks[#ticks + 1] = { order = order, fn = fn }
  table.sort(ticks, function(a, b) return a.order < b.order end)
end

---------------------------------------------------------------------------
-- Who holds the official state: the group leader if they're a summoner
-- running the addon, else the first summoner running it, else alphabetical.
---------------------------------------------------------------------------
function Sync.AuthorityName()
  if not IsInGroup() then return ns.Me() end
  local S, Session = ns.S, ns.Session
  local anySummoners = #S.summoners > 0
  for name, r in pairs(Roster.members) do
    if r.rank == 2 and Roster.HasAddon(name) and (not anySummoners or Session.IsSummoner(name)) then
      return name
    end
  end
  for _, name in ipairs(S.summoners) do
    if Roster.members[name] and Roster.HasAddon(name) then return name end
  end
  local best = ns.Me()
  for name in pairs(Roster.peers) do
    if Roster.members[name] and name < best then best = name end
  end
  return best
end

function Sync.IsAuthority()
  return Sync.AuthorityName() == ns.Me()
end

function Sync.CheckAuthority()
  local S = ns.S
  if Sync.IsAuthority() and S.leader ~= ns.Me() then
    S.epoch = (S.epoch or 0) + 1
    S.seq = 0
    S.leader = ns.Me()
    Sync.Changed()
  end
end

-- Other summoners running the addon: the only people who get the queue,
-- events and the blacklist. `extra` adds names (e.g. summoners just removed).
function Sync.SummonerTargets(extra)
  local out, seen = {}, { [ns.Me()] = true }
  local function add(n)
    if not seen[n] and Roster.members[n] and Roster.HasAddon(n) then
      out[#out + 1] = n; seen[n] = true
    end
  end
  for _, n in ipairs(ns.S.summoners) do add(n) end
  for _, n in ipairs(extra or {}) do add(n) end
  return out
end

---------------------------------------------------------------------------
-- Change propagation
---------------------------------------------------------------------------
local snapPending = false

function Sync.SendSnapshot()
  if IsInGroup() and Sync.IsAuthority() then
    Transport.Send({ t = "SNAP", s = ns.S }, Sync.SummonerTargets())
  end
end

-- Call after changing ns.S. The authority bumps the version and sends a
-- snapshot within a second (several changes share one snapshot).
function Sync.Changed()
  if Sync.IsAuthority() then
    ns.S.seq = (ns.S.seq or 0) + 1
    if not snapPending then
      snapPending = true
      C_Timer.After(1, function()
        snapPending = false
        Sync.SendSnapshot()
      end)
    end
  end
  ns.Update()
end

function Sync.Do(name, m)
  m.op = name
  m.at = m.at or GetServerTime()
  local before = ns.S.summoners -- removed summoners still need to hear they're out
  ops[name](m, false)
  if IsInGroup() then
    Transport.Send({ t = "OP", m = m }, Sync.SummonerTargets(name == "SUMMONERS" and before or nil))
  end
  Sync.Changed()
end

-- Replace our copy with a snapshot from the authority.
function Sync.Adopt(s)
  s.summoners = s.summoners or {}
  local old = ns.S.summoners
  ns.db.state = s
  ns.S = s
  ns.Emit("SUMMONERS_CHANGED", old, s.summoners)
  ns.Update()
end

---------------------------------------------------------------------------
-- Incoming
---------------------------------------------------------------------------
Transport.Handle("OP", function(sender, msg)
  local m = msg.m
  if type(m) ~= "table" or not ops[m.op] then return end
  if not (ns.Session.IsSummoner(sender) or sender == Sync.AuthorityName()) then return end
  ops[m.op](m, true)
  ns.Emit("OP_RECEIVED", m)
  Sync.Changed()
end)

Transport.Handle("SNAP", function(sender, msg)
  local s = msg.s
  if type(s) ~= "table" or sender ~= Sync.AuthorityName() then return end
  local S = ns.S
  local newer = S.leader ~= sender or (s.epoch or 0) > (S.epoch or 0)
    or ((s.epoch or 0) == (S.epoch or 0) and (s.seq or 0) >= (S.seq or 0))
  if newer then Sync.Adopt(s) end
end)

ns.Listen("PEER_SEEN", function(sender, hello, isNew)
  -- A summoner (re)connected: catch them up.
  if hello and ns.Session.IsSummoner(sender) and Sync.IsAuthority() then Sync.SendSnapshot() end
  if isNew then Sync.CheckAuthority() end
end)

ns.Listen("ROSTER_CHANGED", function() Sync.CheckAuthority() end)

---------------------------------------------------------------------------
-- Housekeeping
---------------------------------------------------------------------------
function Sync.Tick()
  Roster.Scan()
  if IsInGroup() and Sync.IsAuthority() then
    local changed, after = false, {}
    for _, t in ipairs(ticks) do
      local c, a = t.fn()
      if c then changed = true end
      if a then after[#after + 1] = a end
    end
    if changed then Sync.Changed() end
    for _, a in ipairs(after) do a() end
  end
  ns.Update()
end

ns.On("PLAYER_LOGIN", function()
  ns.db.state = ns.db.state or Sync.NewState()
  ns.S = ns.db.state
  ns.S.summoners = ns.S.summoners or {}
  Sync.CheckAuthority()
  C_Timer.NewTicker(1, ns.Safe(Sync.Tick))
  C_Timer.NewTicker(30, ns.Safe(Sync.SendSnapshot))
end)
