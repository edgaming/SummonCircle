-- Summon Circle: posting the ad (leader only). One click posts to every
-- ticked channel, then a cooldown.
local ADDON, ns = ...
local Advertise = ns:Module("Advertise")

Advertise.doneAt = nil -- GetTime() of the last ad

-- Player communities are listed as "Community:<club>:<stream>". Show the
-- community's name instead ("Summoners Guild", or "Summoners Guild - Trade"
-- for a channel other than its General one). The raw name stays the key.
function Advertise.ChannelLabel(name)
  local club, stream = name:match("^Community:(%d+):(%d+)$")
  if not club or not C_Club then return name end
  local ok, info = pcall(C_Club.GetClubInfo, club)
  if not ok or type(info) ~= "table" or not info.name or info.name == "" then return name end
  local ok2, s = pcall(C_Club.GetStreamInfo, club, stream)
  if ok2 and type(s) == "table" and s.name and s.name ~= "" and s.streamType ~= 0 and s.name ~= "General" then
    return info.name .. " - " .. s.name
  end
  return info.name
end

function Advertise.JoinedChannels()
  local list, t = {}, { GetChannelList() }
  for i = 1, #t, 3 do
    local id, name, disabled = t[i], t[i + 1], t[i + 2]
    if type(id) == "number" and type(name) == "string" and not disabled then
      list[#list + 1] = { id = id, name = name, label = Advertise.ChannelLabel(name) }
    end
  end
  return list
end

-- Until you pick, Trade is ticked.
function Advertise.IsChannel(name)
  local sel = ns.db.channels
  if sel then return sel[name] == true end
  return name:lower():find("^trade") ~= nil
end

-- Ticked channels you're currently in.
function Advertise.Channels()
  local out = {}
  for _, ch in ipairs(Advertise.JoinedChannels()) do
    if Advertise.IsChannel(ch.name) then out[#out + 1] = ch end
  end
  return out
end

function Advertise.SetChannel(name, on)
  if not ns.db.channels then
    ns.db.channels = {}
    for _, ch in ipairs(Advertise.Channels()) do ns.db.channels[ch.name] = true end
  end
  ns.db.channels[name] = on or nil
end

function Advertise.Text()
  local waiting = #ns.Queue.Waiting()
  local text = ns.db.adText
    :gsub("{city}", ns.ZoneText() or "")
    :gsub("{price}", ns.Money(ns.S.price))
    :gsub("{queue}", waiting > 0 and (waiting .. " in queue") or "no wait!")
  return text
end

function Advertise.CooldownLeft()
  if not Advertise.doneAt then return 0 end
  return math.max(0, ns.db.adCooldown - (GetTime() - Advertise.doneAt))
end

-- Returns label, enabled
function Advertise.ButtonState()
  if #Advertise.Channels() == 0 then return "Advertise (pick a channel)", false end
  local cd = Advertise.CooldownLeft()
  if cd > 0 then return "Advertise " .. ns.Clock(cd), false end
  return "Advertise", true
end

function Advertise.Post()
  if not ns.Roster.IsLeader() or not ns.Session.IsActive() then return end
  local chans = Advertise.Channels()
  if #chans == 0 or Advertise.CooldownLeft() > 0 then return end
  local text = Advertise.Text()
  for _, ch in ipairs(chans) do ns.API.SendChat(text, "CHANNEL", nil, ch.id) end
  Advertise.doneAt = GetTime()
  ns.Update()
end
