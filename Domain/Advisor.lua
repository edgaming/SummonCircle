-- Summon Circle: "what should I do right now?" Drives the banner and the
-- big button. Read-only: it looks at the state and returns one step.
--
-- Returns { text, label?, fn? | summon = { unit, name }, alt? = { label, fn } }
-- The first rule that applies wins, so the order below is the priority.
local ADDON, ns = ...
local Advisor = ns:Module("Advisor")
local Roster, Session, Queue, Rotation, Blacklist =
  ns.Roster, ns.Session, ns.Queue, ns.Rotation, ns.Blacklist

local BL_HIT_WINDOW = 120 -- seconds the "blacklisted whisper" prompt stays up

local function closed()
  if Roster.IsLeader() then
    return { text = "Closed. Click Open for business when your summoners are ready." }
  end
  local leaderName = Roster.GroupLeaderName()
  if leaderName and not Roster.HasAddon(leaderName) then
    return { text = ("Closed. The group leader (%s) needs Summon Circle to open for business."):format(ns.Short(leaderName)) }
  end
  return { text = "Closed. The group leader opens for business." }
end

local function needsAssist()
  local need = Session.NeedingAssist()
  if #need == 0 then return end
  local n = ns.Short(need[1])
  return {
    text = ("%s can't invite customers yet."):format(n),
    label = "Give " .. n .. " assist",
    fn = function() Session.Promote(need[1]) end,
  }
end

local function leftUnpaid(me)
  local left = next(Queue.leftUnpaid)
  if not left then return end
  local n = ns.Short(left)
  return {
    text = ("%s left without paying you."):format(n),
    label = "Blacklist " .. n,
    fn = function()
      Queue.leftUnpaid[left] = nil
      Blacklist.Set(left, "left without paying " .. ns.Short(me))
    end,
    alt = { label = "Let it go", fn = function() Queue.ForgetUnpaid(left) end },
  }
end

local function myCustomers(me, queue, price)
  for _, e in ipairs(queue) do
    if e.caster == me and e.status == "PAID" then
      local n = ns.Short(e.name)
      return {
        text = ("%s paid %s. Send them off!"):format(n, ns.Money(e.paid)),
        label = "Kick " .. n,
        fn = function() Queue.Kick(e.name) end,
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
          fn = function() Queue.Kick(e.name, false, true) end,
          alt = { label = "Kick + blacklist", fn = function() Queue.Kick(e.name, true) end },
        }
      end
      return {
        text = ("%s arrived. Trade them for %s."):format(n, ns.Money(price)),
        label = "Trade " .. n,
        fn = function() Queue.Trade(e.name) end,
      }
    end
  end
end

local function blacklistHit(S)
  local hit = Blacklist.hit
  if not (hit and GetTime() - hit.at < BL_HIT_WINDOW and not S.queue[hit.name]) then return end
  local n = ns.Short(hit.name)
  return {
    text = ("%s whispered, but they're blacklisted: %s, %s (by %s). Not invited."):format(
      n, hit.entry.reason or "no reason", ns.Ago(hit.entry.at, GetServerTime()), ns.Short(hit.entry.by)),
    label = "Invite anyway",
    fn = function() Queue.InviteAnyway(hit.name) end,
    alt = { label = "Ignore", fn = function() Blacklist.ClearHit() end },
  }
end

function Advisor.NextAction()
  local me, S = ns.Me(), ns.S

  if not Session.IsActive() then return closed() end

  if IsInGroup() and not Session.IsSummoner(me) then
    return { text = "You're not one of this group's summoners. If you're waiting for a summon, sit tight!" }
  end

  local step = needsAssist() or leftUnpaid(me)
  if step then return step end

  local queue = Queue.Sorted()
  step = myCustomers(me, queue, S.price)
  if step then return step end

  local nextUp = Rotation.NextUp()
  local cust, ro = Queue.NextCustomer()
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

  return blacklistHit(S) or { text = "No customers yet." }
end
