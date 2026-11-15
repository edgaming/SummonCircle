-- Summon Circle: the network. One hidden chat channel per faction
-- (SummonCircleH / SummonCircleA) that every Summon Circle user on that
-- faction joins, so addons can reach each other outside groups.
--
-- Proven in game by the network spike (2026-11-15): joining is silent once
-- the channel is removed from the chat windows, addon messages flow through
-- it, and long messages arrive intact. The game allows 10 messages at once
-- per prefix, then throttles.
--
-- Joining waits a few seconds after login so the game's own channels
-- (General, Trade, ...) keep their usual numbers. If the channel can't be
-- joined (e.g. all 10 channel slots in use), network features are simply
-- off and everything group-based works as before.
--
--   Net.Available()   true once we're in the channel
--   Net.status        "off" | "joining" | "on" | "failed" | "no faction"
--
-- Features send and receive through Transport.SendNet / Transport.HandleNet.
local ADDON, ns = ...
local Net = ns:Module("Net")

Net.JOIN_DELAY = 10 -- seconds after login
Net.RETRIES = 3
Net.status = "off"
Net.received = 0    -- network messages accepted this session (for /sc net)

function Net.Faction()
  local f = UnitFactionGroup("player")
  if f == "Horde" or f == "Alliance" then return f end
end

function Net.ChannelName()
  local f = Net.Faction()
  return f and ("SummonCircle" .. f:sub(1, 1))
end

function Net.Index()
  local name = Net.ChannelName()
  if not name then return nil end
  local id = GetChannelName(name)
  if type(id) == "number" and id > 0 then return id end
end

function Net.Available()
  return Net.status == "on" and Net.Index() ~= nil
end

-- Remove the channel from every chat window so the player never sees it.
local function hide(name)
  local remove = ChatFrame_RemoveChannel or (ChatFrameUtil and ChatFrameUtil.RemoveChannel)
  if not remove then return end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf then pcall(remove, cf, name) end
  end
end

local function ready(name)
  hide(name)
  if Net.status ~= "on" then
    Net.status = "on"
    ns.Emit("NET_READY")
    ns.Update()
  end
end

function Net.Join(attempt)
  attempt = attempt or 1
  local name = Net.ChannelName()
  if not name then Net.status = "no faction" return end
  if Net.Index() then return ready(name) end
  Net.status = "joining"
  JoinTemporaryChannel(name)
  C_Timer.After(2, ns.Safe(function()
    if Net.Index() then
      ready(name)
    elseif attempt < Net.RETRIES then
      Net.Join(attempt + 1)
    else
      Net.status = "failed"
      ns.Update()
    end
  end))
end

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  if isLogin or isReload then
    C_Timer.After(Net.JOIN_DELAY, ns.Safe(function() Net.Join() end))
  end
end)

-- /sc net: is the network working?
function Net.Describe()
  if Net.status == "on" then
    return ("Network: on (channel %d, %s). Messages received this session: %d."):format(
      Net.Index() or 0, Net.Faction(), Net.received)
  elseif Net.status == "failed" then
    return "Network: couldn't join its chat channel. Are all 10 channel slots in use? (/chatlist) Type /reload to try again."
  elseif Net.status == "no faction" then
    return "Network: off until you pick a faction."
  elseif Net.status == "joining" then
    return "Network: joining..."
  end
  return ("Network: starts %d seconds after login."):format(Net.JOIN_DELAY)
end
