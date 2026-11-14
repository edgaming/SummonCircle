-- Summon Circle: shared state, summoners, rotation, intake, payments,
-- advertising, blacklist.
--
-- The group leader picks who the summoners are. The leader's addon owns the
-- official state and broadcasts it; every summoner keeps a full copy so any
-- of them can take over if leadership changes.
local ADDON, ns = ...

ns.peers = {}  -- ["First Last"] = { shards, afk, seen }  (anyone else running the addon)
ns.roster = {} -- ["First Last"] = { unit, zone, online, rank }
ns.leftUnpaid = {} -- ["First Last"] = true: my customers who left without paying
ns.blHit = nil     -- last blacklisted person who whispered me { name, entry, at }

local ACTIVE = { INVITED = true, GROUP = true } -- statuses that count as "waiting in line"

local function newState()
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

function ns:Ledger(name)
  local L = ns.S.ledger
  L[name] = L[name] or { copper = 0, summons = 0, shards = 0, failed = 0 }
  return L[name]
end

---------------------------------------------------------------------------
-- Roster, summoners & who holds the state
---------------------------------------------------------------------------
function ns:ScanRoster()
  wipe(ns.roster)
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local name, rank, _, _, _, class, zone, online = GetRaidRosterInfo(i)
      local key = ns.UnitKey("raid" .. i) or (name and ns.Full(name))
      if key then
        ns.roster[key] = { unit = "raid" .. i, zone = zone, online = online, rank = rank, class = class }
      end
    end
  elseif IsInGroup() then
    for _, u in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
      local key = UnitExists(u) and ns.UnitKey(u)
      if key then
        ns.roster[key] = {
          unit = u, online = UnitIsConnected(u), rank = ns.IsGroupLeader(u) and 2 or 0,
          class = select(2, UnitClass(u)),
        }
      end
    end
  end
  for name in pairs(ns.peers) do
    if not ns.roster[name] then ns.peers[name] = nil end
  end
end

function ns:HasAddon(name)
  return name == ns.Me() or ns.peers[name] ~= nil
end

function ns:IsSummoner(name)
  if not IsInGroup() then return name == ns.Me() end
  for _, n in ipairs(ns.S.summoners) do
    if n == name then return true end
  end
  return false
end

-- Summoners currently in the group, in rotation order.
function ns:ActiveSummoners()
  if not IsInGroup() then return { ns.Me() } end
  local out = {}
  for _, n in ipairs(ns.S.summoners) do
    if ns.roster[n] then out[#out + 1] = n end
  end
  return out
end

-- Other summoners running the addon: the only people who get the queue,
-- events and the blacklist.
function ns:SummonerTargets(extra)
  local out, seen = {}, { [ns.Me()] = true }
  local function add(n)
    if not seen[n] and ns.roster[n] and self:HasAddon(n) then
      out[#out + 1] = n; seen[n] = true
    end
  end
  for _, n in ipairs(ns.S.summoners) do add(n) end
  for _, n in ipairs(extra or {}) do add(n) end
  return out
end

-- Swap blacklists with anyone who just became a summoner.
function ns:OnSummonersChanged(old, new)
  local was = {}
  for _, n in ipairs(old or {}) do was[n] = true end
  local me = ns.Me()
  local iAmIn = false
  for _, n in ipairs(new) do if n == me then iAmIn = true end end
  if not iAmIn then return end
  if not was[me] then
    self:Send({ t = "BL", list = ns.db.blacklist }, self:SummonerTargets())
    return
  end
  local added = {}
  for _, n in ipairs(new) do
    if not was[n] and n ~= me and ns.roster[n] then added[#added + 1] = n end
  end
  if #added > 0 then self:Send({ t = "BL", list = ns.db.blacklist }, added) end
end

-- Who holds the official state: the group leader if they run the addon,
-- else the first summoner running it, else alphabetical among addon users.
function ns:AuthorityName()
  if not IsInGroup() then return ns.Me() end
  local anySummoners = #ns.S.summoners > 0
  for name, r in pairs(ns.roster) do
    if r.rank == 2 and self:HasAddon(name) and (not anySummoners or self:IsSummoner(name)) then
      return name
    end
  end
  for _, name in ipairs(ns.S.summoners) do
    if ns.roster[name] and self:HasAddon(name) then return name end
  end
  local best = ns.Me()
  for name in pairs(ns.peers) do
    if ns.roster[name] and name < best then best = name end
  end
  return best
end

function ns:IsAuthority()
  return self:AuthorityName() == ns.Me()
end

-- "The leader" as far as the UI is concerned (price, summoner picker, Advertise).
ns.IsLeader = ns.IsAuthority

function ns:CanInvite()
  if not IsInGroup() then return true end
  return ns.IsGroupLeader("player") or ns.IsGroupAssistant("player")
end

function ns:CheckAuthority()
  if self:IsAuthority() and ns.S.leader ~= ns.Me() then
    ns.S.epoch = (ns.S.epoch or 0) + 1
    ns.S.seq = 0
    ns.S.leader = ns.Me()
    self:Changed()
  end
end

---------------------------------------------------------------------------
-- Change propagation
---------------------------------------------------------------------------
local snapPending = false

function ns:SendSnapshot()
  if IsInGroup() and self:IsAuthority() then
    self:Send({ t = "SNAP", s = ns.S }, self:SummonerTargets())
  end
end

function ns:Changed()
  if self:IsAuthority() then
    ns.S.seq = (ns.S.seq or 0) + 1
    if not snapPending then
      snapPending = true
      C_Timer.After(1, function()
        snapPending = false
        ns:SendSnapshot()
      end)
    end
  end
  if self.Refresh then self:Refresh() end
end

---------------------------------------------------------------------------
-- Operations: applied locally right away, broadcast to the group, and
-- reconciled by the leader's next snapshot.
---------------------------------------------------------------------------
local Ops = {}

function Ops.ADD(m)
  local q = ns.S.queue
  if q[m.name] then return end
  q[m.name] = { name = m.name, added = m.at, status = ns.roster[m.name] and "GROUP" or "INVITED" }
end

function Ops.CAST(m, remote)
  local e = ns.S.queue[m.target]
  if e then
    e.status, e.caster, e.castAt = "SUMMONING", m.caster, m.at
  end
  ns.S.lastCaster = m.caster
  local L = ns:Ledger(m.caster)
  L.shards = L.shards + 1
  if remote then ns:PortalAlert(m.caster, m.target) end
end

function Ops.PAID(m)
  local e = ns.S.queue[m.target]
  if e then e.status, e.paid = "PAID", m.amount end
  local L = ns:Ledger(m.caster)
  L.copper = L.copper + m.amount
  L.summons = L.summons + 1
end

function Ops.REMOVE(m) ns.S.queue[m.name] = nil end
function Ops.LEFT(m)
  ns.S.queue[m.name] = nil
  if m.caster == ns.Me() then ns.leftUnpaid[m.name] = true end
end
function Ops.PRICE(m) ns.S.price = m.price end
function Ops.SUMMONERS(m)
  local old = ns.S.summoners
  ns.S.summoners = m.list
  ns:OnSummonersChanged(old, m.list)
end
function Ops.RESET(m) ns.S.ledger = {}; ns.S.sessionStart = m.at end
function Ops.SESSION(m)
  ns.S.active = m.on and true or false
  if m.on then
    ns.S.ledger, ns.S.sessionStart = {}, m.at -- earnings count per session
  end
end

function ns:Do(op, m)
  m.op = op
  m.at = m.at or GetServerTime()
  local before = ns.S.summoners -- removed summoners still need to hear they're out
  Ops[op](m, false)
  if IsInGroup() then
    self:Send({ t = "OP", m = m }, self:SummonerTargets(op == "SUMMONERS" and before or nil))
  end
  self:Changed()
end

---------------------------------------------------------------------------
-- Incoming messages
---------------------------------------------------------------------------
function ns:SendHello()
  self:Send({ t = "HELLO", shards = ns.GetShards(), afk = UnitIsAFK("player") })
end

function ns:SendHeartbeat()
  if IsInGroup() then
    self:Send({ t = "HB", shards = ns.GetShards(), afk = UnitIsAFK("player") })
  end
end

function ns:BLMerge(list)
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

function ns:OnMessage(sender, msg)
  local t = msg.t
  if t == "HB" or t == "HELLO" then
    local isNew = ns.peers[sender] == nil
    ns.peers[sender] = { shards = msg.shards or 0, afk = msg.afk, seen = GetTime() }
    if t == "HELLO" and self:IsSummoner(sender) then
      -- A summoner reconnected: catch them up privately.
      if self:IsSummoner(ns.Me()) then self:Send({ t = "BL", list = ns.db.blacklist }, { sender }) end
      if self:IsAuthority() then self:SendSnapshot() end
    end
    if isNew then self:CheckAuthority() end
    self:Refresh()
  elseif t == "OP" then
    local m = msg.m
    if type(m) ~= "table" or not Ops[m.op] then return end
    if not (self:IsSummoner(sender) or sender == self:AuthorityName()) then return end
    Ops[m.op](m, true)
    if m.op == "ADD" and not m.inviteOk and self:IsAuthority() and self:CanInvite() then
      ns.API.Invite(m.name) -- the summoner who got the whisper had no invite rights
    end
    self:Changed()
  elseif t == "SNAP" then
    local s = msg.s
    if type(s) ~= "table" or sender ~= self:AuthorityName() then return end
    local S = ns.S
    local newer = S.leader ~= sender or (s.epoch or 0) > (S.epoch or 0)
      or ((s.epoch or 0) == (S.epoch or 0) and (s.seq or 0) >= (S.seq or 0))
    if newer then
      s.summoners = s.summoners or {}
      local old = S.summoners
      ns.db.state = s
      ns.S = s
      self:OnSummonersChanged(old, s.summoners)
      self:Refresh()
    end
  elseif t == "BL" then
    if not self:IsSummoner(sender) then return end -- customers can't add entries
    self:BLMerge(msg.list)
    self:Refresh()
  end
end

---------------------------------------------------------------------------
-- Queue & rotation
---------------------------------------------------------------------------
function ns:SortedQueue()
  local list = {}
  for _, e in pairs(ns.S.queue) do list[#list + 1] = e end
  table.sort(list, function(a, b)
    if (a.added or 0) ~= (b.added or 0) then return (a.added or 0) < (b.added or 0) end
    return a.name < b.name
  end)
  return list
end

function ns:Waiting()
  local out = {}
  for _, e in ipairs(self:SortedQueue()) do
    if ACTIVE[e.status] then out[#out + 1] = e end
  end
  return out
end

function ns:QueuePosition(name)
  for i, e in ipairs(self:Waiting()) do
    if e.name == name then return i end
  end
  return 1
end

function ns:NextCustomer()
  local myZone = GetRealZoneText()
  for _, e in ipairs(self:Waiting()) do
    local r = ns.roster[e.name]
    if e.status == "GROUP" and r and r.online and r.zone ~= myZone then return e, r end
  end
end

-- Why a summoner is skipped in the rotation (nil = available).
function ns:LockReason(name)
  local shards, afk
  if name == ns.Me() then
    shards, afk = ns.GetShards(), UnitIsAFK("player")
  else
    local p = ns.peers[name]
    if not p or (GetTime() - p.seen) >= 35 then return "needs the addon" end
    shards, afk = p.shards or 0, p.afk
  end
  if afk then return "AFK" end
  if shards <= 0 then return "no shards" end
end

function ns:ShardsOf(name)
  if name == ns.Me() then return ns.GetShards() end
  return ns.peers[name] and ns.peers[name].shards or 0
end

-- Round robin from the last caster, skipping anyone without shards / AFK.
function ns:NextUp()
  local list = self:ActiveSummoners()
  local n = #list
  if n == 0 then return nil end
  local start = 0
  for i, name in ipairs(list) do
    if name == ns.S.lastCaster then start = i end
  end
  for k = 1, n do
    local name = list[(start + k - 1) % n + 1]
    if not self:LockReason(name) then return name end
  end
end

---------------------------------------------------------------------------
-- Summoning session: OFF by default. While off, the addon never acts on
-- its own (no raid conversion, no auto-invites, no whisper replies).
---------------------------------------------------------------------------
function ns:IsActive()
  return ns.S and ns.S.active == true
end

-- Raid only when it's actually needed: another summoner needs assist
-- (only exists in raids), or the party is nearly full.
function ns:NeedsRaid()
  if not IsInGroup() or IsInRaid() then return false end
  return #self:ActiveSummoners() >= 2 or GetNumGroupMembers() >= 4
end

function ns:StartSession()
  if not self:IsLeader() then return end
  self:Do("SESSION", { on = true })
  -- This runs from a click, so convert right away if the group needs it.
  if ns.IsGroupLeader("player") and self:NeedsRaid() then ns.API.ConvertToRaid() end
end

function ns:StopSession()
  if not self:IsLeader() then return end
  self:Do("SESSION", { on = false })
end

---------------------------------------------------------------------------
-- Leader: picking summoners
---------------------------------------------------------------------------
-- Who the leader can pick: warlocks in the group who aren't customers in
-- the queue. Me first, then everyone else alphabetically.
function ns:SummonerCandidates()
  local me, S = ns.Me(), ns.S
  local out = {}
  for name, r in pairs(ns.roster) do
    if name ~= me and not S.queue[name] and r.class == "WARLOCK" then out[#out + 1] = name end
  end
  table.sort(out)
  table.insert(out, 1, me)
  return out
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
function ns:SetSummoner(name, on)
  if not self:IsLeader() then return end
  local list = {}
  for _, n in ipairs(ns.S.summoners) do
    if n ~= name then list[#list + 1] = n end
  end
  if on then
    list[#list + 1] = name
    -- This runs from a click, so the game lets us hand out assist right now.
    -- (Assist only exists in raids; outside a session we never convert.)
    local r = ns.roster[name]
    if ns.IsGroupLeader("player") and IsInRaid() and r and r.rank == 0 then
      PromoteToAssistant(r.unit)
    end
  end
  self:Do("SUMMONERS", { list = list })
end

-- Summoners (other than me) who can't invite yet. Only the leader can fix it.
function ns:SummonersNeedingAssist()
  local out = {}
  if not self:IsActive() or not ns.IsGroupLeader("player") or not IsInRaid() then return out end
  for _, n in ipairs(self:ActiveSummoners()) do
    local r = ns.roster[n]
    if n ~= ns.Me() and r and r.rank == 0 then out[#out + 1] = n end
  end
  return out
end

function ns:Promote(name)
  local r = ns.roster[name]
  if r and ns.IsGroupLeader("player") then PromoteToAssistant(r.unit) end
end

---------------------------------------------------------------------------
-- Blacklist
---------------------------------------------------------------------------
function ns:IsBlacklisted(name)
  local e = ns.db.blacklist[name]
  if e and not e.del then return e end
end

function ns:BLSet(name, reason, del)
  name = ns.Full(name)
  local e = { by = ns.Me(), at = GetServerTime(), reason = reason, del = del or nil }
  ns.db.blacklist[name] = e
  if IsInGroup() then self:Send({ t = "BL", list = { [name] = e } }, self:SummonerTargets()) end
  self:Refresh()
end

local function ago(t)
  local d = GetServerTime() - (t or 0)
  if d < 3600 then return "just now" end
  if d < 86400 then return ("%dh ago"):format(math.floor(d / 3600)) end
  local days = math.floor(d / 86400)
  return days == 1 and "yesterday" or ("%d days ago"):format(days)
end

function ns:InviteAnyway(name)
  ns.blHit = nil
  if self:CanInvite() then ns.API.Invite(name) end
  self:Do("ADD", { name = name, by = ns.Me(), inviteOk = self:CanInvite() })
end

---------------------------------------------------------------------------
-- What should I do right now? Drives the banner and the big button.
-- Returns { text, label?, fn? | summon = { unit, name }, alt? = { label, fn } }
---------------------------------------------------------------------------
function ns:NextAction()
  local me = ns.Me()
  local S = ns.S

  if not self:IsActive() then
    if self:IsLeader() then
      return { text = "Closed. Click Open for business when your summoners are ready." }
    end
    return { text = "Closed. The group leader opens for business." }
  end

  if IsInGroup() and not self:IsSummoner(me) then
    return { text = "You're not one of this group's summoners. If you're waiting for a summon, sit tight!" }
  end

  local need = self:SummonersNeedingAssist()
  if #need > 0 then
    local n = ns.Short(need[1])
    return {
      text = ("%s can't invite customers yet."):format(n),
      label = "Give " .. n .. " assist",
      fn = function() ns:Promote(need[1]) end,
    }
  end

  local left = next(ns.leftUnpaid)
  if left then
    local n = ns.Short(left)
    return {
      text = ("%s left without paying you."):format(n),
      label = "Blacklist " .. n,
      fn = function() ns.leftUnpaid[left] = nil; ns:BLSet(left, "left without paying " .. ns.Short(me)) end,
      alt = { label = "Let it go", fn = function() ns.leftUnpaid[left] = nil; ns:Refresh() end },
    }
  end

  local queue = self:SortedQueue()
  for _, e in ipairs(queue) do
    if e.caster == me and e.status == "PAID" then
      local n = ns.Short(e.name)
      return {
        text = ("%s paid %s. Send them off!"):format(n, ns.Money(e.paid)),
        label = "Kick " .. n,
        fn = function() ns:Kick(e.name) end,
      }
    end
  end
  for _, e in ipairs(queue) do
    if e.caster == me and e.status == "ARRIVED" then
      local n = ns.Short(e.name)
      local waited = GetServerTime() - (e.arrivedAt or GetServerTime())
      if waited > ns.db.unpaidTimeout then
        return {
          text = ("%s hasn't paid. It's been %s."):format(n, ns.Clock(waited)),
          label = "Kick " .. n,
          fn = function() ns:Kick(e.name, false, true) end,
          alt = { label = "Kick + blacklist", fn = function() ns:Kick(e.name, true) end },
        }
      end
      return {
        text = ("%s arrived. Trade them for %s."):format(n, ns.Money(S.price)),
        label = "Trade " .. n,
        fn = function() ns:Trade(e.name) end,
      }
    end
  end

  local nextUp = self:NextUp()
  local cust, ro = self:NextCustomer()
  if cust and nextUp == me then
    local n = ns.Short(cust.name)
    return {
      text = ("Your turn: summon %s (%s)."):format(n, ro.zone or "?"),
      label = "Summon " .. n,
      summon = { unit = ro.unit, name = cust.name },
    }
  end

  for _, e in ipairs(queue) do
    if e.status == "SUMMONING" then
      if e.caster == me then
        return { text = ("Portal's up. Waiting for %s to accept."):format(ns.Short(e.name)) }
      end
      return { text = ("%s is summoning %s. Click the portal!"):format(ns.Short(e.caster), ns.Short(e.name)) }
    end
  end

  if cust and nextUp then
    return { text = ("%s is up next for %s."):format(ns.Short(nextUp), ns.Short(cust.name)) }
  end
  if cust then
    return { text = "Customers are waiting, but no summoner has shards." }
  end

  local hit = ns.blHit
  if hit and GetTime() - hit.at < 120 and not S.queue[hit.name] then
    local n = ns.Short(hit.name)
    return {
      text = ("%s whispered, but they're blacklisted: %s, %s (by %s). Not invited."):format(
        n, hit.entry.reason or "no reason", ago(hit.entry.at), ns.Short(hit.entry.by)),
      label = "Invite anyway",
      fn = function() ns:InviteAnyway(hit.name) end,
      alt = { label = "Ignore", fn = function() ns.blHit = nil; ns:Refresh() end },
    }
  end
  return { text = "No customers yet." }
end

---------------------------------------------------------------------------
-- Leader housekeeping (runs every 2s on whoever holds the state)
---------------------------------------------------------------------------
function ns:AuthorityTick()
  if not IsInGroup() then return end
  local S, changed, now = ns.S, false, GetServerTime()

  if self:IsActive() and ns.IsGroupLeader("player") and self:NeedsRaid() then
    ns.API.ConvertToRaid()
  end

  local myZone = GetRealZoneText()
  local leavers = {}
  for name, e in pairs(S.queue) do
    local r = ns.roster[name]
    if e.status == "INVITED" then
      if r then
        e.status = "GROUP"; changed = true
      elseif now - (e.added or now) > 90 then
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
          local L = ns:Ledger(e.caster)
          L.failed = L.failed + 1
        end
        e.status, e.caster, e.castAt = "GROUP", nil, nil; changed = true
      end
    end
  end

  -- Summoners: the leader is always one; drop anyone who left or is a customer.
  local list, seen = {}, {}
  if ns.IsGroupLeader("player") then list[1] = ns.Me(); seen[ns.Me()] = true end
  for _, n in ipairs(S.summoners) do
    if not seen[n] and ns.roster[n] and not S.queue[n] then
      list[#list + 1] = n; seen[n] = true
    end
  end
  local differs = #list ~= #S.summoners
  for i = 1, #list do
    if list[i] ~= S.summoners[i] then differs = true end
  end
  if differs then S.summoners = list; changed = true end

  if changed then self:Changed() end
  -- Tell everyone, so the summoner who's owed can choose to blacklist.
  for _, l in ipairs(leavers) do self:Do("LEFT", l) end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function ns:PortalAlert(caster, target)
  if caster == ns.Me() or not self:IsSummoner(ns.Me()) then return end
  local text = ("%s's portal is up for %s. CLICK IT!"):format(ns.Short(caster), ns.Short(target))
  RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
  PlaySound(SOUNDKIT.RAID_WARNING)
end

function ns:Trade(name)
  local r = ns.roster[name]
  if r then InitiateTrade(r.unit) end
end

function ns:Kick(name, blacklist, silent)
  if blacklist then
    self:BLSet(name, "didn't pay " .. ns.Short(ns.Me()))
  elseif not silent and ns.db.thanks ~= "" then
    ns.API.SendChat(ns.db.thanks, "WHISPER", nil, name)
  end
  if self:CanInvite() then
    ns.API.Uninvite(name)
  else
    ns.Print("You need assist to kick. Ask the leader.")
  end
  self:Do("REMOVE", { name = name })
end

function ns:Reinvite(name)
  if self:CanInvite() then ns.API.Invite(name) end
end

---------------------------------------------------------------------------
-- Advertising (leader only)
---------------------------------------------------------------------------
function ns:JoinedChannels()
  local list, t = {}, { GetChannelList() }
  for i = 1, #t, 3 do
    local id, name, disabled = t[i], t[i + 1], t[i + 2]
    if type(id) == "number" and type(name) == "string" and not disabled then
      list[#list + 1] = { id = id, name = name }
    end
  end
  return list
end

-- Ticked channels you're currently in. Until you pick, Trade is ticked.
function ns:AdChannels()
  local sel, out = ns.db.channels, {}
  for _, ch in ipairs(self:JoinedChannels()) do
    local on
    if sel then on = sel[ch.name] else on = ch.name:lower():find("^trade") ~= nil end
    if on then out[#out + 1] = ch end
  end
  return out
end

function ns:IsAdChannel(name)
  local sel = ns.db.channels
  if sel then return sel[name] == true end
  return name:lower():find("^trade") ~= nil
end

function ns:SetAdChannel(name, on)
  if not ns.db.channels then
    ns.db.channels = {}
    for _, ch in ipairs(self:AdChannels()) do ns.db.channels[ch.name] = true end
  end
  ns.db.channels[name] = on or nil
end

function ns:AdText()
  local waiting = #self:Waiting()
  local text = ns.db.adText
    :gsub("{city}", GetRealZoneText() or "")
    :gsub("{price}", ns.Money(ns.S.price))
    :gsub("{queue}", waiting > 0 and (" - " .. waiting .. " in queue") or " - no wait!")
  return text
end

function ns:AdCooldownLeft()
  if not ns.adDoneAt then return 0 end
  return math.max(0, ns.db.adCooldown - (GetTime() - ns.adDoneAt))
end

-- Returns label, enabled
function ns:AdButtonState()
  if #self:AdChannels() == 0 then return "Advertise (pick a channel)", false end
  local cd = self:AdCooldownLeft()
  if cd > 0 then return "Advertise " .. ns.Clock(cd), false end
  return "Advertise", true
end

-- One click posts to every ticked channel (confirmed on Forever).
function ns:Advertise()
  if not self:IsLeader() or not self:IsActive() then return end
  local chans = self:AdChannels()
  if #chans == 0 or self:AdCooldownLeft() > 0 then return end
  local text = self:AdText()
  for _, ch in ipairs(chans) do ns.API.SendChat(text, "CHANNEL", nil, ch.id) end
  ns.adDoneAt = GetTime()
  self:Refresh()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Whisper intake: works for every summoner; ordering is best effort.
ns:On("CHAT_MSG_WHISPER", function(text, sender)
  if ns.IsSecret(text) or ns.IsSecret(sender) then return end
  if not ns:IsActive() then return end
  if IsInGroup() and not ns:IsSummoner(ns.Me()) then return end
  local word = text:lower():match("^%s*(.-)%s*$")
  local hit = false
  for _, k in ipairs(ns.db.keywords) do
    if word == k then hit = true; break end
  end
  if not hit then return end

  local name = ns.Full(sender)
  local bl = ns:IsBlacklisted(name)
  if bl then
    ns.blHit = { name = name, entry = bl, at = GetTime() } -- banner offers "Invite anyway"
    ns:Refresh()
    return
  end

  local e = ns.S.queue[name]
  if not e then
    local ok = false
    if ns:CanInvite() then
      ns.API.Invite(name)
      ok = true
    end
    ns:Do("ADD", { name = name, by = ns.Me(), inviteOk = ok })
  elseif e.status == "INVITED" and not ns.roster[name] and ns:CanInvite() then
    -- They missed or declined the first invite and asked again: re-send it,
    -- but keep their original place in line.
    ns.API.Invite(name)
  end

  ns.API.SendChat(("Invite sent - you're #%d in queue. %s, paid after you arrive to the warlock who summoned you.")
    :format(ns:QueuePosition(name), ns.Money(ns.S.price)), "WHISPER", nil, name)
end)

-- Detect our own summons. The big button records its target in PreClick.
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit ~= "player" or not ns:IsActive() or not ns.IsSummonSpell(spellID) then return end
  local target = ns.pendingTarget or ns.UnitKey("target")
  ns.pendingTarget = nil
  if target then ns:Do("CAST", { caster = ns.Me(), target = target }) end
end)

-- Payment detection: whoever receives the gold gets the credit.
local trade = {}
ns:On("TRADE_SHOW", function()
  trade.partner = ns.UnitKey("NPC")
  trade.money = 0
end)
ns:On("TRADE_MONEY_CHANGED", function() trade.money = GetTargetTradeMoney() or 0 end)
ns:On("TRADE_ACCEPT_UPDATE", function() trade.money = GetTargetTradeMoney() or trade.money end)
ns:On("UI_INFO_MESSAGE", function(_, message)
  if message ~= ERR_TRADE_COMPLETE or not trade.partner then return end
  local name, amount = trade.partner, trade.money or 0
  trade.partner = nil
  if not ns.S.queue[name] or amount <= 0 then return end
  ns:Do("PAID", { caster = ns.Me(), target = name, amount = amount })
  ns.db.lifetime.copper = ns.db.lifetime.copper + amount
  ns.db.lifetime.summons = ns.db.lifetime.summons + 1
  if amount < ns.S.price then
    ns.Print(("%s underpaid: %s of %s."):format(ns.Short(name), ns.Money(amount), ns.Money(ns.S.price)))
  end
end)

local wasInGroup = false
ns:On("GROUP_ROSTER_UPDATE", function()
  ns:ScanRoster()
  local inGroup = IsInGroup()
  if inGroup and not wasInGroup then
    -- Joined someone else's group: start off. If they're summoning and pick
    -- us, the leader's addon switches us on.
    if not ns.IsGroupLeader("player") then ns.S.active = false end
    ns:SendHello()
  elseif wasInGroup and not inGroup then
    -- Left the group: the session ends for us.
    ns.S.active = false
    ns.S.queue = {}
    ns.leftUnpaid, ns.blHit = {}, nil
  end
  wasInGroup = inGroup
  ns:CheckAuthority()
  ns:Refresh()
end)

ns:On("PLAYER_FLAGS_CHANGED", function(unit)
  if unit == "player" then ns:SendHeartbeat(); ns:Refresh() end
end)
ns:On("BAG_UPDATE_DELAYED", function() ns:Refresh() end)
ns:On("CHANNEL_UI_UPDATE", function() ns:Refresh() end)

-- Logging in (not a /reload) always starts with the session off.
ns:On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  if isLogin and not isReload and ns.S then
    ns.S.active = false
    ns:Refresh()
  end
end)

ns:On("PLAYER_LOGIN", function()
  ns.db.state = ns.db.state or newState()
  ns.S = ns.db.state
  ns.S.summoners = ns.S.summoners or {}
  ns:ScanRoster()
  wasInGroup = IsInGroup()
  if wasInGroup then ns:SendHello() end
  ns:CheckAuthority()

  C_Timer.NewTicker(1, ns.Safe(function()
    ns:ScanRoster()
    if ns:IsAuthority() then ns:AuthorityTick() end
    ns:Refresh()
  end))
  C_Timer.NewTicker(10, ns.Safe(function() ns:SendHeartbeat() end))
  C_Timer.NewTicker(30, ns.Safe(function() ns:SendSnapshot() end))
end)

---------------------------------------------------------------------------
-- Slash commands (everything day-to-day is in the window)
---------------------------------------------------------------------------
local HELP = {
  "/sc - show/hide the window",
  "/sc keywords inv,invite,summon,+ - whisper triggers",
  "/sc thanks <text> - whisper sent when you kick a paid customer",
  "/sc bl add First Last [reason] | bl del First Last | bl list",
  "/sc reset - reset the session earnings",
  "/sc stats - lifetime earnings",
}

SLASH_SUMMONCIRCLE1 = "/sc"
SLASH_SUMMONCIRCLE2 = "/summoncircle"
local function slash(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()

  if cmd == "" then
    ns:ToggleUI()
  elseif cmd == "keywords" then
    local list = {}
    for k in rest:gmatch("[^,%s]+") do list[#list + 1] = k:lower() end
    if #list > 0 then ns.db.keywords = list end
    ns.Print("Keywords: " .. table.concat(ns.db.keywords, ", "))
  elseif cmd == "thanks" then
    ns.db.thanks = rest
    ns.Print("Thanks message: " .. (rest ~= "" and rest or "(none)"))
  elseif cmd == "bl" then
    -- Names are two words ("Ash Lock"); anything after is the reason.
    local sub, args = rest:match("^(%S*)%s*(.-)$")
    local first, last, reason = args:match("^(%S+)%s+(%S+)%s*(.-)$")
    local name = first and (first .. " " .. last)
    if sub == "add" and name then
      ns:BLSet(name, reason ~= "" and reason or nil)
      ns.Print("Blacklisted " .. name)
    elseif sub == "del" and name then
      ns:BLSet(name, nil, true)
      ns.Print("Removed " .. name .. " from the blacklist")
    elseif sub == "add" or sub == "del" then
      ns.Print("Use the full name, e.g. /sc bl " .. sub .. " Ash Lock")
    else
      local any = false
      for n, e in pairs(ns.db.blacklist) do
        if not e.del then
          any = true
          ns.Print(("%s - %s (by %s)"):format(n, e.reason or "no reason", ns.Short(e.by)))
        end
      end
      if not any then ns.Print("Blacklist is empty.") end
    end
  elseif cmd == "debug" then
    local P = ns.Print
    local inst = LE_PARTY_CATEGORY_INSTANCE
    P("version", C_AddOns.GetAddOnMetadata(ADDON, "Version"), "| me", ns.Me())
    P("name sources: UnitName [" .. tostring(UnitName("player")) .. "] GetUnitName ["
      .. tostring(GetUnitName("player", true)) .. "] UnitFullName [" .. tostring((UnitFullName("player"))) .. "]")
    P("in group", tostring(IsInGroup()), "| raid", tostring(IsInRaid()),
      "| dungeon-finder group", tostring(inst and IsInGroup(inst) or false))
    P("I'm leader: normal", tostring(UnitIsGroupLeader("player")),
      "| dungeon-finder", tostring(inst and UnitIsGroupLeader("player", inst) or false))
    for n, r in pairs(ns.roster) do
      P("  group:", n, "| rank", r.rank, "| has addon", tostring(ns:HasAddon(n)))
    end
    for n in pairs(ns.peers) do P("  addon heard from:", n) end
    P("queue holder", ns:AuthorityName(), "| summoners:",
      #ns.S.summoners > 0 and table.concat(ns.S.summoners, ", ") or "(none)")
  elseif cmd == "reset" then
    ns:Do("RESET", {})
    ns.Print("Session earnings reset.")
  elseif cmd == "stats" then
    ns.Print(("Lifetime: %s from %d summons."):format(ns.Money(ns.db.lifetime.copper), ns.db.lifetime.summons))
  else
    for _, line in ipairs(HELP) do ns.Print(line) end
  end
end

SlashCmdList.SUMMONCIRCLE = ns.Safe(slash)
