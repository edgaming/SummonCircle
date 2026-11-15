-- Summon Circle: customers. Whisper intake, the queue, casts, arrivals,
-- and the actions summoners take on a customer (trade, kick, re-invite).
--
-- Statuses: INVITED -> GROUP (waiting) -> SUMMONING -> ARRIVED -> PAID
local ADDON, ns = ...
local Queue = ns:Module("Queue")
local Sync, Roster, Session, Blacklist = ns.Sync, ns.Roster, ns.Session, ns.Blacklist

local WAITING = { INVITED = true, GROUP = true }
local INVITE_TIMEOUT = 90 -- seconds to accept an invite before dropping out of line

-- My customers who left without paying: ["First Last"] = true.
Queue.leftUnpaid = {}

-- Set by the action button just before it casts, so we know who was summoned.
Queue.pendingTarget = nil

function Queue.Get(name)
  return ns.S.queue[name]
end

-- Everyone in the queue, oldest first.
function Queue.Sorted()
  local list = {}
  for _, e in pairs(ns.S.queue) do list[#list + 1] = e end
  table.sort(list, function(a, b)
    if (a.added or 0) ~= (b.added or 0) then return (a.added or 0) < (b.added or 0) end
    return a.name < b.name
  end)
  return list
end

-- Customers still waiting for a summon, oldest first.
function Queue.Waiting()
  local out = {}
  for _, e in ipairs(Queue.Sorted()) do
    if WAITING[e.status] then out[#out + 1] = e end
  end
  return out
end

function Queue.Position(name)
  for i, e in ipairs(Queue.Waiting()) do
    if e.name == name then return i end
  end
  return 1
end

-- The next customer we can summon: in the group, online, not already here.
function Queue.NextCustomer()
  local myZone = GetRealZoneText()
  for _, e in ipairs(Queue.Waiting()) do
    local r = Roster.members[e.name]
    if e.status == "GROUP" and r and r.online and r.zone ~= myZone then return e, r end
  end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function Queue.Trade(name)
  local e = ns.S.queue[name]
  if e and e.demo then return ns.Print("(demo) This would open a trade with " .. name .. ".") end
  local r = Roster.members[name]
  if r then InitiateTrade(r.unit) end
end

-- blacklist: also blacklist them. silent: no "Thanks" whisper.
function Queue.Kick(name, blacklist, silent)
  local e = ns.S.queue[name]
  if e and e.demo then -- made-up customer (/sc demo): just take them off the list
    ns.S.queue[name] = nil
    return ns.Update()
  end
  if blacklist then
    Blacklist.Set(name, "didn't pay " .. ns.Short(ns.Me()))
  elseif not silent and ns.db.thanks ~= "" then
    ns.Whisper(ns.db.thanks, name)
  end
  if Roster.CanInvite() then
    ns.API.Uninvite(name)
  else
    ns.Print("You need assist to kick. Ask the leader.")
  end
  Sync.Do("REMOVE", { name = name })
end

function Queue.Reinvite(name)
  local e = ns.S.queue[name]
  if e and e.demo then return end
  if Roster.CanInvite() then ns.API.Invite(name) end
end

-- Add someone to the line (inviting them if we can).
function Queue.Add(name)
  local ok = Roster.CanInvite()
  if ok then ns.API.Invite(name) end
  Sync.Do("ADD", { name = name, by = ns.Me(), inviteOk = ok })
end

function Queue.InviteAnyway(name)
  Blacklist.hit = nil
  Queue.Add(name)
end

function Queue.ForgetUnpaid(name)
  Queue.leftUnpaid[name] = nil
  ns.Update()
end

local function portalAlert(caster, target)
  if caster == ns.Me() or not Session.IsSummoner(ns.Me()) then return end
  local text = ("%s's portal is up for %s. CLICK IT!"):format(ns.Short(caster), ns.Short(target))
  RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
  PlaySound(SOUNDKIT.RAID_WARNING)
end

---------------------------------------------------------------------------
-- Ops
---------------------------------------------------------------------------
Sync.RegisterOp("ADD", function(m)
  local q = ns.S.queue
  if q[m.name] then return end
  q[m.name] = { name = m.name, added = m.at, status = Roster.members[m.name] and "GROUP" or "INVITED" }
end)

Sync.RegisterOp("CAST", function(m, remote)
  local e = ns.S.queue[m.target]
  if e then
    e.status, e.caster, e.castAt = "SUMMONING", m.caster, m.at
  end
  ns.S.lastCaster = m.caster
  local L = ns.Ledger.Get(m.caster)
  L.shards = L.shards + 1
  if remote then portalAlert(m.caster, m.target) end
end)

Sync.RegisterOp("REMOVE", function(m) ns.S.queue[m.name] = nil end)

Sync.RegisterOp("LEFT", function(m)
  ns.S.queue[m.name] = nil
  if m.caster == ns.Me() then Queue.leftUnpaid[m.name] = true end
end)

-- The summoner who got the whisper had no invite rights: the authority invites.
ns.Listen("OP_RECEIVED", function(m)
  if m.op == "ADD" and not m.inviteOk and Sync.IsAuthority() and Roster.CanInvite() then
    ns.API.Invite(m.name)
  end
end)

---------------------------------------------------------------------------
-- Whisper intake: works for every summoner; ordering is best effort.
---------------------------------------------------------------------------
local function isTrigger(text)
  local word = text:lower():match("^%s*(.-)%s*$")
  for _, k in ipairs(ns.db.keywords) do
    if word == k then return true end
  end
  return false
end

ns.On("CHAT_MSG_WHISPER", function(text, sender)
  if ns.IsSecret(text) or ns.IsSecret(sender) then return end
  if not Session.IsActive() then return end
  if IsInGroup() and not Session.IsSummoner(ns.Me()) then return end
  if not isTrigger(text) then return end

  local name = ns.Full(sender)
  local bl = Blacklist.Get(name)
  if bl then
    Blacklist.NoteHit(name, bl)
    return
  end

  local e = ns.S.queue[name]
  if not e then
    Queue.Add(name)
  elseif e.status == "INVITED" and not Roster.members[name] and Roster.CanInvite() then
    -- They missed or declined the first invite and asked again: re-send it,
    -- but keep their original place in line.
    ns.API.Invite(name)
  end

  ns.Whisper(("Invite sent - you're #%d in queue. %s, paid after you arrive to the warlock who summoned you.")
    :format(Queue.Position(name), ns.Money(ns.S.price)), name)
end)

-- Detect our own summons. The action button records its target in PreClick.
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit ~= "player" or not Session.IsActive() or not ns.IsSummonSpell(spellID) then return end
  local target = Queue.pendingTarget or ns.UnitKey("target")
  Queue.pendingTarget = nil
  if target then Sync.Do("CAST", { caster = ns.Me(), target = target }) end
end)

---------------------------------------------------------------------------
-- Housekeeping (authority): invites accepted or expired, arrivals,
-- summons that timed out, customers who left.
---------------------------------------------------------------------------
Sync.OnTick(20, function()
  local S, changed, now = ns.S, false, GetServerTime()
  local myZone = GetRealZoneText()
  local leavers = {}
  for name, e in pairs(S.queue) do
    if not e.demo then -- made-up customers (/sc demo) stay put
      local r = Roster.members[name]
      if e.status == "INVITED" then
        if r then
          e.status = "GROUP"; changed = true
        elseif now - (e.added or now) > INVITE_TIMEOUT then
          S.queue[name] = nil; changed = true -- declined / ignored the invite
        end
      elseif not r then
        if e.status == "ARRIVED" and e.caster then
          leavers[#leavers + 1] = { name = name, caster = e.caster }
        else
          S.queue[name] = nil; changed = true
        end
      elseif e.status == "SUMMONING" then
        if r.zone and r.zone == myZone then
          e.status, e.arrivedAt = "ARRIVED", now; changed = true
        elseif now - (e.castAt or now) > ns.db.summonTimeout then
          if e.caster then
            local L = ns.Ledger.Get(e.caster)
            L.failed = L.failed + 1
          end
          e.status, e.caster, e.castAt = "GROUP", nil, nil; changed = true
        end
      end
    end
  end
  -- Tell everyone, so the summoner who's owed can choose to blacklist.
  return changed, #leavers > 0 and function()
    for _, l in ipairs(leavers) do Sync.Do("LEFT", l) end
  end or nil
end)

ns.Listen("GROUP_LEFT", function()
  ns.S.queue = {}
  Queue.leftUnpaid = {}
end)
