-- The advertising panel: channel names, the Listen box, the ad text.
C_Club = {
  GetClubInfo = function(id)
    if id == "504777831" then return { name = "Summoners Guild" } end
    if id == "504847031" then return { name = "Warlock Pals" } end
  end,
  GetStreamInfo = function(club, stream)
    if club == "504847031" and stream == "2" then return { name = "Trading", streamType = 3 } end
    return { name = "General", streamType = 0 }
  end,
}
local CHANNELS = { 1, "General - Undercity", false, 2, "Trade - City", false,
  6, "Community:504777831:1", false, 7, "Community:504847031:2", false, 8, "Community:505014201:1", false }
function GetChannelList() return unpack(CHANNELS) end
Boot()
local A = ns.Advertise

local labels = {}
for _, ch in ipairs(A.JoinedChannels()) do labels[ch.id] = ch.label end
eq("label: normal channel", labels[2], "Trade - City")
eq("label: community", labels[6], "Summoners Guild")
eq("label: community, other stream", labels[7], "Warlock Pals - Trading")
eq("label: unknown community keeps its raw name", labels[8], "Community:505014201:1")
C_Club.GetClubInfo = function() error("boom") end
eq("label: game error falls back", A.ChannelLabel("Community:504777831:1"), "Community:504777831:1")

UI = ns.UI
UI.TogglePanel("ad")
local p = UI.panels.ad.frame
check("panel opens", p:IsShown())
eq("panel: shows the community name", p.checks[3].label:GetText(), "6. Community:504777831:1")
-- (the C_Club error above makes this one fall back; restore and refresh)
C_Club.GetClubInfo = function(id) if id == "504777831" then return { name = "Summoners Guild" } end end
ns.Update()
eq("panel: community name after refresh", p.checks[3].label:GetText(), "6. Summoners Guild")

check("listen: on when a channel is ticked (Trade by default)", p.read:IsEnabled() and p.read:GetChecked())
A.SetChannel("Trade - City", false)
ns.Update()
check("listen: greyed out with no channel ticked", not p.read:IsEnabled() and not p.read:GetChecked())
check("listen: hint says what to do", p.readHint:GetText():find("Tick a channel") ~= nil)
check("listen: the setting itself is kept", ns.db.readRequests ~= false)
A.SetChannel("Trade - City", true)
ns.Update()
check("listen: back on", p.read:IsEnabled() and p.read:GetChecked())

-- {queue} is its own piece of text.
ns.S.active = true
eq("ad text: empty queue", A.Text(), "WTS summons to Undercity - 30s - whisper 'inv' for instant invite - no wait!")
ns.S.queue["Bob Smith"] = { name = "Bob Smith", status = "GROUP", added = 1 }
eq("ad text: with a queue", A.Text(), "WTS summons to Undercity - 30s - whisper 'inv' for instant invite - 1 in queue")
