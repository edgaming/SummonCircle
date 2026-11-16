-- Summon Circle: who's in the group, who runs the addon, who leads.
--
-- Emits:
--   GROUP_JOINED              we just joined (or formed) a group
--   GROUP_LEFT                we just left our group
--   ROSTER_CHANGED            any group change, after the two above
--   PEER_SEEN(name, hello, isNew)  another addon user checked in
local ADDON, ns = ...
local Roster = ns:Module("Roster")
local Transport = ns.Transport

Roster.members = {} -- ["First Last"] = { unit, zone, map, online, rank, class }
Roster.peers = {}   -- ["First Last"] = { shards, afk, seen }  (other addon users)

-- The map a unit is on (id, name), or nil if the game won't say.
function Roster.MapOf(unit)
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local ok, id = pcall(C_Map.GetBestMapForUnit, unit)
  if not ok or type(id) ~= "number" or ns.IsSecret(id) then return nil end
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
  local name = info and info.name
  if ns.IsSecret(name) then name = nil end
  return id, name
end

function Roster.Scan()
  local members = Roster.members
  wipe(members)
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local name, rank, _, _, _, class, zone, online = GetRaidRosterInfo(i)
      if ns.IsSecret(zone) then zone = nil end
      if ns.IsSecret(class) then class = nil end
      local key = ns.UnitKey("raid" .. i) or (name and ns.Full(name))
      if key then
        local map = Roster.MapOf("raid" .. i)
        members[key] = { unit = "raid" .. i, zone = zone, map = map, online = online, rank = rank, class = class }
      end
    end
  elseif IsInGroup() then
    for _, u in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
      local key = UnitExists(u) and ns.UnitKey(u)
      if key then
        -- Parties don't report zones like raids do; ask for the map instead.
        local map, mapName = Roster.MapOf(u)
        members[key] = {
          unit = u, online = UnitIsConnected(u), rank = ns.IsGroupLeader(u) and 2 or 0,
          class = select(2, UnitClass(u)), zone = mapName, map = map,
        }
      end
    end
  end
  for name in pairs(Roster.peers) do
    if not members[name] then Roster.peers[name] = nil end
  end
end

-- Is this group member where I am? Same map, or the same zone name.
function Roster.IsHere(r)
  if not r then return false end
  local myMap = Roster.MapOf("player")
  if r.map and myMap and r.map == myMap then return true end
  local zone = ns.ZoneText()
  return r.zone ~= nil and zone ~= nil and r.zone == zone
end

function Roster.Get(name)
  return Roster.members[name]
end

function Roster.HasAddon(name)
  return name == ns.Me() or Roster.peers[name] ~= nil
end

function Roster.GroupLeaderName()
  for name, r in pairs(Roster.members) do
    if r.rank == 2 then return name end
  end
end

-- Leader controls (open/close, summoner picker, price, Advertise) belong to
-- the actual group leader, or to you when you're solo.
function Roster.IsLeader()
  return not IsInGroup() or ns.IsGroupLeader("player")
end

function Roster.CanInvite()
  if not IsInGroup() then return true end
  return ns.IsGroupLeader("player") or ns.IsGroupAssistant("player")
end

---------------------------------------------------------------------------
-- Presence: HELLO on joining, a heartbeat every 10 s (shards, AFK).
-- Sent to the whole group: it reveals nothing about the circle.
---------------------------------------------------------------------------
local function presence(t)
  return { t = t, shards = ns.GetShards(), afk = ns.IsAFK("player") }
end

function Roster.SendHello()
  Transport.Send(presence("HELLO"))
end

function Roster.SendHeartbeat()
  if IsInGroup() then Transport.Send(presence("HB")) end
end

local function onPresence(sender, msg)
  -- Only group members count as peers (an addon whisper can come from anyone).
  if not Roster.members[sender] then Roster.Scan() end
  if not Roster.members[sender] then return end
  local isNew = Roster.peers[sender] == nil
  Roster.peers[sender] = { shards = msg.shards or 0, afk = msg.afk, seen = GetTime() }
  ns.Emit("PEER_SEEN", sender, msg.t == "HELLO", isNew)
  ns.Update()
end
Transport.Handle("HELLO", onPresence)
Transport.Handle("HB", onPresence)

---------------------------------------------------------------------------
-- Group changes
---------------------------------------------------------------------------
local wasInGroup = false

function Roster.OnGroupChanged()
  Roster.Scan()
  local inGroup = IsInGroup()
  if inGroup and not wasInGroup then
    ns.Emit("GROUP_JOINED")
    Roster.SendHello()
  elseif wasInGroup and not inGroup then
    ns.Emit("GROUP_LEFT")
  end
  wasInGroup = inGroup
  ns.Emit("ROSTER_CHANGED")
  ns.Update()
end

ns.On("GROUP_ROSTER_UPDATE", Roster.OnGroupChanged)

ns.On("PLAYER_FLAGS_CHANGED", function(unit)
  if unit == "player" then Roster.SendHeartbeat(); ns.Update() end
end)

ns.On("PLAYER_LOGIN", function()
  Roster.Scan()
  wasInGroup = IsInGroup()
  if wasInGroup then Roster.SendHello() end
  C_Timer.NewTicker(10, ns.Safe(Roster.SendHeartbeat))
end)
