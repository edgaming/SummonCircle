-- Summon Circle: summon requests read from chat ("leads").
--
-- While the shop is open, every summoner reads the channels ticked for
-- advertising. A line asking for a summon to our city becomes a lead with
-- one-click Whisper and ×. Nothing is ever whispered without a click.
--
-- Whisper or × starts a 10-minute quiet period for that player, for the
-- whole circle (LEAD_CLAIMED), so a customer never gets three identical
-- whispers. Leads live only in memory and are never saved.
--
-- Lead = { from, text, channel, city, offer, at, claimedBy?, claimedAt? }
local ADDON, ns = ...
local Leads = ns:Module("Leads")
local Session, Roster, Transport, Sync = ns.Session, ns.Roster, ns.Transport, ns.Sync

Leads.EXPIRE = 180     -- seconds after the player's last matching message
Leads.QUIET = 600      -- seconds a whispered/dismissed player stays hidden
Leads.SHOW_CLAIM = 30  -- seconds "Bram Lock whispered" stays on screen

Leads.list = {}   -- ["First Last"] = lead
Leads.quiet = {}  -- ["First Last"] = server time their requests show again
Leads.seenAt = 0  -- last time the Requests view was on screen

-- Reading chat is on while the shop is open, we're one of its summoners,
-- and the Advertising panel's "Read these channels" box is ticked.
function Leads.Enabled()
  if ns.db.readRequests == false or not Session.IsActive() then return false end
  return not IsInGroup() or Session.IsSummoner(ns.Me())
end

-- Players we never show: ourselves, anyone already in the group or queue,
-- blacklisted players, and anyone in their quiet period.
function Leads.Skip(name, now)
  if name == ns.Me() or Roster.members[name] or ns.S.queue[name] then return true end
  if ns.Blacklist.Get(name) then return true end
  return (Leads.quiet[name] or 0) > (now or GetServerTime())
end

-- Leads newest first; the ones another summoner already whispered last.
function Leads.Sorted()
  local out = {}
  for _, l in pairs(Leads.list) do out[#out + 1] = l end
  table.sort(out, function(a, b)
    if (a.claimedBy ~= nil) ~= (b.claimedBy ~= nil) then return b.claimedBy ~= nil end
    if a.at ~= b.at then return a.at > b.at end
    return a.from < b.from
  end)
  return out
end

-- Open leads (not already whispered by someone else).
function Leads.Count()
  local n = 0
  for _, l in pairs(Leads.list) do if not l.claimedBy then n = n + 1 end end
  return n
end

-- Any open lead that arrived since the Requests view was last shown?
function Leads.HasUnseen()
  for _, l in pairs(Leads.list) do
    if not l.claimedBy and l.at > Leads.seenAt then return true end
  end
  return false
end

function Leads.MarkSeen(now)
  Leads.seenAt = now or GetServerTime()
end

---------------------------------------------------------------------------
-- Intake
---------------------------------------------------------------------------
-- A chat line from `sender` in `channel` (the name as GetChannelList gives it).
function Leads.OnChat(text, sender, channel)
  if not Leads.Enabled() or not channel or not ns.Advertise.IsChannel(channel) then return end
  local city = ns.Locations.Current()
  if not city then return end
  local name, now = ns.Full(sender), GetServerTime()
  if not name or Leads.Skip(name, now) then return end
  local hit = ns.ChatParser.Classify(text, city, ns.ChatParser.AdFingerprint(ns.db.adText))
  if not hit then return end
  local old = Leads.list[name]
  if old and old.claimedBy then return end
  -- One lead per player: a repeat message refreshes it.
  Leads.list[name] = {
    from = name, text = text, channel = channel, city = city.id, offer = hit.offer, at = now,
  }
  if not old and ns.db.requestSound then PlaySound(SOUNDKIT.TELL_MESSAGE or 3081) end
  ns.Update()
end

local function channelName(index, label)
  for _, ch in ipairs(ns.Advertise.JoinedChannels()) do
    if ch.id == index then return ch.name end
  end
  return label and (label:gsub("^%d+%.%s*", ""))
end

ns.On("CHAT_MSG_CHANNEL", function(text, sender, _, label, _, _, _, index)
  if ns.IsSecret(text) or ns.IsSecret(sender) then return end
  Leads.OnChat(text, sender, channelName(index, label))
end)

---------------------------------------------------------------------------
-- Whisper / dismiss
---------------------------------------------------------------------------
function Leads.WhisperText(lead)
  local city = ns.Locations.Get(lead.city)
  return ("Selling %s summons - %s. Whisper 'inv' if you want a summon."):format(
    city and city.short or "", ns.Money(ns.S.price))
end

local function claim(name, how)
  local untilT = GetServerTime() + Leads.QUIET
  Leads.quiet[name] = untilT
  Leads.list[name] = nil
  Transport.Send({ t = "LEAD_CLAIMED", from = name, by = ns.Me(), quietUntil = untilT, how = how },
    Sync.SummonerTargets())
  ns.Update()
end

function Leads.Whisper(name)
  local lead = Leads.list[name]
  if not lead or lead.claimedBy then return end
  if lead.demo then -- made-up request (/sc demo): nothing is sent
    Leads.list[name] = nil
    return ns.Update()
  end
  ns.Whisper(Leads.WhisperText(lead), name)
  claim(name, "whisper")
end

function Leads.Dismiss(name)
  local lead = Leads.list[name]
  if not lead then return end
  if lead.demo then
    Leads.list[name] = nil
    return ns.Update()
  end
  claim(name, "dismiss")
end

Transport.Handle("LEAD_CLAIMED", function(sender, msg)
  if not Session.IsSummoner(sender) or type(msg.from) ~= "string" then return end
  local untilT = tonumber(msg.quietUntil) or 0
  if untilT > (Leads.quiet[msg.from] or 0) then Leads.quiet[msg.from] = untilT end
  local lead = Leads.list[msg.from]
  if lead and msg.how == "whisper" then
    lead.claimedBy, lead.claimedAt = sender, GetServerTime()
  else
    Leads.list[msg.from] = nil
  end
  ns.Update()
end)

---------------------------------------------------------------------------
-- Housekeeping
---------------------------------------------------------------------------
function Leads.Prune(now)
  now = now or GetServerTime()
  local changed = false
  local on = Leads.Enabled()
  for name, l in pairs(Leads.list) do
    local gone
    if l.demo then
      gone = now - l.at >= 600 -- made-up requests (/sc demo) last 10 minutes
    elseif not on then
      gone = true
    elseif l.claimedBy then
      gone = now - (l.claimedAt or now) >= Leads.SHOW_CLAIM
    else
      gone = now - l.at >= Leads.EXPIRE or Leads.Skip(name, now)
    end
    if gone then Leads.list[name] = nil; changed = true end
  end
  for name, t in pairs(Leads.quiet) do
    if t <= now then Leads.quiet[name] = nil end
  end
  if changed then ns.Update() end
end

ns.Listen("GROUP_LEFT", function() wipe(Leads.list) end)

ns.On("PLAYER_LOGIN", function()
  C_Timer.NewTicker(1, ns.Safe(function() Leads.Prune() end))
end)
