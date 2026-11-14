-- Summon Circle: the summoning session, who the summoners are, and the price.
--
-- The session is OFF by default. While it's off the addon never acts on its
-- own: no raid conversion, no auto-invites, no whisper replies.
local ADDON, ns = ...
local Session = ns:Module("Session")
local Sync, Roster = ns.Sync, ns.Roster

function Session.IsActive()
  return ns.S ~= nil and ns.S.active == true
end

function Session.IsSummoner(name)
  if not IsInGroup() then return name == ns.Me() end
  for _, n in ipairs(ns.S.summoners) do
    if n == name then return true end
  end
  return false
end

-- Summoners currently in the group, in rotation order.
function Session.ActiveSummoners()
  if not IsInGroup() then return { ns.Me() } end
  local out = {}
  for _, n in ipairs(ns.S.summoners) do
    if Roster.members[n] then out[#out + 1] = n end
  end
  return out
end

-- Raid only when it's actually needed: another summoner needs assist
-- (only exists in raids), or the party is nearly full.
function Session.NeedsRaid()
  if not IsInGroup() or IsInRaid() then return false end
  return #Session.ActiveSummoners() >= 2 or GetNumGroupMembers() >= 4
end

function Session.Start()
  if not Roster.IsLeader() then return end
  Sync.Do("SESSION", { on = true })
  -- This runs from a click, so convert right away if the group needs it.
  if ns.IsGroupLeader("player") and Session.NeedsRaid() then ns.API.ConvertToRaid() end
end

function Session.Stop()
  if not Roster.IsLeader() then return end
  Sync.Do("SESSION", { on = false })
end

function Session.SetPrice(copper)
  ns.db.price = copper
  Sync.Do("PRICE", { price = copper })
end

---------------------------------------------------------------------------
-- Picking summoners (leader)
---------------------------------------------------------------------------
-- Who the leader can pick: warlocks in the group who aren't customers in
-- the queue. Me first, then everyone else alphabetically.
function Session.Candidates()
  local me, S = ns.Me(), ns.S
  local out = {}
  for name, r in pairs(Roster.members) do
    if name ~= me and not S.queue[name] and r.class == "WARLOCK" then out[#out + 1] = name end
  end
  table.sort(out)
  table.insert(out, 1, me)
  return out
end

function Session.SetSummoner(name, on)
  if not Roster.IsLeader() then return end
  local list = {}
  for _, n in ipairs(ns.S.summoners) do
    if n ~= name then list[#list + 1] = n end
  end
  if on then
    list[#list + 1] = name
    -- This runs from a click, so the game lets us hand out assist right now.
    -- (Assist only exists in raids; outside a session we never convert.)
    local r = Roster.members[name]
    if ns.IsGroupLeader("player") and IsInRaid() and r and r.rank == 0 then
      PromoteToAssistant(r.unit)
    end
  end
  Sync.Do("SUMMONERS", { list = list })
end

-- Summoners (other than me) who can't invite yet. Only the leader can fix it.
function Session.NeedingAssist()
  local out = {}
  if not Session.IsActive() or not ns.IsGroupLeader("player") or not IsInRaid() then return out end
  for _, n in ipairs(Session.ActiveSummoners()) do
    local r = Roster.members[n]
    if n ~= ns.Me() and r and r.rank == 0 then out[#out + 1] = n end
  end
  return out
end

function Session.Promote(name)
  local r = Roster.members[name]
  if r and ns.IsGroupLeader("player") then PromoteToAssistant(r.unit) end
end

---------------------------------------------------------------------------
-- Ops
---------------------------------------------------------------------------
Sync.RegisterOp("SESSION", function(m)
  ns.S.active = m.on and true or false
  if m.on then
    ns.S.ledger, ns.S.sessionStart = {}, m.at -- earnings count per session
  end
end)

Sync.RegisterOp("SUMMONERS", function(m)
  local old = ns.S.summoners
  ns.S.summoners = m.list
  ns.Emit("SUMMONERS_CHANGED", old, m.list)
end)

Sync.RegisterOp("PRICE", function(m) ns.S.price = m.price end)

---------------------------------------------------------------------------
-- Housekeeping (authority): raid when needed (first); then, after the
-- queue's housekeeping, keep the summoner list tidy: the leader is always
-- a summoner; drop summoners who left or became customers.
---------------------------------------------------------------------------
Sync.OnTick(10, function()
  if Session.IsActive() and ns.IsGroupLeader("player") and Session.NeedsRaid() then
    ns.API.ConvertToRaid()
  end
end)

Sync.OnTick(30, function()
  local S = ns.S
  local list, seen = {}, {}
  if ns.IsGroupLeader("player") then list[1] = ns.Me(); seen[ns.Me()] = true end
  for _, n in ipairs(S.summoners) do
    if not seen[n] and Roster.members[n] and not S.queue[n] then
      list[#list + 1] = n; seen[n] = true
    end
  end
  local differs = #list ~= #S.summoners
  for i = 1, #list do
    if list[i] ~= S.summoners[i] then differs = true end
  end
  if differs then S.summoners = list end
  return differs
end)

---------------------------------------------------------------------------
-- When the session turns off by itself
---------------------------------------------------------------------------
-- Joined someone else's group: start off. If they're summoning and pick us,
-- the leader's addon switches us on.
ns.Listen("GROUP_JOINED", function()
  if not ns.IsGroupLeader("player") then ns.S.active = false end
end)

-- Left the group: the session ends for us.
ns.Listen("GROUP_LEFT", function() ns.S.active = false end)

-- Logging in (not a /reload) always starts with the session off.
ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  if isLogin and not isReload and ns.S then
    ns.S.active = false
    ns.Update()
  end
end)
